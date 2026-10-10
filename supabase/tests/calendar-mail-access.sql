begin;
-- Disposable, rollback-only fixtures; no connected account or email delivery is used.
insert into auth.users(id,aud,role,email) values
 ('00000000-0000-4000-8000-000000000061','authenticated','authenticated','calendar-mail-one@example.invalid'),
 ('00000000-0000-4000-8000-000000000062','authenticated','authenticated','calendar-mail-two@example.invalid');
insert into public.calendar_connections(id,user_id,email,scopes) values
 ('00000000-0000-4000-8000-0000000000e1','00000000-0000-4000-8000-000000000061','mail@example.invalid','{}');
insert into public.calendar_sources(connection_id,user_id,calendar_id,name,selected,blocks_availability,meeting_suggestions) values
 ('00000000-0000-4000-8000-0000000000e1','00000000-0000-4000-8000-000000000061','primary','Work',true,true,true);
insert into public.mail_outbox(id,user_id,connection_id,raw_message,subject) values
 ('00000000-0000-4000-8000-0000000000f1','00000000-0000-4000-8000-000000000061','00000000-0000-4000-8000-0000000000e1','encrypted-fixture','Private mail');
select public.merge_calendar_range('00000000-0000-4000-8000-0000000000e1','primary','2025-01-01Z','2025-02-01Z',
 '[{"id":"historic","title":"History","starts_at":"2025-01-10T00:00:00Z","ends_at":"2025-01-10T01:00:00Z"}]');
select public.merge_calendar_range('00000000-0000-4000-8000-0000000000e1','primary','2026-01-01Z','2026-02-01Z',
 '[{"id":"current","title":"Current","starts_at":"2026-01-10T00:00:00Z","ends_at":"2026-01-10T01:00:00Z"}]');
select public.merge_calendar_range('00000000-0000-4000-8000-0000000000e1','primary','2026-01-01Z','2026-02-01Z','[]');
do $$ begin
 if not exists(select 1 from public.calendar_events where id='historic') then raise exception 'Another range lost history'; end if;
 if exists(select 1 from public.calendar_events where id='current') then raise exception 'Deleted provider event survived reconciliation'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000061","role":"authenticated"}',true);
update public.calendar_sources set selected=false where connection_id='00000000-0000-4000-8000-0000000000e1';
do $$ begin
 if not exists(select 1 from public.mail_outbox) then raise exception 'Owner cannot read outbox'; end if;
 if not exists(select 1 from public.calendar_sources where not selected and blocks_availability and meeting_suggestions) then raise exception 'Display preference changed availability'; end if;
 begin
  update public.mail_outbox set status='sent';
  raise exception 'Client bypassed delivery service';
 exception when insufficient_privilege then null; end;
 begin
  perform public.merge_calendar_range('00000000-0000-4000-8000-0000000000e1','primary','2026-01-01Z','2026-02-01Z','[]');
  raise exception 'Client replaced provider cache';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000062","role":"authenticated"}',true);
do $$ begin
 if exists(select 1 from public.mail_outbox) or exists(select 1 from public.calendar_ranges) then raise exception 'Cross-user metadata leak'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000061","role":"authenticated","client_id":"third-party-test"}',true);
do $$ begin
 if exists(select 1 from public.mail_outbox) or exists(select 1 from public.mail_preferences) then raise exception 'Mailbox accessible with notes-only MCP grant'; end if;
end $$;
reset role;
insert into public.calendar_jobs(id,job_key,user_id,connection_id,calendar_id,kind,starts_at,ends_at,status,lease,staged,page_token) values
 ('00000000-0000-4000-8000-0000000000f2','fixture-job','00000000-0000-4000-8000-000000000061','00000000-0000-4000-8000-0000000000e1','primary','range','2026-01-01Z','2026-02-01Z','running','00000000-0000-4000-8000-0000000000f3','{"first-page":{"id":"page-one"}}','page-two');
do $$ begin
 if public.commit_calendar_job('00000000-0000-4000-8000-0000000000f2','00000000-0000-4000-8000-0000000000f4','[]') then raise exception 'Expired worker committed a range'; end if;
 if not exists(select 1 from public.calendar_jobs where page_token='page-two' and staged ? 'first-page') then raise exception 'Interrupted page checkpoint lost'; end if;
 if not public.commit_calendar_job('00000000-0000-4000-8000-0000000000f2','00000000-0000-4000-8000-0000000000f3','[{"id":"page-one","title":"Complete page","starts_at":"2026-01-10T00:00:00Z","ends_at":"2026-01-10T01:00:00Z"}]') then raise exception 'Current worker could not commit'; end if;
 if not exists(select 1 from public.calendar_jobs where status='complete' and staged='{}' and page_token is null) then raise exception 'Commit did not clear staging'; end if;
 if not exists(select 1 from public.calendar_events where id='historic') or not exists(select 1 from public.calendar_events where id='page-one') then raise exception 'Job lost unrelated history or its new range'; end if;
end $$;
set local role authenticated;
do $$ begin
 if has_table_privilege('authenticated','public.calendar_jobs','SELECT') then raise exception 'Private provider checkpoints exposed'; end if;
end $$;
reset role;
-- Notification registration is account-owned and claims cannot race the same source.
do $$ declare channel public.calendar_push_channels; begin
 select * into channel from public.claim_calendar_channel('00000000-0000-4000-8000-000000000061','00000000-0000-4000-8000-0000000000f6','synthetic-channel-secret');
 if channel.user_id<>'00000000-0000-4000-8000-000000000061' or channel.calendar_id<>'primary' then raise exception 'Notification ownership lost'; end if;
 if exists(select 1 from public.claim_calendar_channel('00000000-0000-4000-8000-000000000061','00000000-0000-4000-8000-0000000000f7','another-secret')) then raise exception 'Same source claimed twice'; end if;
end $$;
-- A worker crash before watch registration cannot hide an unwatched source for a week.
update public.calendar_push_channels set retry_after=now()-interval '1 minute' where id='00000000-0000-4000-8000-0000000000f6';
do $$ begin
 if not exists(select 1 from public.claim_calendar_channel('00000000-0000-4000-8000-000000000061','00000000-0000-4000-8000-0000000000f8','recovered-secret') where id='00000000-0000-4000-8000-0000000000f8') then raise exception 'Interrupted watch registration did not recover'; end if;
end $$;
update public.calendar_jobs set status='running',lease='00000000-0000-4000-8000-0000000000f3',dirty=true where job_key='fixture-job';
do $$ begin
 if not public.commit_calendar_job('00000000-0000-4000-8000-0000000000f2','00000000-0000-4000-8000-0000000000f3','[]') then raise exception 'Dirty job did not commit'; end if;
 if not exists(select 1 from public.calendar_jobs where job_key='fixture-job' and status='queued' and not dirty and staged='{}' and page_token is null) then raise exception 'Notification during fetch did not trigger a fresh pass'; end if;
end $$;
update public.calendar_jobs set status='complete',updated_at=now()-interval '1 hour' where job_key='fixture-job';
select public.queue_calendar_reconciliation('00000000-0000-4000-8000-000000000061');
do $$ begin
 if not exists(select 1 from public.calendar_jobs where job_key='fixture-job' and status='queued') then raise exception 'Missed notification left stale coverage'; end if;
end $$;
set local role authenticated;
do $$ begin
 if has_table_privilege('authenticated','public.calendar_push_channels','SELECT') or has_function_privilege('authenticated','public.claim_calendar_channel(uuid,uuid,text)','EXECUTE') then raise exception 'Notification verification secrets exposed'; end if;
end $$;
reset role;
-- Undo can precede a delayed send request; the operation remains cancelled.
insert into public.mail_outbox(id,user_id,connection_id,raw_message,status) values
 ('00000000-0000-4000-8000-0000000000f5','00000000-0000-4000-8000-000000000061','00000000-0000-4000-8000-0000000000e1','','cancelled') on conflict(id) do nothing;
insert into public.mail_outbox(id,user_id,connection_id,raw_message,status) values
 ('00000000-0000-4000-8000-0000000000f5','00000000-0000-4000-8000-000000000061','00000000-0000-4000-8000-0000000000e1','delayed MIME','queued') on conflict(id) do nothing;
update public.mail_outbox set status='sending' where id='00000000-0000-4000-8000-0000000000f5' and status='queued';
do $$ begin
 if not exists(select 1 from public.mail_outbox where id='00000000-0000-4000-8000-0000000000f5' and status='cancelled' and raw_message='') then raise exception 'Delayed queue resurrected an undone send'; end if;
end $$;
select 'PASS: range preservation, deletions, separate preferences, owner isolation and no third-party mail access' as result;
rollback;
