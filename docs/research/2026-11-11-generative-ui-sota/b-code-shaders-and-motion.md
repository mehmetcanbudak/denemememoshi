# GenUI slice B — runtime-generated native code & visuals on Apple platforms (SOTA as of 2026-11-11)

Scope: Swift/SwiftUI code generated and executed at runtime, hot reload and agentic dev loops, runtime Metal shader generation, generated vector/animation/particle formats, and how well LLMs generate SwiftUI.
Labels: **Obs** means I read it in the cited primary source in this session. **[INF]** means my inference. Repo metadata (stars, dates, license) comes from the GitHub REST API, fetched 2026-11-11.
Memoshi constraints applied: D53 (A2UI-style JSON cards over a ~25-block catalog), D68 (own SwiftSyntax→bytecode interpreter), D80 (MLX Qwen3 1.7B/4B on device), no JIT, iPhone 14 Pro (A16, 6 GB, **no Apple Intelligence**), iPad Pro M1, Apple-silicon Mac.

---

## 0. TL;DR

| # | Finding | Label |
|---|---|---|
| 1 | **Runtime MSL compilation on iOS is allowed and needs no JIT entitlement.** `MTLDevice.makeLibrary(source:options:)` is public API on iOS 8.0+/iPadOS/visionOS 1.0+. Apple's docs describe building a library "directly from source code by passing it as a string". Shipping App Store apps compile user-written or LLM-written MSL on iPhone/iPad today: Shaderific (since 2021), Shader Playground, and Graphica Playground. | Obs (sources §3.1) |
| 2 | **SwiftUI `ShaderLibrary(url:)` / `(data:)` accept only *precompiled* metallibs.** No documented iOS API turns a source-compiled `MTLLibrary` into metallib bytes. So generated shaders go either (a) into an `MTKView`/`CAMetalLayer` surface hosted in SwiftUI, or (b) through a Mac-side `xcrun metal` precompile, with the metallib synced to iOS and passed to `ShaderLibrary(data:)`. | Obs (API docs); "no API" is [INF] |
| 3 | **New entrant: Kiln** (haplollc, MIT). Engine 2 shipped as v0.2.0/0.2.1 on **2026-10-27**: it runs full SwiftUI apps from a string, and each interpreted `View` is hosted by a real SwiftUI view that owns its `@State`. It has `Kiln.validate` (headless: evaluate every view, fire every action) and a native-vs-interpreted UI-test lab where 6/6 apps match. It is the closest public analogue to D68. | Obs |
| 4 | **Other interpreters:** SwiftScript (Cocoanetics, MIT, v0.1.0 on 2026-10-08) is a swift-syntax tree-walker with no SwiftUI. Lantern (alldritt, MIT) is SwiftSyntax→optimizer→bytecode→VM with a debugger and a SwiftUI bridge, i.e. D68's exact architecture, but dormant since 2026-04-07. | Obs |
| 5 | **Patch** (patch-swift, MIT) serializes SwiftUI bodies into a mirror IR. Body logic runs as Swift-compiled WASM in **WasmKit** (MIT; v0.4.1 added fuel metering, v0.4.2 on 2026-10-11), and native SwiftUI renders the tree. Across their corpus, 82.5% of view nodes lower to the IR. The compile must happen off-device: Xcode's Swift cannot target wasm. | Obs |
| 6 | **SwiftUI codegen quality:** I found no authoritative public SwiftUI leaderboard. The evidence: SWE-Bench Mobile (Feb 2026) best agent config scores **12%** on industrial iOS tasks. SwiftEval shows small models drop sharply on Swift-specific features. A vendor test (n=5 per category) puts basic UI at ~90% first-pass compile and Metal/ARKit/Core ML at ~15%. | Obs |
| 7 | **Shader quality:** ShaderMatch (LLM4Code 2025) finds even top models fail to produce working GLSL in **31%** of cases. Graphica Playground (iOS 26/27) says Apple's PCC model "writes shader maths far better than the on-device model", and it keeps offline templates as a fallback. | Obs |
| 8 | **Data-described motion is solid:** `ParticleEmitterComponent` is **Codable** (iOS 18+/macOS 15+/visionOS 1+). Rive now ships an agent CLI with a text format (RML), but runtimes refuse unsigned scripts. Lottie generation (OmniLottie 4B, CVPR 2026; LottieGPT) is GPU-server-class only. | Obs |
| 9 | **Dev loop:** Xcode 26.3+ has agentic coding. Xcode 27 adds simulator driving, debugger/build-settings MCP tools, SwiftUI "Specialist" agent skills exportable via `xcrun agent skills export`, and resize handles in Live Previews. `xcrun mcpbridge` connects Claude Code/Codex. InjectionNext 2.0.2RC5 (2026-11-10) supports hot reload on device. | Obs |

---

## 1. What changed since 2026-10-22 (the prior repo research)

| Item | Change | Date | Source |
|---|---|---|---|
| Kiln 0.2.0 → 0.2.1 | Engine 2 is now the default. Real struct/class/enum semantics, real SwiftUI state, Charts, networking, `Kiln.validate`, markdown→source helpers, seeded RNG. 0.2.1 adds gradient `foregroundStyle` on Text and a 550-line chess example. | 2026-10-27 | https://github.com/haplollc/Kiln/releases (Obs) |
| OpenSwiftUI 0.25.0 | Adds Stepper, SF Symbols effect/transition APIs, gradients. Interface coverage vs iOS 18.5 is 50.12% (SwiftUI+SwiftUICore), per the 0.24.3 notes. | 2026-11-01 | https://github.com/OpenSwiftUIProject/OpenSwiftUI/releases (Obs) |
| ElementaryUI 0.9.0/0.9.1 | Keyed `ForEach(id:)`, SSR/SSG `.render()`. Minimum macOS 26. Web/DOM target only. | 2026-10-30 / 11-11 | https://github.com/elementary-swift/elementary-ui/releases (Obs) |
| WasmKit 0.4.2 | Wasm 3.0 spec tests, multi-memory, GC type decode, faster threaded loop. 0.4.1 (09-29) added **fuel metering** and hardening against untrusted modules. | 2026-10-11 | https://github.com/swiftwasm/WasmKit/releases (Obs) |
| InjectionNext 2.0.2RC5 | Maintenance RC. 2.0.1+ bundles an MCP server for screenshots and touch record/replay. | 2026-11-10 | https://github.com/johnno1962/InjectionNext (Obs) |
| rive-ios 6.29.0 | Legacy API deprecated in favour of the Swift Concurrency API. Renderer selection removed (always the Rive Renderer). GPU scripts can draw into the render target. | 2026-10-30 | https://community.rive.app/c/announcements/rive-runtime-updates-november-3-2026 (Obs) |
| Graphica Playground 1.4–1.5.1 | Text→Metal shader app. "Studio engine" (iOS 27) uses Apple PCC. | 10-17 → ~11-08 | https://apps.apple.com/my/app/graphica-playground/id6810975699 (Obs) |
| ShadAR (arXiv 2610.19998) | GPT-5.2 generates pixel shaders at runtime and injects them into the AR passthrough feed. 21-user study. | 2026-10-14 | https://arxiv.org/abs/2610.19998 (Obs) |
| Tokamak | Still dormant. Last push 2024-03-23, last release 0.11.1 (2022). | — | GitHub API (Obs) |
| Interswift / Ronith | No new public release found in my searches. The absence is unverified beyond search. | — | [INF] |

---

## 2. Runtime Swift/SwiftUI execution

### 2.1 Candidate table

| Candidate | What it is | Maturity / date | Apple path | License | Fit for Memoshi |
|---|---|---|---|---|---|
| **Kiln** (haplollc) | Swift/SwiftUI interpreter. Own lexer and recursive-descent parser (no SwiftSyntax), tree evaluation. Each interpreted `View` is hosted by a real SwiftUI view that owns `@State`. About 120 modifiers; List/Form/NavigationStack/TabView/sheets/Charts/Shape/Path/GeometryReader; `@Observable`/`ObservableObject`; URLSession+Decodable. Step budget and call-depth limit, so "runaway loops… never hang the app". | 25★, v0.2.1 2026-10-27, last push 2026-11-06. Used in production in Haplo AI's chat "Run" button. | SPM, iOS 17+/macOS 14+, Swift 5.9+. `Kiln.run(code) -> KilnResult(view: AnyView?)`, `KilnView(code:)`, `Kiln.validate(code, ticks: 8, fuel: 2_000_000)` | MIT | **Highest.** Same product shape as D68 "live cards/mini apps", and the validator design is the piece to copy. Risks: tiny bus factor. Tree-walking, not bytecode (perf unmeasured). No UIViewRepresentable, SwiftData, user property wrappers or result builders. `Task.sleep` doesn't wait. Protocol conformance unchecked. |
| **Lantern** (alldritt) | SwiftSyntax 600 → AST → optimizer (constant folding, CSE, DCE, strength reduction) → bytecode → stack VM. Host bridge registry. **Debugger** (breakpoints, stepping, inspection). `LanternSwiftUI` view bridge. IDE helpers (completion, token classifier). Conformance fixtures, including `19_swiftui_views.swift`. | 3★, 142 commits, created 2026-04-02, **last push 2026-04-07** (dormant) | SPM, iOS 18+/macOS 15+, Swift 6.0 | MIT | Architecture reference for D68: bytecode, optimizer passes, debugger, bridge-registration API. Not a dependency candidate (dormant, pinned to SwiftSyntax 600). |
| **SwiftScript** (Cocoanetics) | swift-syntax-based async tree-walker. About 220 auto-generated Foundation bridge files from symbol graphs. 410+ tests. 48 "LLM probe" scripts with expected outputs. Explicitly rejects `@propertyWrapper`/`@resultBuilder`/macros. **No SwiftUI.** | 75★, v0.1.0 2026-10-08 | SPM; Mac/iOS/Linux/Windows | MIT | Two things to reuse for D68's non-UI logic: the bridge-generator approach (symbol graph → allow-list → bridges) and the LLM-probe corpus as a conformance suite. |
| **Patch (patch-swift) + WasmKit** | Real `swiftc` → WASM (stdlib ~5.3 MB; Foundation ~57 MB; Embedded Swift ~11 KB; best case 23.9 KB → 8.8 KB brotli). Runs in WasmKit (pure-Swift interpreter, no JIT). A mirror-DSL `PatchView` builds an IR; the native side renders real SwiftUI. Elm-style loop with event tokens. 82.5% of view nodes lower to the IR; Canvas, continuous gestures and UIViewRepresentable stay native. | patch-swift 34★ (created 2026-06, push 2026-09-17). WasmKit 523★, 0.4.2. | Compile on Mac with a swift.org toolchain + WASM SDK (Xcode's Swift can't target wasm). Run on iOS via WasmKit (SPM). | MIT / MIT | Medium. The **full Swift language**, not a subset, but Mac-in-the-loop compile; no on-device generation-to-run. Sensible "promote a mini-app" path when a bot-built app outgrows the subset. Interaction-rate tree rebuilds only; per-frame work must stay native. |
| **OpenSwiftUI** | Open-source reimplementation of SwiftUI (macOS/iOS/Linux/Android/WASI). | 2,534★, 0.25.0 2026-11-01 | SPM/binary | MIT | Low for runtime genUI: it doesn't interpret source. Useful only as reference for SwiftUI semantics and layout. |
| **ElementaryUI / Tokamak** | SwiftUI-like DSL for the browser DOM via wasm. | ElementaryUI 618★, 0.9.1. Tokamak dormant. | Web only; would need WKWebView | Apache-2.0 | Not native. Skip unless Memoshi accepts a web surface. |
| **JSON→View libs** (A2UI, json-render, DynamicSwiftUI-style) | Covered by the prior research and by slice GenUIProtocols. | — | — | — | D53 stays the safe default. Interpreters sit above it for "mini apps". |
| **Mac-only real compile + dlopen** [INF] | On macOS, Memoshi (not sandboxed, Xcode installed) could run `swiftc -emit-library` on generated SwiftUI and `dlopen` the result. That's the InjectionNext mechanism. Hardened runtime requires `com.apple.security.cs.disable-library-validation` to load dylibs not signed by the same Team ID. | Mechanism Obs (entitlement doc); Memoshi applicability [INF] | macOS 10.7+ entitlement | n/a | Mac-only, gives full fidelity. Impossible on iOS (no compiler, no unsigned code). Useful as a **reference oracle**: run a card natively on the Mac and diff it against interpreter output (Kiln Lab does exactly this). |

Sources: Kiln https://github.com/haplollc/Kiln + STATUS.md https://raw.githubusercontent.com/haplollc/Kiln/main/STATUS.md · Lantern https://github.com/alldritt/Lantern · SwiftScript https://github.com/Cocoanetics/SwiftScript · Patch https://patchrelease.com/blog/swiftui-over-the-wire , https://patchrelease.com/blog/swift-to-webassembly , https://patchrelease.com/blog/wasmkit-webassembly-runtime-swift · entitlement https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation (all Obs).

### 2.2 Kiln: details worth stealing for D68 (Obs, README/STATUS)
- **Hosting model.** "Every `View` struct you write is hosted by a real SwiftUI view, so `@State` lives and dies by SwiftUI's own identity rules." This sidesteps re-implementing state lifetime. For D68 the analogue is one generic `InterpretedView` host struct per interpreted view instance, keyed by the interpreted type and structural identity. [INF]
- **Validation.** `Kiln.validate(source, ticks: 8, fuel: 2_000_000)` "evaluates every view and fires every action once, headless". Errors carry line numbers. This is a cheap pre-display gate for LLM output and a repair-loop signal.
- **LLM ergonomics.** `swiftSource(fromMarkdown:)` merges multi-block replies, and a later block that redeclares a type replaces it. `swiftSource(running:inReply:)` takes only the blocks needed. `looksLikeApp` picks full-height presentation.
- **Conformance method.** Kiln Lab is an iOS app that runs each example natively *and* interpreted under the same XCUITest and diffs the screens. Progress went from 0/5 matching apps to 6/6, and from 1/4 to 5/5 Apple Intelligence replies that run.
- **Limits.** No UIKit/AppKit bridges, SwiftData, packages, user property wrappers or result builders. Async runs straight through.
- **iOS 27 SDK note.** `@State` became a macro in the 2026 SwiftUI, and `ContentBuilder` unifies builders (https://wwdc.ai/2026/269, Obs). Interpreters that parse attributes syntactically are unaffected. D68's SwiftSyntax must track the Swift 6.4 grammar; swift-syntax 604.0.0 exists, per WasmKit's dependabot bump (Obs). [INF]

### 2.3 Measured numbers available
| Metric | Value | Source | Caveat |
|---|---|---|---|
| Kiln latency/memory | **Not published.** `Tools/KilnBench` exists but no numbers are in the README/STATUS. | Obs (absence) | Must measure (E1) |
| Patch tree-rebuild cost | "interaction-rate rebuilds haven't shown up on a profile, though we owe a numbers post" | Obs | No numbers |
| Swift→WASM size | 5.3 MB / 57 MB / 11 KB (stdlib / Foundation / Embedded) | Obs, Swift 6.3 release builds | Their pipeline only |
| WasmKit speed | "wrong tool for a database engine or a render loop" | Obs (Patch) | Qualitative |

### 2.4 Experiments
**E1. Kiln bake-off vs D68 prototype (2 days).** Embed Kiln 0.2.1 in a scratch iOS app. Build a 40-card corpus: 20 cards written by a frontier model and 20 by Qwen3-4B-MLX on the Mac, all within the D68 subset. Run on iPhone 14 Pro and iPad M1.
- Measure: `Kiln.validate` pass rate; parse+first-frame latency p50/p95 (signposts); resident memory delta per card; scroll hitch rate with 10 live cards in a `LazyVStack` (Instruments Hitches).
- Pass: p95 first frame ≤ 50 ms for ≤ 200-line cards; ≤ 15 MB per card; hitch ratio < 5 ms/s; validate pass ≥ 85% (frontier) and ≥ 50% (Qwen3-4B, after 1 repair round fed by validate errors).
- Output: a conformance corpus and per-feature gap list that D68 must beat or match.

**E2. Native-vs-interpreted diff harness (1 day).** Copy the Kiln Lab idea for D68: one XCUITest drives the same card compiled natively and interpreted, with a screenshot diff per step. Pass: ≥ 95% label match on 10 reference cards.

---

## 3. Runtime Metal shader generation

### 3.1 Answer: is runtime MSL compilation allowed on iOS without the JIT entitlement? **Yes.**

| Evidence | Label | Source |
|---|---|---|
| `makeLibrary(source:options:)`: "Synchronously creates a Metal library instance by compiling the functions in a source string." Platforms: iOS 8.0+, iPadOS 8.0+, Mac Catalyst 13.1+, macOS 10.11+, visionOS 1.0+. The source "may only import the Metal default library". An async variant `makeLibrary(source:options:completionHandler:)` also exists. | Obs | https://developer.apple.com/documentation/metal/mtldevice/makelibrary(source:options:) (via mirror https://apple-docs.everest.mt/docs/metal/mtldevice/makelibrary(source:options:)) |
| "The device can also create a library directly from source code by passing it as a string to the `makeLibrary(source:options:)` method." | Obs | https://developer.apple.com/documentation/metal/shader-libraries |
| WWDC21: compile to AIR "either by using Xcode's Metal toolchain… or by compiling from source by using newLibraryWithSource API at runtime". The session also covers function stitching to avoid source-string compilation. | Obs | https://developer.apple.com/videos/play/wwdc2021/10229 (transcript at https://nonstrict.eu/wwdcindex/wwdc2021/10229/) |
| Shipping on-device MSL compilation in App Store apps for iPhone/iPad: Shaderific ("compile them on your iPad", on the App Store since July 2021); Shader Playground ("Write Metal fragment shaders… 60 FPS", iOS 17.6+); Graphica Playground ("compiled and checked on your device's GPU"; exports "runtime-compiled Metal source with an MTKView renderer"). | Obs | https://shaderific.app/ · https://apps.apple.com/us/app/shader-playground/id6767094702 · https://apps.apple.com/my/app/graphica-playground/id6810975699 |
| Why the JIT rule doesn't apply: the no-JIT restriction is about CPU writable+executable memory. MSL compiles to GPU code handled by the Metal compiler and driver, not to executable pages in the app. | **[INF]** (Apple doesn't document the mechanism) | — |

**Consequences for Memoshi.**
- **(a) Rendering path.** A source-compiled `MTLLibrary` works with Metal pipelines in an `MTKView`/`CAMetalLayer`, wrapped in `UIViewRepresentable`/`NSViewRepresentable`. Obs (API).
- **(b) SwiftUI `ShaderLibrary`.** `init(url:)`/`init(data:)` require "the contents of precompiled Metal library" (iOS 17+/macOS 14+/visionOS 1+). https://developer.apple.com/documentation/swiftui/shaderlibrary (Obs via https://sosumi.ai/documentation/swiftui/shaderlibrary). Options:
  - **(b1)** The Mac compiles with `xcrun -sdk iphoneos metal -c x.metal -o x.ir && xcrun -sdk iphoneos metallib x.ir -o x.metallib` and syncs the bytes to iOS for `ShaderLibrary(data:)`. The commands appear in https://forums.developer.apple.com/forums/thread/774771 and https://uvolchyk.medium.com/baking-metal-shaders-with-vapor-and-swiftui-4def70b44d06 (search snippets, Obs).
  - **(b2) Untested.** `MTLDynamicLibrary.serialize(to:)` exists (WWDC21, Obs), but whether SwiftUI accepts that file as a `ShaderLibrary` is unknown. [INF] Test it in E3.
- **(c) Prewarming.** `Shader.compile(as:)` (iOS 18+/macOS 15+/visionOS 2+) compiles asynchronously to avoid a first-use stall. Obs: https://developer.apple.com/documentation/swiftui/shader/compile(as:)

### 3.2 Metal 4 changes relevant to generated shaders (Obs: https://developer.apple.com/documentation/metal/using-the-metal-4-compilation-api)
- `MTL4Compiler` gives a dedicated compiler instance with QoS dispatch queues, progress and status monitoring, and harvesting into binary archives via `MTL4PipelineDataSetSerializer`.
- Apple warns that compile duration is "unpredictable" at runtime, and that "iOS conserves energy and memory by applying limitations to background compilation threads". Compile generated shaders on a `.userInitiated` queue, never on the main actor. [INF]
- Unspecialized → specialized pipelines save recompiles when only formats vary. Function stitching (`MTLFunctionStitchingGraph`, iOS 15+) builds functions from a DAG of precompiled `[[stitchable]]` nodes and "completely skip[s] the Metal frontend". This is the **safe "shader-as-data"** route: the model emits a node graph, not MSL.

### 3.3 Compile latency: what is actually measured
| Measurement | Value | Hardware | Source | Caveat |
|---|---|---|---|---|
| 10,000 × `makeLibrary(source:)` of the same ~80-line shader | 269.49 ms total (~27 µs/call) | iPhone (unspecified), 2021 | https://qiita.com/TokyoYoshida/items/e86fd9ca0c6c4fcfe5cb (Obs) | Obviously hit Metal's source cache. **Cold first-compile cost is not measured anywhere I found.** |
| Rive Android Vulkan first `render()` | 143 ms → ≤ 0.1 ms on main thread after moving to background | Galaxy S23 | Rive Nov-2026 notes (Obs) | Not Apple. Shows shader warm-up dominates first frame. |

→ Measuring cold compile is part of experiment E3.

### 3.4 LLM shader quality
| Source | Finding | Label |
|---|---|---|
| ShaderMatch (Kels et al., LLM4Code@ICSE 2025): 467 Shadertoy GLSL function completions, 20+ open code models | "even top models fail to generate working code in 31% of cases" | Obs (abstract), https://www.computer.org/csdl/proceedings-article/llm4code/2025/261500a096/27ueqWQohVK |
| ShaderBench (shaderlab.ai) | 5,600+ GLSL shaders from 28 models, gallery and voting. Methodology is paywalled ("coming soon"). | Obs, https://www.shaderbench.xyz/benchmark (low evidentiary value) |
| AI Co-Artist (arXiv 2512.08951) | GPT-4 evolves GLSL. Shaders are compile-checked before entering the population. | Obs, https://arxiv.org/abs/2512.08951 |
| ShadAR (arXiv 2610.19998, 2026-10-14) | Runtime GPT-5.2 pixel-shader generation and injection in AR | Obs |
| Graphica Playground | On-device Apple FM generation with auto repair/replace of "broken or blank output". Offline templates "so generation never comes back empty". iOS 27 "Studio engine": PCC model "writes shader maths far better than the on-device model". Sliders tune uniforms **without re-running the AI**. | Obs (vendor App Store text) |
| Vendor SwiftUI test (Rork, n=5/category, spring 2026) | Metal-category features: ~15% first-pass compile, ~60% on-device crash | Obs, https://rorklab.net/en/articles/rork-ai/rork-max-swiftui-native-generation-30-features-benchmark (weak evidence) |
| Memoshi implication | Qwen3 1.7B/4B writing raw MSL will fail often. Use **parameterized templates** (model picks template + uniforms + palette) or a **small expression DSL / stitching graph**. Reserve free-form MSL for frontier/PCC/Mac-hosted models plus a compile-repair loop. | [INF] |

### 3.5 Safety: GPU hangs and watchdogs
- `MTLCommandBufferError.Code.timeout`: "the system interrupted and terminated the command buffer… commands in the buffer took more time to run than the system allows". Obs: https://developer.apple.com/documentation/metal/mtlcommandbuffererror-swift.struct/code/timeout
- Guardrails [INF]:
  1. Static lint before compile: reject `while`, and cap `for` bounds to constants ≤ N by AST/regex rewrite.
  2. Compile off the main thread with a wall-clock budget.
  3. **Probe render**: one 256×256 frame into an offscreen texture in its own command buffer. Check `status`/`error` and GPU time (`gpuEndTime - gpuStartTime`), plus a non-blank/variance check (Graphica's "blank output" detection).
  4. Promote to an on-screen `MTKView` or SwiftUI `layerEffect` only after the probe passes.
  5. Kill switch: on `.timeout`, blacklist the shader hash.
- Don't apply unprobed generated shaders directly as SwiftUI `.colorEffect`/`.layerEffect`. They run in the app's own render pass, so a hang stalls UI frames. [INF]

### 3.6 Candidate table (shaders)
| Candidate | Apple path | On-device? | License | Fit / risks |
|---|---|---|---|---|
| **Free-form MSL → `makeLibrary(source:)` → MTKView** | Metal, iOS 8+. Async compile or MTL4Compiler (iOS 26+). | Yes (compile). Model may be on device or remote. | Apple API | High visual payoff. Small-model quality is the risk. Needs the probe guard. |
| **Template + uniforms (`[[stitchable]]` shaders shipped in the app's default library)** | SwiftUI `ShaderLibrary.default`, `.colorEffect/.distortionEffect/.layerEffect`, iOS 17+ | Fully, no compile at runtime | Own code | **Safest.** A D53 card block `shader{template, uniforms, palette}`. Model only picks parameters, which Qwen3-1.7B can do. [INF] |
| **Function stitching graph** | `MTLStitchedLibraryDescriptor`, iOS 15+ | Yes, skips the MSL frontend | Apple API | "Shader-as-data". The JSON graph can be validated. More engineering; SwiftUI integration is unclear [INF]. |
| **Mac-precompiled metallib → `ShaderLibrary(data:)`** | `xcrun metal`/`metallib` on Mac. SwiftUI on iOS. | Compile on Mac | Apple tools | Lets free-form shaders reach SwiftUI-native effects on iPhone. Needs Mac online/sync. |

### 3.7 Experiment
**E3. Runtime-shader feasibility and latency (2–3 days).** Build a scratch app (iOS 27 + macOS 27).
1. Cold compile: compile 30 generated stitchable fragment shaders with `makeLibrary(source:)`, each with a unique salt comment to defeat the cache. Measure cold-compile p50/p95 on iPhone 14 Pro, iPad M1 and Mac.
2. Compile success rate by model (Qwen3-1.7B, Qwen3-4B, frontier), with one repair round fed by compiler errors.
3. Hostile shader: run an infinite loop through the probe guard. Record whether the app survives, and the error code.
4. SwiftUI path: test `ShaderLibrary(url:)` with a serialized `MTLDynamicLibrary`, and `ShaderLibrary(data:)` with a Mac-built metallib.

Pass criteria:
- Cold compile p95 ≤ 300 ms on A16 [INF threshold].
- Compile+render pass ≥ 90% for frontier and ≥ 60% for Qwen3-4B, after 1 repair.
- Hostile shader yields `.timeout`/an error, with no app termination and the UI recovering within 2 s.
- Full-screen shader holds ≥ 120 fps on iPad M1 for ≥ 80% of passing shaders.
- Fail if every one of these holds: the iPhone can't recover from the hang, cold compile is > 1 s, and Qwen3-4B is < 40%. In that case fall back to template + uniforms only.

---

## 4. Generated vector, animation and particle formats

| Candidate | What / status | Apple path | On-device generation? | License | Fit |
|---|---|---|---|---|---|
| **Rive** (RML + CLI + rive-ios) | The agent writes **RML** (plain-text XML-like `.rml`). The `rive` CLI verifies, previews, renders frames headless, and builds `.riv`. There is a built-in Editor AI agent. Scripts are "AnimaScript" (TS syntax → WASM, sandboxed), and "runtimes refuse any script that isn't signed". rive-ios 6.29.0 (2026-10-30). Perf (M-series, release): 10-entry UI update 2.68 → 0.112 ms. | rive-ios SPM; Swift Concurrency API | **No.** The CLI runs on macOS/Linux/Windows, and scripts must be signed by Rive publishing. Mac-side agent authoring → `.riv` → iOS is feasible. | Runtimes MIT. CLI/editor proprietary. A free-plan splash screen is being introduced (X post). | Medium. Great designer-grade motion, but generation happens off-device and there's vendor-account coupling for scripts. https://rive.app/agents , https://rive.app/docs/cli/overview , https://x.com/rive_app/status/2098199130778857914 (Obs) |
| **Lottie** (lottie-ios + generators) | lottie-ios 4.6.1 (2026-06-13). Generators: OmniLottie (CVPR 2026, 4B VLM; weights 8.46 GB; **15.2 GB GPU memory, 8.34 s per 256 Lottie tokens**; Apache-2.0 code); LottieGPT (arXiv 2604.11792; Qwen-VL fine-tune; claims SOTA on SVG too); agent skills diffusionstudio/lottie (MIT) and kin3o (licence not checked). | lottie-ios SPM (Apache-2.0); `LottieView` in SwiftUI | **Not on device** at useful quality. A frontier model plus a skill can write Lottie JSON, but it's verbose. | Apache-2.0 runtime | Low–medium. Good for importing assets; a poor target for a 1.7B/4B model. https://github.com/OpenVGLab/OmniLottie , https://arxiv.org/abs/2604.11792 , https://github.com/diffusionstudio/lottie (Obs) |
| **SVG path → SwiftUI `Shape`** | nicklockwood/SVGPath (MIT) parses path strings at runtime. Static converters (svg-to-swiftui) work at build time. LLM SVG skill is tracked by SVG-Bench / SArena / svgbench.ai leaderboards. | SPM; `Path`/`Shape` | Yes (parsing). Generation quality depends on the model. | MIT | Medium. Make "icon/illustration" a D53 block holding `d=` strings with bounded complexity. https://github.com/nicklockwood/SVGPath , https://arxiv.org/html/2510.11341 (Obs) |
| **RealityKit `ParticleEmitterComponent` as JSON** | Conforms to **Encodable/Decodable** (iOS 18+, macOS 15+, tvOS 26+, visionOS 1+). Has Presets, shape, speed, burst and spawn parameters. | `JSONDecoder().decode(ParticleEmitterComponent.self…)`, then a `RealityView` entity | **Yes.** The model edits parameters, not code. | Apple API | **High** for "magic/celebration" effects and visionOS. The schema is Apple's encoding, so learn it by encoding presets. https://developer.apple.com/documentation/realitykit/particleemittercomponent (Obs) |
| **SwiftUI native motion as data** (`KeyframeAnimator`, `PhaseAnimator`, `symbolEffect`, `MeshGradient`, `Canvas` + `TimelineView`) | Mature system APIs. | iOS 17/18+ | Yes, as D53 parameter blocks | Apple API | **High.** Small-model friendly, zero code-exec risk. [INF] I didn't re-read these API docs in this session. |
| **Core Animation `CAEmitterLayer` / SF Symbols custom** | CAEmitter properties are plain data. I found no runtime API to register custom SF Symbols from SVG; custom symbols need asset-catalog templates. | QuartzCore / asset catalog | Emitter yes; custom symbols no | Apple | Emitter fine on Mac/iOS 2D. Custom symbols are out for runtime. [INF] |

**E4. Codable particles and motion blocks (1–2 days).**
1. Encode 8 `ParticleEmitterComponent.Presets` to JSON to recover the schema.
2. Prompt Qwen3-1.7B (MLX, iPhone 14 Pro) with the schema plus 3 examples for 20 effect requests.
3. Decode, render in a `RealityView` on iPhone/iPad/visionOS sim, and measure.
4. Add a `motion{keyframes:[…]}` D53 block driven by `KeyframeAnimator` and run the same test.

Pass: decode success ≥ 90%; human "matches request" ≥ 70%; steady fps ≥ 60 on iPhone 14 Pro; generation ≤ 3 s per effect.

---

## 5. Dev-loop tooling: hot reload, previews, agentic Xcode

| Tool | State (2026-11) | Relevance to Memoshi | Source |
|---|---|---|---|
| **Xcode 26.3+ agentic coding** | Released 2026-02-03. Agents (Claude Agent, Codex) explore projects, change settings, **capture SwiftUI Previews**, and iterate through builds and fixes. Providers: Claude, ChatGPT, any Agent Client Protocol or Chat-Completions endpoint. | Fast path for authoring the ~25 native catalog blocks and the D68 bridge layer, not runtime. | https://modaal.dev/claude-code-xcode (quotes Apple; Obs) |
| **Xcode 27** | Agents boot simulators, install/launch apps, synthesize touches, take screenshots. MCP tools for debugger, schemes and build settings. Plan artifacts in Markdown. Filesystem security layer. Gemini/Antigravity. Live Previews gain resize handles. **SwiftUI Specialist** and **What's New in SwiftUI** agent skills, exportable via `xcrun agent skills export`. A second MCP mode via `sudo xcrun mcp-server enable`. Xcode 27.2 RC exposes 54 tools per one report. | Exported SwiftUI skills are ready-made system-prompt material for Memoshi's bot codegen prompts (D68 subset). [INF] | https://developer.apple.com/wwdc26/guides/xcode , https://wwdc.ai/2026/269 , https://zenn.dev/mochiai/articles/43f5d1900ec604 (Obs) |
| **`xcrun mcpbridge`** | `claude mcp add --transport stdio xcode -- xcrun mcpbridge`. Requires "Allow external agents to use Xcode tools" and an open project. | Lets Pi_Swift-side or Claude Code agents build and verify catalog blocks on the dev Mac. | https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode.md , modaal (Obs) |
| **InjectionNext** | 2.0.2RC5 (2026-11-10), MIT, 443★. Simulator, **device** (opt-in network port + codesign identity) and macOS. Needs `-Xlinker -interposable` and HotSwiftUI/Inject. Function bodies only (no new stored properties or signatures). 2.0.1+ ships an MCP server (screenshots, touch record/replay). | Dev-time hot reload of the native catalog and interpreter bridges. Not a runtime genUI mechanism. | https://github.com/johnno1962/InjectionNext (Obs) |
| **Swift Playgrounds (iPad)** | Compiles on device. There is no embedding API for third-party apps. | Not usable by Memoshi. | [INF] |
| **Kiln Lab pattern** | Native-vs-interpreted UI-test diff. | Copy it for D68 conformance (E2). | Obs |

**E5. Agent-authored catalog block via mcpbridge (1 day).** Export the Xcode 27 SwiftUI skills and connect Claude Code via `xcrun mcpbridge`. Ask for 3 new D53 blocks, each with a JSON schema, Preview and snapshot test. Pass: each block builds, previews and passes its test in ≤ 20 min wall-clock with ≤ 2 human edits.

---

## 6. LLM→SwiftUI codegen quality (benchmarks, models)

| Benchmark | Scope | Key number | Label / source |
|---|---|---|---|
| SWE-Bench Mobile (arXiv 2602.09540, 2026-02-10) | 22 agent-model configs on a production iOS codebase (PRD + Figma) | Best **12%** task success. The same model varies up to 6× across agent harnesses. A "Defensive Programming" prompt gave +7.4%. | Obs https://arxiv.org/abs/2602.09540 |
| SwiftEval (MacPaw, FORGE 2025) | 28 hand-crafted Swift problems, 44 code LLMs | "significant LLM scores drop for problems requiring language-specific features, most noticeable in the models of smaller sizes" | Obs https://arxiv.org/abs/2505.24324 |
| UICoder (Apple, NAACL 2024) | SwiftUI text→UI via compiler + CLIP feedback; ~1M synthetic programs | Fine-tuned open models approach or beat proprietary baselines on compile and visual relevance (2024-era) | Obs https://machinelearning.apple.com/research/uicoder |
| Apple "Improving UI generation models from designer feedback" (CHI) | Designer comments, sketches and direct-manipulation feedback for UI generation | — | Obs (title/listing) https://machinelearning.apple.com/research/designer-feedback |
| Rork vendor test (n=5/category) | First-pass compile: basic UI ~90%, StoreKit/MapKit ~70%, HealthKit/camera ~40%, ARKit/Core ML/Metal ~15% | Directional only | Obs (weak) |
| iswift.dev "SwiftUI Codegen Accuracy Report 2026" | Vendor page; client-rendered, content not retrievable | — | Unverified |

**Best current models.** No neutral SwiftUI leaderboard exists, so I can't rank models from primary data.
- Observed: Xcode 26.x natively offers Claude and ChatGPT; Xcode 27 betas add Gemini.
- [INF] For Memoshi's on-device Qwen3 1.7B/4B, expect usable output only on **constrained subsets**: catalog JSON, or a Kiln/D68-subset with the validator in the loop. Free-form SwiftUI and MSL should go to a larger model (Mac-hosted MLX, frontier API, or Foundation Models `PrivateCloudComputeLanguageModel` with its 32K context).
- PCC availability on the A16 iPhone (no Apple Intelligence) is unverified; the PCC API needs an entitlement (Obs: https://wwdc.ai/2026/241).

**E6. Subset-codegen eval (2 days).** Use 50 card prompts, each run through D68-subset Swift and through D53 JSON, on Qwen3-1.7B, Qwen3-4B and one frontier model. Score with Kiln.validate/D68-validate, then a screenshot judge.

Pass for shipping on-device codegen:
- Qwen3-4B valid+faithful ≥ 70% after 1 repair, with p95 generation ≤ 8 s on the M1 iPad.

Otherwise:
- Qwen3-4B emits D53 JSON only.
- Swift-subset generation is routed to the Mac or a remote model.

---

## 7. Cross-cutting risk table

| Risk | Affects | Mitigation |
|---|---|---|
| Interpreter perf on A16 (tree-walking) | Kiln-like D68 | Bytecode (Lantern-style passes). Per-card step/fuel budgets (Kiln fuel 2M; WasmKit fuel metering). Keep per-frame work native (Patch's rule). |
| Generated code breaking state identity | Interpreters, IR | Host each interpreted View in a real SwiftUI view (Kiln). Stable explicit IDs in `ForEach`; Patch's first list update "tore down every row" until it had them. |
| GPU hang from generated shader | MSL path | Static loop caps, offscreen probe, `.timeout` handling, hash blacklist (§3.5) |
| Small-model codegen quality | All codegen | Templates + params, DSL/stitching graphs, validator-repair loop, route to bigger models |
| Vendor lock / account coupling | Rive scripts, Lottie gen services | Use Rive only for Mac-authored assets; keep Lottie as import-only |
| App Review (future) | Downloaded/interpreted code | Not binding now. Patch's policy write-up: https://patchrelease.com/blog/what-apple-allows-ota-updates (not read here) |

---

## 8. Ranked shortlist (slice B)

1. **Interpreted Swift-subset live cards hosted by real SwiftUI views, with a headless validate→repair loop.** This is D68, using Kiln 0.2.x as the reference implementation and benchmark, Lantern for bytecode/debugger design, and SwiftScript's LLM-probe corpus for conformance. It is the only approach here that gives bots *behaviour* (state, logic, navigation) on iPhone without JIT. Kiln shows it is shippable, with 6/6 native-parity apps as of 2026-10-27.
2. **Runtime-generated Metal visuals: template+uniform shader blocks by default, free-form MSL compiled on device (`makeLibrary(source:)`) behind a probe and timeout guard.** It is allowed on iOS and proven in App Store apps. It is cheap, visually striking, and works without Apple Intelligence on A16. Free-form shaders reach SwiftUI-native effects only via a Mac-precompiled metallib.
3. **Data-described native motion and particles as D53 blocks: `KeyframeAnimator`/`PhaseAnimator`/`symbolEffect`/`MeshGradient` plus Codable `ParticleEmitterComponent`; Lottie/Rive as Mac-authored imports.** No code execution at all, small-model friendly, and it runs on visionOS as a bonus. Rive RML and Lottie generators are real, but they generate off-device.

Honourable mentions:
- **Patch-style Swift→WASM (WasmKit) + SwiftUI IR**: full Swift with a Mac compile step; a "promote a mini-app" path.
- **Xcode 27 mcpbridge + exported SwiftUI agent skills**: dev loop and prompt material.
- **InjectionNext**: dev-time hot reload, including on device.
