# Lorca

> A GPL-3.0, local-first Grok Bot clone from EGOIST: a roster of persistent named bots that run on computers you own (a Rust CLI as the agent runtime), synced end-to-end encrypted across desktop and phone through a zero-knowledge relay modeled on Happy. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Lorca
slug: lorca
category: oss-bot-roster-desktop
maker: EGOIST (GitHub egoist; CEO of ChatWise.app / Umida Inc.)
license: GPL-3.0-only
repo: https://github.com/egoist/lorca
website: https://lorca.app
first_public: 2026-09-18            # repo created; first release cli-v0.1.1 on 2026-09-24
latest_release: cli-v0.1.21 + desktop-v0.1.16, 2026-10-16; mobile-v1.0.8, 2026-10-15
release_cadence: "44 GitHub releases in 23 days across cli/desktop/mobile tracks (~13/week); ~456 commits in 32 days"
stars: 316 (as of 2026-10-20)
forks: 31 (as of 2026-10-20)
contributors: 1 human (3 incl. github-actions and imgbot; as of 2026-10-20)
primary_language: Rust
stack: "Rust CLI (tokio, rusqlite, rustls) = localhost WebSocket service + own agent loop; Rust relay (axum, SQLite or Postgres, S3); Go desktop app on EGOIST's MyGo native UI; deprecated AppKit/Swift Mac app; Expo/React Native phone app over the same Rust core via UniFFI; TanStack Start site on Cloudflare Workers"
platforms: [macos, windows, linux, ios, android, cli]
agent_engine: own loop (Rust port of pi-agent-core) + wraps coding CLIs as delegated sub-agents
engines_supported: [raw-api, claude-code, codex, opencode, pi, fx]
model_access: "API keys (DeepSeek, Anthropic, OpenCode Zen, OpenCode Go); subscription logins (ChatGPT, Grok via SuperGrok/X Premium+); any OpenAI Chat/Responses or Anthropic Messages endpoint incl. local Ollama/LM Studio/vLLM"
execution_env: "user host: the bot's assigned Runner, running as the user, no OS sandbox (Codex keeps its own sandbox; cloud sandbox for coding agents is an open PR)"
per_bot_computer: partial - each bot is pinned to one Runner (a user-owned desktop); isolation only by giving a bot a dedicated machine
persistent_bots: yes - named bots with description, model, Access, memory, Runner; lead bot "Chef"
memory: per-bot plain Markdown on the Runner (curated MEMORY.md in every prompt + topic notes + daily logs searched by recall); group "project context" separate
routines: yes - intervals/set times (min 5 min), one-time, PR watches and webhooks (relay-hosted receivers), Google Calendar-relative, self-run event gateway, model-free read-only pre-checks
group_chat: yes - 1-6 bots, sequential turn rounds with silent PASS, max 4 rounds, owner bot; message_bot durable handoffs across Runners, 8-hop loop cap
coding_workspace: partial - file/shell tools for bots; coding delegated to Claude Code/Codex/OpenCode/pi/fx with Cursor-style transcript, change counts, PR state; no diff viewer, worktree manager, or editor
browser_use: yes - Browser plugin (Chrome; headless or persistent per-bot profiles), take-over/return, record-a-workflow to skill
computer_use: no (none found)
connectors: MCP - curated marketplace (~50 plugins) + user mcp.json; plugin calls via "codemode" JS in QuickJS; named multi-accounts for Gmail/Calendar/Drive/Slack/Telegram
channels: Telegram and Slack (bot listens and replies in threads); Gmail/Slack drafts; no WhatsApp, iMessage, SMS, voice calls
mobile: yes - iOS/iPadOS (TestFlight beta), Android APK; phone is a full E2E Device but never a Runner
voice: partial - dictation only (Mac app, phone)
approvals: "per-bot Access (plugin levels, per-tool, files, shell) + per-action LLM Auto-review with plain-language rules and Allow once/Always/Deny cards; unattended runs queue for review"
e2e_encryption: yes - X25519/Ed25519 identity and machine keys, XChaCha20-Poly1305 account key with rotation on unpair, signed+sealed device-to-device envelopes; relay sees ciphertext and metadata, but hosted webhook receivers read plaintext
self_host: yes - relay is one binary (SQLite or Postgres, S3/R2/MinIO), Docker image; model catalog and marketplace URLs overridable
multi_user: no - single-person identity; bots shareable only as encrypted template links/files
pricing: free; no paid tier found; bring your own model accounts; hosted relay free (5 GiB default quota)
maturity: beta - one month old, iOS on TestFlight, single maintainer, relay protocol already at v4 with forced updates
```

## What it is

Lorca describes itself as "Imagine Telegram but single person, with agents, and end-to-end encrypted. Alternative to Grok bot, Muse, Dots" ([GitHub repo description](https://github.com/egoist/lorca)). The mental model is a messenger whose contacts are bots: each bot is "a teammate with one job" with a name, description, model, memory, and a Runner, the one computer it works on ([Bots docs](https://lorca.app/docs/bots)). The architecture doc states the target explicitly: "Lorca is a Grok Bot alternative: persistent named bots, 1:1 chats, group chats, handoff, and orchestration. Work runs on Devices you own" ([ARCHITECTURE.md](https://github.com/egoist/lorca/blob/main/ARCHITECTURE.md)). Many mechanisms are documented as copied "after Grok Bot" (room turns, coding agents, memory shape) ([bots.md](https://github.com/egoist/lorca/blob/main/docs/architecture/bots.md), [coding-agents.md](https://github.com/egoist/lorca/blob/main/docs/architecture/coding-agents.md)).

Target user: an individual (developer or power user) who wants Grok-Bot-style always-on teammates without a vendor cloud: bots run "on computers you own ... Nothing runs in someone else's cloud", with the user's own model accounts and a relay that "only ever holds ciphertext" ([Overview docs](https://lorca.app/docs)). There is no email or password; "Your backup phrase is your account" ([site FAQ strings, web/src/i18n/en.ts](https://github.com/egoist/lorca/blob/main/web/src/i18n/en.ts)).

## Product and UX

- **Onboarding:** install, choose Create / Restore / Pair; Create makes a key pair and shows a backup phrase of thirteen groups of four characters; name the lead bot; connect a provider; talk to Chef ([Get started](https://lorca.app/docs/get-started)).
- **Chef, the lead bot:** every account starts with Chef, a chief of staff that asks what you work on, proposes a small team of one-job bots, creates them on approval, then routes work. "Nothing about Chef is privileged" ([Overview docs](https://lorca.app/docs), [bots.md](https://github.com/egoist/lorca/blob/main/docs/architecture/bots.md#the-lead-bot)).
- **Messenger layout:** sidebar of DMs and groups with sections, pin/hide/mute, unread pills synced across devices; an inspector pane per chat holds profile, Access, model, limits, routines, channels, skills, plugins, memory, tasks, outputs ([Chats](https://lorca.app/docs/chats), [Bots](https://lorca.app/docs/bots)).
- **Working state is quiet:** tool calls are not shown in the transcript; a "shimmering line" says "Running command...", "Using GitHub..."; replies arrive per paragraph; cards appear only when the user must act ([Chats](https://lorca.app/docs/chats), [Tools](https://lorca.app/docs/tools)).
- **Steering:** a message sent mid-turn is queued and injected at the next safe boundary, with "Send now"; Stop ends the turn within about 15 s including handed-off work on other machines ([Chats](https://lorca.app/docs/chats#stop)).
- **Creating bots:** a sheet (name, description, Runner, provider/model, thinking) or by asking any bot; marketplace bots and workflows; templates from shared links ([Bots](https://lorca.app/docs/bots)).
- **Workflows:** a one-page outcome setup (questions, bot pick, account connections), then a mandatory **sample run** before the schedule is turned on; shipped packs are Meeting preparation, Inbox triage, Repository monitoring, Feedback collector ([Workflows](https://lorca.app/docs/workflows)).
- **Reviewing results:** outputs as versioned file/link cards with a self-reported check (Passed / Failed / Not verified); tasks end in "Ready for review" and never auto-complete from a reply; a cross-bot Attention list consolidates reviews, blockers, and commitments ([Chats: Outputs](https://lorca.app/docs/chats#outputs), [Tasks](https://lorca.app/docs/tasks)).
- **Distinctive:** native-feeling UI on all three desktops through EGOIST's own Go UI toolkit; bilingual English/Simplified Chinese apps and docs ([desktop-app.md](https://github.com/egoist/lorca/blob/main/docs/architecture/desktop-app.md), [languages.md](https://github.com/egoist/lorca/blob/main/docs/architecture/languages.md)).

## Architecture

**Three processes** ([ARCHITECTURE.md](https://github.com/egoist/lorca/blob/main/ARCHITECTURE.md)):

```
desktop app (Go, MyGo)  <-- ws://127.0.0.1:4862/ws, bearer serve-token -->  lorca CLI (Rust): keys, agent loop, tools
phone app (Expo)  -- embeds the same Rust core via UniFFI --.                        |
                                                            \                       | HTTPS + sync socket: signed requests,
                                                             `----------------->  Relay (Rust/axum, SQLite|Postgres, S3)
                                                                                    public keys + ciphertext only
```

- **CLI as service.** `lorca serve` binds `127.0.0.1:4862` (dev 4863), stores everything under `~/.lorca/`, and is the only component that talks to the relay and to model providers ([runtime.md](https://github.com/egoist/lorca/blob/main/docs/architecture/runtime.md)). Constraint 1: "The app speaks only to the local CLI over localhost websocket"; the app bundles the binary and starts it unless one already answers ([ARCHITECTURE.md](https://github.com/egoist/lorca/blob/main/ARCHITECTURE.md#constraints)). Headless Runners install the CLI by script and keep it alive with `lorca service install` (launchd agent, systemd user unit with lingering, Windows Run-key supervisor) ([runtime.md](https://github.com/egoist/lorca/blob/main/docs/architecture/runtime.md#updates-and-the-service)).
- **Local wire protocol.** JSON-RPC-like frames `{id, method, params}` / `{id, result}` and events `{event, data}` over `ws://127.0.0.1:4862/ws`. Requests carrying an `Origin` header or a non-loopback `Host` get 403 (defeats browser pages and DNS rebinding), and the upgrade requires `Authorization: Bearer <serve-token>` compared in constant time ([protocols.md](https://github.com/egoist/lorca/blob/main/docs/architecture/protocols.md#app--cli-local-ws)). Method families include `chats.*`, `bots.*`, `tasks.*`, `handoffs.*`, `reviews.*`, `workflows.*`, `playbooks.*`, `outputs.*`, `templates.*` (same doc).
- **Desktop app.** `desktop/` is Go on [MyGo](https://github.com/egoist/mygo) (EGOIST's MIT-licensed native-UI Go framework, 2,435 stars, created 2026-09-26), immediate-mode views, building for Windows, Linux, and Apple-silicon macOS; it replaces the AppKit app in `macos/`, which is deprecated ([README](https://github.com/egoist/lorca/blob/main/README.md), [desktop-app.md](https://github.com/egoist/lorca/blob/main/docs/architecture/desktop-app.md), [desktop/go.mod](https://github.com/egoist/lorca/blob/main/desktop/go.mod) pins `github.com/egoist/mygo v0.4.5`; the doc still says 0.3.6, minor doc drift).
- **Phone apps.** Expo (React Native, expo-router). The phone does not reimplement the protocol: `crates/mobile` wraps the `lorca` library (built without `runner` and `server` features) in a UniFFI object with three calls, `start`, `request(method, params)`, `wake`, exposed through a ~40-line Swift and Kotlin Expo module; events mirror the WebSocket frames into a zustand store ([phone-app.md](https://github.com/egoist/lorca/blob/main/docs/architecture/phone-app.md), [crates/mobile/Cargo.toml](https://github.com/egoist/lorca/blob/main/crates/mobile/Cargo.toml)). So every client speaks one JSON API (`crates/cli/src/api.rs`): desktop over localhost WS, phone in-process.
- **Agent loop (own).** `crates/agent` is "a port of pi-agent-core": same event sequence (`agent_start`, `turn_start`, `message_*`, `tool_execution_*`, `turn_end`, `agent_end`), steering and follow-up queues, `before_tool_call`/`after_tool_call`/`should_stop_after_turn` hooks, parallel or sequential tools, model catalog with rates, thinking levels, cost per message, compaction, turn-level retry, salvage of truncated tool-call JSON ([runtime.md](https://github.com/egoist/lorca/blob/main/docs/architecture/runtime.md#agent-loop), [docs/agent/](https://github.com/egoist/lorca/tree/main/docs/agent)). A turn is a decrypted Job; replies stream to the relay in paragraph-sized encrypted chunks so a paired phone watches it grow (same doc).
- **Delegation to external coding agents.** A bot's `coding_agent` tool starts Claude Code, Codex, OpenCode, pi, or Vercel's fx on the Runner, each over its native protocol: Claude Code `claude -p` stream-json (Agent SDK protocol) with a `PreToolUse` hook so every Bash call comes back to Lorca; Codex `codex app-server` JSON-RPC with `approvalPolicy: on-request`, `sandbox: workspace-write`; OpenCode `opencode acp` and fx `fx acp` over the Agent Client Protocol with `session/request_permission`; pi `pi --mode rpc` JSONL plus a Lorca-written extension that routes non-read tool calls to Lorca ([coding-agents.md](https://github.com/egoist/lorca/blob/main/docs/architecture/coding-agents.md#how-each-agent-runs)). The bot is deliberately a relay: it passes the user's request verbatim, adds no plan, and does not review the result; the agent picks its own branch/worktree and opens a PR, whose state Lorca polls via `gh pr view` every five minutes (same doc).
- **Codemode for plugins.** Bots call MCP tools by writing JavaScript run in a fresh QuickJS VM (`rquickjs`, 256 MiB heap, no network/fs/timers), so paged or filtered results never fill context; every call still passes Access and Auto-review ([plugins.md](https://github.com/egoist/lorca/blob/main/docs/architecture/plugins.md#codemode)). Tool schemas are loaded on demand per turn ([Plugins docs](https://lorca.app/docs/plugins#on-demand-tools)).
- **Models and auth.** Credentials belong to the account, not a device: API keys, ChatGPT and Grok OAuth tokens, and custom providers sync to every Device as one `credentials` blob encrypted with the account key; OAuth refreshes are published back so all Runners share tokens ([identity.md](https://github.com/egoist/lorca/blob/main/docs/architecture/identity.md#account-credentials)). Provider traffic goes directly from the Runner to the provider ([Security docs](https://lorca.app/docs/security#what-ai-providers-see)). Auto-review can use a separate small model or a "decision API" (TypeSafe System One, OpenAI Decisions) that returns probabilities ([Providers docs](https://lorca.app/docs/providers#decision-apis)).
- **Execution environment.** The Runner's host, as the user; "A bot with shell access can reach whatever your user can" and Access "is not a sandbox of the operating system" ([Security docs](https://lorca.app/docs/security#on-your-computer)). Open PR #259 (2026-10-19) adds optional Vercel Sandbox / Cloudflare Sandbox execution for coding agents with the user's own accounts ([PR #259](https://github.com/egoist/lorca/pull/259)).
- **State and storage.** Plaintext lives on Devices: `identity.json` (master secret, identity device only), `machine.json`, `credentials.json`, `mcp.json`, `lorca.sqlite3`, per-bot workspaces `~/.lorca/workspaces/<bot id>/` with memory; mode 0600 files ([runtime.md](https://github.com/egoist/lorca/blob/main/docs/architecture/runtime.md)). Sync is an append-only blob log on the relay with latest-only "slots" (`roster`, `credentials`, `machine-<key>`) and per-chat groups; an outbox re-uploads under the newest key ([identity.md](https://github.com/egoist/lorca/blob/main/docs/architecture/identity.md#relay-surface), [relay-trust.md](https://github.com/egoist/lorca/blob/main/docs/architecture/relay-trust.md#the-account-key)). Keychain storage is listed as "Next" ([status.md](https://github.com/egoist/lorca/blob/main/docs/architecture/status.md)).
- **Remote and mobile access.** No tunnels and no inbound ports: every Device holds an outbound sync socket to the relay; work for another machine is a sealed `job` envelope that waits up to seven days for an offline Runner ([relay.md](https://github.com/egoist/lorca/blob/main/docs/architecture/relay.md), [relay-trust.md](https://github.com/egoist/lorca/blob/main/docs/architecture/relay-trust.md#signed-envelopes)). Pushes go via APNs/FCM with encrypted content ([Phone app docs](https://lorca.app/docs/mobile#notifications)).
- **Extension surface.** MCP plugins from a remote marketplace index (`lorca.app/marketplace/v1.json`) and user `mcp.json` in Claude Desktop/Cursor format, with `toolExposure` filters "as pi does"; skills ("playbooks"); bot templates; event subscriptions via a Python gateway script; full CLI (`lorca tasks`, `lorca events`, `lorca mcp`, `lorca provider`) ([Plugins docs](https://lorca.app/docs/plugins#your-own-mcp-servers), [Relay docs](https://lorca.app/docs/relay#the-model-catalog-and-the-marketplace), [Events docs](https://lorca.app/docs/events)).

## Capabilities in detail

- **Persistent bots and identity.** Bot profile (name, description, SF Symbol/accent or encrypted avatar, provider/model/thinking, Access) lives in the encrypted roster; bots can create and edit each other (except Access) and move themselves between Runners ([bots.md](https://github.com/egoist/lorca/blob/main/docs/architecture/bots.md), [Bots docs](https://lorca.app/docs/bots#edit-a-bot)).
- **Devices and Runners (bots on other machines).** Any Device with `os` macos/linux/windows is a Runner; phones/tablets are Devices that hold keys and chats but never run bots, and Runner status is derived from `os` inside an encrypted blob so the relay is not told it ([identity.md](https://github.com/egoist/lorca/blob/main/docs/architecture/identity.md#devices-and-runners)). Creating a bot for Runner B from Device A writes the profile into the roster and pins B; turns become job envelopes sealed to B, which runs the loop with the account's credentials and uploads encrypted replies; on B the bot uses B's working directory, plugins, coding agents, browser profiles, secrets, and memory ([bots.md](https://github.com/egoist/lorca/blob/main/docs/architecture/bots.md#a-bot-on-another-runner)). Moving a bot leaves memory, secrets, limits, and browser sign-ins on the old disk ([Devices docs](https://lorca.app/docs/devices#restore-on-another-computer), [Limits docs](https://lorca.app/docs/limits)). Any Device can trigger signed self-updates of a headless Runner's CLI ([runtime.md](https://github.com/egoist/lorca/blob/main/docs/architecture/runtime.md#updates-and-the-service)).
- **Group chats.** 1-6 bots (possibly on different Runners). The Device that received the user message runs the room: each member gets a `room_turn` Job with the transcript plus a cue, in chat order with mentioned bots first; it replies or answers `PASS` (never shown); another round runs only for members that heard something new; the exchange ends after a silent round or round four ([bots.md](https://github.com/egoist/lorca/blob/main/docs/architecture/bots.md#the-lead-bot), [Group chats docs](https://lorca.app/docs/group-chats#how-turns-work)). Each group has an owner bot, a description, and a shared Project (brief, goals, constraints, decisions, facts, links, files) with bot-suggested entries the user accepts and link freshness checks ([Group chats docs](https://lorca.app/docs/group-chats#the-project)).
- **Bot-to-bot handoff.** `message_bot { bot_id, message, context?, expected_output?, acceptance_criteria?, task_id? }` creates a durable `handoff-<UUID>` contract stored encrypted in SQLite and delivered as a sealed job; it lands in the target's DM as "Message from", is re-injected into every turn's system prompt so compaction cannot drop it, and the result (completed/failed/blocked/cancelled with evidence) returns to the requesting chat and wakes the requester with a `handoff_result` job. Follow-up, cancel, restart recovery, and an eight-hop cap without user input are built in; bots cannot side-message members of their current group ([handoffs.md](https://github.com/egoist/lorca/blob/main/docs/architecture/handoffs.md), [Chats docs](https://lorca.app/docs/chats#bots-that-message-each-other)).
- **Tasks vs routines vs workflows.** *Tasks* are durable multi-turn work items (goal, owner bot, next step, "done when" checks, dependencies, evidence, limits) that end in "Ready for review" and need explicit Mark Complete ([Tasks docs](https://lorca.app/docs/tasks)). *Routines* are a bot's scheduled or triggered runs in its DM: intervals/times with IANA timezone and missed-run policy, one-time, PR watches, webhooks, calendar-relative, plus optional model-free read-only checks so "a quiet hour costs nothing"; routines auto-pause after seven days without user activity ([Routines docs](https://lorca.app/docs/routines)). *Workflows* are marketplace packs that set up bot + accounts + paused routines and require a sample run before enabling ([Workflows docs](https://lorca.app/docs/workflows)).
- **Memory.** Per bot under `~/.lorca/workspaces/<bot id>/`: `MEMORY.md` (first 200 lines or 24 KB in every system prompt; edited only via `memory_update` append/replace/supersede/remove with dated entries and strike-through history), `memory/<topic>.md` notes, and `memory/log/YYYY-MM-DD.md` diaries never loaded but searchable with `recall`; all writes pass a credential scrubber; pre-compaction memory flush; cross-chat recency brief of the last two days ([bots.md](https://github.com/egoist/lorca/blob/main/docs/architecture/bots.md#memory), [Memory docs](https://lorca.app/docs/memory)).
- **Skills and feedback.** Skills (slug, description, instructions, examples, references, scripts) per bot or per group, progressive disclosure (name/description every turn), "Save as Skill" from chosen messages, versions, export; a built-in `lorca` skill points bots at the docs ([Skills docs](https://lorca.app/docs/skills)). Feedback on replies yields suggested diffs to routine prompts or skills that the user accepts; suggestions can never change schedules, Access, or limits ([Feedback docs](https://lorca.app/docs/feedback)).
- **Plugins.** MCP-based, installed per Runner; marketplace categories span productivity, communication, code, data, finance, plus Chinese services (Feishu, Dida365, Tencent Docs, Zhihu, Amap); Google services require the user's own OAuth client ([Plugins docs](https://lorca.app/docs/plugins)).
- **Browser.** Chrome, headless by default; named per-bot profiles keep sign-ins on the Runner; Take Over / Return to Bot for captchas and 2FA; Record turns a demonstrated task into a skill that halts with a screenshot on a mismatched step ([Browser docs](https://lorca.app/docs/browser)).
- **Coding workspace.** Bots have read/write/edit/grep/find/ls and a PTY shell with background commands, answerable prompts, and a Running tasks list ([Tools docs](https://lorca.app/docs/tools)); heavy coding is delegated to external agents with a Cursor-style transcript page and PR status ([Coding agents docs](https://lorca.app/docs/coding-agents)). No built-in diff viewer or file tree today; open PR #257 adds a working-folder git changes view ([GitHub PRs list via API, #257](https://github.com/egoist/lorca/pull/257)).
- **Channels.** A bot listens on Telegram (BotFather token) or Slack (Socket Mode app) in user-allowed chats only; each thread becomes a conversation in Lorca; outsiders' text is information, never instruction; failures hold the queue ([Channels docs](https://lorca.app/docs/channels)). Emails and Slack messages are drafts by default ([Access docs](https://lorca.app/docs/access)).
- **Secrets.** Requested on a card, sealed to the Runner, stored in `secrets.enc` encrypted with the account DEK, used by name (browser autofill on a matching HTTPS site, env var for commands/coding agents, plugin field), and replaced by placeholders in tool output before the model sees it ([Secrets docs](https://lorca.app/docs/secrets), [secrets.md](https://github.com/egoist/lorca/blob/main/docs/architecture/secrets.md)).
- **Limits.** Spend, tokens, run time, retries, plugin calls per DM/task/routine, plus shared per-account plugin rate limits (60/min, 4 concurrent default) ([Limits docs](https://lorca.app/docs/limits)).
- **Voice, mobile, team.** Dictation only ([Chats docs](https://lorca.app/docs/chats#dictation)); the phone does nearly everything except run bots, whole-turn Stop, and memory editing ([Phone app docs](https://lorca.app/docs/mobile)); no multi-user accounts; sharing is via bot templates ([Share a bot](https://lorca.app/docs/templates)).

## Security and trust model

**Key hierarchy** ([identity.md](https://github.com/egoist/lorca/blob/main/docs/architecture/identity.md), [README](https://github.com/egoist/lorca/blob/main/README.md)):

| Layer | Primitive | Where it lives |
| --- | --- | --- |
| Master secret | 32 random bytes; backup = base32 phrase, 13 groups of 4 | `~/.lorca/identity.json` (0600), only on the identity device (the one that created/restored); phones never hold it |
| Identity signing key | Ed25519, HKDF from master; identity id = hash(pubkey) | private local; public on relay |
| Content keypair | X25519, HKDF from master | seals the account key for restore |
| Account key (DEK) | random XChaCha20-Poly1305 key, in signed generations | on every paired Device; on relay only sealed (to content key and per-device box keys) inside an identity-signed keyring |
| Machine keypair | per-device secret -> HKDF -> Ed25519 signing + X25519 box | `machine.json`; public keys on relay, attested by identity or the pairing device |
| Envelopes | Ed25519-signed by sender machine, `crypto_box_seal` to recipient box key | relay, deleted after consumption or 7 days |
| Push key | HKDF from newest account key | every Device; iOS notification extension keychain |

AEAD blobs are `nonce(24) || ciphertext` with the blob kind as associated data ([identity.md](https://github.com/egoist/lorca/blob/main/docs/architecture/identity.md)). The design is explicitly "after Happy's security model" ([ARCHITECTURE.md](https://github.com/egoist/lorca/blob/main/ARCHITECTURE.md), [Happy security](https://happy.engineering/docs/security/)).

**Relay auth.** Challenge-response: the relay issues a nonce, the device checks it looks like a 16-128 char base64url nonce (so a malicious relay cannot get it to sign an envelope prefix), signs it, and receives a one-hour HMAC bearer; identity-level writes are payloads signed by the identity key ([relay.md](https://github.com/egoist/lorca/blob/main/docs/architecture/relay.md), [relay-trust.md](https://github.com/egoist/lorca/blob/main/docs/architecture/relay-trust.md#what-the-machine-key-signs)).

**Device pairing.** Device A shows `lorca://pair?relay=...&id=<identity pubkey>&ek=<ephemeral X25519 pubkey>&n=<nonce>` as QR/string (10-minute TTL). Device B seals its machine key, box key, name, os, and a random reply key to `ek` and posts it to an unauthenticated relay mailbox. A unseals it, attests B on the relay, and replies with identity and content public keys, the account DEK plus keyring, and relay URL, encrypted under B's reply key (XChaCha20-Poly1305, AD `pair-reply`). B checks the identity pubkey against the string's `id`. Because `ek` and `id` travel out-of-band in the QR/string, the relay can neither read the request nor forge an acceptable reply ([identity.md](https://github.com/egoist/lorca/blob/main/docs/architecture/identity.md#pairing-a-device), [relay-trust.md](https://github.com/egoist/lorca/blob/main/docs/architecture/relay-trust.md#pairing)). Any paired computer can pair others; phones only join.

**Device-to-device work.** Jobs, cancellations, results, and requests are envelopes `{identity, kind, from, to, id, at, body}` signed over `lorca/envelope/v1\0 || json` and sealed to the recipient. The recipient checks identity, kind, recipient, that the sender is a known non-unpaired Device (box keys come only from encrypted `machine` blobs, never from the relay's list), the signature, a freshness window (1 h for questions, 8 days for jobs), and replay via a persistent `opened_envelopes` table. A job runs only if `requested_by` equals the signer ([relay-trust.md](https://github.com/egoist/lorca/blob/main/docs/architecture/relay-trust.md#signed-envelopes)). Added in Mac app 1.0.12: "a relay can no longer send work to your Runners in another Device's name" ([CHANGELOG.md](https://github.com/egoist/lorca/blob/main/CHANGELOG.md)).

**Unpairing and key rotation.** Any Device can unpair any other; the relay revokes the key forever (`revoked_machines`, 410 Gone), peers record it in a local `unpaired_machines` table so a relay cannot resurrect it, and the identity device mints a new account-key generation (identity-signed keyring) distributed to all but the unpaired device; the unpaired device keeps read access to old history only ([relay-trust.md](https://github.com/egoist/lorca/blob/main/docs/architecture/relay-trust.md#the-account-key), [Security docs](https://lorca.app/docs/security#unpairing)).

**Exactly what the relay can see** ([identity.md: Relay surface](https://github.com/egoist/lorca/blob/main/docs/architecture/identity.md#relay-surface), [Security docs](https://lorca.app/docs/security#what-the-relay-sees)):
- Identity, content, machine signing and box public keys, and who attested each machine.
- Blob ids, kinds (e.g. message, file, roster, credentials, job, event), sequence numbers, timestamps, sizes; the slot name (random message id, `roster`, `credentials`, `machine-<pubkey>`, `read-<chat id>`); the group id (random chat id) for messages, read marks, attachments; deleted chat ids.
- The recipient machine key on every envelope; presence (which keys are connected, last connect/disconnect); phone APNs/FCM tokens; pairing mailboxes.
- Not visible: names, titles, messages, files, bot profiles, routines, credentials, device names and `os`, push contents (Apple/Google see only "New reply") ([Phone app docs](https://lorca.app/docs/mobile#notifications)).

**What the relay can do.** It can withhold any blob, deliver an older account blob again (rollback of roster or a message version), or hold back the newest keyring from a restoring device; it cannot write an account blob (needs the newest DEK) or forge device envelopes ([relay-trust.md](https://github.com/egoist/lorca/blob/main/docs/architecture/relay-trust.md#what-the-relay-decides)). Documented residual gaps: rotation waits for the identity device to come online; an unpaired device can, with relay help, inject old-key messages into the history a later-paired device reads or swap attachment bytes lacking a `sha256`; unpairing the identity device itself does not cut it off, only a new identity does (same doc).

**The plaintext exceptions.**
- *Hosted receivers:* GitHub App PR watches and routine webhooks on `relay.lorca.app` read each request in memory, verify it (GitHub HMAC or webhook key), seal it to the Runner, and keep only ciphertext plus per-subscription metadata: identity, Runner machine key, subject (e.g. `acme/project#42`), webhook-key hash, GitHub installation id, PR head commit, and the subscription signing secret, which lets the relay forge events for that subscription only ([receivers.md](https://github.com/egoist/lorca/blob/main/docs/architecture/receivers.md), [Security docs](https://lorca.app/docs/security#webhooks)). Users who distrust this run their own gateway ([Events docs](https://lorca.app/docs/events)).
- *Shared bot links:* encrypted with a per-link key in the URL fragment; the lorca.app page decrypts in the browser ([Security docs](https://lorca.app/docs/security#shared-links)). [INFERENCE] Whoever controls the JavaScript lorca.app serves could exfiltrate the fragment key, the standard web-E2E caveat; `.lorca-template` files are unencrypted.
- *Model providers* see the conversation, description, and tool results in plaintext, with saved secrets replaced by names ([Security docs](https://lorca.app/docs/security#what-ai-providers-see)).
- *Metadata analysis* [INFERENCE]: envelope recipient keys, timing, and sizes likely let a relay operator infer which devices run bots and when, even though `os` is encrypted.

**Self-hosting the relay.** `lorca-relay --bind 0.0.0.0:8787 --db lorca-relay.db` (or `postgres://` for multi-process zero-downtime deploys), behind an HTTPS reverse proxy with `--trust-proxy`; options for quotas (5 GiB default), S3/R2/MinIO attachments, `--min-protocol`, inactivity deletion (365 days), rate limits, Prometheus metrics, APNs/FCM keys, and an optional own GitHub App for PR watches; Dockerfile and Railway notes provided. Set the relay URL on the first device before pairing; later devices learn it from the pairing code ([Relay docs](https://lorca.app/docs/relay#run-your-own-relay), [relay.md](https://github.com/egoist/lorca/blob/main/docs/architecture/relay.md)). [INFERENCE] Pushes to the store-distributed iOS/Android apps need Lorca's own APNs/FCM credentials, so self-hosters likely get no phone pushes without building their own app.

**On-device permissions.** Access (per-bot plugin levels, per-tool checkboxes, files read/write/none, shell on/off; only the user can change it) is checked before Auto-review and again at call time ([Access docs](https://lorca.app/docs/access), [bot-permissions.md](https://github.com/egoist/lorca/blob/main/docs/architecture/bot-permissions.md#execution-boundary)). Auto-review: read-only commands (parsed stage by stage) and read-only plugin calls run at once; other actions are judged by a review model against user rules and the latest user request; cards offer Allow once / Always allow (adds a plain-language rule) / Deny; unattended runs queue actions for later approval ([Auto-review docs](https://lorca.app/docs/auto-review)). As of Mac 1.0.17, "Auto-review allows an action by default, and holds only one it can name a rule for" ([CHANGELOG.md](https://github.com/egoist/lorca/blob/main/CHANGELOG.md)). The docs are candid that the real boundary is the machine: shell runs as the user and "can reach anything you can, whatever the Files setting says" ([Access docs](https://lorca.app/docs/access)). The homepage FAQ understates this ("run commands in the folder you give it") ([web/src/i18n/en.ts](https://github.com/egoist/lorca/blob/main/web/src/i18n/en.ts)).

**Other.** Master secret and credentials are 0600 files, not keychain (open point) ([status.md](https://github.com/egoist/lorca/blob/main/docs/architecture/status.md)). CLI self-updates verify an Ed25519-signed manifest; the macOS app is signed and notarized ([runtime.md](https://github.com/egoist/lorca/blob/main/docs/architecture/runtime.md#updates-and-the-service), [Security docs](https://lorca.app/docs/security#updates)). Telemetry: no analytics/crash-reporting SDK found in `crates/cli/src` or `crates/relay/src` by keyword search (posthog/sentry/telemetry/analytics); devices do fetch the model catalog and marketplace from lorca.app ([Relay docs](https://lorca.app/docs/relay#the-model-catalog-and-the-marketplace)). Known incidents or published advisories: none found.

## Traction and momentum

- GitHub (as of 2026-10-20): 316 stars, 31 forks, 54 open issues+PRs, created 2026-09-18, pushed 2026-10-20 ([GitHub API](https://api.github.com/repos/egoist/lorca)).
- Commits: ~456 total in 32 days (~14/day); at least 100 in the week 2026-10-06..12 and 50 since 2026-10-13 ([commits API](https://api.github.com/repos/egoist/lorca/commits)). In the latest 100 commits, 32 carry "Co-authored-by: Claude Opus 5.5" and 62 are release bot commits; PR #259 is labeled "Generated with Claude Code" ([PR #259](https://github.com/egoist/lorca/pull/259)). Effectively a solo, AI-assisted build.
- Contributors: egoist (419 commits), github-actions[bot] (36), imgbot (1) ([contributors API](https://api.github.com/repos/egoist/lorca/contributors)). Of the last 100 issues/PRs, 95 are by egoist and only 4 by 3 outside users (several in Chinese) ([issues API](https://api.github.com/repos/egoist/lorca/issues?state=all)).
- Releases: 44 GitHub releases between 2026-09-24 and 2026-10-16: 19 `cli-v`, 17 `desktop-v` (0.1.0 on 2026-10-01), 8 `mobile-v` (1.0.0 on 2026-10-09) ([releases API](https://api.github.com/repos/egoist/lorca/releases)). The AppKit Mac app shipped separately via Sparkle up to 1.0.17 and has stopped self-updating in favor of the desktop app ([CHANGELOG.md](https://github.com/egoist/lorca/blob/main/CHANGELOG.md)).
- Code size (main, 2026-10-20, line counts): Rust ~112k, Go desktop ~56k, deprecated Swift ~46k, phone TS/TSX ~25k [measured from a shallow clone before the clone was removed].
- Press: none found; search results surface only the repo and docs.
- Business model: free; no pricing page, paid tier, or account system found on lorca.app or in the site strings; users pay their own model providers and the hosted relay is free with a 5 GiB quota ([lorca.app](https://lorca.app/), [Relay docs](https://lorca.app/docs/relay)). Maker context: EGOIST (github.com/egoist, 13.6k followers, China; author of tsup 11.3k stars, poi, docute) lists himself as "CEO of ChatWise.app", company Umida Inc. ([GitHub profile](https://github.com/egoist)); ChatWise is a local-first BYO-key AI chat desktop app supporting subscription logins and MCP ([chatwise.app](https://chatwise.app/)); he also built MyGo (the UI toolkit) during the Lorca sprint ([mygo repo](https://github.com/egoist/mygo)). [INFERENCE] Lorca is likely a funnel/brand play or future paid product for Umida; monetization intent is unknown.

## Strengths

- The most rigorous E2E design in the open-source Grok Bot clone set: signed, sealed, replay-protected envelopes, key rotation on unpair, an explicit and honest relay-trust doc listing residual attacks ([relay-trust.md](https://github.com/egoist/lorca/blob/main/docs/architecture/relay-trust.md)).
- True multi-machine runtime: any paired desktop is a Runner, bots can be created, moved, and steered from a phone, and offline Runners pick up queued work ([bots.md](https://github.com/egoist/lorca/blob/main/docs/architecture/bots.md#a-bot-on-another-runner)).
- One Rust core reused everywhere (CLI, phone via UniFFI), so protocol and crypto are not reimplemented per client ([phone-app.md](https://github.com/egoist/lorca/blob/main/docs/architecture/phone-app.md)).
- Deep Grok-Bot parity: rooms with silent PASS, durable handoffs, tasks with evidence, attention briefs, routines with model-free checks, workflows with sample runs, skills from chats, feedback-driven prompt diffs.
- Broad model access including SuperGrok/X Premium+ and ChatGPT subscription OAuth, local models, and decision-API reviewers ([Providers docs](https://lorca.app/docs/providers)).
- Documentation discipline: one subject doc per mechanism, size-budgeted and link-checked by `bun run check:docs` ([AGENTS.md](https://github.com/egoist/lorca/blob/main/AGENTS.md)).

## Weaknesses and risks

- **GPL-3.0-only licensing.** Any distributed product that incorporates or links Lorca code (including the Rust core in a mobile app) must ship complete corresponding source under GPL-3.0 to its recipients ([LICENSE](https://github.com/egoist/lorca/blob/main/LICENSE), [GPL-3.0 text](https://www.gnu.org/licenses/gpl-3.0.html), [GPL FAQ](https://www.gnu.org/licenses/gpl-faq.html)); the FSF has argued that Apple's App Store terms conflict with the GPL ([FSF, 2010](https://www.fsf.org/news/2010-05-app-store-compliance)), so a GPL-derived iOS app is legally awkward for anyone but the copyright holder [INFERENCE]. It is GPL, not AGPL, so running a modified relay as a network service does not by itself require publishing source [INFERENCE]. For Memoshi: study the designs and docs, do not copy code; MyGo (MIT) and Happy (MIT) are separately licensed ([mygo](https://github.com/egoist/mygo), [slopus/happy](https://github.com/slopus/happy)).
- **No OS sandbox.** Bots and their coding agents run as the user; isolation relies on an LLM reviewer whose default flipped to allow-by-default in 1.0.17 ([Auto-review docs](https://lorca.app/docs/auto-review), [CHANGELOG.md](https://github.com/egoist/lorca/blob/main/CHANGELOG.md)).
- **Bus factor of one** and extreme churn: relay protocol already at v4 with forced updates; the Mac UI was rewritten within a month ([relay-trust.md](https://github.com/egoist/lorca/blob/main/docs/architecture/relay-trust.md#signed-envelopes)).
- **Key custody is fragile:** single backup phrase, no recovery, master secret in a plain 0600 file; rotation needs the identity device online ([Security docs](https://lorca.app/docs/security)).
- **Runner-bound state:** memory, secrets, limits, browser sign-ins do not follow a bot that moves; a lost disk loses memory ([Devices docs](https://lorca.app/docs/devices)).
- **Runners must stay on** for routines; no hosted execution option (cloud sandboxes only for coding agents, still a PR) ([Routines docs](https://lorca.app/docs/routines), [PR #259](https://github.com/egoist/lorca/pull/259)).
- **Setup friction:** Google services need a self-made OAuth client; Slack needs a self-made app; Telegram needs BotFather ([Plugins docs](https://lorca.app/docs/plugins)).
- Single-person only; no households or teams.
- Marketing copy understates shell reach compared to the docs.

## Ideas worth taking for Memoshi

- **Device/Runner split derived from OS, hidden from the relay**: simple mental model for "which machine does the work" and phones as pure controllers.
- **Signed + sealed envelopes with replay tables and `requested_by == signer`**: makes a relay unable to inject work; adopt as baseline for any remote execution.
- **Account-key generations rotated on unpair, signed keyring**: concrete revocation story users can understand.
- **Out-of-band ephemeral key in the pairing QR**: relay-blind pairing without accounts.
- **One core library across CLI and mobile (UniFFI)**: avoids divergent crypto/protocol implementations.
- **Localhost WS hardening (reject `Origin`, check `Host`, bearer token file)**: cheap and blocks browser-to-localhost attacks.
- **Silent PASS group rounds with round cap and new-information gating**: keeps multi-bot rooms from being noisy.
- **Handoff contracts (expected output, acceptance criteria, evidence) re-injected each turn**: survives compaction and makes delegation auditable.
- **Model-free read-only pre-checks for routines** and **auto-pause after 7 days of user inactivity**: direct cost control.
- **Workflow sample run before enabling a schedule**: trust-building onboarding pattern.
- **Coding agents as peers over their native protocols (stream-json, app-server JSON-RPC, ACP, pi RPC) with every tool call routed back for review**: a pattern to copy rather than wrapping terminals.
- **Codemode (QuickJS sandbox) for MCP calls**: keeps bulky tool results out of context.
- **Secrets by name with output scrubbing** and **credential scrubber on memory writes**.
- **Avoid**: an LLM-only permission boundary on an unsandboxed host; Memoshi should pair review with real isolation (per-bot VM/container).

## Open questions

- Monetization plans for Lorca and its relation to ChatWise/Umida: ask the maker or watch lorca.app for pricing.
- Actual user count and hosted-relay load: only the operator's `/metrics` would show it; App Store/TestFlight numbers unknown.
- Whether the iOS app will ship on the App Store under GPL-3.0 and how (sole copyright holder can dual-license) [INFERENCE]; watch releases.
- Independent security review of the crypto: none found; one would audit `crates/cli/src/envelope.rs`, `keys.rs`, `pairing.rs`, `sync.rs`.
- Whether the iOS/Android builds can receive pushes from a self-hosted relay: test with a self-hosted relay.
- Whether the cloud sandbox PR (#259) merges and whether routines/bots themselves will get hosted runners.

## Sources

1. https://github.com/egoist/lorca (repo, description)
2. https://github.com/egoist/lorca/blob/main/README.md
3. https://github.com/egoist/lorca/blob/main/ARCHITECTURE.md
4. https://github.com/egoist/lorca/blob/main/AGENTS.md
5. https://github.com/egoist/lorca/blob/main/docs/architecture/identity.md
6. https://github.com/egoist/lorca/blob/main/docs/architecture/relay-trust.md
7. https://github.com/egoist/lorca/blob/main/docs/architecture/relay.md
8. https://github.com/egoist/lorca/blob/main/docs/architecture/receivers.md
9. https://github.com/egoist/lorca/blob/main/docs/architecture/protocols.md
10. https://github.com/egoist/lorca/blob/main/docs/architecture/runtime.md
11. https://github.com/egoist/lorca/blob/main/docs/architecture/coding-agents.md
12. https://github.com/egoist/lorca/blob/main/docs/architecture/bots.md
13. https://github.com/egoist/lorca/blob/main/docs/architecture/handoffs.md
14. https://github.com/egoist/lorca/blob/main/docs/architecture/plugins.md
15. https://github.com/egoist/lorca/blob/main/docs/architecture/secrets.md
16. https://github.com/egoist/lorca/blob/main/docs/architecture/bot-permissions.md
17. https://github.com/egoist/lorca/blob/main/docs/architecture/phone-app.md
18. https://github.com/egoist/lorca/blob/main/docs/architecture/desktop-app.md
19. https://github.com/egoist/lorca/blob/main/docs/architecture/languages.md
20. https://github.com/egoist/lorca/blob/main/docs/architecture/status.md
21. https://github.com/egoist/lorca/tree/main/docs/agent
22. https://github.com/egoist/lorca/blob/main/CHANGELOG.md
23. https://github.com/egoist/lorca/blob/main/LICENSE
24. https://github.com/egoist/lorca/blob/main/desktop/go.mod
25. https://github.com/egoist/lorca/blob/main/crates/mobile/Cargo.toml
26. https://github.com/egoist/lorca/blob/main/web/src/i18n/en.ts
27. https://github.com/egoist/lorca/pull/259
28. https://github.com/egoist/lorca/pull/257
29. GitHub API (as of 2026-10-20): https://api.github.com/repos/egoist/lorca , /releases , /contributors , /commits , /issues?state=all
30. https://lorca.app/
31. https://lorca.app/docs
32. https://lorca.app/docs/get-started
33. https://lorca.app/docs/bots
34. https://lorca.app/docs/chats
35. https://lorca.app/docs/group-chats
36. https://lorca.app/docs/tasks
37. https://lorca.app/docs/routines
38. https://lorca.app/docs/workflows
39. https://lorca.app/docs/memory
40. https://lorca.app/docs/skills
41. https://lorca.app/docs/feedback
42. https://lorca.app/docs/templates
43. https://lorca.app/docs/tools
44. https://lorca.app/docs/plugins
45. https://lorca.app/docs/browser
46. https://lorca.app/docs/coding-agents
47. https://lorca.app/docs/channels
48. https://lorca.app/docs/secrets
49. https://lorca.app/docs/access
50. https://lorca.app/docs/auto-review
51. https://lorca.app/docs/limits
52. https://lorca.app/docs/devices
53. https://lorca.app/docs/providers
54. https://lorca.app/docs/mobile
55. https://lorca.app/docs/security
56. https://lorca.app/docs/relay
57. https://lorca.app/docs/events
58. https://github.com/egoist (maker profile)
59. https://github.com/egoist/mygo
60. https://chatwise.app/
61. https://happy.engineering/docs/security/ (design ancestor, cited by Lorca)
62. https://github.com/slopus/happy (license check)
63. https://www.gnu.org/licenses/gpl-3.0.html
64. https://www.gnu.org/licenses/gpl-faq.html
65. https://www.fsf.org/news/2010-05-app-store-compliance
