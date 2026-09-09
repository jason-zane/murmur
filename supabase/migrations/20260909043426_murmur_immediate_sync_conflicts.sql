-- An outdated document is an HTTP conflict, not a retryable SQL serialization failure.
-- PostgREST must return it immediately so the editor can preserve both versions.
create or replace function public.put_session(p_document jsonb, p_expected_version bigint, p_deleted boolean default false)
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
      raise exception 'The cloud copy changed. Reload before saving.' using errcode = 'PT409';
    end if;
    insert into public.session_revisions(user_id, session_id, version, document)
      values (owner, session_id, existing.version, existing.document) on conflict do nothing;
    update public.sessions set document = p_document, title = p_document->'session'->>'title',
      started_at = (p_document->'session'->>'startedAt')::timestamptz,
      version = existing.version + 1, updated_at = now(), deleted_at = case when p_deleted then now() else null end
      where user_id = owner and id = session_id returning * into result;
  else
    if p_expected_version <> 0 or p_deleted then
      raise exception 'The original cloud copy is missing' using errcode = 'PT409';
    end if;
    insert into public.sessions(user_id, id, document, title, started_at)
      values (owner, session_id, p_document, p_document->'session'->>'title',
        (p_document->'session'->>'startedAt')::timestamptz) returning * into result;
  end if;
  return result;
end;
$$;
