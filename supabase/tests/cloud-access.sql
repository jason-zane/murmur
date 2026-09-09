begin;
-- All fixtures are rolled back, including Auth users. No real account is touched.
insert into auth.users(id, aud, role, email) values
 ('00000000-0000-4000-8000-000000000001','authenticated','authenticated','murmur-test-one@example.invalid'),
 ('00000000-0000-4000-8000-000000000002','authenticated','authenticated','murmur-test-two@example.invalid');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.put_session('{"session":{"id":"qa-note","title":"Private fixture","startedAt":"2026-09-09T00:00:00Z","state":"noted"},"note":"Original source","transcript":[],"bullets":[]}'::jsonb,0,false);
-- Replaying a request after a lost response is idempotent.
select public.put_session('{"session":{"id":"qa-note","title":"Private fixture","startedAt":"2026-09-09T00:00:00Z","state":"noted"},"note":"Original source","transcript":[],"bullets":[]}'::jsonb,0,false);
do $$ begin
  if (select version from public.sessions where id='qa-note') <> 1 then raise exception 'Idempotency failed'; end if;
end $$;
select public.put_session('{"session":{"id":"qa-note","title":"Private fixture","startedAt":"2026-09-09T00:00:00Z","state":"noted"},"note":"Revised source","transcript":[],"bullets":[]}'::jsonb,1,false);
do $$ begin
  if (select count(*) from public.session_revisions where session_id='qa-note') <> 1 then raise exception 'Revision lost'; end if;
  begin
    perform public.put_session('{"session":{"id":"qa-note","title":"Private fixture","startedAt":"2026-09-09T00:00:00Z","state":"noted"},"note":"Stale overwrite","transcript":[],"bullets":[]}'::jsonb,1,false);
    raise exception 'Stale write was accepted';
  exception when sqlstate 'PT409' then null;
  end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ begin
  if exists(select 1 from public.sessions) or exists(select 1 from public.session_revisions) then raise exception 'Cross-account leak'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","client_id":"third-party-test"}',true);
do $$ begin
  if not exists(select 1 from public.sessions where id='qa-note') then raise exception 'Authorized MCP cannot read'; end if;
  if public.is_murmur_editor() then raise exception 'MCP received editor permission'; end if;
  begin
    perform public.put_session('{"session":{"id":"qa-note","title":"Private fixture","startedAt":"2026-09-09T00:00:00Z","state":"noted"},"note":"Unapproved write","transcript":[],"bullets":[]}'::jsonb,2,false);
    raise exception 'MCP write succeeded';
  exception when insufficient_privilege then null;
  end;
  if has_table_privilege('authenticated','public.calendar_credentials','SELECT') then raise exception 'Calendar credential leak'; end if;
end $$;
reset role;
do $$ begin
  if public.murmur_access_token_hook('{"claims":{"client_id":"third-party-test","aud":"authenticated"}}')->'claims'->>'aud' <> 'https://murmur-rho-pied.vercel.app/mcp' then
    raise exception 'MCP audience is not bound';
  end if;
  if not has_table_privilege('service_role', 'public.first_party_clients', 'INSERT') or
     not has_table_privilege('service_role', 'public.calendar_credentials', 'INSERT') then
    raise exception 'Server cannot register the Mac or store Calendar credentials';
  end if;
end $$;
select 'PASS: owner isolation, MCP read-only, revision history, stale-write protection, idempotent retry and credential isolation' as result;
rollback;
