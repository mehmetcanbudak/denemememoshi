# S3 WebKit bot browser: draft report from development evidence

**Status:** **DRAFT, 2026-11-03.** Scores evidence gathered on the development Mac (`Mac16,6`, macOS 27.0.1 build 26A434) against the plan's S3 rows: signed Apple Development review copies (DM-b, DM-c) and, for rows 3, 7 and S3.7's memory, an ad-hoc-signed WebKit-only review copy (DM-s3). It is not reference-hardware evidence ([phase-0 reference hardware](../../plan/phase-0.md#reference-hardware)), not a `slice-N` result ([D90](../../plan/decisions.md#d90)), not the filed `S3-<name>.md` report and not a gate verdict. Every measured value names its raw file and field.
**Owns:** The row-by-row development scorecard for [phase-0 S3](../../plan/phase-0.md#s3) and [06 §12 S3](../../plan/06-computers-and-browsers.md#s3-webkit-browser), the open work with owners, and a provisional recommendation for the Fri 2026-11-27 gate.
**Depends on:** [D18](../../plan/decisions.md#d18), [D19](../../plan/decisions.md#d19), [D47](../../plan/decisions.md#d47), [D81](../../plan/decisions.md#d81), [D90](../../plan/decisions.md#d90); [phase-0 §1](../../plan/phase-0.md#1-what-phase-0-must-prove), [§5](../../plan/phase-0.md#spikes), [§9](../../plan/phase-0.md#exit-criteria), [§10](../../plan/phase-0.md#cut-list); [06 §8.2](../../plan/06-computers-and-browsers.md#82-webkit-engine); [HANDOFF consumer follow-through](../../HANDOFF.md#consumer-follow-through-proof); [risks R26](../../plan/risks.md#r26) and [R34](../../plan/risks.md#r34).

## 2026-11-04 proxy component security control

The numbered scorecard below preserves the 2026-11-03 review snapshot; its “not built” statements are not an inventory of newer unqualified source. New code is not a new measurement.

**S3.6 is not qualified.** A separate actual public-WebKit experiment tested seven match/exclusion configurations for HTTP CONNECT and the same seven for SOCKS5, with genuine native proxy authentication. Every owned proxy challenge succeeded, yet every direct loopback request reached an independent sink. [Results, independent counters and limitations](2026-11-04-s6-pyodide-draft.md#2a-authenticated-package-route-and-failed-confinement). This is component-level evidence, not the real-site browser/packet-capture suite or a physical-device result. Configured `proxyConfigurations`, `allowFailover = false` and per-launch credentials do not establish confinement; no browser promotion or platform decision follows from configuration alone.

The [2026-11-06 sealed native Python candidate](2026-11-04-s6-pyodide-draft.md#2c-sealed-native-http-route-2026-11-06-development-control)
does not repair this arbitrary-page browser route. Its fixed controller keeps direct Worker
networking blocked and forwards admitted HTTP data to a native owner; ordinary websites
cannot be confined by treating a fetch shim or hostname content rule as the network boundary.
S3's all-traffic/QUIC/DNS and physical/browser acceptance rows remain held.

### Current source inventory, not additional qualification

The later implementation includes the Mac's `BrowserTaskRunner`, native recipe approval, an app-only Keychain broker, exact-document interaction/form checks, staged one-use uploads, quarantined downloads and `WKJSHandle` frame targeting. These are source capabilities, not newly observed acceptance results. Review results are separate from the normal bot tool/transcript path; normal runtime tools remain disabled.

The committed `spikes/S3-webkit-browser/owned-fixture-suite.json` has **eight tasks on two owned loopback fixture origins**, including explicit positive/denial controls; `read-only-fixture-suite.json` has one denied POST task. Neither is the required twenty-task/five-real-site corpus, and neither supplies a real test account. The exact approved real origins/workflows, owned-account authorization, allowed form/download effects and thirty-real-page snapshot corpus remain missing inputs. Generic recipe success ratios, declared `realSiteCount` and expected-denial successes must not be relabelled as S3.3's score.

The mobile source now has two durable **owned review-profile identities** for the explicitly credential-free loopback fixture only. It uses `WKWebsiteDataStore(forIdentifier:)`, checkpoints probe expectations before cookie writes, reads later checks without rewriting probes, and refuses a corrupt/aliased registry rather than silently adopting replacement identities. Sign-in and network sessions remain ephemeral; no bot-to-browser mapping or persistent secret-bearing session is claimed. An explicit Debug-only `-MemoshiDevelopmentBrowserReview YES` root constructs the browser review without `MobileEngineHost`, the runtime or a broker. Work still stops when inactive.

The actual Debug app now builds and runs on a newly owned iPhone 14 Pro Simulator. Its first builds exposed a flat Pyodide resource-bundle signing failure and `DevicePairingFeature` using `#bundle` without package resources. The repaired bundle passes strict signature verification, and the complete English package catalogue passes its actual compiler and Foundation interpolation smoke. The live fixture then exposed Network.framework listener startup without a connection handler; registering the handler before `start` repairs the observed `EINVAL`. The initial-root/snapshot and wrong-typed-registry refusal UI cases subsequently passed **2/2**. The isolated root's owned container had no normal engine-store directory. [Build and initial UI evidence](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/mobile-browser-ui-7389847d/).

The actual native controls now retain these separate observations; their containing runs are not relabelled as an all-green mobile suite:

| Owned Simulator control | Observed boundary | Exact containing result |
|---|---|---|
| Two original cookie probes across terminate/relaunch | Both profiles retained their own probe without reseeding or accepting the other's cookie | [Lifecycle: 1 passed / 1 failed overall](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/mobile-browser-ui-7389847d/lifecycle-controlled-outcome.json) |
| Native tap | Page count became one; page reported `click trusted`; isolated observer recorded five trusted target events | Same lifecycle result; its later upload assertion failed |
| Actual keyboard | `owned-42` reached the text field; page reported `input trusted`; isolated observer recorded 39 trusted target events among 40 observed events | [Keyboard/importer/history: 2 passed / 1 failed overall](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/mobile-browser-ui-7389847d/keyboard-history-outcomes.json) |
| Native history back | The corrected public delegate recorded `historyNavigationDenied`; the second document stayed live and the first was not resurrected | [History/upload: 1 passed / 1 failed overall](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/mobile-browser-ui-7389847d/history-pass-upload-outcomes.json) |
| Explicit staged file and revocation | Real Files selection delivered one 29-byte private copy; a second tap and new handoff could not reuse it; Home/foreground and profile switch revoked pending authority | [Native delivery/revocation: 2 passed / 0 failed](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/mobile-browser-ui-7389847d/trusted-native-file-activation-and-revocation-summary.json) |

Selecting a file input's **label** initially armed a handoff instead of rejecting an unstaged upload. Shared action classification now follows the actual associated control, preserving submit method/destination/payment policy while leaving independent nested links independent. The actual native label-refusal/importer case subsequently [passed](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/mobile-browser-ui-7389847d/label-policy-and-native-importer-after-summary.json). Its failing-before captures remain retained.

The owned file first reached private app staging through the real Files importer, but native delivery failed with `pickerMismatch`. A separate actual-WebKit regression proved the old focus-based check incorrectly authorized a merely focused file input and a programmatic click. The replacement consumes one observed **trusted activation of the currently marked file control**, resetting it on a new snapshot/mark or intervening observed event; origin, document, revision and private-staging guards remain intact. [Failing-before observations](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/mobile-browser-ui-7389847d/file-activation-before.json), [four passing component tests](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/mobile-browser-ui-7389847d/file-activation-component-after.json) and the subsequent rebuilt mobile delivery/revocation pass above retain their distinct scopes. The owned Simulator and temporary app/scientific drivers were removed after proof; their reproduction source, screenshots, hierarchies and [cleanup receipt](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/mobile-browser-ui-7389847d/owned-scenario-cleanup.json) remain.

The internal volume subsequently filled before a diagnostic test could run. Only owned completed raw result bundles were relocated after byte-tree identity checks; local images/hierarchies remain, and the original raw-result paths resolve through the approved encrypted APFS volume. [Storage/recovery manifest](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/mobile-browser-ui-7389847d/raw-result-storage.json). Keep that volume mounted for those raw bundles; this is not durable remote-runner provisioning.

These are owned credential-free Simulator controls, not provisioned sign-in authority, actual granted browser continuation, normal tool/policy/transcript integration or physical iPhone/iPad acceptance. The proxy failure above remains disqualifying.

### Current Mac API and owned download controls

The current Mac build exposed obsolete `WKDownloadRedirectPolicy` / authentication-delegate spellings and the runner's stale `.select` argument labels. The callers now use the installed public SDK signatures, without changing redirect grants or credential dispositions. [Mac and universal iOS Simulator app builds passed](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/apps-native-contracts-after-675fd1e7/run.json); this is a development build, not signed release qualification.

A separate engine-free carrier compiled the **actual twelve browser implementation files**, using a fresh ad-hoc bundle identity, physically verified owned home, unique profile IDs and two owned loopback origins. The real task runner selected **Beta**, matched the snapshot's option label and independently read DOM value **`blue`**. Direct and same-origin-redirect downloads produced the exact 23-byte files; the ungranted cross-origin redirect failed without reaching its independent sink. A Basic challenge used no credential: its exact 36-byte unauthenticated 401 body was quarantined, not treated as proof of a successful login. Every completed file had mode `0600`. [Actual runtime result](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-browser-api-97f04cb0/attempt-5/result.json), [independent request counters](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-browser-api-97f04cb0/attempt-5/fixture-stats.json), [actual visible-page image](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-browser-api-97f04cb0/attempt-5/owned-browser-page.png).

Selector presence and WebKit's default rejection were **not** used as callback-entry proof. Verified debugger logpoints in the unchanged controller observed **two redirect entries and one authentication entry** in the separately retained second attempt. [Callback output](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-browser-api-97f04cb0/attempt-2/callback-output.json). Earlier disposable assertions incorrectly expected a DOM value instead of the snapshot label, whole-download cancellation instead of an unauthenticated 401 body, and a `.txt` suffix on an extensionless response. Those failures remain retained; no product assertion or timeout was weakened. A later debugger attachment produced no runtime verdict and is also retained, rather than counted as a passing case.

The original in-process store removal was refused as still in use. A fresh identically isolated process subsequently initialized/released and removed **only the five exact recorded owned UUIDs**, without enumerating other stores. [Actual cleanup receipt](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-browser-owned-store-cleanup-dd79ea80/command.log). These controls do not qualify real-site success, broker-backed authentication, all-traffic gateway confinement, reference performance or physical-device rows; normal runtime tools remain disabled.


## 1. Summary

- **Closed windows: the gate case is marginal and its cause is known; 06's fallback passes on this Mac.** WebKit aligns a hidden page's repeating timers to one second whatever `inactiveSchedulingPolicy` says, so a 10 Hz timer in a view with no window runs at exactly 1 Hz (10 s windows 0.999–1.001 Hz); run-b's 0.918–0.968 Hz values are quantization of that 1 Hz timer. In the visible one-point host window that bot runs now use, an 11-minute closed-window run held p50 9.952 Hz, minimum 8.755 Hz, over a 658 s continuous span sampled every second, with 659/659 snapshots ([§6](#6-raw-measurements)).
- **Sign-in fill with a canary: pass on this Mac (development path).** A development sign-in Card filled a harness canary into the offline lab page from the isolated world; the page's own script received both values; a scan of the run's home, stores, report, preferences, unified logs and crash reports found 0 hits. A Card whose page had navigated filled nothing. The Keychain broker and real sites are still absent.
- **Partial evidence, with no leak and no failure:** two review profiles kept their own probe cookie across a normal relaunch and saw none of the other's; three on-screen native actions delivered 59/59 trusted key and mouse events; one opaque-origin frame was snapshotted and clicked by script; five moves between the review window and no window kept the same document. Per-profile WebContent memory is now measured: 16–20 MB parked, 36–38 MB live, 68–69 MB in the visible host during a run.
- **Not run:** the 20-task suite on 5 real sites, 30-page snapshot timing, the Safari check, hidden-host native input, gateway routing and packet capture (no gateway exists), the `willSubmitForm` gate, and every iPhone and iPad row.
- **If the gate were today,** the timebox rule would turn the open rows into fails and Q5's recorded fallback would apply: foreground-only WebKit browsing on This Mac. This draft recommends running the open rows in W4 rather than taking the fallback early ([§10](#10-decision-recommendation-if-the-gate-were-today)).

## 2. Questions and decisions at stake

S3 decides the This Mac half of [D18](../../plan/decisions.md#d18) (one persistent `WKWebsiteDataStore(forIdentifier:)` per bot behind one tool API, sign-in Cards that fill credentials straight into the page, page content as untrusted input) and of [D19](../../plan/decisions.md#d19) (live view, Take over and Hand back, detachable views), plus the iOS store basics ([phase-0 S3](../../plan/phase-0.md#s3)). Row 13 also exercises [D81](../../plan/decisions.md#d81)'s random per-launch credential for WebKit's local proxy port. Phase-0's Q5 is proved by "S3 thresholds met on the Mac; the iOS store check passes". If it fails, Phase 1 starts with foreground-only WebKit browsing on This Mac, and background browsing waits for Chromium with Bot computers in v1.1 ([phase-0 §1](../../plan/phase-0.md#1-what-phase-0-must-prove); [risks R26](../../plan/risks.md#r26)).

| # | Question | Development answer so far | Evidence (file → field) |
|---|---|---|---|
| S3.1 | Does each bot get a persistent store that survives restarts, with bot A's cookie invisible to bot B? | On the Mac, partly yes: 2/2 review profiles met expectations with 0 foreign, 0 missing and 0 unreadable probes. After a normal Quit and relaunch, both still held their own probe and no other profile's; that result exists only as an AX capture. Safari and iOS were not checked. | [run-b report][rb] → `rows[0].evidence`, `isolationChecks[0].observations[]`; [run-b AX after relaunch][rb-relaunch] |
| S3.2 | Can isolated-world scripts snapshot, click, type, scroll and select? Do synthesized `NSEvent`s arrive trusted? | On screen and on synthetic pages, yes: 3 native actions on 2 page hosts delivered 59/59 trusted target key and mouse events. Script clicks arrive untrusted, as designed; script select and scroll completed. No hidden-host native input was run, and a view in no window cannot receive `NSEvent`s. | [run-c report][rc] → `rows[1]`, `actions[].observed[]`, `actions[].verified` |
| S3.3 | What share of 20 scripted tasks on 5 real sites succeeds? | Not run: the review lab has no task runner and blocks submissions and downloads. | [run-b report][rb] → `rows[2]` |
| S3.4 | Does a sign-in Card fill from the Keychain broker, with the secret absent from transcript, logs and model context? | On the Mac, through a development Card and a harness canary rather than the broker: the fill reached the page (its script's SHA-256 digests matched both values), both fields were masked afterwards and the next snapshot held no canary; 0 scan hits across the run's home, WebKit stores, report, preferences, unified logs and crash reports. A Card whose page navigated filled nothing (`pageChanged`). No transcript or event log exists in this WebKit-only run, and the broker is not built. | [DM-s3 report][s3r] → `signIns[]`, `rows[S3.4]`; [file scan][s3-filescan] and [log scan][s3-logscan] → `hits` |
| S3.5 | Does a `WKWebView` in no window keep timers, navigations and scripts running with only the menu bar extra left? | Detached: yes, but WebKit aligns its timers to 1 s (row 3, marginal). In 06's fallback, the visible one-point host window, timers ran unthrottled for 11 minutes with every window closed (pass on this Mac). Reopening through the menu-bar extra reattached the same document without a reload. | [DM-s3 report][s3c] → `backgroundRuns[]`, `runSummaries[]`; [derived values][s3-derived]; [run-c AX reopen][rc-reopen]; [run-c menu-bar action][rc-extra] |
| S3.6 | Do `proxyConfigurations` route every request through the egress gateway? | Not run: no gateway exists and the lab sets no `proxyConfigurations`. | [run-b report][rb] → `network`, `rows[5]` |
| S3.7 | Can the same view move into the inspector without reloading? What does each profile cost in memory? | In the review lab, 5/5 moves kept the same document and none replaced it (3 in run-b, 2 in run-c); Take over held lab actions and Hand Back restored them. Each profile has its own WebContent process: 16–20 MB phys_footprint parked, 36–38 MB live, 68–69 MB in the visible host during a run; the GPU process (shared) is 215–220 MB while any page is visible and 11 MB when none is; Networking 7.4 MB. | [run-b report][rb] and [run-c report][rc] → `rows[9].evidence`, `hostMoves[].result`; [memory readings][s3-memory] → `rows[]` |
| S3.8 | On iPhone and iPad, are two bots' logins kept apart across relaunches, and how long does background automation run? | Not run. | [run-b report][rb] → `rows[10]` |

**Related development finding.** Removing an owned profile's store before any WebKit store was initialized crashed inside WebKit (`EXC_BAD_ACCESS`, fault address `0x48`, queue `com.apple.WebKit.WebsiteDataStoreIO`). The fixed path initializes and releases that exact store first and enumerates no other store; a cold removal in the signed app then removed only the owned profile and left the app running ([crash summary][crash-before] → `exception`, `faultAddress`, `faultingQueue`, `candidateRemedyProof`; [run-d removal][rd-removal] → `profileAbsentFromNativeList`, `otherStoresEnumerated`, `appRunning`). It bears on [per-bot store cleanup](../../plan/06-computers-and-browsers.md#89-profile-persistence-and-cleanup), not on an S3 row.

## 3. How to read the verdicts

- **pass**, **marginal** and **fail** follow [phase-0 §5](../../plan/phase-0.md#spikes): a marginal value lies between the pass and fail bounds, and rows whose bounds meet have no marginal band. 06 §12 lists only a pass bound and a fallback, so its rows take their fail bound from the matching phase-0 row. **not run** means no qualifying measurement exists; **(partial)** marks a not-run row that has some sub-results, none of them a leak or a failure.
- **Development verdicts only.** Phase-0's reference-hardware table gives developers' machines "spread only; never a pass/fail number". Every Mac row still needs the reference box (base 16 GB M1, macOS 27) at one and four concurrent bots ([R34](../../plan/risks.md#r34)), with S3 basics on the 8 GB Mac; iOS rows need the iPhone 14 Pro and the iPad Pro 12.9-inch (M1). A leak would count as a fail on any hardware.
- **Timebox.** A question still open at the end of its timebox counts as a fail for that question.

| Label | Environment | Evidence (file → field) |
|---|---|---|
| DM-b | Development Mac `Mac16,6` with 38,654,705,664 bytes of memory, macOS "Version 27.0.1 (Build 26A434)"; signed Apple Development review copy with hardened runtime, app 0.1.0 (1); WebKit inactive scheduling policy `none`; launched 2026-11-02T21:12:10Z | [run-b report][rb] → `environment`, `backgroundRuns[0].scheduling`, `launchStartedAt`; [run-b signing][rb-sign] → `hardenedRuntime`, `profileKind`; policy mapping in [`BrowserReviewModels.swift`][lab-models] (`BrowserSchedulingPolicy`) |
| DM-c | The same Mac and OS; a separate signed review copy; launched 2026-11-02T22:52:00Z | [run-c report][rc] → `environment`, `launchStartedAt`; [run-c signing][rc-sign] |
| DM-s3 | The same Mac and OS; the working-tree Debug build re-signed ad hoc as a WebKit-only copy with its own preferences domain and isolated home (no helper, Keychain or profile); inactive scheduling policy `none`; launched 2026-11-03T10:44:29Z and 10:51Z | [copy record][s3-copy] → `signing`, `preferencesDomain`; [DM-s3 report][s3c] → `environment` |
| Reference | Base 16 GB M1 on macOS 27; iPhone 14 Pro on iOS 27; iPad Pro 12.9-inch (M1) on iPadOS 27 | No S3 evidence exists |

[INFERENCE] Both signing records list `Contents/MacOS/Memoshi.debug.dylib` (`signedMachOFiles`), which points to a Debug build; timing rows should be repeated on a Release build.

## 4. Full thresholds (06 §12, S3)

Rows 1–9 run on the Mac and rows 10–14 on iPhone and iPad.

| # | Requirement: method → pass | Measured (development) | Verdict | Env | Evidence (file → field) |
|---|---|---|---|---|---|
| 1 | Task success: 20 scripted tasks on 5 sites (search, form, test-account login, pagination, download) → ≥ 90% | Nothing measured. The lab has no task runner and blocks form submissions and downloads | not run | DM-b | [run-b report][rb] → `rows[2]` (`status` `unavailable`) |
| 2 | Trusted input: `NSEvent` clicks and keys checked against `event.isTrusted` on 3 pages, on- and off-screen → true in both | On screen: 3 native actions (2 clicks and one typing of 21 characters) on 2 synthetic page hosts, `lab.memoshi.invalid` and `127.0.0.1`; 59/59 target key and mouse events trusted. Off-screen, in a hidden host window: 0 actions | not run (partial) | DM-c | [run-c report][rc] → `rows[1].evidence`; `actions[2]`, `actions[10]`, `actions[14]` → `observed[]`, `textLength` |
| 3 | Closed windows: timer page and automation loop for 10 min with all windows closed → timers ≥ 1 Hz; `takeSnapshot` works off-screen | Detached (gate case), 1 s sampling for 3 min: 178 samples, rate p50 1.000 Hz, min 0.931 Hz, 80/178 below 1 Hz, every 10 s window 0.999–1.001 Hz; snapshots 178/178. Run-b (5 s sampling, 10 min): min 0.918, median 0.968 Hz, 115/115 snapshots; its rates are 5 or 6 ticks per 5.04–5.47 s period, one tick a second. Fallback, visible one-point host window, 11 min, 1 s sampling, navigation each minute: 659 samples, min 8.755, p50 9.952, p95 10.064 Hz, 0 below 1 Hz, continuous span 658.0 s, image and DOM snapshots 659/659, 11/11 navigations, gaps 0.98–1.02 s | **marginal** detached: exactly the 1 Hz bound, 10× slower than the page asked. **pass** for 06's fallback on this Mac | DM-b, DM-s3 | [DM-s3 report][s3c] → `backgroundRuns[]`, `runSummaries[].cases`, `rows[S3.5]`; [derived values][s3-derived]; [probe][s3-probe] → `rows[]`; [run-b report][rb] → `backgroundRuns[0].samples[]` |
| 4 | Snapshot speed: p50 over 30 real pages → < 300 ms | Spread only, on synthetic pages; no real page. Run-b: 1 manual snapshot, 80.97 ms. Run-c: 3 manual snapshots, 3.70–6.38 ms (the report's p50 is 4 ms). 115 detached DOM snapshots of the 9-element lab page: p50 2.40 ms, p95 7.66 ms | not run | DM-b, DM-c | [run-b report][rb] → `snapshotTimings[].durationMs`, `samples[].domSnapshotMs`, `samples[].domSnapshotElements`; [run-c report][rc] → `snapshotTimings[].durationMs`, `rows[4].evidence` |
| 5 | Profile isolation: cookie set in bot A; check bot B and Safari → invisible to both | Bot to bot on the Mac: 2/2 profiles met expectations with 0 foreign probes; after a normal relaunch each kept its own probe and saw no other (AX only). Safari not checked | not run (partial) | DM-b | [run-b report][rb] → `rows[0].evidence`, `isolationChecks[0].observations[].foundForeignProbe`; [run-b AX after relaunch][rb-relaunch] |
| 6 | Proxy coverage: packet capture while browsing 20 sites → 100% through the gateway; no direct QUIC or DNS | No gateway and no `proxyConfigurations`; requests go direct | not run | DM-b | [run-b report][rb] → `network`, `rows[5]` |
| 7 | Secret safety: fill a sign-in, then search transcripts, event log, unified logs and crash reports → zero hits | Development Card fill of a harness canary on the offline lab page: page digests matched, read-back equal, 2/2 fields masked, verification snapshot without the canary. Scan of the isolated home (WebKit stores, saved report), the preferences domain and the `/var/folders` cache: 17 files, 620,164 bytes, 0 hits; unified log (all processes, info and debug, launch to exit + 60 s, 186.6 MB): 0 hits; no crash report. No transcript or event log exists in this WebKit-only run | **pass** for the development path on this Mac; the broker fill is not built | DM-s3 | [DM-s3 report][s3r] → `signIns[]`; [file scan][s3-filescan] → `report.hits`; [log scan][s3-logscan] → `hits`, `coverage` |
| 8 | Frames: cross-origin iframe snapshot and click (frame registration; `WKJSHandle` on 27) → works | 1 snapshot included the registered opaque-origin `data:` subframe, and 1 script click completed inside it. No cross-site frame on a real page; `WKJSHandle` not used; native input inside frames not mapped | not run (partial) | DM-c | [run-c report][rc] → `rows[7]`; `actions[0]` → `frame`, `path`; frame source in the [lab page][lab-script] |
| 9 | Form gate: `willSubmitForm` blocks a POST on a site without `interact` → blocks | Not exercised: `willSubmitForm` and `browser_site` interact grants are not integrated. The lab blocks every form navigation and refused 2 submit-control actions | not run | DM-c | [run-c report][rc] → `rows[8]`; `actions[5]`, `actions[6]` → `error` (`submitControlBlocked`) |
| 10 | iOS: tasks and isolation. Rows 1, 5 and 7 on iPhone and iPad → as on the Mac | Not run | not run | — | [run-b report][rb] → `rows[10]` |
| 11 | iOS: input. A trusted input path, otherwise DOM events checked against `event.isTrusted` on 3 pages → the 20 tasks of row 1 reach ≥ 90% with the path found | Not run | not run | — | [run-b report][rb] → `rows[10]` |
| 12 | iOS: background. Timer page and automation loop for 10 min with the app in the background, inside a `BGContinuedProcessingTask` → timers ≥ 1 Hz; snapshots work | Not run | not run | — | [run-b report][rb] → `rows[10]` |
| 13 | iOS: proxy. `proxyConfigurations` pointing at the app's loopback proxy, with its per-launch credential; packet capture while browsing 20 sites → every request reaches the proxy | Not run | not run | — | [run-b report][rb] → `rows[10]` |
| 14 | iOS: uploads. A page's file input with and without a staged `browser_upload` → only staged files reach the page | Not run | not run | — | [run-b report][rb] → `rows[10]` |

## 5. Gate measurements (phase-0 §5, S3)

Values and their fields are cited in §4.

| Measurement | Pass / fail | 06 rows | Development result | Verdict |
|---|---|---|---|---|
| Task success (20 tasks, 5 sites) | ≥ 90% / < 90% | 1 | Not measured | not run |
| Trusted input on 3 test pages, on- and off-screen | `isTrusted` true in both / fewer | 2 | On screen 59/59 on 2 page hosts; off-screen none | not run (partial) |
| Page snapshot (30 real pages) | p50 < 300 ms / above | 4 | Synthetic spread only | not run |
| Store isolation and persistence (bot A's cookie checked in bot B and Safari), Mac and iOS | Invisible to both / any leak | 5, 10 | Mac bot to bot: 0 leaks, kept across a relaunch; Safari and iOS not checked | not run (partial) |
| Requests through the gateway (packet capture over 20 sites) | 100%, no direct QUIC or DNS / any leak | 6 (13 on iOS) | No gateway | not run |
| Canary secret after sign-in fill (transcripts, event log, unified logs, crash reports) | 0 hits / any | 7 | Development Card and harness canary: 0 hits in files and unified logs; no transcript or event log in this run | **pass** (development path) |
| Timers and automation with all windows closed | Timers ≥ 1 Hz for 10 minutes; off-screen `takeSnapshot` works / stop or throttle so tasks fail | 3 | Detached: exactly 1 Hz (p50 1.000, 10 s windows 0.999–1.001). Visible one-point host: p50 9.952, min 8.755 Hz over 658 s; snapshots 659/659 | **marginal** detached; **pass** with 06's fallback |

## 6. Raw measurements

Closed-window run on DM-b: 10 minutes, 5 s sampling, navigation included (`backgroundRuns[0].configuration`), from 2026-11-02T21:44:50Z to 21:54:52Z (`startedAt`, `endedAt`), all in the [run-b report][rb]. Percentiles are nearest-rank, computed from the named field; the computed values, with the source file's SHA-256, are retained in the [derived-measurement record][derived].

| Series (field) | n | Min | p50 | p95 | Max |
|---|---:|---:|---:|---:|---:|
| Timer rate, Hz (`samples[].timerHz`) | 115 | 0.918 | 0.968 | 1.934 | 2.157 |
| Timer rate, Hz, without the first sample after each timer start or restart (`timerHz`, `documentChanged`) | 105 | 0.918 | 0.958 | 1.153 | 1.195 |
| Image snapshot, ms (`samples[].imageSnapshotMs`) | 115 | 0.981 | 2.836 | 12.861 | 19.928 |
| DOM snapshot, ms (`samples[].domSnapshotMs`) | 115 | 0.489 | 2.401 | 7.655 | 43.733 |

The 10 samples at or above 1.5 Hz are exactly the first sample of the run and the first sample after each of the 9 navigations, which restart the timer probe ([`BrowserReviewLab.swift`][lab-run], `takeSample`). All 115 samples report `documentVisibility` `hidden`. The earlier inference is now confirmed: run-b's timer fired once a second (hidden-page alignment), and multiplying each `timerHz` by its sampling interval gives 5 ticks (74 samples) or 6 ticks (22) over 5.04–5.47 s, so the sub-1 Hz values are quantization ([derived values][s3-derived]).

Closed-window runs on DM-s3, 2026-11-03, every app window closed, 1 s fixed-cadence sampling, navigation once a minute ([DM-s3 report][s3c] → `backgroundRuns[]`; recomputed in the [derived record][s3-derived]):

| Case (field) | n | Min | p50 | p95 | Max | Span |
|---|---:|---:|---:|---:|---:|---:|
| Visible one-point host, 11 min, rate Hz (`samples[].timerHz`) | 659 | 8.755 | 9.952 | 10.064 | 10.284 | 658.0 s |
| Detached, 3 min, rate Hz (`samples[].timerHz`) | 178 | 0.931 | 1.000 | 1.008 | 6.326 | 177.0 s |
| Detached, 3 min, 10 s windows from `samples[].timerTicks`, Hz | 145 | 0.999 | 1.000 | 1.001 | 1.001 | — |

**Why the gate case sits at 1 Hz.** The [standalone probe][s3-probe] measured 1 Hz in a detached view under all three public policies and in an off-screen window, 9.5–10 Hz in a visible one-point window, and 1 Hz again once detached. In WebKit's source (WebKit/WebKit `d4baac6a`, 2026-11-03, which may differ from the shipped build), `inactiveSchedulingPolicy` only sets RunningBoard assertion preferences; a page that is `IsVisuallyIdle`, which follows from `PageClientImpl::isViewVisible` needing a visible, unoccluded window, has its repeating timers aligned to `DOMTimer::hiddenPageAlignmentInterval()` (1 s), and the switch for that is SPI only. The one-point window costs memory: its page's WebContent process held 68–69 MB during the run against 16 MB parked, and the shared GPU process stayed at about 218 MB.

### 6a. No-bypass boundary control (2026-11-07)

A public-API prototype with independent loopback sinks ([design](../../../../evidence/2026-11-07-memoshi-engineering/analysis/browser-no-bypass-design.md)) found three gaps:
- WebKit's configured proxy exempts loopback and IP-literal targets.
- WebRTC (STUN/TURN) and WebTransport bypass the proxy entirely.
- A host Seatbelt profile does not confine WebKit's networking process.

[D101](../../plan/decisions.md#d101) adds a deny-local `WKContentRuleList` and Lockdown Mode to D81's route on Mac and iOS, and loads fail closed until all are installed.

The owned control in `spikes/S3-webkit-browser/no-bypass/` drives the real product browser files against owned loopback fixtures. Independent sink processes cover TCP v4/v6, bare connect, TURN, STUN v4/v6 and QUIC. Each run includes positive controls. The [run](../../../../evidence/2026-11-07-memoshi-engineering/BrowserBoundary/control-boundary3-f5ecba3816d3/) compares `e75a96c` with the change:

| Scenario | Before (sink events) | After (sink events) |
|---|---:|---:|
| Product, owned-fixture route | 259 | 0 |
| Product, gateway route | 233 | 0 |
| Product, fixture service worker | 20 | 0 |
| Fail-closed checks (6) | failed | passed |
| `target=_blank` click, retained failing control | 3 | 3 |

The positive controls reached the sinks in both runs. The strict verdict stays false because of the `target=_blank` empty loopback connection: no public API closes it. This is owned-fixture development evidence, not the twenty-task real-site corpus, packet capture, a signed build or a physical-device row. Lockdown's cost on real sites is unmeasured.

The owned upload/download suite then exposed a real defect: the allowlist's block-all rule also blocked `blob:` URLs, through which WebKit reads File and Blob contents, so granted pages could not read uploaded files. Route allowlists now exempt each granted origin's own `blob:` URLs; [a focused test](../../../../evidence/2026-11-07-memoshi-engineering/BrowserRepro/10-boundary-tests-before-blob-fix.log) failed before and passes after, and other origins' blobs stay blocked. The [suite then passes 7/7](../../../../evidence/2026-11-07-memoshi-engineering/BrowserRepro/) under the boundary with no setup failures. Its earlier page-load stalls came from WebKit's persistent store on the nearly full external build drive, reproduced before the boundary, not from the boundary.

**Follow-up, 2026-11-08: `data:`, LAN and alternate loopback targets.** No leak was found, so no product code changed. The evidence is in [BrowserFollowups](../../../../evidence/2026-11-08-memoshi-engineering/BrowserFollowups/).
- **`data:` URLs.** Content rules never act on `data:` URLs. `data:` frames, nested frames, objects, scripts, stylesheets and workers still run under deny-local alone, the gateway lists and the fixture list. Their own fetch, image, socket, frame, stylesheet, navigation, refresh and form loads reached the sink in the control. Under every list set they made 0 connections ([focused log](../../../../evidence/2026-11-08-memoshi-engineering/BrowserFollowups/02-boundary-tests.lock.log)). WebKit itself loads neither an SVG image's external reference nor a `data:` document opened by a `target=_blank` link.
- **Private and alternate loopback addresses.** The proxy's exemption covers every IP literal, not only loopback. With the gateway applied and no lists, loads to the host's own `10.211.55.2`, `192.168.1.28` and `fdb2:2c26:f4e4::1` went directly to sinks bound on those addresses; only `sink.localhost` reached the gateway. Deny-local and both route lists blocked these addresses. They also blocked `127.1`, `0x7f000001`, `0x7f.0.0.1`, `0177.0.0.1`, `2130706433`, `[::ffff:127.0.0.1]`, `127.0.0.1.` and `[0:0:0:0:0:0:0:1]`, all of which reached the sink in the control. WebKit refuses `0.0.0.0` and `0` even with no list.
- **Addresses not tested by connecting.** The host has no addresses in 172.16/12 or 169.254/16, and URLs cannot carry the zone that `fe80::/10` needs. For these and for `.local` names, WebKit's URL parser canonicalized each spelling and a deny-local filter matched every result. A zoned `[fe80::1%25lo0]` URL is invalid. The control also probes these from product pages on WebKit's restricted port 10080, which it refused before connecting to an owned sink. So these checks are rule-level evidence, not sink evidence.
- **Control.** The [rerun](../../../../evidence/2026-11-08-memoshi-engineering/BrowserFollowups/control-lan-666f01571910/) compared `e99946e` with the worktree, using these cases, `data:` frames and own-address sinks.
  - Both trees: every positive control was exercised, including each own address and spelling.
  - Product scenarios: 0 sink events and no local host at the gateway.
  - All 6 fail-closed checks passed.
  - The retained `target=_blank` control still shows 2 connections per route.
- **Upload/download suite.** It [still passes 7/7](../../../../evidence/2026-11-06-memoshi-native-repro-b7e4c291/native-repro-browserFollowups-75c8b997/browser/result.json).
- **iOS Simulator.** An owned carrier app compiled the unmodified `MobileBrowserReview*` session files (`spikes/S3-webkit-browser/ios-simulator/`). It ran once on the existing iPhone 18 Pro Max (iOS 27.0) Simulator, using the real `MobileBrowserReviewSession.open` and `load()`/`reload()`. All 54 checks [passed](../../../../evidence/2026-11-08-memoshi-engineering/BrowserFollowups/ios-simulator/run-sim1-9ae261aade9f/):
  - Lockdown read back on every route.
  - On every product route, 8 loopback spellings got 0 sink accepts; the plain control reached each spelling.
  - 30 `networkBoundary.*` refusals from `load()`/`reload()` made no request.
  - Granted origins could read their own blobs; other origins could not.

  With only `NSAllowsLocalNetworking`, the carrier's own ATS stopped the control's `localhost.` probe, so that run left 3 checks not exercised. A rerun that also set `NSAllowsArbitraryLoadsInWebContent` exercised all 54.

  The Simulator uses the Mac's network stack and the Simulator's WebKit, with an ad-hoc-signed carrier. It covers no device radios, no system-wide Lockdown Mode, no UDP sinks, no `target=_blank` and no real sites; physical-device rows stay open.

**Follow-up, 2026-11-08 round 3: `.local`, `fe80`, unbindable ranges.** Evidence is in [BrowserRound3](../../../../evidence/2026-11-08-memoshi-engineering/BrowserRound3/).
- **`.local` names.** Random names registered on mDNSResponder's local-only interface (never announced) pointed at loopback, own private and own ULA sinks. The unblocked control reached all 10 targets; deny-local and both route lists made 0 connections. A `.local` site cannot be granted: the gateway rule is refused and configuration fails closed (`fc-local-name-grant`).
- **`fe80`.** No zoneless `fe80` URL can connect: the kernel returns "No route to host" even to the Mac's own scoped sinks on `lo0` and `en0`. A zoned URL is invalid.
- **169.254/16 and 172.16/12** are not connect-testable without root, because the Mac has no address in them. WebKit refuses port 10080 before content rules (error 103, with or without a list), so the earlier 10080 probes were fail-safe but not list evidence.
- **Safety slip in that round.** A main-frame load the policy allows gets an empty preconnect before content rules apply. That round's ordinary-port main-frame loads to 169.254.x, 172.16.x and `fd00::1`, and one `.local` lookup, therefore probably left the Mac [INFERENCE]; one exploratory `dns-sd` record was also announced on the LAN for about 4 seconds. Those loads were removed.

**Follow-up, 2026-11-08: the gateway route now authenticates WebKit.** Evidence is in [GatewayAuth](../../../../evidence/2026-11-08-memoshi-engineering/GatewayAuth/).
- **Finding.** Before the change every WebKit request on the gateway route was refused `unattributed`, so no granted site had ever loaded through it. A recording relay between real WebKit and the gateway showed why ([red log](../../../../evidence/2026-11-08-memoshi-engineering/GatewayAuth/01-red-core.log)): WebKit sends `CONNECT host:80` (it tunnels plain `http` too) with no `Proxy-Authorization`, the gateway answered 403, and WebKit retried 8 times without ever sending its configured credential. The navigation delegate saw no challenge.
- **Change.** A request with no proxy credential now gets `407 Proxy Authentication Required` with `Proxy-Authenticate: Basic realm="memoshi"` and `Connection: close`, so there is at most one challenge per connection. A wrong or stale credential is still refused `unattributed`. Grant, host and address checks are unchanged and run after authentication. Challenges are counted separately (`EgressGateway.challenges`); they never appear as a decision or in the audit sink, and they resolve nothing.
- **Observed in real WebKit** ([green log](../../../../evidence/2026-11-08-memoshi-engineering/GatewayAuth/02-green-core.log)), with the product's store proxy configuration and its challenge disposition (non-server-trust challenges refused):
  - connection 1: `CONNECT … auth=no` → `407`; connection 2: `CONNECT … auth=yes` → `200 Connection Established`, then the page's `GET` inside the tunnel → `200`. The delegate saw no challenge: WebKit answers the proxy challenge from the store's configuration.
  - A granted owned-fixture host loads through the in-process gateway (public answer delivered to an owned upstream by the test route seam); an ungranted host is refused `host_not_allowed`; no decision is `unattributed`.
  - A granted name whose real local-only mDNS answer is loopback is refused `resolved_private_address`; a `.local` name is refused `local_name`; a granted name rebound from a public answer to loopback loads before and is refused after. The independent sinks saw 0 connections.
- **Other gateway clients are unaffected.** The sandbox curl helper and the native fetch path send the credential up front; the full egress suite, `SandboxComputerTests` and `SandboxHTTPSNetworkTests` pass.
- **Alternate-loopback +2.** Round 3's run saw 2 extra sink connections under list sets. With per-connection sink address, peer port and timing logged, the list sets added 0 connections in both later runs, and the control reached every target. In the round-3 run the control had not reached the own ULA sink when the list phases began, so the extra connections were most likely the control's own late connections [INFERENCE]; the test now waits until the sink is quiet between phases.
- **Preconnect correction.** A cancelling navigation policy prevents the empty preconnect only for page-initiated navigations (0 connections). For an API load (`WKWebView.load`), WebKit preconnects before asking the policy (1 empty connection per load). The product's `load()` refuses origins outside the route before calling the API, so it never triggers this.
- **Safety scope.** Tests and the control now load only this Mac's loopback, own addresses and local-only mDNS names. The restricted-port probes to other hosts' private, link-local, ULA and `.local` addresses, and the LAN-hostname scenario, were removed. The first red run still made the inherited 10080 navigations to those addresses; WebKit refused each before connecting (error 103; the loopback 10080 sink saw 0).
- **Control.** The [rerun](../../../../evidence/2026-11-08-memoshi-engineering/GatewayAuth/control-gatewayauth2-591ca8c106d2/) compared `13f8d5f` with the worktree. Both trees build their browser files from their own tree and link the worktree's packages, so both include the gateway change.
  - Both trees: every positive control exercised, all product scenarios 0 sink events, all 7 fail-closed checks passed, `target=_blank` retained at 2 connections per route; `passExcludingRetainedBlankControl` true.
  - Gateway decisions are now attributed: 216 per run (156 `host_not_allowed`, 60 `local_name`), none `unattributed`. No control page requests its granted origin, so none is allowed there; granted loads are shown by the WebKit gateway tests above.
  - The local-only mDNS names now carry an A and a v4-mapped AAAA record: with A alone every lookup waited 5 s, past the probe's 2 s bound, and the [first rerun](../../../../evidence/2026-11-08-memoshi-engineering/GatewayAuth/control-gatewayauth-446665025981/) missed them in its positive control. Every record was removed and confirmed absent afterwards.
- **Upload/download suite.** It [still passes 7/7](../../../../evidence/2026-11-06-memoshi-native-repro-b7e4c291/native-repro-gatewayAuth-ae27c6ed/browser/result.json).

## 7. Fallback status

| Fallback | Trigger | Status |
|---|---|---|
| Foreground-only WebKit browsing on This Mac; background browsing waits for Chromium with Bot computers in v1.1 ([phase-0 S3](../../plan/phase-0.md#s3), Q5's stop rule, [R26](../../plan/risks.md#r26)) | S3 fails | Not applied. It would apply at a gate held today through the timebox rule (§10), and demo step 11 would run with the window open ([phase-0 §8](../../plan/phase-0.md#exit-demo)). |
| Cut-list item 2, S3 breadth: 10 tasks on 3 sites instead of 20 on 5, keeping store isolation, sign-in fill and windows-closed operation; the iOS check reduced to store isolation ([phase-0 §10](../../plan/phase-0.md#cut-list)) | Phase 0 runs behind | Not invoked. Cuts go in order, so S6 (item 1) goes first, and each cut is recorded in the gate review. Even reduced, Q5 still needs an iOS store-isolation run. |
| 06 row fallbacks: DOM events plus a takeover prompt (row 2); a 1-pixel visible host window (row 3); fewer default elements (row 4); content rules and a Network Extension study (row 6); main frame only with a takeover hint (row 8); a navigation-delegate POST check (row 9); foreground-only browsing on iOS (row 12); per-bot `WKContentRuleList` (row 13); no uploads on iPhone and iPad (row 14) | That row fails | Row 3's host window is now measured and implemented for bot runs: the review lab keeps a running page in the visible one-point window while no review window shows it, and returns it to its parking choice afterwards. It works only while that window is visible and unoccluded, so a sleeping display, a locked screen or a covering window would throttle it again [INFERENCE from WebKit's visibility rule; not measured]. Rows 5 and 7 are blockers with no fallback. |

## 8. Marginal results: owner and proposed Phase 1 ticket

| Row | Owner | Proposed Phase 1 ticket |
|---|---|---|
| 06 row 3 and phase-0 "Timers and automation with all windows closed" | Memoshi (NAT lane: the builder with agents); the user provides the reference box | **Closed-window WebKit timers at ≥ 1 Hz on the reference box.** Re-measure on the base 16 GB M1 (macOS 27, Release build) with every window closed and Memoshi inactive, for a continuous unattended span of at least 600 s counted from the first sample, with one bot and with four concurrent bots. Record n, minimum, p50 and p95 of the timer rate, snapshot success and the WebKit inactive scheduling policy. If the steady rate stays below 1 Hz, measure 06's fallback (a 1-pixel visible host window) under the same protocol and record which one the product uses. Done when the row passes on the reference box at the Phase 1 gate; otherwise S3's foreground-only fallback applies. |

## 9. What remains before the gate

S3 (P0-11) is scheduled for W4, Mon 2026-11-16 to Fri 2026-11-20; spike reports are due Wed 2026-11-25 and the gate is Fri 2026-11-27 ([phase-0 §3](../../plan/phase-0.md#team-and-calendar)).

| Work | Rows | Owner | Prerequisite or current state |
|---|---|---|---|
| A task runner and the 20-task suite on 5 real sites (search, form, test-account login, pagination, download), with an authorized submission and download policy | 1, 10 | Memoshi; the user chooses or approves the sites and supplies the test accounts | The lab has no runner and blocks submissions and downloads |
| Native clicks and keys on 3 pages, on screen and in a hidden host window | 2 | Memoshi | 0 hidden-host actions recorded |
| The Safari check: Safari › Settings › Privacy › Manage Website Data must not list `memoshi.invalid` | 5 | The user (a manual check), or Memoshi on the reference box | A manual step, per the lab ([run-b report][rb] → `rows[0].missing`) |
| Reference-box runs: every Mac row at one and four concurrent bots, including the 30-page snapshot p50 and the closed-window rerun; S3 basics on the 8 GB Mac | 2–9 | Memoshi; the user provides both machines | No reference-box evidence exists; on 2026-11-03 the user put the reference Macs last ([HANDOFF §8](../../HANDOFF.md#8-next-moves)) |
| Qualify the authenticated browser gateway/all-traffic route and packet capture over 20 sites | 6, 13 | Memoshi; the user authorizes capture/capability provisioning where required | `MemoshiEgress` exists and owned authenticated controls run, but every tested public HTTP/SOCKS proxy configuration allowed loopback bypass. The separate sealed Python route does not qualify arbitrary websites |
| Keychain-broker sign-in Card fill, with a canary search of a real transcript and event log | 7, 10 | Memoshi | The development Card and its canary scan pass on the lab page; the broker, real sites and memoshid's transcript path are not built |
| `willSubmitForm` with `browser_site` interact grants | 9 | Memoshi | Not integrated |
| A cross-site frame on a real page, `WKJSHandle` on macOS 27, and native input inside frames | 8 | Memoshi | Only an opaque-origin `data:` frame was exercised |
| Per-profile WebContent memory on the reference box at one and four bots | — | Memoshi | Measured on this Mac by external `footprint` readings ([memory readings][s3-memory]) |
| iPhone and iPad rows, reduced to store isolation if cut-list item 2 is taken | 10–14 | The user: device provisioning and signing (P0-16); Memoshi: the iOS host (P0-09) | Physical runs are released in principle but cannot start until both exist ([phase-0 execution hold](../../plan/phase-0.md#team-and-calendar)); the user put Developer ID, App IDs and profiles last ([HANDOFF §8](../../HANDOFF.md#8-next-moves)) |
| Pi_Swift SDK | — | None identified [INFERENCE: S3 is app-hosted WebKit] | — |

## 10. Decision recommendation if the gate were today

- **Q5 fails.** Under the timebox rule every not-run row counts as a fail, and the marginal closed-window row cannot carry Q5 on its own. Phase 1 would then start with foreground-only WebKit browsing on This Mac, and background browsing would wait for Chromium with Bot computers in v1.1.
- **Keep D18 and D19 as accepted.** Nothing observed contradicts them: per-profile stores kept cookies apart across a relaunch, and moves into and out of the live view kept the same document. This evidence supports no decision update.
- **Do not take the fallback before the real gate.** The windowless view kept snapshots and navigations working for the whole run; only the timer rate missed its bound, by the throttled margin in §6. Run the open rows in W4. If Phase 0 runs behind, cut S6 first, then S3's breadth, and record both in the gate review.
- **iOS and the reference box are Q5's critical path.** Even the reduced iOS check needs P0-09 and P0-16, and only the reference box gives a Mac row a gate number; the user put both the signing items and the reference Macs last [INFERENCE: these are the parts most likely to stay open at the gate].

## 11. Evidence notes and discrepancies

1. **Rounded timer rates.** The report row and HANDOFF's closed-window table give a 0.9 Hz minimum and a 1.0 Hz median. The raw samples give 0.918 Hz and 0.968 Hz: the median itself is below the 1 Hz bound, and 80 of 115 samples are below it. The row prints one decimal place ([`BrowserReviewReport.swift`][lab-report], `closedWindowsRow`). This draft uses the raw values.
2. **The 597 s span** runs from the first sample at 5.34 s to the last at 601.97 s (`samples[].elapsedSeconds`), while the run itself spans 21:44:50Z to 21:54:52Z. [INFERENCE] With 5 s sampling the metric cannot reach 600 s in a 10-minute run, so it is a sampling artifact, not evidence that operation stopped early; the proposed ticket counts the span from the first sample.
3. **Relaunch persistence is AX-only.** The typed run-b report was exported before the relaunch and reports "own probe found after a relaunch: 0" (`rows[0].evidence`); the after-relaunch result is in the AX capture only. This is not a contradiction, but the reference run should export a typed report after relaunching.
4. **Probe interval provenance.** The 10 Hz target appears in the run-b page label and in the current `BrowserSession.startTimerProbe` (`intervalMs: 100`), whose SHA-256 matches the run-d source manifest ([manifest][manifest] → `sourceFiles[]`). No source manifest was retained for run-b's own binary [INFERENCE: same interval].

## 12. Sources

- Memoshi plan: decisions D18, D19, D47, D81, D90; phase-0 §1, §3, §5, §8, §9 and §10; 06 §8, §10.1 and §12; risks R26 and R34; the HANDOFF consumer follow-through.
- Evidence outside the repository: the run-b closed-window report, the run-c action report, AX captures, signing records, the WebKit removal crash summary and the run-d removal result under `2026-11-02-memoshi-consumer-qualification/native/`.
- Source read for field semantics: [`BrowserReviewReport.swift`][lab-report], [`BrowserReviewLab.swift`][lab-run], [`BrowserReviewModels.swift`][lab-models], [`BrowserSession.swift`][lab-session] and [`BrowserAutomationScript.swift`][lab-script].

[rb]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/ui/run-b/browser-closed-window-report.json
[rb-relaunch]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/ui/run-b/ax-browser-two-profile-persistence-after-relaunch.json
[rb-before]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/ui/run-b/ax-browser-before-closed-window-run.json
[rb-sign]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/ui/run-b/signing.json
[rc]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/ui/run-c/browser-action-report.json
[rc-sign]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/ui/run-c/signing.json
[rc-reopen]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/ui/run-c/ax-browser-same-document-reopen-after.json
[rc-extra]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/ui/run-c/menu-extra-reopen-action.json
[rc-takeover]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/ui/run-c/ax-browser-takeover-blocks-actions.json
[rc-handback]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/ui/run-c/ax-browser-handback-summary.json
[rd-removal]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/ui/run-d/cold-removal-result.json
[crash-before]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/cold-removal-crash-summary-before.json
[manifest]: ../../../../evidence/2026-11-02-memoshi-consumer-qualification/native/production-source-and-binary-manifest.json
[lab-report]: ../../../apps/mac/Memoshi/BrowserReviewReport.swift
[lab-run]: ../../../apps/mac/Memoshi/BrowserReviewLab.swift
[lab-models]: ../../../apps/mac/Memoshi/BrowserReviewModels.swift
[lab-session]: ../../../apps/mac/Memoshi/BrowserSession.swift
[lab-script]: ../../../Packages/MemoshiApp/Sources/AppCore/BrowserAutomationScript.swift
[derived]: ../../../../evidence/2026-11-03-memoshi-s3-s4-draft-reports/derived-measurements.json
[s3r]: ../../../../evidence/2026-11-03-memoshi-s3-browser/s3-signin-run.json
[s3c]: ../../../../evidence/2026-11-03-memoshi-s3-browser/s3-continuity-memory-run.json
[s3-derived]: ../../../../evidence/2026-11-03-memoshi-s3-browser/derived-continuity.json
[s3-probe]: ../../../../evidence/2026-11-03-memoshi-s3-browser/probe/webkit-timer-placement-probe.json
[s3-filescan]: ../../../../evidence/2026-11-03-memoshi-s3-browser/scans/run1-file-canary-scan.json
[s3-logscan]: ../../../../evidence/2026-11-03-memoshi-s3-browser/scans/run1-unified-log-canary-scan.json
[s3-memory]: ../../../../evidence/2026-11-03-memoshi-s3-browser/memory/readings.json
[s3-copy]: ../../../../evidence/2026-11-03-memoshi-s3-browser/review-copy.json
