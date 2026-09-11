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
          An AI app you authorise can read your synced library, upcoming
          calendar events, booking links and bookings, and can suggest free
          times. It cannot change anything. Text it requests is shared with
          that provider. You can revoke authorisation in Connections;
          already-issued access tokens
          remain valid until they expire, for up to one hour.
        </p>
        <h2>Google Calendar</h2>
        <p>
          Connecting Google Calendar lets Voice Notes read events from the
          calendars you choose, across one or more Google accounts. Voice Notes
          stores an encrypted refresh token for each account so it can refresh
          your agenda. Disconnecting an account removes its token and its synced
          events.
        </p>
        <h2>Booking links</h2>
        <p>
          If you turn on booking links, Google asks for two more permissions on
          that account: to see when you’re busy and to add meetings to your
          calendar. When someone books, the event is created on your calendar
          and Google sends the invitation from your account. Voice Notes does
          not email guests. The guest’s name, email address, time zone and
          answers are stored with the booking so they appear with the meeting.
          Busy times shared from your Mac contain only start and end times.
          Booking pages are rate limited using a keyed hash of the visitor’s
          network address; raw addresses are not stored.
        </p>
        <h2>Keeping a copy</h2>
        <p>
          You can export Markdown from the web app. The Mac library consists of
          ordinary Markdown and JSON files in Application
          Support/Murmur/sessions, with previous note revisions retained.
        </p>
        <h2>Removing data</h2>
        <p>
          Deleting a local note does not delete its cloud copy. You can delete
          your whole account from Settings: that removes your synced notes and
          revisions, calendar connections, booking links, bookings and connected
          apps at once. The notes on your Mac stay where they are. There are no
          analytics or advertising cookies.
        </p>
      </div>
      <Link className="text-link" href="/">
        Back to your notes
      </Link>
    </main>
  );
}
