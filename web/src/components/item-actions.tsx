"use client";
import { useEffect, useLayoutEffect, useId, useRef, useState, type ReactNode } from "react";
import { MoreHorizontal } from "lucide-react";

/** Ordinary buttons in a disclosure: Tab navigation, Escape and outside dismissal. */
export function ItemActions({ label, children }: { label: string; children: ReactNode }) {
  const id = useId(), ref = useRef<HTMLDivElement>(null), trigger = useRef<HTMLButtonElement>(null), panel = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const [position, setPosition] = useState<{left:number;top:number;width:number}|null>(null);
  useLayoutEffect(() => {
    if (!open) return;
    const place = () => {
      if (!trigger.current || !panel.current) return;
      const anchor = trigger.current.getBoundingClientRect(), height = panel.current.getBoundingClientRect().height;
      const width = Math.min(240, innerWidth - 16);
      const below = anchor.bottom + 4;
      setPosition({width, left:Math.max(8, Math.min(anchor.right - width, innerWidth - width - 8)), top:Math.max(8, Math.min(below + height <= innerHeight - 8 ? below : anchor.top - height - 4, innerHeight - height - 8))});
    };
    place();
    window.addEventListener("resize", place);
    document.addEventListener("scroll", place, true);
    return () => { window.removeEventListener("resize", place); document.removeEventListener("scroll", place, true); };
  }, [open]);
  useEffect(() => {
    const otherOpened = (event: Event) => {
      if ((event as CustomEvent<string>).detail !== id) setOpen(false);
    };
    document.addEventListener("workspace-actions-open", otherOpened);
    return () => document.removeEventListener("workspace-actions-open", otherOpened);
  }, [id]);
  useEffect(() => {
    if (!open) return;
    const outside = (event: Event) => { if (!ref.current?.contains(event.target as Node)) setOpen(false); };
    const escape = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.stopPropagation(); setOpen(false); trigger.current?.focus(); }
    };
    document.addEventListener("pointerdown", outside);
    document.addEventListener("focusin", outside);
    document.addEventListener("keydown", escape);
    return () => { document.removeEventListener("pointerdown", outside); document.removeEventListener("focusin", outside); document.removeEventListener("keydown", escape); };
  }, [open]);
  return <div className="item-actions" ref={ref} data-open={open || undefined}>
    <button className="item-actions-trigger" type="button" ref={trigger} aria-label={`More actions for ${label}`} title={`More actions for ${label}`} aria-expanded={open} aria-controls={id}
      onClick={()=>{if(!open)document.dispatchEvent(new CustomEvent("workspace-actions-open",{detail:id}));setOpen(!open);}}><MoreHorizontal size={18}/></button>
    {open && <div className="item-actions-panel" ref={panel} style={{position:"fixed",right:"auto",left:position?.left ?? 8,top:position?.top ?? 8,width:position?.width ?? 240,maxHeight:"calc(100dvh - 16px)",overflowY:"auto",visibility:position?"visible":"hidden"}} id={id} role="group" aria-label={`Actions for ${label}`} onClick={event=>{
      const button = (event.target as Element).closest("button");
      if (button && !button.disabled) {
        const activeInside = ref.current?.contains(document.activeElement);
        setOpen(false);
        requestAnimationFrame(()=>{
          if (activeInside && (document.activeElement===document.body || ref.current?.contains(document.activeElement))) trigger.current?.focus();
        });
      }
    }}>{children}</div>}
  </div>;
}
