# OpenClaw

> A self-hosted, MIT-licensed personal/team assistant whose Gateway daemon lives on your machine and talks to you through the 30+ chat apps you already use; the open-source reference design the whole "always-on agent" category copies or builds on. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: OpenClaw (formerly Warelay / Clawdbot / Moltbot)
slug: openclaw
category: personal-assistant-gateway
maker: OpenClaw Foundation (US 501(c)(3)); created by Peter Steinberger, who joined OpenAI 2026-02-15 and still makes technical calls
license: MIT
repo: https://github.com/openclaw/openclaw
website: https://openclaw.ai (docs https://docs.openclaw.ai, foundation https://openclaw.org)
first_public: 2025-11-24   # repo created; v0.1.1 tagged 2025-11-25
latest_release: v2026.10.5, 2026-10-18 (beta v2026.10.10-beta.2, 2026-10-19)
release_cadence: "~5 tags/week (22 tags = 14 stable + 8 beta between 2026-09-20 and 2026-10-19; 267 releases total)"
stars: 392912 (as of 2026-10-20)
forks: 82538 (as of 2026-10-20)
contributors: 3625 (GitHub contributors API incl. anonymous, as of 2026-10-20)
primary_language: TypeScript
stack: "Node 24.16+/26.1+ pnpm monorepo; Gateway = WebSocket JSON-frame server on :18789 + HTTP; node:sqlite per-agent DBs (PostgreSQL optional); Baileys (WhatsApp), grammY (Telegram), Playwright/CDP browser; web Control UI + TUI (pi-tui); Swift macOS/iOS/watchOS apps, Kotlin Android, WinUI Windows Hub, Tauri desktop backup"
platforms: [macos, windows, linux, ios, android, web, cli]
agent_engine: "own loop (@openclaw/agent-core, internalized from Mario Zechner's Pi SDK on 2026-05-27) + plugin harnesses (codex, copilot, muse) + CLI backends (claude-cli) + ACP/acpx for external harnesses"
engines_supported: [openclaw (pi-derived), codex, claude-code, copilot-cli, muse-code, gemini-cli, opencode, cursor-cli, droid, raw-api]
model_access: "API keys (~70 provider pages incl. Anthropic, OpenAI, Google, xAI, Meta, OpenRouter, Bedrock, Chinese labs); subscription OAuth (ChatGPT/Codex OAuth; Claude CLI reuse); GitHub Copilot; local models (Ollama, LM Studio, vLLM, SGLang, llama-style servers)"
execution_env: "user host by default (main session tools run on the Gateway host); optional sandbox backends Docker, Podman, SSH, NVIDIA OpenShell, Crabbox cloud workers; paired nodes run device-local commands"
per_bot_computer: "partial: per-agent workspace and optional per-agent sandbox container; cloud sessions can attach a Crabbox VM/desktop per conversation"
persistent_bots: "yes: multiple isolated agents per Gateway, each with workspace (SOUL.md, IDENTITY.md, AGENTS.md), auth profiles, SQLite session store, bound to channel accounts"
memory: "plain Markdown in the workspace (USER.md, MEMORY.md, memory/YYYY-MM-DD.md, DREAMS.md) + memory_search index + default-on 'dreaming' consolidation; memory is a single-active plugin slot (e.g. Honcho)"
routines: "automations (one-shot/interval/cron expr), heartbeat monitor (default 30 min), lifecycle hooks, authenticated webhooks, IMAP trigger plugin, standing orders, Lobster workflows"
group_chat: "yes: agents in group chats with mention gating; experimental multi-agent 'broadcast groups' with bounded follow-up rounds; bot-to-bot loop protection; subagents and swarm"
coding_workspace: "partial: file/exec/apply_patch tools, diffs, managed worktrees, Codex harness, cloud coding sessions; no IDE UI"
browser_use: "yes: dedicated agent-only Chromium profile via CDP, or attach to the user's signed-in Chrome via Chrome DevTools MCP; remote/hosted CDP"
computer_use: "yes: built-in `computer` tool on the Gateway desktop, a paired node (macOS app), or a Crabbox desktop"
connectors: "MCP (client and server), code plugins + bundle plugins, skills; distribution via ClawHub; A2A 1.0 channel"
channels: "WhatsApp, Telegram, iMessage, Slack, Discord, Signal, Microsoft Teams, Google Chat, Matrix, Mattermost, LINE, WeChat, WeCom, Feishu, QQ, Zalo, IRC, Nostr, Twitch, X, SMS, Nextcloud Talk, Synology Chat, Tlon, WebChat, Voice Call (Plivo/Telnyx/Twilio), Reef, A2A and more (~34 listed)"
mobile: "yes: iOS app (App Store, iOS 26.2+) and Android app (Google Play) as Gateway nodes; plus every mobile chat app via channels"
voice: "yes: Talk mode and voice wake on nodes, TTS providers, Voice Call plugin, Discord voice"
approvals: "DM pairing codes for unknown senders + group allowlists/mention gates; exec modes deny/allowlist/ask/auto/full with host-local exec approvals; Codex Guardian when using the Codex harness"
e2e_encryption: "partial: only what each chat channel provides; Reef channel gives E2E agent-to-agent messaging; Gateway WS is loopback by default, remote via Tailscale/SSH"
self_host: "yes (the only mode; hosted services described as optional)"
multi_user: "yes inside one trust boundary: team Gateway, shared sessions, named operator roles, GitHub identity; explicitly not hostile multi-tenant"
pricing: "free; no paid tier, hosted service, or token; users pay their model providers"
maturity: "GA-like: CalVer stable/beta channels, App Store/Play apps, enterprise derivatives (Microsoft Scout/Autopilot, NemoClaw); still very fast-moving (9,607 open issues+PRs as of 2026-10-20)"
```

## What it is

OpenClaw is a long-lived **Gateway** daemon that you install on a laptop, Mac mini, home server, or VPS. It owns every messaging connection, every agent session, credentials, and tool execution; you talk to it from WhatsApp, Telegram, Slack, iMessage, Discord, and 20+ other chat apps, from its web Control UI/TUI, or from native companion apps ([README](https://github.com/openclaw/openclaw/blob/main/README.md), [Gateway architecture](https://docs.openclaw.ai/concepts/architecture)). The mental model is a **control plane for a personal assistant**: the assistant is a resident of your existing chats, not an app you open. The same binary runs a solo assistant or a shared team Gateway; "configuration is the only difference" ([README](https://github.com/openclaw/openclaw/blob/main/README.md), [Teams](https://docs.openclaw.ai/start/teams)).

Target user: originally technical individuals who want "the AI that actually does things" on their own machine with their own keys ([VISION.md](https://github.com/openclaw/openclaw/blob/main/VISION.md)); since mid-2026 also teams and enterprises (Red Hat, Microsoft, NVIDIA, Tencent partners per the [Foundation announcement](https://openclaw.ai/blog/introducing-openclaw-foundation)). Problem claimed: SaaS assistants keep your data and act only when prompted; OpenClaw keeps state, memory, and credentials on your hardware and acts proactively via heartbeat and schedules ([Introducing OpenClaw](https://openclaw.ai/blog/introducing-openclaw), [Heartbeat](https://docs.openclaw.ai/gateway/heartbeat)).

**History (dated).**

| Date | Event | Source |
| --- | --- | --- |
| late 2025 | Starts as "Warelay" / "WhatsApp Relay", a WhatsApp gateway weekend project by Peter Steinberger (Vienna; previously founder of PSPDFKit, per press coverage, not verified here) | [lore](https://docs.openclaw.ai/start/lore), [Introducing OpenClaw](https://openclaw.ai/blog/introducing-openclaw), [VISION.md](https://github.com/openclaw/openclaw/blob/main/VISION.md) |
| 2025-11-24 / 25 | GitHub repo created; v0.1.1 tagged; assistant persona "Clawd" (pun on Claude) in "Clawdbot" | GitHub API, [lore](https://docs.openclaw.ai/start/lore) |
| 2026-01-25 to 27 | Jamieson O'Reilly (Dvuln) reports hundreds of internet-exposed Clawdbot control panels leaking keys and chats | [The Register, 2026-01-27 (press)](https://www.theregister.com/2026/01/27/clawdbot_moltbot_security_concerns), [Bitdefender (third-party)](https://www.bitdefender.com/en-us/blog/hotforsecurity/moltbot-security-alert-exposed-clawdbot-control-panels-risk-credential-leaks-and-account-takeovers) |
| 2026-01-27 | Rename 1: Anthropic asks for a name change on trademark grounds; community picks "Moltbot" in a 5am Discord vote. Handle snipers grab @openclaw and the old `steipete` GitHub name; $-token scams follow | [lore](https://docs.openclaw.ai/start/lore) |
| 2026-01-28 | Matt Schlicht launches Moltbook, an "agents-only" social network populated by OpenClaw agents | [Orca incident archive (third-party)](https://github.com/Continuum-AI-Corp/Orca-AI-Incident-Archive/blob/main/incidents/2026-01/2026-01-31-moltbook-open-database.md), [TechCrunch 2026-01-30 (press)](https://techcrunch.com/2026/01/30/openclaws-ai-assistants-are-now-building-their-own-social-network/) |
| 2026-01-29 | v2026.1.29 fixes CVE-2026-25253: Control UI trusted a `gatewayUrl` query param and sent the stored Gateway token to it (1-click RCE) | [GHSA-g8p2-7wf7-98mq](https://github.com/advisories/GHSA-g8p2-7wf7-98mq), [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-25253) |
| 2026-01-30 | Rename 2: "Moltbot never quite rolled off the tongue"; trademark-searched "OpenClaw"; repo moves to `openclaw/openclaw`, docs to docs.openclaw.ai. Steinberger: >100k stars, 2M visitors in a week | [Introducing OpenClaw](https://openclaw.ai/blog/introducing-openclaw), [lore](https://docs.openclaw.ai/start/lore) |
| 2026-02-01 to 13 | "ClawHavoc": Koi Security finds 341 malicious ClawHub skills (335 in one campaign, Atomic Stealer payloads) out of 2,857 audited; Snyk finds a fake "Google" skill; a VirusTotal scanning partnership reportedly followed (third-party report, not verified in primary sources) | [Koi (third-party)](https://www.koi.ai/blog/clawhavoc-341-malicious-clawedbot-skills-found-by-the-bot-they-were-targeting), [Snyk (third-party)](https://snyk.io/blog/clawhub-malicious-google-skill-openclaw-malware/), [Broadcom bulletin](https://www.broadcom.com/support/security-center/protection-bulletin/malicious-clawhub-skills), [Digital Applied (third-party)](https://www.digitalapplied.com/blog/openclaw-clawhub-security-crisis-clawhavoc-analysis) |
| 2026-02-02 | Wiz finds Moltbook's database open: ~1.5M API keys, 35k emails | [Wiz (third-party)](https://www.wiz.io/blog/exposed-moltbook-database-reveals-millions-of-api-keys), [openclaw#7089](https://github.com/openclaw/openclaw/issues/7089) |
| 2026-02-15 | Steinberger joins OpenAI; project to continue under a foundation. Inside OpenAI he later leads "Claw Labs" | [Reuters (press)](https://www.reuters.com/business/openclaw-founder-steinberger-joins-openai-open-source-bot-becomes-foundation-2026-02-15), [TechCrunch (press)](https://techcrunch.com/2026/02/15/openclaw-creator-peter-steinberger-joins-openai/), [security-in-public post](https://openclaw.ai/blog/openclaw-security-in-public) |
| 2026-02 | "Agents of Chaos" paper attacks six OpenClaw agents; project disputes framing (guardrails disabled) | [arXiv 2602.20021](https://arxiv.org/abs/2602.20021), [security-in-public post](https://openclaw.ai/blog/openclaw-security-in-public) |
| 2026-03 | China "raise a lobster" craze: Tencent, Alibaba, Baidu ship one-click OpenClaw deployments; NVIDIA launches NemoClaw at GTC ("every company needs an OpenClaw strategy") | [CNBC 2026-03-12 (press)](https://www.cnbc.com/2026/03/12/china-openclaw-ai-agent-adoption-tech-companies-government-support-lobster-shrimp.html), [Foundation post](https://openclaw.ai/blog/introducing-openclaw-foundation) |
| 2026-04-03 | Anthropic reported building its own OpenClaw answer | [Semafor (press)](https://www.semafor.com/article/04/03/2026/anthropic-eyes-its-own-version-of-openclaw) |
| 2026-04-30 | Project reports 1,309 security advisories since 2026-01-10 (535 published, 746 invalid; 87% of "critical" invalid) | [security-in-public post](https://openclaw.ai/blog/openclaw-security-in-public) |
| 2026-05-04 / 05 | Microsoft "Project Lobster" / ClawPilot reported; Google "Remy" reported as Gemini's OpenClaw answer | [GeekWire (press)](https://www.geekwire.com/2026/microsofts-openclaw-team-takes-on-the-personal-assistant-challenge/), [Business Insider (press)](https://www.businessinsider.com/google-ai-agent-openclaw-remy-gemini-assistant-2026-5) |
| 2026-05-27 | Embedded Pi SDK internalized into `@openclaw/agent-core` (PR #85341) | [commit bb46b79d](https://github.com/openclaw/openclaw/commit/bb46b79d) |
| 2026-06-02 | Microsoft Scout (first "Autopilot") announced at Build, "powered by OpenClaw open-source technology", Microsoft contributes policy conformance upstream; OpenClaw runs in Windows Execution Containers. Scout renamed Autopilot on 2026-09-25 | [Microsoft blog](https://www.microsoft.com/en-us/copilot/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent/), [Windows blog](https://blogs.windows.com/windowsdeveloper/2026/06/02/build-2026-furthering-windows-as-the-trusted-platform-for-development/), [TechCrunch "OpenClaw-inspired" (press)](https://techcrunch.com/2026/06/02/microsoft-launches-scout-an-openclaw-inspired-personal-assistant/) |
| 2026-06-30 | Native iOS and Android apps ship (chat, Talk mode, remote approvals) | [TechCrunch (press)](https://techcrunch.com/2026/06/30/openclaw-is-finally-available-on-android-and-ios/), [iOS docs](https://docs.openclaw.ai/platforms/ios) |
| 2026-07-08 | OpenClaw Foundation (501(c)(3)) announced: chair Dave Morin, Steinberger "Clawfather", full-time staff (Vincent Koc chief architect), donors OpenAI, U. Michigan (largest), Offline Holdings, Lobster Computer Co.; partners NVIDIA, Microsoft, Red Hat, Tencent, Atlassian | [Foundation post](https://openclaw.ai/blog/introducing-openclaw-foundation) |

**Channel-first vs. app-first [INFERENCE].** OpenClaw's primary UI is other people's messengers: the bot is a contact inside WhatsApp/Telegram/Slack, one Gateway can bind several agents to several channel accounts, and the Control UI is an admin/operator console more than the daily surface. Grok Bot ([announcement](https://x.ai/news/introducing-grok-bot)) and its clones invert that: the product is a first-party messenger whose contact list is a roster of bots, with channels as secondary bridges. Consequences: channel-first gets zero-install reach, native push, group chats with humans, and mobile for free, but inherits each platform's formatting limits, ToS risk (WhatsApp via unofficial Baileys, iMessage via private APIs), weak rich UI (artifacts, diffs, approvals squeezed into chat), and identity fragmentation. App-first owns UX, rich artifacts, approvals, and E2E, but must win a new daily-use surface. OpenClaw has been drifting toward app-first too (Control UI chat, Canvas/A2UI widgets, iOS/Android apps with approvals, cloud sessions sidebar), so the long-run answer looks hybrid.

## Product and UX

- **Install and onboarding**: `curl -fsSL https://openclaw.ai/install.sh | bash` (or PowerShell / `npm i -g openclaw`) launches `openclaw onboard --install-daemon`, which verifies model access, creates the workspace, and installs the Gateway as a LaunchAgent/systemd user unit/Scheduled Task ([README](https://github.com/openclaw/openclaw/blob/main/README.md), [Platforms](https://docs.openclaw.ai/platforms)). `openclaw dashboard` opens the Control UI.
- **First channel**: docs recommend Telegram first (bot token, no plugin); WhatsApp needs QR pairing ([Channels](https://docs.openclaw.ai/channels)).
- **Bootstrap ritual**: a new workspace gets `BOOTSTRAP.md`, a one-time first-run ritual in which the agent and user settle its name, vibe, and emoji into `IDENTITY.md`, then delete the file ([Agent workspace](https://docs.openclaw.ai/concepts/agent-workspace)). Persona lives in `SOUL.md` ([SOUL guide](https://docs.openclaw.ai/concepts/soul)).
- **Creating more bots**: add agents to the roster in config/Control UI, each with its own workspace and auth; bind channel accounts to agents (e.g., two WhatsApp numbers, a Slack workspace) ([Multi-agent routing](https://docs.openclaw.ai/concepts/multi-agent)). Workspace files are edited in **Settings → Agents → Files** ([Agent workspace](https://docs.openclaw.ai/concepts/agent-workspace)).
- **Daily use**: chat in your messenger; slash commands for control; subagent runs listed under **Subagents** in the Control UI with view-only transcripts ([Subagents](https://docs.openclaw.ai/tools/subagents)). macOS menu-bar app with Option-Space Quick Chat ([macOS](https://docs.openclaw.ai/platforms/macos)).
- **Reviewing results**: heartbeat turns surface items quietly; automations deliver to a channel, webhook, or silently ([Automation](https://docs.openclaw.ai/automation)); iOS app browses the agent workspace read-only and caches recent transcripts offline ([iOS](https://docs.openclaw.ai/platforms/ios)).
- **Memory import**: Control UI can import memory from Codex, Claude Code, and Hermes ([Memory](https://docs.openclaw.ai/concepts/memory)).
- Distinctive: the lobster lore/persona culture ("EXFOLIATE!") and the "soul document" framing are a large part of the brand ([lore](https://docs.openclaw.ai/start/lore)).

## Architecture

**Components** ([Gateway architecture](https://docs.openclaw.ai/concepts/architecture), [Nodes](https://docs.openclaw.ai/nodes)):

```text
 WhatsApp(Baileys) Telegram(grammY) Slack Discord iMessage(imsg) Signal ... (channel plugins)
                 \            |            /
                  +--------------------------+   HTTP: /__openclaw__/canvas, /a2ui, webhooks,
                  |  Gateway daemon (Node)    |   OpenAI-compatible + OpenResponses APIs
                  |  sessions, agents, cron,  |
                  |  tools, auth, plugins     |
                  +--------------------------+
     WS :18789 (loopback default)  |  role=operator           | role=node
     Control UI / CLI / TUI / macOS app        iOS / Android / macOS / watchOS / headless nodes
                                                (camera.*, screen.*, location.get, canvas.*, system.run, computer)
     Tool execution: host | Docker | Podman | SSH | OpenShell | Crabbox cloud worker
```

- One Gateway per host; it is the only process that opens a WhatsApp session. Wire protocol: WebSocket text frames with JSON; first frame must be `connect`; `{type:"req"}`/`{type:"res"}`/`{type:"event"}` with JSON-Schema-validated frames; events `agent`, `chat`, `presence`, `health`, `heartbeat`, `cron` ([architecture](https://docs.openclaw.ai/concepts/architecture), [protocol](https://docs.openclaw.ai/gateway/protocol)). Swift/Kotlin protocol bindings are generated (`protocol:gen:swift`, `protocol:gen:kotlin` in [package.json](https://github.com/openclaw/openclaw/blob/main/package.json)).
- **Tech stack**: TypeScript on Node 24.16+/26.1+ (Bun opt-in), pnpm workspace; deps include `express` 5.3, `ws`, `grammy`, `baileys` 7.0.0-rc14, `playwright-core`, `zod`, `typebox`, `@earendil-works/pi-tui` 1.1.0 ([package.json](https://github.com/openclaw/openclaw/blob/main/package.json)). Native apps under `apps/` (Swift macOS/iOS, Kotlin Android incl. Wear); Windows Hub lives in [openclaw/openclaw-windows-node](https://github.com/openclaw/openclaw-windows-node) ([Windows](https://docs.openclaw.ai/platforms/windows)). A `crates/` directory and Kysely/PostgreSQL schema generation exist in the repo root (repo tree).
- **Agent loop / harness**: until May 2026 OpenClaw embedded Mario Zechner's Pi SDK, specifically `@mariozechner/pi-agent-core`, `pi-ai`, `pi-coding-agent`, and `pi-tui` (bumped to 0.54.0 in [2026.2.21](https://github.com/openclaw/openclaw/blob/main/CHANGELOG/2026.2.21.md), 0.58.0 in [2026.3.13](https://github.com/openclaw/openclaw/blob/main/CHANGELOG/2026.3.13.md)). Commit [bb46b79d](https://github.com/openclaw/openclaw/commit/bb46b79d) (2026-05-27, "internalize OpenClaw agent runtime") moved the loop into `packages/agent-core` (`@openclaw/agent-core`) and `src/llm/`; "No external agent framework packages remain" except `pi-tui`, and the legacy runtime id `pi` normalizes to `openclaw` ([Agent runtime architecture](https://github.com/openclaw/openclaw/blob/main/docs/agent-runtime-architecture.md)). Layout: `src/agents/embedded-agent-runner/` (attempt loop, compaction), `src/agents/sessions/`, `src/agents/harness/` (harness registry), `src/llm/providers/`.
- **Pluggable runtimes**: model-scoped `agentRuntime.id` picks the loop: built-in `openclaw`; plugin harnesses `codex` (Codex app-server JSON-RPC; implicitly selected for official OpenAI Responses routes), `copilot` (`@github/copilot-sdk`), `muse` (Meta's Muse Code CLI for `meta/*` models); CLI backend `claude-cli`; and ACP/acpx for Claude Code, Gemini CLI, OpenCode, Cursor, Droid ([Agent runtimes](https://docs.openclaw.ai/concepts/agent-runtimes)).
- **Models and auth**: ~70 provider pages (Anthropic, OpenAI, Google, xAI, Meta, Mistral, DeepSeek, Qwen, Moonshot, MiniMax, Z.ai, OpenRouter, Bedrock, Vercel AI Gateway, Ollama, LM Studio, vLLM, SGLang, ...) ([providers dir](https://github.com/openclaw/openclaw/tree/main/docs/providers)). Subscription auth: ChatGPT/Codex OAuth (PKCE) and Claude CLI reuse, which the docs say "Anthropic staff told us this usage is allowed again" while recommending API keys for production (vendor claim) ([OAuth](https://docs.openclaw.ai/concepts/oauth)). Auth profiles are per agent; the store acts as a "token sink" so refresh-token rotation does not log out the user's other CLIs ([OAuth](https://docs.openclaw.ai/concepts/oauth), [Multi-agent](https://docs.openclaw.ai/concepts/multi-agent)).
- **Execution environment**: main-session tools run on the Gateway host unless sandboxing is configured ([README](https://github.com/openclaw/openclaw/blob/main/README.md)); sandboxing (off by default) moves only tool execution to Docker, Podman, SSH, NVIDIA OpenShell, or Crabbox backends, never the Gateway itself ([Sandboxing](https://docs.openclaw.ai/gateway/sandboxing)). Cloud sessions run coding work on paired devices or throwaway cloud machines while the Gateway keeps transcript, workspace, and credentials ([Cloud sessions](https://docs.openclaw.ai/gateway/cloud-sessions)). The project refuses cloud sandbox providers as plugins; they go into [Crabbox](https://github.com/openclaw/crabbox) ([VISION.md](https://github.com/openclaw/openclaw/blob/main/VISION.md)).
- **State and storage**: workspace (default `~/.openclaw/workspace`) holds Markdown persona/memory; `~/.openclaw/openclaw.json` config; `~/.openclaw/agents/<id>/agent/openclaw-agent.sqlite` holds auth profiles, routing state, sessions, transcripts, memory index; `codex-home/` per agent; `~/.openclaw/credentials/` channel state ([Agent workspace](https://docs.openclaw.ai/concepts/agent-workspace)). Secrets are references rather than inline values (vendor claim, [security-in-public post](https://openclaw.ai/blog/openclaw-security-in-public); [Secrets](https://docs.openclaw.ai/gateway/secrets)). No cloud sync; backup = copy/git the workspace.
- **Remote and mobile access**: Gateway binds loopback; remote via Tailscale Serve, trusted LAN/tailnet bind, SSH tunnel, or trusted-proxy (Cloudflare Access) ([Remote access](https://docs.openclaw.ai/gateway/remote)). Nodes pair by device identity with approval in a pairing store ([architecture](https://docs.openclaw.ai/concepts/architecture)); Apple Watch uses signed HTTPS polling ([Nodes](https://docs.openclaw.ai/nodes)).
- **Extension surface**: code plugins (providers, channels, tools, hooks, harnesses) on `openclaw/plugin-sdk/*`; bundle plugins (skills, MCP servers, config); skills = `SKILL.md` directories with precedence workspace > project `.agents/skills` > personal `~/.agents/skills` > managed > bundled ([Skills](https://docs.openclaw.ai/tools/skills), [VISION.md](https://github.com/openclaw/openclaw/blob/main/VISION.md)); MCP as server and client ([MCP](https://docs.openclaw.ai/tools/mcp)); OpenAI-compatible and OpenResponses HTTP APIs, tools-invoke HTTP API ([gateway docs dir](https://github.com/openclaw/openclaw/tree/main/docs/gateway)); A2A 1.0 JSON-RPC channel for external agents ([Channels](https://docs.openclaw.ai/channels)). Distribution and moderation via [ClawHub](https://clawhub.ai) ([openclaw/clawhub](https://github.com/openclaw/clawhub), 9,523 stars as of 2026-10-20).

## Capabilities in detail

- **Persistent bots and identity**: each agent = workspace + `agentDir` + SQLite session store; workspace files `AGENTS.md` (operating rules), `SOUL.md` (persona/tone/boundaries), `IDENTITY.md` (name, vibe, emoji), `USER.md` (directive-style user model, 4,000-char budget), `BOOT.md` (startup checklist), `BOOTSTRAP.md` (first-run ritual), `skills/` ([Agent workspace](https://docs.openclaw.ai/concepts/agent-workspace)). Bootstrap files injected each session with 20k/60k char caps ([same](https://docs.openclaw.ai/concepts/agent-workspace)).
- **Memory**: "no hidden state": `MEMORY.md` curated long-term facts loaded only in the private main session; daily notes `memory/YYYY-MM-DD.md` indexed for `memory_search`/`memory_get`; "dreaming" (light/deep/REM phases, default on) distills daily notes into `MEMORY.md` with a human-reviewable `DREAMS.md` diary; memory is a one-active plugin slot (built-in, Honcho, active memory) ([Memory](https://docs.openclaw.ai/concepts/memory), [Dreaming](https://docs.openclaw.ai/concepts/dreaming), [VISION.md](https://github.com/openclaw/openclaw/blob/main/VISION.md)).
- **Routines**: user automations (one-shot `--at`, interval, cron expression; isolated/current/named/main session; per-job model), heartbeat (scheduler-owned main-session turn, default every 30 min, quiet unless something needs attention, 30 s minimum and flood guard for event wakes), hooks (`HOOK.md` scripts on lifecycle events), authenticated webhooks, IMAP plugin, standing orders injected into every session, Lobster workflow engine ([Automation](https://docs.openclaw.ai/automation), [Heartbeat](https://docs.openclaw.ai/gateway/heartbeat)).
- **Multi-bot collaboration**: multi-agent routing by bindings ([Multi-agent](https://docs.openclaw.ai/concepts/multi-agent)); experimental "agent group threads" where several agents answer one inbound message with bounded follow-up rounds on Discord/Slack/Telegram/WhatsApp ([Broadcast groups](https://docs.openclaw.ai/channels/broadcast-groups)); bot-to-bot pair loop protection, Discord/Slack accept other bots by default ([Bot loop protection](https://docs.openclaw.ai/channels/bot-loop-protection)); subagents with `context: "fork"` and configurable nesting, swarm ([Subagents](https://docs.openclaw.ai/tools/subagents), [Swarm](https://docs.openclaw.ai/tools/swarm)); Reef = E2E-encrypted, guard-model-screened channel between agents owned by different people ([Reef](https://docs.openclaw.ai/channels/reef)).
- **Coding workspace**: exec, apply-patch, diffs, managed worktrees, code mode, Codex harness, Git co-author credit on team Gateways ([tools dir](https://github.com/openclaw/openclaw/tree/main/docs/tools), [Managed worktrees](https://docs.openclaw.ai/concepts/managed-worktrees), [VISION.md](https://github.com/openclaw/openclaw/blob/main/VISION.md)). No editor UI; cloud sessions show a desktop panel in chat ([Computer use](https://docs.openclaw.ai/nodes/computer-use)).
- **Browser use**: isolated agent-only Chrome/Brave/Edge/Chromium profile via a loopback control service, or the `user` profile attaching to the signed-in Chrome via Chrome DevTools MCP; Chrome extension; hosted CDP ([Browser](https://docs.openclaw.ai/tools/browser)).
- **Computer use**: one `computer` tool targeting the Gateway desktop, a paired node, or a Crabbox desktop; provider-declared action families; vision model drives it ([Computer use](https://docs.openclaw.ai/nodes/computer-use)).
- **Canvas**: Gateway serves hosted widget documents at `/__openclaw__/canvas/` and A2UI renderer at `/__openclaw__/a2ui/`; macOS app exposes `canvas.*` widget-panel commands ([architecture](https://docs.openclaw.ai/concepts/architecture)).
- **Channels**: ~34 listed in the generated catalog, from WhatsApp/Telegram/Slack/Discord/iMessage (via `imsg` JSON-RPC with private-API tapbacks/polls)/Signal (signal-cli)/Teams to WeChat, Feishu, QQ, Zalo, LINE, Matrix, Nostr, X, SMS, Voice Call ([Channels](https://docs.openclaw.ai/channels)).
- **Voice**: Talk mode, voice wake (iOS/Android/macOS nodes), TTS (ElevenLabs, Azure, Deepgram, etc.), Voice Call via Plivo/Telnyx/Twilio, Discord voice ([iOS](https://docs.openclaw.ai/platforms/ios), [Channels](https://docs.openclaw.ai/channels), [providers dir](https://github.com/openclaw/openclaw/tree/main/docs/providers)).
- **Mobile**: iOS/iPadOS 26.2+ App Store app and Google Play Android app act as nodes (camera, screen, location, Talk, Health summaries opt-in) and chat clients ([iOS](https://docs.openclaw.ai/platforms/ios), [Android](https://docs.openclaw.ai/platforms/android)).
- **Team features**: shared Gateway with shared sessions any member can open and steer, named operator roles, GitHub identity sync, Cloudflare Access team-server deployment; "a gateway is one trust domain" ([Teams](https://docs.openclaw.ai/start/teams)). The core team dogfoods on team.openclaw.ai ([VISION.md](https://github.com/openclaw/openclaw/blob/main/VISION.md)).

## Security and trust model

- **Trust model**: "one trusted person per agent"; one trust boundary per Gateway; not a hostile multi-tenant boundary. Mutually untrusted users need separate Gateways/hosts ([Security](https://docs.openclaw.ai/gateway/security), [security-in-public post](https://openclaw.ai/blog/openclaw-security-in-public), [SECURITY.md](https://github.com/openclaw/openclaw/blob/main/SECURITY.md)).
- **Defaults**: loopback bind; unknown DM senders get a pairing code and are not processed until `openclaw pairing approve`; groups allowlisted behind mention gates. Exceptions: container images default to an exposed bind; some workspace channels trust membership ([Security](https://docs.openclaw.ai/gateway/security), [Pairing](https://docs.openclaw.ai/channels/pairing)). `openclaw security audit` checks drift.
- **Tool authority**: sandbox off by default and main-session tools run on host ([README](https://github.com/openclaw/openclaw/blob/main/README.md)). Exec modes `deny`/`allowlist`/`ask`/`auto`/`full`; approvals enforced on the executing host (Gateway or node) and can only tighten config ([Exec approvals](https://docs.openclaw.ai/tools/exec-approvals), [Permission modes](https://docs.openclaw.ai/tools/permission-modes)). Agents with message tools can send across conversations/providers by default unless restricted ([Security](https://docs.openclaw.ai/gateway/security)).
- **Telemetry**: daily version check only; opt-in anonymous feature stats; `update.checkOnStart: false` disables both ([README](https://github.com/openclaw/openclaw/blob/main/README.md), [Telemetry](https://docs.openclaw.ai/gateway/telemetry)).
- **Hardening program**: threat model (MITRE ATLAS), formal verification notes, CodeQL/Semgrep/OpenAI Codex Security, release sign-off by two Foundation staff, OpenTelemetry/Prometheus, ClawSweeper triage bot ([docs/security](https://github.com/openclaw/openclaw/tree/main/docs/security), [security-in-public post](https://openclaw.ai/blog/openclaw-security-in-public)).
- **Incidents**: exposed control panels (Jan 2026), CVE-2026-25253 1-click token exfiltration/RCE (fixed 2026.1.29), ClawHavoc malicious skills (Feb 2026; >700 ClawHub moderation issues closed in April), Moltbook database exposure (third-party site, Feb 2026), indirect prompt injection via link previews "confirmed in active exploitation" and persistence by poisoning `SOUL.md`/`MEMORY.md` per CSA ([CSA research note, 2026-06 (third-party)](https://labs.cloudsecurityalliance.org/wp-content/uploads/2026/06/CSA_research_note_openclaw_indirect_prompt_injection_20260613-csa-styled.pdf)); TechTarget cites >1M internet-exposed instances (third-party, unverified) ([TechTarget](https://www.techtarget.com/cybersecurity/tip/OpenClaw-security-best-practices-for-CISOs)). Memory provenance: files recorded as untrusted are excluded from `USER.md`/`MEMORY.md` context ([Memory](https://docs.openclaw.ai/concepts/memory)).
- **Encryption**: no app-level E2E for chats beyond each channel's own; Reef is the E2E exception ([Reef](https://docs.openclaw.ai/channels/reef)).

## Traction and momentum

- **GitHub (as of 2026-10-20)**: 392,912 stars, 82,538 forks, 1,724 watchers, 9,607 open issues+PRs, 3,625 contributors (incl. anonymous), 115,283 commits on `main`, 267 releases; last push 2026-10-20 (GitHub API). The Foundation calls it "the fastest growing repository in GitHub history" and claims "4.5 million new claws being born every week" (vendor claim, [Foundation post](https://openclaw.ai/blog/introducing-openclaw-foundation)).
- **Releases**: CalVer `vYYYY.M.N` with beta/stable channels; 22 tags (14 stable, 8 beta) between 2026-09-20 and 2026-10-19; latest stable v2026.10.5 (2026-10-18) (GitHub API). Per-release changelog files in [`CHANGELOG/`](https://github.com/openclaw/openclaw/tree/main/CHANGELOG).
- **Distribution**: npm `openclaw` 2,123,703 downloads in week 2026-10-12..18 and 14,756,203 in 2026-09-19..10-18 ([npm API](https://api.npmjs.org/downloads/point/last-month/openclaw)).
- **Community**: Discord ~18k online as of 2026-10-20 ([shields badge](https://img.shields.io/discord/1456350064065904867.json)); ClawCon: 34 events in 16 countries, ~30k sign-ups in five months (vendor claim, [Foundation post](https://openclaw.ai/blog/introducing-openclaw-foundation)).
- **Press**: curated list at [openclaw.ai/press](https://openclaw.ai/press) (TechCrunch, Verge, Reuters, CNBC, BBC, Fortune, MIT Tech Review, Fast Company AI 20).
- **Business model**: none for the project: 501(c)(3), "no paid tier, hosted service, or token"; funded by donors (Amazon, Lobster Computer Company, Offline Holdings, OpenAI, Red Hat, University of Michigan) and infra sponsors (Blacksmith, Convex, GitHub, NVIDIA, Vercel) ([README](https://github.com/openclaw/openclaw/blob/main/README.md)). Commercial value accrues to derivatives and hosts (Tencent/Alibaba/Baidu one-click deploys, Microsoft Scout/Autopilot, NemoClaw).

**Derivative ecosystem (stars as of 2026-10-20, GitHub API).**

| Project | Repo | Stars | Lang | License | Created | Differentiator |
| --- | --- | ---: | --- | --- | --- | --- |
| nanobot (HKU Data Intelligence Lab) | [HKUDS/nanobot](https://github.com/HKUDS/nanobot) | 49,205 | Python | MIT | 2026-02-01 | Ultra-lightweight Python agent framework with WebUI, chat apps, scheduling, memory; the "nano" lineage PicoClaw cites |
| QwenPaw (ex-CoPaw, Alibaba AgentScope) | [agentscope-ai/QwenPaw](https://github.com/agentscope-ai/QwenPaw) | 35,865 | TypeScript | Apache-2.0 | 2026-02-24 | Local or cloud assistant focused on Chinese channels (DingTalk, Lark, WeChat, QQ) plus Discord/Telegram/iMessage |
| ZeroClaw | [zeroclaw-labs/zeroclaw](https://github.com/zeroclaw-labs/zeroclaw) | 33,010 | Rust | Apache-2.0 | 2026-02-13 | Single Rust binary runtime, ~20 providers, 30+ channels, hardware tools |
| NanoClaw | [nanocoai/nanoclaw](https://github.com/nanocoai/nanoclaw) (redirects from qwibitai/, gavrielc/) | 30,977 | TypeScript | MIT | 2026-01-31 | Each agent in its own Linux container on the Claude Agent SDK; "one Slack app per agent", spawn teammates from chat; tiny codebase |
| PicoClaw (Sipeed) | [sipeed/picoclaw](https://github.com/sipeed/picoclaw) | 30,082 | Go | MIT | 2026-02-04 | Runs on $10 boards with ~10 MB RAM; Go rewrite inspired by nanobot, "not a fork" |
| NemoClaw (NVIDIA) | [NVIDIA/NemoClaw](https://github.com/NVIDIA/NemoClaw) | 22,773 | TypeScript | Apache-2.0 | 2026-03-15 | Alpha reference stack running OpenClaw/Hermes inside OpenShell sandboxes with network policy and Nemotron inference |
| OpenFang | [RightNow-AI/openfang](https://github.com/RightNow-AI/openfang) | 18,211 | Rust | Apache-2.0 | 2026-02-24 | "Agent OS" single ~32 MB binary with autonomous "Hands"; benchmarks itself against OpenClaw; last push 2026-07-02 |
| IronClaw (NEAR AI) | [nearai/ironclaw](https://github.com/nearai/ironclaw) | 12,668 | Rust | Apache-2.0 | 2026-02-03 | Untrusted tools in WASM sandboxes with capability permissions, encrypted credential store |
| Moltworker (Cloudflare) | [cloudflare/moltworker](https://github.com/cloudflare/moltworker) | 9,951 | TypeScript | Apache-2.0 | 2026-01-27 | Runs unmodified OpenClaw in Cloudflare Sandbox + R2; experimental PoC, last push 2026-05-09 |
| NullClaw | [nullclaw/nullclaw](https://github.com/nullclaw/nullclaw) | 8,132 | Zig | MIT | 2026-02-16 | 678 KB static binary, ~1 MB RAM |
| LobsterAI (NetEase Youdao) | [netease-youdao/LobsterAI](https://github.com/netease-youdao/LobsterAI) | 6,131 | TypeScript | MIT | 2026-02-12 | Desktop "Cowork" app that keeps OpenClaw as runtime/gateway underneath and owns UI, permissions, artifacts, IM bindings |
| TinyAGI (fka TinyClaw) | [TinyAGI/tinyagi](https://github.com/TinyAGI/tinyagi) (redirect from jlia0/tinyclaw) | 3,623 | TypeScript | MIT | 2026-02-09 | Multi-agent teams with handoff, per-team chat rooms, TinyOffice web portal; dormant since 2026-03-30 |
| MicroClaw | [microclaw/microclaw](https://github.com/microclaw/microclaw) | 747 | Rust | MIT | 2026-02-07 | Chat-resident agent inspired by NanoClaw |
| memU bot | [NevaMind-AI/memUBot](https://github.com/NevaMind-AI/memUBot) | 464 | TypeScript | AGPL-3.0 | 2026-01-27 | "Enterprise-ready OpenClaw" with memU proactive memory |
| Tiny Claw (unrelated name clash) | [warengonzaga/tinyclaw](https://github.com/warengonzaga/tinyclaw) | 297 | TypeScript | GPL-3.0 | 2026-02-04 | Separate "original Tiny Claw" companion; not TinyAGI |

Adjacent, profiled separately: Hermes Agent ([NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent), 255,362 stars, MIT) is a competitor, not a derivative; OpenClaw can import Hermes memory ([Memory](https://docs.openclaw.ai/concepts/memory)). Org tooling: [openclaw/crabbox](https://github.com/openclaw/crabbox) (1,485 stars, Go), [openclaw/clawsweeper](https://github.com/openclaw/clawsweeper) (2,004 stars).

## Strengths

- Unmatched reach: ~34 channels, five desktop/mobile platforms, ~70 model providers, subscription logins ([Channels](https://docs.openclaw.ai/channels), [providers dir](https://github.com/openclaw/openclaw/tree/main/docs/providers), [OAuth](https://docs.openclaw.ai/concepts/oauth)).
- Legible, portable agent state: persona and memory are Markdown files users can read, edit, git, and back up ([Memory](https://docs.openclaw.ai/concepts/memory)).
- Harness-agnostic: built-in loop plus Codex, Copilot, Muse, Claude CLI, ACP; picks per model ([Agent runtimes](https://docs.openclaw.ai/concepts/agent-runtimes)).
- Proactivity built in: heartbeat + automations + hooks + dreaming ([Automation](https://docs.openclaw.ai/automation)).
- Neutral governance and massive ecosystem: 501(c)(3), MIT, backing from OpenAI, Microsoft, NVIDIA, Red Hat, Tencent ([Foundation post](https://openclaw.ai/blog/introducing-openclaw-foundation)).
- Explicit, documented trust model and a mature security process after a rough start ([security-in-public post](https://openclaw.ai/blog/openclaw-security-in-public)).

## Weaknesses and risks

- Complexity: NanoClaw's author describes "nearly half a million lines of code, 53 config files, and 70+ dependencies" (competitor page, [NanoClaw README](https://github.com/nanocoai/nanoclaw)); docs sprawl (sandboxing alone is 12 pages, heartbeat doc 42 KB) [INFERENCE: high setup and ops burden for non-technical users].
- Insecure-by-capability defaults: host execution without sandbox, cross-conversation messaging by default, shared-agent = shared tool authority ([README](https://github.com/openclaw/openclaw/blob/main/README.md), [Security](https://docs.openclaw.ai/gateway/security)). Prompt injection through channels and persistent memory poisoning remain open problems (CSA note above).
- Supply chain: ClawHub skills were a malware vector; marketplace moderation is ongoing labor ([security-in-public post](https://openclaw.ai/blog/openclaw-security-in-public)).
- Platform/ToS risk: WhatsApp via unofficial Baileys, iMessage via private APIs, Claude subscription reuse based on informal staff assurance ([package.json](https://github.com/openclaw/openclaw/blob/main/package.json), [iMessage](https://docs.openclaw.ai/channels/imessage), [OAuth](https://docs.openclaw.ai/concepts/oauth)).
- Churn: ~5 tags/week, config-schema breaks handled by `openclaw doctor --fix` rather than aliases ([VISION.md](https://github.com/openclaw/openclaw/blob/main/VISION.md)); 9.6k open issues+PRs.
- Influence concentration: creator employed by OpenAI and OpenAI is a major donor, mitigated by Foundation governance (vendor claim) ([README](https://github.com/openclaw/openclaw/blob/main/README.md)).
- Chat-surface UX ceiling: rich review (diffs, artifacts, approvals) is awkward in third-party messengers [INFERENCE].

## Ideas worth taking for Memoshi

- **Gateway/node split**: one authoritative daemon owns state and credentials; devices join as capability-declaring nodes (`camera.*`, `screen.*`, `system.run`) over one typed WS protocol; clean model for "bot on my Mac + phone" ([architecture](https://docs.openclaw.ai/concepts/architecture)).
- **Workspace-as-Markdown persona/memory** (`SOUL.md`, `IDENTITY.md`, `USER.md`, `MEMORY.md`, daily notes) with UI editor: user-legible, diffable, importable from Claude Code/Codex/Hermes; adopt, but add provenance and integrity checks against poisoning ([Memory](https://docs.openclaw.ai/concepts/memory)).
- **Bootstrap ritual** (`BOOTSTRAP.md`) where a new bot names itself with the user; cheap delight for "hire a teammate" onboarding ([Agent workspace](https://docs.openclaw.ai/concepts/agent-workspace)).
- **Heartbeat as a scheduler-owned automation** with quiet acknowledgments and rate guards, separate from user cron jobs; gives "always-on" feel without spam ([Heartbeat](https://docs.openclaw.ai/gateway/heartbeat)).
- **Dreaming**: background consolidation from daily notes to curated memory with a human-reviewable diary; good answer to memory bloat ([Dreaming](https://docs.openclaw.ai/concepts/dreaming)).
- **Model-scoped runtime selection** (`agentRuntime.id` per model: own loop vs Codex vs Claude CLI vs ACP) instead of one global engine ([Agent runtimes](https://docs.openclaw.ai/concepts/agent-runtimes)).
- **Bot-to-bot pair loop protection and bounded multi-agent rounds** in shared rooms; required for any roster/group-chat design ([Bot loop protection](https://docs.openclaw.ai/channels/bot-loop-protection), [Broadcast groups](https://docs.openclaw.ai/channels/broadcast-groups)).
- **DM pairing codes** for unknown senders and `security audit` command; adopt as defaults if Memoshi bridges to external channels ([Pairing](https://docs.openclaw.ai/channels/pairing)).
- **Avoid**: host execution as the default, open skill marketplace without signing/scanning, and a single shared tool authority across users; Memoshi should default to per-bot sandboxes and per-user credentials [INFERENCE from incidents above].
- **Consider being OpenClaw-compatible rather than competing on channels**: LobsterAI and Microsoft Scout show the "own the app/product layer, run OpenClaw underneath" pattern ([LobsterAI README](https://github.com/netease-youdao/LobsterAI), [Microsoft blog](https://www.microsoft.com/en-us/copilot/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent/)).

## Open questions

- Actual active-user numbers: "4.5 million new claws per week" and Fast Company's "half a million systems" are unverified; would need Foundation telemetry disclosure (opt-in stats only).
- How much of the Pi SDK code was incorporated vs rewritten in `@openclaw/agent-core`, and license notice details: read `THIRD_PARTY_NOTICES.md` and `packages/agent-core`.
- Status of Anthropic subscription reuse: docs cite informal staff assurance; check Anthropic's published policy.
- Real-world exposure count today (TechTarget's >1M figure is third-party); a Shodan/Censys query for port 18789 would settle it.
- Whether Control UI is migrating to Solid (`ui:solid:inventory` script) and its current framework: inspect `ui/package.json`.
- Microsoft's upstream "policy conformance" contribution: locate the merged PRs.

## Sources

1. https://github.com/openclaw/openclaw (README, package.json, VISION.md, SECURITY.md, CHANGELOG/; GitHub API stats 2026-10-20)
2. https://github.com/openclaw/openclaw/blob/main/docs/agent-runtime-architecture.md
3. https://github.com/openclaw/openclaw/commit/bb46b79d
4. https://github.com/openclaw/openclaw/blob/main/CHANGELOG/2026.2.21.md ; https://github.com/openclaw/openclaw/blob/main/CHANGELOG/2026.3.13.md
5. https://docs.openclaw.ai/concepts/architecture
6. https://docs.openclaw.ai/channels
7. https://docs.openclaw.ai/concepts/agent-workspace
8. https://docs.openclaw.ai/concepts/memory ; https://docs.openclaw.ai/concepts/dreaming
9. https://docs.openclaw.ai/gateway/heartbeat ; https://docs.openclaw.ai/automation
10. https://docs.openclaw.ai/concepts/multi-agent ; https://docs.openclaw.ai/channels/broadcast-groups ; https://docs.openclaw.ai/channels/bot-loop-protection ; https://docs.openclaw.ai/channels/reef
11. https://docs.openclaw.ai/concepts/agent-runtimes ; https://docs.openclaw.ai/concepts/oauth
12. https://docs.openclaw.ai/gateway/sandboxing ; https://docs.openclaw.ai/gateway/cloud-sessions ; https://docs.openclaw.ai/nodes/computer-use
13. https://docs.openclaw.ai/gateway/remote ; https://docs.openclaw.ai/nodes ; https://docs.openclaw.ai/platforms ; https://docs.openclaw.ai/platforms/ios ; https://docs.openclaw.ai/platforms/android ; https://docs.openclaw.ai/platforms/macos ; https://docs.openclaw.ai/platforms/windows
14. https://docs.openclaw.ai/tools/browser ; https://docs.openclaw.ai/tools/skills ; https://docs.openclaw.ai/tools/exec-approvals ; https://docs.openclaw.ai/tools/permission-modes ; https://docs.openclaw.ai/tools/subagents
15. https://docs.openclaw.ai/gateway/security ; https://docs.openclaw.ai/channels/pairing ; https://docs.openclaw.ai/start/teams
16. https://docs.openclaw.ai/start/lore
17. https://openclaw.ai/blog/introducing-openclaw
18. https://openclaw.ai/blog/openclaw-security-in-public
19. https://openclaw.ai/blog/introducing-openclaw-foundation
20. https://openclaw.ai/press
21. https://www.microsoft.com/en-us/copilot/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent/
22. https://github.com/advisories/GHSA-g8p2-7wf7-98mq ; https://nvd.nist.gov/vuln/detail/CVE-2026-25253
23. https://api.npmjs.org/downloads/point/last-month/openclaw ; https://img.shields.io/discord/1456350064065904867.json
24. Derivative repos via GitHub API: HKUDS/nanobot, agentscope-ai/QwenPaw, zeroclaw-labs/zeroclaw, nanocoai/nanoclaw, sipeed/picoclaw, NVIDIA/NemoClaw, RightNow-AI/openfang, nearai/ironclaw, cloudflare/moltworker, nullclaw/nullclaw, netease-youdao/LobsterAI, TinyAGI/tinyagi, microclaw/microclaw, NevaMind-AI/memUBot, warengonzaga/tinyclaw, NousResearch/hermes-agent, openclaw/clawhub, openclaw/crabbox, openclaw/clawsweeper
25. (third-party) https://www.koi.ai/blog/clawhavoc-341-malicious-clawedbot-skills-found-by-the-bot-they-were-targeting ; https://snyk.io/blog/clawhub-malicious-google-skill-openclaw-malware/ ; https://www.broadcom.com/support/security-center/protection-bulletin/malicious-clawhub-skills
26. (third-party) https://www.wiz.io/blog/exposed-moltbook-database-reveals-millions-of-api-keys ; https://github.com/openclaw/openclaw/issues/7089
27. (third-party) https://labs.cloudsecurityalliance.org/wp-content/uploads/2026/06/CSA_research_note_openclaw_indirect_prompt_injection_20260613-csa-styled.pdf ; https://www.techtarget.com/cybersecurity/tip/OpenClaw-security-best-practices-for-CISOs ; https://arxiv.org/abs/2602.20021
28. (press) https://www.theregister.com/2026/01/27/clawdbot_moltbot_security_concerns ; https://www.reuters.com/business/openclaw-founder-steinberger-joins-openai-open-source-bot-becomes-foundation-2026-02-15 ; https://techcrunch.com/2026/02/15/openclaw-creator-peter-steinberger-joins-openai/ ; https://techcrunch.com/2026/06/02/microsoft-launches-scout-an-openclaw-inspired-personal-assistant/ ; https://techcrunch.com/2026/06/30/openclaw-is-finally-available-on-android-and-ios/ ; https://techcrunch.com/2026/01/30/openclaws-ai-assistants-are-now-building-their-own-social-network/ ; https://www.cnbc.com/2026/03/12/china-openclaw-ai-agent-adoption-tech-companies-government-support-lobster-shrimp.html ; https://www.semafor.com/article/04/03/2026/anthropic-eyes-its-own-version-of-openclaw ; https://www.geekwire.com/2026/microsofts-openclaw-team-takes-on-the-personal-assistant-challenge/ ; https://www.businessinsider.com/google-ai-agent-openclaw-remy-gemini-assistant-2026-5 ; https://blogs.windows.com/windowsdeveloper/2026/06/02/build-2026-furthering-windows-as-the-trusted-platform-for-development/
29. https://x.ai/news/introducing-grok-bot (contrast only)
