"use client";
import { DateField } from "./date-field";
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  ArrowUpRight,
  RefreshCw,
  FileText,
  X,
} from "lucide-react";
import { Dialog } from "./dialog";
import { Shell } from "./shell";
import {
  newDocument,
  meetingURL,
  type CalendarMeeting,
  type CloudSession,
} from "@/lib/documents";
const dayKey = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const addDays = (d: Date, n: number) => {
  const v = new Date(d);
  v.setDate(v.getDate() + n);
  return v;
};
const time = (s: string) =>
  new Date(s).toLocaleTimeString(undefined, {
    hour: "numeric",
    minute: "2-digit",
  });
export function MeetingWorkspace({
  email,
  home = false,
}: {
  email: string;
  home?: boolean;
}) {
  const [calendars, setCalendars] = useState<
      {
        connection_id: string;
        calendar_id: string;
        name: string;
        selected: boolean;
      }[]
    >([]),
    [source, setSource] = useState("");
  const [mounted, setMounted] = useState(false);
  const [events, setEvents] = useState<CalendarMeeting[]>([]),
    [notes, setNotes] = useState<CloudSession[]>([]),
    [selected, setSelected] = useState<CalendarMeeting | null>(null),
    [date, setDate] = useState(new Date()),
    [view, setView] = useState("Agenda"),
    [busy, setBusy] = useState(true),
    [error, setError] = useState(""),
    [query, setQuery] = useState(""),
    [connected, setConnected] = useState(false),
    [freshness, setFreshness] = useState("");
  async function load(refresh = false) {
    setBusy(true);
    setError("");
    try {
      const [r, n] = await Promise.all([
        fetch("/api/calendar?workspace=1", {
          method: refresh ? "POST" : "GET",
        }),
        fetch("/api/sessions?order=recent"),
      ]);
      const body = await r.json();
      if (!r.ok) throw new Error(body.error);
      setEvents(body.events);
      setCalendars(body.calendars || []);
      setConnected(Boolean(body.connections?.length));
      setFreshness(
        body.connections
          ?.filter((c: { error: string }) => c.error)
          .map(
            (c: { email: string; error: string }) => `${c.email}: ${c.error}`,
          )
          .join(" · ") || "",
      );
      if (n.ok) {
        const b = await n.json();
        setNotes(b.sessions.filter((s: CloudSession) => !s.deleted_at));
      }
    } catch (e) {
      setError(
        e instanceof Error ? e.message : "Could not load your calendar.",
      );
    } finally {
      setBusy(false);
    }
  }
  useEffect(() => {
    setMounted(true);
    const id = new URLSearchParams(location.search).get("note");
    if (home && id) {
      location.replace(`/notes?note=${encodeURIComponent(id)}`);
      return;
    }
    void load();
  }, []);
  const days = useMemo(() => {
    const first = new Date(date.getFullYear(), date.getMonth(), 1);
    const start = !home && view === "Month" ? addDays(first, -((first.getDay() + 6) % 7)) : date;
    return Array.from({ length: home || view === "Day" ? 1 : view === "Month" ? 42 : 7 }, (_, i) => addDays(start, i));
  }, [date, view, home]);
  function shiftDate(direction: number) {
    setDate(!home && view === "Month"
      ? new Date(date.getFullYear(), date.getMonth() + direction, 1)
      : addDays(date, direction * (home || view === "Day" ? 1 : 7)));
  }
  const filtered = events.filter(
    (e) =>
      e.title.toLowerCase().includes(query.toLowerCase()) &&
      (!source || `${e.connection_id}|${e.calendar_id}` === source),
  );
  const noteFor = (e: CalendarMeeting) =>
    notes.find(
      (n) =>
        n.document.session.calendarEventID === e.id ||
        n.document.session.calendarEventID === `google-${e.id}`,
    );
  async function prepare(e: CalendarMeeting) {
    setError("");
    try {
      const document = newDocument(e.title);
      document.session.calendarEventID = `google-${e.id}`;
      document.session.attendees = e.attendees;
      if (e.booking) {
        document.session.booking = {
          bookingID: e.booking.id,
          eventType: e.booking.event_type,
          guestName: e.booking.guest_name,
          guestEmail: e.booking.guest_email,
          answers: e.booking.answers,
        };
        document.session.summaryTemplate = e.booking.template;
      }
      const r = await fetch("/api/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ document, expectedVersion: 0 }),
      });
      const b = await r.json();
      if (!r.ok) throw new Error(b.error);
      location.assign(`/notes?note=${encodeURIComponent(b.id)}`);
    } catch (e) {
      setError((e as Error).message);
      setSelected(null);
    }
  }
  const month = new Date(date.getFullYear(), date.getMonth(), 1);
  const gridStart = addDays(month, -((month.getDay() + 6) % 7));
  if (!mounted)
    return (
      <Shell email={email}>
        <header className="page-header">
          <h1>{home ? "Home" : "Calendar"}</h1>
          <p role="status">Loading your meetings…</p>
        </header>
      </Shell>
    );
  return (
    <Shell email={email}>
      <header className="page-header">
        <div className="heading-row">
          <div>
            <h1>{home ? "Home" : "Calendar"}</h1>
            <p>
              {home
                ? "Meetings and notes for your day."
                : "Your meetings, guest details and notes."}
            </p>
          </div>
          <a className="button primary" href="murmur://cloud">
            Open Mac to record <ArrowUpRight size={16} />
          </a>
        </div>
      </header>
      {error && (
        <p className="notice" role="alert">
          {error} <button onClick={() => load()}>Try again</button>
        </p>
      )}
      {freshness && (
        <p className="notice" role="status">
          Calendar needs attention. Cached meetings are shown. {freshness}{" "}
          <Link href="/connections">Reconnect</Link>
        </p>
      )}
      <div className="calendar-layout">
        <section className="calendar-main">
          <div className="calendar-toolbar">
            <div className="button-group">
              <button
                className="icon-button"
                aria-label="Previous period"
                onClick={() =>
                  shiftDate(-1)
                }
              >
                <ChevronLeft size={18} />
              </button>
              <button
                className="button small"
                onClick={() => setDate(new Date())}
              >
                Today
              </button>
              <button
                className="icon-button"
                aria-label="Next period"
                onClick={() =>
                  shiftDate(1)
                }
              >
                <ChevronRight size={18} />
              </button>
            </div>
            <DateField value={dayKey(date)} label="Go to date" onChange={(value) => {
              if (value) setDate(new Date(`${value}T12:00:00`));
            }} />
            {!home && (
              <div className="tabs" aria-label="Calendar view">
                {["Agenda", "Day", "Week", "Month"].map((v) => (
                  <button
                    key={v}
                    aria-pressed={view === v}
                    className={v === view ? "selected" : ""}
                    onClick={() => setView(v)}
                  >
                    {v}
                  </button>
                ))}
              </div>
            )}
            <button
              className="icon-button"
              aria-label="Refresh calendar"
              disabled={busy}
              onClick={() => load(true)}
            >
              <RefreshCw size={16} className={busy ? "spin" : ""} />
            </button>
          </div>
          {!home && (
            <label className="field calendar-filter">
              <span>Calendar</span>
              <select
                value={source}
                onChange={(e) => setSource(e.target.value)}
              >
                <option value="">All selected calendars</option>
                {calendars
                  .filter((c) => c.selected)
                  .map((c) => (
                    <option
                      key={`${c.connection_id}|${c.calendar_id}`}
                      value={`${c.connection_id}|${c.calendar_id}`}
                    >
                      {c.name}
                    </option>
                  ))}
              </select>
            </label>
          )}
          {!home && (
            <label className="search">
              <input
                aria-label="Search meetings"
                placeholder="Search meetings"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
              />
            </label>
          )}
          {busy && (
            <p className="muted" role="status">
              Loading meetings…
            </p>
          )}
          {!connected && !busy && (
            <div className="empty">
              <CalendarDays size={28} />
              <h2>Bring your calendars together</h2>
              <p>
                Connect your account to prepare for meetings and keep your
                booking links available at the right times.
              </p>
              <Link href="/connections" className="button">
                Connect calendar
              </Link>
            </div>
          )}
          {!home && view === "Month" && <h2 className="month-heading">{date.toLocaleDateString("en-AU", { month: "long", year: "numeric" })}</h2>}
          <div
            className={
              !home && view === "Month" ? "calendar-month" : view === "Week" && !home ? "calendar-week" : "calendar-agenda"
            }
          >
            {!home && view === "Month" && ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map(day => <div className="month-weekday" key={day}>{day}</div>)}
            {!busy && connected && !home && view === "Agenda" && !days.some(day => filtered.some(event => dayKey(new Date(event.starts_at)) === dayKey(day))) && (
              <p className="calendar-free">{query ? "No matching meetings. Try a different search." : "No meetings this week. Choose another date to see your meetings."}</p>
            )}
            {days.map((d) => {
              const es = filtered.filter(
                (e) => dayKey(new Date(e.starts_at)) === dayKey(d),
              );
              if (!home && view === "Agenda" && !es.length) return null;
              return (
                <section className={"calendar-day" + (!home && view === "Month" && d.getMonth() !== date.getMonth() ? " outside-month" : "")} key={dayKey(d)}>
                  {!home && view === "Month" ? <button className={"month-date" + (dayKey(d) === dayKey(new Date()) ? " today" : "")} aria-label={d.toLocaleDateString("en-AU", {weekday: "long", day: "numeric", month: "long"})} onClick={() => {setDate(d); setView("Day");}}>{d.getDate()}</button> : <h3>
                    {d.toLocaleDateString(undefined, {
                      weekday: "short",
                      day: "numeric",
                      month: "short",
                    })}
                  </h3>}
                  {es.length ? (
                    (!home && view === "Month" ? es.slice(0, 3) : es).map((e) => (
                      <button
                        className="meeting-card"
                        key={`${e.id}-${e.starts_at}`}
                        onClick={() => setSelected(e)}
                      >
                        <span className="meeting-time">
                          {time(e.starts_at)}{view !== "Month" || home ? `–${time(e.ends_at)}` : ""}
                        </span>
                        <strong>{e.title}</strong>
                        <span className="meeting-context">
                          {e.booking
                            ? `${e.booking.guest_name} · Booked`
                            : e.attendees
                                .slice(0, 2)
                                .map((a) => a.name)
                                .join(", ")}
                        </span>
                        {noteFor(e) && (
                          <span className="accent">Note ready</span>
                        )}
                      </button>
                    ))
                  ) : (
                    view !== "Month" || home ? <p className="calendar-free">No meetings</p> : null
                  )}
                  {!home && view === "Month" && es.length > 3 && <button className="month-more" onClick={() => { setDate(d); setView("Day"); }}>+{es.length - 3} more</button>}
                </section>
              );
            })}
          </div>
          {!home && (
            <p className="fine-print">
              Times in {Intl.DateTimeFormat().resolvedOptions().timeZone}.
              Connected meetings are cached for the previous and next 90 days.
            </p>
          )}
          {home && (
            <section className="settings-section">
              <div className="heading-row">
                <h2>Recent notes</h2>
                <Link className="text-link" href="/notes">
                  All notes <ArrowUpRight size={15} />
                </Link>
              </div>
              {notes.slice(0, 4).map((n) => (
                <Link
                  className="recent-note"
                  key={n.id}
                  href={`/notes?note=${encodeURIComponent(n.id)}`}
                >
                  <FileText size={17} />
                  <span>{n.title}</span>
                  <small>{new Date(n.started_at).toLocaleDateString()}</small>
                </Link>
              ))}
              {!notes.length && (
                <p className="muted">
                  Your notes will appear here after you write or record a
                  meeting.
                </p>
              )}
            </section>
          )}
        </section>
        <aside className="calendar-aside">
          <section className="mini-month">
            <div className="heading-row">
              <button
                className="icon-button"
                aria-label="Previous month"
                onClick={() =>
                  setDate(new Date(date.getFullYear(), date.getMonth() - 1, 1))
                }
              >
                <ChevronLeft size={16} />
              </button>
              <strong>
                {month.toLocaleDateString(undefined, {
                  month: "long",
                  year: "numeric",
                })}
              </strong>
              <button
                className="icon-button"
                aria-label="Next month"
                onClick={() =>
                  setDate(new Date(date.getFullYear(), date.getMonth() + 1, 1))
                }
              >
                <ChevronRight size={16} />
              </button>
            </div>
            <div className="month-grid">
              {["M", "T", "W", "T", "F", "S", "S"].map((s, i) => (
                <small key={i}>{s}</small>
              ))}
              {Array.from({ length: 42 }, (_, i) => addDays(gridStart, i)).map(
                (d) => (
                  <button
                    key={dayKey(d)}
                    className={
                      dayKey(d) === dayKey(date)
                        ? "selected"
                        : d.getMonth() !== date.getMonth()
                          ? "muted"
                          : ""
                    }
                    aria-label={d.toDateString()}
                    aria-pressed={dayKey(d) === dayKey(date)}
                    onClick={() => setDate(d)}
                  >
                    {d.getDate()}
                    {events.some(
                      (e) => dayKey(new Date(e.starts_at)) === dayKey(d),
                    ) && <span className="calendar-dot" />}
                  </button>
                ),
              )}
            </div>
          </section>
          <section className="workspace-card">
            <h3>Your booking page</h3>
            <p>Make space for the meetings that matter.</p>
            <Link className="text-link" href="/scheduling">
              Manage booking links <ArrowUpRight size={14} />
            </Link>
          </section>
        </aside>
      </div>
      {selected && (
        <Dialog label="Meeting details" onClose={() => setSelected(null)}>
          <div className="heading-row">
            <span className="eyebrow">
              {selected.booking ? "BOOKED MEETING" : "CALENDAR MEETING"}
            </span>
            <button
              autoFocus
              className="icon-button"
              aria-label="Close meeting"
              onClick={() => setSelected(null)}
            >
              <X size={18} />
            </button>
          </div>
          <h2>{selected.title}</h2>
          <p>
            {new Date(selected.starts_at).toLocaleString()} –{" "}
            {time(selected.ends_at)}
          </p>
          <p>{selected.attendees.map((a) => a.name).join(", ")}</p>
          {selected.booking && (
            <>
              <p>Notes template: {selected.booking.template}</p>
              <h3>Guest answers</h3>
              <dl className="answers">
                {selected.booking.answers.map((a) => (
                  <div key={a.question}>
                    <dt>{a.question}</dt>
                    <dd>{a.answer}</dd>
                  </div>
                ))}
              </dl>
              <Link
                className="button"
                href={`/scheduling?tab=Bookings&booking=${selected.booking.id}`}
              >
                Manage booking and messages
              </Link>
            </>
          )}
          <div className="form-actions">
            {meetingURL(selected.meeting_url) && (
              <a
                className="button primary"
                href={meetingURL(selected.meeting_url)!}
                target="_blank"
                rel="noreferrer"
              >
                Join meeting <ArrowUpRight size={16} />
              </a>
            )}
            {!noteFor(selected) && (
              <button className="button" onClick={() => prepare(selected)}>
                Prepare a note
              </button>
            )}
            {noteFor(selected) && (
              <Link
                className="button"
                href={`/notes?note=${encodeURIComponent(noteFor(selected)!.id)}`}
              >
                Open note
              </Link>
            )}
          </div>
        </Dialog>
      )}
    </Shell>
  );
}
