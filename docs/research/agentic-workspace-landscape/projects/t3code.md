# T3 Code

> An MIT-licensed control surface for coding agents. One server per machine runs the user's existing Claude Code, Codex, Cursor, Grok Build, OpenCode, Pi, Antigravity and ACP agents with their own subscriptions. Electron desktop, web, iOS and Android clients drive that server locally or remotely through LAN pairing, Tailscale, SSH or the hosted T3 Connect relay. Since v0.1.0 it also has agent-to-agent delegation, scheduled and webhook-triggered tasks, and an MCP endpoint that outside agents can use. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

Scope note: the user's local fork "Forma" (`~/Documents/memoshi/harness`, based on t3code v0.0.33, 2026-08-10) is audited in [landscape/in-house-assets.md](../landscape/in-house-assets.md). This profile covers upstream `pingdotgg/t3code` `main` as of 2026-10-20. Upstream has changed a lot since that snapshot: Orchestrator V2, scheduled tasks, delegation, the outside-agent MCP, ACP Registry, Pi, Muse Code and devices all landed after it.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: T3 Code
slug: t3code
category: agent-workspace-ide        # GUI control plane over wrapped coding CLIs/SDKs; no own agent loop
maker: T3 Tools Inc. (copyright holder, App Store seller) under the Ping.gg GitHub org; Theo Browne (CEO Ping.gg) and Julius Marminge (founding engineer, top committer)
license: MIT
repo: https://github.com/pingdotgg/t3code
website: https://t3.codes
first_public: 2026-03-02   # repo created 2026-02-08, first tag v0.0.0-alpha.3 on 2026-03-02
latest_release: v0.1.0, 2026-10-15 (stable; nightly v0.1.1-nightly.20261020.3386 on 2026-10-20)
release_cadence: "~5 nightlies/day (172 in Aug, 147 in Sep, 97 in Oct 1-20, 2026); stable every 1-2 weeks (v0.0.42 09-16, v0.0.44 09-29, v0.0.45 10-02, v0.1.0 10-15)"
stars: 28683 (as of 2026-10-20)
forks: 7686 (as of 2026-10-20)
contributors: 474 GitHub accounts, 714 including anonymous emails (as of 2026-10-20)
primary_language: TypeScript
stack: "Effect 4 (4.0.5) monorepo on Node 24 + pnpm/Vite+; server with Effect RPC over WebSocket, SQLite event store + projections; React 19 + TanStack Router web; Electron 44 desktop; Expo 58 / React Native 0.88 mobile; Clerk auth; node-pty, libghostty-vt; Cloudflare-Workers relay (PlanetScale, Durable Objects, cloudflared tunnels)"
platforms: [macos, windows, linux, web, ios, android, cli]
agent_engine: "wraps CLIs/SDKs: Codex app-server JSON-RPC, Claude Agent SDK, Cursor SDK, ACP (Grok, Antigravity, ACP Registry, local ACP commands), OpenCode HTTP server (1.x/2.x), Pi RPC mode, Muse Code SDK"
engines_supported: [codex, claude-code, cursor-cli, grok-build, opencode, pi, antigravity, muse-code, acp-registry-agents]
model_access: "subscription logins of the installed CLIs (codex login, claude auth login, agent login, grok login, opencode auth, Google sign-in for Antigravity, muse login); API keys via provider env overrides; whatever models the wrapped agent supports; T3 resells nothing"
execution_env: "user host that runs the T3 server (laptop, desktop, or own Linux/macOS box over SSH); git worktrees per thread; provider-native sandboxes only; no container/VM layer"
per_bot_computer: no   # one environment per machine; threads share it; work can be load-balanced across the user's own machines
persistent_bots: no    # threads are per-task; delegated child agents are ephemeral; scheduled tasks can bind to a thread
memory: "none beyond thread history, checkpoints, provider-native sessions, @-attaching other threads, and budgeted portable handoffs on provider switch"
routines: "yes; scheduled tasks: interval (>=1 min), fixed local time + weekdays, or webhook (HMAC-verified, relay-held up to 24h while offline); created by users or by agents via MCP"
group_chat: "no rooms; agent-to-agent via delegate_task (child agents on any provider/model) and orchestrator MCP thread tools"
coding_workspace: "yes; threads, diffs, hidden-ref checkpoints with revert, forks, terminals, git/PR (stacked, draft), worktrees, multi-forge source control, file browser, PR review tab"
browser_use: "yes; server-hosted headless Chrome tabs shared by user and agent (open/navigate/snapshot/click/type/evaluate/record), take-over control, cookie import"
computer_use: "partial; no own computer use; SnapShots attach window screenshots + accessibility tree; providers' own computer-use plugins (Codex) can run inside; iOS Simulator/Android Emulator control via agent-device"
connectors: "MCP (provider-native MCP configs, MCP Apps rendered inline); T3's own MCP server for outside agents; source-control integrations (GitHub, GitLab, Bitbucket, Azure DevOps, Forgejo); no Composio-style catalog"
channels: "none (no Slack/Telegram/email); inbound webhooks to scheduled tasks; outside agents such as ChatGPT reach it over MCP+OAuth; push notifications and Live Activities via T3 Connect"
mobile: "yes; native iOS (App Store since 2026-07-29, v2.0.0 on 2026-10-15) and Android apps: threads, diffs, terminal, browser, device viewer, scheduled tasks"
voice: "partial; on-device iOS dictation into the composer only"
approvals: "4 per-thread modes (Supervised, Auto-accept edits, Auto = provider auto-review, Full access) mapped onto each provider's own policy; default for new threads is Full access; agents cannot approve their own requests"
e2e_encryption: "no app-level E2E; TLS to the environment (Tailscale HTTPS, Cloudflare tunnel); relay brokers DPoP-bound credentials but does not proxy app traffic"
self_host: "yes; server is self-hosted by design; T3 Connect relay is hosted by T3 but its code is in infra/relay (needs your own Clerk, Cloudflare, PlanetScale, APNs)"
multi_user: "partial; scoped pairing tokens per device/agent, no team accounts or shared workspaces"
pricing: "free; no paid tier found; T3 Connect hosted at no listed cost; users pay their own provider subscriptions"
maturity: "beta: v0.1.0 first stable Orchestrator V2 (2026-10-15); README still says 'very very early... Expect bugs'; ~1,239 open issues"
```

## What it is

T3 Code calls itself an "agent harness control surface": it controls agents already installed on your machine from a desktop app, web app and mobile apps, and "works with your subscriptions on Claude Code, Codex, Cursor, Grok Build, OpenCode, and Google Antigravity" ([README](https://github.com/pingdotgg/t3code#readme)). The website says it is "The open-source control plane for coding agents... Bring your own subscription. Fork the whole thing" and "T3 Code doesn't resell tokens... No keys resold. No quota caps" ([t3.codes](https://t3.codes)).

Mental model: an IDE-like thread list per project. Each **environment** is a T3 server that owns the files, provider processes, terminals and git, and any number of clients connect to it. "T3 Code keeps execution in the environment that owns the workspace. Web, desktop, and mobile clients control it over authenticated RPC" ([overview.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/overview.md)). The motivation is stated as a better developer experience than "the Codex desktop app, Conductor, Claude Desktop and Cursor Glass" and being "performant, remote-ready, and truly open... we want you to have everything you need to fork" ([README](https://github.com/pingdotgg/t3code#readme)).

Target user: professional developers who already pay for one or more coding-agent subscriptions and want one GUI for all of them, plus phone supervision. The site claims "Tolerated by over 500,000 devs" (vendor claim, [t3.codes](https://t3.codes)).

## Product and UX

- **Install**: `curl -fsSL https://t3.codes/install.sh | sh` then `t3` (server + local web UI), `t3 service install` for a background service, `npx t3@latest` to try it; desktop via GitHub Releases, winget, scoop, Homebrew cask, .deb, AUR ([README](https://github.com/pingdotgg/t3code#readme), [background-service.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/background-service.md)). At least one provider CLI must be installed and logged in first; Antigravity can be installed and signed into from Settings ([README](https://github.com/pingdotgg/t3code#installation)).
- **Threads and runs**: composer with a provider/model/effort picker and a per-thread permission mode. Follow-ups either steer or queue (setting, with `Cmd/Ctrl+Enter` doing the opposite). The queue lives on the server, survives restarts and can be edited, reordered and steered from mobile ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0)).
- **Limits and recovery**: threads stopped by a usage limit show as **Limited**, with "resume at reset" and "snooze until reset". "Continue threads after restarts" resumes interrupted threads after an update, crash or reboot ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0)).
- **Fork, switch, delegate**:
  - Fork from any finished run. Codex, Claude, Pi and OpenCode 2 use native forks; other providers get portable context transfer. A fork can be merged back into its source.
  - Provider or model can change between turns.
  - The release notes say provider switching "isn't the recommended way to use multiple harnesses. The handoff is lossy". They recommend `delegate_task` instead, e.g. "Claude planning and Codex implementing" ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0)).
- **Subagents you can follow**: native subagents of Claude, Codex, OpenCode 2, Cursor and Pi appear as read-only child threads in a lineage view, with model, status and duration. Background work wakes the parent when done ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0)).
- **Review and ship**:
  - Each thread writes to its own branch, and one button commits, pushes and opens a PR with a generated title and body. Draft, stacked and amended PRs are supported ([t3.codes](https://t3.codes)).
  - Source control covers GitHub, GitLab, Bitbucket, Azure DevOps, Forgejo and GitCafe packages ([repo tree](https://github.com/pingdotgg/t3code/tree/main/packages)).
  - The mobile 2.0 app adds a Pull Requests tab with guided reviews ([App Store listing](https://apps.apple.com/us/app/t3-code-remote-claude-more/id6787819824)).
- **Thread details panel**: workspace, Git, scripts, linked PRs, automations and lineage. Sidebar status (working, waiting, limited, failed) is computed by the server, and threads "settle" based on PR state and inactivity ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0), [overview.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/overview.md)).
- **Visual replies**: agents can answer with a sandboxed self-contained HTML page (chart, table, mockup) rendered above the text reply on all clients. They check their pages with screenshots from a T3-managed headless browser ([html-renders.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/html-renders.md)). MCP Apps from tool calls also render inline ([mcpApps.ts](https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/mcpApps.ts)).
- **Usage page**: token use, cache savings and estimated API-equivalent cost across Codex, Claude Code, Grok, OpenCode, Antigravity, Pi and Cursor history on all connected environments ([usage.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/usage.md)).
- **Devices panel** (distinctive): a live iOS Simulator or Android Emulator next to the thread that both user and agent can drive. The agent uses `device_*` tools and the `agent-device` CLI, and SSH device hosts are supported ([devices.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/devices.md)).
- **SnapShots** (desktop, off by default): a hotkey captures the focused window and attaches it with app name, title and accessibility data to the draft ([snap-shot.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/snap-shot.md)).
- **Multi-machine**: one project can be grouped across environments. Optional **Auto balance** picks the machine for new threads by CPU and memory, with per-machine Prefer, Less often and Manual only settings ([remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md#balance-new-threads-across-machines)). A 2026-10-20 commit adds "add a project to another machine from Run on, .env files included" ([commits](https://github.com/pingdotgg/t3code/commits/main)).

## Architecture

```
clients: Electron desktop (bundles a server) | web (local or app.t3.codes) | Expo iOS/Android
   |  Effect RPC over one authenticated WebSocket (+HTTP), scoped sessions
   |  routes: localhost | LAN pairing | Tailscale HTTPS | desktop-managed SSH | T3 Connect tunnel
   v
T3 server ("environment", one per machine, ~/.t3)
   |-- Orchestrator V2: serialized commands -> events + projections + receipts + outbox in one SQLite txn
   |-- EffectWorker -> provider adapters (Codex app-server, Claude Agent SDK, Cursor SDK, ACP, OpenCode, Pi RPC, Muse)
   |-- checkpoints (hidden git refs), terminals (node-pty), git/PR, headless Chrome tabs, device hub
   |-- /mcp: orchestrator + preview tools for its own agents (thread-scoped bearer) and outside agents (OAuth)
   |-- scheduled tasks (interval / fixed time / webhook) + Scheduler
   `-- cloud link -> cloudflared tunnel <- T3 Connect relay (Cloudflare Workers, Clerk, Durable Objects, APNs)
```

- **Components**: `apps/server`, `apps/web`, `apps/desktop`, `apps/mobile` and `apps/marketing`, plus about 25 workspace packages:
  - `contracts`: Effect Schema RPC contract.
  - `client-runtime`: shared connection and state for web and mobile.
  - `effect-codex-app-server` and `effect-acp`: typed protocol clients.
  - `provider-core` and `provider-{acp,acp-registry,cursor,grok,muse,opencode,pi}`.
  - `source-control-*`, `ssh`, `tailscale`.
  - The relay lives in `infra/relay` ([repo tree](https://github.com/pingdotgg/t3code/tree/main)).
- **Stack**:
  - Effect 4.0.5 throughout via the pnpm catalog ([pnpm-workspace.yaml](https://github.com/pingdotgg/t3code/blob/main/pnpm-workspace.yaml)).
  - Server deps: `@anthropic-ai/claude-agent-sdk ^0.3.276`, `@cursor/sdk 1.0.35`, `node-pty`; Node `^22.16 || ^23.11 || >=24.10` ([apps/server/package.json](https://github.com/pingdotgg/t3code/blob/main/apps/server/package.json)).
  - Electron 44.4.5 with `@clerk/electron` ([apps/desktop/package.json](https://github.com/pingdotgg/t3code/blob/main/apps/desktop/package.json)).
  - Web: React, TanStack Router, Tailwind 4 ([apps/web/package.json](https://github.com/pingdotgg/t3code/blob/main/apps/web/package.json)).
  - Mobile: Expo 58.0.14, React Native 0.88.0, `expo-sqlite`, `@clerk/expo` ([apps/mobile/package.json](https://github.com/pingdotgg/t3code/blob/main/apps/mobile/package.json)).
  - Build tool: Vite+ (`vp`) ([README](https://github.com/pingdotgg/t3code#install-vp)).
- **Orchestration and event sourcing (V2)**:
  - Landed in PR [#2829](https://github.com/pingdotgg/t3code/pull/2829) on 2026-10-02 (823 commits, +380,729/-203,651 lines, by juliusmarminge) and shipped stable in v0.1.0.
  - The [V2 orchestrator](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/orchestration-v2/Orchestrator.ts) "serializes commands and decides events without performing provider or filesystem work".
  - `EventSink` "commits events, persisted projections, the accepted command receipt, and outbox effects in one database transaction". The `EffectWorker` then performs side effects and feeds results back. "A command acknowledgement therefore means the intent committed" ([overview.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/overview.md)).
  - Data model: AppThread, then Run (counted user turn), then a tree of ExecutionNodes (tool, approval, subagent), with provider threads attached. Invariants include "App ids are primary. Provider ids are refs" and "Provider switches create explicit context handoff artifacts" ([orchestration-v2/README.md](https://github.com/pingdotgg/t3code/blob/main/docs/orchestration-v2/README.md)).
  - The model was derived from Codex app-server probes, with Codex treated as "the richest protocol"; weaker providers get app-owned ids and capability flags (same source).
- **Checkpoints**: hidden git refs capture workspace state "without adding commits to the user's branch". A revert must coordinate with the provider conversation, so a provider that cannot roll back its conversation (e.g. Antigravity) rejects revert before touching files ([overview.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/overview.md#turn-completion-and-checkpoints), [providers.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md)).
- **Provider drivers and wire protocols** (adapter boundary in [ProviderAdapter.ts](https://github.com/pingdotgg/t3code/blob/main/packages/provider-core/src/server/ProviderAdapter.ts); "a driver kind identifies an integration; an instance identifies one configuration and account", so two accounts on one driver are isolated ([providers.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md))):
  - Codex: app-server JSON-RPC via `effect-codex-app-server`. MCP is injected with `-c mcp_servers.t3-code.url=...` and a bearer token in an env var. Native `/goal` is mirrored ([orchestrator-mcp-server.md](https://github.com/pingdotgg/t3code/blob/main/docs/orchestration-v2/orchestrator-mcp-server.md), [providers.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md)).
  - Claude: Claude Agent SDK with an HTTP MCP server and `allowedTools: ["mcp__t3-code__*"]` (same source). It runs the user's `claude` login ([README](https://github.com/pingdotgg/t3code#installation)).
  - Cursor: the official `@cursor/sdk` since v0.1.0, replacing the CLI ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0)).
  - Grok Build: shared ACP adapter plus an xAI extension flavor. ACP has no native subagents or steering, so steering is "cancel-and-restart" and forks use portable transfer ([orchestrator-mcp-server.md](https://github.com/pingdotgg/t3code/blob/main/docs/orchestration-v2/orchestrator-mcp-server.md)).
  - ACP Registry: any agent from the official registry (Devin, Cline, Kimi, Droid, Antigravity's `antigravity-acp`...) or any local ACP command (e.g. DeepSeek Harness `dsh --profile acp`). The ACP v2 preview protocol is preferred, with fallback to v1. Binaries are installed under `tools/<agent-id>/<version>/`, with SHA-256 verified when the registry provides one ([providers-acp.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-acp.md)).
  - OpenCode: probes the version. 1.x gets one T3-managed server per thread; 2.x gets one server per instance with per-thread `t3-code-<thread>` MCP entries, and other threads' entries are denied ([providers.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md)).
  - Pi: the user's `pi` in RPC mode; native resume, rollback and fork via Pi session files (same source).
  - Muse Code (Meta): beta, disabled by default, uses `muse login` or `META_API_KEY` ([providers-muse.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-muse.md)). It is driven through an SDK module (`packages/provider-muse/src/server/sdk.ts`) [INFERENCE from file names].
  - Antigravity: per-instance account profiles with file-based credentials and ambient Google credentials stripped. Installs are versioned and leased so running agents are never swapped under ([providers.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md)).
- **Models and auth**: no model calls of its own for agent work. Each provider uses its own saved login on the host, and per-instance env overrides allow API keys. Managed ChatGPT sign-in for a remote environment can complete on a local machine and hand tokens to the destination ([providers.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md)). Minimum versions for v0.1.0: Codex 0.159+, Claude Code 2.1.280+, Grok 1.0.13+, OpenCode 2.0.18+, Pi 0.80.5+ ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0)).
- **Execution environment**: the host running the T3 server, with the user's permissions and git worktrees. Isolation comes from the provider's own sandbox and approval policy. T3 states that "prompt instructions and tool denial do not create a native sandbox" ([providers.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md)). Agent browser tabs run in headless Chrome inside Chrome's sandbox on the host ([remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md#browser-on-a-remote-environment)).
- **State and storage**:
  - Projects, threads and settings live under `~/.t3/userdata` and are kept on uninstall ([background-service.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/background-service.md)).
  - SQLite holds events and projections. V2 imports V1 history one way on first start ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0)).
  - Attachments live outside the workspace ([providers.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md)).
  - Secrets requested from the user go to a server secret store under a one-use `SecretRef` "so the value never reaches the transcript, projections, clients, or model context" ([SecretRequests.ts](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/secrets/SecretRequests.ts)).
  - No cloud sync of threads: the hosted web app keeps only a connection catalog in the browser ([remote.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/remote.md)).
- **Remote and mobile access**:
  - **Routes**: a saved environment holds an ordered route list (LAN, Tailscale, VPN, public URL, SSH, T3 Connect). The client uses the first route that answers and re-probes earlier ones every minute. LAN and tailnet addresses are learned automatically after pairing once ([remote.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/remote.md), [remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md)).
  - **Pairing**: `t3 pair` (or Settings) issues a one-time link or QR code. Hosted pairing URLs carry the secret in the URL fragment so it never reaches the hosted origin. Tokens can be narrowed with `--scope` (`orchestration:read`, `terminal:operate`, `filesystem:write`, `source-control:write`, ...) ([remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md#manage-or-revoke-access), [environment-auth.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/environment-auth.md)).
  - **Tailscale**: `t3 serve --tailscale-serve` or `t3 pair --tailscale` exposes the server at `https://machine.tailnet.ts.net/` ([remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md#tailscale-https)).
  - **SSH**: desktop main spawns SSH and starts or reuses a server under `~/.t3/runtime` on Linux or Apple Silicon hosts, then forwards the port. It stops only servers it launched itself ([remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md#desktop-managed-ssh), [packages/ssh](https://github.com/pingdotgg/t3code/tree/main/packages/ssh)).
  - **T3 Connect**: Clerk identity plus a relay on Cloudflare that provisions a `cloudflared` tunnel per environment. "The relay Worker does not proxy their HTTP or WebSocket sessions"; it mints one-time bootstrap credentials bound to the client's DPoP key. The stated trust caveat: "DPoP... does not make a compromised relay signing key harmless". Idle tunnels are reaped to save Cloudflare cost ([t3-connect.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/t3-connect.md)).
  - **Push**: mobile push notifications and iOS Live Activities / Android ongoing cards for finished, failed, approval-needed or question events. They require T3 Connect; direct or Tailscale connections alone get no push ([mobile-notifications.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/mobile-notifications.md)).
  - **Desktop as pure remote**: the desktop app can run with **Local environment** off ([remote.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/remote.md#desktop-without-a-local-environment)).
- **Extension surface**:
  - Each provider's native skills, MCP and hooks.
  - T3's `/mcp` endpoint, with an orchestrator toolkit (create, launch, message, wait on, read, search and interrupt threads; `delegate_task`; scheduled tasks; PR links), a preview/browser toolkit, and worktree and thread-metadata tools ([orchestrator-mcp-server.md](https://github.com/pingdotgg/t3code/blob/main/docs/orchestration-v2/orchestrator-mcp-server.md), [apps/server/src/mcp](https://github.com/pingdotgg/t3code/tree/main/apps/server/src/mcp)).
  - No plugin API for third-party UI. The intended extension path is "fork it" ([t3.codes](https://t3.codes)).

## Capabilities in detail

**Persistent bots / identity.** None. The unit of work is a thread bound to one project and one environment. Delegated children and native subagents are ephemeral, read-only child threads ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0)). The closest thing to a "bot" is a scheduled task bound to a thread: the original PR describes an agent that can "wake up every 5 minutes and check CI" in its own thread ([PR #3638](https://github.com/pingdotgg/t3code/pull/3638)).

**Memory.** No long-term memory module. Context comes from:
- provider-native sessions;
- `@`-attaching another thread ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0));
- portable handoffs on provider switch or fork. These are "a budgeted selection, not an agent-written summary": a 16,000-token default cap (`T3CODE_CONTEXT_HANDOFF_TOKEN_CAP`, 1,024-64,000), plus a thread-reading tool to fetch omitted history ([portable-handoffs.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/portable-handoffs.md)).

**Routines / automation (scheduled tasks).**
- History: first built in PR [#3638](https://github.com/pingdotgg/t3code/pull/3638) (merged into the V2 branch 2026-07-01), reached `main` with V2 on 2026-10-02, and shipped stable in v0.1.0. Webhook triggers came in [#15085](https://github.com/pingdotgg/t3code/pull/15085) and opt-in offline holding in [#15487](https://github.com/pingdotgg/t3code/pull/15487) (both 2026-10-05) ([commit history](https://github.com/pingdotgg/t3code/commits/main/apps/server/src/scheduledTasks/ScheduledTaskService.ts)).
- Schedule types:
  - `interval`: minimum 60,000 ms, advances by elapsed time across DST.
  - `fixed_time`: `HH:MM` plus weekdays, in the server's time zone. Runs missed by more than 10 minutes are skipped and re-aimed.
  - `webhook` ([scheduledTask.ts](https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/scheduledTask.ts), [Schedule.ts](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/scheduledTasks/Schedule.ts)).
- What a task carries: project, workspace strategy (new worktree, project checkout or specific checkout), full model selection, runtime mode and interaction mode. An optional thread binding posts runs into that thread; unbound tasks start a fresh thread per run ([scheduledTask.ts](https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/scheduledTask.ts), [PR #3638](https://github.com/pingdotgg/t3code/pull/3638)).
- Webhooks:
  - The prompt is a template with `{{body.path}}`, `{{headers.name}}`, `{{query.name}}`, `{{body}}` and `{{request}}` placeholders.
  - Optional HMAC-SHA256 header verification (hex or base64, configurable prefix, constant-time compare).
  - Limits: 60 accepted deliveries per task per minute, 20 queued per task, last 50 deliveries logged ([ScheduledTaskService.ts](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/scheduledTasks/ScheduledTaskService.ts), [webhookVerification.ts](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/scheduledTasks/webhookVerification.ts)).
  - The relay gives a stable URL `/v1/hooks/:environmentId/:hookId/:token`. If the user opts in, it holds requests in a per-environment Durable Object for up to 24 h while the host is offline, with a delivery id for dedup ([t3-connect.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/t3-connect.md)).
- Who can create tasks: humans (web and mobile UI) and agents (MCP `schedule_task` and related tools). Mobile can manage tasks across environments ([PR #12351](https://github.com/pingdotgg/t3code/pull/12351)).
- Known design limit stated in the PR: "Run claiming is in-process only (fine for the local server; needs a DB lease if multi-instance)" ([PR #3638](https://github.com/pingdotgg/t3code/pull/3638)).

**Multi-agent collaboration.**
- `delegate_task` "lets an agent hand work to a child agent on any provider and model, with its own options and role". The parent can wait or keep working and is woken with batched results ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0)).
- The child receives only the task prompt plus an optional role instruction: "Parent conversation history is not copied into the child" ([orchestrator-mcp-server.md](https://github.com/pingdotgg/t3code/blob/main/docs/orchestration-v2/orchestrator-mcp-server.md)).
- MCP credentials for T3's own agents are scoped to environment, parent thread, provider instance and provider session. They expire on idle or when the session is released (same source).
- There are no multi-agent chat rooms.

**Outside agents.**
- Claude Code or Codex in a terminal, ChatGPT, or "bots that support MCP" can connect to `https://<environment>/mcp` with OAuth (PKCE, approval with a pairing code) ([outside-agents.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/outside-agents.md)).
- The default grant is **Read only**. Higher grants are a runtime-mode ceiling: "A thread it starts or steers cannot run with more permissions than the mode you chose". Sign-ins last 30 days. Hosted agents must use the T3 Connect address (same source, [environment-auth.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/environment-auth.md)).
- This lets a chat assistant act as a front-end to coding agents [INFERENCE].

**Coding workspace.** Threads, worktrees with configurable branch names, diffs from checkpoints, revert, terminals (node-pty, libghostty-vt), file browser and editing behind the `filesystem:*` scopes, PR linking and stacks, and merge controls that follow checks ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0), [remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md#manage-or-revoke-access)).

**Browser.**
- Tabs belong to the environment, so "you and your agents see the same tabs from any device". Agents keep using them while no device is connected.
- Users take or release control of an agent's tab. Clipboard, file pickers and downloads bridge to the controlling device. On a phone the tab can go picture-in-picture ([remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md#browser-on-a-remote-environment)).
- Agent operations: status, open, navigate, snapshot, click, type, press, scroll, evaluate, waitFor and recording start/stop ([previewAutomation.ts](https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/previewAutomation.ts)).
- Cookies can be imported from the user's browser into a preview profile ([browser-import.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/browser-import.md)).

**Computer use.** No own desktop-control loop. SnapShots give agents window screenshots plus accessibility trees ([snap-shot.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/snap-shot.md)). Codex's own Computer Use runs inside T3 Code, as shown by an open macOS entitlement bug ([issue #21282](https://github.com/pingdotgg/t3code/issues/21282)). Mobile simulators and emulators are fully agent-controllable ([devices.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/devices.md)).

**Connectors and channels.** No connector catalog and no messaging channels. External input arrives through webhooks (scheduled tasks), outside MCP agents, or provider-native MCP servers. Jira MCP Apps are an example of the inline-rendered MCP Apps in use ([issue #16992](https://github.com/pingdotgg/t3code/issues/16992)).

**Voice.** On-device iOS transcription into the composer; "environment-backed transcription is not implemented" ([voice-input.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/voice-input.md)).

**Mobile.**
- iOS "T3 Code - Remote Claude & more" by T3 Tools, Inc.: released 2026-07-29, v2.0.0 on 2026-10-15, free, 144 ratings averaging 4.85 (US store, as of 2026-10-20) ([iTunes lookup](https://itunes.apple.com/lookup?id=6787819824)).
- The Android app is on Google Play ([README](https://github.com/pingdotgg/t3code#readme)).
- App description: "you have pretty much the full power of the desktop app right in your hands... kick off agent runs, browse files, perform version control actions, review diffs, even use the terminal" ([App Store](https://apps.apple.com/us/app/t3-code-remote-claude-more/id6787819824)).

**Team features.** Single owner per environment. Multiple devices and agents get separately scoped sessions; there are no teams or shared bots ([remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md#manage-or-revoke-access)).

## Security and trust model

- **Approvals**:
  - Four modes: Supervised, Auto-accept edits, Auto (provider auto-review on Codex, Claude, Cursor and Grok) and Full access.
  - **"The initial default is Full access"** for new threads. Projects can override the environment default ([permission-modes.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/permission-modes.md)).
  - Enforcement is the provider's. Providers without auto-review fall back to asking. Muse supports only Supervised and Full access, and Grok has no Auto-accept edits (same source).
  - OpenCode "always" grants are replied as `once` so a full-access thread cannot widen a supervised thread's permissions on a shared server ([providers.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md)).
  - "Agents can't approve their own permission requests" ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0)).
- **Sandboxing**: none of its own. Agents run as the server's user, and the docs say plainly that "Prompt instructions and tool denial do not create a native sandbox" ([providers.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md)). Agent browser tabs run in Chrome's sandbox, which can be disabled with `T3CODE_SERVER_BROWSER_SANDBOX=0` ([remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md#browser-host-setup)).
- **Access control**:
  - Scoped sessions per client. The default pairing grant includes every scope, because "`terminal:operate` is a shell as the server's user and `orchestration:operate` can start a full-access agent, and either can mint a session with every scope", so withholding management "would not be a boundary" ([environment-auth.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/environment-auth.md)).
  - DPoP-bound tokens, and pairing secrets kept in URL fragments ([remote.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/remote.md)).
  - A route-change rule: a token paired over HTTPS never learns a plain-HTTP route (same source).
- **Relay trust**: the relay brokers credentials but does not carry app traffic. A compromised relay signing key is an acknowledged risk ([t3-connect.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/t3-connect.md)). There is no end-to-end encryption on top of TLS. Traffic goes through Cloudflare tunnels that Ping provisions [INFERENCE from t3-connect.md].
- **Secrets**: one-use secret refs keep user-entered secrets out of model context ([SecretRequests.ts](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/secrets/SecretRequests.ts)). Provider credentials stay on the host in each provider's own store. Antigravity is forced to file-based credentials per instance ([providers.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md)).
- **Supply chain**:
  - `cloudflared` is version-pinned with checksums ([t3-connect.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/t3-connect.md)).
  - ACP Registry binaries are SHA-256 verified only when the registry declares a checksum, and "Registry agents are third-party code; review an agent's source and license" ([providers-acp.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-acp.md)).
  - Provider auto-updates run only through the proven owning installer ([providers.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md)).
- **Telemetry (on by default)**:
  - Product events go to `ingest.t3.codes` and are forwarded to PostHog.
  - They include hashed identifiers for the T3 Connect account, **"your OpenAI and Claude accounts when you are signed in"** and each connecting device.
  - Events carry provider, model, effort, permission mode, turn result, duration and token totals. Prompts, responses and file contents are excluded.
  - Relay traces go to Axiom. Opt out with `T3CODE_TELEMETRY_ENABLED=false` ([telemetry.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/telemetry.md)).
  - A 2026-10-20 commit adds "a stable install id and who owns each install" to analytics ([commits](https://github.com/pingdotgg/t3code/commits/main)).
- **Incidents**: no published GitHub security advisories and no `SECURITY.md` (404) as of 2026-10-20 ([advisories API](https://github.com/pingdotgg/t3code/security/advisories)). An issue search for "security" found only platform-entitlement and signing bugs (e.g. [#21283](https://github.com/pingdotgg/t3code/issues/21283), [#5639](https://github.com/pingdotgg/t3code/issues/5639)).

## Traction and momentum

All GitHub numbers as of 2026-10-20 via the GitHub API.

| Metric | Value |
| --- | --- |
| Stars / forks / watchers | 28,683 / 7,686 / 77 ([repo](https://github.com/pingdotgg/t3code)). Repo created 2026-02-08, first commit "Monorepo electron init" 2026-02-08, so the star count is not inherited from a renamed repo |
| Contributors | 474 accounts (714 incl. anonymous). Top: juliusmarminge 3,145 commits, t3dotgg 750, maria-rcks 417, t3-code[bot] 117 |
| Commits on `main` | 7,050 total; ~2,840 since 2026-09-20 (commit search); 1,623 in the 7 days since 2026-10-13 |
| PRs | 6,565 merged total, 3,037 merged since 2026-09-20; 1,144 open |
| Issues | 1,239 open |
| Releases | 55 stable/alpha tags (v0.0.0-alpha.3 2026-03-02 to v0.1.0 2026-10-15) + 647 nightly prereleases (~5/day Aug-Oct) ([releases](https://github.com/pingdotgg/t3code/releases)) |
| Asset downloads | v0.1.0 1.56M, v0.0.45 4.51M summed asset counts; inflated by auto-update metadata and blockmaps [INFERENCE], not a user count |
| Mobile | iOS 144 ratings, avg 4.85 (US) ([iTunes lookup](https://itunes.apple.com/lookup?id=6787819824)) |

- **Governance**:
  - GitHub org Ping.gg ("We build tools for modern devs"). The legal entity on the LICENSE and the App Store is **T3 Tools Inc.** ([LICENSE](https://github.com/pingdotgg/t3code/blob/main/LICENSE), [iTunes lookup](https://itunes.apple.com/lookup?id=6787819824)).
  - Theo Browne's profile says "CEO @ Ping.gg"; Julius Marminge's says "Founding Engineer @pingdotgg" ([GitHub users API](https://github.com/t3dotgg), [juliusmarminge](https://github.com/juliusmarminge)).
  - Maintainers exempt from triage rules: bmdavis419, juliusmarminge, maria-rcks, markflorkowski, t3dotgg, Yash-Singh1 ([TRIAGE_EXEMPTIONS.td](https://github.com/pingdotgg/t3code/blob/main/.github/TRIAGE_EXEMPTIONS.td)).
  - A vouch list of 77 trusted external contributors is used by a `pr-vouch` workflow ([VOUCHED.td](https://github.com/pingdotgg/t3code/blob/main/.github/VOUCHED.td), [workflows](https://github.com/pingdotgg/t3code/tree/main/.github/workflows)).
  - Review is heavily automated (Cursor Bugbot, Macroscope, CodeRabbit configs and PR summaries), and many PRs are agent-authored ([PR #3638](https://github.com/pingdotgg/t3code/pull/3638), [.coderabbit.config.ts](https://github.com/pingdotgg/t3code/blob/main/.coderabbit.config.ts)).
- **Contribution policy**:
  - "We are (mostly) not accepting contributions yet. Small fixes may be considered. Big features will not be" ([README](https://github.com/pingdotgg/t3code#some-notes)).
  - CONTRIBUTING: "We are not actively seeking outside contributions and have limited review capacity". Features need prior explicit maintainer approval in an Ideas discussion, one problem per PR, and behavioral evidence (screenshots for UI) ([CONTRIBUTING.md](https://github.com/pingdotgg/t3code/blob/main/CONTRIBUTING.md)).
  - No CLA.
- **Community and press**: Discord ([invite](https://discord.gg/jn4EGJjrvv), member count unknown). The website quotes developer tweets, e.g. Corey Quinn: "T3 code is freaking transformational" (testimonials selected by the vendor, [t3.codes](https://t3.codes)).
- **Business model**: free, MIT, "Nothing. We built T3 Code because we wanted the best possible development experience" ([README](https://github.com/pingdotgg/t3code#wait-what-are-you-selling-me)). T3 Connect is hosted by T3 with no published price. Tunnel cost control (reaping idle Cloudflare tunnels) suggests Ping absorbs the infrastructure cost [INFERENCE from t3-connect.md]. No paid tier found.

## Strengths

- Broadest serious multi-harness adapter layer in the category: Codex app-server, Claude Agent SDK, Cursor SDK, ACP v1/v2 (any registry agent), OpenCode 1.x/2.x, Pi and Muse, all behind one normalized, capability-flagged event model.
- Production-grade core: an event-sourced orchestrator with a transactional outbox, idempotent command receipts, replay-backed tests, hidden-ref checkpoints, and restart-safe queues and interrupted runs.
- Best-in-class remote story: ordered multi-route connections (LAN, Tailscale, SSH, relay) with learned routes, scoped and DPoP-bound sessions, a relay that brokers but does not proxy, native mobile apps with push and Live Activities, and server-hosted browser tabs and simulators visible from the phone.
- Agent-to-agent orchestration across vendors (`delegate_task`) and an OAuth MCP endpoint that lets ChatGPT or any MCP bot drive local coding agents within a permission ceiling.
- Automations that live on the server: interval, fixed-time and signed-webhook tasks, with relay-held delivery while offline.
- MIT, with a large and very fast-moving team and community (about 230 commits/day on `main` in the last week).

## Weaknesses and risks

- **Coding-only product**: no persistent identities, no long-term memory, no messaging channels, no connector catalog, no non-developer onboarding. A user needs installed and logged-in coding CLIs.
- **Default Full access** with no T3-level sandbox. Safety depends on each provider's policy and the user's host account.
- **Telemetry on by default**, including hashed OpenAI/Claude account identifiers and new install-ownership tracking. This could be a concern for a privacy-positioned product built on it [INFERENCE].
- **Churn**:
  - About 5 nightlies a day, and V2 was a +380k/-204k-line rewrite with a one-way database migration.
  - V1 and V2 clients and servers cannot interoperate ([v0.1.0 notes](https://github.com/pingdotgg/t3code/releases/tag/v0.1.0)).
  - Forks pay a heavy merge tax, as the Forma fork shows ([in-house-assets.md](../landscape/in-house-assets.md)).
- **Effect 4 everywhere**: contributors are pointed to Effect-specific guides ([AGENTS.md](https://github.com/pingdotgg/t3code/blob/main/AGENTS.md)). Partial lifts are hard.
- **Hosted dependencies for the best features**: push notifications and stable webhook URLs require T3 Connect, which runs on Ping's Clerk, Cloudflare and PlanetScale accounts. Self-hosting the relay means re-provisioning all of that ([t3-connect.md](https://github.com/pingdotgg/t3code/blob/main/docs/internals/t3-connect.md), [infra/relay](https://github.com/pingdotgg/t3code/tree/main/infra/relay)).
- **Subscription-auth model**: it drives consumer CLI logins. That is fine for personal use, but provider terms could shift for commercial multi-user products [INFERENCE].
- **Closed contribution model and backlog**: 1,239 open issues and 1,144 open PRs as of 2026-10-20. Outside features are generally not accepted.
- **Brand**: MIT covers code, not the "T3" name or icons. Forks must rebrand and must not point at Ping's relay or Clerk app [INFERENCE; see in-house-assets.md].

## Ideas worth taking for Memoshi

- **Environment owns execution, clients are thin**: one RPC contract with capability negotiation instead of client-version checks. This maps directly onto "a bot's computer" being an environment that phone, web and desktop all attach to.
- **Event log + transactional outbox + idempotent receipts** for agent runs: makes routines, restarts and crash recovery boring. Adopt the pattern even without Effect.
- **Normalized execution graph** (thread, then run, then execution nodes, with provider refs as secondary ids) and explicit capability flags per provider. This is a good adapter contract for a multi-engine Memoshi.
- **Ordered route list with learned routes and DPoP-bound sessions; a relay that brokers but does not proxy.** This gives cheap remote access without carrying user traffic.
- **Scheduled tasks schema** (interval / fixed_time / webhook, workspace strategy, model selection, runtime-mode ceiling, thread binding, signed webhooks, 24h offline hold). It is close to what Memoshi routines need; add a DB lease for multi-instance.
- **Outside-agent MCP with OAuth and a "runtime-mode ceiling" instead of raw scopes**: lets ChatGPT, Grok Bot or other assistants delegate into Memoshi bots safely.
- **`delegate_task` with a fresh child context (no parent history copy)**, plus "do not switch providers, delegate instead". This is a clean answer to multi-engine collaboration.
- **One-use SecretRef for user-entered secrets** so values never hit the transcript or model.
- **Server-owned browser tabs and simulators shared by user and agent with take-over control**: strong "watch your teammate work" UX on mobile.
- **Avoid**: Full access as the default, opt-out telemetry with third-party account hashing, and forking a codebase moving this fast. Prefer pinning a tag or treating it as a reference.

## Open questions

- Will T3 Connect stay free, and what are its tunnel or environment limits? `environment_link_limit_exceeded` exists ([remote-access.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md#t3-connect-troubleshooting)) but no number is documented. Read `infra/relay` config or ask maintainers.
- Real active-user numbers: the "500,000 devs" claim is unverified. Analytics are private.
- Whether any persistent-agent, memory or chat-channel features are on the roadmap: check [Ideas discussions](https://github.com/pingdotgg/t3code/discussions/categories/ideas) and the pinned V2 issue [#14871](https://github.com/pingdotgg/t3code/issues/14871).
- Exact Muse Code protocol (SDK vs CLI JSON): read `packages/provider-muse/src/server/sdk.ts`.
- Android install counts and Discord size: not retrieved (Play Store page and Discord API not fetched successfully).
- Whether multi-instance scheduled-task claiming (DB lease) has been added since PR #3638: read `ScheduledTaskService.ts` run-claim logic in full.

## Sources

1. https://github.com/pingdotgg/t3code (README, repo/contributors/commits/releases/search API, fetched 2026-10-20)
2. https://github.com/pingdotgg/t3code/releases/tag/v0.1.0
3. https://github.com/pingdotgg/t3code/blob/main/LICENSE
4. https://github.com/pingdotgg/t3code/blob/main/CONTRIBUTING.md
5. https://github.com/pingdotgg/t3code/blob/main/AGENTS.md
6. https://github.com/pingdotgg/t3code/blob/main/.github/TRIAGE_EXEMPTIONS.td
7. https://github.com/pingdotgg/t3code/blob/main/.github/VOUCHED.td
8. https://github.com/pingdotgg/t3code/blob/main/docs/internals/overview.md
9. https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md
10. https://github.com/pingdotgg/t3code/blob/main/docs/internals/remote.md
11. https://github.com/pingdotgg/t3code/blob/main/docs/internals/t3-connect.md
12. https://github.com/pingdotgg/t3code/blob/main/docs/internals/environment-auth.md
13. https://github.com/pingdotgg/t3code/blob/main/docs/internals/voice-input.md
14. https://github.com/pingdotgg/t3code/blob/main/docs/orchestration-v2/README.md
15. https://github.com/pingdotgg/t3code/blob/main/docs/orchestration-v2/orchestrator-mcp-server.md
16. https://github.com/pingdotgg/t3code/blob/main/docs/user/permission-modes.md
17. https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md
18. https://github.com/pingdotgg/t3code/blob/main/docs/user/outside-agents.md
19. https://github.com/pingdotgg/t3code/blob/main/docs/user/portable-handoffs.md
20. https://github.com/pingdotgg/t3code/blob/main/docs/user/devices.md
21. https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-acp.md
22. https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-muse.md
23. https://github.com/pingdotgg/t3code/blob/main/docs/user/telemetry.md
24. https://github.com/pingdotgg/t3code/blob/main/docs/user/usage.md
25. https://github.com/pingdotgg/t3code/blob/main/docs/user/background-service.md
26. https://github.com/pingdotgg/t3code/blob/main/docs/user/mobile-notifications.md
27. https://github.com/pingdotgg/t3code/blob/main/docs/user/snap-shot.md
28. https://github.com/pingdotgg/t3code/blob/main/docs/user/html-renders.md
29. https://github.com/pingdotgg/t3code/blob/main/docs/user/browser-import.md
30. https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/scheduledTask.ts
31. https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/previewAutomation.ts
32. https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/mcpApps.ts
33. https://github.com/pingdotgg/t3code/blob/main/apps/server/src/scheduledTasks/ScheduledTaskService.ts
34. https://github.com/pingdotgg/t3code/blob/main/apps/server/src/scheduledTasks/Schedule.ts
35. https://github.com/pingdotgg/t3code/blob/main/apps/server/src/scheduledTasks/webhookVerification.ts
36. https://github.com/pingdotgg/t3code/blob/main/apps/server/src/secrets/SecretRequests.ts
37. https://github.com/pingdotgg/t3code/blob/main/apps/server/package.json, apps/desktop/package.json, apps/web/package.json, apps/mobile/package.json, pnpm-workspace.yaml
38. https://github.com/pingdotgg/t3code/pull/2829 (Orchestrator V2)
39. https://github.com/pingdotgg/t3code/pull/3638 (scheduled tasks), /pull/15085, /pull/15487, /pull/12351
40. https://github.com/pingdotgg/t3code/issues/21282, /issues/21283, /issues/16992, /issues/5639, /issues/14871
41. https://t3.codes (website, fetched 2026-10-20)
42. https://itunes.apple.com/lookup?id=6787819824 (App Store metadata)
43. https://github.com/pingdotgg (org API), https://github.com/t3dotgg, https://github.com/juliusmarminge (user API)
44. ../landscape/in-house-assets.md (Forma fork audit; not repeated here)
