import { addresses, emailAddress } from "./recipients";

/** Display the supplied name, never invent one; retain the address as a fallback. */
export function senderName(value: string): string {
  const first = addresses(value)[0] || "";
  const left = first.indexOf("<"), right = first.lastIndexOf(">");
  if (left >= 0 && right > left) {
    let name = first.slice(0, left).trim();
    if (name.startsWith('"') && name.endsWith('"')) name = name.slice(1, -1).replace(/\\(["\\])/g, "$1");
    if (name) return name;
    return first.slice(left + 1, right).trim() || "Unknown sender";
  }
  return emailAddress(first) || "Unknown sender";
}

export type MailReadingLayout = "split" | "full";
export const readingLayoutKey = (userID: string, preview: boolean) => `concourse:mail-reading-layout:${preview ? "preview:" : ""}${userID}`;
