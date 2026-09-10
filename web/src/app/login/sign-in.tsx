"use client";
import { useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { ArrowRight, Check, Laptop, Globe2 } from "lucide-react";
import { Brand, BrandMark, Waveform } from "@/components/brand";
import { browserClient } from "@/lib/supabase/browser";
import { safeNext } from "@/lib/config";
export function Login({ ready, google }: { ready: boolean; google: boolean }) {
  const params = useSearchParams(),
    next = safeNext(params.get("next"));
  const [email, setEmail] = useState(""),
    [password, setPassword] = useState(""),
    [mode, setMode] = useState<"login" | "signup" | "email" | "reset">("login"),
    [busy, setBusy] = useState(false),
    [message, setMessage] = useState(params.get("error") || "");
  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setMessage("");
    try {
      const client = browserClient();
      if (mode === "reset") {
        const { error } = await client.auth.resetPasswordForEmail(email, {
          redirectTo: `${location.origin}/auth/callback?next=${encodeURIComponent("/auth/reset")}`,
        });
        if (error) throw error;
        setMessage("Check your email for a link to choose a new password.");
      } else if (mode === "email") {
        const { error } = await client.auth.signInWithOtp({
          email,
          options: {
            emailRedirectTo: `${location.origin}/auth/callback?next=${encodeURIComponent(next)}`,
          },
        });
        if (error) throw error;
        setMessage("Check your email for a sign-in link.");
      } else if (mode === "signup") {
        const { error, data } = await client.auth.signUp({
          email,
          password,
          options: {
            emailRedirectTo: `${location.origin}/auth/callback?next=${encodeURIComponent(next)}`,
          },
        });
        if (error) throw error;
        if (data.session) location.assign(next);
        else
          setMessage("Check your email to confirm your account, then sign in.");
      } else {
        const { error } = await client.auth.signInWithPassword({
          email,
          password,
        });
        if (error) throw error;
        location.assign(next);
      }
    } catch (e) {
      setMessage(
        e instanceof Error ? e.message : "Sign-in failed. Please try again.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function signInGoogle() {
    setBusy(true);
    const { error } = await browserClient().auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${location.origin}/auth/callback?next=${encodeURIComponent(next)}`,
      },
    });
    if (error) {
      setMessage(error.message);
      setBusy(false);
    }
  }
  return (
    <div className="auth-layout">
      <section className="auth-story">
        <Brand />
        <div className="story-copy">
          <div className="eyebrow">
            <span className="status-dot" />A little more present.
          </div>
          <h1>
            Room for the
            <br />
            <em>conversation.</em>
          </h1>
          <p>
            Your ideas, your meetings, your own words.
            <br />
            Keep them close. Take them anywhere.
          </p>
          <div className="story-note">
            <div className="note-top">
              <BrandMark compact />
              <span>From conversation to clarity</span>
              <span className="tag">VOICE NOTES</span>
            </div>
            <Waveform />
            <div className="note-line">
              <Check size={16} />
              <span>The decisions worth remembering.</span>
            </div>
            <div className="note-line">
              <Check size={16} />
              <span>The next steps, already in your notes.</span>
            </div>
          </div>
        </div>
        <div className="story-bottom">
          <span>
            <Laptop size={16} />
            Record on your Mac
          </span>
          <span>
            <Globe2 size={16} />
            Pick up anywhere
          </span>
        </div>
      </section>
      <main id="main" className="auth-form">
        <div className="auth-form-inner">
          <span className="eyebrow">YOUR CONVERSATIONS, CONNECTED</span>
          <h2>
            {mode === "signup"
              ? "Make yourself at home."
              : mode === "reset"
                ? "Choose a new password."
                : "Welcome back."}
          </h2>
          <p>
            {mode === "reset"
              ? "Enter your email and we'll send a link to set a new password."
              : "Sign in to find your notes and connect the apps you think with."}
          </p>
          {!ready ? (
            <div className="notice">
              Your cloud workspace is being prepared. Recording and notes remain
              available in the Mac app.
            </div>
          ) : (
            <>
              {google ? (
                <button
                  className="button google-button"
                  disabled={busy}
                  onClick={signInGoogle}
                >
                  <span className="google-g">G</span>Continue with Google
                  <ArrowRight size={17} />
                </button>
              ) : (
                <div className="notice">
                  Google sign-in is being connected. Email sign-in is available
                  below.
                </div>
              )}
              <div className="or">
                <span>or use your email</span>
              </div>
              <form onSubmit={submit}>
                <label htmlFor="email">Email address</label>
                <input
                  id="email"
                  type="email"
                  autoComplete="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                />
                {mode !== "email" && mode !== "reset" && (
                  <>
                    <label htmlFor="password">Password</label>
                    <input
                      id="password"
                      type="password"
                      autoComplete={
                        mode === "signup" ? "new-password" : "current-password"
                      }
                      minLength={8}
                      required
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                    />
                  </>
                )}
                <button className="button primary wide" disabled={busy}>
                  {busy
                    ? "Connecting…"
                    : mode === "signup"
                      ? "Create your account"
                      : mode === "email"
                        ? "Email me a sign-in link"
                        : mode === "reset"
                          ? "Email me a reset link"
                          : "Sign in"}
                  <ArrowRight size={17} />
                </button>
              </form>
              <div className="auth-options">
                <button
                  onClick={() =>
                    setMode(mode === "signup" ? "login" : "signup")
                  }
                >
                  {mode === "signup"
                    ? "Already have an account? Sign in"
                    : "Create an account"}
                </button>
                <button
                  onClick={() => setMode(mode === "email" ? "login" : "email")}
                >
                  {mode === "email" ? "Use a password" : "Use a sign-in link"}
                </button>
                {mode === "login" && (
                  <button onClick={() => setMode("reset")}>
                    Forgot your password?
                  </button>
                )}
                {mode === "reset" && (
                  <button onClick={() => setMode("login")}>Back to sign in</button>
                )}
              </div>
            </>
          )}
          {message && (
            <p className="notice" role="status">
              {message}
            </p>
          )}
          <p className="privacy-foot">
            Your notes belong to you.{" "}
            <Link href="/privacy">How Voice Notes handles your data</Link>
          </p>
        </div>
      </main>
    </div>
  );
}
