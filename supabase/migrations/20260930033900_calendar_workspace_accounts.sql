-- Additive account and calendar contracts; existing clients and booking references keep their IDs.
alter table public.calendar_connections add column provider_subject text;
create unique index calendar_provider_identity on public.calendar_connections(user_id,provider,provider_subject) where provider_subject is not null;
alter table public.calendar_sources add column blocks_availability boolean not null default false;
alter table public.calendar_sources add column meeting_suggestions boolean not null default false;
update public.calendar_sources set blocks_availability = selected, meeting_suggestions = selected;
grant update (blocks_availability,meeting_suggestions) on public.calendar_sources to authenticated;
alter table public.calendar_events add column details jsonb not null default '{}'::jsonb;

create table public.calendar_ranges (
 connection_id uuid not null,
 calendar_id text not null,
 user_id uuid not null references auth.users(id) on delete cascade,
 starts_at timestamptz not null,
 ends_at timestamptz not null check (ends_at > starts_at),
 refreshed_at timestamptz not null default now(),
 primary key (connection_id,calendar_id,starts_at,ends_at),
 foreign key (connection_id,calendar_id) references public.calendar_sources(connection_id,calendar_id) on delete cascade
);
alter table public.calendar_ranges enable row level security;
revoke all on public.calendar_ranges from anon,authenticated;
grant select on public.calendar_ranges to authenticated;
grant all on public.calendar_ranges to service_role;
create policy "Read calendar coverage" on public.calendar_ranges for select to authenticated using ((select auth.uid()) = user_id);

-- A complete range commits atomically. A failed or incomplete provider page never clears the cache.
create function public.merge_calendar_range(p_connection_id uuid,p_calendar_id text,p_start timestamptz,p_end timestamptz,p_events jsonb)
returns void language plpgsql security invoker set search_path = '' as $$
declare owner uuid;
begin
 select user_id into owner from public.calendar_sources where connection_id = p_connection_id and calendar_id = p_calendar_id;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_connection_id::text || ':' || p_calendar_id, 0));
 if owner is null or p_end <= p_start then raise exception 'Invalid calendar range' using errcode='22023'; end if;
 delete from public.calendar_events where connection_id=p_connection_id and calendar_id=p_calendar_id and ends_at>p_start and starts_at<p_end;
 insert into public.calendar_events(user_id,connection_id,calendar_id,id,ical_uid,title,starts_at,ends_at,meeting_url,attendees,details)
 select owner,p_connection_id,p_calendar_id,e->>'id',e->>'ical_uid',e->>'title',(e->>'starts_at')::timestamptz,(e->>'ends_at')::timestamptz,e->>'meeting_url',coalesce(e->'attendees','[]'::jsonb),coalesce(e->'details','{}'::jsonb)
 from jsonb_array_elements(p_events) e
 on conflict (connection_id,calendar_id,id) do update set ical_uid=excluded.ical_uid,title=excluded.title,starts_at=excluded.starts_at,ends_at=excluded.ends_at,meeting_url=excluded.meeting_url,attendees=excluded.attendees,details=excluded.details;
 insert into public.calendar_ranges(connection_id,calendar_id,user_id,starts_at,ends_at,refreshed_at)
 values(p_connection_id,p_calendar_id,owner,p_start,p_end,now())
 on conflict (connection_id,calendar_id,starts_at,ends_at) do update set refreshed_at=excluded.refreshed_at;
end;
$$;
revoke all on function public.merge_calendar_range(uuid,text,timestamptz,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.merge_calendar_range(uuid,text,timestamptz,timestamptz,jsonb) to service_role;
