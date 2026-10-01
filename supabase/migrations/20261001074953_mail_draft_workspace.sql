-- Explicit first-party draft storage; connected AI apps do not gain access.
create table public.mail_drafts (
 id uuid primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 connection_id uuid not null,
 document jsonb not null check(jsonb_typeof(document)='object' and octet_length(document::text)<=30000000),
 version integer not null default 1 check(version>0),
 gmail_state text not null default 'unsynced' check(gmail_state in ('unsynced','pending','synced','error','uncertain')),
 gmail_error text,
 outbox_id uuid references public.mail_outbox(id) on delete set null,
 updated_at timestamptz not null default now(),
 foreign key(connection_id,user_id) references public.calendar_connections(id,user_id) on delete cascade
);
create index mail_drafts_owner_updated on public.mail_drafts(user_id,updated_at desc);
alter table public.mail_drafts enable row level security;
revoke all on public.mail_drafts from public,anon,authenticated;
grant select on public.mail_drafts to authenticated;
grant all on public.mail_drafts to service_role;
create policy "Read own mail drafts" on public.mail_drafts for select to authenticated using(user_id=(select auth.uid()) and (select public.is_murmur_editor()));
