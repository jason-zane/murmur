import { describe, expect, it } from "vitest";
import { nativeWorkspaceDestination } from "../src/lib/native-workspace";
describe("native authenticated workspace destinations", () => {
  it("preserves the chosen setup task and opens the mailbox", () => {
    expect(nativeWorkspaceDestination("/connections?focus=gmail")).toBe("/connections?focus=gmail");
    expect(nativeWorkspaceDestination("/connections?focus=calendar")).toBe("/connections?focus=calendar");
    expect(nativeWorkspaceDestination("/connections?focus=ai")).toBe("/connections?focus=ai");
    expect(nativeWorkspaceDestination("/mail")).toBe("/mail");
  });
  it("rejects external origins and strips unrecognised query data", () => {
    for (const path of ["https://attacker.invalid/mail", "//attacker.invalid/connections", "/api/google/connect", "/notes", "https://["]) expect(nativeWorkspaceDestination(path)).toBe("/scheduling");
    expect(nativeWorkspaceDestination("/connections?focus=bad&next=https://attacker.invalid")).toBe("/connections");
    expect(nativeWorkspaceDestination("/mail?token=untrusted")).toBe("/mail");
  });
});

describe("native Google browser handoff", () => {
  it("allows only the first-party Google connect endpoint and recognised options", async () => {
    const { nativeGoogleDestination } = await import("../src/lib/native-workspace");
    expect(nativeGoogleDestination("/api/google/connect?add=1&inbox=1&expected_user=owner&redirect=https://evil.invalid")).toBe("/api/google/connect?add=1&inbox=1&expected_user=owner");
    for (const value of [null, "https://evil.invalid/api/google/connect", "//evil.invalid/api/google/connect", "/mail", "/api/account"]) expect(nativeGoogleDestination(value)).toBeNull();
  });
});
