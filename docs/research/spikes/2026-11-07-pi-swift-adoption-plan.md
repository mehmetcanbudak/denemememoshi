<!-- Filed 2026-11-07 from the read-only adoption analysis. The SDK request `Pi_Swift/docs/requests/2026-11-07-memoshi-slice-adoption.md` (verification workspace) points here. The pin is unchanged; nothing here is adopted until P1-P3 exist. -->

# Memoshi: plan for adopting the newer Pi_Swift SDK (read-only analysis, 2026-11-07)

**Status:** this is a proposal. Nothing was edited, built or pinned. The pin stays at `892585fc8d8be3093b58c34aacffcd4e68c3a8d9` (`Packages/MemoshiCore/Package.swift:14-19`). The gate also requires that pin (`docs/plan/gates/phase-0.md:9,185,240`).

**Notation.**
- `SDK:` means `/Volumes/PiSwiftVerify-99a45b9ccc5e/workspaces/Pi_Swift/`. `MC/` means `Packages/MemoshiCore/`. `MI/` means `Packages/MemoshiIPC/`.
- SDK status comes from `git --no-optional-locks status --porcelain`, run 2026-11-07 ~13:30 +03:
  - **C**: committed at HEAD `f999b31` and clean.
  - **S**: staged but uncommitted (`M ` or `A `).
  - **W**: uncommitted working-tree edits on top (`MM`, `AM` or ` M`).
- Line numbers in S/W files can shift. `ToolAPI.swift` was being edited during the survey.
- Supporting maps: `local://sdk-api-map.md` and `local://memoshi-side-map.md`.

## 0. Baseline facts that drive the plan

1. **No SDK commit after the pin has ever been CI-qualified.**
   - `3c6ff35` is an ancestor of the pin: `git rev-list --count 3c6ff35..892585fc` = 5, and 3c6ff35 is dated 2026-10-24, the pin 2026-10-25.
   - Its CI run executed all six commands but failed artifact publication on quota (`SDK:docs/VERIFICATION.md:5`, `:1561`).
   - HEAD `f999b31` is 43 commits past the pin, has no tag, and shows 525 porcelain entries.
   - So every H0–H4 and Apple-host API below lacks qualified CI.
2. **SDK full-run state.** Observed from `/Volumes/PiSwiftVerify-99a45b9ccc5e/evidence/main-native-full-current-0{6,7,8}/macos/status` and the XML files.
   - **Run 06:** both profiles exit 1.
     - Default profile: `LoginShellEscapedGroupTests.{returnsTheEnvironment…,reportsAnIncompleteShell…}` and `ContinuedProcessingLifecycleTests.expirationJoinsAnInFlightCommitBeforeClosingAndReturning`.
     - Zero-retention profile: `HarnessTelemetryTests.inheritsTaskTraces`.
   - **Run 07** finished at 10:23:30Z, contrary to "in progress". Both profiles exit 1.
     - Default profile: the same two login-shell tests plus `ContinuedProcessingLifecycleTests.foregroundPublicCompositionCompletesOrRefusesBeforeAdmissionAndReleasesTheWriter`.
     - Zero-retention profile: **`HarnessNestedToolsRestartTests.keepsUnsafeCallerNestedCalls`**, which is H1-relevant.
   - **Run 08** started 10:25:07Z and was running at survey time.
3. **SDK-declared churn after the gate.** At the v1.5.0 sync after the Fri 2026-11-27 gate, the SDK plans:
   - `Storage.commit(batches, receive, context)`;
   - moving watches to Chord;
   - removing `Session.documentState()`, `Conversation.viewState()`, `Harness.taskGraph()` and `DocumentState`;
   - re-basing E17 onto the group-commit `receive`.

   Sources: `SDK:docs/requests/2026-11-02-memoshi-consumer-handoff.md:14,19`. Memoshi uses `watchTaskGraph` and `watchEvents` heavily (`MC/Sources/Runtime/RuntimeAdapter+Engine.swift:98-102`, `RuntimeAdapter.swift:609-613`). A gate-pin adoption will therefore be followed by a second cutover.
4. **Consumer surface.**
   - Only `MC/Sources/Runtime` imports Pi modules (28 files; memoshi-side-map §0).
   - Memoshi references none of `StoreAccess`, `FencedStorage`, lease authority, `ask`/`settle`, file-service injection, wasm2c, `PiAppleHost` or `BotRuntime`.
   - The production app and helper compose `.none` for tools, MCP, Code Mode and subagents (`docs/plan/gates/phase-0.md:9`; `MC/Sources/Runtime/RuntimeExtensionComposition.swift:8-12`; `Packages/MemoshiDaemon/Sources/MemoshiDaemon/DaemonServer.swift:43-48`).
   - [INFERENCE] No shipped user Pi stores exist. Migration must still be correct for dev stores and the historic fixtures (`MC/Tests/MemoshiStoreTests/MigrationTests.swift`, fixtures v1/4/5/6/8).

## 1. Capability map

### H0: one writer per store (E4)

| | Location | Status / notes |
|---|---|---|
| SDK API | `SDK:Sources/PiDurable/Storage/StoreAccess.swift:9` `enum StoreAccess {readWrite, readOnly}`, `:12` `StoreWriterConflict`, `:19` `PersistentStorageAccess` | C (`0b63982`) |
| | `SDK:Sources/PiDurable/Storage/SqliteStorage.swift:5-30` `SqliteStorageOptions(prefix:storePath:access:beforeMigration:commitObserver:)`, `:582` `openSqliteStorage(_:options:databaseOptions:)` | S |
| | E23 probes and hook: `SDK:Sources/PiDurable/Storage/StoreSchema.swift:13` `StoreSchemaStatus`, `:35-61` `StoreMigration`, `:103/:113` probes; `SqliteStorage.swift:22` `beforeMigration` | C (`64a764b`) |
| | iOS close-before-suspend: `SDK:Sources/PiAppleHost/BotHandle.swift` `closeBeforeSuspend()` (lines 15-81) | S (new file) |
| Memoshi today | Three flocks: app store, daemon, per-conversation (`MC/Sources/Store/Ownership.swift:8-22,30-47,132-150`); `checkConversationFile` nlink/path check `:154-171` | Memoshi-owned |
| | Pi file opened by bare path after the conversation lock: `MC/Sources/Runtime/RuntimeAdapter+Threads.swift:92-97` (verified) | |
| | One Harness per storage: `RuntimeAdapter+Engine.swift:12-23`; iOS single engine: `apps/ios/MemoshiMobile/MobileEngineHost.swift:46,59-62` | |
| Delete | Nothing. Deletion test: the three locks also guard `memoshi.sqlite`, the daemon singleton and purge/trash (`Store+ConversationLifecycle.swift:49,222`), none of which the SDK owns. | |
| Adapt | Open the Pi file with `SqliteStorageOptions(storePath:, access: .readWrite, beforeMigration:)`. Map `StoreWriterConflict` to the existing `StoreError.conversationInUse`. Inspection-only opens use `access: .readOnly`, replacing today's "open then refuse to activate" route through `recoveryRequired` (`RuntimeAdapter+Threads.swift:101-107`). | |
| Risks | The SDK writer lock adds sidecars `.n.<name>` / `.p<prefix>.<name>` beside the Pi file (`StoreAccess.swift:49-62`, per the scout). Purge must remove them under Memoshi's conversation lock. The lock-alias repair tests must still cover them (`OwnershipTests.swift:54,199`). | |

### H1: durable waits, memo, settlement, interrupted steps, conversation-wide hold

| | Location | Status / notes |
|---|---|---|
| SDK API | `HookApi.memo(_:)` / `memo(_:value:)`: `SDK:Sources/PiDurable/Harness/TaskRuntime.swift:126,134` | S |
| | `HookApi.ask(_ key:kind:payload:expiresAt:context:) -> WaitResult`: `TaskRuntime.swift:151`; `pendingWaits()`: `:156` | S |
| | `Harness.settle(waitId:value:requestId:context:) -> WaitSettleResult`: `SDK:Sources/PiDurable/Harness/Harness.swift:125` (verified) | W |
| | `WaitSettleResult {settled, alreadySettled(by:value:), expired, notFound}`: `SDK:Sources/PiDurable/Harness/DurableWait.swift:92` (verified) | W |
| | `DurableWaitKind` (`.approval`, `.question`, `.childQuestion`, `.interruptedStep`, `.authority`; open string set): `DurableWait.swift:12-32` | W |
| | Interrupted-step waits never expire: `DurableWait.swift:207` (verified) | W |
| | `InterruptedStep` (including `check` and `decisionWaitId`): `SDK:Sources/PiDurable/Harness/ToolMetadata.swift:188-234` | C |
| | `InterruptedToolDecision {runAgain, skip, markDone}.waitValue(actor:)`: `ToolMetadata.swift:304-315` (verified) | C |
| | `ToolOutcome` / `ToolOutcomeCheck` / `ToolIntent`: `ToolMetadata.swift:24-79`; `ToolRegistration.outcomeCheck(TimeoutMs)`: `Types.swift:165,168` | C / W |
| | `HarnessInspection.waits/.interrupted/.leaseStatus`: `Types.swift:391-402` | W |
| | Store-wide hold: `TaskScheduler.interruptionHold()` `ToolTask.swift:1027`, applied at `Scheduler.swift:512` (verified) and `:701-704` | W |
| | Mandatory `ToolPolicy` / `.conservative`: `SDK:Sources/PiDurable/Harness/ToolPolicy.swift:52,63` | C |
| | Pre-effect gate `HarnessOptions.beforeToolExecution: ToolExecutionGate?`: `Settings.swift:185,188`; `ToolPolicy.swift:93` | S |
| | `ToolExecutionApi.idempotencyKey` = `<sessionId>:<taskId>:<callId>`: `ToolAPI.swift:90` | W, file being edited |
| | `pi.tool` is task version 2 with migration: `ToolTask.swift:193-201` | W |
| Memoshi today | `api as? TaskRuntime` cast to reach `memo`: `MC/Sources/Runtime/PolicyHooks.swift:175-178` (verified) | workaround |
| | Approval wait held inside the `pi.tool` invocation: `PolicyHooks.swift:253-261` (verified), `wait(_:)` `:469-540`; post-restart `reconcile` `:147-167`; dispatch `recheck` `:318-382` | workaround |
| | Memoshi recovery hold: `MC/Sources/Store/Store+ToolDispatch.swift:17-160`, table `unsafe_tool_dispatches` (`MC/Sources/Store/Migrations/008_chat_recovery.sql:15-26`), `Store+ChatRecovery.swift:15-84` (three sources), hook park guard `MC/Sources/Runtime/PolicyHooks+Recovery.swift:9-20,75-103`, `RuntimeToolEffect.swift:1-18`, gating at `RuntimeAdapter+Engine.swift:42-47` and the other sites in memoshi-side-map §H1. Every step is `check: .inconclusive`; no outcome check exists. | workaround |
| | Approvals, cards and audit (product records): `Store+Approvals.swift:9,107,117`, `Store+ApprovalResponses.swift:8,120,140`, `RuntimeAdapter+Approvals.swift:7`; tables `approvals` (002), `approval_bindings.runtime_task_key` (004), `audit_events` (004), `policy_tool_calls` (005) | product |
| | Nested-result capture: `MC/Sources/Runtime/PolicyToolAudit.swift:15-298`; direct `nestedCallDoc` read `RuntimeAdapter+Engine.swift:157-170`; `PolicyHooks+Recovery.swift:22-61` | workaround |
| Delete | `TaskRuntime` cast; in-invocation `wait(_:)` and its expiry poll; `reconcile`; the `memoshi.approval` reattach memo; `Store+ToolDispatch.swift` begin/finish/park bookkeeping; `unsafe_tool_dispatches`; `RuntimeToolEffect`; the unsafe-dispatch source in `readChatRecovery`; the hook park guard for that source. | |
| Adapt | Memoshi policy is split:<br>• **`ToolPolicy`** gets Memoshi's hard allow/deny: kill switch, bot policy, grants, location.<br>• **`beforeTool` hook** calls `HookApi.ask(kind: .approval, key: "memoshi.approval", payload: card, expiresAt: D57 deadline)`.<br>• **`beforeToolExecution` gate** takes the D79 dispatch-time recheck now in `recheck`.<br>Elsewhere:<br>• Cards bind to `waitId` and are rebound from `HarnessInspection.waits` on reopen.<br>• `respondToCard` calls `Harness.settle(..., requestId: client requestId)`. D73 forwarded answers keep the original requestId.<br>• `InterruptedStep` is projected to `Task.interruptedStep`, `tool.interrupted`, `tool.outcome_checked` and `tool.interruption_resolved`.<br>• Resume card: `settle(decisionWaitId, InterruptedToolDecision.*.waitValue(actor:))`.<br>• Tools declare `effects`/`outcomeCheck` in `RuntimeTool`.<br>• `readChatRecovery` keeps one Memoshi-only source: unsettled working-copy exports (`Store+ChatRecovery.swift:33-48`). That source still needs Memoshi's park guard because the SDK cannot see it.<br>• D88 outbox queueing stays in Memoshi. | |
| Keep until the SDK closes the gap | `CommittedToolOutcomes` / `reconcileToolOutcomes` (see §3, gap 2). | |

Kind mapping onto `Task.waitingOn` (object model):
- approval → `approval`
- question / child_question → `user`
- interrupted_step → `resume`
- authority → `authority`
- `InterruptedStep.check == .pending` → `outcome_check`

The SDK has no `outcome_check` or `resume` *wait* kind; the outcome check is a task state, not a wait.

### H2: lease fencing, authority, sequenced feed, snapshots, read-only replicas, promotion

| | Location | Status / notes |
|---|---|---|
| SDK API | `protocol ConversationLeaseAuthority { acquire(storeId:holder:knownEpoch:) }`: `SDK:Sources/PiDurable/Storage/FencedStorage.swift:118` (verified) | C |
| | `ConversationLeaseDecision {granted(epoch: Int, duration: Duration, provisional: Bool), held(by:epoch:)}`: `FencedStorage.swift:22-30` (verified) | C (`dd41b8b`) |
| | `ConversationLeaseValidation` `:34`; `ConversationLeaseStatus` `:45`; `LeaseAuthorityWait` `:59`; `ConversationLeaseRefused` `:124` | C |
| | `actor FencedStorage`: `static open(_:storeId:holder:authority:now:)` `:189-239`; `authorizeExecution()` `:293`; `revalidateLease()` `:304`; `advanceEpoch(to:holder:)` `:322`; feed `head/commits(after:limit:)/exportSnapshot/discardCommits` `:393-405` | C |
| | `CommitIdentity`, `ConversationCommit` (+`encodedLine`), `ConversationSnapshot(asOf)`, `CommitIngestRefused`: `SDK:Sources/PiDurable/Storage/ChangeFeed.swift:13,42,127-131,235` | C (`f999b31`) |
| | `actor ReplicaStorage` (`seed`, `open`, `ingest`, **`promote(holder:authority:now:) -> FencedStorage`**): `SDK:Sources/PiDurable/Storage/ReplicaStorage.swift:24-109` | C (`f999b31`) |
| | `Harness.ingest`: `Session/Ingest.swift:50`; `AgentEventBatch(seq, events)`: `Harness/Events.swift:50,93-99` (W); `CommittedWatch.asOf`: `Session/Observation.swift:72-79` (W) | mixed |
| | Additive namespaces `pi_swift_schema`/`pi_swift_lease` and `pi_feed_*`: `FencedStorage.swift:600-625`, `SqliteChangeFeed.swift:12-30`. Durable schema stays 2 (`SqliteSchema.swift:35`, S). | C |
| Memoshi today | App-store-only fence: `MC/Sources/Store/Store+Ownership.swift:13-124` (`checkFence` inside every Store writer, `Store.swift:73-99`). Pi's database is **not** fenced in its own transaction (comment at `Store+Ownership.swift:85-88`). | workaround |
| | Local lease `expiresAt: Int64.max`: `RuntimeAdapter+Threads.swift:85-86` (verified) | workaround |
| | `recordAuthorityLease` (`Store+AuthorityLeases.swift:1-61`), called only by `Packages/MemoshiDaemon/Sources/MemoshiQualification/S2StoreAdapter.swift:20-31` | qualification only |
| | Device layer, MemoshiIPC (imported only by qualification and `apps/shared/DevicePairing*`):<br>• `MI/Sources/MemoshiDevice/ConversationStore.swift:6-155` (`LeaseRecord`, which has no confirmed/provisional state; `ConversationStore` seam)<br>• `RelayLeaseAuthority.swift`<br>• `DeviceNode.swift:1174-1883` (claim/renew/takeOver/handOver/commit `rseq`/apply/attemptStaleWrite; leases 10 s, renew every 3 s, `:130-131`; replica log limit 4,096 at `:133`)<br>• `MI/Sources/MemoshiDeviceApple/CloudKitLeaseAuthority.swift:10-215` (refuses provisional at `:150-151,214-215`)<br>• `DeviceApplicationFeed.swift:8-235` (group epoch is not a lease epoch, `:64`) | prototype |
| | Event feed: Memoshi's own `Store+Replay.swift:6-16`, `AsOf` `Store+Records.swift:58`; no Pi seq cursor | product |
| | Synthetic replica: `S2StoreAdapter.swift:33-53`; missing pieces stated at `MemoshiQualification/README.md:334-335,392-396` | prototype |
| Delete | `claimConversation(expiresAt: Int64.max)` as the runtime's ownership source; the `S2StoreAdapter` synthetic `ReplicatedRecord` replication of task records; the `MemoshiDevice.ConversationStore` commit/replica path **for conversation data**, which Pi's `ConversationCommit` and `ReplicaStorage.ingest` supersede. | |
| Adapt | Wrap every Pi `SqliteStorage` in `FencedStorage.open(storeId: conversationId, holder: deviceId+storeCopyId, authority:)`. One `ConversationLeaseAuthority` adapter answers from the CloudKit/relay grant plus the D73 direct-hand-over record. It returns `provisional: true` for unconfirmed hand-overs and converts `expiresAt` (absolute, protocol §12.6) to `duration`.<br>`lease.fenced`, failed renewal and local expiry call `advanceEpoch`.<br>The app Store keeps its own `leases`/`checkFence` for `memoshi.sqlite`, which is a separate database, but its epoch comes from the same grant via `recordAuthorityLease`.<br>Event projection moves to `AgentEventBatch.seq` with the cursor stored in Memoshi's transaction.<br>MLS carries `ConversationCommit.encodedLine()` / `ConversationSnapshot.encoded()` bytes as group application messages. | |

**Migration risks.**
- **Downgrade hazard.** The first fenced open writes `pi_swift_*` tables. A pin-era build opening that store "would commit unfenced" (`FencedStorage.swift` ~170-172 doc, per the scout). There is no rollback to the pin except restoring the E23 `beforeMigration` backup.
- D79 requires those backups to be excluded from device backups.
- Plaintext Pi commits must leave the device only inside MLS.
- The replica log limit (4,096) and frame capacity (`DeviceFrameCapacityRegressionTests`) must accommodate snapshots.
- [INFERENCE] `epoch: Int` is 64-bit on all supported targets.

### H3: injectable guarded file service in `EnvDaemonSession`

| | Location | Status / notes |
|---|---|---|
| SDK API | `protocol EnvDaemonFileService { dispatch(_:payload:context:); watch(_:options:onChange:); closeAll() }`: `SDK:Sources/PiEnv/Protocol/DaemonFiles.swift:20-27` | W |
| | `EnvDaemonSession.init(transport:)` (parity default) and **`init(transport:files:)`**: `SDK:Sources/PiEnv/Protocol/Daemon.swift:80,83` (verified) | S |
| | `GuardedDaemonFileService(roots:policy:)`: `SDK:Sources/PiEnv/Guarded/GuardedFileSystem.swift:759,765`. No-follow `openat` walk, nlink ≤ 1, regular files only, temp + `renameat`, read-only roots → `EACCES`, wire codes `SYMLINK`/`NOT_REGULAR`/`EACCES`. | AM (new, edited) |
| | `GuardedRoot`, `GuardedRootProvider`, `GuardedRootSet`, `GuardedFileAccess`, `GuardedFileDecision`: `Guarded/GuardedRoot.swift:15-130` | A |
| | Not on `main`; only on branch `p07-guarded-files` (`f64baef`…`759bac9`) and in the working tree | not in HEAD |
| Memoshi today | `RuntimeSandboxDaemon.serve()` → `EnvDaemonSession(transport:)`: `MC/Sources/Runtime/SandboxComputer.swift:474-487` (verified) | |
| | Seatbelt profile `SandboxComputer.swift:238-326`; D96 private working copies `RuntimeWorkingCopy.swift`, `PrivateWorkingCopy.swift`, `WorkingCopyFileSystem.swift`, `WorkingCopyTree.swift`, `SourceFolderAuthority.swift`, `SourcePathPolicy.swift` | keep |
| | No production sandbox host (`RuntimeEnvironmentComposition.swift:66-67`) | |
| Delete | Nothing. D96 working copies and Seatbelt still confine `exec`/`pty` and admission/export (D96; `docs/plan/decisions.md:1329-1336`). | |
| Adapt | `serve()` constructs `EnvDaemonSession(transport:files: GuardedDaemonFileService(roots: [private working root RW, approved toolchain roots RO], policy: SourcePathPolicy classification))`. The policy must be supplied explicitly; the scout reports the default is `allow`. The roots come from the existing `RuntimeComputer.workingRoot` (`RuntimeEnvironmentComposition.swift:50-52`). | |

### H4: Code Mode wasm2c default

| | Location | Status / notes |
|---|---|---|
| SDK API | `enum CodemodeEngine {wasm2c, wasmKit}`; **`default = .wasm2c`**: `SDK:Sources/PiCodeMode/Engine.swift:8-17` (verified) | MM: the default flip is uncommitted. `VERIFICATION.md:310` says "default remains WasmKit" at `d4f7be7`. |
| | Resolution: an explicit engine wins; a supplied `wasm`/`wasmLoader` selects WasmKit; `.wasm2c` plus a loader throws `CodemodeError` (`Engine.swift:106-115`, per the scout) | MM |
| | `CodemodeSandboxOptions(...engine:warmPool:)`: `Types.swift:126-149`; limits `Engine.swift:23,118-124`; `CODEMODE_MODULE_VERSION = 2`: `SDK:Sources/PiDurable/Codemode/Codemode.swift:8` | MM |
| Memoshi today | `CodemodeSandboxOptions(timeoutMs:memoryLimitBytes:wasmLoader: { loadQuickJSWasm() })`: `MC/Sources/Runtime/RuntimeExtensionSession.swift:112-128`. **Supplying the loader forces WasmKit on the new SDK.** | |
| | Config: 256 MiB / 300,000 ms, `RuntimeExtensionComposition.swift:62-74` | |
| | `CodeModeDeadline.bounded` rewrites `// @options timeout_ms`: `RuntimeExtensionSession.swift:364-395` | |
| | Workload driver: `MC/Sources/Runtime/Qualification/CodeModeWorkload.swift` (excluded from the target, `Package.swift:61`) | |
| Delete | The `wasmLoader` argument. `CodeModeDeadline.bounded` only goes once the SDK documents that `timeoutMs` bounds durable scripts; no such statement was found, so ask (§3). | |
| Adapt | `RuntimeCodeModeConfiguration` gains an explicit `engine` (`.wasm2c`, with `.wasmKit` as the D89 reference/fallback, chosen explicitly and never switched automatically). Memory and time limits stay explicit and identical across launches, because limits enter the replay fingerprint. The workload driver takes `engine` instead of a declared `--backend` label (`CodeModeWorkloadCLI.swift:19`). | |

### Apple host: `BotRuntime` and continued processing

| | Location | Status / notes |
|---|---|---|
| SDK API | `final class BotRuntime` `init(_:)`, `open(bot:context:) -> BotHandle`: `SDK:Sources/PiAppleHost/BotRuntime.swift:29,39,89` (verified at :89). `open` always uses `FencedStorage` with `leases.authority`, E4, E23 probe and backup, mandatory policy, Code Mode, MCP bridge and env. | A (all PiAppleHost Bot* / ContinuedProcessing* files are staged-new) |
| | `BotRuntimeConfiguration(... leases: backup: durability: codeModeLimits: codeModeEngine: ...)`: `BotRuntime.swift:203-262`. On iOS the store dir must be in the app container, not the App Group (`:263-276`). `BotCodeModeLimits.platformDefault`: **macOS unbounded**, iOS 256 MiB (`:310-340`). | A |
| | `BotHandle` (`submit/run/resume/progress/closeBeforeSuspend`), `BotRun.answer` refuses other runs' waits (`answer_outside_run`): `BotHandle.swift:15-117` | A |
| | `ContinuedProcessingHost` (`submit/resume/answer/closeBeforeSuspend`): `ContinuedProcessingHost.swift:13-91`. Outcomes `completed/parked/idle/expired/suspended`: `ContinuedProcessing.swift:9-152`. `BGContinuedProcessingTaskRequest` strategy `.fail`, `<prefix>.<UUID>`: `ContinuedProcessingPlatform.swift:137-181` | A |
| Memoshi today | Own composition: `RuntimeAdapter` / `InProcessEngine` (`MC/Sources/Runtime/InProcessEngine.swift:12-70`); iOS host `apps/ios/MemoshiMobile/MobileEngineHost.swift:15-110` (backup exclusion `:94-104`) | |
| | Own continued processing: `apps/ios/MemoshiMobile/ContinuedTurnProcessing.swift:11-139` (`prefix.turn.<requestId>`, strategy `.fail`); `Packages/MemoshiApp/Sources/AppCore/InProcessChatModel.swift:39-45,101,252-256,562-615`; `Info.plist:5-8` | |
| Delete (if adopted) | `ContinuedTurnProcessing.swift`. The composition half of `RuntimeAdapter+Engine/Threads` duplicates `BotRuntime.open`. | |
| Adapt (if adopted) | `ContinuedProcessingHost` requires a `BotHandle`, so continued processing cannot be adopted without `BotRuntime`. The identifier prefix must stay inside the `$(PRODUCT_BUNDLE_IDENTIFIER).turn.*` permission. Pass explicit `codeModeLimits`, since the macOS default is unbounded. Use `harness.settle` directly for cross-run and forwarded answers (D73) rather than `BotRun.answer`. Configure `BotStoreBackup` copies inside the excluded container (D79). | |

**Recommendation.** Defer `BotRuntime` and `ContinuedProcessingHost` to the last unit (U9).
- Every file in the module is uncommitted.
- Both full runs fail `ContinuedProcessingLifecycleTests`.
- The module overlaps Memoshi's composition, credentials and catalog.

Adopt the lower-level Harness, FencedStorage and policy seams first. They are the same seams `BotRuntime` composes, so U9 becomes a composition swap, not a semantic change [INFERENCE].

## 2. Sequenced adoption units

Every unit is a clean cutover: callers migrate, obsolete code and tests go, no aliases remain. Each unit ends with canonical `scripts/ci.sh`. Retained failures stay failures. No unit starts before preconditions P1–P4 (§3).

**Store schema 12 compatibility.**
- The SDK never reads `memoshi.sqlite`, so schema 12 is compatible as-is for U1 and U2.
- The Pi file stays at durable v2. Fencing adds `pi_swift_*` and `pi_feed_*` namespaces.
- Memoshi needs **schema 13** in U3 and U4, and possibly 14 in U6. Proposed contents:
  - `approval_bindings.wait_id` (unique), replacing `runtime_task_key` as the reattach key;
  - drop `unsafe_tool_dispatches`, guarded by an empty-or-settled precondition;
  - `leases.status` (confirmed/provisional);
  - per-conversation Pi feed cursor `pi_commit_seq`.
- Each migration needs a `MigrationTests` fixture from v12.

| # | Unit | Change | Acceptance observation | Tests obsolete → rewritten |
|---|---|---|---|---|
| U0 | Precondition check | Verify the tag commit contains H0–H2. H3 and H4 may be later units. Read its consumer note. | Tag and CI evidence URL recorded in `Package.swift`'s comment and in HANDOFF. | — |
| U1 | Pin move + mechanical API migration + mandatory policy split | New revision in `MC/Package.swift:16-19`; Package.resolved.<br>Migrate `Double` timestamps and `Usage`, typed task contracts (`TaskReference`/`SettledTask`, `.definition`/`.erased`), `HookApi.now()`/`report()` now `throws`, `subscribeCommitsReturningTask`, `SessionResourceCleanup`/`RegistryListener`, `AuthEvent.deviceCode Double?`, `OAuthTokens JSONString` (`SDK:docs/CHANGES-FOR-CONSUMERS.md:35-42,85-128,99-107,328-331,417-420,457-460`).<br>Install a real `ToolPolicy` carrying Memoshi's hard allow/deny; approvals stay in the hook for now.<br>Open Pi stores with `SqliteStorageOptions(storePath:access:beforeMigration:)` and map `StoreWriterConflict` (H0). | CI green with the same test inventory.<br>A deliberately undeclared-effect tool is denied by policy.<br>A second writer gets `conversationInUse`.<br>A pin-era fixture Pi store opens and its tasks resume. | `InProcessEngineTests.swift:151` and `RuntimeLifecycleTests.swift:153,183` adapt. Every test constructing `HarnessOptions` gains a policy. |
| U2 | H1 waits | Approvals via `HookApi.ask`. Cards bound to `waitId`. `respondToCard` → `Harness.settle(requestId:)`; expiry D57 on the `HarnessOptions.now` clock. Delete the cast, `wait(_:)`, `reconcile` and the approval memo. Migration 13a (`approval_bindings.wait_id`). | Handoff §2.3 (`docs/research/spikes/2026-11-02-pi-swift-consumer-handoff.md:73`):<br>• 10 kills during a pending approval leave `restarts == 0` and the same card, with nothing executed before the decision;<br>• two concurrent settles give `settled` + `alreadySettled`;<br>• settle after the deadline gives `expired`;<br>• a replayed or forwarded requestId does not double-settle;<br>• stop gives a `canceled` card. | `ApprovalStoreTests.swift:57` `sameMemoReattachesOriginalApproval` → waitId rebind.<br>`RuntimePolicySafetyTests.swift:52` `normalCloseCancelsPendingDecision` → close **parks**; only stop/abort cancels (§2.1.2/§2.1.6).<br>`RuntimePolicyContractTests.swift:9`, `RuntimeToolOriginTests.swift:221`, `InProcessEngineTests.swift:163` adapt.<br>The README "SDK approval waits" limitation (`MemoshiQualification/README.md:540-544`) and the ChaosDriver failed-run expectation are removed. |
| U3 | H1 interrupted steps + hold | Tools declare `effects`/`outcomeCheck`. Project `InterruptedStep` / `ToolInterruption` to Memoshi tasks and events. Resume card → `settle(decisionWaitId, InterruptedToolDecision…waitValue(actor:))`. Dispatch recheck moves to `beforeToolExecution`. Delete the `Store+ToolDispatch` bookkeeping, `RuntimeToolEffect` and the unsafe-dispatch hold source. Keep the working-copy-export hold and its park guard. Migration 13b drops `unsafe_tool_dispatches` (refuse while rows are `started`/`unknown`). | §2.3: an interrupted unsafe call taking each of `happened` / `not_happened` / `inconclusive` → Run again / Skip / Mark as done, each with its exact model text and exactly one `tool.outcome_checked` / `tool.interruption_resolved`. Sibling, child, compaction and inbox runs are observed blocked while the decision is pending (`BlockReason.interruptedStep`). Run again reuses `idempotencyKey` against an effect ledger. | `RuntimeRecoveryTests.swift:9,61,99,133,189` rewritten against SDK holds (`uncertainEffectDoesNotContinue` becomes outcome-check cases).<br>`RuntimeToolEffectKeyTests.swift:9,44` → SDK key format.<br>`ChatRecoveryStoreTests.swift:*` → working-copy and SDK sources.<br>`WorkingCopyRecoveryStoreTests` kept.<br>README "No Resume card yet" (`:545-547`) removed. |
| U4 | H1 nested-result retention | **Only after gap 2 closes.** Delete `CommittedToolOutcomes` / `reconcileToolOutcomes`, the direct `nestedCallDoc` read (`RuntimeAdapter+Engine.swift:157-170`) and the `projectionFailed` path. | A SIGKILL between nested-owner retirement and the app receipt recovers the exact final outcome/audit once with no repeated effect (handoff §2.4 "What acceptance still needs"). | `RuntimeToolAuditTests.swift:10,95` adapt; add the retirement-cut chaos point (README `:550-562`). |
| U5 | H2 local fence | `FencedStorage.open` with one `ConversationLeaseAuthority` adapter (Memoshi Store + CloudKit/relay grant). `advanceEpoch` on `lease.fenced`. Provisional → `authority` wait. Remove `expiresAt: Int64.max`. Wire `recordAuthorityLease` into the runtime. `beforeMigration` backup excluded from device backup. Migration 13c (`leases.status`). | A stale-epoch commit is rejected whole (no half-apply) and fails the Session. `advanceEpoch` → the next commit fails. Open with a superseded epoch is refused before `resume()`. A provisional runner makes no external effect until settle confirms. No non-replay-safe call runs after the local deadline until revalidation. A pin build is refused or documented on a fenced store. | `AuthorityLeaseTests.swift:17,43,65` adapt; `RuntimeLifecycleTests.swift:153,183` rewrite; `PolicyToolAuditStoreTests.swift:297,603,640` kept. |
| U6 | H2 feed / replica / promotion | Project by `AgentEventBatch.seq` with the cursor in the same Memoshi transaction. Replicas via `ReplicaStorage.seed/ingest` fed by MLS application messages. Hand-over via `promote`. Delete the `S2StoreAdapter` synthetic replication and the conversation-data use of `MemoshiDevice.ConversationStore`. Migration 14 (feed cursor). | Each commit is projected exactly once across reconnects (re-run the 1,000-cycle replay proof on Pi seq). Stale branch → `CommitIngestRefused.staleEpoch`, which becomes a side thread (E19). 100 hand-overs with no two writers. S2.5/S2.7/S2.10 rows. **C21 copied-intent takeover is blocked by gap 3.** | `S2StoreAdapterTests.swift:21,57` rewritten.<br>`DeviceNodeTests.swift:37,180` (`staleWritesRejected`, `noTwoWriters`) re-targeted to Pi commits.<br>`DeviceDurabilityTests` / `DeviceFrameCapacityRegressionTests` re-run with snapshot sizes. |
| U7 | H3 guarded daemon files | **Only after `p07-guarded-files` is in the tag.** `serve()` → `init(transport:files: GuardedDaemonFileService(...))` with the Memoshi policy. | The S4 105-case matrix (`evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s4-retained-case-reconciliation.json`) re-run: hard-link, symlink and replacement-race cases through `RemoteExecutionEnv` file ops return `SYMLINK`/`NOT_REGULAR`/`EACCES` with no outside inode reached. Upstream env file cases pass against a real daemon with the injected service. | `SandboxComputerTests.swift:15,151,292,356` alias probes rewritten to expect wire refusals; `WorkingCopyAdmissionTests`, `WorkingCopyRaceRegressionTests` kept. |
| U8 | H4 explicit engine | Drop `wasmLoader`; add explicit `engine`; the workload CLI selects the engine. | `CodeModeKillResumeTests.swift:11,86` and `RuntimeToolOriginTests.swift:13,182,221` pass on both engines. D98 W1/W2/W3 run in Release on both (Mac diagnostics, labeled). Pin-era durable Code Mode journals replay or are refused explicitly (module version 2). | Same tests parameterized by engine. |
| U9 | Apple host (optional) | `BotRuntime` / `BotHandle` composition replaces `RuntimeAdapter` composition. `ContinuedProcessingHost` replaces `ContinuedTurnProcessing`. | iOS: expiry parks or closes before suspend and releases the writer. A foreground resume continues the same submission. Simulator reports `simulatorUnavailable`; device rows are held. | `InProcessChatModelTests.swift:50` adapt; add host tests (none exist for `ContinuedTurnProcessing`). |

Dependency order: U1 → U2 → U3 → U5 → U6. U4 needs U3 and gap 2. U7 and U8 are independent after U1. U9 is last.

## 3. Preconditions to request from the SDK owner

Through the authorized request pointer (`SDK:docs/requests/2026-11-02-memoshi-consumer-handoff.md`). Writing there needs the user's per-write authorization (handoff §7).

| # | Request | Blocks |
|---|---|---|
| P1 | A `slice-N` tag on a commit containing at least H0, H1 and the H2 local fence (D90; gate `:9`). | **Adoption** (all units) |
| P2 | Source-qualified CI at that commit **with published evidence**. 3c6ff35 predates the pin, and the quota block (`VERIFICATION.md:5,1561`) must be resolved by the user/owner, not worked around. Also current full runs green or failures listed in Known failures (`VERIFICATION.md:1929+`). Specifically: login-shell escaped-group ×2, `ContinuedProcessingLifecycleTests` ×2, `HarnessTelemetryTests.inheritsTaskTraces`, `HarnessNestedToolsRestartTests.keepsUnsafeCallerNestedCalls`. | **Adoption**. `keepsUnsafeCallerNestedCalls` blocks U3; ContinuedProcessing blocks U9. |
| P3 | A consumer note and migration notes at the tag:<br>(a) breaking-change list as in `CHANGES-FOR-CONSUMERS.md`;<br>(b) fenced-store downgrade behavior;<br>(c) whether pin-era `pi.tool` v1 tasks cut off mid-call surface as `InterruptedStep` after the v2 migration, or are lost (this decides whether U3 may drop Memoshi's held rows);<br>(d) replay of pin-era Code Mode journals under module version 2;<br>(e) whether sandbox `timeoutMs` bounds durable scripts (decides `CodeModeDeadline`). | **Adoption** of U1/U3/U8 |
| P4 | API stability: which surfaces are frozen for the gate pin. Today H1/H2/Apple host are S/W, and the file being edited live is `ToolAPI.swift`. Also a dated plan for the v1.5.0 removals (`taskGraph`, `DocumentState`, watches, `Storage.commit`, E17 re-base). | **Adoption** of U6/U9; churn risk for all |
| G1 | Credential-kill recovery (`VERIFICATION.md:1765,1953`: signed credential kills unproven). | **Qualification only.** Memoshi composes its own credentials; it would block U9 qualification if `BotRuntime` credentials are used. |
| G2 | Nested-result retirement. **Still observed**: `nestedCallDoc` is task-scoped (`SDK:Sources/PiDurable/Harness/ToolTask.swift:158`), and nested settle writes the full result into the parent's doc with receipt `.nested` (`ToolTask.swift:882-895`). That is the same shape as the pin (handoff §2.4). | **Qualification** (S1 all-call audit/recovery) and the **U4** deletion. Does not block the pin move: Memoshi keeps its fail-closed capture. |
| G3 | H2 independent copied-intent takeover. No engine API imports an intent copied from another device into a different store. Only `ToolIntent`, `ToolExecutionGate` and the copied-store epoch+1 rule exist (sdk-api-map §H2). | **Qualification** (S2/C21) and U6's takeover row. Does not block U5. |
| G4 | Physical file protection. iOS sets `.completeUntilFirstUserAuthentication` (`StoreAccess.swift:144-150`), unverifiable on the simulator, with device qualification held (`VERIFICATION.md:172-174`). Guarded daemon writes set no class. | **Qualification only** (iOS device). Mac adoption is unaffected [INFERENCE: the class is iOS-only]. |
| G5 | H3 merged into the tagged line (branch `p07-guarded-files` only). | **U7** and S4 qualification |
| G6 | H4 device/Release measurements (held) and the committed default flip. | **Qualification** (D89/S1.18). Not U8 dev adoption. |

## 4. Conflicts with accepted decisions

None of these requires amending a decision. Each is a constraint on how Memoshi consumes the SDK.

1. **D89, "parity before default / device evidence before shipping".** The SDK flipped `CodemodeEngine.default` to `.wasm2c`. This is uncommitted (`Engine.swift:17`), and its M4 helper "retains its budget misses" (`VERIFICATION.md:1950`). Memoshi must select the engine explicitly and must not count the SDK default as D89/D98 qualification. The current `wasmLoader` usage would silently keep WasmKit.
2. **D98 memory ceiling.** `BotCodeModeLimits.platformDefault` is unbounded on macOS (`BotRuntime.swift:310-340`). Memoshi must pass explicit limits. The SDK's 256 MiB per-VM iOS limit is separate from D98's 100,000,000-byte incremental ceiling.
3. **D79 backups.** `BotStoreBackup.copies` and `beforeMigration` backups are host-placed. They must sit inside the backup-excluded container (`MobileEngineHost.swift:94-104`); the SDK does not enforce this.
4. **D83/D79 hold scope.** The SDK hold is **store-wide** (`Scheduler.swift:512`; doc: "everything else in the store … waits"). This equals "whole conversation" only under D74's one-store-per-conversation layout, which Memoshi uses (`pi/<conversation>.sqlite`). Child conversations created in the same store hold too, which is consistent with D83. Memoshi's working-copy-export hold is invisible to the SDK and stays Memoshi-owned.
5. **Handoff §2.1.1 wait kinds.** There are no `outcome_check` or `resume` wait kinds. This is a mapping difference (§1 H1), not a conflict.
6. **D73 forwarded answers.** `BotRun.answer` refuses waits outside its run (`answer_outside_run`, `BotHandle.swift:85-117`). Cross-run and forwarded answers must use `Harness.settle` directly. This is a risk for U9, not for U2.
7. **D73 provisional leases vs CloudKit.** `CloudKitLeaseAuthority` refuses provisional grants (`CloudKitLeaseAuthority.swift:150-151`). The SDK models provisional as an authority answer, so Memoshi's adapter must merge the direct-hand-over record. This is a design obligation, not a conflict.
8. **D90, "S1 counts only on `slice-N`".** The post-gate v1.5.0 removals mean results from a gate-pin slice must be re-qualified after the second cutover. That is consistent with D90, but it is a schedule risk.

## 5. Immediate actions (no repository edits)

- **None of U1–U9 can start now.** Each needs P1–P3, which do not exist.
- After the canonical CI run finishes, the only reachable step is to file P1–P4 and G2/G3 with the SDK owner. That requires the user's authorization for an SDK request write.
- Recheck run 08's outcome (`/Volumes/PiSwiftVerify-99a45b9ccc5e/evidence/main-native-full-current-08/macos/status`).
