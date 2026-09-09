-- Server-only calendar operations and native client registration need explicit grants.
-- New Supabase projects no longer necessarily auto-expose tables to service_role.
grant select, insert, update, delete on
  public.first_party_clients,
  public.calendar_connections,
  public.calendar_credentials,
  public.calendar_events
  to service_role;
