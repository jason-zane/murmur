"use client";
import { useCallback, useEffect, useState } from "react";
import { Mail, Plus, Send, X } from "lucide-react";
import Link from "next/link";
type Rule = {
  event_type_id: string;
  kind: string;
  offset_minutes: number;
  subject: string;
  body: string;
  enabled: boolean;
};
type Message = {
  id: string;
  booking_id: string;
  kind: string;
  status: string;
  subject: string;
  body: string;
  due_at: string;
  sender: string | null;
  recipient: string | null;
  error: string | null;
};
type MailData = {
  settings: {
    connection_id: string | null;
    enabled: boolean;
    follow_up_drafts: boolean;
  } | null;
  senders: { id: string; email: string }[];
  rules: Rule[];
  messages: Message[];
};
export async function mailRequest(body?: unknown) {
  const r = await fetch(
    "/api/messages",
    body
      ? {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        }
      : {},
  );
  const b = await r.json();
  if (!r.ok) throw new Error(b.error || "Could not load messages.");
  return b;
}
export function EmailConnection() {
  const [data, setData] = useState<MailData | null>(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  useEffect(() => {
    mailRequest()
      .then(setData)
      .catch((e) => setError(e.message));
  }, []);
  async function save(
    connection_id: string | null,
    enabled: boolean,
    follow_up_drafts = data?.settings?.follow_up_drafts ?? true,
  ) {
    setBusy(true);
    try {
      await mailRequest({
        action: "settings",
        connection_id,
        enabled,
        follow_up_drafts,
      });
      setData(await mailRequest());
      setError(
        enabled
          ? "Emails will send through your selected account when you enable a recipe or send a draft."
          : "Email sending is paused. Calendar invitations continue.",
      );
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="settings-section" id="email">
      <div className="heading-row">
        <h2>
          <Mail size={18} /> Email
        </h2>
        <a className="button small" href="/api/google/connect?mail=1">
          Connect Gmail
        </a>
      </div>
      <p>
        Send preparation, reminders and reviewed follow-ups from your own
        account. Replies go to your inbox. Voice Notes does not read your email.
      </p>
      {data && (
        <div className="form-grid">
          <label className="field">
            <span>Send from</span>
            <select
              value={data.settings?.connection_id || ""}
              disabled={busy}
              onChange={(e) => save(e.target.value || null, false)}
            >
              <option value="">Choose an account</option>
              {data.senders.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.email}
                </option>
              ))}
            </select>
          </label>
          <label className="check">
            <input
              type="checkbox"
              checked={data.settings?.enabled || false}
              disabled={busy || !data.settings?.connection_id}
              onChange={(e) =>
                save(data.settings!.connection_id, e.target.checked)
              }
            />
            Allow sending from this account
          </label>
          <label className="check">
            <input
              type="checkbox"
              checked={data.settings?.follow_up_drafts ?? true}
              disabled={busy}
              onChange={(e) =>
                save(
                  data.settings?.connection_id || null,
                  data.settings?.enabled || false,
                  e.target.checked,
                )
              }
            />
            Prepare a private follow-up draft when a booked meeting’s note is
            ready
          </label>
          <p className="fine-print">
            Only labelled decisions and actions are included. Review and edit
            each draft before sending.
          </p>
        </div>
      )}
      {error && (
        <p className="notice" role="status">
          {error}
        </p>
      )}
    </section>
  );
}
const defaults: Record<
  string,
  { subject: string; body: string; offset: number }
> = {
  preparation: {
    subject: "Before {{meeting_title}}",
    body: "Hi {{guest_name}},\n\nI’m looking forward to our meeting on {{meeting_time}}. Please bring any questions or background you’d like to discuss.\n\nJoin here: {{join_link}}\n\nYou can reschedule or cancel using the link in your calendar invitation.",
    offset: 1440,
  },
  reminder: {
    subject: "Reminder: {{meeting_title}}",
    body: "Hi {{guest_name}},\n\nA reminder about our meeting on {{meeting_time}}.\n\nJoin here: {{join_link}}\n\nYou can reschedule or cancel using your calendar invitation.",
    offset: 1440,
  },
  thank_you: {
    subject: "Thank you for {{meeting_title}}",
    body: "Hi {{guest_name}},\n\nThank you for your time today. It was good to meet with you. Please reply here if you have any questions.",
    offset: 60,
  },
};
const labels: Record<string, string> = {
  preparation: "Preparation",
  reminder: "Reminder",
  thank_you: "Thank-you",
  follow_up: "Follow-up",
};
export function Messages({
  types,
  bookingID,
}: {
  types: { id?: string; title: string }[];
  bookingID?: string;
}) {
  const [data, setData] = useState<MailData | null>(null),
    [error, setError] = useState(""),
    [rule, setRule] = useState<Rule | null>(null),
    [draft, setDraft] = useState<Message | null>(null),
    [busy, setBusy] = useState(false),
    [expanded, setExpanded] = useState<string | null>(null);
  const load = useCallback(async () => {
    try {
      setData(await mailRequest());
    } catch (e) {
      setError((e as Error).message);
    }
  }, []);
  useEffect(() => {
    void load();
  }, [load]);
  async function action(body: unknown) {
    setBusy(true);
    setError("");
    try {
      const result = await mailRequest(body);
      if (result.status)
        setError(
          result.status === "sent"
            ? "Google accepted your email. Delivery is not yet confirmed."
            : `Message status: ${result.status.replaceAll("_", " ")}`,
        );
      await load();
      return true;
    } catch (e) {
      setError((e as Error).message);
      return false;
    } finally {
      setBusy(false);
    }
  }
  const messages =
    data?.messages.filter((m) => !bookingID || m.booking_id === bookingID) ||
    [];
  return (
    <section className="messages-area">
      {error && (
        <p className="notice" role="status">
          {error}
        </p>
      )}
      {!data ? (
        <p className="muted">Loading messages…</p>
      ) : (
        <>
          {!bookingID && (
            <>
              <div className="heading-row">
                <div>
                  <h2>Meeting messages</h2>
                  <p>Thoughtful preparation. Clear follow-through.</p>
                </div>
                <Link className="text-link" href="/connections#email">
                  {data.settings?.enabled
                    ? `From ${data.senders.find((s) => s.id === data.settings?.connection_id)?.email || "your account"}`
                    : "Connect an email sender"}
                </Link>
              </div>
              <p className="fine-print">
                Recipes are off until you enable them. Thank-you emails only
                send after you mark a meeting completed. Notes and transcripts
                are never attached automatically.
              </p>
              {types.map((t) => (
                <section className="workspace-card" key={t.id}>
                  <h3>{t.title}</h3>
                  {Object.entries(defaults).map(([kind, d]) => {
                    const existing = data.rules.find(
                      (r) => r.event_type_id === t.id && r.kind === kind,
                    );
                    return (
                      <div className="recipe-row" key={kind}>
                        <div>
                          <strong>{labels[kind]}</strong>
                          <small>
                            {existing?.enabled
                              ? `${existing.offset_minutes} minutes ${kind === "thank_you" ? "after" : "before"}`
                              : "Off"}
                          </small>
                        </div>
                        <button
                          className="button small"
                          onClick={() =>
                            setRule(
                              existing || {
                                event_type_id: t.id!,
                                kind,
                                offset_minutes: d.offset,
                                subject: d.subject,
                                body: d.body,
                                enabled: false,
                              },
                            )
                          }
                        >
                          Edit message
                        </button>
                      </div>
                    );
                  })}
                </section>
              ))}
            </>
          )}
          {rule && (
            <form
              className="workspace-card"
              onSubmit={async (e) => {
                e.preventDefault();
                if (await action({ ...rule, action: "rule" })) setRule(null);
              }}
            >
              <div className="heading-row">
                <h2>{labels[rule.kind]} email</h2>
                <button
                  type="button"
                  className="icon-button"
                  aria-label="Close editor"
                  onClick={() => setRule(null)}
                >
                  <X size={18} />
                </button>
              </div>
              <label className="check">
                <input
                  type="checkbox"
                  checked={rule.enabled}
                  onChange={(e) =>
                    setRule({ ...rule, enabled: e.target.checked })
                  }
                />
                Send automatically for this meeting type
              </label>
              <label className="field">
                <span>
                  Minutes{" "}
                  {rule.kind === "thank_you"
                    ? "after the meeting ends"
                    : "before the meeting starts"}
                </span>
                <input
                  type="number"
                  min="0"
                  max="43200"
                  value={rule.offset_minutes}
                  onChange={(e) =>
                    setRule({ ...rule, offset_minutes: Number(e.target.value) })
                  }
                />
              </label>
              <label className="field">
                <span>Subject</span>
                <input
                  maxLength={200}
                  required
                  value={rule.subject}
                  onChange={(e) =>
                    setRule({ ...rule, subject: e.target.value })
                  }
                />
              </label>
              <label className="field">
                <span>Message</span>
                <textarea
                  rows={8}
                  maxLength={10000}
                  required
                  value={rule.body}
                  onChange={(e) => setRule({ ...rule, body: e.target.value })}
                />
              </label>
              <p className="fine-print">
                Variables:{" "}
                {
                  "{{guest_name}}, {{meeting_title}}, {{meeting_time}}, {{join_link}}"
                }
                . Changes apply to unsent messages. Reminders booked too late
                are skipped.
              </p>
              <details>
                <summary>Preview example</summary>
                <div className="message-preview">
                  {rule.body
                    .replaceAll("{{guest_name}}", "Alex")
                    .replaceAll("{{meeting_title}}", "Intro call")
                    .replaceAll(
                      "{{meeting_time}}",
                      "Monday, 14 September at 9:00 am (Australia/Sydney)",
                    )
                    .replaceAll(
                      "{{join_link}}",
                      "https://meet.google.com/example",
                    )}
                </div>
              </details>
              <button className="button primary" disabled={busy}>
                Save message
              </button>
            </form>
          )}
          <h2>Message history</h2>
          {draft && (
            <form
              className="workspace-card"
              onSubmit={async (event) => {
                event.preventDefault();
                if (
                  await action({
                    action: "edit",
                    id: draft.id,
                    subject: draft.subject,
                    body: draft.body,
                  })
                )
                  setDraft(null);
              }}
            >
              <h3>Edit private draft</h3>
              <label className="field">
                <span>Subject</span>
                <input
                  required
                  maxLength={200}
                  value={draft.subject}
                  onChange={(e) =>
                    setDraft({ ...draft, subject: e.target.value })
                  }
                />
              </label>
              <label className="field">
                <span>Message</span>
                <textarea
                  required
                  rows={8}
                  maxLength={10000}
                  value={draft.body}
                  onChange={(e) => setDraft({ ...draft, body: e.target.value })}
                />
              </label>
              <p className="fine-print">Saving does not send this email.</p>
              <div className="form-actions">
                <button className="button primary" disabled={busy}>
                  Save draft
                </button>
                <button
                  type="button"
                  className="button"
                  disabled={busy}
                  onClick={() => setDraft(null)}
                >
                  Cancel
                </button>
              </div>
            </form>
          )}
          {!messages.length ? (
            <p className="muted">
              Scheduled messages and reviewed drafts appear here. Recipes are
              checked every minute while sending is enabled.
            </p>
          ) : (
            messages.map((m) => (
              <article className="message-row" key={m.id}>
                <button
                  className="message-summary"
                  aria-expanded={expanded === m.id}
                  onClick={() => setExpanded(expanded === m.id ? null : m.id)}
                >
                  <span>
                    <strong>{m.subject || labels[m.kind]}</strong>
                    <small>
                      {m.recipient || "Booking guest"} ·{" "}
                      {new Date(m.due_at).toLocaleString()}
                    </small>
                  </span>
                  <span className="status-badge">
                    {m.status.replaceAll("_", " ")}
                  </span>
                </button>
                {expanded === m.id && (
                  <div className="message-preview">
                    <p>
                      {m.body ||
                        "The latest saved recipe will be used when this message sends."}
                    </p>
                    {m.sender && <small>From {m.sender}</small>}
                    {m.error && <p className="notice">{m.error}</p>}
                    <div className="form-actions">
                      {m.kind === "follow_up" &&
                        ["draft", "failed"].includes(m.status) && (
                          <button
                            className="button small"
                            disabled={busy}
                            onClick={() => setDraft(m)}
                          >
                            Edit draft
                          </button>
                        )}
                      {["draft", "failed"].includes(m.status) && (
                        <button
                          disabled={busy}
                          className="button small primary"
                          onClick={() => {
                            if (
                              confirm(
                                `Send this email to the guest from your connected account?\n\n${m.subject}`,
                              )
                            )
                              void action({ action: "send", id: m.id });
                          }}
                        >
                          <Send size={15} />
                          {m.status === "failed" ? "Retry send" : "Send email"}
                        </button>
                      )}
                      {[
                        "draft",
                        "scheduled",
                        "failed",
                        "needs_attention",
                      ].includes(m.status) && (
                        <button
                          className="button small"
                          disabled={busy}
                          onClick={() => action({ action: "skip", id: m.id })}
                        >
                          Skip message
                        </button>
                      )}
                    </div>
                  </div>
                )}
              </article>
            ))
          )}
        </>
      )}
    </section>
  );
}
export function FollowUp({
  booking,
  onSaved,
}: {
  booking: {
    id: string;
    title: string;
    guest_name: string;
    guest_email: string;
  };
  onSaved?: () => void;
}) {
  const [open, setOpen] = useState(false),
    [subject, setSubject] = useState(`Following up: ${booking.title}`),
    [body, setBody] = useState(
      `Hi ${booking.guest_name},\n\nThank you for your time.\n\n`,
    ),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  return (
    <>
      <button className="text-link" onClick={() => setOpen(!open)}>
        <Plus size={14} />
        Draft follow-up
      </button>
      {open && (
        <form
          className="workspace-card"
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            try {
              await mailRequest({
                action: "draft",
                booking_id: booking.id,
                subject,
                body,
              });
              setOpen(false);
              onSaved?.();
            } catch (e) {
              setError((e as Error).message);
            } finally {
              setBusy(false);
            }
          }}
        >
          <h3>Follow-up to {booking.guest_name}</h3>
          <p className="fine-print">
            To {booking.guest_email}. Add only the decisions and actions you
            want to share. Saving creates a private draft; it does not send.
          </p>
          <label className="field">
            <span>Subject</span>
            <input
              required
              value={subject}
              maxLength={200}
              onChange={(e) => setSubject(e.target.value)}
            />
          </label>
          <label className="field">
            <span>Message</span>
            <textarea
              required
              rows={8}
              value={body}
              maxLength={10000}
              onChange={(e) => setBody(e.target.value)}
            />
          </label>
          {error && (
            <p className="notice" role="alert">
              {error}
            </p>
          )}
          <button className="button primary" disabled={busy}>
            Save draft
          </button>
        </form>
      )}
    </>
  );
}
