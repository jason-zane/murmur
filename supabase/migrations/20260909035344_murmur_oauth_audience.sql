-- Explicit grants, independent of Supabase's default table privileges.
revoke all on public.first_party_clients from anon, authenticated;
grant select on public.first_party_clients to authenticated, supabase_auth_admin;
create policy "Auth hook identifies the native client" on public.first_party_clients
  for select to supabase_auth_admin using (true);

-- OAuth tokens for external apps are bound to this MCP resource, rather than accepting
-- arbitrary Supabase access tokens intended for a different API.
create function public.murmur_access_token_hook(event jsonb) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare claims jsonb := event->'claims';
begin
  if claims->>'client_id' is not null and not exists (
    select 1 from public.first_party_clients where client_id = claims->>'client_id'
  ) then
    claims := jsonb_set(claims, '{aud}', to_jsonb('https://murmur-rho-pied.vercel.app/mcp'::text));
  end if;
  return jsonb_set(event, '{claims}', claims);
end;
$$;
revoke execute on function public.murmur_access_token_hook(jsonb) from public, anon, authenticated;
grant execute on function public.murmur_access_token_hook(jsonb) to supabase_auth_admin;
