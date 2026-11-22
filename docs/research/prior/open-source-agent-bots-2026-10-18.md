# Prior research: open-source personal-agent bots and Pi Durable adoption (2026-10-18)

**Status:** Draft 4 · 2026-10-20 · imported prior research; everything below the `BEGIN VERBATIM COPY` marker is a frozen, byte-identical copy of the source
**Owns:** Memoshi's archived copy of the 2026-10-18 survey of open-source personal-agent bots, with its provenance and known stale points
**Depends on:** [Research index](../README.md) · [Landscape report](../agentic-workspace-landscape/README.md) · [Agent harnesses](../agentic-workspace-landscape/landscape/agent-harnesses.md#pi) · [In-house assets: Apollo](../agentic-workspace-landscape/landscape/in-house-assets.md#apollo)

## Provenance

| Field | Value |
|---|---|
| Source file | `~/Projects/research/open-source-agent-bots-2026-10-18.md`, 25,168 bytes, SHA-256 `f42bca62641fbbe12e032e56379e6a66a480930af7a1c814e717ba4c68ac15e0` |
| Written | 2026-10-17 22:10 UTC, which was 2026-10-18 01:10 local time; hence the date in the file name and in the body's "Research snapshot" line |
| Produced by | omp session `01a14be0-cb85-76b6-9dba-8b2713e2be3d` ("Research top ten open-source bots"), working directory `~/Projects`, model `gpt-6.1-sol` through the `openai-codex` provider. A `BotLandscape` subagent saved a first evidence draft at 22:07 UTC. The parent session read it and rewrote the file into this ranked report at 22:10 UTC. The source bytes still equal that final write. Transcript: `~/.omp/agent/sessions/-Projects/2026-10-17T21-59-45-797Z_01a14be0-cb85-76b6-9dba-8b2713e2be3d.jsonl` |
| Request | The user asked the agent to check Rakazo ("open source grok bot"), find similar open-source bots (alternatives to Grok Bot, Meta Muse and OpenAI Dots, and boop-style assistants such as Apollo), rank a top 10, and find projects that use the new Pi Durable and Code Mode |
| Method (from the body) | Official repositories, license texts, release notes, docs, selected execution code, and a local Apollo and boop checkout. Nothing was installed or run and no model calls were made. GitHub API requests hit HTTP 403 partway through, so ordinary pages were used. Context7's `/earendil-works/pi` docs were consulted |
| Written for | **Apollo**, not Memoshi: the ranking weighs "usefulness to Apollo" |
| Imported | 2026-10-20: copied with `cp`, then this header was prepended. Nothing below the marker was edited |

Check the body against the source (prints `identical`):

```sh
sed '1,/^<!-- BEGIN VERBATIM COPY -->$/d' docs/research/prior/open-source-agent-bots-2026-10-18.md \
  | diff - ~/Projects/research/open-source-agent-bots-2026-10-18.md && echo identical
```

## Known stale points (checked 2026-10-20)

1. **Wrong Apollo checkout.** The "Local Apollo" row and the "Boop and Apollo" section inspected `~/Projects/TEM/apollo-agent`, which pinned `@earendil-works/pi-agent-core` and `pi-ai` at 0.74.0. The active Apollo is `~/Memo/apollo-agent` (package version 1.0.52). It pins `@earendil-works/pi-durable` 1.3.0, and `pi-agent-core`, `pi-ai`, `pi-codemode`, `pi-coding-agent`, `pi-mcp` and `chord` at 1.3.0 as well. It has its own Code Mode in `server/pi/codemode.ts` ([audit](../agentic-workspace-landscape/landscape/in-house-assets.md#apollo)). So the body's "pins Pi core/ai 0.74.0, not new Durable" and "native Pi codemode adoption was not established" do not describe the active checkout.
2. **Broken relative links.** `../TEM/apollo-agent/README.md`, `package.json` and `CONTEXT.md` resolve only from `~/Projects/research/`. In this repo they point nowhere.
3. **Dated numbers.** Star counts (for example Rakazo's 4,455), push dates and "latest release" observations are from 2026-10-17. So are the third-party Pi pins: Rakazo on 0.87.1, Pi Pocket on Durable 1.1.0, and mikan on `^1.3.0` in source.
4. **Pi itself.** v1.3.0 (2026-10-15) is still the latest upstream release on 2026-10-20 (`gh api repos/earendil-works/pi/releases`). It is the version the plan pins ([D6](../../plan/decisions.md#d6)).
5. **License labels.** The body lists IronClaw, ZeroClaw and OpenFang as "MIT OR Apache-2.0". The landscape's [OpenClaw derivatives table](../agentic-workspace-landscape/projects/openclaw.md) lists all three as Apache-2.0, taken from the GitHub API's single license field [INFERENCE: the API reports one SPDX ID for dual-licensed repos]. Read the license file before reusing any code.
6. **Overlap with newer research.** Rakazo, Hermes Agent, OpenClaw and OpenMausBot have full 2026-10-20 profiles in [`../agentic-workspace-landscape/projects/`](../agentic-workspace-landscape/projects/). nanobot, QwenPaw, NanoClaw, invisible_dots and open-dots appear in the [long tail](../agentic-workspace-landscape/landscape/oss-long-tail.md) or the OpenClaw derivatives table. Where the two disagree, the newer landscape docs win.

## What is still unique here

- **The Pi Durable adoption check.** It separates projects that really run Durable and Code Mode (Pi Pocket, mikan, pi-imessage) from those that only carry the name (PiClaw, pi-durable-components, OpenClaw Code Mode, pi-chat). The landscape report profiles none of them. Per the body, mikan installs upstream durable Code Mode (`createCodemodeExtension`) in a real chat bot, while Pi Pocket wraps its own Code Mode declared `replay: "unsafe"`, so an interrupted script is not replayed. Both are source observations from 2026-10-17.
- **Fit notes on projects the landscape skipped:** Agent Zero, Moltis, Letta Code, and Kortix/Suna. Suna's default branch is under the Elastic License 2.0, so it is ideas only under [D33](../../plan/decisions.md#d33).

Memoshi keeps the Pi lessons, not the ranking. Durable replays work after a crash but does not make external side effects exactly-once, and a custom Code Mode does not inherit durable replay. The plan already encodes both: principle 6 in [MASTER_PLAN §3](../../plan/MASTER_PLAN.md#3-principles), Code Mode through `pi-durable/codemode` in [D8](../../plan/decisions.md#d8), and policy on nested calls in [D9](../../plan/decisions.md#d9).

<!-- BEGIN VERBATIM COPY -->
# Open-source personal-agent bots: top 10 and Pi Durable findings

Research snapshot: 2026-10-18. Ranked for persistent personal teammates with memory, background work, tools/computer access, self-hostability, and usefulness to Apollo. This is a fit assessment, not a benchmark or a security certification. Rakazo is included in the ten as the reference project.

**Evidence:** official repositories, actual license texts, release notes, documentation, selected execution code, and the local Apollo/Boop checkout. No projects were installed or run; no live model calls, crash-recovery scenarios, or comparative performance tests were performed. Features below are documented or source-inspected, not independently demonstrated. Current-main capabilities can exceed packaged releases. Open-source application code does not make model access or optional hosted connectors free/open-source.

## Top 10

| Rank | Project / app license | Why it belongs | Main tradeoff |
|---|---|---|---|
| 1 | [Rakazo](https://github.com/elie222/rakazo) — Apache-2.0 | Closest direct Grok Bot/Muse/Dots product shape: persistent named bots, memory, routines, bot-to-bot delegation, browser/terminal/desktop computers, web/Electron/mobile clients, model and sandbox choice. | Still beta; operating API, worker, Postgres and agent computers is a real deployment. Pi-based does not establish native Pi Durable adoption. |
| 2 | [Hermes Agent](https://github.com/NousResearch/hermes-agent) — MIT | Particularly strong everyday assistant: searchable conversation history, agent-maintained memory, reusable skills created from work, scheduled jobs, subagents and a multi-messenger gateway. | More tools/backends mean more setup and secrets. “Learning” means editing skills/memory, not guaranteed improvement or weight training. |
| 3 | [OpenClaw](https://github.com/openclaw/openclaw) — MIT | Broadest integration/device ecosystem in this survey: messaging channels, gateway, control UI, companion apps, automations, plugins, memory, browser and execution tools. | Large operational surface. Its documentation says main-session tools run on the host unless sandboxing is configured. |
| 4 | [Rowboat](https://github.com/rowboatlabs/rowboat) — Apache-2.0 | Most differentiated knowledge-work coworker: editable Markdown knowledge graph, email, meeting notes, browser, scheduled/event agents and collaborative Spaces. | Desktop/work-context-centric. Fully self-hosted multiplayer Harbor adds Postgres, authentication and hosting concerns. |
| 5 | [Agent Zero](https://github.com/agent0ai/agent-zero) — MIT | Complete agent-computer product: Dockerized Linux desktop/browser, project memory, files, document work, scheduler, tools and subordinate agents. Not merely an SDK despite the “framework” description. | Heavier computer workload; broad first-party messenger parity with Hermes/OpenClaw was not established. Host bridging increases reach and risk. |
| 6 | [Moltis](https://github.com/moltis-org/moltis) — MIT | Compelling local persistent server: Rust binary, web/PWA, memory, voice, messaging, cron, browser, MCP and container/Apple Container/WASM options. | Smaller ecosystem. Current main has moved beyond the observed September binary release; browser/container workflows still need those dependencies. |
| 7 | [PiClaw](https://github.com/rcarmo/piclaw) — MIT | Strong packaged Pi-native workspace: browser chat, live steering, editor, terminal, document viewers, memory, schedules, MCP and add-ons. | Primarily single-user; process/workspace access is not per-user OS isolation. Latest release explicitly has not migrated to Pi Durable. |
| 8 | [Pi Pocket](https://github.com/TannerMidd/pi-pocket) — MIT | Most relevant fresh Durable-native personal-product reference: mobile-first PWA, shared sessions, schedules, subagents, browser, approved lessons and codemode. | Young 0.x app on experimental infrastructure. Steering grants host-user authority; its custom codemode is not replayable like upstream durable-codemode. |
| 9 | [QwenPaw, formerly CoPaw](https://github.com/agentscope-ai/QwenPaw) — Apache-2.0 | Complete local-model-friendly workstation: Console/TUI/desktop, multiple agents, memory, schedules, documents, browser/computer tools and many channels. | Broad, fast-moving stack with China-channel emphasis. Old CoPaw instructions can be stale; plugins/models have separate licenses. |
| 10 | [NanoClaw](https://github.com/nanocoai/nanoclaw) — MIT | Useful fork-and-customize teammate architecture: per-agent containers, memory and messaging identities; schedules and credential gateway. Especially relevant to extending Apollo through code. | Native Claude Agent SDK path; adapters/extensions are often skill-applied source changes. Maintaining the customized fork is intentional work; no first-party dashboard by design. |

Order prioritizes the requested product shape, then overall assistant breadth/maturity, then differentiated Apollo value. Pi Pocket's position reflects relevance, not evidence it is more reliable than established agents. Boop is assessed separately as the user's existing baseline, rather than taking a discovery slot.

### Maturity and license anchors

| Project | Observed maintenance/release evidence | Actual app-license source |
|---|---|---|
| Rakazo | Initial beta August 13; [metadata](https://api.github.com/repos/elie222/rakazo) showed October 17 push and 4,455 stars. [Changelog](https://github.com/elie222/rakazo/blob/main/CHANGELOG.md). | [Apache-2.0](https://github.com/elie222/rakazo/blob/main/LICENSE) |
| Hermes | Active October 17 [canary](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.2%2Bcanary.20261017T065512Z); not a claim about latest stable. | [MIT](https://github.com/NousResearch/hermes-agent/blob/main/LICENSE) |
| OpenClaw | Active October 17 [beta artifact](https://github.com/openclaw/openclaw/releases/tag/v2026.10.10-beta.2); not a claim about latest stable. | [MIT](https://github.com/openclaw/openclaw/blob/main/LICENSE) |
| Rowboat | [Spaces launch v1.0.3](https://github.com/rowboatlabs/rowboat/releases/tag/v1.0.3), September 17; [v1.0.5](https://github.com/rowboatlabs/rowboat/releases/tag/v1.0.5) feed updated September 30. | [Apache-2.0](https://github.com/rowboatlabs/rowboat/blob/main/LICENSE) |
| Agent Zero | [v2.14](https://github.com/agent0ai/agent-zero/releases/tag/v2.14), October 13, with concrete chat-restoration/browser/delegation/scheduler fixes. | [MIT](https://github.com/agent0ai/agent-zero/blob/main/LICENSE) |
| Moltis | Observed [20260913.02](https://github.com/moltis-org/moltis/releases/tag/20260913.02) packaged release, September 14; main README is newer. | [MIT](https://github.com/moltis-org/moltis/blob/main/LICENSE.md) |
| PiClaw | [v3.3.4](https://github.com/rcarmo/piclaw/releases/tag/v3.3.4), October 15; Pi 1.2.0 qualification. | [MIT](https://github.com/rcarmo/piclaw/blob/main/LICENSE) |
| Pi Pocket | Current source [0.14.0](https://github.com/TannerMidd/pi-pocket/blob/main/package.json); git install, private npm package field, pinned Pi 1.1.0 family. | [MIT](https://github.com/TannerMidd/pi-pocket/blob/main/LICENSE) |
| QwenPaw | [v2.2.2](https://github.com/agentscope-ai/QwenPaw/releases/tag/v2.2.2), October 15. Canonical repo renamed from CoPaw. | [Apache-2.0](https://github.com/agentscope-ai/QwenPaw/blob/main/LICENSE) |
| NanoClaw | [v2026.10.0](https://github.com/nanocoai/nanoclaw/releases/tag/v2026.10.0), October 9. Old qwibitai repository redirects to nanocoai. | [MIT](https://github.com/nanocoai/nanoclaw/blob/main/LICENSE) |

## Rakazo: what was actually checked

Rakazo is not merely a frontend for Grok. Its [README](https://github.com/elie222/rakazo#readme) describes model-neutral persistent bots, peer/subagent delegation, shared/private computers, voice and integrations. The [self-hosting guide](https://github.com/elie222/rakazo/blob/main/docs/self-host.md) documents the actual API + Graphile Worker + PostgreSQL + computer-provider topology and published multi-arch images. Core operation need not use a hosted sandbox or managed connector; model/service choices still determine external dependencies and cost.

The inspected [adapter manifest](https://github.com/elie222/rakazo/blob/main/packages/adapters/package.json) pins `@earendil-works/pi-agent-core`, `pi-ai` and `pi-telemetry` to **0.87.1**, plus Graphile Worker. Its [Pi runtime](https://github.com/elie222/rakazo/blob/main/packages/adapters/src/pi-runtime.ts) constructs a custom `PiAgentRuntime` using `Agent`; its [session module](https://github.com/elie222/rakazo/blob/main/packages/adapters/src/pi-session.ts) offers an opt-in JSONL transcript recorder. This establishes Pi usage, not native `pi-durable` usage or absence of Rakazo's own recovery mechanisms.

Important deployment caveat: Docker computers have open outbound access by default. Restricting host/LAN/cloud-metadata access requires both the documented configuration and host firewall rules, with platform limitations. See [restricted computer egress](https://github.com/elie222/rakazo/blob/main/docs/self-host.md#restricted-computer-egress). Local host-command support is explicitly privileged. Self-hosted does not mean safe to expose or grant real-account access without configuration/review.

**Assessment:** strongest direct product reference for Apollo's persistent-teammate/computer layer, with a young beta and a substantial operating stack. No claim of demonstrated end-to-end reliability.

## New Pi: the important distinctions

Canonical upstream is now [earendil-works/pi](https://github.com/earendil-works/pi). The old Mario Zechner/badlogic pi-mono project was transferred/renamed, not replaced by an unrelated clone: [Earendil announcement](https://earendil.com/posts/announcing-pi-and-lefos/), [0.74.0 namespace change](https://pi.dev/changelog/releases/0.74.0).

- **Pi 1.0 shipped October 1.** The CLI is the coding agent/SDK; **Pi Durable is a separate, explicitly experimental application harness**, not a ready-made personal bot or a drop-in promise that existing Pi apps gained durability. Latest upstream release observed was [v1.3.0](https://github.com/earendil-works/pi/releases/tag/v1.3.0), October 15. [1.0 launch](https://earendil.com/posts/pi-1-0/), [Durable launch](https://earendil.com/posts/pi-durable/).
- **Durable** checkpoints conversations, queued input and model/tool tasks using persistent storage; reopening the same storage can resume unfinished work. Interrupted model calls are retried; interrupted tools rerun only when their replay policy permits it. Submission IDs deduplicate submissions. This is **not exactly-once arbitrary email/message/payment side effects**; applications still need idempotency/reconciliation. Storage has one owning process. [Contract](https://github.com/earendil-works/pi/tree/main/packages/durable).
- **Codemode** lets the model write JavaScript that batches/chains tool calls and filters their results before putting output into context. Upstream uses a QuickJS sandbox without ambient Node/filesystem/network access; exposed tools still have real powers, and completed effects are not rolled back when a script fails. It is not synonymous with a shell or Claude Code. [CLI docs](https://pi.dev/docs/latest/codemode).
- **Upstream durable-codemode** additionally journals nested calls and replays deterministic scripts against that journal after restart. A project implementing a custom `codemode` tool does not automatically have those semantics. [Durable Code Mode](https://github.com/earendil-works/pi/tree/main/packages/durable#code-mode).

### Actual adoption, rather than name matching

| Project | Pi Durable evidence | Codemode evidence / limitation |
|---|---|---|
| **Rakazo** | Not established in inspected 0.87.1 adapter dependencies/runtime. | Not established. A custom queue/runtime is not native Durable proof. |
| **Local Apollo** | Checked-out manifest pins Pi core/ai **0.74.0**, not new Durable. Its documented Convex Work Fabric/delivery durability is a separate mechanism. | Native Pi codemode adoption was not established by this limited local inspection. |
| **PiClaw** | **No in latest v3.3.4**: release explicitly says the planned migration is not implemented. Pi SDK 1.2.0 usage is real. | A manifest override/transitive package is not proof of enabled upstream codemode. |
| **Pi Pocket** | **Yes:** native Harness + SQLite; pinned Durable 1.1.0. | **Yes:** actual `pi-codemode` wrapper, on by default. Wrapper declares `replay: "unsafe"`, so an interrupted script does not receive upstream durable-codemode replay. |
| **mikan** | **Yes:** native Harness + per-conversation-office SQLite. | **Yes, upstream durable-codemode:** source installs `createCodemodeExtension` and selects its tools on the conversation, not just a dependency declaration. |
| **pi-imessage** | **Yes:** native Harness + fsynced JSONL. Published npm 1.0.0 includes Durable 1.0.2. | Codemode integration not established from inspected harness/dependencies. |

Integration anchors: [Pocket manifest](https://github.com/TannerMidd/pi-pocket/blob/main/package.json), [Harness](https://github.com/TannerMidd/pi-pocket/blob/main/src/server/app.ts), [custom codemode](https://github.com/TannerMidd/pi-pocket/blob/main/src/server/extensions/codemode.ts); [mikan session integration](https://github.com/geminixiang/mikan/blob/main/src/harness/session.ts), [storage](https://github.com/geminixiang/mikan/blob/main/src/sessions/session-store.ts); [pi-imessage Harness](https://github.com/daya0576/pi-imessage/blob/main/src/agent/harness.ts), [published manifest](https://registry.npmjs.org/@kingcrab/pi-imessage/latest); [PiClaw release statement](https://github.com/rcarmo/piclaw/releases/tag/v3.3.4).

### Which Durable apps are worth attention?

- **[Pi Pocket](https://github.com/TannerMidd/pi-pocket): personal-product/UI reference.** Mobile/PWA, shared live sessions, cross-session assistant, watches/webhooks, schedules, browser and memory. Linux/macOS/Windows/Android-Termux per README, Linux most tested. Pi's ordinary extensions are not interchangeable with Pocket's extensions. Steering is shell-equivalent host access; single-session invites are not OS security boundaries and the optional guard is off by default. Its custom codemode interruption caveat matters for Apollo recovery design.
- **[mikan](https://github.com/geminixiang/mikan): strongest source reference for upstream Durable + codemode in a real chat bot.** Slack/Telegram/Discord, experimental GitHub; workspace/container/vault/memory per conversation and separate thread sessions. MIT verified from the [license text](https://github.com/geminixiang/mikan/blob/main/LICENSE), despite GitHub's unrecognized-license display. Published [1.5.1](https://registry.npmjs.org/@geminixiang/mikan/latest) still declares Pi ^1.2.0; current source declares ^1.3.0. Small community and coding/team-first, Node 24.15+, PM2 and container setup. **Application policy matters:** on graceful reload, Slack runs continue after restart; other platforms get up to five minutes to finish, then remaining runs abort. [Deployment policy](https://github.com/geminixiang/mikan/blob/main/src/content/docs/deployment.mdx).
- **[pi-imessage](https://github.com/daya0576/pi-imessage): compact local Mac/iMessage borrowing reference.** Talks directly to Messages.app without Sendblue/BlueBubbles/webhook setup; structured memory, scheduler, browser and web control/history. MIT, npm 1.0.0. macOS, Full Disk Access, Node/Python/native dependencies. An unclean-death owner lock requires operator confirmation/recovery; custom tool loading defaults unspecified replay policy to safe, so side-effect safety remains the tool author's responsibility. Reply allowlists do not prevent all message logging. [Source entry](https://github.com/daya0576/pi-imessage/blob/main/src/main.ts).

Other Pi naming pitfalls:

- [pi-durable-components](https://github.com/IgorWarzocha/pi-durable-components) is an MIT developer toolkit, not a bot and not the upstream Durable package. Its native V8 code/notebook modes are distinct from upstream QuickJS durable-codemode; Notebook is explicitly not a sandbox.
- [OpenClaw Code Mode](https://docs.openclaw.ai/tools/code-mode/executors) is OpenClaw's own implementation; it is not proof of Pi Durable adoption. Historical `docs/pi.md` search results now point to a missing file and should not establish current dependencies.
- Official-org [pi-chat](https://github.com/earendil-works/pi-chat) is a runnable Telegram/Discord extension with per-channel VMs, but Durable adoption was not established. Actual license/package are Apache-2.0 despite its README footer saying MIT. Historical [mom](https://github.com/earendil-works/pi/tree/v0.57.1/packages/mom) is not evidence of a maintained current Durable bot; it is absent from current upstream packages.

## Boop and Apollo: avoid comparing the wrong versions

Public [raroque/boop-agent](https://github.com/raroque/boop-agent) is an [MIT](https://github.com/raroque/boop-agent/blob/main/LICENSE) iMessage starter using **Claude Agent SDK or Codex app-server**, Convex, Sendblue and Composio. It documents dispatcher/workers, tiered memory/consolidation, recurring automations, draft approval and optional local browsing. Its author explicitly calls it a starting point, not a finished product, and not optimized for cost/security. That is why it is a baseline here rather than a top-ten new discovery. [Current manifest](https://github.com/raroque/boop-agent/blob/main/package.json).

The local modified Boop README is Pi-only, but that is not the public upstream's current architecture. The inspected Apollo checkout has progressed further: README (`TEM/apollo-agent/README.md`, outside this repository) documents Pi dispatcher/execution agents, iMessage/Telegram/WhatsApp and iOS, Convex persistence, memory, integrations and work orchestration. package.json (`TEM/apollo-agent/package.json`, outside this repository) pins `@earendil-works/pi-agent-core`/`pi-ai` 0.74.0; CONTEXT.md (`TEM/apollo-agent/CONTEXT.md`, outside this repository) documents Work Fabric and durable outbound delivery. These are source/docs observations, not a current live-service audit.

**Apollo recommendation — inference:** borrow Rakazo's persistent-teammate/computer product ideas, Hermes's procedural-skill learning, and Rowboat's inspectable work knowledge. Evaluate Pocket for the Durable-native product layer and mikan for the upstream durable-codemode seam. Compare their recovery semantics with Apollo's existing Convex work/delivery contracts; a newer harness alone is not evidence Apollo needs replacing or that these projects are ahead in every dimension.

## Hosted reference products, not open-source shortlist entries

- [Grok Bot official launch](https://x.ai/news/introducing-grok-bot), August 11: named always-on teammates, cloud computers, routines and bot collaboration.
- [Meta Muse official launch](https://about.fb.com/news/2026/09/introducing-muse-personal-ai-agent/), September 8: personal goals, ongoing work, dedicated VM/browser, WhatsApp/app access and approval boundaries.
- [OpenAI Dots official launch](https://openai.com/index/introducing-dots/), September 29: always-on assistants, cloud computers, connected apps, ChatGPT/Slack/Teams and proactive research.

These announcements provide hosted products, not self-hostable open-source bot code. Model availability, open SDKs or a third party's similarly named repository do not make the product implementation open-source.

## Other credible candidates and why they did not take a slot

- **[Letta Code](https://github.com/letta-ai/letta-code), Apache-2.0:** strong memory/identity alternative with MemFS, channels, cron, server and desktop. Old Letta repository is now a pointer to this runtime, not grounds to dismiss it as an SDK. Cloud is default; local backend must be deliberately chosen and some remote features require sign-in. [v0.34.16](https://github.com/letta-ai/letta-code/releases/tag/v0.34.16), October 16. A close reserve if memory architecture matters more than agent-computer UX.
- **[HKUDS nanobot](https://github.com/HKUDS/nanobot), MIT:** practical readable Python assistant with gateway, memory, automation and UI. Less differentiated than the ten above for this goal. [v0.3.5](https://github.com/HKUDS/nanobot/releases/tag/v0.3.5), September 15; README explicitly describes current source, not necessarily released PyPI capability.
- **[IronClaw](https://github.com/nearai/ironclaw), MIT OR Apache-2.0:** interesting credential injection, allowlisted WASM tools, memory and routines; less evidenced complete GUI-computer/channel breadth. [v1.4.1](https://github.com/nearai/ironclaw/releases/tag/ironclaw-v1.4.1), September 29.
- **[ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw), MIT OR Apache-2.0:** portable Rust/runtime and hardware integration option. Config-first rather than a polished personal teammate; newer V3 config makes old tutorials stale. [v0.8.5](https://github.com/zeroclaw-labs/zeroclaw/releases/tag/v0.8.5), September 5.
- **[OpenFang](https://github.com/RightNow-AI/openfang), MIT OR Apache-2.0:** real autonomous scheduled “Hands” and dashboard, not merely a framework. Pre-1.0; observed latest release [v0.6.9](https://github.com/RightNow-AI/openfang/releases/tag/v0.6.9) May 12 is a release-cadence caution, not proof development stopped.

## Direct clones / license and maturity watchlist

- **[OpenMausBot](https://github.com/milind-soni/OpenMausBot):** very close Grok-style bot roster/computer/takeover UX with real installers. Apache-2.0 core, but [enterprise code is not OSS](https://github.com/milind-soni/OpenMausBot/blob/main/LICENSING.md). [October 17 v0.1.115](https://github.com/milind-soni/OpenMausBot/releases/tag/v0.1.115) defaults new bots to Full access and removes the app's own profile/team/memory prompts; engine-level prompts remain. Older blanket approval claims are stale. App-event triggers are still groundwork, unlike schedules/webhooks. Worth tracking, not ranked ahead on UI promises alone.
- **[invisible_dots](https://github.com/feder-cr/invisible_dots), formerly feder-cr/dots:** substantial MIT alpha with QEMU computer per agent, scheduler and approvals; current engine is a **nanobot hard fork, not Pi**. [Architecture](https://github.com/feder-cr/invisible_dots/blob/main/docs/architecture.md) requires Linux/Windows x86-64 virtualization, explicitly not macOS/ARM; OpenRouter only. Optional WhatsApp dependencies introduce additional GPL obligations in [third-party notices](https://github.com/feder-cr/invisible_dots/blob/main/THIRD_PARTY_NOTICES.md). Poor direct fit for an Apple Silicon Apollo host.
- **[Xiryn](https://github.com/SouravBeraAkaSpeed/xiryn), MIT:** fresh October 11 launch, browser bot/squad UI, per-agent Docker desktops and Telegram. [Runtime](https://github.com/SouravBeraAkaSpeed/xiryn/blob/main/lib/agent/runtime.ts) says in-memory runs survive tab closure, not server restart; independent concurrent teammates and built-in recurring scheduling were not established. Treat as experimental, not parity with Muse/Dots.
- **[CopilotKit/OpenDots](https://github.com/CopilotKit/OpenDots):** MIT alpha template and useful UI/AG-UI reference. README says conversations require CopilotKit Intelligence, through hosted service, local Docker evaluation, or licensed self-hosted deployment. MIT template does not imply a wholly open, restriction-free standalone backend.
- **[Anil-matcha/open-dots](https://github.com/Anil-matcha/open-dots):** MIT marketing was not verified: inspected root tree lacks a license file and direct main/LICENSE returned 404. This is license uncertainty, not a legal conclusion about every historical file. README/source drift also matters: source now has multiple engine adapters and agent-memory injection despite older README limitations. [Engine source](https://github.com/Anil-matcha/open-dots/blob/main/backend/app/services/engine_registry.py), [memory source](https://github.com/Anil-matcha/open-dots/blob/main/backend/app/services/agent_memory.py). Not a recommendation until licensing/packaging are clear.
- **[Kortix/Suna](https://github.com/kortix-ai/suna):** capable full product, but current default-dev [LICENSE is Elastic License 2.0](https://github.com/kortix-ai/suna/blob/dev/LICENSE), including hosted-service restrictions. Source-available, not a strict OSI-open-source entry; do not inherit old Apache/MIT assumptions.

## Interpretation limits

Repository/release evidence proves that code, documentation and artifacts were publicly available when fetched, not that a task succeeds or that crash recovery cannot duplicate side effects. No security marketing or self-published performance comparisons were accepted as measured facts. Releases/main snapshots and upstream/local forks are intentionally distinguished. Public GitHub API requests eventually hit HTTP 403; ordinary source/release pages were used instead rather than inventing metadata. Context7's current `/earendil-works/pi` documentation was consulted alongside first-party Pi docs/source; actual bot adoption was checked in dependencies and selected runtime code.
