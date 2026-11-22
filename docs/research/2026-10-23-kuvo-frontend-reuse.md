# Kuvo frontend reuse: source-informed assessment

**Status:** Research · 2026-10-23 · inspection authorized by [D91](../plan/decisions.md#d91); no code import or fork selected
**Inspected revision:** [`ddd492b30d52a5553e2ad6f4785dbf05507c7adc`](https://github.com/serhatandic/kuvo-code/commit/ddd492b30d52a5553e2ad6f4785dbf05507c7adc), observed as upstream HEAD, timestamp 2026-10-23T12:43:10Z. Source links below are pinned to it.

> **Subsequent design/staffing choice:** [D92](../plan/decisions.md#d92) adopts a Viticci-led Apple-native assistant family with Kuvo informing the workbench, not blanket pixel parity; [D93](../plan/decisions.md#d93) removes mandatory design contracting. The audit below predates those choices and still selects no fork/import, measures no porting savings and changes no engine or feature stage.

## 1. Conclusion

**[INFERENCE] Prefer selective presentation reuse over a wholesale Kuvo-fork cutover for the current Mac+iPhone+iPad product.** Useful small interfaces exist, but the complete frontend is not independent of its opencode-shaped application state and desktop host.

This is an architecture-fit recommendation, not measured porting effort or an adopted import. Keep Pi_Swift/Pi Durable, MemoshiProtocol, policy, recovery and device contracts authoritative. The separate [design recheck](2026-10-23-design-direction-review.md) asks which visual reference should lead; permitting source reuse does not answer that question.

## 2. Observed runtime and presentation seams

| Evidence | Observed interface or implementation | Consequence for Memoshi [INFERENCE] |
|---|---|---|
| [`SessionModel.swift:358–387`](https://github.com/serhatandic/kuvo-code/blob/ddd492b30d52a5553e2ad6f4785dbf05507c7adc/KuvoCode/Stores/SessionModel.swift#L358-L387) | Session state owns a private concrete `OpenCodeAPI`, reload/drain/send tasks and engine-message IDs; its initializer accepts `Session` and that concrete client | Changing a model-provider setting is insufficient. Retained views need a Memoshi presentation model and intents rather than a second engine authority |
| [`Composer.swift:8–115`](https://github.com/serhatandic/kuvo-code/blob/ddd492b30d52a5553e2ad6f4785dbf05507c7adc/KuvoCode/Views/Session/Composer.swift#L8-L115) | Text/files and send/queue/stop callbacks are explicit, but the interface also exposes `ToolApproval`, `ModelRef`, commands, folders and `Catalog`/`Workspace` environments | Potentially adaptable Mac interaction code, not a portable drop-in composer; preserve Memoshi's approval, origin, queue and cancellation semantics |
| [`EventStream.swift:3–75`](https://github.com/serhatandic/kuvo-code/blob/ddd492b30d52a5553e2ad6f4785dbf05507c7adc/Packages/OpenCodeKit/Sources/OpenCodeKit/Events/EventStream.swift#L3-L75) | The live feed explicitly has no replay; reconnection yields `.connected` and consumers refetch | This is different from Memoshi's sequenced replay/resync contract. Do not retain that contract merely to make existing views easier to connect |
| [`ServerProcess.swift:3–5,85–125`](https://github.com/serhatandic/kuvo-code/blob/ddd492b30d52a5553e2ad6f4785dbf05507c7adc/Packages/OpenCodeKit/Sources/OpenCodeKit/Engine/ServerProcess.swift#L85-L125) | Engine process hosting is guarded by `#if os(macOS)`; `ServerProcess` owns a Foundation process and private opencode server lifecycle | That host is not an in-process iPhone engine. Desktop UI/host reuse does not supply Memoshi's mobile implementation |
| [`Agents/src/agent.ts:184–221`](https://github.com/serhatandic/kuvo-code/blob/ddd492b30d52a5553e2ad6f4785dbf05507c7adc/Agents/src/agent.ts#L184-L221), [`turn.ts:20–61`](https://github.com/serhatandic/kuvo-code/blob/ddd492b30d52a5553e2ad6f4785dbf05507c7adc/Agents/src/turn.ts#L20-L61) | The multiple-agent seam is TypeScript `Thread.run`/`steer`/`interrupt`/`close`; `Turn` owns stored messages and emits `session.execution.started` | Real adapter support exists, but it normalizes into Kuvo/opencode-shaped state. It is not an interchangeable Swift Pi_Durable interface or proof of equivalent recovery |

Memoshi's accepted transport, event, permission and recovery interfaces remain in [protocol.md](../specs/protocol.md), [events.md](../specs/events.md), [policy.md](../specs/policy.md) and [04-architecture.md](../plan/04-architecture.md). Do not add an opencode-compatibility facade merely to avoid mapping the selected presentation values.

## 3. Actual small reuse candidates

These are candidate scopes, not copied modules or promises of savings.

| Candidate | Observed seam | Remaining work before selection |
|---|---|---|
| Diff folding and row presentation | [`ChangesPanel.swift:879–947`](https://github.com/serhatandic/kuvo-code/blob/ddd492b30d52a5553e2ad6f4785dbf05507c7adc/KuvoCode/Views/Session/ChangesPanel.swift#L879-L947): `DiffFolding.rows(for:expanded:file:)` maps line values into stable line/fold/gap rows; the fold view takes a count and expansion action | Establish the exact line/value/parser/style dependency closure. Exclude Git execution, commit/PR/Finder actions and desktop image loading; preserve Memoshi's review and action contracts |
| Small value-bound controls | [`PillPicker.swift:5–52`](https://github.com/serhatandic/kuvo-code/blob/ddd492b30d52a5553e2ad6f4785dbf05507c7adc/KuvoCode/Design/PillPicker.swift#L5-L52): options plus a selection binding, no engine calls | It still depends on `ActivePill`, theme animation, hover/pointer and surface helpers. Extract the selected behavior deliberately, not the entire title bar/theme |
| Larger composer/transcript surfaces | The composer has useful callback inputs, but also concrete engine/domain dependencies listed above | Compare adaptation against a new view consuming Memoshi values. Keyboard/IME, selection, accessibility, performance and mobile behavior remain unvalidated |

A source boundary is not runtime or portability proof. Source-derived visual constants also do not prove observed pixel geometry or motion in a running app; unknown Draft 3 measurements remain provisional until verified with named provenance.

## 4. Full fork versus selective reuse

- **Full personal fork:** authorized under D91, and can retain more existing Mac behavior. It also retains a product's navigation, state, process hosting and engine assumptions. No evidence here establishes it as the cheaper path for Memoshi's complete multi-device requirements.
- **Selective frontend reuse:** a better candidate for preserving Memoshi's runtime/domain design while avoiding needless duplication [INFERENCE]. Choose actual separable surfaces and adapt them to Memoshi's interface; do not import the surrounding engine or orchestration merely because a useful view lives beside it.
- **Independent implementation:** still valid where an extraction would recreate most dependencies. D91 removes a prohibition, not the need to evaluate each import.

## 5. Licence and provenance scope

**Observed:** Kuvo's [LICENSE](https://github.com/serhatandic/kuvo-code/blob/ddd492b30d52a5553e2ad6f4785dbf05507c7adc/LICENSE) is PolyForm Noncommercial 1.0.0. It permits qualifying noncommercial modifications and redistribution and requires terms and supplied notices for copies of any part. Its [NOTICE](https://github.com/serhatandic/kuvo-code/blob/ddd492b30d52a5553e2ad6f4785dbf05507c7adc/NOTICE) supplies the required copyright/commercial-rights notice.

For a selected import, record exact revision, files, changes, resources and dependency closure; preserve applicable terms and notices. Kuvo-authored changes to a permissively licensed dependency do not automatically have separately established permissive clearance. Prefer the original upstream library when that is the desired code and provenance is clearer.

Compatibility of retained PolyForm material with the GPL-linked iSH mobile app and any redistribution remains a specific rights question, not a conclusion that either implementation must be rewritten. Moving code into another module or swapping opencode does not establish compatibility or Apache-2.0 relicensing. No product artwork is selected for copying.

The current dependency licence scanner does not prove the provenance of vendored source. Any actual import must add the applicable records and scoped enforcement before consumption, as D91 requires; this review changes no executable allowlist.

## 6. Verification limits

Read-only source inspection, including repository-tree discovery and a focused seam review. No Kuvo clone, source import, source execution, app build/run, tests or benchmarks were performed. No Memoshi runtime behavior changed. No savings, compile success, runtime equivalence, mobile portability or legal-clearance claim is made.

The related [Viticci design review](2026-10-23-design-direction-review.md) reopens saved screenshots and earlier user requests. Neither note adopts a replacement frontend, changes D43's visual baseline, hires a designer or moves accepted feature stages/dates.
