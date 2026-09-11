"use client";
import { useState } from "react";
import Link from "next/link";
import {
  ArrowUpRight,
  CalendarDays,
  Cloud,
  Laptop,
  Link2,
  LogOut,
  Trash2,
} from "lucide-react";
import { AccountIdentity } from "@/components/account-identity";
import { Shell } from "@/components/shell";
import { LocalTime } from "@/components/local-time";
import { browserClient } from "@/lib/supabase/browser";

export function AccountSettings({
  email,
  calendars,
  calendarUnavailable,
}: {
  email: string;
  calendars: {
    email: string | null;
    updated_at: string | null;
    error: string | null;
  }[];
  calendarUnavailable: boolean;
}) {
  const [signingOut, setSigningOut] = useState(false);
  const [error, setError] = useState("");
  const [confirmEmail, setConfirmEmail] = useState("");
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState("");

  async function deleteAccount(e: React.FormEvent) {
    e.preventDefault();
    if (confirmEmail.trim().toLowerCase() !== email.toLowerCase()) {
      setDeleteError("Type your email address exactly to confirm.");
      return;
    }
    setDeleting(true);
    setDeleteError("");
    try {
      const response = await fetch("/api/account", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: confirmEmail.trim() }),
      });
      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        throw new Error(
          body.error || "Couldn't delete the account. Please try again.",
        );
      }
      await browserClient().auth.signOut({ scope: "local" });
      location.href = "/login?error=Your%20account%20has%20been%20deleted.";
    } catch (error) {
      setDeleteError(
        error instanceof Error
          ? error.message
          : "Couldn't delete the account. Please try again.",
      );
      setDeleting(false);
    }
  }

  async function signOut() {
    setSigningOut(true);
    setError("");
    try {
      const { error } = await browserClient().auth.signOut({ scope: "local" });
      if (error) throw error;
      location.href = "/login";
    } catch (error) {
      setError(
        error instanceof Error
          ? error.message
          : "Could not sign out. Please try again.",
      );
      setSigningOut(false);
    }
  }

  return (
    <Shell email={email}>
      <div className="settings-page">
        <header className="page-header">
          <h1>Settings</h1>
          <p>Your account, connections and data.</p>
        </header>
        <section className="account-card" aria-labelledby="account-heading">
          <h2 id="account-heading">Account</h2>
          <AccountIdentity email={email} />
          <p className="settings-description">
            Use the same account on your Mac and the web to see the same notes.
          </p>
          <div className="account-sync-line">
            <Cloud size={18} />
            <div>
              <strong>Cloud library</strong>
              <p>
                Notes synced from your Mac are available here. Settings ▸
                Connections on your Mac shows its sync state.
              </p>
            </div>
            <Link href="/notes" className="text-link">
              Open your notes
              <ArrowUpRight size={14} />
            </Link>
          </div>
          <div className="account-signout">
            <p>
              Signing out only affects this browser. Your Mac stays connected.
            </p>
            <button
              className="button small"
              disabled={signingOut}
              onClick={signOut}
            >
              <LogOut size={16} />
              {signingOut ? "Signing out…" : "Sign out"}
            </button>
          </div>
          {error && (
            <p className="notice" role="alert">
              {error}
            </p>
          )}
        </section>
        <section
          className="settings-section"
          aria-labelledby="connections-heading"
        >
          <h2 id="connections-heading">Connections</h2>
          <div className="settings-row">
            <CalendarDays size={21} />
            <div>
              <h3>Google Calendar</h3>
              <p>
                {calendarUnavailable
                  ? "Connection status is unavailable. Please try again."
                  : calendars.length
                    ? `Connected as ${calendars.map((c) => c.email ?? "a Google account").join(", ")}`
                    : "Not connected"}
              </p>
              {calendars.some((c) => c.updated_at) && (
                <span className="fine-print">
                  Last refreshed{" "}
                  <LocalTime
                    value={
                      calendars
                        .map((c) => c.updated_at)
                        .filter((v): v is string => Boolean(v))
                        .sort()[0]
                    }
                  />
                </span>
              )}
              {calendars
                .filter((c) => c.error)
                .map((c) => (
                  <p className="notice" key={c.email ?? c.error}>
                    {c.email ? `${c.email}: ` : ""}
                    {c.error}
                  </p>
                ))}
            </div>
            <Link className="text-link" href="/connections">
              {calendars.length
                ? "Manage calendars"
                : "Connect Google Calendar"}
              <ArrowUpRight size={14} />
            </Link>
          </div>
          <div className="settings-row">
            <Link2 size={21} />
            <div>
              <h3>Connected apps</h3>
              <p>
                Connect ChatGPT, Claude and other apps to read your synced
                notes. Review or revoke their access in Connections.
              </p>
            </div>
            <Link className="text-link" href="/connections">
              Manage connected apps
              <ArrowUpRight size={14} />
            </Link>
          </div>
          <div className="settings-row">
            <Laptop size={21} />
            <div>
              <h3>Dictation & recording</h3>
              <p>
                Choose your microphone, shortcuts, dictation bar and meeting
                settings in the Mac app.
              </p>
            </div>
            <a className="text-link" href="murmur://settings">
              Open Mac settings
              <ArrowUpRight size={14} />
            </a>
          </div>
        </section>
        <section
          className="settings-section settings-data"
          aria-labelledby="data-heading"
        >
          <h2 id="data-heading">Your data</h2>
          <p>
            Audio stays on your Mac. Completed notes and transcripts sync
            privately to your account. You can keep recording and editing
            offline on your Mac.
          </p>
          <Link href="/privacy" className="text-link">
            Your data & privacy
            <ArrowUpRight size={14} />
          </Link>
        </section>
        <section
          className="settings-section settings-data"
          aria-labelledby="delete-heading"
        >
          <h2 id="delete-heading">Delete account</h2>
          <p>
            Removes your account, every synced note and revision, your calendar
            connection and any connected apps. The notes on your Mac are
            untouched. This can't be undone.
          </p>
          <form onSubmit={deleteAccount} className="delete-account">
            <label htmlFor="confirm-email">Type {email} to confirm</label>
            <input
              id="confirm-email"
              type="email"
              autoComplete="off"
              value={confirmEmail}
              onChange={(e) => setConfirmEmail(e.target.value)}
              placeholder={email}
            />
            <button
              className="button small danger"
              disabled={
                deleting ||
                confirmEmail.trim().toLowerCase() !== email.toLowerCase()
              }
            >
              <Trash2 size={16} />
              {deleting ? "Deleting…" : "Delete my account"}
            </button>
          </form>
          {deleteError && (
            <p className="notice" role="alert">
              {deleteError}
            </p>
          )}
        </section>
      </div>
    </Shell>
  );
}
