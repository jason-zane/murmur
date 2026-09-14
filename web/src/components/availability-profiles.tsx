"use client";
import { ItemActions } from "./item-actions";
import { useState } from "react";
import {
  AvailabilityFields,
  type Availability,
  type AvailabilitySchedule,
} from "./availability-editor";
export function AvailabilityProfiles({
  schedules,
  defaultAvailability,
  types,
  onChanged,
}: {
  schedules: AvailabilitySchedule[];
  defaultAvailability: Availability;
  types: {
    id?: string;
    title: string;
    availability_schedule_id?: string | null;
  }[];
  onChanged: () => void;
}) {
  const [editing, setEditing] = useState<AvailabilitySchedule | null>(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  async function save() {
    if (!editing) return;
    setBusy(true);
    setError("");
    try {
      const r = await fetch("/api/scheduling/availability", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(editing),
      });
      const b = await r.json();
      if (!r.ok) throw new Error(b.error);
      setEditing(null);
      onChanged();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function remove(s: AvailabilitySchedule) {
    if (!confirm(`Delete “${s.name}”? Schedules in use cannot be deleted.`))
      return;
    setBusy(true);
    try {
      const r = await fetch(`/api/scheduling/availability?id=${s.id}`, {
        method: "DELETE",
      });
      const b = await r.json();
      if (!r.ok) throw new Error(b.error);
      onChanged();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="settings-section">
      <div className="heading-row">
        <div>
          <h2>Availability profiles</h2>
          <p className="fine-print">
            Save different hours for client calls, interviews or focused work.
            Each meeting type can use one of these, your default, or its own
            custom hours.
          </p>
        </div>
        <button
          className="button small"
          onClick={() => setEditing({ ...defaultAvailability, name: "" })}
        >
          New availability profile
        </button>
      </div>
      {error && (
        <p className="notice" role="alert">
          {error}
        </p>
      )}
      {schedules.map((s) => (
        <div className="type-card" key={s.id}>
          <div>
            <h3>{s.name}</h3>
            <p className="type-meta">
              {s.time_zone} ·{" "}
              {types
                .filter((t) => t.availability_schedule_id === s.id)
                .map((t) => t.title)
                .join(", ") || "Not used yet"}
            </p>
          </div>
          <ItemActions label={s.name}>
            <button className="button small" onClick={() => setEditing(s)}>
              Edit
            </button>
            <button
              className="text-link"
              disabled={busy}
              onClick={() => remove(s)}
            >
              Delete availability profile…
            </button>
          </ItemActions>
        </div>
      ))}
      {editing && (
        <section className="workspace-card">
          <h3>
            {editing.id
              ? "Edit availability profile"
              : "New availability profile"}
          </h3>
          <label className="field">
            <span>Profile name</span>
            <input
              required
              maxLength={120}
              placeholder="For example, Client calls"
              value={editing.name}
              onChange={(e) => setEditing({ ...editing, name: e.target.value })}
            />
          </label>
          <AvailabilityFields
            value={editing}
            onChange={(v) => setEditing({ ...editing, ...v })}
          />
          <p className="fine-print">
            Saving updates future available times for every meeting type using
            this profile. Existing bookings keep their times.
          </p>
          <div className="form-actions">
            <button className="button" onClick={() => setEditing(null)}>
              Cancel
            </button>
            <button
              className="button primary"
              disabled={busy || !editing.name.trim()}
              onClick={save}
            >
              Save availability profile
            </button>
          </div>
        </section>
      )}
    </section>
  );
}
