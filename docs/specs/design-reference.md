# Design reference: newer native assistant preview

**Implemented slice:** 2026-10-25, extending the first native preview of 2026-10-24 under [D92](../plan/decisions.md#d92), [D93](../plan/decisions.md#d93) and the user's newer-reference choice in [D94](../plan/decisions.md#d94). This starts the visual-review work in P0-13/P0-19; **neither ticket, P0-09 nor any Phase 0 runtime/device/performance gate is complete**.

The later [text-only Mac integration](#5-real-text-chat-in-the-approved-shell) uses this approved visual family without replacing its layout or turning examples into live resources. Its runtime/native evidence is separate from the original design-only observations.

**Updated 2026-11-21 for [D144](../plan/decisions.md#d144):** Viticci's November 2026 design leads the shell first, with Cognitio kept for selective borrowing later. [Direction from 2026-11-21 (D144)](#direction-2026-11-21) is the current rule. The earlier [D106 section](#direction-2026-11-13) and §1–§7 are kept as historical records.

<a id="direction-2026-11-21"></a>
## Direction from 2026-11-21 (D144)

[D144](../plan/decisions.md#d144) amends [D106](../plan/decisions.md#d106)'s shell-lead order: **Viticci's November 2026 macOS and iOS/iPadOS design leads first**, rebuilt in Memoshi's own SwiftUI code with Memoshi's own tokens, brand, and original avatars. Cognitio remains available for selective workbench/power-user borrowing once the Viticci-led shell is in place.

### Primary visual references (November 2026)

| Reference | Platform | What it defines |
|---|---|---|
| `HXlzoVyXYAAaqV5.png` ([2123856109043929439](https://x.com/viticci/status/2123856109043929439), 20 Nov) | macOS | Primary Mac shell: warm ivory/amber palette, sidebar hierarchy, 3×3 pinned bot grid with Mac-host badge, pinned group chats, bots list, floating header pill, inter-bot message card, inline diff + file-change confirmation/undo rows, warm amber user bubbles, link pills, `Worked Xs · N steps >` disclosure, and composer |
| `HXgvBUIXYAE2lcT.jpg` ([2123498930206089381](https://x.com/viticci/status/2123498930206089381), 19 Nov) | macOS / iPad | Close-up typography & transcript polish: warm amber user bubble, brain + `{}` icons on `Worked 53s · 1 step >`, elevated white assistant card, timestamp + retry (`↻`), and composer pills (`Model`, `High`, `Fast`, voice waveform, mic) |
| `HXBwE66X0AAqvU6.png` ([2121318820132643152](https://x.com/viticci/status/2121318820132643152), 13 Nov) | iPhone Duo / iPad | Adaptive split layout, `Today (30 done >)` header, 3×3 pinned bot grid + Mac-host badge, pinned multi-bot groups, inline MCP pill in prompt, floating right-edge vertical tab bar |

### Surface-by-surface target spec (Phase 1 macOS shell)

1. **Window & palette (Warm ivory/amber)**
   - Unified frameless-style macOS window with warm cream/ivory canvas (`#FAF7F0`-family), slightly warmer tinted sidebar (`#F3EFE6`-family), crisp white elevated assistant cards with subtle hairline border, and rich warm amber user bubbles (`#9E6316`-family) with white text.
   - Top-left window controls (`...`, `+ ▾`, sidebar/inspector toggle) in circular/pill glass buttons.
2. **Sidebar (left column)**
   - **Search:** `Search Everything` rounded field at top.
   - **Utility navigation:** `Today`, `Waiting for You`, `Library`, `My Apps`, `Bookmarks`, `Activity` (monochrome SF Symbols, clean single-line rows).
   - **Pinned bots:** 3×3 circular avatar grid with bot name below each. Selected bot has a soft rounded-rect highlight. Mac-hosted bots show a small black circular Mac-display badge at bottom-right of the avatar.
   - **Pinned groups:** Multi-bot rooms below the grid with clustered circular avatars, pin icon, relative day, and single-line last-message preview.
   - **Bots list:** Chronological list of remaining bots (`Avatar`, name, timestamp, 1-line preview).
3. **Transcript (center column)**
   - **Floating bot header pill:** Centered/top-left capsule showing bot avatar, name, permission/mode badge (e.g. `🔓 Bypass` / Memoshi policy mode), model subtitle (`Claude Opus 5.5` / `GPT-6.1 Sol · Fast`), and dropdown chevron.
   - **Inter-bot handoff card:** Compact centered pill/card (`Messaged <Bot>`, avatar + 2-line preview + disclosure chevron).
   - **Assistant message card:** White rounded card on the warm canvas supporting rich markdown, syntax-highlighted code/diff blocks with copy/expand actions, and inline file-change confirmation/undo rows (`Not Confirmed: <file> · Size A -> B Undo`).
   - **User bubble:** Right-aligned warm amber rounded bubble; inline link/MCP pills below or inside the prompt.
   - **Work summary disclosure:** Compact `brain {} Worked Xs · N steps >` row above the assistant card; tool-count pill (`🔧 1 >`) and timestamp + retry (`↻`) below.
4. **Composer (bottom)**
   - Rounded light-surface container (`Message <Bot>`) with bottom control bar:
     - Left: `+` (attachments/tools), model selector pill (with provider icon), reasoning-effort pill (gauge icon, e.g. `High`), speed/tier pill (bolt icon, e.g. `Standard` / `Fast`).
     - Right: realtime voice waveform button, dictation microphone button.

---

**Updated 2026-11-13 for [D106](../plan/decisions.md#d106)–[D122](../plan/decisions.md#d122):** the lead reference changed. [Direction from 2026-11-13](#direction-2026-11-13) is the current rule. §1–§7 are kept with their evidence unchanged, as the record of the earlier direction ([D92](../plan/decisions.md#d92), [D94](../plan/decisions.md#d94)).

<a id="direction-2026-11-13"></a>
## Direction from 2026-11-13 (D106)

[D106](../plan/decisions.md#d106) supersedes D92's design hierarchy and D94's preview as the lead reference, and amends [D91](../plan/decisions.md#d91): the Kuvo code reuse that D91 permits is not taken for the interface. This section states the rule now in force. It adds no implementation and no evidence.

| Topic | Rule from 2026-11-13 | Decision |
|---|---|---|
| Lead | Cognitio (`~/Projects/Cognitio`, the user's Kuvo-derived Mac app) is the reference for the shell on Mac, iPad and iPhone: card window, sidebar, transcript, composer, bot identity and editor, side panel, workbench and settings (catalog rows SH-06, SH-07, IOS-01) | [D106](../plan/decisions.md#d106) |
| Viticci's grammar | Stays for native Apple-data cards, Apps and phone navigation. It no longer leads the shell | [D106](../plan/decisions.md#d106) |
| Own code | The interface is written new in Memoshi as one SwiftUI codebase shared by the three devices, with AppKit or UIKit only where a surface needs it. No Kuvo- or Cognitio-derived source file, asset or string enters this repository. Cognitio's running app and source are read as a behaviour reference; code is not translated file by file | [D106](../plan/decisions.md#d106) |
| Cognitio | Continues in its own repository under its own licence. Memoshi's agents do not edit it. It is the behaviour reference and the oracle for capability ports | [D107](../plan/decisions.md#d107) |
| Dependencies | SwiftTerm, Textual, WhisperKit and the usage-meter library that UsageKit forks stay usable from their original upstreams, not from Cognitio's forks | [D106](../plan/decisions.md#d106) |
| The earlier preview | The Viticci-style Mac and iPhone preview recorded in §1–§6 is frozen at git tag `design-preview-2026-11-13` and kept as a reference. The new shell starts from Cognitio's layout and reuses Memoshi's own tokens and avatar set where they fit | [D106](../plan/decisions.md#d106) |
| Behaviour descriptions | Each surface needs a written behaviour description before it is built, because the source may not be copied | [D106](../plan/decisions.md#d106) |
| Reuse assessment | §7's outcome, that no source is imported, now holds by decision: it was the assessment's finding, and D106 makes it the rule for interface code | [D106](../plan/decisions.md#d106) |
| Release | O13 stays open; nothing built under D106 may close a public or paid release | [D106](../plan/decisions.md#d106) |

**How to read §1–§7 now.**

- Where they say a reference "leads", or call the shell or visual family "approved", they mean the D94 preview, the one now frozen at the tag. The Viticci references in §1 led that preview; they do not lead the new shell.
- Their build, native-smoke, contrast, text-chat, gallery and token-pipeline evidence stands within its recorded scope. None of it is evidence for the Cognitio-led shell, which has no implementation record yet.
- Stage statements in them, and in the linked assessment, describe the plan on their own dates. The current stages are in the [scope amendment](../plan/AMENDMENT_2026-11-13.md).
- In the assessment's [adoption ledger](../research/2026-11-04-phase0-design-reference-assessment.md#9-user-review-and-adoption-decisions-still-required), the row "One named reuse selection, if desired" is answered for interface code: none is selected. The diff-folding value logic that §7 calls a bounded candidate is not taken either. D106 does not record an outcome for the ledger's other rows.

**Open after D106.**

1. Who writes each surface's behaviour description from Cognitio, and when. The design review decides ([amendment §8, item 11](../plan/AMENDMENT_2026-11-13.md#8-open-items)). No decision says which file holds the descriptions.
2. The palette the new shell starts from. D106 says only that Memoshi's own tokens and avatar set are reused where they fit; §6 records no final palette approval between Current and Warm.

---

**Record of the earlier direction (2026-10-24 to 2026-11-04).** Everything from §1 to §7 was written under D92 and D94, before D106. It is kept as written.

## 1. Reference and rights boundary

The newer user-supplied set leads this slice, rather than merely polishing the first simplified layout:

| Reference | Observed direction | Implemented interpretation |
|---|---|---|
| `ios.jpeg`, `ios2.jpeg`, `ios3.jpeg`, `ios4.jpeg` | Warm ivory/amber, floating bot identity, four bottom tabs, compact composer, resource-specific cards | Original floating identities; native Bots/Memoshi/Others/Search tabs; compact local-draft controls; serif resource headings and native actions |
| `mac.jpeg`, `mac2.jpeg`, `mac3.jpeg`, `mac4.jpeg` | Richer navigation, central conversation, contextual activity/resource or another bot conversation; a separate quick-ask surface in one capture | Richer searchable sidebar and selectable Activity/Details/Chat right column; no separate QuickAsk implementation in this slice |
| [iOS clip](https://x.com/viticci/status/2111581381310533775) | 11.63-second dark-appearance clip showing roster/tabs and app switching/reopening | Native navigation and appearance reference, not evidence of Memoshi execution or a promise to reproduce the demonstrated data |
| `old_ios.jpeg`, `old_ios2.jpeg`, `old_mac.jpeg`, `old_mac2.jpeg` | Earlier interfaces for comparison | Historical context, not the current layout target |

All twelve JPEGs were inspected in the user's private `~/Downloads/viticci/` folder. Their filenames are evidence labels, not bundled assets or authenticated mappings to individual public posts. The earlier public [Mac](https://x.com/viticci/status/2112555465313853810) and [iPhone](https://x.com/viticci/status/2111418614343504107) references remain documented in the [full record](../research/2026-10-21-viticci-full-record-sep-oct.md) and [follow-ups](../research/2026-10-22-viticci-followups.md).

No third-party screenshot, avatar, artwork, product branding or personal transcript is bundled. Bot avatars use original SF Symbol compositions; the conversation copy, reading note and forecast values are original Memoshi examples. Warm's values are an original interpretation, **not pixel-sampled competitor tokens or a final visual approval**.

[D91](../plan/decisions.md#d91) permits personal/noncommercial Kuvo source inspection and selective reuse under its applicable terms. **The D94 visual slice imports no Kuvo code and changes no runtime.** The subsequent Pi text integration is described in §5; it is not a Kuvo frontend import or a licence/distribution clearance. Workbench/review, App/version and source-reuse assessment remain under their existing tickets.

## 2. Design-preview behavior and shared navigation

| Surface | Available now | Truthful boundary |
|---|---|---|
| Appearance | Current/Warm selection in the Mac toolbar and mobile Palette menu; floating bot identities; light/dark and increased-contrast variants | A preference local to each Memoshi app, not a synced setting or the planned Frosted/Solid control |
| Mac Local Daemon status | Independent toolbar/popover for actual signing/connection and the selected development profile | The current text profile bootstraps real Chat state, never preview stores; it offers no background-registration controls. Default ad-hoc signing remains refused. Infrastructure supervision and its earlier observations are in the [foundation record](../HANDOFF.md#foundation-implementation-proof); real chat is §5. |
| Mac sidebar | Waiting for You, Library, Pages, Activity, local project context, Pinned and Bots; searchable bots/resources; Open Beside | Assistant opens real text chat when Design Preview is off; other bots/resources/projects remain original examples, not a connected registry or project manager. |
| Mac context | Activity for the selected bot, resource details, or an independently selected second bot pane; close/reopen | The same Assistant mirrors its one real Chat in text mode; other bots remain example chats. No independent same-bot session or live Activity system is invented. |
| iPhone/iPad shell | Adaptive native TabView; Bots, Memoshi, Others and Search; bot chooser, resource/Activity inspector and Done | Current phone interaction was simulator-reviewed; the new tablet arrangement has not been re-reviewed on iPad |
| Preview conversation and cards | Selectable sample messages; serif resource headings, category labels, opaque cards, native Share/Copy, detail presentation, Hours/Days and note disclosure | These examples contain no WeatherKit/location request, live forecast, model result or fetched research. |
| Preview composer | Compact multiline draft, insert example prompt, copy/clear and connection-information popover; controls stack at accessibility sizes | Local preview draft only; the real Mac text composer is separate (§5), with no attachment upload or full offline queue. |

**Palette semantics:** Warm is the initial preview selection. Current preserves the previous neutral/system-accent color values; both palettes use the newer layout. Choosing Current is not an old-layout rollback. The preference is `design-preview.palette`, stored separately by each app. Switching preserves selected bots, navigation, pane state and drafts.

**Two-pane semantics:** different bots retain independent drafts in the shared `ComposerDrafts` model. Showing the same bot in both Mac panes mirrors its single example conversation and draft. It does not create an independent same-bot session. Opening Activity or resource details preserves the main route and the secondary bot selection.

Example UI continues to say **Design Preview**, **Not connected** and **Examples only**. Those labels remain scoped to examples, not the real Assistant in text mode. The actual Mac integration now applies protocol snapshots/events and acknowledges application receipts; preview identities/preferences have not become a second canonical domain model. [HANDOFF](../HANDOFF.md#text-chat-development-proof) owns the real implementation proof and limits. The future Apps section and accepted feature stages are unchanged.

### Native layout choices

- One Mac `HSplitView` owns the sidebar, main content and optional context. The app owns a `PreviewWorkspace` value graph; each conversation/Activity callback receives the bot actually displayed in that pane. View/toolbar toggles share the same state. Bot shortcuts are ⌘1–⌘3; sidebar is ⌃⌘S and Context is ⌃⌘I.
- Mac content minimum remains 1040 × 700 points, with native title-bar height additional. Context widths adapt to Activity/resource versus conversation content. The previous `NavigationSplitView` plus inspector fitting-size failure on macOS 27.0.1 remains avoided by the single split, not by removing a pane.
- The Mac bot capsule is a plain native Button with a bot-options popover. A borderless native Menu flattened the custom capsule label during runtime review; it was replaced rather than leaving a text-only imitation of the requested header.
- Mobile uses native adaptive tabs and inspector presentation. Large accessibility sizes put the floating identity below the toolbar and stack composer/card controls instead of squeezing them into normal-density rows.
- Resource content stays opaque. Custom material chrome falls back to semantic raised surfaces with Reduce Transparency. Native text styles and Dynamic Type remain in use; no new looping animation or shader is introduced.
- Sender announcements belong to the message's combined static-text element, not the native selectable `Text` child. The latter caused a reproducible AppKit/SwiftUI accessibility-label recursion in the second chat on macOS 27.0.1. Moving the semantics preserves both selection and sender/example announcements; the isolated native repro and full traversal passed afterward.
- Mac conversation/live-chat containers use explicit accessibility containment so their identifiers do not overwrite composer/Send/Stop controls. Real message bubbles reuse the combined static-text sender pattern above, keeping semantics off selectable `Text`.

## 3. Code and build boundary

`Packages/MemoshiApp/Package.swift` retains four app-facing targets:

| Target | Responsibility | Dependencies |
|---|---|---|
| `AppCore` | Preview bots/resources, workspace transitions and per-bot local drafts | System frameworks |
| `DesignSystem` | Generated palette-aware tokens, adaptive colors, floating identity, palette selector and preview notice | SwiftUI/system frameworks |
| `ConversationFeature` | Example transcript, card anatomy/actions/details, compact composer and Activity | `AppCore`, `DesignSystem` |
| `ShellFeature` | Platform navigation, sidebar routes, bot selection and contextual presentation | `AppCore`, `DesignSystem` |

Features do not import one another. `apps/mac/Memoshi/MemoshiApp.swift` and `apps/ios/MemoshiMobile/MemoshiMobileApp.swift` compose conversation, Activity and resource-detail closures. `PreviewWorkspace` separates main bot, secondary bot, activity target, resource target and context mode; selecting context does not overwrite the main chat. The mobile target explicitly depends on DesignSystem. The **design-only slice** introduced no third-party dependency, signing/entitlement setting, service registration or protocol change. The later [D95 foundation](../HANDOFF.md#foundation-implementation-proof) composes `MemoshiClient` and shared exact-pinned NIO transport at the Mac app boundary, through [`DaemonSupervisor`](../../apps/mac/Memoshi/DaemonSupervisor.swift) and [`DaemonStatusView`](../../apps/mac/Memoshi/DaemonStatusView.swift), not through the sample feature stores. Registration stays an explicit user action; no signing bypass or default-signing cutover is part of either slice.

The subsequent text-only integration adds `MemoshiRuntime` behind the daemon, while real-chat presentation remains in the Mac app's `LiveChatModel`/`LiveChatView`. It does not move Pi imports into shared feature targets or change mobile into a runtime host. See §5 and the [current architecture boundary](../plan/04-architecture.md).

[`design-tokens.json`](design-tokens.json) remains canonical. `color.*` retains the prior values for Current; `palettes.warm` supplies four-appearance overrides, with `surface.resource` and `text.onUserBubble` roles. `swift scripts/design-tokens.swift` generates `Packages/MemoshiApp/Sources/DesignSystem/GeneratedTokens.swift`. The small palette environment value and native tint resolve from the same preference; no model, reference container or closure is carried in that custom environment value.

The generator now also emits typography, motion/avatar bindings, native material/elevation bindings, performance budgets and the intended contrast-pair catalogue from the canonical source. This is generated coverage, not full P0-13 native-surface, performance or adoption acceptance. Do not hand-edit generated Swift. The package retains an English string catalog; no additional translation set is claimed.

Run from the repository root:

```sh
scripts/ci.sh
open build/DerivedData/Build/Products/Debug/Memoshi.app
```

For an already booted iOS 27 simulator:

```sh
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/MemoshiMobile.app
xcrun simctl launch booted com.mehmetcanbudak.memoshi
```

Use a specific simulator UDID instead of `booted` when several simulators run. The real-device/model/chaos execution hold remains unchanged.

## 4. Observed native smoke evidence

Private Memoshi captures live outside the repository in `../evidence/2026-10-25-memoshi-newer-ui/`. Current/Warm comparison captures use the same content, pane selection and normal text size; native presentation transitions were allowed to settle before capture.

**Final build/check run, 2026-10-25:** `swift scripts/design-tokens.swift && scripts/ci.sh` passed after the native accessibility fix: token drift; strict format/lint and import boundaries for 89 Swift files; 4 app-core behavior tests and 41 protocol tests; all 3 resolved dependency licences; protocol-schema drift; XcodeGen; Mac/iOS Simulator builds; and embedded-helper bundle layout.

| Environment | Exercised/observed result | Capture |
|---|---|---|
| Mac, macOS 27.0.1 | Current ↔ Warm updates native controls and content without losing draft text; same-state Memoshi/Scout comparison | `mac-current.png`, `mac-warm.png` |
| Same Mac | Different pane drafts survived palette switches; primary bot chooser changed the main bot without replacing Scout; secondary work chip targeted Scout's Activity; returning to Chat preserved drafts; test draft text restored | Same-state comparison and native accessibility assertions |
| Same Mac | Forecast expand selected Details and the forecast; Library exposed both original resources; Pages opened the reading note; Waiting for You showed an honest disconnected empty state | `mac-library.png` |
| Same Mac | Copy exported the exact labelled original forecast through NSPasteboard; previous clipboard contents restored | Native clipboard assertion; no external delivery |
| Same Mac, minimum size | Requested 1040 × 700 outer size clamped to 1040 × 752; Activity ↔ Chat transitions retained both conversations and available composers | `mac-minimum.png` |
| iPhone 18 Pro Max simulator, iOS 27.0 | Current ↔ Warm preserved the selected bot and inserted local draft; Memoshi/Others round trip preserved Scout's draft; own inserted text cleared | `ios-current.png`, `ios-warm.png` |
| Same iPhone simulator | Bots and dedicated Search screens opened; resource expand/Done and bot-specific Activity/Done worked | `ios-bots-tab.png`, `ios-search-tab.png`, `ios-resource-details.png`, `ios-scout-activity.png` |
| Same iPhone simulator | Native ShareLink entered UIKit's share flow and was dismissed without choosing a destination; logs recorded `activityViewControllerDidAppear` and manual dismissal | UIKit diagnostics; simctl's base-app captures did not include the remote sharing scene, so no complete share-sheet screenshot or delivery is claimed |
| Same iPhone simulator | Warm dark appearance, Increase Contrast and accessibility-extra-extra-extra-large text rendered stacked controls and the below-toolbar identity; original light/large/contrast-disabled settings restored | `ios-warm-accessibility.png` |

Permanent behavior tests cover draft isolation/exact text/restoration and workspace target preservation across main selection, Activity, resource and secondary-chat transitions. Native smoke is not replaced by those tests.

### Warm token contrast calculation

Token-only sRGB calculations cover primary, secondary, tertiary and placeholder text over the eight opaque warm surfaces, plus user-bubble foreground/background. They do not certify material composites, every icon/focus state or full WCAG compliance.

| Appearance | Minimum enabled body-text ratio | User-bubble text ratio |
|---|---:|---:|
| Light | 4.75:1 | 5.36:1 |
| Dark | 5.11:1 | 6.10:1 |
| Increased-contrast light | 7.54:1 | 8.31:1 |
| Increased-contrast dark | 7.32:1 | 12.36:1 |

### Limits and historical evidence

The first preview's 2026-10-24 captures and eight native observations remain in `../evidence/2026-10-24-memoshi-first-ui/`, including its iPad regular-width check. That historical tablet result does not verify the new tab-based iPad arrangement. That preview slice had no new physical-device, complete VoiceOver/keyboard-navigation, Reduce Motion, performance or iPad-interaction audit; §6 records the later, bounded native gallery work.

P-STREAM/P-IDLE/P-AMBIENT/P-HIDDEN, paced reveal/polish, connected resources, workbench/reuse assessment and the full P0-09 demo remain under their existing tickets. The original animated multi-status avatar/gallery is now implemented in §6, without certifying those budgets. Real text streaming in §5 is also not a performance-budget pass. The next user design review chooses refinements and the preferred palette; it does not retroactively certify runtime features.

The original UI observations do not certify the later daemon/status/foreground path or real chat. Their distinct actual evidence belongs to the [foundation](../HANDOFF.md#foundation-implementation-proof) and [text-chat proof](../HANDOFF.md#text-chat-development-proof), with Apple Development signing kept separate from Developer ID/notarization, real-device/recovery and release gates.

## 5. Real text chat in the approved shell

The 2026-10-25 native text-chat proof replaced the simplified preview transcript with one actual Assistant Chat backed by the fixed Pi development snapshot. `LiveChatModel` consumes actual daemon snapshots/receipts; `LiveChatView` presents committed messages, a live partial response, a compact model picker/composer and real Send/Stop. That proof used a local provider, with a **Local** host badge, **Text-only development · Tools and Apple connectors off**, and other bots/resources labelled as examples. The subscription-ready settings in §6 supersede its local-only setup, not its retained inference proof.

- Current/Warm retain the same newer layout; real bubbles and controls resolve the existing palette tokens.
- The toolbar's **Design Preview** toggle shows the original examples separately. Toggling back restores the real history; no sample forecast or note is promoted into Pi.
- The right pane retains Activity/Details/Chat. Same-Assistant Chat is a mirrored view of the same canonical messages/draft, not a new thread. Scout/Weather, Activity and resource cards remain examples.
- That proof used a keyless local OpenAI-compatible endpoint. Model Settings now also offers explicit native ChatGPT sign-in and Keychain API-key setup (§6); there is no automatic API-key, subscription or local fallback. Tools, MCP/Code Mode and Apple connectors remain disabled. The mobile app remains the design preview.
- The app-owned helper uses a separate development root; default ad-hoc authentication stays fail-closed. Signing/provisioning defaults and automatic background registration are unchanged.

The [authoritative native/runtime proof](../HANDOFF.md#text-chat-development-proof) records real arithmetic output, a streamed long answer canceled through the native Stop button, exact history after normal quit/reopen, Current/Warm state preservation, preview isolation and same-Chat mirroring. Private Memoshi captures are in `../evidence/2026-10-25-memoshi-text-chat/`; they do not bundle third-party references. This verifies the exercised development path, not full keyboard/VoiceOver/performance QA, a Pi slice tag, an iOS engine or any held gate.

## 6. Original avatar/gallery and subscription-ready development

`Component Gallery` is reachable from the Mac's Development menu and menu-bar extra. [`ComponentGalleryView`](../../Packages/MemoshiApp/Sources/DesignSystem/Gallery/ComponentGalleryView.swift), `DSAvatar` and its Core Animation renderer use the existing generated token source, currently **4.0.0-draft.11** (draft.10 until 2026-11-13). These are original parametric shapes, not copied reference-app art.

- **Actual native surface inspected (2026-11-03):** Current/Warm side by side; light/dark, standard/increased contrast, material/Reduce Transparency and motion/Reduce Motion comparisons; the avatar grid; all twelve silhouettes and twelve colors; and the 16/20/28/40/64/96-point size inventory. The playground's Working → Needs you → Needs attention changes and control/offline overlay toggles were exercised, with native AX trees and window captures retained. Comparison overrides did not change system accessibility preferences.
- **Small rendering and motion:** small paths/eyes are pixel-aligned to display scale, and entry hop/wake motion uses token-driven springs. A real layer-backed `NSWindow` diagnostic reproduced thirteen animated avatars when an error one-shot bypassed the twelve-avatar loop cap. The shared priority budget now includes one-shots: twelve remained animated, the error was admitted, expiry restored a loop, Low Power one-shots stayed bounded and hidden/detached avatars stopped. This measures actual animation presence/lifetime, not CPU, frame time, energy or main-thread cost.
- **Accessibility boundary:** status glyphs have text fallbacks; the inspected playground displays status plus control/offline semantics and a static Reduce Motion form. Native preview comparisons and AX inspection are not a complete screen-reader, keyboard-navigation, Dynamic Type, system-settings or reference-device accessibility audit. The earlier token-only contrast calculation remains distinct from rendered material/icon/focus contrast.
- **Native subscription account exercised:** **Sign in with ChatGPT** uses PiAI's current `openai` direct-scope OAuth flow and app-owned, device-only Keychain storage. The daemon receives a bounded access-token lease, not a refresh token; the pinned provider's `ModelAuth(apiKey: access)` is its native request representation, not a requirement for the user to buy an API key or use legacy Codex login. API-key setup stays separate and a local server is optional. The [real-account Mac proof](../HANDOFF.md#real-cloud-chat-proof) now covers `openai/gpt-6.1-sol`, an actual streamed response stopped through the native button, exact stopped history after normal Quit/reopen and a fresh cloud reply without repeating sign-in. The composer now labels subscription usage separately from API-key charges. This does not qualify iCloud, locked/unattended operation, devices or performance; the earlier synthetic refresh proof remains a distinct diagnostic.

The [consumer proof and remaining gates](../HANDOFF.md#consumer-follow-through-proof) own qualification status. Private Memoshi gallery captures/AX records and real-layer diagnostic source/output are retained in `../evidence/2026-11-02-memoshi-consumer-qualification/native/`. No final palette approval, held physical-device run, performance-budget pass, SDK slice tag or product-tool enablement follows from this work.

**Static follow-through, 2026-11-04:** the actual `swift scripts/design-tokens.swift --check`
[run](../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/design-static-checks.json)
passed generated-Swift drift, 146 intended role pairs across two palettes and four appearances,
and the feature-source color/spacing/size/duration/curve rules. Draft.9 records 26 minimally
derived foreground corrections; surfaces, identity colors, fills, thresholds and pairings
remain unchanged. Layout numbers and design adoption remain provisional.

**2026-11-13:** the same check reported 159 intended role pairs after the code review added the
avatar name-text pairs on `surface.content`. Later the same day [D127](../plan/decisions.md#d127)
corrected the 48 avatar name-text values so that bot names meet the declared contrast on all
eight surfaces, and changed the identity badge to `accent.onFill` on `accent.fill`. Token
source 4.0.0-draft.11 passes with 243 intended role pairs across two palettes and four appearances.
The 146 above is the 2026-11-04 run's count and stays as its record.

**Actual-surface follow-through, 2026-11-04:** a freshly rebuilt, view-only Mac composition
hosted the unchanged public gallery, actual conversation preview and actual `LiveActivitySheet`.
It constructed no helper, engine, broker or network owner. The
[bounded receipt](../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-current-9f2ba72a/current-native-smoke.json)
records current coverage; actual AX records and owned-window captures are retained alongside it.

- All five generated custom-material recipes and the `e0`–`e6` ladder now have labelled gallery
  specimens. The composer is editable and records an exact local-only receipt; Send disables
  after the draft clears. Native review reproduced disappearing Frosted foregrounds: glass
  was attached to an empty background shape. Applying glass to the content, with the public
  identity variant for opaque content, restored readable foregrounds in the same
  [comparison](../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-current-9f2ba72a/materials-glass-fixed-comparison-actual-window.png).
  The failing capture is retained. This does not certify rendered material contrast.
- The actual preview retained the same draft across Solid and Frosted. A live, already
  authorized public keyboard-event sender entered the exact Unicode sample and dismissed
  Activity with Escape, returning to the usable parent. Earlier short-lived CLI sender
  attempts did not update those states; the different result does not establish their exact
  failure cause. No system permission or accessibility setting was changed.
- Manual Start → three Append actions → Settle preserved the exact selectable message.
  Append disabled at the final passage; settlement restored the complete sender/text
  announcement. Context insertion, its real field-focus action and card resolution/removal
  of the obsolete question action were exercised. No timer, model, reveal scheduler or
  later Aiden motion pass was introduced.
- Current Motion/Reduce Motion and default/accessibility-text typography comparisons were
  rendered. Populated, empty and omitted-history Activity states rendered six labelled
  synthetic event kinds, the baseline and bounded-history notices. These are actual view
  results, not live authenticated IPC, kernel attribution or historical audit qualification.

The generator now applies the same installed `swift-format` configuration for generation and
drift checking; generated values/provenance are unchanged by that formatting correction.
The earlier token and 534-file format checks passed before the subsequent pipeline additions.
Full VoiceOver, keyboard-only/focus return, complete text-size/locale/RTL coverage, actual
system-setting contrast/transparency, physical iPad adaptation, reference performance/animation
budgets and user adoption remain open.

**Glyph and native-accent pipeline follow-through, 2026-11-04:** Draft.10 now generates the
canonical general glyph map and existing sizes. The freshly rebuilt native gallery exposes
all **76** entries in its AX inventory; **71** SF Symbol names are checked against the installed
public `NSImage(systemSymbolName:)` API by the generator. Five custom/composed/deferred marks
remain explicitly typed renderer/artwork references, never invalid SF names or substituted
art. The actual [glyph surface](../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-current-9f2ba72a/generated-glyphs-visible-actual-window.png)
renders native symbols and honestly labels those references. This does not implement the
later activity-mark renderer or certify custom-art adoption.

Current `accent.text` and `accent.fill` now derive from the resolved native accent in quantized
sRGB by adjusting OKLCH lightness and reducing chroma only at the gamut boundary. Text uses
every declared opaque pair at the unchanged standard/increased floors; fill uses its actual
on-fill label. A four-appearance cache keys native accent/content/window colors; generation
rejects an unsupported new native background input instead of silently using an incomplete
key. Warm and canonical fallback bytes remain unchanged. Published OKLab coefficients and
their public-domain provenance are recorded in source and `NOTICE`.

The actual [native receipt](../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-current-9f2ba72a/pipeline-native-smoke.json)
retains Current light/dark and standard/increased comparisons, no unresolved opaque floors,
Warm's separate path and [visible derived text/fill](../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-current-9f2ba72a/runtime-native-accent-text-visible-actual-window.png).
The [isolated mathematical smoke](../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/native-accent-math-smoke.json)
passed eight accent families across four appearances, qualifying-seed identity and explicit
impossible-ratio handling. Other seed families were mathematical inputs, not changes to the
user's system accent. The twelve permanent native design/contrast tests pass in the
[current complete canonical run](../../../evidence/2026-11-06-memoshi-phase0-d7fad15e/canonical-native-lint-repaired-859191f4/run.json),
including actual native opaque-surface and on-fill resolution. The
[earlier containing run](../../../evidence/2026-11-04-memoshi-phase0-awlu2ul0/canonical-final-1da07a50/ci.log)
failed in separate filesystem fixtures and remains retained. The eight opt-in native
performance workloads were unrun, not qualified.
Rendered glass/icon/focus contrast, physical/reference budgets and user adoption remain
separate; this closes those two source gaps, not P0-13's entire acceptance.

## 7. Phase 0 reference/reuse assessment v0

The [2026-11-04 assessment](../research/2026-11-04-phase0-design-reference-assessment.md) completes P0-19's **assessment**: personal-resource, delegation, project/workbench-review and App/version journeys; Mac/iPhone/iPad routes; idle, streaming, approval, error, offline, hidden and accessibility states; bounded Kuvo coupling/native fit; exact provenance/notices; and original-art requirements. It carries the existing native records within their original scope and distinguishes current Phase 0 delivery from later accepted phases.

Its selective-reuse matrix cites Kuvo `ddd492b30d52a5553e2ad6f4785dbf05507c7adc`. Diff-folding value logic is a bounded candidate, not an adopted import. The wider picker, highlighting, file, terminal and controller closures are not portable presentation-only modules. No code, art, frontend fork, dependency, token number or runtime authority was imported or selected by the assessment; D91's personal/noncommercial permission does not clear public/commercial or GPL-linked mobile redistribution.

The assessment's [scenario review/adoption ledger](../research/2026-11-04-phase0-design-reference-assessment.md#9-user-review-and-adoption-decisions-still-required) remains open to the user. Filing v0 does not certify those reviews, original-art completion, native accessibility/iPad coverage, any performance budget, a `slice-N` or Phase 0 closure.

**2026-11-13:** [D106](../plan/decisions.md#d106) makes this section's no-import outcome the rule for interface code and names Cognitio as the lead reference; see [Direction from 2026-11-13](#direction-2026-11-13).

