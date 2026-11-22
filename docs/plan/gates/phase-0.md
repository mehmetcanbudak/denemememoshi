# Phase 0 gate readiness: foundations and spikes

Evidence updated: **2026-11-06** · Plan owner: **the builder** · Engineering evidence: coding agents in the existing APP/NAT/RT/PD/QA lanes.

**Amended in place on 2026-11-13 (`ddab24f`); this note added on 2026-11-18.** Two D99 entries below were rewritten to describe the facts of 2026-11-10 and 2026-11-12, without a note at the time: the owner-actions sentence before the remaining-input table, and that table's D99 row. As filed on 2026-11-06 they read: "D99 domain registration/DNS/public-files setup by 2026-11-13" and "Public A lookup returned no address and the association request failed DNS resolution. Registration is not established. | Operator registration, DNS/HTTPS hosting and required public files by 2026-11-13." The rest of this record is as filed. The current reading is in the [gate review draft](phase-0-review-draft.md) and the [D99 amendment](../decisions.md#d99).

**Engineering recommendation: No-go for Phase 1/product-scope expansion.** This is an early readiness review, not the scheduled 2026-11-27 gate, an accepted SDK baseline, a builder-approved platform fallback, a release acceptance receipt or a claim that Phase 0 is complete. Re-gate after the named prerequisites and prescribed measurements exist; no new date is invented. The [gate rule](../10-roadmap.md#gate-template) and [Phase 0 exit criteria](../phase-0.md#exit-criteria) are unchanged.

## 1. Delivered versus planned

The consumer remains pinned to `892585fc8d8be3093b58c34aacffcd4e68c3a8d9`. Development proof creates no `slice-N` and removes no release/broader-qualification hold. The [delivery reconciliation](../../research/spikes/2026-11-02-pi-swift-consumer-handoff.md#current-delivery-reconciliation-2026-11-06) separates later SDK claims from accessible source/request records; no qualifying baseline is adopted. Normal app/helper composition still disables production tools, environments, MCP, Code Mode and subagents.

| Existing ticket / spike | Current evidence | Remaining acceptance / owner |
|---|---|---|
| P0-04/05/06/15/20/21 — [S1](../../research/spikes/2026-11-04-s1-runtime-draft.md) | Ten-minute idle closure/live deletion; lock-alias failing-before repair; real local children/active Stop; controlled ten-approval kill/reopen; bounded policy/MCP/recovery controls | Accepted H0–H4/adoption; two real API-key providers; full real-model/platform chaos/approval/policy matrix; physical iOS/reference performance — RT/APP/NAT/QA |
| P0-10 — [S2](../../research/spikes/2026-11-04-s2-devices-draft.md) | Native MLS, encrypted durable authority/group/replica/mailbox controls; current native-wire processes and genuine competing expiry-window attempts. Existing secured full local pairing/handover/load proof carried, not recreated | Actual Pi stores/H2; provisioned identities/apps; physical pairing; real Bonjour/VPN/CloudKit/APNs/deployed relay/racing; applied real approval Cards; copied effects; O10 — NAT/RT/APP/QA |
| P0-11 — [S3](../../research/spikes/2026-11-03-s3-webkit-browser-draft.md) | Owned recipes; bounded Mac sign-in/input/frame/visible-host proof; actual credential-free Simulator persistence, input, history and staged-file/revocation controls; actual current Mac select/download callback controls. Independent public WebKit proxy controls failed confinement | Approved20-task/five-site corpus; real-page input/snapshots/iframes; full broker/event composition; no-bypass route; physical/mobile/closed-window/reference qualification — NAT/APP/QA |
| P0-12 — [S4](../../research/spikes/2026-11-03-s4-this-mac-sandbox-draft.md) | Exact-UDS/network/HTTPS/policy/audit controls; actual offline toolchain workflows; reproduced/repaired read-only-root, launcher and Unicode-ancestor mutations; new D96 host-library filesystem controls. The [105-case raw matrix](../../research/spikes/2026-11-03-s4-this-mac-sandbox-draft.md#s4-local-boundaries-2026-11-06) retains seven diagnostic effects and five unestablished aliases | H3/full conformance, raw-profile limitations, hostile race/CAS and native capabilities, full usability/TCC/reference performance, authoritative kernel attribution and product qualification — RT/NAT/QA |
| P0-14/16/20 — [S5](../../research/spikes/2026-11-04-s5-distribution-draft.md) | Release/provisioning/hold/signing-order/size-growth/TestFlight contracts; completed current canonical development CI (630 Swift + 23 tooling tests), with original failures retained | G2/app-helper/mobile profiles; signed/notarized/stapled DMG; clean VM/SMAppService; update/helper Apple capabilities; release broker/transport; physical TestFlight; actual size budgets/clean-clone remote CI — NAT/APP/QA, kept last |
| P0-23 — [S6](../../research/spikes/2026-11-04-s6-pyodide-draft.md) | Offline host/Pi bridge carried; sealed native HTTP candidate passed a complete 111.40-second real-WebKit network/scientific/drain control, with retained failures and scoped canary scan; public-host reuse/Stop/timeout retirement passed; the hardened per-bot realm refuses a public-bus forged result and the measured asyncio/timer leftovers, enforces idle/lifetime limits and passed the complete scenario again (59.81 s, reconstructed tail) after a gateway-shutdown repair | Public WebKit proxy controls remain failed; nested-worker leftovers remain (native limits bound them); no soft stop (no `SharedArrayBuffer`); product composition and physical startup/memory/pandas/background/size/Lockdown and D100 route rows remain open; no W25 cut — NAT/RT/QA |
| P0-13/19 — [design](../../specs/design-reference.md#6-original-avatargallery-and-subscription-ready-development) | Generated typography/motion/material/glyph bindings and runtime native-accent derivation; actual material/focus/message/Activity and new glyph/accent review; filed P0-19 assessment; current functional/token/lint integration pass | User adoption, complete native/accessibility/device review and qualifying motion/performance — PD/APP/QA |
| P0-17/22 | [Port audit](../phase-0.md#port-list), replay fixtures and [provenance/licence review](../../research/2026-11-03-provenance-and-licence-review.md) carried | No new import/fork/distribution clearance; notices and release-rights/GPL questions retained — RT/PD/EL |

These are **development scorecards, not six final qualifying reports**. An unrun measurement stays unrun; it is not promoted to a pass or a measured failure to trigger a convenient fallback.

### Bounded pstack maintenance (2026-11-06 through 2026-11-07)

Current architecture/protocol summaries now identify schema 12, implemented mobile/provider
runtime and D100. Build instructions record the existing Rust targets and effective CI
inputs. Release inventory resolves normal ancestor aliases before ordering real nested
Mach-O code. [Failing-before](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/release-alias-red.json),
[passing tooling](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/release-alias-green.json)
and [actual inventory proof](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/release-inventory-smoke.json)
are separate from canonical CI and product signing. The actual held-release CLI still
refuses admission. Neither hold changed.

The [bounded current Runtime results](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/runtime-current-component-results.json)
now retain actual invocation-bound Stop, gateway reopen/replay and deterministic private-copy
guard observations. D79/D83 unknown-effect holds remain explicit. The
[105-case S4 reconciliation](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s4-retained-case-reconciliation.json)
preserves all raw diagnostic effects and absent aliases. Exact cached support, local
synthetic actors and host-library guards do not supply H3, physical or final qualification.

The later [current-source focused SwiftPM run](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/core_cancellation_races_no_symbols.log)
passes four tests across the Stop, gateway continuity and private-copy suites. It uses the
existing build engine with debug symbols and the index store disabled. This is fresh focused
source integration, not full canonical CI, SDK adoption or release admission.

The [complete owned native browser run](../../../../evidence/2026-11-06-memoshi-native-repro-b7e4c291/native-repro-private-data-after-navigation-observation-25f3fad6/browser/result.json)
passes all seven upload and download cases with no setup failures. Private upload exposure
requires fresh GET/POST confirmation. Revoked held downloads reach EOF and lose their partial
file before upstream release. The [actual rendered AX result](../../../../evidence/2026-11-06-memoshi-native-repro-b7e4c291/native-ax-client-after-95gla_bg/chat/result.json)
passes nine bot, Session, Assistant and user labels. These are owned native development
controls, not manual source-picker, spoken VoiceOver, physical-device or S3 confinement proof.
The current [eight runtime credential tests](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/native_runtime_credential_contracts.log)
and [13 unsigned authorization/pairing tests](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/native_app_credential_lifecycle_contracts.log)
pass separately. They use synthetic broker values and do not qualify actual Keychain lock,
sync, unattended access or physical lifecycle behavior.

The [actual small relay CLI control](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s2-journal-cli-small-ri5nl1o4/result.json)
independently matches a closed journal to its two retained authority records and real grant.
The [first](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s2-first-quick-diagnostic.json)
and [separate serial](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s2-serial-quick-diagnostic.json)
full local quick cohorts still fail after renewal refusal and burst fencing. Their failed
reports retain no main relay summary. Neither host load nor queue overflow is an established
cause. Lease limits and expected counts remain unchanged. Neither cohort qualifies S2.
The [changed failed-cohort retention path](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s2-failed-cohort-retention-after.json)
now retains the main terminal summary and raw journal before cleaning owned work.
An independent parser matches all 332 records and 156,508 payload bytes to the reported
closed journal. The qualifier still exits 1 after the burst failure and its owned group
drains. Preserving that failed evidence is not S2 admission or a renewal-delay diagnosis.

The [occupied required-copy control](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/s2-required-copy-refusal-xpm16n3m/result.json)
also preserves the sentinel and original evidence with qualifier exit 1. Its host archives
the original before cleaning its synthetic work. No successful S2 cohort is inferred.

The [actual unsigned built-bundle check](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/actual_legal_bundles_check-exit.json)
passes for Mac, helper and iOS Simulator resources. [Omission and drift controls](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/legal-bundle-negative-sdohti3c/result.json)
fail as required on private copies. This is packaging evidence, not product signing or
public redistribution clearance.

### Engineering follow-through (2026-11-07)

Local commit `e75a96c` passed every unchanged `scripts/ci.sh` step over [two runs](../../../../evidence/2026-11-07-memoshi-engineering/canonical-e75a96c-02-final-steps/run.json) in a clean worktree; the first hit the runner's time limit during the app build. [D101](../decisions.md#d101)–[D103](../decisions.md#d103) record the user's browser-boundary, lease-clock and secret-rule choices. The [handoff section](../../HANDOFF.md#engineering-follow-through-2026-11-07) holds the evidence.
- **S2:** the earlier quick-cohort failures trace to storage stalls on the USB build volume. Three internal-disk `--quick` cohorts with arrival-time expiry now pass with unchanged limits.
- **S4:** app-owned export and secret-profile controls failed before and pass after.
- **Browser:** the boundary and the native accessibility repairs are implemented with focused and rendered-surface proof. Their remaining controls are listed as pending in the handoff.

None of this changes an exit-criterion disposition. S2 still lacks Pi replication, physical devices and deployed services. S3 lacks its no-bypass control result, real sites and physical rows. S4 lacks H3, kernel attribution, TCC and reference rows. The SDK pin is unchanged.

## 2. Exit criteria

| Criterion | Required target | Readiness disposition |
|---|---|---|
| Reports/platform choices | Six reports, or five plus approved S6 move; per-platform D46; measured O10; Python route | Six drafts exist. [D100](../decisions.md#d100) selects Python's sealed native route for development, pending physical rows. No SDK/platform/Python fallback or cut is selected |
| Mac real-model recovery |50/50 correct randomized kills, zero duplicates;10/10 pending real approvals | Open. Failed/local cohorts and controlled-model10/10 remain separate |
| Physical iOS | Same recovery plus three scenarios10/10 each; prescribed both-backend Release series | Unrun; Simulator refusal/Debug tests are not substitutes |
| Authority load / O10 | CloudKit and deployed relay; declared active/idle range, complete samples, renewal policy | Open; original local profiles are not deployed capacity |
| Ship path | Notarized clean-VM install, approved helper lifetime/update, physical internal TestFlight | Open; signing/reference Macs/VM remain last |
| Secret canaries | Zero hits after full required smoke/chaos on both platforms | New owned native-Python scan: 111 files, seven synthetic-credential forms, zero hits; full required cohort/platform scan remains open |
| Design | Generated values/base primitives, budgets or owned gaps, scenario/user review and QA; P0-19 filed | Assessment/current native review and functional pipeline pass exist; adoption, full accessibility/device review and qualifying measurements remain open |
| Exit demo | Prescribed end-to-end demo twice consecutively, no unscripted help; only recorded fallbacks | Not run; fixture replay/private pipes are not the demo |
| Dogfood | At least one week | No qualifying one-week series is supplied by this implementation session |
| Final gate/dependencies | Whole-register rescore, approved decisions, refreshed dependencies, trademark/provenance | This engineering snapshot is filed; final builder gate/admission remains open |

## 3. Demo

[Binding script and formal variants](../phase-0.md#exit-demo). No end-to-end recording or two-consecutive-run receipt exists. Missing notarized DMG, physical TestFlight, accepted runtime/failover/file contracts and authorized real-model/site inputs are not replaced with replay, private pipes or a simulator.

## 4. Budgets and design

[Reference hardware/sample protocols](../phase-0.md#reference-hardware) remain binding. The [historical 2026-11-04 canonical baseline](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/canonical-integrated-a9466911/run.json) passed **605 Swift tests + 23 release-tooling tests**, native MLS/provenance, tokens, lint/boundaries, licences, schema, Mac/universal iOS Simulator builds, sign-in and bundle checks in **3540.76 s**. It is not verification of later source, reference P-STREAM/P-IDLE, frame/energy/physical memory, the separate combined-conformance-under-five-minutes requirement, clean-clone remote CI or release acceptance. All original failures/repairs retain their dated scorecard scope.

The [latest retained 2026-11-06 canonical run](../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/canonical-after-s4-38fb8537/run.json),
after the S4 launcher/Unicode-ancestor repairs and added filesystem cases, passed **630 Swift
tests + 23 release-tooling tests** and all unchanged pipeline stages, including Mac/universal
iOS Simulator builds, in **9183.36 s**. The separate raw-profile matrix remains non-green.
The [624-test](../../../../evidence/2026-11-06-memoshi-phase0-python-hardening-b0f24d5d/canonical-after-python-hardening-78a0e11b/run.json),
[622-test](../../../../evidence/2026-11-06-memoshi-phase0-next-caa93544/canonical-after-ancestor-fix-cbe82d8f/run.json)
and [621-test](../../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/canonical-native-lint-repaired-859191f4/run.json)
runs, the lint failure/repair and existing build/deprecation diagnostics remain retained.
It supplies integration evidence for that retained source, not the later pstack safety
changes, any separate qualification above, an accepted SDK slice, a risk reduction or Phase 1 admission.

Current view-only native review retained the failing/repaired Frosted comparison, exact local composer receipt, Solid/Frosted draft continuity, actual Unicode/Escape input, manual stream/settlement/focus/removed-action behavior and labelled synthetic Activity states. It did not certify full VoiceOver/keyboard-only focus return, every size/locale/RTL, actual OS settings, physical iPad, material/icon/focus contrast or reference motion/performance. Tokens remain provisional until evidence plus user adoption support them.

## 5. Whole-register engineering rescore

The existing **2026-11-04 review of all 60 actual register rows** is carried forward. No standalone R18 row exists; none is invented. L/M/H remain 1/2/3; score is L×I. **No score is reduced, no new risk closed and no historical acceptance broadened by development-only proof.** No qualifying new gate evidence supports changing those scores/statuses. This engineering readiness update is not final builder approval of the risk rescore; the mandatory [Phase 0 evidence](../risks.md#gate-risks) remains due.

| Risk | L | I | Score | Owner | Evidence-based disposition |
|---|---|---|---:|---|---|
| [R1](../risks.md#r1) | H | H | 9 | PD | Phase 0 remains the active scope; no added product phase or silent cut. |
| [R2](../risks.md#r2) | H | H | 9 | RT | Consumer pin is unchanged; newer upstream source is not re-audited/adopted by this record. |
| [R3](../risks.md#r3) | M | H | 6 | NAT | Release tooling is tested source, not notarized installation/update/helper-survival proof. |
| [R4](../risks.md#r4) | M | H | 6 | RT | Mac origin/audit controls exist; complete required both-platform policy matrix remains open. |
| [R5](../risks.md#r5) | M | M | 4 | APP | Development smoke is not scale/long-Chat performance qualification. |
| [R6](../risks.md#r6) | H | H | 9 | RT | No new full-source red-team or prompt-injection gate acceptance; production tools stay off. |
| [R7](../risks.md#r7) | H | M | 6 | PD | No new always-on platform or unapproved model fallback is introduced. |
| [R8](../risks.md#r8) | — | — | — | PD | Closed by D47/D48; no change. |
| [R9](../risks.md#r9) | M | M | 4 | PD | O7/template activation evidence unchanged; later gate remains. |
| [R10](../risks.md#r10) | L | L | 1 | PD | Enterprise capabilities remain out of scope. |
| [R11](../risks.md#r11) | M | M | 4 | PD | No newly authorized billed-provider qualification; no measured full dogfood spend period. |
| [R12](../risks.md#r12) | M | M | 4 | APP | Installed-toolchain compilation is being verified; no future OS/beta qualification inferred. |
| [R13](../risks.md#r13) | — | — | — | PD | Closed by D45; no change. |
| [R14](../risks.md#r14) | M | M | 4 | PD | Current native repairs/review and P0-19 assessment exist; user adoption and full native QA remain open. |
| [R15](../risks.md#r15) | M | H | 6 | RT | Live deletion/lock/reopen controls passed; whole-conversation and distributed uncertain outcomes remain held. |
| [R16](../risks.md#r16) | M | H | 6 | EL | Carry the filed provenance/notices review; no new redistribution or GPL compatibility clearance. |
| [R17](../risks.md#r17) | H | M | 6 | PD | No new competitive-response evidence is claimed. |
| [R19](../risks.md#r19) | M | M | 4 | RT | Remote execution remains v1.1; no SSH/remote-machine qualification. |
| [R20](../risks.md#r20) | H | H | 9 | NAT | VM work remains v1.1; no VM candidate or capacity claim. |
| [R21](../risks.md#r21) | L | M | 2 | PD | Platform floor unchanged; no reach/waitlist evidence. |
| [R22](../risks.md#r22) | M | M | 4 | PD | Exact-name product collision is observed; legal priority/confusion remain unestablished and O8 stays open. |
| [R23](../risks.md#r23) | M | H | 6 | RT | No autonomy/budget scope is enabled by this work. |
| [R24](../risks.md#r24) | M | H | 6 | RT | Development Store/runtime controls passed; reference Pi commit/replication measurements remain open. |
| [R25](../risks.md#r25) | M | M | 4 | NAT | App-host capability lifetime remains a real boundary; no all-host crash recovery qualification. |
| [R26](../risks.md#r26) | H | M | 6 | NAT | Owned fixtures and visible-host proof are bounded; real-site/trusted-input/proxy matrix remains open. |
| [R27](../risks.md#r27) | M | H | 6 | RT | Usable private UDS control passed; H3, full D96 and trustworthy kernel attribution remain open. |
| [R28](../risks.md#r28) | M | H | 6 | RT | Retained scoped canary controls are bounded; full required smoke/chaos/platform scan is not complete. |
| [R29](../risks.md#r29) | M | M | 4 | APP | Actual native states were exercised; reference frame/CPU/hidden/ambient budgets remain unmeasured. |
| [R30](../risks.md#r30) | M | M | 4 | APP | Basic actual native keyboard/AX review is not a full VoiceOver/device accessibility pass. |
| [R31](../risks.md#r31) | H | M | 6 | PD | No new subscription provider/CLI identity flow is selected. |
| [R32](../risks.md#r32) | H | M | 6 | EL | No vendor/platform replacement or new dependency is selected. |
| [R33](../risks.md#r33) | M | M | 4 | PD | No unauthorized real site/account interaction is performed. |
| [R34](../risks.md#r34) | M | H | 6 | EL | Current measurements are development-Mac/prototype data, not the specified reference matrix. |
| [R35](../risks.md#r35) | H | M | 6 | PD | No new tester cohort or telemetry authority; no metrics extrapolation. |
| [R36](../risks.md#r36) | M | M | 4 | RT | Loopback webhook scope remains its later phase; no new receiver/admission surface. |
| [R37](../risks.md#r37) | M | H | 6 | PD | Existing personal/noncommercial risk acceptance retained; no new art/import or release-rights decision. |
| [R38](../risks.md#r38) | M | H | 6 | RT | No Bypass expansion; real mode/origin/red-team acceptance remains due at its gate. |
| [R39](../risks.md#r39) | H | H | 9 | RT | No accepted SDK slice or both-platform Code Mode/recovery receipt; S1 remains open. |
| [R40](../risks.md#r40) | H | H | 9 | RT | Native prototype persistence/fencing passed; actual Pi replication/copied effects and physical links are not qualified. |
| [R41](../risks.md#r41) | M | M | 4 | NAT | Simulator refusal is not an actual continued-processing grant; physical scenarios remain unrun. |
| [R42](../risks.md#r42) | M | H | 6 | EL | Local relay proof is not deployed service operation or capacity. |
| [R43](../risks.md#r43) | M | M | 4 | NAT | No real CloudKit/deployed-relay authority-load series; O10 remains open. |
| [R44](../risks.md#r44) | L | M | 2 | EL | Local encrypted carriers do not prove deployed retention or service-metadata privacy. |
| [R45](../risks.md#r45) | — | — | — | PD | Deferred by D67/O13; no new public App Store decision. |
| [R46](../risks.md#r46) | L | H | 3 | NAT | No qualifying G2/app-helper profile/expiry receipt; provisioning remains last. |
| [R47](../risks.md#r47) | H | H | 9 | PD | One-builder ownership unchanged; no calendar saving or next-phase admission inferred. |
| [R48](../risks.md#r48) | M | M | 4 | NAT | Offline/scoped native HTTP candidate proof exists, with retained timeouts; public proxies failed and physical route/adoption remain unqualified. |
| [R49](../risks.md#r49) | — | — | — | RT | Closed by D68; no change. |
| [R50](../risks.md#r50) | M | M | 4 | PD | Separate prototype remains nonbinding; no edit or migration of that repository. |
| [R51](../risks.md#r51) | H | H | 9 | RT | No new Swift engine/runtime-size qualification; later staged work retained. |
| [R52](../risks.md#r52) | M | H | 6 | RT | No new generated-program capability or red-team acceptance. |
| [R53](../risks.md#r53) | H | M | 6 | NAT | iSH remains in its accepted later probe; no emulator measurement. |
| [R54](../risks.md#r54) | M | H | 6 | EL | Existing GPL/PolyForm combined-work obligations retained; module separation is not clearance. |
| [R55](../risks.md#r55) | L | H | 3 | RT | Signed bytecode stays in its accepted later drop; no trust-path change. |
| [R56](../risks.md#r56) | M | H | 6 | RT | Pinned native MLS/provenance and local recovery controls exist; no external library security audit is inferred. |
| [R57](../risks.md#r57) | M | H | 6 | NAT | No new physical synced-secret/biometric/revocation acceptance. |
| [R58](../risks.md#r58) | L | H | 3 | RT | No new recovery-key enrollment/rotation/recovery qualification. |
| [R59](../risks.md#r59) | L | M | 2 | EL | No new release catalog-signing/refresh qualification. |
| [R60](../risks.md#r60) | H | M | 6 | NAT | Reference iPhone/iPad memory/background measurements are absent. |
| [R61](../risks.md#r61) | M | M | 4 | RT | On-device model stays in Drop 2; no download or offline-answer claim. |

## 6. Decisions

- **D46/D89/D90:** pin/holds unchanged; no platform fallback, shipping backend or slice adoption selected. Newer source is not H0–H4 qualification.
- **O10:** open until real CloudKit/deployed-relay load/renewal/idle evidence. No capacity policy from local handovers.
- **D79/S6:** sealed native HTTP has bounded development proof; the original public WebKit proxy route failed. [D100](../decisions.md#d100) (delegated) selects the sealed route and restates the criterion as no request around the gateway; the physical route and its acceptance remain open. The per-bot realm is kept and hardened; it still cannot attest that cell code stopped, so native limits bound it. No automatic runtime switch, Mac fallback or W25 cut.
- **D96/S4:** rejected live-folder/separate-user kernels stay rejected. Launcher and Unicode-ancestor repairs have actual confined-daemon proof; the raw matrix remains non-green. Host-library admission/export and bounded UDS controls neither enable tools nor waive H3, the seven diagnostic effects or full race/native conformance.
- **D91–D94/design:** assessment filed; no new art/fork/frontend, token adoption or completed user review inferred.
- **O8/name:** [preliminary search filed](../../research/2026-11-04-memoshi-name-and-trademark-preliminary.md). Exact-name Memoshi iPhone listing and Memoh overlap observed, not legal clearance. O8/trademark remain open; D59 identifiers unchanged.
- **Release rights:** existing provenance/notices findings carried. No paid-lawyer prerequisite added to private work; public/commercial/GPL combined-work questions remain before redistribution.

## 7. Cuts and carry-over

**No cut applied.** S6 has not moved to W25, S1 has not silently become remote-only, and S3 has not silently become foreground-only. Accepted cut/fallback rules need a recorded builder decision and their own checks. Phase0 gaps do not automatically become Phase1 carry-over.

## 8. Dogfood

Stage: development/qualification controls, not a completed week. Active-day, real-spend, crash-free and end-to-end usage series required by the gate are not provided. Accepted runtime/file recovery, real-provider and release/device inputs remain separate. Short automated runs do not count as elapsed dogfood days.

## 9. Lessons

**Keep:** original receipts/failing controls; exact SDK/admission boundaries; actual owned-process/native observation after source/tests.

**Change before re-gate:** obtain accepted recovery/fencing/file/backend contracts rather than shims; qualify real device/service/provider/site paths instead of relabeling prototypes; record user adoption and prescribed performance/dogfood/demo evidence.

## 10. Next-phase readiness and refreshed prerequisites

These are refreshed statuses for **existing dependent tickets**, not Phase1 admission or new scheduling:

| Existing ticket | Required before dependent expansion | Owner |
|---|---|---|
| CH-01 / SEC-01 | Accepted S1 baseline and full policy/recovery/approval/platform matrices | RT/APP/QA |
| MOD-01 | Two broker-provisioned real providers and authorized local endpoint; usage/cache/effort/compaction | RT/APP/QA |
| DEV-01 | Accepted H2 feeds/replicas/fences/intents; S2 real transports/physical/O10 | NAT/RT/QA |
| BRW-01 | Approved real sites, no-bypass gateway, native/mobile/accessibility qualification | NAT/APP/QA |
| CMP-02 | H3 plus full D96, authoritative kernel attribution and usability/performance | RT/NAT/QA |
| DIST-01 | G2/profiles/notarization/VM/helper/update/broker/physical TestFlight; actual size/CI receipts | NAT/APP/QA |
| SH-04 / SH-05 / BOT-01 | Canonical integration, user adoption and owned native/device QA/performance gaps; glyph/accent source gaps now implemented and smoked | PD/APP/QA |
| PY-03 / PY-04 | Qualified S6 route or approved W25 move, retaining D79 order | NAT/RT/QA |

External inputs: accepted SDK delivery/adoption receipt; broker-provisioned provider permissions; approved real-site/accounts/tasks; physical devices and authorized Apple/deployed-service capabilities; and, last, reference Macs/VM and signing/release qualification. Finish reachable source/owned-local clearing work first. This review grants none of those authorities.

Remaining owner actions are tracked in [HANDOFF §8](../../HANDOFF.md#8-next-moves):
D99's release domain before a release build (development sign-in runs on `memoshi-auth.pages.dev`), real account/site permissions,
physical device access, design/O8 review and, last, signing/reference/VM inputs. Rotation of
the previously exposed `BRAVE_API_KEY` and `GEMINI_API_KEY` has no completion receipt.
The [complete remaining-input inventory](../../../../evidence/2026-11-06-memoshi-phase0-s4-remaining-4aa86403/remaining-prerequisites.json)
also retains SDK/runtime/credentials/browser/S4/S6/device and formal closure dependencies.

### Current clearing queue (2026-11-06)

The [current prerequisite note](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/current-prerequisite-observations.json)
retains parent observations and explicitly identifies missing raw command logs. It is not
qualification evidence. The [device receipt](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/devices-current.json)
is the actual discovery output.

| Dependency | Current disposition | Exact clearing input |
|---|---|---|
| SDK | Exact consumer pin and both holds remain. No accepted delivery or adoption is established. | Source-bound qualifying slice, H0-H4 evidence and authorized consumer adoption. |
| Clean-source capacity | The earlier formal prerequisite refused 3 GB against its 15 GB floor. A later native build hit ENOSPC. Only owned fixture copies were moved reversibly. A newer `df` call times out; the [independent APFS receipt](../../../../evidence/2026-11-06-memoshi-pstack-safety.3KovFdGh/current-build-capacity-observation-20261107.json) records container-free capacity, not separate volume-quota or backing-image encryption qualification. Normal cached local CI does not require the formal floor by default. | Provision sufficient checkout-volume capacity for the unchanged formal guard without deleting unrelated data. External scratch and unsigned cached builds do not waive release/GitHub Actions admission. |
| Physical/service rows | Discovery found no physical device and four shutdown simulators. | Connected, provisioned reference devices and authorized CloudKit, APNs and deployed relay inputs. |
| Sites/providers | No new real-site/account corpus, paid call or model acquisition was authorized or performed. | Approved task/site/account corpus and provider or existing model inputs with explicit effect and spend scope. |
| D99 | Development host `memoshi-auth.pages.dev` is deployed (2026-11-10); Apple's CDN returned its association file on 2026-11-12. The release domain is not bought. | Release domain bought and attached to the same project before a release build; test sign-ins redone. |
| Native credentials/accessibility/lifecycle | Owned native browser and rendered AX controls pass. No system accessibility preference, Keychain lock state, production identity or physical service changes. | Authorized provisioned identity for locked/unattended and synced-secret checks. Operator-controlled VoiceOver/focus/RTL/contrast and physical background/helper/update scenarios remain separate. |
| Exposed-key rotations | No nonsecret completion receipt is recorded. Actual provider account state is unknown. | Operator confirmation of provider, revocation/replacement action and timestamp. No key values. |
| Release/references | No product signing, provisioning or deployment occurred. Existing tooling used disposable ad-hoc fixtures only. | Authorized identities/profiles, reference Macs and clean VM, then signed release/device measurements. |
| Formal closure | No qualifying week or consecutive complete demos were supplied. | Elapsed dogfood evidence, prescribed two-demo series, final reports, risk rescore and builder admission. |

