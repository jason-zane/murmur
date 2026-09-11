import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { BrandMark } from "@/components/brand";
import { publicEventType } from "@/lib/scheduling/booking";
import { Booker } from "./booker";
export const dynamic = "force-dynamic";
type Params = { params: Promise<{ handle: string; slug: string }> };
export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { handle, slug } = await params;
  const found = await publicEventType(handle, slug).catch(() => null);
  return {
    title: found ? `${found.type.title} with ${found.profile.display_name}` : "Booking link",
    robots: { index: false, follow: false },
  };
}
// Only what a guest needs reaches the page: never the host's account or calendars.
export default async function Page({ params }: Params) {
  const { handle, slug } = await params;
  const found = await publicEventType(handle, slug);
  if (!found) notFound();
  const { profile, type } = found;
  return (
    <main id="main" className="book-shell">
      <Booker
        handle={profile.handle}
        slug={type.slug}
        host={profile.display_name}
        title={type.title}
        description={type.description}
        duration={type.duration_minutes}
        location={type.location_kind}
        questions={type.questions}
      />
      <p className="book-foot">
        <BrandMark compact /> Scheduling by Voice Notes
      </p>
    </main>
  );
}
