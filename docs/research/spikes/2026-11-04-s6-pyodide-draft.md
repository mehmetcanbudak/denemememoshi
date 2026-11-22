# S6 Pyodide: development host and bridge evidence

**Status: DRAFT, updated 2026-11-08. S6 is not qualified.** The offline scientific runtime and a sealed native-gateway candidate have bounded actual-WebKit development-Mac proof. The earlier public HTTP/SOCKS proxy controls remain failed. [D100](../../plan/decisions.md#d100) selects the sealed native route for development; the per-bot realm is kept and hardened (§2e), and now refuses nested workers and binds network admission to the cell that started the work (§2f). No physical-iPhone result, W25 move, general-browser confinement or production-tool enablement follows. P0-23 and D79's fallback order remain unchanged.

**Owners:** NAT for WebKit/device lifetime, footprint and native presentation; RT for the bridge, cancellation, file/package paths and gateway. **Authority:** [S6 acceptance](../../plan/phase-0.md#s6), [D76](../../plan/decisions.md#d76), [D79](../../plan/decisions.md#d79), [D80](../../plan/decisions.md#d80), [D84](../../plan/decisions.md#d84), [D100](../../plan/decisions.md#d100), and [04 §4.16](../../plan/04-architecture.md#416-python-and-notebooks). This record does not amend them.

## 1. Exercised route

`Packages/MemoshiApp/Sources/PyodideSpike` owns one hidden, nonpersistent `WKWebView` per host. Its `WKURLSchemeHandler` serves only the bundled host files and manifest-listed runtime files. Native code verifies the sealed payload before creating the realm. The payload remains Pyodide **314.0.7**, with NumPy, pandas, SciPy, Matplotlib and their 14-package bundled closure. No vendor runtime was modified or downloaded during these runs.

The page is a responsive controller. A small blob module worker dynamically imports the original custom-scheme `worker.mjs`; that module retains its original `import.meta.url`, so runtime modules, Wasm, the Python stdlib, wheels and cell helpers still resolve through the sealed scheme host. The blob URL lives until termination/fatal disposal. A static import in that bootstrap was rejected; dynamic import reached actual `coreReady` and the scientific runtime without broadening the existing script/connect policy or adding an HTTP/file host.

The hidden view explicitly uses public `WKPreferences.inactiveSchedulingPolicy = .none`. The installed Mac returned default raw value `0` (`.suspend` in the installed SDK). Before the correction, instrumented runs stalled during pandas or Matplotlib import after the scientific wheels had loaded. With the corrected hidden-view policy, the public API completed scientific calls and subsequent realm replacement. This setting is **not** an iOS continued-processing grant and does not prevent OS suspension or jetsam.

Cancellation/timeouts retire the native request and discard the interpreter. Native disposal awaits the responsive page's acknowledgment that it called `Worker.terminate()` before a new realm starts. The API provides no worker-join or memory-reclamation acknowledgment: these runs establish the observed request failure, successful new execution and absence of old interpreter state, **not** synchronous WebContent process destruction.

## 2. Actual public-API smoke

A temporary AppKit executable linked the public `PyodideSpike` product and ran the real WebKit event loop. The final executable contained no private reflection, swapped script handler or startup diagnostics. Its isolated `HOME`/`CFFIXED_USER_HOME`, bot folders and outputs were owned by this run. The generated Debug resource accessor selected an exact copied build-resource bundle on an owned SSD directory; native manifest verification remained enabled. The Pi SDK pin and normal app/helper `.none` composition were unchanged.

The [uninstrumented receipt][public] and [raw measurement series][measurements] record:

- **20 actual scientific calls:** each imported the bundled scientific stack, consumed an input CSV, and returned table values `[[1,2],[2,4],[3,6]]` with columns `x,y`. Each figure decoded as a real PNG. Every exported CSV had rows `x,y`, `1,2`, `2,4`, `3,6`; its actual bytes and SHA-256 matched the returned artifact.
- **CPU-bound timeout:** a real infinite Python cell produced `timedOut`; another interpreter subsequently started and executed.
- **Active-cell cancellation:** the driver waited for the worker's execution-start message, canceled the infinite cell and observed `cancelled`.
- **Fresh state:** a marker stored in `builtins` survived a second call before cancellation, but was absent after cancellation/restart. This is interpreter replacement, not the ordinary fresh per-cell globals dictionary.
- **Bot isolation:** a marker persisted across calls in the first bot and was absent in a separately started second bot's interpreter.

Development observations from that receipt, **not reference-device pass/fail numbers**:

| Observation | Value | Boundary |
|---|---:|---|
| Sealed runtime payload | 45,397,543 bytes | Not signed app download/install size; excludes other app components |
| Pyodide core initialization | 1.17838475 s | Worker-reported core phase |
| Scientific-stack load/import | 10.38 s | Worker-reported phase after core readiness |
| WebView to ready | 11.558809542 s | Native ready observation; not process-launch or physical-iPhone cold start |
| Complete public-API scenario | 47.67 s | Includes 20 calls, timeout, multiple starts, cancellation and isolation |

The earlier [instrumented receipt][instrumented] passed the same functional invariants. Neither run enabled network access or configured a proxy. There was no model call, paid API use, OS background grant, physical-device run, synchronous process-kill observation or visible native review.

### Current-source integration control

A [freshly rebuilt public-product executable](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/python-current-5d15fa0b/current-source-offline-smoke.json) subsequently passed in **34.84 s** after native API-contract and scheme-response failure handling were integrated. It linked only `PyodideSpike`, used the same sealed SSD resource copy with manifest verification enabled, and created a new private output folder. Twenty scientific calls again verified the exact table/CSV values, decoded PNGs and artifact bytes/hashes. Actual CPU-bound timeout, active-cell cancellation and absence of the old `builtins` marker after restart also passed.

That control observed core initialization **1.157717291 s**, scientific load/import **10.264 s** and native WebView-to-ready **11.4234545 s**. These are development-Mac samples, not a physical-iPhone distribution or a reference-budget pass. Networking remained disabled; the control neither reran bot isolation nor corrected the failed proxy routes below. Its [raw driver report](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/python-current-5d15fa0b/s6-reports/88b6506c-b8c4-428f-9c18-fec9b79aa027.json) and declared scientific outputs are retained separately from the earlier run.


### Resource-bundle packaging repair

The actual iOS Simulator build rejected the old resource bundle as an unrecognized bundle
format. An owned ad-hoc-signing reproduction isolated the reserved root `Resources` directory:
the same minimal flat bundle signed and strictly verified when its payload was at the root.
The package now copies `Runtime` as a subtree and the four host files directly into its
resource bundle; `PyodidePayload` resolves `Bundle.module.resourceURL` without an old-path shim.
Pinned runtime bytes, manifest verification and capability rules are unchanged.

The actual regenerated iOS resource bundle [passes strict signature verification](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/resource-bundle-ios-signature-proof.json),
without disabling the app build's signing checks. The subsequent missing
`DevicePairingFeature` localization bundle is also repaired; the genuine mobile Debug app now
builds and runs its isolated browser review. Neither is a physical-device or release-signing receipt.

A [newly rebuilt scientific host](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/python-flat-layout-87d804be/packaging-smoke-receipt.json)
then passed in **43.79 s** using the corrected resource layout. The new executable and bundle
were copied into a new sealed owned SSD directory; its generated absolute build-bundle fallback
was unavailable for the entire run and restored afterwards. The manifest SHA-256 remains
`57f41131904edff72a507d8e38bd39d9c6a7749613d34e11630ed5545278a1f1`.
The [actual result](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/python-flat-layout-87d804be/bot/current-source-offline-smoke.json)
again verifies twenty scientific table/CSV/PNG calls, artifact bytes/hashes, real CPU-bound
timeout, cancellation after cell start and no cancelled interpreter-state reuse. Networking
remained disabled; physical measurements, proxy confinement, native Python review and
synchronous OS-thread reclamation remain unmeasured. Earlier timings above retain their
original pre-packaging scope.

The canonical package run then exposed a test-fixture precondition error: Foundation retained
the `/var` temporary alias even after `resolvingSymlinksInPath`, so strict no-follow admission
correctly rejected the root before any intended file operation. The two fixture helpers now
use the existing POSIX `realpath` pattern. [Eight scientific-folder and four browser-staging
tests pass](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/canonical-final-1da07a50/fixture-path-after.json),
including actual byte round trips, hostile links/FIFOs, bounded reads, one-use bindings and
atomic batch refusal. Production path checks, modes and size bounds are unchanged. The
[later unchanged full canonical run](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/canonical-integrated-a9466911/run.json)
also passed; that functional integration does not close the failed network route or physical-device requirements.

### 2a. Authenticated package route and failed confinement

A separate public-host probe configured native WebKit proxy credentials, fetched an owned synthetic wheel through an authenticated HTTP proxy, verified its SHA-256 and imported it to compute `product(6, 7) == 42`. The probe then failed its direct-request denial assertion: a Python `pyfetch` to a separately listening loopback sink returned `DIRECT_SINK`. The independent server recorded both authenticated proxy requests and an actual bypass request; the sink's separate outside-proxy positive control also succeeded.

The [original failed probe](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/pyodide-loopback-bypass-before-fix.json) and [server counters](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/pyodide-loopback-bypass-counters.json) are retained. Setting `matchDomains` to `["", "0.0.0.0/0", "::/0"]` without an `excludedDomains` setter did not fix the bypass: [failed experiment](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/pyodide-all-domain-bypass-failure.json), [independent counters](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/pyodide-all-domain-bypass-counters.json). That ineffective source change was reverted.

A separate [public-API matrix](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/pyodide-public-proxy-api-matrix.json) removed Python from the experiment. Actual `WKWebView.fetch` requests used empty domain lists with and without the exclusion setter, an empty-string match, a wildcard, all-address prefixes, explicit loopback host names and explicit loopback prefixes. **All seven configurations authenticated successfully through the owned proxy; all seven also reached the separate direct loopback sink.** These are component-level WebKit observations, not a run of the real browser product or a physical-device verdict.

The public `socksv5Proxy:` alternative was also exercised with genuine SOCKS5 username/password authentication and the same seven match configurations: [result](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/socks-public-api-9b55f5ad/proxy-api-matrix.json), [independent counters](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/socks-public-api-9b55f5ad/socks-counters.json). Every proxy challenge succeeded, while every direct sink request bypassed it. Switching between the two public proxy constructors is therefore not a correction for this observed loopback case. No untested system-level confinement route is inferred to work or to be impossible.

**Gateway confinement failed this development control.** `allowFailover = false` and a configured proxy are not evidence that every request traverses it. The successful owned wheel is not a qualified general installer, secret broker, package registry or production tool integration. Normal app/helper tool composition remains disabled.

### 2b. Actual Pi-to-worker tool bridge and active Stop

The [integrated bridge receipt](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/engine-python-bridge-91ac5ff4/engine-bridge-smoke.json) passed through the public `RuntimeAdapter`, actual Pi HTTP tool calls, mandatory `.pythonRun` T2 policy in **Auto**, and the public `PyodideSpike` API. Only the external loopback HTTP model was controlled. This was not Bypass, an SDK mock, a paid provider or normal app/helper tool enablement.

- Twenty model-requested scientific tool calls verified the real table values, decoded PNGs and exported CSV bytes/hashes. Two further scientific calls verified recovery after the timeout and cancellation, respectively.
- An actual infinite cell timed out. For Stop, the driver waited for the worker's execution-start message before aborting the engine turn; the turn became `canceled`, the Python host reported `cancelled`, and the next engine turn succeeded in a fresh realm.
- Host callbacks used `RuntimeToolInvocation.runCancellable` to bind **Sendable host work** to the SDK abort signal. The non-Sendable SDK invocation stayed on its original executor; nested `callTool` was not moved into that host task.

The [independent model control](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/engine-python-bridge-91ac5ff4/model-provider-summary.json) recorded 24 tool requests, 23 final replies and zero rejected requests. The AppKit/WebKit exercise exited 0 in 69.71 s on the development Mac with the sealed SSD resource copy. Python networking was **disabled** throughout: this proves no correction to the failed proxy controls, no visible native surface, no physical-device behavior and no reference-performance budget.

### 2c. Sealed native HTTP route: 2026-11-06 development control

The current host optionally accepts a trusted caller-owned `PyodideNetworkTransport`. The
responsive fixed controller forwards structured data to native `WKScriptMessageHandlerWithReply`;
native code checks its main frame, realm/generation and live cell, bounds admission and awaits
cancellation/retirement. The documented pre-import `loadPyodide({jsglobals: ...})` seam supplies
Python's `js.fetch`/`pyfetch`. The original Worker globals remain subject to the same sealed
response-header and HTML CSP: **no HTTP(S) connect permission is added**. The adapter is not the
confinement boundary, and it cannot authorize a site or choose native bot attribution.

The [complete actual run][native-run] passed in **111.40 s**. It linked real `PyodideSpike` and
`MemoshiEgress`, using a host-owned `EgressClient.fetch` over its exact authenticated Unix route.
Original HTTP(S) URLs, methods, headers and binary bodies remain data; each redirect obtains a
new native gateway decision. The only resolver/dial override was the existing debug test seam:
public/private address checks still ran, then accepted synthetic public names connected to an
owned TLS fixture with its existing public test certificate. No real account, provider or
system trust-store change was used.

The [result and independent counters][native-result] establish:

- Real HTTPS status/header/body/URL/clone consumption, non-success status, binary POST bytes,
  bodyless HEAD/304 encoding metadata, refusal of opaque compressed entities, redirect behavior,
  private-address refusal and native synthetic-credential injection/echo scrubbing.
- Request-mode refusal before dispatch and abort of returned response bodies, clones and readers.
  Original implementations failed those actual-WebKit controls; they are not inferred from mocks.
- Original Worker fetch, XHR, WebSocket, remote import and a genuinely created nested blob Worker
  made **zero** requests to the independent sink. A separate no-CSP page reached that sink with
  all five corresponding attempts. The WebSocket handshake and import need not succeed for their
  independently recorded network-attempt positive controls. WebRTC was absent in the Worker;
  no WebRTC connection or universal browser-confinement claim follows.
- Three requests actually reached the owned slow upstream before Stop, timeout or normal cell
  return. Each connection closed before that cooperative fixture's effect boundary; all three
  reported no committed effect. This is not arbitrary third-party uncertain-outcome recovery.
- Twenty scientific calls again verified the exact table matrix and CSV bytes/hashes and decoded
  native PNGs. CPU-bound timeout, active cancellation, successful subsequent execution and an
  unavailable owned gateway without direct fallback also passed.

This is a bounded native HTTP/fetch-compatible subset, not a general browser implementation:
`same-origin`, `no-cors` and integrity requests fail closed; no general micropip installer,
credentialed web session, package registry, production bot policy composition or physical
background grant is qualified. The owned wheel control verifies bytes/hash and an in-memory
pure-Python import only.

The retained [before-repair run][native-before] returned false for all four abort/mode checks.
Core's [failing-before regressions][native-core-red] also reproduced resolution before policy
and bodyless gzip rejection; [all 42 affected gateway tests][native-core-green] then passed.
The live native review caller uses `networkConfigured` to say only that a transport was supplied,
not that a grant or confinement was established.

Earlier disposable-driver guard/role/row-shape failures remain beside these receipts. A separate
[actual startup timeout][native-startup-timeout] is retained, not explained away. The subsequent
internal-root copy had the identical executable SHA-256 and unchanged payload, signature and
public deadline; its success proves neither storage causality nor a cold/reference startup budget.
The earlier offline Pi-to-worker proof (§2b) retains its original scope and is not silently
promoted to networked product integration.

**Route-decision prerequisite superseded.** [D100](../../plan/decisions.md#d100) selects this
sealed native route for development. S6.5 requires every request to reach the gateway, with no
bypass at independent sinks. Physical-device acceptance remains open. D100 does not choose a
platform fallback, repair arbitrary-page S3 confinement or move S6 out of Phase 0.

A later [stronger builtins-state diagnostic][native-state-diagnostic] timed out in its first
fetch-semantics cell, before reaching any new state assertion. It is not counted as an
interpreter-retirement pass; §2d supplies completed public-host retirement controls.
The [scoped credential scan][native-canary] checked 111 owned regular files against seven forms
of this fixture's known synthetic credential, with positive controls, zero hits and no skipped
or changed paths. It read no real provider key and is **not** the full Phase 0 canary gate.

### 2d. Persistent-realm lifetime: 2026-11-06 development measurement

A disposable AppKit carrier linked the real `PyodideSpike` product and called only public
`start`/`execute`/`cancel`/`close`. It used the unmodified generated resource accessor, the sealed
bundle (manifest `57f41131…`) and the unchanged default 60-second startup and cell limits. No
network transport, model or credential was configured; each control had a new private home.
[Receipts][lifetime-20261106] retain the authored cells, hashes, public states and validated
synthetic samples only. The first invocation refused the carrier's own environment guard because
CoreFoundation adds `__CF_USER_TEXT_ENCODING`; only that measured key was then allowed.

| Control | Observation |
|---|---|
| Ordinary reuse | A `builtins` marker survived the next cell |
| Stop / 0.5 s timeout | Executing callback observed; `cancelled` / `timedOut`; restart; marker absent |
| Script-selected terminal | **Red.** Python captured the next request's `id`/`generation` with a public worker `message` listener and posted a complete `result`. Native returned the attacker's stdout and became `ready` while the real cell still slept; a late `cancel` changed nothing until `close` |
| Post-return timers | **Red.** Eight bounded heartbeat computations ran after a genuine normal return and after a later native challenge |

Seven development-Mac startups took 1.02–1.24 s for the core and 9.24–10.13 s for the scientific
stack. Native result limits, file export checks and live-cell network admission still applied:
a forged result passes the same validation as a genuine one. What fails is cell lifetime. In a
persistent per-bot realm, `result` attests that the worker realm sent a message, not that cell
code stopped. Stop, timeout, worker failure (including `busy`) and `close` retire the whole realm;
a normal return leaves scheduled tasks alive. [INFERENCE: `worker.mjs` reads `activeCell` when a
fetch starts, so a task left by one cell could make a native request attributed to a later
admitted cell of the same bot; not measured.] The user then chose to keep one realm per bot and
harden it (§2e); per-cell realm retirement was not adopted.

### 2e. Hardened per-bot realm: later 2026-11-06 development measurement

Three changes keep the realm per bot. Control traffic now uses a private `MessageChannel` created
before any interpreter code; its bound send and event reader are captured, and the page ignores the
public worker bus once connected. At each cell end the worker cancels pending asyncio tasks, gives
them one loop turn, and clears timers the cell created; failing that cleanup fails the cell, which
discards the realm. Native [`PyodideSessionLimits`](../../../Packages/MemoshiApp/Sources/PyodideSpike/PyodideTypes.swift)
discard a realm after an idle period (default 600 s) or at its next call boundary after its
lifetime (default 3,600 s); a cell spanning the lifetime still returns its result first.

The same [carrier][hardening-20261106] ran against an exact pre-change copy of the package and then
against the changed repository, with fresh homes and the unchanged sealed resources:

| Control | Before | After |
|---|---|---|
| Public-bus forged result | Request observed; attacker stdout returned | Request not observable; genuine stdout returned after the 2 s tail |
| Unawaited asyncio task | 8 computations after the post-return ack | 0; cancelled at cell end |
| Cell `setTimeout` loop | 8 computations | 0; timer cleared at cell end |
| Nested-worker messages | 8 computations | **8: residual** (closed in §2f) |
| Reuse, Stop, 0.5 s timeout | Passed earlier | Pass |
| Idle 3 s / lifetime 8 s | Not in build | `idleExpired`; spanning cell returned, then `lifetimeExpired`; `notReady`; fresh realm |

With the hardened host, the complete network/scientific scenario (§2c's retained first 300 lines
plus a [reconstructed tail][scenario-summary-20261106]) passed in **59.81 s**: request-mode
and abort semantics, every native HTTPS case, the sealed Worker network refusals with their
unconfined positives, Stop/timeout/normal-return drains with no committed upstream effect, 20
exact scientific calls, CPU timeout and cancellation, a fresh realm, and an unavailable gateway
with no direct fallback. Its first attempt exposed the gateway-shutdown defect in §3.

**Residuals, stated plainly.** Code in the realm can still schedule work through message ports and
other JavaScript callbacks, and shares this realm's intrinsics and Pyodide's own runner, so a
deliberate cell can still make the worker report a later cell early [INFERENCE: by patching
`pyodide.code` or JavaScript intrinsics; not measured]. Native limits, not the channel, therefore
bound how long cell code runs: Stop, timeout, any worker failure, idle shutdown and the lifetime.
The nested-worker residual and the cross-cell network attribution inference in §2d are measured
and closed in §2f.

**Soft stop is not available.** A [raw custom-scheme diagnostic][isolation-20261106] on macOS 27.0.1
(WebKit 22625.1.29.11.28) found the page and its module worker secure contexts. With COOP/COEP
both became cross-origin isolated, yet `SharedArrayBuffer` stayed undefined, as it is in the host's
worker. Pyodide's `setInterruptBuffer` therefore cannot be used, and Stop stays a realm-discarding
hard stop. The pinned runtime also has no snapshot creator (only a private `_loadSnapshot`
consumer), so a fast fresh-realm-per-call mode would need a runtime change.

### 2f. Nested workers and cross-cell borrowing: 2026-11-08 development measurement

Two real-WebKit tests in `PyodideSpikeTests` (`PyodideRealmLifetimeTests`) start the real host
with an owned in-process transport. That transport is the measurement: it records a request only
after native code has admitted it, together with the cell ID native admitted it for. No network,
credential, model or safety-gated probe was used; the fixtures are the cells themselves.

**Nested workers (reproduced, then refused).** A cell starts a bounded heartbeat worker (one
message every 50 ms, at most 100) whose messages call a Python handler. A later cell marks the
return and sleeps 1.5 s; the handler then counts beats and asks native for one request. Before the
change, on the repository and on an exact pre-change package copy ([red][s6f-red],
[snapshot red][s6f-red-snapshot]): the worker started, **23 beats** ran after the return, and native
admitted `nested-after-return` under the **later** cell's ID. The worker now deletes `Worker` and
`SharedWorker` from its global scope before any interpreter code runs, and fails startup if either
remains. With no instance in the realm, cell code has no constructor to reach, and its attempt
raises. After the change: no worker, 0 beats after return, 0 admissions ([green][s6f-green]).
Stop and `close` still discard the whole realm as before.

**Cross-cell borrowing (measured, then closed).** A first cell makes its own request, then leaves
two pieces of work behind: a chain of JavaScript callbacks (each a sealed local asset load, so
timers still run) and an asyncio task it created that swallows the cell-end cancellation. A later
cell arms both and waits; each then asks for a request while only the later cell is live. On the
exact pre-change copy ([red][s6f-red-borrow]) **both leftover requests were admitted, recorded
under the later cell's ID** — the same ID as that cell's own request. The cause was the §2d
inference: the worker took the cell for a request from whichever cell was live (`activeCell`),
and native's live-cell check then passed. Earlier attempts of this fixture are not counted: a
message-port loop starved the worker's timers and timed out, one revision had a fixture key
error, and three runs hit the 60 s startup deadline while unrelated processes held the host at
load averages of 21–92 ([summary][s6f-summary]).

The fix binds admission to the cell that started the work. Each cell's code now runs as one
asyncio task whose `contextvars` context holds that cell's capability object; tasks it creates
inherit it. JavaScript callbacks, and tasks they create, run in the empty base context. The
worker refuses a request unless the current context's capability is the live cell's, before
anything reaches native. After the change, both leftover requests are refused in the worker, and
native admits exactly the two cells' own requests (`pyfetch` in the first, `js.fetch` in the
second), each under its own ID ([green][s6f-green]: 20 `PyodideSpikeTests` pass).

A disposable AppKit carrier linking the public product ran the same fixtures
([lifecycle carrier][s6f-carrier]). Before the change: the worker ran 11 beats after the return
and native admitted its request under the later cell; both leftovers were admitted under the
later cell. After: no worker, no beats, no leftover admission, and only each cell's own request
admitted under its own ID. The 2026-11-06 lifetime carrier, rebuilt against the changed package
([hardening matrix][s6f-hardening]), passed reuse, Stop, timeout, forged result, timers, asyncio,
isolation, idle and lifetime. Its old nested control now fails as expected: creating the worker
raises, so the cell fails and the realm is discarded. Startup took 35–47 s under that load, not
the earlier 11 s; these are not timing samples.

Consequences and limits:

- A request must come from the cell's own code or a task it created. A request started in a
  JavaScript event callback (a `create_proxy` handler) is refused even while its cell is live.
- Deliberate reach was then measured (2026-11-08, [round 2][s6f-round2], [finish][s6f-finish]).
  On an exact package copy with the D105 worker, work left behind by an earlier cell obtained
  the later cell's admission in six ways, each admitted by native under the later cell's ID:
  entering a live task's context from `asyncio.all_tasks()` (directly, as a copy, as
  `create_task(context=…)`, or from a JavaScript callback), entering contexts found by
  `gc.get_objects()`, and setting the cell's `ContextVar` (found by iterating task contexts) in a
  new context. Frame/traceback walks found no token, nor did `sys.modules` and JavaScript globals
  in the carrier.
- The worker now binds admission to the cell's own tasks rather than a Python-visible token: the
  root task and tasks created while a cell task executes are recorded outside Python, and a
  request is admitted only while a recorded task is current and its coroutine is executing,
  checked with builtins captured before cell code. `deliberateReachCannotBorrowLiveCell` fails
  on its assertions on the D105 copy ([red][s6f-finish-red]) and passes on the repository, where
  all 22 `PyodideSpikeTests` pass ([green][s6f-finish-green]). In the real-host carrier the six
  paths, plus `_asyncio._swap_current_task` (live or fresh module), are refused. **Residual:**
  writing the interpreter's memory through `pyodide_js._module` forged both facts and native
  admitted the request (round 2; not rerun, the worker is unchanged since). No in-realm token
  resists that; only a realm per cell would, which the per-bot realm excludes. Native limits
  still bound it. Searching `sys.modules` and JavaScript globals still makes the later cell fail
  after its own request (`scriptFailed`, realm discarded), so that search stays in the carrier.
- Ordinary Python networking did not regress. `pyfetch` calls `fetch` synchronously inside the
  awaiting coroutine, so it never crosses a JavaScript `await`. A regression test runs 20 steps,
  one cell each, on the real host: sequential `pyfetch`; `pyfetch` in tasks the cell creates
  (loop and module `create_task`, `ensure_future`, `gather`, a task created by a task, a
  `TaskGroup`); `js.fetch`; a request after `asyncio.sleep`; `wait_for`; a POST body; and §2c's
  signal, clone, abort and same-origin observations, started and consumed in Python. It passes
  on the D105 copy and on the repository: all 22 expected requests are admitted, each once under
  its own cell's ID. A fetch JavaScript starts synchronously when cell Python calls it is the
  cell's own; one started after a JavaScript `await` is refused, as D105 intends.
- Not a D105 effect: a JavaScript function that receives a promise from Python and returns
  `p.then(…)` never settles, even for `Promise.resolve(1)`. The awaiting cell times out, and
  `asyncio.wait_for` does not rescue it. This happens on the current, the D105 and the pre-D105
  (`e99946e`) worker alike ([diagnostics][s6f-finish]). Round 2's adapted §2c harness used such
  helpers, which is why it timed out.
- §2c rerun: the first cell now starts and consumes every request in Python, and the sealed
  nested-Worker control expects `construction-denied`. The scenario **passed** in 48.34 s at load
  ~5 ([scenario][s6f-finish-scenario]). The 20-call scientific driver also passed (29.0 s, load
  ~4). Its round 2 `unsafePath` came from the harness: the bot root sat under `~/Documents`, and
  `PyodideBotFolder` opens every ancestor. At the time, macOS refused opening `~/Documents` itself
  (`EPERM`, [INFERENCE: privacy protection]); the same probe succeeded later. The bot root now
  lives under `/private/tmp`. S6.5 stays open for its physical-device rows.
- Nothing here is a physical-iPhone result: S6.1–S6.4 and S6.6 remain open (§5).

## 3. Failures retained, not washed away

| Failure/control | Actual observation | Correction or remaining risk |
|---|---|---|
| Input file creation | The pinned Emscripten filesystem rejected `FS.writeFile(..., {flags: "wx"})` before Python ran | The host now uses numeric `O_WRONLY | O_CREAT | O_EXCL`; the 20 real CSV-input calls exercise successful exclusive creation without replacing it with truncating `w` |
| Page-thread interpreter | A main-thread control completed 20 scientific calls but failed the subsequent cancellation scenario | Computation moved to the dedicated worker; the responsive page owns termination |
| Worker bootstrap | Direct custom-scheme entry/static blob dependency failed startup; dynamic import reached core readiness | Retain the sealed scheme host and dynamic bootstrap. Do not infer that all custom-scheme worker requests are unsupported |
| Hidden import stalls | Wheels loaded, then import progress stopped at pandas or Matplotlib under the original hidden-view policy | Explicit `.none` scheduling; native timeout/cancellation/expiration remain authoritative |
| Built bundle on external APFS/HDD during host pressure | [An uninstrumented run][hdd-negative] completed 20 calls and timeout, then timed out restarting | **Unresolved environmental/portability risk.** The later SSD control passed; this does not prove storage was the sole cause. During the affected period a filesystem query also timed out and host memory was heavily compressed |
| Retained §2c driver source | Both retained `Entry.swift` copies end at line 300 with a tool-output footer; the original 89-line tail is lost | The §2c results stay retained. A later batch reran lines 1–300 verbatim with a clearly labelled [reconstructed tail][scenario-20261106], not the original source |
| Native fetch after gateway shutdown | The reconstructed scenario's unavailable-gateway step trapped a debug build: `EgressClient.fetch` made promises on stopped event loops ("leaking promise") | A [failing-before regression][egress-red-20261106] reproduced it; native exchanges are now created only for open clients, and the [same test passes][egress-green-20261106]. [INFERENCE: release builds skip NIO's leak check, so they would have thrown `closed` and leaked the promise; not measured] |

The [pre-worker scientific control][science-control] is not a recovery pass. Historical failing controls and the later success remain separate evidence. Current development durations are not substituted for S6's iPhone thresholds.

## 4. CSP and capability limits

The blob worker inherits the page CSP. An imported module's `worker-src 'none'` response header does **not** establish a nested-worker prohibition, and the page's `worker-src blob:` still permits one by policy. The prohibition is instead enforced in the worker: it removes the `Worker` and `SharedWorker` constructors before any interpreter code runs (§2f). Native result/file limits, sealed resource admission, per-host isolation and offline connect policy remain in force. Resource-exhaustion behavior and physical-device memory reclamation still need qualification.

The historical public-proxy controls (§2a) supplied no proxy credential to Python, but actual direct loopback bypass still occurred; they remain failed. The sealed native candidate (§2c) does not configure or qualify those WebKit proxy constructors: it keeps direct networking blocked and sends admitted HTTP hops through a trusted native owner. Its bounded synthetic secrecy/negative controls are not complete broker, package-policy, actual bot/tool composition, physical QUIC/DNS or general-installer qualification.

## 5. S6 acceptance remains open

| Row | Required evidence | Current disposition / owner |
|---|---|---|
| S6.1 startup | Prescribed cold/core/scientific startup series on iPhone 14 Pro | **Not run.** Development startup only; NAT |
| S6.2 memory | Prescribed million-row pandas workloads, WebContent footprint and device jetsam evidence | **Not run.** No physical-device or ten-minute pandas measurement; NAT/RT |
| S6.3 background | Actually granted continued processing, expiration and suspension behavior | **Not run.** `.none` scheduling grants no execution time; NAT |
| S6.4 size | Physical-device download/install growth of the pinned core and scientific stack | **Not run.** Sealed payload bytes only; NAT |
| S6.5 bridge | Real tool/file/output correctness, timeout/cancellation and every request through the configured gateway | **Offline public-API/Pi bridge and sealed native-gateway candidate passed bounded development-Mac controls; original public-proxy confinement failed.** Stop/timeout retire the realm. After §2e's hardening a public-bus forged result and the measured asyncio/timer leftovers are refused; after §2f nested workers are refused and leftover work can no longer borrow a later cell's network admission. Callback chains can still run after a return and native limits bound cell lifetime. Physical in-app composition, complete package/broker/policy/native-surface qualification and physical route acceptance remain open; RT/NAT |
| S6.6 Lockdown | Actual device detection/load result and explicit Mac fallback | **Not run.** The host has a Lockdown refusal path, not a measured route/fallback; NAT |

P0-23 is the existing follow-up ticket for these Phase 0 measurements. PY-03/PY-04 use [D100](../../plan/decisions.md#d100)'s route, pending its physical-device rows. **No S6 cut has been approved or recorded by this implementation.** If the user applies the accepted cut order, the gate must explicitly record the move to W25; otherwise S6 stays in Phase 0.

## 6. Primary API/source notes

- [Pyodide 314.0.7 worker documentation](https://pyodide.org/en/314.0.7/usage/webworker.html): module workers, not classic `importScripts()`.
- [Pinned Pyodide configuration](https://github.com/pyodide/pyodide/blob/b1e4fcc2488962f6360a97f19b9982d6fdb5d16f/src/js/pyodide.ts#L55-L111): preserve documented runtime/resource options; no private loader hook was introduced.
- [WebKit dynamic-import destination selection](https://github.com/WebKit/WebKit/blob/2756e8be58521b10c8e8bff8da1f13d97f2eae27/Source/WebCore/bindings/js/ScriptModuleLoader.cpp#L373-L401) and [worker module CSP selection](https://github.com/WebKit/WebKit/blob/2756e8be58521b10c8e8bff8da1f13d97f2eae27/Source/WebCore/bindings/js/WorkerModuleScriptLoader.cpp#L85-L131). This published adjacent-release source is not an assertion of exact installed-binary/source identity; the runtime receipts supply the installed behavior.
- [Blob worker CSP inheritance](https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API/Using_web_workers#content_security_policy) and [worker termination algorithm](https://html.spec.whatwg.org/multipage/workers.html#terminate-a-worker): acknowledgment is not a native thread/process join.
- Installed SDK `WKPreferences.h:84–99` documents inactive scheduling; its Swift async overlay uses `callAsyncJavaScript(_:arguments:in:contentWorld:)`. The two-`in:` overload is completion-handler-based and returns `Void`; disposal uses the awaited overload.

[public]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/pyodide-worker-public-api.json
[measurements]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/pyodide-worker-public-api-measurements.json
[instrumented]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/pyodide-worker-instrumented.json
[hdd-negative]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/pyodide-hdd-restart-negative.json
[science-control]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/pyodide-science-before-worker.json
[native-run]: ../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/python-native-internal-sealed-smoke-2b0d2c28/run.json
[native-result]: ../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/python-native-route-5062b42b/attempt-internal-sealed-copy/result.json
[native-before]: ../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/python-native-route-5062b42b/attempt-before-physical-guard/result.json
[native-core-red]: ../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/native-fetch-policy-bodyless-red-261b5a49/command.log
[native-core-green]: ../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/native-fetch-policy-bodyless-green-0544ae46/command.log
[native-startup-timeout]: ../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/python-native-scientific-contract-smoke-85be3910/run.json
[native-state-diagnostic]: ../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/python-native-state-invariant-smoke-873c0561/run.json
[native-canary]: ../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/native-python-canary-b776f177/result.json
[lifetime-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-next-caa93544/python-lifetime-summary.json
[hardening-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-python-hardening-b0f24d5d/python-hardening-summary.json
[isolation-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-python-hardening-b0f24d5d/isolation-direct/isolation-report.json
[scenario-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-python-hardening-b0f24d5d/scenario-after/scenario-source
[egress-red-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-python-hardening-b0f24d5d/egress-shutdown-red-38399cd7/command.log
[egress-green-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-python-hardening-b0f24d5d/egress-shutdown-green-90a38812/command.log
[scenario-summary-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-python-hardening-b0f24d5d/scenario-summary.json
[s6f-red]: ../../../../evidence/2026-11-08-memoshi-engineering/PythonLifecycle/red-realm-lifetime.log
[s6f-red-snapshot]: ../../../../evidence/2026-11-08-memoshi-engineering/PythonLifecycle/red-prefix-snapshot-realm-lifetime.log
[s6f-green]: ../../../../evidence/2026-11-08-memoshi-engineering/PythonLifecycle/green-pyodide-spike-tests.log
[s6f-carrier]: ../../../../evidence/2026-11-08-memoshi-engineering/PythonLifecycle/lifecycle-carrier/
[s6f-hardening]: ../../../../evidence/2026-11-08-memoshi-engineering/PythonLifecycle/hardening-carrier/
[s6f-red-borrow]: ../../../../evidence/2026-11-08-memoshi-engineering/PythonLifecycle/red-prefix-snapshot-realm-lifetime-v3-r5.log
[s6f-summary]: ../../../../evidence/2026-11-08-memoshi-engineering/PythonLifecycle/summary.json
[s6f-round2]: ../../../../evidence/2026-11-08-memoshi-engineering/PythonRound2/summary.json
[s6f-finish]: ../../../../evidence/2026-11-08-memoshi-engineering/PythonFinish/summary.json
[s6f-finish-red]: ../../../../evidence/2026-11-08-memoshi-engineering/PythonFinish/red-d105-realm-lifetime-r3.log
[s6f-finish-green]: ../../../../evidence/2026-11-08-memoshi-engineering/PythonFinish/green-pyodide-spike-tests-r3.log
[s6f-finish-scenario]: ../../../../evidence/2026-11-08-memoshi-engineering/PythonFinish/scenario-post/d105-207420/result.json
