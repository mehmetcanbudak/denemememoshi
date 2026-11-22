# S5 ship path (signing, notarization, TestFlight, transport): Phase 0 spike report (draft)

> **Draft, 2026-11-14, with later updates (2026-11-18, 2026-11-21): not the final report; rows not yet run count as fail under the timebox rule.**

Reports are due Wed 2026-11-25; the gate is Fri 2026-11-27. Memoshi builds against Pi_Swift's tag `slice-2` since [D134](../../plan/decisions.md#d134) (2026-11-14). Results recorded before the `slice-2` pin (`de5e8ee`, 2026-11-14) are on the earlier development candidate `892585f` and are development evidence ([D90](../../plan/decisions.md#d90)); later results are on `slice-2`, and each row names its commit. The owner put signing, provisioning, the reference Macs and the clean VM last ([phase-0 §3](../../plan/phase-0.md#team-and-calendar), execution hold). None of them has been used: no G2 Developer ID certificate, no Developer ID provisioning profile, no notarization, no clean macOS 27 VM, no TestFlight upload and no physical iPhone or iPad for a Memoshi build. (Pi_Swift's own development-signed runs used both devices on 2026-11-20 in team `476T8NQCSX`, where the owner registered the iPad for development builds that day; [HANDOFF](../../HANDOFF.md#pi-swift-2026-11-21).) `scripts/release-gates.json` still records `releaseBlocked: true` and `broaderQualificationBlocked: true`. The records that do exist come from the development Mac (`Mac16,6`, 36 GB, macOS 27.0.1, 26A434, observed 2026-11-14), with Apple Development signing (Team `476T8NQCSX`).

Sources: the [2026-11-04 S5 draft](2026-11-04-s5-distribution-draft.md) (updated 11-06; used as a source), [HANDOFF](../../HANDOFF.md) foundation and consumer sections, the [11-13 code review section](../../HANDOFF.md#code-review-2026-11-13), [canonical-ci-12](../../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-12/README.md) and the [2026-11-02 replay record](../../../../evidence/2026-11-02-memoshi-consumer-qualification/replay/replay-report.json).

**What later records changed in the 11-04/11-06 draft.**
- The draft's latest canonical run was 630 Swift and 23 release-tooling tests (11-06). The current record is commit `7f766c8` (2026-11-21), on the Pi_Swift `slice-2` pin with a clean tree: 1,562 Swift Testing tests in 16 runs and 111 release-tooling tests, all 18 steps passed, "Sign-in flows" and "Bundle layout" included ([canonical-ci-25](../../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-25/README.md)). It ran on the development Mac with `MEMOSHI_BUILD_ROOT` set; it is not a clean-clone remote run. The record on `8e7bd5b` ([canonical-ci-17](../../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-17/README.md): 1,474 Swift Testing tests in 16 runs plus 6 XCTest and 105 release-tooling tests, all 17 steps), the record on `a2ac274` ([canonical-ci-15](../../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-15/README.md): 1,465 Swift Testing tests in 15 runs plus 6 XCTest and 105 release-tooling tests, all 17 steps, in-tree `.build` with `MEMOSHI_BUILD_ROOT` unset), the record on `6ef4d10` plus the XcodeGen 2.47.0 change ([canonical-ci-16](../../../../evidence/2026-11-19-memoshi-canonical-ci-16/README.md)), the record on `7df84f9` ([canonical-ci-12](../../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-12/README.md): 1,305 Swift tests, 74 release-tooling tests, all 17 steps, including "Sign-in flows" and "Bundle layout" with no Mach-O among 423 files under `Contents/Resources`, run with `MEMOSHI_BUILD_ROOT`) and the records on `4658dcd` ([canonical-ci-11](../../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-11/README.md)), `f22517d` ([canonical-ci-06](../../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-06/README.md)) and `4db72e2` ([canonical-ci-05](../../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-05/README.md)) remain those commits'.
- The draft's capacity problem (ENOSPC on the external scratch) was worked around on 11-08: builds use an owned internal-disk build root ([HANDOFF 11-08](../../HANDOFF.md#engineering-follow-ups-2026-11-08)). The clean-clone remote CI receipt is still missing.
- Since 11-13 CI no longer runs on `pull_request` ([D90](../../plan/decisions.md#d90); [HANDOFF](../../HANDOFF.md#code-review-2026-11-13)). The release refuses until the Python licence texts are bundled ([D126](../../plan/decisions.md#d126)); [D133](../../plan/decisions.md#d133) bundled them in both apps.
- [D99](../../plan/decisions.md#d99)'s release domain is not bought. Development sign-in runs on `memoshi-auth.pages.dev` ([gate readiness §10](../../plan/gates/phase-0.md#current-clearing-queue-2026-11-06)).

## 1. Questions, answers and evidence

| # | Question (short) | Answer so far | Evidence |
|---|---|---|---|
| S5.1 | G2 Developer ID memoshid, hardened runtime, no JIT or unsigned memory, both Code Mode backends | Not answered. Apple Development-signed helpers ran with hardened runtime (`flags=0x10000(runtime)`) and empty entitlements. No G2 identity; no wasm2c backend at the candidate pin `892585f` (`slice-2` has one; not exercised) | [signing details](../../../../evidence/2026-11-02-memoshi-consumer-qualification/replay/signing-details.txt), [HANDOFF foundation](../../HANDOFF.md#observed-development-proof) |
| S5.2 | Both Developer ID profiles embed and validate; production push and CloudKit; profile expiry dates | Not answered. Profile validators exist in `scripts/release.py`; only a wildcard Mac development profile was ever issued | [11-04 draft §3](2026-11-04-s5-distribution-draft.md#3-acceptance-disposition), [HANDOFF provisioned Keychain](../../HANDOFF.md#provisioned-native-keychain-proof-2026-10-26) |
| S5.3 | Launch to `system.hello` ready | Not answered for the signed helper. The runtime host's spawn-to-ready (p95 163.6 ms, n = 3, Debug) is a different boundary and does not stand in for it | [S1 measurements](S1-runtime.md#2-measurements) |
| S5.4 | `SMAppService.agent` with `BundleProgram` in the helper; survives quit, kill -9, replace; hidden relaunch | Not answered. The development helper is app-owned; `SMAppService.notFound` was observed and the supervisor permits a foreground helper without registering a service | [HANDOFF foundation](../../HANDOFF.md#observed-development-proof) |
| S5.5 | Notarized, stapled DMG on the clean VM, no Gatekeeper warning | Not run | — |
| S5.6 | TCC prompt attribution for `~/Documents` reads | Not run | — |
| S5.7 | `run/` 0700, socket and token 0600, token minted per start, peer checks; replay without gaps | On the 2026-11-02 source with Apple Development signing: 1,000 reconnect cycles (990 disconnects, 10 helper EOF/restarts); 0 gaps and 0 duplicates live and in a sequence-zero rebuild, identical chain hash; token rotated. Modes 0700/0600 observed on 10-25 | [replay-report.json](../../../../evidence/2026-11-02-memoshi-consumer-qualification/replay/replay-report.json), [HANDOFF foundation](../../HANDOFF.md#observed-development-proof) |
| S5.8 | Keychain broker answers memoshid only after the peer checks | Development proof only (wildcard profile): device-only Save/get, wrong-purpose refusal, broker-backed local inference. Not on a notarized build | [HANDOFF provisioned Keychain](../../HANDOFF.md#provisioned-native-keychain-proof-2026-10-26) |
| S5.9 | Update replaces the app while a task runs; resumes with no duplicate | Not run | — |
| S5.10 | Internal TestFlight on the iPhone 14 Pro and iPad Pro | Not run; no Memoshi build has run on either device. Pi_Swift's development-signed runs used both on 2026-11-20, and the iPad is registered in team `476T8NQCSX` for development builds since then | [devices discovery](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/devices-current.json), [Pi_Swift device runs](../../../../evidence/2026-11-20-pi-swift-device/README.md) |
| S5.11 | CloudKit CAS from memoshid with the app quit | Not run | — |
| S5.12 | Push to the windowless helper, or the app's forwarding fallback | Not run | — |
| S5.13 | Privacy prompt names and usage strings for memoshid's own work | Not run. Permission texts were decided on 11-13 ([D129](../../plan/decisions.md#d129)); no prompt was observed | — |
| S5.14 | Component sizes of the notarized build; CI fails >10% growth | Not answered. `release.py` records a baseline only from notarized G2 artifacts; no baseline exists | [`scripts/release.py`](../../../scripts/release.py) |
| S5.15 | iCloud Drive grants with Desktop & Documents sync | Not run | — |
| S5.16 | WeatherKit in a Developer ID profile on the Mac | Not run; the REST API stays the route until it is ([NEXT_VERSION §4](../../plan/NEXT_VERSION.md#native-scope-by-device)) | — |

## 2. Measurements

```csv
row,metric,n,p50,p95,unit,hardware,os_build,commit_or_run,evidence
S5.7,forced reconnect cycles with 0 gaps and 0 duplicates (live and seq-0 rebuild),1000,n/a,n/a,cycles,not recorded,not recorded,2026-11-02 replay (Apple Development signed),evidence/2026-11-02-memoshi-consumer-qualification/replay/replay-report.json
S5.7,facts applied and acknowledged (live and rebuild),2702,n/a,n/a,facts,not recorded,not recorded,2026-11-02 replay,evidence/2026-11-02-memoshi-consumer-qualification/replay/replay-report.json
S5.7,reconnect cycle loop wall time,1,10025,n/a,ms,not recorded,not recorded,2026-11-02 replay,evidence/2026-11-02-memoshi-consumer-qualification/replay/replay-report.json
CI,canonical scripts/ci.sh wall time (incremental build),1,1199300,n/a,ms,development Mac (not recorded in run.json),not recorded,7df84f9 canonical-ci-12,evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-12/README.md
```

**Measurements that do not exist yet:** every row that needs signing, notarization, the clean VM, `SMAppService`, Apple services or a device; memoshid start-to-ready from the signed helper; local event latency with 8 streaming threads; component sizes.

## 3. Outcome table

Thresholds from [phase-0 §5 S5](../../plan/phase-0.md#s5).

| Row | Pass bound | Measured | Outcome | Evidence | What it needs |
|---|---|---|---|---|---|
| Clean-VM first launch of the notarized DMG | No Gatekeeper warning; agent registered | Not run | **open** (counts as fail at the timebox) | — | Owner: G2 Developer ID certificate, notarization credentials, a clean macOS 27 VM |
| Entitlements | No JIT, no unsigned memory, never `get-task-allow` | Development builds had empty entitlements; no release build exists | **open** | [signing details](../../../../evidence/2026-11-02-memoshi-consumer-qualification/replay/signing-details.txt) | A signed release build from `scripts/release.py` (owner: identity) |
| Certificate | Issued by the G2 Sub-CA; renewal date on the calendar | No Developer ID certificate | **open** | — | Owner: issue the G2 certificate (P0-16) |
| Forced reconnects | 1,000 with 0 gaps and 0 duplicates | 1,000 cycles, 0 gaps, 0 duplicates, rebuild chain equal (2026-11-02 source) | **pass** | [replay-report.json](../../../../evidence/2026-11-02-memoshi-consumer-qualification/replay/replay-report.json) | Rerun on the gate commit: the replay protocol changed on 11-13 (schema 13, `logId`/`afterTs`, [D131](../../HANDOFF.md#d131-work-2026-11-13)) |
| Local event latency (8 streaming threads) | p95 < 20 ms | Not measured | **open** | — | A memoshid event-latency series on the reference box (owner hardware) |
| memoshid start to ready | < 500 ms | Not measured for memoshid | **open** | — | Signed helper launch-to-ready series on the reference box |
| Agent survives app quit, kill -9 and replace | 3 of 3 | Not run (app-owned helper only) | **open** | [HANDOFF foundation](../../HANDOFF.md#observed-development-proof) | `SMAppService` registration from a Developer ID build (owner: identity) |
| Update with a running task (S5.9) | Resumes; 0 duplicates | Not run | **open** | — | Two signed builds; effect-ledger update scenario |
| Internal TestFlight install (S5.10) | iPhone and iPad | Not run | **open** | — | Owner: App Store Connect setup, iPhone 14 Pro and iPad Pro |
| CloudKit CAS from memoshid, app quit (S5.11) | Succeeds | Not run | **open** | — | Owner: memoshid's Developer ID profile with CloudKit |
| Push reaches memoshid (S5.12) | Registered in the helper, or delivered by the forwarding fallback | Not run | **open** | — | Owner: push capability in both profiles |
| CI size gate (S5.14) | A build that grows a component >10% fails | Enforcement code and synthetic tests exist; no measured budget | **open** | [`scripts/release.py`](../../../scripts/release.py) | A notarized baseline build (owner: identity) |

Count: pass 1 · marginal 0 · fail 0 · open 11 (of 12 rows).

The stop rule for Q7 applies: Phase 1 does not start until the ship path works ([phase-0 §1](../../plan/phase-0.md#1-what-phase-0-must-prove)). The clean-VM run and the TestFlight install are on the never-cut list ([phase-0 §10](../../plan/phase-0.md#cut-list)).

## 4. Proposed decision updates

Proposals only.

- **Execution hold on signing:** the owner put signing last. Propose a date for the signing session before 11-25, because every remaining S5 row and exit-demo step 1 depend on it.
- **D99:** buy the release domain before the first release build. Repeat the test sign-ins afterwards.
- **S5.16 / WeatherKit:** no decision until a Developer ID profile exists; the REST API stays the route meanwhile.

## 5. Phase 1 tickets

| Ticket | Scope | Owner lane | Source row |
|---|---|---|---|
| DIST-01 signing | G2 certificate; three App IDs; two Developer ID profiles with CloudKit and push; notarized DMG; clean-VM run | NAT; identity and Apple account actions by the owner | Clean VM, certificate, entitlements |
| DIST-01 helper | `SMAppService` registration, survival 3 of 3, hidden relaunch, update survival | NAT/QA | Agent survives; update |
| DIST-01 mobile | Internal TestFlight on both devices | NAT; devices by the owner | TestFlight |
| DIST-02 | Clean-clone run of `scripts/ci.sh` on the self-hosted runner | APP/QA | (exit criterion) |
| DIST-01 sizes | Baseline from the first notarized build; prove the >10% rejection | NAT/QA | CI size gate |
| SH-02 replay | Rerun the 1,000-reconnect replay and the sequence-zero rebuild on the gate commit | APP/QA | Forced reconnects |
| DEV-05 / S5.11–S5.12 | CloudKit CAS and push from the helper (shared with [S2](S2-devices.md)) | NAT | CloudKit CAS; push |

No row is marginal.

## 6. Spike code

S5 has no `spikes/S5-*` folder. The release tooling (`scripts/release.py`, `scripts/release-gates.json`, `scripts/check-signin-flows.sh`, the bundle checks in `scripts/ci.sh`) is product tooling. CI's "Release tooling contracts" step runs its tests in `scripts/tests`: 111 in the current canonical record ([canonical-ci-25](../../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-25/README.md), `7f766c8`), after 105 in [canonical-ci-15](../../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-15/README.md) on `a2ac274` and 74 in [canonical-ci-12](../../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-12/README.md) on `7df84f9`. Proposal: keep it and extend it with the first real release run.

The 2026-11-18 review fixes (`8b9b170`) change the tooling as follows:
- The TestFlight wait stops at once, with an error that names the state, when the build reaches a terminal internal state: `MISSING_EXPORT_COMPLIANCE`, `PROCESSING_EXCEPTION`, `IN_EXPORT_COMPLIANCE_REVIEW` or `EXPIRED` (`scripts/lib/release_support.py`).
- `release_source` runs `scripts/check-mls-generated.sh` and checks that the checkout is still clean after the build (`scripts/release.py`).
- `scripts/check-prerequisites.sh` refuses a Pi_Swift checkout with ignored files, because SwiftPM compiles ignored sources too. It and `release.py` share `scripts/lib/pi_swift_manifest.py`, which refuses any package in MemoshiCore's manifest that is neither the pinned checkout nor on its reviewed list (`REVIEWED_PACKAGES`).
- `scripts/lint-boundaries.sh` fails on a grep error, a failed source listing or zero files, and its module list names all 49 Pi_Swift modules; a test compares the list with the pinned checkout's manifests.
- `release.py` runs the Release composition scan `scripts/check-bundle.sh --release-composition` on the Mac app in `verify_mac` and in the macOS `archive`, and on the iPhone and iPad app in `verify_mobile`. The scan fails a Release bundle whose Mach-O code contains a Debug-only development tool name.

## 7. Risks re-scored

| Risk | L | I | Score | Proposed | Why |
|---|---|---|---:|---|---|
| [R3](../../plan/risks.md#r3) Packaging, notarization, provisioning, updates | M | H | 6 | Keep 6 | Nothing signed, notarized or registered; tooling only |
| [R46](../../plan/risks.md#r46) Certificate and profile expiry | L | H | 3 | Keep 3 | No G2 certificate or profile yet |
| [R47](../../plan/risks.md#r47) One-builder calendar | H | H | 9 | Keep 9 | Every S5 row waits on owner actions kept last |

## Sources

- [phase-0.md §5 S5](../../plan/phase-0.md#s5), [09-platform-macos.md](../../plan/09-platform-macos.md)
- [2026-11-04 S5 draft](2026-11-04-s5-distribution-draft.md), [HANDOFF](../../HANDOFF.md), [gate readiness review](../../plan/gates/phase-0.md)
- Evidence: [replay record](../../../../evidence/2026-11-02-memoshi-consumer-qualification/replay/replay-report.json), [canonical-ci-12](../../../../evidence/2026-11-13-memoshi-canonical-s2/canonical-ci-12/README.md), [devices discovery](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/devices-current.json)
