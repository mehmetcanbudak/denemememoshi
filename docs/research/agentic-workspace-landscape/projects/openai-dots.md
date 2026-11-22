# OpenAI Dots

> A named, always-on agent inside ChatGPT that owns a cloud computer and browser, keeps working between conversations, delegates coding to Codex, and is reachable from ChatGPT, Slack, Teams, calls and (beta) SMS. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: OpenAI Dots
slug: openai-dots
category: closed-hosted-agents
maker: OpenAI
license: proprietary
repo: none
website: https://chatgpt.com/dots
first_public: 2026-09-29
latest_release: "no public version numbers; help center updated 2026-10-19"
release_cadence: "continuous server-side; post-launch update batch reported 2026-10-10 (press)"
stars: n/a
forks: n/a
contributors: n/a
primary_language: unknown
stack: "GPT-6 Astra; per-dot Linux cloud VM with Chrome; ChatGPT plugins; Codex / ChatGPT Work for delegated tasks"
platforms: [web, macos, windows, ios, android]
agent_engine: "own loop (GPT-6 Astra) + background agents; delegates to ChatGPT Work and Codex tasks"
engines_supported: ["openai-internal (GPT-6 Astra)", "codex (delegated tasks)"]
model_access: "vendor subscription only (ChatGPT Pro 100/200/500, Business Premium, Enterprise beta)"
execution_env: "per-dot OpenAI cloud VM (Linux + Chrome, sandboxed); optional user's own computer via ChatGPT desktop app"
per_bot_computer: "yes - each dot has its own cloud computer and browser; user can open it and take over"
persistent_bots: "yes - one primary named dot per user (handle @user-name, avatar); specialist dots with own identity in enterprise pilot"
memory: "shares ChatGPT memory plus the dot's own private notes; individual memories not viewable/editable, only full reset"
routines: "yes - scheduled/recurring tasks, self-scheduled wake-ups, read-only proactive research"
group_chat: "partial - dot can sit in Slack channels with humans; one dot per user at launch, 'teams of dots' only envisioned"
coding_workspace: "partial - creates Codex cloud tasks and local Codex tasks; returns PRs; no IDE of its own"
browser_use: "yes - cloud Chrome with secure sign-in and user takeover"
computer_use: "yes - own cloud computer; user's laptop optional (off by default)"
connectors: "ChatGPT plugins shared with ChatGPT/Work/Codex; 'over 4,000 apps' (vendor claim)"
channels: "ChatGPT (web/desktop/mobile), Slack, Microsoft Teams (invite-only alpha), SMS (limited US Pro beta), voice calls; no own email address at launch"
mobile: "yes - ChatGPT iOS/Android app (mobile web unsupported)"
voice: "yes - call your dot in ChatGPT; dot cannot initiate calls at launch"
approvals: "built-in action rules + separate Auto-review system + Custom Rules (act / act if pre-approved / ask / hand off); passwords and money transfers always handed back"
e2e_encryption: "no - encryption at rest and in transit only"
self_host: no
multi_user: "partial - Business Premium/Enterprise admin RBAC; each dot owned by one member; specialist dots and Microsoft Agent 365 integration in preview"
pricing: "first dot included in Pro 100/200/500 ($100/$200/$500 per month, press) and Business Premium; extra dots and speed/volume upgrades announced, unpriced"
maturity: "beta - gradual rollout since 2026-09-29; Enterprise is beta and off by default"
```

## What it is

A "dot" is an always-on personal agent inside ChatGPT, powered by GPT-6 Astra, with "their own cloud computer", that learns from feedback and "can work towards your goals 24/7" ([OpenAI](https://openai.com/index/introducing-dots/)). OpenAI positions it as distinct from Chat (answers), ChatGPT Work (one-off or scheduled delegated tasks) and Codex (software): a dot "keep[s] track of an ongoing responsibility, figure[s] out next steps as things change, and follow[s] up between conversations", delegating to Work or Codex ([ChatGPT Learn](https://learn.chatgpt.com/docs/dots)). The mental model is a named colleague you message or call, not a task runner. Target users are paying Pro individuals and Business Premium/Enterprise members; the launch post names developers, launch leads, scientists, sales leads and creators ([OpenAI](https://openai.com/index/introducing-dots/)).

## Product and UX

- Onboarding: create the dot in the desktop app, desktop web or mobile app, name it, choose shape/color/eyes/accessories or a pet; handle becomes `@yourname-agentname`; the dot "introduces itself" and suggests ways to help ([Help Center](https://help.openai.com/articles/20001530), [ChatGPT Learn](https://learn.chatgpt.com/docs/dots)).
- Profile page: In progress / Scheduled / Completed, Activity view of delegated tasks, Computers (cloud computer with Take over / Return control), Customize (Plugins, Memory, Custom rules), Pause and Reset ([Help Center](https://help.openai.com/articles/20001530)).
- One continuous relationship across channels: "Changing where you talk to it doesn't start a new dot or reset its memory"; the user can route kinds of updates to specific channels (routine progress in ChatGPT, decisions in Slack) ([ChatGPT Learn](https://learn.chatgpt.com/docs/dots)).
- The dot "can decide when to pause and wake up to continue work; you don't need a fixed schedule for every follow-up" and runs background agents in parallel while you keep talking ([ChatGPT Learn](https://learn.chatgpt.com/docs/dots)).
- Distinctive: playful character design (plush-toy avatars), voice calls, Slack presence, and a permission UI built around four rule behaviors rather than per-tool toggles.

## Architecture

- Components: GPT-6 Astra agent; per-dot cloud workspace (Linux + Chrome, sandboxed, isolated per user); code runs "in environments that are separate from the systems that coordinate their work and enforce key safeguards"; separate Auto-review service and safety monitor; encrypted credential service for saved passwords ([OpenAI safety post](https://openai.com/index/how-we-build-safety-security-and-privacy-into-dots/)).
- Agent loop: own harness, not disclosed; background agents, cloud threads, ChatGPT Work and Codex tasks as sub-workers ([ChatGPT Learn](https://learn.chatgpt.com/docs/dots)). Wire protocols: unknown.
- Models: GPT-6 Astra only; "Enterprise model controls and defaults do not apply to dots" ([admin guide](https://learn.chatgpt.com/docs/enterprise/dots-admin-guide.md)). Astra API list price $10/$50 per M tokens is reported by a third party ([beam.ai, third-party](https://beam.ai/agentic-insights/openai-dots-usage-limits-pro-200)).
- Execution: OpenAI cloud VM; optional single local computer via the ChatGPT desktop app, which must stay online; local tasks appear as separate sidebar tasks ([ChatGPT Learn](https://learn.chatgpt.com/docs/dots)).
- State: dot context retained "for as long as you keep your dot"; context does not retain credentials, images or screenshots; files follow the storage location's policy ([Privacy FAQ](https://help.openai.com/articles/20001529)).
- Extension surface: ChatGPT plugins (shared permissions with ChatGPT, Work, Codex), local skills (require connected computer), Codex cloud environments. No public dots API found; enterprise has Analytics API and Compliance API records ([admin guide](https://learn.chatgpt.com/docs/enterprise/dots-admin-guide.md)). Developer API for dots: unknown.

## Capabilities in detail

- Persistent identity: one primary dot per user at launch; "In the future, you'll be able to add more dots" ([OpenAI](https://openai.com/index/introducing-dots/)). Specialist dots get "their own identity, credentials, and access", in focused enterprise pilots; Slack can host a separate account for the dot ([OpenAI](https://openai.com/index/introducing-dots/), [Privacy FAQ](https://help.openai.com/articles/20001529)).
- Memory: receives ChatGPT memories and recent context, writes its own notes, contributes back to ChatGPT memory; disconnecting an app does not delete learned info; no per-item view/delete ([Privacy FAQ](https://help.openai.com/articles/20001529)).
- Routines: reminders and recurring checks, managed in a Scheduled section; proactive research runs read-only in the background ([Help Center](https://help.openai.com/articles/20001530)).
- Coding: "brings you complete PRs to review with attached videos" (vendor claim, [OpenAI](https://openai.com/index/introducing-dots/)); mechanically via Codex cloud environments ([Help Center](https://help.openai.com/articles/20001530)).
- Browser/computer: cloud browser with its own sessions; if a site blocks cloud browsers the dot can fall back to the user's connected computer ([Help Center](https://help.openai.com/articles/20001530)).
- Purchases: with cards already saved on merchant sites, always with approval ([OpenAI safety post](https://openai.com/index/how-we-build-safety-security-and-privacy-into-dots/)).
- Channels: Slack DM or channel mention, only the owner can direct it; Teams is an invite-only alpha; texting is a third-party-provider beta for US Pro; no standalone email address at launch ([admin guide](https://learn.chatgpt.com/docs/enterprise/dots-admin-guide.md), [Help Center](https://help.openai.com/articles/20001530)).

## Security and trust model

- Layers: model refusals; plugin permissions; Custom Rules; Auto-review before consequential actions; runtime safety monitoring that can pause work ([Privacy FAQ](https://help.openai.com/articles/20001529)).
- Auto-review runs outside environments the dot can change; if it blocks a step it returns the reason so the dot can ask, try an alternative, hand off, or stop ([OpenAI safety post](https://openai.com/index/how-we-build-safety-security-and-privacy-into-dots/)).
- Recipient-sensitivity rule: health data requires a named recipient; low-sensitivity PII needs at least a recipient class; approvals stay bound to the task and do not expand on delegation ([OpenAI safety post](https://openai.com/index/how-we-build-safety-security-and-privacy-into-dots/)).
- Proactive research limits "enforce[d] in code": cannot send messages, change app content, or control browser/desktop ([OpenAI safety post](https://openai.com/index/how-we-build-safety-security-and-privacy-into-dots/)).
- Secrets: secure sign-in pauses the model and sends credentials to the browser environment; saved passwords flow through an encrypted credential service ([OpenAI safety post](https://openai.com/index/how-we-build-safety-security-and-privacy-into-dots/)).
- Training: personal plans controlled by "Improve the model for everyone", which can include actions, delegated work and automations; human review may occur even with training off ([Privacy FAQ](https://help.openai.com/articles/20001529)).
- Incidents: 2026-10-07 "Dot turn failures, delayed responses, and reduced proactivity" outage, resolved in about an hour ([OpenAI status](https://status.openai.com/incidents/01M4BP5JE7DKJSP3VG2S2DCWF2)). Separately, Wikimedia said on 2026-10-05 that OpenAI agents (not identified as dots; activity dated May 2026) caused a Wikidata Query Service disruption ([OECD AIM summary of Reuters et al.](https://oecd.ai/en/incidents/2026-10-05-1485)).

## Traction and momentum

- Launched at DevDay 2026-09-29 alongside GPT-6.1 Sol ([OpenAI product releases](https://openai.com/news/product-releases/)). Press framed it as answering Meta Muse three weeks earlier ([PCMag, press](https://uk.pcmag.com/ai/167569/openai-goes-after-metas-muse-with-always-on-dots-agents)); AP's headline tied the launch to OpenAI shelving a model over safety concerns ([AP, press](https://apnews.com/article/sam-altman-openai-conference-dots-agent-77b6b8888145869206996d7509d24256)).
- Availability: Pro outside EEA/UK/Switzerland; Business Premium in all supported regions; Enterprise/Edu/Healthcare beta, admin-enabled ([Help Center](https://help.openai.com/articles/20001530)).
- Pricing: first dot included; conversations do not count toward ChatGPT limits; Work/Codex tasks the dot starts do; extended first-month limits ([ChatGPT Learn](https://learn.chatgpt.com/docs/dots)). Pro 200's Codex/Work allowance halves from 2026-10-30 ([beam.ai, third-party](https://beam.ai/agentic-insights/openai-dots-usage-limits-pro-200)). Bloomberg headlined a "New $500 Paid Tier" at launch ([Bloomberg, press](https://www.bloomberg.com/news/articles/2026-09-29/openai-unveils-always-on-ai-agent-dots-new-500-paid-tier)).
- Plan prices: Pro tiers at $100, $200 and $500 per month ([Engadget, press](https://www.engadget.com/2281998/how-to-use-opeai-dot-rollout-schedule)); Business Premium $125/user/month or $100 billed annually ([beam.ai, third-party](https://beam.ai/agentic-insights/openai-dots-usage-limits-pro-200)).
- Usage numbers: unknown.

## Strengths

- Strongest documented permission model in the category: four-level rules, a separate reviewer outside the agent's reach, sensitivity-scaled recipient authorization.
- Deep reuse of an installed base: ChatGPT memory, plugins, Codex, and desktop/mobile apps from day one.
- One dot across channels (ChatGPT, Slack, Teams, SMS, calls) with shared context.

## Weaknesses and risks

- Single dot per user; no multi-agent rooms yet.
- Memory opacity: cannot view or delete individual memories, only reset the whole dot ([Privacy FAQ](https://help.openai.com/articles/20001529)).
- Price floor $100/month and unpublished long-term usage terms; agent work is billed against Codex/Work quotas.
- Vendor lock: GPT-6 Astra only, OpenAI cloud only, no self-host, no API.
- Not available on Pro in the EU/UK/Switzerland at launch.

## Ideas worth taking for Memoshi

- Four-state action rules (act / act if pre-approved / ask / hand off) as the user-facing permission vocabulary: simpler than per-tool scopes.
- A reviewer process that runs outside the agent's sandbox and returns block reasons to the agent: lets the agent recover instead of failing.
- Read-only "proactive research" mode enforced at the tool layer, separate from action-taking runs.
- Approvals scoped to recipient class and data sensitivity, not just to tool.
- Route update types to channels ("decisions to Slack, progress in app") as a per-bot setting.
- Avoid: opaque memory with reset-only deletion; Memoshi should expose editable memory (Muse does).

## Open questions

- Per-plan usage allowances after the launch month, price of additional dots: watch help.openai.com and learn.chatgpt.com.
- Whether a developer API or Agents SDK hook for dots will ship: watch OpenAI DevDay/platform changelog.
- Harness internals and wire protocols: not disclosed; the GPT-6 Astra system card may cover parts ([system card](https://deploymentsafety.openai.com/gpt-6-astra/change-log)).

## Sources

1. https://openai.com/index/introducing-dots/
2. https://openai.com/index/how-we-build-safety-security-and-privacy-into-dots/
3. https://help.openai.com/articles/20001529 (Dots privacy, security, and safety FAQs)
4. https://help.openai.com/articles/20001530 (Getting started with your dot)
5. https://learn.chatgpt.com/docs/dots
6. https://learn.chatgpt.com/docs/enterprise/dots-admin-guide.md
7. https://status.openai.com/incidents/01M4BP5JE7DKJSP3VG2S2DCWF2
8. https://openai.com/news/product-releases/
9. https://deploymentsafety.openai.com/gpt-6-astra/change-log
10. https://beam.ai/agentic-insights/openai-dots-usage-limits-pro-200 (third-party)
11. https://www.bloomberg.com/news/articles/2026-09-29/openai-unveils-always-on-ai-agent-dots-new-500-paid-tier (press)
12. https://uk.pcmag.com/ai/167569/openai-goes-after-metas-muse-with-always-on-dots-agents (press)
13. https://apnews.com/article/sam-altman-openai-conference-dots-agent-77b6b8888145869206996d7509d24256 (press, headline only; page blocked)
14. https://oecd.ai/en/incidents/2026-10-05-1485 (third-party incident aggregator)
