begin;
create table public.availability_schedules (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(length(name) between 1 and 120),
 time_zone text not null,
 weekly_hours jsonb not null default '[]',
 date_overrides jsonb not null default '[]',
 created_at timestamptz not null default now(),
 unique(user_id,name), unique(id,user_id)
);
alter table public.availability_schedules enable row level security;
revoke all on public.availability_schedules from anon,authenticated;
grant select on public.availability_schedules to authenticated;
grant all on public.availability_schedules to service_role;
create policy "Read your availability schedules" on public.availability_schedules for select to authenticated using(user_id=(select auth.uid()));
alter table public.event_types add column availability_schedule_id uuid;
alter table public.event_types add column availability_override jsonb;
alter table public.event_types add column destination_connection_id uuid references public.calendar_connections(id) on delete set null;
alter table public.event_types add column destination_calendar_id text;
alter table public.event_types add column email_connection_id uuid references public.calendar_connections(id) on delete set null;
alter table public.event_types add constraint event_schedule_owner foreign key(availability_schedule_id,user_id) references public.availability_schedules(id,user_id);
alter table public.event_types add constraint event_availability_mode check(availability_schedule_id is null or availability_override is null);
create index event_types_availability_schedule on public.event_types(availability_schedule_id);
-- Enforce ownership even for direct authenticated table writes.
alter table public.calendar_connections add constraint calendar_connection_owner_key unique(id,user_id);
alter table public.event_types add constraint event_destination_owner foreign key(destination_connection_id,user_id)
 references public.calendar_connections(id,user_id) on delete set null (destination_connection_id);
alter table public.event_types add constraint event_email_owner foreign key(email_connection_id,user_id)
 references public.calendar_connections(id,user_id) on delete set null (email_connection_id);
commit;
