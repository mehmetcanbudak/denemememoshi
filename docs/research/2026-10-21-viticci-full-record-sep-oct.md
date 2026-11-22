# Viticci on X, 1 September → 21 October 2026: the full record, and how 'Apple Bots' works without the Mac

**Status:** Research · 2026-10-21
**Owns:** Every post, reply, quote, repost, photo and video Federico Viticci published on X from 1 September to 21 October 2026 (19:14 UTC), what they show about his 'Apple Bots' app and its device architecture, and whether the iPhone app works while his Mac is off.
**Extends:** [Viticci 'Apple Bots' record](2026-10-21-viticci-apple-bots-record.md) (23 Sep → 21 Oct). Both stay valid; where they overlap, this record adds coverage and corrects three points (§9).
**Depends on:** [Native Apple direction](2026-10-20-native-apple-direction.md) · [Pi brain refresh](2026-10-20-pi-brain-refresh.md) · [NEXT_VERSION](../plan/NEXT_VERSION.md) (proposed) · [decisions](../plan/decisions.md) (binding)
**Companion:** [Complete item index](2026-10-21-viticci-x-index.md), one row per item.
**Mirrored in:** `~/Documents/memoshi/Pi_Swift/docs/research/`. Edit this copy first, then copy it across.

Research is evidence, not decisions ([index](README.md)).

**Labels:**
- **Observed:** seen in a primary source, such as post text, a pixel or video frame, an Apple page or an article.
- **Claim:** stated by Viticci, by on-screen text his agents wrote, or by another maker. Not verified.
- **[INFERENCE]:** our reasoning.

All times are UTC. Personal details in his screenshots are summarised, not quoted.

---

## 1. Summary

1. **Coverage is complete for his own X activity, 1 Sep → 21 Oct 19:14 UTC** (Observed).
   - 516 authored items: 146 posts, 276 replies, 81 quotes, 13 self-replies. There are also 108 reposts.
   - 23 authored items concern the app. None does before 29 September.
   - Bluesky (27 items) and Mastodon (54 items) since 1 September carry nothing about the app.
2. **He first stated the product he wanted on 22 September** (Claim). The post ([2102463157029495285](https://x.com/viticci/status/2102463157029495285)) reads: "I want Grok Bot, but with GPT-6 models, and with Claude's taste, and with Muse's speed, and with GPT-Live voice".
3. **Before building it, he lived in four agent setups at once** (Observed):
   - [Open Minis](https://www.macstories.net/reviews/open-minis-is-the-ios-agent-i-wish-siri-ai-could-be/), an on-device iPhone agent;
   - Hermes Agent on an always-on Mac Studio with local models, driven from the iPhone through the Cadu app;
   - Grok Bot plus Cursor cloud agents as his "always-on (cloud-based)" team;
   - Codex Remote and T3 Code as remote controls for his Macs.
4. **The app was built iPhone- and iPad-first.** The Mac version came later (Observed, with one [INFERENCE]).
   - 29 Sep: "one that I'm building".
   - 3 Oct: "My first iOS app!".
   - 9 Oct: his coding agent reports a feature "Merged and on your iPhone and iPad".
   - 20 Oct: the first post that says "running on macOS".
   - The 8–9 October window screenshots read "Touch and hold a bot … a tap away" and set an AlarmKit alarm that "rings even in Silent mode". That makes them the iPad build in iPadOS windowing, not a Mac [INFERENCE].
5. **The iPhone app runs its own agent and does not need the Mac** [INFERENCE, strongly supported]:
   - Its bots call cloud models directly, configured with his own keys (GPT-6.1 Sol, Claude Opus 5.5, an xAI key for voice).
     - **Corrected 2026-10-22:** only the xAI API key that voice needs is shown. How GPT-6.1 Sol and Claude Opus 5.5 are signed in is not shown. He uses his ChatGPT plan in other apps (Open Minis "via Codex sub"; T3 Code's "Sign in with ChatGPT") ([follow-ups §2.1](2026-10-22-viticci-followups.md#21-what-viticci-shows)).
   - They use on-device Apple frameworks: Reminders, Health, Music, Shazam, HomeKit, WeatherKit, Photos, Maps and AlarmKit.
   - The one video shows a turn on the iPhone surviving a force-quit (§6.3). It matches Apple's documented behaviour for a `BGContinuedProcessingTask`: the system cancels the task when the app is closed in the app switcher, and the durable store resumes it on relaunch. A turn hosted on a Mac would not have failed when the phone app was killed.
6. **The Mac is a second host for some bots and for Mac-only tools** (Observed):
   - On 20 October the macOS build shows a bot, Builder, labelled "On Federico's Mac Studio". Builder manages his Tailscale-served tools: Notion, Hermes web UI, and the RemCTL, MailCTL, MusicCTL, NotesCTL and PhotoCTL bridge.
   - His Mac Studio is "Always awake" (5 Oct). He has run agents on a Mac Studio "since the beginning of the year" (27 Sep).
7. **So the answer to "can he use it on iOS while the Mac is closed" is mostly yes** [INFERENCE]:
   - Phone bots work anywhere with a network connection.
   - Mac-hosted bots, and Mac-only tools such as his Apple CLIs, wait for the Mac.
   - He sidesteps the closed-laptop problem with a desktop Mac Studio that never sleeps. The other Macs he mentions are an M3 Ultra Mac Studio, an M5 Pro Mac mini and a MacBook Pro.
8. **Unknown:**
   - how the phone reaches Mac-hosted bots;
   - whether the bot roster syncs between devices;
   - what runs the "Shell" steps on the iPhone;
   - whether any tool ran twice after the force-quit;
   - how permission prompts work for subagents.

## 2. Method and coverage

| Source | Route | Window | Result |
|---|---|---|---|
| His posts and replies | FxEmbed v2 `api.fxtwitter.com/2/profile/viticci/statuses?with_replies=true&count=40`, 36 cursor pages | 21 Aug → 21 Oct 19:14 | 516 authored items and 108 reposts from 1 Sep, after removing other people's posts in reply chains |
| His posts only | The same without `with_replies`, 21 pages | 24 Aug → 21 Oct | Cross-check; no authored item appears only here |
| His media tab | `…/profile/viticci/media`, 7 pages | 20 Aug → 21 Oct | Cross-check of media items |
| Earlier collection | `../2026-10-21-viticci-apple-bots/raw/` | 22 Sep → 21 Oct 14:39 | Merged. It holds one reply this sweep missed (3 Oct 06:47, about Full Disk Access). This sweep adds 18 authored items, 16 of them from 22–23 Sep, that its saved timeline file lacks |
| Reply context | The parent of each reply, from the timeline pages or `…/2/status/{id}` | — | 284 of 288 parents were in the timeline pages; the rest were fetched |
| Quote posts | `…/status/{id}/quotes`, and the X reader | — | Not retrievable: HTTP 404, and the reader returns only the post and its first replies. The week-one post has 12 quotes nobody has read |
| Bluesky, Mastodon | `app.bsky.feed.getAuthorFeed`, Mastodon `accounts/:id/statuses` | 1 Sep → 21 Oct | 27 and 54 items. They cross-post the M5 Ultra review and the Notion/local-AI story; none mentions the app |
| MacStories | Public articles he links | Sep → Oct | Open Minis review, M5 Ultra review, Deflector, Why aren't AI labs' apps better. Club articles are paywalled; only teasers were read |
| Media | Original photos (`name=orig`) and best-bitrate MP4s for agent- and app-related posts; small stills for the rest; 20 contact sheets of everything | — | 238 stills and videos reviewed. The 5.1 GB full-episode video of the 19 Oct AppStories post was not downloaded |

**Coverage limits:**
- Deleted or protected items are invisible.
- Thread pages after the first are not available through FxEmbed. His own replies come from his timeline, so they are complete.
- Podcasts from September (AppStories 500–503, Connected, NPC, Unwind) were not transcribed. The earlier record transcribed the October episodes, and none mentions the app.

## 3. Before the app: what he used and asked for (1 Sep → 28 Sep)

| UTC | Post | What it shows |
|---|---|---|
| 1 Sep 00:01 | [2094576366343663932](https://x.com/viticci/status/2094576366343663932) | Asked how to improve Grok Bot: "iPad app, a single Routines page to see all automations across bots, triggers for routines … like webhooks, and a voice mode" |
| 2 Sep 07:23 | [2095049875331166640](https://x.com/viticci/status/2095049875331166640) | To Claude Code's team: "persistent remote access to my Mac and start any task in any folder on my Mac **from my iPhone** without having to run `claude rc` from the Mac first" |
| 3 Sep 08:16 | [2095425757589729425](https://x.com/viticci/status/2095425757589729425) | Codex Remote wishes: richer remote voice ("feedback onscreen and/or MCP UI"), a sidebar synced from the Mac, pinned folders |
| 3–4 Sep | [2095469649672470785](https://x.com/viticci/status/2095469649672470785), [2095937504042000823](https://x.com/viticci/status/2095937504042000823) | Pebble Index 01 ring; he drives Hermes Agent and Grok Bot by voice from the ring, via webhooks and MCP (Club story) |
| 4 Sep | [2095950124136427971](https://x.com/viticci/status/2095950124136427971), [2096025249582039180](https://x.com/viticci/status/2096025249582039180) | GPT-6 Astra on a Pro account; Astra uses computer use in Apple Notes on his Mac |
| 6 Sep 20:25 | [2096696337475481606](https://x.com/viticci/status/2096696337475481606) | Uses **Open Minis** daily with Astra via his Codex subscription: "it can just do anything with iOS-native CLIs" |
| 8 Sep 19:57 | [2097414091300122857](https://x.com/viticci/status/2097414091300122857) | Names the category: "the always-on, VM-based personal agent space" (Grok Bot, Meta's Muse) |
| 13 Sep 15:46 | [2099162852393165074](https://x.com/viticci/status/2099162852393165074) | Hermes Agent with Cerebras-hosted Qwen, driven from the **Cadu** iPhone app; the video shows an iPhone chat whose thinking names the model and provider |
| 15 Sep 12:28 | [2099837766972416375](https://x.com/viticci/status/2099837766972416375) | "a local model … running on my M3 Ultra Mac Studio, **from my iPhone** (with Open Minis)". The screenshot header reads "Flash-Next (Mac Studio)": the agent is on the phone and the model is on the Mac |
| 16–17 Sep | [2100267256785654201](https://x.com/viticci/status/2100267256785654201), [2100647150635938248](https://x.com/viticci/status/2100647150635938248), [2100679198733951442](https://x.com/viticci/status/2100679198733951442) | Wants Claude's Dispatch and Remote Control rethought; cloud "long-running projects, with context and memories shared"; Grok Bot gains voice, and Grok's voice was "the only good voice mode … to support 3rd party connectors" |
| 21 Sep 13:01 | [2102020433394483458](https://x.com/viticci/status/2102020433394483458) | M5 Ultra Mac Studio review: "the dream Mac for local AI agents … I've gone local-only with Hermes". The [article](https://www.macstories.net/stories/m5-ultra-mac-studio-review-the-dream-mac-for-local-ai-agents/) says his most-used assistants, Open Minis and Hermes, "are now entirely powered by a model running locally on a Mac Studio". His Desk agents ran "24/7, for 99 days" on it. Cadu runs live voice "with the M5 Ultra as the server" |
| 22 Sep 18:20 | [2102463157029495285](https://x.com/viticci/status/2102463157029495285) | **The wish that became the app:** "I want Grok Bot, but with GPT-6 models, and with Claude's taste, and with Muse's speed, and with GPT-Live voice" |
| 23 Sep 20:21 | [2102855955645858216](https://x.com/viticci/status/2102855955645858216) | ChatGPT Voice with plugins, including "a custom MCP I made that lets me access my Mac from ChatGPT"; voice can now "drive background tasks" |
| 24 Sep 07:54 | [2103030336674550093](https://x.com/viticci/status/2103030336674550093) | Had Opus 5.5 optimise his Open Minis setup for 12 hours |
| 25 Sep 16:50 | [2103527607493148971](https://x.com/viticci/status/2103527607493148971) | NotesCTL preview: "a local MCP server that also works with Tailscale" |
| 26 Sep 20:20 | [2103942910165287369](https://x.com/viticci/status/2103942910165287369) | Muse: simple by default, but you can install CLIs in its VM and inspect every tool call |
| 27 Sep 09:56 | [2104148266850099490](https://x.com/viticci/status/2104148266850099490) | Reply to Simon Støvring's "We all need to leave agents stopping when you close your laptop in 2026": "Started doing this with Mac Studio at the beginning of the year … beats any cloud/hosted VM for local dev work, especially on the iOS side" |
| 27 Sep 14:04 | [2104210562150515055](https://x.com/viticci/status/2104210562150515055) | Wants Muse "to be able to mount specific folders on iOS, I.e. how Open Minis does it" |

**What Open Minis is.** It is the closest public precedent for his app (Observed, from his July 2026 [review](https://www.macstories.net/reviews/open-minis-is-the-ios-agent-i-wish-siri-ai-could-be/)):
- It is "an on-device agent" for iPhone and iPad that works with any frontier model.
- It integrates EventKit, MusicKit, HomeKit, HealthKit, Files, Vision, NaturalLanguage, speech, NFC and Bluetooth.
- Those integrations work as command-line tools inside an emulated Alpine Linux shell (iSH), sandboxed to the app's workspace. The shell can install packages and run Python, Git and SSH.
- Its memory is Markdown files in the Files app.
- Browser use runs in a `WKWebView`. Folders are "mounted" from the Files app, and secrets go into native Keychain prompts.
- He used it with cloud models and with a model on his Mac Studio, through an OpenAI-compatible proxy his agent built.

Apple Bots shows many of the same features: "Linked Folders", "Python", "Secrets", "Shell" steps running a `cobots` command, MCP, skills and recall chips. That suggests it borrows the CLI-bridge pattern [INFERENCE].

## 4. The app, day by day (29 Sep → 21 Oct)

| UTC | Post | What | Evidence |
|---|---|---|---|
| 29 Sep 12:05 | [2104905355247357957](https://x.com/viticci/status/2104905355247357957) | Asked what he uses "for Hermes on the desktop": "The Hermes app + one that I'm building 😁" | Claim; the first mention |
| 3 Oct 10:05 | [2106324671926825444](https://x.com/viticci/status/2106324671926825444) | His build rig: a Cua Space on the M3 Ultra (512 GB) and T3 Code on the M5 Ultra, on his tailnet, with "8 Xcode simulators running on the second Mac" | Observed text |
| 3 Oct 11:37 | [2106347902406627652](https://x.com/viticci/status/2106347902406627652) | Asked what he builds with that rig: "My first iOS app! 😄" | Claim |
| 3 Oct 12:00 | [2106353594794672501](https://x.com/viticci/status/2106353594794672501) | Asks Grok Bot for "iOS widgets for Home Screen / Lock Screen / Control Center … to open specific bots or start voice mode" | Claim; later visible in his own app's design |
| 5 Oct 21:16 | [2107218394705744332](https://x.com/viticci/status/2107218394705744332) | Asked "did your tunnel keep the mac awake or did tasks just die when it went to sleep?": "Always awake" | Claim |
| 7 Oct 00:30 | [2107629523814498673](https://x.com/viticci/status/2107629523814498673) | His Grok Bot + Cursor system is "always-on (cloud-based), self-testing … driving from my phone"; "I use pstack and verification skills religiously" | Claim |
| 8 Oct 13:45 | [2108192119152140318](https://x.com/viticci/status/2108192119152140318) | "my ideal 'Apple Bots' product doesn't exist / so I ported most of @badlogicgames' Pi Durable to Swift … a functioning, lean harness with a bunch of Apple integrations" | Claim; 3 iPhone screens and 1 window (§5) |
| 8 Oct 13:48–13:55 | [2108192903688527912](https://x.com/viticci/status/2108192903688527912), [2108193428945399859](https://x.com/viticci/status/2108193428945399859), [2108194498069344679](https://x.com/viticci/status/2108194498069344679) | "I ended up not going the JSCore route"; asked "Do you keep the harness running on iOS?", he replies that it "supports durability out of the box, but yes, I'll also add support for long running background tasks"; on open source: "I'll try as soon as my Opus limits reset" | Claim |
| 8 Oct 13:47 | [2108192453983613243](https://x.com/viticci/status/2108192453983613243) (repost) | Finn Voorhees: "an agent running on my phone … run any shortcut on my device autonomously, using notification triggers … Powered by PiDurableKit" | Observed video (§8) |
| 9 Oct 18:10 | [2108621017539317981](https://x.com/viticci/status/2108621017539317981) | "I'm working on two apps." The T3 Code screenshot shows the Cobots-Native project on "Federico's Mac Studio"; "Merged and on your iPhone and iPad: Ask before acting (PR #14)"; "Waiting on 6 subagents" | Observed photo |
| 9 Oct 18:19 | [2108623467965038946](https://x.com/viticci/status/2108623467965038946) | "can now set alarms, reminders, events, and more". The window shows bots named Coach, Planner, Chef, Scribe and Researcher; an AlarmKit alarm that "rings even in Silent mode"; and a timer | Observed photo |
| 9 Oct 19:08 | [2108635610160525412](https://x.com/viticci/status/2108635610160525412) | "WeatherKit, MusicKit, Reminders, AlarmKit … native Apple tools with ANY frontier model"; 3 iPhone screens with Reminders, a severe-weather alert and music | Claim and Observed |
| 9–12 Oct | [2108646482345898420](https://x.com/viticci/status/2108646482345898420), [2108682188719866269](https://x.com/viticci/status/2108682188719866269), [2108854940504564200](https://x.com/viticci/status/2108854940504564200), [2109538445114650949](https://x.com/viticci/status/2109538445114650949) | Replies: OpenAI-compatible local endpoints "yes"; HomeKit "On it"; Shortcuts "Yep!"; EventKit, including Google calendars from Internet Accounts, "Indeed" | Claim |
| 11 Oct 13:22 | [2109273374157615588](https://x.com/viticci/status/2109273374157615588) | ESP32 "T3 Pebble" listing his T3 Code sessions; four are titled "Cobots: …", one of them "Apple Watch companion" | Observed photo |
| 13 Oct 20:21 | [2110103719723274444](https://x.com/viticci/status/2110103719723274444) | T3 Code usage on the iPhone for Cobots-Native, spread over four Claude accounts (Main, Secondary, Tertiary, Quaternary) | Observed screenshot |
| 16 Oct 11:42 | [2111060204112458229](https://x.com/viticci/status/2111060204112458229) | "Fable 5.5 landing in my slop codebase" | Joke video, no app on screen |
| 17 Oct 11:26 | [2111418614343504107](https://x.com/viticci/status/2111418614343504107) | Week one: 20+ frameworks, background voice, background tasks, WebKit browser use, mini web apps, native subagents, "Memories and session recall" | Claim; 11 iPhone screens (§5) |
| 17 Oct | [2111441645682172230](https://x.com/viticci/status/2111441645682172230), [2111483585920196847](https://x.com/viticci/status/2111483585920196847), [2111516616601305389](https://x.com/viticci/status/2111516616601305389) | Mini widgets are "super fun to design"; Foundation Models "Yep!"; cards are made "At runtime in SwiftUI" | Claim |
| 17 Oct 22:13 | [2111581381310533775](https://x.com/viticci/status/2111581381310533775) | Asked "can it pick a task back up if the app gets killed?": "Yep! 😄", with an 11.6 s video | **Observed video** (§6.3) |
| 20 Oct 14:44 | [2112555465313853810](https://x.com/viticci/status/2112555465313853810) | "A *very* early look at my 'Apple Bots' app … running on macOS … global quick entry on the Mac, agent split views on Mac/iPad, menu bar … Apple Intelligence … as a background utility … Code mode works beautifully … the latest MCP spec is also natively supported" | Claim; 4 Mac screenshots (§5) |
| 21 Oct 19:14 | [2112986020786422221](https://x.com/viticci/status/2112986020786422221) | Quoting Anthropic's Claude Duet: "Anthropic is making their own Grok Bot / Dots / personal agent app" | Claim; market context, not about his app |

Nothing about the app appeared between 20 Oct 14:44 and 21 Oct 19:14. Open-source and TestFlight requests stay unanswered.

## 5. What each screenshot shows about where things run

All Observed unless marked. Pixel-level descriptions of the 8–20 October media are in the [earlier record §5](2026-10-21-viticci-apple-bots-record.md#5-media). This section covers only device and host evidence.

**iPhone screens (8, 9 and 17 Oct).**
- Bots run with a model named in their header: "GPT-6.1 Sol · Fast" or "Claude Opus 5.5".
- Cards come from on-device frameworks:
  - Health: sleep and steps;
  - Music: the system player's now playing and an in-app "Played by Cobot" player;
  - Shazam;
  - WeatherKit, with the Apple Weather mark and a severe-weather alert;
  - Reminders, with "Changed" and Undo;
  - Photos ("59 photos and 1 video" for 15–17 Oct) and Maps;
  - HomeKit: "only the Outdoor Plug is currently on";
  - AlarmKit.
- The bot list and headers on the iPhone carry no host label. The list after relaunch reads "4 bots · 1 working": Cobot, Researcher, ClubBot, WeatherBot, plus one project.
- Settings, 17 Oct:
  - Providers & Models (8), Helpers, Speech & Dictation (ElevenLabs), Voice Mode (Ara), Images (GPT Image 2.5 Sunburst);
  - under "What Bots Can Use": Tools & Access (36 tools), Skills (2), MCP Servers (3), **Linked Folders (2)**, Secrets, **Python**, Shortcuts;
  - Chat Options.
- Voice Mode settings: "Voice mode talks through xAI's Grok Voice, so it needs an xAI API key … Your bot keeps thinking with its own model and provider". Voice is a speech transport; the bot's own model does the work.
- A mini app ("Your task garden · Version 6 of 6") is labelled "Reminders snapshot … Refresh asks Cobot to fetch the latest tasks. No reminders are changed here." Generated web content reads a data snapshot, and changes go back through the bot.
- Browser use: "MacStories is open in my browser … Done by Cobot · 2 steps · 20s · Watch Steps".
- A "helpers" (subagent) card stopped: "Stopped · 43s · GPT-6.1 Sol · High · Fast".

**Window screenshots on 8 and 9 October: most likely the iPad build** [INFERENCE].
- The empty pinned area reads "Touch and hold a bot and choose Pin. Its face sits here, a tap away", in both windows. That is touch language; the 20 Oct macOS build instead shows ⌘1/⌘2 shortcuts.
- Chef's alarm "rings even in Silent mode", which is AlarmKit behaviour. AlarmKit is iOS, iPadOS and Mac Catalyst only ([native Apple §6.1](2026-10-20-native-apple-direction.md#61-matrix)).
- The same day, his coding agent reported "Merged and on your iPhone and iPad".
- The window chrome (traffic lights, a sidebar toggle) matches iPadOS windowing.
- The 8 Oct MusicBot window lists "Shell" steps: `cobots music library search …`, `curl -L -s …`, `sed … /tmp/oasis.html`, "Read queue.txt", "Wrote queue.txt". On an iPad these must run in an in-app environment, as Open Minis's emulated shell does. That is consistent with "Python" in settings and the iPhone's shell-styled step "Running reminders due today" [INFERENCE].
- The alternative reading, the iPad app running on a Mac, cannot be excluded.

**macOS screens (20 October).**
- Mac-only layout:
  - a sidebar with Waiting for You, Library, Pages, Activity, Projects ("A board of tasks for your bot…"), Pinned (Cobot ⌘1, Builder ⌘2), Bots and Archived;
  - an Activity inspector listing "Thought", "Ran cobots curl -s -X POST https://api.firecrawl.dev/v2/scrape … Shell" and "Ran a script · Code Mode · 2 calls";
  - link-preview popovers and a quick-entry panel ("Cobot · What are my tasks due today?").
- **Builder's header reads "On Federico's Mac Studio · Claude Opus …".** No other bot shows a host. Builder reports work on that Mac:
  - "Removed from Tailscale: :8443 Stems Editor. Funnel is off …";
  - ":9119 Hermes web UI", ":4376 HermesBoard", "/ on 443, the Index Ring bridge";
  - "RemCTL, MailCTL, MusicCTL, NotesCTL and PhotoCTL share that address and still work";
  - "The only public address left is Notion External Agents on :10000";
  - "Porta shows 22 tiles";
  - "I saved a copy of the Tailscale setup … in ~/agent/state/porta/backups/".
- So bots can be bound to a specific Mac, and that Mac hosts his Apple-app CLIs as network services on his tailnet. Whether the window itself runs on the Mac Studio or on another Mac (he also has a MacBook Pro, 4 Oct) is not visible [INFERENCE].

**Development host.** On 9 October the T3 Code panel shows:
- the project on "Federico's Mac Studio", with folders `App`, `CobotsNative.xcodeproj`, `docs`, `Durable` and `UI`, plus `Tools/`;
- "Lineage · 6 running": a weather fix, paper follow-ups, a card fix, AlarmKit and "Pi conformance suite vs …";
- "Previous agents (55) · 3 failed".

## 6. Using the iPhone app while the Mac is off

### 6.1 What runs on the phone alone

| Capability | Evidence | Needs a Mac? |
|---|---|---|
| The agent loop and durable state | Force-quit and resume on the iPhone (§6.3); "the harness supports durability out of the box" (8 Oct) | No [INFERENCE, strong] |
| Cloud models | Per-bot GPT-6.1 Sol or Claude Opus 5.5; 8 providers; local OpenAI-compatible endpoints "yes" | No; a local endpoint on a Mac would need that Mac |
| Reminders, Calendar, Health, Music (system and in-app), Shazam, HomeKit, WeatherKit, Photos, Maps, AlarmKit, Shortcuts, Foundation Models | Cards and replies (§4, §5) | No. Health, HomeKit, AlarmKit and the system Music player are iPhone/iPad features that a Mac cannot provide |
| Voice | Grok Voice with an xAI key, in the background with a Live Activity (17 Oct) | No |
| Browser use, mini web apps, subagents, memory recall | 17 Oct screens | No |
| MCP servers (3), skills, secrets, linked folders, Python | 17 Oct settings | Depends on the server: a Tailscale-served Mac CLI needs that Mac |

### 6.2 What needs the Mac

- **Bots bound to a Mac**, such as Builder "On Federico's Mac Studio" (20 Oct).
- **Mac-only data and tools.** His RemCTL, NotesCTL, MailCTL, MusicCTL and PhotoCTL are Mac CLIs; RemCTL is "a complete reverse-engineer of Reminders based on the private ReminderKit framework". He shares them over Tailscale (25 Sep, 20 Oct); RemCTL's ChatGPT extension is "Local-only for now. You'd need a tunnel" (30 Sep).
- **Local models.** Open Minis and Hermes use models served by the Mac Studio (15 and 21 Sep).
- **His answer to the closed-laptop problem is hardware.** A desktop Mac Studio that is "Always awake" (5 Oct). Others make the same choice: Cursor's Mac settings, in his 7 Oct screenshot, offer "Keep This Computer Awake … when this computer is plugged in and Remote Control is enabled".

### 6.3 The force-quit video against Apple's documentation

The video ([2111581381310533775](https://x.com/viticci/status/2111581381310533775), 11.6 s) is described frame by frame in the [earlier record §5.2](2026-10-21-viticci-apple-bots-record.md#52-the-force-quit-video-observed). Its sequence:
1. A turn starts on the iPhone.
2. He swipes the app away in the app switcher.
3. The Dynamic Island changes from "Cobot / Thinking" to "Cobot / Task failed".
4. He relaunches; the bot list shows "Cobot · Replying…" and the same turn continues to a Reminders card.

Apple's documentation matches each step (Observed, [guide](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados), [class](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)):
- A `BGContinuedProcessingTask` "starts in the foreground" and runs "only in response to someone's action".
- The system shows its progress "in a Live Activity", and a person can cancel it there.
- The system "can terminate a continuous background task abruptly … under resource constraints".
- "The system cancels any running tasks if a person closes the app in the app switcher, but the app doesn't receive an indication of cancellation in that case."

So the app was running the turn on the phone inside a continued-processing task. The kill cancelled it without notice, and the durable store let the relaunched app resume the turn [INFERENCE].

### 6.4 The iOS limits that shape any phone-first agent

Observed in Apple's documentation, as already collected in [native Apple §6.1](2026-10-20-native-apple-direction.md#61-matrix):
- **No unattended background loop.** `BGContinuedProcessingTask` needs a user action, can be cancelled, and dies on an app-switcher close.
- **Live Activities** last up to 8 hours (12 hours on the Lock Screen), hold at most 4 KB of data, and cannot access the network.
- **Background pushes:** "don't try to send more than two or three per hour".
- **Audio** continues in the background only with a background audio mode. That is how a voice session can keep running [INFERENCE].
- **Notification-triggered Shortcuts automations (iOS 27).**
  - Deflector sends silent notifications to itself so an automation runs a shortcut without opening Shortcuts (his [article](https://www.macstories.net/ios/deflector-turns-ios-27-notification-triggers-into-a-shortcut-launcher/), 6 Oct).
  - Finn Voorhees uses the same trick so a PiDurableKit agent on his phone can "run any shortcut on my device autonomously" (8 Oct repost).
  - This is the documented-by-practice way for a phone agent to act through Shortcuts without a Mac [INFERENCE: it depends on a user-enabled automation].

## 7. What he values, in his words (context for product decisions)

- **Orchestration.** A primary bot "can spin up group threads with other specialized bots … which can then spin up @cursor_ai cloud agents, and coordinate" (2 Oct, [2106094796146176008](https://x.com/viticci/status/2106094796146176008)).
- **Verification.** "I want my agents and bots to be constrained to check their work, operate independently, and escalate to me only when needed" (7 Oct).
- **Voice and phone control.** Voice during walks, Pebble-ring webhooks, "mostly driving from my phone" (7 Oct).
- **Native Apple surfaces.** iOS widgets for bots and voice (3 Oct); "No native Apple framework will be ignored" (20 Oct).
- **Taste.** "I have to spend so much time thinking about usability decisions, onboarding flows, iOS best practices" ([Why aren't AI labs' apps better?](https://www.macstories.net/linked/why-arent-ai-labs-apps-better/), 15 Oct).
- **Pain points.**
  - "I wish voice mode worked in group chats";
  - bots that "got lazy and forgot to merge";
  - the Cursor Projects view on iOS is "very barebones";
  - Cursor Remote Control still needs "to open a folder on Mac first" (7 Oct).

## 8. Others building the same pattern (observed in his timeline)

| Who | What | Source |
|---|---|---|
| Open Minis (indie) | Shipping on-device iPhone and iPad agent: Apple-framework CLIs in an emulated Linux shell, Files workspace, Markdown memory, WebKit browser | [Review](https://www.macstories.net/reviews/open-minis-is-the-ios-agent-i-wish-siri-ai-could-be/) |
| Halo (Tanmay Sonawane) | Upcoming iOS agent that "runs in a loop on-device (displayed via Live Activities)" | Same review |
| Finn Voorhees | PiDurableKit agent on an iPhone running allowed shortcuts autonomously via notification triggers (8 Oct); an "always-watching assistant for iOS that lives in the Dynamic Island" using on-device models (18 Sep) | Reposts [2108192453983613243](https://x.com/viticci/status/2108192453983613243), [2100918472054018434](https://x.com/viticci/status/2100918472054018434) |
| Mario Zechner (Pi) | "a little pi durable thing that runs fully on my phone … and it has subagents" (Android); "pi durable was specifically designed to run there as well" (browser). Corrected 2026-10-22: the second post replies to @mjf891's in-browser Pi Durable core, hosted in a WebView with a Kotlin layer and an Alpine proot. The phone app's structure is in [follow-ups §5](2026-10-22-viticci-followups.md#5-how-mario-zechners-phone-app-is-built) | [2106286641551675411](https://x.com/badlogicgames/status/2106286641551675411), [2108191061688664413](https://x.com/badlogicgames/status/2108191061688664413) (found by web search, not in his timeline) |
| Cadu (@fl_rn_st) | iPhone client for Hermes Agent, with the Mac Studio as server; GPT Live voice, Mail automation | Reposts 20 and 24 Sep; [M5 Ultra review](https://www.macstories.net/stories/m5-ultra-mac-studio-review-the-dream-mac-for-local-ai-agents/) |
| Simon Støvring | A ChatGPT plugin "that lets Codex build iOS apps on my remote Mac" | Repost [2108534825485533525](https://x.com/viticci/status/2108534825485533525) |
| OpenAI, Anthropic, Meta, xAI | Dots (expected "message board … hosted on a Remote computer you own", 29 Sep); Claude Projects reaching a local folder (5 Oct); Claude Duet (21 Oct); Muse (8 Sep onwards); Grok Bot (throughout) | His posts |

## 9. Corrections to earlier documents

| Document | Earlier statement | Correction |
|---|---|---|
| [Viticci record §1](2026-10-21-viticci-apple-bots-record.md#1-summary) | His X activity "23 September → 21 October is complete", 237 items | This sweep finds 18 authored items missing from the earlier timeline file: 16 of them on 22–23 Sep, including the 22 Sep "I want Grok Bot, but…" post, and 2 self-replies. It also covers 1–22 Sep and 21 Oct 14:39 → 19:14. The earlier file holds one reply this sweep lacks; both are merged in the [index](2026-10-21-viticci-x-index.md) |
| [Viticci record §3](2026-10-21-viticci-apple-bots-record.md#3-timeline) and [§5.1](2026-10-21-viticci-apple-bots-record.md#51-inventory) | The 8 and 9 Oct posts show "1 Mac window" each | Most likely the iPad build in iPadOS windowing: touch-language copy, an AlarmKit alarm, and "on your iPhone and iPad" the same day (§5) [INFERENCE] |
| [Native Apple direction §4](2026-10-20-native-apple-direction.md#4-demonstrated-claimed-or-inferred-apple-bots) | "Alarms and timers: timer and alarm cards on a Mac … how a Mac build schedules AlarmKit alarms is unknown" | The alarm window is most likely the iPad build, so no Mac AlarmKit question arises [INFERENCE] |
| [Viticci record §5.5](2026-10-21-viticci-apple-bots-record.md#55-what-the-app-visibly-does-and-what-is-only-claimed) | "on the Mac: … a bot running 'On Federico's Mac Studio'" | Precisely: in the macOS build, one bot, Builder, is labelled "On Federico's Mac Studio" and manages that Mac's Tailscale services; other bots show no host (§5) |

## 10. Implications for Memoshi and Pi_Swift [INFERENCE]

These are inferences for discussion. They do not change the binding plan; that needs [change control](../plan/decisions.md#change-control).

1. **The pattern the user wants is "engine on every device".** Each iPhone, iPad and Mac runs its own durable Pi harness, with its own store and on-device Apple tools. Some bots live on an always-on Mac for shell, files, coding and unattended routines. That differs from Draft 4, where the iPhone is only a remote client of a Node daemon on the Mac ([D12](../plan/decisions.md#d12), [D15](../plan/decisions.md#d15), [D38](../plan/decisions.md#d38)).
2. **"Works while the Mac is closed" means:**
   - phone-homed bots keep working;
   - Mac-homed bots show as offline, or queue requests until the Mac returns;
   - nothing promises unattended phone work beyond what iOS allows (§6.4).
3. **The engine requirements this record supports:**
   - durable turns that resume on relaunch;
   - a single writer per store, so the app, widgets and intents cannot run a task twice;
   - work running inside `BGContinuedProcessingTask`, with progress reporting;
   - subagents as child conversations;
   - an approval hook (his "Ask First" setting);
   - Code Mode for tool calling;
   - an MCP client;
   - an in-app execution environment on iOS (files and app-provided CLIs) and a remote environment to a Mac;
   - providers configured with API keys, plus OpenAI-compatible endpoints (corrected 2026-10-22: add Sign in with ChatGPT plan usage where OpenAI's terms allow it, but no Anthropic, Google or Meta subscription flows; [follow-ups §2.4](2026-10-22-viticci-followups.md#24-what-this-means-for-our-app-inference));
   - voice as a separate realtime transport.
4. The detailed requirement list and recommended architecture for the Swift engine are in `~/Documents/memoshi/Pi_Swift/docs/research/apple-bots-engine-requirements.md`.

## 11. Evidence storage

- **Where:** `~/Documents/memoshi/evidence/2026-10-21-viticci-x-sweep/`, outside the repositories, for the same reasons as the [earlier record §12](2026-10-21-viticci-apple-bots-record.md#12-evidence-storage).
- **What:**
  - raw FxEmbed pages (with and without replies, and media);
  - reply parents;
  - Bluesky and Mastodon feeds since 1 September;
  - `catalogue.json` and `archive.md`, the full text of every item;
  - media originals for agent- and app-related posts, and stills for the rest;
  - 20 contact sheets;
  - frames from the force-quit video and Finn Voorhees' phone demo.
- **Size and integrity:** 290 files, about 208 MB. The SHA-256 of `MANIFEST.tsv` is `10a6e692b89974b79a9d4cd5d49d065125f58b7c01474036fe1f4d8a9798485f`. The folder's `README.md` has the check command.
- **Not kept:** the 5.1 GB full-episode video attached to the 19 Oct AppStories post; its URL is in `raw/media_index.json`.

## 12. Limits

- Quote posts (12 on the week-one post) and thread pages after the first could not be retrieved without an X login.
  - **Updated 2026-10-22:** a logged-in X session later found 15 of the 20 quotes on the app posts and 29 more replies, none of them by Viticci. Direct-reply coverage of the app threads is now 93% ([Viticci record §6.1](2026-10-21-viticci-apple-bots-record.md#61-quote-posts)).
  - Quotes of his other posts were not collected.
- Paywalled Club articles were not read, including "Building iOS Apps with Multiple Claude Accounts, T3 Code, Cua Spaces, and pstack" (9 Oct), which describes how he builds the app.
- September podcasts were not transcribed.
- Nothing was installed, built, run or signed into. Statements about how the app works internally are inferences from screenshots and replies.
- Topic tags in the index are keyword-assigned and serve navigation only.

## Sources

- **X posts:** the IDs above and every row of the [index](2026-10-21-viticci-x-index.md), retrieved through the FxEmbed v2 API on 21 October 2026.
- **MacStories:**
  - [Open Minis Is the iOS Agent I Wish Siri AI Could Be](https://www.macstories.net/reviews/open-minis-is-the-ios-agent-i-wish-siri-ai-could-be/);
  - [M5 Ultra Mac Studio Review: The Dream Mac for Local AI Agents](https://www.macstories.net/stories/m5-ultra-mac-studio-review-the-dream-mac-for-local-ai-agents/);
  - [Deflector Turns iOS 27 Notification Triggers into a Shortcut Launcher](https://www.macstories.net/ios/deflector-turns-ios-27-notification-triggers-into-a-shortcut-launcher/);
  - [Why Aren't AI Labs' Apps Better?](https://www.macstories.net/linked/why-arent-ai-labs-apps-better/).
- **Apple:** [Performing long-running tasks on iOS and iPadOS](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados); [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask).
- **Other makers' posts:** Mario Zechner [2106286641551675411](https://x.com/badlogicgames/status/2106286641551675411) and [2108191061688664413](https://x.com/badlogicgames/status/2108191061688664413); Finn Voorhees and Simon Støvring via the reposts listed in §8.
