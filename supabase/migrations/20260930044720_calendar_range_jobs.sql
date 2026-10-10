create table public.calendar_jobs (
 id uuid primary key default gen_random_uuid(),
 job_key text not null unique,
 user_id uuid not null references auth.users(id) on delete cascade,
 connection_id uuid not null,
 calendar_id text,
 kind text not null check(kind in ('discover','range')),
 starts_at timestamptz,
 ends_at timestamptz,
 status text not null default 'queued' check(status in ('queued','running','complete','failed')),
 staged jsonb not null default '{}'::jsonb,
 page_token text,
 lease uuid,
 attempts integer not null default 0,
 retry_after timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 error text,
 foreign key(connection_id,user_id) references public.calendar_connections(id,user_id) on delete cascade,
 foreign key(connection_id,calendar_id) references public.calendar_sources(connection_id,calendar_id) on delete cascade,
 check(kind='discover' or (calendar_id is not null and starts_at is not null and ends_at>starts_at))
);
create index calendar_jobs_due on public.calendar_jobs(retry_after) where status in ('queued','failed');
alter table public.calendar_jobs enable row level security;
revoke all on public.calendar_jobs from anon,authenticated;
grant all on public.calendar_jobs to service_role;
-- Provider staging and checkpoints are private. The first-party API returns coverage metadata.
create function public.commit_calendar_job(p_id uuid,p_lease uuid,p_events jsonb)
returns boolean language plpgsql security invoker set search_path='' as $$
declare job public.calendar_jobs;
begin
 select * into job from public.calendar_jobs where id=p_id and lease=p_lease and status='running' for update;
 if not found then return false; end if;
 perform public.merge_calendar_range(job.connection_id,job.calendar_id,job.starts_at,job.ends_at,p_events);
 update public.calendar_jobs set status='complete',staged='{}',page_token=null,lease=null,error=null,attempts=0,updated_at=now() where id=p_id;
 return true;
end;
$$;
revoke all on function public.commit_calendar_job(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.commit_calendar_job(uuid,uuid,jsonb) to service_role;
