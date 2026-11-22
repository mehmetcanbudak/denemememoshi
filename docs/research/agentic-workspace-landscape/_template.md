# <Product name>

> One-sentence positioning in your own words. Last verified: YYYY-MM-DD.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name:
slug:
category:            # closed-hosted-agents | oss-bot-roster-desktop | oss-self-hosted-platform | agent-workspace-ide | coding-harness | personal-assistant-gateway | other
maker:               # person / company
license:             # SPDX id, "proprietary", or "source-available (<terms>)"
repo:
website:
first_public:        # YYYY-MM-DD
latest_release:      # version, YYYY-MM-DD
release_cadence:     # e.g. "~3 releases/week"
stars:               # number (as of YYYY-MM-DD)
forks:
contributors:
primary_language:
stack:               # e.g. "Electron 43, React 19, Node harness server, SQLite"
platforms: []        # macos, windows, linux, ios, android, web, cli
agent_engine:        # own loop | wraps CLIs | embeds SDK  (+ names)
engines_supported: [] # e.g. claude-code, codex, grok-build, opencode, pi, gemini-cli, cursor-cli, raw-api
model_access:        # subscription logins | API keys | local models | vendor credits (list all)
execution_env:       # where the agent's tools run: user host | cloud VM | container | user-chosen sandbox
per_bot_computer:
persistent_bots:     # durable identities/personas
memory:              # mechanism, one line
routines:            # schedules / triggers / webhooks
group_chat:          # multi-bot rooms, bot-to-bot handoff
coding_workspace:    # files, diffs, terminal, git, worktrees
browser_use:
computer_use:
connectors:          # Composio / MCP / native / none
channels:            # Slack, Telegram, WhatsApp, iMessage, email, SMS, voice call...
mobile:
voice:
approvals:           # permission model, one line
e2e_encryption:
self_host:
multi_user:          # teams, shared bots, households
pricing:
maturity:            # alpha | beta | GA + one-line evidence
```

## What it is

Concept and mental model (contacts in a messenger? IDE? control plane?). Target user. What problem it claims to solve.

## Product and UX

Key screens and flows, onboarding, how a user creates a bot / starts work / reviews results. Note what feels distinctive.

## Architecture

- Components and processes (include a small diagram if the source shows one).
- Tech stack.
- Agent loop / harness: own loop or wrapped CLI/SDK; wire protocols (ACP, stream-JSON, Codex app-server JSON-RPC, MCP, HTTP+SSE, WebSocket).
- Models and providers; how auth works (subscription OAuth vs API keys vs local).
- Execution environment: local host, VM, container, sandbox provider.
- State and storage: where transcripts, memory, secrets live; sync model.
- Remote and mobile access: relay, tunnel, pairing, encryption.
- Extension surface: skills, plugins, MCP, connectors, APIs.

Cite file paths in the repo (`path/to/file.ts`) when describing internals.

## Capabilities in detail

Persistent bots and identity, memory, routines/automation, multi-bot collaboration, coding workspace, browser and computer use, connectors, channels, voice, mobile, team features. Only what is evidenced.

## Security and trust model

Permissions and approvals, sandboxing, secret storage, network exposure, encryption, telemetry. Known incidents or open security issues.

## Traction and momentum

Stars/forks/contributors (as-of date), release history, commit activity, community size, notable press. Business model and pricing.

## Strengths

## Weaknesses and risks

Technical, product, licensing, platform-lock, sustainability.

## Ideas worth taking for Memoshi

Concrete patterns, UX details, or architectural choices to adopt, adapt, or avoid. Each one line plus why.

## Open questions

What we could not verify and how one would find out.

## Sources

Numbered list of every URL used, primary sources first.
