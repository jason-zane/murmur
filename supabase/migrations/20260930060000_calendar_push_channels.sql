-- Push channels contain verification secrets and are never exposed to clients.
create table public.calendar_push_channels (
 connection_id uuid not null,
 calendar_id text not null,
 user_id uuid not null references auth.users(id) on delete cascade,
 id uuid not null unique,
 token text not null,
 resource_id text,
 expires_at timestamptz not null default now(),
 retry_after timestamptz not null default now(),
 error text,
 primary key(connection_id,calendar_id),
 foreign key(connection_id,user_id) references public.calendar_connections(id,user_id) on delete cascade,
 foreign key(connection_id,calendar_id) references public.calendar_sources(connection_id,calendar_id) on delete cascade
);
alter table public.calendar_push_channels enable row level security;
revoke all on public.calendar_push_channels from anon,authenticated;
grant all on public.calendar_push_channels to service_role;
alter table public.calendar_jobs add column dirty boolean not null default false;
-- Notifications arriving during a paginated fetch require another complete pass.
create or replace function public.commit_calendar_job(p_id uuid,p_lease uuid,p_events jsonb)
returns boolean language plpgsql security invoker set search_path='' as $$
declare job public.calendar_jobs;
begin
 select * into job from public.calendar_jobs where id=p_id and lease=p_lease and status='running' for update;
 if not found then return false; end if;
 perform public.merge_calendar_range(job.connection_id,job.calendar_id,job.starts_at,job.ends_at,p_events);
 update public.calendar_jobs set status=case when dirty then 'queued' else 'complete' end,
 staged='{}',page_token=null,lease=null,error=null,attempts=0,dirty=false,retry_after=now(),updated_at=now() where id=p_id;
 return true;
end;
$$;
-- Claim renewal atomically, without scanning calendars over the network.
create function public.claim_calendar_channel(p_owner uuid,p_id uuid,p_token text)
returns setof public.calendar_push_channels language plpgsql security invoker set search_path='' as $$
declare old public.calendar_push_channels;
begin
 insert into public.calendar_push_channels(connection_id,calendar_id,user_id,id,token)
 select s.connection_id,s.calendar_id,s.user_id,gen_random_uuid(),replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','')
 from public.calendar_sources s where (s.selected or s.meeting_suggestions) and (p_owner is null or s.user_id=p_owner)
 on conflict(connection_id,calendar_id) do nothing;
 select c.* into old from public.calendar_push_channels c join public.calendar_sources s using(connection_id,calendar_id)
 where (p_owner is null or c.user_id=p_owner) and (s.selected or s.meeting_suggestions)
 and (c.resource_id is null or c.expires_at<now()+interval '1 day') and c.retry_after<=now()
 order by c.expires_at for update of c skip locked limit 1;
 if not found then return; end if;
 return query update public.calendar_push_channels c set id=p_id,token=p_token,resource_id=null,
 expires_at=now()+interval '7 days',retry_after=now()+interval '5 minutes',error=null
 where c.id=old.id returning c.*;
end;
$$;
revoke all on function public.claim_calendar_channel(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.claim_calendar_channel(uuid,uuid,text) to service_role;
-- Missed/expired push channels cannot leave a closed client's cached ranges stale forever.
create function public.queue_calendar_reconciliation(p_owner uuid)
returns integer language plpgsql security invoker set search_path='' as $$
declare queued integer;
begin
 with due as (
  select j.id from public.calendar_jobs j join public.calendar_sources s using(connection_id,calendar_id)
  where j.kind='range' and j.status='complete' and j.updated_at<now()-interval '15 minutes'
  and (p_owner is null or j.user_id=p_owner) and (s.selected or s.meeting_suggestions)
  order by j.updated_at limit 100 for update of j skip locked
 ) update public.calendar_jobs j set status='queued',staged='{}',page_token=null,dirty=false,retry_after=now()
 from due where j.id=due.id;
 get diagnostics queued=row_count;
 return queued;
end;
$$;
revoke all on function public.queue_calendar_reconciliation(uuid) from public,anon,authenticated;
grant execute on function public.queue_calendar_reconciliation(uuid) to service_role;
