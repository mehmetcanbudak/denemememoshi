# S4 This Mac sandbox without Node: draft report from development evidence

**Status:** **DRAFT, updated 2026-11-06.** Development-Mac evidence, not reference-hardware evidence, a `slice-N` result, the filed `S4-<name>.md` report or a gate verdict. **Production command/file tools remain disabled.** The rejected same-port LAN allowance stays removed. [§4c](#4c-2026-11-04-exact-unix-route-and-verified-https) records the usable exact Unix gateway; [§4e](#4e-installed-toolchain-assets-and-actual-offline-workflows) adds explicit read-only installed-toolchain assets and real offline workflows. H3, generic toolchain networking, complete D96 coverage, kernel attribution and reference qualification remain open. Earlier candidate failures remain historical evidence, not options to retry.
**Owns:** The row-by-row development scorecard for [phase-0 S4](../../plan/phase-0.md#s4) and [06 §12 S4](../../plan/06-computers-and-browsers.md#s4-this-mac-sandbox), the status of D77's fallback order and D96, the open work with owners (Memoshi, Pi_Swift SDK request H3, the user), and a provisional recommendation for the Fri 2026-11-27 gate.
**Depends on:** [D16](../../plan/decisions.md#d16), [D46](../../plan/decisions.md#d46), [D77](../../plan/decisions.md#d77), [D81](../../plan/decisions.md#d81), [D90](../../plan/decisions.md#d90), [D96](../../plan/decisions.md#d96); [phase-0 §1](../../plan/phase-0.md#1-what-phase-0-must-prove), [§5](../../plan/phase-0.md#spikes), [§9](../../plan/phase-0.md#exit-criteria); [06 §3](../../plan/06-computers-and-browsers.md#3-this-mac-sandboxed); the HANDOFF S4 records from the [kernel gate](../../HANDOFF.md#s4-confinement-kernel-gate) to the [consumer follow-through](../../HANDOFF.md#consumer-follow-through-proof); [consumer handoff H3](2026-11-02-pi-swift-consumer-handoff.md#4-h3-guarded-file-service-inside-envdaemonsession-new-untracked); [risks R27](../../plan/risks.md#r27) and [R34](../../plan/risks.md#r34).

## 1. Summary

- **Three D77 candidates failed and stay rejected.** The srt-ordered filesystem prototype and Memoshi's own deny-default profile each passed 31/34 raw and 13/16 real PiEnv probes, failing 3 hard-link cases each. The separate non-admin user (UID 502) with Seatbelt passed 15/18: it read a host-owned `0644` inode through its granted alias by raw read, SDK read and SDK exec. Any escape blocks a candidate.
- **D96's private working copies showed no escape and no unauthorized source effect in any development check:** 4/4 admission cases, 23/23 raw and PiEnv isolation checks and 8/8 durable-policy export scenarios on 2026-10-27; 14/14 grant-backed export scenarios on 2026-11-01; 55/55 native checks against the runtime library on 2026-11-02. Its retained Seatbelt rules did fail 2 environment conformance cases until an exact `/private/var/select/sh` read rule was added on 2026-11-02.
- **No complete S4 gate row is qualified.** The complete guarded external-daemon conformance suite cannot be composed at pin `892585fc` without H3. Cold start, exec overhead, toolchains, remaining D96 races/capabilities and actual privacy attribution remain unqualified.
- **The usable confined-route gap has development proof.** An exact per-computer Unix socket is reachable; another bot's socket, direct TCP/UDP and the Mac's LAN listener at the exact gateway TCP port remain denied. Actual confined curl clients send an absolute proxy target and their per-call capability explicitly. Ordinary proxy-aware clients are not thereby qualified ([§4c](#4c-2026-11-04-exact-unix-route-and-verified-https)).
- **Secret protection has real HTTPS follow-through.** Verified upstream TLS, host-bound injection, recognized response/header/decision scrubbing and rotation protections execute. Nested real Pi calls retain their child/root audit attribution; plaintext credential dispatch is refused before another broker release. The known-encoding/minimum-length limits remain; this is not a universal secrecy claim or production enablement.
- **If the gate were today,** Q6 would fail with no qualified fallback in D77's order, and the stop rule would hold CMP-03 and every ticket that runs bot commands or file tools. Production tools are already disabled ([§9](#9-decision-recommendation-if-the-gate-were-today)).

## 2. Questions and decisions at stake

S4 decides the This Mac computer design in [D16](../../plan/decisions.md#d16) and how it works without Node ([D46](../../plan/decisions.md#d46), [D77](../../plan/decisions.md#d77)). D77 keeps the bot's PiEnv daemon inside a Seatbelt profile with a no-follow guard in the daemon, and fixes the order if S4 fails. [D96](../../plan/decisions.md#d96) amends D16, D77 and [D81](../../plan/decisions.md#d81) for the filesystem workflow only: private working copies with trusted admission and policy-controlled export, without lowering any S4 threshold or waiving the SDK's missing guarded-file-service seam. Phase-0's Q6 is proved by "S4 escape suite: 0 escapes". If it fails, D77's fallbacks apply in order, each only after it passes the full escape suite; if none passes, CMP-03 and every ticket that runs bot commands or file tools waits, and the gate takes a new decision on D16 ([phase-0 §1](../../plan/phase-0.md#1-what-phase-0-must-prove); [risks R27](../../plan/risks.md#r27)).

| # | Question | Development answer so far | Evidence (file → field) |
|---|---|---|---|
| S4.1 | Does the per-bot sandboxed environment start cold in under 300 ms and pass Pi's environment conformance suite? | Cold start was not measured. Through an external sandboxed daemon with D96's rules, 26 registered cases passed, 2 failed and 1 was excluded, against 28 passed and 1 excluded for both the in-process and the unsandboxed-daemon baselines; the 2 failures are classified profile-induced. An exact `file-read*` rule for `/private/var/select/sh` passed both in a targeted rerun; a data-only rule still failed both. The complete suite has not been rerun under the corrected rule. | [initial conformance][env-orig] → `summaries[]`, `classifications[]`; [selector-read rerun][env-sel] → `candidateProfileRevision`, `scope.conformance`, `summaries[0]`; [data-only rerun][env-data] → `summaries[0]` |
| S4.2 | Do `read`, `write` and `edit` run inside the sandbox? Does a daemon guard resolve paths without following symlinks? | In the qualification runs, real `RemoteExecutionEnv` file and exec calls reached a PiEnv `EnvDaemonSession` launched under Seatbelt. The guard cannot be composed: at pin `892585fc`, `EnvDaemonSession` holds `private let files = DaemonFiles()` and exposes only `init(transport:)`. It is requested from Pi_Swift as H3. Product file tools are not composed. | [kernel-gate verification][k-ver] → `sdkIntegration.daemon`, `sdkIntegration.guardGap`; [initial conformance][env-orig] → `scope.guardSeam`; [H3 request](2026-11-02-pi-swift-consumer-handoff.md#42-request) |
| S4.3 | Are live sources, `~/.ssh`, `~/Library/Keychains`, other bot homes and copied `.env` unreadable? Are unsafe writes and links refused? Does export keep original path classes and read-only or revoked authority, with no source effect before approval and conflict checks? | Partly. Under D96, live-source and outside reads and writes were denied through raw, SDK and exec paths; copied `.env` and an uppercase variant were denied while `.env.example` read; symlink, multiply-linked and FIFO inputs and late symlinks were refused; originals stayed unchanged until an approved export. Grant-backed exports kept `.env`, `AGENTS.md`, `.git/config` and `.git/objects/…` protected in Bypass, and deny, read-only, revoke, downgrade, conflict and changed-digest cases exported nothing. The `~/.ssh`, Keychain and other-home canaries ran only against the rejected kernels, where they were denied. The case, normalization and race suite has not run. | [private-copy report][wc] → `admission[]`, `sandbox.checks[]`; [source-grant report][sg] → `scenarios[]`; [own-profile kernel results][k-strict] → `cases[]` |
| S4.4 | Do per-bot network lists leak between bots? Are localhost, the Mac's LAN address, private ranges, `docker.sock` and memoshid's socket blocked? Does a proxy-ignoring tool fail closed? | The exact Unix route now works with explicitly authenticated absolute-form requests. Cross-bot Unix sockets, direct TCP/UDP, owned unrelated sockets, resolution and the same-port LAN listener are denied; a non-Unix-aware curl fails closed. `allowLocalBinding`, actual Docker/memoshid sockets and reference breadth remain open. | [§4c](#4c-2026-11-04-exact-unix-route-and-verified-https), [actual confined run][gw-20261104] |
| S4.5 | Are the pasteboard, `osascript`, `open -a` and `security find-generic-password` blocked while git, npm, pip, cargo and swift work? | Actual raw-profile offline git/npm/pip/cargo/swift workflows now run with explicitly admitted installed assets. Security/osascript spawns and four baseline-reachable Mach lookups are refused; no clipboard contents or service messages were accessed. `securityd` lacked a working baseline, and complete native-capability/H3/reference coverage remains open. | [§4e](#4e-installed-toolchain-assets-and-actual-offline-workflows); [toolchain controls][tools-20261106]; [offline workflows][offline-20261106] |
| S4.6 | Do credential masks inject a token only toward listed hosts, never visible inside? | A confined real curl request reached the owned, certificate-verified HTTPS upstream with its actual credential; the returned/persisted values contained no scanned credential form. Canonical policy refused the plaintext version without another release. Rotation and independent-stream scrubbing also run in the standalone gateway suite. Unknown encodings and remaining reference/full-conformance coverage are not inferred. | [§4c](#4c-2026-11-04-exact-unix-route-and-verified-https), [actual confined run][gw-20261104] |
| S4.7 | Are violations attributed to bot and task? What does the sandbox add to exec latency? Where must the launcher live? | Committed gateway/secret-use metadata and nested child/root attribution have development proof. Writable configured launchers and a Unicode ancestor omission were reproduced and repaired; the final affected suites and direct-write smoke pass. Native Activity has only separately labelled view-only proof. Authoritative kernel-denial mapping and reference exec overhead remain open | [§4c](#4c-2026-11-04-exact-unix-route-and-verified-https); [§4f](#s4-local-boundaries-2026-11-06); [separate-user verification][su-ver] remains historical |

## 3. How to read the verdicts

- **pass**, **marginal** and **fail** follow [phase-0 §5](../../plan/phase-0.md#spikes); every S4 row is a 0/100% count or a single bound, so none has a marginal band. **not run** means no qualifying measurement exists; **(partial)** marks a not-run row that has some sub-results, none of them an escape or an unauthorized effect.
- **The verdicts score D96's private working copies,** the candidate under qualification. The rejected candidates' measured fails are in [§6](#6-fallback-status-d77s-order-and-d96).
- **Development verdicts only.** Phase-0's reference-hardware table gives developers' machines "spread only; never a pass/fail number". Every row still needs the reference box (base 16 GB M1, macOS 27) at one and four concurrent bots ([R34](../../plan/risks.md#r34)), with S4 basics on the 8 GB Mac. An escape counts as a fail on any hardware.
- **Timebox.** A question still open at the end of its timebox counts as a fail for that question.

| Label | Environment | Evidence (file → field) |
|---|---|---|
| DM-k | arm64 development Mac, macOS 27.0.1 (26A434), `/usr/bin/sandbox-exec`; recorded as a developer machine, not reference-hardware performance acceptance (2026-10-26) | [kernel-gate verification][k-ver] → `host`, `date` |
| DM-u | Development Mac; the non-admin `memoshibot` account, real and effective UID 502 (2026-10-27) | [separate-user verification][su-ver] → `identity`, `date` |
| DM-w | Development Mac; UID 501; native build for `arm64-apple-macos27.0` (2026-10-27) | [private-copy verification][wc-ver] → `observedUID`; [compile recipe][wc-compile] |
| DM-r | Development Mac; native executables built for `arm64-apple-macos27.0`, with the host OS build not recorded. The 2026-11-01 driver reused the external descriptor-copy actor; the 2026-11-02 runs linked the production `MemoshiRuntime` archive | [source-grant compile recipe][sg-compile] (`WorkingCopy.swift` input); [recovery verification][rc-ver] → `native.actualProductionRuntimeArchiveLinked`; [recovery compile recipe][rc-compile] |
| DM-e | Development Mac, macOS "Version 27.0.1 (Build 26A434)"; SDK candidate `892585fc8d8be3093b58c34aacffcd4e68c3a8d9` (2026-11-02) | [initial conformance][env-orig] → `host`, `sdkCandidate` |
| DM-g | Development Mac, UID 501, Xcode 27.2 / Swift 6.4.2; SwiftPM debug tests with the fixture executable as the confined daemon; SDK candidate `892585fc` (2026-11-03) | [evidence README][gw]; [sandbox report][gw-net] |
| Reference | Base 16 GB M1 on macOS 27; the 8 GB Mac for S4 basics | No S4 evidence exists |

## 4. Full thresholds (06 §12, S4), candidate: D96 private working copies

| # | Requirement: method → pass | Measured (development) | Verdict | Env | Evidence (file → field) |
|---|---|---|---|---|---|
| 1 | Daemon under the sandbox: the PiEnv daemon under the per-bot profile using only private roots; the complete environment conformance suite through that external daemon, plus independent-copy admission and export fixtures → passes; cold start < 300 ms; no live source capability reaches the daemon | Conformance with D96's rules: sandboxed daemon 26 passed, 2 failed, 1 excluded, against 28 passed and 1 excluded for the in-process and unsandboxed-daemon baselines. The exact `/private/var/select/sh` read rule passed the 2 affected cases (27 excluded); a data-only variant failed both. No complete rerun under the corrected rule; the held signal case never ran. Cold start not measured. No live source capability reached the daemon: 16/16 expected denials held across raw, SDK, exec and proposal-walk checks, 7/7 legitimate controls worked, and admission passed 4/4. The guard seam is absent at the pin | not run (partial) | DM-e, DM-w | [initial conformance][env-orig] → `summaries[]`, `excludedCases`, `scope.guardSeam`, `scope.limitations[0]`; [selector-read rerun][env-sel] → `summaries[0]`; [data-only rerun][env-data] → `summaries[0]`; [private-copy report][wc] → `sandbox.checks[]` (`expectedAllowed`, `allowed`, `mechanism`), `admission[]` |
| 2 | Per-bot network: one sandbox manager with per-bot network lists, chained to the gateway → no list leaks between bots; every request reaches the policy engine | Actual per-conversation computers, explicit Unix-proxy HTTP/HTTPS, foreign-list refusal and raw bypass controls passed. The runtime bridge rechecks current Store/directory authority and applies current network grants; the nested HTTPS run verifies allowed/secret-use facts and plaintext denial. Generic client/toolchain interoperability and reference breadth remain open | development functional proof; full row not qualified | DM-g | [§4c](#4c-2026-11-04-exact-unix-route-and-verified-https); [actual confined run][gw-20261104] |
| 3 | Reads: approved private read roots; deny live sources and outside data; nested and glob secret denies keep original-source classes inside copies → `~/.ssh`, `~/Library/Keychains`, other homes, live source paths and configured copied `.env` all denied | Earlier live-source/private-copy proofs remain. The current raw matrix additionally denies owned synthetic SSH/Keychain/live-source shapes, cross-bot homes/TMPDIRs and configured secret files, with ordinary/template positives. Five requested default-ignorable aliases did not physically exist; none is counted as a denial. No actual private user path was accessed | development partial; full guard/native qualification open | DM-w, DM-r; development Mac 2026-11-06 | Earlier evidence above; [current paired matrix][local-raw-current] and [§4f](#s4-local-boundaries-2026-11-06) |
| 4 | Writes and links: raw and SDK writes outside private roots; unsafe-source admission; staged symlink, hard-link and special entries; immutable export with current `Grant.access`, original path class, authority and conflict checks → no unauthorized original or outside effect; unsafe input and output refused; originals change only after authorized export; full case, normalization and race suite passes | Earlier admission/export/current-grant/conflict proofs remain. New actual filesystem controls cover protected Unicode names, an allowed combining filename with exact proposal bytes, matching-byte/mode descendant replacement, late staged hardlink/FIFO refusal and moved-original-subtree cleanup preservation. Launcher and combining-ancestor mutations were reproduced and repaired. The full concurrent race/CAS suite remains open; controlled source outcomes do not erase raw-profile diagnostic effects | development partial; full race/guard qualification open | DM-w, DM-r; development Mac 2026-11-06 | Earlier reports [wc], [sg] and [rt]; [affected suites][local-focused] and [§4f](#s4-local-boundaries-2026-11-06) |
| 5 | Shared paths: `/tmp/claude`; per-bot `TMPDIR` → no path writable by two bots | The current owned matrix denies both bots the same existing shared pathname/inode, additional shared read/write/create targets and each other's TMPDIR; each bot's private TMPDIR remains writable. These are owned synthetic shared paths, not access to the real /tmp/claude tree | development partial; no full shared-path/product qualification | Development Mac 2026-11-06 | [current paired matrix][local-raw-current]; [§4f](#s4-local-boundaries-2026-11-06) |
| 6 | Mach services: pasteboard, `osascript`, `open -a`, `security find-generic-password` with SecurityServer removed; then git, npm, pip, cargo and swift → all blocked; toolchains work | Actual current raw-profile offline toolchain workflows pass. Four baseline-reachable Mach lookups and the security/osascript executables are denied. The securityd baseline was unavailable; no clipboard-content probe or complete native-capability/H3/reference qualification follows | not run (partial) | Development Mac, 2026-11-06 | [§4e](#4e-installed-toolchain-assets-and-actual-offline-workflows); [toolchain controls][tools-20261106]; [offline workflows][offline-20261106] |
| 7 | Local network: a LAN service bound to the Mac's own IP, with and without `allowLocalBinding`; `docker.sock`; memoshid's socket → all blocked by default | The rejected `localhost:<port>` allowance stays removed. The exact own Unix socket is usable; another bot's Unix socket, both TCP proxy listeners, direct loopback/UDP and an unsandboxed-reachable LAN listener at the exact gateway port are denied. `allowLocalBinding` and the real Docker/memoshid sockets remain untested | development route/bypass proof; full row not qualified | DM-g | [actual confined run][gw-20261104] |
| 8 | Fail closed: a tool that ignores proxy variables → it fails | Ordinary proxy-aware and `--noproxy` direct curl controls fail while the explicit Unix/absolute-target client succeeds. The owned upstream receives only authorized proxy requests; in-sandbox resolution also fails | development functional proof; no generic toolchain claim | DM-g | [actual confined run][gw-20261104] |
| 9 | Overhead: exec latency inside the sandboxed daemon versus unsandboxed → < 50 ms p95 | Not run. The kernel matrix's `elapsedMs` times only the sandboxed probe process, and the conformance durations are single observations the report itself excludes from performance claims | not run | — | [kernel matrix][k-matrix] → `run()`; [initial conformance][env-orig] → `scope.limitations[0]` |
| 10 | Violations: the sandbox's violation log mapped to bot and task → shown in the activity log | The Store/schema/policy bridge emits committed `egress.*` and `secret.used` metadata; a nested Pi HTTPS call verifies matching child task, bot and origin. A bounded native Activity sheet consumes those committed events. Actual UI review and kernel-denial-to-task projection remain open | not run (partial) | DM-g | [§4c](#4c-2026-11-04-exact-unix-route-and-verified-https) |
| 11 | Privacy prompts: trusted admission from a granted `~/Documents/x`, then daemon tools reading its private copy; observe the actual responsible process → one source-access prompt attributed to Memoshi; no invented daemon or TCC attribution | Not run. The folder-management proof exercised the picker and grants, not TCC | not run | — | [folder-management verification][fm-ver] → `limits[3]` |

### 4a. 2026-11-03 egress gateway and environment-hook run

Development evidence on DM-g (this Mac, pinned candidate `892585fc`), not a `slice-N`, gate or reference-hardware result. Synthetic data, an owned scripted model and owned loopback upstreams only; no external network. A test resolver maps synthetic names to public or private addresses; every check runs against that address, then only the connection is delivered to the owned upstream. Raw outputs, commands and scans are in the [evidence folder][gw].
**Historical candidate, not the current profile:** the network allowance described in this subsection was removed after integration reproduced its same-port LAN hole. Its positive controls remain standalone evidence only. §4b records the interim denial-only correction; §4c records the current explicit Unix route.


- **Implementation:** `MemoshiEgress` (one standalone gateway, a loopback listener per computer, per-bot host lists, IP-literal/local-name refusal, post-resolution private/special-range refusal of every answer, connection to the checked address, host-bound HTTP header placeholder replacement and recognized echo scrubbing) and the runtime `env` hook (`RuntimeEnvironmentComposition`, a bot → Computer directory, a lazy Seatbelt-confined PiEnv daemon in the conversation's private working copy, per-call proxy attribution). The current [decision sink](../../../Packages/MemoshiCore/Sources/Egress/EgressGateway.swift) scrubs every string before retaining it in memory/JSONL; that later protection is detailed in §4b, not attributed to this historical run. Development composition only; normal app/helper composition stays `.none`.
- **S1.12:** through real RuntimeAdapter/PiDurable/SQLite, the same tool resolved no computer, then bot A's sandbox in its private copy, and bot B's sandbox in its home, per conversation; the directory was asked for each call and generation.
- **Filesystem rows were not changed by this initial run.** H3 remained missing; the candidate added a network allowance and public TLS-configuration reads.
- **Finding and remaining gaps:** the network allowance was unsafe and is now removed (§4b). A usable confined transport, HTTPS mask injection, ask/Bypass tiers, `egress.*`/`secret.used` audit events and kernel-violation mapping remain open.

### 4b. Integration correction: network denied

**Historical interim correction, superseded by §4c:** this profile denied even the owned gateway. It closed the measured LAN hole but was not a working networked sandbox. The retained observations below describe that revision, not today's Unix allowance. Production composition remains `.none`.

- Installed Seatbelt rejected numeric host rules (`127.0.0.1:<port>` and `127.0.0.1/32:<port>`) with status 65, “host must be * or localhost in network address”. Reusing `localhost` would retain the demonstrated LAN allowance.
- [`SandboxProfile.make`](../../../Packages/MemoshiCore/Sources/Runtime/SandboxComputer.swift) emits no outbound-network allowance. `SandboxComputerTests` runs the actual confined PiEnv daemon and owned listeners: its own proxy, another bot's proxy and a real LAN listener on the exact own-proxy port all return `errno=1` (`EPERM`); direct TCP/UDP/owned Unix-socket probes are denied too. Proxied and proxy-ignoring curl both fail; the upstream receives no request and the gateway records no decision. There is no legitimate allowed-host control from this sandbox.
- Per-call environment selection, private-copy execution and masked environment values still run through real RuntimeAdapter/PiDurable/PiEnv. The earlier 16-test standalone gateway run is historical. The later [retained run][gw-redaction] passed **19 tests in 2 suites**, independently of Seatbelt, including three actual owned upstream/proxy regressions: credential echoes in response field names; denied/normalized decision metadata across active and released credentials; and cold refusal without a broker release. Test-only resolution validates synthetic public-address answers before routing the connection to an owned loopback upstream; no real public upstream is inferred.
- [`EgressUpstreamRelay`](../../../Packages/MemoshiCore/Sources/Egress/EgressProxyHandler.swift) drops response header fields whose **names** contain a recognized credential form (ASCII-insensitive), scrubs values and streams body scrubbing across chunk boundaries. [`EgressDecisionLog`](../../../Packages/MemoshiCore/Sources/Egress/EgressGateway.swift) registers tokens before exposure, placeholders when a client opens and fetched values before forwarding. Gateway-wide protection persists for its lifetime across call revocation, client closure and credential rotation. Every decision string is scrubbed before **both** memory and JSONL retention, and host scrubbing precedes the 255-character cap; unauthenticated/forbidden destinations never cause a broker read.
- **Protection limits:** [`EgressEchoScrubber`](../../../Packages/MemoshiCore/Sources/Egress/EgressSecrets.swift) recognizes its raw, hex, percent, JSON-escaped and base64/base64url forms only when the form is at least six bytes. Unknown/arbitrary encodings are not solved. A broker value never released to the gateway is unknown to it and cannot be scrubbed by value; tokens/placeholders are protected without releasing it. CONNECT is opaque, with no HTTPS mask injection or response-content inspection. These controls are defense in depth, not an end-to-end secret-leak guarantee.
- [The retained real-daemon run][gw-closed] passed the current outbound-denial regressions. Together with the separate 19-test gateway run, this is a bounded security correction, **not** a reduced S4 acceptance criterion or a confined working gateway. It does not qualify allowed-host routing, HTTPS masks, H3, policy tiers, reference performance or production tool enablement.
- **Next prerequisite:** qualify a transport the sandbox can reach without opening the host's same-port LAN service; then rerun both legitimate gateway controls and raw bypass probes. Do not restore the rejected rule or declare networking complete from deny-all results.

### 4c. 2026-11-04 exact Unix route and verified HTTPS

**Current development evidence:** [4 tests in 2 suites passed][gw-20261104], using the actual Seatbelt-confined PiEnv daemon, system curl, RuntimeAdapter/PiDurable/SQLite, owned HTTP/TLS upstreams and a test-only checked-address resolver. No global CA installation, unrelated LAN service or external credential was used. The full environment/guard/reference gate remains open.

- `SandboxComputerTests` resolves no computer, then bot A's private-copy computer and bot B's home computer through real calls. Its raw probes permit only the exact own Unix gateway. A real owned LAN listener at the gateway's exact TCP port is reachable outside the sandbox and returns `EPERM` inside; the same holds for direct loopback, UDP, another computer's gateway and unrelated owned sockets.
- **Client protocol matters:** libcurl documents that [`CURLOPT_UNIX_SOCKET_PATH`](https://curl.se/libcurl/c/CURLOPT_UNIX_SOCKET_PATH.html) ignores proxy options. `--unix-socket` does not apply proxy credentials or create HTTPS CONNECT automatically. The qualified client therefore sends `Proxy-Authorization` and an absolute request target explicitly over that socket. Its target host is still policy-checked. Ordinary git/npm/pip/cargo/swift proxy support is **not** established.
- `SandboxHTTPSNetworkTests` exercises absolute-form HTTPS forwarding through that Unix route, with certificate verification at the gateway and host-bound placeholder release. A direct connection cannot reach the TLS upstream. The bot cannot replace the host-provided public CA. The separate system-curl CONNECT proof uses an **unconfined TCP client**, not a confined command; do not merge those proofs.
- The nested real Pi call records its successful `computer_run`, `egress.allowed` and `secret.used` under the same actual child task/bot/origin, retaining the outer parent call. A subsequent plaintext credential request is refused with `hard_deny.secret_transport`, no second broker release and no second upstream effect. The retained stores/homes/gateway files are scanned for the fixture credential's recognized forms.
- The standalone gateway suite passed **32 tests in 4 suites** in the integrated run, including rotation, independent in-flight response streams, header/body/decision protections, unused-credential refusal, verified TLS and scoped CONNECT. A real rotation regression had first exposed an old-value response leak; per-stream scrubbers now refresh gateway-lifetime protections at header/body/end boundaries without mixing pending body buffers.
- `RuntimeGatewayPolicy` composes both authorization and decision sinks from one Store/directory authority. Current grants are rechecked after awaited authority work; canonical facts use the current fenced call, not a fabricated root task. `egress.*` and `secret.used` schema/Store/Activity code exists. This does not invent kernel-denial attribution or establish the native sheet's visual/accessibility behavior.

**Not closed:** H3 and full guarded-daemon conformance, generic client networking, remaining D96 escape/race/socket/native-capability rows, kernel-to-task logging, TCC/launcher/toolchain usability, reference performance and release enablement. The rejected live-folder/separate-user candidates remain rejected.

### 4d. Durable gateway activity is distinct from kernel attribution

The current source already connects the gateway to durable audit: `RuntimeSandboxHost` uses one
`RuntimeGatewayPolicy` as authorizer and decision sink; the invocation's actual durable Pi task
key binds the per-exec proxy capability; Store writes commit `egress.*`/`secret.used` with the
fenced original caller; committed events reach the bounded native Activity projection. No new
forwarding layer or interpretation of a diagnostic report array is needed for that path.

The [current view-only native review](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-current-9f2ba72a/current-native-smoke.json)
subsequently exercised the actual Activity sheet with explicitly labelled synthetic policy,
tool, egress and secret-use fixtures, including empty/omitted history and keyboard dismissal.
It does **not** turn §4c's separate runtime test into a live authenticated app-to-gateway proof.
That test directly asserts the plaintext canonical policy denial, not a separately reopened
blocked egress row; it does not reopen its Store or connect a native committed-event consumer.
No single existing smoke establishes private copy + real allow/block + reopened audit + native
Activity, and no historical/tamper-verification service is implied by the bounded sheet.

The remaining kernel requirement needs an **authoritative denial identity correlated to the
immutable command/request and daemon/descendant lifetime**. At the adopted pin, transport
exposes the daemon PID and stderr, while ordinary exec exposes output/status rather than that
denial/caller contract. A daemon PID is not one tool call. Nonzero exit, `EPERM` text, child
stderr or a delayed kernel message must not be converted into `policy.decided` or assigned to
the currently active task. H3's injectable descriptor guard is a separate missing prerequisite;
it would not by itself attribute arbitrary descendant kernel events. RT/NAT retain both gaps.




### 4e. Installed toolchain assets and actual offline workflows

The original profile could not read installed Node/Python assets or compiler support libraries.
Installed Xcode wrappers also refused to run without their read-only licence receipt. No licence,
developer selection, account, install or system configuration was changed. `RuntimeSandboxHost`
now accepts explicit canonical existing **read-only toolchain roots** from its trusted host.
The profile grants their reads without lifting protected-secret denies and denies their writes
even when a root is nested inside the otherwise writable bot home; since the ancestor repair
below, that includes moving or replacing the root's ancestors. It reads only the exact
`/Library/Preferences/com.apple.dt.Xcode.plist` receipt, not the preferences directory or a Mach service.
No home-wide discovery or network/Mach allowance was added.

The [retained raw-profile controls][tools-20261106] used canonical installed executable paths,
explicit `DEVELOPER_DIR`, private caches and owned inputs. Git, Node/npm, Python/pip, Rust/Cargo
and Swift ran. The [actual offline workflows][offline-20261106] then exercised a staged Git diff,
an npm script whose owned output bytes matched, pip hashing an owned file, an offline locked
no-dependency Cargo build and a Swift build. Both produced programs actually printed `42`.
All fourteen baseline/confined command records exited successfully; no package installation,
download or external network was attempted. These are raw-profile development observations,
not the complete Pi/H3 daemon suite or generic package-manager proxy compatibility.

The same controls refused outside data, writes to the installed asset root and its protected
`.env`. The permanent actual-PiEnv test additionally covers new-file denial inside such a root,
unchanged existing bytes, an ungranted sibling and an ordinary home-write positive control.
SecurityServer, LaunchServices, Apple Events and cfprefsd lookups succeeded outside and failed
inside confinement; the probe sent no service messages. `com.apple.securityd` failed in both
conditions and is **inconclusive**. Security/osascript executable controls were denied; the
`open -h` baseline itself exited 1. No pasteboard content was read or written.

**Ancestor repair (later 2026-11-06 batch).** A subpath deny protects a spelling, not the
asset's inode. With the exact earlier profile, an [owned raw control][ancestor-red-20261106]
renamed a writable ancestor of a nested read-only root and then overwrote the moved original
(same device/inode); a second tree installed a replacement at the configured spelling. Direct
overwrite, create and root rename stayed `EPERM`, and every matched unconfined operation changed
independently inspected bytes or inodes. The new actual-PiEnv regression
[failed the same way][ancestor-consumer-red-20261106] through `RuntimeComputerHandle.run`.
`SandboxProfile` now also denies `file-write-unlink` on each ancestor's literal path, so ordinary
children stay writable. The [unchanged regression passed][ancestor-consumer-green-20261106] for a
distant-ancestor rename and an immediate-ancestor replacement, with ordinary sibling
create/overwrite/rename/delete under every protected ancestor. [Paired raw vectors][ancestor-paired-20261106]
used identical owned trees: before the repair, ancestor rename, replacement and both
`RENAME_SWAP` directions succeeded; after it, all were `EPERM`. Root/asset swaps, unlink and
hard-link creation were refused by both profiles. This covers these owned vectors only, not
complete D96/H3 path-race conformance.

The original failed asset/Xcode-selection experiments are retained beside the final controls.
H3, remaining D96 path/link/race/native-capability rows, generic client networking,
kernel/TCC attribution and reference cold-start/exec measurements remain required. Later launcher
and Unicode-ancestor work is recorded separately in [§4f](#s4-local-boundaries-2026-11-06).

The [current five Runtime/Seatbelt tests][runtime-20261106] pass with a fresh private evidence
directory: actual per-conversation selection, exact Unix/direct/LAN controls, read-only assets
and nested verified HTTPS/policy/audit. Earlier evidence-writer runs correctly rejected reused
names or a missing parent directory; those harness failures remain retained. Separately, all
42 gateway tests passed after policy was moved before DNS and bodyless encoded-response
metadata was accepted without permitting compressed opaque entities. No deadline or full
acceptance criterion was relaxed.

<a id="s4-local-boundaries-2026-11-06"></a>
### 4f. Launcher integrity, Unicode ancestors and remaining file rows

**Launcher integrity.** An [owned raw control][local-launcher-raw-red] overwrote a configured
launcher nested in its writable bot home; an outside-home launcher was denied. The
[actual PiEnv regression][local-launcher-red] also moved the executable or its parent directory.
The profile now denies writes to the exact executable and removal of every ancestor entry,
while ordinary sibling files remain writable. A second [actual failing run][local-unicode-red]
proved that Character-based slash scanning omitted an ancestor when a filename began with a
combining mark. The shared ancestor walk now uses Unicode scalars, for both launchers and
read-only toolchain roots. [Final affected suites][local-focused] pass all three launcher
cases and the new combining-name toolchain case; the independent [direct-write smoke][local-launcher-smoke]
keeps both configured launcher files byte/identity-identical under Seatbelt while matched
unconfined controls overwrite them. These are owned development fixtures, not signed-launcher
or full external-daemon qualification.

**Host-library D96 controls.** The same affected run passes nine new parameterized cases:
three actual protected Unicode filenames; an allowed template/combining filename whose proposal
retains exact path/text bytes; unchanged versus matching-content/mode descendant replacement;
late staged hardlink/FIFO refusal with safe unlink-only cleanup; and preservation of an admitted
source subtree moved into the private root. The last case records cleanup-required, restores
the source subtree explicitly, and proves a repeated close remembers the failure instead of
retrying cleanup. Original bytes/inodes survive. Replacement timestamps are not equalized:
this proves conflict refusal, not inode-only causality or concurrent syscall-race/CAS safety.
The [final canonical run][local-canonical] also passes whole-admission refusal for protected
secret-spelled and KeyStore directories, preserving their child bytes and identities. These
two host-library cases do not turn the raw directory-profile effects below into passes.

**The raw matrix is not a clean pass.** The [earlier-profile][local-raw-before] and
[current-profile][local-raw-current] runs each exercise 105 cases / 300 workers with matched
unconfined positives, two confined attempts, and independent host bytes/inodes:

| Outcome | Cases per run | Scope |
|---|---:|---|
| Denied with valid controls | 68 | Cross-bot/shared/TMPDIR/outside paths, configured secret files, established case/NFC–NFD aliases and protected link/rename attempts |
| Allowed with verified effects | 25 | Ordinary home/copy/TMPDIR data, template files and readable inert config |
| Requested physical alias not established | 5 | Default-ignorable spellings; not security passes or permission denials |
| Reproducible diagnostic effects | 7 | Four reads/writes under newly constructed secret-spelled directories; three accesses through deliberately preexisting secret/config hardlinks |

Both matrix commands exit **2**, preserving all seven effects. The path-based profile is not
an inode guard or a complete secret-subtree classifier. D96 admission refuses protected input
names and multiply-linked inputs; late staged unsafe objects refuse proposals. These raw
fixtures deliberately bypass admission and do not establish an admitted-original escape, but
neither are they waived or silently relabelled as a zero-escape result. The probe contracts and
complete receipts remain with the evidence. Actual user SSH/Keychain data, another user's home,
real shared scratch and live Docker/memoshid sockets were not touched.

**Remaining boundary.** H3, full external-daemon/file/handle/watch conformance, complete hostile
race/CAS guarantees, native service breadth, generic toolchain networking, immutable kernel
caller/denial correlation, explicit user-granted TCC observation and reference timing remain
open. [Read-only current device discovery][local-devices] returned zero physical Apple devices
and four explicitly simulated rows; it installed/launched/paired/provisioned nothing. No SDK
pin, production composition, permission, account, signing or gate decision changed.

The [final source hashes][local-source-hashes] identify the frozen production/test files.
Probe sources and complete receipts were retained before [removing only this batch's two
owned scratch/compiler roots][local-cleanup]; normal SwiftPM caches, the MLS payload and
the canonical CI root were excluded.

The same [unchanged canonical CI][local-canonical] passed 630 Swift tests and 23 release-tooling
tests, including the actual launcher/Unicode-ancestor regressions and added host-library cases.
The separate raw matrix still exits 2. CI is development integration, not S4 qualification.

### 4g. Bounded pstack follow-through

The [retained case reconciliation](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s4-retained-case-reconciliation.json)
classifies all 105 raw cases without rerunning rejected profiles. It preserves 68 valid
denials, 25 allowed effects, seven diagnostic effects and five unestablished aliases.
The raw exit status remains 2. No admitted-copy or zero-escape conclusion is added.

The [current-source Runtime component](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/runtime-component-bound-cancellation-after-f5a0a28b/working-copy/claims.jsonl)
passes 59 consumer claims for two deterministic private-copy guards. A policy-time source
replacement refuses before export effects while preserving both original objects.
An installed source inode moved into the private tree survives refused cleanup, with
remembered partial outcome and cleanup refusal. Exact-pinned cached support makes this
bounded Runtime-source evidence, not current whole-tree integration.

The [same component's Stop proof](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/runtime-component-bound-cancellation-after-f5a0a28b/stop/claims.jsonl)
binds the computer handle to its invocation signal. The target exits before its effect
barrier is released and produces no effect afterward. A distinct Session conversation
finishes its actual command and effect. D79/D83 unknown-effect recovery remains explicit.
The complete gateway attribution/reopen/offline-replay scenario also passes after the fix.

The later [supported current-source SwiftPM run](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/core_cancellation_races_no_symbols.log)
also passes the two private-copy tests together with Stop and gateway continuity, four tests
in three suites. Its existing build engine disables debug symbols and the index store for
this focused diagnostic. This does not promote the component to full canonical CI or close
any qualification row below.

H3's guarded external-daemon file/handle/watch seam remains unavailable at the unchanged
pin. Last-check-to-syscall races, hostile CAS, multi-file atomicity, native capabilities,
authoritative kernel attribution, TCC and reference rows stay unqualified. Neither raw
diagnostic effects nor the S4 stop rule are waived by these bounded consumer proofs.

## 5. Gate measurements (phase-0 §5, S4)

Values and their fields are cited in §4 and §6.

| Measurement | Pass / fail | 06 rows | Development result | Verdict |
|---|---|---|---|---|
| Escape suite (reads, writes, symlinks, hard links, shared paths, sockets, localhost and LAN, Apple Events, pasteboard, `open -a`, `security`) | 0 escapes and toolchains still work / any escape | 3–7 | Earlier admitted-source slices and exact Unix/network denials remain. Launcher/Unicode-ancestor defects were reproduced and repaired. The current 105-case raw matrix retains seven diagnostic effects and five unestablished aliases; it is not a zero-escape result. Owned shared-path positives/denials and offline toolchain workflows do not qualify H3 or full native/race coverage | not qualified; bounded controls and retained effects in [§4f](#s4-local-boundaries-2026-11-06) |
| File tools outside private home/copies; original source effects | 100% of direct accesses denied inside the sandbox and audited, and trusted export alone may apply the exact currently authorized, policy-approved proposal / any direct allowed access, lowered original path class or unauthorized source effect | 1, 3, 4 | Earlier admitted-source/export controls remain. New D96 cases refuse protected names, changed descendants and late hardlinks/FIFOs, preserving source bytes/inodes and moved source subtrees. Raw fixtures deliberately bypass admission and retain diagnostic effects. Authoritative sandbox-violation audit, the daemon guard and full race/CAS qualification remain absent | not qualified; host-library proof is not daemon conformance |
| Per-bot network lists | No leak between bots; every request reaches the policy engine / any leak | 2 | Explicit Unix HTTP/verified-HTTPS route, per-conversation selection, foreign-list refusal and raw same-port LAN/bypass controls passed on the development Mac | development functional proof; full row open |
| Non-proxy-aware tool | Fails closed / reaches the network | 8 | Ordinary/direct curl fails; the explicitly authenticated absolute-form Unix client succeeds | development functional proof; generic clients unqualified |
| Masked credential | Real value only on egress to listed hosts / visible inside, or sent elsewhere | — (phase-0 S4.6 only) | Real confined HTTPS injection/response secrecy and nested canonical audit passed; plaintext was refused without another release. Standalone rotation protections passed within recognized-form/minimum-length limits | development proof; full reference/conformance gate open |
| Exec latency inside the sandbox versus unsandboxed | < 50 ms p95 / above | 9 | Not measured | not run |

## 6. Fallback status: D77's order and D96

D77 fixes the order if S4 fails: S4's other design by its scorecard, then a separate unprivileged macOS user plus Seatbelt, then a Linux VM only for work that runs on Linux. D96 inserted private native working copies for qualification after the first two had failed.

| Order | Candidate | Measured result | Status | Evidence (file → field) |
|---|---|---|---|---|
| D77, S4's two designs | srt-ordered Swift filesystem prototype | Raw 31/34 and PiEnv 13/16; failed `read_preexisting_hardlink`, `write_preexisting_hardlink` and `rename_hardlink_then_read` (raw) and `exec_hardlink_read` (PiEnv); all 6 positive controls passed; daemon EOF exit 0 | Rejected: any escape blocks, so the fidelity, overhead and maintenance tie-break was never reached. Not a complete srt port | [kernel-gate verification][k-ver] → `candidates[0]`, `scorecard.reason` |
| D77, S4's two designs | Own deny-default Seatbelt profile | Same counts and the same failed cases | Rejected | [kernel-gate verification][k-ver] → `candidates[1]` |
| D77 second | Separate non-admin user (UID 502) plus Seatbelt | 15/18 with Seatbelt against 18/18 without; failed `raw_publicAlias`, `sdk_read_publicAlias` and `sdk_exec_publicAlias`. A read-only gate: no outside-write claim | Rejected | [separate-user verification][su-ver] → `measurements[]`, `verdict` |
| D96 | Private native Mac working copies (amends D16, D77 and D81 for the filesystem workflow) | §4: filesystem and policy slices showed no escape; no S4 row has passed | Under qualification, not accepted | §4 |
| D77 third | Linux VM, only for Linux-compatible work | No evidence | Unprovisioned and unqualified; it would need its own complete zero-escape qualification | [phase-0 S4](../../plan/phase-0.md#s4) |
| Stop rule | None of the above passes | — | Would apply at a gate held today: CMP-03 and every ticket that runs bot commands or file tools wait, the gate takes a new decision on D16, and demo step 5 shows the hold | [phase-0 §1](../../plan/phase-0.md#1-what-phase-0-must-prove), [§8](../../plan/phase-0.md#exit-demo) |

The pinned SDK's own control passed 16/16 cases unsandboxed ([kernel-gate verification][k-ver] → `unsandboxedSDKControl`): the probes worked, so the hard-link accesses were the profiles' to deny.

### 6a. App-owned export and secret-profile controls (2026-11-07)

[D103](../../plan/decisions.md#d103) records the user's strict choice.

Before the change ([evidence](../../../../evidence/2026-11-07-memoshi-engineering/S4Controls/red-p1-p2-p6-p7-attempt2.log)):
- an approved delete or replace destroyed an outside edit made after the final conflict check, and still reported applied;
- all four secret-directory cases were readable and writable in the sandbox;
- 20 of 31 policy secret spellings were readable in the bot home, private copy and toolchain root.

After the change:
- export moves or swaps (`renameatx_np` with `RENAME_EXCL`/`RENAME_SWAP`) and verifies the moved object, restoring it and refusing on a mismatch;
- private cleanup quarantines each entry before removal;
- the profile's secret rules are generated from `SourceSecretSpellings` and cover secret-directory descendants.

The [focused suites](../../../../evidence/2026-11-07-memoshi-engineering/parent-queue/07-s4-suites.log) pass 40 tests in 5 suites. They include coverage for late creates, parent and root swaps, admission swaps, native-service lookups with no Mach message sent, listeners, and real git/Python clients that ignore the Unix route.

The new profile's [real proof](../../../../evidence/2026-11-07-memoshi-engineering/S4Controls/new-profile-proof-attempt2/summary.json) records 0 failures across 108 secret rows, 21 control rows and 14 offline git/npm/pip/cargo/swift workflow rows. The fixed-parameter profile hash moves from `2479e29c…a50e16` to `925fd75e…2cd7f`.

The seven retained raw diagnostic effects stay attached to the earlier profile and the five aliases stay unestablished; neither is reclassified. Kernel limits remain: a writer holding an open descriptor, and multi-file atomicity. No S4 row passes: H3, kernel attribution, TCC and the reference rows are still required.

**Volumes without swap (2026-11-08).** Export now selects its mechanism from the source volume's own capability report (`ATTR_VOL_CAPABILITIES`), never from a path, a file-system name or a call's result alone ([probe][swap-probe]):
- APFS (including `/Volumes/MEW0`, an APFS image stored on the exFAT `/Volumes/Elements`) reports swap and exclusive rename: replace keeps the verified swap.
- HFS+ reports exclusive rename but not swap. Replace now moves the original to an exclusive Memoshi name, verifies it is the admitted original, then renames the replacement exclusively onto the freed name. A changed original is renamed back. A name recreated between the two renames is never overwritten: the original goes back if the name is free, otherwise both objects stay and the Memoshi name is reported. The user's name is briefly absent instead of briefly showing the approved bytes. Before the change, every replace on HFS+ refused.
- exFAT and FAT32 report neither. No race-safe sequence exists there: restoring or installing an object at a name needs `RENAME_EXCL`, `RENAME_SWAP` or a hard link, and none is available, and a held descriptor still reports one link after an unlink. Create, replace and delete therefore refuse before any temporary is created. On FAT32 the probe's `RENAME_SWAP` call returned success and overwrote the destination, and `RENAME_EXCL` onto a free name was accepted as a plain rename. Before the change, the FAT32 delete interleavings ended in partial applications with source effects. [INFERENCE] A FAT32 replace that reached the swap would have overwritten the file at the name, and a create was not exclusive.
- exFAT and FAT32 keep extended attributes, including the OS-stamped provenance, in hidden `._` files that admission already refuses, so folders with files created on this Mac are refused at admission there.

Moved-aside originals now use `.memoshi-export-` names, the only residue names the export journal accepts; an earlier reoccupied delete reported a `.memoshi-delete-` name the journal rejects. The [failing-before][swap-red] and [passing-after][swap-green] runs cover APFS, the MEW0 image, HFS+, the physical exFAT volume, an exFAT image and a FAT32 image with the same late-edit, outside-save and moved-original interleavings: 31 tests and 132 cases in 3 suites pass. The kernel limits above remain. On both the swap and the fallback path, a writer that renames an object onto Memoshi's random moved-aside name after verification can still lose it.

## 7. Marginal results

None. No S4 row has a marginal band in the plan, and no row has a scored measurement yet.

## 8. What remains before the gate

S4 (P0-12) is scheduled for W2, Mon 2026-11-02 to Fri 2026-11-06, and P0-21 depends on it; H3 is needed by the gate pin freeze on Fri 2026-11-13; spike reports are due Wed 2026-11-25 and the gate is Fri 2026-11-27 ([phase-0 §3](../../plan/phase-0.md#team-and-calendar), [H3](2026-11-02-pi-swift-consumer-handoff.md#4-h3-guarded-file-service-inside-envdaemonsession-new-untracked)).

| Work | Rows | Owner | Prerequisite or current state |
|---|---|---|---|
| A public file-service seam in `EnvDaemonSession`, covering every path the daemon resolves, plus daemon conformance hooks | 06 row 1; phase-0 file-tools row | Pi_Swift SDK request H3 | The later SDK delivery note reports tracking/targeting, but no qualifying source/tag is adopted; the accessible request remains the original pointer. See the [2026-11-06 delivery reconciliation](2026-11-02-pi-swift-consumer-handoff.md#current-delivery-reconciliation-2026-11-06) |
| Compose the descriptor-guarded service in Memoshi's sandboxed daemon entrypoint; rerun the complete registered conformance suite under the corrected profile, including the held signal case | 1 | Memoshi | Needs H3. [INFERENCE] The held case kills an owned synthetic process group, which the 2026-11-03 release of Mac kill runs appears to cover ([phase-0 execution hold](../../plan/phase-0.md#team-and-calendar)) |
| Complete confined networking qualification, generic clients and policy/mask breadth | 2, 8; phase-0 network, proxy and mask rows | Memoshi | The exact Unix route, verified HTTPS masks, current-authority bridge and real bypass controls have development proof. Qualify remaining client/toolchain, policy breadth and reference rows without restoring the rejected TCP allowance |
| The complete escape suite against D96: private paths, shared paths, Mach services, LAN with/without `allowLocalBinding`, Docker/memoshid sockets | 3, 5, 6, 7 | Memoshi | Owned shared/private/TMPDIR and earlier network/socket controls ran. The 105-case raw matrix retains seven diagnostic effects and five unestablished aliases (§4f); full guard/native/socket qualification remains open, not a clean pass |
| Complete git/npm/pip/cargo/swift usability inside the profile | 6 | Memoshi; the user if an additional toolchain is required | Actual installed offline workflows now pass (§4e), without installs or configuration changes. Generic networking, complete dependency/build breadth, H3 and reference qualification remain open |
| The full case, normalization and race suite for writes and links | 4 | Memoshi | Actual Unicode admission/proposal, changed descendant, late hardlink/FIFO and moved-source cleanup controls pass (§4f). Full hostile concurrent race/CAS proof required by [runtime verification][rt-ver] → `limits[4]` remains open |
| Complete violation attribution to bot/task and native activity | 10 | Memoshi | Canonical gateway/secret-use metadata and Activity source exist; kernel-denial mapping and actual native-surface qualification remain open |
| The privacy-prompt observation from a granted `~/Documents/x` | 11 | The user grants the folder and answers any prompt; Memoshi observes the responsible process | Not run |
| Reference-box cold start and exec latency (n, p50, p95) at one and four concurrent bots; S4 basics on the 8 GB Mac | 1, 9 | Memoshi; the user provides both machines | No reference-box evidence exists; on 2026-11-03 the user put the reference Macs last ([HANDOFF §8](../../HANDOFF.md#8-next-moves)) |

## 9. Decision recommendation if the gate were today

- **Q6 fails.** The escape suite has not run in full on D96, and every not-run row counts as a fail under the timebox rule. The two kernel designs and the separate user have measured escapes, and the Linux VM is unqualified. The stop rule applies: Phase 1 starts, CMP-03 and every ticket that runs bot commands or file tools wait, and the gate takes a new decision on D16.
- **Keep D96 as the only native candidate.** Carry forward the reproduced/repaired ancestor and launcher defects, bounded positive proofs and retained raw-profile diagnostic effects; they do not qualify the full route. Do not reopen the rejected live-folder kernels or the separate user: their failures were measured, not inferred. The Linux VM covers Linux-compatible work only after its own qualification.
- **Make H3 the deciding dependency.** Without the guarded-file-service seam at the Fri 2026-11-13 gate pin, row 1 and the file-tools row cannot pass, and S4/P0-12 stays open at the gate, as the consumer handoff states. If H3 lands, run the remaining rows before Wed 2026-11-25; cold start and exec latency also need the reference box, which the user put last, so they stay open until it is available.
- **No decision update follows from this evidence.** Production tools stay disabled.

## 10. Evidence notes and discrepancies

1. **No discrepancy found between the JSON reports and the HANDOFF, 06 and phase-0 prose for S4.** The counts in [§1](#1-summary) and [§6](#6-fallback-status-d77s-order-and-d96) match the verification and report fields cited above, as do the provider request counts, report sizes and report SHA-256 values the HANDOFF quotes.
2. **06 §12's D96 paragraph quotes the 50-check limits proof** ([limits output][lm-out]). The later recovery proof ran 55 checks with the same 20 export, 20 limit and 9 metadata cases plus 2 more export scenarios and 3 recovery cases ([recovery output][rc-out]; [recovery verification][rc-ver] → `native.checks`); this supersedes the count and does not contradict it.
3. **Historical kernel-gate passes.** The earliest `~/.ssh`, Keychain, other-home, shared-path, socket and Mach-service denials used synthetic canaries in the rejected live-folder kernels; they do not qualify D96. The later exact-route controls and current owned raw-profile matrix are recorded separately in §4c–§4f, with the seven diagnostic effects and five unestablished aliases retained rather than promoted to passes.
4. **Derived counts.** The 16/16 denial and 7/7 control counts, the applied source-grant scenarios and the report hashes compared with the HANDOFF are retained in the [derived-measurement record][derived].

## 11. Sources

- Memoshi plan: decisions D16, D46, D77, D81, D90 and D96; phase-0 §1, §3, §5, §8 and §9; 06 §3 and §12; risks R27 and R34; the HANDOFF S4, source-grant, folder-management, runtime-copy, metadata, limits, ownership and consumer records; the [consumer handoff](2026-11-02-pi-swift-consumer-handoff.md) §4.
- Evidence outside the repository: `2026-10-26-memoshi-s4-confinement`, `2026-10-27-memoshi-s4-separate-user`, `2026-10-27-memoshi-s4-working-copies`, `2026-11-01-memoshi-source-grants`, `2026-11-01-memoshi-folder-management`, `2026-11-02-memoshi-runtime-working-copies`, `2026-11-02-memoshi-working-copy-metadata`, `2026-11-02-memoshi-working-copy-limits`, `2026-11-02-memoshi-working-copy-recovery`, `2026-11-02-memoshi-consumer-qualification/environment` and `2026-11-03-memoshi-wave3-integration/native` (separate confined-denial and standalone-gateway logs, not one end-to-end pass).

[k-ver]: ../../../../evidence/2026-10-26-memoshi-s4-confinement/verification.json
[k-strict]: ../../../../evidence/2026-10-26-memoshi-s4-confinement/strict-kernel-results.json
[k-srt]: ../../../../evidence/2026-10-26-memoshi-s4-confinement/srt-port-kernel-results.json
[k-matrix]: ../../../../evidence/2026-10-26-memoshi-s4-confinement/kernel-matrix.py
[su-ver]: ../../../../evidence/2026-10-27-memoshi-s4-separate-user/verification.json
[wc]: ../../../../evidence/2026-10-27-memoshi-s4-working-copies/working-copy-results-c67e4ff6-0b72-441d-a1b5-edd3b5c0c91a.json
[wc-ver]: ../../../../evidence/2026-10-27-memoshi-s4-working-copies/verification.json
[wc-compile]: ../../../../evidence/2026-10-27-memoshi-s4-working-copies/compile-command.json
[sg]: ../../../../evidence/2026-11-01-memoshi-source-grants/source-grant-results.json
[sg-compile]: ../../../../evidence/2026-11-01-memoshi-source-grants/compile-command.json
[sg-out]: ../../../../evidence/2026-11-01-memoshi-source-grants/native-output.txt
[fm-ver]: ../../../../evidence/2026-11-01-memoshi-folder-management/verification.json
[rt]: ../../../../evidence/2026-11-02-memoshi-runtime-working-copies/runtime-copy-results.json
[rt-ver]: ../../../../evidence/2026-11-02-memoshi-runtime-working-copies/verification.json
[rt-out]: ../../../../evidence/2026-11-02-memoshi-runtime-working-copies/native-stdout.txt
[md-out]: ../../../../evidence/2026-11-02-memoshi-working-copy-metadata/native-stdout.txt
[lm-out]: ../../../../evidence/2026-11-02-memoshi-working-copy-limits/native-stdout.txt
[rc-out]: ../../../../evidence/2026-11-02-memoshi-working-copy-recovery/native-stdout.txt
[rc-ver]: ../../../../evidence/2026-11-02-memoshi-working-copy-recovery/verification.json
[rc-compile]: ../../../../evidence/2026-11-02-memoshi-working-copy-recovery/compile-command.json
[env-orig]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/environment/original-report.json
[env-sel]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/environment/selector-read-report.json
[env-data]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/environment/data-only-selector-report.json
[derived]: ../../../../evidence/2026-11-03-memoshi-s3-s4-draft-reports/derived-measurements.json
[gw]: ../../../../evidence/2026-11-03-memoshi-env-gateway/README.md
[gw-net]: ../../../../evidence/2026-11-03-memoshi-env-gateway/test-reports/s4-sandbox-network.json
[gw-closed]: ../../../../evidence/2026-11-03-memoshi-wave3-integration/native/focused-core-s4-tests.txt
[gw-redaction]: ../../../../evidence/2026-11-03-memoshi-wave3-integration/native/egress-redaction-tests.txt

[gw-20261104]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/s4-confined-gateway-tests.txt
[tools-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/s4-toolchain-license-read/observations.json
[offline-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/s4-offline-workflows/observations.json
[runtime-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/native-runtime-owned-existing-evidence-2f7d23f7/run.json
[ancestor-red-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-next-caa93544/sandbox/run-a0e6142e-ac4f-4d5a-909c-6838f7f7df5e/report.json
[ancestor-consumer-red-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-next-caa93544/sandbox-consumer-red-e677ff11/command.log
[ancestor-consumer-green-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-next-caa93544/sandbox-consumer-green-34676886/command.log
[ancestor-paired-20261106]: ../../../../evidence/2026-11-06-memoshi-phase0-next-caa93544/sandbox-paired-vectors.json
[local-launcher-raw-red]: ../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/launcher-before/result.json
[local-launcher-red]: ../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/s4-launcher-consumer-red-corrected-cc6dd970/command.log
[local-unicode-red]: ../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/s4-unicode-and-d96-before-55594062/command.log
[local-focused]: ../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/s4-final-focused-8b0d8dd4/run.json
[local-launcher-smoke]: ../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/launcher-final/result.json
[local-raw-before]: ../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/raw-profile-before.json
[local-raw-current]: ../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/raw-profile-current.json
[local-devices]: ../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/device-prerequisite-summary.json
[local-source-hashes]: ../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/changed-source-final.json
[local-cleanup]: ../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/owned-cleanup-result.json
[local-canonical]: ../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/canonical-after-s4-38fb8537/run.json
[swap-probe]: ../../../../evidence/2026-11-08-memoshi-engineering/S4SwapFallback/probe/rename-probe-2026-11-08.jsonl
[swap-red]: ../../../../evidence/2026-11-08-memoshi-engineering/S4SwapFallback/red-race-before-fallback-attempt2-sidecars-removed.log
[swap-green]: ../../../../evidence/2026-11-08-memoshi-engineering/S4SwapFallback/green-suites-after-fallback.log
