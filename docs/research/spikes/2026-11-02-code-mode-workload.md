# Code Mode workload, p95 limits and memory ceiling

**Status:** **Accepted 2026-11-03 by [D98](../../plan/decisions.md#d98)** as proposed; the limits below are binding for S1.18 and [Phase 0 open question 5](../../plan/phase-0.md#open-questions) links here. D89/D90 record, authored 2026-11-02, due Mon 2026-11-09. It defines inputs, boundaries, sample counts and pass/fail limits. **At authoring no Node, Pi_Swift or device measurement had been taken, and no harness had been compiled or run. Later on 2026-11-02 the Swift harness was compiled directly against the Core Debug products and launched once each for W1 and W2 on the Mac as a diagnostic ([§8.1](#81-mac-consumer-diagnostic-2026-11-02)). That diagnostic is not a measurement under §5 and not gate evidence; no Node, Release, wasm2c or device measurement exists.** Acceptance is not a measurement or SDK acceptance. D87's calendar, D89's Thu 2026-11-12 device date and D90's slice rule are unchanged; Mac kill runs are released and device runs still lack their host and provisioning ([phase-0 §3](../../plan/phase-0.md#team-and-calendar)).
**Owns:** Memoshi's representative Code Mode workloads, their deterministic fixtures, the measured boundary, cold/warm definitions, sample counts, separate cold/warm p95 limits, the incremental-memory ceiling and the stop/limit acceptance for the pinned guest on both backends and both reference devices.
**Depends on:** [D80](../../plan/decisions.md#d80), [D83](../../plan/decisions.md#d83), [D89](../../plan/decisions.md#d89), [D90](../../plan/decisions.md#d90); [phase-0 S1/S1.18](../../plan/phase-0.md#s1); [04 §4.7, §4.17, §12](../../plan/04-architecture.md#47-code-mode); Pi_Swift [requirements E7/§4](../../../../Pi_Swift/docs/research/apple-bots-engine-requirements.md#4-gates-before-an-app-depends-on-the-engine), [roadmap P05/P08](../../../../Pi_Swift/plans/001-swift-port-completion-roadmap.md#p05) and [VERIFICATION §5](../../../../Pi_Swift/docs/VERIFICATION.md#5-gate-evidence-d46); [fixtures](fixtures/CodeModeWorkload/22dc6c26f3c5/).

## 1. Summary

| Item | Value |
|---|---|
| Guest | quickjs-wasi 3.6.2 / QuickJS-NG 0.17.0, `quickjs.wasm` 637,405 bytes, SHA-256 `d4c9375f2b1ca4dc95f72c8aa2982a7a9951ac8011490d79c6582df732b4bbd9` |
| Backends | wasm2c (shipping, WABT 1.0.42) is the gate subject; WasmKit (reference/compatibility) is always measured and reported |
| Devices | iPhone 14 Pro is binding for D89/D46; iPad Pro 12.9-inch (5th generation, M1) runs the same protocol and limits and is reported separately ([D80](../../plan/decisions.md#d80)) |
| Timing workloads | **W1** issue digest: 5 nested calls, about 11 KB of results. **W2** batch read: 12 nested calls across 3 tools, about 462 KB of results |
| Stop/limit cases | **W3a** Stop in a polling loop, **W3b** Stop in a native sort, **W3c** memory-limit failure |
| Samples | 10 launches per device × backend × case. W1/W2 launches yield one cold and one warm sample each. p95 is nearest-rank, so with 10 samples it is the **maximum** |
| W1 limits | cold p95 **≤ 600 ms**, warm p95 **≤ 100 ms** |
| W2 limits | cold p95 **≤ 1,500 ms**, warm p95 **≤ 1,000 ms** |
| Memory ceiling | **≤ 100,000,000 bytes** of physical footprint over the idle baseline, warm pool and retained VMs included |
| Stop | Stop to settled p95 **≤ 1,000 ms** (W3a, W3b) |

## 2. Fixture set

The data fixture directory mirrors Pi_Swift's `Tests/<Target>/Fixtures/<Kind>/<rev12>/` convention, keyed by the upstream head the scripts target. The two Swift qualification sources live at Memoshi's runtime integration boundary but are explicitly excluded from the shipped `MemoshiRuntime` target. Copy the fixture data and both linked Swift sources into the SDK owner's measurement host; no additional public library API is required.

| File | Contents |
|---|---|
| [`scenario.json`](fixtures/CodeModeWorkload/22dc6c26f3c5/scenario.json) | Machine-readable composition, tool generator rules, workloads, protocol and limits |
| [`expected.json`](fixtures/CodeModeWorkload/22dc6c26f3c5/expected.json) | Exact returned strings, nested-call counts per tool, policy-decision counts, byte sizes and W3 outcomes |
| [`provenance.json`](fixtures/CodeModeWorkload/22dc6c26f3c5/provenance.json) | Pins, read sources, derivation, execution status, revision history and SHA-256 of every fixture file |
| [`scripts/`](fixtures/CodeModeWorkload/22dc6c26f3c5/scripts/) | The exact `code` argument of each codemode call |
| [`CodeModeWorkload.swift`](../../../Packages/MemoshiCore/Sources/Runtime/Qualification/CodeModeWorkload.swift) | Nonshipping one-launch protocol against Pi_Swift's public API at the consumer pin: fixture tools with a served-call ledger, counting policy hooks, timed codemode wrapper, footprint, environment and guest readings, verification |
| [`CodeModeWorkloadCLI.swift`](../../../Packages/MemoshiCore/Sources/Runtime/Qualification/CodeModeWorkloadCLI.swift) | macOS smoke driver: one child process per launch, each with a private store directory under an explicitly supplied absolute `TMPDIR`; propagates the first failing child status and never signals a child. Mac numbers are never gate evidence |
| [`harness/codemode-workload-bench.ts`](fixtures/CodeModeWorkload/22dc6c26f3c5/harness/codemode-workload-bench.ts) | Node-oracle baseline for W1/W2, written against the same upstream APIs as `test/codemode-bench.ts` at `22dc6c26f3c5` |

The Swift harness uses only APIs read at consumer pin `892585fc8d8be3093b58c34aacffcd4e68c3a8d9`: `openSqliteStorage`, `Harness.open`, `Conversation.configure/submit/abort`, `Submission.wait`, `createRegistry`, `Extension`, `HookRegistration`/`HookHandlers`, `ToolRegistration`, `createCodemodeTool`, `CodemodeSandbox(options:)` with `memoryLimitBytes`, `wasmLoader` and `onWorkerStarted`, `loadQuickJSWasm`, `getQuickJSWasmURL`, `CodemodeWorkerLifetime.exited`, the faux provider with its request count and pending responses, and `task_info(TASK_VM_INFO)` in the same form as Pi_Swift's `Scripts/benchmarks/ai-release.swift`. A direct `swiftc` compile against those modules confirmed this API use on 2026-11-02 (§8.1). `phys_footprint`, `ledger_phys_footprint_peak` and `os_proc_available_memory()` were checked in the installed iPhoneOS 27.2 SDK headers.

Expected values were derived from the generator rules and cross-checked at authoring time by an independent reimplementation. On 2026-11-02 Pi_Swift at the consumer pin reproduced every W1 and W2 expected value in all six turns of the Mac diagnostic (§8.1). W3 outcomes are unconfirmed. The first oracle check is still the Node baseline in the prepared oracle worktree: every sample must report `verified: true` before any device timing is interpreted.

## 3. Workloads

Fixture tools are deterministic, replay-safe and callable only by scripts (`callers: [tools]`), so the measured time is engine and durable overhead, not tool latency. Their exact rules are in `scenario.json`.

| ID | Script shape | Why it is representative |
|---|---|---|
| W1 `issue-digest-5` | `issues_list` once, then 4 parallel `issue_get`; parse four 2.7 KB issue documents, sort by update time, count checklist items and words; return a 344-byte JSON string | Requirements §4's example, "a durable Code Mode script with 5 nested tool calls", and phase-0 exit-demo step 6 ("summarize the five newest issues … five nested calls") |
| W2 `batch-read-12` | `code_search`, then 10 parallel `file_read` (46,000 bytes and 1,000 lines each) plus `symbols_outline`; multiline regex over 460,000 characters; return a 150-byte JSON string | 07-coding §10.1's "find all callers of `x`, read each, summarize". Each read sits just under the 51,200-byte / 2,000-line default tool output limit in both upstream `truncate.ts` and Pi_Swift `Truncate.swift`, so this is the largest result a nested call returns inline. 12 calls across 3 tools matches the design system's CodeModeCard example |
| W3a `stop-polling-loop` | `probe_mark`, then an endless arithmetic loop | Stop during JavaScript that polls the interrupt handler |
| W3b `stop-native-sort` | Build 262,144 numbers, `probe_mark`, then default `Array.prototype.sort()` | Stop during a long native built-in: [P05-04](../../../../Pi_Swift/plans/001-swift-port-completion-roadmap.md#p05)'s non-polling case |
| W3c `memory-limit` | `probe_mark`, then 1 MiB strings until the configured QuickJS limit fails the script | The always-set memory limit fails the script, not the host |

Every turn also crosses a counting `pi.tool` policy hook, so W1 must record 6 decisions (outer call plus 5 nested) and W2 13. This stands in for E21's mandatory policy, which does not exist at the pin; the product evaluator's own cost belongs to Memoshi's separate policy budgets.

## 4. Boundaries, cold and warm

- **Composition (unmeasured):** a fresh file-backed SQLite store per launch, the faux provider (`faux/faux-1`, no pacing), the fixture tools and policy hooks, `Harness.open`, model configuration. Store open plus resume is already budgeted separately (E26, < 50 ms p95).
- **Idle baseline:** after 2,000 ms idle, before any Code Mode object exists, read `phys_footprint`.
- **Code Mode initialisation (`codemodeInitMs`, measured):** construct `CodemodeSandbox` and install the codemode tool into the live registry. No VM may start before the cold turn; the harness fails the launch if one did. A backend that pre-initialises VMs at construction pays for it here.
- **Gated boundary (`codemodeMs`):** entry to return of the durable codemode tool's `execute`, read by a wrapper that adds two clock reads. It includes module loading, VM creation or pool acquisition, prelude, script, every nested durable tool task with its hooks and commits, the journal and the committed result. It excludes faux streaming and the outer result commit.
- **Reported, not gated:** `turnMs` from `submit` to the terminal `wait()`, comparable with upstream `bench:codemode`; commits per turn; module-load and worker counts.
- **Cold sample:** the first turn of a fresh process, after initialisation. Every cold sample is a new launch.
- **Warm sample:** the third turn of the same launch, after one recorded warm-up turn, each preceded by 1,500 ms idle. The gap stands for one model round trip between scripts (first token p50 < 1.5 s, [MASTER_PLAN §14](../../plan/MASTER_PLAN.md#14-success-metrics)) and gives an asynchronous pool time to refill. At the consumer pin there is no warm pool, so warm means a cached parsed module and a fresh VM; after [P05-05](../../../../Pi_Swift/plans/001-swift-port-completion-roadmap.md#p05) it means the shipping pool at steady state.

## 5. Protocol and samples

1. **Build and environment:** Release, no debugger (the harness records `P_TRACED`), a signed host app installed on the device, device unlocked, host in the foreground, Low Power Mode off and `thermalState` nominal before each launch. Charging state and OS build are recorded.
2. **Launches:** 10 per device × backend × case, each a fresh process started by the device driver, which enforces 120 s per W1/W2 launch and 300 s per W3 launch and records a missed deadline as a failed launch.
3. **W1/W2 launch:** composition, idle baseline, initialisation, cold turn, warm-up turn, warm turn, final footprint after 1,500 ms idle.
4. **W3 launch:** composition, idle baseline, initialisation, a verified W1 warm-up, the W3 turn, a verified W1 isolation turn, final footprint. For W3a/W3b the harness waits for `probe_mark`, waits 100 ms, presses Stop through `Conversation.abort()` (the product Stop path), then waits for the submission's terminal state and the VM lifetime's exit.
5. **Statistic:** nearest-rank p95 of 10 samples is sample 10 of 10, the maximum. Report every raw sample, median and maximum.
6. **Validity:** a launch counts only if every turn verifies against `expected.json`, no VM started before the cold turn, and the build/environment checks held. A verification failure fails that configuration; a root-caused harness defect may be fixed and the whole configuration rerun, as VERIFICATION §5 allows for kill batches.

## 6. Limits and grounding

These are product budgets taken from accepted Memoshi contracts, not predictions of device performance. The M4 Max figures in Pi_Swift's engine report are desktop observations and were not used to set them.

| Limit | Value | Grounded in | Derivation |
|---|---|---|---|
| W1 warm p95 | ≤ 100 ms | [D83](../../plan/decisions.md#d83)'s Swift engine probe: < 100 ms p95 for a 200-line bot-written card on the reference iPhone 14 Pro, and limits enforced within 100 ms ([04 §4.17](../../plan/04-architecture.md#swift-engine-probe)); approval card visible < 100 ms p95 on the runner ([04 §12](../../plan/04-architecture.md#12-performance-budgets), D83); iSH per-command overhead < 100 ms p50 ([06 iSH probe](../../plan/06-computers-and-browsers.md#ish-probe)) | Memoshi's accepted budget for one step of in-app code work on the reference devices; a small script is one such step |
| W2 warm p95 | ≤ 1,000 ms | D83's probe bound for the large unit: < 1 s for a 2,000-line mini app on the reference iPhone | The large representative script gets the large-unit bound |
| Cold allowance | +500 ms | Daemon start to ready, no live work, < 500 ms ([04 §12](../../plan/04-architecture.md#12-performance-budgets), D83) | Cold limit = warm limit + the accepted engine cold-initialisation budget. One-time costs do not depend on the script, so the allowance is the same for both workloads |
| W1 cold p95 | ≤ 600 ms | As above | 100 + 500 |
| W2 cold p95 | ≤ 1,500 ms | As above | 1,000 + 500 |
| Incremental footprint | ≤ 100,000,000 bytes | D83's probe treats "a 100 MB allocation" by one bot-written program as a runaway that must be stopped on the reference iPhone; E26 gives ten idle bots < 300 MB; the iSH probe allows a heavy runtime < 300 MB, and only the heavy runtimes take turns ([D80](../../plan/decisions.md#d80)) | A representative script must stay below the runaway case. Code Mode is not in the turn-taking set, so it cannot claim a heavy-runtime allowance. The decimal reading of "100 MB" is the stricter one |
| Stop settled, W3a/W3b | p95 ≤ 1,000 ms | CH-07: "Stop settles in < 1 s with consistent state" ([feature catalog](../../plan/feature-catalog.md)) | Measured from Stop to the submission's terminal state; no nested call may follow Stop |

Further rules:

- **Ceiling measurement:** per W1/W2 launch, `max(ledger_phys_footprint_peak, phys_footprint)` at the end minus the idle baseline. The ledger peak is a process high-water mark [INFERENCE: field name and ledger semantics; the harness also keeps `phys_footprint`]; any pre-baseline transient therefore counts against the workload, which is conservative. The maximum over 10 launches must not exceed the ceiling. For W3 launches, the final `phys_footprint` after the isolation turn minus the baseline must not exceed it, so a VM still unwinding after Stop counts.
- **W3b exit time:** `workerExitedMs` is recorded but not limited here. P05-04 owns the safe hard-stop contract; Memoshi requires only that retained memory stays inside the ceiling and that no call follows Stop.
- **W3c:** the script must fail with text naming the limit (`out of memory` or a sandbox failure), the host must survive, and the isolation turn must verify. Its peak is recorded, not held to the ceiling, because the case is designed to reach the configured limit.
- **Gate subject:** wasm2c must meet every limit on the iPhone 14 Pro. WasmKit results are always reported; under [D89](../../plan/decisions.md#d89) WasmKit may cover a compatibility failure only after meeting the same limits, never as an unmeasured escape. The iPad and Mac do not substitute for the iPhone.
- **Sandbox configuration:** `memoryLimitBytes` 268,435,456, the value in [04 §4.7](../../plan/04-architecture.md#47-code-mode)'s sketch and upstream `bench:codemode`; timeout 300,000 ms; default stack and interrupt settings. The product's iOS limit is not decided here (§9). W1/W2 do not approach it; W3c deliberately does.

## 7. Results to retain

One `memoshi.codemode-workload.result.v1` JSON line per launch. It carries the workload, the backend label and the evidence that confirms it, the launch index, environment before/after, idle baseline and `codemodeInitMs`. For every sample it records `codemodeMs`, `turnMs`, commits, decisions, codemode executions, model requests, nested calls as reported and as served, script, served and result bytes, the returned text, verification and W3 stop times. It ends with the final footprint, incremental peak, resolved guest path and SHA-256, and failures. Retain the device model and OS build, Pi_Swift revision and, for wasm2c, the generated-source digest and compiler settings that P05-02 records. Phase-0 also requires interruption/trap results; W3 supplies the deterministic Code Mode inputs, while Swift/C trap injection stays in P05-03's own safety suite.

## 8. What cannot run yet

Every item below is an execution prerequisite, not a waiver. An unmeasured case is not a pass.

| Prerequisite | State on 2026-11-02 | Owner | Effect on this record |
|---|---|---|---|
| wasm2c backend | Absent at the consumer pin and at SDK HEAD `f5dc5a1`; P05-02/P05-03 unchecked, P05 "current execution deferred" | Pi_Swift | The gate subject cannot be measured |
| Backend selection and identity | `QuickJSEngine` and `backendName` are internal; WasmKit is the only adapter; no E32 capability flag. §8.1's label rests on that source fact, not on runtime identity | Pi_Swift (P05-06, P07-01) | Results need verifiable backend identity before they count |
| Warm pool | Not implemented (P05-05) | Pi_Swift | Today's warm samples measure module reuse only |
| Safe hard stop for non-polling built-ins | Open (P05-04) | Pi_Swift | W3b exit time is informational until resolved |
| Node-oracle differential gate | Not run (P05-07) | Pi_Swift | Timing may be measured, but wasm2c cannot become default before it passes |
| Generated-C provenance, helper resources, no-JIT linkage | Open (P05-02, P05-08). §8.1's consumer binary links JavaScriptCore through PiCore's `ECMAScriptRegExp` | Pi_Swift | Measured builds must carry them |
| iOS Release measurement host and device driver | `PiChaosHost`/driver are P08 deliverables that "do not exist yet" | Pi_Swift (P08-01) | Nothing can run on the reference devices |
| Device execution hold | Released in principle on 2026-11-03 (user delegated; [phase-0 §3](../../plan/phase-0.md#team-and-calendar)); device runs still need the host, driver and provisioning below | User | No device run can start yet |
| Signing/provisioning for a host on the user's iPhone and iPad | Not established; this task changes no account, profile or signing setting | User and Memoshi host integration | Required before installation |
| Slice tag | D90 counts S1 results only on a `slice-N` tag; **Leave release blocked** stands, so no tag exists | User decision on the quota hold | Device numbers before a tag are development observations, not gate evidence |
| SDK broader qualification | **Keep broader qualification blocked** (SDK disk hold) stands | User/parent | No SDK qualification run follows from this record |
| Node baseline host | VERIFICATION §5 takes the Node baseline on the 16 GB M1 reference box; its readiness is not recorded | User | The baseline is diagnostic; its absence does not change the device limits |
| Fixture confirmation | Analytic. W1/W2 reproduced by Pi_Swift (Debug, WasmKit, Mac; §8.1); not oracle-confirmed; W3 unconfirmed | Pi_Swift on first run | Run the Node baseline first |
| Mandatory policy and common host entry | E21 and E32 `BotRuntime.open` absent; the fixture policy extension stands in | Pi_Swift (P04-08, P07-01) | Re-run through E32's path once it exists, so the measurement exercises what Memoshi ships |
| iPad lane | Same prerequisites | Pi_Swift with the user's release | Reported separately; not part of D89's Thu 11-12 requirement |

**Later status, reconciled 2026-11-06:** [D98](../../plan/decisions.md#d98) accepted this workload/protocol/limits, and the [SDK notice](../../../../handoffs/2026-11-03-pi-swift-answer-and-v1.5.0-sync-for-memoshi.md) accepted them as measurement input. Later notes report development backend work, but the accessible request/source does not contain the advertised answer/interfaces and no qualifying consumer baseline is supplied. See the [delivery reconciliation](2026-11-02-pi-swift-consumer-handoff.md#current-delivery-reconciliation-2026-11-06). The dated source observations above remain historical; neither the notice nor input acceptance is parity, Release/device/p95 acceptance or permission to lift SDK holds.


### 8.1 Mac consumer diagnostic, 2026-11-02

This is a development observation. It is not a measurement under §5 and not gate evidence. It shows three things: the harness compiles against the pinned public API, W1 and W2 produce every expected value through Pi_Swift's durable Code Mode path, and the guest resolves from the integrated Core build. Hashes and the full change list are in [`provenance.json`](fixtures/CodeModeWorkload/22dc6c26f3c5/provenance.json) `history[1]`.

- **Harness revision.** Review before the compile found three defects, all now fixed. Byte sizes and served calls were never checked. A Stop turn could not detect a call after Stop when the aborted call returned no result. The CLI dropped failing child statuses and trapped on `--launches 0`. Each turn now also checks one codemode execution, exactly two faux model requests, the fixture tools' own served-call ledger and every `inputBytes` size. Each launch records its resolved guest. Expected values are unchanged.
- **Build.** Both harness files were compiled with one direct `swiftc` (Swift 6.4.2, `-swift-version 6 -Onone -D DEBUG`, macOS SDK 27.2), with no warnings. The link used `libMemoshiRuntime.a` only as the carrier of the pinned objects. Its Pi_Swift and WasmKit members are byte-identical to the Core `Products/Debug` objects, which were built from the clean checkout at the consumer pin. The harness imports only Pi_Swift modules and system frameworks, and the binary defines no Memoshi-module symbol.
- **Run.** One driver-mode launch each for W1 and W2 (`--launches 1`). The environment was empty apart from a fresh synthetic `HOME` and `TMPDIR`, `PATH`, `LANG` and `PACKAGE_RESOURCE_BUNDLE_PATH`, which pointed at Core `Products/Debug`. Driver and child exited 0 with no failures. The synthetic `HOME` and `TMPDIR` were empty afterwards, and no process was signalled.
- **Guest.** Both launches resolved `Products/Debug/Pi_PiCodeMode.bundle/Contents/Resources/quickjs.wasm` (637,405 bytes, SHA-256 `d4c9375f…4bbd9`). The executable's directory holds no resource bundle, so the guest was found through the Debug-only `PACKAGE_RESOURCE_BUNDLE_PATH` override.

| Workload | Turns verified | Result | Nested calls (reported = served) | Decisions | Model requests | Served bytes | `codemodeMs` cold / warm-up / warm | Incremental peak |
|---|---|---|---|---|---|---|---|---|
| W1 | 3 of 3 | exact, 344 B | 5: `issues_list` 1, `issue_get` 4 | 6 | 2 | 10,928 | 6,204 / 6,211 / 6,168 ms | 13,074,456 B |
| W2 | 3 of 3 | exact, 150 B | 12: `code_search` 1, `file_read` 10, `symbols_outline` 1 | 13 | 2 | 461,598 | 12,542 / 12,443 / 12,477 ms | 21,233,688 B |

These timings come from Debug (`-Onone`) WasmKit objects on a Mac, with one sample per mode. They are not compared with §6's limits and support no p95, Release, wasm2c, device or SDK-qualification claim. The WasmKit label follows from the pin having only one `QuickJSEngine`, not from runtime identification. This run did not exercise W3a/W3b/W3c, Stop, CLI failure paths or the Node oracle; later CLI diagnostics are recorded below. Proof is in the owned throwaway scratch `/private/tmp/memoshi-codemode-workload-smoke.OZR7YMkY` (`MANIFEST.sha256`, `run-W1/`, `run-W2/`, `proof/`).

### 8.2 CLI failure propagation and scratch ownership, 2026-11-02

- **Original failure-path run.** Ten malformed numeric `--launch`/`--launches` values returned usage status 64. An absent fixture propagated launch status 1. A synthetic fixture copy with only the expected W1 result count changed from 4 to 5 returned verification status 2 from both child and driver. All three turns failed only result equality; actual output, served counts and byte sizes remained correct. A verification failure is status **2**, not 1.
- **Missing-value defect fixed.** A trailing `--launch` or `--launches` had been ignored, starting the default ten-child driver. Missing values and a second flag in place of a value now return 64 before work begins.
- **Cleanup claim corrected.** The original revision used `FileManager.temporaryDirectory`; on Darwin that may select the per-user temporary directory before `TMPDIR`. Empty synthetic `HOME`/`TMPDIR` did **not** prove where the old store lived. The corrected CLI requires an explicit absolute `TMPDIR` and constructs its private 0700 directory directly beneath it.
- **Corrected executable exercised.** Seven cases passed: four missing/flag-valued arguments, absent and relative `TMPDIR`, and the one-child negative oracle driver. During the latter run, live sampling observed real store files beneath the supplied directory, owned by the current UID with mode 0700; no scratch files remained after normal exit. The three turns retained their expected counts and failed only result equality; driver status was 2. No process was signalled. Source/binary/proof hashes are in `provenance.json` `history[3]`.
- **Scope.** Swift sources are nonshipping qualification code under `MemoshiRuntime/Qualification`, explicitly excluded from the library and co-compiled with their host; no new public product API or lint exemption was added. The diagnostic ran alongside Memoshi CI and supplies no timing, Release, device, backend-identity, W3 or SDK qualification claim. Proof roots: `/private/tmp/memoshi-codemode-cli-failure-smoke.AQycobwq` and `/private/tmp/memoshi-codemode-cli-corrected/proof`.

## 9. Decisions this record needs

1. **Limits/protocol accepted by [D98](../../plan/decisions.md#d98).** SDK measurement-input acceptance is separately reported above. That closes the input decision, not any performance/backend/platform acceptance.
2. **Product iOS memory limit per Code Mode VM.** P05-05 requires an always-set limit; Memoshi has only 04 §4.7's 256 MiB sketch. If the product chooses another value, W3c and the ceiling evidence are re-run with it.
3. **Device execution and installation.** Memoshi's physical runs were released in principle on 2026-11-03, contingent on the real host/devices/provisioning. SDK-specific qualification/release holds are separate and remain; no profile/install/signing action or physical result follows from this record.

## 10. Sources

- Memoshi: decisions D80, D83, D88–D90, D96; phase-0 S1, S1.18, the S1 measurement table, exit criteria and open question 5; 04 §4.7, §4.17 Swift engine probe, §12 performance budgets; 06 iSH probe; 07 §10.1; MASTER_PLAN §14; feature catalog CH-05, CH-07; HANDOFF §8.
- Pi_Swift, read only: requirements E7, design notes and §4 at the consumer pin; [Code Mode engine report](../../../../Pi_Swift/docs/design/code-mode-engine-2026-10-23.md); roadmap P05, P07-01, P08 and its qualification matrix at HEAD `f5dc5a1`; VERIFICATION §§4–5; MILESTONES M5; the API files listed in `provenance.json`.
- Upstream at `22dc6c26f3c5`, read only: `packages/durable/test/codemode-bench.ts`, `src/codemode/codemode.ts`, `src/harness/types.ts`, `src/truncate.ts`, `packages/codemode/src/types.ts`.
- Installed SDK: iPhoneOS27.2 `mach/task_info.h` (`phys_footprint`, rev3 `ledger_phys_footprint_peak`), `os/proc.h` (`os_proc_available_memory`), Foundation `NSProcessInfo.h` (`thermalState`, `isLowPowerModeEnabled`).
