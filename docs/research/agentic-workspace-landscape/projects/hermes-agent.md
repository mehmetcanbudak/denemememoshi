# Hermes Agent (Nous Research)

> A self-hosted, MIT-licensed Python agent runtime with a skill-writing learning loop, a 25+ channel messaging gateway, cron, subagents, and seven terminal backends. Since 2026-08-31 its own Electron desktop app also ships a Grok-Bot-style "Bot Mode" (roster, forever-chats, routines, group rooms, per-bot screens), and Nous sells hosted instances (Hermes Cloud) and a credit subscription (Nous Portal). Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Hermes Agent
slug: hermes-agent
category: personal-assistant-gateway   # also ships oss-bot-roster-desktop (Bot Mode) and a hosted tier (Hermes Cloud)
maker: Nous Research
license: MIT
repo: https://github.com/NousResearch/hermes-agent
website: https://hermes-agent.nousresearch.com
first_public: 2026-03-12            # first GitHub release v2026.3.12; repo created 2025-07-22; press says launched February 2026
latest_release: v0.22.2, 2026-10-15
release_cadence: "41 tagged releases 2026-03-12..2026-10-15 (~1.4/week); stable SemVer channel since v0.21.6, plus a rolling main channel"
stars: 255361 (as of 2026-10-20)
forks: 55611 (as of 2026-10-20)
contributors: 4631 (GitHub API incl. anonymous, as of 2026-10-20)
primary_language: Python (core), TypeScript (desktop, TUI, dashboard)
stack: "Python 3.14 agent core + SQLite/FTS5 state; Electron 40 + React 19 + Vite 8 + Tailwind 4 desktop (noVNC, xterm); Ink/React TUI; Vite/React web dashboard"
platforms: [macos, windows, linux, android, web, cli]   # android = Termux APT package; web = local dashboard / Hermes Cloud dashboard
agent_engine: own loop (AIAgent, 3 API modes); optional Codex app-server runtime for OpenAI turns; ACP server for editors
engines_supported: [raw-api, codex, copilot-acp]
model_access: API keys (40+ provider plugins) | subscription logins (ChatGPT/Codex, SuperGrok/X Premium+, Claude Max extra-usage, Copilot, Qwen, MiniMax) | local models (llama.cpp one-click, Ollama, LM Studio) | vendor credits (Nous Portal)
execution_env: user-chosen: local host, Docker, SSH, Singularity, Modal, Daytona, Vercel Sandbox; Hermes Cloud = Nous-hosted container per agent
per_bot_computer: partial — Bot Screen gives each profile its own Xfce/VNC desktop and browser profile on a Linux gateway host (shared OS user, not a security boundary); Hermes Cloud gives each agent its own container
persistent_bots: yes — a Bot is a profile (~/.hermes/profiles/<name>/) with SOUL.md, model pin, skills, memory, avatar, voice, one canonical forever Bot Chat
memory: MEMORY.md (2,200 chars) + USER.md (1,375 chars) frozen into the prompt, FTS5 session_search over SQLite, background review that writes memory and skills; optional external provider (Honcho, Mem0, Supermemory, etc.)
routines: yes — cron (natural language or cron expressions, skills attached, platform delivery, script-only mode), webhook-triggered jobs, /heartbeat, /goal loops, per-Bot Routines pane
group_chat: yes — group rooms of 2-6 Bots, @mentions, message_agent bot-to-bot DMs, cross-machine relay, A2A v1.0, Kanban board shared across profiles
coding_workspace: yes — file tools, terminal, git review and worktrees, diffs, LSP, ACP for VS Code/Zed/JetBrains
browser_use: yes — local (Browser Use CLI, Camofox, Lightpanda) and cloud (Browser Use, Browserbase, Firecrawl) backends; password-manager login fill
computer_use: yes — background computer use via cua-driver MCP on macOS/Windows/Linux, with any tool-capable model
connectors: MCP client and server + Nous-hosted connectors (e.g. Linear, Notion) + 600-entry plugin catalog
channels: Telegram, Discord, Slack, WhatsApp (Web and Cloud API), Signal, SMS, email, iMessage (BlueBubbles, Photon), Matrix, Mattermost, Teams, Google Chat, LINE, Feishu, WeCom, Weixin, QQ, DingTalk, Yuanbao, SimpleX, IRC, ntfy, Home Assistant, webhooks, OpenAI-compatible API server
mobile: partial — no first-party iOS/Android app found; reach via messaging channels, Termux package, community PWA
voice: yes — STT/TTS, streaming TTS with barge-in, wake word, Discord voice channels, per-Bot voices
approvals: dangerous-command approval (smart/manual/off), hardline blocklist, deny-by-default for cron/unattended runs, optional write approval for memory and skill changes, DM pairing and allowlists
e2e_encryption: no own E2E layer; inherits the channel's encryption (e.g. Signal, SimpleX) [INFERENCE]
self_host: yes — install script, Docker image, Nix flake, MSIX/Microsoft Store, signed macOS build
multi_user: partial — gateway allowlists and DM pairing; Hermes Business (team balance, per-member caps, shared org skills) is a paid Portal tier
pricing: "OSS free; Nous Portal Free $0 / Plus $20 / Super $100 / Ultra $200 per month with 1.1x credits; Hermes Cloud billed daily from credit (~$0.29/day small running, $0.03/day stopped); Business usage-based, Enterprise contact sales"
maturity: GA-leaning beta — v0.x SemVer, signed stable releases since 2026-10, but very high churn (~24k commits in 6 weeks) and multiple 2026 CVEs
```

## What it is

Hermes Agent is Nous Research's open-source "self-improving AI agent". It is a long-running personal agent that lives on your own machine, a $5 VPS, or serverless infrastructure, and that you talk to from a terminal, a desktop app, or a chat app ([README](https://github.com/NousResearch/hermes-agent/blob/main/README.md)). Its pitch is a "closed learning loop": it writes and patches reusable skills after hard tasks, curates its own memory, searches past sessions, and models the user across sessions ([README](https://github.com/NousResearch/hermes-agent/blob/main/README.md)). The README calls it "the only agent with a built-in learning loop" (vendor claim).

The mental model has three layers [INFERENCE from the docs]:

1. **Runtime and control plane.** One Python `AIAgent` core serves the CLI, TUI, gateway, cron, ACP, API server, and batch runner ([architecture.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/architecture.md)).
2. **Messenger-style roster.** In Hermes Desktop, Bot Mode turns profiles into named Bots shown as contacts, each with a permanent chat, routines, and group rooms ([bot-mode.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/bot-mode.md)).
3. **Paid hosting layer.** Nous Portal bundles models and tools under one subscription, and Hermes Cloud runs always-on instances ([nous-portal.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/nous-portal.md), [Hermes Cloud](https://portal.nousresearch.com/cloud)).

Target users have widened over time. Early adopters were technical people who self-host; v0.22.0 adds a guided first-launch chat on a free trial model so newcomers can start without an API key ([v0.22.0 notes](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.0)), and there are team tiers ([Hermes Business](https://portal.nousresearch.com/business)).

Hermes is the main open-source competitor to OpenClaw. It ships a first-class OpenClaw importer ([README](https://github.com/NousResearch/hermes-agent/blob/main/README.md)) and a Claude Code/Codex importer ([import-from-other-agents.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/import-from-other-agents.md)).

## Product and UX

**Front ends.** All of them share one config, session database, skill set, and memory ([desktop.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/desktop.md)):
- Classic CLI (`hermes`).
- TUI (`hermes --tui`), the recommended interactive surface ([tui.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/tui.md)).
- Local web dashboard (`hermes dashboard` on 127.0.0.1:9119) for config, keys, MCP, pairing, cron, skills, logs, and analytics ([web-dashboard.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/web-dashboard.md)).
- Hermes Desktop (Electron), first shipped in v0.16.0 on 2026-06-05 ([release](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.6.5)).

**Onboarding.** `curl | bash` or the PowerShell one-liner, then `hermes setup`. `hermes setup --portal` does the Nous Portal OAuth, picks a model, and enables the Tool Gateway in one step ([README](https://github.com/NousResearch/hermes-agent/blob/main/README.md)). In v0.22.0 a fresh desktop install opens a card-by-card setup chat on the free `nous/welcome` model: name, accent color, layout, apps to connect, plugins, a tour, and up to four suggested first tasks ([v0.22.0](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.0)).

**Desktop.** Features ([desktop.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/desktop.md)):
- Chat with streaming tool activity.
- Preview rail for web pages, files, and tool output.
- File browser, artifacts, multi-pane tabs, terminal pane.
- Live subagent panel with Steer and Stop.
- Git review and worktrees, Memory Graph, Quick Entry, voice, HUD mode, a plugin SDK.
- A multi-connection registry: local runtime, remote `hermes serve` gateways (LAN/Tailscale/internet), SSH hosts, and Hermes Cloud instances, all in one roster ([multi-connection-desktop.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/multi-connection-desktop.md)).

**Bot Mode** (built in and on by default since v0.21.0, 2026-08-31) ([release](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.8.31), [bot-mode.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/bot-mode.md)):
- **Roster.** A Bots tab next to Sessions, one row per profile with avatar, last-message preview, and unread state. It also has an "Active now" strip, search, hide/unhide, and user-made sections. Section membership is stored in profile metadata so it follows the Bot across desktops.
- **Creating a Bot.** "New Agent" asks for Name, Title, and Description; the Bot introduces itself as the first message. An Advanced panel can clone from a profile, pin a model/provider, set a custom SOUL.md, enable individual skills/toolsets/MCP servers, copy API keys, and choose which machine the Bot lives on ("Create on").
- **Forever-chat.** Each Bot has one canonical Bot Chat. `/new` inside it is rerouted to `/compact` so the relationship never forks.
- **Routines pane.** Docked beside the chat. Routines are ordinary cron jobs named `[bot:<name>] <routine>`, and their runs land in the Bot's chat.
- **Group rooms.** 2-6 Bots. Stop/hold semantics are tied to @mentions. Each member's turn gets the room transcript since its last turn (about 200 messages or 32k characters).
- **Bot-to-bot messaging.** Via `message_agent`, including relaying to Bots on other connected machines.

**Origin of Bot Mode.** Nous first published it as a separate desktop plugin, [NousResearch/Hermes-Bot-Mode](https://github.com/NousResearch/Hermes-Bot-Mode), created 2026-08-13, two days after Grok Bot launched on 2026-08-11. The repo was archived once Bot Mode moved in-tree at `apps/desktop/src/plugins/hermes-bots/` via PR #87886 ([archive note](https://github.com/NousResearch/Hermes-Bot-Mode/blob/main/README.md)).

**Bot Screen** (v0.22.0). On a headless Linux gateway each Bot gets its own Xfce desktop over TigerVNC, streamed into the desktop app through noVNC. The user can take over for a login, 2FA, CAPTCHA, or payment step and then hand control back ([bot-screen.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/bot-screen.md)).

**What stands out:**
- The Bot is not a new primitive. It is a profile, so everything works from the CLI too (`hermes -p <bot> chat`, `hermes cron list`).
- `/goal` runs Ralph-style loops checked by a judge model ([goals.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/goals.md)).
- `/heartbeat` gives a session one recurring in-thread prompt ([heartbeat.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/heartbeat.md)).
- `/learn` turns a folder, URL, or book into a knowledge-base skill ([skills.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/skills.md)).

## Architecture

**Components** (from [architecture.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/architecture.md)):

```text
Entry points: CLI (cli.py) | Gateway (gateway/run.py) | ACP (acp_adapter/) | API server | Batch runner | Python library
        -> AIAgent (run_agent.py facade; loop in agent/conversation_loop.py + agent/turn_*.py)
           prompt builder | provider resolution (3 API modes) | tool registry (70+ tools, ~28 toolsets)
        -> Session storage: SQLite + FTS5 (hermes_state*.py, gateway/session.py)
        -> Tool backends: terminal (7), browser (5), web (4), MCP, file, vision...
```

As of v0.22.0, one messaging gateway and one desktop backend per machine serve every profile, replacing the earlier one process per profile ([v0.22.0](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.0)).

**Tech stack.**
- Python core pinned to 3.14 via `pyproject.toml`, with every direct dependency exact-pinned after the 2026-05 "Mini Shai-Hulud" PyPI worm ([pyproject.toml](https://github.com/NousResearch/hermes-agent/blob/main/pyproject.toml)).
- Its own package manager, `hermes pm`, uses uv to manage hash-checked environments ([v0.22.0](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.0)).
- Desktop: Electron 40.10, React 19.2, Vite 8, Tailwind 4, @novnc/novnc, @xterm/xterm ([apps/desktop/package.json](https://github.com/NousResearch/hermes-agent/blob/main/apps/desktop/package.json)).
- TUI: a forked Ink (`@hermes/ink`) with React ([ui-tui/package.json](https://github.com/NousResearch/hermes-agent/blob/main/ui-tui/package.json)).
- GitHub language bytes: Python 112 MB, TypeScript 39 MB ([GitHub API](https://api.github.com/repos/NousResearch/hermes-agent/languages)).
- v0.22.0 says the source shrank from about 1.06M to 698K lines and `gateway/run.py` from 34,847 to 5,512 lines (vendor claim, [v0.22.0](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.0)).

**Agent loop.** Hermes runs its own synchronous loop ([agent-loop.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/agent-loop.md)):
- Three API modes: `chat_completions` (OpenAI-compatible), `codex_responses`, and `anthropic_messages`.
- The mode is resolved from the provider and base URL; messages are normalized to OpenAI-format dicts.
- Tools run sequentially or in a thread pool.
- Middle turns are compressed when context gets large; Anthropic prompt caching is used.
- The system prompt stays frozen per session for cache stability ([architecture.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/architecture.md)).

Optional engines and protocols:
- OpenAI/Codex turns can be handed to the Codex CLI app-server, with Hermes acting as the shell around it ([codex-app-server-runtime.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/codex-app-server-runtime.md)).
- ACP server over stdio/JSON-RPC for VS Code, Zed, and JetBrains ([acp.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/acp.md)).
- MCP client, plus `mcp_serve.py`.
- An OpenAI-compatible API server (`gateway/platforms/api_server*.py`).
- A2A v1.0 ([v0.20.0](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.8.3)).
- An experimental Relay: the gateway dials out over one authenticated WebSocket to a connector that holds the platform tokens ([relay.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/messaging/relay.md)).

**Models and auth.**
- 42 model-provider plugins under `plugins/model-providers/`, including anthropic, bedrock, vertex, azure-foundry, openrouter, openai-codex, xai, copilot, copilot-acp, qwen-oauth, ollama-cloud, lmstudio, nous, and others ([tree](https://github.com/NousResearch/hermes-agent/tree/main/plugins/model-providers)).
- Subscription logins: ChatGPT/Codex OAuth; SuperGrok / X Premium+ device-code OAuth ([xai-grok-oauth.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/guides/xai-grok-oauth.md)); Anthropic OAuth only on Claude Max with purchased extra-usage credits, not Claude Pro ([providers.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/providers.md)).
- Nous Portal OAuth stores one refresh token in `~/.hermes/auth.json` and mints short-lived JWTs per request ([nous-portal.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/nous-portal.md)).
- Local models: one-click llama.cpp (CPU/CUDA/Metal/Vulkan/ROCm) since v0.22.0.
- Credential pools and fallback providers are supported.
- `hermes proxy` re-exposes a subscription as a local OpenAI-compatible endpoint for other apps ([subscription-proxy.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/subscription-proxy.md)).

**Execution environment.** `terminal.backend` can be `local`, `docker`, `ssh`, `singularity`, `modal`, `daytona`, or `vercel_sandbox` ([tools.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/tools.md); code in `tools/environments/`, which also has `managed_modal.py`).
- Docker uses one persistent container per process, accessed via `docker exec` (same doc).
- Daytona and Modal hibernate when idle ([README](https://github.com/NousResearch/hermes-agent/blob/main/README.md)).
- Nous Portal can provide a managed Modal sandbox as an add-on ([nous-portal.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/nous-portal.md)).

**State and storage.**
- Everything lives under `HERMES_HOME` (`~/.hermes`, or `%LOCALAPPDATA%\hermes` on Windows).
- `state.db`: SQLite with FTS5, session lineage across compressions.
- `memories/MEMORY.md` and `USER.md`; `skills/`; `cron/jobs.json`; `kanban.db`; `auth.json`; `profiles/<name>/` ([memory.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/memory.md), [kanban.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/kanban.md)).
- There is no cloud sync. Multiple desktops attach to the same backend, and per-Bot UI metadata lives in profile metadata so it follows the backend ([bot-mode.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/bot-mode.md)).

**Remote and mobile access.**
- The desktop connects to a remote `hermes serve` gateway by session token or OAuth, to SSH hosts (the app opens the tunnel), or to Hermes Cloud through portal sign-in.
- Desktop tokens are stored as 0600 files in the Electron main process; OS keychain encryption is optional ([multi-connection-desktop.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/multi-connection-desktop.md)).
- Phones reach Hermes through messaging channels. Android/Termux has a signed APT repo ([README](https://github.com/NousResearch/hermes-agent/blob/main/README.md)).
- No first-party iOS app found (unknown).

**Extension surface.**
- Skills follow the agentskills.io SKILL.md standard, with progressive disclosure and a Skills Hub ([skills.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/skills.md)).
- Python plugins loaded from user/project dirs and pip entry points. Memory providers and context engines are single-select plugin types ([architecture.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/architecture.md)).
- Desktop plugin SDK (`@hermes/plugin-sdk`) ([desktop-plugin-sdk.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/desktop-plugin-sdk.md)).
- Hooks, MCP.
- A 600-entry reviewed plugin catalog pinned to commits ([v0.22.0](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.0), `plugin-catalog/`).

## Capabilities in detail

**Persistent bots and identity.**
- Profiles are isolated: config, memory, skills, credentials, sessions, cron. SOUL.md is the persona file ([profiles.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/profiles.md)).
- `/personality` switches personas inside a session ([README](https://github.com/NousResearch/hermes-agent/blob/main/README.md)).
- Bot Mode adds avatar, title, voice, and the canonical Bot Chat on top of profiles ([bot-mode.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/bot-mode.md)).

**Learning loop (skills).**
- The system prompt tells the agent to save a non-trivial workflow, a recovered dead end, or a user correction as a skill using `skill_manage` (create/patch/delete/write_file). An advisory linter discourages "incident log" skills ([skills.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/skills.md)).
- After a turn, a background fork of `AIAgent` reviews the conversation and may write memory or patch skills. It defaults to the main model's warm cache, or runs on a cheaper `auxiliary.background_review` model using a digest. `write_approval` can stage those writes for human review ([memory.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/memory.md)).
- A **Curator** pass runs about every 7 days when the agent has been idle for 2+ hours. It moves agent-created skills through active -> stale -> archived and proposes merges. It never deletes ([curator.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/curator.md)).

**Memory.**
- Two bounded files are injected as a frozen snapshot at session start: MEMORY.md (2,200 chars) and USER.md (1,375 chars). When full, the tool returns an error rather than silently dropping entries ([memory.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/memory.md)).
- `session_search` runs FTS5 over all sessions. The memory doc says it returns raw messages with "no LLM summarization", but the README says "FTS5 session search with LLM summarization". The docs conflict; behavior unverified in code.
- External providers (one active at a time): RetainDB and ByteRover are bundled; Honcho (dialectic user modeling, by Plastic Labs), Mem0, Supermemory, Hindsight, OpenViking, and Holographic come from the catalog. Everything sent to them goes through a secret scrub first ([memory-providers.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/memory-providers.md), [honcho.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/honcho.md)).

**Routines and automation** ([cron.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/cron.md)):
- The agent manages cron through a single `cronjob_manage` tool: one-shot or recurring jobs, pause/edit/trigger.
- Jobs can attach multiple skills, pin a model, and deliver to the origin chat, files, or any platform.
- "No-agent" mode runs a script and delivers its stdout verbatim.
- Webhook routes can fire a job on external events.
- The scheduler gives each job a fresh `AIAgent` ([architecture.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/architecture.md)).
- Related: `/heartbeat` (in-thread) and `/goal` (judge-checked continuation loop).

**Subagents and multi-agent work.**
- `delegate_task` spawns isolated child `AIAgent`s with their own terminal sessions. Up to 10 run concurrently by default, results can be validated against an `output_schema`, and top-level calls return a handle and post results asynchronously ([delegation.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/delegation.md)).
- Subagents are visible and steerable live in CLI/TUI/Desktop as of v0.22.0.
- Kanban is a durable board across profiles in `~/.hermes/kanban.db`, where each worker is its own OS process ([kanban.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/kanban.md)).
- Bot group rooms, `message_agent`, cross-machine relay, and `hermes peer` cover bot-to-bot communication ([bot-mode.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/bot-mode.md)).
- Mixture-of-agents is also documented ([mixture-of-agents.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/mixture-of-agents.md)).

**Coding workspace.**
- File tools (`read_file`, `write_file`, `patch`, `search_files`), terminal with background process registry, `execute_code` (Python scripts that call tools via RPC), LSP, checkpoints and rollback.
- Git worktrees and the desktop git review ([architecture.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/architecture.md), [desktop.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/desktop.md)).

**Browser and computer use.**
- Browser backends: Browser Use (cloud and CLI), Browserbase, Firecrawl, Camofox, Lightpanda ([browser.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/browser.md)).
- Computer use runs in the background on all three desktop OSes through the `cua-driver` MCP, with no cursor warp, and works with any tool-capable model ([computer-use.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/computer-use.md)).
- A credential vault plus 1Password/Bitwarden fill passwords without the model seeing them ([credential-vault.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/credential-vault.md)).

**Connectors.**
- MCP client, including OAuth/PKCE servers.
- Nous-hosted app connectors (Linear, Notion) with a free connectors-only identity; desktop Connectors page ([v0.22.0](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.0)).
- The Tool Gateway covers web search, FAL image generation, OpenAI TTS, Browser Use cloud browser, and a Modal sandbox ([nous-portal.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/nous-portal.md)).

**Channels.**
- 27 platform plugins in `plugins/platforms/` plus core API-server, webhook, and MS Graph adapters. Per-platform capability matrix (voice/images/files/threads/reactions/typing/streaming) is in [messaging/index.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/messaging/index.md).
- iMessage via BlueBubbles or Photon. Teams meetings pipeline. Email with an agent address guide.

**Voice.** Microphone mode, streaming TTS with barge-in, wake word ("hey hermes"), Discord voice channels ([voice-mode.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/voice-mode.md), [v0.20.0](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.8.3)).

**Mobile.** Messaging apps and Termux (above). Community PWA [przbadu/hermes-ui](https://github.com/przbadu/hermes-ui) (third-party).

**Teams.**
- Gateway allowlists and DM pairing; a team Telegram assistant guide ([security.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/security.md)).
- Hermes Business: invite by email, one central balance with per-member caps, skills published to a team library, isolated tenant on Nous infrastructure ([portal.nousresearch.com/business](https://portal.nousresearch.com/business)). Third-party writeups say org skills sync read-only into `~/.hermes/skills/_org/<org_id>/` ([hermesagents.net, third-party](https://hermesagents.net/blog/hermes-business-and-enterprise-explained)); not found by `gh search code` (unknown).
- Hermes Enterprise: on-prem or private cloud with SSO and SLAs (vendor claim, same page).

**OpenClaw migration.** `hermes claw migrate` (with `--dry-run`, `--preset user-data`, `--overwrite`) imports SOUL.md, MEMORY.md/USER.md, skills (into `skills/openclaw-imports/`), command allowlist, messaging config, allowlisted API keys, TTS assets, and AGENTS.md. Setup auto-detects `~/.openclaw` ([README](https://github.com/NousResearch/hermes-agent/blob/main/README.md); code in `hermes_cli/claw.py`). Present since the first release notes on 2026-03-17 ([v2026.3.17](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.3.17)). Also documented: an agent-guided `openclaw-migration` skill and `hermes import-agent` for `~/.claude` and `~/.codex`.

**Ecosystem: Grok-Bot recreations and desktop GUIs** (GitHub API, as of 2026-10-20):

| Project | What | Stars | Status |
|---|---|---|---|
| [thomasbek3/hermes-bot-kit](https://github.com/thomasbek3/hermes-bot-kit) (MIT) | "The Grok Bot experience for your Hermes fleet": 4 desktop plugins (iMessage-style Bubble Mode, live remote-desktop Computer pane with an agent "hands" plugin, Bot Sections, Task Dock) + a `texting-style` agent plugin; needs Hermes Desktop >= 0.20.5 ([README](https://github.com/thomasbek3/hermes-bot-kit/blob/master/README.md)). Found via [GrokBot Guide](https://grokbotguide.com/open-source/hermes-bot-kit) (third-party). | 183 | created 2026-08-22, last push 2026-09-24 |
| [NousResearch/Hermes-Bot-Mode](https://github.com/NousResearch/Hermes-Bot-Mode) | Official Bot Mode plugin, now in core | 669 | archived |
| [fathah/hermes-desktop](https://github.com/fathah/hermes-desktop) ("Hermes One") | Community desktop companion | 14,429 | active |
| [dodo-reach/hermes-desktop](https://github.com/dodo-reach/hermes-desktop) | macOS manager over pure SSH | 2,030 | last push 2026-06-19 |
| [nickvasilescu/hermes-desktop-os1](https://github.com/nickvasilescu/hermes-desktop-os1) | macOS workspace on Orgo cloud computers and SSH hosts | 529 | active |
| [hunterbohm/hermes-computer-viewer](https://github.com/hunterbohm/hermes-computer-viewer) | Fork of the bot-kit computer viewer | 44 | — |

**Aiden Agent and Hermes.** Aiden Agent does **not** embed or run Hermes. Its [hermes-bot-run-control-plan.md](https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/hermes-bot-run-control-plan.md) is titled "Hermes-inspired Bot run control". It re-implements Hermes-style busy-input handling on Aiden's own Pi runtime: Telegram queue/interrupt, Steer/Queue, `/new` -> compaction for the canonical Bot chat. It pins upstream `gateway/run.py` at commit 836b5f8 as a reference and states "No upstream code copied" ([.memory/hermes-bot-run-controls.md](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/hermes-bot-run-controls.md)). Aiden's bot memory budgets are "twice Hermes Agent's defaults" ([renderer/shared/bot-memory.ts](https://github.com/sambitcreate/aiden-agent/blob/main/renderer/shared/bot-memory.ts)).

## Security and trust model

**Eight documented layers** ([security.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/security.md)):
1. User authorization (allowlists, DM pairing).
2. Dangerous-command approval: `smart`/`manual`/`off` plus YOLO, a hardline blocklist floor, user deny rules, and `cron_mode`/`unattended_mode` that deny by default.
3. File-write denylist with an optional `HERMES_WRITE_SAFE_ROOT`.
4. Container isolation.
5. Env filtering for MCP subprocesses.
6. Prompt-injection scanning of context files.
7. Cross-session isolation.
8. cwd sanitization.

**Secrets.**
- Memory providers and channel deliveries receive secret-scrubbed text ([memory-providers.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/memory-providers.md)).
- The Portal path keeps a single refresh token on disk.
- Website passwords are encrypted locally and never shown to the model ([credential-vault.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/credential-vault.md)).
- Relay keeps platform tokens off the gateway ([relay.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/messaging/relay.md)).

**Isolation caveats stated by the maker.**
- Bots on one host share the OS user, files, and network. The Bot Screen control lease is "a tool-level fence ... not an OS one". Chromium's DevTools port is reachable by any local user ([bot-screen.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/bot-screen.md)).
- Two agent processes must not share one HERMES_HOME ([memory.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/memory.md)).

**Supply chain.** Exact-pinned dependencies after the 2026-05 PyPI worm ([pyproject.toml](https://github.com/NousResearch/hermes-agent/blob/main/pyproject.toml)). Signed macOS/MSIX builds and a reviewed plugin catalog ([v0.22.0](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.0)).

**Known CVEs** (third-party databases; we did not check patch status):
- [CVE-2026-9366](https://www.sentinelone.com/vulnerability-database/cve-2026-9366/): prompt-builder injection.
- [CVE-2026-10223](https://www.sentinelone.com/vulnerability-database/cve-2026-10223/): memory scan injection, public PoC.
- [CVE-2026-11461](https://www.sentinelone.com/vulnerability-database/cve-2026-11461/): session-title authorization bypass, versions up to 0.12.0.
- [CVE-2026-14626](https://www.sentinelone.com/vulnerability-database/cve-2026-14626/): API DoS.
- [CVE-2026-71963](https://vuldb.com/vuln/398458): git `core.fsmonitor` OS command injection, versions up to 0.21.0.

The repo's GitHub security-advisories API returned no published GHSAs as of 2026-10-20.

**Telemetry.** No product-telemetry policy page found (unknown). The dashboard is documented as localhost-only ([web-dashboard.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/web-dashboard.md)).

## Traction and momentum

**GitHub** (as of 2026-10-20):
- 255,361 stars, 55,611 forks, 983 watchers.
- 4,631 contributors (API, including anonymous).
- 56,847 commits on `main`.
- 50,144 open issues+PRs (`open_issues_count`).
- Last push 2026-10-20 ([GitHub API](https://api.github.com/repos/NousResearch/hermes-agent)).
- Press reported 214,000 stars "in six months" ([Startup Fortune, press](https://startupfortune.com/hermes-agent-crosses-214000-github-stars-as-developers-abandon-commercial-ai-agent-frameworks/)).

**Releases.** 41 releases from v2026.3.12 (2026-03-12) to v0.22.2 (2026-10-15) ([releases](https://github.com/NousResearch/hermes-agent/releases)). Milestones:
- v0.16.0 "Surface", 2026-06-05: first desktop app.
- v0.17.0, 2026-06-19: iMessage via Photon, Raft.
- v0.20.0 "Herald", 2026-08-03: voice, A2A.
- v0.21.0 "Pantheon", 2026-08-31: Bot Mode built in.
- v0.22.0 "Threshold", 2026-10-13/14: onboarding chat, connectors, local models, stable channels, Microsoft Store, Bot Screen.

**Churn the maker reports.** v0.22.0 counts about 24,200 commits, 6,080 merged PRs, and 2,520 contributors since v0.21.0, roughly six weeks. v0.21.0 counts about 5,800 commits and 760+ contributors (vendor claim, release notes). That volume suggests heavy agent-authored contribution [INFERENCE]. The `contributors/emails/` registry holds 2,081 entries, several at `@openclaw.local` hosts ([tree](https://github.com/NousResearch/hermes-agent/tree/main/contributors)).

**Business and pricing.**
- **Nous Portal plans** ([Hermes Cloud page](https://portal.nousresearch.com/cloud), as of 2026-10-20):
  - Free $0: free models only.
  - Plus $20/mo: $22 credits, $10 rollover cap.
  - Super $100/mo: $110 credits.
  - Ultra $200/mo: $220 credits.
  - Paid tiers include 200+ models and hosted tool use.
  - The Tool Gateway is paid-only, apart from a "free tool pool" on some accounts ([tool-gateway.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/tool-gateway.md)).
- **Hermes Cloud** ([cloud page](https://portal.nousresearch.com/cloud)):
  - One-click deploy; $2 minimum credit or a subscription.
  - Billed daily from credit: compute while running (metered to the second) plus storage, storage only while stopped.
  - Inference and tools are billed on top. 14 regions.
  - A search-indexed portal page listed a small size (5 sessions, 1 GB RAM, 2 vCPU) at $0.29/day running and $0.03/day stopped, and a medium size (2 GB RAM, 4 vCPU) at $0.56/day ([portal.nousresearch.com/info via search snippet](https://portal.nousresearch.com/info); the page itself returned HTTP 429).
  - Cloud agents auto-update to the newest release tag ([v2026.9.14](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.9.14)).
  - They can be managed from a local Hermes through the Portal MCP server ([manage-hermes-cloud-with-mcp.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/guides/manage-hermes-cloud-with-mcp.md)).
- **Hermes Business** is self-serve on Nous infrastructure; **Enterprise** is contact sales ([business page](https://portal.nousresearch.com/business)).
- **Press:** $90M financing announced 2026-10-07 and a reported $1.5B valuation; Nous claims 24M+ clones/downloads ([TokenPost, press](https://www.tokenpost.com/news/business/27550), [Startup Fortune, press](https://startupfortune.com/nous-research-confirms-15-billion-valuation-and-launches-business-ai-agents/)).

## Strengths

- **The learning loop is the real product.** It has bounded memory files with explicit capacity, background review on a cheaper model, write-approval gates, and a curator that archives stale skills. It is a complete, documented answer to "agent gets better over time" ([memory.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/memory.md), [curator.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/curator.md)).
- **One primitive (the profile) underlies everything.** Bots, gateways, cron, and the CLI all see the same object, so Bot Mode added almost no new storage.
- **Widest channel and backend coverage in the category.** 27 messaging plugins and 7 terminal backends, including serverless hibernation [INFERENCE vs peers].
- **Model-agnostic, with many subscription logins** and a single-bill option (Portal) for people who don't want to manage keys.
- **Responds very quickly to competitors.** A Grok Bot clone plugin shipped two days after Grok Bot, and was in core within three weeks.
- **MIT license, very large community,** and a funded company behind it.

## Weaknesses and risks

- **Extreme churn.** 2M-line diffs per release, a 50k open-issue/PR backlog, and many 2026 CVEs make it a moving and risky base to fork or embed [INFERENCE].
- **Bots on a host share one OS user.** Per-bot screens are not security boundaries (maker-stated). True per-bot isolation needs separate hosts or Hermes Cloud.
- **Python core plus a large Electron app.** The install footprint is heavy: bundled Python, Node, uv, and FFmpeg via the installer ([README](https://github.com/NousResearch/hermes-agent/blob/main/README.md)).
- **No first-party mobile app.** Mobile depends on third-party chat apps.
- **Commercial pull toward Nous Portal.** The Tool Gateway, connectors, and Cloud route through Nous infrastructure, and Portal model routing may change per model ([nous-portal.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/nous-portal.md)).
- **Some docs conflict.** Example: whether session search uses LLM summarization (README vs memory.md).
- **Anthropic subscription access is narrow.** Claude Max extra-usage only.

## Ideas worth taking for Memoshi

- **Make "bot = profile directory" the core primitive.** Isolated config, memory, skills, and credentials per bot keep the UI and CLI symmetric and make bots portable and inspectable.
- **Give each bot one canonical forever-chat where `/new` compacts instead of forking.** It preserves the "teammate" illusion and stops session sprawl.
- **Treat routines as plain cron jobs namespaced per bot, with results delivered into that bot's chat.** One scheduler, no second automation system.
- **Use bounded, capacity-labeled memory files frozen per session, plus FTS search over all transcripts.** Cheap, cache-friendly, and the agent can see when memory is full.
- **Run background post-turn review on a cheap model, behind an optional human approval queue, before memory or skills change.** You get learning without silent drift.
- **Add a curator that archives stale agent-made skills and never deletes them.** Skill libraries otherwise rot into near-duplicates.
- **Support takeover-and-handback on a per-bot remote screen** for logins, 2FA, and payments. It is the practical fix for browser agents getting stuck at auth walls.
- **Ship importers for OpenClaw, Claude Code, and Codex homes** with dry-run previews. They lower switching cost and are cheap to build.
- **Avoid sharing one OS user across bots if per-bot computers are a selling point.** Hermes documents this as its own gap.

## Open questions

- Hermes Cloud instance sizes and prices beyond the search snippet. Read portal.nousresearch.com/agents/new while signed in; the public pages returned HTTP 429 to us.
- Whether org skills (`_org/<org_id>`) are implemented in the OSS client or only on Portal. A targeted code search failed on this repo; check `hermes_cli/` skill sync code directly.
- Patch status of the listed CVEs. Compare the affected functions against current `main`, and check whether NVD entries list fixed versions.
- How much of the commit and contributor volume is agent-generated. Sample authors via `gh api repos/NousResearch/hermes-agent/commits`.
- Whether an official mobile app is planned. Watch the release notes and desktop docs.
- Telemetry or analytics in the desktop app. Inspect `apps/desktop/electron/` for analytics calls.

## Sources

1. https://github.com/NousResearch/hermes-agent (README, tree, GitHub API stats, 2026-10-20)
2. https://github.com/NousResearch/hermes-agent/releases (v2026.3.12 to v0.22.2; notes for v0.16.0, v0.20.0, v0.21.0, v0.21.x patches, v0.22.0, v0.22.2)
3. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/architecture.md
4. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/agent-loop.md
5. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/bot-mode.md
6. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/bot-screen.md
7. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/desktop.md
8. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/multi-connection-desktop.md
9. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/skills.md
10. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/curator.md
11. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/memory.md
12. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/memory-providers.md
13. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/honcho.md
14. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/cron.md
15. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/delegation.md
16. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/kanban.md
17. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/heartbeat.md
18. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/goals.md
19. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/tools.md
20. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/codex-app-server-runtime.md
21. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/acp.md
22. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/computer-use.md
23. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/browser.md
24. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/credential-vault.md
25. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/voice-mode.md
26. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/web-dashboard.md
27. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/tui.md
28. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/messaging/index.md
29. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/messaging/relay.md
30. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/profiles.md
31. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/security.md
32. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/import-from-other-agents.md
33. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/nous-portal.md
34. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/providers.md
35. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/tool-gateway.md
36. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/subscription-proxy.md
37. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/guides/manage-hermes-cloud-with-mcp.md
38. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/guides/xai-grok-oauth.md
39. https://github.com/NousResearch/hermes-agent/blob/main/pyproject.toml, apps/desktop/package.json, ui-tui/package.json
40. https://portal.nousresearch.com/cloud (Hermes Cloud and Portal plan pricing, 2026-10-20)
41. https://portal.nousresearch.com/business (Hermes Business / Enterprise)
42. https://portal.nousresearch.com/info (instance pricing, via search snippet only; HTTP 429 on fetch)
43. https://github.com/NousResearch/Hermes-Bot-Mode (archived official plugin)
44. https://github.com/thomasbek3/hermes-bot-kit (README, GitHub API)
45. https://grokbotguide.com/open-source/hermes-bot-kit (third-party discovery lead)
46. https://github.com/sambitcreate/aiden-agent/blob/main/docs/plans/hermes-bot-run-control-plan.md, .memory/hermes-bot-run-controls.md, renderer/shared/bot-memory.ts
47. https://github.com/fathah/hermes-desktop, https://github.com/dodo-reach/hermes-desktop, https://github.com/nickvasilescu/hermes-desktop-os1, https://github.com/przbadu/hermes-ui, https://github.com/hunterbohm/hermes-computer-viewer (GitHub API)
48. https://www.sentinelone.com/vulnerability-database/cve-2026-9366/, cve-2026-10223, cve-2026-11461, cve-2026-14626; https://vuldb.com/vuln/398458 (third-party)
49. https://startupfortune.com/hermes-agent-crosses-214000-github-stars-as-developers-abandon-commercial-ai-agent-frameworks/ (press)
50. https://www.tokenpost.com/news/business/27550 (press)
51. https://startupfortune.com/nous-research-confirms-15-billion-valuation-and-launches-business-ai-agents/ (press)
52. https://hermesagents.net/blog/hermes-business-and-enterprise-explained (third-party)
