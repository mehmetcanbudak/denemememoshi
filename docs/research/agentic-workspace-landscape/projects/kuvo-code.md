# Kuvo Code

> A native SwiftUI macOS shell around an unmodified, pinned opencode 2.x server, adding PR-style review, a side panel with files/terminal/browser, SSH remote machines, and "bots" (persistent single-job agents with memory, self-scheduled wake-ups, model-free watches and group chats). Last verified: 2026-10-20.

> **2026-10-23 D91 amendment — current reuse policy.** [D91](../../../plan/decisions.md#d91) supersedes the historical no-source/no-fork/observer separation policy below; it does not change the upstream licence.
> - All participants, including builders, may inspect [Kuvo's GitHub source](https://github.com/serhatandic/kuvo-code) and copy/adapt code for this personal/noncommercial project under applicable terms. No separate observer or paid legal appointment is required before authorized source/reference or personal-use work.
> - [P0-19](../../../plan/phase-0.md#tickets) is a source-informed reference/reuse assessment, not gated by P0-22: record actual shared-screen/state observations, tokens/motion and named upstream revision/paths or observed runtime provenance; assess frontend reuse viability without assumed savings. Unknown Draft 3 values remain provisional until checked.
> - Reused code retains PolyForm Noncommercial 1.0.0 terms and required notices; record revision, paths, changes and licence coverage, checking third-party terms individually. There is no automatic Apache-2.0 relicensing, and replacing the engine or splitting modules does not remove retained-code obligations or resolve compatibility. Applicable rights and GPL-linked iSH compatibility must be resolved before public/commercial redistribution; the pre-public-release review remains.
> - Inspection, selective reuse and a personal fork are permitted options, not a selected or implemented fork, import, frontend replacement or architecture cutover. Keep Memoshi's Pi_Swift/Pi Durable, protocol, policy, recovery and device contracts. Following the [Viticci-guided review](../../2026-10-23-design-direction-review.md), [D92](../../../plan/decisions.md#d92) replaces blanket Kuvo visual parity with a Viticci-led assistant/Kuvo-informed workbench family; [D93](../../../plan/decisions.md#d93) removes mandatory design contracting, not design QA. Existing working layouts and feature/date stages remain.
> - Branding stays original. Screenshots, artwork, media and private material stay outside both repos; source permission is not permission to copy Kuvo art or other products' assets.
>
> **Evidence boundary:** this amendment imports no code, adds no runtime validation and does not claim an earlier audit read implementation. The dated observations and matrix licence facts below remain unchanged; any new source evidence must identify its own revision and paths.

> **Historical observer material ([D43](../../../plan/decisions.md#d43), [D55](../../../plan/decisions.md#d55); 2026-10-22 methodology, reuse policy superseded by D91 on 2026-10-23).** That version retained facts from Kuvo's public website, docs, README, CHANGELOG, licence files and GitHub metadata. The following two instructions are historical, not current requirements:
> - Builders implement from the plan, the specs and the clean-room parity spec.
> - Kuvo's repository and any Kuvo fork stay out of a builder's context.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Kuvo Code
slug: kuvo-code
category: agent-workspace-ide        # coding-first, with a bot roster (overlaps oss-bot-roster-desktop)
maker: Serhat Andıç (solo developer; GitHub profile lists Microsoft as employer), brand "Kuvo" (kuvo.run)
license: "source-available (PolyForm-Noncommercial-1.0.0; commercial use needs a separate paid license; CLA lets owner relicense)"
repo: https://github.com/serhatandic/kuvo-code
website: https://www.kuvo.run/code/
first_public: 2026-10-13   # repo created and v0.1.0 released that day
latest_release: v0.5.22, 2026-10-19
release_cadence: "~4 releases/day (29 releases 2026-10-13..2026-10-19)"
stars: 64 (as of 2026-10-20)
forks: 7 (as of 2026-10-20)
contributors: 1 (as of 2026-10-20; 2 open external PRs for a Windows port)
primary_language: Swift
stack: "SwiftUI + AppKit (Liquid Glass), Textual, UsageKit, SwiftTerm, WebKit panel browser, Sparkle updates; TypeScript agents bridge run on the engine's Bun; opencode 2.0.32 server"
platforms: [macos]   # Apple silicon, macOS 26+; remote engine on Linux x64/arm64 over SSH
agent_engine: "embeds opencode as a private HTTP+SSE server; plus a bridge that wraps Claude Agent SDK, Codex app-server, Cursor SDK, ACP (Grok, Antigravity) - bridge is Unreleased on main"
engines_supported: [opencode, claude-code, codex, cursor-cli, grok-build, antigravity]   # all but opencode are Unreleased on main as of 2026-10-20
model_access: "subscription logins via opencode (GitHub Copilot, ChatGPT, SuperGrok, GitLab Duo, Poe, OpenCode), API keys for any opencode provider, custom OpenAI/Anthropic-compatible endpoints, free OpenCode Zen models without account"
execution_env: "user host (Mac) or user's own Linux server over SSH; git worktrees for isolation; no container/VM sandbox"
per_bot_computer: "no; each bot gets its own folder and on Mac its own browser tabs; can live on a remote Linux machine"
persistent_bots: "yes; name, generated avatar, personality, model, one job, one long-lived engine session"
memory: "per-bot memory file with its job, read at start of work"
routines: "bot self-scheduled wake-ups (once or repeating, DST-aware); model-free scheduled shell 'watches' that wake bot on output change; scheduled group-chat meetings"
group_chat: "yes; turn-taking group chats with a lead who sums up and assigns parts; bot-to-bot and session-to-session messaging"
coding_workspace: "yes; projects with multiple folders, git Changes tab with line comments, commit/PR creation, worktrees with N parallel attempts, terminals, file tree, undo/fork from message"
browser_use: "yes; WebKit panel browser on Mac, headless Chrome for Testing on remote machines; browser-use style numbered-element tools; credential fill without model seeing passwords"
computer_use: no
connectors: "MCP (opencode), curated integrations: official remote MCP, token/app MCP, pinned OSS MCP servers, or 'in the browser' for Discord/Telegram/WhatsApp/X/LinkedIn/Reddit; skills; slash commands"
channels: "macOS notifications with inline reply/approve; no inbound messaging channels"
mobile: no   # as of 2026-10-20
voice: no (unknown; not found in the public docs)
approvals: "opencode permission rules (allow/ask/deny per tool and pattern, blocks win); per-session Approve All vs Ask First; answerable from notifications"
e2e_encryption: "partial; remote engines reached through SSH tunnel"
self_host: "yes; everything local; remote engine on your own Linux box; no Kuvo account or cloud"
multi_user: no   # single-user desktop; bots shareable as export files only
pricing: "free for personal/noncommercial use; commercial use needs paid license (price unknown); user pays model providers"
maturity: "alpha/early beta: pre-1.0 (0.5.x), first public release 2026-10-13, single developer"
```

## What it is

Kuvo Code positions itself as "a native macOS harness for coding agents that works with any model", whose engine is opencode, unmodified; Kuvo Code is "the interface, written in SwiftUI" ([README](https://github.com/serhatandic/kuvo-code#readme)). The marketing page has moved beyond pure coding: its headline is "Bots that keep the build green" and it describes "Coding agents and bots for your Mac, on any model" ([kuvo.run/code](https://www.kuvo.run/code/)).

Mental model: an IDE-like window (sidebar of bots, group chats, chats and projects; conversation in the middle; tabbed side panel on the right) ([Sessions docs](https://www.kuvo.run/code/docs/sessions/)), plus a roster of bots that behave like teammates in a messenger, each with a face, one job, a memory and an alarm clock ([Bots docs](https://www.kuvo.run/code/docs/bots/)).

Target user: individual developers on Apple-silicon Macs who already pay for Copilot/ChatGPT/SuperGrok or have API keys and want a native (non-Electron) front-end over opencode; the ready-made bots also aim at personal-assistant jobs (day planning, inbox, mentions, news digest) ([llms.txt](https://www.kuvo.run/llms.txt)).

## Product and UX

- **Onboarding**: download DMG, first launch downloads and verifies the opencode engine, connect an account with Shift-Cmd-K or pick a model marked Free (from OpenCode Zen), open a folder with Cmd-O ([Getting started](https://www.kuvo.run/code/docs/)). If you already use opencode, Kuvo Code keeps its own sessions and accounts; Settings > General > Bring Over imports keys, MCP servers, agents, commands, plugins and skills ([Settings docs](https://www.kuvo.run/code/docs/settings/)).
- **Sessions**: per-project sessions with status glyphs (drawing `>_` = working, orange hand = waiting for you, red = failed, dot = finished unseen); steering vs queueing messages (Return injects at next step, Cmd-Return queues); Build/Plan modes; per-message model + effort; context ring with Summarize Now; Undo From Here (reverts conversation and git-tracked files) and New Session From Here (fork) ([Sessions docs](https://www.kuvo.run/code/docs/sessions/)).
- **Review like a PR**: Changes tab reads git directly (Uncommitted/Unstaged/Staged/Since main/This Session); folded unchanged lines; image before/after; hover a line number, click +, write a comment; comments ride along with the next message and render as cards. Commit with model-suggested message; Create Pull Request (GitHub/GitLab) with model-written title/body; worktree sessions can Merge into main, and Ask the Agent to Fix It resolves conflicts ([Changes docs](https://www.kuvo.run/code/docs/changes/)).
- **Worktrees and attempts**: a new session can run in a git worktree on its own branch (`kuvo/` prefix), with a per-project setup command; "Attempts" spawns N worktrees for the same task to compare ([Sessions docs](https://www.kuvo.run/code/docs/sessions/#worktrees)).
- **Side panel**: per-conversation tabs for Changes, Files (highlighted code, rendered Markdown, Quick Look), Terminal (login shell; SwiftTerm), Run (project run command), and a WebKit browser with keychain-backed password saving ([Panel docs](https://www.kuvo.run/code/docs/panel/)).
- **Agent browsing**: agent opens pages in the visible panel browser; Take Over / Hand Back; sign-in cards fill credentials directly into the page so "the agent and the model never see them" ([Browsing docs](https://www.kuvo.run/code/docs/browsing/)).
- **Generative UI**: agents can render live charts, diagrams, small apps or clickable choices inline in the conversation ([Sessions docs](https://www.kuvo.run/code/docs/sessions/#the-transcript)).
- **Usage menu bar item**: plan limits, pace, reset times and spend for Copilot, ChatGPT (Codex), SuperGrok, OpenCode, OpenRouter, Z.ai; a fork of OpenUsage ([Usage docs](https://www.kuvo.run/code/docs/usage/)).
- **Bots UX** (distinctive): animated avatars encode state; site imagery shows bots "Working", "Has news", "Wakes in 2 hours" (asleep), "Watching", "Needs you" ([kuvo.run/code](https://www.kuvo.run/code/)). Docs: "it bounces while it works, hops and glows when it needs you, cheers when it has news for you, sleeps until its next wake-up, and keeps a lookout while it watches something" ([Bots docs](https://www.kuvo.run/code/docs/bots/#working-with-a-bot)). A new bot speaks first ("What's my purpose?"); your answer becomes its job. Nine templates: Keeper, Tally, Sage, Lookout, Lens, Herald, Compass, Courier, Echo; nine personality presets (Skeptic, Mentor, ...) ([kuvo.run/code](https://www.kuvo.run/code/), [llms.txt](https://www.kuvo.run/llms.txt)).

## Architecture

```
Kuvo Code.app (SwiftUI/AppKit)
  |-- HTTP client + SSE event stream ---> opencode 2.0.32 `serve --stdio --port 0` (private, random password)
  |-- browser tool server on 127.0.0.1 (new port+token per launch) <--- engine's browser tools
  |-- agents bridge (on engine's Bun) ---> Claude Agent SDK / Codex app-server / Cursor SDK / ACP (Grok, Antigravity)  [Unreleased]
  |-- ssh tunnel ---> remote Linux: ~/.kuvo-code/{engine, browser(Chrome for Testing), kuvo-browser.js}
  `-- UsageKit (OpenUsage fork) menu bar item
```

- **Stack**: Swift, SwiftUI and AppKit with Liquid Glass, "No Electron, and no web view for the interface" ([kuvo.run/code](https://www.kuvo.run/code/)); built with Textual, SwiftUIMath, SwiftTerm, Prism, browser-use's page reader, Chromium, OpenUsage, Sparkle, KeyboardShortcuts ([How it works](https://www.kuvo.run/code/docs/architecture/)). Requires Xcode 27 to build ([README](https://github.com/serhatandic/kuvo-code#build-from-source)).
- **How it drives opencode (the "unmodified" claim)**:
  - Pinned version: 2.0.32, the version the app is written against ([README](https://github.com/serhatandic/kuvo-code#how-it-works), [CHANGELOG](https://github.com/serhatandic/kuvo-code/blob/main/CHANGELOG.md)). So it targets opencode **v2**, not v1.
  - Download on first launch, checked against its checksum and code signature; Linux builds (x64, arm64) are checked on the Mac before upload ([README](https://github.com/serhatandic/kuvo-code#how-it-works)). Kept at `~/Library/Application Support/run.kuvo.code/engine`; resumable download added in 0.5.22 ([CHANGELOG](https://github.com/serhatandic/kuvo-code/blob/main/CHANGELOG.md)).
  - Launch: `opencode serve --stdio --port 0` with a random password; it exits when the app does ([README](https://github.com/serhatandic/kuvo-code#how-it-works)).
  - Wire protocol: opencode 2.x HTTP API plus an SSE event stream for live transcripts ([README](https://github.com/serhatandic/kuvo-code#how-it-works)).
  - Separation from a user's own opencode: data, sessions, accounts and settings in `~/Library/Application Support/run.kuvo.code/opencode`; a small plugin in the engine's `plugins` folder gives agent-run commands the user's real `~/.config` etc. back so `gh` finds its login ([README](https://github.com/serhatandic/kuvo-code#how-it-works), [Getting started](https://www.kuvo.run/code/docs/)).
  - "Unmodified" holds for the binary; Kuvo extends behavior through opencode's own extension points (plugin, config file, MCP-style tool servers) [INFERENCE from the above].
- **Outside agents bridge (Unreleased on `main` as of 2026-10-20)**: `Agents/` TypeScript server run by the engine's Bun drives Claude Code via the Claude Agent SDK and the user's `claude`, Codex via app-server, Cursor via its SDK, Grok and Antigravity via ACP, and "answers the app in the engine's own API"; sessions can hand over between agents; "Auto" falls through a user-ordered model list when one hits its usage limit ([README](https://github.com/serhatandic/kuvo-code#how-it-works), [CHANGELOG Unreleased](https://github.com/serhatandic/kuvo-code/blob/main/CHANGELOG.md)).
- **Models and auth**: opencode's provider list; subscription OAuth (GitHub Copilot, ChatGPT, SuperGrok; Unreleased adds GitLab Duo, Poe, OpenCode under Subscriptions), API keys, custom OpenAI/Anthropic-compatible providers, free OpenCode Zen models ([Accounts docs](https://www.kuvo.run/code/docs/accounts/), [CHANGELOG](https://github.com/serhatandic/kuvo-code/blob/main/CHANGELOG.md)). The current site says Claude subscriptions are not supported ("Anthropic's models take an API key") ([llms.txt](https://www.kuvo.run/llms.txt)); the Unreleased Claude Code bridge changes this by running the user's own `claude` login.
- **Execution environment**: agent tools run directly on the Mac in the project folder, or on a user's Linux box (x86-64/ARM64, not Alpine) reached with SSH keys; the engine binds localhost only there and is reached via SSH tunnel; it outlives the connection and stops after a day without the app unless a bot wake-up or watch is pending ([Machines docs](https://www.kuvo.run/code/docs/machines/)). Isolation is git worktrees, not containers. The sibling product Kuvo Box documents giving agents a container instead ([llms.txt](https://www.kuvo.run/llms.txt)).
- **State and storage**: everything under `~/Library/Application Support/run.kuvo.code` (engine, sessions, accounts, bots' memory/wake-ups/watches, group chats, personalities, browser history); integration keys and saved passwords in the macOS Keychain; remote state in `~/.kuvo-code`; settings/keys pushed to remote engines in owner-only files deleted at stop, "never in its environment" ([Privacy docs](https://www.kuvo.run/code/docs/privacy/), [Integrations docs](https://www.kuvo.run/code/docs/integrations/), [CHANGELOG 0.5.18](https://github.com/serhatandic/kuvo-code/blob/main/CHANGELOG.md)). No cloud sync and no Kuvo account.
- **Remote**: SSH tunnels to machines.
- **Extension surface**: opencode agents (modes/subagents, import from `~/.claude/agents`), permission rules, MCP servers (popular list from the official MCP Registry, Code Mode for big servers), skills (`~/.claude/skills`, `~/.agents/skills`, GitHub skill collections), slash commands (import from `~/.claude/commands`), engine plugins; a project's `opencode.json` / `.opencode` wins ([Customize docs](https://www.kuvo.run/code/docs/customize/)).

## Capabilities in detail

**Bots (what a bot is).** "A bot is an agent with a name, a look and one job. It keeps one conversation, remembers what it learns, and can wake itself up later to carry on" ([Bots docs](https://www.kuvo.run/code/docs/bots/)). So a bot = persistent agent identity + single long-lived opencode session + memory file + self-scheduled timers + watchers. It is not a separate runtime; it is an opencode session with extra instructions and tools [INFERENCE].
- Folder per bot; it works there or in one of your projects ([Bots docs](https://www.kuvo.run/code/docs/bots/#make-a-bot)).
- Placement: This Mac (works while awake, prevents idle sleep) or a remote machine (keeps working and waking while the Mac is off; Ask First steps wait until you open the app) ([Bots docs](https://www.kuvo.run/code/docs/bots/#make-a-bot)).
- Per-bot integration keys (e.g. a GitHub token only that bot can use); export/import bots as files (without memory or wake-ups); delete moves folder to Trash ([Bots docs](https://www.kuvo.run/code/docs/bots/#memory-and-wake-ups)). 0.5.17 hardened import against hidden jobs injected via line breaks in a shared bot's name ([CHANGELOG](https://github.com/serhatandic/kuvo-code/blob/main/CHANGELOG.md)).

**Triggers and schedules.**
- Wake-ups: the bot schedules a wake-up holding a note; when due, the note arrives in its conversation. Repeats keep their time of day and weekday across DST and travel. On the Mac the app fires them (missed ones fire on next open); on a machine the engine does ([Bots docs](https://www.kuvo.run/code/docs/bots/#memory-and-wake-ups)).
- Watches: "Kuvo Code runs a quick check for it on a schedule, without its model, and wakes it only when what the check prints is still different a couple of minutes later"; failed curl/wget/gh runs and timeouts don't count; Check Now previews ([Bots docs](https://www.kuvo.run/code/docs/bots/#memory-and-wake-ups)). This is a cheap, model-free polling trigger.
- Group-chat meetings on a schedule (e.g. weekdays at 9), only while the app is open ([Bots docs](https://www.kuvo.run/code/docs/bots/#group-chats)).
- No webhooks or inbound event triggers found (unknown).

**Multi-bot collaboration.** Group chats: bots talk one at a time. Lead speaks first unless @-mentioned; bots with nothing new stay quiet; Keep Going after many turns; lead writes a wrap-up assigning parts with dependencies; Start the Work sends each part to the bot's own conversation, reports return to the chat; in-chat bots can look things up but not change files ([Bots docs](https://www.kuvo.run/code/docs/bots/#group-chats)). Agent mail: any session or bot can see the others and send one a message (optionally waiting for the reply), across Mac and machines ([Bots docs](https://www.kuvo.run/code/docs/bots/#working-with-a-bot)).

**Coding workspace.** Projects of multiple folders, worktrees, attempts, Changes/commit/PR, terminal, Run, file tree, `@` mentions, `!` shell commands, subagents with their own panel tab and composer (Unreleased), background-command bar ([Sessions docs](https://www.kuvo.run/code/docs/sessions/), [CHANGELOG](https://github.com/serhatandic/kuvo-code/blob/main/CHANGELOG.md)).

**Browser.** Mac: WebKit panel browser, tools served by the app on 127.0.0.1 with per-launch port and token; numbered-element page reading from browser-use; tools for click/type/select/scroll/keys/history/screenshots/PDF/tabs/hover/wait/uploads; bots browse in their own tabs. Remote: headless Chrome for Testing plus Rocky Linux 8 libraries in `~/.kuvo-code/browser`, driven over a pipe by `kuvo-browser.js`, streamed live to the panel ([Browsing docs](https://www.kuvo.run/code/docs/browsing/), [README](https://github.com/serhatandic/kuvo-code#how-it-works)). No desktop computer use.

**Connectors.** Settings > Integrations groups mail/calendar, chat, social, code/work. Connection kinds: official remote server; official with your token or your registered app; pinned open-source MCP server run with Node or the engine's Bun; or "In the browser" where "there's no server worth trusting" ([Integrations docs](https://www.kuvo.run/code/docs/integrations/)). The catalog includes Apple Calendar and Reminders, Outlook, Gmail, Slack, Discord, Telegram, WhatsApp, X, LinkedIn, Reddit, GitHub, Linear, Notion, Jira, Asana, Zoom; Discord/Telegram/WhatsApp/X/LinkedIn/Reddit are browser-driven ([CHANGELOG 0.5.0](https://github.com/serhatandic/kuvo-code/blob/main/CHANGELOG.md)).

**Channels.** Bots are reached only inside the app. Outbound to the user: macOS notifications with Reply/Allow/Always Allow/Deny inline; Dock badge ([Sessions docs](https://www.kuvo.run/code/docs/sessions/)). Telegram/WhatsApp are things a bot can operate in the browser, not channels through which you talk to the bot [INFERENCE].

**Voice**: not found. **Team features**: none; single-user app.

## Security and trust model

- **Permissions**: opencode rules per tool/pattern (`git push *`), lower rule wins, Blocks win over everything; session-level Approve All (default) or Ask First; Always Allowed list is reviewable ([Customize docs](https://www.kuvo.run/code/docs/customize/#permissions)). Default is Approve All, so out of the box the agent edits and runs commands without asking ([Sessions docs](https://www.kuvo.run/code/docs/sessions/#talking-to-the-agent)).
- **Sandboxing**: none beyond git worktrees; agent runs as the user on the Mac or remote host [INFERENCE from docs; no sandbox described].
- **Engine supply chain**: pinned version, checksum and code-signature check before execution on Mac; Linux builds checked on the Mac before upload ([README](https://github.com/serhatandic/kuvo-code#how-it-works)). App updates via signed Sparkle feed from GitHub releases; Developer ID signed and notarized ([README](https://github.com/serhatandic/kuvo-code#how-it-works)).
- **Network exposure**: engine on random port with random password; browser tool server on 127.0.0.1 with per-launch token; remote engine localhost-only via SSH ([README](https://github.com/serhatandic/kuvo-code#how-it-works)). SECURITY.md lists these as explicit review scope ([SECURITY.md](https://github.com/serhatandic/kuvo-code/blob/main/SECURITY.md)).
- **Secrets**: Keychain for integration keys and browser passwords; credentials typed into sign-in cards go straight into the page, never to the model ([Browsing docs](https://www.kuvo.run/code/docs/browsing/#signing-in)).
- **Fixed leaks (recent)**: 0.5.22 fixed agent-run commands inheriting the engine's environment, which "hold the key to its browser tools: a command that printed its environment showed it, there for the model to read"; 0.5.18 moved remote MCP keys out of the environment for the same reason; 0.5.17 fixed hidden-job injection through shared bot names ([CHANGELOG](https://github.com/serhatandic/kuvo-code/blob/main/CHANGELOG.md)). These show an active but young threat model.
- **Usage tracker**: reads and renews sign-ins of other tools (Codex, Grok CLI) from Keychain; 0.5.17 stopped renewing the Grok CLI sign-in because it could sign the CLI out ([CHANGELOG](https://github.com/serhatandic/kuvo-code/blob/main/CHANGELOG.md)).
- **Telemetry**: anonymous usage on by default (opt-out in Settings > Privacy or the first-launch note), sent to `analytics.porigam.com.tr`; includes install ID, app/macOS version, CPU kind, RAM range, locale, event names with provider/model/mode, error kinds, durations as ranges, plus a heartbeat every ~2 minutes while open; never prompts, code, file names or error text ([Privacy docs](https://www.kuvo.run/code/docs/privacy/)). Web search goes to Exa by default ([Privacy docs](https://www.kuvo.run/code/docs/privacy/#what-it-connects-to)).
- **Incidents**: no security advisories or security issues found (3 open issues, none security) as of 2026-10-20 ([issues](https://github.com/serhatandic/kuvo-code/issues)).

## Traction and momentum

All numbers as of 2026-10-20 via GitHub API.

| Metric | Value |
| --- | --- |
| Stars / forks | 64 / 7 ([repo](https://github.com/serhatandic/kuvo-code)) |
| Contributors | 1 (serhatandic) |
| Commits on main | 1,002, first 2026-10-13 10:50 UTC, latest 2026-10-19 20:43 UTC (history appears to be published in bulk at launch [INFERENCE]) |
| Releases | 29: v0.1.0 (2026-10-13) to v0.5.22 (2026-10-19), ~4/day ([releases](https://github.com/serhatandic/kuvo-code/releases)) |
| DMG downloads (sum of per-release asset counts) | ~285 |
| Open issues / PRs | 1 bug, 2 PRs from an external contributor (Ggboykxz) proposing a Windows port on the engine's HTTP API |

- Maker: Serhat Andıç, İzmir, Türkiye; GitHub profile lists company Microsoft ([GitHub user API](https://github.com/serhatandic)). No company entity found; analytics host is `porigam.com.tr` (relationship unknown).
- Press / community coverage: none found (unknown).
- **Other Kuvo products**: kuvo.run "makes small, native Mac apps for developers: Kuvo Code for coding agents and AI bots, and Kuvo Box for Docker" ([kuvo.run](https://www.kuvo.run/)). **Kuvo Box** runs the real Docker Engine in a lightweight Linux VM with a native SwiftUI app; docker CLI and Compose unchanged; a `kuvo` CLI; a docs page on giving Claude Code and other agents a container to work in; macOS 15+, Apple silicon ([kuvo.run/box](https://www.kuvo.run/box/), [llms.txt](https://www.kuvo.run/llms.txt)). Repo [serhatandic/kuvo-box](https://github.com/serhatandic/kuvo-box): 8 stars, created 2026-10-11, license NOASSERTION, same "free for personal use" model. The website source repo `serhatandic/kuvo-web` (linked from docs "Suggest an edit") returns 404 to the API, so it is private or deleted as of 2026-10-20.
- **Business model and pricing**: "Free for personal use"; "Commercial use, like at work, needs a paid license: write to info@kuvo.run"; users pay model providers ([kuvo.run/code FAQ](https://www.kuvo.run/code/)). License price unknown.

### License (exact terms)

- `LICENSE` is the verbatim **PolyForm Noncommercial License 1.0.0** ([LICENSE](https://github.com/serhatandic/kuvo-code/blob/main/LICENSE)). NOTICE: "Required Notice: Copyright 2026 Serhat Andıç. Commercial rights reserved." ([NOTICE](https://github.com/serhatandic/kuvo-code/blob/main/NOTICE)).
- Key grants: copyright license to use, change and distribute "for any permitted purpose"; "Any noncommercial purpose is a permitted purpose"; personal use "for research, experiment, and testing for the benefit of public knowledge, personal study, private entertainment, hobby projects, amateur pursuits, or religious observance, without any anticipated commercial application" is permitted; use by charities, educational institutions, public research, public safety/health, environmental and government organizations is permitted "regardless of the source of funding". Distributors must pass on the terms and `Required Notice:` lines. Patent license terminates on patent claims; 32-day cure period for violations ([LICENSE](https://github.com/serhatandic/kuvo-code/blob/main/LICENSE)).
- README: "source-available ... You may use, study, modify, and redistribute it for permitted noncommercial purposes. Commercial use, including monetizing a fork or derivative, requires a separate written license from the copyright holder" ([README](https://github.com/serhatandic/kuvo-code#license)).
- CLA (Harmony-based, outbound option): contributors grant a perpetual, irrevocable, sublicensable license; "The project owner may license your Contribution as part of Kuvo Code under any license, including source-available, commercial, or proprietary terms" ([CONTRIBUTOR_LICENSE_AGREEMENT.md](https://github.com/serhatandic/kuvo-code/blob/main/CONTRIBUTOR_LICENSE_AGREEMENT.md)).

> **2026-10-23 D91 policy note:** the no-source clause in the following historical Memoshi interpretation is superseded, not a consequence of licence classification. Upstream licence observations and the matrix's factual licence value remain as recorded; current personal/noncommercial source reading/reuse follows the amendment above.

- **Not OSI open source**: PolyForm Noncommercial discriminates by field of endeavor, which fails OSD criterion 6, and GitHub reports the license as `NOASSERTION`. For Memoshi this means: nobody building Memoshi reads Kuvo's code ([D55](../../../plan/decisions.md#d55)); copying code into a commercial Memoshi, or using Kuvo Code itself at work, needs a license from the author. Third-party pieces inside it keep their own licenses (opencode MIT, browser-use, Prism, OpenUsage MIT) and can be used from upstream directly ([THIRD_PARTY_LICENSES.txt](https://github.com/serhatandic/kuvo-code/blob/main/THIRD_PARTY_LICENSES.txt), [Licenses/](https://github.com/serhatandic/kuvo-code/tree/main/Licenses)) [INFERENCE on OSD analysis; not legal advice].

## Strengths

- Rides opencode's provider breadth, subscription logins and free models without forking it: low maintenance, upstream improvements come free.
- Strong, polished native UX: PR-style review with line comments sent to the agent, steering vs queueing, undo/fork, worktree attempts, notification actions.
- Bots are a minimal yet complete persistent-agent model: identity + one session + memory file + self-scheduled wake-ups + model-free watches + group chats with a lead and task handoff.
- "Bring your own always-on box": remote Linux engine over SSH keeps bots running with the Mac off, with no vendor cloud.
- Careful security details for a 1-week-old project: a verified engine binary, and credentials never shown to the model (README, docs).
- Extremely fast iteration (~4 releases/day) and docs written for both humans and LLMs (`llms.txt`, `llms-full.txt`, docs-aware system prompt).

## Weaknesses and risks

- **Licensing**: noncommercial-only; any work use needs a paid license, which limits adoption and forks.
- **Platform lock**: Apple silicon + macOS 26 only; Windows exists only as external PRs.
- **Bus factor**: one developer, one week old; behavior changes daily.
- **Tight coupling to opencode 2.x**: the app is pinned to the engine version it's written against.
- **Default Approve All** with no sandbox; agents run as the user on host or server.
- **Bots depend on the app being open** on the Mac (wake-ups, meetings); 24/7 requires your own Linux server.
- **No inbound channels** (Telegram/Slack/SMS) to talk to bots; mobile app not shipped.
- **Telemetry opt-out** rather than opt-in, sent to a third-party-looking domain.
- Doc drift: the docs and the daily releases do not always agree [INFERENCE].

## Ideas worth taking for Memoshi

- **Model-free watches**: run a cheap scheduled shell check and wake the agent only when output stays changed; big cost saver for "watch X" bots.
- **Self-scheduled wake-ups** (a note the bot leaves itself): survives restarts, portable to a remote host.
- **Job lives in memory**: a new bot asks "What's my purpose?" and keeps the answer in its memory file; the sidebar shows it under the bot's name.
- **Avatar state as status UI**: working / needs you / has news / asleep until wake-up / watching; instantly legible roster.
- **Group chat protocol**: one speaker at a time, lead summarizes, explicit "who does what" with dependencies, then work happens in each bot's own session and reports back; in-chat turns are read-only.
- **Agent mail** (send a message, optionally wait for the reply) for bot-to-bot and session-to-bot handoff.
- **Wrap, don't fork, the engine**: pin a version and verify the binary before running it (README).
- **Credentials never reach the model**: sign-in cards fill pages directly; per-site "let agents sign in on their own" allowlist.
- **PR-style review with line comments queued into the next message**: maps well to non-code artifacts too.
- **Avoid**: noncommercial licensing if Memoshi wants contributors or work use; opt-out telemetry; Mac-only lock-in.

## Open questions

- Commercial license price and terms: ask info@kuvo.run.
- Relationship of `porigam.com.tr` to the author: WHOIS or ask the maker.
- Whether the Windows PRs will be accepted given the CLA and license.
- Real active-user numbers: only GitHub asset counts are public; the analytics dashboard is private.

## Sources

1. https://github.com/serhatandic/kuvo-code (README, repo API stats, releases, issues, PRs, commits; fetched 2026-10-20)
2. https://github.com/serhatandic/kuvo-code/blob/main/LICENSE
3. https://github.com/serhatandic/kuvo-code/blob/main/NOTICE
4. https://github.com/serhatandic/kuvo-code/blob/main/CONTRIBUTOR_LICENSE_AGREEMENT.md
5. https://github.com/serhatandic/kuvo-code/blob/main/SECURITY.md
6. https://github.com/serhatandic/kuvo-code/blob/main/CHANGELOG.md
7. https://www.kuvo.run/code/docs/ (Getting started) and pages: installation, accounts, sessions, changes, panel, browsing, machines, bots, integrations, customize, settings, usage, shortcuts, architecture, privacy, troubleshooting, uninstall (via https://www.kuvo.run/llms-full.txt, docs updated 2026-10-18)
8. https://www.kuvo.run/code/
9. https://www.kuvo.run/
10. https://www.kuvo.run/llms.txt
11. https://www.kuvo.run/box/ and https://github.com/serhatandic/kuvo-box
12. https://github.com/serhatandic (user profile via API)
13. https://polyformproject.org/licenses/noncommercial/1.0.0
14. https://github.com/serhatandic/kuvo-web (404 as of 2026-10-20)
