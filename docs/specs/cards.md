# Generated Cards

**Status:** Draft 4 · 2026-10-22 · updated for D44–D89 on 2026-10-23 · updated on 2026-11-13 for [D106](../plan/decisions.md#d106)–[D122](../plan/decisions.md#d122): JSON cards move to Phase 1, stream as the model writes them and can be updated in place; native diagrams and math are proposed for the catalog; an App is a page App or a Swift App with a pane, exported functions, view tools and selection carry, and the built-in panes are Apps on the same contract; connect cards, source chips, the call card and the mail cards are stated; the bot's digest of program actions (CH-31) moves to Phase 2
**Owns:** The JSON a bot writes for a `generated` card (catalog version 1): the envelope, the block catalog (the `tabs` block included), references, actions, validation, data rules, versioning and the fallback, accessibility, and the kinds that are never generated. Also the Swift engine that runs live cards and Apps: its language, compile step, interpreter, component kit, tool bridge, permission lists and signed bytecode cache (§11), and Swift Apps with their background jobs and widgets (§12). Since 2026-11-13 also: how a JSON card streams and is updated in place (§2.1, §2.2); native diagrams and math in cards (§3.1); the App contract where it meets cards and the engine: page Apps (§12.7), panes, places, exported functions, selection carry and the App-side surface for them (§12.9); the cards the built-in Apps produce (§12.10); and the card behaviour of connect cards, source chips, the call card and mail (§8.1–§8.4).
**Depends on:** [D53](../plan/decisions.md#d53), [D68](../plan/decisions.md#d68), [D71](../plan/decisions.md#d71), [D72](../plan/decisions.md#d72), [D74](../plan/decisions.md#d74), [D78](../plan/decisions.md#d78), [D79](../plan/decisions.md#d79), [D80](../plan/decisions.md#d80), [D81](../plan/decisions.md#d81), [D85](../plan/decisions.md#d85), [D87](../plan/decisions.md#d87), [D88](../plan/decisions.md#d88), [D89](../plan/decisions.md#d89), [D110](../plan/decisions.md#d110), [D111](../plan/decisions.md#d111), [D112](../plan/decisions.md#d112), [D114](../plan/decisions.md#d114), [D115](../plan/decisions.md#d115), [D116](../plan/decisions.md#d116), [D118](../plan/decisions.md#d118), [D119](../plan/decisions.md#d119), [D121](../plan/decisions.md#d121), [D67](../plan/decisions.md#d67), [D52](../plan/decisions.md#d52), [D50](../plan/decisions.md#d50), [D29](../plan/decisions.md#d29), [object-model.md §4.18](object-model.md#418-card-crd_), [§4.32](object-model.md#432-mini-app-app_), [§4.37](object-model.md#437-view-viw_) and [§4.38](object-model.md#438-voice-call-vcl_), [policy.md](policy.md), [events.md](events.md), [protocol.md](protocol.md), [03-design-system.md §8.5](../plan/03-design-system.md#85-generated-card-block-catalog), [02-experience.md](../plan/02-experience.md), [AMENDMENT_2026-11-13.md](../plan/AMENDMENT_2026-11-13.md)

A generated card lets a bot show anything that has no native card: a flight comparison, a plan, a dashboard, a checklist. The bot writes it in one of two ways ([D68](../plan/decisions.md#d68)):
- a **JSON card** is data. The app validates it against a fixed catalog of SwiftUI blocks and draws it natively on Mac, iPhone and iPad. There is no code, HTML or script in it, and it never fetches anything ([D53](../plan/decisions.md#d53)). From Phase 1 it streams as the model writes it and can be updated in place (§2.1, §2.2; [D115](../plan/decisions.md#d115));
- a **live card** is a small SwiftUI-style program that Memoshi's Swift engine runs inline in the conversation, with state, timers and tool calls that pass policy (§11), from Phase 2 on the Mac and Phase 3 on iPhone and iPad.

**Three layers** ([D115](../plan/decisions.md#d115), amending [D53](../plan/decisions.md#d53) and [D68](../plan/decisions.md#d68)). Generated interface comes in three layers, and this spec owns the first two. Layer 1 is the JSON card: native blocks from a fixed catalog, on the Mac in Phase 1 (CH-19, CH-25) and on iPhone and iPad in Phase 3 (CH-20). Layer 2 is bot-written Swift, live cards and Swift Apps, run by the engine of §11: Phase 2 on the Mac, Phase 3 on iPhone and iPad. Layer 3 is a sandboxed web page: page Apps (§12.7; CH-37, Phase 1), interactive artifacts (TP-07, Phase 1) and the screens connectors provide (MCP Apps; CH-45, Phase 2); of these, this spec covers only page Apps. Diagrams, charts and math draw natively (§3.1; CH-41). Generated motion and shader effects, and native 3D and Gaussian-splat views, are later design passes with no phase (EXPL-13, EXPL-14): nothing in the catalog or the kit provides them.

**Apps** ([D114](../plan/decisions.md#d114), [D119](../plan/decisions.md#d119)) are programs with versions, saved data and a permission list, built in or made by a bot. A bot-made App is a **page App**, a sandboxed web page (Phase 1 on the Mac), or a **Swift App**, run by the same engine as live cards (Phase 2 on the Mac); both reach iPhone and iPad in Phase 3. An App opens as a pane beside the chat, a side-panel tab on Mac and iPad and full screen on iPhone, or inline, and on the Mac also as a sheet over its conversation, a window or full screen ([D85](../plan/decisions.md#d85)); it may export functions to bots (§12.9). Background jobs and home-screen widgets arrive in Drop 1 ([D87](../plan/decisions.md#d87), §12).

The JSON shape follows Google's A2UI: the client keeps "a 'catalog' of trusted, pre-approved UI components", the agent "can only request to render components from that catalog", and the UI is "a flat list of components with ID references" ([A2UI](https://a2ui.org/); [generative UI research §7](../research/2026-10-22-python-and-native-generative-ui.md#7-native-generative-ui-premade-and-generated-cards)). Memoshi's catalog and field names are its own. [D115](../plan/decisions.md#d115) aligns the format with the open A2UI standard: the flat list with `id` references, A2UI's adjacency list, is what lets a card draw block by block while it streams and lets a later update name only the blocks that change (§2.1, §2.2; [generative UI survey §3](../research/2026-11-11-generative-ui-sota.md#3-pick-1-catalog-constrained-native-ui-streamed), read as the reason and not as authority). Whether D53's schema is kept and mapped to A2UI or A2UI's schema is adopted is decided by the survey's experiment A-E4 ([amendment §8](../plan/AMENDMENT_2026-11-13.md#8-open-items), item 4; Open question 2).

Features ([feature-catalog.md](../plan/feature-catalog.md)): CH-19 (generated cards, streamed; Phase 1 since [D115](../plan/decisions.md#d115)), CH-20 (on iPhone and iPad, Phase 3), CH-25 (the `tabs` block, Phase 1), CH-41 (native diagrams, charts and math, Phase 1), CH-21 (live Swift cards, Phase 2), CH-22 (Swift Apps on the Mac, Phase 2), CH-23 (Swift Apps, page Apps and App panes on iPhone and iPad, Phase 3), CH-24 (the Swift engine and component kit, Phase 2), CH-31 (the bot's digest of program actions, Phase 2 since [D114](../plan/decisions.md#d114)), CH-33 to CH-40 (the App contract in Phase 1: the pane and the places an App may add to, App functions, view tools, selection carry, page Apps, the self-check snapshot, Apps for all bots by grant, and App-drawn function calls), CH-43 and CH-44 (project-scoped Apps, and plugin developer mode with Full access on this Mac, Phase 2), CH-26 (App background jobs on Mac, iPhone and iPad, Drop 1), CH-27 (App widgets on Mac, iPhone and iPad, Drop 1), CH-28 to CH-30 and CH-32 (the signed bytecode cache, the rest of Swift, rich styling and the adaptive kit, Drop 1; [D87](../plan/decisions.md#d87)), CH-09 (the native card framework they sit in). Native cards and chips whose behaviour this spec states: CON-14 (connect cards), CON-15 and CON-16 (source chips), V2-09 (the call card), CON-08 and SEC-28 (mail), and AP-14 to AP-21 (the built-in Apps and the Apple-data cards they reuse).

---

## 1. Rules

1. **Data, or code only the engine runs.** A JSON card is data drawn by built-in blocks, and nothing in it runs. A live card or Swift App is Swift that only Memoshi's own interpreter runs; it reaches nothing outside the component kit and the tool bridge, and it loads no native code, HTML or scripts (§11, [D68](../plan/decisions.md#d68)). A page App is the one place where HTML and scripts run: in a sandboxed web view of its own, never inside a card, and reaching tools only through the same bridge (§12.7, [D114](../plan/decisions.md#d114)). Plugin developer mode's compiled plugins are not engine programs and run in a separate helper on the Mac (§12.11).
2. **Untrusted input.** JSON and Swift alike are model output. JSON is validated and size-limited, as it streams and again before it is stored (§2.1); Swift is compiled and runs within the interpreter's work and memory limits (§11.8). Both are drawn as plain content: text never becomes app chrome, and the only markup the app reads in it is the inline bold, italic, code and https links of a `text` block (§3, [D81](../plan/decisions.md#d81)).
3. **No fetching of its own.** A JSON card shows only data the bot's run produced. Images and files are references to the run's own attachments and artifacts, never URLs ([§6](#6-data-rules)). A program fetches only through tools, which pass policy (§11.6).
4. **Every action passes policy.** A button on a JSON card names a declared action: a tool call, a message to the bot, or an open. Pressing it is a policy decision under the bot's permission mode, exactly like a tool call the model makes ([D52](../plan/decisions.md#d52)). A program's tool calls are decided the same way, within the permission list the user approved for it (§11.6, §11.11).
5. **Decisions are native.** Approvals, drafts, sign-in, purchases, Resume and Apple data are native cards. A generated card or a program can never imitate them, and an action that needs one opens the native card instead ([§8](#8-kinds-that-are-never-generated)). An App, page or Swift, built in or bot-made, never adds to, draws or replaces approval, draft, sign-in or purchase cards, permission sheets, the composer or the title bar ([D114](../plan/decisions.md#d114), §12.9).
6. **One look.** Blocks take their style from the design tokens. A JSON card or a live card chooses only semantic options (`tone`, `style`, `level`); it sets no colors, fonts or sizes. An App may style its own canvas (§11.5).

---

## 2. Envelope

A bot posts a card through Memoshi's card tool ([D8](../plan/decisions.md#d8)). The runner validates it; the stored Card's `payload` holds the validated JSON ([object-model §4.18](object-model.md#418-card-crd_)). A bot may instead write a live card in Swift, which the engine runs; it has no envelope of its own and is specified in §11 ([D68](../plan/decisions.md#d68)). §2–§7 describe JSON cards. JSON cards ship on the Mac in Phase 1 (CH-19, [D115](../plan/decisions.md#d115)) and on iPhone and iPad in Phase 3 (CH-20); live cards follow with the engine in Phase 2.

```json
{
  "catalogVersion": "1.0",
  "title": "Flights to Lisbon, 14 November",
  "summary": "Three options under €300",
  "root": "b1",
  "blocks": [
    { "id": "b1", "type": "stack", "axis": "vertical", "children": ["b2", "b3", "b4"] },
    { "id": "b2", "type": "text", "text": "Prices checked at 09:40 on the airline sites." },
    { "id": "b3", "type": "table",
      "columns": [
        { "key": "dep", "title": "Departs", "format": "time" },
        { "key": "dur", "title": "Duration", "format": "duration" },
        { "key": "price", "title": "Price", "format": "currency", "currency": "EUR" }
      ],
      "rows": [
        { "dep": "2026-11-14T09:10:00Z", "dur": 9900, "price": 214 },
        { "dep": "2026-11-14T13:35:00Z", "dur": 10500, "price": 189 }
      ] },
    { "id": "b4", "type": "button", "title": "Ask me to hold the 09:10 flight", "style": "primary", "action": "a1" }
  ],
  "actions": [
    { "id": "a1", "kind": "message", "text": "Hold the 09:10 flight." }
  ],
  "replaces": null
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `catalogVersion` | string `major.minor` | yes | The catalog the bot wrote against ([§7](#7-versions-and-the-fallback)) |
| `title` | text(≤120) | yes | The card's title; also used in the Inbox and on other devices |
| `summary` | text(≤200) | yes | One plain line for lists and VoiceOver; never in a push payload ([D48](../plan/decisions.md#d48)) |
| `root` | block ID | yes | The block drawn at the top |
| `blocks` | block[] | yes | A flat list; blocks refer to each other by `id` |
| `actions` | action[] | no | Declared up front; buttons and rows refer to them by `id` ([§5](#5-actions)) |
| `replaces` | `ID<crd>` | no | A newer version of an earlier card from the same bot in the same conversation. The old card collapses to a one-line "Updated" link, and its buttons are disabled ([D81](../plan/decisions.md#d81)). To change a card where it stands, the bot updates it in place instead ([§2.2](#22-updating-a-card-in-place)) |

Every block has `id` (unique in the card, `[a-z0-9_]{1,24}`) and `type`. Blocks are listed once and placed by reference, so the same block may not appear under two parents.

### 2.1 Streaming

From Phase 1 a JSON card streams: its blocks appear as the model writes them ([D115](../plan/decisions.md#d115); CH-19). The runner's runtime emits the card's partial data, and the app validates it as it arrives and draws what is valid so far ([amendment §6](../plan/AMENDMENT_2026-11-13.md#6-where-the-new-parts-run); [04 §4.15](../plan/04-architecture.md#415-cards)). The flat list is what makes this work: a block is complete in itself and names its children by `id`, so the app can draw it before the blocks it refers to have arrived. This is A2UI's adjacency-list model ([generative UI survey §3](../research/2026-11-11-generative-ui-sota.md#3-pick-1-catalog-constrained-native-ui-streamed)); the survey is the reason for the alignment, and the rules below are Memoshi's own.

1. **What streams.** The JSON a bot passes to the card tool, while the model is still writing that call. A live card does not stream: its file compiles whole (§11.7). An update streams like a first post (§2.2).
2. **Whole blocks.** Partial data travels as a UI-only frame, `card.delta`: `{ cardId, toolCallId, rev, set?, blocks?, actions? }` ([events.md](events.md), [protocol.md §7.4](protocol.md#74-ui-only-frames)) [INFERENCE: the frame's name and shape are set in Phase 1]. `set` carries `catalogVersion`, `title`, `summary` and `root`; `blocks` and `actions` carry whole blocks and whole actions, added or replaced by `id`, never part of a block; `rev` counts from 1 without gaps for one card. A block the model is still writing is not sent and not drawn.
3. **Order.** `catalogVersion`, `title`, `summary` and `root` come first, so the frame and the title can draw at once; then `blocks`, parents before children; then `actions` [INFERENCE: the order the card tool's schema asks for is set in Phase 1]. A card that arrives in another order is still valid: order changes only how soon it draws.
4. **Partial data is not a Card.** The frames go only to the devices that are showing the conversation, like the text deltas of a message. Nothing is stored, replicated or audited while a card streams, and a frame may be dropped: a device that missed one waits for the finished card.
5. **Validated as it arrives.** The app applies §3's field rules and §4's reference rules to each block as it arrives, and draws it then. A reference to a block that has not arrived yet shows a placeholder in its place until it does [INFERENCE: the placeholder's look is set in the design review, [03 §8.5](../plan/03-design-system.md#85-generated-card-block-catalog)]. A block that fails shows §7's fallback row, as in a finished card.
6. **Limits hold while streaming.** The limits of §3 and §4 (120 blocks, 64 KB, depth 8, and each block's own) apply to partial data too. When a stream passes one, the app stops drawing new blocks, and the card ends as §7 says for a card that fails as a whole [INFERENCE: set in Phase 1].
7. **Drawn blocks do not move.** A block already on screen keeps its place when later ones arrive, as streamed prose does ([03 §8.5](../plan/03-design-system.md#85-generated-card-block-catalog)).
8. **Nothing runs from a card that is still arriving.** Buttons, links and row actions are inert, and input blocks submit nothing, until the card is stored: the runner checks a press against the stored card (§5), and a card that is still streaming has none [INFERENCE: when the controls look active is set in the design review].
9. **The finished card decides.** When the model has finished the call, the runner validates the whole card as before and stores it (§2, §7), which writes `card.created` once; the card tool's result names any block that failed. The stored `payload` replaces whatever a device assembled from the frames, so a stored Card never depends on what a device drew ([04 §4.15](../plan/04-architecture.md#415-cards)).
10. **A stream that ends early.** If the run stops, fails or is interrupted before the whole card reaches the card tool, no Card is written and the partly drawn card is removed [INFERENCE: set in Phase 1]. A card that fails validation as a whole becomes §7's `error` card.
11. **No secrets.** The output scrubber runs on the stored JSON (§6). How partial data is scrubbed before it leaves the runner is set in Phase 1 with [policy.md §13](policy.md#13-secrets-in-policy) [INFERENCE: it must be no weaker than for streamed message text].

### 2.2 Updating a card in place

A bot can change a JSON card it posted without posting a new one ([D115](../plan/decisions.md#d115); Phase 1, with CH-19) [INFERENCE: the card tool's `update` operation, its arguments and the rules below are set in Phase 1; D115 fixes only that catalog cards stream and follow A2UI].

- **By `id`.** An update names the card and carries blocks, and optionally `title`, `summary` and `actions`: `{ cardId, blocks, title?, summary?, actions? }`. A block whose `id` the card already has replaces that block. A block with a new `id` is added, and a parent's `children` in the same update must place it. A block leaves the card when no parent names it any more. `root` and `catalogVersion` do not change. Because the card is a flat list, an update sends only the blocks that change, never the whole tree.
- **Validated whole.** The runner applies the update to the stored card and validates the result with every rule of §3–§7, limits included. A result that fails as a whole changes nothing, and the bot gets the errors in the tool's result; a single block that fails renders as the fallback row (§7).
- **The same Card.** The card keeps its `id`, its place in the transcript and its frame. The runner stores the new `payload` and emits `card.updated` ([events.md](events.md)), so every device redraws it. Blocks the update did not name stay as they are, and an input block whose `id` and `type` are unchanged keeps what the user typed on that device [INFERENCE].
- **Who and when.** Only the bot that posted the card, from a run in the same conversation. A card that a newer one `replaces` can no longer be updated. An update is classified like posting the card ([policy.md §10.6](policy.md#106-generated-cards)). It is still a run's data: a card has no timers and fetches nothing, so it changes only when a run of its bot updates it (§6).
- **Streams.** An update streams like a first post (§2.1), with `card.delta` frames for the same `cardId`: its blocks redraw as they arrive, and the stored result decides. An update that fails or ends early leaves the stored card as it was.
- **`replaces` stays** for a new card that should appear as the newest entry in the conversation; the old one collapses to its "Updated" link (§2). An update is for a card that should change where it stands, such as a progress card or a table that gains rows.
- **Live cards** are not updated this way: the bot posts a newer card with `replaces` (§11.2).

---

## 3. Block catalog (version 1)

Twenty-six blocks in five groups. Their look, states and accessibility are in [03-design-system.md §8.5](../plan/03-design-system.md#85-generated-card-block-catalog); this table is the wire contract. The catalog ships on the Mac in Phase 1 (CH-19; `tabs` is CH-25) and on iPhone and iPad in Phase 3 (CH-20) ([D115](../plan/decisions.md#d115)).

| Group | Block | Fields (beyond `id`, `type`) | Limits |
|---|---|---|---|
| Layout | `stack` | `axis` (`vertical`, `horizontal`), `spacing` (`tight`, `normal`, `loose`), `children` | ≤ 12 children |
| Layout | `grid` | `columns` (2–4), `children` | Collapses to one column at compact width; ≤ 24 children |
| Layout | `section` | `title`, `footer?`, `children` | ≤ 12 children |
| Layout | `divider` | — | — |
| Layout | `tabs` | `tabs`: `[{ title, symbol?, children }]`, `initial?` (the index of the tab shown first; default 0) | 2–6 tabs; title ≤ 24; ≤ 12 children per tab |
| Text and media | `heading` | `text`, `level` (1–3) | text ≤ 120 |
| Text and media | `text` | `text`, `emphasis?` (`none`, `secondary`, `strong`) | text ≤ 2,000; plain text with line breaks and inline Markdown for bold, italic, code and links ([D81](../plan/decisions.md#d81)): a link must be `https:`, shows its domain and opens in the in-app browser; no images or other markup |
| Text and media | `label` | `text`, `symbol` (from the allowed SF Symbols list) | text ≤ 120 |
| Text and media | `badge` | `text`, `tone` (`neutral`, `info`, `success`, `warning`, `danger`) | text ≤ 24; the text carries the meaning, the tone only reinforces it |
| Text and media | `image` | `source` (`attachment:` or `artifact:` reference from the run), `alt` (required), `aspect?` | ≤ 4 per card |
| Text and media | `code` | `text`, `language?` | ≤ 200 lines; shown, never run |
| Data | `keyValue` | `items`: `[{ key, value, format? }]` | ≤ 20 items |
| Data | `list` | `items`: `[{ title, subtitle?, value?, badge?, action? }]` | ≤ 50 items |
| Data | `table` | `columns`: `[{ key, title, format? }]`, `rows`: `[{ key: value }]`, `sortable?` | ≤ 8 columns, ≤ 50 rows |
| Data | `chart` | `mark` (`bar`, `line`, `area`, `point`, `sector`), `series`: `[{ name, points: [{ x, y }] }]`, `xTitle?`, `yTitle?`, `summary` (required) | ≤ 4 series, ≤ 500 points in total; drawn with Swift Charts |
| Data | `metric` | `label`, `value`, `format?`, `delta?`, `trend?` (`up`, `down`, `flat`) | — |
| Data | `progress` | `value` (0–1) or `steps`: `{ done, total }`, `label?` | — |
| Data | `timeline` | `items`: `[{ time, title, detail? }]` | ≤ 30 items |
| Data | `map` | `pins`: `[{ lat, lon, title }]`, `region?` | ≤ 20 pins; coordinates come from the run; MapKit draws the map, the card fetches no places |
| Input | `textField` | `name`, `label`, `placeholder?`, `kind` (`text`, `number`, `email`), `value?` | value ≤ 500 |
| Input | `choice` | `name`, `label`, `options`: `[{ value, title }]`, `multiple?`, `style?` (`list`, `segmented`, `menu`) | ≤ 12 options |
| Input | `toggle` | `name`, `label`, `value?` | — |
| Input | `datePicker` | `name`, `label`, `mode` (`date`, `time`, `dateTime`), `value?`, `min?`, `max?` | — |
| Input | `slider` | `name`, `label`, `min`, `max`, `step?`, `value?` | — |
| Actions | `button` | `title`, `style` (`primary`, `secondary`, `destructive`), `action` | ≤ 3 buttons per stack; one `primary` per card |
| Actions | `link` | `title`, `action` (an `open` action) | — |

**Formats** for table cells, `keyValue` values and `metric`: `text`, `number`, `percent`, `currency` (with an ISO 4217 `currency`), `date`, `time`, `dateTime` (ISO 8601, shown in the user's time zone), `duration` (seconds). The app formats values with the user's locale, so a card sends raw typed values and never preformatted dates or currencies when a format exists. When the bot lacks a raw value, it may send plain text instead, marked with the `text` format ([D81](../plan/decisions.md#d81)).

**Tabs** (CH-25, [D68](../plan/decisions.md#d68)). A `tabs` block shows a row of tab buttons above the blocks of one tab at a time, such as Hours and Days on a forecast, or Summary, Trades and Chart on a backtest. Switching tabs is local to the device that draws the card: it sends nothing to the bot and runs no action. Each device remembers the last tab it showed for a card, without syncing it, and opens the card on that tab next time; a device that has not shown the card opens it on `initial` ([D81](../plan/decisions.md#d81)). Each tab's `children` are placed under that tab only (§4). Input blocks in a hidden tab keep their values, and an action can still read them. The row is a segmented control, or a menu when the titles do not fit the width; accessibility is in §10.

```json
{ "id": "b5", "type": "tabs", "initial": 0,
  "tabs": [
    { "title": "Summary", "children": ["b6", "b7"] },
    { "title": "Trades", "symbol": "list.bullet", "children": ["b8"] },
    { "title": "Chart", "symbol": "chart.xyaxis.line", "children": ["b9"] }
  ] }
```

### 3.1 Diagrams, charts and math

Diagrams, charts and math draw natively from Phase 1, in messages and in cards, with no web view ([D115](../plan/decisions.md#d115); CH-41; [amendment §4.5](../plan/AMENDMENT_2026-11-13.md#45-apps-and-generated-interface-d114-d115)).

| Kind | In a card | Drawn by |
|---|---|---|
| Chart | The `chart` block above, unchanged: `bar`, `line`, `area`, `point`, `sector` | Swift Charts |
| Diagram | A `diagram` block: `source` (Mermaid text), `summary` (required, as for `chart`) [INFERENCE: the block's name, fields and limits are set in Phase 1] | Pele_Swift |
| Math | A `math` block: `source` (the formula), `alt` (required) [INFERENCE: the block's name and fields, the notation and the renderer are set in Phase 1] | A renderer chosen in Phase 1 (CH-41) |

- **A minor version.** `diagram` and `math` are not among version 1.0's twenty-six blocks. If Phase 1 makes them blocks, they arrive as a minor catalog version (§7), so a device that does not know them shows the fallback row [INFERENCE: whether a diagram is a catalog block or only part of message rendering is set in Phase 1, [04 §4.15](../plan/04-architecture.md#415-cards)].
- **Data, not code.** A diagram's or a formula's source is text that the app parses and draws. Nothing in it runs, no link in it is followed, and it loads nothing (§1, rules 1 and 3). A source the renderer cannot parse shows as its plain text in place of the drawing, and the bot is told (§7).
- **Semantic only.** Both take their colors and type from the design tokens (§1, rule 6; [03 §8.5](../plan/03-design-system.md#85-generated-card-block-catalog)).
- **Later stages.** Generated motion and shader effects, and native 3D and Gaussian-splat views, are later design passes with no phase (EXPL-13, EXPL-14; [D115](../plan/decisions.md#d115)). The catalog has no block for them, and a JSON card has no animation, timer or 3D content of its own.

---

## 4. References and structure

- `root` and every `children`, `action` and `source` reference must resolve within the card or the run.
- The block graph is a tree: no cycles, no block with two parents, depth ≤ 8.
- A card has ≤ 120 blocks and its JSON is ≤ 64 KB; the limits are tuned in Phase 1, when JSON cards ship ([D115](../plan/decisions.md#d115)) [INFERENCE: the tuning moved with CH-19]. They hold while a card streams and after every update (§2.1, §2.2).
- Input blocks hold their values on the device that draws the card until an action submits them.

---

## 5. Actions

| `kind` | Fields | What pressing it does |
|---|---|---|
| `tool` | `tool`, `args` | A typed tool call ([D50](../plan/decisions.md#d50)) decided by policy under the bot's mode, as if the model had made it; its tier, card and audit row are the tool's ([policy.md](policy.md)). The bot sees the call and its result in its next turn |
| `message` | `text` | Sends `text` into the bot's Chat as the user's reply, so the bot continues once admitted. The user sees the message before it is sent when it carries input values. If neither the runner nor an available allowed model is reachable, use the persistent local unsent queue with the original `requestId`, **Waiting for connection** and cancellation before delivery; no answer or effect is fabricated ([D88](../plan/decisions.md#d88), [protocol.md §5.3](protocol.md#53-conversations-chats-sessions-groups)) |
| `open` | `target` (`artifact:`, `attachment:` or `https:` URL) | Opens an artifact in its viewer, or a URL in the bot's browser after the browser's site policy ([D18](../plan/decisions.md#d18)); never in a web view inside the card |

- **Inputs.** An action's `args` may take values from input blocks by name: `{ "date": { "input": "b7" } }`. Values are type-checked against the tool's schema before the policy decision.
- **Who presses.** Only the user presses buttons. A card action is always attended, and the press is checked again by the runner of the card's conversation, whichever device the user pressed it on ([D49](../plan/decisions.md#d49), [D74](../plan/decisions.md#d74)).
- **Money and credentials.** An action whose tool would spend money or use, reveal or grant a credential opens the native `purchase` or `sign_in` card instead of running, in every mode, Bypass included ([D52](../plan/decisions.md#d52)).
- **Destructive style.** `style: destructive` is a visual hint only. Policy decides from the tool's tier, never from the button's style.
- **No auto-press.** A JSON card has no timers, no on-appear actions and no default action bound to Return. A live card or App may run code when it appears or on a timer, and an App in its background jobs; those tool calls are the program's own, never the user's (§11.6, §12.4).
- **Opening an App.** A card never holds an App (§12.9). A button opens one with a `tool` action that calls `view.open`, the bot's view tool, which changes only what is shown ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps), item 14) [INFERENCE: `view.open`'s arguments are set in Phase 1].

---

## 6. Data rules

- A JSON card is a snapshot of data the bot's run already holds. It has no live queries, timers or polling; a bot that wants to show new data updates the card in place (§2.2), posts a new card with `replaces`, or writes a live card that fetches through tools (§11).
- Images and files come only from the run's `attachment:` or `artifact:` references. Remote URLs are rejected at validation; there is no image loading from the network.
- The JSON must carry no secrets. The runner's output scrubber runs on it before storage, as on any tool output ([policy.md](policy.md)).
- Cards sync to every paired device as part of the conversation's replica ([D49](../plan/decisions.md#d49)); pushes about a card carry no card content ([D48](../plan/decisions.md#d48)). The partial data of a card that is still streaming goes only to the devices showing the conversation and is never part of the replica (§2.1).

---

## 7. Versions and the fallback

- `catalogVersion` is `major.minor`. A minor version adds optional fields or new blocks; a major version may change meaning.
- The app draws every block its version knows. A block that fails validation renders as a plain fallback row ("This part can't be shown") in its place, and the rest of the card still draws, so one bad block does not hide a card; the card tool's result tells the bot which blocks failed and why, so it can fix and repost ([D81](../plan/decisions.md#d81)). A block type the device's version does not know renders the same row, with **Update Memoshi**.
- A card that fails validation as a whole (missing `root`, cycles, over the limits) is stored with its error and shown as an `error` card that names the problem; the bot receives the validation errors as the card tool's result, so it can fix and repost.
- The bot's prompt carries the catalog of the app version on the runner of its conversation, so bots target the runner's newest version, not the oldest among the user's devices ([D81](../plan/decisions.md#d81)); an older device shows the fallback row, with **Update Memoshi**, for each block it cannot draw.
- Live cards and Swift Apps carry the engine and kit versions they compiled against instead of `catalogVersion`, with the same fallback for a device that is too old (§11.10).
- **The catalog is the boundary** ([D115](../plan/decisions.md#d115)). A bot can ask only for blocks the catalog names, and the app draws only blocks it ships. A `type` outside the catalog is never interpreted, fetched or handed to a web view: it renders as the fallback row above, while the card streams and when it is stored, as before D115. Aligning with A2UI does not widen this: a card from another agent would render only through this catalog (Open question 2).
- **While a card streams** the same fallbacks apply block by block (§2.1); what the bot is told comes from the stored card's validation.

---

## 8. Kinds that are never generated

A Card has one of twenty-one kinds today ([object-model §4.18](object-model.md#418-card-crd_)): `generated`, which this spec defines, and the twenty native kinds below, which the app draws from typed payloads. From Phase 2 there are twenty-two, with `voice_call` (§8.3; [D111](../plan/decisions.md#d111)).

- **Decisions:** `approval`, `draft`, `question`, `form`, `secure_form`, `sign_in`, `purchase`, `grant_request`, the proposals (`routine_proposal`, `memory_proposal`, `bot_proposal`), `takeover_request` and `resume`. A connect card is the `sign_in` card with `variant: connector` (§8.1).
- **Apple data:** `apple_data` for Reminders, Calendar, Music, Weather, Maps, Contacts and Photos ([D50](../plan/decisions.md#d50), [D53](../plan/decisions.md#d53)). From Drop 2, each is a live view of the real item, not a picture of it ([D79](../plan/decisions.md#d79); AP-12, [D87](../plan/decisions.md#d87)): it shows the item's current state and freshness ([object-model.md §4.18](object-model.md#418-card-crd_), `resource`), re-reads the item before any write, shows a conflict instead of overwriting when the item changed elsewhere, and marks a write that timed out "outcome unknown" until a re-read settles it. A refresh never rewrites what an earlier decision card recorded.
- **System:** `handoff`, `budget_warning`, `budget_stop`, `run_summary`, `error`, and `setup_checklist`, which lists an imported bot's missing setup ([bot-definition.md §5.5](bot-definition.md#55-commit), [D82](../plan/decisions.md#d82)). From Phase 2 a finished voice call leaves a display card of kind `voice_call`, the 22nd kind (§8.3).

A generated card that tries to look like one of these (for example, an "Approve" button whose action is a message) is still only a generated card: it carries the generated-card frame and never resolves an approval, because approvals resolve only through `cards.respond` on a native card ([protocol.md](protocol.md)).

Live cards and Apps cannot draw these either. The component kit has no decision cards, a program draws only inside its frame, and the Apple-data views the kit offers are display components whose controls are tool calls under policy (§11.5). A page App draws only inside its web view's frame (§12.7).

### 8.1 Connect cards

A connect card is the native `sign_in` card with `variant: connector` ([object-model §4.16](object-model.md#416-connector-con_), [§4.18](object-model.md#418-card-crd_); [D112](../plan/decisions.md#d112); CON-14, Phase 1). It is not a new kind.

- **When.** Connecting an entry of the built-in connector catalog creates the Connector in `needs_auth` and posts the card. A bot that needs a connector the user has not connected gets the same card. Its subject is the Connector.
- **What it shows.** The connector, the account, the requested scopes and which bots get it, with one primary action, **Connect**, which opens the system web sign-in ([02 §7.8](../plan/02-experience.md#78-sign-in-sign_in)). A connector reached through Composio (CON-19, Phase 2, off by default) carries the notice that Composio holds the user's tokens on its servers.
- **Resolving.** Sign in or cancel, through `cards.respond`; it resolves with `connector.authorized`. The token goes to Keychain by reference and never reaches the model, the card's payload or a log.
- **Never generated.** A JSON card, a live card or an App cannot draw one or start the sign-in itself. An action or a call that needs a credential opens this card instead, in every mode (§5, §11.6; [D52](../plan/decisions.md#d52)).

### 8.2 Source chips

`web_search` and `x_search` results carry their source links, shown as chips under the reply that used them ([D112](../plan/decisions.md#d112); CON-15, CON-16, Phase 1). Source chips are neither a Card nor a block: the app draws them from the tool's result, never from model text.

- **Shape.** A search result carries `sources: [{ url, title? }]` [INFERENCE: the field names are set in Phase 1 with the tools' result schemas]. `url` must be `https:`. The chip shows the link's domain, which the app reads from `url`; `title` is display text only.
- **Opening.** A chip opens its link the way a `text` block's link opens: in the in-app browser, with the domain shown (§3; [03 §8.2](../plan/03-design-system.md#82-conversation)).
- **Untrusted.** Search results are untrusted content ([policy.md §6](policy.md#6-exposure-rule)). A chip is content, never app chrome, and it grants and approves nothing.
- **In a card.** A JSON card that cites sources uses blocks the catalog has: a `link` block per source, or `list` rows, each with an `open` action (§3, §5). The same `https:` and domain rules hold, and the card takes the links from its run's results (§6). The catalog has no citation block of its own [INFERENCE: whether a later minor version adds one is set in Phase 1].

### 8.3 The call card

A finished voice call leaves a card with its length and transcript ([D111](../plan/decisions.md#d111); V2-09: the Mac in Phase 2; VO-05: iPhone and iPad in Phase 3). Its kind is `voice_call`, a native display kind of its own and the 22nd card kind, from Phase 2 ([object-model §4.18](object-model.md#418-card-crd_), whose open question 19 was settled on 2026-11-13) [INFERENCE: the name and payload are set in Phase 2].

| | |
|---|---|
| Subject | The Voice call: `{ kind: voice_call, id }` ([object-model §4.38](object-model.md#438-voice-call-vcl_)) |
| Payload | `{ durationMs, engine, provider?, startedAt, endedAt, transcriptMessageId }` [INFERENCE: field names set in Phase 2]. The transcript is not copied into the payload: it is stored once, in the conversation's store, and the card points to it |
| Status | A display card, like `apple_data` and `generated`: never in the Inbox, never `needsYou`, no expiry and no resolution actions |
| Posted by | The conversation's runner, when the call ends; one card per call [INFERENCE: whether a failed call leaves one is set in Phase 2] |
| Shows | The bot, the call's length, the engine in words (on device, or cloud) and the transcript folded behind a disclosure ([03 §8.3](../plan/03-design-system.md#83-cards), `CallCard`) |

- **Why a kind of its own.** No existing kind presents a Voice call. `run_summary` presents a Task and has a seen state; `generated` is written by a bot and may carry buttons. The call card is neither: the app builds it from the call's record, with no model call.
- **Never generated.** A bot cannot post or imitate one; a generated card that looks like one is still a generated card in its own frame.
- **Nothing is decided on it.** A voice session only listens and speaks. Work the call handed over shows as ordinary messages and Cards in the conversation, and each Card is answered on that Card.
- **Not for other audio.** Reading a reply aloud, voice memos and the narrator leave no call card ([object-model §4.38](object-model.md#438-voice-call-vcl_), invariant 4).

### 8.4 Mail

The built-in `mail.*` tools add no card kind. Their classes and tiers are [policy.md §3.1](policy.md#31-operation-classes)'s ([D118](../plan/decisions.md#d118), [D121](../plan/decisions.md#d121)); this table says only which existing native card each raises in an attended run in Ask first and Auto.

| The bot's call | Class | Card |
|---|---|---|
| Send, reply or forward | `mail.send` | A Draft: the `draft` card with `draftKind: email`, which the user sends, except where the user let that bot send mail by itself ([D116](../plan/decisions.md#d116)). The same draft shows in its thread in the Mail pane (§12.10) |
| Archive or un-archive, mark read or unread, label or un-label, move, star | `mail.organize` | An `approval` card the first time. Its **Always allow** writes a standing rule for that bot and that mail account, for at most 90 days; while the rule holds there is no card |
| Delete, unsubscribe, change filters or forwarding | `mail.destroy` | An `approval` card with typed confirmation, each time. It has no **Always allow**, and no standing rule covers it |
| List, read a thread, search; prepare a draft | `mail.read`, `mail.stage` | The `approval` card of their tier under the bot's mode and standing rules, like any other call |

- **Send mail by itself.** Where the user turned it on for a bot, that bot's `mail.send` Draft is recorded and sent with no card. It never applies to a run started by incoming mail or other outside content, where the draft card always shows ([policy.md §11.3](policy.md#113-mail-drafts-and-send-mail-by-itself), [D116](../plan/decisions.md#d116), [D57](../plan/decisions.md#d57)).
- **Other runs and Bypass.** What unattended runs, runs started by outside content and Bypass change is [policy.md §4](policy.md#4-modes-regimes-and-the-decision-matrix)'s, not this spec's. In a run started by arriving mail, `mail.organize` runs only under a rule the user set for that trigger, and `mail.destroy` is denied.
- **From a card or a program.** A button on a JSON card, or a call from a live card or an App, that names a mail tool gets the same cards: a send is the native draft card, shown over the program, never a control the card or the program draws (§5, §11.6).
- **The user's own actions** in the Mail pane are the user's, not a bot's: they are not tool calls and raise no card.
- **Exposure.** Every message is untrusted content and private data, so the T3–T5 cards of a task that read mail carry the exposure note ([policy.md §6](policy.md#6-exposure-rule)), and an App version written by such a task waits for approval before it first runs (§12.2).

---

## 9. App Review

v1 is for the user's own devices: the iPhone and iPad app installs through TestFlight internal testing or from Xcode, so App Review does not shape JSON cards, live cards or Apps in v1 ([D67](../plan/decisions.md#d67)). iOS's own limits still hold, so the engine has no JIT and starts no processes (§11.1).

For a later public release ([O13](../plan/decisions.md#open-decisions)), the App Review Guidelines would apply on iPhone and iPad (text of 16 October 2026, quoted in the [generative UI research §5](../research/2026-10-22-python-and-native-generative-ui.md#5-app-review-rules-for-running-generated-code)):

- **2.5.2.** Apps "may not download, install, or execute code which introduces or changes features or functionality of the app". A JSON card is data drawn by blocks the app ships, so it adds no feature [INFERENCE]. Live cards and Apps run generated Swift, which is what this guideline targets (§12.8).
- **2.5.19.** Every card form would be described in the app and in the review notes, with nothing hidden or dormant (IOS-05 and DIST-08's App Store part, deferred to before a public release).
- **4.7.** It covers "HTML5 and JavaScript mini apps": page Apps ([D29](../plan/decisions.md#d29), [D114](../plan/decisions.md#d114)) would follow it, and 4.7.2's ban on extending native APIs to such software would bear on Swift Apps (§12.8).

---

## 10. Accessibility

- Every block has an accessible name: its text, its `label`, or its required `alt` (images) or `summary` (charts and the card itself).
- Tone never carries meaning alone: badges always have text, and trends have words as well as arrows ([D30](../plan/decisions.md#d30)).
- Tables expose rows and headers to VoiceOver; charts expose their `summary` and an audio graph where Swift Charts provides one.
- Dynamic Type on iPhone and iPad, and the message-size setting on the Mac, scale every block; a card reflows instead of clipping.
- Input blocks are reachable and operable by keyboard on the Mac.
- A `tabs` block is a tab group: each tab button is a selectable element that reads its title and position ("Trades, tab 2 of 3"), the selected tab is announced, ←/→ move between tabs with a keyboard, and the shown tab's blocks follow in reading order.
- Live cards and Swift Apps get the same from the kit (§11.5): kit components carry their own labels and traits, and Dynamic Type, Reduce Motion and Increase Contrast apply to every program. A page App's accessibility is its web page's [INFERENCE: what a page App must provide is set in Phase 1].

---

## 11. The Swift engine

Bots write SwiftUI-style Swift, and Memoshi runs it ([D68](../plan/decisions.md#d68), amended by [D71](../plan/decisions.md#d71); CH-21 to CH-24 in Phase 2 on the Mac, with CH-31 in Phase 2 since [D114](../plan/decisions.md#d114) and CH-26 to CH-30 and CH-32 in Drop 1, [D87](../plan/decisions.md#d87); layer 2 of [D115](../plan/decisions.md#d115)). SwiftSyntax parses the file, Memoshi's compiler checks it and turns it into bytecode, Memoshi's interpreter runs the bytecode with no JIT, and native SwiftUI components draw the views it builds. This is the approach of Ronith's prototype, whose compile step went "from swift source to bytecode, rest is interpreted" ([generative UI research §3](../research/2026-10-22-python-and-native-generative-ui.md#3-roniths-swift-interpreter)), built as our own code. Interswift (MIT) shows the same split into a guest compiler, a small VM and a SwiftUI renderer ([research §4](../research/2026-10-22-python-and-native-generative-ui.md#4-interswift-in-detail-observed-commit-03486798-archived-in-evidence)).

One parser, one interpreter and one component kit serve two forms, live cards and Swift Apps (§11.2). JSON cards (§2–§7) stay for quick, static cards. Page Apps (§12.7) do not use the engine: they share only its tool bridge and permission lists (§11.6, §11.11). Throughout §11, "App" means a Swift App unless a sentence says otherwise.

### 11.1 Pipeline and where it runs

| Step | What happens | Where |
|---|---|---|
| Write | The bot posts a live card's file with the card tool (`format: "swift"`), or edits an App's files one at a time with the `mini_app` tool (§12.1) [INFERENCE: the card tool's Swift arguments are set in Phase 2; the `mini_app` tool's operations in Phase 1, with page Apps] | The runner of the program's conversation ([D74](../plan/decisions.md#d74)) |
| Parse | SwiftSyntax builds a syntax tree off the main thread, with a nesting limit (`maximumNestingLevel`) and a time limit | Every device that compiles |
| Check | The compiler resolves every name against the program's own declarations in all its files, the language (§11.4), the kit (§11.5) and the tool bridge (§11.6), and checks types and limits. It lists every tool and web host the program can call: its permission list (§11.11). Anything else is an error with a line, a column and a fix (§11.7) | Same |
| Lower | The checked tree becomes bytecode, with a map from instructions to lines | Same |
| Sign | From Drop 1, the runner signs the bytecode it made (§11.12) | The runner of the program's conversation |
| Store | The Card or the App version keeps the **source**, with the engine and kit versions, a hash of the source and the permission list ([object-model §4.18](object-model.md#418-card-crd_), [§4.32](object-model.md#432-mini-app-app_)). From Drop 1, the signed bytecode is kept beside it as a cache and syncs with it ([D71](../plan/decisions.md#d71), [D87](../plan/decisions.md#d87)) | That runner, then replicas |
| Run | In v1.0 the interpreter runs the device's own compile of the source. From Drop 1 it may instead run synced bytecode that passes the device's checks (§11.12); the kit draws the views it builds ([D87](../plan/decisions.md#d87)) | The device that shows the card or App, in the bot's engine helper on the Mac; from Drop 1, the runner of its conversation for a background job (§12.4) |

- **Compile on the runner; sign from Drop 1.** The runner compiles when the bot posts, so the bot gets every error in its turn. Every v1.0 device compiles the source locally; the signed cache is not required. From Drop 1 the runner signs its bytecode (CH-28, [D87](../plan/decisions.md#d87)), and another device runs it only if one of the user's paired devices signed it, its engine version matches, and the device's bytecode verifier accepts it; otherwise the device compiles the source itself and caches its own bytecode by source hash and engine version ([D71](../plan/decisions.md#d71), §11.12).
- **Where it runs** ([D78](../plan/decisions.md#d78)). On the Mac every live card and App runs in a sandboxed engine helper, one per bot, with no secrets, no files and no network: its only way out is the tool bridge. The app draws the component tree the helper sends and returns the user's input ([protocol.md §5.10](protocol.md#510-live-cards-and-mini-apps)), and a helper crash stops only that bot's programs. On iPhone and iPad, where iOS allows apps no such helpers, programs run in the app, each in its own interpreter instance. From Drop 1 an App's background jobs run without a screen on the runner of its conversation: on the Mac in the bot's helper, never memoshid, and on iPhone and iPad inside the app, when it is that conversation's runner and iOS grants background time (§12.4). memoshid compiles and stores source, signs cached bytecode from Drop 1 ([D87](../plan/decisions.md#d87)), and decides programs' tool calls; it never runs a program.
- **On screen, plus jobs and widgets.** A live card runs while it is visible and an App while it is open; off screen a program pauses and keeps its state until the app quits. An App's code runs without its screen only in its refresh jobs (§12.4) and its widgets (§12.5), both from Drop 1 ([D87](../plan/decisions.md#d87)). Other work while the user is away is a routine ([D23](../plan/decisions.md#d23)).
- **No JIT and no native code.** The interpreter is a bytecode loop written in Swift. It generates no machine code and loads no native code, so it runs on iPhone and iPad, where iOS forbids JIT ([D67](../plan/decisions.md#d67)). [D114](../plan/decisions.md#d114)'s plugin developer mode does not change this: its compiled plugins are not engine programs and run in a separate helper on the Mac (§12.11).

### 11.2 Two forms

| | Live card | Swift App |
|---|---|---|
| Where it shows | Inline in a conversation, in the generated-card frame ([03 §8.5](../plan/03-design-system.md#85-generated-card-block-catalog)) | A pane beside the chat, a side-panel tab on Mac and iPad and full screen on iPhone, or inline ([D114](../plan/decisions.md#d114), §12.9); on the Mac also a sheet over its conversation, with **Open in Window**, **Full Screen** and a per-App opening preference ([D85](../plan/decisions.md#d85)). It uses the App chrome ([03 §8.7](../plan/03-design-system.md#87-mini-app-chrome)), opened from its chip, the bot's Library, ⌘K or the sidebar's **Apps** section, or through Spotlight, Siri or Shortcuts ([02 §10.11](../plan/02-experience.md#1011-mini-apps-and-live-cards), [D81](../plan/decisions.md#d81)) |
| Record | A `generated` Card with `sourceFormat: swift` | A `MiniApp` with numbered versions (§12) |
| Entry point | `struct … : Card` (§11.3) | `@main struct … : App` (§11.3) |
| State | `@State`, kept while the app runs | `@State`, kept while the app runs |
| Saved data | None | `@Saved` values, the same on every device, with no fixed size limit (§12.3) |
| Changing it | The bot posts a newer card with `replaces` | The bot publishes a new version, often after the user asks in the "Ask the bot to change it" box (§12.2) |
| Look | Kit components with semantic options only, like a JSON card (§1, rule 6) | Kit components plus look modifiers inside its own canvas (§11.5) |
| Source | One file, with no fixed size limit (§11.7) | One or more files, edited one at a time, with no fixed size limit (§11.3) |
| Permission list | Approved when the card first appears, and again when a newer card adds to it (§11.11) | Approved when the App first appears, and again when a new version adds to it (§11.11) |
| Without a screen | None: no background jobs or widgets | From Drop 1, refresh jobs on a schedule or when data it uses changes, run by the runner of its conversation (§12.4), and home-screen widgets drawn from saved data (§12.5); neither is required for v1.0 ([D87](../plan/decisions.md#d87)) |
| Exported functions | None | Typed functions that bots inside its scope call through a Code Mode namespace (§12.9, [D114](../plan/decisions.md#d114)) |
| Phase | Mac in Phase 2 (CH-21); iPhone and iPad in Phase 3 | Mac in Phase 2 (CH-22) and iPhone and iPad in Phase 3 (CH-23); background jobs (CH-26) and widgets (CH-27) on all three in Drop 1 ([D87](../plan/decisions.md#d87)); a page App may come first, in Phase 1, and be replaced by it (§12.7) |

### 11.3 File shape

```swift
import SwiftUI

struct BacktestCard: Card {             // a live card
    let title = "Momentum backtest"
    let summary = "Return 3.0%, worst drawdown 5.2%"
    // let replaces = "crd_…"            // optional, as in §2

    var body: some View { … }           // exactly one root view
}
```

```swift
import SwiftUI

@main
struct Chores: App {                    // an App
    let name = "Chores"
    let summary = "This week's chores, with reminders"

    var body: some Scene {
        WindowGroup { ChoreList() }     // exactly one WindowGroup with one root view
    }
    // var jobs: some Jobs { … }        // optional refresh jobs (§12.4)
    // var widgets: some Widgets { … }  // optional home-screen widgets (§12.5)
    // var functions: some Functions { … } // optional exported functions (§12.9)
}
```

- **One program.** A live card is one file with exactly one `struct` that conforms to `Card`, with `title` and `summary` as string literals and an optional `replaces`. An App has exactly one `@main struct` that conforms to `App`, with `name` and `summary` as string literals, a `body` of one `WindowGroup`, and optionally its refresh jobs (§12.4), widgets (§12.5) and exported functions (§12.9). `Card` and `App` are names the compiler knows; no Swift toolchain ever builds the file.
- **Several files** (Apps only, [D71](../plan/decisions.md#d71)). An App may span several files, such as `Chores.swift`, `ChoreList.swift` and `Chore.swift` [INFERENCE: how files are named]. They compile together as one program, so a declaration in one file is visible in all, and exactly one file holds the `@main` struct. Bots edit one file at a time (§12.1). A live card stays one file.
- **The rest of the program** holds its own views (`struct … : View`), data types, functions and constants (§11.4).
- **Imports:** `SwiftUI`, `Foundation`, `Charts` and `MapKit` are accepted and only select kit names. Any other import is an error.
- **Previews** ([D81](../plan/decisions.md#d81)). When a program is posted or published, the runner renders its `#Preview` blocks headlessly as a smoke test, and an error a preview hits reaches the bot in the tool's result, like a compile error (§11.7). A preview's tool calls do not run [INFERENCE]. Before it reports a card or an App done, the bot also looks at a rendered snapshot of what it made (CH-38, [D110](../plan/decisions.md#d110); from Phase 1 for JSON cards and page Apps).

### 11.4 The language

Nearly all of Swift ([D72](../plan/decisions.md#d72), widening [D68](../plan/decisions.md#d68)'s subset); version 1 is below [INFERENCE: exact coverage is set in Phase 2]. v1.0 ships the core, D68's subset plus classes and protocols with extensions; the program's own generics, `async let`, task groups and actors follow in Drop 1 (CH-29, [D87](../plan/decisions.md#d87)). The language widens, not the reach: data still comes only through tools, with no Apple or system APIs beyond the kit (§11.5, §11.6).

| Area | Supported |
|---|---|
| Values and types | `Int`, `Double`, `Bool`, `String`, `Date`, `UUID`; optionals with `if let`, `guard let`, `?.` and `??`; arrays, dictionaries and sets; tuples; ranges; key paths to properties (`\.title`) |
| Declarations | `let` and `var`; `func` with argument labels, default values and results; `struct`s, `enum`s and `class`es, `@Observable` classes and `ObservableObject` included; `protocol`s with extensions; generic types and functions of the program's own; `actor`s; `extension`s of the program's own types; conformance to the kit's protocols (`View`, `Identifiable`, `Hashable`, `Equatable`, `Comparable`, `Codable`) |
| Control flow | `if`, `else`, `guard`, `switch` with patterns and `where`, `for in`, `while`, `repeat`, `break`, `continue`, `return`, `?:`, and `do`, `try` and `catch` |
| Closures | Closures as arguments and as values: `map`, `filter`, `sorted(by:)`, `reduce`, `first(where:)`, button actions. Captured values follow Swift: value types are copied, class instances are shared |
| Standard library | A listed subset: collection methods (`count`, `isEmpty`, `append`, `insert`, `remove(at:)`, `remove(atOffsets:)`, `move(fromOffsets:toOffset:)`, `firstIndex(where:)`, `map`, `compactMap`, `filter`, `reduce`, `sorted`, `first`, `last`, `min`, `max`, `contains`, `enumerated`, `zip`, `prefix`, `suffix`, `joined`, `Dictionary(grouping:by:)`); string methods (`lowercased`, `uppercased`, `hasPrefix`, `hasSuffix`, `contains`, `split`, `trimmingCharacters(in:)`); number conversions (`Int("12")`); math (`abs`, `min`, `max`, `rounded`, `pow`); dates (`Date.now`, `addingTimeInterval`, `Calendar.current` arithmetic and components); `UUID()`; `Int.random(in:)`; `print`, to the program's log (§11.8) |
| Formatting | String interpolation, and `.formatted(…)` with number, percent, currency, date, time and relative styles, in the user's locale |
| State | `@State`; `@Binding` and `$` bindings, to pass state to child views and inputs; `@Observable` objects held in `@State`, and `ObservableObject` with `@StateObject` and `@ObservedObject` [INFERENCE: which wrappers]; `ForEach` over arrays, ranges and bindings (`ForEach($items) { $item in … }`); `@Saved` in Apps (§12.3); `@Environment` values: `dismiss`, `colorScheme`, `dynamicTypeSize` and `horizontalSizeClass`, and, read-only, `locale`, `timeZone`, `calendar`, `scenePhase` and the accessibility values, such as `accessibilityReduceMotion` ([D81](../plan/decisions.md#d81)) |
| Effects | `.task { }` when a view appears; `.onChange(of:)`; timers, as `Timer.publish(every:on:in:).autoconnect()` with `.onReceive`, or `TimelineView(.periodic(from:by:))`; `withAnimation`; `async` functions, `Task { }`, `async let`, task groups and actors ([D72](../plan/decisions.md#d72)); an await that reaches outside the program is a tool call (§11.6) |

**Rejected**, each with a fix (§11.7):
- **Reaching outside the engine:** other imports, `URLSession`, `FileManager`, `UserDefaults` and `@AppStorage`, `Process`, `NotificationCenter`, `DispatchQueue`, `UIApplication`, `NSWorkspace`, and every other Apple or system API beyond the kit. Data comes only through tools (§11.6).
- **Native and unsafe code** ([D72](../plan/decisions.md#d72)): unsafe pointers, `@_silgen_name`, dynamic loading such as `dlopen`, Objective-C interop such as `@objc`, `#if`, and macros other than `#Preview` and `@Observable`. [D114](../plan/decisions.md#d114) adds one exception to D72's exclusion of dynamic loading, outside the engine: plugin developer mode's compiled plugins, on the Mac only (§12.11). Nothing changes for live cards and Swift Apps.
- **Unknown names:** any view, modifier, type, function or property outside the language, the kit and the bridge.

**Checked before and during a run.** Full static checking of generics and protocols is hard, so the compiler checks names and shapes before a program runs, and the interpreter checks the rest while it runs. Every error, at compile time or at run time, still carries a line and a fix (§11.7, §11.8; [D72](../plan/decisions.md#d72) risks).

### 11.5 The component kit

The kit is a large set of native SwiftUI components that programs build their views from ([D68](../plan/decisions.md#d68)). Each component is Memoshi's own code, compiled into the app: a program can only arrange and configure components, and SwiftUI draws them [INFERENCE: module names in [04 §4.17](../plan/04-architecture.md#417-the-swift-engine-live-cards-and-mini-apps)].

| Group | Components |
|---|---|
| D53's blocks | Every block of §3, `tabs` included. A block uses its SwiftUI spelling where SwiftUI has a matching view (`VStack`, `HStack`, `Grid`, `Section`, `Divider`, `Text`, `Label`, `List`, `Table`, `ProgressView`, `TextField`, `Toggle`, `DatePicker`, `Slider`, `Picker`, `Button`, `Link`, `Chart`, `Map`), and otherwise its catalog spelling: the block's name in UpperCamelCase with labels from its §3 fields, such as `Metric("Return", value: 0.03, format: .percent, trend: .up)`, `KeyValue(items:)`, `Timeline(items:)`, `Badge("Late", tone: .warning)` and `Tabs { Tab("Summary") { … } }` |
| Lists and forms | `List` with sections, `onDelete`, `onMove` and swipe actions; `Form`; `LabeledContent`; `DisclosureGroup`; `Stepper`. There is no `SecureField`: programs never handle secrets (§11.6) |
| Navigation | `NavigationStack`, `NavigationLink`, `.navigationTitle`, toolbars, `.sheet`, `.alert`, `.confirmationDialog`, `.searchable` |
| Tabs | `TabView` with tab items, for an App's top level; the `tabs` block (`Tabs`) for a switch inside a view |
| Gestures | `Button`, `.onTapGesture`, `.swipeActions`, `.contextMenu`, `.refreshable`: the gestures whose handlers make attended calls (§11.6) |
| Charts | Swift Charts' `Chart` with `BarMark`, `LineMark`, `AreaMark`, `PointMark`, `RuleMark` and `SectorMark`, axes and legends; at most 4 series. Long series use Swift Charts' vectorized plots, such as `LinePlot` and `AreaPlot`, up to about 100,000 points; beyond that the kit downsamples them with Largest-Triangle-Three-Buckets (LTTB) ([D81](../plan/decisions.md#d81)). A JSON card's `chart` block stays at 500 points (§3) |
| Maps | `Map` with `Marker` and `Annotation`, from coordinates the program got through tools; no user location, which is a tool too |
| Media | `Image(artifact:)` and `Image(attachment:)` from the bot's run, `Image(systemName:)` from the allowed SF Symbols, audio and video players for artifacts, and QuickLook previews of PDF and CSV artifacts ([D81](../plan/decisions.md#d81)). No `AsyncImage` and no remote URLs (§1, rule 3) |
| Apple data | The native views of the `apple_data` cards (Reminders, Calendar, Music, Weather, Maps, Contacts and Photos) as components, such as `ReminderRow(reminder)` and `WeatherCard(forecast)` [INFERENCE: names], drawn from values the program got through tools ([D53](../plan/decisions.md#d53)). Their controls are tool calls under policy |
| Layout | `ZStack`, `ScrollView`, `Spacer`, `LazyVGrid` and `ViewThatFits`, with alignment and spacing. A live card sits inline in a conversation, so it has no vertical `ScrollView`: the compiler rejects one (`swift.not_allowed`) ([D81](../plan/decisions.md#d81)) |
| Look (Apps only) | `padding`, `frame`, `foregroundStyle` and `background` with semantic or literal colors, `font` with text styles, `clipShape`, `Circle`, `Capsule`, `RoundedRectangle`, gradients, `opacity`, animations and transitions, and, from Drop 1 ([D72](../plan/decisions.md#d72); CH-30, [D87](../plan/decisions.md#d87)), shadows, materials, overlays, offsets, SF Symbol rendering modes, `Canvas` drawing and images from the bot's files [INFERENCE: spellings]. The compiler checks text contrast against its background (`swift.low_contrast`), and Dynamic Type and Reduce Motion apply automatically. A live card stays semantic-only: it uses only the semantic options of D53's blocks, such as `.foregroundStyle(.secondary)` for `emphasis`, `.font(.headline)` for `level` and `.buttonStyle(.borderedProminent)` for `style`, so it looks like Memoshi (§1, rule 6); any other look modifier in a live card is a compile error |

- **Not in the kit:** decision cards (approval, draft, sign-in, purchase, Resume, grant request), the composer, the title bar, permission sheets, web views, and anything that draws outside the program's frame. The live card's frame and the App chrome are drawn by the app, so a program can never pass for Memoshi's own controls (§8).
- **Accessibility.** Components carry their labels and traits. An `Image` needs `alt` or an accessibility label and a `Chart` a summary, as in §10, or the file does not compile. Dynamic Type, Reduce Motion and Increase Contrast apply to every component, and a program cannot turn them off.
- **Versions.** The kit has its own `major.minor` version; a minor version adds components (§11.10).

### 11.6 The tool bridge

A program reaches data and the world only through Memoshi's tools, within the permission list the user approved for its version (§11.11), and every call passes policy like a call the bot makes ([D68](../plan/decisions.md#d68), [D71](../plan/decisions.md#d71); [policy.md §10.7](policy.md#107-live-cards-and-mini-apps)).

```swift
let due = try await tools.reminders.list(list: "Home")
let tomorrow = Date.now.addingTimeInterval(86_400)
try await tools.reminders.add(title: "Water the plants", list: "Home", due: tomorrow)
let rates = try await tools.webFetch(url: "https://api.example.com/rates.json")
```

- **Generated from the catalog.** Each typed tool ([D50](../plan/decisions.md#d50), [object-model §4.30](object-model.md#430-tool-definition)) appears in the `tools` namespace as an `async throws` function. It is named from its shell command where it has one (`tools.reminders.add(…)` for `reminders add`), and otherwise from its name in lowerCamelCase, with labels and types from its parameters. Connector tools are called by name, `tools.connector("github", "list_issues", ["repo": "acme/web"])`, and classified by verb as always ([policy.md §3.3](policy.md#33-mcp-tools-verb-classification)) [INFERENCE: spellings set in Phase 2]. The compiler checks every call against the tool's schema and adds the tool, and for a web call its host, to the version's permission list (§11.11).
- **Which tools.** Every tool the bot can call, its granted connectors included, within the version's approved permission list (§11.11). That covers risky tools too, such as shell commands, or the `mini_app` tool, with which a program changes its own code; the permission list names them plainly. There is no fixed list of tools programs may not call, and a program never holds more access than its bot ([D71](../plan/decisions.md#d71)).
- **Each call is the bot's call.** The engine that runs the program, in the bot's engine helper on the Mac or in the app on iPhone and iPad, sends the call to the runner of the program's conversation: the conversation a live card was posted in, or the App's `conversationId` (`cards.callTool` or `miniApps.callTool`, [protocol.md §5.10](protocol.md#510-live-cards-and-mini-apps)). The runner refuses it if it is outside the version's approved list (§11.11). Otherwise it decides it by the bot's mode, grants and policy as for the bot, runs it where the tool lives, and that device re-checks its grants ([D49](../plan/decisions.md#d49)). The call carries its source: the card or the App, the version, and what started it.
- **Who started it decides the regime** ([D71](../plan/decisions.md#d71)):
  - a tap, or another gesture of the user's: inside the handler of a button, a toggle, a picker, a submit, a swipe or context-menu action, or pull to refresh, and in the tasks that handler starts, the call is the user's: origin `user`, attended. A tap is not an approval: a call that asks still shows its native card (below);
  - anything else, a `.task` when a view appears (an on-open call), `.onChange`, a timer or a background job (§12.4), is the program's own call: origin `app`, which takes the unattended column ([policy.md §4.3](policy.md#43-unattended-originrootkind--routine-wake-watch)). A call that needs a standing rule shows **Allow for this App** in the App's chrome, or **Allow for this card** in a live card's frame.
  - a call made inside a function that a bot called (§12.9) is neither: it is a nested call of that bot's task, with trigger `function`, decided in the calling task's origin, regime and mode ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps), item 13).
- **What the bot sees** ([D81](../plan/decisions.md#d81)). Every call shows in the program's activity and in the audit log. From Phase 2 (CH-31, moved from Drop 1 by [D114](../plan/decisions.md#d114)), the bot's next turn also carries a compact digest of the calls the user started with a tap or another gesture in its live cards and Apps, and of any call a program made on its own that failed. A program's other own calls, such as on-open, timer and job calls, stay out of the bot's turns ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps)).
- **Results and errors** ([D81](../plan/decisions.md#d81)). A result arrives as a typed value from the tool's result schema. A denial, an expiry, a failure or a timeout throws a `ToolError` that the program can catch. It carries a stable `code` the program can switch on and a plain `reason` it can show, such as "Needs your approval", "Not allowed: needs a grant", "Not in this App's approved list" or "Waiting for your Mac". The codes follow the bridge call's error: its `kind`, such as `policy_denied`, `timeout` or `device_unreachable`, and for a denial the policy reason, such as `bridge.not_approved` ([protocol.md §10](protocol.md#10-errors)) [INFERENCE: the codes and their Swift spelling are set in Phase 2].
- **Cards stay native.** A call that asks shows the native approval or draft card over the program, in the Inbox and as a notification, never inside the program's views, and the program's `await` resumes when the card is answered; a background job's cards show in the Inbox and as notifications (§12.4). A money or credential call opens the native `purchase` or `sign_in` card, in every mode ([D52](../plan/decisions.md#d52)). A program reads a secret only as the bot can: through `secret.reveal`, from a tap with typed confirmation, never from timers, on-open calls or jobs ([D71](../plan/decisions.md#d71), corrected 2026-10-22). The revealed value carries a `secret` label: the program may show it, but a call that would pass it to any tool, or a write that would save it, is denied ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps)).
- **Talking to the bot** ([D81](../plan/decisions.md#d81)). `bot.ask("…")`, from a gesture handler only, opens a confirm sheet over the program, drawn by the app, that shows the exact text with **Send** and **Edit**. **Send** submits the text as the user's message in the program's conversation; **Edit** lets the user change it first. With no reachable runner or available allowed model, Send uses the persistent local unsent path with its original `requestId`, **Waiting for connection** and cancellation before delivery, then normal idempotent delivery to the current confirmed runner on reconnect ([D88](../plan/decisions.md#d88), [protocol.md §5.3](protocol.md#53-conversations-chats-sessions-groups)); it is not an answer or a side-thread summary. When the text holds a value labelled `untrusted`, the sheet shows the exposure note ([policy.md §6](policy.md#6-exposure-rule)). A program never sends a message as the user by itself.
- **Exposure, value by value** ([D72](../plan/decisions.md#d72)). In the style of CaMeL, every value a program holds records where it came from: the user (`user`), private data such as Apple data, files and connector data (`privateData`), or untrusted content such as web pages and others' connector content (`untrusted`). A value computed from others, or inside a branch that depends on them, carries their labels [INFERENCE: how labels follow control flow is set in Phase 2]. Policy's exposure effects apply to a call through the labelled values that reach its arguments, instead of through flags on the whole program ([policy.md §6](policy.md#6-exposure-rule)).
- **Limits.** At most 4 calls in flight and 60 a minute per program, background jobs included, and budgets apply as for any call (§11.8).

### 11.7 Compile step and errors

1. **Post.** The bot posts a live card's file through the card tool, or edits an App's files one at a time through the `mini_app` tool and then publishes them (§12.1). Source has no fixed size limit ([D71](../plan/decisions.md#d71)); the parser's nesting and time limits (step 2) and the interpreter's work and memory limits (§11.8) bound a program.
2. **Parse** with SwiftSyntax, off the main thread, with a low nesting limit and a time limit, whose values are set in Phase 2 ([08 TM-32](../plan/08-security-and-privacy.md#3-threat-model)).
3. **Check.** Resolve names across all of the program's files, check types and tool calls, check the static limits (§11.8), and list every tool and web host the program can call: its permission list (§11.11). The compiler is strict: an unsupported construct fails here, with a fix, instead of crashing later ([D68](../plan/decisions.md#d68)).
4. **Lower** to bytecode, with the map from instructions to lines that run-time errors use.
5. **Sign, store and show.** A program that compiles is stored as source with its permission list, and the runner renders its `#Preview` blocks headlessly as a smoke test (§11.3) and, from Drop 1, signs its bytecode and keeps it beside the source as a cache (§11.12). It then appears: the live card in the conversation, or the App's chip with its new version, and the user approves its permission list when it first appears or when it adds to the list (§11.11). A program that does not compile posts nothing, and the bot gets its errors in the tool's result, so it can fix the file in one pass ([D81](../plan/decisions.md#d81)): at most 20 per result, leaving out errors that only follow from an earlier one, each with a fix-it where the compiler can suggest one, and with the number of errors left out.

Each error has a line and column, a code, and a message that names the construct and suggests a fix:

```text
12:5   swift.unsupported       `@AppStorage` is not supported. Use `@Saved var chores: [Chore] = []`, which keeps any value for this App.
31:21  swift.not_allowed       `URLSession` cannot be used: programs reach the network only through tools. Use `try await tools.webFetch(url:)`.
40:9   swift.unknown_modifier  `.onLongPressGesture` is not in the kit yet. Use `.contextMenu` or a `Button`.
47:30  swift.type_mismatch     `tools.reminders.add(due:)` takes a `Date`, not a `String`. Use `Date.now.addingTimeInterval(86_400)`.
```

Codes [INFERENCE]: `swift.parse_error` (not valid Swift), `swift.unknown_name`, `swift.unknown_view`, `swift.unknown_modifier`, `swift.unsupported` (a construct outside the language, §11.4), `swift.not_allowed` (an API that would reach outside the engine, a symbol off the list, a look or layout a live card may not use), `swift.type_mismatch`, `swift.bad_argument` (an unknown label or a wrong literal), `swift.unknown_tool` (a tool the bot lacks), `swift.dynamic_host` (a web call whose host is not written as a literal, so the permission list cannot name it, §11.11), `swift.low_contrast` (text that fails the contrast check, §11.5), `swift.migration_needed` (a renamed or removed saved field with no migration, §12.3), `swift.secret` (a secret in a live card's source, below) and `swift.limit` (over a static limit). Run-time errors have the same shape, with `run.` codes (§11.8).

**Secrets in a live card's source** ([D82](../plan/decisions.md#d82)). The secret scanner checks a live card's source in the check step. A finding fails the publish with `swift.secret` at the secret's line, and nothing is stored: the source is never scrubbed, because redaction would silently change the code and the bytecode compiled from it ([object-model.md §4.18](object-model.md#418-card-crd_)).

### 11.8 The interpreter and its limits

The interpreter runs one instance per visible live card or open App, and one per background job run (§12.4) or widget (§12.5), each on its own executor off the main thread. On the Mac those instances live in the bot's engine helper, one helper per bot, and the app applies the component trees they send on the main thread; on iPhone and iPad each runs in the app ([D78](../plan/decisions.md#d78)). Every operation is checked, so a program can fail but cannot crash the app: an index out of range, a force-unwrapped `nil`, a division by zero or a limit stops the handler that hit it, shows the error and its line in the program's frame (for a job, in its run's outcome and the log), and leaves everything else running. If the helper itself crashes, only that bot's programs stop, and the app offers to reopen them [INFERENCE].

| Limit | Value, tuned by the engine probe and in Phase 2 | When exceeded |
|---|---|---|
| Work per handler: an action, a timer tick, a `.task`, a background job's run, or one evaluation of a view's `body` | 1,000,000 instructions; 50 ms for a `body`; a wall-clock watchdog backs the count up ([D81](../plan/decisions.md#d81)) | The handler stops with `run.too_much_work` |
| Call depth | 256 frames | `run.stack_overflow` |
| Memory per program | 64 MB on a Mac; 32 MB on iPhone and iPad | `run.out_of_memory`, and the program stops |
| Views | 5,000 per update; lists are lazy | `run.too_many_views` |
| Timers | 4 per program, each at least 1 s apart | A compile error, or `run.timer_limit` |
| Tool calls | 4 in flight; 60 a minute | The extra call waits, then throws `run.tool_rate` |
| Background jobs | A schedule at most every 15 minutes; one run of a job at a time | A shorter schedule is a compile error (`swift.limit`); a trigger during a run is skipped |

There is no fixed limit on source, on saved data or on a single value; the memory limit bounds what a program holds at once ([D71](../plan/decisions.md#d71)).

- **Watchdog** ([D81](../plan/decisions.md#d81)). Work is counted in instructions, the same on every device, and a wall-clock watchdog backs the count up, as Wasmtime pairs fuel with epoch interruption: a handler still running when its time is up stops with `run.too_much_work` too, whatever its instruction count [INFERENCE: the engine probe sets the time].
- **Failures** ([D81](../plan/decisions.md#d81)). A handler that fails is switched off first, and the rest of the program keeps running [INFERENCE: until the program is reloaded]. The bot gets one automatic attempt to fix each version: the runner sends it the error and its line as a change request (§12.2), and the attempt counts toward the bot's budgets. A program that fails three times in a minute stops, with "This App stopped" and its error. Further fixes are the user's to ask for, with the **Ask the bot to fix it** button, which sends the error and its line to the bot as a change request.
- **Off screen.** When a live card scrolls away or an App closes, its timers stop. Tool calls already sent finish; their results update the program if it is still loaded and are dropped otherwise.
- **Log** ([D81](../plan/decisions.md#d81)). `print` output, run-time errors and each background job run's outcome go to the program's log. The bot reads an App's log through the `mini_app` tool and a live card's through the card tool [INFERENCE: the card tool's operation is set in Phase 2], and Developer, the experience level, shows the log in the program's info sheet (this is not §12.11's plugin developer mode).

### 11.9 Examples

**A live card.** A Python run on the Mac ([D60](../plan/decisions.md#d60)) saved an equity curve as an artifact. The bot shows it with its numbers, in two tabs:

```swift
import SwiftUI

struct Month: Identifiable {
    let id: String              // "2026-08"
    let ret: Double
    let drawdown: Double
}

let months = [
    Month(id: "2026-08", ret: 0.021, drawdown: -0.034),
    Month(id: "2026-09", ret: -0.008, drawdown: -0.052),
    Month(id: "2026-10", ret: 0.017, drawdown: -0.029),
]

struct BacktestCard: Card {
    let title = "Momentum backtest, August to October 2026"
    let summary = "Return 3.0%, worst drawdown 5.2%"

    var body: some View {
        VStack(spacing: .loose) {
            Tabs {
                Tab("Summary") {
                    HStack {
                        Metric("Return", value: 0.030, format: .percent, trend: .up)
                        Metric("Worst drawdown", value: -0.052, format: .percent)
                    }
                    Image(artifact: "art_01JD2W7K3M8Q4R6T5V0X1Y2Z3A", alt: "Equity curve, August to October")
                }
                Tab("Months") {
                    Table(months) {
                        TableColumn("Month", value: \.id)
                        TableColumn("Return", value: \.ret, format: .percent)
                        TableColumn("Drawdown", value: \.drawdown, format: .percent)
                    }
                }
            }
            Button("Run it on 2025 too") {
                bot.ask("Run the same backtest on 2025.")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
```

**An App.** The user asked for a weekly chore list that can set reminders:

```swift
import SwiftUI

struct Chore: Identifiable, Codable {
    var id = UUID()
    var title: String
    var done = false
}

@main
struct Chores: App {
    let name = "Chores"
    let summary = "This week's chores, with reminders"

    var body: some Scene {
        WindowGroup { ChoreList() }
    }
}

struct ChoreList: View {
    @Saved var chores: [Chore] = []
    @State private var newTitle = ""
    @State private var status = ""

    var left: Int { chores.filter { !$0.done }.count }

    var body: some View {
        NavigationStack {
            List {
                Section("\(left) left this week") {
                    ForEach(chores) { chore in
                        HStack {
                            Button {
                                toggle(chore)
                            } label: {
                                Label(chore.title, systemImage: chore.done ? "checkmark.circle.fill" : "circle")
                            }
                            Spacer()
                            Button("Remind me") {
                                Task { await remind(chore) }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onDelete { chores.remove(atOffsets: $0) }
                }
                Section {
                    TextField("New chore", text: $newTitle)
                    Button("Add") {
                        chores.append(Chore(title: newTitle))
                        newTitle = ""
                    }
                    .disabled(newTitle.isEmpty)
                }
                if !status.isEmpty {
                    Text(status).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Chores")
        }
    }

    func toggle(_ chore: Chore) {
        if let i = chores.firstIndex(where: { $0.id == chore.id }) {
            chores[i].done.toggle()
        }
    }

    func remind(_ chore: Chore) async {
        do {
            try await tools.reminders.add(title: chore.title, list: "Home",
                                          due: Date.now.addingTimeInterval(86_400))
            status = "Reminder set for \(chore.title)."
        } catch {
            status = error.localizedDescription
        }
    }
}
```

What happens:
1. The bot writes the App's one file with the `mini_app` tool and publishes it. The runner compiles it and stores version 1's source and permission list, which names one tool: adding reminders. From Drop 1 it also signs the bytecode as a cache ([D87](../plan/decisions.md#d87)). The conversation shows the App's chip: "Chores · Version 1 · Open" ([02 §10.11](../plan/02-experience.md#1011-mini-apps-and-live-cards)).
2. The user opens it on an iPhone. The full-screen chrome first shows the permission list, "Chores can add reminders", and the user approves it (§11.11). In v1.0 the iPhone compiles the source locally. From Drop 1 it may run the runner's signed bytecode once its checks pass, otherwise compiling the source (§11.12); `chores` comes from the saved data, empty at first.
3. Adding, ticking and deleting chores change `chores`, which the engine saves for every device (§12.3). No tool is called, so policy decides nothing.
4. **Remind me** is a gesture, so `tools.reminders.add` is the user's call, and the approved list names it: `apple.write`, T4. In Ask first and Auto it goes out as a native draft card over the App; Send runs it, and `await` returns; Discard makes it throw, and the status line shows why. In Bypass it runs at once, and its Draft is recorded and audited ([policy.md §15](policy.md#15-test-vectors), V97 and V98).
5. Had the bot also loaded today's reminders in `.task { … }` when the list appears, the permission list would also name reading reminders, and that read would be the program's own call (origin `app`): T3 under the unattended column, so it is denied until the user taps **Allow for this App** ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps), V99 and V100).

### 11.10 Versions, devices and promotion

- **Engine and kit versions.** The language and interpreter (the engine) and the kit each have a `major.minor` version, and every stored program records the versions it compiled against. A minor version adds names; a major version may change meaning. A device whose engine or kit is older than a program's shows a plain fallback ("Update Memoshi to open this") in its place, as §7 does for unknown blocks.
- **The bot's prompt** carries the language, the kit and the bridge of the engine on the runner of the program's conversation, so bots target the runner's newest version, not the oldest among the user's devices ([D81](../plan/decisions.md#d81)). A device whose engine or kit is older shows the fallback above, with **Update Memoshi**.
- **One language and kit everywhere** ([D81](../plan/decisions.md#d81)). The same language and kit compile and run on Mac, iPhone and iPad, and from Drop 1 the kit adapts to the device (CH-32, [D87](../plan/decisions.md#d87)): richer on the Mac, lighter on iPhone. A program may mark an extreme part Mac-only, with a lighter fallback that iPhone shows instead [INFERENCE: how a part is marked is set in Drop 1]. A tool a device lacks runs on another device through the bridge (§11.6).
- **Phases.** JSON cards and page Apps come first, on the Mac in Phase 1 (CH-19, CH-37; [D114](../plan/decisions.md#d114), [D115](../plan/decisions.md#d115)). The engine and kit (CH-24), live cards (CH-21) and Swift Apps (CH-22) ship on the Mac in Phase 2, after the engine probe that opens it in plan week W52 ([04 §4.17](../plan/04-architecture.md#swift-engine-probe)), with the bot's digest of program actions (CH-31, moved from Drop 1 by [D114](../plan/decisions.md#d114)); Apps and live cards reach iPhone and iPad in Phase 3 (CH-23). Drop 1 adds background jobs (CH-26) and widgets (CH-27) on Mac, iPhone and iPad, the signed bytecode cache (CH-28), the rest of Swift (CH-29), rich styling (CH-30) and the adaptive kit (CH-32) ([D87](../plan/decisions.md#d87)).
- **Promotion** ([D81](../plan/decisions.md#d81)). A program that proves useful can ship in a release as a bundled engine program: its source, reviewed like other app code, run by the same engine. It is rewritten as native app code only if it needs to be (Open question 4).

### 11.11 Permission lists

Every version of a program has a permission list: each tool and web host it can call ([D71](../plan/decisions.md#d71)). Within its approved list a program may call every tool its bot can call (§11.6), so the list is the main guard on what a program can do ([risks.md R52](../plan/risks.md#r52)).

- **Made by the compiler.** The check step lists each tool the program calls, each connector tool by connector and name, and each web host its calls reach (§11.7). A web call names its host as a literal, such as `"https://api.example.com/…"`, so the list is complete; a host built at run time is a compile error (`swift.dynamic_host`) [INFERENCE]. The list is stored with the version ([object-model §4.32](object-model.md#432-mini-app-app_)) and shown in the program's info sheet. A page App has no compiler: its version states its list, and the runner's check is the same (§12.7).
- **Approved by the user.** The user approves the list when a live card or App first appears, and again when a new version adds to it. A version that adds nothing needs no new approval, and a live card that replaces another counts as its new version [INFERENCE]. The list shows in a native sheet that the app draws in the card's frame or the App's chrome ([03 §8.7](../plan/03-design-system.md#87-mini-app-chrome)), never in the program's views, on whichever paired device shows the program ([protocol.md §5.10](protocol.md#510-live-cards-and-mini-apps)).
- **Plain words.** Each entry says what the program can do, such as "Add reminders" or "Read pages on api.example.com". Risky abilities, such as running shell commands or changing its own code, are named plainly at the top ([D71](../plan/decisions.md#d71)) [INFERENCE: which abilities count as risky is set in Phase 2].
- **Not an approval of calls.** The list says what a version may call at all; it is not a grant, a standing rule or an approval. Each call is still decided by policy (§11.6): a tap is the user's call, attended, but it is not an approval, and timers, on-open calls and background jobs are the program's own, unattended.
- **Enforced by the runner.** The runner refuses any call outside the version's approved list (`bridge.not_approved`, [policy.md §10.7](policy.md#107-live-cards-and-mini-apps)), whatever the compiler or the interpreter produced. Until the user approves a version's additions, it may call only what the earlier approved list held, and a first version nothing; its background jobs do not start before its list is approved [INFERENCE].
- **Functions.** A tool call made inside an exported function is held to the same list, whichever bot called the function and whatever that bot could call directly (§12.9).

### 11.12 Signed bytecode cache

The runner compiles and signs a program's bytecode, which syncs with the source as a cache ([D71](../plan/decisions.md#d71); CH-28, Drop 1, [D87](../plan/decisions.md#d87)). Until Drop 1, every device compiles the source itself. The source stays the stored, runnable form (§11.1): the cache saves a device the compile, and lets widgets draw without a compiler (§12.5).

- **Signed on the runner.** When a program compiles (§11.7), the runner signs its bytecode with its device signing key ([object-model §4.26](object-model.md#426-device-dev_)). The signature covers the bytecode, the source hash, the engine and kit versions and the permission list [INFERENCE: the key and what it covers].
- **Synced as a cache.** The signed bytecode replicates with the Card or the App version to every paired device, keyed by source hash and engine version ([object-model §4.32](object-model.md#432-mini-app-app_)). Any device may drop it, and losing it loses nothing.
- **Three checks.** A device runs synced bytecode only if one of the user's paired devices signed it, its engine version matches the device's own, and the device's bytecode verifier accepts it. If any check fails, the device compiles the source itself and keeps that bytecode in its own cache, which never syncs [INFERENCE]. A revoked device is no longer paired, so its signatures fail ([protocol.md §12.5](protocol.md#125-revocation)).
- **The verifier** reads the bytecode before any of it runs. It checks that every instruction and operand is well formed, that jumps stay inside their function and the stack stays balanced, and that every kit name, bridge call and web host it uses is known to its engine version and in the version's permission list [INFERENCE: the checks are set in Drop 1].
- **The runner still decides.** Signatures and the verifier bound the trust path between devices ([risks.md R55](../plan/risks.md#r55); [08 TM-35](../plan/08-security-and-privacy.md#3-threat-model)). Whatever bytecode a device runs, the runner applies its own checks to every call: the approved list (§11.11) and policy (§11.6).
- **Widgets** draw from the cache their device has checked or compiled, and never compile (§12.5).

---

<a id="12-swift-mini-apps"></a>
<a id="12-swift-apps"></a>
## 12. Apps

An App is a program that works beside a conversation: one a bot makes for the user, such as a chore list, a habit tracker or a backtest dashboard, or one of the built-in ones (§12.10) ([D68](../plan/decisions.md#d68), [D114](../plan/decisions.md#d114), [D119](../plan/decisions.md#d119); [object-model §4.32](object-model.md#432-mini-app-app_)). "The app" in lower case still means Memoshi. A bot-made App is one of two kinds:

| | Page App | Swift App |
|---|---|---|
| What it is | A sandboxed web page (§12.7; CH-37) | A Swift program run by the engine of §11 (CH-22, CH-23) |
| `kind` | `page` | `swift` |
| Stage | The Mac in Phase 1; iPhone and iPad in Phase 3, with CH-23 | The Mac in Phase 2; iPhone and iPad in Phase 3 |
| Both have | Versions, saved data, a permission list per version, the tool bridge with policy on every call, panes and places, exported functions and selection carry (§12.9) | The same |

An App opens as a pane beside the chat, a side-panel tab on Mac and iPad and full screen on iPhone, or inline; on the Mac it can also open as a sheet over its conversation, in a window or full screen ([D85](../plan/decisions.md#d85), §12.1). A Swift App can replace a page App and keep its data (§12.2). §12.1–§12.6 were written for Swift Apps and hold for page Apps too, except where they speak of Swift source, compiling, the kit, `@Saved`'s syntax, jobs or widgets; §12.7 says what differs. From Drop 1, a Swift App may also refresh itself in background jobs and offer home-screen widgets ([D71](../plan/decisions.md#d71); CH-26, CH-27, [D87](../plan/decisions.md#d87)). Viticci's "Your task garden · Version 6 of 6", with its "Ask Cobot to change it" field, is the model ([record §3.4](../research/2026-10-20-native-apple-direction.md#34-post-3-one-week-of-progress-2026-10-17)).

### 12.1 Making and opening one

- **The `mini_app` tool** makes and changes an App. The bot edits one file per call (`{ appId?, path, source }`; without `appId`, the edit starts a new App), and the runner compiles the whole App after each edit and returns its errors (§11.7). `publish` (`{ appId, note? }`, where `note` says what changed) makes the edited files a new version once they compile together; edits not yet published run nowhere and are never shown. The tool also reads an App's files, versions, permission list, saved data and log [INFERENCE: operations, arguments and where unpublished edits are kept are set in Phase 1, with page Apps; the Swift-specific parts in Phase 2]. Publishing is `self.state` (T0): it stores source and, from Drop 1, signed bytecode as a cache ([D87](../plan/decisions.md#d87)); v1.0 devices compile source locally, and compiling runs nothing ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps)). A publish that does not compile publishes nothing (§11.7). A program whose approved list names the `mini_app` tool can change its own code the same way (§11.6). The same tool makes a page App: the first edit names the kind (`kind: page` or `swift`) [INFERENCE: set in Phase 1], and for a page App the runner checks the files where it compiles a Swift App's (§12.7).
- **Where it lives.** Each App belongs to the bot that made it and changes it ([object-model §4.32](object-model.md#432-mini-app-app_)). By the user's grant it may be opened to all the user's bots (`scope: all_bots`; CH-39, Phase 1), and from Phase 2 a project-scoped App lives in its project's folder and loads only behind a trust prompt (CH-43) ([D114](../plan/decisions.md#d114); how the grant and the trust answer are recorded is [object-model's open question 22](object-model.md#open-questions)). It appears as a chip in the conversation where the bot made it, as a side-panel tab while its pane is open (§12.9), in the bot's Library, in ⌘K, on iPhone in the bot's profile, and in the sidebar's **Apps** section, which lists the user's Apps from every bot: a deliberate exception to [D43](../plan/decisions.md#d43)'s Kuvo sidebar parity ([D81](../plan/decisions.md#d81); [02 §10.11](../plan/02-experience.md#1011-mini-apps-and-live-cards)). Spotlight, Siri and Shortcuts open an App too, through an App Intent: `OpenMiniAppIntent` on a `MiniAppEntity`, indexed in Spotlight by name only [INFERENCE: names].
- **Opening** an App runs its current version on that device. It opens as a pane beside the chat, a side-panel tab on Mac and iPad and full screen on iPhone, or inline in the transcript ([D114](../plan/decisions.md#d114), §12.9); on the Mac it can also open as a sheet over its conversation, with **Open in Window** and **Full Screen** one click away. A per-App setting keeps the user's choice of how it opens (`presentation`: `pane`, `sheet`, `window` or `full_screen`; [D85](../plan/decisions.md#d85), [object-model §4.32](object-model.md#432-mini-app-app_)). A bot opens, closes and arranges panes with the view tools (§12.9). The App chrome shows its name and bot, the version switcher, an info button and the change box ([03 §8.7](../plan/03-design-system.md#87-mini-app-chrome)). The first time it opens, and when a new version adds to its permission list, the chrome first shows the list for the user to approve (§11.11). Opening is the user's action, not a tool call; what the program then calls must be in its approved list and passes policy (§11.6). An App that a bot opens with `view.open` runs its on-open calls as the program's own, exactly as when the user opens it.

### 12.2 Versions and "Ask the bot to change it"

- **Versions.** Every publish adds a numbered version with its files, its note, its permission list, the task that wrote it and that task's exposure flags. The chrome shows "Version 6 of 6" and switches between versions.
- **Permission changes.** A version whose permission list adds tools or web hosts shows what it adds, risky abilities first, and calls them only after the user approves (§11.11). A version that adds nothing opens as before.
- **Earlier versions** open as a preview: they run on a copy of the saved data, and their changes to it are dropped. **Restore** publishes an earlier version's files again as a new version.
- **The change box.** "Ask <bot> to change it", at the foot of the App, submits the request as the user's message in the conversation the App belongs to, with a reference to the App and version on screen. If neither the runner nor an available allowed model is reachable, it persists in the existing local unsent queue with its `requestId`, shows **Waiting for connection** and can be canceled before delivery; reconnect submits it once through the normal confirmed-runner path with current grants, budgets and recovery holds ([D88](../plan/decisions.md#d88), [protocol.md §5.10](protocol.md#510-live-cards-and-mini-apps)). Only an admitted, model-backed turn reads the files, edits them and publishes a new version. A run-time error offers **Ask <bot> to fix it**, which fills the box with the error and its line (§11.8).
- **A new version while the App is open** ([D81](../plan/decisions.md#d81)). A version that answers a change the user asked for in the change box replaces the running one on its own. Any other version never replaces it under the user's hands: the chrome shows "Version 7 is ready" with **Switch**. Either way, a version that needs the user's approval shows its sheet before it runs (§11.11, below).
- **Made after untrusted content** ([D72](../plan/decisions.md#d72)). A version written by a task exposed to untrusted content needs the user's approval before its first run: the chrome shows what changed and its permission list, and nothing in the version runs, its background jobs included, until the user approves (§11.11). Its T4 actions keep their draft cards in every mode, Bypass included, as runs started by outside content do ([D57](../plan/decisions.md#d57)). The chrome and the version list keep the exposure note ("Made after reading web or email content", SEC-24). A live card posted by such a task is treated the same way [INFERENCE].
- **A Swift App replaces a page App** ([D114](../plan/decisions.md#d114); Phase 2 on the Mac). A bot may publish a Swift version of an App that was a page App. It is the next numbered version of the same App: the App's `kind` becomes `swift`, its saved data stays, and its scope, its opening preference and its place under Apps do not change ([object-model §4.32](object-model.md#432-mini-app-app_)). The new version's permission list is approved like any version's (§11.11), and a saved field that the Swift version renames or drops needs a migration (§12.3). Restoring an earlier page version publishes it again as a new version, like any restore [INFERENCE].

### 12.3 Saved data

- **`@Saved`** declares a value the App keeps: `@Saved var chores: [Chore] = []`. Values are stored as JSON under their names and restored when the App opens on any device. There is no fixed size limit; a program's memory limit bounds what it holds at once (§11.8, [D71](../plan/decisions.md#d71)). Its background jobs and widgets use the same values (§12.4, §12.5).
- **The same data on every device** ([D73](../plan/decisions.md#d73)). Saved data is a merge-friendly type (a CRDT): an edit applies at once on the device where it is made, offline included, and on the runner for a background job, and edits merge per item and per field when devices meet ([object-model §3.4](object-model.md#34-runner-replicas-and-record-ownership)).
- **Growth.** Saved data syncs with the bot's records to every paired device, so an App that keeps a lot makes sync and storage grow ([D71](../plan/decisions.md#d71)).
- **Migrations at publish** ([D72](../plan/decisions.md#d72)). Publishing compares the version's saved types with the stored data. New fields get their defaults; a renamed or removed field needs a migration the bot writes, or the publish fails with a fix (`swift.migration_needed`) [INFERENCE: how a migration is written is set in Phase 2]. Snapshots stay as a safety net: the runner keeps the saved data as it was each time a version is replaced, and Restore offers it back. Snapshots, those taken before the bot's writes included (below), are kept for 30 days within a size budget, and the last 3 always; every version's files are kept ([D82](../plan/decisions.md#d82), [object-model.md §4.32](object-model.md#432-mini-app-app_)).
- **The bot and the data** ([D81](../plan/decisions.md#d81)). The bot reads an App's saved data through the `mini_app` tool, to answer questions about it or to move it to a new shape, and a read brings each value's stored labels into the task's exposure flags ([policy.md §6](policy.md#6-exposure-rule)). Writing it is T1, like a write in the bot's home, and the runner snapshots the saved data before each write the bot makes, as it does when a version is replaced (above).
- **Labels.** Each saved value keeps its provenance labels with it, per `@Saved` key and per item in a collection, so a value read back carries the labels it was saved with ([D72](../plan/decisions.md#d72), §11.6).
- **No secrets.** Saved data is scrubbed like any record ([policy.md §13](policy.md#13-secrets-in-policy)), and a value labelled `secret` is never saved (§11.6).
- **Not saved data: view state and selection** ([D114](../plan/decisions.md#d114)). What one view of an App shows in one conversation on one device, such as its open tab or item, its scroll position and its filters, is App view state: device-local, never synced, never part of saved data, and dropping it loses nothing the App saved ([object-model §4.32](object-model.md#432-mini-app-app_)) [INFERENCE: how a program declares it is set in Phase 1 for page Apps and in Phase 2 for Swift Apps]. The user's selection in a pane is neither (§12.9).

### 12.4 Background jobs

An App may declare refresh jobs, which run without a screen, on a schedule or when data it uses changes ([D71](../plan/decisions.md#d71); CH-26, Drop 1 on Mac, iPhone and iPad, [D87](../plan/decisions.md#d87)).

```swift
@main
struct Prices: App {
    let name = "Prices"
    let summary = "The prices I follow, checked every hour"

    var body: some Scene {
        WindowGroup { PriceList() }
    }

    var jobs: some Jobs {                       // [INFERENCE: syntax set in Drop 1]
        Job("Check prices", every: .hours(1)) { await checkPrices() }
    }
}
```

- **Triggers.** A job runs on a schedule, an interval or a time of day, or when data it uses changes, such as its saved data [INFERENCE: which changes can trigger a job is set in Drop 1]. A schedule runs at most every 15 minutes, and a job runs once at a time (§11.8).
- **Where it runs.** The runner of the App's conversation runs it without a screen, in a sandboxed engine helper. On the Mac that is the bot's helper, a process with no secrets, never memoshid ([04 §4.17](../plan/04-architecture.md#417-the-swift-engine-live-cards-and-mini-apps), [09 §9.7](../plan/09-platform-macos.md#97-the-engine-helpers-sandbox-d71)); on iPhone and iPad it runs inside the app, when the app is that conversation's runner and iOS grants background time ([09 §12.10](../plan/09-platform-macos.md#1210-mini-app-jobs-and-widgets-d71)). It runs the runner's signed bytecode (§11.12). A due job does not move the lease; when the conversation is idle and an awake Mac is reachable, its lease returns to the Mac, so jobs run there again ([D74](../plan/decisions.md#d74)). A job that comes due while no runner can run it runs at the next chance [INFERENCE] (Open question 12). Its threats are [08 TM-36](../plan/08-security-and-privacy.md#3-threat-model).
- **Unattended.** Every call a job makes is the program's own: origin `app`, trigger `job`, under the unattended rules and the bot's budgets, within the version's approved list ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps)). A call that a `rule` cell denies offers **Allow for this App** in the chrome the next time the App opens, and the blocked job also posts one item to the Inbox ([D81](../plan/decisions.md#d81)). A call that asks or drafts shows its native card in the Inbox and as a notification; if the run ends before the answer, a pending approval is canceled and a staged draft waits for the user's Send [INFERENCE].
- **Output.** A job has no views. It saves data and sends notifications through tools ([D71](../plan/decisions.md#d71)): its `@Saved` writes apply on its runner and merge with other devices' edits like any program's (§12.3), and it tells the user through a notification tool, which passes policy like any call [INFERENCE: the tool is set in Drop 1]. The App's widgets then reload from the exported snapshot (§12.5, [D79](../plan/decisions.md#d79)).
- **Stopping.** A job does not start while the kill switch is on, its bot is paused or a budget it charges is exhausted, as for a routine run [INFERENCE]. Each run's outcome goes to the program's log (§11.8) and to the `mini_app.job_ran` event ([events.md §5.19](events.md#519-live-cards-and-mini-apps)).

### 12.5 Widgets

An App may offer home-screen widgets on Mac, iPhone and iPad, drawn from its saved data ([D71](../plan/decisions.md#d71); CH-27, Drop 1, [D87](../plan/decisions.md#d87)).

```swift
    var widgets: some Widgets {                 // in the App's `App` declaration, beside `body` [INFERENCE: syntax set in Drop 1]
        Widget("Chores left", sizes: [.small, .medium]) { ChoresLeftWidget() }
    }
```

- **WidgetKit.** Memoshi's widget extension offers one App widget; when the user adds it, they pick an App and one of the widgets it offers [INFERENCE: one configurable widget, because an extension's widget kinds are fixed when the app is built] ([09 §12.10](../plan/09-platform-macos.md#1210-mini-app-jobs-and-widgets-d71)).
- **Saved data only.** A widget's view reads the App's saved data and makes no tool calls, so nothing in it reaches policy ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps)). It is built from the kit components WidgetKit can draw [INFERENCE: the subset is set in Drop 1].
- **From the cache.** The widget extension draws with the bytecode its device has checked or compiled, and never compiles (§11.12). The app copies that bytecode and the saved data where the extension can read them, and the extension runs within the memory WidgetKit gives it [INFERENCE]. Until the device holds usable bytecode, the widget shows a placeholder.
- **Reloads.** When the saved data or the current version changes, from the app, from another device or from a background job, the device copies the new data and asks WidgetKit to reload, within the reloads WidgetKit allows [INFERENCE] ([protocol.md §5.10](protocol.md#510-live-cards-and-mini-apps)).
- **Tapping** a widget opens the App.

### 12.6 Devices

- An App opens on any paired device, whichever devices run its bot's conversations. Its tool calls go to the runner of its conversation (§11.6). While that runner cannot be reached, calls wait with "Waiting for your Mac", and the App keeps working on its saved data.
- Its background jobs run only on the runner of its conversation (§12.4); its widgets show on any paired device that holds its saved data, from a snapshot the app exports to the App Group (§12.5, [D79](../plan/decisions.md#d79)).
- Page Apps run on the Mac from Phase 1 and Swift Apps from Phase 2; both reach iPhone and iPad in Phase 3 (CH-23), from the same source (§11.10, §12.7).
- A pane's layout is kept per device: where a view sits on one device, a side-panel tab on Mac and iPad or full screen on iPhone, is never applied to another ([object-model §4.37](object-model.md#437-view-viw_), ViewLayout).

<a id="127-web-mini-apps"></a>
### 12.7 Page Apps

A page App is an App drawn as a web page in a sandboxed web view ([D114](../plan/decisions.md#d114), [D119](../plan/decisions.md#d119); CH-37; layer 3 of [D115](../plan/decisions.md#d115)). It is the Phase 1 way for a bot to build a working pane, on the Mac; it reaches iPhone and iPad in Phase 3 with CH-23. It keeps [D29](../plan/decisions.md#d29)'s role for web content, a page for what a page draws best, and does not use the Swift engine.

- **Same contract.** Versions, the change box, saved data, scope, panes and places, exported functions and selection carry are those of §12.1–§12.3 and §12.9. A page App's version holds the page's source files (`kind: page`, [object-model §4.32](object-model.md#432-mini-app-app_)) and has no engine or kit version.
- **Sandbox.** The page runs in a sandboxed web view, and its scripts run only there. Whatever they do, the page reaches tools, files, secrets and the network only through the tool bridge; the web view, like the engine, is not a boundary policy relies on ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps)) [INFERENCE: how the web view's own loads are held to the version's approved hosts is set in Phase 1; [policy.md §18](policy.md#18-open-questions), item 27].
- **Tool bridge.** The same bridge as §11.6: each call goes to the runner of the App's conversation (`miniApps.callTool`), is refused outside the version's approved list, and is otherwise decided as the bot's call. A call made while the page handles the user's input is a gesture, attended; a call the page makes on load or on a timer is the program's own, origin `app`. Cards stay native and show over the page.
- **Permission list.** A page App has no compiler, so its version states its list of tools and web hosts; the user approves it in the same native sheet, and the runner enforces it (§11.11) [INFERENCE: how a version states its list is set in Phase 1]. A version written after untrusted content waits for approval before it first runs (§12.2).
- **Exposure.** Until a page's values can carry labels one by one, a page App's call takes the labels of every value its page has received ([policy.md §10.7](policy.md#107-live-cards-and-mini-apps), item 9).
- **The page's interface** [INFERENCE: every name in this table is set in Phase 1]. The app gives the page one object, `memoshi`, and nothing else:

  | Surface | Does |
  |---|---|
  | `memoshi.tools.call(name, args)` | One bridge call; it resolves with the tool's typed result or rejects with the `ToolError` of §11.6 |
  | `memoshi.saved.get(key)`, `memoshi.saved.set(key, value)` | The App's saved data, the same store as `@Saved` (§12.3), so a Swift App that replaces the page keeps it |
  | `memoshi.viewState` | This view's device-local state (§12.3) |
  | `memoshi.functions.export(name, schema, handler)` | Declares an exported function (§12.9) |
  | `memoshi.selection.set(summary, content)`, `memoshi.selection.clear()` | Reports what the user has selected, for the chip (§12.9) |
  | `memoshi.bot.ask(text)` | As `bot.ask` in §11.6: from a gesture only, behind the app's confirm sheet |

- **Limits.** The bridge limits of §11.8 hold: 4 calls in flight and 60 a minute. The web view's memory and work limits are set in Phase 1 [INFERENCE].
- **Decisions stay native.** A page cannot draw or cover approval, draft, sign-in or purchase cards, permission sheets, the composer or the title bar: it draws only inside its frame, and the app draws the chrome (§12.9).
- **Replaced by a Swift App.** A Swift version can replace the page and keep its data (§12.2).
- **Not Apps.** Interactive artifacts (TP-07, Phase 1) and the screens connectors provide (MCP Apps; CH-45, Phase 2) use the same web layer but are not Apps, and this spec does not define them ([policy.md §18](policy.md#18-open-questions), item 30).
- **No JavaScript Apps.** [D62](../plan/decisions.md#d62)'s Apps, JavaScript in Code Mode's engine driving native blocks, are superseded by Swift Apps ([D68](../plan/decisions.md#d68)) and stay superseded ([D115](../plan/decisions.md#d115)): a page App's script draws a web page in its own web view and never drives native blocks. Code Mode still composes tools in one step for the bot; its pinned upstream `quickjs.wasm` uses wasm2c for shipping, WasmKit as reference and compatibility fallback, and no JavaScriptCore backend ([D89](../plan/decisions.md#d89)). That backend choice does not change this Swift engine.

### 12.8 For a later public release

v1 installs only on the user's own devices, so App Review does not shape Apps (§9, [D67](../plan/decisions.md#d67)). If Memoshi is published later ([O13](../plan/decisions.md#open-decisions)), guideline 4.7 names only "HTML5 and JavaScript mini apps", 4.7.2 bars extending native APIs to such software without Apple's permission, and 2.5.2 bars downloaded code that changes the app's features ([research §5](../research/2026-10-22-python-and-native-generative-ui.md#5-app-review-rules-for-running-generated-code)). Interpreting generated Swift is the pattern Apple acted against in 2026, so a public release needs its own decision on the engine for iPhone and iPad ([risks.md R45](../plan/risks.md#r45), deferred) [INFERENCE].

### 12.9 The App contract: panes, places, functions and selection

[D114](../plan/decisions.md#d114) adds four things to an App, for page Apps and Swift Apps alike: a pane, exported functions, view tools for the bot, and selection carry. They ship on the Mac in Phase 1 (CH-33 to CH-36) and on iPhone and iPad in Phase 3 (CH-23). The pattern comes from Pi's p2 and Ultimate ([merge assessment §12.3](../research/2026-11-12-memoshi-cognitio-bot-hq-merge.md#123-the-app-contract-proposed-for-memoshi), read as the reason and not as authority); the rules are D114's. Objects and field names are [object-model §4.32](object-model.md#432-mini-app-app_)'s and [§4.37](object-model.md#437-view-viw_)'s; classes and tiers are [policy.md §10.7](policy.md#107-live-cards-and-mini-apps)'s.

- **Panes.** An App may show as a pane beside the chat: a side-panel tab on Mac and iPad, full screen on iPhone, or inline in the transcript, besides the sheet, window and full screen of §12.1. An open pane is a View (`viw_`) of kind `app`. Layout is kept per device.
- **Inline, and Apps in cards.** An App shown inline sits in the transcript in the frame of a live card ([03 §8.7](../plan/03-design-system.md#87-mini-app-chrome)) [INFERENCE: set in the design review]. It is a View placed `inline`, not a Card: an App adds no card kind ([object-model §4.18](object-model.md#418-card-crd_)). A JSON card never contains an App, a web view or a program, and the catalog has no block that hosts one (§1, rule 1). A card points to an App by reference, with a button whose `tool` action calls `view.open` (§5), and the App's chip stays the way a published App first appears in its conversation (§12.1) [INFERENCE: whether a later catalog version gains a block that places an App's inline view inside a card is set in Phase 1].
- **View tools.** A bot opens, closes, arranges and lists panes with `view.open`, `view.close`, `view.arrange` and `view.list` (CH-35). They change only what is shown; their class is [policy.md §3.1](policy.md#31-operation-classes)'s. A view grants nothing, and an App that a bot opens runs its on-open calls as the program's own (§11.6).
- **Places.** A version lists the places it adds to (`places`), from a fixed set: a side-panel tab (`side_panel_tab`), a row under Apps (`apps_row`), a ⌘K command (`command`), the look of its own function calls in the transcript (`function_call_look`), a widget (`widget`; Drop 1, §12.5) and an App Intent (`app_intent`). Never: approval, draft, sign-in or purchase cards, permission sheets, the composer or the title bar. The app enforces this when it draws, as it does for generated cards (§8).
- **Exported functions.** A version may export functions to bots: `functions: [{ name, description, params, result }]`, with `params` and `result` as JSON Schema ([object-model §4.32](object-model.md#432-mini-app-app_); CH-34). The runtime installs the current version's functions as a Code Mode namespace and replaces them in place when a version is published ([amendment §6](../plan/AMENDMENT_2026-11-13.md#6-where-the-new-parts-run)). A bot inside the App's scope calls one as a nested call of its own task; the class is `app.call` ([policy.md §3.1](policy.md#31-operation-classes), [D121](../plan/decisions.md#d121)). The function's code runs inside the App's sandbox, with no screen [INFERENCE: where it executes, the bot's engine helper for a Swift App or the page's web view, and what happens while the pane is closed, are set in Phase 1]. Every tool call it makes carries the trigger `function`, is refused outside the version's approved permission list, and is otherwise classified on its own and decided as the calling bot's call. So a function gives a bot nothing the bot could not do itself, and nothing outside the App's list. A version written after untrusted content runs no function before the user approves it (§12.2).

  ```swift
      var functions: some Functions {             // in the App's `App` declaration, beside `body` [INFERENCE: syntax set in Phase 2]
          Function("addChore", description: "Adds a chore to this week's list") { (title: String) in addChore(title) }
      }
  ```

  A page App declares the same with `memoshi.functions.export` (§12.7).
- **The look of function calls.** An App may supply how its own function calls look in the transcript (CH-40; after Pi's p2, [merge assessment §12.5](../research/2026-11-12-memoshi-cognitio-bot-hq-merge.md#125-other-ideas-worth-taking)). The look is display only, built from the call's structured details. The call's decision, its chip and any card it raised come from the runner's records, and a call of an App that supplies no look shows as a standard tool chip. It is not a Card and cannot draw one [INFERENCE: what a look may be built from, the catalog's blocks or the kit, is set in Phase 1].
- **Selection carry.** What the user selects in a pane travels with the next message they send in that conversation, once, behind a removable chip (CH-36). The program reports only what is selected: a `summary` (≤ 200 characters) and the `content`. The app adds the view and the item and takes the exposure labels from the selected values, so a program cannot mark its own selection as trusted, and a selection from mail or a web page stays untrusted ([object-model §4.37](object-model.md#437-view-viw_), Selection; [policy.md §10.7](policy.md#107-live-cards-and-mini-apps), item 14). Removed or never sent, a selection is stored nowhere [INFERENCE: the Swift spelling is set in Phase 2; the page spelling is in §12.7].
- **Scope.** The bot that made the App, or all the user's bots by the user's grant (CH-39, Phase 1); project-scoped Apps behind a trust prompt from Phase 2 (CH-43). Only a bot inside the scope sees the namespace and may call the functions, and widening the scope is the user's act.
- **What stays.** The rules for bot-written code are unchanged: sandboxed; a permission list per version that the user approves (§11.11); policy on every call; exposure labels per value; and a version written after untrusted content needs approval before it first runs (§12.2).
- **Self-check.** Before it reports an App done, the bot looks at a rendered snapshot of it (CH-38, [D110](../plan/decisions.md#d110)).

### 12.10 Built-in Apps

Mail, Calendar, Reminders merged with Tasks, Contacts, Notes (Markdown files) and Files with the Library are Apps with `source: built_in`, keyed by `builtInKey` ([D116](../plan/decisions.md#d116), [D114](../plan/decisions.md#d114); [object-model §4.32](object-model.md#432-mini-app-app_); AP-15 to AP-20 on the Mac in Phase 1, AP-21 on iPhone and iPad in Phase 3). They are native code that ships with Memoshi, written against §12.9's contract: each opens as a pane, sits under Apps, exports functions, is opened by the view tools and carries the user's selection. They have no bot-written versions, and nothing changes the signed core at run time; a bot drives one through its functions, its views and the typed tools below. They add no card kind and reuse the native cards that exist:

| App (`builtInKey`) | Tools behind it | Cards a bot's work produces |
|---|---|---|
| Mail (`mail`) | `mail.*` (CON-08) | The `draft` card with `draftKind: email` for a send; `approval` cards for tidying and for deletes (§8.4) |
| Calendar (`calendar`) | The Calendar tools (AP-14) | The `apple_data` card with `variant: calendar` to show events; the `draft` card with `draftKind: calendar` to create, update or cancel one |
| Reminders and Tasks (`tasks`) | The Reminders tools (AP-14); Tasks | The `apple_data` card with `variant: reminders`; a write is a Draft (`draftKind: reminders`) under the bot's mode, as in §11.9. Tasks add no card |
| Contacts (`contacts`) | The Contacts tools (AP-14) | The `apple_data` card with `variant: contacts`; a write is a Draft (`draftKind: contacts`) under the bot's mode |
| Notes (`notes`) | File tools [INFERENCE: set in Phase 1] | None of its own: a note is a Markdown file, and a bot's write follows the path rules of [policy.md §3.5](policy.md#35-paths) |
| Files and Library (`files`) | File tools [INFERENCE: set in Phase 1] | None of its own; an artifact that a card names in an `open` action opens in its viewer (§5) |

- **The cards do not move into the pane.** A Draft or an approval raised by work in a built-in App shows as its native card in the conversation and in the Inbox, as for any App (§11.6). The Mail pane also shows a bot's draft in its thread; sending it there is the same Send, with the same content hash and device check ([policy.md §11.2](policy.md#112-send-protocol-normative)) [INFERENCE: set in Phase 1].
- **Draft kinds.** Mail and Calendar writes use the existing `email` and `calendar` draft kinds, and a Reminders or Contacts write uses `reminders` or `contacts` ([object-model §4.18](object-model.md#418-card-crd_)) [INFERENCE: names set in Phase 1].
- **The user's own actions** in a built-in pane are the user's: they are not tool calls, raise no card and never ask ([D118](../plan/decisions.md#d118) for Mail; [policy.md §10.7](policy.md#107-live-cards-and-mini-apps)).
- **Live Apple-data cards** stay Drop 2 (AP-12; §8).
- **Open.** Whether a built-in App has a record of its own, and how a bot extends one beyond calling its functions, are [object-model's open question 26](object-model.md#open-questions).

### 12.11 Plugin developer mode

[D114](../plan/decisions.md#d114)'s plugin developer mode exists on the Mac only, is off by default and arrives in Phase 2 (CH-44). It is not Developer, the experience level that shows a program's source and log (§11.8). This spec states only what it means for cards and Apps; the records are [object-model §4.32](object-model.md#432-mini-app-app_)'s and the rules [policy.md §10.7](policy.md#107-live-cards-and-mini-apps)'s (items 16 and 17).

- **Plugins are not engine programs.** In plugin developer mode a bot may write compiled Swift plugins. They run in a separate helper process, never in memoshid or the app, and not in the engine of §11: the language of §11.4 and the interpreter's limits of §11.8 do not describe them. This is the one exception to [D72](../plan/decisions.md#d72)'s exclusion of dynamic loading. Building or loading one is `plugin.install` ([policy.md §3.1](policy.md#31-operation-classes)). The plugin interface is designed in Phase 2 ([amendment §8](../plan/AMENDMENT_2026-11-13.md#8-open-items), item 10).
- **The bridge and the list stay.** A plugin reaches Memoshi's tools only through the tool bridge, within the permission list the user approved for its version, and each call passes policy as the bot's call.
- **Full access on this Mac.** Inside plugin developer mode the user may switch a single App or plugin to Full access on this Mac, after a typed confirmation that names the risks. Only the user can turn it on: no tool, bot, App or plugin can. That App or plugin then runs outside the sandbox on that Mac and carries a badge wherever it appears. Its calls through the tool bridge still pass policy within its approved list.
- **Cards are unchanged.** Neither plugin developer mode nor Full access on this Mac lets a plugin or an App draw, cover or answer approval, draft, sign-in or purchase cards, permission sheets, the composer or the title bar.
- **Not on iPhone or iPad.** Neither exists there. An App switched to Full access on this Mac on one Mac runs sandboxed, as any App does, on every other device [INFERENCE].
- **Not offered:** changing the signed core at run time.

---

## Open questions

1. **Authoring paths.** Settled by [D68](../plan/decisions.md#d68): JSON cards, live Swift cards and Swift Apps, with one engine for the last two; JavaScript Apps are dropped (§11, §12). [D114](../plan/decisions.md#d114) and [D115](../plan/decisions.md#d115) add page Apps as a third path, in a sandboxed web view (§12.7).
2. **Interop.** Settled in part by [D115](../plan/decisions.md#d115): the format is aligned with the open A2UI standard, and cards stream (§2.1). Open: whether D53's schema is kept and mapped to A2UI or A2UI's schema is adopted, which the survey's experiment A-E4 decides ([amendment §8](../plan/AMENDMENT_2026-11-13.md#8-open-items), item 4), and whether cards from other agents (for example MCP servers) then render through the same catalog.
3. **Card size in long Chats.** Do large cards collapse to their `summary` in the transcript after a time, with the full card one click away?
4. **Promotion.** Settled in part by [D81](../plan/decisions.md#d81): a program that proves itself ships in a release as reviewed source, bundled as an engine program, and is rewritten natively only if needed (§11.10). Open: who decides, and from which usage signal?
5. **One engine everywhere.** Settled by [D81](../plan/decisions.md#d81): one language and kit on every device; the kit adapts, richer on the Mac and lighter on iPhone, and a program may mark extreme parts Mac-only with a lighter fallback on iPhone (§11.10). The adapted kit comes in Drop 1 (CH-32, [D87](../plan/decisions.md#d87)).
6. **`ForEach`.** Settled by [D68](../plan/decisions.md#d68): `ForEach` and other control flow are part of the language (§11.4).
7. **The engine on iPhone.** How much do SwiftSyntax and the interpreter add to the app, and how fast do a 200-line card and a 2,000-line App compile and run on the reference iPhone 14 Pro and iPad Pro (M1) ([D80](../plan/decisions.md#d80))? v1.0 requires local source compilation on every device; the signed cache arrives only in Drop 1 ([D87](../plan/decisions.md#d87), §11.12). The engine probe in plan week W52, which opens Phase 2, measures local compilation first, then Phase 3 ([risks.md R51](../plan/risks.md#r51); [04 §4.17](../plan/04-architecture.md#swift-engine-probe)); future cache use is not a substitute for that evidence.
8. **Saved data from two devices.** Settled by [D73](../plan/decisions.md#d73): saved data is a CRDT, so edits made on two devices merge per item and per field (§12.3).
9. **The look of Apps.** Settled by [D72](../plan/decisions.md#d72): rich styling in Apps, with contrast checked at compile time and Dynamic Type and Reduce Motion honoured automatically; live cards stay semantic-only (§11.5). It comes in Drop 1 (CH-30, [D87](../plan/decisions.md#d87)).
10. **The bridge's tool list.** Settled by [D71](../plan/decisions.md#d71): within its approved permission list a program may call every tool its bot can call, so an App runs Python on the Mac when its list names the `python` tool (§11.6, §11.11).
11. **Apps in the sidebar.** Settled by [D81](../plan/decisions.md#d81): the sidebar gets an **Apps** section, a deliberate exception to [D43](../plan/decisions.md#d43)'s Kuvo sidebar parity ([MASTER_PLAN §6](../plan/MASTER_PLAN.md#6-experience-at-a-glance)), and Spotlight, Siri and Shortcuts open Apps (§12.1).
12. **Jobs on an iPhone runner.** iOS decides when an app gets background time, so a job may run late or rarely while an iPhone or iPad holds the lease of the App's conversation (§12.4). Settled in part by [D74](../plan/decisions.md#d74): a due job does not move the lease, and an idle conversation's lease returns to an awake Mac. Open: should a job that needs the Mac wait for it [INFERENCE]?
13. **Streaming details** (Phase 1). The `card.delta` frame's final shape, the field order the card tool asks for, the placeholder for a block that has not arrived, when a streaming card's controls look active, what is left of a stream that ends early, and how partial data is scrubbed (§2.1).
14. **In-place updates** (Phase 1). The card tool's `update` operation and its arguments, whether an update may remove a block by naming it, and whether a device keeps the user's typed input across an update (§2.2).
15. **Diagram and math blocks** (Phase 1). Whether `diagram` and `math` are catalog blocks or only part of message rendering, their fields and limits, and the math notation and renderer (§3.1; CH-41).
16. **The call card's kind.** Settled on 2026-11-13: `voice_call`, a native display kind, the 22nd from Phase 2 (§8.3; [object-model §4.18](object-model.md#418-card-crd_)). Open only, for Phase 2: the payload's field names and whether a failed call leaves a card.
17. **Page Apps** (Phase 1). The names of the `memoshi` object; how a version states its permission list; how the web view's loads are held to approved hosts; the web view's memory and work limits; where an exported function runs while the pane is closed (§12.7, §12.9; [policy.md §18](policy.md#18-open-questions), item 27).
18. **Apps inside cards** (Phase 1). Whether a catalog block may place an App's inline view inside a JSON card, or a card only points to an App with `view.open` (§12.9).
19. **Sources** (Phase 1). The `sources` field of search results, and whether the catalog gains a citation block (§8.2).
20. **Draft kinds for reminders and contacts.** Settled on 2026-11-13 by [object-model §4.18](object-model.md#418-card-crd_): `reminders` and `contacts` (§12.10).

## Sources

- [D53](../plan/decisions.md#d53) and the decisions it extends ([D8](../plan/decisions.md#d8), [D29](../plan/decisions.md#d29)); [D68](../plan/decisions.md#d68) (the Swift engine), which supersedes [D61](../plan/decisions.md#d61) (Swift files compiled to JSON) and [D62](../plan/decisions.md#d62) (JavaScript Apps); [D71](../plan/decisions.md#d71) (background jobs, widgets, permission lists, tool access, sizes and bytecode); [D72](../plan/decisions.md#d72) (language, look, data migrations and untrusted content); [D73](../plan/decisions.md#d73) (merged app data); [D67](../plan/decisions.md#d67) (personal use first); [D81](../plan/decisions.md#d81) (table 1 of the review of inferred choices); [D85](../plan/decisions.md#d85) (Mac sheet, with mobile full screen unchanged); [D87](../plan/decisions.md#d87) (release boundaries); [D88](../plan/decisions.md#d88) (no-model messages); [D89](../plan/decisions.md#d89) (Code Mode, separate from the Swift engine).
- [A2UI](https://a2ui.org/); [a2ui-swift](https://github.com/BBC6BAE9/a2ui-swift) (MIT); [json-render](https://github.com/vercel-labs/json-render) and [json-render-swift](https://github.com/ivanvanderbyl/json-render-swift) (Apache-2.0), as summarized in the [generative UI research](../research/2026-10-22-python-and-native-generative-ui.md).
- Ronith's Swift interpreter, as recorded in the [generative UI research §3](../research/2026-10-22-python-and-native-generative-ui.md#3-roniths-swift-interpreter): a compile step to bytecode, an interpreter, and native SwiftUI apps run from a `.swift` file.
- Interswift (MIT, commit `03486798`), as recorded in the [generative UI research §4](../research/2026-10-22-python-and-native-generative-ui.md#4-interswift-in-detail-observed-commit-03486798-archived-in-evidence): a SwiftSyntax guest compiler, a stack VM and a SwiftUI renderer, which reports "Unbridged symbol", "Unbridged modifier" and "Unbridged view expression" as diagnostics.
- [swift-syntax](https://github.com/swiftlang/swift-syntax) (Apache-2.0 with the Runtime Library Exception): `Parser.parse(source:maximumNestingLevel:)`.
- Viticci's task garden App, in the [native Apple direction record §3.4](../research/2026-10-20-native-apple-direction.md#34-post-3-one-week-of-progress-2026-10-17).
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), last updated 2026-10-16, for a later public release only.
- [D110](../plan/decisions.md#d110) (the self-check snapshot), [D111](../plan/decisions.md#d111) (the call card), [D112](../plan/decisions.md#d112) (connect cards and source chips), [D114](../plan/decisions.md#d114) and [D119](../plan/decisions.md#d119) (Apps: kinds, panes, places, functions, selection, plugin developer mode), [D115](../plan/decisions.md#d115) (three layers, streamed catalog cards, native diagrams and math), [D116](../plan/decisions.md#d116) and [D118](../plan/decisions.md#d118) (the built-in Apps and mail), [D121](../plan/decisions.md#d121) (classes and tiers, stated in [policy.md](policy.md)); the [scope amendment of 2026-11-13](../plan/AMENDMENT_2026-11-13.md) §4.5, §6 and §8.
- The [generative UI survey of 2026-11-11](../research/2026-11-11-generative-ui-sota.md) §3 (catalog-constrained streamed cards; A2UI v1.0's flat adjacency list) and the [merge assessment](../research/2026-11-12-memoshi-cognitio-bot-hq-merge.md) §12.3 (the App contract) and §12.5 (function-call rendering owned by the App): the reasons for D114 and D115, not authority.
