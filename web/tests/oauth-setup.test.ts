import { describe, expect, it } from "vitest";
import { clientsFromResponse, findDesktopClient } from "../scripts/oauth-clients.mjs";

describe("production OAuth setup compatibility", () => {
  it("accepts the empty client list returned by the production Auth version", () => {
    expect(clientsFromResponse({ nextPage: null, lastPage: 0, total: 0 })).toEqual([]);
  });
  it("finds an existing Mac registration in both server response formats", async () => {
    const client = { client_id: "existing-mac", client_name: "Murmur for Mac", redirect_uris: ["murmur://oauth/callback"] };
    for (const data of [{ clients: [client] }, { 0: client, total: 0, nextPage: null, lastPage: 0 }]) {
      expect(await findDesktopClient({ listClients: async () => ({ data, error: null }) })).toBe(client);
    }
  });
  it("checks later pages before allowing a new registration", async () => {
    const client = { client_id: "existing-mac", client_name: "Voice Notes for Mac", redirect_uris: ["murmur://oauth/callback"] };
    const pages: number[] = [];
    expect(await findDesktopClient({ listClients: async ({ page }: { page: number }) => {
      pages.push(page);
      return { data: { clients: page === 1 ? Array.from({ length: 100 }, () => ({ client_name: "Other app" })) : [client] }, error: null };
    } })).toBe(client);
    expect(pages).toEqual([1, 2]);
  });
  it("stops on an unexpected response instead of creating duplicate credentials", () => {
    expect(() => clientsFromResponse({ records: [] })).toThrow("registration was not attempted");
  });
});
