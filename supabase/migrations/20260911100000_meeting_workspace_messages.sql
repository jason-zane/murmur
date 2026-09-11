-- Generated with the CLI, ordered after the scheduling migration it depends on.
begin;
create table public.mail_settings (
 user_id uuid primary key references auth.users(id) on delete cascade,
 connection_id uuid references public.calendar_connections(id) on delete set null,
 enabled boolean not null default false,
 follow_up_drafts boolean not null default true
);
create table public.booking_message_rules (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 event_type_id uuid not null references public.event_types(id) on delete cascade,
 kind text not null check(kind in ('preparation','reminder','thank_you')),
 offset_minutes integer not null default 1440 check(offset_minutes between 0 and 43200),
 subject text not null check(length(subject) between 1 and 200),
 body text not null check(length(body) between 1 and 10000),
 enabled boolean not null default false,
 unique(event_type_id,kind)
);
create table public.booking_messages (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 booking_id uuid not null references public.bookings(id) on delete cascade,
 rule_id uuid references public.booking_message_rules(id) on delete set null,
 schedule_key text unique,
 booking_start timestamptz not null,
 due_at timestamptz not null,
 kind text not null check(kind in ('preparation','reminder','thank_you','follow_up')),
 status text not null default 'draft' check(status in ('draft','scheduled','sending','sent','failed','needs_attention','skipped')),
 subject text not null default '',
 body text not null default '',
 recipient text,
 sender text,
 provider_id text,
 error text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index booking_messages_due on public.booking_messages(due_at) where status='scheduled';
create index booking_messages_owner on public.booking_messages(user_id,created_at desc);
create index booking_message_rules_owner on public.booking_message_rules(user_id);
alter table public.bookings add column attendance text not null default 'unknown' check(attendance in ('unknown','completed','no_show'));
alter table public.bookings add column operation_key uuid;
alter table public.bookings add column operation_until timestamptz;
-- A lease serialises provider mutations and email dispatch for one booking.
-- Invoker rights and service-role-only execution; no exposed definer function.
create function public.claim_booking_operation(p_id uuid, p_key uuid) returns boolean
language sql set search_path='' as $$
 with claimed as (
 update public.bookings set operation_key=p_key, operation_until=now()+interval '2 minutes'
 where id=p_id and (operation_until is null or operation_until < now()) returning id
 ) select exists(select 1 from claimed);
$$;
revoke all on function public.claim_booking_operation(uuid,uuid) from public,anon,authenticated;
grant execute on function public.claim_booking_operation(uuid,uuid) to service_role;
alter table public.mail_settings enable row level security;
alter table public.booking_message_rules enable row level security;
alter table public.booking_messages enable row level security;
revoke all on public.mail_settings,public.booking_message_rules,public.booking_messages from anon,authenticated;
grant select on public.mail_settings,public.booking_message_rules,public.booking_messages to authenticated;
grant all on public.mail_settings,public.booking_message_rules,public.booking_messages to service_role;
create policy "Read own email settings" on public.mail_settings for select to authenticated using(user_id=(select auth.uid()) and (select public.is_murmur_editor()));
create policy "Read own message rules" on public.booking_message_rules for select to authenticated using(user_id=(select auth.uid()) and (select public.is_murmur_editor()));
create policy "Read own messages" on public.booking_messages for select to authenticated using(user_id=(select auth.uid()) and (select public.is_murmur_editor()));
commit;
