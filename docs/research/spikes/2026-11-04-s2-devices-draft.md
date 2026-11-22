# S2 devices, links and leases: development scorecard

**Status: DRAFT, 2026-11-04. S2 is not qualified and O10 is open.** Native MLS, encrypted durable journals and local transport/recovery components are implemented and exercised below. They are not actual Pi-store replication, a physical Mac/iPhone/iPad matrix, provisioned CloudKit/APNs or deployed relay capacity. No platform/adoption/failover decision follows from a source implementation or a local test pass.

**Owners:** NAT for device identities, pairing and transports; RT for Pi transaction fencing/replication/effect recovery; QA for process/physical/reference measurements. **Authority:** [S2 acceptance and thresholds](../../plan/phase-0.md#s2), [D48](../../plan/decisions.md#d48), [D49](../../plan/decisions.md#d49), [D73](../../plan/decisions.md#d73), [D74](../../plan/decisions.md#d74), [D75](../../plan/decisions.md#d75), [D82](../../plan/decisions.md#d82), [D83](../../plan/decisions.md#d83), [O10](../../plan/decisions.md#open-decisions) and [04 §2.8](../../plan/04-architecture.md#28-devices-links-runners-and-replicas).

## 1. Current native integration result

The [clean integrated result][clean] exited 0 after the ownership/receipt repairs and removal of temporary diagnostics:

| Target | Tests | Suites | Observed test duration |
|---|---:|---:|---:|
| MemoshiTransportTests | 36 | 4 | 5.998 s |
| MemoshiDeviceTests | 63 | 15 | 1.159 s |
| MemoshiDeviceAppleTests | 28 | 5 | 0.918 s |

These are actual development-Mac native/crypto/transport/persistence tests, not reference-performance samples. Build time was 162.99 s and command wall time 339.23 s; neither is an O10 or transport latency distribution. The receipt is an explicitly labeled result extract, not a fabricated full console transcript. The separate current-wire process control below subsequently ran the actual owned executable.

### Reproduced failures and domain repairs

[Four new regressions failed before the repair][red], with nine issues. Feed catch-up consumed the inviter's final authenticated hello before the live pairing coordinator could receive the unchanged carrier. An interrupted join lost that completion receipt. A definitively false grant leaked its receipt, while an unavailable authority caused a potentially valid receipt to be consumed too soon.

- **Completion belongs to the pairing domain.** `DeviceGroup` now keeps a token-scoped live join owner; `PairingExchange.join` acquires/releases it on success and failure. No whole-pairing recovery gate prevents independent native feed progress.
- **The original proof remains durable.** `pendingJoin`/confirmation state survives authority adoption until actual completion. The retained hello must match the native-authenticated original inviter, Welcome epoch, local recipient and anchor. Ordinary Node dispatch cannot retire that reserved completion. Explicit interrupted recovery requires no live coordinator and fresh authoritative membership/full-feed reconciliation before finishing and acknowledging the exact receipt. A newer epoch is not an invented hello.
- **Authority unavailability differs from rejection.** A false grant is consumed only after an independent authoritative comparison. An unavailable execution authority retains the exact receipt; a narrow retryable message-window state allows reevaluation without adding another capacity slot or admitting an in-flight duplicate.
- **Node-owned seal/publication and native catch-up share an ownership boundary.** The diagnostic control observed an open current epoch with local sender cursor 2 but published cutoff 1 during catch-up. The Node now serializes its seal→publish path with the native-feed read. Domain receipt consumers run after that sending gate is released, because they may send authenticated responses themselves. Old-epoch cutoffs, immutable publication identity and authority checks remain strict.

The [intermediate full-suite extract][intermediate] retained the four repaired passes **and** three still-failing integration tests, rather than claiming a green suite. The final clean run retained real Noise/native traffic, canonical-history/receipt checks and subsequent legitimate commits. Fixtures now explicitly consume the real initial/successor lease notice before forwarding, compare immutable full rosters rather than different devices' self-excluding peer lists, and await owned teardown. Incidental diagnostic/wording pins were removed, not re-pinned to a different error string. The production checks were not loosened to accommodate a fixture.

A later [canonical run](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/canonical-final-e70f25c1/ci.log)
exposed one remaining handover-fixture ordering assumption: `rebalance` waits for the
successor's own grant, not the former runner's asynchronous lease projection.
The hostile same-sequence/receipt scenario now observes the exact successor/epoch
on the former runner before asking it to forward. No sleep, timeout increase,
production routing change or removed security assertion substitutes for that
precondition. The [complete current IPC/device run](../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/device-projection-ready-074174c0/command.log)
then passed all **36 transport, 63 device and 28 Apple-device tests**, including
the original receipt, conflicting-history and legitimate successor continuation
checks. This does not add physical, actual-Pi-store or deployed-service acceptance.

### Current-wire owned process control

The [first process attempt][process-identity-red] failed before pairing because the qualification driver wrote each probe's exclusive identity file before creating its private parent directory. The caller now creates that owned directory with mode 0700; the identity writer's exclusive/no-follow 0600 behavior is unchanged. A [subsequent external-image run][process-image] reached real pairing/replication but failed its relay burst: only 31 of 60 writes were admitted after a long publication/renewal stall and lease loss. Its failure remains recorded; no TTL, renewal interval, test count or fencing check was increased to pass.

The [same-binary private-SSD control][process-ssd] then exited **0 in 32.16 s**, with unchanged `--quick` scenario counts and timing. This is a storage-sensitive development control, not proof of the external-image stall's exact kernel cause or a reference/deployed capacity result.

| Current-wire observation | Actual result |
|---|---:|
| Fresh pairing probes | 5 |
| Direct / relay burst replica changes, in exact order | 60 / 60 |
| Rebalance handovers | 10 |
| Unique forwarded requests / original-result repeats | 20 / 2 |
| Old runner's attempted writes refused during expiry window | 670 |
| Successor's accepted writes during that same window | 86 |
| Accepted stale local writes / audited two-writer epochs | 0 / 0 |
| Relay canary hits / positive-control hits | 0 / 1,262 |

Raw per-series CSVs and distributions remain in the report directory. Native transport duplicate observations are deduplicated carriers, not duplicated committed application changes: both direct and relay exact-order checks passed. Normal process reopen retained the original forwarding receipt, runner payload, encrypted mailbox answers and expired-answer notice. The mailbox control does **not** apply a response to a real runner Card or display a native notice. Bonjour, real elapsed QR expiry and authority load were not selected; no result for them is implied. Unlike the older full run's empty expiry window, this reduced native-wire control contains actual competing attempts. It still writes prototype app metadata, **not Pi stores or copied external-effect intents**.

### 2026-11-07 lease-under-storage-stall repair (development evidence only)

The [renewal diagnosis](../../../../evidence/2026-11-07-memoshi-engineering/analysis/s2-renewal-diagnosis.md) found that retained quick-cohort lease losses were renewals sent before expiry but evaluated after it, behind synchronous durable writes on an external encrypted image. The relay now stamps each frame on the authority clock when NIO reads it, and `RelayLeaseAuthority` judges `claim` and `renew` expiry at that arrival time, never later than now. Epoch compare-and-swap, runner checks and `reserve`'s processing-time check are unchanged, and a renewal that *arrives* after expiry is still refused. The qualification relay's evidence journal is now an ordered background writer that `close()` drains, and `s2-measurements.json` gains a non-gating `storage` block (work volume plus before/after write+fsync probes).

[`LeaseArrivalTimeRegressionTests`](../../../../evidence/2026-11-07-memoshi-engineering/S2LeaseFix/01-ipc-arrival-before-fix.log) failed before the change (2 of 4: a stalled in-time renewal was refused; a stalled pre-expiry competing claim was granted) and [passed after it](../../../../evidence/2026-11-07-memoshi-engineering/S2LeaseFix/03-ipc-focused-after-fix.log) with the device boundary, frame-capacity, lease-authority and relay-security suites (29 tests). The blocked-journal-write regression [failed before](../../../../evidence/2026-11-07-memoshi-engineering/S2LeaseFix/02-daemon-journal-before-fix.log) and [passed after](../../../../evidence/2026-11-07-memoshi-engineering/S2LeaseFix/04-daemon-focused-after-fix.log) with the qualification suites (21 tests). TTL, renewal interval, burst size and the 60 s wait are unchanged. The retained R, C, S and F failures remain failures. Three internal-disk `--quick` cohorts [exited 1 before pairing](../../../../evidence/2026-11-07-memoshi-engineering/S2LeaseFix/internal-cohorts/): the harness ran a copied CLI without its `MemoshiCore_MemoshiStore` resource bundle, so the Mac child crashed at startup. They are an invalid setup, not a lease result, and no lease outcome is claimed. Their `storage` blocks did record internal APFS (`/dev/disk3s5`) with probe p50 0.05–0.08 ms and max 1.2–5.4 s. O10 must record arrival time as the expiry clock before this counts toward S2.

### 2026-11-08 renewal TTL and store-decoupled renewal (development evidence only)

A runner now renews by the TTL it claimed. Before, `DeviceNode` renewed by its configured default, so the S2 driver's 6,000 ms claims renewed to 10,000 ms, or to 3,000 ms once a scenario configured that default. In a retained 2026-11-07 cohort, [53 of 108 relay renewals asked for a different TTL than their device's latest claim](../../../../evidence/2026-11-08-memoshi-engineering/S2Followups/baseline-2026-11-07-cohort-1-ttl.json): 26 asked for 10 s after a 6 s claim, 24 for 3 s after a 6 s claim, and 3 for 3 s after a 10 s claim. A hand-over or take-over claim without a TTL keeps the node default. The renewal loop also no longer waits for the local store to record a renewal before its next tick. Each store lease write is queued per conversation in the order the node decided it, and a commit waits for that queue first. The queued write carries only the authority's granted expiry. A reply that lands after the node observed a newer epoch is not recorded, and the store's epoch-forward rule is unchanged. The device journal record is still written in the actor, as before.

[`LeaseRenewalTimingRegressionTests`](../../../../evidence/2026-11-08-memoshi-engineering/S2Followups/01-ipc-renewal-before-fix.log) failed before the change, 2 of 3: a 6 s claim renewed to 2 s (the test's node default), and 0 renewals were sent in 600 ms while one store write was held. The guard, a lease lost during a held write, passed before and after. After the change [all device suites passed](../../../../evidence/2026-11-08-memoshi-engineering/S2Followups/03-focused-after-fix.log): 88 `MemoshiDeviceTests` (including arrival-time, boundary and frame-capacity), 28 `MemoshiDeviceAppleTests`, and 11 qualification tests (S2 journal, storage and Store adapter). Three internal-disk `--quick` cohorts on the rebuilt CLI [exited 0](../../../../evidence/2026-11-08-memoshi-engineering/S2Followups/04-cohorts.log) with unchanged driver limits and `duplicateGrants` 0. Every relay renewal (146–148 per cohort, 86–88 of them for 6 s claims) asked for its claim's TTL, with 0 mismatches. Mac `renewed` events report `ttl_ms=6000` for those leases ([summaries](../../../../evidence/2026-11-08-memoshi-engineering/S2Followups/)). These cohorts ran on internal APFS, so they do not show behaviour under a storage stall.

The CloudKit lease authority cannot take D102's arrival-time rule ([analysis](../../../../evidence/2026-11-08-memoshi-engineering/S2Followups/cloudkit-arrival-time-analysis.txt)). Its decisions run on the deciding device's clock before the save. CloudKit's only server-side predicate is the change tag (`.ifServerRecordUnchanged`), and the lease deadline is end-to-end encrypted. `modificationDate` is known only after a save succeeds. Expiry under CloudKit therefore stays judged by device clocks, and cross-device clock skew is an open O10 risk.

### 2026-11-08 device journal off the node actor, and a stalled-medium control (development evidence only)

`DeviceNode` no longer blocks on a renewal's replica-journal write. Every journal append now runs on one ordered writer, so the journal keeps the node's decision order, but callers differ in what they wait for:

- **Renewal record: not awaited.** Recovery never trusts a journaled expiry. It re-reads the authority and resumes only the epoch the node already held, which a renewal does not change. A failed renewal write still fails the node closed.
- **Commit records: awaited without blocking the node.** The publication record is durable before the publish, and the change record is durable before `committed` or the broadcast. Other conversations keep renewing while a commit waits.
- **Everything else: blocks until durable, as before.** That covers lease decisions (claim, loss, membership fencing, hand-over, observed epochs) and replica applies. Their in-memory change and record must stay one actor turn, and they also wait behind any queued write.

The MLS group checkpoint is a separate actor and is unchanged.

[`DeviceJournalStallRegressionTests`](../../../../evidence/2026-11-08-memoshi-engineering/S2Round3/02-journal-stall-before.log) failed before the change: while one journal write was held, the node did not answer for 1 s and sent 0 renewals in 400 ms. The durability guards passed before and after: a commit stayed incomplete and unpublished while the write was held, and a failed renewal write failed the node closed. After the change, [the device, Apple and qualification suites passed](../../../../evidence/2026-11-08-memoshi-engineering/S2Round3/03-after.log): 90 `MemoshiDeviceTests`, 28 `MemoshiDeviceAppleTests` and 54 `MemoshiQualificationTests`. In the held-write test, the node answered, kept renewing, completed the commit after release, and reopened with the commit durable.

Three internal-disk `--quick` cohorts on the rebuilt CLI ([internal-1..3](../../../../evidence/2026-11-08-memoshi-engineering/S2Round3/)) exited 0 with `duplicateGrants: 0`. Relay renewals matching their claimed TTL: 153/155, 164/164 and 150/150. Both internal-1 misses are renewals of the expiry scenario's conversation, sent 1 ms before the authority refused them after the take-over. Their TTL read and `sentAt` stamp straddle the deliberate SIGSTOP (`rtt` 2.46 s and 2.85 s) [INFERENCE: the freeze landed between the two clock reads].

Three cohorts were then run with `--work-dir` on `/Volumes/MEW0`, alongside a timestamped `fsync` probe on the same volume, with unchanged limits ([mew0-1..3](../../../../evidence/2026-11-08-memoshi-engineering/S2Round3/), [correlation script](../../../../evidence/2026-11-08-memoshi-engineering/S2Round3/s2_correlate.py)). The volume is the encrypted ASIF image on a USB exFAT disk; the storage block reports `apfs`, removable. All three exited 1 with the same finding, `timeout waiting for phone rseq 60`, in the commit burst:

| Cohort | Longest probe stall | Probe stalls > 1 s | Renewal evaluation delays | Relay renewals applied/denied | Mac `renewRefused`/`leaseLost` |
|---|---|---|---|---|---|
| mew0-1 | 96.0 s `fsync` | 10 | 94.6 s, 94.1 s | 54/2 | 2/2 |
| mew0-2 | 33.0 s `write` | 9 | 32.5 s, 31.3 s | 44/2 | 2/2 |
| mew0-3 | 39.1 s `fsync` | 11 | 38.8 s, 37.8 s | 60/2 | 2/2 |

In each cohort the sequence matched the probe:

1. Each burst's two runner renewals were sent 0.3–1.9 s after the probe's longest stall began.
2. The authority evaluated them only when that stall ended, and granted them, because D102 judges a renewal at its arrival time.
3. The stall had outlasted the 6 s TTL, so the granted expiry had already passed. The next renewals were refused 0–95 ms after they were sent, and the Mac lost both leases.
4. Fencing held: `duplicateGrants: 0` and `claimsDenied: 0`.

No device emitted any event during the longest stall in each cohort ([windows](../../../../evidence/2026-11-08-memoshi-engineering/S2Round3/mew0-stall-windows.txt)). Every other relay renewal was evaluated within 1 s, and the Mac's `late_ns` stayed at or below 125 ms.

This is the expected D102/D104 limit, not a regression: when the authority's own durable write stalls past the TTL (here 33–96 s, also past the driver's 60 s wait), no lease design keeps the lease. S2 qualification still needs bounded-latency storage.

The probe does not show which process's write held the authority. [INFERENCE: the relay's journal and mailbox live on the same volume.] One side effect: after such a stall the authority answers `renewed: true` with an expiry already in the past. Nothing is written under that expiry, because commits re-check `expiresAt > now` with the authority, and the next renewal is refused. The scratch on MEW0 was deleted.

## 2. Implemented durable components and limits

The [qualification contract](../../../Packages/MemoshiDaemon/Sources/MemoshiQualification/README.md#s2-durable-device-and-authority-qualification-prototype) describes the current implementation and its exact run recipes:

- Durable authority state binds exact enrolled identities, membership/revocations, lease epochs/deadlines, reservations, immutable publications and signed full sender feeds. Native sealing checkpoints an ordinal/predecessor before publication; the same ciphertext is reused across carriers.
- Native ratchet state, authenticated plaintext/routing receipts and receive cursors/digests checkpoint before exposure. Exact consumed replay remains inert; reopening does not decrypt it again. A missing predecessor, unaccepted old-epoch seal or unresolved reservation holds recovery instead of discarding history.
- Owner-only, no-follow, stable-lock journals encrypt group/replica/publication/offline-approval state with identity-derived domain-separated AES-GCM keys. A missing half of initialized state fails closed. This does not establish malicious-owner rollback resistance, secure flash erasure, production retention/compaction or encrypted Pi replication.
- The device Keychain adapter uses a separate device-only `.devices` group with no plaintext/replacement fallback. Native pairing composes it only after explicit Start and retains encrypted unbound enrollment intent. The harness uses explicit synthetic 0600 identity files: it is **not** a new provisioned Keychain or physical pairing result.
- The Apple layer implements CKSyncEngine state/fetch, encrypted mailboxes, exporter-derived persistent-record AEAD and conditional group-head CAS. The native tests include exact retained receipts after four epoch retirements/restart, delayed >1024-generation feeds, current-manifest rekey checks and a real fragmented Noise carrier. None contacts a deployed CloudKit database or proves APNs delivery.

The native prototype pins mls-rs 0.57.0 and the Memoshi-owned UniFFI boundary; its [provenance](../../../Packages/MemoshiMLS/Native/PROVENANCE.json) and retained license inventory remain required. Existing native public-client/provenance/admission evidence is carried forward from the qualification contract. Source copy phases are not a signed-bundle result.

## 3. Carry forward the secured local process/load run

The [existing full secured local report][old-process] and [independent raw-sample verification][old-verifier] remain authoritative **within their original pre-current-wire scope**: 50 fresh confirmed pairing probes, 100 handovers, 20 frozen-runner takeovers/stale-write refusals, 400 unique forwards with 40 original-ID repeats and 12,642 accepted Chat/Session writes. The report's zero audited two-writer/backwards-epoch/stale-write outcomes and relay canary controls are retained, not recreated or relabeled.

Its expiry-window commit count was **zero**. It therefore does not establish nonvacuous simultaneous write attempts in that window. Its three Mac workers and local simulated-user load profiles do not establish physical-device behavior, current native-MLS wire qualification, actual Pi transaction feeds, CloudKit or deployed relay capacity. O10's renewal/idle policy and declared-load capacity remain unresolved.

## 4. Acceptance disposition

| Row | Current development evidence | Remaining acceptance / owner |
|---|---|---|
| S2.1 pairing | Real Noise/native MLS, exact enrollment/confirmation, replay/key-swap/closed-screen/deadline-boundary refusal, revocation and durable completion regressions pass | Actual app QR display/mobile scan, prescribed real elapsed expiry and physical revocation; NAT/QA |
| S2.2 direct link | Native TCP and Network.framework carrier interoperability on this Mac | Real Bonjour/local-network permission, tailnet/VPN and streaming latency distributions; NAT/QA |
| S2.3 iCloud | Source implementation and local authenticated state/ordering/recovery tests | Authorized app/helper profiles, private database encrypted round trip, content-free wake, launch/wake/backstop fetch and physical latency; NAT |
| S2.4 relay | Existing secured local encrypted relay/process proof and durable mailbox/native recovery tests | Deployed store-and-forward, actual content-free APNs and physical/offline delivery; NAT/QA |
| S2.5 handover | Local app-store lease/reservation/digest fencing, legitimate successor continuation and old secured process proof | **Actual Pi stores**, three permitted transport paths, physical/reference handover/expiry and accepted H2; RT/NAT/QA |
| S2.6 replicas | Durable native/canonical prototype history, exact consumed replay and delayed-feed recovery | Streaming Pi replicas and genuine day-offline catch-up through accepted transaction feeds/atomic ingest; RT/NAT/QA |
| S2.7 per-conversation leases | Existing independent Chat/Session local proof and native continuous-write handover tests | Physical simultaneous Chat/Session runners, home-Mac idle return and measured rebalance; RT/NAT/QA |
| S2.8 forwarding | Original-ID replay/canonical receipt checks and carried local multi-link process proof | Actual app-to-runner forwarding/streaming without moving a healthy runner across all required links; APP/NAT/QA |
| S2.9 offline approvals | Encrypted original-request mailbox, exact expiry and durable display notice tests | Apply before expiry/drop with notice against the same real runner Card/policy, device-owner authorization and physical/native display; RT/APP/NAT |
| S2.10 failover | Fresh authority is required; unresolved reservations and missing history fail closed | Accepted H2/H1 confirmed/provisional execution, copied intent **before** real effects, outcome checks and prescribed 50-kill no-repeat matrix; RT/QA |
| S2.11 racing | Local coordinator/transport recovery tests | Actual simultaneous Bonjour/VPN/CloudKit/relay racing, direct upgrade and loss/repeat measurements; NAT/QA |
| S2.12 authority load | Original raw local simulated-user profiles are preserved | CloudKit **and deployed relay** declared-load/active-idle measurements: claims/renewals, latency, retries/throttles, pushes, genuine expiry/fencing attempts and capacity/renewal policy; NAT/RT/QA |

## 5. Prerequisites and existing follow-ups

The adopted Pi consumer stays at `892585fc8d8be3093b58c34aacffcd4e68c3a8d9`. Native protocol/journal work is not an H2 transaction fence, read-only Pi replica, commit feed, safe-promotion or copied-intent implementation. An accepted qualifying SDK baseline and permitted adoption are prerequisites, not a reason to add a consumer shim or restore authority from a local lease file.

Physical/reference devices, authorized Apple capabilities, real links and deployed services remain separate inputs; [S5](2026-11-04-s5-distribution-draft.md) keeps their signing/distribution gates last. P0-10 and S2's existing owners retain the spike work; dependent DEV-01 and the device/runner tickets are refreshed only with actual decisions/evidence. This draft does not create a final spike verdict, resolve O10 or lift release/broader-qualification holds.

[clean]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-device-integrated-clean.json
[red]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/pairing-receipt-regressions-before-fix.json
[intermediate]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/pairing-receipt-regressions-after-fix.json
[old-process]: ../../../../evidence/2026-11-03-memoshi-wave3-integration/s2-current-full/s2-measurements.json
[old-verifier]: ../../../../evidence/2026-11-03-memoshi-wave3-integration/verify_s2_samples.py
[process-identity-red]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/s2-current-wire-77d82e37/s2-measurements.json
[process-image]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/s2-current-wire-67d57a47/s2-measurements.json
[process-ssd]: ../../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/s2-current-wire-ssd-d447f2b0/s2-measurements.json
