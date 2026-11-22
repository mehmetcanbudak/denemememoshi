# E21 — Pi_Swift discovery globals without a policy decision

- **Date:** 2026-11-16
- **Status:** Proposal. Not a decision, and not recorded in [policy.md](../specs/policy.md). The choice between the two routes below (declared metadata only, or an SDK hook) awaits the owner's decision ([HANDOFF §8, proposed decisions of 2026-11-18](../HANDOFF.md#proposed-decisions-2026-11-18)).
- **Sources:** [S1-runtime.md §4, E21 bullet](spikes/S1-runtime.md#4-proposed-decision-updates), [S1.10 policy coverage row](spikes/S1-runtime.md#3-outcome-table), [D103](../plan/decisions.md#d103), [D108](../plan/decisions.md#d108), [D134](../plan/decisions.md#d134), [D138](../plan/decisions.md#d138), [R4](../plan/risks.md#r4)

## What the row is about

Pi_Swift's engine exposes three **discovery globals** to a bot's Code Mode script: `searchTools`, `describeTool` and `describeNamespace` (`../Pi_Swift-slice-2/Sources/PiDurable/Codemode/Codemode.swift:67`). They let a bot *discover* what tools exist and what they take. They are not tool calls — they do not mutate anything.

The problem is that Memoshi's policy hook decides every **tool call**, but nothing in Memoshi decides what a bot may *discover*. S1.10 measured the tool side: 200 of 200 scripted calls from the three origins (model 52, Code Mode 50, MCP 98) were decided and audited by `beforeTool`, with blocks (denying and throwing authorizers) and redactions; argument rewrite was not run ([S1.10](spikes/S1-runtime.md#1-questions-answers-and-evidence)). So a bot can read the tool surface without Memoshi having a policy on it. The S1 row calls this **E21** and marks it open. R4 (policy coverage gaps, score 6) does not name E21 in [risks.md](../plan/risks.md#r4); only the S1 report's risk rescore ([S1 §7](spikes/S1-runtime.md#7-risks-re-scored)) cites it as a reason to keep R4 at 6.

## What Memoshi allows and denies

| Case | Disposition | Why |
|---|---|---|
| A bot calls `searchTools`, `describeTool` or `describeNamespace` | **Allowed today, with no policy decision** | They read declared metadata only. Nothing is mutated, nothing is secret. |
| A bot uses the discovery result to call a tool | **Decided by the normal tool hook** | The discovery itself is not the decision; the call is. |
| A discovery result is used to reach something not declared | **Not possible today; must not become possible** | The engine serves only declared metadata. |
| A discovery call is made by a foreign origin | **No policy exists; same gap** | The hook covers tool calls from all three origins, not discovery. |

## The two routes the S1 report proposes

1. **Record it as a policy note**: state that the three discovery globals read only declared metadata, that they are not tool calls, and that the tool hook still decides every call made using what they return. This is the cheaper route, and it is what this note proposes; nothing records it yet.
2. **Ask the SDK for a hook** (Pi_Swift side): give Memoshi a `beforeDiscovery` hook so discovery is also decided. This is the stronger route. This note does not propose it, because it is a Pi_Swift API change and Memoshi's pin is `slice-2` (D134), which does not expose such a hook.

## Argument rewrite is not measured

S1.10 also asks for a hook that can rewrite a call's arguments. That case was not run: the S1 report says "Argument rewrite was not run" ([S1.10](spikes/S1-runtime.md#1-questions-answers-and-evidence)), and the tool-origins evidence lists argument rewrite under "Not run" ([README](../../../evidence/2026-11-03-memoshi-tool-origins/README.md)). SEC-01 still owes it ([S1 §5](spikes/S1-runtime.md#5-phase-1-tickets)). No recorded case is a precedent for E21.

## What must NOT change before the gate

- **No new tool behaviour.** Discovery stays read-only. Nothing here is a product feature; it is a policy record.
- **No weakening of S1.10.** The 200/200 coverage stands; E21 is recorded as an open gap, not as a pass.
- **No change to R4.** It stays at 6 until E21 is closed or the owner decides it is acceptable at that score.
- **No change to the pin.** Route 2 stays a Pi_Swift item, not a Memoshi one.

## What stays open for Phase 1

- Whether the owner accepts "discovery reads declared metadata" as enough, or wants the SDK hook (route 2).
- Discovery on **iOS**: the S1.18 row is not run (no physical device). The policy text is platform-neutral; the coverage is not yet measured there.
- Whether discovery results may be cached or forwarded by a bot. Not decided; treat as not allowed until decided.