-- Legacy tables inherited broad Supabase default grants before explicit ACLs.
-- Row-level security does not apply to TRUNCATE or REFERENCES. The product needs
-- row reads/writes, not client-managed table operations. Preserve all existing row
-- grants, policies, service-role access and objects; reduce only these capabilities.
revoke truncate, references, trigger
  on public.sessions, public.session_revisions, public.calendar_connections, public.calendar_events
  from public, anon, authenticated;
