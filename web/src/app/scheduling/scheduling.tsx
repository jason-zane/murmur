"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  ArrowUpRight,
  Check,
  Copy,
  LoaderCircle,
  MapPin,
  Pencil,
  Phone,
  Plus,
  Trash2,
  Video,
  X,
} from "lucide-react";
import { Shell } from "@/components/shell";

type Question = { id: string; label: string; required: boolean; long: boolean };
type EventType = {
  id?: string;
  slug: string;
  title: string;
  description: string;
  duration_minutes: number;
  location_kind: "google_meet" | "video_link" | "in_person" | "phone";
  location_detail: string | null;
  summary_template: "meeting" | "oneOnOne" | "standup" | "interview";
  questions: Question[];
  minimum_notice_minutes: number;
  buffer_before_minutes: number;
  buffer_after_minutes: number;
  slot_interval_minutes: number | null;
  booking_window_days: number;
  daily_limit: number | null;
  active: boolean;
  position: number;
};
type Hours = { days: number[]; start: string; end: string }[];
type Override = { date: string; ranges: { start: string; end: string }[] };
type Profile = {
  handle: string;
  display_name: string;
  time_zone: string;
  weekly_hours: Hours;
  date_overrides: Override[];
  destination_connection_id: string | null;
  destination_calendar_id: string | null;
};
type Booking = {
  id: string;
  title: string;
  status: string;
  starts_at: string;
  ends_at: string;
  guest_name: string;
  guest_email: string;
  guest_time_zone: string;
  answers: { question: string; answer: string }[];
  meeting_url: string | null;
};
type Data = {
  profile: Profile | null;
  types: EventType[];
  bookings: Booking[];
  accounts: { id: string; email: string | null; can_book: boolean }[];
  calendars: {
    connection_id: string;
    calendar_id: string;
    name: string;
    is_primary: boolean;
    can_write: boolean;
  }[];
  base_url: string;
};

const DAYS: [string, number][] = [
  ["Monday", 1],
  ["Tuesday", 2],
  ["Wednesday", 3],
  ["Thursday", 4],
  ["Friday", 5],
  ["Saturday", 6],
  ["Sunday", 0],
];
const TEMPLATES = { meeting: "Meeting", oneOnOne: "1:1", standup: "Stand-up", interview: "Interview" };
const LOCATIONS = {
  google_meet: ["Google Meet", Video],
  video_link: ["Your video link", Video],
  in_person: ["In person", MapPin],
  phone: ["Phone call", Phone],
} as const;
const slugify = (value: string) =>
  value
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 50) || "meeting";
const blankType = (position: number): EventType => ({
  slug: "intro-call",
  title: "Intro call",
  description: "",
  duration_minutes: 30,
  location_kind: "google_meet",
  location_detail: null,
  summary_template: "meeting",
  questions: [{ id: "topic", label: "What would you like to talk about?", required: false, long: true }],
  minimum_notice_minutes: 240,
  buffer_before_minutes: 0,
  buffer_after_minutes: 0,
  slot_interval_minutes: null,
  booking_window_days: 60,
  daily_limit: null,
  active: true,
  position,
});
function dayMap(hours: Hours) {
  const map = new Map<number, { start: string; end: string }>();
  for (const block of hours) for (const d of block.days) if (!map.has(d)) map.set(d, { start: block.start, end: block.end });
  return map;
}
function fromDayMap(map: Map<number, { start: string; end: string }>): Hours {
  const groups = new Map<string, number[]>();
  for (const [day, r] of map) groups.set(`${r.start}-${r.end}`, [...(groups.get(`${r.start}-${r.end}`) ?? []), day]);
  return [...groups].map(([key, days]) => {
    const [start, end] = key.split("-");
    return { days: days.sort(), start, end };
  });
}
const when = (value: string) =>
  new Date(value).toLocaleString(undefined, {
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });

async function send(url: string, method: string, body?: unknown) {
  const r = await fetch(url, {
    method,
    headers: body === undefined ? undefined : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const result = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(result.error || "Something went wrong. Try again.");
  return result;
}

function CopyLink({ url }: { url: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="url-copy">
      <code>{url}</code>
      <button
        aria-label="Copy booking link"
        onClick={async () => {
          try {
            await navigator.clipboard.writeText(url);
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
          } catch {}
        }}
      >
        {copied ? <Check size={17} /> : <Copy size={17} />}
        <span>{copied ? "Copied" : "Copy link"}</span>
      </button>
    </div>
  );
}

export function Scheduling({ email, googleReady }: { email: string; googleReady: boolean }) {
  const [data, setData] = useState<Data | null>(null);
  const [message, setMessage] = useState("");
  const [profile, setProfile] = useState<Profile | null>(null);
  const [saving, setSaving] = useState(false);
  const [editing, setEditing] = useState<EventType | null>(null);
  const [zones, setZones] = useState<string[]>([]);

  const load = useCallback(async () => {
    try {
      const body: Data = await send("/api/scheduling", "GET");
      setData(body);
      const zone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
      const local = email.split("@")[0] || "me";
      const target =
        body.calendars.find((c) => c.can_write && c.is_primary && body.accounts.find((a) => a.id === c.connection_id)?.can_book) ??
        body.calendars.find((c) => c.can_write && body.accounts.find((a) => a.id === c.connection_id)?.can_book);
      setProfile(
        body.profile ?? {
          handle: slugify(local).slice(0, 40).padEnd(3, "0"),
          display_name: local.replace(/[._-]+/g, " ").replace(/\b\w/g, (c) => c.toUpperCase()),
          time_zone: zone,
          weekly_hours: [{ days: [1, 2, 3, 4, 5], start: "09:00", end: "17:00" }],
          date_overrides: [],
          destination_connection_id: target?.connection_id ?? null,
          destination_calendar_id: target?.calendar_id ?? null,
        },
      );
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Booking settings couldn't be loaded.");
    }
  }, [email]);

  useEffect(() => {
    void load();
    try {
      setZones(Intl.supportedValuesOf("timeZone"));
    } catch {}
    const p = new URLSearchParams(location.search);
    if (p.get("error")) setMessage(p.get("error")!);
    if (p.get("connected")) setMessage("Booking is allowed on your calendar. Invitations will come from your own account.");
  }, [load]);

  const bookable = data?.accounts.some((a) => a.can_book) ?? false;
  const destinations = useMemo(
    () =>
      (data?.calendars ?? []).filter(
        (c) => c.can_write && data?.accounts.find((a) => a.id === c.connection_id)?.can_book,
      ),
    [data],
  );
  const live =
    Boolean(data?.profile?.destination_calendar_id) && bookable && Boolean(data?.types.some((t) => t.active));
  const hours = profile ? dayMap(profile.weekly_hours) : new Map();

  async function saveProfile() {
    if (!profile) return;
    setSaving(true);
    setMessage("");
    try {
      const saved = await send("/api/scheduling", "PUT", profile);
      setData((d) => (d ? { ...d, profile: saved } : d));
      setProfile(saved);
      setMessage("Your link and hours are saved.");
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Couldn't save your link.");
    } finally {
      setSaving(false);
    }
  }
  function setDay(day: number, value: { start: string; end: string } | null) {
    if (!profile) return;
    const map = dayMap(profile.weekly_hours);
    if (value) map.set(day, value);
    else map.delete(day);
    setProfile({ ...profile, weekly_hours: fromDayMap(map) });
  }
  async function toggleType(type: EventType) {
    try {
      const saved = await send(`/api/scheduling/event-types/${type.id}`, "PATCH", { ...type, active: !type.active });
      setData((d) => (d ? { ...d, types: d.types.map((t) => (t.id === saved.id ? saved : t)) } : d));
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Couldn't update this meeting type.");
    }
  }
  async function removeType(type: EventType) {
    if (!confirm(`Remove “${type.title}”? Existing bookings stay on your calendar.`)) return;
    try {
      await send(`/api/scheduling/event-types/${type.id}`, "DELETE");
      setData((d) => (d ? { ...d, types: d.types.filter((t) => t.id !== type.id) } : d));
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Couldn't remove this meeting type.");
    }
  }

  if (!data || !profile)
    return (
      <Shell email={email}>
        <div className="scheduling-page">
          <header className="page-header">
            <h1>Booking links</h1>
          </header>
          {message ? <p className="notice" role="alert">{message}</p> : <p className="muted" role="status">Loading your booking settings…</p>}
        </div>
      </Shell>
    );

  const profileURL = `${data.base_url}/${data.profile?.handle ?? profile.handle}`;
  const steps = [
    { done: data.accounts.length > 0, label: "Connect Google Calendar" },
    { done: bookable, label: "Allow booking on your calendar" },
    { done: Boolean(data.profile?.destination_calendar_id), label: "Choose your link, hours and calendar" },
    { done: data.types.some((t) => t.active), label: "Add a meeting type" },
  ];

  return (
    <Shell email={email}>
      <div className="scheduling-page">
        <header className="page-header">
          <h1>Booking links</h1>
          <p>
            Let people choose a time that suits you both. Invitations come from your own calendar with your own
            meeting link, and Voice Notes has the right notes ready when the call starts.
          </p>
        </header>
        {message && (
          <p className="notice" role="status">
            {message}
          </p>
        )}

        {live ? (
          <section className="booking-live">
            <span className="eyebrow">YOUR BOOKING PAGE IS LIVE</span>
            <CopyLink url={profileURL} />
            <Link className="text-link" href={profileURL.replace(/^https?:\/\/[^/]+/, "")} target="_blank">
              Preview as a guest
              <ArrowUpRight size={14} />
            </Link>
          </section>
        ) : (
          <section className="setup-steps" aria-label="Setup">
            {steps.map((s, i) => (
              <div key={s.label} className={s.done ? "setup-step done" : "setup-step"}>
                <span>{s.done ? <Check size={14} /> : i + 1}</span>
                {s.label}
              </div>
            ))}
          </section>
        )}

        {!data.accounts.length ? (
          <section className="connection-row">
            <div>
              <h2>Connect your calendar first</h2>
              <p>Booking checks when you’re busy and adds meetings to your calendar.</p>
            </div>
            <a className={"button primary " + (googleReady ? "" : "disabled")} href="/api/google/connect">
              Connect Google
              <ArrowUpRight size={16} />
            </a>
          </section>
        ) : (
          !bookable && (
            <section className="connection-row">
              <div>
                <h2>Allow booking on your calendar</h2>
                <p>
                  Google will ask for two more permissions: to add booked meetings to your calendar, and to see when
                  you’re busy. Google sends the invitation from your own account; Voice Notes never emails guests.
                </p>
              </div>
              <div className="connection-actions">
                {data.accounts.map((a) => (
                  <a
                    key={a.id}
                    className="button small primary"
                    href={`/api/google/connect?booking=1${a.email ? `&account=${encodeURIComponent(a.email)}` : ""}`}
                  >
                    Allow for {a.email ?? "this account"}
                    <ArrowUpRight size={15} />
                  </a>
                ))}
              </div>
            </section>
          )
        )}

        <section className="settings-section" aria-labelledby="link-heading">
          <h2 id="link-heading">Your link</h2>
          <div className="form-grid">
            <label className="field">
              <span>Link name</span>
              <div className="prefixed">
                <em>{data.base_url.replace(/^https?:\/\//, "")}/</em>
                <input
                  value={profile.handle}
                  onChange={(e) => setProfile({ ...profile, handle: e.target.value.toLowerCase() })}
                  autoComplete="off"
                  spellCheck={false}
                />
              </div>
            </label>
            <label className="field">
              <span>Name guests see</span>
              <input value={profile.display_name} onChange={(e) => setProfile({ ...profile, display_name: e.target.value })} />
            </label>
            <label className="field">
              <span>Your time zone</span>
              <select value={profile.time_zone} onChange={(e) => setProfile({ ...profile, time_zone: e.target.value })}>
                {(zones.length ? zones : [profile.time_zone]).map((z) => (
                  <option key={z}>{z}</option>
                ))}
              </select>
            </label>
            <label className="field">
              <span>Add bookings to</span>
              <select
                value={profile.destination_calendar_id ? `${profile.destination_connection_id}|${profile.destination_calendar_id}` : ""}
                onChange={(e) => {
                  const [connection, calendar] = e.target.value.split("|");
                  setProfile({
                    ...profile,
                    destination_connection_id: connection || null,
                    destination_calendar_id: calendar || null,
                  });
                }}
              >
                <option value="">{destinations.length ? "Choose a calendar" : "Allow booking first"}</option>
                {destinations.map((c) => (
                  <option key={`${c.connection_id}|${c.calendar_id}`} value={`${c.connection_id}|${c.calendar_id}`}>
                    {c.name} · {data.accounts.find((a) => a.id === c.connection_id)?.email}
                  </option>
                ))}
              </select>
            </label>
          </div>

          <h3 className="field-heading">When you’re available</h3>
          <p className="fine-print">
            Times outside these hours are never offered. Every calendar you tick in Connections, and busy times shared
            from your Mac, also block times.
          </p>
          <div className="hours">
            {DAYS.map(([label, day]) => {
              const value = hours.get(day);
              return (
                <div className="hours-row" key={day}>
                  <label className="check">
                    <input
                      type="checkbox"
                      checked={Boolean(value)}
                      onChange={(e) => setDay(day, e.target.checked ? { start: "09:00", end: "17:00" } : null)}
                    />
                    {label}
                  </label>
                  {value ? (
                    <span className="time-range">
                      <input type="time" value={value.start} aria-label={`${label} start`} onChange={(e) => setDay(day, { ...value, start: e.target.value })} />
                      –
                      <input type="time" value={value.end === "24:00" ? "23:59" : value.end} aria-label={`${label} end`} onChange={(e) => setDay(day, { ...value, end: e.target.value === "23:59" ? "24:00" : e.target.value })} />
                    </span>
                  ) : (
                    <span className="muted">Unavailable</span>
                  )}
                </div>
              );
            })}
          </div>

          <h3 className="field-heading">Date changes</h3>
          <div className="overrides">
            {profile.date_overrides.map((o, i) => (
              <div className="hours-row" key={`${o.date}-${i}`}>
                <input
                  type="date"
                  value={o.date}
                  aria-label="Date"
                  onChange={(e) => {
                    const next = [...profile.date_overrides];
                    next[i] = { ...o, date: e.target.value };
                    setProfile({ ...profile, date_overrides: next });
                  }}
                />
                {o.ranges.length ? (
                  <span className="time-range">
                    <input type="time" value={o.ranges[0].start} aria-label="Start" onChange={(e) => {
                      const next = [...profile.date_overrides];
                      next[i] = { ...o, ranges: [{ ...o.ranges[0], start: e.target.value }] };
                      setProfile({ ...profile, date_overrides: next });
                    }} />
                    –
                    <input type="time" value={o.ranges[0].end} aria-label="End" onChange={(e) => {
                      const next = [...profile.date_overrides];
                      next[i] = { ...o, ranges: [{ ...o.ranges[0], end: e.target.value }] };
                      setProfile({ ...profile, date_overrides: next });
                    }} />
                  </span>
                ) : (
                  <span className="muted">Unavailable all day</span>
                )}
                <button
                  className="text-link"
                  onClick={() => {
                    const next = [...profile.date_overrides];
                    next[i] = { ...o, ranges: o.ranges.length ? [] : [{ start: "09:00", end: "12:00" }] };
                    setProfile({ ...profile, date_overrides: next });
                  }}
                >
                  {o.ranges.length ? "Make unavailable" : "Set hours"}
                </button>
                <button
                  className="icon-button"
                  aria-label="Remove date change"
                  onClick={() => setProfile({ ...profile, date_overrides: profile.date_overrides.filter((_, j) => j !== i) })}
                >
                  <X size={16} />
                </button>
              </div>
            ))}
            <button
              className="text-link"
              onClick={() =>
                setProfile({
                  ...profile,
                  date_overrides: [...profile.date_overrides, { date: new Date().toISOString().slice(0, 10), ranges: [] }],
                })
              }
            >
              <Plus size={15} />
              Add a day off or different hours
            </button>
          </div>
          <div className="form-actions">
            <button className="button primary" onClick={saveProfile} disabled={saving}>
              {saving ? <LoaderCircle className="spin" size={16} /> : <Check size={16} />}
              Save link and hours
            </button>
          </div>
        </section>

        <section className="settings-section" aria-labelledby="types-heading">
          <div className="heading-row">
            <h2 id="types-heading">Meeting types</h2>
            {!editing && (
              <button className="button small" onClick={() => setEditing(blankType(data.types.length))}>
                <Plus size={15} />
                New meeting type
              </button>
            )}
          </div>
          {editing && !editing.id && (
            <TypeEditor
              value={editing}
              onCancel={() => setEditing(null)}
              onSaved={(saved) => {
                setData((d) => (d ? { ...d, types: [...d.types, saved] } : d));
                setEditing(null);
              }}
            />
          )}
          {data.types.length === 0 && !editing && (
            <p className="muted">Add a meeting type, such as a 30-minute intro call, to start taking bookings.</p>
          )}
          {data.types.map((type) =>
            editing?.id === type.id ? (
              <TypeEditor
                key={type.id}
                value={type}
                onCancel={() => setEditing(null)}
                onSaved={(saved) => {
                  setData((d) => (d ? { ...d, types: d.types.map((t) => (t.id === saved.id ? saved : t)) } : d));
                  setEditing(null);
                }}
              />
            ) : (
              <div className={type.active ? "type-card" : "type-card off"} key={type.id}>
                <div>
                  <h3>{type.title}</h3>
                  <p className="type-meta">
                    {type.duration_minutes} min · {LOCATIONS[type.location_kind][0]} · Notes use {TEMPLATES[type.summary_template]}
                    {!type.active && " · Hidden"}
                  </p>
                  {data.profile && type.active && <CopyLink url={`${data.base_url}/${data.profile.handle}/${type.slug}`} />}
                </div>
                <div className="type-actions">
                  <label className="switch">
                    <input type="checkbox" checked={type.active} onChange={() => toggleType(type)} />
                    <span>{type.active ? "On" : "Off"}</span>
                  </label>
                  <button className="icon-button" aria-label={`Edit ${type.title}`} onClick={() => setEditing(type)}>
                    <Pencil size={16} />
                  </button>
                  <button className="icon-button" aria-label={`Remove ${type.title}`} onClick={() => removeType(type)}>
                    <Trash2 size={16} />
                  </button>
                </div>
              </div>
            ),
          )}
        </section>

        <section className="settings-section" aria-labelledby="upcoming-heading">
          <h2 id="upcoming-heading">Upcoming bookings</h2>
          {data.bookings.length === 0 ? (
            <p className="muted">No one has booked yet. New bookings appear here and on your calendar.</p>
          ) : (
            data.bookings.map((b) => (
              <BookingRow
                key={b.id}
                booking={b}
                onCancelled={() => setData((d) => (d ? { ...d, bookings: d.bookings.filter((x) => x.id !== b.id) } : d))}
              />
            ))
          )}
        </section>
      </div>
    </Shell>
  );
}

function BookingRow({ booking, onCancelled }: { booking: Booking; onCancelled: () => void }) {
  const [confirming, setConfirming] = useState(false);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  return (
    <div className="booking-row">
      <div className="booking-when">{when(booking.starts_at)}</div>
      <div>
        <h3>
          {booking.title} · {booking.guest_name}
        </h3>
        <p className="type-meta">{booking.guest_email}</p>
        {booking.answers.length > 0 && (
          <dl className="answers">
            {booking.answers.map((a) => (
              <div key={a.question}>
                <dt>{a.question}</dt>
                <dd>{a.answer}</dd>
              </div>
            ))}
          </dl>
        )}
        {confirming && (
          <div className="cancel-confirm">
            <label className="field">
              <span>Note for {booking.guest_name} (optional)</span>
              <input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={1000} />
            </label>
            <div className="form-actions">
              <button className="button small" onClick={() => setConfirming(false)} disabled={busy}>
                Keep booking
              </button>
              <button
                className="button small danger"
                disabled={busy}
                onClick={async () => {
                  setBusy(true);
                  setError("");
                  try {
                    await send(`/api/scheduling/bookings/${booking.id}`, "POST", { action: "cancel", reason: reason || undefined });
                    onCancelled();
                  } catch (e) {
                    setError(e instanceof Error ? e.message : "Couldn't cancel this booking.");
                    setBusy(false);
                  }
                }}
              >
                Cancel booking
              </button>
            </div>
            <p className="fine-print">Google removes the event and tells {booking.guest_name} from your calendar.</p>
          </div>
        )}
        {error && <p className="notice" role="alert">{error}</p>}
      </div>
      <div className="type-actions">
        {booking.meeting_url && (
          <a className="text-link" href={booking.meeting_url} target="_blank" rel="noreferrer">
            Join
            <ArrowUpRight size={14} />
          </a>
        )}
        {!confirming && (
          <button className="text-link" onClick={() => setConfirming(true)}>
            Cancel
          </button>
        )}
      </div>
    </div>
  );
}

function TypeEditor({
  value,
  onCancel,
  onSaved,
}: {
  value: EventType;
  onCancel: () => void;
  onSaved: (saved: EventType) => void;
}) {
  const [type, setType] = useState(value);
  const [slugTouched, setSlugTouched] = useState(Boolean(value.id));
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const set = <K extends keyof EventType>(key: K, v: EventType[K]) => setType((t) => ({ ...t, [key]: v }));
  const number = (v: string, fallback: number | null = null) => (v === "" ? fallback : Math.max(0, Math.round(Number(v))));
  async function save() {
    setBusy(true);
    setError("");
    try {
      const body = {
        ...type,
        location_detail: type.location_kind === "google_meet" || type.location_kind === "phone" ? null : type.location_detail,
      };
      const { id, ...fields } = body;
      const saved = id
        ? await send(`/api/scheduling/event-types/${id}`, "PATCH", fields)
        : await send("/api/scheduling/event-types", "POST", fields);
      onSaved(saved);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Couldn't save this meeting type.");
      setBusy(false);
    }
  }
  return (
    <div className="type-editor">
      <div className="form-grid">
        <label className="field">
          <span>Name</span>
          <input
            value={type.title}
            onChange={(e) => {
              set("title", e.target.value);
              if (!slugTouched) set("slug", slugify(e.target.value));
            }}
          />
        </label>
        <label className="field">
          <span>Link ending</span>
          <input
            value={type.slug}
            spellCheck={false}
            onChange={(e) => {
              setSlugTouched(true);
              set("slug", e.target.value.toLowerCase());
            }}
          />
        </label>
        <label className="field">
          <span>Length</span>
          <select value={type.duration_minutes} onChange={(e) => set("duration_minutes", Number(e.target.value))}>
            {[15, 20, 30, 45, 60, 90, 120].map((m) => (
              <option key={m} value={m}>
                {m} minutes
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>Notes template</span>
          <select value={type.summary_template} onChange={(e) => set("summary_template", e.target.value as EventType["summary_template"])}>
            {Object.entries(TEMPLATES).map(([k, label]) => (
              <option key={k} value={k}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>Where</span>
          <select value={type.location_kind} onChange={(e) => set("location_kind", e.target.value as EventType["location_kind"])}>
            {Object.entries(LOCATIONS).map(([k, [label]]) => (
              <option key={k} value={k}>
                {label}
              </option>
            ))}
          </select>
        </label>
        {(type.location_kind === "video_link" || type.location_kind === "in_person") && (
          <label className="field">
            <span>{type.location_kind === "video_link" ? "Your meeting room link" : "Address"}</span>
            <input
              value={type.location_detail ?? ""}
              placeholder={type.location_kind === "video_link" ? "https://zoom.us/j/…" : "Street, suburb"}
              onChange={(e) => set("location_detail", e.target.value)}
            />
          </label>
        )}
      </div>
      <p className="fine-print">
        {type.location_kind === "google_meet"
          ? "Google creates a Meet link on your calendar event."
          : type.location_kind === "video_link"
            ? "Use your own Zoom or Teams room. It goes into the invitation."
            : type.location_kind === "phone"
              ? "Guests give a number and you call them."
              : "The address goes into the invitation."}
      </p>
      <label className="field">
        <span>Description guests see</span>
        <textarea rows={3} value={type.description} onChange={(e) => set("description", e.target.value)} maxLength={2000} />
      </label>

      <h3 className="field-heading">Questions for guests</h3>
      {type.questions.map((q, i) => (
        <div className="question-row" key={q.id}>
          <input
            aria-label="Question"
            value={q.label}
            onChange={(e) => set("questions", type.questions.map((x, j) => (j === i ? { ...x, label: e.target.value } : x)))}
          />
          <label className="check">
            <input
              type="checkbox"
              checked={q.required}
              onChange={(e) => set("questions", type.questions.map((x, j) => (j === i ? { ...x, required: e.target.checked } : x)))}
            />
            Required
          </label>
          <label className="check">
            <input
              type="checkbox"
              checked={q.long}
              onChange={(e) => set("questions", type.questions.map((x, j) => (j === i ? { ...x, long: e.target.checked } : x)))}
            />
            Long answer
          </label>
          <button className="icon-button" aria-label="Remove question" onClick={() => set("questions", type.questions.filter((_, j) => j !== i))}>
            <X size={16} />
          </button>
        </div>
      ))}
      {type.questions.length < 10 && (
        <button
          className="text-link"
          onClick={() =>
            set("questions", [
              ...type.questions,
              { id: `q-${Math.random().toString(36).slice(2, 8)}`, label: "", required: false, long: false },
            ])
          }
        >
          <Plus size={15} />
          Add a question
        </button>
      )}
      <p className="fine-print">Answers appear with the meeting in Voice Notes and in the calendar event.</p>

      <details className="advanced">
        <summary>Notice, buffers and limits</summary>
        <div className="form-grid">
          <label className="field">
            <span>Minimum notice (hours)</span>
            <input
              type="number"
              min={0}
              value={type.minimum_notice_minutes / 60}
              onChange={(e) => set("minimum_notice_minutes", (number(e.target.value, 0) as number) * 60)}
            />
          </label>
          <label className="field">
            <span>Book up to (days ahead)</span>
            <input type="number" min={1} max={365} value={type.booking_window_days} onChange={(e) => set("booking_window_days", Math.max(1, number(e.target.value, 1) as number))} />
          </label>
          <label className="field">
            <span>Free time before (minutes)</span>
            <input type="number" min={0} max={240} value={type.buffer_before_minutes} onChange={(e) => set("buffer_before_minutes", number(e.target.value, 0) as number)} />
          </label>
          <label className="field">
            <span>Free time after (minutes)</span>
            <input type="number" min={0} max={240} value={type.buffer_after_minutes} onChange={(e) => set("buffer_after_minutes", number(e.target.value, 0) as number)} />
          </label>
          <label className="field">
            <span>Most per day</span>
            <input type="number" min={1} max={50} placeholder="No limit" value={type.daily_limit ?? ""} onChange={(e) => set("daily_limit", number(e.target.value))} />
          </label>
          <label className="field">
            <span>Start times every (minutes)</span>
            <input type="number" min={5} max={480} placeholder={`${type.duration_minutes}`} value={type.slot_interval_minutes ?? ""} onChange={(e) => set("slot_interval_minutes", number(e.target.value))} />
          </label>
        </div>
      </details>
      {error && <p className="notice" role="alert">{error}</p>}
      <div className="form-actions">
        <button className="button small" onClick={onCancel} disabled={busy}>
          Cancel
        </button>
        <button className="button small primary" onClick={save} disabled={busy}>
          {busy ? <LoaderCircle className="spin" size={15} /> : <Check size={15} />}
          {type.id ? "Save changes" : "Create meeting type"}
        </button>
      </div>
    </div>
  );
}
