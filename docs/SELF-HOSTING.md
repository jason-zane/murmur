# Self-hosting the Voice Notes backend

Everything about recording, transcription, notes, summaries and Claude Desktop works with
no backend at all. Hosting one adds: your notes on the web, Google Calendar, and a
connector URL that lets ChatGPT or Claude read your notes from anywhere. The reference
deployment is one Vercel project and one Supabase project on their free tiers.

## What you need

- A [Supabase](https://supabase.com) account (free tier is fine).
- A [Vercel](https://vercel.com) account.
- Node 24 and the [Supabase CLI](https://supabase.com/docs/guides/cli).
- Optional: a Google Cloud project, for "Continue with Google" and Google Calendar.
- A build of the Mac app pointed at your deployment (last step).

## 1. Supabase project

1. Create a project. Note its **project ref** (the subdomain of its URL) and, from
   *Project Settings ▸ API*, the **publishable key** and a **secret key**.
2. Link and apply the migrations from the repository root:

   ```bash
   supabase link --project-ref <ref>
   supabase db push
   ```

3. Check the policies against a throwaway copy of the schema (rolled back, touches nothing):

   ```bash
   supabase start                     # local stack, once
   docker exec -i supabase_db_murmur psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q < supabase/tests/cloud-access.sql
   ```

## 2. Environment

```bash
cd web && cp .env.example .env.local
```

Fill in `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`,
`SUPABASE_SECRET_KEY`, and `NEXT_PUBLIC_SITE_URL` — the https origin your Vercel project
will be served from (for example `https://notes.example.com`, no trailing slash). You can
deploy once to learn the Vercel URL first. `GOOGLE_TOKEN_ENCRYPTION_KEY` is 32 random bytes,
base64: `openssl rand -base64 32`.

## 3. Auth configuration

`web/scripts/configure-cloud.mjs` does all of it when given a Supabase **management
token** for your project (`MURMUR_SUPABASE_MANAGEMENT_TOKEN` in `.env.local`):

```bash
cd web && node scripts/configure-cloud.mjs
```

It sets the Site URL, allows the two redirects (`<site>/auth/callback` and
`murmur://oauth/callback`), enables the OAuth server with the `/oauth/consent` page and
dynamic client registration, enables the custom access-token hook, writes the MCP
audience (`<site>/mcp`) into `murmur_config`, registers the public **Voice Notes for Mac**
OAuth client and saves its id to `.env.local`.

Without a management token, do the Auth settings by hand in the dashboard
(*Authentication ▸ URL configuration*, *Authentication ▸ OAuth server*, *Authentication ▸
Hooks ▸ Customize access token* → `public.murmur_access_token_hook`), then run the script
anyway: it still registers the Mac client and the audience.

## 4. Google (optional)

In Google Cloud: an external OAuth consent screen, the **Google Calendar API** enabled, and
a **Web application** OAuth client with two redirect URIs:

```text
https://<ref>.supabase.co/auth/v1/callback
<site>/api/google/callback
```

Put the client id and secret in `.env.local` and rerun `configure-cloud.mjs`; it enables
the Google provider and sets `NEXT_PUBLIC_GOOGLE_ENABLED`. Calendar is a sensitive scope:
while the consent screen is in *Testing*, only listed test users can connect it.

## 5. Vercel

Import the repository with `web` as the root directory (Next.js is detected). Push the
environment:

```bash
cd web && node scripts/push-environment.mjs      # VERCEL_SCOPE=<team> if the project is in a team
```

Deploy. The region closest to you is fine; the free tier is enough for a few people.

## 6. The Mac app

Build with your origin stamped in:

```bash
make install SITE_URL=https://notes.example.com
```

The app reads `VoiceNotesSiteURL` from its Info.plist for the sign-in bootstrap
(`<site>/api/config`). Friends who use your deployment need this build; a build with the
default origin signs in to the reference deployment instead. Stored credentials remember
the origin they came from, so changing it means sign out, sign in.

## 7. Verify

- `curl <site>/api/config` returns `"ready": true` and your `desktopClientID`.
- `curl <site>/.well-known/oauth-protected-resource` lists your Supabase issuer.
- `curl -i <site>/mcp` answers `401` with a `WWW-Authenticate` challenge.
- Sign in from the Mac app (Settings ▸ Connections), record something, and see it at
  `<site>/`.
- Password reset from `/login` ▸ *Forgot your password?* round-trips through your email.
- `npm run test:integration` with `NEXT_PUBLIC_SITE_URL` set proves the audience follows
  your configuration.

## Updating

Pull, `supabase db push` for new migrations, redeploy on Vercel, and rebuild the Mac app
with the same `SITE_URL`. [CLOUD.md](CLOUD.md) describes the trust model and the sync
contract if you want to know what the pieces do.
