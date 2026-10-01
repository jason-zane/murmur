"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  BookOpen,
  Mail,
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
import { useEffect, useState } from "react";
import { Dialog } from "./dialog";
import { Brand } from "./brand";
const destinations = [
  ["/", "Today", Home],
  ["/calendar", "Calendar", CalendarDays],
  ["/mail", "Mail", Mail],
  ["/notes", "Notes", BookOpen],
  ["/scheduling", "Booking links", CalendarClock],
  ["/dictation", "Dictation history", AudioLines],

] as const;
export function Shell({
  email,
  children,
  onNew,
  layout,
}: {
  email: string;
  children: React.ReactNode;
  onNew?: () => void;
  layout?: "mail";
}) {
  const path = usePathname();
  const [open, setOpen] = useState(false);
  const [welcome, setWelcome] = useState(false);
  const welcomeKey = `voice-notes:workspace-v2:${email}`;
  useEffect(() => {
    if (path !== "/" || document.documentElement.classList.contains("native-workspace")) return;
    try { if (!localStorage.getItem(welcomeKey)) setWelcome(true); } catch { /* Storage is optional. */ }
  }, [path, welcomeKey]);
  function closeWelcome() {
    try { localStorage.setItem(welcomeKey, "seen"); } catch { /* Local work remains available. */ }
    setWelcome(false);
  }
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
    <div className={layout === "mail" ? "shell shell-mail" : "shell"}>
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
            {nav("/connections", "Connected apps", Link2)}
            {nav("/settings", "Settings", Settings)}
            <button className="workspace-guide" onClick={() => setWelcome(true)}>Set up your workspace</button>
          </nav>
          <Link
            href="/settings"
            className="account"
            aria-label={`Account settings, ${email}`}
          >
            <span className="avatar">{email[0]?.toUpperCase() || "V"}</span>
            <span className="sidebar-account-details">
              <span className="account-label">Concourse account</span>
              <span className="account-email" title={email}>
                {email}
              </span>
            </span>
          </Link>
        </div>
      </aside>
      {welcome && <Dialog label="Set up your workspace" onClose={closeWelcome}>
        <div className="heading-row"><h2>Set up your workspace</h2><button className="icon-button" aria-label="Close setup guide" onClick={closeWelcome}><X size={20} /></button></div>
        <p>Move between Today, Calendar, Mail and Notes. Connect only the apps you want to use.</p>
        <div className="workspace-setup-list">
          <Link href="/connections?focus=calendar" onClick={closeWelcome}><CalendarDays size={20} /><span><strong>Bring your calendars together</strong><small>Work and personal accounts, past meetings and upcoming events.</small></span><Plus size={18} /></Link>
          <Link href="/connections?focus=gmail" onClick={closeWelcome}><Mail size={20} /><span><strong>Connect your Gmail inboxes</strong><small>Read, reply and organise mail beside your calendar and notes.</small></span><Plus size={18} /></Link>
          <Link href="/connections?focus=ai" onClick={closeWelcome}><Link2 size={20} /><span><strong>Ask about your notes</strong><small>Set up ChatGPT or Claude when you’re ready.</small></span><Plus size={18} /></Link>
        </div>
        <p className="fine-print">Your downloaded content remains available offline. You can revisit setup from Connected apps.</p>
        <button className="button" onClick={closeWelcome}>Start with my workspace</button>
      </Dialog>}
      <main id="main" className="workspace">
        {children}
      </main>
    </div>
  );
}
