-- Unapplied migration: install the source revision boundary before creating drafts.
-- Existing owner INSERT/UPDATE grants remain intact, including PostgREST writes.
create schema concourse_private;
revoke all on schema concourse_private from public, anon, authenticated;
grant usage on schema concourse_private to authenticated;
alter default privileges in schema concourse_private revoke execute on functions from public;

create function concourse_private.enforce_session_revision()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if TG_OP = 'INSERT' then
    NEW.version := 1;
    return NEW;
  end if;
  if NEW.user_id is distinct from OLD.user_id or NEW.id is distinct from OLD.id then
    raise exception 'Note identity cannot change' using errcode = '22023';
  end if;
  if NEW.document is distinct from OLD.document or NEW.title is distinct from OLD.title
    or NEW.started_at is distinct from OLD.started_at or NEW.deleted_at is distinct from OLD.deleted_at then
    if OLD.version >= 9007199254740991 then
      raise exception 'Note revision limit reached' using errcode = '22023';
    end if;
    -- Assign once: put_session already requests this version; direct writes cannot
    -- reuse or reset it. Reverting content still creates a new revision.
    NEW.version := OLD.version + 1;
    NEW.updated_at := now();
  else
    NEW.version := OLD.version;
  end if;
  return NEW;
end;
$$;
revoke all on function concourse_private.enforce_session_revision() from public, anon, authenticated;
create trigger enforce_session_revision before insert or update on public.sessions
  for each row execute function concourse_private.enforce_session_revision();

-- Private, reviewable text drafts. No outbox, provider call or dispatch state.
create table public.follow_up_drafts (
  user_id uuid not null,
  session_id text not null,
  document jsonb not null check (jsonb_typeof(document) = 'object'),
  version bigint not null default 1 check (version > 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, session_id),
  foreign key (user_id, session_id) references public.sessions(user_id, id) on delete cascade
);
alter table public.follow_up_drafts enable row level security;
revoke all on public.follow_up_drafts from public, anon, authenticated;
grant select on public.follow_up_drafts to authenticated;
create policy "Read your follow-up drafts in Concourse" on public.follow_up_drafts
  for select to authenticated using ((select auth.uid()) = user_id and (select public.is_murmur_editor())
    and exists(select 1 from public.sessions s where s.user_id=(select auth.uid())
      and s.id=follow_up_drafts.session_id and s.deleted_at is null));

-- Direct INSERT/UPDATE is deliberately unavailable: it would bypass CAS/lineage.
-- The narrow privileged operation is outside exposed schemas, has no owner argument,
-- checks uid/editor itself, and uses an empty search_path with qualified relations.
create function concourse_private.put_follow_up_draft(p_session_id text, p_document jsonb, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  owner uuid := (select auth.uid());
  source public.sessions;
  existing public.follow_up_drafts;
  result public.follow_up_drafts;
  fields jsonb;
  span jsonb;
  quote text;
  matched boolean;
begin
  if owner is null or not public.is_murmur_editor() then
    raise exception 'Concourse sign-in required' using errcode = '42501';
  end if;
  if p_session_id is null or p_session_id !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'
    or p_expected_version is null or p_expected_version < 0 or p_expected_version > 9007199254740991
    or jsonb_typeof(p_document) is distinct from 'object' or octet_length(p_document::text) > 100000
    or not (p_document ?& array['sourceVersion','recipe','fields','evidence','unknowns','reviewed'])
    or p_document - array['sourceVersion','recipe','fields','evidence','unknowns','reviewed'] <> '{}'::jsonb
    or p_document->>'recipe' is distinct from 'meeting-follow-up/v1'
    or jsonb_typeof(p_document->'sourceVersion') is distinct from 'number'
    or p_document->>'sourceVersion' !~ '^[1-9][0-9]{0,15}$'
    or jsonb_typeof(p_document->'reviewed') is distinct from 'boolean'
    or jsonb_typeof(p_document->'fields') is distinct from 'object'
    or jsonb_typeof(p_document->'evidence') is distinct from 'array'
    or jsonb_typeof(p_document->'unknowns') is distinct from 'array' then
    raise exception 'Invalid follow-up draft' using errcode = '22023';
  end if;
  if (p_document->>'sourceVersion')::bigint > 9007199254740991 then
    raise exception 'Invalid source version' using errcode = '22023';
  end if;
  fields := p_document->'fields';
  if not (fields ?& array['recipient','subject','body']) or fields - array['recipient','subject','body'] <> '{}'::jsonb
    or jsonb_typeof(fields->'recipient') is distinct from 'string'
    or jsonb_typeof(fields->'subject') is distinct from 'string'
    or jsonb_typeof(fields->'body') is distinct from 'string'
    or length(fields->>'recipient') > 254 or length(fields->>'subject') > 200 or length(fields->>'body') > 10000
    or fields->>'subject' ~ E'[\r\n]'
    or fields->>'recipient' ~ E'[\r\n]'
    or jsonb_array_length(p_document->'evidence') > 30 or jsonb_array_length(p_document->'unknowns') > 20 then
    raise exception 'Invalid follow-up fields' using errcode = '22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_document->'unknowns') item
    where jsonb_typeof(item) <> 'string' or length(item #>> '{}') not between 1 and 500) then
    raise exception 'Invalid unresolved details' using errcode = '22023';
  end if;
  if (p_document->>'reviewed')::boolean and (fields->>'recipient' !~ '^(?!\.)(?!.*\.\.)([A-Za-z0-9_''+\-\.]*)[A-Za-z0-9_+-]@([A-Za-z0-9][A-Za-z0-9\-]*\.)+[A-Za-z]{2,}$' or btrim(fields->>'subject') = ''
    or btrim(fields->>'body') = '' or jsonb_array_length(p_document->'evidence') = 0
    or jsonb_array_length(p_document->'unknowns') <> 0) then
    raise exception 'Unresolved draft cannot be reviewed' using errcode = '22023';
  end if;

  -- Lock the source as well as the draft so a simultaneous note edit cannot validate
  -- evidence from one revision and save approval against a different revision.
  select * into source from public.sessions where user_id = owner and id = p_session_id for share;
  if not found or source.deleted_at is not null then
    raise exception 'Note unavailable' using errcode = 'PT404';
  end if;
  if source.version <> (p_document->>'sourceVersion')::bigint then
    raise exception 'Source note changed' using errcode = 'PT409';
  end if;
  for span in select value from jsonb_array_elements(p_document->'evidence') loop
    if jsonb_typeof(span) <> 'object' or not (span ?& array['kind','id','text'])
      or span - array['kind','id','text'] <> '{}'::jsonb
      or jsonb_typeof(span->'kind') is distinct from 'string' or span->>'kind' not in ('note','transcript','bullet')
      or jsonb_typeof(span->'id') is distinct from 'string' or length(span->>'id') not between 1 and 128
      or jsonb_typeof(span->'text') is distinct from 'string' or length(span->>'text') not between 1 and 2000
      or btrim(span->>'text') = '' then
      raise exception 'Invalid source evidence' using errcode = '22023';
    end if;
    quote := span->>'text';
    matched := case span->>'kind'
      when 'note' then span->>'id' = 'note' and strpos(coalesce(source.document->>'note',''), quote) > 0
      when 'transcript' then exists(select 1 from jsonb_array_elements(coalesce(source.document->'transcript','[]')) item
        where item->>'id' = span->>'id' and strpos(coalesce(item->>'text',''), quote) > 0)
      when 'bullet' then exists(select 1 from jsonb_array_elements(coalesce(source.document->'bullets','[]')) item
        where item->>'id' = span->>'id' and strpos(coalesce(item->>'text',''), quote) > 0)
      else false end;
    if not matched then raise exception 'Evidence does not match the note' using errcode = '22023'; end if;
  end loop;
  if (select count(*) from jsonb_array_elements(p_document->'evidence')) <>
    (select count(distinct value) from jsonb_array_elements(p_document->'evidence')) then
    raise exception 'Duplicate source evidence' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(owner::text || ':follow-up:' || p_session_id, 0));
  select * into existing from public.follow_up_drafts where user_id = owner and session_id = p_session_id for update;
  if found then
    if existing.document = p_document then
      return to_jsonb(existing) - 'user_id';
    end if;
    if existing.version <> p_expected_version then
      raise exception 'Draft changed on another device' using errcode = 'PT409';
    end if;
    update public.follow_up_drafts set document = p_document, version = existing.version + 1, updated_at = now()
      where user_id = owner and session_id = p_session_id returning * into result;
  else
    if p_expected_version <> 0 then raise exception 'Original draft missing' using errcode = 'PT409'; end if;
    insert into public.follow_up_drafts(user_id,session_id,document) values(owner,p_session_id,p_document) returning * into result;
  end if;
  return to_jsonb(result) - 'user_id';
end;
$$;
revoke all on function concourse_private.put_follow_up_draft(text,jsonb,bigint) from public, anon, authenticated;
grant execute on function concourse_private.put_follow_up_draft(text,jsonb,bigint) to authenticated;
create function public.put_follow_up_draft(p_session_id text, p_document jsonb, p_expected_version bigint)
returns jsonb language sql security invoker set search_path = '' as $$
  select concourse_private.put_follow_up_draft(p_session_id,p_document,p_expected_version);
$$;
revoke all on function public.put_follow_up_draft(text,jsonb,bigint) from public, anon;
grant execute on function public.put_follow_up_draft(text,jsonb,bigint) to authenticated;

-- One statement gives a consistent snapshot of the current note and saved draft.
create function public.get_follow_up_draft(p_session_id text) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('sourceVersion',s.version,'draft',case when d.session_id is null then null else to_jsonb(d) - 'user_id' end)
  from public.sessions s left join public.follow_up_drafts d on d.user_id=s.user_id and d.session_id=s.id
  where s.user_id=(select auth.uid()) and s.id=p_session_id and s.deleted_at is null and (select public.is_murmur_editor());
$$;
revoke all on function public.get_follow_up_draft(text) from public, anon;
grant execute on function public.get_follow_up_draft(text) to authenticated;
