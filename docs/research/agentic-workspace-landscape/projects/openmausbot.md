# OpenMausBot (MausBot)

> An Apache-2.0, local-first Electron "messenger of bots": each contact is an agent backed by a CLI you already pay for (Claude Code, Codex, Grok Build, 10+ ACP agents), with its own computer, apps, memory and schedules, plus a paid always-on hosted tier (MausBot Cloud). Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: OpenMausBot (brand "MausBot"; formerly OpenGrokBot)
slug: openmausbot
category: oss-bot-roster-desktop
maker: Milind Soni and Omkar Satpute; trademarks and App Store entity Supamaus Software Private Limited (India)
license: Apache-2.0, except enterprise/ which is source-available (license key for production, no hosting for third parties)
repo: https://github.com/milind-soni/OpenMausBot
website: https://mausbot.com (openmausbot.com 308-redirects here)
first_public: 2026-08-11
latest_release: v0.1.118, 2026-10-19
release_cadence: "~1.6 desktop releases/day (112 tags in 70 days; 32 in the last 30)"
stars: 5231 (as of 2026-10-20)
forks: 874 (as of 2026-10-20; no fork has more than 1 star)
contributors: 139 (as of 2026-10-20, contributors API incl. anonymous)
primary_language: TypeScript
stack: "Electron 43, React 19, Vite 7, Tailwind 4, Node 24 harness server (HTTP + SSE on 127.0.0.1:8799), node:sqlite, zod 4, Cua Driver, Cloudflare Workers + D1, Fly.io for hosted homes"
platforms: [macos, windows, linux, ios, android, web, cli]
agent_engine: wraps CLIs (stream-JSON, Codex app-server JSON-RPC, ACP, pi RPC, Meta MSP) + raw OpenAI-compatible API drivers; no own agent loop for CLI engines
engines_supported: [claude-code, codex, grok-build, gemini-cli, kimi-cli, factory-droid, cursor-cli, opencode, qwen-code, hermes-agent, cline, pi, antigravity, muse-code, custom-acp, raw-api]
model_access: subscription logins (Claude, ChatGPT, SuperGrok, Google, Meta) | API keys (xAI, OpenAI-compat, OpenRouter, Groq, Mistral, Cerebras, MiniMax, Meta) | local models via OpenAI-compatible endpoints | vendor credits (Cloud trial $5, Pro $10/mo, Max $20/mo Claude credit)
execution_env: agent CLIs on the user host (or the hosted Cloud home); GUI/computer tools on user-chosen backend: host via Cua, Local VM container (Docker/Podman), Boat cloud VM, BYO VPS container over SSH
per_bot_computer: yes (one Boat sandbox or Local VM container per bot; host sharing optional)
persistent_bots: yes (durable bot identity with avatar/mascot, instructions, model, skills, memory, approval level)
memory: per-bot markdown (MEMORY.md 200 lines/24 KB in prompt, topic files, daily logs), keyword recall before each turn, background capture, journal with undo; team memory 6,000 B
routines: yes (once/weekday/interval/cron schedules, webhooks on 127.0.0.1:8800, Composio app events via broker long-poll; calendar view)
group_chat: yes (rooms/groups with per-member engines, Chief of Staff delegation, decision-model auto-routing, single job-runtime record for handoffs)
coding_workspace: partial (per-bot/room working folders, engine-native edits with approval cards, rewind/branches; no built-in diff/terminal/worktree UI found)
browser_use: yes (per-bot isolated browser engine via CDP/agent-browser, egress gate; "My Chrome"; cloud desktop browser)
computer_use: yes (Cua Driver on macOS and Ubuntu Xorg opt-in; Wayland disabled; cloud/VM desktops with live view and takeover)
connectors: Composio sessions (500+ apps, managed broker or own key) + custom MCP servers (stdio/HTTP) + native HighLevel CRM + 1Password + X research (treg)
channels: in-app chat + phone companions; Slack only on hosted org workspaces; Slack/Telegram/iMessage "coming soon"
mobile: yes (native iOS app on App Store and Android APK as thin clients paired to the host; installable PWA); native source removed from public repo 2026-10-06
voice: yes (TTS via ElevenLabs, Fish Audio, xAI, macOS voices, local Chatterbox; live calls on user's OpenAI key; macOS on-device dictation)
approvals: per-bot level mapped to each engine's native permission mode (Ask / Auto-accept edits / Approve for me / Full access / Codex custom); default Full access; never-list safety floor
e2e_encryption: partial (HPKE for phone credential entry; password-encrypted backups; hosted phone path via Cloudflare Tunnel, not E2E)
self_host: yes (desktop, `npx openmausbot serve` with tunnel/Tailscale/own proxy, Docker/Podman, multi-workspace fleet on one Linux host)
multi_user: partial (email sign-in, invites and paired devices on self-hosted servers; org library, budgets, SSO/white-label in enterprise/)
pricing: "Free app; MausBot Cloud $15/$49/$99 per month; Team $169/mo, Business $599/mo, Business self-hosted $299/mo (yearly); white-label +$99/mo; BYO model usage"
maturity: beta (v0.1.x, Ubuntu beta, Windows installer unsigned; 256 open issues; "Early but real" per README)
```

## What it is

OpenMausBot is a desktop chat app whose sidebar is a roster of bots; "every bot in the sidebar is a real agent — Claude or Codex running locally under the hood — with its own personality, its own model, its own cloud computer, and its own connected apps" ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)). It was started on 2026-08-11, the day xAI launched Grok Bot, as an explicit open clone ("independent project inspired by Grok Bot", formerly **OpenGrokBot**) ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md); [repo API created_at 2026-08-11](https://api.github.com/repos/milind-soni/OpenMausBot); scaffold commit [43a40803](https://github.com/milind-soni/OpenMausBot/commit/43a40803) "Scaffold ... for OpenGrokBot", renamed in [20f7ef03](https://github.com/milind-soni/OpenMausBot/commit/20f7ef03) on 2026-08-12). It now positions itself as the open alternative to Grok Bot, Meta Muse, OpenAI dots, Manus Cue and Instinct ([README comparison table](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)).

Mental model: a messenger (contacts, pin, unread, channels/groups) on top of a local agent control plane. Target user: individuals and small businesses who already pay for Claude/ChatGPT/Grok subscriptions and want a "team" of agents doing recurring business work (sales follow-up, bookkeeping, recruiting, support triage) ([mausbot.com](https://mausbot.com/)). The claimed problem: "One assistant in one box is the wrong shape for agents" and closed products keep "the model, the computer and your data on its maker's side of the line" ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)).

Naming and business (resolved):

| Name | What it is | Evidence |
|---|---|---|
| OpenMausBot | Repo, npm package, installer filenames, data dir `~/.openmausbot` | [repo](https://github.com/milind-soni/OpenMausBot), [npm](https://registry.npmjs.org/openmausbot) |
| MausBot | Consumer brand of the same product since ~2026-10-06; openmausbot.com 308-redirects to mausbot.com; iOS app name | [Meet MausBot blog, 2026-10-06](https://mausbot.com/blog/meet-mausbot); `curl -I https://www.openmausbot.com` → `location: https://mausbot.com/` (checked 2026-10-20); [README "Also known as MausBot"](https://github.com/milind-soni/OpenMausBot/blob/main/README.md) |
| MausBot Cloud ("OMB Cloud") | The paid layer: one always-on Fly.io app per customer running the same server image | [docs/cloud-pro.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/cloud-pro.md), [mausbot.com/pro](https://mausbot.com/pro) |
| SupaMaus | The company (Supamaus Software Private Limited, owner of the OpenMausBot/MausBot trademarks and App Store developer) and also a separate product: "SupaMaus for Browser", an embeddable AI-cursor onboarding widget priced per seat. Not the same product as MausBot; the app reuses "SupaMaus cursor mascots" | [LICENSING.md](https://github.com/milind-soni/OpenMausBot/blob/main/LICENSING.md), [supamaus.com](https://www.supamaus.com/), [App Store listing](https://apps.apple.com/in/app/mausbot/id6803387923), [supamaus-releases repo](https://github.com/milind-soni/supamaus-releases) |

Makers: the blog says "MausBot is made by Omkar Satpute and Milind Soni" ([blog](https://mausbot.com/blog/meet-mausbot)). Milind Soni (GitHub `milind-soni`, X `@milindlabs`) holds the copyright and authored 3,026 commits; Omkar Satpute (GitHub `aivsomkar`, company "SupaMaus", X `@BuildwithOmkarr`) authored 498 and handles the iOS app and marketing ([contributors API](https://api.github.com/repos/milind-soni/OpenMausBot/contributors), [enterprise/LICENSE](https://github.com/milind-soni/OpenMausBot/blob/main/enterprise/LICENSE), [mausbot.com/pro support emails @supamaus.com](https://mausbot.com/pro)). Milind also ships [tiptour-macos](https://github.com/milind-soni/tiptour-macos) (681 stars, local computer use) and [axstream](https://github.com/milind-soni/axstream).

## Product and UX

- Onboarding: download desktop app, an "engine check" that installs/signs in one CLI (Claude Code, Codex, ...), create a bot (name, engine, model, optional working folder), send a small task ([mausbot.com/download](https://mausbot.com/download)). The first-run tour also imports skills and MCP servers from Claude Code, Codex, Cursor, Claude Desktop and Gemini, and can import a Grok Bot by link ([docs/team-sharing.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/team-sharing.md)).
- Sidebar of bots like chats (pin, unread, duplicate, hide); channels/groups with their own transcript, shared instructions, working folder and responder rules; teams with a **Chief of Staff** bot that can create specialists ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md), [chat-and-teams.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/features/chat-and-teams.mdx)).
- Model picker with a provider rail; switch a bot's model mid-conversation ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)).
- Computer panel: live screen preview of the bot's desktop, "Open desktop" takeover, or point the bot at "this Mac"; "Sign in needed" cards hand control to the person and back ([computers/index.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/computers/index.mdx)).
- Approval and question cards inline in chat (Allow / Deny / answer) ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)).
- Automations page with routines on a calendar (a deliberate UX choice: "I hate the routines UI that every harness app has right now", Milind on X, quoted on [mausbot.com](https://mausbot.com/)); a bot creates triggers from a sentence and the chat shows a live card with Edit, Pause and Undo ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)).
- Teams as one Markdown file with YAML frontmatter, installable from [BotMRR](https://botmrr.io) or GitHub; imports land with connections off, routines paused and skills disabled ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md), [openmausbot-teams FORMAT](https://github.com/milind-soni/openmausbot-teams)).
- Distinctive: animated cursor mascots per bot with role-aware expressions; "Advanced mode" toggle hides detail by default ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md); Omkar on X, quoted on [mausbot.com](https://mausbot.com/)); 10 UI languages ([mausbot.com](https://mausbot.com/)).

## Architecture

Components derived from source (paths in [milind-soni/OpenMausBot@main](https://github.com/milind-soni/OpenMausBot)):

```text
                 Electron shell (electron/main.mjs)  ── owns cua-driver lifecycle, safeStorage secrets,
                 macOS / Windows / Ubuntu            companion sidecar, WebContentsView browser pool
                        │ HTTP commands, one SSE stream
 React app (src/, :5199) ┘
                        ▼
 Harness server  127.0.0.1:8799  (server/index.ts, server/harness/*)
 ├─ ProviderRegistry (harness/registry.ts) → BUILT_IN_DRIVERS (drivers/builtIn.ts)
 │    claude.ts      claude CLI, stream-json both ways, one retained process per thread
 │    codex.ts       codex app-server, JSON-RPC as NDJSON on stdio
 │    acp/core.ts    ACP JSON-RPC 2.0 stdio: grok, gemini, kimi, droid, cursor, opencode,
 │                   qwen, hermes, cline, custom ACP
 │    pi.ts          pi --mode rpc;  muse-code.ts  Meta Muse Session Protocol
 │    antigravity*.ts  Google Antigravity ACP;  openai-compat.ts, grok.ts (xAI API), meta,
 │                   mistral, cerebras, groq, minimax  (transcript-replay API drivers)
 ├─ EventBus (harness/bus.ts) → canonical events → SSE + events/<threadId>.ndjson
 │    drivers/native.ts tees provider-native frames beside the canonical stream
 ├─ Permission broker: permission-proxy.ts (MCP --permission-prompt-tool → unix socket),
 │    auto-approve.ts levels, safety-floor.ts never-list, chat-tool-approval.ts
 ├─ Job runtime (server/runtime/, runtime.db): one Assignment record for every handoff
 ├─ Memory (workspace.ts, memory-*.ts, recall.ts), skills (skills.ts, skill-learn.ts)
 ├─ Routines/triggers (routines.ts, routine-*.ts, webhooks.ts → 127.0.0.1:8800, app-triggers.ts)
 ├─ Computers: boat.ts (Boat API), container-computer.ts (Local VM, Cua XFCE image),
 │    vps-computer.ts (BYO VPS over Docker SSH), local-computer.ts (host via Cua)
 │    cloud-computer-tools.ts (MCP at /api/internal/computer/mcp, turn-scoped capability)
 ├─ Browser (server/browser/*: CDP driver, per-bot sessions, egress gate)
 ├─ Connectors: composio.ts, mcp-*.ts, connector-*.ts, highlevel/*, onepassword.ts
 ├─ Voice: tts/* (ElevenLabs, Fish, xAI, system, Chatterbox), live-call*.ts
 └─ MCP server for external orchestrators (docs/mcp-server.md), headless CLI (server/headless/)
 Companion sidecar (companion/src): 0.0.0.0:8810 paired devices, 127.0.0.1:8811 control,
   127.0.0.1:8812 hosted gateway ← Cloudflare Tunnel
 Cloudflare Workers: cloudflare/composio-broker (D1), cloudflare/control-plane (Better Auth, tunnels)
 Hosted: MausBot Cloud = same server image on one Fly app per customer (Dockerfile, deploy/fly/)
```

- **Two-process core.** "The app holds no transports of its own — it sends typed commands over HTTP and folds one SSE event stream into state. The harness server owns every agent process and normalizes each provider's native protocol into one canonical runtime event stream (logged per-thread as NDJSON)" ([README "How it works"](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)). The bus writes `EVENTS_DIR/<threadId>.ndjson` ([server/harness/bus.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/harness/bus.ts)); `drivers/native.ts` "tees every provider-native message beside the canonical stream, so protocol drift shows up in a diff" ([source](https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/native.ts)).
- **Lineage.** The driver SPI is "ported from upstream's provider contracts with Promises for Effect" and the registry/bus are ports of "ProviderInstanceRegistryLive" and "ProviderService fan-in + EventNdjsonLogger" ([server/contracts.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/contracts.ts), [registry.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/harness/registry.ts)); the NOTICE credits T3 Code (MIT) for Antigravity, browser, egress gate and citation code ([NOTICE](https://github.com/milind-soni/OpenMausBot/blob/main/NOTICE)). [INFERENCE] The harness core is derived from T3 Code's server architecture.
- **Driver SPI.** `ProviderDriver`/`ProviderAdapter` in [server/contracts.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/contracts.ts); unknown drivers "round-trip as an unavailable shadow snapshot" rather than crashing. Request outcomes are `allowed-once | rejected | answered | unavailable`, with `unavailable` the fail-closed default. Adding a provider is "one file in server/drivers/ plus a one-line registration"; any ACP CLI or OpenAI-compatible endpoint plugs in by config ([docs/custom-engines.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/custom-engines.md)).
- **Wire protocols per engine** (header comments): Claude Code "over stream-json both ways: prompt on stdin, one retained CLI process per thread" ([claude.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/claude.ts)); Codex "headless over its app-server JSON-RPC (NDJSON on stdio)... approvals arrive as server→client requests" ([codex.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/codex.ts)); Grok Build "the official grok CLI over ACP stdio ... on the grok.com subscription login (~/.grok/auth.json), not the xAI API key" ([acp/grok.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/acp/grok.ts)); ACP "permissions fail closed: only an allow-kind option approves" ([acp/core.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/acp/core.ts)); pi over `pi --mode rpc` ([pi.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/pi.ts)); Meta Muse Code over its Muse Session Protocol ([muse-code.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/muse-code.ts)). The README's "cloud-computer agent" driver was deleted on 2026-10-06 ("Delete the Computer engine: every turn runs on the bot's own engine", [#2329](https://github.com/milind-soni/OpenMausBot/pull/2329)); [server/routines.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/routines.ts) still documents a `cloud` runner that "runs the agent inside the bot's Boat VM".
- **Auth.** Bots use the CLIs' own logins and subscriptions, "no proxy in the middle" ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)); API keys live in `~/.openmausbot/config.json` and are write-only through the API; desktop uses Electron `safeStorage`; the npm CLI path stores keys "as plaintext, not encrypted, in private config.json (0600)" ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md), [docs/composio.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/composio.md)). Each secret goes only to the driver that reads it; "the Boat token reaches no engine" ([server/config.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/config.ts)).
- **Execution environment.** Agent CLIs run on the host with the user's privileges ([SECURITY.md](https://github.com/milind-soni/OpenMausBot/blob/main/SECURITY.md)). Computer backends are chosen per bot ([computers/index.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/computers/index.mdx)):

| Backend | Isolation | Implementation |
|---|---|---|
| This computer | none | Cua Driver binary bundled and pinned, owned by Electron; macOS supported, Ubuntu Xorg opt-in, Wayland disabled ([computer-use-integration.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/computer-use-integration.md), [README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)) |
| Local VM | container | Docker/Podman with the official Cua XFCE image, `cua-driver mcp` inside ([container-computer.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/container-computer.ts), [local-vm.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/computers/local-vm.mdx)) |
| Boat cloud computer | hosted VM | Boat public API v1 at `https://boat.dev/api/v1`, one sandbox per bot ([boat.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/boat.ts), [included-services.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/included-services.ts)) |
| BYO VPS | container over SSH | Docker SSH transport, one Cua MCP container per bot ([vps-computer.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/vps-computer.ts), [byo-vps.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/byo-vps.md)) |

- **The "Box API" is Boat.** Source: "Boat token (ascii.dev renamed Box to Boat); config key "box", env BOX_TOKEN" ([server/config.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/config.ts)); a legacy relay still speaks "Boat's retired box dialect (/boxes under a base ending in /api/box/v1)" ([boat-relay.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/boat-relay.ts)). Boat is run by ASCII (Y Combinator-backed): persistent Ubuntu VMs with SSH, Docker, 60 fps desktop, disk-level fork; billed per second with a $20/month account minimum ($20 = 2,000,000 VM-seconds of 4 vCPU/8 GB; small 0.5x, large 2x); 7-day trial with 25 compute hours; EU regions only (Germany, Finland, France) ([boat.dev, fetched 2026-10-20](https://boat.dev/)). Isolation is described as full VMs (vendor claim); hypervisor technology unknown. OMB-side detail: sandbox names carry a hash of the local environment id so other installs on the same account never claim them; default TTL 8 h (trial 2 h); "disk persists, tmux does not"; owner console commands run under `env -i` without provider credentials ([boat.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/boat.ts)). Boat is the project's sponsor ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)).
- **State and storage.** `DATA_DIR = OMB_DATA_DIR ?? ~/.openmausbot` (legacy `~/.opengrokbot` migrated) ([config.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/config.ts)): `config.json`, `messages.db` (SQLite transcripts), `runtime.db` (assignments, append-only `assignment_events`, inbox), `events/*.ndjson`, `workspaces/<botId>/` memory, `memory-journal/<botId>.ndjson` ([docs/runtime-contract.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/runtime-contract.md), [docs/memory.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/memory.md), [docs/sentinel.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/sentinel.md)). No cloud sync for local use; desktop-to-Cloud "Copy this computer here" uploads an encrypted workspace backup, and `.ombbackup` exports are password-encrypted ([data-and-backups.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/self-hosting/data-and-backups.mdx)).
- **Remote and mobile access.** A companion sidecar exposes a default-deny allowlist on `0.0.0.0:8810` to paired devices; hosted HTTPS uses one Cloudflare Tunnel per installation routed to an Electron-owned gateway on `127.0.0.1:8812`; LAN (Bonjour) and Tailscale need no account ([docs/ios-companion.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/ios-companion.md), [cloudflare/control-plane/README.md](https://github.com/milind-soni/OpenMausBot/blob/main/cloudflare/control-plane/README.md)). Pairing: two-minute QR window plus six-digit fallback, per-device token in iOS Keychain, server stores only a digest ([ios-companion.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/mobile/ios-companion.mdx)). Credential-request cards from the phone use QR-pinned HPKE ([docs/ios-companion.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/ios-companion.md), [NOTICE](https://github.com/milind-soni/OpenMausBot/blob/main/NOTICE)). Desktop-to-desktop pairing over HTTPS or Tailscale ([docs/desktop-companion.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/desktop-companion.md)).
- **Extension surface.** Custom engines (ACP/OpenAI-compatible, config only), custom MCP servers ([docs/custom-mcp-servers.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/custom-mcp-servers.md)), per-bot Agent Skills (imports land disabled; a skill recorder turns observed commands into a skill) ([server/skills.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/skills.ts); Milind on X quoted on [mausbot.com](https://mausbot.com/)), an outbound stdio MCP server for Claude Desktop/Cursor/Hermes to orchestrate bots ([docs/mcp-server.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/mcp-server.md)), a headless `openmausbot team apply` / `run` CLI for CI ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)), and a large-catalog "agents tool bridge" (`find_tool`/`use_tool`) ([agents-bridge.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/agents-bridge.ts)).

## Capabilities in detail

- **Persistent bots and identity.** "A bot is a durable agent identity. A thread is one conversation with that bot and has its own transcript, provider session, approvals, costs, and running state" ([chat-and-teams.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/features/chat-and-teams.mdx)). Busy threads queue messages and supported providers can be steered mid-turn (same source).
- **Memory.** Per bot: `MEMORY.md` (first 200 lines or 24 KB loaded into the system prompt every turn), `memory/<topic>.md` read on demand with a topic index, `archive.md`, daily logs. Before each turn, keyword recall injects up to 4 notes and 4 passages from the bot's other 1:1 conversations (max 6,000 chars), fenced so "a command inside one is not an instruction". Background "memory upkeep" runs a quick model call after 2 min of quiet or 6 turns to file new facts, with optional helper model for engines lacking a cheap text call. Writes are atomic, `0600`, credential-redacted, and journaled outside the workspace with one-click undo ([docs/memory.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/memory.md)). Team memory has a 6,000-byte prompt budget, revisioned writes (409/428 on stale) and pinned rules (same source).
- **Routines/automation.** Schedules (once, weekdays, every 5-1,440 min, five-field cron with IANA zone via Croner), webhooks on a dedicated `127.0.0.1:8800` receiver with bearer or capability URL, and Composio "app events"; interval runs skip when the previous run is still active ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md), [docs/routine-schedules.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/routine-schedules.md)). The docs disagree on confirmation: the README says bots create triggers "no confirmation" with an Undo card, while routine-schedules.md says "Nothing is scheduled until you confirm" for cron rules.
- **Multi-bot collaboration.** Groups where each participant keeps its own provider state and timeouts; Chief of Staff delegation (`coordinate_bots`, `create_bot`) ([chat-and-teams.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/features/chat-and-teams.mdx)). All handoffs (chat, room, routine, webhook, goal run, external) share one SQLite `Assignment` record with a lifecycle (`queued → running → waiting/needs_input → completed|failed|cancelled`), depth/budget checks and dedupe; this "replaces the two delegation systems, the six wake lanes, the dozen clocks" the server had grown ([docs/runtime-contract.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/runtime-contract.md)). Rooms set to Auto route un-mentioned messages with a decision model (TypeSafe Jev or OpenRouter) in "a few hundred milliseconds" with 0.6 confidence threshold ([docs/decision-model.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/decision-model.md)). A user reports a five-engine debate room (Codex, Grok Build, Antigravity, OpenCode, Claude Code) (third-party, X post quoted on [mausbot.com](https://mausbot.com/)).
- **Coding workspace.** Per-bot or shared room working folders; edits happen through the engines' own tools with approval cards; rewind/branching on edited messages ([chat-and-teams.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/features/chat-and-teams.mdx)). No dedicated diff viewer, terminal pane or worktree manager was found in the docs index (unknown).
- **Browser and computer use.** Built-in browser per bot over CDP (Electron `WebContentsView` on desktop, an isolated persistent browser engine on servers, with an egress gate that blocks the server's own network unless allow-listed) ([computer-use-integration.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/computer-use-integration.md), [docs/self-hosting.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/self-hosting.md)). Saved logins and 1Password are typed by the app via `fill_login`; "the bot never sees the password" ([computers/index.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/computers/index.mdx)). A person can take control; while held, bot actions are refused, not queued ([computer-control.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/computer-control.ts)). USB Android control via a Phone Harness skill ([android-control.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/mobile/android-control.mdx)).
- **Connectors.** One Composio project key → one reusable Composio Session with multi-account mode and per-bot tool grants; packaged builds instead register with a managed Cloudflare Worker broker that keeps the shared Composio key out of desktop builds and stores per-installation tokens as SHA-256 in D1 ([docs/composio.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/composio.md), [composio-broker/README.md](https://github.com/milind-soni/OpenMausBot/blob/main/cloudflare/composio-broker/README.md)). App events: Composio posts signed webhooks to the broker, which queues per installation in D1; the desktop long-polls `GET /v1/events` (25 s) so it "needs no public URL"; Gmail is polled every 15 min; 500 events/day on desktop, 2,000 on paid Cloud (same sources, [README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)). Native HighLevel CRM integration ([docs/highlevel.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/highlevel.md)).
- **Channels.** Only the app and its companions today. Slack exists for hosted organization workspaces through an Admin service ([hosted-slack-management.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/verification/hosted-slack-management.md)); "Slack, Telegram and iMessage" are "Coming soon" on Pro and Max ([mausbot.com/pricing](https://mausbot.com/pricing)). No Telegram/WhatsApp/iMessage/SMS code found in the tree (searched file names 2026-10-20).
- **Voice.** TTS from ElevenLabs, Fish Audio, xAI, macOS voices or local Chatterbox, with markdown rewritten into a "spoken register"; keys stay on the harness ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md), [docs/voice-mode.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/voice-mode.md)). Live calls use the user's own OpenAI key ([mausbot.com/pro](https://mausbot.com/pro)); desktop calls are macOS-only, on Apple on-device dictation ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)).
- **Mobile.** iOS app "MausBot" (App Store id6803387923, developer Supamaus Software Private Limited; also TestFlight) and an Android APK (tags `android-v1.0.0` 2026-09-01 to `android-v1.5.0` 2026-09-27) are thin clients: bot/room lists, paged transcripts, send/interrupt, approvals with narrow always-allow, live Boat view, widgets, live calls ([App Store](https://apps.apple.com/in/app/mausbot/id6803387923), [docs/ios-companion.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/ios-companion.md), [releases](https://github.com/milind-soni/OpenMausBot/releases)). Closed-app push is not in the first version; the host must stay awake (same docs). The `ios/` and `android/` source trees were removed from the public repo on 2026-10-06 ([#2382 "Cleanup"](https://github.com/milind-soni/OpenMausBot/pull/2382)); the download page distributes both "in our Discord" ([mausbot.com/download](https://mausbot.com/download)). A PWA install is documented ([docs/phone-web-app.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/phone-web-app.md)).
- **Team features.** Shareable team files, org library, multi-user self-hosted servers with email sign-in and invites, per-workspace fleet on one Linux host ([docs/self-hosting.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/self-hosting.md), [server/fleet.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/fleet.ts)); enterprise entitlements `whitelabel`, `sso` (planned), `admin`, `budgets`, `billing` ([enterprise/FEATURES](https://github.com/milind-soni/OpenMausBot/blob/main/enterprise/FEATURES)). Opt-in health scanner "Sentinel" reads the data dir and groups failures, no model calls ([docs/sentinel.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/sentinel.md)).

## Security and trust model

- **Approvals.** Levels are each provider's own permission mode passed through: Ask, Auto-accept edits, Approve for me (provider auto-review), Full access, Codex Custom. "Every bot and conversation starts at **Full access**, the default T3 Code uses too", except hosted company workspaces which default to Ask; Full access applies with "no confirmation dialog" and also skips the "Send on your behalf?" card for connected-app sends ([docs/approval-levels.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/approval-levels.md)). A Chief of Staff's level flows down to delegated work ([auto-approve.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/auto-approve.ts)). The website FAQ concedes "approval coverage depends on the engine and tool, so it is not a guarantee that every action will pause" ([mausbot.com](https://mausbot.com/)).
- **Broker and floor.** Claude asks route through an MCP `--permission-prompt-tool` proxy to the broker over a unix socket ([permission-proxy.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/permission-proxy.ts)); a shell-command never-list is never self-approved at any level ([safety-floor.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/safety-floor.ts)). New/imported bots get connected apps off or no grants ([permissions-and-secrets.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/security/permissions-and-secrets.mdx)).
- **Network exposure.** Harness binds 127.0.0.1 only; loopback is trusted as owner on self-hosted servers ("any process that can reach 127.0.0.1:8799 has full control, including the shell your bots can use"); browsers never get loopback trust ([docs/self-hosting.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/self-hosting.md), [request-auth.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/request-auth.ts)). Known open issue: on hosted/shared workspaces a bot's shell can reach the Slack worker's guarded routes and "get Full-access work done without a card"; fix planned ([SECURITY.md](https://github.com/milind-soni/OpenMausBot/blob/main/SECURITY.md)).
- **Secrets.** Write-only API; Electron `safeStorage` on desktop; plaintext `config.json` (0600) on the npm path; memory writes and native logs redact credentials ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md), [redact.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/redact.ts)).
- **Supply chain.** Cua Driver for Linux is tag-pinned with size, SHA-256 and member allowlist checks; no runtime self-update of native automation code ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md), [third_party/cua-driver](https://github.com/milind-soni/OpenMausBot/tree/main/third_party/cua-driver)). macOS builds are signed and notarized; the Windows installer is not code-signed ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)).
- **Telemetry.** PostHog (US) product analytics, on unless the user opts out (`analyticsEnabled()` returns true unless the opt-out key is `"1"`, [src/lib/analytics.ts](https://github.com/milind-soni/OpenMausBot/blob/main/src/lib/analytics.ts)); events are tied to email if shared on the first-run screen ([docs/analytics.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/analytics.md)).
- **Incidents.** No published GitHub security advisories (API, 2026-10-20). README warns that unrelated "Maus"/"SupaMaus" crypto tokens are not affiliated ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)).

## Traction and momentum

All figures as of 2026-10-20 unless stated.

| Metric | Value | Source |
|---|---|---|
| Stars / forks | 5,231 / 874 | [repo API](https://api.github.com/repos/milind-soni/OpenMausBot) |
| Contributors | 139 (top: milind-soni 3,026, aivsomkar 498, robinsonnblack 345, bradhallett 314 commits) | [contributors API](https://api.github.com/repos/milind-soni/OpenMausBot/contributors) |
| Commits on main | 5,631 total; 3,509 since 2026-09-20 (~117/day) | commits API pagination |
| AI co-authored commits | 1,830 commits contain "Co-authored-by: Claude" | GitHub commit search |
| PRs / issues | 2,571 PRs (1,988 merged); 584 issues (256 open) | GitHub issue search |
| Desktop releases | 112 tags v0.1.0 (2026-08-11) → v0.1.118 (2026-10-19): 43 in Aug, 44 in Sep, 25 in Oct 1-19 | [openmausbot-releases](https://github.com/milind-soni/openmausbot-releases/releases) |
| Release-asset downloads | 45,379 (main repo) + 29,953 (releases repo) installer/zip/apk downloads; includes auto-update zips, not unique users | releases API |
| Android APK downloads | ~4,600 across six tags | [releases](https://github.com/milind-soni/OpenMausBot/releases) |
| npm `openmausbot` | 7,334 downloads 2026-09-19..10-18; first published 2026-09-05; 61 versions | [npm API](https://api.npmjs.org/downloads/point/last-month/openmausbot) |
| Discord | 2.9k members (vendor claim) | [mausbot.com](https://mausbot.com/) |
| iOS app | 3 ratings, 3.7 (India store snippet) | [App Store](https://apps.apple.com/in/app/mausbot/id6803387923) |

- Forks/derivatives: no GitHub fork has more than 1 star (e.g. [Samuraizan/OpenBot](https://github.com/Samuraizan/OpenBot), 0 stars, forked 2026-08-18). Non-fork derivatives: [oliexe/paseo-bots](https://github.com/oliexe/paseo-bots) (42 stars, "A Grok Bot / OpenMausBot"-style pixel coworkers for Paseo), [harmanhanjra/OpenMausBotV2](https://github.com/harmanhanjra/OpenMausBotV2) (5, adds NVIDIA NIM), [Simple-With-Us/BotFleet](https://github.com/Simple-With-Us/BotFleet) (4, Mac/iOS bot workspace), Chinese localizations [iiiiiei/OpenMausBot-zh](https://github.com/iiiiiei/OpenMausBot-zh) and [lokih1028/OpenMausBot-Desktop](https://github.com/lokih1028/OpenMausBot-Desktop) (1 each) ([GitHub repo search](https://github.com/search?q=openmausbot&type=repositories)). Ecosystem: [openmausbot-teams](https://github.com/milind-soni/openmausbot-teams) (31 stars), [BotMRR](https://botmrr.io) team marketplace.
- Launch press: viral X posts on launch day ("within 4 hours an OSS clone exists") and a Product Hunt listing (third-party, quoted on [mausbot.com](https://mausbot.com/)).
- **Business model.** Free app (Apache-2.0) + GitHub Sponsors; **MausBot Cloud** per-person plans: Starter $15/mo (2 shared vCPU/2 GB, sleeps when idle, 1 cloud computer, 10 computer-hours), Pro $49/mo (4 vCPU/4 GB always on, 4 computers, 200 h, $10/mo Claude credit, 5,000 research lookups), Max $99/mo (8 vCPU/8 GB, 8 computers, 500 h, $20/mo credit); 3-day trial with $5 Claude credit; model usage BYO ([mausbot.com/pro](https://mausbot.com/pro), [mausbot.com/pricing](https://mausbot.com/pricing)). Team plans: Team $169/mo ($135 billed yearly), Business $599/mo ($479 yearly), Business self-hosted $299/mo billed yearly, white-label +$99/mo ([mausbot.com/pricing](https://mausbot.com/pricing)). Each Cloud customer gets one Fly.io app with an always-on `home` machine, `/data` volume and `https://<app>.fly.dev`; "OMB Cloud includes no AI usage" beyond the metered trial credit ([docs/cloud-pro.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/cloud-pro.md)). Enterprise license keys for `enterprise/` ([LICENSING.md](https://github.com/milind-soni/OpenMausBot/blob/main/LICENSING.md)).

## Strengths

- Broadest engine coverage in the category: 22 built-in drivers spanning subscription CLIs, ACP agents and raw APIs, behind one small SPI ([drivers/builtIn.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/builtIn.ts)).
- Reuses users' existing subscriptions with no proxy; zero marginal model cost for the maker on the free tier ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)).
- Pluggable computer backends with a clean per-bot choice, including a fully local container option and BYO VPS ([computers/index.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/computers/index.mdx)).
- Unusually thorough design docs and invariants written as code comments (runtime contract, memory budget, approval mapping, security scope).
- Strong distribution: three desktop OSes, npm/headless server, iOS + Android, MCP server for outside orchestrators, team marketplace.
- Extreme shipping velocity (~1.6 releases/day) and active community (139 contributors).

## Weaknesses and risks

- **Unsafe default.** New bots start at Full access, which also skips send confirmations for email/payments ([docs/approval-levels.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/approval-levels.md)); agents run on the host with user privileges.
- **Velocity vs stability.** v0.1.x, ~117 commits/day with a large AI-co-authored share, a ~4,300-file tree, and README drift (e.g. the cloud-computer agent removed in [#2329](https://github.com/milind-soni/OpenMausBot/pull/2329) is still listed; routine-confirmation docs disagree) [INFERENCE: high regression and maintainability risk; bus factor of one maintainer].
- **Third-party dependencies.** Cloud computers depend on Boat (EU-only, the project's sponsor) and connectors on Composio and a maker-run Cloudflare broker; app events do not work with a self-supplied Composio key ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)).
- **Laptop-bound unless paid.** Local bots stop when the host sleeps; phone push needs the app open ([docs/ios-companion.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/ios-companion.md)).
- **Subscription terms.** [INFERENCE] Running consumer Claude/ChatGPT subscriptions 24/7 on hosted Cloud homes may conflict with provider usage terms or rate limits; the vendor itself recommends Claude Max or API keys for heavy 24/7 use ([mausbot.com/pro](https://mausbot.com/pro)).
- **Openness narrowing.** Native mobile source left the public repo ([#2382](https://github.com/milind-soni/OpenMausBot/pull/2382)); `enterprise/` is source-available; names and mascot are trademarks ([LICENSING.md](https://github.com/milind-soni/OpenMausBot/blob/main/LICENSING.md)).
- **Channel gap.** No Telegram/WhatsApp/iMessage/email-in channels yet ([mausbot.com/pricing](https://mausbot.com/pricing)).
- Unsigned Windows installer; Ubuntu still beta; opt-out telemetry.

## Ideas worth taking for Memoshi

- **Canonical event stream + native tee.** Normalize every engine into one event schema logged per thread as NDJSON, and keep raw provider frames beside it so protocol drift shows up as a diff ([native.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/native.ts)).
- **ACP as the default plug.** One shared ACP driver with per-CLI quirk objects covers about ten agents; custom engines become config, not code ([acp/core.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/acp/core.ts)).
- **One job record from day one.** Model every handoff (chat, room, routine, webhook, bot-to-bot) as a single SQLite assignment with an append-only event log; OMB had to retrofit this after six wake lanes ([runtime-contract.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/runtime-contract.md)).
- **Approvals as passthrough plus floor.** Map product levels onto each engine's native permission modes, add a never-list floor, but default to Ask, not Full access.
- **Inspectable memory.** Plain markdown with a visible load budget gauge, credential redaction before disk, and a journal stored outside the bot's writable workspace with undo ([docs/memory.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/memory.md)).
- **Routines on a calendar,** created by the bot from a sentence with an in-chat Edit/Pause/Undo card, and skip-if-still-running semantics.
- **Webhook relay without public IPs.** A small edge worker queues third-party events per installation; the desktop long-polls ([composio-broker](https://github.com/milind-soni/OpenMausBot/blob/main/cloudflare/composio-broker/README.md)).
- **Separate trust surfaces.** Loopback-only core API, a default-deny sidecar for phones, a separate control port with per-launch tokens; secrets reach only the process that needs them.
- **Portable team files.** Markdown + YAML frontmatter that imports with connections off, routines paused, skills disabled; plus importers from competitors (Grok Bot export prompt) to lower switching cost ([team-sharing.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/team-sharing.md)).
- **Hosted tier = same binary.** Per-customer always-on machine (Fly app) running the identical server, BYO model auth; "Copy this computer here" migration ([docs/cloud-pro.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/cloud-pro.md)).
- **Avoid:** prompt-level secrets (use app-typed logins like `fill_login`), consumer-subscription dependence for always-on hosting, and doc drift from AI-velocity development.

## Open questions

- Boat's isolation technology (hypervisor, multi-tenant boundaries) and data-processing terms; check [docs.boat.dev](https://docs.boat.dev/llms.txt) security pages or ask ASCII.
- MausBot Cloud paid user count and revenue: not published; ask the makers or watch Stripe/Whop signals.
- Where the iOS/Android source now lives and under what license after [#2382](https://github.com/milind-soni/OpenMausBot/pull/2382); ask in Discord or check for a new repo.
- Whether the `cloud` routine runner still runs an agent inside the Boat VM after [#2329](https://github.com/milind-soni/OpenMausBot/pull/2329); read `server/routine-execution.ts`.
- Provider-terms compliance of subscription logins on hosted Cloud homes; check Anthropic/OpenAI consumer terms.
- Ship dates for Slack/Telegram/iMessage channels and closed-app push; watch the [changelog](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/changelog/index.mdx).

## Sources

1. https://github.com/milind-soni/OpenMausBot (README, repo API, contributors, commits, releases)
2. https://github.com/milind-soni/openmausbot-releases/releases
3. https://github.com/milind-soni/OpenMausBot/blob/main/LICENSING.md and https://github.com/milind-soni/OpenMausBot/blob/main/enterprise/LICENSE
4. https://github.com/milind-soni/OpenMausBot/blob/main/enterprise/FEATURES
5. https://github.com/milind-soni/OpenMausBot/blob/main/NOTICE
6. https://github.com/milind-soni/OpenMausBot/blob/main/SECURITY.md
7. https://github.com/milind-soni/OpenMausBot/blob/main/server/contracts.ts
8. https://github.com/milind-soni/OpenMausBot/blob/main/server/harness/registry.ts and https://github.com/milind-soni/OpenMausBot/blob/main/server/harness/bus.ts
9. https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/builtIn.ts, claude.ts, codex.ts, acp/core.ts, acp/grok.ts, pi.ts, muse-code.ts, native.ts
10. https://github.com/milind-soni/OpenMausBot/blob/main/server/config.ts, boat.ts, boat-relay.ts, included-services.ts
11. https://github.com/milind-soni/OpenMausBot/blob/main/server/permission-proxy.ts, auto-approve.ts, safety-floor.ts, request-auth.ts, computer-control.ts
12. https://github.com/milind-soni/OpenMausBot/blob/main/docs/runtime-contract.md
13. https://github.com/milind-soni/OpenMausBot/blob/main/docs/memory.md
14. https://github.com/milind-soni/OpenMausBot/blob/main/docs/approval-levels.md
15. https://github.com/milind-soni/OpenMausBot/blob/main/docs/routine-schedules.md
16. https://github.com/milind-soni/OpenMausBot/blob/main/docs/composio.md
17. https://github.com/milind-soni/OpenMausBot/blob/main/cloudflare/composio-broker/README.md
18. https://github.com/milind-soni/OpenMausBot/blob/main/cloudflare/control-plane/README.md
19. https://github.com/milind-soni/OpenMausBot/blob/main/docs/ios-companion.md
20. https://github.com/milind-soni/OpenMausBot/blob/main/docs/cloud-pro.md
21. https://github.com/milind-soni/OpenMausBot/blob/main/docs/self-hosting.md
22. https://github.com/milind-soni/OpenMausBot/blob/main/docs/computer-use-integration.md
23. https://github.com/milind-soni/OpenMausBot/blob/main/docs/voice-mode.md
24. https://github.com/milind-soni/OpenMausBot/blob/main/docs/decision-model.md
25. https://github.com/milind-soni/OpenMausBot/blob/main/docs/team-sharing.md
26. https://github.com/milind-soni/OpenMausBot/blob/main/docs/mcp-server.md
27. https://github.com/milind-soni/OpenMausBot/blob/main/docs/analytics.md and src/lib/analytics.ts
28. https://github.com/milind-soni/OpenMausBot/blob/main/docs/sentinel.md
29. https://github.com/milind-soni/OpenMausBot/tree/main/apps/docs/content/docs (computers, features, mobile, security, self-hosting pages)
30. https://github.com/milind-soni/OpenMausBot/pull/2329 and https://github.com/milind-soni/OpenMausBot/pull/2382
31. https://mausbot.com/ , https://mausbot.com/pro , https://mausbot.com/pricing , https://mausbot.com/download , https://mausbot.com/blog/meet-mausbot
32. https://www.supamaus.com/
33. https://boat.dev/ (vendor page, fetched 2026-10-20)
34. https://apps.apple.com/in/app/mausbot/id6803387923 (App Store listing)
35. https://registry.npmjs.org/openmausbot and https://api.npmjs.org/downloads/point/last-month/openmausbot
36. https://github.com/milind-soni/openmausbot-teams
37. GitHub repository search for "openmausbot" (derivatives), fetched 2026-10-20
