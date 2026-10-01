"use client";
import { CalendarEditor } from "./calendar-editor";
import FullCalendar from "@fullcalendar/react";
import dayGridPlugin from "@fullcalendar/daygrid";
import timeGridPlugin from "@fullcalendar/timegrid";
import interactionPlugin from "@fullcalendar/interaction";
import type {WorkspaceEvent} from "@/lib/calendar-workspace";
import { DateField } from "./date-field";
import { useEffect, useMemo, useState, useRef } from "react";
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
        can_write?: boolean;
      }[]
    >([]),
    [source, setSource] = useState("");
  const [mounted, setMounted] = useState(false);
  const [events, setEvents] = useState<WorkspaceEvent[]>([]),
    [notes, setNotes] = useState<CloudSession[]>([]),
    [selected, setSelected] = useState<WorkspaceEvent | null>(null),
    [date, setDate] = useState(new Date()),
    [view, setView] = useState("Agenda"),
    [busy, setBusy] = useState(true),
    [error, setError] = useState(""),
    [query, setQuery] = useState(""),
    [connected, setConnected] = useState(false),
    [freshness, setFreshness] = useState(""),[pending,setPending]=useState(false);
  const requestVersion=useRef(0);
  const grid=useRef<FullCalendar>(null);
  const [creation,setCreation]=useState<{date:Date;end:Date;allDay:boolean} | null>(null);
  const [editing,setEditing]=useState<WorkspaceEvent | null | undefined>(undefined);
  async function load(refresh = false) {
    const version=++requestVersion.current;
    const first=new Date(date.getFullYear(),date.getMonth(),1);
    const from=view==="Month"?addDays(first,-((first.getDay()+6)%7)):new Date(date.getFullYear(),date.getMonth(),date.getDate());
    if(view==="Week"&&!home) from.setDate(from.getDate()-((from.getDay()+6)%7));
    const to=addDays(from,home || view==="Day"?1:view==="Month"?42:7);
    setBusy(true);
    setError("");
    try {
      const [r, n] = await Promise.all([
        fetch(`/api/calendar/events?${new URLSearchParams({from:from.toISOString(),to:to.toISOString(),...(refresh?{refresh:"1"}:{})})}`),
        fetch("/api/sessions?order=recent"),
      ]);
      const body = await r.json();
      if (!r.ok) throw new Error(body.error);
      if(version!==requestVersion.current) return;
      setPending(Boolean(body.pending));
      setEvents(body.events);
      setCalendars(body.calendars || []);
      setConnected(Boolean(body.connections?.length));
      setFreshness(body.failures?.map((c:{message:string})=>c.message).join(" · ") || "");
      if (n.ok) {
        const b = await n.json();
        setNotes(b.sessions.filter((s: CloudSession) => !s.deleted_at));
      }
    } catch (e) {
      if(version!==requestVersion.current) return;
      setError(
        e instanceof Error ? e.message : "Could not load your calendar.",
      );
    } finally {
      if(version===requestVersion.current) setBusy(false);
    }
  }
  useEffect(() => {
    setMounted(true);
    const id = new URLSearchParams(location.search).get("note");
    if (home && id) {
      location.replace(`/notes?note=${encodeURIComponent(id)}`);
      return;
    }
  }, []);
  useEffect(()=>{void load();const timer=setInterval(()=>{if(document.visibilityState==="visible") void load();},30000);const focus=()=>void load();window.addEventListener("focus",focus);return()=>{clearInterval(timer);window.removeEventListener("focus",focus);requestVersion.current++;};},[date,view,home]);
  useEffect(()=>{grid.current?.getApi().gotoDate(date);grid.current?.getApi().changeView(view==="Month"?"dayGridMonth":view==="Day"?"timeGridDay":"timeGridWeek");},[date,view]);
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
      [e.title,e.details?.description,e.details?.location,...e.attendees.map(a=>a.email || a.name)].filter(Boolean).join(" ").toLowerCase().includes(query.toLowerCase()) &&
      (!source || `${e.connection_id}|${e.calendar_id}` === source),
  );
  const noteFor = (e: WorkspaceEvent) =>
    notes.find(
      (n) =>
        n.document.session.calendarEventID === e.stable_id ||
        (e.legacy_id_unique===true && (n.document.session.calendarEventID === e.id || n.document.session.calendarEventID === `google-${e.id}`)),
    );
  async function prepare(e: WorkspaceEvent) {
    setError("");
    try {
      const document = newDocument(e.title);
      document.session.calendarEventID = e.stable_id;
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
          <h1>{home ? "Today" : "Calendar"}</h1>
          <p role="status">Loading your meetings…</p>
        </header>
      </Shell>
    );
  return (
    <Shell email={email}>
      <header className="page-header">
        <div className="heading-row">
          <div>
            <h1>{home ? "Today" : "Calendar"}</h1>
            <p>
              {home
                ? "Meetings and notes for your day."
                : "Your meetings, guest details and notes."}
            </p>
          </div>
          {!home && <button className="button primary" onClick={()=>{setCreation(null);setEditing(null);}}>New event</button>}
          <a className="button" href="murmur://cloud">
            Open Mac to record <ArrowUpRight size={16} />
          </a>
        </div>
      </header>
      {error && (
        <p className="notice" role="alert">
          {error} <button onClick={() => load()}>Try again</button>
        </p>
      )}
      {pending && <p className="muted" role="status">Updating calendars · downloaded events are shown.</p>}
      {freshness && (
        <p className="notice" role="status">
          Calendar needs attention. Cached meetings are shown. {freshness}{" "}
          <Link href="/connections">Reconnect</Link>
        </p>
      )}
      <div className={"calendar-layout" + (!home && view === "Month" ? " month-layout" : "")}>
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
          <div className="calendar-filters">
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
          </div>
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
          {!home && view!=="Agenda" && <FullCalendar ref={grid} plugins={[dayGridPlugin,timeGridPlugin,interactionPlugin]} initialDate={date} initialView={view==="Month"?"dayGridMonth":view==="Day"?"timeGridDay":"timeGridWeek"} headerToolbar={false} firstDay={1} height="70vh" scrollTime="08:00:00" scrollTimeReset={false} slotEventOverlap={false} eventMinHeight={24} eventShortHeight={32} slotLabelFormat={{hour:"numeric",minute:"2-digit",hour12:true}} dayHeaderFormat={{weekday:"short",day:"numeric"}} nowIndicator allDayText="All day" selectable eventClick={info=>setSelected(info.event.extendedProps.original)} select={info=>{setCreation({date:info.start,end:info.end,allDay:info.allDay});setEditing(null);}} events={filtered.map(e=>({id:e.stable_id,title:e.title,start:e.details?.all_day?e.details.start_date:e.starts_at,end:e.details?.all_day?e.details.end_date:e.ends_at,allDay:e.details?.all_day,extendedProps:{original:e}}))}/>}
          {(home || view==="Agenda") && <div
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
                (e) => new Date(e.ends_at)>new Date(d.getFullYear(),d.getMonth(),d.getDate()) && new Date(e.starts_at)<addDays(new Date(d.getFullYear(),d.getMonth(),d.getDate()),1),
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
                        key={e.stable_id}
                        onClick={() => setSelected(e)}
                      >
                        <span className="meeting-time">
                          {e.details?.all_day?"All day":time(e.starts_at)}{!e.details?.all_day && (view !== "Month" || home) ? `–${time(e.ends_at)}` : ""}
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
          </div>}
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
                      (e) => new Date(e.ends_at)>new Date(d.getFullYear(),d.getMonth(),d.getDate()) && new Date(e.starts_at)<addDays(new Date(d.getFullYear(),d.getMonth(),d.getDate()),1),
                    ) && <span className="calendar-dot" />}
                  </button>
                ),
              )}
            </div>
          </section>
          <section className="workspace-card">
            <h3>Your booking page</h3>
            <p>Manage meeting types and availability.</p>
            <Link className="text-link" href="/scheduling">
              Manage booking links <ArrowUpRight size={14} />
            </Link>
          </section>
        </aside>
      </div>
      {editing!==undefined && <CalendarEditor event={editing || undefined} date={creation?.date || date} endDate={creation?.end} allDayDefault={creation?.allDay} calendars={calendars} onClose={()=>setEditing(undefined)} onSaved={()=>{setEditing(undefined);setSelected(null);void load(true);}}/>}
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
          <p>{calendars.find(c=>c.connection_id===selected.connection_id&&c.calendar_id===selected.calendar_id)?.name}</p>
          {selected.details?.location && <p>{selected.details.location}</p>}
          {selected.details?.description && <p className="event-description">{selected.details.description}</p>}
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
            {calendars.some(c=>c.connection_id===selected.connection_id&&c.calendar_id===selected.calendar_id&&c.can_write) && <button className="button" onClick={()=>{setEditing(selected);setSelected(null);}}>Edit event</button>}
            {selected.details?.response && <label className="field"><span>Your response</span><select value={selected.details.response} onChange={async e=>{try{const r=await fetch("/api/calendar/events",{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({connection_id:selected.connection_id,calendar_id:selected.calendar_id,id:selected.id,etag:selected.details.etag,response:e.target.value})});const b=await r.json();if(!r.ok) throw new Error(b.error);setSelected(null);void load(true);}catch(e){setError((e as Error).message);}}}><option value="needsAction">No response</option><option value="accepted">Yes</option><option value="tentative">Maybe</option><option value="declined">No</option></select></label>}
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
