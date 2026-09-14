import { redirect } from "next/navigation";
import { cloudReady } from "@/lib/config";
import { serverClient } from "@/lib/supabase/server";
import { Shell } from "@/components/shell";
export const dynamic = "force-dynamic";
export default async function Page() {
  if (!cloudReady()) redirect("/login");
  const client = await serverClient();
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) redirect("/login");
  return (
    <Shell email={user.email || "Your account"}>
      <header className="page-header">
        <h1>Dictation</h1>
        <p>Dictation history and settings live on your Mac.</p>
      </header>
      <section className="workspace-card">
        <h2>Dictate on your Mac</h2>
        <p>
          Hold your push-to-talk key, speak, then release to insert your words
          into the app you’re using.
        </p>
        <a className="button primary" href="murmur://dictation">
          Open Dictation on Mac
        </a>
      </section>
      <section className="settings-section">
        <h2>History and personalisation</h2>
        <p>
          Dictation history, your dictionary, shortcuts and transcription
          settings are stored on your Mac. They are not uploaded to your Voice
          Notes account.
        </p>
      </section>
    </Shell>
  );
}
