"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  BookOpen,
  CalendarDays,
  CalendarClock,
  Home,
  AudioLines,
  Link2,
  Settings,
  Plus,
  Menu,
  X,
} from "lucide-react";
import { useState } from "react";
import { Brand } from "./brand";
const destinations = [
  ["/", "Home", Home],
  ["/calendar", "Calendar", CalendarDays],
  ["/notes", "Notes", BookOpen],
  ["/dictation", "Dictation", AudioLines],
  ["/scheduling", "Booking links", CalendarClock],
] as const;
export function Shell({
  email,
  children,
  onNew,
}: {
  email: string;
  children: React.ReactNode;
  onNew?: () => void;
}) {
  const path = usePathname();
  const [open, setOpen] = useState(false);
  const nav = (href: string, label: string, Icon: typeof Home) => (
    <Link
      key={href}
      href={href}
      onClick={() => setOpen(false)}
      className={"nav" + (path === href ? " active" : "")}
      aria-current={path === href ? "page" : undefined}
    >
      <Icon size={18} />
      {label}
    </Link>
  );
  return (
    <div className="shell">
      <header className="mobile-bar">
        <Brand />
        <button
          className="icon-button"
          aria-label={open ? "Close navigation" : "Open navigation"}
          aria-expanded={open}
          onClick={() => setOpen(!open)}
        >
          {open ? <X /> : <Menu />}
        </button>
      </header>
      <aside className={"sidebar" + (open ? " mobile-open" : "")}>
        <Brand />
        <nav aria-label="Main navigation">
          {destinations.map(([href, label, Icon]) => nav(href, label, Icon))}
        </nav>
        {onNew && (
          <button className="new-note" onClick={onNew}>
            <Plus size={17} />
            New note
          </button>
        )}
        <div className="sidebar-bottom">
          <nav aria-label="Preferences">
            {nav("/connections", "Connections", Link2)}
            {nav("/settings", "Settings", Settings)}
          </nav>
          <Link
            href="/settings"
            className="account"
            aria-label={`Account settings, ${email}`}
          >
            <span className="avatar">{email[0]?.toUpperCase() || "V"}</span>
            <span className="sidebar-account-details">
              <span className="account-label">Voice Notes account</span>
              <span className="account-email" title={email}>
                {email}
              </span>
            </span>
          </Link>
        </div>
      </aside>
      <main id="main" className="workspace">
        {children}
      </main>
    </div>
  );
}
