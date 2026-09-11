"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { ArrowUpRight, CalendarX, LoaderCircle } from "lucide-react";

type View = {
  status: "pending" | "confirmed" | "cancelled";
  title: string;
  host: string;
  handle: string | null;
  slug: string | null;
  starts_at: string;
  ends_at: string;
  location: string;
  meeting_url: string | null;
  guest_name: string;
};
const format = (value: string) =>
  new Date(value).toLocaleString(undefined, {
    weekday: "long",
    month: "long",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });

// The token lives after # so it is never sent to the server in a URL.
export function ManageBooking({ id }: { id: string }) {
  const [token, setToken] = useState("");
  const [view, setView] = useState<View | null>(null);
  const [error, setError] = useState("");
  const [reason, setReason] = useState("");
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);

  async function post(body: Record<string, unknown>) {
    const r = await fetch(`/api/book/manage/${encodeURIComponent(id)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const result = await r.json();
    if (!r.ok) throw new Error(result.error);
    return result;
  }
  useEffect(() => {
    const t = location.hash.slice(1);
    setToken(t);
    if (!t) {
      setError("Open the link from your booking confirmation or calendar invitation.");
      return;
    }
    post({ action: "view", token: t })
      .then(setView)
      .catch((e) => setError(e instanceof Error ? e.message : "This booking couldn’t be found."));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (error && !view)
    return (
      <section className="book-card book-done">
        <h1>This link isn’t working.</h1>
        <p className="book-lede">{error}</p>
      </section>
    );
  if (!view)
    return (
      <section className="book-card book-done" aria-busy="true">
        <p className="muted" role="status">
          <LoaderCircle className="spin" size={15} /> Finding your booking…
        </p>
      </section>
    );
  const past = new Date(view.ends_at) < new Date();
  return (
    <section className="book-card book-done">
      {view.status === "cancelled" && (
        <span className="done-mark muted-mark">
          <CalendarX size={22} />
        </span>
      )}
      <h1>{view.status === "cancelled" ? "This booking is cancelled." : view.title}</h1>
      <p className="book-lede">
        With {view.host}
        <br />
        <strong>{format(view.starts_at)}</strong>
        <br />
        {view.location}
      </p>
      {view.status === "cancelled" ? (
        <>
          <p className="book-lede">{view.host}’s calendar has been updated and you’ve been told by email.</p>
          {view.handle && (
            <Link className="button" href={`/book/${view.handle}${view.slug ? `/${view.slug}` : ""}`}>
              Book a new time
            </Link>
          )}
        </>
      ) : past ? (
        <p className="book-lede">This meeting has already happened.</p>
      ) : (
        <>
          {view.meeting_url && (
            <a className="button primary" href={view.meeting_url} target="_blank" rel="noreferrer">
              Meeting link
              <ArrowUpRight size={16} />
            </a>
          )}
          {!confirming ? (
            <div className="form-actions centered">
              {view.handle && view.slug && (
                <Link className="button" href={`/book/${view.handle}/${view.slug}?reschedule=${id}#${token}`}>
                  Reschedule
                </Link>
              )}
              <button className="button" onClick={() => setConfirming(true)}>
                Cancel booking
              </button>
            </div>
          ) : (
            <div className="cancel-confirm">
              <label className="field">
                <span>Note for {view.host} (optional)</span>
                <textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={1000} />
              </label>
              {error && <p className="notice" role="alert">{error}</p>}
              <div className="form-actions centered">
                <button className="button" disabled={busy} onClick={() => setConfirming(false)}>
                  Keep booking
                </button>
                <button
                  className="button danger"
                  disabled={busy}
                  onClick={async () => {
                    setBusy(true);
                    setError("");
                    try {
                      await post({ action: "cancel", token, reason: reason || undefined });
                      setView({ ...view, status: "cancelled" });
                    } catch (e) {
                      setError(e instanceof Error ? e.message : "The booking couldn’t be cancelled. Try again.");
                    } finally {
                      setBusy(false);
                    }
                  }}
                >
                  {busy && <LoaderCircle className="spin" size={15} />}
                  Cancel booking
                </button>
              </div>
            </div>
          )}
        </>
      )}
    </section>
  );
}
