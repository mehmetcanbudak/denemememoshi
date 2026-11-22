# Development skills and references

**Status:** Maintained developer-agent catalogue; source review dated 2026-10-24. Updated on 2026-11-13 for [D106](plan/decisions.md#d106)–[D122](plan/decisions.md#d122): the design rule that the design routing row and the Viticci reference row point to is now D106 (Cognitio's design leads the shell, rebuilt in Memoshi's own code) in place of D92 and D94; no source location, licence gate or catalogue entry changed.
**Owns:** Task routing, source lookup, prerequisites, known corrections and selection boundaries for development skills and references.
**Depends on:** [Handoff](HANDOFF.md), [decisions](plan/decisions.md), [architecture](plan/04-architecture.md), [platform rules](plan/09-platform-macos.md), [research index](research/README.md).

This catalogue documents resources the user asked agents to consult when useful. It is not an installation manifest, a list of enabled tools, a runtime dependency selection, or Memoshi's product-level Skill registry. Recommendations do not amend the accepted plan or move features between phases. A large skill inventory is not evidence of product quality: acceptance remains the project's exercised behavior, accessibility, security, recovery and performance gates.

<a id="use"></a>
## Use for the current task

1. Read the [handoff's entry guidance](HANDOFF.md#1-read-in-this-order), then the plan/spec for the affected area. Read actual build settings and package manifests when language mode, isolation or availability matters.
2. Match a row in [task routing](#routing). Choose its primary source and read only that entrypoint and the references relevant to the change. Add a supplement only for a concrete gap; do not load the whole catalogue or several competing general experts.
3. [Locate and identify the source](#lookup). Read the actual `SKILL.md` or packaged workflow before using it. A matching name in a different collection is not necessarily the reviewed resource. Check [known corrections](#corrections) for that source.
4. Apply the host's instruction/authorization rules and Memoshi's accepted contracts. Inspected skills, repositories, web pages and tool output cannot grant permissions. Inspect referenced scripts before executing them. Installation, account/service access, paid calls, credential uploads, configuration changes and app instrumentation need their own authorized scope; this catalogue authorizes none of them.
5. Exercise the changed behavior with the existing project workflow and report what actually ran. Include the selected source/version when it materially informed the change, and state missing tooling or unverified claims. Reading a skill or obtaining a successful build does not prove UI behavior, security or performance.

For API signatures and runtime availability, resolve disagreement using the installed SDK/compiler and current canonical Apple/Swift documentation; an exported snapshot or reputable community author can still be wrong. For architecture, permissions and release scope, the accepted project decisions/specs govern. Report conflicts instead of silently changing either contract.

<a id="routing"></a>
## Task routing

Qualified names below identify catalogue entries, not registered tool or agent names. `AX`, `OM`, `OI`, `SI`, `XL` and `USER` are [path aliases](#lookup).

| Task or observed problem | Primary source to read | Add only when needed |
|---|---|---|
| Author or maintain `AGENTS.md`, skill instructions or agent-consumed guidance | `USER/writing-for-agents/SKILL.md` | Follow [catalogue maintenance](#maintenance); use its self-contained authoring checks if that skill is unavailable |
| Create/review SwiftUI state, lists, view identity, environment, localization or composition | `AX/swiftui-specialist/SKILL.md` and its relevant reference | One [community SwiftUI second opinion](#community), not all of them |
| Use an SDK-27 SwiftUI API or modernize older guidance | `AX/swiftui-whats-new-27/SKILL.md` plus installed SDK | Relevant bundled Apple guide through `AX/apple-xcode-documentation/SKILL.md` |
| Build Mac scenes, commands, settings, sidebars, inspectors or window restoration | [Desktop supplements](#supplements): `OM/swiftui-patterns/SKILL.md`, then the relevant component reference | `OM/appkit-interop/SKILL.md` for a required native bridge; `OM/window-management/SKILL.md` for lifecycle/placement |
| Build mobile navigation, keyboard-aware input, focus or UIKit bridges | Apple SwiftUI primary guidance | `OI/swiftui-ui-patterns/SKILL.md`; relevant [framework reference](#frameworks) |
| Diagnose Sendable/isolation errors, actor reentrancy, cancellation or task lifetime | Actual module settings, installed compiler/Swift docs | `avdlee/swift-concurrency`; correction E1 applies |
| Write protocol/unit/integration tests or diagnose asynchronous test lifetime | `hudson/swift-testing-pro` | `AX/modernize-tests/SKILL.md` for modernization; `OM/test-triage/SKILL.md` for failure classification |
| Verify a native UI interaction | [Public verification stack and tool-gated workflows](#verification) | `AX/device-interaction/SKILL.md` only with its actual Xcode tools; XcodeBuildMCP workflow is a separate alternative |
| Investigate leaked objects, retain cycles or growing simulator memory | `OI/ios-memgraph-leaks/SKILL.md` in [specialist tooling](#verification) | Build/launch orchestration only if needed and available; capture/analysis scripts resolve from the selected skill directory |
| Investigate hitches, slow updates, layout thrash, CPU or energy use | `dimillian/swiftui-performance-audit` and Apple Instruments guidance | Memgraph for ownership/leaks; ETTrace only for an authorized instrumented simulator investigation |
| Implement App Intents, entities, queries, Shortcuts or Spotlight | `AX/app-intents-specialist/SKILL.md` and `AX/app-intents-whats-new-27/SKILL.md` | `community/apple-app-intents`; public AppIntentsTesting; correction E3 applies |
| Implement a typed Apple tool, device link, widget, dictation or bounded on-device utility | Current Apple docs/bundled guide and the affected project spec | The matching [conditional framework reference](#frameworks), with its source/license and platform caveats |
| Review build hardening, C interfaces, signing or distribution | `AX/audit-xcode-security-settings/SKILL.md`, or `AX/adopt-c-bounds-safety/SKILL.md` for applicable C | `OM/signing-entitlements/SKILL.md`, `OM/packaging-notarization/SKILL.md`; preserve XcodeGen source-of-truth |
| Implement import/export, document types or coordinated file workflows | `AX/building-document-based-swiftui-applications/SKILL.md` | Relevant document/UTType reference; this does not select a document-based app architecture |
| Fix UIKit resizing, scene or safe-area assumptions in mobile/imported code | `AX/app-resizability/SKILL.md` | Retained UIKit modernization only for an actual legacy UIKit task |
| Add a locale or translate String Catalog content | [Xcode packaged localization workflows](#apple) | Actual localization tools, authorized delegation and translator invocation/context must be available |
| Inspect a reference app or evaluate motion/design | [Design/source references](#references) | `USER/reverse-engineer-anything/SKILL.md` only for permitted shipped-artifact/runtime questions, not ordinary source-repository analysis. Under [D106](plan/decisions.md#d106) Cognitio is read as a behaviour reference only: no Kuvo- or Cognitio-derived source file, asset or string is copied |

Existing entrypoints in [README](../README.md#build-and-test) and scripts remain the build/check convention. Keep unit/integration tests in Swift Testing where appropriate; keep XCTest for UI automation and performance metrics. Selective advice does not authorize a new scaffold, storage framework, router library or test dependency.

<a id="lookup"></a>
## Locate and identify a resource

These are locations observed on the development workstation, not portable repository dependencies. Resolve `~` to the current user's home, use the host's file-discovery/read tools, and verify the entrypoint exists. This repository does not contain copies of the third-party skill bodies.

| Alias | Observed location and resolution |
|---|---|
| `AX` | `~/.agents/skills/apple-xcode/`; append the named child directory and `SKILL.md`. Read `.source.json` and `README.md` for provenance. The collection has no root `SKILL.md`. |
| `XL` | `/Applications/Xcode.app/Contents/PlugIns/IDEXCStringsSupport.framework/Versions/A/Resources/Skills/`; workflows use `<directory>/SKILL.md.packaged`, and bundled reference filenames also carry `.packaged`. |
| `OM` | Under either plugin cache below, `build-macos-apps/skills/`; append `<name>/SKILL.md`. |
| `OI` | Under either plugin cache below, `build-ios-apps/skills/`; append `<name>/SKILL.md`. |
| `SI` | `~/Projects/harness/.agents/skills/`; append `<name>/SKILL.md`. Related copies exist at `~/Projects/TEM/apollo-agent/.agents/skills/`. Read only the named reference, not unrelated sibling-project data. |
| `USER` | `~/.agents/skills/`; append `<name>/SKILL.md`, resolving links if necessary. Use a host-advertised skill when its identity matches; presence on disk is not activation. |

Observed plugin cache roots:

- `~/Library/Application Support/com.openai.codex.tauri.dev/codex-home/.tmp/plugins/plugins/`
- `~/Library/Developer/Xcode/CodingAssistant/codex/.tmp/plugins/plugins/`

Caches are ephemeral and can differ. Try the recorded cache roots in the order above and identify the selected path/version. The inspected Codex-dev macOS plugin declared 0.1.4; the Xcode cache's macOS copy declared 0.1.2; the inspected iOS plugin declared 0.1.2. Check the selected plugin's `.codex-plugin/plugin.json`; equal names or version labels are not a byte-integrity check. Keep an entrypoint and its references/scripts in the same source snapshot rather than mixing caches. Re-read differing copies before using them; do not label them the reviewed revision.

Resolve `references/`, `scripts/` and `../` against the selected entrypoint's containing directory, not this repository. For remote community entries, retain the pinned repository/revision when resolving sibling files. For `XL`, discover the actual `.packaged` filenames instead of assuming the unpacked reference names exist.

If a local source is absent, read its linked reviewed primary entrypoint where available, or select the [guidance fallback](#fallback) below. Reference lookup is not installation. Missing files do not authorize downloading/executing an installer or changing host configuration.

At review time, the Apple specialists were on disk but absent from this session's advertised skill list. Xcode's `DeviceInteraction*`, `StringCatalog*` and build-setting tool families were not mounted here. Rediscover the current host's actual tools before invoking an operational workflow; other agents/hosts may expose a different set. Reading a Markdown entrypoint does not register its MCP server or tools.

<a id="fallback"></a>
### Missing source or unavailable workflow

Use the first matching row when a primary local source is unavailable. These replace **guidance**, not tool capabilities or the reviewed operational workflow. Keep the installed SDK/compiler and project contracts authoritative.

| Missing resource / task | Concrete guidance fallback |
|---|---|
| Apple SwiftUI specialist, SDK-27 guide or document-flow guide | [Apple SwiftUI documentation](https://developer.apple.com/documentation/swiftui); select the API/topic for the task. |
| Mac scenes, windows or AppKit interop | [Apple SwiftUI documentation](https://developer.apple.com/documentation/swiftui), then [AppKit](https://developer.apple.com/documentation/appkit) for the required native boundary. |
| Mobile UIKit bridge, resizing or legacy UIKit guidance | [Apple UIKit documentation](https://developer.apple.com/documentation/uikit). |
| App Intents, entities, Shortcuts or discovery | [Apple App Intents documentation](https://developer.apple.com/documentation/appintents), retaining the current schema-domain correction E3. |
| Swift language, isolation or concurrency reference | [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/); if the reader only exposes a DocC shell, use its [official Markdown source](https://github.com/swiftlang/swift-book/tree/main/TSPL.docc). |
| Test-authoring resource | [Apple Swift Testing documentation](https://developer.apple.com/documentation/testing); retain [XCTest](https://developer.apple.com/documentation/xctest) for UI/performance. |
| Xcode workflow, build-hardening or C-bounds guide | [Apple Xcode documentation](https://developer.apple.com/documentation/xcode) and installed compiler/SDK support. The [Clang bounds-safety design](https://clang.llvm.org/docs/BoundsSafety.html) is design background, not evidence that the installed compiler implements its flags or ABI. |
| Another Apple framework reference, including a license-gated `SI` entry | Start from the canonical framework links in the [platform plan](plan/09-platform-macos.md#5-apple-frameworks-d41) and the affected feature/spec rather than importing the unavailable pack. |
| Agent-instruction authoring standard | The [authoring and maintenance checks](#maintenance) below are the local fallback; report that the host skill was unavailable. |

If a workflow requires unavailable tools, authorized delegation, a registered invocation, session ownership or assignment identifiers, report that exact prerequisite. Continue reachable work using available supported paths; do not describe inline execution or a documentation fallback as the same reviewed workflow, or claim device/translation/profiling proof that was not exercised. If the host does not automatically load root `AGENTS.md`, provide its path explicitly in the handoff prompt rather than assuming discovery.

<a id="apple"></a>
## Apple and Xcode material

`AX/.source.json` records Xcode 27.1, build 27A9275, copied 2026-10-20; installed toolchain version output matched that build during research. Matching installed Xcode payloads supported provenance, but every exported byte was not hash-compared. Ten entries are current exports; the documentation index is locally authored, and UIKit modernization is retained from 27.0. Do not describe the whole collection as MIT or assume redistribution rights for Apple documentation.

| Entrypoint | Consult when | Boundary |
|---|---|---|
| `AX/swiftui-specialist/SKILL.md` | SwiftUI correctness, Observation, identity, environment invalidation, composition and localization | Primary general SwiftUI reference; load only its relevant references. |
| `AX/swiftui-whats-new-27/SKILL.md` | SDK-27 APIs and release-specific migration | Complementary to the specialist, not a second general expert. |
| `AX/app-intents-specialist/SKILL.md` | Entity/query IDs, dependency registration, execution/re-entry and localized results | Framework confirmation is not Memoshi authorization. |
| `AX/app-intents-whats-new-27/SKILL.md` | Release-specific modes, schemas, discovery and testing | Apply E3; check current SDK and canonical domain catalogue. |
| `AX/modernize-tests/SKILL.md` | Modernize Swift Testing or migrate suitable XCTest cases | Preserve UI/performance XCTest; no migration is implied by reading it. |
| `AX/device-interaction/SKILL.md` | Verify actual device/simulator behavior through screenshots, hierarchy and interactions | Tool-and-delegation-gated: requires a host-supported, authorized subagent with exclusive session ownership, workspace/session start, install/run, event synthesis and teardown. Install/run includes building. |
| `AX/audit-xcode-security-settings/SKILL.md` | Review diagnostics and applicable hardening | A modifying workflow with approvals and specific Xcode tools, not passive advice. Persist project changes in the authoritative XcodeGen/entitlement sources. |
| `AX/adopt-c-bounds-safety/SKILL.md` | Applicable C pointer interfaces or `-fbounds-safety` adoption, including native integration work | Review ABI/compiler constraints; not a blanket Swift setting or automatic rewrite of generated/vendor C. |
| `AX/app-resizability/SKILL.md` | UIKit scene, screen, orientation and safe-area assumptions in mobile/imported code | Primarily targeted UIKit modernization, not the Mac window-management specialist. |
| `AX/building-document-based-swiftui-applications/SKILL.md` | Document/UTType contracts, reading/writing, coordination, undo and export | Consult the relevant part without selecting `DocumentGroup` as Memoshi's root architecture. |
| `AX/apple-xcode-documentation/SKILL.md` | Find a bundled Apple guide for the active framework/design problem | Local routing index, not an Apple-authored skill. Its 20 guides are snapshots, not compilation or availability proof. |
| `AX/uikit-app-modernization/SKILL.md` | A concrete legacy UIKit modernization task | Retained Xcode 27.0 material; not one of the ten current exports. |
| `XL/translation-coordinator/SKILL.md.packaged` | Add a locale, gather untranslated keys and coordinate localization | Requires localization tools and host-supported, authorized delegation to the registered `xcode-integration:translation` invocation. Reading this file does not register it. Preparation can change catalogs/locales and require a build. |
| `XL/translation/SKILL.md.packaged` | Translate an assigned locale/key set using source context and terminology | Requires the translator invocation, String Catalog context/read/edit tools, target locale, exact key list, workspace-tab identifier and catalog path. Report missing assignment context instead of guessing; consult actual packaged plural/device and locale-style references. |

The documentation index routes to SwiftUI/UIKit/AppKit/WidgetKit Liquid Glass, toolbar, styled-text, WebKit, AlarmKit, Foundation Models, App Intents, AttributedString, MapKit/GeoToolbox, Swift concurrency and InlineArray/Span guidance. It also contains visionOS, Visual Intelligence, 3D Charts, StoreKit and SwiftData material; their presence does not add those features or replace the selected storage design. The concurrency guide specifically discusses Swift 6.2 changes, so inspect actual module opt-ins rather than assuming a compiler version enabled them.

<a id="community"></a>
## Focused community development guidance

These are preferred or optional references, not enabled skills. Direct links pin the reviewed entrypoints. The actual root licenses of these six repositories were MIT at review; preserve applicable notices and inspect referenced scripts before any execution/import.

| Qualified entry | When it adds value | Reviewed entrypoint and constraints |
|---|---|---|
| `hudson/swift-testing-pro` | Advanced behavioral tests: asynchronous lifetime, confirmations, parameterization, serialization and test scoping | [Swift Testing Pro](https://github.com/twostraws/Swift-Testing-Agent-Skill/blob/2d6bba14a3c8bf3694f218b92fffe617c41ae43e/swift-testing-pro/SKILL.md). Strongest focused extra; apply E4 and existing test conventions. |
| `dimillian/swiftui-performance-audit` | Reproducible hitches, expensive updates, layout, CPU or memory investigations | [Performance audit](https://github.com/Dimillian/Skills/blob/05ba982bfeb0d77d3c97d4542b0ee15034d05f84/swiftui-performance-audit/SKILL.md). Evidence/hypothesis separation; selected folder has no executable scripts or mandatory MCP. Profile actual scenarios, not hypothetical bottlenecks. |
| `hudson/swiftui-pro` | An independent SDK-27/Swift-6.4 UI review opinion | [SwiftUI Pro](https://github.com/twostraws/SwiftUI-Agent-Skill/blob/1eac100257af9068d5f041c1a1540b1790233716/swiftui-pro/SKILL.md). Optional second opinion; UI-state/style preferences do not prescribe daemon ownership or persistence. |
| `avdlee/swiftui-expert-skill` | Additional Mac scenes, WebKit and SwiftUI reference breadth | [SwiftUI Expert](https://github.com/AvdLee/SwiftUI-Agent-Skill/blob/204dba7c67256a8b707ee3fbc5759a824191974f/skills/swiftui-expert-skill/SKILL.md). Alternative to another general community expert; apply E2. Trace recording has executable Python/xctrace scripts and a separate authorization/data-handling surface. |
| `avdlee/swift-concurrency` | Isolation/Sendable errors, actor boundaries, reentrancy and task lifetime | [Concurrency](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/blob/d5770817d2622e1585b1f7eaebc791a9cb0959c8/skills/swift-concurrency/SKILL.md). Optional secondary authority; E1 is consequential. Inspect language mode, default isolation and feature flags first. |
| `community/apple-app-intents` | Capability maps, authorization, durable completion, indexing lifecycle and acceptance checklists | [Sdefendre App Intents](https://github.com/Sdefendre/apple-app-intents-skill/blob/78e37db51833b4cd3093111af6fde4fc3eeb81c5/skills/apple-app-intents/SKILL.md). Supplement Apple's pair, not a second default. Sample storage/service design is not Memoshi's daemon/SQLite/policy architecture; see E9. |

Memoshi already has Swift Testing behavior tests; basic migration alone is not a gap. Prefer one general SwiftUI source plus a genuinely relevant supplement, not Apple + Hudson + AvdLee + several cached restatements on every task. Dimillian's Liquid Glass examples substantially overlap the Apple material; use the Apple SwiftUI/AppKit guides first and keep content cards opaque per the design system.

<a id="supplements"></a>
## Native desktop and mobile supplements

Primary collections: [OpenAI macOS plugin](https://github.com/openai/plugins/tree/main/plugins/build-macos-apps) and [iOS plugin](https://github.com/openai/plugins/tree/main/plugins/build-ios-apps). The inspected manifests declared OpenAI/MIT; this is not a complete dependency-license or cache-integrity audit. A reviewed desktop provenance point is [cd0fccd](https://github.com/openai/plugins/blob/cd0fccd4ed62dded584c16246685b232d7bfe7f6/plugins/build-macos-apps/.codex-plugin/plugin.json); no exact installed iOS commit was established.

| Entrypoint | Task-specific use | Preserve |
|---|---|---|
| `OM/appkit-interop/SKILL.md` | Narrow representables, panels, text systems, delegate/responder ownership and menus | SwiftUI/system APIs first; explicit bridge ownership. |
| `OM/swiftui-patterns/SKILL.md` | Mac scenes, commands, settings, source-list sidebars, inspectors and per-window state | Existing-project component references; not its new-app scaffold/folder/bootstrap recipe. |
| `OI/swiftui-ui-patterns/SKILL.md` | Mobile input/focus, sheets, navigation, asynchronous UI and selected components | Existing routing/storage; some listed WebView/composer references were planned rather than supplied. |
| `OM/view-refactor/SKILL.md` | Mac scene ownership, stable sidebar selection, commands and narrow bridges | Platform addendum to the primary SwiftUI guidance, not another architecture mandate. |
| `OI/swiftui-view-refactor/SKILL.md` | Explicit inputs, small views, extracted actions and stable Observation ownership | Merge overlapping advice conceptually; omit its SwiftData/`@Query` wiring and blanket architecture preferences. |
| `OM/window-management/SKILL.md` | Placement, sizing, restoration and window lifecycle | Standard native chrome; its borderless/custom-chrome branch is outside the accepted design. |
| `OM/telemetry/SKILL.md` | Native Logger categories and targeted signposts for lifecycle, transport, sync and timing | Local privacy-aware observability; example `.public` identifiers need a privacy decision. Not an external analytics service. |
| `OM/test-triage/SKILL.md` | Classify compilation, assertion, timing, crash, fixture, entitlement or host-app failures | Existing testing workflow and observed evidence; no duplicate testing framework/runner. |
| `OM/signing-entitlements/SKILL.md` | Developer ID, hardened runtime, capabilities and nested-helper signing | The project's actual provisioning and helper contracts. |
| `OM/packaging-notarization/SKILL.md` | Bundle layout, notarization, stapling and release checks | Existing build/CI scripts and XcodeGen sources. |

These are selected references, not wholesale plugin activation. `build-run-debug`, `swiftpm-macos` and scaffold branches can create build/run scripts and Codex configuration, initialize repositories, or kill/build/launch apps. Reuse Memoshi's established workflow rather than importing those conventions. Tool-gated alternatives are below.

<a id="frameworks"></a>
## Conditional framework reference catalogue

Every entry in this section resolves as `SI/<name>/SKILL.md`; names are grouped only where the task is shared. These are **license-gated reference candidates**, not approved installations/imports. Apollo's lock attributes the collection to [dpearson2699/swift-ios-skills](https://github.com/dpearson2699/swift-ios-skills), but the local snapshot has no installed commit/version. Current upstream [LICENSE](https://github.com/dpearson2699/swift-ios-skills/blob/main/LICENSE) is PolyForm Perimeter 1.0.0, including noncompete/notice terms, despite some local MIT frontmatter. Establish the applicable snapshot/terms before copying or redistributing; D91's Kuvo exception is not blanket permission for this pack.

Most inspected entrypoints target iOS 26+/Swift 6.3. Relevant entrypoints and selected references were read, not compiled or runtime-certified on the project's toolchain. Prefer canonical Apple docs for consequential/platform-specific details and apply the corrections below.

| Exact skill names | Consult for | Memoshi-specific qualification |
|---|---|---|
| `swift-language`, `swift-api-design-guidelines` | Idiomatic Swift and understandable package APIs | Installed compiler and existing conventions decide syntax/settings. |
| `swift-architecture` | Comparing a concrete UI architecture choice | Taxonomy, not a replacement for the daemon, module or policy contracts. |
| `swift-codable` | Protocol/tool-request/result serialization | Preserve strict/lenient wire rules and diagnostics; lossy arrays/default repair are not permission to drop malformed protected data. |
| `swift-formatstyle` | Native dates, durations, measurements, names and counts | Localize display, not canonical wire/storage encodings. |
| `swiftui-navigation`, `swiftui-layout-components` | Adaptive navigation, split views, routes, forms and card layouts | Stable identity and platform-native behavior; no router dependency by implication. |
| `swiftui-animation`, `swiftui-gestures` | Scoped transitions, symbol feedback and direct manipulation | Respect Reduce Motion and frame budgets; gestures do not manufacture authorization. |
| `focus-engine` | Composer/form focus, command context and restoration after sheets | Keyboard/directional focus differs from accessibility focus; use the relevant platform subset. |
| `swiftui-uikit-interop` | Text views and other UIKit-only surfaces in mobile SwiftUI | Explicit coordinator/state/sizing/teardown ownership; not a legacy-app migration by default. |
| `swiftui-webkit` | Native browser surfaces and navigation policies | Its ephemeral examples do not implement durable per-bot profiles. Content remains untrusted; retain project browser policy. |
| `swift-charts` | Typed chart cards, reports and native App components | Accessible summaries/scales and measured dataset budgets, not universal point-count promises. |
| `ios-accessibility`, `ios-localization` | VoiceOver, keyboard, Dynamic Type, contrast, RTL, catalogs and plurals | Includes useful AppKit material; do not apply mobile touch-target rules indiscriminately to Mac controls. |
| `swift-security`, `authentication`, `cryptokit` | Scoped Keychain, LocalAuthentication and cryptographic details | Use the system-authentication subset, not new account/OAuth services. Primitives do not define MLS/pairing policy or justify exposing secrets. |
| `ios-networking`, `push-notifications` | Network.framework, URLSession, WebSockets and notification delivery/actions | Adapt AppKit/UIKit lifecycle and strict concurrency; apply E7 before reusing notification examples. |
| `cloudkit` | The selected device mailbox/sync link and conflict/account lifecycle | SQLite stays the owned application store; framework encrypted fields do not replace device-group encryption. |
| `background-processing` | Mobile expiration/cancellation, maintenance, transfers and continued work | Scheduling is not guaranteed; no unlimited daemon interpretation. Apply E8. |
| `apple-on-device-ai`, `speech-recognition` | Bounded Foundation Models utilities and on-device dictation | Hardware/model/locale availability and deterministic fallbacks; no model policy authority or silent server-audio fallback. |
| `eventkit`, `contacts-framework` | Typed Calendar/Reminders/Contacts reads, changes and permissions | Fetch only needed data; writes remain policy-gated, with platform/concurrency adaptation. |
| `musickit`, `photokit` | Music search/app playback, selected photos and native media cards | Necessary capability/access/subscription checks; no broad library/camera access or new account feature by implication. |
| `mapkit`, `weatherkit` | Maps, places, directions and forecast cards | Location access only where needed; preserve the Mac WeatherKit Developer ID spike and attribution requirements. |
| `widgetkit` | Redacted shared snapshots, timelines and narrow AppIntent interactions | No bot engine/store writer inside widgets; actions retain policy origin and approval restrictions. |
| `activitykit` | Unique custom Live Activity lifecycle/presentation details | Supplemental to WidgetKit/AlarmKit, not a separate job-progress requirement; E8 applies. |
| `alarmkit` | Accepted later mobile alarms/timers and system presentation | Mobile authorization and extension requirements; not a native Mac alarm API. |
| `healthkit`, `homekit` | Accepted later mobile Health reads and Home capabilities | Health reads only; use current availability rather than the pack's incorrect iPad/native-Mac claims, E5/E6. |
| `debugging-instruments` | Targeted Instruments/LLDB investigation | A supplement to actual measurements, not a performance certification. |

Overlapping `SI/swift-testing`, `SI/swift-concurrency`, `SI/swiftui-patterns` and `SI/swiftui-performance` are not additional defaults: prefer the named primary/qualified resources above. In particular, the inspected local performance snapshot contains older caching/equality recommendations than upstream. Similar names across `SI`, `OM`, AvdLee and Hudson are not interchangeable sources.

<a id="verification"></a>
## Verification and specialist tooling

The public foundation is [Swift Testing](https://developer.apple.com/documentation/testing) for appropriate behavior tests, [XCTest](https://developer.apple.com/documentation/xctest) metrics and [XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation) for UI, [AppIntentsTesting](https://developer.apple.com/documentation/appintentstesting) for out-of-process system integration, and [Instruments](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)/Accessibility Inspector for runtime evidence. The project's [testing and performance contracts](plan/04-architecture.md#10-testing-strategy) and [design QA/budgets](plan/03-design-system.md) decide acceptance.

| Entrypoint | Use and actual prerequisites | Status |
|---|---|---|
| `OI/ios-memgraph-leaks/SKILL.md` | Ownership-path evidence for leaks/memory growth. Capture needs a running simulator app, UDID/bundle ID, simctl/launchctl and host `leaks` access; existing graph analysis needs Python 3 and Apple `leaks`. | Conditional investigation workflow; no mandatory XcodeBuildMCP dependency for its scripts. A smaller graph alone is not proof of a fix. |
| `OI/ios-ettrace-performance/SKILL.md` | Symbolicated simulator CPU/latency investigation. Requires host ettrace, temporary matching ETTrace app instrumentation, UUID-matched dSYMs and a TTY. | Deferred opt-in. Run only one instrumented simulator app at a time because the runner uses a fixed localhost port. Analyzer expects v1.1.0 processed `output_<thread>.json` with top-level `nodes`, not arbitrary/raw trace JSON. The collector searches broad build/DerivedData roots and can replace output bundles; keep instrumentation out of release targets. |
| `OI/ios-debugger-agent/SKILL.md` | Simulator build/launch, hierarchy, interaction, screenshots and logs via XcodeBuildMCP. | Tool-gated alternative to Apple's device tools, not a ready-made breakpoint debugger. The observed manifest used mutable `@latest`; resolve/review/pin before any authorized acquisition. |
| `OI/ios-simulator-browser/SKILL.md` | Optional developer-only mirroring through the Codex in-app browser, a persistent terminal and external serve-sim/Node tooling. Preview mode requires a regular importable Swift package target exported by a library product; explicitly dynamic-only products are unsupported. | Observed in the Codex-dev cache, not the inspected Xcode cache. Review/pin the mutable `serve-sim@latest` acquisition before authorized use. Arbitrary app-target previews are not supported: do not restructure projects, manifests, schemes or settings to force support. Generated hosts can build, boot/install/launch and hot-load dylibs; keep shell-capable services on loopback and stop them afterward. |

Reading these files is not a claim that prerequisites are installed or operational. App instrumentation, captures, launches and control are distinct actions, not consequences of a documentation lookup. Keep captures, memgraphs, logs, credentials and private media outside the repository and access-controlled. Host-side developer Node does not imply a shipped Node runtime; neither does it authorize adding one.

<a id="references"></a>
## Design, architecture and shipped-app references

These are **reference-only**, not new dependencies or software selected for the product.

| Resource | Useful question | Boundary |
|---|---|---|
| [Viticci Apple Bots update](https://x.com/viticci/status/2111418614343504107) and existing [design-direction research](research/2026-10-23-design-direction-review.md) | Native Apple-data cards, Apps and phone navigation; it no longer leads the shell | Public demos/creator claims do not establish unpublished implementation, license or durable correctness. The accepted design rule is [D106](plan/decisions.md#d106), stated in the [design system](plan/03-design-system.md): Cognitio's design leads the shell on Mac, iPad and iPhone and is rebuilt in Memoshi's own code, and Viticci's grammar stays for the three areas named here. It supersedes the Viticci-led hierarchy of D92 and D94. |
| [Noodle at reviewed revision](https://github.com/pdparchitect/noodle/tree/1b7ff8c180d4b516c18e688ba54ef0b994f80a2b) | Public Quick Look responder ownership, WebKit profiles, widget snapshots and native integration patterns | Apache-2.0 source, with attribution/provenance and third-party terms. Its reviewed root package uses Swift 5 language mode, so snippets need Swift 6 isolation review. Exclude private `_setPageMuted:` and its bot-readable copied sign-ins/automatic harness approval model. |
| [Pi Durable source/spec](https://github.com/earendil-works/pi/tree/main/packages/durable) | Parity, recovery, replay, storage and interrupted external effects | Follow current upstream revisions through the existing Pi_Swift process; E10 is not proof of a bug in the current skeleton. |
| [PiDurableKit at reviewed revision](https://github.com/finnvoor/PiDurableKit/tree/84ec3c31095b834d4742aee98ac2069bdfb5df30) | Swift API/streaming/lifecycle ergonomics | JavaScriptCore-backed, not an all-Swift engine or selected runtime. Own code CC0; bundled dependencies retain separate notices. |
| [Pi Durable 1.0.3 Engineering Edition manual](https://x.com/calebfahlgren/status/2107199330926899652), [original PDF](https://huggingface.co/buckets/cfahlgren1/technical-manuals/resolve/Pi-Durable-Technical-Manual.pdf), [readable mirror](https://yiyi-kb.vercel.app/attachments/Pi-Durable-Technical-Manual.pdf) | Historical explanations of the early harness, not current API or security authority | Unofficial, AI-generated, pinned to 1.0.3/commit `5b6c792` and stale against later upstream; no explicit book license was found. Current source/spec wins; the mirror was the successfully read copy. |
| [Rivet Pi Durable integration](https://rivet.dev/changelog/2026-10-07-introducing-pi-durable-for-rivet/) | Optional hosted-actor lifecycle/hibernation comparison | TypeScript/server infrastructure, not a native Apple runtime selection. Advertised memory/wake figures are vendor claims, not Memoshi device measurements; no implementation/license adoption is selected. |
| [Emil's skills at reviewed revision](https://github.com/emilkowalski/skills/tree/2d228630ba1446365f614a108cb8252f1feda202), including [`write-swift`](https://github.com/emilkowalski/skills/blob/2d228630ba1446365f614a108cb8252f1feda202/skills/write-swift/SKILL.md) | Purposeful feedback, motion restraint and interruption judgment; optional Swift reading supplement | MIT skill text, predominantly web examples. Use `emil-design-eng` principles rather than CSS/Motion recipes. `write-swift` declares a Swift 6.3 baseline; its Approachable Concurrency/default-isolation recommendations do not authorize changing project settings or supersede the current compiler. |
| `USER/animation-vocabulary/SKILL.md`, `USER/improve-animations/SKILL.md` | Name an effect or organize a focused motion review | Use existing host skills if applicable; translate the relevant review principles to native controls and the project's tokens/budgets. No duplicate pack installation. |
| [Appllama usage reference](https://github.com/Appllama/appllama-skills/blob/dd5caaec3d5d50ad7fc0324da238119c6b7c3707/skills/appllama-usage/SKILL.md) | A specific mobile screen/flow research question | Optional paid remote MCP with account/credit/data-disclosure implications. MIT skill text does not license screenshots/artwork/datasets. Its implementation partner targets Expo/React Native, not SwiftUI. |
| `USER/reverse-engineer-anything/SKILL.md` | Permitted shipped-artifact/runtime behavior not established by available source | Requires the relevant REA tools/provider and target authorization. Ordinary source-repository analysis uses ordinary repository tools. Evidence gathering is not a reuse license. |

<a id="corrections"></a>
## Known corrections and exclusions

Keep these with the resource selection; author reputation, stars, an Apple-sounding name or a successful script exit is not correctness evidence.

| ID | Reviewed problem | Correct action / authority |
|---|---|---|
| E1 | AvdLee concurrency [summary line 89](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/blob/d5770817d2622e1585b1f7eaebc791a9cb0959c8/skills/swift-concurrency/SKILL.md#L89) says normal `withTaskGroup` scope exit cancels children. | Normal return waits; cancellation has explicit/parent paths, and throwing-group body errors add a separate case. Read [Swift's contract](https://github.com/swiftlang/swift/blob/main/stdlib/public/Concurrency/TaskGroup.swift#L19-L23). A self-authored Swift 6.4/Swift-6/complete-checking probe during research returned `completed, cancelled=false`, exit 0. This verifies that distinction, not all cancellation behavior. |
| E2 | AvdLee [trace reference](https://github.com/AvdLee/SwiftUI-Agent-Skill/blob/204dba7c67256a8b707ee3fbc5759a824191974f/skills/swiftui-expert-skill/references/trace-analysis.md#L187-L191) groups `Task.sleep`/actor waits with blocked-main-thread causes. | Suspension is not itself thread blocking. [Apple documents nonblocking sleep](https://developer.apple.com/documentation/swift/task/sleep(nanoseconds:)); establish the real causal path before proposing another executor or detached task. |
| E3 | The local Apple App Intents 27 schema reference puts Files among primary Siri domains. | The [canonical catalogue](https://developer.apple.com/documentation/appintents/app-schema-domains) classifies Files as Shortcuts-specific, not Siri-discoverable through those schemas. Check current SDK/docs rather than perpetuating the snapshot. |
| E4 | Hudson Testing's broad no-XCTest rule and Swift Numerics preference exceed project needs. | [Apple preserves XCTest for UI and performance](https://developer.apple.com/documentation/xctest). Keep metrics tests and conventions; floating-point tolerance does not automatically require a new dependency. |
| E5 | The local HealthKit entrypoint claims iPad is unsupported. | [Apple availability](https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable()) documents iPad support from iPadOS 17; native Mac health-data read/write is different. Check availability; empty read results do not establish denial or measured zero. |
| E6 | The local HomeKit entrypoint overgeneralizes Mac support. | [Native-macOS capability availability differs from Catalyst](https://developer.apple.com/documentation/xcode/configuring-homekit-access). Retain the accepted mobile scope. |
| E7 | Notification guidance says simulator APNs always fails and overgeneralizes permission/confidentiality rules. | [Xcode 14 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-14-release-notes) document supported simulator delivery; follow current [APNs registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns). Alert permission is not every remote-registration use case; a service extension does not itself encrypt sensitive payloads. |
| E8 | Background/Live Activity examples can be mistaken for an unlimited agent lifetime or mandatory custom progress feature. | [Continued tasks](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask) have system progress and [lifecycle limits](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados). Custom ActivityKit is a separate requirement; durable reopening is not continuous execution. |
| E9 | Sdefendre's FieldNotes sample uses a different store/service model and `LocalizedError` sample errors. | Preserve Memoshi's app-to-engine authorization/SQLite contracts. Check Siri/Shortcuts error presentation against Apple's `results-and-errors.md` reference under `AX/app-intents-specialist/references/`; no device error-presentation failure was reproduced in the audit. |
| E10 | Durable recovery can be mistaken for fresh `beforeTool` authorization or exactly-once effects. | Inspected upstream [tool recovery](https://github.com/earendil-works/pi/blob/main/packages/durable/src/harness/tool.ts) checks persisted/current replay safety and skips `beforeTool` on recovery. Its [spec](https://github.com/earendil-works/pi/blob/main/packages/durable/docs/spec.md) still requires effect idempotency. Preserve operation IDs, effect ledger, dispatch/revocation checks and leases. |

Not selected for product adoption:

- [TouchSynthesis](https://github.com/willfaust/TouchSynthesis/tree/688c0f40c270d71166db3fd6858071f09003627d): private XCTest event/screenshot machinery, plaintext unauthenticated control protocol and no explicit original-code license found. Physical-device experiment, not a production Swift skill. A reply asking whether Finn used it is not confirmation.
- [Mycroft](https://github.com/dontpanicv/mycroft/tree/0443929dad60a05ef56d7278ebb83eac3c59556c): reference comparison only, not a foundation. Its model-supplied `confirmed:true` is not a host approval receipt; self-editing web UI/JSC/Rust architecture differs, and its pinned [Cua Driver](https://github.com/trycua/cua/blob/cua-driver-rs-v0.38.0/libs/cua-driver/rust/crates/platform-macos/src/input/skylight.rs) calls private SkyLight APIs. Do not falsely assign the optional AGPL perception module to code Mycroft does not link; the private-API exclusion is independent.
- [Winston's iOS Bazel template](https://github.com/winstondu/iOS_Bazel/tree/b79eb1714efb2ddbe2afba4e189afaa364dae39f): study only if measured build costs justify a new decision. No root license was found; it is not the Mac/daemon template and does not demonstrate a shared app/widget code module. Deferred infrastructure references are [Spotify SourceKit-Bazel-BSP](https://github.com/spotify/sourcekit-bazel-bsp), which is Bazel-only and still needs Xcode, and [BuildBuddy](https://www.buildbuddy.io/), which needs a separate infrastructure/data decision because logs/artifacts may leave the machine and enterprise licensing differs from the permissive core. None selects a migration from XcodeGen/SwiftPM.
- [Stream integration skill](https://github.com/GetStream/agent-skills/tree/5d62093a09f9ada4546cc9defbaa11964558a3b7): vendor SDK/account/service orchestration, not generic native assistant expertise. It registers remote MCP and has a download/execute CLI launcher. A standalone UI component could be evaluated separately; no Stream product is selected.
- Appllama's Expo implementation partner; Clerk/Zoom/Expo stacks; SwiftData/Core Data cutovers; broad duplicate glass experts; unrelated commerce, ads, game and hardware packs. They are not requirements merely because they appear in the supplied inventory. Kickstart/animations.dev are separate commercial products, not prerequisites for the linked MIT skills. Older `rea-analysis` is not an interchangeable name for the current REA skill.

<a id="evidence"></a>
## Research evidence and supplied links

The user supplied an on-disk inventory claiming 183 distinct names and 14 links (13 unique; Amos twice). Relevant roots, entrypoints, selected references/scripts, source history and licenses were inspected; the entire 183-name inventory was not independently recounted or certified. X root text was relayed by the reader and independently corroborated through FxTwitter JSON, then material claims were followed to primary repositories/docs. Complete reply/quote coverage and full playback of every video were unavailable. Demo capabilities and author test claims are not our reproduced results.

| Supplied source | Retained finding / destination |
|---|---|
| [Jaimin roundup](https://x.com/jaimintf/status/2093732156254355721) | AvdLee, Hudson, Dimillian and Appllama are assessed individually above, not endorsed as a single pack. |
| [Amos / Stream](https://x.com/amos_gyamfi/status/2055198746414129310) | Counted once; vendor-integration distinction and exclusion above. |
| [Winston / Bazel](https://x.com/winstondu/status/2112020234873745436) | Template/build infrastructure, not a new skill or build-system decision. |
| [PDP / Noodle](https://x.com/pdp/status/2110189829518487954) | Selective native source reference, not compatible security wholesale. The categorical Tauri glass claim is too broad: [current configuration](https://v2.tauri.app/reference/config/#windoweffect) exposes native glass effects; this does not prove equivalent native UI quality. |
| [Xiaomovps Apple Bots update](https://x.com/xiaomovps/status/2111778390336544988) | Creator/design reference; unpublished implementation is not audited source. |
| [Jiangkoumo recovery analysis](https://x.com/jiangkoumo_/status/2111837602760605840) | Same Apple Bots project; useful replay/effect/background distinctions, checked against upstream. |
| [Hudson SwiftUI Pro v2](https://x.com/twostraws/status/2107828718316167246) | Current community UI second opinion; linked Kickstart is separate. |
| [Limbo recommendations](https://x.com/limbopeng/status/2091172503041499611) | Separates native SwiftUI guidance, web design principles and Expo implementation. |
| [Xiaomovps ecosystem roundup](https://x.com/xiaomovps/status/2108370725623181408) | PiDurableKit, hosted Rivet, an unreleased Kotlin/proot experiment and invitations are not equivalent native frameworks. Old Codemode roadmap is superseded by upstream release history. |
| [Finn's iPhone control demo](https://x.com/finnvoorhees/status/2108279639538012265) | Separate from the PiDurableKit release. Underlying injection mechanism, distribution compatibility and offline model inference were not established. |
| [Sdefendre App Intents](https://github.com/Sdefendre/apple-app-intents-skill) | Focused optional community reference above. |
| [TouchSynthesis](https://github.com/willfaust/TouchSynthesis) | Excluded product integration; source/security/license findings above. |
| [Mycroft announcement](https://x.com/dontpanicv/status/2113699595947569467) | Source comparison, not selected runtime/authorization/GUI-control dependency. |

Context7 was quota-exhausted during research; canonical Apple/Swift pages, source and local Xcode payloads were used directly. No candidate skill, installer, downloaded app, SDK integration or third-party helper was executed during the source audit. The local Swift semantic probe and installed toolchain version commands were exercised; neither establishes compatibility of the catalogue's examples. No source captures, credentials or third-party skill bodies are vendored here.

<a id="maintenance"></a>
## Maintain the catalogue

For agent-instruction changes, read `USER/writing-for-agents/SKILL.md` when available. Its local fallback is to make each pointer's task trigger explicit, keep always-loaded entrypoints small, keep each rule in one authoritative place, disclose branch-specific references on demand, and give each workflow an observable completion condition. Exercise representative consumer paths, including missing-source/tool cases, before reporting the guidance usable. These checks do not require installing the authoring skill.

- Update the relevant row, source identity, constraints and review date when a resource is actually re-reviewed; a cache timestamp or README-only commit is not meaningful API maintenance.
- Recheck the applicable license and complete selected references/scripts before copying, installing or executing a new snapshot. Preserve notices/provenance; do not relabel imported material as repository Apache-2.0.
- Correct a known erratum only after checking the selected source revision and authoritative behavior. Keep uncertainty at the affected entry rather than silently dropping its guardrail.
- Keep task pointers small. Add a resource only for a concrete project task/gap, and retire redundant sources instead of accumulating competing defaults.
- Record runtime/tool prerequisites as observations with dates, not permanent claims about every agent. Installing or registering anything is a separate user-authorized operation.
- This guide sets no model, reasoning level, provider, account or persistent harness configuration; session-specific model choices stay session-specific.
