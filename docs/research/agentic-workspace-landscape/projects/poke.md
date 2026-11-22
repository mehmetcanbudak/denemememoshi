# Poke

> A proactive personal agent that lives in your text threads (Apple Messages for Business, SMS, WhatsApp, Telegram), extended through shareable "Recipes" that bundle MCP integrations and onboarding; made by The Interaction Company of California, acquired by Cognition (Devin) on 2026-07-23. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Poke
slug: poke
category: closed-hosted-agents
maker: The Interaction Company of California (Marvin von Hagen et al.), part of Cognition since 2026-07-23
license: proprietary (CLI distributed as the `poke` npm package)
repo: none public for the service
website: https://poke.com
first_public: 2026-03 (public launch per TechCrunch; seed-funded 2025)
latest_release: unknown (release notes at poke.com/docs/release-notes)
release_cadence: unknown
stars: n/a (closed)
forks: n/a
contributors: n/a
primary_language: unknown
stack: hosted cloud agent; messaging gateways (Apple Messages for Business via a messaging service provider, SMS, WhatsApp, Telegram); MCP-based integrations; `npx poke` CLI with tunnels for local MCP servers; REST API (poke.com/api/v1)
platforms: [ios, android, web, cli]  # via native messaging apps; web for setup/Kitchen
agent_engine: own loop
engines_supported: [raw-api]  # "frontier models" on Pro/Ultra; providers undisclosed
model_access: vendor credits (Free / Pro $19 / Ultra $199 per month; pay-as-you-go beyond credits on Ultra)
execution_env: Poke cloud (no per-user VM documented)
per_bot_computer: no
persistent_bots: yes - single persona "Poke" per user with a strong personality
memory: yes - uses memory plus integrated services to act "right on time" (mechanism unknown)
routines: reminders and "real-time automations running in the background" (Pro/Ultra); recipes can create automations
group_chat: unknown
coding_workspace: no (integrates GitHub, Vercel, Cursor, Devin, Sentry, Supabase as services)
browser_use: unknown
computer_use: no
connectors: MCP servers (remote, API-key, OAuth, or local via tunnel) + first-party integrations (Gmail, Outlook, Calendar, Notion, Linear, Asana, Todoist, Granola, Oura, Fitbit, Strava, Hue, Sonos, Ramp, Mercury...)
channels: Apple Messages (Messages for Business), SMS, WhatsApp (some markets), Telegram; voice memos
mobile: yes (native texting)
voice: partial - accepts voice messages
approvals: unknown
e2e_encryption: no (business-messaging relay through provider)
self_host: no
multi_user: no
pricing: Free $0; Pro $19/mo; Ultra $199/mo (as of 2026-10-20)
maturity: GA (public since March 2026; hundreds of thousands of users per acquirer)
```

## What it is

"Poke is a personal agent that lives in your texts. It messages you first, follows up with you, and feels less like software and more like a friend" ([Cognition, 2026-07-23](https://cognition.com/blog/interaction)). The site pitches "Proactive, private, personal, and right in your texts" on "Apple Messages, WhatsApp, Telegram, and more" ([poke.com](https://poke.com/)). Launched publicly in March 2026; became the first AI agent approved on Apple's Messages for Business platform on 2026-06-04 (press: [TechCrunch](https://techcrunch.com/2026/06/04/apple-approves-poke-as-the-first-ai-agent-on-its-messages-for-business-platform/)).

## Product and UX

- Onboarding by text; plans Free, Pro and Ultra; "Every plan gets all of Poke" with differences in model tier, automation rate limits and support ([poke.com](https://poke.com/)).
- Recipes: blueprints bundling onboarding context, a prefilled first message, required integrations (MCP templates) and a share link `https://poke.com/r/<referralCode>`; published recipes earn creator payouts via Venmo ([docs](https://poke.com/docs/creating-recipes)).
- On Apple Messages for Business, UI follows Apple style rules (link previews, buttons) (press: [TechCrunch](https://techcrunch.com/2026/06/04/apple-approves-poke-as-the-first-ai-agent-on-its-messages-for-business-platform/)).

## Architecture

- Hosted agent; channels via messaging providers; Poke pays its Messages-for-Business provider per user (press: [TechCrunch](https://techcrunch.com/2026/06/04/apple-approves-poke-as-the-first-ai-agent-on-its-messages-for-business-platform/)).
- Extension: `npx poke@latest mcp add <url>` for remote MCP servers (optional API key); `npx poke@latest tunnel http://localhost:3000/mcp` exposes a local MCP server, tools re-synced every 5 minutes; OAuth MCP servers go through the web flow; CLI credentials at `~/.config/poke/credentials.json`; API base `https://poke.com/api/v1` ([docs](https://poke.com/docs/creating-recipes)).
- Models, memory store, sandboxing: unknown. Post-acquisition, "Cognition's models and infrastructure will make Poke even faster and more reliable" ([Cognition](https://cognition.com/blog/interaction), vendor claim).

## Capabilities in detail

Daily planning, calendar, health/fitness tracking, smart home, photo editing via text (press: [TechCrunch](https://techcrunch.com/2026/06/04/apple-approves-poke-as-the-first-ai-agent-on-its-messages-for-business-platform/)); reminders and head starts on tasks from text or voice messages; proactive use of integrations and memory ([poke.com](https://poke.com/)).

## Security and trust model

Apple approval required verifiable live-support capability and clear AI identification (press: [TechCrunch](https://techcrunch.com/2026/06/04/apple-approves-poke-as-the-first-ai-agent-on-its-messages-for-business-platform/)). Local-MCP tunnels expose developer machines to the hosted agent while active ([docs](https://poke.com/docs/creating-recipes)) [INFERENCE: a risk surface]. Approval model and data retention: unknown. Incidents: none found as of 2026-10-20.

## Traction and momentum

100 million messages relayed by June 2026 (press: [TechCrunch](https://techcrunch.com/2026/06/04/apple-approves-poke-as-the-first-ai-agent-on-its-messages-for-business-platform/)); "more than 100 million messages ... in just the last three months" and "hundreds of thousands of people" (vendor claim, [Cognition](https://cognition.com/blog/interaction)). Funding: $15M seed (2025) + $10M (April 2026) at $300M post-money; 10-person team before acquisition (press: [TechCrunch](https://techcrunch.com/2026/06/04/apple-approves-poke-as-the-first-ai-agent-on-its-messages-for-business-platform/)). Acquired by Cognition 2026-07-23 ([Cognition](https://cognition.com/blog/interaction)).

## Strengths

- Native-texting UX including a sanctioned Apple Messages channel (others rely on unofficial iMessage bridges).
- Personality and proactivity as product differentiators.
- Developer-friendly MCP extension with tunnels and a creator economy (recipes with payouts).

## Weaknesses and risks

- Single assistant, no multi-bot roster or own computer; limited for long-running computer tasks.
- Acquisition by a coding-agent company may shift priorities toward Devin integration [INFERENCE].
- Opaque security/approval model.

## Ideas worth taking for Memoshi

- Shareable "recipe" = onboarding prompt + required integrations + install link; good primitive for sharing bot setups.
- `tunnel` command to expose a local MCP server to a hosted agent, with periodic tool sync.
- Pursue Apple Messages for Business as a sanctioned iMessage channel (months-long approval).
- Agent-initiated messages ("messages you first") as default proactivity pattern.

## Open questions

- Memory architecture and data retention; approval rules for sends/purchases.
- Roadmap after Cognition (Devin hand-offs from texts?).

## Sources

1. https://poke.com/
2. https://poke.com/docs/creating-recipes
3. https://cognition.com/blog/interaction
4. Press: https://techcrunch.com/2026/06/04/apple-approves-poke-as-the-first-ai-agent-on-its-messages-for-business-platform/
5. Press: https://techcrunch.com/2026/07/24/why-cognition-bought-poke-ai-personality-is-becoming-a-competitive-advantage/
