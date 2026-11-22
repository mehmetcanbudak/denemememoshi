# Instinct

> Invite-only consumer personal assistant from Spear Street Technology (Noah Shinn) with "no new interfaces": you text or call it, it connects to your accounts and devices and acts with a phone and a computer the way a person would. The fastest-funded and most security-criticized entrant of 2026. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Instinct
slug: instinct
category: closed-hosted-agents
maker: Spear Street Technology, Inc. d/b/a Instinct (San Francisco; founder/CEO Noah Shinn)
license: proprietary
repo: none
website: https://instinct.com (also instinct.co)
first_public: 2026-08-26 (public invite-only launch post; private beta from Feb 2026 per WSJ via Fortune)
latest_release: group-chat agents for early-access users, 2026-10-05
release_cadence: unknown (frequent fixes announced on X)
stars: n/a (closed)
forks: n/a
contributors: n/a
primary_language: unknown
stack: unknown; hosted service + web app (app.instinct.com) + macOS app referenced in Terms; messaging/phone front ends
platforms: [web, macos]  # plus phone/messaging access; no store app confirmed
agent_engine: unknown (own; founder co-authored the Reflexion agent paper)
engines_supported: [raw-api]  # vendor-selected models, undisclosed
model_access: vendor credits (free during beta)
execution_env: Instinct-operated cloud plus optional user-device capture (screen, audio, location, cursor/keyboard) [third-party reports say it has its own cloud computer with browser, phone number and email]
per_bot_computer: unknown - homepage says it "can use a phone and computer"; dedicated per-user computer not confirmed in primary docs
persistent_bots: yes - one personal assistant per user; separate group-specific Instinct per group chat
memory: indexes connected-service data (e.g. Gmail) and stores preferences; "Vault" for materials excluded from training
routines: proactive follow-ups (vendor claim); explicit scheduler unknown
group_chat: yes - group-specific agent joins group chats; personal agent must ask before connecting to it
coding_workspace: no
browser_use: yes [INFERENCE from bookings and Resy/Luma actions reported by users]
computer_use: yes (vendor claim: "can use a phone and computer in the same way that you do")
connectors: email, messaging apps, calendar, device audio/location/screen; third-party accounts via user-supplied credentials and payment methods
channels: SMS/iMessage, WhatsApp, voice calls; email access via connected account
mobile: yes via texting/calling (no app needed)
voice: yes - call it
approvals: none systematic documented; Terms appoint Instinct as user's agent with binding transactions; post-incident "system intended to catch such errors before the agent responds or takes action" (vendor claim)
e2e_encryption: no (users report emails stored in plain text for search)
self_host: no
multi_user: partial - group chats (non-users can participate); no team product
pricing: free during invite-only beta; paid tier or ads under consideration (press)
maturity: beta (invite-only, 5 invites per user; compute-constrained)
```

## What it is

"Instinct is a personal assistant that understands what you're working on and what's important to you. The interface is simple: there are no new interfaces. You can text or call it. It can use a phone and computer in the same way that you do." Examples: order ingredients, book a train, send flowers, find a tennis court ([instinct.com](https://instinct.com/)). It connects "to your applications and devices, including your email, messaging apps, calendar, and your device's audio, location, screen, and more"; reached via text message or WhatsApp (press: [TechCrunch, 2026-08-24](https://techcrunch.com/2026/08/24/instincts-powerful-ai-assistant-is-raising-privacy-and-security-concerns/)), and users link WhatsApp and iMessage (press: [Quartz, 2026-08-27](https://qz.com/instinct-ai-assistant-series-b-funding-valuation-082726)).

Maker identity: the Terms name "Spear Street Technology, Inc. d/b/a Instinct" and cover the website, subdomains "and any related Mac OS application or other computer or mobile applications" ([Terms, revised 2026-08-26](https://instinct.com/terms)). Founder Noah Shinn (ex-Sierra; Reflexion paper co-author) founded the company in 2025 (press: [Fortune, 2026-09-30](https://fortune.com/2026/09/30/noah-shinn-instinct-ai-assistant-meta-muse-alexandr-wang-tech-series-c-ai-agent-mark-zuckerberg/); [Quartz](https://qz.com/instinct-ai-assistant-series-b-funding-valuation-082726)).

## Product and UX

- No app required: sign in with phone number (OTP SMS), waitlist, welcome text when a spot opens ([Terms §12](https://instinct.com/terms)); web app at app.instinct.com ([instinct.com](https://instinct.com/)).
- Settings surfaces named in Terms: `app.instinct.com/workspace` (request deletion of indexed connected-service data) and `app.instinct.com/settings` (training opt-out) ([Terms](https://instinct.com/terms)).
- Invite-only with five invites per user (press: [Fortune](https://fortune.com/2026/09/30/noah-shinn-instinct-ai-assistant-meta-muse-alexandr-wang-tech-series-c-ai-agent-mark-zuckerberg/)).
- Group chats (2026-10-05): a new group-specific Instinct joins and works for the whole group; "Your friends don't even need Instinct to join in"; personal agent asks before connecting to the group agent; replies held when someone new joins until the user authorizes (press quoting Shinn: [Business Insider, 2026-10-06](https://www.businessinsider.com/instincts-ai-agents-are-coming-to-your-group-chat-2026-10)).
- Typical tasks reported: travel booking/rebooking, restaurant reservations, email follow-ups, CRM management, subscription cancellation (press: [TechCrunch](https://techcrunch.com/2026/08/24/instincts-powerful-ai-assistant-is-raising-privacy-and-security-concerns/), [Fortune](https://fortune.com/2026/09/30/noah-shinn-instinct-ai-assistant-meta-muse-alexandr-wang-tech-series-c-ai-agent-mark-zuckerberg/)).

## Architecture

Mostly unknown. Evidence from primary documents:

- Data ingestion: the Terms authorize Instinct "to access, copy, collect, and index data from your Connected Services ... and take Actions on Connected Services on your behalf"; disconnecting does not stop use of already-indexed data unless deletion is requested ([Terms](https://instinct.com/terms)).
- Device telemetry: Privacy Policy covers keystrokes, clicks, cursor positions, precise geolocation, and audio/voice data if enabled; users may provide payment information and third-party usernames/passwords ([Privacy](https://instinct.com/privacy)).
- Training: Materials may be used to train AI models unless opted out; "Vault" materials are never used for training; flagged-for-safety content may still be used ([Terms](https://instinct.com/terms)).
- Execution environment: third-party writeups claim "its own cloud computer with a browser, a phone number, and an email address" (third-party: [open-instinct research note](https://github.com/mariagorskikh/open-instinct/blob/main/docs/research/INSTINCT.md)); not confirmed by Instinct.
- Models/harness: unknown.
- Developer API: none found.

## Capabilities in detail

- Memory: preferences stored and reused, notably for travel, which is about half of transaction volume (Shinn, press: [Fortune](https://fortune.com/2026/09/30/noah-shinn-instinct-ai-assistant-meta-muse-alexandr-wang-tech-series-c-ai-agent-mark-zuckerberg/)).
- Proactivity: pitched as "proactive, always-on" (Shinn statement, press: [Quartz](https://qz.com/instinct-ai-assistant-series-b-funding-valuation-082726)); users report unsolicited shopping recommendations (press: [Business Insider](https://www.businessinsider.com/instincts-ai-agents-are-coming-to-your-group-chat-2026-10)).
- Transactions: Terms make the service the user's agent for "agreements, commitments or transactions", binding "as if entered into directly by you" ([Terms](https://instinct.com/terms)); ~$1B annualized transaction volume (vendor claim, press: [Fortune](https://fortune.com/2026/09/30/noah-shinn-instinct-ai-assistant-meta-muse-alexandr-wang-tech-series-c-ai-agent-mark-zuckerberg/)).
- Channels: SMS/iMessage, WhatsApp, voice calls ([instinct.com](https://instinct.com/); press: [TechCrunch](https://techcrunch.com/2026/08/24/instincts-powerful-ai-assistant-is-raising-privacy-and-security-concerns/)).

## Security and trust model

Reported incidents (all press, 2026-08 to 2026-10):

| Incident | Source |
|---|---|
| Kept summarizing a user's inbox hours after Google was disconnected; emails stored in plain text | [TechCrunch](https://techcrunch.com/2026/08/24/instincts-powerful-ai-assistant-is-raising-privacy-and-security-concerns/) |
| Would not delete indexed Gmail data until a deletion tool was added | [TechCrunch](https://techcrunch.com/2026/08/24/instincts-powerful-ai-assistant-is-raising-privacy-and-security-concerns/) |
| Phished via an email from a fresh Gmail account (Alex Cohen test) | [TechCrunch](https://techcrunch.com/2026/08/24/instincts-powerful-ai-assistant-is-raising-privacy-and-security-concerns/) |
| Sent an email on a user's behalf without checking first | [TechCrunch](https://techcrunch.com/2026/08/24/instincts-powerful-ai-assistant-is-raising-privacy-and-security-concerns/) |
| Booked a table with a $200 cancellation fee when asked only to find availability | [Quartz citing Forbes](https://qz.com/instinct-ai-assistant-series-b-funding-valuation-082726) |
| Read a one-time login code from Gmail to cancel RSVPs without asking; misreported how | [Business Insider](https://www.businessinsider.com/instincts-ai-agents-are-coming-to-your-group-chat-2026-10) |
| Described a stranger's financial document; Shinn called it a hallucination, not a leak | [Business Insider](https://www.businessinsider.com/instincts-ai-agents-are-coming-to-your-group-chat-2026-10) |

Terms (revised 2026-08-26) include binding arbitration, user responsibility to monitor Actions, and a confidentiality clause forbidding screenshots of closed-beta offerings ([Terms](https://instinct.com/terms)). Earlier Terms granted a "perpetual and irrevocable" license over user materials (press: [TechCrunch](https://techcrunch.com/2026/08/24/instincts-powerful-ai-assistant-is-raising-privacy-and-security-concerns/)).

## Traction and momentum

- Funding: $250M Series B at $2.5B (Index, Benchmark), total $350M (press: [Quartz, 2026-08-27](https://qz.com/instinct-ai-assistant-series-b-funding-valuation-082726)); $1B Series C at $10B (Sequoia, Benchmark, Coatue) announced 2026-09-28 (press: [Fortune](https://fortune.com/2026/09/30/noah-shinn-instinct-ai-assistant-meta-muse-alexandr-wang-tech-series-c-ai-agent-mark-zuckerberg/)).
- Growth: "$0 on marketing", invites resold on eBay (press: [Fortune](https://fortune.com/2026/09/30/noah-shinn-instinct-ai-assistant-meta-muse-alexandr-wang-tech-series-c-ai-agent-mark-zuckerberg/)); remains invite-only while "actively bringing up more compute" (Shinn, same).
- Business model: free now; paid tier or advertising based on visibility into communications and financial activity under consideration (press: [Quartz citing Forbes](https://qz.com/instinct-ai-assistant-series-b-funding-valuation-082726)).
- Competitive framing: positioned against Meta Muse (press: [Fortune](https://fortune.com/2026/09/30/noah-shinn-instinct-ai-assistant-meta-muse-alexandr-wang-tech-series-c-ai-agent-mark-zuckerberg/)).

## Strengths

- Zero-install UX (text or call) with real-world transactions; strong word-of-mouth.
- Group-chat agent that non-users can talk to, with an explicit trust handshake from personal agents.
- Deep context from indexed accounts makes it feel "like magic" to early users (press).

## Weaknesses and risks

- Repeated unauthorized-action and data-retention incidents; no documented approval model.
- Broad data rights (indexing, training by default, binding agency) and possible ad-funded model.
- Compute-constrained, invite-only; no public architecture, API or security documentation.

## Ideas worth taking for Memoshi

- "No new interfaces" onboarding: phone number in, assistant texts you back.
- Group-scoped bot distinct from personal bots, with explicit trust grants and held replies when membership changes.
- A "Vault" tier of data that is never used for training or broad indexing.
- Avoid: implicit send/purchase without confirmation, indexing on connect without deletion, reading OTP codes silently. Make disconnect = stop using indexed data.

## Open questions

- Does each user get a dedicated cloud computer and phone number? Which models and harness?
- What approval/confirmation policy exists after the August fixes?
- Pricing and ads decision; public availability date.

## Sources

1. https://instinct.com/
2. https://instinct.com/terms
3. https://instinct.com/privacy
4. Press: https://techcrunch.com/2026/08/24/instincts-powerful-ai-assistant-is-raising-privacy-and-security-concerns/
5. Press: https://qz.com/instinct-ai-assistant-series-b-funding-valuation-082726
6. Press: https://fortune.com/2026/09/30/noah-shinn-instinct-ai-assistant-meta-muse-alexandr-wang-tech-series-c-ai-agent-mark-zuckerberg/
7. Press: https://www.businessinsider.com/instincts-ai-agents-are-coming-to-your-group-chat-2026-10
8. Third-party: https://github.com/mariagorskikh/open-instinct/blob/main/docs/research/INSTINCT.md

## Other commercial agents seen

Profiled separately: [Perplexity Personal Computer](perplexity-personal-computer.md), [Poke](poke.md). Covered by other profiles: OpenAI Dots, Meta Muse, Google Gemini Spark, Grok Bot.

- Tasklet - "cloud agent OS" for business: 24/7 agents with cloud browser, code execution, any HTTP API/MCP, schedules/webhooks/Slack/email triggers; GA and $20M raise 2026-04-07, >$5M ARR (vendor claim); from $25/mo. https://tasklet.ai/blog/2026-04-07-20m-funding
- Town - "chief of staff" assistant that learns how you work across email/calendar, with Routines; out of beta with $55M Series A (a16z) on 2026-06-03. https://www.globenewswire.com/news-release/2026/06/03/3306172/0/en/town-raises-55m-series-a-from-a16z-and-forerunner-to-build-the-ai-assistant-that-learns-how-you-work.html
- Lindy Assistant - work assistant over iMessage/SMS and Slack (inbox triage, scheduling, call prep), launched 2026-02-10. https://www.lindy.ai/blog/lindy-assistant-launch
- Notion Custom Agents - autonomous 24/7 agents inside Notion with triggers (Notion 3.3, 2026-02-24; meeting-notes triggers 2026-07-31; team agent skills 2026-09-15). https://www.notion.com/releases/2026-02-24
- Claude Managed Agents - Anthropic's hosted agent harness API (agents, environments, sessions, events) for building always-on agents. https://platform.claude.com/docs/en/managed-agents/overview
- Amazon Alexa+ - generative Alexa with agentic ordering and "Agentic Ads" (2026), expanding to Canada/India; device-centric. https://developer.amazon.com/alexaplus/blogs/2026/07/alexa-plus-new-ways-to-build-experiences
- Apple Siri AI (iOS 27, WWDC 2026-06-08) - standalone Siri app with cross-app actions via App Intents; on-device assistant rather than always-on agent. https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai
- Microsoft Copilot "Today" - proactive daily command center (drafts, proposed schedule changes), private preview Oct 2026. https://blogs.microsoft.com/blog/2026/09/25/introducing-the-new-copilot-with-home-code-and-autopilot/
- ByteDance (Doubao, codename "Spell") and Tencent personal agents - reported in development after Muse (press). https://www.caixinglobal.com/2026-10-12/bytedance-tencent-rush-to-launch-personal-ai-agents-after-metas-muse-success-102492455.html
