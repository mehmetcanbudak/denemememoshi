# Execution environments: where a bot's "computer" can run

> Landscape of the places an agent's tools, shell, browser and desktop can run: cloud sandboxes and VMs, desktop VMs for computer use, cloud browsers, and local isolation, plus how the profiled products choose among them. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries an inline source link. `(vendor claim)` = stated by the maker, not verified in code or docs. `[INFERENCE]` = our reasoning, not a sourced fact. `unknown` = searched, not found. Prices are USD list prices read on 2026-10-20 unless the page gives its own date. Per-hour figures in square brackets are our arithmetic from per-second list rates. Cold-start numbers are vendor claims unless stated otherwise; the browser cold-start medians come from Browser Use's BrowserArena table, which a competitor published ([third-party/competitor page](https://browser-use.com/cloud-browsers.md)).

## 1. Summary table

| # | Option | Class | Isolation | Persistence | GUI desktop | Cold start | Pricing / license fact (as of 2026-10-20) | Regions | SDKs | License / self-host |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | [E2B](https://e2b.dev/pricing) | Cloud sandbox | Firecracker microVM ([docs](https://docs.e2b.dev/faq/security-and-compliance.md)) | Pause/resume with memory, paused kept indefinitely and not billed; snapshots, forks, volumes (beta) | Yes, E2B Desktop (Ubuntu + VNC) | ~150 ms (vendor claim) | $0.000014/vCPU-s [$0.0504/vCPU-h], $0.0000045/GiB-s [$0.0162/GiB-h]; Hobby $0 + $100 one-time; Pro $150/mo | US default; EU, APAC on request (Pro+) | Python, JS/TS | Apache-2.0 runtime, self-hostable ([e2b-dev/runtime](https://github.com/e2b-dev/runtime)) |
| 2 | [Daytona](https://www.daytona.io/pricing) | Cloud sandbox | Container by default; Linux VM, Windows, macOS classes | Containers: stop keeps disk, archive; VMs: pause with memory, fork | Yes, Linux and Windows Computer Use + VNC; macOS via use.computer | <90 ms container create (vendor claim) | $0.0504/vCPU-h, $0.0162/GiB-h, Windows $0.0858/vCPU-h; $200 free credits | `us`, `eu`, dedicated on request | Python, TS, Ruby, Go, Java | OSS repo archived; last public tag v0.190.0 AGPL-3.0; core now private ([repo](https://github.com/daytonaio/daytona)) |
| 3 | [Modal Sandboxes](https://modal.com/pricing) | Cloud sandbox | gVisor or VM runtime | Max 24 h per sandbox; FS/dir snapshots (30 d), memory snapshots (alpha, 7 d) | No | 1-2 s (vendor claim) | $0.00003942/physical core-s [~$0.071/vCPU-h], $0.00000667/GiB-s [$0.024/GiB-h]; Starter $0 + $30/mo credits | Broad/narrow region pinning (1.15x-1.75x) | Python, JS/TS, Go | Proprietary; client Apache-2.0 |
| 4 | [Cloudflare Sandbox SDK / Containers](https://developers.cloudflare.com/containers/platform/pricing/) | Cloud sandbox | microVM per instance (hypervisor not named) | Lives while Durable Object active, inactivity timeout up to 6 h; rootfs snapshots (beta, 30 d); R2 mounts | No | 1-3 s ([docs](https://developers.cloudflare.com/containers/concepts/architecture/)) | Needs Workers Paid $5/mo; $0.000020/active vCPU-s, $0.0000025/GiB-s [$0.009/GiB-h] | Global ("Region: Earth"), no pinning described | TypeScript | SDK Apache-2.0; runtime not self-hostable |
| 5 | [Vercel Sandbox](https://vercel.com/docs/sandbox/pricing) | Cloud sandbox | Firecracker microVM | Persistent sandboxes: FS auto-snapshot on stop, auto-resume (no memory); 24 h session on Pro | No | Sub-second (vendor claim) | Active CPU $0.128/h, memory $0.0212/GB-h, $0.60/1M creations; Hobby free quota (page updated 2026-09-10) | 19 regions | JS/TS, Python | SDK Apache-2.0; service proprietary |
| 6 | [Fly Machines](https://docs.fly.io/about/pricing) | Cloud VM | Firecracker microVM | Volumes, stopped rootfs, suspend with memory (<=2 GB RAM) | No | Resume "a few hundred ms", cold ~2+ s ([docs](https://docs.fly.io/reference/suspend-resume.md)) | performance-2x 4 GB $66/mo; shared $0.0000008465/vCPU-s; no platform fee | 17 regions | REST API, flyctl | Proprietary; flyctl Apache-2.0 |
| 7 | [Fly Sprites](https://fly.io/sprites.md) | Cloud VM | Dedicated microVM | 100 GB disk, ~1 s CoW checkpoints; auto warm (memory frozen) after ~30 s idle, then cold | No | Warm 100-500 ms, cold 1-2 s (vendor claim) | CPU $0.0385/CPU-h and memory $0.021875/GB-h on actual use; warm/cold not charged for compute | unknown | JS/TS, Go, Python, Elixir | Proprietary |
| 8 | [Morph Cloud](https://cloud.morph.so/pricing) | Cloud VM | VM (hypervisor not disclosed) | Infinibranch snapshot/branch/restore of full VM; pause with memory | No | Restore <250 ms (vendor claim) | 1 MCU = $0.05 = 1 vCPU-h + 4 GB RAM-h + 16 GB disk-h; Team $40/mo | unknown | Python, TS | Proprietary; SDK Apache-2.0 |
| 9 | [Runloop](https://runloop.ai/pricing) | Cloud devbox | micro-VM (vendor claim) | Disk snapshots; suspend/resume disk only (Pro) | No | "a few seconds" (vendor claim) | $0.108/CPU-h, $0.0252/GB-h; Pro $250/mo | unknown | Python, TS | Proprietary; SDKs MIT; VPC deploy (Enterprise) |
| 10 | [Blaxel](https://blaxel.ai/pricing) | Cloud sandbox | microVM | Auto standby after ~15 s keeps memory + FS + processes, indefinitely | No | Resume <25 ms (vendor claim) | $0.0000115/GB-RAM-s [$0.0414/GB-h], CPU not billed separately; snapshot storage $0.20/GB-mo | us-pdx-1, us-was-1, eu-lon-1, eu-fra-1 | TS, Python, Go | Proprietary; SDKs MIT |
| 11 | [CodeSandbox SDK (Together AI)](https://www.together.ai/pricing) | Cloud sandbox (legacy) | Firecracker microVM | Memory snapshot, hibernation, resume <1 s (vendor claim) | Browser IDE only | Template clone <3 s (vendor claim) | Together Code Sandbox $0.0446/vCPU-h, $0.0149/GiB-h; CodeSandbox SDK marked legacy ([docs](https://docs.together.ai/docs/together-code-sandbox-legacy.md)) | unknown | TS (legacy), Python + TS (`together-sandbox`) | SDK MIT; service proprietary |
| 12 | [Northflank](https://northflank.com/pricing) | Cloud sandbox / PaaS | Kata Containers or gVisor microVM | Volumes; "no forced time limits"; no memory pause found | No | <1 s (vendor claim) | $0.01667/vCPU-h, $0.00833/GB-h, disk $0.15/GB-mo | 5 regions + BYOC (AWS, GCP, Azure, Oracle, any K8s) | JS, REST, CLI | Proprietary; BYOC; self-deployable control plane (Enterprise) |
| 13 | [Boat (formerly box.ascii.dev)](https://docs.boat.dev/llms.txt) | Cloud desktop VM | VM per sandbox, own kernel, disk, IP | No memory pause; stop keeps disk 14 d; named snapshots never expire; fork | Yes, Ubuntu desktop at 60 fps (Moonlight/WebRTC or VNC) | Ready ~2 s (OpenMausBot maintainer probe, third-party) | 2 vCPU/4 GB $0.018/h; 4 vCPU/8 GB $0.036/h; plans from $20/mo returned as sandbox time; no free tier | EU only (DE, FI, FR) | Python, TS | Proprietary |
| 14 | [Orgo](https://www.orgo.ai/pricing) | Desktop VM | VM per agent (vendor claim) | Persistent by default; suspend/resume, snapshot, clone, fork | Yes, Linux; Windows (Scale); Mac on request | "online in seconds" (vendor claim) | Starter $24/mo (annual) for 1 computer 8 GB; Growth $82/mo for 4; extra computer $32.50 | unknown | REST, npm `orgo`, CLI, MCP | Proprietary; on-prem Enterprise only |
| 15 | [Cua](https://cua.ai/pricing) / [Lume](https://github.com/trycua/cua) | Desktop VM tooling (BYO compute) | Local gVisor container default; Lume = Apple Virtualization.framework macOS/Linux VMs | Local VM disks | Yes | unknown | Cua Cloud ended 2026-10-18 ([notice](https://cua.ai/docs/cua-sdk/guides/cua-cloud-ended)); relay plans Free / Pro $18/mo / Teams $30/seat/mo | Your hardware or your AWS/GCP/Modal | Python, TS, Swift, Kotlin | SDK, Driver, Lume MIT; Spaces FSL-1.1-MIT |
| 16 | [Kasm Workspaces](https://docs.kasm.com/docs/reference/license) | Desktop streaming | Docker containers streamed via KasmVNC | Persistent profiles (detail unknown) | Yes | unknown | Community Edition free for non-commercial use, up to 5 concurrent sessions; commercial per named user or per concurrent session | Self-hosted or Kasm Cloud | REST | Proprietary platform; KasmVNC GPL-2.0 |
| 17 | [Browserbase](https://www.browserbase.com/pricing) + [Stagehand](https://github.com/browserbase/stagehand) | Cloud browser | 1 browser per VM, VM recreated per session ([docs](https://docs.browserbase.com/guides/security.md)) | Contexts persist cookies/auth; max session 6 h | Browser only | 877 ms median (competitor-published) | Developer $20/mo incl. 100 browser-h, then $0.12/h; Startup $99/mo, then $0.10/h | US East/West, EU Central, UK | Node, Python | Service proprietary; Stagehand MIT |
| 18 | [Steel](https://steel.dev/pricing) | Cloud browser | unknown | Profiles, session context; sessions <=15 min (Launch) to 24 h (Enterprise) | Browser only | 3,509 ms median (competitor-published) | $0.10/browser-h (Launch), $0.08/h (Scale $250/mo) | `us-east` only | TS, Python | [steel-browser](https://github.com/steel-dev/steel-browser) Apache-2.0, self-hostable |
| 19 | [Hyperbrowser](https://www.hyperbrowser.ai/pricing) | Cloud browser + sandboxes | unknown (sandboxes described as VMs) | Profiles (`persistChanges`) | Browser; macOS VM sandboxes in beta | 1,417 ms median (competitor-published) | Browser $0.10/h; sandboxes $0.045/vCPU-h + $0.015/GiB-h; Startup $30/mo | us-central/east/west, europe-west, asia-south | Node, Python | Proprietary |
| 20 | [Browser Use Cloud](https://browser-use.com/pricing) | Cloud browser | "fresh isolated browser per run" (vendor claim) | Profiles; sessions up to 240 min | Browser only | 493 ms median (vendor-published) | $0.02/browser-h, per minute; no subscription (page verified 2026-09-03) | US default, EU Frankfurt | SDK, REST, CDP, MCP | Cloud proprietary; [browser-use](https://github.com/browser-use/browser-use) MIT |
| 21 | [Kernel](https://www.kernel.sh/docs/info/pricing) | Cloud browser | Unikraft unikernel per browser ([docs](https://www.kernel.sh/docs/info/unikernels.md)) | Standby snapshot after 5 s idle (not billed); profiles; timeout up to 72 h | Headful + computer-control API | <20 ms (vendor claim); 318 ms median (competitor-published) | Headless ~$0.06/h, headful ~$0.48/h, idle not billed; Developer free + $5/mo credits | us-east, eu-west, ap-southeast | TS, Python, Go | Platform proprietary; [kernel-images](https://github.com/kernel/kernel-images) Apache-2.0 |
| 22 | [Anchor Browser](https://docs.anchorbrowser.io/pricing.md) | Cloud browser | unknown | Profiles, persistent volumes, fixed IP per profile; max duration configurable | Browser only | 2,800 ms median (competitor-published) | $0.05/browser-h + $0.01 per browser created; Starter $50/mo | US (Free/Starter); US/EU/Asia/AU (Growth) | Node, Python | Proprietary; on-prem Enterprise only |
| 23 | [Apple `container`](https://github.com/apple/container) + [Containerization](https://github.com/apple/containerization) | Local | One lightweight Linux VM per container (Virtualization.framework) | OCI images, volumes, `container commit` (1.6.0) | No (headless) [INFERENCE] | Sub-second (vendor claim) | Free, Apache-2.0; requires Apple silicon, macOS 26 for full networking | Local | CLI, Swift | Apache-2.0 |
| 24 | [Docker Sandboxes (`sbx`)](https://docs.docker.com/ai/sandboxes/) | Local (+ cloud) | microVM per sandbox with its own kernel and Docker daemon | Persists until `sbx rm` | Terminal/SSH | unknown | "CLI and local sandbox compute are free to use, including for commercial work"; cloud pay-as-you-go (rates not public) | Local; Docker cloud | CLI | Proprietary ([releases](https://github.com/docker/sbx-releases), no SPDX license) |
| 25 | [Docker Desktop](https://docs.docker.com/subscription/desktop-license/) | Local | Shared Linux VM + containers | Volumes | No | unknown | Paid for orgs with >=250 employees or >=$10M revenue; Pro $9-11, Team $15-16, Business $24 per user/mo ([pricing](https://www.docker.com/pricing/)) | Local | CLI, API | Proprietary app; Moby/Engine Apache-2.0 |
| 26 | [Lima](https://github.com/lima-vm/lima) / [Colima](https://github.com/abiosoft/colima) | Local | Full Linux VM (VZ on macOS, QEMU on Linux) | Persistent VM disk | Not documented | unknown | Free; Lima Apache-2.0 (CNCF incubating), Colima MIT | Local | CLI | Apache-2.0 / MIT |
| 27 | [OrbStack](https://orbstack.dev/pricing) | Local | One shared-kernel Linux VM ("not a substitute for a full VM" per [docs](https://docs.orbstack.dev/architecture)) | Persistent | No | "Starts in seconds" (vendor claim) | Free personal; Pro $8/user/mo for commercial use | Local, macOS only | CLI | Proprietary |
| 28 | [Firecracker](https://github.com/firecracker-microvm/firecracker) | Local/server primitive | KVM microVM | Pause/resume, full + diff snapshots | No display device | <=125 ms to guest init ([spec](https://github.com/firecracker-microvm/firecracker/blob/main/SPECIFICATION.md)) | Free, Apache-2.0; Linux + KVM only | Your hosts | REST API | Apache-2.0 |
| 29 | [Tart](https://github.com/openai/tart) | Local macOS/Linux VM | Virtualization.framework full VM | Persistent VM dirs, OCI push/pull, suspend | Yes (window, VNC) | unknown | FSL-1.1-ALv2 since 2026-06-05 (no Competing Use); now owned by OpenAI | Local, Apple silicon | CLI | Source-available, converts to Apache-2.0 |
| 30 | [bubblewrap](https://github.com/containers/bubblewrap) / [Landlock](https://docs.kernel.org/userspace-api/landlock.html) | Local process sandbox (Linux) | User namespaces / kernel LSM | n/a | n/a | Process spawn | Free; bubblewrap LGPL-2.1, Landlock in-kernel (GPL-2.0) | Local | CLI / syscalls | OSS |
| 31 | macOS Seatbelt (`sandbox-exec`) | Local process sandbox (macOS) | Kernel MAC policy (SBPL), same kernel, no VM | n/a | n/a | Process spawn | Built in, free; CLI marked DEPRECATED but still shipped and used by Codex and Claude Code ([open replacement request](https://github.com/apple/containerization/issues/737)) | Local | CLI / `sandbox_init` | Apple proprietary |
| 32 | [gVisor](https://gvisor.dev/docs/) / [Kata Containers](https://github.com/kata-containers/kata-containers) | Server primitive | User-space kernel / VM per container | Container-level | No | unknown | Both Apache-2.0, free; Linux only | Your hosts | OCI runtimes | Apache-2.0 |
| 33 | [Gondolin](https://github.com/earendil-works/gondolin) | Local micro-VM sandbox | Linux micro-VM per sandbox: QEMU by default, experimental libkrun backend on Hypervisor.framework | Disk checkpoints (snapshots) with resume; rootfs `readonly`, `memory` or `cow` | No desktop; Chromium can run inside with only its DevTools endpoint exposed | unknown | Free, Apache-2.0; v0.13.0 on 2026-10-04; 2,316 stars; QEMU via `brew install qemu`; ~200 MB+ guest assets fetched on first use | Local (macOS, Linux; ARM64 most tested) | TypeScript SDK + CLI | Apache-2.0 |

## 2. Classes

### 2.1 Cloud sandboxes and VMs

The cloud sandbox market has converged on hardware-VM isolation. E2B, Vercel, Fly and CodeSandbox use Firecracker ([E2B](https://docs.e2b.dev/faq/security-and-compliance.md), [Vercel](https://vercel.com/docs/sandbox/concepts), [Fly](https://fly.io/machines.md)). Cloudflare, Blaxel, Runloop, Morph and Boat say "microVM" or "VM" without naming the hypervisor. Northflank runs Kata or gVisor ([product](https://northflank.com/product/sandboxes)). Modal lets you choose gVisor or VM ([docs](https://modal.com/docs/guide/sandboxes)). Daytona is the exception: its default class is a container, with VMs as an option ([docs](https://www.daytona.io/docs/sandboxes/)).

Persistence is the axis that matters most for an always-on bot, and vendors fall into three tiers:

| Persistence tier | Providers | What survives |
|---|---|---|
| Memory-preserving pause, idle not billed | E2B ([persistence](https://docs.e2b.dev/sandbox/persistence.md): paused kept indefinitely, not billed), Blaxel standby ([overview](https://docs.blaxel.ai/Sandboxes/Overview.md)), Fly Sprites warm state ([lifecycle](https://docs.fly.io/sprites/concepts/lifecycle.md)), Morph pause, Fly Machines suspend (<=2 GB RAM), Daytona VM classes, CodeSandbox hibernation | Running processes, open shells, browser state in RAM |
| Disk-only persistence with auto-resume | Vercel persistent sandboxes ([docs](https://vercel.com/docs/sandbox/concepts/persistent-sandboxes)), Boat stop (disk kept 14 d) and snapshots, Runloop suspend, Daytona container stop/archive, Cloudflare rootfs snapshots (beta, 30 d) | Files, installed packages; processes restart |
| Lifetime-capped sessions | Modal (max 24 h), Cloudflare (inactivity timeout up to 6 h, tied to a Durable Object, [lifetime](https://developers.cloudflare.com/sandbox/concepts/lifetime/)), E2B continuous runtime 1 h Hobby / 24 h Pro (resets on pause) | Long runs must checkpoint and recreate |

Desktop GUI built in: E2B Desktop ([repo](https://github.com/e2b-dev/desktop), Apache-2.0), Daytona Computer Use on Linux and Windows ([docs](https://www.daytona.io/docs/en/computer-use.md)), Boat (60 fps Ubuntu desktop, [site](https://boat.dev/)). Every other cloud sandbox above is headless; a desktop means building an image with Xvfb + noVNC yourself [INFERENCE].

Self-hosting: only E2B ships a maintained open runtime. `e2b-dev/infra` now redirects to [e2b-dev/runtime](https://github.com/e2b-dev/runtime) (Apache-2.0), which includes "E2B Embed", a single-node self-host package that needs Linux x86-64 with KVM ([index](https://e2b.dev/index.md)). Daytona archived its OSS repo. Per its README, "As of June 2026, Daytona's core development has moved to a private codebase"; the last public tag is AGPL-3.0 ([repo](https://github.com/daytonaio/daytona)). Northflank offers BYOC at no added cost on pay-as-you-go ([pricing](https://northflank.com/pricing)), and E2B offers BYOC on Enterprise ([docs](https://docs.e2b.dev/byoc.md)).

Identity note: box.ascii.dev now redirects to Boat (boat.dev). OpenMausBot renamed Box to Boat across the repo on 2026-09-28 and calls `https://boat.dev/api/v1` ([server/boat.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/boat.ts)). Boat runs in the EU only (Germany, Finland, France), which matters for latency to US users and for data residency ([docs](https://docs.boat.dev/llms.txt)).

### 2.2 Desktop-capable VMs for computer use

- **Orgo**: persistent cloud desktops, Linux self-serve, Windows on the Scale plan, Mac on request; VNC plus a screenshot/click/type API, MCP and CLI ([pricing](https://www.orgo.ai/pricing), [docs](https://docs.orgo.ai/llms.txt)). Flat per-computer monthly pricing is easy to explain to end users. No free tier.
- **Scrapybara**: shut down. The homepage now reads "Scrapybara built computers for agents. Now we're building Capy" ([scrapybara.com](https://scrapybara.com)). Do not build on it.
- **Cua / Lume**: Cua Cloud and Fleets ended on 2026-10-18, and `on="cloud"` now errors ([notice](https://cua.ai/docs/cua-sdk/guides/cua-cloud-ended)). Cua is now bring-your-own compute: local gVisor containers, Lume macOS/Linux VMs on Apple Virtualization.framework (MIT), or your own AWS/GCP/Modal ([README](https://raw.githubusercontent.com/trycua/cua/main/README.md)). The cuabot package is marked with "known security issues, do not run". The repo has 30,287 stars as of 2026-10-20.
- **Kasm Workspaces**: self-hosted container desktops streamed to the browser with KasmVNC (GPL-2.0). The Community Edition allows up to 5 concurrent sessions for non-commercial use ([license](https://docs.kasm.com/docs/reference/license)). It suits a self-hosted team deployment more than a per-user desktop app [INFERENCE].
- **Daytona Computer Use**, **E2B Desktop** and **Boat**: see 2.1. Daytona reaches macOS through use.computer. use.computer sells macOS VMs on Mac minis at M4 $0.90/h; that price comes from a search snippet of the JS-rendered [pricing page](https://use.computer/pricing) and is unverified.
- **Hyperbrowser macOS sandboxes**: Apple-silicon VMs (beta, on request) with persistent disks. Start "can take several minutes" ([docs](https://hyperbrowser.ai/docs/sandboxes/macos.md)).
- **Reference images (self-host, free)**: Anthropic's [computer-use-demo](https://github.com/anthropics/claude-quickstarts/tree/main/computer-use-demo) (Xvfb + VNC Docker image, MIT) and OpenAI's [openai-cua-sample-app](https://github.com/openai/openai-cua-sample-app) (MIT). OpenAI hosts no CUA VM.
- **AWS Bedrock AgentCore**: Browser Tool $0.0895/vCPU-h + $0.00945/GB-h ([pricing](https://aws.amazon.com/bedrock/agentcore/pricing/)); Runtime max session 8 h ([limits](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/bedrock-agentcore-limits.html)).

macOS guests are capped: the macOS Tahoe 26 license allows "up to two (2) additional copies or instances" in VMs per Apple computer ([SLA](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf)). Virtualization.framework enforces the cap by returning `virtualMachineLimitExceeded` ([Apple docs](https://developer.apple.com/documentation/virtualization/vzerror/code/virtualmachinelimitexceeded)). A Mac can therefore host at most two macOS bot desktops at once; Linux guests are not capped [INFERENCE].

### 2.3 Browser infrastructure

| Provider | Per browser-hour | Session cap | Persistence | Self-host |
|---|---|---|---|---|
| [Browser Use Cloud](https://browser-use.com/pricing) | $0.02 (per minute) | 240 min | Profiles | Library MIT, cloud no |
| [Anchor](https://docs.anchorbrowser.io/pricing.md) | $0.05 + $0.01 per browser created | Configurable, "no upper limit" | Profiles, volumes, fixed IP | Enterprise only |
| [Kernel](https://www.kernel.sh/docs/info/pricing) | ~$0.06 headless, ~$0.48 headful; standby free | Up to 72 h after standby | Profiles, standby snapshots | kernel-images Apache-2.0 |
| [Steel](https://steel.dev/pricing) | $0.10 Launch / $0.08 Scale | 15 min to 24 h by plan | Profiles | steel-browser Apache-2.0 |
| [Hyperbrowser](https://www.hyperbrowser.ai/pricing) | $0.10 | Team default (max unknown) | Profiles | No |
| [Browserbase](https://www.browserbase.com/pricing) | $0.12 Developer / $0.10 Startup overage | 6 h | Contexts | No (Stagehand MIT) |

Every provider sells persistent logins through profiles or contexts, which is the bot-identity equivalent for browsing. CAPTCHA solving and stealth are gated to paid tiers at Browserbase, Steel and Anchor. Kernel is the only provider where an idle headful browser costs nothing (standby after 5 s, [docs](https://www.kernel.sh/docs/browsers/termination.md)). Steel and Kernel ship Apache-2.0 browser images, so Memoshi could run the same image locally and in the cloud [INFERENCE].

### 2.4 Local isolation

| Mechanism | Boundary strength | Where it fits in Memoshi |
|---|---|---|
| Seatbelt (`sandbox-exec`) on macOS; bubblewrap + seccomp on Linux | Same kernel; policy-level file and network limits | Per-command guardrail when a bot runs on the host. Codex and Claude Code both landed here. |
| Apple `container` (macOS 26, Apple silicon) | One VM per container, own kernel | Default per-bot Linux computer on modern Macs; free, Apache-2.0 |
| Gondolin (Earendil, the maker of Pi) | Linux micro-VM per sandbox; host-side HTTP/TLS egress allowlists and secret placeholders | Pi-native per-bot computer: a Pi extension runs Pi tools inside the VM; experimental |
| Docker Sandboxes `sbx` | microVM per sandbox, own Docker daemon, host-side egress proxy with credential injection | Strong option to reuse, but proprietary and needs a Docker login [INFERENCE] |
| Lima / Colima / Docker Desktop / OrbStack / Podman | Containers share one Linux VM | Fine for running bots apart from the host; weak between bots |
| Tart / Lume (Virtualization.framework) | Full VM; macOS guests capped at 2 | Local macOS desktop computer for a bot |
| Firecracker / gVisor / Kata | VM or user-space kernel | Linux servers only; relevant for a self-hosted Memoshi server, not the Mac app |
| Windows Sandbox / WSL2 | Hyper-V VM | Windows Sandbox is disposable, one instance at a time, Pro/Enterprise only ([docs](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/)); WSL2 hosts bubblewrap |

Facts behind the table:
- **Apple `container`** 1.6.0 shipped on 2026-10-20 and has 50,814 stars. Releases are roughly every 2-3 weeks and have included fixes for several security advisories ([releases](https://github.com/apple/container/releases)). Each container gets a dedicated IP via vmnet. On macOS 15 container-to-container networking is missing ([README](https://github.com/apple/container)). Memory freed in the guest is not returned to the host, so long-lived bots need periodic restarts ([technical overview](https://github.com/apple/container/blob/main/docs/technical-overview.md)).
- **Docker Sandboxes** need macOS 14+ on Apple silicon, Windows 11, or Ubuntu 24.04+ with KVM. They offer mountless, direct-mount and clone workspace modes ([architecture](https://github.com/docker/docs/blob/main/content/manuals/ai/sandboxes/architecture.md), [security](https://docs.docker.com/ai/sandboxes/security/isolation/)).
- **Codex CLI** ([repo](https://github.com/openai/codex), Apache-2.0):
  - macOS uses Seatbelt through a hard-coded `/usr/bin/sandbox-exec` (`codex-rs/sandboxing/src/seatbelt.rs` plus `.sbpl` policies).
  - Linux and WSL2 use bubblewrap, then `no_new_privs` and seccomp (`codex-rs/linux-sandbox/`). Landlock is now "legacy" because it "cannot isolate app-server Unix sockets" ([README](https://github.com/openai/codex/blob/main/codex-rs/linux-sandbox/README.md)).
  - Native Windows uses Microsoft Execution Containers (`mxc`) on 24H2+, with fallbacks to elevated sandbox users or restricted tokens (`codex-rs/windows-sandbox-rs/`).
- **Claude Code** ([docs](https://code.claude.com/docs/en/sandboxing)) sandboxes the Bash tool with Seatbelt on macOS and bubblewrap + socat + seccomp on Linux/WSL2. Network goes through a host proxy with an allowlist that is empty by default. Sandboxing is off by default, and Read/Edit/Write tools, hooks and MCP servers are not covered. The engine is [anthropics/sandbox-runtime](https://github.com/anthropics/sandbox-runtime) (`srt`, Apache-2.0, v0.0.81 as of 2026-10-20, "Beta Research Preview"). Memoshi could embed it directly [INFERENCE].
- **Tart** moved to `openai/tart` after Cirrus Labs joined OpenAI on 2026-04-07 ([cirruslabs.org](https://cirruslabs.org/)). It was relicensed to FSL-1.1-ALv2 on 2026-06-05; the FSL forbids "Competing Use" ([repo](https://github.com/openai/tart)). Lume (MIT) carries less licensing risk for macOS VMs [INFERENCE].
- **Gondolin** ([repo](https://github.com/earendil-works/gondolin), Apache-2.0, created 2026-02-03, v0.13.0 on 2026-10-04, 2,316 stars as of 2026-10-20) is Earendil's "Experimental Linux microvm setup with a TypeScript Control Plane as Agent Sandbox". Network and file access stay under host-side policy written in JavaScript: HTTP/TLS egress allowlists with request and response hooks, and secrets the guest sees only as placeholders, injected by the host for allowed hosts. It also has programmable VFS mounts, an ingress gateway, SSH, disk checkpoints with resume and custom Alpine images. A [Pi extension](https://github.com/earendil-works/gondolin/blob/main/host/examples/pi-gondolin.ts) runs Pi tools in a micro-VM with the project at `/workspace`, and a [Browser Use example](https://github.com/earendil-works/gondolin/blob/main/host/examples/browser-use.ts) runs Chromium inside the VM with only its DevTools endpoint exposed ([README](https://github.com/earendil-works/gondolin#readme)). QEMU is the default backend. The libkrun backend uses Hypervisor.framework on macOS, ships prebuilt as `@earendil-works/gondolin-krun-runner-darwin-arm64`, and is marked experimental. A bundled QEMU brings GPL-2.0 obligations [INFERENCE].

### 2.5 How profiled products choose

| Product | Model | Detail |
|---|---|---|
| Grok Bot | One persistent cloud computer per user, shared by all of that user's bots | Firecracker microVM per user ([teams](https://docs.x.ai/grok-bot/teams-and-enterprises)). Each bot gets its own screen, but screens are "not separate security boundaries"; `/workspace`, cookies and CLI credentials are shared ([computer](https://docs.x.ai/grok-bot/computer-and-apps)). Idle computers hibernate; durable disk; Reset restores the last snapshot ([security](https://docs.x.ai/grok-bot/security)). US only, no self-host or BYO image. Initial setup "can take several minutes" ([troubleshooting](https://docs.x.ai/grok-bot/troubleshooting)). No per-VM price: usage is bundled in subscriptions and metered by steps and tokens ([plans](https://cursor.com/help/grok-bot/plans)). Optional approval-gated execution on the user's local computer ([approvals](https://docs.x.ai/grok-bot/approvals-security-and-privacy)). |
| OpenMausBot | Per-bot "Works on": This computer, Local VM, Boat cloud, self-hosted VPS, or Off | Local VM is a Docker/Podman desktop container per bot (`maxInstances: 2`), not a hypervisor VM ([local-vm.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/computers/local-vm.mdx)). Auto selection never silently provisions or enables host control ([computer-selection.ts](https://github.com/milind-soni/OpenMausBot/blob/main/server/computer-selection.ts)). The app sleeps a Boat after 10 min idle, or keeps it up if a routine runs within 30 min ([cloud-and-vps.mdx](https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/computers/cloud-and-vps.mdx)). |
| Rakazo | One env var, `SANDBOX_PROVIDER` = docker, e2b, daytona, createos, boat, railway, none, plus host "this Mac" | Agent loop stays in the Rakazo worker; the sandbox only exposes lifecycle, exec, files and desktop ([sandbox-factory.ts](https://github.com/elie222/rakazo/blob/main/packages/adapters/src/sandbox-factory.ts), [computer-runtime.md](https://github.com/elie222/rakazo/blob/main/docs/computer-runtime.md)). Workspace is exported to Rakazo-owned storage, so switching provider loses only system packages. Providers billed while running are capped by `COMPUTER_MAX_ACTIVE_MS` (default 2 h). One Team Computer per workspace by default; Private Computer per bot is optional. |
| Lorca | No sandbox; bots run on a user-owned "Runner" (any paired desktop or VPS running the `lorca` CLI) | "The policy gates the CLI's own tools and is no OS sandbox" ([bot-permissions.md](https://github.com/egoist/lorca/blob/main/docs/architecture/bot-permissions.md), [devices.mdx](https://github.com/egoist/lorca/blob/main/web/content/docs/devices.mdx)). |
| Hermes Agent | `terminal.backend` = local, docker, ssh, modal (or Nous-managed Modal), daytona, vercel_sandbox, singularity, plus plugins | Docker defaults to one persistent container. Modal and Vercel snapshot the filesystem on cleanup and restore it the next session; no live processes survive on cloud backends ([configuration.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/configuration.md), [terminal_env_registry.py](https://github.com/NousResearch/hermes-agent/blob/main/agent/terminal_env_registry.py)). |
| OpenClaw | Gateway on host; tool sandbox configured by mode (off/non-main/all) x scope (agent/session/shared) x backend (docker, podman, ssh, openshell, crabbox) | Off by default. Network defaults to `none`; `workspaceAccess` none/ro/rw; optional sandbox browser container with noVNC; Crabbox leases throwaway Daytona machines ([modes-scope-and-backend.md](https://github.com/openclaw/openclaw/blob/main/docs/gateway/sandboxing/modes-scope-and-backend.md), [sandbox.md](https://github.com/openclaw/openclaw/blob/main/docs/gateway/config-agents/sandbox.md)). |

Related runtime choices among big-tech products:
- **Claude Cowork** runs in Anthropic's cloud by default. Its local mode uses a dedicated Linux VM through Virtualization.framework on macOS or Hyper-V on Windows ([support](https://support.claude.com/en/articles/14479288-claude-cowork-desktop-architecture-overview)).
- **Manus** pairs per-task temporary VMs with a paid persistent "Cloud Computer" ([help](https://help.manus.im/en/articles/15392111-what-is-the-cloud-computer)).
- **Gemini Spark** reportedly runs on dedicated Google Cloud VMs ([press](https://techcrunch.com/2026/05/19/google-introduces-gemini-spark-a-24-7-agentic-assistant-with-gmail-integration/)).

Two shapes dominate [INFERENCE]:
- **Vendor-hosted persistent VM per user, shared by that user's bots**: Grok Bot, Manus Cloud Computer, the hosted MausBot Cloud.
- **An OSS provider seam** that puts one interface in front of Docker plus E2B, Daytona, Boat, Modal, Vercel and others: Rakazo, Hermes, OpenClaw, OpenMausBot.

Boat appears in two seams (OpenMausBot, Rakazo) and Daytona in three (Rakazo, Hermes, OpenClaw via Crabbox).

## 3. Cost model for N always-on bots

All numbers below are [INFERENCE]: our arithmetic on the list prices cited in section 1.

Assumptions:
- N = 5 bots, each with its own computer sized 2 vCPU / 4 GiB RAM / 20 GB disk. That matches Rakazo's E2B template ([e2b-template.ts](https://github.com/elie222/rakazo/blob/main/packages/adapters/src/e2b-template.ts)); Boat's "small" size is the same.
- A month is 730 h.
- Scenario A, 24/7: computers never pause.
- Scenario B, on-demand: each bot is active 2 h/day (60 h/month) for chats and routines, then paused or snapshotted. Provider-specific idle states are used where they exist.
- Where only active CPU is billed (Vercel, Cloudflare, Sprites), we assume 10% average CPU utilisation in A and 30% while active in B.
- Excluded: LLM tokens, egress, browsers (priced separately below), taxes, and enterprise discounts.

| Provider | Hourly rate for 2 vCPU / 4 GiB | A: 5 bots 24/7 per month | B: 5 bots x 60 h per month | Notes |
|---|---|---|---|---|
| E2B | 2x$0.0504 + 4x$0.0162 = $0.166 | $604 + Pro $150 = ~$754 (24 h max continuous runtime needs Pro) | ~$50; paused is free, Hobby $0 base | Memory-preserving pause; best fit for B |
| Daytona | $0.166 (same rates) | ~$605 + small storage | ~$50 | Container class has no memory pause |
| Modal | ~$0.142 + $0.096 = $0.238 | ~$868 | ~$71 minus $30/mo credits = ~$41 | 24 h max sandbox lifetime |
| Runloop | $0.216 + $0.101 = $0.317 | ~$1,156 + Pro $250 | ~$95 (suspend needs Pro $250) | Most expensive list rate |
| Blaxel | 4 GB x $0.0414 = $0.166 | ~$604 | ~$50 + standby storage (~14 GB x $0.20 = ~$2.80/bot) = ~$64 | Standby keeps processes |
| Morph | 2 MCU/h x $0.05 = $0.10 | ~$365 | ~$30 | Full-VM snapshots |
| Vercel Sandbox | 4x$0.0212 + active CPU | ~$310 memory + ~$93 CPU = ~$403 | ~$25 memory + ~$23 CPU = ~$48, + snapshot storage ~$4; Pro $20/mo credit | Disk-only resume; 24 h session cap |
| Cloudflare Containers | 4x$0.009 + active CPU | ~$131 memory + ~$53 CPU + $5 = ~$189 | ~$11 memory + ~$13 CPU after plan inclusions + $5 = ~$28 | No memory persistence; 6 h inactivity cap |
| Northflank | 2x$0.01667 + 4x$0.00833 = $0.067 | ~$243 + disk $15 = ~$258 | ~$20 + disk | Lowest per-vCPU list rate; no memory pause found |
| Fly Machines | performance-2x 4 GB = $66/mo flat | ~$330 | Suspend applies only up to 2 GB RAM, so B needs smaller machines | Shared-CPU machines are much cheaper |
| Fly Sprites | Billed on actual CPU and RAM use | ~$150-200 if kept awake (~$0.04/h at 10% CPU, 1.5 GB) | ~$18 (warm/cold idle not charged for compute) | Fixed 8 vCPU ceiling; no GUI |
| Boat | $0.018/h (small) | 5 x $13.14 = ~$66 | ~$5.40 usage, but the minimum plan is $20/mo, so $20 | Includes a desktop; EU only |
| Orgo | Flat per computer | Growth $82 + 1 extra $32.50 = ~$115 (annual billing) | Same, flat | Includes desktop; 8 GB computers |
| Grok Bot | Bundled | One VM per user, shared by all bots; usage metered in steps and tokens | Hibernates automatically | Not comparable per VM |
| Local (Apple `container` / Docker Sandboxes) | $0 marginal | Host needs ~20 GB RAM free for 5 x 4 GB VMs | Same | Hardware and electricity only |

Optional cloud browser for scenario B, assuming 5 bots x 60 browser-hours = 300 h/month:
- Browser Use: $6.
- Anchor: ~$15 plus creation fees.
- Kernel headless: ~$18; headful: ~$144, with idle free.
- Steel Launch: $30.
- Browserbase Developer: $20 + 200 h x $0.12 = $44.

Takeaways from the model [INFERENCE]:
1. Keeping a Linux computer awake 24/7 on a per-second sandbox (E2B, Daytona, Blaxel, Modal) costs about $120-175 per bot per month at 2 vCPU / 4 GiB. That is close to the price of a consumer AI subscription for each bot.
2. With memory-preserving pause (E2B, Blaxel, Sprites, Morph), an on-demand bot costs about $4-14 per month, and resume takes milliseconds to a few seconds. The products already behave this way: Grok Bot hibernates idle computers, and OpenMausBot sleeps a Boat after 10 minutes.
3. Flat-priced desktop VMs (Boat at $13/bot-month 24/7, Orgo at ~$23-32/computer-month) beat per-second sandboxes for always-on bots. They trade away region choice (Boat is EU-only) or flexibility.
4. Sharing one computer across all of a user's bots, as Grok Bot does, divides the always-on cost by N. The price is that bots stop being security boundaries from each other.

## 4. Options for Memoshi

Design premise: local-first by default, with an optional cloud computer per bot. The products that handle this best put a provider seam under a Memoshi-owned workspace. Rakazo's `SandboxProvider` (lifecycle, exec, files, desktop) and Hermes's terminal-backend registry both keep the agent loop outside the sandbox and treat the computer as a replaceable tool host ([Rakazo computer-runtime.md](https://github.com/elie222/rakazo/blob/main/docs/computer-runtime.md)).

| Option | What | Pros | Cons |
|---|---|---|---|
| L0. Host + policy sandbox | Bot tools run on the user's machine, wrapped per command by Seatbelt on macOS or bubblewrap + seccomp on Linux, ideally by embedding `srt` (Apache-2.0) | Zero setup; full access to the user's apps and files when allowed; the approach Codex and Claude Code use | Same kernel; `sandbox-exec` is deprecated; no protection for GUI or computer use; all bots share one host identity |
| L1. Per-bot local Linux VM | Apple `container` on macOS 26 (one VM per container, Apache-2.0); Gondolin (Apache-2.0, Pi's own micro-VM sandbox with host-side egress and secret policy, experimental); Docker Sandboxes `sbx`, Podman or WSL2 elsewhere; image includes Xvfb + noVNC + Chromium for a bot desktop | Real kernel boundary per bot; free; works offline; image is portable to cloud providers; Gondolin adds secrets by placeholder and egress allowlists out of the box | Needs Apple silicon and macOS 26 for the best path; RAM cost (~4 GB per awake bot); bot stops when the laptop sleeps; guest memory not returned to the host |
| L2. Local macOS VM | Lume (MIT) or Tart (FSL, OpenAI-owned) on Virtualization.framework | A Mac desktop for macOS-only apps | Hard cap of 2 macOS VMs per Mac; large images; licensing risk with Tart |
| L3. User-owned runner | Lorca-style pairing of another Mac, home server or VPS running a headless Memoshi runner | Always on without vendor bills; data stays with the user | No isolation unless combined with L0 or L1; the user maintains the hardware |
| C1. Per-bot cloud sandbox, pause-first | Adapter seam with E2B first (Apache-2.0 runtime, self-hostable, memory pause, desktop template), then Daytona or Blaxel or Sprites | Survives the laptop sleeping; routines and webhooks run at any time; ~$4-14/bot-month when on-demand | Per-second billing gets expensive if bots never pause; needs lifecycle discipline (idle sleep, max-active caps as in Rakazo); vendor churn (Cua Cloud and Scrapybara shut down in 2026, Daytona went closed-source) |
| C2. Flat cloud desktop | Boat or Orgo adapter for bots that need a GUI | Cheapest always-on desktop; computer-use APIs and live view built in | Boat EU-only and proprietary; Orgo has no free tier; flat plans complicate per-bot billing |
| C3. Shared per-user cloud computer | One VM per user with a screen per bot, as in Grok Bot | 1/N cost; bots share logins and files | Bots are not isolated from each other, so a prompt-injected bot can reach every other bot's credentials |
| B. Browser layer | Per-bot persistent Chromium profile locally by default; optional Kernel, Browser Use or Steel cloud browsers for always-on routines | Cheap ($0.02-0.12/h); profiles act as durable bot identity | CAPTCHA and stealth cost extra; logins live with the vendor |

Recommended shape [INFERENCE]:
1. **Default to L0 for chat-only and file bots, and L1 for bots that run code or the browser.** Store each bot's workspace and browser profile in a Memoshi-owned directory that is mounted into the VM. That way the computer is disposable and moving it between local and cloud is a sync, not a migration, which is Rakazo's pattern.
2. **Make cloud an opt-in per bot ("keep this bot awake in the cloud") behind a provider seam.** E2B is the first adapter because of its open runtime, memory-preserving pause that is free while paused, and desktop template. Boat is the cheap desktop option for EU users. Apply OpenMausBot's lifecycle defaults: sleep after 10 minutes idle, wake on routine or webhook, never silently provision.
3. **Show estimated monthly cost per bot in the UI before enabling cloud.** The gap between ~$120-175 per bot-month 24/7 and ~$4-14 per bot-month on-demand is large enough that users should see it.
4. **Avoid a shared multi-bot computer as the default.** Grok Bot's own docs say its per-bot screens are not security boundaries. Per-bot isolation is a differentiator Memoshi can offer at low cost locally.

## Open questions

- Grok Bot VM specs (vCPU, RAM, disk) are not published. Grok Bot account owners could check the in-app computer settings.
- Cloud pricing for Docker Sandboxes is visible only in the console. A Docker account is needed to find out.
- Hypervisors for Cloudflare, Blaxel, Runloop, Morph and Boat are undisclosed. Ask the vendors or check `/proc/cpuinfo` and `dmesg` inside a trial sandbox.
- The Fly Sprites plans conflict: [sprites.md](https://fly.io/sprites.md) lists a Hero plan, while [pricing.md](https://fly.io/pricing.md) says "No plans and no tiers".
- Self-serve CodeSandbox prices could not be read (HTTP 403), and Kasm commercial prices come only from checkout snippets and a third-party listing.
- No sourced cold-start figures exist for Apple `container`, Lima, Tart or Docker Sandboxes. A local benchmark on a macOS 26 Mac would settle them.

## Sources

1. https://e2b.dev/pricing
2. https://docs.e2b.dev/sandbox/persistence.md
3. https://docs.e2b.dev/faq/security-and-compliance.md
4. https://github.com/e2b-dev/runtime
5. https://github.com/e2b-dev/desktop
6. https://www.daytona.io/pricing
7. https://www.daytona.io/docs/sandboxes/
8. https://www.daytona.io/docs/en/computer-use.md
9. https://github.com/daytonaio/daytona
10. https://modal.com/pricing
11. https://modal.com/docs/guide/sandboxes
12. https://developers.cloudflare.com/containers/platform/pricing/
13. https://developers.cloudflare.com/sandbox/concepts/lifetime/
14. https://developers.cloudflare.com/containers/concepts/architecture/
15. https://vercel.com/docs/sandbox/pricing
16. https://vercel.com/docs/sandbox/concepts/persistent-sandboxes
17. https://docs.fly.io/about/pricing
18. https://docs.fly.io/reference/suspend-resume.md
19. https://fly.io/sprites.md
20. https://docs.fly.io/sprites/concepts/lifecycle.md
21. https://cloud.morph.so/pricing
22. https://runloop.ai/pricing
23. https://blaxel.ai/pricing
24. https://docs.blaxel.ai/Sandboxes/Overview.md
25. https://www.together.ai/pricing
26. https://docs.together.ai/docs/together-code-sandbox-legacy.md
27. https://northflank.com/pricing
28. https://northflank.com/product/sandboxes
29. https://docs.boat.dev/llms.txt
30. https://boat.dev/
31. https://www.orgo.ai/pricing
32. https://docs.orgo.ai/llms.txt
33. https://scrapybara.com
34. https://cua.ai/pricing
35. https://cua.ai/docs/cua-sdk/guides/cua-cloud-ended
36. https://raw.githubusercontent.com/trycua/cua/main/README.md
37. https://docs.kasm.com/docs/reference/license
38. https://hyperbrowser.ai/docs/sandboxes/macos.md
39. https://aws.amazon.com/bedrock/agentcore/pricing/
40. https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/bedrock-agentcore-limits.html
41. https://github.com/anthropics/claude-quickstarts/tree/main/computer-use-demo
42. https://github.com/openai/openai-cua-sample-app
43. https://www.browserbase.com/pricing
44. https://docs.browserbase.com/guides/security.md
45. https://github.com/browserbase/stagehand
46. https://steel.dev/pricing
47. https://github.com/steel-dev/steel-browser
48. https://www.hyperbrowser.ai/pricing
49. https://browser-use.com/pricing
50. https://browser-use.com/cloud-browsers.md (competitor-published benchmark)
51. https://www.kernel.sh/docs/info/pricing
52. https://www.kernel.sh/docs/info/unikernels.md
53. https://www.kernel.sh/docs/browsers/termination.md
54. https://github.com/kernel/kernel-images
55. https://docs.anchorbrowser.io/pricing.md
56. https://github.com/apple/container
57. https://github.com/apple/container/releases
58. https://github.com/apple/container/blob/main/docs/technical-overview.md
59. https://github.com/apple/containerization
60. https://github.com/apple/containerization/issues/737
61. https://docs.docker.com/ai/sandboxes/
62. https://docs.docker.com/ai/sandboxes/security/isolation/
63. https://github.com/docker/docs/blob/main/content/manuals/ai/sandboxes/architecture.md
64. https://github.com/docker/sbx-releases
65. https://docs.docker.com/subscription/desktop-license/
66. https://www.docker.com/pricing/
67. https://github.com/lima-vm/lima
68. https://github.com/abiosoft/colima
69. https://orbstack.dev/pricing
70. https://docs.orbstack.dev/architecture
71. https://github.com/firecracker-microvm/firecracker
72. https://github.com/firecracker-microvm/firecracker/blob/main/SPECIFICATION.md
73. https://github.com/openai/tart
74. https://cirruslabs.org/
75. https://www.apple.com/legal/sla/docs/macOSTahoe.pdf
76. https://developer.apple.com/documentation/virtualization/vzerror/code/virtualmachinelimitexceeded
77. https://github.com/containers/bubblewrap
78. https://docs.kernel.org/userspace-api/landlock.html
79. https://gvisor.dev/docs/
80. https://github.com/kata-containers/kata-containers
81. https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/
82. https://github.com/openai/codex
83. https://github.com/openai/codex/blob/main/codex-rs/linux-sandbox/README.md
84. https://code.claude.com/docs/en/sandboxing
85. https://github.com/anthropics/sandbox-runtime
86. https://docs.x.ai/grok-bot/teams-and-enterprises
87. https://docs.x.ai/grok-bot/computer-and-apps
88. https://docs.x.ai/grok-bot/security
89. https://docs.x.ai/grok-bot/troubleshooting
90. https://docs.x.ai/grok-bot/approvals-security-and-privacy
91. https://cursor.com/help/grok-bot/plans
92. https://github.com/milind-soni/OpenMausBot/blob/main/server/boat.ts
93. https://github.com/milind-soni/OpenMausBot/blob/main/server/computer-selection.ts
94. https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/computers/local-vm.mdx
95. https://github.com/milind-soni/OpenMausBot/blob/main/apps/docs/content/docs/computers/cloud-and-vps.mdx
96. https://github.com/elie222/rakazo/blob/main/packages/adapters/src/sandbox-factory.ts
97. https://github.com/elie222/rakazo/blob/main/docs/computer-runtime.md
98. https://github.com/elie222/rakazo/blob/main/packages/adapters/src/e2b-template.ts
99. https://github.com/egoist/lorca/blob/main/docs/architecture/bot-permissions.md
100. https://github.com/egoist/lorca/blob/main/web/content/docs/devices.mdx
101. https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/configuration.md
102. https://github.com/NousResearch/hermes-agent/blob/main/agent/terminal_env_registry.py
103. https://github.com/openclaw/openclaw/blob/main/docs/gateway/sandboxing/modes-scope-and-backend.md
104. https://github.com/openclaw/openclaw/blob/main/docs/gateway/config-agents/sandbox.md
105. https://support.claude.com/en/articles/14479288-claude-cowork-desktop-architecture-overview
106. https://help.manus.im/en/articles/15392111-what-is-the-cloud-computer
107. https://techcrunch.com/2026/05/19/google-introduces-gemini-spark-a-24-7-agentic-assistant-with-gmail-integration/ (press)
108. https://use.computer/pricing (search snippet only)
109. https://github.com/earendil-works/gondolin
110. https://www.npmjs.com/package/@earendil-works/gondolin-krun-runner-darwin-arm64
