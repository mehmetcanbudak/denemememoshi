# Review of inferred choices

**Status:** Decision record · 2026-10-22 · binding through the review decisions in [`decisions.md`](decisions.md) (D81 onward)
**Owns:** The outcome of every design choice that agents had made by inference ([INFERENCE]) and the user reviewed on 2026-10-22. High-impact choices are decisions D71–D80 in [`decisions.md`](decisions.md). This record holds the medium and low ones, table by table, with the doc locations each outcome changes.

Each row names the docs it changes (file and line at the time of the review), the outcome, and who chose it: the user, or the user leaving it to the recommendation. "Keep as specified" means the current text stands and loses its [INFERENCE] mark.

**Later amendments:** this is the historical 548-row review, not a new inventory. On 2026-10-23, [D88](decisions.md#d88) amended offline acceptance to distinguish model-backed side threads from no-model waiting; [D89](decisions.md#d89) superseded the former Code Mode fallback order; and [D91](decisions.md#d91) superseded the no-Kuvo-source/personal-fork exclusion recorded in PL-028, permitting qualifying personal-use source inspection and code reuse. [D92](decisions.md#d92) replaces blanket Kuvo appearance parity with a Viticci-led assistant/Kuvo-informed workbench family; the Apps section and Frosted/Solid option remain. [D93](decisions.md#d93) removes mandatory external design contracting, not design QA. The original outcomes below remain intact; active specs and release gates follow those amendments.

<a id="table-1"></a>
## Table 1: the Swift engine, cards and policy (D81)

From the specs `cards.md` and `policy.md`. 14 rows were already settled by D51, D67 and D71–D78; 62 were decided row by row, 20 kept and 42 changed.

| ID | Area | Where | Outcome | Chosen by |
|---|---|---|---|---|
| CP-024 | Engine | cards.md:363 | Keep as specified | User's choice |
| CP-025 | Engine | cards.md:365–372 | keep the instruction budget; add a wall-clock watchdog backstop (fuel plus epoch interruption, as Wasmtime) | Left to the recommendation |
| CP-026 | Engine | cards.md:376 | a failing handler is disabled first; one automatic budgeted bot fix attempt per version; three failures a minute stop the app; further fixes user-triggered | Left to the recommendation |
| CP-027 | Engine | cards.md:377 | Keep as specified | User's choice |
| CP-028 | Engine | cards.md:523, 577 | one language and kit everywhere; the kit adapts (richer on the Mac, lighter on iPhone); programs may mark extreme parts Mac-only with a lighter iPhone fallback | Left to the recommendation |
| CP-034 | Engine | cards.md:579 | Keep as specified | User's choice |
| CP-060 | Engine | cards.md:273 | render #Preview headlessly at publish as a smoke test; errors go to the bot | User's choice |
| CP-061 | Engine | cards.md:287 | add read-only locale, timeZone, calendar, scenePhase and accessibility environment values | User's choice |
| CP-065 | Engine | cards.md:345 | Keep as specified | User's choice |
| CP-066 | Engine | cards.md:348 | keep the 20-error cap; suppress cascade errors; fix-its where possible; report the omitted count | Left to the recommendation |
| CP-067 | Engine | cards.md:378 | live cards get the same bot-readable log; the Developer-only view stays | User's choice |
| CP-068 | Engine | cards.md:521 | Keep as specified | User's choice |
| CP-069 | Engine | cards.md:525 | ship reviewed source as bundled engine programs; rewrite natively only if needed | Left to the recommendation |
| CP-021 | Kit | cards.md:308 | about 100k points with vectorized plots, LTTB-downsampled beyond; JSON stays 500 | User's choice |
| CP-062 | Kit | cards.md:310 | keep players; add QuickLook previews for PDF and CSV artifacts | User's choice |
| CP-063 | Kit | cards.md:312 | add ViewThatFits; no vertical ScrollView inside inline live cards | User's choice |
| CP-029 | Mini apps | cards.md:542 | Keep as specified | User's choice |
| CP-030 | Mini apps | cards.md:544 | auto-switch when the user asked from the change box; else show ready | User's choice |
| CP-032 | Mini apps | cards.md:552 | keep T1; reads carry stored labels; snapshot before each bot write | User's choice |
| CP-033 | Mini apps | cards.md:557 | Keep as specified | User's choice |
| CP-035 | Mini apps | cards.md:583; 536 (unmarked) | Spotlight, Siri and Shortcuts launch plus a sidebar Apps section (deliberate exception to D43 sidebar parity) | User's choice |
| CP-022 | Bridge | cards.md:338 | an inline confirm sheet in the program shows the exact text with Send and Edit; untrusted values show the exposure note | Left to the recommendation |
| CP-023 | Bridge | cards.md:340, 373; policy.md:904 | Keep as specified | User's choice |
| CP-064 | Bridge | cards.md:336 | ToolError carries a stable error code plus the plain reason | User's choice |
| CP-011 | Policy | policy.md:373, 417, 1263 | if gateway routing fails, ship iSH with guest networking off | User's choice |
| CP-012 | Policy | policy.md:375 | keep S3; if it fails, per-bot content rules block by host | User's choice |
| CP-013 | Policy | policy.md:418 | Keep as specified | User's choice |
| CP-014 | Policy | policy.md:571; 1251 (unmarked) | Telegram owner messages attended for T0-T1 only; T2 and up in the app | User's choice |
| CP-036 | Policy | policy.md:206; 1250 (unmarked) | tree-sitter-bash embedded in Swift; unparseable or ambiguous lines are opaque and ask | Left to the recommendation |
| CP-037 | Policy | policy.md:277 | a maintained data file of credential-printing commands, adding cloud CLIs, op read, vault read | User's choice |
| CP-038 | Policy | policy.md:285 | decide every call of a line before any runs; one grouped card | Left to the recommendation |
| CP-039 | Policy | policy.md:287; 416 (unmarked) | Keep as specified | User's choice |
| CP-041 | Policy | policy.md:393, 417 | keep raw TCP only to granted host:port; SSH keys used through the sign-only agent (CP-045) | Left to the recommendation |
| CP-042 | Policy | policy.md:403, 415, 1260 | package-registry preset on by default for every bot on iPhone and iPad | User's choice |
| CP-043 | Policy | policy.md:405 | Keep as specified | User's choice |
| CP-044 | Policy | policy.md:413, 488 | Keep as specified | User's choice |
| CP-045 | Policy | policy.md:419, 1263 | a sign-only SSH agent socket in the guest, backed by the broker | User's choice |
| CP-046 | Policy | policy.md:420 | default to the host-side adapter; the week-47 probe confirms; the in-guest daemon only if conformance needs it | Left to the recommendation |
| CP-047 | Policy | policy.md:596 | keep; downloaded files are labelled untrusted, and reading one marks the task | Left to the recommendation |
| CP-048 | Policy | policy.md:647 | rules carry across versions except versions written after untrusted content | User's choice |
| CP-049 | Policy | policy.md:799; 1247 (unmarked) | Keep as specified | User's choice |
| CP-050 | Policy | policy.md:825 | Keep as specified | User's choice |
| CP-052 | Policy | policy.md:894 | a compact digest of the user's mini app actions enters the bot's next turn; timer and job calls stay in the activity log except failures | Left to the recommendation |
| CP-053 | Policy | policy.md:954; 1248 (unmarked) | Keep as specified | User's choice |
| CP-054 | Policy | policy.md:1017; 1249 (unmarked) | coalesce identical reads but keep each read's paths in the row | User's choice |
| CP-055 | Policy | policy.md:1023; 1258 (unmarked) | per-device chains replicated read-only and merged on export | User's choice |
| CP-070 | Policy | policy.md:190 | Keep as specified | User's choice |
| CP-071 | Policy | policy.md:307 | write via a temp file then rename inside the verified directory | User's choice |
| CP-072 | Policy | policy.md:371 | in-process gateway for app tools; a loopback proxy with a random per-launch credential only for WebKit (and iSH if needed), bound only while needed | Left to the recommendation |
| CP-073 | Policy | policy.md:473; 900 (unmarked) | on-screen blocks stay in the frame; blocked background jobs also post one Inbox item | User's choice |
| CP-074 | Policy | policy.md:545 | record loaded memory entries by ID and content hash, not copies | User's choice |
| CP-075 | Policy | policy.md:886 | inline bold, italic, code and sanitized links (https only, domain shown, opened in the in-app browser); no images | User's own choice |
| CP-076 | Policy | policy.md:1189 | the same policy speed targets on the iPhone 14 Pro, measured in Phase 3 | User's choice |
| CP-015 | JSON cards | cards.md:13; 574 (unmarked) | Keep as specified | User's choice |
| CP-016 | JSON cards | cards.md:70 | collapse a replaced card to a one-line Updated link; disable its buttons | User's choice |
| CP-017 | JSON cards | cards.md:128 | Keep as specified | User's choice |
| CP-018 | JSON cards | cards.md:138 | Keep as specified | User's choice |
| CP-019 | JSON cards | cards.md:161 | keep the fallback row and tell the bot which blocks failed | User's choice |
| CP-056 | JSON cards | cards.md:109 | raw typed values formatted in the user's locale; a plain-text fallback allowed, marked as text | Left to the recommendation |
| CP-057 | JSON cards | cards.md:111; policy.md:887 (unmarked) | each device remembers a card's last tab (not synced) | Left to the recommendation |
| CP-058 | JSON cards | cards.md:111 | Keep as specified | User's choice |
| CP-020 | Versions | cards.md:163, 522 | bots target the runner's newest version; a device that cannot draw something shows a fallback with Update Memoshi | Left to the recommendation |
| CP-001 | Engine | cards.md:277 | Settled by D72 | Already decided |
| CP-002 | Engine | cards.md:224; policy.md:905 | Settled by D78 | Already decided |
| CP-003 | Kit | cards.md:313, 581 | Settled by D72 | Already decided |
| CP-004 | Mini apps | cards.md:550, 580 | Settled by D73 | Already decided |
| CP-005 | Mini apps | cards.md:551 | Settled by D72 | Already decided |
| CP-007 | Mini apps | cards.md:545; policy.md:592, 903 | Settled by D72 | Already decided |
| CP-031 | Mini apps | cards.md:549, 374 | Settled by D71 | Already decided |
| CP-006 | Bridge | cards.md:339; policy.md:592, 903 | Settled by D72 | Already decided |
| CP-008 | Policy | policy.md:1262 | Settled by D72 | Already decided |
| CP-009 | Policy | policy.md:120, 400 | Settled by D76 | Already decided |
| CP-010 | Policy | policy.md:60, 313, 319; 1259 (unmarked) | Settled by D76 | Already decided |
| CP-040 | Policy | policy.md:372, 404 | Settled by D76 | Already decided |
| CP-051 | Policy | policy.md:872 | Settled by D51 | Already decided |
| CP-059 | App Review (later) | cards.md:188, 567 | Settled by D67 | Already decided |

<a id="table-2"></a>
## Table 2: the object model, protocol and events (D82)

From the specs `object-model.md`, `protocol.md`, `events.md` and `bot-definition.md`. 15 rows were already settled by D46 and D71–D78; of the other 49, 18 were kept, 30 changed and one matched a table 1 outcome. The user approved the keeps as a list and chose every change row by row.

| ID | Area | Where | Outcome | Chosen by |
|---|---|---|---|---|
| MP-005 | Lease failover | object-model.md:1411 | D73's write-ahead intents, plus stranded commits rejoin like a side thread. +~2 days [INFERENCE] | User's choice |
| MP-008 | Durable waits | object-model.md:419, 1128 | Keep as specified | User's choice |
| MP-009 | Pairing security | protocol.md:657, 887 | Noise IKpsk2 with the QR key as the pre-shared key, no PAKE; it authenticates adding the device to the MLS group | User's choice |
| MP-012 | Replication scope | object-model.md:216 | Keep as specified | User's choice |
| MP-013 | Device selection | object-model.md:1408 | awake device with the data and grant; prefer the user's pin, then mains power. | User's choice |
| MP-014 | Device links | protocol.md:669 | race links Happy Eyeballs-style in D48's order; upgrade when direct appears. +~1 day [INFERENCE] | User's choice |
| MP-015 | Device wire format | protocol.md:638 | Keep as specified | User's choice |
| MP-016 | Live streaming | events.md:680 | stream UI frames only to devices focusing the conversation, coalesced to ~10/s. +~1 day [INFERENCE] | User's choice |
| MP-017 | Cross-device calls | protocol.md:744 | on expiry return `device_unreachable` (never dispatched), not a denial. | User's choice |
| MP-019 | Side-thread summary | object-model.md:967, 1413 | the bot's model writes the gist (the on-device model when offline, D80); an exact list of effects is appended | User's choice |
| MP-020 | Side-thread tools | object-model.md:976 | Keep as specified | User's choice |
| MP-021 | Audit across devices | object-model.md:882, 1410 | verify every chain; devices sign their chain heads and peers anchor them. +~2 days [INFERENCE] | User's choice |
| MP-023 | Background timing | object-model.md:512 | relay sends content-free wake pushes at fire times; past a grace window, apply missedRun. +~2 days [INFERENCE] | User's choice |
| MP-024 | Mac Python | object-model.md:582 | Keep as specified | User's choice |
| MP-026 | Tool effects | object-model.md:992 | Keep as specified | User's choice |
| MP-027 | MCP tools | object-model.md:1004 | Keep as specified | User's choice |
| MP-028 | Live card source | object-model.md:705 | reject the publish with a compile error at the secret's line. | User's choice |
| MP-029 | Program tool calls | object-model.md:423, 1330 | Keep as specified | User's choice |
| MP-030 | Interrupted steps | object-model.md:419 | the tool result also says it was interrupted, when, and how it settled. | User's choice |
| MP-031 | Bot context | object-model.md:1323 | keep them model-visible, carrying their source run's exposure flags into context. | User's choice |
| MP-034 | Notebooks across devices | object-model.md:1414 | sync the notebook's folder to the kernel device, content-addressed; outputs sync back. +~3 days [INFERENCE] | User's choice |
| MP-037 | Import mode | bot-definition.md:590 | sheet offers the file's mode, default Ask first; Bypass via its confirmation. | User's choice |
| MP-038 | Run limits | object-model.md:282 | daily cap = scheduled fires plus margin; keep 48 for event triggers. | User's choice |
| MP-039 | IDs | object-model.md:17 | Keep as specified | User's choice |
| MP-040 | Bot handle | object-model.md:273 | Keep as specified | User's choice |
| MP-041 | Per-device setup | object-model.md:304 | create records on arrival; folders and WebKit stores on first use. | User's choice |
| MP-042 | Computers | object-model.md:571 | any paired device that reaches the host connects, with the D75-synced key. +~2 days [INFERENCE] | User's choice |
| MP-043 | Computers | object-model.md:579 | Keep as specified | User's choice |
| MP-044 | Revocation | object-model.md:908; protocol.md:685 | Keep as specified | User's choice |
| MP-045 | Side threads | object-model.md:975 | one open side thread per parent conversation (Chat or Session). | User's choice |
| MP-046 | Side threads | object-model.md:978 | replicate the joined side thread read-only, like other conversations. +~1 day [INFERENCE] | User's choice |
| MP-047 | Notebooks | object-model.md:1008 | Keep as specified | User's choice |
| MP-048 | Notebooks | object-model.md:1017 | holding device by default; a reachable Mac when imports need Mac-only packages. +~1 day [INFERENCE] | User's choice |
| MP-050 | Notebooks | object-model.md:1023 | Keep as specified | User's choice |
| MP-051 | Notebooks | object-model.md:1025 | mark outputs stale after a kernel restart; offer one-tap Run all above. +~1 day [INFERENCE] | User's choice |
| MP-049 | Run status enums | object-model.md:1018, 1046 | one enum for notebooks and mini apps: ok, error, interrupted, canceled, limit_reached. | User's choice |
| MP-052 | Mini app look | object-model.md:1041 | SF Symbol on a colored tile, Shortcuts-style; the user can change both | User's choice |
| MP-053 | Mini app lists | object-model.md:1047 | pinned first, then unpinned apps by last use. | User's choice |
| MP-054 | Mini app versions | object-model.md:1052, 1416 | keep all sources; snapshots 30 days, always the last 3, within a size budget. | User's choice |
| MP-055 | iSH connection | object-model.md:1332 | same as CP-046 (D81): the host-side adapter by default | Already decided |
| MP-056 | Local transport | protocol.md:44 | Originally NWListener with NWProtocolWebSocket and a backpressure-only NIO fallback; [D95](decisions.md#d95) supersedes that selection with exact-pinned SwiftNIO on both sides for same-FD peer authentication. | User's choice, amended by D95 |
| MP-057 | Versioning | protocol.md:150 | Keep as specified | User's choice |
| MP-058 | Pairing | protocol.md:658, 887 | 5 minutes, and void as soon as the QR screen closes. | User's choice |
| MP-059 | Replication | protocol.md:723 | Keep as specified | User's choice |
| MP-060 | Crash recovery | events.md:602 | consume the change feed from a cursor saved in D atomically; scan as fallback. | User's choice |
| MP-061 | Retention | events.md:611 | Keep as specified | User's choice |
| MP-062 | bot.md parsing | bot-definition.md:49 | keep depth 10; raise the node cap to 100,000. | User's choice |
| MP-063 | Import first run | bot-definition.md:277 | app-built setup checklist card; the intro turn only restates the job. +~1 day [INFERENCE] | User's choice |
| MP-064 | Signing (v2) | bot-definition.md:576 | Keep as specified | User's choice |
| MP-001 | Multi-device writes | object-model.md:215, 224; protocol.md:718 | Settled by D73 | Already decided |
| MP-002 | Offline intents | protocol.md:337, 718 | Settled by D73 | Already decided |
| MP-003 | Lease hand-over | protocol.md:715 | Settled by D73 | Already decided |
| MP-004 | Lease authority | protocol.md:714, 884 | Settled by D73 | Already decided |
| MP-006 | Where work runs | object-model.md:223 | Settled by D74 | Already decided |
| MP-007 | Background work | object-model.md:1412 | Settled by D74 | Already decided |
| MP-010 | iCloud encryption | protocol.md:677, 885 | Settled by D75 | Already decided |
| MP-011 | User-level sync | object-model.md:218, 1409 | Settled by D73 | Already decided |
| MP-018 | Mini app data sync | object-model.md:1060, 1415 | Settled by D73 | Already decided |
| MP-022 | iOS execution | object-model.md:1235, 1253 | Settled by D46 | Already decided |
| MP-025 | Browser sessions | object-model.md:602 | Settled by D75 | Already decided |
| MP-032 | Mini app data size | object-model.md:1044 | Settled by D71 | Already decided |
| MP-033 | Groups (v1.1) | object-model.md:1405 | Settled by D74 | Already decided |
| MP-035 | iOS app architecture | protocol.md:13, 75, 427, 888 | Settled by D78 | Already decided |
| MP-036 | Schema and codegen | protocol.md:870; README.md:47 | Settled by D78 | Already decided |

<a id="table-3"></a>
## Table 3: the architecture, computers and browsers (D83)

From `04-architecture.md` and `06-computers-and-browsers.md`. 27 rows were already settled by D46–D80; of the other 107, 67 were kept, 36 changed and 4 matched earlier outcomes. The user approved the keeps as a list and chose every change row by row.

| ID | Area | Where | Outcome | Chosen by |
|---|---|---|---|---|
| AC-002 | Hand-over | 04:263 | Keep as specified | User's choice |
| AC-003 | Approvals across devices | 04:263 | Keep as specified | User's choice |
| AC-004 | Background runs | 04:267 | routines and watches get their own lanes and leases; wakes stay in their conversation. +~2 days [INFERENCE] | User's choice |
| AC-006 | CloudKit lease | 04:272, 04:274 | Keep as specified | User's choice |
| AC-012 | Always-on Mac (v1.1) | 06:696, 06:1146 | an always-on Mac becomes every bot's home Mac by default (with AC-035) | User's choice |
| AC-015 | iOS egress | 06:28, 06:42, 06:43, 06:203, 06:577, 04:559 | Keep as specified | User's choice |
| AC-016 | iOS browser egress | 06:203, 06:758, 06:1142 | Keep as specified | User's choice |
| AC-017 | Python on iOS | 04:765, 04:770, 06:197 | D76 (network through the in-app gateway); files keep being copied in and out (CP-043) | Already decided |
| AC-018 | iSH connection | 04:243, 04:582, 06:117, 06:231, 06:1149 | D81 (CP-046): the host-side adapter by default; the probe confirms | Already decided |
| AC-019 | iSH network | 06:235, 06:1149 | Keep as specified | User's choice |
| AC-021 | iSH policy tier | 06:234 | Keep as specified | User's choice |
| AC-028 | Hosting VMs (v1.1) | 04:186, 06:600 | Keep as specified | User's choice |
| AC-029 | VM shares (v1.1) | 06:525 | Keep as specified | User's choice |
| AC-030 | iCloud link | 04:273 | Keep as specified | User's choice |
| AC-031 | iCloud link | 04:275 | fetch at launch, wake and relay nudges; keep a slow backstop timer. | User's choice |
| AC-032 | Mac wake | 04:190 | IOKit sleep and wake notifications; keep the clock-jump check as backstop. | User's choice |
| AC-034 | Offline side threads | 06:220 | Keep as specified | User's choice |
| AC-035 | Two Macs | 06:222, 06:1143 | the bot's home Mac, set per bot; it also receives idle leases. | User's choice |
| AC-036 | Live view across devices | 06:899, 06:1144 | screencast to any device, with takeover by forwarded input. +~4 days [INFERENCE] | User's choice |
| AC-037 | Code layout | 04:279, 04:307, 04:1081 | Keep as specified | User's choice |
| AC-039 | SQLite concurrency | 04:317 | reads stay on read connections; FTS rebuilds run batched on the writer. | User's choice |
| AC-040 | Harness pool | 04:374 | a lower starting cap on iPhone and iPad, say 16; S1 tunes both. | User's choice |
| AC-041 | Prompt context | 04:426 | Keep as specified | User's choice |
| AC-042 | Subagents | 04:489 | keep depth 1; allow 8 at once, queueing the rest, under budgets. | User's choice |
| AC-043 | Code Mode | 04:530 | Code Mode scripts may call models within budget slices plus a per-script spend cap | User's choice |
| AC-044 | Run origin | 04:627 | record every steer's origin in the outbox too, whatever Phase 0 finds. | User's choice |
| AC-045 | Resume after a crash | 04:679 | hold the whole file per D79: skip its resume, queue new messages. | User's choice |
| AC-046 | Credentials | 04:704 | Keep as specified | User's choice |
| AC-049 | Transcript list | 04:1142 | Keep as specified | User's choice |
| AC-050 | Search | 04:1224 | Keep as specified | User's choice |
| AC-051 | Performance budget | 04:1277 | under 2.0 s p95, the same as with the daemon running. | User's choice |
| AC-052 | Performance budget | 04:1286 | Keep as specified | User's choice |
| AC-053 | Performance budget | 04:1287 | under 100 ms p95 on the runner; S2 sets a cross-device budget. | User's choice |
| AC-054 | Performance budget | 04:1291 | Keep as specified | User's choice |
| AC-117 | Performance budget | 04:1278 | under 500 ms. | User's choice |
| AC-118 | Performance budget | 04:1281 | under 50 ms p95. | User's choice |
| AC-119 | Performance budget | 04:1288 | Keep as specified | User's choice |
| AC-055 | Python runs | 04:763 | Keep as specified | User's choice |
| AC-056 | Python packages | 04:764 | Keep as specified | User's choice |
| AC-058 | Pyodide lifetime | 04:151, 04:766, 06:200 | an open notebook counts as active, keeping its Pyodide warm. | User's choice |
| AC-060 | Package installs on iOS | 04:765, 06:198, 06:229 | Keep as specified | User's choice |
| AC-061 | Python routing | 04:767 | Keep as specified | User's choice |
| AC-062 | Notebook kernel (Mac) | 04:769, 06:356 | Keep as specified | User's choice |
| AC-063 | Notebook kernel | 04:769 | Keep as specified | User's choice |
| AC-064 | Python secrets (Mac) | 04:770, 06:358 | Keep as specified | User's choice |
| AC-065 | Python interpreter (Mac) | 06:353, 06:1147 | memoshid installs one pinned, hash-checked CPython once; bots share it read-only and keep their own packages | User's choice |
| AC-066 | Python egress | 06:354 | Keep as specified | User's choice |
| AC-067 | Python limits | 06:357 | Keep as specified | User's choice |
| AC-068 | Mini apps | 04:786 | Keep as specified | User's choice |
| AC-070 | Mini app versions | 04:1367 | run the last compatible version read-only, with an Update Memoshi banner. | User's choice |
| AC-071 | Swift engine limits | 04:774, 04:789 | D71 removed the data cap; timer and in-flight call caps stay as specified (CP-025) | Already decided |
| AC-072 | Swift engine probe | 04:799, 04:1292 | Keep as specified | User's choice |
| AC-073 | Swift engine probe | 04:800, 04:1292 | 120 fps on the ProMotion reference devices (D80); 60 fps as floor. | User's choice |
| AC-074 | Swift engine probe | 04:803 | at least 90% within one fix round. | User's choice |
| AC-103 | Swift engine probe | 04:801 | Keep as specified | User's choice |
| AC-076 | iSH lifecycle | 04:152, 06:159, 06:236, 06:983 | Keep as specified | User's choice |
| AC-077 | iSH memory | 06:969 | D80 (heavy runtimes take turns on the iPhone); the iSH probe sets the iPad's cap | Already decided |
| AC-078 | iSH root file system | 06:63, 06:1149 | bundle Alpine's minirootfs; update each bot's copy with apk upgrade under policy. | User's choice |
| AC-079 | iSH files | 06:43, 06:229 | Keep as specified | User's choice |
| AC-080 | iSH security | 06:234 | Keep as specified | User's choice |
| AC-081 | iSH fallback | 06:238, 06:1104 | use the Mac's shell first, as D79 does for Python; then Blink, then v86. | User's choice |
| AC-082 | iSH probe | 06:1095, 04:1293 | Keep as specified | User's choice |
| AC-083 | iSH probe | 06:1096, 04:1293 | Keep as specified | User's choice |
| AC-084 | iSH probe | 06:1098 | Keep as specified | User's choice |
| AC-085 | iSH probe | 06:1099 | Keep as specified | User's choice |
| AC-104 | iSH probe | 06:1097 | Keep as specified | User's choice |
| AC-086 | iOS folders | 06:184 | Keep as specified | User's choice |
| AC-087 | iOS browser input | 06:755-756 | Keep as specified | User's choice |
| AC-088 | iOS browsing in the background | 06:755, 06:757 | Keep as specified | User's choice |
| AC-089 | iOS uploads | 06:866 | Keep as specified | User's choice |
| AC-090 | Browser memory | 06:966 | on iPhone, 2 tabs per bot and 4 in total, closing on pressure. | User's choice |
| AC-091 | S3 on iOS | 06:1049 | Keep as specified | User's choice |
| AC-093 | SSH keys (v1.1) | 04:1075, 06:506 | Keep as specified | User's choice |
| AC-094 | Choosing a computer (v1.1) | 06:49 | Keep as specified | User's choice |
| AC-095 | Shared VMs (v1.1) | 06:64 | one Linux user per bot on a shared VM. | User's choice |
| AC-096 | VM access (v1.1) | 04:580 | Keep as specified | User's choice |
| AC-097 | Guest daemon (v1.1) | 06:404, 06:1146 | VM guests run upstream's Linux pi-env daemon, since iSH uses the host-side adapter (D81) | User's choice |
| AC-098 | VM worktrees (v1.1) | 06:524 | Keep as specified | User's choice |
| AC-099 | Image licensing (v1.1) | 06:501 | publish the full source packages beside each image, plus the manifest. +~1 day [INFERENCE] | User's choice |
| AC-100 | VM wake (v1.1) | 06:445-453, 04:1298 | Keep as specified | User's choice |
| AC-101 | SSD writes (v1.1) | 06:1001 | Keep as specified | User's choice |
| AC-102 | Cloud computer (v2) | 06:703 | Keep as specified | User's choice |
| AC-105 | Python processes (Mac) | 04:145, 06:356 | a kernel lives while its notebook is open, then 10 idle minutes. | User's choice |
| AC-106 | MCP stdio servers | 04:148 | stop after 10 idle minutes, like pi-env; restart on the next call. | User's choice |
| AC-107 | iOS boot | 04:283 | Keep as specified | User's choice |
| AC-108 | Module split | 04:297 | Keep as specified | User's choice |
| AC-110 | Environment ids | 04:586 | Keep as specified | User's choice |
| AC-111 | Retention | 04:1008 | Keep as specified | User's choice |
| AC-112 | Backups on iOS | 04:1026 | Keep as specified | User's choice |
| AC-113 | Push fallback | 04:1176 | Keep as specified | User's choice |
| AC-114 | Testing | 04:1242 | a Swift-native validator, keeping Node out of the repo (D46). | User's choice |
| AC-115 | Testing | 04:1245 | promote S2's harness, plus deterministic simulation of clocks and networks in CI. +~4 days [INFERENCE] | User's choice |
| AC-120 | Context meter | 04:1338 | Keep as specified | User's choice |
| AC-121 | Relaunching hidden | 04:213 | use `NSWorkspace.openApplication` with `activates = false` and `hides = true`. | User's choice |
| AC-122 | Updates | 04:218 | Keep as specified | User's choice |
| AC-123 | Quitting (v1.1) | 04:185 | save VMs silently on quit; confirm only when a run is active. | User's choice |
| AC-124 | VM clock (v1.1) | 04:190 | Keep as specified | User's choice |
| AC-125 | VM display (v1.1) | 06:377 | Keep as specified | User's choice |
| AC-126 | VM snapshots (v1.1) | 06:582 | Keep as specified | User's choice |
| AC-127 | VM engine comparison (v1.1) | 06:619 | Keep as specified | User's choice |
| AC-128 | VM display fallback (v1.1) | 06:642 | fall back first to a VNC server in the guest over vsock | Left to the recommendation |
| AC-129 | Size estimates | 06:44, 06:989-997 | Keep as specified | User's choice |
| AC-130 | Inspector | 06:894 | Keep as specified | User's choice |
| AC-131 | Phase 2 exit | 06:1027 | add Python-specific escapes: ctypes, subprocess, raw sockets, proxy bypass. | User's choice |
| AC-132 | Phase 3 exit | 06:1030 | also re-run the probe's memory and battery soak, plus a swipe-away test. | User's choice |
| AC-133 | Notebook edits | 04:769 | Keep as specified | User's choice |
| AC-134 | Python results | 04:768 | Keep as specified | User's choice |
| AC-001 | Pi storage and lease | 04:17 | Settled by D74 | Already decided |
| AC-005 | Replicating app records | 04:270 | Settled by D73 | Already decided |
| AC-007 | Replication | 04:1001 | Settled by D74 | Already decided |
| AC-008 | Deletion | 04:1047 | Settled by D74 | Already decided |
| AC-009 | Version skew | 04:225 | Settled by D74 | Already decided |
| AC-010 | Stop all bots | 04:193 | Settled by D75 | Already decided |
| AC-011 | Local models | 04:701 | Settled by D74 and D80 | Already decided |
| AC-013 | iOS UI-to-engine API | 04:237, 04:1137 | Settled by D78 | Already decided |
| AC-014 | iOS trust boundary | 04:244, 04:1204 | Settled by D76 | Already decided |
| AC-020 | iSH app commands | 04:738, 06:230 | Settled by D69 | Already decided |
| AC-022 | Mac app commands | 04:737, 04:1217 | Settled by D77 | Already decided |
| AC-023 | S4 sandbox gate | 06:1071, 06:1145 | Settled by D77 | Already decided |
| AC-024 | Mac sandbox symlinks | 06:293 | Settled by D77 | Already decided |
| AC-025 | Registration | 04:172 | Settled by D58 | Already decided |
| AC-026 | Mac sleep | 06:981 | Settled by D77 | Already decided |
| AC-027 | Browser sign-ins | 06:726 | Settled by D75 | Already decided |
| AC-033 | Budgets across devices | 04:714 | Settled by D76 | Already decided |
| AC-038 | GPL boundary | 04:26 | Settled by D69 | Already decided |
| AC-047 | iOS storage | 04:1073 | Settled by D79 | Already decided |
| AC-048 | Code generation | 04:1113 | Settled by D78 | Already decided |
| AC-057 | Pyodide instances | 04:765, 06:968, 06:1148 | Settled by D76 | Already decided |
| AC-059 | Python fallback on iOS | 04:766, 06:201 | Settled by D79 | Already decided |
| AC-069 | Mini apps offline | 04:1366 | Settled by D73 | Already decided |
| AC-075 | iSH scope | 06:49, 06:215 | Settled by D69 | Already decided |
| AC-092 | macOS prompts | 06:295, 06:692 | Settled by D58 | Already decided |
| AC-109 | Code Mode fallback | 04:533 | Settled by D64 | Already decided |
| AC-116 | Performance reference | 04:1272 | Settled by D80 | Already decided |

<a id="table-4"></a>
## Table 4: the platform, bots and the Assistant (D84)

From `09-platform-macos.md` and `05-bots-and-assistant.md`. 14 rows were already settled by D44–D79; of the other 95, 59 were kept and 36 changed. The user approved the keeps as a list and chose every change row by row, leaving one to the recommendation.

| ID | Area | Where | Outcome | Chosen by |
|---|---|---|---|---|
| PB-003 | Device security on iOS (08 Q10, Q13 own it) | `09-platform-macos.md:803` | audit chains copied read-only (D81); views and exports merge them in clock order, verifying each | User's choice |
| PB-005 | Python on iOS | `09-platform-macos.md:848` | S6 also tests Lockdown Mode; detect it and route Python to the Mac | User's choice |
| PB-010 | Runs: concurrency | `05-bots-and-assistant.md:31, :423` | keep 2/bot and 6/device; defer starts when hot or in Low Power | User's choice |
| PB-011 | Runs: run limits | `05-bots-and-assistant.md:57, :1025, :420` | maxTokens excludes cache reads; other limits unchanged | User's choice |
| PB-012 | Budgets: bot defaults | `05-bots-and-assistant.md:1016, :131, :1007-1013, :1134-1138, :1155` | keep the per-bot defaults and add an account-wide monthly cap set at onboarding | User's choice |
| PB-013 | Prompt budget | `05-bots-and-assistant.md:58, :1232, :1222, :1226` | Keep as specified | User's choice |
| PB-014 | Memory: per-turn load | `05-bots-and-assistant.md:36, :513-515` | Keep as specified | User's choice |
| PB-015 | Memory: store caps | `05-bots-and-assistant.md:40, :547` | Keep as specified | User's choice |
| PB-016 | Memory: ranking | `05-bots-and-assistant.md:519` | kind-specific half-lives: facts and preferences 180 days, procedures 90, others 30 | User's choice |
| PB-017 | Memory: conflict check | `05-bots-and-assistant.md:602` | top-5 FTS candidates judged by the on-device model, utility model fallback +~1 day [INFERENCE] | User's choice |
| PB-018 | Wakes: caps | `05-bots-and-assistant.md:45, :705-712, :1275` | Keep as specified | User's choice |
| PB-019 | Watches: detection | `05-bots-and-assistant.md:47, :729-733` | feed watches fire on the first new item; other kinds keep confirmation | User's choice |
| PB-020 | Watches: fires and failures | `05-bots-and-assistant.md:49, :736, :741, :1272` | Keep as specified | User's choice |
| PB-021 | Handoffs: limits | `05-bots-and-assistant.md:55, :975, :207, :919, :934` | Keep as specified | User's choice |
| PB-022 | Bot identity: persona | `05-bots-and-assistant.md:25, :71` | Keep as specified | User's choice |
| PB-023 | Assistant: new-bot proposals | `05-bots-and-assistant.md:266` | Keep as specified | User's choice |
| PB-024 | Triggers: connector events | `05-bots-and-assistant.md:673` | coalesce 60 s, widening to 15 min under bursts; ≤12 runs an hour +~0.5 days [INFERENCE] | User's choice |
| PB-025 | Teach-by-demonstration (v1.1): retention | `05-bots-and-assistant.md:1180` | Keep as specified | User's choice |
| PB-026 | Bot creation: intro turn | `05-bots-and-assistant.md:299` | Keep as specified | User's choice |
| PB-027 | Runs: missing report | `05-bots-and-assistant.md:414` | post a non-empty final answer as an unnotified update, flagged auto-posted | User's choice |
| PB-028 | Memory: consolidation device | `05-bots-and-assistant.md:656, :1278` | run on the Chat's runner; the pass carries its lease epoch, stale passes discarded | User's choice |
| PB-029 | Budgets across devices | `05-bots-and-assistant.md:1031, :1278` | side threads reserve a slice if the authority answers, else a held standby slice +~0.5 days [INFERENCE] | User's choice |
| PB-030 | Routines: cancel_previous | `05-bots-and-assistant.md:770` | Keep as specified | User's choice |
| PB-031 | Auto-pause when away | `05-bots-and-assistant.md:786` | Keep as specified | User's choice |
| PB-032 | Handoffs: verification | `05-bots-and-assistant.md:949` | deterministic checks first; a failed check blocks acceptance; model reviews the rest | User's choice |
| PB-034 | Skills: name collisions | `05-bots-and-assistant.md:1108` | bot, then global, then project; warn when a skill is shadowed | User's choice |
| PB-036 | OS floor: revisit trigger | `09-platform-macos.md:56` | drop the trigger; the current-and-previous policy sets the floor | User's choice |
| PB-037 | OS support after v1 | `09-platform-macos.md:58, :884` | Keep as specified | User's choice |
| PB-038 | Liquid Glass over live views | `09-platform-macos.md:135` | a detached live view uses the standard window toolbar, with the live view laid out below it, never under it | Left to the recommendation |
| PB-039 | App Intents: authentication | `09-platform-macos.md:203` | Keep as specified | User's choice |
| PB-040 | Bot computers (v1.1): Rosetta | `09-platform-macos.md:38` | Keep as specified | User's choice |
| PB-041 | Hardening: Enhanced Security | `09-platform-macos.md:422` | adopt from Phase 1 for memoshid; engine helper from its first build +~1 day [INFERENCE] | User's choice |
| PB-042 | Node fallback ship path | `09-platform-macos.md:460, :890` | a time-boxed Node packaging spike only if the Mac misses the gate | User's choice |
| PB-043 | LaunchAgent: ProcessType | `09-platform-macos.md:480` | Keep as specified | User's choice |
| PB-044 | Uninstall | `09-platform-macos.md:510, :889` | uninstall leaves the device group and deletes only this device's iCloud records +~0.5 days [INFERENCE] | User's choice |
| PB-045 | Updates: leases | `09-platform-macos.md:706, :888` | a maintenance hold extends the Mac's leases; normal expiry if the restart overruns +~0.5 days [INFERENCE] | User's choice |
| PB-046 | GPL-3.0: friends' builds | `09-platform-macos.md:771, :860, :895` | Keep as specified | User's choice |
| PB-047 | iOS memory pressure | `09-platform-macos.md:788, :863` | Keep as specified | User's choice |
| PB-048 | Push: self-hosted relay | `09-platform-macos.md:801` | Keep as specified | User's choice |
| PB-049 | Notifications: content on iOS | `09-platform-macos.md:802` | Keep as specified | User's choice |
| PB-050 | iSH: debug server | `09-platform-macos.md:862` | Keep as specified | User's choice |
| PB-051 | GUI computer use (v1.1) | `09-platform-macos.md:288` | Keep as specified | User's choice |
| PB-052 | Peer checks: code requirement | `09-platform-macos.md:341` | Keep as specified | User's choice |
| PB-054 | Hardening: debugger | `09-platform-macos.md:420` | Keep as specified | User's choice |
| PB-055 | Privacy prompts for memoshid | `09-platform-macos.md:582, :592, :880` | Keep as specified | User's choice |
| PB-056 | Updates: rollback | `09-platform-macos.md:707` | Keep as specified | User's choice |
| PB-057 | iOS memory entitlement | `09-platform-macos.md:788, :841, :894` | enable increased-memory-limit and extended-virtual-addressing from Phase 3 | User's choice |
| PB-058 | iOS Local Network: multicast | `09-platform-macos.md:797` | Keep as specified | User's choice |
| PB-059 | iOS background browsing | `09-platform-macos.md:816, :892` | browse inside the turn's continued-processing task; pause and resume if WebKit suspends | User's choice |
| PB-060 | iSH in the background | `09-platform-macos.md:863` | Keep as specified | User's choice |
| PB-061 | Bot identity: handle | `05-bots-and-assistant.md:23` | ≤24 chars, unique ignoring case; reserved handles such as @assistant and @memoshi | User's choice |
| PB-062 | Bot identity: job line | `05-bots-and-assistant.md:24, :72, :1132` | Keep as specified | User's choice |
| PB-063 | Proposals: expiry and re-proposal | `05-bots-and-assistant.md:28, :820` | declines block 30 days, then 90; a third blocks until the user asks | User's choice |
| PB-064 | Memory: pins | `05-bots-and-assistant.md:37, :529` | cap pins by their block's bytes, not count; refuse a pin that won't fit | User's choice |
| PB-065 | Memory: consolidation cost | `05-bots-and-assistant.md:41, :592` | Keep as specified | User's choice |
| PB-066 | Memory: undo window | `05-bots-and-assistant.md:42, :595, :630` | Keep as specified | User's choice |
| PB-067 | Proactivity: per-bot caps | `05-bots-and-assistant.md:44` | ≤20 routines and ≤50 watches per bot | User's choice |
| PB-068 | Watches: check limits | `05-bots-and-assistant.md:48, :722-723` | Keep as specified | User's choice |
| PB-069 | Runs: recent summaries | `05-bots-and-assistant.md:692` | Keep as specified | User's choice |
| PB-070 | Wakes: after a pause | `05-bots-and-assistant.md:716` | fire once whatever the delay, telling the bot how late | User's choice |
| PB-071 | Budgets: routines (Phase 3) | `05-bots-and-assistant.md:1016` | 1.5 × preview, rounded up; cap at the bot's monthly limit, not remaining | User's choice |
| PB-072 | Cost preview: watches | `05-bots-and-assistant.md:1049` | Keep as specified | User's choice |
| PB-073 | Cost preview: run prior | `05-bots-and-assistant.md:1054-1059, :1274` | this prior until the ledger has runs, then the user's own medians per effort +~0.5 days [INFERENCE] | User's choice |
| PB-074 | Skills: learning loop | `05-bots-and-assistant.md:1119` | ≤1 unsolicited skill proposal per bot per week; user requests always go through | User's choice |
| PB-075 | Groups (v1.1): member turn | `05-bots-and-assistant.md:53, :873` | Keep as specified | User's choice |
| PB-076 | Groups (v1.1): budget | `05-bots-and-assistant.md:845, :1014` | Keep as specified | User's choice |
| PB-077 | Groups (v1.1): loop guard | `05-bots-and-assistant.md:902` | Keep as specified | User's choice |
| PB-078 | Bot status | `05-bots-and-assistant.md:94` | Keep as specified | User's choice |
| PB-079 | Assistant: routing | `05-bots-and-assistant.md:191` | Keep as specified | User's choice |
| PB-082 | Watches: file-check placement | `05-bots-and-assistant.md:727` | Keep as specified | User's choice |
| PB-083 | Prompt: section order | `05-bots-and-assistant.md:1193` | Keep as specified | User's choice |
| PB-084 | Memory audit in Bypass | `05-bots-and-assistant.md:644` | Keep as specified | User's choice |
| PB-085 | Daily brief: cost | `05-bots-and-assistant.md:255` | Keep as specified | User's choice |
| PB-086 | OS floor: cost signal | `09-platform-macos.md:42, :57` | drop the Phase 2 count; the current-and-previous policy decides | User's choice |
| PB-087 | Foundation Models: timeouts | `09-platform-macos.md:172` | Keep as specified | User's choice |
| PB-088 | Size budget | `09-platform-macos.md:438-440` | set budgets from S5 measurements; CI fails on >10% growth per component | User's choice |
| PB-089 | TestFlight freshness | `09-platform-macos.md:639` | Keep as specified | User's choice |
| PB-090 | Export API | `09-platform-macos.md:95` | Keep as specified | User's choice |
| PB-091 | SMAppService: notFound | `09-platform-macos.md:491` | Keep as specified | User's choice |
| PB-092 | memoshid: resource loading | `09-platform-macos.md:502` | Keep as specified | User's choice |
| PB-093 | App Sandbox: bookmarks | `09-platform-macos.md:608, :617` | Keep as specified | User's choice |
| PB-094 | Release signing (iOS) | `09-platform-macos.md:647` | Keep as specified | User's choice |
| PB-095 | Provisioning profiles | `09-platform-macos.md:655, :887` | Keep as specified | User's choice |
| PB-096 | First launch | `09-platform-macos.md:665` | Keep as specified | User's choice |
| PB-097 | iOS Local Network prompt | `09-platform-macos.md:796` | Keep as specified | User's choice |
| PB-098 | iOS linked folders | `09-platform-macos.md:811` | Keep as specified | User's choice |
| PB-100 | Licence build check | `09-platform-macos.md:862` | Keep as specified | User's choice |
| PB-102 | Bundle: resource bundles | `09-platform-macos.md:378` | put the bundles in memoshid.app's own Resources, Xcode's default for that target | User's choice |
| PB-103 | Supply chain: rg and fd | `09-platform-macos.md:379` | compile the downloader out with a build flag before ever linking PiCodingAgent | User's choice |
| PB-104 | Notarization (v1.1) | `09-platform-macos.md:432` | Keep as specified | User's choice |
| PB-105 | Diagnostics | `09-platform-macos.md:520` | Keep as specified | User's choice |
| PB-106 | iCloud entitlement | `09-platform-macos.md:547` | Production in every build on the user's devices, Xcode installs included | User's choice |
| PB-107 | Privacy: iCloud Drive | `09-platform-macos.md:582` | test iCloud Drive grants separately in S5, with Desktop & Documents sync on | User's choice |
| PB-108 | Application Firewall | `09-platform-macos.md:584` | Keep as specified | User's choice |
| PB-109 | Homebrew cask | `09-platform-macos.md:725` | Keep as specified | User's choice |
| PB-001 | Credentials across devices | `09-platform-macos.md:319, :886` | Settled by D75 | Already decided |
| PB-002 | Keychain on the Mac | `09-platform-macos.md:316, :882` | Settled by D75 | Already decided |
| PB-004 | Python packages on iOS | `09-platform-macos.md:852` | Settled by D76 | Already decided |
| PB-006 | Engine mapping | `05-bots-and-assistant.md:369` | Settled by D44, D46 | Already decided |
| PB-007 | Devices: due fires | `05-bots-and-assistant.md:752, :1278` | Settled by D73, D74 | Already decided |
| PB-008 | Chat context reset | `05-bots-and-assistant.md:30, :382, :387` | Settled by D78 | Already decided |
| PB-009 | Memory as evidence | `05-bots-and-assistant.md:644` | Settled by D78 | Already decided |
| PB-033 | Skills on iPhone and iPad | `05-bots-and-assistant.md:1110` | Settled by D69 | Already decided |
| PB-035 | Permission modes for unattended work | `05-bots-and-assistant.md:1279, :1177` | Settled by D57 | Already decided |
| PB-053 | LaunchAgent: BundleProgram | `09-platform-macos.md:376, :478` | Settled by D58 | Already decided |
| PB-080 | Bot deletion on iPhone and iPad | `05-bots-and-assistant.md:333, :1278` | Settled by D74 | Already decided |
| PB-081 | Triggers: intents on iOS | `05-bots-and-assistant.md:672` | Settled by D79 | Already decided |
| PB-099 | App Review (O13): 4.7 | `09-platform-macos.md:832, :834, :837, :891` | Settled by D67 | Already decided |
| PB-101 | App Review (O13): 2.5.2 | `09-platform-macos.md:829, :830` | Settled by D67 | Already decided |

<a id="table-5"></a>
## Table 5: the experience, design, coding and security (D85)

From `02-experience.md`, `03-design-system.md`, `07-coding.md` and `08-security-and-privacy.md`. 15 rows were already settled by D74–D78; of the other 67, 44 were kept, 20 changed and 3 matched earlier outcomes. The user approved the keeps as a list and chose every change row by row, leaving one to the recommendation.

| ID | Area | Where | Outcome | Chosen by |
|---|---|---|---|---|
| UX-001 | Approvals | `08-security-and-privacy.md:61` | Keep as specified | User's choice |
| UX-006 | Browser across devices | `02-experience.md:1482` | a secure answer travels MLS-encrypted to the runner's browser, which fills it in (watch and takeover are D83) | User's choice |
| UX-013 | Browser egress (iOS) | `08-security-and-privacy.md:377` | keep; S3 also tests WebKit's known proxy bypasses; if it fails, browse on the Mac. | User's choice |
| UX-014 | iSH egress | `08-security-and-privacy.md:383` | Keep as specified | User's choice |
| UX-017 | Resume card | `02-experience.md:459`, `:778`, `:1484` | Keep as specified | User's choice |
| UX-018 | Offline side threads | `02-experience.md:1406` | Keep as specified | User's choice |
| UX-019 | iOS first launch | `02-experience.md:159`, `:1483` | Welcome leads with Pair with your Mac; Set up here sits beside it. | User's choice |
| UX-020 | iOS coding surfaces | `02-experience.md:159`, `:1483`; `07-coding.md:260` | Changes and Files with Accept, comments, Commit (run on Mac); Terminal mirrored read-only. +~5 days [INFERENCE] | User's choice |
| UX-021 | iOS → Mac git | `07-coding.md:260` | typed memoshid calls over D48 links, reusing the Mac's commit path. | User's choice |
| UX-022 | Notifications (iOS) | `02-experience.md:1286` | Keep as specified | User's choice |
| UX-023 | Python (iOS) | `07-coding.md:343` | Keep as specified | User's choice |
| UX-024 | iSH projects | `07-coding.md:195` | Keep as specified | User's choice |
| UX-025 | iSH image | `02-experience.md:1488` | D83 (AC-078): Alpine's base image ships in the app; apk updates each bot's copy under policy | Already decided |
| UX-027 | Release signing | `08-security-and-privacy.md:191` | in the reviewer-gated CI release environment (09 §10.2), never on feed hosts. | User's choice |
| UX-028 | Egress (iOS) | `08-security-and-privacy.md:378` | Keep as specified | User's choice |
| UX-029 | Device links | `08-security-and-privacy.md:385` | Keep as specified | User's choice |
| UX-030 | Skills and MCP | `08-security-and-privacy.md:437` | add a model review of descriptions and scripts at install; it only adds flags. +~2 days [INFERENCE] | User's choice |
| UX-031 | Audit | `08-security-and-privacy.md:454` | D82 (MP-021): each device signs its chain head, peers record it, and every chain is verified | Already decided |
| UX-033 | Privacy | `08-security-and-privacy.md:506` | Keep as specified | User's choice |
| UX-034 | Incident response | `08-security-and-privacy.md:523` | Keep as specified | User's choice |
| UX-035 | Folder grants | `07-coding.md:91` | Keep as specified | User's choice |
| UX-036 | AGENTS.md | `07-coding.md:110` | also load a subtree's AGENTS.md when the bot first reads or edits there. +~1 day [INFERENCE] | User's choice |
| UX-037 | Code search | `07-coding.md:238` | Mac bundles signed rg and fd, run inside the sandbox; iPhone and iPad stay native. +~1 day [INFERENCE] | User's choice |
| UX-039 | Background processes | `07-coding.md:301` | Keep as specified | User's choice |
| UX-069 | Background processes | `07-coding.md:299` | Keep as specified | User's choice |
| UX-040 | Review without git | `07-coding.md:376` | Keep as specified | User's choice |
| UX-041 | Bot commits | `07-coding.md:459` | Keep as specified | User's choice |
| UX-042 | Worktrees in VMs (v1.1) | `07-coding.md:514` | Keep as specified | User's choice |
| UX-043 | External agents (v1.1) | `07-coding.md:736` | Keep as specified | User's choice |
| UX-044 | Secrets in dev servers | `07-coding.md:797` | verify on the corpus in spike C6; secret files must fail stat, not just read. | User's choice |
| UX-045 | Python environments | `07-coding.md:337` | create a project `.venv` with uv on first install; uv's `.venv` ignores itself in git. | User's choice |
| UX-046 | Python supply chain | `07-coding.md:339`; `08-security-and-privacy.md:204` | Keep as specified | User's choice |
| UX-047 | Python installs | `07-coding.md:340` | Keep as specified | User's choice |
| UX-048 | Python (numba) | `07-coding.md:342` | Keep as specified | User's choice |
| UX-049 | Notebook outputs | `02-experience.md:1179`, `:1486` | render HTML outputs in the artifacts' sandboxed web view; Plotly via bundled plotly.js. +~3 days [INFERENCE] | User's choice |
| UX-050 | Notebook co-editing | `02-experience.md:1485` | your edit wins; the bot's concurrent change appears as a proposal on that cell. +~2 days [INFERENCE] | User's choice |
| UX-051 | Notebook review | `07-coding.md:350` | Keep as specified | User's choice |
| UX-052 | Mini app placement | `02-experience.md:1192`, `:1487` | on the Mac a mini app opens as a sheet over its conversation; Open in Window and Full Screen are one click away, and a per-app "always open this way" setting | Left to the recommendation |
| UX-053 | Mini app navigation | `02-experience.md:1193` | D81 (CP-035): a sidebar Apps section, plus Spotlight, Siri and Shortcuts launch | Already decided |
| UX-054 | Live cards | `03-design-system.md:453` | Keep as specified | User's choice |
| UX-055 | Text contrast | `03-design-system.md:133` | Keep as specified | User's choice |
| UX-056 | iPhone performance | `03-design-system.md:920` | Keep as specified | User's choice |
| UX-057 | iPad keyboard | `02-experience.md:151` | Keep as specified | User's choice |
| UX-058 | Keyboard focus | `02-experience.md:1428` | keep F6 and add ⌥⌘` for next pane (⇧ for previous), as Xcode does. | User's choice |
| UX-059 | VoiceOver | `02-experience.md:1437` | Keep as specified | User's choice |
| UX-060 | iSH inspector | `02-experience.md:867` | add a running-process list and Reset image (typed confirmation). +~1 day [INFERENCE] | User's choice |
| UX-061 | Materials | `03-design-system.md:99` | add Kuvo's Frosted/Solid appearance toggle, reusing the Reduce Transparency path. | User's choice |
| UX-062 | Shadows | `03-design-system.md:240` | Keep as specified | User's choice |
| UX-063 | Text reveal | `03-design-system.md:502` | Keep as specified | User's choice |
| UX-064 | Motion | `03-design-system.md:555` | Keep as specified | User's choice |
| UX-065 | Shaders (design pass) | `03-design-system.md:664` | Keep as specified | User's choice |
| UX-066 | Shaders (design pass) | `03-design-system.md:666` | Keep as specified | User's choice |
| UX-067 | Commit messages | `07-coding.md:142` | match recent history's style, whatever it is, unless instructions say otherwise. | User's choice |
| UX-068 | Pi_Swift parity | `07-coding.md:218` | Keep as specified | User's choice |
| UX-070 | Python pins | `07-coding.md:337` | also accept `pylock.toml` (PEP 751), which uv installs (preview). | User's choice |
| UX-071 | Mini app history | `07-coding.md:679` | Keep as specified | User's choice |
| UX-072 | Metrics | `07-coding.md:915` | Keep as specified | User's choice |
| UX-073 | Metrics | `07-coding.md:916` | Keep as specified | User's choice |
| UX-074 | Metrics | `07-coding.md:918` | Keep as specified | User's choice |
| UX-075 | Metrics | `07-coding.md:919` | Keep as specified | User's choice |
| UX-076 | Metrics | `07-coding.md:925` | Keep as specified | User's choice |
| UX-077 | Threat model | `08-security-and-privacy.md:131` | Keep as specified | User's choice |
| UX-078 | GPL separation | `08-security-and-privacy.md:209` | Keep as specified | User's choice |
| UX-079 | Card expiry | `08-security-and-privacy.md:292` | Keep as specified | User's choice |
| UX-080 | Model keys | `08-security-and-privacy.md:352` | Keep as specified | User's choice |
| UX-081 | Update checks | `08-security-and-privacy.md:470` | Keep as specified | User's choice |
| UX-082 | Key compromise | `08-security-and-privacy.md:525` | rotate via a Developer ID-signed DMG carrying the new key; never change both keys. | User's choice |
| UX-002 | Approvals / modes | `02-experience.md:1481` | Settled by D78 | Already decided |
| UX-003 | Kill switch | `08-security-and-privacy.md:253` | Settled by D75 | Already decided |
| UX-004 | Lost devices | `08-security-and-privacy.md:625` | Settled by D75 | Already decided |
| UX-005 | Secrets across devices | `08-security-and-privacy.md:336` | Settled by D75 | Already decided |
| UX-007 | Secrets at rest | `08-security-and-privacy.md:333` | Settled by D75 | Already decided |
| UX-008 | Mac sandbox | `07-coding.md:252` | Settled by D77 | Already decided |
| UX-009 | Mac sandbox fallback | `07-coding.md:259`, `08-security-and-privacy.md:249` | Settled by D77 | Already decided |
| UX-010 | iOS file boundary | `08-security-and-privacy.md:249` | Settled by D76 | Already decided |
| UX-011 | Python isolation (iOS) | `08-security-and-privacy.md:205`, `:379` | Settled by D76 | Already decided |
| UX-012 | Python isolation (iOS) | `08-security-and-privacy.md:631` | Settled by D76 | Already decided |
| UX-015 | Undo | `07-coding.md:401` | Settled by D77 | Already decided |
| UX-016 | Commit hooks | `07-coding.md:456` | Settled by D77 | Already decided |
| UX-026 | Secrets (iOS) | `08-security-and-privacy.md:107`, `:341` | Settled by D76 | Already decided |
| UX-032 | Deletion | `08-security-and-privacy.md:490` | Settled by D74 | Already decided |
| UX-038 | Path guard | `07-coding.md:263` | Settled by D77 | Already decided |

<a id="table-6"></a>
## Table 6: the roadmap, risks, Phase 0 and product (D86)

From `10-roadmap.md`, `decisions.md`, `risks.md`, `phase-0.md`, `feature-catalog.md`, `01-product.md`, `MASTER_PLAN.md`, `NEXT_VERSION.md` and `HANDOFF.md`. 11 rows were already settled by D67–D79; of the other 72, 43 were kept, 26 changed and 3 matched earlier outcomes. The user approved the keeps as a list and chose every change row by row.

| ID | Area | Where | Outcome | Chosen by |
|---|---|---|---|---|
| PL-002 | Python on iPhone/iPad | phase-0.md:360, 365; risks.md:130 | Keep as specified | User's choice |
| PL-062 | Python on iPhone/iPad | phase-0.md:355 | Keep as specified | User's choice |
| PL-014 | Swift engine | 10-roadmap.md:211; feature-catalog.md:190 | Keep as specified | User's choice |
| PL-063 | Swift engine | risks.md:92 | signal at more than 1 in 10 failing after one fix round; keep 15 MB | User's choice |
| PL-010 | Identifiers | decisions.md:875 | separate IDs now: the Mac app is com.mehmetcanbudak.memoshi.mac, iOS keeps the base | User's choice |
| PL-011 | Python on the Mac | decisions.md:890; feature-catalog.md:551 | D83 (AC-065): one pinned, hash-checked CPython shared read-only; each bot keeps its own packages | Already decided |
| PL-012 | Licensing | decisions.md:896 | Keep as specified | User's choice |
| PL-015 | iSH computer | decisions.md:993 | D81 (CP-046): the host-side adapter by default; the probe confirms | Already decided |
| PL-016 | iSH computer | risks.md:102 | Keep as specified | User's choice |
| PL-017 | iSH computer | risks.md:102; HANDOFF.md:248 | Keep as specified | User's choice |
| PL-018 | iSH fallback | decisions.md:924 | Keep as specified | User's choice |
| PL-019 | Hosted relay | 10-roadmap.md:246, 267, 304; risks.md:126; decisions.md:1058; HANDOFF.md:236 | free and capped for the user and invited testers; set caps before testers join | User's choice |
| PL-073 | Hosted relay | risks.md:126 | Keep as specified | User's choice |
| PL-020 | Relay privacy | risks.md:113 | relay logs hold metadata only and are deleted after 7 days | User's choice |
| PL-021 | iCloud link | risks.md:127 | Keep as specified | User's choice |
| PL-022 | Devices | phase-0.md:245, 246 | replica lag p95 < 250 ms direct, < 1 s via relay; hand-over unchanged | User's choice |
| PL-023 | Approvals | phase-0.md:247 | keep iCloud's 30 s; add relay-path approvals at p95 < 5 s | User's choice |
| PL-024 | Browser on iOS | phase-0.md:267 | Keep as specified | User's choice |
| PL-025 | Engine performance | phase-0.md:217, 218, 220, 341 | Keep as specified | User's choice |
| PL-026 | Webhooks | risks.md:111 | Keep as specified | User's choice |
| PL-027 | GPL licensing | risks.md:148 | lawyer before a public release; self-check ish-arm64's App Store exception before friends install | User's choice |
| PL-028 | Clean room | HANDOFF.md:195 | drop Track A (no personal Kuvo fork); using Kuvo's released app stays fine | User's choice |
| PL-029 | Dogfood cost | 10-roadmap.md:443 | $300 a month until M2.1, then a larger cap the user sets for coding inside Memoshi | User's choice |
| PL-030 | Alpha | 10-roadmap.md:443; risks.md:272 | Keep as specified | User's choice |
| PL-031 | Cut order | 10-roadmap.md:384 | protect PY-04 like CH-25; group 1 slips only AP-03 and AP-04 | User's choice |
| PL-032 | Cut order | 10-roadmap.md:394 | Keep as specified | User's choice |
| PL-033 | Cut order | 10-roadmap.md:396 | Keep as specified | User's choice |
| PL-034 | Cut order | 10-roadmap.md:398, 401, 403 | Keep as specified | User's choice |
| PL-035 | Coding | 01-product.md:469 | Keep as specified | User's choice |
| PL-036 | Safety gate | 10-roadmap.md:160 | ≥ 100 cases covering every injection source × mode × T3–T5 tier × origin +~1 day [INFERENCE] | User's choice |
| PL-037 | Coding UX | 10-roadmap.md:202 | also open a 10,000-line diff in < 500 ms with lazy rows | User's choice |
| PL-038 | Dogfood | 10-roadmap.md:205, 432 | Keep as specified | User's choice |
| PL-039 | Memory | feature-catalog.md:222 | Keep as specified | User's choice |
| PL-040 | Budgets | feature-catalog.md:273; 01-product.md:550 | show a range from past runs; 80% of actual costs fall inside it | User's choice |
| PL-041 | Onboarding | feature-catalog.md:474 | Keep as specified | User's choice |
| PL-042 | Pricing | 01-product.md:592 | Keep as specified | User's choice |
| PL-057 | Pricing | 01-product.md:612 | re-check each storefront's payment rules at O13; keep the Mac payment-provider note | User's choice |
| PL-043 | Bot computers (v1.1) | decisions.md:1051; MASTER_PLAN.md:246 | Keep as specified | User's choice |
| PL-079 | Bot computers (v1.1) | MASTER_PLAN.md:441; 01-product.md:532; feature-catalog.md:346 | Keep as specified | User's choice |
| PL-044 | Apple tools (proposal) | NEXT_VERSION.md:15, 153-154, 161-184, 439-445 | adopt; Mac uses the WeatherKit framework if S5 confirms; AlarmKit on iPad too +~2 days [INFERENCE] | User's choice |
| PL-045 | QuickAsk (proposal) | NEXT_VERSION.md:15, 186-190 | adopt QuickAsk fully in v1, live typed drafts included, with both rules (no keystrokes to a remote model without disclosure; Undo is a new authorized act) | User's own choice |
| PL-046 | bot.md import (proposal) | NEXT_VERSION.md:15, 333 | follow D26 and EXP-01: grants and routines import as proposals; memory export opt-in | User's choice |
| PL-047 | Computers (proposal) | NEXT_VERSION.md:15, 351-368 | Keep as specified | User's choice |
| PL-048 | Takeover (proposal) | NEXT_VERSION.md:15, 370 | Keep as specified | User's choice |
| PL-049 | Memory (proposal) | NEXT_VERSION.md:15, 385-394 | Keep as specified | User's choice |
| PL-080 | Memory (proposal) | NEXT_VERSION.md:15, 383, 396-398 | Keep as specified | User's choice |
| PL-050 | Routines (proposal) | NEXT_VERSION.md:15, 412 | Keep as specified | User's choice |
| PL-051 | Verification (proposal) | NEXT_VERSION.md:15, 506-527 | Keep as specified | User's choice |
| PL-052 | OS floor | decisions.md:402 | D84 (PB-036): the trigger is dropped; the current-and-previous policy sets the floor | Already decided |
| PL-053 | Routines | decisions.md:710 | Keep as specified | User's choice |
| PL-054 | Routines | risks.md:125 | Keep as specified | User's choice |
| PL-056 | Developer account | decisions.md:884 | Keep as specified | User's choice |
| PL-058 | Platform | 10-roadmap.md:69; risks.md:120 | Keep as specified | User's choice |
| PL-059 | Costs | 10-roadmap.md:104 | self-hosted Apple-silicon Mac mini runner; the reference box keeps perf CI | User's choice |
| PL-060 | Operations (v2) | 10-roadmap.md:315 | Keep as specified | User's choice |
| PL-061 | Build tooling | phase-0.md:96 | Keep as specified | User's choice |
| PL-064 | Generated cards | feature-catalog.md:185; 10-roadmap.md:207 | Keep as specified | User's choice |
| PL-066 | Generated cards | feature-catalog.md:191 | reject zero tabs with a fixable error; draw an empty tab as an empty state | User's choice |
| PL-065 | Mini apps | feature-catalog.md:188 | Keep as specified | User's choice |
| PL-067 | Triggers | feature-catalog.md:244 | Keep as specified | User's choice |
| PL-068 | Voice (v2) | feature-catalog.md:596 | p50 under 500 ms, p95 under 1 s, on the baseline Mac | User's choice |
| PL-069 | Distribution | feature-catalog.md:511; risks.md:87 | upload a TestFlight build nightly when main changed; keep the two-week alarm | User's choice |
| PL-070 | Signing | feature-catalog.md:512; risks.md:129 | Keep as specified | User's choice |
| PL-071 | Research | 01-product.md:512; risks.md:152, 153 | n ≥ 5 per round; fewer than 5 sessions counts as "too few" | User's choice |
| PL-072 | Telemetry | risks.md:153 | Keep as specified | User's choice |
| PL-074 | Permission modes | risks.md:112 | Keep as specified | User's choice |
| PL-075 | Schedule | risks.md:77, 78, 84, 89 | keep the rest; signal when the port trails upstream main by 4+ weeks | User's choice |
| PL-076 | Product metrics | 01-product.md:539 | keep the metrics local logs can measure; drop NPS until a public release | User's choice |
| PL-077 | Users | 01-product.md:94, 109 | Keep as specified | User's choice |
| PL-078 | Strategy | 01-product.md:625, 636 | Keep as specified | User's choice |
| PL-081 | Views (proposal) | NEXT_VERSION.md:15, 414-426 | adopt the visual task and artifact views in v1; the Group explanations ship with Groups (v1.1) | User's own choice |
| PL-083 | Collaboration (proposal) | NEXT_VERSION.md:15, 335-349 | shared rooms move to v1.1 with Groups; 'routing never grants permission' is a rule from v1 | User's own choice |
| PL-001 | Python on iPhone/iPad | 10-roadmap.md:124, 508; decisions.md:891; phase-0.md:34, 374; feature-catalog.md:553 | Settled by D79 | Already decided |
| PL-003 | This Mac sandbox | phase-0.md:311; risks.md:100 | Settled by D77 | Already decided |
| PL-004 | Swift engine | decisions.md:904; feature-catalog.md:187 | Settled by D71 and D78 | Already decided |
| PL-013 | Swift engine | decisions.md:976; feature-catalog.md:190; risks.md:92 | Settled by D72 | Already decided |
| PL-005 | Apple-data cards (proposal) | NEXT_VERSION.md:15, 143-244 | Settled by D79 | Already decided |
| PL-006 | Recovery and policy (proposal) | NEXT_VERSION.md:15, 300-305 | Settled by D79 | Already decided |
| PL-007 | Protocol | decisions.md:652 | Settled by D78 | Already decided |
| PL-008 | Protocol | 10-roadmap.md:84 | Settled by D74 | Already decided |
| PL-009 | Storage on iOS | phase-0.md:76 | Settled by D79 | Already decided |
| PL-055 | App Review | decisions.md:789, 906 | Settled by D67 | Already decided |
| PL-082 | Delivery (proposal) | NEXT_VERSION.md:15, 490-504 | Settled by D70 | Already decided |
