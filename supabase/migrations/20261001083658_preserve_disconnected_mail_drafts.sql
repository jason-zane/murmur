-- Provider disconnection must not delete independently saved first-party work.
alter table public.mail_drafts drop constraint mail_drafts_connection_id_user_id_fkey;
alter table public.mail_drafts alter column connection_id drop not null;
alter table public.mail_drafts add constraint mail_drafts_connection_id_user_id_fkey
 foreign key(connection_id,user_id) references public.calendar_connections(id,user_id)
 on delete set null(connection_id);
create index mail_drafts_connection_owner on public.mail_drafts(connection_id,user_id) where connection_id is not null;
