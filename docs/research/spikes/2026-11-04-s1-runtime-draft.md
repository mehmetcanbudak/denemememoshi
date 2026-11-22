# S1 runtime, policy and recovery — development report

**Status: DRAFT / NOT QUALIFIED — 2026-11-04.** This records development evidence, failures and remaining acceptance, not a Phase 0 exit or an SDK release receipt. [S1 acceptance](../../plan/phase-0.md#s1) remains binding. Owners: RT for runtime/SDK contracts; NAT for native/device/reference qualification.

Consumer candidate remains **`892585fc8d8be3093b58c34aacffcd4e68c3a8d9`**. No sibling SDK source was changed or newer baseline adopted. Normal app/helper composition remains `.none`: production command/file tools, MCP, Code Mode, environment and subagents remain disabled. The [consumer handoff](2026-11-02-pi-swift-consumer-handoff.md) owns H0–H4 and the existing release/broader-qualification holds.

## 1. Completed live-runtime lifecycle proof

The [actual default-timer receipt][lifecycle] passed with three real Pi SQLite stores/Harnesses in one owned process. The driver used the unchanged 600-second idle configuration, not an accelerated test clock. A temporary process-scoped `caffeinate -i` assertion prevented system idle sleep; it changed no system setting or runtime idle threshold.

| Observed invariant | Actual result |
|---|---|
| Idle Session closure | 601.068393750 seconds after last use |
| Unrelated Assistant Chat | Stayed open while separately exercised |
| Delete / restore / purge | Two deletions, one restore, one purge; only selected stores affected |
| Historical mutation receipts | Original delete and purge receipts preserved, including replay after restore |
| Process identity | Same PID 72079 throughout the scenario |
| Reopen after idle | Two open stores after the independent idle Session reopened |
| Candidate / application schema | Unchanged candidate above / schema 12 |

This is **runtime-host development proof**, not an authenticated memoshid/GUI/SMAppService run or a reference-hardware benchmark. The process closed its actual runtime/stores and removed only its own synthetic work root.

After the explicit logical lock-release repair below, a [fresh actual lifecycle run][lifecycle-lock] again exited 0, preserving PID 39382, the unrelated Chat and every original mutation receipt. It used the same default 600-second configuration; the observed close was **643.311993208 s** and command wall time **677.68 s** under the concurrent development workload. That late observation is retained, not rounded to ten minutes or promoted to reference-timing acceptance.

### Reproduced deletion/recovery defects and repairs

[Failing-before evidence][lifecycle-red] exercised replacement of the Store ancestor/root/Pi directory, replacement of the lock directory and a pending-purge request ID reused by another mutation. The old purge could resolve another tree; failed purge/request collision could permanently poison startup.

The Store now retains verified root/Pi/run descriptors for its lifetime, performs conversation locking and purge operations relative to those descriptors, and refuses known path replacement before handing a pathname to the pinned SDK. Pending purge IDs reserve their method/parameter identity in shared request lookup. Failed runtime acquisition releases only its own new claim or actually acquired ownership, never a different live owner's reused lease. This does not claim H3's general guarded file service or eliminate the SDK's pathname-opening contract.

The earlier [Core snapshot][core] passed **86 Store, 150 Runtime and 32 Egress tests** after these fixes. A later public-Store regression retained a duplicate lock descriptor: closing the logical owner left `flock` held, so reopening failed with `alreadyOpen`. That regression [failed before repair][lock-alias-red]. `FileLock.release` now explicitly relinquishes the shared lock under its existing mutex before closing its own descriptor; the regression also verifies that the replacement owner still excludes another writer. This consumer Store repair is not SDK H0.

The [current complete Core run][core-serial] passed **87 Store / 15 suites (1.687 s), 151 Runtime / 30 suites (118.623 s), and 32 Egress / 4 suites (7.017 s)**, including that lock transition and cooperative host cancellation. Command wall time was **325.41 s**, not acceptance of the combined upstream/Memoshi five-minute reference budget. An earlier implicit-parallel run cleared the ownership regressions but retained five issues in wall-clock-limited Code Mode/approval and sandbox cases. The passing control explicitly used `--no-parallel`, with the same deadlines, assertions, test selection and scenario-internal concurrency. The canonical package runner now makes that scheduling explicit and disables automatic dependency resolution. This is functional development verification, not a claim that resource-contention, reference-hardware, physical-device or SDK qualification gates passed.

### Qualification-carrier request lifetime

Later canonical runs retained an S1 host-test timeout at **77.339 s** and **113.079 s**
against its unchanged 60-second limit. Isolated and original-suite-order phase traces did
not reproduce the delay; temporary tracing was removed. The direct owned-runner sample
also shifted a long delay to an earlier HTTP case, so it does not establish a cause or a
repair for the original timeout. [Raw failures and diagnosis][host-timeout] remain visible.

A separate reproduced defect let `LoopbackHTTPServer.close()` return while request
callbacks still ran; the full run recorded NIO work scheduled after loop shutdown. The
[real HTTP regression][request-drain-red] failed because the active callback was neither
canceled nor finished when close returned. The listener now owns those tasks, closes
admission, cancels requests, closes channels and drains callbacks before shutting down the
event loop. Concurrent close callers await the same shutdown task.

The [complete repaired daemon suite][request-drain-after] passed **35 qualification tests
and one daemon-security test**, including active-request drainage and both held-stream
proxy cases, without changing deadlines. The [actual rebuilt `s1` CLI][current-cli]
then passed in **7.375 s**: one owned kill during five streams, five original receipts
replayed, ten store opens, 64 retention commits during eight streams and zero canary hits
across 56 retained files. The driver removed its own work root. This is current scripted
private-pipe development proof, not authenticated daemon/UI, real-model, reference or
Phase 0 acceptance; it is not an explanation of the earlier timing failure.

### Lifecycle payload and generated-schema integration

The later [complete canonical run](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/canonical-final-d109cc93/ci.log)
passed the runtime/daemon packages but exposed stale lifecycle schema definitions.
`SessionRestoredPayload`'s synthesized empty decoder also accepted `null`, scalars
and arrays and never requested an object container from the schema recorder.
The [six-input consumer regression](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/restored-object-red-df6f86a0/command.log)
failed before repair.

The payload now uses the existing `EmptyParams` keyed-object coding convention;
valid version-1 `{}` wire bytes are unchanged. The [real schema-generator CLI](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/protocol-schema-current-fcccea46/run.json)
regenerated the committed schema from Swift, including all **34** modeled requests.
The [complete original protocol suite plus the new regression](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/protocol-lifecycle-after-fb88e283/command.log)
then passed **41 tests**, including validation of all **180** fixture cases, before
redundant artifact-copy/registry/style checks were removed. Actual wire-boundary,
canonical generation, closed-definition/reference checks and the CLI schema-drift
gate remain. No validator, fixture, payload version, SDK pin or acceptance hold was
weakened.

## 2. Approval kills: separate controlled and real-model cohorts

The [controlled external-model cohort][controlled] passed ten actual pending-approval SIGKILL/reopen cases using real Pi, policy hooks, durable task memos, application decisions/cards and the external effect ledger. Only the external HTTP model was controlled; no runtime, storage or approval decision was mocked.

| Cohort / invariant | Actual result |
|---|---:|
| Controlled-model pending approvals reattached to original decision/card | 10 of 10 |
| Controlled-model duplicated effects / effects before decision | 0 / 0 |
| Controlled-model output canary hits | 0 across 47 files |
| Real `qwen3:0.6b` complete approval-attempt scenarios | 7 of 10 passed |
| Real-model actual pending approvals that reattached | 9; one attempt never reached a tool or approval |
| Real-model duplicated effects / effects before decision | 0 / 0 |
| Real-model output canary hits | 0 across 45 files |

The [real-model batch][real] is retained as **failed**, not replaced by the controlled cohort. Its [independent upstream metadata][upstream] forwarded response payloads without rewriting and retained only content/reasoning byte counts, finish reasons and usage:

- `r002`: upstream request 7 returned `stop`, zero visible content, reasoning content and no tool call. No pending approval existed to kill.
- `r007` and `r009`: post-tool upstream requests 32 and 42 returned `stop` with zero visible content and reasoning content. The same durable approvals had reattached, but the transcript correctly failed its nonempty-final-answer criterion.

These three failures are explained by the observed upstream responses, not inferred Pi text loss. The earlier five-point real-model batch remains separately retained; its missing upstream capture prevents a retrospective assertion that its empty answers had the same cause. The ten controlled cases do not qualify iOS, invocation-free waits, arbitrary expiry/cancellation races or H1's nested-result/owner-retirement window.

## 3. Real children and active Stop

The owned local model completed one [foreground child][foreground] and one [persistent background child][background] through actual Pi subagent execution. Each had a real task-owned child conversation, original-parent attribution, a committed checkpoint and inspectable history. These are normal-execution development observations, not kill/resume, native active attachment or physical-device acceptance.

The [active-child Stop negative control][child-stop-before] exposed a separate defect: the child was durably `canceled` while its cooperative Swift host callback still finished its wait and wrote one checkpoint. The fixture waited for executor drainage before checking the ledger, so process exit did not hide a late effect.

The repair adds `RuntimeToolInvocation.runCancellable`: only Sendable host-owned work enters the SDK's abort-bound Swift task; the non-Sendable SDK invocation and nested `callTool` remain on their original executor. First-party asynchronous export/checkpoint/effect callbacks now use that boundary. A [fresh real-model run with the same delegation prompt][child-stop-after] actually entered the child checkpoint, requested targeted child Stop, observed the child `canceled` and root `done`, drained the executor and verified **zero checkpoint effects**. It exited 0 in 20.99 s; that wall time is not an abort-latency distribution. The separate [actual Pi-to-Python bridge](2026-11-04-s6-pyodide-draft.md#2b-actual-pi-to-worker-tool-bridge-and-active-stop) also propagated engine Stop to a running infinite worker and executed successfully afterward. Arbitrary uncooperative callbacks, real-model child kill/resume, native attachment and physical-device acceptance are not established.

Historical real-crypto/scripted-child SIGKILL and native completed-child inspection are carried forward from [the existing handoff](../../HANDOFF.md#multi-conversation-device-proof), not recreated or reclassified as full real-model active-child qualification.

An additional foreground/background kill/reopen driver did not reach either child: both first lives returned `modelUnavailable` before an original task receipt. The [current prerequisite record][model-prerequisite] retains the provider's empty model catalog and absence of the previously authorized cached manifest/GGUF. No model was downloaded, user cache restored, credential fallback used or failed cohort resampled. Those attempts are **not child kill/recovery results**; earlier completed local-model observations retain their original provenance.

## 4. Acceptance disposition

| Row | Development evidence / remaining gate |
|---|---|
| S1.1 conversation spine | Existing signed five-conversation send/kill/replay proof carried forward; full real-model/platform acceptance remains open. |
| S1.2 lifecycle and measurements | Default idle/live deletion proof above passed. Existing open/resume/admission/commit samples are development measurements, not reference-box acceptance. |
| S1.3 provider usage/cost | Local streaming/usage and controlled provider contracts exercised; two real API-key providers, provider-side comparison and complete cost matrix remain unavailable. |
| S1.4 live prompts/cache | Existing next-request scripted contracts retained; real-provider stable cache and ten-edit matrix remain open. |
| S1.5 model/effort/tools | Existing next-request contracts retained; local reasoning effort is explicitly unsupported rather than silently accepted. Full real-provider matrix remains open. |
| S1.6–S1.7 children | Normal real-model foreground/background execution and one real active-child Stop passed. Real-model kill/resume, native attachment and complete cancellation/platform coverage remain open. |
| S1.8 Code Mode | Existing live nested/scripted interruption evidence retained. Integrated five-call recovery and the authoritative nested-result retention window remain H1-dependent. |
| S1.9 MCP | Mac stdio/deferred search and real loopback HTTP OAuth consumer contracts passed in Core. Both-platform remote OAuth/secrecy acceptance remains open. |
| S1.10 policy | Existing 200-call model/nested/MCP coverage is carried forward. Complete general rewrite, throwing-hook/redaction/audit acceptance on both platforms is not claimed. |
| S1.11 approval kills | Controlled Mac cohort above passed; separate real-model batch failed. Physical iOS and general durable-wait/recovery contracts remain open. |
| S1.12 environment | Private-copy/UDS-gateway development proof is separate from full H3 external-daemon conformance and physical in-app environment qualification. |
| S1.13 chaos | No complete 50-kill real-model matrix across streaming/tools/nested/approval/children/compaction on either platform. No smaller cohort is called this acceptance. |
| S1.14 abort | Corrected cooperative host cancellation passed actual real-child and Pi-to-Python Stop probes. The complete 20-abort latency/background-survival series remains open. |
| S1.15 long Chat | Two long-chat compaction/reset quality runs and required dogfood judgment remain open. |
| S1.16 event mapping | Existing content-free application facts and authoritative Pi history mapping retained; no second transcript store introduced. |
| S1.17 combined conformance | Memoshi-only Core snapshot above is not the combined upstream/Memoshi CI qualification or its under-five-minute gate. |
| S1.18 physical iOS / Code Mode | No physical iPhone/iPad connected. Genuine continued-processing grant/expiry, simultaneous app/App Intent open refusal and Release backend measurements remain unrun. D98 workload/limits and H4 remain binding. |

## 5. Gate and next prerequisite

S1 is **not qualified**. No D46 platform fallback, SDK adoption, production-tool promotion or broader/release hold was silently changed. Required next inputs include an accepted qualifying SDK receipt, physical reference devices, reference Mac measurements, two broker-provisioned API-key providers and separate authorization for billed/cloud kill batches. The observed weak local-model failures stay visible; output rewriting or repeated sampling until a passing batch is not a substitute.

[lifecycle]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/lifecycle-live-0711c0fa/lifecycle.json
[lifecycle-red]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/lifecycle-ownership-failing-before.txt
[core]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/core-integrated-tests.txt
[controlled]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/approval-controlled-ten-6c21ff81/summary.json
[real]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/real-model-approval-ten-1920af3f/chaos/summary.json
[upstream]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/real-model-approval-ten-1920af3f/stream-metadata.json
[foreground]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/local-model-foreground-child.json
[background]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/local-model-background-child.json
[child-stop-before]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/local-model-active-child-stop-before-fix.json
[child-stop-after]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/local-model-active-child-stop-after.json
[core-serial]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/core-serial-integrated-clean.json
[lock-alias-red]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/lock-alias-release-before-fix.json
[lifecycle-lock]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/lifecycle-lock-release-86952972/lifecycle.json
[model-prerequisite]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/local-model-current-prerequisite.json
[host-timeout]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/host-timeout-diagnosis-a2ad29ba/diagnosis.json
[request-drain-red]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/shutdown-regression-red-a017bc87/command.log
[request-drain-after]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/shutdown-regression-after-faeb9b19/command.log
[current-cli]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/s1-current-cli-53c73716/s1-measurements.json
