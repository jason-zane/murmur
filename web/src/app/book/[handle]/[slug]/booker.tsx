"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  ArrowLeft,
  ArrowUpRight,
  CalendarCheck,
  Check,
  ChevronLeft,
  ChevronRight,
  Clock,
  Copy,
  Globe,
  LoaderCircle,
  MapPin,
  Phone,
  Video,
} from "lucide-react";

type Question = { id: string; label: string; required: boolean; long: boolean };
type Location = "google_meet" | "video_link" | "in_person" | "phone";
const LOCATION = {
  google_meet: ["Google Meet", Video],
  video_link: ["Video call", Video],
  in_person: ["In person", MapPin],
  phone: ["Phone call", Phone],
} as const;
const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const ymd = (d: Date, timeZone: string) =>
  new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
const clock = (d: Date, timeZone: string) =>
  new Intl.DateTimeFormat(undefined, { timeZone, hour: "numeric", minute: "2-digit" }).format(d);
const longDate = (d: Date, timeZone: string) =>
  new Intl.DateTimeFormat(undefined, { timeZone, weekday: "long", month: "long", day: "numeric" }).format(d);

type Done = { starts_at: string; ends_at: string; meeting_url: string | null; location?: string; manage_url?: string };

export function Booker(props: {
  handle: string;
  slug: string;
  host: string;
  title: string;
  description: string;
  duration: number;
  location: Location;
  questions: Question[];
}) {
  const [timeZone, setTimeZone] = useState("UTC");
  const [zones, setZones] = useState<string[]>([]);
  const [month, setMonth] = useState<{ y: number; m: number } | null>(null);
  const [slots, setSlots] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [day, setDay] = useState<string | null>(null);
  const [slot, setSlot] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<Done | null>(null);
  const [reschedule, setReschedule] = useState<{ id: string; token: string } | null>(null);
  const [copied, setCopied] = useState(false);
  const [Icon, placeLabel] = [LOCATION[props.location][1], LOCATION[props.location][0]];

  useEffect(() => {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
    setTimeZone(zone);
    try {
      setZones(Intl.supportedValuesOf("timeZone"));
    } catch {}
    const [y, m] = ymd(new Date(), zone).split("-").map(Number);
    setMonth({ y, m: m - 1 });
    const id = new URLSearchParams(location.search).get("reschedule");
    const token = location.hash.slice(1);
    if (id && token) setReschedule({ id, token });
  }, []);

  const load = useCallback(async () => {
    if (!month) return;
    setLoading(true);
    setError("");
    // A day in any time zone falls inside the month plus 14 hours either side.
    const from = new Date(Date.UTC(month.y, month.m, 1) - 14 * 3600e3);
    const to = new Date(Date.UTC(month.y, month.m + 1, 1) + 14 * 3600e3);
    try {
      const r = await fetch(
        `/api/book/${encodeURIComponent(props.handle)}/${encodeURIComponent(props.slug)}?${new URLSearchParams({
          from: from.toISOString(),
          to: to.toISOString(),
          timeZone,
        })}`,
      );
      const body = await r.json();
      if (!r.ok) throw new Error(body.error);
      setSlots(body.slots);
    } catch (e) {
      setSlots([]);
      setError(e instanceof Error ? e.message : "Open times couldn’t be loaded. Try again.");
    } finally {
      setLoading(false);
    }
  }, [month, timeZone, props.handle, props.slug]);
  useEffect(() => {
    void load();
  }, [load]);

  const byDay = useMemo(() => {
    const map = new Map<string, string[]>();
    if (!month) return map;
    const prefix = `${month.y}-${String(month.m + 1).padStart(2, "0")}`;
    for (const s of slots) {
      const key = ymd(new Date(s), timeZone);
      if (!key.startsWith(prefix)) continue;
      map.set(key, [...(map.get(key) ?? []), s]);
    }
    return map;
  }, [slots, timeZone, month]);
  useEffect(() => {
    if (!day || !byDay.has(day)) setDay([...byDay.keys()].sort()[0] ?? null);
  }, [byDay, day]);

  if (!month) return <section className="book-card" aria-busy="true" />;
  const today = ymd(new Date(), timeZone);
  const [ty, tm] = today.split("-").map(Number);
  const first = new Date(Date.UTC(month.y, month.m, 1)).getUTCDay();
  const length = new Date(Date.UTC(month.y, month.m + 1, 0)).getUTCDate();
  const cells: (string | null)[] = [
    ...Array((first + 6) % 7).fill(null),
    ...Array.from({ length }, (_, i) => `${month.y}-${String(month.m + 1).padStart(2, "0")}-${String(i + 1).padStart(2, "0")}`),
  ];
  const monthLabel = new Intl.DateTimeFormat(undefined, { month: "long", year: "numeric", timeZone: "UTC" }).format(
    new Date(Date.UTC(month.y, month.m, 1)),
  );
  const atCurrentMonth = month.y === ty && month.m === tm - 1;
  const move = (delta: number) => {
    const d = new Date(Date.UTC(month.y, month.m + delta, 1));
    setMonth({ y: d.getUTCFullYear(), m: d.getUTCMonth() });
    setDay(null);
    setSlot(null);
  };

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!slot) return;
    setBusy(true);
    setError("");
    try {
      const r = reschedule
        ? await fetch(`/api/book/manage/${reschedule.id}`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ action: "reschedule", token: reschedule.token, start: slot, time_zone: timeZone }),
          })
        : await fetch(`/api/book/${encodeURIComponent(props.handle)}/${encodeURIComponent(props.slug)}`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              start: slot,
              name,
              email,
              time_zone: timeZone,
              ...(props.location === "phone" ? { phone } : {}),
              answers,
            }),
          });
      const body = await r.json();
      if (!r.ok) {
        if (r.status === 409) {
          setSlot(null);
          void load();
        }
        throw new Error(body.error);
      }
      setDone(body);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Your booking couldn’t be completed. Try again.");
    } finally {
      setBusy(false);
    }
  }

  const summary = (
    <aside className="book-summary">
      <span className="eyebrow">{props.host.toUpperCase()}</span>
      <h1>{props.title}</h1>
      <p className="book-fact">
        <Clock size={15} />
        {props.duration} minutes
      </p>
      <p className="book-fact">
        <Icon size={15} />
        {placeLabel}
      </p>
      {slot && (
        <p className="book-fact chosen">
          <CalendarCheck size={15} />
          {longDate(new Date(slot), timeZone)}, {clock(new Date(slot), timeZone)}
        </p>
      )}
      {props.description && <p className="book-description">{props.description}</p>}
    </aside>
  );

  if (done) {
    const start = new Date(done.starts_at);
    return (
      <section className="book-card book-done" aria-live="polite">
        <span className="done-mark">
          <Check size={22} />
        </span>
        <h1>{reschedule ? "Your meeting has moved." : "You’re booked."}</h1>
        <p className="book-lede">
          {props.title} with {props.host}
          <br />
          <strong>
            {longDate(start, timeZone)}, {clock(start, timeZone)}–{clock(new Date(done.ends_at), timeZone)}
          </strong>
          <br />
          <span className="muted">{timeZone.replace(/_/g, " ")}</span>
        </p>
        <p className="book-lede">
          {reschedule
            ? `${props.host}’s calendar has sent you an updated invitation.`
            : `An invitation from ${props.host}’s calendar is on its way to ${email}.`}
        </p>
        {done.meeting_url && (
          <a className="button primary" href={done.meeting_url} target="_blank" rel="noreferrer">
            Meeting link
            <ArrowUpRight size={16} />
          </a>
        )}
        {done.manage_url && (
          <div className="manage-copy">
            <p className="fine-print">Keep this private link to reschedule or cancel.</p>
            <button
              className="text-link"
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(done.manage_url!);
                  setCopied(true);
                } catch {}
              }}
            >
              {copied ? <Check size={14} /> : <Copy size={14} />}
              {copied ? "Link copied" : "Copy link to change this booking"}
            </button>
          </div>
        )}
      </section>
    );
  }

  return (
    <section className={slot ? "book-card with-form" : "book-card"}>
      {summary}
      {slot ? (
        <form className="book-form" onSubmit={submit}>
          <button type="button" className="text-link" onClick={() => setSlot(null)}>
            <ArrowLeft size={14} />
            Choose another time
          </button>
          {reschedule ? (
            <p className="book-lede">Move your booking to this time? {props.host}’s calendar will send you an updated invitation.</p>
          ) : (
            <>
              <label className="field">
                <span>Your name</span>
                <input required value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" maxLength={120} />
              </label>
              <label className="field">
                <span>Email</span>
                <input required type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" maxLength={320} />
              </label>
              {props.location === "phone" && (
                <label className="field">
                  <span>Phone number</span>
                  <input required type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} autoComplete="tel" maxLength={40} />
                </label>
              )}
              {props.questions.map((q) => (
                <label className="field" key={q.id}>
                  <span>
                    {q.label}
                    {!q.required && <small> Optional</small>}
                  </span>
                  {q.long ? (
                    <textarea
                      rows={3}
                      required={q.required}
                      maxLength={2000}
                      value={answers[q.id] ?? ""}
                      onChange={(e) => setAnswers({ ...answers, [q.id]: e.target.value })}
                    />
                  ) : (
                    <input
                      required={q.required}
                      maxLength={2000}
                      value={answers[q.id] ?? ""}
                      onChange={(e) => setAnswers({ ...answers, [q.id]: e.target.value })}
                    />
                  )}
                </label>
              ))}
            </>
          )}
          {error && <p className="notice" role="alert">{error}</p>}
          <button className="button primary wide" disabled={busy}>
            {busy && <LoaderCircle className="spin" size={16} />}
            {reschedule ? "Move my booking" : "Confirm booking"}
          </button>
          {!reschedule && (
            <p className="fine-print">
              Your details go to {props.host}. The invitation comes from their calendar.
            </p>
          )}
        </form>
      ) : (
        <>
          <div className="book-calendar">
            <div className="month-head">
              <h2>{monthLabel}</h2>
              <span>
                <button className="icon-button" aria-label="Previous month" disabled={atCurrentMonth} onClick={() => move(-1)}>
                  <ChevronLeft size={18} />
                </button>
                <button className="icon-button" aria-label="Next month" onClick={() => move(1)}>
                  <ChevronRight size={18} />
                </button>
              </span>
            </div>
            <div className="month-grid" role="grid" aria-label={monthLabel}>
              {WEEKDAYS.map((w) => (
                <span key={w} className="weekday">
                  {w}
                </span>
              ))}
              {cells.map((d, i) =>
                d ? (
                  <button
                    key={d}
                    className={[
                      "day",
                      byDay.has(d) ? "open" : "",
                      d === day ? "selected" : "",
                      d === today ? "today" : "",
                    ].join(" ")}
                    disabled={!byDay.has(d)}
                    aria-pressed={d === day}
                    aria-label={`${d}${byDay.has(d) ? `, ${byDay.get(d)!.length} times` : ", unavailable"}`}
                    onClick={() => setDay(d)}
                  >
                    {Number(d.slice(8))}
                  </button>
                ) : (
                  <span key={`blank-${i}`} />
                ),
              )}
            </div>
            <label className="zone">
              <Globe size={14} />
              <select value={timeZone} onChange={(e) => setTimeZone(e.target.value)} aria-label="Time zone">
                {(zones.length ? zones : [timeZone]).map((z) => (
                  <option key={z} value={z}>
                    {z.replace(/_/g, " ")}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <div className="book-times">
            {loading ? (
              <p className="muted" role="status">
                <LoaderCircle className="spin" size={15} /> Finding open times…
              </p>
            ) : error ? (
              <p className="notice" role="alert">
                {error}
              </p>
            ) : day ? (
              <>
                <h2>{longDate(new Date(byDay.get(day)![0]), timeZone)}</h2>
                <div className="slot-list">
                  {byDay.get(day)!.map((s) => (
                    <button key={s} className="slot" onClick={() => setSlot(s)}>
                      {clock(new Date(s), timeZone)}
                    </button>
                  ))}
                </div>
              </>
            ) : (
              <p className="muted">No open times this month. Try the next month.</p>
            )}
            {reschedule && (
              <p className="fine-print">
                Choosing a new time for an existing booking. <Link href={`/book/manage/${reschedule.id}#${reschedule.token}`}>Back to your booking</Link>
              </p>
            )}
          </div>
        </>
      )}
    </section>
  );
}
