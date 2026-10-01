# Mail review — 1 October 2026

This batch implements Jason’s Mail review without changing the selected workspace design or native app identity. Notes save in Concourse. Email drafts now save in Concourse first and sync to Gmail, with separate status and device recovery when either destination is unavailable.

## Implemented

- Enabled From account selection for new messages and replies, including All inboxes. Changing sender preserves recipients, body and attachments while keeping provider draft/thread IDs scoped to their mailbox. The previous sender’s saved copy remains available.
- Inline reply, reply-all and forward keep the thread in the reader. Back, mailbox changes and reader navigation save the draft before closing it. Main-route interruption retains immediate device recovery.
- Top conversation actions expose reply, reply-all, forward, archive, unread, star, bin and Create note. Less frequent actions remain in More.
- Remote images load when a message opens; per-message blocking remains available. Sanitisation, the script-free iframe and no-referrer policy remain in place. Existing embedded-image hydration is retained.
- Create note explicitly copies the chosen email into a Concourse note with sender, recipients, timestamp and mailbox context, then offers Open note without abandoning the thread. Repeated clicks and acknowledgement retries reuse one note ID.
- Concourse drafts appear in Drafts with provider-only copies deduplicated by mailbox/provider ID. Queued drafts move to Outbox; cancelling returns their Concourse copy to Drafts.

## Storage and concurrency

`mail_drafts` is first-party, owner-scoped storage. Authenticated clients can select their own drafts only through the editor policy; direct client writes, anonymous access and connected AI clients are denied. The authenticated Mail API validates mailbox ownership and performs versioned server writes. Concourse accepts unfinished addresses for recovery; Gmail and send operations still require valid recipients.

A provider creation whose acknowledgement is interrupted is retained as uncertain and is not silently repeated. A changed Gmail revision or a second-session Concourse version preserves device edits and requires review/new-copy recovery. Provider IDs are retained as soon as acknowledged. No general ChatGPT authentication or AI generation is added.

Local migration: `20261001074953_mail_draft_workspace.sql`. Applied production migration: `20261001081258_mail_draft_workspace`, project `olxjfdsslbpdvywsnzrc`.

## Verification

- TypeScript: passed.
- Web tests: 336 passed, 2 pre-existing skipped, 32 files.
- Next production build: passed.
- Eight actual local browser scenarios: sender switching, Back/save, reload/reopen, Escape, email-to-note source context, inline forward, mobile width/toolbar/sender access, decoded embedded and HTTPS remote images. Synthetic transports only; sending disabled. Mobile screenshot review found and corrected a pre-existing folders-open/grid interaction that otherwise narrowed the conversation to 140 px.
- Actual production SQL transaction: owner read, other-owner denial, connected-client denial, anonymous denial, direct-write denial, stale-version CAS and mailbox-owner foreign-key checks passed. All synthetic rows rolled back; remaining fixture Auth rows: zero. No live provider tokens or private messages used.
- Security advisor: no new draft-table findings; existing service-only RLS/no-policy informational findings and existing leaked-password warning remain unchanged.

Not run: live Gmail draft creation/update, real sends, private email rendering, two real browser sessions against Gmail, native capture/VoiceOver. Mail changes are hosted web components; the previously installed native checkpoint remains unchanged. This is not a claim of complete Gmail parity.

## Release and rollback

Production web release is authorised by Jason’s instruction to publish and review iteratively. The additive table preserves existing data. Web rollback can use the previous deployment `dpl_DTH553ezTpmkeE35AkJk2QJhf1tn`; keep the new table/drafts rather than deleting user work. The source release and deployment receipts are recorded in the task’s `audit/mail-review` directory.

Next useful batch: source-linked follow-through from an email or note into a reviewable local task/invite, then rich-body editing and account-aware thread/draft recovery. These require explicit functionality boundaries rather than visual parity claims.
