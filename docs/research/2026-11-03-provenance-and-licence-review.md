# Provenance and licence review: Draft 3 port audit, dependencies, Kuvo and release blockers

**Status:** Review record · 2026-11-03 · P0-17 port audit and P0-22 licence/provenance/redistribution review. It records terms and observations, not legal advice, a legal conclusion or clearance for public or commercial redistribution ([D91](../plan/decisions.md#d91)).
**Owns:** Where every class of material in this repository came from, under which recorded terms, what was re-expressed or copied, and the open public/commercial redistribution blockers, as of `62866f6` plus the uncommitted Phase 0 work observed on 2026-11-03.
**Depends on:** [D33](../plan/decisions.md#d33) · [D36](../plan/decisions.md#d36) · [D55](../plan/decisions.md#d55) · [D65](../plan/decisions.md#d65) · [D69](../plan/decisions.md#d69) · [D91](../plan/decisions.md#d91) · [R16](../plan/risks.md#r16) · [R37](../plan/risks.md#r37) · [R54](../plan/risks.md#r54) · [phase-0 §7](../plan/phase-0.md#port-list) · [`NOTICE`](../../NOTICE)

Research is evidence, not decisions ([index](README.md)). Labels: `[INFERENCE]` is reasoning from the cited observations; everything else cites a file or a command whose output is kept in the [evidence directory](../../../evidence/2026-11-03-memoshi-provenance/).

## 1. Result

- **P0-17 (port audit).** Every Draft 3 item now has a verdict in [phase-0 §7](../plan/phase-0.md#port-list). No item was ported directly: the protocol, transport, store, policy, granted-folder guard, client and utilities were re-implemented in Swift; the artifact preview, the shell-command table, the git helpers and the harnesses are deferred; the reference-only code and the drop list are dropped. Six files carry headers naming the original Draft 3 paths ([§3.2](#32-what-memoshi-re-expressed-and-what-it-copied)). The drop list was not copied ([§4](#4-drop-list-verification-p0-17)).
- **Licence scan.** `scripts/scan-licenses.sh` exited 0 with `ok: 31 resolved dependencies carry accepted licenses`: 31 occurrences of 9 distinct packages across five packages; `MemoshiApp` resolves none ([§6](#6-resolved-third-party-dependencies)).
- **Draft 3.** The reference revision `ce39f8a` contains no licence file; the prototype's current, untracked `LICENSE` reserves all rights and needs "a separate decision" for redistribution ([§3](#3-draft-3-prototype)).
- **Pi.** Pi_Swift `892585f` and upstream Pi `22dc6c26` each carry one MIT `LICENSE` and no `NOTICE` ([§5](#5-pi_swift-and-upstream-pi)).
- **Kuvo.** No Kuvo code, binary or asset is in the repository. Kuvo text appears as attributed quotations in research and plan documents, plus one unattributed product phrase in the plan ([§7](#7-kuvo-code)).
- **Apple material, captures, GPL.** No skill payload, image, video or other binary file is tracked or appears in the repository's history ([supplementary-checks.txt](../../../evidence/2026-11-03-memoshi-provenance/supplementary-checks.txt), scan H), and no Apple documentation prose was found in the current tree (scan G); iSH/Open Minis is not present ([§8](#8-apple-documentation-and-skill-material)–[§10](#10-the-gpl-ish-and-open-minis-boundary)).
- **NOTICE.** Three factual corrections were made ([§11](#11-notice-corrections-made-by-this-review)). Eight redistribution blockers remain open, with owners ([§12](#12-open-publiccommercial-redistribution-blockers)).

## 2. Inputs, commands and method

| Input | Revision and state | Access |
|---|---|---|
| This repository | `62866f6` (= `origin/main`), 572 tracked files. The final scan (2026-11-03T08:30:58Z) read the working tree, including 26 untracked, non-ignored files and uncommitted edits to tracked files from parallel Phase 0 work, and this record | Read; this record, the §7 table, the research index and `NOTICE` edited |
| Draft 3 prototype, `~/Documents/Memoshi-Plan` | HEAD = reference revision `ce39f8a7ca324ce1c2473518593b1fb4f96ebe4b` (2026-10-22), 84 commits, no remote; working tree with 96 modified and 165 untracked entries; audit tree `3570e71` | Read-only `git show`/`ls-tree`/`status` and file reads ([licence-facts.txt](../../../evidence/2026-11-03-memoshi-provenance/licence-facts.txt)) |
| Pi_Swift, `../Pi_Swift` | Candidate `892585fc8d8be3093b58c34aacffcd4e68c3a8d9` | `LICENSE`/`NOTICE` only |
| Upstream Pi, `../pi-upstream` (origin `earendil-works/pi`) | `22dc6c26f3c530e11b8cc40443ecdce2b3c84116` | `LICENSE` and `packages/durable/test/codemode-bench.ts` |
| Kuvo Code source, `~/Projects/Cognitio` | A local clone whose only remote, `upstream`, is `serhatandic/kuvo-code`; `refs/remotes/upstream/main` = `230827f9` (2026-10-27) and `ddd492b`, the revision of the [frontend-reuse assessment](2026-10-23-kuvo-frontend-reuse.md) | Read-only git objects |
| Kuvo apps | `/Applications/Kuvo Code.app`, `/Applications/Kuvo.app` | SHA-256 of every file |
| Apple/Xcode skill export | `~/.agents/skills/apple-xcode` (112 text files; [skills catalogue](../skills.md#apple-and-xcode-material)) | Read |

**Commands.**

- `bash scripts/scan-licenses.sh`: exit 0 in 9.2 s ([output](../../../evidence/2026-11-03-memoshi-provenance/scan-licenses.out)); a rerun at 08:28:58Z, with parallel work's uncommitted change to `Packages/MemoshiDaemon/Package.swift` present, exited 0 with identical output ([rerun](../../../evidence/2026-11-03-memoshi-provenance/scan-licenses-rerun.out)).
- `python3 provenance-scan.py <dir>` ([script](../../../evidence/2026-11-03-memoshi-provenance/provenance-scan.py), [report](../../../evidence/2026-11-03-memoshi-provenance/provenance-scan.txt), [JSON](../../../evidence/2026-11-03-memoshi-provenance/provenance-scan.json)), final run 2026-11-03T08:30:58Z. Sections A–H of the report are cited below as "scan A" and so on; counts are given for files git tracks and, separately, for untracked files.
- The git, `jq`, `shasum` and `grep` commands with their outputs are in [licence-facts.txt](../../../evidence/2026-11-03-memoshi-provenance/licence-facts.txt), which also lists the introducing commit of every source file (`git log --diff-filter=A --format=%h -- <path>`).
- Comparisons of `NOTICE` blocks with their sources, the `BrowserSession.swift` line comparison, the quotation count, the `swift-json-schema` licence, the skill-payload history check and the dropped-file SQL check are in [supplementary-checks.txt](../../../evidence/2026-11-03-memoshi-provenance/supplementary-checks.txt).

**Similarity method.** Lines are whitespace-normalized. The scan compares single lines of at least 30 characters, windows of three consecutive non-trivial lines and, for prose, sequences of eight words. A match that also occurs in the third-party SwiftPM checkouts under `Packages/{MemoshiCore,MemoshiProtocol}/.build/checkouts` (Pi_Swift excluded) counts as generic; that corpus contains standard licence texts and ordinary Swift/plist idioms. Remaining matches were reviewed by hand. A text scan finds copied text, not translation or paraphrase: TypeScript re-expressed in Swift is detected by headers and review, not by the scan. Classifying a remaining match as an idiom is `[INFERENCE]`.

## 3. Draft 3 prototype

### 3.1 Licence state

- **At `ce39f8a`:** `git ls-tree` finds no `LICENSE`, `COPYING` or `NOTICE` among its 179 files. Its three `package.json` files are `"private": true` with no `license` field. Its plan records decision D11, "Open core: Apache-2.0 core; proprietary team/enterprise", as a plan decision (`MASTER_PLAN.md:411`, `README.md:84`); no file grants a licence ([licence-facts.txt](../../../evidence/2026-11-03-memoshi-provenance/licence-facts.txt)).
- **Today:** the working tree has an untracked `LICENSE` (modified 2026-10-23 12:45, SHA-256 `d053805e…2edcb32`): "Copyright (c) 2026 Mehmet Can Budak. All rights reserved. … not released under an open-source license. You may build and run it on your own Mac. Redistribution, a public app store listing, and a hosted service need a separate decision." `NOTICE` reproduces it byte for byte ([supplementary-checks.txt](../../../evidence/2026-11-03-memoshi-provenance/supplementary-checks.txt)).
- The named holder is the same person as `NOTICE:2` (`Copyright 2026 Mehmet Can Budak`). `[INFERENCE]` The "separate decision" is therefore the owner's own.

### 3.2 What Memoshi re-expressed and what it copied

Six files re-express Draft 3 behaviour and carry headers naming the original paths; all were introduced in [`8a4abaf`](https://github.com/mehmetcanbudak/Memoshi/commit/8a4abaf0e7136c82b69e31dab3960105054c19d6):

| Memoshi file | Header | Draft 3 source at `ce39f8a` | Literal carry-over found (scan A, C, D) |
|---|---|---|---|
| [`Store/Migrations.swift`](../../Packages/MemoshiCore/Sources/Store/Migrations.swift) | lines 4–5, path and revision | `sidecar/src/store/db.ts`, `store/migrations.ts` | The `INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)` statement |
| [`Store/Migrations/001_event_log.sql`](../../Packages/MemoshiCore/Sources/Store/Migrations/001_event_log.sql) | line 1, paths only | same | The `schema_migrations (version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)` table, the only identical normalized SQL statement. Shared object names are `approvals`, `events`, `schema_migrations` and `tasks`; columns and constraints differ |
| [`Store/Identifiers.swift`](../../Packages/MemoshiCore/Sources/Store/Identifiers.swift) | line 5 | `sidecar/src/ids.ts` | None; ULIDs replace UUID fragments |
| [`Store/EventBus.swift`](../../Packages/MemoshiCore/Sources/Store/EventBus.swift) | lines 12–13 | `sidecar/src/events/bus.ts` | None |
| [`Store/Schedule.swift`](../../Packages/MemoshiCore/Sources/Store/Schedule.swift) | lines 9–10 | `sidecar/src/routines/schedule.ts`, `routines/cron.ts` | The month-abbreviation list (5 eight-word sequences) |
| [`Store/StoreLogger.swift`](../../Packages/MemoshiCore/Sources/Store/StoreLogger.swift) | line 20 | `sidecar/src/log.ts` | The redaction key list and value patterns (12 eight-word sequences) |

Everything else in Memoshi's code shares no non-generic three-line window with Draft 3 at `ce39f8a` or its current working tree except boilerplate (scan A: 131 windows in 14 tracked files, none in untracked files). Of these, 90 are in the generated `protocol/protocol.schema.json` and match JSON Schema structure in the prototype's current, post-reference `packages/protocol/contract.json`; `scripts/protocol-schema.sh` derives the Memoshi file from Swift types. The rest are XcodeGen settings with the same target name (`apps/mac/project.yml`, 8), `Info.plist` keys (5–7 per plist), the CI header (3), HTML boilerplate in `BrowserAutomationScript.swift` (3, one of them also in `demo/seed.ts`'s sample page), the approval status cases `pending`/`allowed`/`denied`/`expired` (2), and single AppKit/SwiftUI/JSON-enum idioms. Single-line matches (scan A: 267 lines in 81 tracked files, 15 in 5 untracked files) are SwiftUI modifiers, Foundation/WebKit calls, `CodingKeys` declarations and plist placeholders, plus the declared SQL line above `[INFERENCE: idioms]`.

Plan and specification text in `docs/` is adapted from the prototype's superseded plan pack where it says so, for example [risks.md](../plan/risks.md) ("Adapted from Draft 3 `docs/05-decisions-risks.md`"), the [decision mapping](../plan/decisions.md#mapping-from-draft-3) and the `draft-3-tokens` source (licence "Own") in [`design-tokens.json`](../specs/design-tokens.json). Scan D counts the shared eight-word sequences, for example 54 in `decisions.md`, 25 in `MASTER_PLAN.md`, 18 in `object-model.md` and 16 in `design-tokens.json`.

### 3.3 Redistribution limits

The recorded terms allow building and running the prototype on the owner's own Mac, and leave redistribution, a public store listing and a hosted service to a separate decision. Memoshi's `NOTICE` records the reference, reproduces those terms and states that the record is "not clearance for public or commercial redistribution". `[INFERENCE]` A public or commercial release that includes the six files above or the adapted plan/token text first needs the owner's recorded licence decision for that material ([B1](#12-open-publiccommercial-redistribution-blockers)).

## 4. Drop-list verification (P0-17)

Scan B took each dropped file at `3570e71`, at `ce39f8a` and in the prototype's working tree, extracted the compound identifiers that occur in no other Draft 3 file and every string literal of at least 12 characters, and searched every tracked and untracked Memoshi text file. Scan A compared all Draft 3 code line by line and window by window.

| Dropped file | Fingerprints | Matches in Memoshi |
|---|---|---|
| `sidecar/src/tools/memoshi-tools.ts` (host-direct tools) | 25 unique identifiers, 99 literals | Code: the JSON Schema keyword `maxLength` (protocol limits) and the Homebrew prefix `/opt/homebrew/bin` (`scripts/ci.sh`, a `PATH` entry). Docs: `enrichedEnv` where [08-security-and-privacy.md](../plan/08-security-and-privacy.md) and [policy.md §17](../specs/policy.md#17-changes-from-draft-3) describe the defect being fixed, and Node module names in research |
| `sidecar/src/runtime/fake.ts` (fake runtime) | 4 unique identifiers, 11 literals | None anywhere |
| `sidecar/src/demo/seed.ts` (demo seed) | 9 unique identifiers, 30 literals | Code: none. Docs: `src/greet.js` where the plan and audit describe the overwrite defect, and file or module names |

No three-line window of code from these files occurs in Memoshi code, apart from the HTML boilerplate noted in §3.2. None of the three files contains an SQL statement in any of the three versions, so there was no SQL to search for ([supplementary-checks.txt](../../../evidence/2026-11-03-memoshi-provenance/supplementary-checks.txt)). Production tools stay disabled; deterministic runtime tests script only an external loopback HTTP provider ([`RuntimeTestProvider.swift`](../../Packages/MemoshiCore/Tests/MemoshiRuntimeTests/RuntimeTestProvider.swift), introduced in [`8a4abaf`](https://github.com/mehmetcanbudak/Memoshi/commit/8a4abaf0e7136c82b69e31dab3960105054c19d6)) instead of a fake runtime.

## 5. Pi_Swift and upstream Pi

- **Pi_Swift `892585f`.** One root `LICENSE`, MIT, "Copyright (c) 2025 Mario Zechner" and "Copyright (c) 2026 Pi_Swift contributors" (SHA-256 `bc50d0cd…6b132c6e`); no `NOTICE`. `MemoshiCore` pins it by exact revision from the sibling repository ([`Package.swift`](../../Packages/MemoshiCore/Package.swift) lines 13–18), and `MemoshiRuntime` links `PiDurable`, `PiAI`, `PiCore` and `Chord`. `NOTICE` reproduces the licence byte for byte and records that the candidate is unpublished, unmodified and not a qualified slice.
- **Upstream Pi `22dc6c26`.** One root `LICENSE`, MIT, "Copyright (c) 2025 Mario Zechner" (SHA-256 `0457f5bc…af13c48`); no other licence or notice file in the tree. Memoshi links no upstream Pi code.
- **Research fixture.** [`codemode-workload-bench.ts`](spikes/fixtures/CodeModeWorkload/22dc6c26f3c5/harness/codemode-workload-bench.ts) is a Node harness designed to be copied into upstream's `packages/durable/test/`; no Memoshi product builds it. It shares 20 lines of at least 30 characters (imports, Pi API set-up calls and timing/clean-up statements) and 6 three-line windows with upstream's 93-line `codemode-bench.ts` (scan F). Its [`provenance.json`](spikes/fixtures/CodeModeWorkload/22dc6c26f3c5/provenance.json) lists that file as read, and the harness carries no licence line ([B6](#12-open-publiccommercial-redistribution-blockers)).
- **Not checked here:** components vendored inside Pi_Swift, such as the QuickJS WebAssembly guest named in that `provenance.json`. `NOTICE` says only that "The guest's upstream licence resources remain unmodified" ([B4](#12-open-publiccommercial-redistribution-blockers)).

## 6. Resolved third-party dependencies

`bash scripts/scan-licenses.sh` resolved each package under `Packages/` and classified the licence files at each checkout's root. Result: exit 0, `ok: 31 resolved dependencies carry accepted licenses` ([output](../../../evidence/2026-11-03-memoshi-provenance/scan-licenses.out)). Versions and revisions are from the five committed `Package.resolved` files; `apps/mac/project.yml` lists only local packages, and the generated, ignored Xcode `Package.resolved` pins the same nine.

| Package | Version, revision | Resolved by (occurrences) | Licence file → scan class | Recorded terms | Use per manifests and `NOTICE` |
|---|---|---|---|---|---|
| `pi_swift` (local SCM) | `892585fc` | Client, Core, Daemon (3) | `LICENSE` → MIT | MIT, reproduced in `NOTICE` | `MemoshiRuntime` |
| `swift-argument-parser` | 1.8.2, `6a52f325` | Client, Core, Daemon (3) | `LICENSE.txt` → Apache-2.0 | Apache-2.0 with the Runtime Library Exception (RLE), in `NOTICE` | Pi_Swift graph |
| `swift-atomics` | 1.3.1, `0442cb5a` | Client, Core, Daemon, IPC (4) | `LICENSE.txt` → Apache-2.0 | Apache-2.0 with RLE, in `NOTICE` | SwiftNIO graph |
| `swift-collections` | 1.7.4, `844289ac` | Client, Core, Daemon, IPC, Protocol (5) | `LICENSE.txt` → Apache-2.0 | Apache-2.0 with RLE, in `NOTICE` | SwiftNIO graph (`DequeModule`); also via `swift-json-schema` |
| `swift-nio` | 2.104.0, `6db9d9ab` | Client, Core, Daemon, IPC (4) | `LICENSE.txt` → Apache-2.0 | Apache-2.0 without RLE; `NOTICE.txt` and the MIT/BSD-3 component terms reproduced in `NOTICE` | `MemoshiTransport`; test-only in `MemoshiRuntimeTests` |
| `swift-syntax` | 604.0.0, `050f1a34` | Client, Core, Daemon, Protocol (4) | `LICENSE.txt` → Apache-2.0 | Apache-2.0 with RLE, in `NOTICE` | Pi_Swift graph; macros of `swift-json-schema` |
| `swift-system` | 1.8.1, `869129b7` | Client, Core, Daemon, IPC (4) | `LICENSE.txt` → Apache-2.0 | Apache-2.0 with RLE, in `NOTICE` | SwiftNIO graph |
| `wasmkit` | 0.4.2, `a7455cb8` | Client, Core, Daemon (3) | `LICENSE` → MIT | MIT and `NOTICE.txt`, reproduced in `NOTICE` | Pi_Swift graph (`PiCodeMode`) |
| `swift-json-schema` | 0.14.2, `121b469b` | Protocol (1) | `LICENSE` → MIT, "Copyright (c) 2024 Austin Evans" | Added to `NOTICE` by this review | `MemoshiProtocolTests` only ([`Package.swift`](../../Packages/MemoshiProtocol/Package.swift) lines 13–14, 26–32) |

The scan's classifier reports the RLE variants as "Apache-2.0"; a direct comparison found the exception text of `NOTICE` inside the `LICENSE.txt` of all five RLE packages and absent from SwiftNIO's. Every block that `NOTICE` reproduces (Pi_Swift `LICENSE`, WasmKit `LICENSE` and `NOTICE.txt`, SwiftNIO `NOTICE.txt`, `CNIOLLHTTP/LICENSE`, the prototype `LICENSE`) is byte-identical to its source ([supplementary-checks.txt](../../../evidence/2026-11-03-memoshi-provenance/supplementary-checks.txt)). SQLite is the SDK's system library (`CSQLite/module.modulemap`: `link "sqlite3"`), not a vendored copy.

Limits, as [R16](../plan/risks.md#r16) states: the scan reads root licence files only and does not prove vendored-source provenance, component licences inside a checkout, or which products a bundle links.

## 7. Kuvo Code

**Search method.** (1) Git blob identity between this repository's `HEAD` and Kuvo's trees at `230827f9` (1,508 files) and `ddd492b` (1,175 files). (2) SHA-256 of all 136 files in the two installed Kuvo apps against all tracked files. (3) Three-line windows and eight-word sequences of every Memoshi text file, tracked and untracked, against Kuvo's code, documentation, `LICENSE` and `NOTICE` at both revisions (scan E). (4) `git grep -i -E 'kuvo|serhatandic|opencode'` outside `docs/` and `NOTICE`.

**Results.**

- **Code and assets:** 0 identical blobs; 0 identical app-bundle files; the string search finds only process text in `README.md` and `.github/pull_request_template.md`. The non-generic three-line windows in code (29 in 20 tracked files, 3 in 3 untracked files) were reviewed: imports, `catch`/`return` blocks, a `JSONValue` `Codable` ladder that differs in its cases (`integer`/`double` versus Kuvo's `number`), plist closers, `Process` null-device set-up and `JSONEncoder` options `[INFERENCE: language/API idioms]`. Eight-word code matches (511 in 92 tracked files, 28 in 9 untracked files) are of the same kind. The one file named like a Kuvo file, `apps/mac/Memoshi/BrowserSession.swift`, shares 16 normalized lines of at least 20 characters with Kuvo's `BrowserSession.swift`, all WebKit properties or calls such as `canGoBack`, `WKWebViewConfiguration()` and `stopLoading()` ([supplementary-checks.txt](../../../evidence/2026-11-03-memoshi-provenance/supplementary-checks.txt)); its other shared sequences are `WKUIDelegate` method signatures.
- **Text:** attributed quotations of Kuvo's public `README.md`, `CHANGELOG.md`, `LICENSE` and contributor agreement, in [kuvo-code.md](agentic-workspace-landscape/projects/kuvo-code.md) (134 sequences), [02-experience.md](../plan/02-experience.md) (9), [03-design-system.md](../plan/03-design-system.md) (8), [08-security-and-privacy.md](../plan/08-security-and-privacy.md) (8), [decisions.md](../plan/decisions.md) (6, PolyForm clauses), [HANDOFF.md](../HANDOFF.md) and [platform-building-blocks.md](agentic-workspace-landscape/landscape/platform-building-blocks.md) (1 each); this record quotes the job phrase and Kuvo's Required Notice line below (7). [07-coding.md](../plan/07-coding.md) shares two Codex app-server method names that Kuvo's agents also use.
- **One unattributed product phrase, since reworded:** [05-bots-and-assistant.md](../plan/05-bots-and-assistant.md) lines 73 and 297 defined a bot's job as "what to watch, what to make, what never to do without asking". The same words are Kuvo UI and tool text (`KuvoCode/Views/BotEditor.swift:668`, `KuvoCode/Stores/BrowserToolServer.swift:229,231` at `230827f9`), first committed in Kuvo `4f9eca09` (2026-10-15) and in Memoshi's initial commit `68c79ae` (2026-10-22). `[INFERENCE]` The plan took the phrase from Kuvo. No Memoshi code contained it. On 2026-11-03 both lines were rewritten in original wording (responsibilities, what the bot produces, and the limits it checks with the user first); a repository-wide search then found the phrase only in this record.
- **Values:** [`design-tokens.json`](../specs/design-tokens.json) lists `kuvo-docs` and `draft-3-tokens` sources. Draft 3's Kuvo-audit values (rows and composer padding, for example) are numbers of unknown method and remain provisional until P0-19 names a revision or runtime observation.

**D91 terms.** Kuvo is PolyForm Noncommercial 1.0.0 (`LICENSE` SHA-256 `c0ea4a89…`, identical at both revisions) with `NOTICE` "Required Notice: Copyright 2026 Serhat Andıç. Commercial rights reserved." Because nothing was imported, no PolyForm terms or Required Notice attach to Memoshi code today. A future import must record revision, paths and changes and retain the terms and the Required Notice line; it does not become Apache-2.0 ([D91](../plan/decisions.md#d91), [`NOTICE`](../../NOTICE)).

## 8. Apple documentation and skill material

`git ls-files` finds no skill directories or `SKILL.md` payloads. The [skills catalogue](../skills.md) links and routes; it states that Apple documentation in the Xcode export has no assumed redistribution rights and that the `SI` pack's current licence is PolyForm Perimeter 1.0.0 and is not imported ([§Apple and Xcode material](../skills.md#apple-and-xcode-material), [§Conditional framework reference catalogue](../skills.md#conditional-framework-reference-catalogue)). Against the local export (112 text files), scan G finds eight-word sequences only in code (35 in 24 tracked files, 1 in 1 untracked file), all SwiftUI/AppKit idioms, and none in documentation. `design-tokens.json` cites the Human Interface Guidelines as guidance (`apple-hig`, licence "Apple documentation"); it does not reproduce their text.

## 9. Design references and captures

No image, video, PDF, font, archive, asset catalog or other binary file is tracked, untracked, or present in any of the 24 commits' history (scan H; `git log --all --numstat` reports no binary change). User-supplied Viticci references are cited by path outside the repository (`Downloads/viticci/…` in the `design-tokens.json` palette `$source`). [D91](../plan/decisions.md#d91) grants no right to third-party art; branding stays original.

Third-party design values are recorded where adopted: Aiden Agent 0.36.1 (MIT) is the stated source of the syntax colours, elevation tokens and the Markdown typography scale (`design-tokens.json` `$source` entries and `$meta.sources` `aiden-0.36.1`/`aiden-0.58.0`); the Markdown scale is generated into the shipped [`GeneratedTokens.swift`](../../Packages/MemoshiApp/Sources/DesignSystem/GeneratedTokens.swift). `NOTICE` does not carry Aiden's MIT notice ([B6](#12-open-publiccommercial-redistribution-blockers)).

## 10. The GPL iSH and Open Minis boundary

**Current state:** not linked. `Packages/ISH` does not exist; no manifest, project or script refers to `ish-arm64` or Open Minis except the scan's rule (`scripts/scan-licenses.sh:5–8, 15, 132–134`: GPL is accepted only for the dependencies of `Packages/ISH`, and any other package that depends on it fails).

**What must hold when it lands** ([D69](../plan/decisions.md#d69), [R54](../plan/risks.md#r54), [`NOTICE`](../../NOTICE)):

1. iSH and any Open Minis code live in one GPL-3.0 leaf module that only the iPhone and iPad target links and no Apache-2.0 module imports; the Mac app and `memoshid` link no GPL code.
2. The iPhone and iPad app is a GPL-3.0 combined work: no closed-source code in it, and its source offered at its tag with every distributed build, including internal TestFlight builds for friends; iSH's `LICENSE.IOS` exception is self-checked; the App Store conflict stays with O13.
3. Every dependency joining the iPhone app gets a compatibility check. A clean scan or a module boundary does not establish compatibility for PolyForm Kuvo material, so none enters that app without resolved combined-work rights ([D91](../plan/decisions.md#d91)).
4. `[INFERENCE]` Today's scan covers package graphs only; a product-level check that the Mac bundles contain no GPL code (DIST-03) has to land with the module.

## 11. NOTICE corrections made by this review

1. Added `Packages/MemoshiCore/Sources/Store/Migrations/001_event_log.sql`, whose header names the Draft 3 store paths, to the list of re-expressed files.
2. Replaced "The broader P0-17 licence/provenance review remains open" (P0-17 is the port audit; the licence review is P0-22) with a pointer to this record and the §7 table, keeping the statement that neither is redistribution clearance.
3. Added the test-only resolved dependency `swift-json-schema` 0.14.2 (MIT, "Copyright (c) 2024 Austin Evans"), which `NOTICE` omitted.

## 12. Open public/commercial redistribution blockers

None blocks private, personal-use work ([D91](../plan/decisions.md#d91)). Each must close before a public or commercial release (O13).

| # | Blocker | Evidence | Owner |
|---|---|---|---|
| B1 | No recorded licence for Draft 3-derived material: the six re-expressed files and the adapted plan/token text | §3 | User (copyright holder); EL records it in `NOTICE` |
| B2 | Kuvo-sourced text and values: keep, attribute or rewrite the quotations; name a revision or runtime observation for Kuvo-audit token values or replace them. The unattributed job phrase was rewritten on 2026-11-03 | §7 | PD ([R37](../plan/risks.md#r37)) |
| B3 | GPL-3.0 iSH module obligations, including the source offer, `LICENSE.IOS` check, dependency compatibility and the App Store conflict | §10 | EL ([R54](../plan/risks.md#r54)) |
| B4 | Product-level third-party inventory: which packages each shipped bundle links, and the components vendored inside Pi_Swift such as the QuickJS guest | §5, §6 | EL, RT |
| B5 | Pi_Swift `892585f` is resolved from an unpublished sibling repository; a source release needs the pinned engine published or vendored with its licence | `NOTICE` | RT, Pi_Swift maintainer |
| B6 | MIT attribution decisions for adapted values and lines: Aiden token values (shipped Markdown scale) and the upstream Pi bench lines in the research harness | §5, §9 | PD (tokens), RT (harness) |
| B7 | Research documents quote third-party posts, licences and vendor text, and include verbatim prior-research copies; review them before the repository becomes public | §7; for example the [Viticci full record](2026-10-21-viticci-full-record-sep-oct.md) (44 quoted passages of at least 60 characters, [supplementary-checks.txt](../../../evidence/2026-11-03-memoshi-provenance/supplementary-checks.txt)) and the [research index §3](README.md#3-prior-research-before-draft-4) | Research owner |
| B8 | The rights/legal review before public or commercial redistribution, and the lawyer's review of the GPL module before a public release | [D91](../plan/decisions.md#d91), [R16](../plan/risks.md#r16), [R54](../plan/risks.md#r54) | User |

## 13. Limits of this review

- Scans find shared text, not translation, paraphrase or structural copying; the Swift re-expressions are identified by headers and review.
- Pi_Swift sources and its vendored resources were not compared (scope: its `LICENSE`/`NOTICE` only), so Memoshi code was not checked for text copied from Pi_Swift.
- Kuvo was compared at two local revisions only; copying from other revisions, from Kuvo's website or from other products would need further sources.
- The untracked files of parallel Phase 0 work were scanned as they stood on 2026-11-03 and may change before they are committed.
- Access to the prototype was read-only except that one `git status` refreshed the stat cache in its `.git/index` (2026-11-03 10:55:31 +0300). Its HEAD (`ce39f8a`) and its 261 status entries were the same before and after; no tracked content, ref, staged change or working-tree file changed.
- No legal interpretation of PolyForm, GPL, MIT, Apache-2.0 or the prototype's terms is offered; the questions are tracked in §12.

## 14. Later 2026-11-03 integration: test vectors and unchanged dependency terms

This addendum does not rerun or extend the earlier tree-wide similarity scan. The [current integration proof](../HANDOFF.md#multi-conversation-device-proof) and its [canonical licence output](../../../evidence/2026-11-03-memoshi-wave3-integration/ci-final.txt) still resolve 31 accepted dependency occurrences. Pi's immutable revision is unchanged. The manifests additionally consume `PiEnv` from that same licensed SDK and use the existing NIO pin for the standalone egress target and non-shipping device prototype; no Cacophony or KuvoLink implementation is a package dependency.

[`NoiseVectorTests.swift`](../../Packages/MemoshiIPC/Tests/MemoshiDeviceTests/NoiseVectorTests.swift) identifies two kinds of **test-only numeric data**, not a cryptographic audit or published validation for every implemented pattern:

- Published `Noise_IK_25519_AESGCM_SHA256` and `Noise_K_25519_AESGCM_SHA256` values came through the pre-existing local `~/Projects/Cognitio/Packages/KuvoLink/Vectors/noise.json`. Its `source` field names [Cacophony's vector file](https://github.com/haskell-cryptography/cacophony/blob/master/vectors/cacophony.txt). That local input and the retained [Cacophony subset](../../../evidence/2026-11-03-memoshi-s2-devices/noise-reference/cacophony-subset.json) have identical SHA-256 `84f1fdfee3bab8a684237b579fc799c555243d167077110434d0aafac2688668`. The input does not identify an immutable upstream commit; the snapshot digest is recorded rather than assigning it an invented revision.
- The upstream [root licence](https://github.com/haskell-cryptography/cacophony/blob/master/LICENSE), read on 2026-11-03, is **The Unlicense**, with a public-domain dedication and warranty disclaimer. These recorded upstream terms are distinct from Kuvo's terms; they do not license the whole local KuvoLink implementation or clear other Kuvo-derived material.
- `IKpsk2`/`IK` ChaChaPoly values are [independently generated cross-implementation data](../../../evidence/2026-11-03-memoshi-s2-devices/noise-reference/cross-implementation-vectors.json), SHA-256 `61d9faa485de82aa1c543e1aea1bc0cb3efbafbba17d910874d3b910ea1f7958`, from the retained Python/pyca-cryptography reference. They are not described as upstream-published vectors. That generator and raw source snapshot remain outside this repository.

The first retrieval used the existing local data; this addendum fetched upstream repository/licence metadata, not an implementation import. No reference app, Haskell implementation, skill payload or raw capture is added to a product. The broader product-inventory, provenance and public/commercial redistribution limits in §12 remain open.

## Sources

- Evidence: [scan-licenses.out](../../../evidence/2026-11-03-memoshi-provenance/scan-licenses.out), [provenance-scan.py](../../../evidence/2026-11-03-memoshi-provenance/provenance-scan.py), [provenance-scan.txt](../../../evidence/2026-11-03-memoshi-provenance/provenance-scan.txt), [provenance-scan.json](../../../evidence/2026-11-03-memoshi-provenance/provenance-scan.json), [licence-facts.txt](../../../evidence/2026-11-03-memoshi-provenance/licence-facts.txt), [supplementary-checks.txt](../../../evidence/2026-11-03-memoshi-provenance/supplementary-checks.txt).
- Repository: [`NOTICE`](../../NOTICE), [`LICENSE`](../../LICENSE), the five `Package.resolved` files, [`scripts/scan-licenses.sh`](../../scripts/scan-licenses.sh), [phase-0 §7](../plan/phase-0.md#port-list), [in-house assets §7](agentic-workspace-landscape/landscape/in-house-assets.md#draft-3-build), [policy.md](../specs/policy.md), [design-tokens.json](../specs/design-tokens.json), [skills catalogue](../skills.md).
- Commits: [`9ed972e`](https://github.com/mehmetcanbudak/Memoshi/commit/9ed972e7fca6dcc6a8ea6280f2cf58533c32d3bb), [`e440063`](https://github.com/mehmetcanbudak/Memoshi/commit/e440063754083b4abe4f652c4fd8b5b6d8d3066f), [`d4793c0`](https://github.com/mehmetcanbudak/Memoshi/commit/d4793c0b51d374703e81aa58b54cfe3c7d5108bd), [`8a4abaf`](https://github.com/mehmetcanbudak/Memoshi/commit/8a4abaf0e7136c82b69e31dab3960105054c19d6), [`d32939b`](https://github.com/mehmetcanbudak/Memoshi/commit/d32939ba535e6ea4843a59d6a5be6f36c987b315), [`e99a2b3`](https://github.com/mehmetcanbudak/Memoshi/commit/e99a2b3a65205c8945a8d65f1818ef087189691f), [`92dec81`](https://github.com/mehmetcanbudak/Memoshi/commit/92dec819ccca96496f4cf8d6d90bb32defc53f1f), [`522e34f`](https://github.com/mehmetcanbudak/Memoshi/commit/522e34ff7ccea8531643bdc86f61201cd7192dd5), [`b9b2240`](https://github.com/mehmetcanbudak/Memoshi/commit/b9b22403208b71a0eeb9ddfb4be1f0410f26b81e).
- External, read-only: the Draft 3 prototype at `ce39f8a`; Pi_Swift `892585f` (`LICENSE`); upstream Pi `22dc6c26`; the local Kuvo clone at `230827f9` and `ddd492b`; the installed Kuvo apps; the Apple/Xcode skill export.
