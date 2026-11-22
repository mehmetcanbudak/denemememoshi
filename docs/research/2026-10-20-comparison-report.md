# Grok-style assistants: the best references for Memoshi

**Research date:** 2026-10-20. **Purpose:** compare the strongest relevant products, check every supplied source, and define the combination worth building around Kuvo's native workspace and Pi Durable.

**Companion deliverable:** [Memoshi next-version specification](../plan/NEXT_VERSION.md). This repository still contains plans and research, not a working Memoshi application. The new specification is a proposal; Draft 4 remains the accepted baseline.

**Policy/design update, 2026-10-23:** [D91](../plan/decisions.md#d91) permits inspecting and adapting Kuvo Code source for qualifying personal/noncommercial use with its terms, notices and provenance. [D92](../plan/decisions.md#d92) adopts a Viticci-led assistant family with a Kuvo-informed workbench instead of blanket competitor parity; [D93](../plan/decisions.md#d93) removes mandatory design contracting, not design QA. The clean-room and visual-baseline recommendations below record the 2026-10-20 position, not current rules. See the later [frontend assessment](2026-10-23-kuvo-frontend-reuse.md) and [design recheck](2026-10-23-design-direction-review.md); no fork/import or feature/date move is selected.

**Read:** [shortlist and feature matrices](#3-shortlist-ten-core-references-plus-the-requested-openbot) · [native Apple direction](#9-the-viticci-direction-native-utility-not-merely-native-looking-chat) · [memory verdict](#10-optmem-the-gist-and-orbs-three-different-jobs) · [combined version](#11-what-the-combined-version-takes) · [every supplied link](#12-every-supplied-link-checked).

## 1. Recommendation

**Build one Swift product with a Kuvo-style workbench, Grok-style persistent teammates, native Apple resource views, and Pi Durable as its only embedded brain.** Reuse permissively licensed mechanisms selectively. Do not combine entire product backends, and do not call the result SOTA before running comparable tasks.

This is an architecture-fit recommendation [INFERENCE], not a benchmark winner:

- **Kuvo is the right interaction base**, but not a commercially unrestricted code base. Its public licence is PolyForm Noncommercial; the project's existing clean-room decision remains appropriate.
- **A native card should act on a real object.** A reminder checkbox must update the actual reminder; a music view must reflect the player. The model's text is neither the resource state nor the success receipt.
- **Pi persistence, memory and external effects are separate concerns.** Durable task replay does not make an email, calendar write or payment exactly-once.
- **Execution location must be visible.** A Mac client controlling a VPS bot does not give that bot Mac permissions. An iPhone client is not an always-running desktop agent host.
- **Use the new ideas without importing their weaknesses:** no default full access, no unreviewed memory promotion, no generated web UI masquerading as a trusted approval, no obsolete managed-compute dependency.

## 2. Method and evidence

The existing [landscape report](agentic-workspace-landscape/README.md), [26-product matrix](agentic-workspace-landscape/matrix.md), [long-tail survey](agentic-workspace-landscape/landscape/oss-long-tail.md) and [own-code audits](agentic-workspace-landscape/landscape/in-house-assets.md) supplied the starting map. This refresh follows the user's new links and checks high-impact facts against their owners' pages, repositories, documentation and announcements.

The [Tierroom explore page](https://my-tierroom.party/explore) was read in Markdown and opened in a real browser. Its Table view rendered **63 agents**. Its tiers, votes and recommendations are editorial/community signals, not task benchmarks. The [alternatives article](https://my-tierroom.party/blog/open-source-grok-bot-alternatives-mausbot-rakazo-codync-openbot) explicitly describes AI-assisted documentation research and distinguishes three Apache-2.0 products from nightly-labs/OpenBot's noncommercial source availability. We do not reuse its numerical scores as measured quality.

Evidence vocabulary:

- **Documented:** first-party documentation establishes support; operation was not independently exercised.
- **Source-inspected:** selected implementation or licence was inspected; not a complete security or correctness audit.
- **Demonstrated/announced:** a maker's post or demonstration; not proof of general availability or reliability.
- **Inherited:** the earlier repository research supplies a fact; this refresh did not independently repeat that inspection.
- **Unknown:** not established by the inspected evidence. It does not mean absent.
- **[INFERENCE]:** our judgment, proposed design or extrapolation.

No competitor was installed or given credentials, no paid plan was purchased, and no task-completion, latency, security or memory benchmark was run in this refresh. Public documentation and social demos cannot prove those properties.

## 3. Shortlist: ten core references, plus the requested OpenBot

**Order means value to this particular build**, weighing native workspaces, Pi compatibility, distinctive capabilities, inspectable evidence and reuse rights. It is not overall product quality or an empirical SOTA ranking. Infrastructure entries are deliberately labelled: Cua and Reason Network complement an assistant rather than replace one.

| Priority | Product | Why it belongs | Licence / what we can take |
|---|---|---|---|
| 1 | **[Kuvo Code](https://www.kuvo.run/code/)** | Best-fit native workspace reference: projects, worktrees, split sessions, review, bots and browser | PolyForm Noncommercial; clean-room reference, not the source fork |
| 2 | **[Grok Bot](https://x.ai/bot)** | Persistent-teammate experience: proactive Assistant, cards, mobile takeover, connectors and routines | Proprietary; behaviour ideas only |
| 3 | **[Aiden Agent](https://github.com/sambitcreate/aiden-agent)** | Closest inspected runtime example: embedded Pi Durable 1.3.0, recovery, Code Mode, worktrees and artifacts | MIT; selected runtime patterns/code with attribution |
| 4 | **[Codync](https://github.com/leepokai/Codync)** | Strong phone pairing, bounded collaboration, memory-write hygiene and many external harnesses | Apache-2.0; protocols/checks, not copied Grok-derived visual identity or hosted relay |
| 5 | **[Rakazo](https://github.com/elie222/rakazo)** | Always-on server design, pluggable computers, origin/verb-aware policy and watches | Apache-2.0; selected mechanisms |
| 6 | **[Noodle](https://github.com/pdparchitect/noodle)** | Native Swift Mac/iPhone suite and restricted-by-default execution | Apache-2.0; native patterns, not its different runtime |
| 7 | **[OpenMausBot / MausBot](https://github.com/milind-soni/OpenMausBot)** | Broad bots, team packages, browser profiles and per-bot computer choices | Apache-2.0 core; exclude source-available enterprise code |
| 8 | **[Cua Spaces / Driver](https://github.com/trycua/cua)** | Computer infrastructure, observation/input, live view and takeover reference | MIT Driver/client vs FSL Spaces/server/Swift samples; component-level selection |
| 9 | **[Reason Network](https://github.com/reason-machines/reason-network)** | Live-session directory and bounded cross-machine agent communication; Pi extension | MIT OR Apache-2.0 engine; closed CLI/cloud product separate |
| 10 | **[Orbs](https://github.com/nikuscs/orbs)** | Scoped memory, source-linked tombstones, suppression and revision-safe edits | MIT; memory mechanisms, not its unsandboxed/auto-approval defaults |
| 11, comparison reference | **[nightly-labs/OpenBot](https://github.com/nightly-labs/openbot)** | Requested comparison; useful routines and provider handoff, but overlaps with stronger reusable sources | PolyForm Noncommercial; ideas only |

**Grok identity:** the inspected x.ai pages use SpaceXSI branding, while Cursor supplies the downloads, account, cloud and terms. The iOS seller is X Corp. The existing research records SpaceX's Cursor acquisition; the current builder/operator evidence is in the [Grok refresh](2026-10-20-bot-comparison-refresh.md#4-grok-bot-identity-capabilities-and-limits). These are **independent alternatives**, not official open-source editions of Grok Bot. Open model weights, Grok Build's CLI and unofficial reconstructions are different things.

### 3.1 Platform, brain and deployment

The following matrices synthesize the [core-product refresh](2026-10-20-bot-comparison-refresh.md#7-comparison-matrix), [Kuvo check](2026-10-20-kuvo-base.md), [Cua audit](2026-10-20-cua-spaces-refresh.md), [Reason findings](2026-10-20-new-products.md), and [Orbs inspection](2026-10-20-memory-orbs.md). Those retain per-fact primary citations and fresh/inherited labels. Here, **unknown means unestablished, not absent**; none of the capabilities was exercised as a product task.

| Product | Client/platform | Brain and model choice | Where work runs / maturity |
|---|---|---|---|
| Kuvo | SwiftUI/AppKit Mac 26+, Apple silicon | opencode; provider choice | Local Mac or SSH host; v0.5.22 public page |
| Grok | Mac/Windows/Linux; iOS/Android in docs | Cursor-managed harness/models; no customer picker | Cursor cloud only; local commands through desktop; beta/GA wording differs by plan |
| Aiden | Electron Mac arm64/Linux; iOS TestFlight, Android | **Embedded Pi Durable + Code Mode 1.3.0** | Desktop host; v0.59.0 |
| Codync | Electron desktop; SwiftUI iPhone; TUI; Android source | ACP to about 40 harnesses; Pi through `pi-acp`, **not Durable** | Self-hosted Rust host, local/VPS; v2.20.4 |
| Rakazo | Web/Electron; iOS/Android | Embedded `pi-agent-core` **1.3.0**, not Durable | Server + worker + database + selected computer; beta v0.3.x |
| Noodle | Native Swift Mac 26; iOS 26 TestFlight | Vendor harnesses, Apple/local options; no Pi | User Macs and assigned Computer/Browser apps; v0.70.0 |
| MausBot | Electron desktop; PWA; phone apps not sourced in public repo | Multiple CLI/ACP/API drivers; Pi native RPC | Desktop/server/cloud; early v0.1.x |
| Cua | SwiftUI Mac Spaces; other desktop variants; Mac/iPhone bot samples | Bring an agent; SDK has no agent brain | Host/container/VM/BYO infrastructure; SDK 0.5.0, Spaces 0.11.0; Swift SDK build required |
| Reason Network | Machine daemon, CLI/MCP and agent integrations | Connects existing sessions; Pi coding-agent extension | Peer machines/self-hostable relay; early v0.12.0, not a complete assistant UI |
| Orbs | Web app + local daemon | Pi coding-agent RPC; optional hosted Jev routing | Bun/SQLite or Cloudflare; two commits, no releases |
| nightly OpenBot | Electron/web; mobile support in earlier profile | Codex/Claude/ACP; Pi native RPC | Desktop, server and hosted choices; development preview v0.46.0 |

**Two important distinctions:** Pi RPC/ACP compatibility is not embedded Pi Durable. A native phone client is not evidence that the agent runtime executes continuously on the phone. Codync replaced its native Mac transcript with Electron after reported scrolling/streaming problems; that is a performance risk to test, not proof that SwiftUI cannot work.

### 3.2 Bots, collaboration, memory and automation

| Product | Bots / collaboration | Memory / context | Scheduled and proactive work |
|---|---|---|---|
| Kuvo | Persistent jobs; bounded lead-driven Groups and assigned work | Editable per-bot memory; conversation context | Jobs, wakes and model-free watches; remote host for availability |
| Grok | Persistent Bots, groups, Team Bots, primary proactive Bot | Preferences, role/work context; team/per-person context in earlier profile | Schedules, webhooks, app/email triggers; teach-a-task skills |
| Aiden | Durable Bots and child work; no shipped group chat in profile | “About you” + bot notes; history recall; scanned writes | Approved bot-proposed routines and silent outcomes |
| Codync | Rooms capped at 3 rounds/10 replies; ask/message tools; wait-cycle rejection | Shared “yours” + bot memory; protected user edits, checked writes, reversible dreaming | Once/interval/cron/webhook/app events; fresh routine sessions |
| Rakazo | Bots, groups, handoffs and child bots | Bot/shared Markdown in Postgres with revisions | Cron, webhooks, GitHub and read-only watches |
| Noodle | Bot backstories, goal groups, file forwarding | Bot-maintained Markdown | Heartbeats and self-wakes; no webhooks in inspected profile |
| MausBot | Rosters, routed channels, Chief of Staff; portable team definitions | Per-bot Markdown, recall and undo journal in profile | Once/weekdays/interval, local webhooks and Composio events |
| Cua | Bot samples and shared Spaces; agent owns task semantics | Harness-dependent; not a governed memory service | Harness/application responsibility |
| Reason Network | Live people/machine/session directory; push/turn/pull messaging; hop limits | Not a knowledge-memory layer | Delivery/idle wake; not a calendar scheduler |
| Orbs | Mentions, routed/roundtable rooms; queue explanations | Organization/bot/room facts, provenance, revisions and forget suppression | Autonomous scheduling not established in this inspection |
| nightly OpenBot | Agent messaging; channels removed despite stale README | Tiered per-agent knowledge and history search in profile | Chained flows, missed-run policy, signed webhooks and hosted wake |

### 3.3 Workspace, computer and extension surfaces

| Product | Workspace / files / artifacts | Browser and computer boundary | Skills / MCP / connectors |
|---|---|---|---|
| Kuvo | Multi-folder projects, worktrees, attempts, diff/image review, comments, commit/PR | Visible WebKit and remote browser; takeover; a worktree is not a sandbox | Skills/MCP/integrations; exact target checked for credential filling |
| Grok | Shared `/workspace`, files and app/repo cards; not a Kuvo-style Git workbench | Firecracker **per user**, shared by that user's Bots; desktop local-command approval separate | Connect Apps, skills, custom MCP; many account-wide connectors |
| Aiden | Managed worktrees, terminal, diffs, commit/push; Workspace Artifacts | Host execution; optional Mac computer use; Full mode is not sandboxed | Pi tools/Code Mode; broader extension detail in existing profile |
| Codync | Bot folders and versioned notes; **no automatic worktrees** | Real desktop, one bot at a time; phone takeover makes bots look-only; no built-in browser documented | ACP harness ecosystem, connectors and internal `team`/`computer` MCP |
| Rakazo | Terminal/files and CLI Git workflow; no dedicated worktree/diff UI in profile | Docker/other providers; Team/Private computers; new local bridge has no GUI control | Skills, MCP and connector/tool adapters |
| Noodle | Bot/shared folders and patch review | Separate Browser/Computer apps; restrictions fail closed when unavailable | Harness-specific tools; do not assume all harnesses expose identical capabilities |
| MausBot | Bot/channel folders, attachments and shared team configuration | Per-bot browser profiles; cloud/VM/host choices, but agent CLIs still run with host-user privileges | Multiple engines, skills, MCP, Composio; bounded app control plane |
| Cua | Files/processes/streams of the selected Space, not a coding workspace | A Space can be host, container or VM; Driver observes tree + pixels; background input has limits | SDK/CLI/MCP; full Spaces stack has mixed licensing |
| Reason Network | Contextual session directory and bounded file attachments; cloud Reason separately has PR evidence | Uses connected sessions; no new sandbox boundary by itself | MCP and agent hooks/extensions |
| Orbs | Bot homes, shared skills, uploads; Media tab is an empty state | Pi tools execute as the user; explicitly not a sandbox | Bridge injects MCP and skills; internal memory/room/bot tools |
| nightly OpenBot | Agent folders plus Shared; no Git UI established | Host/server Cua Driver; Workspace-only mode versus broad Full access | Many harnesses, skills/MCP; provider fallback/handoff |

### 3.4 Voice, Apple utility, permissions and privacy

| Product | Voice / mobile utility | Native Apple resource-card fit | Material permission / privacy limit |
|---|---|---|---|
| Kuvo | No fresh claim of live voice or shipping phone app | Strong native shell; supplied docs do not establish the requested Music/Shazam/Health views | Approve All default; opt-out anonymous usage; no sandbox implied by folders |
| Grok | Live voice, dictation, memos, phone approvals/takeover | Rich interaction cards, but not evidence of native Apple framework coverage | Shared computer/credentials; model review is an aid, not a hard per-bot boundary; hosted data |
| Aiden | Gemini Live/Parakeet in profile; remote phone access | Electron; borrow runtime, not native views | Bots default Full in profile; narrow Custom grants; host computer use opt-in |
| Codync | On-device voice by default; optional realtime providers; native iPhone | Native phone is useful; not proof of Apple personal-resource integrations | New bots auto-approve; analytics on by default; paired device trusted as owner; webhook delivery is not E2E even though remote pairing is |
| Rakazo | BYO voice services; mobile clients | No native Apple resource suite established | Sandbox boundary and explicit consequential-action policy; Docker egress open by default in prior audit |
| Noodle | On-device transcription; native phone through Hub | Strong native reference, but requested resource coverage unestablished | Restricted default, yet no in-chat approval UI; harness actions auto-approved within access; account lending shares the account |
| MausBot | TTS choices and Mac live calls; phone apps | No public native Swift resource implementation established | Full access default; connected sends/payments can skip cards and limits; server-mode keys stored plaintext |
| Cua | Phone remote computer sample, not evidence of voice or personal-life APIs | Swift samples show useful structure but are FSL | Host mode controls real desktop; prompt rules are not enforcement; default relay sees plaintext |
| Reason Network | Phone reachability depends on connected assistant | No native Apple resource suite | Signed identity is not action authority; closed CLI and hosted paths are separate from OSS engine |
| Orbs | Native mobile/live voice unestablished | Web app, not a Swift capability host | Unsandboxed tools; optional third-party routing/auto-approval receives private inputs |
| nightly OpenBot | On-device spoken replies since 0.46.0; not merely dictation | No requested Swift resource suite established | Full default; “Always allow” escalates; README/changelog disagree; voice usage events collected |

**Commercial and operating cost:** permissive source does not include model, VM or relay costs. Grok's page lists $30/$100/$200 tiers but contradicts its docs on multipliers. MausBot Cloud lists $15/$49/$99 plus differing computer/credit allowances. Kuvo and nightly OpenBot require separate commercial arrangements for uses outside their noncommercial licence. Cua's paid plans now concern relay/session usage, not renting its former cloud computers. Current plan details and caveats are in the linked investigations; none is a normalized cost-per-completed-task comparison.

**Best fit by need [INFERENCE]:** Kuvo for the workbench; Aiden for embedded Durable; Codync for phone/memory protocols; Rakazo for server execution and policy; Noodle for native composition; MausBot for portable teams; Cua for computer tooling; Reason Network for external-session coordination; Orbs for forgetting semantics. Keep all of those behind one product model rather than stacking their servers.

## 4. Why Kuvo remains the base

Kuvo's current [product page](https://www.kuvo.run/code/) advertises SwiftUI + AppKit, an unmodified opencode engine, macOS 26+ on Apple silicon and v0.5.22. Its public docs establish the combination most relevant to the user's workspace requirement:

- [Projects and sessions](https://www.kuvo.run/code/docs/sessions/): multi-folder projects, steer/queue, tabs/splits, worktrees, parallel attempts and context visibility.
- [Review](https://www.kuvo.run/code/docs/changes/): real Git changes, staged/unstaged/branch/session views, image differences, line comments and commit/PR workflow.
- [Bots](https://www.kuvo.run/code/docs/bots/): stable jobs, editable memory, wakes, model-free watches and bounded lead-driven group work.
- [Browser](https://www.kuvo.run/code/docs/browsing/): visible structured actions, human takeover and direct credential filling with stale-target checks.

**What changes:** implement that role around Pi, then add the personal-life resource experience. Do not force Pi into Kuvo's opencode wire protocol or copy its backend.

**What does not transfer:** the site's default Approve All behaviour, opt-out telemetry, or assumption that a bot folder/worktree is a security sandbox. [Detailed Kuvo findings](2026-10-20-kuvo-base.md)

**Licence:** [PolyForm Noncommercial 1.0.0](https://github.com/serhatandic/kuvo-code/blob/main/LICENSE). Public source is not equivalent to an OSI open-source licence or permission for anticipated commercial use. [D33](../plan/decisions.md#d33) and [D43](../plan/decisions.md#d43) already require a clean build. They also record a separate design-law risk for exact visual parity; clean-room code does not eliminate that risk.

## 5. Additional candidates beyond the core comparison

These were checked to avoid selecting only similarly named Grok clones. They are not all suitable product bases.

| Candidate | Primary evidence checked | Useful contribution | Why not replace Pi/Kuvo with it |
|---|---|---|---|
| **Hermes Agent** | [README](https://github.com/NousResearch/hermes-agent/blob/main/README.md): MIT, configurable models, persistent memory/skill learning, schedules, subagents, messaging gateway and multiple execution backends | Learning-loop and channel/automation reference | A separate runtime/product; adopting it wholesale would replace the fixed Pi-brain choice |
| **OpenClaw** | [README](https://github.com/openclaw/openclaw/blob/main/README.md): MIT, one Gateway, broad channels and native companion nodes; main-session tools run on host unless sandboxing is configured | Device-capability routing, pairing and channel integration | Different gateway/runtime ownership; not a native Kuvo-like workbench and not automatically isolated |
| **CopilotKit/OpenBot** | [README](https://github.com/CopilotKit/OpenBot/blob/HEAD/README.md), [MIT licence](https://github.com/CopilotKit/OpenBot/blob/HEAD/LICENSE) | Policy outside the agent; per-bot computer/profile; compiled versus sandboxed interactive UI; takeover refuses agent actions | Explicitly an alpha template, not a finished product. Requires CopilotKit Intelligence and its separate licence/account conditions; MIT at repository root does not remove those dependencies |
| **OpenHuman** | [Memory documentation](https://tinyhumans.gitbook.io/openhuman/features/memory.md); [Tierroom profile](https://my-tierroom.party/agents/openhuman.md) only for broader discovery | Inspectable memory packs, provenance chips, explicit queued-versus-committed memory status | Current memory docs say committed content lives in hosted or self-hosted CortexDB. Do not assume local inference makes memory local. Broader feature/ GPL-3.0 claims here remain the profile's secondary evidence |

CopilotKit/OpenBot is **not** nightly-labs/openbot. The former's root licence is MIT and it is an AG-UI-oriented template; the latter is the source-available workspace discussed in the user's Tierroom article. Neither is an official open-source release of Grok Bot.

The additional product investigations below carry the remaining new sources; the existing landscape matrix remains the larger reference for products not freshly re-profiled.

## 6. Cua's new announcement: useful, but not a free Swift foundation

The [19 October launch thread](https://x.com/trycua/status/2112228154651881479) really does announce the **Cua Spaces SDK** and a Mac/iPhone bots example. The exact post text was cross-checked through X's official embed and a mirror. The implementation and distribution qualifications matter more than the ten-line demo:

| Part | Current finding | Decision for this project [INFERENCE] |
|---|---|---|
| SDK/CLI/local daemon, Driver, Lume, client-side Spaces overlay | MIT; the Swift SDK still requires building the Rust library rather than consuming a published binary | Selectively reusable, pinned and tested; not a complete application |
| In-Space daemon, streaming, Keyvault, teleport, Swift bot samples | FSL-1.1-MIT, including the [Mac example](https://github.com/trycua/cua/blob/main/examples/cua-bots-macos/LICENSE); future MIT conversion is not current MIT permission | Ideas only under D33; do not ship these components |
| Computer location | A Space may be a container, VM, or **the user's real desktop** | Show the actual boundary; “Space” must not imply a VM |
| Background Mac control | Accessibility plus screen capture and undocumented platform mechanisms; foreground fallbacks and unsupported surfaces exist | Do not reopen D41 silently. Prefer the Linux VM driver path |
| Hosted compute | Cua documents Cloud/Fleets as ended on 18 October; some earlier commit wording says 16 October | No dependency on the old managed-compute product |
| Relay/privacy | [Cua documents](https://cua.ai/docs/spaces/guides/relay-security) a plaintext-capable TLS proxy; encrypted mesh is beta, off by default; `prefer` may fall back | A future optional adapter must require the encrypted path or use a trusted direct connection |
| Provider portability | Azure appears in the launch thread but not the full docs; E2B/Daytona need a contrib build and are marked unmeasured | Do not claim universal cloud support |
| Bot safety | Cua Bots documents its rules as instructions, not enforcement | Keep policy in Memoshi's action broker, outside the model |

The [injaneity post](https://x.com/injaneity/status/2112271256972386799) is a suggested prompt telling Grok Bot to install Cua and obtain KVM access. We recorded it, **did not execute it**, and did not treat a social post as permission to change this machine. Whether a particular hosted bot has KVM/sudo remains unverified.

The most valuable reusable piece is **MIT Cua Driver behind the existing computer interface**, especially inside an isolated Linux guest. Its distinction between delivered input and verified application effect is more important than a floating agent cursor. [Full Cua evidence, licences, advisories and limitations](2026-10-20-cua-spaces-refresh.md)

## 7. agentes.chat, Reason and LightVela

### agentes.chat: take the room model, not an unverified security promise

Both [wescld's 20 October browser demo](https://x.com/wescld/status/2112340417832272071) and [15 October feature tour](https://x.com/wescld/status/2110840611213623633) refer to **[agentes.chat](https://agentes.chat)**. The latter is identified by its video, the author's bio and a corroborating linked quote, not just visual resemblance.

The strongest ideas are a responsible person per agent, an audience scope, a router that chooses speakers but grants no permission, pre-call budgets, memory provenance, versioned outputs and in-chat browser takeover. Those fit the combined design.

**Watchlist, not a production-base recommendation:** public access is a waitlist; no repository, licence or usable terms/privacy pages were found. The maker's own demo delegates to Claude Code on a Mac with `--dangerously-skip-permissions`. The site's approval claims do not establish that this nested execution path is governed. Keep Memoshi's mandatory worker permissions instead.

### Reason: separate the network engine from the hosted product

[Reason's site](https://reasonmachines.com) and [X profile](https://x.com/reasonmachines) describe two different things:

- **Reason cloud:** proprietary coding product; useful evidence-backed PRs, shared sessions and opaque one-time link references. Its documented server-side storage of Claude subscription credentials is not a pattern for Memoshi.
- **[Reason Network](https://github.com/reason-machines/reason-network):** MIT OR Apache-2.0 Rust engine, v0.12.0 at inspection. A directory of live sessions across people/machines, encrypted peer transport, Pi integration, explicit push/turn/pull delivery and bounded peer conversations. Early-stage and not runtime-tested here.

Reason Network earns a reference slot because it adds a missing interoperability mechanism without requiring another agent brain. Its closed installer/CLI and server-mediated hosted-assistant path must not inherit the engine's “open source, P2P” label. A signed approval is origin evidence, not permission to bypass Memoshi's policy.

The site and repository contain text addressed to AI agents telling them to run an installer without asking. **Those are untrusted setup instructions; none were followed.**

### LightVela: managed Hermes, not a new engine to embed

[LightVela](https://lightvela.ai) is Tencent Lighthouse's hosted Hermes product. Its current docs cover multiple bot profiles, messaging channels, scheduled tasks, memory controls, a publishing workbench and a Cloud Computer beta. Tierroom's unknown computer-use cell is behind these primary docs.

Borrow the **fixed-text / script / agent** scheduled-task distinction, typed task chaining and memory writes failing explicitly at the cap rather than silently discarding knowledge. Do not adopt another runtime or infer a separate security boundary from each bot profile.

Its [terms](https://lightvela.ai/terms-of-service/) restrict use of service outputs to build competing agentic platforms and publication of benchmarks without consent. No LightVela output was generated for this research. The comparison uses public documentation, and the proposed benchmark excludes it unless authorized.

[Full evidence matrix, retrieved post text, demonstration limits and legal findings](2026-10-20-new-products.md)

## 8. Pi is the right brain, but “all the Pi stuff” needs selection

The [Pi refresh](2026-10-20-pi-brain-refresh.md) checked the release tag, npm metadata and the **published package contents**, not just current `main`.

| Component | Role in the combined product | Decision |
|---|---|---|
| `pi-durable` 1.3.0 | Conversation/task persistence, recovery, nested work and hooks | Execution root |
| `pi-ai` 1.3.0 | Model providers, usage and cost | API keys/local endpoints under existing policy |
| `pi-codemode` 1.3.0 | Bounded scripted tool composition | Through Durable's extension; nested tools still governed |
| `pi-mcp` 1.3.0 | MCP client | Wrap every exposed operation as a governed Durable tool |
| `pi-env` 1.3.0 | Remote filesystem/process execution | Behind named sandbox/VM/SSH executors |
| `chord`, `pi-telemetry` | Internal state/cancellation and telemetry contracts | Dependencies, not extra product backends |
| `pi-coding-agent` | CLI/SDK with its own session owner | Developer tool or explicit external worker, not the embedded brain |
| Gondolin | Egress/secret-placeholder design | Reference; do not import a second VM platform |
| `pi-durable-components` | Some published extensions and useful presentation contracts | Reference only; scheduling/UI/voice pieces are currently local-only |
| `pi-server`, `pi-client`, `pi-protocol`; private web UI; credential relays | Removed, stale, unlicensed or conflicting with project auth policy | Exclude |

Three consequences are already incorporated into the next-version proposal:

1. **Recovery holds are real admission barriers.** In 1.3.0, progress calls can start all recovered work in the Harness's storage file. A held thread cannot accept a normal submission just because `resume()` was omitted.
2. **Durability is not exactly-once effects.** Unsafe tools are not automatically replayed, remote disconnects can leave mutations uncertain, and recorded intent means recovery does not rerun `beforeTool`. The executor still enforces current grants and the effects ledger.
3. **Use exact published artifacts and licence notices.** The inspected `main` has unreleased breaking changes and a one-way storage migration despite still saying 1.3.0. The inspected npm tarballs omit the root MIT licence text.

Pi does not provide the Apple UI, permissions, product scheduler, scoped memory, device pairing, protocol or safe publication workflow. Those remain Memoshi modules. A more complete bundle of packages would not remove those responsibilities.

## 9. The Viticci direction: native utility, not merely native-looking chat

**The prototype is “Apple Bots,” a private project.** Viticci says he ported “most of” Pi Durable to Swift. No public repository, download or TestFlight was found. Four supplied posts show the prototype; [the 14 October post](https://x.com/viticci/status/2110282174440017929) instead shows Grok Bot's proactive suggestions.

All of the supplied Viticci media are **still images, not videos**. They show reminder/change cards, music players and queues, Shazam results, Health charts, weather, Photos/Maps, timers/alarms, voice/Live Activity surfaces, generated mini apps, a Mac Inspector and quick entry. They do not independently prove that controls commit changes or audio plays.

**Corrected 2026-10-21:** this holds for the supplied posts only. A reply outside them carries an 11.6 s video of the prototype resuming a task after a force-quit ([full record](2026-10-21-viticci-apple-bots-record.md#52-the-force-quit-video-observed)).

The combined design adopts the strongest grammar [INFERENCE]:

- Native, typed views of real resources, with source, freshness and execution device.
- Compact “worked / steps” chips and an expandable evidence pane.
- Old/new values and explicit change controls; reversible operations can offer an audited compensating Undo.
- A **live resource view separate from an immutable approval receipt**.
- Quick entry on Mac; compact native navigation on iPhone; actual platform integrations rather than a web card pretending to be Reminders.

The implementation must respect Apple's real platform split:

| User-visible goal | Mac approach | iPhone approach / limit |
|---|---|---|
| Reminders and calendar | EventKit; native editor | EventKit/system editor; public APIs do not expose every Reminders feature |
| Play music | In-app MusicKit player | In-app or permitted system Music player; native macOS lacks that system-player API |
| Shazam | Explicit microphone capture | Explicit microphone capture; this is not arbitrary app-audio interception |
| Alarms, Health, Home | Do not promise phone-only frameworks on native macOS | Authorized phone capability; no invisible always-on iOS agent host |
| Weather | REST path for the Developer ID build | WeatherKit entitlement; attribution required |
| Widgets and Live Activities | Widgets and mirrored phone activities | System budgets and finite lifetimes; not approval or background-execution loopholes |

The [Apple feasibility study](2026-10-20-native-apple-direction.md) links each conclusion to Apple documentation and records the distribution/permission spikes still needed. No private Reminder database access, Full Disk Access, Apple Events or system-audio tap is silently added to the proposal.

The two other examples are now identified:

- **[Oscar Hong → Agent Bump](https://x.com/oscrhong/status/2112267545638207767):** hackathon phone-web experience for introducing two people's agents. Borrow the scoped invitation idea, not an unverified identity/security protocol.
- **[Arne Strickmann → Personal Agent Proxy Quick actions](https://x.com/arnestrickmann/status/2112341539154542928):** MIT project; typed action cards appear while typing, and the action waits for the button. Borrow fast typed drafts and explicit user action. Typing must not itself perform an external mutation.

## 10. OptMem, the gist and Orbs: three different jobs

| Source | What it actually is | Licence found | Decision [INFERENCE] |
|---|---|---|---|
| [OptMem](https://github.com/VictorTaelin/OptMem) | Python notes CLI; agent-written notes and binary-tree summaries; regex recall and an age-faded view | None; licence question remains unanswered | Do not integrate the component |
| [Supplied gist](https://gist.github.com/VictorTaelin/91837951a5ce5b38f341ec1ba1df6449) | OptChat, now headed **UniiChat**: an indefinitely growing transcript with a zoomable summary tree | No licence statement | Relevant to context management, not a replacement for scoped memory |
| [UniiChat implementation](https://github.com/VictorTaelin/uniichat) | Newly published implementation of that recipe | Apache-2.0 | Permissible experimental reference; no demonstrated quality/cost win here |
| [Orbs](https://github.com/nikuscs/orbs) | MIT multi-bot web chat with a local Pi RPC daemon; governed organization/bot/room facts | MIT | Borrow memory mechanisms and group explanations; not its runtime or security defaults |

**Why not “just add OptMem”:** it lacks this product's provenance, visibility and deletion model. Its `forget` drops summaries, not the raw notes; later summaries reconstruct the content. A single lifelong identity also does not implement user/bot/project/team boundaries.

**The gist is relevant, but at a different layer.** A transcript-summary tree could reduce repeated compaction loss and offer zoomable evidence. It does not replace facts with scoped visibility, corrections and retractions. No reproducible task-quality benchmark was found; the cache claims rely on simulations and constrained experiments. Pi 1.3.0's Anthropic adapter does not place the internal view breakpoints that the full recipe assumes.

**Orbs is more valuable for memory governance than for workspaces.** Adopt revision-checked idempotent edits, text-free deletion tombstones, suppression of re-extraction from forgotten source messages, and honest wording about retained chat history. Its source also provides “why this bot answered” and queue explanations.

Do not import Orbs' unsandboxed daemon or model-judged auto-approval. Its hosted Jev routing path can send excerpts, bot instructions and tool inputs to another provider. Its Media tab is an empty state at the inspected commit; it is not evidence of a complete artifact library. Only two commits and no releases were present.

**Chosen memory design:** keep scoped SQLite/FTS5 knowledge, Pi execution history and live Apple resource state separate. Evaluate a tree-shaped compaction summary only behind correctness, privacy, cache-cost and deletion gates. [Full algorithms, source inspection, licences and evaluation plan](2026-10-20-memory-orbs.md)

## 11. What the combined version takes

The concrete deliverable is [**Memoshi — next-version proposal**](../plan/NEXT_VERSION.md): an original native-shell schematic, process architecture, module interfaces, typed resource contract, policy flow, device split, five end-to-end journeys, adoption map and executable acceptance scenarios for future implementation.

| Source | Adopt or preserve in the combined design | Deliberately do not import |
|---|---|---|
| Kuvo | Native workbench, projects/worktrees, review, bounded Groups, watches, visible browser | Source/brand/assets, opencode backend, Approve All default |
| Grok | Persistent teammates, proactive offers, consequential-action cards, mobile handoff, useful completed work | Shared-bot security assumptions, model-only authority, vendor lock-in |
| Aiden | Published Durable integration, explicit recovery, persisted approvals, worktree/artifact evidence | Electron UI and Full-by-default execution |
| Codync | Device-bound pairing, bounded asks, wait-cycle rejection, memory hygiene | Auto-approve/analytics defaults, copied visual identity, third-party personal relay |
| Rakazo | Computer-provider seam, action/origin policy and always-on orchestration | Another backend/database/job owner |
| Noodle | Native composition and refuse-to-start when required confinement fails | Silent approval as a universal policy or sharing account credentials |
| MausBot | Per-bot computer/profile choice and portable team definitions without secrets | Full access, host-privileged nested workers and unconfirmed external sends |
| Cua | Guest-side Driver candidate and precise observation/effect vocabulary | FSL samples/server/media stack, private host APIs, plaintext relay dependency |
| Reason Network / Reason | External-session discovery, honest delivery states, bounded peer messages; evidence-backed PRs | Peer text as authority, closed runtime dependency, server-side subscription credentials |
| Orbs | Revision-safe memory writes, forget suppression, provenance and routing explanations | Unsandboxed Pi RPC daemon and hosted model-based auto-approval |
| nightly OpenBot | Missed-run policy, chained routines and explicit provider handoff ideas | Noncommercial code and broad permission escalation |
| Viticci / Personal Agent Proxy | Native resource views, compact activity, quick typed drafts and real Apple utility | Private prototype code, unproved Swift harness equivalence, automatic effects while typing |
| agentes.chat / Agent Bump | Accountable owners, scoped human-agent rooms and explicit invitations | Undocumented production guarantees or arbitrary sharing of capabilities |
| LightVela | No-model routine modes, typed chaining and explicit memory-cap failures | Hosted Hermes backend or restricted service outputs |
| OptMem / UniiChat | Optional evidence-preserving summary-tree experiment | OptMem code, single-memory authority and unfounded cache/SOTA claims |
| Pi ecosystem | One published, integrity-pinned execution stack | Stale server packages, local-only modules and a second session owner |

The proposal intentionally preserves the accepted decision log instead of silently rewriting it. Adoption must update the affected object/protocol/event/policy/platform/roadmap contracts together. In particular, iPhone-native execution, new resource types and optional memory optimization are **proposed**, not already implemented or approved exceptions to Draft 4.

The target is not “every feature switched on.” It is **one coherent product whose best features share identity, policy, event history, memory scope and evidence** [INFERENCE]. The specification defines how to test that claim; this research does not prove it.

## 12. Every supplied link checked

**21 unique URLs, 22 appearances in the request:** the Cua announcement was supplied twice. All unique sources were retrieved. X text was cross-checked beyond the model relay; media was inspected where recorded in the detailed logs. Product operation was not tested.

| # | Supplied source | Actual finding / evidence limit | Detailed record |
|---|---|---|---|
| 1 | [Tierroom explore](https://my-tierroom.party/explore) | Directory and rendered Table view; 63 entries, editorial signals | [Core comparison](2026-10-20-bot-comparison-refresh.md) |
| 2 | [Cua announcement](https://x.com/trycua/status/2112228154651881479) | Spaces SDK and Mac/iPhone bot samples; exact text corroborated; mixed licences | [Cua](2026-10-20-cua-spaces-refresh.md) |
| 3 | [OptMem](https://github.com/VictorTaelin/OptMem) | Notes CLI and summary tree; no licence found; forgetting is not deletion | [Memory](2026-10-20-memory-orbs.md) |
| 4 | [Victor Taelin gist](https://gist.github.com/VictorTaelin/91837951a5ce5b38f341ec1ba1df6449) | OptChat/UniiChat recipe; all revisions read; context, not scoped knowledge | [Memory](2026-10-20-memory-orbs.md) |
| 5 | [nikuscs/orbs](https://github.com/nikuscs/orbs) | MIT web/Pi-RPC group chat; inspected memory mechanisms and security limits | [Orbs](2026-10-20-memory-orbs.md) |
| 6 | [agentes.chat](https://agentes.chat) | Rendered FAQ/demo; waitlist; legal pages unavailable | [New products](2026-10-20-new-products.md) |
| 7 | [wescld: 2112340417832272071](https://x.com/wescld/status/2112340417832272071) | agentes.chat browser research/takeover demo; sampled video | [New products](2026-10-20-new-products.md) |
| 8 | [wescld: 2110840611213623633](https://x.com/wescld/status/2110840611213623633) | agentes.chat agent/computer/permissions/memory tour; sampled video | [New products](2026-10-20-new-products.md) |
| 9 | [Ga_Vasques comparison](https://x.com/Ga_Vasques/status/2111609699422388339) | Same author's four-product article, not independent benchmark evidence | [New products](2026-10-20-new-products.md) |
| 10 | [Tierroom alternatives article](https://my-tierroom.party/blog/open-source-grok-bot-alternatives-mausbot-rakazo-codync-openbot) | Documentation survey; useful leads; Pi, memory and voice facts now partly stale | [Core comparison](2026-10-20-bot-comparison-refresh.md) |
| 11 | [LightVela](https://lightvela.ai) | Hosted Hermes; current computer/scheduling/memory docs and restrictive terms | [New products](2026-10-20-new-products.md) |
| 12 | [Reason X profile](https://x.com/reasonmachines) | Network and multiplayer announcements; profile/media checked | [New products](2026-10-20-new-products.md) |
| 13 | [Reason site](https://reasonmachines.com) | Proprietary cloud coding product plus separately open network engine | [New products](2026-10-20-new-products.md) |
| 14 | [injaneity](https://x.com/injaneity/status/2112271256972386799) | Grok-to-Cua setup prompt; read as data, not executed | [Cua](2026-10-20-cua-spaces-refresh.md) |
| 15 | [oscrhong](https://x.com/oscrhong/status/2112267545638207767) | Agent Bump hackathon web demo; scoped cross-user introduction idea | [Native direction](2026-10-20-native-apple-direction.md) |
| 16 | [arnestrickmann](https://x.com/arnestrickmann/status/2112341539154542928) | Personal Agent Proxy Quick actions; video and MIT repository | [Native direction](2026-10-20-native-apple-direction.md) |
| 17 | [Viticci: 2108192119152140318](https://x.com/viticci/status/2108192119152140318) | “Apple Bots” origin; claimed Swift Durable port; Health/Music/Shazam stills | [Native direction](2026-10-20-native-apple-direction.md) |
| 18 | [Viticci: 2112555465313853810](https://x.com/viticci/status/2112555465313853810) | Mac prototype, Reminders, Inspector and quick-entry stills | [Native direction](2026-10-20-native-apple-direction.md) |
| 19 | [Viticci: 2111418614343504107](https://x.com/viticci/status/2111418614343504107) | Week-one prototype tour: music, voice, Live Activity, mini app, settings; stills | [Native direction](2026-10-20-native-apple-direction.md) |
| 20 | [Viticci: 2110282174440017929](https://x.com/viticci/status/2110282174440017929) | **Grok Bot**, not his prototype: proactive offer shown in a question card | [Native direction](2026-10-20-native-apple-direction.md) |
| 21 | [Viticci: 2108623467965038946](https://x.com/viticci/status/2108623467965038946) | Alarm/reminder/event claim; Mac alarm cards and phone self-reply; native Mac mechanism unknown | [Native direction](2026-10-20-native-apple-direction.md) |

## 13. Verification, gaps and freshness

- **Observed research surfaces:** Tierroom's rendered explore/table view; the public product pages and media described in the seven supporting investigations. Scripted site demos are labelled, not treated as live executions.
- **Deliverable checks:** 13 new/updated Markdown files checked; 648 local links and anchors resolve; all 21 unique supplied URLs occur in the source ledger; code fences balance. One malformed Apple feasibility row was corrected and its table rechecked. The original SVG schematic was parsed and rendered in Chromium: 34 text labels, no out-of-bounds labels or horizontal overflow; fill inheritance was corrected and visually confirmed. This validates the documents and schematic, not an application.
- **Source evidence:** selected public code/licences, pinned repository revisions, current package metadata and published Pi artifacts. This is not a full security or transitive-licence audit.
- **Unavailable proof:** competitor task execution, Swift prototype source, Apple's actual permission flows on a signed Memoshi app, Pi recovery in Memoshi, and like-for-like quality/cost measurements.
- **Access/document gaps:** agentes.chat's terms/privacy pages did not resolve to usable documents; several vendor sources contradict themselves; Context7 was unavailable, so API claims use the owners' direct docs.
- **Freshness rule:** these refresh files supersede overlapping facts in the older landscape snapshot, especially Rakazo's Pi version, Codync's memory/Mac client, OpenBot's voice/channels, Cua licensing/hosting and Pi publication state. The earlier generated matrix is retained as historical research, not silently regenerated from unmodified profiles.
- **Implementation status:** report and proposed specification only. No Memoshi source code, executable, integration or shipping app was created. The repository's accepted detailed contracts are intentionally unchanged pending adoption.

### Supporting investigations

1. [Grok and core alternatives](2026-10-20-bot-comparison-refresh.md)
2. [Kuvo clean-room base](2026-10-20-kuvo-base.md)
3. [Cua products, licensing and security](2026-10-20-cua-spaces-refresh.md)
4. [OptMem, UniiChat and Orbs](2026-10-20-memory-orbs.md)
5. [agentes.chat, LightVela, Reason and the linked posts](2026-10-20-new-products.md)
6. [Viticci and native Apple feasibility](2026-10-20-native-apple-direction.md)
7. [Pi brain and ecosystem](2026-10-20-pi-brain-refresh.md)
