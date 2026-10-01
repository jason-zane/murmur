begin;
-- Synthetic, rollback-only rows. No token issuance, credentials or provider calls.
insert into auth.users(id,aud,role,email) values
 ('f1000000-0000-4000-8000-000000000001','authenticated','authenticated','follow-up-owner@example.invalid'),
 ('f1000000-0000-4000-8000-000000000002','authenticated','authenticated','follow-up-other@example.invalid');
insert into public.first_party_clients(client_id,label) values ('concourse-follow-up-test-native','Synthetic native client');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$
declare
 note jsonb := '{"session":{"id":"follow-up-synthetic-qa","title":"Synthetic pilot","startedAt":"2026-10-01T00:00:00Z","state":"noted"},"note":"## Decisions\nStart a small pilot.\n## Private notes\nDo not share this.","transcript":[{"id":"line-1","text":"Sam will send the checklist."}],"bullets":[{"id":"bullet-1","text":"Confirm the date."}]}'::jsonb;
 draft jsonb := '{"sourceVersion":1,"recipe":"meeting-follow-up/v1","fields":{"recipient":"sam@","subject":"Pilot follow-up","body":"Start a small pilot."},"evidence":[{"kind":"note","id":"note","text":"Start a small pilot."},{"kind":"transcript","id":"line-1","text":"Sam will send the checklist."},{"kind":"bullet","id":"bullet-1","text":"Confirm the date."}],"unknowns":["Recipient and target date are missing."],"reviewed":false}'::jsonb;
 saved jsonb;
 revised jsonb;
 bad jsonb;
 i integer;
begin
 perform public.put_session(note,0,false);
 if public.get_follow_up_draft('follow-up-synthetic-qa')->'draft' <> 'null'::jsonb then raise exception 'Empty draft incorrect'; end if;
 saved := public.put_follow_up_draft('follow-up-synthetic-qa',draft,0);
 if saved->>'version' <> '1' or saved ? 'user_id' or saved->'document'->'fields'->>'recipient' <> 'sam@' then raise exception 'Initial draft or owner exposure'; end if;
 if public.put_follow_up_draft('follow-up-synthetic-qa',draft,0)->>'version' <> '1' then raise exception 'Duplicate create'; end if;
 if (select count(*) from public.follow_up_drafts where session_id='follow-up-synthetic-qa') <> 1 then raise exception 'Duplicate row'; end if;
 revised := jsonb_set(draft,'{fields,body}','"My edited wording"');
 if public.put_follow_up_draft('follow-up-synthetic-qa',revised,1)->>'version' <> '2' then raise exception 'Edit not saved'; end if;
 if public.put_follow_up_draft('follow-up-synthetic-qa',revised,1)->>'version' <> '2' then raise exception 'Lost-response retry incremented'; end if;
 begin
   perform public.put_follow_up_draft('follow-up-synthetic-qa',draft,1);
   raise exception 'Stale overwrite';
 exception when sqlstate 'PT409' then null; end;
 if public.get_follow_up_draft('follow-up-synthetic-qa')->'draft'->'document'->'fields'->>'body' <> 'My edited wording' then raise exception 'Stale edit replaced wording'; end if;
 for i in 1..11 loop
   bad := case i
    when 1 then draft || '{"owner":"f1000000-0000-4000-8000-000000000002"}'::jsonb
    when 2 then jsonb_set(draft,'{fields,send}','true')
    when 3 then jsonb_set(draft,'{reviewed}','true')
    when 4 then jsonb_set(draft,'{evidence,0,text}','"Invented decision"')
    when 5 then jsonb_set(draft,'{evidence,1,id}','"another-note-line"')
    when 6 then jsonb_set(draft,'{fields,subject}',to_jsonb(E'Header\nBcc: outsider@example.invalid'::text))
    when 7 then jsonb_set(draft,'{evidence}',draft->'evidence' || jsonb_build_array(draft->'evidence'->0))
    when 8 then jsonb_set(draft,'{fields,body}',to_jsonb(repeat('x',10001)))
    when 9 then jsonb_set(draft,'{fields,recipient}','"sam@example.invalid,other@example.invalid"') || '{"reviewed":true,"unknowns":[]}'::jsonb
    when 10 then jsonb_set(draft,'{sourceVersion}','null')
    when 11 then jsonb_set(draft,'{evidence,0,kind}','"external"') end;
   begin
     perform public.put_follow_up_draft('follow-up-synthetic-qa',bad,2);
     raise exception 'Invalid draft accepted: %',i;
   exception when invalid_parameter_value then null; end;
 end loop;
 begin
   update public.follow_up_drafts set document=draft where session_id='follow-up-synthetic-qa';
   raise exception 'Direct update bypass';
 exception when insufficient_privilege then null; end;
 begin
   insert into public.follow_up_drafts(user_id,session_id,document) values('f1000000-0000-4000-8000-000000000001','follow-up-synthetic-qa',draft);
   raise exception 'Direct insert bypass';
 exception when insufficient_privilege then null; end;
 begin
   delete from public.follow_up_drafts where session_id='follow-up-synthetic-qa';
   raise exception 'Direct delete bypass';
 exception when insufficient_privilege then null; end;

 perform set_config('request.jwt.claims','{"sub":"f1000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
 if exists(select 1 from public.follow_up_drafts) or public.get_follow_up_draft('follow-up-synthetic-qa') is not null then raise exception 'Cross-owner leak'; end if;
 begin
   perform public.put_follow_up_draft('follow-up-synthetic-qa',draft,0);
   raise exception 'Cross-owner save';
 exception when sqlstate 'PT404' then null; end;

 perform set_config('request.jwt.claims','{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated","client_id":"unapproved-ai-app"}',true);
 if exists(select 1 from public.follow_up_drafts) or public.get_follow_up_draft('follow-up-synthetic-qa') is not null then raise exception 'AI draft leak'; end if;
 begin
   perform public.put_follow_up_draft('follow-up-synthetic-qa',draft,2);
   raise exception 'AI wrote draft';
 exception when insufficient_privilege then null; end;
 -- Private helper must enforce the same boundary even if called directly in SQL.
 begin
   perform concourse_private.put_follow_up_draft('follow-up-synthetic-qa',draft,2);
   raise exception 'AI private helper bypass';
 exception when insufficient_privilege then null; end;

 perform set_config('request.jwt.claims','{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated","client_id":"concourse-follow-up-test-native"}',true);
 revised := jsonb_set(revised,'{fields,recipient}','"sam@example.invalid"') || '{"unknowns":[],"reviewed":true}'::jsonb;
 saved := public.put_follow_up_draft('follow-up-synthetic-qa',revised,2);
 if saved->>'version' <> '3' or saved->'document'->>'reviewed' <> 'true' then raise exception 'Approved native client cannot review'; end if;
 note := jsonb_set(note,'{note}','"## Decisions\nPause the pilot."');
 perform public.put_session(note,1,false);
 if public.get_follow_up_draft('follow-up-synthetic-qa')->>'sourceVersion' <> '2' then raise exception 'Source snapshot stale'; end if;
 begin
   perform public.put_follow_up_draft('follow-up-synthetic-qa',revised,3);
   raise exception 'Old approval accepted after source changed';
 exception when sqlstate 'PT409' then null; end;
 -- An old reviewed record remains recoverable; the API invalidates its effective approval.
 if public.get_follow_up_draft('follow-up-synthetic-qa')->'draft'->'document'->'fields'->>'body' <> 'My edited wording' then raise exception 'Source change lost edits'; end if;
 revised := revised || '{"sourceVersion":2,"reviewed":false,"evidence":[{"kind":"note","id":"note","text":"Pause the pilot."}]}'::jsonb;
 perform public.put_follow_up_draft('follow-up-synthetic-qa',revised,3);
 perform public.put_session(note,2,true);
 if public.get_follow_up_draft('follow-up-synthetic-qa') is not null then raise exception 'Deleted source readable'; end if;
 if exists(select 1 from public.follow_up_drafts where session_id='follow-up-synthetic-qa') then raise exception 'Deleted source direct read'; end if;
 begin
   perform public.put_follow_up_draft('follow-up-synthetic-qa',revised,4);
   raise exception 'Deleted source writable';
 exception when sqlstate 'PT404' then null; end;
 if (select count(*) from public.booking_messages where user_id='f1000000-0000-4000-8000-000000000001') <> 0
   or (select count(*) from public.mail_outbox where user_id='f1000000-0000-4000-8000-000000000001') <> 0 then raise exception 'Dispatch side effect'; end if;
end $$;
-- Exercise the table grants that bypass put_session: the trigger must make each
-- material owner write a new source revision, regardless of a supplied version.
do $$
declare
 note jsonb := '{"session":{"id":"follow-up-direct-source-qa","title":"Direct-write QA","startedAt":"2026-10-01T00:00:00Z","state":"noted"},"note":"Confirmed checklist.","transcript":[],"bullets":[]}'::jsonb;
 draft jsonb := '{"sourceVersion":1,"recipe":"meeting-follow-up/v1","fields":{"recipient":"sam@example.invalid","subject":"Checklist","body":"Confirmed checklist."},"evidence":[{"kind":"note","id":"note","text":"Confirmed checklist."}],"unknowns":[],"reviewed":true}'::jsonb;
 changed jsonb;
 saved jsonb;
 source_version bigint;
begin
 insert into public.sessions(user_id,id,document,title,started_at,version)
 values(auth.uid(),'follow-up-direct-source-qa',note,'Direct-write QA','2026-10-01T00:00:00Z',123);
 if (select version from public.sessions where id='follow-up-direct-source-qa') <> 1 then raise exception 'Insert controls source revision'; end if;
 saved := public.put_follow_up_draft('follow-up-direct-source-qa',draft,0);
 changed := jsonb_set(note,'{note}','"Changed checklist."');
 update public.sessions set document=changed,version=1 where id='follow-up-direct-source-qa';
 if public.get_follow_up_draft('follow-up-direct-source-qa')->>'sourceVersion' <> '2' then raise exception 'Direct write reused reviewed source version'; end if;
 begin
   perform public.put_follow_up_draft('follow-up-direct-source-qa',draft,1);
   raise exception 'Direct write revived approval';
 exception when sqlstate 'PT409' then null; end;
 if public.get_follow_up_draft('follow-up-direct-source-qa')->'draft'->'document'->'fields'->>'body' <> 'Confirmed checklist.' then raise exception 'Direct write lost saved wording'; end if;
 update public.sessions set document=note,version=1 where id='follow-up-direct-source-qa';
 if (select version from public.sessions where id='follow-up-direct-source-qa') <> 3 then raise exception 'Content revert revived old approval'; end if;
 update public.sessions set version=999,updated_at=now() where id='follow-up-direct-source-qa';
 if (select version from public.sessions where id='follow-up-direct-source-qa') <> 3 then raise exception 'Version-only write tampered with source revision'; end if;
 update public.sessions set title='Retitled' where id='follow-up-direct-source-qa';
 update public.sessions set started_at='2026-10-02T00:00:00Z' where id='follow-up-direct-source-qa';
 update public.sessions set deleted_at=now() where id='follow-up-direct-source-qa';
 if public.get_follow_up_draft('follow-up-direct-source-qa') is not null then raise exception 'Direct soft delete readable'; end if;
 update public.sessions set deleted_at=null,version=1 where id='follow-up-direct-source-qa';
 if (select version from public.sessions where id='follow-up-direct-source-qa') <> 7 then raise exception 'Metadata/delete/restore did not advance revision'; end if;
 insert into public.sessions(user_id,id,document,title,started_at,version)
 values(auth.uid(),'follow-up-direct-source-qa',changed,'Direct-write QA','2026-10-01T00:00:00Z',1)
 on conflict(user_id,id) do update set document=excluded.document,version=excluded.version;
 if (select version from public.sessions where id='follow-up-direct-source-qa') <> 8 then raise exception 'Upsert bypassed revision boundary'; end if;
 if (public.put_session(note,8,false)).version <> 9 then raise exception 'Normal note write double incremented'; end if;
 if (public.put_session(note,8,false)).version <> 9 then raise exception 'Normal retry changed revision'; end if;
 begin
   update public.sessions set id='follow-up-moved-qa',document=jsonb_set(note,'{session,id}','"follow-up-moved-qa"') where id='follow-up-direct-source-qa';
   raise exception 'Note identity moved away from lineage';
 exception when invalid_parameter_value then null; end;
 if has_function_privilege('authenticated','concourse_private.enforce_session_revision()','EXECUTE') then raise exception 'Client can execute revision helper'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
 if has_table_privilege('anon','public.follow_up_drafts','SELECT') or has_function_privilege('anon','public.put_follow_up_draft(text,jsonb,bigint)','EXECUTE')
    or has_schema_privilege('anon','concourse_private','USAGE') then raise exception 'Anonymous access'; end if;
 begin
  perform public.get_follow_up_draft('follow-up-synthetic-qa');
  raise exception 'Anonymous read';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
 if (select prosecdef from pg_proc where oid='concourse_private.enforce_session_revision()'::regprocedure)
    or (select proconfig from pg_proc where oid='concourse_private.enforce_session_revision()'::regprocedure) <> array['search_path=""']
    or (select prosecdef from pg_proc where oid='public.put_follow_up_draft(text,jsonb,bigint)'::regprocedure)
    or not (select prosecdef from pg_proc where oid='concourse_private.put_follow_up_draft(text,jsonb,bigint)'::regprocedure)
    or (select proconfig from pg_proc where oid='concourse_private.put_follow_up_draft(text,jsonb,bigint)'::regprocedure) <> array['search_path=""']
    then raise exception 'Privileged function boundary drift'; end if;
end $$;
select 'PASS: follow-up owner/editor isolation, direct-write denial, exact lineage, incomplete drafts, explicit review, version conflicts, idempotent retries, source changes through RPC/direct update/upsert/revert/metadata/delete/restore, trigger privilege boundary, native/AI boundaries and no dispatch' as result;
rollback;
