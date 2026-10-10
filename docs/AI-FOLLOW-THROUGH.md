# Reviewable follow-through and provider choice — proposal

This is a design proposal, not an implemented AI integration. Concourse should help a broad audience finish work across mail, calendars and notes while keeping every consequential action reviewable. The next bounded implementation should be a local, synthetic **meeting note → follow-up draft** flow. It can prove the interactions before provider access, private-data transmission or email delivery is enabled.

## Separate three connections

| Connection | Owns | Must not imply |
| --- | --- | --- |
| Concourse account | Identity, library synchronisation, app preferences | Google or model access |
| Product services | Mail/calendar scopes, transcription, storage | Permission to send or spend without review |
| AI provider and funding | Provider, model, allowed capabilities, quota/billing source | Access to all content or permission to fall back to a paid provider |

Keep the existing read-only MCP connection (“ask another app about my notes”) separate from model inference inside Concourse. They have different data movement, authentication and user expectations.

## Provider adapter

Use one capability-aware adapter contract with `listModels`, `capabilities`, `generateText`, `cancel` and normalised errors. Providers: mock, an approved ChatGPT connection, BYO API key, a configured local model, and a later explicitly funded hosted option. Store a stable connection ID, capability snapshot, funding label and selected model with each job. Secret storage belongs in the Mac Keychain or server secret store, never client bundles, prompts or logs.

Capabilities should distinguish text, structured output, custom tools, audio transcription, audio input, streaming and context limits. Show incompatible providers clearly. Model lists must come from the authorised provider rather than a hard-coded assumption. Quota exhaustion pauses work with its existing inputs and edits intact. Never switch funding sources silently. A user can explicitly retry on another provider after reviewing what content it will receive and how it is funded.

OpenAI’s Sign in with ChatGPT can support eligible third-party text inference, with identity and inference authorised separately. It uses an eligible plan’s existing Codex/ChatGPT Work allowance. Commercial availability is a selected-partner trial: Concourse’s remotely hosted or paid distribution is **not confirmed eligible**. The documented personal/local/open-source route requires its own registered client and PKCE flow; do not reuse installed Codex credentials. [Client access](https://developers.openai.com/siwc/request-client-id), [sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in).

For an eligible implementation, use the public Responses API with `store: false`, `stream: true` and authorised model discovery; treat terminal completion as success, never partial streamed text. There is no implied access to ChatGPT conversations or memory. The preview excludes audio/video inputs and transcription, plus hosted connectors/MCP, file search, Code Interpreter and image generation. Keep dictation and recording transcription on a separate service/local engine. [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference), [preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations), [recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery).

## A durable review item

Persist a stable job ID and input revision before generation. Suggested state machine:

`queued → generating → needs review → approved → applied`

Also support `cancelled`, `interrupted`, `failed`, and `waiting for provider`. Cancellation invalidates the running generation; late responses cannot replace newer work. Regeneration creates a new candidate rather than overwriting edits. A note change makes the candidate visibly out of date. Closing a view preserves the pending review item. Retrying a completed or approved job must not create duplicate drafts or calendar events.

Each item stores source IDs/revisions, provider/model, prompt recipe version, candidate, user edits and application idempotency key. Keep generation and application distinct. Models propose structured candidates; deterministic application code checks account ownership, current permissions, dates, time zones, conflicts and latest source revision again. There is no model-controlled send operation. A draft should be reviewable in Concourse before any provider mailbox draft is created. Sending uses the existing explicit composer action.

## Prompt recipes

Treat all emails, transcripts and notes as untrusted source material. Instructions inside them do not override the recipe. Send only the selected source scope. Validate the schema and evidence references before presenting a candidate; an invalid result remains a recoverable failed job.

| Recipe | Inputs | Structured output | Rules |
| --- | --- | --- | --- |
| `meeting-follow-up/v1` | Selected summary/transcript spans, verified participants, requested tone | Subject, body, recipient suggestions, actions, unknowns, source references | Do not invent commitments, owners, dates, addresses or attendance. Separate decisions from proposed next steps. Unverified recipients remain unselected. |
| `meeting-actions/v1` | Selected meeting spans and explicit date/time-zone context | Action text, owner candidate, due-date candidate, confidence, supporting spans | “Next Friday” is a suggestion with the original phrase and interpreted date visible. Missing owner/date stays empty. |
| `email-meeting-proposal/v1` | One selected email/thread, received timestamp, sender, user time zone | Candidate title, participants, start/end, time zone, ambiguities and evidence | Distinguish a tentative suggestion from a confirmed invitation. Never treat an ambiguous zone or relative date as settled. Conflict checking is deterministic, after extraction. |

A review sheet shows the selected content and provider/funding label, editable candidate, evidence and unresolved fields. Primary actions: **Save draft** or **Add to calendar** after required fields are resolved. Secondary actions: **Regenerate**, **Cancel**, and **Keep for later**. Sending is always a separate explicit step. Return navigation restores the original note/email selection.

## User settings and initial acceptance criteria

Settings should offer per-workflow **Off**, **Suggest when requested**, and **Offer suggestions**; default to requested/reviewable use. Include eligible source scope, default provider/model/funding, and whether to offer follow-ups after summarisation. Avoid an automatic-send mode. Generation history should show what content was used without logging full private payloads by default.

The next mock-only batch is complete when a synthetic note opens a draft review, edits survive cancel/back/navigation, regeneration cannot overwrite edits, late and interrupted responses are ignored, repeated save produces one local draft, source changes require re-review, and quota/provider errors preserve work. Test uncertain recipients, unsupported providers, empty transcripts, long inputs and malicious instructions embedded in notes. No OAuth, provider transmission or mailbox writes are needed to validate this batch.
