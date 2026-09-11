"use client";

/** One date control throughout scheduling, preserving the browser's calendar and keyboard entry. */
export function DateField({ value, onChange, label = "Choose date" }: {
  value: string; onChange: (value: string) => void; label?: string;
}) {
  return (
    <div className="date-field">
      <input type="date" aria-label={label} value={value}
        onChange={(event) => onChange(event.target.value)} />
    </div>
  );
}
