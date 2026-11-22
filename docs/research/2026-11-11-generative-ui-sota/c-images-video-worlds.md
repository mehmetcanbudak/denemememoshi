# Slice C — Real-time / low-latency generated images, video & interactive worlds for Apple apps (SOTA as of 2026-11-11)

Scope: on-device and cloud image/video/world generation consumable by a native Swift/SwiftUI app (macOS/iOS/iPadOS 27; visionOS bonus), judged against Memoshi constraints (iPhone 14 Pro A16/6 GB/no Apple Intelligence; iPad Pro M1 8 GB; Apple-silicon Mac; no JIT, no child processes on iOS; MLX already in-app per D80; personal-use distribution).

Legend: **Obs** = read in the cited primary source. **[INF]** = my inference. Vendor-reported numbers are marked "(vendor)".

---

## 0. What changed since 2026-10-22 / headline findings

| # | Finding | Label | Source |
|---|---|---|---|
| 1 | **`ImageCreator` (programmatic on-device Image Playground) is discontinued.** "will no longer work in iOS 27, iPadOS 27, macOS 27, and visionOS 27 or later"; in betas it throws at runtime in TestFlight builds; in public OS releases code won't compile. Apple says: move to the Image Playground **sheet**, "or integrate another image generation service of your choice." (News post dated 2026-06-11) | Obs | https://developer.apple.com/news/?id=dz9wvq0r |
| 2 | Image Playground in the 27 releases runs on a **new model on Private Cloud Compute**, adds photorealistic + "virtually any style", `sizeSpecification = .closest(to:)`, `.drawing(PKDrawing)` concepts, `.externalProvider` style (e.g. ChatGPT), `.emoji` style → `NSAdaptiveImageGlyph` via `onAdaptiveImageGlyphCreation`, `personalization = .disabled`, `@Environment(\.supportsImageGeneration)`; usage-limited by the system (more with iCloud+). Only UI surface: `.imagePlaygroundSheet` / `ImagePlaygroundViewController`. | Obs | WWDC26 session 375 transcript: https://developer.apple.com/videos/play/wwdc2026/375 (mirror https://apple-docs.everest.mt/docs/wwdc/wwdc2026-375) |
| 3 | ⇒ **Memoshi bots cannot generate images headlessly via Apple APIs anymore**, and the iPhone 14 Pro (no Apple Intelligence) gets `supportsImageGeneration == false`. Apple path = user-initiated sheet on M1 iPad / Mac only. | [INF] from 1–2 | — |
| 4 | **FLUX 3 Image Klein** (BFL, 2026-10-15): 5.6B open weights, step-distilled + base, up to 10 refs; 11.2 GB BF16 / 5.6 GB FP8; API `flux-3-image-klein` from $0.009/1K image; API median 4.54 s T2I (vendor); **FLUX Kommunity License** (free commercial < $5M revenue). | Obs | https://bfl.ai/blog/flux-3-image-klein |
| 5 | **mflux 0.23.0 (2026-10-16)** runs FLUX 3 Image Klein (4/6/8-bit) and Qwen-Image-2.1-Turbo 8-step; **0.24.0 (2026-10-27)** adds FIBO 2, needs Python ≥3.11 / Pillow 13. | Obs | https://github.com/mflux-community/mflux/releases |
| 6 | **Draw Things "Harvest Season" (2026-10-15)**: new M5 Ultra / M6 benchmarks vs mflux, mlx-serve, vpipe on Krea 2 Turbo, Qwen Image 2.1 Turbo, MiniMax H3 (video). DT 1.11–1.97× faster than best competitor on M3 Ultra/M4 Pro/M5 Ultra; 0.89–1.25× on M6. M5 Ultra 5.87–6.74× M3 Ultra end-to-end. (Charts only; no absolute seconds in text.) | Obs | https://releases.drawthings.ai/p/harvest-season-new-hardware-new-inference |
| 7 | **Decart Lucy 2.6** realtime (Oct 2026), 720p, `lucy-latest`; fast mode 2× price; Swift SDK (MIT, LiveKit-backed) at v0.7.1+. | Obs | https://docs.platform.decart.ai/changelog |
| 8 | **Genie 4** announced 2026-10-27: native audio, Gemini 3.8 Flash in-the-loop steering; trusted testers only; "coming soon" to AI Ultra + Gemini API early-access partners. No public API. | Obs | https://deepmind.google/blog/genie-4-a-new-generation-of-world-simulation/ |
| 9 | **World Labs Frameboy (2026-11-05)**: Atlas world model streamed from cloud GPUs to browser at up to 15 fps; World Labs **joined AMD** (2026-09-28). | Obs | https://worldlabs.ai/blog/atlas-realtime ; https://worldlabs.ai/blog |
| 10 | **Matrix-Game 4.0** (Skywork, 2026-10-15): engine renders low-poly frames, causal few-step video model "neurally renders" them; 67 FPS RTX 5080 @864×480 (vendor); Apache-2.0 (v4). NVIDIA only. | Obs | https://github.com/SkyworkAI/Matrix-Game |
| 11 | **OpenAI Images 2.6** (2026-11-04): `gpt-image-2.6-flare` / `-sunburst`; GIF (2–64 frames) and SVG output; `complexity` dial; Flare "as little as six seconds" at low quality (vendor, via secondary write-up); `gpt-image-2` now marked Deprecated on its model page. | Obs (model page) / secondary | https://developers.openai.com/api/docs/models/gpt-image-2 ; https://www.digitalapplied.com/blog/gpt-image-2-6-flare-sunburst-api-guide |
| 12 | **Nano Banana 2.1** (`gemini-nano-banana-2.1`, Oct 2026): no Live API support; 1K/2K/4K. A 760-job production study reports **p50 68 s** (2K edits w/ reference). | Obs (docs) / third-party measured | https://ai.google.dev/gemini-api/docs/models/gemini-nano-banana-2.1 ; https://thenote.app/post/en/nano-banana-2-1-api-in-production-latency-failures-and-concurrency-from-760-real-mvkpj8kpac |

---

## 1. Latency / fps table (hardware + source per row)

All rows Obs unless marked. "E2E" = end-to-end incl. text encode + VAE; "denoise" = DiT loop only.

### 1a. Images — on Apple devices

| Model / engine | Res, steps | Hardware | Latency | Notes | Source |
|---|---|---|---|---|---|
| SD 2.1 base, Core ML, ANE (`SPLIT_EINSUM_V2`, 6-bit) | 512², 20 steps, CFG | **iPhone 14 Pro Max (A16)** | **7.9 s** E2E (2.69 it/s) | closest proxy for Memoshi's iPhone 14 Pro; iOS 17-era bench | https://github.com/apple/ml-stable-diffusion (now `apple-aiml-research/ml-stable-diffusion`) |
| SD 2.1 base, Core ML, ANE | 512², 20 | iPad Pro **M1** | 11.2 s E2E | | same |
| SDXL-iOS Core ML (4.04-bit MBP) | 768², 20 | iPhone 14 Pro Max | 77 s (reduceMemory) | memory-starved | same |
| SDXL-iOS Core ML | 768², 20 | iPad Pro M1 | 36 s | | same |
| **SnapGen++ 0.4B DiT** (K-DMD, 4 steps) | 1024², 4 | iPhone 16 Pro Max | **1.8 s** total (360 ms/step + 120 ms tiny-VAE) | paper; weights not observed as released | https://arxiv.org/html/2601.08303 |
| **Bonsai Image ternary 4B** (FLUX.2 Klein 4B, 1.58-bit, MLX Swift) | 512², 4 | iPhone 17 Pro Max (A19 Pro, 12 GB) | **9.4 s** (2.35 s/step) | 256²: 4.0 s; 128²: 2.7 s; Apache-2.0; 3.88 GB payload | https://huggingface.co/prism-ml/bonsai-image-ternary-4B-mlx-2bit |
| Bonsai Image ternary 4B | 1024², 4 | iPhone 17 Pro Max | 34.0 s | | same |
| Bonsai Image ternary 4B (MLX) | 512² / 1024², 4 | Mac **M4 Pro** 48 GB | **5.78 s / 24.26 s** | 3.15× / 5.56× vs stock mflux FP16; 2.38 GB mean active mem @1024² | same |
| FLUX.1 schnell, Draw Things | 768², 2 | iPhone 17 Pro | < 35 s E2E (~10 s/step) | 1024²: just over 50 s; Qwen Image 2-step 768²: just over 45 s | https://releases.drawthings.ai/p/iphone-17-pro-doubles-ai-performance |
| iPhone 16 Pro thermal note | — | iPhone 16 Pro | throttling "after about a minute" at 70 °F for 1024²+ | | same |
| FLUX.2 klein 4B / 9B, Z-Image Turbo — **Lightning Draft** (Draw Things) | recommended settings | Mac **M5 Max** | **"around or under one second"** (vendor) | "interactive latency"; 6-bit variant, second run | https://releases.drawthings.ai/p/introducing-lightning-draft-interactive |
| FLUX.2 klein 4B, mflux 4-bit | 1024², 4 | Mac Studio **M3 Ultra** 256 GB | **9.2 s** (2.8 s/step) | bf16 9.1 s — no quant penalty on M3+ | https://github.com/raullenchai/Rapid-MLX/issues/3058 |
| FLUX.2 klein 4B, mflux | 1024², 4 | Mac mini **M2 Pro** 32 GB | 52 s (4-bit) / 44–47 s (bf16); later median 41.8 s bf16 | 4-bit is *slower* on M1/M2 (quantized_matmul −30 %) | same |
| Z-Image Turbo, mflux 4-bit | 1024², 8 | M3 Ultra / M2 Pro | 34 s / 150 s | | same |
| Z-Image Turbo 8-bit, **mlx-swift** 0.30.6 (Swift app) | 1024², 9 fwd | Mac **M4 Max** 36 GB | 57.6 s median (68.3 s one run); 4-step 30.6 s | peak 18.5 GiB; text-enc 2.4 s, VAE 3.3 s | https://github.com/whit3rabbit/turbospark/blob/main/docs/ZIMAGE_TURBO_MLX_SPEED.md |
| Z-Image Turbo, int8 Metal-4 tensor-op engine (`zimgturbo`) | 1024², 8 | Mac **M5 Pro** | 13.5–14.0 s E2E (author-reported) | relayed via turbospark doc; M4 probe didn't reproduce | same |
| FLUX.1-schnell / Klein 4B / Qwen-Image-2.1 via mlx-dfloat (lossless DF11) | 1024² | M1 Max 32 GB | peak 19.8 GiB / 11.9 GiB / 20.4 GiB; step ~3.5–4 % slower than pre-decoded | memory, not speed, lever | https://pypi.org/project/mlx-dfloat/0.2.1 |
| FLUX 3 Image Klein distilled (INT8/NVFP4) | 1 MP, 16 steps | RTX 5090 / RTX 4070 / GB300 | ~4 s / < 9 s / < 0.6 s (NVIDIA-measured) | reference for cloud; no Apple numbers published | https://bfl.ai/blog/flux-3-image-klein |

### 1b. Images — cloud APIs (what a Swift client sees)

| Service / model | Transport | Latency | Price | Source |
|---|---|---|---|---|
| **fal `fal-ai/flux-2/klein/realtime`** (img2img) | **WebSocket**, raw JPEG frames out; 1–8 steps (default 3); 768² / 1024²; `output_feedback_strength` loop; optional RIFE interpolation | not published (designed for streaming; recommends 704² JPEG q50 input) | $0.00194 / compute-second | https://fal.ai/models/fal-ai/flux-2/klein/realtime/llms.txt |
| FLUX.2 klein 4B on fal H100 (reference) | HTTP | 0.39 s / image 1024² 4 steps | — | https://github.com/raullenchai/Rapid-MLX/issues/3058 |
| BFL API `flux-3-image-klein` | HTTP (poll) | median 4.54 s T2I, 7.18 s edit @1 MP incl. queue (vendor) | from $0.009 / 1K image | https://bfl.ai/blog/flux-3-image-klein |
| OpenAI `gpt-image-2.6-flare` | HTTP + **SSE `image_generation.partial_image`** events (b64 partials) | "as little as 6 s" at low quality (vendor, secondary) | $30/M image-out tokens; +100 tokens per partial | https://developers.openai.com/api/reference/resources/images/generation-streaming-events ; https://www.digitalapplied.com/blog/gpt-image-2-6-flare-sunburst-api-guide |
| Google `gemini-nano-banana-2.1` | HTTP (no Live API) | p50 68 s for 2K edits w/ ref, 4K tail > 4 min (third-party, 760 jobs) | see pricing page | https://ai.google.dev/gemini-api/docs/models/gemini-nano-banana-2.1 ; thenote.app link above |
| Apple Image Playground (PCC) | system sheet only | not published | free to dev; per-user quota | WWDC26-375 |

### 1c. Video / worlds

| System | Output | Rate / latency | Hardware | Source |
|---|---|---|---|---|
| **Decart Lucy 2 RT** (preview) | 720p v2v | **20 FPS** | Decart cloud | https://docs.platform.decart.ai/changelog (Jan 2026) |
| Decart realtime SDK | bidirectional ~30 fps; 1.3–2.4 Mbps each way; "good" = RTT ≤150 ms, ≥20 fps in | — | iOS 14.3 floor / iOS 15 rec. | https://docs.platform.decart.ai/integrations/network-requirements.md |
| Decart Oasis 3 Preview (world model, driving) | camera frames from actions | "under 200 ms end to end" (secondary citing Decart) | cloud; $0.02/s | https://docs.platform.decart.ai/getting-started/pricing.md ; https://apidog.com/blog/project-genie-alternatives/ |
| **StreamDiffusionV2** (MLSys 2026 best paper) | streaming v2v/t2v | TTFF < 0.5 s; **58.28 FPS (14B), 64.52 FPS (1.3B)** | 4× H100, no TensorRT/quant | https://arxiv.org/abs/2511.07399 ; https://streamdiffusionv2.github.io/ |
| Self-Forcing (Wan 1.3B causal) | t2v streaming | "real-time … sub-second latency on a single GPU" | 1 GPU | https://arxiv.org/abs/2506.08009 |
| Krea Realtime 14B (Self-Forcing from Wan 2.1 14B) | t2v / v2v | **11 fps**, 4 steps; first frames ~1 s | 1× B200 | https://www.krea.ai/blog/krea-realtime-14b |
| Krea Realtime 14B **MLX port** (SceneWorks) | same | no speed published; q4 tier 20.3 GB | Apple silicon (Mac) | https://huggingface.co/SceneWorks/krea-realtime-14b-mlx |
| **FastMetal-QAD** 1.3B (Wan2.1, INT8, 3-step DMD) | 480×832×81 frames (~5 s clip) | 110 s E2E; **45 s fast mode** (~1.8 fps [INF]); peak 3.9 GiB | Mac **M4 Max** 36 GB | https://haoailab.com/blogs/fastmetal/ |
| FastMetal-QAD 5B | 704×1280×81 | 151 s / 47 s fast | M4 Max | same |
| FastMetal-QAD 1.3B | 480p ×81 | 156 s / 58 s fast | MacBook Air M5 24 GB fanless | same |
| Odyssey-2 Pro (API) | action-conditioned world video | **new frame every 50 ms** (20 fps); 60-min connection cap (secondary) | cloud | https://documentation.api.odyssey.ml/odyssey-2-overview.md |
| Odyssey-3 / Pro | 832×480 / 1280×720 | research preview; Physics-IQ v2v 66.1 | cloud (MI355X costing) | https://odyssey.systems/meet-odyssey-3 |
| World Labs **Frameboy** (Atlas) | camera-controlled novel views | **up to 15 fps** streamed to browser | cloud GPUs | https://worldlabs.ai/blog/atlas-realtime |
| Genie 3 | 720p, 20–24 fps (secondary) | — | cloud | https://meetcody.ai/models/genie-3 |
| Genie 4 | photoreal + native audio | no fps published | cloud; waitlist | DeepMind blog (above) |
| Matrix-Game 4.0 | 864×480 neural rendering of low-poly engine frames | **67 FPS RTX 5080**, 58 FPS RTX 5070 Ti (steady, no I/O) | NVIDIA | https://github.com/SkyworkAI/Matrix-Game |
| HY-World 1.5 (WorldPlay) | keyboard/mouse world | 24 fps (secondary) | NVIDIA | https://apidog.com/blog/project-genie-alternatives/ |
| LingBot-World v1 / Infinity | interactive world | 16 fps < 1 s latency; Infinity 720p60 distilled (secondary) | NVIDIA | same |

**Bottom line of the numbers [INF]:** on Memoshi's *reference* hardware, true real-time (≥10 fps) generation exists **only in the cloud**. On-device the floor is ~1 s/image (M5-class Mac with Lightning Draft; SnapGen++-class 0.4B DiT on A18+), realistically **5–25 s on M1–M4 Macs / M1 iPad for a 4B DiT at 512²–1024²**, and **only SD-1.x/2.x-class Core ML on ANE is credible on the A16 iPhone 14 Pro** (7.9 s at 20 steps; a 1–4-step distilled UNet should land ~1–3 s [INF]).

---

## 2. Apple first-party

### 2.1 Image Playground framework (iOS/iPadOS/macOS/visionOS 27)

| Field | Detail |
|---|---|
| What | System sheet (`.imagePlaygroundSheet`, `ImagePlaygroundViewController`) backed by new PCC image model. Concepts `.text`, `.extracted(from:title:)`, `.drawing(PKDrawing)`, `sourceImage`; options `sizeSpecification`, `personalization`; styles incl. `.animation/.illustration/.sketch/.emoji/.externalProvider`. Obs (WWDC26-375). |
| Maturity | Shipping in 27 releases; **`ImageCreator` removed** (Obs, dev news 2026-06-11). |
| Apple path | `import ImagePlayground`; gate with `@Environment(\.supportsImageGeneration)`. Output = temp file URL (copy it) or `NSAdaptiveImageGlyph`. |
| On-device vs cloud | Cloud (PCC). Requires Apple Intelligence device + region + user enablement. |
| Numbers | None published. |
| License | System framework. |
| Fit / risks | ✅ Zero infra, privacy story, Genmoji for inline text. ❌ **User-in-the-loop only** — bots can't call it (conflicts with D53 "bots emit cards"). ❌ iPhone 14 Pro unsupported. ❌ Quota opaque. [INF] Use only as an optional "Make art for this card" button on Mac/M1 iPad. |
| Experiment (½ day) | Add a card action "Illustrate" that opens the sheet seeded with `.extracted(from: card.body)` + `.closest(to: cardSize)`; measure time-to-accepted-image across 10 cards on iPad M1 and Mac. **Pass:** median ≤ 15 s user-perceived and `supportsImageGeneration` false-path falls back cleanly on iPhone 14 Pro. |

### 2.2 Genmoji / `NSAdaptiveImageGlyph`
- iOS 27: Genmoji is now a style of the Image Playground sheet (`.emoji`) delivered via `onAdaptiveImageGlyphCreation` (Obs, WWDC26-375). Rendering/storage of `NSAdaptiveImageGlyph` in attributed text unchanged since WWDC24 (Obs: https://developer.apple.com/videos/play/wwdc2024/10220/).
- Fit [INF]: Memoshi's card catalog should **render** adaptive glyphs inside text blocks (store as RTFD/`NSAttributedString` data) even though bots can't *create* them.

### 2.3 Core ML Stable Diffusion (`apple/ml-stable-diffusion`)
- Repo now under `apple-aiml-research/ml-stable-diffusion`, MIT, 18k★, 128 commits; still SD 1.x/2.x/SDXL-era; Swift package `StableDiffusion` (Obs: https://github.com/apple/ml-stable-diffusion). No DiT/FLUX support observed.
- **Relevance:** the only Apple-maintained path that runs on the **ANE**, and the only one with published A16 numbers (7.9 s, 512², 20 steps). [INF] Treat as legacy-but-useful for the iPhone 14 Pro tier with a distilled UNet (SD-Turbo / LCM / SDXS-class) converted via its Python tooling.

---

## 3. On-device diffusion on Apple silicon — candidates

### 3.1 MLX-Swift distilled DiT in-process (Bonsai ternary Klein 4B; FLUX.2 Klein 4B; Z-Image Turbo)

| Field | Detail |
|---|---|
| What | Run a 4-step distilled DiT inside the app using **mlx-swift** (same runtime as D80 LLMs). Bonsai Image = FLUX.2 Klein 4B with ternary (1.58-bit) weights; Qwen3-4B 4-bit text encoder offloaded after encode; tiled VAE. Obs (HF card). |
| Maturity | Bonsai published 2026-05 (white paper), App Store "Bonsai Studio for iPhone" exists (Obs, card). turbospark shows Z-Image Turbo in a Swift MLX app (Obs). FLUX.2 Klein 4B **Apache-2.0** (Obs: https://huggingface.co/black-forest-labs/FLUX.2-klein-4B). |
| Apple path | `mlx-swift` (MIT) ≥0.30; SwiftPM; Metal GPU; iOS/iPadOS/macOS. Needs `com.apple.developer.kernel.increased-memory-limit` + `os_proc_available_memory()` checks on iOS (Obs: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit). No JIT needed (Metal kernels are precompiled/AOT-compiled by Metal, not CPU JIT) [INF]. |
| Numbers | M4 Pro 5.8 s @512² / 24.3 s @1024²; iPhone 17 Pro Max 9.4 s @512² (Obs). M2 Pro Klein 4B 42–52 s @1024² (Obs). |
| License | Bonsai Apache-2.0; FLUX.2 Klein 4B Apache-2.0; mlx-swift MIT. Z-Image / Qwen-Image / Krea 2 licenses **not verified** here. FLUX 3 Klein = FLUX Kommunity (OK for personal use). |
| Fit | ✅ Shares MLX runtime with Qwen3 (D80) → one memory manager, one Metal queue. ✅ Offline/private. ⚠️ **iPhone 14 Pro (6 GB):** 3.88 GB payload + Memoshi's LLM → must unload LLM during image gen; A16 has no GPU Neural Accelerators, so expect ≫ A19's 2.35 s/step [INF: 3–5× slower → 30–45 s @512²]. ⚠️ iPad M1 8 GB: workable at 512² [INF]. ✅ Mac: good. ⚠️ M1/M2: use bf16 not 4-bit for speed when RAM allows (Obs, Rapid-MLX #3058). |
| Experiment (2–3 days) | Build `ImageGenService` (actor) on mlx-swift loading Bonsai ternary 4B; generate 512² card backgrounds from bot-supplied prompts; LLM unloaded during gen. Measure on Mac, iPad M1, iPhone 14 Pro: s/image, peak `phys_footprint`, jetsam events, `ProcessInfo.thermalState` after 10 consecutive images. **Pass:** Mac ≤ 10 s, iPad M1 ≤ 20 s, iPhone 14 Pro ≤ 45 s **or** cleanly refuses via memory pre-check; zero jetsam; thermal ≤ `.fair` on iPad. **Fail →** iPhone tier uses §3.3 or cloud. |

### 3.2 Draw Things engine / app as a local server (Mac)

| Field | Detail |
|---|---|
| What | Fastest Apple-silicon inference engine (Metal FlashAttention, ANE+GPU split, Neural-Accelerator kernels); "Lightning Draft" ~≤1 s on M5 Max for Klein 4B/9B, Z-Image Turbo (vendor). Obs. |
| Maturity | Shipping app; open "community" repo with gRPC server + Swift CLI. Obs: https://github.com/drawthingsai/draw-things-community |
| Apple path | Embed = **GPL-3.0** (Obs) → not acceptable in-process. Isolated use: Memoshi (Mac) calls a separately-running Draw Things app / gRPCServerCLI over localhost. [INF] iOS can't spawn it (no child processes) but could call a Mac on the LAN. |
| Numbers | §1a rows (Lightning Draft; iPhone 17 Pro FLUX schnell <35 s). Harvest Season: 1.1–2× faster than mflux/mlx-serve/vpipe on M3U/M4 Pro/M5U (Obs). |
| Fit | ✅ Best Mac speed; "GPL only isolated" satisfied by process/network boundary [INF]. ❌ External dependency the user must run; not on iOS standalone. |
| Experiment (1 day) | On the Mac, run Draw Things gRPC server; write a 150-line Swift client (grpc-swift) that requests 512² Klein-4B images for 20 bot cards. **Pass:** p50 ≤ 3 s on the reference Mac, and ≥2× faster than §3.1 on the same Mac. Decide "Mac-turbo optional backend" if pass. |

### 3.3 Core ML ANE distilled UNet (iPhone 14 Pro tier)

| Field | Detail |
|---|---|
| What | SD-1.5/2.1-class UNet, step-distilled (SD-Turbo/LCM/SDXS-style) and 6-bit palettized, run via Apple's `StableDiffusion` Swift package on `.cpuAndNeuralEngine`. |
| Maturity | Apple pipeline mature but stale (SD-era). SnapGen++ (0.4B DiT, 1.8 s @1024² on iPhone 16 Pro Max) shows the SOTA ceiling, but **weights not observed as released** (project page https://snap-research.github.io/snapgenplusplus has paper links only) [INF]. |
| Numbers | iPhone 14 Pro Max SD2.1 512² 20 steps: 7.9 s (Obs). [INF] 4 steps → ~2 s denoise + ~1 s TE/VAE. |
| License | Apple package MIT; model weights vary (SD-Turbo is non-commercial research licence — fine for personal use [INF, verify]). |
| Fit | ✅ Only realistic sub-5 s on-device path on A16; ANE keeps GPU free for SwiftUI/MLX; low power [INF]. ❌ Quality well below 2026 DiTs; 512² only. |
| Experiment (2 days) | Convert a 1–4-step distilled SD UNet with `python_coreml_stable_diffusion` (6-bit), run on iPhone 14 Pro for 256²/512² card thumbnails. **Pass:** ≤ 3 s E2E @512², peak < 1.5 GB, no throttling over 20 images. |

### 3.4 Mac-only heavyweights (mflux / FLUX 3 Klein / Qwen-Image-2.1 / Krea 2)
- Python-based (mflux) → Mac only, needs embedded Python or separate process; useful as a **dev/benchmark harness**, not shipping path [INF]. FLUX 3 Klein via mflux 0.23 (4/6/8-bit) Obs. No Apple timing for FLUX 3 Klein found.
- mlx-teacache (TeaCache step-skipping, pure MLX, PyPI ~1 wk old) — quality-preserving speedup for non-distilled models (Obs: https://pypi.org/project/mlx-teacache).

---

## 4. Real-time streaming generation & how Swift consumes it

### 4.1 Decart realtime (Lucy 2.6 / Restyle 2 / Oasis 3)

| Field | Detail |
|---|---|
| What | Cloud v2v realtime editing/restyling of a live camera stream; world model Oasis 3 (driving). Obs. |
| Maturity | Production; Lucy 2.6 Oct 2026; 720p default, 1080p option; fast mode. Obs. |
| Apple path | **Native Swift SDK `DecartAI/decart-ios` (MIT)**, LiveKit WebRTC; `client.createRealtimeManager(...)`, `manager.connect(localStream:)`, `setPrompt`, reference image `Data`; iOS + macOS; ephemeral client tokens (60 s TTL). iOS floor 14.3. Obs (https://docs.platform.decart.ai/sdks/swift-realtime.md). Oasis 3 is Python gRPC SDK only (Obs, changelog). |
| Numbers | Lucy 2 RT 720p@20 fps (Obs). 1.3–2.4 Mbps/direction (Obs). Live dashboard tracks TTFF/E2E per region (Obs: https://lucy-status.decart.ai/). |
| Price | $0.01/s Restyle 2; $0.02/s Lucy 2.6 ($0.04 fast); Oasis 3 $0.02/s (Obs). |
| Fit | ✅ Only Swift-native realtime gen-video SDK found. ✅ Works on iPhone 14 Pro (decode is HW). ⚠️ Needs a token-minting backend (a tiny serverless fn) — personal use could embed key [INF; Decart warns against]. ⚠️ Cost: 10 min/day ≈ $12/day at $0.02/s. ❌ Input is a camera/video track — to "animate a card" you'd feed a synthetic `LocalVideoTrack` from a rendered SwiftUI view [INF]. |
| Experiment (1–2 days) | "Living card": render a SwiftUI card to `CVPixelBuffer` at 15 fps (`ImageRenderer`), push as LiveKit custom video source to `lucy-restyle-2` with bot-chosen prompt; display remote track in the card. **Pass:** TTFF ≤ 2 s, ≥ 15 fps sustained 60 s on iPhone 14 Pro on Wi-Fi, battery drain ≤ 2 %/min, thermal ≤ `.fair`. |

### 4.2 fal realtime (WebSocket) — FLUX.2 klein realtime and custom `@fal.realtime()` apps

| Field | Detail |
|---|---|
| What | Persistent WebSocket per session; send base64 JPEG + prompt, receive raw JPEG frames; steps 1–8; optional latent feedback loop (pseudo-video) and RIFE interpolation. Obs. |
| Apple path | `URLSessionWebSocketTask` directly (no SDK required) [INF]; fal-swift (MIT, SPM) exists, last tagged 0.5.6 (2024) — realtime coverage not verified (Obs: https://github.com/fal-ai/fal-swift). fal also lets you deploy your own realtime endpoint (Obs: https://docs.fal.ai/serverless/development/realtime). |
| Numbers | Price $0.00194/compute-s (Obs). Klein 4B on H100 ≈ 0.39 s/1024² 4-step (Obs, Rapid-MLX ref). [INF] ~3–6 fps at 768² 3-step per session. |
| Fit | ✅ Cheapest interactive image loop; ✅ img2img of a **rendered native card** = "neural skin" over SwiftUI layout (same idea as Matrix-Game 4.0's engine-plus-neural-renderer, Obs). ⚠️ Key handling; network-dependent. |
| Experiment (1 day) | Snapshot a card (`ImageRenderer`, 704²) → fal klein realtime with style prompt, steps=2, feedback 0.9; display frames. **Pass:** round-trip p50 ≤ 600 ms, p95 ≤ 1.2 s on home Wi-Fi from iPhone 14 Pro; layout/text still legible (manual check 10 cards). |

### 4.3 One-shot cloud image APIs with progressive delivery
- **OpenAI** `v1/images/generations` with `stream=true` + `partial_images` → SSE `image_generation.partial_image` (b64) then `image_generation.completed` (Obs, API ref). Swift: `URLSession.bytes(for:)` line-parse SSE [INF]. Good for "image fades in" UX inside a card. 2.6 Flare ≥ ~6 s (vendor).
- **BFL** `flux-3-image-klein` 4.5 s median, $0.009/1K (vendor) — best price/latency for non-streaming card art [INF].
- **Google** Nano Banana 2.1: no Live API, minute-scale p50 for 2K edits (third-party) → background jobs only.

### 4.4 Research-grade streaming video (server-side only)
- **StreamDiffusionV2** (Apache-2.0 per repo [not verified here]; MLSys 2026 best paper): 58–65 FPS on 4×H100, TTFF < 0.5 s (Obs). **Self-Forcing** / **Krea Realtime 14B** (11 fps 1×B200, Apache-2.0) (Obs). Apple client path = self-host + WebRTC (LiveKit Swift SDK) [INF].
- On Mac: **FastMetal-QAD** (Apache-2.0, MLX) is the best local *video* path but is offline-speed (~45 s for a 5 s 480p clip on M4 Max fast mode) (Obs). Krea Realtime 14B MLX port exists, no fps published (Obs). self-forcing-mlx is a 0-star experimental port (Obs: https://github.com/audiohacking/self-forcing-mlx).
- LTX: LTX-2.5 released 2026-08-11 (Obs: https://github.com/Lightricks/LTX-Video); no realtime claim found in primary sources this pass.

---

## 5. Interactive world models — developer availability & Apple-client path

| Model | Dev access (2026-11-11) | Transport / SDK | Apple client path [INF unless noted] | License | Fit for Memoshi |
|---|---|---|---|---|---|
| **Genie 4** (DeepMind, 2026-10-27) | Trusted testers; waitlist; "coming soon" to AI Ultra (Project Genie) + Gemini API/AI Studio early-access partners (Obs) | none public | none | proprietary | Watch only |
| Genie 3 / Project Genie | Consumer product, Google AI Ultra (Obs: https://labs.google/projectgenie) | none | — | proprietary | No |
| **Odyssey-2 Pro API** / Odyssey-3 preview | API key at developer.odyssey.ml; Odyssey-3 "get in touch" (Obs) | **JS + Python SDKs only**; client credentials for browser (Obs: llms.txt) | WKWebView hosting the JS SDK, bridge prompts via `WKScriptMessageHandler`; or reverse-engineer WebRTC (not documented) | proprietary | Best *available* interactive-video API; experiment candidate |
| **Decart Oasis 3 Preview** | Public, $0.02/s (Obs) | Python **gRPC** SDK `decart-oasis` (Obs) | grpc-swift against same protos if published [unverified] | proprietary | Driving-sim only; low fit |
| **World Labs Atlas / Frameboy / Marble** | Frameboy browser demo; Viewfinder closed beta; Marble World API (prepaid) exports splats/meshes (Obs) | Web; REST for Marble | Marble → SPZ/PLY → RealityKit/Metal splat renderer (see GenUI3DSplats slice) | proprietary; company now part of AMD | Generated *assets* (not frames) fit native rendering better |
| **Matrix-Game 4.0** | Open weights (Obs) | self-host Python, NVIDIA | stream from own GPU box via WebRTC | Apache-2.0 (v4) | Concept fit (engine + neural render) but no Apple runtime |
| HY-World 1.5/2.0, LingBot-World, Cosmos 3 | open weights (secondary) | self-host | — | mixed (HY-World excludes EU/UK/KR; LingBot Infinity NC) | No |
| Dynamics Lab Mirage | site parked (secondary) | — | — | — | Dead/unclear |

[INF] For Memoshi, a "world" is better delivered as **generated 3D assets rendered natively** (splats/meshes in RealityKit) than as streamed pixels: works offline after generation, 60/120 fps local, no per-second billing, visionOS-native.

---

## 6. Generated imagery inside cards vs full frames; caching; energy/thermal

| Concern | Recommendation | Basis |
|---|---|---|
| **What to generate** | Small, decorative assets: 256²–512² backgrounds, avatars, icons, headers; never text-bearing UI (keep text/controls native SwiftUI per D53/D68). | [INF]; quality limits on small text noted by Bonsai card (Obs) |
| **Full frames** | Only via cloud realtime (Decart/fal) and only while card is on-screen & foregrounded. | [INF] |
| **Resolution economics** | Cost scales ~quadratically w/ pixels: Bonsai iPhone 17 Pro Max 2.7 s @128², 4.0 s @256², 9.4 s @512², 34 s @1024² (Obs). Generate at 256–512² and upscale/blur for backgrounds. | Obs + [INF] |
| **Cache key** | `sha256(model_id ‖ weights_rev ‖ prompt_norm ‖ seed ‖ steps ‖ w×h ‖ style)`; store HEIC in Application Support; LRU by bytes; reuse across bots. FastMetal uses content-addressed prompt cache for text-encoder output (Obs) — also cache **text embeddings** per prompt. | Obs (FastMetal) + [INF] |
| **Placeholders** | Deterministic gradient / mesh-gradient from prompt hash immediately; swap in image with crossfade; for cloud SSE show partials. | [INF]; OpenAI partials Obs |
| **Scheduling** | Generate when app foreground; batch pre-generation only when `ProcessInfo.processInfo.thermalState <= .fair`, not Low Power Mode, ideally charging. iOS background execution is unreliable for multi-second GPU work [INF]. | — |
| **Thermals** | iPhone 16 Pro throttles after ~1 min of 1024² generation at 70 °F (Obs, Draw Things). Cap sustained gen on iPhone 14 Pro to short bursts; prefer ANE (Core ML) over GPU on iPhone for energy [INF]. | Obs + [INF] |
| **Memory** | Unload LLM (D80) before image DiT on ≤8 GB devices; use `os_proc_available_memory()` gate + increased-memory-limit entitlement (Obs). Offload text encoder after encode (Bonsai, FastMetal pattern, Obs). | Obs |
| **M1/M2 quantization trap** | 4-bit weights are ~15–20 % slower than bf16 on M1/M2-class GPUs for DiTs; no penalty on M3+ (Obs). iPad M1: prefer bf16/fp16 when memory allows. | Obs |

---

## 7. Candidate summary matrix

| # | Candidate | On-dev / cloud | Best Memoshi device | Latency class | License | Swift path maturity | Memoshi fit |
|---|---|---|---|---|---|---|---|
| A | MLX-Swift distilled DiT (Bonsai ternary Klein 4B / Klein 4B) | on-device | Mac, iPad M1 | 5–25 s | Apache-2.0 | medium (mlx-swift; Bonsai iOS app exists) | **High** |
| B | Cloud fast image + streaming partials (BFL FLUX 3 Klein / OpenAI SSE / fal klein) | cloud | iPhone 14 Pro | 0.5–6 s | API ToS | high (URLSession/WebSocket) | **High** |
| C | Decart realtime WebRTC (Lucy/Restyle) | cloud | all | 20–30 fps | SDK MIT; service proprietary | **high (official Swift SDK)** | Medium-high (living cards) |
| D | fal realtime img2img "neural skin" | cloud | all | ~sub-second/frame [INF] | API ToS | medium (raw WS) | Medium-high |
| E | Core ML ANE distilled UNet | on-device | iPhone 14 Pro | ~1–3 s [INF] | MIT pkg; weights vary | high (Apple pkg) but stale | Medium |
| F | Draw Things server (Mac, GPL isolated) | local Mac | Mac | ~1 s (M5 Max) – few s | GPL-3.0 (isolated) | medium (gRPC) | Medium (Mac turbo) |
| G | Image Playground sheet / Genmoji | PCC | Mac, iPad M1 | n/p | system | high | Low-medium (user-only) |
| H | World models (Odyssey via WKWebView; Genie 4 later) | cloud | Mac/iPad | 15–20 fps | proprietary | low | Low (watch) |
| I | Local causal video (FastMetal-QAD, Krea RT MLX) | on-device Mac | Mac ≥16–36 GB | 45 s+/clip | Apache-2.0 | low (Python MLX) | Low |

---

## 8. Ranked shortlist (this slice)

1. **On-device MLX-Swift 4-step DiT for card imagery (Bonsai ternary FLUX.2 Klein 4B; plain Klein 4B on Mac), content-hash cached, LLM-unload-aware.** — Reuses Memoshi's existing MLX runtime (D80), Apache-2.0 end-to-end, offline/private, measured 5.8 s @512² on M4 Pro and 9.4 s on A19 Pro; replaces the now-dead `ImageCreator` for bot-driven art on Mac/iPad (iPhone 14 Pro gated by memory pre-check).
2. **Cloud fast-image tier behind one `ImageProvider` protocol (BFL `flux-3-image-klein` / OpenAI SSE partials / fal klein WebSocket)** — The only way to give the A16 iPhone sub-5 s, high-quality card art; partial-image streaming and fal's WebSocket loop give "generative UI that feels live" with plain `URLSession`, no SDK lock-in.
3. **Decart realtime via the official MIT Swift SDK for opt-in "living cards" (restyle a rendered SwiftUI card or camera feed at 20–30 fps)** — The single production-grade, Swift-native realtime generative-video path today; world models (Genie 4, Odyssey, Frameboy) are not yet developer-reachable from Swift and should stay on the watch list.

Not ranked but recommended: support **rendering** `NSAdaptiveImageGlyph` and offer the Image Playground sheet as a user-initiated "Illustrate" action on supported devices; keep Core ML ANE UNet (E) as the iPhone-14-Pro offline fallback if experiment 3.1 fails its iPhone threshold.
