import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, Download, ShieldCheck } from "lucide-react";
import { Brand } from "@/components/brand";
import { latestMac, megabytes, releasesPage } from "@/lib/release";

export const metadata: Metadata = {
  title: "Download Concourse for Mac",
  description:
    "Hold a key and speak anywhere you type. Record a call and keep the notes. A small download for Apple silicon Macs.",
};

export default async function Page() {
  const { version, size } = await latestMac();
  const facts = [
    version && `Version ${version}`,
    megabytes(size),
    "macOS 26 Tahoe or later",
    "Apple silicon",
  ].filter(Boolean);

  return (
    <div className="download-page">
      <header className="download-bar">
        <Brand />
        <Link className="text-link" href="/login">
          Sign in <ArrowRight size={15} />
        </Link>
      </header>
      <main id="main" className="download-main">
        <section className="download-hero">
          <span className="eyebrow">FOR MACOS</span>
          <h1>
            Concourse, <em>on your Mac</em>
          </h1>
          <p>
            Hold a key and speak anywhere you type. Record a call and keep the
            transcript, the notes and the next steps. Everything stays on your
            Mac unless you choose to sign in.
          </p>
          <a
            className="button primary download-button"
            href="/api/download/mac"
          >
            <Download size={18} />
            Download for Mac
          </a>
          <p className="fine-print">{facts.join(" · ")}</p>
        </section>
        <section className="download-steps" aria-labelledby="setup">
          <h2 id="setup">Three steps, once</h2>
          <ol>
            <li>
              <h3>Drag it to Applications</h3>
              <p>
                Open the disk image and drop Concourse onto the Applications
                shortcut beside it. It needs to live there: starting at login
                and the Claude Desktop connection both point at that location.
              </p>
            </li>
            <li>
              <h3>Say yes the first time you open it</h3>
              <p>
                macOS will say it can&rsquo;t verify the app. Concourse is
                signed, but notarising it needs a paid Apple developer account
                this project doesn&rsquo;t have. Open{" "}
                <strong>System Settings ▸ Privacy &amp; Security</strong>,
                scroll to <em>Security</em>, and choose{" "}
                <strong>Open Anyway</strong>. You only do this once — updates
                keep the approval.
              </p>
            </li>
            <li>
              <h3>Grant the microphone and Accessibility</h3>
              <p>
                The first run walks you through it. Accessibility is the one
                macOS won&rsquo;t let an app ask for, so it opens System
                Settings and you switch Concourse on there. Without it, the
                push-to-talk key can&rsquo;t be seen and text can&rsquo;t be
                inserted.
              </p>
            </li>
          </ol>
          <p className="download-assurance">
            <ShieldCheck size={17} />
            <span>
              Dictation and transcription run on your Mac. Signing in is
              optional and only syncs what you record after you do.
            </span>
          </p>
        </section>
        <footer className="download-footer">
          <a
            className="text-link"
            href="https://github.com/jason-zane/murmur/blob/master/docs/INSTALL.md"
          >
            Full install guide <ArrowRight size={15} />
          </a>
          <a className="text-link" href={releasesPage}>
            Release notes <ArrowRight size={15} />
          </a>
        </footer>
      </main>
    </div>
  );
}
