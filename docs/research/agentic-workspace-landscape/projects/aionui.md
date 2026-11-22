# AionUi

> A cross-platform Electron "Cowork" desktop (plus WebUI and IM channels) that puts a built-in Rust agent and 30+ ACP-speaking CLI agents (Claude Code, Codex, Gemini CLI, OpenCode, OpenClaw, Hermes, Pi, Grok Build...) behind one chat UI, with office-document skills, cron jobs, and leader/teammate "Team mode"; maintained by a commercial company that now distributes installers only from its own site and runs a paid prepaid-token mode. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: AionUi
slug: aionui
category: agent-workspace-ide        # multi-harness GUI; overlaps personal-assistant-gateway (IM channels, cron)
maker: "iOfficeAI GitHub org (brand AionUi); site terms name AionUi Inc., Delaware corporation; same org ships OfficeCLI"
license: Apache-2.0   # frontend (AionUi) and backend (AionCore, aionrs) repos; shipped installers built off-GitHub since 2026-08-06
repo: https://github.com/iOfficeAI/AionUi
website: https://www.aionui.com
first_public: 2025-08-07   # repo created and v1.0.0 released that day (originally a Gemini CLI GUI)
latest_release: v2.2.2, 2026-09-09   # bundles AionCore v0.2.2
release_cadence: "~3 releases/week through 2026-09-09 (170 releases in 13 months; 24 between 2026-07-20 and 2026-09-09); none since (6 weeks)"
stars: 33652 (as of 2026-10-20)
forks: 3496 (as of 2026-10-20)
contributors: 116 (as of 2026-10-20, GitHub API incl. anonymous)
primary_language: TypeScript   # backend AionCore and agent aionrs are Rust
stack: "Electron 37 + React 19 + Arco Design + UnoCSS (electron-vite); Rust AionCore backend (Axum 0.8, Tokio, SQLite/sqlx, JWT+CSRF, WebSocket) spawned as sidecar; Rust aionrs built-in agent; managed Node/npx for ACP bridges; Expo/React Native mobile client in repo"
platforms: [macos, windows, linux, web]   # WebUI from any browser; Android only via Termux+proot WebUI; iOS/Android Expo app in repo, no store listing found
agent_engine: "both: own loop (aionrs Rust agent over a JSON stream protocol) + wraps CLIs via ACP (npx-pinned adapters such as @agentclientprotocol/claude-agent-acp, @zed-industries/codex-acp, pi-acp) and direct CLI sessions; remote OpenClaw gateway"
engines_supported: [aionrs, claude-code, codex, gemini-cli, qwen-code, opencode, openclaw, hermes, pi, cursor-cli, grok-build, github-copilot, goose, kimi-cli, codebuddy, factory-droid, auggie, qoder, mistral-vibe, kiro, nanobot, snow, antigravity, kilo, mimo-code, minimax-code, omp, raw-api]
model_access: "API keys for 30+ platforms (Gemini/Vertex, Anthropic, OpenAI, Bedrock, DeepSeek, OpenRouter, xAI, many Chinese clouds), NewAPI gateway, local Ollama/LM Studio; subscription logins inherited from wrapped CLIs (and aionrs Claude.ai OAuth); vendor credits via AionUi 'Prepaid Mode' balance"
execution_env: "user host (desktop or self-run server); all agents share the chosen workspace folder; process-group containment for teardown only, no sandbox"
per_bot_computer: no   # agents run on the user's machine; no VM/container per agent
persistent_bots: "partial; 'assistants' = named personas (rules Markdown + skills + backend/model), 21 built-in; teams persist leader/teammate slots; no durable autonomous identity loop"
memory: "per-conversation history in SQLite; aionrs has project memory with auto-indexing; otherwise delegated to each wrapped CLI (CLAUDE.md, etc.)"
routines: "cron (5-field + tz), every-N interval, one-time; bound to a conversation (continue or new each run); agents can create jobs; keep-awake + missed-trigger detection; retries"
group_chat: "yes; Team mode: leader decomposes and delegates to teammates via injected Team MCP server, async mailbox, shared task board; cross-conversation @@ messaging and agent-created conversations"
coding_workspace: "yes; file tree, Changes tab with git repo/worktree discovery, diff preview, multi-tab preview/editor, open in VS Code/terminal; parallel sessions"
browser_use: "partial; in-app webview preview browser with CDP agent control in desktop mode (PRD: zero-config, take-over for logins); not available in WebUI; otherwise via MCP (Playwright/chrome-devtools)"
computer_use: no
connectors: "MCP (unified management, injected/synced per agent capability, OAuth); three-tier skills (builtin pptx/docx/xlsx/pdf/mermaid, custom, extension); Extension SDK (acpAdapters, assistants, skills, channels, themes, settings, webui); AionHub/skills.aionui.com"
channels: "Telegram, Slack, Discord, Lark/Feishu, DingTalk, WeChat (personal), WeCom; extension channels; pairing-code authorization"
mobile: "partial; responsive WebUI/PWA with QR login; Expo 'AionUi Mobile' app in repo (v0.1.0, QR scan to WebUI server), store availability unknown"
voice: "partial; speech-to-text input (OpenAI, Deepgram streaming); no voice output or calls found"
approvals: "per-agent ACP permission dialogs routed by backend (allow/deny options, sidebar badge, desktop notification); per-agent YOLO/full-auto modes (e.g. Claude bypassPermissions)"
e2e_encryption: "no; WebUI is plain HTTP on LAN unless user adds TLS/tunnel; credentials AES-256-GCM encrypted at rest in SQLite"
self_host: "yes; desktop local-first; headless WebUI via --webui --remote under xvfb/systemd; Docker and standalone web-cli exist but partly stale"
multi_user: "partial; backend has user scope, per-user filesystem isolation and an 'aionpro' identity mode (external accounts); WebUI is effectively single-admin"
pricing: "free (BYOK); optional Prepaid Mode: buy USD balance on aionui.com, deducted per token at AionUi pricing (rates not public)"
maturity: "beta/GA-ish: v2.2.x, 13 months of near-daily releases, ~920k GitHub asset downloads; but public commits fell from 152 (Aug 2026) to 6 (Sep) and 2 (Oct, docs only)"
```

## What it is

AionUi calls itself "a free, open-source, Cowork app with AI Agents" with taglines "Built-in Agent | Zero Setup | Any API Key | Multi-Agents | Remote Access | Cross-Platform | 24/7 Automation" ([README](https://github.com/iOfficeAI/AionUi#readme)). It explicitly positions against Anthropic's Claude Cowork: macOS/Windows/Linux instead of macOS only, any model instead of Claude only, WebUI plus Telegram/Lark/DingTalk/WeChat instead of desktop only, cron automation, and free instead of "$100/month" (vendor claim, [README comparison](https://github.com/iOfficeAI/AionUi#-why-choose-aionui-over-claude-cowork)).

Mental model: a chat client with a sidebar of conversations, each conversation bound to one agent backend (the built-in agent or an external CLI agent) and a workspace folder, plus a right-hand preview/file panel. On top sit "assistants" (persona presets), "teams" (multi-agent rooms), scheduled tasks, and remote entry points. It is closer to a control plane over many harnesses than to a roster of persistent teammates.

Target user: two audiences at once. (1) Non-developers doing office work (PPT/Word/Excel generation, folder organisation) who just paste an API key and use the built-in agent; 21 built-in assistants are mostly office and content presets ([README](https://github.com/iOfficeAI/AionUi#built-in-agent--install--go-zero-configuration)). (2) Developers who already have Claude Code, Codex, Hermes or OpenClaw installed and want one GUI, parallel sessions, and phone access ([README](https://github.com/iOfficeAI/AionUi#multi-agent-mode--already-have-cli-agents-bring-them-in)). The community is heavily Chinese (WeChat groups rotated 25 times, Lark/DingTalk/WeCom channels, 10 README translations) ([commits](https://github.com/iOfficeAI/AionUi/commits/main), [README](https://github.com/iOfficeAI/AionUi#readme)).

History: v1.0.0 on 2025-08-07 was a Gemini-only chat GUI ("Full Gemini API integration") ([v1.0.0 release](https://github.com/iOfficeAI/AionUi/releases/tag/v1.0.0)); the org still has a `gemini-cli-pro` repo ([org repos](https://github.com/iOfficeAI)). It then grew ACP multi-agent support, WebUI, channels, cron, teams, and in 2026 a Rust backend rewrite (AionCore, created 2026-04-09) and a Rust built-in agent (aionrs, created 2026-04-01) ([AionCore](https://github.com/iOfficeAI/AionCore), [aionrs](https://github.com/iOfficeAI/aionrs)).

## Product and UX

- **Onboarding**: install, enter any API key, start; no CLI install needed because the built-in agent is bundled ([README Quick Start](https://github.com/iOfficeAI/AionUi#-quick-start)). Installed CLI agents are auto-detected and appear as selectable backends ([README](https://github.com/iOfficeAI/AionUi#multi-agent-mode--already-have-cli-agents-bring-them-in)). Since v2.1.49 (2026-08-06) installers are not attached to GitHub releases; release notes say "Download the latest build from the official website" ([v2.2.2 notes](https://github.com/iOfficeAI/AionUi/releases/tag/v2.2.2)); the site serves files from `static.aionui.com/releases` (site bundle, fetched 2026-10-20). Homebrew `brew install aionui` is also listed ([README](https://github.com/iOfficeAI/AionUi#install)).
- **Conversations**: each conversation picks a backend, model, mode (plan/auto/YOLO where the agent supports it) and workspace; multiple run in parallel with independent context ([README](https://github.com/iOfficeAI/AionUi#multi-task-parallel-processing)). v2.2.1 added a distinct sidebar "waiting for you" state for permission requests and AskUserQuestion, with desktop notifications that name the conversation ([v2.2.1 notes](https://github.com/iOfficeAI/AionUi/releases/tag/v2.2.1)). Conversations can be forked ([AionCore migration 036](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/036_conversation_fork.sql)).
- **Preview panel** (distinctive for office work): 10+ formats including PDF, Word, Excel, PowerPoint (also .odt/.ods/.odp), code, Markdown, HTML, images and diffs, multi-tab, live-tracking file changes, editable for Markdown/code/HTML ([README](https://github.com/iOfficeAI/AionUi#preview-panel--instantly-view-ai-generated-results)). Office preview/conversion uses the org's OfficeCLI .NET binary, auto-installed by the backend ([Dockerfile comment](https://github.com/iOfficeAI/AionUi/blob/main/Dockerfile), [AionCore aionui-office crate](https://github.com/iOfficeAI/AionCore/blob/main/ARCHITECTURE.md)).
- **Assistants**: 21 built-ins (Cowork, PPT Creator, Morph PPT/3D, Word/Word Form/Excel Creator, Pitch Deck, Dashboard, Academic Paper, Financial Model, 3D Game, UI/UX Pro Max, Planning with Files, Story Roleplay with SillyTavern cards, AionUi Butler...) defined in AionCore's [assistants.json](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-app/assets/builtin-assistants/assistants.json); users create their own with Markdown rules and attached skills ([README](https://github.com/iOfficeAI/AionUi#extensible-assistants--skills)).
- **Explorer**: Files and Changes tabs; Changes re-discovers git repos and linked worktrees; VS Code-style toolbar ([v2.2.2 notes](https://github.com/iOfficeAI/AionUi/releases/tag/v2.2.2)).
- **Team view**: horizontal member "pills" with stable identity colours per slot, parallel columns or single chat, leader always first and non-removable, warm-up guidance while member runtimes start ([team runtime PRD](https://github.com/iOfficeAI/AionUi/blob/main/docs/prds/teams/team-runtime-experience.md)).
- **Desktop pet**: an animated companion window with ~20 states (working, thinking, attention, sleeping, done, error...) and a confirm window ([public/pet-states](https://github.com/iOfficeAI/AionUi/tree/main/public/pet-states), [process/pet](https://github.com/iOfficeAI/AionUi/tree/main/packages/desktop/src/process/pet)). That approvals can be answered from the pet is [INFERENCE] from `petConfirmManager.ts`.
- **Customisation**: user CSS themes ([custom theme guide](https://github.com/iOfficeAI/AionUi/blob/main/docs/guides/custom-theme.md)).

## Architecture

```
AionUi.app (Electron 37: main process + React 19 renderer, IPC bridge in preload)
  |-- spawns sidecar ---> aioncore (Rust, Axum + Tokio + SQLite)  HTTP /api/* + WebSocket /ws
  |                         |-- aionui-ai-agent: agent registry, CLI probe, ACP manager, aionrs manager, permission router
  |                         |      |-- aionrs (built-in Rust agent, JSON stream protocol)
  |                         |      |-- npx-pinned ACP adapters / native `--acp` CLIs (Claude Code, Codex, Gemini, Pi, Grok...)
  |                         |      `-- remote agents (OpenClaw gateway handshake with device keys)
  |                         |-- aionui-team (leader/teammates, mailbox, task board, Team MCP stdio bridge over per-team TCP port+token)
  |                         |-- aionui-cron, aionui-channel (Telegram/Slack/Discord/Lark/DingTalk/WeChat), aionui-mcp, aionui-office, aionui-file
  |                         `-- aionui-auth (JWT + CSRF, QR login, rate limit), aionui-realtime (event bus)
  |-- WebUI mode (--webui [--remote]): same SPA served over HTTP to browsers / PWA / Expo mobile app
  `-- in-app webview browser + CDP port for agent browser control (desktop only)
```

- **Two repos, two languages**: AionUi is the Electron frontend; AionCore builds the `aioncore` backend binary that the app launches automatically and whose port it passes to the renderer ([development guide](https://github.com/iOfficeAI/AionUi/blob/main/docs/contributing/development.md)). AionCore is a 27-crate Cargo workspace layered foundation/capability/domain/composition ([ARCHITECTURE.md](https://github.com/iOfficeAI/AionCore/blob/main/ARCHITECTURE.md), [crates/](https://github.com/iOfficeAI/AionCore/tree/main/crates)). Frontend stack: Electron ^37.10, React ^19.1, electron-vite 5, Arco Design, UnoCSS, better-sqlite3, `@agentclientprotocol/sdk` ^0.18, `@modelcontextprotocol/sdk`, `@sentry/electron` ([package.json](https://github.com/iOfficeAI/AionUi/blob/main/package.json), [AGENTS.md](https://github.com/iOfficeAI/AionUi/blob/main/AGENTS.md)).
- **Agent catalog in SQLite**: built-in agents are seeded rows in `agent_metadata` (command, args, env, `native_skills_dirs`, `behavior_policy` such as `supports_team`, `yolo_id`, capabilities, auth methods, modes, models) ([001_initial_schema.sql](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/001_initial_schema.sql)). Claude Code launches as `npx -y @agentclientprotocol/claude-agent-acp@<pinned>` and Codex as `npx -y @zed-industries/codex-acp@<pinned>` ([migration 008](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/008_builtin_acp_agents_use_npx.sql)); Gemini runs `--acp`, Cursor runs `cursor-agent acp`, Droid `acp-daemon`, Pi via `npx pi-acp`, and 18 ACP Registry agents were added in one migration ([migration 025](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/025_sync_and_add_acp_registry_agents.sql)). A lock file pins registry packages including `@xai-official/grok` (Grok Build), Kilo, MiniMax Code, MiMo, DeepAgents and Pi ([acp-registry-npx-lock.json](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-runtime/resources/acp-registry-npx-lock.json)); Oct 2026 commits are mostly bot-like "bump registry pins to probed versions" and "verify claude against 2.1.28x" ([AionCore commits](https://github.com/iOfficeAI/AionCore/commits/main)).
- **Auto-detection**: `cli_probe.rs` resolves each agent's binary on an enhanced PATH, runs `--version` with a 5 s inline budget and a 30 s background recheck, and classifies failures (`command_not_found`, `version_probe_failed`, `version_probe_timeout`, invalid package lock) so slow CLIs are not marked broken ([cli_probe.rs](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-ai-agent/src/cli_probe.rs)). A managed Node runtime is shipped for npx bridges ([aionui-runtime](https://github.com/iOfficeAI/AionCore/tree/main/crates/aionui-runtime/src)). Users can add custom agents (probed), and extensions can contribute `acpAdapters` over CLI or HTTP with health checks and API-key fields ([example manifest](https://github.com/iOfficeAI/AionUi/blob/main/examples/e2e-full-extension/aion-extension.json)).
- **Wire protocols**: ACP over stdio for external agents ([manager/acp](https://github.com/iOfficeAI/AionCore/tree/main/crates/aionui-ai-agent/src/manager/acp), [protocol/acp.rs](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-ai-agent/src/protocol/acp.rs)) with dialect handling and npx cache repair; aionrs uses its own JSON stream protocol that lets the host inject MCP servers at runtime ([aionrs README](https://github.com/iOfficeAI/aionrs#readme)); backend-to-UI is REST + a single `/ws` WebSocket with `{domain}.{actionName}` events ([ARCHITECTURE.md](https://github.com/iOfficeAI/AionCore/blob/main/ARCHITECTURE.md)). There is also a cc-switch integration that reads provider env from that tool ([cc_switch](https://github.com/iOfficeAI/AionCore/tree/main/crates/aionui-ai-agent/src/cc_switch)).
- **Built-in agent (aionrs)**: Rust tool-use agent with Read/Write/Edit/ExecCommand/Grep/Glob/ViewImage/Spawn, skills, hooks, plan mode, MCP client, session persistence, project memory, context compaction, prompt caching, and "OAuth login: use Claude.ai subscription directly, no API key needed" ([aionrs README](https://github.com/iOfficeAI/aionrs#readme)).
- **Models and auth**: 30+ API platforms, NewAPI gateway, local models via custom endpoint ([README](https://github.com/iOfficeAI/AionUi#any-api-key-full-cowork-agent-power)); external CLIs keep their own login. Provider keys, channel credentials and remote-agent tokens are AES-256-GCM encrypted with a key derived from a per-install secret, decoupled from the JWT secret in migration 042 ([042_add_encryption_secret.sql](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/042_add_encryption_secret.sql)).
- **Execution environment**: agents run as child processes on the host in the selected workspace; `aionui-process` containment is a process-group kill "orthogonal to any security sandbox", with Job Object/cgroup tiers "intentionally not built" ([containment.rs](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-process/src/containment.rs)).
- **State**: SQLite tables for users, providers, conversations, messages, artifacts, ACP sessions, agents, remote agents, MCP servers, OAuth tokens, assistants, teams, mailbox, team tasks, cron jobs ([schema](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/001_initial_schema.sql)); "All data is stored locally in a SQLite database" (vendor claim, [README Q&A](https://github.com/iOfficeAI/AionUi#quick-qa)). No cloud sync in BYOK mode per site terms.
- **Remote and mobile**: `--webui` starts an embedded server (default port 25808 in current builds, docs also say 3000); `--remote` binds to the LAN; QR or password login; systemd recipe; "Use only on trusted networks" ([WebUI guide](https://github.com/iOfficeAI/AionUi/blob/main/docs/guides/webui.md)). Headless Linux requires Electron under `xvfb-run` ([server deploy guide](https://github.com/iOfficeAI/AionUi/blob/main/docs/guides/deploy-server.md)); a no-Electron `@aionui/web-host`/`aionui-web` CLI exists ([web-host README](https://github.com/iOfficeAI/AionUi/blob/main/packages/web-host/README.md), [web-cli](https://github.com/iOfficeAI/AionUi/blob/main/packages/web-cli/package.json)), but a user reports its CDN tarball returns 403 ([issue #4193](https://github.com/iOfficeAI/AionUi/issues/4193)). Internet access is left to the user (wiki tutorial) ([README](https://github.com/iOfficeAI/AionUi#cowork-from-anywhere)). The Expo app (`ai.resopod.aionui`) scans the WebUI `/qr-login` QR and talks REST+WebSocket ([app.config.ts](https://github.com/iOfficeAI/AionUi/blob/main/mobile/app.config.ts), [connect.tsx](https://github.com/iOfficeAI/AionUi/blob/main/mobile/app/connect.tsx)); last touched 2026-07-15 ([commits](https://github.com/iOfficeAI/AionUi/commits/main/mobile)).
- **Extension surface**: MCP with unified management and per-agent injection ([README](https://github.com/iOfficeAI/AionUi#multi-agent-mode--already-have-cli-agents-bring-them-in)); three-tier skills delivered through "an AionUi-owned view instead of being placed in the workspace" since AionCore 0.2.1 ([v2.2.1 notes](https://github.com/iOfficeAI/AionUi/releases/tag/v2.2.1)); Extension SDK contributing ACP adapters, assistants, skills, channels, themes, settings and WebUI pages ([examples/](https://github.com/iOfficeAI/AionUi/tree/main/examples)); an extension hub repo ([AionHub](https://github.com/iOfficeAI/AionHub)) and `skills.aionui.com` (site bundle).

## Capabilities in detail

- **24/7 cowork, concretely**: (1) scheduled tasks: cron with timezone, every-N, or one-time; each job bound to a conversation with "continue" or "new conversation each time"; per-job model, workspace and reasoning effort; agents can create jobs mid-conversation; keep-awake while jobs are active and missed-trigger detection after wake ([README scheduled tasks](https://github.com/iOfficeAI/AionUi#scheduled-tasks--cowork-on-autopilot)); schema adds `created_by user|agent`, `last_status ok|error|skipped|missed` and `max_retries 3` ([cron_jobs schema](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/001_initial_schema.sql)). (2) Remote reach via WebUI and IM channels so a phone can drive the desktop's agents. It is still the user's own machine that must stay on; there is no hosted runtime in BYOK mode [INFERENCE from architecture and site terms].
- **Multi-agent (Team mode)**: leader receives the task, delegates to teammates via a built-in Team MCP server; teammates run in parallel, exchange results through an async mailbox (`message`, `idle_notification`, `shutdown_request`) and a task board with `blocked_by`/`blocks` dependencies; all share one workspace; teammates can be added/removed live; silent agents auto-escalate to failed ([README Team Mode](https://github.com/iOfficeAI/AionUi#team-mode--coordinated-multi-agent-collaboration), [schema](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/001_initial_schema.sql)). Team routing uses a per-team TCP port and auth token behind a fixed MCP server name, after a 64-char Anthropic tool-name limit bug ([team_mcp.rs](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-api-types/src/team_mcp.rs)). Leader backends: Claude Code, Codex, Hermes, Gemini, Snow, Aion CLI; other ACP agents with `mcpCapabilities.stdio` are auto-supported ([README](https://github.com/iOfficeAI/AionUi#team-mode--coordinated-multi-agent-collaboration)). Outside teams, `@@` mentions route messages across conversations and agents can create new conversations ([v2.2.1](https://github.com/iOfficeAI/AionUi/releases/tag/v2.2.1), [v2.2.2](https://github.com/iOfficeAI/AionUi/releases/tag/v2.2.2) notes).
- **Persistent bots**: assistants are reusable personas, not living agents; no per-assistant memory file, inbox, or self-wake beyond cron jobs. Channel bots bind an IM account to a chosen agent/model ([channels PRD](https://github.com/iOfficeAI/AionUi/blob/main/docs/prds/remote/channels/channels.md)).
- **Office and file workflows**: built-in `pptx`, `docx`, `xlsx`, `pdf`, `mermaid` skills; Morph-transition PPTX, academic papers, Excel analysis/charts, batch rename/organise folders, all producing editable files previewed in-app ([README](https://github.com/iOfficeAI/AionUi#office-assistants--ppt-word--excel)). Image generation/editing via Gemini-family models ([README](https://github.com/iOfficeAI/AionUi#ai-image-generation--editing)).
- **Browser**: preview panel already shows agent-opened pages; the agent-browser PRD specifies a zero-config in-app browser the agent drives (open, click, type, scroll, read, screenshot), user take-over for logins, globally shared persistent login state, and explicitly not in WebUI because there is no `<webview>`/CDP there ([agent-browser PRD](https://github.com/iOfficeAI/AionUi/blob/main/docs/prds/agent-browser/prd.md)). How much of the PRD shipped is unknown; a community PR adding a browser automation engine with persistent profiles is open ([PR #4318](https://github.com/iOfficeAI/AionUi/pull/4318)).
- **Channels**: Telegram, Slack, Discord, Lark/Feishu, DingTalk, WeChat, WeCom, plus extension channels; bot token, test, then pending pairing requests that the owner approves ([channels PRD](https://github.com/iOfficeAI/AionUi/blob/main/docs/prds/remote/channels/channels.md), [aionui-channel plugins](https://github.com/iOfficeAI/AionCore/tree/main/crates/aionui-channel/src/plugins)).
- **Remote agents**: currently only OpenClaw over its gateway protocol with device keypair pairing ("目前只支持远程连接 OpenClaw") ([remote-agent PRD](https://github.com/iOfficeAI/AionUi/blob/main/docs/prds/conversations/remote/remote-agent.md), [remote_agents schema](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/001_initial_schema.sql)).
- **Voice**: speech input with OpenAI and Deepgram (incl. streaming) STT ([aionui-shell stt](https://github.com/iOfficeAI/AionCore/tree/main/crates/aionui-shell/src), [SpeechInputButton.tsx](https://github.com/iOfficeAI/AionUi/blob/main/packages/desktop/src/renderer/components/chat/SpeechInputButton.tsx)).
- **Team/multi-user features**: user scope and per-user file isolation exist for an `aionpro` identity mode with external accounts ([030_user_scope.sql](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/030_user_scope.sql), [per_user_fs_isolation_e2e.rs](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-app/tests/per_user_fs_isolation_e2e.rs)); the open-source WebUI is a single admin login.

## Security and trust model

- **Approvals**: ACP permission requests are routed by the backend to the UI and back, keyed by tool-call ID, cancelled on stop ([permission_router.rs](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-ai-agent/src/manager/acp/permission_router.rs)); each team member has its own dialog and sidebar badge ([README](https://github.com/iOfficeAI/AionUi#team-mode--coordinated-multi-agent-collaboration)). YOLO modes are per agent; Claude Code's seeded `yolo_id` is `bypassPermissions` ([schema](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/001_initial_schema.sql)). Cron jobs run unattended, so approvals for scheduled runs depend on the chosen mode [INFERENCE].
- **Sandboxing**: none; process containment is lifecycle-only ([containment.rs](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-process/src/containment.rs)). Team members share one folder.
- **Network exposure**: WebUI `--remote` serves plain HTTP on the LAN with JWT + double-submit CSRF, bcrypt passwords, login rate limiting, QR tokens ([aionui-auth](https://github.com/iOfficeAI/AionCore/tree/main/crates/aionui-auth/src), [WebUI guide](https://github.com/iOfficeAI/AionUi/blob/main/docs/guides/webui.md)). TLS/tunnel is the user's job. Channel bots let anyone who pairs (after owner approval) drive an agent with host file access.
- **Secrets**: AES-256-GCM at rest ([migration 042](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/042_add_encryption_secret.sql)); open PRs say `ApiKeyManager.getStatus` returns plaintext keys ([#4139](https://github.com/iOfficeAI/AionUi/pull/4139), [#4125](https://github.com/iOfficeAI/AionUi/pull/4125), both open).
- **Fixed issues**: path traversal in HTML renderer resource inlining and in the image-generation MCP tool (Aug 2026) ([#4097](https://github.com/iOfficeAI/AionUi/pull/4097), [#3906](https://github.com/iOfficeAI/AionUi/pull/3906)); SQL-injection and XSS fixes in a July 2026 audit PR that is still open ([#3521](https://github.com/iOfficeAI/AionUi/pull/3521)). No published GitHub security advisories for AionUi or AionCore (API, 2026-10-20).
- **Telemetry**: Sentry crash/error reporting with an analytics ID when the build has `SENTRY_DSN` ([sentry.ts](https://github.com/iOfficeAI/AionUi/blob/main/packages/desktop/src/sentry.ts)); no opt-out found in that file. Site terms: BYOK traffic goes device-to-provider and is not seen by AionUi; Prepaid Mode routes requests through AionUi backend with limited retention (site terms bundle, fetched 2026-10-20).
- **Supply chain**: built-in agents run `npx -y <package>@<pin>` from npm at session start ([migration 008](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/008_builtin_acp_agents_use_npx.sql)); pins are bumped near-daily.
- **Build provenance gap**: a user's live process list shows the official Linux build launching `aioncore ... --identity-mode aionpro`, which disables password login and broke headless WebUI ([issue #4193](https://github.com/iOfficeAI/AionUi/issues/4193), open). The public launcher never passes that flag ([backend-launcher.ts](https://github.com/iOfficeAI/AionUi/blob/main/packages/web-host/src/backend-launcher.ts)), while AionCore supports `Local | Webui | Aionpro` modes, with AionPro requiring `AIONCORE_BOOTSTRAP_SECRET` ([cli.rs](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-app/src/cli.rs)). [INFERENCE] Shipped installers are built from code or config that is not public, so the Apache-2.0 repo is not a reproducible description of what users run.
- **Prompt injection in fetched material**: none observed.

## Traction and momentum

- **GitHub (as of 2026-10-20)**: 33,652 stars, 3,496 forks, 149 watchers, 877 open issues, 116 contributors, ~5,990 commits, 170 releases ([repo API](https://github.com/iOfficeAI/AionUi)). Issue/PR numbers reach #4338. Sibling repos: OfficeCLI 32,209 stars (created 2026-03-15), AionCore 121, aionrs 128, AionHub 45 ([org](https://github.com/iOfficeAI)).
- **Star organicity**: GitHub's stargazer endpoints returned 404/empty on 2026-10-20, so the timeline could not be sampled. Indirect signals are consistent with real use: a 10.4% fork ratio, 116 contributors, ~920k cumulative downloads of GitHub release assets up to v2.1.47 (2026-08-05; often 3k-12k per release), 4,300+ issues/PRs, Trendshift badge ([releases API](https://github.com/iOfficeAI/AionUi/releases)). Growth was helped by promotion: a contributor bonus of free Kimi "Allegretto" plans ($39/mo value) with affiliate links, and featured YouTube videos by Julian Goldie SEO (27K and 11K views) and WorldofAI ([README](https://github.com/iOfficeAI/AionUi#readme)). The repo name/creation date (2025-08-07) matches v1.0.0, so no rename inflation. OfficeCLI reaching 32k stars in seven months is notable, but not verified here.
- **Cadence and slowdown**: ~3 releases/week from 2025-08 to 2026-09-09; commits 167 (Jul 2026), 152 (Aug), 6 (Sep), 2 (Oct, both WeChat QR updates) in AionUi; AionCore 161/164/36/11; aionrs 111/33/0/0 ([commits API](https://github.com/iOfficeAI/AionUi/commits/main)). On 2026-10-14 maintainers closed a batch of old community PRs unmerged ([PR list](https://github.com/iOfficeAI/AionUi/pulls?q=is%3Apr+is%3Aclosed)). Community PRs and issues keep arriving.
- **Business model**: free BYOK app; "Prepaid Mode" where users buy a USD balance and AionUi "will deduct ... your actual token consumption multiplied by AionUi's then-current token pricing", with AionUi possibly picking the model; operated by AionUi Inc. (Delaware) (site terms in [aionui.com](https://www.aionui.com) bundle, fetched 2026-10-20). An "AionPro" account mode exists in the backend, including a one-shot "AionUi->AionPro data adoption" ([AionCore CHANGELOG](https://github.com/iOfficeAI/AionCore/blob/main/CHANGELOG.md)). Affiliate links to Kimi plans in README. The website bundle contains leftover account-SDK code referencing Pionex (`com.pionex.client`, `download.pionex.com`, Pionex Zendesk) ([aionui.com](https://www.aionui.com) JS bundle); [INFERENCE] the team shares code or staff with the Pionex crypto-exchange group. The mobile bundle id `ai.resopod.aionui` hints at another related entity ([app.config.ts](https://github.com/iOfficeAI/AionUi/blob/main/mobile/app.config.ts)).
- **Press**: community WeChat articles ("5500 Stars: How Open Source Breaks Anthropic's AI Tool Moat") and YouTube reviews linked from README ([README](https://github.com/iOfficeAI/AionUi#community-articles)); no major press found.

## Strengths

- Widest harness coverage found in the category: ~30 agents via ACP plus a built-in agent, with a pinned-npx catalog, version probing and registry sync that absorb upstream churn ([migration 025](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/025_sync_and_add_acp_registry_agents.sql), [cli_probe.rs](https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-ai-agent/src/cli_probe.rs)).
- Zero-setup path for non-developers (bundled agent + any API key) alongside power-user CLI mode.
- Office-document focus (OfficeCLI, in-app PPT/Word/Excel preview) that coding-first rivals lack.
- Real automation and reach primitives already shipped: cron with agent-created jobs, keep-awake, IM channels incl. WeChat/Lark/DingTalk, WebUI with QR login.
- Team mode built on standard pieces (MCP tool injection + mailbox + task board) that work across heterogeneous CLIs.
- Large contributor base, extension SDK, permissive license for the published code.

## Weaknesses and risks

- **Openness is eroding** [INFERENCE from evidence]: installers left GitHub (2026-08-06), shipped builds run a non-public `aionpro` identity mode ([#4193](https://github.com/iOfficeAI/AionUi/issues/4193)), public commits nearly stopped after 2026-09-09, old PRs mass-closed. Forking the repo may not reproduce the shipped product.
- **Security posture**: no sandbox, plain-HTTP LAN WebUI, IM bots with host file access, open PRs about plaintext key exposure and a stalled security-audit PR.
- **Not persistent teammates**: assistants are presets; memory is delegated to each CLI; no per-agent computer; the host must stay awake. Far from Grok Bot's per-teammate cloud computer.
- **Breadth over depth**: 30 backends × modes × team support means many capability mismatches; open bugs such as Codex sub-agent completion breaking team turns ([#4338](https://github.com/iOfficeAI/AionUi/issues/4338)) and WebUI team mode re-fetching history ([#4120](https://github.com/iOfficeAI/AionUi/issues/4120)).
- **Headless story is fragile**: Electron under xvfb, stale Dockerfile referencing a missing `scripts/build-server.mjs` ([Dockerfile](https://github.com/iOfficeAI/AionUi/blob/main/Dockerfile), [scripts/](https://github.com/iOfficeAI/AionUi/tree/main/scripts)), web-host README still says "placeholder implementations" ([web-host README](https://github.com/iOfficeAI/AionUi/blob/main/packages/web-host/README.md)).
- **ToS exposure**: aionrs advertises using a Claude.ai subscription via OAuth ([aionrs README](https://github.com/iOfficeAI/aionrs#readme)); third-party use of consumer subscriptions is a platform-policy risk [INFERENCE].
- **Telemetry and provenance**: Sentry on by default in official builds without a visible opt-out in source.

## Ideas worth taking for Memoshi

- **Agent catalog as data**: seed harness definitions (command, args, pinned adapter version, capabilities, yolo mode, skills dirs) in a DB table with migrations, not code; lets you ship new harnesses without app releases.
- **Two-budget CLI probe** (5 s inline, 30 s background, classified errors): avoids marking slow-but-healthy CLIs as broken at startup.
- **Team via MCP injection + mailbox + task board**: harness-agnostic multi-agent coordination that works with any ACP agent supporting stdio MCP; adopt, but give each teammate its own workspace/worktree instead of one shared folder.
- **Cron jobs bound to a conversation** with "continue vs new each run", `created_by agent`, missed/skipped status, keep-awake: copy this schema almost verbatim for routines.
- **"Waiting for you" as a first-class sidebar state** plus notification naming the conversation: cheap, high-value UX for many parallel agents.
- **Pairing-code approval for IM channels**: owner approves each new chat user; apply to every inbound channel.
- **Avoid**: plain-HTTP LAN remote access, unsandboxed shared folders for teams, and shipping binaries that differ from public source; Memoshi should offer an E2E relay and reproducible builds if it claims openness.
- **Office preview as a differentiator**: a rendered PPTX/DOCX/XLSX preview panel makes non-coding outputs reviewable; consider OfficeCLI (Apache-2.0) rather than building one.

## Open questions

- What exactly is AionPro (hosted accounts, paid tier, team product)? Watch aionui.com after login, AionCore `aionpro` code paths, and future releases.
- Is development continuing in a private repo? Compare future installer versions on `static.aionui.com` with public tags.
- Prepaid Mode token prices and which models it routes to: requires an account on aionui.com.
- Did the in-app agent browser PRD ship? Test current build or read `packages/desktop/src/process` browser code.
- Mobile app store availability for `ai.resopod.aionui`: search App Store/Play listings.
- Organic star curve: GitHub stargazer API was unavailable; retry later or use a third-party star tracker.
- Relationship to Pionex and "resopod": WHOIS, company filings, or ask the maker.

## Sources

1. https://github.com/iOfficeAI/AionUi (README, repo/contributor/commit/release API stats; fetched 2026-10-20)
2. https://github.com/iOfficeAI/AionUi/releases/tag/v2.2.2, https://github.com/iOfficeAI/AionUi/releases/tag/v2.2.1, https://github.com/iOfficeAI/AionUi/releases/tag/v1.0.0
3. https://github.com/iOfficeAI/AionUi/blob/main/AGENTS.md
4. https://github.com/iOfficeAI/AionUi/blob/main/docs/contributing/development.md
5. https://github.com/iOfficeAI/AionUi/blob/main/docs/contributing/file-structure.md
6. https://github.com/iOfficeAI/AionUi/blob/main/docs/guides/webui.md
7. https://github.com/iOfficeAI/AionUi/blob/main/docs/guides/deploy-server.md
8. https://github.com/iOfficeAI/AionUi/blob/main/docs/guides/cdp.md
9. https://github.com/iOfficeAI/AionUi/blob/main/docs/prds/agent-browser/prd.md
10. https://github.com/iOfficeAI/AionUi/blob/main/docs/prds/remote/channels/channels.md
11. https://github.com/iOfficeAI/AionUi/blob/main/docs/prds/conversations/remote/remote-agent.md
12. https://github.com/iOfficeAI/AionUi/blob/main/docs/prds/teams/team-runtime-experience.md
13. https://github.com/iOfficeAI/AionUi/blob/main/package.json
14. https://github.com/iOfficeAI/AionUi/blob/main/packages/desktop/src/sentry.ts
15. https://github.com/iOfficeAI/AionUi/blob/main/packages/web-host/README.md and https://github.com/iOfficeAI/AionUi/blob/main/packages/web-host/src/backend-launcher.ts
16. https://github.com/iOfficeAI/AionUi/blob/main/packages/web-cli/package.json
17. https://github.com/iOfficeAI/AionUi/blob/main/Dockerfile
18. https://github.com/iOfficeAI/AionUi/blob/main/mobile/app.config.ts and https://github.com/iOfficeAI/AionUi/blob/main/mobile/app/connect.tsx
19. https://github.com/iOfficeAI/AionUi/tree/main/examples (extension manifests)
20. https://github.com/iOfficeAI/AionUi/issues/4193, /issues/4338, /issues/4120, /pull/4139, /pull/4125, /pull/4097, /pull/3906, /pull/3521, /pull/4318
21. https://github.com/iOfficeAI/AionCore (repo, ARCHITECTURE.md, CHANGELOG.md, commits, releases)
22. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/001_initial_schema.sql
23. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/008_builtin_acp_agents_use_npx.sql
24. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/025_sync_and_add_acp_registry_agents.sql
25. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/030_user_scope.sql
26. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-db/migrations/042_add_encryption_secret.sql
27. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-runtime/resources/acp-registry-npx-lock.json
28. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-ai-agent/src/cli_probe.rs
29. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-ai-agent/src/manager/acp/permission_router.rs
30. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-api-types/src/team_mcp.rs
31. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-process/src/containment.rs
32. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-app/src/cli.rs
33. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-app/tests/per_user_fs_isolation_e2e.rs
34. https://github.com/iOfficeAI/AionCore/blob/main/crates/aionui-app/assets/builtin-assistants/assistants.json
35. https://github.com/iOfficeAI/aionrs (README)
36. https://github.com/iOfficeAI/OfficeCLI, https://github.com/iOfficeAI/AionHub, https://github.com/iOfficeAI (org API)
37. https://www.aionui.com (SPA JS bundle: terms of service, privacy policy, Prepaid/BYOK mode, AionUi Inc. address, static.aionui.com and skills.aionui.com endpoints; fetched 2026-10-20)
38. https://x.com/AionUi/status/2079493379914961069 (Kimi contributor bonus campaign, linked from README; not fetched)
