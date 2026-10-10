import { z } from "zod";
import { sessionID } from "../documents";

// A saved proposal is never a mailbox draft or an instruction to dispatch mail.
export const FOLLOW_UP_RECIPE = "meeting-follow-up/v1" as const;
export const followUpFields = z.object({
  // Incomplete typing is durable work; address validity is an approval gate.
  recipient: z.string().max(254).refine(value => !/[\r\n]/.test(value)),
  subject: z.string().max(200).refine(value => !/[\r\n]/.test(value)),
  body: z.string().max(10000),
}).strict();
export const followUpDocument = z.object({
  sourceVersion: z.number().int().min(1).max(Number.MAX_SAFE_INTEGER),
  recipe: z.literal(FOLLOW_UP_RECIPE),
  fields: followUpFields,
  evidence: z.array(z.object({
    kind: z.enum(["note", "transcript", "bullet"]),
    id: z.string().min(1).max(128),
    text: z.string().min(1).max(2000).refine(value => Boolean(value.trim())),
  }).strict()).max(30),
  unknowns: z.array(z.string().min(1).max(500)).max(20),
  reviewed: z.boolean(),
}).strict().superRefine((document, ctx) => {
  if (document.reviewed && (!z.email().safeParse(document.fields.recipient).success || !document.fields.subject.trim() ||
      !document.fields.body.trim() || !document.evidence.length || document.unknowns.length)) {
    ctx.addIssue({ code: "custom", message: "Confirm the recipient, wording, evidence and missing details before marking this draft reviewed." });
  }
  const keys = document.evidence.map(item => `${item.kind}:${item.id}:${item.text}`);
  if (new Set(keys).size !== keys.length) ctx.addIssue({ code: "custom", message: "Duplicate source evidence." });
});
export const followUpWrite = z.object({
  document: followUpDocument,
  expectedVersion: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
}).strict();
export { sessionID as followUpSourceID };
export type FollowUpDocument = z.infer<typeof followUpDocument>;
export type SavedFollowUp = { session_id: string; version: number; document: FollowUpDocument; updated_at: string };

/** Preserve the saved wording, but never present old source approval as current. */
export function effectiveFollowUp(draft: SavedFollowUp | null, sourceVersion: number) {
  const sourceChanged = Boolean(draft && draft.document.sourceVersion !== sourceVersion);
  return {
    draft: draft && sourceChanged ? { ...draft, document: { ...draft.document, reviewed: false } } : draft,
    sourceVersion,
    sourceChanged,
  };
}
