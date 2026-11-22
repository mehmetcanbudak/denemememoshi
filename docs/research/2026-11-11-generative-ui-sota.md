# Generative UI on Apple platforms: the top five state-of-the-art approaches (2026-11-11)

**Status:** Research · 2026-11-11
**Owns:** A ranked survey of ways Memoshi's bots could generate what the user sees on Mac, iPhone and iPad: native UI from structured output, interpreted Swift, generated shaders and motion, 3D and Gaussian splats, and generated images, video and worlds. Each pick has a 1–3 day experiment with pass/fail thresholds.
**Depends on:** [Python and native generative UI](2026-10-22-python-and-native-generative-ui.md) (prior pass; this note covers only what changed or was not covered) · [decisions](../plan/decisions.md): D53 (JSON cards), D67 (personal use), D68/D71/D72 (Swift engine), D80 (MLX model on device) · [cards spec](../specs/cards.md) · [03 §9.9 shader effects](../plan/03-design-system.md#shader-effects)
**Evidence:** four slice reports with per-candidate tables, latency tables and every source URL, in [`2026-11-11-generative-ui-sota/`](2026-11-11-generative-ui-sota/): [A protocols and structured output](2026-11-11-generative-ui-sota/a-protocols-and-structured-output.md) · [B code, shaders and motion](2026-11-11-generative-ui-sota/b-code-shaders-and-motion.md) · [C images, video and worlds](2026-11-11-generative-ui-sota/c-images-video-worlds.md) · [D 3D and Gaussian splats](2026-11-11-generative-ui-sota/d-3d-and-gaussian-splats.md).

Research is evidence, not decisions ([index](README.md)). Labels: **Observed** (read in the cited primary source), **Rechecked** (also confirmed on this machine on 2026-11-11, in the Xcode 27.2 SDK or through `gh api`), **Claim** (a vendor's or author's figure we did not reproduce), **[INFERENCE]** (our reasoning). Reference devices are D80's: iPhone 14 Pro (A16, 6 GB, no Apple Intelligence), iPad Pro M1 (8 GB) and an Apple-silicon Mac.

## 1. The ranking

| # | Approach | What the bot generates | Runs on all three reference devices? | Status in the plan |
|---|---|---|---|---|
| 1 | **Catalog-constrained native UI, streamed** | Structured output (JSON or a compact DSL) constrained token by token to the card catalog, streamed into SwiftUI | Yes: MLX on the iPhone, MLX or the system model elsewhere | Extends accepted D53 |
| 2 | **Interpreted Swift live cards and mini apps** | SwiftUI-style Swift run by an in-app interpreter with real SwiftUI state | Yes; generation quality decides which model writes it | Accepted D68; a new public reference implementation exists |
| 3 | **Generated GPU visuals and motion** | Metal shaders (templates with parameters, or free-form source compiled on device), particles and keyframe motion as data | Yes | Not planned for generated content (only design-pass chrome, 03 §9.9) |
| 4 | **Native 3D and Gaussian splats** | Scene specs turned into USD, and splat assets generated from photos or prompts | Rendering yes (gated on device test); generation tiered by device | Not in the plan |
| 5 | **Generated images, video and worlds** | Card art on device; real-time restyled video and worlds from the cloud | Images on the Mac and iPad; the iPhone needs the cloud or an older model | Not in the plan |

**Why this order** [INFERENCE]: the ranking weighs how much each approach changes what a bot can show, against whether it runs on the reference devices today without JIT or child processes. Picks 1 and 2 are the generative UI proper and already have accepted decisions, so the experiments de-risk planned work. Pick 3 is cheap and visually striking. Pick 4 got a first-party Apple renderer this year. Pick 5 lost its Apple API and is cloud-bound for real time.

## 2. What changed since the last pass (2026-10-22)

| Change | Why it matters | Label |
|---|---|---|
| iOS/macOS 27 add a public Foundation Models **`LanguageModel` protocol**. `MLXLanguageModel` in `mlx-swift-lm` ≥ 3.32.3 conforms to it, with `MLXGuidedGeneration` (vendored XGrammar: JSON Schema, EBNF) | Qwen3 on the A16 phone can use the same `@Generable` / `PartiallyGenerated` streaming path as Apple's system model, with hard structural guarantees | Rechecked (`public protocol LanguageModel` in the iPhoneOS 27.2 SDK; `MLXFoundationModels`, `MLXGuidedGeneration`, `MLXCXGrammar` in the repo) |
| **A2UI v1.0** is "Current" (2026-11-06), and Google ships an **official A2UI Swift SDK 0.10.0** (Apache-2.0, iOS 17+/macOS 14+, alpha). Breaking spec changes still landed on 11-03 and 11-11 | D53's "A2UI-style" wire format can align with a first-party, conformance-tested renderer | Rechecked (`swift/core`, `swift/swiftui` in `a2ui-project/a2ui`) |
| **A2UI Express** (2026-10-27): a compact Python-like inference format compiled to A2UI JSON; "up to 3x fewer tokens", "up to 3x lower latency" | At phone decode speeds, output tokens set card latency | Claim (Google) |
| **Kiln** 0.2.x (MIT, 2026-10-27): runs SwiftUI apps from a string; each interpreted `View` is hosted by a real SwiftUI view that owns its `@State`; headless `Kiln.validate` | The closest public analogue to D68 | Rechecked (MIT, 0.2.1 published 2026-10-27) |
| **`ImageCreator` is discontinued** in iOS/iPadOS/macOS/visionOS 27; Apple points to the Image Playground sheet "or another image generation service of your choice" | Bots cannot generate images headlessly through Apple anymore | Rechecked ([Apple developer news, 2026-06-11](https://developer.apple.com/news/?id=dz9wvq0r)) |
| RealityKit **`GaussianSplatComponent`** and the new **USDKit** framework are in the 27 SDKs | A first-party splat renderer and a Swift USD authoring API | Rechecked (`public struct GaussianSplatComponent` in RealityFoundation; `USDKit.framework` in the iPhoneOS 27.2 SDK) |

## 3. Pick 1: catalog-constrained native UI, streamed

**What.** The bot's model is constrained at every decoding step to the card catalog, so its output always parses and validates. The output streams as cumulative snapshots into native SwiftUI blocks that appear as they are generated.

**Stack.**
- `LanguageModelSession` with `MLXLanguageModel` (iPhone, iPad, Mac) or `SystemLanguageModel` (Apple Intelligence devices); `ClaudeLanguageModel` and Firebase's Gemini conformer exist for cloud models (Observed, [slice A §2.1](2026-11-11-generative-ui-sota/a-protocols-and-structured-output.md#21-foundation-models-guided-generation--languagemodel-protocol-iosmacos-27)).
- The D53 catalog compiled at run time to a `DynamicGenerationSchema`, or to an EBNF grammar for a compact DSL.
- `PartiallyGenerated` snapshots keyed in `ForEach` by `GenerationID`, which Apple guarantees "present and stable" for a response; layout-defining fields first, because properties are generated in declaration order (Observed).
- The wire format aligned with A2UI v1.0 (flat adjacency list, `root`, `@path` data bindings, placeholders for unresolved references), using `A2UISwiftCore` as validator and state engine behind Memoshi's own block views (Observed; the SDK says targets "can depend on `A2UISwiftCore` and `BasicCatalog` alone").

**Evidence.**

| Fact | Number | Label |
|---|---|---|
| Unconstrained small models on catalog-bound UI (OpenUI benchmark) | LFM 2.5 2.6B 3.3% valid; Granite 4.1 8B 14.7%; Ministral 8B 27.2%; frontier models up to 99.5% | Observed, first-party Thesys benchmark |
| Output tokens per screen, same benchmark | A2UI JSON 2,823 mean; OpenUI Lang 1,362 | Observed, first-party |
| Template-first ("decision model") screens | Tree on screen in 92–298 ms, complete in 0.8–1.7 s over 11 prompts | Claim (Google blog; small sample) |
| Cold grammar compile in MLXGuidedGeneration | "can block for hundreds of milliseconds"; prewarm off the main actor | Observed (README) |
| Qwen3 decode speed on the A16 | No primary source; ~15–20 tok/s for 1.7B is a secondary figure | Unmeasured |

**Why first.** Small on-device models produce invalid UI almost every time without constraints, and constraints are the only evidence-backed fix [INFERENCE from the benchmark]. This turns D80's phone model into a usable card author and keeps D53's rule that a card is data.

**Risks.** Constrained output is valid but can be ugly. A2UI v1.0 is still taking breaking changes, so pin a commit. The system model's 8,192-token context cannot hold a full ~26-block schema, so prune per request. A16 throughput is unmeasured.

**Experiments** (details and thresholds in slice A):
- **A-E2, constrained vs unconstrained Qwen3 on the A16** (2 days). 50 card prompts × Qwen3 1.7B/4B × {prompt only, schema-constrained} on the iPhone 14 Pro and iPad M1. **Pass:** 100% structural validity, ≥ 90% judged sensible, mask overhead ≤ 15% tok/s, peak memory ≤ 3.2 GB on the iPhone.
- **A-E4, Swift-call card DSL vs JSON** (2 days). An EBNF for `Card(Column([Text($title)]))`-style calls, parsed by D68's SwiftSyntax front end and lowered to D53 JSON. **Pass:** ≥ 2x fewer tokens and ≥ 1.8x faster at equal validity, with no quality loss in a blind A/B.
- **A-E5, template-first cards** (1 day). A `@Generable enum` picks one of six templates, the skeleton renders at once and slot text streams in. **Pass:** skeleton ≤ 600 ms and complete ≤ 4 s on the iPhone 14 Pro.

## 4. Pick 2: interpreted Swift live cards and mini apps

**What.** D68 as accepted: bots write SwiftUI-style Swift, Memoshi compiles it to bytecode and interprets it without JIT, and native components draw it. What is new is public evidence that the approach ships, and a reference to measure against.

**Reference implementations** (Observed, [slice B §2](2026-11-11-generative-ui-sota/b-code-shaders-and-motion.md#2-runtime-swiftswiftui-execution)):

| Project | Relevance to D68 | License / state |
|---|---|---|
| **Kiln** (haplollc) | Each interpreted `View` is hosted by a real SwiftUI view, so `@State` follows SwiftUI's identity rules. ~120 modifiers, Charts, navigation. `Kiln.validate(source, ticks: 8, fuel: 2_000_000)` runs every view and fires every action headless. A native-vs-interpreted UI-test lab matches 6/6 apps. Used in production in Haplo AI's chat "Run" button | MIT, 0.2.1, 2026-10-27; no published latency numbers |
| **Lantern** (alldritt) | D68's exact architecture: SwiftSyntax → optimizer → bytecode → stack VM, with a debugger and a SwiftUI bridge | MIT; dormant since 2026-04-07 |
| **SwiftScript** (Cocoanetics) | No SwiftUI, but bridges generated from symbol graphs and 48 "LLM probe" scripts usable as a conformance corpus | MIT, 0.1.0 |
| **Patch** + WasmKit 0.4.x | Real `swiftc` → WASM compiled on a Mac, run in WasmKit (fuel metering since 0.4.1), rendered from an IR in native SwiftUI | MIT; Mac-in-the-loop compile |

**Evidence on generation quality.** No neutral SwiftUI leaderboard exists. SWE-Bench Mobile's best agent configuration solves 12% of industrial iOS tasks; SwiftEval shows small models drop sharply on Swift-specific features (Observed). [INFERENCE] Qwen3 1.7B/4B should write cards in the constrained form of pick 1; free-form Swift goes to the Mac's model or a cloud model, with a validate-then-repair loop.

**Experiments:**
- **B-E1, Kiln bake-off** (2 days). Embed Kiln 0.2.1 in a scratch app; 40 cards in the D68 subset (20 from a frontier model, 20 from Qwen3-4B). **Pass:** p95 first frame ≤ 50 ms for ≤ 200-line cards, ≤ 15 MB per card, validate pass ≥ 85% (frontier) and ≥ 50% (Qwen3-4B after one repair round). The result is the bar D68 must meet or beat.
- **B-E2, native-vs-interpreted diff harness** (1 day). One XCUITest drives the same card compiled natively and interpreted, with a screenshot diff per step: the D68 conformance method.

## 5. Pick 3: generated GPU visuals and motion

**What.** Three tiers, from safest to most expressive:
1. **Data-described motion:** `KeyframeAnimator`, `PhaseAnimator`, `symbolEffect`, `MeshGradient` parameters, and RealityKit's `ParticleEmitterComponent`, which is `Codable` (iOS 18+), so a bot can emit a particle effect as JSON (Observed).
2. **Shader templates with parameters:** `[[stitchable]]` shaders compiled into the app and used through SwiftUI's `colorEffect`/`distortionEffect`/`layerEffect`; the model picks a template, uniforms and a palette. No compilation at run time.
3. **Free-form Metal source:** `MTLDevice.makeLibrary(source:options:)` is public on iOS 8+ and visionOS 1+, and App Store apps (Shaderific, Shader Playground, Graphica Playground) compile MSL on iPhone and iPad today (Observed). That this is outside the no-JIT rule is [INFERENCE]: Apple does not document the mechanism.

**Constraints** (Observed, slice B §3):
- SwiftUI's `ShaderLibrary(url:)` and `(data:)` take only precompiled metallibs. A source-compiled library renders through an `MTKView`, or the Mac compiles a metallib with `xcrun metal` and syncs it.
- A hung shader surfaces as `MTLCommandBufferError.timeout`. Slice B proposes a guard: cap loops statically, compile off the main thread, render one offscreen probe frame, show the shader only if the probe passes, and blacklist its hash on timeout.
- ShaderMatch finds that even top models fail to produce working shader code in 31% of cases. Graphica Playground reports Apple's PCC model writes shader maths "far better than the on-device model" and keeps offline templates as a fallback (Claim, vendor).
- No cold-compile latency measurement exists anywhere found.

**Plan conflicts.** [03 §9.9](../plan/03-design-system.md#shader-effects) says shaders "ship in the `DesignSystem` package and compile at build time" and never run over model text. Those rules are written for design-pass chrome; generated shaders in cards would need their own decision. Tiers 1–2 fit D53 as new blocks.

**Experiments:**
- **B-E4, Codable particles and motion blocks** (1–2 days). Recover the particle schema by encoding Apple's presets; Qwen3-1.7B on the iPhone writes 20 effects. **Pass:** ≥ 90% decode, ≥ 70% judged to match the request, ≥ 60 fps, ≤ 3 s to generate.
- **B-E3, runtime shader feasibility** (2–3 days). Cold-compile 30 salted shaders on the three devices, measure compile success by model with one repair round, and run a hostile infinite-loop shader through the guard. **Pass:** cold compile p95 ≤ 300 ms on the A16; the hostile shader yields an error without terminating the app; ≥ 60% compile-and-render for Qwen3-4B after one repair. **Fail** means template-only.

## 6. Pick 4: native 3D and Gaussian splats

**Rendering.**
- **RealityKit `GaussianSplatComponent`** (Rechecked in the iPhoneOS 27.2 SDK). It needs an Apple7 GPU (A14/M1 or newer), so all three reference devices qualify [INFERENCE]. It loads no files: the app parses PLY/SPZ/USD and fills `LowLevelBuffer`s, and because buffers are referenced, writing to them animates the splats. Thermal mitigation is the app's job (Observed, Apple docs).
- **Caveat:** the iOS 27 and macOS 27 release notes still say the API "will be available in an upcoming release"; only visionOS 27 is unambiguous. A community probe of beta 1 found a cap of ~200k splats per resource (Observed, [slice D §1](2026-11-11-generative-ui-sota/d-3d-and-gaussian-splats.md#1-native-apple-splat-support--the-explicit-answer)).
- **USDKit** (iOS/macOS 27): author a `USDStage` from Swift and render it live with `USDStageComponent`. OpenUSD now has a Gaussian-splat prim. This gives an all-native path from a bot's JSON scene spec to a `RealityView`, with no ML model on the phone.
- **Fallback:** MetalSplatter 1.0.1 (MIT, iOS 18+, PLY/SPZ/.splat, fixed loading of Apple SHARP output); ~400–450k splats at 90 fps on Vision Pro in a community test (Observed). SceneKit is deprecated as of 26 (Observed).

**Generation, tiered by device:**

| Tier | Model / service | Speed | License | Note |
|---|---|---|---|---|
| On device | Apple **SHARP** (one photo → ~1.18M metric Gaussians) via a community Core ML conversion | ~1.9 s on an M4 Max | Model: **research-only** ("does not include … product development") | Unmeasured on the A16; decimate to the RealityKit cap |
| On device (capture) | **PocketGS** training from ARKit captures | ~4 min, < 3 GB peak, 52 fps render on an iPhone 15 (same A16) | Paper | Research code; shows the A16 can train splats |
| Mac | Speridlabs **Idol** (object image → 3D Gaussians, including unseen sides), MLX port | 126 s, 9.49 GB peak on an M3 Ultra | Apache-2.0 (gated DINOv3/FLUX.2 VAE dependencies) | Python on the Mac; new since 2026-10-22 |
| Cloud | World Labs **Marble** API (text/image/video → world) | Latency not published | $0.12 (draft) – $2.48 per world | Exports SPZ at 100k/500k, which fits RealityKit's budget |
| Cloud | **Tripo** v3 image → splat; mesh → USDZ | ~4 min | $0.30 per splat | |

**Experiments:**
- **D-E1, RealityKit splats go/no-go** (1–2 days). A `RealityView` card loads 100k/200k/500k-splat assets on the three devices. **Pass:** ≥ 200k splats at ≥ 55 fps on the iPhone with memory < 600 MB, and ≥ 1M at 60 fps on the Mac. **Fail** (init throws below 100k, or the API is inert on iOS 27.x) means MetalSplatter (D-E2).
- **D-E6, LLM scene spec → USD card** (2 days). A 10-primitive JSON schema (box, sphere, text, image plane, light, camera, group, transform, splat reference…) written by Qwen3-4B, validated, built with USDKit and rendered with `USDStageComponent`. **Pass:** ≥ 90% valid, ≤ 1.5 s from JSON to first frame on the iPhone, 60 fps at ≤ 50 primitives.
- **D-E4, photo → 3D on device** (2 days). SHARP Core ML as a bot tool on the iPad M1 and iPhone 14 Pro. **Pass:** ≤ 10 s on the iPad, ≤ 20 s on the iPhone, peak < 3 GB. Record a licence decision before any use beyond the user's own devices.

## 7. Pick 5: generated images, video and worlds

**Apple no longer offers a bot-callable image API.** `ImageCreator` stops working in the 27 releases; Image Playground is now a user-opened sheet backed by a Private Cloud Compute model, and is unavailable on the iPhone 14 Pro (Rechecked; Observed, WWDC26 session 375). It can still be a user-initiated "Illustrate" action on the Mac and iPad.

**Card art on device.** MLX Swift, the runtime D80 already brings, runs 4-step distilled DiTs in process:

| Model | Hardware | Time | Label |
|---|---|---|---|
| Bonsai ternary FLUX.2 Klein 4B (Apache-2.0, 3.88 GB) | M4 Pro Mac | 5.78 s at 512², 24.3 s at 1024² | Claim (model card) |
| Same | iPhone 17 Pro Max (A19 Pro) | 9.4 s at 512² | Claim (model card) |
| FLUX.2 Klein 4B, mflux | M2 Pro Mac | 42–52 s at 1024²; 4-bit is *slower* than bf16 on M1/M2 | Observed (issue thread) |
| SD 2.1, Core ML on the Neural Engine | iPhone 14 Pro Max (A16) | 7.9 s at 512², 20 steps | Observed (Apple repo) |

[INFERENCE] The iPad M1 and the Mac can generate 512² card backgrounds in roughly 5–25 s if the LLM is unloaded first. The iPhone 14 Pro's realistic on-device path is a few-step distilled Stable Diffusion on the Neural Engine, or the cloud. Generate small decorative assets only, never text-bearing UI, and cache by a hash of model, prompt, seed and size. Draw Things is the fastest Mac engine but is GPL-3.0, so it could only be a separate local server.

**Real time is cloud-only on these devices.**
- **Decart** has an official Swift SDK (MIT, LiveKit WebRTC, iOS and macOS). Lucy 2's real-time preview ran 720p at 20 fps; Lucy 2.6 shipped in October; pricing is $0.01–0.04 per second (Observed). A "living card" would feed a SwiftUI card rendered to frames and show the restyled stream.
- **fal**'s FLUX.2 Klein real-time endpoint takes JPEG frames over a plain WebSocket; OpenAI streams partial images over SSE (Observed).
- **World models** are not reachable from Swift: Genie 4 (announced 2026-10-27) is trusted-tester only; Odyssey offers JavaScript and Python SDKs; World Labs' Frameboy is a 15 fps browser demo; Matrix-Game 4.0 needs NVIDIA (Observed). [INFERENCE] For Memoshi, a generated "world" is better delivered as a 3D asset rendered natively (pick 4).

**Experiments:**
- **C-3.1, MLX image service** (2–3 days). An actor on `mlx-swift` loading Bonsai ternary Klein 4B, generating 512² card backgrounds with the LLM unloaded. **Pass:** ≤ 10 s on the Mac, ≤ 20 s on the iPad M1, and on the iPhone 14 Pro either ≤ 45 s or a clean refusal from a memory pre-check; no jetsam; thermal state ≤ `.fair` on the iPad after 10 images.
- **C-4.1, Decart living card** (1–2 days). **Pass:** first frame ≤ 2 s and ≥ 15 fps for 60 s on the iPhone 14 Pro over Wi-Fi, battery drain ≤ 2% per minute.

## 8. Considered and ranked lower

| Item | Why lower | Slice |
|---|---|---|
| MCP Apps / OpenAI Apps SDK | HTML only, so a sandboxed `WKWebView` tier; against D53's no-HTML rule for bot output. Useful later for third-party apps. ext-apps v2.1.0 shipped 2026-11-10 | A |
| AG-UI 1.0 | Only a community Swift SDK, which targets the pre-1.0 contract. At most an internal event vocabulary for subagents and interrupts | A |
| Gemini dynamic view | Generates HTML/JS per prompt; the quality bar, not a catalog-bound pattern | A |
| Rive / Lottie generation | Rive's agent CLI and Lottie generators (OmniLottie needs a 15 GB GPU) run off device; runtimes are fine for imported assets | B |
| Mac `swiftc` + `dlopen` | Full fidelity but Mac-only and needs library-validation exceptions; useful as a reference oracle for the interpreter | B |
| TRELLIS.2, SAM 3D, Hunyuan3D | 34–72 GB for the Swift-MLX TRELLIS.2 port; SAM's custom licence; Hunyuan's open weights exclude the EU/UK/Korea | D |
| Spark / Radix splats in `WKWebView` | Best level-of-detail streaming, but non-native; only if pick 4's native renderers fail for multi-million-splat worlds | D |
| Local real-time video (FastMetal-QAD, Krea Realtime MLX) | ~45 s for a 5 s 480p clip on an M4 Max: not real time | C |

## 9. Suggested experiment order

Each step can stop the line after it. Steps 1–3 de-risk accepted decisions; steps 4–6 explore new capabilities.

1. **A-E2** constrained Qwen3 on the A16: decides whether the phone's model can author cards at all.
2. **B-E1** Kiln bake-off: sets the D68 performance and validity bar.
3. **A-E4** Swift-call card DSL: decides the card authoring format and whether cards and mini apps share one parser.
4. **D-E1** RealityKit splats go/no-go, then **D-E6** scene spec → USD.
5. **B-E4** Codable particles and motion blocks, then **B-E3** runtime shaders.
6. **C-3.1** MLX card art on the Mac and iPad.

## 10. What this changes in the plan

Nothing by itself. Adopting any of it goes through [change control](../plan/decisions.md#change-control). The candidates for a decision are:
- D53: align the wire format with A2UI v1.0 (the [cards spec's open question 2](../specs/cards.md#open-questions)) and add constrained decoding as the card tool's generation path on device;
- D68: adopt the Kiln-style hosting model and validate-then-repair loop, with B-E1's numbers as a gate;
- new card blocks for motion, particles and shader templates; generated free-form shaders would need an exception to 03 §9.9's build-time rule;
- 3D, splat and image generation tools, none of which the feature catalog has today.

## 11. Notes on sources

- Every URL behind this summary is in the slice reports. Vendor and benchmark-owner figures are marked Claim or "first-party" there; secondary sources are labelled.
- No latency on the iPhone 14 Pro comes from a primary source for MLX decoding, RealityKit splats, Kiln or SHARP. Each experiment above measures it first.
- One third-party WWDC summary site fetched during research (wwdc.ai) contained instructions addressed to AI agents; they were ignored, and facts taken from it are corroborated in Apple's own documentation or marked as such in slice B.
