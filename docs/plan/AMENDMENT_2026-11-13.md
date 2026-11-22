# Memoshi — scope amendment of 2026-11-13

**Status:** Accepted scope per [D106–D122](decisions.md#d106) · 2026-11-13 · phases keep their numbers and the milestones M1–M3 name their gates; the estimated calendar is [D122](decisions.md#d122)'s, carried in [`10-roadmap.md`](10-roadmap.md).
**Owns:** what v1.0 contains after D106–D122, by milestone, and the reviews those decisions trigger.
**Depends on:** [`MASTER_PLAN.md`](MASTER_PLAN.md), [`decisions.md`](decisions.md), [`feature-catalog.md`](feature-catalog.md), the [merge assessment](../research/2026-11-12-memoshi-cognitio-bot-hq-merge.md).

This file is the summary of record for what D106–D122 changed. [D123–D133](decisions.md#d123), taken the same day after the code review, settle engineering points and are not repeated here. The plan and spec documents were revised to match on 2026-11-13; where one still disagrees, the decisions win. Catalog IDs below are rows that existed before the amendment; "new" marks a feature whose row was added to [`feature-catalog.md`](feature-catalog.md) by the revision. In the tables, M1 means Phase 1, M2 means Phase 2 and M3 means Phase 3, with Phase 4's hardening before the v1.0 gate. `[INFERENCE]` marks reasoning.

---

## 1. Target

> A native, local-first workspace where an Assistant runs a team of bots, with Cognitio's interface on Memoshi's engine and policy, extended by governed Apps that bots build and change while you talk.

| Layer | Comes from | Decision |
|---|---|---|
| Engine, policy, devices, Apple data | Memoshi's plan (Pi_Swift on every device) | D44, D46, unchanged |
| Interface on Mac, iPad and iPhone | Cognitio's design, rebuilt in Memoshi's own code | D106 |
| Orchestration and teamwork | The Assistant; bot-to-bot messages; groups; goals | D109 |
| Engineering tool | Cognitio's workbench; outside coding agents; Ultimate's team mode | D110 |
| Malleability | Pi's p2 and Ultimate: Apps with panes, functions and data, built by bots | D114 |
| Generated interface | Streamed catalog cards, bot-written Swift, sandboxed web pages | D115 |
| Personal information | Mail, Calendar, Reminders, Contacts, Notes, Files | D116 |
| Reach | Voice, search, connector catalog, app events, image and video | D111, D112 |
| Computers | Sandbox, local virtual machine or cloud computer per bot; other machines over SSH | D113 |

Two ways of working are both first-class: talk to the Assistant and let it coordinate, or drive bots and coding sessions directly.

## 2. What changed against Draft 4

| Area | Before | Now | Decision |
|---|---|---|---|
| Design lead | Viticci-led assistant, Kuvo informs the workbench (D92, D94) | Cognitio leads the whole shell on every device; Viticci's grammar for Apple-data cards, Apps and phone navigation | D106 |
| Kuvo code | Reuse permitted, none selected (D91) | No Kuvo- or Cognitio-derived code in the interface; rebuilt | D106 |
| Cognitio | Not in the plan | Continues in parallel; reference and oracle | D107 |
| Claude on a subscription | Blocked (DIST-03); Claude Code worker in v1.1 | Claude Code as a model on the Mac (M1) and as a worker (M2) | D108 |
| Bot-to-bot messages | v1.1 | M1 | D109 |
| Groups | v1.1 | M2 | D109 |
| Goals | Absent | M2 | D109 |
| External coding agents | v1.1 | M2, Mac | D110 |
| Team mode, landing gate, reviewers | Absent | M2, optional per project | D110 |
| Voice conversation | v2 | Mac M2, iPhone and iPad M3; cloud and on-device engines | D111 |
| Text-to-speech, voice memos | Absent | With voice | D111 |
| Web and X search | Absent | M1 | D112 |
| Connector catalog | MCP by hand | Built-in catalog and connect cards (M1); optional Composio (M2) | D112 |
| Connector events | Phase 3 | M2, Mac | D112 |
| Image and video generation | Absent | M2 | D112 |
| Bot computers (VM per bot) | v1.1 | End of M2 | D113 |
| Cloud computers | v2 | M2, after local | D113 |
| Remote machines, always-on Mac host | v1.1 | M3 | D113 |
| Takeover from iPhone and iPad | Drop 2 | M3 | D113 |
| Apps | A sheet owned by one bot; consume tools only | Apps: pane, exported functions, view tools, selection carry, wider scope | D114 |
| Bot-built panes | Phase 2 (Swift engine) | M1 as page Apps; Swift Apps M2 | D114 |
| Plugin developer mode, Full access on this Mac | Absent; dynamic loading excluded (D72) | Mac only, opt-in | D114 |
| Catalog cards | Phase 2, not streamed | M1, streamed, A2UI-aligned | D115 |
| Mail | A connector row with an open question (CON-08) | Typed `mail.*` tools and a native pane, M1 | D116 |
| Calendar, Reminders, Contacts tools | Phase 2 (AP-10) | M1, with native panes | D116 |
| Calendar | One gate, Fri 2028-11-24 | Milestones M1–M3, with v1.0 at M3 on Fri 2030-09-27 (an estimate); nothing deferred | D117, D122 |

## 3. Milestones

Phase 0 and its gate on Fri 2026-11-27 are unchanged. Each milestone ends with a gate review as before (change-control rule 6).

| | M1 — Mac: Assistant, bots, Apps, personal information | M2 — Mac: workbench, teams, voice, computers | M3 — iPhone, iPad, devices; hardening → v1.0 |
|---|---|---|---|
| Phase | Phase 1, 46 plan weeks | Phase 2, 83 plan weeks | Phase 3, 55 plan weeks, then Phase 4, 8 |
| Gate ([D122](decisions.md#d122), estimates) | M1, Fri 2027-10-29 | M2, Fri 2029-06-29 | Phase 3 gate Fri 2030-08-02; M3 and v1.0, Fri 2030-09-27 |
| Outcome | Memoshi is the daily Mac app for chat, bots, mail and calendar | Memoshi is the daily Mac engineering tool; bots speak and have their own computers | Every bot on every device with one history |
| Exit (short) | The builder uses Memoshi instead of Cognitio for chat and bots. The Assistant delegates through Handoffs. A bot builds a working pane in one conversation and changes it on request. Inbox triage and the week view are used daily. No T4 action without a card outside Bypass, except mail sent by a bot the user lets send mail by itself (D116) | First accepted diff within 10 minutes for a new project. A team-mode change lands only after its checks pass. A call hands work to a bot and speaks the result. A bot finishes a web chore in its own computer while watched. A Swift App replaces a page App and keeps its data | Phase 3's and Phase 4's exits, plus: a voice call from the Action Button; a bot's computer watched and taken over from the phone; a bot running on a Mac mini while the laptop sleeps |

## 4. Scope by area

### 4.1 Shell and conversation (D106)

| Feature | From | Milestone | Catalog |
|---|---|---|---|
| Card window: sidebar, conversation, side panel; tabs; split view | Cognitio | M1 | SH-* |
| Sidebar: Inbox, Assistant, Bots, Groups (M2), Projects (M2), Sessions, Apps | Memoshi, Cognitio | M1 | SH-07 |
| Transcript: fast scrolling, tool calls that fold open, one steps line ("Worked for 2m · 7 steps"), a live caption of what the bot is thinking, turn-end row, find, selection across messages | Cognitio, bot-hq | M1 | CH-02–08, CH-16 |
| Composer: model and effort picker, permission-mode chip, attachments, `@` files, queue, steer, stop, side question, dictation; `/` commands in M2 (CH-18) | Cognitio | M1 | CH-06–08, MOD-04, AP-03 |
| Cards: approval with deny-and-say-why, question with a recommended pick, form, draft, sign-in | Memoshi, Cognitio, Ultimate | M1 | CH-09, SEC-04–07 |
| ⌘K, menu bar, actionable notifications, settings with search, onboarding with a starter team | Memoshi, Cognitio | M1 | SH-09–11, AP-02, ON-01–08 |
| Message actions, context meter, compaction and reset; fork and rewind from a checkpoint in M2 (CODE-05); transcript export in M3 (EXP-03) | Memoshi, Cognitio | M1 | CH-13, CH-14 |
| QuickAsk | Memoshi | M1 | AS-09 |

### 4.2 Assistant, bots and teamwork (D109)

| Feature | From | Milestone | Catalog |
|---|---|---|---|
| Assistant as light orchestrator; daily brief; check-ins that stay quiet when you just wrote | Memoshi, Ultimate, bot-hq | M1 | AS-01–06 |
| Roster; bot record; look, personality, job, templates, work limits; `bot.md` export | Memoshi, Cognitio | M1 | BOT-02–10, EXP-01/02 |
| Inbox; a global Tasks view | Memoshi, bot-hq | M1 | IN-01–07, new |
| Handoffs; subagents | Memoshi | M1 | AS-08, CH-15 |
| Bot-to-bot messages under a grant, hop cap and budgets | Memoshi, bot-hq, Cognitio | M1 | GR-06 |
| Groups of 2–6 with a lead | Memoshi, Cognitio | M2 | GR-01–03, 05, 07, 09–11 |
| Goals with criteria and a decision log | Cognitio, Ultimate | M2 | new |
| Governed memory; nightly consolidation | Memoshi | M1 | MEM-01–10 |
| Routines, wakes, model-free watches | Memoshi | M1 | RT-01–12 |
| Triggers from app events and local webhooks | Memoshi, bot-hq | M2 | RT-13, RT-14 |
| Budget floor; usage display; subscription plan meters | Memoshi, Cognitio | M1 | BU-01, BU-02, BU-07, new |
| Budgets for routines and Handoffs; cost preview | Memoshi | M3 | BU-03–06 |

### 4.3 Models (D108)

| Feature | Milestone | Catalog |
|---|---|---|
| API keys, local endpoints, Sign in with ChatGPT, per-bot model | M1 | MOD-02–05, MOD-08 |
| Claude through Claude Code as a model, Mac | M1 | new |
| Apple's on-device model for small jobs | M1 | AP-04 |
| Model roles with ordered fallback lists | M2 | new |
| A downloaded open model on iPhone and iPad | Drop 2 | MOD-09 |

### 4.4 Tools and reach (D112)

| Feature | Milestone | Catalog |
|---|---|---|
| This Mac sandbox per bot; a WebKit browser per bot with live view, takeover and sign-in cards | M1 | CMP-03–05, BRW-02–08 |
| MCP connectors with OAuth; skills | M1 | CON-01–07, CON-09, CON-10, CON-13 (project skills, CON-11, in M2; skill proposals, CON-12, in M3) |
| Built-in connector catalog with connect cards | M1 | new |
| `web_search`, `x_search`, source chips | M1 | new |
| Composio as an optional route, off by default | M2 | new |
| Image and video generation | M2 | new |
| Code Mode | M1 | CH-05 |
| Python and notebooks on the Mac | M2 | PY-01, PY-02 |

### 4.5 Apps and generated interface (D114, D115)

| Feature | Milestone | Catalog |
|---|---|---|
| Streamed native cards from the catalog, A2UI-aligned | M1 | CH-19, CH-25 |
| Native diagrams, charts and math | M1 | new |
| App contract: side-panel pane, exported functions, `view` tools, selection carry | M1 | new |
| Page Apps and interactive artifacts in a sandboxed web view, with the tool bridge and permission list | M1 | TP-07, new |
| A bot sees a rendered snapshot of what it built before reporting done | M1 | new |
| An App usable by all your bots, by grant | M1 | new |
| Swift engine: live cards and Swift Apps on the Mac | M2 | CH-21, CH-22, CH-24 |
| Digest of what you did in an App, sent to its bot | M2 | CH-31 |
| Project-scoped Apps behind a trust prompt | M2 | new |
| Plugin developer mode on the Mac: compiled Swift plugins in a separate helper; Full access on this Mac per App or plugin | M2 | new |
| Screens provided by connectors (MCP Apps) | M2 | new |
| Swift Apps and catalog cards on iPhone and iPad | M3 | CH-20, CH-23 |
| App background jobs, widgets, bytecode cache, the rest of Swift | Drop 1 | CH-26–30, CH-32 |
| Generated motion and shaders; 3D and Gaussian-splat views | Later design passes | new |

### 4.6 Personal information (D116)

| Feature | Milestone | Catalog |
|---|---|---|
| `mail.*` tools for Gmail, Microsoft 365 and IMAP; Mail pane | M1 Mac, M3 iPhone and iPad | CON-08, new |
| Calendar, Reminders and Contacts tools; Calendar pane; Reminders merged with Tasks; Contacts pane | M1 Mac, M3 iPhone and iPad | AP-10 (part), AP-11, new |
| Notes pane (Markdown); Files and Library pane | M1 | CMP-04, TP-06, new (the Library tabs of TP-08 stay in Phase 2) |
| Music, Weather, Maps, Photos, Shortcuts and Notifications tools with native cards | M2 | AP-10 (rest) |
| App Intents, Siri and Shortcuts | M2 | AP-05 |
| Alarms, Health (read), Home; Spotlight; widgets | M3 | AP-06, AP-07, AP-11 |
| Live Apple-data cards; Shazam; in-app Music | Drop 2 | AP-12, AP-13 |

### 4.7 Engineering workbench (D110)

| Feature | Milestone | Catalog |
|---|---|---|
| Projects and sessions; coding tools in the sandbox | M2 | PR-01–09, CODE-01 |
| Changes with line comments, accept and reject, checkpoints, undo | M2 | CODE-02–05 |
| Worktrees, commit, push and PR, tests, CI watches, bot review | M2 | CODE-06–12 |
| Terminal, files, preview; `/plan`, `/review` | M2 | TP-01–05, CH-18 |
| Codex, Claude Code and ACP agents as workers | M2 | R11-08–10 |
| Team mode: lead per worktree, helpers, parallel reviewers, a code-only landing gate | M2 | new |
| Attempts: the same task in several worktrees, compared | M2 | R11-15 |
| Coding on iPhone and iPad, run on the Mac | Drop 2 | CODE-17 |

### 4.8 Voice (D111)

| Feature | Milestone |
|---|---|
| Dictation | M1 |
| Voice call with a bot on the Mac: cloud realtime engine and on-device engine; work handed to the bot's queue; call card with transcript | M2 |
| Read a reply aloud; voice memos | M2 |
| The voice bot opens views and reads an answer back before committing it; optional spoken narrator | M2 |
| Voice on iPhone and iPad: Action Button, Live Activity, Start Voice Chat intent | M3 |

### 4.9 Computers and devices (D113)

| Feature | Milestone | Catalog |
|---|---|---|
| Bot computer: a Linux VM per bot with a desktop and Chromium; live view, takeover, sleep when idle | End of M2 | CMP-06–12, CMP-15–20, BRW-11, BRW-12 |
| Cloud computer behind the same seam; cost shown first; per-bot choice | M2, after local | V2-02 |
| GUI computer use inside a Bot or Cloud computer | M2 | R11-12 |
| iPhone and iPad app with the engine inside; in-app environment; iSH; Python | M3 | IOS-01–04, IOS-06, PY-03, PY-04 |
| Pairing, encrypted links, runner leases, replicas, offline queue, push, biometric approvals | M3 | DEV-02–12 |
| Remote machines over SSH; an always-on Mac as host | M3 | CMP-13, CMP-14, R11-07 |
| Watch and take over a bot's browser or computer from iPhone and iPad | M3 | BRW-15 |

### 4.10 Trust and release

Unchanged and still required from Phase 1: tiers T0–T5 and three permission modes, approvals and drafts, secrets by reference, egress allowlists, the hash-chained audit log, the red-team suite, Stop All Bots. Signed and notarized Mac builds from Phase 1; internal TestFlight builds from Phase 3; the security review and the accessibility audit in Phase 4, before the M3 gate.

## 5. Smaller items adopted with D117

| Item | From | Milestone |
|---|---|---|
| Triggers when a conversation's context passes a set fill level | Ultimate | M2 |
| A reflection pass that turns failures and corrections into proposals | Ultimate | M2 |
| Pause every bot when a provider reports a rate limit, with Play | Ultimate | M1 |
| The look of an App's function calls in chat comes from the App | Pi p2 | M1 |
| Prompt-cache warming after a break, off by default | Cognitio, Ultimate | M2 |
| A developer view of what the model was sent | Ultimate | M2 |
| Attempts (R11-15) move from v1.1 to M2 with the workbench | Cognitio | M2 |

## 6. Where the new parts run

| Part | Runs in | Note |
|---|---|---|
| Shell | The app, one SwiftUI codebase | D106 |
| View registry and App panes | The app; App code in the bot's engine helper on the Mac and inside the app on iPhone and iPad; page Apps in a sandboxed web view | Tool calls go to the conversation's runner, as for Apps |
| App functions | The runtime installs the function namespace (an extension installed and replaced in place, exposed as a Code Mode namespace); the function's code runs in the App's sandbox ([cards.md §12.9](../specs/cards.md#129-the-app-contract-panes-places-functions-and-selection)) | Pi_Swift already has runtime install and Code Mode tool registration |
| Card streaming | The runtime emits partial card data; the app validates as it arrives | |
| Voice | Audio and Apple speech in the app; the cloud session key comes through the Keychain broker | The voice session is a client of the conversation's queue |
| Search, mail, image and video | Typed tools in the runtime, through the egress gateway | |
| Calendar, Reminders, Contacts | Host calls in the app | As the plan's Apple tools |
| Computers | One seam, four providers: This Mac, Bot computer, Cloud computer, Remote machine | |
| Outside coding agents | Child processes started by the runtime inside the bot's sandbox, Mac only | Policy through each agent's own permission protocol |
| Plugins built in plugin developer mode | A separate helper process on the Mac | Never memoshid, never the app |

<a id="7-reviews-these-decisions-trigger"></a>
## 7. Reviews these decisions triggered

All four were carried out on 2026-11-13: each file below was revised to state D106–D122, and the set was then checked for consistency.

| Review | Files | Why |
|---|---|---|
| Roadmap (rule 3) | `10-roadmap.md`, `feature-catalog.md`, `MASTER_PLAN.md` §11–§12, `risks.md`, `phase-0.md` (next-phase readiness) | Stages moved; new rows; dates for M1–M3 |
| Spec (rule 4) | `object-model.md` (App, View, Goal, mail account, computer kinds), `cards.md` §11–§12, `policy.md` (new tools, App function calls, plugin developer mode), `protocol.md`, `events.md` | New and changed objects |
| Design (rule 5) | `02-experience.md`, `03-design-system.md`, `../specs/design-reference.md` | New lead; side-panel Apps; six panes |
| Area docs | `05-bots-and-assistant.md`, `06-computers-and-browsers.md`, `07-coding.md`, `08-security-and-privacy.md`, `09-platform-macos.md` | Each gains moved or new features |

## 8. Open items

| # | Item | Decided by |
|---|---|---|
| 1 | Sizes and gate dates for M1, M2 and M3 | **Settled** by [D122](decisions.md#d122), as estimates |
| 2 | Policy tier for reversible mail changes (archive, mark read, label) | **Settled** by [D118](decisions.md#d118): `mail.organize`, T3, coverable by a standing rule |
| 3 | Whether the binding vocabulary renames mini app to App | **Settled** by [D119](decisions.md#d119): App everywhere; identifiers stay |
| 4 | Keep the D53 card schema and map to A2UI, or adopt A2UI's schema | The survey's experiment A-E4 |
| 5 | Default providers: web search, cloud voice, the on-device voice, image and video | Defaults **settled** by [D120](decisions.md#d120); each still gets a short measured comparison before its phase |
| 6 | Cloud computer provider | Default **settled** by [D120](decisions.md#d120): E2B, with Orgo and Daytona selectable; compared before the work starts |
| 7 | VM engine (O2), helper split (O3), awake-VM caps by memory (O4) | VM spike (CMP-01) at the start of the Bot computer work in Phase 2 ([D122](decisions.md#d122)) |
| 8 | Gmail and Microsoft sign-in for a public release: the providers review apps that read mail [INFERENCE: from general knowledge; verify] | Before O13 |
| 9 | Claude Code's terms | Before O13 |
| 10 | The plugin interface for plugin developer mode. Pi_Swift's loader compiles and loads Swift in-process; D114 requires a separate helper | Phase 2 design |
| 11 | Who writes each surface's behaviour description from Cognitio, and when | Design review |
| 12 | Cursor as a worker: needs a JavaScript runtime today | Revisit if it speaks ACP |

## 9. Risks added or raised

| Risk | Why | Mitigation |
|---|---|---|
| Scope | v1.0 now holds what was v1.0, v1.1 and part of v2, with one builder ([D45](decisions.md#d45)) and a second live codebase ([D107](decisions.md#d107)): 197 plan weeks where D87 had 105 ([D122](decisions.md#d122)) | Milestones that are each usable; the cut order in `10-roadmap.md` stays available; a gate review may re-date a later phase |
| The rebuilt interface | Cognitio's transcript is custom text layout tuned over a long time; matching it in new code is the hardest single surface [INFERENCE] | Build and measure the transcript first in M1 |
| Bot-written code beside mail | An injected email could steer a bot into changing an App | D72's rule: a version written after untrusted content waits for approval; sends are drafts, and a bot's own sending never applies to a run started by incoming mail; exposure labels |
| Full access on this Mac | It removes the sandbox for one App or plugin | Mac only, inside plugin developer mode, confirmed, badged; never for iPhone or iPad |
| Virtual machines and cloud computers | Memory per awake VM; provider cost and lock-in | Caps by installed memory (O4); cost shown first; one seam for all providers |
| Provider terms | Claude through Claude Code; mail providers' review; X search needs an xAI key | Each is one route among several; re-checked before a public release |
| The Swift engine (R51) | Unchanged, and now more depends on it | Page Apps in M1 and catalog cards mean bots can build before it lands |
| Pi_Swift (R39) | Unchanged | The 2026-11-27 gate and its fallbacks |
