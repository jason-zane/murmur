import { Suspense } from "react";
import { Login } from "./sign-in";
import { cloudReady, googleReady } from "@/lib/config";
export default function Page() {
  return (
    <Suspense fallback={<main className="auth-layout">Loading Voice Notes…</main>}>
      <Login ready={cloudReady()} google={googleReady()} />
    </Suspense>
  );
}
