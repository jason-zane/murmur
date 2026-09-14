import { afterAll, beforeAll, expect, it, vi } from "vitest";
import { createClient } from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "node:crypto";
import { encryptToken } from "../src/lib/calendar";
import {
  SEND_SCOPE,
  dispatchMessage,
  materialiseMessages,
} from "../src/lib/messages/service";
import { bookingOperation } from "../src/lib/scheduling/operation";
const api = process.env.NEXT_PUBLIC_SUPABASE_URL!;
if (api !== "http://127.0.0.1:56321")
  throw new Error("Isolated local Murmur required.");
process.env.GOOGLE_TOKEN_ENCRYPTION_KEY ||= randomBytes(32).toString("base64");
const admin = createClient(api, process.env.SUPABASE_SECRET_KEY!, {
  auth: { persistSession: false, autoRefreshToken: false },
});
let uid: string,
  bid: string,
  cid: string,
  tid: string,
  other: string,
  ownerToken: string,
  otherToken: string;
let sent = 0,
  timeout = false;
const realFetch = globalThis.fetch;
vi.stubGlobal(
  "fetch",
  async (input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (url.origin === "https://oauth2.googleapis.com")
      return Response.json({ access_token: "local-only", scope: SEND_SCOPE });
    if (url.origin === "https://gmail.googleapis.com") {
      sent++;
      if (timeout) throw new Error("timeout");
      return Response.json({ id: `mail-${sent}` });
    }
    if (url.origin !== api)
      throw new Error(`Unexpected network request: ${url.origin}`);
    return realFetch(input, init);
  },
);
const must = <T>(r: { data: T; error: unknown }) => {
  if (r.error) throw r.error;
  return r.data as NonNullable<T>;
};
beforeAll(async () => {
  const owner = await admin.auth.admin.createUser({
    email: `mail-${randomUUID()}@example.invalid`,
    email_confirm: true,
  });
  if (owner.error) throw owner.error;
  uid = owner.data.user.id;
  const ownerLink = await admin.auth.admin.generateLink({
    type: "magiclink",
    email: owner.data.user.email!,
  });
  if (ownerLink.error) throw ownerLink.error;
  const ownerSession = await createClient(
    api,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  ).auth.verifyOtp({
    type: "email",
    token_hash: ownerLink.data.properties.hashed_token,
  });
  if (ownerSession.error) throw ownerSession.error;
  ownerToken = ownerSession.data.session!.access_token;
  const second = await admin.auth.admin.createUser({
    email: `other-${randomUUID()}@example.invalid`,
    email_confirm: true,
  });
  if (second.error) throw second.error;
  other = second.data.user.id;
  const otherLink = await admin.auth.admin.generateLink({
    type: "magiclink",
    email: second.data.user.email!,
  });
  if (otherLink.error) throw otherLink.error;
  const otherSession = await createClient(
    api,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  ).auth.verifyOtp({
    type: "email",
    token_hash: otherLink.data.properties.hashed_token,
  });
  if (otherSession.error) throw otherSession.error;
  otherToken = otherSession.data.session!.access_token;
  cid = must(
    await admin
      .from("calendar_connections")
      .insert({
        user_id: uid,
        provider: "google",
        email: "host@example.invalid",
        scopes: [SEND_SCOPE],
      })
      .select("id")
      .single(),
  ).id;
  must(
    await admin
      .from("calendar_credentials")
      .insert({
        connection_id: cid,
        user_id: uid,
        encrypted_refresh_token: encryptToken("local-only"),
      }),
  );
  must(
    await admin
      .from("mail_settings")
      .insert({ user_id: uid, connection_id: cid, enabled: true }),
  );
  tid = must(
    await admin
      .from("event_types")
      .insert({
        user_id: uid,
        title: "Intro",
        slug: "intro",
        duration_minutes: 30,
        location_kind: "google_meet",
        summary_template: "meeting",
      })
      .select("id")
      .single(),
  ).id;
  bid = must(
    await admin
      .from("bookings")
      .insert({
        user_id: uid,
        event_type_id: tid,
        title: "Intro",
        status: "confirmed",
        starts_at: new Date(Date.now() + 3600000).toISOString(),
        ends_at: new Date(Date.now() + 5400000).toISOString(),
        guest_name: "Guest",
        guest_email: "guest@example.invalid",
        guest_time_zone: "Australia/Sydney",
        summary_template: "meeting",
        location_kind: "google_meet",
        manage_token_hash: "a".repeat(64),
      })
      .select("id")
      .single(),
  ).id;
});
afterAll(async () => {
  vi.unstubAllGlobals();
  if (uid) await admin.auth.admin.deleteUser(uid);
  if (other) await admin.auth.admin.deleteUser(other);
});
async function draft() {
  const b = must(
    await admin.from("bookings").select("starts_at").eq("id", bid).single(),
  );
  return must(
    await admin
      .from("booking_messages")
      .insert({
        user_id: uid,
        booking_id: bid,
        booking_start: b.starts_at,
        kind: "follow_up",
        subject: "Follow-up",
        body: "Only reviewed content",
        due_at: new Date().toISOString(),
      })
      .select("id")
      .single(),
  ).id;
}
it("serialises booking edits and email operations", async () => {
  await bookingOperation(bid, async () => {
    await expect(bookingOperation(bid, async () => true)).rejects.toThrow(
      /being updated/,
    );
  });
  expect(await bookingOperation(bid, async () => true)).toBe(true);
});
it("only the owner can send, and repeat calls cannot duplicate a send", async () => {
  const id = await draft();
  await expect(dispatchMessage(id, other)).rejects.toThrow(/not found/);
  expect(await dispatchMessage(id, uid)).toEqual({ status: "sent" });
  expect(sent).toBe(1);
  await expect(dispatchMessage(id, uid)).rejects.toThrow(/already/);
  expect(sent).toBe(1);
});
it("does not retry ambiguous provider acceptance", async () => {
  const id = await draft();
  timeout = true;
  expect(await dispatchMessage(id, uid)).toEqual({ status: "needs_attention" });
  timeout = false;
  const count = sent;
  await expect(dispatchMessage(id, uid)).rejects.toThrow(/already/);
  expect(sent).toBe(count);
});
it("materialises once per rule, booking and start time", async () => {
  must(
    await admin
      .from("booking_message_rules")
      .insert({
        user_id: uid,
        event_type_id: tid,
        kind: "reminder",
        subject: "Hi {{guest_name}}",
        body: "{{meeting_time}}",
        offset_minutes: 10,
        enabled: true,
      }),
  );
  await materialiseMessages();
  await materialiseMessages();
  const rows = must(
    await admin
      .from("booking_messages")
      .select("id")
      .eq("booking_id", bid)
      .eq("kind", "reminder"),
  );
  expect(rows).toHaveLength(1);
});
it("suppresses old messages after rescheduling or cancellation", async () => {
  const id = await draft();
  must(
    await admin.from("bookings").update({ status: "cancelled" }).eq("id", bid),
  );
  const count = sent;
  expect(await dispatchMessage(id, uid)).toEqual({ status: "skipped" });
  expect(sent).toBe(count);
});

it("isolates private mail data and forbids direct client writes", async () => {
  const client = (token: string) =>
    createClient(api, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
  expect(
    must(await client(ownerToken).from("mail_settings").select("user_id")),
  ).toHaveLength(1);
  expect(
    must(await client(otherToken).from("mail_settings").select("user_id")),
  ).toHaveLength(0);
  expect(
    (
      await client(ownerToken)
        .from("mail_settings")
        .update({ enabled: false })
        .eq("user_id", uid)
    ).error,
  ).not.toBeNull();
  expect(
    (
      await client(ownerToken).rpc("claim_booking_operation", {
        p_id: bid,
        p_key: randomUUID(),
      })
    ).error,
  ).not.toBeNull();
});
