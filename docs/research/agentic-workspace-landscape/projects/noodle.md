# Noodle

> A free, Apache-2.0, native Swift macOS messenger in which persistent "bots" (each wrapping a coding-agent CLI you already pay for, or a local model) live as contacts and group-chat members. Companion apps add VMs, signed-in browsers, agent-built mini-apps, an iOS client, and a "Hub" that lends your subscriptions to family or friends. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

Disambiguation: two unrelated projects share the name. [poteto/noodle](https://github.com/poteto/noodle) ("Orchestrate agents using skills", MIT, 517 stars, last push 2026-03-19) is a skill-driven coding-agent scheduler. [noodle-run/noodle](https://github.com/noodle-run/noodle) ("Rethinking Student Productivity", AGPL-3.0, 12,173 stars, last push 2024-10-17) is a student productivity web app. Star counts are from the GitHub API as of 2026-10-20.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Noodle
slug: noodle
category: oss-bot-roster-desktop
maker: "pdp (GitHub pdparchitect; CBK.AI / ChatBotKit, London)"
license: Apache-2.0
repo: https://github.com/pdparchitect/noodle
website: https://usenoodle.app
first_public: 2026-09-05      # repo created 2026-09-04T22:51Z; first release v0.3.0 published 2026-09-05
latest_release: "Noodle 0.69.1, 2026-10-19 (Hub 0.36.1 same day)"
release_cadence: "~1.8 main-app releases/day (81 tagged releases in 45 days); 316 release objects across 6 apps"
stars: 179 (as of 2026-10-20)
forks: 21 (as of 2026-10-20)
contributors: "5 incl. 1 bot; owner authored 1,610 of ~1,647 commits (as of 2026-10-20)"
primary_language: Swift
stack: "Swift 6 / SwiftUI, macOS 26+ (Apple silicon DMGs), Tuist, Sparkle 2.9.4, signed XPC Agent Host + Seatbelt, MLX (mlx-swift-lm) + Apple Foundation Models, MCP swift-sdk 0.12.1, Network.framework QUIC (Hub), CloudKit, LiveKit WebRTC build (calls)"
platforms: [macos, ios]
agent_engine: "wraps CLIs (7 vendor harnesses over app-server JSON-RPC / stream-JSON / ACP / MSP) + own loop for Apple Foundation Models, MLX and OpenAI-compatible models"
engines_supported: [codex, claude-code, vercel-fx, grok-build, muse-code, opencode-v2, antigravity, apple-intelligence, mlx-local, ollama, openai-compatible-api]
model_access: "subscription logins (ChatGPT, Claude.ai, Grok, Meta, Google, Vercel) via each CLI; API keys (OpenAI, OpenRouter, Vercel AI Gateway, custom); local models (Apple on-device, MLX Qwen/Gemma/gpt-oss/Llama, Ollama, TensorFold); lent subscriptions via Hub"
execution_env: "user host: Seatbelt-sandboxed per-bot workspace by default, or unrestricted as the user; optional Noodle Computer VMs (Linux, Windows 11 Arm), separate macOS account, or SSH host"
per_bot_computer: "partial: opt-in Noodle Computer VMs, assignable to one or several bots"
persistent_bots: "yes: name, avatar, backstory, public description, voice, own workspace folder and history"
memory: "markdown files in the bot workspace (memory.md, preferences.md, assignments.md) maintained by the bot, plus generated AGENTS.md; harness session resume"
routines: "heartbeats (default every 30 min), bot-scheduled one-off and repeating wake-ups (min 5 min interval), standing assignments; no webhooks found"
group_chat: "yes: multi-bot groups with shared goal, @mentions, mixed harnesses, cross-group routing rules"
coding_workspace: "partial: per-bot folder, shared folders, .patch/.diff review UI; no built-in editor, terminal pane or worktree manager found"
browser_use: "yes: Noodle Browser (persistent signed-in profiles, click/type/upload/screenshot, WebMCP-style site tools experimental)"
computer_use: "partial: terminal and files in VMs; agents cannot click or type on Local Mac or Windows desktops"
connectors: "MCP (remote OAuth services, catalog incl. Google Workspace, Pipedream, Krea), native macOS tools (Calendar, Reminders, Maps, OCR, image gen), ChatGPT Apps / Claude.ai connectors toggle"
channels: "own Mac app and iOS app only; Spotlight/Shortcuts/Services 'Send to Agent'; no Telegram/Slack/WhatsApp found"
mobile: "iOS 26 TestFlight beta (Noodle Mobile), connects to a Hub or to your Mac acting as a personal Hub"
voice: "on-device transcription of voice messages; live voice calls only for Codex bots (audio goes to OpenAI)"
approvals: "no approval UI: harness tool requests are auto-approved inside the bot's sandbox; access mode (restricted/unrestricted, Apps) is the control"
e2e_encryption: "partial: device-Hub link is QUIC + TLS 1.3 with pinned P-256 keys, no relay; data is plaintext at rest on the Hub Mac"
self_host: "yes: everything runs on user Macs; no Noodle cloud backend (CloudKit only for push and space sync)"
multi_user: "yes: Noodle Hub users, plans that lend harnesses, admins, shared bots"
pricing: "free; users pay their own model providers"
maturity: "beta: 0.x versions, ~6 weeks old, mostly one author, iOS app on TestFlight, several features marked experimental"
```

## What it is

Noodle presents agents as contacts in a native messenger. Each bot has a name, backstory, workspace and history, runs on a [harness](https://github.com/pdparchitect/noodle/blob/main/docs/harness-setup.md) the user chooses with an existing account, and can join groups that work toward a shared goal ([README](https://github.com/pdparchitect/noodle/blob/main/README.md)). The website pitches "Personal AI agents that get things done on your Mac. Add a Hub to share subscriptions and local models with your household or team" ([usenoodle.app](https://usenoodle.app/)). Earlier taglines were "Meet your AI team" and "Chat and work with your AI agents in one native macOS messenger" (third-party: [search-index snippets](https://usenoodle.app/)). The current GitHub description is "Personal AI agents." ([GitHub API](https://github.com/pdparchitect/noodle)).

Target user: Apple-ecosystem individuals and households who already pay for ChatGPT, Claude, Grok, Meta or Google plans and want always-available assistants with no new account ("Noodle doesn't sell you a model", [website](https://usenoodle.app/)). The README positions Noodle against Grok Bot and Meta Muse on four points: bring-your-own harness, open source, native rather than HTML UI, and local data and computers. That comparison table is the maker's own, not a neutral source ([README "How Noodle compares"](https://github.com/pdparchitect/noodle/blob/main/README.md)).

The product is a suite of independently versioned apps ([README Apps table](https://github.com/pdparchitect/noodle/blob/main/README.md)):

| App | Role | Min OS |
| --- | --- | --- |
| Noodle | Messenger and agent runtime | macOS 26 |
| Noodle Computer | Linux/Windows VMs, a separate local macOS account, or SSH hosts for agents | macOS 26 (Windows needs 27) |
| Noodle Browser | Persistent signed-in browsers assigned to bots | macOS 26 |
| Noodle Applet | Runs "noodlets", the mini-apps and games bots build | macOS 15 |
| Noodle Hub | Menu-bar server that runs other people's bots on your harness sign-ins | macOS 26 |
| Noodle Mobile | iPhone/iPad client for a Hub (TestFlight) | iOS 26 |

## Product and UX

- **Onboarding:** the first-run welcome offers Codex, Claude, Muse and Grok. Noodle downloads the harness if needed and opens its sign-in, then creates a starter team (personal assistant, full-stack developer, researcher) in a "Team" group that introduces itself ([harness-setup.md](https://github.com/pdparchitect/noodle/blob/main/docs/harness-setup.md)). Noodle Mobile seeds the same three-bot team on first Hub join ([Mobile/README.md](https://github.com/pdparchitect/noodle/blob/main/Mobile/README.md)).
- **Creating a bot:** choose a harness, model, effort and profile, write a backstory (private) and a public description (visible to other bots), pick a voice, then assign tools, computers, browsers and shared folders in tabs ([usage.md](https://github.com/pdparchitect/noodle/blob/main/docs/usage.md), [security.md](https://github.com/pdparchitect/noodle/blob/main/docs/security.md)).
- **Messenger affordances:** @mentions, reactions, Markdown, attachments with Quick Look, annotations on images and patches, chat backgrounds, pins, unread sorting, archived bots and groups, Spaces per Hub (⌘1/⌘2). Conversations can open in separate or floating always-on-top windows. A global ⌃⌥Space picker floats a chat over any app ([usage.md](https://github.com/pdparchitect/noodle/blob/main/docs/usage.md)).
- **Activity and cost:** a per-bot floating activity log shows tool calls and output. A Usage window (⇧⌘U) charts tokens and cost by bot, harness or model ([usage.md](https://github.com/pdparchitect/noodle/blob/main/docs/usage.md)).
- **Review:** `.patch`/`.diff` attachments open a review view with a commit walkthrough, per-file Viewed checkboxes and line comments that reach the bot as annotations (v0.68.0, [CHANGELOG](https://github.com/pdparchitect/noodle/blob/main/CHANGELOG.md)).
- **OS hooks:** Spotlight and Shortcuts "Send to Agent", a Services menu entry, desktop widgets, and iOS widgets plus share extension ([usage.md](https://github.com/pdparchitect/noodle/blob/main/docs/usage.md), [Mobile/README.md](https://github.com/pdparchitect/noodle/blob/main/Mobile/README.md)).
- **Morning brief:** the hero screenshots ("Chloe ... sends the morning brief and waits for a yes before switching the car insurance") are rendered from a scripted demo fixture. It has a fixed clock, canned messages and `autoReplies` ([Scenarios/personal-assistant/scenario.json](https://github.com/pdparchitect/noodle/blob/main/Scenarios/personal-assistant/scenario.json)); 15 such scenarios exist under `Scenarios/`. No dedicated morning-brief feature exists. The real mechanism is generic: ask a bot for "a report every weekday at nine" and it sets a repeating wake-up ([usage.md](https://github.com/pdparchitect/noodle/blob/main/docs/usage.md)). The "waits for a yes" behaviour comes from the backstory prompt ("you never spend money or sign anything without a yes"), not an enforced approval gate [INFERENCE from the fixture and from [security.md "Approvals"](https://github.com/pdparchitect/noodle/blob/main/docs/security.md)].
- **Distinctive:** the bots-build-software loop. Bots write "noodlets" that open in Noodle Applet, appear as cards in chat, run on iPhone, and can be played on a TV with the phone as controller ([Applet/README.md](https://github.com/pdparchitect/noodle/blob/main/Applet/README.md), [Mobile/README.md](https://github.com/pdparchitect/noodle/blob/main/Mobile/README.md)).

## Architecture

**Components**

```
Noodle.app (SwiftUI, sandboxed)
  ├─ NoodleRuntime: per-bot AgentRuntimeProcess (Codex / Claude / ACP / Muse / Antigravity / Apple)
  ├─ NSXPC ─► signed Agent Host service ─► applies Seatbelt profile ─► harness CLI process tree
  │                                                  └─ bot calls `messenger` / tool CLIs to post and act
  ├─ NoodleMCP (remote MCP over OAuth) · built-in tools (Calendar, Reminders, Maps, Vision, Images)
  ├─ app-extension tools ─► Noodle Computer (VMs) · Noodle Browser · Noodle Applet
  └─ HubCore / HubLink ─► QUIC (UDP 38415, TLS 1.3, pinned P-256) ─► Noodle Hub / Noodle Mobile
```

Diagram reconstructed from source by us; sources: `Sources/NoodleRuntime/*AgentProcess.swift`, [`ExtendedAgentConnection.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleRuntime/ExtendedAgentConnection.swift), [`AgentHostProtocol.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleAgentBridge/AgentHostProtocol.swift), [`Package.swift`](https://github.com/pdparchitect/noodle/blob/main/Package.swift), [`LinkTransport.swift`](https://github.com/pdparchitect/noodle/blob/main/Shared/HubLink/Sources/HubLink/LinkTransport.swift).

**Tech stack:** Swift tools 6.0, macOS 26.0 deployment target, Tuist project ([`Package.swift`](https://github.com/pdparchitect/noodle/blob/main/Package.swift), [`Project.swift`](https://github.com/pdparchitect/noodle/blob/main/Project.swift)). Dependencies: Sparkle for updates; `mlx-swift-lm` and `mlx-swift-examples` (SDXL image generation); `swift-transformers`; the MCP Swift SDK; a LiveKit WebRTC build for calls ([`Package.swift`](https://github.com/pdparchitect/noodle/blob/main/Package.swift)). Languages by bytes: Swift 11.4 MB, with small Python/Shell/JS/C#/Go remnants for VM images and the site ([GitHub languages API](https://api.github.com/repos/pdparchitect/noodle/languages), as of 2026-10-20).

**Agent loop and harness abstraction.** Noodle never shows a harness's assistant text as a chat message. "Messenger is the sole author of user-visible messages". Each bot posts by running a `messenger` CLI (the Noodle binary invoked as `messenger`), with flags such as `--list-participants` and `--react` ([`ACPAgentProcess.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleRuntime/ACPAgentProcess.swift), [`MessengerCLI.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/MessengerCLI.swift), [`MessengerDocumentation.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/MessengerDocumentation.swift)). Wake events (message, heartbeat, scheduled wake, organize, recovery) arrive as typed notifications with per-event guidance text ([`MessengerDocumentation.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/MessengerDocumentation.swift)). Restricted launches are routed per provider in [`HarnessRuntimeConnection.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleRuntime/HarnessRuntimeConnection.swift).

| Harness | Protocol (how Noodle drives it) | Auth via existing account | Status (2026-10-20) |
| --- | --- | --- | --- |
| Codex (OpenAI) | `codex app-server --enable/--disable apps`, JSON-RPC over stdio ([`CodexLaunch.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/CodexLaunch.swift), [`CodexAgentProcess.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleRuntime/CodexAgentProcess.swift)) | ChatGPT sign-in: in-app device code or `codex login`; multiple profiles; restricted bots also inherit `~/.codex/config.toml` providers ([harness-setup.md](https://github.com/pdparchitect/noodle/blob/main/docs/harness-setup.md), [security.md](https://github.com/pdparchitect/noodle/blob/main/docs/security.md)) | Supported; the only harness that takes voice calls ([voice-messages.md](https://github.com/pdparchitect/noodle/blob/main/docs/voice-messages.md)) |
| Claude Code (Anthropic) | `claude -p --input-format stream-json --output-format stream-json --permission-mode bypassPermissions --permission-prompts none --session-id/--resume`, settings JSON disables Claude.ai connectors and nested sandbox ([`ClaudeLaunch.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/ClaudeLaunch.swift)) | Claude.ai OAuth from Claude Code's Keychain item; `claude auth login`; profiles; Noodle writes renewed tokens back to your Keychain item ([security.md](https://github.com/pdparchitect/noodle/blob/main/docs/security.md)) | Supported; the only harness reporting cost ([usage.md](https://github.com/pdparchitect/noodle/blob/main/docs/usage.md)) |
| Vercel FX | ACP JSON-RPC over newline-delimited stdio ("FX v0.0.8 uses ACP"), client fs/terminal capabilities off ([`FxProtocol.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/FxProtocol.swift)) | `fx login` or in-app sign-in; System sign-in only, no profiles | Supported |
| Grok Build (xAI) | ACP with xAI's extended session updates such as `retry_state` ([`GrokProtocol.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/GrokProtocol.swift)) | `grok login` or device code; profiles; sign-ins expire after 7 days ([harness-setup.md](https://github.com/pdparchitect/noodle/blob/main/docs/harness-setup.md)) | Supported |
| Muse Code (Meta) | Muse's own "MSP v1" session protocol, explicitly "not ACP", UUIDv7 idempotency IDs ([`MuseProtocol.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/MuseProtocol.swift), [`MuseAgentProcess.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleRuntime/MuseAgentProcess.swift)) | `muse login` or device code; profiles | Supported; repeated breakage from Muse updates fixed in changelog ([CHANGELOG](https://github.com/pdparchitect/noodle/blob/main/CHANGELOG.md)) |
| OpenCode v2 | ACP; only versions >=2.0.0 <3.0.0 ([`OpenCodeProtocol.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/OpenCodeProtocol.swift)) | Free OpenCode models with no account; `opencode auth login` for your providers; restricted bots ignore global OpenCode config, use workspace `opencode.json` ([harness-setup.md](https://github.com/pdparchitect/noodle/blob/main/docs/harness-setup.md)) | Supported; v1 and package-manager installs unsupported |
| Google Antigravity | `agy --input-format stream-json --output-format stream-json --dangerously-skip-permissions --conversation <id>` ([`AntigravityProtocol.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/AntigravityProtocol.swift)) | Google sign-in by running `agy` in Terminal; profiles | Supported; cannot be interrupted mid-turn ([harness-setup.md](https://github.com/pdparchitect/noodle/blob/main/docs/harness-setup.md)) |
| Apple Intelligence (built in) | In-process own loop on Apple Foundation Models, MLX local models (Qwen3/3.5/3.6/3.8, Gemma 4, gpt-oss, Llama), and OpenAI-compatible Chat Completions for remote models (OpenAI, OpenRouter, Vercel AI Gateway, Ollama, TensorFold, custom) ([`Sources/NoodleAppleRuntime/`](https://github.com/pdparchitect/noodle/tree/main/Sources/NoodleAppleRuntime), [harness-setup.md](https://github.com/pdparchitect/noodle/blob/main/docs/harness-setup.md)) | None for on-device models; API keys in the login Keychain for remote ones; Private Cloud Compute not used | Experimental; 32,768-token context cap; remote models need macOS 27 |
| MonoCode | unknown | unknown | Listed on the website only; no docs or code found ([usenoodle.app](https://usenoodle.app/), GitHub code search hit only `website/index.html`) |

Harness lifecycle. Noodle can download each vendor CLI from the vendor's own servers into its own storage. It verifies the vendor's Apple code signature before running it and checks for updates every 6 hours. It rolls back a release that breaks Noodle, and a user-installed copy always takes precedence ([harness-setup.md](https://github.com/pdparchitect/noodle/blob/main/docs/harness-setup.md), `*ExecutableTrust.swift`, [`HarnessSignatureVerification.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/HarnessSignatureVerification.swift)). A "Kick" control restarts stuck bots. Codex bots that stall for 10 minutes auto-restart up to twice and resume unfinished work ([harness-setup.md](https://github.com/pdparchitect/noodle/blob/main/docs/harness-setup.md)).

**Execution environment.** Restricted bots run on the host under a Seatbelt profile that the signed Agent Host applies to the whole harness process tree: `(deny default)`, outbound network allowed, inbound bind only for the verified harness executable on localhost ([`RestrictedAgentSandbox.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/RestrictedAgentSandbox.swift)). Unrestricted bots run as the Mac user ([security.md](https://github.com/pdparchitect/noodle/blob/main/docs/security.md)). Noodle Computer offers four kinds of machine ([Computer/README.md](https://github.com/pdparchitect/noodle/blob/main/Computer/README.md)):

- Linux Shell/Desktop VMs, each in its own virtual machine, with a non-root `agent` user, no host folder or clipboard sharing, and persistent disks.
- Windows 11 Arm VMs (macOS 27).
- An experimental "Local Mac": a separate standard macOS user account, not isolated like a VM.
- SSH computers.

**State and storage.** Each bot is a self-contained package with `agent.json`, `workspace/` and `runtime/<harness>-runtime.json` session state ([`AgentStorageLayout.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/AgentStorageLayout.swift)). Chats and workspaces stay on the Mac ([privacy.md](https://github.com/pdparchitect/noodle/blob/main/docs/privacy.md)). Tool OAuth sign-ins live in the macOS Keychain, while harness sign-in copies live in the bot folder ([security.md](https://github.com/pdparchitect/noodle/blob/main/docs/security.md)). User-made Spaces sync through the user's private iCloud database with `encryptedValues` and CKSyncEngine ([`SpaceCloudSync.swift`](https://github.com/pdparchitect/noodle/blob/main/Shared/HubLink/Sources/HubLink/SpaceCloudSync.swift)).

**Remote and mobile access.**

- **Transport:** the Hub link is QUIC (ALPN `noodle-hub/1`) over UDP 38415 with TLS 1.3. Both sides present self-signed certificates and peers are pinned by long-lived P-256 public key ([`LinkTransport.swift`](https://github.com/pdparchitect/noodle/blob/main/Shared/HubLink/Sources/HubLink/LinkTransport.swift), [`LinkIdentity.swift`](https://github.com/pdparchitect/noodle/blob/main/Shared/HubLink/Sources/HubLink/LinkIdentity.swift)).
- **Reachability:** there is no relay. The Hub asks the router for a port via UPnP or NAT-PMP, or the user forwards UDP 38415 or adds a domain ([Hub/README.md](https://github.com/pdparchitect/noodle/blob/main/Hub/README.md), [`RouterPortMapping.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/HubCore/RouterPortMapping.swift)).
- **Push:** notifications go through CloudKit's public database. Only a topic, a conversation ID and an unread count are stored, under a hashed record name ([`CloudKitPushes.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/HubCore/CloudKitPushes.swift)).
- **Mac to iPhone:** "Let My Devices Reach This Mac" turns the user's own Mac into a private, single-person Hub that the phone pairs with by QR code. The Mac stays awake while this is on ([README](https://github.com/pdparchitect/noodle/blob/main/README.md), [`PersonalHub.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/HubCore/PersonalHub.swift)).

**Extension surface.**

- **Remote MCP services:** added via browser OAuth. Custom MCPs must also use browser sign-in; services that need a pasted API key or run as a local program are not supported ([mcp-connections.md](https://github.com/pdparchitect/noodle/blob/main/docs/mcp-connections.md)). This contradicts the README claim of "any MCP you can think of" ([README](https://github.com/pdparchitect/noodle/blob/main/README.md)).
- **Tool providers:** each lives under `Tools/<Name>` as an app extension or a built-in ([`Package.swift`](https://github.com/pdparchitect/noodle/blob/main/Package.swift)).
- **Skills:** generated `AGENTS.md` and skills inside the workspace ([`MessengerDocumentation.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/MessengerDocumentation.swift)).
- **External agents:** Noodle Computer and Noodle Browser expose `noodle-computer` / `noodle-browser` CLIs that also run as MCP servers, so outside agents such as Claude Code or Codex can use them ([Computer/README.md](https://github.com/pdparchitect/noodle/blob/main/Computer/README.md), [Browser/README.md](https://github.com/pdparchitect/noodle/blob/main/Browser/README.md)).

## Capabilities in detail

- **Persistent bots:** identity (name, avatar face, backstory, public description, voice), private workspace, history and harness session. Idle bots start a fresh session after a day by default while keeping workspace, memory and messages ([usage.md](https://github.com/pdparchitect/noodle/blob/main/docs/usage.md)).
- **Memory:** bot-maintained `memory.md`, `preferences.md` and `assignments.md` in the workspace, guided by `.agents/skills/preferences-and-memory/SKILL.md`. An "organize" event asks the bot to merge duplicates and tidy them ([`MessengerDocumentation.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/MessengerDocumentation.swift)). For local/remote Apple-runtime models, older turns are summarized or dropped while the full transcript stays searchable ([harness-setup.md](https://github.com/pdparchitect/noodle/blob/main/docs/harness-setup.md)). No vector store or knowledge-graph memory was found.
- **Routines:** heartbeats wake idle bots, default every 30 min, and only while Noodle is open and the Mac is awake ([usage.md](https://github.com/pdparchitect/noodle/blob/main/docs/usage.md)). On a heartbeat the bot checks unread messages, then runs a full round of each standing assignment in `assignments.md` ([`MessengerDocumentation.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/MessengerDocumentation.swift)). Self-scheduled wake-ups are capped at 3 pending and 12 consecutive; repeating schedules fire at most once every 5 min ([usage.md](https://github.com/pdparchitect/noodle/blob/main/docs/usage.md)). No webhooks or external event triggers were found.
- **Group chats:** a shared group description sets the goal. Bots reply only when addressed, when they own the work, or when they add something new, and they route work to the group it belongs to ([`MessengerDocumentation.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/MessengerDocumentation.swift), v0.66.0 [CHANGELOG](https://github.com/pdparchitect/noodle/blob/main/CHANGELOG.md)). A group can mix harnesses, and each bot sends the group conversation to its own provider ([privacy.md](https://github.com/pdparchitect/noodle/blob/main/docs/privacy.md)). Busy-bot delivery (queue vs interrupt) is configurable, with per-harness urgent-message handling (0.67.0 and 0.69.1 [CHANGELOG](https://github.com/pdparchitect/noodle/blob/main/CHANGELOG.md)).
- **Coding workspace:** per-bot folder, Read & Write or Read Only shared folders listed in the generated `AGENTS.md`, and a patch review UI. The coding itself is delegated to the wrapped CLIs.
- **Browser:** Noodle Browser profiles keep sign-ins and are assigned per bot. Bots open, read, fill, click, upload, download and screenshot pages, with a visible cyan pointer and "Pause Agents". Site-provided agent tools are supported experimentally; forms needing confirmation are left for the user to submit ([Browser/README.md](https://github.com/pdparchitect/noodle/blob/main/Browser/README.md)).
- **Computer use:** terminal and files in VMs, with desktop screenshots shared to chat. Agents "cannot yet click or type" on Local Mac or Windows desktops ([Computer/README.md](https://github.com/pdparchitect/noodle/blob/main/Computer/README.md)).
- **Connectors:**
  - MCP catalog with Google Workspace (experimental, tester-only; Gmail can draft but not send), Pipedream and Krea (0.69.0).
  - Native Calendar and Reminders, Maps, on-device OCR (Vision), background removal and MLX SDXL image generation (~7 GB models).
  - Codex "Apps" and Claude.ai connectors behind a per-bot toggle.
  - Sources: [mcp-connections.md](https://github.com/pdparchitect/noodle/blob/main/docs/mcp-connections.md), [usage.md](https://github.com/pdparchitect/noodle/blob/main/docs/usage.md), [security.md](https://github.com/pdparchitect/noodle/blob/main/docs/security.md), [CHANGELOG](https://github.com/pdparchitect/noodle/blob/main/CHANGELOG.md).
- **Channels:** only Noodle's own apps. A GitHub code search for "Telegram" returned 0 hits. "iMessage" appears only in `Sources/NoodleCore/ToolCatalog.swift` (context unverified). Issue [#7](https://github.com/pdparchitect/noodle/issues/7) proposes an IMAP/SMTP mail companion (open).
- **Voice:**
  - Voice messages are transcribed on device with Apple speech ([voice-messages.md](https://github.com/pdparchitect/noodle/blob/main/docs/voice-messages.md)).
  - Live calls work only with Codex bots: "your voice is sent to OpenAI" ([voice-messages.md](https://github.com/pdparchitect/noodle/blob/main/docs/voice-messages.md)). Calls use WebRTC ([`Package.swift`](https://github.com/pdparchitect/noodle/blob/main/Package.swift)).
  - On iPhone, calls appear on the system call screen.
- **Mobile:** Noodle Mobile on iOS 26 is a client for a Hub or for the user's own Mac:
  - chats, bot creation and editing, live view of shared browser tabs and computers;
  - noodlets that run on the phone;
  - widgets, a share extension and notifications;
  - archive, and admin user management.

  Sources: [Mobile/README.md](https://github.com/pdparchitect/noodle/blob/main/Mobile/README.md), [`Mobile/Sources/`](https://github.com/pdparchitect/noodle/tree/main/Mobile/Sources). It cannot run agents on its own [INFERENCE: every documented flow requires pairing with a Hub or Mac].
- **Hub / team features:**
  - **Plans:** Hub users are assigned plans, and each plan "decides which harnesses each plan lends". The Default plan lends nothing ([Hub/README.md](https://github.com/pdparchitect/noodle/blob/main/Hub/README.md)).
  - **Admins:** admins manage other users.
  - **Invitations:** one-time, valid for 15 minutes.
  - **Logs:** a 90-day audit log.
  - **Limits:** 100 MB file cap by default.
  - **Shared resources:** per-Hub image models; bots shared from a member's Mac to other Hub users ([usage.md](https://github.com/pdparchitect/noodle/blob/main/docs/usage.md)).

## Security and trust model

- **Restricted by default.** The Seatbelt sandbox is enforced by a signed XPC Agent Host. Bots cannot read personal files, other bots' files, Noodle storage or the Keychain, and they cannot accept incoming connections. If the limit cannot be applied, the bot does not start ([security.md](https://github.com/pdparchitect/noodle/blob/main/docs/security.md), [`RestrictedAgentSandbox.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/RestrictedAgentSandbox.swift)). The docs list honest limitations: internet egress is open, there is no undo for workspace writes, the sandbox is not a VM (no CPU or spend limits), and file names leak ([security.md "Limitations"](https://github.com/pdparchitect/noodle/blob/main/docs/security.md)).
- **No human-in-the-loop approvals.** "Noodle does not show approval or question forms in chat. It approves a harness's tool requests automatically, within the bot's access". Questions that need a typed answer are declined ([security.md](https://github.com/pdparchitect/noodle/blob/main/docs/security.md)). Claude Code runs with `bypassPermissions` and Antigravity with `--dangerously-skip-permissions` ([`ClaudeLaunch.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/ClaudeLaunch.swift), [`AntigravityProtocol.swift`](https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/AntigravityProtocol.swift)).
- **Credential exposure.** Each restricted bot gets a readable private copy of the harness sign-in, and "A bot that follows misleading instructions can hand your sign-in to someone else". Backups of a bot folder include the sign-in. Claude Code token renewals are written back into the user's Keychain item ([security.md "Sign-ins"](https://github.com/pdparchitect/noodle/blob/main/docs/security.md)).
- **Hub threat model** is documented in [security.md "Noodle Hub"](https://github.com/pdparchitect/noodle/blob/main/docs/security.md):
  - Lending a sign-in shares the account. A borrower "can end up using your account directly, outside the Hub".
  - Admins can impersonate any non-admin.
  - An invitation is a bearer key until first use.
  - Users must compare the Hub key out of band, because Hub names can be spoofed.
  - Shared bots expose everything they can reach and remember.
  - Hub bots can reach the LAN.

  This contradicts the website's claim that borrowers' bots "use the subscriptions you lend them without ever holding your sign-ins" ([usenoodle.app](https://usenoodle.app/)). The docs are the more precise source.
- **Encryption.** Transport is QUIC/TLS 1.3 with key pinning between devices and the Hub. At rest, conversations, files and memory are "within reach of whoever runs" the Hub ([privacy.md](https://github.com/pdparchitect/noodle/blob/main/docs/privacy.md)). Not end-to-end against the Hub operator.
- **Harness integrity.** Downloaded harnesses are checked against the vendor's Apple code signature before running ([CHANGELOG 0.21.0 area](https://github.com/pdparchitect/noodle/blob/main/CHANGELOG.md), `*ExecutableTrust.swift`).
- **Telemetry.** "Noodle collects no analytics or usage data" ([privacy.md](https://github.com/pdparchitect/noodle/blob/main/docs/privacy.md)) (vendor claim; no analytics SDK in [`Package.swift`](https://github.com/pdparchitect/noodle/blob/main/Package.swift) dependencies).
- **Untrusted content.** `ToolUntrustedContent.swift` exists, and browser site-tools are treated as untrusted ([Browser/README.md](https://github.com/pdparchitect/noodle/blob/main/Browser/README.md)). Not further verified.
- **Incidents.** No published GitHub security advisories (API returned 0, as of 2026-10-20). Vulnerabilities are reported privately via GitHub advisories ([SECURITY.md](https://github.com/pdparchitect/noodle/blob/main/SECURITY.md)). Open security-adjacent issues: [#45](https://github.com/pdparchitect/noodle/issues/45) (RSA keys for SSH computers).

**Terms-of-service implications of the Hub.**

- **OpenAI.** The consumer Terms of Use say: "You may not share your account credentials or make your account available to anyone else" ([OpenAI Terms of Use, effective 2026-01-01](https://openai.com/policies/row-terms-of-use/)).
- **Anthropic consumer terms.** Anthropic's Consumer Terms say: "You may not share your Account login information ... You also may not make your Account available to anyone else" ([Anthropic Consumer Terms](https://www.anthropic.com/legal/consumer-terms)).
- **Claude Code legal page.** Anthropic's Claude Code legal page says subscription OAuth "is designed to support ordinary use of Claude Code". It adds that developers may not "route requests through Free, Pro, or Max plan credentials on behalf of their users" or "collect, store, or intermediate Claude.ai credentials or session tokens", and that Pro/Max limits "assume ordinary, individual usage" ([Claude Code Legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)).
- **What is plainly allowed.** The same page allows an end user to sign in to the unmodified Claude Code binary with their own subscription. Noodle running the vendor-signed binary for its owner on their own Mac fits that pattern [INFERENCE].
- **Where Hub lending conflicts.** Lending a personal subscription to other household members through a Hub makes the account available to others. That appears to conflict directly with both OpenAI's and Anthropic's account-sharing clauses [INFERENCE]. Noodle's practice of copying OAuth tokens into per-bot folders and writing renewed tokens back to the Keychain may also be read as "storing or intermediating" credentials [INFERENCE].
- **What Noodle discloses.** Noodle's docs cover the data-privacy side of personal subscriptions ([privacy.md](https://github.com/pdparchitect/noodle/blob/main/docs/privacy.md)). They do not warn that lending may breach provider terms. Enforcement risk (account suspension) falls on the lender [INFERENCE].
- **Not checked.** xAI, Meta, Google and Vercel terms were not reviewed for this profile.

## Traction and momentum

- **GitHub stats (as of 2026-10-20):** 179 stars, 21 forks, 36 open issues+PRs (46 issues and 48 PRs total) ([GitHub API](https://api.github.com/repos/pdparchitect/noodle)). The repo was created 2026-09-04 and pushed 2026-10-20.
- **Commits:** about 1,647 on `main`, 1,610 of them by `pdparchitect` and 31 by `noodle-theo[bot]`, with three outside contributors at 1-3 commits each ([contributors API](https://api.github.com/repos/pdparchitect/noodle/contributors)). It is effectively a solo project, written largely with agents [INFERENCE from the bot contributor and the repo-level `AGENTS.md`/`.agents/skills`].
- **Releases:** 316 GitHub release objects ([releases API](https://github.com/pdparchitect/noodle/releases)), as of 2026-10-20:

  | App | Releases | First | Latest |
  | --- | --- | --- | --- |
  | Noodle | 81 | 2026-09-05 | 0.69.1, 2026-10-19 |
  | Computer | 47 | 2026-09-10 | 0.32.2 |
  | Applet | 47 | 2026-09-13 | 0.33.0 |
  | Hub | 46 | 2026-09-24 | 0.36.1 |
  | Browser | 31 | 2026-09-18 | 0.20.0 |
  | Suite bundles | 60 | 2026-09-18 | 2026-10-19 |

  The changelog runs from 0.3.0 (2026-09-05) to 0.69.1 with 1-3 versions on most days ([CHANGELOG](https://github.com/pdparchitect/noodle/blob/main/CHANGELOG.md)). Mobile ships via TestFlight (`.github/workflows/testflight.yml`).
- **Maker:** pdp. GitHub bio: "maker, security and hacking, sometimes CISO, producer of @chatbotkit, @crmkit and @openzot"; company CBK.AI, London ([GitHub user API](https://api.github.com/users/pdparchitect)). The devlog runs as posts on X ([x.com search "from:pdp noodle"](https://x.com/search?q=from%3Apdp%20noodle&f=live)), not read for this profile.
- **Press:** no press coverage of Noodle found. A web search surfaced only the repo, the site and same-name projects.
- **Business model:** free and Apache-2.0, "Everything is free" ([usenoodle.app](https://usenoodle.app/)). No paid tier, hosted service or donations link found. A possible tie-in to ChatBotKit is unknown; ChatBotKit appears only as the demo site in Browser screenshots ([README](https://github.com/pdparchitect/noodle/blob/main/README.md)).

## Strengths

- **Widest subscription-harness coverage seen so far.** Seven vendor CLIs plus local and on-device models, each driven by its native protocol (app-server, stream-JSON, ACP, MSP) rather than screen-scraping. Mixed-vendor groups work.
- **Genuinely native.** SwiftUI and deep macOS integration: Spotlight/Shortcuts/Services, widgets, floating chats, Quick Look, Keychain, EventKit, CloudKit, Virtualization, Foundation Models.
- **Restricted-by-default sandbox** enforced at the OS level per bot, with unusually candid security and privacy docs that list limitations and threat scenarios.
- **Household-scale multi-user** without any vendor cloud. The Hub is a peer-to-peer QUIC server with key-pinned pairing, plans, admins and audit logs.
- **Companion apps** give agents real computers (Linux/Windows VMs, SSH) and persistent signed-in browsers. Both are also exposed to outside agents via CLI and MCP.
- **Extreme shipping velocity** and a detailed user-facing changelog.

## Weaknesses and risks

- **ToS exposure.** Hub "lending" of personal ChatGPT/Claude subscriptions appears to conflict with the account-sharing clauses quoted above [INFERENCE]. Provider enforcement (token revocation, CLI protocol changes, rate limits) could break the core premise.
- **Credential exfiltration by design.** Bots hold readable copies of OAuth tokens. With open egress and auto-approved tools, a prompt-injected bot can leak the user's account (acknowledged in [security.md](https://github.com/pdparchitect/noodle/blob/main/docs/security.md)).
- **No approval gates.** All tool calls are auto-approved within the sandbox. "Ask before paying" is prompt-level only.
- **Platform lock.** Apple silicon and macOS 26+ only. Windows VMs and remote models need macOS 27. No Android, Windows, Linux or web client. Mobile is TestFlight-only and needs an always-on Mac.
- **Fragile integration surface.** Seven fast-moving vendor CLIs, each with its own protocol. The changelog shows repeated fixes after vendor updates (Muse 1.4.2 and 1.4.4 breakages).
- **Always-on depends on a Mac staying awake.** Heartbeats run only while Noodle is open and the Mac is awake. There is no cloud fallback.
- **Bus factor of one.** Over 97% of commits come from a single author, the project is 6 weeks old, and there is no business model.
- **Marketing drift.** Website claims ("without ever holding your sign-ins", "any MCP you can think of") go further than the docs. The "morning brief" is a scripted demo fixture, not a feature.

## Ideas worth taking for Memoshi

- **Messenger CLI as the only author of user-visible messages.** Decoupling harness output from chat makes every harness behave the same and keeps bots from leaking chain-of-thought into chat.
- **Typed wake events with per-event guidance** (message, heartbeat, scheduled wake, organize, recovery), documented in one exhaustive switch. This is a clean contract for proactive behaviour.
- **Standing assignments as a workspace file** (`assignments.md`) that heartbeats execute in full each round. Routines stay inspectable and editable by both user and bot.
- **Per-harness native protocol adapters behind one process interface** (app-server JSON-RPC, stream-JSON, ACP, MSP). Prefer ACP where it exists and fall back to vendor protocols.
- **Verify vendor code signatures** before running auto-installed harnesses, and let a user-installed copy always win. Cheap supply-chain hygiene.
- **Starter team on first sign-in** (assistant, developer, researcher in a group that introduces itself). It solves the empty-state problem immediately.
- **Peer-to-peer device link** using QUIC with key-pinned self-signed certs, one-time 15-minute invitations, and CloudKit for metadata-only push. Remote access without operating a relay.
- **Avoid:** lending personal subscriptions across people. Treat multi-user as "each person brings their own account" or API keys, unless provider terms explicitly allow it [INFERENCE].
- **Avoid:** auto-approving all tool calls. Add a real approval primitive for spend and send actions instead of relying on backstory wording.
- **Adapt:** candid "what restricted access protects / limitations" docs, written per feature. These build trust with technical users.

## Open questions

- What is MonoCode, listed on the website but absent from docs and code? Check future commits and harness files, or ask the maker.
- Does Noodle Hub's lending model have any provider blessing or published guidance? Search the maker's X devlog and provider policy pages for xAI, Meta, Google and Vercel.
- What does "iMessage" in `ToolCatalog.swift` refer to: a planned channel or an MCP catalog entry? Read the file.
- What is the browser engine of Noodle Browser (WKWebView vs Chromium), and how are site agent tools discovered? Read `Browser/Sources`.
- Are DMGs notarized, and is the Agent Host's code-signing requirement pinned to a Team ID? Check `AgentHostIdentity` and release workflows.
- What are the real adoption numbers (DMG download counts, TestFlight seats)? Sum `download_count` from the releases API.
- What is the maker's long-term plan or monetization, and any tie-in to ChatBotKit? Read the X devlog or ask.

## Sources

1. https://github.com/pdparchitect/noodle (repo; GitHub API `repos/pdparchitect/noodle`, `/releases`, `/contributors`, `/languages`, as of 2026-10-20)
2. https://github.com/pdparchitect/noodle/blob/main/README.md
3. https://github.com/pdparchitect/noodle/blob/main/docs/harness-setup.md
4. https://github.com/pdparchitect/noodle/blob/main/docs/security.md
5. https://github.com/pdparchitect/noodle/blob/main/docs/privacy.md
6. https://github.com/pdparchitect/noodle/blob/main/docs/usage.md
7. https://github.com/pdparchitect/noodle/blob/main/docs/mcp-connections.md
8. https://github.com/pdparchitect/noodle/blob/main/docs/voice-messages.md
9. https://github.com/pdparchitect/noodle/blob/main/CHANGELOG.md
10. https://github.com/pdparchitect/noodle/blob/main/SECURITY.md
11. https://github.com/pdparchitect/noodle/blob/main/Hub/README.md
12. https://github.com/pdparchitect/noodle/blob/main/Mobile/README.md
13. https://github.com/pdparchitect/noodle/blob/main/Computer/README.md
14. https://github.com/pdparchitect/noodle/blob/main/Browser/README.md
15. https://github.com/pdparchitect/noodle/blob/main/Applet/README.md
16. https://github.com/pdparchitect/noodle/blob/main/Package.swift and Project.swift
17. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/CodexLaunch.swift
18. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/ClaudeLaunch.swift
19. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/FxProtocol.swift
20. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/GrokProtocol.swift
21. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/MuseProtocol.swift
22. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/OpenCodeProtocol.swift
23. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/AntigravityProtocol.swift
24. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleRuntime/ACPAgentProcess.swift
25. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleRuntime/HarnessRuntimeConnection.swift
26. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleRuntime/ExtendedAgentConnection.swift
27. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleAgentBridge/AgentHostProtocol.swift
28. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/RestrictedAgentSandbox.swift
29. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/AgentStorageLayout.swift
30. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/MessengerCLI.swift
31. https://github.com/pdparchitect/noodle/blob/main/Sources/NoodleCore/MessengerDocumentation.swift
32. https://github.com/pdparchitect/noodle/blob/main/Shared/HubLink/Sources/HubLink/LinkTransport.swift
33. https://github.com/pdparchitect/noodle/blob/main/Shared/HubLink/Sources/HubLink/LinkIdentity.swift
34. https://github.com/pdparchitect/noodle/blob/main/Shared/HubLink/Sources/HubLink/SpaceCloudSync.swift
35. https://github.com/pdparchitect/noodle/blob/main/Sources/HubCore/CloudKitPushes.swift
36. https://github.com/pdparchitect/noodle/blob/main/Scenarios/personal-assistant/scenario.json
37. https://usenoodle.app/
38. https://x.com/search?q=from%3Apdp%20noodle&f=live (maker devlog; not read)
39. https://openai.com/policies/row-terms-of-use/ (OpenAI Terms of Use, effective 2026-01-01)
40. https://www.anthropic.com/legal/consumer-terms (Anthropic Consumer Terms)
41. https://code.claude.com/docs/en/legal-and-compliance (Claude Code legal and compliance)
42. https://github.com/poteto/noodle (unrelated same-name project)
43. https://github.com/noodle-run/noodle (unrelated same-name project)
