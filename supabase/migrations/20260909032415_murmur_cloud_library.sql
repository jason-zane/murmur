-- Murmur's own project only. Every exposed table is private by default.
create table public.first_party_clients (
  client_id text primary key,
  label text not null
);
alter table public.first_party_clients enable row level security;
create policy "Signed-in clients can identify the native app" on public.first_party_clients
  for select to authenticated using (true);
grant select on public.first_party_clients to authenticated;
revoke all on public.first_party_clients from anon;

create function public.is_murmur_editor() returns boolean
language sql stable security invoker set search_path = '' as $$
  select (select auth.uid()) is not null and (
    (select auth.jwt()->>'client_id') is null or exists (
      select 1 from public.first_party_clients where client_id = (select auth.jwt()->>'client_id')
    )
  );
$$;
revoke execute on function public.is_murmur_editor() from public, anon;
grant execute on function public.is_murmur_editor() to authenticated;

create table public.sessions (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null check (id ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'),
  document jsonb not null check (jsonb_typeof(document) = 'object' and document->'session'->>'id' = id),
  title text not null,
  started_at timestamptz not null,
  version bigint not null default 1 check (version > 0),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id)
);
create index sessions_chronological on public.sessions(user_id, started_at desc, id);
alter table public.sessions enable row level security;
create policy "Read your library" on public.sessions for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Create your notes from Murmur" on public.sessions for insert to authenticated
  with check ((select auth.uid()) = user_id and (select public.is_murmur_editor()));
create policy "Edit your notes from Murmur" on public.sessions for update to authenticated
  using ((select auth.uid()) = user_id and (select public.is_murmur_editor()))
  with check ((select auth.uid()) = user_id and (select public.is_murmur_editor()));
grant select, insert, update on public.sessions to authenticated;
revoke all on public.sessions from anon;

create table public.session_revisions (
  user_id uuid not null,
  session_id text not null,
  version bigint not null,
  document jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_id, session_id, version),
  foreign key (user_id, session_id) references public.sessions(user_id, id) on delete cascade
);
alter table public.session_revisions enable row level security;
create policy "Read your history" on public.session_revisions for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Preserve your revisions" on public.session_revisions for insert to authenticated
  with check ((select auth.uid()) = user_id and (select public.is_murmur_editor()));
grant select, insert on public.session_revisions to authenticated;
revoke all on public.session_revisions from anon;

-- One transaction serializes each document, checks its version and preserves the old copy.
-- Equal retries return the existing row, including when a response was lost in transit.
create function public.put_session(p_document jsonb, p_expected_version bigint, p_deleted boolean default false)
returns public.sessions language plpgsql security invoker set search_path = '' as $$
declare
  owner uuid := (select auth.uid());
  session_id text := p_document->'session'->>'id';
  existing public.sessions;
  result public.sessions;
begin
  if owner is null or not public.is_murmur_editor() then
    raise exception 'Only your signed-in Murmur app can change notes' using errcode = '42501';
  end if;
  if session_id is null or session_id !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'
     or octet_length(p_document::text) > 8000000
     or p_document->'session'->>'state' not in ('raw','noted')
     or p_expected_version < 0 then
    raise exception 'Invalid or unfinished session' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(owner::text || ':' || session_id, 0));
  select * into existing from public.sessions where user_id = owner and id = session_id for update;
  if found then
    if existing.document = p_document and (existing.deleted_at is not null) = p_deleted then return existing; end if;
    if existing.version <> p_expected_version then
      raise exception 'The cloud copy changed. Reload before saving.' using errcode = '40001';
    end if;
    insert into public.session_revisions(user_id, session_id, version, document)
      values (owner, session_id, existing.version, existing.document) on conflict do nothing;
    update public.sessions set document = p_document, title = p_document->'session'->>'title',
      started_at = (p_document->'session'->>'startedAt')::timestamptz,
      version = existing.version + 1, updated_at = now(), deleted_at = case when p_deleted then now() else null end
      where user_id = owner and id = session_id returning * into result;
  else
    if p_expected_version <> 0 or p_deleted then
      raise exception 'The original cloud copy is missing' using errcode = '40001';
    end if;
    insert into public.sessions(user_id, id, document, title, started_at)
      values (owner, session_id, p_document, p_document->'session'->>'title',
        (p_document->'session'->>'startedAt')::timestamptz) returning * into result;
  end if;
  return result;
end;
$$;
revoke execute on function public.put_session(jsonb,bigint,boolean) from public, anon;
grant execute on function public.put_session(jsonb,bigint,boolean) to authenticated;

create table public.calendar_connections (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  updated_at timestamptz,
  error text
);
alter table public.calendar_connections enable row level security;
create policy "Read your calendar status" on public.calendar_connections for select to authenticated
  using ((select auth.uid()) = user_id);
grant select on public.calendar_connections to authenticated;
revoke all on public.calendar_connections from anon;

create table public.calendar_credentials (
  user_id uuid primary key references auth.users(id) on delete cascade,
  encrypted_refresh_token text not null,
  updated_at timestamptz not null default now()
);
alter table public.calendar_credentials enable row level security;
revoke all on public.calendar_credentials from anon, authenticated;

create table public.calendar_events (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  title text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  meeting_url text,
  attendees jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);
create index calendar_events_agenda on public.calendar_events(user_id, starts_at);
alter table public.calendar_events enable row level security;
create policy "Read your agenda" on public.calendar_events for select to authenticated
  using ((select auth.uid()) = user_id);
grant select on public.calendar_events to authenticated;
revoke all on public.calendar_events from anon;

-- Only the server can atomically replace a user's Google Calendar snapshot.
create function public.replace_calendar_events(p_user_id uuid, p_events jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  delete from public.calendar_events where user_id = p_user_id;
  insert into public.calendar_events(user_id,id,title,starts_at,ends_at,meeting_url,attendees)
    select p_user_id, value->>'id', value->>'title', (value->>'starts_at')::timestamptz,
      (value->>'ends_at')::timestamptz, value->>'meeting_url', value->'attendees'
      from jsonb_array_elements(p_events);
  update public.calendar_connections set updated_at = now(), error = null where user_id = p_user_id;
end;
$$;
revoke execute on function public.replace_calendar_events(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.replace_calendar_events(uuid,jsonb) to service_role;
