# Multica

> A source-available, self-hostable issue tracker (Linear-style board) in which AI coding agents are first-class assignees: you assign an issue, @-mention, chat, or fire a cron/webhook "Autopilot", and a local daemon on your own machine runs one of 26 detected coding CLIs (Claude Code, Codex, Cursor, Copilot, Kimi, OpenCode, Grok, Pi, ...) and writes comments, status and results back to the issue. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Multica
slug: multica
category: oss-self-hosted-platform   # agent-native project management (issue board) rather than a messenger
maker: Index Labs (Hong Kong) Limited (team previously behind devv.ai)
license: "source-available (Multica License = Apache-2.0 + Part I conditions: no hosted/managed service for third parties - even free - and no embedding in a commercially distributed product without a commercial license; Multica logo/name/attribution in any derived UI must stay; producer may change license for contributions)"
repo: https://github.com/multica-ai/multica
website: https://www.multica.ai
first_public: 2026-01-16   # repo created 2026-01-13, v0.1.0 released 2026-01-16
latest_release: v0.6.3, 2026-10-16
release_cadence: "164 releases 2026-01-16..2026-10-16 (~4/week); ~daily on weekdays in Aug 2026, slowed to ~1.6/week since 2026-09-20 (7 releases)"
stars: 53266 (as of 2026-10-20)
forks: 6985 (as of 2026-10-20)
contributors: 346 logged-in, 350 incl. anonymous (as of 2026-10-20); one is the bot account multica-eve (489 commits, 491 merged PRs)
primary_language: Go
stack: "Go backend (Chi, sqlc, gorilla/websocket) + PostgreSQL 17 (pgcrypto, pg_trgm); Next.js 16 web; Electron desktop sharing web UI packages; Expo/React Native iOS app; Go CLI + daemon; Docker Compose / Helm"
platforms: [web, macos, windows, linux, cli, ios]   # iOS build-from-source only, not on App Store; no Android
agent_engine: "wraps CLIs: daemon spawns each tool as a child process per run (stream-json, Codex app-server JSON-RPC, ACP JSON-RPC over stdio, CLI JSON/NDJSON modes)"
engines_supported: [claude-code, codex, cursor-cli, copilot-cli, opencode, grok-build, kimi-cli, pi, oh-my-pi, hermes, openclaw, antigravity, qwen-code, kiro-cli, codebuddy, trae-cli, deepseek-harness, minimax-code, qoder, qoder-cn, codearts, deveco, reasonix, qwenpaw, zeroclaw, dim, muse]   # no gemini-cli; custom profiles reuse these protocol families
model_access: "whatever the local CLI is signed in with (subscription logins or API keys); Multica ships no model; custom runtime profiles for wrappers"
execution_env: "user host via local daemon (laptop, server, or container/VM you choose); runs are unsandboxed as the daemon's OS user; per-run workdir + git worktree from a bare repo cache; hosted 'Cloud Runtime' EC2 nodes exist in code (SaaS-only, feature-gated)"
per_bot_computer: "no; agents bind to a runtime (machine x CLI); many agents share a machine; per-run workdirs only. Cloud Runtime nodes are per-workspace fleet nodes, not per-agent"
persistent_bots: "yes; named agents with avatar, instructions, model, skills, runtime, Access scope; not long-running processes - each trigger is a run"
memory: "no dedicated memory store; continuity = issue thread + project resources + skills + CLI session resumption (session id stored per issue/chat); Codex native memory disabled per run by default"
routines: "Autopilots: multiple 5-field cron schedules with IANA timezone + signed/idempotent webhooks (GitHub/GitLab event filters); 'create issue' or 'run only' modes; auto-pause at 90% failure; plus agent-created issue wakeups (at/every/cron/event/until-PR-checks/until-children-done)"
group_chat: "partial; Squads: leader agent routes work by @-mentioning members (agents or humans) in issue comments, re-triggered on replies; no multi-bot chat room; external Slack/Lark/Telegram groups reach one bot per agent via @-mention"
coding_workspace: "partial; per-run git worktrees, GitHub/GitLab/Gitea/Forgejo PR linking (merged PR closes issue), execution log with tool calls, per-run cost; no in-app diff review, editor or terminal"
browser_use: "no built-in; only via MCP servers the user configures (daemon hardens browser MCP configs on Windows)"
computer_use: no
connectors: "MCP (Multica-managed per agent, merged with runtime-local servers), Composio-backed agent integrations, plugin SDK (sandboxed iframe surfaces, hooks), CLI + REST API, GitHub App"
channels: "Slack (Socket Mode), Feishu/Lark, DingTalk, WeCom, Telegram (last three community-maintained); one bot per agent; DMs + @-mention in groups; /issue, /new, /clear"
mobile: "partial; iPhone/iPad Expo app, build from source with your own signing, not on App Store; no Android"
voice: no   # WeCom voice messages rejected; Telegram audio passed only as file attachment
approvals: "none inside runs: CLIs run with bypassPermissions / danger-full-access and auto-answered prompts; human gate is the issue review status (agents move to in_review, humans mark done) plus per-agent Access scopes"
e2e_encryption: no   # TLS to server; channel credentials encrypted with a server key; custom_env stored plaintext in DB
self_host: "yes; Docker Compose, single binary, Helm chart; free for internal use within one organization; daily anonymous telemetry on by default (DO_NOT_TRACK=1)"
multi_user: "yes; workspaces, owner/admin/member roles, per-agent Access (only me / workspace / specific people), private vs public runtimes, shared skills, inbox, subscriptions"
pricing: "self-host free for internal use; Cloud Free and Pro plans billed per human seat via Stripe (agents never consume seats; price shown only at checkout, unknown publicly); credit balance for cloud billing in code; commercial/hosting licenses via sales"
maturity: "beta: pre-1.0 (v0.6.3), ~5,644 commits, 164 releases in 9 months, hosted cloud with paid tier live; large surface but fast churn"
```

## What it is

Multica calls itself "Agents that show up on the board": "a source-available workspace where you assign work to AI coding agents the way you'd assign it to a teammate - they pick up the issue, report progress, raise blockers, and hand it back for review" ([README](https://github.com/multica-ai/multica#readme)). The site's tagline is "Project Management for Human + Agent Teams" and "Your next 10 hires won't be human" ([multica.ai](https://www.multica.ai)).

Mental model: a Linear-like issue tracker (workspaces, projects, issues, statuses, comments, inbox) where the assignee picker lists humans, agents and squads side by side ([homepage](https://www.multica.ai)). The control plane (server) records and coordinates; connected computers execute: "Multica records and coordinates the work; connected computers execute it" ([How Multica works](https://multica.ai/docs/how-multica-works)). An agent "is not a long-running process; it executes only when triggered" ([Core concepts](https://multica.ai/docs/concepts)).

Target user: small software teams already running several coding CLIs who want one queue, audit trail and review gate across them. The README pitch: "You already run Claude Code, Codex, and three other agents. Each one lives in its own terminal tab, forgets everything when the session ends..." ([README](https://github.com/multica-ai/multica#what-is-multica)). The name is a backronym ("Multiplexed Information and Computing Agent") referencing Multics time-sharing; the stated bet is "two engineers and a fleet of agents can move like twenty" ([VISION.md](https://github.com/multica-ai/multica/blob/main/VISION.md)).

Maker: Index Labs (Hong Kong) Limited, named as "the producer" in the license ([LICENSE](https://github.com/multica-ai/multica/blob/main/LICENSE)); "a small team that has been working together since 2021. Before Multica, we built devv.ai, an AI search engine for developers" ([About](https://www.multica.ai/about)).

## Product and UX

- **Onboarding**: Cloud sign-up by email code; `multica setup` "walks you through OAuth, starts the daemon, and scans for the 26 supported coding tools" ([homepage](https://www.multica.ai)). Desktop (macOS/Windows/Linux) "connects the computer it runs on as a runtime automatically"; on the web you click **Add a computer** and paste two commands ([README](https://github.com/multica-ai/multica#your-first-agent-in-five-minutes)). Prerequisite: at least one agent CLI installed and signed in - "Multica drives them; it doesn't ship them" (same).
- **Create an agent**: name, avatar, instructions, up to three conversation starters, skills, runtime + model + thinking level, Access, concurrency, env vars, CLI args, MCP, integrations ([Agents](https://multica.ai/docs/agents)). **Build with AI** lets an "Agent Builder" interview you and draft the config; it needs an online runtime ([Create an agent](https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/agents-create.mdx)).
- **Assign an issue**: pick an agent or squad as assignee, then a confirmation dialog with **Start** or **Don't start yet**; Backlog never starts runs ([Assigning issues](https://multica.ai/docs/assigning-issues)). Four trigger types total: assignment, @-mention in a comment, direct chat, Autopilot - "Agents never start work on their own" ([How Multica works](https://multica.ai/docs/how-multica-works)).
- **Watching work**: issue header chip ("Engineer is working"), an **Execution log** in the issue sidebar with per-run transcript (messages, tool calls, errors, streaming live), stop and retry buttons ([Runs](https://multica.ai/docs/tasks)); per-run cost bars and token detail added in v0.6.3 ([release v0.6.3](https://github.com/multica-ai/multica/releases/tag/v0.6.3)).
- **Steering**: "Reply while it works and the message lands in the current run, not the next one. Claude Code, Codex, and Grok today" ([README](https://github.com/multica-ai/multica#stay-in-the-loop)); shipped as "steer a running agent from the normal composer, per recipient" in v0.6.0 ([release v0.6.0](https://github.com/multica-ai/multica/releases/tag/v0.6.0)).
- **Review gate**: agents mark issues in progress on start and "ready for review when they deliver"; "A run ending does not complete the issue by itself" ([Issues](https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/issues.mdx)). Merged linked PRs can move the issue to a workspace-chosen status (same).
- **Workflows**: per-project status columns with handoffs, so moving a card into a step can reassign it and start an agent with step instructions ([Workflows](https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/workflows.mdx)); shipped v0.6.3 ([release v0.6.3](https://github.com/multica-ai/multica/releases/tag/v0.6.3)).
- **Chat**: one-to-one private chats with an agent outside any issue, optional project context attached, each message one run, session resumed when possible ([Chat](https://multica.ai/docs/chat)).
- **Quick actions** (saved requests that don't change assignee/status), **issue deliverables and dynamic blocks** (HTML/Mermaid frames, CSV/JSON viewers) ([release v0.6.0](https://github.com/multica-ai/multica/releases/tag/v0.6.0)), **Inbox** for humans only - "Agents do not use the inbox" ([Core concepts](https://multica.ai/docs/concepts)).
- **Runtimes dashboard**: per-machine list of detected CLIs with online status and CLI version, usage charts (input/output/cache tokens), activity heatmap, daily cost ([homepage](https://www.multica.ai), [Daemon and runtimes](https://multica.ai/docs/daemon-runtimes)).
- Distinctive: the agent is an ordinary teammate in a familiar PM tool (same assignee dropdown, same activity timeline), rather than a chat contact; the issue is the unit of memory and audit.

## Architecture

```
   Web (browser)        Desktop (Electron)        iPhone/iPad (Expo)
         |                      |                          |
     Next.js 16  ---HTTPS+WebSocket---------------------------+
         v                      v                          v
   Go backend (Chi + WebSocket, sqlc) ----> PostgreSQL 17
         |  tasks.claim RPC + wakeup hints over WebSocket; HTTP poll backstop; 15 s heartbeat
   Agent daemon (Go, `multica daemon`) on your machine
         |  spawns per run, in per-run worktree under ~/multica_workspaces/
   claude -p stream-json | codex app-server (JSON-RPC) | kimi/grok/hermes ACP | cursor-agent stream-json | opencode run --format json | ...
         |  agent calls back with `multica issue comment add ...` using run-scoped MULTICA_TOKEN
```
(Adapted from the [README architecture diagram](https://github.com/multica-ai/multica#architecture).)

- **Components**: Go API/WebSocket server (`server/cmd/server`), the `multica` CLI that also hosts the daemon (`server/cmd/multica/cmd_daemon.go`), daemon internals in `server/internal/daemon/` (claim, reconcile, GC, repo cache, skill cache, MCP merge), per-CLI backends in `server/pkg/agent/`, daemon WebSocket hub in `server/internal/daemonws/`, scheduler in `server/internal/scheduler/` ([repo tree](https://github.com/multica-ai/multica/tree/main/server)).
- **Stack**: Next.js 16, Electron, Expo/React Native, Go (Chi, sqlc, gorilla/websocket), PostgreSQL 17 with `pgcrypto` + `pg_trgm`; dev prerequisites Node 22, pnpm 10.28.2, Go 1.26.9 ([README](https://github.com/multica-ai/multica#architecture)).
- **Dispatch**: when a run is queued "the server notifies the matching daemon; the daemon also polls periodically as a backstop"; heartbeat every 15 s, offline within ~3 min; default concurrency 20 runs per daemon, 6 per agent ([Daemon and runtimes](https://multica.ai/docs/daemon-runtimes)). The WebSocket control connection carries `tasks.claim` RPC responses of up to 32 task payloads each ([`server/internal/daemon/wakeup.go`](https://github.com/multica-ai/multica/blob/main/server/internal/daemon/wakeup.go)). A runtime = one computer x one CLI (or custom profile), registered per workspace (same docs).
- **Wire protocols per CLI** (from `server/pkg/agent/`):
  - Claude Code: `claude -p --output-format stream-json --input-format stream-json`, stdin kept open for follow-ups ([`claude.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/claude.go)); the same stream-json backend serves CodeBuddy and Qwen.
  - Codex: `codex app-server` JSON-RPC with handshake/turn timeouts and a "semantic inactivity" stall detector ([`codex.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/codex.go)).
  - Cursor: `cursor-agent -p --output-format stream-json` ([`cursor.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/cursor.go)).
  - Copilot CLI: `copilot -p <prompt> --output-format json --allow-all --no-ask-user`, ACP mode explicitly blocked ([`copilot.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/copilot.go)).
  - Kimi (`kimi acp`), Hermes (`hermes acp`), Grok (`grok agent stdio`, plus xAI's ACP interjection extension for steering): ACP JSON-RPC 2.0 over stdio ([`kimi.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/kimi.go), [`hermes.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/hermes.go), [`grok.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/grok.go)).
  - OpenCode: `opencode run --format json --dangerously-skip-permissions`, with a separate v2 adapter because OpenCode 2.0 removed `--dir`/`--variant` and made `run` a thin client of a resident service; v2 runs with MCP are refused ([`opencode.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/opencode.go), [`opencode_v2.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/opencode_v2.go)).
  - OpenClaw: `--json --session-id` NDJSON ([`openclaw.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/openclaw.go)); Pi and Oh-My-Pi share a "pi JSON event protocol" backend, with new forks added as descriptor entries ([`builtin_runtimes.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/builtin_runtimes.go)).
  - Protocol-critical flags (`-p`, `--output-format`, `--permission-mode`, ...) are stripped from user args; custom runtime profiles must pick an existing "protocol family" ([Daemon and runtimes](https://multica.ai/docs/daemon-runtimes)).
- **How agents report back**: the daemon builds a prompt telling the CLI to run `multica issue get <id> --output json`, scan threads with `multica issue comment list ...`, and post results with `multica issue comment add ... --content-file ./reply.md`; the same CLI handles chat history, attachments, issue creation and wakeups ([`server/internal/daemon/prompt.go`](https://github.com/multica-ai/multica/blob/main/server/internal/daemon/prompt.go)). The daemon injects `MULTICA_TOKEN` (task-scoped `mat_` credential, max 24 h), `MULTICA_TASK_ID`, `MULTICA_AGENT_ID`, `MULTICA_WORKSPACE_ID`, `MULTICA_SERVER_URL`; writes are attributed to the agent and run ([Daemon and runtimes](https://multica.ai/docs/daemon-runtimes)). "Agents drive Multica through the same CLI you do" ([README](https://github.com/multica-ai/multica#make-it-yours)).
- **Models and auth**: no model shipped; model list is discovered from each CLI (e.g. `omp models --json`, `dsh --list-models`) and the CLI's own login (subscription or API key) is used ([Providers](https://multica.ai/docs/providers)). Daemon authenticates with a PAT obtained via `multica login`/setup OAuth ([homepage](https://www.multica.ai)).
- **Execution environment**: the CLI runs as a child process with "the full permissions of the operating-system user running the daemon"; per-run workdir under `~/multica_workspaces/`, per-run `CODEX_HOME`/`HERMES_HOME` ([Security model](https://multica.ai/docs/security-model)). Repos come from bare clone caches "used as the source for creating per-task worktrees" ([`repocache/cache.go`](https://github.com/multica-ai/multica/blob/main/server/internal/daemon/repocache/cache.go)). Optional hosted **Cloud Runtime** nodes: the server proxies to a private `multica-cloud` service that provisions EC2 instances (instance type, region, AMI, subnet, key pair) bootstrapped via SSM with a node-scoped PAT, exposed only on the web SaaS ([`handler/cloud_runtime.go`](https://github.com/multica-ai/multica/blob/main/server/internal/handler/cloud_runtime.go), [`runtimes.json`](https://github.com/multica-ai/multica/blob/main/packages/views/locales/en/runtimes.json), [`runtimes-page.tsx`](https://github.com/multica-ai/multica/blob/main/packages/views/runtimes/components/runtimes-page.tsx)).
- **State and storage**: server stores issues, comments, agent config, skills, run records/transcripts and results; local machine keeps CLI credentials, code and file changes ([How Multica works](https://multica.ai/docs/how-multica-works)). Exception: agent `custom_env` and MCP config are stored server-side - "`custom_env` values are stored in plaintext in the Multica server database" ([Create an agent](https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/agents-create.mdx)). Runtime-local MCP servers are merged on the daemon "so runtime URLs, headers, commands, and env values never need to leave the machine" ([`runtime_mcp.go`](https://github.com/multica-ai/multica/blob/main/server/internal/daemon/runtime_mcp.go)).
- **Remote and mobile access**: all clients talk to the central server over HTTPS + WebSocket; no relay/tunnel to the daemon is needed because the daemon dials out ([README](https://github.com/multica-ai/multica#architecture)). iOS app is build-from-source ([Mobile app](https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/mobile-app.mdx)).
- **Extension surface**: skills (SKILL.md bundles injected into each CLI's native skill dir, e.g. `.claude/skills/`, `$CODEX_HOME/skills/`) ([Providers](https://multica.ai/docs/providers)); Multica-managed MCP per agent; Composio-backed integrations (`server/internal/integrations/composio/`, [`server/pkg/composio/README.md`](https://github.com/multica-ai/multica/blob/main/server/pkg/composio/README.md)); a plugin SDK where UI "surfaces" run as a single script in a `sandbox="allow-scripts"` iframe with server-side storage, manifest-declared `net:` scopes and immutable published versions ([`packages/plugin-sdk/README.md`](https://github.com/multica-ai/multica/blob/main/packages/plugin-sdk/README.md)); examples in `examples/plugins/` (deploy-sentinel, schedule-pulse, triage-notify, ...); full CLI and REST API ([CLI docs](https://multica.ai/docs/cli)); a separate [multica-cli skill](https://github.com/multica-ai/multica-cli) lets Codex/Claude Code/Cursor drive Multica.

## Capabilities in detail

- **Persistent bots and identity**: agents are durable named identities with avatar, description, instructions, skills, model and runtime; switching model or instructions keeps history ([Agents](https://multica.ai/docs/agents)). Agents can create issues, comment and change status, but "have no inbox and don't receive `@all`" (same). Archive cancels all unfinished runs (same).
- **Memory**: no agent memory store. Context comes from the issue (description, threads), project resources (repos, docs), skills and native CLI session resumption - "Multica stores the session identifier the tool returns. The next time work continues on the same issue, the runtime tries to resume that session" ([Providers](https://multica.ai/docs/providers)). Codex native memory is disabled per run unless `MULTICA_CODEX_MEMORY` is set, "to keep host or previous-task memories from crossing workspace boundaries" ([`execenv/codex_memory.go`](https://github.com/multica-ai/multica/blob/main/server/internal/daemon/execenv/codex_memory.go)). Skills are pitched as compounding team memory: "One person's skill is every agent's skill" ([homepage](https://www.multica.ai)).
- **Routines - Autopilots**: Runbook + assignee (agent or squad) + triggers; modes **Create issue** (queued like any issue, waits for an offline runtime) or **Run only** (skipped if runtime offline, no auto-retry); multiple schedules per autopilot with a schedule editor or raw 5-field cron + IANA timezone; webhook triggers with unique tokenized URL, 256 KiB JSON limit, `Idempotency-Key` and `X-GitHub-Delivery` dedup, optional signing secret, event/action filters, replay; auto-pause when the past 7 days have >= 50 runs at 90% failure ([Autopilots](https://multica.ai/docs/autopilots)). Cloud plans gate autopilot quota through a private policy endpoint; self-host "retain[s] the unlimited paths" ([`entitlement/README.md`](https://github.com/multica-ai/multica/blob/main/server/internal/entitlement/README.md)).
- **Routines - Issue wakeups** (v0.6.0 "issue wakeup v2 - conditions, runaway protection, check-ins"): an agent or member saves a timer, cron, event subscription or condition on an issue; the agent finishes and later gets "another ordinary run when the input arrives... There is no sleeping process"; e.g. `--until-pr checks --expires-in 2h`, `--until-children-done --stage 1`, `--kind event --event task.completed` ([`docs/engineering/issue-wakeups.md`](https://github.com/multica-ai/multica/blob/main/docs/engineering/issue-wakeups.md), [release v0.6.0](https://github.com/multica-ai/multica/releases/tag/v0.6.0)).
- **Multi-bot collaboration - Squads**: one leader agent plus agent and human members with role descriptions. Assigning to a squad enqueues a run for the leader only; the leader gets a system-managed "Squad Operating Protocol", roster with exact mention links (`[@Name](mention://agent/<uuid>)`) and squad instructions; it posts one delegation comment that @-mentions members (each mention triggers a run), records its evaluation via `multica squad activity`, and stops. It is re-triggered on most later comments (not on explicit @-routing or its own comments, with dedup) and moves the parent to `in_review` when done; `done` is left to humans ([Squads](https://multica.ai/docs/squads)). "Squads... don't merge multiple agents into a new agent, and they don't automatically raise concurrency" (same).
- **Human-agent collaboration**: humans and agents share the assignee picker, comment threads and a unified activity timeline ([homepage](https://www.multica.ai)); @-mention an agent in a comment for a one-off without changing ownership ([Mentioning agents](https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/mentioning-agents.mdx)); agents report blockers (`agent_blocked` failure reason, "Provide what its comment asked for") ([Runs](https://multica.ai/docs/tasks)).
- **Reliability**: run states `deferred/queued/dispatched/waiting_local_directory/running/completed/failed/cancelled`; transient failures auto-retry (2 attempts, 3 for network); typed failure reasons including `provider_quota_limit`, `context_overflow`; no fixed run duration cap ([Runs](https://multica.ai/docs/tasks)).
- **Coding workspace**: per-run worktrees, project-attached repos, GitHub/GitLab/Gitea/Forgejo integration ([README](https://github.com/multica-ai/multica#make-it-yours)); "one verdict per PR in the issue sidebar" ([release v0.6.0](https://github.com/multica-ai/multica/releases/tag/v0.6.0)). No in-app editor, terminal or line-level diff review found [INFERENCE from docs list and release notes].
- **Browser and computer use**: none built in; browser access only through user-configured MCP servers ([`browser_mcp_config.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/browser_mcp_config.go)).
- **Channels**: Slack (Socket Mode), Feishu/Lark (new connections mainland-China only), DingTalk, WeCom, Telegram; each bot bound to one agent; DMs and @-mention in groups; `/issue`, `/new`, `/clear`; sender must bind their platform account to a workspace membership; per-chat/thread session isolation ([Channels](https://multica.ai/docs/channels)).
- **Voice**: none; WeCom voice messages get an "unsupported" reply; Telegram audio is passed as a file attachment ([Channels](https://multica.ai/docs/channels)).
- **Mobile**: iPhone/iPad Expo app "not on the App Store yet", build from source; "no Android client yet" ([Mobile app](https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/mobile-app.mdx)).
- **Team features**: workspaces, `owner`/`admin`/`member` roles, email invitations; per-agent Access ("Only me" default, "Entire workspace", "Specific people") that admins "cannot bypass" ([Members and roles](https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/members-roles.mdx), [Agents](https://multica.ai/docs/agents)); runtimes private by default - "the runtime is someone else's computer, and running an agent there spends their machine and their tool credentials"; owners can make a runtime public, and revoking cancels teammates' runs ([Daemon and runtimes](https://multica.ai/docs/daemon-runtimes)); private one-to-one chats invisible even to admins ([Chat](https://multica.ai/docs/chat)); docs in en/zh/ja/ko/fr.

## Security and trust model

- **No sandbox, by design**: "By default a run executes with the full permissions of the operating-system user running the daemon... Multica makes no filesystem-sandbox guarantee"; "If the daemon runs as your personal user account, a run can read your SSH keys, edit your shell profile, and delete your documents" ([Security model](https://multica.ai/docs/security-model)). Recommended boundary: dedicated Unix user, container, or VM (same).
- **Approvals auto-answered**: "Multica runs agents unattended, so approval prompts are answered automatically... Codex runs with `sandbox_mode = "danger-full-access"` and Claude Code with `--permission-mode bypassPermissions`"; a previous Linux `workspace-write` sandbox for Codex was removed because it broke host CLIs and "never prevented a run from reading and exfiltrating credentials" ([Security model](https://multica.ai/docs/security-model)).
- **Run-scoped tokens**: `MULTICA_TOKEN` bound to agent + run, max 24 h, but inherited by every child process ([Daemon and runtimes](https://multica.ai/docs/daemon-runtimes)).
- **Secrets**: CLI credentials stay on the machine; agent `custom_env` and MCP config are server-side, plaintext in the DB, readable only by owners/admins with audit records ([Create an agent](https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/agents-create.mdx)). Chat-platform credentials require a per-platform 32-byte encryption key on self-host ([Channels](https://multica.ai/docs/channels)). Webhook URLs embed a bearer token, hidden by default, rotatable ([Autopilots](https://multica.ai/docs/autopilots)).
- **Plugins**: opaque-origin sandboxed iframes with generated CSP and consent screen per immutable version ([plugin SDK](https://github.com/multica-ai/multica/blob/main/packages/plugin-sdk/README.md)).
- **Telemetry**: self-hosted servers send one anonymous daily snapshot to a compiled-in endpoint `https://telemetry.multica.ai/v1/telemetry/events`, enabled by default; separate PostHog analytics toggle ([SELF_HOSTING.md](https://github.com/multica-ai/multica/blob/main/SELF_HOSTING.md)).
- **Vulnerability handling**: no `SECURITY.md` in the repo and zero published GitHub security advisories (GitHub API, as of 2026-10-20). Issue [#1382](https://github.com/multica-ai/multica/issues/1382) ("Can I submit a security vulnerability I found? ... where can I submit it?") has been open since 2026-04-20. Other open security issues: [#1667](https://github.com/multica-ai/multica/issues/1667) (Origin header not validated on state-changing requests, CSRF defense-in-depth gap, v0.2.16), [#2554](https://github.com/multica-ai/multica/issues/2554) (daemon bare repo cache may inherit embedded credentials in `remote.origin.url`), [#7118](https://github.com/multica-ai/multica/issues/7118) (Windows binaries not code-signed). Recent fixes touch authorization boundaries: "restrict notifications to current workspace recipients", "revoke workspace WebSocket access" ([release v0.6.3](https://github.com/multica-ai/multica/releases/tag/v0.6.3)), "refuse an inbound turn from a member who may not run the agent" ([release v0.6.0](https://github.com/multica-ai/multica/releases/tag/v0.6.0)).
- **Install path**: self-host and CLI install via `curl ... install.sh | bash` ([README](https://github.com/multica-ai/multica#get-started)).
- **Cost runaway**: open bug [#9167](https://github.com/multica-ai/multica/issues/9167) reports "Infinite retries of the same session after task failure (16 times in 16 minutes) burn tokens without backoff" (v0.6.1, Windows, OpenCode).

## Traction and momentum

- **GitHub** (as of 2026-10-20): 53,266 stars, 6,985 forks, 184 watchers, 1,869 open issues+PRs (1,024 open issues), 3,934 merged PRs, ~5,644 commits on `main`, 346 logged-in contributors (350 with anonymous) ([GitHub API](https://api.github.com/repos/multica-ai/multica)). Created 2026-01-13, so ~53k stars in nine months; no rename signal (first release three days after creation). Star timeline could not be sampled (stargazer API returned 404) - unknown whether growth was organic or spiky.
- **Contributor concentration**: top four humans hold ~4,260 commits (Bohan-J 1,540, forrestchang 1,124, NevilleQingNY 1,096, ldnvnbl 503); the bot account `multica-eve` has 489 commits and authored 491 merged PRs - the team dogfoods Multica agents on its own repo (commits are co-authored by `multica-agent`) ([contributors API](https://api.github.com/repos/multica-ai/multica/contributors), [LICENSE commit history](https://github.com/multica-ai/multica/commits/main/LICENSE)).
- **Releases**: 164 releases from v0.1.0 (2026-01-16) to v0.6.3 (2026-10-16); "We release most weekdays" ([README](https://github.com/multica-ai/multica#development)); 22 releases between 2026-08-11 and 2026-09-15, then 7 since 2026-09-20 as minor versions got larger (v0.6.0 workflows, wakeups v2, steering) ([releases](https://github.com/multica-ai/multica/releases)). 263 commits since 2026-09-20.
- **Community**: Discord, X `@MulticaAI` / `@multica_hq`, docs in five languages ([README](https://github.com/multica-ai/multica)). Third-party directories list it (e.g. whichcoding.tools, tulsk.io comparison - third-party, discovery only).
- **Business model**: hosted Cloud with **Free** and **Pro** plans billed per human seat through Stripe Checkout - "Agents never use a seat"; the price is shown only in Stripe ("Stripe Checkout shows the authoritative per-seat price"); usage limits per month (issue count, autopilot quota) come from a private Cloud policy service ([`billing.json`](https://github.com/multica-ai/multica/blob/main/packages/views/locales/en/billing.json), [`entitlement/README.md`](https://github.com/multica-ai/multica/blob/main/server/internal/entitlement/README.md)). Code also contains a credits balance/top-up flow for `multica-cloud` billing (test page) and Cloud Runtime nodes. Homepage CTAs: "Start free trial", "Talk to sales" ([homepage](https://www.multica.ai)). Revenue levers in the license: commercial hosting/embedding licenses and branding waivers ([licensing FAQ](https://www.multica.ai/licensing)). Public price: unknown.

## Strengths

- Clearest "agents as teammates" model for software teams: reuses the familiar issue/assignee/review mental model instead of inventing a new chat UI; every run is tied to an issue with transcript, cost and status ([Runs](https://multica.ai/docs/tasks)).
- Broadest CLI coverage in the category (26 runtimes, four protocol families) with detailed per-tool hardening (Codex stall detection, OpenCode v2 contract changes, ACP interjection for Grok steering) ([`server/pkg/agent/`](https://github.com/multica-ai/multica/tree/main/server/pkg/agent)).
- Thoughtful scheduling: Autopilots with idempotent, filterable webhooks and failure auto-pause, plus agent-authored conditional wakeups (until PR checks pass, until children done) without sleeping processes ([Autopilots](https://multica.ai/docs/autopilots), [issue-wakeups.md](https://github.com/multica-ai/multica/blob/main/docs/engineering/issue-wakeups.md)).
- Real multi-user design: per-agent Access, private-by-default runtimes (protects a teammate's machine and subscription), role model, private chats.
- Daemon dials out to the server, so laptops behind NAT work with no tunnel; code and CLI credentials never leave the machine (except `custom_env`/MCP config).
- Unusually honest security docs ("Multica does not pretend to be the boundary").
- Very high velocity and documentation quality; self-host via Compose or Helm.

## Weaknesses and risks

- **License trap**: not OSI open source. Anyone offering Multica (or a substantial part) to users outside their own organization needs a commercial license "even when it is offered free of charge"; a fork can be published but "each operator must obtain its own commercial license"; derived UIs must keep Multica branding; contributors grant the producer the right to change the license "to be more strict or relaxed" ([LICENSE](https://github.com/multica-ai/multica/blob/main/LICENSE)). The license tightened repeatedly: Apache-2.0 on 2026-04-01, modified Apache with commercial restrictions on 2026-04-08, branding condition widened to "all UI code" on 2026-07-30, free public hosting explicitly restricted on 2026-08-03 ([LICENSE history](https://github.com/multica-ai/multica/commits/main/LICENSE)).

  Exact restricting terms, Part I of the [LICENSE](https://github.com/multica-ai/multica/blob/main/LICENSE) (verbatim, as of 2026-10-20):

  > a. Hosted or embedded service: Unless you have obtained a commercial license from the producer, you may not use the Multica source code to provide a hosted service to third parties, or embed Multica as a component of a product or service that is sold, licensed, or otherwise commercially distributed to third parties.
  > - This restriction applies to offering Multica (in whole or substantial part) as a SaaS platform, a managed service, or as an integrated component within another commercial offering.
  > - Providing a hosted service to third parties is restricted whether or not you charge for it. A publicly accessible instance operated for users outside your own organization requires a commercial license even when it is offered free of charge, carries no advertising, and sells no paid tier.
  > - Internal use within a single organization (including multiple workspaces) does not require a commercial license.
  >
  > b. Branding and copyright information: Unless the producer has granted you a written branding waiver, you may not remove or modify the Multica LOGO, the Multica product name, or the copyright and attribution information displayed by a Multica user interface. [...] user interface code remains covered when it is modified, moved, renamed, or extracted into another package or repository.
  >
  > c. Attribution for non-interface use: If you redistribute or operate a product or service built on Multica's backend, daemon, or CLI without a Multica user interface, you must [...] state in your user-facing documentation that the product is built on Multica, including a link to https://github.com/multica-ai/multica.
  >
  > 2. Contributions: By submitting a contribution to Multica, you agree that: a. The producer can adjust this Multica License to be more strict or relaxed as deemed necessary. b. Your contributed code may be used for commercial purposes, including but not limited to its cloud business operations.

  The licensing FAQ adds that people outside your organization driving your instance "through another entry point" such as "a public website backed by Multica, a Slack integration, or an API - even when it is free" requires a license ([licensing FAQ](https://www.multica.ai/licensing)). There is no separate "competing product" clause; the hosted-service and embedding clauses cover that case. GitHub reports the license as `NOASSERTION` ([GitHub API](https://api.github.com/repos/multica-ai/multica)).

- **Coding-only scope**: everything is framed around coding CLIs, repos and PRs; no browser/computer use, no voice, no personal-assistant surfaces (email, calendar), memory is issue-scoped.
- **No sandbox and no approvals inside runs**: all CLIs run with permissions bypassed as the daemon user; safety relies on the user creating a separate OS user/container/VM ([Security model](https://multica.ai/docs/security-model)).
- **Security process gaps**: no SECURITY.md or advisories; a public "where do I report a vulnerability" issue open six months; secrets in `custom_env` plaintext in the DB.
- **Bring-your-own CLI burden**: every runtime machine must install and sign in each CLI; hosted Cloud Runtime is SaaS-only and gated.
- **Churn**: pre-1.0 with weekday releases; protocol adapters must track upstream CLI changes (OpenCode 2.0 broke flags; Copilot usage events disappeared) ([`opencode_v2.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/opencode_v2.go), [`copilot.go`](https://github.com/multica-ai/multica/blob/main/server/pkg/agent/copilot.go)); 1,000+ open issues.
- **Mobile weak**: iOS build-from-source only, no Android.
- **Regional skew**: many integrations target Chinese platforms (Feishu, DingTalk, WeCom, Huawei CodeArts/DevEco, Qoder CN) [INFERENCE: team and market partly China-focused]; new Lark connections limited to mainland-China Feishu ([Channels](https://multica.ai/docs/channels)).

## Ideas worth taking for Memoshi

- **Run as a first-class object separate from the task/conversation** (one issue, many runs; typed states; failure reasons; retries) - gives auditability and clean retry semantics.
- **Agents report through a CLI with a run-scoped token** (`multica issue comment add`) instead of parsing final output - works uniformly across any engine and attributes writes to the agent.
- **Outbound-dialing daemon with WebSocket wakeup + poll backstop + heartbeat** - avoids tunnels for user-owned machines; copy the "queued runs wait for an offline runtime with grace" rule.
- **Private-by-default runtimes and per-agent Access** - essential once bots run on someone's personal subscription; adopt for shared/household bots.
- **Wakeups as data, not sleeping processes** (timer, cron, event, condition like "until PR checks pass") that create ordinary runs - a good model for Memoshi routines and bot self-scheduling.
- **Webhook triggers with idempotency keys, event filters, replay and failure-rate auto-pause** - cheap robustness for automations.
- **Squad leader protocol**: router agent that only delegates via @-mentions and stops, with loop guards (no self-trigger, dedup queued runs) - reusable for Memoshi group chats.
- **Skills injected into each engine's native skill directory** per run, never overwriting repo skills - engine-agnostic skill sharing.
- **Avoid** unsandboxed bypass-permissions as the only mode for a consumer product; Memoshi needs a per-bot computer or container by default.
- **Avoid** building on Multica code: its license forbids offering it as a hosted service to third parties and embedding it in a distributed commercial product without a deal.

## Open questions

- Cloud Pro per-seat price and Free-tier limits: only visible at Stripe Checkout; check by creating a Cloud workspace and starting an upgrade.
- Cloud Runtime availability and pricing (EC2 nodes, credits): gated on the SaaS; confirm via the Runtimes page on multica.ai or sales.
- Whether commercial licenses have been granted to any hosting providers, and their price: ask via contact-sales.
- Star-growth shape (organic vs. campaign): stargazer API failed; use star-history.com or GH Archive.
- How the hosted service isolates tenant data and whether it has had incidents: no status page or security page found; ask maintainers or watch Discord.
- Whether the 2026-04-01..04-08 Apache-2.0-only window gives a cleanly forkable snapshot: legal review needed [INFERENCE].

## Sources

1. https://github.com/multica-ai/multica (README, repo tree)
2. https://github.com/multica-ai/multica/blob/main/LICENSE
3. https://github.com/multica-ai/multica/commits/main/LICENSE
4. https://api.github.com/repos/multica-ai/multica (stats, releases, contributors; queried 2026-10-20)
5. https://github.com/multica-ai/multica/releases (v0.1.0..v0.6.3)
6. https://github.com/multica-ai/multica/releases/tag/v0.6.3
7. https://github.com/multica-ai/multica/releases/tag/v0.6.0
8. https://github.com/multica-ai/multica/blob/main/VISION.md
9. https://github.com/multica-ai/multica/blob/main/SELF_HOSTING.md
10. https://multica.ai/docs/how-multica-works
11. https://multica.ai/docs/concepts
12. https://multica.ai/docs/agents
13. https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/agents-create.mdx
14. https://multica.ai/docs/assigning-issues
15. https://multica.ai/docs/squads
16. https://multica.ai/docs/autopilots
17. https://multica.ai/docs/daemon-runtimes
18. https://multica.ai/docs/security-model
19. https://multica.ai/docs/providers
20. https://multica.ai/docs/tasks
21. https://multica.ai/docs/chat
22. https://multica.ai/docs/channels
23. https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/workflows.mdx
24. https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/issues.mdx
25. https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/members-roles.mdx
26. https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/mobile-app.mdx
27. https://github.com/multica-ai/multica/blob/main/apps/docs/content/docs/mentioning-agents.mdx
28. https://github.com/multica-ai/multica/blob/main/docs/engineering/issue-wakeups.md
29. https://github.com/multica-ai/multica/blob/main/server/internal/daemon/prompt.go
30. https://github.com/multica-ai/multica/blob/main/server/internal/daemon/wakeup.go
31. https://github.com/multica-ai/multica/blob/main/server/internal/daemon/runtime_mcp.go
32. https://github.com/multica-ai/multica/blob/main/server/internal/daemon/repocache/cache.go
33. https://github.com/multica-ai/multica/blob/main/server/internal/daemon/execenv/codex_memory.go
34. https://github.com/multica-ai/multica/blob/main/server/pkg/agent/builtin_runtimes.go
35. https://github.com/multica-ai/multica/blob/main/server/pkg/agent/claude.go
36. https://github.com/multica-ai/multica/blob/main/server/pkg/agent/codex.go
37. https://github.com/multica-ai/multica/blob/main/server/pkg/agent/cursor.go
38. https://github.com/multica-ai/multica/blob/main/server/pkg/agent/copilot.go
39. https://github.com/multica-ai/multica/blob/main/server/pkg/agent/kimi.go
40. https://github.com/multica-ai/multica/blob/main/server/pkg/agent/hermes.go
41. https://github.com/multica-ai/multica/blob/main/server/pkg/agent/grok.go
42. https://github.com/multica-ai/multica/blob/main/server/pkg/agent/opencode.go
43. https://github.com/multica-ai/multica/blob/main/server/pkg/agent/opencode_v2.go
44. https://github.com/multica-ai/multica/blob/main/server/pkg/agent/openclaw.go
45. https://github.com/multica-ai/multica/blob/main/server/pkg/agent/browser_mcp_config.go
46. https://github.com/multica-ai/multica/blob/main/server/internal/handler/cloud_runtime.go
47. https://github.com/multica-ai/multica/blob/main/packages/views/runtimes/components/runtimes-page.tsx
48. https://github.com/multica-ai/multica/blob/main/packages/views/locales/en/runtimes.json
49. https://github.com/multica-ai/multica/blob/main/packages/views/locales/en/billing.json
50. https://github.com/multica-ai/multica/blob/main/server/internal/entitlement/README.md
51. https://github.com/multica-ai/multica/blob/main/server/pkg/composio/README.md
52. https://github.com/multica-ai/multica/blob/main/packages/plugin-sdk/README.md
53. https://www.multica.ai (homepage)
54. https://www.multica.ai/licensing
55. https://www.multica.ai/about
56. https://github.com/multica-ai/multica/issues/1382
57. https://github.com/multica-ai/multica/issues/1667
58. https://github.com/multica-ai/multica/issues/2554
59. https://github.com/multica-ai/multica/issues/7118
60. https://github.com/multica-ai/multica/issues/9167
61. https://github.com/multica-ai/multica-cli
62. https://whichcoding.tools/tools/multica and https://tulsk.io/compare/multica (third-party, discovery only)
