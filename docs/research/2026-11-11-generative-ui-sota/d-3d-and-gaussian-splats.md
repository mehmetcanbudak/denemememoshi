# Slice D — Generated 3D & Gaussian Splatting on Apple platforms (as of 2026-11-11)

Scope: rendering and generating 3D Gaussian splats (3DGS) and meshes in a native SwiftUI app on iOS/iPadOS/macOS 27 (visionOS as a bonus), under Memoshi's constraints: on-device bots, no JIT, no child processes, A16/6 GB iPhone 14 Pro, M1 iPad Pro 8 GB, Apple-silicon Mac, personal-use distribution, permissive licenses preferred.

Labels: **Obs** = I read it in the cited primary source (or checked it in the local Xcode 27.2 SDK/macOS 27.0.1 runtime on this machine). **[INF]** = my inference. "—" = not found in primary sources.

---

## 0. TL;DR

1. **Yes, Apple now ships a first-party Gaussian-splat renderer.** `RealityKit.GaussianSplatComponent` / `GaussianSplatResource` exist in the iOS/iPadOS/macOS/visionOS/tvOS **27.0** SDKs and need an **Apple7 GPU family** device or newer (A14/M1+). That covers all three Memoshi reference devices [INF: A16 = Apple8 and M1 = Apple7]. One caveat: the iOS 27 and macOS 27 release notes still say *"The Gaussian Splat Component API in RealityKit will be available in an upcoming release"*, while visionOS 27 ships it. Even so, the Xcode 27.2 SDK headers and the macOS 27.0.1 runtime both export the symbols. Details in §1.
2. **USD now carries splats too.** OpenUSD added a `ParticleField3DGaussianSplat` prim (Apple, NVIDIA, Adobe and Pixar). A new system framework, **USDKit** (iOS/macOS 27), can author and compose USD from Swift. Its `USDStageComponent` renders a USD stage live as RealityKit entities, so the path from an LLM-described scene to USD to RealityView needs no third-party code.
3. **Fastest on-device generation is Apple's SHARP (ml-sharp).** It turns one photo into about 1.18 M metric Gaussians in a single forward pass. A community Core ML conversion takes about 1.9 s on an M4 Max. The **model license is research-only, not for products.**
4. **Object image→splat is now permissively licensed.** Speridlabs **Idol** (Apache-2.0, released ~Oct 2026) has a native MLX port in `mlx-vlm`: 126 s and 9.5 GB peak on an M3 Ultra. That is Mac-only in practice, not iPhone.
5. **Image→mesh** is still heavy. TRELLIS.2-4B is MIT-licensed and has MLX and Swift-MLX ports, but needs 34–72 GB. The **cloud APIs** are cheap and fast enough for async bot jobs: World Labs Marble at $0.12–$2.48 per world with SPZ/PLY/GLB export, and Tripo image→splat at $0.30 in about 4 min.
6. **Formats:** `KHR_gaussian_splatting` is now **ratified** by Khronos. SPZ is the de-facto compressed interchange format (Marble, MetalSplatter, Tripo-adjacent). Spark's `.RAD` handles LoD streaming. Blender 5.3 imports PLY, SPZ, USD and glTF splats.
7. **SceneKit is deprecated** as of iOS/macOS 26 (docs list availability 8.0–26.0). Use RealityKit with `RealityView` (iOS 18 / macOS 15+) and `LowLevelMesh` for procedural geometry.

---

## 1. Native Apple splat support — the explicit answer

| Question | Answer | Label | Source |
|---|---|---|---|
| Is there a first-party splat API? | **Yes.** `GaussianSplatComponent` (struct, `Component`), `GaussianSplatResource` (final class), `GaussianSplatResource.BufferResource`/`BufferDescriptor`, `GaussianSplatEvents.RenderingChanged` | Obs | https://developer.apple.com/documentation/realitykit/gaussiansplatcomponent ; https://developer.apple.com/documentation/realitykit/gaussiansplatresource |
| Platforms (doc metadata) | iOS 27.0, iPadOS 27.0, macOS 27.0, Mac Catalyst 27.0, visionOS 27.0 (+tvOS 27 in the swiftinterface) | Obs | same; local `RealityFoundation.swiftmodule/arm64e-apple-{ios,macos,xros}.swiftinterface` in Xcode 27.2: `@available(visionOS 27.0, macOS 27.0, iOS 27.0, tvOS 27.0, macCatalyst 27.0, *) public struct GaussianSplatComponent` |
| Runtime present on macOS 27? | Yes: `dyld_info -exports RealityFoundation` on macOS 27.0.1 (26A434) lists 159 `GaussianSplat*` symbols | Obs (local) | this machine |
| Release-note caveat | iOS 27 **and** macOS 27 release notes, RealityKit → New Features: *"The Gaussian Splat Component API in RealityKit will be available in an upcoming release."* (178061856). The visionOS 27 notes have no such caveat and list a fixed splat bug (183538823). iOS 27.2 notes don't mention it. | Obs | https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes ; .../macos-release-notes/macos-27-release-notes ; .../visionos-release-notes/visionos-27-release-notes |
| Beta-1 history | At WWDC beta 1 the symbols were absent from the iOS and macOS SDKs (device-only on visionOS). Community probe: ~200 k splats per resource limit; whole-entity culling when the camera is within ~3× the bounding radius; buffers needed padding to 256 B; `colorSpace = sRGB` was mandatory | Obs (community) | https://github.com/ibrews/SplatStage (README) |
| GPU requirement | "Gaussian splats require a device with Apple7 GPU family support." Not rendered in the Simulator | Obs | GaussianSplatComponent doc; sample article https://developer.apple.com/documentation/visionos/rendering-gaussian-splats-with-realitykit |
| Reference devices covered? | iPhone 14 Pro (A16), iPad Pro M1, Apple-silicon Mac: yes | [INF] (Apple7 = A14/M1 generation; A16 is newer) | Metal feature-set tables |
| File loading | **None.** "The framework doesn't load files directly, so you parse your source format — PLY, USD, or any other container — and populate the buffers yourself." Apple's sample parses PLY and also USD (`ParticleField3DGaussianSplat` prim via USDKit) | Obs | GaussianSplatComponent doc; sample article |
| Data layout | position f3, scale f3, rotation f4 (w,x,y,z), opacity f1, SH (degree 0–3). Half precision allowed. AoS or SoA in `LowLevelBuffer`. `scaleActivation`/`opacityActivation` ∈ {identity, exponential, sigmoid}. `projectionMode` ∈ {perspective, tangential}. `sortingMode` ∈ {depth, distance}. `colorSpace: CGColorSpace` | Obs | local swiftinterface; doc |
| Dynamic/animated splats | "The framework references the resource's buffers rather than copying them, so you can update the contents of the underlying `LowLevelBuffer` instances to animate the splats over time." | Obs | GaussianSplatResource doc |
| Limits / throttling | Internal limit on total splats; `BufferResource` init **throws** above it. A scene renders "a limited number of splat entities". Renderer self-throttles and emits `RenderingChanged{isRenderingLimited, renderingStatus ∈ normal/medium/low}`. **Thermal is the app's job**: "The system will *not* automatically limit … in response to thermal state." | Obs | doc; https://developer.apple.com/documentation/realitykit/gaussian-splat-rendering-guidelines |
| Lighting/shadows | Splats ignore scene lighting; `GroundingShadowComponent` gives an approximate sphere-proxy shadow; no collision geometry (supply `ShapeResource` yourself) | Obs | doc; sample |
| Exact numeric splat limit on iOS 27 GA | — (only the ~200 k beta-1 community number) | — | — |
| Spatial Scenes (2D photo→3D) API | `ImagePresentationComponent.Spatial3DImage.generate()` is **visionOS 26+ only**. iOS/macOS have no developer API | Obs | https://developer.apple.com/documentation/realitykit/imagepresentationcomponent (availability: visionOS 26.0) |
| USD splats | OpenUSD "Particle Fields" prim type for Gaussian splats; **USDKit** (iOS/macOS/visionOS 27) with `USDStage`, `USDPrim`, `USDStageComponent` ("renders a USD stage as RealityKit entities"), `USDPlayer`, `exportPackage` with mesh/texture compression | Obs | WWDC26 285 https://developer.apple.com/videos/play/wwdc2026/285 ; https://developer.apple.com/documentation/usdkit |

**Bottom line.** On Xcode 27.2 you can call `GaussianSplatComponent` on iOS and macOS. Apple's own iOS/macOS 27 release notes still flag it as "upcoming", though, so treat it as **possibly unstable or partially enabled on iPhone/Mac until a device test proves otherwise** [INF]. That device test is experiment E1. Keep MetalSplatter (MIT) as the fallback renderer.

---

## 2. Rendering candidates

### 2.1 RealityKit `GaussianSplatComponent` (first-party)

| Field | Detail |
|---|---|
| What | System splat renderer in RealityKit's transparency pass, back-to-front sorting; part of the entity/component graph, so it composes with meshes, `ManipulationComponent`, shadows and attachments |
| Maturity/date | WWDC26 (June 2026, session 279 "Explore advances in RealityKit", chapter 17:09). visionOS 27 GA. iOS/macOS 27 caveat in §1 (Obs) |
| Apple path | `RealityView { content in … entity.components.set(GaussianSplatComponent(resource)) }` in SwiftUI. `RealityView` is available iOS 18 / macOS 15 / visionOS 1 (Obs, https://developer.apple.com/documentation/realitykit/realityview). Data goes into `LowLevelBuffer`s. Parsing: own PLY reader, or USDKit for USD particle fields |
| On-device/cloud | On-device rendering |
| Perf numbers | No Apple-published fps/splat-count numbers. Community, beta 1: ~200 k splats per resource, so large scenes must be chunked (SplatStage). Native-vs-MetalSplatter A/B is "TBD" in SplatStage |
| License | System framework |
| Fit for Memoshi | Best fit. Pure Swift and SwiftUI, no JIT, no web view, buffers updatable for "live" cards. The D68 interpreter can drive entity transforms; D53 cards can reference a splat asset. Risks: release-note caveat; unknown splat cap on A16; no scene lighting; must parse PLY/SPZ ourselves; must handle `thermalStateDidChange` |
| Experiment **E1** (1–2 d) | Build a `RealityView` card that loads (a) a SHARP PLY decimated to 100 k, 200 k and 500 k splats and (b) a Marble `100k`/`500k` SPZ via MetalSplatter's SplatIO (MIT) into `LowLevelBuffer`s. Measure on iPhone 14 Pro, iPad M1 and Mac: does `BufferResource` init throw, and at what count? Steady fps (CADisplayLink / Instruments RealityKit trace), `RenderingChanged` events, `phys_footprint`, thermal state after 5 min orbiting. **Pass:** ≥ 200 k splats at ≥ 55 fps on the iPhone with no `isRenderingLimited` and memory < 600 MB, and ≥ 1 M splats at 60 fps on the Mac. **Fail:** the init throws below 100 k, or the API is non-functional on iOS 27.x. In that case use MetalSplatter (2.2) |

### 2.2 MetalSplatter (scier) — Swift/Metal library

| Field | Detail |
|---|---|
| What | Swift/Metal 3DGS renderer for iOS, macOS and visionOS. Modules: MetalSplatter, PLYIO, SplatIO, SplatConverter, SampleApp |
| Maturity/date | **1.0.0 (2026-02-02)**: SH0–SH3, SPZ I/O, multi-chunk load and sort, Swift 6 strict concurrency, minimum iOS 18 / macOS 15 / visionOS 2. **1.0.1 (2026-02-20)**: fixes loading of ml-sharp PLYs, instant chunk replacement without glitches. Formats: PLY, SPZ, .splat. 725★, 115 forks | Obs https://github.com/scier/MetalSplatter/releases ; https://github.com/scier/MetalSplatter |
| Apple path | `MTKView`/`CAMetalLayer` wrapped in `UIViewRepresentable`/`NSViewRepresentable`, or CompositorServices on visionOS. SPM package |
| Perf numbers | 0.1.1 (2024): "Reduced memory usage by 50% (can now load ~8m splats) and increased frame rate by ~75%" (hardware not stated). Community: **~400–450 k splats at 90 fps on Apple Vision Pro (M2)**, "measured in SplatDiorama" | Obs releases; Obs https://github.com/ibrews/SplatStage |
| License | **MIT** (Obs LICENSE, © 2026 Sean Cier) |
| Fit/risks | Works on iOS 18+, so it doesn't depend on the iOS 27 API caveat. Swift 6 matches Memoshi. Chunk replacement suits streaming generated content. Risks: single maintainer; "documentation is entirely missing"; it sits outside the RealityKit scene graph, so composing with RealityKit UI is harder |
| Experiment **E2** (1 d) | Use the same assets as E1 in MetalSplatter's SampleApp in Release mode on the 3 devices, and get an fps-vs-splat-count curve (100 k, 250 k, 500 k, 1 M, 2 M). **Pass:** ≥ 60 fps at 500 k on the iPhone 14 Pro. Doubles as the A/B baseline against E1 |

### 2.3 Other Swift/Metal renderers (new entrants)

| Project | What | Status | License | Note |
|---|---|---|---|---|
| splatkit-ios (Xget7) | Native Metal SDK for iOS 17+, A14/M1+. GPU visibility + radix sort, SH0–3, `.spz` and `.lodsplat`, experimental LoD and hybrid tiles, walk collider | 0.1.0-beta.2. "LOD and 16-bit sorting remain experimental; sustained 30/60 FPS not guaranteed" | MIT | Obs https://github.com/Xget7/splatkit-ios — early (2★) but has LoD, which MetalSplatter lacks |
| MetalGaussianSplatRelighting | Relightable splats (split-sum IBL, deferred PBR for Ref-Gaussian assets), based on MetalSplatter | community | — | Obs https://github.com/john-rocky/MetalGaussianSplatRelighting |
| DeformableMetalSplatter | Dynamic (4D) 3DGS on MetalSplatter; MobileCLIP text-prompted region selection | demo | — | Obs (listed in MetalSplatter README) |
| mlx-splat | 3DGS renderer for Apple silicon using MLX + Metal | community | MIT | Obs (search listing) https://github.com/daikiad/mlx-splat |
| splatx-metal | 3DGS **training** on Apple silicon; Metal kernels reproducing gsplat | community | Apache-2.0 | Obs (search listing) https://github.com/PoSTMEDIA-AI/splatx-metal |

### 2.4 Web fallback: Spark 2.x / Radix (World Labs) in `WKWebView`

| Field | Detail |
|---|---|
| What | **Spark**: THREE.js 3DGS renderer. Spark 2.0 (blog 2026-04-14) adds an LoD splat tree, the streamable `.RAD` format, a shared paged GPU pool ("default 16 M splats"), `ExtSplats` (32 B/splat, fp32 centers), skinning, portals and shader graphs. **Radix**: new WebGPU renderer from the same org (0.0.1 as of 2026-10-31) |
| Perf numbers | Spark rule of thumb: "iPhone: 1–3 million splats; Computer: 1–5 million (10–20+ M on some desktops)". Default LoD budget N = "500K–2.5M depending on your device type". Radix, M3 Max, Chrome, 1080p, WebGPU: 0.5 M → 2.8 ms, 2 M → 2.0–5.0 ms, 6.1 M → 6.7 ms, 10 M → 8.2 ms GPU/frame. Spark 2.3.1 (WebGL2) at 10 M inside: 16.5 ms vs Radix 9.2 ms. Tiny-lod build: 1–3 s per 1 M splats | Obs https://sparkjs.dev/docs/performance/ ; https://sparkjs.dev/docs/new-features-2.0 ; https://sparkjs.dev/radix/docs/ref/performance.html |
| Apple path | `WKWebView` (or SwiftUI `WebView`, WebKit-in-SwiftUI, new in 26) loading a bundled page. Safari/WebKit 26.0 ships **WebGPU** (Obs https://webkit.org/blog/17333/webkit-features-in-safari-26-0/). Spark 2.3.1 is WebGL2-only ("has no WebGPU path", Radix docs) |
| License | Spark: MIT [INF — repo license not re-read this session]. Radix: — |
| Fit/risks | JS runs in the WebContent process, so Memoshi's no-JIT constraint doesn't apply to its own process [INF]. Best LoD/streaming story today, and the native renderer for Marble's SPZ/.RAD. Risks: WebView memory caps (a SHARP→ONNX→WebGPU attempt crashed on visionOS Safari from RAM limits, Obs https://ironj.github.io/apple-sharp-gaussian-splat-jiggle), a WebKit WebGPU leak on iOS (Obs https://bugs.webkit.org/show_bug.cgi?id=312563), and it is non-native, against the D53/D68 spirit |
| Experiment **E3** (1 d) | Bundle a Spark 2.x page in `WKWebView`. Stream a Marble world as `.RAD` or 500 k SPZ on the iPhone 14 Pro. **Pass:** ≥ 50 fps with WebContent memory < 1 GB for 5 min. Only adopt if E1 and E2 both fail for multi-million-splat *worlds* |

---

## 3. Formats

| Format | Status (Nov 2026) | Apple-side reader | Source |
|---|---|---|---|
| `.ply` (3DGS convention) | Universal raw format. Apple sample documents the property set (`x,y,z,f_dc_*,f_rest_*,opacity,scale_*,rot_*`, log-scale, logit opacity, channel-major SH) | MetalSplatter PLYIO (MIT); Apple sample code | Obs Apple sample article |
| `.spz` (Niantic) | Compressed. Marble exports `100k`/`500k`/`full_res` SPZ. MetalSplatter 1.0 and splatkit read it. Blender 5.3 imports it | MetalSplatter SplatIO | Obs https://docs.worldlabs.ai/api/rendering-spz.md ; MetalSplatter releases |
| `.splat` (antimatter15) | Legacy, lossy. Tripo image→splat outputs `.splat` | MetalSplatter | Obs Tripo doc |
| `.sog` (PlayCanvas) | Not supported by MetalSplatter ("hopefully opens the door to SOG") | — | Obs https://radiancefields.com/metalsplatter-releases-v1.0 |
| `.RAD` (Spark 2.0) | LoD tree, HTTP-range streamable | web only | Obs Spark 2.0 docs |
| glTF `KHR_gaussian_splatting` | RC 2026-02-03. README status now **"Complete, Ratified by the Khronos Group"**. Baseline kernel `ellipse`. Compression (`KHR_gaussian_splatting_compression_spz`) is a separate draft/RC | none native on Apple [INF] | Obs https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_gaussian_splatting/README.md ; https://www.khronos.org/news/press/gltf-gaussian-splatting-press-release |
| OpenUSD Particle Fields (`ParticleField3DGaussianSplat`) | New prim type (Apple/NVIDIA/Adobe/Pixar). Apple's RealityKit sample reads it via USDKit | USDKit (iOS 27) | Obs WWDC26 285; sample article |

**Recommendation [INF]:** store the canonical form as SPZ (small, widely supported). Decode to SoA half-float buffers for RealityKit. Treat USD particle fields as the export/interchange format.

---

## 4. Generation candidates

### 4.1 Apple SHARP (`apple/ml-sharp`) — single photo → metric 3DGS

| Field | Detail |
|---|---|
| What | Feed-forward network that regresses a metric 3DGS scene from one photo; "less than a second on a standard GPU"; LPIPS −25–34 % vs prior SOTA |
| Maturity | arXiv 2512.10685 (v1 2025-12-11, v2 2026-02-27). **ICLR 2026**. Code and checkpoint public | Obs https://arxiv.org/abs/2512.10685 ; https://github.com/apple/ml-sharp |
| Apple path | PyTorch reference supports CPU/CUDA/**MPS** for prediction. Community **Core ML** `.mlpackage` (pearsonkyle/Sharp-coreml) runs on CPU/GPU/ANE and includes a Swift runner (`sharp.swift`, CoreML + CoreImage) | Obs README; https://huggingface.co/pearsonkyle/Sharp-coreml |
| Output | ~**1,179,648 Gaussians** at a 1536×1536 input (SH0 linear RGB). Runner supports decimation (`-d 0.5`) | Obs HF card |
| Numbers | Core ML on **M4 Max: ~1.9 s** (Obs HF card). Shipping iOS app "Sapling" claims SHARP runs locally on iPhone (device and latency not stated; Obs dev's Reddit post 2026-01-12 https://www.reddit.com/r/GaussianSplatting/comments/1qaivmi/). Native visionOS Core ML app works (Obs ironj blog). iPhone 14 Pro latency and memory: — |
| License | Code: Apple sample-code-style license. **Model: "Apple Machine Learning Research Model" license, "exclusively for Research Purposes … does not include … product development or use in any commercial product or service."** (Obs LICENSE_MODEL) |
| Fit/risks | Technically ideal: one photo in, a metric splat out in ~2 s, on device, no network. MetalSplatter 1.0.1 explicitly fixed ml-sharp PLY loading. Risks: **license** (personal use is arguably neither research nor commercial; legal grey area [INF]); 1.18 M splats is over the beta-1 RealityKit per-resource cap, so decimate to ≤ 200 k or chunk; only nearby novel views (not 360°); unknown peak memory on a 6 GB A16 |
| Experiment **E4** (2 d) | Integrate `Sharp-coreml` via the Swift runner logic into a Memoshi bot tool `photoTo3D(image) -> splatAssetID`. Run on iPad M1 and iPhone 14 Pro with `.cpuAndNeuralEngine` and `.all`. Decimate to 200 k and render via E1/E2. **Measure:** latency, `phys_footprint` peak, thermal state, ANE vs GPU. **Pass:** ≤ 10 s on the iPad M1, ≤ 20 s on the iPhone, peak < 3 GB, no jetsam. Record the license decision before shipping beyond the developer's own devices |

### 4.2 Speridlabs **Idol** — single object image → 3DGS (new entrant, Apache-2.0)

| Field | Detail |
|---|---|
| What | Object image → 32 k–1,048,576 Gaussians (default 262,144), "including the sides the picture never showed". 370 M DiT + octree and Gaussian decoders. Conditioning: DINOv3 ViT-H+ and FLUX.2 VAE. BiRefNet matting. ~1.8 B parameters per full request. Builds on TripoSplat |
| Maturity | HF model with 1.9 k likes and 28 k downloads; MLX port validated 2026-11-02 | Obs https://huggingface.co/speridlabs/idol ; https://github.com/speridlabs/idol-sdk |
| Numbers | H100: 6.7 s; B300: 3.4 s; RTX 4090: 19.1 s (50 steps, 262 k Gaussians). 7.2 GB VRAM peak. **PyTorch MPS, M4 MacBook Air: ~4 min (10 steps, 65 k) / ~18 min (50 steps, 262 k, needs 24 GB).** **Native MLX (`mlx-vlm`), M3 Ultra: 126 s including encoder load, 9.49 GB peak MLX memory** (50 steps, 262 k). X post claims ~8.6 GB peak, "fits 16 GB Macs" | Obs idol-sdk README; Obs https://github.com/Blaizzy/mlx-vlm/blob/main/mlx_vlm/models/idol/README.md ; claim https://x.com/Stefan_3D_AI/status/2117523359588376881 |
| Apple path | Mac only in practice: Python `mlx-vlm` (includes `/v1/meshes` server). A Swift-MLX port does not exist yet [INF]. iPhone (6 GB) is out of reach at ~9 GB [INF]. iPad M1 (8 GB) is marginal [INF] |
| License | Idol code and weights **Apache-2.0**. Dependencies: DINOv3 (gated, Meta license) and FLUX.2-dev (gated; only the VAE is used), so check those terms [INF] |
| Fit/risks | Best permissive object-to-splat model with a local Apple path. Fits a "Mac generates, iPhone views" split (generate on Mac, sync the SPZ via CloudKit). Risk: Python on Mac; this is not D60 Pyodide on iOS |
| Experiment **E5** (2 d) | On the Mac, run `mlx_vlm.server --mesh-model speridlabs/idol` as a local helper. A bot sends a generated or captured image and gets a PLY back, converted to SPZ and synced. **Measure:** wall time at 20, 30 and 50 steps × 65 k / 262 k Gaussians on the user's Mac, plus peak memory. **Pass:** ≤ 60 s at 262 k on an M-series Pro/Max with ≥ 32 GB; 360° object coherent by visual check |

### 4.3 Microsoft **TRELLIS.2-4B** — image → PBR mesh (GLB)

| Field | Detail |
|---|---|
| What | 4 B flow-matching model on O-Voxel sparse latents. Textured PBR meshes up to 1536³. Also does shape-conditioned texturing |
| Numbers | **H100: 512³ ~3 s, 1024³ ~17 s, 1536³ ~60 s.** Official code requires a 24 GB+ NVIDIA GPU | Obs https://huggingface.co/microsoft/TRELLIS.2-4B |
| Apple ports | `gtrg55/trellis2-mlx` (MIT, 71★): MLX + MPS, tested on an M4 Max with 128 GB; "1024³ … can take several minutes". `xocialize/mlx-trellis2-swift`: **pure Swift-MLX** re-port, parity-gated; on M5 Max 128 GB, resident + activation **34 GB (res512) / 69 GB (res1024) / 72 GB (res1536)**; mesh+bake to GLB in ~25–30 s; outputs glTF. Upstream PR #175 adds MPS/Metal | Obs https://github.com/gtrg55/trellis2-mlx ; https://github.com/xocialize/mlx-trellis2-swift ; https://github.com/microsoft/TRELLIS.2/pull/175 |
| License | Model and code **MIT** (Obs HF). Swift port: "Other" (license not checked) |
| Fit/risks | Gives editable meshes that convert to USDZ (RealityKit-native, lit, collidable). Far too large for iPhone and iPad; only high-memory Macs [INF]. Better used via a cloud API (Runware hosts it, Obs search listing) |
| Experiment | Skip unless the user's Mac has ≥ 64 GB. Otherwise use the cloud equivalent (4.6) |

### 4.4 Meta **SAM 3D** (Objects + Body)

| Field | Detail |
|---|---|
| What | SAM 3D Objects: masked object(s) in a natural image → shape, texture and layout; exports a Gaussian splat (`output["gs"].save_ply`) or mesh. SAM 3D Body: human mesh recovery |
| Maturity | Checkpoints 2025-11-19; encoder weights 2026-06-01; SA-3DAO artist set and leaderboard 2026-06-02 | Obs https://github.com/facebookresearch/sam-3d-objects |
| Apple path | None official; CUDA-centric reference [INF]. No MLX/Core ML port found |
| License | **SAM License** (custom, not OSI) | Obs LICENSE |
| Fit | Strongest for cluttered real photos (occlusion). Cloud or Mac-research only for Memoshi. Rank low |

### 4.5 Tencent Hunyuan3D

| Field | Detail |
|---|---|
| Status | Open weights stop at **2.1** (Tencent Hunyuan 3D 2.1 Community License: territory excludes **EU, UK, South Korea**, and outputs are covered too). 2.5/3.0/3.1 are hosted-only. HY 3D 3.1 released 2026-01-16 | Secondary sources only: https://cgworld.jp/flashnews/01-202602-TencentHY3D.html ; https://triposr.org/blog/hunyuan3d-versions [verify before use] |
| Timing | 3.1 Rapid ~84 s, Pro ~174 s end-to-end (third-party measurement, 2026-09-27) | https://ai3d.studio/hunyuan-3d (secondary) |
| Fit | License territory is a red flag if the user is in the EU or UK [INF]. Hosted API only. Lower priority than Tripo/Marble |
| Related | **HunyuanWorld-Mirror (WorldMirror, ICML 2026)**: feed-forward multi-view → depth/pose/normals/**3DGS** in ~1–2 s on one GPU, under a community license (secondary summary) https://github.com/Tencent-Hunyuan/HunyuanWorld-Mirror |

### 4.6 Cloud generation APIs

| Service | Output | Speed | Price | Apple-relevant export | Source |
|---|---|---|---|---|---|
| **World Labs Marble API** (`marble-1.0-draft`, `marble-1.0`, `marble-1.1`, `marble-1.1-plus`) | Full **3DGS worlds** from text, image, pano, multi-image or video. SPZ at `100k`/`500k`/`full_res` + `semantics_metadata` (metric scale, ground offset), pano, collider mesh. `:export` → PLY (free) or HQ GLB mesh (3,500 cr = $2.80) | — (not published in docs read) | $1 = 1,250 credits. Draft **150 cr ($0.12)**. Standard 1,500–1,600 cr (~$1.20–1.28). 1.1-plus median **$1.28**, max $2.48 | SPZ 100k/500k map directly onto the RealityKit per-resource budget; coordinate convention `marble_raw_opencv` | Obs https://docs.worldlabs.ai/api/pricing ; /api/faq ; /api/rendering-spz.md ; /marble/models.md |
| **Tripo API v3** | **`POST /v3/generation/image-to-splat`** → `.splat`; image/text/multiview → mesh (H/P series) | splat: "Typical generation time is around 4 minutes" | splat: **30 credits = $0.30** (1 credit = $0.01 from 2026-12-01) | Convert API outputs **USDZ**, GLTF, FBX, OBJ, STL, 3MF. V2 retired 2026-11-01 | Obs https://developers.tripo3d.ai/en/docs/generation-image-to-splat ; /en/docs/billing ; https://developers.tripo3d.ai/llms.txt ; https://platform.tripo3d.ai/docs/generation |
| Meshy / Rodin | Image/text → mesh | — | — | — (not verified this session) | — |

**Fit [INF]:** cloud calls fit Memoshi's bot model as async jobs: a bot emits a card with a "generating…" state, then swaps in the asset. Marble's Draft tier at $0.12 is the cheapest "world" generator. Tripo is the only API found that does **image→splat** and **mesh→USDZ** under one key.

### 4.7 Feed-forward multi-view splatting (capture → splat in seconds)

| Model | Note | License | Apple path | Source |
|---|---|---|---|---|
| AnySplat (SIGGRAPH Asia 2025) | Unposed, uncalibrated images → 3DGS, feed-forward | MIT (HF `lhjiang/anysplat`) | none found | Obs search listing https://github.com/InternRobotics/AnySplat |
| Depth Anything 3 | Any-view → depth, pose, **3D Gaussians**. Small/Base/Metric-Large are Apache-2.0; Giant/Nested (needed for the GS head) are CC BY-NC | mixed | none found | secondary https://github.com/bytedance-seed/depth-anything-3 |
| WorldMirror | see 4.5 | community | none | secondary |
| 2026 arXiv wave | GlobalSplat, F4Splat, InfiniSplat v2 (2610.20341), SplatAnything (2611.08264) | various | none | search listings only |

**Verdict [INF]:** none has an Apple-silicon port yet. They are research-grade for Memoshi. Watch for an MLX port of DA3-Base (Apache) with a GS head.

### 4.8 On-device splat **training** (capture → splat on the phone)

| Item | Detail | Source |
|---|---|---|
| **PocketGS** (arXiv 2601.17354) | End-to-end 3DGS training **on iPhone 15 (A16, 6 GB)**, the same SoC class as Memoshi's iPhone 14 Pro. 500 iterations in **~4 min** (255 s mean). Peak **< 3 GB** (training mean 2.22 GB). Render **52 fps** on the same phone. Uses ARKit poses | Obs https://arxiv.org/html/2601.17354v5 |
| Apple Object Capture | `ObjectCaptureSession` (iOS 17+) + `PhotogrammetrySession` (iOS 17+, macOS 12+) → USDZ **mesh**, not splats; on-device reconstruction | Obs https://developer.apple.com/documentation/realitykit/objectcapturesession ; PhotogrammetrySession doc |

### 4.9 4D / dynamic splats

| Item | Detail | Source |
|---|---|---|
| RealityKit | Buffers are referenced, not copied, so you can animate splats by writing to `LowLevelBuffer` (e.g. from a Metal compute pass) | Obs GaussianSplatResource doc |
| Spark 2.0 | Dyno shader graphs, linear-blend skinning for rigged splat characters, portals | Obs Spark 2.0 docs |
| DeformableMetalSplatter | Dynamic 3DGS on Metal | Obs MetalSplatter README |
| Feed-forward 4D generation on Apple | — none found | — |

---

## 5. Mesh-side Apple stack for generated 3D

| Tech | Status | Path | Fit for LLM-generated scenes |
|---|---|---|---|
| **USDKit** (new, iOS/macOS/visionOS 27) | System framework: `USDStage()` / `.open`, `definePrim(at:type:)`, references, `addTransformOperation`, attributes, `applyAPISchema`, `exportPackage(to:options:[.preferSmallTextureFiles, .preferSmallMeshFiles])` (AOM mesh codec, "up to 90 %" mesh reduction; average asset "7× smaller"), and **`USDStageComponent`** ("renders a USD stage as RealityKit entities", manual or automatic mode) | Obs WWDC26 285; https://developer.apple.com/documentation/usdkit ; usdstagecomponent doc | **Best mesh path.** A bot emits a small JSON scene spec (D53-style, validated), Swift maps it to `definePrim` calls, and `USDStageComponent` renders it live. USDZ export comes free. No code generation; fits D68 because the interpreter only needs USDKit bindings |
| `LowLevelMesh` / `LowLevelTexture` | iOS 18 / macOS 15 / visionOS 2. Vertex buffers updated directly, including by Metal compute | Obs https://developer.apple.com/documentation/realitykit/lowlevelmesh ; sample "Generating interactive geometry with RealityKit" | Procedural/parametric shapes (charts-in-3D, terrain, ribbons) from interpreter-emitted parameters |
| `MeshResource.generate*`, `ShapeResource` | built-ins | — | Primitives for the catalog |
| Reality Composer Pro 3 | New at WWDC26 (no-code games, light baker, NavMesh, graphs) | Obs WWDC26 279 related sessions | Authoring-time only; not runtime generation |
| Preview on Mac | 3D editing, RealityKit/Storm/new Raytracer renderers, OpenPBR, compression | Obs WWDC26 285 | Debugging generated USD |
| **SceneKit** | **Deprecated**: framework availability ends at 26.0 on every platform; WWDC25 288 migration guide | Obs https://developer.apple.com/documentation/scenekit ; https://developer.apple.com/videos/play/wwdc2025/288/ | Don't build on it |
| Safari `<model>` | USD in web pages on macOS/iOS 26+ | Obs WWDC26 285; WebKit 26.0 blog | Irrelevant natively; useful if a web card needs 3D |

---

## 6. Showing splats/3D inside a SwiftUI app — integration notes

| Topic | Note | Label/Source |
|---|---|---|
| Container | `RealityView` (iOS 18/macOS 15+) is the SwiftUI-native host for both splats (27+) and USD/meshes. MetalSplatter needs `MTKView` in a `UIViewRepresentable` | Obs RealityView doc |
| Card sizing | Splat cost is fill-bound (overdraw). Radix: pixel ratio 2 made the draw 2.6× slower inside scenes. Small in-feed cards are much cheaper than full-screen | Obs Radix perf doc |
| Many cards | RealityKit caps splat entities per scene. For feed scrolling, render only the focused card live and show the others as snapshot images | Obs sample article; [INF] strategy |
| Thermal | Apple explicitly puts thermal mitigation on the app: observe `ProcessInfo.thermalStateDidChangeNotification`, then decimate or LoD-swap at `.serious`/`.critical` | Obs splat guidelines; WWDC26 279 |
| Memory | Raw SH3 float PLY ≈ 248 B/splat (62 floats) [INF arithmetic]. 1 M splats ≈ 248 MB, SH0 half ≈ 28 B/splat → 28 MB. Spark packed = 16 B/splat. `com.apple.developer.kernel.increased-memory-limit` entitlement exists (iOS 15+) | [INF] arithmetic; Obs Spark docs; entitlement doc |
| Sanitize | RealityKit **rejects** non-finite values; sanitize NaN/Inf to 0 | Obs sample article |
| Coordinates | SHARP: OpenCV frame (x right, y down, z fwd), centre at (0,0,+z). Marble: `marble_raw_opencv`, metric scale factor; the web viewer rotates 180° about X | Obs ml-sharp README; Marble rendering-spz doc |
| Simulator | Splats don't render in the Simulator (RealityKit and splatkit), so test on device | Obs sample; splatkit README |

---

## 7. Performance table (hardware + source per row)

| # | Renderer / model | Workload | Hardware | Result | Source | Label |
|---|---|---|---|---|---|---|
| P1 | MetalSplatter | 90 fps budget | Apple Vision Pro (M2) | ~400–450 k splats | https://github.com/ibrews/SplatStage | Obs (community) |
| P2 | MetalSplatter 0.1.1 | max loadable | not stated | ~8 M splats; +75 % fps vs 0.1.0 | https://github.com/scier/MetalSplatter/releases | Obs |
| P3 | RealityKit GaussianSplatComponent (beta 1) | per-resource cap | Apple Vision Pro | ~200 k splats/resource; whole-entity cull within ~3× radius | SplatStage README | Obs (community, beta) |
| P4 | PocketGS renderer | render | iPhone 15 (A16, 6 GB) | **52.3 fps** (Mobile-GS 62.6, MetaSapiens 49.2) | https://arxiv.org/html/2601.17354v5 Table | Obs |
| P5 | PocketGS training | 500 iters | iPhone 15 (A16) | 255 s; peak < 3 GB | same | Obs |
| P6 | Spark (WebGL2) guidance | budget | iPhone (generic) | 1–3 M splats | https://sparkjs.dev/docs/performance/ | Obs |
| P7 | Radix (WebGPU) | 0.5 / 2 / 6.1 / 10 M splats | M3 Max, Chrome, 1080p | 2.8 / 2.0–5.0 / 6.7 / 8.2 ms GPU/frame | https://sparkjs.dev/radix/docs/ref/performance.html | Obs |
| P8 | Spark 2.3.1 vs Radix | 10 M inside (Grace) | M3 Max | 16.5 ms vs 9.2 ms; vsync 73 vs 81 fps on WebGL2 | same | Obs |
| P9 | SHARP Core ML | 1 image → ~1.18 M Gaussians | M4 Max | ~1.9 s | https://huggingface.co/pearsonkyle/Sharp-coreml | Obs |
| P10 | SHARP (PyTorch) | 1 image | "standard GPU" | < 1 s | https://github.com/apple/ml-sharp | Obs |
| P11 | Idol (MLX) | 50 steps, 262 k | M3 Ultra | 126 s; 9.49 GB peak | mlx-vlm Idol README | Obs |
| P12 | Idol (PyTorch MPS) | 10 steps 65 k / 50 steps 262 k | M4 MacBook Air | ~4 min / ~18 min (24 GB) | idol-sdk README | Obs |
| P13 | Idol (CUDA) | 50 steps 262 k | H100 / RTX 4090 | 6.7 s / 19.1 s | idol-sdk README | Obs |
| P14 | TRELLIS.2-4B | 512³ / 1024³ / 1536³ | H100 | ~3 / ~17 / ~60 s | HF model card | Obs |
| P15 | mlx-trellis2-swift | footprint res512 / 1024 / 1536 | M5 Max 128 GB | 34 / 69 / 72 GB charged; GLB bake ~25–30 s | https://github.com/xocialize/mlx-trellis2-swift | Obs |
| P16 | Tripo image→splat | 1 image | cloud | ~4 min, $0.30 | Tripo docs | Obs |
| P17 | Marble API | 1 world | cloud | $0.12 (draft) – $2.48 (1.1-plus max); latency — | World Labs pricing | Obs |
| P18 | RealityKit splats on iPhone 14 Pro / iPad M1 | any | — | **no published numbers → E1** | — | gap |

---

## 8. What changed since 2026-10-22 (prior repo research cutoff)

- **Idol** (Speridlabs, Apache-2.0) image→splat; MLX port validated **2026-11-02**; X announcement 2026-11-03.
- **Radix** (World Labs WebGPU splat renderer) docs and benchmarks (Oct 9 comparison; 0.0.1 tested 2026-10-31); Spark at 2.3.1.
- **Tripo API V2 shut down 2026-11-01**; V3 has `image-to-splat` and a USD pricing display from 2026-12-01.
- Blender 5.3 native splat import (PLY/SPZ/USD/glTF), Fortnite UEFN 43.00 splats (radiancefields news, 2026-11-09/10) — ecosystem signal only.
- Everything else here (RealityKit splats, USDKit, KHR ratification, MetalSplatter 1.0, SHARP, TRELLIS.2 ports) predates 2026-10-22, but the prior research did not cover it.

---

## 9. Ranked shortlist (slice D)

1. **RealityKit `GaussianSplatComponent` + USDKit in `RealityView` (native splat and USD rendering), with MetalSplatter (MIT) as fallback.** First-party, Swift-only, no JIT/web, and covers all reference devices (Apple7+). Bots only emit an asset reference plus camera/transform params, which fits D53/D68 directly. Gate on E1 because of the iOS/macOS 27 release-note caveat.
2. **LLM scene spec → USDKit `USDStage` → `USDStageComponent` (procedural mesh scenes, plus `LowLevelMesh` for parametric geometry).** Fully on-device, deterministic and validatable, so it fits the "no code/HTML, catalog-validated" rule. USDZ export comes for free. It is the only generated-3D path that needs **no** ML model on an A16 [INF].
3. **Photo/idea → splat generation, tiered.** On device: **SHARP Core ML** (~2 s on M-series, single-photo metric splats; flag the research-only model license). Mac helper: **Idol via MLX** (Apache-2.0, ~2 min). Cloud: **Marble API** for whole worlds ($0.12–$2.5, SPZ 100k/500k) and **Tripo** for objects ($0.30, `.splat`/USDZ). This covers "make it 3D" requests within real device limits.

Suggested experiment order: **E1 → E2** (renderer go/no-go, 2–3 days total) → **E4** (SHARP on device) → **E6**:

**E6 (2 d), LLM→USD scene card:** define a 10-prim JSON schema (box, sphere, cylinder, text, image plane, light, camera, group, transform, splat-ref). Have the on-device Qwen3-4B (D80) emit it for 20 prompts, validate it, build a `USDStage` via USDKit, and render with `USDStageComponent` in a card. **Measure:** schema-valid rate, prompt→first-frame latency on the iPhone 14 Pro, memory. **Pass:** ≥ 90 % valid, ≤ 1.5 s from JSON to first frame, 60 fps for ≤ 50 prims.
