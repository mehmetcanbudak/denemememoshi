# OSS long tail: open-source projects in the agentic workspace / persistent-bot category

Scope: open-source (or source-available) projects beyond those profiled elsewhere in this research set. Excluded by design: Grok Bot, OpenMausBot, Rakazo, Noodle (pdparchitect), Lorca, nightly-labs/openbot, Aiden Agent (sambitcreate), Kuvo Code, OpenClaw and its claw derivatives (zeroclaw, nanoclaw, picoclaw, ironclaw, nullclaw, mimiclaw, etc.), Hermes Agent and Hermes-specific clients.

## 1. Method

All queries run on 2026-10-20. Star counts and push dates come from the authenticated GitHub REST API (`gh api repos/OWNER/REPO`) on that day; they move daily.

| Source | Queries / pages |
|---|---|
| GitHub topics (`gh search repos --topic ... --sort stars`) | grok-bot, grokbot, openai-dots, meta-muse, ai-teammates, personal-agent, personal-assistant, agent-workspace, pi-coding-agent, opencode |
| GitHub keyword search (`gh search repos`) | "Grok Bot alternative", "open source Grok Bot", "OpenAI Dots alternative" (0 hits), "Meta Muse alternative" (0 hits), "AI teammates", "persistent AI agents", "pi coding agent desktop", "opencode desktop", "grok bot clone", "codex desktop app", "claude code gui", "pi desktop app", "grok-ship" |
| Directories | [grokbotguide.com/open-source](https://grokbotguide.com/open-source/) (third-party, 14 entries dated 2026-09-02), [agent-orchestrators.com](https://agent-orchestrators.com/) (third-party, 257 tools; categories "assistants", "swarms", "desktop/web", "terminal") |
| Awesome lists | [RongleCat/awesome-grok-bot](https://github.com/RongleCat/awesome-grok-bot), [ZeroPointRepo/awesome-grok-bot](https://github.com/ZeroPointRepo/awesome-grok-bot), [kydlikebtc/awesome-grokbot](https://github.com/kydlikebtc/awesome-grokbot), [majiayu000/awesome-grok-bot](https://github.com/majiayu000/awesome-grok-bot) (mostly catalogs of x.ai/bot share links, not software) |
| Hacker News (hn.algolia.com API, stories with `created_at_i > 2026-08-01`) | "Show HN Grok Bot", "open source Grok Bot", "AI teammates", "Show HN personal agent", "OpenAI Dots", "Meta Muse open source", "Show HN agents own computer", "Show HN pi agent", "Show HN opencode" |
| Verification | README read via `gh api repos/O/R/readme` for every project with a note below; LICENSE header via `gh api repos/O/R/license`; oldest commit via the commits API for repos whose `created_at` predates the category. No clones, no code executed. |

Identity checks performed:
- **Renamed repos with inherited stars.** Three repos have a `created_at` years before the category existed but a first commit in 2026: [feder-cr/invisible_dots](https://github.com/feder-cr/invisible_dots) (created 2024-08-04, oldest commit 2026-09-29), [Anil-matcha/open-dots](https://github.com/Anil-matcha/open-dots) (created 2023-05-25, oldest commit 2026-09-29), [vastsa/PI-Desktop](https://github.com/vastsa/PI-Desktop) (created 2023-03-22, oldest commit 2026-07-24). Their star counts (marked `*`) are most likely carried over from an earlier project under the same repo id [INFERENCE] and overstate traction in this category.
- **Bloks** resolved to [hamedgitty/bloks](https://github.com/hamedgitty/bloks) through the source link on the [grokbotguide page](https://grokbotguide.com/open-source/bloks/); **OpenGrok** to [OnlyTerp/opengrok](https://github.com/OnlyTerp/opengrok).
- **"OpenBot" is three projects:** [CopilotKit/OpenBot](https://github.com/CopilotKit/OpenBot) (MIT, AG-UI template, covered here), nightly-labs/openbot (profiled elsewhere), and small same-name clones ([Leka74/openbot](https://github.com/Leka74/openbot), [jccrump/openbot](https://github.com/jccrump/openbot), [openbotorg/openbot](https://github.com/openbotorg/openbot)).
- **"Aiden" is three projects:** sambitcreate/aiden-agent (profiled elsewhere); [aidenapp.org](https://aidenapp.org/) (closed-source paid macOS IDE over Claude Code/Codex CLIs, Free/$20 Solo/$169 lifetime per its site); [taracodlabs/aiden](https://github.com/taracodlabs/aiden) (AGPL-3.0 "Autonomous Work Engine", npm `aiden-runtime`). None of the three are related.
- **"Noodle":** [poteto/noodle](https://github.com/poteto/noodle) (MIT, Go, 517 stars, last push 2026-03-19) is unrelated to the profiled pdparchitect/noodle.
- **"Conductor"** (Melty Labs) has no public repo (`melty-labs/conductor` returns 404); T3 Code's README names it as closed inspiration ([t3code README](https://github.com/pingdotgg/t3code)). Not in the table.
- **gawkbot** predates Grok Bot: repo created 2026-03-25 ([GitHub API](https://github.com/najmuzzaman-mohammad/gawkbot)), relabelled "open source grok bot" after the 2026-08-11 launch [INFERENCE from dates].

## 2. Triage table

Sorted by stars. Clusters: a = bot-roster messengers cloning Grok Bot; b = self-hosted agent platforms; c = Pi GUIs/workspaces; d = opencode/Codex/Claude GUIs and orchestrators; e = vertical/niche. "Engine(s)" is what the README names; "own" means the project ships its own agent loop. `*` = stars likely inherited from a renamed repo (see Method). Licenses: SPDX from the GitHub API; non-SPDX licenses read from the LICENSE header.

| # | Name | Repo / URL | License | Stars (2026-10-20) | Last push | Cluster | Stack | Engine(s) | Concept | Standout idea | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | cc-switch | [farion1231/cc-switch](https://github.com/farion1231/cc-switch) | MIT | 146,560 | 2026-10-19 | d | Rust/Tauri | Claude Code, Codex, OpenCode, OpenClaw configs | Desktop switcher for provider/config of many coding CLIs | Single place to swap providers across harnesses | reference |
| 2 | paperclip | [paperclipai/paperclip](https://github.com/paperclipai/paperclip) | MIT | 104,912 | 2026-10-20 | b | TypeScript, Node + React | BYO: any agent that accepts a heartbeat | Org-chart 'company' of agents with goals, budgets, approvals | Heartbeat-driven agents plus per-agent budgets and governance | profile-worthy |
| 3 | orca | [stablyai/orca](https://github.com/stablyai/orca) | MIT | 98,728 | 2026-10-20 | d | TypeScript, Electron | Codex, Claude Code, OpenCode, Pi | Parallel worktree orchestrator with mobile companion | Design Mode: click a DOM element to send HTML/CSS/crop to the agent | profile-worthy |
| 4 | multica | [multica-ai/multica](https://github.com/multica-ai/multica) | Multica License (source-available) | 53,266 | 2026-10-20 | b | Go + TypeScript | Claude Code, Codex, Cursor, Copilot, Kimi, OpenCode | Issue board where agents are assignees | Agents as board teammates, 'Squads', cron 'Autopilots', local daemon runtime | profile-worthy |
| 5 | nanobot | [HKUDS/nanobot](https://github.com/HKUDS/nanobot) | MIT | 49,205 | 2026-10-20 | b | Python | own loop, any model | Ultra-light self-hosted personal agent framework | Minimal codebase with WebUI, MCP, memory | reference |
| 6 | CowAgent | [zhayujie/CowAgent](https://github.com/zhayujie/CowAgent) | MIT | 47,470 | 2026-10-20 | b | Python | own harness, many models | Personal assistant + agent harness wired to chat apps | Long-lived (2022) codebase pivoted to agent harness; large CN chat-app reach | reference |
| 7 | herdr | [herdrdev/herdr](https://github.com/herdrdev/herdr) | Apache-2.0 | 44,880 | 2026-10-18 | d | Rust | any terminal agent CLI | Background runtime owning agent terminals | Sessions survive reboot; agents spawn panes and prompt each other over a socket API | reference |
| 8 | openhuman | [tinyhumansai/openhuman](https://github.com/tinyhumansai/openhuman) | GPL-3.0 | 42,171 | 2026-10-20 | b | Rust | own harness | Personal agent harness: desktop app + Rust library | Claims hundreds of agents on a $10 server (vendor claim) | reference |
| 9 | buzz | [block/buzz](https://github.com/block/buzz) | Apache-2.0 | 36,168 | 2026-10-20 | a | Rust, Tauri + React | ACP: Goose, Codex, Claude Code | Slack-like workspace on a self-owned Nostr relay | Every message, approval and git event is a signed event in one log | profile-worthy |
| 10 | QwenPaw | [agentscope-ai/QwenPaw](https://github.com/agentscope-ai/QwenPaw) | Apache-2.0 | 35,865 | 2026-10-20 | b | TypeScript | AgentScope, many models | Personal assistant deployable locally or in cloud, many chat apps | Formerly CoPaw; Alibaba AgentScope lineage | reference |
| 11 | AionUi | [iOfficeAI/AionUi](https://github.com/iOfficeAI/AionUi) | Apache-2.0 | 33,652 | 2026-10-19 | d | TypeScript, Electron | ACP: Claude Code, Codex, OpenCode, Gemini CLI, OpenClaw, Hermes, Pi, 20+ | '24/7 Cowork app' GUI over many CLI agents | Broadest multi-harness GUI via ACP | reference |
| 12 | invisible_dots | [feder-cr/invisible_dots](https://github.com/feder-cr/invisible_dots) | MIT | 32,180* | 2026-10-19 | a | TypeScript + Go | own agent via OpenRouter | Self-hosted Dots/Grok Bot clone: each Dot owns a QEMU VM | Anti-detection patched Firefox per browser identity; crash-safe task log | profile-worthy |
| 13 | t3code | [pingdotgg/t3code](https://github.com/pingdotgg/t3code) | MIT | 28,681 | 2026-10-20 | d | TypeScript, Electron + mobile | Claude Code, Codex, Cursor, Grok Build, OpenCode, Antigravity | 'Agent harness control surface' on desktop, web, iOS, Android | Reuses existing subscriptions; remote-ready | reference |
| 14 | cmux | [manaflow-ai/cmux](https://github.com/manaflow-ai/cmux) | custom (no SPDX) | 28,293 | 2026-10-20 | d | Swift (Ghostty) | any terminal agent | macOS terminal with vertical tabs and agent notifications | Native Ghostty base | skip |
| 15 | happy | [slopus/happy](https://github.com/slopus/happy) | MIT | 24,231 | 2026-10-19 | d | TypeScript | Claude Code, Codex, Grok, ACP | Desktop + E2E-encrypted mobile app for agent sessions | E2E encryption between phone and host | reference |
| 16 | paseo | [getpaseo/paseo](https://github.com/getpaseo/paseo) | custom (no SPDX) | 21,486 | 2026-10-20 | d | TypeScript | multiple coding agents | Orchestrate coding agents from desktop and mobile | Mobile-first supervision | reference |
| 17 | openworker | [andrewyng/openworker](https://github.com/andrewyng/openworker) | MIT | 18,629 | 2026-10-17 | b | Python | BYO key or Ollama | Desktop 'AI coworker' delivering finished work | Every action governed and logged; specialist coworkers | reference |
| 18 | rowboat | [rowboatlabs/rowboat](https://github.com/rowboatlabs/rowboat) | Apache-2.0 | 18,040 | 2026-10-20 | b | TypeScript | own | AI coworker with memory and collaboration | Knowledge-graph memory | reference |
| 19 | claudian | [YishenTu/claudian](https://github.com/YishenTu/claudian) | MIT | 15,740 | 2026-10-20 | e | TypeScript | Claude Code, Codex | Obsidian plugin embedding coding agents in a vault | Notes-first workspace | reference |
| 20 | superset | [superset-sh/superset](https://github.com/superset-sh/superset) | ELv2 | 15,386 | 2026-10-20 | d | TypeScript | 100+ parallel coding agents | Agentic IDE for parallel agents | Scale target: 100+ agents | reference |
| 21 | agent-orchestrator | [OrchestratorInc/agent-orchestrator](https://github.com/OrchestratorInc/agent-orchestrator) | Apache-2.0 | 13,396 | 2026-10-20 | d | Go | Claude Code, Codex, 30+ | Supervised agent teams planning to merge | Live Kanban with PRs/CI/review | reference |
| 22 | openchamber | [openchamber/openchamber](https://github.com/openchamber/openchamber) | MIT | 11,896 | 2026-10-19 | d | TypeScript | OpenCode | Agentic dev environment on OpenCode | Largest opencode-specific GUI found | reference |
| 23 | cloudflare-os | [cloudflare/cloudflare-os](https://github.com/cloudflare/cloudflare-os) | Apache-2.0 | 11,490 | 2026-10-20 | b | TypeScript, Workers | own on Workers | Self-hostable 'company OS' on Cloudflare | Gatekeepers guardrail framework; sandboxed apps | reference |
| 24 | Octop | [TencentCloud/Octop](https://github.com/TencentCloud/Octop) | MIT | 10,364 | 2026-10-20 | b | Python | own multi-agent | Multi-user assistant with expert team; WeCom/Feishu/QQ | Multi-user from day one | reference |
| 25 | munder-difflin | [HarnessMD/munder-difflin](https://github.com/HarnessMD/munder-difflin) | MIT | 8,929 | 2026-10-19 | a | TypeScript, Electron, Pixi.js | Claude Code, Codex, Grok, Kimi, Gemini, Qwen, OpenCode, Crush, Pi, Copilot, Cursor | Office of CLI agents coordinated by 'your clone' | 2D office floor; mailbox + memory per agent; local dictation and meeting notes | profile-worthy |
| 26 | claude-squad | [smtg-ai/claude-squad](https://github.com/smtg-ai/claude-squad) | AGPL-3.0 | 8,630 | 2026-08-20 | d | Go | Claude Code, Codex, OpenCode, Amp | tmux manager for parallel terminal agents | Detached sessions per worktree | skip |
| 27 | openrig | [mvschwarz/openrig](https://github.com/mvschwarz/openrig) | Apache-2.0 | 7,930 | 2026-10-20 | d | TypeScript | Claude Code, Codex, Pi | YAML-defined persistent agent team in tmux | Team-as-config file | reference |
| 28 | PI-Desktop | [vastsa/PI-Desktop](https://github.com/vastsa/PI-Desktop) | LGPL-3.0 | 7,055* | 2026-10-20 | c | TypeScript, Electron + Rust host | Pi | Modular plugin desktop workspace on Pi harness | Plugin system; Rust host core | reference |
| 29 | OpenBot | [CopilotKit/OpenBot](https://github.com/CopilotKit/OpenBot) | MIT | 6,694 | 2026-10-19 | a | TypeScript, Docker Compose, PostgreSQL | any AG-UI agent | Company-owned bot template: one container computer per bot | Policy check + audit row before every action; generative UI answers | profile-worthy |
| 30 | LobsterAI | [netease-youdao/LobsterAI](https://github.com/netease-youdao/LobsterAI) | MIT | 6,131 | 2026-10-20 | e | TypeScript | own | Desktop agent for data analysis, slides, docs | Office-deliverable focus | reference |
| 31 | open-dots | [Anil-matcha/open-dots](https://github.com/Anil-matcha/open-dots) | none (no LICENSE file) | 5,897* | 2026-10-19 | a | Python + Next.js | Claude Code CLI only | Self-hosted Dots alternative: Telegram/web tasks in sandboxes | Approval prompts before writes/shell/push; routines with missed-run tracking | reference |
| 32 | Raven | [EverMind-AI/Raven](https://github.com/EverMind-AI/Raven) | Apache-2.0 | 5,522 | 2026-10-20 | d | Python | Claude Code, Codex, OpenCode, OpenClaw, Hermes, Copilot, Qwen, Kimi | Host agent planning tasks as a DAG over sub-agents | 'Harness of harnesses' | reference |
| 33 | devspace | [Waishnav/devspace](https://github.com/Waishnav/devspace) | MIT | 5,279 | 2026-10-12 | e | TypeScript | ChatGPT/Claude/Grok Bot via MCP | Self-hosted MCP server exposing your machine to chat assistants | Turns hosted assistants into local coding agents | reference |
| 34 | tutti | [tutti-os/tutti](https://github.com/tutti-os/tutti) | Apache-2.0 | 3,845 | 2026-10-08 | b | TypeScript | Claude Code, Codex, Hermes, OpenClaw | Multi-user, multi-agent real-time collaboration space | Open-source + paid VM edition split | reference |
| 35 | CodexDesktop-Rebuild | [Haleclipse/CodexDesktop-Rebuild](https://github.com/Haleclipse/CodexDesktop-Rebuild) | none | 2,728 | 2026-10-03 | d | JavaScript | Codex | Cross-platform rebuild of Codex desktop | Unofficial port | skip |
| 36 | Memoh | [felinics/Memoh](https://github.com/felinics/Memoh) | AGPL-3.0 | 2,710 | 2026-10-20 | b | Go | built-in (Vercel AI SDK) or hosted Claude Code/Codex | Every agent gets its own cloud computer, memory, channels | Telegram/Discord/Lark/WeChat channels; self-host or cloud | profile-worthy |
| 37 | agent-teams-ai | [777genius/agent-teams-ai](https://github.com/777genius/agent-teams-ai) | AGPL-3.0 | 2,282 | 2026-10-19 | d | TypeScript | Claude Code, Codex, OpenCode, Cursor, Grok, Copilot, 200+ models | Desktop for autonomous coding-agent teams | Inter-agent messaging + Kanban + review | reference |
| 38 | waku-agent | [ShenSeanChen/waku-agent](https://github.com/ShenSeanChen/waku-agent) | MIT | 2,059 | 2026-10-11 | b | Python | own | Local-first agent harness you own | Own loop and memory | skip |
| 39 | gini-agent | [Open-Curiosity/gini-agent](https://github.com/Open-Curiosity/gini-agent) | MIT | 2,041 | 2026-07-18 | b | TypeScript | own | 'The agent that remembers and learns' | Memory-first; no push since 2026-07-18 | skip |
| 40 | core | [RedPlanetHQ/core](https://github.com/RedPlanetHQ/core) | custom (NOASSERTION) | 2,000 | 2026-09-07 | e | TypeScript | memory layer | 'Personal AI OS' memory graph | Portable memory across agents | reference |
| 41 | row-bot | [siddsachar/row-bot](https://github.com/siddsachar/row-bot) | Apache-2.0 | 1,630 | 2026-10-19 | b | Python | Ollama or cloud | Local-first desktop assistant (ex-Thoth) | Visible browser automation; parent-led child agents | reference |
| 42 | nanoMuse | [nano-muse/nanoMuse](https://github.com/nano-muse/nanoMuse) | GPL-3.0 | 1,547 | 2026-10-18 | a | Swift + web + relay | own, BYO key or community relay | Open Muse clone: one named agent on phone, desktop, web | Self-hostable relay joins devices; free community model allowance | profile-worthy |
| 43 | gawkbot | [najmuzzaman-mohammad/gawkbot](https://github.com/najmuzzaman-mohammad/gawkbot) | Sustainable Use License | 1,506 | 2026-10-15 | a | Go + macOS/iOS | Claude Code, Codex, OpenCode, Hermes, OpenClaw, local | Grok Bot clone that builds bots/micro-apps from a description or demo | Adopts agents already on the machine; Mac-notch approvals | profile-worthy |
| 44 | alook | [alookai/alook](https://github.com/alookai/alook) | Apache-2.0 | 1,424 | 2026-10-20 | a | TypeScript | Claude Code, Codex, OpenCode, Pi | Rooms where people and local agents share channels and DMs | Agents get handles, inboxes, memberships; shareable | reference |
| 45 | gentle-shell | [Gentleman-Programming/gentle-shell](https://github.com/Gentleman-Programming/gentle-shell) | MIT | 1,367 | 2026-10-19 | c | TypeScript | Pi | Pi-native shell for controlled development | Workspace-led control | skip |
| 46 | openmeld | [amplifthq/openmeld](https://github.com/amplifthq/openmeld) | MIT | 1,366 | 2026-10-20 | a | TypeScript | hosted Center Agent + Codex, Claude Code, Grok Bot, OpenCode, Antigravity, Cursor CLI | Shared Spaces for people, cloud agents and everyone's local agents | Mixes hosted agent with each member's local agents | reference |
| 47 | talorys | [rociiu/talorys](https://github.com/rociiu/talorys) | MIT | 1,344 | 2026-10-19 | b | TypeScript, Cloudflare Workers | own | Single-user assistant deployed into your own Cloudflare account | Zero vendor backend; memory with temporal 'past fact' handling | profile-worthy |
| 48 | pi-gui | [minghinmatthewlam/pi-gui](https://github.com/minghinmatthewlam/pi-gui) | MIT | 1,273 | 2026-10-14 | c | TypeScript, Electron | Pi (@earendil-works/pi-coding-agent) | Desktop shell around the Pi CLI with worktree threads | No separate agent: all sessions/auth via pi itself | reference |
| 49 | celesto | [CelestoAI/celesto](https://github.com/CelestoAI/celesto) | Apache-2.0 | 1,040 | 2026-10-17 | e | Python | infra | Secure persistent computer for AI agents | Sandbox-as-a-product for persistent agents | reference |
| 50 | OpenCompany | [zeenie-ai/OpenCompany](https://github.com/zeenie-ai/OpenCompany) | MIT | 1,013 | 2026-10-16 | b | Python | own | Self-improving 'AI employees' | Company metaphor | skip |
| 51 | wesight | [freestylefly/wesight](https://github.com/freestylefly/wesight) | MIT | 950 | 2026-10-01 | d | TypeScript | Claude Code, Codex, OpenClaw, Hermes | One-click desktop workspace for many CLIs | CN market installer | skip |
| 52 | agent-swarm | [desplega-ai/agent-swarm](https://github.com/desplega-ai/agent-swarm) | MIT | 906 | 2026-10-20 | b | TypeScript | Claude Code, Codex, Pi, OpenCode, Cursor, Amp, Grok, Devin, ACP | Lead agent delegates to container workers with memory and schedules | Company OS with review gates | reference |
| 53 | pi-web | [jmfederico/pi-web](https://github.com/jmfederico/pi-web) | MIT | 894 | 2026-10-20 | c | TypeScript | Pi | Web UI keeping Pi sessions alive in real workspaces | Browser supervision after disconnect | reference |
| 54 | pocketpaw | [pocketpaw/pocketpaw](https://github.com/pocketpaw/pocketpaw) | MIT | 892 | 2026-10-20 | b | Python | own | Self-hosted personal AI in 30 seconds | Install speed focus | skip |
| 55 | ling-stack | [ling-stack-org/ling-stack](https://github.com/ling-stack-org/ling-stack) | MIT | 888 | 2026-10-20 | a | TypeScript | BYO models | Local project channel with model-bound AI teammates | Tool approvals and results kept with the conversation | reference |
| 56 | aiden | [taracodlabs/aiden](https://github.com/taracodlabs/aiden) | AGPL-3.0 | 859 | 2026-10-19 | b | TypeScript (npm aiden-runtime) | multiple providers | 'Autonomous Work Engine' across files, terminal, browser, channels | Not the profiled sambitcreate Aiden Agent | reference |
| 57 | kody | [kody-hq/kody](https://github.com/kody-hq/kody) | FSL-1.1-ALv2 | 819 | 2026-10-20 | e | TypeScript | any agent | 'Your agents' cloud': memory, keys, code, automations | Portable agent state across harnesses | reference |
| 58 | Codync | [leepokai/Codync](https://github.com/leepokai/Codync) | Apache-2.0 | 637 | 2026-10-20 | a | Rust | Claude Code, Codex, Cursor, Pi, OpenCode, Grok Build, Gemini, Copilot, ~40 | Coding agents as persistent bots messaged from phone/desktop | iOS App Store client; free, no paid tier | reference |
| 59 | taOS | [jaylfc/taOS](https://github.com/jaylfc/taOS) | AGPL-3.0 | 573 | 2026-10-20 | b | Python | multi-framework | Self-hosted agent OS, offline by default | Multi-framework group chat | reference |
| 60 | opengrok | [OnlyTerp/opengrok](https://github.com/OnlyTerp/opengrok) | MIT | 492 | 2026-09-22 | e | JavaScript | routes Grok Bot to any model | Model-routing layer for Grok Bot itself | Per-agent model selection inside the official app | reference |
| 61 | personal-agent-template | [vercel-labs/personal-agent-template](https://github.com/vercel-labs/personal-agent-template) | MIT | 475 | 2026-09-02 | b | TypeScript | Vercel AI SDK [INFERENCE] | Template for a durable personal agent: web, Slack, Linear | Official Vercel reference architecture | reference |
| 62 | OpenInstinct | [Merit-Systems/OpenInstinct](https://github.com/Merit-Systems/OpenInstinct) | MIT | 465 | 2026-10-05 | e | TypeScript | any model | iMessage assistant driving a real browser | Encrypted vault unlocked per action | reference |
| 63 | pi-app | [justhil/pi-app](https://github.com/justhil/pi-app) | MIT | 379 | 2026-10-19 | c | TypeScript | Pi, Codex | Pi desktop app | Pi GUI | skip |
| 64 | open-instinct | [mariagorskikh/open-instinct](https://github.com/mariagorskikh/open-instinct) | MIT | 375 | 2026-10-16 | e | TypeScript | unknown | Open-source Instinct via iMessage | Instinct clone | skip |
| 65 | rho | [mikeyobrien/rho](https://github.com/mikeyobrien/rho) | MIT | 374 | 2026-10-01 | b | TypeScript | unknown | Always-running agent that checks in on its own | Proactive check-ins on macOS/Linux/Android | reference |
| 66 | howcode | [IgorWarzocha/howcode](https://github.com/IgorWarzocha/howcode) | MIT | 369 | 2026-10-16 | c | TypeScript | Pi | 'The Pi desktop app you want to use' | Pi GUI | skip |
| 67 | pi-desktop | [DLYZZT/pi-desktop](https://github.com/DLYZZT/pi-desktop) | Apache-2.0 | 277 | 2026-10-18 | c | TypeScript, Electron | Pi (+ Herdr integration) | pi-desktop.app: local-first Pi workbench | Shared user/agent browser with separate read/interact grants; nested tool-call history | reference |
| 68 | Comma | [AFK-surf/Comma](https://github.com/AFK-surf/Comma) | AGPL-3.0 | 271 | 2026-10-03 | b | Elixir | unknown | Sessionless always-on proactive assistant | Goal decomposition across computer, phone, browser | reference |
| 69 | rovai-ai | [murray17/rovai-ai](https://github.com/murray17/rovai-ai) | MIT | 200 | 2026-10-20 | a | Rust | Claude Code, Codex CLI, OpenCode, Pi | Persistent teams of coding agents with shared conversations | Collaborative memory | skip |
| 70 | bloks | [hamedgitty/bloks](https://github.com/hamedgitty/bloks) | FSL-1.1-MIT | 200 | 2026-10-19 | a | TypeScript | Claude Code, Codex (provider sessions); imports OpenClaw/Hermes setup | Messaging-app desktop: agents as contacts, rooms as group chats | /goal loops until a check passes; quiet check-in routines | reference |
| 71 | xiryn | [SouravBeraAkaSpeed/xiryn](https://github.com/SouravBeraAkaSpeed/xiryn) | MIT | 191 | 2026-10-13 | a | TypeScript, Docker | any model, Claude Code, Codex | Personal agent team, each with a Linux desktop in Docker | Telegram control; encrypted vault | reference |
| 72 | oto-dock | [OtoDock/oto-dock](https://github.com/OtoDock/oto-dock) | FSL-1.1-ALv2 | 191 | 2026-10-14 | b | Python | Claude Code, Codex | Self-hosted company OS with agents in departments | Departments metaphor | skip |
| 73 | grok-ship | [kunchenguid/grok-ship](https://github.com/kunchenguid/grok-ship) | MIT | 189 | 2026-09-06 | e | Python | Grok Bot + Cursor cloud agents | Software-factory distribution for Grok Bot | Adversarial review before PRs | skip |
| 74 | DeepSeekBot | [BotHarness/DeepSeekBot](https://github.com/BotHarness/DeepSeekBot) | MIT | 176 | 2026-10-20 | a | TypeScript | DeepSeek Harness | GrokBot alternative on DeepSeek Harness | Cheap-model bot team | reference |
| 75 | errand | [runta-dev/errand](https://github.com/runta-dev/errand) | Apache-2.0 | 136 | 2026-09-22 | a | TypeScript, Electron | Runta Runtime (cloud) | Desktop home for persistent teammates on Runta cloud computers | Vendor runtime funnel | skip |
| 76 | hypergrok-trading-desk | [galleonlabs/hypergrok-trading-desk](https://github.com/galleonlabs/hypergrok-trading-desk) | MIT | 127 | 2026-10-19 | e | Python | Grok Bot | Seven-agent Hyperliquid trading desk template | Role prompts for a desk | skip |
| 77 | OpenGrokBot | [wolfqing/OpenGrokBot](https://github.com/wolfqing/OpenGrokBot) | MIT | 72 | 2026-09-29 | a | TypeScript | ACP, Ollama | Self-hosted teammates each with its own computer | Explicit Grok Bot feature parity table | skip |
| 78 | 5dive | [5dive-ai/5dive](https://github.com/5dive-ai/5dive) | MIT | 72 | 2026-10-20 | b | Shell/bash | claude, codex, others | Agent company where each agent is a Linux user + systemd service | OS primitives instead of a platform: unix users, systemd, journald, SQLite queue | reference |
| 79 | jelly | [dctanner/jelly](https://github.com/dctanner/jelly) | MIT | 60 | 2026-10-19 | a | TypeScript, Bun + React + SQLite | Pi; ChatGPT subscription or key | Local multi-bot system for running a business from one VM | Sudo-on-request; VNC browser takeover | reference |
| 80 | botato | [hackyguru/botato](https://github.com/hackyguru/botato) | Apache-2.0 | 58 | 2026-09-24 | a | TypeScript | Claude Code, Gemini CLI, Ollama | Local bots with memory, schedule, own computer; shared channels | Bots read and answer each other in rooms | reference |
| 81 | guaca | [madebywelch/guaca](https://github.com/madebywelch/guaca) | AGPL-3.0 | 45 | 2026-10-19 | a | Rust | ACP | Desktop for agent crews in a container workspace, local or VPS | Plugins are MCP servers gated per agent | skip |
| 82 | Pi-App | [AJSubrizi/Pi-App](https://github.com/AJSubrizi/Pi-App) | MIT | 35 | 2026-08-05 | c | TypeScript | Pi, Codex | Pi desktop app | No push since 2026-08-05 | skip |
| 83 | sugabots | [nitrictech/sugabots](https://github.com/nitrictech/sugabots) | MIT | 31 | 2026-10-20 | a | TypeScript, React + Hono + PostgreSQL | Anthropic/OpenAI-compatible | Self-hosted workspace with agent 'pods' | Encrypted provider creds in your DB | skip |
| 84 | open-grok-bot | [Anil-matcha/open-grok-bot](https://github.com/Anil-matcha/open-grok-bot) | none (no LICENSE file) | 14 | 2026-09-20 | a | Python, FastAPI + Next.js | unknown | Grok Bot alternative with governed computer use | Same author as open-dots | skip |
| 85 | open-grokbot | [ishandutta2007/open-grokbot](https://github.com/ishandutta2007/open-grokbot) | MIT | 9 | 2026-08-13 | a | Python | Ollama | Early (2026-08-13) clone | First-48h clone | skip |
| 86 | OpenGrokBot | [Z4YT0N/OpenGrokBot](https://github.com/Z4YT0N/OpenGrokBot) | MIT | 7 | 2026-10-01 | a | TypeScript | Claude Code, Codex, Gemini CLI, OpenAI-compatible | AI company debating in a group chat | Subscription reuse | skip |
| 87 | OpenGrokBot | [nickylin/OpenGrokBot](https://github.com/nickylin/OpenGrokBot) | MIT | 4 | 2026-09-29 | a | JavaScript | Codex, OpenRouter, Ollama | Chinese-language Grok Bot replica | Same roster UI | skip |

Leads seen but not verified enough for the table: Pi pod ([Show HN, 121 points, 2026-10-02](https://news.ycombinator.com/item?id=49937304), pipod.dev), Routi Bot ([Show HN 2026-09-08](https://news.ycombinator.com/item?id=49617611); `narralabs/routi` returned 404), Linubot ([Show HN 2026-09-08](https://news.ycombinator.com/item?id=49614843); `agent-sh/linubot` returned 404), [jakob-bu/grok-bot-linux-unofficial](https://github.com/jakob-bu/grok-bot-linux-unofficial) (unofficial Linux port of the closed app, 32 stars, [HN 33 points](https://news.ycombinator.com/item?id=49467702)), [ChHsiching/grok-bot-0.18-original](https://github.com/ChHsiching/grok-bot-0.18-original) (archive of Grok Bot 0.18 runtime bundles; licensing of redistributed vendor code is questionable).

## 3. Clusters

**(a) Bot-roster messengers cloning Grok Bot.** The densest cluster: GitHub search returned 2,011 repositories matching "grok bot" created after 2026-08-11, 21 of them with the exact phrase "Grok Bot alternative" (search API `total_count`, 2026-10-20; [search](https://github.com/search?q=%22Grok+Bot+alternative%22&type=repositories)). Two sub-shapes. *BYO-CLI rosters* wrap agents already on the machine as named bots: gawkbot, Munder Difflin, Codync, Bloks, Alook, botato, Z4YT0N/OpenGrokBot. *Own-computer platforms* give each bot a VM/container: CopilotKit OpenBot, invisible_dots, Xiryn, wolfqing/OpenGrokBot, Errand (vendor cloud), Guaca. Messaging-layer variants push the metaphor further: Buzz (Nostr relay), OpenMeld and Alook (shared rooms with other humans' agents). nanoMuse is the only serious Muse-shaped (single named agent, many devices) clone. Most small entries (< 100 stars) are a weekend of work with feature-parity tables and no releases.

**(b) Self-hosted agent platforms.** Older or broader than the Grok Bot wave: paperclip (company/org-chart), multica (issue board), Memoh (agent-per-cloud-computer), nanobot, CowAgent, QwenPaw, Octop, OpenHuman, Rowboat, OpenWorker, Cloudflare OS, Talorys, 5dive, agent-swarm. They converge on the same feature list from the opposite direction (platform first, chat UI second).

**(c) Pi GUIs/workspaces.** Pi (earendil-works) has become a popular embeddable harness; at least eight desktop/web shells wrap it: pi-gui, PI-Desktop, pi-web, DLYZZT/pi-desktop (pi-desktop.app), howcode, justhil/pi-app, AJSubrizi/Pi-App, gentle-shell, plus Jelly using Pi as its agent core. All are developer-centric (threads, worktrees, review); none frames Pi as a non-developer assistant except Jelly.

**(d) opencode/Codex/Claude GUIs and orchestrators.** Huge star counts (Orca, cc-switch, t3code, AionUi, Happy, Paseo, Superset, herdr, cmux) but the product is "many coding sessions in parallel worktrees with mobile supervision", not persistent teammates. Relevant to Memoh/Memoshi for the harness-adapter layer and phone-companion UX, not for the assistant layer.

**(e) Vertical/niche.** Domain templates on top of Grok Bot or clones (HyperGrok trading desk, grok-ship software factory, Anomalia marketing), Instinct clones on iMessage (OpenInstinct, open-instinct), routing/bridging layers (OpenGrok model router for Grok Bot, DevSpace MCP bridge), memory/state layers (CORE, kody), and notes-centric embeddings (Claudian in Obsidian).

## 4. Notes on the 8 most interesting projects not covered elsewhere

### CopilotKit OpenBot (cluster a)
- MIT, TypeScript, 6,694 stars as of 2026-10-20, created 2026-08-17, six days after Grok Bot ([GitHub API](https://github.com/CopilotKit/OpenBot)). Launched via [Show HN 2026-08-19](https://news.ycombinator.com/item?id=49365575).
- Explicitly "a template, not a product": no hosted version, nothing published as a package; you fork and replace the example tenant package ([README](https://github.com/CopilotKit/OpenBot)).
- Any agent speaking AG-UI arrives as a "coworker with a channel of its own"; answers can be UI components rather than prose ([README](https://github.com/CopilotKit/OpenBot)).
- Each bot's allowed browser and file actions reach "one container each with its own Chromium, logins and workspace"; every action is checked against policy and gets an audit row before it runs ([README](https://github.com/CopilotKit/OpenBot)).
- Docker Compose + PostgreSQL; no model ships in the box. Thread storage uses CopilotKit Intelligence, which the README says runs locally on a free Developer plan, so there is a commercial dependency (vendor claim).
- Relevance: the cleanest open reference for "policy decision before action, audit after" and protocol-agnostic agent onboarding (AG-UI).

### invisible_dots (cluster a)
- MIT, TypeScript + Go, 32,180 stars* (inherited, see Method); oldest commit 2026-09-29, the day Dots launched ([GitHub API](https://github.com/feder-cr/invisible_dots)).
- Each "Dot" gets a hardware-accelerated QEMU VM with a Linux desktop and persistent disk that sleeps when idle and wakes for messages, tasks or automations ([README](https://github.com/feder-cr/invisible_dots)).
- Browser is a C++-patched Firefox with in-engine fingerprinting ("built to be undetectable by anti-bot systems"); each browser identity keeps its own cookies and logins ([README](https://github.com/feder-cr/invisible_dots)).
- Per-tool allow/ask/deny permissions; "ask" items wait in an Inbox, survive restarts and run exactly once; crash-safety claim that a `kill -9` never double-runs a tool call (vendor claim).
- Reach: web UI, CLI, HTTP API with live events, Telegram, opt-in WhatsApp; models via OpenRouter.
- Relevance: strongest open design for durable task queues and exactly-once tool execution; the anti-detection angle is a legal/ToS risk Memoshi should not copy blindly [INFERENCE].

### gawkbot (cluster a)
- Sustainable Use License (fair-code, not OSI), Go, 1,506 stars, created 2026-03-25 ([GitHub API](https://github.com/najmuzzaman-mohammad/gawkbot), [LICENSE](https://github.com/najmuzzaman-mohammad/gawkbot/blob/main/LICENSE)).
- Concept: describe a job in one sentence or "demo it once on a call" and it builds a bot plus a micro-app with its own screen, schedule and tool allowlist, across 1200+ integrations (vendor claim) ([README](https://github.com/najmuzzaman-mohammad/gawkbot)).
- Discovers and "adopts" Claude Code, Codex or OpenCode already on the machine and places them under a "Chief of Staff" bot.
- Approval UX: a gawkbot pops out of the Mac camera notch; answer with one key, by voice, or from an iPhone companion. Every send, commit, purchase and delete waits for a click.
- Publishes a row-by-row comparison against Grok Bot, Rakazo, OpenMausBot, OpenBot ([gawk.bot/open-source-grok-bot](https://gawk.bot/open-source-grok-bot.html), competitor page).
- Relevance: "record a demonstration, get an automation" plus generated micro-app UIs is the most product-differentiated idea in the long tail.

### Munder Difflin (cluster a)
- MIT, TypeScript/Electron/Pixi.js, 8,929 stars, created 2026-05-31 ([GitHub API](https://github.com/HarnessMD/munder-difflin)).
- Wraps 12 CLIs (Claude Code, Antigravity, Codex, Grok, Kimi, Gemini CLI, Qwen, OpenCode, Crush, Pi, Copilot CLI, Cursor) and runs them on the user's existing subscriptions ([README](https://github.com/HarnessMD/munder-difflin)).
- Each agent gets long-term memory, a mailbox and a desk on a 2D office floor; "your clone" (Michael) routes work between agents.
- Bundles local dictation into any app and local meeting transcription ("cancel your Granola and Wispr Flow").
- Open core: Pro tier $150/year after 2026-10-24, free until then (vendor claim, README).
- Relevance: proof that a playful spatial UI plus voice capture sells; also shows the open-core path a desktop roster app can take.

### nanoMuse (cluster a)
- GPL-3.0, Swift + web + relay, 1,547 stars, created 2026-09-23; README reports 1,000 stars on 2026-10-13, eighteen days after first release ([README](https://github.com/nano-muse/nanoMuse)).
- One named agent with its own look, in the style of Meta Muse: acts instead of answering, keeps working while the app is closed, remembers you, asks before irreversible actions.
- Phone app, desktop app, web console and the relay joining them are all in one repo; the relay is self-hostable.
- Free model allowance on a community relay paid by the developer, then BYO key (vendor claim). Version 1.0.0 shipped 2026-10-09, 1.0.5 latest at time of reading.
- Accompanying paper on Hugging Face Daily Papers 2026-10-08 (per README).
- Relevance: the only mature open take on a single persistent persona across devices, the "assistant" half of Memoshi rather than the "team" half.

### Memoh (cluster b)
- AGPL-3.0, Go, 2,710 stars, created 2026-01-12 ([GitHub API](https://github.com/felinics/Memoh)).
- Every agent gets its own cloud computer: filesystem, desktop, browser, network, long-term memory, online 24/7 when the laptop is closed ([README](https://github.com/felinics/Memoh)).
- Runs its built-in agent with your keys, or hosts existing Claude Code and Codex agents inside Memoh workspaces.
- Channels: Telegram, Discord, Lark, WeChat, Web UI. Memory spans sessions and platforms; scheduled tasks and MCP tools.
- Dual distribution: hosted cloud (app.memoh.net) and one-line self-host via Docker Compose, with a single-process mode when no internal RPC secret is set.
- Relevance: predates Grok Bot by seven months with the same "agent-per-computer" model; also a name collision risk with "Memoshi" worth noting [INFERENCE].

### Buzz by Block (cluster a)
- Apache-2.0, Rust, 36,168 stars, created 2026-03-06 ([GitHub API](https://github.com/block/buzz)).
- Self-hostable workspace where humans and agents share rooms; under the hood it is a Nostr relay, so every message, reaction, workflow step, review approval and git event is a signed event in one log ([README](https://github.com/block/buzz)).
- Same identity and audit model for people and processes; agents can open repos, send patches, review code, run workflows, edit canvases and orchestrate other agents.
- Agents enter through an agent-first JSON CLI and an ACP harness (Goose, Codex, Claude Code); YAML workflows trigger on message, reaction, schedule or webhook. Approval gates are listed as "infra exists, glue still drying".
- Relevance: the strongest answer to "how do bots and humans share an auditable, portable record"; signed events give provenance for free.

### Talorys (cluster b)
- MIT, TypeScript on Cloudflare Workers, 1,344 stars, created 2026-10-10 ([GitHub API](https://github.com/rociiu/talorys)); agent-orchestrators.com reports +421 stars in 7 days (third-party).
- Single-user assistant that runs entirely in the user's own Cloudflare account, installed with `npx create-talorys@latest`; no server, database or account operated by the developers ([README](https://github.com/rociiu/talorys)).
- Chat, durable personal memory you can view/edit/delete, tasks, notes, projects, reminders and routines on a schedule.
- Memory history handles facts that change over time (e.g. asks whether the old car is now a past fact); optional semantic recall, off by default.
- Relevance: serverless "your cloud, not ours" deployment is a cheap always-on path that avoids running a VM per user.

Also profile-worthy but likely overlapping other agents' scope: [paperclip](https://github.com/paperclipai/paperclip) ("If it can receive a heartbeat, it's hired"; org charts, budgets, governance), [multica](https://github.com/multica-ai/multica) (agents as issue assignees, Squads, cron Autopilots, source-available license), [Orca](https://github.com/stablyai/orca) (parallel worktrees, mobile companion, Design Mode), and [5dive](https://github.com/5dive-ai/5dive) (each agent is a Linux user running an official CLI as a systemd service, coordinated through one bash CLI and a SQLite task queue).

## 5. Patterns

**Copied from Grok Bot by nearly everyone** (observed across the cluster (a) READMEs above):
- Named bots with persona/avatar in a messenger-style sidebar (roster), 1:1 chats plus group rooms where bots read each other.
- "Each bot gets its own computer": VM (invisible_dots), container (OpenBot, Xiryn, Guaca), cloud runtime (Memoh, Errand) or a per-bot directory (gawkbot, botato).
- Persistent memory written by the agent as notes/skills in its home directory.
- Routines/cron schedules and webhook triggers; approval gates on external actions; phone reach via Telegram or a companion app.
- Bring-your-own-subscription: wrapping Claude Code/Codex/OpenCode CLIs instead of paying per token, which is the main pitch against Grok Bot pricing.

**Rare** (one or two projects each):
- Exactly-once tool execution and crash-safe queues (invisible_dots).
- Signed, portable event log for human and agent actions (Buzz).
- Automation authored by demonstration plus generated micro-app UIs (gawkbot).
- Policy decision before action with an audit row, as a first-class layer (CopilotKit OpenBot).
- Budgets per agent and org-level governance (paperclip).
- Temporal memory ("this is now a past fact") (Talorys).
- Single persona synced across phone/desktop/web via a self-hostable relay (nanoMuse).
- Local voice capture and meeting transcription bundled into the roster app (Munder Difflin).
- OS-native isolation (unix users + systemd) instead of containers (5dive).

**Gaps nobody fills yet** [INFERENCE]:
- A unified personal-assistant + team product: projects split into "one persona" (nanoMuse, Talorys) or "a roster of workers" (most of cluster a); none lets the personal assistant own and delegate to the roster with shared memory.
- Cross-bot memory governance: no project offers user-reviewable shared memory with provenance and per-bot read scopes.
- Cost control for always-on agents: only paperclip exposes budgets; none shows predicted spend before a routine runs, despite press on idle token burn ([The Register, press](https://www.theregister.com/ai-and-ml/2026/10/13/openais-dot-assistant-burned-300k-tokens-in-a-day-without-a-single-prompt/5302913)).
- Portability: no shared bot-definition format beyond small attempts ([jcpsimmons/gbdl](https://github.com/jcpsimmons/gbdl), 3 stars); bots cannot move between clones or to/from Grok Bot.
- Evaluation and replay: none offers "rerun last week's routine against a new model and diff the outcome".
- Non-developer onboarding: almost every project requires a signed-in coding CLI, Docker, or Node; among the projects read, only gawkbot, Codync and Munder Difflin state that they ship signed macOS installers ([gawkbot](https://github.com/najmuzzaman-mohammad/gawkbot), [Codync](https://github.com/leepokai/Codync), [Munder Difflin](https://github.com/HarnessMD/munder-difflin)).
