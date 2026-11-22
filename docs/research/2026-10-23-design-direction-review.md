# Design direction recheck: Viticci's Apple-native assistant and Kuvo's workbench

**Status:** Research and discussion record · 2026-10-23
**Scope:** Reopened under [D91](../plan/decisions.md#d91); prior user intent, saved visual evidence, current-plan coverage and the choices still requiring discussion.

> **Subsequent user decisions, 2026-10-23:** [D92](../plan/decisions.md#d92) adopts the Viticci-led assistant + Kuvo-informed workbench hierarchy, replacing blanket Kuvo parity. [D93](../plan/decisions.md#d93) removes mandatory design contracting while retaining design QA, accessibility and performance gates. No fork, new layout or feature/date move is selected. The discussion below preserves the evidence and options presented **before** that choice; its references to pending visual/hiring amendments are historical, not current blockers.

**Bottom line [INFERENCE]:** The user asked for Kuvo's workspace strengths **and** Viticci's native Apple personal-assistant direction, not merely Kuvo chrome with extra features.
Much of that product behaviour is already planned. The unresolved choice is presentation: exact Kuvo parity on all shared Mac surfaces versus a coherent assistant-led design across Mac, iPhone and iPad.
This review reopens that discussion; **it does not override D43 by itself**, select a fork or make a designer hire a prerequisite.

## 1. Prior user intent, not an invented design brief

Source: the supplied conversation extract, `viticci-design-user-history.md` (session-local; timestamps below are UTC). Short exact excerpts:

| User request | Exact excerpt | Meaning for this review [INFERENCE] |
|---|---|---|
| 2026-10-20 20:15 | “kuvocode is the one I want to use as base since it also has workspace stuff and is swift” | Kuvo's workspaces and native implementation matter; source reuse is now permitted by D91, not yet selected. |
| 2026-10-20 20:15 | “and i want this general design that this federico viticci is taking” | Viticci is an explicit design reference, not just an integration checklist. |
| 2026-10-20 21:10 | “he is building almost exactly what we want to do” | Recheck the whole assistant experience, including the phone. |
| 2026-10-21 14:13 | “we want the same thing he built but in our way” | Combine the references into Memoshi rather than reproduce another app's identity. |
| 2026-10-22 17:51 | “What we wanted was to have the apps just like” | This introduces the [runtime-SwiftUI reply](https://x.com/viticci/status/2111516616601305389), followed by the Ronith and Jason Kneen examples; the request was not satisfied by describing all cards as inert JSON. |

The 21 October request also explicitly says “we like viticci's app”; the 22 October request asks for “swift generation on demand kind of idea”.
Those requests guide the discussion. They do not establish a specific home screen, tab set, avatar shape, pixel target or requirement to pay someone to supply the design.

## 2. Evidence reopened, and its actual date range

Read the outside-repository evidence `README.md` and all three folder indexes under `~/Documents/memoshi/evidence/`.
The saved Viticci timeline covers **2026-09-01 through 2026-10-21 19:14 UTC**; the app's public development record starts on 3 October, and the latest app showcase is 20 October.
Collection spans **20–22 October**: the 22 October logged-in reply/quote passes extend thread retrieval, not whole-timeline coverage through 22 or 23 October.
The mobile follow-up folder was collected on 22 October: Mario's saved timeline spans 19 September–22 October, Armin's 12–22 October and Ronith's 2 September–22 October.
The generative-UI examples discussed below were posted on 21–22 September and 15/21 October. **No fresh whole-X sweep was performed for this review.**
Coverage and missing/deleted/protected/deeper-reply limits remain those of the [full record §2](2026-10-21-viticci-full-record-sep-oct.md#2-method-and-coverage) and [media record §2](2026-10-21-viticci-apple-bots-record.md#2-method-and-coverage).

These files were actually reopened visually, not inferred from the prose. Names below are relative to the indicated evidence folder:

| Saved material reopened | Primary post | What was visible |
|---|---|---|
| `2026-10-21-viticci-apple-bots/media/ab_2108192119152140318_1_photo.jpg` and `_2_photo.jpg` | [8 Oct origin](https://x.com/viticci/status/2108192119152140318) | Phone Health/music/Shazam cards; a window with roster, transcript and Activity. |
| Same folder: `ab_2108623467965038946_1_photo.jpg` | [9 Oct timers/alarms](https://x.com/viticci/status/2108623467965038946) | Touch-worded roster and timer/alarm cards in a window, most likely iPadOS [INFERENCE]. |
| Same folder: `ab_2111418614343504107_1_photo.jpg` and `_4_photo.jpg` | [17 Oct week one](https://x.com/viticci/status/2111418614343504107) | Phone weather/music controls, navigation, versioned reminder garden, helper and browser-result cards. |
| Same folder: `ab_2112555465313853810_1_photo.jpg`, `_3_photo.jpg`, `_4_photo.jpg` | [20 Oct macOS](https://x.com/viticci/status/2112555465313853810) | Activity inspector, two bot conversations side by side, Reminders change/Undo, floating quick entry. |
| Same folder: `ab_2111581381310533775_1_video.mp4`, frames at 0.5, 3 and 9.5 seconds | [17 Oct recovery reply](https://x.com/viticci/status/2111581381310533775) | Working chat, failed system activity, then the task's Reminders result in the reopened app. |
| `2026-10-22-pi-mobile/frames/dense_ronith.jpg`, `dense_jk1.jpg`, `dense_jk2.jpg`, `sheet_armin_nativeui.jpg` | [Ronith](https://x.com/ronithhh/status/2102163666422702538), [Kneen phone](https://x.com/jasonkneen/status/2102501917674836012), [Kneen Mac](https://x.com/jasonkneen/status/2102504779746324821), [Ronacher](https://x.com/mitsuhiko/status/2110680275516854588) | Saved frame sheets: document/source-to-UI transitions, counter/weather/workout screens; separate Python debugger and Reminders-style UI. |

**Device caution:** the 8–9 October window images are not established Mac screenshots. Touch instructions, the alarm context and the development record support an iPad interpretation; an iPad app running on a Mac cannot be excluded.
The 20 October post explicitly identifies macOS. Neither window chrome nor a host label proves the hardware capturing the image or the implementation toolkit ([full record §5](2026-10-21-viticci-full-record-sep-oct.md#5-what-each-screenshot-shows-about-where-things-run)).

## 3. Observed UI patterns worth discussing

- **Bots and roster:** persistent named bots, distinctive faces, short previews/status, pinned access and a visible needs-attention destination.
  The Mac shows keyboard shortcuts beside pinned bots; the phone shows the roster after relaunch. This is people-like navigation to ongoing work, not a dashboard of model providers.
- **Chat plus resource cards:** prose sits beside structured representations of Health, music, weather, reminders, timers and alarms.
  Cards show source/type, relevant dates or freshness, object-specific actions and sometimes the acting bot. The Mac reminder card visibly records a before→after due-date change and Undo.
  The visual distinction is between a resource you can inspect or act on and a paragraph saying the task is done; the underlying write is not proven by a still.
- **Collapsed work, inspectable activity:** short elapsed-time/step-count chips keep the transcript quiet; chevrons and a separate Activity pane expose categories, durations and individual work rows.
  Both the probable iPad window and the identified macOS window show this. A stopped helper is also visible; completion is not the only represented state.
- **Mini-app snapshot, version and change request:** the phone's reminder garden has a version selector, a dated snapshot disclosure, refresh and a dedicated request-to-change field.
  Its disclosure distinguishes fetched reminder data from editing reminders. The surrounding app owns navigation/version controls; the expressive garden is content, not the assistant's entire visual system.
- **Split views and quick entry:** two separately composed bot chats are visible together in the 20 October Mac image; a compact bot-selecting send panel is also shown.
  This is stronger evidence than a claim of “split views”, but it does **not** show an iPad two-agent split or a menu bar implementation.
- **Platform-native navigation grammar:** phone bottom tabs, back/done actions, contextual menus and full-screen mini-app presentation; wide-window sidebar, inspector and keyboard paths.
  These are observed visual conventions, not proof that every control is a stock SwiftUI component or that a desktop layout should be scaled down onto a phone.

The earlier [native Apple study §5](2026-10-20-native-apple-direction.md#5-design-grammar) already identified most of this grammar; the [media record §5](2026-10-21-viticci-apple-bots-record.md#5-media) and device corrections above qualify it.

## 4. What the posts and demos do not prove

- Viticci's [“At runtime in SwiftUI” reply](https://x.com/viticci/status/2111516616601305389) is an **author claim**, not a disclosed compiler, renderer or security architecture.
  It does not prove arbitrary Swift interpretation, that every resource card is generated, or that the reminder garden is itself native rather than web content.
- Attractive controls do not prove successful playback, reliable writes/Undo, permission enforcement, accessibility, performance, or complete framework coverage.
  “20+ Apple frameworks”, background Apple Intelligence, iPad agent splits and the menu bar remain claims beyond the reopened pixels ([media record §5.5](2026-10-21-viticci-apple-bots-record.md#55-what-the-app-visibly-does-and-what-is-only-claimed)).
- The recovery recording supports a visible failure→relaunch→result sequence, not uninterrupted background operation or duplicate-effect safety ([record §5.2](2026-10-21-viticci-apple-bots-record.md#52-the-force-quit-video-observed)).
- Model names are not proof of account/sign-in arrangements; the [22 October follow-ups §2.1](2026-10-22-viticci-followups.md#21-what-viticci-shows) correct the earlier API-key assumption.
- **Do not merge distinct authors' apps:** Ronith's interpreter prototype, Kneen's Interswift and Ronacher's Python IDE are not Viticci's app or each other.
  The reopened Ronith sheet shows source and working-looking screens; the bytecode route is his explanation, and he explicitly reports incomplete coverage. Interswift's archived source establishes that its rich Weather/Workout demos are precompiled host components, not general SwiftUI interpretation ([generative UI study §3–§4](2026-10-22-python-and-native-generative-ui.md#3-roniths-swift-interpreter)).
  Ronacher's Reminders-style Python screen is not proof of integration with Apple's Reminders database ([same study §2.2](2026-10-22-python-and-native-generative-ui.md#22-what-the-video-and-photos-show-observed)); the [follow-ups §4.5](2026-10-22-viticci-followups.md#45-native-mini-apps-roniths-swift-interpreter-checked-2026-10-22) is an earlier, narrower pass.

## 5. What Memoshi already specifies — not yet implements

| Reference pattern | Current plan coverage and limits |
|---|---|
| Assistant plus persistent team/workspaces | [02 §1](../plan/02-experience.md#1-scope-and-principles), [§4](../plan/02-experience.md#4-sidebar): Assistant-led home, bots, projects and sessions. The pinned-grid presentation waits where it conflicts with Kuvo parity. |
| Chat with native resources and generated UI | [D53](../plan/decisions.md#d53), [02 §7.20–§7.21](../plan/02-experience.md#720-apple-data-apple_data): hand-built Apple/decision cards, JSON display cards and Swift live cards. D53's original inert-JSON description is not the whole current contract. |
| Quiet work with inspectable details | [02 §5.1–§5.3](../plan/02-experience.md#51-transcript-items), [03 §8.2](../plan/03-design-system.md#82-conversation): collapsed thinking/tool groups, exact call details, duration, provenance and policy explanation. Not an identical Viticci Activity layout. |
| Versioned mini apps with change request | [D68](../plan/decisions.md#d68), [02 §10.11](../plan/02-experience.md#1011-mini-apps-and-live-cards), [03 §8.7](../plan/03-design-system.md#87-mini-app-chrome): Swift engine, versions, ChangeBox and permission boundaries. [D85](../plan/decisions.md#d85) makes Mac presentation a sheet with window/full-screen options; phone/iPad remain full screen. |
| Live resource state, not only a frozen answer | [D79](../plan/decisions.md#d79), [02 §7.20](../plan/02-experience.md#720-apple-data-apple_data): current item state, re-read before write, conflicts and unknown outcomes. Live Apple-data cards are **Drop 2**, not an already working v1.0 capability. |
| Native phone/iPad navigation | [02 §3.6](../plan/02-experience.md#36-iphone-and-ipad), [03 §1](../plan/03-design-system.md#1-decisions-in-this-doc): first-class universal app, phone tabs, adaptive iPad sidebar/inspector and system chrome, without a Kuvo parity target. |
| Quick entry and wide-window work | [02 §11.4](../plan/02-experience.md#114-menu-bar-extra) already has QuickAsk/hotkey; live typed drafts wait for Drop 2. [§3.5](../plan/02-experience.md#35-other-windows-and-sheets) allows multiple windows, **not** Viticci's two composers in one window; §1 explicitly forbids a second composer. |

[D87](../plan/decisions.md#d87) stages the core Swift mini apps on Mac in Phase 2 and phone/iPad in Phase 3; jobs/widgets/richer styling/adaptive-kit extensions are Drop 1, and live Apple resources/QuickAsk drafts are Drop 2.
Earlier research recommendations are historical input, not authority to undo those later decisions or accelerate their dates.

## 6. The actual tensions to resolve

**All shared Mac surfaces, not just coding.** [D43](../plan/decisions.md#d43) requires 100/100 parity in layout, density, materials, type, motion, navigation, interactions and behaviour wherever Kuvo and Memoshi overlap.
That constrains shared bot navigation, chat/composer and inspectors as well as project/coding surfaces. [03's backlog](../plan/03-design-system.md#design-pass-backlog) postpones competing roster/motion treatments.
Memoshi-only Assistant/Inbox/cards/mini apps and all phone/iPad surfaces have exceptions, but adding a Viticci-inspired card does not make the surrounding shared Mac shell exempt.
[D91](../plan/decisions.md#d91) permits inspecting/adapting Kuvo source; it does not settle this visual choice, select a fork or establish that frontend reuse saves work.

**Contracted help is a planning assumption, not evidence of design necessity.** [D45](../plan/decisions.md#d45) currently specifies about five contracted design days in Phase 0 and design QA before beta.
The user's reference-led direction does not imply that payment is needed before we can discuss or develop the design. Nor do these screenshots prove that a paid designer is unnecessary for every later quality gap.
[INFERENCE] Reconsider the mandatory contracting assumption explicitly: use the user's references and reviewable design reasoning as the authority, with targeted external help an option if a concrete gap warrants it. This note cancels no existing commitment and makes no new one.

## 7. Two bounded directions for discussion [INFERENCE]

| Direction | Boundary and trade-off |
|---|---|
| **A. Keep the current parity boundary.** | Kuvo remains exact on **all** shared Mac surfaces; apply the native-resource/mini-app grammar to existing exceptions and first-class phone/iPad layouts. Least decision change, but cannot promise Viticci's overall Mac presentation or his dual-composer split. |
| **B. One assistant-led Apple-native family, Kuvo-informed workbench.** | Discuss a bounded D43 amendment for shared bot navigation, transcript/composer and activity/inspection presentation; retain Kuvo's workspace/coding strengths and assess code reuse separately. Keep phone/iPad navigation platform-specific. Greater visual coherence is the goal, not a wholesale frontend replacement; exact screens and the affected parity boundary require user choice. |

**Recommendation [INFERENCE]: discuss B first.** It best fits the repeated request for Viticci's general direction while retaining Kuvo's workspace value and Memoshi's trust/recovery contracts.
Use the same existing journeys to compare A and B: a personal-resource request, bot delegation, project work and opening/changing a mini app, each considered on phone, iPad and Mac.
Do not choose a new home/tab layout, dual-chat feature, avatar geometry, visual token set or staffing requirement from these references alone. Any such adoption needs its own explicit decision and impact review.

## 8. Boundaries of this deliverable

No code, design adoption, source import, fork selection, feature/date move or new hiring commitment results from this note; D43 and D45 remain the current baseline pending amendment.
No actual Memoshi visual verification is possible yet: the [Mac](../../apps/mac/Memoshi/MemoshiApp.swift) and [mobile](../../apps/ios/MemoshiMobile/MemoshiMobileApp.swift) entry points still show only the app name and protocol version, not the planned experience. No app was run for this review.
Third-party artwork, screenshots/video, private reminders, addresses and other personal details remain outside both repositories. Reuse the **interaction principles**, not the garden illustration, bot art or exact proprietary product wording; Kuvo's separately authorized code reuse does not broaden that permission.
