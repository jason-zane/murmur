import { describe, expect, it } from "vitest";
import {
  messageDue,
  mimeMessage,
  renderTemplate,
  ruleSchema,
  skipReason,
} from "../src/lib/messages/schema";
describe("meeting messages", () => {
  it("schedules across a DST transition using elapsed time", () => {
    expect(
      messageDue(
        "reminder",
        "2026-10-04T09:00:00+11:00",
        "2026-10-04T09:30:00+11:00",
        1440,
      ),
    ).toBe("2026-10-02T22:00:00.000Z");
  });
  it("only expands supported variables once, preserving guest text", () => {
    expect(
      renderTemplate("Hello {{guest_name}}", {
        guest_name: "{{join_link}}",
        meeting_title: "Intro",
        meeting_time: "Monday",
        join_link: "private",
      }),
    ).toBe("Hello {{join_link}}");
    expect(() => renderTemplate("{{transcript}}", {} as never)).toThrow();
  });
  it("rejects unsupported recipe variables and injected subject headers", () => {
    const rule = {
      event_type_id: "550e8400-e29b-41d4-a716-446655440000",
      kind: "reminder",
      offset_minutes: 60,
      subject: "Hi",
      body: "{{guest_name}}",
      enabled: true,
    };
    expect(ruleSchema.safeParse(rule).success).toBe(true);
    expect(
      ruleSchema.safeParse({ ...rule, body: "{{private_notes}}" }).success,
    ).toBe(false);
    expect(
      ruleSchema.safeParse({
        ...rule,
        subject: "Hi\r\nBcc: victim@example.com",
      }).success,
    ).toBe(false);
  });
  it("suppresses cancelled, moved, disabled and uncompleted messages", () => {
    const b = {
      status: "confirmed",
      starts_at: "2026-09-14T00:00:00Z",
      attendance: "unknown",
    };
    const m = { booking_start: b.starts_at, kind: "reminder" };
    expect(skipReason(m, b, true)).toBeNull();
    expect(skipReason(m, { ...b, status: "cancelled" }, true)).toMatch(
      /cancelled/,
    );
    expect(
      skipReason(m, { ...b, starts_at: "2026-09-14T01:00:00Z" }, true),
    ).toMatch(/moved/);
    expect(skipReason(m, b, false)).toMatch(/off/);
    expect(skipReason({ ...m, kind: "thank_you" }, b, true)).toMatch(
      /completed/,
    );
  });
  it("encodes Unicode messages and prevents recipient header injection", () => {
    const raw = Buffer.from(
      mimeMessage(
        "host@example.com",
        "guest@example.com",
        "Résumé",
        "Hello, Zoë!",
        "id",
      ),
      "base64url",
    ).toString();
    expect(raw).toContain("To: guest@example.com\r\n");
    expect(raw).toContain(Buffer.from("Hello, Zoë!").toString("base64"));
    expect(() =>
      mimeMessage(
        "host@example.com",
        "guest@example.com\r\nBcc: x@example.com",
        "Hi",
        "Body",
        "id",
      ),
    ).toThrow();
  });
});

it("prepares only labelled decisions and actions for review", async () => {
  const { followUpDraft } = await import("../src/lib/messages/schema");
  const draft = followUpDraft(
    "## Private notes\nDo not share this\n## Decisions\nProceed with the pilot\n## Actions\n- Sam: send the plan\n## Transcript\nSensitive discussion",
    "Alex",
  );
  expect(draft).toContain("Proceed with the pilot");
  expect(draft).toContain("Sam: send the plan");
  expect(draft).not.toContain("Do not share");
  expect(draft).not.toContain("Sensitive discussion");
});
