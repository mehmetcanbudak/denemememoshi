# In-house assets: boop and harness (Forma)

Audit of two repos already on disk next to Memoshi, as of 2026-10-20. Read-only: local files, local git refs, and `gh api` only. Nothing was fetched, built, or run.

- `boop` = `~/Documents/memoshi/boop`
- `harness` = `~/Documents/memoshi/harness`

Links to upstream files point at the exact commit checked out locally (boop `3197913`, t3code `a7b0366c`, Forma `542c77d5`), so they match what is on disk.

Two more audits were appended on 2026-10-20 for the Draft 4 plan, under the same read-only rules: [section 6](#apollo) covers Apollo (`~/Memo/apollo-agent`, the user's own assistant) and [section 7](#draft-3-build) covers the Draft 3 build (`~/Documents/Memoshi-Plan`, the code of the superseded Draft 3 plan). Neither repo is public (Apollo's remote is private; Draft 3 has no remote), so their paths are local. In the reuse map, `apollo-agent/` means `~/Memo/apollo-agent` and `Memoshi-Plan/` means `~/Documents/Memoshi-Plan`.

## 1. Summary

| | boop | harness (Forma) |
|---|---|---|
| What it is | Single-user iMessage personal assistant: dispatcher agent + ephemeral sub-agents, tiered memory, cron automations, draft-before-send, Composio connectors, debug dashboard | Fork of T3 Code: server-owned coding-agent workspace (Codex, Claude, Cursor, Grok, OpenCode) with web, Electron desktop, Expo mobile clients and remote access |
| Upstream | [raroque/boop-agent](https://github.com/raroque/boop-agent), MIT | [stevesarmiento/harness](https://github.com/stevesarmiento/harness) (fork of [pingdotgg/t3code](https://github.com/pingdotgg/t3code)), MIT |
| Local divergence | 0 commits vs upstream; only uncommitted skill files plus an untracked Rust GPUI desktop port | Checked-out branch is 168 commits of Forma work on top of t3code v0.0.33; local copy is 2,525 commits behind the remote Forma branch |
| Size | ~10.7k LOC TS in `server/` + 15.5k LOC Rust in untracked `desktop/` | ~460k LOC TS across apps/packages (excl. vendored `.repos/`) |
| Tests | 16 vitest files, 71 cases | ~780 test files in apps/packages |
| Maturity | Polished template, single tenant, no auth, in-process scheduler | Production-grade, event-sourced, heavily tested; Forma layer is one person's UI-heavy fork |
| Best use for Memoshi | Copy or reference the assistant brain: memory, automations, drafts, runtime switch, connector registry | Reference (or fork) for the coding workspace, multi-engine harness, approvals, and remote/mobile access |

Main takeaway [INFERENCE]: the two repos fit together. boop covers the "personal assistant + routines + memory" half of Memoshi. T3 Code covers the "agentic workspace + multi-engine + mobile" half. Neither has a persistent bot roster. Both are MIT. boop's real lock-ins are Convex and Sendblue. T3 Code's are Effect 4 and a very fast-moving upstream.

**Added for Draft 4** ([section 6](#apollo), [section 7](#draft-3-build)):

| | Apollo | Draft 3 build |
|---|---|---|
| What it is | The user's own assistant, grown from a boop fork: iOS, watchOS, macOS, iMessage, Telegram and WhatsApp surfaces, a hosted coordinator, Convex state, and paired Mac workers for local capabilities | The code of the superseded Draft 3 plan: a SwiftUI Mac app that launches a Node sidecar running Pi Durable |
| Pi | Seven `@earendil-works` packages pinned at exactly 1.3.0, including `pi-durable`; real Durable turns; its own `apollo_code` Code Mode on upstream `pi-codemode`'s QuickJS sandbox | `pi-durable` 1.3.0 through eight APIs, with Pi's fake model only |
| Size and tests | About 82k TS lines in `server/`, 48k in `convex/` and 99k Swift lines in `ios/`; 432 JS/TS and 133 Swift test files | 31 Swift files (about 11.5k LOC), 19 sidecar files (about 5.9k LOC) and a 683-line Zod protocol; 35 sidecar tests, no Swift tests |
| Best use for Memoshi | Port the Apple capability contracts and Swift services, hash-bound approvals, the draft commit protocol, automation leases and memory provenance | Port the protocol package, transport replay and auth, the store-and-event pattern, policy and approvals, and the test harnesses; drop its runtime, tools and seed ([D36](../../../plan/decisions.md#d36)) |

Takeaway for the new sections [INFERENCE]: Apollo is the deepest source for Apple integrations and for effect safety (intent recorded before dispatch, explicit unknown outcomes, fenced leases), but its Convex and multi-tenant plumbing does not transfer. Draft 3 is a thin, tested skeleton; its value is the protocol, store and policy code, not its runtime.

## 2. boop

### Provenance and license

- Remotes: `origin` = `github.com/mehmetcanbudak/boop`, `upstream` = `github.com/raroque/boop-agent` (local `git remote -v`). GitHub marks `mehmetcanbudak/boop` as a fork of `raroque/boop-agent`, created 2026-08-17, 0 stars (gh api, 2026-10-20).
- License: MIT, "Copyright (c) 2026 Chris Raroque" (`boop/LICENSE`). Same as upstream ([gh api](https://github.com/raroque/boop-agent)).
- Upstream stats (gh api, 2026-10-20): 1,382 stars, 299 forks, 24 open issues, created 2026-04-14, last push 2026-07-13, 4 contributors, no GitHub releases. The first commit is "Initial commit: boop-agent template" (2026-04-14). Local history has 107 commits.
- Upstream has had no push since 2026-07-13. Ten PRs are still open. Several fix breakage against current dependencies (titles only, not verified): [#82 "Fix Codex runtime rejecting all models newer than gpt-5.5"](https://github.com/raroque/boop-agent/pull/82), [#83 Codex app-server turn aborts](https://github.com/raroque/boop-agent/pull/83), [#78 Composio authorize endpoint](https://github.com/raroque/boop-agent/pull/78), [#72 runaway Convex demo reads](https://github.com/raroque/boop-agent/pull/72). Others add features: [#61 iOS dock + voice mode](https://github.com/raroque/boop-agent/pull/61), [#65 GitAgent protocol](https://github.com/raroque/boop-agent/pull/65), [#80 portable agent run export](https://github.com/raroque/boop-agent/pull/80).

### Divergence from upstream (local refs)

- `main`, `desktop-gpui` (checked out), `origin/main` and `upstream/main` all point at `3197913` "Add desktop app, resilient webhooks, and realistic demo mode (#67)" (2026-07-13). `git rev-list --left-right --count main...upstream/main` = `0 0`. The `gh api compare` call shows upstream main has not moved since then.
- Uncommitted local work (`git status`, 77 entries):
  - Edits to `AGENTS.md`, `CLAUDE.md`, `package-lock.json`, `skills-lock.json`.
  - About 30 new `convex-*` agent skills under `.agents/skills/` and `.claude/skills/`. This is dev tooling, not product code.
  - An untracked `desktop/` directory: a Rust GPUI port of the debug dashboard. Its `Cargo.toml` uses `gpui 0.2.2`, `gpui-component 0.5.1`, `convex 0.10.4`, `tokio`, `reqwest`. It is about 15.5k LOC across 40 `.rs` files, with 119 `#[test]` functions, and file mtimes are 2026-08-18.
  - Its header (`~/Documents/memoshi/boop/desktop/src/main.rs`) says all eight panels are ported on live Convex subscriptions. It lists the memory force-graph, demo-mode fakes, and window-state persistence as outstanding.
  - `~/Documents/memoshi/boop/desktop/src/supervisor.rs` spawns `node scripts/dev.mjs` and reuses the readiness markers from `electron/main.cjs`.
  - This is the user's own unpushed work, and it exists only on this disk.

### Stack

- Runtime: Node + TypeScript + Express 5 + `ws`. Agent engines: `@anthropic-ai/claude-agent-sdk ^0.1.0` or the Codex app-server over JSON-RPC. The repo vendors 570+ generated protocol type files in [`server/runtimes/codex-app-server-protocol/`](https://github.com/raroque/boop-agent/tree/3197913/server/runtimes) (`boop/package.json`).
- State: Convex 1.36 with 14 tables in [`convex/schema.ts`](https://github.com/raroque/boop-agent/blob/3197913/convex/schema.ts), including a 1024-dimension vector index on `memoryRecords` ([ARCHITECTURE.md](https://github.com/raroque/boop-agent/blob/3197913/ARCHITECTURE.md)).
- Integrations:
  - Composio (`@composio/core`, `@composio/claude-agent-sdk`).
  - Sendblue for iMessage in and out, with ngrok for the inbound tunnel.
  - Optional Patchright Chrome for browser use.
  - Local Apple data: `chat.db` read through `/usr/bin/sqlite3`; Notes and Reminders through `osascript` ([README](https://github.com/raroque/boop-agent/blob/3197913/README.md)).
- Embeddings: Voyage `voyage-3`, OpenAI `text-embedding-3-large`, or a local `Xenova/bge-large-en-v1.5` fallback via `@huggingface/transformers`, all 1024-dimension ([`server/embeddings.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/embeddings.ts)).
- UI: Vite + React + Tailwind 4 debug dashboard (`debug/src/`). Electron 43 shell ([`electron/main.cjs`](https://github.com/raroque/boop-agent/blob/3197913/electron/main.cjs), 844 lines) plus the local untracked GPUI port.
- Auth model: uses the user's Claude Code or Codex/ChatGPT subscription session, so there is "no separate provider API key" ([README](https://github.com/raroque/boop-agent/blob/3197913/README.md)).

### Architecture and key modules

| Concern | File(s) | Notes |
|---|---|---|
| Dispatcher ("interaction agent") | [`server/interaction-agent.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/interaction-agent.ts) (654 LOC) | One per user turn. Tools are limited to memory, `spawn_agent`, automations, and drafts. Web, files, and integrations are denied to it ([README](https://github.com/raroque/boop-agent/blob/3197913/README.md)). |
| Workers ("execution agents") | [`server/execution-agent.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/execution-agent.ts) | Ephemeral, one task each. Loads only the integrations named in the spawn. Every tool call is logged to Convex. Claude runs with `permissionMode: bypassPermissions`, and the dispatcher acts as gatekeeper ([ARCHITECTURE.md](https://github.com/raroque/boop-agent/blob/3197913/ARCHITECTURE.md)). |
| Engine abstraction | [`server/runtimes/index.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/runtimes/index.ts), [`types.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/runtimes/types.ts), [`claude.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/runtimes/claude.ts), [`codex-app-server.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/runtimes/codex-app-server.ts) | `runAgentRuntime(config, request)` switches on `"claude" \| "codex"`. A shared `RuntimeTool` type carries a zod shape, a JSON schema, and a handler. Codex runs with `approvalPolicy: "never"` and `sandbox: "read-only"`. |
| Memory | [`server/memory/types.ts`, `tools.ts`, `extract.ts`, `clean.ts`](https://github.com/raroque/boop-agent/tree/3197913/server/memory); [`server/consolidation.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/consolidation.ts) | Tiers: short (5%/day decay), long (2%/day), permanent. Six segments. Post-turn fire-and-forget extraction. A 6-hourly decay/archive/prune loop. A daily proposer + judge consolidation that merges, supersedes, or prunes. |
| Automations | [`server/automations.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/automations.ts), [`server/automation-tools.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/automation-tools.ts), [`server/timezone-config.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/timezone-config.ts) | 30-second in-process poll with `croner` cron and user timezone. Each run reuses the sub-agent spawn and can push its result to iMessage. |
| Proactive triggers | [`server/proactive-email.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/proactive-email.ts), [`server/composio-webhook.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/composio-webhook.ts) | A Composio Gmail trigger goes to a classifier model, and important mail is injected as a synthetic turn into the dispatcher. |
| Approvals (external actions) | [`server/draft-tools.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/draft-tools.ts) | Workers can only call `save_draft`. The dispatcher calls `send_draft` or `reject_draft`, and sending spawns a fresh worker. |
| Connectors | [`server/integrations/registry.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/integrations/registry.ts), [`composio.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/composio.ts), [`integrations/*-loader.ts`](https://github.com/raroque/boop-agent/tree/3197913/server/integrations), [`server/apple/`](https://github.com/raroque/boop-agent/tree/3197913/server/apple), [`server/browser/`](https://github.com/raroque/boop-agent/tree/3197913/server/browser) | `IntegrationModule { name, isEnabled, createServer, createTools }`. Each spawn gets a toolkit-scoped Composio session, so a sub-agent sees only the toolkits it asked for. |
| Channel | [`server/sendblue.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/sendblue.ts), [`server/sendblue-webhook-auth.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/sendblue-webhook-auth.ts) | Webhook dedup in a Convex table, an HMAC-derived shared secret compared with `timingSafeEqual`, and chunking at 2,900 chars. |
| Ops | [`server/heartbeat.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/heartbeat.ts), [`server/local-access.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/local-access.ts), [`server/privacy.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/privacy.ts), [`server/usage.ts`](https://github.com/raroque/boop-agent/blob/3197913/server/usage.ts) | 15-minute agent timeout and orphan reaping. Browser and Apple routes are localhost-only. Phone numbers and handles are redacted. Token and cost accounting. |
| Debug UI | `debug/src/components/*Panel.tsx` | Agents, automations, memory (including a graph view), consolidation, connections, events, and settings, driven by reactive Convex queries. |

### Production-quality vs prototype

- Solid enough to lift:
  - The runtime abstraction and Codex app-server client.
  - The draft-gated external actions.
  - The memory decay math and consolidation pipeline.
  - Webhook auth and dedup.
  - Localhost guards and PII redaction.
  - The toolkit-scoped connector registry.
- Prototype or single-tenant by design ([ARCHITECTURE.md "What's intentionally missing"](https://github.com/raroque/boop-agent/blob/3197913/ARCHITECTURE.md)):
  - No user auth.
  - The scheduler double-fires if more than one instance runs.
  - No knowledge graph (only `supersedes`).
  - Inbound depends on an ngrok tunnel.
  - System prompts are hard-coded in `server/*-agent.ts`.
  - Workers bypass Claude permissions entirely.
- Tests: 16 vitest files with 71 cases in `test/`. They cover Sendblue auth, media, and sync, browser security, local access, the runtime switch, the Composio catalog, the Apple bridge, and the memory graph model. There are no end-to-end agent tests. The untracked GPUI port has 119 Rust unit tests.

### Mapping to Memoshi

| Memoshi capability | boop coverage |
|---|---|
| Personal assistant | Strong: the whole product is a dispatcher, worker, and channel. |
| Bot roster | Weak: workers get an optional `name` but are ephemeral. There are no persistent identities or personas [INFERENCE from `server/execution-agent.ts`]. |
| Routines | Strong: cron automations, notify-to-channel, and the Gmail proactive trigger. |
| Memory | Strong: tiered, decaying, consolidated, with vector recall. |
| Connectors | Strong via Composio (~1000 toolkits, vendor claim), plus local Apple data and the local browser. |
| Coding workspace | None. |
| Mobile / remote | iMessage is the mobile client. The iOS app exists only as an open PR (#61). |
| Multi-engine | Two engines (Claude Agent SDK, Codex app-server). |
| Approvals | Drafts for external side effects. No per-tool approval prompts. |

## 3. harness (Forma)

### Provenance and license

- Remote: `origin` = `github.com/stevesarmiento/harness`. There is no `upstream` remote locally. GitHub marks it as a fork of `pingdotgg/t3code`. It has 0 stars and 0 forks, was created 2026-04-21, and was last pushed 2026-10-07 (gh api, 2026-10-20).
- License: MIT, "Copyright (c) 2026 T3 Tools Inc." (`harness/LICENSE`). The Forma commits add no separate license.
- The product is rebranded "Forma" in [README.md](https://github.com/stevesarmiento/harness/blob/542c77d5/README.md). The rebrand is partial:
  - The README links to `github.com/pingdotgg/forma` releases, `brew install --cask forma`, and `winget install Forma.Forma`. `gh api repos/pingdotgg/forma` returns 404, so these look like search-and-replace artifacts.
  - The docs still say "T3 Code" throughout.
- Upstream pingdotgg/t3code (gh api, 2026-10-20):
  - 28,681 stars, 7,685 forks, 2,382 open issues.
  - At least 100 contributors (the API page cap).
  - Last push 2026-10-20. Latest stable release [v0.1.0](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0) on 2026-10-15 (previous: v0.0.45 on 2026-10-02). Nightly releases ship several times a day.
  - About 2,816 commits since 2026-09-20 (commit search count).

### Divergence (local refs, plus gh api for the remote)

- Branches:
  - Local `main` = `origin/main` = `a7b0366c`, a pure t3code commit dated 2026-08-10, the v0.0.33 era. The fork's `main` mirrors t3code.
  - The Forma work is on `merge/upstream-v0.0.31` (checked out). It is 168 commits ahead of `origin/main`, all by "Steven", the first on 2026-04-21 ("rebrand"). It is 0 behind.
- Size of the Forma delta: `git diff --stat origin/main HEAD` = 489 files, +38,863 / -17,664. Changes are concentrated in `apps/web/src` (chat, settings, custom icons) and `apps/server/src` (componentPreview, persistence). `packages/` changed in only 30 files (+1,929).
- Forma-added server and contract modules:

| Module | Paths |
|---|---|
| Component preview harness (isolated Vite server that previews the user's React components) | `apps/server/src/componentPreview/`, `packages/contracts/src/componentPreview.ts` |
| Turn queue and ask/plan modes | `apps/server/src/threadExtensions/ThreadExtensionService.ts`, `packages/contracts/src/threadExtensions.ts`, `apps/server/src/persistence/Layers/ProjectionThreadTurnQueue.ts` |
| Thread forking | `apps/server/src/orchestration/threadForking.ts` |
| Project agent/skill inventory | `apps/server/src/project/ProjectAgentInventory.ts`, `packages/contracts/src/localAgents.ts` |
| Protected paths (blocks agent access to `~/Library/Messages`, Mail, and similar) | `apps/server/src/workspace/WorkspaceProtectedPaths.ts`, `packages/shared/src/protectedPaths.ts` |
| Migrations | `apps/server/src/persistence/Migrations/935`–`941` |

- Merge policy:
  - Upstream rejections are recorded in [`docs/internals/SKIPPED-UPSTREAM.md`](https://github.com/stevesarmiento/harness/blob/542c77d5/docs/internals/SKIPPED-UPSTREAM.md), e.g. the upstream theme library and the sidebar v2 default.
  - 21 files carry `// Fork:` markers.
  - Merge commits are named "Merge upstream/main v0.0.33 with Forma protection policy" (2026-08-10).
- Staleness of the local clone, via gh api compare:
  - The remote `merge/upstream-v0.0.31` branch is 2,525 commits ahead of local HEAD `542c77d5`. Its head is "Merge upstream main (Effect 4.0.1, GitHub API, /goal) into the Forma fork" (2026-10-07). On the remote, that branch is 184 commits ahead of fork `main`.
  - A newer remote branch, `merge/upstream-v0.0.38`, also exists.
  - t3code `main` is 4,612 commits ahead of local `a7b0366c`.

### Stack

- Bun/Node + TypeScript, with a monorepo driven by `vp` and pnpm catalogs (`harness/package.json`, `pnpm-workspace.yaml`).
- Effect 4.0.0-beta.103 everywhere locally: `effect`, `@effect/platform-*`, `@effect/sql-sqlite-bun`, `@effect/atom-react`, `@effect/vitest`. The remote fork has since moved to Effect 4.0.1 (merge commit title).
- Persistence: SQLite event store plus projections (`apps/server/src/persistence/Layers/Sqlite.ts`, 61 migrations).
- Clients:
  - Web: React + Vite, with Monaco added by Forma (`apps/web/src/lib/monaco.ts`).
  - Desktop: Electron (`apps/desktop`).
  - Mobile: Expo 56 / React Native 0.85 with `@clerk/expo` and `expo-notifications` (`apps/mobile/package.json`).
- Native: `native/libghostty-vt` (terminal), `native/resource-monitor` (Rust).
- Hosted relay ("T3 Connect", `infra/relay`): Cloudflare, PlanetScale, Drizzle, and Axiom via `alchemy` (`infra/relay/alchemy.run.ts`), with Clerk auth and APNs ([`infra/relay/README.md`](https://github.com/pingdotgg/t3code/blob/a7b0366c/infra/relay/README.md), [`docs/internals/t3-connect.md`](https://github.com/pingdotgg/t3code/blob/a7b0366c/docs/internals/t3-connect.md)).
- `.repos/alchemy-effect` and `.repos/effect-smol` are committed read-only reference copies, about 13k files, used as agent context ([`AGENTS.md`](https://github.com/pingdotgg/t3code/blob/a7b0366c/AGENTS.md) line 126).

### Architecture and key modules

Source: [`docs/internals/overview.md`](https://github.com/pingdotgg/t3code/blob/a7b0366c/docs/internals/overview.md) and [`providers.md`](https://github.com/pingdotgg/t3code/blob/a7b0366c/docs/internals/providers.md), verified against paths on disk.

| Layer | Paths | Notes |
|---|---|---|
| RPC contract | `packages/contracts/src/rpc.ts`, `orchestration.ts`, `settings.ts` | Effect RPC over one authenticated WebSocket. Each method has a required scope. |
| Event-sourced orchestration | `apps/server/src/orchestration/Layers/OrchestrationEngine.ts`, `decider.ts`, `projector.ts` | Single-writer command queue. Idempotent command receipts. Events and projections are written in one SQL transaction. |
| Provider drivers | `apps/server/src/provider/builtInDrivers.ts`, `provider/Drivers/{Codex,Claude,Cursor,Grok,OpenCode}Driver.ts`, `provider/Layers/*Adapter.ts`, `ProviderInstanceRegistry`, `ProviderService` | Adding an engine means a driver plus an adapter, with no orchestration or client changes ([providers.md](https://github.com/pingdotgg/t3code/blob/a7b0366c/docs/internals/providers.md)). |
| Protocol clients | `packages/effect-codex-app-server/` (46k LOC, mostly generated), `packages/effect-acp/` (Agent Client Protocol, 13k LOC) | Typed Effect clients. Workspace-private packages, but self-contained. |
| Workers | `ProviderRuntimeIngestion.ts`, `ProviderCommandReactor.ts`, `CheckpointReactor.ts`, `packages/shared/src/DrainableWorker.ts` | Queue-backed and drainable for deterministic tests. |
| Checkpoints | `apps/server/src/checkpointing/`, `apps/server/src/vcs/VcsDriver.ts` | Every turn is bracketed by hidden Git refs, giving exact diff and revert. |
| Approvals | `thread.approval.respond`, `thread.runtime-mode.set` in `packages/contracts/src/orchestration.ts` | Four modes: Supervised, Auto-accept edits, Auto, Full access. Each is mapped to the provider's own sandbox and approval policy ([`docs/user/permission-modes.md`](https://github.com/pingdotgg/t3code/blob/a7b0366c/docs/user/permission-modes.md)). |
| Client runtime | `packages/client-runtime/src/` | Connection supervisor, RPC session, and Atom state, shared by web and mobile. |
| Remote | `packages/ssh`, `packages/tailscale`, `apps/server/src/relay`, `infra/relay`, `packages/client-runtime` connection targets | Direct bearer, relay tunnel, Tailscale serve, and desktop-managed SSH ([`docs/internals/remote.md`](https://github.com/pingdotgg/t3code/blob/a7b0366c/docs/internals/remote.md)). |
| MCP | `apps/server/src/mcp/` | HTTP MCP server, session registry, preview automation broker. |
| Background | `apps/server/src/background/BackgroundPolicy.ts`, `HostPowerMonitor.ts` | Power-aware background policy. |

### Production-quality vs prototype

- Production-grade (upstream):
  - Event-sourced engine, driver registry, checkpointing, remote access, and mobile client.
  - About 780 test files under `apps/` and `packages/`: server 248, web 254, mobile 101, desktop 57, client-runtime 47, shared 43, plus 27 in `infra/relay`.
  - Desktop packaging scripts for dmg, AppImage, and nsis (`package.json` `dist:desktop:*`).
  - The README still says "We are very very early in this project. Expect bugs."
- Forma layer:
  - Mostly visual: icons, sidebar, composer, settings pages, Monaco editor.
  - Plus four functional features: component preview, turn queue/ask/plan modes, thread forking, protected paths.
  - The feature code has tests (e.g. `ThreadExtensionService.test.ts`).
  - It is one maintainer's fork with expensive manual merges and no releases. The branding and install instructions are inconsistent.
- No routines or automations exist in the server: `grep` for cron or scheduling in `apps/server/src` finds nothing. No long-term memory either [INFERENCE: no memory module in `apps/server/src`].

### Mapping to Memoshi

| Memoshi capability | harness coverage |
|---|---|
| Personal assistant | None (coding-only). |
| Bot roster | Partial: per-project agent and skill inventory (`ProjectAgentInventory.ts`, Forma). Threads are per-task, not persistent teammates. |
| Routines | None. |
| Memory | None beyond thread history and checkpoints. |
| Connectors | MCP server plumbing only (`apps/server/src/mcp/`). |
| Coding workspace | Strong: threads, diffs, checkpoints, terminals, git/PRs, worktrees, component preview. |
| Mobile / remote | Strong: Expo app, relay, Tailscale, SSH, push notifications. |
| Multi-engine | Strong: five drivers plus typed Codex app-server and ACP clients. |
| Approvals | Strong: four permission modes with inline approve/reject. |

## 4. Reuse map

| Memoshi capability | Asset | Path | Reuse mode | Value |
|---|---|---|---|---|
| Personal assistant (dispatcher/worker split) | boop | `boop/server/interaction-agent.ts`, `boop/server/execution-agent.ts` | reference (port pattern, rewrite prompts) | high |
| Multi-engine harness (lightweight) | boop | `boop/server/runtimes/index.ts`, `types.ts`, `claude.ts`, `codex-app-server.ts` | copy | med |
| Multi-engine harness (full) | harness/t3code | `harness/apps/server/src/provider/builtInDrivers.ts`, `provider/Drivers/*`, `provider/Layers/*Adapter.ts`, `provider/Services/ProviderInstanceRegistry.ts` | fork or reference | high |
| Codex app-server protocol client | harness/t3code | `harness/packages/effect-codex-app-server/` | copy (if Memoshi adopts Effect), else reference | high |
| ACP client (Gemini/OpenCode-style agents) | harness/t3code | `harness/packages/effect-acp/` | copy (if Effect) / reference | med |
| Memory (tiers, decay, extraction) | boop | `boop/server/memory/types.ts`, `extract.ts`, `clean.ts`, `tools.ts` | copy, then swap the Convex calls for Memoshi storage | high |
| Memory consolidation (proposer + judge) | boop | `boop/server/consolidation.ts` | copy | high |
| Embeddings with local fallback | boop | `boop/server/embeddings.ts` | copy | med |
| Routines / automations | boop | `boop/server/automations.ts`, `automation-tools.ts`, `timezone-config.ts` | copy, add a distributed lock | high |
| Proactive triggers | boop | `boop/server/proactive-email.ts`, `composio-webhook.ts` | reference | med |
| Connectors registry | boop | `boop/server/integrations/registry.ts`, `composio.ts`, `composio-routes.ts` | copy | high |
| Local Mac data (Messages/Notes/Reminders) | boop | `boop/server/apple/*`, `boop/server/privacy.ts` | copy | med |
| Local browser automation | boop | `boop/server/browser/`, `boop/server/browser-routes.ts` | reference | med |
| Approvals for external side effects | boop | `boop/server/draft-tools.ts` | copy | high |
| Approvals for code/tool actions | harness/t3code | `harness/packages/contracts/src/orchestration.ts` (`thread.approval.respond`, runtime modes), `harness/docs/user/permission-modes.md` | reference | high |
| Path guardrails | harness (Forma) | `harness/apps/server/src/workspace/WorkspaceProtectedPaths.ts`, `harness/packages/shared/src/protectedPaths.ts` | copy | med |
| Coding workspace core (event sourcing, checkpoints) | harness/t3code | `harness/apps/server/src/orchestration/`, `harness/apps/server/src/checkpointing/`, `harness/apps/server/src/vcs/` | fork (take upstream t3code, not Forma) | high |
| Turn queue / ask-plan modes / thread fork | harness (Forma) | `harness/apps/server/src/threadExtensions/ThreadExtensionService.ts`, `harness/apps/server/src/orchestration/threadForking.ts` | reference | med |
| Component preview | harness (Forma) | `harness/apps/server/src/componentPreview/` | reference | low |
| Bot roster (persistent identities) | neither; closest: Forma agent inventory | `harness/apps/server/src/project/ProjectAgentInventory.ts`, `harness/packages/contracts/src/localAgents.ts` | reference | low |
| Mobile / remote access | harness/t3code | `harness/apps/mobile/`, `harness/packages/client-runtime/`, `harness/packages/ssh/`, `harness/packages/tailscale/`, `harness/docs/internals/remote.md` | fork or reference | high |
| Hosted relay + push | harness/t3code | `harness/infra/relay/` | reference (needs own Clerk, APNs, Cloudflare) | med |
| Messaging channel (iMessage) | boop | `boop/server/sendblue.ts`, `sendblue-webhook-auth.ts`, `convex/sendblueDedup.ts` | reference (channel adapter pattern) | med |
| Observability / debug UI | boop | `boop/debug/src/components/*Panel.tsx`, `boop/desktop/src/*` (untracked GPUI port) | reference | med |
| Desktop shell | boop / harness | `boop/electron/main.cjs`, `harness/apps/desktop/` | reference | low |
| Forma UI chrome (icons, sidebar, settings) | harness (Forma) | `harness/apps/web/src/components/icons/custom/`, `harness/apps/web/src/components/settings/` | ignore | low |
| Vendored Effect reference repos | harness | `harness/.repos/` | ignore | low |
| Apple capability registry (risk, approval and location per operation; TS-to-Swift codegen) | Apollo | `apollo-agent/server/apple/platform/capability-registry.ts`, `types.ts`; `apollo-agent/scripts/generate-apple-capability-swift.ts` | port | high |
| Hash-bound approvals for native actions | Apollo | `apollo-agent/server/apple/platform/action-contract.ts`, `work-approval-binding.ts` | port | high |
| Draft commit protocol (intent before dispatch; unknown outcomes never retried) | Apollo | `apollo-agent/server/draft-tools.ts`, `apollo-agent/shared/approval-declaration.ts`, `apollo-agent/convex/drafts.ts` | port (Convex mutations become SQLite transactions) | high |
| Code Mode (capability-only script tool, nested calls as durable leaf tasks) | Apollo | `apollo-agent/server/pi/codemode.ts` | reference (Memoshi uses `pi-durable/codemode`, [D8](../../../plan/decisions.md#d8); borrow the leaf intent, unknown-outcome fence and alias guard) | high |
| Model-call receipts in a Pi Durable extension | Apollo | `apollo-agent/server/pi/dispatch.ts` | port | high |
| Pi embedding boundary (SDK in a disposable Worker with a scrubbed environment) | Apollo | `apollo-agent/server/pi/engine.ts`, `executor.ts`, `executor-worker.ts`, `executor-protocol.ts` | reference (skip the Convex `storage.ts`) | med |
| Routine leases, fencing and a no-write "shadow" tier | Apollo | `apollo-agent/server/automation-lease.ts`, `apollo-agent/shared/automation-contract.ts`, `apollo-agent/convex/automations.ts` | port | high |
| Delivery with explicit unknown outcomes | Apollo | `apollo-agent/server/channels/gateway.ts`, `apollo-agent/server/work-projection.ts` | reference | med |
| Memory provenance, recall that can abstain, adversarial consolidation | Apollo | `apollo-agent/server/memory/`, `apollo-agent/convex/memoryProvenance.ts`, `apollo-agent/convex/memoryRecords.ts`, `apollo-agent/server/consolidation.ts` | port (replace Convex with SQLite) | high |
| Mac native services (ScreenCaptureKit, Accessibility, Spotlight, Apple Events, LocalAuthentication) | Apollo | `apollo-agent/electron/macos/MacAssistanceServices.swift`, `MacAppleEvents.swift`, `MacOwnerAuthentication.swift` | copy (own Swift code) | high |
| Apple surfaces and data providers (App Intents, widgets, Spotlight, EventKit, Contacts, Foundation Models drafts) | Apollo | `apollo-agent/ios/ApolloClient/Sources/ApolloSystemSurfaces/`, `apollo-agent/ios/ApolloClient/Sources/ApolloClientUI/` (`AppleEventKitContextProvider.swift`, `AppleContactsContextProvider.swift`, `OnDeviceDraftAssistant.swift`), `apollo-agent/ios/ApolloApp/ApolloWidgets/` | port (the package manifest declares macOS 14) | high |
| Keychain broker (Secure Enclave key) | Apollo | `apollo-agent/scripts/macos/ApolloWorkerKeychain.swift`, `apollo-agent/server/worker/keychain.ts` | port | med |
| VM lifecycle on Virtualization.framework | Apollo | `apollo-agent/electron/macos-native/Sources/NativeEnergyVM/`, `apollo-agent/server/apple/native-energy-vm/` | reference for the Bot computer spike ([D17](../../../plan/decisions.md#d17), O2) | med |
| Mac data readers (`osascript`, `sqlite3`) | Apollo | `apollo-agent/server/apple/*-local.ts` | reference (Memoshi.app calls EventKit and Contacts natively) | low |
| Cloud plumbing (Convex, multi-tenant auth, Electron shell) | Apollo | `apollo-agent/convex/`, `apollo-agent/server/auth/`, `apollo-agent/electron/*.cjs` | ignore | low |
| App-to-daemon protocol schema | Draft 3 build | `Memoshi-Plan/packages/protocol/src/index.ts` | port with changes (generate Swift types from it) | high |
| Transport: replay, heartbeat, token and Origin checks | Draft 3 build | `Memoshi-Plan/sidecar/src/server.ts` (RPC and SSE handlers) | port with changes (one multiplexed stream, [D13](../../../plan/decisions.md#d13)) | high |
| Store and event log (each change and its numbered event in one transaction) | Draft 3 build | `Memoshi-Plan/sidecar/src/store/db.ts`, `migrations.ts`, `Memoshi-Plan/sidecar/src/events/types.ts` | port with changes (global sequence, pruning, snapshots, [D14](../../../plan/decisions.md#d14)) | high |
| Policy engine and durable approvals | Draft 3 build | `Memoshi-Plan/sidecar/src/policy/engine.ts`, `Memoshi-Plan/sidecar/src/approvals/service.ts` | port with changes (standing rules; nested, browser and VM calls, [D9](../../../plan/decisions.md#d9), [D27](../../../plan/decisions.md#d27)) | high |
| Workbench realpath guard and git helpers | Draft 3 build | `Memoshi-Plan/sidecar/src/workbench/service.ts` | port with changes (a real PTY) | med |
| App-side supervisor, RPC and event-stream clients | Draft 3 build | `Memoshi-Plan/apps/mac/Memoshi/Services/SidecarSupervisor.swift`, `RPCClient.swift`, `EventStream.swift` | port with changes (bundled Node; no silently dropped events) | med |
| Sandboxed artifact preview | Draft 3 build | `Memoshi-Plan/apps/mac/Memoshi/Views/ArtifactPreviewView.swift` | port with changes (keep JavaScript off and the existing CSP; add a navigation policy [INFERENCE]) | med |
| Smoke, chaos, kill-resume and snapshot harnesses | Draft 3 build | `Memoshi-Plan/scripts/` (`smoke.mjs`, `smoke.sh`, `chaos.mjs`, `kill-resume.sh`, `sse-check.mjs`), `Memoshi-Plan/apps/mac/Memoshi/App/SnapshotSupport.swift` | port with changes | high |
| Schedule, log, ids and bus utilities | Draft 3 build | `Memoshi-Plan/sidecar/src/routines/schedule.ts`, `log.ts`, `ids.ts`, `events/bus.ts` | copy | med |
| Pi event mapping, server orchestration, app state, views, theme | Draft 3 build | `Memoshi-Plan/sidecar/src/runtime/pi-durable.ts`, `sidecar/src/server.ts`, `Memoshi-Plan/apps/mac/Memoshi/Services/AppModel.swift`, `apps/mac/Memoshi/Views/`, `apps/mac/Memoshi/Design/Theme.swift` | reference | low |
| Host-direct agent tools, fake runtime, demo seed | Draft 3 build | `Memoshi-Plan/sidecar/src/tools/memoshi-tools.ts`, `sidecar/src/runtime/fake.ts`, `sidecar/src/demo/seed.ts` | ignore (drop, [D36](../../../plan/decisions.md#d36)) | low |

## 5. Risks

| Risk | Detail | Severity |
|---|---|---|
| License | Both are MIT, so copying is allowed if the copyright notices are kept: "Chris Raroque" for boop, "T3 Tools Inc." for harness. T3 Code, T3 Connect, and the T3 icons are brand assets; MIT does not cover trademarks [INFERENCE]. The fork ships production T3 Connect Clerk identifiers in `.env.example` ([t3-connect.md](https://github.com/pingdotgg/t3code/blob/a7b0366c/docs/internals/t3-connect.md)). A Memoshi product must not point at pingdotgg's relay or Clerk app [INFERENCE]. | med |
| Convex lock-in (boop) | Every state read and write goes through `convex/_generated/api` (14 tables, a vector index, reactive dashboard queries). The untracked GPUI port also binds to Convex directly (`convex 0.10.4`). The self-hosted backend is under the FSL-1.1 with an Apache-2.0 future license, not OSI open source ([get-convex/convex-backend LICENSE.md](https://github.com/get-convex/convex-backend), gh api 2026-10-20). Reusing memory and automations means rewriting the persistence calls. | high |
| Sendblue cost | boop's README says "free on their agent plan" ([README](https://github.com/raroque/boop-agent/blob/3197913/README.md)). Sendblue's own pricing page as of 2026-10-20 lists Free as a shared number with verified contacts only. The AI Agent plan is $100/line/month with a dedicated number and up to 1,000 inbound contacts/day. Outbound-first use needs custom Enterprise pricing ([sendblue.com/pricing](https://www.sendblue.com/pricing)). Per-user dedicated lines do not scale for a consumer app [INFERENCE]. Inbound also needs a public tunnel (ngrok). | high |
| Effect learning curve (harness) | All of the server, contracts, and client runtime use Effect 4 (beta.103 locally, 4.0.1 on the remote). Upstream's own AGENTS.md tells contributors to read `.repos/effect-smol/LLMS.md` and an Effect checklist before writing server code. Partial lifts are hard because services, layers, and RPC schemas cross every module [INFERENCE]. | high |
| Upstream churn (t3code) | Several nightlies a day. About 2.8k commits in the 30 days to 2026-10-20. 4,612 commits since the local snapshot. Forma pays for each sync with large manual merges (2,525 commits in one sync) and a skip policy file. A Memoshi fork of t3code would inherit this tax; picking a frozen tag or using it only as a reference avoids it [INFERENCE]. | high |
| Upstream stagnation (boop) | No push since 2026-07-13. Open PRs suggest current Codex models (newer than gpt-5.5) and Composio authorize flows may be broken on `main` (PR titles #82, #78, not verified). `@anthropic-ai/claude-agent-sdk ^0.1.0` is old. Expect to own maintenance. | med |
| Subscription-auth model | Both drive the user's local Claude Code / Codex CLI sessions instead of API keys. Fine for a personal tool. A commercial multi-user product would need to check provider terms and support API-key or hosted-engine paths [INFERENCE]. | med |
| Security posture (boop) | No user auth. Claude workers use `bypassPermissions`, so the only gate is the prompt-level dispatcher and draft rule. `chat.db` access needs Full Disk Access. Mitigations already present: localhost-only control routes, redaction, and webhook secret checks (`server/local-access.ts`, `server/privacy.ts`, `server/sendblue-webhook-auth.ts`). | med |
| Single-process scheduler (boop) | Double-fires when more than one instance runs ([ARCHITECTURE.md](https://github.com/raroque/boop-agent/blob/3197913/ARCHITECTURE.md)). Needs a lease or lock before any hosted deployment. | med |
| Unpushed local work | `boop/desktop/` (15.5k LOC Rust GPUI port) is untracked, and the `convex-*` skills are uncommitted. Both exist only on this disk and are lost if the disk fails or the checkout is cleaned. | med |
| Stale local clone (harness) | The local Forma checkout is 2,525 commits behind its own remote branch and predates the Effect 4.0.1 stable migration. Code read here can differ from current upstream. | low |
| Repo weight (harness) | About 13k vendored files in `.repos/`, 7 Forma migrations interleaved with upstream ones (935–941, including "ReconcileLegacyForkMigrationHistory"). Schema drift with upstream is a real merge hazard. | low |

No prompt-injection content was found in the files read. The `AGENTS.md` and `CLAUDE.md` files in both repos contain normal contributor instructions for coding agents; they were treated as data. boop's README contains affiliate/referral links and discount codes (plain marketing, not instructions).

<a id="apollo"></a>
## 6. Apollo (`~/Memo/apollo-agent`)

Appended 2026-10-20 for the Draft 4 plan. A read-only audit of the local checkout: local files, `git` metadata and line counts only. Nothing was built, installed or run, and `.env.local`, `backups/` and `data/` were not opened. Paths are relative to `~/Memo/apollo-agent` and were checked on disk; `file:line` references are at `main` = `2f001ecb`.

### Provenance and license

- Remote: `origin` = `github.com/mehmetcanbudak/Apollo-Agent`, a private repository that GitHub does not mark as a fork (gh api, 2026-10-20). `main` = `2f001ecb` "docs: reconcile current project state and release evidence" (2026-10-20 14:22 +0300). It is 0 ahead and 0 behind `origin/main` with a clean working tree, and has 2,457 tracked files. The package is `apollo-agent` 1.0.52 (`package.json:3`).
- License: MIT, "Copyright (c) 2026 Chris Raroque" (`LICENSE:3`). Apollo started as the user's copy of the boop template ([section 2](#2-boop)); its README calls the project a "fork-and-own template" (`README.md:673`), and the later commits are the user's. Code the user wrote can move under Memoshi's Apache-2.0 license; anything derived from boop keeps the MIT notice ([D33](../../../plan/decisions.md#d33)) [INFERENCE].
- Two prior research docs describe older Apollo states. The [2026-10-18 survey](../../prior/open-source-agent-bots-2026-10-18.md) inspected `~/Projects/TEM/apollo-agent` on Pi 0.74.0, and the [2026-10-17 session](../../prior/apollo-zeron-unpeel-2026-10-17.md) saw this checkout on Pi 1.1.0 at package 1.0.49. This section supersedes both on Apollo facts.

### What it is

- In its own words: "a daily-use personal assistant with authenticated iOS, macOS, iMessage, Telegram, and local dashboard surfaces. A Railway coordinator routes user-scoped work to Claude, Codex, or Pi runtimes; Convex stores durable tenant-owned state; paired Mac workers provide explicitly approved local capabilities" (`README.md:7`). `ARCHITECTURE.md:3` calls it a "distributed personal-assistant system".
- One singleton coordinator plus optional ingress replicas on Railway (`ARCHITECTURE.md:7-27`, `railway.json`). Paired Mac workers live in `server/worker/`. Third-party tools go through tenant-scoped Composio (`INTEGRATIONS.md:3`).

### Stack

- **Runtime:** Node 26.5.1 (`.nvmrc`; `engines.node` is `26.5.x`, `package.json:183`), Docker image `node:26.5.1-bookworm-slim`, Railway deploy with a `/readyz` health check.
- **State:**
  - Convex `^1.47.0` is the authority (`package.json:127`); self-hosting it is optional (`self-hosted/docker-compose.yml`).
  - Local stores: the Mac Knowledge vault (a `node:sqlite` catalog with age encryption, `server/knowledge/local-vault.ts`), an encrypted runtime-obligation journal (`server/runtime-accounting.ts:108`), and a SwiftData outbox on iOS (`docs/privacy.md:25`).
- **Engines:** Claude Agent SDK `^0.3.301` (`package.json:102`), Codex app-server (`server/runtimes/codex-app-server.ts`), and Pi (below). Embeddings from Voyage, OpenAI or a local Hugging Face model (`server/embeddings.ts`); OpenAI for transcription and vision; ElevenLabs for speech.
- **Channels:** Sendblue iMessage, Telegram (grammy), WhatsApp (the unofficial baileys library) and native iOS, behind one gateway (`server/channels/`).
- **Clients:**
  - SwiftUI `ios/ApolloApp`, with the app, widgets, a watch app and complications, and Share, Messages, MessageFilter, DeviceActivity and MailKit extensions.
  - All of it sits on the SwiftPM package `ios/ApolloClient`, which declares iOS 17, macOS 14 and watchOS 11 (`ios/ApolloClient/Package.swift:7-15`).
  - An Electron 44.8.0 companion with Swift helpers on the Mac, and a Vite debug dashboard (`debug/`).
- **Size (tracked files, `wc -l`):** `server/` about 81.8k TS lines in 852 files, 570 of them generated Codex protocol types; `convex/` about 48.3k; `ios/` about 99k Swift lines in 420 files; `electron/` about 11k JS lines plus 3.3k Swift; `test/` about 67k.
- **Tests:** 432 JS/TS test files (Vitest 5.0.5 with four projects, plus `node:test`) and 133 Swift test files.

### Pi usage

| Item | Finding |
|---|---|
| Versions | `package.json:106-112` pins `@earendil-works/chord`, `pi-agent-core`, `pi-ai`, `pi-codemode`, `pi-coding-agent`, `pi-durable` and `pi-mcp` at exactly `1.3.0`, and the same versions are installed. `pi-env` is not a dependency. `pi-agent-core` is declared but never imported |
| Harness | `Harness.open` with sequential tool execution, retries off and compaction budgets (`server/pi/engine.ts:238-247`); `root`, `configure`, `submit`, `wait`, `commit`, `usage`, `snapshot` and `watchEvents` (`engine.ts:248-274`) |
| Extension | `defineExtension` hooks `GenerationTask` `beforeRequest` and `CompactionTask` `beforeCompact` (`server/pi/dispatch.ts:392-428`). A `Models` wrapper records intent before I/O: "an acknowledged response may replay, uncertain I/O may not" (`dispatch.ts:143,338-372`) |
| Tools | Plain `ToolRegistration` objects (`server/pi/tools.ts:190-210`), filtered by allow and deny patterns (`tools.ts:88-94`, `server/runtimes/tool-policy.ts`). MCP through pi-mcp's `McpClient` (`server/integrations/mcp.ts:3`) |
| Storage | A custom `RpcPiStorage` (`server/pi/storage.ts:154`) backed by Convex (`convex/piDurable.ts:54-225`) with a fenced acquire, begin, stage and publish flow. Production has no SQLite mirror (`README.md:462`) |
| Isolation | The Pi SDK runs in a disposable Worker with a scrubbed, allowlisted environment, while the parent process owns tools and the storage RPC (`server/pi/executor.ts:16-33,58-59,98-161`). Frames are capped at 4 MiB (`executor-protocol.ts:23-24`) |
| Not used | `beforeTool`/`afterTool` (no matches in `server/`, `convex/`, `shared/` or `test/`); Pi subagents (Apollo has its own `spawn_agent`, `server/interaction-agent.ts:828`); `reset`; and the `pi-durable` subpaths `codemode`, `storage/sqlite`, `env`, `tools` and `tool-search` |

### Code Mode: `server/pi/codemode.ts`

Apollo's Code Mode is its own durable wrapper around upstream `pi-codemode`, not pi-durable's `createCodemodeExtension`.

- **Sandbox.** It exposes one tool, `apollo_code` (`:210`), and runs scripts in upstream `CodemodeSandbox` with `globals: []` (`:278`). Upstream runs a QuickJS WASM VM in a fresh `worker_threads` Worker for each run (`node_modules/@earendil-works/pi-codemode/dist/runtime/host.js`).
- **Capability-only.** A script can call only the turn's approved tools, plus `store`, `load`, `text()` and `image()`. The tool description says "No process, network, filesystem or ambient tools" (`:211`). An alias guard rejects tool names that collide across canonical, provider and QuickJS spellings (`:127-130`). Only execution and background turns get the tool (`tools.ts:211-216`).
- **Limits.** 32 calls, 120,000 characters of code, 60 seconds, 32 MiB of memory, 512,000 bytes of output and a 1 MiB store (`:16-20,228-231,302`).
- **Durability.**
  - The tool is `replay: "unsafe"` and sequential (`:218`).
  - Each nested call is its own Durable leaf task, `apollo.codemode.leaf`, owned by the parent task (`:252-254`). A leaf commits its intent before its one permitted dispatch (`:185-187`).
  - If recovery finds a leaf mid-execution, the outcome becomes unknown and the whole scope is fenced (`:190-194`).
  - Scripts are not replayed, and leaves that already ran are not rolled back when a script fails.
- **Policing.** `assertDispatchAllowed()` wraps every leaf and reaches the executor's `authorize()`, which rechecks the Convex fence (`codemode.ts:154,246,256,286`; `executor.ts:88-96,137`). Arguments are validated against each tool's JSON schema. Integration tools arrive already wrapped as draft-staging tools (`server/execution-agent.ts:228-243`), so a script can stage a draft but not send it [INFERENCE].
- **Results.** They are projected to text and receipt fields, truncated, and wrapped in `BEGIN/END UNTRUSTED TOOL-RESULT` markers (`codemode.ts:82-116`, `server/runtimes/instruction-boundary.ts:9-17`).

For Memoshi: [D8](../../../plan/decisions.md#d8) uses upstream `pi-durable/codemode`, which replays deterministic scripts against journaled nested calls, and [D9](../../../plan/decisions.md#d9) polices nested calls in `beforeTool`. Apollo's wrapper is a reference for what upstream does not provide: per-call intent records, an unknown-outcome fence, an alias guard and untrusted-result wrapping [INFERENCE].

### Apple integrations

| Capability | Where it runs | Paths |
|---|---|---|
| App Intents and Shortcuts | iOS | `ios/ApolloApp/ApolloApp/Sources/ApolloApp.swift:73`, `ios/ApolloClient/Sources/ApolloSystemSurfaces/ApolloSystemActions.swift:174-302`, `ios/ApolloClient/Sources/ApolloClientUI/SystemSurfaces/ApolloFocusAndEntityDonations.swift` |
| Widgets and Live Activities (ActivityKit, AlarmKit) | iOS, with pushes from the server | `ios/ApolloApp/ApolloWidgets/ApolloWidgets.swift`, `ios/ApolloApp/ApolloWidgets/ApolloLiveActivities.swift`, `server/channels/ios/live-activity-push.ts` |
| Calendar (EventKit) | Mac worker through an XPC helper; iOS | `server/apple/calendar-local.ts` and `scripts/macos/ApolloNativeXPCService.swift`; `ios/ApolloClient/Sources/ApolloClientUI/AppleEventKitContextProvider.swift` |
| Reminders | Mac worker through `osascript`; iOS through EventKit | `server/apple/reminders-local.ts`; `AppleEventKitContextProvider.swift` |
| Contacts | Mac worker: read-only `sqlite3` over `AddressBook-v*.abcddb`; iOS: the Contacts framework | `server/apple/contacts-local.ts`; `ios/ApolloClient/Sources/ApolloClientUI/AppleContactsContextProvider.swift` |
| Notes | Mac worker through `osascript`; the Electron host through Apple Events | `server/apple/notes-local.ts`; `electron/macos/MacAppleEvents.swift` |
| Messages | Mac worker reads `chat.db` read-only, which needs Full Disk Access; sending goes through Sendblue. iOS has Messages and SMS-filter extensions | `server/apple/messages-local.ts`; `ios/ApolloApp/ApolloMessageFilterExtension/ApolloMessageFilterExtension.swift` |
| Mail | A MailKit extension, also packaged for the Mac; Apple Events compose a visible draft | `ios/ApolloApp/ApolloMailKitExtension/ApolloMailKitExtension.swift`; `electron/macos/MacAppleEvents.swift` |
| Spotlight | CoreSpotlight on iOS, with no message bodies indexed; `mdfind` on the Mac | `ios/ApolloClient/Sources/ApolloClientUI/SystemSurfaces/ApolloSpotlightIndexer.swift`; `electron/macos/MacAssistanceServices.swift` |
| Notifications | APNs over HTTP/2 with a JWT; handlers on iOS and the Mac | `server/channels/apns.ts`; `ios/ApolloApp/ApolloApp/Sources/ApolloAppAssembly+Notifications.swift`; `electron/mac-notifications-handoff.cjs` |
| Foundation Models | iOS, for draft rewriting only | `ios/ApolloClient/Sources/ApolloClientUI/OnDeviceDraftAssistant.swift:85-113` |
| Speech | iOS transcription; a Mac media helper | `ios/ApolloClient/Sources/ApolloClientUI/SpeechTranscription.swift`; `scripts/macos/ApolloKnowledgeMedia.swift` |
| Health, location, HomeKit, CallKit | iOS | `ios/ApolloClient/Sources/ApolloClientUI/AppleHealthContextProvider.swift`, `AppleLocationContextProvider.swift`, `AppleExperiences/HomeKitExperience.swift`, `AppleVoIPCallCoordinator.swift` |
| ScreenCaptureKit, Accessibility, clipboard, Quick Look, LocalAuthentication | Mac native host inside the Electron companion | `electron/macos/MacAssistanceServices.swift`, `electron/macos/MacOwnerAuthentication.swift` |
| Keychain, with a Secure Enclave key and `AfterFirstUnlockThisDeviceOnly` | Mac worker helper | `scripts/macos/ApolloWorkerKeychain.swift:58-65`, `server/worker/keychain.ts` |
| Virtualization.framework | A SwiftPM module (about 1.1k lines, with tests) that validates an isolated `VZVirtualMachineConfiguration` and controls the VM lifecycle, bridged to Node | `electron/macos-native/Sources/NativeEnergyVM/`, `server/apple/native-energy-vm/` |

Two contracts tie these together. `shared/ios-native-tools.ts` lists 41 native tools. The capability registry (`server/apple/platform/capability-registry.ts`) declares risk, approval and location for each operation, and is generated into Swift as `ios/ApolloClient/Sources/ApolloClient/CapabilityCatalog.generated.swift` by `scripts/generate-apple-capability-swift.ts`. Approvals for Apple actions bind an immutable action hash (`server/apple/platform/action-contract.ts`, `work-approval-binding.ts`). Source support is not device acceptance: the [2026-10-17 session](../../prior/apollo-zeron-unpeel-2026-10-17.md) lists the permission, entitlement, hardware and foreground gates that remain.

### Patterns worth porting

- **Memory as evidence.** The exact phrase "memory is evidence, not authority" does not occur in Apollo. It is the wording of section E of the [2026-10-17 blueprint](../../prior/apollo-zeron-unpeel-2026-10-17.md). Apollo implements the idea:
  - evidence rows per memory: a `memoryEvidence` table (`convex/schema.ts:658`), at most 32 rows per memory (`convex/memoryRecords.ts:422`);
  - grounded recall that can abstain (`server/memory/search.ts:139`);
  - "A memory is supporting evidence, not an image gallery" (`convex/memoryRecords.ts:28`);
  - consolidation prompts that call memories "untrusted user data" (`server/consolidation.ts:18-19`).
- **Consolidation.** A proposer, an adversary and a judge, none with tools. Proposals are validated against the memory IDs that were loaded (`server/consolidation.ts:101-104,149,257-259`). boop's version has only a proposer and a judge ([section 2](#2-boop)).
- **Draft commit protocol.**
  - Staging requires a declared target, risk and reversibility (`server/draft-tools.ts:620-700`, `shared/approval-declaration.ts`).
  - Commit is a sequence (`server/draft-tools.ts:318-512`, `convex/drafts.ts:207-449`): compare-and-set acquire, persist the dispatch ID, call the provider, then record and settle.
  - An unknown outcome is never retried.
- **Automation leases.** `AutomationLeaseGuard` has the states active, lost, uncertain, cancelled and stopped (`server/automation-lease.ts`). Leases are fenced in Convex (`convex/automations.ts`), and a "shadow" tier runs with no write authority (`shared/automation-contract.ts`).
- **Delivery.** History is written before delivery (`ARCHITECTURE.md:106-107`). A send that throws is recorded as `unknown` (`server/channels/gateway.ts:287-290,386-387`), and the owner is asked to confirm it (`server/work-projection.ts:78-94`).
- **Accounting.**
  - Runtime obligations go to an encrypted crash journal (`server/runtime-accounting.ts:108`).
  - Usage snapshots replace each other instead of being summed (`:529`).
  - The default capacity is 200 turns per 24 hours (`server/quotas/turn-capacity.ts:76-79`).
- **Privacy.** Phone and email redaction (`server/privacy.ts`), a log auditor (`server/privacy/log-audit.ts`), and a retention table (`docs/privacy.md`).

### Mapping to Memoshi

| Memoshi capability | Apollo coverage |
|---|---|
| Personal assistant | Strong: the whole product, with boop's dispatcher-and-worker split |
| Bot roster | None: one assistant plus ephemeral workers spawned with `spawn_agent` [INFERENCE] |
| Routines | Strong: leased, fenced automations with a shadow tier, plus the proactive email path |
| Memory | Strong: evidence-backed recall that can abstain, and adversarial consolidation |
| Connectors | Strong: tenant-scoped Composio and pi-mcp |
| Coding workspace | Weak: coding work goes through the Codex and Claude runtimes, and the 2026-10-17 session found no embedded terminal in Apollo's product surfaces |
| Apple integrations | The strongest of all audited assets: iOS and watchOS surfaces, a Mac native host, and a capability registry with Swift codegen |
| Approvals and drafts | Strong: hash-bound approvals, a draft commit protocol and explicit unknown outcomes |
| Pi Durable | Real: Harness turns, durable leaf tasks and model-call receipts, on Convex storage, without `beforeTool`/`afterTool` |
| Computers and browsers | Partial: boop's local browser module (`server/browser/`), paired Mac workers as capability hosts, and the VM module above; no computer per bot [INFERENCE] |

### Risks

| Risk | Detail | Severity |
|---|---|---|
| Convex lock-in | Every domain is a Convex mutation, with about 48k lines in `convex/`, and the Pi Durable storage adapter is Convex-specific (`server/pi/storage.ts`, `convex/piDurable.ts`). The patterns transfer; the code does not | high |
| Subscription auth | Apollo drives Claude Code, `codex login` and Pi `/login` sessions (`README.md:174-180`), and `ModelRuntime` reads file-backed auth (`server/pi/models.ts:196-206`). [D10](../../../plan/decisions.md#d10) forbids shipping Pi's Anthropic, Google or Meta subscription OAuth paths, so none of this is ported | high |
| Hosted multi-tenant design | An owner `userId` on every row, five-minute ES256 actor tokens, App Attest and passkeys, Composio identities `apollo:<userId>`, capacity windows and a singleton coordinator (`ARCHITECTURE.md`, `INTEGRATIONS.md:18-22`). Memoshi is single-user and local | med |
| Unofficial WhatsApp | The baileys library, with earlier security findings (`plans/021-close-critical-security-and-account-boundaries.md:48-49`). [D37](../../../plan/decisions.md#d37) excludes WhatsApp | med |
| Permission scope | The `osascript` and `sqlite3` readers need Automation and Full Disk Access granted to the Node process. Memoshi.app should call EventKit and Contacts natively instead [INFERENCE] | med |
| Node version | Apollo targets Node 26.5.x. Memoshi bundles one pinned Node ([D15](../../../plan/decisions.md#d15)), so check version-specific APIs when porting [INFERENCE] | low |
| Electron | Only the Swift parts of the companion are useful to a native app | low |

Agent-directed instructions found and not followed (treated as data; reported as possible prompt injection):

- `.claude/skills/convex-improve-convex-plugin/SKILL.md:14`, duplicated under `.agents/skills/`, tells agents to run `curl -fsSL "<anteater>/send-transcript" | bash` to upload the coding-session transcript. The skill text says this step is consent-gated. Memoshi should not import this skill.
- `CLAUDE.md:5-11` and `AGENTS.md:5-11` contain Convex boilerplate telling agents that a rules file overrides what they have learned, and to run `npx convex ai-files install`.

<a id="draft-3-build"></a>
## 7. Draft 3 build (`~/Documents/Memoshi-Plan`)

Appended 2026-10-20 for the Draft 4 plan. This section records the read-only audit of the Draft 3 code made on 2026-10-20. Sizes and `file:line` anchors were re-checked on disk for this write-up; nothing was built or run. Paths are relative to `~/Documents/Memoshi-Plan`.

### Provenance

- A local git repository with no remote. It has three commits, all on 2026-10-20 (+0300): `181a939` "Phase 0 foundation and Phase 1 workbench" (04:34), `edfd33c` "Phase 1.1 polish and Phase 2 team core" (05:42) and `3570e71` "Phase 3 artifact gallery and read-only preview" (06:01).
- The audit covers the working tree: `3570e71` plus 26 uncommitted entries (21 modified files and 5 untracked, including `apps/mac/Memoshi/Views/GroupEditorView.swift` and `HandoffSheet.swift`).
- It is our own code. The plan pack around it (`MASTER_PLAN.md`, `docs/`, `specs/`) is superseded by [this repo's plan](../../../plan/MASTER_PLAN.md) (see the [mapping from Draft 3](../../../plan/decisions.md#mapping-from-draft-3)), and the code is not continued ([D36](../../../plan/decisions.md#d36)).

### Shape and size

| Part | Path | Size | Tests |
|---|---|---|---|
| Mac app (SwiftUI) | `apps/mac/Memoshi/`, project in `apps/mac/project.yml` | 31 Swift files, about 11.5k LOC. `Services/AppModel.swift` is 1,716 lines and makes every sidecar call | None |
| Sidecar (Node) | `sidecar/src/` | 19 files, about 5.9k LOC. Pins `@earendil-works/pi-durable`, `pi-ai` and `chord` at 1.3.0 | 35 tests in 7 files under `sidecar/test/` |
| Protocol | `packages/protocol/src/index.ts` | 683 lines of Zod | `sidecar/test/protocol.test.ts` |
| Harnesses | `scripts/smoke.mjs`, `smoke.sh`, `chaos.mjs`, `kill-resume.sh`, `sse-check.mjs`, `SSEReader.swift`; snapshot capture in `apps/mac/Memoshi/App/SnapshotSupport.swift` | | End-to-end checks |

The Swift protocol models (`apps/mac/Memoshi/Models/ProtocolModels.swift`) are hand-copied from the Zod package and have already drifted from it.

### Runtime, transport and storage

- **Launch.**
  - The app looks for a system Node: `MEMOSHI_NODE`, then `/opt/homebrew/bin/node`, then `/usr/local/bin/node` (`apps/mac/Memoshi/Services/SidecarSupervisor.swift:278-283`). It runs the repo's own `sidecar/dist/index.js` (`:336-347`).
  - The esbuild bundle marks `@earendil-works/*` as external (`sidecar/package.json:10`), so the Pi packages never enter the bundle and the build cannot ship ([D15](../../../plan/decisions.md#d15)).
- **Transport.**
  - HTTP JSON-RPC on `POST /rpc` plus server-sent events on `GET /events?sessionId&after` (`sidecar/src/server.ts:467,473`), bound to `127.0.0.1`.
  - A bearer token (`:499`), an Origin check that admits only a missing Origin, `null` or `memoshi://app` (`:439-441`), and a 15-second heartbeat (`:1556-1566`).
  - Only the selected session streams. The app refreshes the other sessions and the routines by polling every 12 seconds (`apps/mac/Memoshi/Services/AppModel.swift:420-426`) ([D13](../../../plan/decisions.md#d13)).
- **Storage.**
  - `state.db` on `node:sqlite`, with 15 tables (`sidecar/src/store/migrations.ts`).
  - Each change and its numbered event commit in one `BEGIN IMMEDIATE` transaction that bumps a per-session sequence (`sidecar/src/store/db.ts:338-347`).
  - Every transcript is also kept in a per-session Pi SQLite file (`sidecar/src/runtime/pi-durable.ts:174`), so transcripts are stored twice ([D7](../../../plan/decisions.md#d7)).
- **Pi Durable usage.**
  - Only `Harness.open`, `root`, `submit`, `abort`, `resume`, `watchEvents`, `defineExtension` and `defineTool` are used. Code Mode, MCP, `pi-env`, built-in tools, hooks, subagents, the task graph and `configure` are not.
  - The model is Pi's fake provider, hard-wired: `fauxProvider` in `sidecar/src/runtime/pi-durable.ts:5-8,175-178`, and the seeded agent's model is `faux/faux-1` (`sidecar/src/demo/seed.ts:112`). No real LLM ever ran.
  - Agent model and effort settings are saved but never used.

### Policy, approvals and routines

- Risk levels come from regular expressions, with a list of always-denied commands (`sidecar/src/policy/engine.ts`).
- Approvals are durable and keyed by session and tool call. They expire after 10 minutes (`MEMOSHI_APPROVAL_TIMEOUT_MS`, `sidecar/src/config.ts:86-87`), and there is no "Always allow".
- Routines tick on a 30-second timer inside the sidecar (`sidecar/src/server.ts:327-328`), so they run only while the app is open ([D12](../../../plan/decisions.md#d12)).

### Defects

| Defect | Where | Draft 4 answer ([feature IDs](../../../plan/feature-catalog.md)) |
|---|---|---|
| In auto mode, the seeded agent can overwrite `src/greet.js` in any opened folder | Seed agent at `sidecar/src/demo/seed.ts:111-115`; scripted fake tool call at `sidecar/src/runtime/pi-durable.ts:440-441` | Drop the seed and the fake runtime ([D36](../../../plan/decisions.md#d36)); the new sample project never touches files outside its own folder (ON-09) |
| `read_file` bypasses policy and the secret-file check | `sidecar/src/tools/memoshi-tools.ts:60-74` | One policy engine on `beforeTool`/`afterTool` for every call, nested ones included ([D9](../../../plan/decisions.md#d9); SEC-01) |
| The tool path guard misses symlink escapes: `resolveInside` compares `path.resolve` strings, not real paths | `sidecar/src/tools/memoshi-tools.ts:27-37` | Port the workbench guard, which resolves real paths (`sidecar/src/workbench/service.ts:96-108`), and enforce paths in the computer's sandbox too ([D16](../../../plan/decisions.md#d16); SEC-12) |
| Permission edits do not reach open sessions. Instruction and memory edits likely never apply, because `root()` options apply only at creation | `sidecar/src/runtime/pi-durable.ts` | Render identity, instructions, memory and grants into every request ([D7](../../../plan/decisions.md#d7); BOT-04) |
| Restarts likely reorder entries, events are never pruned, and the context meter is misleading | `sidecar/src/store/`, `sidecar/src/runtime/pi-durable.ts`, app views | One event log with a global sequence, pruning and snapshots ([D13](../../../plan/decisions.md#d13), [D14](../../../plan/decisions.md#d14); SH-03), and a context meter within 5% of provider usage (CH-14) |
| Hardened runtime and App Sandbox are off | `apps/mac/project.yml:35`; `apps/mac/Memoshi/Memoshi.entitlements:5-6` | Hardened runtime, signing and notarization ([D15](../../../plan/decisions.md#d15), [D32](../../../plan/decisions.md#d32); DIST-01, DIST-02); entitlements are settled in [09-platform-macos.md](../../../plan/09-platform-macos.md) |
| Dark mode is forced, and no Liquid Glass APIs are used | `apps/mac/Memoshi/Views/RootView.swift:31` | A native look in light and dark, with Liquid Glass for chrome only ([D29](../../../plan/decisions.md#d29), [D31](../../../plan/decisions.md#d31); SH-04, AP-01) |
| Swift protocol models are hand-copied and have drifted; there are no Swift tests | `apps/mac/Memoshi/Models/ProtocolModels.swift` | Generate Swift types from the protocol package (SH-02) |

### Reuse verdicts

| Verdict | What | Paths | Change needed ([feature IDs](../../../plan/feature-catalog.md)) |
|---|---|---|---|
| Port with changes | Protocol package | `packages/protocol/src/index.ts` | Generate the Swift types from it instead of copying them by hand (SH-02) |
| Port with changes | Transport: replay, heartbeat, auth | `sidecar/src/server.ts` (RPC and SSE handlers) | One stream for all conversations, as JSON-RPC over a WebSocket on a Unix socket ([D13](../../../plan/decisions.md#d13); SH-02, SH-03) |
| Port with changes | Store and event pattern | `sidecar/src/store/db.ts`, `migrations.ts`, `sidecar/src/events/types.ts` | A global sequence, pruning and snapshots; transcripts only in Pi storage ([D7](../../../plan/decisions.md#d7), [D14](../../../plan/decisions.md#d14); SH-03) |
| Port with changes | Policy and approvals, the strongest part of the build | `sidecar/src/policy/engine.ts`, `sidecar/src/approvals/service.ts` | Standing rules ("Always allow next time"), and coverage of nested Code Mode, MCP, browser and VM calls ([D9](../../../plan/decisions.md#d9), [D27](../../../plan/decisions.md#d27); SEC-01, SEC-04, SEC-05) |
| Port with changes | Workbench realpath guard and git helpers | `sidecar/src/workbench/service.ts` | A real PTY for the terminal (TP-01); the realpath check on every file tool (SEC-12); git status (PR-07) |
| Port with changes | Supervisor, RPC and event-stream clients | `apps/mac/Memoshi/Services/SidecarSupervisor.swift`, `RPCClient.swift`, `EventStream.swift` | Launch the bundled Node; stop silently dropping events that fail to decode (SH-01, SH-03, DIST-01) |
| Port with changes | Artifact preview | `apps/mac/Memoshi/Views/ArtifactPreviewView.swift` | Keep JavaScript off (`allowsContentJavaScript = false`, `:286`) and the injected CSP (`default-src 'none'`, `:300`). Add a navigation delegate, since none exists and a meta refresh or link could navigate the preview away [INFERENCE] (TP-06) |
| Port with changes | Smoke, chaos and snapshot harnesses | `scripts/smoke.mjs`, `smoke.sh`, `chaos.mjs`, `kill-resume.sh`, `sse-check.mjs`, `SSEReader.swift`; `apps/mac/Memoshi/App/SnapshotSupport.swift` | Retarget them to the new protocol and a real model [INFERENCE]; they back the chaos exit criteria of SH-03 and CH-11 |
| Reuse as-is | Schedule, log, ids and bus utilities | `sidecar/src/routines/schedule.ts`, `sidecar/src/log.ts`, `sidecar/src/ids.ts`, `sidecar/src/events/bus.ts` | None |
| Reference only | Pi event mapping, server orchestration, `AppModel`, views and theme | `sidecar/src/runtime/pi-durable.ts`, `sidecar/src/server.ts`, `apps/mac/Memoshi/Services/AppModel.swift`, `apps/mac/Memoshi/Views/`, `apps/mac/Memoshi/Design/Theme.swift` | Rewritten for Draft 4 |
| Drop | Host-direct agent tools, the fake runtime, the demo seed | `sidecar/src/tools/memoshi-tools.ts`, `sidecar/src/runtime/fake.ts`, `sidecar/src/demo/seed.ts` | None ([D36](../../../plan/decisions.md#d36)); coding tools run only in the session's computer (CODE-01) |

### Risks

| Risk | Detail | Severity |
|---|---|---|
| Porting defects with the code | The weak tool path guard and the `read_file` bypass sit next to code we port. Port by the verdict table, not by copying directories [INFERENCE] | med |
| Untested Pi paths | Nothing in the build ever ran a real model, Code Mode, MCP or hooks, so its 35 tests say nothing about those paths | med |
| Local-only history | No remote, and 26 uncommitted entries, including two untracked Swift views, exist only on this disk | low |

No prompt-injection content was found in the Draft 3 files read.

## 8. Open questions and sources for sections 6 and 7

### Open questions

1. Does Apollo's `ios/ApolloClient` package build and pass its tests on macOS 27? Its manifest declares macOS 14; nobody has built it for the Mac app.
2. Does upstream `pi-durable/codemode` cover what Apollo's wrapper adds (per-call intent records, the unknown-outcome fence, the alias guard), or should Memoshi's policy engine add them in `beforeTool` and `afterTool` ([D9](../../../plan/decisions.md#d9))? Check in Phase 0.
3. Should Memoshi's SQLite storage borrow Apollo's fenced acquire, begin, stage and publish flow, or rely on pi-durable's single owning process ([D14](../../../plan/decisions.md#d14))?
4. Is Apollo's Virtualization.framework module a useful starting point for the Bot computer spike ([D17](../../../plan/decisions.md#d17), O2)?
5. Do Draft 3's 35 sidecar tests still pass against Pi 1.3.0 with a real model?

### Sources

- Apollo: local checkout `~/Memo/apollo-agent` at `2f001ecb` (clean); `README.md`, `ARCHITECTURE.md`, `INTEGRATIONS.md`, `LICENSE`, `package.json`, and the files cited above. Repository metadata: `gh api repos/mehmetcanbudak/Apollo-Agent` (2026-10-20).
- Draft 3 build: local repository `~/Documents/Memoshi-Plan` at `3570e71` plus its working tree; the files cited above.
- Prior research: [2026-10-18 survey](../../prior/open-source-agent-bots-2026-10-18.md); [2026-10-17 session](../../prior/apollo-zeron-unpeel-2026-10-17.md).
