# Events

**Status:** Draft 4 · implementation scope updated 2026-11-03; distinguishes bounded local emitters from the full accepted event catalog · updated 2026-11-13 for [D106](../plan/decisions.md#d106)–[D122](../plan/decisions.md#d122): staged event families for views and Apps, Goals, voice, mail, Cloud computers, team mode and streamed cards (§5.20–§5.26), and Groups, Bot computers, external agents and connector events restaged; no existing type changed · updated 2026-11-14 for [D134](../plan/decisions.md#d134): Pi_Swift pin `slice-2` ([§8](#8-pi-projection) notes) · updated 2026-11-18 for the review fixes (`754cca2..8b9b170`; covered by [`canonical-ci-15`](../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-15/README.md) on `a2ac274`, see [HANDOFF, deep review](../HANDOFF.md#deep-review-2026-11-18)): schema 15, `task.cancel_requested` from `chats.abort`, `tool.interrupted`'s current emitters, `card.updated`'s fields and the not-dispatched settlement ([§8](#8-pi-projection))
**Owns:** The event envelope, the full event catalog by domain, event classes (audited, durable, UI-only), ordering, resync, Pi projection, retention and compatibility rules.
**Depends on:** [object-model.md](object-model.md), [protocol.md](protocol.md), [policy.md](policy.md), [04-architecture.md](../plan/04-architecture.md), [08-security-and-privacy.md](../plan/08-security-and-privacy.md), [decisions D7, D9, D13, D14, D46–D53 and D68–D84](../plan/decisions.md), [D87](../plan/decisions.md#d87), [D88](../plan/decisions.md#d88), [D108](../plan/decisions.md#d108)–[D122](../plan/decisions.md#d122), the [scope amendment of 2026-11-13](../plan/AMENDMENT_2026-11-13.md), [cards.md](cards.md)

Every device keeps its own append-only event log in its `memoshi.sqlite` ([D49](../plan/decisions.md#d49)). "Everything that matters writes an event in the same transaction" ([MASTER_PLAN §5 rule 6](../plan/MASTER_PLAN.md#rules)). The protocol carries these events to clients as one multiplexed stream with replay ([D13](../plan/decisions.md#d13)); the transport, handshake, RPC methods and device layer are in [protocol.md](protocol.md). This spec owns *what* the events are.

Adapted from Draft 3 `specs/events.md`, which defined 13 SSE event types with a per-session sequence. Draft 4 keeps its envelope fields (`seq`, `ts`, `payload`), its replay rules (gapless sequence, dedupe by sequence, write before acknowledge) and its fixture discipline, and fixes its gaps: one global stream instead of per-session streams, a durable/UI-only split so transcripts are not stored twice, an audit class, and a coverage test so no type is defined but never emitted (`taskgraph.snapshot` was). The full mapping is in [§12](#12-mapping-from-draft-3).

**Updated 2026-11-13 for [D106](../plan/decisions.md#d106)–[D122](../plan/decisions.md#d122).** This revision adds staged contracts and changes no existing type, field or class. New: views, selection carry, App scope and plugin developer mode (§5.20); Goals (§5.21); voice (§5.22); mail tidying (§5.23); team mode and the landing gate (§5.24); streamed cards (§5.25); Cloud computer and live-view rows (§5.13); one bot row (§5.2); and a Provider setting row (§5.14). Restaged: Group types to Phase 2 and bot-to-bot messages to Phase 1 ([D109](../plan/decisions.md#d109)); the VM types to the end of Phase 2 and takeover from iPhone and iPad to Phase 3 ([D113](../plan/decisions.md#d113)); `external_agent` to Phase 2 ([D110](../plan/decisions.md#d110)); connector events to Phase 2 on the Mac ([D112](../plan/decisions.md#d112)); and the `mini_app.*` types to Phase 1, with page Apps ([D114](../plan/decisions.md#d114)). §5.26 lists the added types by phase. Each is the accepted target for its phase: none has a Swift payload, a fixture or an emitter yet, and these additions change nothing in Phase 0's registry, wire or fixtures; what changed there on 2026-11-13 came from separate code fixes ([protocol.md §14](protocol.md#14-schema-codegen-and-fixtures)). Phases and the gates M1–M3 are those of [D117](../plan/decisions.md#d117) and [D122](../plan/decisions.md#d122); the scope by phase is in the [amendment of 2026-11-13](../plan/AMENDMENT_2026-11-13.md).

**Current implementation boundary:** `MemoshiStore` is at SQLite schema **15**. Schema 11 added local Session lifecycle, schema 12 gateway audit summaries, schema 13 the event log's identity ([D131](../plan/decisions.md#d131)), which adds no event type, schema 14 the Resume card's `resume_steps` ([D138](../plan/decisions.md#d138)), and schema 15 the S4 sandbox attribution tables, which add no event type. The emitters added with schemas 11 and 12 write only types already in this catalog (`session.deleted`, `session.restored`, `session.purged` and `trash.emptied`; `egress.allowed`, `egress.blocked` and `secret.used`); those added with schema 14 write `tool.interrupted`, `tool.interruption_resolved` and `card.updated`, and `card.created` and `card.resolved` for the `resume` card ([protocol.md](protocol.md#current-step-settlement)). It commits records plus numbered durable/audited events atomically, publishes only committed changes and captures replay/live observation together. Schemas 4/5 add bounded policy/approvals and immutable call/outcome receipts; schema 6 adds [folder grants and dependent approvals](../HANDOFF.md#source-grant-development-proof), with real `grant.granted/revoked/expired` emitters. [Native folder management](../HANDOFF.md#folder-management-development-proof) applies folder snapshots before acknowledgment and uses existing mutation receipts. The [runtime copy/export integration](../HANDOFF.md#runtime-working-copy-development-proof) adds no event kind: real Pi policy/approval/completion facts accompany actual source effects, including `tool_failed` and an explicit model-visible unknown outcome after partial export. The [development profile](protocol.md#current-text-chat-profile) projects Pi message/task metadata, focused UTF-16 deltas and committed outcomes without copying transcript/output text into events. HMAC/peer anchors and full engine/host/device services remain unimplemented or unqualified. An `app` hello is not itself a host capability channel. The remaining catalog is the accepted target; [§11](#11-contract-fixtures-and-tests) separates fixtures from emitters.

**Bot/Session lifecycle subset (2026-11-03):** the current store retains schema 9's real bot/conversation lifecycle. Bot/Chat creation commits audited `bot.created {name, role, createdBy, chatId}` and durable `chat.created {botId}` with the records in one transaction, including fresh Assistant bootstrap. Actual profile changes commit audited `bot.updated {changed, revision}`; persona/job bodies and model-output text never enter that payload. Session creation commits durable `session.created {leadBotId, origin}` at `cseq: 1`. Replays, no-ops and refused mutations add no duplicate facts. Generic Store commits cannot fabricate these lifecycle events. The Mac directory refreshes real bot/conversation snapshots before acknowledging them. Migrated preexisting bots get no invented retrospective creation events. These development payloads do **not** claim the full catalog's avatar, template, Computer, Browser, project or revision-history behavior.

**Real child-task subset (schema 10):** trusted host composition alone may install foreground/persistent-background Pi subagents; normal app/helper composition stays `.none`. [`Store+RuntimeTasks`](../../Packages/MemoshiCore/Sources/Store/Store+RuntimeTasks.swift) binds a `kind: subagent` task to its original root task and app conversation, then emits actual `task.created/started/status_changed/cancel_requested/finished` transitions. Foreground ownership cascades parent cancellation; a background anchor survives ordinary parent Stop and is stopped only by its own targeted task cancellation. Terminal facts require authoritative settled owner/submission state after pending tool outcomes drain, not `afterTool`, an empty live graph or a parent's success. Original IDs/ownership persist across reopen; child content remains in Pi, not event/audit payloads.

The child watcher emits a static, content-free `task.progress {taskId, message: "Child response updated."}` at most once per second per child, with the owning bot/conversation/task in `scope`. It is an observed-change refresh hint, not a percentage, child text or a fabricated lifecycle transition. The Mac carrier applies conversation focus to it; in-process consumers filter scope locally. [`tasks.graph`/`tasks.history`](protocol.md#current-child-task-profile) supply current records and actual child text. The existing single native event consumer coalesces refreshes; root projections require corroborated task ID, `kind: turn`, conversation and current watermark, so child state/text cannot become the root reply. [Focused retained proof](../../../evidence/2026-11-03-memoshi-wave3-integration/native/runtime-child-conversation-tests.txt) covers real children, typed inspection, targeted Stop, provider defaults and Core child kill cases, not all-call/nested-retirement recovery acceptance.


---

## 1. Principles

1. **Tables are the truth; events are the change log.** Clients rebuild state from list and history RPCs and follow it with events. Events are not event-sourced state, so pruning them loses no data.
2. **Same transaction.** A change to a memoshid object and its events (and audit rows, for audited types) commit together or not at all.
3. **One fact, one event.** Each domain fact has one type. When a Card wraps a domain object, resolving it writes the domain event (for example `approval.resolved`) and then `card.resolved`, in one transaction ([object-model.md §4.18](object-model.md#418-card-crd_)).
4. **No transcript copies.** Transcripts live once, in Pi storage ([D7](../plan/decisions.md#d7)). Persisted events carry IDs, hashes, counts and short labels, never message text, file contents or tool output.
5. **No secrets, ever.** Secrets appear only as `SecretRef`s. URLs are stored without query strings or fragments.
6. **Three classes.** Every type is **audited** (A), **durable** (D) or **UI-only** (U) ([§4](#4-event-classes)); the class is fixed per type.
7. **Every shipping type requires an emitter and a fixture.** This is the release coverage contract checked under [§11](#11-contract-fixtures-and-tests), not a claim that declaring a future payload/fixture implements its domain.
8. **One writer per conversation.** Events about a conversation's records are written first by its runner, the device that holds that conversation's lease; one bot's conversations may have different runners ([D74](../plan/decisions.md#d74)). Other devices write the same facts when they apply the replication stream, with the runner's `deviceId` and the same `cseq`. Events about bot-wide and user-level records (settings, grants, routines, memory, Trash state) are written by the device that made the change and reach the others as merges ([object-model.md §3.4](object-model.md#34-runner-replicas-and-record-ownership)).

## 2. Envelope

```json
{
  "v": 1,
  "seq": 48211,
  "cseq": 317,
  "ts": 1792486812345,
  "type": "approval.requested",
  "typeVersion": 1,
  "deviceId": "dev_01JC0D4E5F6G7H8J9K0M1N2P3Q",
  "actor": { "kind": "bot", "id": "bot_01JC3F7Q9R2M8K4T6V5W0X1Y2Z" },
  "subject": { "kind": "approval", "id": "apr_01JC3G5Y6Z7A8B9C0D1E2F3G4H" },
  "scope": {
    "botId": "bot_01JC3F7Q9R2M8K4T6V5W0X1Y2Z",
    "conversationId": "ses_01JC3G2A7B8C9D0E1F2G3H4J5K",
    "projectId": "prj_01JC1A2B3C4D5E6F7G8H9J0K1M",
    "taskId": "tsk_01JC3G4M5N6P7Q8R9S0T1V2W3X"
  },
  "origin": { "kind": "user", "id": "usr_01JC0A1B2C3D4E5F6G7H8J9K0M", "rootKind": "user", "hops": 0 },
  "payload": { "...": "type-specific" }
}
```

With §6's payload in place of `"...": "type-specific"`, this is the golden fixture `protocol/fixtures/events/approval.requested@1.json` ([protocol.md §14](protocol.md#14-schema-codegen-and-fixtures)).

| Field | Type | Null | Meaning |
|---|---|---|---|
| `v` | int | no | Envelope schema version; `1` in v1. The schema pins it with `const` (`$defs/EnvelopeVersion`): a strict decoder rejects another value, and a lenient one keeps it and reports `constraint_violated` [INFERENCE: Phase 0 implementation choice, 2026-10-23] |
| `seq` | int | yes | **Log sequence.** Assigned in the same SQLite transaction as the change on this device's log (`INTEGER PRIMARY KEY AUTOINCREMENT`), gapless, never reused. Each device numbers its own log, so a replicated change gets a local `seq` when it is applied. `null` for UI-only frames. |
| `after` | int | yes | UI-only frames only: the last durable `seq` written when the frame was sent, so clients can order it |
| `cseq` | int | yes | **Conversation sequence.** Gapless per conversation (`cht_`, `ses_`, `lan_`, `grp_`, `sth_`), set iff the event is durable and `scope.conversationId` is set. It is assigned by the conversation's writer (its runner, or the device that holds a side thread), so it is the same on every device. Work in child conversations (subagents and run conversations) rides its thread with `scope.taskId`; a Handoff's lane is a conversation of its own, with its own `cseq` ([D74](../plan/decisions.md#d74)). |
| `ts` | int | no | Unix epoch milliseconds, UTC (Draft 3 convention) |
| `type` | string | no | `<domain>.<past_participle>`, lowercase snake_case (`approval.requested`, `bot.status_changed`). UI-only streams use nouns (`message.delta`, `tool.output`, `task.progress`). |
| `typeVersion` | int | no | Payload schema version of this type ([§10](#10-compatibility-and-versioning)) |
| `deviceId` | string | no | The device that made the change: the conversation's runner for conversation records, the device that made the edit for bot-wide and user-level records, the owning device for device records, or the device that holds a side thread ([object-model.md §3.4](object-model.md#34-runner-replicas-and-record-ownership)) |
| `actor` | object | no | Who caused it: `{ kind, id? }`, `kind` is `user`, `assistant`, `bot`, `trigger` (`id` = `rtn_`, `wch_` or `wak_`), `system`, or `external_agent` (Phase 2, Mac only: an external coding agent working in a session, [D110](../plan/decisions.md#d110); §5.24) |
| `subject` | object | no | The primary object: `{ kind, id }`, `kind` is an object name from [object-model.md](object-model.md) (`bot`, `task`, `approval`, …) or `system`. Tool calls have no object ID, so `tool.*` events have `{ kind: "tool_call", id: <toolCallId> }`, and `inbox.changed` has `{ kind: "system", id: "inbox" }`, since the Inbox is a projection without an ID [INFERENCE: Phase 0 implementation choice, 2026-10-23] |
| `scope` | object | no | Routing context: `{ botId?, conversationId?, projectId?, taskId? }` |
| `origin` | object | yes | The work's `Origin` (`kind`, `id`, `rootKind`, `hops`), on events about work ([object-model.md §3.3](object-model.md#33-origin-and-regime)) |
| `payload` | object | no | Type-specific; JSON camelCase; enum values snake_case |

**Live-only fields.** Fields marked † in the catalog are attached only to the live frame sent to clients that focus the conversation, and are stripped before the event is persisted. Replayed or resynced clients fetch that content through history RPCs. This is how `message.completed` can carry the final text live without the log storing transcripts ([D7](../plan/decisions.md#d7)).

**Class rules** [INFERENCE: Phase 0 implementation choice, 2026-10-23]. A UI-only (U) type carries `seq: null` and `after`, and no `cseq`; a durable (D) or audited (A) type carries an integer `seq` and no `after`. The schema's `<Type>Event` definitions require this, a strict decoder (the engine's) rejects a frame that breaks it, and a lenient decoder (a client's) keeps the event and reports `inconsistent_event_class` ([§10](#10-compatibility-and-versioning)). An optional field with no value is left out rather than sent as `null` ([protocol.md §4](protocol.md#4-conventions)), so in the table above "yes" for `after`, `cseq` and `origin` means the field may be absent; `seq` is the only envelope field sent as `null`.

**Delivery** (agreed with [protocol.md](protocol.md)): each event is a JSON-RPC 2.0 notification with method `event` and the envelope as `params`; the engine may batch several notifications in one WebSocket frame. A client calls `events.subscribe { after, focus? }` and receives `{ mode: "replay" | "resync", head, minRetainedSeq }`. UI-only frames go only to clients that declared the conversation in focus (`events.focus`), except global UI-only types (`task.progress`, `inbox.changed`, `device.links_changed`, `replica.state_changed`, `system.resync_required`). Between devices, the replication stream carries each change with its events, and the receiving device writes them into its own log ([protocol.md §12.7](protocol.md#127-replication-and-catch-up)). UI-only frames cross devices only to a device that shows the conversation, coalesced to about 10 frames a second, over direct and relay links and never through iCloud ([D82](../plan/decisions.md#d82)).

**Current focus boundary:** the full catalog's global `task.progress` intent above is not a claim that current child hints broadcast globally. A child hint carries `scope.conversationId`; [`RPCSession`](../../Packages/MemoshiDaemon/Sources/MemoshiDaemon/RPCSession+Events.swift) filters every conversation-scoped UI-only frame against focus, including that hint. Durable facts remain replayable independently of focus. The typed in-process feed orders live hints behind their durable `after` watermark but does not implement socket focus RPCs; the app filters conversation/task scope. No child `message.delta` is forwarded as a root message stream.

## 3. Ordering, delivery and idempotency

- Durable events are totally ordered by `seq` within a device's log. Within a conversation, `cseq` has no gaps; a gap is a bug, and the client asks for a resync of that conversation.
- Replicated changes are applied in each conversation's replication order (`rseq`). A change from an older lease epoch is rejected (`lease.fenced`) and never reaches the log ([object-model.md §3.4](object-model.md#34-runner-replicas-and-record-ownership)). Merged records apply on arrival.
- Delivery is at-least-once. Clients dedupe by `seq`. UI-only stream frames carry `offsetUtf16`: the stream's length in UTF-16 code units (the unit of `NSString` lengths) before this append. Receivers drop overlap they already have, append only unseen text, and fetch history (with `live`) only on a real gap; a late delta never regresses a message that `message.completed` already finished. `tool.output` counts over Pi's retained output window and adds `trimStart` when Pi trims the window. The scheme follows the measured MemoBot behavior ([http.md](../research/prior/grok-bot-measured/http.md)); the receiver rule is in [protocol.md](protocol.md).
- The engine writes an event before acknowledging the RPC that caused it (kept from Draft 3). On a subscribed connection, the events a request wrote are sent before its response, a result or an error alike, because both share one ordered send queue; the daemon does this for mutating methods and `bots.grants.list`, and reads that can write events are not ordered yet ([protocol.md §4](protocol.md#4-conventions)).
- Clients never treat an event as fact unless it was persisted, except UI-only frames, which only animate what history RPCs will later confirm.
- **Coalescing:** `message.delta`, `tool.output`, `codemode.output` and `process.output` follow Pi's commit cadence (partial answers and tool output are committed at most every 100 ms by default, pi-durable README "Watching a Conversation"); `bot.status_changed` and `inbox.changed` are coalesced to at most one per subject per 250 ms; `egress.blocked` is coalesced per host per task.
- **Staged streams** (§5.22, §5.25): `card.delta` and `voice.transcript` are UI-only and never stored. `card.delta` orders a card's frames by a gapless `rev` instead of an offset, and `voice.transcript` uses `offsetUtf16` within a segment; receivers apply the same overlap and gap rules as above [INFERENCE: their cadence is set with their phases]. They go only to clients that focus the conversation. Three staged frames are routed differently: `view.arranged` goes to the device whose layout it changes (§5.20), and `browser.frame` and `computer.frame` to the connection that opened the watch (§5.13).

## 4. Event classes

| Class | Persisted in `events` | Mirrored to `audit_log` | Replayable | Use |
|---|---|---|---|---|
| **A** audited | yes | yes, same transaction, hash-chained ([policy.md](policy.md)) | yes | Decisions, permissions, external effects, identity and configuration changes, deletions, every tool call outcome |
| **D** durable | yes | no | yes, within retention | State changes clients must not miss |
| **U** UI-only | no | no | no | Streaming text and output, progress, counters; recovered through history RPCs |

Audit rows hold the same redacted payload as the event plus its hash; payloads can later be purged while the hash keeps the chain verifiable. The audit chain ships in v1 (Phase 1); construction, keying and the 1-year default retention are in [policy.md](policy.md). Each device keeps its own chain, and its rows replicate read-only to the user's other paired devices ([D81](../plan/decisions.md#d81), [policy.md §14.3](policy.md#143-tamper-evidence)). Each device signs its chain head, its peers anchor the signed heads, and verification checks every chain ([D82](../plan/decisions.md#d82)). Every policy decision is audited ([D27](../plan/decisions.md#d27)); every tool call therefore produces at least `policy.decided` and `tool.completed` (or `codemode.completed`).

**Development implementation (2026-11-03):** schema 4 atomically mirrors class-A envelopes into local `audit_events`, independently of event pruning. Schema 5 adds immutable fenced runtime-call receipts: `afterTool` prepares scrub accounting but does **not** claim completion; actual Pi terminal/result commits produce one `tool.completed` fact and mirror. Generation-side rejections use real result-entry receipts when no tool task exists. Normal rejected/aborted/nested-schema outcomes and reopen deduplication have [bounded proof](../HANDOFF.md#committed-tool-outcome-proof). Model `outputBytes` includes committed SDK diagnostic text; nested calls count returned text/canonical structured data, zero when absent, not HTTP wire bytes. This remains a plain mirror, not keyed chains/anchors or historical source backfill. The nested result-retirement crash window [below](#current-nested-result-retirement) remains open under H1/E20: these live/normal-reopen receipts are not a complete all-origin audit or kill/resume pass.

## 5. Catalog

Columns: **C** = class. Payload lists key fields; every payload also identifies its subject. † = live-only field.

A payload identifies its subject by the subject's ID field (`messageId`, `taskId`, `approvalId`, `cardId`, `sideThreadId` and so on), even where a row below lists no fields, as for `task.started`, `approval.expired` and `card.expired`, and even where an example in §6 shows only a payload's other fields [INFERENCE: Phase 0 implementation choice, 2026-10-23]. The [typed registry](../../Packages/MemoshiProtocol/Sources/MemoshiProtocol/Events/EventEnvelope.swift) and its fixtures cover the currently declared subset, including lifecycle, policy, tool-outcome and review payloads. The full accepted catalog below remains broader; declarations/schema coverage alone do not certify an emitter, audit chain or installed service.

**Listed values are exact** [INFERENCE: Phase 0 implementation choice, 2026-10-23]. Where a row lists a field's values, those are all its values, even when the field's wider enum has more: `message.queued`'s `whenBusy` is `steer` or `follow_up`, never `reject`, and `task.finished`'s `status` is only a terminal one. A Swift payload gives such a field its own open enum of exactly those values, so the schema and a strict decoder reject any other value, and a lenient decoder keeps it as `.unknown` ([§10](#10-compatibility-and-versioning)). Fields with a limit, such as a title of at most 120 characters or a tier from 0 to 5, follow [protocol.md §4](protocol.md#4-conventions) (Field limits).

### 5.1 System

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `system.started` | D | `version`, `protocolVersion`, `engineVersion` (Pi_Swift and its upstream pin, [D44](../plan/decisions.md#d44)), `recovering` | The engine finished booting |
| `system.recovered` | A | `resumedTasks`, `interruptedTasks`, `uncertainDrafts`, `reconciledMessages` | Crash recovery completed ([§8](#8-pi-projection)) |
| `system.storage_recovered` | A | `store` (`memoshi` or a thread ID), `restoredFrom?` (backup date), `historyUnavailable` | A corrupt store was moved to quarantine and restored from the latest backup; an Inbox card tells the user ([04 §6.7](../plan/04-architecture.md#67-backups-and-integrity)) |
| `system.stopping` | D | `reason`: `update`, `user`, `signal` | Graceful shutdown begins |
| `system.migrated` | A | `store` (`memoshi` or a thread ID), `fromSchema`, `toSchema`, `backupPath` | A migration ran; the store was backed up first ([D44](../plan/decisions.md#d44)) |
| `system.settings_changed` | A | `keys`, non-sensitive `values` | Experience mode, telemetry opt-in, the relay and iCloud links, the relaunch setting and similar changed |
| `system.app_connected` | D | `appVersion`, `capabilities` | On the Mac: Memoshi.app's capability channel connected ([D12](../plan/decisions.md#d12)) |
| `system.app_disconnected` | D | `reason` | It disconnected |
| `system.pruned` | D | `beforeSeq`, `deleted` | The retention job pruned events ([§9](#9-retention-and-pruning)) |
| `system.data_exported` | A | `scope`, `format` | The user exported data |
| `system.diagnostics_exported` | A | `contents` | The user exported diagnostics ([D28](../plan/decisions.md#d28)) |
| `system.resync_required` | U | `scope?` (`conversationId`), `reason`: `cursor_expired`, `gap`, `projector_reset`, `protocol_changed` | Sent to one client that must refetch ([§7](#7-snapshots-and-resync)) |

### 5.2 Bot

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `bot.created` | A | `name`, `role`, `avatar`, `createdBy`, `templateKey?`, `importedFrom?` | A bot was created (with its Chat, Computer and Browser) |
| `bot.updated` | A | `changed` (field names), non-sensitive values | Name, avatar, model, computer, section or pin changed |
| `bot.permission_mode_changed` | A | `permissionMode`, `previous`, `by`, `bypassConfirmed?` | The user changed the bot's permission mode; turning on Bypass records that the confirmation naming the risks was accepted ([D52](../plan/decisions.md#d52)) |
| `bot.mail_send_by_itself_changed` | A | `mailSendByItself`, `previous`, `by` (always `user`), `deviceId` | Phase 1: the user turned **Send mail by itself** on or off for the bot (`Bot.mailSendByItself`), so the log shows every period it was on ([D116](../plan/decisions.md#d116), [policy.md §11.3](policy.md#113-mail-drafts-and-send-mail-by-itself), [§14.2](policy.md#142-what-is-audited)) [INFERENCE: name set in Phase 1] |
| `bot.revision_proposed` | A | `revisionId`, `fields`, `proposedBy`, `cardId` | A persona or job change was proposed |
| `bot.persona_changed` | A | `revisionId`, `version`, `fields`, `by` | A revision was applied |
| `bot.revision_rejected` | A | `revisionId`, `by` | A revision was rejected |
| `bot.status_changed` | D | `status`, `previous`, `pauseReason?`, `takenOver`, `computerState`, `nextWakeAt?`, `unreadCount`, `runnerDeviceIds` (the devices that run its conversations with live work, [D74](../plan/decisions.md#d74)) [INFERENCE: name] | Derived status or its orthogonal fields changed ([object-model.md §5.1](object-model.md#51-bot-status)) |
| `bot.fault_changed` | D | `fault` (`code`, `message`) or `null` | A blocking fault was raised or cleared |
| `bot.paused` | A | `reason`: `user`, `away`, `budget` | Paused |
| `bot.resumed` | A | `by` | Resumed |
| `bot.archived` | A | | Archived |
| `bot.restored` | A | `by`, `deviceId` | Restored from archive, or from Trash on any device ([D74](../plan/decisions.md#d74)) |
| `bot.deleted` | A | `purgeAfter` | Moved to Trash on every device, with its Chat and lanes, for 30 days ([D74](../plan/decisions.md#d74)) |
| `bot.purged` | A | `by`: `user` (Empty Trash) or `system` (30 days) | Purged everywhere: records, conversation stores and their replicas, home folders |
| `bot.exported` | A | `formatVersion`, `includesMemory`, `memoryCount` | Exported as `bot.md` ([bot-definition.md](bot-definition.md)) |
| `bot.imported` | A | `formatVersion`, `sourceBotId?`, `requestedGrants`, `proposedRoutines`, `proposedWatches`, `missingSkills`, `warnings` | Created from a `bot.md` |

From Phase 2 a change of a bot's voice engine (`Bot.voice`, [D111](../plan/decisions.md#d111)) is a `bot.updated` with `changed: voice`, and the user's choice among This Mac (sandboxed), a Bot computer and a Cloud computer ([D113](../plan/decisions.md#d113)) is the existing `bot.updated` with `changed: computerId`; neither has a type of its own [INFERENCE].

### 5.3 Chat, session and project

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `chat.created` | D | `botId` | With its bot |
| `chat.read` | D | `lastReadMessageId` | Read cursor moved |
| `chat.context_reset` | D | `by`, `hasNote` | "Start fresh" (Pi `reset`) |
| `chat.compacted` | D | `reason`: `auto`, `manual`, `overflow` | Pi compaction placed a summary |
| `session.created` | D | `projectId?`, `leadBotId`, `workspaceKind?`, `origin` | A session opened |
| `session.updated` | D | `changed`: `title`, `model`, `computerId`, `plan` | Includes turning the `/plan` option on or off ([D52](../plan/decisions.md#d52)) |
| `session.forked` | A | `fromSessionId`, `atMessageId?`, `taskId?` | The user forked a session: a new Session with its own store and lease, started from the parent's history at the fork point, and from a coding turn also its checkpoint's files ([D77](../plan/decisions.md#d77), [D80](../plan/decisions.md#d80), [policy.md §3.10](policy.md#310-checkpoint-restores-and-forks)) |
| `session.read` | D | `lastReadMessageId` | |
| `session.context_reset` | D | `by`, `hasNote` | |
| `session.compacted` | D | `reason` | |
| `session.archived` | D | | |
| `session.restored` | D | | |
| `session.deleted` | A | `purgeAfter` | Moved to Trash on every device for 30 days ([D74](../plan/decisions.md#d74)) |
| `session.purged` | A | `by`: `user` or `system` | Purged everywhere; its Pi file goes once no thread (for example a fork) references it |
| `trash.emptied` | A | `count`, `kinds`, `by` (`user` or `system`, like `session.purged`; [D130](../plan/decisions.md#d130)) | **Empty Trash** purged what was listed, on every device ([D74](../plan/decisions.md#d74)); a request with no `ids` purges everything in Trash [INFERENCE: names in Phase 2] |
| `session.changes_updated` | U | `files` (`path`, `status`, `added`, `removed`), `totals` | Worktree change set changed ([07-coding.md](../plan/07-coding.md)) |
| `project.added` | A | `name`, `rootPath` (home-relative), `deviceId`, `trust` | |
| `project.updated` | D | `changed` | |
| `project.trust_changed` | A | `trust`, `previous` | |
| `project.bot_attached` | A | `botId` | |
| `project.bot_detached` | A | `botId` | |
| `project.removed` | A | | App state removed; the folder is untouched |

### 5.4 Message

**Local unsent is not a durable conversation event** ([D88](../plan/decisions.md#d88)). When neither the runner nor an available allowed model is reachable, the existing device-local queue persists the message and original client `requestId` across restart and shows **Waiting for connection** ([protocol.md §5.3](protocol.md#53-conversations-chats-sessions-groups), [§9](protocol.md#9-idempotency)). Queuing or canceling before delivery emits no `message.*`, `task.*`, `side_thread.*` or model-fallback event and acquires no lease; there is no authoritative store write, model turn, tool call, answer, summary or effect to report. On reconnect, normal idempotent submission to the current confirmed runner admits each uncanceled input once, and the existing `message.created` or Pi `message.queued` event confirms its optimistic row using that same `requestId`. Current grants, budgets and recovery holds remain in force; no new event family or scheduler is introduced.

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `message.created` | D | `messageId`, `role`, `authorId?`, `kind`, `requestId?` (user messages: the client's `requestId` from `chats.send`, `sessions.send` or `groups.send`; it confirms the app's optimistic composer row, [protocol.md](protocol.md)), `replyToMessageId?`, `attachments` (`name`, `mimeType`, `sizeBytes`), `content`†. `kind` and `attachments` are always present, `attachments` as `[]` when there are none [INFERENCE: Phase 0 implementation choice, 2026-10-23] | A user message was admitted, a bot message started streaming, or a card, note or summary entry was placed |
| `message.delta` | U | `messageId`, `offsetUtf16`, `text`, `channel`: `text`, `thinking` | Streaming partial |
| `message.completed` | D | `messageId`, `stopReason`, `usage?`, `reconciled?` (§8), `content`†. `stopReason` is `stop`, `length`, `tool_use`, `error` or `aborted`, and there is no `role` [INFERENCE: Phase 0 implementation choice, 2026-10-23] | The `pi.assistant` entry committed |
| `message.failed` | D | `messageId`, `error` (`code`, `message`, `retryable`, `retryAfterMs?`), `partial` | The generation failed; partial text is kept |
| `message.queued` | D | `messageId`, `requestId?` (as in `message.created`), `whenBusy`: `steer`, `follow_up` | Admitted input queued while the conversation was busy (Pi `pi.inbox`); it confirms the optimistic row, and `message.created` follows when the input is placed. Never emitted for a device-local unsent message ([D88](../plan/decisions.md#d88)) |
| `message.withdrawn` | D | `messageId` | An admitted Pi queued input was withdrawn; canceling a local unsent message emits no conversation event |

### 5.5 Task

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `task.created` | D | `taskId`, `kind`, `title`, `origin?`, `regime`, `parentTaskId?`, `routineId?`, `watchId?`, `wakeId?`, `handoffId?`, `scheduledFor?`. `origin` may be left out of the payload, since the envelope carries it [INFERENCE: Phase 0 implementation choice, 2026-10-23] | A task was created (for runs, in the claim transaction) |
| `task.started` | D | `taskId`, `status?` (`running`, as in [protocol.md §13](protocol.md#13-examples)) [INFERENCE: Phase 0 implementation choice, 2026-10-23] | First transition to `running` |
| `task.status_changed` | D | `status` (`running` or `waiting`), `waitingOn?`, `previous` (`running` or `waiting`: `task.started` and `task.finished` report every transition out of `queued`, [object-model.md §5.2](object-model.md#52-task)) [INFERENCE: Phase 0 implementation choice, 2026-10-23] | Non-terminal transitions |
| `task.progress` | U | `message`, `step?`, `percent?` (0–100 [INFERENCE: Phase 0 implementation choice, 2026-10-23]) | Target progress chips/tickers. Current child hint is static/content-free, ≤1 Hz and scoped to the owning conversation/task; it carries no `step`, `percent` or child output |
| `task.interrupted` | D | `reason`: `restart`, `lease_expired`; `resumeMode`, `lastToolCallId?` | A restart, or a lease that expired mid-step, interrupted it. With `resumeMode = explicit` its step gets an outcome check or a Resume card ([D42](../plan/decisions.md#d42), [D51](../plan/decisions.md#d51)) |
| `task.resumed` | D | `by`: `user` (a Resume or error card), `system` (`resumeMode = auto`, or a definite outcome check) | It continued after an interruption or an error card. Current code (since 2026-11-20, [`RuntimeAdapter+Threads`](../../Packages/MemoshiCore/Sources/Runtime/RuntimeAdapter+Threads.swift), `Store.recordTurnResumed`): sent with `by: system` once per restart, and since [D139](../plan/decisions.md#d139) also after a graceful close, when a conversation first opens and Pi continues an admitted chat turn it had not settled; that reply then carries `resumedAfterInterruption` in `chats.history` ([protocol.md](protocol.md#current-text-chat-profile)). Not sent for a turn that finished, was stopped, is held for a Resume card or is parked by Pi. `by: user` and `task.interrupted` are still never sent, and child tasks' resumes are not recorded |
| `task.cancel_requested` | D | `by` | Stop pressed; the abort runs bottom-up. Current code: `tasks.abort` and, since 2026-11-18, `chats.abort` record it with `by: user` before the actual abort ([protocol.md](protocol.md#current-text-chat-profile)); a child's cancellation that Pi reports is projected with `by: system` ([`Store+RuntimeTasks`](../../Packages/MemoshiCore/Sources/Store/Store+RuntimeTasks.swift)) |
| `task.finished` | A | `status`, `outcome`, `summary?`, `error?`, `usage`, `durationMs` | Terminal: `done`, `failed` or `canceled` |

There is no pushed task-graph event: the task panel loads `tasks.graph` (with `asOf`) and follows `task.*` events ([§7](#7-snapshots-and-resync)).

### 5.6 Tool and Code Mode

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `tool.started` | U | `toolCallId`, `parentToolCallId?`, `tool`, `verb?`, `tier`, `argsPreview`, `computerId?`, `deviceId?` (the device that runs it when that is not the runner, [D49](../plan/decisions.md#d49)) | A tool call began (after `policy.decided`) |
| `tool.output` | U | `toolCallId`, `offsetUtf16`, `text`, `trimStart?` | Running output over Pi's retained window |
| `tool.completed` | A | `toolCallId`, `parentToolCallId?`, `tool`, `ok`, `errorCode?`, `exitCode?`, `durationMs`, `outputBytes`, `redactions`, `usage?` | The result committed (metadata only, never output) |
| `tool.interrupted` | A | `toolCallId`, `tool`, `replay`: `safe`, `unsafe`; `effect`: `rerun`, `outcome_check`, `resume_card` | A restart or an expired lease cut the call off before its outcome was recorded. A replay-safe call reruns; any other shows as "Interrupted: may have happened" and gets its outcome check, or a Resume card if its tool has none ([D51](../plan/decisions.md#d51)). Current code: emitted once with each Resume card, always with `replay: unsafe` and `effect: resume_card`, for a kill or crash, a stale dispatch found at reopen, a stopped execution, an unknown returned outcome, a step whose result Pi lost after Memoshi recorded it as completed, and a replay-safe step whose tool is no longer registered as replay-safe (still `replay: unsafe`) ([protocol.md](protocol.md#current-step-settlement), [`Store+ResumeSteps`](../../Packages/MemoshiCore/Sources/Store/Store+ResumeSteps.swift)) |
| `tool.outcome_checked` | A | `toolCallId`, `tool`, `checkTool`, `result`: `happened`, `not_happened`, `inconclusive`; `next`: `continue`, `run_again`, `resume_card` | The automatic outcome check of an interrupted call finished ([D51](../plan/decisions.md#d51)) |
| `tool.interruption_resolved` | A | `toolCallId`, `tool`, `action`: `run_again`, `skip`, `mark_done`; `cardId`, `by` | The user answered the Resume card, on any device ([D51](../plan/decisions.md#d51)) |
| `codemode.started` | U | `toolCallId`, `scriptHash`, `scriptPreview`, `tools` | A Code Mode script began |
| `codemode.output` | U | `toolCallId`, `offsetUtf16`, `text` | Script output |
| `codemode.resumed` | D | `toolCallId`, `replayedCalls` | After a restart the script re-ran from its journal without repeating finished calls |
| `codemode.completed` | A | `toolCallId`, `ok`, `errorCode?` (`replay_diverged`, `timeout`, …), `nestedCalls`, `durationMs`, `scriptHash` | The script finished |

The outer `codemode` call emits `codemode.*` instead of `tool.*`. Each nested call emits its own `policy.decided` and `tool.*` with `parentToolCallId`, because Pi runs `beforeTool` and `afterTool` for nested Code Mode and MCP-bridge calls ([D9](../plan/decisions.md#d9)). The shell front end works the same way: its outer call emits `tool.*`, and each typed call parsed from the command line emits its own `policy.decided` and `tool.*` with `parentToolCallId`. Every typed call of a line is decided before any of them runs, and the calls that ask share one grouped card ([D81](../plan/decisions.md#d81), [policy.md §3.4.6](policy.md#346-the-shell-front-end)). An unknown command fails the shell call before anything runs ([D50](../plan/decisions.md#d50)).

A bot's call to a function that an App exports (Phase 1, [D114](../plan/decisions.md#d114)) is such a nested call, and so is every tool call the function makes; §5.20 gives the details. No `tool.*` type or field changes for it.

### 5.7 Policy, approval, grant, egress and secret

Names and fields agreed with [policy.md](policy.md).

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `policy.decided` | A | `toolCallId`, `parentToolCallId?`, `via?`: `model`, `code_mode`, `mcp` (the call's channel, [policy.md](policy.md) P1: an MCP-bridge tool is `mcp` whoever calls it, otherwise `model` for the model's own call and `code_mode` for a call nested in a Code Mode script; absent for a call nested in any other host tool and in facts recorded before the field), `tool`, `decision`: `allow`, `ask`, `draft`, `deny`, `rewrite`; `autoSend?` (a `draft` that is sent without a card: a Bypass bot's, [D52](../plan/decisions.md#d52), or the built-in `mail.send` of a bot whose Send mail by itself is on, [D116](../plan/decisions.md#d116)); `tier` (always an integer 0–5; an unknown or unclassifiable tool is `opClass: unknown` with tier 3), `opClass`, `ruleId`, `permissionMode`, `plan`, `origin`, `attendance`, `exposure` (`untrusted`, `privateData`), `deviceId`, `recheck?`, `source?` (a live card's or App's call: its ID, version and trigger, §5.19), `grantId?` (the `tool_rule` Grant of the standing rule that allowed the call; staged, not in the Phase 0 Swift payload yet, §10 rule 8), `reasonCode`, `policyVersion`, `argsHash` | Every tool call, before it runs. The device that runs a cross-device call re-checks its grants and writes its own `policy.decided` with `recheck: true` ([D49](../plan/decisions.md#d49), SEC-27) |
| `policy.redacted` | A | `toolCallId`, `count`, `kinds` | `afterTool` redacted output |
| `policy.rule_changed` | A | `ruleId?`, `policyVersion`, `change` | Built-in rules or user deny rules changed |
| `policy.paused` | A | `by` | "Stop all bots" kill switch engaged: every run aborts and routines, wakes and watches pause (feature SEC-22) |
| `policy.resumed` | A | `by` | Kill switch released |
| `approval.requested` | A | Approval fields except `confirmationText`; `cardId`, `confirmationRequired` | A call needs a decision |
| `approval.resolved` | A | `status`: `allowed`, `denied`; `scope?`: `once`, `task`, `always`; `grantId?`, `decidedBy`, `typedConfirmationOk?`, `deviceAuth?` (T4 and T5: `face_id`, `touch_id` or `passcode`, [D75](../plan/decisions.md#d75)) | The user decided |
| `approval.expired` | A | | `expiresAt` passed; treated as denied |
| `approval.canceled` | A | `reason`: `task_canceled`, `call_aborted`, `superseded`, `kill_switch`, `grant_revoked` | The call went away first ([policy.md §10.1](policy.md#101-lifecycle)) |
| `grant.requested` | A | `grantId`, `kind`, `target`, `scope`, `requestedBy`, `reason?` | |
| `grant.granted` | A | `grantId`, `grantedBy`, `expiresAt?`, `sourceApprovalId?`, `effect?` | |
| `grant.denied` | A | `grantId`, `by` | |
| `grant.revoked` | A | `grantId`, `by` | |
| `grant.expired` | A | `grantId` | |
| `egress.allowed` | A | `host`, `computerId`, `taskId` | First admitted connection per host/computer/task; admission before dispatch, not proof of delivery or an external effect |
| `egress.blocked` | A | `host`, `computerId`, `taskId?`, `count` | Refused by gateway/policy; first refusal is immediate, later counts are durably coalesced per host/computer/task and flushed on tool settlement or ownership release/recovery. Unknown or malformed call attribution has no task and is never assigned to the current root turn |
| `secret.stored` | A | `secretRef`, `kind`, `label`, `thisDeviceOnly` | A secure form or sign-in stored a secret |
| `secret.used` | A | `secretRef`, `purpose`: `browser_fill`, `egress_placeholder`, `exec_env`; `host` | Host-side credential use (never its value or mask token); gateway emission records an actual prepared header injection, not a claim that the upstream received it. On iPhone and iPad the broker is in-process ([D76](../plan/decisions.md#d76)) |
| `secret.scope_changed` | A | `secretRef`, `thisDeviceOnly`, `holderDeviceId?`, `by` | The user marked a secret this device only, or let it sync again ([D75](../plan/decisions.md#d75)) [INFERENCE: names in Phase 2] |
| `secret.deleted` | A | `secretRef` | |

**Current local folder emitter (schema 6):** only the Store lifecycle APIs emit the three typed `grant.granted`, `grant.revoked` and `grant.expired` facts; generic `Store.commit` cannot manufacture them. They are bot-scoped, identify the grant and actor where applicable, and never carry bookmark bytes or a copied source path. A read/write access change increments the record revision and emits `grant.granted` again; consumers must read the current record rather than infer access/revision from that payload. Grant change/expiry and cancellation of dependent pending approvals/cards share one transaction. `sourceApprovalId`/`effect`, `grant.requested/denied`, management RPCs and replicated grant lifecycle are still target contracts, not this local emitter.

**Current close (2026-11-20, [D139](../plan/decisions.md#d139)):** a graceful close (Quit of the app-owned helper, `system.shutdown`, `InProcessEngine.close`) aborts no conversation. For a turn that streams a reply, waits on an approval (a foreground subagent child's included) or runs a child, it writes none of `approval.canceled`, `card.canceled`, `tool.completed {errorCode: aborted}` and `task.finished`; approvals, Cards, child tasks and queued inputs stay, and Pi writes running work back as pending. The close projects nothing; the next open's reconcile does, as after a crash. After reopen the Store records `task.resumed {by: system}` (§5.5): Pi regenerates a reply that was streaming, flagged `resumedAfterInterruption` and with no `[stopped]` note; a call that waited on an approval gets a second `policy.decided` (`ask`) and waits on the same approval and Card, as after a kill; a child waiting on a Card stays `waiting/approval`, and the child and its parent continue. A user Stop still cancels the approval, the Card and the turn ([policy.md §10.1](policy.md#101-lifecycle)).

**Classes added on 2026-11-13** ([D118](../plan/decisions.md#d118), [D121](../plan/decisions.md#d121)). `policy.decided` carries the classes of [policy.md §3.1](policy.md#31-operation-classes) in `opClass` as their tools ship: `search.web`, `mail.read`, `mail.stage`, `mail.organize`, `mail.send`, `mail.destroy` and `app.call` in Phase 1; `media.generate`, `voice.cloud`, `computer.cloud_start`, `computer.input` and `plugin.install` in Phase 2. Their tiers are policy.md's and are not restated here. `source.trigger` gains `function`, for a call made by an App's exported function (§5.20). `ruleId` names the deciding rule (`matrix.ask`, `rule.allow`, `bridge.not_approved`, `mail.send_by_itself`), and `reasonCode` is the stable reason beside it ([policy.md](policy.md), Wire names). A standing rule is a `tool_rule` Grant: creating, revoking and expiring one are `grant.granted`, `grant.revoked` and `grant.expired`. A call that a standing rule allowed is a `policy.decided` with `decision: allow`, `ruleId: rule.allow` and the rule's Grant in `grantId?`, never in `ruleId` ([policy.md §9](policy.md#9-evaluation-order-and-pseudo-code), §5.23). `grantId?` is the one field this adds to `policy.decided`; it is optional, so Phase 0's payload and fixtures stay valid [INFERENCE: set in Phase 1].


### 5.8 Draft

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `draft.created` | A | `draftId`, `draftKind`, `op?`, `target` (summary), `connectorId?`, `accountId?`, `version`, `contentHash`, `validUntil?`, `autoSend`, `cardId?` (absent with `autoSend`) | A T4 call was staged |
| `draft.updated` | A | `version`, `contentHash`, `editedBy` | Edited by the user or revised by the bot |
| `draft.send_started` | A | `version`, `contentHash`, `autoSend`, `deviceAuth?` (`face_id`, `touch_id` or `passcode`; absent with `autoSend`, [D75](../plan/decisions.md#d75)) | The user pressed Send with the hash they saw, or, with `autoSend`, the engine started the send itself as the bot ([D52](../plan/decisions.md#d52)); a single-use send token was issued |
| `draft.sent` | A | `version`, `externalRef?` | The provider confirmed |
| `draft.failed` | A | `error`, `retryable`, `uncertain` | The send failed or its outcome is unknown after a crash |
| `draft.discarded` | A | `by` | |
| `draft.expired` | A | | `validUntil` passed |
| `draft.superseded` | A | `byDraftId` | The bot staged a newer draft for the same target |

**Mail** (Phase 1 on the Mac, Phase 3 on iPhone and iPad; [D116](../plan/decisions.md#d116), [D118](../plan/decisions.md#d118)). `mail.send` is T4 and a Draft, except where the user let that bot send mail by itself ([policy.md §11.3](policy.md#113-mail-drafts-and-send-mail-by-itself)). Its Draft has `draftKind: email`, the built-in mail Connector as `connectorId` and the mail account as `accountId`. Where the bot sends by itself the Draft is still recorded: `draft.created` and `draft.send_started` carry `autoSend: true` and no `cardId`, and the `policy.decided` before them has `decision: draft`, `autoSend: true` and `ruleId: mail.send_by_itself`, which tells it from a Bypass send (`bypass.send`). No `draft.*` type or field is added (§5.23).

### 5.9 Memory

Names agreed with [05-bots-and-assistant.md](../plan/05-bots-and-assistant.md).

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `memory.written` | A | `memoryId`, `scope`, `scopeId`, `kind`, `author`, `provenance`, `contentHash`, `content`† | A bot wrote its own scope |
| `memory.proposed` | A | `memoryId`, `scope`, `scopeId`, `contentHash`, `cardId?`, `content`† | A write to `user` or `team` scope, or an import |
| `memory.accepted` | A | `by` | Proposal accepted |
| `memory.rejected` | A | `by` | Proposal rejected |
| `memory.updated` | A | `changed`, `by`, `contentHash` | Edited (user) or corrected |
| `memory.retracted` | A | `by` | Marked as never true |
| `memory.superseded` | A | `byMemoryId` | Merged into another entry |
| `memory.archived` | A | `by`: `user`, `consolidation` | Removed from loading, still searchable |
| `memory.restored` | A | `by` | |
| `memory.expired` | D | `validTo` | Its validity window ended ("past") |
| `memory.quarantined` | A | `reason` | The secret or injection scanner flagged it |
| `memory.consolidation_proposed` | A | `consolidationId`, `counts` (`merge`, `supersede`, `retire`, `archive`, `promote`), `cardId` | The nightly pass produced a diff |
| `memory.consolidation_applied` | A | `consolidationId`, `applied` | The user accepted it (fully or partly) |

Memory written on another device arrives through replication and produces the same `memory.*` types, with that device's `deviceId`. Concurrent edits merge entry by entry: validity windows, statuses and deletions ([D49](../plan/decisions.md#d49), DEV-10).

### 5.10 Card and Inbox

Names agreed with [02-experience.md](../plan/02-experience.md).

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `card.created` | D | `cardId`, `kind`, `variant?`, `subject?`, `messageId`, `title`, `inbox`, `needsYou`, `expiresAt?`, `payload`. `subject` may be left out, as a card's subject may be null; `messageId` and `payload` are always present [INFERENCE: Phase 0 implementation choice, 2026-10-23] | A card was placed |
| `card.updated` | D | `cardId`, `payload` | Display data changed (for example a draft was edited, or a Resume card no longer offers Run again once Pi's result is projected) |
| `card.resolved` | D | `cardId`, `outcome`, `by`. `outcome` is the card's `{action, payload?}` and `by` an actor kind ([protocol.md §5.6](protocol.md#56-memory-decisions-and-the-inbox)) [INFERENCE: Phase 0 implementation choice, 2026-10-23] | Resolved through `cards.respond` (after the domain event) |
| `card.expired` | D | | Its subject expired |
| `card.canceled` | D | `cardId`, `reason` | Its subject went away. The approval emitter cancels domain/card together without inventing a user answer; native pending counts clear from authoritative state. |
| `card.seen` | D | | A `run_summary` or news card was seen |
| `inbox.changed` | U | `pendingCount`, `needsYouCount`, `unreadCount` | Inbox counts changed (badges, menu bar) |

The Inbox has no events of its own beyond the counter: it is a projection over cards ([object-model.md §4.22](object-model.md#422-inbox)). Display cards (`apple_data`, `generated`) emit only `card.created` and `card.updated`, and a live card also `card.permissions_approved` (§5.19); a JSON card's buttons start tool calls or messages, and a live card's program calls tools through the bridge, which emit their own events ([cards.md](cards.md), §5.19).

From Phase 1 a JSON card streams as the model writes it ([D115](../plan/decisions.md#d115), CH-19). Its partial updates are the UI-only `card.delta` frames of §5.25; `card.created` and `card.updated` stay the only durable facts about a card's content and keep their payloads and meaning.

### 5.11 Routine, watch and wake

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `routine.proposed` | A | `routineId`, `botId`, `name`, `trigger`, `costPreview`, `cardId` | A bot proposed a routine |
| `routine.enabled` | A | `by`, `costPreview`, `nextRunAt` | The user enabled it |
| `routine.updated` | A | `changed` | |
| `routine.paused` | A | `reason`: `user` | |
| `routine.auto_paused` | A | `reason`: `away`, `failures`, `budget`, `auth` | |
| `routine.resumed` | A | `by` | |
| `routine.archived` | A | `reason`: `rejected`, `user`, `bot_archived` | |
| `routine.fired` | D | `taskId`, `scheduledFor`, `firedAt`, `triggerKind`, `late` | The routine's lane runner claimed a firing in that lane's store under its lease; the run task exists ([D83](../plan/decisions.md#d83)). The Chat runner only records the idempotent report |
| `routine.skipped` | D | `scheduledFor`, `reason`: `paused`, `bot_paused`, `missed`, `concurrency`, `budget`, `run_cap` (the runs-per-day limit, RT-12) | A firing was not run |
| `routine.webhook_rejected` | D | `path`, `reason`: `bad_signature`, `unknown_path`, `rate_limited`, `payload_too_large` | memoshid's loopback-only webhook receiver on the Mac refused a request (coalesced per path per minute; [D13](../plan/decisions.md#d13)). Accepted webhooks emit `routine.fired` with `triggerKind: webhook`. |
| `watch.proposed` | A | `watchId`, `kind`, `spec` (summary), `intervalSec`, `cardId` | A bot proposed a watch |
| `watch.activated` | A | `by` | Approved, or created active by the user |
| `watch.updated` | A | `changed` | |
| `watch.checked` | U | `result`: `same`, `candidate`, `error`; `hash?` | One model-free check ran |
| `watch.changed` | D | `baselineHash`, `newHash`, `taskId` | A change was confirmed; a run started |
| `watch.failed` | D | `error`, `consecutiveErrors` | A check failed (not counted as a change) |
| `watch.paused` | A | `reason` | |
| `watch.auto_paused` | A | `reason` | |
| `watch.resumed` | A | `by` | |
| `watch.deleted` | A | `by` | Deleted, or its proposal rejected |
| `wake.scheduled` | D | `wakeId`, `at?`, `rrule?`, `tz?`, `notePreview`, `createdByTaskId`, `chainDepth` | A bot scheduled a wake |
| `wake.fired` | D | `taskId`, `fireCount` | It fired and started a run |
| `wake.canceled` | D | `by` | |

Runs are tasks: their lifecycle is the `task.*` family with `origin.kind` `routine`, `wake`, `watch`, `webhook` or `connector_event` and `scope.taskId` ([object-model.md §5.5](object-model.md#55-routine-run)). There is no `run.*` domain.

From Phase 2 a Goal's runs are tasks too, with `origin.kind` `goal` (§5.21, [D109](../plan/decisions.md#d109)), and connector events start runs on the Mac (RT-14, [D112](../plan/decisions.md#d112); §5.15).

### 5.12 Handoff and group

Handoff types ship in Phase 1, bot-to-bot messages included (GR-06). Group types arrive with Groups in Phase 2: [D109](../plan/decisions.md#d109) moved them from v1.1 with [D24](../plan/decisions.md#d24)'s rules unchanged (GR-01–03, GR-05, GR-07, GR-09–11). Shared rooms with other people (GR-12) stay in v1.1 and add no type here.

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `handoff.created` | A | `handoffId`, `from`, `toBotId`, `goal`, `deadline?`, `hop`, `parentHandoffId?`, `groupId?`, `taskId`, `laneId?` (the receiving bot's lane, [D74](../plan/decisions.md#d74)) | A delegation was recorded |
| `handoff.status_changed` | A | `status`, `previous`, `by`, `note?` | Any handoff transition ([object-model.md §5.8](object-model.md#58-handoff)) |
| `handoff.evidence_added` | D | `evidence` (`kind`, reference) | |
| `group.created` | A | `name`, `leadBotId`, `memberBotIds`, `projectId?` | |
| `group.updated` | D | `changed`: `name`, `goal`, `limits` | |
| `group.member_added` | A | `botId` | |
| `group.member_removed` | A | `botId` | |
| `group.lead_changed` | A | `leadBotId`, `previous` | |
| `group.round_started` | D | `taskId`, `round` | |
| `group.round_completed` | D | `taskId`, `round`, `spoke`, `passed` | |
| `group.passed` | U | `taskId`, `round`, `botId` | A member passed silently (shown only in Developer views) |
| `group.limit_reached` | D | `taskId`, `limit`: `rounds`, `hops`; `value` | The loop guard stopped the exchange ([D24](../plan/decisions.md#d24)) |
| `group.read` | D | `lastReadMessageId` | |
| `group.paused` | D | | |
| `group.archived` | D | | |

**Bot-to-bot messages** (Phase 1, GR-06, [D109](../plan/decisions.md#d109)). A bot's message to another bot is a Handoff ([object-model.md §4.8](object-model.md#48-handoff-hnd_)), so it adds no type. It emits `handoff.created` with `from.kind = bot` and its `hop`, then `handoff.status_changed` and `handoff.evidence_added`, and its result joins the issuing conversation as a `message.created`. The sender's call is a `policy.decided` with `opClass: bot.handoff`, and the receiving run's tasks have `origin.kind` `bot`. Without the `bot_messaging` Grant the call asks through `grant.requested` when attended and is denied otherwise; the 9th hop without a user message is a `policy.decided` denial with `origin.hop_cap` ([policy.md §5.1](policy.md#51-origins-and-regimes)). `group.limit_reached` needs a Group, so it starts in Phase 2 [INFERENCE: whether the hop cap outside a Group gets an event of its own is set in Phase 1 with GR-06, [05 §7.6](../plan/05-bots-and-assistant.md#76-bot-to-bot-messaging-rules)].

### 5.13 Computer, browser and takeover

Names agreed with [06-computers-and-browsers.md](../plan/06-computers-and-browsers.md). The VM types (`computer.snapshot_created`, `computer.snapshot_restored`, `computer.image_updated`, `computer.resource_pressure`) arrive with Bot computers at the end of Phase 2 ([D113](../plan/decisions.md#d113), which moved them from v1.1; CMP-06–12, CMP-15–20). The Cloud computer types follow in Phase 2, after the local ones (V2-02), and the live-view frames for another device in Phase 3 (BRW-15).

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `computer.created` | A | `computerId`, `botId`, `deviceId`, `kind`, `resources?` | |
| `computer.updated` | A | `changed`: `resources`, `sharedWithBotIds`, `name` | Sharing changes are security-relevant |
| `computer.state_changed` | D | `state`, `previous`, `stateReason?` | Any lifecycle transition ([object-model.md §5.6](object-model.md#56-computer)) |
| `computer.snapshot_created` | D | `snapshotId`, `reason`, `sizeBytes` | |
| `computer.snapshot_restored` | A | `snapshotId` | |
| `computer.image_updated` | A | `channel`, `version`, `digest` | |
| `computer.resource_pressure` | D | `awakeCount`, `awakeCap`, `memoryPressure`, `kind?`: `memory`, `battery`, `disk`, `ssd_writes`; `action?`: `slept`, `stopped`, `deferred_wake`, `refused_create` | The awake-VM cap, RAM, battery, disk or SSD-write budget forced a decision |
| `computer.removed` | A | | |
| `computer.cloud_started` | A | `computerId`, `provider`, `providerRef`, `costPreview` (`microUsdPerHour`, `basis`), `toolCallId?`, `approvalId?`, `by` | Phase 2, after Bot computers: a Cloud computer started at its provider, after its `computer.cloud_start` decision. `costPreview` is the estimate that was shown first, on the approval card where the mode asks and otherwise as a notice ([D113](../plan/decisions.md#d113), [D121](../plan/decisions.md#d121), [policy.md §3.1](policy.md#31-operation-classes)). `computer.state_changed` still reports the state [INFERENCE: names set in Phase 2] |
| `computer.cloud_stopped` | A | `computerId`, `provider`, `action`: `paused`, `stopped`; `reason`: `user`, `bot`, `idle`, `budget`, `error`; `awakeMs`, `spentMicroUsd`, `costKnown` | Phase 2: a Cloud computer was paused or stopped at its provider, so it stops charging; `budget` is a budget stop ([policy.md §12](policy.md#12-budgets), B12) [INFERENCE: names and values set in Phase 2] |
| `browser.created` | D | `browserId`, `botId`, `deviceId?`, `engine`, `computerId?` | |
| `browser.state_changed` | D | `state`, `previous` | |
| `browser.navigated` | U | `url` (no query or fragment), `title` | Live view and activity ticker |
| `browser.frame` | U | `watchId`, `browserId`, `seq` (the frame's own counter), `width`, `height`, `image` | Phase 3 (BRW-15, [D83](../plan/decisions.md#d83), [D113](../plan/decisions.md#d113)): one compressed frame of a bot's browser on another device, sent only to the connection that opened the watch and never stored ([protocol.md §12.13](protocol.md#1213-browser-live-view-across-devices)) [INFERENCE: shape] |
| `computer.frame` | U | `watchId`, `computerId`, `seq`, `width`, `height`, `image` | Phase 3: the same for the desktop of a Bot computer or a Cloud computer [INFERENCE: name and shape set in Phase 3; how the desktop stream reaches another device is [06 open question 21](../plan/06-computers-and-browsers.md#13-open-questions)] |
| `browser.download_completed` | D | `fileName`, `sizeBytes`, `sha256` | |
| `browser.signin_completed` | A | `site`, `secretRef` | A sign-in card filled credentials host-side |
| `browser.data_cleared` | A | `by`, `scope` | Cookies and site data cleared; cleared cookies are cleared on every device, since they sync [INFERENCE] |
| `browser.cookies_synced` | D | `browserId`, `fromDeviceId`, `added`, `changed`, `removed`, `hosts` (registrable domains, never values) | This device applied a batch of the bot's cookie changes from another device, coalesced per profile per minute ([D75](../plan/decisions.md#d75)) [INFERENCE: names in Phase 2] |
| `takeover.requested` | D | `surface`: `browser`, `computer`; `reason`, `cardId` | A bot asked the user to take over |
| `takeover.started` | A | `surface`, `browserId?`, `computerId?`, `by` | `control` became `user` ([D19](../plan/decisions.md#d19)) |
| `takeover.ended` | A | `surface`, `noteProvided`, `durationMs` | Hand back (the note itself reaches the task as the hand-back input) |

**Takeover from another device, and input** ([D113](../plan/decisions.md#d113)). A Bot computer's desktop takeover, at the end of Phase 2, is the existing `takeover.*` with `surface: computer`. From Phase 3 `takeover.started` also carries `controlDeviceId?`: the device the user took control from when it is not the host, an iPhone or iPad included (`Computer.controlDeviceId`, `Browser.controlDeviceId`) [INFERENCE: name]; the type and its other fields are unchanged. Input has two classes:

- **A bot's GUI input** inside a Bot computer or a Cloud computer (`computer_click`, `computer_type`, `computer_key`, `computer_scroll`; class `computer.input`, [policy.md §3.1](policy.md#31-operation-classes)) is a tool call. Each emits `policy.decided` and `tool.completed`, both audited, and no type of its own.
- **The user's own input** during a takeover is never an event. It is forwarded to the host and applied there, and neither the log nor the audit chain holds keystrokes, pointer positions or frames. `takeover.started` and `takeover.ended` bound the period ([06 §9.6](../plan/06-computers-and-browsers.md#96-audit)).

A Cloud computer's charges are usage rows (§5.14); no `computer.*` type reports money beyond the start's estimate and the stop's total.

### 5.14 Budget, usage and model

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `budget.created` | A | `budgetId`, `ownerKind`, `ownerId`, `period`, `limitTokens?`, `limitMicroUsd?` | |
| `budget.updated` | A | `changed`, `by` | Limits changed (raising is a user action) |
| `budget.warned` | A | `spentTokens`, `spentMicroUsd`, `ratio` | 80% reached, once per period ([D25](../plan/decisions.md#d25)) |
| `budget.exhausted` | A | `spentTokens`, `spentMicroUsd`, `stoppedTaskIds` | 100% reached; work stops |
| `budget.reset` | D | `periodStartedAt` | New period |
| `usage.recorded` | D | `usageId`, `provider`, `model`, `source`, `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens`, `costMicroUsd`, `costKnown`, `budgetIds` | A `usg_` row was written from Pi `pi.usage` |
| `model.status_changed` | D | `provider`, `model?`, `status`: `ok`, `rate_limited`, `auth_failed`, `unreachable`, `deprecated`; `retryAfterMs?` | Provider health changed |
| `model.provider_added` | A | `provider`, `kind`: `api_key`, `local_endpoint`, `on_device` | |
| `model.provider_removed` | A | `provider` | |
| `provider.changed` | A | `capability`, `providerId`, `change`: `configured`, `selected`, `removed`; `by` (always `user`), `deviceId` | Phase 1 for `web_search` and `x_search`, Phase 2 for the other capabilities. The user configured, selected or removed a capability's provider ([D120](../plan/decisions.md#d120), [object-model.md §4.39](object-model.md#439-provider-setting)). Never a key or a `SecretRef` value [INFERENCE: name set in Phase 1] |
| `model.fallback_started` | A | `modelRef` (the Mac-local model), `using`: `open_model`, `apple` or `cloud`; `fallbackRef?` (the model actually used) | An available allowed fallback actually served a turn because the Mac was unreachable; never emitted merely for selecting a preference or queuing a no-model message. The open phone model remains MOD-09, Drop 2. Audited, since a cloud fallback sends data off the user's devices ([D74](../plan/decisions.md#d74), [D80](../plan/decisions.md#d80), [D87](../plan/decisions.md#d87), [D88](../plan/decisions.md#d88)) [INFERENCE: names in Phase 2] |
| `model.fallback_ended` | D | `modelRef` | The Mac was reachable again, and the conversation went back to the local model |

Budget slices emit nothing of their own ([protocol.md §12.11](protocol.md#1211-budget-slices)): `budget.warned` and `budget.exhausted` are emitted by the device whose reserve or report crosses the threshold, and their spend is the budget's total across devices ([D76](../plan/decisions.md#d76)). An already admitted step waiting for the bot's local model while set to wait for the Mac emits `task.status_changed` with `waitingOn = device`. A new no-model unsent message has no task and emits no such event ([D88](../plan/decisions.md#d88), §5.4).

**Usage added by [D108](../plan/decisions.md#d108)–[D121](../plan/decisions.md#d121).** Image and video generation, a Cloud computer's charges and a cloud voice session (all Phase 2) are recorded as `usage.recorded` rows against the bot's budgets, so `budget.warned` and `budget.exhausted` cover them unchanged ([policy.md §12](policy.md#12-budgets), B11–B13) [INFERENCE: their `source` values are set in Phase 2, with [object-model.md §4.23](object-model.md#423-budget-bud_)]. Usage through Claude Code as a bot's model (Phase 1, Mac only, MOD-11) is a `usage.recorded` with `costKnown: false`: price unknown, never free ([D108](../plan/decisions.md#d108)) [INFERENCE: the route is turned on and off with `models.providers.setEnabled` ([protocol.md §5.13](protocol.md#513-connector-catalog-mail-accounts-and-providers)) and takes none of `model.provider_added`'s listed `kind` values; whether that change reuses `model.provider_added` and `model.provider_removed` with a new value or gets a type of its own is set in Phase 1]. Group budgets (`budget.created` with `ownerKind: group`) arrive with Groups in Phase 2 ([D109](../plan/decisions.md#d109)).

### 5.15 Connector and skill

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `connector.added` | A | `connectorId`, `ref`, `kind` | |
| `connector.updated` | A | `changed` | |
| `connector.status_changed` | D | `status`, `previous` | |
| `connector.authorized` | A | `accountId`, `scopes` | |
| `connector.auth_expired` | D | `accountId` | Needs re-authorization |
| `connector.revoked` | A | `accountId?`, `by` | |
| `connector.tools_changed` | A | `added`, `removed`, `reclassified`, `toolsHash` | The server's tool list changed; tools are re-classified by verb |
| `connector.event_received` | D | `event`, `routineIds` | An inbound connector event matched routine triggers |
| `connector.removed` | A | | |
| `skill.installed` | A | `skillId`, `name`, `scope`, `source`, `hasScripts` | |
| `skill.proposed` | A | `skillId`, `cardId` | A bot proposed a skill (teach-by-demonstration is v1.1) |
| `skill.updated` | A | `sha256` | |
| `skill.enabled` | A | | |
| `skill.disabled` | A | | |
| `skill.removed` | A | | |

**Stages** ([D112](../plan/decisions.md#d112), [D116](../plan/decisions.md#d116)). `connector.event_received` starts on the Mac in Phase 2 with connector event triggers (RT-14, moved from Phase 3); an arriving email that starts a run is such an event ([policy.md §5.1](policy.md#51-origins-and-regimes)). A connector added from the built-in catalog (Phase 1, CON-14) emits the existing `connector.added`, which then also carries `catalogKey?` [INFERENCE: name set in Phase 1], and its connect card resolves with `connector.authorized` ([object-model.md §4.16](object-model.md#416-connector-con_)). A mail account (Phase 1 on the Mac, Phase 3 on iPhone and iPad) is a ConnectorAccount of the built-in mail Connector: adding it is `connector.authorized` and removing it `connector.revoked` (§5.23). Composio (Phase 2, off by default, CON-19) adds no type [INFERENCE: how a connector reached through it is marked is set in Phase 2].

### 5.16 Artifact and coding

Coding types are owned by [07-coding.md](../plan/07-coding.md); names agreed there.

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `artifact.created` | D | `artifactId`, `kind`, `title`, `version` | |
| `artifact.updated` | D | `version`, `sha256` | |
| `artifact.archived` | D | | |
| `artifact.deleted` | A | | |
| `review.comment_added` | D | `commentId`, `path`, `line` | |
| `review.comments_sent` | D | `commentIds`, `taskId` | Queued line comments went out with the next message |
| `review.hunk_accepted` | A | `path`, `hunkId` | |
| `review.hunk_rejected` | A | `path`, `hunkId` | Reverts the hunk in the worktree |
| `git.worktree_created` | D | `path`, `branch`, `baseSha` | |
| `git.worktree_removed` | A | `path` | |
| `git.checkpoint_created` | D | `checkpointId`, `taskId`, `treeSha?`, `kind` (`start`, `turn` or `before_restore`), `position` (`messageId`, `cseq`) | A coding turn's checkpoint was taken ([D77](../plan/decisions.md#d77)) |
| `git.checkpoint_restored` | A | `checkpointId`, `taskId`, `scope`: `files`, `conversation` or `both`; `beforeRestoreCheckpointId`, `by` | The user restored a turn's files, its conversation or both; clients refetch the session's history after a conversation restore ([D77](../plan/decisions.md#d77)) |
| `git.committed` | A | `sha`, `branch`, `fileCount` | |
| `git.pushed` | A | `remote`, `branch`, `sha`, `draftId` | A `git_push` draft was sent |
| `git.pr_opened` | A | `url`, `number?`, `draftId` | A `pull_request` draft was sent |
| `process.started` | D | `pid`, `toolCallId?`, `commandPreview`, `purpose`: `dev_server`, `test`, `other` | |
| `process.output` | U | `pid`, `offsetUtf16`, `text` | Terminal output |
| `process.exited` | D | `pid`, `exitCode`, `signal?`, `durationMs` | |
| `process.preview_detected` | D | `url`, `port` | A dev server is listening |
| `terminal.output` | U | `terminalId`, `sessionId`, `offsetUtf16`, `text` | Output of a user terminal on a computer; sent only while the session is in focus ([protocol.md](protocol.md) `terminals.*`) |
| `terminal.exited` | D | `terminalId`, `sessionId`, `exitCode?`, `signal?` | The terminal's shell exited |
| `notebook.cell_started` | D | `notebookId`, `cellId`, `deviceId` | A notebook cell began running ([D60](../plan/decisions.md#d60)) [INFERENCE: final names in Phase 2] |
| `notebook.cell_finished` | D | `notebookId`, `cellId`, `status: ok \| error`, `durationMs`, `outputCount` | The cell's outputs are saved to the notebook file |

Team mode's attribution, the landing gate and external coding agents (Phase 2, [D110](../plan/decisions.md#d110)) are in §5.24.

### 5.17 Audit

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `audit.exported` | A | `fromSeq`, `toSeq`, `format`, `chains?` (each merged chain's `deviceId` and range, when the export merges other devices' copies, [D81](../plan/decisions.md#d81)) [INFERENCE: name] | |
| `audit.pruned` | A | `beforeSeq`, `purgedPayloads` | Retention purged payloads (hashes stay) |
| `audit.verified` | D | `ok`, `headHash`, `entries`, `chains` (each chain's `deviceId`, `ok` and `brokenAt?`: the device's own and its copies of the others', checked against their signed heads, [D82](../plan/decisions.md#d82)) [INFERENCE: name] | Verification ran over every chain the device holds |
| `audit.chain_broken` | A | `atSeq`, `deviceId` (whose chain, [D82](../plan/decisions.md#d82)) | Verification failed; on the device's own chain a new segment starts ([policy.md](policy.md)) |

### 5.18 Devices, leases, replication and side threads

Names agreed with [protocol.md §12](protocol.md#12-device-layer) ([D48](../plan/decisions.md#d48), [D49](../plan/decisions.md#d49), [D74](../plan/decisions.md#d74), [D75](../plan/decisions.md#d75)). Lease and replication events have the conversation as `subject` and its bot in `scope.botId`, since each conversation has its own lease; device and group events have the device.

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `device.paired` | A | `deviceId`, `platform`, `name`, `pairedByDeviceId` | A device finished pairing |
| `device.pairing_failed` | A | `reason`: `expired` (its 5 minutes passed or its QR screen closed, [D82](../plan/decisions.md#d82)), `reused`, `auth_failed` | A pairing attempt was refused; a QR key is never reusable |
| `device.updated` | D | `changed`: `name`, `appVersion`, `osVersion`; `updateRequired?` (the device fell more than one release behind and is now a read-only replica, [D74](../plan/decisions.md#d74)) | |
| `device.revoked` | A | `deviceId`, `by` | A paired device revoked another: it left the device group, its leases move on, its links close and its replicas are erased by withdrawing its data keys ([D75](../plan/decisions.md#d75)) |
| `device.group_epoch_changed` | A | `epoch`, `previous`, `cause`: `joined`, `recovery_join` or `revoked`; `deviceId` | The device group moved to a new epoch, ordered by the lease authority ([D75](../plan/decisions.md#d75), [D79](../plan/decisions.md#d79)) [INFERENCE: names in Phase 2] |
| `device.links_changed` | U | `deviceId`, `direct`, `relay`, `icloud` (each `up`, `down` or `off`) | A link to a device came up or went down |
| `lease.granted` | A | `runnerDeviceId`, `previousDeviceId?`, `epoch`, `authority`: `icloud`, `relay`, `direct`; `reason`: `created`, `expired`, `revoked`, `rebalanced` ([D74](../plan/decisions.md#d74)); `provisional` (a direct hand-over the authority has not confirmed, [D73](../plan/decisions.md#d73)); `expiresAt` | The conversation's lease moved to a device, at a new epoch |
| `lease.handover_started` | D | `epoch`, `toDeviceId`, `reason?` (`rebalance`: an idle conversation returns to an awake Mac) | The runner is finishing its step to hand over |
| `lease.expired` | D | `epoch`, `runnerDeviceId` | The conversation's runner stayed unreachable past `expiresAt` |
| `lease.fenced` | A | `staleEpoch`, `currentEpoch`, `fromDeviceId`, `what`: `write`, `tool_call`, `change` | A write, cross-device call or replicated change with an older epoch was rejected |
| `lease.confirmed` | A | `epoch`, `authority` | The authority confirmed a lease taken by direct hand-over; the runner may now make external effects ([D73](../plan/decisions.md#d73)) [INFERENCE: names in Phase 2] |
| `effect.intent_copied` | A | `taskId`, `toolCallId`, `to` (`device` or `relay`), `intentHash` | An external effect's intent was copied to another device or the relay before the effect ran ([D73](../plan/decisions.md#d73)) [INFERENCE: names in Phase 2] |
| `message.forwarded` | D | `messageId`, `fromDeviceId` | A message sent on a device that is not the conversation's runner reached that runner, which answers it ([D73](../plan/decisions.md#d73)) [INFERENCE: names in Phase 2] |
| `card.answer_lapsed` | D | `cardId`, `answeredOnDeviceId` | An answer queued while the runner of the card's conversation was unreachable was dropped because its card was no longer pending; the user is told ([D73](../plan/decisions.md#d73)) [INFERENCE: names in Phase 2] |
| `config.merged` | A | `subject`, `fields`, `restrictiveWon` | Concurrent edits of a configuration record from two devices merged, restrictive changes winning ([D73](../plan/decisions.md#d73)) [INFERENCE: names in Phase 2] |
| `replica.state_changed` | U | `state`: `live`, `catching_up`, `offline`, `update_required`; `appliedRseq`, `lagMs?` | This device's copy of the conversation changed state ("Syncing…", "Offline", "Update Memoshi") |
| `replica.caught_up` | D | `fromRseq`, `toRseq`, `via`: `direct`, `relay`, `icloud`; `snapshot` | This device finished catching up a conversation, from the log or a snapshot |
| `side_thread.opened` | D | `sideThreadId`, `parentConversationId`, `baseCseq` | A device that could neither reach the conversation's runner nor take its lease started a real side thread with an available allowed model; never a no-model queued input ([D88](../plan/decisions.md#d88)) |
| `side_thread.joined` | D | `sideThreadId`, `summaryMessageId`, `results` (counts by kind), `memoryCount` | The parent conversation's current confirmed runner wrote a real side thread's summary from an available allowed model, with the exact recorded effect list. No-model unsent inputs are delivered normally, never joined ([D88](../plan/decisions.md#d88)) |

Lease renewals emit nothing. Cross-device tool calls use the `tool.*` family with `deviceId` set, and a step waiting for an unreachable device emits `task.status_changed` with `waitingOn = device` ("Waiting for your Mac", [D49](../plan/decisions.md#d49)). If the wait expires, the call is never dispatched: it ends with `tool.completed` (`ok: false`, `errorCode: device_unreachable`), not a denial ([D82](../plan/decisions.md#d82)).

<a id="519-live-cards-and-mini-apps"></a>
### 5.19 Live cards and Apps

Names for the records of live cards and Apps ([D68](../plan/decisions.md#d68), [D71](../plan/decisions.md#d71), [D114](../plan/decisions.md#d114); [object-model.md §4.32](object-model.md#432-mini-app-app_)) [INFERENCE: final names in Phase 1 for the types page Apps need, in Phase 2 for the rest]. The runner of the program's conversation writes them, and other devices write the same facts when they apply replication. [D119](../plan/decisions.md#d119) makes "App" the word in prose; the `mini_app.*` type names stay.

**Release scope** ([D87](../plan/decisions.md#d87)). v1.0 publishes source and compiles it locally on each device; these publication events do not require a signed-bytecode cache. `mini_app.job_ran`, trigger `job`, widget reloads and signed-cache use arrive in Drop 1. Their contracts stay below for that release.

**Stages** ([D114](../plan/decisions.md#d114), [D115](../plan/decisions.md#d115)). The `mini_app.*` types below ship in Phase 1 on the Mac with page Apps (CH-37), cover Swift Apps on the Mac from Phase 2 (CH-22) and reach iPhone and iPad in Phase 3 (CH-23). `card.permissions_approved` ships with live cards in Phase 2 (CH-21). From Phase 1 `mini_app.created` and `mini_app.version_published` also carry `kind` (`page` or `swift`), `functions` (the names of the functions the version exports) and `places` (the kinds of place it adds to), and a page App's events carry no `engineVersion` or `kitVersion` ([object-model.md §4.32](object-model.md#432-mini-app-app_)) [INFERENCE: names set in Phase 1]. A Swift App that replaces a page App is a `mini_app.version_published` whose `kind` changed; its saved data is kept. Views, App functions, scope changes and plugin developer mode are in §5.20.

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `mini_app.created` | A | `appId`, `botId`, `name`, `version` (1), `sourceHash`, `engineVersion`, `kitVersion`, `permissions` (the compiled list of tools and hosts), `exposure` | The bot's first publish compiled |
| `mini_app.version_published` | A | `version`, `sourceHash`, `engineVersion`, `kitVersion`, `permissionsAdded?` (tools and hosts the earlier approved list lacks), `needsRunApproval` (written after untrusted content, [D72](../plan/decisions.md#d72)), `migratedKeys?` (saved fields its migration renamed or removed), `note?`, `restoredFrom?`, `exposure`, `changeRequestMessageId?` (the change request it answers; a device that has the App open switches to it, [D81](../plan/decisions.md#d81)) | A new version compiled and became current, from the bot, a restore or the program's own `mini_app` call |
| `mini_app.publish_failed` | D | `appId?`, `errorCount`, `firstCode` | A publish did not compile and stored nothing; the errors reach the bot in the tool's result |
| `mini_app.permissions_approved` | A | `appId`, `version`, `tools`, `hosts`, `runApproved?` (the first run of a version written after untrusted content), `deviceId` | The user approved a version's permission list, when the App first appeared or when a version added to it, and with it any first-run approval ([cards.md §11.11](cards.md#1111-permission-lists), [§12.2](cards.md#122-versions-and-ask-the-bot-to-change-it)) |
| `card.permissions_approved` | A | `cardId`, `tools`, `hosts`, `deviceId` | The user approved a live card's permission list |
| `mini_app.change_requested` | D | `appId`, `version`, `messageId`, `automatic?` (the runner's one automatic fix request for a version that failed, [D81](../plan/decisions.md#d81)) [INFERENCE: name] | The user's "Ask the bot to change it" input was admitted, or the runner sent the bot a failing version's automatic fix request. A no-model local unsent input emits nothing until admission ([D88](../plan/decisions.md#d88)) |
| `mini_app.data_saved` | D | `appId`, `savedDataRevision`, `keys`, `bytes`, `deviceId` | `@Saved` writes were applied; the values are not in the event |
| `mini_app.opened` | D | `appId`, `version`, `deviceId` | A device opened it (`lastRun`) |
| `mini_app.job_ran` | D | `appId`, `version`, `job`, `trigger` (`schedule` or `change`), `outcome` (a run outcome, `ok`, `error`, `interrupted`, `canceled` or `limit_reached`, or `skipped` for a trigger that started no run, [D82](../plan/decisions.md#d82)), `durationMs`, `deviceId` | From Drop 1, a background job's run ended on the runner of the App's conversation ([D87](../plan/decisions.md#d87), [cards.md §12.4](cards.md#124-background-jobs)) |
| `mini_app.run_failed` | D | `appId`, `version`, `code` (a `run.` code), `line`, `deviceId` | A program stopped after repeated failures ([cards.md §11.8](cards.md#118-the-interpreter-and-its-limits)) |
| `mini_app.updated` | D | `appId`, `changed` (field names) | Phase 1. The user changed an App's own settings: its opening preference, pinning or icon (`miniApps.update`, [protocol.md §5.12](protocol.md#512-views-app-panes-and-app-functions)) [INFERENCE: name set in Phase 1] |
| `mini_app.archived`, `mini_app.restored` | D | `by` | |
| `mini_app.deleted` | A | `by` | The user deleted it, with its versions and saved data |

A program's tool calls use the usual families: `policy.decided` and `tool.*`, with `source` and with the `app` task in `scope.taskId` ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps)); a background job's calls carry trigger `job`, and a call outside the approved list is a `policy.decided` denial with `bridge.not_approved`. A live card is a Card, so posting one emits `card.created` and no new type. Widget reloads emit nothing of their own: a device reloads an App's widgets when `mini_app.data_saved` or `mini_app.version_published` arrives ([protocol.md §5.10](protocol.md#510-live-cards-and-mini-apps)) [INFERENCE]. Switching tabs in a `tabs` block emits nothing, and the last tab each device remembers never syncs ([D81](../plan/decisions.md#d81)).

### 5.20 Views, App functions, scope and plugin developer mode

Names for what [D114](../plan/decisions.md#d114) adds to Apps ([object-model.md §4.32](object-model.md#432-mini-app-app_), [§4.37](object-model.md#437-view-viw_); [policy.md §10.7](policy.md#107-live-cards-and-mini-apps)) [INFERENCE: names set in Phase 1 for views, selection and scope, and in Phase 2 for project trust, plugins and Full access on this Mac]. Views, selection carry and the `all_bots` scope ship in Phase 1 on the Mac (CH-33–CH-36, CH-39) and reach iPhone and iPad in Phase 3 with CH-23. Project-scoped Apps (CH-43) and plugin developer mode (CH-44) are Phase 2; plugin developer mode, plugins and Full access on this Mac exist on the Mac only.

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `view.opened` | D | `viewId`, `kind`, `item` (`kind`, `id`), `title`, `openedBy`, `openedByTaskId?` | Phase 1. A View opened beside the conversation: the user opened a pane in the side panel, or a bot called `view.open`. The conversation's runner writes it; a view the user opens on another device is forwarded to the runner first |
| `view.closed` | D | `viewId`, `by` | Phase 1. `view.close` or the user closed it |
| `view.arranged` | U | `arrangement` (`viewId`, `place`, `order`, `size?`), `activeViewId?`, `byTaskId` | Phase 1. A bot's `view.arrange` asked a device to change its layout. Sent only to the device whose layout changes. Layout is device-local, so nothing is stored or replicated, and the user's own rearranging emits nothing [INFERENCE: which device, when several show the conversation, is [object-model.md open question 25](object-model.md#open-questions)] |
| `message.selection_attached` | D | `messageId`, `viewId`, `item` (`kind`, `id`), `exposure` (`untrusted`, `privateData`) | Phase 1 (CH-36). The user's selection in a view travelled with this message, once. Written in the transaction that admits the message. The selection's `summary` and `content` are part of the message's input in Pi and never in the event; `exposure` holds the labels of what was selected |
| `mini_app.scope_changed` | A | `appId`, `scope` (`kind`: `bot`, `all_bots` or `project`; `projectId?`), `previous`, `by` (always `user`), `deviceId` | Phase 1 for `all_bots` (CH-39), Phase 2 for `project` (CH-43). The user changed which bots see the App and may call its functions |
| `mini_app.trust_changed` | A | `appId`, `projectId`, `trusted`, `by`, `deviceId` | Phase 2. The user answered a project-scoped App's trust prompt, or withdrew the answer [INFERENCE: whether the answer is kept per App or is the project's own trust (`project.trust_changed`) is [object-model.md open question 22](object-model.md#open-questions)] |
| `device.developer_mode_changed` | A | `deviceId`, `developerMode`, `previous`, `by` (always `user`) | Phase 2, Mac only. The user turned plugin developer mode on or off on this Mac (`Device.developerMode`). Turning it off also disables every plugin on that Mac (`plugin.status_changed`) and turns off every Full access on this Mac switch there, each with its own `full_access.revoked` [INFERENCE] |
| `plugin.installed` | A | `pluginId`, `botId`, `deviceId`, `name`, `sourceHash`, `installApprovalId`, `createdByTaskId` | Phase 2, Mac only. A plugin (`plg_`) was built from this source in plugin developer mode, after its `plugin.install` approval. A changed source is a new `plugin.installed` with a new approval |
| `plugin.loaded` | A | `pluginId`, `sourceHash`, `installApprovalId`, `deviceId` | Phase 2. The separate helper process loaded the plugin; it never loads in memoshid or the app [INFERENCE: whether an unchanged, approved plugin loads again after a restart without a new confirmation is [policy.md §18](policy.md#18-open-questions), item 26] |
| `plugin.status_changed` | A | `pluginId`, `status`: `active`, `disabled`; `previous`, `by`: `user`, `system` (with plugin developer mode turned off) | Phase 2. The user disabled the plugin on that Mac, which ends its helper process, or enabled it again. A re-enabled plugin loads again only after the same validation as an install, and then emits `plugin.loaded` [INFERENCE: set in Phase 2] |
| `plugin.removed` | A | `pluginId`, `by` | Phase 2. The user removed it |
| `full_access.granted` | A | `subject` (`kind`: `mini_app` or `plugin`; `id`), `deviceId`, `by` (always `user`), `typedConfirmationOk` | Phase 2, Mac only. The user switched one App or plugin to Full access on this Mac, after the sheet that names the risks and a typed confirmation |
| `full_access.revoked` | A | `subject`, `deviceId`, `by`: `user`, `system`; `reason`: `user`, `developer_mode_off`, `removed` | Phase 2. The switch was turned off: by the user, with plugin developer mode, or because the App or plugin was deleted [INFERENCE: values] |

**App function calls add no type** (Phase 1, CH-34). A bot calls a function that an App exports through the App's Code Mode namespace, so the call is a nested call of §5.6: its own `policy.decided` (`opClass: app.call`) and `tool.started` and `tool.completed`, with `parentToolCallId` naming the `codemode` call it was made from. Every tool call the function makes is a further nested call under the function's call, with its own `policy.decided` and `tool.*`, whose `source` names the App, its version and the trigger `function`. A call outside the version's approved permission list is a `policy.decided` denial with `bridge.not_approved`, and one from a version written after untrusted content a denial with `bridge.version_not_approved` ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps), item 13). The function's result returns to the bot as a tool result in Pi, never in an event. The app draws the call with the App's own look (CH-40) by joining `tool.*` to that `policy.decided` through `toolCallId` [INFERENCE: the namespaced tool name, and whether the outer call also carries `source`, are set in Phase 1].

**Who writes them.** Views and `message.selection_attached` are conversation records, written by the conversation's runner with its `cseq`. `mini_app.scope_changed` and `mini_app.trust_changed` are written by the runner of the App's conversation, like the other `mini_app.*` types [INFERENCE]. `device.developer_mode_changed`, `plugin.*` and `full_access.*` are records of the Mac they concern: that Mac writes them, and they replicate read-only, so every device shows the Full access on this Mac badge.

**What emits nothing.** A layout change the user makes, App view state (the open tab or item, the scroll position, filters) and an unsent selection are device-local and emit nothing; a selection whose chip the user removed before sending leaves no trace ([object-model.md §4.37](object-model.md#437-view-viw_)). The bot's view tools are `self.state` tool calls, so each has its `policy.decided` (coalesced like other T0 allows) and its `tool.completed`; `view.list` only reads. What an App or plugin with Full access on this Mac does directly on that Mac is not a tool call and reaches no event; its calls through the tool bridge still emit `policy.decided` and `tool.*` ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps), item 17). A built-in App (Mail, Calendar, Reminders merged with Tasks, Contacts, Notes, Files with the Library) follows the same contract, so its views, function calls and scope use these types; the user's own actions in a built-in pane are not tool calls (§5.23).

### 5.21 Goals

Phase 2 on the Mac (GR-13); a Goal's surfaces reach iPhone and iPad in Phase 3 (IOS-07) ([D109](../plan/decisions.md#d109); [object-model.md §4.36](object-model.md#436-goal-gol_); [05 §6.9](../plan/05-bots-and-assistant.md#69-goals-phase-2)) [INFERENCE: names and values set in Phase 2, with the points [object-model.md open question 24](object-model.md#open-questions) leaves open].

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `goal.created` | A | `goalId`, `botId`, `createdBy`, `criteriaCount`, `projectId?`, `budgetId?`, `laneId?` | A Goal was set. The outcome and the criteria text stay in the record |
| `goal.updated` | A | `changed` (field names), `by` | Its outcome, criteria or budget link changed |
| `goal.status_changed` | A | `status`: `active`, `paused`, `achieved`, `stopped`, `archived`; `previous`, `by`, `reason?`: `user`, `criteria_met`, `budget`, `limit`, `bot_archived` | Any Goal transition ([object-model.md §5.9](object-model.md#59-other-lifecycles)). A pause or a stop beats a concurrent resume |
| `goal.run_started` | D | `taskId` | A run toward the Goal started, in the Goal's lane or in a Session for project work; the run task exists |
| `goal.criterion_changed` | D | `index`, `met`, `evidence?` (`kind`, reference), `taskId` | A run marked a criterion met, or no longer met |
| `goal.decision_recorded` | D | `seq` (the entry's place in the Goal's log), `taskId`, `refCount`, `decision`†, `reason`† | A run appended an entry to the Goal's decision log (GoalDecision). The entry's text is in the record; the event carries it only on the live frame |

A Goal's runs are tasks: `task.*` with `origin.kind` `goal`, `scope.taskId` and the `unattended` regime ([D121](../plan/decisions.md#d121)). Every call they make is a `policy.decided` like any unattended run's, and a budget stop ends a run with outcome `budget_stopped`. The decision log is the Goal's own record of what the bot decided on the way; it is not the audit chain, which still records every policy decision. The Goal record is bot-wide, so `goal.created`, `goal.updated` and `goal.status_changed` are written by the device that made the change and merge elsewhere. `goal.run_started`, `goal.criterion_changed` and `goal.decision_recorded` are conversation records of the Goal's lane or Session, written by its runner with its `cseq` [INFERENCE]. Who may propose a Goal, and which card carries the proposal, are open; no proposal type is defined until they are settled.

### 5.22 Voice

Phase 2 on the Mac (V2-09, VO-01–VO-04); Phase 3 on iPhone and iPad (VO-05, VO-06) ([D111](../plan/decisions.md#d111), [D120](../plan/decisions.md#d120); [object-model.md §4.38](object-model.md#438-voice-call-vcl_); [02 §10.13](../plan/02-experience.md#1013-voice)) [INFERENCE: names and values set in Phase 2].

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `voice.call_started` | A | `voiceCallId`, `botId`, `deviceId` (the device the user spoke on), `engine`: `cloud`, `on_device`; `provider?`, `grantId?` (`cloud`: the bot's cloud-voice grant) | A voice call began. With `engine: cloud` audio leaves the device for the length of the call, which is why the type is audited |
| `voice.turn_handed_over` | D | `voiceCallId`, `messageId`, `taskId` | What the user said was admitted to the bot's normal queue as the user's message. `message.created` and `task.*` follow as for a typed message, with origin `user` |
| `voice.transcript` | U | `voiceCallId`, `segmentId`, `speaker`: `user`, `bot`; `offsetUtf16`, `text`, `final` | A piece of the running transcript, for the call's live caption. Sent only to clients that focus the conversation |
| `voice.call_ended` | A | `voiceCallId`, `status`: `ended`, `failed`; `durationMs`, `transcriptMessageId?`, `cardId?`, `taskIds`, `error?` (`code`, `message`) | The call ended or failed. The transcript was written once, as an entry in the conversation's Pi store, and the call's card was placed (`card.created` with `kind: voice_call`, the 22nd card kind, [cards.md §8.3](cards.md#83-the-call-card)) [INFERENCE: kind set in Phase 2] |
| `voice.memo_created` | D | `messageId`, `botId`, `durationMs` | A bot's voice memo was placed in the conversation (VO-02) [INFERENCE: how a memo's audio is stored is set in Phase 2, [object-model.md §4.38](object-model.md#438-voice-call-vcl_)] |
| `voice.speech_sent` | A | `purpose`: `read_aloud`, `memo`, `narrator`; `provider`, `messageId?`, `characters` | Text was sent to the cloud voice provider to be spoken outside a call. Never emitted for the on-device engine, where nothing leaves the device [INFERENCE: which of these may use the cloud engine is [policy.md §18](policy.md#18-open-questions), item 22] |

Rules:

1. **No audio, and no speech text on disk.** No event, audit row or Voice call record holds audio, and no persisted event holds transcript text ([D7](../plan/decisions.md#d7)). `voice.transcript` is UI-only: never stored, never replayed, and sent to another device only over direct and relay links, never through iCloud (§2).
2. **One transcript, in Pi.** The call's transcript is stored once, in the conversation's Pi store, at `transcriptMessageId`. It is kept and purged with its conversation (§9), and a client that joins late reads it through the history RPC.
3. **The call is not the work.** A voice session only listens and speaks. Everything the bot does for a call runs from the task of `voice.turn_handed_over`, under the normal `policy.decided`, `tool.*`, `card.*` and `budget.*` families. A spoken answer is not a card answer, so a call resolves no card ([policy.md §5.1](policy.md#51-origins-and-regimes)).
4. **Cloud voice is granted per bot.** Giving and withdrawing the cloud-voice grant are `grant.granted` and `grant.revoked`. A cloud session's charges are `usage.recorded` rows (§5.14) [INFERENCE: whether starting a cloud call also writes a `policy.decided` with `opClass: voice.cloud` is [policy.md §18](policy.md#18-open-questions), item 22].
5. **What emits nothing.** Reading a reply aloud, playing a voice memo and the spoken narrator on the on-device engine; the read-back before a voice bot commits an answer, which is speech inside the call; and, on iPhone in Phase 3, the Action Button, the Live Activity and the Start Voice Chat intent, which only start or show a call. Turning the narrator on or off is a `system.settings_changed`. A voice bot opens views with the view tools of §5.20.
6. **Who writes them.** The Voice call and its durable events are conversation records: the conversation's runner writes them from what the calling device reports, with its `cseq` ([object-model.md §4.38](object-model.md#438-voice-call-vcl_)) [INFERENCE]. A second call while one is active is refused and emits nothing.

### 5.23 Search, media and mail

The built-in tools of [D112](../plan/decisions.md#d112) and [D116](../plan/decisions.md#d116) are typed tools, so their activity is recorded where every tool call's is: `policy.decided` before the call, and `tool.started`, `tool.output` and `tool.completed` around it (§5.6, §5.7). Only mail tidying adds types, because every `mail.organize` change is audited with what is needed to undo it ([D118](../plan/decisions.md#d118), [policy.md §14.2](policy.md#142-what-is-audited)).

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `mail.organized` | A | `toolCallId`, `accountId`, `op`: `archive`, `unarchive`, `mark_read`, `mark_unread`, `label`, `unlabel`, `move`, `star`, `unstar`; `count`, `messageRefs` (the provider's message IDs), `undo` (per message, what it had before: folder, labels, flags), `grantId?` (the standing rule's Grant, as on the call's `policy.decided`) | Phase 1 on the Mac, Phase 3 on iPhone and iPad (CON-08, CON-20, SEC-28). A `mail.organize` call changed messages in one mailbox. Written with the call's `tool.completed` |
| `mail.organize_undone` | A | `accountId`, `auditIds` (the `mail.organized` entries undone), `count`, `by` | Phase 1. One or more of those changes were undone (`connectors.accounts.undoChanges`, [protocol.md §5.13](protocol.md#513-connector-catalog-mail-accounts-and-providers)) |

[INFERENCE: the names, the `op` values and the form of `undo` are set in Phase 1; how a change is undone, and for how long, is [policy.md §18](policy.md#18-open-questions), item 28.] The payloads never hold a subject, a sender, a recipient or body text.

| Fact | Recorded as |
|---|---|
| `web_search`, `x_search` (Phase 1; CON-15, CON-16) | `policy.decided` (`opClass: search.web`) and `tool.*`. The query is covered by `argsHash` and shown only in the redacted `argsPreview`; results and their source links are the tool result in Pi, and later decisions carry `exposure.untrusted` |
| Image and video generation (Phase 2; CON-17, CON-18) | `policy.decided` (`opClass: media.generate`) and `tool.*`; the cost is a `usage.recorded` row (§5.14) [INFERENCE: whether the result is also an Artifact, with `artifact.created`, is set in Phase 2] |
| `mail.list`, `mail.thread`, `mail.search` | `policy.decided` (`opClass: mail.read`) and `tool.*`; later decisions carry `exposure.untrusted` and `exposure.privateData` |
| `mail.draft` | `policy.decided` (`opClass: mail.stage`) and `tool.*`; nothing is sent |
| `mail.archive`, `mail.label`, and the mark read or unread, move and star operations | `policy.decided` (`opClass: mail.organize`), `tool.*` and `mail.organized` |
| A `mail.organize` standing rule created | `approval.resolved` with `scope: always`, then `grant.granted` for the `tool_rule` Grant, with `sourceApprovalId` and an `expiresAt` at most 90 days away; or `grant.granted` alone when the user sets the rule from a blocked item or the bot's Inspector |
| The rule used | A `policy.decided` with `decision: allow`, `ruleId: rule.allow` and the rule's Grant in `grantId`; `mail.organized` repeats that `grantId` |
| The rule expired or revoked | `grant.expired`, `grant.revoked` |
| `mail.organize` in a run started by outside content, with no rule the user set for that trigger | A `policy.decided` denial (`ruleId: rule.none_unattended`), and the blocked item's `card.created` |
| `mail.send` (send, reply, forward) | `policy.decided` (`opClass: mail.send`, a draft) and the `draft.*` family (§5.8) |
| Send mail by itself turned on or off | `bot.mail_send_by_itself_changed` (§5.2) |
| Send mail by itself used | A `policy.decided` with `decision: draft`, `autoSend: true` and `ruleId: mail.send_by_itself`; then `draft.created` and `draft.send_started` with `autoSend: true`; then `draft.sent` or `draft.failed` |
| Deleting a message, unsubscribing, changing filters or forwarding | `policy.decided` (`opClass: mail.destroy`), `approval.*` with typed confirmation, and `tool.completed` |
| A mail account added or removed | `connector.authorized`, `connector.revoked`; its `account` Grant: `grant.granted`, `grant.revoked` |
| An arriving email that starts a run (Phase 2 on the Mac) | `connector.event_received`, then `task.*` with `origin.kind` `connector_event` |

**The user's own actions in the Mail pane** are the user's, not a bot's: they are not tool calls, never ask, and emit no `policy.*`, `tool.*` or `mail.*` event ([D118](../plan/decisions.md#d118), [policy.md §3.1](policy.md#31-operation-classes)) [INFERENCE: whether they are recorded at all waits on the mail cache question, [object-model.md open question 21](object-model.md#open-questions)]. The same holds for the other built-in panes. MCP mail connectors keep their verb classification and their `draft.*` events; `mail.organized` belongs only to the built-in `mail.*` tools.

### 5.24 Team mode and external coding agents

Phase 2, on the Mac ([D110](../plan/decisions.md#d110); [07 §9.5](../plan/07-coding.md#95-team-mode-phase-2-optional-per-project), [§11](../plan/07-coding.md#11-external-coding-agents-phase-2-on-the-mac)) [INFERENCE: names and values set in Phase 2]. Team mode (CODE-18–CODE-20) arranges sessions, tasks and reviews that already exist, so its leads, helpers and reviewers keep the `session.*`, `task.*`, `handoff.*`, `review.*` and `git.*` types, and turning it on for a project is a `project.updated` with `changed: teamMode`. The types below add only who worked for whom, and the landing gate's run. Its surfaces reach iPhone and iPad in Phase 3 (IOS-07); the emitters stay on the Mac.

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `team.task_assigned` | D | `taskId`, `teamRole`: `helper`, `reviewer`; `leadBotId`, `sessionId` (the lead's worktree session), `handoffId?` (when the helper or reviewer is another bot) | The lead of a piece of work delegated a helper task, or a reviewer run started for it (`Task.teamRole`, [object-model.md §4.7](object-model.md#47-task-tsk_)). A reviewer's lens is the task's `title`, and the task's own life is `task.*` |
| `team.verdict_recorded` | D | `sessionId`, `reviewerTaskIds`, `verdict`, `commentCount` | The reviewers' findings were merged into one verdict for the change. A verdict is not an approval and decides nothing in policy [INFERENCE: the verdict's values are [07 open question 13](../plan/07-coding.md#open-questions)] |
| `landing.started` | A | `landingId`, `sessionId`, `branch`, `baseBranch`, `headSha`, `baseSha`, `by` | The landing gate began for a change. In Ask first and Auto it starts from the user's Merge |
| `landing.step_completed` | D | `landingId`, `step`: `merge`, `check`, `rerun`, `fast_forward`; `ok`, `check?` (the check's name in project settings, never its command line or output), `exitCode?`, `durationMs`, `attempt` | One step of the gate finished: the trial merge, a project check, the single rerun of a failed check, or the fast-forward |
| `landing.finished` | A | `landingId`, `result`: `landed`, `conflict`, `checks_failed`, `canceled`; `landedSha?`, `failedChecks?`, `attempts`, `durationMs` | The gate ended. `landed` means the base branch was fast-forwarded to exactly the commit whose checks passed; with any other result nothing landed |

The gate is code in memoshid, not a model and not a tool call, so its own steps have no `policy.decided`. The project's checks run inside the bot's computer and emit the usual `process.*` types [INFERENCE: where the gate runs them is [07 open question 13](../plan/07-coding.md#open-questions) and [policy.md §18](policy.md#18-open-questions), item 25]. Push and PR stay `draft.*`, followed by `git.pushed` and `git.pr_opened`. A run of the gate is a Task with `kind: landing` in the session whose change it lands, and `landingId` is that Task's `tsk_` ID ([object-model.md §4.7](object-model.md#47-task-tsk_), invariant 11). So `landing.*` events have that Task as `subject` and in `scope.taskId`, their `branch`, `baseBranch`, `headSha`, `baseSha`, `step`, `attempts`, `result`, `landedSha` and `failedChecks` are the fields of `Task.landing`, and `task.created` and `task.finished` report the Task's life beside them: `landed` ends it `done`, `conflict` and `checks_failed` end it `failed`, and `canceled` ends it `canceled` [INFERENCE: set in Phase 2].

**External coding agents** (R11-08–R11-10). Codex app-server, Claude Code and ACP agents work inside a session as delegated workers and add no type. Each tool call an agent makes is routed through policy and emits `policy.decided` and `tool.*` with `actor.kind = external_agent` (§2), in the session's task and with that task's origin. What an agent changed is attributed in the diff records of [07 §6.2](../plan/07-coding.md#62-diff-pipeline), not in events [INFERENCE: the form of `actor.id` for an agent, and whether an agent's start and exit need more than `process.started` and `process.exited`, are set in Phase 2]. Claude Code as a bot's model (Phase 1, [D108](../plan/decisions.md#d108)) is not an external agent: the bot is the actor (§5.14).

### 5.25 Streamed cards

Phase 1 (CH-19, CH-25; [D115](../plan/decisions.md#d115)). A JSON card from the block catalog streams as the model writes it: the runtime emits partial card data, and the app validates it as it arrives ([amendment §6](../plan/AMENDMENT_2026-11-13.md#6-where-the-new-parts-run)). The partial updates are UI-only and the durable log holds only the finished card, so a replay, a resync and a device that was offline all reach the same final card.

| Type | C | Payload | Emitted when |
|---|---|---|---|
| `card.delta` | U | `cardId`, `toolCallId`, `rev`, `set?` (`catalogVersion`, `title`, `summary`, `root`), `blocks?`, `actions?` | A streaming card gained or changed blocks. Sent only to clients that focus the conversation |

Rules, agreed with [cards.md §2.1](cards.md#21-streaming) [INFERENCE: the frame's name and fields are set in Phase 1; whether its field names follow A2UI's is [amendment §8](../plan/AMENDMENT_2026-11-13.md#8-open-items), item 4]:

1. **Whole blocks only.** A frame's `blocks` and `actions` are complete entries of the card envelope ([cards.md §2](cards.md#2-envelope)), upserted by `id`. A frame never carries part of a block: the runtime holds a block back until its JSON is complete. `set` replaces the envelope fields it names. A reference to a block that has not arrived shows a placeholder until it does.
2. **Ordered by `rev`.** `rev` counts a stream's frames from 1 without gaps. A receiver applies frames in order and drops one it already has. Frames may be dropped under backpressure: on a gap the receiver stops applying that stream and waits for the finished card ([cards.md §2.1](cards.md#21-streaming)) [INFERENCE: whether the history RPC's `live` state also offers the partial card to a client that joins mid-stream is set in Phase 1].
3. **Validated twice.** The app validates each block as it arrives, against the same catalog the runner uses; a block that fails draws the plain fallback. The runner validates the whole card when the model has finished it.
4. **One durable fact.** Nothing is persisted while a card streams: no Card row, no `card.created` and no `cseq`; only the `cardId` is allocated when the stream starts. When the runner has validated the whole card, it writes the Card and one `card.created` whose `payload` is the validated card, exactly as for a card that was not streamed. That payload is the card: the receiver replaces what it assembled with it, and a late `card.delta` never changes a card that a durable event has placed.
5. **Same result either way.** Applying a stream's frames in `rev` order yields the `payload` of the durable event that ends it; the runner sends no block that it would not accept in the final card [INFERENCE]. §11 check 8 tests this.
6. **A stream that ends early** (an error, a Stop, a restart) writes no card. The frames stop, the call's outcome is its `tool.completed`, and the client drops the partial card. Crash recovery has nothing to reconcile, since nothing was stored. A finished card that fails validation as a whole is stored as the `error` card of [cards.md §7](cards.md#7-versions-and-the-fallback), with its own `card.created`.
7. **A bot's update of a stored JSON card** may stream the same way, against the existing `cardId`, with `rev` starting again at 1. It ends in the existing `card.updated` with the new validated `payload`; a failed update writes nothing, and the card keeps its ID and its place in the transcript ([cards.md §2.2](cards.md#22-updating-a-card-in-place)) [INFERENCE: set in Phase 1]. A newer card with `replaces` is a new card and a new stream. A live card does not stream this way: its drawing is the `program.*` frames of [protocol.md §5.10](protocol.md#510-live-cards-and-mini-apps).

### 5.26 Types added on 2026-11-13, by phase

40 types gained rows in this catalog for [D106](../plan/decisions.md#d106)–[D122](../plan/decisions.md#d122): 23 audited, 12 durable and 5 UI-only. 39 are new; `browser.frame` already existed in [protocol.md §7.4](protocol.md#74-ui-only-frames) and is listed here for the first time, restaged from Drop 2. Each ships with the feature that needs it; the phase below is the first one, on the Mac unless it says otherwise.

| Phase (gate) | Types |
|---|---|
| 1 (M1): 11 | `view.opened`, `view.closed`, `view.arranged`, `message.selection_attached`, `mini_app.scope_changed`, `mini_app.updated`, `provider.changed`, `card.delta`, `mail.organized`, `mail.organize_undone`, `bot.mail_send_by_itself_changed` |
| 2 (M2): 27 | `mini_app.trust_changed`, `device.developer_mode_changed`, `plugin.installed`, `plugin.loaded`, `plugin.status_changed`, `plugin.removed`, `full_access.granted`, `full_access.revoked`; `goal.created`, `goal.updated`, `goal.status_changed`, `goal.run_started`, `goal.criterion_changed`, `goal.decision_recorded`; `voice.call_started`, `voice.turn_handed_over`, `voice.transcript`, `voice.call_ended`, `voice.memo_created`, `voice.speech_sent`; `computer.cloud_started`, `computer.cloud_stopped`; `team.task_assigned`, `team.verdict_recorded`, `landing.started`, `landing.step_completed`, `landing.finished` |
| 3: 2 | `browser.frame`, `computer.frame`. The Phase 1 and Phase 2 types reach iPhone and iPad in Phase 3 with their features (views, selection, App scope, mail, Goals, voice), except the plugin developer mode, plugin and Full access on this Mac types, which stay Mac only, and the team-mode and landing types, whose emitters run on the Mac |

Existing types whose stage the decisions moved, with no change to their payloads:

| Types | Was | Now | Decision |
|---|---|---|---|
| `group.*` | v1.1 | Phase 2 | [D109](../plan/decisions.md#d109) |
| `handoff.*` for a bot-to-bot message | v1.1 | Phase 1 | [D109](../plan/decisions.md#d109) |
| `computer.snapshot_created`, `computer.snapshot_restored`, `computer.image_updated`, `computer.resource_pressure`; `takeover.*` with `surface: computer` | v1.1 | End of Phase 2 | [D113](../plan/decisions.md#d113) |
| `takeover.*` from an iPhone or iPad, with `browser.frame` | Drop 2 | Phase 3 | [D113](../plan/decisions.md#d113) |
| Events with `actor.kind = external_agent` | v1.1 | Phase 2, Mac only | [D110](../plan/decisions.md#d110) |
| `connector.event_received` | Phase 3 | Phase 2, on the Mac | [D112](../plan/decisions.md#d112) |
| `mini_app.*` (all but `mini_app.job_ran`, which stays Drop 1) | Phase 2 | Phase 1 with page Apps; Swift Apps in Phase 2 on the Mac and Phase 3 on iPhone and iPad | [D114](../plan/decisions.md#d114) |
| `card.created` and `card.updated` for a generated JSON card | Phase 2 | Phase 1, streamed | [D115](../plan/decisions.md#d115) |

---

## 6. Payload examples

**`approval.requested`** (the envelope is in [§2](#2-envelope); together they are the fixture `events/approval.requested@1.json`):

```json
{
  "approvalId": "apr_01JC3G5Y6Z7A8B9C0D1E2F3G4H",
  "cardId": "crd_01JC3G5Y6Z7A8B9C0D1E2F3G4J",
  "toolCallId": "call_7f3a",
  "tool": "bash",
  "tier": 2,
  "permissionMode": "ask_first",
  "attendance": "attended",
  "exposure": { "untrusted": false, "privateData": true },
  "computerKind": "mac_sandbox",
  "deviceId": "dev_01JC0D4E5F6G7H8J9K0M1N2P3Q",
  "targets": ["~/Projects/acme"],
  "argsHash": "sha256:0c4d8e2f",
  "argsPreview": { "command": "npm test" },
  "ruleId": "matrix.ask",
  "reasonCode": "exec_requires_approval",
  "policyVersion": "1",
  "expiresAt": 1792488612345,
  "confirmationRequired": false
}
```

**`message.completed`**, as persisted and as the live frame for a focused client:

```json
{ "v": 1, "seq": 48230, "cseq": 321, "ts": 1792486830002, "type": "message.completed", "typeVersion": 1, "deviceId": "dev_01JC0D4E5F6G7H8J9K0M1N2P3Q",
  "actor": { "kind": "bot", "id": "bot_01JC3F7Q9R2M8K4T6V5W0X1Y2Z" },
  "subject": { "kind": "message", "id": "msg_01JC3G6N7P8Q9R0S1T2V3W4X5Y" },
  "scope": { "botId": "bot_01JC3F7Q9R2M8K4T6V5W0X1Y2Z", "conversationId": "ses_01JC3G2A7B8C9D0E1F2G3H4J5K" },
  "payload": { "messageId": "msg_01JC3G6N7P8Q9R0S1T2V3W4X5Y", "stopReason": "stop" } }
```

```json
{ "...": "same envelope",
  "payload": { "messageId": "msg_01JC3G6N7P8Q9R0S1T2V3W4X5Y", "stopReason": "stop",
               "content": [{ "type": "text", "text": "All 214 tests pass. The flaky login test now waits for the session cookie." }] } }
```

**A quiet routine run** (three durable events; no Chat line, no card, no notification; it appears only in the routine's run history):

```json
[
  { "seq": 50101, "cseq": 902, "type": "routine.fired", "actor": { "kind": "trigger", "id": "rtn_01JC2B3C4D5E6F7G8H9J0K1M2N" },
    "subject": { "kind": "routine", "id": "rtn_01JC2B3C4D5E6F7G8H9J0K1M2N" },
    "scope": { "botId": "bot_01JC3F7Q9R2M8K4T6V5W0X1Y2Z", "conversationId": "cht_01JC1Z2Y3X4W5V6T7S8R9Q0P1N", "taskId": "tsk_01JC3H0A1B2C3D4E5F6G7H8J9K" },
    "payload": { "taskId": "tsk_01JC3H0A1B2C3D4E5F6G7H8J9K", "scheduledFor": 1792483200000, "firedAt": 1792483200410, "triggerKind": "schedule", "late": false } },
  { "seq": 50102, "cseq": 903, "type": "task.created",
    "origin": { "kind": "routine", "id": "rtn_01JC2B3C4D5E6F7G8H9J0K1M2N", "rootKind": "routine", "hops": 0 },
    "payload": { "taskId": "tsk_01JC3H0A1B2C3D4E5F6G7H8J9K", "kind": "run", "title": "Morning CI check",
                 "origin": { "kind": "routine", "id": "rtn_01JC2B3C4D5E6F7G8H9J0K1M2N", "rootKind": "routine", "hops": 0 },
                 "regime": "unattended", "routineId": "rtn_01JC2B3C4D5E6F7G8H9J0K1M2N", "scheduledFor": 1792483200000 } },
  { "seq": 50140, "cseq": 911, "type": "task.finished",
    "payload": { "taskId": "tsk_01JC3H0A1B2C3D4E5F6G7H8J9K", "status": "done", "outcome": "no_update", "summary": "CI green on main; nothing new.",
                 "usage": { "inputTokens": 5120, "outputTokens": 214, "cacheReadTokens": 4096, "cacheWriteTokens": 0, "costMicroUsd": 1830, "costKnown": true },
                 "durationMs": 21877 } }
]
```

(Envelope fields not relevant to the example are omitted. The whole `task.created` and `task.finished` events are the fixtures `events/task.created@1.json` and `events/task.finished@1.json`.)

**`bot.status_changed`:**

```json
{ "status": "asleep", "previous": "working", "takenOver": false,
  "computerState": "awake", "nextWakeAt": 1792540800000, "unreadCount": 0, "runnerDeviceIds": ["dev_01JC0D4E5F6G7H8J9K0M1N2P3Q"] }
```

**An interrupted step** whose outcome check could not tell, so the user decides on a Resume card (payloads only; tool names are illustrative):

```json
[
  { "type": "tool.interrupted", "payload": { "toolCallId": "call_9b21", "tool": "reminders_add", "replay": "unsafe", "effect": "outcome_check" } },
  { "type": "tool.outcome_checked", "payload": { "toolCallId": "call_9b21", "tool": "reminders_add", "checkTool": "reminders_find", "result": "inconclusive", "next": "resume_card" } },
  { "type": "card.created", "payload": { "cardId": "crd_01JC3J1K2M3N4P5Q6R7S8T9V0W", "kind": "resume",
    "subject": { "kind": "task", "id": "tsk_01JC3G4M5N6P7Q8R9S0T1V2W3X" }, "messageId": "msg_01JC3J2K3M4N5P6Q7R8S9T0V1W",
    "title": "Interrupted: may have happened", "inbox": true, "needsYou": true,
    "payload": { "toolCallId": "call_9b21", "tool": "reminders_add", "checkTool": "reminders_find", "result": "inconclusive" } } },
  { "type": "tool.interruption_resolved", "payload": { "toolCallId": "call_9b21", "tool": "reminders_add", "action": "run_again", "cardId": "crd_01JC3J1K2M3N4P5Q6R7S8T9V0W", "by": "user" } },
  { "type": "card.resolved", "payload": { "cardId": "crd_01JC3J1K2M3N4P5Q6R7S8T9V0W", "outcome": { "action": "run_again" }, "by": "user" } }
]
```

The `card.created`, `tool.interruption_resolved` and `card.resolved` payloads are those of the fixtures `events/card.created@1.json`, `events/tool.interruption_resolved@1.json` and `events/card.resolved@1.json`. `tool.interrupted` has a Swift payload; its fixture `events/tool.interrupted@1.json` is the form Memoshi's built step settlement emits ([protocol.md](protocol.md#current-step-settlement)): `replay: unsafe` and `effect: resume_card`, with no outcome check. That built `resume` card's payload is `{toolCallId, tool, actions}`, not the `checkTool`/`result` form above; the outcome check is not built, and `tool.outcome_checked` has no Swift payload yet.

**`system.resync_required`** (UI-only, sent to one client):

```json
{ "v": 1, "seq": null, "after": 50140, "ts": 1792486900000, "type": "system.resync_required", "typeVersion": 1, "deviceId": "dev_01JC0D4E5F6G7H8J9K0M1N2P3Q",
  "actor": { "kind": "system" }, "subject": { "kind": "system", "id": "memoshid" }, "scope": {},
  "payload": { "scope": { "conversationId": "ses_01JC3G2A7B8C9D0E1F2G3H4J5K" }, "reason": "projector_reset" } }
```

Fixture: `events/system.resync_required@1.json`.

**A streamed card** (Phase 1, §5.25; payloads only). Three UI-only frames, then the one durable event, whose `payload` is the whole validated card:

```json
[
  { "type": "card.delta", "payload": { "cardId": "crd_01JD5K2M3N4P5Q6R7S8T9V0W1X", "toolCallId": "call_41c0", "rev": 1,
    "set": { "catalogVersion": "1.0", "title": "Flights to Lisbon, 14 November", "root": "b1" },
    "blocks": [ { "id": "b1", "type": "stack", "axis": "vertical", "children": ["b2", "b3"] } ] } },
  { "type": "card.delta", "payload": { "cardId": "crd_01JD5K2M3N4P5Q6R7S8T9V0W1X", "toolCallId": "call_41c0", "rev": 2,
    "blocks": [ { "id": "b2", "type": "text", "text": "Prices checked at 09:40 on the airline sites." } ] } },
  { "type": "card.delta", "payload": { "cardId": "crd_01JD5K2M3N4P5Q6R7S8T9V0W1X", "toolCallId": "call_41c0", "rev": 3,
    "set": { "summary": "Two options under €300" },
    "blocks": [ { "id": "b3", "type": "table",
      "columns": [ { "key": "dep", "title": "Departs", "format": "time" }, { "key": "price", "title": "Price", "format": "currency", "currency": "EUR" } ],
      "rows": [ { "dep": "2026-11-14T09:10:00Z", "price": 214 }, { "dep": "2026-11-14T13:35:00Z", "price": 189 } ] } ] } },
  { "type": "card.created", "payload": { "cardId": "crd_01JD5K2M3N4P5Q6R7S8T9V0W1X", "kind": "generated",
    "messageId": "msg_01JD5K3M4N5P6Q7R8S9T0V1W2X", "title": "Flights to Lisbon, 14 November", "inbox": false, "needsYou": false,
    "payload": { "catalogVersion": "1.0", "title": "Flights to Lisbon, 14 November", "summary": "Two options under €300", "root": "b1",
                 "blocks": [ "… b1, b2 and b3 exactly as streamed …" ] } } }
]
```

**`mail.organized`** (Phase 1, §5.23): two messages archived under a standing rule.

```json
{ "toolCallId": "call_5d02", "accountId": "acc_01JD6A1B2C3D4E5F6G7H8J9K0M", "op": "archive", "count": 2,
  "messageRefs": ["18c2f0a91b7e4d55", "18c2f0b3c9a01e72"],
  "undo": [ { "ref": "18c2f0a91b7e4d55", "folder": "INBOX" }, { "ref": "18c2f0b3c9a01e72", "folder": "INBOX" } ],
  "grantId": "grt_01JD6A2B3C4D5E6F7G8H9J0K1M" }
```

`card.delta` and `mail.organized` have no Swift payloads or fixtures yet; they get them in Phase 1 (§11).

## 7. Snapshots and resync

Snapshots are **pulled, never pushed** (agreed with [protocol.md](protocol.md)). Draft 3 pushed `conversation.snapshot` and defined `taskgraph.snapshot` without ever emitting it. In Draft 4 every snapshot is the result of a list or history RPC that returns `asOf: { seq, cseq? }`:

| Snapshot | RPC (names per [protocol.md](protocol.md)) | Contents |
|---|---|---|
| Roster | `bots.list` | Bots with derived status fields |
| Inbox | `inbox.list` | Pending cards and unseen news |
| Computers and browsers | `computers.list` | States and `control` |
| Devices | `devices.list` | Paired devices and their links, the device group's epoch, each conversation's lease and this device's replica state per conversation |
| Budgets | `budgets.list` | Spend and state per budget |
| Task graph | `tasks.graph` | Live tasks of a conversation with owner edges and `waitingOn`; built from D and Pi `harness.taskGraph()` of the open store |
| Child attachment | `tasks.history` | Current implemented read-only child page: `{task, background, items: [{entryId, role, text, stopReason?}], liveText?, nextBefore?, asOf}`; required `PageLimit` and an optional opaque exclusive `before` cursor. Not a Session or second transcript |
| Conversation | `chats.history`, `sessions.history`, `groups.history` | A page of messages, cards and tool chips from Pi storage, plus `live` (in-flight message and tools) |
| Views (Phase 1) | `views.list` | A conversation's open views and this device's layout ([object-model.md §4.37](object-model.md#437-view-viw_)) [INFERENCE: name set in Phase 1] |
| Providers (Phase 1) | `providers.list` | Each capability's providers, with which is configured and selected; never credential values [INFERENCE: name set in Phase 1] |
| Goals (Phase 2) | `goals.list`, `goals.decisions` | Goals with their status and criteria; a Goal's decision log [INFERENCE: names set in Phase 2] |
| Voice calls (Phase 2) | `voiceCalls.list` | Calls with their status, length and card; the transcript comes from the conversation's history RPC [INFERENCE: name set in Phase 2] |
| Plugins and Full access on this Mac (Phase 2, Mac only) | `plugins.list`, `fullAccess.list` | Plugins built in plugin developer mode, and the Apps and plugins switched to Full access on this Mac [INFERENCE: names set in Phase 2] |

Client algorithm:

1. Call `events.subscribe { after: lastSeq }`. With `mode: "replay"`, apply events from `after + 1` to `head`.
2. With `mode: "resync"` (cursor older than retention, or first launch), call the list RPCs, keep each result's `asOf.seq`, and apply only later events to it.
3. On `system.resync_required`, refetch only the named scope (one conversation or everything).
4. Opening a conversation calls its history RPC; afterwards, durable events with `cseq > asOf.cseq` and UI-only frames for that conversation apply. A card that is still streaming is not in the history yet: a client that joins mid-stream or misses a `card.delta` shows the card when its `card.created` arrives (§5.25).

Resync triggers: the cursor is older than the oldest retained event; a `seq` or `cseq` gap; a projector reset (a Pi watch overflowed or a store reopened, [§8](#8-pi-projection)); a protocol change. These snapshots come from the device's own engine; devices catch up with each other through the replication stream ([protocol.md §12.7](protocol.md#127-replication-and-catch-up)).

## 8. Pi projection

Transcript and task changes happen in Pi first. The engine's runtime adapter projects them into Memoshi records and events. Pi storage is one file per thread ([object-model.md §6](object-model.md#6-pi-mapping)); the adapter subscribes to commits of each open store and to its conversation views.

The mapping and crash-reconciliation paragraph in this section describe the **accepted target**, including feed/replication and nested-result settlement work that Memoshi does not use yet at its `slice-2` pin ([D134](../plan/decisions.md#d134)); interrupted-step settlement (Run again, Skip, Mark as done, [D138](../plan/decisions.md#d138)) is in use since `71111a6`. The current implementation uses bounded immutable-entry/task scans, commit capture and app receipts; it does not claim an SDK replayable feed or a recoverable result where Pi has retired the only authoritative copy.

| Pi change (names from pi-durable 1.3.0; re-checked on Pi_Swift, [D44](../plan/decisions.md#d44)) | Memoshi effect |
|---|---|
| `pi.user` entry placed | `msg_` row; `message.created` (unless the submit path already wrote it) |
| Submission queued in `pi.inbox` | `message.queued` |
| New generation partial in `pi.live` | `msg_` row allocated with no entry yet; `message.created` (bot); then `message.delta` frames |
| `pi.assistant` entry committed | `msg_` row linked to the entry; `message.completed` |
| Generation failed | `message.failed` |
| `pi.tool` task created | (after `policy.decided` in `beforeTool`) `tool.started` |
| Tool output in `pi.live` | `tool.output` |
| Partial arguments of a card-tool call in `pi.live` (Phase 1, [D115](../plan/decisions.md#d115)) | `card.delta` frames, one per completed block; the committed call writes the Card and `card.created` (§5.25) [INFERENCE: set in Phase 1] |
| `pi.tool-result` entry | `tool.completed` |
| Nested call (with `parentToolCallId`) | Same, with the parent set |
| `pi.compaction` entry, `pi.reset` | `*.compacted`, `*.context_reset` |
| Task state of a Memoshi task kind | `task.*` |
| `pi.usage` delta | `usg_` row, `usage.recorded`, budget checks |
| Custom `memoshi.*` entries | Written by the engine itself; projected only into the `msg_` index |
| Interrupted step reported by recovery (Pi_Swift requirements E2) | `tool.interrupted`, then `tool.outcome_checked` or a `resume` card ([D51](../plan/decisions.md#d51)). Exception in the current code: a replay-unsafe step Memoshi settles itself as never dispatched (no dispatch record, no projected result) gets no `tool.interrupted`, since none of `rerun`, `outcome_check` and `resume_card` is true for it; it ends with its `tool.completed` (`ok: false`, `errorCode: interrupted`) ([protocol.md](protocol.md#current-step-settlement), [`RuntimeInterruptedDispatchTests`](../../Packages/MemoshiCore/Tests/MemoshiRuntimeTests/RuntimeInterruptedDispatchTests.swift)). Adding an `effect` value such as `not_dispatched` awaits the owner's decision ([HANDOFF, proposed decisions](../HANDOFF.md#proposed-decisions-2026-11-18)) |
| Replicated change applied to a replica store | The same `msg_` rows and events as on the runner, with the runner's `deviceId` and `cseq` ([D49](../plan/decisions.md#d49)) |


<a id="current-nested-result-retirement"></a>
**Current nested-retirement limitation (H1/E20, 2026-11-03):** at Pi candidate `892585fc`, the pin until [D134](../plan/decisions.md#d134), a completed nested `pi.tool`'s terminal result is only `{kind: "nested"}`. `slice-2` also keeps a completed nested result that does not retire with its caller (`Harness.completedNestedCalls`), but Memoshi does not read it yet, so what follows still holds. Its complete `NestedCallState.result` is a document scoped to the parent task and retired with that owner. [`PolicyToolAudit`](../../Packages/MemoshiCore/Sources/Runtime/PolicyToolAudit.swift) captures content-free final metadata synchronously while a live commit still has it, then persists an authoritative Memoshi receipt before publishing completion. A crash after the SDK retires the document but before that app receipt is stored can leave no result to reconcile on reopen. The adapter fails closed with `projectionFailed` (`storage_failed` through the shared typed error mapper); it does not infer success from parent settlement, synthesize `tool.completed` or blindly repeat an effect.

This is the [consumer observation under existing H1/E20](../research/spikes/2026-11-02-pi-swift-consumer-handoff.md#24-consumer-observation-nested-result-retirement-2026-11-03), not a new H-number request; H4 remains Code Mode. [`SubagentKillResumeTests`](../../Packages/MemoshiCore/Tests/MemoshiRuntimeTests/SubagentKillResumeTests.swift) really SIGKILL foreground/background child hosts after an immutable **model-tool** checkpoint and verify original ownership, one completion and one effect. Their [retained results](../../../evidence/2026-11-03-memoshi-wave3-integration/native/runtime-child-conversation-tests.txt) do not cut the nested-result-retirement window. P0-15's chaos matrix still lacks nested Code Mode/child-retirement/compaction kill points, and full all-call policy/audit and recovery acceptance remains open. No SDK source/pin or accepted recovery rule is changed by this observation.

**Crash reconciliation** ([D82](../plan/decisions.md#d82)). Pi offers no API to read commits since a given `Seq` ([04-architecture.md](../plan/04-architecture.md)), and "a client that joins late or reconnects starts from the current view; nothing is replayed" (pi-durable README, Watching a Conversation). Pi_Swift adds a change feed, a [D49](../plan/decisions.md#d49) engine requirement. The projector consumes it from a cursor per store, which it saves in D in the same transaction as the records and events it projects, so after a crash it resumes from that cursor and nothing is missed or projected twice. The entry scan is the fallback, for a store whose feed no longer reaches back to its cursor: on boot, for each thread with live work, the projector reads entries after the conversation's last linked `msg_` row. Either way it emits the missing `message.completed` and `tool.completed` events with `payload.reconciled = true`. Deltas lost in the crash are not replayed (they are UI-only). Tasks that a restart interrupted get `task.interrupted`: those with `resumeMode = auto` continue on their own, and those with `resumeMode = explicit` have their interrupted step checked (`tool.outcome_checked`) or held behind a Resume card ([D42](../plan/decisions.md#d42), [D51](../plan/decisions.md#d51)). Drafts found in `sending` become `failed` with `uncertain = true`. Then `system.recovered` summarizes. A slow Pi watch "keeps at most 100 undelivered frames" before collapsing them into one full view; the projector treats that as a projector reset and sends `system.resync_required` for that conversation. Pi commit `Seq` values are stored for diagnostics only.

## 9. Retention and pruning

| Data | Default retention | Pruning |
|---|---|---|
| `events` (classes A and D) | 30 days (Developer setting: 7–365), and at least the latest 200,000 rows, whichever keeps more ([04 §6.5](../plan/04-architecture.md#65-retention-and-pruning)) | Hourly job, batches of 5,000 rows, oldest first; never the newest row; writes `system.pruned` |
| `audit_log` | 1 year, configurable ([policy.md](policy.md)) | Payloads purged, hashes kept; writes `audit.pruned` |
| UI-only frames | Never stored | — |
| Voice-call transcripts (Phase 2) | With their conversation, like any transcript: stored once, in its Pi store | Purged with the conversation. No audio is ever stored ([object-model.md §4.38](object-model.md#438-voice-call-vcl_)) |
| Goal decision log (Phase 2) | With its Goal [INFERENCE] | `goal.decision_recorded` events prune like any D event; the log's rows do not |
| `mail.organized` undo data (Phase 1) | In the event and its audit row | It is purged with the audit payload at the latest; the undo window itself is not set ([policy.md §18](policy.md#18-open-questions), item 28) [INFERENCE] |
| `usage_records` | 400 days: a year of comparisons, plus slack | Monthly roll-ups kept |
| Transcripts | Until the conversation is purged from Trash (30 days after deletion, or Empty Trash) | Delete its Pi store file on every device ([D74](../plan/decisions.md#d74)) |
| Cards, approvals, drafts | With their conversation | Removed when the conversation is purged; audit rows remain |

Rules:

- `seq` values are never reused (`AUTOINCREMENT`), so pruning never breaks ordering.
- A client whose cursor is older than the oldest retained `seq` gets `mode: "resync"`.
- Memory provenance (`eventSeq`) may point at a pruned event; the memory row keeps `conversationId`, `messageId` and `taskId`, and audited memory events stay in `audit_log` for a year.
- Backups (`VACUUM INTO`) and their retention are in [04-architecture.md](../plan/04-architecture.md).

## 10. Compatibility and versioning

1. **Envelope.** `v = 1`. A new envelope means `v = 2`, negotiated in the handshake ([protocol.md](protocol.md)).
2. **Additive changes only within a protocol version:** new types, new optional fields, new enum values. They do not bump `typeVersion`.
3. **Breaking changes** (removing or renaming a field, changing its meaning or type) bump the type's `typeVersion`. The engine emits the new version only to clients whose handshake declares support; older clients receive the previous version during one minor release, then get a repair action.
4. **Types are never renamed.** A replaced type is marked deprecated in this catalog and removed only with a protocol major version.
5. **Unknown input and receipts.** Clients ignore unknown fields and decode unknown enum values to `unknown(raw)`. Unknown event types/versions are surfaced in Developer diagnostics and delivered as opaque events, never silently dropped; their durable cursor advances only after the consumer explicitly acknowledges its handling, not when decoding or enqueueing succeeds ([protocol §8](protocol.md#8-replay-and-snapshots)). If a decode failure hides required state, request a resync for that scope. The Draft 3 client silently dropped undecodable events ([Draft 3 build audit](../research/agentic-workspace-landscape/landscape/in-house-assets.md#draft-3-build)). In the Swift types, an unknown `type`, an unreadable `typeVersion` and a known type whose payload fails to decode all become `.unknown(type, typeVersion, raw)`, retaining the raw payload through re-encoding, up to number normalization: `1.0` may return as `1`, and an integer beyond 64 bits loses precision ([protocol §3.5](protocol.md#35-versioning-and-capabilities)). Each is reported once to the decoder's diagnostics sink with its reason (`unknown_event_type`, `unsupported_event_version` or `undecodable_event_payload`), type, `seq`, conversation and place in the frame. A frame breaking §2's class rules is kept/reported as `inconsistent_event_class`; a value outside §4's field limits in the protocol is kept/reported as `constraint_violated` with the limited type's name. The engine decodes strictly and rejects these inputs ([protocol §3.5](protocol.md#35-versioning-and-capabilities)) [INFERENCE: Phase 0 implementation choice, 2026-10-23; receipt contract implemented 2026-10-25].
6. **Persisted versions.** Stored rows keep their `typeVersion`. Clients decode every version still within retention.
7. **Enums are closed in the engine, open in clients.** The engine decodes every input strictly, so it rejects an enum value it does not know, and it builds every payload it writes through the Swift types, which are the source of truth: their initializers enforce the field limits, and the engine sets their enums only to known values ([D78](../plan/decisions.md#d78), [protocol.md §14](protocol.md#14-schema-codegen-and-fixtures)). Nothing validates payloads against the JSON Schema at run time. The schema is generated from the Swift types; it checks the fixtures in CI and documents the wire [INFERENCE: Phase 0 implementation choice, 2026-10-23].
8. **Additions of 2026-11-13.** Everything this spec gained for [D106](../plan/decisions.md#d106)–[D122](../plan/decisions.md#d122) is additive under rule 2: new types (§5.26); new optional fields on types that have no Swift payload yet (`takeover.started`'s `controlDeviceId`, `connector.added`'s `catalogKey`, and the `kind`, `functions` and `places` of `mini_app.created` and `mini_app.version_published`); one optional field on a Phase 0 type (`policy.decided`'s `grantId`); and new values of fields whose values no row lists (`policy.decided`'s `opClass`, `ruleId` and `source.trigger`). No `typeVersion` changes and no type is renamed or removed. A client built before a type's phase receives it as an opaque event under rule 5.

## 11. Contract fixtures and tests

Adapted from Draft 3's fixture layout:

```
protocol/fixtures/events/
  approval.requested@1.json
  message.completed@1.json          # persisted form
  message.completed@1.live.json     # live form with † fields
  task.finished@1.json
  ...
```

CI checks:

1. Every catalog type has at least one fixture per `typeVersion`; every fixture validates against the JSON Schema.
2. Swift decodes every fixture and re-encodes it to an equal value.
3. **Emitter coverage:** every catalog type shipping in the release under test has at least one emitter call site in the engine, and an integration run fails if the engine emits a type that is not in the catalog. Future contracts retain their fixtures but do not require emitters before their release: in particular, `mini_app.job_ran` starts in Drop 1 ([D87](../plan/decisions.md#d87)). This closes the Draft 3 `taskgraph.snapshot` gap without pulling future features into v1.0.
4. **Class enforcement:** U types never reach the `events` table; A types always write an `audit_log` row in the same transaction; † fields never reach disk.
5. **Secret scan** over fixtures, and over the `events` and `audit_log` tables after every chaos run.
6. **Chaos** (ported harness): kill the engine (memoshid, or the iPhone and iPad app) mid-task, mid-send and mid-hand-over; assert `seq` and `cseq` stay gapless, reconciliation emits the missing completions, no store ever has two writers, and no external side effect repeats ([MASTER_PLAN §14](../plan/MASTER_PLAN.md#14-success-metrics), DEV-06).
7. **No-model admission** ([D88](../plan/decisions.md#d88), DEV-09 Phase 3 P0). Persist an airplane-mode message and its `requestId` on the reference iPhone without an offline model, restart, and assert that this unsent input produces no conversation message/task/side-thread or fallback event, lease acquisition, tool call or effect. Cancellation before delivery leaves nothing to admit. Reconnect to the current confirmed runner and assert one admission per uncanceled ID through the normal event/idempotency path, with current grants, budgets and recovery holds. Separately, with an available allowed model, exercise real side-thread join events and the exact effect list. Drop 2 adds downloaded-model offline-answer coverage and retains this no-model queue scenario.
8. **Streamed cards** (Phase 1, §5.25). For each stream fixture, apply its `card.delta` frames in `rev` order, once plainly and once with a frame repeated, and assert that the result equals the `payload` of the `card.created` or `card.updated` that ends the stream; with a frame dropped, assert that the client stops at the gap and shows the stored card when it arrives. Assert that no `card.delta` reaches the `events` table, and that an aborted stream leaves no Card and no `card.*` event.
9. **Staged families** (§5.26). Each type gets its Swift payload, fixtures and emitter in the phase that ships it (check 3); until then it is a contract only. From then: no `voice.transcript` text and no audio reach disk; `mail.organized` and `message.selection_attached` hold no subject, address, body or selected content (check 5's scan runs over seeded mail and selection fixtures); `view.arranged` never replicates; and `device.developer_mode_changed`, `plugin.*` and `full_access.*` are never written by an iPhone or iPad.

**Declared protocol coverage (2026-11-03).** [`EventRegistry`](../../Packages/MemoshiProtocol/Sources/MemoshiProtocol/Events/EventEnvelope.swift) registers the current typed payload subset, including `bot.created`, `bot.updated`, `chat.created`, `session.created`, bounded message/task/policy/review types and six system lifecycle/settings payloads. Their fixtures and canonical schema are contract artifacts; the exact registry, not a historical payload count, defines what this build decodes. `message.created` and `message.completed` also retain live fixtures. Future catalog entries are not silently removed or declared implemented.

The protocol tests cover registered fixture/schema decoding, equal re-encoding, secret scanning, † stripping/class rules and visible unknown/constraint diagnostics. Wire-rule tests break exact value lists/field limits (including `v`) and require strict/schema rejection or visible lenient preservation ([protocol §14](protocol.md#14-schema-codegen-and-fixtures), check 7). These are **contract tests**, not proof of model execution, policy, host availability, distributed replication or every catalog emitter.

**Implemented emission/storage coverage.** Current Store/Daemon sources emit settings, migration, pruning, graceful stopping, bounded Pi message/task/policy facts, verified child-task facts/content-free refresh hints and the bot/Chat/Session lifecycle subset above. Record changes and A/D facts commit together; class A is mirrored into audit rows, and publication follows commit. The client uses consumer-applied receipts and a snapshot barrier; examples in Design Preview never acknowledge real state. Fixtures for future host/device and other catalog domains do not imply emitters. The parent's later [signed text-only protocol smoke](../../../evidence/2026-11-03-memoshi-wave3-integration/native/signed-protocol-final/result.json) observed five focused delta tasks and isolated histories, automatic reconnect after one owned helper SIGKILL, five original receipts and an applied cursor equal to the final snapshot head. It used a normal no-tools helper, so it does not establish signed approval/card routing, nested-result recovery, all-call audit or the full chaos matrix. H1/E20, full shipping-domain coverage, HMAC/peer anchoring, physical devices and fresh S2 validation remain open; dated proof and limits live in [HANDOFF](../HANDOFF.md).

## 12. Mapping from Draft 3

| Draft 3 type | Draft 4 |
|---|---|
| `conversation.snapshot` | Pulled: `chats.history`, `sessions.history`, `groups.history` |
| `conversation.delta` | `message.delta` (U), `tool.started` and `tool.output` (U), `message.completed` (D) |
| `session.status` | Derived client-side from `task.*` and `card.*` (`Session.activity`) |
| `taskgraph.snapshot` (never emitted) | Pulled: `tasks.graph`, followed by `task.*` |
| `task.updated` | `task.created`, `task.started`, `task.status_changed`, `task.finished` |
| `approval.requested` | `approval.requested` (A), with tier, origin, attendance and exposure |
| `approval.resolved` | `approval.resolved`, `approval.expired`, `approval.canceled` |
| `usage.updated` (cumulative) | `usage.recorded` per usage row, plus `budget.*` |
| `computer.status` | `computer.state_changed` |
| `routine.fired` | `routine.fired` plus `task.*` for the run |
| `artifact.created` | `artifact.created` |
| `memory.updated` | The `memory.*` family |
| `error` | `message.failed`, `task.finished` with `failed`, `model.status_changed`; transport errors are JSON-RPC errors ([protocol.md](protocol.md)) |
| Commands (`session.send`, …) | Moved to [protocol.md](protocol.md) |

---

## Open questions

1. **Retention defaults.** Are 30 days of events and one year of audit right for disk use at two audited events per tool call? Measure in Phase 1 dogfooding.
2. **`bot.status_changed` class.** It is durable for the menu bar and for replicas on other devices; if volume is high it could become UI-only plus `bots.list`.
3. **Per-type version negotiation.** Is protocol-version gating enough, or does the handshake need per-type maximum versions ([protocol.md](protocol.md))?
4. **UI-only frames across devices.** Settled by [D82](../plan/decisions.md#d82): they stream only to devices that show the conversation, coalesced to about 10 a second, over direct and relay links; live-only (†) content never travels through iCloud ([§2](#2-envelope)).
5. **Projector durability.** Settled by [D82](../plan/decisions.md#d82): the projector records its progress as a change-feed cursor saved in D in the same transaction as its writes, and the entry scan is only its fallback ([§8](#8-pi-projection)).
6. **Replication log retention.** How long the relay mailbox and the iCloud sync log keep changes, and when they are compacted into snapshots ([protocol.md §12.7](protocol.md#127-replication-and-catch-up)).
7. **Card stream granularity** ([D115](../plan/decisions.md#d115), §5.25). Whole-block frames keep validation simple. Does a large block, such as a long table, need row-level frames? And do the frame's field names follow A2UI's if experiment A-E4 adopts its schema ([amendment §8](../plan/AMENDMENT_2026-11-13.md#8-open-items), item 4)? Phase 1, with [cards.md](cards.md).
8. **`view.arranged`.** Is a UI-only frame enough, or does a bot's `view.arrange` need an answer from the device it changes, and which device is that when several show the conversation ([object-model.md open question 25](object-model.md#open-questions))? Phase 1, with [protocol.md](protocol.md).
9. **The pause on a provider rate limit** (BU-09, Phase 1). How the pause of every bot and the user's Play are recorded is not set: a new `bot.paused` reason, or a type of its own ([05 §8.2](../plan/05-bots-and-assistant.md#82-enforcement)). This spec adds nothing until it is.
10. **Goals** (§5.21). The proposal path and its card; whether `goal.criterion_changed` is written by the run's runner or by the device that holds the Goal record; whether a Goal with a cap of its own needs more than `budget.*`. Phase 2, with [object-model.md open question 24](object-model.md#open-questions).
11. **Voice** (§5.22). Whether an on-device call needs the audited class or only a cloud call does; whether starting a cloud call writes a `policy.decided`; how a voice memo is stored; and whether `voice.speech_sent` is needed once [policy.md §18](policy.md#18-open-questions) item 22 is settled. Phase 2.
12. **Desktop live view on another device** (§5.13). `computer.frame` mirrors `browser.frame`, but how a Bot computer's desktop or a Cloud computer's provider stream reaches an iPhone or iPad is not specified ([06 open question 21](../plan/06-computers-and-browsers.md#13-open-questions)). Phase 3.
13. **External agents and team mode** (§5.24). The form of `actor.id` for an agent; whether an agent's start and exit need events; and the verdict's values and record. Phase 2, with [07-coding.md](../plan/07-coding.md).
14. **The user's own actions in built-in panes** (§5.23). They emit nothing today. Whether the Mail pane's changes are recorded for undo or for the other devices waits on the mail cache question ([object-model.md open question 21](object-model.md#open-questions)). Phase 1.

## Sources

- Draft 3 `~/Documents/Memoshi-Plan/specs/events.md` (13 types, SSE envelope, replay, fixtures) and `docs/02-architecture.md` (event-log pattern, write-before-ack, audit).
- pi-durable 1.3.0 README (local copy `~/Documents/Memoshi-Plan/.spike/pi-durable/package/README.md`): Watching a Conversation (100 ms commit cadence, 100-frame watch limit, no replay), Busy Conversations, Tools (replay policy, nested calls, `parentToolCallId`), Code Mode (journaled resume), Agent Events, Usage and Cost; `dist/types.d.ts` (`Seq`, IDs). Upstream: <https://github.com/earendil-works/pi>.
- [MASTER_PLAN](../plan/MASTER_PLAN.md) §5 and §14; decisions [D7](../plan/decisions.md#d7), [D9](../plan/decisions.md#d9), [D13](../plan/decisions.md#d13), [D14](../plan/decisions.md#d14), [D22](../plan/decisions.md#d22)–[D28](../plan/decisions.md#d28), [D42](../plan/decisions.md#d42), [D44](../plan/decisions.md#d44), [D46](../plan/decisions.md#d46)–[D53](../plan/decisions.md#d53), [D83](../plan/decisions.md#d83), [D87](../plan/decisions.md#d87) and [D88](../plan/decisions.md#d88).
- [Draft 3 build audit](../research/agentic-workspace-landscape/landscape/in-house-assets.md#draft-3-build) (per-session streams, polling, dropped events, double transcript storage).
- [Grok Bot profile](../research/agentic-workspace-landscape/projects/grok-bot.md) (closed error enum and replay fixture corpus shared across clients).
- Names agreed on 2026-10-20 with the owners of [protocol.md](protocol.md), [policy.md](policy.md), [02-experience.md](../plan/02-experience.md), [05-bots-and-assistant.md](../plan/05-bots-and-assistant.md), [06-computers-and-browsers.md](../plan/06-computers-and-browsers.md) and [07-coding.md](../plan/07-coding.md), and on 2026-10-22 with the owners of [policy.md](policy.md), [02](../plan/02-experience.md), [04](../plan/04-architecture.md), [05](../plan/05-bots-and-assistant.md), [06](../plan/06-computers-and-browsers.md), [07](../plan/07-coding.md) and [09](../plan/09-platform-macos.md).
- Decisions [D106](../plan/decisions.md#d106)–[D122](../plan/decisions.md#d122) and the [scope amendment of 2026-11-13](../plan/AMENDMENT_2026-11-13.md). The names staged on 2026-11-13 follow the revised [object-model.md](object-model.md) and [policy.md](policy.md), and were exchanged that day with the owners of [protocol.md](protocol.md) and [cards.md](cards.md).
