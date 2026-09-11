"use client";
import { EmailConnection } from "@/components/messages";
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
import { canBook, canListCalendars } from "@/lib/google";
type Account = {
  id: string;
  email: string | null;
  scopes: string[];
  updated_at: string | null;
  error: string | null;
};
type Source = {
  connection_id: string;
  calendar_id: string;
  name: string;
  color: string | null;
  is_primary: boolean;
  selected: boolean;
};
export function Connections({
  email,
  mcpURL,
  accounts: initialAccounts,
  calendars: initialCalendars,
  calendarUnavailable,
  googleReady,
}: {
  email: string;
  mcpURL: string;
  accounts: Account[];
  calendars: Source[];
  calendarUnavailable: boolean;
  googleReady: boolean;
}) {
  const [accounts, setAccounts] = useState(initialAccounts);
  const [calendars, setCalendars] = useState(initialCalendars);
  const [pending, setPending] = useState<string | null>(null);
  const [grantsState, setGrantsState] = useState<"loading" | "ready" | "error">(
    "loading",
  );
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
      setMessage(
        p.get("connected") === "email"
          ? "Gmail is connected. Choose your sender and allow sending in Email below."
          : "Google Calendar is connected. Choose which calendars to include below.",
      );
  }, []);
  function apply(body: { connections: Account[]; calendars: Source[] }) {
    setAccounts(body.connections);
    setCalendars(body.calendars);
  }
  async function refresh() {
    setBusy(true);
    try {
      const r = await fetch("/api/calendar", { method: "POST" });
      const body = await r.json();
      if (!r.ok) throw new Error(body.error);
      apply(body);
      setMessage(`Calendar refreshed. ${body.events.length} upcoming events.`);
    } catch (e) {
      setMessage(
        e instanceof Error ? e.message : "Could not refresh Calendar.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function choose(source: Source, selected: boolean) {
    const key = `${source.connection_id}|${source.calendar_id}`;
    setPending(key);
    setCalendars((all) =>
      all.map((c) =>
        c.connection_id === source.connection_id &&
        c.calendar_id === source.calendar_id
          ? { ...c, selected }
          : c,
      ),
    );
    try {
      const r = await fetch("/api/calendar/sources", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          connection_id: source.connection_id,
          calendar_id: source.calendar_id,
          selected,
        }),
      });
      const body = await r.json();
      if (!r.ok) throw new Error(body.error);
      apply(body);
    } catch (e) {
      setCalendars((all) =>
        all.map((c) =>
          c.connection_id === source.connection_id &&
          c.calendar_id === source.calendar_id
            ? { ...c, selected: !selected }
            : c,
        ),
      );
      setMessage(
        e instanceof Error ? e.message : "Could not update that calendar.",
      );
    } finally {
      setPending(null);
    }
  }
  async function disconnect(account: Account) {
    if (
      !confirm(
        `Disconnect ${account.email ?? "this Google account"}? Its meetings leave your agenda and its calendars stop blocking booking times.`,
      )
    )
      return;
    setBusy(true);
    const r = await fetch(
      `/api/calendar?connection=${encodeURIComponent(account.id)}`,
      {
        method: "DELETE",
      },
    );
    setBusy(false);
    if (r.ok) {
      setAccounts((all) => all.filter((a) => a.id !== account.id));
      setCalendars((all) => all.filter((c) => c.connection_id !== account.id));
      setMessage(`${account.email ?? "The account"} is disconnected.`);
    } else
      setMessage("Could not disconnect Google Calendar. Please try again.");
  }
  return (
    <Shell email={email}>
      <div className="connections-page">
        <header className="page-header">
          <h1>Connections</h1>
          <p>
            Calendars, email and the apps connected to your Voice Notes account.
          </p>
        </header>
        <div className="connection-account">
          <AccountIdentity email={email} />
          <Link href="/settings" className="text-link">
            Account settings
            <ArrowUpRight size={14} />
          </Link>
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
              Name it Voice Notes, paste this URL and continue. Add the
              connector, then select Connect and approve access to your Voice
              Notes account.
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
              {accounts.length
                ? "Ticked calendars appear in your agenda, name your meetings on the Mac, and block times on your booking links."
                : "See what’s next, join on time, and prepare with context from past meetings. Connect work and personal accounts."}
            </p>
            {calendarUnavailable && (
              <p className="notice">
                Calendar status is unavailable. Please try again.
              </p>
            )}
            {accounts.map((account) => {
              const own = calendars.filter(
                (c) => c.connection_id === account.id,
              );
              return (
                <div className="calendar-account" key={account.id}>
                  <div className="calendar-account-head">
                    <strong>{account.email ?? "Google account"}</strong>
                    {canBook(account.scopes) && (
                      <span className="chip">Booking allowed</span>
                    )}
                  </div>
                  {account.updated_at && (
                    <span className="fine-print">
                      Last refreshed <LocalTime value={account.updated_at} />
                    </span>
                  )}
                  {account.error && <p className="notice">{account.error}</p>}
                  {own.length > 0 && (
                    <ul className="calendar-list">
                      {own.map((c) => (
                        <li key={c.calendar_id}>
                          <label className="check">
                            <input
                              type="checkbox"
                              checked={c.selected}
                              disabled={pending !== null}
                              onChange={(e) => void choose(c, e.target.checked)}
                            />
                            <span
                              className="swatch"
                              style={{ background: c.color ?? "var(--accent)" }}
                              aria-hidden="true"
                            />
                            {c.name}
                            {c.is_primary && <small>Primary</small>}
                          </label>
                        </li>
                      ))}
                    </ul>
                  )}
                  <div className="calendar-account-actions">
                    {!canListCalendars(account.scopes) && (
                      <a
                        className="text-link"
                        href={`/api/google/connect${account.email ? `?account=${encodeURIComponent(account.email)}` : ""}`}
                      >
                        Show my other calendars
                        <ArrowUpRight size={14} />
                      </a>
                    )}
                    <button
                      className="text-link"
                      onClick={() => void disconnect(account)}
                      disabled={busy}
                    >
                      Disconnect
                    </button>
                  </div>
                </div>
              );
            })}
            {!googleReady && !accounts.length && (
              <p className="fine-print">
                Google Calendar setup is being completed. Your Mac’s calendar
                connection remains available.
              </p>
            )}
          </div>
          <div className="connection-actions">
            {accounts.length ? (
              <>
                <button
                  className="button small"
                  onClick={refresh}
                  disabled={busy}
                >
                  <RefreshCw size={16} />
                  Refresh
                </button>
                <a
                  className={"text-link " + (!googleReady ? "disabled" : "")}
                  href={googleReady ? "/api/google/connect?add=1" : undefined}
                >
                  Add another Google account
                </a>
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
              Sign in from Settings → Account in the Mac app to sync your
              library. Record, dictate and edit offline. Your changes catch up
              when you reconnect.
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
            <p className="muted" role="status">
              Loading connected apps…
            </p>
          ) : grantsState === "error" ? (
            <div className="grant-row">
              <p className="muted" role="alert">
                Could not load connected apps.
              </p>
              <button className="text-link" onClick={() => void loadGrants()}>
                Try again
              </button>
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
        <EmailConnection />
      </div>
    </Shell>
  );
}
