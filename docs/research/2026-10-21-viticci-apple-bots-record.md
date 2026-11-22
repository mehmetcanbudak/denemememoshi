# Viticci's 'Apple Bots': the complete public record

**Status:** Research · 2026-10-21
**Owns:** Every public post, reply, photo and video about Federico Viticci's 'Apple Bots' prototype (3–21 October 2026), the context around it, the Swift ports of Pi Durable that surfaced in its threads, the coverage limits of this collection, and where the raw evidence is kept.
**Depends on:** [Native Apple direction](2026-10-20-native-apple-direction.md) (extended here, and corrected in §11) · [Pi brain refresh](2026-10-20-pi-brain-refresh.md) · [NEXT_VERSION](../plan/NEXT_VERSION.md) (proposed) · [decisions](../plan/decisions.md) (binding)

Research is evidence, not decisions ([index](README.md)).

**Labels:**
- **Observed:** seen in a primary source: post text, a pixel or video frame, a repository file, an Apple page.
- **Claim:** stated by Viticci, by on-screen text his coding agent wrote, or by another maker. Not verified.
- **[INFERENCE]:** our reasoning.

All times are UTC. Personal details visible in his screenshots (addresses, private reminders) are summarised, not quoted.

---

## 1. Summary

1. **Coverage of his own X activity, 23 September 08:51 UTC → 21 October, is complete** (Observed). Two independent timeline sweeps agree: one of his posts, one of his posts plus replies. Together they hold 237 items of his own: 99 posts and 138 replies. 21 of them concern the app. Nothing new about it appeared on 21 October.
   - **Corrected 2026-10-21 (later):** a sweep from 1 September finds 18 authored items missing from this collection's timeline file: 16 on 22–23 September, including the "I want Grok Bot, but with GPT-6 models…" post, and 2 self-replies. The merged coverage is 1 Sep → 21 Oct 19:14 UTC, with 516 authored items ([full record §2, §9](2026-10-21-viticci-full-record-sep-oct.md#9-corrections-to-earlier-documents)).
   - **Added 2026-10-22:** quote posts and late replies, read through the user's logged-in X session (§2, §6.1).
     - 15 of the 20 quotes X counts are visible. They include John Voorhees's "There is another. More soon..." on the WeatherKit/MusicKit self-reply.
     - 29 more replies were found (18 through search, 11 by scrolling the thread pages), none of them by Viticci, so his reply record above stands.
     - Direct-reply coverage rose from 81% to 93% (184 of 197). The remaining 13 are not shown to the account in any view (§13).
2. **One video shows the app working** (Observed). An 11.6 s iPhone recording in a reply ([2111581381310533775](https://x.com/viticci/status/2111581381310533775)) shows a turn surviving a force-quit and finishing after relaunch. The earlier finding that 'Apple Bots' appears only in still images is wrong (§11).
3. **The code base is "Cobots-Native"** (Observed, in a T3 Code screenshot). It has a `Durable` folder and runs "the Pi conformance suite". Its coding agent reports an "Ask before acting" feature merged as PR #14.
4. **He plans an App Store release** (Claim).
   - Club MacStories, 9 October: "we're working on two different apps that we plan to release on the App Store in the near future."
   - No name, date, TestFlight or repository exists.
   - About a dozen open-source requests and a dozen beta requests in the replies went unanswered. The one answer went to Pi's author: "I'll try as soon as my Opus limits reset".
5. **His answers about the app** (Claim):
   - local OpenAI-compatible endpoints: "yes";
   - HomeKit: "On it";
   - Shortcuts: "Yep!";
   - EventKit, including Google calendars added through Internet Accounts: "Indeed";
   - Apple Foundation Models: "Yep!";
   - how the cards are made: "At runtime in SwiftUI";
   - JavaScriptCore: "I ended up not going the JSCore route";
   - long-running background tasks: planned.
6. **Public Swift routes to Pi Durable exist** (Observed).
   - PiDurableKit (CC0-1.0) runs upstream pi-durable 1.3.0 inside JavaScriptCore.
   - PiSwift (MIT) is a native Swift port of 1.1.0.
   - Rui Carmo archived his Swift and Rust ports, citing "a zillion people doing parallel work on this".
7. **No other channel carries it** (Observed).
   - There are no Apple Bots posts on Bluesky or Mastodon, and no MacStories article.
   - It is not mentioned in the 11 October episodes of AppStories, Connected, MacStories Unwind and NPC.
   - Connected 624 (15 October) does record his view of agent products and his prediction for Apple (§7.4).
8. **Apple platform facts found along the way** (Observed; §10):
   - Full Disk Access will require "very explicit user action" (announced 2 October, with no date or mechanism);
   - the original Developer ID Sub-CA expires on 1 February 2027;
   - App Review guideline 2.5.19 is new, on hidden, dormant or undocumented features (16 October).

## 2. Method and coverage

| Source | Route | Window | Result |
|---|---|---|---|
| His top-level posts | FxEmbed API `api.fxtwitter.com/2/profile/viticci/statuses`, paginated by cursor | 23 Sep → 21 Oct | 106 of his posts and self-replies, plus reposts |
| His posts and replies | The same endpoint with `with_replies=true`, 15 pages | 22 Sep → 21 Oct | 235 of his items. Only two self-replies are missing, and the other route has them |
| His media tab | `…/2/profile/viticci/media` | 23 Sep → 20 Oct | 74 posts with media, 10 of them replies |
| Threads | `…/2/conversation/{id}`, first page in both `likes` and `recency` ranking, followed into sub-threads | The seven app threads | The coverage table below |
| Quote posts | First through FxEmbed `…/2/status/{id}/quotes` and web search, which failed (HTTP 404; no X operators). Then, on 22 Oct, through the user's logged-in X session: each post's Quotes page, X search `quoted_tweet_id:` (Latest and Top) and `url:` | 22 Oct | 15 of 20 quotes (§6.1) |
| Late replies | X search `conversation_id:` in the same logged-in session, newest first, paged back with `until_time` | 22 Oct | 18 more replies; none by Viticci |
| Thread pages | The same session with JavaScript allowed for Apple Events, which the user turned on for this pass. Page scripts scrolled each app thread to its end, pressed X's "Show replies" and "Show probable spam", and repeated under each reply sort (Relevant, Recent, Likes). The three Quotes pages with gaps were scrolled the same way | 22 Oct | 11 more direct replies; no more quotes |
| Cross-check | Web search `from:viticci "Apple Bots"` | — | Returns the same four posts |
| Bluesky, Mastodon | `app.bsky.feed.getAuthorFeed`; Mastodon `accounts/:id/statuses` | 1 → 21 Oct | 5 and 16 items; none about the app |
| MacStories | Public pages and the public parts of Club posts | October | §7 |
| Podcasts | YouTube auto-captions for AppStories 504–506, Connected 623–624 and NPC (20 Oct). YouTube then rate-limited caption downloads, so Unwind (2, 9, 16 Oct) and NPC (6, 13 Oct) were transcribed locally with whisper.cpp (large-v3-turbo) | 1 → 21 Oct | 11 episodes; none mentions the app |
| Media | Photos at `name=orig`, videos at the highest bitrate. Frames every 0.25 s plus scene changes; `ffmpeg` volume detection; whisper on the one video with sound | — | §5 |
| Repositories | `gh api` and shallow clones at the commits in §8. Nothing was built or run | — | §8 |

**The logged-in session.** Read-only, on the user's X account in Brave.
- **Window:** AppleScript opened separate windows and navigated only its own tab in each. Afterwards it closed those windows. One of them also held tabs it had not opened, so there it closed only its own tab. The user's tabs were not touched.
- **Capture:** the first pass saved each page's rendered DOM ("single file" MHTML) and parsed it, with no JavaScript. In the second pass the user allowed JavaScript from Apple Events. Page scripts then only scrolled, pressed the reply-revealing controls and switched reply sort, and read the rendered posts. Nothing was posted, liked or followed.
- **Afterwards:** the captures were deleted, because they contain the account's page state. The parsed results are kept (§12).

**Thread coverage.** FxEmbed returns only the first page of a thread; its next-page cursor returns HTTP 404. Taking both ranking modes recovers most replies. In the logged-in session on 22 October, X search added 18 more and scrolling the thread pages 11 more. The platform's reply counter and our counts may not measure the same thing, so both are shown. **Viticci's own replies don't depend on this table.** They come from his replies timeline, which is complete.

| Post | X reply counter (22 Oct) | Direct replies retrieved | Including nested replies |
|---|---|---|---|
| [2108192119152140318](https://x.com/viticci/status/2108192119152140318) origin | 52 | 51 | 77 |
| [2108621017539317981](https://x.com/viticci/status/2108621017539317981) two apps | 10 | 10 | 12 |
| [2108623467965038946](https://x.com/viticci/status/2108623467965038946) alarms | 18 | 15 | 32 |
| [2108635610160525412](https://x.com/viticci/status/2108635610160525412) self-reply | 10 | 10 | 13 |
| [2111418614343504107](https://x.com/viticci/status/2111418614343504107) week one | 67 | 62 | 73 |
| [2111581381310533775](https://x.com/viticci/status/2111581381310533775) video reply | 3 | 2 | 2 |
| [2112555465313853810](https://x.com/viticci/status/2112555465313853810) Mac | 37 | 34 | 39 |

In total, 184 of 197 direct replies (93%) were retrieved. The other 13 appear under no sort order and no reveal control, even to the logged-in account. They may be deleted, from suspended or protected accounts, or from accounts this account blocks or mutes [INFERENCE].

## 3. Timeline

| When (UTC) | Post | What | Evidence |
|---|---|---|---|
| 3 Oct 11:37 | [2106347902406627652](https://x.com/viticci/status/2106347902406627652) | Asked what he is building with his Cua Space and T3 Code setup: "My first iOS app! 😄" | Observed text; that this is the app is [INFERENCE] |
| 8 Oct 13:45 | [2108192119152140318](https://x.com/viticci/status/2108192119152140318) | "my ideal 'Apple Bots' product doesn't exist / so I ported most of @badlogicgames' Pi Durable to Swift and ended up with a functioning, lean harness with a bunch of Apple integrations" | Claim; 2 photos |
| 8 Oct 13:48–13:55 | Three replies (§4) | Not JavaScriptCore; durability "out of the box"; open-sourcing "as soon as my Opus limits reset" | Claim |
| 9 Oct 18:10 | [2108621017539317981](https://x.com/viticci/status/2108621017539317981) | "I'm working on two apps." Links [Club MacStories Weekly 532](https://www.macstories.net/club/macstories-weekly-issue-532/building-ios-apps-with-multiple-claude-accounts-t3-code-cua-spaces-and-pstack/), whose public teaser says both apps are planned for the App Store. The photo shows T3 Code on "Cobots-Native" (§5.3) | Claim; Observed photo |
| 9 Oct 18:19 | [2108623467965038946](https://x.com/viticci/status/2108623467965038946) | "can now set alarms, reminders, events, and more 😎 / Watch as I create a better Siri AI lol" | Claim; 1 photo |
| 9 Oct 19:08 | [2108635610160525412](https://x.com/viticci/status/2108635610160525412) | "WeatherKit, MusicKit, Reminders, AlarmKit – I'm going to do it all, and let you use native Apple tools with ANY frontier model, in a clean UI, with crazy good performance and mini interactive interfaces." | Claim; 1 photo |
| 9–12 Oct | Replies (§4) | Local endpoints, HomeKit, Shortcuts, EventKit | Claim |
| 11 Oct 13:22 | [2109273374157615588](https://x.com/viticci/status/2109273374157615588) | His ESP32 "T3 Pebble" device lists his T3 Code sessions, four of them titled "Cobots: …" (§5.3) | Observed |
| 15 Oct | [MacStories](https://www.macstories.net/linked/why-arent-ai-labs-apps-better/) | "We're working on our first two apps for MacStories (more in the near future)" | Claim |
| 17 Oct 11:26 | [2111418614343504107](https://x.com/viticci/status/2111418614343504107) | Week one: "Support for 20+ Apple frameworks (including Music playback and agent Shazam)", voice in the background ("either GPT-Live or Grok Voice"), background tasks, WebKit browser use, mini web apps, native subagents, "Memories and session recall" | Claim; 4 photos |
| 17 Oct | Replies (§4) | Foundation Models; cards made "At runtime in SwiftUI" | Claim |
| 17 Oct 22:13 | [2111581381310533775](https://x.com/viticci/status/2111581381310533775) | Asked "can it pick a task back up if the app gets killed?", he answers "Yep! 😄" with an 11.6 s video | **Observed video** |
| 20 Oct 14:44 | [2112555465313853810](https://x.com/viticci/status/2112555465313853810) | On the Mac: "a global quick entry on the Mac, agent split views on Mac/iPad, menu bar"; "Apple Intelligence is seamlessly integrated as a background utility"; "Code mode works beautifully"; "the latest MCP spec is also natively supported" | Claim; 4 photos |
| 20–21 Oct | — | Two more "open source?" questions go unanswered; no post about the app on 21 October | Observed |

## 4. Every reply he wrote about the app

| UTC | Question and asker | His reply | Post |
|---|---|---|---|
| 3 Oct 11:37 | "what are u building w this set up" (@kozycodes) | "My first iOS app! 😄" | 2106347902406627652 |
| 3 Oct 14:51 | "are you running local models? if so what models?" (@kozycodes) | "Thanks! Here", quoting his M5 Ultra Mac Studio review ("I've gone local-only with Hermes") | 2106396660716953819 |
| 8 Oct 13:48 | Finn Voorhees, about his PiDurableKit: "sorry, I beat you by 1 minute" | "ha! I ended up not going the JSCore route" | 2108192903688527912 |
| 8 Oct 13:50 | "Do you keep the harness running on iOS? Is it a background task when the user leaves the app?" (@ekurutepe) | "the harness supports durability out of the box, but yes, I'll also add support for long running background tasks" | 2108193428945399859 |
| 8 Oct 13:55 | Mario Zechner: "any chance you could oss the swift port? for science?" | "I'll try as soon as my Opus limits reset 🫠" | 2108194498069344679 |
| 9 Oct 19:51 | "Gonna support OpenAI compatible endpoints for local?" (@bandarbkhalid) | "yes" | 2108646482345898420 |
| 9 Oct 20:18 | Hopes for a post on an agent that "autonomously improves these apps" (@sandwichlegend) | "You know me well 😜" | 2108653302640464179 |
| 9 Oct 22:13 | "Add HomeKit to the mix!" (@alpha4th) | "On it" | 2108682188719866269 |
| 10 Oct 09:39 | "Any plans to hook it into Shortcuts for custom flows?" (@miwas_07) | "Yep!" | 2108854940504564200 |
| 12 Oct 06:55 | "Are events going through EventKit? Curious how it handles Google calendars added via Internet Accounts." (@szamski) | "Indeed" | 2109538445114650949 |
| 17 Oct 12:58 | "love the mini widgets - every agent should be doing this" (@bentossell) | "Thank you! It's super fun to design these 😄" | 2111441645682172230 |
| 17 Oct 15:44 | "can you use apple foundational model?" (@rishirsv) | "Yep! ☺️" | 2111483585920196847 |
| 17 Oct 17:56 | "how are you generating these individual components?" (@interplato) | "At runtime in SwiftUI 😄" | 2111516616601305389 |
| 17 Oct 22:13 | "can it pick a task back up if the app gets killed?" (@ashxhart) | "Yep! 😄", with the video | 2111581381310533775 |

## 5. Media

### 5.1 Inventory

| Post | Media | Size or length | Audio | Shows |
|---|---|---|---|---|
| 2108192119152140318 | 2 photos | 4096×2711, 2598×2308 | — | 3 iPhone screens, 1 Mac window |
| 2108621017539317981 | 1 photo | 2048×1276 | — | T3 Code on the Cobots-Native code base |
| 2108623467965038946 | 1 photo | 2048×2043 | — | A Mac window, bot Chef |
| 2108635610160525412 | 1 photo | 2048×1356 | — | 3 iPhone screens |
| 2109273374157615588 | 3 photos | — | — | The T3 Pebble device listing "Cobots:" sessions |
| 2111060204112458229 ("Fable 5.5 landing in my slop codebase") | Video | 3840×2160, 12.9 s | Yes, no speech | A rocket-car stunt clip with no app on screen, read as a joke about a model launch [INFERENCE] |
| 2111418614343504107 | 4 photos | 2048×2048, 3 × 2048×1356 | — | 11 iPhone screens |
| 2111581381310533775 | Video | 1206×2622, 11.6 s | Track present but digitally silent (−91 dB) | **The app resuming after a force-quit** (§5.2) |
| 2112555465313853810 | 4 photos | 2 × 2636×1956, 2644×2132, 1596×660 | — | Mac windows and the quick-entry panel |
| 2112640104762114363 | GIF | 480×468, 2.27 s | None | A reaction GIF replying to a Claude early-access call; unrelated |

Exactly one video shows the app.

**Corrected 2026-10-21 (later):** the windows in 2108192119152140318 and 2108623467965038946 are most likely the iPad build in iPadOS windowing, not a Mac. Both read "Touch and hold a bot and choose Pin … a tap away". The Chef alarm "rings even in Silent mode" (AlarmKit). The same day, his coding agent reported "Merged and on your iPhone and iPad". The first post he labels macOS is 2112555465313853810 ([full record §5](2026-10-21-viticci-full-record-sep-oct.md#5-what-each-screenshot-shows-about-where-things-run)).

### 5.2 The force-quit video (Observed)

| Time (s) | Screen |
|---|---|
| 0.0 | Dark chat with Cobot. The header reads "Cobot · Bypass · Claude Opus 5.5" and the message box "Now get my tasks due today" |
| 0.5–1.25 | "Preparing · 0s", then "Working · 0s", then a "Recalled 3" chip. The keyboard bar shows "Write with Siri" |
| 1.5–1.75 | The App Switcher shows X, T3 Code (subtitled "Cobots-…") and the app ("Thinking") |
| 2.0 | The app is swiped away. The Dynamic Island shows "Cobot / Thinking" with a stop control inside a progress ring |
| 2.25–4.0 | The island changes to "Cobot / Task failed" with a "!" |
| 4.0–4.5 | He relaunches it from the Dock icon, a winged robot; a cold-launch spinner appears |
| 4.75–5.5 | "Bots / 4 bots · 1 working". Cobot shows "● Replying…"; Researcher, ClubBot, WeatherBot and a project "iPhone Duo Review" are listed; the tabs are Bots, Cobot, Others and Search |
| 6.0–8.25 | The same turn continues: "Recalled 3", "Thinking 6s… 7s", header "Working · 6s" |
| 8.5 | "Running reminders due today", with a terminal glyph |
| 9.0 | "Worked · 1 step", then a card "REMINDERS · Today · 4 reminders" across two lists |
| 11.25 | The answer: four tasks today, none overdue. Chip: "Worked 11s · 1 step" |

**What it shows:**
- The elapsed-time counter carries across the kill (6 s at 6.5 s, 11 s in total), so the stored turn resumed rather than a new one starting [INFERENCE].
- The island sequence matches iOS 26's system interface for a user-started `BGContinuedProcessingTask` that ended unsuccessfully [INFERENCE].
- Whether any tool call ran twice is not visible.
- The on-screen clock (00:12 on Sunday) matches the posting time in Rome.

### 5.3 The code base and its work queue

All Observed. The quoted text was written on screen by his coding agent, so its contents are claims.

**T3 Code thread "Cobots-Native / Hello" (9 October).**
- "Merged and on your iPhone and iPad: **Ask before acting** (PR #14). Bots ask before they change things: you get Allow, Always Allow, or Deny right in the chat, and deletes ask every time. … You set this per bot in its profile, under Can Use › Ask First."
- It also lists "Reminders and Calendar cards".
- In progress: "the Weather hours clipping fix, AlarmKit, the Pi conformance suite, card 4's fix, paper follow-ups. The lean harness part 2 starts as soon as AlarmKit and card 4's fix leave `Tools/`."
- Changed folders: `App`, `CobotsNative.xcodeproj`, `docs`, `Durable`, `UI`.
- Status: "Waiting on 6 subagents".

**T3 Pebble session titles (11 October):**
- "Cobots: avatar generation progress, graceful failure, effort control";
- "Cobots: two-step compaction (elide old tool output first)";
- "Cobots: send key, expensive-model ask, answered cards, tab tip, hover";
- "Cobots: Apple Watch companion".

### 5.4 New details in the photos already described

The [earlier investigation](2026-10-20-native-apple-direction.md#3-the-seven-links) describes all 15 photos. Viewing them again at full resolution adds:
- **Origin post.**
  - Cobot played "Sunday Morning Call" at 2:32 PM. That request came before Shazam identified a different song, "Slide Away", at 2:40 PM. The earlier text implied the reverse order.
  - The sleep card reads "5h 58s": "s" where "m" is meant.
- **Alarms post.** An alarm created at 4:55 PM reads "in 14 h 27 min" on a screen captured around 5:03 PM, so the countdown updates live [INFERENCE].
- **Week-one post.**
  - Voice settings show "Service: Grok Voice" and an "xAI API Key" row, with voices Eve, Ara, Rex, Sal and Leo. Each bot can pick its own voice.
  - A skill card moves an existing skill into "the shared skills".
  - A helpers card for "three independent read-only checks" reads "Stopped".
  - Settings gains a "Chat Options" row.
- **Mac post.**
  - A link-preview summary carries a rosette glyph, possibly Apple Intelligence's [INFERENCE].
  - The composer shows "Write with Siri".
  - Builder keeps backups under `~/agent/state/…/backups/`.
- **Across posts.**
  - The app has a dark mode.
  - User bubbles are blue on 8–9 October and orange from 17 October.
  - Every bot shows "Bypass" from 17 October; Chef had no badge on 9 October.

### 5.5 What the app visibly does, and what is only claimed

**Observed in stills or video:**
- a roster with Projects, Pinned and "Waiting for You";
- a model per bot (GPT-6.1 Sol, Claude Opus 5.5), with effort and Fast settings;
- status chips: Thinking, Running, Worked, Recalled, Thought;
- activity steps: web search, shell (including a `cobots` command), read and write, and "Code Mode";
- cards for:
  - Reminders, with a "Changed" row and Undo;
  - Health;
  - music, with a mini-player;
  - Shazam;
  - weather;
  - timers and alarms;
  - Photos and Maps;
  - helpers (subagents);
  - browser results;
  - skill approval;
  - link previews;
- a versioned mini web app;
- voice mode with a Live Activity;
- settings rows for MCP Servers, Skills, Secrets, Python and Shortcuts;
- on the Mac: split view, a quick-entry panel, and a bot running "On Federico's Mac Studio";
  - **Corrected 2026-10-21 (later):** one bot, Builder, is labelled "On Federico's Mac Studio" in the macOS build and manages that Mac's Tailscale services; the other bots show no host ([full record §5](2026-10-21-viticci-full-record-sep-oct.md#5-what-each-screenshot-shows-about-where-things-run)).
- on the iPhone: a turn resuming after a force-quit.

**Claimed only:**
- "20+ Apple frameworks", and GPT-Live voice;
- calendar and event cards;
- that AlarmKit schedules real alarms, and how a Mac build would do it;
- HomeKit;
- iPad split views, and a menu bar;
- Apple Intelligence as a background utility, and "the latest MCP spec";
- an Apple Watch companion, and an iPad build;
- that "most of" Pi Durable was ported to Swift.

## 6. What the audience asked

220 replies by other people were retrieved across the seven threads. Keyword themes, which can overlap: features 47, how it is built 43, open source 17, TestFlight or release 14, price 3.

Reading those matches individually gives about a dozen explicit open-source requests and about a dozen requests to try it. Viticci replied to 12 of the 220 (§4). Of the open-source requests he answered only Mario Zechner's, and he answered none of the requests to try it.

Other questions he left unanswered:
- "where is pi durable running? locally?";
- "how are you handling permissions when a subagent wants to touch something like contacts mid-task?";
- "is there any guidance around what kind of UI to render or what to prompt?";
- "How will the app show a tool call that was interrupted and can't safely be retried?";
- "Nice, are they running on device models?";
- "how are you handling permission prompts across 20+ frameworks", and a similar question from another reply;
- "Can you kick a job off on the iPad and pick it up on the Mac? That would be sick." (21 Oct 21:35);
- "Will agents carry over between the Mac and the iPad split view, or stay per device?";
- "A native Swift harness makes a lot of sense now that Apple is tightening Full Disk Access because of agents. What are you doing for permissions, approve each action or full access?";
- "Will we ever get official plugins to connect Apple/iCloud services to AI Agents?".

### 6.1 Quote posts

Observed through the logged-in session. The non-English quotes are given as our English gist [translation].

| Quoted post | X counter | Found | Quotes |
|---|---|---|---|
| Origin, 8 Oct | 3 | 0 | Its Quotes page reads "No Quotes yet", and search returns nothing |
| Alarms, 9 Oct | 2 | 1 | @benvargas: "One dude with AI is beating Apple." |
| WeatherKit/MusicKit self-reply, 9 Oct | 1 | 1 | @johnvoorhees (MacStories): "There is another. More soon..." |
| Week one, 17 Oct | 12 | 11 | @sughanthans1: "Federico is a goat in the Apple community. He is making basically the grokbot for Apple ecosystem"; @ronaldmannak: "If Siri had vision"; @ashxhart: "Apple Bots"; @avgvstvs96: "this looks so well done!"; @SHAHpri3: "This Is What I Want From AI On Apple Devices". Six Chinese-language posts summarise the features [translation]: @jimmyyangrz, @ChenAaron ("Based on Pi, for Apple, it's a Bot"), @dustADD ("voice keeps going in the background, I really want this"), @KevinKKGo ("Pi Durable rewritten in Swift … will greatly improve Siri's weak experience"), @davidzhouyu and @0xmando000 (who singles out the kill-and-resume reply) |
| Mac, 20 Oct | 2 | 2 | @Phil_Holland: "VERY cool"; @ChrisPirillo: "This is incredible. The makings of a killer app." |

On John Voorhees's "There is another": on 20 October he showed "a first look at my Apple Reminders 'rescheduler' app", which Viticci reposted. Whether that is the second of the "two apps" is not stated [INFERENCE].

## 7. Context: what he wants and how he works

### 7.1 What he likes in existing products

- **Orchestration** (2 Oct, [2106094796146176008](https://x.com/viticci/status/2106094796146176008)): "My primary bot can spin up group threads with other specialized bots (coder, researcher, etc.), which can then spin up @cursor_ai cloud agents, and coordinate. … none of the other hosted/cloud assistants (Muse, Dots, etc.) currently match this."
- **His working system** (7 Oct, [2107629523814498673](https://x.com/viticci/status/2107629523814498673)):
  - "an always-on (cloud-based), self-testing setup that I've been (mostly) driving from my phone";
  - "There are outer and inner loops". Grok Bot coordinates bots and a thread per app; inside each, a Cursor project runs agents in cloud VMs that can hold env secrets;
  - "I use pstack and verification skills religiously. I want my agents and bots to be constrained to check their work, operate independently, and escalate to me only when needed";
  - routines "scan logs and analytics for errors" and hand off for review;
  - he uses voice mode during walks and starts sessions with webhooks from a Pebble ring.
- **Group coordination** (8 Oct, [2107986615419428906](https://x.com/viticci/status/2107986615419428906)): "night and day difference how the bots talk to each other and coordinate in group threads".

### 7.2 What he asked other products for

- **To Grok Bot's team** (3 Oct, [2106353594794672501](https://x.com/viticci/status/2106353594794672501)): "iOS widgets for Home Screen / Lock Screen / Control Center would be great to open specific bots or start voice mode with primary bot".
- **Pain points** (7 Oct, [2107631155268772000](https://x.com/viticci/status/2107631155268772000)):
  - "I wish voice mode worked in group chats";
  - a bot "said was going to monitor a PR, and then got lazy and forgot to merge it";
  - "The Cursor Projects view on iOS is a good start, but it's very barebones";
  - "Smarter models".

### 7.3 His tools and how he builds

- **His Apple CLIs.**
  - [RemCTL](https://github.com/viticci/remctl) (MIT) is a Reminders CLI and MCP server; its 2.0 release runs inside ChatGPT as an extension (30 Sep). He calls it "a complete reverse-engineer of Reminders based on the private ReminderKit framework" ([2105342565608219022](https://x.com/viticci/status/2105342565608219022)).
  - NotesCTL, an Apple Notes CLI, is in preview: "it's coming and it'll be free".
  - An Apple Mail CLI (MailCTL) is in progress.
- **How he builds.**
  - Claude in T3 Code orchestrates computer use on a second Mac through a Cua Space, with 8 Xcode simulators running (3 Oct).
  - "pstack coordinating everything and usually have around 20 simulators with computer use happening across 4 Macs" (7 Oct, [2107734083900203241](https://x.com/viticci/status/2107734083900203241)).
  - Club Weekly 532 covers "Multiple Claude Accounts, T3 Code, Cua Spaces, and pstack" for members; it was not read.
- **Taste over code** ([15 Oct](https://www.macstories.net/linked/why-arent-ai-labs-apps-better/)): "while I'm not writing the code, I have to spend so much time thinking about usability decisions, onboarding flows, iOS best practices, and 'it just doesn't feel right' issues that models haven't been able to abstract yet."

### 7.4 His view of the market

Source: [Connected 624](https://www.relay.fm/connected/624), 15 October, around 59:40–69:00, from auto-captions.
- **Two kinds of agent:** "agents for nerds like me that you run on your own computer" (OpenClaw, Hermes, or "make your own with the Pi harness"), and consumer agents "hosted in the cloud" (Dots, Muse).
- **What every agent has:** a harness, connectors, and "some variation of the cloud VM … usually running Linux", with a file system, a shell and a Chromium browser.
- **What he values:** tasks that run for a long time, and memory about him.
- **His prediction:** Apple will build "their own native Siri agent harness that runs directly on the OS". It would need no VM, keep memories in a background process, show tasks in Live Activities, and be "based on app intents".

### 7.5 Related MacStories coverage (Observed)

- [HomeView Points to Siri AI as the Next Developer Platform](https://www.macstories.net/stories/homeview-points-to-siri-ai-as-the-next-developer-platform/) (John Voorhees, 14 Oct): "Siri, with apps integrated through App Intents, is emerging as a new UI."
- [Perplexity Computer's Local-First Approach to Agents](https://www.macstories.net/news/perplexity-computers-local-first-approach-to-agents/) (Voorhees, 20 Oct): the local mode runs the model and the agent on the Mac and goes to the cloud only with the user's approval. Perplexity recommends at least 36 GB of memory.
- AppStories 505, "Full Disk Access in the Age of Agents" (12 Oct).

## 8. Swift ports of Pi Durable

Observed. Repositories were read at the commits listed; nothing was built or run.

| Repository | Licence | Commit read | Approach | Gaps |
|---|---|---|---|---|
| [finnvoor/PiDurableKit](https://github.com/finnvoor/PiDurableKit) | CC0-1.0 | `7288c69` (19 Oct) | Runs upstream pi-durable **1.3.0** JavaScript inside JavaScriptCore, on iOS 17, macOS 14, tvOS 17 and visionOS 1. A daily job rebuilds it against npm and runs upstream's storage and environment conformance suites. Code Mode runs through QuickJS compiled to WebAssembly | No pi-env or MCP. No shell on iOS; on macOS the shell is "not confined". Bundles subscription sign-in flows (Claude Pro/Max, ChatGPT, Copilot). Open issues: #4 (requests can hang for an hour) and #5 ("Two harnesses can open the same storage and run its tasks twice") |
| [xibbon/PiSwift](https://github.com/xibbon/PiSwift) (Miguel de Icaza's `migueldeicaza/PiSwift` redirects here) | MIT | `a73c391` (17 Oct) | A native Swift port of pi-durable **1.1.0**, landed on 9 Oct. Runs upstream examples as tests: 903 Durable test declarations, 3,754 in total. macOS 15, iOS 18 | No durable Code Mode or `tool_search`, which upstream added in 1.2.0. The Durable code is in no tagged release. Its two claims about sharing storage with the TypeScript runtime conflict |
| [rcarmo/swift-ai](https://github.com/rcarmo/swift-ai), [rcarmo/rs-ai](https://github.com/rcarmo/rs-ai) | MIT | `976f0ac`, `b509708` | Swift and Rust ports at 1.0.1 | Archived on 10 Oct |
| [rcarmo/go-ai](https://github.com/rcarmo/go-ai) | MIT | `3e74502` (16 Oct) | A Go port that claims 1.3.0 | Uses its own storage formats, not upstream's; no MCP or pi-env |

**What people said in the threads** (Observed text):
- **Miguel de Icaza,** 8 Oct: "have not done durable purely on the experimental grounds". On 9 Oct: "I updated it to have Durable support now".
- **Mario Zechner,** 9 Oct: "pi durable is still a tiny bit in flux, but the tests are very comprehensive, so following upstream should be easy."
- **Finn Voorhees,** 8 Oct: "JSCore is nice because you don't need to improve it yourself, you can just wait for @badlogicgames to do all the work".
- **Rui Carmo,** in his READMEs on 10 Oct: "I have decided to halt this project … there are a zillion people doing parallel work on this."

**Viticci's own code.** He has 10 public repositories; none is written in Swift or relates to the app. Whether 'Apple Bots' derives from PiSwift is unknown. It does not use JavaScriptCore, by his own reply.

## 9. Others building the same thing

Observed replies in the app threads:
- **Finn Voorhees:** PiDurableKit (§8).
- **@mweinbach:** "the same idea but macOS version using OpenTunnel to an iOS app that could organize threads of a bunch of other agents".
- **@MarceloMarfil:** "mine is built around regular pi + imessage".
- **@kavindpadi:** "a single pi durable that other ios apps can access".
- **@calebsmithdev** (20 Oct): "working on similar with Pi Durable as well".
- **@itstorio_** (21 Oct): "a home server with an android client, and durable jobs were the hardest part to get right".
- **@shahin43:** "pi durable agents with sandbox engines".

## 10. Apple platform facts

All Observed.

| Date | Fact | Source | Relevance to Memoshi [INFERENCE] |
|---|---|---|---|
| 2 Oct | Apple "will introduce additional controls to ensure that users who genuinely wish to grant an app this extraordinary level of access can only do so with very explicit user action", citing AI agents. It gave no mechanism and no date ("Apple did not say when", MacRumors) | [Apple](https://developer.apple.com/news/?id=p6zjojqw), [MacRumors](https://www.macrumors.com/2026/10/02/apple-announces-macos-full-disk-access-changes/) | Draft 4 does not use Full Disk Access. Approaches that read other apps' private databases, as RemCTL does, become harder |
| 1 Oct | The original Developer ID Certification Authority (Sub-CA) expires on 1 February 2027:<br>• certificates it issued stop working that day;<br>• `.pkg` installers signed with them stop installing;<br>• notarized apps with a secure timestamp keep working.<br>New certificates come from the G2 Sub-CA and must be renewed every year | [Apple](https://developer.apple.com/news/?id=w4atic4c) | Ship-path spike S5 should issue G2 certificates. Yearly renewal becomes a release-calendar item |
| 13 Oct | The Developer Program License Agreement adds terms for a Live Assistance API, an App Replacement Entitlement and HomeView widgets | [Apple](https://developer.apple.com/news/?id=17mwd36z) | Terms not yet read; check them before the iPhone phase |
| 16 Oct | App Review Guidelines add 2.5.19, on "hidden, dormant, or undocumented features", and clarify 1.2 | [Apple](https://developer.apple.com/news/?id=92th7e5i) | Applies to generated mini apps and downloaded skills on iPhone, alongside 2.5.2 and 4.7 |

## 11. Corrections to earlier documents

Each corrected document now carries a dated note pointing here.

| Document | Earlier statement | Correction |
|---|---|---|
| [Native Apple direction §1](2026-10-20-native-apple-direction.md#1-summary) | "'Apple Bots' appears only in still images … None of the Viticci posts has a video." | True of the five supplied posts only. A reply ([2111581381310533775](https://x.com/viticci/status/2111581381310533775)) carries an 11.6 s video of the app (§5.2) |
| [Native Apple direction §3.2](2026-10-20-native-apple-direction.md#32-post-1-the-origin-post-2026-10-08) | Lists the Shazam result, then playback | The song played ("Sunday Morning Call", 2:32 PM) came before the Shazam result ("Slide Away", 2:40 PM) |
| [Native Apple direction §4](2026-10-20-native-apple-direction.md#4-demonstrated-claimed-or-inferred-apple-bots) | Background tasks: "Claimed" | Partly observed. A system activity appears when the app is left, and the turn resumes after a force-quit |
| [Native Apple direction §9](2026-10-20-native-apple-direction.md#9-open-questions) | Ship or open-source: "Unknown. Nothing beyond 'stay tuned' was found." | An App Store release is planned (Claim, 9 Oct); on open source, "I'll try" (8 Oct); no date for either |
| [Comparison report §9](2026-10-20-comparison-report.md#9-the-viticci-direction-native-utility-not-merely-native-looking-chat) | "All of the supplied Viticci media are still images, not videos." | True of the supplied posts only; see §5.2 |
| [NEXT_VERSION §4](../plan/NEXT_VERSION.md#native-scope-by-device) | "Four supplied posts show it in still images"; keep Node "rather than introducing a second harness port" | The evidence now includes a video and public Swift and JavaScriptCore routes (§8). Where Pi runs is under discussion; the proposal's recommendation stands until it is decided |

## 12. Evidence storage

**Where.** The raw evidence is in `~/Documents/memoshi/evidence/2026-10-21-viticci-apple-bots/`, outside the repository. It is third-party media and other people's personal data, and the repository is meant to become public under Apache-2.0. The same rule keeps Kuvo captures out under [D43](../plan/decisions.md#d43).

**What it holds:**
- original photos and videos, plus extracted frames and crops;
- API responses: timelines, thread pages, Bluesky and Mastodon feeds, and the parsed quotes and replies from the logged-in X session (`raw/x_session_quotes_and_replies_2026-10-22.json`);
- podcast captions and transcripts;
- the research agents' working reports;
- `MANIFEST.tsv`, which lists the path, size, SHA-256 and source of each file.

**Size and integrity.** 336 files, about 102 MB. SHA-256 of `MANIFEST.tsv`: `bbb8d4147d3c8135256dcfd8d1cd97b56eaf5ef352636b7365777351d2cc45a6`. The folder's `README.md` has the check command.

**Not kept:**
- the cloned repositories (§8 records their commits);
- the podcast audio;
- the logged-in page captures, which contain the account's page state;
- the temporary working folders.

## 13. Limits

- **Quote posts:** 15 of the 20 that X counts were found. The origin post's 3, and one each on the alarms and week-one posts, did not appear on their Quotes pages, even scrolled to the end, or in search. They may be deleted, protected or filtered by X [INFERENCE].
- **Replies:** 184 of 197 direct replies (93%) were found. None of the seven app posts has replies hidden by Viticci; each post's Hidden replies page is empty. The other 13 appear under no sort order and no reveal control (§2).
- **Paywalled material was not read:** Club MacStories Weekly 532's article, AppStories+ and Connected Pro. Brave is not signed in to Club MacStories.
- **Transcripts are machine-made:** captions are auto-generated and the local transcripts come from whisper, so quotes from them are approximate.
- **Audio:** the force-quit video's audio is digital silence; the joke video has sound but no speech.
- **Nothing was installed, built or run.** The X account was used read-only: nothing was posted, liked or followed. The only controls pressed were X's "Show replies", "Show probable spam" and reply-sort menus.

## Sources

- **X posts:** the IDs above, retrieved through the FxEmbed v2 API (`api.fxtwitter.com`: profile `statuses` with and without replies, `media`, `conversation`, `status`) on 20–21 October 2026. Quote posts and late replies were read through the user's logged-in X web session on 22 October 2026.
- **MacStories:**
  - [Building iOS Apps with Multiple Claude Accounts, T3 Code, Cua Spaces, and pstack](https://www.macstories.net/club/macstories-weekly-issue-532/building-ios-apps-with-multiple-claude-accounts-t3-code-cua-spaces-and-pstack/) (public teaser);
  - [Why Aren't AI Labs' Apps Better?](https://www.macstories.net/linked/why-arent-ai-labs-apps-better/);
  - [HomeView Points to Siri AI as the Next Developer Platform](https://www.macstories.net/stories/homeview-points-to-siri-ai-as-the-next-developer-platform/);
  - [Apple Announces Plan to Impose New Full Disk Access Controls on Mac Developers](https://www.macstories.net/linked/apple-announces-plan-to-impose-new-full-disk-access-controls-on-mac-developers/);
  - [Perplexity Computer's Local-First Approach to Agents](https://www.macstories.net/news/perplexity-computers-local-first-approach-to-agents/).
- **Apple Developer news:**
  - [Updates to Full Disk Access in macOS](https://developer.apple.com/news/?id=p6zjojqw);
  - [Upcoming expiration of Developer ID Certification Authority (Sub-CA)](https://developer.apple.com/news/?id=w4atic4c);
  - [Updated Apple Developer Program License Agreement](https://developer.apple.com/news/?id=17mwd36z);
  - [Updated App Review Guidelines](https://developer.apple.com/news/?id=92th7e5i).
- **Other coverage:** [MacRumors on Full Disk Access](https://www.macrumors.com/2026/10/02/apple-announces-macos-full-disk-access-changes/).
- **Podcasts:**
  - [Connected 623](https://www.relay.fm/connected/623) and [Connected 624](https://www.relay.fm/connected/624);
  - AppStories 504–506 (YouTube `0XCvw7skfpo`, `gDcVjiwsIgk`, `kBkwsXLBM44`);
  - the [MacStories Unwind](https://feeds.transistor.fm/macstories-unwind) and [NPC](https://feeds.transistor.fm/npc-next-portable-console) feeds.
- **Repositories:** [PiDurableKit](https://github.com/finnvoor/PiDurableKit), [PiSwift](https://github.com/xibbon/PiSwift), [swift-ai](https://github.com/rcarmo/swift-ai), [rs-ai](https://github.com/rcarmo/rs-ai), [go-ai](https://github.com/rcarmo/go-ai), [RemCTL](https://github.com/viticci/remctl).
