"use client";
import { ItemActions } from "@/components/item-actions";
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
  Mail,
  Link2,
  RefreshCw,
  Unplug,
} from "lucide-react";
import { Shell } from "@/components/shell";
import { browserClient } from "@/lib/supabase/browser";
import { canBook, canListCalendars, canReadEvents } from "@/lib/google";
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
  blocks_availability?: boolean;
  meeting_suggestions?: boolean;
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
  const calendarAccounts = accounts.filter(a => canReadEvents(a.scopes));
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
    const focus = p.get("focus");
    if (["calendar", "gmail", "ai"].includes(focus || "")) document.getElementById(`connect-${focus}`)?.scrollIntoView({ block: "start" });
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
  async function choose(source: Source, preference: "selected" | "blocks_availability" | "meeting_suggestions", selected: boolean) {
    const key = `${source.connection_id}|${source.calendar_id}`;
    setPending(key);
    setCalendars((all) =>
      all.map((c) =>
        c.connection_id === source.connection_id &&
        c.calendar_id === source.calendar_id
          ? { ...c, [preference]: selected }
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
          [preference]: selected,
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
            ? { ...c, [preference]: source[preference] }
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
        `Disconnect ${account.email ?? "this Google account"}? Its calendars and mailbox are disconnected. Queued mail is removed and calendars stop blocking booking times.`,
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
          <h1>Connected apps</h1>
          <p>
            Calendars, email and the apps connected to your Concourse account.
          </p>
        </header>
        <div className="connection-account">
          <AccountIdentity email={email} />
          <Link href="/settings" className="text-link">
            Account settings
            <ArrowUpRight size={14} />
          </Link>
        </div>
        <section className="connection-row" id="connect-calendar">
          <span className="connection-symbol">
            <CalendarDays size={25} />
          </span>
          <div>
            <h2>Google Calendar</h2>
            <p>
              {calendarAccounts.length
                ? "Choose what appears in Calendar, what blocks booking times, and what suggests meetings on your Mac."
                : "See what’s next, join on time, and prepare with context from past meetings. Connect work and personal accounts."}
            </p>
            {calendarUnavailable && (
              <p className="notice">
                Calendar status is unavailable. Please try again.
              </p>
            )}
            {calendarAccounts.map((account) => {
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
                              onChange={(e) => void choose(c, "selected", e.target.checked)}
                            />
                            <span
                              className="swatch"
                              style={{ background: "var(--accent)" }}
                              aria-hidden="true"
                            />
                            {c.name} · Show in Calendar
                            {c.is_primary && <small>Primary</small>}
                          </label>
                          <label className="check"><input type="checkbox" checked={c.blocks_availability ?? c.selected} disabled={pending !== null} onChange={e=>void choose(c,"blocks_availability",e.target.checked)}/>Use for booking availability</label>
                          <label className="check"><input type="checkbox" checked={c.meeting_suggestions ?? c.selected} disabled={pending !== null} onChange={e=>void choose(c,"meeting_suggestions",e.target.checked)}/>Use for meeting suggestions</label>
                        </li>
                      ))}
                    </ul>
                  )}
                  <div className="calendar-account-actions">
                    {!account.scopes.includes("https://www.googleapis.com/auth/calendar.events") && <a className="text-link" href={`/api/google/connect?booking=1&account=${encodeURIComponent(account.email || "")}`}>Allow calendar editing</a>}
                    <a className="text-link" href={`/api/google/connect?inbox=1&account=${encodeURIComponent(account.email || "")}`}>Connect Gmail inbox</a>
                    {!canListCalendars(account.scopes) && (
                      <a
                        className="text-link"
                        href={`/api/google/connect${account.email ? `?account=${encodeURIComponent(account.email)}` : ""}`}
                      >
                        Show my other calendars
                        <ArrowUpRight size={14} />
                      </a>
                    )}
                    <ItemActions label={account.email || "Google account"}>
                    <button
                      className="text-link"
                      onClick={() => void disconnect(account)}
                      disabled={busy}
                    >
                      Disconnect account…
                    </button>
                    </ItemActions>
                  </div>
                </div>
              );
            })}
            {!googleReady && !calendarAccounts.length && (
              <p className="fine-print">
                Google Calendar setup is being completed. Your Mac’s calendar
                connection remains available.
              </p>
            )}
          </div>
          <div className="connection-actions">
            {calendarAccounts.length ? (
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
        <section className="connection-row" id="connect-gmail">
          <span className="connection-symbol"><Mail size={25} /></span>
          <div>
            <h2>Gmail inboxes</h2>
            <p>Read, reply and organise work and personal mail together. Mailbox access is separate from your calendar connection.</p>
            {accounts.filter(a => a.scopes.includes("https://www.googleapis.com/auth/gmail.modify")).map(a => <p key={a.id}><strong>{a.email || "Google account"}</strong> · Inbox connected{!canReadEvents(a.scopes) && <> · <a className="text-link" href={`/api/google/connect?account=${encodeURIComponent(a.email || "")}`}>Connect this account’s calendar</a></>} <button className="text-link" disabled={busy} onClick={() => void disconnect(a)}>Disconnect account…</button></p>)}
            <Link className="text-link" href="/mail">Open Mail <ArrowUpRight size={14} /></Link>
          </div>
          <a className={"button small " + (!googleReady ? "disabled" : "")} aria-disabled={!googleReady} href={googleReady ? "/api/google/connect?inbox=1&add=1" : undefined}>Connect Gmail <ArrowUpRight size={16} /></a>
        </section>
        <section className="mcp-card" id="connect-ai">
          <span className="connection-symbol">
            <Link2 size={25} />
          </span>
          <div>

            <h2>Ask ChatGPT or Claude about your notes</h2>
            <p>
              Paste this URL into your app’s connector settings. Sign in to
              Concourse, approve access, and start asking.
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
          <p>Copy the connector URL above, then choose your AI app. Each app asks you to approve access.</p>
          <div className="calendar-account-actions">
            <a className="button small" href="https://chatgpt.com/plugins" target="_blank" rel="noreferrer">Open ChatGPT <ArrowUpRight size={16} /></a>
            <a className="button small" href="https://claude.ai/settings/connectors" target="_blank" rel="noreferrer">Open Claude <ArrowUpRight size={16} /></a>
          </div>
          <details>
            <summary>Connect ChatGPT</summary>
            <p>
              In ChatGPT settings, enable Developer mode under Security and login if available. Open Plugins, choose the plus button and add Concourse using the connector URL above. Follow the sign-in prompt. Workspace policy may require an administrator. Start a new chat and select Concourse from the tools menu to use it.
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
              In Claude, open Customize ▸ Connectors and use the plus button to add a custom connector. Paste the URL above, name it Concourse and connect your account. Team and Enterprise owners first add it for their organisation.
            </p>
          </details>
        </div>
        <section className="connection-row">
          <span className="connection-symbol">
            <Laptop size={25} />
          </span>
          <div>
            <h2>Concourse on your Mac</h2>
            <p>
              Sign in from Connected apps in the Mac app to sync your
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
        <details className="connection-automation"><summary>Booking emails and follow-up drafts</summary><EmailConnection /></details>
      </div>
    </Shell>
  );
}
