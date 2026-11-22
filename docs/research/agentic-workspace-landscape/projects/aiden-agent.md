# Aiden Agent

> MIT-licensed Electron desktop workspace (macOS + Linux) that embeds Mario Zechner's Pi agent runtime in-process, adds Grok-style durable Bots with Hermes-style memory and routines, Telegram control, and native iOS/Android remote clients that drive the desktop over LAN or Tailscale. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

Repo links below point at `main` of [sambitcreate/aiden-agent](https://github.com/sambitcreate/aiden-agent) as of commit `126c2dd` (2026-10-20).

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Aiden Agent
slug: aiden-agent
category: agent-workspace-ide   # workspace-first desktop app; Grok-style Bot roster added in 0.55.0 (2026-10-09)
maker: Sambit Biswas (GitHub sambitcreate), solo; self-described non-coder building with coding agents
license: MIT
repo: https://github.com/sambitcreate/aiden-agent
website: https://chatwithaiden.com (still describes the older SwiftUI menu-bar client; download links point to the Electron beta)
first_public: 2026-07-18   # repo created; first GitHub release v0.27.23 on 2026-07-25
latest_release: v0.58.0, 2026-10-19
release_cadence: "~4.8 releases/week overall (62 releases 2026-07-25..2026-10-19); ~2.6/week in October"
stars: 85 (as of 2026-10-20)
forks: 4 (as of 2026-10-20)
contributors: 5 incl. bots (sambitcreate 3,940 commits; claude 77; github-actions 75; cursoragent 49; devin-ai-integration 6) (as of 2026-10-20)
primary_language: TypeScript
stack: "Electron 43, React 19, Vite 8, Tailwind, TanStack Router/Query, Radix; Pi 1.3.0 (pi-agent-core, pi-ai, pi-durable, chord, pi-codemode); SQLite (Bots); Rust (Computer Use broker, helpers); SwiftUI iOS; Kotlin Android"
platforms: [macos, linux, ios, android]   # macOS arm64 DMG; Linux x64/arm64 AppImage/deb/rpm; iOS via TestFlight only; Android debug APK
agent_engine: embeds SDK (Pi pi-agent-core Agent via own PiAgentRuntimeHarness; Pi Durable Harness per Bot) + wraps ACP agents (Google Antigravity)
engines_supported: [pi, raw-api, antigravity-acp]
model_access: API keys (Pi's 36 built-in providers), subscription OAuth (ChatGPT/Codex; Google Antigravity plan via ACP), local models (Ollama, LM Studio, Apple Foundation Models), custom compatible endpoints
execution_env: user host (Electron main process; per-Bot managed home folder, not a sandbox)
per_bot_computer: no (each Bot gets a hidden managed home directory on the user's machine; explicitly "not a sandbox in Full mode")
persistent_bots: yes (since 0.55.0; name, subtitle, character, photo, instructions "soul", routines, one durable conversation per Bot)
memory: per-Bot bounded MEMORY.md + USER.md (64 entries each) via main-owned bot_memory tool, threat-scanned, frozen per-session snapshot, background review every 10 turns; separate scoped SQLite MemoryStore for workspace chats
routines: yes (croner scheduled tasks, llm or script mode; per-Bot routines; Bot-proposed routines need approval; [SILENT] replies; catch-up after pause)
group_chat: no (rooms and message_agent are a separate, unshipped track)
coding_workspace: yes (folders, scratch, managed git worktrees, terminal drawer, diffs, commit/push, external editor, native subagents incl. implementer)
browser_use: yes (shared Electron browser tabs in Environment panel; agent browser tools act on the same tabs)
computer_use: partial (macOS-only opt-in beta: pinned Cua cua-driver 0.34.1 behind an authenticated Rust broker)
connectors: MCP (incl. OAuth) + 66-entry plugin catalog (Composio, Gmail, Google Calendar, Notion, Slack, Outlook, GitHub, Linear, Figma ...) + Exa web search
channels: Telegram (workspace remote control and per-Bot binding); desktop/phone notifications
mobile: yes (Aiden On The Go: native iOS/iPadOS (TestFlight) and Android clients; desktop remains authority)
voice: yes (Aiden Live: Gemini Live duplex voice + optional screen share; on-device Parakeet dictation; Telegram voice replies)
approvals: workspace Full/Ask/None (+ Read-only) per folder; Ask cards per write/shell/web/MCP; Bot Full (default) or Custom grants; per-chat Computer Use access card; least-privilege intersection for remote devices
e2e_encryption: no app-level E2E; LAN uses pinned per-install P-256 TLS, Tailscale path uses tailnet encryption plus per-device credentials
self_host: yes (desktop app is the host; no Aiden cloud)
multi_user: no (single owner; multiple paired phones and paired computers of the same owner)
pricing: free, BYO model keys/subscriptions; no paid tier found
maturity: beta (README "beta desktop release"; Intel Mac build not yet published; several features flagged experimental)
```

## What it is

Aiden Agent is "a native-feeling desktop workspace for chatting with local or hosted AI models and safely working inside the folders you choose" ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)). The repo description widens the audience: "Pi based agent for Designers, Coders and Everyday users" ([GitHub API](https://api.github.com/repos/sambitcreate/aiden-agent), as of 2026-10-20).

Mental model: a Codex-desktop-style chat workspace whose agent is Pi, plus a second mode, **Bots**, that behaves like contacts in a messenger (one persistent conversation per Bot, routines, Telegram binding) and was explicitly modelled on Grok Bots screenshots and on Rakazo ([bots rework design §2](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-07-bots-rework-design.md)). The desktop is the single authority for files, credentials, execution and memory; phones and other computers are remote controls ([PRODUCT.md](https://github.com/sambitcreate/aiden-agent/blob/main/PRODUCT.md)).

Maker's story: the author writes "I don't come from a coding background", liked Codex's desktop UX, opencode's provider freedom, Cursor's nimbleness and Claude Code's models, but kept returning to Pi for its plugin system, which "lacked a GUI". A first native SwiftUI version was abandoned after two weeks as "the wrong fight for someone who doesn't already write code"; the project pivoted to Electron after recreating it in Raycast's Glaze, running out of credits within an hour, and using Codex to extract the code ([README "Why Aiden"](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)). The git history bears this out: branches named `claude/project-thread-*` and commit authors `claude`, `cursoragent` and `devin-ai-integration` ([commits API](https://api.github.com/repos/sambitcreate/aiden-agent/commits), [contributors API](https://api.github.com/repos/sambitcreate/aiden-agent/contributors), as of 2026-10-20). The repo carries `AGENTS.md`, `CLAUDE.md` and a 200-file `.memory/` directory of agent-maintained engineering notes ([tree](https://github.com/sambitcreate/aiden-agent/tree/main/.memory)).

## Product and UX

- **Workspace chat**: pick a folder, scratch workspace or managed worktree with an access level; the composer has `/` app commands and `$` skill invocation; `Cmd-K` palette; busy composer offers Steer/Queue ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md), [busy controls](https://github.com/sambitcreate/aiden-agent/blob/main/docs/chat-composer-busy-controls.md)). The Environment panel holds files, diffs, terminal, browser, Simulator, Subagents and (since 2026-10-19) Artifacts tabs ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)).
- **Model Pad**: a personal "capability-and-pace map" of models, optionally enriched with Artificial Analysis scores through a benchmark-only OpenRouter key kept separate from inference credentials ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)).
- **Bots** (0.55.0, 2026-10-09): Bots sidebar on desktop, list on phones; first run is a "Meet your first Bot" carousel of presets; create is two steps (name, "What should it help with?", then optional connect-now chips); chat has a name pill opening Profile (photo, character colour+shape, Instructions, Routines) and an Advanced page (model, image model, Full/Custom access, chat-activity verbosity, Telegram binding). Delete replaces Archive ([bots-rework-ui note](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/bots-rework-ui.md), [design §3-4](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-07-bots-rework-design.md)). Design goal in the owner's words: "simple enough for 'my mom'" ([design §1](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-07-bots-rework-design.md)).
- **Connect cards**: a Bot-only `suggest_connection({pluginId, reason})` tool posts a typed "Connect {name}" card; "Not now" suppresses that plugin for that Bot; on phones the button says "Finish on your Mac" because credentials stay on the desktop ([design §7](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-07-bots-rework-design.md)).
- **Recovery is explicit**: an interrupted Bot turn shows a Resume button rather than restarting automatically ([design §1, §6.4](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-07-bots-rework-design.md)).
- **Aiden Live**: a blue orb starts an explicit voice session with listening/thinking/speaking/approval states; first use walks through model access, microphone and Screen & Accessibility permissions ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)).
- **Workspace artifacts**: "make me an artifact that shows the open PRs" produces a persistent page in Aiden UI Markup with `shell`/`file` data sources (max 8 sources/page, 20 pages/workspace, 30 s and 256 KiB per source), refresh on show/interval (>=60 s), and buttons that `sendPrompt`, `compose`, or run approved commands. Desktop only ([workspace-artifacts.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/workspace-artifacts.md); merged [PR #554](https://github.com/sambitcreate/aiden-agent/pull/554) 2026-10-19).
- **Simulator devices**: Environment Simulator tab streams and controls iOS Simulators and Android Emulators locally, on a paired Mac or an SSH host, with an optional 3D device body and consent-gated `device_*` agent tools; adapted from T3 Code (MIT); on by default on macOS since 0.55.0 ([devices.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/devices.md), [plans index](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/README.md)).
- **Design Studio / Create Images**: default-off flags `AIDEN_EXPERIMENTAL_DESIGN_STUDIO` / `AIDEN_EXPERIMENTAL_CREATE_IMAGES`; ADR status "Proposed"; a design project owns one hidden chat reusing the normal `llmClient.start` pipeline; the former "Designer Mode" (select UI in a local Vite app, request a bounded change, review the diff) becomes phase DS-4 ([README Upcoming](https://github.com/sambitcreate/aiden-agent/blob/main/README.md), [design-studio-adr.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/design-studio-adr.md)).

## Architecture

Components (from the README diagram, [README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)):

```text
React renderer --(allowlisted context bridge)--> Electron preload --(typed IPC)--> Electron main
  main: Pi agent + model adapters; workspace tools, Git, terminal; encrypted credentials + JSON stores;
        MCP, attachments, search, voice; hardened native helpers (Rust/Swift)
```

**Tech stack**: Electron 43, React 19, TypeScript 5, Vite 8, Tailwind, TanStack Router/Query, Radix, `node-pty`, `sherpa-onnx-node` (on-device speech), `@google/genai`, `@modelcontextprotocol/sdk` 1.30.0, `@agentclientprotocol/sdk` 1.7.0, `croner` ([package.json](https://github.com/sambitcreate/aiden-agent/blob/main/package.json)). Native helpers under `native/` include `computer-use-broker` (Rust), `apple-foundation-models`, `secret-service-authority`, `lease-flock`, `subagent-shell-runner`, `subagent-file-mutator`, `worktree-remover` ([tree](https://github.com/sambitcreate/aiden-agent/tree/main/native)).

### How Pi is embedded

| Package (exact pin, [package.json](https://github.com/sambitcreate/aiden-agent/blob/main/package.json)) | Used for |
| --- | --- |
| `@earendil-works/pi-agent-core` 1.3.0 | Low-level `Agent` loop for foreground chats and subagents |
| `@earendil-works/pi-ai` 1.3.0 | Provider registry (`builtinModels()`), streaming, credentials |
| `@earendil-works/pi-durable` 1.3.0 + `@earendil-works/chord` 1.3.0 | One durable SQLite-backed `Harness` per Bot |
| `@earendil-works/pi-codemode` 1.3.0 | Code-mode tool calling in a `CodemodeSandbox` |
| `@aiden/pi-legacy-harness` = alias of `pi-agent-core@0.87.1` | Frozen legacy journal compaction (`compact`, `generateBranchSummary`) |

Pi lives at [earendil-works/pi](https://github.com/earendil-works/pi) (the old `badlogic/pi-mono` URL redirects there; MIT; 116,531 stars; v1.3.0 released 2026-10-15, as of 2026-10-20). Aiden shipped the 1.3.0 upgrade four days later in v0.58.0 ([PR #505 in release notes](https://github.com/sambitcreate/aiden-agent/releases/tag/v0.58.0)). The desktop app does **not** depend on `pi-coding-agent`; only the separate CLI does (below). An older plan still says the app embeds `pi-coding-agent` behind `llmClient` ([telegram plan, 2026-08-11](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/telegram-remote-control-plan.md)); the current manifest shows that has been dropped from the desktop app.

- **In-process, in Electron main.** `PiAgentRuntimeHarness` ([main/services/pi-agent-runtime-harness.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/pi-agent-runtime-harness.ts), ~123 KB) imports `Agent`, `runToolCall` and the before/after-tool hook types from `pi-agent-core` and wraps them. Construction is through [main/services/generation-harness.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/generation-harness.ts). The design rationale: Pi's public `AgentHarness` could not resume Aiden's journaled durable tail, lacked global sequential tool execution and between-tool compaction, so Aiden adapts Pi's low-level `Agent` and treats the adapter as "the future migration seam" ([pi-runtime-harness-plan.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/pi-runtime-harness-plan.md)). Effectful tool batches are forced sequential although Pi defaults to parallel; tool plans are made durable before execution; terminal outcomes are a closed union `completed | app_cancelled | provider_failed | host_failed` (same doc).
- **Pi's extension loader is not exposed.** Pi packages are re-hosted as libraries; e.g. `pi-telegram` was ported, not installed, because "Aiden does not expose Pi's extension loader" ([telegram plan](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/telegram-remote-control-plan.md)). Trusted contributions go through a process-owned registry (`PiAgentRuntimeExtensionRegistry`) snapshotted per run ([harness plan](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/pi-runtime-harness-plan.md)).
- **Bots on Pi Durable.** [main/services/bot-runtime/harness-host.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/bot-runtime/harness-host.ts) hosts "One Pi Durable harness per Bot, hosted in Electron main" at `<profile>/bots/<dir>/session.sqlite` via `openNodeSqliteStorage`; lazy open, 10-minute idle close, corrupt DB moved aside, and it never calls `resume()` on open, so interrupted work waits for the user. An OS `flock` profile lock ([profile-lock.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/bot-runtime/profile-lock.ts)) exists because a spike showed "two processes on one database double-billed a turn" ([design §2](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-07-bots-rework-design.md)). Tools are adapted from `pi-agent-core` `AgentTool` to Pi Durable tools in [tool-adapter.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/bot-runtime/tool-adapter.ts); persona/authority sections come from the `aiden-bot` extension in [bot-extension.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/bot-runtime/bot-extension.ts) ([bot-durable-runtime note](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/bot-durable-runtime.md)).
- **Subagents: Agent in main, provider call in a utility process.** Children are fresh embedded Pi `Agent`s inside Electron main, not the `pi-subagents` CLI extension ([native subagents plan](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/aiden-native-subagents-plan.md)). Since then, "Keeps Pi's Agent, session, tools, approvals, and MCP authority in main. Only the provider request is delegated to a one-request Electron utility process" via `utilityProcess.fork` ([subagent-inference-process.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/subagents/subagent-inference-process.ts), [subagent-inference-worker.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/subagents/subagent-inference-worker.ts)).
- **Compaction worker.** The vendored `pi-vcc` compiler (from [sting8k/pi-vcc](https://github.com/sting8k/pi-vcc) 0.7.1, MIT) runs in `node:worker_threads`, max two concurrent ([pi-vcc/UPSTREAM.md](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/pi-vcc/UPSTREAM.md), [worker-client.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/pi-vcc/worker-client.ts)).
- **ACP harness.** [main/services/acp/harness.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/acp/harness.ts) defines "The contract an ACP agent implements to become an Aiden provider"; Google Antigravity is the shipped instance, appearing as a model-picker provider, with file I/O routed through Aiden and confined to the chat folder; it is excluded from Bots, scheduled tasks, Live, Telegram, subagents and phone-started turns ([antigravity.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/antigravity.md)).
- **CLI.** `packages/cli` (`aiden-cli` 0.1.0, `private: true`) bundles `@earendil-works/pi-coding-agent` 1.3.0 plus `pi-mcp`, rebranded through Pi's `piConfig` (`configDir: ".aiden"`), for headless Linux use ([packages/cli/package.json](https://github.com/sambitcreate/aiden-agent/blob/main/packages/cli/package.json), [aiden-cli-plan.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/aiden-cli-plan.md)). Not published to npm [INFERENCE from `private: true`].

### Pi provider integration plan

Goal: make Pi's `Models` collection "the only authority for chat providers, models, authentication, catalog refresh, and streaming" instead of Aiden's seven-preset array; Pi registered 36 built-in chat providers at the audited version ([pi-provider-integration-plan.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/pi-provider-integration-plan.md), dated 2026-07-19). Shipped: `ProviderRegistry` over `builtinModels()`, encrypted Pi credentials, device-local models store, provider-owned auth flows, native streaming, voice credential lookup. Open: Pi-native custom-endpoint composition, per-message provider provenance, large-catalog virtualization, legacy cleanup (same doc; README "Upcoming" agrees). Subscription login exists for ChatGPT/Codex (`OPENAI_CODEX_PROVIDER_LABEL = "ChatGPT / Codex"`, base URL `chatgpt.com/backend-api`, OAuth credentials) ([codex-provider.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/codex-provider.ts)).

### Compaction and durable memory plans

- Shipped baseline: append-only private chat journals, pre-prompt and post-response pressure checks, proactive threshold compaction, one compact-and-retry on overflow, crash-recoverable checkpoints, child-agent parity, all delegated to Pi core's summary and cut-point logic ([compaction-plan.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/compaction-plan.md), status 2026-08-14).
- [Pi Compaction and Durable Memory Upgrade](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/pi-compaction-memory-upgrade-plan.md): "Phases 0-7 are implemented; installed/signed and credentialed operator acceptance remains Pending." Principles: the full transcript stays the source of truth; durable memory is "a separate, scoped, approval-controlled store, not compaction prose promoted into standing instructions"; compaction may produce memory *suggestions* only after a successful checkpoint; identity, persona, AGENTS instructions and permissions are not memory.
- Workspace-chat memory is a SQLite `MemoryStore` with scopes, expiry, provenance and approvals ([memory-store.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/memory-store.ts), [upgrade-11-memory note](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/upgrade-11-memory.md)).

### State, remote access, extension surface

- **State**: chats, settings, workspace metadata and speech models local; provider credentials and MCP OAuth in OS encrypted credential storage; Linux refuses to store secrets on Electron's `basic_text` backend ([README Privacy](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)). Bots: `<profile>/bots/<dir>/{session.sqlite, memory/, routine-notes.json}` ([bot-memory-soul note](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/bot-memory-soul.md), [bot-proactivity note](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/bot-proactivity.md)).
- **Remote**: HTTP API `/api/aiden/v1` ([OpenAPI](https://github.com/sambitcreate/aiden-agent/blob/main/protocol/aiden-remote/v1/openapi.json), [138 KB API doc](https://github.com/sambitcreate/aiden-agent/blob/main/docs/aiden-remote-api-v1.md)). LAN: Bonjour `_aiden-agent._tcp`, per-install P-256 HTTPS identity, QR carrying private CA anchor and key pin. Away: Tailscale Serve proxying only `/api/aiden/v1` to a loopback listener; never Funnel, never `serve reset`. Per-device random credential stored as scrypt digest; QR codes expire after 5 minutes and work once; no external push relay ([remote-access doc](https://github.com/sambitcreate/aiden-agent/blob/main/docs/aiden-on-the-go-remote-access.md), [threat model §8](https://github.com/sambitcreate/aiden-agent/blob/main/docs/security/aiden-remote-threat-model.md)). Desktop-to-desktop control: pair computers with a six-digit match code; paired computer gets full control of chats ([remote-access doc](https://github.com/sambitcreate/aiden-agent/blob/main/docs/aiden-on-the-go-remote-access.md)).
- **Extension surface**: Pi-compatible disk skills and prompt templates, MCP (stdio/remote, OAuth, scoped resources and server instructions), a 66-entry plugin catalog in [renderer/shared/plugin-catalog.ts](https://github.com/sambitcreate/aiden-agent/blob/main/renderer/shared/plugin-catalog.ts) (Composio, Gmail, Google Calendar/Drive, Notion, Slack, Outlook, GitHub, Linear, Figma, Canva, Datadog, PostHog ...), Exa search, ACP providers ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md), [harness plan](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/pi-runtime-harness-plan.md)).

## Capabilities in detail

**Persistent Bots and capability grants.** Bot = name, subtitle, character (colour + shape + optional photo), instructions, routines, exactly one conversation, hidden managed home workspace ([design §3](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-07-bots-rework-design.md)). Access is **Full by default** or Custom; Custom narrows the Bot and each chat can narrow further but never exceed it ([design Defaults](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-07-bots-rework-design.md), [threat model §1](https://github.com/sambitcreate/aiden-agent/blob/main/docs/security/aiden-remote-threat-model.md)). Tool policy classifies skills/MCP joins, web, computer_use, subagents, schedules, file locations and shell, re-checked at every call ([bot-durable-runtime note](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/bot-durable-runtime.md)). Linux Bots need an unlocked Secret Service keyring ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)).

**"Soul" and memory** (shipped 0.56.0, [plans index](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/README.md); [design](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-09-bot-memory-soul-proactivity-design.md)):
- The soul is the Bot record's `instructions` field, rendered first among Bot sections and subordinate to authority. A `SOUL.md` file was rejected because a Full-access Bot "could permanently rewrite its own identity with one `echo`".
- `MEMORY.md` (Bot notes) and `USER.md` (about the person), section-sign separated entries, budgets 2,200 and 1,375 chars, capped at 64 entries each, stored outside the Bot home so shell and file tools do not see them; a full store rejects writes and returns current entries so the model consolidates.
- One main-owned `bot_memory` tool; threat/secret scan (invisible/bidi code points, role-hijack and exfiltration patterns, Luhn card numbers) ([bot-memory-soul note](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/bot-memory-soul.md)).
- Snapshot frozen per session open (keeps prompt cache), refreshed after compaction or person edits; memory flush before compaction via Pi Durable's `beforeCompact` hook; add-only background review every 10 person turns; "Memory updated" line; Profile -> Memory view/edit/erase on desktop, iOS and Android.
- Explicitly adapted from Hermes Agent (`prompt_builder.py` `load_soul_md`, `memory_tool.py`, `background_review.py`, `cron/notepad.py`), "Only behaviour is adapted. No source is copied" (design header).
- 0.58.0 adds "more room to remember and a way to recall past chats" ([v0.58.0 notes](https://github.com/sambitcreate/aiden-agent/releases/tag/v0.58.0)).

**Proactivity and routines.** Routines target the Bot's conversation with `requestId = routine:<taskId>:<fireTime>`; "If there is nothing new, reply exactly [SILENT]" suppresses bubble and notification; failures always surface; a Bot cannot create recurring work itself, only `propose` (max 2 pending) which becomes an approval card; per-routine `routine_notes` notepad (16 keys, 8,000 bytes) offered only on that routine's runs; one catch-up of the newest missed fire within 7 days after pause; no hidden heartbeat, only a "Daily check-in" starter suggestion ([design §8](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-07-bots-rework-design.md), [soul design §2](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-09-bot-memory-soul-proactivity-design.md), [bot-proactivity note](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/bot-proactivity.md)). Routine results reach Mac notifications, a new phone Bot feed, and the bound Telegram chat (same).

**Scheduled tasks (workspace level).** `mode: "llm"` or `mode: "script"` (stdout delivered verbatim, empty = silent); dedicated chat thread per task; croner-driven main-process service; read-only LLM runs withhold MCP; Full runs persist an exact approved MCP server scope; modelled on Hermes Agent's cron subsystem as behaviour reference ([scheduled-tasks-plan.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/scheduled-tasks-plan.md)).

**Hermes Agent: reference, not integration.** No Hermes runtime is embedded. The "Hermes-inspired Bot run control" plan read NousResearch/hermes-agent `gateway/run.py` at `836b5f8` as a "product reference, not copied code", and produced bounded Telegram queues (20 prompts / 32 MiB), `/queue`, `/continue`, `/interrupt`, `/steer`, and a shared durable input admission boundary `chat-run-input-v1` used by desktop, Telegram and phones ([hermes-bot-run-control-plan.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/hermes-bot-run-control-plan.md), [note](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/hermes-bot-run-controls.md)). Hermes is also the cited model for the Computer Use tool shape and the Telegram adapter behaviour ([computer-use-integration.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/computer-use-integration.md), [upgrade-22-telegram note](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/upgrade-22-telegram.md)). The iOS client retains an MIT notice from "Hermex" for adapted pieces ([ios/README.md](https://github.com/sambitcreate/aiden-agent/blob/main/ios/README.md)).

**Native subagents.** A foreground chat delegates 1-4 `scout`, `planner`, `reviewer` or `implementer` tasks; children inherit workspace and model, stop with the parent; implementer can write and run shell within the parent ceiling (Full: no extra card; Ask: one write grant and one shell grant per child run); implementer cannot delegate; per-task model and effort since 0.55.0; hosted concurrency 2, local 1 ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md), [native subagents plan](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/aiden-native-subagents-plan.md), [orchestration expansion](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/subagent-orchestration-expansion-plan.md)). Background (detached) subagents are still "Phase 7B coordinator activation is next" (same doc).

**Coding workspace.** Folders, scratch workspaces, managed git worktrees with crash-aware cleanup; terminal drawer (node-pty); files/diffs; branch compare; commit/push of checked snapshots; external editor discovery; chat fork and chat pull requests ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md), [plans index](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/README.md)).

**Browser and Computer Use.** Shared in-app browser with isolated profiles, responsive viewports and annotations; agent browser tools operate on the same tabs ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md), [environment-browser.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/environment-browser.md)). Computer Use (macOS opt-in beta) uses Cua's Rust `cua-driver` 0.34.1 over MCP stdio, hash- and Team-ID-pinned, telemetry/self-update disabled; Aiden's own Rust broker ([native/computer-use-broker](https://github.com/sambitcreate/aiden-agent/tree/main/native/computer-use-broker)) is only the permission/transport boundary, packaged as `CuaDriver.app` "Aiden Computer Use", and authenticates Aiden's main process by kernel audit token rather than PIDs; one `computer_use` function with `som`/`vision`/`ax` capture modes ([computer-use-integration.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/computer-use-integration.md)). First call per chat raises Deny / Allow for this chat / Always allow (0.56.0) ([plans index](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/README.md)).

**Voice.** Aiden Live runs on Google's Gemini Live API (`@google/genai`), voice-only by default since 0.41.5, screen capture on by default since 0.55.0 with kill switch `AIDEN_EXPERIMENTAL_GEMINI_LIVE_SCREEN=0`; has a Computer Use bridge ([gemini-live-assistant-plan.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/gemini-live-assistant-plan.md), [gemini-live/computer-use-bridge.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/gemini-live/computer-use-bridge.ts)). Dictation uses on-device Parakeet via sherpa-onnx ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md), [package.json](https://github.com/sambitcreate/aiden-agent/blob/main/package.json)).

**Channels.** Telegram only: ported from [llblab/pi-telegram](https://github.com/llblab/pi-telegram) (MIT fork of badlogic/pi-telegram), wired to `llmClient`; workspace remote control plus per-Bot binding in Advanced ([telegram plan](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/telegram-remote-control-plan.md)). No Slack/WhatsApp/iMessage/email channel found (searched plans index; unknown beyond Telegram).

**Mobile (Aiden On The Go).** Native SwiftUI iPhone/iPad app (TestFlight only; version 0.1.0 build 22 in internal beta testing) and Android app (debug APK from CI), both pure remote clients: Bots list, Bot chat with Messages-style bubbles, workspace browsing, approvals, Steer/Queue, Live Activities, deep links `aiden-otg://bot/{id}/chat` ([ios/README.md](https://github.com/sambitcreate/aiden-agent/blob/main/ios/README.md), [plans index](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/README.md), [README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)).

**Team features.** None found; single-owner product.

## Security and trust model

- Renderer sandboxed with no Node access, allowlisted bridge ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)).
- Workspace access levels Full / Ask / None (+ read-only chats); Ask cards for writes and shell; web and MCP calls approved per call ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)). Tool approval scopes and timed ask-user exist as completed plans ([plans index](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/README.md)).
- Bots default to **Full access**, which includes the shell in the Bot home and other OS-accessible locations; the threat model states the managed home "is not a sandbox in Full mode" and a compromised paired phone with `bot:write` "can exercise the granted Bot surface until revoked" ([threat model §1, §8](https://github.com/sambitcreate/aiden-agent/blob/main/docs/security/aiden-remote-threat-model.md)).
- Memory writes are scanned for injection/secrets and stored outside shell-reachable defaults, but Full shell can still reach them, hence read-side validation ([soul design §2.1, §6.3](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-09-bot-memory-soul-proactivity-design.md)).
- MCP results treated as untrusted data (fence + redact) per the taracodlab learnings plan ([taracodlab-learnings-plan.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/taracodlab-learnings-plan.md)).
- Computer Use: pinned binary hashes, Sigstore verification option, audit-token mutual authentication, no PATH lookup or self-update ([computer-use-integration.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/computer-use-integration.md)).
- Telemetry: "inspect or export bounded local diagnostics without an automatic upload path" ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)).
- Distribution: installer verifies checksums, Apple signing/Gatekeeper on macOS and GitHub build attestation on Linux; but the recommended install is `curl ... | sh` ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)).
- Known incidents or security advisories: none found ([open issues](https://github.com/sambitcreate/aiden-agent/issues), checked 2026-10-20; open issues are almost all owner-filed flaky-test and P-level bugs).

## Traction and momentum

All as of 2026-10-20 ([GitHub API](https://api.github.com/repos/sambitcreate/aiden-agent)):

| Metric | Value |
| --- | --- |
| Stars / forks / watchers | 85 / 4 / 0 |
| Created | 2026-07-18 |
| Commits on default branch | 4,147 (about 44/day since creation) |
| Commits since 2026-09-20 | 2,191 (about 73/day) |
| Merged PRs | 461 |
| Issues | 61 total, 31 open |
| Releases | 62, v0.27.23 (2026-07-25) to v0.58.0 (2026-10-19); per month: Jul 4, Aug 32, Sep 19, Oct 1-19 7 ([releases](https://github.com/sambitcreate/aiden-agent/releases)) |
| Contributors | sambitcreate 3,940; claude 77; github-actions 75; cursoragent 49; devin-ai-integration 6 |

- Velocity is extreme for a solo project and is produced by AI coding agents directed by one person (agent-authored commits, `claude/project-thread-*` branches, AI reviewers "Pullfrog" and "Sol" named in notes) ([hermes-bot-run-controls note](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/hermes-bot-run-controls.md), [commits](https://github.com/sambitcreate/aiden-agent/commits/main)). [INFERENCE] The commit count reflects agent granularity, not human throughput.
- Community: no external contributors with merged code found; one issue at most from a non-owner (GitHub search, 2026-10-20). No press found.
- Website [chatwithaiden.com](https://chatwithaiden.com/) still markets a "private macOS menu-bar AI client" on TestFlight ("Product information last updated: June 19, 2026"), with a "Try Aiden Agent Beta" button linking the Electron DMG; it claims "Tested by folks at" OpenAI, Apple, Google, Kagi (vendor claim). The [aiden-website](https://github.com/sambitcreate/aiden-website) repo referenced in the README returns 404 (private or removed) as of 2026-10-20.
- Business model and pricing: none; free MIT app, bring your own keys or subscriptions.

## Strengths

- Deepest public integration of Pi as an embedded library in a GUI, tracking Pi releases within days (1.3.0 in four days) ([package.json](https://github.com/sambitcreate/aiden-agent/blob/main/package.json)).
- Bots implement the Grok Bot pattern on open code with unusually careful durability: per-Bot SQLite session, explicit Resume, no double-run across processes, idempotent routine request IDs ([harness-host.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/bot-runtime/harness-host.ts)).
- Memory design is bounded, user-visible, erasable and injection-scanned, with clear separation of identity, memory and compaction ([soul design](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-09-bot-memory-soul-proactivity-design.md)).
- Mobile and multi-computer remote control without any vendor cloud, using LAN pinning or Tailscale Serve ([remote-access doc](https://github.com/sambitcreate/aiden-agent/blob/main/docs/aiden-on-the-go-remote-access.md)).
- Extensive written design rationale (plans, specs, ADRs, threat model, 200 memory notes) that is reusable research even if the app is not.
- Breadth: subagents, artifacts, simulators, Computer Use, voice, Telegram, Linux packaging.

## Weaknesses and risks

- **Solo-maintainer / bus factor**: one human account drives 95% of commits; continuity depends on one person plus agent subscriptions ([contributors API](https://api.github.com/repos/sambitcreate/aiden-agent/contributors)).
- **Scope sprawl vs. adoption**: very large surface (5,122 files in tree) with 85 stars; many features carry "physical-device acceptance pending" or "operator acceptance pending" ([plans index](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/README.md)).
- **Upstream churn**: Pi Durable is "labelled experimental, and breaking changes ship in patch releases" ([design §2](https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-07-bots-rework-design.md)); Aiden pins exactly and keeps a 0.87.1 legacy alias, adding upgrade cost.
- **Pre-1.0 "no migrations" policy**: the Bots rework deleted existing extra Bot conversations and transcripts (same doc).
- **Full-by-default Bots on the host** with no sandbox; containment relies on Custom grants and approvals ([threat model §8](https://github.com/sambitcreate/aiden-agent/blob/main/docs/security/aiden-remote-threat-model.md)).
- **Platform gaps**: no Windows; Intel Mac pending; iOS only via TestFlight; Computer Use and Apple models macOS-only ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)).
- **Brand confusion**: at least two other agent products named AIDEN (see below), and the website still advertises a different (SwiftUI menu-bar) product.

## Ideas worth taking for Memoshi

- **One durable session file per bot** (Pi Durable SQLite, lazy open, idle close, OS file lock) - simple isolation, per-bot delete is `rm -rf`, prevents double-billing across processes.
- **Explicit Resume instead of auto-restart** after crashes - avoids silently repeated side effects; pair with `replay: safe|unsafe` per tool.
- **Soul in the record, not a file the bot can edit** - prevents self-rewriting identity via shell; keep memory outside the bot's working dir.
- **Bounded memory stores that reject overflow and force consolidation**, plus a frozen per-session snapshot for prompt caching and a periodic add-only review.
- **Bots propose routines; humans approve** (approval card, max 2 pending) and `[SILENT]` no-op replies - proactivity without spam or runaway automation.
- **Per-routine notepad** scoped to that routine's runs - cheap continuity for recurring jobs without polluting global memory.
- **`suggest_connection` cards** with per-plugin "Not now" suppression - consent-based connector onboarding inside chat.
- **Desktop as authority, phones as remote** over LAN-pinned TLS or Tailscale Serve with single-use 5-minute QR pairing and per-device revocable credentials - no relay to run.
- **Provider request in a short-lived utility process while the agent loop stays in main** - isolates provider SDK crashes and credential helpers.
- **ACP harness interface for third-party agents** (Antigravity) as "just another provider" - a route to Claude Code/Codex/Gemini CLI engines.
- **Avoid**: shipping Full access as the bot default on the host without a sandbox; deleting user data under a "pre-1.0, no migrations" rule.

## Open questions

- Is the iOS app publicly available beyond internal TestFlight testers? Check the TestFlight link and App Store Connect status in [ios/TESTFLIGHT.md](https://github.com/sambitcreate/aiden-agent/blob/main/ios/TESTFLIGHT.md).
- Actual user count: no download telemetry; GitHub release asset download counts via `gh api repos/sambitcreate/aiden-agent/releases --jq '.[].assets[].download_count'` would give a lower bound (not collected here due to API rate limiting).
- Whether workspace chats will also move onto Pi Durable (the plans index says "remain undecided") ([plans index](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/README.md)).
- Whether multi-Bot rooms / `message_agent` will ship; only referenced as a separate track ([compaction-memory plan](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/pi-compaction-memory-upgrade-plan.md)).
- Contents of the private `aiden-website` repo and the relation between the SwiftUI TestFlight "Aiden" and the Electron app's version numbering (releases start at v0.27.23) [INFERENCE: versions continued from the earlier app].

### Disambiguation: other products named AIDEN

- **AIDEN by aidenapp.org**: proprietary "agentic AI IDE" for macOS that runs on top of the user's installed Claude Code and Codex CLIs, with multi-agent orchestration on parallel git worktrees, spec-driven development with human approval before code, a kanban feature board and auto-PRs; Free (1 project), Solo $20/mo or $169 lifetime, Team $20/seat/mo; built solo by Kylian Migot (Lekiks). No public repo or OSS license found ([aidenapp.org](https://aidenapp.org/), [about](https://aidenapp.org/about), as of 2026-10-20). Unrelated to Aiden Agent.
- **taracodlabs/aiden**: "an autonomous AI agent and work engine built solo", AGPL-3.0, created 2026-03-07, 859 stars as of 2026-10-20, homepage aiden.taracod.com ([GitHub API](https://api.github.com/repos/taracodlabs/aiden)). Aiden Agent's maker audited it as a "broader autonomous-agent platform (CLI-first runtime, daemon, channels, first-party loop, 'moat' safety)", Windows-first Electron, with `SOUL.md`/`USER.md`/`MEMORY.md`, and chose to borrow reliability ideas but not its code or AGPL core ([taracodlab-learnings-plan.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/taracodlab-learnings-plan.md)). Unrelated codebase; candidate for its own profile.

## Sources

1. https://github.com/sambitcreate/aiden-agent (README, LICENSE)
2. https://api.github.com/repos/sambitcreate/aiden-agent (repo stats, 2026-10-20)
3. https://github.com/sambitcreate/aiden-agent/releases (62 releases; v0.58.0 notes)
4. https://api.github.com/repos/sambitcreate/aiden-agent/contributors
5. https://github.com/sambitcreate/aiden-agent/blob/main/package.json
6. https://github.com/sambitcreate/aiden-agent/blob/main/PRODUCT.md
7. https://github.com/sambitcreate/aiden-agent/blob/main/main/services/pi-agent-runtime-harness.ts
8. https://github.com/sambitcreate/aiden-agent/blob/main/main/services/generation-harness.ts
9. https://github.com/sambitcreate/aiden-agent/blob/main/main/services/pi-legacy-harness.ts
10. https://github.com/sambitcreate/aiden-agent/blob/main/main/services/bot-runtime/harness-host.ts
11. https://github.com/sambitcreate/aiden-agent/blob/main/main/services/subagents/subagent-inference-process.ts
12. https://github.com/sambitcreate/aiden-agent/blob/main/main/services/subagents/subagent-inference-worker.ts
13. https://github.com/sambitcreate/aiden-agent/blob/main/main/services/pi-vcc/UPSTREAM.md
14. https://github.com/sambitcreate/aiden-agent/blob/main/main/services/pi-vcc/worker-client.ts
15. https://github.com/sambitcreate/aiden-agent/blob/main/main/services/pi-codemode.ts
16. https://github.com/sambitcreate/aiden-agent/blob/main/main/services/acp/harness.ts
17. https://github.com/sambitcreate/aiden-agent/blob/main/main/services/codex-provider.ts
18. https://github.com/sambitcreate/aiden-agent/blob/main/renderer/shared/plugin-catalog.ts
19. https://github.com/sambitcreate/aiden-agent/blob/main/packages/cli/package.json
20. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/README.md
21. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/pi-runtime-harness-plan.md
22. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/pi-provider-integration-plan.md
23. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/compaction-plan.md
24. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/pi-compaction-memory-upgrade-plan.md
25. https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-07-bots-rework-design.md
26. https://github.com/sambitcreate/aiden-agent/blob/main/docs/superpowers/specs/2026-10-09-bot-memory-soul-proactivity-design.md
27. https://github.com/sambitcreate/aiden-agent/blob/main/.memory/bot-durable-runtime.md
28. https://github.com/sambitcreate/aiden-agent/blob/main/.memory/bot-memory-soul.md
29. https://github.com/sambitcreate/aiden-agent/blob/main/.memory/bot-proactivity.md
30. https://github.com/sambitcreate/aiden-agent/blob/main/.memory/bots-rework-ui.md
31. https://github.com/sambitcreate/aiden-agent/blob/main/.memory/hermes-bot-run-controls.md
32. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/hermes-bot-run-control-plan.md
33. https://github.com/sambitcreate/aiden-agent/blob/main/.memory/upgrade-22-telegram.md
34. https://github.com/sambitcreate/aiden-agent/blob/main/.memory/upgrade-11-memory.md
35. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/aiden-native-subagents-plan.md
36. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/subagent-orchestration-expansion-plan.md
37. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/scheduled-tasks-plan.md
38. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/completed/telegram-remote-control-plan.md
39. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/gemini-live-assistant-plan.md
40. https://github.com/sambitcreate/aiden-agent/blob/main/docs/computer-use-integration.md
41. https://github.com/sambitcreate/aiden-agent/blob/main/docs/aiden-on-the-go-remote-access.md
42. https://github.com/sambitcreate/aiden-agent/blob/main/docs/security/aiden-remote-threat-model.md
43. https://github.com/sambitcreate/aiden-agent/blob/main/docs/aiden-remote-api-v1.md
44. https://github.com/sambitcreate/aiden-agent/blob/main/docs/workspace-artifacts.md
45. https://github.com/sambitcreate/aiden-agent/blob/main/docs/devices.md
46. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/design-studio-adr.md
47. https://github.com/sambitcreate/aiden-agent/blob/main/docs/antigravity.md
48. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/aiden-cli-plan.md
49. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/taracodlab-learnings-plan.md
50. https://github.com/sambitcreate/aiden-agent/blob/main/ios/README.md
51. https://github.com/sambitcreate/aiden-agent/pull/554
52. https://github.com/earendil-works/pi (Pi, formerly badlogic/pi-mono)
53. https://github.com/llblab/pi-telegram
54. https://github.com/sting8k/pi-vcc
55. https://chatwithaiden.com/ (maker website)
56. https://aidenapp.org/ and https://aidenapp.org/about (different product)
57. https://api.github.com/repos/taracodlabs/aiden (different product)
