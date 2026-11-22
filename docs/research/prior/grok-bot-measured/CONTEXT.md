# Grok Bot as measured: MemoBot's domain vocabulary (secondary source)

**Status:** Draft 4 · 2026-10-20 · imported prior research; everything below the `BEGIN VERBATIM COPY` marker is a frozen, byte-identical copy of the source
**Owns:** Memoshi's archived copy of MemoBot's `CONTEXT.md`, the glossary behind its Grok Bot re-implementation, with a mapping to Memoshi's binding vocabulary
**Depends on:** [Research index](../../README.md) · [behavior.md](behavior.md) · [http.md](http.md) · [MASTER_PLAN §5](../../../plan/MASTER_PLAN.md#5-vocabulary-and-object-model) · [D4](../../../plan/decisions.md#d4) · [D33](../../../plan/decisions.md#d33)

> **Behavior reference only. Never copy assets.** MemoBot reuses Grok Bot's original static assets under a user-approved policy whose redistribution rights are unverified (see the header of [behavior.md](behavior.md)). Memoshi uses MemoBot's docs only to understand behavior and never copies a Grok Bot or MemoBot asset ([D33](../../../plan/decisions.md#d33)).

## Provenance

| Field | Value |
|---|---|
| Source file | `~/Projects/MemoBot/CONTEXT.md`, 2,492 bytes, SHA-256 `bb28e602b8c54ba26728dc178bfc6d3ca1573d39b6cf53e8b20d4e02315ad6c3`, last modified 2026-10-19 17:17 local time |
| What it is | The glossary of MemoBot, a local re-implementation of the Grok Bot desktop app ([behavior.md](behavior.md)). These are MemoBot's terms for the concepts its authors observed; they are not Grok Bot's own vocabulary |
| Evidence class | **Secondary source**, measured against Grok Bot desktop **0.71.2**. The installed app is now **0.72.0** (`/Applications/Grok Bot.app`, checked 2026-10-20) |
| Repo state | `~/Projects/MemoBot` is not a git repository and has no LICENSE file. The SHA-256 above pins the copied bytes |
| Imported | 2026-10-20: copied with `cp`, then this header was prepended. Nothing below the marker was edited |

Check the body against the source (prints `identical` while the source is unchanged):

```sh
sed '1,/^<!-- BEGIN VERBATIM COPY -->$/d' docs/research/prior/grok-bot-measured/CONTEXT.md \
  | diff - ~/Projects/MemoBot/CONTEXT.md && echo identical
```

## MemoBot terms in Memoshi vocabulary

Memoshi's terms are binding ([MASTER_PLAN §5](../../../plan/MASTER_PLAN.md#5-vocabulary-and-object-model), [D4](../../../plan/decisions.md#d4)). When a Memoshi doc borrows a behavior from MemoBot, it uses the Memoshi term. The mapping is ours [INFERENCE].

| MemoBot term | Memoshi term | Difference that matters |
|---|---|---|
| Workspace | none | Memoshi has one local user per Mac, so there is no isolated multi-account workspace. Do not confuse it with a Project |
| Bot | Bot | A Memoshi bot also has a job, a persona kept in the app record, a computer, a browser, grants and a budget ([D21](../../../plan/decisions.md#d21)) |
| Section | user-made section in the sidebar's Bots list | Presentation grouping ([MASTER_PLAN §6](../../../plan/MASTER_PLAN.md#6-experience-at-a-glance)), not an object in §5 |
| Conversation | Chat or Session | A Memoshi bot has exactly one Chat; Sessions are extra working threads. A MemoBot bot can have many conversations |
| Run | Task | Routine runs are Tasks (§5, rule 2) |
| Provider | model provider, through `pi-ai` | A model setting, not a Memoshi object ([D10](../../../plan/decisions.md#d10)) |
| Connection | Connector | Granted per bot in Memoshi. Grok Bot's connectors are account-wide ([profile](../../agentic-workspace-landscape/projects/grok-bot.md)) |
| Skill | Skill | A Memoshi Skill is a `SKILL.md` package scoped to a bot, a project or global |
| Knowledge document | a file in the bot's Library | Not Memory: a Memoshi Memory entry carries provenance, author, a validity window and visibility ([D22](../../../plan/decisions.md#d22)) |
| Approval | Approval | A Memoshi approval is tied to a policy rule and expires to denied ([D27](../../../plan/decisions.md#d27)) |
| Automation | Routine | Memoshi also has Watches and Wakes as separate objects ([D23](../../../plan/decisions.md#d23)) |
| Activity | event log and audit | Not a user-facing object in §5; see [`events.md`](../../../specs/events.md) |
| Parity scenario | none | MemoBot's acceptance cases against Grok Bot. Memoshi has no parity target |
| Clarification | question Card | One of the Card types in §5 |
| Voice call | voice conversation | v2 ([MASTER_PLAN §11](../../../plan/MASTER_PLAN.md#11-scope)) |
| Dictation | dictation | v1, on-device through SpeechAnalyzer ([D41](../../../plan/decisions.md#d41)) |

<!-- BEGIN VERBATIM COPY -->
# MemoBot

MemoBot is an independently implemented personal-agent application. A workspace owns its bots, conversations, knowledge, connections, and automation schedules.

## Language

**Workspace**: An isolated collection of user-owned agent data and configuration.

**Bot**: A named, configurable agent with an avatar, instructions, provider selection, knowledge, skills, and permissions.

**Section**: An owned named sidebar group, represented by a BotSection record and bot section references. It is separate from labels and pin order; removal ungroups bots without deleting them. Collapse is local presentation state.

**Conversation**: An ordered exchange of messages with one bot.

**Run**: One execution of a bot in response to a prompt or an automation trigger, including its model calls and any approved tool calls.

**Provider**: A configured public or locally hosted model-inference endpoint, distinct from MemoBot's own application backend.

**Connection**: A user-authorized integration exposing tools or resources to selected bots.

**Skill**: A reusable, user-managed instruction document that can be enabled for a bot.

**Knowledge document**: A file or note explicitly added to a bot's persistent reference library.

**Approval**: A user's decision about a specific consequential tool call before that call executes.

**Automation**: A persisted schedule that supplies a prompt to a bot at a defined time.

**Activity**: A durable record of a run, approval, integration action, or automation outcome.

**Parity scenario**: A behavioral acceptance case used to compare independently implemented clients, not a claim of identical private model internals.

**Clarification**: A persisted structured question with uniquely identified choices and optional human text/attachments. Its owner-scoped pending→answered transition creates one continuation run; it grants no consequential-tool permission. Canonical answer state informs later model context without rewriting the original tool log.

**Voice call**: Application-owned continuing spoken conversation with one bot/conversation, with lifecycle distinct from listening/thinking/speaking activity. Navigation does not transfer/end it; microphone mute does not cancel output speech. Input amplitude is measured; system-TTS bars represent activity, not measured output PCM.

**Dictation**: A single recording that supplies transcribed text to the composer. Dictation and a voice call cannot own the microphone simultaneously.
