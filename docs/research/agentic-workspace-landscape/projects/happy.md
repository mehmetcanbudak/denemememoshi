# Happy (slopus)

> MIT-licensed family of tools from Steve Korshakov and Kirill Dubovitskiy: an end-to-end encrypted phone/web remote control for coding agents running on your own machine (the original `happy` CLI, a relay server and an Expo app), now joined by an Electron desktop app and a separate multi-model agent runtime ("Happy Agent") that adds persistent bots, a built-in "Chief of Staff", scheduled messages, Telegram export and team servers. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Happy (Happy Coder / Happy Harness)
slug: happy
category: coding-harness   # mobile remote control + relay; Happy Agent adds a bot roster (overlaps oss-bot-roster-desktop)
maker: slopus org (Happy Engineering); Steve Korshakov (ex3ndr) and Kirill Dubovitskiy (bra1nDump); App Store seller "Bulka, LLC"
license: MIT   # happy, happy-desktop, happy-agent all MIT; docs site repo has no license
repo: https://github.com/slopus/happy   # plus slopus/happy-desktop and slopus/happy-agent
website: https://happy.engineering/
first_public: 2025-07-18   # repo created (first commit 2025-07-13); iOS app released 2025-07-21
latest_release: "CLI 1.2.5 (2026-09-22, 1.2.6-beta.1 2026-10-09); iOS 1.8.0 (2026-10-07); desktop v0.0.98 (2026-10-17); Happy Agent v0.4.101 (2026-10-19)"
release_cadence: "CLI ~2-4 tags/month; desktop 46 releases and Happy Agent 86 releases in the 30 days to 2026-10-20 (mostly previews)"
stars: 24231 (as of 2026-10-20; happy-desktop 94, happy-agent 32)
forks: 2071 (as of 2026-10-20)
contributors: 84 (as of 2026-10-20, incl. anonymous; happy-agent 9, happy-desktop 5)
primary_language: TypeScript
stack: "Expo 55 / React Native 0.83 app (iOS, Android, web) with native Swift and Kotlin ports in progress; Node CLI (Claude Agent SDK, Codex app-server, ACP); Fastify + Socket.IO relay on Postgres (Prisma), Redis, S3 or PGlite+filesystem self-host; Electron 43 + React 19 desktop; Happy Agent daemon on Pi foundations with SQLite"
platforms: [macos, windows, linux, ios, android, web, cli]
agent_engine: "wraps CLIs (original CLI: Claude Code local + Agent SDK remote, Codex app-server, ACP agents); Happy Agent = own loop on Pi with reimplemented Codex/Claude/Grok Build prompts and tools, Claude inference via Agent SDK"
engines_supported: [claude-code, codex, grok-build, gemini-cli, antigravity, opencode, openclaw, acp-generic, bedrock]
model_access: "subscription logins reused from local claude/codex/grok CLIs; API keys; Amazon Bedrock; no Happy-provided model credits"
execution_env: "user host; Happy Agent restricted modes use macOS Seatbelt / Linux Bubblewrap; optional Docker-backed sessions; bots can run on configured runners or a team server"
per_bot_computer: "partial; each bot gets its own folder/workspace and may run on host, in a Docker image, or on a runner; no per-bot cloud VM"
persistent_bots: "yes (Happy Agent, 2026-09+); immutable username, display name, avatar, one continuous conversation; seeded admin bot 'Chief of Staff'"
memory: "no dedicated memory store found; bot = one durable conversation with automatic compaction; persistent /goal objectives"
routines: "partial; scheduled one-shot messages and wait/wait_until bounded to 24 h; persistent goals; workflows module; no cron/recurring schedule found"
group_chat: "partial; bots message each other (send_bot_message, <happy-agent> mentions), create tasks/subtasks; team mode shares sessions among people; no multi-bot room evidenced"
coding_workspace: "yes; diffs and branch changes on phone, worktrees from phone, file tree/read/write/ripgrep RPC, remote terminals (Ghostty-backed PTY), /review"
browser_use: unknown   # agent-browser skill exists in repo tooling only
computer_use: no
connectors: "MCP (stdio + streamable HTTP) in Happy Agent; skills/plugins; GitHub OAuth on relay"
channels: "Happy mobile/web app; push via Expo; Telegram built in for exported bots; generic bridge WebSocket protocol for other chat services"
mobile: "yes; core product. iOS 4.9 (1,033 ratings), Google Play 5.0 (3.1k+ reviews) as of 2026-10-20"
voice: "yes; ElevenLabs realtime voice agent that can message the session and answer permission prompts; free allowance then RevenueCat subscription or BYO ElevenLabs agent; not E2E"
approvals: "per-tool permission requests mirrored to phone (approve / approve for session / deny / abort); CLI modes default/acceptEdits/plan/read-only/safe-yolo/yolo; Happy Agent Auto/Workspace write/Read only/Full access"
e2e_encryption: "yes with caveats; NaCl box key wrap + AES-256-GCM per-session DEKs; pairing key delivered unauthenticated (open issue #1503); push titles, usage, metadata and server-held vendor tokens are not E2E"
self_host: "yes; `happy server` (PGlite, no Postgres/Redis/S3) or Docker/K8s server; mobile/web point at custom server URL"
multi_user: "partial; team mode = Happy Agent server + WorkOS organization ('Happy Social'), invite by email; relay-level session sharing still 'future' in docs"
pricing: "free and open source; paid voice subscription via RevenueCat (price unknown); no paid tier for sync"
maturity: "beta; CLI 1.x and store apps in production since 2025-07, desktop and Happy Agent pre-1.0 with daily previews; 657 open issues"
```

## What it is

Happy started as "Code on the go — control AI coding agents from your phone, browser, or terminal" ([happy-cli README](https://github.com/slopus/happy/blob/main/packages/happy-cli/README.md)): you run `happy claude` or `happy codex` instead of the agent command, scan a QR code, and the same live session appears on your phone. The maintainers' own framing: Happy is "end-to-end encrypted remote access to your coding agents ... The relay in the middle carries only ciphertext and can read nothing" (vendor claim; [happy-agent docs/happy.md](https://github.com/slopus/happy-agent/blob/main/docs/happy.md)).

Since mid-2026 the brand has shifted to "Any Model. Your Subscription. Happy Harness. Orchestrate Claude, Codex and Grok in one app" ([README](https://github.com/slopus/happy/blob/main/README.md), [happy.engineering](https://happy.engineering/)). The product family is now four repos ([README](https://github.com/slopus/happy/blob/main/README.md)):

| Repo | Role |
| --- | --- |
| [slopus/happy](https://github.com/slopus/happy) | mobile app (iOS/Android/web), original CLI, relay server |
| [slopus/happy-desktop](https://github.com/slopus/happy-desktop) | Electron desktop app (macOS/Windows/Linux) |
| [slopus/happy-agent](https://github.com/slopus/happy-agent) | headless agent runtime the desktop runs on |
| [slopus/slopus.github.io](https://github.com/slopus/slopus.github.io) | website and docs |

The happy-agent docs also describe "Happy 2", a self-hosted "Slack-like workspace where people and coding agents build together", started with `npx happy2` ([docs/happy.md](https://github.com/slopus/happy-agent/blob/main/docs/happy.md)); its source location is unknown (npm `happy2` had 1,462 downloads in the month to 2026-10-18, [npm API](https://api.npmjs.org/downloads/point/last-month/happy2)).

Target user: developers who already pay for Claude, ChatGPT/Codex or SuperGrok and want to keep long-running agents moving from a phone. "Happy adds a harness, not another bill" ([README](https://github.com/slopus/happy/blob/main/README.md)).

Mental model: control plane plus remote. The agent and your files stay on your computer; the phone is a synchronized client of one durable session, and "there is no separate remote mode" in Happy Agent ([docs/happy.md](https://github.com/slopus/happy-agent/blob/main/docs/happy.md)).

## Product and UX

- **Onboarding (mobile)**: create an account in the app with no email or password; install Happy Desktop or `npm install -g happy`; scan the QR code the computer shows ([App Store listing](https://apps.apple.com/us/app/happy-codex-claude-code-app/id6748571505)). The CLI offers mobile QR or web-browser auth ([ui/auth.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/ui/auth.ts)). Desktop pairs from Settings → Mobile Access, with no Node or CLI needed ([desktop docs/mobile-access.md](https://github.com/slopus/happy-desktop/blob/main/docs/mobile-access.md)).
- **From the phone**: start a session or pick up a desk session; notifications when an agent needs input or finishes; approve/deny permissions or run in Auto; pick model and effort from providers on the computer; review changes as a file list with colored diffs and branch changes; attach photos; group sessions by project; side chat; drafts that follow you between phone and computer ([App Store listing](https://apps.apple.com/us/app/happy-codex-claude-code-app/id6748571505), [app CHANGELOG](https://github.com/slopus/happy/blob/main/packages/happy-app/CHANGELOG.md)).
- **New-session composer**: pick machine, agent, model, permissions and git worktree in one screen; offline machines show "last seen" (iOS 1.8.0 notes, 2026-10-07, [App Store](https://apps.apple.com/us/app/happy-codex-claude-code-app/id6748571505)). Spawning into a directory that does not exist comes back as an explicit approval request ([docs/happy.md](https://github.com/slopus/happy-agent/blob/main/docs/happy.md)).
- **Bots on the phone**: "make one from your phone: pick a face, name it, start talking" (2026-09-20 changelog, [CHANGELOG](https://github.com/slopus/happy/blob/main/packages/happy-app/CHANGELOG.md)).
- **Voice**: mic button starts an ElevenLabs voice agent that knows all active sessions, can route instructions to the session you are looking at, and reads out permission requests and "ready" events ([docs/voice-architecture.md](https://github.com/slopus/happy/blob/main/docs/voice-architecture.md)).
- **Desktop**: model picker across Claude, Codex and Grok, model switching mid-task, bot roster with animated faces and a Chief of Staff ([happy-desktop tree](https://github.com/slopus/happy-desktop/tree/main/packages/happy-desktop-ui/src), [App Store](https://apps.apple.com/us/app/happy-codex-claude-code-app/id6748571505)).
- What feels distinctive: no account identity beyond a keypair; one session visible on terminal, desktop and phone at once; permission prompts answerable by voice.
- Quality signal: a store review calls it "vibe coded and lacks polish", citing navigation bugs and slow long chats (2026-05-13, [App Store reviews](https://apps.apple.com/us/app/happy-codex-claude-code-app/id6748571505)).

## Architecture

```
 phone / web (Expo app)          relay (happy-server)                 your computer
 master secret (32 B)   <--->  Fastify HTTP + Socket.IO /v1/updates  <--->  happy CLI + daemon (~/.happy)
 content keypair               Postgres: ciphertext blobs, ids, seq,        |-- claude (local, interactive) / Agent SDK (remote)
 decrypts all DEKs             presence, push tokens, usage                 |-- codex app-server, ACP agents
 ElevenLabs voice (direct)     Expo push -> APNs/FCM                        Happy Agent daemon (Unix socket API)
                               S3 / local files: encrypted images           |-- desktop app (Electron) as client
                                                                            |-- optional Tailcat exposure, team mode
```

- **Components**: `packages/happy-app` (Expo client for iOS, Android, web, plus `src-tauri`), `packages/happy-cli` (`happy` on npm), `packages/happy-server` (relay), `packages/happy-server-self-host` (bundled self-host runtime), `packages/happy-wire` (shared protocol types), `packages/happy-agent` (remote session control for the CLI, not the runtime), native ports `packages/happy-ios` (Swift, UIKit, GRDB, iOS 26) and `packages/happy-android` (Kotlin) ([repo tree](https://github.com/slopus/happy/tree/main/packages), [happy-ios README](https://github.com/slopus/happy/blob/main/packages/happy-ios/README.md), [happy-android AGENTS.md](https://github.com/slopus/happy/blob/main/packages/happy-android/AGENTS.md)). The old `slopus/happy-cli` and `slopus/happy-server` repos are archived ([happy-cli repo](https://github.com/slopus/happy-cli)).
- **Stack**: Expo ~55, React Native 0.83.1, `@elevenlabs/react-native`, `livekit-client` ([happy-app package.json](https://github.com/slopus/happy/blob/main/packages/happy-app/package.json)); Electron ^43.1 and React 19.2 desktop ([happy-desktop-electron package.json](https://github.com/slopus/happy-desktop/blob/main/packages/happy-desktop-electron/package.json)); relay on Node, Fastify with Zod, Socket.IO, Prisma/Postgres, Redis, S3/MinIO, Prometheus metrics ([docs/backend-architecture.md](https://github.com/slopus/happy/blob/main/docs/backend-architecture.md)).
- **CLI wrapper (how it attaches to local sessions)**:
  - Claude Code runs in a loop that switches between `local` and `remote` modes ([claude/loop.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/claude/loop.ts)). Local mode spawns the real interactive `claude` with a temporary settings file holding a `SessionStart` hook so Happy learns the Claude session ID ([claude/claudeLocal.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/claude/claudeLocal.ts)). Remote mode, used when the phone sends a message, drives Claude through the Claude Agent SDK ([claude/claudeRemote.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/claude/claudeRemote.ts), [permission-resolution.md](https://github.com/slopus/happy/blob/main/docs/permission-resolution.md)).
  - Codex goes through the Codex app-server JSON-RPC client ([codex/codexAppServerClient.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/codex/codexAppServerClient.ts)). Other agents use ACP: `happy agy`, `happy gemini` (deprecated), `happy openclaw`, `happy acp opencode`, `happy acp -- custom-agent` ([happy-cli README](https://github.com/slopus/happy/blob/main/packages/happy-cli/README.md), [acpAgentConfig.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/agent/acp/acpAgentConfig.ts)).
  - A background daemon registers the machine, spawns sessions on request from the phone, and keeps machine state synced; state lives in `~/.happy` (`access.key`, `settings.json`, `daemon.state.json`, `logs/`) ([docs/cli-architecture.md](https://github.com/slopus/happy/blob/main/docs/cli-architecture.md), [happy-cli README](https://github.com/slopus/happy/blob/main/packages/happy-cli/README.md)). The README recommends starting the daemon from the shell profile instead of launchd, because a LaunchAgent cannot reach the macOS keychain the Claude Agent SDK needs ([happy-cli README](https://github.com/slopus/happy/blob/main/packages/happy-cli/README.md)).
- **Happy Agent runtime** (desktop): headless daemon that "owns agents, tools, permissions, durable state, and the public API"; built on Pi; reimplements Codex prompts and tools on Pi's Codex transport; calls the Claude Agent SDK for inference with its built-in tools, skills and slash commands disabled, and supplies its own; uses xAI's Responses API with Grok CLI credentials ([happy-agent README](https://github.com/slopus/happy-agent/blob/main/README.md)). Clients talk to it over a private Unix socket through `@slopus/happy-agent-client`. It "speaks the Happy protocol natively": it registers as a machine on the relay and syncs every primary session ([docs/happy.md](https://github.com/slopus/happy-agent/blob/main/docs/happy.md)).
- **Wire protocol**: one Socket.IO endpoint `/v1/updates` with `user-scoped`, `session-scoped` and `machine-scoped` connections; durable `update` events carry a per-user monotonic `seq`; `ephemeral` events carry presence and usage; point-to-point RPC (`rpc-register`, `rpc-call`) is routed through `rpc:<userId>:<method>` rooms ([docs/realtime-sync-and-rpc.md](https://github.com/slopus/happy/blob/main/docs/realtime-sync-and-rpc.md), [docs/backend-architecture.md](https://github.com/slopus/happy/blob/main/docs/backend-architecture.md)). Writes use optimistic `expectedVersion` ([docs/encryption.md](https://github.com/slopus/happy/blob/main/docs/encryption.md)).
- **Models and auth**: Happy never hosts provider logins. Happy Agent reuses `codex`, `claude` and `grok login` credentials on the machine and cites Anthropic's policy that third-party Agent SDK apps draw from the user's Claude plan (vendor claim; [happy-agent README](https://github.com/slopus/happy-agent/blob/main/README.md)). Separately, the relay can store user vendor API keys (OpenAI, Anthropic, Gemini) encrypted with a server key ([docs/user-identity.md](https://github.com/slopus/happy/blob/main/docs/user-identity.md)).
- **Execution environment**: the user's host. Happy Agent's restricted modes run shell commands under macOS Seatbelt or Linux Bubblewrap with shell network blocked; Docker-backed sessions and per-bot "host or Docker image" settings exist ([happy-agent README](https://github.com/slopus/happy-agent/blob/main/README.md), [bots README](https://github.com/slopus/happy-agent/blob/main/packages/happy-agent-modules/sources/bots/README.md)).
- **State and storage**: relay Postgres holds encrypted session/machine/project/artifact/KV blobs ([schema.prisma](https://github.com/slopus/happy/blob/main/packages/happy-server/prisma/schema.prisma)). Happy Agent persists sessions in its daemon (SQLite) so they survive client disconnect and restart ([happy-agent README](https://github.com/slopus/happy-agent/blob/main/README.md)).
- **Remote access alternatives**: Happy Agent embeds Tailcat v0.7.0 ([tailscale/tailcat](https://github.com/tailscale/tailcat), BSD-3-Clause) so a daemon can be reached across NAT through an "unguessable" address with no Tailscale account, gated by a local bearer token (standalone) or WorkOS token (team) ([docs/tailcat.md](https://github.com/slopus/happy-agent/blob/main/docs/tailcat.md)). An unpublished, experimental `expo-tailcat` module puts an app-scoped WireGuard userspace connection on the phone ([expo-tailcat README](https://github.com/slopus/happy/blob/main/packages/expo-tailcat/README.md)).
- **Extension surface**: Happy Agent MCP (stdio and streamable HTTP), skills, plugins, slash commands, `happy.toml` and `mcp.toml` config ([happy-agent README](https://github.com/slopus/happy-agent/blob/main/README.md)); exported-bot bridge protocol ([docs/exported-bot-protocol.md](https://github.com/slopus/happy-agent/blob/main/docs/exported-bot-protocol.md)); remote terminal API with Ghostty-backed PTYs and WebSocket VT replay ([happy-agent README](https://github.com/slopus/happy-agent/blob/main/README.md)).

### E2E encryption protocol (as implemented)

**Keys.**
- *Master secret*: 32 random bytes created at signup on the phone or browser; backed up as a base32 string in dash-separated 5-character groups ([secretKeyBackup.ts](https://github.com/slopus/happy/blob/main/packages/happy-app/sources/auth/secretKeyBackup.ts), [security docs](https://happy.engineering/docs/security/)).
- *Derived keys* (HMAC-SHA512 tree): `contentDataKey = deriveKey(master, 'Happy EnCoder', ['content'])`, then a NaCl box keypair seeded from it (the *content keypair*); an analytics ID and provider-account hash key; a master blob key for legacy image attachments ([sync/encryption/encryption.ts](https://github.com/slopus/happy/blob/main/packages/happy-app/sources/sync/encryption/encryption.ts)).
- *Account identity*: an Ed25519 signing keypair from the secret. `POST /v1/auth` verifies a signed random challenge and upserts `Account` by public key; the server returns a bearer token signed with `HANDY_MASTER_SECRET`. No passwords exist ([encryption.ts authChallenge](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/encryption.ts), [authRoutes.ts](https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/api/routes/authRoutes.ts), [docs/user-identity.md](https://github.com/slopus/happy/blob/main/docs/user-identity.md)).
- *DEKs*: the CLI makes a random 32-byte AES-256 key per session and keeps a random `machineKey` for machine records. It wraps each one to the content public key with an anonymous NaCl box (ephemeral X25519 keypair; layout `ephPub(32) | nonce(24) | ct`, prefixed with version byte 0) and uploads it as `dataEncryptionKey` ([api/api.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/api.ts), [docs/encryption.md](https://github.com/slopus/happy/blob/main/docs/encryption.md)).
- *Content encryption*: AES-256-GCM, layout `ver(1)=0 | nonce(12) | ct | tag(16)`, with no associated data ([encryptWithDataKey](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/encryption.ts)). Older "legacy" accounts use NaCl secretbox (XSalsa20-Poly1305) directly under the shared master secret ([docs/encryption.md](https://github.com/slopus/happy/blob/main/docs/encryption.md)). Image blobs use secretbox under a per-session subkey `deriveKey(DEK, 'Happy Blobs', ['session'])` ([encryption.ts](https://github.com/slopus/happy/blob/main/packages/happy-app/sources/sync/encryption/encryption.ts)).

**Pairing (terminal to phone).**
1. The CLI makes an ephemeral NaCl box keypair and sends `POST /v1/auth/request { publicKey, supportsV2: true }`. It shows `happy://terminal?<base64url(pub)>` as a QR code, or opens a web-auth URL, then polls the same endpoint every second ([ui/auth.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/ui/auth.ts)).
2. The phone scans the QR code and builds two answers: V1 = box(master secret) and V2 = box(`0x00 || content public key`), both to the CLI's ephemeral key. It asks the server `GET /v1/auth/request/status` and sends V2 only if the server reports `supportsV2`, otherwise V1, via `POST /v1/auth/response` ([useConnectTerminal.ts](https://github.com/slopus/happy/blob/main/packages/happy-app/sources/hooks/useConnectTerminal.ts), [authApprove.ts](https://github.com/slopus/happy/blob/main/packages/happy-app/sources/auth/authApprove.ts)).
3. The server stores the response; the first writer wins. On the next poll it returns the response plus a bearer token for the approving account ([authRoutes.ts](https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/api/routes/authRoutes.ts)).
4. The CLI opens the box. With 32 bytes it stores a legacy credential (master secret); with a `0x00`-prefixed key it stores `{publicKey, machineKey: random(32), token}` ([ui/auth.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/ui/auth.ts)).

Result: in V2 the CLI holds only the content public key, its machine key, and the DEKs of sessions it created. It "cannot decrypt other sessions' DEKs". When the phone resumes a session on a machine, it hands that session's raw DEK back to the daemon ([security docs](https://happy.engineering/docs/security/), [encryption.ts comments](https://github.com/slopus/happy/blob/main/packages/happy-app/sources/sync/encryption/encryption.ts)).

**Adding devices.** A new phone picks "Restore an existing account" and shows an account-restoration QR; a signed-in phone scans it under Settings → Account → Link New Device (the `/v1/auth/account/request|response` pair). Typing the secret key also works. Desktop "cannot list or selectively revoke phones", and logging out "is not a server-side per-device revocation guarantee" ([desktop docs/mobile-access.md](https://github.com/slopus/happy-desktop/blob/main/docs/mobile-access.md), [authRoutes.ts](https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/api/routes/authRoutes.ts)).

**What is encrypted.** Session metadata (path, host, home dir, summary, Claude session ID, tools, lifecycle), agent state (pending and completed permission requests with tool arguments and decisions), every message, machine metadata and daemon state, artifact header and body, KV values, access keys, RPC params and results, session avatars and image attachments ([docs/encryption.md](https://github.com/slopus/happy/blob/main/docs/encryption.md), [RpcHandlerManager.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/rpc/RpcHandlerManager.ts), [SESSION_AVATARS.md](https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/api/routes/SESSION_AVATARS.md)).

## Capabilities in detail

**Persistent bots and identity (Happy Agent).** "Bots are persistent single-conversation assistants", each with an immutable username, a dedicated folder and workspace, one root agent, an avatar and an admin flag. On first start the daemon seeds one admin bot, "Chief of Staff" (`chief_of_staff` system key). Its instructions are injected from source on every inference, so upgrades update it without touching its identity. Only admin bots can call `create_bot`, and only to create non-admin bots; unnamed bots name themselves from their first message ([bots README](https://github.com/slopus/happy-agent/blob/main/packages/happy-agent-modules/sources/bots/README.md)). Per-bot settings cover a secret allowlist, whether the bot is confined to its own tree, and host vs Docker execution (same source).

**Memory.** No dedicated long-term memory store was found. A bot is "one continuous chat" with automatic compaction, and `/goal` objectives survive restarts ([bots README](https://github.com/slopus/happy-agent/blob/main/packages/happy-agent-modules/sources/bots/README.md), [happy-agent README](https://github.com/slopus/happy-agent/blob/main/README.md)). Unknown beyond that.

**Routines.** Every agent gets `wait` / `wait_until`. `schedule_message`, `list_scheduled_messages` and `cancel_scheduled_message` deliver messages later. Both waits and scheduled messages are capped at 24 hours and survive daemon restarts ([scheduling README](https://github.com/slopus/happy-agent/blob/main/packages/happy-agent-modules/sources/scheduling/README.md)). No cron or recurring schedule was found (a code search for "cron" in happy-agent hit only a prompt file).

**Multi-agent and multi-user.** Subagents across providers; tasks created by bots report back to the bot; `list_bots` and `send_bot_message` ([bots README](https://github.com/slopus/happy-agent/blob/main/packages/happy-agent-modules/sources/bots/README.md), [agents-and-collaboration.md](https://github.com/slopus/happy-agent/blob/main/docs/agents-and-collaboration.md)). "Natively multiplayer: deploy a team server and work together. Everyone signs in as themselves" ([happy.engineering](https://happy.engineering/)). A team is a WorkOS organization with a registered Happy Agent server endpoint, managed through "Happy Social" sign-in and admin-bot tools such as `create_happy_team` and `invite_happy_team_member` ([docs/happy-teams.md](https://github.com/slopus/happy-agent/blob/main/docs/happy-teams.md)). Relay-level E2E session sharing (re-wrapping a DEK for a friend's key) is still labelled "Future" ([security docs](https://happy.engineering/docs/security/)).

**Coding workspace.** Remote RPCs against a session: `abort`, `bash`, `listFileTree`, `readFile`, `writeFile`, `ripgrep`, `communication`. They run "through the same AgentContext, filesystem boundary, and sandbox as the agent's own tools" ([docs/happy.md](https://github.com/slopus/happy-agent/blob/main/docs/happy.md)). The phone also offers diff review, worktree creation and model/effort switching ([App Store](https://apps.apple.com/us/app/happy-codex-claude-code-app/id6748571505)).

**Channels.** The Happy app (iOS, Android, web). Exported bots: "Telegram is built in and needs no bridge", and other services connect through a bridge on one authenticated WebSocket (`/v0/exported-bots/connect`, per-bot bridge token stored as a SHA-256 digest) ([exported-bot-protocol.md](https://github.com/slopus/happy-agent/blob/main/docs/exported-bot-protocol.md)).

**Push notifications and permission prompts.** The CLI or daemon posts session events of kind `done` ("It's ready!"), `permission` ("Permission request") or `question` ("Clarification needed") to `POST /v1/sessions/:id/push-event`. The body is the session summary text or the last path segment of the project folder ([pushNotifications.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/pushNotifications.ts)). The server suppresses the push when a UI client reports `app-state: active`, otherwise sends it through Expo's push API, and reports `sent`/`suppressed`/`no_tokens`/`failed` back. That reporting was added after "a total push outage stayed invisible for two months" ([pushDispatch.ts](https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/push/pushDispatch.ts), [pushSend.ts](https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/push/pushSend.ts)). Per-message pushes were removed as too noisy (same source). Permission requests live in encrypted `agentState.requests` and are answered with `approved | approved_for_session | denied | abort` plus an optional mode and `allowTools` ([docs/encryption.md](https://github.com/slopus/happy/blob/main/docs/encryption.md)). "Don't ask again" grants persist (2026-08-25 changelog, [CHANGELOG](https://github.com/slopus/happy/blob/main/packages/happy-app/CHANGELOG.md)). Caveat: `happy agy` runs `agy --print` with no per-tool approval gate ([happy-cli README](https://github.com/slopus/happy/blob/main/packages/happy-cli/README.md)).

**Voice.** ElevenLabs Conversational AI over LiveKit/WebRTC on native and WebSocket on web. Client tools `messageClaudeCode` and `processPermissionRequest` route to the focused session. Context arrives as silent `sendContext` (new messages, focus) or response-triggering `sendPrompt` (permissions, ready), queued while anyone speaks, with 0.5 VAD threshold and 300 ms silence debounce ([docs/voice-architecture.md](https://github.com/slopus/happy/blob/main/docs/voice-architecture.md), [PRIVACY.md](https://github.com/slopus/happy/blob/main/PRIVACY.md)). Limits: free 20 min per 30 days, subscribed 5 h per 30 days, 100 conversations per 30 days hard cap, unlimited with a bring-your-own ElevenLabs agent; cost about $0.01/min (vendor numbers, [docs/paid-voice.md](https://github.com/slopus/happy/blob/main/docs/paid-voice.md)). The iOS 1.8.0 notes say "1 hour free, then subscription required" ([App Store](https://apps.apple.com/us/app/happy-codex-claude-code-app/id6748571505)); the two sources disagree.

**Multi-device sync.** Server-ordered per-user `seq` updates over Socket.IO, with re-fetch after reconnect ([docs/realtime-sync-and-rpc.md](https://github.com/slopus/happy/blob/main/docs/realtime-sync-and-rpc.md)). An encrypted KV store with versioned mutations carries preferences such as layout choice ([docs/encryption.md](https://github.com/slopus/happy/blob/main/docs/encryption.md), [CHANGELOG](https://github.com/slopus/happy/blob/main/packages/happy-app/CHANGELOG.md)). Drafts sync between phone and desktop (2026-09-20 changelog). Presence is debounced in memory; sessions and machines go offline after 10 minutes of silence ([docs/backend-architecture.md](https://github.com/slopus/happy/blob/main/docs/backend-architecture.md)).

**Browser and computer use.** Not evidenced as product features (unknown).

## Security and trust model

### Relay threat model (honest-but-curious and malicious operator)

Assumes the CLI pairing is honest unless stated. "Relay" means whoever runs `happy-server`, the hosted default `api.cluster-fluster.com` ([happy-serve-self-host.md](https://github.com/slopus/happy/blob/main/docs/plans/happy-serve-self-host.md)), or anyone holding its database and `HANDY_MASTER_SECRET`.

**The relay cannot read**: message content, prompts, tool calls and results, file contents, session metadata (path, host, machine name, summary), agent state including permission-request arguments, artifacts, KV values, images, RPC params and results ([docs/encryption.md](https://github.com/slopus/happy/blob/main/docs/encryption.md), [RpcHandlerManager.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/rpc/RpcHandlerManager.ts)).

**The relay can read (plaintext)**:
- Account public key (hex), account CUID, optional profile (`firstName`, `lastName`, `username`, avatar), GitHub linkage, social graph (`UserRelationship`, `UserFeedItem`) ([schema.prisma](https://github.com/slopus/happy/blob/main/packages/happy-server/prisma/schema.prisma)). An open issue notes the docs claimed public keys were hashed while code stores them in plaintext hex ([#416](https://github.com/slopus/happy/issues/416)).
- Every ID, session `tag`, project `externalId`, per-object `seq` and version, timestamps, `active`/`lastActiveAt`, presence pings, message counts, sizes and timing (so activity patterns), client type and version (`X-Happy-Client`), and IP addresses ([schema.prisma](https://github.com/slopus/happy/blob/main/packages/happy-server/prisma/schema.prisma), [docs/backend-architecture.md](https://github.com/slopus/happy/blob/main/docs/backend-architecture.md), [ui/auth.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/ui/auth.ts)).
- KV keys, which are "Unencrypted for indexing" ([schema.prisma](https://github.com/slopus/happy/blob/main/packages/happy-server/prisma/schema.prisma)).
- RPC method names and timing: methods are registered in plaintext with a scope prefix (e.g. a session's `bash`, `readFile`) ([RpcHandlerManager.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/rpc/RpcHandlerManager.ts), [docs/happy.md](https://github.com/slopus/happy-agent/blob/main/docs/happy.md)).
- Per-session usage reports with token counts and cost ([usageHandler.ts](https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/api/socket/usageHandler.ts)).
- **Push notification text**: title (kind) and body (session summary or project folder name) are sent in plaintext to the relay and then to Expo, APNs or FCM ([pushNotifications.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/pushNotifications.ts), [pushDispatch.ts](https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/push/pushDispatch.ts)). This contradicts PRIVACY.md (updated 2026-10-08), which says pushes "are sent directly from your devices to each other, not from our backend ... We never see the content of your notifications" ([PRIVACY.md](https://github.com/slopus/happy/blob/main/PRIVACY.md)). It also contradicts docs saying the operator cannot see "your machine's name" or titles, at least for folder-named sessions ([docs/happy.md](https://github.com/slopus/happy-agent/blob/main/docs/happy.md)).
- **Server-side secrets the relay can decrypt**: GitHub OAuth tokens and user vendor API keys (OpenAI, Anthropic, Gemini). They are encrypted with a KeyTree from `HANDY_MASTER_SECRET` and "are not end-to-end encrypted" ([docs/encryption.md](https://github.com/slopus/happy/blob/main/docs/encryption.md)); an open PR proposes client-side encryption ([#681](https://github.com/slopus/happy/issues/681)).
- **Voice**: audio and context, including message history, project path and pending permission arguments, go directly to ElevenLabs and are "not covered by Happy's end-to-end encryption" ([PRIVACY.md](https://github.com/slopus/happy/blob/main/PRIVACY.md)). The relay sees voice-usage metadata and mints tokens; the ElevenLabs user ID is HMAC(CUID, master secret) ([docs/user-identity.md](https://github.com/slopus/happy/blob/main/docs/user-identity.md)).

**What a malicious relay can do (active attacks)**:
1. **Pairing-key substitution leading to RCE on the host** (open issue [#1503](https://github.com/slopus/happy/issues/1503), 2026-07-10, unanswered as of 2026-10-20). The CLI sends its ephemeral public key to the server, and the response is an anonymous box with no sender authentication and no fingerprint confirmation ([ui/auth.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/ui/auth.ts)). So the relay can return its own "content public key". The CLI then wraps every new DEK to the attacker. The relay can read all of that terminal's sessions and forge valid AEAD user messages, which the agent executes with its tools. The phone would fail to decrypt those sessions, so the attack is detectable after the fact but not prevented [INFERENCE]. Desktop shows a "public account-key fingerprint" for the CLI login but documents no comparison step ([mobile-access.md](https://github.com/slopus/happy-desktop/blob/main/docs/mobile-access.md)).
2. **Protocol downgrade**: the phone picks V1 (send the full master secret to the terminal) or V2 (send only the content public key) based on the server-reported `supportsV2` flag ([authApprove.ts](https://github.com/slopus/happy/blob/main/packages/happy-app/sources/auth/authApprove.ts)). A relay can force V1 and widen what each terminal holds. The secret stays boxed to the QR-scanned key, so the relay itself does not learn it [INFERENCE].
3. **Replay, reorder, drop**: GCM is used without associated data binding ciphertext to session ID or `seq`, and the RPC handler decrypts params with no nonce or timestamp check, so a relay could replay an earlier user prompt or `bash` RPC within the same session, or withhold messages [INFERENCE from [encryption.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/encryption.ts) and [RpcHandlerManager.ts](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/rpc/RpcHandlerManager.ts)]. Legacy accounts share one secretbox key across sessions, so cross-session swaps are possible there too [INFERENCE].
4. **Client-code trust root**: the web client is served by the operator (self-host injects `window.__HAPPY_CONFIG__` into the bundled webapp), and the mobile app tracks OTA update versions. Whoever ships client JS can exfiltrate the master secret, so E2E does not protect against the vendor itself [INFERENCE from [happy-serve-self-host.md](https://github.com/slopus/happy/blob/main/docs/plans/happy-serve-self-host.md) and [product-analytics.md](https://github.com/slopus/happy/blob/main/docs/product-analytics.md)].
5. **Account or token forgery on careless self-hosts**: auth tokens are derived from `HANDY_MASTER_SECRET`, and the repo ships public dev values for it (`local-dev-secret-not-for-production`, etc.), so copied configs allow forging tokens for any user ID (open issue [#1764](https://github.com/slopus/happy/issues/1764), 2026-09-07).

**Non-relay attackers**: pairing requests have no expiry and the first authenticated responder wins, so anyone who captures a QR code or auth URL (screen share, conference demo) can later bind that terminal to their own account (open issue [#674](https://github.com/slopus/happy/issues/674); [authRoutes.ts](https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/api/routes/authRoutes.ts)). Other open issues: no rate limiting ([#599](https://github.com/slopus/happy/issues/599)), unsanitized Mermaid SVG on web ([#1086](https://github.com/slopus/happy/issues/1086)), `--claude-env` values logged in plaintext ([#1279](https://github.com/slopus/happy/issues/1279)), a vulnerable MCP SDK pin ([#1224](https://github.com/slopus/happy/issues/1224)), and a "Security Contact?" request ([#329](https://github.com/slopus/happy/issues/329)). No GitHub security advisories are published (API returned 0, 2026-10-20).

### Local trust model
- Happy Agent has four permission modes. Auto does a one-call model review of risky escalations and fails closed. Workspace write is the default (edits in the workdir and temp paths, shell network blocked). Read only and Full access round out the set. Sandboxing uses Seatbelt or Bubblewrap ([happy-agent README](https://github.com/slopus/happy-agent/blob/main/README.md)).
- Secret bundles are stored as "plaintext JSON" in Happy Agent's SQLite (mode 0600), injected per command only when named; command output is not redacted ([happy-agent README](https://github.com/slopus/happy-agent/blob/main/README.md)).
- Phone RPCs get no wider access than the agent ([docs/happy.md](https://github.com/slopus/happy-agent/blob/main/docs/happy.md)). Self-host mode never silently falls back to the public server ("Fail closed", [happy-serve-self-host.md](https://github.com/slopus/happy/blob/main/docs/plans/happy-serve-self-host.md)).
- **Telemetry**: PostHog analytics in the phone and desktop apps, on by default with opt-out. They are tied to an ID derived from the secret key and include model, provider, effort, device and IP-derived city; Happy Agent itself sends none ([PRIVACY.md](https://github.com/slopus/happy/blob/main/PRIVACY.md)).

## Traction and momentum

All GitHub numbers as of 2026-10-20 via the GitHub API.
- **slopus/happy**: 24,231 stars, 2,071 forks, 84 contributors, 657 open issues and 416 open PRs, 3,564 commits. The first commit ("feat: initial version") is dated 2025-07-13 and the repo was created 2025-07-18, so the star history is not from a renamed repo. Last push 2026-10-19. 300+ commits since 2026-09-20 ([repo](https://github.com/slopus/happy)).
- Top committers: ex3ndr (Steve Korshakov) 1,866 and bra1nDump (Kirill Dubovitskiy) 901, then ahundt 249 and Scoteezy 220 ([contributors](https://github.com/slopus/happy/graphs/contributors)). Korshakov's bio cites past work on Telegram-S, Openland and Tact ([GitHub profile](https://github.com/ex3ndr)).
- **happy-desktop** (created 2026-07-11): 94 stars, 114 releases, 46 in the last 30 days; latest stable v0.0.98 (2026-10-17), previews up to v0.0.99-preview.10 on 2026-10-19 ([releases](https://github.com/slopus/happy-desktop/releases)).
- **happy-agent** (created 2026-07-04): 32 stars, 192 releases, 86 in the last 30 days; v0.4.101 on 2026-10-19 ([releases](https://github.com/slopus/happy-agent/releases)).
- **CLI**: npm `happy` 1.2.5 latest, 1.2.6-beta.1 (2026-10-09); 34,457 downloads in the month to 2026-10-18, plus 2,071 for the legacy `happy-coder` package ([npm API](https://api.npmjs.org/downloads/point/last-month/happy)). Release tags: 1.1.10 (2026-06-23), 1.2.1 (2026-08-25) through 1.2.5 (2026-09-22) ([releases](https://github.com/slopus/happy/releases)).
- **Mobile**: iOS "Happy: Codex & Claude Code App" v1.8.0 (2026-10-07), first released 2025-07-21, 4.86 average from 1,033 ratings, #90 in Developer Tools, seller Bulka, LLC ([iTunes lookup](https://itunes.apple.com/lookup?id=6748571505), [App Store](https://apps.apple.com/us/app/happy-codex-claude-code-app/id6748571505)). Google Play shows 5.0 from 3.1k+ reviews (vendor-displayed, [happy.engineering](https://happy.engineering/)).
- **Community**: Discord linked from the README; community credits in the app changelog ([CHANGELOG](https://github.com/slopus/happy/blob/main/packages/happy-app/CHANGELOG.md)).
- **Business model**: everything free and MIT. Revenue comes from voice subscriptions through RevenueCat (price unknown). The desktop and server code also contain "Happy Cloud"/"Happy Social" WorkOS accounts for teams; whether teams will be paid is unknown ([docs/paid-voice.md](https://github.com/slopus/happy/blob/main/docs/paid-voice.md), [docs/happy-teams.md](https://github.com/slopus/happy-agent/blob/main/docs/happy-teams.md)). Hosted relay costs (Postgres, K8s, Expo push) are absorbed by the maker [INFERENCE].

## Strengths

- Proven at scale: the most-starred open-source phone remote for coding agents, real store ratings, and 15 months in production.
- Clean, readable key hierarchy (master secret → content keypair → per-session DEKs) with good docs (`docs/encryption.md`, the website security page). This is the reference that Lorca says it follows ([Lorca ARCHITECTURE.md](https://github.com/egoist/lorca/blob/main/ARCHITECTURE.md)).
- Keypair-only accounts: no email, password or OAuth needed for the core product.
- Wraps unmodified local agent installs, including the real interactive `claude` TUI in local mode, so users keep their subscription and terminal workflow.
- Thoughtful push design: event-kind pushes only, presence-based suppression, outcome reporting.
- Self-host in one command (`happy server` with PGlite) and an explicit no-silent-fallback rule.
- Fast-moving successor stack (Happy Agent) with Seatbelt/Bubblewrap sandboxing, durable sessions, bots, Telegram export and team mode.

## Weaknesses and risks

- **Unauthenticated pairing** ([#1503](https://github.com/slopus/happy/issues/1503)) undermines the "relay can read nothing" claim against a malicious or compromised relay, and the escalation path ends in code execution on the host.
- **Docs and privacy policy overstate E2E**: plaintext push titles, usage and cost data, KV keys, and server-decryptable vendor tokens; PRIVACY.md misdescribes the push path.
- No per-device revocation and no device list; a leaked master secret means the whole account until a new account is made ([mobile-access.md](https://github.com/slopus/happy-desktop/blob/main/docs/mobile-access.md)).
- Two parallel stacks (original CLI with local/remote mode switching vs Happy Agent with a single session) plus native iOS and Android rewrites in progress. Users must understand which `happy` command belongs to which product ([happy-agent README](https://github.com/slopus/happy-agent/blob/main/README.md)).
- High issue and PR backlog (657 issues, 416 PRs) with security issues open for months; quality complaints in store reviews.
- Platform risk: depends on Anthropic allowing subscription use through the Agent SDK, on OpenAI's Codex app-server, and on the Grok CLI auth store. Happy Agent reimplements vendor prompts and tools, which can break when vendors change.
- Voice sends full session context to ElevenLabs; sources disagree on the free allowance.
- Sustainability: free relay with only voice monetized; team or cloud monetization is unannounced (unknown).

## Ideas worth taking for Memoshi

- **Adopt the key hierarchy** (account secret → HKDF/HMAC-derived content keypair → random per-session and per-bot DEKs wrapped to the content public key). Hosts get only the public key, which makes per-object sharing and per-host scoping cheap.
- **Fix Happy's pairing gap**: authenticate the pairing response (sign the response with the account key, or use Noise XX/IK with a short authentication string shown on both screens). Expire pairing requests after about 5 minutes. Never let the server choose the protocol version.
- **Bind AEAD to context**: use session ID, message seq and sender as associated data, and add replay protection for RPCs and commands that run tools.
- **Keep push content opaque**: send only a kind plus an encrypted payload, and decrypt on device with an iOS Notification Service Extension. Happy's plaintext summary or folder name is the leak to avoid.
- **Copy the push-dispatch semantics**: three event kinds (done, permission, question), suppression when an active UI client is present, and explicit outcome reporting so outages are visible.
- **"No separate remote mode"** (Happy Agent): phone, desktop and channel messages all enter the same session queue and permission boundary. That is simpler than Happy CLI's local/remote switching.
- **Phone RPCs limited to the agent's own sandbox** (bash, readFile, ripgrep go through the agent context), plus explicit approval before creating directories on the host.
- **Device management from day one**: a device list, per-device revocation (per-device keys wrapped from the account key), and a recovery-key UX like Happy's base32 groups.
- **Voice as an opt-in, clearly non-E2E layer** with BYO-provider bypass. Treat voice context as an export of transcript data and label it in the UI.
- **One-command self-host** with embedded Postgres-compatible storage (PGlite) and fail-closed server URL handling.
- **Avoid** storing third-party API keys server-side when sync is advertised as zero-knowledge; keep them on the host or wrap them client-side.

## Open questions

- Will [#1503](https://github.com/slopus/happy/issues/1503) be fixed, and does Happy Agent's pairing (desktop "Mobile Access") share the same unauthenticated flow? Check `packages/happy-agent-modules/sources/mobileConnector` in happy-agent.
- Where are the phone's master secret and the CLI's DEKs stored: Keychain/Keystore or app storage? (`tokenStorage.ts` not inspected; the docs say CLI DEKs are kept "memory and on disk".)
- Voice subscription price and whether team mode or Happy Cloud will be paid: check the in-app paywall or RevenueCat offerings.
- Source location and license of "Happy 2" (`npx happy2`).
- Whether the hosted relay keeps message ciphertext indefinitely ("Retained until you delete it", [PRIVACY.md](https://github.com/slopus/happy/blob/main/PRIVACY.md)) and how account deletion propagates.
- Whether mobile OTA updates are code-signed or pinned: inspect `app.config.js` and `eas.json` update settings.

## Sources

1. https://github.com/slopus/happy (README, repo API stats, releases, contributors, commits, issues; fetched 2026-10-20)
2. https://github.com/slopus/happy/blob/main/docs/encryption.md
3. https://github.com/slopus/happy/blob/main/docs/backend-architecture.md
4. https://github.com/slopus/happy/blob/main/docs/user-identity.md
5. https://github.com/slopus/happy/blob/main/docs/realtime-sync-and-rpc.md
6. https://github.com/slopus/happy/blob/main/docs/cli-architecture.md
7. https://github.com/slopus/happy/blob/main/docs/permission-resolution.md
8. https://github.com/slopus/happy/blob/main/docs/voice-architecture.md
9. https://github.com/slopus/happy/blob/main/docs/paid-voice.md
10. https://github.com/slopus/happy/blob/main/docs/deployment.md
11. https://github.com/slopus/happy/blob/main/docs/plans/happy-serve-self-host.md
12. https://github.com/slopus/happy/blob/main/docs/product-analytics.md
13. https://github.com/slopus/happy/blob/main/PRIVACY.md
14. https://github.com/slopus/happy/blob/main/packages/happy-cli/README.md
15. https://github.com/slopus/happy/blob/main/packages/happy-cli/src/ui/auth.ts
16. https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/encryption.ts
17. https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/api.ts
18. https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/rpc/RpcHandlerManager.ts
19. https://github.com/slopus/happy/blob/main/packages/happy-cli/src/api/pushNotifications.ts
20. https://github.com/slopus/happy/blob/main/packages/happy-cli/src/claude/loop.ts
21. https://github.com/slopus/happy/blob/main/packages/happy-cli/src/claude/claudeLocal.ts
22. https://github.com/slopus/happy/blob/main/packages/happy-cli/src/codex/codexAppServerClient.ts
23. https://github.com/slopus/happy/blob/main/packages/happy-cli/src/agent/acp/acpAgentConfig.ts
24. https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/api/routes/authRoutes.ts
25. https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/push/pushDispatch.ts
26. https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/push/pushSend.ts
27. https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/api/socket/usageHandler.ts
28. https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/api/routes/SESSION_AVATARS.md
29. https://github.com/slopus/happy/blob/main/packages/happy-server/prisma/schema.prisma
30. https://github.com/slopus/happy/blob/main/packages/happy-server-self-host/README.md
31. https://github.com/slopus/happy/blob/main/packages/happy-app/sources/hooks/useConnectTerminal.ts
32. https://github.com/slopus/happy/blob/main/packages/happy-app/sources/auth/authApprove.ts
33. https://github.com/slopus/happy/blob/main/packages/happy-app/sources/auth/secretKeyBackup.ts
34. https://github.com/slopus/happy/blob/main/packages/happy-app/sources/sync/encryption/encryption.ts
35. https://github.com/slopus/happy/blob/main/packages/happy-app/CHANGELOG.md
36. https://github.com/slopus/happy/blob/main/packages/happy-app/package.json
37. https://github.com/slopus/happy/blob/main/packages/happy-ios/README.md
38. https://github.com/slopus/happy/blob/main/packages/happy-android/AGENTS.md
39. https://github.com/slopus/happy/blob/main/packages/expo-tailcat/README.md
40. https://github.com/slopus/happy/issues/1503 (content key delivered unauthenticated)
41. https://github.com/slopus/happy/issues/1764 (public development master secret)
42. https://github.com/slopus/happy/issues/674 (pairing requests never expire)
43. https://github.com/slopus/happy/issues/681, /416, /599, /1086, /1224, /1279, /329
44. https://github.com/slopus/happy-agent (README, releases, contributors)
45. https://github.com/slopus/happy-agent/blob/main/docs/happy.md
46. https://github.com/slopus/happy-agent/blob/main/docs/tailcat.md
47. https://github.com/slopus/happy-agent/blob/main/docs/happy-teams.md
48. https://github.com/slopus/happy-agent/blob/main/docs/exported-bot-protocol.md
49. https://github.com/slopus/happy-agent/blob/main/docs/agents-and-collaboration.md
50. https://github.com/slopus/happy-agent/blob/main/packages/happy-agent-modules/sources/bots/README.md
51. https://github.com/slopus/happy-agent/blob/main/packages/happy-agent-modules/sources/scheduling/README.md
52. https://github.com/slopus/happy-desktop (README, releases, contributors)
53. https://github.com/slopus/happy-desktop/blob/main/docs/mobile-access.md
54. https://github.com/slopus/happy-desktop/blob/main/packages/happy-desktop-electron/package.json
55. https://happy.engineering/ (fetched 2026-10-20)
56. https://happy.engineering/docs/security/ (fetched 2026-10-20)
57. https://apps.apple.com/us/app/happy-codex-claude-code-app/id6748571505 and https://itunes.apple.com/lookup?id=6748571505 (fetched 2026-10-20)
58. https://api.npmjs.org/downloads/point/last-month/happy, /happy-coder, /happy2 (fetched 2026-10-20)
59. https://github.com/tailscale/tailcat (repo API)
60. https://github.com/slopus/happy-cli (archived predecessor repo)
61. https://github.com/ex3ndr and https://github.com/bra1nDump (GitHub profiles via API)
62. https://github.com/egoist/lorca/blob/main/ARCHITECTURE.md (design-derivation reference)
