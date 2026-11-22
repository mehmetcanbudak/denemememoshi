# Specs

**Status:** Draft 4 · 2026-10-20 · updated 2026-10-23 for D44–D89 · updated 2026-11-13 for [D106](../plan/decisions.md#d106)–[D122](../plan/decisions.md#d122): the index lines for object-model, events, protocol, policy and cards name their added scope, freeze points follow the moved stages and name M1, and the vocabulary row carries App
**Owns:** The index of implementation-level specs, their owners and status, and the conventions every spec shares.
**Depends on:** [MASTER_PLAN](../plan/MASTER_PLAN.md), [decisions](../plan/decisions.md), [04-architecture.md](../plan/04-architecture.md)

These are the contracts that Memoshi.app, memoshid and the iPhone and iPad app (all Swift, with Pi_Swift as the engine, [D44](../plan/decisions.md#d44), [D46](../plan/decisions.md#d46)) and the protocol schema build against. Plan docs in [`../plan/`](../plan/) explain *why*; specs say *exactly what*. Adapted from Draft 3 `specs/README.md`.

## Index

| Spec | Owns | Owner (plan area) | Status | Freeze point |
|---|---|---|---|---|
| [object-model.md](object-model.md) | Objects, fields, IDs, relations, invariants, storage owners, Pi mapping, state machines; devices and their group, leases per conversation, replicas, lanes, side threads versus local unsent messages, budget slices, checkpoints, Trash, secret entries and tool definitions; from 2026-11-13 also App (the object once called mini app), View, Goal (GR-13), Voice call (V2-09), mail account (CON-08), Provider setting, the plugin developer mode records (CH-44) and the computer kinds a bot can be given (CMP-05; [D109](../plan/decisions.md#d109), [D111](../plan/decisions.md#d111), [D113](../plan/decisions.md#d113), [D114](../plan/decisions.md#d114), [D116](../plan/decisions.md#d116), [D119](../plan/decisions.md#d119), [D120](../plan/decisions.md#d120)) | Domain specs | Draft 4 | Phase 0 gate (the protocol's Swift types follow it) |
| [events.md](events.md) | Event envelope, catalog by domain (devices, leases and replication included), audited, durable and UI-only classes, resync, Pi projection, retention, compatibility; from 2026-11-13 also the events of the objects that D109–D116 add or change ([amendment §7](../plan/AMENDMENT_2026-11-13.md#7-reviews-these-decisions-trigger)) | Domain specs | Draft 4 | Phase 0 gate; additive changes afterwards |
| [protocol.md](protocol.md) | The typed API (Swift types; in process on iPhone and iPad, JSON-RPC 2.0 over a WebSocket on a Unix socket on the Mac), handshake, RPC methods, program frames, errors, idempotency, app capability calls; the device layer: pairing and the device group, links, leases per conversation, replication, versions, handoff lanes, budget slices, cookie sync and cross-device tool calls; from 2026-11-13 also the methods for Apps as panes with exported functions and for the other objects that D109–D116 add or change ([D114](../plan/decisions.md#d114), [amendment §7](../plan/AMENDMENT_2026-11-13.md#7-reviews-these-decisions-trigger)) | Architecture ([04-architecture.md](../plan/04-architecture.md)) | Draft 4 | Phase 0 gate |
| [policy.md](policy.md) | Tiers T0–T5, permission modes (Ask first, Auto, Bypass), rule evaluation, approvals, grants and standing rules, drafts and send tokens, exposure, audit hash chain; from 2026-11-13 also the classes and tiers for search, mail, media generation, cloud voice, Cloud computers, App function calls and view tools, and the plugin developer mode regime with Full access on this Mac (SEC-28, CH-34, CH-35, CH-44; [D118](../plan/decisions.md#d118), [D121](../plan/decisions.md#d121)) | Security ([08-security-and-privacy.md](../plan/08-security-and-privacy.md)) | Draft 4 | Phase 1 (before the first T2+ tool ships) |
| [cards.md](cards.md) | Card schema ([D53](../plan/decisions.md#d53)): the JSON a bot writes, its block catalog, actions, validation and fallback, and the native kinds; Swift live cards and Apps, their engine, permission lists, source and staged jobs/widgets/cache contracts; from 2026-11-13 also catalog cards streamed as the model writes and aligned with A2UI, and the App contract of pane, exported functions, view tools, selection carry and page Apps (CH-19, CH-33 to CH-37; [D114](../plan/decisions.md#d114), [D115](../plan/decisions.md#d115)) | Design ([03-design-system.md](../plan/03-design-system.md)) | Draft 4 | Phase 1, before generated cards ship (CH-19, moved from Phase 2 by [D115](../plan/decisions.md#d115)) [INFERENCE]; Drop 1 additions at the Drop 1 gate ([D87](../plan/decisions.md#d87)) |
| [bot-definition.md](bot-definition.md) | The portable `bot.md` format: front matter schema, persona, export and import rules | Domain specs, with [05-bots-and-assistant.md](../plan/05-bots-and-assistant.md) | Draft 4 | M1, the gate at the end of Phase 1 (EXP-01 in [feature-catalog.md](../plan/feature-catalog.md)) |
| [design-tokens.json](design-tokens.json) | Color, type, spacing, radius, motion, avatar shape and color IDs | Design ([03-design-system.md](../plan/03-design-system.md)) | Draft 4 | Phase 0 (primitives), Phase 1 (avatars) |

"Owner" is the plan area responsible for the spec; a change to a spec owned by one area that touches another's names needs both owners' agreement.

[design-reference.md](design-reference.md) is a record, not a contract, so it has no row above: it states the design direction of [D106](../plan/decisions.md#d106) and keeps the implementation record of the earlier preview, frozen at git tag `design-preview-2026-11-13`.

## Source-of-truth order

1. [MASTER_PLAN](../plan/MASTER_PLAN.md) vocabulary and [decisions](../plan/decisions.md) bind everything.
2. `object-model.md` defines the domain; every other spec uses its names.
3. `events.md` and `protocol.md` define the wire; `policy.md` defines decisions; `bot-definition.md` defines the file format; `cards.md` defines card JSON and Swift live cards and Apps; `design-tokens.json` defines the visuals.
4. If code and a spec disagree, the spec wins until it is deliberately changed. A change that alters the object model goes through [change control](../plan/decisions.md#change-control) (rule 4: spec review).

## Shared conventions

| Topic | Rule |
|---|---|
| IDs | Prefixed ULIDs (`bot_01JC…`), globally unique, never reused ([object-model.md §1.1](object-model.md#11-ids)); Pi's numeric IDs never leave the runtime adapter |
| Timestamps | Unix epoch milliseconds, UTC, integers; RFC 3339 only in human-authored files (`bot.md`) |
| Casing | JSON fields camelCase; enum values lowercase snake_case; SQLite tables plural snake_case; YAML keys in `bot.md` snake_case |
| Money | Integer micro-USD on the wire and in storage; decimal dollars only in `bot.md` and the UI |
| Secrets | Never in records, events, audit, logs, memory or files; only Keychain references (`SecretRef`) |
| Transcripts | Stored once per device, in Pi storage: each conversation's store on its runner, and read-only replicas elsewhere ([D7](../plan/decisions.md#d7), [D49](../plan/decisions.md#d49), [D74](../plan/decisions.md#d74)); no spec may copy message text into `memoshi.sqlite` tables or persisted events |
| Devices | Every device keeps its own `memoshi.sqlite`, event log and Pi stores. Each conversation has one writer, its runner, fenced by that conversation's lease epoch, so one bot may run conversations on two devices at once; bot-wide records merge ([object-model.md §3.4](object-model.md#34-runner-replicas-and-record-ownership), [D74](../plan/decisions.md#d74)) |
| No-model messages | When neither the conversation's runner nor an allowed model is reachable, the device persists the message in its existing local unsent queue with its original `requestId` and shows **Waiting for connection**. It creates no authoritative message, model turn, side-thread answer, tool call or effect; cancellation removes it before delivery, and reconnect uses the normal idempotent send to the current confirmed runner. A real side thread still requires an available allowed model ([D88](../plan/decisions.md#d88), [protocol.md §9](protocol.md#9-idempotency)) |
| Code Mode | The same pinned upstream `quickjs.wasm`: wasm2c for shipping, WasmKit as reference and compatibility fallback, no JavaScriptCore backend. Pi_Swift's Node-oracle differential and physical-device safety/performance gates still apply ([D89](../plan/decisions.md#d89)) |
| Swift program releases | v1.0 stores source and compiles it locally on each device. Background jobs, widgets and the signed-bytecode cache arrive in Drop 1, not as v1.0 prerequisites ([D87](../plan/decisions.md#d87), [cards.md](cards.md)) |
| Unknown input | Consumers ignore unknown fields, decode unknown enum values as `unknown`, and surface unknown event types in diagnostics instead of dropping them silently |
| Breaking changes | Bump the protocol version or the event's `typeVersion`, add a migration note, update fixtures |
| Vocabulary | The UI says Bot, never "agent" ([D4](../plan/decisions.md#d4)). The object once called a mini app is an App, with a capital A, of kind page App or Swift App; "the app" in lower case is Memoshi. Identifiers keep their names: the `mini_app` tool, `miniApps.*` methods, `mini_app.*` events and the `app_` prefix ([D119](../plan/decisions.md#d119)) |

## Generated artifacts and fixtures

- The protocol's Swift types are its source of truth, shared by memoshid and both apps; the JSON Schema (Draft 2020-12) is generated from them for tests and docs, so hand-copied models cannot drift (the Draft 3 build's models had drifted, [Draft 3 build audit](../research/agentic-workspace-landscape/landscape/in-house-assets.md#draft-3-build)) ([D78](../plan/decisions.md#d78), [protocol.md §14](protocol.md#14-schema-codegen-and-fixtures)).
- Every event type, RPC method and device message has fixtures under `protocol/fixtures/`, validated in CI against the JSON Schema and by a Swift decode-and-re-encode round trip ([events.md §11](events.md#11-contract-fixtures-and-tests)).
- `bot.md` templates shipped with the app ([feature-catalog.md](../plan/feature-catalog.md) ON-06) are validated by the same loader as user imports.

## Adding or changing a spec

1. Name it after its domain (for example `git-review.md`).
2. Use the standard header (Title, Status, Owns, Depends on) and end with Open questions and Sources.
3. Include purpose, data shapes, invariants, state machines where relevant, examples, failure modes and the fixtures it needs.
4. Link it from this index and from the plan doc that owns the area.
5. Record the change in the spec's status line and, if a decision changed, in [decisions.md](../plan/decisions.md).

## Open questions

1. Settled in part by [D78](../plan/decisions.md#d78): the protocol's Swift types are the source of truth and generate the JSON Schema. Open: should CI check `object-model.md` and `events.md` against those types, so the Markdown cannot drift from them?
2. Who owns the review comments (`rvc_`) long-term: [07-coding.md](../plan/07-coding.md) or a future `git-review.md` spec? Checkpoints (`ckp_`) are now in [object-model.md §4.6](object-model.md#46-session-ses_) ([D77](../plan/decisions.md#d77)).

## Sources

- Draft 3 `~/Documents/Memoshi-Plan/specs/README.md` (conventions, source-of-truth order, "adding a spec").
- [MASTER_PLAN §16 document map](../plan/MASTER_PLAN.md#16-document-map) and [decisions](../plan/decisions.md).
- [Draft 3 build audit](../research/agentic-workspace-landscape/landscape/in-house-assets.md#draft-3-build) (protocol model drift, dropped events).
