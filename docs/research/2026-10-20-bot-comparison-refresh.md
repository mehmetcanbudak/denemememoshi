# Bot comparison refresh: Grok Bot and its self-hostable alternatives

**Checked:** 2026-10-20, about 19:45–20:45 UTC. **Scope:** Grok Bot, Codync, OpenMausBot, Rakazo, Noodle, Aiden Agent, nightly-labs/openbot, and CopilotKit/OpenBot (for disambiguation). Kuvo Code, Cua Spaces and agentes.chat belong to other tasks and are not assessed here. **Status:** research input for the parent's [comparison report](2026-10-20-comparison-report.md). Research is evidence; the [plan](../plan/MASTER_PLAN.md) and [decisions](../plan/decisions.md) stay binding.

## 1. Decision summary

The suggestions below say which products fit best as sources and references. They are not a benchmark ranking and carry no scores [INFERENCE].

| Product | Suggested role | Why, in one line |
|---|---|---|
| **Grok Bot** | Main slot (behavior bar, ideas only) | It defines the shape the others copy: cards, Team Bots, one shared cloud computer per user. It is proprietary and model-locked |
| **Aiden Agent** | Main slot | The only product in this set that runs **Pi Durable 1.3.0** (one Durable harness per Bot, with policy in `beforeTool`) and wires **pi-codemode**. MIT |
| **Codync** | Main slot (new; today it is only a long-tail row) | Apache-2.0 Rust host with the best memory governance and remote-pairing design in the set. It has a native SwiftUI iPhone app and a Grok-patterned UX. New bots auto-approve |
| **Rakazo** | Main slot | Apache-2.0, `pi-agent-core` 1.3.0 on a server, the cleanest pluggable sandbox seam, and the origin of approval-by-verb and origin rules |
| **Noodle** | Main slot | The only native Swift Mac and iOS suite here. Bots are restricted by default and get separate computer and browser apps. Apache-2.0 |
| **OpenMausBot** | Main slot | Largest Apache-2.0 roster, with a per-bot computer choice (cloud desktop, local VM or host) and a portable team file format. Its approval defaults loosened this month: Full access is the default, and sends through connected apps skip the card at Full access |
| **nightly-labs/openbot** | Reference only; first row to drop if a newcomer needs the slot | PolyForm Noncommercial (source-available, ideas only). Its ideas overlap with OpenMausBot and Codync. Its README and changelog disagree on core behavior |
| **CopilotKit/OpenBot** | Reference only | An MIT **template**, in alpha, that needs CopilotKit Intelligence. Its one transferable idea, a gateway that decides and records every action, is already Memoshi's [D9](../plan/decisions.md#d9) |

**Corrections that change conclusions** (details in [§8](#8-corrections)):

1. **Rakazo now pins Pi 1.3.0, not 0.87.1.** It still does not use `pi-durable`. The bump landed 2026-10-18 in [#1501](https://github.com/elie222/rakazo/pull/1501), after the Tierroom snapshot and our 2026-10-18 survey.
2. **Codync's memory is no longer "Engram plus keeper", and it is not purely per-bot.** [context-and-memory.md](https://github.com/leepokai/Codync/blob/main/docs/features/context-and-memory.md) says "Dreaming replaces the keeper", and its "yours" layer is shared by every bot that uses it. New Codync bots default to `Auto`: "Requests are approved once, automatically. New bots start here" ([model.rs](https://github.com/leepokai/Codync/blob/main/host/src/store/model.rs)).
3. **OpenMausBot's "Bots ask before they act" is not the default.** New bots start at Full access ([v0.1.109](https://github.com/milind-soni/OpenMausBot/releases/tag/v0.1.109)). At Full access, sends through connected apps skip the send card and the daily limit ([v0.1.111](https://github.com/milind-soni/OpenMausBot/releases/tag/v0.1.111)).
4. **nightly OpenBot has voice now.** [0.46.0](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md) (2026-10-20) added on-device spoken replies and a Voice pane. Its [README](https://github.com/nightly-labs/openbot/blob/main/README.md) still lists channel chats, which 0.38.1 removed.
5. **Aiden's Bot memory budgets doubled**, to 2,750 and 4,400 characters, and Aiden added `bot_recall` ([#515](https://github.com/sambitcreate/aiden-agent/pull/515)).
6. **Grok Bot's own pages disagree.** On plan multipliers, [x.ai/bot](https://x.ai/bot) says Super is 3.5× and Ultra 12× Premium usage, while the [pricing docs](https://docs.x.ai/x-subscription/pricing) give 4×/15×/50× of Plus, which works out to 3.75× and 12.5×. On platforms, the landing page names only macOS and Windows desktops plus iOS, while the [docs](https://docs.x.ai/grok-bot/overview) add Linux and Android.
7. **Codync left native SwiftUI on the Mac.** In [2.7.0](https://github.com/leepokai/Codync/releases/tag/v2.7.0) the SwiftUI + AppKit chat was replaced by Electron because it "had become too slow to scroll and stream long transcripts" ([README](https://github.com/leepokai/Codync/blob/main/README.md#changelog)). This is a performance data point for Memoshi's native transcript ([D31](../plan/decisions.md#d31)) [INFERENCE].

## 2. Method and evidence vocabulary

This doc uses the [comparison report's](2026-10-20-comparison-report.md#2-method-and-evidence) vocabulary:

- **Documented:** first-party documentation establishes support; nobody exercised it.
- **Source-inspected:** selected files were read; this is not an audit.
- **Demonstrated/announced:** a maker's post or demo.
- **Inherited:** earlier repository research supplies the fact, and this pass did not repeat the check.
- **Unknown:** not established; it does not mean absent.
- **[INFERENCE]:** our judgment.
- **(vendor claim):** marketing that was not checked.

The tables add two tags:

- **F (fresh):** documented or source-inspected in this pass, with the citation in §4–§6.
- **I (inherited):** taken from the linked [landscape profile](agentic-workspace-landscape/projects/) (2026-10-20) and not re-checked.

How the checks were made:

- **Repositories:** read through the GitHub API at these `main` heads, recorded at the end of the pass:
  - OpenMausBot `2bfb982f5a`
  - nightly OpenBot `5d60b004f7`
  - CopilotKit/OpenBot `e8bb27368f`
  - Rakazo `c0efb42024`
  - Codync `66cd93f30d`
  - Noodle `9bcf0bbede`
  - Aiden `2b085b6aaa`
  - Pi `22dc6c26f3`
- **App Store metadata:** from Apple's lookup API, e.g. `https://itunes.apple.com/lookup?id=6794501026`.
- **Not done:** nothing was installed, run, signed into or purchased. No benchmark was run, and no Kuvo source was read.
- **Context7:** queried for Pi facts but failed with a monthly-quota error. Pi facts come from Pi's own repository instead (§5).
- **X:** no X posts were among this task's links, and none were read.

## 3. User-supplied links: retrieval record

| Link | Retrieval | What was observed | Relevance | Limits |
|---|---|---|---|---|
| [x.ai/bot](https://x.ai/bot) | Read in full 2026-10-20 (plain `curl` got HTTP 403) | Title "AI teammates that finish the work / Grok Bot"; `og:site_name` SpaceXSI. Downloads link to `api2.cursor.sh`; Contact sales goes to `cursor.com`. Prices: Premium $30, Super $100 ("3.5x Premium usage"), Ultra $200 ("12x Premium usage"). FAQ: "Every Grok Bot shares one persistent cloud computer … Isolation is per user, not per Grok Bot"; "generally available for Enterprise, as well as for teams on the Teams plan"; clients "desktop (macOS or Windows) or … the iOS app" | Primary vendor page; ownership and pricing signals | Marketing. Lines such as "get smarter over time" are vendor claims. The target of "More downloads" was not resolved |
| [Tierroom explore](https://my-tierroom.party/explore) | Read through its Markdown alternate (`/explore.md`) | "Radar Scout" directory: five alternative guides, nine English articles and 63 agent entries (count confirmed) | Discovery only. It surfaced Codync, CopilotKit's OpenBot, OpenMuse and OpenDots, and many newcomers | Editorial tiers, no test data |
| [Tierroom article](https://my-tierroom.party/blog/open-source-grok-bot-alternatives-mausbot-rakazo-codync-openbot) | Read in full via the Markdown alternate | By Guilherme Vasques, published 2026-10-17. An AI-assisted documentation review of MausBot, Rakazo, Codync and OpenBot at pinned commits, with 14 editorial criteria scored /56. It labels licenses correctly: three Apache-2.0 products, OpenBot PolyForm Noncommercial | Useful leads to primary files (pinned SHAs) | The author says it is not hands-on and gives scores "not benchmark results". Several facts are stale (§8.1). We reuse none of its numbers. The author also runs Tierroom, so the site and the article are not independent sources ([new-products §11](2026-10-20-new-products.md#11-where-tierroom-discovery-only-diverges-from-primary-sources)) |
| [Tierroom Codync profile](https://my-tierroom.party/agents/codync.md) | Read (followed from explore) | Indie maker Lee Po Kai; feature checklist; "Android is unconfirmed" | Discovery only | Partly superseded (§6.1) |

## 4. Grok Bot: identity, capabilities and limits

### 4.1 Who owns and operates it (fresh)

| Signal | Observation | Source |
|---|---|---|
| Brand | An x.ai page; `og:site_name` "SpaceXSI", Twitter `@spacexsi`; the launch video file is named `…cursor_bot_edit_v8…` | [x.ai/bot](https://x.ai/bot) |
| Builder and operator | Desktop download from `api2.cursor.sh`; sales on `cursor.com`. "The computers Bots work on run in Cursor's cloud." "Cursor manages model selection. There is no customer-facing model picker" | [x.ai/bot](https://x.ai/bot), [docs overview](https://docs.x.ai/grok-bot/overview), [security](https://docs.x.ai/grok-bot/security) |
| Contract | Cursor's "Grok Bot Terms", last updated 2026-10-12, supplement "the agreement governing Customer's use of the Services"; the Provider is "the entity providing Grok Bot to Customer under the Agreement" | [cursor.com/terms/grok-bot](https://cursor.com/terms/grok-bot) |
| iOS listing | Seller X Corp.; bundle ID `co.anysphere.sand`; version 1.16.0 (2026-10-18); first release 2026-08-11; 4.91 from 12,452 ratings | [App Store](https://apps.apple.com/us/app/grok-bot/id6794501026), via Apple's lookup API |
| Corporate history | SpaceX closed its Cursor acquisition 2026-08-14; the SpaceXAI → SpaceXSI rename was announced 2026-10-04 | Inherited ([profile](agentic-workspace-landscape/projects/grok-bot.md#corporate-relationship-spacexai--spacex--cursor)) |

[INFERENCE] Grok Bot is built and run by Cursor (Anysphere) under the SpaceXSI/SpaceXAI brand. Which legal entity contracts with a buyer of The X Subscription is unknown from these pages.

### 4.2 Capabilities (fresh unless marked)

- **Bots and computer.** Named, persistent Bots on "a persistent cloud computer with a browser, filesystem, and terminal". "Each Bot gets its own screen on the shared computer, and one Bot runs one computer-use task on its screen at a time" ([overview](https://docs.x.ai/grok-bot/overview)).
- **Memory.** "Stable preferences, role context, and summaries of prior work". The docs advise checking the current source for consequential decisions ([overview](https://docs.x.ai/grok-bot/overview)). Team memory and per-person notes in Team Bots are inherited ([profile](agentic-workspace-landscape/projects/grok-bot.md#capabilities-in-detail)).
- **Clients.** Desktop on macOS (Apple silicon and Intel), Windows (x64 and Arm64) and Linux (x64 and Arm64) ([overview](https://docs.x.ai/grok-bot/overview)).
- **Mobile.** iOS 18+ and Android 9+, with dictation, live voice chat, voice memos, approvals and takeover. Editing or testing routines and teach-by-demonstration need the desktop ([mobile](https://docs.x.ai/grok-bot/mobile)).
- **Latest changelog entry.** Still 0.71.2 (2026-10-14): tagged email aliases trigger routines, and team admins can turn off "Messaging between Bots" ([changelog](https://x.ai/changelog/bot)).
- **Inherited and unchanged:** routines (50 per Bot, at least 5 minutes apart), webhooks, app and email triggers, Auto Review plus Ask-first rules, draft and purchase cards, Team Bots in Slack, teach-by-demonstration ([profile](agentic-workspace-landscape/projects/grok-bot.md)).

### 4.3 Limits (fresh)

- **Isolation is per user.**
  - "Each user gets a dedicated Firecracker microVM"; for a separate computer and credential set, "give it its own Cursor user" ([security FAQ](https://docs.x.ai/grok-bot/security-faq)).
  - The Terms say Bots sharing that environment "must not be treated as separate security boundaries", and that deleting a Bot "may not delete shared files, sessions, credentials, or routines" ([terms](https://cursor.com/terms/grok-bot)).
- **Safety controls carry no guarantee.** "Approval and automated-review controls are provided as aids only" ([terms](https://cursor.com/terms/grok-bot)).
- **Models and region.** No model picker; "the serving mix can change over time with no fixed vendor set guaranteed". "The team model allowlist is Enterprise only, and enforcement is not guaranteed." "Grok Bot computers run in the United States today", which "is not the same as" Cursor's US-only data-residency program ([security](https://docs.x.ai/grok-bot/security)).
- **An allowlist turns web search off.** Under an allowlist network policy, "Grok Bot's web search is off"; web fetch "stays on and follows the allowlist" ([security FAQ](https://docs.x.ai/grok-bot/security-faq)).
- **Maturity and plans.**
  - The launch post still says "Grok Bot is in beta" ([launch](https://x.ai/news/introducing-grok-bot)); the landing page says GA for Enterprise and Teams.
  - Grok Bot is in Premium, Super and Ultra, not Plus. "Bot usage draws from that seat's shared weekly usage pool" ([pricing](https://docs.x.ai/x-subscription/pricing)).
- **Inherited:** a percent-only usage meter, weekly allowances burned by bot-to-bot loops, unbounded per-Bot threads, and secrets visible through `env` ([profile](agentic-workspace-landscape/projects/grok-bot.md#weaknesses-and-risks)).

## 5. Pi integration across the set (fresh)

Upstream [earendil-works/pi](https://github.com/earendil-works/pi) is MIT, with 116,682 stars; its latest release is [v1.3.0](https://github.com/earendil-works/pi/releases/tag/v1.3.0) (2026-10-15). Its [RPC mode](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc.md) "runs Pi as a long-lived subprocess controlled through JSON records on stdin and stdout", and the docs recommend the SDK for in-process hosts. [`pi-durable`](https://github.com/earendil-works/pi/blob/main/packages/durable/README.md) is marked "Experimental. The API changes without notice between releases."

| Product | How it uses Pi | Packages and versions | Pi Durable? | Evidence |
|---|---|---|---|---|
| Aiden Agent | Embedded. One Pi Durable harness per Bot at `<profile>/bots/<dir>/session.sqlite`; an `aiden-bot` extension whose `beforeTool` checks policy; approvals persisted in the tool-task memo. Code Mode runs through pi-codemode's `CodemodeSandbox` in `main/services/pi-codemode.ts`; whether every Bot turn uses it is Unknown | `pi-agent-core`, `pi-ai`, `chord`, `pi-durable` and `pi-codemode` 1.3.0, plus a legacy alias `@aiden/pi-legacy-harness` → `pi-agent-core@0.87.1` | **Yes** | [package.json](https://github.com/sambitcreate/aiden-agent/blob/main/package.json), [bot-durable-runtime.md](https://github.com/sambitcreate/aiden-agent/blob/main/.memory/bot-durable-runtime.md), [pi-codemode.ts](https://github.com/sambitcreate/aiden-agent/blob/main/main/services/pi-codemode.ts), [#505](https://github.com/sambitcreate/aiden-agent/pull/505) |
| Rakazo | Embedded `pi-agent-core` runtime in the API and worker | `pi-agent-core`, `pi-ai` and `pi-telemetry` 1.3.0 since 2026-10-18 | No (Graphile Worker runs its jobs, its own mechanism [INFERENCE]) | [adapters/package.json](https://github.com/elie222/rakazo/blob/main/packages/adapters/package.json), [#1501](https://github.com/elie222/rakazo/pull/1501) |
| OpenMausBot | Child process: "`pi --mode rpc --no-session`), not ACP"; Pi reads its own `auth.json`; also handles oh-my-pi RPC v2 chunks | The user installs `@earendil-works/pi-coding-agent` | No | [server/drivers/pi.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/drivers/pi.ts) |
| nightly OpenBot | Child process: "Pi uses its native `--mode rpc` interface. It does not use an ACP wrapper", plus an extension using `registerMcpServer` | A managed Pi archive from GitHub releases, checked by SHA-256 | No | [providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md#pi) |
| Codync | ACP adapter from the registry; also oh-my-pi | Third-party [`pi-acp`](https://github.com/svkozak/pi-acp) 0.0.34 (MIT, Sergii Kozak) over `pi-coding-agent` | No | [backends.rs](https://github.com/leepokai/Codync/blob/main/host/src/agent/backends.rs), [ACP registry](https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json) |
| Noodle | None. Its harness list has no Pi | n/a | n/a | [README](https://github.com/pdparchitect/noodle/blob/main/README.md), [harness-setup.md](https://github.com/pdparchitect/noodle/blob/main/docs/harness-setup.md) |
| Grok Bot | None. Its own Cursor-run harness | n/a | n/a | [security](https://docs.x.ai/grok-bot/security) |

A peer task found that `nikuscs/orbs` also drives `pi --mode rpc` ([memory and orbs research](2026-10-20-memory-orbs.md)).

[INFERENCE] Memoshi's [D6](../plan/decisions.md#d6) puts embedded Pi Durable behind its own adapter, and Aiden is the only shipping product here built that way. The RPC and ACP routes (OpenMausBot, OpenBot, Codync) are references for [D11](../plan/decisions.md#d11)-style delegation to an external Pi CLI, not for the brain.

## 6. Fresh facts per product

Star counts and releases come from the GitHub API on 2026-10-20. Counts cover releases on GitHub, not tags.

### 6.1 Codync ([leepokai/Codync](https://github.com/leepokai/Codync))

**Identity and license**

- Created 2026-03-18. 668 stars, 85 forks, 7 contributors; `leepokai` has 1,169 commits.
- 70 releases:
  - 6 v1.x (2026-03-23 to 03-29), when [v1.0.0](https://github.com/leepokai/Codync/releases/tag/v1.0.0) was a "Real-time Claude Code monitor for macOS and iPhone";
  - 64 v2.x, from [v2.1.0](https://github.com/leepokai/Codync/releases/tag/v2.1.0) (2026-09-25, "refine Grok-style UI") to [v2.20.4](https://github.com/leepokai/Codync/releases/tag/v2.20.4) (2026-10-20).
- License: Apache-2.0; "versions up to 2.11.0 were MIT". "The Codync name, logo and the Codync Cloud relay are not covered, and hosted or multi-tenant services must run their own relay and accounts" ([README](https://github.com/leepokai/Codync/blob/main/README.md#license), [NOTICE](https://github.com/leepokai/Codync/blob/main/NOTICE)).
- Codync Cloud is "free for personal use"; "Computers or accounts that break this are blocked" ([TRADEMARK.md](https://github.com/leepokai/Codync/blob/main/TRADEMARK.md)).
- The project is "maintained by one person. There is no bug bounty" ([SECURITY.md](https://github.com/leepokai/Codync/blob/main/SECURITY.md)).

**Architecture** ([README](https://github.com/leepokai/Codync/blob/main/README.md))

- A Rust `codync-host` runs on macOS, Windows and Linux, with a static Linux binary for headless servers. It speaks ACP to each agent, keeps transcripts in SQLite and serves loopback HTTP+SSE.
- The desktop is Electron for macOS, Windows and Linux since 2.7.0; the iPhone app is native SwiftUI.
- There is also an SSH-friendly TUI.
- An Android Kotlin/Compose client exists as source, but "Release APKs are unsigned" and none is attached to releases ([apps/android](https://github.com/leepokai/Codync/blob/main/apps/android/README.md)).
- "UI patterns (roster, character avatars, approval cards, trace sheet …) follow Grok Bot". The bot model names "Grok-Bot-style character shape[s]" ([model.rs](https://github.com/leepokai/Codync/blob/main/host/src/store/model.rs)).

**Engines and accounts**

- About 40 agents through the [ACP registry](https://agentclientprotocol.com/registry); installed harnesses are detected automatically.
- "It never calls a provider's API with your login" ([README FAQ](https://github.com/leepokai/Codync/blob/main/README.md#faq)).

**Bots and teams**

- One persistent chat per bot.
- New bots get `~/.codync/bots/<id>/workspace`; "a personal folder is not a sandbox", and "automatic Git worktrees are not implemented here" ([bot-workspaces.md](https://github.com/leepokai/Codync/blob/main/docs/features/bot-workspaces.md)).
- A group "room turn" runs at most 3 rounds and 10 replies ([groups-and-replies.md](https://github.com/leepokai/Codync/blob/main/docs/features/groups-and-replies.md)).
- The built-in `team` MCP offers `list_bots`, `ask_bot` (wait for the reply) and `message_bot` (queue it) ([bot-collaboration.md](https://github.com/leepokai/Codync/blob/main/docs/features/bot-collaboration.md)). Chains "stop after 8 hand-offs, with at most 16 pending messages per bot and 64 overall" ([v2.11.0](https://github.com/leepokai/Codync/releases/tag/v2.11.0)).

**Memory** ([context-and-memory.md](https://github.com/leepokai/Codync/blob/main/docs/features/context-and-memory.md))

- **Two layers.** A shared "yours" layer (400 tokens) and a per-bot layer (1,200 tokens).
- **Notes.** Versioned Markdown notes: 2,000 tokens per file, 20 files per folder.
- **Write checks.** Every non-user write is checked for hidden characters, prompt-carrying links, planted instructions, passwords, keys, and ID or card numbers. Each bot writes memory at once, "whatever its permission".
- **"Dreaming replaces the keeper"** ([v2.18.0](https://github.com/leepokai/Codync/releases/tag/v2.18.0), 2026-10-18):
  - every change "must quote what the user typed";
  - at most 10 changes and a quarter of the entries per run;
  - it pauses while plan usage is above 75%;
  - every run is logged and can be undone.
- **Harness memory off.** The harness's own memory (for example Claude Code auto memory) is off by default.
- **Compaction.** Codync compacts ahead of time and has a loop guard: after three host compactions in a day, it rolls over to a handoff card.

**Routines** ([routines.md](https://github.com/leepokai/Codync/blob/main/docs/features/routines.md))

- Triggers:
  - `interval`, `once` and `cron` (with an IANA time zone);
  - `webhook`;
  - `event` from Slack, GitHub, Microsoft Teams, Linear, Sentry, PagerDuty or email.
- Each run gets a fresh session, and only one routine per bot runs at a time. `(pass)` ends silently.
- The cloud "keeps public deliveries for up to 72 hours"; "deliveries are not end-to-end encrypted. The cloud terminates HTTPS, sees the content and stores the key to check signatures."

**Computer and browser** ([computer-use.md](https://github.com/leepokai/Codync/blob/main/docs/features/computer-use.md))

- A built-in `computer` MCP drives the **user's own desktop** through cua-driver (MIT). It works in the background through accessibility where it can.
- "One bot at a time." While a phone has taken over the screen, bots may only use tools that look.
- `type_login` fills a saved login that "the agent never sees".
- The driver's `browser_*` tools are excluded, and no built-in browser is documented (Unknown).

**Voice and remote**

- Voice ([voice-call.md](https://github.com/leepokai/Codync/blob/main/docs/features/voice-call.md)):
  - on-device by default;
  - OpenAI (`gpt-realtime-2.1`) or Gemini (`gemini-3.8-live`) with the user's own keys;
  - the realtime model is "an operator in front of the bot, not a replacement for it".
- Remote access ([remote-relay.md](https://github.com/leepokai/Codync/blob/main/docs/reference/remote-relay.md)):
  - an end-to-end encrypted Cloudflare relay;
  - the host is the only authority for device grants, and the cloud can only shorten them;
  - a 6-digit code confirms each access request.
- iOS app: seller Pokai Lee, version 2.20.0 ([App Store](https://apps.apple.com/app/codync/id6760984418)).

**Security and telemetry**

- `Permission::Auto` is the default: "Requests are approved once, automatically. New bots start here" ([model.rs](https://github.com/leepokai/Codync/blob/main/host/src/store/model.rs); since [v2.5.1](https://github.com/leepokai/Codync/releases/tag/v2.5.1)).
- A paired device is "trusted like the owner". It can run coding agents that "execute shell commands, by default without asking" ([SECURITY.md](https://github.com/leepokai/Codync/blob/main/SECURITY.md)).
- Secrets live in an XChaCha20-Poly1305 vault keyed from the OS keyring, which "does not claim to isolate secrets from arbitrary code running as the same OS user" ([connector-credentials.md](https://github.com/leepokai/Codync/blob/main/docs/features/connector-credentials.md)).
- PostHog analytics are "on by default on every device" ([analytics.md](https://github.com/leepokai/Codync/blob/main/docs/features/analytics.md)).

**Inherited:** only the [long-tail row](agentic-workspace-landscape/landscape/oss-long-tail.md) (637 stars, "reference"). Codync has no profile.

### 6.2 OpenMausBot ([milind-soni/OpenMausBot](https://github.com/milind-soni/OpenMausBot))

**Identity and license**

- 5,279 stars, 882 forks; latest [v0.1.119](https://github.com/milind-soni/OpenMausBot/releases/tag/v0.1.119) (2026-10-20).
- 69 desktop releases plus Android APK releases (`android-v1.0.0`…`v1.5.0`).
- The core is Apache-2.0. `enterprise/` is source-available: production use needs a license key, and hosting for third parties or white-labelling needs a partner agreement. The OpenMausBot and MausBot names and the mascot are Supamaus trademarks; "a product built on OpenMausBot needs its own name" ([LICENSING.md](https://github.com/milind-soni/OpenMausBot/blob/main/LICENSING.md)).
- The current tree has no Swift or Kotlin app source, only the companion sidecar ([ios-companion.md](https://github.com/milind-soni/OpenMausBot/blob/main/docs/ios-companion.md)). The iOS app is published by Supamaus Software Private Limited, version 1.5.0 ([App Store](https://apps.apple.com/in/app/mausbot/id6803387923)).

**Shape** ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md))

- Platforms: Electron on macOS (signed and notarized), Windows (installer not code-signed) and Ubuntu 24.04 (beta).
- Engine: a harness server on `127.0.0.1:8799` normalizes every engine into one event stream. It drives the `claude`, `codex` and `grok` CLIs, and "any ACP-speaking CLI or OpenAI-compatible endpoint" through config.
- Interfaces: a bounded MCP control plane (no approvals, deletion or credentials), and a headless `openmausbot` CLI.

**Computers and browser**

- Each bot can use "a cloud Linux desktop, an isolated Local VM, or … your own computer". "Host control is available on macOS and Ubuntu Xorg after explicit opt-in"; Wayland is disabled ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md)).
- The agent CLIs themselves still "run real CLIs (`claude`, `codex`) with the user's own privileges" ([SECURITY.md](https://github.com/milind-soni/OpenMausBot/blob/main/SECURITY.md)).
- Browser:
  - "a page a bot opens can no longer reach OpenMausBot itself, other apps on your computer, devices on your home network, or cloud metadata addresses" ([v0.1.113](https://github.com/milind-soni/OpenMausBot/releases/tag/v0.1.113));
  - each bot's browser keeps its own Chrome profile ([v0.1.119](https://github.com/milind-soni/OpenMausBot/releases/tag/v0.1.119));
  - "browsers in the cloud never open Reddit" ([#3032](https://github.com/milind-soni/OpenMausBot/pull/3032)).
- The 0.1.113 notes also announce bot-detection evasion: a real-Chrome browser that sites "flag … much less" (vendor claim). See §9.

**Teams and automations** ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md))

- Channels have rosters and responder rules. A Chief of Staff leads, and a "decision model" (TypeSafe Jev or OpenRouter) routes messages in Auto rooms.
- Triggers:
  - schedules: once, on chosen weekdays, or every 5–1,440 minutes, with an overlapping run skipped;
  - webhooks on `127.0.0.1:8800`;
  - Composio app events by long poll, up to 500 a day on a desktop.
- Teams import from one Markdown file: the MIT [BotMRR Markdown v1](https://github.com/milind-soni/openmausbot-teams/blob/main/FORMAT.md) format. Packages "never carry credentials, conversations, permissions, memory, or computer access", and routines arrive paused.

**Approvals** (default regression)

- [v0.1.109](https://github.com/milind-soni/OpenMausBot/releases/tag/v0.1.109): "Bots start with Full access, on every engine".
- [v0.1.111](https://github.com/milind-soni/OpenMausBot/releases/tag/v0.1.111): at Full access, bots "send through your connected apps (email, Slack, posts, payments) without a 'Send on your behalf?' card or a daily limit".
- [v0.1.115](https://github.com/milind-soni/OpenMausBot/releases/tag/v0.1.115): "No more permission prompts from OpenMausBot itself" for profile, team and memory changes.
- [SECURITY.md](https://github.com/milind-soni/OpenMausBot/blob/main/SECURITY.md) lists a known open issue: a bot's shell can post into a Full-access Slack thread "without a card".
- In terminal or server setup, "API keys are saved as plaintext, not encrypted" in `config.json` (0600 on Unix) ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md#run-from-a-terminal-or-on-a-server)).

**Voice and cost**

- Voice: TTS from ElevenLabs, Fish Audio, xAI, Mac voices or Chatterbox. Calls are macOS-only ([README](https://github.com/milind-soni/OpenMausBot/blob/main/README.md#status)).
- [MausBot Cloud](https://mausbot.com/pricing):
  - Starter $15 a month: sleeps when idle; 2 shared CPUs, 2 GB; one cloud computer at a time, 10 hours a month.
  - Pro $49: always on; 4 computers at once, 200 hours; $10 of Claude credit.
  - Max $99: 8 computers, 500 hours; $20 of Claude credit.
  - Each plan bills by card after a 3-day trial; users bring their own Claude or ChatGPT account or an API key.

**Inherited:** per-bot `MEMORY.md` (200 lines / 24 KB), keyword recall and an undo journal; cron and Composio triggers; 22 engines; Cloud on Fly.io ([profile](agentic-workspace-landscape/projects/openmausbot.md)).

### 6.3 Rakazo ([elie222/rakazo](https://github.com/elie222/rakazo))

**Identity:** 4,913 stars, 889 forks; [v0.3.1](https://github.com/elie222/rakazo/releases/tag/v0.3.1) (2026-10-19); ten versioned releases plus an Android APK release. Unmodified Apache-2.0 text ([LICENSE](https://github.com/elie222/rakazo/blob/main/LICENSE)). iOS app by Inbox Zero Inc., version 1.0.6 ([App Store](https://apps.apple.com/app/rakazo/id6801531099)).

**Shape** ([README](https://github.com/elie222/rakazo/blob/main/README.md))

- Clients: web, Electron, iPhone and Android.
- Models: "Bring-your-own model credentials through Pi".
- Computers: "Shared Team Computers and isolated Private computers" on Docker, E2B, Daytona, CreateOS, Boat, Railway, or a "trusted local-computer".
- Voice: users bring their own ElevenLabs, OpenAI, Cartesia or Fish Audio key.
- Install: Docker Compose images or a Railway template.

**New since the profile**

- [#1519](https://github.com/elie222/rakazo/pull/1519) (2026-10-19) lets bots use the local computer through an authenticated native bridge in the desktop app:
  - enabled only after native confirmation;
  - the host shell runs commands, while file tools stay scoped to bot workspaces;
  - "graphical screen control remains unavailable";
  - consent can be revoked at once.
- [#1550](https://github.com/elie222/rakazo/pull/1550) renamed the Box provider to Boat.
- **Pi 1.3.0** (§5).

**Inherited:** per-tool approvals, in which the sandbox is the boundary and external writes, secrets, deletes and self-edits ask; verb and origin rules; Markdown memory in Postgres with revisions; read-only watch triggers ([profile](agentic-workspace-landscape/projects/rakazo.md)). Docker computers have open egress by default ([2026-10-18 survey](prior/open-source-agent-bots-2026-10-18.md)).

### 6.4 Noodle ([pdparchitect/noodle](https://github.com/pdparchitect/noodle))

This is the official project, as identified in the [profile](agentic-workspace-landscape/projects/noodle.md); `poteto/noodle` and `noodle-run/noodle` are unrelated.

- **Identity.** 181 stars, 21 forks; [v0.70.0](https://github.com/pdparchitect/noodle/releases/tag/v0.70.0) (2026-10-20); 82 main-app releases since 2026-09-05. Apache-2.0.
- **Apps.** A native suite for macOS 26: Noodle, Computer (Linux, macOS and Windows computers), Browser ("dedicated browsers you sign in to and assign to agents"), Applet, Hub, and Mobile (iOS 26, TestFlight) ([README](https://github.com/pdparchitect/noodle/blob/main/README.md)).
- **Harnesses.** Codex, Claude Code, FX, Grok Build, Muse Code, OpenCode v2, Antigravity and Apple Intelligence; no Pi.
- **Security** ([security.md](https://github.com/pdparchitect/noodle/blob/main/docs/security.md)):
  - "Every bot starts with restricted access"; "If Noodle cannot apply the limit, the bot does not start".
  - A restricted bot can still reach the internet. An unrestricted bot "runs as your Mac user".
  - "Noodle does not show approval or question forms in chat. It approves a harness's tool requests automatically, within the bot's access."
  - Hub: "Lending a sign-in shares the account".
- **0.70.0 changes.** It shows plan-limit use for Codex and Claude Code accounts, adds a Kick button with a reason for paused bots, and lets a user forward files between bots.
- **Inherited:** heartbeats, self-scheduled wakes, bot-maintained `memory.md`, and one author doing about 97% of the commits ([profile](agentic-workspace-landscape/projects/noodle.md)).

### 6.5 Aiden Agent ([sambitcreate/aiden-agent](https://github.com/sambitcreate/aiden-agent))

- **Identity.** 85 stars, 4 forks; [v0.59.0](https://github.com/sambitcreate/aiden-agent/releases/tag/v0.59.0) (2026-10-20, adds Workspace Artifacts); 63 releases since 2026-07-25. MIT ([LICENSE](https://github.com/sambitcreate/aiden-agent/blob/main/LICENSE)). Electron `^43.1.1`.
- **Pi.** It is the Pi Durable adopter (§5).
- **Memory.** [#515](https://github.com/sambitcreate/aiden-agent/pull/515) (in v0.58.0) doubled the budgets to 2,750 characters for "About you" and 4,400 for Bot notes, added a read-only `bot_recall` search over the Bot's own history, and calls itself "stage 1 of bringing Bot memory closer to Hermes Agent".
- **Platforms and Computer Use** ([README](https://github.com/sambitcreate/aiden-agent/blob/main/README.md)):
  - the iPhone and iPad app ships through "TestFlight only"; the Intel Mac build is pending;
  - Computer Use is a macOS opt-in beta whose first call in a chat raises one access card (Deny, Allow for this chat, or Always allow).
- **Inherited:** Bots default to Full access, and the Bot home "is not a sandbox in Full mode"; managed git worktrees, a terminal and diffs; croner routines, Bot-proposed routines that need approval, and `[SILENT]`; persona kept in the Bot record; no group chat shipped ([profile](agentic-workspace-landscape/projects/aiden-agent.md)).

### 6.6 nightly-labs/openbot ([repo](https://github.com/nightly-labs/openbot)): source-available, not open source

**Identity and license**

- 691 stars, 112 forks; v0.46.0 (2026-10-20); 80 app releases since [v0.1.0](https://github.com/nightly-labs/openbot/releases/tag/v0.1.0) (2026-08-13).
- [LICENSE](https://github.com/nightly-labs/openbot/blob/main/LICENSE): PolyForm Noncommercial 1.0.0 (GitHub reports `NOASSERTION`). Commercial use needs a license from `licenses@openbot.run`; "Versions up to and including 0.1.11 remain available under Apache-2.0".
- Outside contributors sign an assignment agreement that "assigns its copyright to Synthetify Labs" ([README](https://github.com/nightly-labs/openbot/blob/main/README.md#license-and-attribution)).

**Shape** ([README](https://github.com/nightly-labs/openbot/blob/main/README.md))

- Providers: Codex app-server and Claude Code, plus Grok CLI, OpenCode, Gemini, Cursor and Cline through ACP. Pi and Muse are covered in [providers.md](https://github.com/nightly-labs/openbot/blob/main/docs/architecture/providers.md).
- Workspaces: each agent gets `~/OpenBot/Agents/<agent-id>` plus `~/OpenBot/Shared`.
- Computer use: a cua-driver child process on macOS, Windows and Linux.
- Deployment: a Linux server installer, a Docker or ECS image, and a shared macOS host package with one Standard user per tenant.

**Permissions: two first-party sources disagree**

- The README warning says agents "run with `danger-full-access` and `approvalPolicy: never`" after first-launch consent, and "Full local access is an explicit current product decision, not a security boundary".
- The [CHANGELOG](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md) says otherwise:
  - 0.22.0: Full access "is the default";
  - 0.43.0 (2026-10-17) added Workspace only, Ask first and Full access;
  - at Ask first, "Claude's own tools run without asking";
  - "Always allow" moves the agent to Full access.

**Changes since the profile** ([CHANGELOG](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md))

- 0.38.1 (2026-10-13): "Channels are no longer supported". The README's "What works" still lists shared channel chats.
- 0.46.0 added on-device spoken replies (Supertonic 3, about 145 MB, "no text or audio leaves the computer") and a Voice pane. It also sends usage-count events for the voice features to OpenPanel.
- Hosted servers run in the EU:
  - Starter, Standard and Pro tiers by member count (3/10/25) and storage (12/50/100 GB);
  - they stop when idle and wake before routines ([guide](https://openbot.run/guides/openbot-hosted-servers));
  - prices appear only in an image (inherited: from EUR 20).

**Inherited:** deep routines (chained flows, missed-run policy, signed webhooks), provider fallback with a handoff packet, and multiple accounts per provider ([profile](agentic-workspace-landscape/projects/openbot.md)).

### 6.7 CopilotKit/OpenBot ([repo](https://github.com/CopilotKit/OpenBot)): disambiguation, reference only

- **Identity.** MIT ([LICENSE](https://github.com/CopilotKit/OpenBot/blob/main/LICENSE)); 6,731 stars, 922 forks; [v0.2.0](https://github.com/CopilotKit/OpenBot/releases/tag/v0.2.0) (2026-10-12).
- **What it is** ([README](https://github.com/CopilotKit/OpenBot/blob/main/README.md)):
  - "A template, not a product"; "Alpha";
  - any AG-UI agent becomes a coworker;
  - "one container each with its own Chromium, logins and workspace";
  - every tool call "goes through one gateway that decides and records it".
- **Dependency and defaults.** It requires "a CopilotKit Intelligence project and license" (free plan; self-hostable). `.env.example` sets `OPENBOT_SINGLE_USER=true`.
- **Relationship.** It is not related to nightly-labs/openbot, or to the OpenMausBot fork that is also named `OpenBot` ([profile disambiguation](agentic-workspace-landscape/projects/openbot.md)).

## 7. Comparison matrix

F = fresh this pass (cited in §4–§6). I = inherited from the product's landscape profile. Cells are evidence summaries, not scores.

### 7.1 Platform, engine, bots, workspaces

| Product | Native / platforms | Engine / Pi mode | Persistent bots and teams | Workspaces and git |
|---|---|---|---|---|
| Grok Bot | F: desktop macOS/Win/Linux; iOS, Android; vendor cloud | F: Cursor-run harness, no model picker; no Pi | I: named Bots, primary Bot, groups 2–6, Team Bots; F: admins can disable bot-to-bot | I: `/workspace` on shared box; repo cards; no diff/worktree UI |
| Codync | F: Rust host; Electron desktop (SwiftUI Mac dropped in 2.7.0); native SwiftUI iPhone; Android source only; TUI | F: ACP client for ~40 agents; Pi via third-party `pi-acp` | F: one chat per bot; rooms ≤3 rounds/10 replies; `team` MCP; 8-hop chain cap | F: personal workspace "not a sandbox"; no auto-worktrees |
| OpenMausBot | F: Electron macOS/Win/Ubuntu beta; iOS and Android apps (source not public); PWA | F: CLI drivers + ACP/OpenAI-compatible; Pi via `pi --mode rpc` | F: channels with rosters, Chief of Staff, decision-model routing, team packages | I: per-bot/channel folders; F: no worktree code found |
| Rakazo | F: web, Electron, iOS App Store, Android APK; server-first | F: embedded `pi-agent-core` 1.3.0; no Durable | I: one thread per bot; groups, handoffs, child bots | I: terminal + files on computer; gh CLI; no diff/worktree UI |
| Noodle | F: native Swift suite, macOS 26; iOS 26 TestFlight | F: 7 vendor harnesses + Apple/local models; no Pi | I: bots with backstory; goal groups; F: forward files between bots | I: per-bot folder + shared folders; patch/diff review |
| Aiden Agent | F: Electron macOS arm64 + Linux; iOS TestFlight; Android | F: embedded Pi Durable + Code Mode 1.3.0, one harness per Bot | I: durable Bots; no group chat shipped | I: managed git worktrees, terminal, diffs, commit/push |
| nightly OpenBot | F: Electron macOS/Win/Linux; web client; I: iOS TestFlight, Android | F: Codex app-server, Claude, ACP; Pi via native RPC | F: agent-to-agent messages; channels removed in 0.38.1 | F: `~/OpenBot/Agents/<id>` + Shared; I: no git UI |

### 7.2 Isolation, voice and mobile, memory, automations

| Product | Browser / computer isolation | Voice / mobile | Memory | Automations |
|---|---|---|---|---|
| Grok Bot | F: one Firecracker microVM per user, shared by all Bots; not security boundaries; US only | F: dictation, live voice, voice memos; iOS and Android apps (some flows desktop-only) | F: preferences, role context, work summaries; I: Team memory | I: schedules (50/Bot), webhooks, app and email triggers |
| Codync | F: agents on host; real-desktop control, one bot at a time; phone takeover → look-only; no VM; no browser documented | F: on-device default; OpenAI or Gemini realtime with own key; iPhone | F: shared "yours" + per-bot layers, checked writes, versioned notes, "dreaming", undo | F: interval/once/cron/webhook/event; cloud queues webhooks 72 h, not E2E |
| OpenMausBot | F: per-bot Boat cloud desktop / Local VM / host; CLIs on host; per-bot Chrome profile with egress gate | F: TTS options; calls macOS-only; live calls on own OpenAI key | I: per-bot `MEMORY.md`, recall, undo journal | F: once/weekday/5–1,440 min, local webhooks, Composio events |
| Rakazo | F: sandbox providers (Docker default); Team or Private computer; consent-gated local bridge without GUI | F: BYO voice keys, calls; iOS and Android | I: Markdown docs in Postgres with revisions, bot/shared scopes | I: crons, webhooks, GitHub, read-only watches |
| Noodle | F: restricted by default (fails closed); separate Computer and Browser apps assigned per bot | I: on-device transcription; F: iOS TestFlight via Hub | I: bot-maintained Markdown files | I: 30-min heartbeats, self-wakes; no webhooks |
| Aiden Agent | I: host, "not a sandbox in Full mode"; F: Computer Use opt-in with per-chat card | I: Gemini Live, Parakeet; F: phone over LAN/Tailscale | F: 2,750/4,400-char budgets + `bot_recall`; I: scanned writes | I: croner; Bot-proposed routines need approval; `[SILENT]` |
| nightly OpenBot | I: host or server; sandbox only in Workspace only; F: full access "not a security boundary" | F: on-device spoken replies + Voice pane (0.46.0) | I: tiered per-agent store + history search | I: chained flows, missed-run policy; F: hosted wake before routines |

### 7.3 Approvals, deployment, license, maturity

| Product | Default approvals / security | Deployment | License / reuse for Memoshi ([D33](../plan/decisions.md#d33)) | Maturity and cost caveats |
|---|---|---|---|---|
| Grok Bot | I: Auto Review + rules, draft cards; F: controls are "aids only" | F: SaaS in Cursor's cloud | F: proprietary; **ideas only** | F: beta (launch post), GA for Enterprise/Teams; $30/$100/$200 from a shared weekly pool; multipliers inconsistent |
| Codync | F: **Auto by default**; paired device = owner; PostHog on by default | F: self-hosted host; free personal relay; multi-tenant must run its own | F: Apache-2.0 (≤2.11.0 MIT); name/logo/Cloud excluded; **reusable** with NOTICE | F: one maintainer; first bot-era release 2026-09-25; free |
| OpenMausBot | F: **Full access by default**; sends skip cards at Full access; plaintext keys in server mode | F: desktop, `npx openmausbot serve`, Docker, MausBot Cloud | F: Apache-2.0 core **reusable**; `enterprise/` source-available; trademarks excluded | F: v0.1.x "Early but real"; Cloud $15/$49/$99; Boat billed after trial |
| Rakazo | I: sandbox is the boundary; external writes/secrets/deletes ask; verb and origin rules | F: Compose images, Railway, VPS | F: Apache-2.0 **reusable**; I: name/logo not granted | F: beta v0.3.x; operate Postgres + worker + sandboxes |
| Noodle | F: no approval UI; auto-approves inside sandbox; Hub lending shares accounts | F: user Macs only | F: Apache-2.0 **reusable** (forking as base is ruled out by [D43](../plan/decisions.md#d43)) | F: ~1.8 releases/day; I: ~one author; free |
| Aiden Agent | I: **Full by default** for Bots; Custom grants narrow | F: desktop is the host; no cloud | F: MIT **reusable** | F: v0.59; I: one author plus coding agents |
| nightly OpenBot | F: Full access default; README and changelog disagree; "Always allow" escalates to Full | F: desktop, Linux server, Docker/ECS, EU hosting, multi-tenant Mac host | F: PolyForm Noncommercial, **source-available, ideas only**; ≤0.1.11 Apache-2.0 | F: "development preview"; commercial license by email |

## 8. Corrections

### 8.1 To the Tierroom article (2026-10-17 snapshot)

| Article claim | Current primary evidence |
|---|---|
| Rakazo's adapters "pin these Pi packages at 0.87.1" | 1.3.0 since 2026-10-18 ([#1501](https://github.com/elie222/rakazo/pull/1501)). Still no `pi-durable` |
| Codync has an "Engram database per bot … and a keeper" | "Dreaming replaces the keeper" ([v2.18.0](https://github.com/leepokai/Codync/releases/tag/v2.18.0)); Engram data migrates once; a shared "yours" layer spans bots ([doc](https://github.com/leepokai/Codync/blob/main/docs/features/context-and-memory.md)). The article's `engram-memory.md` and `groups-and-threads.md` are now `context-and-memory.md` and `groups-and-replies.md` on `main` |
| OpenBot's voice "remains narrower" | On-device spoken replies and a Voice pane since 0.46.0 ([CHANGELOG](https://github.com/nightly-labs/openbot/blob/main/CHANGELOG.md)); voice prompts are still unavailable on Linux ([README](https://github.com/nightly-labs/openbot/blob/main/README.md)) |
| Codync's "integrated browser … not confirmed" | No built-in browser is documented, and the computer tool deliberately leaves out cua-driver's `browser_*` tools ([computer-use.md](https://github.com/leepokai/Codync/blob/main/docs/features/computer-use.md)) |
| Codync's control design (not discussed) | New bots default to `Auto` approval and analytics are on by default (§6.1). This is material for any "safest" comparison |
| Star counts (5,050 / 4,452 / 489 / 594) | 5,279 / 4,913 / 668 / 691 on 2026-10-20 |
| 14-criterion scores, e.g. "51/56" | Editorial, self-described as not benchmarks. Not reused here |

The article's license distinctions and its warning that "a VPS chat opened on your Mac does not automatically gain control of that Mac" still stand.

### 8.2 To our landscape docs (for the parent; the landscape files were not edited)

- **[openbot.md](agentic-workspace-landscape/projects/openbot.md):** latest release v0.44.3 → v0.46.0. Voice "dictation only; no TTS or calls" is stale. Add the README/CHANGELOG contradictions.
- **[openmausbot.md](agentic-workspace-landscape/projects/openmausbot.md):** v0.1.118 → v0.1.119. Add sends without cards at Full access (0.1.111), removed app-owned confirmations (0.1.115), the browser egress gate (0.1.113) and per-bot Chrome profiles (0.1.119).
- **[rakazo.md](agentic-workspace-landscape/projects/rakazo.md):** add the local-computer bridge (#1519) and the Box → Boat rename (#1550).
- **[aiden-agent.md](agentic-workspace-landscape/projects/aiden-agent.md):** memory "64 entries each" now also has 2,750/4,400-character budgets and `bot_recall` (0.58.0). Latest release v0.58.0 → v0.59.0.
- **[noodle.md](agentic-workspace-landscape/projects/noodle.md):** 0.69.1 → 0.70.0.
- **[grok-bot.md](agentic-workspace-landscape/projects/grok-bot.md):**
  - add the landing page's 3.5×/12× figures beside the docs' 4×/15×/50×;
  - add the iOS bundle ID `co.anysphere.sand`, distinct from the reconstructed macOS `com.anysphere.sand`;
  - add the Terms' "aids only" and shared-environment clauses (2026-10-12).
- **[oss-long-tail.md](agentic-workspace-landscape/landscape/oss-long-tail.md):** Codync row 637 → 668 stars. Promote Codync to a full profile, noting that it began as a Claude Code monitor in March and that its first bot-era release was on 2026-09-25.
- **[Landscape README §1.8](agentic-workspace-landscape/README.md#1-executive-summary):** add Codync (auto-approve) to the weak-defaults list.
- **[2026-10-18 survey](prior/open-source-agent-bots-2026-10-18.md)** (frozen, so not edited): its "Rakazo pins 0.87.1" is superseded by this doc.

### 8.3 Contradictions inside first-party sources

- **nightly OpenBot:** the README lists channel chats and a blanket `danger-full-access` warning, while the CHANGELOG removed channels (0.38.1) and added three permission modes (0.43.0).
- **OpenMausBot:** the README's "Bots ask before they act … A permission broker turns every risky action into a decision you make" against the Full-access default since 0.1.109.
- **Grok Bot:**
  - the landing page names macOS and Windows desktops and iOS; the docs name Linux and Android too;
  - the landing page gives Super 3.5× and Ultra 12× Premium, which doesn't reconcile with the docs' 15×/50× of Plus (3.75×/12.5×);
  - eligibility reads "Premium, Super, Ultra, Teams, and Enterprise" on the landing page, but "every paid individual Cursor plan … Cursor Teams … SuperGrok" in the [overview](https://docs.x.ai/grok-bot/overview) and [mobile docs](https://docs.x.ai/grok-bot/mobile).
- **Codync:** the README's platform table omits Android, while the repo and voice docs contain an Android client.

## 9. What Memoshi should take or avoid [INFERENCE]

The plan stays as it is; these are inputs for the decisions named.

- **Brain ([D6](../plan/decisions.md#d6), [D9](../plan/decisions.md#d9), [D42](../plan/decisions.md#d42)).** Study Aiden's per-Bot Durable harness, its `beforeTool` policy and approvals persisted in the tool memo (MIT). That is the only shipping instance of Memoshi's engine choice.
- **Memory ([D22](../plan/decisions.md#d22)).** Codync supplies the most concrete, copyable rules (Apache-2.0):
  - automatic consolidation only from text the user typed, never from pasted, quoted or forwarded text;
  - capped runs, with an undo log;
  - a forgotten memory is never written again, by a bot or by dreaming, reworded or not;
  - checks on every write;
  - memory changes reach each session as a `<memory_update>` on its next message, while the opening stays unchanged so the prompt cache holds;
  - the harness's own memory turned off.

  Codync also writes memory "whatever its permission"; Memoshi's provenance and scope rules should still govern it.
- **Groups and handoffs ([D24](../plan/decisions.md#d24)).** Reference numbers: Codync's 3 rounds / 10 replies per room turn and 8-hop chains with 16/64 pending caps, and Grok's admin switch for bot-to-bot messaging.
- **Policy defaults ([D27](../plan/decisions.md#d27)).** Codync ships Auto by default; OpenMausBot, OpenBot and Aiden ship Full. The exceptions are Noodle (a fail-closed sandbox with no prompts) and Rakazo (the sandbox is the boundary, and it asks before external writes). Avoid OpenBot's "Always allow ⇒ Full access" escalation and OpenMausBot's Full-access sends without a card.
- **Computers and browsers ([D16](../plan/decisions.md#d16)–[D19](../plan/decisions.md#d19)).**
  - *Copy:* OpenMausBot's browser egress gate (block self, LAN and cloud metadata) and its per-bot persistent profiles; Noodle's browsers assigned per bot; Codync's look-only rule during human takeover.
  - *Reject:* the 0.1.113 bot-detection-evasion browser, as a site-terms risk, and Grok's shared computer, as the contrast case.
- **Remote and mobile ([D38](../plan/decisions.md#d38)).** Codync's relay is the strongest reference: the host is the only authority, the cloud can only shorten grants, a 6-digit code confirms access, and push is sealed. Its webhooks are not end-to-end encrypted, so label any Memoshi relay path that is not.
- **Portable format ([D26](../plan/decisions.md#d26)).** OpenMausBot's MIT BotMRR format and its export exclusions: no credentials, conversations, permissions, memory or computers; routines paused; imports on Ask.
- **Telemetry ([D28](../plan/decisions.md#d28)).** Codync's analytics are on by default and OpenBot sends OpenPanel events; Memoshi stays off by default.
- **Native risk ([D31](../plan/decisions.md#d31)).**
  - *Spike early:* Codync abandoned its SwiftUI + AppKit Mac chat over long-transcript scrolling and streaming, so Memoshi should spike long-transcript performance before the Phase 0 transcript design hardens. Noodle and Kuvo show it can work natively.
  - *Don't copy:* Codync's "Grok-Bot-style" avatar shapes, which are derived from a proprietary design ([D33](../plan/decisions.md#d33)).
- **Subscriptions ([D10](../plan/decisions.md#d10)).** These need policy review before Memoshi copies them:
  - MausBot Cloud runs users' Claude or ChatGPT CLI logins on vendor-run machines;
  - Noodle's Hub lends sign-ins to other people.

## 10. Limits and open questions

- **No hands-on validation.** Every capability above is documented, source-inspected or inherited. None was exercised, and no reliability, security, latency or memory-quality claim is made.
- **Not audits.** Source reading was limited to the files cited: Codync `model.rs` and `backends.rs`, OpenMausBot `pi.ts`, Aiden's runtime note, `pi-codemode.ts` and `package.json`, Rakazo's `package.json`, and license files.
- **Moving targets.** `main` moves several times a day, so the SHAs in §2 bound the observations.
- **Unresolved:**
  - OpenBot's hosted prices, which appear only in an image;
  - Codync Cloud's [terms](https://codync.dev/terms), not read;
  - the target of Grok Bot's "More downloads" link;
  - Grok Bot 0.72.0, installed locally but not in the changelog.
- **Open questions:**
  - Does Codync's native-transcript failure apply to Memoshi's planned transcript stack? Answering it needs a Phase 0 spike.
  - Will Codync's `Auto` default, or OpenMausBot's Full-access default, be reversed? Watch their releases.
  - Who is the contracting entity for Grok Bot under The X Subscription?

## 11. Sources

Primary, fetched 2026-10-20:

1. https://x.ai/bot, https://x.ai/news/introducing-grok-bot, https://x.ai/changelog/bot
2. https://docs.x.ai/grok-bot/overview, https://docs.x.ai/grok-bot/mobile, https://docs.x.ai/grok-bot/security, https://docs.x.ai/grok-bot/security-faq, https://docs.x.ai/x-subscription/pricing
3. https://cursor.com/terms/grok-bot
4. https://apps.apple.com/us/app/grok-bot/id6794501026; https://apps.apple.com/app/codync/id6760984418; https://apps.apple.com/app/rakazo/id6801531099; https://apps.apple.com/in/app/mausbot/id6803387923 (all via `itunes.apple.com/lookup`)
5. Codync:
   - https://github.com/leepokai/Codync (README, LICENSE, NOTICE, TRADEMARK.md, SECURITY.md);
   - `docs/features/`: `context-and-memory.md`, `routines.md`, `computer-use.md`, `voice-call.md`, `groups-and-replies.md`, `bot-collaboration.md`, `bot-workspaces.md`, `connector-credentials.md`, `analytics.md`, `remote-screen.md`;
   - `docs/reference/remote-relay.md`, `host/src/store/model.rs`, `host/src/agent/backends.rs`, `apps/android/README.md`;
   - releases v1.0.0, v2.1.0, v2.5.1, v2.7.0, v2.11.0, v2.12.0, v2.18.0, v2.20.4.
6. OpenMausBot:
   - https://github.com/milind-soni/OpenMausBot (README, LICENSING.md, SECURITY.md, `server/drivers/pi.ts`, `docs/ios-companion.md`);
   - releases v0.1.108–v0.1.119, PR #3032;
   - https://mausbot.com/pricing;
   - https://github.com/milind-soni/openmausbot-teams/blob/main/FORMAT.md.
7. Rakazo: https://github.com/elie222/rakazo (README, LICENSE, `packages/adapters/package.json`); PRs #1501, #1519, #1550; release v0.3.1.
8. Noodle: https://github.com/pdparchitect/noodle (README, LICENSE, `docs/security.md`, `docs/harness-setup.md`); release v0.70.0.
9. Aiden Agent: https://github.com/sambitcreate/aiden-agent (README, LICENSE, `package.json`, `.memory/bot-durable-runtime.md`); PRs #505, #515; releases v0.57.0–v0.59.0.
10. nightly OpenBot: https://github.com/nightly-labs/openbot (README, LICENSE, CHANGELOG.md, `docs/architecture/providers.md`); https://openbot.run/guides/openbot-hosted-servers.
11. CopilotKit OpenBot: https://github.com/CopilotKit/OpenBot (README, LICENSE); release v0.2.0.
12. Pi: https://github.com/earendil-works/pi (`packages/coding-agent/docs/rpc.md`, `packages/durable/README.md`); release v1.3.0.
13. ACP: https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json; https://github.com/svkozak/pi-acp.

Discovery, not used as benchmark truth:

14. https://my-tierroom.party/explore, https://my-tierroom.party/blog/open-source-grok-bot-alternatives-mausbot-rakazo-codync-openbot, https://my-tierroom.party/agents/codync.md

Inherited, in-repo:

15. [Landscape profiles](agentic-workspace-landscape/projects/): grok-bot, openmausbot, openbot, rakazo, noodle, aiden-agent
16. [Long tail](agentic-workspace-landscape/landscape/oss-long-tail.md), [2026-10-18 survey](prior/open-source-agent-bots-2026-10-18.md), [comparison report](2026-10-20-comparison-report.md), [memory and orbs research](2026-10-20-memory-orbs.md) (peer task)
