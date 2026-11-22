# MemoshiQualification: non-shipping P0-15, S1, S2 and S4-T1 harnesses

This target and `memoshi-qualification` provide the P0-15 Mac `chaos` driver/effect ledger,
the finite S1 multi-conversation/private-pipe scenario, the S2 loopback device/authority
prototype and the S4-T1 raw Seatbelt matrix (`s4-matrix`). They are **qualification code
only**, not a shipping runtime or a gate verdict.
Neither `Memoshi.app` nor `memoshid` links this target. Normal app/helper composition still
supplies no tools, MCP, Code Mode, environments or subagents; only the iOS app's Debug-only
`DevelopmentComposition` adds development tools, and only when a launch argument asks for them. The Pi_Swift consumer pin is the
tag `slice-2`, `ce1728ef8236d95a8b94b50a856670c48ad85365` (D134); the sibling SDK is read-only.

## Chaos: runtime host, not the memoshid protocol

The `chaos` command drives the **runtime-host level**: a child process composes the real
`MemoshiStore` and `RuntimeAdapter`, and through it PiDurable at the pinned Pi_Swift candidate,
exactly as `memoshid --development-chat` does, plus one trusted test tool. It does **not** go
through `memoshid`'s authenticated Unix-socket protocol, `MemoshiClient` or the app: that path
requires genuinely signed app/helper peers (same-FD Apple anchor, team and hardened-runtime
checks, no development bypass), which a SwiftPM-built harness cannot be.

Consequently `chaos` does not exercise client reconnect/replay from `after`, the daemon's
`cards.respond` RPC routing, launchd/SMAppService restart or the app's Waiting for You surface.
Approvals are answered through `RuntimeAdapter.respondToCard`, the same runtime method the
daemon's `cards.respond` handler calls, with `actor = user`. The `s1` command below adds real
production JSON-RPC codec/typed-shape coverage over private pipes, **not** authenticated Unix
IPC or `RPCSession` coverage. A separate
[genuinely signed text-only smoke](../../../../../evidence/2026-11-03-memoshi-wave3-integration/native/signed-protocol-final/result.json)
observed same-FD authentication/hello/Unix WebSocket/RPCSession, five focused live conversations,
one owned helper SIGKILL, automatic reconnect, five original receipts and isolated settled
histories. That normal `.none` helper run is not produced by either command here and does not
exercise signed `cards.respond`, approval-over-kill, nested retirement, the full chaos matrix
or SMAppService. It is not release/reference qualification.

## Chaos pieces

| Piece | What it does |
|---|---|
| `EffectLedger*.swift` | Loopback-only HTTP ledger on 127.0.0.1 with an OS-chosen port written to `ledger.port`. `POST /v1/effects` records an effect once per idempotency key (`201 recorded`), deduplicates a same-key same-body retry (`200 replayed`) and refuses a same-key different-body attempt (`409 conflict`). Every attempt is an fsync'd JSONL line in `effects.jsonl` before the reply; a torn final line is truncated on reopen. `GET /v1/summary` and `ledger-summary` report attempts, effects, replays, conflicts and **duplicates** (effects beyond the first for one run/step). Runs as its own process; each run registers the SHA-256 of its bearer token on the ledger's stdin; stdin EOF stops it. |
| `CanarySecrets.swift` | Per-run `mqcanary_…` secrets (40 random base62 characters plus `/` and `+`). The scanner reads files as raw bytes (SQLite, WAL/SHM, JSONL, logs) and path names, without following symlinks, for raw, JSON-escaped (`\/`, `\u00XX`), percent-encoded (reserved-only and every byte, both hex cases), base64/base64url (all three byte alignments) and hex forms, and reports path, encoding and offset. Zero hits required. |
| `QualificationProvider.swift` | The controlled external model (default): a loopback OpenAI-compatible server. Requests still go through PiAI's real HTTP client and Memoshi's per-use credential checks; it requires the run's **bearer canary**. Without a tool result it streams three deltas and calls `qualification_effect`; with one it streams the final answer. In a `subagent` run it first delegates and calls `qualification_effect` only after the child's answer (see **Subagent point** below). |
| `RealModelProxy.swift` | Real-model mode: a loopback proxy in front of a local OpenAI-compatible server (local Ollama). It requires the run's **bearer canary** on every request and never forwards it, lists and serves only the selected model, and relays streams as they arrive. A streaming kill arms a one-shot pause: the next reply that streams text stops being relayed at its N-th text delta, or before its first other chunk (tool call, reasoning or finish), the upstream request is canceled, and the response stays open until the killed host's socket closes. |
| `QualificationHost.swift` | The host child (`memoshi-qualification host`). Configuration, including the bearer canary, arrives on stdin only. The tool is a T3 `net.fetch` (asks in Ask first), declared replay-safe because it sends an idempotency key the ledger deduplicates (04-architecture §4.11). The key is `mq1:<run>:<RuntimeToolInvocation.effectKey>:<callID>`, i.e. the durable `<conversation>:<Pi task>` identity plus the call ID. The ledger bearer is the **synthetic-file canary**, read from the run's `secrets/ledger-token` on every call. |
| `ChaosDriver.swift`, `ChaosPlan.swift`, `ChaosReport.swift` | The driver: seeded plan, process lifecycle, verification and reports. |

## Running chaos

```sh
swift build --package-path Packages/MemoshiDaemon --product memoshi-qualification
Packages/MemoshiDaemon/.build/debug/memoshi-qualification chaos \
  --runs 5 --seed 20261103 --work-dir /tmp/mq-chaos.XXXX --output-dir ../evidence/<topic>
```

Options: `--points streaming,tool-executing,approval-waiting,effect-posted,idle,subagent,compaction`
(without `--points` a batch draws the five points the recorded S1.13 batches used,
`streaming,tool-executing,approval-waiting,effect-posted,idle`, in that order, and prints why it
leaves out `subagent` and `compaction`; those two run only when `--points` names them, and
naming `compaction` refuses that run until the runtime starts a compaction step; `plan.json`
records the resolved selection as `points`. An S1.13 gate batch names its points explicitly:
`--points streaming,tool-executing,approval-waiting,effect-posted,idle`),
`--kills-per-run K` (default 1; repeated kills at the same point, each starting a new host
life), `--startup discover-then-resume|daemon` (below), `--terminal-timeout SECONDS` (default 90:
how long a life may take to reach its kill point, or the final life a terminal turn),
`--upstream URL --upstream-model ID` (real-model mode, below) and `--keep-run-dirs`. Without
`--output-dir` the report goes to `<work>/report`; cleanup retains that directory.
The exit status is 0 only when every run passed, required logs and reports were retained,
all required scans completed without hits, the ledger stopped normally with a journal
matching its live summary, and owned work cleanup succeeded. Startup, capture, retention,
publication and cleanup errors remain batch failures even when individual runs passed.

**Startup order.** `discover-then-resume` (default) runs `start → modelsList → resume`, the
order the runtime recovery tests use. `daemon` runs `start → resume → modelsList`, memoshid's
order, where a client lists models only after it connects. Since 2026-11-03
`RuntimeAdapter.resume()` first discovers a configured provider whose model a thread's
unfinished turns selected but the registry lacks; if it stays unknown (for example a keyed local
provider before the app's Keychain host connects) the thread stays paused, counted in
`RuntimeStatus.awaitingModels`, until a later `modelsList()`. The harness's keyless loopback
provider exercises only the discovered case, in both orders.

**Real-model mode.** `--upstream http://127.0.0.1:11434/v1 --upstream-model qwen3:0.6b` puts
`RealModelProxy` in front of that loopback server and selects `local/<model>` for every run. The
driver never starts, stops or pulls the server or its models: start `ollama serve` yourself only
if it is not already running, and stop what you started. A real model words its own answer, so
the final-answer check becomes "nonempty text with stop reason `stop`"; every other check is
unchanged, including exactly one approval, tool completion and ledger effect. A real model may
skip or repeat the tool call, which fails that run honestly. Use a longer `--terminal-timeout`
for a slow model.

**Subagent point.** A `subagent` run composes the real task-owned foreground delegation
(`RuntimeExtensionComposition(subagents:)` with `RuntimeSubagentConfiguration(foreground: true,
persistentBackground: false, childTools: [])`): the child gets no tools and no background form,
so it can never run the parent's effect. The scripted model delegates with the call ID
`mq-<run>-subagent` and the task "subagent-task: reply with the single word done and call no
tool (run <run>)"; the child answers `done`. Only that answer as the subagent result
(PiDurable's `<harness>` replay notes removed) makes the model call `qualification_effect`; any
other subagent result is answered without the effect and counted as a mismatch. With the
scripted model the kill waits only for the held child stream; a real model's child cannot be
held, so there the window is a second live run. Each window is recorded in the run result's
`subagentKillWindows` (`held-child-stream` or `second-live-run`), beside `subagentCompletions`
and `childTaskStatuses`. Since 2026-11-18 a `subagent` run fails unless it shows exactly one ok
delegation and one child task that ended `done` with no tools, no mismatched subagent result
and, with the scripted model, exactly kills + 1 child requests (one held per kill and one
answered); a run at any other point must spawn no child. The 2026-11-16 scripted batches
([harness items](../../../../../evidence/2026-11-16-memoshi-harness-items/README.md)) predate
these checks and never checked the child. Four real-model `--points subagent` batches ran on
2026-11-19 (`qwen3:8b`, a loaded development Mac; none is an S1 gate batch; records under
`../evidence/2026-11-19-memoshi-real-subagent-kill*`, outside git): 5 of 5 passed (seed
20261119, all `second-live-run` windows, one child `done` each, 0 duplicates, scan clean); 6 of
20 (seed 20261120; the other 14 failed, 13 of them once the model was unavailable, and the harness
counts them as failures with an `invalid:` cause, not in a separate count); 15 of 20 by the
driver's output (seed 20261121; runs 16–20 and the reports were lost to a full disk); and a
batch stopped after 5 runs, 3 passed and 2 unclassified `timeout waiting for host inspect`
failures, with no files kept. The status is kept in
[remaining-work §1.3](../../../../docs/plan/remaining-work.md#13-runs-owed-that-need-no-owner-input).

The work directory must be absent or empty. An explicit output directory must be absent
and disjoint from work; only the default `<work>/report` may be nested inside work.
Canonical identities reject ancestor aliases that point into an occupied output. Normal
temporary-directory aliases remain valid. Work and output are also refused inside
`~/Library/Application Support/Memoshi`, `…/Memoshi Development`, `~/Documents/Memoshi-Plan` or
`/private/tmp/memoshi-native-review`. Refusal happens before child startup and preserves
existing files. Each run gets a synthetic `HOME`, `TMPDIR`, store and secrets under
`<work>/runs/<run>`. Cleanup checks admitted identities, removes only owned paths, and
preserves borrowed empty work and retained output. This is not hostile same-user
descriptor-relative traversal protection. The driver signals only processes it spawned.

Every consecutive block of as many runs as there are selected points covers each selected
point once, in seeded order (with the five default points, a 50-run batch gives each ten
runs); each run draws its kill
delay (0–250 ms) and streaming pause (1–3 deltas) from the same seed. Canaries come from the
system generator, never the seed. A streaming kill waits until the model holds a reply open and
the host has published a text delta, answering approvals meanwhile (a real model may call the
tool before it streams text).

## Chaos per-run checks

1. Each deliberate kill ends the host with signal 9; the final life closes normally with exit 0.
2. Every restarted life resubmits the original `chats.send` parameters and gets the **original
   receipt** (`messageId`, `taskId`, `writtenSeq`, `replayed: true`); the stored turn keeps it.
3. The turn and task end `done`, with exactly the original user message, exactly one bot message
   that is the final answer and the last message, unique message IDs and no live run, recovery
   hold or queued input.
4. Exactly one approval and one card, decided `allowed` by `user`; for approval-waiting kills,
   every restart shows the **same** pending approval ID and card (reattached), never two.
5. Nothing ran before a decision: no `tool_executing` event and no recorded effect while a
   decision was pending.
6. Exactly one durable `tool.completed` fact (ok) and exactly one ledger effect for the run, with
   zero duplicates and conflicts, under a single idempotency key.
7. Zero canary hits across the run's directories and the ledger (only `secrets/ledger-token`, the
   declared source file, is excluded), and later across every output file; zero provider
   requests without the bearer canary.

Outputs: `plan.json`, `results.jsonl` (one line per run), `results.md` (the S1 table, rendered
after the output scan with the batch verdict, ledger exit, journal consistency, cleanup state
and every batch failure known at that point; its bytes are scanned before publication),
`summary.json` (batch totals, ledger live/journal summaries, exits, cleanup and `failures`),
`output-canary-scan.json` (every output file scanned for every run's canaries),
`ledger-effects.jsonl` (the journal copy) and each host life's stdout/stderr log under `runs/`.

The standalone `scan` subcommand exits 0 only for zero hits over at least one file it read and
2 for any hit. A missing root, a directory that cannot be listed or a scan that read no file
exits 1; a canary line without a value is a usage error (64). Every subcommand refuses an
option it does not know, and never takes a token starting with `--` as an option's value.

Required stdout log write or close failure does not stop pipe drainage or decoded-line
delivery. It fails `drainOutput` after stdout EOF, owned-handle close and `onEnd`.
Child exit and capture success are separate observations. Direct child stderr writes use
the existing inherited file descriptor; their write failures are not independently
observable by the parent's stdout reader.

## S1: typed private-pipe multi-conversation scenario

[`S1Driver`](S1Driver.swift) spawns an owned `s1-host` with the actual Store/RuntimeAdapter,
PiDurable/PiAI and a controlled loopback provider. [`S1Host`](S1Host.swift) decodes production
`JSONRPCCodec` requests and encodes the real typed method results/events over driver-owned
stdin/stdout. The first private-pipe line carries the synthetic bearer, never argv, environment
or retained logs. Measurement/control messages are visibly separate from production method
results; this is a qualification carrier, not another production transport or a signing bypass.
Tools/extensions/environment are absent. (The `chaos` host's `subagent` runs are described
under **Subagent point** above.)

From the repository root, with fresh, disjoint, **absent** work/output directories whose parents
already exist:

```sh
swift build --package-path Packages/MemoshiDaemon --product memoshi-qualification
Packages/MemoshiDaemon/.build/debug/memoshi-qualification s1 \
  --work-dir /tmp/mq-s1-20261103 \
  --output-dir ../evidence/mq-s1-20261103 \
  --open-samples 3 --timeout-seconds 300
```

`--open-samples` is 1…30 (default 3); it repeats opening each of ten actual conversation stores,
not thirty independent hosts per conversation. `--timeout-seconds` is 1…3600 (default 300).
[`QualificationPaths`](QualificationPaths.swift) rejects existing roots, overlap and case aliases
before exclusive creation; the driver removes only its newly owned synthetic work root and
retains output. It only signals children it spawned and closes its own controlled provider.

**Scenario and measurement boundaries:**

| Exercised boundary | What it means, and does not mean |
|---|---|
| Assistant + three bot Chats + a project-less Session | Five real app conversations/Pi stores, independent histories and original send receipts. One owned SIGKILL interrupts all five streaming turns; reopen/resubmission must preserve each original user/receipt and settle one authoritative answer. This is not five independent kill runs. |
| Ten open conversations / four streaming | Nine home Chats (Assistant plus eight bots) and one Session. `TASK_VM_INFO.phys_footprint` is sampled inside the owned runtime-host PID while four real scripted SSE streams remain held and emit more text during sampling. Driver/provider processes are excluded; shared caches, allocator retention and SQLite are included, so incremental process bytes are not exclusive per-Harness allocation. |
| Open + resume + history | Host clock around the first `runtime.history` of a settled persisted conversation in a fresh process. Includes ownership, Pi SQLite/Harness activation and bounded history; excludes process startup, model discovery, JSON and pipe transit. This `s1` scenario does not exercise ten-minute expiry or live deletion; the separate `lifecycle` command below covers those paths. |
| Eight simultaneous sends / commits under eight streams | Send time ends at durable admission, not final answer. The commit series alternates real retention-setting writes while all eight streams continue: Store actor/SQLite transaction/event-publication time, not isolated SQLite COMMIT syscall time or Pi's internal commit latency. |
| Event bytes per settled turn | Exact stored payload JSON and canonical replay-envelope bytes grouped by task at a fixed replay head. No duplicate transcript or durable delta text; excludes shared SQLite B-tree/index/WAL allocation and lifecycle facts not bound to a turn. |
| Credential/canary checks | The owned provider requires the bearer on each actual HTTP attempt. Raw scanner checks work files before deletion and retained output after logs close; it does not inspect compressed encodings or system-wide logs. No real cloud provider/Keychain/paid call is exercised. |

Outputs include `s1-measurements.json` (`evidenceClass`, `protocolBoundary`, `referenceQualification`,
`passedInvariants`, `checks`, `failures`, distributions and explicit boundaries), raw per-series
`samples/*.csv`, `samples/summary.csv`, `samples/event-bytes-per-turn.csv`, `event-log.jsonl`,
`original-sends-and-receipts.json`, `settled-turns.json`, conversation/history snapshots and logs.
[`S1Measurements`](S1Measurements.swift) owns exact clock/byte/sample definitions.

The [retained 2026-11-03 run](../../../../../evidence/2026-11-03-memoshi-wave3-integration/s1/s1-measurements.json)
reports `passedInvariants: true`, `referenceQualification: false`, `failures: []`. It has 17
unique turns and 22 provider endpoint attempts, including the five interrupted attempts; the
provider field named `completions` counts endpoint attempts, **not 22 settled answers**. See
original receipts/settled-turns for authoritative logical counts. This run is scripted
development evidence, not a real-model, `slice-N`, reference-budget or new signed-protocol pass.
It does not cover hello, same-FD peer authentication, Unix WebSocket, `RPCSession`
subscription/focus/backpressure, the app's applied-receipt cursor or SMAppService.

## Default-idle and live Session lifecycle

`lifecycle` uses three real Pi SQLite stores/Harnesses in one owned runtime host. It keeps
the Assistant's Chat in use while a separate Session reaches the unchanged **600-second**
idle limit; no accelerated clock or test-only idle configuration is used.

```sh
swift build --package-path Packages/MemoshiDaemon --product memoshi-qualification
Packages/MemoshiDaemon/.build/debug/memoshi-qualification lifecycle \
  --work-dir /private/tmp/memoshi-lifecycle-work-20261104 \
  --output-dir /private/tmp/memoshi-lifecycle-report-20261104
```

Both paths must be fresh and absent. As for the other qualification commands,
`MEMOSHI_BUILD_ROOT` can redirect build artifacts without changing these runtime paths.
The driver calls the implemented `sessions.delete`, `trash.list`, `trash.restore` and
`trash.empty` runtime methods: deletion closes only the selected idle Session's Harness,
releases its ownership and retains its original Pi file in 30-day local Trash; explicit
purge removes only the frozen selected stores. Restore keeps conversation identity, and
a previously committed delete/purge request returns its original historical receipt
without reapplying the mutation. The bot's endless home Chat is not independently deleted.

The finite command writes `lifecycle.json`, including actual monotonic idle observations,
the host PID, SDK candidate, schema, invariant results and failure list, then closes its
runtime and removes only its owned synthetic work root. This is **runtime-host development
evidence**, not authenticated memoshid/GUI/SMAppService, reference-hardware or `slice-N`
qualification. The [2026-11-04 actual receipt](../../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/lifecycle-live-0711c0fa/lifecycle.json)
passed: the idle Session closed after 601.068393750 seconds, the unrelated Chat stayed
open, and deletion/restore/purge preserved original receipts with the same host PID.
The unchanged candidate and schema are recorded in the receipt; production composition
was not widened.

## Real-model child fixture

Core's nonshipping `memoshi-runtime-fixture subagent-host` can select an explicitly owned
loopback model without aliasing it to the scripted provider's `contract-model`.
Build its `memoshi-runtime-fixture` product from `Packages/MemoshiCore`; the command's
`--data`, `--provider`, `--ledger` and original `--request-id` are required. The ledger
must be an existing owned file. Use isolated private HOME/TMPDIR and only processes/data
owned by the qualification run.

- `--model PROVIDER/MODEL` selects the exact discovered model; omitted means the existing
  scripted `local/contract-model`. The exercised real choice was `local/qwen3:0.6b`.
- `--prompt TEXT` supplies the explicit synthetic delegation instruction.
- `--form foreground|background|both` registers only the selected delegation form;
  omitted means both, preserving the controlled fixture.
- `--stop-active-child` waits until the owned checkpoint callback actually starts, sends the
  real task-targeted UI abort, and waits for executor drainage before checking zero effects.
- `--checkpoint-delay-ms 0...60000` controls the cooperative wait. Active-child Stop requires
  a nonzero delay and defaults to 15000 ms. The two Stop modes are mutually exclusive.
- `--configure` configures the first owned Store. On reopen retain the same original
  send/model/prompt/request identity and inspect its replayed receipt; do not replace it
  with a new task. No arbitrary model/key fallback or automatic retry is supplied.

The development [foreground receipt](../../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/local-model-foreground-child.json)
and [background receipt](../../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/local-model-background-child.json)
show actual local-model child execution, preserved parent identity/history and one real
checkpoint invocation each. Background completion after normal parent completion is
**not** parent-Stop survival. Neither receipt qualifies kill/resume, cancellation propagation,
native attachment/active-child Stop or physical iOS.

The [retained before-fix negative](../../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/local-model-active-child-stop-before-fix.json)
recorded a canceled child but one late checkpoint after executor drainage. After binding
Sendable host work with `RuntimeToolInvocation.runCancellable`, a [fresh same-prompt real-model run](../../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/local-model-active-child-stop-after.json)
exited 0: callback entered, child Stop requested, child canceled, root done, executor drained
and no checkpoint effect. This is one development-Mac Stop probe, not a latency series,
native active attachment, real-model kill/resume or physical-device qualification.

The separate [five-point real-model chaos run](../../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/local-model-chaos-five-summary.json)
passed **3/5**, not five: approval-waiting and idle cases ended with empty final answers;
idle shutdown also timed out. Duplicate effects and retained-output canary hits were zero.
The failures remain failures; this is not the full 50-kill matrix or S1 acceptance.


## S2: durable device and authority qualification prototype

[`S2Driver`](S2Driver.swift) owns one loopback relay and three Mac processes labelled Mac,
iPhone and iPad. Each `s2-device` has a real MemoshiStore and `MemoshiDevice.DeviceNode`;
these labels are **not physical devices or an iOS background run**. The prototype exercises
Noise pairing/confirmation and encrypted carriers around genuine RFC 9420 MLS packets,
direct/relay links, per-conversation fenced app-store commits, replication/forwarding,
handover/expiry, durable store-and-forward, revocation and normal OS-process reopen with the
original identity/native checkpoint/cursors/forwarding receipt. Optional `--bonjour` uses
actual Network.framework advertisement, discovery and authenticated Noise connections.
It does not replicate Pi stores, execute models/tools/effects or satisfy the production
device-layer catalog.

**Run recipes are not measurements.** The [current native-wire development scorecard](../../../../docs/research/spikes/2026-11-04-s2-devices-draft.md)
records 127 component tests and the separate actual `--quick` process control: 32.16 s,
670 old-runner refusals and 86 successor commits in the nonvacuous expiry window, with
unchanged timing/counts on private SSD data. Initial identity-directory and external-image
lease-loss failures remain linked there. This did not select Bonjour, real QR expiry or load,
and it did not use physical devices or Pi replicas. Carry the already secured full local
pairing/handover/load run forward within its original scope, not as current-wire/deployed capacity.

```sh
# Reduced scenario counts; four short authority-load profiles if the scenarios reach them.
Packages/MemoshiDaemon/.build/debug/memoshi-qualification s2 \
  --work-dir /tmp/mq-s2-quick-20261103 \
  --output-dir ../evidence/mq-s2-quick-20261103 --quick --load

# Full counts, durable authority load and a selected real 301-second QR-expiry check.
Packages/MemoshiDaemon/.build/debug/memoshi-qualification s2 \
  --work-dir /tmp/mq-s2-full-durable-20261103 \
  --output-dir ../evidence/mq-s2-full-durable-20261103 --load --real-expiry

# Explicit current-host Bonjour opt-in; may require the host's local-network permission.
Packages/MemoshiDaemon/.build/debug/memoshi-qualification s2 \
  --work-dir /tmp/mq-s2-bonjour-20261103 \
  --output-dir ../evidence/mq-s2-bonjour-20261103 --quick --bonjour

swift test --package-path Packages/MemoshiIPC --filter DeviceNativeRecoveryTests
swift test --package-path Packages/MemoshiIPC --filter DeviceDurabilityTests
swift test --package-path Packages/MemoshiIPC --filter DeviceTransportRecoveryTests
swift test --package-path Packages/MemoshiIPC --filter DeviceSecurityTransitionTests
```

The same absent/disjoint-root rules apply. `--quick` reduces counts and steady load duration;
`--real-expiry` actually waits until 301 seconds after issuing an unused QR invitation, rather
than claiming five-minute expiry from a shorter run. `--load` runs only after the preceding
device scenarios complete; a scenario failure can leave the load matrix unmeasured.
The report records the real-expiry, Bonjour and load selections explicitly. Omitting a flag is
not proof of that scenario. The retained pre-journal full run below omitted `--real-expiry`.

Checks added on 2026-11-13 (runs recorded before that date were not held to them):

- `s2-measurements.json` carries the verdict as `passed`, every disqualifying reason in
  `failures` and informational observations in `notes` (formerly one mixed `findings` list).
  Work cleanup precedes the report, so the verdict covers it.
- The two-writer audits fail when they saw too little to prove anything. In all three
  histories: no commit, or a commit without an epoch. In the hand-over Chat and in the expiry
  conversation: fewer than two writing devices or fewer than two epochs (for expiry, the frozen
  runner's commits before a freeze and its successor's commits after the take-over). The
  hand-over Session is held by the Mac throughout, so one writer and one epoch are what a
  correct run shows there; its audit requires its commits only. The report states each
  requirement beside its result (`audit.<label>.requiredWriters`, `.requiredEpochs`).
- A relay summary whose `duplicateGrants` is not 0 fails the batch. Since 2026-11-20 a relay
  that keeps no grant log (the load relays, `--no-grant-log`) reports no `grants` and no
  `duplicateGrants` at all, instead of a vacuous 0; the main relay must report both.
- Revocation is probed without the revoked node's own guards (`rawRelayHello`, `rawClaim`,
  `rawRenew`, `rawLink`). A revoked node knows it was removed (D133) and refuses these itself,
  so each probe bypasses it: `rawClaim` and `rawRenew` open a fresh relay connection with the
  revoked identity (`DeviceNode.attemptUnguardedAuthority`), and `rawLink` sends the real link
  handshake without the node's membership check (`attemptUnguardedLink`). The relay must refuse
  the hello and count that refusal, the peer must refuse the link handshake itself, and the main
  relay's grant log must hold no grant to the revoked device from the revocation on. A raw claim
  normally ends as `revoke.claim.connectionClosed`: the relay gives a revoked device no session
  (at most a reading of its removal, which ends on an authority request), so the authority never
  answers it. A timeout or an ended child is a batch error, never a refusal.
- `relay-journal.bin` labels control requests and replies with their own record kinds (4 and
  5); an unknown kind fails the journal.
- The revoked link counts as refused only for the peer's own `unknownPeer` handshake refusal.
  A handshake the peer gave up on at its ten-second deadline, or a message it refused on an
  existing link, is not that proof.
- Two D131 behaviours depend on races that no scenario forces, so they are reported and not
  required: `reservation.released` (reservations a writer cancelled because its reserve was
  refused or failed, or because its store refused at the fence) and
  `recovery.unacceptedOldEpochReported` (publications that still surfaced as held at a closed
  group epoch instead of being sealed again; expected 0).

Checks added on 2026-11-18 (`8b9b170`; first held in the full run
[s2-full-08](../../../../../evidence/2026-11-13-memoshi-canonical-s2/s2-full-08/README.md) on `a2ac274`):

- Each revoked probe's relay refusal is tied to that probe. The driver reads the relay's own
  refusal count with the relay's new `stats` command before and after the hello, the raw claim
  and the raw renewal, and requires exactly one new refusal for each probe that the relay
  refused; none, or more than one, is a batch error. An unanswered raw claim or renewal counts
  as `revoke.claim.connectionClosed` or `revoke.renew.connectionClosed` only then.
- A member control runs in the same batch: the witness's raw claim of a fresh conversation
  over the same raw path must be answered, granted and released (`rawClaimAndRelease`,
  `revoke.control.rawClaimGranted`), so an unanswered revoked request was refused, not lost on
  a path that answers nobody.
- The probe waits, bounded, until the revoked device reports `removedFromGroup`, with no fixed
  settle time.
- Only commits refused by the fence or by the device's own membership count as refused
  (`commitStream` and `writeLoop`: `writes.refused`, `expiry.oldRunner.concurrentRefused`,
  `revoke.write.refused`, with `revoke.write.refusedByFence` and `.refusedByMembership`). Any
  other write failure, such as a closed store or an unreachable lease authority, or a reply
  without its counts, fails the batch.
- The scenarios that run once are reported in their own object `once` (below).
- When a check runs, both of its outcomes are recorded, the one that did not happen as 0. A
  "must be 0" counter is therefore present only if its check ran.

### Qualified group size and the stress phase (D133)

Device groups are qualified at 8 devices. Every batch, quick or full, runs in two phases in the
same processes:

- **Qualified phase.** The Mac, the iPhone, the iPad and five probe devices: exactly 8 devices,
  read from the Mac's group and required (`group.qualified.devices`; any other size fails the
  batch). Links, lease operations, replica lag, forwarding, hand-overs, expiry take-over and
  store-and-forward run here. Their series and counters keep their plain names at the top
  level of `s2-measurements.json`, and `qualified.groupDevices` states the size: these are the
  qualified numbers. The top level also holds the batch-wide counters (group sizes, the content
  audit, reservation and recovery tallies) and the explicit zero counters of the checks that ran.
- **Stress phase.** The remaining probe devices are paired (45 in a full run, 4 with
  `--quick`), the QR checks run (replay, voided code, wrong key then right key, which adds one
  device; since 2026-11-18 they are recorded under `once`), and the same seven scenarios run again with the same counts: 54 devices in a full
  run, 13 with `--quick` (`group.stress.devices`). Everything this phase records carries the
  prefix `stress.`: the report puts it in the separate object `stress` (`groupDevices`,
  `series`, `counters`, and a `what` line that says it is not the qualified numbers), and its
  samples are `samples/stress.<series>.csv`. Every check on those scenarios applies to both
  phases; a forbidden outcome or a missing proof in the stress phase fails the batch too.

The stress phase starts after the qualified phase's commits in the same device processes, so
its numbers include whatever a longer history costs. Approvals, revocation, the late QR check
and the restart run once, after the stress phase, as they did in earlier full runs. Since
2026-11-18 they are reported in their own object `once` (recorded with the prefix `once.`;
`once.groupDevices`, read from `group.once.devices`; samples `samples/once.<series>.csv`), apart
from both phases. The
optional Bonjour scenario runs in the qualified phase only. Runs recorded before 2026-11-13
had one phase: a full run measured everything at about 54 devices and a quick run at 9.

### Revocation proof (D133)

The iPad is revoked while it holds something. Before the revocation it claims a conversation,
commits three changes that the Mac replicates, and has a renewal accepted
(`revoke.lease.held`, `revoke.renewals.beforeRevocation`). After it:

- **The relay** refuses a fresh hello signed by the revoked identity and counts that refusal
  itself (`revoke.relay.refused`, `relays.main.statistics.refusals`). Since 2026-11-18 the
  driver reads that count through the relay's `stats` command around each probe and requires
  one new refusal per refused probe. No request of a revoked device reaches the authority over
  the network: that is the product's rule, and this is its proof.
- **The authority itself is asked anyway.** On its private owner pipe the relay process puts
  the revoked device's claim of the conversation it held (with the right expected epoch, while
  that lease is expired and free, so a member's claim would be granted) and a renewal of its
  old lease to the run's real `RelayLeaseAuthority` as that sender, through `handle(_:from:)`,
  the entry the relay uses for a connection it has authenticated. Required: neither is
  answered, the authority counts exactly two refusals of a revoked sender, the lease record is
  unchanged, and the same path grants the Mac a fresh conversation, which shows the probe can
  see a grant (`revoke.authority.refused`). This proves the authority's own membership check.
  It does not prove that such a request can arrive (it cannot), and it is not a test of the
  wire between relay and authority; these two requests are not in the relay journal.
- **Renewals.** The revoked device's raw renewal is not accepted, and none of its `renewed`
  events was sent after the authority's removal time, watched for 2.5 s, longer than its 2 s
  renewal interval (`revoke.renew.refused`; `revoke.renew.accepted` is forbidden).
- **Writes.** Its commit attempts accept nothing, and only its fence or its membership may
  refuse them (any other failure is a batch error), none of its `committed` events is later than
  the revocation, and the two-writer audit over its and the Mac's commits of that conversation
  needs two writers and two epochs with no shared epoch (`revoke.write.*`, `audit.revoked.*`).
- **Successor.** The Mac takes the conversation over at exactly the next epoch and commits
  three changes there (`revoke.successor.accepted`, series `revoke.successor.takeOver`).
  `revoke.lease.expiredAtRemoval` reports whether the authority had already expired the lease
  when the device was removed.
- **Grant log.** The main relay's own log must hold a grant to the revoked device before the
  revocation, none from it on, and a later grant of that conversation to another device at the
  next epoch.

### Trusted host enrollment, not remote self-enrollment

[`S2RelayProcess`](S2RelayProcess.swift) accepts enrollment only through its owned parent's
private stdin control plane. The exact roster binds **device ID, signing key and agreement key**.
The main scenario enrolls the Mac as the initial active group member, phone/iPad as exact-key
candidates, and a pre-generated roster of fresh pairing-probe candidates. Only public identities
cross that private control plane; private probe identities stay in their owning process, and a
retry of the same QR code retains the same identity. Positive probes therefore measure new
confirmed members, not unauthorized self-enrollment or repeated pairing of an existing phone.
Candidates gain membership/lease authority only after authenticated pairing confirmation and an
active member's signed group transition. A remote relay hello may prove
an enrolled identity, never create/replace one, displace an existing connection by claiming its
ID or read another device's mailbox. Revocation fences membership and closes stale links.

Each load worker emits a public `loadEnrollment` roster to the parent; the parent sends
`enroll` over the relay's private pipe and only then sends `enrolled` to the worker's stdin.
Thus the low-level `s2-load --relay-port … --users … --active … --idle … --active-renew-ms …
--active-ttl-ms … --idle-renew-ms … --idle-ttl-ms … --moves … --duration-ms … --output …`
command is a **driver-owned child**, not a self-enrolling public load client. Its corresponding
`s2-relay --directory …` must be owned and explicitly enrolled by that control plane; do not
substitute a network hello or an arbitrary reachable relay for it.

### Reservation, catch-up and availability boundaries

The [`DeviceNode`](../../../MemoshiIPC/Sources/MemoshiDevice/DeviceNode.swift) checks authoritative
group membership, lease/epoch, committed sequence and exact payload digest on direct **and**
relay paths. A writer reserves the next sequence before its local commit, then publishes that
operation's exact digest. A successor synchronizes the authority's high-water and digests before
writing; conflicting duplicate sequences are refused. Reconnect initiates cursor catch-up
instead of relying only on old queued mailbox frames.

This prototype needs the **trusted relay reachable for ordinary peer authorization and
writes even over a direct link**. It is not an offline-direct/provisional-runner product.
Missing authoritative plaintext blocks takeover. A reservation ends without a publication in
two ways only (D131): its own writer cancels it when its store refused the commit at the
fence (a `FenceError`, which means nothing was written), before the store was called, or when
the reserve itself was refused or its reply was lost, and a
membership removal ends the removed device's pending reservations together with its leases.
A cancelled or ended operation can never be reserved or published again. Every other
unresolved reservation survives authority restart and blocks successors. A committed payload
checkpointed locally before uncertain publication is republished with the same operation
ID/digest after reopen, never rebuilt or renumbered. A store failure that is not a fence
refusal, or a crash between the actual store commit and that checkpoint, can still strand a
reservation: this is fail-closed availability loss, not synthetic store recovery.

The authority journals exact membership/enrolled keys/revocations, lease epochs/deadlines,
reservations, immutable publications and signed full sender feeds before success. Every
native seal—including Hello/control packets—has a durable predecessor ordinal; one
ciphertext is published before Noise emission and reused across recipients. Nonrecipients
advance the native ratchet but never dispatch another device's domain message. Membership
CAS closes signed prior-epoch prefixes and rolling digests; missing predecessors hold recovery
rather than dropping input. A seal the authority had not accepted when its group epoch closed
is retired, and its retained plaintext is sealed again for the new epoch under the same
operation ID (D131). A seal at or below the closed cutoff is never sealed again, and a
message whose only recipient left the group stays held.

Native ratchet state, authenticated plaintext receipt, routing, sender cursor and prefix
digest checkpoint together before exposure. Reopen never decrypts an already-consumed
packet twice. Transport receipt and durable application acknowledgement remain distinct;
the relay removes pending delivery only after the appropriate authenticated receipt.
Fresh execution authority is never restored merely by loading a local lease. A delayed
`lease.request` carries required `expectedEpoch`; receiver and inside-transfer checks
require the same unexpired, self-owned authority epoch.

`DeviceStateJournal` uses stable exclusive ownership around no-follow, owner-only state;
native latest-value checkpoints are atomically replaced under that stable lock. Group,
replica/publication and offline-approval state is encrypted with domain-separated
CryptoKit AES-GCM keys derived from the device identity. Missing one half of initialized
state fails closed. RFC 9420 exists in this implementation; malicious-owner rollback
resistance, secure erasure from flash/backups, encrypted Pi replication and a production
retention/compaction policy are not established. Finite journals remain bounded to 512 MiB.

`DeviceIdentityKeychain` provides explicit create/load in a provisioned `.devices` access
group: data-protection Keychain, non-synchronizable, after-first-unlock-this-device-only,
with no replacement or plaintext fallback. The inert native pairing review composes it
only after explicit Start, with encrypted unbound enrollment intent before factory return.
Normal runtime composition remains unchanged. No new provisioned OS-Keychain or Cloud
proof is implied; the process harness uses explicitly synthetic 0600 identity files.

Expiry takeover now requires real commits before each freeze and concurrent successor/old-runner
write attempts after resume: positive successor commits and old-runner refusals are mandatory,
and any old-runner commit fails the run. The old writer is quiescent at SIGSTOP, deliberately
separating expiry fencing from the unresolved-reservation availability case. A resumed old
runner whose store refuses a write that the authority's preflight had let through releases
that reservation (node event `reservationReleased`); the write still counts as a refusal. Since
2026-11-18 a hand-over or expiry write counts as refused only when the fence or the device's
membership refused it; any other write failure fails the batch.

`OfflineApprovalMailbox` preserves original ordinary allow-once/deny requests until the
original card deadline, expires them at the exact boundary, and retains a user-display notice
until acknowledged. The process scenario reopens this encrypted mailbox before and after real
elapsed expiry. Selection/notice persistence is measured, **not** application to a real runner's
Card/policy, device-owner authentication or native display; those integration gates remain.

`MemoshiDeviceApple` now implements CKSyncEngine state/fetch, encrypted mailboxes, signed
sender feeds, exporter-derived persistent-record AEAD and conditional atomic CloudKit
publication. Persistent reads use exported keys, not application-ratchet decryption.
All-feed publication and lease/membership fences share a group-head CAS, so contention
must be measured in O10. These are source implementations, not live CloudKit/APNs,
provisioning, physical-device or deployed-capacity qualification. Missing bound history,
account mismatch or unavailable exporter keys hold recovery; none resets authority.

Actual Pi transaction feeds, atomic replica ingest, copied-intent authority and
Harness-observer-aware promotion still require an accepted qualified SDK baseline.
The consumer pin is `slice-2` (`ce1728ef8236d95a8b94b50a856670c48ad85365`, D134); Memoshi
does not yet use its feed, replica or copied-intent APIs, and release/broader qualification holds remain. Requirements accepted in the SDK handoff
are not acceptance of an unqualified source candidate.

D75's native prototype uses pinned **mls-rs 0.57.0**
(`a1436f4a5433214ed62349e77835b57a0accdc42`), CryptoKit provider 0.11.0 and a Memoshi-owned
UniFFI 0.32.2 boundary; it does not import the upstream OpenSSL-only UniFFI wrapper.
`scripts/build-memoshi-mls.sh` built Mac/iOS/simulator arm64 payloads with exact-verified
Rust 1.97.0. Cargo.lock, generated Swift/header/module artifacts, the payload inventory and
119 retained dependency-license records now exist. The [provenance record](../../../MemoshiMLS/Native/PROVENANCE.json)
lists actual provider modifications and the unchanged upstream third-party-audit disclaimer.
Cipher suite 0x0001 and three retained epochs are prototype choices, not shipping adoption.

The [post-contract six-test native run](../../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-mls-six-tests-post-contract.txt)
exercised membership, revocation, checkpoint/replay and the 1,024-generation forward bound
with retained skipped keys after the actor-initializer signer `@Sendable` correction.
All six passed; this development Mac run is not reference-hardware qualification.
The [standalone public-API consumer](../../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-mls-public-client.json)
also compiled from a `MainActor` caller and exercised authenticated join, encrypted
in-memory checkpoint/reopen, replay rejection and removed-member rejection.
It does not prove disk crash atomicity, Keychain persistence, CloudKit or authority CAS.
The full IPC/Cloud/Pi layers still require separate evidence; neither native run sets O10
or lifts a gate.

Both app targets now have generated copy phases for the native licence inventory,
provenance and binding notice; mobile also carries the root `LICENSE`/`NOTICE`.
The [notice-admission CLI smoke](../../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-notice-admission.json)
accepted all 119 retained package records and refused missing text, a modified binding
notice and a link back into the source repository. That owned resource-tree smoke and
successful Xcode project generation are not an actual built/signed-bundle result.

### Load profiles, raw observations and counters

[`S2LoadProcess`](S2LoadProcess.swift) reserves each lease's scheduling/in-flight slot **before**
launching its renewal/move task. Queued and running work is counted and drained before the
final report (a drain timeout fails); a second overlapping operation cannot be scheduled for
that lease just because the first task has not started yet.

The current `--load` matrix has three worker processes per profile, with the following
**per-worker** declarations (not deployment capacity):

| Profile key | Users | Active / idle conversations per user | Active renew / TTL | Idle renew / wake TTL |
|---|---|---|---|---|
| `baseline-active-only` | 10 | 8 / 0 | 1,000 / 3,000 ms | 0 / 0 ms |
| `mix-idle-renewed` | 10 | 8 / 32 | 1,000 / 3,000 ms | 10,000 / 30,000 ms |
| `mix-idle-unleased` | 10 | 8 / 32 | 1,000 / 3,000 ms | 0 / 30,000 ms |
| `scaled-mix-idle-renewed` | 20 quick; 100 full | 8 / 32 | 1,000 / 3,000 ms | 10,000 / 30,000 ms |

The requested steady phase is 8 seconds with `--quick`, 60 seconds otherwise, after the initial
claim burst; each idle profile schedules two idle moves/wakes per user per cycle. In
`mix-idle-unleased`, zero means **no periodic idle renewal**: a wake still claims a finite
`idleTtlMs` lease and leaves it to expire. The retained profile key does not mean zero live
authority leases.

Each active/idle population rotates over Chat, Session, routine-lane and watch-lane lease
identities; reports retain actual total/active/idle kind counts rather than calling every key a
Chat. These are authority-load classifications, not implementations of routines or watches.
The current load authority uses the same synchronized durable journal as the main scenario;
the historical in-memory load result below must not be relabelled as durable capacity.

- `authorityOperations` counts actual steady-phase authority RPC attempts, including every
  release, claim, renewal and retry, even refusals/failures; it is not an estimate of two
  operations per move. Initial claim-burst timing/counts are reported separately.
- `operationsPerSecond` and `renewalsPerSecond` divide by actual `steadyPhaseSeconds`,
  including queued/running drain time, not the nominal requested interval.
- `periodicallyRenewedLeases` counts the client's renewal set at report time, **not** the
  authority's live lease count; transient wake leases may still exist outside that set.
- Claim/renew/move latency distributions and scheduling lateness use retained observations;
  successful samples, refused renewals, errors, claim/move failures, load-induced expiry,
  fencing and recovery claims must be read together. A zero/missing series is not an
  unmeasured capacity pass; no CloudKit throttles/push volume are measured by this relay run.

The top-level `s2-measurements.json` retains `passed`, series/counters, `notes` and `failures`,
each worker's report,
relay summaries and host metadata. Scenario samples are in `samples/*.csv`; every available
load worker independently retains
`load-samples/<profile>/<worker>/{report.json,claims.csv,renewals.csv,moves.csv,scheduler.csv,authority-attempts.csv}`.
The first three CSVs carry `duration_ns`; scheduler samples carry
`monotonic_ns,lateness_ns`. The additional attempt CSV retains every real initial/steady RPC
identity, device/conversation, operation, expected epoch, start/finish clock and outcome,
including transport failures, denied claims/renewals and explicitly unacknowledged releases.
Actual move retries and request/transport-failure totals are retained, not assumed from a mix.
Failure of one worker/report/sample retention does not skip other workers' evidence. Logs stay
in `logs/`; all main-relay files, including durable ciphertext/mailbox and authority state, are
scanned before owned work-root cleanup with a plaintext store as a positive control. Load relays
disable verbose evidence journaling/grant retention, **not durable authority journaling**.
Missing/partial evidence and errors remain failures, not silently discarded successful means.

Relay shutdown joins its tracked producers before closing the required evidence journal
and freezing final statistics. `relay-summary.json` carries a terminal `journal` outcome,
either closed or failed, instead of loose byte and entry counters. Counts include only
payload bytes and records whose writes completed for this journal owner. They exclude
framing bytes and are not cumulative counts for a previously populated file.

The first write or close failure survives finalization. Repeated close returns the same
outcome without closing the handle twice. A failed outcome returns a nonzero relay exit
and cannot emit successful `stopped`. Both main and load report admission reject it.
An intentionally empty evidence journal in a load profile is a valid closed zero-count
outcome; disabling verbose evidence does not disable durable authority storage.

Journal writes run in append order on one background queue, so a stalled volume no longer
blocks the relay serve loop or the lease frames behind it; `close()` drains that queue before
closing the handle. Every guarantee above still holds: counts cover completed writes only,
nothing is written after the first failure, and that failure is the terminal outcome. The
backlog is held in memory until it is written.

`s2-measurements.json` also carries a `storage` block: the `--work-dir` path, its `statfs`
mount point/device/file system, Foundation's internal/removable/local flags, and two
write+fsync probes (`beforeScenarios`, `afterBatch`; 100 × 512 B, 10 ms apart, p50/p95/p99/max
and the count above 1 s). It records the medium, never gates or reclassifies a result.

A device renews each lease by the TTL its runner claimed (the `claim` command's `ttlMs`), not
by the node's configured default; a hand-over or take-over claim without a TTL uses that
default for its own renewals. The scenario limits are unchanged (`claimAndRenew`: 6,000 ms
claim, renewal every 2,000 ms), so each renewal now extends to 6 s, not 10 s. Device `renewed`
events carry `ttl_ms=` and `expires_at=` (the authority's granted expiry). The renewal loop no
longer waits for the local store to record a renewal before its next tick: that store write is
queued in decision order behind earlier lease writes, and a commit waits for it first.

The device's replica journal no longer blocks the node on a renewal. A renewal's journal record
is written in order behind every earlier journal write, but the node does not wait for its
`fsync`; recovery never trusts a journaled expiry and resumes only an epoch it already held. A
commit waits for its publication and change records without blocking the node, so other
conversations keep renewing while it waits. Lease decisions (claim, loss, fencing, hand-over,
observed epochs) and replica applies still block the node until their record is durable.

After owned shutdown attempts, the batch retains `main-relay-summary.json` and
`main-relay-journal.bin` in its output even when a scenario throws. A missing main result is
recovered from that retained terminal summary. Source artifacts must be regular files.
Required publication failures remain nonzero, do not overwrite occupied destinations and
keep the original owned work rather than deleting the only remaining evidence.

The [actual occupied-destination control](../../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s2-required-copy-refusal-xpm16n3m/result.json)
preserves the exact sentinel, returns qualifier exit 1 and keeps the original journal and
matching terminal summary. Its host archives those originals before removing only its
own synthetic work. A successful proof check is not a successful S2 qualification.

The [current focused run](../../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/qualification_after_failed_relay_retention.log)
passes 20 behavioral tests. The [small actual CLI control](../../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s2-journal-cli-small-ri5nl1o4/result.json)
independently matches two authority records and a real grant to the closed journal.
The earlier [first](../../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s2-first-quick-diagnostic.json)
and [serial](../../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s2-serial-quick-diagnostic.json)
full quick cohorts fail after renewal refusal and lose their main summary during cleanup.
The [after-retention cohort](../../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s2-failed-cohort-retention-after.json)
still exits 1, but its retained main summary agrees with all 332 raw records and 156,508
payload bytes. Original lease limits and expected counts remain. This repair preserves
failed evidence. It does not qualify S2, establish the renewal-delay cause or supply Pi replication.



**Retained pre-journal evidence (not a result for the new durable/Bonjour slice):** the repaired
[quick run](../../../../../evidence/2026-11-03-memoshi-wave3-integration/s2-current-quick-enrolled/s2-measurements.json)
and [full `s2 --load` run](../../../../../evidence/2026-11-03-memoshi-wave3-integration/s2-current-full/s2-measurements.json)
exited 0; the full run took 412.08 seconds. The
[independent raw verifier](../../../../../evidence/2026-11-03-memoshi-wave3-integration/verify_s2_samples.py)
recomputed all 72 load distributions/windows across 12 workers and 48 integer-nanosecond CSVs,
reconciled actual elapsed-time rates, and matched initial-plus-steady RPC totals to each
[relay's independent counters](../../../../../evidence/2026-11-03-memoshi-wave3-integration/s2-current-full/load-verification.json).
All workers had zero errors, failed initial claims/moves, load-induced expiry, fencing and
recovery claims. Two ordinary busy claim retries occurred while an unacknowledged release was
still in flight; both are included in actual RPC counts, not discarded or called failed moves.
The [first secured failure](../../../../../evidence/2026-11-03-memoshi-wave3-integration/s2-current-quick/s2-measurements.json)
exposed an authority outage destroying an established encrypted stream; the repair preserves
that stream while refusing unauthorized processing, then revalidates/catches up on reconnect.
The [next run](../../../../../evidence/2026-11-03-memoshi-wave3-integration/s2-current-quick-repaired/s2-measurements.json)
correctly refused un-enrolled fresh pairing probes; their trusted candidate-roster preparation
was then fixed, not the enrollment fence. Both failures remain retained.
The earlier [real-expiry report](../../../../../evidence/2026-11-03-memoshi-wave3-integration/s2-full/s2-measurements.json)
predates these security/raw-retention fixes. Current full counts are development evidence,
not a fresh 301-second expiry check, complete device gate or O10/deployment-capacity conclusion.

## S4-T1: raw Seatbelt matrix (`s4-matrix`)

`s4-matrix` runs the 105-vector raw Seatbelt profile matrix of S4-T1. Each case runs a worker,
the CLI's own executable (`Bundle.main.executableURL`, not `argv[0]`) re-run as
`memoshi-qualification --s4-worker <job>`, directly or under `sandbox-exec`.

```sh
swift build --package-path Packages/MemoshiDaemon --product memoshi-qualification
Packages/MemoshiDaemon/.build/debug/memoshi-qualification s4-matrix \
  --output-dir ../evidence/<topic>/s4-matrix/run-N
```

- Without `--parent` the CLI creates the owned scratch `/private/tmp/memoshi-s4-20261114`
  (0700, owned by this user, canonical) if it is absent and a fresh `run-parent.XXXXXX` below
  it. `--parent DIR` must be an absolute canonical directory strictly below that scratch or
  below an `--owned-root DIR` (repeatable; each an absolute canonical directory this user owns).
  A relative `--parent` or `--owned-root` is a usage error.
- `--output-dir DIR` must not exist yet: the CLI creates it 0700 and writes each file
  (`report.json`, `summary.json`, `aliases.json`) exclusively, 0600. Without it the receipt
  stays in the run root and the summary goes to stdout only.
- `--aliases-volume PATH` (repeatable) runs the three default-ignorable alias spellings (one
  with U+200B, two with U+200D) behind the matrix's five default-ignorable vectors on another
  mounted volume, and requires `--output-dir`. It works in a 0700 scratch directory and removes
  exactly that directory.
- Exit codes: 0 when every case passed; 2 when the only failures are the three preexisting
  hard-link `guard_bypass` cases, D137's accepted limit (or bypasses were reproduced with no
  failure); 3 for any other failure, also one in the same run as those hard links, and for a
  requested alias volume that was skipped or kept its scratch; 64 for a usage error (including
  an existing `--output-dir`); 1 for an error that stopped the run.
- The matrix runs the profile held in `SandboxProfileSnapshot.swift`, not the shipping source
  directly. `SandboxProfileDriftTests` requires the shipping profile to render exactly that
  snapshot. Every run up to and including run-1 used the d0dc184 snapshot; the snapshot was
  re-taken from the shipping profile after the 2026-11-18 case-insensitivity change.

The [first CLI run](../../../../../evidence/2026-11-18-memoshi-review-fixes/s4-matrix/run-1/README.md)
(2026-11-18, package build, default form, d0dc184 snapshot) gave 72 denied, 25 allowed, 3
reproducible effects and 5 default-ignorable aliases not established, exit 2.
[Run-2](../../../../../evidence/2026-11-18-memoshi-review-fixes/s4-matrix/run-2/README.md), on
the re-taken snapshot, gave the same counts and the same outcome for every case, exit 2; the new
case-insensitive spellings are not among the 105 vectors, so the matrix does not measure them.
Both are development-Mac runs of the raw profile matrix, not S4 acceptance or D96 admission
conformance.

## Known chaos and shared recovery limits

- **SDK approval waits (H1/E6):** the pinned SDK has no invocation-free wait. The approval wait
  runs inside the `pi.tool` invocation; after a kill Pi reruns `beforeTool`, which reattaches
  through the `memoshi.approval` task memo. Each kill while waiting counts toward
  `HarnessSettings.restartLimit` (5); after enough consecutive kills the task is parked and the
  run never finishes, which the harness records as a failed run.
- **No Resume card yet:** an unsafe (non-replay-safe) tool interrupted after dispatch holds the
  conversation for an outcome check/Resume card that the SDK cannot settle yet. The harness tool
  is keyed and replay-safe, as §4.11 prescribes, so it exercises keyed retry, not the hold.
- **Real models:** only a small local model was run (see the evidence); it may skip or repeat
  the tool call, which the harness reports as a failed run rather than retrying it.
- **Separate child proof, and a wired subagent point:** the `chaos` plan now has a `subagent`
  kill point (the host runs a spawned child conversation; the kill reaches both; since
  2026-11-18 the run checks the child, see **Subagent point**). The nested
  Code Mode and compaction points are still unwired (compaction is refused per run). Core's real
  [`SubagentKillResumeTests`](../../../MemoshiCore/Tests/MemoshiRuntimeTests/SubagentKillResumeTests.swift)
  independently SIGKILL foreground/background child hosts after an immutable **model-tool**
  checkpoint; [retained results](../../../../../evidence/2026-11-03-memoshi-wave3-integration/native/runtime-child-conversation-tests.txt)
  verify original ownership and one completion/effect, not the nested-retirement window.
- **Nested result retirement (existing H1/E20):** at this pin a completed nested `pi.tool`
  retains only `{kind: "nested"}`; its full result is a parent-task-scoped document retired
  with the owner. A crash after retirement but before Memoshi persists an authoritative receipt
  may leave no result to reconcile. The runtime fails closed with `projectionFailed`
  (`storage_failed`), never fabricated success, an invented audit completion or blind retry.
  The [consumer observation](../../../../docs/research/spikes/2026-11-02-pi-swift-consumer-handoff.md#24-consumer-observation-nested-result-retirement-2026-11-03)
  remains H1/E20; H4 is already Code Mode. All-call policy/audit/kill acceptance stays open.
- The canary scanner does not decode compressed data or MIME-wrapped (line-broken) base64.
- Mac development evidence only, not reference-box or iOS runs; S1 counts results only on a
  `slice-N` tag.
