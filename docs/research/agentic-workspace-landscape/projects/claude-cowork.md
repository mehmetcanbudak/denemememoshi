# Claude Cowork (and Anthropic's always-on agents: Dispatch, Claude Tag)

> Anthropic's delegation agent for non-coding knowledge work: launched 2026-01-12 as a local desktop agent, moved to per-session cloud sandboxes on 2026-07-07, merged into the main Claude app on 2026-09-16; complemented by Claude Tag, a shared, ambient @Claude teammate in Slack (2026-06-23). Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Claude Cowork (now part of "one Claude"); related - Dispatch, Claude Tag (@Claude in Slack)
slug: claude-cowork
category: closed-hosted-agents
maker: Anthropic
license: proprietary
repo: none
website: https://claude.com/product/cowork ; https://www.claude.com/product/tag
first_public: 2026-01-12
latest_release: cloud-only default for new Pro/Max Cowork tasks, 2026-10-06
release_cadence: multiple product updates per month (help-center release notes)
stars: n/a (closed)
forks: n/a
contributors: n/a
primary_language: unknown
stack: Claude desktop (macOS/Windows/Linux beta) + web + iOS/Android + Chrome side panel; cloud sessions in per-session ephemeral sandboxes on Anthropic infra; local sessions use a Linux VM (Virtualization.framework / Hyper-V); Claude Tag on Slack
platforms: [macos, windows, linux, web, ios, android]
agent_engine: own loop (Claude Code agent harness lineage)
engines_supported: [raw-api]  # Anthropic models only
model_access: subscription logins (Pro/Max/Team/Enterprise); Enterprise usage at API rates; Tag billed per org/channel spend limits
execution_env: cloud sandbox per session (default since 2026-10-06 for Pro/Max); local agent loop + Linux VM for legacy desktop tasks; local files/browser/computer use brokered through the desktop app
per_bot_computer: no persistent computer; ephemeral sandbox per session (destroyed at end)
persistent_bots: partial - single assistant identity; Dispatch = one persistent thread; Claude Tag = one shared Claude per Slack channel with admin-scoped "separate Claude identities"
memory: account memory used across chats and tasks (view/edit/delete); Tag builds channel-scoped memory from channel traffic
routines: scheduled recurring tasks that run in the cloud with no device online; Tag can schedule tasks for itself over hours or days
group_chat: partial - Claude Tag is multiplayer within a Slack channel; no multi-bot rooms
coding_workspace: partial - code execution, files; coding routed to Claude Code ("Code" tab)
browser_use: yes - built-in browser in Claude Desktop or user's Chrome via Claude in Chrome (needs desktop app online)
computer_use: yes - beta on Pro/Max, desktop app only; not on Linux
connectors: native connectors + MCP (remote and local), skills, plugins (bundles of skills + connectors)
channels: Claude apps (web/desktop/mobile push), Slack (Claude Tag), Chrome side panel; no SMS/WhatsApp/iMessage/email-in
mobile: yes - start, steer, answer questions, approve from phone; push notifications
voice: yes (voice mode in Claude apps; not Cowork-specific)
approvals: per-conversation Manual (default, ask before each action) or Auto (automated safety checks before actions); asks before permanently deleting files; nothing ships before review for scheduled cloud work
e2e_encryption: no
self_host: no (Claude Managed Agents API offers self-hosted sandboxes for developers)
multi_user: yes - Team/Enterprise admin controls, network policy, OTel, Compliance API; Tag shared per channel
pricing: Pro $20/mo ($17 annual); Max from $100/mo (5x) or $200 (20x); Team $25/$125 seat monthly; Enterprise $20/seat + usage at API rates (as of 2026-10-20)
maturity: GA on Pro/Max (unified experience rolling out since 2026-09-16); cloud beta on Team/Enterprise; Claude Tag beta (Team/Enterprise)
```

## What it is

Cowork "brings Claude Code's agentic capabilities to the Claude desktop app for knowledge work" and debuted as a research preview on 2026-01-12 for Max plans on macOS ([Claude release notes](https://support.claude.com/en/articles/12138966-release-notes)). Anthropic reports "more than 90%" of Cowork usage is not software development; business operations and content creation are roughly half ([Anthropic, 2026-07-07](https://claude.com/resources/articles/cowork-web-mobile)).

Key 2026 milestones:

| Date | Change | Source |
|---|---|---|
| 2026-01-12 | Research preview, Claude Desktop macOS, Max | [release notes](https://support.claude.com/en/articles/12138966-release-notes) |
| 2026 (spring) | Dispatch: message Claude from phone, it works on your desktop; computer use | [help](https://support.claude.com/en/articles/13947068), [blog](https://claude.com/blog/dispatch-and-computer-use) |
| 2026-06-23 | Claude Tag: @Claude in Slack as a team member, ambient mode, beta for Team/Enterprise, replaces Claude in Slack | [Anthropic](https://www.anthropic.com/news/introducing-claude-tag) |
| 2026-07-07 | Cowork on web and mobile; work continues in the cloud with laptop closed; scheduled tasks run with no device online | [Anthropic](https://claude.com/resources/articles/cowork-web-mobile) |
| 2026-09-16 | Cowork and chat merged into "one Claude" (Pro/Max rollout); Docs and Slides | [Anthropic](https://claude.com/resources/articles/cowork-is-now-claude) |
| 2026-10-06 | New Pro/Max Cowork tasks run only in the cloud; "Only on your computer" option removed | [help](https://support.claude.com/en/articles/15520349) |

## Product and UX

- One conversation list; no mode picker: "Ask Claude for what you need, and it can decide which tool to use"; several tasks can run at once ([help](https://support.claude.com/en/articles/16761823)).
- Handoff flow: describe the outcome, close the laptop, check progress or answer Claude's questions from the phone, get finished DOCX/XLSX/PPTX or shareable Docs/Slides back ([Anthropic](https://claude.com/resources/articles/cowork-is-now-claude), [help](https://support.claude.com/en/articles/16761823)).
- Permission dial in the message box: Manual (default) vs Auto ([help](https://support.claude.com/en/articles/16761823)).
- Dispatch: "a single persistent thread with Claude. This thread doesn't reset"; routes dev tasks to Claude Code and knowledge work to Cowork; push notification when done or when Claude needs a go-ahead; not available to new users after the merge ([help](https://support.claude.com/en/articles/13947068)).
- Claude Tag: tag @Claude in a channel; it breaks work into stages and replies in-thread; anyone can pick up where the last person left off; DMs use personal connectors ([Anthropic](https://www.anthropic.com/news/introducing-claude-tag)).

## Architecture

- Cloud sessions: "the agent loop and code execution run in an isolated, temporary sandbox on Anthropic-managed infrastructure. Each session gets its own sandbox, created when the session starts and destroyed when it ends" ([architecture overview](https://support.claude.com/en/articles/14479288)).
- Network: sandbox cannot reach private/internal/metadata addresses; egress goes through a mandatory proxy outside the sandbox with allow-listed destinations ([same](https://support.claude.com/en/articles/14479288)).
- Credentials: only session-scoped tokens that expire within hours; "Connector authorization tokens never enter the sandbox; connector calls are made on the server side" ([same](https://support.claude.com/en/articles/14479288)).
- Device bridge: local files, browser and computer use are reached "through the Claude Desktop app on that device over an Anthropic-brokered connection", each local tool call checked against permissions; offline desktop = no device access ([same](https://support.claude.com/en/articles/14479288)). When a cloud task needs a local file, Claude fetches a copy of just that file ([help](https://support.claude.com/en/articles/15520349)).
- Local (legacy) sessions: agent loop native on device; shell and code in a dedicated Linux VM (Apple Virtualization.framework / Hyper-V) with its own egress filtering and syscall restrictions ([architecture overview](https://support.claude.com/en/articles/14479288)).
- Models: Anthropic only; Claude Tag "works with Opus 4.8" ([Anthropic](https://www.anthropic.com/news/introducing-claude-tag)).
- Extension surface: connectors (remote MCP; local MCP via desktop only), skills, plugins ([help](https://support.claude.com/en/articles/16761823), [help](https://support.claude.com/en/articles/15520349)). Developer counterpart: Claude Managed Agents, a "pre-built, configurable agent harness that runs in managed infrastructure" with Agent / Environment / Session / Events concepts ([docs](https://platform.claude.com/docs/en/managed-agents/overview)).
- Migration path to local: "Download task data", then `/port-task-data` in Claude Code ([help](https://support.claude.com/en/articles/15520349)).

## Capabilities in detail

- Memory: "Claude uses what it remembers from your chats in the tasks it works on for you"; memory can be turned off per task; memory from local-only tasks stays with those tasks ([help](https://support.claude.com/en/articles/16761823), [help](https://support.claude.com/en/articles/15520349)).
- Routines: "Scheduled tasks can run in the cloud, so they keep going when your computer is off" ([help](https://support.claude.com/en/articles/16761823)).
- Cross-surface: start, steer, resume, connectors, skills, scheduled tasks on desktop, web and mobile; local files/browser/computer use from web or mobile only via an online desktop app ([help surface table](https://support.claude.com/en/articles/15520349)).
- Claude Tag specifics: channel-scoped memory, optional learning from other permitted channels (not private channels), "ambient" proactive updates and follow-ups on stalled threads, self-scheduled tasks ([Anthropic](https://www.anthropic.com/news/introducing-claude-tag)). Anthropic says 65% of its product team's code is created by its internal Tag (vendor claim, [same](https://www.anthropic.com/news/introducing-claude-tag)).
- Limitations: no conversation branching, no "Add from GitHub", search excludes older Cowork tasks ([help](https://support.claude.com/en/articles/16761823)).

## Security and trust model

- Cloud-session isolation, proxy egress, short-lived tokens, connector tokens server-side (above). Org controls: turn cloud sessions off, set network policy, disable persistent "always allow", require trusted-device enrollment and recent sign-in ([architecture overview](https://support.claude.com/en/articles/14479288)).
- Dispatch safety warning: phone-to-desktop control "creates a chain where instructions from your phone can trigger real actions on your computer" and "malicious content the model encounters along the way" could cascade ([help](https://support.claude.com/en/articles/13947068)).
- Observability: Compliance API and OpenTelemetry capture Cowork activity; EDR cannot see inside the VM or cloud sandbox ([architecture overview](https://support.claude.com/en/articles/14479288)).
- Tag governance: admins scope tools/data per channel ("separate Claude identities"), memories stay scoped, org and per-channel token spend limits, log of every action and requester ([Anthropic](https://www.anthropic.com/news/introducing-claude-tag)).
- Concerns: Tag ingests channel data into Anthropic-hosted context (press: [The Register, 2026-06-23](https://www.theregister.com/ai-and-ml/2026/06/23/anthropic-reimagines-claude-in-slack-as-nosy-always-on-agentic-ai-coworker/5260422)). Model training on consumer plans follows the "Help improve our AI models" setting ([help](https://support.claude.com/en/articles/15520349)).

## Traction and momentum

- Usage counts against plan limits; agentic tasks use more ([help](https://support.claude.com/en/articles/16761823)). Doubled Cowork limits promo through 2026-08-05 ([Anthropic](https://claude.com/resources/articles/cowork-web-mobile)).
- Tag launch credits: $25,000 (Enterprise) / $2,500 (Team) for orgs with >10 seats migrating before 2026-09-01 (press: [The Register](https://www.theregister.com/ai-and-ml/2026/06/23/anthropic-reimagines-claude-in-slack-as-nosy-always-on-agentic-ai-coworker/5260422)).
- Pricing (as of 2026-10-20): Free $0; Pro $20/mo or $17/mo annual ("Hand off and schedule tasks"); Max from $100/mo; Team standard $25/$20, premium $125/$100 per seat; Enterprise $20/seat + usage at API rates; @Claude (Tag) not on individual plans ([pricing](https://claude.com/pricing)).

## Strengths

- Clear, documented cloud-sandbox security model (ephemeral sandbox, egress proxy, tokens outside the sandbox) and a device bridge for local reach.
- True cross-device continuity: start on desktop, answer questions on phone, finish anywhere.
- Collapsing chat vs agent modes removes a routing decision from users.
- Tag shows a credible "shared teammate in a channel" pattern with scoped identities and spend caps.

## Weaknesses and risks

- No persistent per-agent computer or named bot roster; one assistant per user (plus channel Tags).
- No consumer messaging channels (SMS, WhatsApp, iMessage, email-in).
- Forced cloud migration on 2026-10-06 removed local-only choice for Pro/Max; local files processed on Anthropic servers.
- Fast product churn (Dispatch closed to new users within months).
- Anthropic models only.

## Ideas worth taking for Memoshi

- Ephemeral per-session sandbox with egress proxy outside it; credentials and connector tokens never enter the sandbox.
- Desktop app as a brokered bridge so cloud agents can reach local folders/browser only while the app is online.
- Single permission dial (Manual / Auto with automated pre-action checks) per conversation.
- Questions route to the phone mid-task; "nothing ships until reviewed" for unattended scheduled work.
- Channel-scoped bot identity with memory isolation and per-channel spend limits (Tag) for team mode.
- Task export + import into a local harness (`/port-task-data`) as a portability escape hatch.

## Open questions

- How Claude Tag will expand beyond Slack (Teams, email) and whether individual plans get it.
- Memory mechanism details (structure, retention) for cloud tasks.
- Whether Anthropic will ship a consumer always-on agent with its own identity (reports of an internal "Conway" project are third-party only; not confirmed).

## Sources

1. https://support.claude.com/en/articles/12138966-release-notes
2. https://claude.com/resources/articles/cowork-web-mobile
3. https://claude.com/resources/articles/cowork-is-now-claude
4. https://support.claude.com/en/articles/16761823
5. https://support.claude.com/en/articles/15520349
6. https://support.claude.com/en/articles/14479288
7. https://support.claude.com/en/articles/13947068
8. https://claude.com/blog/dispatch-and-computer-use
9. https://www.anthropic.com/news/introducing-claude-tag
10. https://claude.com/pricing
11. https://platform.claude.com/docs/en/managed-agents/overview
12. Press: https://www.nbcnews.com/tech/tech-news/anthropic-will-make-claude-cowork-available-users-cloud-rcna353218
13. Press: https://www.theregister.com/ai-and-ml/2026/06/23/anthropic-reimagines-claude-in-slack-as-nosy-always-on-agentic-ai-coworker/5260422
14. Third-party (unconfirmed Conway reports): https://claudeai.dev/blog/conway-timeline-how-anthropic-is-building-always-on-agents
