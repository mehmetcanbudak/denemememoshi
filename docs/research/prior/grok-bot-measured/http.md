# Grok Bot as measured: MemoBot protocol 1 (secondary source)

**Status:** Draft 4 · 2026-10-20 · imported prior research; everything below the `BEGIN VERBATIM COPY` marker is a frozen, byte-identical copy of the source
**Owns:** Memoshi's archived copy of MemoBot's `spec/http.md`, the HTTP and event protocol MemoBot designed for its Grok Bot re-implementation, kept for its state-machine rules
**Depends on:** [Research index](../../README.md) · [behavior.md](behavior.md) · [CONTEXT.md](CONTEXT.md) · [D13](../../../plan/decisions.md#d13) · [D33](../../../plan/decisions.md#d33) · [`protocol.md`](../../../specs/protocol.md)

> **Behavior reference only. Never copy assets.** MemoBot reuses Grok Bot's original static assets under a user-approved policy whose redistribution rights are unverified (see the header of [behavior.md](behavior.md)). This file is MemoBot's own interface text and contains no assets, but the same rule applies: Memoshi takes behavior, never Grok Bot or MemoBot assets ([D33](../../../plan/decisions.md#d33)).

## Provenance

| Field | Value |
|---|---|
| Source file | `~/Projects/MemoBot/spec/http.md`, 36,934 bytes, SHA-256 `3128f843ee416445480fcd6062d186de640ce87b7eed1daf7f0666f58168efdb`, last modified 2026-10-20 09:06 local time |
| What it is | MemoBot's own REST and server-sent-events API under `/api/v1`. The body opens: "This is our independently designed interface, not the reference's wire protocol." Grok Bot's real protocol is private and unknown |
| Evidence class | **Secondary source**: MemoBot's design, shaped by behavior its authors measured from Grok Bot desktop **0.71.2**. The installed app is now **0.72.0** (`/Applications/Grok Bot.app`, checked 2026-10-20) |
| Repo state | `~/Projects/MemoBot` is not a git repository and has no LICENSE file. The SHA-256 above pins the copied bytes |
| Imported | 2026-10-20: copied with `cp`, then this header was prepended. Nothing below the marker was edited |

Check the body against the source (prints `identical` while the source is unchanged):

```sh
sed '1,/^<!-- BEGIN VERBATIM COPY -->$/d' docs/research/prior/grok-bot-measured/http.md \
  | diff - ~/Projects/MemoBot/spec/http.md && echo identical
```

## Why this file was copied

Of MemoBot's two optional specs, this is the one that helps Memoshi. It states the behaviors in [behavior.md](behavior.md) as exact state transitions, invariants and error cases. Memoshi's transport is different: JSON-RPC 2.0 over a WebSocket on a Unix domain socket, with one multiplexed event stream ([D13](../../../plan/decisions.md#d13)). So take the rules, not the routes or status codes.

| Rule in the body | Body section | Memoshi doc it informs |
|---|---|---|
| Publish an event only after the durable state it describes exists. Sequence IDs increase monotonically but need not be consecutive. Replay from `Last-Event-ID`, or resynchronize when replay is lost | "Snapshot and events" | [`protocol.md`](../../../specs/protocol.md), [`events.md`](../../../specs/events.md) |
| A streaming delta carries `offsetUtf16`, the reply's length before the append. Receivers drop overlap they already have, append only unseen text, and fetch canonical state only on a real gap. A delayed snapshot never regresses a finished reply | same | [`protocol.md`](../../../specs/protocol.md) |
| In a room, bots get only the room's history, never their private transcript. Other participants appear to the model as untrusted user turns. Approvals stay with the owner of the executing computer and connections; room membership grants no authority over them | "Local recipients and shared rooms" | Groups in [05-bots-and-assistant.md](../../../plan/05-bots-and-assistant.md); [`policy.md`](../../../specs/policy.md) |
| A clarification moves from pending to answered in one atomic step that also creates exactly one run. A concurrent duplicate gets `409 CLARIFICATION_INFLIGHT`, a late one `409 CLARIFICATION_ANSWERED`. Answering grants no tool authority | "Sections and clarification answers" | Question Card in [`object-model.md`](../../../specs/object-model.md) |
| An approval takes at most one terminal decision. Denial or cancellation never executes the tool | "Automations, approvals and activity" | [`policy.md`](../../../specs/policy.md) |
| Disconnecting, deleting, disabling or re-keying a connection first cancels the unfinished runs and pending approvals that depend on it, keeping partial output, and only then closes the transport | "Configuration, skills, providers and connections" | Connectors in [08-security-and-privacy.md](../../../plan/08-security-and-privacy.md) |
| Installs accept only trusted descriptors: HTTPS GitHub archives pinned to a 40-hex commit, redirects rejected, size and entry-count limits, no traversal or links, no hooks or scripts executed. Reconfiguration is atomic and a failed install restores the previous package | same | Skills and Connectors in [08-security-and-privacy.md](../../../plan/08-security-and-privacy.md) |
| Mention and skill chips in a message are presentation, not authority. A chip extends scope for one turn only and is revalidated at execution and on retry | "Structured turn documents and reference authority" | [`policy.md`](../../../specs/policy.md), composer in [02-experience.md](../../../plan/02-experience.md) |
| Export and import remap every ID and strip provider and connection selections, secrets and approval grants. A bot imported from a template starts with Ask policy and no private integrations | "Automations, approvals and activity"; "Private template drafts and immutable publications" | `bot.md` in [`bot-definition.md`](../../../specs/bot-definition.md) ([D26](../../../plan/decisions.md#d26)) |

**Ignore for Memoshi:**

- Accounts, cookies, CSRF tokens and saved-device grants. Memoshi has one local user and authenticates the app with a per-launch token and a peer user-ID check ([D13](../../../plan/decisions.md#d13)).
- The public preview listener and template links. Sharing is v2 ([MASTER_PLAN §11](../../../plan/MASTER_PLAN.md#11-scope)).
- WebAuthn security keys, Native Email, and local feedback.

**Why `spec/portability.md` was not copied:** it is MemoBot's plan for its own future Rust and Swift ports. Its export and import rules are covered in more detail here; see the note in [behavior.md](behavior.md).

<!-- BEGIN VERBATIM COPY -->
# MemoBot protocol 1

This is our independently designed interface, not the reference's wire protocol. JSON uses camelCase, UUID IDs, UTC ISO-8601 timestamps, and `version: 1` on snapshots, exports and events. Entity records are specified in `src/shared/types.ts`. Unknown/missing records return 404; invalid requests 400; unsigned users 401; policy/spending denials 403; concurrent invalid transitions 409. Errors are `{error:{code,message}}`, never stacks/secrets. Deletions return `{ok:true}`. Creation returns its entity; updates return the updated entity. All paths below are under `/api/v1`.

## Bootstrap and identity

- `GET /bootstrap` -> `Bootstrap` (public); returns the per-process CSRF token only to same-origin browser access. No permissive CORS.
- `POST /session/register` `{displayName,email,password}` -> `{profile}` + HttpOnly SameSite=Strict session cookie. Unique email, salted password KDF, new isolated workspace.
- `POST /session/login` `{email,password}` -> `{profile}` + cookie.
- `POST /session/logout` -> `{ok:true}`; forget the current account on this device, revoke its remembered authority and tracked sessions, and clear the current session cookie. Other saved accounts remain saved.
- `PATCH /profile` `{displayName?,email?,currentPassword?,newPassword?}` -> Profile.
- `GET /accounts` -> `{accounts:{id,displayName,email}[]}` (authenticated). Only valid account grants bound to the private `memo_device` cookie are listed; this is not an enumeration of every account in the database. Successful sign-in and authenticated bootstrap remember the account; private authority stays encrypted server-side and out of portable exports.
- `POST /accounts/:id/activate` `{}` -> `{profile}` and a new session cookie. Require a valid saved-device grant; reject unknown/expired/revoked/policy-mismatched authority with `403 ACCOUNT_NOT_SAVED`. Revoke the previous active session, not the other account's saved grant. Unsaved accounts require real login/key authentication; knowing an ID is not authority.
- `DELETE /accounts/:id` -> `{ok:true}`; forget that account on this device, revoke its remembered authority and tracked sessions, and clear the cookie if it is active. Password/security-key policy changes revoke the affected account's remembered authorities.

Unsafe methods require `X-MemoBot-Token: <bootstrap.csrfToken>` and an allowed same-origin Origin when present. Sessions scope every resource. Same-origin static client is served by this backend. Development origins, if any, must be explicitly configured, not wildcard.

## Snapshot and events

- `GET /snapshot` -> Snapshot. Bots contain sidebar previews; does not embed all messages/attachments. Provider/connection secrets are redacted into `hasApiKey/hasSecret`.
- `GET /events` -> SSE. `id: <seq>`, `event: message`, `data: EventEnvelope` per event. Sequence IDs are monotonically increasing, not necessarily consecutive: the durable event log is shared across isolated accounts. Support Last-Event-ID or resynchronize on replay loss. Clean up disconnected clients; heartbeat is allowed.
- Event types: `state.changed` `{entity,id?}` requests snapshot refresh; `message.created` Message; `message.delta` `MessageDelta` `{id,botId,conversationId,offsetUtf16,delta}`; `message.updated` Message; `run.updated` Run; `approval.created` Approval; `approval.updated` Approval. Publish only after durable corresponding state exists. Events are scoped to the signed-in account. `offsetUtf16` is the assistant content's UTF-16 code-unit length before this append; receivers ignore covered overlap, append only unseen text, and fetch canonical state on a genuine gap/missing message—not on every token. Terminal replies cannot be regressed by delayed streaming snapshots. Replay cache may be invalidated during protocol cutover without deleting durable conversations or activity.

Snapshot and authenticated bootstrap include owned `sections:BotSection[]` and `clarifications:Clarification[]`; anonymous bootstrap returns empty arrays. Events `clarification.created` and `clarification.updated` carry complete canonical Clarification records after durable commit.

## Local recipients and shared rooms

- `GET /recipients?query=` -> `{recipients:ChatRecipient[]}` (authenticated). Search owned, nonarchived ordinary bots and other people registered on this independent server by display name/email. `ChatRecipient` is `{id,kind:'bot'|'person',name,avatar?}`; responses never expose email, device sign-in grants, credentials, bot instructions or provider configuration. Recipient avatars expose only shape/color, not private image attachment IDs.
- `POST /groups` `{recipients:[{id,kind}],name?}` -> `{bot:Bot}` (201). Require 1–50 unique recipient references, existing local people and bots owned by the creator; the signed-in person is implicit. `Bot.group` is `{ownerId,members:ChatRecipient[]}`. Names are trimmed/nonempty and limited to 255 characters, matching ordinary bot creation/rename; unrelated profile/provider/section limits remain unchanged. Rooms are real durable aggregates, not copied private bots or per-member histories.
- `GET /groups/:id` -> `{bot:Bot}`; `GET /groups/:id/messages?conversationId=&before=&limit=` -> `MessagesPage`. Only people explicitly in the room have access. Unknown rooms and nonmembership both return 404. Each room has one canonical conversation whose ID equals the room ID; passing another conversation ID is 404. Pagination matches ordinary message semantics.
- `POST /groups/:id/messages` `{content,document?,attachmentIds?,conversationId?,replyToId?}` -> `GroupMessageSubmission` `{userMessage:Message,submissions:RunSubmission[]}` (201). The server derives `Message.sender:ChatRecipient` from the current authenticated person, ignoring request-supplied identity. Human-only rooms persist and stream the human message with `runId:null` and an empty submissions array: no invented assistant or run. Validate every configured bot participant's real provider/model before accepting the turn. Missing/unavailable configuration is a real error, not simulated delivery.
- Bot participants execute the creator's actual selected provider/model, instructions, skills, knowledge, tools, spending policy and approval settings through the ordinary runtime. Only room history is supplied, never the private bot transcript. Each output has `sender` equal to its originating bot; `Run.botId` and `Message.botId` remain the room ID. Other room participants are identified as untrusted user turns to the model rather than impersonating the executing assistant. Run input retains the selected private bot ID server-side.
- Snapshots include every room the current person belongs to and its runs/clarifications, without exposing another account's providers, settings, integrations, usage or private bots. Persist each message/run once under the room owner. Migration 6 adds `group_rooms`, explicit `group_members`, and explicit `group_files`; ordinary account-scoped `Store.require` and existing export/import semantics are unchanged. Rooms cannot be imported as membership grants, and private bot export does not include shared room history.
- Existing `/events` streams and durable replay logs fan out room message/delta/update, run and clarification events only to room members. Room creation/preview changes emit member-only `state.changed`. No global broadcast channel or private external directory/service is involved.
- Members may cancel/retry their room's real runs through existing `/runs/:id/cancel|retry`; retry reuses the canonical original human turn and configured bot participant without duplicating the human message. Nonmembers cannot control room runs. Approvals remain owner-only: room membership does not grant authority over someone else's computer, integration secrets or tool execution. Only the execution owner receives approval records/events and may decide them. Members may answer room clarifications; the answer is attributed to the authenticated member.
- An attachment is shared only by including an owned file (or a file already shared in that same room) in an accepted room message. `GET /attachments/:id` permits its owner or a member of a room containing that explicit file grant; knowing a file/room ID grants nothing. Sharing does not expose sibling uploads, private avatar files or account attachment directories. Files stay in their uploading account's bounded, symlink-safe storage; no duplicate bytes or private history copies are created.


## Bots, conversations and files

- `POST /bots` mutable bot fields with required `name` -> Bot. Fields include `avatar,description,instructions,providerId,model,pinned,pinOrder,archived,sectionId,labels,skillIds,connectionIds,approvalMode,unread,voice`; omitted fields receive defaults.
- `PATCH /bots/:id` partial mutable Bot fields -> Bot. Section/provider/skill/connection references must belong to the account. `sectionId:null` ungroups; `archived` implements hide/restore; unread and pin order persist independently.
- `DELETE /bots/:id` -> `{ok:true}`; cancel its runs and pending approvals, remove its owned conversations/library/schedules.
- `GET /bots/:id/conversations` -> `{conversations:Conversation[]}`.
- `POST /bots/:id/conversations` `{title?}` -> Conversation.
- `GET /bots/:id/messages?conversationId=&before=&limit=` -> `{messages:Message[],conversationId,nextCursor:string|null}`. Chronological returned order; last page by default, stable id/time cursor; default conversation created if absent.
- `POST /bots/:id/messages` `{content,document?,attachmentIds?,conversationId?,replyToId?}` -> `{run:Run,userMessage:Message,assistantMessage:Message}` (201). Return promptly; run streams asynchronously. Provider/model availability is validated before creating a run; exact failure is visible, never invented content.
- `POST /runs/:id/cancel` -> Run. Cancel queued/running/pending-approval work, preserve partial text; cancellation must abort actual transport/process work.
- `POST /runs/:id/retry` -> `{run:Run}`. Re-execute the original owned prompt without duplicating unrelated messages.
- `POST /bots/:id/clear` `{conversationId?}` -> `{ok:true}`. Cancel affected work first.
- `GET /search?q=&limit=` -> `{results:SearchResult[]}`; own workspace only.
- `POST /attachments` JSON `{name,mimeType,data:<base64>}` -> Attachment. Max 25 MiB decoded, UUID storage filename; reject unsafe names/path traversal. Extract supported document text.
- `GET /attachments/:id` -> owned bytes with safe MIME/content disposition and no content sniffing.
- `GET /bots/:id/documents` -> `{documents:KnowledgeDocument[]}`.
- `POST /bots/:id/documents` `{name,content?,attachmentId?}` -> KnowledgeDocument.
- `PATCH /documents/:id` `{name?,content?}` -> KnowledgeDocument.
- `DELETE /documents/:id` -> `{ok:true}`.

### Replies, reactions and read cursors

- `Message` optionally carries `document:ChatDocument`, `replyToId:UUID` and `reactions:[{emoji:string,actors:[{id:UUID,name:string}]}]`. Reactions contain nonempty unique actor lists and unique normalized emoji buckets. Missing optional fields remain compatible with older records.
- `GET /bots/:id/messages/:messageId?conversationId=` and `GET /groups/:id/messages/:messageId?conversationId=` -> the canonical `Message` (200), not a wrapper or a new page. The optional conversation filter must match. Private lookups require bot/message/conversation ownership and reject group records through the private endpoint; room lookups require current explicit membership and the room's canonical conversation. Missing, cross-bot, cross-conversation and unauthorized targets return `404 NOT_FOUND`. This lookup does not advance the read cursor.
- `POST /bots/:id/messages/:messageId/reactions` and `POST /groups/:id/messages/:messageId/reactions` accept exactly `{emoji:string,active:boolean}` -> canonical `Message` (200). Require session, same-origin/CSRF mutation protections and the same target isolation as lookup; re-resolve ownership/membership after body I/O. Actor IDs/names are not accepted: activation uses the signed-in profile's ID/display name, removal affects only that ID. No room-owner privilege is required for a member's own reaction.
- Emoji input is 1–32 UTF-16 code units, normalized for redundant/missing presentation selectors, then restricted to one RGI emoji or supported standalone skin-tone/hair picker component. Malformed bodies/unsupported emoji return `400 INVALID_REQUEST`. Repeating the desired active state is idempotent; remove empty buckets. Changed state is durably stored before member/account-scoped `message.updated`; unchanged requests emit no update. Only `status:'streaming'` is blocked with `409 MESSAGE_STREAMING`; failed/cancelled messages can be reacted to.
- Reply submission and clarification answers accept an optional UUID `replyToId`. Resolve it from canonical owned/room history, never a supplied quotation: require the same bot/conversation and `status:'complete'`. Missing/wrong-conversation targets return `404 NOT_FOUND`; any incomplete target returns `409 REPLY_TARGET_INCOMPLETE`. Revalidate during durable submission and execution/retry. Provider context resolves a completed prior message and labels its content/sender/attachment text as untrusted conversation data, not system instructions; a reference is not additional participant/tool authority.
- `Bot.lastReadMessageId?:UUID|null` is the viewer's persisted read cursor, not a writable bot field. For rooms it is projected from that member's private preferences, never shared with other members. Listing a message page clears that viewer's `unread` and records the latest message in the entire selected conversation, even when requesting an older page. Patching `unread:false` records the latest message; `unread:true` records the penultimate message (or null), making the last message unread. Private bot patches use the default conversation; rooms use their sole conversation. Accepted human sends advance the sender's cursor; clear resets a removed cursor.
- The client freezes the entry unread boundary separately from subsequent persisted cursor updates. Reading/pagination/refresh must not slide an already displayed new-message divider; explicit read-boundary revisions capture a new boundary. A missing older cursor is resolved through loaded history rather than invented as a different message. The optional field preserves legacy-record handling.

### Structured turn documents and reference authority

`ChatDocument` is a validated `{type:'doc',content:ChatNode[]}` tree, not arbitrary HTML. Supported blocks/marks include paragraphs, headings, quotes, lists/tasks, code, horizontal rules, bold/italic/strike/underline/code and safe absolute HTTP(S)/mailto links. Bound depth to 32, nodes to 20,000 and visible text to 2,000,000 UTF-16 code units. Canonical `chatDocumentText(document)` must equal submitted `content` (or clarification answer `text`); mismatch/malformed structure returns `400 INVALID_REQUEST`. Plain text remains accepted without a document.

Inline mentions are `{type:'mention',attrs:{id,label,kind:'bot'|'person'|'everyone'}}`; skill/app chips are `{type:'skillReference',attrs:{id,label,kind:'skill'|'connection'}}`. Labels are presentation, not authority. Private mentions resolve owned non-room bots or existing local people; room mentions must be current room participants. Everyone requires a group with at least two members and ID `everyone` (`400 INVALID_REFERENCE`); absent participants give `404 REFERENCE_NOT_FOUND` (ordinary owned-record lookup may give `404 NOT_FOUND`). Mentioning does not itself dispatch a private bot or grant access.

Skill/app references resolve in the execution owner's account and add scope only for this turn, without changing saved bot selections. A nonowner room author may reference only IDs already selected by every responding bot (`403 REFERENCE_NOT_SHARED`); missing records return 404. App references require enabled, connected, non-native MCP connections (`409 REFERENCE_UNAVAILABLE`). Validate at submission/commit and again at execution/retry; historical chips do not grant future authority.


### Avatar photos

- `avatar` is `{shape,color,imageAttachmentId?:UUID|null}`. Bot create/patch validates an owned referenced PNG; `null` restores character rendering. Attachment IDs are private account references, never public template references.
- `POST /avatar-images/generate` `{description,providerId?}` -> Attachment (201). Description is trimmed, 1–4,000 characters. The explicit provider or account default must be enabled, OpenAI-compatible, have an explicitly configured `imageModel` and an API key. Missing default gives `400 IMAGE_PROVIDER_REQUIRED`; actual provider failures remain errors, not fabricated images.
- Generation calls the configured public HTTPS `images/generations` endpoint. Resolve and pin a public IP for TLS; reject nonpublic addresses and redirects. Accept one base64 PNG or a same-origin HTTPS PNG URL; never send the bearer key on the image download. A 120-second bound and response byte limits apply.
- Generated images are validated and stored as private `avatar.png` attachments; generation does not itself patch a bot. Upload/paste/crop use the existing attachment API followed by explicit bot PATCH. The UI's crop is a 256×256 PNG, with zoom/reposition preview; selecting a candidate is not yet a saved bot mutation.
- Referenced avatar validation accepts only bounded, nonanimated PNG: at most 8 MiB and 2048×2048 pixels, checked chunk CRC/structure and bounded decompression, then pixel decode/re-encode with ancillary metadata stripped. Invalid data returns `400 INVALID_AVATAR_IMAGE`; SVG/animated/malformed images cannot cross this avatar seam.
- Portable export includes PNG attachment bytes and import stages/validates them before the atomic graph commit, remaps `imageAttachmentId`, and removes staged files on failure. Missing image payloads are `400 INVALID_BUNDLE`. No public attachment grant is created.

## Sections and clarification answers

- `POST /sections` `{name}` -> BotSection (201); `PATCH /sections/:id` `{name}` -> BotSection. Names are trimmed/nonempty, at most 240 characters; record is `{id,name,createdAt,updatedAt}`.
- `DELETE /sections/:id` -> `{ok:true}`. Atomically ungroups its bots and deletes only the section. Lists come from snapshot/bootstrap, not a separate GET route.
- `GET /clarifications` -> `{clarifications:Clarification[]}` scoped to the account.
- `POST /clarifications/:id/answer` `{optionIds:string[],text:string,document?:ChatDocument,replyToId?:UUID,attachmentIds?:UUID[]}` -> `RunSubmission` `{run,userMessage,assistantMessage}` (201). Require choice, nonblank text or attachment; maximum 26 unique choice IDs and 20 unique owned attachments. The optional document must describe answer `text`; the server prefixes the question/selected options in the persisted human turn. Reply authority follows ordinary message submission. Invalid options/multiple selections for single-choice yield `400 INVALID_ANSWER`; malformed submission yields `400 INVALID_REQUEST`.
- Clarification is `{id,botId,conversationId,messageId,question,options:[{id,label,description?}],multiple,state:'pending'|'answered',answer:{optionIds,text}|null,createdAt,answeredAt?}`. Options number 2–26 with unique IDs. Pending has null answer/no answeredAt; answered has both. Source must be the owned assistant message in the same conversation; human answer message carries `clarificationId`.
- Concurrent duplicate answer returns `409 CLARIFICATION_INFLIGHT`; committed answer returns `409 CLARIFICATION_ANSWERED`. Provider preparation failure leaves pending state. Revalidate source after asynchronous preparation, then atomically commit answer/messages/run before events. Clarification is information, not tool authorization. Historical inference uses canonical answer state without modifying immutable tool results. Retry likewise revalidates its source after asynchronous preparation so clear/delete cannot resurrect removed prompts.

## Configuration, skills, providers and connections

- `PATCH /settings` partial Settings -> Settings. Persist; workspace must be an absolute real directory. CSRF/session checks required.
- `GET /providers/:id/models` -> `{models:ModelInfo[]}` using real endpoint.
- `POST /providers` Provider fields (except id/hasApiKey) + optional `apiKey` -> Provider.
- `PATCH /providers/:id` partial same, optional `apiKey` (empty clears) -> Provider.
- `DELETE /providers/:id` -> `{ok:true}`; clear dangling selections explicitly.
- `POST /providers/:id/test` -> `{ok:true,models:ModelInfo[]}` only on a successful real probe; report real failure otherwise.
- `POST /skills` `{name,description?,content}` -> Skill.
- `PATCH /skills/:id` partial mutable Skill -> Skill.
- `DELETE /skills/:id` -> `{ok:true}`; remove from bot selections.
- `GET /catalog?q=&category=` -> `{entries:CatalogEntry[]}` from the staged public registry plus independently implemented adapters, excluding private/account catalog records. Presentation metadata and publisher artwork do not establish installation, authorization or connected state.
- `GET /catalog/:id/configuration` -> `{values,configuredKeys}`; only nonsecret declared values are returned. `configuredKeys` can indicate saved secrets without returning their contents.
- `POST /catalog/:id/install` `{variables?:{[key:string]:string}}` -> `{plugin,connections,skills,prerequisites}` (201). `plugin` is `{id,catalogId,revision:string|null,connectionIds,skillIds,configuredKeys,installedAt}` and is included in `Snapshot.plugins`. Only trusted server-side catalog descriptors are accepted; no request-supplied archive URL, revision, commands or ambient credentials.
- Archive descriptors pin an HTTPS GitHub repository to a 40-hex commit. Download the corresponding codeload tar.gz with redirects rejected; validate the pinned root and reject traversal, duplicate paths, links/devices and excessive sizes (64 MiB archive, 256 MiB expanded, 16 MiB/file, 50,000 entries). Retain declared manifests, real skills/supporting source and supported declarative MCP configuration with an owned receipt mapping source paths to generated record IDs. Installation never executes setup hooks, scripts or declared executables.
  Manifest-relative directory references may use a leading `./` and a single trailing `/` (for example `./skills/`); traversal, empty segments, and absolute paths remain invalid.
- Setup accepts only declared fields and explicit user values; defaults do not authorize use of publisher accounts. Secret values are encrypted and are not returned by configuration GET. Missing/unsupported/private-service connector configuration is surfaced as prerequisites, not a fabricated connection. Native Email has `installable:false`, reports unavailable, and has no mailbox address/service.
- Reinstall without `variables` returns the owned installation/receipt; reconfiguration preserves source-mapped IDs and atomically replaces owned package records/source. It does not authorize/probe connectors. `404 CATALOG_NOT_FOUND`, `409 CATALOG_BUSY`, `409 CATALOG_REVISION`, `409 CATALOG_STORAGE`, `400 CATALOG_VARIABLE`, `400 CATALOG_PACKAGE`, `400 CATALOG_PREREQUISITE`, `413 CATALOG_SIZE`, `502 CATALOG_DOWNLOAD`, `499 CATALOG_CANCELLED` and `400 CATALOG_INSTALL` distinguish real failure paths. Failed/cancelled installation cleans staging and restores the previous package rather than reporting success.
- `DELETE /plugins/:id` -> `{ok:true}`; cancel owned connection runs/disconnect transports, remove owned source/receipt, skills/connections and their secrets, and clear bot selections. It does not uninstall external executables or revoke a third party's account.
- `POST /connections` mutable Connection fields + optional `secret` -> Connection. Native presets use `kind:native`, `url` is a native capability key such as `computer`, `messages`, `files`.
- `PATCH /connections/:id` partial mutable fields + optional `secret` -> Connection.
- `DELETE /connections/:id` -> `{ok:true}`; disconnect live client and remove bot selections and encrypted credentials.
- `POST /connections/:id/test` -> Connection after actual tool discovery/capability probe. On authorization-required return real status, not connected.
- `POST /connections/:id/authorize` -> `{authorizationUrl:string}`; UI opens public authorization page. This starts real OAuth when server supports it, otherwise a concrete error.
- `GET /connections/oauth/callback?code=&state=` public but state/PKCE protected; completes pending OAuth and redirects to `/#connections` without exposing codes/tokens in UI/logs.
- `POST /connections/:id/disconnect` -> Connection.

Connection disconnect/delete and configuration replacement, disablement or secret change cancel affected nonterminal runs before disconnecting the transport. Affected scope includes saved bot selections, group participant bot selections and the original turn's explicit connection chip. An installed-plugin connection is global run scope, so disconnecting it cancels all that owner's nonterminal runs. Cancellation preserves partial output, aborts active work and cancels pending approvals; it is not merely removal from a picker. Plugin uninstall follows the same cancellation/disconnection seam.

## Automations, approvals and activity

- `POST /automations` `{botId,name,prompt,schedule,enabled?}` -> Automation.
- `PATCH /automations/:id` partial -> Automation; recompute next trigger when schedule/enabled changes.
- `DELETE /automations/:id` -> `{ok:true}`.
- `POST /automations/:id/run` -> `{run:Run}`. Real prompt dispatched using target bot.
- `POST /approvals/:id` `{decision:'allow'|'deny'}` -> Approval. At most one terminal decision; must belong to current account; denial/cancellation never executes tools.
- `GET /activity?limit=` -> `{activity:Activity[]}`.
- `GET /usage` -> UsageSummary from actual run counters and configured prices. Cost null when unknown; spending cap applies to known accumulated costs.
- `GET /export?botId=` -> ExportBundle `{version:1,exportedAt,bots,sections,conversations,messages,clarifications,skills,documents,automations,settings?,attachments?:[{attachment,data:<base64>}]}`. Single-bot exports include referenced sections/skills and omit settings. Provider/connection selections and tool connection IDs are stripped; full-export settings clear workspace/provider references and security-key enablement. Record graph is captured before asynchronous attachment reads to remain consistent across concurrent clear.
- `POST /import` ExportBundle -> `{bots:Bot[],imported:number}`. Validate version, unique IDs and complete graph; remap sections/bots/conversations/messages/clarifications/skills/documents/automations/attachments and their references. Require unique question-source messages and exactly one linked human answer for answered clarifications, none for pending. Import atomically without overwriting; no arbitrary file paths/secrets/approval grants. Clear provider/connections and imported unread flags; clean staged files on failure.

Portable messages preserve structured documents, replies and normalized reactions. Import validates document/text equality, unique normalized emoji buckets/actor IDs, and every reply against a completed target appearing earlier in the bundle's message array in the same bot/conversation (`400 INVALID_BUNDLE` for reply graph failures; schema failures are `400 INVALID_REQUEST`). Remap reply IDs; remap each distinct historical reaction actor to a fresh UUID consistently across the import, retaining its display name. These historical actors are not current accounts, membership or authority to remove another actor's reaction. Preserve a read cursor only if its referenced bundled message belongs to that bot, otherwise set null; imported unread is false. Included bot/skill chips remap to the new entities; app/person/excluded bot or skill references become stable-per-import `unavailable:` IDs, preserving visible history without binding live local authority. Everyone remains a marker, not an imported membership grant. Retry reuses the original human message/document/reply and validates current ownership, participant, configuration and reference availability; imported history never restores credentials or connection grants.

## Local feedback

- `POST /feedback` `{content,conversationId?,requestResponse:boolean}` -> `{id,receivedAt}` (201). Trimmed content must contain 1–20,000 characters; optional conversation ID must belong to the signed-in account.
- The owned SQLite feedback queue stores the report, optional owned conversation ID, response preference and profile email only when a response was requested. The receipt proves local acceptance only: no vendor submission, email delivery or support response is implied. There is no feedback delivery/status/list route.

## Native and voice

- `GET /native/status` -> NativeStatus from new OS helper if available; precise unavailable status otherwise.
- `POST /native/action` `{action,input}` -> `{result:unknown}`. Explicit user settings/capability actions only; never an unauthenticated raw shell. Model-driven actions go through run approvals.
- `POST /voice/transcribe` `{data:<base64>,mimeType,providerId?,language?}` -> `{text:string}` through real configured public transcription or native adapter. Language is optional empty/valid BCP-47 tag, at most 80 characters; clients pass bot voice language. Explicit provider overrides `settings.speechProviderId`; disabled provider yields `400 PROVIDER_DISABLED`. Disconnect/abort cancels transcription.

`bot.voice` is `{voiceURI:string,language:string,rate:number}`, default `{voiceURI:'',language:'',rate:1}`. Empty URI/language means system-selected voice/automatic language. URI maximum is 500 characters. Supported keys: `en,ar-EG,ar-SA,ar-AE,bn,ca,zh-CN,da,nl,fi,fr,de,hi,hu,id,it,ja,ko,pl,pt-BR,pt-PT,ru,es-MX,es-ES,sv,th,tr,vi`. Trim/case-fold language, prefer exact canonical key, otherwise accept a family match only if unique; unsupported/ambiguous input becomes automatic. Rates normalize to nearest `0.5,0.75,1,1.25,1.5,2` (ties lower); numeric strings are parsed and nonfinite numeric input defaults to 1. Create/patch/import normalize preferences. Call lifecycle/audio ownership are client-domain state, not an invented HTTP call endpoint.

## Server module contract

`src/server/app.ts` exports `createApp(options)` returning `Promise<MemoApplication>`: `{url:string,previewUrl?:string,close():Promise<void>}`. Options: `{dataDir:string,host?:string,port?:number,staticDir?:string,nativeHelperPath?:string,desktop?:boolean,onSettingsChange?:(settings:Settings)=>void}`. Bind port 0 in tests, default 3157 in desktop/CLI. Publishing environment variables configure the separate preview listener, not a public binding for the private API. Runtime creation is defined in `src/shared/runtime.ts`. Node CLI and Electron import the same backend; no proprietary runtime imports.

## Owned security keys

- `GET /security-keys` -> `{keys:{id,name,createdAt}[]}` (authenticated).
- `POST /security-keys/registration/options` `{}` -> WebAuthn `PublicKeyCredentialCreationOptionsJSON` (authenticated).
- `POST /security-keys/registration/verify` `{response:RegistrationResponseJSON,name?:string}` -> `{verified:true,key:{id,name,createdAt}}`.
- `POST /security-keys/authentication/options` `{email}` -> `PublicKeyCredentialRequestOptionsJSON` (public, CSRF protected, challenge cookie).
- `POST /security-keys/authentication/verify` `{response:AuthenticationResponseJSON}` -> `{profile}` and a new owned session (public, CSRF/challenge/origin/RP verified).
- `DELETE /security-keys/:id` -> `{ok:true}` (authenticated; do not leave an enabled key-only account locked out).
- Enabling `settings.securityKeysEnabled` requires an enrolled key. With key-only login enabled, password login returns `403 SECURITY_KEY_REQUIRED`; an owned key assertion is required. Challenges are expiring and single-use, credential IDs are globally unique within this relying party, ownership and counters are verified, and private key material never enters the backend.

## Private template drafts and immutable publications

- `POST /bots/:id/template-drafts` `{}` -> `TemplateDraft` (201); create a private durable snapshot from an owned bot, including a sanitized PNG if present. `memobot_create_template` likewise returns `{type:'template-draft',draftId}` without publishing or granting consequential tool approval.
- `GET /template-drafts/:id` -> `{id,botId,bot,revision,createdAt,updatedAt,publication:null|{link:TemplateLink,revision}}`. Require both draft and source bot ownership. New drafts start at revision 1; direct revocation of the published link makes `publication` null on GET.
- `PATCH /template-drafts/:id` `{revision,bot:{name,avatar:{shape,color},description,instructions},removeImage?}` -> TemplateDraft. Name is trimmed/nonempty, at most 255 characters; edited instructions are trimmed/nonempty, at most 4,000 characters; description at most 4,000. Unknown fields and incoming image data are rejected. Preserve the draft's existing PNG unless `removeImage:true`; increment revision and update the private draft only, never the live bot.
- `POST /template-drafts/:id/publish` `{revision}` -> TemplateDraft. Require the expected positive revision and nonblank body (`400 TEMPLATE_BODY_REQUIRED`). Publish only the allowlisted snapshot; redact known account secrets/workspace paths from text. Repeating publish at the same published revision returns the existing link. Editing alone leaves the previous immutable publication unchanged; explicit republish atomically creates a replacement and revokes its predecessor.
- `POST /template-drafts/:id/revoke` `{revision}` -> TemplateDraft with null publication, preserving the private draft. Edit/publish/revoke with a stale revision return `409 TEMPLATE_DRAFT_CHANGED`. `DELETE /template-drafts/:id` -> `{ok:true}`; delete the owned draft and revoke any associated publication (no revision body).
- Drafts and publication tokens are private authority, not portable exports. Renderer cards refresh ownership/publication before copying links; errors are visible and stale edits cannot silently overwrite another window.

### Direct configuration-only template links

- `POST /bots/:id/template-links` `{}` -> `TemplateLink` creates an unguessable owned template link after explicit user confirmation.
- `GET /bots/:id/template-links` -> `{links:TemplateLink[]}`; `DELETE /template-links/:id` revokes an owned link and returns `{ok:true}`.
- Public `GET /templates/:token` -> `BotTemplate`: `{version:1,bot:{name,avatar:{shape,color},description,instructions,avatarImageDataUrl?:string},createdAt}`. Optional image is a sanitized bounded `data:image/png;base64,…`, not a private attachment ID. Invalid/revoked tokens return 404. No transcripts, other files, connection/skill IDs, provider credentials, account data or approval grants are included.
- Without publishing configuration, URLs use the private server's origin and `/#template/<token>` and are local-only. With `MEMOBOT_PUBLIC_URL` configured, a **separate loopback-only public preview listener** starts; `MEMOBOT_PREVIEW_PORT` selects its port (default 0, an ephemeral port). `MemoApplication.previewUrl` and CLI logs report that local listener address. Reverse-proxy only that preview listener behind the user's own TLS/domain; never publish the private API port.
- The preview listener serves static client assets, anonymous `GET /bootstrap` (`authenticated:false`, `needsSetup:false`, empty CSRF, `capabilities.publicPreviewOnly:true`, no desktop/native/speech/notification capabilities), and config-only `GET /templates/:token`. Every other API method/path returns `403 PUBLIC_PREVIEW_ONLY`, independently of Host, Origin, cookies, or CSRF. It never creates a session.
- Public preview's **Create a copy** opens `memobot://template/<token>?origin=<sourceOrigin>`. The receiver's own desktop loads local `/#template/<token>?origin=<sourceOrigin>`; its private, CSRF-protected `POST /templates/preview` `{origin,token}` retrieves and validates the published configuration without cookies/authorization/redirects. Transport, redirect and malformed-source failures are `502 TEMPLATE_FETCH_FAILED`; invalid references are `400 INVALID_REQUEST`; revoked links remain `404 NOT_FOUND`.
- The receiving local preview preserves intent through its own authentication, then `POST /templates/import` `{origin,token}` -> Bot (201) fetches/revalidates the snapshot, sanitizes/stores its PNG as a new owned attachment and creates the bot/conversation with default ask policy and no private integrations. It never transplants the source attachment ID. Capability tokens are not logged or exported. All private APIs bind only localhost/127.0.0.1/::1; the primary listener does not trust the configured public Host/Origin.
