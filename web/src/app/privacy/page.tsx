import Link from "next/link";
import { Brand } from "@/components/brand";
export default function Page() {
  return (
    <main id="main" className="privacy-page">
      <Brand />
      <h1>Your words belong to you.</h1>
      <div className="prose">
        <h2>On your Mac</h2>
        <p>
          Voice Notes records and transcribes on your device. Dictation and your
          local note files work without a cloud account. Editor recovery drafts
          stay on the device where you wrote them.
        </p>
        <h2>When you connect an account</h2>
        <p>
          Completed meeting transcripts, written notes, titles, speaker names
          and participant details sync to your account. Vercel runs the web app
          and Supabase stores account data. Audio recordings are not uploaded by
          cloud sync.
        </p>
        <h2>Your connected apps</h2>
        <p>
          An AI app you authorize can read your synced library and upcoming
          calendar events. Text it requests is shared with that provider. You
          can revoke authorization in Connections; already-issued access tokens
          remain valid until they expire, for up to one hour.
        </p>
        <h2>Google Calendar</h2>
        <p>
          Connecting Google Calendar grants read-only access to your primary
          calendar. Voice Notes stores an encrypted refresh token so it can refresh
          your agenda. Disconnecting removes that token and the synced calendar
          events.
        </p>
        <h2>Keeping a copy</h2>
        <p>
          You can export Markdown from the web app. The Mac library consists of
          ordinary Markdown and JSON files in Application
          Support/Murmur/sessions, with previous note revisions retained.
        </p>
        <h2>Removing data</h2>
        <p>
          Deleting a local note does not delete its cloud copy. Account removal
          currently requires the project owner to delete the account through
          Supabase; that cascades to its notes, revisions, calendar events and
          credentials. This is a personal deployment with no analytics or
          advertising cookies.
        </p>
      </div>
      <Link className="text-link" href="/">
        Back to your notes
      </Link>
    </main>
  );
}
