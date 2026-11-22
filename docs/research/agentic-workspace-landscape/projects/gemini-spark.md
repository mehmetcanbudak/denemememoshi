# Google Gemini Spark (now "Tasks in Gemini")

> Google's 24/7 background agent inside the Gemini app: runs on Google Cloud VMs with a remote browser and code-execution computer, wired natively into Gmail/Workspace, driven by schedules, Gmail monitors and topic monitors; since October 2026 folded into the main chat as the "Task" mode. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found.

## Matrix row

Copy-paste-safe YAML; the master report aggregates these blocks. Use `yes` / `no` / `partial` / `unknown` plus a short qualifier where needed.

```yaml
name: "Google Gemini Spark (Tasks in Gemini)"
slug: gemini-spark
category: closed-hosted-agents
maker: Google
license: proprietary
repo: none
website: https://gemini.google/overview/agent/spark
first_public: 2026-05-19
latest_release: "Chat/Task redesign rolling out 2026-10-01 (web) and 2026-10-12 (Android); no version numbers"
release_cadence: "monthly-scale Gemini app drops (release notes 2026-05-19, 06-30, 07-21, 09-30, 10-13)"
stars: n/a
forks: n/a
contributors: n/a
primary_language: unknown
stack: "Gemini models (3.5 Flash at launch, 3.6 Flash by July, user-selectable model menu) on the Google Antigravity agent harness; Google Cloud VMs; remote Chrome; Chrome auto browse"
platforms: [web, android, ios, macos]
agent_engine: "own loop (Antigravity harness)"
engines_supported: ["google-internal (Gemini models)"]
model_access: "vendor subscription only (Google AI Pro / Ultra)"
execution_env: "Google Cloud VM per user (remote browser + remote code-execution computer); optional local Chrome; Mac app works on connected folders"
per_bot_computer: "yes - remote browser and remote computer per user, data persisted between sessions until deleted"
persistent_bots: "no - one Gemini identity; work is organized as task threads, not named agents (custom sub-agents announced, not found shipped)"
memory: "Personal Intelligence (memory of past chats, saved instructions, connected-app context) plus reusable skills"
routines: "yes - time-based schedules, Gmail-filter monitors, topic monitors; max 50 active schedules, 15 concurrent tasks"
group_chat: no
coding_workspace: "partial - runs code on the remote computer and emits code files; Antigravity coding agent sits beside it in the Mac app"
browser_use: "yes - remote cloud browser or the user's local Chrome; 'View live' and take over"
computer_use: "partial - Mac app edits files in connected folders and can be driven remotely from a phone; no full desktop GUI control found"
connectors: "native Google Workspace, Search, Maps, YouTube, Photos; 40+ connected apps; custom MCP servers (US, English)"
channels: "Gemini app (web, Android, iOS, Mac); Android Halo progress surface (press); texting/emailing Spark announced at I/O, not found in help docs"
mobile: yes
voice: "partial - schedules can be created from a Gemini Live chat; no phone calls"
approvals: "asks before high-stakes actions (spend, send, delete, share); per-task browsing confirmation; write actions on custom MCP apps need manual confirmation; sign-in steps hand over to user"
e2e_encryption: no
self_host: no
multi_user: "no - personal Google accounts only; work accounts excluded (enterprise counterpart is the separate Gemini agent in Gemini Enterprise, 2026-10-08)"
pricing: "Google AI Pro $19.99/mo; AI Ultra $100 or $200/mo; compute-based limits that refresh every 5 hours with a weekly cap"
maturity: "beta to GA-in-app - beta for US Ultra from late May 2026, expanded to Pro and 'wherever Gemini Apps are supported' except EEA, Nigeria, Switzerland, UK"
```

## What it is

Announced at I/O on 2026-05-19 as "a 24/7 personal AI agent that helps you navigate your digital life", Spark "runs on Gemini 3.5 and uses the Antigravity harness", is "deeply integrated with the Workspace tools", and "keeps working in the background even when you close your laptop or lock your phone" ([Google blog](https://blog.google/innovation-and-ai/products/gemini-app/next-evolution-gemini-app/)). Sundar Pichai said it "runs on dedicated virtual machines on Google Cloud" ([TechCrunch, press](https://techcrunch.com/2026/05/19/google-introduces-gemini-spark-a-24-7-agentic-assistant-with-gmail-integration/)). It is a delegation mode of the Gemini assistant, not a roster of named bots: the user assigns tasks, sets schedules, and teaches skills. Target users: Google AI Pro/Ultra consumers, parents, small businesses ([Google Canada blog](https://blog.google/intl/en-ca/products/explore-get-answers/introducing-gemini-spark-your-247-personal-ai-agent-in-canada/)).

## Product and UX

- Launch UX: a separate "Spark" tab/"Switch to Spark" silo in the Gemini app ([Gemini release notes](https://gemini.google/us/release-notes/?hl=en), [Chrome Unboxed, press](https://chromeunboxed.com/google-is-quietly-ditching-the-spark-brand-to-merge-tasks-directly-into-gemini/)).
- October 2026 redesign: "Chat" / "Task" toggle above the prompt box, unified history filterable by Ready / Needs attention / In progress, new "Scheduled" page (Active, Paused, Completed, Suggested), "Gemini Spark Settings" renamed "Task settings" ([9to5Google, press](https://9to5google.com/2026/10/12/gemini-spark-task-redesign/)). Help center now titles the feature "Manage your tasks & workflows in Gemini Apps" ([Gemini Help](https://support.google.com/gemini/answer/17094507)).
- Task thread with a work panel (completed/current/planned steps, files read or updated); conversational onboarding via "set up", "get started" or "interview me" ([Gemini Help](https://support.google.com/gemini/answer/17094507)).
- Generated files: docx, xlsx, pptx, pdf, code, media, archives; Markdown edited in Canvas (ibid.).
- Mac: connected folders, temporary backups for 24 hours, remote control of the Mac app from a phone on the same Wi-Fi/Bluetooth ([Gemini Help, Mac](https://support.google.com/gemini/answer/17208717?hl=en)).

## Architecture

- Model + harness: Gemini models on the Antigravity harness ([Google blog](https://blog.google/innovation-and-ai/products/gemini-app/next-evolution-gemini-app/)); "Driven by Gemini 3.6 Flash" by July ([Google Canada blog](https://blog.google/intl/en-ca/products/explore-get-answers/introducing-gemini-spark-your-247-personal-ai-agent-in-canada/)); users can change model and thinking level from the model menu ([Gemini Help](https://support.google.com/gemini/answer/17094507)).
- Execution: remote browser (cookies persisted between sessions) and remote computer for code execution, both deletable in Task settings; local Chrome via "Chrome auto browse" when the device stays awake, falling back to the remote browser (ibid.).
- Sources the agent may use: Connected Apps, skills, chats, tasks, signed-in websites, Personal Intelligence, location (ibid.).
- Extension surface: skills (reusable instructions, replacing Gems) ([release notes](https://gemini.google/us/release-notes/?hl=en)); custom connected apps via any standard MCP server URL, with Dynamic Client Registration or manual credentials ([Gemini Help, custom apps](https://support.google.com/gemini/answer/17209137?hl=en)).
- Developer API for Spark: none found. Enterprise counterpart: the "Gemini agent" (Gemini Enterprise, 2026-10-08) exposes "a single agent and a single API", headless operation, Slack/M365 channels, sub-agents with their own identity and coworker agents with `@agents.company.com` mailboxes ([Google Cloud blog](https://cloud.google.com/blog/products/ai-machine-learning/welcome-to-gemini-at-work-2026)).

## Capabilities in detail

- Routines: time-based (once to yearly), Gmail monitors (fires on emails matching a Gmail filter), topic monitors (news, finance, sports, local events); time zone locked at creation; schedules do not run when usage limits are hit ([Gemini Help, schedules](https://support.google.com/gemini/answer/17094710?hl=en)).
- Limits: 50 active schedules, 15 concurrently running tasks (ibid.).
- Connectors: Gmail, Calendar, Docs, Drive, Keep, Sheets, Slides, Tasks, Contacts, Photos, YouTube, Search/Flights/Hotels/Maps; "more than 40 apps or services" in chat; launch MCP partners Canva, OpenTable, Instacart ([Gemini Help](https://support.google.com/gemini/answer/17094507), [release notes](https://gemini.google/us/release-notes/?hl=en), [Google blog](https://blog.google/innovation-and-ai/products/gemini-app/next-evolution-gemini-app/)).
- Announced but not confirmed shipped in help docs: "texting and emailing Spark, creating custom sub-agents and operating your local browser" ([Google blog](https://blog.google/innovation-and-ai/products/gemini-app/next-evolution-gemini-app/)); local browser operation has since shipped as Chrome auto browse ([Gemini Help](https://support.google.com/gemini/answer/17094507)). A dedicated Spark Gmail address was described at I/O ([TechCrunch, press](https://techcrunch.com/2026/05/19/google-introduces-gemini-spark-a-24-7-agentic-assistant-with-gmail-integration/)); current status unknown.
- Daily Brief: separate always-on digest agent for AI Plus/Pro/Ultra ([Google blog](https://blog.google/innovation-and-ai/products/gemini-app/next-evolution-gemini-app/)).

## Security and trust model

- Design rule: "ask you first before performing high-stakes actions like spending money or sending emails" ([Google blog](https://blog.google/innovation-and-ai/products/gemini-app/next-evolution-gemini-app/)).
- Help center warns: do not type credentials or payment details into task threads; take over the browser instead; "If a schedule runs when you are offline, you may not be able to stop Gemini from completing an unintended action" ([Gemini Help](https://support.google.com/gemini/answer/17094507)).
- Browsing: first-time Chrome permission, then confirmation for every task that involves browsing; sign-in pauses until the user takes over or confirms "Sign in with Google" (ibid.).
- Custom MCP: "Google does not control, monitor, or secure third-party MCP servers"; write actions currently require manual confirmation ([Gemini Help, custom apps](https://support.google.com/gemini/answer/17209137?hl=en)).
- Prerequisites tie the agent to data collection: Keep Activity on and Personal Intelligence opt-in are required ([Gemini Help](https://support.google.com/gemini/answer/17094507)).
- Impostor: a GitHub repo `google-gemini-spark/gemini-spark` advertising a "Win/Mac, MIT, free launch tier" Spark agent appeared in search results; it returned HTTP 404 via the GitHub API on 2026-10-20. Not a Google project; likely a malware or SEO lure [INFERENCE].
- Incidents specific to Spark: none found.

## Traction and momentum

- Timeline: I/O announce 2026-05-19; trusted testers that week, US Ultra beta the following week ([Google AI subscriptions blog](https://blog.google/products-and-platforms/products/google-one/google-ai-subscriptions/)); available in the US by 2026-06-02 ([PCMag, press](https://uk.pcmag.com/ai/165246/google-agentic-ai-tool-gemini-spark-now-available-how-to-try-it)); macOS app 2026-06-30 ([release notes](https://gemini.google/us/release-notes/?hl=en)); India and Australia 2026-07-29, Canada (Pro) 2026-07-31 ([Google India blog](https://blog.google/intl/en-in/company-news/technology/introducing-gemini-spark-your-247-personal-ai-agent-in-country/), [Google Canada blog](https://blog.google/intl/en-ca/products/explore-get-answers/introducing-gemini-spark-your-247-personal-ai-agent-in-canada/)); brand de-emphasized into "Task" from 2026-10-01 ([Chrome Unboxed, press](https://chromeunboxed.com/google-is-quietly-ditching-the-spark-brand-to-merge-tasks-directly-into-gemini/)).
- Distribution: Gemini app has "more than 900 million" monthly users (vendor claim, [Google blog](https://blog.google/innovation-and-ai/products/gemini-app/next-evolution-gemini-app/)); Spark-specific usage unknown.
- Pricing: AI Pro $19.99/month; Ultra $100/month new tier and $200/month (reduced from $250) ([Google AI subscriptions blog](https://blog.google/products-and-platforms/products/google-one/google-ai-subscriptions/), [gemini.google plans](https://gemini.google/us/about/?hl=en)); compute-based limits refreshing every five hours up to a weekly cap ([Google AI subscriptions blog](https://blog.google/products-and-platforms/products/google-one/google-ai-subscriptions/)).

## Strengths

- Zero-setup access to the user's mail, calendar and documents; Gmail-filter triggers are a uniquely cheap, precise event source.
- Clean task/schedule/skill vocabulary ("what, when, how") documented for consumers.
- Remote browser plus local Chrome fallback; Mac remote control from phone.
- Cheapest entry among big-lab agents ($19.99 Pro).

## Weaknesses and risks

- No persistent persona or multiple agents; tasks are threads, so "teammate" framing is absent in the consumer product.
- Brand churn (Spark tab, then Task) signals product uncertainty.
- Requires activity logging and Personal Intelligence opt-in; excluded in EEA/UK/Switzerland/Nigeria; personal accounts only.
- Announced channels (SMS, email to Spark) not evidenced as shipped.

## Ideas worth taking for Memoshi

- Treat "monitors" (email-filter triggers, topic watches) as first-class routine types next to cron schedules.
- Expose hard, documented concurrency and schedule caps; users can plan around them.
- "Interview me" onboarding that turns a conversation into skills and schedules.
- Persist remote-browser cookies per user but give a one-click wipe for browser and code-execution state.
- Chat vs Task as one composer toggle instead of a separate agent area; Google moved away from the silo after five months.
- From Gemini Enterprise: coworker agents with their own mailbox, calendar, drive and directory entry; a strong model for Memoshi's persistent teammates.

## Open questions

- Is the dedicated Spark email address or SMS channel live? Check support.google.com/gemini for an "email Gemini" article.
- Which model runs tasks by default after Gemini 4 Argon (2026-10-13)? Check release notes and the model help article (answer 18648722).
- Will consumer Spark and the enterprise Gemini agent converge (shared memory, coworker agents for Workspace Business)? Watch workspaceupdates.googleblog.com.

## Sources

1. https://blog.google/innovation-and-ai/products/gemini-app/next-evolution-gemini-app/
2. https://blog.google/products-and-platforms/products/google-one/google-ai-subscriptions/
3. https://gemini.google/us/release-notes/?hl=en
4. https://support.google.com/gemini/answer/17094507 (Manage your tasks & workflows; formerly 16596215)
5. https://support.google.com/gemini/answer/17094710?hl=en (schedules)
6. https://support.google.com/gemini/answer/17209137?hl=en (custom MCP apps)
7. https://support.google.com/gemini/answer/17208717?hl=en (Mac)
8. https://blog.google/intl/en-ca/products/explore-get-answers/introducing-gemini-spark-your-247-personal-ai-agent-in-canada/
9. https://blog.google/intl/en-in/company-news/technology/introducing-gemini-spark-your-247-personal-ai-agent-in-country/
10. https://cloud.google.com/blog/products/ai-machine-learning/welcome-to-gemini-at-work-2026
11. https://gemini.google/us/about/?hl=en (plans and prices)
12. https://techcrunch.com/2026/05/19/google-introduces-gemini-spark-a-24-7-agentic-assistant-with-gmail-integration/ (press)
13. https://uk.pcmag.com/ai/165246/google-agentic-ai-tool-gemini-spark-now-available-how-to-try-it (press)
14. https://9to5google.com/2026/10/12/gemini-spark-task-redesign/ (press)
15. https://chromeunboxed.com/google-is-quietly-ditching-the-spark-brand-to-merge-tasks-directly-into-gemini/ (press)
