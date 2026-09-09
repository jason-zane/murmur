"use client";
import { LocalTime } from "@/components/local-time";
import { AccountIdentity } from "@/components/account-identity";
import Link from "next/link";
import { useEffect, useState } from "react";
import {
  ArrowUpRight,
  CalendarDays,
  Check,
  Copy,
  Laptop,
  Link2,
  RefreshCw,
  Unplug,
} from "lucide-react";
import { Shell } from "@/components/shell";
import { browserClient } from "@/lib/supabase/browser";
export function Connections({
  email,
  mcpURL,
  calendar: initialCalendar,
  googleReady,
}: {
  email: string;
  mcpURL: string;
  calendar: { email: string; updated_at: string; error: string | null } | null;
  googleReady: boolean;
}) {
  const [calendar, setCalendar] = useState(initialCalendar);
  const [grantsState, setGrantsState] = useState<"loading" | "ready" | "error">("loading");
  const [copied, setCopied] = useState(false),
    [message, setMessage] = useState(""),
    [busy, setBusy] = useState(false),
    [grants, setGrants] = useState<
      { client: { id: string; name: string }; granted_at: string }[]
    >([]);
  async function loadGrants() {
    setGrantsState("loading");
    try {
      const { data, error } = await browserClient().auth.oauth.listGrants();
      if (error) throw error;
      setGrants((data ?? []) as typeof grants);
      setGrantsState("ready");
    } catch {
      setGrantsState("error");
    }
  }
  useEffect(() => {
    void loadGrants();
    const p = new URLSearchParams(location.search);
    if (p.get("error")) setMessage(p.get("error")!);
    if (p.get("connected"))
      setMessage("Google Calendar is connected. Your next meetings are ready.");
  }, []);
  async function refresh() {
    setBusy(true);
    try {
      const r = await fetch("/api/calendar", { method: "POST" });
      const body = await r.json();
      if (!r.ok) throw new Error(body.error);
      setCalendar(body.connection);
      setMessage(`Calendar refreshed. ${body.events.length} upcoming events.`);
    } catch (e) {
      setMessage(
        e instanceof Error ? e.message : "Could not refresh Calendar.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function disconnect() {
    setBusy(true);
    const r = await fetch("/api/calendar", { method: "DELETE" });
    setBusy(false);
    if (r.ok) location.reload();
    else setMessage("Could not disconnect Google Calendar. Please try again.");
  }
  return (
    <Shell email={email}>
      <div className="connections-page">
        <header className="page-header">
          <h1>Connections</h1>
          <p>Google Calendar and the apps connected to your Voice Notes account.</p>
        </header>
        <div className="connection-account">
          <AccountIdentity email={email} />
          <Link href="/settings" className="text-link">Account settings<ArrowUpRight size={14} /></Link>
        </div>
        <section className="mcp-card">
          <span className="connection-symbol">
            <Link2 size={25} />
          </span>
          <div>
            <div className="eyebrow">CHATGPT · CLAUDE · YOUR OWN APPS</div>
            <h2>One link. Your whole library.</h2>
            <p>
              Paste this URL into your app’s connector settings. Sign in to
              Voice Notes, approve access, and start asking.
            </p>
            <div className="url-copy">
              <code>{mcpURL}</code>
              <button
                aria-label="Copy MCP URL"
                onClick={async () => {
                  try {
                    await navigator.clipboard.writeText(mcpURL);
                    setCopied(true);
                    setTimeout(() => setCopied(false), 2200);
                  } catch {
                    setMessage("Select the URL to copy it.");
                  }
                }}
              >
                {copied ? <Check size={18} /> : <Copy size={18} />}
                <span>{copied ? "Copied" : "Copy URL"}</span>
              </button>
            </div>
            <div className="prompt-examples">
              <span>“What did we decide last week?”</span>
              <span>“Help me prepare for my next meeting.”</span>
            </div>
            <p className="fine-print">
              Connected AI apps can read your synced notes and agenda. They
              cannot edit them. The text they request is shared with that
              provider.
            </p>
          </div>
        </section>
        <div className="connection-guides">
          <details>
            <summary>Connect ChatGPT</summary>
            <p>
              Open ChatGPT settings and find Apps / Connectors. Enable developer
              mode if your plan requires it, then create a custom MCP app with
              this URL and OAuth authentication. Sign in when prompted.
            </p>
            <a
              href="https://developers.openai.com/apps-sdk/deploy/connect-chatgpt/"
              target="_blank"
              rel="noreferrer"
              className="text-link"
            >
              ChatGPT setup guide
              <ArrowUpRight size={14} />
            </a>
          </details>
          <details>
            <summary>Connect Claude</summary>
            <p>
              In Claude, open Customize → Connectors → Add custom connector.
              Name it Voice Notes, paste this URL and continue. Add the connector,
              then select Connect and approve access to your Voice Notes account.
            </p>
          </details>
        </div>
        <section className="connection-row">
          <span className="connection-symbol">
            <CalendarDays size={25} />
          </span>
          <div>
            <h2>Google Calendar</h2>
            <p>
              {calendar
                ? `Connected${calendar.email ? ` as ${calendar.email}` : ""}. Your primary calendar is available in Voice Notes and your connected AI apps.`
                : "See what’s next, join on time, and prepare with context from past meetings."}
            </p>
            {calendar?.updated_at && (
              <span className="fine-print">
                Last refreshed <LocalTime value={calendar.updated_at} />
              </span>
            )}
            {calendar?.error && <p className="notice">{calendar.error}</p>}
            {!googleReady && !calendar && (
              <p className="fine-print">
                Google Calendar setup is being completed. Your Mac’s calendar
                connection remains available.
              </p>
            )}
          </div>
          <div className="connection-actions">
            {calendar ? (
              <>
                <button
                  className="button small"
                  onClick={refresh}
                  disabled={busy}
                >
                  <RefreshCw size={16} />
                  Refresh
                </button>
                <button
                  className="text-link"
                  onClick={disconnect}
                  disabled={busy}
                >
                  Disconnect
                </button>
              </>
            ) : (
              <a
                className={"button " + (!googleReady ? "disabled" : "")}
                aria-disabled={!googleReady}
                href={googleReady ? "/api/google/connect" : undefined}
              >
                Connect Google
                <ArrowUpRight size={16} />
              </a>
            )}
          </div>
        </section>
        <section className="connection-row">
          <span className="connection-symbol">
            <Laptop size={25} />
          </span>
          <div>
            <h2>Voice Notes on your Mac</h2>
            <p>
              Sign in from Settings → Account in the Mac app to sync your library.
              Record, dictate and edit offline. Your changes catch up when you
              reconnect.
            </p>
          </div>
          <a href="murmur://cloud" className="button small">
            Open Mac app
            <ArrowUpRight size={16} />
          </a>
        </section>
        <section className="authorized-apps">
          <h2>Apps you’ve connected</h2>
          {grantsState === "loading" ? (
            <p className="muted" role="status">Loading connected apps…</p>
          ) : grantsState === "error" ? (
            <div className="grant-row">
              <p className="muted" role="alert">Could not load connected apps.</p>
              <button className="text-link" onClick={() => void loadGrants()}>Try again</button>
            </div>
          ) : grants.length ? (
            grants.map((grant) => (
              <div className="grant-row" key={grant.client.id}>
                <span>
                  <strong>{grant.client.name}</strong>
                  <small>
                    Approved <LocalTime value={grant.granted_at} dateOnly />
                  </small>
                </span>
                <button
                  className="text-link"
                  onClick={async () => {
                    const { error } =
                      await browserClient().auth.oauth.revokeGrant({
                        clientId: grant.client.id,
                      });
                    if (error) setMessage(error.message);
                    else {
                      setMessage(
                        "Access revoked. Any already-issued access token expires within one hour.",
                      );
                      void loadGrants();
                    }
                  }}
                >
                  <Unplug size={15} />
                  Revoke access
                </button>
              </div>
            ))
          ) : (
            <p className="muted">
              No apps connected yet. They’ll appear here after you approve them.
            </p>
          )}
        </section>
        {message && (
          <p className="notice" role="status">
            {message}
          </p>
        )}
      </div>
    </Shell>
  );
}
