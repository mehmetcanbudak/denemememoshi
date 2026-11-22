# OpenBot (nightly-labs)

> Source-available Electron desktop app that wraps the coding CLIs you already pay for (Codex, Claude Code, Grok, OpenCode, Gemini, Cursor, Cline, Pi, Muse, any ACP agent) as persistent, named teammates with their own workspace folders, queues, routines, browser and agent-to-agent messaging, shareable with coworkers and phones over WebRTC. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

Disambiguation (not this product):
- **openbot.one**: an unrelated web/PWA app titled "OpenBot", manifest description "Your personal AI workspace", with workspaces, invite codes and a "cloud runtime" in its JS bundle; maker unknown, no link to nightly-labs found ([openbot.one](https://openbot.one), [manifest](https://openbot.one/manifest.webmanifest)).
- **CopilotKit OpenBot**: not just a proposal. It is a shipped MIT repo, created 2026-08-17, 6,694 stars as of 2026-10-20. It gives each AG-UI agent its own container with Chromium, files and tools, and routes every action through a policy and audit gateway ([CopilotKit/OpenBot](https://github.com/CopilotKit/OpenBot), [copilotkit.ai/openbot](https://www.copilotkit.ai/openbot)). It deserves its own profile.
- **Samuraizan/OpenBot**: a GitHub fork of `milind-soni/OpenMausBot` (MIT, 0 stars, last push 2026-08-18) ([GitHub API](https://github.com/Samuraizan/OpenBot)).
- **openbot.ai**: "the data engineering layer for Physical AI", covering robot datasets and the `openbot-data` CLI ([openbot.ai](https://openbot.ai)). It is unrelated to Intel's older OpenBot robotics project.
- **getopenbot.com**: "the world's first chief of staff agent" that dispatches Claude Code, Codex and Cursor; maker unknown ([getopenbot.com](https://www.getopenbot.com/)).

## Matrix row

```yaml
name: OpenBot
slug: openbot
category: oss-bot-roster-desktop   # source-available, not OSI open source
maker: Synthetify Labs sp. z o.o. (Poland), GitHub org nightly-labs, lead author Norbert Bodziony; Android listing published by Akudama Sàrl (Lausanne)
license: source-available (PolyForm Noncommercial 1.0.0; commercial use needs a paid license; <=0.1.11 Apache-2.0; CLA assigns copyright to Synthetify Labs)
repo: https://github.com/nightly-labs/openbot
website: https://openbot.run
first_public: 2026-08-13   # v0.1.0; repo created 2026-08-12
latest_release: v0.44.3, 2026-10-19
release_cadence: "~8 releases/week (78 desktop releases in 68 days)"
stars: 671 (as of 2026-10-20)
forks: 108
contributors: 28
primary_language: TypeScript
stack: "Electron 44.7, SolidJS 2 rc, Effect 4, Bun 1.4, node:sqlite event log + projections; TanStack Start on Cloudflare Workers + D1 + R2 (accounts/site); Bun Signal + coturn (WebRTC); Expo 57 / React Native 0.86 mobile"
platforms: [macos, windows, linux, ios, android, web]   # iOS = TestFlight beta only; web = openbot.run/app client to a host; Linux server + Docker image
agent_engine: wraps CLIs and SDKs (Codex app-server JSON-RPC, Claude Agent SDK, ACP for the rest, Pi RPC, Muse MSP)
engines_supported: [codex, claude-code, grok-cli, opencode, gemini-antigravity, cursor-cli, cline, pi, muse, custom-acp, openai-compatible-via-opencode, ollama, lm-studio]
model_access: subscription logins of each CLI (ChatGPT, Claude, SuperGrok, Google AI Pro/Ultra, Cursor, Cline, Meta), API keys (xAI, OpenCode Go, Gemini, Cursor, Cline, Meta, custom endpoints), local models, OpenCode free models
execution_env: user host (desktop), self-hosted Linux/Docker server, or vendor-hosted EU Linux VM; per-provider OS sandbox only in "Workspace only" mode (macOS sandbox-exec; Codex/Claude native sandboxes)
per_bot_computer: no (one shared host; a workspace folder per agent; Computer Use shares the host screen; hosted/self-hosted servers give agents a virtual display)
persistent_bots: yes (named agents with avatar, title, instructions, model, skills, memories, routines; survive restarts and provider switches)
memory: per-agent memory store (64-512 entries, essential/searchable/selectable tiers, tools remember/forget/search) + shared SQLite tables + history_search/history_read over the thread
routines: yes (timezone-aware schedules, cron, one-time, webhook triggers with signing secret, local-script trigger, routine flows chaining agents on a canvas, ICS feed)
group_chat: partial (agent-to-agent messages/delegation and sidebar-section teams; multi-agent "channels" deprecated 2026-10-13)
coding_workspace: partial (per-agent folder, file panel with previews/diffs of attachments, provider-native tools; no IDE, no git/worktree UI; GitHub connector)
browser_use: yes (embedded Chromium per app, CDP-driven, persistent tabs, takeover, live view to remote members)
computer_use: yes (bundled cua-driver on macOS/Windows/Linux; Sunshine/Moonlight remote desktop)
connectors: MCP (stdio + Streamable HTTP with OAuth), marketplace plugins/skills, native GitHub App, 1Password, Bitwarden, Composio listing via MCP link
channels: Slack, Discord, Telegram (orchestrator agent routes to teammates); webhooks; local scripts API/CLI; no email/SMS/voice call
mobile: yes (iOS TestFlight beta, Android on Google Play; remote client paired to a host; push + Live Activities)
voice: dictation only (local Parakeet TDT / Whisper, optional ElevenLabs Scribe); no TTS or calls
approvals: per-agent Workspace only / Ask first / Full access (default Full access); approval and question cards on desktop, Dynamic Island, mobile, Slack/Discord/Telegram buttons
e2e_encryption: partial (team/mobile traffic is peer-to-peer WebRTC, so Cloudflare and TURN never see plaintext [INFERENCE]; push payloads sealed per phone)
self_host: yes (desktop host, Linux server installer, Docker/ECS image, self-hostable account + Signal + TURN)
multi_user: yes (owner/admin/member roles on a host; plan seats 3/10/25; shared agents and conversations)
pricing: "app $0 for noncommercial use; commercial license by email; hosted EU server from EUR 20 / USD 25 per month (Starter/Standard/Pro); model costs via your own provider plans"
maturity: beta ("development preview" per README; 78 releases in 68 days; ~24k installer downloads)
```

## What it is

OpenBot is a desktop control plane that turns the coding-agent CLIs on your machine into a roster of named, long-lived "teammates" ([README](https://github.com/nightly-labs/openbot#readme)). It does not train or host models. It starts each vendor CLI as a child process and gives every agent four durable things: a workspace directory, a thread, an identity, and a private provider session that is kept apart from the thread so the model can change without losing context ([OpenBot 101](https://openbot.run/guides/openbot-101)).

The maker calls it "a free, open-source, local-first alternative to Grok Bot" ([Introducing OpenBot](https://openbot.run/news/introducing-openbot)). The code is actually under PolyForm Noncommercial, so it is source-available, not open source ([LICENSE](https://github.com/nightly-labs/openbot/blob/main/LICENSE)). The pitch is "multiplayer": coworkers join your OpenBot host, see the same agents and conversations, and agents pass work to each other ([Introducing OpenBot](https://openbot.run/news/introducing-openbot)).

Target users are individuals and small teams who already pay for ChatGPT, Claude or SuperGrok, and want agents running on their own Mac mini, VPS or a hosted server instead of in a vendor cloud ([Introducing OpenBot](https://openbot.run/news/introducing-openbot), [hosted servers guide](https://openbot.run/guides/openbot-hosted-servers)). Messaging is mostly comparative: the site has comparison pages against Grok Bot, Muse, Hermes Agent, OpenClaw, Manus, Claude Cowork, Devin, ChatGPT dots and Instinct ([CHANGELOG 0.23.0, 0.29.0, 0.40.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).

## Product and UX

- **Layout.** It looks like a messenger. A left page rail opens Agents, Routines, Schedule, Usage, Marketplace and Settings, and shows each provider's plan limits as rings. A sidebar lists agents in user-defined sections plus a "Needs you" group. The center is the chat. A tabbed side panel holds Browser, Files, Tasks and Agent settings ([CHANGELOG 0.42.0, 0.25.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). On macOS, a notch "Dynamic Island" overlay shows replies, questions, approvals and browser takeovers, and you can answer from it ([CHANGELOG 0.4.0, 0.35.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Onboarding.** A language wheel comes first. Then one question: "Start free" (downloads OpenCode and uses its free models, no sign-in) or "I have a subscription" (ChatGPT, Claude or Grok). On macOS, the only other step is the Computer Use permissions ([CHANGELOG 0.34.0, 0.36.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). Provider CLIs are downloaded and pinned on demand ([README](https://github.com/nightly-labs/openbot#agent-setup)).
- **Creating an agent.** You create one by prompt, by guided form (avatar, title, instructions, provider, model, reasoning effort), from a Marketplace template, from a published share link, or by importing a Grok Bot export ZIP. Agents can also create and configure other agents with `openbot.create_agent` and `openbot.update_profile` ([README](https://github.com/nightly-labs/openbot#what-works), [agents.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/agents.md), [CHANGELOG 0.21.0, 0.24.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Working.** Messages queue FIFO per agent and can be edited, reordered, or steered into a running turn (Codex and Claude only). An agent can run 1 to 4 parallel "tasks", each with its own provider thread ([CHANGELOG 0.31.0, 0.41.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). A Tasks page groups all agents' work into Needs you, Working, Waiting and Closed ([CHANGELOG 0.44.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). Plans render as live task lists. Agents can reply with sandboxed HTML "visual replies", Mermaid diagrams and interactive blocks such as buttons, chips and forms ([CHANGELOG 0.23.0, 0.31.0, 0.44.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Reviewing.** The thread shows the files opened and commands run under each answer ([OpenBot 101](https://openbot.run/guides/openbot-101)). Routine runs collapse into one row per run and can stay silent through `routine_no_update` ([agents.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/agents.md)).
- **Distinctive details.** You can switch providers mid-thread with a bounded handoff packet. Backup models take over when a plan hits its usage limit ([CHANGELOG 0.40.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). Usage and limit rings show per provider account. Several accounts per provider are supported, and each agent can be pinned to one ([CHANGELOG 0.39.1](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). The UI ships in 10 languages ([CHANGELOG 0.43.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).

## Architecture

**Components** ([README Architecture](https://github.com/nightly-labs/openbot#architecture), [ARCHITECTURE.md](https://github.com/nightly-labs/openbot/blob/main/docs/ARCHITECTURE.md)):

```text
Electron main
├── local Codex App Server process over stdio JSONL
├── local Claude Agent SDK session over stream JSON
├── ACP / Pi RPC / Muse MSP child processes
├── SQLite command log and read projections (openbot.db)
├── secure typed IPC handlers, Team API (loopback HTTP)
└── sandboxed WebContentsView browser host
    ↕ typed preload bridge (window.openbot)
SolidJS renderer
Hidden sandboxed page ── WebRTC DataChannels ── desktop/web/mobile clients
Cloudflare Workers (TanStack Start): accounts, D1, R2, marketplace, site
Signal (Bun, WebSocket) + coturn: connection setup and relay only
```

- `src/main` holds the Electron lifecycle, IPC and Team API routes (`src/main/team-api/route-*.ts`). `src/backend` holds the provider adapters, persistence, scheduling, transfers and browser host. `apps/auth-api` holds the account API and public site. `apps/mobile` is the Expo app. `remote/` holds the self-hostable Signal, coturn and ACME stack ([README](https://github.com/nightly-labs/openbot#architecture), [repo tree](https://github.com/nightly-labs/openbot)).
- **Stack:** Electron 44.7.0, SolidJS 2.0.0-rc.0, Effect 4.0.0, `@agentclientprotocol/sdk` 1.4.0, `@anthropic-ai/claude-agent-sdk` 0.3.263, `@muse-code/sdk` 1.4.2, and electron-updater ([package.json](https://github.com/nightly-labs/openbot/blob/main/package.json)). Mobile uses Expo ~57, React 19.2 and React Native 0.86 ([apps/mobile/package.json](https://github.com/nightly-labs/openbot/blob/main/apps/mobile/package.json)).

**Agent harness: one internal protocol, many adapters.**
- Every adapter implements `AgentClient` (`src/backend/agent-client.ts`). Its events and requests are typed as `AppServerNotification` and `AppServerRequest`, which is the Codex App Server JSON-RPC vocabulary. So Codex's wire format is the normalized internal protocol, and the other adapters translate into it ([agent-client.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/agent-client.ts)).
- `src/backend/provider-drivers.ts` builds each client and its sign-in mode. The modes are browser, CLI command, terminal, device code, Muse device flow, and ACP `authenticate` ([provider-drivers.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/provider-drivers.ts)).

| Engine | Adapter file | Wire | Notes |
| --- | --- | --- | --- |
| Codex | `src/backend/app-server-client.ts` | `codex app-server --listen stdio://` JSON-RPC | Native sandbox modes `workspace-write` / `danger-full-access` ([app-server-client.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/app-server-client.ts), [workspace-sandbox.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/agent/workspace-sandbox.ts)) |
| Claude Code | `src/backend/claude-client.ts` | Claude Agent SDK `query()`, stream JSON; OpenBot tools as an SDK MCP server | `canUseTool` callback enforces Workspace only and routes `AskUserQuestion` ([claude-client.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/claude-client.ts)) |
| Grok CLI | `src/backend/grok-client.ts` extends `AcpAgentClient` | ACP | Adds xAI login and billing hooks ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md)) |
| OpenCode | `acp-client.ts` + `opencode-config.ts` | `opencode acp` | Also carries custom OpenAI-compatible endpoints ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md)) |
| Gemini | `acp-client.ts`, `acp-sign-in.ts` | Google Antigravity ACP server (`agy_acp_server`), downloaded on the user's machine | No redistribution licence; `oauth-personal` ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md#gemini)) |
| Cursor | `acp-client.ts` | `cursor-agent acp` | Confined config dir `~/.cursor/openbot-confined` |
| Cline | `acp-client.ts` | `cline --acp` | Forces `CLINE_SESSION_BACKEND_MODE=local` so no detached hub escapes the sandbox |
| Custom ACP | `custom-acp-agents-client.ts` | ACP, one process per agent per folder | ACP registry install from `cdn.agentclientprotocol.com` |
| Pi | `pi-client.ts`, `pi-rpc.ts` | `--mode rpc` (no ACP) | MCP via a small `registerMcpServer` extension |
| Muse (Meta) | `muse-client.ts` | `@muse-code/sdk`, `muse serve` over MSP | Meta device sign-in |

- **ACP split.** `acp-connection.ts` handles transport, `acp-configuration.ts` handles config and model discovery, and `acp-client.ts` handles sessions, streaming, permissions, tool bridging and cancellation ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md)).
- **What is normalized.** Turns and items, plans, approvals and questions, context usage and compaction (`contextCompaction: events | request | native | unsupported`), usage limits, history import, and session resume ([agent-client.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/agent-client.ts), [providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md)). Under `canUseTool`, Claude's own tools are auto-allowed. Only writes outside the workspace (in Workspace only mode) and `AskUserQuestion` go to OpenBot ([claude-client.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/claude-client.ts)).
- **Built-in tools.** `agent/tool-catalog.ts` gives every adapter nine direct tools: `ask_user`, `attach_files_to_response`, `list_agents`, `send_message`, `search_memories`, `remember`, `forget_memory`, `react_to_user_message` and `routine_no_update`. It adds three discovery tools (`tool_search`, `tool_describe`, `tool_call`) that lazy-load everything else. The maker reports this cut default instruction plus tool text by 80.4%, from about 25.4k to about 5.0k tokens. The design cites Hermes's on-demand discovery as its reference ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md)). ACP, Pi and Muse receive these tools through a local MCP bridge.
- **Instruction delivery.** Developer instructions go to Codex as `developerInstructions` and get appended to the Claude and Pi system prompts. Grok and other ACP agents get them as a tagged block in turn input. Muse gets them first in turn input ([agents.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/agents.md)).
- **Provider switch handoff.** A replacement session gets a packet of at most 32,000 characters: 24k recent messages, 4k older excerpts, 2k captured work steps and 2k instructions. The agent can then call `history_search` and `history_read` to recover the rest ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md)).
- **Runtime management.** OpenBot downloads and pins each CLI per platform. It checks upstream hourly and verifies npm integrity or GitHub digests. Grok, Gemini and Cursor have no published hash, so those downloads are trusted on TLS alone. A remote `provider-runtime-blocklist.json` can pull a bad upstream version ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md#provider-cli-updates)).

**Models and auth.**
- OpenBot reuses each CLI's own login (`~/.codex`, `~/.claude`, `~/.grok`, `~/.gemini`, `~/.cursor`, `~/.cline`) and "does not copy provider credentials" ([README](https://github.com/nightly-labs/openbot#local-data-and-network-boundaries)).
- Optional keys (OpenCode Go, custom endpoints, custom-agent env) are encrypted with Electron `safeStorage` in a `0600` envelope, and no IPC getter returns them ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md)).
- For multiple accounts, each additional account gets its own CLI home directory, selected by an environment variable ([provider-drivers.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/provider-drivers.ts)).
- On a remote host, owners and admins can sign in through a relay: device code, paste-back, or the host's browser shown through live view ([CHANGELOG 0.38.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- The maker publishes a separate provider-terms note for Claude subscriptions ([docs/provider-terms.md](https://github.com/nightly-labs/openbot/blob/main/docs/provider-terms.md)).

**Execution environment.**
- Every agent runs on the host, with cwd `~/OpenBot/Agents/<agent-id>` and extra access to `~/OpenBot/Shared` ([README](https://github.com/nightly-labs/openbot#local-data-and-network-boundaries)).
- Hosts can be a desktop, a Linux server (`install-server.sh`, systemd), Docker (`ghcr.io/nightly-labs/openbot` with seccomp, Electron sandbox on), AWS ECS, a multi-tenant macOS "Host package", or a vendor-hosted EU Linux VM ([README](https://github.com/nightly-labs/openbot#linux-server-with-no-screen), [docs/docker.md](https://github.com/nightly-labs/openbot/blob/main/docs/docker.md)).
- Docker hosts can run several isolated instances, each with its own CPU, memory and disk limits ([CHANGELOG 0.39.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- There is no per-agent container or VM.

**State and storage.**
- `userData/openbot.db` is the canonical event log plus projections: agents, conversations, provider session bindings, queues, reactions and attachment indexes ([README](https://github.com/nightly-labs/openbot#local-data-and-network-boundaries)).
- Transfers live under `~/OpenBot/Shared/Transfers`, each with a `.openbot-transfer.json` manifest carrying a SHA-256. Agent-created tables live in `~/OpenBot/Shared/Data/agent-data.db` ([README](https://github.com/nightly-labs/openbot#local-data-and-network-boundaries), [CHANGELOG 0.13.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- Native provider transcripts stay in each CLI's own directory. There is no cloud sync of chats. "Server transfer" export/import moves agents between hosts ([CHANGELOG 0.39.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).

**Remote and mobile.**
- "Publishing" keeps the Team API on loopback. A hidden sandboxed Electron page bridges it to clients over WebRTC DataChannels (protocol v2/v3 frames, application codecs v1–v7). Signal only exchanges setup messages, and coturn relays when ICE fails ([README](https://github.com/nightly-labs/openbot#commands), [providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md#protocol-compatibility)).
- Cloudflare stores accounts, memberships, invitations and session records, but "does not carry chats, files, commands, or remote desktop media" (vendor claim, consistent with the architecture).
- Mobile pairs by QR "Mobile Connect" ticket or a revocable permanent link. Headless servers can print one with `openbot mobile-connect` ([CHANGELOG 0.5.0, 0.37.0, 0.38.1](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- The web client runs at `openbot.run/app` ([CHANGELOG 0.19.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). All of this transport is self-hostable ([docs/self-hosting.md](https://github.com/nightly-labs/openbot/blob/main/docs/self-hosting.md)).

**Extension surface.**
- MCP servers are host-global. Stdio servers can run on a managed Bun if the host has no Node. HTTP servers get OAuth handled by OpenBot through a local proxy that injects tokens ([CHANGELOG 0.15.3, 0.44.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- Skills follow the Codex `SKILL.md` folder format, with a versioned local library and `create_skill` / `revise_skill` tools ([README](https://github.com/nightly-labs/openbot#local-skills)).
- The Marketplace has Agents, Apps (plugins = MCP record plus pinned skills) and Skills ([CHANGELOG 0.13.0, 0.27.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- Automation surfaces: a loopback Local scripts HTTP API with bearer token, the `openbot-cli`, and signed webhooks ([agents.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/agents.md), [docs/automation.md](https://github.com/nightly-labs/openbot/blob/main/docs/automation.md)).

## Capabilities in detail

- **Persistent bots and identity.** Agents keep their workspace, thread, identity and provider session across restarts and model changes ([OpenBot 101](https://openbot.run/guides/openbot-101)). The queue survives crashes ([README](https://github.com/nightly-labs/openbot#what-works)). Browser tabs, URLs and agent ownership persist across restarts ([CHANGELOG 0.1.4](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). An idle CLI is stopped after 60 s to 10 min and resumed from its session on the next message ([CHANGELOG 0.19.0, 0.21.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). Agents can be hidden instead of deleted, and their routines pause while hidden ([agents.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/agents.md)). They can be published as share-link templates; files and memories are excluded, and publishing stops if a field looks like a secret ([CHANGELOG 0.21.1](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Workspaces and handoff.** Each agent has one directory, kept between runs, plus one shared directory "for handoffs". The maker states plainly that "a workspace organizes work. It does not limit what an agent can touch" in the default Full access mode ([Every agent gets a workspace](https://openbot.run/news/every-agent-gets-a-workspace)). Managed file transfers between agents carry an ownership and integrity manifest ([README](https://github.com/nightly-labs/openbot#local-data-and-network-boundaries)).
- **Memory.**
  - Per-agent memories hold 64 to 512 entries, set per host ([CHANGELOG 0.34.0, 0.44.1](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Each memory is marked essential (fixed prompt budget), searchable or selectable ([CHANGELOG 0.35.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Memories go into instructions last, after stable rules and profile ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md)).
  - Separate stores hold Slack, Discord and Telegram workspace facts ([CHANGELOG 0.38.1](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - A shared SQLite database lets agents create their own tables, including FTS5 ([CHANGELOG 0.13.0, 0.40.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Memory is not semantic or vector-based. History search is local keyword matching ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md)).
- **Routines and automation.**
  - Schedules: timezone-aware, cron with validation, and one-time runs ([CHANGELOG 0.2.1, 0.40.0, 0.44.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Triggers: webhooks with a signing secret and event filters ([CHANGELOG 0.33.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)), and local scripts ([CHANGELOG 0.29.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Policies for missed runs and usage limits ([CHANGELOG 0.30.0, 0.37.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)), and quiet runs that post nothing when there is no news ([agents.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/agents.md)).
  - Routine flows link agents on a canvas; an agent waits for all its inputs before it runs ([CHANGELOG 0.34.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Results can be delivered to Slack, Discord or Telegram ([CHANGELOG 0.40.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). An ICS calendar feed lists upcoming runs ([CHANGELOG 0.31.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - An agent can park a request with "waits" until an outside event such as a build finishes ([CHANGELOG 0.38.1](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Hosted servers wake shortly before a scheduled routine ([CHANGELOG 0.25.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Multi-bot collaboration.**
  - Agents message and delegate with `send_message`, track teammates with `list_agents`, and stop delegated work with `interrupt_agent`, but only work they started. Replies from several teammates are batched into one turn ([agents.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/agents.md)).
  - Channels (multi-agent rooms with one task owner, Stop, Reassign, and so on) shipped in 0.8.0 and were deprecated in 0.38.1. They were replaced by "agents in one sidebar section know each other and send work to each other first" ([CHANGELOG 0.8.0, 0.38.1](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Coding workspace.**
  - Coding happens inside the wrapped CLIs. OpenBot adds a file panel with code highlighting, HTML/XLSX/Markdown/email previews and folder views ([CHANGELOG 0.12.0, 0.31.0, 0.35.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - A native GitHub App connector posts issues and PRs as `openbotgit[bot]` ([CHANGELOG 0.25.2](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Static site hosting is available on openbot.run, with per-plan site limits ([CHANGELOG 0.27.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - There is no diff review UI, terminal pane or worktree manager [INFERENCE from changelog and README; none found].
- **Browser use.**
  - The embedded Chromium is a separate sandboxed Electron session, driven by native CDP since "Browser Automation V2" ([README](https://github.com/nightly-labs/openbot#local-data-and-network-boundaries), [CHANGELOG 0.5.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Users can take over a tab at any time ([CHANGELOG 0.44.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). Remote members get a live view with input ([CHANGELOG 0.14.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Logins can be filled from 1Password or Bitwarden "Shared with OpenBot" vaults without the agent seeing the secret ([CHANGELOG 0.30.0, 0.31.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Snapshot output is capped at 20k characters ([CHANGELOG 0.24.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Computer use.**
  - The bundled `cua-driver` runs as an OpenBot child process and is exposed to every provider as MCP ([README](https://github.com/nightly-labs/openbot#what-works), [CHANGELOG 0.17.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Screen capture requires approval for each capture ([CHANGELOG 0.39.1](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - On hosted, self-hosted and Docker servers, agents get their own virtual display ([CHANGELOG 0.43.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Human remote desktop uses bundled Sunshine and Moonlight Web, built from source ([CHANGELOG 0.1.14](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Connectors.** MCP, a Marketplace catalog (Linear, Notion, Figma, Sentry, Stripe, Vercel, Canva, Paper, Cobrain, Composio by link, and others), GitHub, 1Password and Bitwarden ([CHANGELOG 0.14.0, 0.20.0, 0.24.0, 0.35.0, 0.39.1](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Channels.** Slack, Discord and Telegram each get an "Orchestrator" agent that routes requests to the best teammate and answers in-thread with approvals, Stop and files. Events reach the host through Signal ([CHANGELOG 0.28.0, 0.31.0, 0.34.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md), [docs/messaging.md](https://github.com/nightly-labs/openbot/blob/main/docs/messaging.md)). Agents can post proactively with `messaging_post` ([CHANGELOG 0.38.2](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). Signal holds an encrypted message for up to 10 minutes while it wakes a sleeping hosted server ([CHANGELOG 0.38.1](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). No email, SMS, WhatsApp or iMessage channel was found.
- **Voice.** Dictation only. The local default is NVIDIA Parakeet TDT 0.6B v3 (25 European languages), with Whisper large-v3 turbo optional and ElevenLabs Scribe v2 Realtime available with your own key. Voice prompts are unavailable on Linux ([CHANGELOG 0.35.0, 0.37.0, 0.38.1](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md), [README](https://github.com/nightly-labs/openbot#linux)).
- **Mobile.**
  - Expo app `run.openbot.mobile`, v1.3.2 released 2026-10-17 and 1.3.3 in review ([apps/mobile/CHANGELOG.md](https://github.com/nightly-labs/openbot/blob/main/apps/mobile/CHANGELOG.md)).
  - Android is on Google Play under developer "Akudama Sàrl" with 500+ downloads, updated 2026-10-16 ([Google Play](https://play.google.com/store/apps/details?id=run.openbot.mobile)).
  - iOS is a TestFlight public beta only; the App Store lookup for the bundle id returns no results ([CHANGELOG 0.24.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md), [iTunes lookup](https://itunes.apple.com/lookup?bundleId=run.openbot.mobile)).
  - Features: chats, agent create/edit, dictation, search, routine test runs, browser live view with cursor, push notifications and Live Activities ([CHANGELOG 0.21.0, 0.34.0, 0.38.2, 0.40.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Team features.**
  - Owner, admin and member roles. Admins manage providers, MCP, skills, updates and agent permissions. Members chat and use agents ([CHANGELOG 0.22.0, 0.43.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Invitations are single-use or permanent links. Seat limits are 3 with no plan, then 3, 10 or 25 by plan ([CHANGELOG 0.15.3, 0.25.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md), [billing.ts](https://github.com/nightly-labs/openbot/blob/main/packages/contracts/src/billing.ts)).
  - Cursor and Cline agents originally stayed local-only; 0.31.0 exposed them to joined servers ([CHANGELOG 0.31.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).

## Security and trust model

- **Default posture.** The README still warns that agents run with `danger-full-access` and `approvalPolicy: never` after first-launch consent, and that this is "an explicit current product decision, not a security boundary" ([README](https://github.com/nightly-labs/openbot#security)). Since then, per-agent Permissions were added: Workspace only, Ask first, and Full access, which is the default ([CHANGELOG 0.22.0, 0.43.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). Turbo mode was folded into Full access ([CHANGELOG 0.43.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Workspace only enforcement.** This mode lets an agent write only to its workspace, `~/OpenBot/Shared` and the temp folders. Reads and network stay open.
  - Codex uses its native `workspace-write` sandbox. Claude is checked inside `canUseTool` ([workspace-sandbox.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/agent/workspace-sandbox.ts)).
  - CLI providers run under a generated macOS `sandbox-exec` Seatbelt profile that also protects each CLI's settings, hooks and MCP files ([process-confinement.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/process-confinement.ts)).
  - On Linux and Windows, confinement fails closed: those agents refuse to start in Workspace only. The code says bubblewrap "cannot deny a protected file that does not exist yet" ([process-confinement.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/process-confinement.ts)).
- **Approval flow.** The ACP adapter maps `session/request_permission` onto Codex-style `item/commandExecution/requestApproval`, `item/fileChange/requestApproval` and `item/permissions/requestApproval` requests, then picks the best matching ACP option from the user's decision ([acp-client.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/acp-client.ts)). A host-side `AttentionRegistry` collects these. They surface on desktop, the Dynamic Island, mobile, the web client, Slack/Discord/Telegram buttons, and the Local scripts API ([agents.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/agents.md), [CHANGELOG 0.28.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). Only owners or admins can press "dangerous" interactive-block buttons ([CHANGELOG 0.44.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). Agents cannot grant Full access, Computer Use or MCP changes to other agents ([CHANGELOG 0.24.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Secrets.**
  - Keys and OAuth tokens are stored with `safeStorage` or the OS keychain ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md), [CHANGELOG 0.15.3](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Since 0.44.0, agents never receive MCP OAuth tokens; a local proxy injects them ([CHANGELOG 0.44.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Secure browser prompts keep passwords out of transcripts ([CHANGELOG 0.17.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Logs, diagnostics, crash reports and analytics are redacted on exit ([What gets redacted](https://openbot.run/news/what-gets-redacted-before-it-leaves), [CHANGELOG 0.43.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Network exposure.** The Team API, Local scripts API and routine ICS feed bind to `127.0.0.1` and reject foreign `Origin` and `Host` headers ([agents.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/agents.md)). Remote access goes over WebRTC. Webhooks are relayed through Signal ([README](https://github.com/nightly-labs/openbot#local-data-and-network-boundaries)).
- **Telemetry.**
  - OpenPanel product analytics records tool, plugin, domain and routine usage plus daily counts. Opt-out is in Settings. Mobile analytics defaults to on ([CHANGELOG 0.8.0, 0.25.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md), [PRIVACY.md](https://github.com/nightly-labs/openbot/blob/main/PRIVACY.md)).
  - The website stores first-visit attribution on the account ([CHANGELOG 0.39.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Error reports exclude messages, prompts and paths (vendor claim, [CHANGELOG 0.32.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Supply chain.** macOS builds are signed and notarized. Windows has been signed by Synthetify Labs since 0.31.0. Linux AppImages are unsigned. Releases ship SBOMs and Sigstore attestations ([README](https://github.com/nightly-labs/openbot#releases), [release v0.44.3](https://github.com/nightly-labs/openbot/releases/tag/v0.44.3)).
- **Incidents.** No GitHub security advisories and no issues with "security" in the title (searched 2026-10-20). The 0.43.0 and 0.44.0 notes fix real issues:
  - Attachments from remote members could be executed with "Open".
  - A JWKS endpoint could publish a private key if one was misconfigured.
  - Removed members could rejoin with old invitations.
  - Any account could send invitation emails.
  ([CHANGELOG 0.43.0, 0.44.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md))

## Traction and momentum

- **GitHub (as of 2026-10-20):** 671 stars, 108 forks, 5 watchers, 28 contributors. There are 1,791 commits on `main`, 1,594 merged PRs and 715 issues. Repo created 2026-08-12, last push 2026-10-20 ([GitHub API](https://github.com/nightly-labs/openbot)).
- **Who builds it:** top committers are NorbertBodziony (1,154), Sniezka1927 (325) and nrb-dev (194), so it is a small core team ([contributors](https://github.com/nightly-labs/openbot/graphs/contributors)). Agent-tooling files in the repo (`.claude`, `.codex`, `.agents`, `AGENTS.md`) suggest heavy agent-assisted development [INFERENCE].
- **Releases:** 78 desktop releases from v0.1.0 (2026-08-13) to v0.44.3 (2026-10-19), roughly 8 per week. The installers (`.dmg`, `.exe`, `.AppImage`) total 24,237 downloads across all releases ([GitHub releases API](https://github.com/nightly-labs/openbot/releases)). Android has 500+ installs ([Google Play](https://play.google.com/store/apps/details?id=run.openbot.mobile)). A Product Hunt launch existed (banner removed in 0.34.0) ([CHANGELOG 0.31.0, 0.34.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). There is a Discord community at discord.openbot.run ([CHANGELOG 0.40.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Business model:**
  - The app is free for noncommercial use and sold as a commercial license (licenses@openbot.run) ([README](https://github.com/nightly-labs/openbot#license-and-attribution)).
  - Paid hosted EU servers (Germany, Finland, France) start at EUR 20 / USD 25 per month. Starter is 12 GB / 3 seats / 3 sites; Standard 50 GB / 10 seats / 10 sites at 2x speed; Pro 100 GB / 25 seats / 50 sites at 4x speed. Yearly billing is 20% off; billing runs through Stripe in EUR, USD and PLN ([competitor page: openbot.run/compare/grok-bot](https://openbot.run/compare/grok-bot), [billing.ts](https://github.com/nightly-labs/openbot/blob/main/packages/contracts/src/billing.ts), [hosted servers guide](https://openbot.run/guides/openbot-hosted-servers)).
  - Custom deployments are sold through a "For Teams" page ([CHANGELOG 0.41.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
  - Model costs stay on the user's own provider plans. The landing page says "$0" ([PricingSection.tsx](https://github.com/nightly-labs/openbot/blob/main/apps/auth-api/src/components/landing/PricingSection.tsx)).
- **Corporate identity.** The copyright, license and Windows signing all name Synthetify Labs spółka z o.o. ([README](https://github.com/nightly-labs/openbot#license-and-attribution)). The Android publisher is Akudama Sàrl, Lausanne, with contact hello@nightly.app ([Google Play](https://play.google.com/store/apps/details?id=run.openbot.mobile)). The GitHub org `nightly-labs` dates from 2022 and has 71 public repos. It is likely the team behind the Nightly crypto wallet [INFERENCE].
- **Content dating.** Several openbot.run news posts are dated July–August 2026, before the repo existed (for example "Every agent gets a workspace", dated 2026-07-24). The "Introducing OpenBot" article was added in 0.10.0 on 2026-09-15 ([news feed](https://openbot.run/news), [CHANGELOG 0.10.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)). This looks like backdated SEO content [INFERENCE].

### Feature timeline (from CHANGELOG.md)

Source: [CHANGELOG.md](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md). Patch releases are folded into the nearest row when they contain only fixes.

| Version | Date | Headline changes |
| --- | --- | --- |
| 0.1.0 | 2026-08-13 | First public release (Apache-2.0). Codex App Server lifecycle with ChatGPT login; persistent agents with own threads and workspaces; FIFO queues; agent-to-agent messages and file transfers; embedded browser; optional macOS Computer Use; context-budget compaction; signed auto-update; full-access consent at first launch |
| 0.1.1–0.1.11 | 08-13 → 08-16 | Claude CLI provider; per-agent provider and model; persisted browser tabs; Windows x64 builds (unsigned) |
| 0.1.14 | 2026-08-22 | **License changed to PolyForm Noncommercial 1.0.0**; P2P Remote Control (bundled Sunshine/Moonlight); local Whisper dictation; universal invitation links |
| 0.1.15–0.1.22 | 08-22 → 08-24 | Conversational profile edits; managed transfer manifests with SHA-256; message search, Markdown, read state; CSP; browser picture-in-picture |
| 0.2.0–0.2.1 | 08-24 → 08-25 | Create Bot flow; **scheduled routines** (timezone-aware, run history); **agent memories**; sidebar sections; skills marketplace |
| 0.3.0–0.3.5 | 08-26 → 08-27 | **Grok CLI provider**; composer attachments; reactions; provider runtimes downloaded on demand from pinned vendor artifacts |
| 0.4.0–0.4.3 | 08-30 → 09-02 | macOS Dynamic Island overlay for questions and approvals; Team API version negotiation; self-hosted Signal + coturn; WebRTC Team API v2, retiring the cloudflared tunnel |
| 0.5.0 | 2026-09-07 | **Phone pairing** (mobile app); session and device revocation; Browser Automation V2 over native CDP; guided agent setup; "bot" renamed to "agent" everywhere |
| 0.6.0 | 2026-09-08 | Usage and cost reports; mobile server settings and invite QR |
| 0.7.0 | 2026-09-09 | **OpenCode via ACP** (4th provider); Team API v4; model search |
| 0.8.0 | 2026-09-11 | **Channels** (multi-agent rooms); custom OpenAI-compatible endpoints; OpenCode free models; mobile attachments; mobile analytics on by default |
| 0.9.0 | 2026-09-14 | Linux AppImage; per-agent **skills**; i18n (Japanese); /news and /guides |
| 0.10.0–0.10.1 | 09-15 | MCP server management; mobile channels; repo moved to `nightly-labs/openbot`; "Introducing OpenBot" article |
| 0.11.0–0.12.0 | 09-16 → 09-17 | Edit queued messages; Marketplace detail pages; XLSX and Markdown previews |
| 0.13.0 | 2026-09-18 | Marketplace **Plugins** (MCP + skills); shared agent SQLite tables; no-reply teammate messages; usage for all providers |
| 0.14.0–0.14.1 | 09-19 | Live view of a host browser tab for remote members; 14-plugin catalog |
| 0.15.3 | 2026-09-21 | Managed Bun for MCP; MCP elicitation; permanent invite links; macOS multi-tenant Host package; OpenBot-held OAuth for HTTP MCP |
| 0.16.0–0.17.0 | 09-21 | Device-code ChatGPT login; standing approval and Turbo mode; **cua-driver Computer Use for all providers**; secure password prompts |
| 0.18.0–0.20.1 | 09-23 | French; routine status marks; **web client at openbot.run/app**; Storage tab; notification levels; Workspace only flag (not yet enforced); Linux arm64; Composio listing |
| 0.21.0–0.21.2 | 09-24 → 09-26 | **Import agents from Grok Bot**; mobile dictation; **publish agent as template**; local trace log |
| 0.22.0 | 2026-09-26 | **Gemini via Antigravity ACP**; **Workspace only enforced**; admins manage a joined host remotely |
| 0.23.0 | 2026-09-27 | Plan task lists; "Waiting for replies" block; agents can stop delegated work and create agents on chosen models; /compare pages |
| 0.24.0 | 2026-09-28 | Agents configure other agents; local model and ACP agent detection (Ollama, LM Studio); **custom ACP agents**; iPhone TestFlight beta; Intel macOS build; 3-member host limit |
| 0.25.0–0.25.2 | 09-29 | **Hosted servers** (Stripe plans, Starter/Standard/Pro); host updates from clients; LaTeX; "Needs you" group; GitHub App connector; encrypted Live Activity push |
| 0.26.0 | 2026-09-30 | Hosted-server self-update, memory guards and turn concurrency caps; idle tab unloading |
| 0.27.0 | 2026-10-01 | **Cursor CLI provider**; Turkish; global ⌘K search; per-server hosted-site limits; full-screen Marketplace |
| 0.28.0 | 2026-10-02 | **Slack connector with Orchestrator agent**; **Cline provider**; Brazilian Portuguese; self-hosted account and Signal service; Schedule calendar; provider restart |
| 0.29.0 | 2026-10-02 | **Local-script routine trigger**; headless Linux server installer; provider diagnostics log |
| 0.30.0 | 2026-10-05 | Agent-suggested Marketplace apps; **official Docker image**; 1Password; routine usage-limit policy; provider switch carries work log |
| 0.31.0 | 2026-10-07 | Visual HTML replies and Mermaid; steer-while-working; durable send/retry; **Discord connector**; Bitwarden; routine ICS feed; signed Windows builds |
| 0.32.0–0.33.0 | 10-07 | Error reporting; paged provider history; **webhook-triggered routines** |
| 0.34.0–0.34.1 | 10-09 | **Routines canvas and routine flows** (agent to agent chains); **Telegram**; Russian, Spanish, German; quiet runs; OAuth for HTTP MCP; "Start free" onboarding; Android app |
| 0.35.0–0.35.2 | 10-10 | **Native Pi RPC and Muse MSP providers**; ACP registry install; memory tiers and search; Parakeet dictation; lazy tool discovery (fewer context tokens) |
| 0.36.0 | 2026-10-10 | Polish; language wheel; resource diagnostics; AWS ECS guide |
| 0.37.0 | 2026-10-11 | Missed-run policy; `openbot mobile-connect` for servers; code login for Grok, Cursor, Cline and Muse; Gemini API key; Whisper large-v3 turbo |
| 0.38.0 | 2026-10-12 | Relayed sign-in (providers, MCP, connectors) from a member's own browser to the host; MCP sign-in apps |
| 0.38.1–0.38.2 | 10-13 | Messaging wakes sleeping servers; ElevenLabs dictation; routines canvas on web; **agent waits**; permanent mobile link; messaging workspace memory; **channels deprecated** (sections replace them); proactive `messaging_post`; Italian; iPhone push |
| 0.39.0–0.39.1 | 10-14 | Server-to-server agent transfer; multi-instance Docker; operator claim login; Vercel app; agent screen capture; **multiple accounts per provider** |
| 0.40.0 | 2026-10-15 | **Backup models on usage limit**; server timezone; routine delivery to Slack, Discord and Telegram; one-time routines; Docker backup and restore; Android push |
| 0.41.0 | 2026-10-16 | **Agent tasks** (1–4 parallel threads per agent); For Teams page; database integrity and growth fixes |
| 0.42.0 | 2026-10-16 | Page-rail redesign; Settings as a page; tabbed side panel; licensor named in LICENSE |
| 0.43.0 | 2026-10-17 | **Permissions: Workspace only / Ask first / Full access** (Turbo removed); `openbot-cli` and Local scripts API v2; side questions; quotes; status page; agent virtual display on servers; hide agents; security fixes |
| 0.44.0–0.44.3 | 10-18 → 10-19 | **Interactive ask blocks** (buttons, chips, forms); Tasks page; browser takeover anytime; MCP token proxy (agents never see OAuth tokens); profile activity stats; message rail |

## Strengths

- **Broadest engine coverage in the category**: ten built-in engines plus any ACP agent, all behind one `AgentClient` interface that reuses the Codex app-server vocabulary ([agent-client.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/agent-client.ts)). Users bring existing subscriptions with no per-token markup.
- **Real persistence model**: an event-sourced SQLite log, a crash-safe queue, provider-session resume, and a bounded cross-provider handoff with on-demand history tools ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md)).
- **Mature automation surface for a two-month-old project**: schedules, one-time runs, webhooks, local scripts, routine flows, quiet runs, missed-run and usage-limit policies, and waits ([CHANGELOG](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Local-first multiplayer without a data-carrying cloud**: WebRTC P2P from desktop, web and mobile to the host, with self-hostable signal and TURN ([README](https://github.com/nightly-labs/openbot#local-data-and-network-boundaries)).
- **Every deployment option**: a single binary covers desktop, headless Linux, Docker/ECS, a multi-tenant Mac host and a paid hosted VM.
- **Very high shipping velocity and documentation discipline**: per-feature architecture docs and an explicit Team API compatibility policy, with frozen protocol profiles v1–v7.

## Weaknesses and risks

- **License.** PolyForm Noncommercial blocks commercial use and forks, despite "open source" marketing ([LICENSE](https://github.com/nightly-labs/openbot/blob/main/LICENSE), [Introducing OpenBot](https://openbot.run/news/introducing-openbot)). The CLA assigns copyright to one company, which allows future relicensing.
- **Security posture.** The default is Full access on the user's real machine. Workspace only is macOS-only for most CLI providers, there is no per-agent isolation between agents, and Computer Use shares the user's screen ([process-confinement.ts](https://github.com/nightly-labs/openbot/blob/main/src/backend/process-confinement.ts), [Every agent gets a workspace](https://openbot.run/news/every-agent-gets-a-workspace)).
- **Platform and terms dependency.**
  - It wraps vendors' subscription CLIs. Their terms can change, as the Claude provider-terms doc shows ([docs/provider-terms.md](https://github.com/nightly-labs/openbot/blob/main/docs/provider-terms.md)).
  - Grok, Gemini and Cursor downloads are trusted on TLS only ([providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md#provider-cli-updates)).
  - Much changelog volume is per-CLI breakage repair: Grok `additionalDirectories`, OpenCode session loss, Gemini disk fill, Claude `--resume` ([CHANGELOG 0.40.0–0.44.1](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Product churn.** Channels shipped and were deprecated within 5 weeks. The permission model was rewritten three times (Turbo, Workspace only, then the Permissions setting). The README security warning lags the current model.
- **Scale and performance debt.** Many 0.40–0.43 fixes address database growth, O(n²) queue scans and memory on long histories ([CHANGELOG 0.41.0, 0.43.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Telemetry.** Analytics collects tool, plugin and domain usage by default with opt-out, and mobile analytics defaults to on ([CHANGELOG 0.8.0, 0.25.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)).
- **Mobile is incomplete.** No App Store release; iOS is TestFlight only.
- **Sustainability.** The team is small (three main committers). The corporate identity is split across a Polish company, a Swiss publisher and the nightly-labs org.

## Ideas worth taking for Memoshi

- **Adopt one canonical internal event protocol and write adapters into it.** OpenBot uses the Codex app-server JSON-RPC shapes. It makes approvals, plans and compaction uniform across ten engines.
- **Separate an agent's identity, thread and workspace from the provider session.** This makes "model is just a setting" true and survives vendor churn.
- **Use a bounded handoff packet plus `history_search` and `history_read` tools on provider switch or session loss.** It is cheaper than summarizing and degrades gracefully.
- **Lazy tool discovery (`tool_search`, `tool_describe`, `tool_call`).** The reported 80% cut in base prompt tokens matters when every bot carries platform tools.
- **Quiet routine runs via an explicit `routine_no_update` tool rather than a magic string.** Models are unreliable at exact tokens.
- **Missed-run, usage-limit and backup-model policies per routine and agent.** These are real failure modes for always-on bots on subscription plans.
- **Agent "waits" that park a request until an external event.** This is a clean primitive for builds, approvals and webhooks.
- **Keep the host as the data plane and the cloud as rendezvous only (WebRTC + Signal + TURN).** It suits a privacy-led positioning. Copy the Team API capability negotiation and the frozen protocol profiles.
- **Inject MCP OAuth tokens through a local proxy so agents never hold tokens.** Fill browser logins from a dedicated password-manager vault the agent cannot read.
- **Avoid shipping Full access as the default, and avoid OS-specific sandboxing that fails closed off macOS.** Memoshi should decide on per-bot isolation (container or VM) early. CopilotKit OpenBot is the contrast case.
- **Avoid naming collisions.** At least five unrelated "OpenBot" products exist, which hurts discovery.

## Open questions

- **Hosted plan prices per tier.** The amounts live in Stripe, not code, and `/v2/hosting/plans` requires sign-in. Signing in with a test account and opening the add-server dialog would show them.
- **Commercial license price and terms.** Ask licenses@openbot.run.
- **Relationship between Synthetify Labs, Akudama Sàrl and the Nightly wallet team.** Company registries and the Play developer page would settle it.
- **Whether Linux and Windows confinement is planned.** A bubblewrap or AppContainer issue search would tell.
- **Whether channels and their data have actually been removed after the 0.38.1 deprecation.** Read `src/backend` channel stores on the next release.
- **Real active-user numbers** beyond download counts. Unknown.

## Sources

1. https://github.com/nightly-labs/openbot (README, GitHub API stats as of 2026-10-20)
2. https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md
3. https://github.com/nightly-labs/openbot/blob/main/LICENSE
4. https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md
5. https://github.com/nightly-labs/openbot/blob/main/docs/architecture/agents.md
6. https://github.com/nightly-labs/openbot/blob/main/docs/ARCHITECTURE.md
7. https://github.com/nightly-labs/openbot/blob/main/src/backend/agent-client.ts
8. https://github.com/nightly-labs/openbot/blob/main/src/backend/provider-drivers.ts
9. https://github.com/nightly-labs/openbot/blob/main/src/backend/acp-client.ts
10. https://github.com/nightly-labs/openbot/blob/main/src/backend/claude-client.ts
11. https://github.com/nightly-labs/openbot/blob/main/src/backend/app-server-client.ts
12. https://github.com/nightly-labs/openbot/blob/main/src/backend/grok-client.ts
13. https://github.com/nightly-labs/openbot/blob/main/src/backend/agent/workspace-sandbox.ts
14. https://github.com/nightly-labs/openbot/blob/main/src/backend/process-confinement.ts
15. https://github.com/nightly-labs/openbot/blob/main/packages/contracts/src/billing.ts
16. https://github.com/nightly-labs/openbot/blob/main/apps/auth-api/src/components/landing/PricingSection.tsx
17. https://github.com/nightly-labs/openbot/blob/main/package.json
18. https://github.com/nightly-labs/openbot/blob/main/apps/mobile/package.json
19. https://github.com/nightly-labs/openbot/blob/main/apps/mobile/CHANGELOG.md
20. https://github.com/nightly-labs/openbot/blob/main/PRIVACY.md
21. https://github.com/nightly-labs/openbot/blob/main/docs/provider-terms.md
22. https://github.com/nightly-labs/openbot/blob/main/docs/docker.md
23. https://github.com/nightly-labs/openbot/blob/main/docs/self-hosting.md
24. https://github.com/nightly-labs/openbot/blob/main/docs/messaging.md
25. https://github.com/nightly-labs/openbot/blob/main/docs/automation.md
26. https://github.com/nightly-labs/openbot/releases (78 releases; v0.44.3 assets)
27. https://openbot.run/news/introducing-openbot
28. https://openbot.run/news/every-agent-gets-a-workspace
29. https://openbot.run/news (RSS)
30. https://openbot.run/news/what-gets-redacted-before-it-leaves
31. https://openbot.run/guides/openbot-101
32. https://openbot.run/guides/openbot-hosted-servers
33. https://openbot.run/compare/grok-bot (vendor comparison page; used only for OpenBot's own pricing and hosting-region claims)
34. https://play.google.com/store/apps/details?id=run.openbot.mobile
35. https://itunes.apple.com/lookup?bundleId=run.openbot.mobile (no App Store result)
36. https://github.com/CopilotKit/OpenBot and https://www.copilotkit.ai/openbot (disambiguation)
37. https://github.com/Samuraizan/OpenBot (disambiguation; fork of milind-soni/OpenMausBot)
38. https://openbot.one and https://openbot.one/manifest.webmanifest (disambiguation)
39. https://openbot.ai (disambiguation)
40. https://www.getopenbot.com/ (disambiguation)
