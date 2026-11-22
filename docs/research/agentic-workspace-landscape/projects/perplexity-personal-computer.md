# Perplexity Personal Computer

> Perplexity's cloud agent ("Computer", multi-model teams of agents with 400+ connectors) extended onto the user's own Mac: the Perplexity macOS app runs continuously, ideally on a dedicated Mac mini, controlling local files, native apps and the Comet browser, remotely steerable from iPhone, with a hybrid local-model privacy gate. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Perplexity Personal Computer (Perplexity Computer on Mac)
slug: perplexity-personal-computer
category: closed-hosted-agents
maker: Perplexity AI
license: proprietary
repo: none
website: https://www.perplexity.ai/personal-computer
first_public: 2026-03-12 (announced at Ask 2026, waitlist); available to all Mac users 2026-05-07
latest_release: Hybrid compute on Mac (local models + privacy gate), 2026-09-01
release_cadence: unknown (major features roughly monthly per blog)
stars: n/a (closed)
forks: n/a
contributors: n/a
primary_language: unknown
stack: Perplexity macOS app (macOS 15+) + Comet browser + Perplexity cloud "Computer" sandbox; optional local models (Gemma 4 E4B, Qwen3.6 35B-A3B, Perplexity model) on Apple silicon with >=24GB
platforms: [macos, ios, web]
agent_engine: own loop (Perplexity Computer harness orchestrating 20+ frontier models)
engines_supported: [raw-api]  # Perplexity-routed frontier models + local models
model_access: vendor credits (Pro/Max subscription credits); local models for hybrid compute
execution_env: user's Mac (local files/apps, "isolated sandbox environment" for actions) + secure development sandbox on Perplexity servers
per_bot_computer: partial - the user's own Mac mini acts as the always-on agent computer; cloud sandbox per task
persistent_bots: no - one Computer; it spins up "teams of agents" per objective
memory: personal context across tasks (vendor claim; mechanism unknown)
routines: monitors triggers and executes proactive tasks around the clock (press); scheduler details unknown
group_chat: no
coding_workspace: partial - writes/runs code in cloud sandbox; local file read/write
browser_use: yes - drives local Comet browser
computer_use: yes - operates Mail, Finder, Messages, Notes, Slack and any native Mac app
connectors: 400+ connectors (Gmail, Slack, GitHub, Notion, Salesforce...) plus Comet for sites without connectors
channels: Perplexity apps (Mac taskbar shortcut, iPhone remote); Slack for enterprise Computer
mobile: yes - start tasks and approve human-in-the-loop requests from iPhone
voice: yes - voice mode on Mac
approvals: on-device authorization for sensitive steps; human-in-the-loop approvals from any device; kill switch and audit trail (press); hybrid privacy gate masks/keeps local/refuses/asks consent before data leaves the Mac
e2e_encryption: no (hybrid mode keeps classified-sensitive data on device)
self_host: partial - runs on user hardware but requires Perplexity cloud and account
multi_user: partial - Enterprise admin rules for hybrid data egress and audits
pricing: initially Max-only ($200/mo, 10,000 credits, press); since 2026-05-07 in the Mac app with Pro/Max credit usage; hybrid compute on Pro, Max, Enterprise
maturity: GA on macOS (2026-05-07)
```

## What it is

Perplexity Computer (launched 2026-02-25) is "a system for turning a question into autonomous and continuously working teams of agents"; Personal Computer "takes Computer out of the cloud-only world and onto the device where most of your real work already takes place" ([Perplexity blog, 2026-05-07](https://www.perplexity.ai/hub/blog/personal-computer-is-available-to-all-mac-users)). "Computer now runs 24/7 on your Mac mini in the Perplexity Mac App" ([product page](https://www.perplexity.ai/personal-computer)). Announced at Ask 2026 as software, not hardware: "The Mac mini acts as the always-on host" (press: [TNW, 2026-03-12](https://thenextweb.com/news/perplexity-personal-computer-enterprise)).

## Product and UX

- One keyboard shortcut summons a taskbar anywhere on the Mac; context-aware of the active app; voice mode ([product page](https://www.perplexity.ai/personal-computer)).
- Start a task on iPhone that uses Mac files/apps; "Approve a human-in-the-loop request from any of your devices" ([blog](https://www.perplexity.ai/hub/blog/personal-computer-is-available-to-all-mac-users)).
- Can produce live dashboards instead of documents ([blog](https://www.perplexity.ai/hub/blog/personal-computer-is-available-to-all-mac-users)).
- Hybrid: model selector > "hybrid" > choose local and cloud models ([hybrid blog, 2026-09-01](https://www.perplexity.ai/hub/blog/introducing-hybrid-compute-on-mac)).

## Architecture

- Split execution: local files and native Mac apps on the device; "tools, files, 400+ connectors, and personal context in a secure development sandbox on Perplexity servers"; Comet drives web tools without connectors ([blog](https://www.perplexity.ai/hub/blog/personal-computer-is-available-to-all-mac-users)).
- Actions run "in an isolated sandbox environment, with on-device authorization protecting sensitive steps"; always-on mode "secured with 2FA" ([product page](https://www.perplexity.ai/personal-computer)).
- Model orchestration across "20+ frontier models" ([product page](https://www.perplexity.ai/personal-computer)); harness described as "model-agnostic" ([blog](https://www.perplexity.ai/hub/blog/personal-computer-is-available-to-all-mac-users)).
- Hybrid compute: cloud does reasoning, search and planning; a local model processes private files; an on-device classifier identifies names, addresses, account numbers and secrets, and the privacy gate can "mask sensitive details, keep it local, refuse the action, or ask for consent" ([hybrid blog](https://www.perplexity.ai/hub/blog/introducing-hybrid-compute-on-mac)).
- Developer surface: usage-based Computer API from February; new APIs at Ask 2026 (press: [TNW](https://thenextweb.com/news/perplexity-personal-computer-enterprise)); details unknown.

## Capabilities in detail

- Local file read/write/search in connected folders; native app control (Mail, Finder, Messages, Notes, Slack); Comet browser automation ([product page](https://www.perplexity.ai/personal-computer)).
- Always-on: teams of agents run continuously from a central Mac mini ([blog](https://www.perplexity.ai/hub/blog/personal-computer-is-available-to-all-mac-users)); trigger monitoring and proactive tasks (press: [TNW](https://thenextweb.com/news/perplexity-personal-computer-enterprise)).
- Enterprise: admin rules for what must stay on the Mac / be masked / need approval, plus audits of data leaving the device ([hybrid blog](https://www.perplexity.ai/hub/blog/introducing-hybrid-compute-on-mac)).

## Security and trust model

Approvals for sensitive actions, full session audit trail and a kill switch (press: [TNW](https://thenextweb.com/news/perplexity-personal-computer-enterprise)); on-device authorization and sandboxed actions ([product page](https://www.perplexity.ai/personal-computer)); privacy gate for hybrid ([hybrid blog](https://www.perplexity.ai/hub/blog/introducing-hybrid-compute-on-mac)). Incidents specific to Personal Computer: none found as of 2026-10-20.

## Traction and momentum

Launch sequence: Computer 2026-02-25, Personal Computer waitlist 2026-03-12, GA in new Mac app 2026-05-07, hybrid compute 2026-09-01 ([hybrid blog and related posts](https://www.perplexity.ai/hub/blog/introducing-hybrid-compute-on-mac)). Initial access was Max-only at $200/month with 10,000 credits (press: [TNW](https://thenextweb.com/news/perplexity-personal-computer-enterprise)); credit usage now tied to Pro/Max subscriptions ([blog](https://www.perplexity.ai/hub/blog/personal-computer-is-available-to-all-mac-users)). User counts unknown.

## Strengths

- "Bring your own always-on box" (Mac mini) avoids hosting a VM per user while still being 24/7.
- Hybrid local/cloud with an explicit, classifier-driven privacy gate and admin egress policy.
- Native macOS app control plus browser plus 400+ connectors.

## Weaknesses and risks

- Mac-only; best experience needs dedicated hardware left on.
- Credit-metered; no persistent named bots or multi-bot collaboration.
- Not in the Mac App Store (direct download) ([blog](https://www.perplexity.ai/hub/blog/personal-computer-is-available-to-all-mac-users)).

## Ideas worth taking for Memoshi

- Support a user-owned always-on host (Mac mini/home server) as an execution target alongside cloud VMs.
- Privacy gate between local data and cloud models: classify, mask, keep local, refuse or ask.
- Cross-device approvals: human-in-the-loop prompts answerable from phone.
- Global hotkey taskbar with active-app context.

## Open questions

- Persistent memory design and trigger/scheduler UI for Personal Computer.
- How the cloud sandbox and local Mac sessions share state and credentials.

## Sources

1. https://www.perplexity.ai/personal-computer
2. https://www.perplexity.ai/hub/blog/personal-computer-is-available-to-all-mac-users
3. https://www.perplexity.ai/hub/blog/introducing-hybrid-compute-on-mac
4. Press: https://thenextweb.com/news/perplexity-personal-computer-enterprise
