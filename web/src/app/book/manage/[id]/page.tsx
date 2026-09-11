import type { Metadata } from "next";
import { BrandMark } from "@/components/brand";
import { ManageBooking } from "./manage";
export const metadata: Metadata = { title: "Your booking", robots: { index: false, follow: false } };
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <main id="main" className="book-shell">
      <ManageBooking id={id} />
      <p className="book-foot">
        <BrandMark compact /> Scheduling by Voice Notes
      </p>
    </main>
  );
}
