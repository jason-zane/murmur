"use client";
import { useEffect, useRef, type ReactNode } from "react";
import { MoreHorizontal } from "lucide-react";

/** A disclosure of ordinary buttons: native Tab order, Escape and outside-click dismissal. */
export function ItemActions({ label, children }: { label: string; children: ReactNode }) {
  const ref = useRef<HTMLDetailsElement>(null);
  useEffect(() => {
    const close = (event: PointerEvent) => {
      if (!ref.current?.contains(event.target as Node)) ref.current?.removeAttribute("open");
    };
    const escape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && ref.current?.open) {
        event.stopPropagation();
        ref.current.open = false;
        ref.current.querySelector("summary")?.focus();
      }
    };
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", escape);
    return () => { document.removeEventListener("pointerdown", close); document.removeEventListener("keydown", escape); };
  }, []);
  return <details className="item-actions" ref={ref}>
    <summary aria-label={`Actions for ${label}`} title={`Actions for ${label}`}><MoreHorizontal size={18} /></summary>
    <div className="item-actions-panel" onClick={(event) => {
      const button = (event.target as Element).closest("button");
      if (button && !button.disabled) ref.current?.removeAttribute("open");
    }}>{children}</div>
  </details>;
}
