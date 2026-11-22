# Meta Muse

> Meta's free-tier consumer personal agent: one named, avatar-bearing agent per person living in a dedicated cloud VM, guarded by a separate host-side "Sentinel" that owns all egress and connector permissions; reachable in the Muse app, WhatsApp and a Mac app. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Meta Muse
slug: meta-muse
category: closed-hosted-agents
maker: "Meta (Meta Superintelligence Labs)"
license: proprietary
repo: "none for the agent; open-source gadget SDK at github.com/facebookincubator/muse-gadget-sdk; Muse Code SDK at github.com/meta-models/muse-code-sdk (MIT)"
website: https://muse.ai
first_public: 2026-09-08
latest_release: "no public version numbers; Muse Wonder models announced 2026-10-12"
release_cadence: "weekly-scale feature drops (Canada + Mac 2026-09-18, Small Business 2026-09-29, gadgets 2026-10-02)"
stars: n/a
forks: n/a
contributors: n/a
primary_language: unknown
stack: "Muse Spark 1.3 model; per-user Linux VM; 'Hatch' harness in systemd-nspawn cell; host-side Sentinel, authd, privsep workers, hatch-safety classifiers; Postgres state; eBPF egress control; Chromium behind CDP broker"
platforms: [ios, android, web, macos]
agent_engine: "own harness ('Hatch' daemon) with subagent swarms and crons"
engines_supported: ["meta-internal (Muse Spark 1.3)"]
model_access: "vendor service only (free tier + Muse subscription)"
execution_env: "dedicated per-user cloud VM (Muse Secure VM); Mac app acts in native macOS apps"
per_bot_computer: "yes - isolated Linux VM with browser, filesystem, terminal, enough CPU/RAM to compile code"
persistent_bots: "yes - one personal Muse per user with name and custom avatar; side chats for separate contexts"
memory: "persistent memory files the user can read and edit; 'forget' on request"
routines: "yes - schedules (crons) and event-triggered background work; Goals tab tracks long-running plans"
group_chat: "no - single agent per user; internal subagents only"
coding_workspace: "partial - agent writes code and builds its own tools in the VM; no user-facing IDE (separate Muse Code CLI for developers)"
browser_use: "yes - Chromium via CDP broker; subagent sees accessibility tree; user can watch and take over"
computer_use: "partial - cloud VM shell and browser; Mac app operates files, Mail, Messages, Calendar, Notes"
connectors: "built-in connectors (Meta apps, email, business tools such as Shopify, Stripe, Slack, Notion, QuickBooks), custom connectors, agent-written connectors; partner program"
channels: "Muse app (iOS/Android/web), WhatsApp, macOS app; AI glasses 'coming soon'; DIY gadgets via SDK"
mobile: yes
voice: "partial - cloud dictation in Mac app; voice calling unknown"
approvals: "Sentinel decides allow/deny/ask for every connector action and network request; grants one-time/session/task/time-bounded/perpetual; tainted-egress tracking"
e2e_encryption: "no today; Muse Confidential VM with user-held key promised 'later this year' (vendor claim)"
self_host: no
multi_user: "no - personal accounts; Muse for Small Business adds business connectors, not shared team agents"
pricing: "Free with weekly limit; Power $20/mo (500M Muse tokens/week); Max $100/mo (3B tokens/week)"
maturity: "beta - consumer launch 2026-09-08 in US (Canada 2026-09-18); help center still says 'limited testing'"
```

## What it is

Muse is "a secure, private personal AI agent that proactively helps with people's goals and suggests ideas", running on "Muse Secure VM, a dedicated, virtual machine (VM) that houses both the agent and a person's data", powered by Muse Spark ([Meta Newsroom](https://about.fb.com/news/2026/09/introducing-muse-personal-ai-agent/)). The mental model is messaging a person: "talking to it works just like messaging another person, in the Muse app or directly in WhatsApp" (ibid.). Target user is the mass consumer ("built to work for billions"), with a Small Business extension from 2026-09-29 ([Meta Newsroom](https://about.fb.com/news/2026/09/introducing-muse-small-business/)). Press reported Muse is "modeled on the open-source AI agent OpenClaw" ([Fox Business, press](https://www.foxbusiness.com/technology/meta-introduces-muse-personal-ai-agent-can-send-emails-book-travel)).

## Product and UX

- One long main conversation, interruptible, multiple tasks in flight; side chats added after testing; chat bubbles because proactive messages arrive out of turn ([How We Designed Muse](https://introducing.muse.ai)).
- User-designed avatar and name ("Veda" in the designers' example) are "one of the core features people light up about most" (ibid.).
- Transparency: status snippet under the avatar, full activity log and approved permissions on tap, readable/editable Memory files (ibid.).
- Goals tab for long-running plans; Ideas tab with generated suggestions to beat the "where do I start" problem (ibid.).
- Artifacts: interactive outputs (itineraries, dashboards) that live outside the chat (ibid.).
- Deterministic UI where conversation is not enough: structured approval cards and secure credential capture (ibid.).
- Payments: Link by Stripe one-time cards with Link purchase protections; Shop Pay and 1Password "coming soon" ([Meta Newsroom](https://about.fb.com/news/2026/09/introducing-muse-personal-ai-agent/)).

## Architecture

From Meta's security write-up ([How We Built Safety Into Muse](https://research.meta.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse)):

```
clients (iOS/Android/web) --secure transport--> per-user VM
  runtime cell (systemd-nspawn, Debian rootfs, unprivileged root, filtered syscalls)
    Hatch daemon (harness), workspace files, tools, subagents, crons
  host-side services (separate systemd units)
    hatch-safety  - classifiers on model I/O, prompt-injection detection
    privsep       - executes built-in connector logic with scoped creds
    hatch-authd   - credential store + surrogate tokens
    Sentinel      - sole authority for connector actions and network egress
    postgres      - durable app state
    proxies       - inference + telemetry egress
  IPC: Unix sockets with SO_PEERCRED and peer ACLs
```

- "Hatch is our internal name for Muse in the codebase" (ibid.).
- Network: forward proxy with userns/veth and eBPF; Sentinel inspects L4 and L7 (host, resolved IP, method, path, decoded request), blocks SSRF, inserts real credentials just-in-time in place of surrogate tokens (ibid.).
- "Tainted egress": eBPF cgroup programs plus custom LSM hooks mark a process tainted once it reads user data; tainted processes lose auto-allow (ibid.).
- Browser: separate CDP broker; browser subagent sees an accessibility-tree snapshot, cannot run page JS, devtools disabled; agent paused during takeover or credential fill (ibid.).
- Connectors: CLIs in the cell only marshal args and file descriptors to privsep workers; each worker has a credential allowlist; email connector filters OTPs, reset links and magic links (ibid.).
- Data: VM is the system of record, continuously backed up; trajectories sanitized and used for training by default with an opt-out (ibid.).
- Developer surface: no public Muse agent API found. Adjacent: Meta Model API and the Muse Code CLI with a versioned session protocol (`muse serve`, `@muse-code/sdk`) ([Muse Code docs](https://dev.meta.ai/docs/muse-code.md)); partner connector program at muse.ai/platform ([Meta Newsroom](https://about.fb.com/news/2026/09/introducing-muse-small-business/)); open-source gadget SDK for ESP32/Raspberry Pi ([The Verge, press](https://www.theverge.com/tech/1004330/meta-muse-ai-gadgets-home-link)).

## Capabilities in detail

- Agentic work: browse, fill forms, "negotiate on their behalf", purchase, and keep working after the app closes ([Meta Newsroom](https://about.fb.com/news/2026/09/introducing-muse-personal-ai-agent/)); "launches swarms of subagents, builds its own tools, and edits itself" (vendor claim, [security post](https://research.meta.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse)).
- Routines: works "on a schedule and in response to relevant events", notifies only when something is meaningfully new ([How We Designed Muse](https://introducing.muse.ai)).
- Connectors: Meta apps (Instagram, Facebook), email, plus Asana, Box, Canva, Dropbox, Figma, Granola, HighLevel, QuickBooks, Klaviyo, Lovable, Notion, Shopify, Slack, Stripe, Zoom; custom connectors; Muse can write connectors for APIs/CLIs ([Small Business post](https://about.fb.com/news/2026/09/introducing-muse-small-business/), [security post](https://research.meta.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse)).
- Mac app (2026-09-18): acts across files, Mail, Messages, Calendar and Notes in native apps ([TechCrunch, press](https://techcrunch.com/2026/09/18/metas-muse-hits-mac-letting-the-ai-take-actions-on-your-computer/)).
- Hardware: Muse Home Link giveaway (5,000 units) and DIY gadgets ([The Verge, press](https://www.theverge.com/tech/1004330/meta-muse-ai-gadgets-home-link)).
- Muse Code (separate product, 2026-08 early beta): terminal/CI coding agent on Muse Spark 1.2, approvals and OS sandbox on by default, subagents, skills, hooks, MCP, session messaging between local sessions; four subscription plans with "Contributor mode" (more usage in exchange for training data) on by default ([Muse Code docs](https://dev.meta.ai/docs/muse-code.md), [subscriptions](https://dev.meta.ai/docs/muse-code/subscriptions)). Not integrated into the consumer Muse app as far as found.

## Security and trust model

- Sentinel is "the sole permission authority"; approvals are "strict capabilities, not conversational suggestions", answered in client UI outside the chat ([security post](https://research.meta.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse)).
- Read/write separation per connector and finer-than-OAuth action controls (ibid.).
- Bug bounty up to $300,000, including $130,000 for single-user prompt injection (ibid.).
- Data: not shared with ad systems, but agent browsing appears as the user's activity and can influence ads (ibid.). Meta can still access data operationally until Confidential VM ships (ibid.).
- Incidents: Mac-app local privilege escalation via undocumented settings redirecting transcription, found by Patrick Wardle, hotfixed ([The Verge, press](https://www.theverge.com/tech/998679/meta-muse-patch-zero-day-exploit-ai-agent), 2026-09-22); Muse shared a user's home address with a Marketplace contact ([PCMag, press](https://me.pcmag.com/en/security/38187/metas-muse-ai-agent-shared-someones-address-without-their-permission), 2026-09-29); report of a pre-launch "breakout bug" fix ([The Verge, press](https://www.theverge.com/tech/1004781/meta-reportedly-made-a-mad-dash-to-fix-a-muse-ai-breakout-bug-weeks-before-launch), 2026-10-05); Amazon blocked Muse from its store ([Fortune, press](https://fortune.com/2026/09/22/metas-muse-ai-is-exploding-in-popularity-and-drawing-heated-backlash/)).

## Traction and momentum

- Topped the US App Store free chart in its second week; first-12-day downloads reportedly outpaced ChatGPT's 12-day US/Canada debut ([Fortune, press](https://fortune.com/2026/09/22/metas-muse-ai-is-exploding-in-popularity-and-drawing-heated-backlash/), [The Verge, press](https://www.theverge.com/tech/998679/meta-muse-patch-zero-day-exploit-ai-agent)).
- Availability: US at launch (iOS, Android, web) ([Meta Newsroom](https://about.fb.com/news/2026/09/introducing-muse-personal-ai-agent/)); Canada from 2026-09-18 ([iPhone in Canada, press](https://www.iphoneincanada.ca/2026/09/18/metas-muse-ai-agent-is-now-available-in-canada/)); no EU/UK date found.
- Pricing: free with refreshing limit; Power $20/month (500M Muse tokens/week); Max $100/month (3B/week) ([Meta Help Center](https://www.meta.com/help/subscriptions/1021145227643680/)). Separate Meta One bundles (Core $7.99, Premium $19.99) cover broader Meta AI usage ([TechCrunch, press](https://techcrunch.com/2026/09/15/meta-expands-subscription-push-with-new-ai-focused-plans/)).
- Models: Muse Wonder and Wonder Full announced 2026-10-12 ([Meta Newsroom related link](https://about.fb.com/news/2026/10/introducing-muse-wonder-models/)); whether the consumer agent switched to Wonder: unknown.

## Strengths

- Most detailed public security architecture in the category; deterministic enforcement (Sentinel, surrogate credentials, taint tracking) rather than model-only safeguards.
- Free tier and WhatsApp distribution give the widest consumer reach.
- Strong consumer UX patterns: avatar identity, Goals, Ideas, Artifacts, editable memory.

## Weaknesses and risks

- Early incidents (Mac 0-day, address disclosure) despite the architecture; prompt injection is acknowledged as open.
- Training on sanitized trajectories by default; Meta can access VM data until Confidential VM ships.
- Personal-only: no shared team agents or multi-agent rooms.
- Platform friction: Amazon block shows commerce sites may refuse consumer agents.
- US/Canada only.

## Ideas worth taking for Memoshi

- Two security domains per agent computer: untrusted runtime cell vs. host-side credential/egress authority the agent cannot modify.
- Surrogate tokens swapped in at the network boundary so the model never holds real secrets.
- Taint-based approval: auto-allow egress only from processes that have not read user data; cuts approval fatigue.
- Approval scopes (one-time, session, task, time-bounded, perpetual) presented by the authority, not by the agent.
- Email connector that strips OTPs and reset links before the agent sees mail.
- Editable memory files plus a Goals view and an Ideas feed for onboarding.
- Proactive-message bar: notify only when meaningfully new; let the user dial proactivity up/down.

## Open questions

- Does Muse expose any developer API for third-party apps to message or task a user's Muse? Watch muse.ai/platform.
- Model behind the agent after Muse Wonder (2026-10-12): check Meta Newsroom and dev.meta.ai model docs.
- Confidential VM ship date and audit details: muse-security@meta.com, Meta Newsroom.
- Free-tier weekly token amount: not published by Meta (third parties claim 100M; unverified).

## Sources

1. https://about.fb.com/news/2026/09/introducing-muse-personal-ai-agent/
2. https://research.meta.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse (security.muse.ai)
3. https://introducing.muse.ai (How We Designed Muse)
4. https://about.fb.com/news/2026/09/introducing-muse-small-business/
5. https://www.meta.com/help/subscriptions/1021145227643680/ (About Muse subscriptions)
6. https://dev.meta.ai/docs/muse-code.md
7. https://dev.meta.ai/docs/muse-code/subscriptions
8. https://about.fb.com/news/2026/10/introducing-muse-wonder-models/
9. https://www.theverge.com/tech/998679/meta-muse-patch-zero-day-exploit-ai-agent (press)
10. https://www.theverge.com/tech/1004330/meta-muse-ai-gadgets-home-link (press)
11. https://www.theverge.com/tech/1004781/meta-reportedly-made-a-mad-dash-to-fix-a-muse-ai-breakout-bug-weeks-before-launch (press)
12. https://fortune.com/2026/09/22/metas-muse-ai-is-exploding-in-popularity-and-drawing-heated-backlash/ (press)
13. https://me.pcmag.com/en/security/38187/metas-muse-ai-agent-shared-someones-address-without-their-permission (press)
14. https://techcrunch.com/2026/09/18/metas-muse-hits-mac-letting-the-ai-take-actions-on-your-computer/ (press)
15. https://techcrunch.com/2026/09/15/meta-expands-subscription-push-with-new-ai-focused-plans/ (press)
16. https://www.iphoneincanada.ca/2026/09/18/metas-muse-ai-agent-is-now-available-in-canada/ (press)
17. https://www.foxbusiness.com/technology/meta-introduces-muse-personal-ai-agent-can-send-emails-book-travel (press)
