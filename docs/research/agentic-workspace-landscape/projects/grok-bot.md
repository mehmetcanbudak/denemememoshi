# Grok Bot

> SpaceXAI's hosted roster of persistent "AI teammates": named Bots you message like coworkers, which share one always-on Cursor-hosted cloud computer per user (browser, terminal, `/workspace`), learn routines, coordinate with each other, and come back only for approvals. Built and operated by Cursor (Anysphere), now a SpaceX subsidiary. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

Naming note: the company is legally SpaceXAI LLC (formerly X.AI LLC) ([Cursor Grok API terms](https://cursor.com/terms/grok-api)); it rebranded from xAI to SpaceXAI in July 2026 and Musk announced a further rename to "SpaceXSI" on 2026-10-04 (press: [Reuters](https://www.reuters.com/business/media-telecom/musk-says-he-will-rename-spacexai-spacexsi-2026-10-04)). x.ai pages already say "SpaceXSI" ([launch post title](https://x.ai/news/introducing-grok-bot)). This profile uses "SpaceXAI".

## Matrix row

```yaml
name: Grok Bot
slug: grok-bot
category: closed-hosted-agents
maker: SpaceXAI (SpaceXSI) brand; built, billed, and operated by Cursor / Anysphere Inc., a SpaceX subsidiary since 2026-08-14
license: proprietary (Grok Bot Terms at cursor.com/terms/grok-bot); companion CLI Grok Build is Apache-2.0
repo: none for Grok Bot; companion xai-org/grok-build (Apache-2.0, read-only mirror) contains the Grok Bot "computer hub" wire protocol
website: https://x.ai/bot
first_public: 2026-08-11
latest_release: desktop 0.71.2, 2026-10-14 in the public changelog; 0.72.0 installed on this Mac on 2026-10-20 but not yet in the changelog (iOS 1.16.0, ~2026-10-19)
release_cadence: "~6 desktop releases/week (51 changelog entries covering ~56 versions, 2026-08-12 to 2026-10-14)"
stars: n/a (closed); grok-build 27,460 (as of 2026-10-20)
forks: n/a; grok-build 5,192 (as of 2026-10-20)
contributors: n/a; grok-build 1 (sync account; external PRs not accepted)
primary_language: unknown for service; desktop is Electron/TypeScript (third-party reconstruction); grok-build is Rust
stack: "Electron 42.1.0 desktop (secondary evidence), native iOS/Android apps, Cursor backend, per-user Firecracker microVM 'box', JSON-RPC computer hub with bot.* relay methods, noVNC screen view"
platforms: [macos, windows, linux, ios, android]
agent_engine: own loop (Cursor-built in-box harness; not user-replaceable); delegates coding to Cursor Cloud Agents
engines_supported: [raw-api]  # vendor-managed models only; no BYO engine
model_access: vendor credits only (weekly included usage + on-demand / top-ups); no model picker, no API keys
execution_env: cloud VM (Cursor-hosted Firecracker microVM per user, US-only); optional approved command execution on the user's own desktop
per_bot_computer: no — ONE computer per user account shared by all of that user's Bots (shared files, browser cookies, CLI credentials); each Bot gets its own screen on it; one computer-use task per Bot screen at a time; screens are not security boundaries
persistent_bots: yes — named Bots with profile, avatar, description, memory, routines; primary (starred) Bot; Team Bots
memory: per-Bot summarized preferences/facts (model-written, not user-editable store); Team Bots add team memory + per-person private notes
routines: yes — schedules (>=5 min apart, up to 50 per Bot), webhooks with payload, event triggers (Slack, GitHub PR, MS Teams, Linear, Sentry, PagerDuty), per-email-tag triggers
group_chat: yes — 2-6 Bots per group, @mentions, async bot-to-bot messages and ownership handoff
coding_workspace: partial — terminal + /workspace + GitHub/GitLab/Bitbucket/Azure DevOps access, PR previews; heavy coding delegated to Cursor Cloud Agents / "Projects"
browser_use: yes — shared persistent Chromium-class browser on the cloud computer, take-over, Secure Forms, 1Password
computer_use: yes — full desktop on cloud computer (1920x1200 since 0.68.1), watch/take control
connectors: native plugins via "Connect Apps" (Gmail, Outlook, Slack, GitHub, Notion, Figma, Canva, Stripe, QuickBooks, Glean, 1Password...), custom MCP (remote HTTPS or command), Cursor connector policy
channels: desktop + mobile apps, Slack (Team Bots with own Slack app), X (@bot tagging), Bot-owned email address, voice chat, grok.com chat relay
mobile: yes — iOS/iPadOS 18+ and Android 9+ apps
voice: yes — dictation, live voice chat, Bot voice memos
approvals: model-based Auto Review + Ask first / Always allow rules; draft cards for email/Slack; human take-over for passwords/2FA/payments; local-exec per-command approval by default
e2e_encryption: no (server-side processing; secrets encrypted at rest; TLS in transit)
self_host: no (no on-prem, no BYO image)
multi_user: yes — Teams/Enterprise, Team Bots shared with per-person private chats, managers, SSO/SCIM, admin dashboard
pricing: "included in The X Subscription Premium $30/mo, Super $100/mo, Ultra $200/mo (Plus $8 excluded); legacy Cursor Pro/Pro+/Ultra/Teams and linked SuperGrok/X Premium+; weekly usage pool + on-demand/top-ups; free trial = usage credit"
maturity: beta — launch post and docs call it beta; enterprise GA to all Enterprise teams since 0.40.0 (2026-09-03)
```

## What it is

- Mental model: a messenger whose contacts are Bots. "Grok Bot is your team of always-on agents. They have their own computer, work inside tools and apps like you do, and keep working 24/7" ([launch post, 2026-08-11](https://x.ai/news/introducing-grok-bot)). A Bot is "a durable AI teammate with a name, a job, its own conversation, and working context that develops over time" ([docs: Create and manage Bots](https://docs.x.ai/grok-bot/bots)).
- Problem claimed: finishing the last 10% of work inside the real tool rather than producing chat drafts; working "including platforms with no clean API or MCP" ([launch post](https://x.ai/news/introducing-grok-bot)); setup "is a message, not a workflow builder" ([docs overview](https://docs.x.ai/grok-bot/overview)).
- Target user: knowledge workers and teams (sales outbound, ops, recruiting, expenses, bug reproduction are the showcased roles) ([launch post](https://x.ai/news/introducing-grok-bot); [App Store listing](https://apps.apple.com/us/app/grok-bot/id6794501026)). Originated as an internal prototype used across the company (vendor claim, [launch post](https://x.ai/news/introducing-grok-bot)).
- Who actually builds it: Cursor. The download link is `api2.cursor.sh` and the launch video file is named `..._cursor_bot_edit_v8...` ([launch post](https://x.ai/news/introducing-grok-bot)); sign-in is a Cursor account, billing and support are Cursor's, "The computers Bots work on run in Cursor's cloud" ([docs overview](https://docs.x.ai/grok-bot/overview)); store listings say "© 2026 Anysphere, Inc." while the publisher is X Corp. (iOS) / SpaceXAI LLC (Android) ([App Store](https://apps.apple.com/us/app/grok-bot/id6794501026); [Google Play](https://play.google.com/store/apps/details?id=ai.x.grok.bot)). The reconstructed 0.18.0 macOS bundle ID is `com.anysphere.sand` and the app is Developer-ID signed by Anysphere (secondary evidence, [reconstruction PROVENANCE.md](https://github.com/b-nnett/grok-bot-0.18-reconstructed/blob/main/PROVENANCE.md)).

### Corporate relationship (SpaceXAI / SpaceX / Cursor)

| Date | Event | Source |
|---|---|---|
| 2026-02 | SpaceX acquires xAI (press: valuation US$250B) | third-party: [Wikipedia SpaceXAI](https://en.wikipedia.org/wiki/SpaceXAI) |
| 2026-04-21 | Cursor partners with SpaceX/SpaceXAI to train models on Colossus | [Cursor blog](https://cursor.com/blog/spacex-model-training) |
| 2026-06-16 | SpaceX signs agreement to acquire Anysphere for ~$60B in stock | press: [Reuters](https://www.reuters.com/legal/transactional/spacex-buy-anysphere-60-billion-2026-06-16) |
| 2026-07-06/07 | xAI rebrands as SpaceXAI | press: [The Verge](https://www.theverge.com/ai-artificial-intelligence/961896/xais-x-account-is-now-spacexai) |
| 2026-08-11 | Grok Bot launches (beta) under x.ai, built by Cursor | [launch post](https://x.ai/news/introducing-grok-bot) |
| 2026-08-14 | "Cursor has officially been acquired by SpaceX"; post links "building AI teammates" to x.ai/bot | [Cursor blog](https://cursor.com/blog/joining-spacex) |
| 2026-10-04 | Musk announces SpaceXAI to be renamed SpaceXSI | press: [Reuters](https://www.reuters.com/business/media-telecom/musk-says-he-will-rename-spacexai-spacexsi-2026-10-04) |
| 2026-10-12 | "The X Subscription": one plan for Grok, Grok Bot, Cursor and X Premium | [Cursor forum announcement](https://forum.cursor.com/t/introducing-the-x-subscription/174450); [docs](https://docs.x.ai/x-subscription/overview) |

Cursor's Grok API terms describe SpaceXAI LLC as "an Affiliate service provider engaged by Anysphere to operate the Grok API Services" ([cursor.com/terms/grok-api](https://cursor.com/terms/grok-api)). [INFERENCE] Grok Bot is a Cursor product carrying the SpaceXAI brand; Cursor ships it, SpaceXAI supplies the brand, distribution (X, grok.com, SuperGrok), and models.

## Product and UX

- Onboarding: install desktop app, sign in with a Cursor account (or "Sign in with Grok"/link SuperGrok), onboarding asks what you work on and suggests Bots; setup creates your first Bot and the shared computer ([changelog 0.31.0](https://x.ai/changelog/bot#v0.31.0), [0.51.0](https://x.ai/changelog/bot#v0.51.0); [mobile docs](https://docs.x.ai/grok-bot/mobile)).
- Main screen: sidebar of Bots (pin, hide, sections, unread), 1:1 chats and group chats; details pane with Routines, Tasks, Library, Setup; "Computer" view that opens in Watching mode until you press Take control ([chat docs](https://docs.x.ai/grok-bot/chat-and-collaboration); [changelog 0.70.2](https://x.ai/changelog/bot#v0.70.2)).
- Creating a Bot: Cmd/Ctrl+N, name it, describe the job; durable rules go in the description, task instructions in chat; Bots can also create Bots ([bots docs](https://docs.x.ai/grok-bot/bots); [changelog 0.34.0](https://x.ai/changelog/bot#v0.34.0)).
- In-chat interaction cards are the core UX: approval cards (Allow once / Always allow / Deny), question cards (multi-select), Secure Forms for logins, email/Slack draft cards with Send/Discard, purchase cards with amount, connector sign-in cards, PR/link previews, interactive app cards (Figma, Notion, Canva) ([changelog 0.25.0](https://x.ai/changelog/bot#v0.25.0), [0.30.0](https://x.ai/changelog/bot#v0.30.0), [0.44.0](https://x.ai/changelog/bot#v0.44.0), [0.45.0](https://x.ai/changelog/bot#v0.45.0), [0.70.2](https://x.ai/changelog/bot#v0.70.2)).
- Distinctive: "Teach a task" demonstration recording (up to 10 minutes, no audio) becomes a draft skill ([skills docs](https://docs.x.ai/grok-bot/skills-routines-and-automations)); a starred primary Bot that proactively offers to take work ([changelog 0.66.0](https://x.ai/changelog/bot#v0.66.0)); Bots tint the chat in their color ([0.68.1](https://x.ai/changelog/bot#v0.68.1)); Bot avatars with eyes and shapes ([0.64.0](https://x.ai/changelog/bot#v0.64.0)).
- Sharing: "Share as template" produces an x.ai link (public or team-only) that recipients open on x.ai and "Add to Grok Bot"; a copy carries identity, description, skills and routines, not the computer, logins or history ([bots docs](https://docs.x.ai/grok-bot/bots)); third-party catalogs index thousands of public shares, e.g. awesome-grok-bot "5257 live x.ai/bot shares" (third-party, [GitHub](https://github.com/majiayu000/awesome-grok-bot)). A Marketplace (renamed "Connect Apps" in 0.67.0) lists plugins and, for a time, Bots, with a Verified badge for first-party Bots ([0.41.0](https://x.ai/changelog/bot#v0.41.0), [0.63.0](https://x.ai/changelog/bot#v0.63.0), [0.67.0](https://x.ai/changelog/bot#v0.67.0)).
- Entry points beyond the app: tag `@bot` on X and your main Bot picks up the post as a task (not available in UK/EU/EEA/Australia) ([tag docs](https://docs.x.ai/grok-bot/tag-on-x)); Slack for Team Bots; a Bot-owned email inbox ([0.70.2](https://x.ai/changelog/bot#v0.70.2)); grok.com chat can send prompts to Bots (protocol constant `grok-chat.<conversationId>.<uuid>`, [bot_relay.rs](https://github.com/xai-org/grok-build/blob/main/crates/common/xai-tool-protocol/src/bot_relay.rs)).

## Architecture

```
 Desktop app (Electron)   iOS / Android   Slack app   X @bot   grok.com chat
          \                    |             |          |          /
           \___________________|_____________|__________|_________/
                                     |
             Cursor backend: Cursor account auth, connector OAuth tokens,
             usage meter, durable transcript store, routines/triggers
                                     |
             "Computer hub" JSON-RPC relay (bot.command, bot.roster,
             bot.status, bot.transcript.offbox, bot.usage, bot.event,
             bot.vncDescriptor ...)
                                     |
             Per-user "box": Firecracker microVM, US region, hibernates
             - in-box gateway + agent harness, one agent per Bot
             - shared /workspace, browser profile, CLI credentials
             - one screen per Bot (noVNC view / take control)
               |                                   |
     Cursor Cloud Agents                 user's desktop (optional):
     (separate computers for coding)     local exec, egress routing, security keys
```

Sources for the diagram: shared computer and screens ([computer docs](https://docs.x.ai/grok-bot/computer-and-apps)); Firecracker microVM per user ([security FAQ](https://docs.x.ai/grok-bot/security-faq)); connector tokens on Cursor's backend, US-only hosting ([security docs](https://docs.x.ai/grok-bot/security)); hub methods and "box" vocabulary ([methods.rs](https://github.com/xai-org/grok-build/blob/main/crates/common/xai-tool-protocol/src/methods.rs), [bot_relay.rs](https://github.com/xai-org/grok-build/blob/main/crates/common/xai-tool-protocol/src/bot_relay.rs)); Cloud Agents ([files docs](https://docs.x.ai/grok-bot/files-and-results)); local execution and egress routing ([approvals docs](https://docs.x.ai/grok-bot/approvals-security-and-privacy); [changelog 0.50.0](https://x.ai/changelog/bot#v0.50.0)). The diagram itself is our synthesis [INFERENCE].

- **Components and processes.**
  - Primary evidence on internals comes from the open Grok Build repo, which vendors Grok Bot's client protocol. `crates/common/xai-tool-protocol/src/methods.rs` lists "every JSON-RPC method understood by the computer hub", including `bot.command` ("Passthrough of an in-box gateway command"), `bot.vncDescriptor` ("Short-lived noVNC descriptor. May wake a hibernated box"), `bot.roster` (live agent roster read from the box), and "cold" reads that never wake the box (`bot.status`, `bot.transcript.offbox`, `bot.usage`) ([methods.rs](https://github.com/xai-org/grok-build/blob/main/crates/common/xai-tool-protocol/src/methods.rs)).
  - `bot_relay.rs` defines a closed error enum covering account linking between xAI and Cursor accounts (`never linked`, consent required, enterprise-managed, Privacy Mode (Legacy) refusing cloud-agent storage) and box states `box_waking`, `box_hibernated`, `box_migrating` ([bot_relay.rs](https://github.com/xai-org/grok-build/blob/main/crates/common/xai-tool-protocol/src/bot_relay.rs)).
  - The usage meter is "Percent-only by contract — no currency amounts cross the wire"; readings can exceed 100 under on-demand overage (same file).
  - Generated Swift and Kotlin clients plus a TypeScript package `frontend/packages/bot-relay-protocol/` consume the same fixtures ([fixtures README](https://github.com/xai-org/grok-build/blob/main/crates/common/xai-tool-protocol/fixtures/bot_relay/README.md)).
  - `crates/common/xai-computer-hub-core/src/bot_tools.rs` defines "hub-synthesized Grok Bot harness tools": `bot_create_agent`, `bot_list_agents`, `bot_send_prompt` (with `on_busy` supersede/reject/queue), transcript readers, `bot_await_turn`, `bot_search_agents`, `bot_voice_call_plan` ([bot_tools.rs](https://github.com/xai-org/grok-build/blob/main/crates/common/xai-computer-hub-core/src/bot_tools.rs)). These are the primitives behind bot-to-bot messaging and handoff [INFERENCE].
- **Tech stack.**
  - Desktop: Electron 42.1.0 per the third-party reconstruction (secondary evidence: [PROVENANCE.md](https://github.com/b-nnett/grok-bot-0.18-reconstructed/blob/main/PROVENANCE.md)). Its module map names `electron-main`, `host` (gateway server, roster, automations, box, connectors), `node-agent-coordinator`, `box-exec-daemon`, `local-exec-daemon`, and packages such as `agent-core`, `agent-transcript`, `agent-summarization`, `cursor-plugins`, and `mcp-core` ([source/ tree](https://github.com/b-nnett/grok-bot-0.18-reconstructed/tree/main/source)). Dependencies include Connect RPC and protobuf ([package.json](https://github.com/b-nnett/grok-bot-0.18-reconstructed/blob/main/package.json)).
  - Linux desktop ships deb and rpm packages ([changelog 0.45.0](https://x.ai/changelog/bot#v0.45.0)).
- **Agent loop / harness.**
  - Own Cursor-built harness running per Bot inside the box; the user cannot swap engines.
  - Bots spawn subagents and Cursor Cloud Agents; a "Project" is "a Cloud Agent that plans the work and runs its own agents" ([changelog 0.57.0](https://x.ai/changelog/bot#v0.57.0)).
  - Bot computers also have the Cursor CLI (`agent -p`) available (user report, [forum](https://forum.cursor.com/t/grok-bot-computer-cursor-cli-agent-p-stuck-on-connection-lost-reconnecting-since-oct-19-codex-works-from-same-machine/175385)).
  - No ACP is used between Bot clients and the box; the wire is the hub's JSON-RPC relay. ACP belongs to Grok Build, see below.
- **Models and auth.**
  - "Cursor manages model selection. There is no customer-facing model picker, and the serving mix can change over time with no fixed vendor set guaranteed"; usage analytics show the serving model, including failovers ([security docs](https://docs.x.ai/grok-bot/security)).
  - When a model is unavailable in a region, "Bots fall back to Grok" ([changelog 0.70.2](https://x.ai/changelog/bot#v0.70.2)). This implies non-Grok models serve some turns [INFERENCE].
  - Auth is a Cursor account (SSO/SAML via Cursor), optionally linked to a Grok/X account ([security docs](https://docs.x.ai/grok-bot/security)).
- **Execution environment.**
  - One Firecracker microVM per user ([security FAQ](https://docs.x.ai/grok-bot/security-faq)). Durable disk, hibernation when idle, daily encrypted control-plane backups, image updates preserve files ([security docs](https://docs.x.ai/grok-bot/security)).
  - Recover/Update/Reset controls exist; Reset rebuilds from the last snapshot ([computer docs](https://docs.x.ai/grok-bot/computer-and-apps)).
  - Enterprise "Allow Sudo on Bot Computers" and Team Setup scripts customize the image ([security docs](https://docs.x.ai/grok-bot/security)).
  - A user can register several computers; local desktops count as computers for local execution ([changelog 0.29.0](https://x.ai/changelog/bot#v0.29.0), [0.68.0](https://x.ai/changelog/bot#v0.68.0)).
- **State and storage.**
  - Transcripts are stored server-side in a durable store that can be read without waking the box ([bot_relay.rs](https://github.com/xai-org/grok-build/blob/main/crates/common/xai-tool-protocol/src/bot_relay.rs)).
  - Files, browser sessions and saved logins live on the box disk; connector OAuth tokens never touch the box ([security docs](https://docs.x.ai/grok-bot/security)).
  - Personal Auto-review rules are stored on the desktop and synced to the box ([approvals docs](https://docs.x.ai/grok-bot/approvals-security-and-privacy)).
  - Grok Bot "requires data storage and does not support Legacy Privacy Mode" (same page).
- **Remote and mobile access.**
  - Everything is cloud-first, so mobile is a thin client over the same backend ([mobile docs](https://docs.x.ai/grok-bot/mobile)).
  - The live screen is streamed via noVNC descriptors ([methods.rs](https://github.com/xai-org/grok-build/blob/main/crates/common/xai-tool-protocol/src/methods.rs)).
  - Box hostnames sit under `*.cursorvm.com` ([security FAQ](https://docs.x.ai/grok-bot/security-faq)).
  - The desktop can act as an egress proxy for the box ("Route egress through this desktop", [changelog 0.50.0](https://x.ai/changelog/bot#v0.50.0)) and as a WebAuthn bridge for hardware keys ([approvals docs](https://docs.x.ai/grok-bot/approvals-security-and-privacy)).
- **Extension surface.**
  - Plugins from Connect Apps (connectors plus packaged skills), up to 200 skills from installed plugins ([changelog 0.71.2](https://x.ai/changelog/bot#v0.71.2)).
  - Private skills library shared by all Bots; custom MCP servers (Remote HTTPS or Command); Team Secrets injected as environment variables ([skills docs](https://docs.x.ai/grok-bot/skills-routines-and-automations); [Team Bots docs](https://docs.x.ai/grok-bot/team-bots); [changelog 0.59.0](https://x.ai/changelog/bot#v0.59.0)).
  - Enterprise Admin API for computers ([changelog 0.71.2](https://x.ai/changelog/bot#v0.71.2)).
  - No public Grok Bot API or SDK found (unknown).

### Grok Build (companion coding CLI)

| Aspect | Fact |
|---|---|
| What | "SpaceXAI's terminal-based AI coding agent", full-screen Rust TUI, headless mode, ACP mode ([README](https://github.com/xai-org/grok-build/blob/main/README.md)) |
| License | Apache-2.0; repo "synced periodically from the SpaceXAI monorepo"; "does not accept external pull requests" ([CONTRIBUTING.md](https://github.com/xai-org/grok-build/blob/main/CONTRIBUTING.md)) |
| Repo stats (as of 2026-10-20) | 27,460 stars, 5,192 forks, created 2026-07-14, last push 2026-09-29, 1 contributor, 0 GitHub releases (`gh api repos/xai-org/grok-build`) |
| Latest version | 1.0.62, 2026-10-16 ([Build changelog](https://x.ai/changelog/build)) |
| Protocols | `grok agent stdio` runs it "as an ACP agent over JSON-RPC on stdin/stdout"; headless `-p` with `plain`, `json`, `streaming-json` output ([headless docs](https://docs.x.ai/build/cli/headless-scripting)) |
| Features | MCP, plugins and marketplaces, hooks, subagents, worktrees, sandbox profiles, sessions, Claude Code flag aliases and `grok import` of Claude Code sessions ([CLI reference](https://docs.x.ai/build/cli/reference)); custom OpenAI-compatible models via `~/.grok/config.toml` ([overview](https://docs.x.ai/build/overview)) |
| Plugin format | skills, commands, agents, hooks, `.mcp.json`, `.lsp.json`, indexed by `.grok-plugin/marketplace.json` ([xai-org/plugin-marketplace](https://github.com/xai-org/plugin-marketplace)) |
| Relation to Grok Bot | Separate product. Its repo contains the Grok Bot computer-hub SDK and bot-relay protocol (above), so Grok Build shares infrastructure crates with Grok Bot. The hub tool descriptions suggest any hub-connected harness can create and message Grok Bots [INFERENCE]. Grok Bot itself delegates coding to Cursor Cloud Agents, not to Grok Build (docs mention only Cloud Agents). |

### Unofficial reconstructions (secondary evidence only)

| Project | What it shows | Stats (as of 2026-10-20) |
|---|---|---|
| [b-nnett/grok-bot-0.18-reconstructed](https://github.com/b-nnett/grok-bot-0.18-reconstructed) | Readable TypeScript reconstruction of the 0.18.0 macOS app's Electron, host, coordinator, local-exec and protocol layers. Adds an inference router (Cursor, Claude Code, Codex, OpenRouter) and a local Docker sandbox "in place of the remote box". The renderer is kept as minified shipped code. No license; "No upstream source-code license is implied". It preserves the original installers via Git LFS, so redistribution risk is high. | 3,532 stars, 3,655 forks, TypeScript, created and last pushed 2026-08-23 |
| [OnlyTerp/opengrok](https://github.com/OnlyTerp/opengrok) | MIT "config sidecar" that injects a per-agent model picker into an installed Grok Bot and routes to OpenAI-compatible endpoints (Claude, GLM, Qwen, Gemini, DeepSeek, local). It claims a 256k context window and "wire-captures" (unverified). | 492 stars, 65 forks, JavaScript, last push 2026-09-22 |

Both were found via [grokbotguide.com/open-source](https://grokbotguide.com/open-source/) (third-party directory). They show that the client-to-box contract is stable enough to intercept, and that users want BYO models and local sandboxes [INFERENCE].

## Capabilities in detail

- **Persistent Bots and identity.**
  - Bots have a name, label, description, avatar and color; duplicate, pin, hide and delete are available ([bots docs](https://docs.x.ai/grok-bot/bots)).
  - There is a starred primary Bot ([0.66.0](https://x.ai/changelog/bot#v0.66.0)).
  - Bots can claim their own email address (users report `@mail.grokbot.com`, [forum](https://forum.cursor.com/t/grok-bot-email-outbound-works-but-inbound-mail-is-not-received/175361)). Mail sent from that address waits on a draft card, and `name+tag@` aliases can trigger routines ([0.70.2](https://x.ai/changelog/bot#v0.70.2), [0.71.2](https://x.ai/changelog/bot#v0.71.2)).
  - Bots have no separate machine identity: "Bots act as the signed-in member" ([security docs](https://docs.x.ai/grok-bot/security)).
- **Memory.**
  - Bots keep "stable preferences, role context, and summaries of prior work". Conversations and learned context stay separate per Bot; shared files, browser sessions and handoffs move context between Bots ([overview](https://docs.x.ai/grok-bot/overview)).
  - Memory writes are not reviewed by Auto Review ([security docs](https://docs.x.ai/grok-bot/security)).
  - Duplicating a Bot does not copy learned memory ([bots docs](https://docs.x.ai/grok-bot/bots)).
  - Users report each Bot is "one unbounded thread", with no compaction or new-session primitive (forum feature request, 33 posts, [thread](https://forum.cursor.com/t/grok-bot-prune-compact-an-agent-s-context-without-creating-a-new-bot/168333)).
- **Routines and automation.**
  - Skills are reusable instructions; routines bind a skill to one Bot with a schedule or event trigger ([skills docs](https://docs.x.ai/grok-bot/skills-routines-and-automations)).
  - Limits: up to 50 routines per Bot, schedules at least 5 minutes apart, the 20 most recent run records kept, and Test run performs real work (same page).
  - Triggers: webhooks with payload ([0.21.0](https://x.ai/changelog/bot#v0.21.0), [0.27.0](https://x.ai/changelog/bot#v0.27.0)); Microsoft Teams, Linear, Sentry and PagerDuty ([0.17.0](https://x.ai/changelog/bot#v0.17.0)); a single GitHub PR that self-removes on merge ([0.25.0](https://x.ai/changelog/bot#v0.25.0)); and email tags.
  - Routines may be paused after long absence to control unattended usage ([skills docs](https://docs.x.ai/grok-bot/skills-routines-and-automations)).
- **Multi-bot collaboration.**
  - Async bot-to-bot messages wake the receiver ([chat docs](https://docs.x.ai/grok-bot/chat-and-collaboration)).
  - Group chats of 2 to 6 Bots support @mentions, @everyone and Reply-to-Bot. Approvals, secret requests and drafts do not appear in groups, and handoff messages are text-only (same page).
  - Stopping a Bot also stops Bots it handed work to and Cloud Agents it started ([0.56.0](https://x.ai/changelog/bot#v0.56.0)).
  - Admins can disable bot-to-bot messaging ([0.71.2](https://x.ai/changelog/bot#v0.71.2)).
- **Coding workspace.**
  - The box has a terminal and `/workspace`. Repo access covers GitHub, GitLab, Bitbucket and Azure DevOps ([0.49.0](https://x.ai/changelog/bot#v0.49.0)), and GitHub supports releases, tags, branches and multi-file PR review ([0.56.0](https://x.ai/changelog/bot#v0.56.0)).
  - Cloud Agent results are copied back into chat ([files docs](https://docs.x.ai/grok-bot/files-and-results)).
  - There are no diff or worktree views in the Bot UI (not found in docs).
- **Browser and computer use.**
  - A shared persistent browser and desktop. The user can watch or take control, and the Bot hands over CAPTCHAs, 2FA and payments ([computer docs](https://docs.x.ai/grok-bot/computer-and-apps)).
  - Secure Forms, chat forms and 1Password (Mac) are supported ([0.44.0](https://x.ai/changelog/bot#v0.44.0), [0.53.0](https://x.ai/changelog/bot#v0.53.0)).
  - Purchases go through Stripe Link or X Money with an approval card ([0.30.0](https://x.ai/changelog/bot#v0.30.0), [0.70.2](https://x.ai/changelog/bot#v0.70.2)).
  - Built-in site guides cover popular travel, food, shopping and shipping sites ([0.59.0](https://x.ai/changelog/bot#v0.59.0)).
  - Bots can read X without connecting an X account ([computer docs](https://docs.x.ai/grok-bot/computer-and-apps)).
- **Connectors.**
  - Installed connectors are account-wide, not per Bot ([computer docs](https://docs.x.ai/grok-bot/computer-and-apps)).
  - Named connectors include Gmail, Outlook, Slack, Google Drive, OneDrive, GitHub, Notion, Figma, Canva, Stripe, QuickBooks Online, Glean (MCP), Vercel, Datadog and Xero ([changelog 0.53.0-0.71.2](https://x.ai/changelog/bot)).
  - The connector policy and the network policy are separate layers ([security FAQ](https://docs.x.ai/grok-bot/security-faq)).
- **Channels.**
  - Desktop and mobile apps, Slack (Team Bots), X `@bot`, Bot email inbox, voice, and the grok.com relay; see Product and UX.
  - Microsoft Teams appears only as a trigger and admin-checklist item ([0.55.0](https://x.ai/changelog/bot#v0.55.0)).
  - No WhatsApp, Telegram, SMS or iMessage channel was found (unknown).
- **Voice.** Dictation, live voice chat, Bot voice memos with word-synced transcripts, and Team Bot voice chat ([chat docs](https://docs.x.ai/grok-bot/chat-and-collaboration); [0.57.0](https://x.ai/changelog/bot#v0.57.0), [0.65.0](https://x.ai/changelog/bot#v0.65.0)). There is also a voice-call plan tool in the hub ([bot_tools.rs](https://github.com/xai-org/grok-build/blob/main/crates/common/xai-computer-hub-core/src/bot_tools.rs)).
- **Mobile.** iOS/iPadOS 18+ and Android 9+. The mobile apps support approvals, take-over and routine review; editing and testing routines and teach-by-demonstration need the desktop ([mobile docs](https://docs.x.ai/grok-bot/mobile)).
- **Team features (Team Bots, beta 0.61.0, 2026-09-26).**
  - Each teammate has a private chat with a shared Team Bot. Team memory plus per-person notes, and up to 25 encrypted secrets that the model never sees (redacted as `[REDACTED]`) ([Team Bots docs](https://docs.x.ai/grok-bot/team-bots)).
  - OAuth plugins act as the asker ([Team Bots docs](https://docs.x.ai/grok-bot/team-bots)).
  - A Team Bot can have its own Slack app with DMs, @mentions and thread replies ([0.61.0](https://x.ai/changelog/bot#v0.61.0)). Slack approvals ([0.63.0](https://x.ai/changelog/bot#v0.63.0)), managers ([0.64.0](https://x.ai/changelog/bot#v0.64.0)) and Slack user-group mentions ([0.68.1](https://x.ai/changelog/bot#v0.68.1)) came later.
  - Slack channel conversations run on a separate shared computer per Team Bot. "In a conversation where nobody can answer an approval card, the Bot runs without Auto-review" unless the team enforces it ([Team Bots docs](https://docs.x.ai/grok-bot/team-bots)).

## Security and trust model

- **Isolation.**
  - Isolation is per user, not per Bot. Each user gets "a dedicated Firecracker microVM with its own kernel, memory, and virtual devices"; "When a workload needs its own computer and credential set, give it its own Cursor user" ([security FAQ](https://docs.x.ai/grok-bot/security-faq)).
  - "Do not use separate Bots as a security boundary" ([approvals docs](https://docs.x.ai/grok-bot/approvals-security-and-privacy)).
- **Approvals.**
  - Auto Review is "an independent review model" covering shell commands, plugin calls, computer use, automation writes, and Cloud Agent/subagent delegation. It does not cover memory writes or most settings ([security docs](https://docs.x.ai/grok-bot/security)).
  - Ask-first rules win over allow rules. Approvals from unattended work expire after about 10 minutes ([approvals docs](https://docs.x.ai/grok-bot/approvals-security-and-privacy)).
  - Before irreversible actions (send, post, buy, delete), a Bot checks the user's own messages for approval ([0.70.2](https://x.ai/changelog/bot#v0.70.2)). After a bank or brokerage connector returns data, the Bot asks before sharing it (same release).
- **Credentials.**
  - Connector tokens stay on Cursor's backend. Secure secret requests are masked and kept from the model ([security docs](https://docs.x.ai/grok-bot/security)).
  - Users report saved secrets printed in plain text via `env` on the box (some values masked, some not) and ask for platform-level masking (forum, 2026-10-20, [thread](https://forum.cursor.com/t/feature-request-mask-secret-values-in-bot-shell-output/175384)).
  - A forum bug titled "SECURITY ISSUE - Grok Bot sessions can't be fully signed out remotely" was listed on the grok-bot tag (title only seen; [tag page](https://forum.cursor.com/tag/grok-bot/416)).
- **Network.**
  - Allow-all by default. Enterprise-only allowlists exist, and an allowlist turns web search off ([security FAQ](https://docs.x.ai/grok-bot/security-faq)).
  - Egress uses shared static IPs that identify Grok Bot traffic, with no dedicated IPs ([security docs](https://docs.x.ai/grok-bot/security)).
- **Prompt injection.** Outside content "is marked as untrusted data when presented to the model". The defenses "reduce, but do not eliminate, risk" ([security docs](https://docs.x.ai/grok-bot/security)).
- **Logging and audit.** Audit logs, Action Recording (90-day retention, scrubbed commands), OpenTelemetry export and opt-in conversation-content export are Enterprise-only ([security docs](https://docs.x.ai/grok-bot/security)).
- **Data.**
  - Computers run in the US only ([security docs](https://docs.x.ai/grok-bot/security)).
  - Zero data retention follows Cursor's provider agreements. The team model allowlist "enforcement is not guaranteed" (same page).
  - Certifications: ISO/IEC 27001 and 42001 (Anysphere scope includes Grok Bot) ([security docs](https://docs.x.ai/grok-bot/security)). Cursor earned AIUC-1 on 2026-08-13 per its blog index ([Cursor blog](https://cursor.com/blog/joining-spacex)).
  - Google Play data-safety: may share personal and financial info with third parties ([Play listing](https://play.google.com/store/apps/details?id=ai.x.grok.bot)).
- **Incidents.**
  - A Grok-wide outage was attributed to a Memphis data center on 2026-09-04 (press: [PCMag AU](https://au.pcmag.com/ai/119676/chatgpt-claude-gemini-and-more-are-all-down-right-now)). Its impact on Grok Bot is unknown.
  - Many current forum reports concern computer connectivity ("Can't reach your computer"), login loops on 0.71.2, and reset hangs ([tag page](https://forum.cursor.com/tag/grok-bot/416)).
  - No disclosed data breach or CVE was found (unknown).

## Traction and momentum

- Release history: 51 changelog entries from 0.17.0 (2026-08-12) to 0.71.2 (2026-10-14), roughly 6 per week. The changelog does not list builds before 0.17.0; the launch-day build is unknown. The changelog stops at 0.71.2 as of 2026-10-20 (our brief expected 0.70.x as latest; 0.71.2 is newer). Timeline below.
- Mobile:
  - iOS: 4.9 stars from 12K ratings, #12 Productivity, version 1.16.0, "Developer X Corp." ([App Store](https://apps.apple.com/us/app/grok-bot/id6794501026), as of 2026-10-20).
  - Android: 4.7 stars from 13.1K reviews, 1M+ downloads, updated 2026-10-19 ([Google Play](https://play.google.com/store/apps/details?id=ai.x.grok.bot), as of 2026-10-20).
- Community: an active `grok-bot` tag on the Cursor forum (dozens of topics updated per day) ([tag page](https://forum.cursor.com/tag/grok-bot/416)); third-party share catalogs, guides and a Chinese handbook ([grokbotguide.com](https://grokbotguide.com/open-source/)).
- Press:
  - InfoQ, 2026-08-17: "combines persistent agents, workflow memory, and multi-agent coordination into a consumer-facing product"; it quotes a user saying Grok Bot "replaced OpenClaw, Hermes, & my local model" (press: [InfoQ](https://www.infoq.com/news/2026/08/grok-bot-agent/)).
  - Third-party reviews praise teach-a-task and memory and flag the shared computer and price gate (third-party: [eesel](https://www.eesel.ai/blog/grok-bot-review), [Layer3 Labs](https://www.layer3labs.io/guides/grok-bot-review)).
  - A Mashable review was searched for and not found (unknown).
- Launch gating changed: press reported launch access limited to SuperGrok Heavy, Cursor Ultra and Cursor Teams Premium (press: [InfoQ](https://www.infoq.com/news/2026/08/grok-bot-agent/)); Cursor Pro, SuperGrok and X Premium+ were added in [0.27.0 on 2026-08-25](https://x.ai/changelog/bot#v0.27.0); all Enterprise teams in [0.40.0 on 2026-09-03](https://x.ai/changelog/bot#v0.40.0). The launch post now lists the broader set [INFERENCE: edited after launch].
- Business model: no standalone SKU; Grok Bot is a bundled entitlement that drives Cursor, SuperGrok and X subscriptions.

### Pricing and plan matrix (as of 2026-10-20)

| Path | Grok Bot | Usage | Source |
|---|---|---|---|
| The X Subscription Free / Plus ($8/mo) | not included | n/a | [x-subscription pricing](https://docs.x.ai/x-subscription/pricing) |
| The X Subscription Premium $30/mo ($300/yr) | included | shared weekly pool with Grok and Cursor ("4x") | same |
| The X Subscription Super $100/mo ($1000/yr) | included | larger pool ("15x") | same |
| The X Subscription Ultra $200/mo ($2000/yr) | included | larger pool ("50x") | same |
| Teams on The X Subscription | Premium $30, Super $100, Ultra $200 per seat; every paid seat | seat's weekly pool | same |
| Legacy Cursor Pro / Pro+ / Ultra | included | tiers ascending, weekly reset | [Cursor plans help](https://cursor.com/help/grok-bot/plans) |
| Legacy Cursor Teams (self-serve) | every member | Teams allowance, on-demand on by default | same |
| Linked SuperGrok / SuperGrok Plus / SuperGrok Heavy / X Premium+ | usage grant on a Cursor account | Pro = SuperGrok = X Premium+; Pro+ = SuperGrok Plus; Ultra = SuperGrok Heavy; grants do not stack ("uses whichever one grants more") | same |
| Grok Business seat | via "Sign in with Grok" | matches seat license | same |
| Cursor Enterprise / Grok Enterprise | via account team | admin-managed | same |
| Free trial | usage credit plus 7-day window, metered by agent steps and tokens; "not restored" if one run consumes it | n/a | same |

Overage: legacy plans use on-demand billing through Cursor with a monthly limit that "is not a hard stop in the middle of a run"; The X Subscription uses prepaid top-ups. The SuperGrok link is "permanent once created", and unifying into The X Subscription "can't be undone" ([Cursor plans help](https://cursor.com/help/grok-bot/plans); [X Subscription overview](https://docs.x.ai/x-subscription/overview)). Third-party models in Cursor bill at API list prices from first use ([X Subscription overview](https://docs.x.ai/x-subscription/overview)).

### Changelog timeline (complete, from [x.ai/changelog/bot](https://x.ai/changelog/bot))

| Date | Version | Headline features |
|---|---|---|
| 2026-08-11 | launch (beta) | Announcement; desktop + iOS; separate Grok Bot usage ([post](https://x.ai/news/introducing-grok-bot)) |
| 2026-08-12 | 0.17.0 | Routine triggers from MS Teams, Linear, Sentry, PagerDuty; Auto-review asks before unrequested tasks; SuperGrok Heavy on Standard team seats |
| 2026-08-12 | 0.18.0 | Cancel Trial (removes remaining trial credits) |
| 2026-08-14 | 0.19.0 | Manage Plan; upgrade to Ultra or link SuperGrok Heavy when usage runs out; "Agent" renamed "Bot"; local command requests hide command until shown |
| 2026-08-14 | 0.20.0 | Dictation (Cmd/Ctrl+D); modifier keys in computer use; Bot manages Cloud Agents on request |
| 2026-08-19 | 0.21.0 | App languages (CJK, Hindi, ES, PT, FR, DE, PL); webhook-triggered routines; Enterprise Team Setup scripts and network access policy |
| 2026-08-20 | 0.22.0 | Team setup and translation fixes |
| 2026-08-21 | 0.24.0 | Setting/plugin deep links; multi-team sign-in; voice input auto-detects language |
| 2026-08-25 | 0.25.0 | Multi-select questions; on-demand limit None/Fixed/Unlimited; single-PR GitHub routines; Premium seat upgrade path |
| 2026-08-25 | 0.26.0 | App menu with updates; right-to-left typing |
| 2026-08-25 | 0.27.0 | Cursor Pro, SuperGrok, X Premium+ access; webhook routines receive request body |
| 2026-08-26 | 0.28.0 | Russian, Turkish, Italian, Swedish |
| 2026-08-27 | 0.29.0 | Settings → Computer with Always allow / Ask / Never per computer; replies in Grok phone notifications |
| 2026-08-28 | 0.30.0 | Share Bot as template (team or public); Link purchase cards; Enterprise Action Recording; Arabic/Hebrew RTL and more languages; cross-computer approval |
| 2026-09-01 | 0.31.0 | Onboarding suggests Bots; team invites; admin Setup Checklist; HTML previews; Cloud Agent Open in Web/Cursor; >50 Bots |
| 2026-09-01 | 0.32.0 | IME typing on the Bot's computer; team setup flow |
| 2026-09-01 | 0.33.0 | Enterprise Group Access and team trials; Link wallet card picker |
| 2026-09-01 | 0.34.0 | PR status previews; Bots can create Bots in sidebar sections |
| 2026-09-02 | 0.35.0 | Longer jobs and page-by-page browsing; admin invite links; shared-Bot fixes |
| 2026-09-02 | 0.36.0 | Routine runs open in their own chat; Always allow for local execution works |
| 2026-09-03 | 0.37.0 | Setup asks which daily tools you use; template share menu; Enterprise trial countdown |
| 2026-09-03 | 0.38.0 | Enterprise Group Access placement |
| 2026-09-03 | 0.39.0 | Vietnamese, Indonesian; localized greetings |
| 2026-09-03 | 0.40.0 | Available to every Enterprise team; Urdu, Thai, Bengali; Audit Logs for Bot events |
| 2026-09-04 | 0.41.0 | Marketplace lists Bots plus plugins; Verified badge for first-party Bots |
| 2026-09-06 | 0.44.0 | Chat forms that fill pages for sign-ins; message timestamps; Mac AutoFill; local-computer requests in chat |
| 2026-09-08 | 0.45.0 | Email and Slack draft cards (Send/Discard); Enterprise-enforced Auto-review and team rules |
| 2026-09-09 | 0.46.0 | Usage & Billing with weekly usage and monthly on-demand limit; chat renaming |
| 2026-09-09 | 0.48.0 | Multiple accounts on one desktop; unified Marketplace homepage; Enterprise Conversation Insights |
| 2026-09-11 | 0.49.0 | Repo access cards for GitHub, GitLab, Bitbucket, Azure DevOps; clickable file paths |
| 2026-09-11 | 0.50.0 | Route the Bot computer's web egress through your own desktop |
| 2026-09-14 | 0.51.0 | Setup creates first Bot; delete routines; Bot can change own title and avatar |
| 2026-09-15 | 0.52.0 | Pause/resume routines; built-in GitHub connection |
| 2026-09-15 | 0.53.0 | 1Password sign-in (Mac); uploads to Drive/OneDrive/Gmail; computer uses your time zone |
| 2026-09-16 | 0.54.0 | Search palette upgrades; HEIC; Enterprise Delete VMs and Data |
| 2026-09-16 | 0.55.0 | Dashboard Setup Checklist (Slack or MS Teams, network); form-filling fixes |
| 2026-09-17 | 0.56.0 | Deeper GitHub (releases, branches, multi-file PR review); clearer approval cards; spreadsheet previews; Stop cascades to delegated Bots and Cloud Agents |
| 2026-09-18 | 0.57.0 | Projects (Cloud Agent that plans and runs its own agents); voice-memo word sync; richer link previews; expanded Enterprise audit logs |
| 2026-09-22 | 0.58.0 | Czech, Danish, Finnish, Hungarian, Norwegian; Enterprise Terminate Inactive Computers (30 days); Action Recording redaction |
| 2026-09-25 | 0.59.0 | Enterprise Team Secrets as env vars; busy Bot answers user first; built-in site guides |
| 2026-09-26 | 0.60.0 | Outlook draft cards; more reliable replies |
| 2026-09-26 | 0.61.0 | Team Bots (beta): publish to team, per-person private chats, team memory, Slack app with threads/channels, admin-added Team Bots |
| 2026-09-28 | 0.62.0 | Quote-to-prompt (Cmd/Ctrl+L), lists, spell check; Library tab; admin Team Bot management |
| 2026-09-29 | 0.63.0 | Slack approval cards; Team Bot in Slack can message your own Bots; faster browsing |
| 2026-09-30 | 0.64.0 | Disable drafts per Bot (send directly); Team Bot managers; refreshed avatars |
| 2026-09-30 | 0.65.0 | Team Bot voice chat; automatic updates on by default |
| 2026-10-02 | 0.66.0 | Proactive primary Bot offers to take work; Slack status line |
| 2026-10-02 | 0.67.0 | Marketplace renamed Connect Apps; Bot templates on the web; Team Bot links on x.ai |
| 2026-10-05 | 0.68.0 | Marathi, Tamil, Telugu, Swahili, Hausa; remove computers; Gmail send-as; Custom Rules naming |
| 2026-10-07 | 0.68.1 | Slide decks (PowerPoint/Google Slides); formatted emails; Bot-colored chats; Slack user-group mentions; 1920x1200 computer screen |
| 2026-10-11 | 0.70.2 (incl. 0.69.0-0.70.1) | Bot-owned email addresses; X search without connecting X; in-chat app cards (Figma, Notion, Canva); pay with X Money or Stripe Link; template finder; Glean MCP, QuickBooks; irreversible-action self-check; regional model fallback to Grok |
| 2026-10-14 | 0.71.2 (incl. 0.71.0-0.71.1) | Tagged email aliases trigger routines; admins can disable bot-to-bot messaging; Enterprise Manage Bot Computers + Admin API; 250 MB files / 1 GB video, 20 attachments; 200 plugin skills; low-disk cleanup prompt |

Versions 0.23, 0.42, 0.43 and 0.47 are absent from the changelog.

## Strengths

- **Hosted box.** Always-on work with zero user setup: the cloud computer, browser and persistent logins make "close the laptop" true ([overview](https://docs.x.ai/grok-bot/overview)).
- **Familiar coworker UX.** Messenger roster, avatars, group chats, voice memos and draft/approval cards. Users rate it 4.7 to 4.9 on the app stores.
- **Distribution.** Bundled into Cursor, SuperGrok and X subscriptions, with entry points on X (`@bot`), grok.com and Slack.
- **Shipping velocity.** About 6 desktop releases per week, each with detailed user-facing release notes.
- **Enterprise depth for a beta.** SSO/SCIM, network allowlists, Team Setup scripts, Team Secrets, enforced Auto Review, OTel export, audit logs, ISO certifications ([security docs](https://docs.x.ai/grok-bot/security)).
- **Credential design.** Model-invisible secrets and backend-held OAuth tokens, plus Team Bots acting as the asker.

## Weaknesses and risks

- **Shared computer.** One computer per user is the opposite of per-Bot isolation. All Bots share cookies, files and CLI credentials, and the docs tell users to create separate accounts for isolation ([security FAQ](https://docs.x.ai/grok-bot/security-faq)). Some marketing implied per-Bot machines; this caused confusion (third-party: [agenticbrew](https://www.agenticbrew.ai/news/d719f20d-2613-471e-8f6b-dd77403247f4/grok-bot-ai-agent)).
- **No model choice or BYO.** There is no model picker, BYO key or local model, and the model allowlist may not be enforced ([security docs](https://docs.x.ai/grok-bot/security)). Hosting is US-only with no self-hosting.
- **Usage burn and opaque metering.**
  - The meter is percent-only ([bot_relay.rs](https://github.com/xai-org/grok-build/blob/main/crates/common/xai-tool-protocol/src/bot_relay.rs)).
  - Bot-to-bot loops burned a weekly allowance; staff said "each bot-to-bot message runs a turn that counts toward your weekly usage" and asking Bots to stay quiet "is only a hint" ([forum](https://forum.cursor.com/t/grok-bot-weekly-usage-hits-100-after-bot-to-bot-reviews-the-user-asked-to-stop/170271)). Another user reported 5 agents talking for 7 hours on on-demand spend (same thread).
  - There is no quantified allowance per tier ([forum question](https://forum.cursor.com/t/grok-bot-pro-vs-pro/175187)).
- **Billing complexity.** Users report confusion across Cursor, SuperGrok, X, Apple and Google channels ([App Store review, 2026-10-01](https://apps.apple.com/us/app/grok-bot/id6794501026)); access changed after the X Subscription rollout ([forum](https://forum.cursor.com/t/anyone-else-seeing-grok-bot-access-changes-after-the-unified-plans-rollout/175364)).
- **Reliability.** Users report "Can't reach your computer", login loops and reset hangs ([tag page](https://forum.cursor.com/tag/grok-bot/416)). Reviewers describe it as "a high school-level intern" that "gives up too easily" ([App Store review, 2026-09-03](https://apps.apple.com/us/app/grok-bot/id6794501026)).
- **Context growth.** Unbounded per-Bot threads with no compaction primitive ([forum](https://forum.cursor.com/t/grok-bot-prune-compact-an-agent-s-context-without-creating-a-new-bot/168333)).
- **Platform lock and corporate churn.** Two parent renames in three months and an irreversible account unification. The product depends on the Cursor account, cloud and Privacy Mode semantics.
- **Regional gaps.** `@bot` tagging is unavailable in the UK, EU, EEA and Australia ([tag docs](https://docs.x.ai/grok-bot/tag-on-x)).

## Ideas worth taking for Memoshi

- **Typed in-chat cards** (approval, draft, purchase, Secure Form, question, sign-in). They keep the messenger metaphor while making side effects reviewable. Adopt.
- **Wake vs. cold reads.** Split "cold" reads (status, transcript, usage) that never wake the compute from "warm" commands that do. This is cheap and keeps the UI fast while boxes hibernate ([methods.rs](https://github.com/xai-org/grok-build/blob/main/crates/common/xai-tool-protocol/src/methods.rs)). Adopt.
- **Closed error enum with box states** (`box_waking`, `box_hibernated`, `box_migrating`) plus a replay fixture corpus shared by TS, Swift and Kotlin clients. It gives one stable contract across desktop and mobile. Adopt.
- **Bot-tool vocabulary.** `bot_send_prompt` with `on_busy` (supersede/reject/queue) and `bot_await_turn` handles are a clean bot-to-bot messaging API. Adopt.
- **Per-Bot computers or explicit profiles.** Grok Bot's shared-computer model is its biggest trust gap. Offer per-Bot browser profiles or credential scopes as a differentiator. Adapt.
- **Budgets for bot-to-bot traffic.** Use hard per-thread turn caps and loop detection, not prompt hints, since Grok Bot users lost weekly quotas this way. Avoid their failure.
- **Memory split.** Separate identity, working set and archive, with Compact and New session primitives; this is what power users are asking Grok Bot for ([forum](https://forum.cursor.com/t/grok-bot-prune-compact-an-agent-s-context-without-creating-a-new-bot/168333)). Adopt.
- **Secrets the model cannot read.** Reference secrets by name, redact `[REDACTED]` in all tool output, and enforce a minimum length so redaction is reliable ([Team Bots docs](https://docs.x.ai/grok-bot/team-bots)). Also mask environment listings at the platform level, the gap users found. Adopt and harden.
- **Team Bot pattern.** One shared configuration and team memory, private per-person notes, and plugins that act as the asker. This is a good household/team model. Adopt.
- **Approval routing.** Expire approvals from unattended work after a timeout and offer "Always allow this in the future" from the expired card. Adopt.
- **Desktop as egress proxy and hardware-key bridge** for the cloud box. This solves datacenter-IP blocking and passkeys. Consider.
- **Draft-before-send by default,** with a per-Bot "disable drafts" escape hatch. Adopt.

## Open questions

- Which models serve Bot turns, and in what mix? The docs refuse to commit. One could check usage analytics in a paid account or the OpenGrok wire captures (secondary).
- Exact weekly allowance per tier: unknown. Measure with a test account via `bot.usage` percentage deltas per task.
- Is the in-box agent harness related to Grok Build's `xai-grok-shell` runtime, or to Cursor's own agent? The open crates share the hub SDK, but the in-box gateway source is not public. Diffing reconstructed 0.18.0 `box-exec-daemon` against grok-build crates could tell.
- Android launch date and pre-0.17.0 builds: not in the changelog; app-store version history might show them.
- Status of the "sessions can't be fully signed out remotely" security bug: thread not read in full.
- Whether teach-a-task is generally available or still gradual ("may be enabled gradually", [skills docs](https://docs.x.ai/grok-bot/skills-routines-and-automations)).

## Sources

1. https://x.ai/news/introducing-grok-bot
2. https://x.ai/changelog/bot
3. https://docs.x.ai/grok-bot/overview
4. https://docs.x.ai/grok-bot/bots
5. https://docs.x.ai/grok-bot/computer-and-apps
6. https://docs.x.ai/grok-bot/skills-routines-and-automations
7. https://docs.x.ai/grok-bot/chat-and-collaboration
8. https://docs.x.ai/grok-bot/files-and-results
9. https://docs.x.ai/grok-bot/mobile
10. https://docs.x.ai/grok-bot/tag-on-x
11. https://docs.x.ai/grok-bot/team-bots
12. https://docs.x.ai/grok-bot/approvals-security-and-privacy
13. https://docs.x.ai/grok-bot/security
14. https://docs.x.ai/grok-bot/security-faq
15. https://docs.x.ai/grok-bot/teams-and-enterprises
16. https://cursor.com/help/grok-bot/plans
17. https://docs.x.ai/x-subscription/overview
18. https://docs.x.ai/x-subscription/pricing
19. https://docs.x.ai/x-subscription/grok-bot
20. https://docs.x.ai/build/overview
21. https://docs.x.ai/build/cli/reference
22. https://docs.x.ai/build/cli/headless-scripting
23. https://x.ai/changelog/build
24. https://github.com/xai-org/grok-build (README.md, CONTRIBUTING.md, crates/common/xai-tool-protocol/src/methods.rs, crates/common/xai-tool-protocol/src/bot_relay.rs, crates/common/xai-tool-protocol/fixtures/bot_relay/README.md, crates/common/xai-computer-hub-core/src/bot_tools.rs)
25. https://github.com/xai-org/plugin-marketplace
26. https://cursor.com/blog/spacex-model-training
27. https://cursor.com/blog/joining-spacex
28. https://cursor.com/terms/grok-api
29. https://apps.apple.com/us/app/grok-bot/id6794501026
30. https://play.google.com/store/apps/details?id=ai.x.grok.bot
31. https://forum.cursor.com/t/introducing-the-x-subscription/174450
32. https://forum.cursor.com/tag/grok-bot/416
33. https://forum.cursor.com/t/grok-bot-weekly-usage-hits-100-after-bot-to-bot-reviews-the-user-asked-to-stop/170271
34. https://forum.cursor.com/t/feature-request-mask-secret-values-in-bot-shell-output/175384
35. https://forum.cursor.com/t/grok-bot-prune-compact-an-agent-s-context-without-creating-a-new-bot/168333
36. https://forum.cursor.com/t/grok-bot-email-outbound-works-but-inbound-mail-is-not-received/175361
37. https://forum.cursor.com/t/grok-bot-computer-cursor-cli-agent-p-stuck-on-connection-lost-reconnecting-since-oct-19-codex-works-from-same-machine/175385
38. https://forum.cursor.com/t/grok-bot-pro-vs-pro/175187
39. https://forum.cursor.com/t/anyone-else-seeing-grok-bot-access-changes-after-the-unified-plans-rollout/175364
40. https://github.com/b-nnett/grok-bot-0.18-reconstructed (secondary; README.md, PROVENANCE.md, docs/ARCHITECTURE.md, package.json)
41. https://github.com/OnlyTerp/opengrok (secondary)
42. https://grokbotguide.com/open-source/ (third-party directory)
43. https://www.infoq.com/news/2026/08/grok-bot-agent/ (press)
44. https://www.reuters.com/legal/transactional/spacex-buy-anysphere-60-billion-2026-06-16 (press)
45. https://www.reuters.com/business/media-telecom/musk-says-he-will-rename-spacexai-spacexsi-2026-10-04 (press)
46. https://www.theverge.com/ai-artificial-intelligence/961896/xais-x-account-is-now-spacexai (press)
47. https://en.wikipedia.org/wiki/SpaceXAI (third-party)
48. https://au.pcmag.com/ai/119676/chatgpt-claude-gemini-and-more-are-all-down-right-now (press)
49. https://www.eesel.ai/blog/grok-bot-review (third-party)
50. https://www.layer3labs.io/guides/grok-bot-review (third-party)
51. https://www.agenticbrew.ai/news/d719f20d-2613-471e-8f6b-dd77403247f4/grok-bot-ai-agent (third-party)
52. https://github.com/majiayu000/awesome-grok-bot (third-party)
