# Orca

> An MIT-licensed Electron "Agent Development Environment" from Stably AI (YC W22): it wraps ~40 off-the-shelf coding CLIs, gives each task its own git worktree on the local machine, an SSH host, a self-hosted always-on Orca server or a BYO cloud VM, and adds diff review, an embedded Chromium with Design Mode, cron automations, an experimental multi-agent orchestration bus, and an E2E-encrypted iOS/Android companion. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Orca
slug: orca
category: agent-workspace-ide        # parallel-worktree orchestrator over third-party coding CLIs
maker: Stably AI / Stably, Inc. (YC W22; founders Jinjing Liang, Neil Parker); core committers nwparker, Jinwoo-H, brennanb2025
license: MIT   # whole monorepo incl. desktop, mobile and cloud/ relay; API/auth services live in private stablyai/orca-cloud
repo: https://github.com/stablyai/orca
website: https://www.onorca.dev
first_public: 2026-03-17   # repo created and first commit same day; first release v1.0.12 on 2026-03-21
latest_release: v1.4.232, 2026-10-20   # mobile-android-v0.0.57, 2026-10-17
release_cadence: "~5 stable desktop releases/week (21 in 30 days to 2026-10-20) plus RCs; 979 releases total incl. 576 RCs and 39 Android builds"
stars: 98742 (as of 2026-10-20)   # real repo, no rename; but app contains an in-app star prompt that can star via the user's gh CLI
forks: 6297 (as of 2026-10-20)
contributors: 453 (as of 2026-10-20; GitHub API incl. anonymous; ~6 core committers wrote ~98% of the last week's 1,474 commits)
primary_language: TypeScript
stack: "Electron 43, React 19, Zustand, Tailwind 4, Monaco, xterm.js 6 (WebGL), node-pty, Node 'orcad' daemon, node:sqlite caches, Claude Agent SDK, Codex app-server client, ACP client; mobile Expo 55 / React Native 0.83 + tweetnacl; relay on GCP (Cloud Run/GCE, Cloud SQL Postgres, Terraform); PostHog telemetry"
platforms: [macos, windows, linux, ios, android, web]   # web = browser client to a paired Orca server; Linux CLI is `orca-ide`
agent_engine: "wraps CLIs: PTY/TUI for any CLI plus status hooks; structured 'Chat UI' sessions via Claude Agent SDK, Codex app-server JSON-RPC, Pi JSONL RPC, ACP (Grok, OpenCode, OpenCode 2, OMP, Antigravity)"
engines_supported: [claude-code, codex, grok-build, opencode, pi, omp, cursor-cli, gemini-cli, github-copilot-cli, antigravity, amp, droid, kimi, kiro, qwen-code, goose, cline, aider, hermes-agent, openclaw, devin, any-cli]
model_access: "subscription logins of each CLI (Claude Max, ChatGPT/Codex, Grok, Cursor, Copilot...) with multi-account hot-swap; API keys via each CLI's config; local models only if the CLI supports them; no Orca credits"
execution_env: "user host by default; or SSH host, a self-hosted 'Remote Orca Server' (orca serve), or a BYO per-worktree cloud VM/container recipe (Vercel Sandbox, Fly, Modal, Docker); worktree = isolation, not a sandbox"
per_bot_computer: "partial; optional per-worktree disposable VM/container via repo recipe (experimental, BYO provider); no persistent per-agent computer"
persistent_bots: no   # agents are sessions in worktrees; no named personas or durable identities
memory: "none of its own; respects CLAUDE.md / AGENTS.md and agent hooks; cross-agent session-history index ('AI vault') for search/resume"
routines: "yes; `orca automations` cron/RRULE/preset schedules with shell precheck, missed-run grace, reuse-session, per-host scheduling"
group_chat: "partial; experimental orchestration Runs with coordinator inbox, tasks DAG, worker_done/heartbeat/question messages, @all/@codex group addresses, decision gates; Claude Agent Teams panes"
coding_workspace: "yes; worktree per task, Monaco editor, WebGL terminal splits, diff viewer with line annotations sent to agent, commit/push/PR/stacked PRs, GitHub/GitLab/Bitbucket/Linear/Jira"
browser_use: "yes; embedded Chromium per worktree, agent-drivable via `orca browser` CLI (snapshot/click/fill), Design Mode element grab"
computer_use: "yes (beta); `orca computer` accessibility-tree + screenshot control on macOS/Windows/Linux; iOS Simulator and Android emulator skills"
connectors: "native GitHub, GitLab, Bitbucket, Gitea, Azure DevOps, Linear (incl. MCP), Jira; MCP config inspection; Orca skills via `npx skills add`; plugins API"
channels: "none inbound; mobile push notifications (APNs/FCM) and desktop notifications only"
mobile: "yes; iOS App Store + Android APK companion (beta), pairs via Orca Relay or LAN/Tailscale; UI bundle served OTA from the desktop"
voice: "partial; dictation into prompts (local STT models or OpenAI transcription on desktop, mic dictation on mobile); no voice conversation"
approvals: "per-agent launch flags; default historically Yolo (bypass flags pre-filled), now Manual | Auto | Yolo selector (v1.4.232); Chat UI renders permission/question cards; answerable from phone"
e2e_encryption: "yes for mobile/remote RPC: Curve25519 ECDH + XSalsa20-Poly1305 (tweetnacl) over WebSocket via relay; open issues on pairing identity and reusable bearer tokens"
self_host: "yes; desktop is local-first, `orca serve` headless server; relay source is in repo (cloud/) but hosted relay/auth needs Orca account"
multi_user: "partial; one Remote Orca Server can be shared by several paired clients with per-client revocable tokens; no roles, no team workspace"
pricing: "free (MIT); user pays agent subscriptions/API; optional Orca account for Relay, artifact links and skill sharing; no paid tier found"
maturity: "beta/GA-ish: v1.4.x, ~99k stars, 4,053 PRs merged in 30 days; Chat UI, orchestration, Cloud VM and computer use flagged experimental/beta"
```

## What it is

Orca calls itself "The AI Orchestrator for 100x builders" that lets you "Run Codex, ClaudeCode, OpenCode or Pi side-by-side — each in its own worktree, tracked in one place" ([README](https://github.com/stablyai/orca#readme)). Its site positions it as an "Agent Development Environment (ADE)": "IDEs were built for you. An ADE is built for you and your agents: worktrees, terminals, browser, and CLI in one app" ([onorca.dev](https://www.onorca.dev/)). The GitHub repo description has drifted toward the Grok Bot vocabulary: "Orca is the place for working with a fleet of agents (e.g. Grok Bot, Claude Code). Run any coding agent with your own subscription. Available on desktop, mobile and remote runtime" ([GitHub API](https://api.github.com/repos/stablyai/orca)), but no Grok Bot-specific integration was found in source; "Grok" support means the xAI `grok` CLI ([supported agents](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/supported.mdx)).

Mental model: an IDE whose primary unit is the **workspace = git worktree + agent terminals + browser tabs + editor tabs**, listed in a sidebar grouped by project, with status (working / waiting / done) per worktree ([Worktrees docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/model/worktrees.mdx)). Agents are not bots with identities; they are processes of third-party CLIs that Orca launches and supervises. "Works with any CLI agent — if it runs in a terminal, it runs in Orca" ([README](https://github.com/stablyai/orca#readme)).

Target user: engineers running many coding agents at once on their own subscriptions; YC's listing describes "an ADE built for engineers who run 10 to 100 coding agents at once" (via [third-party Medium summary](https://medium.com/@gwrx2005/orca-pi-and-opencode-open-source-agentic-tools-and-the-changing-practice-of-software-development-e2a208d898ef), not verified on YC directly).

## Product and UX

- **Create a workspace**: dialog with Project, Run on (local / SSH / Remote Orca Server / cloud recipe), Agent, and a name field that can link a GitHub PR, Linear/Jira issue or GitLab MR; branch derived from the name or Linear's branch name. Creation (`git fetch` + `git worktree add`) runs in the background with progress in the sidebar ([Worktrees docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/model/worktrees.mdx)).
- **Worktree hygiene**: per-repo shared paths (APFS clone or symlink), `orca.yaml` `worktree.sharedDirectories` for gitignored trees like `node_modules`, `.worktreeinclude` to copy `.env` files; setup hooks such as `pnpm install` ([Worktrees docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/model/worktrees.mdx), [Hooks & memory](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/hooks-memory.mdx)). Sleep/hibernate worktrees, nested child worktrees from orchestration, bulk delete with preserved-branch review.
- **Parallel "race"**: the flagship recipe is manual: create three worktrees from the same ref, launch Claude Code / Codex / Cursor CLI, paste the same prompt, compare diffs, ship the winner, delete the losers ([Race three agents](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/recipes/parallel-agents.mdx)). The README's "Fan one prompt across five agents ... compare the results and merge the winner" ([README](https://github.com/stablyai/orca#readme)) is not a dedicated compare/merge tool; merging is via commit, push and PR from the winning worktree [INFERENCE from docs].
- **Review**: diff against the start-from ref; **Annotate AI Diff** pins Markdown comments to lines, then **Send to agent** composes one batched, line-anchored prompt and lets you choose which agent in the worktree gets it ([Annotate AI Diff](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/review/annotate-ai-diff.mdx)). Commit with AI-drafted message, push (force-with-lease only as an explicit action), create PR/MR (stacked PRs on GitHub, Bitbucket supported), **Fix with AI** on hook failures ([Commit & push](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/review/commit-push.mdx)). An "Attribution" view exists ([docs list](https://github.com/stablyai/orca/tree/main/docs/site/content/docs/review)).
- **Chat UI (experimental)**: a structured transcript + composer over supported agent sessions (Claude, Codex, Grok, OMP, later OpenCode 2, Antigravity), with model/effort pills, slash commands and skills, permission/question cards; "The terminal remains the source of truth" ([Chat UI docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/native-chat.mdx), [v1.4.232](https://github.com/stablyai/orca/releases/tag/v1.4.232)).
- **Design Mode**: toggle in the embedded browser toolbar, hover-highlight, click an element; Orca captures outer HTML plus neighborhood, curated computed CSS, a cropped PNG, and the source file/line when a dev source map exists, and "ships into the active agent terminal as one attachment" ([Design Mode docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/browser/design-mode.mdx)). Details under Architecture.
- **Accounts and usage**: status-bar account switcher showing Claude/Codex usage and rate-limit resets, hot-swap accounts without re-login, spend Codex reset credits ([README](https://github.com/stablyai/orca#readme), [Mobile docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/mobile.mdx)).
- **Orca CLI**: agents can drive Orca (`orca worktree create`, `terminal send`, browser `snapshot`/`click`/`fill`, `automations`, `orchestration`, `computer`) and Orca installs matching skills ([CLI skills](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/cli/skills.mdx)).
- **Star prompt**: after a user spawns 35 agents beyond a baseline, a card asks for a GitHub star; if `gh` is authenticated, one click stars `stablyai/orca` via `gh api -X PUT user/starred/stablyai/orca` ([`src/main/star-nag/service.ts`](https://github.com/stablyai/orca/blob/main/src/main/star-nag/service.ts), [`threshold-trigger.ts`](https://github.com/stablyai/orca/blob/main/src/main/star-nag/threshold-trigger.ts), [`orca-star.ts`](https://github.com/stablyai/orca/blob/main/src/main/github/client/fetch/orca-star.ts), [`constants.ts`](https://github.com/stablyai/orca/blob/main/src/shared/constants.ts) `STAR_NAG_INITIAL_THRESHOLD = 35`).

## Architecture

```
Electron desktop (React renderer, Monaco, xterm WebGL)
  |-- main process / orcad (Node daemon: PTYs, worktrees, runtime RPC, automations scheduler)
  |     |-- PTY lane: node-pty -> any agent CLI TUI; managed status hooks POST to local endpoint
  |     |-- structured lane: Claude Agent SDK | Codex app-server (JSON-RPC) | Pi --mode rpc (JSONL)
  |     |                    | ACP stdio (grok, opencode acp, omp acp, antigravity)
  |     |-- embedded Chromium tabs (Design Mode grab scripts, agent browser CLI bridge)
  |     |-- computer-use native helpers (macOS Swift, Windows, Linux)
  |     |-- ssh (remote worktrees, remote runtime upload)
  |-- runtime RPC server (port 6768 default) <--- E2EE WebSocket ---> phone / web / other desktops
  |                                       \--- outbound WSS ---> Orca Relay (director + cells, GCP) <--- phone
  |-- push gateway (APNs/FCM, Cloud Run)  <--- desktop authenticates with its X25519 key
```

- **Processes**: Electron app plus `orcad`, "Orca's own Node server", used by `orca serve`; on packaged macOS the desktop app's server is used instead ([Remote servers](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/remote-servers.mdx), [`src/main/orcad/main.ts`](https://github.com/stablyai/orca/blob/main/src/main/orcad/main.ts)). Terminal scrollback "survives restarts" ([README](https://github.com/stablyai/orca#readme)).
- **Stack**: Electron 43.7.8, React 19.2, Zustand 5, Tailwind 4, Monaco 0.55, `@xterm/xterm` 6.1 beta with WebGL addon, node-pty, `@anthropic-ai/claude-agent-sdk` 0.3.284, electron-updater, posthog-node ([`package.json`](https://github.com/stablyai/orca/blob/main/package.json)); mobile is Expo 55 / React Native 0.83 with tweetnacl ([`mobile/package.json`](https://github.com/stablyai/orca/blob/main/mobile/package.json)). Native helpers in Rust/Swift under `native/` (computer use, Windows agent hook, CLI launcher) ([repo tree](https://github.com/stablyai/orca/tree/main/native)).
- **How each engine is driven** (two lanes):
  - *PTY/TUI lane (all agents)*: "the agent combobox just launches a process in a terminal" with per-agent default args ([supported agents](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/supported.mdx)). Status comes from Orca-managed hooks installed into each agent's config (e.g. `src/main/grok/grok-hook-config.ts`, Pi/OMP status extensions in `src/main/pi/agent-status-extension-source.ts`, OpenCode 2 status plugin in `src/main/opencode2/status-plugin-setup-source.ts`); hook endpoints are written to `{userData}/agent-hooks/endpoint.env` and re-sourced each invocation so agents survive app restarts ([Hooks & memory](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/hooks-memory.mdx)). Transcripts are read back from each CLI's own session files by parsers in `src/main/ai-vault/session-scanner-*-parser.ts` (Claude, Codex, Grok, Hermes, Kimi, Kiro, Cursor, Devin, etc.) ([tree](https://github.com/stablyai/orca/tree/main/src/main/ai-vault)).
  - *Structured lane (Chat UI)*: Claude via the Claude Agent SDK with Orca supplying the child process (`spawnClaudeCodeProcess`) so it owns the pid and tree-kill ([`claude-agent-sdk-process-spawn.ts`](https://github.com/stablyai/orca/blob/main/src/main/claude/claude-agent-sdk-process-spawn.ts)); Codex via `codex app-server` JSON-RPC (`src/main/codex/codex-app-server-client.ts`, Codex >= 0.136.0 required for chats per [v1.4.227](https://github.com/stablyai/orca/releases/tag/v1.4.227)); Pi via `handleTransport: 'jsonl-rpc'` with `PI_CODING_AGENT_DIR` per account ([`rpc-agent-definition.ts`](https://github.com/stablyai/orca/blob/main/src/main/pi/rpc-agent-definition.ts)); ACP over stdio for `grok`, `opencode acp` (1.x in-process; 2.x spawns private `opencode serve --stdio`), `omp acp`, Antigravity, with per-agent "dialects" and `approvalEnforcement: 'orca'` ([`acp-launch-specs.ts`](https://github.com/stablyai/orca/blob/main/src/main/acp/acp-launch-specs.ts), [`acp-structured-agent-definitions.ts`](https://github.com/stablyai/orca/blob/main/src/main/acp/acp-structured-agent-definitions.ts)).
- **Models and auth**: no Orca model access; each CLI uses its own login. Multi-account is done by pointing each CLI at a different home dir (`CODEX_HOME`-style, `PI_CODING_AGENT_DIR`; Claude accounts "use separate folders" per [v1.4.227](https://github.com/stablyai/orca/releases/tag/v1.4.227)); `orca account add --agent claude|codex` ([CLI reference](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/cli/reference.mdx)).
- **Execution environment**: four modes: local, SSH target (git worktree and agents run remote, UI local), Remote Orca Server (server owns projects, worktrees, terminals and agents; clients are UI), and per-workspace Cloud VM recipes in `orca.yaml` that Orca runs as create/suspend/resume/destroy scripts against Vercel Sandbox, Fly, Modal, SSH or local Docker. "Orca does not sell managed VPS hosting" ([Ways to run](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/ways-to-run.mdx)).
- **State and storage**: local, under Electron userData; `node:sqlite`-based caches (`src/main/sqlite/`), JSON persistence (`src/main/persistence.ts`), secrets via Electron safeStorage / macOS Keychain (`src/main/host/electron-secret-store.ts`, `src/main/macos-keychain/`) ([tree](https://github.com/stablyai/orca/tree/main/src/main)). Conversation content stays in each CLI's native store; Orca indexes it.
- **Remote and mobile access**:
  - *Pairing*: desktop shows a one-time code / QR; phone pastes or scans; "Prefer Orca Relay ... sign-in is required for Relay only"; LAN or Tailscale direct paths on port 6768 also work; a versioned mobile protocol blocks mismatched versions ([Mobile docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/mobile.mdx)).
  - *Relay*: "Phones and desktops never talk to each other directly: each opens an outbound WebSocket to a relay cell, the relay pairs the two sessions, and it splices frames between them. A director assigns hosts to cells"; GCP deployment via Terraform, Postgres in prod; API and auth services are in private `stablyai/orca-cloud` ([`cloud/README.md`](https://github.com/stablyai/orca/blob/main/cloud/README.md)).
  - *Encryption*: mobile uses tweetnacl "Curve25519 ECDH key exchange and XSalsa20-Poly1305 authenticated encryption. JSON RPC uses base64([24-byte nonce][ciphertext]) over WebSocket text frames" ([`mobile/src/transport/e2ee.ts`](https://github.com/stablyai/orca/blob/main/mobile/src/transport/e2ee.ts)); an "e2ee-v2" host latch exists ([`direct-e2ee-framing-policy.ts`](https://github.com/stablyai/orca/blob/main/mobile/src/transport/direct-e2ee-framing-policy.ts)). Push: the desktop authenticates to the push gateway "with the same X25519 key it uses for the relay"; logs never contain tokens or notification bodies ([`cloud/README.md`](https://github.com/stablyai/orca/blob/main/cloud/README.md)).
  - *OTA mobile UI*: since Android v0.0.55 "The Orca app on your phone now gets most of its screens and features from the desktop it's paired with"; the phone downloads a web bundle from the desktop and runs it in a shell module ([mobile-android-v0.0.55](https://github.com/stablyai/orca/releases/tag/mobile-android-v0.0.55), `mobile/modules/orca-mobile-web-shell`, `src/shared/mobile-web-bundle`).
  - *Remote Orca Server*: access link per client with "a separate, revocable token for each paired client"; docs say "Do not forward the Orca port directly to the public internet" ([Remote servers](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/remote-servers.mdx)).
- **Design Mode internals**: guest-injected scripts (`src/main/browser/grab-guest-*.ts`) collect a `BrowserGrabPayload`: sanitized URL, viewport, tag, selector, element path, nearby elements, React component names read from `__reactFiber$` keys, `sourceFile`, text and HTML snippets, safe attributes, accessibility role/name, rects, 16 computed style properties and a PNG crop ([`src/shared/browser-grab-types.ts`](https://github.com/stablyai/orca/blob/main/src/shared/browser-grab-types.ts), [`grab-guest-react-script.ts`](https://github.com/stablyai/orca/blob/main/src/main/browser/grab-guest-react-script.ts)). The main process treats the payload as untrusted: re-clamps budgets, strips query strings/fragments from URLs, and drops secret-looking values ([`browser-grab-payload.ts`](https://github.com/stablyai/orca/blob/main/src/main/browser/browser-grab-payload.ts)).
- **Extension surface**: Orca skills installed into agents (`orca-cli`, `orchestration`, `computer-use`, `orca-linear`, `orca-jira`, `orca-emulator`, `orca-per-workspace-env`) as thin stubs whose full text is served by the version-matched CLI; skill bundles can be shared via revocable links with an Orca account ([CLI skills](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/cli/skills.mdx)); plugin API with examples (`examples/plugins/hello-orca`, `hostile-panel`) ([tree](https://github.com/stablyai/orca/tree/main/examples/plugins)); MCP config inspection UI (`src/shared/mcp-config.ts`); `orca.yaml` per-repo config.

## Capabilities in detail

- **Persistent bots and identity**: none. Agents are CLI sessions tied to worktrees; sessions can be hibernated and resumed, and Session History indexes conversations across all supported CLIs ([docs list](https://github.com/stablyai/orca/tree/main/docs/site/content/docs/agents)).
- **Memory**: defers to `CLAUDE.md` / `AGENTS.md` ("left alone — they belong to the agent") ([Hooks & memory](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/hooks-memory.mdx)). `src/main/memory/` is process RAM monitoring, not agent memory ([tree](https://github.com/stablyai/orca/tree/main/src/main/memory)).
- **Routines/automation**: `orca automations create --trigger hourly|daily|weekdays|weekly|<cron>|<RRULE> --time --timezone --prompt --provider --repo|--workspace|--project --host`, `--precheck "<shell>"` to skip runs cheaply, `--reuse-session` to continue in the same terminal, `--missed-run-grace-minutes`, `--extra-agent-args` limited to model/effort flags; an Automations page aggregates schedules across connected hosts; runs can be triggered manually and rerun ([Automations docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/cli/automations.mdx)). The docs' own example "Inbox digest ... Summarize unread mail" shows assistant-style use. Scheduling is per host, so unattended runs need an always-on host (Remote Orca Server) [INFERENCE from [Ways to run](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/ways-to-run.mdx)].
- **Multi-agent collaboration**: experimental Orchestration: a **Run** (namespace + coordinator inbox), **Tasks** with dependencies and statuses, **Dispatches** (one attempt on a terminal), supervised **workers** started in the current or a new child worktree with a chosen agent/model/effort, inbox **messages** (`worker_done`, `heartbeat`, `question`, `escalation`), group addresses (`@all`, `@idle`, `@claude`, `@codex`, `@worktree:<id>`), blocking `ask`, **decision gates**, and federated workers on other hosts (`--on windows`). Workers get an injected preamble ("Send `worker_done` exactly once, even on failure") ([Orchestration docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/cli/orchestration.mdx)). Claude Agent Teams can be launched with native panes per teammate ([supported agents](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/supported.mdx)). This is a coordinator-agent pattern driven by CLI calls, not a human-visible group chat.
- **Coding workspace**: worktrees, Monaco editor, file explorer with drag-to-prompt, Markdown/PDF/image viewers, notebooks, Ghostty-class terminal splits, diff viewer, GitHub/GitLab/Bitbucket/Gitea/Azure DevOps source-control integrations, Linear and Jira boards ([README](https://github.com/stablyai/orca#readme), [tree](https://github.com/stablyai/orca/tree/main/src/main)).
- **Browser use**: a real Chromium tab per worktree with profiles; agents drive it through `orca` CLI snapshot/click/fill; Design Mode for human-to-agent element context; HTML/Markdown can be published as public artifact links (opt-in, off by default) ([Browser overview](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/browser/overview.mdx), [Settings](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/settings.mdx)).
- **Computer use**: `orca computer list-apps | get-app-state | click --element-index | type | scroll | screenshot`, snapshot-act-snapshot loop over accessibility trees, beta, needs Accessibility and Screen Recording permissions ([Computer use](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/cli/computer-use.mdx)).
- **Connectors**: native code-host and tracker integrations listed above; no Composio-style SaaS connector catalog found.
- **Channels**: none (no Slack/Telegram/WhatsApp/email). Notifications go to desktop and to phones via APNs/FCM ([`cloud/README.md`](https://github.com/stablyai/orca/blob/main/cloud/README.md)).
- **Voice**: "Enable Voice Dictation" with microphone choice ([Settings](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/settings.mdx)); `src/main/speech/` contains a local STT model manager and an OpenAI transcription client ([tree](https://github.com/stablyai/orca/tree/main/src/main/speech)); mobile dictation in terminal and Chat UI ([Mobile docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/mobile.mdx)).
- **Mobile**: "a read-mostly view of running agents": status across all paired hosts, terminal scrollback, Chat UI with composer, attachments and dictation, Quick Commands, Source Control stage/commit, browser view (Web/Mobile), account switcher and usage, creating workspaces from GitHub/Linear/GitLab/branch, push notifications. "The mobile app is intentionally not a full editor — it's a remote control for the desktop you already have running" ([Mobile docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/mobile.mdx)).
- **Team features**: a shared Remote Orca Server with multiple paired clients and a "Hide other-client workspaces" filter ([Worktrees docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/model/worktrees.mdx)); no org accounts, roles or shared billing found.

## Security and trust model

- **Permissive defaults**: "For new launches, Orca pre-fills each supported CLI's permission-bypass flag — `--dangerously-skip-permissions` for Claude, `--dangerously-bypass-approvals-and-sandbox` for Codex, `--yolo` for Gemini / Cursor / ..." and "A worktree is an isolated checkout, not a security sandbox" ([supported agents](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/supported.mdx)). v1.4.232 (2026-10-20) adds a global **Manual | Auto | Yolo** selector where Auto lets Claude and Codex handle approvals ([v1.4.232](https://github.com/stablyai/orca/releases/tag/v1.4.232)). For ACP agents, Orca answers every permission request (`approvalEnforcement: 'orca'`) ([`acp-structured-agent-definitions.ts`](https://github.com/stablyai/orca/blob/main/src/main/acp/acp-structured-agent-definitions.ts)).
- **Sandboxing**: none by default; optional per-workspace VM/container only through BYO recipes ([Ways to run](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/ways-to-run.mdx)).
- **Network exposure**: runtime server (default port 6768) for direct/LAN/Tailscale pairing; docs warn against public port forwarding ([Remote servers](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/remote-servers.mdx)). Relay hosted by Stably on GCP; frames are E2E-encrypted with NaCl box ([`e2ee.ts`](https://github.com/stablyai/orca/blob/main/mobile/src/transport/e2ee.ts)).
- **Open security issues (filed 2026-08-30, open as of 2026-10-20)**: pairing QR value is persisted as the long-lived bearer token and not exchanged for a per-device credential, so a photographed QR stays usable; "The mobile RPC allowlist includes terminal input, filesystem mutation, Git operations, and authenticated external-service actions" ([#17398](https://github.com/stablyai/orca/issues/17398)); pairing links use the custom `orca://` scheme carrying bearer credentials, interceptable by another app registering the scheme ([#17397](https://github.com/stablyai/orca/issues/17397)); pairing shows no desktop name or key fingerprint and the phone contributes no persistent public key ([#17400](https://github.com/stablyai/orca/issues/17400)); Windows credential ACL hardening does not fail closed ([#17395](https://github.com/stablyai/orca/issues/17395)). The Android v0.0.55 notes say "Pairing links are more secure, and scanning a new code replaces an old pairing" ([release](https://github.com/stablyai/orca/releases/tag/mobile-android-v0.0.55)); whether these issues are fully addressed is unknown.
- **No SECURITY.md**: private vulnerability reporting is enabled but undocumented ([#25552](https://github.com/stablyai/orca/issues/25552), opened 2026-10-05); no published GitHub security advisories found (API returned none, 2026-10-20).
- **OTA code path** [INFERENCE]: because the phone executes a UI bundle served by the paired desktop ([mobile-android-v0.0.55](https://github.com/stablyai/orca/releases/tag/mobile-android-v0.0.55)), a compromised or spoofed host can ship arbitrary UI code to the phone shell; the impact depends on what native capabilities the shell exposes (not audited).
- **Secrets**: Electron safeStorage / macOS Keychain (`src/main/host/electron-secret-store.ts`, `safe-storage-availability.ts`); Design Mode strips URL query strings and secret-like attribute values ([`browser-grab-payload.ts`](https://github.com/stablyai/orca/blob/main/src/main/browser/browser-grab-payload.ts)).
- **Telemetry**: on by default in packaged builds, anonymous install ID, events to PostHog Cloud US; no prompts, paths, repo names or outputs; agent kinds and token counts are sent; opt-out in Settings or `DO_NOT_TRACK=1` / `ORCA_TELEMETRY_DISABLED=1` ([Telemetry docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/telemetry.mdx)). Note the telemetry page says "Orca has no account system", while Relay and artifacts require an Orca account ([Mobile docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/mobile.mdx), [Settings](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/settings.mdx)); the docs are inconsistent.

## Traction and momentum

- **GitHub (as of 2026-10-20)**: 98,742 stars, 6,297 forks, 154 watchers, 8,548 open issues+PRs, 453 contributors (API, anon included); repo created 2026-03-17T03:28Z with the first commit at 03:29Z, so no rename inflation; ~15,300 commits on `main` ([GitHub API](https://api.github.com/repos/stablyai/orca)).
- **Activity**: 1,474 commits 2026-10-13..2026-10-20, of which Neil (732), Jinwoo Hong (278), Brennan Benson (191), "OrcaWin" (153), Kelvin Amoaba (49), Jinjing (49); 4,053 PRs merged and 2,641 issues opened 2026-09-20..2026-10-20 ([GitHub search API](https://github.com/stablyai/orca/pulls?q=is%3Apr+is%3Amerged+merged%3A%3E%3D2026-09-20)). The volume per core committer suggests heavily agent-authored code [INFERENCE]; the repo also contains `docs/audits/` memory-retention audits typical of agent-driven maintenance ([tree](https://github.com/stablyai/orca/tree/main/docs/audits)).
- **Releases**: 979 releases total (364 stable desktop, 576 RCs, 39 Android); 21 stable desktop releases in the 30 days to 2026-10-20 ([releases](https://github.com/stablyai/orca/releases)). Release-asset downloads sum to ~118M across all releases (2026-10-20), with ~1.43M on v1.4.229 alone; these counts include auto-updater fetches, so they indicate a large installed base rather than unique users [INFERENCE].
- **Star growth and organic check**: third-party snapshots report "over 43,000 GitHub stars in about five months" around 2026-08-12 ([agenticbrew, third-party](https://www.agenticbrew.ai/tools/run/b23f6312-ccd5-40a6-b3c9-05f5933fd688)) and "67K+" roughly a month later ([agentconn, third-party](https://agentconn.com/agents/orca/)); stably.ai still shows a stale "Star 4.3k" badge ([stably.ai](https://www.stably.ai/)). We could not pull a stargazer timeline (the stargazers API returned 404 for every repo from this environment). Issue/PR volume, downloads and named public endorsements on the site ([onorca.dev](https://www.onorca.dev/)) point to real usage, but the in-app star prompt that stars through the user's `gh` CLI after 35 spawned agents ([`src/main/star-nag/`](https://github.com/stablyai/orca/tree/main/src/main/star-nag)) means the star count measures nudged users. It is not inflated by bots, but it should not be compared one-to-one with projects that never ask [INFERENCE].
- **Community**: Discord, X @orca_build, WeChat groups (group 11 full, group 12 open) and READMEs in 6 languages ([README](https://github.com/stablyai/orca#readme)).
- **Maker and business model**: site published by "Stably, Inc.", "Backed by Y Combinator" ([onorca.dev](https://www.onorca.dev/)); Stably's paid product is AI QA testing (plain-English tests turned into Playwright), and its homepage cross-promotes Orca with "Before you test, you build" ([stably.ai](https://www.stably.ai/)). Third-party sources say YC W22, founders Jinjing Liang (CEO) and Neil Parker, $500k disclosed funding (2022) ([Medium, third-party](https://medium.com/@gwrx2005/orca-pi-and-opencode-open-source-agentic-tools-and-the-changing-practice-of-software-development-e2a208d898ef), [aVenture, third-party](https://aventure.vc/companies/stably-ai-orca-san-francisco-ca-us)). Orca has no price, no paid tier and sells no hosting; the only Stably-hosted services are Relay, push, artifact links and skill sharing behind a free Orca account. Monetization plan: unknown. Orca likely works as top-of-funnel for Stably [INFERENCE].

## Strengths

- Widest engine coverage in the category (~40 CLIs) at near-zero adapter cost via the PTY lane, with deeper structured adapters only where they pay off (Claude SDK, Codex app-server, Pi RPC, ACP).
- Worktree lifecycle is unusually complete: background creation, shared gitignored dirs, `.worktreeinclude`, setup hooks, sleep/hibernate, nested children, preserved-branch review, external-worktree adoption.
- Review loop (line annotations batched into one prompt, choose the target agent, Fix with AI on hook failures) is tight and agent-agnostic.
- Design Mode payload is well designed: structured, budgeted, secret-scrubbed, React-component and source-map aware.
- Compute placement is flexible: local, SSH, always-on self-hosted server and per-workspace BYO VM, all behind one "Run on" picker, with mobile and automations on the same runtime.
- Mobile companion is real, E2E-encrypted, and avoids App Store lag by loading its UI from the paired desktop.
- MIT across desktop, mobile and relay; shipping velocity is extreme.

## Weaknesses and risks

- Not an assistant product: no persistent agent identities, no memory layer, no messaging channels, no non-coding connectors.
- Defaults to permission-bypass flags with no sandbox; "Auto" mode only arrived 2026-10-20 and only for Claude/Codex.
- Open mobile-pairing weaknesses (reusable bearer QR, custom-scheme credential links, no peer identity) and no SECURITY.md, on an RPC surface that includes terminal input and file mutation.
- Hosted Relay and push run on Stably's GCP account, and the API/auth services are closed (`stablyai/orca-cloud`), so self-hosters get direct/Tailscale only unless they stand up their own relay.
- The PTY-first design makes the Chat UI a transcript decoder over TUIs; parity is still "under active tuning" ([Chat UI docs](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/native-chat.mdx)).
- Sustainability and quality: about 4,000 merged PRs a month from a handful of committers, 8.5k open issues, and frequent compatibility notes between desktop, mobile and server versions; business model unclear.
- Star metric is nudged in-app, so it overstates traction relative to peers.

## Ideas worth taking for Memoshi

- **Two-lane engine adapter** (raw PTY for any CLI, structured SDK/JSON-RPC/ACP for top engines): broad coverage on day one, rich UI where it matters.
- **Hook endpoint file re-sourced on every hook call** (`endpoint.env`): long-lived agent processes survive app restarts without dead ports.
- **Per-account home-dir isolation** for subscription CLIs: enables multi-account hot-swap and usage meters without handling tokens.
- **Design Mode payload schema** (selector, HTML snippet, curated computed styles, a11y, React component, source file, crop, all budgeted and secret-scrubbed): copy for any "point at UI, tell the bot" feature.
- **Batched line-anchored review notes with a target-agent picker**: one revision pass instead of comment ping-pong.
- **Automation `--precheck` shell probe and missed-run grace**: cheap gating keeps scheduled agents from burning tokens on nothing.
- **Orchestration worker contract** (exactly-once `worker_done` with task+dispatch IDs, heartbeats, blocking `ask`, decision gates): a sound protocol for bot-to-bot handoff in Memoshi group work.
- **Phone UI served OTA by the desktop host**: keeps phone and host versions in lockstep; adopt only with signed bundles to close the host-to-phone code path.
- **Relay design** (outbound WSS from both sides, director + cells, NaCl box E2E, push gateway authenticated by the host key, no payloads in logs): good template. Avoid their pairing mistakes: use single-use tickets, per-device keys, fingerprints and verified app links.
- **Avoid**: bypass-permission defaults and the in-app star prompt.

## Open questions

- Have #17397/#17398/#17400 been fixed in code (the v0.0.55 notes hint at it)? Check `src/main/runtime/device-registry.ts` and `mobile/src/transport/pairing.ts` at HEAD.
- Does the hosted Relay cost anything at scale, and what does the private `orca-cloud` auth hold (accounts, device registry, metadata)? Ask the maintainers or read the Relay terms.
- Is the OTA mobile web bundle signed or integrity-checked beyond the E2E channel? Inspect `src/shared/mobile-web-bundle` and `mobile/modules/orca-mobile-web-shell`.
- Real active-user numbers: telemetry exists (PostHog) but no public DAU figure found.
- Monetization roadmap for Orca vs Stably's QA product: unknown; YC profile or founder posts may say.
- Why the repo description names Grok Bot: positioning only, or a planned integration? No code evidence found.

## Sources

1. https://github.com/stablyai/orca (README)
2. https://api.github.com/repos/stablyai/orca (GitHub API: stars, forks, created_at, description, topics; contributors and commits endpoints)
3. https://github.com/stablyai/orca/releases (releases incl. v1.4.232, v1.4.230, v1.4.229, v1.4.227, mobile-android-v0.0.55/0.0.57)
4. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/model/worktrees.mdx
5. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/ways-to-run.mdx
6. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/mobile.mdx
7. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/remote-servers.mdx
8. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/browser/design-mode.mdx
9. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/browser/overview.mdx
10. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/cli/automations.mdx
11. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/cli/orchestration.mdx
12. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/cli/skills.mdx
13. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/cli/computer-use.mdx
14. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/cli/reference.mdx
15. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/supported.mdx
16. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/native-chat.mdx
17. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/hooks-memory.mdx
18. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/review/annotate-ai-diff.mdx
19. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/review/commit-push.mdx
20. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/recipes/parallel-agents.mdx
21. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/settings.mdx
22. https://github.com/stablyai/orca/blob/main/docs/site/content/docs/telemetry.mdx
23. https://github.com/stablyai/orca/blob/main/cloud/README.md
24. https://github.com/stablyai/orca/blob/main/mobile/src/transport/e2ee.ts
25. https://github.com/stablyai/orca/blob/main/mobile/src/transport/direct-e2ee-framing-policy.ts
26. https://github.com/stablyai/orca/blob/main/src/shared/browser-grab-types.ts
27. https://github.com/stablyai/orca/blob/main/src/main/browser/browser-grab-payload.ts
28. https://github.com/stablyai/orca/blob/main/src/main/browser/grab-guest-react-script.ts
29. https://github.com/stablyai/orca/blob/main/src/main/acp/acp-launch-specs.ts
30. https://github.com/stablyai/orca/blob/main/src/main/acp/acp-structured-agent-definitions.ts
31. https://github.com/stablyai/orca/blob/main/src/main/pi/rpc-agent-definition.ts
32. https://github.com/stablyai/orca/blob/main/src/main/claude/claude-agent-sdk-process-spawn.ts
33. https://github.com/stablyai/orca/blob/main/src/main/orcad/main.ts
34. https://github.com/stablyai/orca/blob/main/src/main/star-nag/service.ts
35. https://github.com/stablyai/orca/blob/main/src/main/star-nag/threshold-trigger.ts
36. https://github.com/stablyai/orca/blob/main/src/main/github/client/fetch/orca-star.ts
37. https://github.com/stablyai/orca/blob/main/src/shared/constants.ts
38. https://github.com/stablyai/orca/blob/main/package.json
39. https://github.com/stablyai/orca/blob/main/mobile/package.json
40. https://github.com/stablyai/orca/issues/17397
41. https://github.com/stablyai/orca/issues/17398
42. https://github.com/stablyai/orca/issues/17400
43. https://github.com/stablyai/orca/issues/17395
44. https://github.com/stablyai/orca/issues/25552
45. https://www.onorca.dev/
46. https://www.stably.ai/
47. https://medium.com/@gwrx2005/orca-pi-and-opencode-open-source-agentic-tools-and-the-changing-practice-of-software-development-e2a208d898ef (third-party)
48. https://aventure.vc/companies/stably-ai-orca-san-francisco-ca-us (third-party)
49. https://www.agenticbrew.ai/tools/run/b23f6312-ccd5-40a6-b3c9-05f5933fd688 (third-party)
50. https://agentconn.com/agents/orca/ (third-party)
