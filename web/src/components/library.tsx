"use client";
import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import {
  ArrowUpRight,
  CalendarDays,
  Check,
  Cloud,
  FileText,
  Laptop,
  LoaderCircle,
  Pin,
  Plus,
  RefreshCw,
  Search,
  X,
  ChevronLeft,
  Copy,
  Download,
} from "lucide-react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { Shell } from "./shell";
import { BrandMark, Waveform } from "./brand";
import {
  matches,
  meetingURL,
  newDocument,
  preview,
  type CloudSession,
  type CalendarMeeting,
  type MeetingDocument,
} from "@/lib/documents";
const date = (value: string) =>
  new Date(value).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
const time = (value: string) =>
  new Date(value).toLocaleTimeString(undefined, {
    hour: "numeric",
    minute: "2-digit",
  });
const duration = (s: number) =>
  `${Math.floor(s / 60)}:${Math.floor(s % 60)
    .toString()
    .padStart(2, "0")}`;
export function Library({ email, userID }: { email: string; userID: string }) {
  const [rows, setRows] = useState<CloudSession[]>([]),
    [events, setEvents] = useState<CalendarMeeting[]>([]),
    [query, setQuery] = useState(""),
    [selected, setSelected] = useState<string | null>(null),
    [filter, setFilter] = useState("all"),
    [loading, setLoading] = useState(true),
    [message, setMessage] = useState(""),
    [dayLabel, setDayLabel] = useState("Your day"),
    [calendarConnected, setCalendarConnected] = useState(false);
  const load = useCallback(async () => {
    setMessage("");
    try {
      let offset: number | null = 0;
      const all: CloudSession[] = [];
      while (offset !== null) {
        const r: Response = await fetch(`/api/sessions?offset=${offset}`);
        const body: {
          sessions: CloudSession[];
          nextOffset: number | null;
          error?: string;
        } = await r.json();
        if (!r.ok) throw new Error(body.error);
        all.push(...body.sessions);
        offset = body.nextOffset;
      }
      setRows(
        all
          .filter((r) => !r.deleted_at)
          .sort((a, b) => b.started_at.localeCompare(a.started_at)),
      );
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Could not load your notes.");
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => {
    setDayLabel(
      new Date().toLocaleDateString(undefined, {
        weekday: "long",
        month: "long",
        day: "numeric",
      }),
    );
    void load();
    const id = new URLSearchParams(location.search).get("note");
    if (id) setSelected(id);
    void fetch("/api/calendar").then(async (r) => {
      if (r.ok) {
        const b = await r.json();
        setEvents(b.events || []);
        setCalendarConnected(Boolean(b.connections?.length ?? b.connection));
      }
    });
  }, [load]);
  async function create() {
    setMessage("");
    try {
      const r = await fetch("/api/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ document: newDocument(), expectedVersion: 0 }),
      });
      const row = await r.json();
      if (!r.ok) throw new Error(row.error);
      setRows((v) => [row, ...v]);
      setSelected(row.id);
    } catch (e) {
      setMessage(
        e instanceof Error ? e.message : "Could not create your note.",
      );
    }
  }
  function replace(row: CloudSession) {
    setRows((v) => v.map((r) => (r.id === row.id ? row : r)));
  }
  const current = rows.find((r) => r.id === selected),
    visible = rows.filter(
      (r) =>
        matches(r.document, query) &&
        (filter !== "pinned" || r.document.session.pinned),
    );
  return (
    <Shell email={email} onNew={create}>
      {current ? (
        <div className="notes-detail-layout">
          <aside className="note-index" aria-label="Notes list">
            <label className="search">
              <Search size={16} />
              <input
                aria-label="Search notes"
                placeholder="Search notes"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
              />
            </label>
            {visible.map((n) => (
              <button
                key={n.id}
                className={n.id === current.id ? "selected" : ""}
                onClick={() => {
                  if (n.id === current.id) return;
                  if (
                    document.querySelector(".note-editor") &&
                    !confirm(
                      "Leave this note? An unfinished draft stays in this browser.",
                    )
                  )
                    return;
                  setSelected(n.id);
                  history.replaceState(
                    null,
                    "",
                    `/notes?note=${encodeURIComponent(n.id)}`,
                  );
                }}
              >
                <strong>{n.title}</strong>
                <small>{date(n.started_at)}</small>
              </button>
            ))}
          </aside>
          <NoteDetail
            key={current.id}
            row={current}
            userID={userID}
            onBack={() => {
              setSelected(null);
              history.replaceState(null, "", "/notes");
            }}
            onSaved={replace}
          />
        </div>
      ) : (
        <>
          <header className="page-header">
            <div className="heading-row">
              <div>
                <h1>Notes</h1>
                <p>Your meetings and ideas, together.</p>
              </div>
              <button className="button primary" onClick={create}>
                <Plus size={16} />
                New note
              </button>
            </div>
          </header>
          <div className="notes-workspace">
            <section className="notes-section">
              <div className="library-toolbar">
                <div className="tabs">
                  <button
                    className={filter === "all" ? "selected" : ""}
                    onClick={() => setFilter("all")}
                  >
                    All notes <span>{rows.length}</span>
                  </button>
                  <button
                    className={filter === "pinned" ? "selected" : ""}
                    onClick={() => setFilter("pinned")}
                  >
                    <Pin size={14} />
                    Pinned
                  </button>
                </div>
                <button
                  className="icon-button"
                  aria-label="Refresh notes"
                  onClick={load}
                >
                  <RefreshCw size={16} />
                </button>
              </div>
              <label className="search">
                <Search size={17} />
                <input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder="Find a thought, person or meeting…"
                  aria-label="Search your library"
                />
                {query && (
                  <button
                    className="icon-button"
                    aria-label="Clear search"
                    onClick={() => setQuery("")}
                  >
                    <X size={14} />
                  </button>
                )}
              </label>
              {message && (
                <p className="notice" role="alert">
                  {message} <button onClick={load}>Try again</button>
                </p>
              )}
              {loading ? (
                <div className="empty">
                  <LoaderCircle className="spin" />
                  <p>Opening your library…</p>
                </div>
              ) : visible.length === 0 ? (
                <div className="empty">
                  <span className="empty-icon">
                    <FileText size={26} />
                  </span>
                  <h3>
                    {query
                      ? "No matching notes yet."
                      : "Your next thought starts here."}
                  </h3>
                  <p>
                    {query
                      ? "Try a name, a phrase or a few different words."
                      : "Connect the Mac app to bring your meeting notes here, or start writing now."}
                  </p>
                  <button
                    className="button"
                    onClick={query ? () => setQuery("") : create}
                  >
                    {query ? "Clear search" : "Write your first note"}
                    <Plus size={16} />
                  </button>
                </div>
              ) : (
                <div className="note-list">
                  {visible.map((row) => (
                    <button
                      className="note-row"
                      key={row.id}
                      onClick={() => {
                        setSelected(row.id);
                        history.replaceState(
                          null,
                          "",
                          `/notes?note=${encodeURIComponent(row.id)}`,
                        );
                      }}
                    >
                      <span
                        className={
                          "note-icon " +
                          (row.document.session.engine === "Notes"
                            ? "personal"
                            : "")
                        }
                      >
                        <FileText size={19} />
                      </span>
                      <div className="note-row-content">
                        <div className="note-meta">
                          {date(row.started_at)}
                          <span>·</span>
                          {row.document.session.app ||
                            (row.document.session.engine === "Notes"
                              ? "Personal note"
                              : "Meeting")}
                          {row.document.session.pinned && <Pin size={12} />}
                        </div>
                        <h3>{row.title}</h3>
                        <p>
                          {preview(row.document) ||
                            "A little space for your ideas."}
                        </p>
                        <div className="note-footer">
                          {row.document.session.speakers
                            .slice(0, 3)
                            .join(" · ")}
                          {row.document.session.duration > 0 && (
                            <span>
                              {duration(row.document.session.duration)}
                            </span>
                          )}
                        </div>
                      </div>
                      <ArrowUpRight className="row-arrow" size={17} />
                    </button>
                  ))}
                </div>
              )}
            </section>
          </div>
        </>
      )}
    </Shell>
  );
}
function NoteDetail({
  row,
  userID,
  onBack,
  onSaved,
}: {
  row: CloudSession;
  userID: string;
  onBack: () => void;
  onSaved: (r: CloudSession) => void;
}) {
  const key = `murmur:draft:${userID}:${row.id}`;
  const [title, setTitle] = useState(row.title),
    [text, setText] = useState(row.document.note || ""),
    [editing, setEditing] = useState(!row.document.note),
    [tab, setTab] = useState("note"),
    [message, setMessage] = useState(""),
    [busy, setBusy] = useState(false),
    [copied, setCopied] = useState(false),
    [sourceQuery, setSourceQuery] = useState("");
  useEffect(() => {
    try {
      const saved = localStorage.getItem(key);
      if (saved) {
        const draft = JSON.parse(saved);
        setText(draft.text);
        setTitle(draft.title);
        if (Number.isSafeInteger(draft.baseVersion))
          setBaseVersion(draft.baseVersion);
        setEditing(true);
        setMessage(
          "Your unfinished draft was recovered. Save when you’re ready.",
        );
      }
    } catch {
      setMessage(
        "Browser draft storage is unavailable. Keep this tab open until your note is saved.",
      );
    }
  }, [key]);
  const [baseVersion, setBaseVersion] = useState(row.version),
    [conflict, setConflict] = useState<CloudSession | null>(null);
  const changed = title !== row.title || text !== (row.document.note || "");
  function change(nextTitle: string, nextText: string) {
    setTitle(nextTitle);
    setText(nextText);
    try {
      localStorage.setItem(
        key,
        JSON.stringify({ title: nextTitle, text: nextText, baseVersion }),
      );
    } catch {
      setMessage(
        "Your browser could not keep a recovery draft. Save before closing this tab.",
      );
    }
  }
  useEffect(() => {
    const before = (e: BeforeUnloadEvent) => {
      if (changed) {
        e.preventDefault();
      }
    };
    window.addEventListener("beforeunload", before);
    return () => window.removeEventListener("beforeunload", before);
  }, [changed]);
  async function save() {
    setBusy(true);
    setMessage("");
    try {
      const document: MeetingDocument = {
        ...row.document,
        session: {
          ...row.document.session,
          title: title.trim() || "Untitled note",
          state: "noted",
          noteSource: "You",
        },
        note: text,
      };
      const r = await fetch("/api/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ document, expectedVersion: baseVersion }),
      });
      const body = await r.json();
      if (!r.ok) {
        if (r.status === 409) {
          const latest = await fetch(`/api/sessions/${row.id}`);
          if (latest.ok) setConflict(await latest.json());
        }
        throw new Error(body.error);
      }
      onSaved(body);
      setBaseVersion(body.version);
      setTitle(body.title);
      localStorage.removeItem(key);
      setEditing(false);
      setMessage("Saved. Your Mac will pick this up when it’s online.");
    } catch (e) {
      setMessage(
        e instanceof Error
          ? e.message
          : "Could not save. Your draft stays in this browser.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function pin() {
    if (busy || changed) return;
    setBusy(true);
    setMessage("");
    try {
      const document = {
        ...row.document,
        session: {
          ...row.document.session,
          pinned: !row.document.session.pinned,
        },
      };
      const r = await fetch("/api/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ document, expectedVersion: row.version }),
      });
      const body = await r.json();
      if (!r.ok) throw new Error(body.error || "Could not pin this note.");
      onSaved(body);
      setBaseVersion(body.version);
    } catch (e) {
      setMessage(
        e instanceof Error
          ? e.message
          : "Could not pin this note. Try again when you’re online.",
      );
    } finally {
      setBusy(false);
    }
  }
  function download() {
    const blob = new Blob([`# ${title}\n\n${text}`], { type: "text/markdown" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${title.replace(/[^a-z0-9 -]/gi, "") || "Meeting"}.md`;
    a.click();
    URL.revokeObjectURL(url);
  }
  return (
    <article className="document">
      <header className="document-toolbar">
        <button className="text-link" onClick={onBack}>
          <ChevronLeft size={17} />
          Notes
        </button>
        <div>
          <button
            className={
              "icon-button " + (row.document.session.pinned ? "is-pinned" : "")
            }
            aria-label={row.document.session.pinned ? "Unpin note" : "Pin note"}
            onClick={pin}
            disabled={changed || busy}
          >
            <Pin size={17} />
          </button>
          <button
            className="icon-button"
            aria-label="Copy note"
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(`# ${title}\n\n${text}`);
                setCopied(true);
                setTimeout(() => setCopied(false), 2000);
              } catch {
                setMessage(
                  "Copy was blocked by your browser. Select the note text to copy it.",
                );
              }
            }}
          >
            {copied ? <Check size={17} /> : <Copy size={17} />}
          </button>
          <button
            className="icon-button"
            aria-label="Download Markdown"
            onClick={download}
          >
            <Download size={17} />
          </button>
        </div>
      </header>
      <div className="document-inner">
        <div className="eyebrow">
          {date(row.started_at)}
          <span> · </span>
          {row.document.session.app || "Your notes"}
        </div>
        {editing ? (
          <input
            aria-label="Note title"
            className="title-input"
            disabled={busy}
            value={title}
            onChange={(e) => change(e.target.value, text)}
          />
        ) : (
          <h1>{title}</h1>
        )}
        <div className="document-meta">
          {row.document.session.speakers.join(" · ")}
          <span>
            {row.document.session.duration > 0
              ? duration(row.document.session.duration)
              : "Personal note"}
          </span>
          <span>Version {row.version}</span>
        </div>
        {row.document.session.booking && (
          <details className="workspace-card">
            <summary>
              Booking details · {row.document.session.booking.eventType}
            </summary>
            <p>
              {row.document.session.booking.guestName} ·{" "}
              {row.document.session.booking.guestEmail}
            </p>
            {row.document.session.booking.answers.map((answer, index) => (
              <div key={index}>
                <strong>{answer.question}</strong>
                <p>{answer.answer}</p>
              </div>
            ))}
            <p className="fine-print">
              Provided by the guest before the meeting.
            </p>
            {row.document.session.booking.bookingID && (
              <a
                className="text-link"
                href={`/scheduling?tab=Bookings&booking=${encodeURIComponent(row.document.session.booking.bookingID)}`}
              >
                Booking and follow-up messages
              </a>
            )}
          </details>
        )}
        <div className="document-tabs">
          <div className="tabs">
            <button
              className={tab === "note" ? "selected" : ""}
              onClick={() => setTab("note")}
            >
              Notes
            </button>
            <button
              className={tab === "transcript" ? "selected" : ""}
              onClick={() => setTab("transcript")}
            >
              Transcript <span>{row.document.transcript.length}</span>
            </button>
          </div>
          {tab === "note" &&
            (editing ? (
              <button
                className="button primary small"
                disabled={busy || !changed}
                onClick={save}
              >
                {busy ? "Saving…" : "Save note"}
                <Check size={15} />
              </button>
            ) : (
              <button className="button small" onClick={() => setEditing(true)}>
                Edit note
              </button>
            ))}
        </div>
        {message && (
          <p role="status" className="notice">
            {message}
          </p>
        )}
        {conflict && (
          <div className="conflict-actions">
            <button
              className="button small"
              onClick={() => {
                onSaved(conflict);
                setBaseVersion(conflict.version);
                try {
                  localStorage.setItem(
                    key,
                    JSON.stringify({
                      title,
                      text,
                      baseVersion: conflict.version,
                    }),
                  );
                } catch {}
                setConflict(null);
                setMessage(
                  "Your draft is ready to save as the next revision. The previous cloud version will be kept in history.",
                );
              }}
            >
              Keep my draft
            </button>
            <button
              className="button small"
              onClick={() => {
                onSaved(conflict);
                setTitle(conflict.title);
                setText(conflict.document.note || "");
                setBaseVersion(conflict.version);
                setConflict(null);
                localStorage.removeItem(key);
                setEditing(false);
                setMessage("Showing the cloud version.");
              }}
            >
              Use cloud version
            </button>
          </div>
        )}
        {tab === "note" ? (
          editing ? (
            <>
              <textarea
                className="note-editor"
                disabled={busy}
                aria-label="Meeting notes in Markdown"
                value={text}
                onChange={(e) => change(title, e.target.value)}
                placeholder="What’s on your mind? Markdown works here."
              />
              <p className="editor-hint">
                {changed
                  ? "Draft kept in this browser · save to sync it"
                  : "All changes saved"}
                <span>Markdown supported</span>
              </p>
            </>
          ) : (
            <div className="prose">
              <ReactMarkdown remarkPlugins={[remarkGfm]}>
                {text ||
                  "No written notes yet. Read the transcript or start writing."}
              </ReactMarkdown>
            </div>
          )
        ) : (
          <div className="transcript">
            <label className="search">
              <Search size={17} />
              <input
                aria-label="Search transcript"
                value={sourceQuery}
                onChange={(e) => setSourceQuery(e.target.value)}
                placeholder="Find a moment…"
              />
            </label>
            {row.document.transcript
              .filter((s) =>
                s.text.toLowerCase().includes(sourceQuery.toLowerCase()),
              )
              .map((s) => (
                <div className="transcript-segment" key={s.id}>
                  <time>{duration(s.start)}</time>
                  <div>
                    <strong>
                      {s.speaker || (s.source === "you" ? "You" : "Call")}
                    </strong>
                    <p>{s.text}</p>
                  </div>
                </div>
              ))}
            {!row.document.transcript.length && (
              <div className="empty">
                <p>This is a personal note. There’s no recorded transcript.</p>
              </div>
            )}
          </div>
        )}
      </div>
    </article>
  );
}
