"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  BookOpen,
  CalendarClock,
  Link2,
  ArrowUpRight,
  Settings,
  Laptop,
  Plus,
} from "lucide-react";
import { Brand } from "./brand";
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
  return (
    <div className="shell">
      <aside className="sidebar">
        <Brand />
        <div className="workspace-name">
          Your space<span>PERSONAL</span>
        </div>
        <nav aria-label="Main navigation">
          <Link href="/" className={path === "/" ? "nav active" : "nav"}>
            <BookOpen size={18} />
            Your notes
          </Link>
          <Link
            href="/scheduling"
            className={path === "/scheduling" ? "nav active" : "nav"}
          >
            <CalendarClock size={18} />
            Booking links
          </Link>
          <Link
            href="/connections"
            className={path === "/connections" ? "nav active" : "nav"}
          >
            <Link2 size={18} />
            Connections
          </Link>
          <Link href="/settings" className={path === "/settings" ? "nav active" : "nav"}>
            <Settings size={18} />
            Settings
          </Link>
        </nav>
        {onNew && (
          <button className="new-note" onClick={onNew}>
            <Plus size={17} />
            Start a note<span>＋</span>
          </button>
        )}
        <div className="sidebar-bottom">
          <a className="mac-link" href="murmur://cloud">
            <Laptop size={18} />
            <span>
              Open Voice Notes on Mac<small>Record & dictate on device</small>
            </span>
            <ArrowUpRight size={14} />
          </a>
          <Link href="/settings" className="account" aria-label={`Account settings, signed in as ${email}`}>
            <span className="avatar">{email[0]?.toUpperCase() || "M"}</span>
            <span className="sidebar-account-details">
              <span className="account-label">Signed in as</span>
              <span className="account-email" title={email}>{email}</span>
            </span>
          </Link>
          <Link href="/privacy" className="quiet-link">
            Your data & privacy
          </Link>
        </div>
      </aside>
      <main id="main" className="workspace">
        {children}
      </main>
    </div>
  );
}
