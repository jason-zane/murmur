import { describe, expect, it } from "vitest";
import { randomBytes } from "node:crypto";
import {
  documentSchema,
  matches,
  meetingURL,
  newDocument,
} from "../src/lib/documents";
import { safeNext } from "../src/lib/config";
import {
  decryptToken,
  encryptToken,
  normalizeEvent,
} from "../src/lib/calendar";
import { limitedJSON } from "../src/lib/http";

describe("cloud boundary", () => {
  it("accepts native documents without a summary, excluding private recovery state", () => {
    const value = {
      ...newDocument("Résumé planning"),
      note: undefined,
      editingDraft: "Private unfinished thought",
    };
    const result = documentSchema.parse(value);
    expect(result.note).toBeNull();
    expect("editingDraft" in result).toBe(false);
    expect(matches(result, "résumé")).toBe(true);
  });
  it("rejects unfinished capture and unsafe IDs", () => {
    const doc = newDocument();
    doc.session.state = "recording" as never;
    expect(documentSchema.safeParse(doc).success).toBe(false);
    doc.session.state = "raw";
    doc.session.id = "../another-person";
    expect(documentSchema.safeParse(doc).success).toBe(false);
  });
  it("searches the complete source including the last segment", () => {
    const doc = newDocument();
    doc.transcript = Array.from({ length: 1000 }, (_, i) => ({
      id: crypto.randomUUID(),
      start: i,
      end: i + 1,
      source: "call",
      text: i === 999 ? "Cobalt decision on Monday" : "Ordinary discussion",
    }));
    expect(matches(doc, "Cobalt Monday")).toBe(true);
    expect(matches(doc, "Tuesday")).toBe(false);
  });
  it("does not accept redirects or meeting links with hostile origins", () => {
    for (const path of [
      "//evil.test",
      "/\\evil.test",
      "/\n/evil.test",
      "https://evil.test",
    ])
      expect(safeNext(path)).toBe("/");
    expect(safeNext("/oauth/consent?authorization_id=abc")).toContain(
      "/oauth/consent",
    );
    for (const value of [
      "https://meet.google.com.evil.test/abc",
      "javascript:alert(1)",
      "http://meet.google.com/abc",
      "https://user:secret@meet.google.com/abc",
    ])
      expect(meetingURL(value)).toBeNull();
    expect(meetingURL("https://meet.google.com/abc-defg-hij")).toBe(
      "https://meet.google.com/abc-defg-hij",
    );
  });
  it("limits streamed request bodies even without Content-Length", async () => {
    const request = new Request("http://localhost/api", {
      method: "POST",
      body: '{"payload":"too much data"}',
    });
    await expect(limitedJSON(request, 10)).rejects.toMatchObject({
      status: 413,
    });
  });
  it("encrypts Google credentials and detects tampering", () => {
    process.env.GOOGLE_TOKEN_ENCRYPTION_KEY =
      randomBytes(32).toString("base64");
    const value = encryptToken("fixture-refresh-token");
    expect(value).not.toContain("fixture-refresh-token");
    expect(decryptToken(value)).toBe("fixture-refresh-token");
    const parts = value.split(".");
    const bytes = Buffer.from(parts[2], "base64url");
    bytes[0] ^= 1;
    parts[2] = bytes.toString("base64url");
    expect(() => decryptToken(parts.join("."))).toThrow();
  });
  it("ignores cancelled, declined and all-day calendar blocks", () => {
    const event = {
      id: "meeting",
      summary: "Planning",
      start: { dateTime: "2026-09-09T10:00:00+10:00" },
      end: { dateTime: "2026-09-09T11:00:00+10:00" },
      hangoutLink: "https://meet.google.com/abc-defg-hij",
    };
    expect(normalizeEvent(event)?.meeting_url).toContain("meet.google.com");
    expect(normalizeEvent({ ...event, status: "cancelled" })).toBeNull();
    expect(
      normalizeEvent({
        ...event,
        attendees: [{ self: true, responseStatus: "declined" }],
      }),
    ).toBeNull();
    expect(
      normalizeEvent({ ...event, start: { date: "2026-09-09" } }),
    ).toBeNull();
  });
});
