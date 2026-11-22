# Decisions

**Status:** Draft 4 · 2026-10-20 · D44–D87 added 2026-10-22 · D88–D93 added 2026-10-23 · D94–D95 added 2026-10-25 · D96 added 2026-10-27 · D97 added 2026-11-01 · D98–D99 added 2026-11-03 · D100 added 2026-11-06 · D101–D103 added 2026-11-07 · D104–D105 added 2026-11-08 · D99 amended 2026-11-10 · D106–D133 added 2026-11-13, D134–D138 on 2026-11-14
**Purpose:** The binding decision log for Memoshi. Every plan and spec doc follows these. To change one, add a new decision that supersedes it (see [change control](#change-control)); never edit a decision silently.

Status values: **Accepted** = locked for planning. **Accepted, spike-gated** = locked unless a named spike disproves it. **Proposed** = recommended, awaiting sign-off. **Open** = needs a decision; a recommended default is given.

Evidence links point into [`../research/`](../research/). `[INFERENCE]` marks reasoning rather than sourced fact.

---

## Product

<a id="d1"></a>
### D1. Product shape
- **Status:** Accepted (user direction, 2026-10-20); amended by [D47](#d47) (2026-10-22): Memoshi ships on Mac, iPhone and iPad.
- **Choice:**
  - One native Mac app in which a personal **Assistant** runs a team of persistent **bots** that do real work, including coding, in **projects**, each on its own **computer** and **browser**.
  - In the user's words: "a native Swift app like Kuvo Code, running on the latest Pi (Durable, Code Mode, MCP), with Aiden Agent's design and animations, bots like Grok Bot, and a browser and a computer for each bot — and the bots can also do coding through Pi."
- **Rationale:**
  - The landscape's largest gap is an assistant that owns and delegates to a team with governed memory ([white space](../research/agentic-workspace-landscape/README.md#6-white-space-memoshi-can-own)).
  - Per-bot isolation is the clearest contrast with Grok Bot's shared computer ([profile](../research/agentic-workspace-landscape/projects/grok-bot.md)).
- **Supersedes:** Draft 3 positioning ("the native workbench with a team").

<a id="d2"></a>
### D2. Home model: Assistant-led
- **Status:** Accepted
- **Choice:**
  - The app opens to the **Assistant's Chat**, with the **Inbox** one click away.
  - **Bots**, **Groups**, **Projects** and **Sessions** (sessions without a project) are peer sidebar sections.
  - Bots are first-class identities; projects are first-class workspaces; **Sessions**, **Tasks** and **Handoffs** join them.
- **Rationale:**
  - Kuvo Code already mixes bots, group chats, chats and projects in one sidebar ([profile](../research/agentic-workspace-landscape/projects/kuvo-code.md)), so a combined sidebar is proven.
  - A pinned Assistant at the top expresses the product thesis.
  - Draft 3's "projects lead" home hid the team. A roster-first home (Grok) hides the workbench.
- **Consequences:** The Assistant must be useful on day one with no project open. Every project session stays one click (or ⌘K) away.
- **Alternatives considered:** projects first (Draft 3 D4); roster first (Grok Bot).
- **Supersedes:** Draft 3 D4.

<a id="d3"></a>
### D3. First user and modes
- **Status:** Accepted
- **Choice:**
  - Builders on a Mac: developers, technical founders, technical operators and product-minded builders.
  - **Guided** mode is the default; **Developer** mode is opt-in. Both use the same objects and surfaces.
  - Non-technical consumers are not a v1 target market, but no bot workflow may require writing code.
- **Rationale:** These users bring keys, grant folders deliberately, and want both a team and a workbench. The landscape's non-developer gap ([long tail](../research/agentic-workspace-landscape/landscape/oss-long-tail.md#5-patterns)) shapes onboarding even before it becomes a market.
- **Keeps:** Draft 3 D13 and D26.

<a id="d4"></a>
### D4. Vocabulary
- **Status:** Accepted
- **Choice:**
  - The terms and definitions in [MASTER_PLAN §5](MASTER_PLAN.md#5-vocabulary-and-object-model) are binding in the UI, code and docs.
  - The UI says **Bot** (not "agent"), **Assistant**, **Chat**, **Project**, **Session**, **Group**, **Task**, **Handoff**, **Routine**, **Watch**, **Wake**, **Computer**, **Browser**, **Memory**, **Connector**, **Skill**, **Card**, **Approval**, **Draft**, **Artifact**, **Inbox**, **Budget** and **Grant**.
  - **"Chat" always means a bot's one home thread.** Sessions without a project are listed in a sidebar section labeled **Sessions**, never "Chats" (amended 2026-10-20 after a naming clash surfaced in [`02-experience.md`](02-experience.md)).
- **Rationale:** "Bot" is the category's word (Grok Bot, Kuvo, Noodle, Aiden). One vocabulary keeps a five-source union coherent.

<a id="d5"></a>
### D5. v1 scope
- **Status:** Accepted; superseded by [D47](#d47) (2026-10-22): v1 adds iPhone and iPad, and Bot computers, Remote machines and Groups move to v1.1.
- **Choice:** v1 is everything in [MASTER_PLAN §11 v1](MASTER_PLAN.md#11-scope): the Assistant, a team, a workbench, and a computer and browser per bot. Reach features ship in v1.1: iPhone, Telegram, runner, external coding agents, teach-by-demonstration, GUI computer use in Bot computers, and Attempts.
- **Rationale:** The user's decided direction makes bots, per-bot computers and browsers, and coding core.
- **Supersedes:** Draft 3 D9 (build loop plus team; local VMs and browser automation deferred).

## Engine

<a id="d6"></a>
### D6. Engine: Pi Durable behind our adapter
- **Status:** Accepted; superseded in part by [D44](#d44) (2026-10-22). The engine is now Pi_Swift on the latest upstream. The adapter boundary, the contract tests and the fallback carry over.
- **Choice:**
  - Use `@earendil-works/pi-durable`, `pi-codemode`, `pi-mcp`, `pi-env` and `pi-ai` at **1.3.x, pinned to exact versions**.
  - Only `memoshid/runtime/` may import Pi types.
  - Every Pi upgrade must pass contract tests.
  - Fallback: `pi-agent-core` plus our own durability layer (the exit path OpenClaw took on 2026-05-27).
- **Rationale:**
  - Durable conversations, tasks, subagents, Code Mode, MCP and execution environments match the product one-for-one.
  - Pi's own README says "Experimental. The API changes without notice". Pi 1.0.0 shipped on 2026-10-01 and 1.3.0 on 2026-10-15, with breaking changes in 1.0.3, 1.0.4, 1.1.0 and 1.2.0 (Pi changelog; [harnesses](../research/agentic-workspace-landscape/landscape/agent-harnesses.md#pi)).
- **Keeps:** Draft 3 D2 and D21.

<a id="d7"></a>
### D7. Conversation mapping
- **Status:** Accepted (storage detail verified in Phase 0)
- **Choice:**
  - Chats, Sessions and Groups are Pi Durable conversations. Tasks are Pi Durable tasks. Subagents are child conversations. A Computer is a Pi `env`.
  - **Bot identity, instructions, memory and grants are rendered into every request** from the app's records. They are never frozen when a conversation is created.
  - Transcripts live once, in Pi Durable storage. Memoshi's SQLite holds app objects, projections and the event log.
- **Rationale:** The Draft 3 build fixed instructions at `root()` creation, so later edits likely never applied, and it stored every transcript twice ([audit](../research/agentic-workspace-landscape/landscape/in-house-assets.md#draft-3-build)).

<a id="d8"></a>
### D8. Tools and Code Mode
- **Status:** Accepted
- **Choice:**
  - **Tools:** Pi's coding tools, plus Memoshi tools for memory, cards, handoffs, routines, wakes, watches, browser and computer.
  - **Code Mode** (`pi-durable/codemode`) is on by default for bots with large tool sets.
  - **MCP tools** come in through `pi-mcp` as deferred tools, found with `tool_search`.
  - **Background runs** reach the user only through `post_update` or end silently with `no_update`. Interactive turns stream normally.
- **Rationale:** Code Mode and deferred tools keep context small ([harnesses](../research/agentic-workspace-landscape/landscape/agent-harnesses.md)). An explicit quiet-run tool beats magic strings (OpenBot `routine_no_update`, Aiden `[SILENT]`).

<a id="d9"></a>
### D9. One policy engine, outside the model
- **Status:** Accepted
- **Choice:**
  - All tool calls pass one policy engine in memoshid, attached through Pi Durable's `beforeTool` (block or rewrite) and `afterTool` (redact or replace) hooks.
  - These hooks also run for nested Code Mode and MCP-bridge calls, which carry `call.parent`.
  - The UI renders decisions but is never the trust boundary.
  - Deterministic rules decide first; an optional model-based reviewer can only add friction, never remove it.
- **Rationale:**
  - Pi ships hooks but no policy ([harnesses](../research/agentic-workspace-landscape/landscape/agent-harnesses.md#pi)).
  - The big labs enforce safety outside the agent (Muse Sentinel, the Dots reviewer).
- **Keeps:** Draft 3 D18.

<a id="d10"></a>
### D10. Models and accounts
- **Status:** Accepted; the Sign in with ChatGPT clause is superseded by [D54](#d54) (2026-10-22). `pi-ai` is now Pi_Swift's PiAI ([D44](#d44)).
- **Choice:**
  - Provider-agnostic through `pi-ai`, using the user's API keys.
  - Local models (Ollama, LM Studio, MLX) through OpenAI-compatible endpoints.
  - Apple Foundation Models on-device for small jobs only: titles, summaries, memory proposal drafts, risk explanations, commit messages.
  - "Sign in with ChatGPT" only after OpenAI approves Memoshi as a commercial partner.
  - **Never ship Pi's Anthropic, Google or Meta subscription OAuth paths.**
- **Rationale:** Anthropic forbids third-party apps from offering Claude.ai login or routing requests through user plans. Google bans third-party use and has enforced it. Meta limits its subscription to the Muse Code CLI. Pi's OAuth modules borrow those vendors' client IDs ([policy quotes](../research/agentic-workspace-landscape/landscape/agent-harnesses.md#4-subscription-auth-policy-verbatim-dated)).
- **Keeps:** Draft 3 D17.

<a id="d11"></a>
### D11. External coding agents (v1.1)
- **Status:** Accepted
- **Choice:**
  - Codex (app-server), Claude Code (the unmodified binary) and ACP agents can work as delegated coding workers.
  - Every tool call they make is routed back through Memoshi policy using each agent's native permission protocol.
  - Users sign in to each vendor's own CLI themselves.
  - Memoshi never collects, stores or forwards vendor credentials, and never resells usage.
- **Rationale:** This is the only path Anthropic explicitly allows for using a Claude subscription inside another product, and it gives users best-in-class coding agents ([harnesses](../research/agentic-workspace-landscape/landscape/agent-harnesses.md)).

## Architecture

<a id="d12"></a>
### D12. Process model
- **Status:** Accepted (helper split revisited at the Phase 3 gate); amended by [D46](#d46) (2026-10-22): memoshid is a Swift executable running Pi_Swift, and iPhone and iPad run the engine inside the app.
- **Choice:**
  - **Memoshi.app** is the UI and the host for native capabilities: VMs, WebKit browsers, Foundation Models, notifications, dictation, and the Keychain broker. It is a login item that keeps running in the menu bar when its windows close.
  - **memoshid** is the bundled Node runtime with Pi Durable, the scheduler, policy, memory and connectors. It is registered as a LaunchAgent through `SMAppService` and survives app restarts, crashes and updates.
  - When a run needs a native capability while the app is not running, memoshid relaunches the app hidden, unless the user has turned that off.
- **Rationale:**
  - Hosting VMs and WebKit in the app gives native, embedded live views (`VZVirtualMachineView`, `WKWebView`) without cross-process streaming.
  - A separate daemon keeps routines alive when windows close. In Draft 3, routines ran on a timer inside an app-owned sidecar and stopped when the app quit ([audit](../research/agentic-workspace-landscape/landscape/in-house-assets.md#draft-3-build)).
- **Consequence:** Bot computer VMs have no network of their own, and their tool calls cross the app process. An app crash therefore interrupts VM work, not just the live view. This is the main input to [O3](#open-decisions) at the Phase 3 gate.
- **Alternatives considered:** a separate native helper app per capability (Noodle's Computer and Browser apps), which gives better crash isolation but no embedded views; everything in one process.
- **Supersedes:** Draft 3 D19 (one app, one sidecar).

<a id="d13"></a>
### D13. Transport
- **Status:** Accepted; amended by [D46](#d46) (Node-specific peer checks dropped) and [D48](#d48) (device links replace the v1.1 relay-only phone client), 2026-10-22.
- **Choice:**
  - **Framing:** JSON-RPC 2.0 in both directions over a WebSocket.
  - **Socket:** a Unix domain socket in the user's Application Support folder, mode 0600, with a per-launch token and a check of the peer's user ID.
  - **Peer verification:** the token file is mode 0600, but any process of the same user can read it. So the token and user-ID check are necessary but not enough.
    - Both sides also verify each other's code signature; memoshid does this through a small native addon.
    - Before releasing secrets, the app additionally checks the daemon process's executable path, its launchd label and PID, and its arguments. Because the launcher hands its process over to the bundled Node (`execv`), the path checked is `Helpers/node`.
    - These extra checks exist because memoshid runs a general-purpose interpreter (Node) ([`09-platform-macos.md`](09-platform-macos.md), [`../specs/protocol.md`](../specs/protocol.md)).
  - **Event stream:** one multiplexed stream, sent as notifications with a global sequence number and replay on reconnect.
  - **Daemon to app:** memoshid calls the app's capabilities (browser, computer, Foundation Models, notifications, Keychain broker) over the same connection.
  - **Remote clients:** the protocol is designed for a v1.1 phone client through an end-to-end-encrypted relay.
  - **Local webhooks:** a separate, loopback-only HTTP receiver accepts webhook triggers only. Each routine has its own path and signing secret, and the receiver offers no control methods. Public webhooks arrive through the relay in v1.1 ([D23](#d23)).
- **Rationale:**
  - Capability calls need daemon-to-app requests.
  - A Unix socket removes browser-to-localhost attack surface.
  - Draft 3 streamed only the selected session and polled the rest every 12 s ([audit](../research/agentic-workspace-landscape/landscape/in-house-assets.md#draft-3-build)).
- **Supersedes:** Draft 3's loopback HTTP + per-session SSE. Its replay, heartbeat and auth logic is ported.

<a id="d14"></a>
### D14. Storage
- **Status:** Accepted; amended by [D49](#d49) (2026-10-22): every device keeps its own SQLite and replicas, and each bot has its own durable store with one writer at a time.
- **Choice:**
  - SQLite in WAL mode, owned by memoshid, holds app objects, projections, the append-only event log (with pruning and snapshots), memory (with FTS5), routines, approvals and audit.
  - Pi Durable storage holds transcripts and task state.
  - Files hold bot homes and projects.
  - **Secrets live only in Keychain** and are never written to disk, environment files or logs.
- **Keeps:** Draft 3 D7 and D22.

<a id="d15"></a>
### D15. Bundled Node
- **Status:** Accepted; superseded by [D46](#d46) (2026-10-22). No Node ships unless the Mac misses the Pi_Swift gate, in which case this decision returns.
- **Choice:**
  - A pinned Node LTS ships inside the app bundle, behind a small signed launcher, re-signed with the hardened runtime and only the JIT entitlement V8 needs (`allow-jit`), and notarized.
  - **Version:** Node 24.22.0 now. Ship v1 on Node 26 LTS if the Phase 0 packaging spike passes. Node 22 reaches end of life on 2027-04-30, around the v1 launch, so it is ruled out even though Pi's engine floor (22.19) allows it.
  - memoshid is bundled together with its Pi dependencies.
  - Users never install Node.
- **Rationale:** The Draft 3 sidecar left the Pi packages external and launched the system Node, so it could not ship ([audit](../research/agentic-workspace-landscape/landscape/in-house-assets.md#draft-3-build)). Kuvo verifies and pins its engine the same way ([profile](../research/agentic-workspace-landscape/projects/kuvo-code.md)).

## Computers and browsers

<a id="d16"></a>
### D16. A computer for every bot
- **Status:** Accepted; amended by [D47](#d47) (2026-10-22): Bot computers and Remote machines move to v1.1, so This Mac (sandboxed) is every Mac bot's computer in v1, and iPhone and iPad bots use the in-app environment ([D50](#d50)). Amended by [D77](#d77) (2026-10-22): a no-follow guard and one channel for This Mac's sandbox, and a fixed fallback order if spike S4 fails.
- **Choice:** Every bot has a computer, chosen per bot:
  - **This Mac (sandboxed)** (default): a per-bot pi-env daemon runs inside Anthropic's `sandbox-runtime` (Seatbelt), so file tools, exec and the terminal are all sandboxed. Access is limited to the bot's home folder plus granted folders, and network goes through an allowlist proxy. (Corrected 2026-10-20: wrapping only Pi's local environment would leave Pi's file tools unsandboxed; [`06-computers-and-browsers.md`](06-computers-and-browsers.md).)
  - **Bot computer:** a Linux VM ([D17](#d17)).
  - **Remote machine:** SSH through pi-env, for builds and long jobs on a Mac mini or server. It is not always-on by itself: pi-env stops its jobs 30 s after the link drops, so long work must be detached on purpose. Full always-on comes with the v1.1 runner.
  - **Cloud computer:** v2, behind the same seam.

  No bot ever defaults to Full access, and bots share a computer only by explicit user choice.
- **Rationale:** Grok Bot's shared computer means bots are not security boundaries for each other ([profile](../research/agentic-workspace-landscape/projects/grok-bot.md)). In the open-source products, Full access is the norm and incidents follow ([landscape §1](../research/agentic-workspace-landscape/README.md#1-executive-summary)).
- **Keeps and extends:** Draft 3 D5. **Supersedes:** Draft 3 D6 (local + SSH only).

<a id="d17"></a>
### D17. Bot computer design
- **Status:** Accepted, spike-gated; deferred to v1.1 by [D47](#d47) (2026-10-22), with its spike, O2 and O4.
- **Choice:**
  - **Hosting:** one Linux VM per bot on Virtualization.framework, hosted by the app's Computer service.
  - **Image:** a desktop, Chromium, toolchains, `sshd` and pi-env's daemon. Tools run through pi-env's `RemoteExecutionEnv` over SSH.
  - **Projects:** shared into the VM with virtiofs.
  - **Idle:** an idle VM saves its state and sleeps. The number of awake VMs is capped by RAM.
  - **Egress:** goes through a host proxy with allowlists and secret placeholders, after Gondolin's design.
  - **Display:** the live view is a native `VZVirtualMachineView`.
- **Spike alternatives:** Apple's Containerization framework (headless OCI micro-VMs) and Gondolin (QEMU or experimental libkrun, with a TypeScript control plane and a Pi extension) ([execution environments](../research/agentic-workspace-landscape/landscape/execution-environments.md)). Gondolin's egress and secret model is adopted whichever engine wins.
- **Rationale:** Apple's hypervisor avoids bundling QEMU (GPL-2.0). It supports saving and restoring VM state, shared folders and a native display. Reusing pi-env gives one execution path for VMs and remote machines.

<a id="d18"></a>
### D18. A browser for every bot
- **Status:** Accepted; amended by [D47](#d47) (2026-10-22): v1 uses WebKit on every device, and Chromium in a Bot computer moves to v1.1.
- **Choice:**
  - Each bot has a persistent browser profile behind one tool API with two engines:
    - **WebKit:** a `WKWebView` with a per-bot `WKWebsiteDataStore(forIdentifier:)`, hosted by the app, for bots on This Mac.
    - **Chromium over CDP:** inside the bot's VM, for bots with a Bot computer.
  - Sign-in cards fill credentials straight into the page, so the model never sees them.
  - Page content is always untrusted input.
  - Bots on a Remote machine browse with WebKit on the Mac.
- **Rationale:** WebKit gives native, visible co-browsing with no download, a pattern Kuvo Code has proven ([profile](../research/agentic-workspace-landscape/projects/kuvo-code.md)). Chromium inside a VM gives robust background automation, isolated from the host.

<a id="d19"></a>
### D19. Live view and takeover
- **Status:** Accepted; taking over a Bot computer moves to v1.1 with [D47](#d47) (2026-10-22).
- **Choice:**
  - The inspector shows any bot's browser or computer live.
  - **Take over** pauses the bot and hands control to the user; **Hand back** resumes the bot with a note of what changed.
  - Views can be detached into their own window.
- **Rationale:** Every leading product offers watch-and-take-over, for logins, CAPTCHAs, 2FA and payments ([Grok Bot](../research/agentic-workspace-landscape/projects/grok-bot.md), [Dots](../research/agentic-workspace-landscape/projects/openai-dots.md)).

## Bots and the Assistant

<a id="d20"></a>
### D20. The Assistant
- **Status:** Accepted; amended by [D49](#d49) (2026-10-22): the Assistant runs on every device.
- **Choice:**
  - The Assistant is a special, pinned bot; there is exactly one per user, and the user picks its display name.
  - **What it can do:**
    - read and propose writes to the **user** memory scope;
    - see every bot's status and the Inbox;
    - delegate through Handoffs;
    - propose new bots, routines and grants;
    - run the daily brief;
    - be the front door for future channels (iPhone, Telegram).
  - **What it cannot do:**
    - bypass policy;
    - read a bot's private memory without a grant;
    - get a Bot computer by default.
- **Rationale:** This is the white space: no product ships an assistant that owns a team ([landscape §6](../research/agentic-workspace-landscape/README.md#6-white-space-memoshi-can-own)). The pattern comes from boop's dispatcher, [Apollo](../research/agentic-workspace-landscape/landscape/in-house-assets.md#apollo) and the [2026-10-17 blueprint](../research/prior/apollo-zeron-unpeel-2026-10-17.md).

<a id="d21"></a>
### D21. Bot identity and creation
- **Status:** Accepted
- **Choice:**
  - A bot has: name, avatar, job, persona, model and effort, computer, browser, grants, routines, memory and budget.
  - The persona is stored in the app record. The bot cannot edit it; changes it proposes become cards with version history.
  - Bots are created by conversation (a new bot asks "What's my job?") or from a template.
  - A bot, or the Assistant, may create another bot only through a proposal card.
- **Rationale:**
  - Persona-in-record prevents self-rewriting identity (Aiden).
  - Self-edits as proposals come from Rakazo.
  - "Job lives in memory" onboarding comes from Kuvo.

  ([profiles](../research/agentic-workspace-landscape/projects/aiden-agent.md))

<a id="d22"></a>
### D22. Memory
- **Status:** Accepted
- **Choice:**
  - **Scopes:** user (owned by the Assistant), bot, team, and project.
  - **Entry fields:** provenance (source event), author, validity window (from/to, so a fact can become "no longer true"), visibility, and status.
  - **Writes:**
    - A bot writes its own scope freely within a bounded per-turn load budget (initially 64 entries or 8 KB).
    - Writes to the user and team scopes are proposals.
    - All writes are scanned for secrets and injection.
  - **Maintenance:** a nightly consolidation pass produces a reviewable diff. It is ported from boop and keeps boop's three stages: a proposer, an adversary, and a judge.
  - **Search:** SQLite FTS5. Embeddings are optional later.
  - **Rule:** "Memory is evidence, not authority": a bot re-checks the current source before a consequential action.
- **Keeps:** Draft 3 D22 (FTS5, no vector DB in v1).

<a id="d23"></a>
### D23. Proactivity
- **Status:** Accepted
- **Choice:**
  - **Triggers:** schedules (cron or RRULE with a time zone, at most every 5 minutes), intervals, one-time runs, self-scheduled wakes, model-free watches, connector events, and webhooks. Webhooks are local (loopback receiver, CLI, Shortcuts) in v1; public webhooks arrive through the relay in v1.1.
  - **Who creates routines:** bots propose them and the user approves.
  - **Quiet runs:** a run with nothing new ends with `no_update`. It sends no notification and leaves no line in the bot's Chat; it appears only in the routine's run history. A run with news posts one summary line.
  - **Policies:** missed-run, concurrency and auto-pause (after repeated failures, or 7 days without the user).
  - **Origin rule:** a run started by a trigger can never change instructions, grants or the roster.
- **Rationale:** Every cost incident in the category came from unbounded autonomy: Grok Bot loops, and Dots burning tokens unprompted ([landscape §5.4](../research/agentic-workspace-landscape/README.md#54-proactivity-without-runaway-cost)).

<a id="d24"></a>
### D24. Groups and handoffs
- **Status:** Accepted; amended by [D47](#d47) (2026-10-22): Groups, bot-to-bot hops and the hop cap move to v1.1, and Handoffs to one bot stay in Phase 1.
- **Choice:**
  - A Group has 2–6 bots plus the user, with one lead.
  - The lead plans and assigns. Members work in their own tasks and report back. Members may pass silently.
  - **Limits:** at most 4 rounds per user message, and at most 8 bot-to-bot hops per thread, with a loop guard.
  - **Handoffs:** every delegation is a Handoff record (goal, context references, expected output, acceptance criteria, deadline, status, evidence), re-injected on every turn.
  - **Phasing:** Handoffs from the user or the Assistant to a single bot ship in Phase 1, because they carry the product thesis. Groups, bot-to-bot hops and the hop cap ship in Phase 3.
- **Rationale:** Lorca's and Kuvo's group protocols, plus Grok Bot's loop incidents ([landscape §5.5](../research/agentic-workspace-landscape/README.md#55-multi-bot-collaboration)).

<a id="d25"></a>
### D25. Budgets
- **Status:** Accepted; group budgets move to v1.1 with Groups ([D47](#d47), 2026-10-22).
- **Choice:**
  - Token and money budgets per bot, routine and group: a warning at 80% and a hard stop at 100%.
  - A cost preview is shown before a routine is enabled, estimated from model prices and past runs.
  - Usage appears in the menu bar.
  - **Phasing:** a budget floor ships with routines in Phase 1: a per-run cap for unattended runs (default $1) and a monthly stop per bot. Full budgets, group budgets and cost previews ship in Phase 3.
  - **Handoff budgets:** a Handoff may carry its own cap, set by whoever delegates. It is enforced like a routine budget and never exceeds the receiving bot's remaining budget. Handoff caps ship with full budgets in Phase 3 (BU-03). Until then, a Handoff's work counts against the receiving bot's Phase 1 budget floor.
  - **Enforcement:** stops are enforced by wrapping pi-ai's model calls and aborting at 100%, because Pi ignores a throwing `beforeRequest` hook ([`04-architecture.md`](04-architecture.md)).
- **Rationale:** Only paperclip ships budgets today; no product previews cost ([long tail](../research/agentic-workspace-landscape/landscape/oss-long-tail.md#5-patterns)).

<a id="d26"></a>
### D26. Portable bot format
- **Status:** Accepted
- **Choice:**
  - `bot.md`: YAML front matter (identity, job, model, computer, browser, grants, routines, skills) plus a Markdown persona.
  - Export and import are included in v1; exporting memory is opt-in. Signed bundles come later.
- **Rationale:** No portable bot format exists in the category ([long tail](../research/agentic-workspace-landscape/landscape/oss-long-tail.md#5-patterns)). Spec: [`../specs/bot-definition.md`](../specs/bot-definition.md).

## Safety and privacy

<a id="d27"></a>
### D27. Policy: tiers, modes and rules
- **Status:** Accepted; its approval modes are superseded by [D52](#d52) (2026-10-22): each bot is in Ask first, Auto or Bypass, and bots in Bypass skip the draft card for T4. Its unattended column stays, in Ask first and Auto alike ([D57](#d57)).
- **Choice:**
  - Risk tiers T0–T5 and approval modes (Ask, Auto, Plan, Read-only), as in [MASTER_PLAN §10](MASTER_PLAN.md#10-safety-at-a-glance).
  - MCP tools are classified by verb. Unknown tools ask, and are denied in Plan, Read-only and untrusted runs.
  - Draft-before-send for all T4 actions.
  - Runs started by a trigger or another bot never escalate without an attended user decision. Each task runs under a regime (attended, unattended or untrusted) set by where its chain started.
  - Secrets are used by reference only. Egress goes through allowlists.
  - Approvals expire to denied: after 30 minutes when attended and 10 minutes when unattended, and T5 approvals always after 10 minutes. An expired card for a T1–T3 action offers "Always allow next time". Standing rules last 1–90 days and never cover T4 or T5.
  - Every decision is audited.
- **Rationale:**
  - Approval by verb and origin rules come from Rakazo; standing rules from an expired card come from Grok Bot.
  - The weak open-source defaults are an anti-pattern ([landscape §5.6](../research/agentic-workspace-landscape/README.md#56-approvals-secrets-and-safety)).
- **Keeps:** Draft 3 D18. Spec: [`../specs/policy.md`](../specs/policy.md).

<a id="d28"></a>
### D28. Telemetry
- **Status:** Accepted
- **Choice:**
  - Telemetry is off by default.
  - With opt-in, anonymous usage and error data is collected (IDs, durations, error kinds). Prompts, code, file names or tool output are never collected.
  - Diagnostics export is local and user-initiated.
- **Rationale:** Opt-out telemetry in T3 Code, paperclip and Kuvo Code is a trust cost ([landscape §5.6](../research/agentic-workspace-landscape/README.md#56-approvals-secrets-and-safety)).

## Design

<a id="d29"></a>
### D29. Design direction
- **Status:** Accepted, re-sequenced by [D43](#d43) (2026-10-20). v1 builds Kuvo Code's look and motion. Aiden's motion system and the Grok-style roster and avatars move to later design passes.
- **Choice:**
  - **Information architecture and review loop:** Kuvo's.
  - **Visual restraint and motion system:** Aiden's, pinned to Aiden 0.36.1 (commit `f87e9e7f`). Aiden has since changed its streaming, ticker and timing defaults; [`03-design-system.md`](03-design-system.md) records the differences.
  - **Bot roster and avatars:** Grok-style.
  - All of it native SwiftUI, with Liquid Glass for chrome only. The explicit list of glass surfaces is in [`03-design-system.md`](03-design-system.md) and [`09-platform-macos.md`](09-platform-macos.md); glass never sits over live views.
  - **Motion must carry state, causality or progress.** Idle UI is still, except avatar state signals.
  - Every motion has a Reduce Motion form and a frame budget.
  - Web views are for content only: previews, artifacts, inline widgets, browsing.
- **Rationale:**
  - The user chose "Aiden Agent's design and animations".
  - Aiden's motion inventory and GPUI parity audit are the best available spec. The parity audit is incomplete, so treat it as a spec with gaps.
  - Grok's assets are proprietary: we draw our own.
- **Supersedes:**
  - Draft 3 D1 ("Kuvo is the base"; restyle-free) and D23 (tokens from a Kuvo audit).
  - Draft 3's "No bouncing, no parallax, no decorative loops" rule, replaced by "motion with meaning".
- **Keeps:** Draft 3 D20 (embedded web only for content), extended to inline widgets and browsing.

<a id="d30"></a>
### D30. Accessibility
- **Status:** Accepted
- **Choice:**
  - WCAG 2.2 AA, full keyboard access and VoiceOver.
  - Honor Reduce Motion, Reduce Transparency and Increase Contrast.
  - Avatar states are never conveyed by color or motion alone.
- **Keeps:** Draft 3 principle 11.

## Platform and business

<a id="d31"></a>
### D31. Platform: macOS 27+ on Apple silicon, SwiftUI + AppKit
- **Status:** Accepted (re-confirmed); extended by [D56](#d56) (2026-10-22) with iOS 27+ and iPadOS 27+. Amended by [D84](#d84) (2026-10-22): its current-and-previous OS policy replaces the beta-signup trigger.
- **Choice:** Target macOS 27+ on Apple silicon, built with SwiftUI and AppKit. No Electron and no web shell.
- **Rationale:**
  - **Correction (2026-10-20):** Liquid Glass, Foundation Models and most APIs we depend on shipped in macOS 26. Checked against the macOS 27 SDK, the 27-only APIs we adopt mostly remove custom code. Draft 3 was wrong about two "SwiftUI 27" features ([`09-platform-macos.md`](09-platform-macos.md#2-the-os-floor-d31)).
  - What the floor buys: one OS to test and no `#available` branches.
  - v1 ships about six months out, so the target user will be on 27.
- **Trade-off:** Kuvo Code and Noodle chose macOS 26.0 for reach (Kuvo Code's public install docs, [kuvo.run/llms-full.txt](https://www.kuvo.run/llms-full.txt): "macOS 26 or later"; Noodle's `Info.plist`, 2026-10-20). Re-sourced on 2026-10-22 under [D55](#d55), which rules out reading Kuvo's app bundle.
- **Revisit if** either:
  - beta signups show more than 25% of interested users still on 26 [INFERENCE threshold] (settled by [D86](#d86), as [D84](#d84) decided: this trigger is dropped, and the current-and-previous policy alone sets the floor);
  - at the Phase 2 gate, supporting 26 would need fewer than about ten `#available(macOS 27, *)` branches.
- **Keeps:** Draft 3 D3 and D8.

<a id="d32"></a>
### D32. Distribution
- **Status:** Accepted; extended by [D56](#d56) (2026-10-22): the iPhone and iPad app ships through the App Store. [D67](#d67) (2026-10-22) sets that aside for v1: the iPhone and iPad app installs through TestFlight internal testing or Xcode.
- **Choice:**
  - Direct download, Developer ID signing, notarization and Sparkle updates.
  - No Mac App Store in v1: the daemon, VMs and deep file access conflict with the App Store sandbox.
- **Keeps:** Draft 3 D24 (now Accepted).

<a id="d33"></a>
### D33. License and reuse
- **Status:** Accepted. Amended by [D69](#d69) (2026-10-22): the iPhone and iPad app may link GPL-3.0 components (iSH), kept in their own module. Amended by [D91](#d91) (2026-10-23): Kuvo Code source inspection and personal/noncommercial code reuse are permitted; retained Kuvo material does not become Apache-2.0. [D92](#d92) replaces the historical clean-room appearance-parity reference below with a Viticci-led assistant/Kuvo-informed workbench hierarchy.
- **Choice:**
  - **Our license:** open core. The app and daemon are Apache-2.0; hosted services (relay, cloud computers, sync) are proprietary.
  - **Reuse rule:** we copy code only from permissive sources (MIT, Apache-2.0, BSD), with attribution.
  - GPL, PolyForm, source-available and proprietary products are ideas only: Lorca, Kuvo Code, Kuvo Box, OpenBot, multica, Grok Bot. We never copy any product's assets.
  - **Kuvo Code** is also the clean-room parity reference for look and behaviour ([D43](#d43)). That adds no right to copy anything from it.
- **Keeps:** Draft 3 D11 and D16.

<a id="d34"></a>
### D34. Name
- **Status:** Accepted (working name). Since [D59](#d59) (2026-10-22) the permanent identifiers no longer depend on the name, so a rename changes only what users see.
- **Choice:** Memoshi.
- **Before any brand work:**
  - clear the trademark;
  - assess the near-identical open-source project `felinics/Memoh` (AGPL-3.0, same concept) ([long tail](../research/agentic-workspace-landscape/landscape/oss-long-tail.md)).
- **Keeps:** Draft 3 D12.

<a id="d35"></a>
### D35. Team and timeline
- **Status:** Proposed; superseded by [D45](#d45) (2026-10-22): one builder with coding agents.
- **Choice:**
  - Team: 3 engineers (2 Swift, 1 TypeScript/runtime), plus product/design and 0.5 QA.
  - About 25 weeks to v1 (Phases 0–4).
  - A solo builder working with coding agents should plan on about 2–2.5× that, and apply the cut order in [`10-roadmap.md`](10-roadmap.md).
- **Keeps:** Draft 3 D15.

<a id="d36"></a>
### D36. Fresh repo; Draft 3 code is reference
- **Status:** Accepted (user direction, 2026-10-20). Amended by [D65](#d65) (2026-10-22): `~/Documents/Memoshi-Plan` continues as a separate prototype and moves to Pi_Swift later; this repo stays the source of truth.
- **Choice:**
  - This repo is the source of truth for plans and, later, code. The Draft 3 build in `~/Documents/Memoshi-Plan` is not continued.
  - **Port selectively:** the protocol package, transport replay and auth, the store and event-log pattern, policy and approvals, schedule/ids/bus utilities, and the smoke and chaos harnesses.
  - **Drop:** the fake-model runtime, the host-direct agent tools and the demo seed.
- **Rationale:** The Draft 3 runtime only ever ran Pi's fake model. Its agent tools act directly on the host, and its seeded agent can overwrite project files without approval ([audit](../research/agentic-workspace-landscape/landscape/in-house-assets.md#draft-3-build)).

<a id="d37"></a>
### D37. Channels
- **Status:** Accepted; amended by [D47](#d47) (2026-10-22): the iPhone and iPad app moves to v1.
- **Choice by release:**
  - **v1:** in-app, actionable macOS notifications, the menu bar extra, and App Intents/Shortcuts.
  - **v1.1:** iPhone and Telegram.
  - **v2:** Slack, bot-owned email addresses, and iMessage through `imsg` on the user's Mac.
  - **WhatsApp:** not planned. Its Cloud API bars general-purpose assistants since 2026-01-15, and the unofficial route risks bans ([building blocks](../research/agentic-workspace-landscape/landscape/platform-building-blocks.md#5-messaging-channels)).

<a id="d38"></a>
### D38. Mobile
- **Status:** Accepted; superseded by [D47](#d47) and [D48](#d48) (2026-10-22). Its pairing rule carries over.
- **Choice:**
  - **iPhone app (v1.1):** a remote client to the user's Mac over a self-hostable, end-to-end-encrypted relay.
  - **Pairing:** a one-time key in the QR code, mutually authenticated, never reusable.
  - **Push:** sent by our own APNs sender with content-free payloads.
- **Rationale:** Happy's and Orca's pairing flaws show what to avoid ([landscape §5.7](../research/agentic-workspace-landscape/README.md#57-phones-and-remote-access)).
- **Supersedes:** Draft 3 D10 (mobile in v2).

<a id="d39"></a>
### D39. Hosted services
- **Status:** Proposed; amended by [D48](#d48) (2026-10-22): the relay and its hosted instance move to v1.
- **Choice by release:**
  - **v1:** no hosted services. Static distribution hosting does not count: the website, DMGs, the Sparkle feed and signed Bot computer images are required in v1.
  - **v1.1:** the relay, self-hostable, with an optional hosted instance.
  - **v2:** cloud computers, E2B first, behind the computer seam, with cost shown per bot ([cost model](../research/agentic-workspace-landscape/landscape/execution-environments.md#3-cost-model-for-n-always-on-bots)).
- **Supersedes:** Draft 3 D14 (hosted cloud in v3).

<a id="d40"></a>
### D40. Business model
- **Status:** Open
- **Recommended default:**
  - The app is free and users bring their own keys and models.
  - Paid "Memoshi Cloud" later: hosted relay and push, cloud computers, encrypted sync, team bots.
  - Never resell tokens in v1.
- **Decide before a public release** (O13); it said "before beta" until [D67](#d67) made v1 personal.
- **Keeps:** Draft 3 D25 (Open).

<a id="d41"></a>
### D41. Apple platform leverage
- **Status:** Accepted; Virtualization.framework moves to v1.1 with Bot computers ([D47](#d47), 2026-10-22), and [D56](#d56) adds the rules for iPhone and iPad.
- **Choice:**
  - **Foundation Models**, for small on-device jobs only, with deterministic fallbacks.
  - **App Intents and Shortcuts** (they never bypass policy).
  - **Spotlight**, indexing titles only by default.
  - **WidgetKit**, open-only for approvals.
  - **SpeechAnalyzer** for on-device dictation.
  - **Actionable notifications.**
  - **Virtualization.framework** for Bot computers.
  - **ScreenCaptureKit and Accessibility:** not used in v1 or v1.1. Computer use on the user's own Mac is an exploration item (feature catalog EXPL-02) and needs a new decision. GUI computer use inside a Bot computer (v1.1) needs no host Screen Recording or Accessibility permission.
- **Keeps:** Draft 3 D27. Detail: [`09-platform-macos.md`](09-platform-macos.md).

<a id="d42"></a>
### D42. Crash recovery and resume
- **Status:** Accepted (added 2026-10-20 to settle principle 6 against Aiden's explicit Resume); extended by [D51](#d51) (2026-10-22). Its open mechanism is re-checked on Pi_Swift in spike S1 ([D46](#d46)).
- **Choice:**
  - After a crash or restart, a task whose next step is replay-safe resumes on its own.
  - A task that could repeat a side effect waits for an explicit **Resume** card. This covers any pending T4/T5 step, a non-replay-safe tool, or a nested call interrupted before its result was committed. The card shows what may have happened and what will run next.
  - Every side-effecting tool records an intent before it runs and its outcome after. If the outcome is unknown, the task is never retried automatically.
  - Each task carries its resume mode (`auto` or `explicit`), as specified in [`../specs/object-model.md`](../specs/object-model.md).
  - **Open mechanism:** Pi Durable 1.3 has no pause API, so where the adapter holds an `explicit` task is not yet verified. The candidates are a memo-keyed wait in `beforeRequest` or in `beforeTool`. Spike S1.13 decides ([04 open question 10](04-architecture.md#open-questions)).
- **Rationale:**
  - Pi Durable replays safely, but a replay-safe tool with external effects "still needs its own idempotency" (pi-durable README).
  - Aiden chose an explicit Resume to avoid silently repeated side effects ([profile](../research/agentic-workspace-landscape/projects/aiden-agent.md)).
  - Apollo records intent before dispatch and never retries an unknown outcome ([in-house](../research/agentic-workspace-landscape/landscape/in-house-assets.md#apollo)).
  - This keeps principle 6: work resumes, and a side effect never silently runs twice.

<a id="d43"></a>
### D43. Kuvo Code parity through a clean-room build
- **Status:** Accepted (user decisions, 2026-10-20), subsequently amended by D55, D81 and D85. [D91](#d91) supersedes its no-source/no-fork restrictions, observer separation and private-work legal prerequisite. [D92](#d92) (2026-10-23) supersedes its blanket 100/100 Kuvo visual/behavior parity and parity-spec precedence with a Viticci-led Apple-native assistant family and Kuvo-informed workbench. The choice below records the historical direction. First recorded from `~/Documents/Memoshi-Plan/HANDOFF-KUVO-CLEAN-BUILD.md`, then amended the same day:
  - no request goes to Kuvo's author;
  - v1 builds Kuvo's look and motion;
  - Memoshi's own design layer waits for later design passes.
- **Choice:**
  - **A clean build.**
    - Memoshi contains no Kuvo code, assets or text, and it is never started from a Kuvo fork.
    - Forking Kuvo, Noodle or Lorca as the product's base is ruled out.
    - If Kuvo's own frontend ever had to ship, the only path is a commercial licence from its author.
  - **v1: Kuvo's look and motion, 100/100.** On every surface the two apps share, v1 matches Kuvo Code exactly: layout, proportions, sizes, spacing, density, colours, materials, typography, motion, navigation, interaction patterns and behaviour.
    - Memoshi-only surfaces (the Assistant, the Inbox, Handoffs, Cards Kuvo doesn't have) use the same visual language.
    - Engineering effort goes to the system: Pi Durable, memoshid, policy, and the computers and browsers.
  - **Later: design passes.** Once the system is stable, design passes add Memoshi's own layer:
    - Aiden-derived motion for streaming, thinking, tool calls and cards;
    - a Grok-style roster with livelier bot avatars of our own;
    - optional Metal shader effects;
    - further UI and UX work found in dogfooding.

    A gate review schedules each pass. By default the first runs alongside Phase 5, after the v1 gate ([10-roadmap](10-roadmap.md#phase-5)); a gate may pull it earlier when the plan is ahead. The specs wait in [`03-design-system.md`](03-design-system.md#design-pass-backlog), and until a pass ships, the parity spec wins wherever they differ from it.
  - **Never parity:** policy, privacy, accessibility and the performance budgets ([D27](#d27), [D28](#d28), [D30](#d30), [`03-design-system.md`](03-design-system.md#performance-budgets)). Kuvo's defaults, such as Approve All and opt-out telemetry, are not targets.
  - **Always ours:**
    - all code;
    - the name, app icon and logo, and custom icons;
    - bot characters and their animations;
    - illustrations and sounds;
    - UI text and docs.

    Where Kuvo uses its own art, the parity spec says what the art communicates and asks for a Memoshi original. In v1, the avatars are our own art with Kuvo's state behaviours ([`03-design-system.md`](03-design-system.md#avatar-system)). The spec never measures or describes Kuvo's bot characters beyond that state vocabulary.
  - **Clean-room process:**
    1. **The observer (PD)** writes `docs/specs/kuvo-parity.md`. It covers every shared screen and state, including empty and error states, plus measurements, semantic tokens, motion timings and flows.
       - Sources: the running app and Kuvo's public site and docs. For exact values and behaviour, the observer may also read Kuvo's source.
       - The spec carries numbers, descriptions and flows only: no code, no copied text, no assets.
    2. **Builders** (engineers and coding agents) implement from the parity spec, 02, 03 and the tokens. Kuvo's repository, any Kuvo fork and any Kuvo source excerpt never enter a builder's context or prompt.
    3. **Captures stay private.** Screenshots and recordings of Kuvo stay in the observer's folder outside this repository, because the repository will be public under Apache-2.0.
    4. **Review:**
       - side-by-side screenshot parity in design QA ([`03-design-system.md`](03-design-system.md#design-qa));
       - a provenance register: `NOTICE` plus per-file provenance headers ([R16](risks.md#r16));
       - before each release, a scan of the tree and the app bundle for Kuvo-specific names, strings and assets.
  - **Legal position: an accepted risk.**
    - The user's reading: Kuvo's author allows forks and copying for personal use, and objects to someone renaming the same app and selling it. Memoshi is a different product with different features, built clean-room, so no request goes to the author.
    - Design law still applies to an identical chrome. Regulation (EU) 2024/2822 counts graphical user interfaces as products, and counts a design's "movement, transition or any other sort of animation" as part of the design. An unregistered EU design protects against copying for three years from first disclosure in the EU, and the owner can still register within 12 months ([EUR-Lex](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32024R2822)).
    - The user accepted that risk ([R37](risks.md#r37)). A lawyer reviews Memoshi before it ships publicly or is sold (the Phase 4 launch checklist), as the addendum asked.
- **Rationale:**
  - Kuvo Code is under PolyForm Noncommercial 1.0.0 (its public [`LICENSE`](https://github.com/serhatandic/kuvo-code/blob/main/LICENSE); re-sourced on 2026-10-22 under [D55](#d55) from a copy in the installed 0.5.22 bundle).
    - "Any noncommercial purpose is a permitted purpose", and the terms "do not allow you to sublicense or transfer any of your licenses".
    - Memoshi is open core with paid tiers ([D33](#d33), [D40](#d40)). Building on Kuvo's code would be commercial use, and the result could not be relicensed under Apache-2.0.
  - Kuvo Code is built around the opencode engine, so a fork moved to Pi would rewrite its core anyway ([profile](../research/agentic-workspace-landscape/projects/kuvo-code.md)) [INFERENCE]. (Edited 2026-10-22 under [D55](#d55) to remove a detail taken from Kuvo's source.)
  - The user's priority is the system: Pi Durable in a native Swift app, with the look of Kuvo Code, the best of the native Swift apps reviewed (Kuvo Code, Noodle, Lorca). Design passes follow when the project reaches a stable stage. This also keeps the Aiden motion port and the Grok-style roster off v1's critical path.
- **Supersedes:**
  - D29's design clauses for v1. Kuvo's look and motion replace Aiden's visual restraint and motion, and the Grok-style roster, until the design passes.
  - Restores Draft 3 D1 (Kuvo as the base) and D23 (tokens from a Kuvo audit), in clean-room form.
- **Consequences:**
  - Phase 0 ticket P0-19 writes the parity spec ([phase-0](phase-0.md#tickets)). Its tokens and motion sections come first, because P0-13 builds the design primitives from them.
  - Token values and motion recipes in [`03-design-system.md`](03-design-system.md) and [`design-tokens.json`](../specs/design-tokens.json) are provisional on shared surfaces until the spec lands.
  - New risk R37; R14 and R29 change.
  - The roadmap schedules design passes at gates ([10-roadmap](10-roadmap.md#phase-5)).
  - The launch checklist gains the provenance scan and the lawyer's review ([10-roadmap](10-roadmap.md#phase-4)).

<a id="d44"></a>
### D44. Engine: Pi_Swift, always on the latest upstream Pi
- **Status:** Accepted (user decisions, 2026-10-22). Its Memoshi-Plan line is made precise by [D65](#d65): the prototype moves to Pi_Swift once Pi_Swift's product slice compiles. Amended by [D90](#d90) (2026-10-23): that point is Pi_Swift's slice-ready state.
- **Choice:**
  - Memoshi's engine is **Pi_Swift** (`~/Documents/memoshi/Pi_Swift`), the native Swift port of upstream Pi, used as Swift packages. The Memoshi-Plan build moves to it too.
  - **Always latest.** Pi_Swift follows the latest upstream `main` of `earendil-works/pi`, and Memoshi follows the latest Pi_Swift. The first catch-up targets upstream's latest `main` at the time it starts, which already includes v1.4.0.
  - **Tracking.** Agents update Pi_Swift with its runbook, `Pi_Swift/docs/UPSTREAM-SYNC.md`:
    1. a worklist from `Scripts/upstream-delta.swift`;
    2. porting;
    3. upstream's tests and the Swift tests;
    4. then the pin in `UPSTREAM.lock.json`.
  - **Kept from D6:**
    - only the runtime adapter imports Pi types;
    - every engine update passes the contract tests;
    - the fallback (the agent loop plus our own durability layer) stays sized, not built.
  - **User data.** An engine update that migrates stored data backs up the store first. Migrations only go forward; returning to an older engine means restoring the backup.
- **Rationale:**
  - The user wants one native engine on Mac, iPhone and iPad. Viticci's app shows the pattern ([full record](../research/2026-10-21-viticci-full-record-sep-oct.md), [follow-ups](../research/2026-10-22-viticci-followups.md)).
  - npm publishes releases only, so following `main` from Node would mean building Pi from source, which the [Pi brain refresh](../research/2026-10-20-pi-brain-refresh.md) rules out. Pi_Swift ports from upstream's source, so `main` is its natural input ([follow-ups §7](../research/2026-10-22-viticci-followups.md#7-following-upstream-pi)).
- **Supersedes:** D6's package choice, the npm packages at "1.3.x, pinned to exact versions".
- **Consequences:**
  - **Decisions to review**, because they assume Pi runs in a bundled Node daemon:
    - D12 (memoshid as the Node runtime);
    - D13 (Node-specific peer checks);
    - D14 (Pi Durable storage, whose format is now upstream's latest);
    - D15 (bundled Node);
    - D38 (iPhone as a remote client only);
    - D42 (its note on Pi 1.3's missing pause API).
  - **Plan docs to review**, because they carry the same assumption: `04-architecture.md` (contract C20 and the `@earendil-works/*` import rule), `08-security-and-privacy.md` (TM-13), `09-platform-macos.md`, `phase-0.md` (spike S1), `risks.md` (A3), `01-product.md` and `NEXT_VERSION.md`.
  - **Roadmap review** (change-control rule 3). Phase 0 starts on 2026-10-26, and its spike S1 assumed npm Pi in Node. Pi_Swift does not compile yet, so S1 now waits on Pi_Swift's product slice compiling and passing its tests.
  - **Memoshi-Plan** changes its own plan:
    - its `MASTER_PLAN.md` says "Do not embed Pi in Swift";
    - `docs/02-architecture.md` rejects "Embed Pi in Swift";
    - `sidecar/package.json` pins `@earendil-works/pi-durable` 1.3.0.
  - The Pi brain refresh's "Never build Pi from `main`" now applies only to npm consumers, such as Apollo.

<a id="d45"></a>
### D45. Team: one builder with coding agents
- **Status:** Accepted (user decisions, 2026-10-22). Supersedes [D35](#d35); closes O9. Its calendar was superseded by D66/D70 and then [D87](#d87); its friendly alpha is optional under [D67](#d67). [D93](#d93) (2026-10-23) supersedes the mandatory contracted-designer allocation; one builder with coding agents and the required design QA remain.
- **Choice:**
  - Memoshi is built by one person directing coding agents. Design help is contracted: about 5 days in Phase 0, and design QA before the beta.
  - The roadmap's solo calendar becomes the plan, re-sized for the scope in D46–D56:
    - Phase 0 runs 5 weeks, Mon 2026-10-26 to Fri 2026-11-27;
    - the v1 gate moves from Fri 2027-11-19 to about **Fri 2028-01-14**, about 6 more plan weeks counting the year-end break [INFERENCE, from feature-catalog row counts]. The user chose the later date over cutting scope.
  - Level 1 cuts apply from the start, and the cut order stays the safety valve.
  - The plan's roles (APP, NAT, RT, PD, QA, EL) become hats that one person wears with agents. Nothing assumes people working in parallel. The friendly alpha (at least 3 testers) replaces "the team" in the dogfood criteria.
  - Pi_Swift is planned and built in its own repository by its own agent. Memoshi takes it through [D46](#d46)'s gate.
- **Rationale:** D35's three-engineer team was never staffed; O9 had been open since 2026-10-20.
- **Consequences:** [`10-roadmap.md`](10-roadmap.md)'s solo calendar becomes its main calendar. [`phase-0.md`](phase-0.md) is rewritten for one person over 5 weeks. Dogfood criteria, costs and gate-review roles change.

<a id="d46"></a>
### D46. Pi_Swift on every device: gate, fallbacks and process model
- **Status:** Accepted, gated at the Phase 0 review (user decisions, 2026-10-22). Extends [D44](#d44). Supersedes [D15](#d15) and the Node parts of [D12](#d12) and [D13](#d13), which completes D44's review of those three. Its Mac packaging is amended by [D58](#d58) (2026-10-22): memoshid ships as an app-shaped helper with its own provisioning profile.
- **Choice:**
  - **One engine everywhere.** Pi_Swift ([D44](#d44)) runs in memoshid on the Mac, and inside the app on iPhone and iPad.
  - **Mac:** D12's two processes stay. Memoshi.app hosts the UI and the native capabilities. **memoshid** becomes a signed Swift executable, registered as a LaunchAgent through `SMAppService`, and it survives app restarts, crashes and updates as before. No Node, native addon or JIT entitlement ships.
  - **iPhone and iPad:** no daemon. A turn keeps running in the background inside a `BGContinuedProcessingTask` that shows its progress, and committed turns resume at launch (Pi_Swift requirements E1–E3). One writer per store across the app, widgets, intents and extensions (E4, extended by [D49](#d49)).
  - **Transport ([D13](#d13)):** JSON-RPC 2.0 over a WebSocket on the Unix socket stays. Each side checks the other's code signature and team ID through the connection's audit token, and the app checks the daemon's signature before it releases secrets. The Node-only checks are dropped: the `execv` hand-over to `Helpers/node`, the interpreter arguments and the native addon.
  - **The gate,** at the Phase 0 review on Fri 2026-11-27, on macOS and on iOS:
    - upstream's storage and environment conformance suites pass;
    - 50 random kills give 50 correct resumes and 0 duplicated effects;
    - every tool call, nested ones included, gets a policy decision;
    - 10 of 10 pending approvals survive a kill;
    - on iOS also: swiping the app away during a continued-processing task and relaunching resumes correctly; a second open of the same store is refused; Code Mode finishes within its time limit on a mid-range iPhone.
  - **If the Mac misses the gate,** memoshid goes back to upstream Pi in bundled Node, as D6, D12, D13 and D15 read on 2026-10-20. Pi_Swift stays on iPhone and iPad.
  - **If iOS misses the gate,** v1's iPhone and iPad app is a remote screen for bots that run on the Mac, over [D48](#d48)'s links. Running bots on the phone or tablet ([D49](#d49), [D50](#d50)) moves to v1.1, and the v1 date holds.
  - D44's last-resort fallback, the agent loop plus our own durability layer, stays sized but not built.
- **Rationale:**
  - One codebase for tools, policy and storage on every device. iPhone and iPad need the engine inside the app, because iOS has no Node.
  - Without Node there is no runtime to bundle, sign and notarize (S5), and no general-purpose interpreter behind D13's extra peer checks.
  - Pi_Swift is early: on 2026-10-21 only PiCore, PiTelemetry and PiCodeMode type-checked (Pi_Swift requirements §2). The gate and the two fallbacks protect the calendar.
- **Consequences:**
  - Phase 0's spike S1 becomes this gate. The engine work happens in the Pi_Swift repository; Memoshi's Phase 0 integrates and measures it.
  - S5 drops Node packaging and adds the Swift daemon, the provisioning profile for CloudKit and push ([D56](#d56)) and a TestFlight build.
  - The repository needs no pnpm or Zod. ~~Protocol schemas stay JSON Schema, with Swift types generated from them [INFERENCE].~~ Since [D78](#d78) (2026-10-22), Swift types are the protocol's source of truth and the JSON Schema is generated from them.
  - This Mac's sandbox ([D16](#d16)) relied on Anthropic's `sandbox-runtime`, a Node library (Apache-2.0). It is ported to Swift or replaced by our own Seatbelt profile and egress proxy; spike S4 decides.
  - [D42](#d42)'s open mechanism, how an `explicit` task is held, is re-checked on Pi_Swift in S1.

<a id="d47"></a>
### D47. v1 scope: Mac, iPhone and iPad
- **Status:** Accepted (user decisions, 2026-10-22). Supersedes [D5](#d5) and D1's "one native Mac app". Changes [D16](#d16) to [D19](#d19), [D24](#d24), [D25](#d25), [D37](#d37), [D38](#d38) and [D41](#d41) as listed below. v1 gains Python ([D60](#d60)), the Swift engine for live cards and mini apps ([D68](#d68)) and the emulated Linux computer through iSH ([D69](#d69)). Its "App Review applies to v1" no longer holds ([D67](#d67)).
- **Choice:**
  - **v1 ships on Mac, iPhone and iPad,** with the same bots on each ([D49](#d49)). The iPhone and iPad app is one universal app, with iPad layouts (sidebar, split view).
  - **Moved to v1.1 to make room.** These were the roadmap's level 3 cuts. Bot computers now move to v1.1 outright rather than shipping as a Developer-mode preview.
    - **Bot computers:** a Linux VM per bot on Virtualization.framework, with Chromium inside (CMP-01, CMP-06 to CMP-20, BRW-11, BRW-12). O2, O4 and the VM spike (the old Phase 0 spike S2; S2 is now the devices spike) move with them.
    - **Remote machines** over SSH (CMP-13 and its rows), next to the v1.1 always-on Mac host (R11-07). D16 called that host "the runner"; it is renamed so that "runner" keeps [D49](#d49)'s meaning, the device that runs a bot.
    - **Groups:** group chats with a lead, bot-to-bot hops and the hop cap (GR-01 to GR-03, GR-05 to GR-07, GR-09 to GR-11), and group budgets.
  - **Stays in v1:** Handoffs from the user or the Assistant to one bot (AS-08, GR-04, GR-08), and budgets for routines and Handoffs (BU-03).
  - **Every bot's computer in v1:** This Mac (sandboxed) on the Mac ([D16](#d16)); the in-app environment on iPhone and iPad ([D50](#d50)).
  - **Browsers in v1:** a WebKit profile per bot on every device ([D18](#d18)).
  - **Channels in v1** ([D37](#d37)): the iPhone and iPad app joins the v1 list. Telegram stays in v1.1.
- **Rationale:** The user's direction. Viticci's app was built iPhone- and iPad-first, and its phone agent runs without the Mac ([full record](../research/2026-10-21-viticci-full-record-sep-oct.md)). The three moved areas are the largest separable parts of the old Phase 3, and the roadmap already listed them as level 3 cuts.
- **Consequences:**
  - D19's takeover of a Bot computer and D41's Virtualization.framework line move to v1.1.
  - R11-01 to R11-05 (iPhone, pairing, relay, push, phone approvals) and EXPL-09 (iPad) enter v1. The roadmap's Phase 3 becomes iPhone, iPad and devices.
  - App Review applies to v1 ([D56](#d56)).

<a id="d48"></a>
### D48. Device links: direct, relay and iCloud
- **Status:** Accepted (user decisions, 2026-10-22). Supersedes [D38](#d38), except its pairing rule, and D39's "no hosted services in v1". Extends [D13](#d13). On the Mac, memoshid uses CloudKit and push itself ([D58](#d58)). Amended by [D75](#d75) (2026-10-22): everything that crosses devices is encrypted to one MLS group of the user's devices.
- **Choice:**
  - **Pairing** (kept from D38): a one-time key in a QR code, mutually authenticated and never reusable. Every device has its own keys, and any paired device can revoke a lost one.
  - **Three links, all end-to-end encrypted and chosen automatically:**
    1. **Direct:** on the same network (found through Bonjour), or at any address the user already reaches, such as a tailnet or VPN name. Live streaming.
    2. **Relay:** Memoshi's relay, self-hostable, with a hosted instance that we run. Live streaming, and store-and-forward away from home. Pushes go through our own APNs sender with content-free payloads.
    3. **iCloud:** the user's own CloudKit private database, used as a mailbox and sync log. Its fields are end-to-end encrypted (`encryptedValues`), and CloudKit subscriptions wake devices with content-free alerts. No Memoshi server is involved. Developer ID Mac apps can use CloudKit and push with a Developer ID provisioning profile ([Apple](https://developer.apple.com/developer-id/)).
  - **Order:** direct first, then the relay, then iCloud. The relay and iCloud each carry everything a device needs to catch up, so either one alone is enough. The user can turn either off; with both off, devices sync only when they are directly connected.
  - **What the services see:** neither our relay nor Apple can read content. Both see metadata: timing, sizes and device identifiers.
- **Rationale:** The user chose all three. Direct is fastest. The relay streams live anywhere and needs no iCloud account. iCloud works without any Memoshi server, and Apple delivers its wake-ups.
- **Consequences:**
  - [D39](#d39): the relay and its hosted instance become v1 services. Public webhooks through the relay stay in v1.1 ([D23](#d23)).
  - [D40](#d40): the hosted relay was a candidate paid service, and iCloud now offers a free path. Revisit before the beta (O11).
  - The protocol gains a device layer for pairing, links and replication ([`../specs/protocol.md`](../specs/protocol.md)). Pi's remote environment (Pi_Swift requirements E9b) runs over these links.
  - New risks: running a hosted service alone, CloudKit quotas and push throttling, and exposed metadata.

<a id="d49"></a>
### D49. Bots run on every device
- **Status:** Accepted, spike-gated (user decisions, 2026-10-22); the Phase 0 devices spike sets its targets (O10). Amends [D7](#d7), [D14](#d14), [D20](#d20), [D22](#d22) and [D23](#d23), and completes D44's review of D14. Amended by [D73](#d73) (2026-10-22): its "runner follows the user" bullet is superseded (an awake, reachable runner keeps the conversation and other devices forward), settings merge across devices, and hand-overs without the authority are provisional. Amended by [D74](#d74) (2026-10-22): the store, lease and runner are per conversation, not per bot. Amended by [D88](#d88) (2026-10-23): when neither the runner nor an allowed model is reachable, messages queue without an answer or effects.
- **Choice:**
  - **One bot, every device.** Every bot, the Assistant included, is on every paired device with the same identity, settings, memory and one continuous history. The user can talk to any bot from any device and sees its live state everywhere.
  - **One writer at a time.** Each bot has its own durable store. Exactly one device, the bot's current **runner**, writes it, under a lease that carries a fencing epoch. A write with an older epoch is rejected, so two devices can never run the same bot.
    - The lease is granted by a compare-and-swap on one authority: the user's CloudKit record when iCloud is on, otherwise the relay.
    - When neither is reachable, the lease moves only between devices that are directly connected.
    - This extends Pi_Swift's exclusive store lock (requirements E4).
  - **Live replicas.** Every other device keeps a replica of the bot's history, cards and status. Changes stream in real time over [D48](#d48)'s links, and a device that was offline catches up from the log.
  - **The runner follows the user.** When the user messages a bot from a device that is not its runner, the lease moves there as soon as the bot is idle or between committed steps: the old runner finishes its step and hands over, and the new one continues. If the runner is unreachable (a sleeping Mac, a phone app that was killed), its lease expires after a short timeout (O10), and another device continues from the last committed step. Anything that was in flight follows [D42](#d42) and [D51](#d51).
  - **Tools run where they live.** Every tool declares where it can run ([D50](#d50)):
    - the Mac only: the shell, Mac files, Mac-only command-line tools and local models;
    - iPhone and iPad only: frameworks that exist only there;
    - any device: data that iCloud already syncs (Reminders, Calendar, Contacts), Weather, Maps and the web.

    A runner calls another device's tools through Pi's remote environment over D48's links. Policy decides on the runner, and the device that executes re-checks its own grants. If that device is unreachable, the step waits ("Waiting for your Mac") under the normal approval expiry.
  - **Background work.** Routines, watches and wakes run on an awake Mac when one is available. iOS gives apps only limited background time, so a routine run by a phone or tablet may run late [INFERENCE] (settled by [D86](#d86): kept). A routine that needs Mac tools waits for the Mac.
  - **Offline.** A device that can neither reach the runner nor take the lease still answers. The message runs in a **side thread**: a child conversation on that device, with its own store. When the devices reconnect, the side thread's summary and results join the bot's history as an entry the runner sees, and memory written there syncs. Nothing is lost, and no store ever has two writers.
  - **Memory** ([D22](#d22)) syncs entry by entry, merging validity windows, statuses and deletions. A whole scope is never overwritten.
- **Rationale:**
  - The user asked for bots that run everywhere, seamlessly and in real time.
  - A lease with a fencing token is the standard way to keep a single writer across machines [INFERENCE; M. Kleppmann, "How to do distributed locking", 2016].
  - A Pi store must never have two writers: two harnesses on one store ran tasks twice (PiDurableKit issue #5, [record §8](../research/2026-10-21-viticci-apple-bots-record.md#8-swift-ports-of-pi-durable)).
  - Conversation histories cannot be merged safely, so the design never merges them; side threads join as entries.
- **Alternatives considered:** one home device per bot (a bot is unavailable while its device sleeps); a separate bot list per device; every device running its own copy of each bot (split histories and conflicting memory).
- **Consequences:**
  - [D7](#d7): a conversation's transcript lives once, in the runner's store, with read-only replicas elsewhere. [D14](#d14): every device keeps its own SQLite and event log, replicated. [D20](#d20): the Assistant runs on any device. [D23](#d23): routines prefer a Mac.
  - New engine requirements for Pi_Swift: a store per bot, an epoch-fenced lease, snapshots and a change feed, store hand-over, a remote environment between devices, and side threads as child conversations.
  - The specs gain the runner, lease, replica and side thread ([`../specs/object-model.md`](../specs/object-model.md)), and the lease and replication messages ([`../specs/protocol.md`](../specs/protocol.md)).
  - New risks: bugs in distributed state, iOS background limits and CloudKit throttling.

<a id="d50"></a>
### D50. Tools: typed, with a shell front end
- **Status:** Accepted (user decisions, 2026-10-22). Extends [D8](#d8) and [D16](#d16), and specifies Pi_Swift's in-app iOS environment (requirements E9c). Its Python note is settled by [D60](#d60), its Code Mode fallback was amended by [D64](#d64) and is now superseded by [D89](#d89) (2026-10-23), and [D63](#d63) and then [D69](#d69) add an optional emulated Linux computer, now in v1 through iSH. Its App Review consequence waits for a public release ([D67](#d67)).
- **Choice:**
  - **Typed tools are the source of truth.** Every capability is a typed tool that declares its parameters, effects, risk tier ([D27](#d27)), where it can run ([D49](#d49)), whether it is replay-safe, and how to check its outcome ([D51](#d51)). The Apple capabilities are Reminders, Calendar, Contacts, Music, Weather, Maps, Photos, Alarms, Health (read), Home, Shortcuts, Notifications and Files. One definition serves every device whose OS has the framework.
  - **A shell front end, generated from the same tools.**
    - On iPhone and iPad, where apps cannot start processes, the bot gets an emulated shell. It has app commands such as `reminders add …` and `calendar list …`, file commands (`ls`, `cat`, `grep`, `find`, `head`, `wc`) and pipes, over the bot's folder.
    - Each command line is parsed into typed tool calls before anything runs, so policy judges the typed calls, never the text. An unknown command fails.
    - On the Mac the bot keeps its real sandboxed shell ([D16](#d16)), with the same app commands installed as a command-line tool, so skills work on every device.
  - **Files:** the bot's folder in the app's container, plus folders the user links (security-scoped bookmarks).
  - **Code Mode** composes tools in one step on every device (PiCodeMode; JavaScriptCore is its fallback, requirements E7).
  - **Python** is not part of this decision. The [Python research](../research/2026-10-22-python-and-native-generative-ui.md#64-recommendation-inference) recommends Python on the Mac and Pyodide on iPhone; that needs its own decision.
- **Rationale:** The user chose both. Typed tools let policy judge every call exactly. A shell keeps models' fluency with commands and the command-line skills that Viticci's app and Open Minis use ([follow-ups §4](../research/2026-10-22-viticci-followups.md#4-open-minis-as-a-source-and-the-state-of-the-art-for-tools)).
- **Consequences:** [`../specs/policy.md`](../specs/policy.md) gains command-line parsing. The tool catalog is written once. Every command is a documented app feature for App Review ([D56](#d56)).

<a id="d51"></a>
### D51. Interrupted steps: check, then ask
- **Status:** Accepted (user decisions, 2026-10-22). Extends [D42](#d42).
- **Choice:**
  - A step with side effects that was cut off before its outcome was recorded shows in place as **"Interrupted: may have happened"**.
  - If its tool declares an outcome check ([D50](#d50)), such as "does the reminder exist?", "is the message in Sent?" or "does the event exist?", that read-only check runs automatically. When the answer is definite, the bot records it and carries on: if the step happened, it continues; if not, the step runs again under normal policy.
  - Otherwise a **Resume card** shows what may have happened and what will run next, with **Run again**, **Skip** and **Mark as done**. Bypass never skips this card ([D52](#d52)): it guards against doing something twice, not against a permission.
  - The card appears in the bot's Chat, in the Inbox and as a notification, on every device ([D49](#d49)).
  - Replay-safe steps (idempotent or keyed) still resume on their own (D42).
- **Rationale:** It keeps D42's rule that an unknown outcome is never retried blindly, with fewer cards. Viticci left the question unanswered ([record §6](../research/2026-10-21-viticci-apple-bots-record.md#6-what-the-audience-asked)).
- **Consequences:** Tool definitions gain an outcome check. The Resume card (CH-11) gains its three actions. Pi_Swift's recovery (requirements E2) reports interrupted steps.

<a id="d52"></a>
### D52. Permission modes: Ask first, Auto and Bypass
- **Status:** Accepted (user decisions, 2026-10-22). Supersedes [D27](#d27)'s approval modes (Ask, Auto, Plan, Read-only) and, for bots in Bypass, its draft-before-send rule. Clarified by [D57](#d57) (2026-10-22): runs started by outside content keep their drafts, runs nobody is watching use D27's unattended column in every mode, and Bypass keeps the card for unknown tools and `host_exec` patches.
- **Choice:**
  - Each bot has one permission mode, the same on every device. **New bots start in Ask first,** in Guided and Developer mode alike.
    - **Ask first:** D27's Ask column. Reads (T0) run; T1–T3 ask; T4 goes out as a draft card; T5 asks with typed confirmation.
    - **Auto:** D27's Auto column. Inside its sandbox, granted folders and allowed sites the bot acts (T0–T2); T3 asks; T4 goes out as a draft card; T5 asks with typed confirmation.
    - **Bypass:** no approval cards, except for:
      - spending money;
      - using, revealing or granting a login or other credential (sign-in cards);
      - changes to the bot's own permissions, grants, instructions or persona, which stay proposals ([D21](#d21), [D23](#d23)). Otherwise a bot could lift its own limits.

      T4 actions run without a draft card; the draft is still recorded and audited. Reaching sites beyond the allowlist is allowed and logged.
  - **Bypass is a deliberate switch.** It is off by default and turned on per bot after a confirmation that names the risks. A Bypass badge marks the bot wherever it appears.
  - **The same in every mode:** the sandbox and granted folders; every denial, including those of the untrusted regime; budgets; the audit log; Resume cards ([D42](#d42), [D51](#d51)); the origin rule ([D23](#d23)); approval expiry and standing rules (D27).
  - **Plan and Read-only are no longer modes.** Plan stays a per-session option for coding (`/plan`): it proposes without running anything above T0. Read-only becomes a property of a grant, such as a read-only folder.
  - Guided and Developer ([D3](#d3)) are unchanged.
- **Rationale:** The user's answers. It matches the "Ask First" and "Bypass" settings in Viticci's app ([record §5](../research/2026-10-21-viticci-apple-bots-record.md#5-media)), and gives power users Bypass.
- **Risk:** In Bypass, a prompt injection in a web page or an email can make a bot send, post, delete or reach a new site without a card. The sandbox, grants, budgets and audit log limit the damage and record it.
- **Consequences:**
  - [MASTER_PLAN §10](MASTER_PLAN.md#10-safety-at-a-glance)'s table gains a Bypass column, and [`../specs/policy.md`](../specs/policy.md)'s mode × tier × origin matrix changes with it.
  - The safety metric becomes: T4 and T5 actions without an approval or a draft, in Ask first and Auto bots: 0; money and credential actions without a card, in any mode: 0.
  - The composer's mode picker (CH-06) shows the three modes.

<a id="d53"></a>
### D53. Cards: native and generated
- **Status:** Accepted (user decisions, 2026-10-22). Extends [D8](#d8)'s card tool, and narrows [D29](#d29)'s web views for inline widgets. Extended by [D61](#d61) and then [D68](#d68) (cards and mini apps written in Swift and run by Memoshi's Swift engine); its catalog gains a `tabs` block (D68). Amended by [D79](#d79) (2026-10-22): native Apple-data cards are live views of the item.
- **Choice:**
  - **Native cards** for Apple data and for decisions: hand-built SwiftUI cards for Reminders, Calendar, Music, Weather, Maps, Contacts and Photos, and for approvals, drafts, sign-in, purchases and Resume. These are never generated.
  - **Generated cards** for everything else, such as flights, comparisons, plans and dashboards:
    - a bot describes a card in JSON, using Memoshi's catalog of about 25 SwiftUI building blocks (text, list, table, chart, map, image, form fields, buttons, progress and the like) in an A2UI-style schema;
    - the app validates the JSON against the catalog and draws the card natively on Mac, iPhone and iPad;
    - no code, HTML or scripts.
  - **Actions:** a button names an action, a tool call or a message, which passes policy like any other call. A purchase or sign-in button opens a native card drawn by the app, never a generated one.
  - **Data:** a card shows data from the bot's run. It cannot fetch anything by itself.
  - **Versions:** the catalog is versioned, and an unknown block renders as a plain fallback.
  - **Web content** keeps its D29 roles: previews, artifacts, MCP Apps and mini apps. Charts and tables planned as web widgets (CH-17) become native blocks. On iPhone and iPad, mini apps follow App Review 4.7 ([D56](#d56)).
- **Rationale:** The user's answer. JSON drawn by built-in blocks is data rather than downloaded code, which fits App Review 2.5.2 [INFERENCE]. A2UI and json-render show the pattern ([generative UI research §7](../research/2026-10-22-python-and-native-generative-ui.md#7-native-generative-ui-premade-and-generated-cards)). The research's later authoring paths, a Swift subset and JavaScript with signals, are not part of this decision.
- **Consequences:** [`03-design-system.md`](03-design-system.md) gains the block catalog, and a card schema spec joins `docs/specs/`. The feature catalog gains generated-card rows next to CH-09. Design QA covers generated cards.

<a id="d54"></a>
### D54. Sign in with ChatGPT in open-source builds
- **Status:** Accepted (user decisions, 2026-10-22). Supersedes [D10](#d10)'s Sign in with ChatGPT clause; closes O5.
- **Choice:**
  - Open-source, locally hosted Memoshi builds may offer OpenAI's official Sign in with ChatGPT plan usage: Pi's `openai-chatgpt` flow in Pi_Swift's PiAI, with one `ext_agent_host_id` per device.
  - Before any paid or hosted build, complete OpenAI's interest form.
  - API keys stay for images and voice, which plan usage does not cover, and for other providers.
  - Still never shipped: Anthropic, Google and Meta subscription sign-in, and the Codex CLI client-ID flow (Pi_Swift requirements E11's build switch).
- **Rationale:** OpenAI: "These docs explain ChatGPT plan usage for open-source and locally hosted apps. If you're interested in offering it in a paid or remotely hosted app, complete the interest form." D10 was stricter than OpenAI's terms ([follow-ups §2.3](../research/2026-10-22-viticci-followups.md#23-what-the-vendors-allow-retrieved-2026-10-22-unless-marked)).
- **Consequences:** R11-13 moves into v1. Phase 0's admin ticket drops "apply for O5". Plan usage has preview limits: `store: false` and `stream: true` are required, and image generation and audio input are unsupported.

<a id="d55"></a>
### D55. Kuvo clean room: a separate observer, no source
- **Status:** Accepted (user decisions, 2026-10-22), then superseded in part by [D91](#d91) (2026-10-23): source inspection and personal/noncommercial code reuse are allowed, with no observer/builder segregation or lawyer-before-reference gate. The choice below records the former policy; private captures still stay outside the repository. [D92](#d92) replaces D43's visual-parity target. [D86](#d86)'s exclusion of a personal fork is amended by D91.
- **Choice:**
  - **The observer is a separate agent** with its own session and context, and it never builds Memoshi. It works only from the running Kuvo Code app and Kuvo's public website and docs. It never reads Kuvo's source code or the internals of its app bundle.
  - **Nobody on the build side reads Kuvo's source:** neither the user, who directs the builders, nor any builder agent.
  - **Kuvo source material leaves this repository before its first commit,** so it never enters git history. A scan on 2026-10-22 found 21 such passages in the plan and 50 in the research. Values the plan took from Kuvo's source are either re-measured by the observer from the running app or public docs, or replaced by Memoshi's own values marked [INFERENCE]. Values from Draft 3's "Kuvo audit", whose method is unknown, are provisional until the observer re-measures them.
  - **A lawyer reviews the clean-room process and the parity scope before the parity spec (P0-19) starts,** and again before launch (D43).
  - Captures of Kuvo stay outside the repository (D43).
- **Rationale:** Under D43's process of 2026-10-20 the observer could read Kuvo's source, and the repository held source-derived passages that builders read. Both weaken the clean-room position under PolyForm Noncommercial 1.0.0 and EU design law (D43).
- **Consequences:** P0-19's sources change, and it starts after the legal review; until the spec lands, P0-13 builds the design primitives on provisional tokens. The research profile [`kuvo-code.md`](../research/agentic-workspace-landscape/projects/kuvo-code.md) keeps only public facts, and `matrix.md` is regenerated from it. R37 changes.

<a id="d56"></a>
### D56. Apple platform rules for Mac, iPhone and iPad
- **Status:** Accepted (user decisions, 2026-10-22). Extends [D31](#d31), [D32](#d32) and [D41](#d41). Amended by [D58](#d58) (2026-10-22): S5 creates a second provisioning profile, for memoshid. Its account and identifiers are set by [D59](#d59). Its App Store distribution and App Review rules are set aside by [D67](#d67) (2026-10-22): v1 is for the user's own devices.
- **Choice:**
  - **Platforms:** macOS 27+ on Apple silicon (D31), iOS 27+ and iPadOS 27+.
  - **Distribution:** the Mac app stays Developer ID-signed and notarized, with Sparkle updates (D32). The iPhone and iPad app ships through the App Store, with TestFlight for the alpha and beta.
  - **Certificates:** the ship-path spike (S5) issues Developer ID certificates from Apple's G2 Sub-CA. Certificates from the original Sub-CA stop working on 2027-02-01 ([Apple](https://developer.apple.com/news/?id=w4atic4c)). Renewal becomes a yearly release-calendar item. S5 also creates the Developer ID provisioning profile with iCloud (CloudKit) and push ([D48](#d48)).
  - **Full Disk Access:** Memoshi never requests it. Apple said on 2 October that granting it will need "very explicit user action" ([Apple](https://developer.apple.com/news/?id=p6zjojqw)). Features that read other apps' databases are out.
  - **App Review (iPhone and iPad):**
    - generated cards are data drawn by built-in blocks, and nothing downloaded adds or changes a feature (2.5.2);
    - every feature, including the shell commands ([D50](#d50)) and Code Mode, is documented in the app and in the review notes, with nothing hidden or dormant (2.5.19);
    - mini apps follow 4.7, 4.7.2 and 4.7.3.
  - Read the Developer Program License Agreement changes of 13 October before the iPhone phase.
- **Rationale:** The user's answer, based on Apple's developer news of 1, 2, 13 and 16 October ([record §10](../research/2026-10-21-viticci-apple-bots-record.md#10-apple-platform-facts)).
- **Consequences:** S5 changes. [`09-platform-macos.md`](09-platform-macos.md) gains an iPhone and iPad section. New risks: App Review rejection and certificate expiry.

<a id="d57"></a>
### D57. Bypass and runs nobody is watching
- **Status:** Accepted (user decisions, 2026-10-22). Clarifies [D52](#d52) and keeps [D27](#d27)'s unattended column. Closes O12.
- **Choice:**
  - **Runs started by outside content keep their drafts.** In the untrusted regime (webhooks, connector events, App Intents and Shortcuts), T4 actions go out as draft cards in every mode, Bypass included.
  - **Runs nobody is watching follow one set of rules.** Routines, wakes and watches use D27's unattended column in Ask first and Auto alike, so a routine has no mode of its own:
    - T1 writes in the bot's own home run, and writes to project files ask;
    - T2 runs in a Bot computer (v1.1), and asks on This Mac and in the in-app environment unless a standing rule covers it;
    - T3 is denied unless granted; T4 is a draft card; T5 is denied.

    In Bypass, these asks become allows and drafts are sent at once, and every denial stays. Unattended approvals still expire after 10 minutes, and expired means denied (D27).
  - **Bypass also keeps the card for:**
    - unknown tools, because policy cannot tell whether they spend money or use a credential. After the first card, a standing rule ("Always allow") quiets that tool;
    - patches to files that make the Mac run code outside the sandbox (`host_exec`: git hooks and git config, `.husky`, `.envrc`, VS Code tasks, launch and settings files, `.devcontainer`), because the sandbox blocks those writes in every mode.
  - **Credential actions** under D52 include giving a connector more access, writing secret files such as `.env`, and commands that print a credential, such as `gh auth token`.
- **Rationale:** The user's answers.
  - A hostile email or webhook must not be able to make a bot send before anyone looks.
  - Every new bot starts in Ask first. Routines that asked before every write would fail while the user is away, because their approvals expire after 10 minutes.
  - The two extra cards keep D52's promises: money and credentials always ask, and the sandbox is the same in every mode.
- **Consequences:**
  - The safety metric gains a line: T4 actions without a draft in runs started by outside content, in any mode: 0.
  - [`../specs/policy.md`](../specs/policy.md) §4.3, §4.4 and §4.7 and its vectors, [MASTER_PLAN §10](MASTER_PLAN.md#10-safety-at-a-glance) and [`08-security-and-privacy.md`](08-security-and-privacy.md) follow.

<a id="d58"></a>
### D58. memoshid ships as an app-shaped helper with its own provisioning profile
- **Status:** Accepted (user decisions, 2026-10-22). Amends [D46](#d46)'s Mac packaging and [D56](#d56)'s provisioning profile. Spike S5 checks it in its first week. Its identifiers are set by [D59](#d59).
- **Choice:**
  - **memoshid is an app-shaped bundle inside Memoshi.app,** at `Contents/Helpers/memoshid.app`, with no window and no Dock icon. It has its own bundle ID and its own Developer ID provisioning profile (`Contents/embedded.provisionprofile`) with iCloud (CloudKit, the same container as the app) and push. This is the pattern Apple documents for a daemon that needs a restricted entitlement ([Apple](https://developer.apple.com/documentation/xcode/signing-a-daemon-with-a-restricted-entitlement)).
  - **memoshid uses CloudKit and push itself,** for [D48](#d48)'s iCloud link and [D49](#d49)'s lease, so both keep working while the app is quit or has crashed. The engine calls iCloud the same way on Mac, iPhone and iPad.
  - **Unchanged:** D12's two processes; the `SMAppService` LaunchAgent registration, whose `BundleProgram` now points into the helper; the D13 transport and its code-signature checks; the Keychain broker. Secrets stay readable only by Memoshi.app, and memoshid's profile carries no keychain access group.
  - **If a windowless helper cannot register for push,** Memoshi.app receives the pushes and passes them to memoshid over the socket, and an awake Mac keeps its live relay connection. CloudKit stays in memoshid either way.
- **Rationale:** The user's answer. Apple says "a daemon is a standalone executable, so you can't embed a provisioning profile in it", and its fix is to "wrap your daemon in an app-like structure". If the app did memoshid's iCloud work instead, D49's lease authority would stop whenever the app was down. If S5 finds that macOS attributes granted-folder access to memoshid rather than to Memoshi.app, the same wrapper is already the fix ([`09-platform-macos.md`](09-platform-macos.md)).
- **Consequences:**
  - S5 creates two App IDs and two Developer ID provisioning profiles, and both are regenerated at each yearly certificate renewal (DIST-09).
  - S5 checks that the helper's profile validates in the notarized build, that a CloudKit compare-and-swap works from memoshid with the app quit, that the windowless helper can register for push, and which name privacy prompts show.
  - The peer checks pin memoshid's new designated requirement.
  - [`09-platform-macos.md`](09-platform-macos.md) §7, [`04-architecture.md`](04-architecture.md), [`../specs/protocol.md`](../specs/protocol.md) §6 and §12.3, [`phase-0.md`](phase-0.md) S5, the feature catalog (DIST-01) and [`risks.md`](risks.md) (A10, R3) follow.

<a id="d59"></a>
### D59. Apple developer account and permanent identifiers
- **Status:** Accepted (user decisions, 2026-10-22). Fills in [D56](#d56) and [D58](#d58), and separates the identifiers from [D34](#d34)'s working name. Its bundle-ID inference is settled by [D86](#d86) (2026-10-22): the Mac app has its own ID.
- **Choice:**
  - **Account:** an individual Apple Developer Program membership in the user's legal name. The user is its Account Holder, the only role that can create Developer ID certificates. The App Store seller and the Mac signing certificate show that name.
  - **Permanent prefix:** `com.mehmetcanbudak.memoshi`, used as `<prefix>` throughout the plan:
    - the apps' bundle IDs: `com.mehmetcanbudak.memoshi` for the iPhone and iPad app and `com.mehmetcanbudak.memoshi.mac` for the Mac app (settled by [D86](#d86); the one-shared-ID inference is withdrawn);
    - memoshid's bundle ID and LaunchAgent label: `com.mehmetcanbudak.memoshi.memoshid`;
    - the iCloud container: `iCloud.com.mehmetcanbudak.memoshi`;
    - the keychain access group and the App Group: `<TeamID>.com.mehmetcanbudak.memoshi.secrets` and `<TeamID>.com.mehmetcanbudak.memoshi.shared`.
  - These identifiers never change, even if the product is renamed (O8). A rename changes only what users see: the display name, the App Store name, the website and the update feed's address.
- **Rationale:** The user's answers. An individual membership needs no D-U-N-S number or company paperwork, so Phase 0 can start on Monday, and Apple converts an individual membership to an organization on request. iCloud containers can never be deleted or renamed ([Apple engineer](https://developer.apple.com/forums/thread/818604)), and a published App Store app keeps its bundle ID, so the prefix is set once, apart from the brand.
- **Consequences:**
  - P0-16 enrolls or renews the individual membership, then creates the two App IDs, the container and both profiles under this prefix.
  - The rename risk (R22) shrinks to visible names, and the question of when to name the container is settled.
  - Converting to an organization later keeps these identifiers only if Apple keeps the Team ID [INFERENCE: confirm with Apple before converting] (settled by [D86](#d86): kept).

<a id="d60"></a>
### D60. Python on Mac, iPhone and iPad
- **Status:** Accepted (user decisions, 2026-10-22). Settles [D50](#d50)'s Python note. v1: the Mac in Phase 2, iPhone and iPad in Phase 3, after S6. Amended by [D67](#d67): run-time packages on iOS; [D76](#d76): one Pyodide per bot, gateway networking and per-script approval; [D79](#d79): trimmed Pyodide, then the Mac, then native CPython; [D83](#d83): shared pinned CPython on the Mac; and [D85](#d85): notebook outputs and concurrent edits (all 2026-10-22). [D87](#d87) places the notebook extras in Drop 2.
- **Choice:**
  - **Mac:** Python 3 runs in each bot's This Mac sandbox ([D16](#d16)), with its own package environment in the bot's home [INFERENCE: a managed CPython installed by `uv` on first use; the Phase 2 spike picks the install path] (settled by [D86](#d86), as [D83](#d83) decided: memoshid installs one pinned, hash-checked CPython that every bot shares read-only, and each bot keeps its own packages). Packages such as numpy, pandas, SciPy and Matplotlib come from PyPI through the package-registries egress preset. Heavy research and backtests run here, and bots on iPhone or iPad reach this Python through cross-device tools ([D49](#d49)).
  - **iPhone and iPad:** Pyodide (CPython compiled to WebAssembly) in a hidden web view, pinned and bundled with NumPy, pandas, SciPy and Matplotlib, so nothing that adds features is downloaded at run time. It runs as a tool in the in-app environment ([D50](#d50)). Web content is memory-limited and suspended in the background, so long runs go to the Mac. If S6 shows that Pyodide's cold start or memory fail on a mid-range iPhone, the fallback is native CPython in the style of Carnets [INFERENCE].
  - **Notebooks:** `.ipynb` files open in a native SwiftUI notebook view on every device. Cells run on the device's own Python or, over [D48](#d48)'s links, on the Mac's. Outputs (text, tables, images) render natively, and bots can read, write and run notebooks.
  - **Mac only:** packages that generate machine code at run time, such as numba and so vectorbt, which cannot run on iPhone.
- **Rationale:** The user's answer, for quant research, backtests and notebooks. The [Python research](../research/2026-10-22-python-and-native-generative-ui.md#6-python-in-our-apps-quant-research-and-notebooks) found that Pyodide 314.0.7 ships NumPy 2.4, pandas 3, SciPy 1.18 and Matplotlib 3.10, and that the scientific packages publish no iOS wheels for native CPython. User-viewable, editable code follows App Review's developer-tool precedent (2.5.2) [Claim: the research's reading].
- **Consequences:** new feature rows; Phase 0 spike S6 (Pyodide cold start, memory and background behaviour on a mid-range iPhone); Phase 2 and Phase 3 grow ([D66](#d66)); Python runs count as T2 commands under policy.
- **Licences:** Pyodide and the python-build-standalone CPython builds that `uv` installs are MPL-2.0 (Observed, their repositories), a per-file copyleft. They ship unmodified, as separate components, with their notices and a link to their source; a change to one of their files would be published under MPL-2.0. MPL-2.0 allows this inside a larger work under other terms (its §3.3). [D33](#d33)'s rule covers code copied into ours, which this is not [INFERENCE: the pre-launch legal review confirms] (settled by [D86](#d86): kept).

<a id="d61"></a>
### D61. Generated cards written as Swift files
- **Status:** Accepted (user decisions, 2026-10-22). Extends [D53](#d53). v1, Phase 2. Superseded by [D68](#d68) (2026-10-22): Swift files now run in Memoshi's Swift engine instead of compiling to JSON only.
- **Choice:**
  - A bot may write a generated card as a small Swift file in a SwiftUI-like subset. Memoshi compiles it with SwiftSyntax into D53's JSON before the card is stored and drawn. The file never runs as code; this follows Interswift's pipeline (parse, view tree, native components) ([research §4, §7.2](../research/2026-10-22-python-and-native-generative-ui.md#72-where-swift-files-fit-inference)).
  - The JSON stays the stored and validated form, so D53's block catalog, validation, actions, versions and data rules apply unchanged. An unsupported construct fails with an error the bot can fix.
  - The card tool compiles on the device that runs the bot [INFERENCE].
  - A generated card that proves useful can later become a built-in, compiled card in a release.
- **Rationale:** The user's answer ("new ones generated as Swift files"). Compiling to data keeps D53's App Review position: nothing downloaded runs as code (2.5.2) [INFERENCE].
- **Consequences:** [`../specs/cards.md`](../specs/cards.md) gains the Swift subset and its mapping to blocks; Phase 2 grows ([D66](#d66)).

<a id="d62"></a>
### D62. Native mini apps (v1.1)
- **Status:** Accepted (user decisions, 2026-10-22). Extends [D53](#d53) and [D29](#d29). v1.1, on every device. Superseded by [D68](#d68) (2026-10-22): native mini apps are written in Swift and ship in v1.
- **Choice:**
  - A mini app's logic is JavaScript in Code Mode's engine, whose signals drive D53's native blocks, like Armin Ronacher's Python `ui` layer ([research](../research/2026-10-22-python-and-native-generative-ui.md)). Its actions pass policy like any other call.
  - It ships on the Mac first. On iPhone and iPad it ships only after App Review is consulted, because guideline 4.7 covers "HTML5 and JavaScript mini apps" and 4.7.2 bars exposing native APIs without Apple's permission.
  - Web mini apps (D29) stay as they are in v1.
- **Rationale:** The user's answer: mini apps described by a script and drawn natively, everywhere.
- **Consequences:** v1.1 scope; an App Review risk for iPhone and iPad (R45).

<a id="d63"></a>
### D63. Emulated Linux as an optional extra (v1.1)
- **Status:** Accepted (user decisions, 2026-10-22). Extends [D50](#d50). v1.1, iPhone and iPad. Superseded by [D69](#d69) (2026-10-22): the emulated Linux computer uses iSH and ships in v1.
- **Choice:**
  - An emulated Linux with a package manager becomes an optional, extra computer on iPhone and iPad. D50's shell front end stays the default, and the Mac keeps its real shell.
  - The emulator must be permissively licensed ([D33](#d33)). iSH, which Open Minis uses, is GPL-3.0 (its `LICENSE.md`), so it is out. Candidates: Blink (ISC) and v86 (BSD-2), which runs in a web view where WebKit may JIT [INFERENCE] (settled by [D86](#d86): kept).
- **Rationale:** The user's answer, after Open Minis showed apk packages, Python, Git and SSH on an iPhone.
- **Risk:** every instruction is emulated, so it is slow and heavy, and App Review may object to downloaded packages (2.5.2).

<a id="d64"></a>
### D64. Code Mode engine fallback order
- **Status:** Accepted (user decisions, 2026-10-22). Amends [D50](#d50)'s "JavaScriptCore is its fallback". Amended by [D79](#d79) (2026-10-22): the last resort runs the same `quickjs.wasm` on JavaScriptCore's WebAssembly when that runs without JIT. **Superseded by [D89](#d89) (2026-10-23): wasm2c for shipping, WasmKit as reference and fallback, no JavaScriptCore.**
- **Choice:** Code Mode runs upstream's `quickjs.wasm` (QuickJS-NG) on WasmKit. If S1 shows it too slow on a mid-range iPhone, the same `quickjs.wasm` is translated to C at build time with `wasm2c` (WABT, Apache-2.0). JavaScriptCore is the last resort.
- **Rationale:** The user's answer. ~~`wasm2c` keeps upstream's exact engine bytes, its sandbox and its snapshots, so journals replay the same way.~~ *Correction (2026-10-23): Code Mode replays journals, not VM snapshots. Translating the pinned guest preserves its input identity, but backend equivalence still needs the differential replay checks in [D89](#d89).* JavaScriptCore's JavaScript engine is a different engine with no public memory limit ([follow-ups §6](../research/2026-10-22-viticci-followups.md#6-the-javascript-engine)).
- **Consequences:** Pi_Swift requirements E7 changes; S1 measures WasmKit first.

<a id="d65"></a>
### D65. Memoshi-Plan is a prototype
- **Status:** Accepted (user decisions, 2026-10-22). Amends [D36](#d36)'s "not continued" and makes [D44](#d44)'s Memoshi-Plan line precise. Amended by [D90](#d90) (2026-10-23): the move waits for Pi_Swift's slice-ready state, not compilation alone.
- **Choice:**
  - `~/Documents/Memoshi-Plan` continues as a separate prototype with its own agent. It stays on Node and Pi 1.3.0 until Pi_Swift's product slice compiles, then moves to Pi_Swift.
  - It does not bind Memoshi. This repo's plan is the product's source of truth, and Memoshi ports proven pieces from it under [D33](#d33) and D36.
  - Its agent rewords the three lines that contradict D44 and D46 (its `MASTER_PLAN.md` "Do not embed Pi in Swift", `docs/02-architecture.md`'s "Embed Pi in Swift: No", and the 1.3.0 pin in `sidecar/package.json`) to "Node Pi until Pi_Swift compiles". The user passes this on; Memoshi's agents do not edit that repository while its agent works there.
- **Rationale:** The user's answer. On 2026-10-22 its agent committed about every 10 minutes, building features such as group policy and remote machines.
- **Risk:** two code bases for one builder ([D45](#d45)) split effort, and the prototype's features may drift from Memoshi's scope.

<a id="d66"></a>
### D66. v1 calendar: the gate moves to about Fri 2028-02-25
- **Status:** Accepted (user decisions, 2026-10-22). Supersedes [D45](#d45)'s date. Change-control rule 3 roadmap review. Its calendar is superseded by [D70](#d70) (2026-10-22).
- **Choice:**
  - Phase 2 grows from 13 to 17 weeks (2027-04-19 → 2027-08-13) for Python on the Mac, the notebook view and Swift-file cards ([D60](#d60), [D61](#d61)).
  - Phase 3 grows from 18 to 20 weeks (2027-08-16 → 2028-01-14, with the year-end break 2027-12-20 → 2027-12-31) for Pyodide on iPhone and iPad and the notebook view there.
  - Phase 4 stays 6 weeks (2028-01-17 → 2028-02-25). Phases 0 and 1 are unchanged. The total is 66 plan weeks.
- **Rationale:** The user chose the later date over cutting scope or letting the new work slip. The extra weeks are estimates [INFERENCE]: about 2.5 for Python and notebooks on the Mac, 1.5 for Swift-file cards, and 2 for Pyodide on iPhone and iPad.
- **Consequences:** [`10-roadmap.md`](10-roadmap.md)'s calendar and phases, the feature catalog's phase table, the risk gates' plan weeks, and the dates in MASTER_PLAN, HANDOFF and README follow.

<a id="d67"></a>
### D67. Personal use first: no App Store in v1
- **Status:** Accepted (user decisions, 2026-10-22). Sets aside [D56](#d56)'s App Store distribution and App Review rules for v1, and [D47](#d47)'s "App Review applies to v1". Opens O13.
- **Choice:**
  - v1 is built for the user's own use, as "the best possible app" for them. The iPhone and iPad app installs on the user's devices through TestFlight internal testing or straight from Xcode. Internal TestFlight builds skip Beta App Review and each expires after 90 days, so CI uploads fresh ones; an Xcode development build lasts up to a year [Claim: 2026 guides quoting Apple].
  - App Review guidelines stop shaping v1's features. iOS's own limits still hold: no JIT, no child processes, background time limits and memory limits.
  - The Mac app stays Developer ID-signed and notarized (D32, D56); its certificates and profiles (D58, D59) are unchanged.
  - The friendly alpha becomes optional: friends can join later as internal TestFlight testers.
  - A public release, through the App Store or otherwise, is decided later (O13).
- **Rationale:** The user's direction: "app store stuff isn't important for us right now, only I can use it to make the best possible sota app".
- **Consequences:**
  - Phase 4 drops App Review and the store release. IOS-05 (App Review readiness) and DIST-08's App Store part move out of v1, to before a public release. R45 is deferred.
  - Pyodide may install extra packages at run time (D60), and the emulated Linux may download packages (D69).
  - Metrics that need other users (beta cohorts, opt-in rates) wait for a public release.

<a id="d68"></a>
### D68. One Swift engine for live cards and mini apps
- **Status:** Accepted (user decisions, 2026-10-22). Supersedes [D61](#d61)'s compile-to-JSON-only rule and [D62](#d62). Extends [D53](#d53). Amended by [D71](#d71) (jobs, widgets, permissions, tool access, sizes and bytecode), [D72](#d72) (language, styling, migrations and exposure tracking), and [D85](#d85) (Mac mini apps open as a sheet, with window and full-screen options). [D87](#d87) stages the core in Phase 2 on the Mac and Phase 3 on iPhone and iPad, with the remaining language and mini-app power features in Drop 1 (all 2026-10-22).
- **Choice:**
  - **The engine.** Bots write SwiftUI-style Swift. SwiftSyntax parses it; Memoshi's compiler checks it and turns it into bytecode; Memoshi's interpreter runs it, with no JIT; native SwiftUI components draw it. This is the approach of Ronith's prototype ([research §3](../research/2026-10-22-python-and-native-generative-ui.md#3-roniths-swift-interpreter)), built as our own code.
  - **Two forms, one engine:** live cards inline in a conversation, and mini apps full screen, with versions and an "Ask the bot to change it" box, like Viticci's task garden.
  - **The language:** a growing Swift subset with state (`@State`), `if`, `switch`, loops, `ForEach`, functions, structs, arrays, dictionaries, string formatting, timers and saved data per mini app [INFERENCE: the exact subset is set in Phase 2].
  - **The component kit:** a large set of native SwiftUI components, from D53's blocks to lists, forms, navigation, charts, maps, media, tabs, and the built-in Apple-data cards.
  - **Capabilities:** the code reaches data only through Memoshi's tools, which pass policy like any bot call. It cannot call Apple APIs directly, load native code, or reach files or the network except through tools, and it runs under time and memory limits.
  - **Errors:** unsupported code fails at compile time with a line, a column and a suggested fix, instead of crashing.
  - **Kept:** JSON cards (D53) for quick, static cards, and web mini apps (D29). The card catalog gains a `tabs` block for JSON cards and the kit.
- **Rationale:** The user's answer: Ronith's approach ("we want this as well"), and live cards and mini apps together from the start, without App Store limits ([D67](#d67)). The two forms share the parser, the interpreter and the kit.
- **Consequences:** about 10 weeks [INFERENCE], counted in [D70](#d70); [`../specs/cards.md`](../specs/cards.md) §11 becomes the engine's spec; new feature rows and risks.

<a id="d69"></a>
### D69. Emulated Linux on iPhone and iPad through iSH, in v1
- **Status:** Accepted (user decisions, 2026-10-22). Supersedes [D63](#d63). Amends [D33](#d33). v1, Phase 3.
- **Choice:**
  - The emulated Linux computer on iPhone and iPad uses iSH, through Open Minis's ARM64 version (`OpenMinis/ish-arm64`), with an Alpine Linux user space: a package manager, a real shell, Python, Git, SSH and ffmpeg. It is an optional computer next to the in-app environment (D50).
  - Memoshi's app commands (D50) become real programs inside it, as Open Minis's "native offloads" are, so a bot's scripts work the same on the Mac shell, the mini shell and iPhone Linux.
  - **Licence:** iSH is GPL-3.0, so it, and any code taken from Open Minis (GPL-3.0), lives in its own GPL-3.0 module that only the iPhone and iPad app links. The rest of the repository stays Apache-2.0, and the Mac app links no GPL code. The iPhone and iPad app is then a GPL-3.0 combined work: if it is ever distributed, its source must be offered and no closed-source code can be in it. iSH's `LICENSE.IOS` promises not to pursue the GPL and App Store terms conflict.
- **Rationale:** The user's answer ("make whatever needed so we can use it in the best way possible"). iSH is proven on iPhone: Open Minis ships it on the App Store with this licence model (Observed, its README).
- **Risks:** emulation is slow and uses memory and battery; numeric Python stays on Pyodide or the Mac (D60).
- **Consequences:** about 3 weeks in Phase 3 [INFERENCE], counted in [D70](#d70). Pi_Swift's PiEnv reaches the guest in one of two ways, and the Phase 3 iSH probe picks one [INFERENCE] (settled by [D86](#d86), as [D81](#d81) decided, in favour of the host-side adapter by default, which the probe confirms): a host-side adapter that runs commands through the emulator's in-process shell, or a pi-env daemon built for Linux ARM64 inside the guest, which may start slowly under emulation.

<a id="d70"></a>
### D70. v1 calendar: the gate moves to about Fri 2028-04-28
- **Status:** Accepted (user decisions, 2026-10-22). Supersedes [D66](#d66)'s calendar. Its calendar is superseded by [D87](#d87) (2026-10-22): v1.0 on Fri 2028-11-24, then two feature drops.
- **Choice:**
  - Phases 0 and 1 are unchanged (W1–W23).
  - Phase 2 is 23 weeks, W24–W46 (2027-04-19 → 2027-09-24): the Swift engine on the Mac joins Python and notebooks.
  - Phase 3 is 24 weeks, W47–W70 (2027-09-27 → 2028-03-24, with the year-end break 2027-12-20 → 2027-12-31 outside plan weeks): the engine on iPhone and iPad, Pyodide, and iSH.
  - Phase 4 is 5 weeks, W71–W75 (2028-03-27 → **Fri 2028-04-28**), without App Review.
  - The total is 75 plan weeks; Phase 5 (v1.1) starts Mon 2028-05-01.
- **Rationale:** The user chose to put the Swift engine and iSH in v1. The estimates [INFERENCE]: the Swift engine adds about 8 weeks (6 in Phase 2, 2 in Phase 3), iSH about 3, and dropping App Store work saves about 2 (1 in Phase 3, 1 in Phase 4).
- **Consequences:** the roadmap, the feature catalog, the risk gates (plan weeks 5, 23, 46, 70, 75), and the dates in MASTER_PLAN, HANDOFF and README follow.

<a id="d71"></a>
### D71. Swift engine rules: background jobs, widgets, permissions, tool access, sizes and bytecode
- **Status:** Accepted (user decisions, 2026-10-22, the first round of the review of inferred choices). Amends [D68](#d68). Replaces the inferred rules in [`../specs/cards.md`](../specs/cards.md) §11–§12 and [`../specs/policy.md`](../specs/policy.md) §10.7. Its "within its approved list" rule gains per-value exposure tracking under [D72](#d72). Amended by [D87](#d87) (2026-10-22): jobs, widgets and the signed bytecode cache ship in Drop 1.
- **Choice:**
  - **Background jobs.** A mini app may declare refresh jobs, on a schedule or when data it uses changes. The bot's runner runs them without a screen, in a sandboxed engine helper: on the Mac a helper process with no secrets, never memoshid; on iPhone and iPad inside the app, when it is the runner and iOS grants background time. Jobs follow the unattended rules and budgets, and they save data and send notifications through tools.
  - **Widgets.** A mini app may offer home-screen widgets on Mac, iPhone and iPad (WidgetKit), drawn from its saved data. Tapping a widget opens the mini app.
  - **A permission list per version.** A tap counts as the user, attended, but it is not an approval. Timers, on-open calls and background jobs are the program's own, unattended. The compiler lists every tool and web host a version can call. The user approves the list when a live card or mini app first appears, and again when a new version adds to it; risky abilities, such as shell commands or changing its own code, are named plainly. The runner refuses any call outside the approved list.
  - **Tool access.** Within its approved list, a program may call every tool the bot can call, decided by the bot's mode, grants and policy as for the bot. This removes the fixed list of tools programs may not call. ~~Programs never see secrets, because the bot never does.~~ *Correction (2026-10-22): the bot can read a secret through `secret.reveal` (T5, typed confirmation, attended only), so a program can too, but only from a tap with typed confirmation, never from timers, on-open calls or jobs. Under [D72](#d72)'s per-value tracking a revealed secret carries a `secret` label: a program may show it, but never pass it to a tool call or save it.*
  - **Sizes.** No fixed limits on source or saved data; only the interpreter's work and memory limits apply. A mini app may span several files, and bots edit one file at a time.
  - **Bytecode.** The runner compiles and signs a program's bytecode, which syncs with the source as a cache. A device runs synced bytecode only if one of the user's paired devices signed it, its engine version matches, and the device's bytecode verifier accepts it; otherwise it compiles the source itself. Widgets use the cache.
- **Rationale:** The user's answers. The user chose wider tool access, no size limits and synced bytecode over the recommended options (a short block list, multi-file sizes with caps, and compiling on every device).
- **Risks:** a buggy or tricked program can do anything its approved list allows, so the list is now the main guard. Unbounded saved data makes sync and storage grow. Synced bytecode adds a trust path between devices, bounded by signatures, the verifier and the runner's own checks.
- **Consequences:** about 5.5 weeks [INFERENCE: 3.5 for background jobs and widgets, 0.5 for permission lists, 0.5 for several files, 1 for signing and the verifier], tallied for one calendar change at the end of the review. The specs, architecture, security, platform and experience docs, the feature catalog and the risks follow.

<a id="d72"></a>
### D72. Swift engine: language, look, data migrations and untrusted content
- **Status:** Accepted (user decisions, 2026-10-22, the second round of the review of inferred choices). Amends [D68](#d68) and [D71](#d71). Amended by [D87](#d87) (2026-10-22): the core language, migrations and exposure tracking ship in v1.0; the remaining language and rich styling ship in Drop 1.
- **Choice:**
  - **Nearly all of Swift.** Besides D68's value types, closures and control flow, programs may use classes (`@Observable` and `ObservableObject` included), protocols with extensions, their own generics, `async let`, task groups and actors. Still excluded: unsafe pointers, `@_silgen_name`, dynamic loading, Objective-C interop, `#if`, and macros other than `#Preview` and `@Observable`. The language widens, not the reach: data still comes only through tools, with no Apple or system APIs beyond the kit (D68).
  - **Rich styling in mini apps.** Besides padding, frames, colors, fonts, shapes, gradients and animations: shadows, materials, overlays, offsets, SF Symbol rendering modes, Canvas drawing and images from the bot's files. Contrast is checked at compile time, and Dynamic Type and Reduce Motion are honoured automatically. Live cards stay semantic-only.
  - **Saved data migrations.** Publishing compares a version's saved types with the stored data. New fields get defaults; renamed or removed fields need a migration the bot writes, or the publish fails with a fix. Snapshots stay as a safety net.
  - **Per-value exposure tracking**, in the style of CaMeL: every value records where it came from (the user, private data, or untrusted content), and policy's exposure effects apply to a call through the values that reach its arguments. This replaces per-program flags.
  - **Versions written after untrusted content.** A version written by a task exposed to untrusted content needs the user's approval before its first run, showing what changed and its permission list. Its T4 actions keep draft cards in every mode, Bypass included, as [D57](#d57) does for untrusted runs.
  - **The review's process.** High-impact inferred choices are decided in rounds. Medium and low ones are reviewed as area tables with a recommended pick per row, which the user approves or pulls out to discuss.
- **Rationale:** The user's answers. The user chose nearly all of Swift over the recommended subset (value types plus `@Observable` classes and protocols).
- **Risks:** a near-complete Swift front end is v1's largest single build [INFERENCE]. Full static type checking of generics and protocols is hard, so the engine may check names and shapes before a run and the rest during it, with every error still carrying a line and a fix. Per-value tracking costs interpreter speed and memory [INFERENCE].
- **Consequences:** about 9.5 weeks [INFERENCE: 6 or more for the language, 1.5 for styling, 0.5 for migrations, 1.5 for per-value tracking]; the review's tally is about 15 weeks so far, for one calendar change at its end.

<a id="d73"></a>
### D73. Multi-device correctness: merged settings, expiring offline answers, a stable runner, merged app data and safe failover
- **Status:** Accepted (user decisions, 2026-10-22, the third round of the review of inferred choices). Amends [D49](#d49), superseding its "The runner follows the user" bullet, and [D71](#d71).
- **Choice:**
  - **Settings merge.** Bot settings, routines, skills and other configuration records can be edited on any device, offline included, and merge field by field (hybrid logical clocks, with add-wins sets for lists). Restrictive changes win: a revoked grant, a lowered permission mode, a paused routine or a stop beats a concurrent loosening, until the user loosens again on a device that has seen the restriction. Decisions (card answers, approvals and drafts) still go to the runner, and conversation histories stay single-writer (D49).
  - **Offline answers expire with their card.** An answer made while the runner is unreachable waits only until its card expires. It applies if the card is still pending when the runner is reached; otherwise it is dropped and the user is told.
  - **A stable runner.** An awake, reachable runner keeps the bot. Another device forwards the user's messages to it and streams the answer. The lease moves only when the runner cannot be reached, by D49's expiry and hand-over; when the lease is free, an awake Mac is preferred. Runs no longer stall when iOS suspends the app, and switching devices no longer forces a hand-over.
  - **Mini app data merges.** Saved data is a merge-friendly type (a CRDT): edits apply at once on any device, offline included, and merge per item and per field when devices meet.
  - **Safe failover.** A runner whose lease the authority has not confirmed (a direct hand-over while iCloud and the relay are unreachable) is provisional: it may read, think and draft, but makes no external effect until the authority confirms. Before any external effect runs, its intent is copied to another device or the relay, so a runner that takes over after a failure runs the step's outcome check ([D51](#d51)) instead of repeating the effect.
- **Rationale:** The user's answers, all as recommended. A runner that stays put avoids stalled runs on iPhone and hand-over churn; restrictive-wins merging keeps offline edits safe.
- **Consequences:** about 4.25 weeks [INFERENCE: 2 for merged settings, 0.25 for expiring answers, 0.5 for forwarding, 0.5 for mini app data, 1 for provisional runners and write-ahead intents]; the review's tally is about 19.25 weeks. Pi_Swift needs no new engine feature for this [INFERENCE]: the host gates effects and copies intents in `beforeTool` (E6, E20).

<a id="d74"></a>
### D74. Leases per conversation, rebalancing, handoffs, versions, Trash and local-model fallback
- **Status:** Accepted (user decisions, 2026-10-22, the fourth round of the review of inferred choices). Amends [D49](#d49) (its "One writer at a time" bullet now applies per conversation) and [D73](#d73).
- **Choice:**
  - **A lease per conversation.** Each conversation (a Chat, a Session, a lane) has its own durable store and its own epoch-fenced lease, so one bot may run conversations on two devices at once. Bot-wide records merge: memory entry by entry (D49), settings field by field (D73). Bot-wide limits, such as budgets and run caps, are enforced with merged counters that can briefly overshoot [INFERENCE].
  - **Rebalancing.** When an awake Mac is reachable and a conversation is idle, its lease returns to the Mac, so routines and Mac tools run there again; other devices forward (D73).
  - **Handoff work runs under the receiving bot's own lease and store,** with its own memory, tools and grants. Its result joins the sender's conversation as an entry.
  - **Older app versions.** Store migrations expand, then contract, so the previous app version can still read and run. Anything older is a read-only replica with an **Update Memoshi** prompt and never takes a lease.
  - **Trash.** A deleted conversation or bot stays in Trash for 30 days on every device and can be restored from any of them. **Empty Trash** purges it everywhere.
  - **Local-model fallback.** A bot set to a local model on the Mac chooses what happens while the Mac is unreachable: Apple's on-device model (the default; private, offline), a cloud model the user picks, or waiting for the Mac.
- **Rationale:** The user's answers. The user chose a lease per conversation over the recommended one store per bot; it matches upstream Pi's one file per session.
- **Risks:** per-conversation runners add more leases and hand-overs, and bot-wide limits can overshoot briefly.
- **Consequences:** about 3.25 weeks [INFERENCE: 1 for per-conversation leases and merged counters, 0.25 for rebalancing, 0.5 for handoff leases, 0.5 for version compatibility, 0.5 for Trash, 0.5 for the model fallback]; the review's tally is about 22.5 weeks. Pi_Swift's E16 and E17 become a store, lease, snapshot and change feed per conversation.

<a id="d75"></a>
### D75. Security across devices: synced keys, biometrics, a global stop, MLS and synced browser sessions
- **Status:** Accepted (user decisions, 2026-10-22, the fifth round of the review of inferred choices). Amends [D48](#d48) (encryption) and [D49](#d49). Extended by [D79](#d79) (2026-10-22): a recovery key in iCloud Keychain lets a new device join the MLS group when no old device is left. Amended by [D87](#d87) (2026-10-22): browser-cookie sync ships in Drop 2.
- **Choice:**
  - **Keys sync through iCloud Keychain.** Model keys, OAuth tokens and other secrets are synchronizable Keychain items, which Apple syncs end to end encrypted. Any secret can be marked "this device only".
  - **One Keychain class.** Every secret stays readable after first unlock, so unattended runs can use any key while the Mac is locked (synced items use the synchronizable form of that class).
  - **Biometrics for T4 and T5.** Sends, money and credential approvals need Face ID, Touch ID or the device passcode on every device. Revoking a device erases its replicas by withdrawing its data keys.
  - **"Stop all bots" stays global.** Pressed on any device, it stops every bot on every device, and it wins over concurrent offline edits ([D73](#d73)).
  - **MLS for device encryption.** The user's devices form one MLS group (RFC 9420): everything that crosses devices, the iCloud sync log and store-and-forward messages included, is encrypted to the group, with forward secrecy and a new epoch whenever a device joins or is revoked. Pairing adds the new device to the group, authenticated by the QR code. [INFERENCE: through `awslabs/mls-rs` (Apache-2.0 OR MIT) and its UniFFI Swift bindings with a CryptoKit backend; UniFFI's runtime is MPL-2.0, shipped unmodified like [D60](#d60)'s components; mls-rs has no third-party audit yet (Claim, its README). The lease authority's compare-and-swap can order MLS commits.]
  - **Browser sessions sync.** Each bot's browser cookies sync end to end encrypted between the user's devices (under the MLS group), so a bot signed in on one device is signed in on all.
- **Rationale:** The user's answers. The user kept one Keychain class and chose full MLS and synced cookies over the recommended split classes, a rotating group key and routing to the signed-in device.
- **Risks:** every key is readable on a powered-on Mac once it has been unlocked; MLS is the most complex option, and its library is unaudited; synced cookies put live sessions on every device, which biometrics and revoke-erase bound.
- **Consequences:** about 4 weeks [INFERENCE: 0.5 for synced keys, 0.5 for biometrics, 2 for MLS, 1 for cookie sync]; the review's tally is about 26.5 weeks.

<a id="d76"></a>
### D76. Budget slices, bot isolation on iPhone and iPad, and Python's runtimes, network and rules
- **Status:** Accepted (user decisions, 2026-10-22, the sixth round of the review of inferred choices; the user left the budget design to the recommendation). Amends [D60](#d60) and [D74](#d74).
- **Choice:**
  - **Budget slices.** Each active runner reserves a slice of the bot's remaining budget through the lease authority, spends locally within it, renews it as needed, and returns the unspent part when its conversation goes idle or its lease ends. A provisional runner ([D73](#d73)) spends only the slice it holds. A bot never overruns its cap by more than one in-flight model call per runner. This is the quota-lease pattern of large rate limiters [INFERENCE].
  - **Isolation on iPhone and iPad.** Each bot gets handles to its own folder and its linked folders, and every file operation resolves relative to those handles without following symlinks, so no path check can be raced. Secret reads go through an in-process broker that logs every release, as on the Mac.
  - **One Pyodide per bot,** started on first use and closed when idle or under memory pressure, so bots' Python state never mixes.
  - **Python's network on iPhone and iPad** goes through the in-app gateway under the bot's allowlists, the same as Python on the Mac.
  - **"Always allow" for Python** covers one script or notebook, identified by its content; changed code asks again.
- **Rationale:** The user's answers, all as recommended.
- **Consequences:** about 2.5 weeks [INFERENCE: 0.5 for budget slices, 1 for folder handles and the broker, 0.25 for Pyodide per bot, 0.5 for Python's network, 0.25 for per-script rules]; the review's tally is about 29 weeks. BU-03, BU-07 and the definition of done keep their "no overrun beyond one in-flight call" promise, per runner.

<a id="d77"></a>
### D77. The Mac sandbox, its fallback order, Mac sleep, checkpoints and commit hooks
- **Status:** Accepted (user decisions, 2026-10-22, the seventh round of the review of inferred choices; the user left commit hooks to the recommendation). Amends [D16](#d16).
- **Choice:**
  - **The Mac sandbox.** The bot's pi-env daemon stays inside the Seatbelt sandbox that spike S4 proves, so its file tools and its commands are both confined. A guard in the daemon also resolves paths without following symlinks, as defence in depth. App commands reach memoshid over the daemon's existing channel, so the sandbox needs no extra opening.
  - **If S4 fails, a fixed order.** First S4's other design, chosen by a fixed scorecard: any escape blocks, then fidelity to `srt`, overhead and maintenance, and a tie goes to the `srt` port. Then a separate unprivileged macOS user account for bots, plus Seatbelt, which keeps Xcode and macOS tools. A Linux VM only for work that runs on Linux.
  - **Mac sleep.** While runs are active on mains power, Memoshi prevents idle sleep by default; the display may still sleep. On battery it does not. One setting changes both.
  - **Checkpoints.** Each coding turn is a checkpoint. The user can restore its files, its conversation or both, or fork a new session from it.
  - **Commit hooks stay as planned.** A repository's pre-commit and commit-msg hooks run inside the session's sandbox; Memoshi then commits outside it with `--no-verify`, so signing works and repository code never runs unconfined.
- **Rationale:** The user's answers, all as recommended.
- **Consequences:** about 1 week [INFERENCE: 0.25 for the guard and the channel, 0.25 for the sleep assertion, 0.5 for checkpoints]; the review's tally is about 30 weeks.

<a id="d78"></a>
### D78. Chat continuity, memory checks, mode changes, where programs run, and the typed API
- **Status:** Accepted (user decisions, 2026-10-22, the eighth round of the review of inferred choices; the user left where programs run to the recommendation). Amends [D46](#d46)'s protocol note, [D68](#d68) and [D71](#d71).
- **Choice:**
  - **No automatic Chat reset.** Compaction and memory keep a bot's Chat going. After a long idle, at least 6 hours, a **Start fresh?** chip offers a reset; only the user resets.
  - **Values from memory.** A T4 or T5 card whose arguments come only from memory shows "From memory, not re-checked" and a **Check now** button, which runs a fresh read of the source (for example, looks up the contact) before the user approves.
  - **Mode changes with pending cards.** When a bot moves to Auto or Bypass with cards pending, Memoshi asks once, for example "Apply Auto to 3 pending cards?". Yes decides them under the new mode; No leaves them pending.
  - **Where programs run.** On the Mac every live card and mini app runs in a sandboxed engine helper, one per bot, with no secrets, no files and no network: its only way out is the tool bridge. The app draws the component tree the helper sends and returns the user's input. A helper crash stops only that bot's programs. On iPhone and iPad, where iOS allows apps no such helpers, programs run in the app, each in its own interpreter instance.
  - **The typed API.** Swift types are the source of truth for Memoshi's protocol; the JSON Schema is generated from them for tests and docs. The iPhone and iPad app calls its in-process engine through a typed Swift API, with no JSON inside the process, and the Mac uses the same API over its socket ([D13](#d13)).
- **Rationale:** The user's answers. For where programs run, the recommendation changed to the helper: under [D72](#d72)'s near-complete Swift the interpreter is large enough that a bug in it could crash the app, and on the Mac the app holds Keychain access ([D58](#d58)), so a helper with nothing to steal is the safer home. The interpreter already produces components as data, which makes the split cheap.
- **Consequences:** about 1.5 weeks [INFERENCE: 1 for programs in the helper, 0.25 for Check now, 0.25 for the rest]; the review's tally is about 31.5 weeks.

<a id="d79"></a>
### D79. Live Apple-data cards, recovery rules, fallbacks, widget data, backups, Code Mode, the model catalog and gateway sign-ins
- **Status:** Accepted (user decisions, 2026-10-22, the ninth round of the review of inferred choices; the user left backups to the recommendation). Amends [D53](#d53), [D60](#d60), [D64](#d64) and [D75](#d75), and adopts two proposals of [`NEXT_VERSION.md`](NEXT_VERSION.md). [D87](#d87) places live Apple-data cards in Drop 2 and widgets in Drop 1. **Its Code Mode clause is superseded by [D89](#d89) (2026-10-23); the other clauses stand.**
- **Choice:**
  - **Live Apple-data cards.** Native cards for Reminders, Calendar and the other Apple data are live views of the item, after NEXT_VERSION's resource views: they show its current state, re-read it before any write, show a conflict when it changed elsewhere, and mark a write that timed out as "outcome unknown".
  - **Recovery rules** (NEXT_VERSION): while a step is recovered, its whole thread holds; grants are re-checked when a call is dispatched, not only when it was approved; a redactor that fails returns safe output, never the raw text; nothing retries on its own after the link to a bot's computer was lost.
  - **If Pyodide fails spike S6:** first a trimmed, lazily loaded Pyodide; then phones use the Mac's Python; native CPython for iOS only if both fail.
  - **Data for widgets and Shortcuts on iPhone and iPad.** Bot stores stay private in the app's container. Widgets read a small exported snapshot, saved data and signed bytecode, from the App Group, and Shortcuts actions run in the app's own process. This answers Pi_Swift's E4 question.
  - **Backups and recovery.** Bot stores are excluded from device backups, so a restored device never brings back stale leases; it re-syncs from the user's other devices or from iCloud. A recovery key, kept in iCloud Keychain, lets a new device join the devices' MLS group ([D75](#d75)) and read the iCloud sync log when no old device is left.
  - **Code Mode's last resort** runs the same `quickjs.wasm` on JavaScriptCore's WebAssembly, if spike S1 shows that it runs without JIT on iPhone; otherwise JavaScriptCore's JavaScript engine.
  - **The model catalog.** Each provider's own model list says which models are available; a catalog that CI builds daily from upstream Pi, and signs, supplies prices and limits (Pi_Swift E31).
  - **Gateway sign-ins.** OpenRouter's and Radius's sign-ins stay in product builds, outside E11's subscription switch: they create usage-billed keys and reuse no subscription.
- **Rationale:** The user's answers. For backups, the recommendation adds the recovery key: with MLS, losing every device at once would otherwise leave the iCloud copy unreadable.
- **Consequences:** about 2.75 weeks [INFERENCE: 1 for live cards, 0.5 for the recovery rules, 0.25 for widget data, 0.5 for the recovery key, 0.5 for the catalog]; the review's tally is about 34.25 weeks. Pi_Swift's E4, E7, E11, E16 and E31 questions are answered.

<a id="d80"></a>
### D80. Reference devices, an open model on the phone, a domain for public files, forks and the only-device backup
- **Status:** Accepted (user decisions, 2026-10-22, the tenth round of the review of inferred choices). Supersedes [D74](#d74)'s default local-model fallback; amends [D74](#d74)'s forks and [D79](#d79)'s backup rule. [D87](#d87) places MOD-09 in Drop 2. [D88](#d88) (2026-10-23) settles the earlier no-model case: queue until connectivity returns.
- **Choice:**
  - **Reference devices** are the user's own: an **iPhone 14 Pro** (A16, 6 GB of RAM [Claim], 150 GB free) and an **iPad Pro 12.9-inch (5th generation, M1)** (8 GB of RAM unless it is a 1 TB or 2 TB model [Claim], 70 GB free). Every gate that said "a mid-range iPhone" (S1, S6, the Swift engine and iSH probes) measures on these. Both run iOS and iPadOS 27 (Observed, Apple Support).
  - **Memory on the iPhone.** The app requests the increased-memory-limit entitlement [INFERENCE: check its effect on a 6 GB device], and the heavy runtimes (Pyodide, the iSH guest and the on-device model) take turns there instead of loading together [INFERENCE].
  - **A small open model on the phone** is the default while the Mac is away for bots on a local model. It runs on MLX and downloads on first use, sized per device [INFERENCE]: about 1.7B parameters on the iPhone 14 Pro, about 4B on the iPad (for example Qwen3, Apache-2.0). Apple's on-device model stays an option where it exists; the iPhone 14 Pro has none, because Apple Intelligence needs an iPhone 15 Pro or later [Claim: MacRumors]. A cloud model or waiting for the Mac stay the other choices.
  - **A domain for public files.** A domain the user owns, served by GitHub Pages or Cloudflare Pages, hosts the MCP client document, the universal-link file for sign-in redirects, the Mac update feed, the signed model catalog ([D79](#d79)) and the website. The user picks the domain before Pi_Swift needs it for E29 (Fri 2026-11-13).
  - **Forks get their own store and lease.** A forked Session ([D77](#d77)) is a new conversation that starts from its parent's history at the fork point, so "a lease per conversation" ([D74](#d74)) has no exception.
  - **The only-device backup.** When a device is the user's only device and both iCloud and the relay are off, its stores are included in device backups: there is no other copy and no lease that could go stale. Otherwise D79's exclusion holds.
- **Rationale:** The user's answers; the forks and the backup exception close gaps the doc updates found.
- **Consequences:** about 1.5 weeks [INFERENCE] for the on-device model; the review's tally is about 35.75 weeks.

<a id="d81"></a>
### D81. Review table 1: Swift engine, card and policy details
- **Status:** Accepted (user decisions, 2026-10-22, row by row; 16 rows left to the recommendation). Amends [D43](#d43)'s sidebar parity, [D68](#d68), [D69](#d69) and the specs `cards.md` and `policy.md`. [D92](#d92) (2026-10-23) removes blanket sidebar parity; the Apps section and its launch paths remain, no longer described as the sole parity exception.
- **Choice:** the 62 outcomes of table 1 in [`inferred-choices-review.md`](inferred-choices-review.md#table-1): 20 inferred choices kept as specified and 42 changed. The ones that change what the user sees or what is allowed:
  - **A sidebar "Apps" section,** plus Spotlight, Siri and Shortcuts launch for mini apps: a deliberate exception to D43's exact Kuvo sidebar parity.
  - **Telegram (v1.1):** messages from the owner count as the user only for reads and small writes (T0–T1); T2 and up are confirmed in the app.
  - **Mini apps:** a requested change switches in automatically; at its next turn the bot hears a short digest of what the user did in its live cards and mini apps (calls the user started, plus a program's own calls that failed); `bot.ask` shows an inline confirm sheet with the exact text; a failing handler is switched off first, the bot gets one automatic fix attempt per version, and three failures in a minute stop the app.
  - **The kit adapts by device:** one language everywhere, richer on the Mac, lighter on iPhone, and parts a program marks Mac-only show a lighter fallback on iPhone. Charts take about 100,000 points, documents get QuickLook previews, and card text may use bold, italic, code and https links that open in the in-app browser.
  - **iSH:** if its traffic cannot be routed through the gateway, it ships with guest networking off; SSH uses a sign-only agent backed by the broker; the engine reaches iSH through a host-side adapter by default.
  - **Safety details:** writes go through a temporary file and a rename; audit chains are copied read-only between devices; WebKit's local proxy port takes a random credential per launch; bots target the runner's newest version, with an **Update Memoshi** fallback on older devices.
- **Rationale:** The user's answers, row by row.
- **Consequences:** about 2.5 weeks [INFERENCE: the smoke-tested previews, audit copies, grouped shell cards, the Apps section and Spotlight launch, the bot digest and the adaptive kit]; the review's tally is about 38.25 weeks. The specs and plan docs follow the record's rows.
- **Amended 2026-11-08 (gateway authentication):** A request with no proxy credential gets `407` with `Proxy-Authenticate: Basic realm="memoshi"` and `Connection: close`, at most once per connection.
  - WebKit sends the store's configured credential only after this challenge. Before the change, every WebKit request to the bot-browser gateway was refused `unattributed`, so no granted site could load through it.
  - Wrong or stale credentials are still refused `unattributed`, and grant, host and address checks run after authentication.
  - Challenges are counted separately from decisions and audit ([evidence](../../../evidence/2026-11-08-memoshi-engineering/GatewayAuth/)).

<a id="d82"></a>
### D82. Review table 2: object model, protocol and events
- **Status:** Accepted (user decisions, 2026-10-22; keeps approved as a list, changes row by row). Amends [D49](#d49), [D73](#d73), [D74](#d74) and the specs `object-model.md`, `protocol.md`, `events.md` and `bot-definition.md`. Amended by [D88](#d88) (2026-10-23): side-thread answers require an available allowed model; no-model messages stay queued and do not generate a side-thread summary. [D95](#d95) (2026-10-25) supersedes only the Network.framework transport selection and backpressure-only SwiftNIO fallback restriction.
- **Choice:** the 49 outcomes of table 2 in [`inferred-choices-review.md`](inferred-choices-review.md#table-2): 18 kept as specified, 30 changed, and one matched D81. The ones that change behaviour:
  - **Devices:** pairing uses a Noise handshake (IKpsk2) keyed by the QR code, which expires after 5 minutes or when its screen closes; links race in order (Happy Eyeballs); live updates stream only to devices showing the conversation, about 10 a second; when several devices qualify, the awake one with the data and grant runs a tool, then the user's pin, then mains power.
  - **Failures and offline work:** stranded commits rejoin like a side thread; an unreachable device returns `device_unreachable`, never a denial; side threads are one per conversation, replicated read-only after they join, and their summary appends an exact list of effects; every device signs its audit chain head, and verification checks every chain.
  - **Bots:** a step that was interrupted tells the model so; run and side-thread summaries carry their exposure flags; a routine's daily cap follows its schedule; the relay wakes iPhones and iPads with a content-free push at fire times; an imported bot's sheet offers the file's mode, and an app-built checklist lists missing setup.
  - **Mini apps and notebooks:** icons are a symbol on a colored tile; recent apps follow the pinned ones; snapshots are kept for 30 days and always the last 3; a live card with a secret in its source fails to publish with a compile error; notebooks run on the Mac when they need Mac-only packages, sync their folder to the device that runs them, and mark outputs stale after a restart.
  - **Engineering:** memoshid's local server uses Network.framework (**transport selection superseded by [D95](#d95)**); crash recovery reads Pi_Swift's change feed from a cursor committed with the app's records; bot.md files allow 100,000 YAML nodes.
- **Rationale:** The user's answers.
- **Consequences:** about 3.5 weeks [INFERENCE: 18 days summed from the rows' estimates]; the review's tally is about 41.75 weeks.

<a id="d83"></a>
### D83. Review table 3: architecture, computers and browsers
- **Status:** Accepted (user decisions, 2026-10-22; keeps approved as a list, changes row by row; one row left to the recommendation). Amends [D49](#d49), [D73](#d73), [D74](#d74), [D76](#d76) and [D78](#d78), and `04-architecture.md` and `06-computers-and-browsers.md`.
- **Choice:** the 107 outcomes of table 3 in [`inferred-choices-review.md`](inferred-choices-review.md#table-3): 67 kept as specified, 36 changed and 4 matched earlier outcomes. The ones that change behaviour:
  - **Runners and leases:** routines and watches get their own lanes and leases (wakes stay in their conversation); each bot has a home Mac, which serves Mac-only tools and receives idle leases, and an always-on Mac (v1.1) becomes every bot's home by default; while a step is recovered, its whole conversation holds ([D79](#d79)).
  - **Browsers:** the user can watch and take over a bot's browser from any device, by streaming its screen and forwarding input; on iPhone a bot keeps at most 2 tabs, and 4 in total.
  - **Code Mode and subagents:** scripts may call models within the budget slices and a per-script spend cap; subagents stay one level deep, with up to 8 at once and the rest queued.
  - **Faster targets:** a cold launch under 2.0 s p95, an approval card under 100 ms p95 on the runner, the daemon ready in 500 ms, a page of history in 50 ms; the Swift engine probe aims at 120 fps on the ProMotion reference devices (60 as the floor) and at 90% of programs compiling within one fix round.
  - **Python:** on the Mac one pinned, hash-checked CPython is shared read-only by all bots, which keep their own packages; an open notebook keeps its Python running.
  - **iSH:** Alpine's base image ships in the app and each bot's copy updates with `apk` under policy; if iSH fails its probe, the Mac's real shell comes first, then Blink, then v86.
  - **Engineering:** CloudKit fetches at launch, on wake and on relay nudges, with a slow backstop timer; macOS sleep and wake notifications; full-text rebuilds in batches on the writer; at most 16 open conversations on iPhone and iPad to start; steer origins recorded in Memoshi's own outbox; a Swift-native schema validator; deterministic simulation of clocks and networks in CI.
  - **v1.1:** VM guests run upstream's pi-env daemon; shared VMs give each bot its own Linux user; images ship with their full source packages; quitting saves VMs silently unless a run is active; a VNC server over vsock is the VM display's fallback.
- **Rationale:** The user's answers.
- **Consequences:** about 2.5 weeks [INFERENCE: 12 days summed from the rows' estimates]; the review's tally is about 44.25 weeks.

<a id="d84"></a>
### D84. Review table 4: the platform, bots and the Assistant
- **Status:** Accepted (user decisions, 2026-10-22; keeps approved as a list, changes row by row; one row left to the recommendation). Amends [D23](#d23), [D25](#d25), [D31](#d31), [D76](#d76) and [D80](#d80), and `09-platform-macos.md` and `05-bots-and-assistant.md`.
- **Choice:** the 95 outcomes of table 4 in [`inferred-choices-review.md`](inferred-choices-review.md#table-4): 59 kept as specified and 36 changed. The ones that change behaviour:
  - **Budgets and limits:** an account-wide monthly cap, set at onboarding, over the per-bot defaults; cached tokens don't count toward a run's token cap; a routine's default budget is capped at the bot's monthly limit; side threads spend from a reserved or standby slice; cost previews switch to the user's own medians once there is history.
  - **Proactivity:** connector events batch over 60 s, widening to 15 minutes under bursts, at most 12 runs an hour; feed watches fire on the first new item; a past-due wake fires once however late, telling the bot how late; a bot may have 50 watches; a run that forgets to report posts its final answer as a quiet update; background runs wait while the device is hot or in Low Power Mode.
  - **Memory and skills:** facts and preferences fade with a 180-day half-life, procedures 90, others 30; pins are capped by space, not count; possible conflicts are judged by the on-device model; consolidation runs on the Chat's runner under its lease epoch; a bot's own skills beat global and project skills; unsolicited skill proposals come at most weekly, and a declined proposal waits 30 days, then 90, then until asked.
  - **Bots and Handoffs:** handles are unique ignoring case, with reserved names such as @assistant; a failing deterministic check blocks a Handoff's acceptance.
  - **Platform:** a detached live view uses the standard window toolbar, with the live view below it; Lockdown Mode is detected and sends Python to the Mac; iOS gets the increased-memory-limit and extended-virtual-addressing entitlements and browses inside the turn's background task; every build on the user's devices uses iCloud's Production environment; iCloud Drive grants are tested separately in S5; Enhanced Security hardening from Phase 1 for memoshid and from its first build for the engine helper; a maintenance hold covers leases during Sparkle restarts; uninstalling leaves the device group; size budgets come from S5's measurements, with CI failing on 10% growth; memoshid keeps its own resource bundles; PiCodingAgent's downloader is compiled out; the macOS floor follows the current-and-previous policy alone; a Node packaging spike happens only if the Mac misses the gate.
- **Rationale:** The user's answers.
- **Consequences:** about 1.5 weeks [INFERENCE: 6.5 days summed from the rows' estimates]; the review's tally is about 45.75 weeks.

<a id="d85"></a>
### D85. Review table 5: the experience, design, coding and security
- **Status:** Accepted (user decisions, 2026-10-22; keeps approved as a list, changes row by row; one row left to the recommendation). Amends [D43](#d43), [D60](#d60), [D75](#d75) and [D77](#d77), and `02-experience.md`, `03-design-system.md`, `07-coding.md` and `08-security-and-privacy.md`. [D92](#d92) (2026-10-23) retains Frosted/Solid as an appearance option, not a requirement for exact Kuvo parity; its other choices remain.
- **Choice:** the 67 outcomes of table 5 in [`inferred-choices-review.md`](inferred-choices-review.md#table-5): 44 kept as specified, 20 changed and 3 matched earlier outcomes. The ones that change behaviour:
  - **Mini apps on the Mac** open as a sheet over their conversation, with Open in Window and Full Screen one click away, and a per-app setting to always open one way.
  - **iPhone and iPad:** the welcome screen leads with "Pair with your Mac", with "Set up here" beside it; coding sessions show Changes and Files with Accept, comments and Commit (run on the Mac through typed calls), and the terminal mirrored read-only; a secure answer given on one device travels MLS-encrypted to the runner's browser, which fills it in.
  - **Coding:** a subfolder's AGENTS.md loads when the bot first works there; the Mac bundles signed ripgrep and fd inside the sandbox; commit messages follow the repository's recent style; a project without pins gets its own uv `.venv`; `pylock.toml` counts as a pin.
  - **Notebooks:** HTML and Plotly outputs render in the sandboxed artifact web view; when the user and a bot edit the same cell, the user's edit wins and the bot's change becomes a proposal.
  - **Security:** spike S3 also tests WebKit's known proxy bypasses; secret files are invisible to the sandbox, not just unreadable, verified in spike C6; skills and MCP servers get a model review at install that can only add warnings; the Sparkle signing key lives in the reviewer-gated CI environment, and a compromised key rotates through a Developer ID-signed DMG.
  - **Design:** Kuvo's Frosted/Solid appearance toggle ([D43](#d43) parity); ⌥⌘\` moves between panes alongside F6; the iSH inspector adds a process list and Reset image.
- **Rationale:** The user's answers.
- **Consequences:** about 3 weeks [INFERENCE: 16 days, after removing the browser takeover already counted in D83]; the review's tally is about 48.75 weeks.

<a id="d86"></a>
### D86. Review table 6: the roadmap, risks, Phase 0 and product
- **Status:** Accepted (user decisions, 2026-10-22; keeps approved as a list, changes row by row). Amends [D55](#d55), [D59](#d59) (the Mac app's bundle ID) and [`NEXT_VERSION.md`](NEXT_VERSION.md)'s proposals. Amended by [D90](#d90) (2026-10-23): until the Mac mini is set up, the self-hosted runner can be the development Mac, and pull requests from forks never reach it. Amended by [D91](#d91) (2026-10-23): a personal Kuvo fork is an allowed option again, not a selected cutover.
- **Choice:** the 72 outcomes of table 6 in [`inferred-choices-review.md`](inferred-choices-review.md#table-6): 43 kept as specified, 26 changed and 3 matched earlier outcomes. The ones that change behaviour or scope:
  - **Identifiers:** the Mac app gets its own bundle ID, `com.mehmetcanbudak.memoshi.mac`; the iPhone and iPad app keeps `com.mehmetcanbudak.memoshi`. P0-16 creates them; they are permanent.
  - **Clean room:** Track A, a personal Kuvo fork, is dropped; using Kuvo's released app stays fine ([D55](#d55)).
  - **Proposals adopted from NEXT_VERSION:** QuickAsk in full in v1, with live typed drafts, no keystrokes sent to a remote model without disclosure, and Undo as a new authorized act; visual task and artifact views in v1, with Groups' explanations arriving with Groups in v1.1; shared rooms move to v1.1 with Groups, and "routing never grants permission" is a rule from v1; Apple tools with the WeatherKit framework on the Mac if S5 confirms it, and AlarmKit on iPad too; bot.md imports keep D26's proposals.
  - **Targets and signals:** replica lag p95 under 250 ms direct and 1 s via the relay; relay approvals under 5 s p95; a 10,000-line diff opens in 500 ms; cost previews show a calibrated range; voice turns p50 under 500 ms (v2); the Swift engine signal at 1 program in 10 failing; a schedule signal when the port trails upstream by 4 weeks; the red-team suite covers every source, mode, tier and origin.
  - **Operations:** the builder's spend stays capped at $300 a month until M2.1, then at a larger cap the user sets; a nightly TestFlight upload whenever main changed; a self-hosted Mac mini CI runner; relay logs hold metadata only for 7 days, with the relay free and capped for the user and invited testers; a GPL self-check before any friend installs a build, and the lawyer before a public release; notebooks on iPhone and iPad become a protected row; local metrics only, with NPS waiting for a public release.
- **Rationale:** The user's answers.
- **Consequences:** about 2 weeks [INFERENCE: 3 days from the rows, about 3 for live QuickAsk drafts and about 5 for the visual views]; the review's tally is about 50.75 weeks. Shared rooms add to v1.1, not v1.

<a id="d87"></a>
### D87. Staged calendar: v1.0 on Fri 2028-11-24, then two feature drops
- **Status:** Accepted (user decision, 2026-10-22, at the end of the review of inferred choices). Supersedes [D70](#d70)'s calendar. Change-control rule 3 roadmap review. Settles the review's tally (D71–D86, about 51 plan weeks [INFERENCE]). Amended by [D88](#d88) (2026-10-23): v1.0 queues messages when offline without a model, rather than promising an answer; MOD-09 remains in Drop 2 and the calendar is unchanged.
- **Choice:**
  - **v1.0 carries the review's foundations and all earlier v1 scope.** The foundations, about 30 weeks: the core Swift language (value types, `@Observable` classes, protocols, closures), per-value tracking, permission lists, migrations at publish, the per-bot engine helper and the typed API ([D71](#d71), [D72](#d72), [D78](#d78)); per-conversation leases, merged settings, the stable runner, safe failover and merged app data ([D73](#d73), [D74](#d74)); MLS with the recovery key, synced keys and biometrics ([D75](#d75), [D79](#d79)); budget slices, iOS isolation and Python's rules ([D76](#d76)); the sandbox guard, checkpoints and Mac sleep ([D77](#d77)); the recovery rules and the model catalog ([D79](#d79)); and the foundation rows of tables 1–6 ([D81](#d81)–[D86](#d86)).
  - **The calendar** [INFERENCE: the review's estimates]:
    - Phase 0: 5 weeks, W1–W5 (2026-10-26 → 2026-11-27), unchanged.
    - Phase 1: 19 weeks, W6–W24 (2026-11-30 → 2027-04-23).
    - Phase 2: 35 weeks, W25–W59 (2027-04-26 → 2028-01-07).
    - Phase 3: 40 weeks, W60–W99 (2028-01-10 → 2028-10-13).
    - Phase 4: 6 weeks, W100–W105 (2028-10-16 → **Fri 2028-11-24, the v1.0 gate**); 105 plan weeks.
    - **Drop 1, mini app power:** 11 weeks, W106–W116 (2028-11-27 → 2029-02-23). Background jobs and widgets, the signed bytecode cache, the rest of Swift (own generics, actors, `async let`, task groups), rich styling, the bot's digest of program actions and the adaptive kit.
    - **Drop 2, devices and polish:** 10 weeks, W117–W126 (2029-02-26 → 2029-05-04). The on-device phone model, synced browser cookies, browser takeover across devices, coding on iPhone and iPad, notebook extras (HTML outputs, co-editing, folder sync), live Apple-data cards, visual views, live QuickAsk drafts and the Apple tools proposal.
    - Year-end breaks (2026, 2027, 2028) stay outside plan weeks.
    - **v1.1 (Phase 5)** starts Mon 2029-05-07, sized at the v1.0 gate: the earlier v1.1 scope plus shared rooms ([D86](#d86)), remote machines reachable from any device and published VM image sources ([D82](#d82), [D83](#d83)).
  - Each drop has its own gate review, like a phase.
- **Rationale:** The user chose a staged plan over one gate on about Fri 2029-05-11. v1.0 lands six months earlier, and the foundations come first, so the drops add features without rework.
- **Consequences:** the roadmap, the feature catalog's phase column (Drop 1 and Drop 2 rows), the risk gates (plan weeks 5, 24, 59, 99, 105, 116 and 126), MASTER_PLAN, HANDOFF, README and the product release lists follow.

<a id="d88"></a>
### D88. Queue offline messages until a model is reachable
- **Status:** Accepted (user choice, 2026-10-23: "Queue until reconnected"). Amends [D49](#d49)'s offline-answer promise, [D80](#d80)'s no-model fallback, [D82](#d82)'s side-thread summary rule and [D87](#d87)'s v1.0 acceptance scope. Change-control rules 3 and 4: roadmap and object-model review.
- **Choice:**
  - **No model, no answer.** When a device cannot reach the conversation's runner and has no available, allowed model, it keeps the user's messages in its device-local unsent queue and shows **Waiting for connection**. The queue survives an app restart, keeps each message's existing client `requestId`, and may be canceled before delivery. It neither writes the conversation's authoritative store nor starts a model turn, a tool call or an external effect.
  - **Reconnect through the normal runner.** Once connectivity returns, uncanceled messages go through the existing forwarding and idempotent submission path to the conversation's current confirmed runner. They reuse their original `requestId`; a reconnect or app restart does not submit another copy. Current grants, budgets and the recovery hold still apply. Queuing does not take a lease or choose an unapproved fallback model.
  - **Side threads still require a model.** If the runner is unreachable but an allowed model is reachable, the existing side-thread rules still apply. A wholly disconnected device can answer only with an available on-device model. A pending message with no model is not an answered side thread, and has no fabricated answer, summary or effects. A real side thread is summarized by an available allowed model when it rejoins, with the exact effect list from its records.
  - **Release boundary.** MOD-09 remains in Drop 2. Before then, the reference iPhone's fully disconnected no-model path queues; its v1.0 gate proves retention across restart, no execution while queued, cancellation, and one delivery after reconnect. Drop 2 additionally proves actual offline answers with the downloaded model, with the same safe queuing behavior when that model is unavailable.
- **Rationale:** The user chose to keep [D87](#d87)'s staged release rather than bring the phone model forward. The old Phase 3 demo promised answers on a reference iPhone for which the plan supplied no offline model.
- **Consequences:** DEV-09 stays Phase 3 P0 with a capability-aware gate; MOD-09 stays Drop 2. Product journeys, UI states, side-thread and protocol contracts, the release gate and the Pi_Swift requirements distinguish pending messages from executed side threads. This is app-layer behavior, not a new Pi_Swift engine capability. The roadmap review keeps D87's dates and phase totals; no Phase 0 device or recovery gate has been executed by this documentation change.

<a id="d89"></a>
### D89. Code Mode: wasm2c for shipping, WasmKit as reference and fallback
- **Status:** Accepted (2026-10-23: the user adopted the Pi_Swift engine handoff and authorized this reconciliation). Supersedes [D64](#d64) and [D79](#d79)'s Code Mode clause, and replaces [D50](#d50)'s JavaScriptCore fallback. Amended by [D90](#d90) (2026-10-23): the workload record adds a memory ceiling.
- **Choice:**
  - **One pinned guest, two backends.** Code Mode runs upstream's `quickjs.wasm`. Shipping builds translate it to C with `wasm2c`; WasmKit runs the same guest as the reference and compatibility fallback. JavaScriptCore is neither a WebAssembly nor a JavaScript fallback. The adopted build pins quickjs-wasi 3.6.2 (QuickJS-NG 0.17.0) and WABT 1.0.42; later pins follow Pi_Swift's upstream-sync process.
  - **Constrained host integration.** The C backend uses explicit bounds checks, malloc-backed linear memory, no signal handler and retained call-depth protection, with generated-source provenance and compiler settings recorded. Memory limits, interruption, trap handling and the Swift/C boundary must pass the engine's verification; faster desktop measurements do not establish those properties.
  - **Parity before default.** Pi_Swift's differential check against the upstream Node oracle gates making wasm2c the default. The shared guest identity alone does not prove replay equivalence. Journals, host calls, clocks, rounding and failure behavior must agree; WasmKit remains a reference and fallback, not a presumed faster escape from a device performance failure.
  - **Device evidence before shipping.** On Thu 2026-11-12, measure both backends in Release on the iPhone 14 Pro, cold and warm, against the workload and p95 limits Memoshi must record by Mon 2026-11-09. S1.18 uses that evidence and still proves policy coverage, recovery and the iOS scenarios in the integrated host. Retire S1.19's JavaScriptCore experiment; an unset workload or missing device result is not a pass.
- **Rationale:** The [adopted Pi_Swift engine report](../../../Pi_Swift/docs/design/code-mode-engine-2026-10-23.md) records promising wasm2c measurements on an M4 Max and the reasons for rejecting JavaScriptCore. Those are desktop observations, not iPhone results or a proof of integrated replay equivalence.
- **Consequences:** Align active Memoshi plans and specs with Pi_Swift E7, requirements §6 and M4–M5. Preserve the existing parity and physical-device gates. The roadmap review changes no phase scope or dates; no runtime backend is implemented, benchmark rerun or device gate passed by this decision record.

<a id="d90"></a>
### D90. Phase 0 readiness: the engine trigger, a Code Mode memory ceiling and the CI host
- **Status:** Accepted (2026-10-23; left to the recommendation: the user asked to "do what's best" and fix what the Phase 0 readiness check found). Amends [D44](#d44)'s and [D65](#d65)'s move trigger, [D86](#d86)'s CI runner and [D89](#d89)'s device gate. No scope or date changes, so no roadmap review (change-control rule 3).
- **Choice:**
  - **Slice-ready starts the engine work.** P0-05 and P0-06 start when Pi_Swift is slice-ready, as its [requirements §4](../../../Pi_Swift/docs/research/apple-bots-engine-requirements.md#4-gates-before-an-app-depends-on-the-engine) define it: the product slice builds in CI for macOS 27 and iOS 27, every slice test target compiles, the storage and environment conformance suites and the Code Mode suite pass at the pin on macOS, the E11 switch is in, and a `slice-N` tag and consumer note exist. Pi_Swift plans `slice-1` for Fri 2026-10-30 (its M2). If that slips, adapter code may be written against whatever compiles, but S1 results count as gate evidence only on a `slice-N` tag. Memoshi-Plan's move to Pi_Swift waits for the same point.
  - **A memory ceiling for Code Mode.** The record due Mon 2026-11-09 adds a memory ceiling to the workload and its cold and warm p95 limits: the most memory the workload adds to the app's footprint over its idle baseline, with the warm pool included. Pi_Swift's Release runs on the iPhone 14 Pro on Thu 2026-11-12 already record peak memory; a shipping backend over the ceiling fails like one over a time limit.
  - **A private repository and a safe runner.** P0-01 creates a private GitHub repository for Memoshi's code (this repository has no remote yet) and registers its self-hosted runner on the Mac mini that D86 chose, or on the development Mac beside Pi_Swift's runner until the Mac mini is set up. Self-hosted jobs run for pushes, schedules and manual runs in the repository itself, never for pull requests from forks, so the repository can later go public without exposing the runner. GitHub's guidance is that self-hosted runners "should almost never be used for public repositories on GitHub, because any user can open pull requests against the repository and compromise the environment" ([GitHub Docs, secure use reference](https://docs.github.com/en/actions/reference/security/secure-use); Claim; read 2026-10-23).
- **Rationale:** The two repositories disagreed: Pi_Swift's milestones and this repo's HANDOFF named slice-ready, while `phase-0.md` and the roadmap said the slice only had to compile. S1 numbers taken on an engine whose conformance suites fail could not count at the gate. On the 6 GB reference iPhone, memory rather than time is what gets the app ended, and the heavy runtimes already take turns ([D80](#d80)); a time-only gate could pass a backend that fails there. A runner that forks can reach would let anyone's code run on the Mac that signs and notarizes the builds [INFERENCE: CI holds those credentials from P0-14].
- **Consequences:** `phase-0.md` (the W2 row, P0-01, P0-05, S1 and S1.18 with its measurement table, the exit criteria, the risk table and open questions 3 and 5); the roadmap's Phase 0 rows, exit criterion and dependencies; the Code Mode gates in 04, 06, 07, 09 and the policy spec; R39 and R50; MASTER_PLAN, HANDOFF and README; Pi_Swift's requirements §4 and §6 and its milestones. The user's note to Memoshi-Plan's agent now reads "Node Pi until Pi_Swift is slice-ready". The user's execution hold stands; [HANDOFF §8](../HANDOFF.md#8-next-moves) records its scope and the dates it must be lifted by to keep the Phase 0 gate.

<a id="d91"></a>
### D91. Kuvo Code source access and personal-use code reuse
- **Status:** Accepted (user choice, 2026-10-23). Amends [D33](#d33), [D43](#d43) and [D86](#d86); supersedes [D55](#d55)'s source-access restrictions, observer separation and requirement for legal review before private reference/reuse work. Its reopened design/staffing questions are settled by [D92](#d92) and [D93](#d93); its source/reuse terms and no-selected-fork boundary remain.
- **Choice:**
  - **Source access is allowed.** The user, researchers, observers and builders may inspect Kuvo Code's GitHub source and copy or adapt its code for this personal/noncommercial project under its applicable licence. A personal fork and selective frontend reuse are allowed options. This exception is specific to Kuvo Code, not every source-available or proprietary product.
  - **Permission is not a cutover.** Keep this Memoshi repository, Pi_Swift/Pi Durable, MemoshiProtocol and the existing policy, recovery and device contracts. Inspect the actual frontend/runtime coupling before choosing a fork or import. This decision imports no code, selects no replacement frontend and claims no saved weeks.
  - **Preserve rights and provenance.** Record the upstream revision, paths, changes, licence and required notices for any reused material. Kuvo's [PolyForm Noncommercial 1.0.0 licence](https://github.com/serhatandic/kuvo-code/blob/main/LICENSE) permits qualifying noncommercial modifications and redistribution; it does not make retained Kuvo material Apache-2.0. Replacing opencode or changing most of the app does not erase those obligations, and a separate module does not itself cure licence incompatibility. Check included third-party terms separately.
  - **Private work is not gated on hiring a lawyer.** P0-19 is a source-informed reference/reuse assessment that builders may perform; it no longer needs a separate observer or P0-22 first. P0-22 records the licence/provenance review and unresolved distribution rights. Preserve the review before public/commercial distribution, including compatibility if Kuvo code is proposed for the GPL-linked iSH mobile app. The current dependency licence scan is not proof of vendored-source provenance or compatibility; any actual import must add the applicable notices and enforcement before consumption.
  - **Keep original branding and private evidence.** This code permission does not authorize copying Viticci, Grok or MemoBot artwork or private content. Memoshi's branding remains original. Establish rights separately before importing product art; third-party captures and personal data stay outside both repositories.
  - **Reopen design, do not silently decide it.** Recheck Viticci's Apple-native interfaces and the earlier user conversations. His examples guide the discussion alongside Kuvo's workbench. [D43](#d43)'s existing visual baseline, [D45](#d45)'s contracting assumption and the accepted feature stages remain unchanged until the user decides their amendments.
- **Rationale:** The user explicitly permits inspecting and copying Kuvo code for personal forks, consistent with [D67](#d67)'s own-device-first goal. Public source availability alone is not a licence grant; the applicable terms and the user's stated personal-use intent are the basis for this change.
- **Consequences:** Update the active plan, specs and handoff; P0-19 may use source evidence, while unverified Draft 3 values remain provisional until checked against a named revision or runtime observation. Change-control rules 3 and 5 trigger roadmap and design reviews: no runtime scope, phase dates or D1/D2 feature placements change merely because reuse is now permitted. The [design-direction review](../research/2026-10-23-design-direction-review.md) records evidence and proposals, not an adopted redesign.

<a id="d92"></a>
### D92. Viticci-led assistant design with a Kuvo-informed workbench
- **Status:** Accepted (user's ask-tool choice, 2026-10-23: “Viticci-led assistant + Kuvo workbench”). Supersedes [D43](#d43)'s blanket 100/100 shared-surface visual/behavior parity and parity-spec-wins precedence; amends [D81](#d81), [D85](#d85) and [D91](#d91)'s open visual question.
- **Choice:**
  - **One Apple-native family.** Viticci's observed assistant interaction grammar leads: persistent bots and conversations, native resource cards, concise work summaries with inspectable activity, and versioned mini apps with change requests. Use native, adaptive navigation on Mac, iPhone and iPad rather than scaling down the desktop.
  - **Kuvo informs the workbench.** Preserve its project/workspace, files, terminal, diff and review strengths and assess suitable frontend reuse under D91. This is not a second skin or an exact-pixel requirement, including in coding surfaces.
  - **Memoshi owns the design contract.** Shared semantic tokens, state/action honesty, policy boundaries, accessibility and performance budgets govern every surface. P0-19's planned output becomes `docs/specs/design-reference.md`: the assistant/workbench reference and source-reuse assessment, not a competitor-parity contract. No old spec file exists to retain as an alias.
  - **Review scenarios, not a parity score.** Review personal-resource, delegation, project-review and mini-app journeys as their accepted features ship, across relevant devices and empty/loading/error/permission states. Keep same-state visual evidence and measurements, VoiceOver/keyboard/Dynamic Type/contrast/Reduce Motion checks, and all existing performance gates; an attractive screenshot is not successful execution.
  - **No silent feature redesign.** This hierarchy does not choose new tabs, sidebar order, a second composer, avatar geometry, numeric tokens, a fork or an import. Existing working layouts, the Apps section and Frosted/Solid remain. Aiden/Grok/Metal later-pass features, runtime parity gates and D87's phase/D1/D2 stages and dates do not move.
- **Rationale:** The [reopened design evidence](../research/2026-10-23-design-direction-review.md) and earlier user requests call for Viticci's general Apple-native assistant direction alongside Kuvo's workspaces, not mandatory Kuvo identity on every shared Mac surface. The user selected this over retaining exact parity.
- **Consequences:** Update current design precedence, planned P0-19 path, provenance metadata and visual acceptance wording throughout the plan/specs/handoff. Unknown Draft 3 values stay provisional; a Kuvo value is reference input, not automatically Memoshi's adopted token. Design and roadmap reviews change no runtime scope or calendar by this decision alone.

<a id="d93"></a>
### D93. No mandatory designer contract
- **Status:** Accepted (user's ask-tool choice, 2026-10-23: “No mandatory designer”). Amends [D45](#d45)'s staffing assumption and [D91](#d91)'s open contracting question.
- **Choice:**
  - The builder and coding agents implement against the user-approved reference hierarchy in D92, with the user's design review. There is no mandatory freelancer, fixed five-day allocation, payment or hiring dependency in Phase 0.
  - Targeted outside artwork, accessibility or polish help is optional later for a concrete identified gap, with scope and cost chosen separately. This decision assumes no existing contract or cancellation.
  - Design QA, original-brand/art rights, accessibility and performance acceptance remain required. Optional help does not weaken quality gates or establish that agents solve every design problem unaided.
- **Rationale:** The approved references and iterative review provide the initial direction. The user rejected retaining the planned five-day contract as a prerequisite.
- **Consequences:** Remove mandatory contracting/hiring language from current staffing, tickets, dependencies and risk assumptions. Keep existing builder estimates, capacity reviews, cuts and D87 dates; deleting an external-help assumption is not measured savings or permission to advance feature stages.

<a id="d94"></a>
### D94. Newer Viticci preview layout and reversible palette comparison
- **Status:** Accepted (explicit user direction, 2026-10-25). Amends [D92](#d92)'s layout/token deferral for this native design-preview slice; final visual approval remains iterative.
- **Choice:**
  - **Use the newer reference set, not just polish the first preview.** The user-supplied newer Mac/iOS images and iOS clip guide warmer surfaces, floating bot identities, compact mobile composition, a richer Mac sidebar and resource-card presentation. Keep original Memoshi artwork, symbols and example copy; importing third-party media is not authorized.
  - **Compare Current and Warm in the running apps.** Current retains the prior neutral/system-accent color roles; Warm is an original ivory/amber interpretation of the newer reference, with light, dark and increased-contrast variants. Start the preview in Warm and persist each app's selection locally. Switching changes appearance without resetting drafts, bot selection or panes. This selects a reviewable comparison, not final pixel measurements or a replacement for the planned Frosted/Solid setting.
  - **Native phone navigation and a compact composer.** The preview has Bots, Memoshi, Others and Search tabs, retaining per-bot local drafts and truthful disconnected state. The universal app uses adaptive native navigation rather than a scaled-down desktop.
  - **Richer Mac navigation and a real contextual column.** Waiting for You, Library, Pages, Activity, local project context, Pinned and Bots replace the simplified roster. The right column can show the targeted bot's example Activity, selected resource details or a second bot conversation. Different bots have independent drafts; showing the same bot twice mirrors its single example chat, not two new threads.
  - **Tangible resource cards.** Use resource-specific serif headings, category labels, refined surfaces, native Share, exact labelled-sample Copy, working detail presentation and existing card-specific controls.
- **Rationale:** The user explicitly selected all four newer-reference changes and requested a palette selector to make comparison and subsequent design discussion easier.
- **Consequences:** Record implementation, source boundaries and exercised native scenarios in [design-reference.md](../specs/design-reference.md); generate both palettes from [design-tokens.json](../specs/design-tokens.json). This UI slice does not complete P0-13/P0-19 or any runtime/device/performance gate, import Kuvo code, connect Apple services, replace Pi_Swift/Pi Durable or change D87's scope, phases, dates, future Apps section or execution hold.

<a id="d95"></a>
### D95. Authenticated local transport on exact-pinned SwiftNIO
- **Status:** Accepted (2026-10-25; after the public-SDK feasibility investigation, the user delegated the NIO-versus-XPC choice: “Do whats best and sota”). Supersedes only [D82](#d82)'s Network.framework selection and its restriction of a SwiftNIO fallback to backpressure gaps.
- **Choice:**
  - **One stack on both sides.** Use SwiftNIO **exactly 2.104.0**, with NIOPosix Unix sockets and NIOWebSocket, shared by memoshid and MemoshiClient through `Packages/MemoshiIPC`'s `MemoshiTransport` product. No Network.framework transport or XPC cutover remains selected.
  - **Authenticate the connected socket before HTTP.** Keep `autoRead` disabled from channel creation. Inspect that same connected descriptor through `withUnsafeTransportIfAvailable(of: NIOBSDSocket.Handle.self)`; require same-user `getpeereid` and `LOCAL_PEERTOKEN`, then audit-selected dynamic code validation with `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)`. Require the Apple anchor, our Team ID, the sealed expected signing identifier and hardened runtime; reject ad-hoc signatures and hardening relaxations. Only after these checks may either side install HTTP/WebSocket handlers or read/write protocol bytes. The client validates the daemon before reading the per-start token.
  - **Preserve the contract.** [D13](#d13)'s bidirectional JSON-RPC/WebSocket/AF_UNIX boundary, private filesystem modes, rotated token, five-second hello, roles, typed schema, ordering/replay, bounded queues and no-Node decision remain. This changes transport technology, not product authority, policy or device leases.
  - **No signing bypass.** Repository defaults remain ad-hoc: a normal development build must fail closed and show that qualifying signing is required. Separate Apple Development-signed harness evidence is not Developer ID, provisioning, notarization or deployment approval; those gates remain under P0-14/P0-16 and S5.
- **Rationale:** The Xcode 27.1/macOS 27 public Network.framework API exposes no connected Unix peer descriptor, audit token or adopted-descriptor seam that can satisfy the required same-socket credential checks before HTTP/WebSocket. The blocker is authentication, not a hypothetical backpressure failure. Exact-pinned NIO exposes the actual socket while preserving D13; XPC would change that wire boundary.
- **Consequences:** Reconcile protocol §2, architecture and P0-07/P0-08 with the [shared transport implementation](../../Packages/MemoshiIPC/Sources/MemoshiTransport/LocalWebSocket.swift), [peer validation](../../Packages/MemoshiIPC/Sources/MemoshiTransport/PeerAuthentication.swift) and [Security bridge](../../Packages/MemoshiIPC/Sources/CMemoshiSecurity/CMemoshiSecurity.c). The [foundation implementation/proof record](../HANDOFF.md#foundation-implementation-proof) separates actual observations from remaining gates. Ticket IDs, estimates, D87's calendar, Pi_Swift's readiness trigger, production signing requirements and the real-device/recovery execution hold do not change; code and smoke evidence alone do not complete a ticket or Phase 0.

<a id="d96"></a>
### D96. Qualify private Mac working copies instead of direct live-folder execution
- **Status:** Accepted for qualification (user's ask-tool choice, 2026-10-27: “Private Mac working copies”). Amends [D16](#d16), [D77](#d77) and [D81](#d81) only for This Mac's filesystem workflow; it is not production or S4 acceptance. Amended by [D137](#d137) (2026-11-14): two accepted limits and an open-writer warning.
- **Choice:**
  - **Keep native Mac execution, change file exposure.** Qualify the sandboxed PiEnv daemon against a private working copy rather than adding the user's live source folders or main repository metadata to its read/write profile. File tools and commands run inside Seatbelt through the existing `RemoteExecutionEnv` path. Approved system/toolchain reads remain explicit; the bot gets no ambient live-folder capability.
  - **Admit inputs through trusted host code.** A selected folder grant authorizes checked input admission and, if read-write, possible later export; it is not a direct sandbox path exception. Descriptor-relative no-follow traversal validates every admitted entry. Refuse unsafe symbolic links, multiply-linked regular files and special files rather than blindly copying or silently omitting them. Admitted working files must have independent inode identity. Root/grant restrictions and secret handling remain in force.
  - **Private edits are not original-file effects.** Bot writes change the private copy. Originals change only through a separate trusted host export, with an immutable content-bound proposal, current original-folder authority, the existing policy/approval rules and live source-conflict checks. Read-only grants cannot export. Staging beneath a bot home never lowers the original path's `secret`, `host_exec`, `instruction`, `git_internal` or `ci_config` classification.
  - **Host export handles data, never repository programs.** Open verified directory descriptors, use no-follow target handling and temporary-file/`renameat` replacement, preserve outside edits on detected conflicts and report partial/unknown effects honestly. Hardened host git remains the only host-side coding-program path and never runs repository hooks. Normal conflict checks are not a claim of a multi-file filesystem transaction or proven non-cooperating-writer compare-and-swap.
  - **Qualify before enabling.** Exercise link refusal at admission, independent copy identity, no direct live-path access from raw/file/exec paths, private-copy-only writes, real approval/revocation/content binding and conflict-preserving export. Retain D77's zero-escape scorecard and its daemon guard, full conformance, gateway/masks, toolchain, attribution, privacy-prompt and performance gates. The pinned SDK's missing guarded-file-service seam is not waived. Production tools remain disabled until the required gates pass.
  - **No new user-facing computer or blanket OS setup.** This remains This Mac (`mac_sandbox`), not a new Workspace object or VM level. Bind private copies to the existing bot/computer/conversation or project Session authority and checkpoints. The qualification uses isolated synthetic data under the current user; it does not require a privileged launcher, another account, personal-folder permission changes or a service install. The existing test account is left intact.
- **Rationale:** Both path-profile prototypes and the actual separate-user fallback failed the preexisting inode-alias gate. The Standard account correctly denied host-owned `0600` data, but readable `0644` aliases inside a grant still worked through raw reads, SDK reads and SDK exec. The user chose to qualify private working copies over the remaining Linux-only VM fallback or leaving file/command work blocked while doing unrelated Phase 0 work.
- **Consequences:** Reconcile This Mac, granted-folder, policy, coding and environment-factory descriptions with checked admission, private execution and policy-controlled export. Do not share live main-repository `.git` files/object stores into the model environment; private coding metadata must be qualified in Phase 2. No new schema kind, phase, estimate, date or measured saving is inferred; D87's calendar, D90's slice gate and the device/intentional-kill hold are unchanged. If this candidate fails, D77's remaining Linux VM is still only for Linux-compatible work and itself needs qualification. [Measured prerequisite failures](../HANDOFF.md#s4-separate-user-setup).
- **Qualification follow-through (2026-10-27):** the [bounded native filesystem and durable-policy export proof](../HANDOFF.md#s4-private-working-copies) passed on synthetic data; source/report bytes and normal shutdown are retained. This is not full S4 or production acceptance. The content-only actor refuses directory/mode changes; product source grants/sensitive-path mapping, SDK guard/conformance and the remaining full-S4 gates stay open.
- **Runtime follow-through (2026-11-02):** the [runtime-owned copy/export library](../HANDOFF.md#runtime-working-copy-development-proof) now replaces the external-only mechanism for new consumers, retaining content-only limits and disabled product composition. Native policy/effect/unknown-outcome and cross-Chat checks passed, with canonical CI. This is implementation evidence, not an amendment of the unchanged SDK/full-S4/metadata/recovery/release gates or D87's staging.
- **Metadata follow-through (2026-11-02):** the [conservative runtime metadata profile and native proof](../HANDOFF.md#working-copy-metadata-development-proof) refuse unsupported ACLs, attributes/forks and flags rather than dropping them. This qualifies bounded refusal, not general metadata preservation or an amendment of D96/full-S4 gates; product tools remain disabled.
- **Resource follow-through (2026-11-02):** the [bounded copy profile and native proof](../HANDOFF.md#working-copy-limits-development-proof) add tightening-only development ceilings for admission/scans/proposals/export history and explicit bounded-cleanup failure. Values are conservative [INFERENCE] pre-enablement limits, not product workload/performance acceptance. Recovery, live-writer/global/hard-duration resource guarantees, SDK/full-S4 and release gates remain; no automatic restart export or product-tool enablement follows.

<a id="d97"></a>
### D97. Track stable Apple toolchains through qualified baselines
- **Status:** Accepted for the current upgrade (2026-11-01 toolchain follow-through requested by the user after asking to use newer/latest versions).
- **Choice:** Adopt the installed **Xcode 27.2 / Swift 6.4.2** in place of the former Xcode 27.1 / Swift 6.4 baseline. Prefer newer stable Apple releases as they become available, but record the selected Xcode/compiler versions, run the canonical CI entrypoint and exercise affected native behavior before treating that upgrade as qualified. Keep the previous proof's actual toolchain/version facts historical.
- **Rationale:** A permanently frozen old Xcode needlessly blocks useful upgrades; an unrecorded floating `latest` makes a result hard to reproduce and silently conflates a new SDK/compiler with the version previously tested. A current, explicitly qualified snapshot supports both upgrade cadence and diagnosable builds.
- **Consequences:** Update `scripts/check-toolchain.sh`, the XcodeGen source and the active toolchain paragraphs together. The checker still rejects an unqualified mismatch; it is not removed or weakened to an unbounded minimum-version check. XcodeGen remains 2.46.0 until separately upgraded. Deployment targets, Swift 6 language/strict-concurrency settings, SwiftPM's 6.4 tools minimum, exact Pi/NIO dependencies, D90's slice/release hold and held device/kill cases are unchanged. This does not authorize downloads, automatic host updates, new accounts, signing/entitlement changes or new product enablement. A failed upgrade remains unqualified rather than being declared green.

<a id="d98"></a>
### D98. Accept the Code Mode workload, p95 limits and memory ceiling
- **Status:** Accepted (2026-11-03; the user delegated Phase 0 open question 5: "do whats best"). Supplies [D90](#d90)'s Memoshi input to [D89](#d89)'s two-backend measurement.
- **Choice:** Accept the [versioned workload record](../research/spikes/2026-11-02-code-mode-workload.md) as proposed. Workloads W1 (5 nested calls) and W2 (12 nested calls) and stop/limit cases W3a–W3c; 10 launches per device × backend × case, with nearest-rank p95, which for 10 samples is the maximum. W1: cold p95 ≤ 600 ms, warm p95 ≤ 100 ms. W2: cold p95 ≤ 1,500 ms, warm p95 ≤ 1,000 ms. Incremental physical footprint ≤ 100,000,000 bytes. Stop settled p95 ≤ 1,000 ms. `wasm2c` on the iPhone 14 Pro is the gate subject; WasmKit is always reported and may cover a compatibility failure only after meeting the same limits.
- **Rationale:** The limits come from budgets Memoshi had already accepted (D83's Swift engine probe, the 500 ms engine cold start, CH-07's one-second Stop), not from desktop observations, and the fixtures reproduce exactly at the pinned candidate. Accepting them before Mon 2026-11-09 keeps Pi_Swift's Thu 2026-11-12 measurement possible; leaving them proposed would make S1.18 unmeasurable, not safer.
- **Consequences:** The record becomes binding for S1.18. Acceptance is not a measurement, SDK acceptance, a `slice-N` or a device run: the `wasm2c` backend, warm pool, device driver and device provisioning do not exist yet. The Mac Debug WasmKit diagnostics (W1 about 6.2 s, W2 about 12.5 s per script) are development observations that neither pass nor fail the Release device limits, but they show how far the shipping path must be from Debug interpretation [INFERENCE]. A device result above any limit triggers D89's `wasm2c` tuning and then D46's platform fallback; a limit is relaxed only by a new decision, never after the fact.

<a id="d99"></a>
### D99. Serve public files from memoshi.mehmetcanbudak.com
- **Status:** Accepted, registration pending (2026-11-03; the user delegated [D80](#d80)'s domain choice: "do whats best"). Buying the domain and changing DNS are the user's actions.
- **Choice:** Register `mehmetcanbudak.com` and serve Memoshi's public files from `memoshi.mehmetcanbudak.com` on GitHub Pages or Cloudflare Pages: the MCP client document, the universal-link file for sign-in redirects, the Mac update feed, the signed model catalog and the website.
- **Rationale:** These URLs become identities (OAuth client IDs, associated domains, the update feed inside shipped builds) that are costly to move. The product name is not cleared (O8, [R22](risks.md#r22)), and [D59](#d59) already keeps permanent identifiers under the user's own reverse-DNS prefix `com.mehmetcanbudak.memoshi` so a rename does not move them; the matching forward domain keeps that property. RDAP lookups on 2026-11-03 found `mehmetcanbudak.com`, `mehmetcanbudak.dev` and `mehmetcanbudak.app` unregistered, `memoshi.app` and `memoshi.dev` unregistered, and `memoshi.com` registered by another party since 2012. Availability can change before purchase.
- **Consequences:** Until registration nothing that embeds the domain ships; Pi_Swift's E29 sign-in redirect and the MCP client document wait for it. After registration: the subdomain's DNS record, HTTPS-only hosting, `/.well-known/apple-app-site-association`, and the associated-domains entitlement in P0-16's profiles. A product-named marketing domain may be added after O8 without moving identity-bearing files. Agents make no purchase, account or DNS change.
- **Amended 2026-11-10 (development host; user decision recorded with Pi_Swift):**
  - Until the domain is bought, sign-in development uses the Cloudflare Pages host `memoshi-auth.pages.dev` (project `memoshi-auth`, deployed 2026-11-10). It serves the MCP client document at `https://memoshi-auth.pages.dev/oauth/client.json` (`client_id` is that URL, redirect `https://memoshi-auth.pages.dev/oauth/callback`, no client secret) and `/.well-known/apple-app-site-association` for `476T8NQCSX.com.mehmetcanbudak.memoshi` and `476T8NQCSX.com.mehmetcanbudak.memoshi.mac`, path `/oauth/callback*`. On 2026-11-12 Apple's CDN returned that association file (HTTP 200, `application/json`). Record: "User decisions — 2026-11-10" in Pi_Swift's `docs/requests/2026-11-07-memoshi-slice-adoption.md`.
  - Memoshi's development builds add `applinks:memoshi-auth.pages.dev?mode=developer` and register that redirect. The Mac update feed, signed model catalog and website do not move to this host.
  - The user still buys a domain before release and attaches it to the same project. That changes the client identity, so test sign-ins are redone and the entitlement is updated; nothing that embeds `pages.dev` ships in a release build. The 2026-11-13 registration deadline no longer applies.
  - This Mac's network times out command-line HTTPS to `*.pages.dev` while browsers load it; universal links are unaffected because iOS fetches the association file from Apple's CDN.

<a id="d100"></a>
### D100. Python reaches the gateway through a sealed native bridge
- **Status:** Accepted for development (2026-11-06; the user delegated the open S6 route choice: "do whats best"). Changes how [D76](#d76)'s Python network rule is met on iPhone and iPad; [D81](#d81)'s WebKit loopback proxy stays the bot browser's route. S6.5 acceptance still needs its physical-device rows.
- **Choice:** Python in the in-app environment reaches the network only through native code. The sealed page's CSP refuses every direct connection from the Python worker, and Python's `fetch`/`pyfetch` are answered natively: the host checks the main frame, realm and live cell, then each hop gets its own decision from the in-app gateway under the bot's allowlists. S6.5's "every network request from the web view goes through its proxy" is measured as: every request reaches the gateway, and independent sinks see none go around it.
- **Rationale:** In every tested HTTP and SOCKS configuration, WebKit's configured proxy authenticated successfully while direct loopback requests still reached an independent sink ([S6 §2a](../research/spikes/2026-11-04-s6-pyodide-draft.md#2a-authenticated-package-route-and-failed-confinement)). The sealed route passed a complete development run ([S6 §2c](../research/spikes/2026-11-04-s6-pyodide-draft.md#2c-sealed-native-http-route-2026-11-06-development-control)): the worker's own fetch, XHR, WebSocket, remote import and a nested worker made zero requests, while native hops kept real HTTP semantics, per-hop decisions and native-only credential injection.
- **Consequences:** Python's network is a bounded fetch subset: no WebSocket, no `same-origin`, `no-cors` or integrity requests, and no general in-page package installer; registry installs ([06 §2.7](06-computers-and-browsers.md#27-iphone-and-ipad-the-in-app-environment)) download natively through the same gateway. The route is proven on the development Mac only; physical iPhone/iPad runs remain required, and no platform fallback or W25 cut follows from this decision.

<a id="d101"></a>
### D101. Bot browsers add a deny-local rule list and Lockdown Mode to the gateway route
- **Status:** Accepted for development (user decision, 2026-11-07, choosing among the measured options). Amends [D81](#d81)'s bot-browser route; [D100](#d100) is unchanged. S3 acceptance still needs its real-surface control run, physical-device rows and approved real sites.
- **Choice:** Every bot web view, on Mac and iPhone/iPad, applies three layers before any page loads:
  - [D81](#d81)'s authenticated gateway proxy;
  - a fixed deny-local `WKContentRuleList` (loopback, IP literals, `localhost`, `.local`), followed by the per-bot allowlist list;
  - `securityRestrictionMode = .lockdown`.

  Loads fail closed until all three are in place. Route allowlists exempt each granted origin's own `blob:` URLs, because WebKit reads File and Blob contents through `blob:` loads that content rules see; blob data never leaves the device, and other origins' blobs stay blocked. The owned direct-fixture route uses block-all plus its exact fixture origins instead of deny-local. A `target=_blank` click's empty loopback connection is a known, retained failing control.
- **Rationale:** A public-API prototype with independent loopback sinks ([design](../../../evidence/2026-11-07-memoshi-engineering/analysis/browser-no-bypass-design.md)) found three things:
  - WebKit exempts loopback and IP-literal targets from the configured proxy.
  - WebRTC (STUN/TURN) and WebTransport bypass it entirely.
  - A host Seatbelt profile does not confine WebKit's networking process.

  Deny-local rules close every URL-based loopback path. Lockdown is the only public switch that removes WebRTC and WebTransport. A Network Extension filter would conflict with 08 §15's no-privileged-helper rule.
- **Consequences:**
  - Lockdown disables about 51 web features, including service workers, IndexedDB, WebGL and JIT. Real-site task success under Lockdown is unmeasured.
  - The `target=_blank` preconnect remains open and is reported, not hidden.
  - The S3 no-bypass criterion is measured by the owned independent-sink control in `spikes/S3-webkit-browser/no-bypass/`.
  - No real-site run, packet capture or Developer ID-signed control has happened yet.
- **Amended 2026-11-08 (control follow-up):** WebKit's proxy exemption covers every IP-literal target, including private and ULA addresses, not only loopback; the deny-local list blocks them. No `data:`, LAN or alternate-loopback leak was found, and the iOS Simulator run passes ([evidence](../../../evidence/2026-11-08-memoshi-engineering/BrowserFollowups/)).
- **Amended 2026-11-08 (gateway route proven):**
  - Real WebKit now authenticates to the gateway and loads a granted owned-fixture host through it.
  - Loopback and private answers, a rebinding to loopback, and `.local` names are refused with 0 independent-sink connections.
  - A cancelling navigation policy prevents the empty preconnect only for page-initiated navigations. Loads through `WKWebView.load` preconnect before policy, so the product's `load()` route check is their control.
  - The no-bypass control passes apart from the retained `target=_blank` failure (2 connections per route), and every gateway decision is now attributed ([evidence](../../../evidence/2026-11-08-memoshi-engineering/GatewayAuth/)).

<a id="d102"></a>
### D102. The relay authority judges lease expiry at frame arrival
- **Status:** Accepted for development (user decision, 2026-11-07). Narrows [O10](#open-decisions)'s expiry clock for the relay authority; TTL, renewal interval and idle policy stay open.
- **Choice:** The relay's lease authority stamps each frame with its own clock when the transport reads it. It judges claim and renewal expiry at that arrival time, clamped to never exceed processing time. Decisions stay linearized through the epoch compare-and-swap. A renewal that arrives after expiry is still refused. `reserve` and write admission keep processing-time checks. The CloudKit authority, which has no server clock, is not covered.
- **Rationale:** The S2 quick cohorts lost their leases when storage stalls on the build volume delayed the authority's processing of renewals that had arrived in time ([diagnosis](../../../evidence/2026-11-07-memoshi-engineering/analysis/s2-renewal-diagnosis.md)). The regression suite failed before the change: a renewal that arrived at 2000 ms, before its 4000 ms expiry, was refused, and a competing claim won epoch 2. It passes after, with the late-arrival and competing-claim guards intact ([evidence](../../../evidence/2026-11-07-memoshi-engineering/S2LeaseFix/)).
- **Consequences:** This is not a TTL relaxation. An authority whose own durable write stalls past the TTL still loses the lease, so S2 qualification also needs bounded-latency storage. The 6 s first claim followed by 10 s renewals remains an open O10 policy question.
- **Amended 2026-11-08:** [D104](#d104) makes renewals extend by the claimed TTL, so the 6 s / 10 s mismatch above no longer occurs; the TTL value itself stays open under O10.

<a id="d103"></a>
### D103. Sandbox secret rules follow the host's secret list and cover secret-named directories
- **Status:** Accepted for development (user decision, 2026-11-07: strict). Amends [D96](#d96)'s sandbox profile; full S4 acceptance stays open.
- **Choice:** The Seatbelt profile's secret rules are generated from the same spelling list host admission uses (`SourceSecretSpellings`), and they protect every descendant of a secret-named directory. Toolchains that need such a path get an explicit grant, never a weaker rule. [D96](#d96)'s `renameat` names the mechanism: export replace and delete use `renameatx_np` with `RENAME_SWAP`/`RENAME_EXCL` and verify the moved object, so a late outside edit is restored and the export refuses.
- **Rationale:** Before the change, 20 of 31 policy secret spellings were readable inside the sandbox and all four secret-directory cases were readable and writable. Approved deletes and replaces destroyed outside edits made after the final conflict check ([evidence](../../../evidence/2026-11-07-memoshi-engineering/S4Controls/)). After the change, the real-profile proof shows 0 failures in 108 secret rows and 14 offline git/npm/pip/cargo/swift workflow rows.
- **Consequences:**
  - On volumes without swap support, export replace and delete are refused.
  - During a refused replace, the approved bytes are briefly visible at the user's file name.
  - The seven retained raw diagnostic effects stay attached to the earlier profile and are not reclassified.
  - Kernel-level limits remain: a writer holding an open descriptor, and multi-file atomicity.
- **Amended 2026-11-08 (export on volumes without swap):**
  - Volumes that report exclusive rename but no swap (HFS+) replace by moving the original aside exclusively, verifying it, then installing the replacement exclusively. The user's file name is briefly absent.
  - Volumes that report no exclusive rename (exFAT, FAT32) refuse every export before any effect, because no race-safe sequence exists there.
  - The mechanism follows the volume's reported capabilities, never errno alone: FAT32 accepts both flags as an ordinary overwriting rename.
  - The earlier "refused on volumes without swap support" consequence now applies only to volumes without exclusive rename ([evidence](../../../evidence/2026-11-08-memoshi-engineering/S4SwapFallback/)).

<a id="d104"></a>
### D104. Lease renewals extend by the claimed TTL; local lease writes do not hold up renewals
- **Status:** Accepted for development (2026-11-08; the user asked for the S2 follow-ups to be done). Narrows [O10](#open-decisions); TTL, renewal interval and idle policy stay open.
- **Choice:**
  - A runner renews each lease by the TTL it claimed it with. A claim without a TTL (hand-over, take-over, or resume after restart) uses the node's configured default.
  - Local store lease writes are queued per conversation, in the order the node decided them. The renewal loop does not wait for them; commits do. Each write carries only the authority-granted expiry.
  - A renewal reply that arrives after the node has seen a newer epoch, or has lost its runner role, is not recorded.
- **Rationale:**
  - Before: 6 s claims renewed to the node default (10 s, or 3 s once a scenario configured it). A held local store write stopped all renewals.
  - After: the regression suite passes ([evidence](../../../evidence/2026-11-08-memoshi-engineering/S2Followups/)). Three internal-disk quick cohorts each show 0 of 146–148 relay renewals off their claimed TTL, with no duplicate grants.
- **Consequences:**
  - [D102](#d102)'s arrival-time rule cannot apply to the CloudKit authority, for three reasons: its decisions run on the deciding device's clock, CloudKit's only server-side condition is the change tag, and the deadline is end-to-end encrypted. Cross-device clock skew is an open O10 risk.
  - The device journal write is still synchronous inside the node actor.
- **Amended 2026-11-08 (device journal):**
  - Device journal appends run on one ordered writer. A renewal's record is not awaited, because recovery re-reads the authority and resumes only an epoch the node already held.
  - A commit awaits its publication and change records without blocking the node. Lease decisions and replica applies still block until durable.
  - On a medium whose stalls outlast the TTL, leases are still lost, as [D102](#d102) states. On the USB disk image, stalls of 33–96 s cost the lease in three of three quick cohorts, with no duplicate grants ([evidence](../../../evidence/2026-11-08-memoshi-engineering/S2Round3/)).

<a id="d105"></a>
### D105. Python cells cannot start workers, and network access belongs to the cell that started the work
- **Status:** Accepted for development (2026-11-08; follows from the user's request to close the per-bot realm's lifecycle gaps). Amends [D100](#d100)'s consequences; S6's physical-device rows stay open.
- **Choice:** The per-bot Python realm refuses nested workers by removing `Worker` and `SharedWorker` before any interpreter code runs. Native network admission requires the requesting Python context to carry the live cell's token. Each cell runs as one asyncio task holding that token, which its own tasks inherit. Requests from JavaScript event callbacks, or from work an earlier cell left behind, are refused before reaching native.
- **Rationale:** In real WebKit, on an exact pre-change copy, a nested worker kept running after its cell returned, and an earlier cell's leftover callback and task were admitted under a later cell's ID. After the change neither happens, and the real-host carriers confirm it ([S6 §2f](../research/spikes/2026-11-04-s6-pyodide-draft.md#2f-nested-workers-and-cross-cell-borrowing-2026-11-08-development-measurement), [evidence](../../../evidence/2026-11-08-memoshi-engineering/PythonLifecycle/)).
- **Consequences:** Python cannot use Web Workers. Network calls must be awaited from cell code or from tasks it creates. Cell code that deliberately reaches a live cell's context through the shared interpreter (for example via `gc`) remains bounded only by native limits.
- **Amended 2026-11-08 (task-bound admission):**
  - **Mechanism:** admission no longer relies on a Python-visible token. The worker records, outside Python, each cell's root task and every task created while one of them runs. A request is admitted only while a recorded task is the interpreter's current task and its coroutine is executing. The check uses builtins captured before cell code runs.
  - **Before:** on an exact copy of the earlier worker, leftover work obtained a later cell's admission six ways: entering a live task's context or a copy of it, contexts found by `gc`, and the cell `ContextVar`.
  - **After:** all six and `_asyncio._swap_current_task` are refused.
  - **Unchanged:** ordinary networking (`pyfetch`, `js.fetch`, cell tasks, `gather`, `TaskGroup`, `wait_for`, requests after `sleep`) is admitted under its own cell. A fetch started synchronously by JavaScript that cell Python calls counts as the cell's own; one started after a JavaScript `await` is refused. The §2c scenario and the 20-call driver pass ([evidence](../../../evidence/2026-11-08-memoshi-engineering/PythonFinish/)).
  - **Residual:** Python that writes interpreter memory through `pyodide_js._module` can forge both facts. Only a realm per cell would prevent that, and [D100](#d100) excludes it, so native limits bound it. Separately, and on earlier workers too, a JavaScript function that returns `p.then(…)` on a promise from Python never settles, so cells consume fetch results in Python.

<a id="d106"></a>
### D106. Cognitio's design leads on every device, rebuilt in Memoshi's own code
- **Status:** Accepted (user's ask-tool choices, 2026-11-13: "Cognitio leads the whole shell on every device"; "Rebuild the same look and behaviour in Memoshi's own code"; a public or paid release stays possible). Supersedes [D92](#d92)'s design hierarchy and [D94](#d94)'s preview as the lead reference; amends [D91](#d91): the permitted Kuvo code reuse is not taken for the interface.
- **Choice:**
  - **Lead.** Cognitio (`~/Projects/Cognitio`, the user's Kuvo-derived Mac app) is the reference for the shell on Mac, iPad and iPhone: card window, sidebar, transcript, composer, bot identity and editor, side panel, workbench and settings. Viticci's grammar stays for native Apple-data cards, Apps and phone navigation.
  - **Own code.** The interface is written new in Memoshi as one SwiftUI codebase shared by the three devices, with AppKit or UIKit only where a surface needs it. No Kuvo- or Cognitio-derived source file, asset or string enters this repository. Cognitio's running app and source are read as a behaviour reference; code is not translated file by file.
  - **Permissive dependencies stay usable** from their original upstreams, not from Cognitio's forks: SwiftTerm, Textual, WhisperKit and the usage-meter library UsageKit forks.
  - **Release.** O13 stays open; nothing built under this decision may close a public or paid release.
  - **The existing preview is kept.** The Viticci-style Mac and iPhone preview is frozen at git tag `design-preview-2026-11-13`. The new shell starts from Cognitio's layout and reuses Memoshi's own tokens and avatar set where they fit.
- **Rationale:** The user prefers how Cognitio looks and works. Kuvo's PolyForm Noncommercial terms would bind any build that contains its code and would collide with the GPL iSH module on iPhone and iPad ([merge assessment §7](../research/2026-11-12-memoshi-cognitio-bot-hq-merge.md#7-constraints-that-bind-the-merge)). Rebuilding costs time and removes both problems.
- **Consequences:** Design review (rule 5): `02-experience.md`, `03-design-system.md`, `../specs/design-reference.md`. Each surface needs a written behaviour description before it is built, because the source may not be copied. DIST-03's Kuvo exception goes unused for interface code.

<a id="d107"></a>
### D107. Cognitio continues beside Memoshi
- **Status:** Accepted (user's ask-tool choice, 2026-11-13: "Keep developing both in parallel").
- **Choice:** Cognitio keeps its own development and plans, its iPhone plan included, in its own repository and under its own licence. It does not bind Memoshi, and Memoshi's agents do not edit it, as [D65](#d65) rules for Memoshi-Plan. It is D106's behaviour reference and the oracle for capability ports: its tests and vectors describe behaviour that Memoshi re-implements in Swift on Pi_Swift.
- **Rationale:** The user's choice. The [merge assessment](../research/2026-11-12-memoshi-cognitio-bot-hq-merge.md#8-decisions-this-needs) recommended freezing Cognitio's features; that recommendation was not taken.
- **Consequences:** Two live codebases share one builder's attention ([D45](#d45)) [INFERENCE]; the roadmap review counts it.

<a id="d108"></a>
### D108. Claude through Claude Code, as a coding worker and as a model on the Mac
- **Status:** Accepted (user's direction, 2026-11-13). Amends [D11](#d11) (role and stage), [D54](#d54) and catalog row DIST-03.
- **Choice:**
  - Claude Code, the unmodified program the user installs and signs in to with its own `claude auth login`, may serve as an external coding worker (D11) and as the model of any bot on the Mac, relayed through that program.
  - Memoshi starts no Anthropic sign-in, never reads, stores or forwards Claude credentials, and ships no Anthropic client ID. DIST-03 narrows from "no Anthropic subscription flows" to "no Anthropic sign-in flow inside the app", and its CI check follows.
  - A bot whose model is Claude Code has the Mac as its runner. From iPhone and iPad its messages forward to the Mac ([D73](#d73)) and wait while the Mac is unreachable ([D88](#d88)).
  - Subscription usage shows as price unknown, never as free.
  - Stages: model on the Mac in M1; coding worker in M2 ([D110](#d110), [D117](#d117)).
- **Rationale:** The user's existing subscription, and D11's own rationale: this is the route Anthropic allows inside another product. Ultimate's README says of the same route that "subscription coverage is not guaranteed".
- **Consequences:** The provider's terms are re-checked before any public release (O13). A terms change can remove this route; API keys and the other providers stay.

<a id="d109"></a>
### D109. The Assistant orchestrates lightly; bots message each other and form groups in v1.0
- **Status:** Accepted (user's ask-tool choices, 2026-11-13). Amends [D20](#d20), [D24](#d24), [D47](#d47) and [D87](#d87).
- **Choice:**
  - **Two ways of working, both first-class:** talking to the Assistant, which coordinates the team; and driving bots and sessions directly, as in a workbench.
  - **The Assistant** does small things itself (answers, memory, to-dos, lookups) and hands anything long-running or code-running to a bot or a session's lead through a Handoff. Every Handoff is visible. It answers a bot's question itself when the user already gave the answer; otherwise the question card reaches the user with a recommended pick.
  - **Bot-to-bot messages** (GR-06) move from v1.1 to M1, under the grant, the 8-hop cap and budgets.
  - **Groups** (GR-01–03, 05, 07, 09–11) move from v1.1 to M2 with D24's rules unchanged. Shared rooms with other people (GR-12) stay in v1.1.
  - **Goals**, a new object in M2: an outcome with criteria that a bot works toward hands-off, inside its budgets and the normal policy, keeping a log of each decision it took.
- **Rationale:** The user wants an orchestrating bot in the manner of Ultimate's and a direct engineering tool in the manner of Cognitio, and bots that talk to each other. Cognitio and Ultimate both ship goals.
- **Consequences:** Spec review (rule 4) for Goal; `05-bots-and-assistant.md`; roadmap review.

<a id="d110"></a>
### D110. Engineering: outside coding agents, team mode and self-checks in v1.0
- **Status:** Accepted (user's ask-tool choices, 2026-11-13). Amends [D11](#d11), [D47](#d47) and [D87](#d87).
- **Choice:**
  - **External coding agents** move from v1.1 to M2, Mac only: Codex app-server (R11-08), Claude Code (R11-09) and ACP agents (R11-10). Every tool call still passes Memoshi policy (D11). An agent whose kit needs a JavaScript runtime, Cursor's today, stays out ([D46](#d46)).
  - **Team mode**, optional per project and beside direct sessions: a lead bot per piece of work in its own worktree; helper tasks that build; several reviewers, each with a different lens, merged into one verdict; and a landing gate that is a program, not a model. The gate merges, runs the project's checks, reruns a failing check once, and only then fast-forwards.
  - **Self-check.** Before it reports done, a bot looks at what it made: a rendered snapshot of an App or card, a screenshot of a web preview, the diff. From M1 for Apps and previews.
- **Rationale:** Cognitio drives five outside agents today; Ultimate's coordinator, reviewers and landing gate are its working model ([merge assessment §12.5](../research/2026-11-12-memoshi-cognitio-bot-hq-merge.md#125-other-ideas-worth-taking)).
- **Consequences:** `07-coding.md`; roadmap review.

<a id="d111"></a>
### D111. Voice in v1.0: a cloud realtime engine and an on-device engine
- **Status:** Accepted (user's ask-tool choices, 2026-11-13). Moves V2-09 from v2 into v1.0.
- **Choice:**
  - **Shape.** A voice session only listens and speaks. Work is handed to the bot's normal queue as the user's message, so policy, Cards and budgets apply unchanged, and the result is spoken back. One call at a time; a finished call leaves a card with its length and transcript.
  - **Two engines,** chosen per bot or per call: a cloud realtime voice (xAI or OpenAI, on the user's key), where audio leaves the device and the interface says so; and an on-device engine (Apple speech recognition plus an on-device voice) that works offline.
  - **Stages:** the Mac in M2; iPhone and iPad in M3.
  - **With it:** reading a reply aloud and voice memos from bots; on iPhone the Action Button, a Live Activity for the call and a Start Voice Chat App Intent; a voice bot that can open views and reads an answer back before it commits it; and a spoken narrator for background events, off until the user turns it on.
- **Rationale:** bot-hq, Grok Bot 1.0, Ultimate and Pi's p2 all ship voice in this shape; p2's runs entirely on local models.
- **Consequences:** V2-09's target (turn gaps under 500 ms p50 and 1 s p95) applies to the cloud engine; the on-device target is set by measurement. `08-security-and-privacy.md` gains the audio disclosure. Dictation (AP-03) is unchanged.

<a id="d112"></a>
### D112. Search, a connector catalog, app events and media generation
- **Status:** Accepted (user's ask-tool choices, 2026-11-13).
- **Choice:**
  - **Search.** `web_search` (the user picks the provider and key) and `x_search` (xAI key) are typed tools in M1. Results carry their source links, shown as chips.
  - **Connectors.** A built-in catalog over MCP with one-tap connect cards; tokens stay in Keychain by reference. Composio is an optional extra for the long tail, off by default, with a notice that it holds the user's tokens on its servers.
  - **Connector event triggers** (RT-14) move from Phase 3 to M2 on the Mac.
  - **Image and video generation** are tools in M2, on the user's provider key.
- **Rationale:** None of these had a plan row except RT-14; bot-hq, Cognitio and Grok Bot ship them ([merge assessment §5](../research/2026-11-12-memoshi-cognitio-bot-hq-merge.md#5-gap-lists)).
- **Consequences:** New catalog rows; policy tiers for the new tools; roadmap review.

<a id="d113"></a>
### D113. A full computer per bot in v1.0, local or cloud
- **Status:** Accepted (user's direction, 2026-11-13: both a local virtual machine and a cloud computer, chosen per bot, in v1.0). Amends [D16](#d16), [D17](#d17), [D19](#d19), [D47](#d47) and [D87](#d87).
- **Choice:**
  - **Bot computers** (a Linux VM per bot with a desktop and Chromium, live view, takeover, sleep when idle; CMP-06–12, CMP-15–20, BRW-11, BRW-12) move from v1.1 to the end of M2 on the Mac.
  - **Cloud computers** (V2-02) move from v2 to M2, after the local ones and behind the same computer seam.
  - **The user chooses per bot:** This Mac (sandboxed), a Bot computer or a Cloud computer. A cloud computer shows its cost before it starts. A bot keeps its home and browser profile when it moves.
  - **GUI computer use** inside a Bot or Cloud computer arrives with them.
  - **Remote machines** over SSH (CMP-13, CMP-14) and the always-on Mac host move from v1.1 to M3.
  - **Watching and taking over** a bot's browser or computer from iPhone and iPad (BRW-15) moves from Drop 2 to M3.
  - Isolation stays per bot (D16); a shared computer is only ever the user's explicit choice.
- **Rationale:** The user wants each bot to have a computer that can be watched. bot-hq and Grok Bot share one cloud computer between bots with no wall between them, which D16 rejects.
- **Consequences:** O2, O3 and O4 are decided at the start of M2, with the VM spike. VM image sources are published ([D83](#d83)). The cloud provider is chosen by a short comparison; V2-02 named E2B first.

<a id="d114"></a>
### D114. Apps: bots build and extend the app, under policy
- **Status:** Accepted (user's ask-tool choices, 2026-11-13). Amends [D68](#d68), [D71](#d71), [D72](#d72), [D81](#d81) and [D85](#d85), and `../specs/cards.md` §11–§12.
- **Choice:**
  - **An App is a mini app plus four things:** a pane beside the chat (a side-panel tab on Mac and iPad, full screen on iPhone, or inline), in addition to sheet, window and full screen; functions it exports to the bot as a Code Mode namespace; view tools for the bot (`view.open`, `view.close`, `view.arrange`, `view.list`), with layout kept per device; and the user's selection in a pane travelling with the next message, once, behind a removable chip.
  - **Places an App may add to:** a side-panel tab, a row under Apps, a ⌘K command, the look of its own function calls in the transcript, a widget and an App Intent. Never: approval, draft, sign-in or purchase cards, permission sheets, the composer or the title bar.
  - **Rules for bot-written code stay:** sandboxed; a permission list per version that the user approves; policy on every call; exposure labels per value; and a version written after untrusted content needs approval before it first runs.
  - **Developer mode, Mac only, off by default.** A bot may write compiled Swift plugins that run in a separate helper process, never in memoshid or the app. Inside developer mode the user may switch a single App or plugin to **Full access on this Mac** after a confirmation that names the risks; it carries a badge wherever it appears. Neither exists on iPhone or iPad.
  - **Stages.** Page Apps (a sandboxed web view with the same tool bridge and permission list) in M1. Swift Apps in M2 on the Mac and M3 on iPhone and iPad; one can replace a page App and keep its data. The digest of the user's actions (CH-31) moves from Drop 1 to M2.
  - **Scope.** The bot that made it, or all the user's bots by grant (v1.0). Project-scoped Apps live in the project folder behind a trust prompt (M2).
  - **Built-in features** (Mail, Calendar, Tasks, Notes, Contacts, Files and Library) are written against the same contract, so bots can drive and extend them.
  - **Not offered:** changing the signed core at run time. Changing Memoshi itself is coding work on its repository.
- **Rationale:** Pi's p2 and Ultimate show agents writing reusable, hot-reloaded plugins inside their own interface. Both run that code unsandboxed with no approval step; that is taken only as an explicit opt-in on the user's own Mac ([merge assessment §12](../research/2026-11-12-memoshi-cognitio-bot-hq-merge.md#12-malleable-software-pis-p2-ultimate-mail-and-calendar)).
- **Consequences:** Spec review (rule 4): `object-model.md` (whether the binding vocabulary renames Mini app to App is decided there), `cards.md`, `policy.md` §10.7 (App function calls; the developer-mode regime) and `protocol.md`. D72's exclusion of dynamic loading gains the developer-mode exception. `02-experience.md`'s rejection of side-pane placement is reversed. The threat model gains bot-written code beside mail.

<a id="d115"></a>
### D115. Generated interface in three layers
- **Status:** Accepted (user's ask-tool choices, 2026-11-13). Amends [D53](#d53) and [D68](#d68); [D62](#d62) stays superseded.
- **Choice:**
  - **Layer 1:** native cards from the block catalog, aligned with the open A2UI standard and streamed as the model writes. CH-19 moves from Phase 2 to M1.
  - **Layer 2:** bot-written Swift for live cards and Apps, run by Memoshi's interpreter as D68 decided; M2 on the Mac, M3 on iPhone and iPad.
  - **Layer 3:** a sandboxed web page for page Apps, interactive artifacts (TP-07 moves to M1) and screens that connectors provide (MCP Apps).
  - **Native diagrams, charts and math:** Pele_Swift for Mermaid, Swift Charts.
  - **Later design passes:** generated motion and shader effects; native 3D and Gaussian-splat views.
  - A further technique enters when its experiment in the [survey](../research/2026-11-11-generative-ui-sota.md) passes its stated threshold, and is recorded in the scope amendment.
- **Rationale:** The survey ranks catalog-constrained streamed cards first and interpreted Swift second; the user chose all three layers over dropping the interpreter.
- **Consequences:** The survey's first experiments (A-E2, B-E1, A-E4) become M1 work. R51 is unchanged.

<a id="d116"></a>
### D116. Mail, Calendar and personal-information panes
- **Status:** Accepted (user's ask-tool choices, 2026-11-13). Amends CON-08 and AP-10's staging.
- **Choice:**
  - **Mail.** Typed `mail.*` tools (list, thread, search, draft, send, archive, label) over the providers' own interfaces: Gmail, Microsoft 365 and IMAP, several accounts at once. Tokens stay in Keychain by reference and traffic passes the egress gateway. This closes CON-08's open connector question; MCP mail connectors stay possible.
  - **Calendar, Reminders and Contacts** through Apple's frameworks. Those AP-10 tools move from Phase 2 to M1 on the Mac.
  - **Built-in native panes** on D114's contract: Mail, Calendar, Reminders merged with Tasks, Contacts, Notes (Markdown files) and Files with the Library. The Mac in M1; iPhone and iPad in M3.
  - **Sending.** A bot prepares a draft and the user sends it. The user may let a trusted bot send mail by itself; that never applies to a run started by incoming mail or other outside content ([D57](#d57)).
  - All message content carries the untrusted label ([policy.md §6](../specs/policy.md#6-exposure-rule)).
- **Rationale:** Pi's author showed bot-built Mail and Calendar panes on 2026-11-12. Apple offers no interface for reading the Mail store, and Apple Events are excluded ([D41](#d41)) [INFERENCE: platform knowledge, not tested].
- **Consequences:** New catalog rows; `08-security-and-privacy.md` treats mail as the main injection path; `09-platform-macos.md` gains the purpose strings.

<a id="d117"></a>
### D117. Milestones replace the single v1.0 gate
- **Status:** Accepted (user's ask-tool choices, 2026-11-13: usable milestones; nothing deferred; record in this log). Supersedes [D87](#d87)'s calendar, and its stage assignments where D106–D116 move features. Phase 0 and its 2026-11-27 gate are unchanged.
- **Choice:**
  - **M1, Mac:** the Assistant, bots, Apps and personal information. **M2, Mac:** the workbench, teams, voice and bot computers. **M3:** iPhone, iPad and devices, then hardening. v1.0 is M3 passed.
  - **Nothing leaves v1.0.** iSH ([D69](#d69)), Python and notebooks on iPhone and iPad ([D60](#d60)), the iCloud link ([D48](#d48)), video generation and Cloud computers all stay.
  - **Dates are not set here.** A roadmap review (rule 3) sizes M1–M3 and sets their gates. Until it is filed, 2028-11-24 no longer describes v1.0's scope.
  - The scope, by milestone, is in [`AMENDMENT_2026-11-13.md`](AMENDMENT_2026-11-13.md); the smaller items it lists as adopted are accepted with this decision.
  - Drop 1, Drop 2 and v1.1 keep what D106–D116 did not move.
- **Rationale:** The user wants the union of the compared products in v1.0 and chose milestones over cuts. The added scope does not fit 105 plan weeks with one builder ([D45](#d45)) [INFERENCE].
- **Consequences:** Roadmap review: `10-roadmap.md`, `feature-catalog.md` (restaging and new rows), `MASTER_PLAN.md` §11–§12, `risks.md`. Until those are revised, D106–D117 and the amendment win where an older plan doc disagrees.

<a id="d118"></a>
### D118. Tidying a mailbox is its own, lighter class
- **Status:** Accepted (user's ask-tool choice, 2026-11-13). Amends [D116](#d116) and `../specs/policy.md` §3.1 for the built-in mail tools.
- **Choice:**
  - **`mail.organize`** covers reversible changes inside one mailbox: archive and un-archive, mark read or unread, label and un-label, move between folders, star. Its base tier is T3. It asks the first time; a standing rule may then cover it per bot and per mail account for up to 90 days. Every change is audited and can be undone.
  - **Runs started by outside content.** In a run started by an arriving email or other outside content, `mail.organize` runs only under a standing rule the user set for that trigger, and is otherwise denied. [D57](#d57) is unchanged for everything else.
  - **Unchanged:** `mail.send` (send, reply, forward) is T4 and a Draft, except where the user let that bot send mail by itself ([D116](#d116)). Delete, unsubscribe and changes to filters or mail forwarding are T5.
  - **The user's own actions** in the Mail pane are the user's, not a bot's, and never ask.
  - **MCP mail connectors** keep the verb classification of `policy.md` §3.3: archive, label, mark and move stay `connector.write`, T4. The lighter class belongs only to the built-in `mail.*` tools, whose effects Memoshi can verify and undo.
- **Rationale:** Triage at one card per message is unusable, and standing rules never cover T4. These changes are reversible and never leave the mailbox.
- **Consequences:** `policy.md` gains `mail.read` (T3), `mail.stage` (T3), `mail.organize` (T3), `mail.send` (T4) and `mail.destroy` (T5) with test vectors; `08-security-and-privacy.md` follows.

<a id="d119"></a>
### D119. "App" is the word; identifiers stay
- **Status:** Accepted (user's ask-tool choice, 2026-11-13: "App everywhere"). Amends the binding vocabulary ([D4](#d4)) and [D114](#d114)'s open naming question.
- **Choice:**
  - The object the plan called a mini app is an **App** in the interface, the plan and the specs. It covers the built-in ones (Mail, Calendar, Tasks, Notes, Contacts, Files) and the ones bots build. Two kinds are named where it matters: a **page App** (sandboxed web page) and a **Swift App** (run by the Swift engine). "Web mini app" becomes page App.
  - Written with a capital A. "The app" in lower case still means Memoshi itself.
  - **Identifiers do not change:** the `mini_app` tool, the `miniApps.*` protocol methods, the `mini_app.*` events, the `app_` ID prefix, `OpenMiniAppIntent`, `MiniAppEntity` and the Swift types that carry the name.
  - Earlier decisions, research records and gate records keep their original wording.
- **Rationale:** One word that matches the sidebar's Apps section. A bare `App` or `AppEntity` identifier would collide with SwiftUI's `App` and App Intents' `AppEntity`, and the protocol already ships `mini_app` values in its schema.
- **Consequences:** Live plan and spec prose is renamed; `MASTER_PLAN.md` §5 and `object-model.md` carry the definition.

<a id="d120"></a>
### D120. Default providers, all swappable
- **Status:** Accepted (user's ask-tool choices, 2026-11-13). Fills in [D111](#d111), [D112](#d112) and [D113](#d113).
- **Choice:** Each capability is a setting with several built-in providers on the user's own key. A new install starts with:
  - **Web search:** the bot's own model's built-in search when it has one; otherwise Exa. Brave Search, Tavily and Parallel are selectable.
  - **X search:** xAI.
  - **Cloud voice:** xAI realtime voice; OpenAI realtime voice is selectable.
  - **On-device voice:** Apple's speech recognition and system voices, plus an optional downloadable open voice of higher quality.
  - **Image and video generation:** xAI; OpenAI and Google are selectable.
  - **Cloud computer:** E2B; Orgo and Daytona are selectable.
  - A further provider is added when it passes the comparison below.
- **Rationale:** One xAI key covers X search, voice, images and video. E2B pauses with memory, does not bill while paused and has a self-hostable open runtime ([execution environments](../research/agentic-workspace-landscape/landscape/execution-environments.md)). The providers were not benchmarked against each other for this decision.
- **Consequences:** Each default gets a short measured comparison before the phase that ships it, and may change by a note in the gate review. Provider prices and terms are re-read at that point.

<a id="d121"></a>
### D121. Policy classes for the tools D109–D116 add
- **Status:** Accepted for planning (2026-11-13; derived from D109–D118 and `policy.md`'s existing rules under the user's "do what's best" direction). `policy.md` is the normative home; a tier here may be tightened there, never loosened, without a new decision.
- **Choice:**

  | Operation | Class | Base tier | Note |
  |---|---|---|---|
  | `web_search`, `x_search` | `search.web` | T3 | Network beyond the allowlist; results are untrusted content |
  | Mail tools | `mail.*` | per [D118](#d118) | Message content is private data and untrusted |
  | Image and video generation | `media.generate` | T3 | Budgeted like a model call |
  | Cloud voice session | `voice.cloud` | T3 | Audio leaves the device; granted per bot. The on-device engine is T0 |
  | GUI input inside a Bot or Cloud computer | `computer.input` | T2 | Existing class, now in v1.0 |
  | Starting a Cloud computer | `computer.cloud_start` | T3 | Shows a cost preview; charges count against the bot's budget |
  | A bot calling an App's function | `app.call` | T0 | Like `code.run`: every tool call the function makes is classified on its own, inside the App's approved permission list |
  | `view.open`, `view.close`, `view.arrange`, `view.list` | `self.state` | T0 | Changes only what is shown |
  | Bot-to-bot messages | `bot.handoff` | T0 | Existing class; needs the `bot_messaging` grant and obeys the hop cap |
  | Building or loading a plugin in plugin developer mode | `plugin.install` | T5 | Attended only, typed confirmation, Mac only |

  - **Full access on this Mac** is a setting only the user can change, with typed confirmation. No tool, bot, App or plugin can turn it on (`policy.md` §5.2, self-change).
  - **Goals** run under the unattended regime. **Outside coding agents'** calls map to the existing classes ([D11](#d11)).
- **Rationale:** Every doc that mentions these tools needs one agreed tier, and each follows an existing rule: network beyond the allowlist is T3, GUI input is T2, changes to what a bot may do are T5.
- **Consequences:** `policy.md` §3.1, §4, §8, §10.7 and its test vectors; `MASTER_PLAN.md` §10; `08-security-and-privacy.md`.

<a id="d122"></a>
### D122. The estimated calendar after the roadmap review
- **Status:** Accepted as an estimate (user's direction, 2026-11-13: "write best estimates as milestone dates don't matter much"). Fills in [D117](#d117)'s open dates and supersedes [D87](#d87)'s calendar.
- **Choice:**
  - **Phases keep their numbers.** M1 is the gate at the end of Phase 1, M2 at the end of Phase 2 and M3 at the end of Phase 4; v1.0 is M3 passed.
  - **Reading D106–D117.** Where those decisions say "in M1", "in M2" or "in M3", read "in Phase 1", "in Phase 2" and "in Phase 3". "The start of M2" in [D113](#d113) means the start of the Bot computer work in Phase 2. [D114](#d114)'s "developer mode" is written "plugin developer mode" in the plan and specs, to keep it apart from the Guided and Developer interface levels of [D3](#d3).
  - **Sizes:** Phase 0, 5 plan weeks (unchanged); Phase 1, 46; Phase 2, 83; Phase 3, 55; Phase 4, 8: 197 plan weeks to v1.0, where D87 had 105. Drop 1 is 10 weeks and Drop 2 is 9.
  - **Gates:** Phase 0, Fri 2026-11-27 (unchanged); **M1, Fri 2027-10-29**; **M2, Fri 2029-06-29**; Phase 3, Fri 2030-08-02; **M3 and v1.0, Fri 2030-09-27**; Drop 1, Fri 2030-12-06; Drop 2, Fri 2031-02-21. v1.1 starts Mon 2031-02-24.
  - Year-end breaks stay outside plan weeks, as before.
  - Every duration is an [INFERENCE] estimate for one builder with coding agents ([D45](#d45)). The item-by-item sizing is in [`10-roadmap.md`](10-roadmap.md).
- **Rationale:** D106–D121 add about 92 plan weeks to v1.0: about 27 in Phase 1, 48 in Phase 2, 15 in Phase 3 and 2 in Phase 4 [INFERENCE]. Most of what moved in from v1.1 and v2 had never been sized.
- **Consequences:** `10-roadmap.md` carries the calendar; every other document cites it. The cut order in `10-roadmap.md` stays the safety valve. A gate review may re-date a later phase by a note, without a new decision, when measured progress differs from these estimates.


<a id="d123"></a>
### D123. S2 is rerun before the gate relies on it
- **Status:** Accepted (user's ask-tool choice, 2026-11-13).
- **Choice:** The full S2 run (devices, authority, revocation) is repeated on a committed tree with the stricter harness and filed as the new record. Until then the Phase 0 gate record treats two points as unproven: revocation at the claim and link levels, and the expiry two-writer audit.
- **Rationale:** The code review of 2026-11-13 found that in the recorded runs only the relay's refusal was real; the claim and link refusals were the revoked device's own guards, and the 2026-11-03 runs report `audit.expiry.commits: 0`, so that audit checked nothing ([review record](../../../evidence/2026-11-13-memoshi-code-review/README.md)).
- **Consequences:** `risks.md` and `../HANDOFF.md` list the rerun as required before the gate. The filed gate record is not edited; the gate review reads the new record.

<a id="d124"></a>
### D124. The two device holds stay for Phase 0 and get a way out in Phase 1
- **Status:** Accepted (user's ask-tool choices, 2026-11-13).
- **Choice:**
  - **A message sealed for an old group state.** Today a device stops at that state if the group changes before the authority accepts the message. In Phase 1 the device seals the same message again for the new group state under the same operation ID, so it is delivered once and never twice, and retires the old one.
  - **A reservation that is never released.** In Phase 1 two ways out are added: the reserving device may cancel when its own save failed before anything was written, and a removed device's reservation ends together with its leases.
  - Both holds stay exactly as they are through the Phase 0 gate.
- **Rationale:** Both holds keep data safe but can leave a device or a conversation stuck for good. Changing them before the gate would change what S2 measured.
- **Consequences:** Spec review ([change control](#change-control) rule 4) for `../specs/protocol.md` §12 in Phase 1; `10-roadmap.md` and `risks.md` carry the items. The S2 scorecard's wording that excludes rebasing is superseded from Phase 1.

<a id="d125"></a>
### D125. The Mac may use the camera, for the pairing scanner only
- **Status:** Accepted (user's ask-tool choice, 2026-11-13). Amends the "Camera: never requested" line of `09-platform-macos.md` §9.4.
- **Choice:** The Mac app carries the camera entitlement. Its only use is scanning another device's one-time pairing code; macOS still asks the user before first use.
- **Rationale:** The Mac app already ships the scanner and its purpose string, and a signed build cannot open the camera without the entitlement.
- **Consequences:** `09-platform-macos.md` §9.2 and §9.4; the Mac entitlements file.

<a id="d126"></a>
### D126. One licence rule for every dependency
- **Status:** Accepted (user's ask-tool choices, 2026-11-13). Extends DIST-03's licence scan.
- **Choice:**
  - **Rust crates** in the MLS library are held to the same accepted list as Swift packages (MIT, Apache-2.0, BSD, ISC), with two named exceptions: MPL-2.0 for the `uniffi` crates and Unicode-3.0 for the crate that needs it. An unknown or unlisted licence fails the scan.
  - **Python packages shipped with Pyodide** are checked against a reviewed table, one row per package, built from each package's own licence files. A package without a row, or with a licence the table does not accept, fails the scan.
  - **Named exceptions in that table** (user's choice, same day): `numpy` (BSD-3-Clause, with bundled parts under 0BSD, Zlib and CC0-1.0), `pillow` (MIT-CMU), `scipy` (BSD-3-Clause, with Qhull) and `matplotlib` (its own licence, based on the Python licence). `matplotlib` ships fonts without their licence files, so those texts are taken from matplotlib's own source release of the same version and retained in the repository beside the other third-party licence sources. The table names every part the package ships or compiles in, each under its own permissive licence: matplotlib's own licence, the font licences, ColorBrewer, Solarized, Yorick, the CC0-1.0 resize observer, AGG, Qhull and FreeType. They are not in the app bundle yet: bundling them with the Python runtime is a release requirement, and the release check refuses a build without them.
  - **Two parts of `matplotlib` with no licence text in the package or its source release** (user's choice, same day): the `Humor-Sans.ttf` font and the 41 Adobe font-metric (AFM) files stay, and evidence from outside the package is retained for them instead: the SIL Open Font License text and the record that the font is under it, and Adobe's permission notice for its AFM files. Each retained text names its source and digest. A part for which no such evidence can be found is not accepted and comes back to the user.
  - **37 font-metric files accepted without evidence** (user's choice, same day): the search found evidence for Humor Sans (byte-identical to Debian's font, which is under the Open Font License), the 4 Utopia files, Qhull and FreeType. It found none for 37 files in `matplotlib/mpl-data/fonts/afm`: 35 Adobe base-35 files (the package ships the 1988–1992 editions; Adobe's public notice covers the 1997–1999 editions) and 2 Helvetica Light files. The user accepts these 37 files as a named exception, listed file by file with digests, knowing that no permission text was found. They are used only for PostScript output with a printer's built-in fonts. The risk is low but not zero; removing them from the packaged runtime stays the way out if it is ever questioned.
- **Rationale:** Before this, Rust crates were refused only when GPL-family or PolyForm, and the Python packages were not checked at all although the plan said they were.
- **Consequences:** `scripts/` licence tooling and its tests; `04-architecture.md` states what the scan covers.

<a id="d127"></a>
### D127. Two colour fixes for contrast
- **Status:** Accepted (user's ask-tool choices, 2026-11-13).
- **Choice:**
  - **Bot names in their avatar colour** are corrected with the documented contrast-correction method until they meet the declared contrast on every background a name can sit on.
  - **The identity badge** is drawn with the checked pair `accent.onFill` on `accent.fill` (the pair buttons use), as a solid accent capsule.
- **Rationale:** Both missed the contrast the tokens themselves declare (4.6:1, and 7:1 in Increase Contrast). The Phase 1 design pass ([D106](#d106)) may restyle either, inside the same rule.
- **Consequences:** The design-tokens file, its generated code and its checks; `../specs/design-reference.md` §6.

<a id="d128"></a>
### D128. Before a Chat is compacted: a memory flush and summary instructions
- **Status:** Accepted (user's ask-tool choice, 2026-11-13). Settles the disagreement between `04-architecture.md` §4.12 and `05-bots-and-assistant.md` §4.1.
- **Choice:** Memoshi uses the engine's `beforeCompact` hook for two things: a silent memory flush (one short turn in which the bot may only save memories, at most once per compaction, with a 2-minute limit), and summary instructions that keep open commitments with dates, pending cards, active Handoffs, decisions and the user's corrections. What the flush saves follows the normal memory rules: it is evidence, never a standing instruction, and it shows in the memory log. Its cost counts against the bot's budget.
- **Rationale:** A Chat never resets by itself ([D78](#d78)), so compaction is where a bot would otherwise lose commitments and facts.
- **Consequences:** `04-architecture.md` §4.12 follows `05-bots-and-assistant.md` §4.1. The tree-shaped summary of `NEXT_VERSION.md` §5 stays an experiment, not the baseline.

<a id="d129"></a>
### D129. Permission texts for Calendar, Reminders, Contacts and the microphone
- **Status:** Accepted (user's ask-tool choice, 2026-11-13). The Phase 1 design review may polish the wording.
- **Choice:**
  - **Calendar:** "Memoshi shows your calendar in its Calendar pane. Bots you allow can read your events and add or change them."
  - **Reminders:** "Memoshi shows your reminders with its tasks. Bots you allow can read your reminders and add or change them."
  - **Contacts:** "Memoshi shows your contacts in its Contacts pane. Bots you allow can look people up and add or change contacts."
  - **Microphone, from Phase 2:** "Memoshi uses the microphone while you dictate or talk with a bot. Dictation and on-device calls stay on this Mac. A call on a cloud voice sends audio to the provider you chose."
- **Consequences:** `09-platform-macos.md` §9.3 carries them as the planned wording.

<a id="d130"></a>
### D130. Smaller points settled after the code review
- **Status:** Accepted (user's ask-tool choices, 2026-11-13).
- **Choice:**
  - **Daemon socket fallback.** When the data root is too long for a socket path, the socket goes in the user's private temporary folder, not in `/tmp/memoshi-<uid>`, so another account on the Mac cannot block start-up.
  - **Host-call slots.** When a cancelled handler ends, the app answers `canceled`, and the daemon keeps that slot until then. A ninth request can no longer end the connection.
  - **Error retry flag.** The schema states the per-kind `retryable` value; the decoder stays tolerant and always reports the kind's value.
  - **`trash.emptied`.** Its `by` is `user` or `system`, like `session.purged`.
  - **Mac app.** After a timeout or a daemon error while it applies an event, the app reloads by itself once before it shows Reconnect.
  - **Discarding.** A saved request that the engine keeps refusing, and a refused model-key setup, can be discarded by the user after a confirmation.
  - **iPhone.** A turn that waits for the user's approval does not count as stalled: the background task completes while it waits and starts again when the turn runs. If a first enrollment fails, the half-made identity is removed.
  - **Empty Trash** purges everything in Trash in one request, in batches, as the spec says.
  - **Values confirmed:** egress gateway: 64 connections per client, 60 s for a request head, one name lookup at a time per client, the newest 4,096 decisions kept for display, 10 s to close an upstream its client left; "try again after" hint 1 s; the Mac app waits up to 120 s for its helper; 10 s for the last handshake frame on a direct device link; a release waits up to 45 minutes, checking every 60 s, for TestFlight to confirm an upload, inside a 285-minute job limit.
  - **Moved to Phase 1 as open items,** each needing a designed rule: a log identity in the daemon's hello to detect a restored history; retiring old de-duplication history in the CloudKit transport; a deadline for the last handshake frame on the relay route; localization tables for the app package; a reset for the browser lab's cookie probe.
- **Rationale:** Each closes a finding of the code review of 2026-11-13 where the fix needed the user's choice.
- **Consequences:** `../specs/protocol.md` and `../specs/events.md` for the first four; the code; `10-roadmap.md` for the Phase 1 items.

<a id="d131"></a>
### D131. The remaining open items are done now, before the S2 rerun
- **Status:** Accepted (user's instruction, 2026-11-13: "let's do all these as well and finish all").
- **Choice:**
  - **Timing.** The ways out of the two device holds ([D124](#d124)) and the five items [D130](#d130) moved to Phase 1 are built now. This supersedes D124's "both holds stay exactly as they are through the Phase 0 gate" and D130's "moved to Phase 1". They are fixes to existing behaviour, not new product features, so the rule that no product feature starts before the Phase 0 gate still holds.
  - **Order.** Code, independent review, the full check, a commit; then the canonical CI run and the full S2 rerun ([D123](#d123)) on that commit; then the push. S2 is rerun after the device changes so that the new record measures the code as it now is.
  - **The rules** [INFERENCE: engineering rules chosen to carry out the instruction]:
    - **Host-call deadline.** When the app's own 10-second deadline for a host call passes, the app cancels the handler and answers `timeout` when the handler has ended, as it already does for `canceled`. The slot stays taken until then.
    - **A message sealed for an old group state** is retired with its plaintext held and sealed again for the new state under the same operation ID, as D124 describes, on the direct, relay and CloudKit routes. A receiver refuses a message numbered above a closed state's cutoff, so it can never apply both. The last pairing message is the exception: if the group changed before it was sent, the pairing is refused and started again.
    - **A reservation that is never released** ends in the two ways D124 describes. The writer may cancel when its own store refused the write, and also when it never saw the grant and so wrote nothing; the authority refuses a cancel once a write under that reservation is recorded.
    - **Restored history.** The daemon's hello carries an identity of its event log. A client that sees another identity drops its cursor and reloads. Because a copy restored from a backup keeps its identity, a client that resumes also states the time of the last event it applied, and the daemon refuses the cursor when its own event at that position has another time, or when it no longer keeps that event and so cannot check. A refused cursor costs one reload.
    - **Old de-duplication history** in the CloudKit transport is retired only below saved marks under which every message is refused anyway, so a retired entry can never let a replay in. New message IDs are always minted above the mark, so a clock set back cannot block sending.
    - **Relay-route handshake.** The 10-second limit for the last handshake frame counts from the first handshake frame on both routes, not from when the listener starts.
    - **Localization tables.** The app package's AppCore, ConversationFeature and ShellFeature modules get their own String Catalogs.
    - **Cookie probe.** The browser lab gets an explicit reset with a confirmation. A reset first reads and records the generation it ends, then starts a new numbered one, and every verdict names its generation, so a reset cannot pass for a clean result or hide a loss.
    - **A refused Send's explanation** stays visible on iPhone and iPad next to any later problem.
- **Rationale:** The user wants no open ends left from the code review. Doing the device changes before the S2 rerun avoids measuring code that is about to change.
- **Consequences:** `../specs/protocol.md` (hello, replay, host calls, §12); `10-roadmap.md`, `risks.md`, `NEXT_VERSION.md` and `../HANDOFF.md` drop these as open Phase 1 items. The S2 scorecard's wording that excludes rebasing is superseded now, not from Phase 1.

<a id="d132"></a>
### D132. Pairing messages may span several encrypted messages; a device group holds at most 64 devices
- **Status:** Accepted (engineering fix under the user's instruction of 2026-11-13 to finish the open items; found by the full S2 run).
- **Choice:**
  - A pairing message that does not fit one encrypted message is sent in several, with its total length authenticated in the first piece and a total of at most 256 KiB. A message that fits one encrypted message is sent exactly as before.
  - A device group holds at most 64 devices, which is the limit of the MLS library as built. The 65th device is refused with a clear reason before anything is changed.
  - [INFERENCE: the 256 KiB bound; a full group's welcome is about 94 KB.]
- **Rationale:** The full S2 run on commit `67e750d` paired 43 devices and then refused every further one: the welcome message grows by about 1.4 KB per device and had outgrown one encrypted message (65,535 bytes). The limit came in on 2026-11-07 with the real MLS welcome and went unseen because every S2 run since then used the quick mode with five test devices ([record](../../../evidence/2026-11-13-memoshi-canonical-s2/s2-full-01/README.md)).
- **Consequences:** `../specs/protocol.md` §12.2 and §12.3. The S2 run is repeated on the commit that holds the fix ([D123](#d123)).

<a id="d133"></a>
### D133. Device groups are qualified at 8 devices; the limits of the 2026-11-13 runs are closed where this Mac allows
- **Status:** Accepted (user's answer of 2026-11-13 to the proposal: "yes do all that you can do and lets finish all").
- **Choice:**
  - **Group size.** Hand-over and lease targets are measured and set with 8 devices in the group, which covers one person's devices with room to spare. A run with about 54 devices stays as a stress test. The limit of 64 devices ([D132](#d132)) is unchanged.
  - **Group state.** A device saves its group state as a journal that is compacted from time to time, not as a full rewrite for every message. Forward secrecy is kept: a change that replaces an epoch's secrets is always written as a full compaction, so replaced secrets leave the disk when the call returns, as before; per-message key material that a consumed message deletes stays on disk for at most 64 further change rows. A file with change rows cannot be opened by the older code; there is no downgrade path.
  - **Revocation proof.** S2 puts a revoked device's claim to the authority itself, and the revoked device holds a lease before it is revoked, so that "no grant afterwards" proves something.
  - **A full group** refuses to issue a pairing code, so no code is used up and the user sees the reason.
  - **A removed device** learns of its removal from proof it can check, also on the relay route, and then drops what it held. It is shown only the group's membership changes, never the message feed: after revocation the relay gives it no application message, not even one from an epoch in which it was still a member, and it checks the changes on a copy of its group state. Once its removal is verified it deletes everything it received through the group, not only the messages it held to resend: its group keys and its own signing key in the group, the message history, the conversation replicas and the approvals. The app says so. A device that was only signed out of the relay, and not removed from the group, keeps its data.
  - **App code.** The logic changed this week in the Mac and iOS app targets moves into the app package, where tests run.
  - **Python licence texts** are bundled with the Python runtime.
  - [INFERENCE: the figure 8; the journal as the way to cut the cost.]
- **Rationale:** These close the limits reported after the canonical CI and S2 runs of 2026-11-13, as far as they can be closed without signed apps, physical devices or Apple's servers.
- **Consequences:** `../specs/protocol.md` §12 where the wire changes; `../HANDOFF.md`; the S2 run is repeated on the commit that holds the changes.

<a id="d134"></a>
### D134. Memoshi moves its Pi_Swift pin to the `slice-2` release
- **Status:** Accepted (user's instruction, 2026-11-14).
- **Choice:**
  - Memoshi's Pi_Swift dependency moves from the development candidate `892585fc8d8be3093b58c34aacffcd4e68c3a8d9` to the annotated tag `slice-2` (commit `ce1728ef8236d95a8b94b50a856670c48ad85365`, 2026-11-12), the release Pi_Swift qualified for Memoshi's gate. Later commits on Pi_Swift's `main` are not taken.
  - Memoshi follows Pi_Swift's consumer notes for `slice-1` and `slice-2` and the [adoption plan](../research/spikes/2026-11-07-pi-swift-adoption-plan.md). Where the new engine offers a call Memoshi was waiting for, such as settling an interrupted step (Run again, Skip, Mark as done; Pi_Swift requirement E20), Memoshi uses it in its existing surfaces; no new product feature is enabled before the Phase 0 gate.
  - From this pin on, S1 results count for the gate as the plan requires ([D90](#d90)); results recorded on the old candidate stay development evidence.
  - **How the pin is held.** SwiftPM refuses an exact-revision dependency on `slice-2`, because that commit adds a local package (`Vendor/SwiftBashParser`) and SwiftPM allows local dependencies only for branch or path requirements. Memoshi therefore depends by path on a clean clone `../Pi_Swift-slice-2` at exactly that commit; `scripts/check-prerequisites.sh` creates it from the sibling `../Pi_Swift` and refuses to build unless its HEAD is that commit, its tree is clean and the `slice-2` tag points at it. The pin no longer appears in the `Package.resolved` files. A later Pi_Swift tag that folds that package into its root package would let Memoshi return to a revision pin; the request is passed to the Pi_Swift project.
- **Rationale:** Pi_Swift published `slice-1` and `slice-2` on 2026-11-12, so the release holds that kept Memoshi on the candidate no longer apply. The pin move gives the gate a qualified engine and the step settlement that the Mac and iPhone recovery surfaces lack.
- **Consequences:** `Packages/MemoshiCore/Package.swift` and every `Package.resolved`, `NOTICE`, `README.md`, `../HANDOFF.md`, `10-roadmap.md`, `risks.md` and the spike report drafts; the canonical CI run and the full S2 run are repeated on the commit that holds the move.

<a id="d135"></a>
### D135. The new-tab preconnect is accepted as a reported limit until bots browse in their own computers
- **Status:** Accepted (user's choice, 2026-11-14: "do what's best"). Extends [D101](#d101); answers option A and D of the [S3 filter study](../research/2026-11-14-s3-network-extension-filter-study.md).
- **Choice:**
  - A `target=_blank` link makes WebKit open one empty connection to the link's host before Memoshi's navigation policy is asked. No request, cookie or page data is sent. Memoshi keeps the D101 gateway route, reports the gap to Apple and WebKit with a minimal reproduction, and records it in the S3 report and the gate review as a named exception, not a pass.
  - The gap is closed fully when bots browse only inside their own Bot computers (virtual machines, [D113](#d113)), the industry's isolation model; until then bot browsing on This Mac carries this limit.
  - A macOS network filter (options B and C of the study) is not built now: it needs the signing work that is still open, a system extension the user must approve, and an exception to 08 §15's "no privileged helper"; it can be reconsidered if the upstream reports stay unanswered when Bot computers are planned.
- **Rationale:** the residual is a connection without payload to a host the page already named; the filter would add a privileged component, two approvals and signing work to close it, while VM isolation closes it as part of planned work.
- **Consequences:** the S3 report and the gate review name the exception; `phase-0-review-draft.md` lists the upstream report numbers once filed.

<a id="d136"></a>
### D136. A signed-in bot opens other sites in a separate, empty profile
- **Status:** Accepted (user's choice, 2026-11-14). Amends the cross-origin refusal recorded in the S3 runs of 2026-11-14 and works with [D101](#d101) and the synced browser sessions of [D75](#d75).
- **Choice:**
  - When a bot whose browser profile holds cookies for a site follows a link or is told to open another site, Memoshi opens that site in a separate, throwaway profile with no cookies or storage, and discards it when the task ends. The signed-in profile never sends its cookies to another site. This follows the per-site storage partitioning of Firefox's Total Cookie Protection and Safari.
  - The same gateway route, deny-local rules and Lockdown Mode apply to the throwaway profile.
  - Nothing moves between the two profiles except what the bot itself carries in its task (no cookie, storage or cache).
- **Rationale:** the old rule refused every cross-site move once any cookie existed: safe but too limiting for real tasks; a separate profile keeps the login from travelling without blocking the move.
- **Consequences:** the bot browser broker and its S3 controls change before the real-site browser test set runs.

<a id="d137"></a>
### D137. Two accepted limits of private Mac copies, with a warning for files still open
- **Status:** Accepted (user's choices, 2026-11-14). Amends [D96](#d96).
- **Choice:**
  - **Hardlinks.** A file that already has a second name on disk can be changed through that other name. D96's admission already refuses multiply-linked inputs, so such a file never enters a private copy; this is recorded as a limit, not a fail.
  - **Files still open.** A program that keeps a file open can write to it after Memoshi exported it, and those writes can be lost; macOS offers no way to stop this. Accepted as a limit. Before an export, Memoshi checks whether any process still has the file open for writing, waits briefly, and if one still does, says so on the export card. The warning is best effort, not a guarantee.
- **Rationale:** both cases sit below what macOS lets an unprivileged app control; refusing them would block normal work, and the warning tells the user when a loss is possible.
- **Consequences:** the S4 report counts these two cases as accepted limits; the export path gains the open-writer check and its card text.

<a id="d138"></a>
### D138. Which choices an interrupted step offers
- **Status:** Accepted (user's confirmation, 2026-11-14). Refines [D51](#d51) for the settlement built on Pi_Swift `slice-2` ([D134](#d134)).
- **Choice:**
  - A step the user stopped offers only **Skip** and **Mark as done**, never **Run again**: the user ended it on purpose, and the model can call the tool again itself if it should.
  - An export of a private working copy ([D96](#d96)) never offers **Run again**, whether or not its export record exists; a repeated export could overwrite the user's files twice.
  - Other interrupted steps offer all three choices under D51's rules.
- **Rationale:** Run again is the only choice that can repeat an effect; it is offered only where repeating is what the user would expect.
- **Consequences:** the Resume card and the Mac and iPhone recovery text show only the offered choices.

<a id="d139"></a>
### D139. Closing the app keeps work; approval outcomes and Python starts
- **Status:** Accepted (user's choices, 2026-11-20). Applies [`04-architecture.md` §2.3](04-architecture.md), [`policy.md` §10.1](../specs/policy.md) and [D27](#d27) to the development build's app-owned helper; records the round-2 open items of the [2026-11-20 app tests](../HANDOFF.md#fixes-2026-11-20-round2).
- **Choice:**
  - A graceful close (Quit of the app-owned helper, `system.shutdown`, `InProcessEngine.close`) stops no work. A reply that is streaming continues after the next start, as in the product, where ⌘Q leaves memoshid working: Pi regenerates it and it is marked "Interrupted · continued after a restart". Stop stays the way to end a reply.
  - A pending approval survives a close for every conversation, a foreground subagent's included; the child and its parent continue after the next start. Only a user Stop, the kill switch, a revoked grant or expiry ends one.
  - The model gets a separate result for each approval outcome. Denied: "The user denied the call; nothing was done." Expired: "The user did not answer in time; nothing was done." (policy.md §10.1). Canceled: "The approval was canceled before an answer; nothing was done."
  - `python_run`'s interpreter keeps its 120 s start limit; Stop ends a start at once. The real limit is set from the S6 physical-device start times.
  - The transcript shows a turn's end state (Stopped, or Interrupted · continued) after the turn's Cards, and a turn whose only reply called a tool gets no empty bubble. Placing each Card at its tool call within the reply is left to the Phase 1 transcript design.
- **Rationale:** the same close should not keep one kind of work and drop another; the spec already keeps work across a quit, and a crash already did. Distinct outcomes let the model react correctly (no retry after a denial; offer to ask again after an expiry). A shorter start limit would turn slow starts into failures before any device numbers exist.
- **Consequences:** a close can cost a second generation on relaunch (paid tokens on a cloud model). The close tests and the stopped-reply tests cover the regenerated reply, the child's resume, the three texts, Stop during a Python start and the new transcript order.

<a id="d140"></a>
### D140. Phase 0 gate line: Pi_Swift `slice-2.2`, Code Mode `wasm2c`, cuts and durability
- **Status:** Accepted (owner decisions, 2026-11-21). Supersedes [D134](#d134)'s `slice-2` pin; records decisions 13, 14, 17, 24, 25, 26, 27 and Pi store durability from [remaining-work.md §1.1](remaining-work.md#11-owner-decisions).
- **Choice:**
  - **Pi_Swift pin (decision 24):** move Memoshi's pin from `slice-2` (`ce1728ef`) to `slice-2.2` (`56d6fc89ebb039ad1b5e9128c8b12131d92d0cbe`), which includes `slice-2.1`'s `HarnessToolsTests` ordering fix and the iOS private-container check fix.
  - **Code Mode backend (decision 25):** drop Memoshi's custom QuickJS WasmKit loader (`wasmLoader: loadQuickJSWasm()`) so `CodemodeSandbox` uses Pi_Swift's `wasm2c` default; drop WasmKit as a shipping fallback. Keep bounded per-VM linear memory (256 MB on Mac; tighter iOS cap matching Pi_Swift's passing iPhone/iPad runs).
  - **D46 per platform, Code Mode measurement date and Phase 0 cuts (decisions 14, 17):** record D46 per platform (macOS: `memoshid` daemon; iOS/iPadOS: in-process engine). Set the Code Mode Release measurement date before Fri 2026-11-27. Apply the Phase 0 cut list: **Cut 1** (defer S6 Pyodide gate sign-off to W52), **Cut 2** (S3 breadth: gate on the owned no-bypass control and Lockdown suite, defer the 20-site live corpus), and **Cut 3** (S2 breadth: gate on local/CloudKit/relay smoke once signing lands, defer multi-relay load). Existing S6, S3 and S2 code and CI tests remain in tree.
  - **S1 approval criterion (decision 13):** read S1's approval criterion per approval (19/19 = 100%, 0 unauthorized executions), noting the 10/10 follow-up batch.
  - **Per-API freeze list (decision 26):** freeze the `PiDurable`, `PiAI`, `PiCore`, `Chord`, `PiCodeMode`, `PiMCP`, and `PiEnv` surface Memoshi imports at `slice-2.2`. Explicitly retain `taskGraph` (`watchTaskGraph()` / `CommittedWatch<TaskGraph>`); `documentState` and `viewState` are unused by Memoshi and need not be held back.
  - **E9b and E28 at the gate (decision 27):** accept E9b (TLS 1.2 PSK without forward secrecy on the local/ephemeral link, where MLS provides end-to-end forward secrecy above it) and E28 (no host identity when bypassing `BotRuntime`, which Memoshi never bypasses) as documented Phase 0 gate bounds, tracked for v1.0 hardening.
  - **Pi store durability (ADR-0001 / P04-11):** use `.processKill` (WAL + `synchronous = NORMAL`) as the default.
- **Rationale:** `slice-2.2` and `wasm2c` clear S1.17's last intermittent failure and S1's Code Mode failure with zero breaking changes; applying Cuts 1–3 lets Phase 0 close on schedule so Phase 1 Mac daily-app work can begin without waiting on secondary hardware/corpora.
- **Consequences:** `scripts/lib/pi-swift-pin.sh`, `Packages/MemoshiCore/Package.swift`, `RuntimeConfiguration.swift`, `scripts/check-signin-flows.sh` and `scripts/release-gates.json` move to `slice-2.2`; `RuntimeExtensionSession.swift` omits `wasmLoader`; `scripts/ci.sh` verifies the new pin and `wasm2c` path.

<a id="d141"></a>
### D141. Phase 0 protocol, runtime, sandbox and review settlements
- **Status:** Accepted (owner decisions, 2026-11-21). Records decisions 1–12, 15 and 16 from [remaining-work.md §1.1](remaining-work.md#11-owner-decisions); narrows [D138](#d138), extends [D133](#d133), amends [D77](#d77) and [D96](#d96), and replaces part of [D131](#d131).
- **Choice:**
  - **1–2 (Resume "Run again"):** withhold "Run again" after an unknown returned outcome (narrows D138); "Run again" requires a fresh approval under current policy (D51/D52).
  - **3–4 (Device pairing & transport store):** once the add is accepted, the inviter reports success with completion pending (replaces part of D131); the device transport store lives at `<zone>/transport` and is erased on device removal (extends D133).
  - **5, 10, 15 (This Mac sandbox):** use one host-launched `sandbox-exec` per command (amends D77, D96); keep `.git/config` and `.git/hooks` unwritable so `git init`/`git clone` fail inside the sandbox as an intended host-exec boundary (D103); accept multi-file non-atomic exports and the documented denial-attribution limits with D77.
  - **6–9 (Runtime & S1):** keep `qwen3:8b` as the local S1 kill-batch model; keep E21 discovery globals reading declared metadata only for Phase 0 (no Pi_Swift R5 hook required); reads that commit events do not wait for those commits; emit no `tool.interrupted` for Memoshi's not-dispatched settlement.
  - **11, 12, 16 (Re-pairing, review & O10):** defer re-pairing a removed device as a new device to Phase 3; accept the 2026-11-18 deep review as satisfying the owed review of `cd440c4..a2ac274`; adopt S2's current implemented lease/renewal/hand-over values as provisional Phase 0 O10 targets, to be refined with live multi-device telemetry in Phase 3.
- **Rationale:** Every item matches already-tested behavior and preserves Memoshi's safety boundaries without adding Phase 0 churn.
- **Consequences:** No code rollback is needed for items 1–12, 15 or 16; O10 carries provisional Phase 0 targets into Phase 3.

<a id="d142"></a>
### D142. Phase 0 UI, LaunchAgent wait, browser lab and decision cross-reference
- **Status:** Accepted (owner decisions, 2026-11-21). Records decisions 18–23, `setsid` reaping, `python_run` chat visibility and the D124/D130 pointer to D131 from [remaining-work.md §1.1](remaining-work.md#11-owner-decisions).
- **Choice:**
  - **18, 23 (iOS Development Review & landscape layout):** gate the iOS Development Review menu row to `#if DEBUG` before any build leaves the owner's devices; defer iPhone landscape-with-keyboard layout rework to Phase 3.
  - **19 (LaunchAgent wait):** keep the 3 s wait for a kickstarted LaunchAgent daemon; D130's 120 s wait applies only to the app's own spawned helper.
  - **20 (Lab browser separate profile):** keep today's triggers for ending a lab separate profile (typed address, lab page, revoke/re-authorize, session close) and document them in the S3 report.
  - **21–22 (iPhone header pill):** keep the header pill's text-size cap with Large Content Viewer and keep `text.secondary` for "Engine on this device".
  - **Detached `setsid` sandbox children:** do not add a polling-based partial reaper; full process isolation belongs in Phase 2 Bot computers.
  - **`python_run` output in Chat:** keep tool output model-only for Phase 0; defer native Python result cards and post-execution Card status copy to Phase 1/3.
  - **Cross-reference:** note that [D124](#d124) and [D130](#d130) are extended and updated by [D131](#d131).
- **Rationale:** Keeps Release/TestFlight builds clean of development menus while deferring mobile product-UI polish and VM-level process isolation to their planned phases.
- **Consequences:** `apps/ios/MemoshiMobile/MemoshiMobileApp.swift` wraps the Development Review row and sheet in `#if DEBUG`.

<a id="d143"></a>
### D143. Phase 0 gate decision: Go to Phase 1
- **Status:** Accepted (owner gate decision, 2026-11-21, commit `0c94dea`).
- **Choice:** Approve **Go** at the Phase 0 gate and enter **Phase 1 (Mac Product)** under the Cuts 1–3 and platform scope recorded in [D140](#d140)–[D142](#d142), backed by the following verified receipts:
  - **P0-16 & S5 distribution (both platforms):** Developer ID Application (G2 Sub-CA, Team `476T8NQCSX`, valid through `2027-12-21`), iCloud container `iCloud.com.mehmetcanbudak.memoshi`, three explicit App IDs, three validated provisioning profiles (`0c12ddce…`, `e6c4ad32…`, `d5596602…`), App Store Connect app record `6837721953` + App Manager API key, notarized & stapled `Memoshi.dmg` (74.6 MB; Gatekeeper `spctl` + `check-dmg` passed; initial baseline committed in `scripts/release-size-baseline.json`), and internal-only TestFlight build `0.0.1 (1)` (`bbe48a99-1102-42dd-bd7f-8f278ff9bc54`, `IN_BETA_TESTING`, valid through `2027-02-19`).
  - **Physical-hardware verification:** notarized `Memoshi.app` launched on the owner's Mac with zero Gatekeeper warnings, authenticated `memoshid 0.0.1-phase0.1 (1)` (`Protocol 1`, `ready`), and streamed a live local-model reply; TestFlight build `0.0.1 (1)` installed and launched cleanly on the owner's physical iPhone and iPad with the dark `AppIcon`, in-process engine running, and `Development Review` absent in Release (D142).
  - **S1 Runtime & Code Mode (`slice-2.2` + `wasm2c`):** 18/18 `scripts/ci.sh` on `slice-2.2` (`d5178eb`, 1,575 Swift Testing + 111 tooling + 81 spike tests + Mac/iOS app tests); S1.17 `scripts/test-contracts.sh` in 229 s wall (< 300 s bar) with `HarnessToolsTests` green; real-model `codemode-nested` kill batch 5/5 pass on `qwen3:8b` (`d3aac18`, 0 duplicates); `CodeModeWorkload --backend wasm2c` Release 50/50 pass across W1, W2, W3a, W3b, W3c (W1 cold/warm p95 40.44 / 36.27 ms, peak 6.36 MB; W2 cold/warm p95 102.51 / 103.05 ms, peak 9.45 MB; W3a/W3b stop settled ≤ 190.17 ms; W3c OOM survived cleanly).
  - **S2 Devices & Replay:** signed event-replay 17/17 pass (1,000 cycles, head 1,997, 0 gaps/duplicates); full S2 qualification (`scripts/run-s2-full-v2.py`, `s2 --load --real-expiry`) passed exit 0 on clean `0c94dea` (946.5 s wall, quiet load 5.86 → 4.30) with `verify_s2_samples.py` `verified: true` (72 distributions, 48 raw CSVs, 12 workers; `scaled-mix-idle-renewed` 12,000 convs / 600 devices / 3,411 ops/s at claims p95 11.78 ms, moves p95 70.58 ms, renewals p95 4.28 ms, RSS 42.9 MB).
- **Explicit carry-forwards (not waived; tracked into Phase 1 / Phase 3):**
  - Owner housekeeping: rotate `BRAVE_API_KEY` and `GEMINI_API_KEY`; file the two Apple/WebKit Feedback reports (D135 `_blank` preconnect; macOS 27.0.1 `willSubmitForm`).
  - Hardware/service evidence deferred by Cuts 1–3 or Phase 1/3 scope: clean macOS 27 VM / 16 GB M1 reference-box pass/fail series; production `SMAppService` background LaunchAgent persistence (enabled in Phase 1); live multi-device CloudKit + relay pairing smoke and O11 hosted relay deployment; S6 Pyodide on physical iOS (Cut 1, W52); S3 external 20-task/5-site corpus (Cut 2).
- **Rationale:** Every foundational contract, runtime/Code Mode path, S2 load profile, and real Apple signing/notarization/TestFlight ship path is now proven end-to-end on `slice-2.2`. Remaining items are cleanly bounded Phase 1/3 deliverables or owner housekeeping and do not block Phase 1 Mac product engineering.
- **Consequences:** Phase 0 closes on `0c94dea`; Phase 1 (Mac Product, M1) is now open.

<a id="d144"></a>
### D144. Viticci's November 2026 design leads the shell first; Cognitio borrowed selectively later
- **Status:** Accepted (owner direction, 2026-11-21). Amends [D106](#d106)'s shell-lead order; keeps [D106](#d106)'s own-code/licensing boundary and [D107](#d107).
- **Choice:**
  - **Lead first:** Viticci's November 2026 macOS and iOS/iPadOS design — anchored by the 20 Nov macOS capture (`HXlzoVyXYAAaqV5.png`, [2123856109043929439](https://x.com/viticci/status/2123856109043929439)), the 19 Nov transcript close-up (`HXgvBUIXYAE2lcT.jpg`, [2123498930206089381](https://x.com/viticci/status/2123498930206089381)), and the 13 Nov iPhone Duo capture (`HXBwE66X0AAqvU6.png`, [2121318820132643152](https://x.com/viticci/status/2121318820132643152)) — leads the Phase 1 macOS shell and subsequent iPad/iPhone shell.
  - **Cognitio later:** Once the Viticci-led shell is built and running on real Memoshi state, selectively inspect and borrow desired workbench/power-user patterns from Cognitio without adopting Cognitio's full chrome upfront.
  - **Own code & original brand:** Match the layout, visual craft, warm ivory/amber surface hierarchy, and interaction grammar in Memoshi's own SwiftUI code, tokens, brand, and original avatars. No third-party source file, asset, or string enters this repository.
- **Rationale:** Memoshi already has a Warm-palette Viticci preview foundation (`design-preview-2026-11-13`), and Viticci's November 2026 captures show a mature, cohesive macOS + iOS/iPadOS assistant shell. Building to that target first gets Phase 1 to a daily-driver Mac app faster while keeping Cognitio available for selective later additions.
- **Consequences:** [design-reference.md](../specs/design-reference.md) is updated with the D144 surface-by-surface spec for the November 2026 captures; Phase 1 Mac UI work targets that spec first.

---

<a id="mapping-from-draft-3"></a>
## Mapping from Draft 3

| Draft 3 | Topic | Now | Outcome |
|---|---|---|---|
| D1 | Design base: Kuvo | D29, D43, D91, D92, D106 | D92 replaced blanket Kuvo parity with a Viticci-led assistant family and Kuvo-informed workbench; D106 (2026-11-13) makes Cognitio's design the lead on every device, rebuilt in Memoshi's own code, and leaves D91's permitted reuse unused for the interface |
| D2 | Runtime: pi-durable | D6, D44 | Kept, then changed by D44 (2026-10-22): Pi_Swift |
| D3 | SwiftUI + AppKit | D31 | Kept |
| D4 | Projects lead | D2 | Superseded: Assistant-led |
| D5 | Per-agent computer | D16 | Kept and extended |
| D6 | Local + SSH in v1 | D16, D17, D39, D47, D113 | Superseded: Bot computer VMs in v1, cloud in v2; D47 (2026-10-22) moved VMs and SSH to v1.1; D113 (2026-11-13) brings Bot computers and Cloud computers into v1.0 in Phase 2 and Remote machines in Phase 3 |
| D7 | SQLite | D14 | Kept |
| D8 | macOS 27+ | D31 | Kept |
| D9 | v1 = build loop + team | D5 | Superseded |
| D10 | Mobile in v2 | D38, D47 | Superseded: v1.1, then v1 by D47 (2026-10-22) |
| D11 | Open core | D33 | Kept |
| D12 | Name | D34 | Kept |
| D13 | Full builder spectrum | D3 | Kept |
| D14 | Hosted cloud in v3 | D39 | Superseded: v2 |
| D15 | 3 engineers + design | D35, D45, D93 | One builder with coding agents; D93 removes mandatory contracted design help while retaining design QA |
| D16 | Open-source boundary | D33 | Kept |
| D17 | Provider-agnostic models | D10 | Kept, with the subscription-auth rules |
| D18 | Sidecar-enforced approvals | D9, D27 | Kept |
| D19 | One app, one sidecar | D12, D46, D58 | Superseded: app plus LaunchAgent daemon, a Swift app-shaped helper since D46 and D58 (2026-10-22) |
| D20 | Web only for preview/artifacts | D29, D114, D115 | Kept, extended to inline widgets, browsing, page Apps and the screens connectors provide |
| D21 | RuntimeAdapter | D6 | Kept |
| D22 | FTS5 memory | D22 | Kept |
| D23 | Tokens from Kuvo audit | D43, D91, D92, D106 | Verified references inform Memoshi's semantic tokens; no automatic adoption of Kuvo values, and unknown Draft 3 measurements remain provisional; since D106 the shell reuses Memoshi's own tokens where they fit Cognitio's layout |
| D24 | Direct download | D32 | Kept (now Accepted) |
| D25 | Pricing TBD | D40 | Still open |
| D26 | Guided / Developer | D3 | Kept |
| D27 | Apple platform leverage | D41 | Kept |

---

## Open decisions

| # | Question | Recommended default | Decide by |
|---|---|---|---|
| O1 | Business model and pricing | [D40](#d40) default | Before a public release (O13; was "before beta" until [D67](#d67)) |
| O2 | Bot computer engine: direct Virtualization.framework, Containerization, or Gondolin | Direct Virtualization.framework ([D17](#d17)) | Start of the Bot computer work in Phase 2, with the VM spike ([D113](#d113)); was the start of v1.1 ([D47](#d47)) |
| O3 | Split native capabilities into a helper process | No for v1 unless crash data says otherwise. VM tool calls cross the app, so an app crash interrupts VM work ([D12](#d12)) | Start of the Bot computer work in Phase 2, with the VM spike ([D113](#d113)); was the start of v1.1 ([D47](#d47)) |
| O4 | Awake VM cap and default VM size | Standard VM 2 vCPU / 4 GB. Awake cap by installed RAM: 0 on 8 GB Macs (one compact VM by opt-in), 1 at 16 GB, 2 at 24 GB, 3 at 32–36 GB, 4 at 48 GB, 6 at 64 GB+ ([`06-computers-and-browsers.md`](06-computers-and-browsers.md)) [INFERENCE] (settled by [D86](#d86): kept) | The VM spike at the start of the Bot computer work in Phase 2 ([D113](#d113)); was the start of v1.1 ([D47](#d47)) |
| O5 | Apply for OpenAI "Sign in with ChatGPT" | Closed by [D54](#d54): allowed in open-source builds; the interest form before any paid or hosted build | — |
| O6 | First external channel in v1.1 | Telegram | Phase 4 gate |
| O7 | Starter team composition | Assistant, plus three templates chosen in [`05-bots-and-assistant.md`](05-bots-and-assistant.md) | Phase 1 |
| O8 | Final product name | Memoshi, pending checks ([D34](#d34)); the identifiers no longer depend on it ([D59](#d59)) | Before brand work |
| O9 | Team size reality | Closed by [D45](#d45): one builder with coding agents | — |
| O10 | Lease timeout, renewal/idle policy, hand-over time and replica lag for bots on every device | Set by the Phase 0 devices spike ([D49](#d49)), including [S2.12's authority-load measurements](phase-0.md#s2-12); [D102](#d102) fixes the relay authority's expiry clock at frame arrival; [D104](#d104) makes renewals extend by the claimed TTL; TTL/renewal policy, CloudKit clock skew and unmeasured capacity remain open | Phase 0 gate |
| O11 | The hosted relay: who runs it, regions, abuse limits, cost cap, and whether it stays free | Free and capped while only the user and invited testers use it [INFERENCE] (settled by [D86](#d86), with the caps set before any tester joins); decided with O1 ([D48](#d48), [D40](#d40)) | Before a public release (O13; was "before beta" until [D67](#d67)) |
| O12 | In Bypass, do runs started by webhooks, connector events or App Intents (the untrusted regime) send T4 actions without a draft card? | Closed by [D57](#d57): they keep the draft card in every mode, Bypass included | — |
| O13 | Public release: the App Store or another channel, and when | Decide after the v1 gate; until then v1 is for the user's own devices ([D67](#d67)) | After v1 |

---

<a id="change-control"></a>
## Change control

1. Every new decision gets the next number, a status, rationale and consequences.
2. Accepted decisions are never silently reversed; a new decision supersedes them.
3. A decision that changes phase scope triggers a roadmap review ([`10-roadmap.md`](10-roadmap.md)).
4. A decision that changes the object model triggers a spec review ([`../specs/object-model.md`](../specs/object-model.md)).
5. A decision that changes design direction triggers a design review ([`03-design-system.md`](03-design-system.md)).
6. Each phase ends with a one-page gate review: shipped vs. planned, exit criteria with evidence, lessons, decision updates.
