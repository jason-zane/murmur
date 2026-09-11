-- Several calendar accounts per person, which of their calendars count, and booking links.
-- Guests never read or write these tables: the web server validates each public request and
-- writes with the service role. People read their own rows; only Voice Notes' own apps edit.

create extension if not exists btree_gist with schema extensions;

-- Calendar accounts --------------------------------------------------------------------------
-- The existing single Google connection becomes the person's first account.
alter table public.calendar_connections add column id uuid not null default gen_random_uuid();
alter table public.calendar_connections add column provider text not null default 'google'
  check (provider in ('google'));
alter table public.calendar_connections add column scopes text[] not null default '{}';
alter table public.calendar_connections add column created_at timestamptz not null default now();
update public.calendar_connections
  set scopes = array['https://www.googleapis.com/auth/calendar.events.readonly'];
alter table public.calendar_connections drop constraint calendar_connections_pkey;
alter table public.calendar_connections add primary key (id);
create unique index calendar_connections_account
  on public.calendar_connections(user_id, provider, lower(email));
create index calendar_connections_owner on public.calendar_connections(user_id, created_at);

alter table public.calendar_credentials add column connection_id uuid;
update public.calendar_credentials c set connection_id = k.id
  from public.calendar_connections k where k.user_id = c.user_id;
delete from public.calendar_credentials where connection_id is null;
alter table public.calendar_credentials drop constraint calendar_credentials_pkey;
alter table public.calendar_credentials alter column connection_id set not null;
alter table public.calendar_credentials add primary key (connection_id);
alter table public.calendar_credentials add constraint calendar_credentials_connection
  foreign key (connection_id) references public.calendar_connections(id) on delete cascade;

-- The agenda is a cache. Clear it and force the next read to rebuild it per calendar.
delete from public.calendar_events;
alter table public.calendar_events drop constraint calendar_events_pkey;
alter table public.calendar_events add column connection_id uuid not null
  references public.calendar_connections(id) on delete cascade;
alter table public.calendar_events add column calendar_id text not null;
alter table public.calendar_events add column ical_uid text;
alter table public.calendar_events add primary key (connection_id, calendar_id, id);
update public.calendar_connections set updated_at = null;

-- Every calendar an account can see. Selected calendars appear in the agenda and block
-- booking times. People may change only that choice; names come from the provider.
create table public.calendar_sources (
  connection_id uuid not null references public.calendar_connections(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  calendar_id text not null check (length(calendar_id) between 1 and 1024),
  name text not null check (length(name) <= 500),
  time_zone text,
  color text,
  is_primary boolean not null default false,
  can_write boolean not null default false,
  selected boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (connection_id, calendar_id)
);
create index calendar_sources_owner on public.calendar_sources(user_id);
alter table public.calendar_sources enable row level security;
create policy "Read your calendars" on public.calendar_sources for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Choose your calendars" on public.calendar_sources for update to authenticated
  using ((select auth.uid()) = user_id and (select public.is_murmur_editor()))
  with check ((select auth.uid()) = user_id and (select public.is_murmur_editor()));
revoke all on public.calendar_sources from anon, authenticated;
grant select on public.calendar_sources to authenticated;
grant update (selected) on public.calendar_sources to authenticated;

drop function public.replace_calendar_events(uuid, jsonb);
-- Replaces one account's snapshot only. Another account's events are never touched.
create function public.replace_calendar_events(p_connection_id uuid, p_events jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
declare owner uuid;
begin
  select user_id into owner from public.calendar_connections where id = p_connection_id;
  if owner is null then
    raise exception 'Unknown calendar connection' using errcode = '22023';
  end if;
  delete from public.calendar_events where connection_id = p_connection_id;
  insert into public.calendar_events(user_id, connection_id, calendar_id, id, ical_uid, title,
      starts_at, ends_at, meeting_url, attendees)
    select owner, p_connection_id, value->>'calendar_id', value->>'id', value->>'ical_uid',
      value->>'title', (value->>'starts_at')::timestamptz, (value->>'ends_at')::timestamptz,
      value->>'meeting_url', coalesce(value->'attendees', '[]'::jsonb)
    from jsonb_array_elements(p_events)
    on conflict do nothing;
  update public.calendar_connections set updated_at = now(), error = null where id = p_connection_id;
end;
$$;
revoke execute on function public.replace_calendar_events(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.replace_calendar_events(uuid, jsonb) to service_role;

-- Busy times from this Mac's own calendars (iCloud, Exchange). Start and end only.
create table public.device_busy_times (
  user_id uuid primary key references auth.users(id) on delete cascade,
  blocks jsonb not null default '[]'::jsonb
    check (jsonb_typeof(blocks) = 'array' and jsonb_array_length(blocks) <= 2000),
  uploaded_at timestamptz not null default now()
);
alter table public.device_busy_times enable row level security;
create policy "Read your device busy times" on public.device_busy_times for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Share busy times from your Mac" on public.device_busy_times for insert to authenticated
  with check ((select auth.uid()) = user_id and (select public.is_murmur_editor()));
create policy "Update busy times from your Mac" on public.device_busy_times for update to authenticated
  using ((select auth.uid()) = user_id and (select public.is_murmur_editor()))
  with check ((select auth.uid()) = user_id and (select public.is_murmur_editor()));
revoke all on public.device_busy_times from anon, authenticated;
grant select, insert, update on public.device_busy_times to authenticated;

-- Booking links ------------------------------------------------------------------------------
create table public.booking_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  handle text not null
    check (handle ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$' and handle not in ('manage', 'api', 'new')),
  display_name text not null check (length(display_name) between 1 and 120),
  time_zone text not null check (length(time_zone) between 1 and 64),
  weekly_hours jsonb not null
    default '[{"days":[1,2,3,4,5],"start":"09:00","end":"17:00"}]'::jsonb
    check (jsonb_typeof(weekly_hours) = 'array' and jsonb_array_length(weekly_hours) <= 50),
  date_overrides jsonb not null default '[]'::jsonb
    check (jsonb_typeof(date_overrides) = 'array' and jsonb_array_length(date_overrides) <= 400),
  destination_connection_id uuid,
  destination_calendar_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (destination_connection_id, destination_calendar_id)
    references public.calendar_sources(connection_id, calendar_id) on delete set null
);
create unique index booking_profiles_handle on public.booking_profiles(handle);
alter table public.booking_profiles enable row level security;
create policy "Read your booking profile" on public.booking_profiles for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Create your booking profile" on public.booking_profiles for insert to authenticated
  with check ((select auth.uid()) = user_id and (select public.is_murmur_editor()));
create policy "Edit your booking profile" on public.booking_profiles for update to authenticated
  using ((select auth.uid()) = user_id and (select public.is_murmur_editor()))
  with check ((select auth.uid()) = user_id and (select public.is_murmur_editor()));
revoke all on public.booking_profiles from anon, authenticated;
grant select, insert, update on public.booking_profiles to authenticated;

create table public.event_types (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  slug text not null check (slug ~ '^[a-z0-9]([a-z0-9-]{0,48}[a-z0-9])?$'),
  title text not null check (length(title) between 1 and 120),
  description text not null default '' check (length(description) <= 2000),
  duration_minutes int not null check (duration_minutes between 5 and 480),
  location_kind text not null default 'google_meet'
    check (location_kind in ('google_meet', 'video_link', 'in_person', 'phone')),
  location_detail text check (length(location_detail) <= 500),
  summary_template text not null default 'meeting'
    check (summary_template in ('meeting', 'oneOnOne', 'standup', 'interview')),
  questions jsonb not null default '[]'::jsonb
    check (jsonb_typeof(questions) = 'array' and jsonb_array_length(questions) <= 10),
  minimum_notice_minutes int not null default 240 check (minimum_notice_minutes between 0 and 43200),
  buffer_before_minutes int not null default 0 check (buffer_before_minutes between 0 and 240),
  buffer_after_minutes int not null default 0 check (buffer_after_minutes between 0 and 240),
  slot_interval_minutes int check (slot_interval_minutes between 5 and 480),
  booking_window_days int not null default 60 check (booking_window_days between 1 and 365),
  daily_limit int check (daily_limit between 1 and 50),
  active boolean not null default true,
  position int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, slug)
);
alter table public.event_types enable row level security;
create policy "Read your meeting types" on public.event_types for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Create your meeting types" on public.event_types for insert to authenticated
  with check ((select auth.uid()) = user_id and (select public.is_murmur_editor()));
create policy "Edit your meeting types" on public.event_types for update to authenticated
  using ((select auth.uid()) = user_id and (select public.is_murmur_editor()))
  with check ((select auth.uid()) = user_id and (select public.is_murmur_editor()));
create policy "Remove your meeting types" on public.event_types for delete to authenticated
  using ((select auth.uid()) = user_id and (select public.is_murmur_editor()));
revoke all on public.event_types from anon, authenticated;
grant select, insert, update, delete on public.event_types to authenticated;

-- A pending row holds the time while the calendar event is created. Two live bookings for
-- one person can never overlap, however many guests submit at the same moment.
create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type_id uuid references public.event_types(id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'cancelled')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  title text not null check (length(title) between 1 and 300),
  summary_template text not null
    check (summary_template in ('meeting', 'oneOnOne', 'standup', 'interview')),
  location_kind text not null,
  location_detail text,
  meeting_url text,
  guest_name text not null check (length(guest_name) between 1 and 120),
  guest_email text not null check (length(guest_email) between 3 and 320),
  guest_time_zone text not null check (length(guest_time_zone) between 1 and 64),
  answers jsonb not null default '[]'::jsonb check (jsonb_typeof(answers) = 'array'),
  connection_id uuid references public.calendar_connections(id) on delete set null,
  calendar_id text,
  provider_event_id text,
  manage_token_hash text not null check (length(manage_token_hash) = 64),
  cancel_reason text check (length(cancel_reason) <= 1000),
  cancelled_by text check (cancelled_by in ('guest', 'host', 'system')),
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  constraint bookings_no_overlap exclude using gist (
    user_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status <> 'cancelled')
);
create index bookings_upcoming on public.bookings(user_id, starts_at);
create index bookings_provider_event on public.bookings(user_id, provider_event_id);
alter table public.bookings enable row level security;
create policy "Read your bookings" on public.bookings for select to authenticated
  using ((select auth.uid()) = user_id);
revoke all on public.bookings from anon, authenticated;
grant select on public.bookings to authenticated;

-- Public booking endpoints are rate limited per hashed address. No raw IP is stored.
create table public.booking_rate_limits (
  bucket text not null check (length(bucket) <= 200),
  window_start timestamptz not null,
  hits int not null default 0,
  primary key (bucket, window_start)
);
alter table public.booking_rate_limits enable row level security;
revoke all on public.booking_rate_limits from anon, authenticated;

create function public.hit_booking_rate_limit(p_bucket text, p_limit int, p_window_seconds int)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare
  bucket_start timestamptz :=
    to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  total int;
begin
  insert into public.booking_rate_limits(bucket, window_start, hits) values (p_bucket, bucket_start, 1)
    on conflict (bucket, window_start)
    do update set hits = public.booking_rate_limits.hits + 1
    returning hits into total;
  if random() < 0.02 then
    delete from public.booking_rate_limits where window_start < now() - interval '1 day';
  end if;
  return total <= p_limit;
end;
$$;
revoke execute on function public.hit_booking_rate_limit(text, int, int) from public, anon, authenticated;
grant execute on function public.hit_booking_rate_limit(text, int, int) to service_role;

grant select, insert, update, delete on
  public.calendar_sources,
  public.device_busy_times,
  public.booking_profiles,
  public.event_types,
  public.bookings,
  public.booking_rate_limits
  to service_role;
