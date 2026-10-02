import { describe, expect, it } from "vitest";
import { senderName, readingLayoutKey } from "../src/lib/mail/presentation";
import { replyRecipients } from "../src/lib/mail/recipients";

describe("readable mail sender identity", () => {
  it.each([
    ["Priya Example <priya@example.com>", "Priya Example"],
    ['"Doe, Jane" <jane@example.com>', "Doe, Jane"],
    ['"Jane \\"JJ\\" Doe" <jane@example.com>', 'Jane "JJ" Doe'],
    ["Zoë 李 <zoe@example.com>", "Zoë 李"],
    ["sam@example.com", "sam@example.com"],
    ['"" <sam@example.com>', "sam@example.com"],
    ["<sam@example.com>", "sam@example.com"],
    ["", "Unknown sender"],
  ])("labels %s without exposing address chrome", (source, expected) => {
    expect(senderName(source)).toBe(expected);
  });
  it("does not change the address used for a reply", () => {
    const message = {from: '"Doe, Jane" <jane@example.com>', reply_to: "", to: "sam@example.com", cc: ""};
    expect(senderName(message.from)).toBe("Doe, Jane");
    expect(replyRecipients(message, "sam@example.com")).toEqual({ to: ["jane@example.com"], cc: [] });
  });
  it("separates synthetic and authenticated layout preferences by owner", () => {
    expect(readingLayoutKey("one", false)).not.toBe(readingLayoutKey("one", true));
    expect(readingLayoutKey("one", false)).not.toBe(readingLayoutKey("two", false));
  });
});
