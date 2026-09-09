import Link from "next/link";
import { Brand } from "@/components/brand";
export default function NotFound() {
  return (
    <main id="main" className="consent">
      <Brand />
      <h1>This page has wandered off.</h1>
      <p>Your notes are still where you left them.</p>
      <Link href="/" className="button primary">
        Back to your library
      </Link>
    </main>
  );
}
