"use client";
import { useState } from "react";
import type { OAuthAuthorizationDetails } from "@supabase/supabase-js";
import { ArrowRight, BookOpen, CalendarDays, Check } from "lucide-react";
import { Brand } from "@/components/brand";
import { browserClient } from "@/lib/supabase/browser";
export function Consent({
  details,
  email,
  desktop,
}: {
  details: OAuthAuthorizationDetails;
  email: string;
  desktop: boolean;
}) {
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  async function decide(approve: boolean) {
    setBusy(true);
    const client = browserClient();
    const { data, error } = approve
      ? await client.auth.oauth.approveAuthorization(details.authorization_id, {
          skipBrowserRedirect: true,
        })
      : await client.auth.oauth.denyAuthorization(details.authorization_id, {
          skipBrowserRedirect: true,
        });
    if (error || !data) {
      setError(error?.message || "Could not connect. Please try again.");
      setBusy(false);
    } else location.assign(data.redirect_url);
  }
  return (
    <main id="main" className="consent">
      <Brand />
      <span className="eyebrow">YOUR PERMISSION, YOUR CHOICE</span>
      <h1>Connect {details.client.name || "this app"} to Voice Notes?</h1>
      <p>
        You’re signed in as <strong>{email}</strong>.
      </p>
      <div className="consent-access">
        <div>
          <BookOpen size={20} />
          <span>
            <strong>
              {desktop
                ? "Sync your notes and transcripts"
                : "Read your notes and transcripts"}
            </strong>
            <small>
              {desktop
                ? "Bring this Mac’s completed meetings into your account and download your cloud notes."
                : "Find meetings, read the conversation and help you work with it."}
            </small>
          </span>
          <Check size={18} />
        </div>
        <div>
          <CalendarDays size={20} />
          <span>
            <strong>Read your upcoming meetings</strong>
            <small>Access your connected Google Calendar agenda.</small>
          </span>
          <Check size={18} />
        </div>
      </div>
      <p className="fine-print">
        {desktop
          ? "Recording and dictation stay on your Mac. Completed meeting text will sync to your account."
          : "Your notes may be sent to this app’s AI provider. This connection has read-only access."}{" "}
        You can revoke access in Connections.
      </p>
      <p className="redirect-domain">
        Returning to <code>{details.redirect_uri}</code>
      </p>
      {error && (
        <p className="notice" role="alert">
          {error}
        </p>
      )}
      <div className="consent-actions">
        <button
          className="button"
          disabled={busy}
          onClick={() => decide(false)}
        >
          Cancel
        </button>
        <button
          className="button primary"
          disabled={busy}
          onClick={() => decide(true)}
        >
          {busy ? "Connecting…" : "Allow connection"}
          <ArrowRight size={17} />
        </button>
      </div>
    </main>
  );
}
