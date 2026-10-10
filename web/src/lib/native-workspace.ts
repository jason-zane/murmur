/** The bearer-to-cookie handoff may open only first-party workspaces. */
export function nativeWorkspaceDestination(path: string | null): string {
  try {
    const target = new URL(path || "/scheduling", "https://native.invalid");
    if (target.origin !== "https://native.invalid" || !["/scheduling", "/connections", "/mail"].includes(target.pathname)) return "/scheduling";
    const focus = target.searchParams.get("focus");
    return target.pathname + (target.pathname === "/connections" && ["calendar", "gmail", "ai"].includes(focus || "") ? `?focus=${focus}` : "");
  } catch { return "/scheduling"; }
}

/** Browser handoffs can continue only a Google connection on this origin. */
export function nativeGoogleDestination(path: string | null): string | null {
  try {
    const target = new URL(path || "", "https://native.invalid");
    if (target.origin !== "https://native.invalid" || target.pathname !== "/api/google/connect") return null;
    const query = new URLSearchParams();
    for (const key of ["add", "booking", "mail", "inbox", "account", "expected_user"]) {
      const value = target.searchParams.get(key);
      if (value) query.set(key, value);
    }
    return target.pathname + (query.size ? `?${query}` : "");
  } catch { return null; }
}
