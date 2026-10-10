import { describe, it, expect } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { agenda } from "../src/lib/calendar";
function client(accounts: Record<string, unknown>[]) {
  return { from: (table: string) => {
    const q: any = { select: () => q, gt: () => q, lt: () => q, order: () => q, limit: () => q, maybeSingle: () => q,
      then: (resolve: (value: unknown) => unknown) => Promise.resolve({ data: table === "calendar_connections" ? accounts : table === "booking_profiles" ? null : [], error: null }).then(resolve) };
    return q;
  } } as unknown as SupabaseClient;
}
describe("calendar connection capability status", () => {
  const gmail = { id: "gmail", email: "mail@example.invalid", scopes: ["https://www.googleapis.com/auth/gmail.modify"], updated_at: null, error: "Mail needs attention" };
  const calendar = { id: "calendar", email: "calendar@example.invalid", scopes: ["https://www.googleapis.com/auth/calendar.readonly"], updated_at: "2026-09-30T00:00:00Z", error: null };
  it("keeps a Gmail-only account available without reporting a calendar connection", async () => {
    const result = await agenda(client([gmail]));
    expect(result.connections).toHaveLength(1);
    expect(result.connection).toBeNull();
  });
  it("uses the calendar account's status when Gmail was connected first", async () => {
    const result = await agenda(client([gmail, calendar]));
    expect(result.connections).toHaveLength(2);
    expect(result.connection).toMatchObject({ email: calendar.email, error: null, updated_at: calendar.updated_at });
  });
});
