-- Mailbox data stays first-party. Existing third-party note grants do not gain mail access.
create table public.mail_outbox (
 id uuid primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 connection_id uuid not null,
 draft_id text,
 thread_id text,
 raw_message text not null check(length(raw_message)<=30000000),
 subject text not null default '',
 status text not null default 'queued' check(status in ('queued','sending','sent','cancelled','failed','uncertain')),
 due_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 provider_id text,
 error text,
 foreign key (connection_id,user_id) references public.calendar_connections(id,user_id) on delete cascade
);
create index mail_outbox_due on public.mail_outbox(due_at) where status='queued';
alter table public.mail_outbox enable row level security;
revoke all on public.mail_outbox from anon,authenticated;
grant select on public.mail_outbox to authenticated;
grant all on public.mail_outbox to service_role;
create policy "Read own outbox" on public.mail_outbox for select to authenticated using(user_id=(select auth.uid()) and (select public.is_murmur_editor()));
-- Bodies are fetched from the provider on demand, not automatically copied into notes/MCP.
create table public.mail_preferences (
 connection_id uuid primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 signature text not null default '' check(length(signature)<=5000),
 notifications boolean not null default false,
 foreign key(connection_id,user_id) references public.calendar_connections(id,user_id) on delete cascade
);
alter table public.mail_preferences enable row level security;
revoke all on public.mail_preferences from anon,authenticated;
grant select on public.mail_preferences to authenticated;
grant all on public.mail_preferences to service_role;
create policy "Read own mail preferences" on public.mail_preferences for select to authenticated using(user_id=(select auth.uid()) and (select public.is_murmur_editor()));
