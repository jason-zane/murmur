// Auth 2.196 returns a bare array. auth-js spreads it into numbered properties;
// newer Auth versions return { clients }. Reject unfamiliar shapes so a setup
// retry cannot silently create a duplicate first-party client.
export function clientsFromResponse(data) {
  if (!data || typeof data !== "object") throw new Error("Missing OAuth client list.");
  if (Array.isArray(data.clients)) return data.clients;
  const keys = Object.keys(data);
  const metadata = new Set(["nextPage", "lastPage", "total"]);
  if (!keys.includes("total") || keys.some((key) => !metadata.has(key) && !/^\d+$/.test(key)))
    throw new Error("Unrecognized OAuth client list; registration was not attempted.");
  return keys.filter((key) => /^\d+$/.test(key)).sort((a, b) => Number(a) - Number(b)).map((key) => data[key]);
}

export async function findDesktopClient(oauth) {
  for (let page = 1; ; page++) {
    const { data, error } = await oauth.listClients({ page, perPage: 100 });
    if (error) throw error;
    const clients = clientsFromResponse(data);
    const desktop = clients.find((client) =>
      ["Voice Notes for Mac", "Murmur for Mac"].includes(client.client_name) &&
      client.redirect_uris?.includes("murmur://oauth/callback"),
    );
    if (desktop) return desktop;
    if (clients.length < 100) return null;
  }
}
