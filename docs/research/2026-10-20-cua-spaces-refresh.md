# Cua Spaces, Cua SDK, Cua Driver and Lume: refresh and reuse map for Memoshi

> Snapshot: 2026-10-20, about 20:30 UTC. Research input for the Grok-style + Kuvo Code + Pi assistant synthesis. It checks two user-supplied X posts, Cua's current products (Cua Spaces, the "Cua Spaces SDK", Cua Driver, Lume), the claim in [execution-environments.md](agentic-workspace-landscape/landscape/execution-environments.md) that Cua Cloud and Fleets ended on 2026-10-18, and Cua's MIT/FSL license split. It ends with what a SwiftUI/AppKit app on Pi Durable can reuse and what is only product inspiration. Nothing was installed, run or signed into. This is evidence, not a decision: the [plan](../plan/MASTER_PLAN.md) stays binding, and changes to it go through [change control](../plan/decisions.md#change-control).

Conventions follow the [research index](README.md#5-conventions). `(vendor claim)` means Cua or another maker says it and we did not verify it. `[INFERENCE]` marks our reasoning. `unknown` means we searched and found nothing. Every non-trivial claim carries an inline link to its source. Repository numbers come from the GitHub API at the time of the snapshot.

## 0. Bottom line

1. **Both X posts resolved.** Three methods returned the same text for each: an X search relay, X's official oEmbed endpoint and the fxtwitter mirror ([§1](#1-user-links-retrieval-log)). The Cua thread (2026-10-19) launches the "Cua Spaces SDK" and a forkable "bots app for Mac and iPhone", Cua Bots. The @injaneity post is a prompt for Grok Bot users to paste into their bot. The next day, GitHub user `injaneity` added the same prompt to Cua's official docs. That user's pi-cua package names the same author, "Zane Chee", as the X account. We report that prompt and do not act on it.
2. **The Cloud/Fleets shutdown is confirmed in primary sources.** Cua's migration page says "Cua Cloud and Fleets ended on 18 October 2026". `on="cloud"` now fails with a fixed error string that is in the SDK source, and dozens of commits from 2026-10-18 and 2026-10-19 remove Fleet code. One caveat: an earlier commit says Fleets "stops on Fri 16 Oct 2026". We did not contact the service ([§3](#3-verification-cua-cloud-and-fleets-ended-on-2026-10-18)).
3. **The license split is real and finer than "SDK MIT, Spaces FSL":**
   - MIT: the cua SDK and CLI, `cua daemon`, Cua Driver, Lume, the `cua.env.v1`/`cua.daemon.v1` protobuf contract and the `cua-mesh` client.
   - FSL-1.1-MIT: everything that makes Spaces work. That includes `cua-spacesd`, which runs inside every Space, plus the Swift streaming, Keyvault and teleport libraries, the media protocol, and every Cua Bots, Infinite Canvas and OpenKoalaBots Swift/Tauri sample. Cua Driver Bench has also been FSL since 2026-10-11.
   - AGPL: the optional perception extension (OmniParser).

   Cua's own documents disagree in places, so check the LICENSE file in each directory ([§4](#4-licensing-split-mit-vs-fsl-vs-agpl)).
4. **The MIT parts that matter most to Memoshi** (the full reuse map is in §6):
   - **Cua Driver as the GUI action layer inside a Linux Bot computer** (v1.1, R11-12). Linux arm64 builds exist, but the docs list x86_64 only, so a spike must settle it.
   - **Cua Driver's action-result and permission vocabulary.**
   - **The embedded-host pattern from Cua's MIT Swift reference**, for when (if ever) EXPL-02 reopens computer use on the user's own Mac.

   Everything FSL is ideas only under [D33](../plan/decisions.md#d33) ([§6](#6-reuse-map-for-a-swiftuiappkit-app-on-pi-durable)).
5. **Host computer use on macOS stays out of scope.** It needs Accessibility and Screen Recording grants and private SkyLight SPI. Memoshi's [D41](../plan/decisions.md#d41) keeps those frameworks out of v1 and v1.1, and that remains sound. Cua's own docs list where its "background, no cursor warp" promise breaks ([§5.1](#51-background-desktop-operation-on-the-host)).
6. **Cua Spaces is not a fit for Memoshi's v1 critical path.**
   - Its "This Mac" Space hands the agent the user's real desktop.
   - Its hosted relay is a TLS-terminating proxy that can read sessions in plaintext. End-to-end encryption is beta and off by default.
   - Its rules for Cua Bots are prompts, not enforcement.
   - Its core pieces are FSL.

   A Spaces adapter for users who already run Cua is at most a v2 option behind the computer seam ([§8](#8-recommendations)).
7. **Marketing and docs diverge in a few places.** The X thread names Azure; the docs never mention it. E2B and Daytona need a source build with `--features contrib`, and Cua's own support matrix lists them as "not measured". We make no performance or benchmark comparison in this doc.

## 1. User links: retrieval log

The request listed the Cua link twice; it is logged once below.

| User link | Methods and outcome | Content observed | Relevance to Memoshi | Limits |
|---|---|---|---|---|
| [x.com/trycua/status/2112228154651881479](https://x.com/trycua/status/2112228154651881479) (canonical; submitted twice) | (1) Direct `read` through an X search relay, which returned the 5-post thread and replies; the tool notes that "the model relays the text". (2) X's official oEmbed endpoint ([oEmbed](https://publish.twitter.com/oembed?url=https://twitter.com/x/status/2112228154651881479); a 301 redirect, then 200) returned post 1 verbatim, by "Cua (@trycua)". (3) The fxtwitter mirror returned posts 1–5 with timestamps and expanded links ([post 1](https://api.fxtwitter.com/status/2112228154651881479)). All three agree. | Mon 2026-10-19 17:03 UTC. **1/** "Introducing the Cua Spaces SDK. Every big lab now ships a bot with its own computer: Grok Bot, Muse, dots. None let you bring your own. With Cua Spaces, now you can. Put Claude Code, Codex or any agent on compute you choose, and run jobs across all your computers at once." **2/** "Each bot gets its own Space… your laptop or the office Mac mini, in your own AWS, Google Cloud or Azure account, or on a sandbox provider like E2B, Daytona or Modal. Watch it work and take over anytime." **3/** "Ten lines to start one… Change `on: "local"` to the name of another of your computers". **4/** "Claude Code, Codex, Gemini CLI, Goose, OpenCode, Hermes or your own." **5/** "Fork the full bots app for Mac and iPhone" plus a docs link. Video frames we inspected (6-frame previews of the post 1, 3 and 5 videos) show the `startThread(embedded().spaces(), {agent: "claude-code", … placement: {type: "dedicated", on: "local"}})` snippet switching to `on: "host:office mac mini"`, koala bot faces, "Self-host your bots.", `ghcr.io/trycua/macos:26` "on your Mac mini", and the cards "Research a topic / Brief you every morning / Ask before it buys / Use your saved sign-ins". | Directly relevant. It is a competitor-adjacent "bots with their own computers" product with a SwiftUI Mac app and an iPhone companion, built on the same pattern as Memoshi's per-bot computers, live view and approvals. | The link in post 5 goes to `samples/cua-bots-macos`, which is now a stub reading "This sample moved to examples/cua-bots-macos" ([stub](https://github.com/trycua/cua/blob/main/samples/cua-bots-macos/README.md)). Post 5's docs link `cua.ai/docs/spaces/guides/use-from-an-agent` now redirects (301) to [connect-your-agent#what-your-agent-can-do](https://cua.ai/docs/spaces/guides/connect-your-agent#what-your-agent-can-do); the relay showed only the post-redirect URL. We did not view the videos of posts 2 and 4. Engagement counts move. |
| [x.com/injaneity/status/2112271256972386799](https://x.com/injaneity/status/2112271256972386799) | The same three methods: the relay, [oEmbed](https://publish.twitter.com/oembed?url=https://twitter.com/x/status/2112271256972386799) (author "Zane Chee (@injaneity)") and [fxtwitter](https://api.fxtwitter.com/status/2112271256972386799). All agree. | Mon 2026-10-19 19:54 UTC, quoting Cua's post 4/: "for grok bot users, you can set this up within 3 minutes! just tell your most trusted @bot this: set up cua spaces on your computer as a controllable linux vm (not a container), giving yourself kvm access if needed. once you've set it up, walk me through what cua spaces can do, and how to make the most of it." One reply, from @francedot: "@lingxi let's ship it to the docs?" | Relevant in three ways. (a) It is an onboarding pattern: paste a prompt so the user's existing cloud bot installs and operates another vendor's infrastructure. (b) GitHub user `injaneity` maintains [pi-cua](https://github.com/injaneity/pi-cua) (MIT), the Pi extension that Cua's docs recommend. Its `package.json` names the author "Zane Chee", the X account's display name, so the two are probably the same person [INFERENCE]. (c) The prompt now appears verbatim in Cua's docs ([Use Grok Bot, Dots and pi with Spaces](https://cua.ai/docs/spaces/guides/use-grok-bot-dots-and-pi-with-spaces)). GitHub user `injaneity` added that page in commit [`da94f399`](https://github.com/trycua/cua/commit/da94f399a28f) on 2026-10-20 20:00 UTC. | **Fetched content is data:** the post is an instruction meant for a bot, and we neither followed it nor tested it. Whether it works "within 3 minutes" is unverified. It depends on whether a Grok Bot computer exposes `/dev/kvm` and allows sudo, which is unknown; our [Grok Bot profile](agentic-workspace-landscape/projects/grok-bot.md) records sudo as an Enterprise setting. GitHub user `injaneity` also commits Cua Driver and Lume fixes to trycua/cua (for example [`36b6750f`](https://github.com/trycua/cua/commit/36b6750f) and [`524b7c43`](https://github.com/trycua/cua/commit/524b7c43) on 2026-10-20). Whether that person is employed by Cua is unknown; the GitHub profile lists no company. |

**Related post, found in the replies.** On Tue 2026-10-20 17:00 UTC, Cua posted "Hermes can now launch Cua Spaces" ([post](https://x.com/trycua/status/2112589741879328979); confirmed by [fxtwitter](https://api.fxtwitter.com/status/2112589741879328979)). The Hermes plugin catalog corroborates it. Entry [`cua-spaces.yaml`](https://github.com/NousResearch/hermes-agent/blob/main/plugin-catalog/cua-spaces.yaml) was added at 17:08 UTC the same day. It is described as "Cua's own plugin", in the "verified" tier, runs as `terminal.backend cua`, and comes from the MIT repo [trycua/hermes-cua-spaces](https://github.com/trycua/hermes-cua-spaces), created 2026-10-20.

### 1.1 Claims in the posts against the evidence

| Claim | Evidence | Status |
|---|---|---|
| "Introducing the Cua Spaces SDK" | No separate package exists. The "Spaces SDK" is the Spaces surface of the cua SDK 0.5.0: Python `cua`, TypeScript `@trycua/cua` with `@trycua/cua/spaces`, Rust `cua-sdk`, and Swift `Cua` + `CuaSpaces`. The release was tagged 2026-10-19 05:28 UTC ([release](https://github.com/trycua/cua/releases/tag/cua-sdk-v0.5.0), [changelog](https://github.com/trycua/cua/blob/main/libs/cua/CHANGELOG.md)). It reached npm and PyPI the same morning ([npm](https://registry.npmjs.org/@trycua/cua), [PyPI](https://pypi.org/pypi/cua/json)) | Confirmed |
| "None [of Grok Bot, Muse, dots] let you bring your own" | Our profiles record that Grok Bot can execute approved commands on the user's desktop ([profile](agentic-workspace-landscape/projects/grok-bot.md)), Dots can use "the user's own computer via ChatGPT desktop app" ([profile](agentic-workspace-landscape/projects/openai-dots.md)), and Muse's Mac app "acts in native macOS apps" ([profile](agentic-workspace-landscape/projects/meta-muse.md)). None of them takes your own VM or compute as the bot's dedicated computer | Vendor claim; true only in the narrow sense of BYO dedicated compute |
| "your own AWS, Google Cloud or Azure account" | The docs list `aws`, `gcp` and `modal` ([where sandboxes run](https://cua.ai/docs/cua-sdk/guides/local-runtimes)). A search of the full docs ([llms-full.txt](https://cua.ai/docs/llms-full.txt), 2.5 MB) finds no mention of Azure | Azure unsupported in docs |
| "or on a sandbox provider like E2B, Daytona or Modal" | E2B and Daytona are "opt-in. The default `cua` build knows the words… A build with `--features contrib` includes them". The nightly support matrix shows e2b, daytona and modal as "not measured… never" ([providers](https://cua.ai/docs/cua-sdk/guides/local-runtimes#other-sandbox-providers)) | Exists in code; unmeasured by the vendor |
| "Watch it work and take over anytime" | There are live streams, viewer and editor roles, and editor input "as a human" ([share](https://cua.ai/docs/spaces/guides/share-a-space)). In Cua Bots, "The bot has control until you take over" ([Cua Bots](https://cua.ai/docs/spaces/examples/cua-bots)) | Documented; not tested |
| "Ten lines to start one" | The `startThread` example in [connect-your-agent](https://cua.ai/docs/spaces/guides/connect-your-agent#run-an-agent-inside-a-space) has ten lines | Documented; not run |
| "Bring any agent" | The harness ids are `claude-code`, `openai-codex`, `gemini-cli`, `google-antigravity`, `opencode`, `goose`, `pi`, `hermes` and `openclaw`. For `pi` the note says "Community ACP adapter; no MCP client" ([run a coding agent](https://cua.ai/docs/cua-sdk/guides/run-a-coding-agent)) | Documented; not run |
| "Fork the full bots app for Mac and iPhone" | [examples/cua-bots-macos](https://github.com/trycua/cua/tree/main/examples/cua-bots-macos) (macOS 14+) and [examples/cua-bots-ios](https://github.com/trycua/cua/tree/main/examples/cua-bots-ios) (iOS 18+). Both are **FSL-1.1-MIT**. Running them means building the Rust FFI from source; "local Spaces need Docker" ([Cua Bots](https://cua.ai/docs/spaces/examples/cua-bots)) | Exists; source-available, not open source |

## 2. What Cua is now

### 2.1 Product map

| Component | What it is | License | Latest release | Requirements | Notes |
|---|---|---|---|---|---|
| **Cua Spaces app** | Desktop app that gives agents "full desktops": a Space is "a container or a VM, or the computer's own desktop" ([how Spaces works](https://cua.ai/docs/spaces/concepts/how-spaces-works)). Native SwiftUI on macOS; Tauri on Windows and Linux; an Electron preview | FSL-1.1-MIT ([LICENSING.md](https://github.com/trycua/cua/blob/main/legal/LICENSING.md)) | 0.11.0, 2026-10-20 ([release](https://github.com/trycua/cua/releases/tag/cua-spaces-v0.11.0)); the README still links the 0.9.4 DMG | macOS 26+; Windows "preview"; Ubuntu 24.04 is the only supported Linux ([install](https://cua.ai/docs/spaces/guides/install)) | Launches at login by default. 0.11.0 adds "Cua asks before a second agent connects, and before an agent does something risky" on This Mac |
| **cua-spacesd** | The daemon inside each Space (port 3211, gRPC and gRPC-Web): processes, files, screenshots, input through Cua Driver, streaming and teleport ([how sandboxes work](https://cua.ai/docs/cua-sdk/concepts/how-sandboxes-work)) | **FSL-1.1-MIT**, including `cua-relay` ([LICENSING.md](https://github.com/trycua/cua/blob/main/legal/LICENSING.md)) | 0.5.3, 2026-10-03 | Ships in Cua's images | It replaced the deprecated `cua-computer-server` |
| **cua SDK, `cua` CLI, `cua daemon`** | A Rust core with UniFFI bindings, embedded in your process or shared through a local daemon. It has "no agent layer"; you drive it from your own harness ([own harness](https://cua.ai/docs/cua-sdk/guides/own-harness)) | MIT | 0.5.0, 2026-10-19. Python `cua` 0.5.0 and `cua-sandbox` 0.9.1 on PyPI; `@trycua/cua` 0.5.0 on npm. Rust only by git tag ("not on crates.io yet") | Local runtimes: gVisor when installed, else runc, on Docker or Podman; QEMU for VMs; Lume for macOS guests ([runtimes](https://cua.ai/docs/cua-sdk/guides/local-runtimes)) | **Swift `Cua` is "not yet released"**: [`Package.swift`](https://github.com/trycua/cua/blob/main/libs/cua/swift/Package.swift) has `releaseURL = ""`, so you build the Rust library yourself. Kotlin is not released either ([README](https://raw.githubusercontent.com/trycua/cua/main/README.md)) |
| **`CuaSpaces` Swift overlay** | A thin Swift layer over `Cua` for Spaces: attach or create, agent runs, files ([README](https://github.com/trycua/cua/blob/main/libs/spaces-sdk-swift/README.md)) | MIT. "The live screen (`CuaSpacesStreaming`…) is part of Cua Spaces… FSL-1.1-MIT" | Unreleased (path dependency) | macOS 14+ | It was extracted from a 46-entry `FRICTION.md` log kept while building the OpenKoalaBots Swift sample. Its README example still mentions `on: .cloud`, which is stale |
| **Cua Driver** (`cua-driver-rs`) | Background computer-use driver for macOS, Windows and Linux; CLI, MCP and SDKs ([overview](https://cua.ai/docs/cua-driver)) | MIT (`license = "MIT"` in [Cargo.toml](https://github.com/trycua/cua/blob/main/libs/cua-driver/rust/Cargo.toml)); code derived from yabai, T3 Code and others is credited in [THIRD_PARTY_NOTICES](https://github.com/trycua/cua/blob/main/libs/cua-driver/rust/THIRD_PARTY_NOTICES.md) | 0.37.0, 2026-10-20. **All 107 `cua-driver-rs-v*` GitHub releases are flagged pre-release.** 0.34.0 shipped on 2026-10-05, so four minor versions landed in 15 days | macOS 14+ (Accessibility and Screen Recording); Windows 10, 11 or Server with an interactive session; Linux "64-bit (x86_64)" ([overview](https://cua.ai/docs/cua-driver)). The [0.37.0 assets](https://github.com/trycua/cua/releases/tag/cua-driver-rs-v0.37.0) also include linux-arm64, Windows arm64 and Sigstore bundles | No Swift binding: Python, TypeScript and Rust only. Telemetry is on by default |
| **Lume** | macOS and Linux VMs on Apple silicon through Virtualization.framework; CLI, a localhost HTTP API and MCP ([overview](https://cua.ai/docs/lume)) | MIT | 0.6.1, 2026-10-04 | Apple silicon. The docs say "macOS 13 or later", but [`Package.swift`](https://github.com/trycua/cua/blob/main/libs/lume/Package.swift) declares `.macOS(.v14)`. 8 GB free RAM; 50 GB per macOS guest; at most two macOS guests | Uses the **private** `_VZVNCServer` SPI through the `Dynamic` library ([VNCService.swift](https://github.com/trycua/cua/blob/main/libs/lume/src/VNC/VNCService.swift)). Telemetry is on by default |
| **Cua Bench / Cua Driver Bench / CUA-S1** | Evaluation harnesses and small decision models | Bench: MIT. **Driver Bench: FSL-1.1-MIT**; its versions published before 11 Oct 2026 were MIT. CUA-S1 source: MIT; weights per their Hugging Face cards ([README](https://raw.githubusercontent.com/trycua/cua/main/README.md)) | Bench 0.3.1, 2026-10-19 | n/a | Out of scope here. We cite no benchmark results |
| **cua-perception** (optional Driver extension) | Parses a screenshot into labeled regions on the local CPU | **Not MIT**: an AGPL-3.0-only OmniParser model plus Apache-2.0 PP-OCR ([how it works](https://cua.ai/docs/cua-driver/concepts/how-cua-driver-works#the-optional-perception-extension)) | 0.2.1, 2026-09-26 | macOS arm64, Linux x64, Windows x64 | "Redistributing it, or offering it to users over a network, can trigger AGPL-3.0 source obligations" |
| **cua-mesh** | A WireGuard-based userspace mesh between your devices and computers (boringtun, no TUN, no root) | MIT client; "A hosted machine's side of it is part of cua-spacesd (FSL)" ([LICENSING.md](https://github.com/trycua/cua/blob/main/legal/LICENSING.md), [Cargo.toml](https://github.com/trycua/cua/blob/main/libs/cua/crates/cua-mesh/Cargo.toml)) | A crate in the cua Rust workspace; per the docs it runs "inside Cua itself", with no VPN profile or system extension | n/a | **Beta, off by default** (`CUA_MESH`) ([relay security](https://cua.ai/docs/spaces/guides/relay-security)) |
| **Deprecated** | `cuabot`, `cua-computer`, `cua-computer-server`, `cua-agent` | MIT, no longer maintained | Latest in the registries: `cuabot` 1.0.14 on npm (2026-02-10), and on PyPI `cua-computer` 0.5.19, `cua-computer-server` 0.3.46 and `cua-agent` **0.9.1**. `cua-agent` 0.9.1 is the 2026-10-19 security fix for GHSA-gj99; the migration page still says 0.9.0 ([npm](https://registry.npmjs.org/cuabot), [PyPI](https://pypi.org/pypi/cua-agent/json)) | n/a | "`cuabot` has known security issues… Do not run it" ([migration](https://cua.ai/docs/cua-sdk/guides/cua-cloud-ended)). The npm registry's latest `cuabot` version carries no `deprecated` notice, so `npx cuabot` would still install it without a warning [INFERENCE from registry metadata] |

**Plans** (hosted relay, sharing and teams only, because "Cua doesn't rent computers"):
- Free: $0, 2 live sessions, 20 remote hours a month.
- Pro: $18 a month or $180 a year, 5 sessions, 200 hours.
- Teams: $30 per seat a month or $300 per seat a year, 1–100 seats, pooled.

Spaces reached directly on your network do not count against these limits ([pricing](https://cua.ai/pricing), [teams](https://cua.ai/docs/spaces/guides/teams)). Two of Cua's own pages disagree. The pricing page lists "Sharing a Space with named people" under Free. The Teams and Share pages say "Sharing is for teams: Free and Pro accounts without a team cannot share a Space".

**Repository health.** [trycua/cua](https://github.com/trycua/cua) has 30,420 stars, 2,195 forks and 1,163 open issues, and was last pushed 2026-10-20 20:13 UTC. Between 2026-10-13 and 2026-10-20 it took 365 commits, and 254 of them carry a `Co-authored-by: Claude` trailer (GitHub API). [INFERENCE] Heavy agent-assisted development and daily releases mean APIs churn quickly. The Driver's 0.35 release changed `get_window_state` defaults and `type_text` newline semantics ([operate](https://cua.ai/docs/cua-driver/guides/operate#before-updating-to-035)).

**Ecosystem uptake of Cua Driver**, from our profiles:
- Hermes ships computer use "via the `cua-driver` MCP" ([profile](agentic-workspace-landscape/projects/hermes-agent.md)).
- OpenBot bundles it ([profile](agentic-workspace-landscape/projects/openbot.md)).
- OpenMausBot bundles and pins it, and uses Cua's Xfce image for local VMs ([profile](agentic-workspace-landscape/projects/openmausbot.md)).
- Aiden pins 0.34.1 behind its own broker ([profile](agentic-workspace-landscape/projects/aiden-agent.md)).
- T3 Code patched it for Linux ([THIRD_PARTY_NOTICES](https://github.com/trycua/cua/blob/main/libs/cua-driver/rust/THIRD_PARTY_NOTICES.md)).

[INFERENCE] Among the open-source bot apps we profiled, Cua Driver is the de facto host computer-use driver.

## 3. Verification: "Cua Cloud and Fleets ended on 2026-10-18"

**Verdict: confirmed from primary sources, with a date caveat.** We did not test the service itself.

| Evidence | What it shows |
|---|---|
| [Migrate from Cua Cloud and deprecated packages](https://cua.ai/docs/cua-sdk/guides/cua-cloud-ended) | "Cua Cloud, including Cua Fleets (pools, claims, warm replicas and the Terraform provider), ended on 18 October 2026. The Fleets pages have been removed." `on="cloud"`, `local=False`, `--on cloud` and `pool:` references fail with "Cua Cloud has ended; use a local sandbox or your own computer." `Cua.fleet()`, `cua fleet`, `cua pools`, `FLEETS_TOKEN` and cloud suspend/resume/extend-lease are removed |
| Code | GitHub code search finds the error string in 97 files, including `libs/cua/crates/cua-sdk/src/native/config.rs` and `libs/python/cua-sandbox/cua_sandbox/_ended.py`. Commit [`5d78ec8b`](https://github.com/trycua/cua/commit/5d78ec8b7705d942a3d260b276bcce76614a634c) (2026-10-18 08:24 UTC) added it |
| Removal commits | Between 2026-10-18 and 2026-10-19 the repo got [`c6540d2c`](https://github.com/trycua/cua/commit/c6540d2c) ("docs: Cua Cloud ended on 18 October 2026"), [`348c47cc`](https://github.com/trycua/cua/commit/348c47cc) ("delete the Fleet SDK, pools and claims…") and about 15 more (CUA-1833, -1834, -1836) |
| **Date caveat** | Commit [`c4ec0dd9`](https://github.com/trycua/cua/commit/c4ec0dd9) (2026-10-18 00:07 UTC) is titled "remove the Cua Fleets docs after the 16 Oct shutdown". Its body says "Cua Cloud (Fleets) stops on Fri 16 Oct 2026". All later docs say 18 October |
| What still runs as a Cua-hosted service | **The relay** (`relay.cua.ai`), accounts, Teams, device enrollment and billing ([how Spaces works](https://cua.ai/docs/spaces/concepts/how-spaces-works), [teams](https://cua.ai/docs/spaces/guides/teams)). "Bring your own compute" does not mean "no Cua service in the path" whenever a computer is reached through the relay |
| Replacement for hosted capacity | Your own AWS (EC2 `t4g.medium` "about $0.04/hour"), Google Cloud (`e2-medium` "about $0.04/hour") or Modal ("about $0.24/hour"). These are vendor estimates. Sandboxes get an 8-hour time limit by default, an account can hold at most 32 machines, and macOS is not offered in any cloud ([your own cloud](https://cua.ai/docs/cua-sdk/guides/local-runtimes#your-own-cloud)) |

## 4. Licensing split: MIT vs FSL vs AGPL

**The rule as Cua states it.** "MIT code defines extension points; FSL code implements them; MIT code never links FSL code." `scripts/check-license-direction.py` enforces this in CI (vendor claim; we did not run it) ([LICENSING.md](https://github.com/trycua/cua/blob/main/legal/LICENSING.md)).

| Bucket | Components | Evidence | Status for Memoshi under [D33](../plan/decisions.md#d33) |
|---|---|---|---|
| **MIT** | cua SDK (Python, TypeScript, Rust, and the unreleased Swift and Kotlin); the `cua` CLI; `cua daemon`; the client side of Spaces orchestration (create/list/delete, `host_spaces`, `cua-host`); the `cua-proto` contract (`cua.env.v1`, `cua.daemon.v1`, including `StreamService` tickets); `MediaSession` (encoded frames); `@trycua/cua/spaces/pip`; `cua-mesh`; **Cua Driver**; **Lume**; Cua Bench; CUA-S1 source; `libs/kasm`; the `CuaSpaces` Swift overlay; the OpenKoalaBots **TypeScript** sample (`"license": "MIT"` in [package.json](https://github.com/trycua/cua/blob/main/examples/openkoalabot-example-ts/package.json); no own LICENSE file, so the root MIT applies) | [LICENSING.md](https://github.com/trycua/cua/blob/main/legal/LICENSING.md), [root LICENSE](https://github.com/trycua/cua/blob/main/LICENSE.md) | Code may be copied with attribution. **Assets may not** (for example `examples/openkoalabots-assets`) |
| **FSL-1.1-MIT** | The Spaces apps (SwiftUI, Tauri, web, Electron); **cua-spacesd and cua-relay**; `cua-spaces-app-core`; `cua-keyvault`; `cua-teleport` and `-bundle`; `cua-machine-seal`; `cua-volume`; `cua-spaces-ext`; `cua-spaces-ffi`; `cua-spaces-cli`; the media protocol, transport, client and codec; `cua-viewer`; `cua-spacesd-html5`; `cua-logging`; `libs/spaces-app-swift` (`CuaSpacesFFI`, `CuaSpacesTeleport`, `CuaSpacesStreaming`); `libs/spaces-notch-swift`; **Cua Bots macOS and iOS**; Infinite Canvas; the OpenKoalaBots **Swift and Tauri** samples; Cua Driver Bench; plus `cua-chromium-storage` and `libs/cua/bench/streaming`, which have FSL LICENSE files but are missing from the table | The LICENSE files themselves ([Cua Bots](https://github.com/trycua/cua/blob/main/examples/cua-bots-macos/LICENSE), [media protocol](https://github.com/trycua/cua/blob/main/libs/cua/crates/cua-media-protocol/LICENSE), [chromium storage](https://github.com/trycua/cua/blob/main/libs/cua/crates/cua-chromium-storage/LICENSE)) | **Ideas only.** D33 copies only MIT, Apache-2.0 or BSD code |
| **AGPL** | `cua-perception` (OmniParser icon detector, AGPL-3.0-only) and `cua-som` (AGPL-3.0-or-later) | [README](https://raw.githubusercontent.com/trycua/cua/main/README.md) licensing section | Avoid. Never ship them, and do not install them in Memoshi images |

**What FSL-1.1-MIT forbids.** It permits any purpose except a **Competing Use**, which it defines as:

> making the Software available to others in a commercial product or service that: 1. substitutes for the Software; 2. substitutes for any other product or service we offer using the Software that exists as of the date we make the Software available; or 3. offers the same or substantially similar functionality as the Software.

([license text](https://github.com/trycua/cua/blob/main/examples/cua-bots-macos/LICENSE))

[COMMERCIAL.md](https://github.com/trycua/cua/blob/main/legal/COMMERCIAL.md) adds that offering Spaces "or a product built on it, to others as a hosted or managed service (for example hosted desktops, sandboxes or computer-use environments)" needs a commercial license. Each release "becomes MIT two years after it ships".

[INFERENCE, not legal advice] Memoshi is open core, with an Apache-2.0 app and daemon ([D33](../plan/decisions.md#d33)), a planned paid "Memoshi Cloud" with hosted relay and cloud computers ([D39](../plan/decisions.md#d39), [D40](../plan/decisions.md#d40)), and per-bot computers with live view, takeover and approvals ([D16](../plan/decisions.md#d16)–[D19](../plan/decisions.md#d19)). That plausibly meets clause 3 for the Spaces app and the Cua Bots samples. D33 already forbids copying source-available code, so the practical rules are:
- never link or bundle any FSL crate or library;
- never put `cua-spacesd` in a Memoshi VM image;
- treat Cua Bots and the Spaces UI as screenshots of ideas.

Code released around 2026-10-20 converts to MIT around 2028-10-20.

**Inconsistencies in Cua's documents:**
- The README says "The streaming wire protocol stays MIT". The `cua-media-protocol` LICENSE file and LICENSING.md say the media protocol and transport are FSL; only the `cua-proto` gRPC contract is MIT.
- LICENSING.md claims to list "every licence file tracked in the repository". The git tree has 44 LICENSE files, and four are missing from the table: two FSL (`cua-chromium-storage`, `libs/cua/bench/streaming`) and two MIT (`cua-cursor-motion` in Rust and TypeScript).

Before reusing anything, check the LICENSE file in the directory at a pinned commit.

## 5. Capability analysis against Memoshi's questions

### 5.1 Background desktop operation on the host

**Mechanism, per Cua's docs and design notes:**
- Cua Driver is "the UI layer of a computer-use agent": `model -> agent harness -> Cua Driver (MCP, CLI, or SDK) -> OS accessibility + input -> apps` ([how it works](https://cua.ai/docs/cua-driver/concepts/how-cua-driver-works)).
- On macOS it uses the Accessibility API, "Scoped CoreGraphics and SkyLight events" and "ScreenCaptureKit per window".
- Cua's launch post spells out the private pieces: SkyLight's **`SLEventPostToPid`**, **`SLPSPostEventRecordTo`** for focus-without-raise (copied from yabai and credited in [THIRD_PARTY_NOTICES](https://github.com/trycua/cua/blob/main/libs/cua-driver/rust/THIRD_PARTY_NOTICES.md)), and the private **`_AXObserverAddNotificationAndCheckRemote`**, which keeps the trees of occluded Electron apps alive ([blog, 2026-04-23](https://cua.ai/blog/inside-macos-window-internals)).
- The post also describes a decoy left-click at `(-1, -1)` that "ticks" Chromium's user-activation gate, so the real click "is treated as a trusted continuation".
- The current design plan confirms the keyboard "posts through `SLEventPostToPid` with a public `CGEvent::post_to_pid` fallback. Both transports are process-scoped" ([macOS background input v1 plan](https://github.com/trycua/cua/blob/main/libs/cua-driver/docs/macos-background-input-v1-plan.md), status "Proposed", 2026-08-04).

**Action ladder** ([how it works](https://cua.ai/docs/cua-driver/concepts/how-cua-driver-works#the-action-ladder)):
1. Element in the background: `AXPerformAction`, UI Automation Invoke, or AT-SPI. "The only rung the driver can verify itself."
2. Pixel in the background.
3. Page: CDP for browser tabs.
4. Foreground, where the window is raised and then restored.

**Where background mode breaks, in Cua's own words:**
- Canvas apps and games (Blender, Unity, "most native games, and some WebGL-heavy Electron apps") need the foreground. Their "pixel clicks silently no-op" ([troubleshoot](https://cua.ai/docs/cua-driver/guides/troubleshoot#known-limits)).
- A macOS drag-and-drop needs a brief foreground step. It runs only with `CUA_DRIVER_ALLOW_BRIEF_FOREGROUND=1`, and the docs say "Leave the variable unset on a Mac someone is using" ([operate](https://cua.ai/docs/cua-driver/guides/operate#allow-a-brief-foreground-step-macos)).
- "Off-Space SwiftUI windows lose their tree."
- "Minimized windows drop keyboard commits."
- "Chromium turns pixel right-clicks into left-clicks."
- Pixel input to a `desktop` target is foreground-only.
- On Wayland, raw background keys refuse ([platform support](https://cua.ai/docs/cua-driver/concepts/platform-support)).

**Validation.** Each supported behavior is a cell in a Rust catalog. A background cell passes only when "focus, z-order, the real cursor, and the foreground app stayed untouched" (vendor claim; we did not reproduce it).

[INFERENCE] Background operation on macOS rests on undocumented SPI that may change in any macOS release. Cua's docs never mention macOS 27 (0 hits in the full docs), and Memoshi's floor is macOS 27 ([D31](../plan/decisions.md#d31)).

### 5.2 Isolating the user's mouse and keyboard

**The driver's promise.** Background delivery "does not raise the window, move the real pointer, or switch the frontmost app. The agent gets its own cursor overlay." Desktop screenshots leave out that overlay: on macOS 14+ through a ScreenCaptureKit filter, and on Windows through `WDA_EXCLUDEFROMCAPTURE` ([platform support](https://cua.ai/docs/cua-driver/concepts/platform-support#desktop-captures-leave-out-the-agent-cursor)).

**What is still shared.** "All sessions still share one screen, keyboard, and focus, and native input is admitted one action at a time" ([processes and sessions](https://cua.ai/docs/cua-driver/concepts/how-cua-driver-works#processes-and-sessions)). macOS key events are scoped to a process, not a window. Cua's design plan therefore requires the driver to refuse a background keystroke unless the target element provably belongs to the requested window, after finding that a keystroke could otherwise reach "a sibling window" ([plan](https://github.com/trycua/cua/blob/main/libs/cua-driver/docs/macos-background-input-v1-plan.md)).

**The VM alternative.** A Space can be "a fresh computer inside this Mac, away from your files and your mouse" ([quickstart](https://cua.ai/docs/spaces/quickstart)). That is the isolation model Memoshi's Bot computer already uses ([06 §1](../plan/06-computers-and-browsers.md)).

**Cua's change of stance.** In April 2026 Cua said it had been "recommending isolated VMs and GUI containers" and "never evangelized our users to install the computer-server… directly on one's own desktop host" ([blog](https://cua.ai/blog/inside-macos-window-internals)). In October 2026 the Spaces quickstart makes "This Mac… your first Space", after two grants: "Let Cua control this Mac" and "Let Cua see this screen" ([quickstart](https://cua.ai/docs/spaces/quickstart)).

### 5.3 Accessibility vs pixels

- **Both, every time.** `get_window_state(pid, window_id)` returns the accessibility tree and a screenshot in one call. "The tree says what is actionable… the screenshot says which one, and shows what the tree omits or gets wrong" ([how it works](https://cua.ai/docs/cua-driver/concepts/how-cua-driver-works#observe-tree-and-pixels-together)).
- **Leaner default since 0.35.** A read returns a compact `tree_markdown` and walks at most 250 nodes. Element tokens belong to one snapshot, and a stale token is refused ([operate](https://cua.ai/docs/cua-driver/guides/operate#before-updating-to-035)).
- **Permissions.** Without Screen Recording, a read returns "the tree only (no PNG)". Accessibility is needed for every tree read and every input ([troubleshoot](https://cua.ai/docs/cua-driver/guides/troubleshoot)).
- **Verification is accessibility-only.** Results carry `effect` (`confirmed`, `unverifiable`, `suspected_noop`, `partial`, `refused`), `escalation` and `verified`. "A delivered event is not an applied change": Electron, Catalyst and web content can echo a write they did not apply.
- **Surfaces with no tree** use the optional, AGPL perception extension. Each region is bound to its screenshot's `capture_id`, which expires after 60 s and cannot be reused. Parsing takes "about 2 to 2.5 seconds on macOS" per screenshot on the CPU (vendor-measured).
- **Linux**, which is what a Memoshi Bot computer would use, works through AT-SPI 2 over D-Bus for the tree and X11/XTest for input. It is "Supported with toolkit limits" ([platform support](https://cua.ai/docs/cua-driver/concepts/platform-support)). The summary of the 2026-06-18 Linux post on the [blog index](https://cua.ai/blog) says the same.

### 5.4 Takeover and multiplayer

**Spaces.**
- A viewer gets presence with "their own named cursor" and a view-only stream. An editor also gets "Pointer and keyboard input… as a human", plus shell, files, clipboard and MCP. `cua-spacesd` enforces the role ([share](https://cua.ai/docs/spaces/guides/share-a-space)).
- A media session takes an input policy: `view_only` (the default), `background_only` or `allow_activation` ([stream](https://cua.ai/docs/spaces/guides/stream-a-desktop)).
- Sharing asks for Touch ID or a password. Removing someone "cuts their open streams at once".

**Cua Bots.** "The bot has control until you take over; its face rides next to its pointer." A bot asks for sign-ins, and you either pick a saved Keyvault sign-in or "take over its computer and type it yourself." On the iPhone the computer "opens in your control" through `SpacesdClient.click` and `typeText` ([Cua Bots](https://cua.ai/docs/spaces/examples/cua-bots), [iOS README](https://github.com/trycua/cua/blob/main/examples/cua-bots-ios/README.md)).

**What is missing.** We found no hard lock that holds the agent's actions while a human acts on a shared Space. Cursors are presence, and the driver serializes native input. [INFERENCE] Memoshi's [D19](../plan/decisions.md#d19) design is stricter: `control: bot|user`, the next bot call is held, and Hand back comes with a change summary ([06 §9](../plan/06-computers-and-browsers.md)).

**Keyboard capture in the Spaces macOS app.** Clicking the stream gives it the keyboard; Control+Option gives it back; and "Shortcuts macOS reserves (⌘Tab, ⌘Space…) stay on the Mac: capturing them would need an event tap and the Accessibility permission" ([app README](https://github.com/trycua/cua/blob/main/apps/cua-spaces-macos/README.md)). For a Memoshi `VZVirtualMachineView`, the public [`capturesSystemKeys`](https://developer.apple.com/documentation/virtualization/vzvirtualmachineview/capturessystemkeys) property (macOS 12+) "determines whether the system should send certain system keyboard shortcuts to the guest" and needs no Accessibility grant [INFERENCE: we read the API docs only].

### 5.5 Host and VM requirements

| Use | Requirement | Source |
|---|---|---|
| Spaces app | macOS 26+; Windows preview (x64 or Arm); Ubuntu 24.04 `.deb` (an AppImage is "not a supported one") | [install](https://cua.ai/docs/spaces/guides/install) |
| macOS Space | Apple silicon, "about 50 GB" of disk, at most two macOS VMs per Mac ("Apple allows two macOS VMs at a time on one Mac"), and the Local Network permission for the VM connection | [troubleshoot](https://cua.ai/docs/spaces/guides/troubleshoot); Apple's SLA is cited in [execution environments §2.2](agentic-workspace-landscape/landscape/execution-environments.md#22-desktop-capable-vms-for-computer-use) |
| Linux Space | A container engine (Docker, Colima or Podman; gVisor when installed) or QEMU, which needs read and write access to `/dev/kvm` | [install](https://cua.ai/docs/spaces/guides/install), [runtimes](https://cua.ai/docs/cua-sdk/guides/local-runtimes) |
| Host a "spare Mac" | A LaunchAgent in the GUI session; "The mini needs an active GUI login session"; turn on auto-login for a headless mini; grant `cua-spacesd` Screen Recording and Accessibility, and grant Cua Driver its own; default limits of 4 Spaces and 2 macOS VMs | [add a computer](https://cua.ai/docs/spaces/guides/add-a-computer) |
| Lume | Apple silicon; macOS 13+ per the docs, 14+ per `Package.swift`; 8 GB free RAM (16 GB for an 8 GB guest); 50 GB per guest | [Lume](https://cua.ai/docs/lume) |
| Cua Driver | macOS 14+; Windows with a user signed in at the desktop (not Session 0); a Linux x86_64 desktop (arm64 binaries exist, see §2.1) | [overview](https://cua.ai/docs/cua-driver), [VMs and remote](https://cua.ai/docs/cua-driver/guides/vms-and-remote) |
| Your own cloud | AWS, GCP or Modal credentials plus a cua.ai sign-in. Each sandbox joins the relay as a machine of your account | [your own cloud](https://cua.ai/docs/cua-sdk/guides/local-runtimes#your-own-cloud) |

### 5.6 Mac and iOS restrictions

**macOS: TCC permissions follow the app's identity.**
- Grants belong to `CuaDriver.app` (`com.trycua.driver`), "not to whatever terminal spawned a `cua-driver` process" ([how it works](https://cua.ai/docs/cua-driver/concepts/how-cua-driver-works#processes-and-sessions)).
- An embedding app can own the grants itself. But "a gateway, terminal, `open`, or `NSWorkspace` launch changes the TCC responsibility chain and cannot lend the app's grants" ([use the SDK](https://cua.ai/docs/cua-driver/guides/use-the-sdk#expose-mcp-from-a-desktop-app)).
- After a bundle ID or signature change, stale grants have to be reset with a scoped `tccutil` call ([troubleshoot](https://cua.ai/docs/cua-driver/guides/troubleshoot#reset-stale-macos-permissions)).
- macOS Tahoe adds "Tahoe's separate direct screen capture" prompt ([VMs and remote](https://cua.ai/docs/cua-driver/guides/vms-and-remote)).

**macOS: private SPI.** The Driver uses SkyLight and private AX symbols (§5.1), and Lume uses `_VZVNCServer`. App Review guideline 2.5.1 reads: "Apps may only use public APIs and must run on the currently shipping OS" ([guidelines](https://developer.apple.com/app-store/review/guidelines/)). Memoshi ships outside the Mac App Store ([D32](../plan/decisions.md#d32)), so this is not a distribution blocker. It is a fragility risk [INFERENCE].

**macOS: compatibility.** None of Cua's docs mentions macOS 27, so compatibility with Memoshi's floor is unknown.

**iOS.**
- No component drives iOS: Cua Driver supports macOS, Windows and Linux only.
- The Cua Bots iPhone app "is a remote client". It reaches a bot's Space through the relay or directly through `cua-spacesd`.
- Its README lists the gaps: "a phone off the Mac's network can't reach it yet"; push works only "while the app is open"; Keyvault approvals happen on the Mac ("a Cua-signed app with Touch ID"); and "The cua SDK's iOS XCFramework slices are not exercised in CI" ([iOS README](https://github.com/trycua/cua/blob/main/examples/cua-bots-ios/README.md)).
- The Swift `Cua` package declares iOS 15+, but no binary is released.

### 5.7 Privacy and security

**Telemetry is on by default and goes to PostHog EU.**
- The SDK, CLI, daemon, `cua-spacesd` and the app count only fixed event names (vendor claim). The data is linked to your account when you are signed in ([telemetry](https://cua.ai/docs/cua-sdk/concepts/telemetry)). The Spaces 0.11.0 notes contradict that: account linking "stays off until our policy is published" ([release](https://github.com/trycua/cua/releases/tag/cua-spaces-v0.11.0)).
- Cua Driver and Lume send "content-free, pseudonymous" events, also on by default ([operate](https://cua.ai/docs/cua-driver/guides/operate#telemetry), [Lume](https://cua.ai/docs/lume/concepts/how-lume-works#telemetry)).
- Switches: `DO_NOT_TRACK=1`, `CUA_TELEMETRY=0`, `CUA_DRIVER_RS_TELEMETRY_ENABLED=false` and `LUME_TELEMETRY_ENABLED`. Update checks are separate requests.

**The relay can read sessions.** "`relay.cua.ai` is a trusted, TLS-terminating proxy, not a blind relay… It can read the plaintext of anything it proxies while the request is in flight: shell output, file contents, the desktop media stream, keystrokes and clipboard data", plus Keyvault passwords and teleport bundles unless they are sealed. "A compromised relay process… is equivalent to a compromised session for every computer currently routed through it" ([relay security](https://cua.ai/docs/spaces/guides/relay-security)).
- Teleport bundles are sealed to a guest key that is pinned on first use, but only for images built after that shipped.
- A Keyvault site-login password still crosses the relay unsealed when the user acknowledges the risk.
- End-to-end encryption through the mesh is beta and off by default.

**Credentials.**
- On the Spaces daemon path, "The daemon copies your agent's credential file (for example `~/.claude/.credentials.json`) into the Space at start", unless `CUA_SPACES_AGENT_CREDENTIALS_HOME=none` is set ([connect your agent](https://cua.ai/docs/spaces/guides/connect-your-agent#run-an-agent-inside-a-space)).
- The SDK's own sandbox-agent page says "Nothing is copied from your machine's agent config" ([run a coding agent](https://cua.ai/docs/cua-sdk/guides/run-a-coding-agent)). The two statements appear to describe different entry points. Confirm before relying on either.
- Provider keys live in one login-Keychain item that "trusts the Cua apps of this Mac". Agents cannot read them through MCP (vendor claim).

**Agent authority and permissions.**
- "`space_bash`, `send_file`, `teleport_app` and `hotspot_start` act with your authority". A `spaces:readonly` permission exists.
- `hotspot_start` shares "this computer's network with a Space" ([connect your agent](https://cua.ai/docs/spaces/guides/connect-your-agent#limit-what-an-agent-can-do), [llms-full](https://cua.ai/docs/llms-full.txt)).
- Cua Driver modes:
  - `standard` (the default) lets observation, input, isolated browsers and recording run "without prompts".
  - `bounded` requires a capability manifest that denies everything not listed.
  - `unrestricted` has "No protection against prompt injection".
- Policies "do not filter responses, rate-limit, or authenticate callers, and code running inside the runtime's process can bypass them". "Same-user code and malware on the same desktop are outside this boundary" ([permissions](https://cua.ai/docs/cua-driver/guides/permissions)).
- Attaching to a logged-in Chrome profile is an explicit grant, because "loopback is not authentication" ([browsers](https://cua.ai/docs/cua-driver/guides/browsers#attach-to-a-logged-in-profile)).
- `run_script`, sandboxed JavaScript that drives the tools, is on by default from 0.35.

**Advisories published 2026-10-19 and 2026-10-20** ([GitHub](https://github.com/trycua/cua/security/advisories)):
- [GHSA-5cjh-q5qq-72f7](https://github.com/trycua/cua/security/advisories/GHSA-5cjh-q5qq-72f7), medium. In cua-spaces up to 0.10.0, `teleport_app` ignored the caller's item selection, so "an approved request delivers the app's whole stored session". A Firefox-preferences-only request delivered session cookies. Fixed in 0.11.0.
- [GHSA-gj99-rv7m-vm79](https://github.com/trycua/cua/security/advisories/GHSA-gj99-rv7m-vm79), high. The approval server of the deprecated `cua-agent` was unauthenticated, so a peer could "forge the human decision".
- [GHSA-8jjf-g53q-cr56](https://github.com/trycua/cua/security/advisories/GHSA-8jjf-g53q-cr56), high. The `cua-agent` playground leaked LLM API keys through reflected CORS.
- [GHSA-f42q-9h29-hw57](https://github.com/trycua/cua/security/advisories/GHSA-f42q-9h29-hw57), low. On Windows in bounded mode, a `bundle_id` grant matched any program with the same file name. Fixed in Driver 0.37.0.

**Patterns Memoshi should not copy** (each is a documented fact; the conclusion is [INFERENCE]):
- Cua Bots "Rules are instructions to the bot, not enforcement: agent runs approve their own tool calls inside the bot's Space" ([Cua Bots](https://cua.ai/docs/spaces/examples/cua-bots#limits)).
- The Hermes plugin skips "dangerous-command prompts" in a disposable Space ([catalog](https://github.com/NousResearch/hermes-agent/blob/main/plugin-catalog/cua-spaces.yaml)).
- Lume's installer starts an HTTP API on `localhost:7777` at login with no documented authentication: "Keep it there unless you have… a plan for authentication" ([manage VMs](https://cua.ai/docs/lume/guides/manage-vms)).
- After an update, the Spaces app refreshes the "Cua MCP entries in Claude Code, Cursor and the other agents… without any window" ([install](https://cua.ai/docs/spaces/guides/install#after-an-update)).
- A headless host Mac needs auto-login ([add a computer](https://cua.ai/docs/spaces/guides/add-a-computer)).
- The @injaneity onboarding asks a cloud bot to install infrastructure with `curl | sh` and grant itself KVM access ([docs](https://cua.ai/docs/spaces/guides/use-grok-bot-dots-and-pi-with-spaces)). It does this on a Grok Bot computer, where cookies and CLI credentials are shared across all of a user's bots ([profile](agentic-workspace-landscape/projects/grok-bot.md)).

## 6. Reuse map for a SwiftUI/AppKit app on Pi Durable

Memoshi's seams, for reference:
- Pi tool → policy hooks → `RemoteExecutionEnv` → the pi-env daemon, which runs under Seatbelt, in the VM over SSH on vsock, or on a remote host ([06 §1](../plan/06-computers-and-browsers.md)).
- Pi Durable's `HarnessOptions.env` rebuilds the environment on each use.
- Bot computers are Debian 13 arm64 VMs with Xorg and Xfce on Virtualization.framework ([D17](../plan/decisions.md#d17)).
- GUI computer use runs inside Bot computers only, in v1.1 ([R11-12](../plan/feature-catalog.md)).
- Host computer use is EXPL-02, which needs a new decision ([D41](../plan/decisions.md#d41)).

### 6.1 Reusable (MIT, attribution required)

| # | Candidate | License | What to reuse | Where it fits | Gate and caveats |
|---|---|---|---|---|---|
| 1 | **Cua Driver inside the Linux Bot computer** | MIT | The `cua-driver` binary as the GUI action layer behind Memoshi's own `computer_click`, `computer_type` and similar tools. Call it as `cua-driver call …` through pi-env exec, or as `cua-driver mcp` over the existing SSH channel. Cua documents MCP over SSH for VMs ([VMs and remote](https://cua.ai/docs/cua-driver/guides/vms-and-remote)) | v1.1 R11-12. It runs in the guest, so the host gets no TCC prompts. [INFERENCE] This fits D41 | Spike first. Linux arm64 assets exist, but the docs name x86_64 only. Debian 13 and arm64 have no published coverage. Every release is flagged pre-release. Pin by SHA-256 and verify the Sigstore bundles. Use `bounded` mode with a per-task manifest. Turn off telemetry and update checks, which must fail closed through the gateway anyway. Disable `run_script`. Keep web automation on Memoshi's Chromium-over-CDP path ([D18](../plan/decisions.md#d18)) |
| 2 | **Driver contracts and vocabulary** | MIT (docs and code) | The `effect`, `verified` and `escalation` result fields; refusal codes; "refuse instead of guessing"; element tokens bound to one snapshot; `ActionInterrupted` with `NotStarted`/`Completed`/`Unknown` ("never replay `Unknown` blindly"); a deny-by-default capability manifest with `expires_after` and `idle_timeout`; content-free activity events ([use the SDK](https://cua.ai/docs/cua-driver/guides/use-the-sdk), [permissions](https://cua.ai/docs/cua-driver/guides/permissions)) | Memoshi's computer tool API and its crash-replay rules (`replay: "unsafe"` and `outcome_uncertain`, [06 §8.4](../plan/06-computers-and-browsers.md)) | Ideas, or code copied with attribution. No dependency needed |
| 3 | **Embedded-host pattern for the user's own Mac** | MIT ([ExampleAgentHarness.swift](https://github.com/trycua/cua/blob/main/libs/cua-driver/rust/examples/embedded-host-macos/ExampleAgentHarness.swift)) | The host app requests Accessibility and Screen Recording *as itself*, starts `cua-driver serve --embedded` as a direct child with `CUA_DRIVER_EMBEDDED=1` and `CUA_DRIVER_HOST_BUNDLE_ID`, attaches `cua-driver mcp --embedded` over stdio, and checks `health_report` (`bundle_identity`) and `check_permissions` (`attribution: host`) | **EXPL-02 only.** It needs a new decision that changes D41 | It puts both TCC grants on Memoshi.app itself, which is a large trust ask. It relies on private SPI and on Cua's release cadence. A Swift app talks to it over MCP JSON-RPC, because there is no Swift binding. [INFERENCE] The nested binary must be signed with Memoshi's Developer ID and pass notarization |
| 4 | **`cua.env.v1` and `cua.daemon.v1` protobuf contract** | MIT (`cua-proto`) | A reference API shape for a guest agent: `ComputerService`, `AccessibilityService`, `WindowsService` and `StreamService` tickets ([protocol](https://cua.ai/docs/cua-sdk/reference/protocol)) | Only if Memoshi ever needs a guest agent beyond pi-env | The server that implements it, `cua-spacesd`, is FSL |
| 5 | **pi-cua** | MIT ([repo](https://github.com/injaneity/pi-cua), v0.1.0, 27 stars, created 2026-08-18) | Patterns for running Pi on another computer: route only the six workspace tools (`read`, `write`, `edit`, `bash`, `find`, `grep`) plus pi's `!` shell; move only missing Git objects and verify the tree; on resume, refuse to substitute a different machine; block a replaced tool while remote; ask before destructive tools | Remote machines and their return path | It targets `@earendil-works/pi-coding-agent` extensions (dev dependency 1.3.0), not Pi Durable, and depends on `@trycua/cua`. Memoshi already routes through pi-env `RemoteExecutionEnv`, so take only the ideas |
| 6 | **OpenKoalaBots TypeScript sample** | MIT per `package.json` | A Node server that orchestrates bots over Spaces with `@trycua/cua` ([sample](https://github.com/trycua/cua/tree/main/examples/openkoalabot-example-ts)) | Reading material for memoshid adapters | Its README is stale: it says `@trycua/cua` is "not published on npm yet", but 0.5.0 is. Never copy `openkoalabots-assets` |
| 7 | **hermes-cua-spaces** | MIT ([repo](https://github.com/trycua/hermes-cua-spaces)) | How a terminal backend maps to a Space | A possible v2 adapter | Do not copy its prompt-skipping |
| 8 | **cua-mesh** | MIT client | A WireGuard userspace mesh through boringtun: no TUN, no root, direct when possible, relay-forwarded ciphertext otherwise ([relay security](https://cua.ai/docs/spaces/guides/relay-security#end-to-end-encrypted-connections-beta)) | Design input for the v1.1 end-to-end encrypted relay (R11-03) | Beta. Written in Rust. The coordinator and host sides are FSL |
| 9 | **Lume** | MIT | A reference for macOS guests: unattended setup by writing files to the Data volume, SIP changes through paired Recovery, transactional disk growth ([how Lume works](https://cua.ai/docs/lume/concepts/how-lume-works)) | Only if macOS-guest Bot computers ever enter the plan. They are not in it ([D17](../plan/decisions.md#d17)) | Avoid the `_VZVNCServer` private SPI. Do not copy the unauthenticated localhost API. Memoshi's live view is `VZVirtualMachineView` |

### 6.2 Not reusable

| Item | Why |
|---|---|
| Cua Spaces apps; `cua-spacesd`; Keyvault; teleport; Cua Volume; the media stack; `CuaSpacesFFI`, `CuaSpacesStreaming` and `CuaSpacesTeleport`; notch views; Cua Bots macOS and iOS (including the plain-Swift `CuaBotsCore`, because the license covers the whole directory); Infinite Canvas; OpenKoalaBots Swift and Tauri; Cua Driver Bench; `cua-chromium-storage` | FSL-1.1-MIT. Ideas only under D33, with Competing Use risk (§4) |
| `cua-perception` and `cua-som` | AGPL |
| Keyvault trust | Bound to Cua's signature. Approving saved sign-ins "takes a Cua-signed app" ([Cua Bots limits](https://cua.ai/docs/spaces/examples/cua-bots#limits)), and the Keychain item "trusts the Cua apps of this Mac" |
| The Cua relay as Memoshi's relay | Cua's hosted service. It is plaintext-capable, and its relay code is FSL |

## 7. Product and demo inspiration (ideas only, no code or assets)

- **Cua Bots on Mac and iPhone** ([docs](https://cua.ai/docs/spaces/examples/cua-bots)):
  - Create a bot in three steps: name, face (color, eyes, ears), and where it runs plus which agent drives it.
  - The face changes with state: thinking, working, waiting, done, paused.
  - "Ada's computer" shows live beside the chat, framed in the bot's color, with picture in picture, and the bot's face rides next to its pointer.
  - Approval cards cover buying, deleting and contacting anyone, and you can answer them from the phone.
  - Custom rules take the form "When Ada wants to … Ada should …", with four choices: without asking, when you say so, ask first, or hand off to you. Rules about passwords and money cannot be changed.
  - A Scheduled page lists every bot's routines, and the profile menu has Pause, Resume and Reset.
  - These map onto Memoshi's roster, approvals, routines and takeover. Memoshi's differentiator is that its rules are enforced by policy outside the model ([D9](../plan/decisions.md#d9)), while Cua's are prompts.
- **Spaces Mac app** ([README](https://github.com/trycua/cua/blob/main/apps/cua-spaces-macos/README.md)):
  - A notch panel with live tiles of each Space.
  - Drag a window or app onto a Space to teleport it.
  - Named presence cursors, one per person and agent.
  - Clear keyboard-capture rules for the stream.
  - One shared core behind two shells, with parity tests.
- **Honest security pages.** "What the relay can see" is a template for Memoshi's v1.1 relay disclosure ([relay security](https://cua.ai/docs/spaces/guides/relay-security)).
- **Consent design for teleport and the Keyvault** ([teleport](https://cua.ai/docs/spaces/guides/teleport-an-app), [Keyvault](https://cua.ai/docs/spaces/guides/keyvault)):
  - Each site is listed with counts.
  - An identity provider "is never picked for you".
  - Sensitive opt-ins start off.
  - Touch ID is required before secrets are read.
  - A site login types into the page only on the saved login's exact origin, and "One approval covers one sign-in". This matches Memoshi's sign-in cards ([D18](../plan/decisions.md#d18)).
  - The advisory GHSA-5cjh shows why an approval must bind the exact payload.
- **Persistent agents** ([docs](https://cua.ai/docs/spaces/guides/persistent-agents)):
  - Each agent has a memory home with a single-writer lease.
  - Files that look like secrets are kept out of memory, and the user is notified.
  - The daemon fires routines "whether or not an app is open".
  - Pause suspends a local Space.
- **Driver demo craft** ([operate](https://cua.ai/docs/cua-driver/guides/operate)):
  - The agent cursor has six motion styles.
  - Trajectory recordings render with zoom.
  - Computer History is an encrypted, metadata-only log of actions ("never stores screenshots, typed text, keystrokes…").
- **The "spare Mac" host pattern.** It is analogous to Memoshi's Mac mini runner (R11-07), with the same caveats: a GUI login session is required, auto-login on a headless host, and TCC grants on the host daemon ([add a computer](https://cua.ai/docs/spaces/guides/add-a-computer#use-a-spare-mac-to-host-spaces)).

## 8. Recommendations

These are inputs for the parent synthesis and for change control. They do not alter any binding decision.

1. **Keep [D41](../plan/decisions.md#d41) as written.**
   - Host computer use through Cua Driver needs the two TCC grants D41 excludes, plus private SPI with no stated macOS 27 support. It would also share the user's keyboard, screen and focus (§5.2).
   - If EXPL-02 is ever opened, prototype the MIT embedded-host pattern (§6.1 row 3) behind a developer flag.
   - Required prerequisites:
     - a new decision;
     - `bounded` mode with Memoshi-generated manifests;
     - every action routed through Memoshi's tiers;
     - telemetry and update checks off;
     - the binary pinned and signed by Memoshi;
     - a kill switch;
     - a test matrix on each macOS beta.
2. **For R11-12 (v1.1), spike Cua Driver inside the Bot computer before writing our own X11 action layer.** The plan already picked X11 and Xfce for "XTest and screen capture" ([06 §4](../plan/06-computers-and-browsers.md)). Pass criteria to add to the v1.1 spike:
   - linux-arm64 runs on Debian 13 under Virtualization.framework;
   - accessibility-tree quality for GTK and Xfce apps;
   - background delivery to occluded windows;
   - effect verification rate;
   - no egress except through the gateway;
   - telemetry, update checks and `run_script` disabled.

   Fallback: Memoshi's own XTest plus AT-SPI tools, guided by the Driver's MIT contract (§6.1 row 2).
3. **Adopt the Driver's result and permission vocabulary in the `computer_*` tool API now.** This is cheap and license-clean, and it aligns with the `outcome_uncertain` replay rules.
4. **Never link, bundle or copy FSL Cua code, and never ship `cua-spacesd` in Memoshi images** (§4). Do not route Memoshi traffic through `relay.cua.ai`.
5. **Keep Cua off the v1 critical path.** At most, consider an optional "Cua Spaces" computer adapter in v2 for users who already run Cua, behind the same computer seam as E2B ([D39](../plan/decisions.md#d39)). Conditions:
   - Use only the MIT client (`@trycua/cua` in memoshid).
   - Give it the trust class of a Remote machine, with no Memoshi gateway, and require `CUA_MESH=require` for relay paths.
   - Spike whether pi-env can run inside a Space over a `Connection` command [INFERENCE: untested].
   - Turn off credential copying (`CUA_SPACES_AGENT_CREDENTIALS_HOME=none`).
6. **For Pi, read pi-cua for patterns, not code paths** (§6.1 row 5). Memoshi already has the better seam: pi-env with `RemoteExecutionEnv`.
7. **Corrections for [execution-environments.md](agentic-workspace-landscape/landscape/execution-environments.md) row 15 and §2.2**, for the parent to integrate:
   - SDK languages: Python and TypeScript are published (0.5.0); Rust is git-tag only; Swift and Kotlin are unreleased.
   - Local runtime: "gVisor when installed, else runc" on Docker or Podman, plus QEMU and Lume.
   - Licenses: add FSL for `cua-spacesd`, the Swift Spaces libraries, the samples and Driver Bench, and AGPL for perception.
   - Cloud locations: E2B and Daytona need a contrib build and are not measured. Azure is absent from the docs.
   - Plans: add yearly prices and session and hour limits.
   - The relay is a plaintext-capable hosted dependency.
   - Stars were 30,420 at 20:15 UTC.
   - The 18 October date stands, with the 16 October commit caveat.
8. **No performance claims.** Treat "within 3 minutes", "ten lines", perception timings and every Cua-Bench figure as vendor claims. Memoshi's S2 and S3 spikes measure on our reference hardware ([phase 0](../plan/phase-0.md)).

## 9. Open questions

1. Does Cua Driver's linux-arm64 build work on Debian 13 arm64 with Xorg, Xfce and AT-SPI under Virtualization.framework? Answer in the v1.1 spike; Cua publishes no coverage for it.
2. Does a Grok Bot or Dots computer expose `/dev/kvm` and sudo, as the @injaneity prompt assumes? Unknown. Without KVM, QEMU falls back to TCG emulation ([runtimes](https://cua.ai/docs/cua-sdk/guides/local-runtimes)).
3. Which agent-credential rule applies to `agent_start` in Spaces, and to persistent agents, when the two docs pages disagree (§5.7)? A source read of `cua-agents` or a doc fix would settle it.
4. Did Cua Cloud stop serving on 16 or 18 October? The docs say 18; one commit says 16. Only Cua or an old client run could say.
5. Will SkyLight-based background input survive macOS 27 and 28? Cua states no macOS 27 support.
6. When will Cua Driver publish a release that is not flagged pre-release, and when will the Swift `Cua` package ship a binary?

## Method and limits

- **Reading Cua's docs.** We read pages through their `.md` variants, and searched the full-text [llms-full.txt](https://cua.ai/docs/llms-full.txt), downloaded once, about 2.5 MB.
- **Reading GitHub.** We used the GitHub API to read repository metadata, releases (791 listed), commits, security advisories and the LICENSE file tree, and read raw files directly. We read only Cua and Hermes material (plus the pi-cua repo), never Kuvo Code source.
- **Package registries.** We read the npm and PyPI registry JSON for publication dates.
- **X posts.** We used three methods (§1). We extracted 6-frame previews from three of the five launch videos; the downloads were temporary and have been deleted.
- **Context7.** We tried it for an API cross-check, and it failed ("Monthly quota exceeded"). Cua's own docs were the primary source anyway.
- **What we did not do.** We installed nothing, ran no Cua tool, created no account and contacted no Cua service. Anything about runtime behavior is therefore documentation or a vendor claim, not hands-on validation.

## Sources

**Social:**
1. https://x.com/trycua/status/2112228154651881479, with thread posts https://x.com/trycua/status/2112228156958822650, https://x.com/trycua/status/2112228158699434443, https://x.com/trycua/status/2112228160351952950 and https://x.com/trycua/status/2112228161941631230
2. https://x.com/injaneity/status/2112271256972386799
3. https://x.com/trycua/status/2112589741879328979
4. https://publish.twitter.com/oembed?url=https://twitter.com/x/status/2112228154651881479 and https://publish.twitter.com/oembed?url=https://twitter.com/x/status/2112271256972386799
5. https://api.fxtwitter.com/status/2112228154651881479 and https://api.fxtwitter.com/status/2112271256972386799 (third-party mirror)

**Cua docs and site:**

6. https://cua.ai/docs/llms.txt and https://cua.ai/docs/llms-full.txt
7. https://cua.ai/docs/spaces/guides/connect-your-agent
8. https://cua.ai/docs/spaces/guides/use-grok-bot-dots-and-pi-with-spaces
9. https://cua.ai/docs/spaces/examples/cua-bots
10. https://cua.ai/docs/spaces/concepts/how-spaces-works
11. https://cua.ai/docs/spaces/guides/relay-security
12. https://cua.ai/docs/spaces/guides/install
13. https://cua.ai/docs/spaces/guides/troubleshoot
14. https://cua.ai/docs/spaces/guides/teams
15. https://cua.ai/docs/spaces/quickstart
16. https://cua.ai/docs/spaces/guides/add-a-space
17. https://cua.ai/docs/spaces/guides/add-a-computer
18. https://cua.ai/docs/spaces/guides/share-a-space
19. https://cua.ai/docs/spaces/guides/stream-a-desktop
20. https://cua.ai/docs/spaces/guides/teleport-an-app
21. https://cua.ai/docs/spaces/guides/keyvault
22. https://cua.ai/docs/spaces/guides/persistent-agents
23. https://cua.ai/pricing
24. https://cua.ai/docs/cua-sdk/guides/cua-cloud-ended
25. https://cua.ai/docs/cua-sdk/guides/local-runtimes
26. https://cua.ai/docs/cua-sdk/concepts/how-sandboxes-work
27. https://cua.ai/docs/cua-sdk/guides/own-harness
28. https://cua.ai/docs/cua-sdk/guides/run-a-coding-agent
29. https://cua.ai/docs/cua-sdk/concepts/telemetry
30. https://cua.ai/docs/cua-sdk/reference/protocol
31. https://cua.ai/docs/cua-driver
32. https://cua.ai/docs/cua-driver/concepts/how-cua-driver-works
33. https://cua.ai/docs/cua-driver/concepts/platform-support
34. https://cua.ai/docs/cua-driver/guides/use-the-sdk
35. https://cua.ai/docs/cua-driver/guides/permissions
36. https://cua.ai/docs/cua-driver/guides/operate
37. https://cua.ai/docs/cua-driver/guides/vms-and-remote
38. https://cua.ai/docs/cua-driver/guides/troubleshoot
39. https://cua.ai/docs/cua-driver/guides/browsers
40. https://cua.ai/docs/cua-driver/guides/connect-your-agent
41. https://cua.ai/docs/lume
42. https://cua.ai/docs/lume/concepts/how-lume-works
43. https://cua.ai/docs/lume/guides/manage-vms
44. https://cua.ai/blog/inside-macos-window-internals
45. https://cua.ai/blog (index; the summary of the 2026-06-18 Linux post)

**GitHub, Cua:**

46. https://github.com/trycua/cua and https://raw.githubusercontent.com/trycua/cua/main/README.md
47. https://github.com/trycua/cua/blob/main/legal/LICENSING.md
48. https://github.com/trycua/cua/blob/main/legal/COMMERCIAL.md
49. https://github.com/trycua/cua/blob/main/examples/cua-bots-macos/LICENSE
50. https://github.com/trycua/cua/blob/main/samples/cua-bots-macos/README.md
51. https://github.com/trycua/cua/blob/main/examples/cua-bots-ios/README.md
52. https://github.com/trycua/cua/blob/main/libs/cua/swift/README.md and https://github.com/trycua/cua/blob/main/libs/cua/swift/Package.swift
53. https://github.com/trycua/cua/blob/main/libs/spaces-sdk-swift/README.md
54. https://github.com/trycua/cua/blob/main/apps/cua-spaces-macos/README.md
55. https://github.com/trycua/cua/blob/main/libs/cua-driver/rust/examples/embedded-host-macos/ExampleAgentHarness.swift
56. https://github.com/trycua/cua/blob/main/libs/cua-driver/docs/macos-background-input-v1-plan.md
57. https://github.com/trycua/cua/blob/main/libs/cua-driver/rust/Cargo.toml and https://github.com/trycua/cua/blob/main/libs/cua-driver/rust/THIRD_PARTY_NOTICES.md
58. https://github.com/trycua/cua/blob/main/libs/lume/src/VNC/VNCService.swift and https://github.com/trycua/cua/blob/main/libs/lume/Package.swift
59. https://github.com/trycua/cua/blob/main/libs/cua/crates/cua-mesh/Cargo.toml
60. https://github.com/trycua/cua/blob/main/libs/cua/crates/cua-media-protocol/LICENSE and https://github.com/trycua/cua/blob/main/libs/cua/crates/cua-chromium-storage/LICENSE
61. https://github.com/trycua/cua/blob/main/examples/openkoalabot-example-ts/package.json
62. https://github.com/trycua/cua/blob/main/libs/cuabot/README.md
63. https://github.com/trycua/cua/blob/main/libs/cua/CHANGELOG.md
64. Releases: https://github.com/trycua/cua/releases/tag/cua-spaces-v0.11.0, https://github.com/trycua/cua/releases/tag/cua-driver-rs-v0.37.0, https://github.com/trycua/cua/releases/tag/cua-sdk-v0.5.0, https://github.com/trycua/cua/releases/tag/lume-v0.6.1 and https://github.com/trycua/cua/releases/tag/cua-spacesd-v0.5.3
65. Commits: https://github.com/trycua/cua/commit/c4ec0dd9, https://github.com/trycua/cua/commit/5d78ec8b7705d942a3d260b276bcce76614a634c, https://github.com/trycua/cua/commit/c6540d2c, https://github.com/trycua/cua/commit/348c47cc and https://github.com/trycua/cua/commit/da94f399a28f
66. Advisories: https://github.com/trycua/cua/security/advisories/GHSA-5cjh-q5qq-72f7, https://github.com/trycua/cua/security/advisories/GHSA-gj99-rv7m-vm79, https://github.com/trycua/cua/security/advisories/GHSA-8jjf-g53q-cr56 and https://github.com/trycua/cua/security/advisories/GHSA-f42q-9h29-hw57

**GitHub, other:**

67. https://github.com/injaneity/pi-cua (README and package.json)
68. https://github.com/trycua/hermes-cua-spaces
69. https://github.com/NousResearch/hermes-agent/blob/main/plugin-catalog/cua-spaces.yaml

**Registries:**

70. https://registry.npmjs.org/@trycua/cua, https://registry.npmjs.org/@trycua/cua-driver, https://pypi.org/pypi/cua/json, https://pypi.org/pypi/cua-driver/json and https://pypi.org/pypi/cua-sandbox/json

**Apple:**

71. https://developer.apple.com/app-store/review/guidelines/ (2.5.1)
72. https://developer.apple.com/documentation/virtualization/vzvirtualmachineview/capturessystemkeys

**In repo:**

73. [decisions.md](../plan/decisions.md), [06-computers-and-browsers.md](../plan/06-computers-and-browsers.md), [feature-catalog.md](../plan/feature-catalog.md), [execution-environments.md](agentic-workspace-landscape/landscape/execution-environments.md), and the profiles for [Grok Bot](agentic-workspace-landscape/projects/grok-bot.md), [Dots](agentic-workspace-landscape/projects/openai-dots.md), [Muse](agentic-workspace-landscape/projects/meta-muse.md), [Hermes](agentic-workspace-landscape/projects/hermes-agent.md), [OpenBot](agentic-workspace-landscape/projects/openbot.md), [OpenMausBot](agentic-workspace-landscape/projects/openmausbot.md) and [Aiden Agent](agentic-workspace-landscape/projects/aiden-agent.md)
