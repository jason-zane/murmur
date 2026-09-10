"use client";
import { useState } from "react";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { Brand } from "@/components/brand";
import { browserClient } from "@/lib/supabase/browser";

export function ResetPassword({ email }: { email: string }) {
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [done, setDone] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (password !== confirm) {
      setMessage("The two passwords don't match.");
      return;
    }
    setBusy(true);
    setMessage("");
    try {
      const { error } = await browserClient().auth.updateUser({ password });
      if (error) throw error;
      setDone(true);
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Couldn't change the password. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main id="main" className="auth-form">
      <div className="auth-form-inner">
        <Brand />
        <h2>{done ? "Password changed." : "Choose a new password."}</h2>
        {done ? (
          <>
            <p>You're signed in as {email}. Use the new password on your Mac and the web.</p>
            <Link className="button primary wide" href="/">
              Open your notes
              <ArrowRight size={17} />
            </Link>
          </>
        ) : (
          <>
            <p>For {email}. At least 8 characters.</p>
            <form onSubmit={submit}>
              <label htmlFor="password">New password</label>
              <input
                id="password"
                type="password"
                autoComplete="new-password"
                minLength={8}
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
              <label htmlFor="confirm">Again, to be sure</label>
              <input
                id="confirm"
                type="password"
                autoComplete="new-password"
                minLength={8}
                required
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
              />
              <button className="button primary wide" disabled={busy}>
                {busy ? "Saving…" : "Save new password"}
                <ArrowRight size={17} />
              </button>
            </form>
          </>
        )}
        {message && (
          <p className="notice" role="alert">
            {message}
          </p>
        )}
      </div>
    </main>
  );
}
