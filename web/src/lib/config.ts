export const siteURL = () =>
  (process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000").replace(
    /\/$/,
    "",
  );
export const cloudReady = () =>
  Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL &&
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  );
export const googleReady = () =>
  process.env.NEXT_PUBLIC_GOOGLE_ENABLED === "true";
export const safeNext = (value: string | null | undefined) =>
  value?.startsWith("/") &&
  !value.startsWith("//") &&
  !/[\\\u0000-\u0020\u007f]/.test(value)
    ? value
    : "/";
