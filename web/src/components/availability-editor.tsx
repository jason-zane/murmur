"use client";
import { useId } from "react";
import { Plus, X, Copy } from "lucide-react";
type Range = { start: string; end: string };
export type WeeklyHours = { days: number[]; start: string; end: string }[];
const DAYS: [[string, number], ...[string, number][]] = [
  ["Monday", 1],
  ["Tuesday", 2],
  ["Wednesday", 3],
  ["Thursday", 4],
  ["Friday", 5],
  ["Saturday", 6],
  ["Sunday", 0],
];
export function RangesEditor({
  ranges,
  onChange,
  label,
}: {
  ranges: Range[];
  onChange: (r: Range[]) => void;
  label: string;
}) {
  return (
    <div className="ranges-editor">
      {ranges.map((r, i) => (
        <div className="time-range" key={i}>
          <input
            type="time"
            value={r.start}
            aria-label={`${label} start ${i + 1}`}
            onChange={(e) =>
              onChange(
                ranges.map((v, j) =>
                  j === i ? { ...v, start: e.target.value } : v,
                ),
              )
            }
          />
          <span>–</span>
          <input
            type="time"
            value={r.end === "24:00" ? "23:59" : r.end}
            aria-label={`${label} end ${i + 1}`}
            onChange={(e) =>
              onChange(
                ranges.map((v, j) =>
                  j === i
                    ? {
                        ...v,
                        end:
                          e.target.value === "23:59" ? "24:00" : e.target.value,
                      }
                    : v,
                ),
              )
            }
          />
          <button
            type="button"
            className="icon-button"
            aria-label={`Remove ${label} hours ${i + 1}`}
            onClick={() => onChange(ranges.filter((_, j) => j !== i))}
          >
            <X size={14} />
          </button>
        </div>
      ))}
      <button
        type="button"
        className="text-link"
        disabled={ranges.length >= 10}
        onClick={() => onChange([...ranges, { start: "13:00", end: "17:00" }])}
      >
        <Plus size={14} />
        {ranges.length ? "Add hours" : "Set hours"}
      </button>
    </div>
  );
}
export function WeeklyHoursEditor({
  value,
  onChange,
}: {
  value: WeeklyHours;
  onChange: (v: WeeklyHours) => void;
}) {
  const ranges = (day: number) =>
    value
      .filter((r) => r.days.includes(day))
      .map(({ start, end }) => ({ start, end }));
  function set(day: number, next: Range[]) {
    onChange([
      ...value
        .map((r) => ({ ...r, days: r.days.filter((d) => d !== day) }))
        .filter((r) => r.days.length),
      ...next.map((r) => ({ ...r, days: [day] })),
    ]);
  }
  return (
    <div className="hours">
      {DAYS.map(([label, day]) => (
        <div className="hours-row" key={day}>
          <label className="check">
            <input
              type="checkbox"
              checked={ranges(day).length > 0}
              onChange={(e) =>
                set(
                  day,
                  e.target.checked ? [{ start: "09:00", end: "17:00" }] : [],
                )
              }
            />
            {label}
          </label>
          {ranges(day).length ? (
            <RangesEditor
              label={label}
              ranges={ranges(day)}
              onChange={(v) => set(day, v)}
            />
          ) : (
            <span className="muted">Unavailable</span>
          )}
          {day === 1 && (
            <button
              type="button"
              className="text-link"
              onClick={() =>
                onChange([
                  ...value
                    .filter((r) => r.days.some((d) => d === 0 || d === 6))
                    .map((r) => ({
                      ...r,
                      days: r.days.filter((d) => d === 0 || d === 6),
                    })),
                  ...ranges(1).map((r) => ({ ...r, days: [1, 2, 3, 4, 5] })),
                ])
              }
            >
              <Copy size={14} />
              Copy to weekdays
            </button>
          )}
        </div>
      ))}
    </div>
  );
}

export type Availability = {
  time_zone: string;
  weekly_hours: WeeklyHours;
  date_overrides: { date: string; ranges: Range[] }[];
};
export type AvailabilitySchedule = Availability & { id?: string; name: string };
export function AvailabilityFields({
  value,
  onChange,
}: {
  value: Availability;
  onChange: (v: Availability) => void;
}) {
  const zoneID = useId();
  return (
    <>
      <label className="field">
        <span>Time zone</span>
        <input
          list={zoneID}
          value={value.time_zone}
          onChange={(e) => onChange({ ...value, time_zone: e.target.value })}
        />
        <datalist id={zoneID}>
          {Intl.supportedValuesOf("timeZone").map((z) => (
            <option key={z} value={z} />
          ))}
        </datalist>
      </label>
      <WeeklyHoursEditor
        value={value.weekly_hours}
        onChange={(weekly_hours) => onChange({ ...value, weekly_hours })}
      />
      <h3>Date exceptions</h3>
      {value.date_overrides.map((o, i) => (
        <div className="hours-row" key={i}>
          <input
            type="date"
            aria-label="Exception date"
            value={o.date}
            onChange={(e) =>
              onChange({
                ...value,
                date_overrides: value.date_overrides.map((r, j) =>
                  j === i ? { ...r, date: e.target.value } : r,
                ),
              })
            }
          />
          <RangesEditor
            label={o.date || "Exception"}
            ranges={o.ranges}
            onChange={(ranges) =>
              onChange({
                ...value,
                date_overrides: value.date_overrides.map((r, j) =>
                  j === i ? { ...r, ranges } : r,
                ),
              })
            }
          />
          <button
            className="icon-button"
            aria-label="Remove exception"
            onClick={() =>
              onChange({
                ...value,
                date_overrides: value.date_overrides.filter((_, j) => j !== i),
              })
            }
          >
            <X size={16} />
          </button>
        </div>
      ))}
      <button
        className="text-link"
        onClick={() =>
          onChange({
            ...value,
            date_overrides: [...value.date_overrides, { date: "", ranges: [] }],
          })
        }
      >
        <Plus size={14} />
        Add a date exception
      </button>
      <p className="fine-print">
        Leave an exception without hours to mark the whole day unavailable.
      </p>
    </>
  );
}
