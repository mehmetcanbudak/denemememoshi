# Cue by Manus

> A consumer app for a roster of personal agents, each provisioned with its own email address, phone number, wallet and cloud computer, that can be texted over iMessage/Telegram/LINE/Slack, grouped into multi-agent chats, and run automations; built on Manus's agent infrastructure. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Cue by Manus
slug: manus-cue
category: closed-hosted-agents
maker: Manus AI (Butterfly Effect Pte. Ltd., Singapore)
license: proprietary
repo: none
website: https://cue.im
first_public: 2026-09-28
latest_release: Android app updated 2026-10-19 (Google Play listing)
release_cadence: unknown (Play listing shows bug-fix updates)
stars: n/a (closed)
forks: n/a
contributors: n/a
primary_language: unknown
stack: Manus infrastructure; Cascade agent harness (Manus 2.0); per-agent cloud computer; web, desktop (macOS/Windows) and mobile clients
platforms: [web, macos, windows, android, ios]  # iOS "coming soon after App Store review" at launch
agent_engine: own loop (Manus Cascade harness)
engines_supported: [raw-api]  # Manus-selected models; none user-pluggable
model_access: vendor credits (Cue weekly allowance; Plus membership included free with invite)
execution_env: cloud VM per agent ("its own computer")
per_bot_computer: yes
persistent_bots: yes - each agent has an identity (email, phone number, wallet, computer)
memory: "Memory and Dream" remember preferences, habits, plans (vendor claim; mechanism unknown)
routines: scheduled and event/condition-triggered automations
group_chat: yes - several agents in a group chat with a shared goal hand work to each other
coding_workspace: no (coding lives in Manus Studio, not Cue)
browser_use: yes [INFERENCE: via own computer; Manus core capability]
computer_use: yes - own cloud computer; Manus Remote Control/Computer Use separately drives the user's own desktop
connectors: native app connections (email, calendar, messaging) with per-app permissions; QR-code service agents at supported merchants
channels: iMessage, Telegram, LINE, Slack (messenger integrations); agent phone number for calls/SMS; agent email
mobile: yes (Android 10K+ installs; iOS pending at launch)
voice: yes - agent "can take your calls and leave you a summary"
approvals: purchases and payments require user confirmation; budget caps on the wallet; per-app permission grants
e2e_encryption: no (Play data-safety: encrypted in transit only)
self_host: no
multi_user: partial - personal teams of agents; group chats with humans unknown
pricing: free in early access with invite code; Plus membership included; phone-number subscription billed separately and counts against a Cue weekly allowance
maturity: beta (invite-only early access since 2026-09-28)
```

## What it is

Cue is "a new standalone app for your personal agents, on your phone and desktop, built on the same infrastructure as Manus" ([Manus blog, 2026-09-28](https://manus.im/en/blog/introducing-manus-2-0)). The mental model is contacts: "In Cue, each agent has its own email, phone number, wallet, and computer, so it can send messages, pay within the budget you set, and see a task through on its own machine. It can also take your calls and leave you a summary in Cue" ([same](https://manus.im/en/blog/introducing-manus-2-0)). Target is consumers ("From choosing a coffee and planning a trip to organizing your day", [Google Play](https://play.google.com/store/apps/details?id=ai.manus.agents&hl=en)).

Cue launched together with Manus 2.0 (Cascade harness, Manus Studio, Cloud Computer, event-triggered Automations, Remote Control) ([Manus help center](https://help.manus.im/en/articles/17190150-what-is-new-in-manus-2-0)). Context: Meta agreed to buy Manus at the end of 2025 and Beijing ordered the deal cancelled; Manus is now Singapore-based and independent (press: [TNW, 2026-09-29](https://thenextweb.com/news/manus-2-0-cue-ai-agents-email-phone-wallet)).

## Product and UX

- Onboarding: invite code required; Manus users open the "Agents (Cue!)" sidebar tab and scan a QR code to download ([help center](https://help.manus.im/en/articles/17190150-what-is-new-in-manus-2-0)); launch code MEETCUE for a limited number of users ([Manus blog](https://manus.im/en/blog/introducing-manus-2-0)).
- Teams of agents: "a Marketing channel can have three agents: One researches venues, Another turns the research into a shortlist, A third drafts a deck"; or keep a single personal assistant ([help center](https://help.manus.im/en/articles/17190150-what-is-new-in-manus-2-0)).
- Per-agent settings: Agent Info > Integration > Messenger toggles each connected messaging platform on/off ([help center](https://help.manus.im/en/articles/14178640-can-i-connect-multiple-messaging-agents-at-once-in-cue)).
- In-person services: scan a merchant's QR code to create a dedicated Cue for that service that browses the menu and orders; "You confirm the payment" ([Google Play](https://play.google.com/store/apps/details?id=ai.manus.agents&hl=en)).
- Automations can be created conversationally ("describing what you want done and when") ([help center](https://help.manus.im/en/articles/17190150-what-is-new-in-manus-2-0)).

## Architecture

- Components: Cue clients (web, macOS, Windows, Android, iOS pending) ([cue.im](https://www.cue.im/), [Manus blog](https://manus.im/en/blog/introducing-manus-2-0)); Manus backend with the Cascade harness that "brings in specialized capabilities only when the work needs them" and in one configuration used 23.2% fewer tokens and cost 32% less (vendor claim, [Manus blog](https://manus.im/en/blog/introducing-manus-2-0)).
- Execution: each agent has its own computer ([help center](https://help.manus.im/en/articles/17190150-what-is-new-in-manus-2-0)); sizing, persistence and OS unknown.
- Identity provisioning: per-agent email, phone number, wallet; phone number is a separate subscription whose usage counts toward a Cue weekly allowance rather than Manus credits ([pricing help](https://help.manus.im/en/articles/11711111-what-is-the-current-membership-pricing-for-manus)).
- Models: unknown (not disclosed).
- Extension surface/API: Manus has a public API ([open.manus.ai](https://open.manus.ai/docs)), but no Cue-specific API found (unknown).

## Capabilities in detail

- Persistent agents with identity: yes (above).
- Memory: "Memory and Dream help Cue remember your food preferences, travel habits, learning progress, and the plans you want to stick with" ([Google Play](https://play.google.com/store/apps/details?id=ai.manus.agents&hl=en), vendor claim). "Dream" suggests offline memory consolidation [INFERENCE].
- Routines: "Automations can run on a schedule or respond to supported events and conditions" ([Google Play](https://play.google.com/store/apps/details?id=ai.manus.agents&hl=en)).
- Multi-agent: group chat with shared goal and handoffs ([Manus blog](https://manus.im/en/blog/introducing-manus-2-0)).
- Channels: iMessage, Telegram, LINE, Slack; multiple simultaneously per agent ([help center](https://help.manus.im/en/articles/14178640-can-i-connect-multiple-messaging-agents-at-once-in-cue)).
- Voice/phone: takes calls on the user's behalf and summarizes ([Manus blog](https://manus.im/en/blog/introducing-manus-2-0)).
- Payments: wallet with user-set budget; bookings and payments "after you confirm" ([Google Play](https://play.google.com/store/apps/details?id=ai.manus.agents&hl=en)).

## Security and trust model

- Approvals: payment confirmation, budgets, per-app permission grants revocable "at any time" ([Google Play](https://play.google.com/store/apps/details?id=ai.manus.agents&hl=en)).
- Data: Play data-safety says data may be shared with third parties (personal info, device IDs), collected types include financial info; encrypted in transit; deletion on request ([Google Play](https://play.google.com/store/apps/details?id=ai.manus.agents&hl=en)).
- Team plan offers data-training opt-out; consumer opt-out for Cue unknown ([pricing help](https://help.manus.im/en/articles/11711111-what-is-the-current-membership-pricing-for-manus)).
- Jurisdiction/regulatory risk: China-blocked Meta acquisition and a new China-market team (press: [TNW](https://thenextweb.com/news/manus-2-0-cue-ai-agents-email-phone-wallet)).
- Incidents: none specific to Cue found as of 2026-10-20.

## Traction and momentum

- Google Play (as of 2026-10-20): 10K+ downloads, 4.7 stars from ~2.5K reviews, mixed reviews ("literally not even working" vs daily use) ([Google Play](https://play.google.com/store/apps/details?id=ai.manus.agents&hl=en)).
- Coverage: Bloomberg 2026-09-28 (press, [Bloomberg](https://www.bloomberg.com/news/articles/2026-09-28/manus-expands-ai-tools-in-renewed-push-into-agent-market)), framed as a response to Meta Muse (press: [TNW](https://thenextweb.com/news/manus-2-0-cue-ai-agents-email-phone-wallet)).
- Pricing: free during invite-only early access with Plus included ([Google Play](https://play.google.com/store/apps/details?id=ai.manus.agents&hl=en)); Manus core plans Free / Pro from $20 / Pro from $40 / Team from $20 per seat ([pricing help](https://help.manus.im/en/articles/11711111-what-is-the-current-membership-pricing-for-manus)).

## Strengths

- Most literal "agent as a person" provisioning: inbox, phone line, wallet, computer per agent.
- Multi-agent group chat with handoffs is a shipped consumer feature, not a demo.
- Broad channel coverage including LINE and Slack, multiple per agent.
- Reuses a mature agent backend (Manus) and its automations engine.

## Weaknesses and risks

- Invite-gated, iOS lagging at launch, early reliability complaints.
- Regulatory/ownership overhang (Meta deal blocked by China); data-sharing disclosures on Play.
- Opaque internals: models, memory mechanism, computer lifecycle undisclosed.
- Payments and phone numbers expand fraud/abuse surface [INFERENCE].

## Ideas worth taking for Memoshi

- Per-bot provisioned identity (email + phone + wallet + computer) as a packaged "hire" step; separately metered phone line.
- Wallet with a user-set budget plus confirmation, rather than raw card access.
- Multi-messenger binding per bot with simple on/off toggles.
- Ephemeral service agents spawned from a merchant QR code: a scoped bot for one transaction.
- Conversational creation of automations ("describe what and when").
- "Dream" style offline memory consolidation pass [INFERENCE].

## Open questions

- Does each agent's computer persist between tasks, and what OS/browser does it run?
- How do group-chat agents share memory and permissions?
- Which models power Cue, and is there a developer API? (Check Manus docs/API once Cue leaves early access.)
- Final pricing after early access.

## Sources

1. https://manus.im/en/blog/introducing-manus-2-0
2. https://help.manus.im/en/articles/17190150-what-is-new-in-manus-2-0
3. https://help.manus.im/en/articles/14178640-can-i-connect-multiple-messaging-agents-at-once-in-cue
4. https://help.manus.im/en/articles/11711111-what-is-the-current-membership-pricing-for-manus
5. https://play.google.com/store/apps/details?id=ai.manus.agents&hl=en
6. https://www.cue.im/
7. https://open.manus.ai/docs
8. Press: https://thenextweb.com/news/manus-2-0-cue-ai-agents-email-phone-wallet
9. Press: https://www.bloomberg.com/news/articles/2026-09-28/manus-expands-ai-tools-in-renewed-push-into-agent-market
