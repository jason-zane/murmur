import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowUpRight, Clock } from "lucide-react";
import { BrandMark } from "@/components/brand";
import { publicProfile } from "@/lib/scheduling/booking";
export const dynamic = "force-dynamic";
const LOCATION: Record<string, string> = {
  google_meet: "Google Meet",
  video_link: "Video call",
  in_person: "In person",
  phone: "Phone call",
};
export async function generateMetadata({ params }: { params: Promise<{ handle: string }> }): Promise<Metadata> {
  const found = await publicProfile((await params).handle).catch(() => null);
  return {
    title: found ? `Book time with ${found.profile.display_name}` : "Booking link",
    robots: { index: false, follow: false },
  };
}
export default async function Page({ params }: { params: Promise<{ handle: string }> }) {
  const { handle } = await params;
  const found = await publicProfile(handle);
  if (!found) notFound();
  const { profile, types } = found;
  return (
    <main id="main" className="book-shell">
      <section className="book-card book-index">
        <span className="book-avatar" aria-hidden="true">
          {profile.display_name[0]?.toUpperCase()}
        </span>
        <h1>{profile.display_name}</h1>
        <p className="book-lede">Choose a meeting to see open times.</p>
        {types.length ? (
          <div className="book-types">
            {types.map((t) => (
              <Link key={t.slug} href={`/book/${profile.handle}/${t.slug}`} className="book-type">
                <span>
                  <strong>{t.title}</strong>
                  <small>
                    <Clock size={13} /> {t.duration_minutes} min · {LOCATION[t.location_kind]}
                  </small>
                  {t.description && <em>{t.description}</em>}
                </span>
                <ArrowUpRight size={17} />
              </Link>
            ))}
          </div>
        ) : (
          <p className="muted">There’s nothing to book right now.</p>
        )}
      </section>
      <p className="book-foot">
        <BrandMark compact /> Scheduling by Voice Notes
      </p>
    </main>
  );
}
