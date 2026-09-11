-- Deployment-specific values the database needs, so a self-hosted copy of Voice Notes
-- can run the same migrations unchanged. Readable only by the auth hook and the server.
create table public.murmur_config (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);
alter table public.murmur_config enable row level security;
revoke all on public.murmur_config from public, anon, authenticated;
grant select on public.murmur_config to supabase_auth_admin, service_role;
grant insert, update, delete on public.murmur_config to service_role;
create policy "Auth hook reads deployment config" on public.murmur_config
  for select to supabase_auth_admin using (true);

-- The audience OAuth tokens for external apps are bound to: this deployment's MCP URL.
-- `web/scripts/configure-cloud.mjs` keeps it in step with NEXT_PUBLIC_SITE_URL.
insert into public.murmur_config (key, value)
values ('mcp_audience', 'https://murmur-rho-pied.vercel.app/mcp')
on conflict (key) do nothing;

-- Same hook as before, reading the audience from config instead of a literal.
create or replace function public.murmur_access_token_hook(event jsonb) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
  claims jsonb := event->'claims';
  audience text;
begin
  if claims->>'client_id' is not null and not exists (
    select 1 from public.first_party_clients where client_id = claims->>'client_id'
  ) then
    select value into audience from public.murmur_config where key = 'mcp_audience';
    if audience is null then
      raise exception 'murmur_config.mcp_audience is not set';
    end if;
    claims := jsonb_set(claims, '{aud}', to_jsonb(audience));
  end if;
  return jsonb_set(event, '{claims}', claims);
end;
$$;
revoke execute on function public.murmur_access_token_hook(jsonb) from public, anon, authenticated;
grant execute on function public.murmur_access_token_hook(jsonb) to supabase_auth_admin;
