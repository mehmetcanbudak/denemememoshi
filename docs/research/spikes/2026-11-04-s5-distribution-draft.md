# S5 distribution, credentials and CI: development scorecard

**Status: DRAFT, updated 2026-11-06. S5 is not qualified.** This records existing development evidence, implemented release controls and remaining acceptance. It is not a signed release receipt, final qualifying spike report or permission to lift an SDK/release hold. Signing, provisioning, reference Macs and the clean VM remain last.

**Owners:** NAT for signing, Apple capabilities, helper lifetime, credentials and physical installs; APP for authenticated transport/native review; QA for measurements and clean-VM/update scenarios. **Authority:** [S5 acceptance](../../plan/phase-0.md#s5), [D46](../../plan/decisions.md#d46), [D56](../../plan/decisions.md#d56), [D58](../../plan/decisions.md#d58), [D67](../../plan/decisions.md#d67), [D84](../../plan/decisions.md#d84) and [09 macOS platform](../../plan/09-platform-macos.md).

## 1. Existing proof is carried forward, not promoted

The [handoff](../../HANDOFF.md) and [build/development boundaries](../../../README.md#build-and-test) retain the separately Apple Development-signed app/helper, authenticated replay and native conversation/credential observations. In particular:

- The provisioned Mac credential proof used an authorized **wildcard development profile**, not separate permanent Developer ID app/helper profiles. It exercised device-only Save/get, purpose refusal, broker-backed local inference, deletion/revocation and scoped privacy checks. The helper did not receive the app's secret-group entitlement.
- The native development helper is **app-owned**. App-owned startup/quit or a signed private development carrier does not establish actual `SMAppService.agent` registration, System Settings approval or helper survival after app replacement.
- Prior authenticated replay and the signed 1,000-cycle development result remain useful transport evidence. They are not notarized peer authorization, reference latency/startup measurements or an update-survival result.
- The current runtime-host lifecycle/approval/Python probes are separately scoped in [S1](2026-11-04-s1-runtime-draft.md) and [S6](2026-11-04-s6-pyodide-draft.md). They do not run through the release helper protocol and cannot fill S5's signing, service or platform rows.

No account sign-in, certificate issuance, capability enablement, profile installation, notarization upload, TestFlight upload or service registration is reported as newly exercised here.

## 2. Implemented release controls are not a release run

[`scripts/release.py`](../../../scripts/release.py) already provides explicit-input commands for release archive/signing, inside-out code signing, separate app/helper profile validation, hardened-runtime/entitlement checks, notarization acceptance/log collection, app/DMG stapling, exact embedded-app verification and internal TestFlight distribution. Source inspection is not evidence that Apple accepted an artifact or a device installed it.

The size workflow records a baseline only from verified actual Developer ID G2/notarized/stapled artifacts. `package` requires either a reviewed baseline or an explicit first-baseline selection; `check-sizes` rejects any measured component above its reviewed ten-percent limit. There is **no measured qualified release baseline in this report**. Debug binaries, the sealed Pyodide payload and synthetic unit-test sizes must not become release budgets.

[`scripts/release-gates.json`](../../../scripts/release-gates.json) still records consumer revision `892585fc8d8be3093b58c34aacffcd4e68c3a8d9`, development-only qualification, no qualifying tag/acceptor/evidence digest, and both release and broader-qualification holds. The recorded upstream freeze is not an accepted consumer cutover. Neither a successful local build nor availability of newer SDK source authorizes release.

## 3. Acceptance disposition

| Row | Current disposition | Required remaining evidence / owner |
|---|---|---|
| S5.1 G2 helper / no JIT | Release validators exist; no qualifying signed Release result here | Actual G2 Developer ID helper, hardened runtime, accepted Code Mode backend/provenance and no JIT/unsigned-memory entitlement; NAT/RT |
| S5.2 separate profiles / CloudKit / push | Optional app-only secret/device groups and separate-profile validation are implemented, not provisioned capability proof | Permanent IDs, distinct app/helper profiles with authorized CloudKit/push, actual embedded profile/expiration validation and production round trip; NAT |
| S5.3 start to `system.hello` | No reference-box series here | Actual signed helper launch-to-ready distribution; do not substitute runtime open/resume or pipe transit; NAT/QA |
| S5.4 service lifetime | App-owned development helper only | Actual `SMAppService.agent` registration/approval, hidden relaunch and quit/SIGKILL/replacement survival; NAT/APP/QA |
| S5.5 clean-VM DMG | Not exercised | Notarized/stapled DMG installed/launched on the prescribed clean VM without Gatekeeper warning, agent registered; NAT/QA |
| S5.6 Documents TCC | Not exercised | Actual prompt attribution from the helper reading a granted project; NAT/QA |
| S5.7 transport | Existing signed development replay carried forward | Release peer/audit-token checks, private run/socket/token permissions and rotation, prescribed reconnect and eight-stream latency qualification; APP/NAT/QA |
| S5.8 broker | Existing provisioned development proof carried forward | Notarized peer authorization, locked/unattended use and device-only semantics without plaintext/environment fallback; APP/NAT |
| S5.9 update | No actual replace/resume result | Drain/checkpoint/replace/resume while work runs, with independent effect ledger proving no loss/duplicate; NAT/RT/QA |
| S5.10 mobile distribution | No physical iPhone/iPad connected in the already recorded read-only discovery | Internal TestFlight install on both prescribed devices, required capabilities and refresh/90-day-expiry handling; NAT/QA |
| S5.11 app-quit CloudKit CAS | Source implementation is not an Apple service receipt | Own-profile helper CAS with app quit; NAT |
| S5.12 windowless push | Not exercised | Content-free push to the windowless helper, or the explicitly recorded prescribed forwarding fallback; NAT |
| S5.13 privacy identity | Not exercised | Actual Files and Folders/Local Network prompt names and usage strings from helper work; NAT/QA |
| S5.14 component budgets | Enforcement/recording code exists; actual budgets absent | Measure every component/installed total/DMG from qualified artifacts, review baseline and prove >10% rejection; NAT/QA |
| S5.15 iCloud Drive | Not exercised; not inferred from ordinary Documents access | Desktop/Documents sync enabled, actual helper prompt identity and continuing granted reads/writes; NAT/QA |
| S5.16 WeatherKit | No framework-or-REST decision made here | Actual authorized Developer ID profile and notarized forecast attempt; record the result and use only the prescribed route; NAT |

## 4. Clean-clone CI and exact-source availability

The [CI workflow](../../../.github/workflows/ci.yml) checks out trusted same-repository code and runs the same [`scripts/ci.sh`](../../../scripts/ci.sh) used locally. The self-hosted runner has explicit `MEMOSHI_PI_SWIFT_SOURCE` and `MEMOSHI_BUILD_ROOT` inputs. The prerequisite gate requires the exact local-only consumer commit and sufficient private POSIX storage; it is not a branch/tag fallback, remote SDK substitution or disk bypass.

The approved encrypted APFS scratch used by this development session establishes a usable local build filesystem, **not** a persistent runner provisioning or clean-clone remote CI receipt. A session-mounted image must not silently become reboot-safe runner infrastructure. Restore the runner's durable exact-source availability and adequate storage, then retain an actual clean-clone remote run. No existing prerequisite or SDK hold is weakened to make that run appear green.

An [earlier canonical attempt](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/canonical-final-5a75792f/run.json)
stopped during Core compilation: SwiftBuild's `mkdtemp` for an internal
`swbuild.tmp.*` directory failed with `No space left on device`. No Core test
verdict or downstream gate pass is inferred from that failed build. The
[actual Foundation probes](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/foundation-temporary-routing.json)
returned the internal per-user temporary directory with either external `TMPDIR`
spelling, with or without a trailing slash. External scratch does not eliminate
that internal-capacity prerequisite.

Only owned completed UI artifacts were relocated: four further raw result bundles,
**273,532,604 file bytes**, joined the earlier six on approved encrypted storage.
[Per-bundle SHA-256 records](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/mobile-browser-ui-7389847d/raw-result-storage.json)
were durably recorded before each of these four originals was replaced by its
retained-path link. The interrupted partial duplicate was replaced only after a
fresh verified copy existed. Keep that encrypted volume mounted; no user files,
SDK clone, global cache, disk floor, test deadline or supported build engine was
removed or substituted. Resumed verification is separate from a clean-clone or
remote CI receipt.

After that owned offload, the [same supported Core build and complete tests](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/core-after-owned-offload-ab473fed/run.json)
passed: **87 Store, 151 Runtime and 32 Egress tests**. The original storage failure
remains retained; this incremental local recovery does not qualify clean-clone
capacity or the full canonical pipeline.

The [current unchanged canonical run](../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/canonical-after-s4-38fb8537/run.json), after the S4 launcher/Unicode-ancestor repairs and added filesystem cases, passed with exit `0` in **9183.36 s**: **630 Swift tests and 23 release-tooling tests**, native MLS/source provenance, tokens, 545-file lint/552-file boundaries, 34 resolved dependency licence occurrences, schema, Mac/universal iOS Simulator builds, sign-in and bundle/notices checks. [Full raw log](../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/canonical-after-s4-38fb8537/ci.log). The [624-test](../../../../evidence/2026-11-06-memoshi-phase0-python-hardening-b0f24d5d/canonical-after-python-hardening-78a0e11b/run.json), [622-test](../../../../evidence/2026-11-06-memoshi-phase0-next-caa93544/canonical-after-ancestor-fix-cbe82d8f/run.json) and [621-test](../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/canonical-native-lint-repaired-859191f4/run.json) runs, the [initial new-code lint failure](../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/canonical-native-integrated-356e0fda/run.json), earlier receipts and compiler/deprecation diagnostics remain; no warning-free claim is made. No assertion, deadline, prerequisite, SDK pin or build engine was relaxed. This incremental development run is not the separate under-five-minute conformance, durable clean-clone/remote, reference or signed-release qualification.


## 5. Closure and existing follow-ups

P0-14/P0-16/P0-20 remain the Phase 0 owners for these measurements and setup; DIST-01/MOD-01 remain their dependent product tickets. This draft creates no invented Apple receipt, size budget, permanent identifier or completed follow-up. Final S5 filing requires the actual measurements, artifact/profile identities and verdicts above. Any formal fallback/carry-over belongs in the Phase 0 gate review, not in a retrospective relabeling of development evidence.
