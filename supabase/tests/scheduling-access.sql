begin;
-- Rollback-only fixtures for calendar accounts and booking links. No real account is touched.
insert into auth.users(id, aud, role, email) values
 ('00000000-0000-4000-8000-000000000011','authenticated','authenticated','murmur-host-one@example.invalid'),
 ('00000000-0000-4000-8000-000000000012','authenticated','authenticated','murmur-host-two@example.invalid');
insert into public.calendar_connections(id, user_id, email, scopes) values
 ('00000000-0000-4000-8000-0000000000a1','00000000-0000-4000-8000-000000000011','work@example.invalid','{}'),
 ('00000000-0000-4000-8000-0000000000a2','00000000-0000-4000-8000-000000000011','home@example.invalid','{}');
insert into public.calendar_sources(connection_id, user_id, calendar_id, name, is_primary, can_write, selected) values
 ('00000000-0000-4000-8000-0000000000a1','00000000-0000-4000-8000-000000000011','primary','Work',true,true,true),
 ('00000000-0000-4000-8000-0000000000a2','00000000-0000-4000-8000-000000000011','primary','Home',true,true,true);

-- Refreshing one account keeps the other account's agenda.
select public.replace_calendar_events('00000000-0000-4000-8000-0000000000a1',
  '[{"calendar_id":"primary","id":"w1","title":"Work sync","starts_at":"2026-09-20T01:00:00Z","ends_at":"2026-09-20T02:00:00Z"}]');
select public.replace_calendar_events('00000000-0000-4000-8000-0000000000a2',
  '[{"calendar_id":"primary","id":"h1","title":"Dentist","starts_at":"2026-09-20T03:00:00Z","ends_at":"2026-09-20T04:00:00Z"}]');
select public.replace_calendar_events('00000000-0000-4000-8000-0000000000a1', '[]');
do $$ begin
  if (select count(*) from public.calendar_events where connection_id = '00000000-0000-4000-8000-0000000000a2') <> 1 then
    raise exception 'Refreshing one account removed another account''s events';
  end if;
  if exists (select 1 from public.calendar_events where connection_id = '00000000-0000-4000-8000-0000000000a1') then
    raise exception 'Account snapshot was not replaced';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000011","role":"authenticated"}',true);
insert into public.booking_profiles(user_id, handle, display_name, time_zone, destination_connection_id, destination_calendar_id)
  values ('00000000-0000-4000-8000-000000000011','host-one','Host One','Australia/Sydney','00000000-0000-4000-8000-0000000000a1','primary');
insert into public.event_types(user_id, slug, title, duration_minutes)
  values ('00000000-0000-4000-8000-000000000011','intro','Intro call',30);
update public.calendar_sources set selected = false where connection_id = '00000000-0000-4000-8000-0000000000a2';
do $$ begin
  begin
    update public.calendar_sources set name = 'Renamed' where connection_id = '00000000-0000-4000-8000-0000000000a1';
    raise exception 'Calendar names were editable';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.bookings(user_id, starts_at, ends_at, title, summary_template, location_kind,
      guest_name, guest_email, guest_time_zone, manage_token_hash)
      values ('00000000-0000-4000-8000-000000000011', now(), now() + interval '30 minutes', 'Direct', 'meeting',
        'google_meet', 'Guest', 'guest@example.invalid', 'UTC', repeat('a', 64));
    raise exception 'A client wrote a booking directly';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.booking_profiles(user_id, handle, display_name, time_zone)
      values ('00000000-0000-4000-8000-000000000011','manage','Reserved','UTC');
    raise exception 'A reserved or duplicate handle was accepted';
  exception when check_violation or unique_violation then null;
  end;
  if has_table_privilege('authenticated', 'public.booking_rate_limits', 'SELECT') then
    raise exception 'Rate limit buckets are readable';
  end if;
end $$;

-- Another person sees nothing and cannot take the handle.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000012","role":"authenticated"}',true);
do $$ begin
  if exists (select 1 from public.booking_profiles) or exists (select 1 from public.event_types)
     or exists (select 1 from public.calendar_sources) then
    raise exception 'Cross-account booking leak';
  end if;
  begin
    insert into public.booking_profiles(user_id, handle, display_name, time_zone)
      values ('00000000-0000-4000-8000-000000000012','host-one','Impostor','UTC');
    raise exception 'Handle was taken twice';
  exception when unique_violation then null;
  end;
end $$;

-- Connected AI apps read, but never edit.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000011","role":"authenticated","client_id":"third-party-test"}',true);
do $$ begin
  if not exists (select 1 from public.event_types where slug = 'intro') then raise exception 'MCP cannot read meeting types'; end if;
  update public.event_types set title = 'Changed by an app';
  if exists (select 1 from public.event_types where title = 'Changed by an app') then
    raise exception 'MCP edited a meeting type';
  end if;
end $$;

reset role;
do $$ begin
  if (select selected from public.calendar_sources where connection_id = '00000000-0000-4000-8000-0000000000a2') then
    raise exception 'Owner could not change which calendars count';
  end if;
end $$;

-- Two live bookings can never overlap; a cancelled one frees the time.
insert into public.bookings(user_id, status, starts_at, ends_at, title, summary_template, location_kind,
  guest_name, guest_email, guest_time_zone, manage_token_hash)
  values ('00000000-0000-4000-8000-000000000011','confirmed','2026-09-21T00:00:00Z','2026-09-21T00:30:00Z',
    'First','meeting','google_meet','A','a@example.invalid','UTC', repeat('a', 64));
do $$ begin
  begin
    insert into public.bookings(user_id, status, starts_at, ends_at, title, summary_template, location_kind,
      guest_name, guest_email, guest_time_zone, manage_token_hash)
      values ('00000000-0000-4000-8000-000000000011','pending','2026-09-21T00:15:00Z','2026-09-21T00:45:00Z',
        'Overlap','meeting','google_meet','B','b@example.invalid','UTC', repeat('b', 64));
    raise exception 'Overlapping bookings were accepted';
  exception when exclusion_violation then null;
  end;
end $$;
insert into public.bookings(user_id, status, starts_at, ends_at, title, summary_template, location_kind,
  guest_name, guest_email, guest_time_zone, manage_token_hash)
  values ('00000000-0000-4000-8000-000000000011','confirmed','2026-09-21T00:30:00Z','2026-09-21T01:00:00Z',
    'Back to back','meeting','google_meet','C','c@example.invalid','UTC', repeat('c', 64));
update public.bookings set status = 'cancelled' where title = 'First';
insert into public.bookings(user_id, status, starts_at, ends_at, title, summary_template, location_kind,
  guest_name, guest_email, guest_time_zone, manage_token_hash)
  values ('00000000-0000-4000-8000-000000000011','confirmed','2026-09-21T00:00:00Z','2026-09-21T00:30:00Z',
    'Rebooked','meeting','google_meet','D','d@example.invalid','UTC', repeat('d', 64));
-- Another host's calendar is independent.
insert into public.bookings(user_id, status, starts_at, ends_at, title, summary_template, location_kind,
  guest_name, guest_email, guest_time_zone, manage_token_hash)
  values ('00000000-0000-4000-8000-000000000012','confirmed','2026-09-21T00:00:00Z','2026-09-21T00:30:00Z',
    'Other host','meeting','google_meet','E','e@example.invalid','UTC', repeat('e', 64));

-- Removing the destination calendar clears it from the profile rather than failing.
delete from public.calendar_sources where connection_id = '00000000-0000-4000-8000-0000000000a1';
do $$ begin
  if (select destination_calendar_id from public.booking_profiles where handle = 'host-one') is not null then
    raise exception 'Profile kept a calendar that no longer exists';
  end if;
  if not public.hit_booking_rate_limit('fixture', 2, 60) or not public.hit_booking_rate_limit('fixture', 2, 60)
     or public.hit_booking_rate_limit('fixture', 2, 60) then
    raise exception 'Rate limit did not stop the third request';
  end if;
end $$;
select 'PASS: per-account refresh, calendar choice, booking isolation, read-only apps, reserved handles, no overlaps and rate limits' as result;
rollback;
