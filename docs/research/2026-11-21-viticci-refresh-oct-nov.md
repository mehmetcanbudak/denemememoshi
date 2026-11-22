# Viticci on X refresh: 21 October → 21 November 2026

**Status:** Research · 2026-11-21
**Owns:** Follow-up sweep of Federico Viticci's (`@viticci`) public X activity after the [2026-10-21 full record](2026-10-21-viticci-full-record-sep-oct.md) (cutoff: 2026-10-21 19:14 UTC) through 2026-11-21, focusing on his 'Apple Bots' (`Cobots-Native`) app, MacRemote, his Apple CLIs, and related screenshots.
**Extends:** [Viticci 'Apple Bots' record](2026-10-21-viticci-apple-bots-record.md) · [Viticci full record (1 Sep → 21 Oct)](2026-10-21-viticci-full-record-sep-oct.md) · [Viticci follow-ups](2026-10-22-viticci-followups.md)

Research is evidence, not decisions ([index](README.md)). Labels: **Observed** (seen in post text or downloaded media), **Claim** (stated by Viticci), **[INFERENCE]** (our reasoning).

---

## 1. Coverage & Limits

- **Media tab (`api.fxtwitter.com/2/profile/viticci/media`):** Complete from **2026-10-21 19:14 UTC → 2026-11-21** (4 pages, reaching back to 15 Oct). Captures every post/reply with images or videos in the gap.
- **Posts + replies (`with_replies=true`):** Complete from **2026-11-13 07:02 UTC → 2026-11-21** (5 pages; page 6 returned HTTP 404 from FxEmbed). Text-only replies between 22 Oct and 12 Nov are not included in this sweep.
- **Total unique items merged after 2026-10-21 19:14 UTC:** 131 authored by `@viticci` + 70 other/reposts.

---

## 2. Key Project Updates (21 Oct → 21 Nov 2026)

| UTC | Post | What's new | Media |
|---|---|---|---|
| 12 Nov 20:15 | [2120973771922403372](https://x.com/viticci/status/2120973771922403372) | `@ChatGPT your dot still doesn't have this tho` | 1 photo |
| 13 Nov 19:00 | [2121317231204442618](https://x.com/viticci/status/2121317231204442618) | **MacRemote beta launch** (Club MacStories Weekly 537; open source soon): *"Claude, ChatGPT, and other agents live in the cloud. But your best tools are on your Mac. MacRemote bridges the two. One slick Mac app, and you decide exactly what gets shared via a secure tunnel."* | 1 photo (MacRemote banner/icon) |
| 13 Nov 19:06 | [2121318820132643152](https://x.com/viticci/status/2121318820132643152) | **Cobot on iPhone Duo using MacRemote via MCP:** *"A native iOS agent, based on Pi Durable, totally sandboxed, but able to reach my Mac via MCP? Yep. I've been using MacRemote for 6 months now, and I love it so much."* | 1 photo (iPhone Duo unfolded screenshot of Cobot) |
| 13 Nov 19:10 | [2121319774189736336](https://x.com/viticci/status/2121319774189736336) | **Apple CLIs + MCPs:** NotesCTL final beta out, nearing public release; launching Apple Mail (`MailCTL`) and Photos (`PhotoCTL`) CLIs + MCPs alongside it. | 2 photos |
| 14 Nov 17:13 | [2121652692674330802](https://x.com/viticci/status/2121652692674330802) | Early Club member feedback on MacRemote beta. | 1 photo |
| 18 Nov 19:44 | [2123140430506160451](https://x.com/viticci/status/2123140430506160451) | Reflects on custom tools built in H1 2026 paying off at MacStories. | 3 photos |
| 19 Nov 19:29 | [2123498930206089381](https://x.com/viticci/status/2123498930206089381) | Praises Gemini 4 Neon for assistant tasks, research, and code review (using "Gemini 4 Neon High in T3 Code"). | 3 photos |
| 20 Nov 19:08 | [2123856109043929439](https://x.com/viticci/status/2123856109043929439) | **Approaching TestFlight (45 days, 530 PRs):** *"I've been building my first iOS app for the past 45 days. 530 PRs later, I'm approaching TestFlight. Here's my @t3dotcodes setup with a fleet of Macs (832 GB RAM pool), agents, simulators, and my fork of @poteto's pstack that is making it happen."* Links Club MacStories Weekly 538. | 4 photos (macOS Cobot app + T3 Code `Cobots-Native` PR #533) |

---

## 3. Observed UI & Architecture Details from New Screenshots

### 3.1 iPhone Duo / iPadOS screenshot ([2121318820132643152](https://x.com/viticci/status/2121318820132643152), 13 Nov)
- **Layout:** Two-column split on unfolded iPhone Duo, plus a floating vertical tab pill on the right edge (Chats, Bot, Groups, Search).
- **Sidebar:** `Today` (`30 done >`), 3×3 pinned bot grid (`Pixel`, `Cobot`, `ClubBot`, `Builder`, `Researcher`, `Proofer`, `Linker`, `MacStories Coder`, `MacStories QA`).
- **Mac-hosted indicator:** `Builder`, `MacStories Coder`, and `MacStories QA` carry a black circular **Mac display badge** on their avatars, visually distinguishing Mac-hosted bots from on-device/cloud bots.
- **Group chats:** Pinned multi-bot rooms below the grid (`Feeeboard`, `MacStories Articles`) with clustered bot avatars.
- **Chat & MCP:** `Cobot` header shows `🔓 Bypass` permission badge and `GPT-6.1 Sol · Fast`. Prompt uses an inline `@MacRemote` MCP pill (`Get my tasks due today with [MacRemote]`). Shows collapsible `Worked 51s · 2 steps >` summary.
- **Composer:** Model pill (`GPT-6.1 Sol`), reasoning effort pill (`High`), speed tier (`Fast`), voice mode waveform, and dictation mic.

### 3.2 macOS screenshot ([2123856109043929439](https://x.com/viticci/status/2123856109043929439) photo 1, 20 Nov)
- **Visual palette:** Warm ivory/cream canvas with warm amber user message bubbles.
- **Sidebar sections:** `Search Everything`, `Today`, `Waiting for You`, `Library`, `My Apps`, `Bookmarks`, `Activity`; `Pinned` 3×3 bot grid; pinned group chats (`Feeeboard`, `MacStories Articles`); `Bots` list (`WeatherBot`, `Health Coach`).
- **Inter-bot messaging & file confirmation:** Transcript in `Proofer` (`Claude Opus 5.5`) shows a `Messaged ClubBot` card, inline diff block, and inline file-change confirmation/undo rows (`Not Confirmed: draft_checked.md · Size 2 KB -> 10 KB Undo`).

### 3.3 T3 Code / `Cobots-Native` screenshot ([2123856109043929439](https://x.com/viticci/status/2123856109043929439) photo 4, 20 Nov)
- **Progress:** `Cobots-Native` is at **PR #533** (up from PR #14 in the October record).
- **Panels/features mentioned in PR #533:** `Activity`, `Links`, `Live Captions`, `project tasks`, `model picker`, `context lens`, `Library`, `Listen`, plus a `global, floating quick entry` task in the sidebar.
- **Review workflow:** Uses dual model reviewers (`Opus 5.5` and `Gemini 4 Neon at xhigh`).
- **Other projects visible in T3 Code sidebar:** `frames-cli`, `bookeeper` (MacStories Bookkeeping App), and `Stacks`.

### 3.4 Transcript close-up ([2123498930206089381](https://x.com/viticci/status/2123498930206089381) photo 1, 19 Nov)
- Shows `ClubBot` running `Gemini 4 Neon` (`High`, `Fast`) on the warm ivory/amber theme: warm amber user bubble, `Worked 53s · 1 step >` with brain + `{}` icons, crisp white assistant card with subtle border, timestamp + retry button (`8:16 PM ↻`), and composer pills.

### 3.5 Notable thread replies (13 Nov & 20 Nov)
- **MailCTL safety ([2121321101796008358](https://x.com/viticci/status/2121321101796008358)):** Confirmed MailCTL only creates drafts (*"Yep, only make drafts."*).
- **Parallel T3 Code workflow ([2124096212148060261](https://x.com/viticci/status/2124096212148060261), [2124064557845082601](https://x.com/viticci/status/2124064557845082601)):** Prefers splitting work into parallel units across threads rather than a single long thread, running up to ~30 simulators across his 5-Mac fleet (M5 Ultra, M3 Ultra, M5 Pro mini, PROLED MacBook Pro, old MBP).
