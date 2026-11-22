# Microsoft Scout / Autopilot

> Microsoft's OpenClaw-derived "always-on personal agent" for Microsoft 365: shipped first (2026-06-02) as the Scout desktop app for Frontier tenants, renamed Autopilot on 2026-09-25 and moved to a cloud-hosted, tenant-resident agent with its own Entra identity, memory, computer and workspace. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: Microsoft Scout (renamed Microsoft Autopilot on 2026-09-25)
slug: microsoft-autopilot-scout
category: closed-hosted-agents
maker: Microsoft (Omar Shahine, CVP; "Project Lobster" team)
license: proprietary (built on OpenClaw open-source code)
repo: none public (docs source repo MicrosoftDocs/microsoft-scout-pr is private)
website: https://learn.microsoft.com/microsoft-scout ; https://blogs.microsoft.com/blog/2026/09/25/introducing-the-new-copilot-with-home-code-and-autopilot/
first_public: 2026-06-02
latest_release: Scout desktop "August 2026" release (docs updated 2026-08-21); Autopilot private preview from end of Sept 2026
release_cadence: monthly Scout desktop releases (July, August 2026 what's-new entries)
stars: n/a (closed)
forks: n/a
contributors: unknown (internal Microsoft team plus internal PR community)
primary_language: unknown
stack: Scout = Windows/macOS desktop app on GitHub Copilot model/skills plumbing (~/.copilot dirs) + OpenClaw code; Autopilot = cloud-hosted container per agent in the customer's M365 tenant, Entra identity, Microsoft IQ/Work IQ, Agent 365, Purview
platforms: [windows, macos, web]  # Scout desktop: Win11+/macOS 12+; Autopilot surfaces in Copilot app, Teams, Outlook
agent_engine: own loop derived from OpenClaw; models routed via GitHub Copilot
engines_supported: [raw-api]  # GitHub Copilot model catalog; no third-party CLI wrapping
model_access: vendor credits (GitHub Copilot license for Scout; Autopilot on Copilot usage-based billing)
execution_env: Scout = user host (desktop, shell, browser) with M365 cloud calls; Autopilot = Microsoft-hosted cloud container treated as untrusted, zero-trust runtime
per_bot_computer: yes for Autopilot ("its own identity, memory, computer and workspace"); no for Scout (user's machine)
persistent_bots: yes - user names the agent, gives it a role and goal; each has its own governed Entra identity
memory: layered memory that decays when unused and strengthens with use (vendor claim); Work IQ / Microsoft IQ org context; session history stored per device in OneDrive
routines: Scout heartbeat (15-120 min, work-hours window, separate permission policy) + schedule/condition/one-shot automations; Autopilot "routines" panel, watches channels and follows up threads
group_chat: partial - Autopilot is @mentioned in Teams channels/chats like a colleague; Scout launches typed sub-agents (Explore, Task, Code review, Research, General)
coding_workspace: Scout yes (files, shell with 3-tier permissions, git/gh, Co-Create editors); Autopilot unknown; separate "Code" tab in Copilot
browser_use: yes (Scout browser automation incl. network inspection)
computer_use: partial - Scout drives shell and browser, no general GUI control documented; Autopilot has its own cloud computer
connectors: native Microsoft 365 (Outlook, Teams, OneDrive, SharePoint, To Do, Loop, meeting transcripts, rooms) + MCP servers via desktop app + Copilot plugin registry
channels: Teams (primary chat surface for Scout; @mention for Autopilot), Outlook, documents; no SMS/WhatsApp/iMessage
mobile: no for Scout (docs say desktop only); Autopilot reachable through Teams/Outlook mobile [INFERENCE]
voice: unknown
approvals: Scout - Approve / Always allow / Deny per sensitive action, 3-tier shell policy, sensitive paths, stricter background policy; Autopilot - human sign-off on sensitive actions, Purview DLP and sensitivity labels enforced before send/write
e2e_encryption: no (Microsoft-processed; credentials redacted from logs, scoped tokens outside the container)
self_host: no
multi_user: yes - enterprise tenant, admin control via Intune/Group Policy/Agent 365; vision of "hundreds" of Autopilots per business (press)
pricing: Scout requires Frontier enrollment + GitHub Copilot license; Autopilot billed via Copilot usage-based billing (UBB) credits, no public price as of 2026-10-20
maturity: Scout = experimental Frontier preview (2026-06-02); Autopilot = private preview (end of Sept 2026), consumer version promised later
```

## What it is

Microsoft frames "Autopilots" as a new agent category: "always-on agents that work autonomously, with their own identity, and act on your behalf" ([Microsoft 365 blog, 2026-06-02](https://www.microsoft.com/en-us/copilot/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent/)). Scout was "our first Autopilot agent", "powered by OpenClaw open-source technology" ([same](https://www.microsoft.com/en-us/copilot/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent/)). It grew out of Omar Shahine's personal OpenClaw bot "Lobster" (own Apple ID and email, texted via iMessage, eventually nine always-on agents) and Jakob Werner's internal desktop agent "Clawpilot", downloaded by thousands of employees ([Microsoft Command Line, 2026-06-02](https://commandline.microsoft.com/project-lobster-openclaw-personal-ai-assistant-enterprise-secure/)).

On 2026-09-25 Microsoft renamed it: "Autopilot, previously called Scout, is your digital teammate ... Give it a name, a role and a goal, and it goes to work — watching channels, following up on threads, running recurring work and picking a project back up days later, without waiting for a prompt" and it "lives in your tenant with its own identity, memory, computer and workspace" ([Official Microsoft Blog, 2026-09-25](https://blogs.microsoft.com/blog/2026/09/25/introducing-the-new-copilot-with-home-code-and-autopilot/)). Target: enterprise knowledge workers; Nadella says Autopilots "will also go to the consumer side" (press: [PCMag, 2026-09-26](https://me.pcmag.com/en/migrated-18166-windows-10/38154/ready-to-put-your-work-on-autopilot-microsoft-readies-its-ai-agent-for-release)).

Two shapes, same lineage:

| | Scout (June-Aug 2026) | Autopilot (Sept 2026+) |
|---|---|---|
| Runs | Desktop app on user's Windows/macOS machine ([overview](https://learn.microsoft.com/en-us/microsoft-scout/overview)) | Cloud-hosted in the customer tenant ([blog](https://blogs.microsoft.com/blog/2026/09/25/introducing-the-new-copilot-with-home-code-and-autopilot/)) |
| Interaction | Chat in app, results in Teams | @mention in Teams/Outlook/chats/channels/documents |
| Access | Frontier + Intune policy + opt-in attestation + GitHub Copilot license ([blog](https://www.microsoft.com/en-us/copilot/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent/)) | Private preview from end of September 2026 ([blog](https://blogs.microsoft.com/blog/2026/09/25/introducing-the-new-copilot-with-home-code-and-autopilot/)) |

## Product and UX

- Scout: chat conversation; Scout "selects tools and works through the steps, showing progress in real time"; user approves sensitive actions; results land in the conversation or workspace folder ([overview](https://learn.microsoft.com/en-us/microsoft-scout/overview)). Chat list can be filtered by chats vs automations, pinned, marked unread; model and reasoning-effort pickers per message; on-demand conversation compaction ([what's new, July 2026](https://learn.microsoft.com/en-us/microsoft-scout/whats-new)).
- Co-Create: user and Scout edit the same file simultaneously with automatic merge; editors for Markdown (inline comments), code, CSV/TSV, Mermaid, Excalidraw; workspaces can live in OneDrive/SharePoint ([what's new](https://learn.microsoft.com/en-us/microsoft-scout/whats-new)).
- Users name their instance (TechCrunch's demo agent was "Sebastian") and give ongoing feedback that becomes memories and skills (press: [TechCrunch, 2026-06-02](https://techcrunch.com/2026/06/02/microsoft-launches-scout-an-openclaw-inspired-personal-assistant/)).
- Autopilot screenshot shows an overview page with a "Run the supplier review" prompt, and navigation for routines, plugins and recent sessions ([blog image caption](https://blogs.microsoft.com/blog/2026/09/25/introducing-the-new-copilot-with-home-code-and-autopilot/)).

## Architecture

- Lineage: OpenClaw code plus Microsoft identity/governance; "Every package is ingested through a curated, signed Microsoft supply chain, and every tool call, model request, and network hop is mediated by a zero-trust runtime — the agent's container is treated as untrusted, with Microsoft-controlled identity, tokens, and policy sitting outside it" ([Command Line](https://commandline.microsoft.com/project-lobster-openclaw-personal-ai-assistant-enterprise-secure/)).
- Models: Scout "processes your prompts and content through GitHub Copilot" and inherits its model catalog, which can include third-party and open-source models "including models from China-based providers"; the GitHub Copilot admin picks models ([FAQ](https://learn.microsoft.com/en-us/microsoft-scout/faq)). Skills live in `~/.copilot/bundled-skills/`, `~/.copilot/m-skills/` (synced) and `~/.copilot/skills/` as `SKILL.md` folders ([FAQ](https://learn.microsoft.com/en-us/microsoft-scout/faq)), i.e. the GitHub Copilot skill layout [INFERENCE: the desktop app reuses GitHub Copilot CLI/SDK plumbing].
- Scout backend: "If Microsoft Scout loses connection to its backend, work in progress pauses" ([FAQ](https://learn.microsoft.com/en-us/microsoft-scout/faq)) - local tools, cloud loop/model calls [INFERENCE].
- Autopilot: cloud computer + workspace per agent in the tenant, grounded in Microsoft IQ ([blog](https://blogs.microsoft.com/blog/2026/09/25/introducing-the-new-copilot-with-home-code-and-autopilot/)); press describes "its own cloud computer, workspace, storage, and identity" (press: [The Decoder](https://the-decoder.com/microsoft-gives-copilot-another-makeover-adding-an-autopilot-agent-and-usage-based-billing/)).
- Identity: "Every agent operates under its own governed Entra identity, not a shared, anonymous service account"; credentials "scoped to the task at hand, redacted from logs" ([MS 365 blog](https://www.microsoft.com/en-us/copilot/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent/)).
- Storage: session history "stored per device in your OneDrive" ([what's new](https://learn.microsoft.com/en-us/microsoft-scout/whats-new)).
- Extension: SKILL.md skills, MCP servers via desktop app ([MS 365 blog](https://www.microsoft.com/en-us/copilot/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent/)), Copilot plugin registry for Autopilot ([blog](https://blogs.microsoft.com/blog/2026/09/25/introducing-the-new-copilot-with-home-code-and-autopilot/)). No public developer API for Autopilot found (unknown).

## Capabilities in detail

- Memory: Werner designed "layers of memory" where unused items fade and used ones gain relevance ([Command Line](https://commandline.microsoft.com/project-lobster-openclaw-personal-ai-assistant-enterprise-secure/), vendor claim); "remembers your preferences and decisions across conversations" ([overview](https://learn.microsoft.com/en-us/microsoft-scout/overview)).
- Routines: Heartbeat runs a fixed prompt every 15/30/60/120 minutes during configured work hours with its own permission policy; Automations are schedule-triggered, condition-triggered or one-shot, each with per-automation reasoning effort and context size ([FAQ](https://learn.microsoft.com/en-us/microsoft-scout/faq), [what's new](https://learn.microsoft.com/en-us/microsoft-scout/whats-new)).
- Sub-agents: Explore, Task, Code review, Research, General-purpose, run in parallel and report back ([FAQ](https://learn.microsoft.com/en-us/microsoft-scout/faq)).
- M365 actions: mail, calendar, Teams chats/channels/posts, presence, To Do, OneDrive/SharePoint files and sharing, SharePoint Lists, inbox rules, meeting transcripts, room booking ([what's new](https://learn.microsoft.com/en-us/microsoft-scout/whats-new)).
- Proactive coordination: schedules meetings across time zones, blocks focus time, flags stalled decisions ([MS 365 blog](https://www.microsoft.com/en-us/copilot/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent/), vendor claim).
- Mobile: Scout "is a desktop application ... not available on mobile" ([FAQ](https://learn.microsoft.com/en-us/microsoft-scout/faq)).

## Security and trust model

- Three-tier shell permissions (auto-approve / prompt / deny), sensitive paths, capability toggles per category ([FAQ](https://learn.microsoft.com/en-us/microsoft-scout/faq)).
- External content (emails, web pages, Teams messages) is tagged untrusted and treated as data ([FAQ](https://learn.microsoft.com/en-us/microsoft-scout/faq)).
- Background modes use "a more restrictive permission policy than interactive conversations" ([FAQ](https://learn.microsoft.com/en-us/microsoft-scout/faq)).
- Purview sensitivity labels and DLP enforced "before anything is sent or written"; Agent 365 is the admin control plane ([MS 365 blog](https://www.microsoft.com/en-us/copilot/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent/), [Command Line](https://commandline.microsoft.com/project-lobster-openclaw-personal-ai-assistant-enterprise-secure/)).
- "Policy conformance" contributed upstream to OpenClaw; continuous checks produce audit trails ([MS 365 blog](https://www.microsoft.com/en-us/copilot/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent/); press: [TechCrunch](https://techcrunch.com/2026/06/02/microsoft-launches-scout-an-openclaw-inspired-personal-assistant/)).
- Not available in GCC/GCC High/DoD or sovereign clouds; custom skills are not validated by Microsoft ([FAQ](https://learn.microsoft.com/en-us/microsoft-scout/faq)).
- Incidents: none specific to Scout/Autopilot found as of 2026-10-20 (unknown).

## Traction and momentum

- Internal: "Clawpilot" downloaded by thousands of Microsoft employees within weeks ([Command Line](https://commandline.microsoft.com/project-lobster-openclaw-personal-ai-assistant-enterprise-secure/), vendor claim).
- Timeline: Build announcement 2026-06-02; desktop releases in July and August 2026 ([what's new](https://learn.microsoft.com/en-us/microsoft-scout/whats-new)); rename and private-preview expansion 2026-09-25 ([blog](https://blogs.microsoft.com/blog/2026/09/25/introducing-the-new-copilot-with-home-code-and-autopilot/)).
- Business model: Cowork, Code and Autopilot "run on UBB" (usage-based billing) while the per-user licence covers chat and Office ([blog](https://blogs.microsoft.com/blog/2026/09/25/introducing-the-new-copilot-with-home-code-and-autopilot/)); no public Autopilot price as of 2026-10-20 (press: [PCMag](https://me.pcmag.com/en/migrated-18166-windows-10/38154/ready-to-put-your-work-on-autopilot-microsoft-readies-its-ai-agent-for-release)).

## Strengths

- Distribution: lands inside Teams/Outlook where enterprise users already are; @mention-a-colleague UX.
- Most complete enterprise governance story in the category: per-agent directory identity, DLP before send, admin plane, audit.
- Well-documented local permission model (tiers, sensitive paths, separate background policy) that is directly reusable as a design reference.

## Weaknesses and risks

- Microsoft-365-only reach; no consumer messaging channels; Scout needed four prerequisites (Frontier, Intune, attestation, GitHub Copilot licence).
- Product identity churn (Clawpilot, Project Lobster, Scout, Autopilot) and an architectural pivot from desktop to cloud within four months.
- Usage-based billing with no published rate makes cost unpredictable [INFERENCE].
- Model routing through GitHub Copilot can include China-based providers unless admins restrict ([FAQ](https://learn.microsoft.com/en-us/microsoft-scout/faq)).

## Ideas worth taking for Memoshi

- Separate permission policy for unattended runs (heartbeat/automations) vs interactive chat: limits blast radius of always-on work.
- Heartbeat as a first-class primitive (one prompt, interval, work-hours window) distinct from discrete automations.
- "Approve / Always allow / Deny" with the always-allow pattern written back into an editable allowlist.
- Decaying memory with reinforcement on use, to avoid the stale-facts problem Shahine describes.
- Treat the agent container as untrusted; keep tokens and policy outside it and mediate every tool call and network hop.
- Typed sub-agents (explore/task/review/research) with background completion reports.
- Co-Create: agent and user editing the same file with merge, instead of agent-only artifacts.

## Open questions

- What OpenClaw components survive in Autopilot vs Microsoft rewrites? (No public repo; watch OpenClaw upstream for Microsoft "policy conformance" PRs.)
- Autopilot per-agent compute size, persistence of its cloud computer, and UBB price per hour/task (check Microsoft Learn once Autopilot docs publish; Ignite 2026-11-17..20).
- Whether a consumer Autopilot will ship with messaging channels beyond Teams.

## Sources

1. https://www.microsoft.com/en-us/copilot/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent/
2. https://blogs.microsoft.com/blog/2026/09/25/introducing-the-new-copilot-with-home-code-and-autopilot/
3. https://commandline.microsoft.com/project-lobster-openclaw-personal-ai-assistant-enterprise-secure/
4. https://learn.microsoft.com/en-us/microsoft-scout/overview
5. https://learn.microsoft.com/en-us/microsoft-scout/faq
6. https://learn.microsoft.com/en-us/microsoft-scout/whats-new
7. Press: https://techcrunch.com/2026/06/02/microsoft-launches-scout-an-openclaw-inspired-personal-assistant/
8. Press: https://me.pcmag.com/en/migrated-18166-windows-10/38154/ready-to-put-your-work-on-autopilot-microsoft-readies-its-ai-agent-for-release
9. Press: https://the-decoder.com/microsoft-gives-copilot-another-makeover-adding-an-autopilot-agent-and-usage-based-billing/
