"use client";
import { useEffect, useState } from "react";

export function LocalTime({ value, dateOnly = false }: { value: string; dateOnly?: boolean }) {
  const [label, setLabel] = useState("…");
  useEffect(() => {
    const date = new Date(value);
    setLabel(dateOnly ? date.toLocaleDateString() : date.toLocaleString());
  }, [value, dateOnly]);
  return <time dateTime={value}>{label}</time>;
}
