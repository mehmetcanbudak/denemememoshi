# Native Apple direction: the seven posts, their design grammar, and what Apple platforms allow

**Status:** Research · 2026-10-20
**Owns:** Evidence for a native Swift Mac and iPhone assistant with Apple-style interactive cards, music playback, Shazam and real system integration: the outcome for each of the seven links the user supplied, what they demonstrate versus claim, the platform constraints, and a recommendation for Memoshi's next-version spec
**Depends on:** [decisions](../plan/decisions.md) ([D27](../plan/decisions.md#d27), [D29](../plan/decisions.md#d29), [D41](../plan/decisions.md#d41), [D43](../plan/decisions.md#d43)) · [02-experience §7 Cards](../plan/02-experience.md#7-cards) · [09-platform-macos](../plan/09-platform-macos.md) · [feature catalog](../plan/feature-catalog.md) · [Apollo's Apple integrations](agentic-workspace-landscape/landscape/in-house-assets.md#apple-integrations) · [Grok Bot profile](agentic-workspace-landscape/projects/grok-bot.md)

Research is evidence, not a decision ([research index](README.md)). Nothing here changes [D43](../plan/decisions.md#d43) (v1 matches Kuvo Code on shared surfaces), [D41](../plan/decisions.md#d41) (no host Accessibility or ScreenCaptureKit in v1 or v1.1) or the phase plan (the iPhone app is Phase 5). §7 is input for a next-version spec and goes through [change control](../plan/decisions.md#change-control).

Markers follow the [research conventions](README.md#5-conventions): `[INFERENCE]` is our reasoning, "(author claim)" is a statement by a post's author that we could not verify, and "unknown" means searched and not found. **No hands-on validation:** nothing was installed, run, signed into or tested. Screenshots and video frames were viewed; they show UI states, not behaviour.

---

## 1. Summary

1. **What the links are.** Four of the five Federico Viticci posts show his private prototype, which he only ever calls 'Apple Bots', in quotes: a Swift app for which he "ported most of" Pi Durable to Swift, with native Apple integrations. His fifth post (2026-10-14) is about Grok Bot (`@bot`), not his app. Oscar Hong's post is **Agent Bump**, a hackathon web app that pairs two people's agents. Arne Strickmann's post shows the **Quick actions** feature of **Personal Agent Proxy** (MIT).
2. **What is demonstrated.** 'Apple Bots' appears only in still images: 23 phone and Mac screens across 12 images. None of the Viticci posts has a video. Stills prove a screen existed, not that a checkbox toggles or a song plays. The two videos (Agent Bump, 19.6 s; Personal Agent Proxy, 16.5 s) were viewed as sampled frames.
   - **Corrected 2026-10-21:** this holds for the five supplied posts only. A later reply carries an 11.6 s video of the app resuming a task after a force-quit ([full record §5.2](2026-10-21-viticci-apple-bots-record.md#52-the-force-quit-video-observed)).
3. **The design grammar worth taking.**
   - Cards are typed views of real system objects. Each is labelled with its source, how fresh it is and which bot acted.
   - A change shows the old and new value, with Undo.
   - Generated mini apps show a dated snapshot and send changes back through the agent.
   - Work folds into "Worked 13s · 3 steps" chips, with an Activity pane beside the transcript.
   - Installing a capability still asks, even while the bot runs in "Bypass".
4. **Platform reality.**
   - Native macOS lacks several capabilities the screenshots rely on: `SystemMusicPlayer`, `MPMusicPlayerController`, AlarmKit, starting a Live Activity, HomeKit, Health data and EventKit UI.
   - A Developer ID–signed Mac app, which is how Memoshi ships ([09 P6](../plan/09-platform-macos.md)), cannot get the WeatherKit capability.
   - iOS has no public way to drive another app's UI, and no unbounded background execution.
5. **Recommendation (§7).**
   - Keep the Card as the one-shot decision with an immutable receipt.
   - Add a separate **live object view**: a native SwiftUI view bound to a system object such as a reminder, an event or a track, rendered by Memoshi.app as the capability host.
   - Start on the Mac with EventKit and in-app music, and identify songs by microphone only.
   - Route phone-only frameworks (Health, Home, AlarmKit, control of the Music app) through the iPhone client, and only while the user is present.

### 1.1 Feature coverage

| What the user wants | Shown in the posts | Mac (native, Developer ID, no App Sandbox) | iPhone (App Store) | Plan today |
|---|---|---|---|---|
| Interactive Reminders cards | Yes: list and "Today" cards with a change row and Undo (stills) | Yes, within public EventKit; no sections, tags, subtasks or smart lists | Yes, same limits | [AP-08](../plan/feature-catalog.md) Calendar and Reminders connector, Phase 3, P2; no live view |
| Calendar events | Claimed ("events"); no event card seen | Yes; Memoshi draws its own editor (no EventKit UI on macOS) | Yes; EventKit UI editor needs no calendar access on iOS 17+ | AP-08 |
| Music playback | Yes: "Played by Cobot" player, album tiles, queue menu | Yes, in-app (`ApplicationMusicPlayer`, macOS 14+) | Yes, in-app and by controlling the Music app | None |
| "What am I playing?" | Yes (iPhone) | No API; Apple Events to Music.app only | Yes (`SystemMusicPlayer`, `MPMusicPlayerController`) | None |
| Shazam | Yes: a Shazam song card (iPhone) | Yes by microphone; this Mac's own audio needs a Core Audio tap and a new permission | Yes by microphone | None |
| Alarms and timers | Yes: timer and alarm cards (on a Mac) | No (AlarmKit is iOS, iPadOS and Mac Catalyst 26) | Yes; alarms break through Focus and silent mode | None |
| Weather | Yes, with Apple Weather attribution | Only through the WeatherKit REST API | Yes (WeatherKit) | None |
| Health charts | Yes (iPhone) | No (`isHealthDataAvailable()` is false on macOS) | Yes | None |
| Home accessories | Bot text only ("only the Outdoor Plug is currently on") | No (HomeKit is Mac Catalyst only) | Yes | None |
| Photos and Maps cards | Yes | Yes | Yes | None |
| Voice in the background | Yes: a Live Activity with Mute and End | Not needed; the Mac app keeps running | Background audio mode plus a Live Activity | [V2-09](../plan/feature-catalog.md) voice conversation, Phase 6 |
| Generated mini apps | Yes: "Your task garden · Version 6 of 6" | Web content in a sandboxed view ([D29](../plan/decisions.md#d29)) | App Review 4.7, 4.7.2 and 4.7.3 apply | Inline widgets, Phase 2 |
| App Intents and Shortcuts | A "Shortcuts" settings row | Yes | Yes | [AP-05](../plan/feature-catalog.md), Phase 2 |
| Widgets and Live Activities | A Live Activity | Widgets yes; Live Activities only mirrored from a paired iPhone | Yes | AP-07 widgets, Phase 3; iPhone, Phase 5 |
| Global quick entry, menu bar | Quick-entry panel shown; menu bar claimed | Yes | Not applicable | QuickAsk in the menu bar extra with an optional hotkey ([02 §11.4](../plan/02-experience.md)) |

---

## 2. Method

**X posts.** Each post was read four ways, and the readings were compared.

| Route | What it returns | Trust |
|---|---|---|
| The `read` tool on the `x.com` URL | Text relayed by a model (xAI `x_search`), plus selected replies and metrics | Relay; never used alone |
| X's syndication endpoint, `https://cdn.syndication.twimg.com/tweet-result?id=<id>` | Exact text (cut at about 280 characters for long posts), UTC time, mentions, media types and sizes, video variants and durations | X-owned; primary |
| X's oEmbed endpoint, `https://publish.x.com/oembed?url=…` (post 3 only, after the first read failed) | The opening text as embed HTML | X-owned; primary |
| FixTweet's API, `https://api.fxtwitter.com/<user>/status/<id>` | The full text of long posts | Third-party mirror; used to cross-check the relay |

For all seven posts, the relay and FixTweet agree word for word. Syndication matches the opening of every post. The authors' self-replies cited below were also confirmed through syndication.

**Media.**
- All 15 photos in the seven posts and Viticci's self-reply were viewed at up to 2,048 px, from `pbs.twimg.com` with `name=large`.
- Both videos were downloaded to `/tmp` and viewed as frames: Agent Bump as a 6-frame grid plus frames at 8 s and 17 s; Personal Agent Proxy as a 6-frame grid plus frames at 1.5, 5, 9 and 14.5 s.
- The Personal Agent Proxy video has no audio track. Agent Bump's AAC audio was not heard.
- Nothing was saved into this repository, and the temporary files were deleted.
- The video quoted in Arne Strickmann's post (from @anishfn) was not viewed.

**Corroboration.**
- MacStories, through its site search and a direct read of the one matching review.
- Viticci's GitHub, Mastodon and Bluesky accounts.
- xAI's docs and the Grok Bot changelog feed.
- Personal Agent Proxy's GitHub repository and docs, the Shapeshift README, and Y Combinator's event page.

**Apple facts.**
- Context7 was tried first and failed with "Monthly quota exceeded".
- Availability and quotes therefore come from Apple's documentation JSON (`developer.apple.com/tutorials/data/documentation/<path>.json`), which is the data behind the linked doc pages.
- Also used: Apple Developer Account help (App Services and the macOS capability table), Apple Support (Shortcuts) and the App Review Guidelines (last updated 2026-10-16).
- Platform lists below are Apple's availability metadata as of 2026-10-20.

**Not done.** No product was installed or run, no TestFlight was used, and no downloaded code was executed. Kuvo Code was not consulted.

---

## 3. The seven links

### 3.1 Outcomes

| # | Link | Author, time (UTC) | Retrieval | What it is | Media viewed | Relevance |
|---|---|---|---|---|---|---|
| 1 | https://x.com/viticci/status/2108192119152140318 | Federico Viticci, 2026-10-08 13:45 | Retrieved; relay, syndication and FixTweet agree | 'Apple Bots' origin post | 2 photos: 3 iPhone screens and 1 Mac window | High: Health, Music and Shazam cards; Activity pane |
| 2 | https://x.com/viticci/status/2112555465313853810 | Viticci, 2026-10-20 14:44 | Retrieved; a long post, so the full text comes from the relay and FixTweet, which agree | 'Apple Bots' on macOS | 4 photos: 3 Mac windows and a quick-entry panel | High: Reminders card, split view, quick entry |
| 3 | https://x.com/viticci/status/2111418614343504107 | Viticci, 2026-10-17 11:26 | The first read failed (xAI error 500, "Internal error during token parsing"); a retry succeeded, and oEmbed and syndication confirm the opening | 'Apple Bots' after one week | 4 photos: 11 iPhone screens | High: music, voice, Live Activity, mini app, settings |
| 4 | https://x.com/viticci/status/2110282174440017929 | Viticci, 2026-10-14 08:10 | Retrieved | Grok Bot's proactivity, not 'Apple Bots' | 1 photo: one iPhone screen | Medium: an assistant offers work through a question card |
| 5 | https://x.com/viticci/status/2108623467965038946 | Viticci, 2026-10-09 18:19 | Retrieved, with the author's self-reply [2108635610160525412](https://x.com/viticci/status/2108635610160525412) at 19:08 | 'Apple Bots' alarms, reminders and events | 1 photo (Mac); the self-reply has 1 photo (3 iPhone screens) | High: timer and alarm cards, Reminders list, weather alert, now playing |
| 6 | https://x.com/oscrhong/status/2112267545638207767 | Oscar Hong, 2026-10-19 19:40 | Retrieved; a self-reply corrects the hashtag | Agent Bump, a hackathon web app | Video, 19.6 s; 2 photos | Low to medium: a cross-user agent handshake |
| 7 | https://x.com/arnestrickmann/status/2112341539154542928 | Arne Strickmann, 2026-10-20 00:34 | Retrieved; a self-reply links personalagentproxy.com | Personal Agent Proxy's Quick actions | Video, 16.5 s, no audio | Medium: instant typed widgets; owner actions versus agent actions |

**Product names.**
- **Posts 1, 2, 3 and 5.** Viticci writes 'Apple Bots' or "Apple Bots", always in quotes; it reads as a working label. No website, App Store page, TestFlight or repository was found. A web and X search on 2026-10-20 found no other name.
  - The screenshots name bots, not the app: Cobot, MusicBot, Pixel, Builder, Researcher, ClubBot, WeatherBot, Coach, Planner, Chef and Scribe.
  - Activity rows read "Ran cobots …" (Shell), and one bot's message mentions a "Cobots Gallery". So "cobots" may be the app's command namespace or an internal name [INFERENCE].
- **Post 4.** The app is Grok Bot: xAI's docs say "Tag @bot in a post or reply on X to hand that post to your Grok Bot as a task" ([tag on X](https://docs.x.ai/grok-bot/tag-on-x)).
- **Post 6.** The names all come from the media: "Agent Bump" on a slide, "AGENTBUMP" on the in-app card, "bumpmyagent" in chat text, and "Muse2Muse via BMA" as a caption.
- **Post 7.** The product is Personal Agent Proxy, from Arne Strickmann's self-reply and its [README](https://github.com/personalagentproxy/proxy), which credits @hkonsti_ and @arnestrickmann.

### 3.2 Post 1: the origin post (2026-10-08)

> my ideal 'Apple Bots' product doesn't exist
>
> so I ported most of @badlogicgames' Pi Durable to Swift and ended up with a functioning, lean harness with a bunch of Apple integrations and it's already pretty useful…?
>
> am I actually doing this?

**Image 1: three iPhone screens of the bot "Cobot".** The header reads "GPT-6.1 Sol · Fast"; the composer chip reads "GPT-6.1 Sol Medium".
- **Sleep.** "What about my time slept?" leads to a "Worked 13s · 3 steps" chip and a card titled "Your sleep over the last week", sourced "Apple Health · October 2–8…". The card has two stat tiles, a bar chart of six recorded nights, and share and expand buttons. The text answer excludes one night as "missing data, not zero sleep".
- **A stated limit.** A message says the Reminders tool knows "whether a task is completed—not when it was completed". It offers to "chart completed reminders by list from the last 90 days—the history this tool makes available".
- **Now playing.** "What am I playing now" ("Worked 8s · 1 step") gets an answer naming the song and album "in the Music app".
- **Shazam.** "Shazam it" leads to "Worked 2m 11s · 1 step", then "Shazam confirmed it—see the song card." The card shows artwork, a "Shazam" label, title and artist, with **Play Here** and **Apple Music** buttons.
- **Playback.** "Yes—it's in your library. Playing it here now." The player card reads "Played by Cobot", with title, artist, a scrubber (0:00 / −5:12) and back, play and forward buttons.
- **Corrected 2026-10-21:** the order is the reverse of this list. Cobot played "Sunday Morning Call" at 2:32 PM, before Shazam identified "Slide Away" at 2:40 PM ([full record §5.4](2026-10-21-viticci-apple-bots-record.md#54-new-details-in-the-photos-already-described)).
- **Steps.** A steps card from Apple Health shows a total and a bar chart.

**Image 2: a Mac window.**
- **Sidebar.** An empty pinned area reads "Pin your bots: Touch and hold a bot and choose Pin. Its face sits here, a tap away." The touch wording suggests copy shared with the iPhone app [INFERENCE]. Below it are roster rows for MusicBot and Cobot.
- **Chat.** MusicBot is asked to use the user's library and web search to list ten widely praised Oasis B-sides that the user owns. After "Worked 12s · 2 steps" it says "My earlier answer wasn't properly verified—sorry about that." After "Worked 48s · 9 steps" it answers with a table (# · B-side · Version you have).
- **Activity pane.** "MusicBot · Worked 1m 15s · 11 steps · Today, 3:04 PM to 3:05 PM". Each step has a kind and a duration:
  - "Searched the web for …" and "Read radiox.co.uk" (Web Search);
  - "Ran cobots music library search …", "Ran curl -L -s …" and "Ran sed …" (Shell);
  - "Read queue.txt" (Read) and "Wrote queue.txt" (Write).

**Replies seen through the relay.**
- Mario Zechner: "noice!"
- Finn Voorhees quoted his own announcement of a Swift wrapper that runs pi-durable in JavaScriptCore. That is [PiDurableKit](https://github.com/finnvoor/PiDurableKit) (CC0-1.0, created 2026-10-08). Whether 'Apple Bots' uses it is unknown; Viticci says he "ported" Pi Durable to Swift.

**Limits.**
- A Dynamic Island pill labelled "T3 · Done" is visible. The post-3 screenshots show a T3 app in the Dock, so the pill probably belongs to that app, not to 'Apple Bots' [INFERENCE].

### 3.3 Post 5 and its self-reply: alarms, reminders and events (2026-10-09)

> My "Apple Bots" app based on Pi Durable in Swift can now set alarms, reminders, events, and more 😎
>
> Watch as I create a better Siri AI lol

The attachment is a still photo (syndication type `photo`), not a video, despite "Watch".

**The Mac window.**
- **Sidebar.** The same "Pin your bots" empty state, then a roster: Coach ("Keeps you moving"), Planner ("Plans the week"), Chef ("Done: the run alarm is off and the eggs are cancelled."), Scribe and Researcher.
- **Chef's chat (GPT-6.1 Sol).**
  - **Timer.** "Pause the bread dough, I'm heading out." ("Worked 5s · 1 step") gets "Paused with 23 minutes to go. Resume it when you're back." The card reads "TIMER · CHEF / Bread dough / Paused", with a ring showing 23:00 and **Resume** and **Cancel** buttons.
  - **Alarm.** "Wake me up at 7:30 tomorrow." gets "Set for 7:30 tomorrow. It rings even in Silent mode." The card reads "ALARM · CHEF / Wake up / Tomorrow · in 14 h 27 min / 7:30 AM", with **Cancel**.
  - **Second timer.** "And four minutes for the tea." gets "Tea's steeping." and a second timer card, cut off.

**Self-reply** ([2108635610160525412](https://x.com/viticci/status/2108635610160525412)):

> WeatherKit, MusicKit, Reminders, AlarmKit – I'm going to do it all, and let you use native Apple tools with ANY frontier model, in a clean UI, with crazy good performance and mini interactive interfaces.
>
> Wish me luck. 😌

**Its image: three iPhone screens of the bot "Researcher".**
- **Work list.** "What's in my Work list?" gets a card reading "WORK / Work / 15 reminders". Each row has a circle checkbox, a title, a due or repeat line and a "…" menu, followed by "Show 10 More" and a text summary of the open tasks.
- **Weather.** "Weather data from Apple Weather." The card has:
  - an alert row, "Yellow Warning for Thunderstorm", from a national meteorological service;
  - current conditions, an Hours/Days switch, hourly forecasts and a chart;
  - "Weather · Legal" with the Apple logo, "Updated 8:52 PM", a refresh button and **Open in Weather**.
- **Now playing.** "Play underneath the sky." gets a "Now Playing · Researcher" card with a scrubber and back, pause and forward buttons.

**Limits.**
- AlarmKit exists only on iOS, iPadOS and Mac Catalyst 26 ([AlarmKit](https://developer.apple.com/documentation/alarmkit)). So either the Mac build is Mac Catalyst or the iPad app running on a Mac, or the alarms are scheduled on another device, or the cards schedule no real alarm. Which one is unknown.
- "It rings even in Silent mode" is the bot's text, not something we observed. It matches AlarmKit's documented behaviour, which "overrides both a device's focus and silent mode" ([sample](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)).
- An orange countdown-style glyph appears in the Dynamic Island on two screens. Its owner app is unknown.

### 3.4 Post 3: one week of progress (2026-10-17)

> One week of progress on my 'Apple Bots' app based on @badlogicgames' Pi Durable, in Swift. We got:
>
> - Support for 20+ Apple frameworks (including Music playback and agent Shazam)
> - Voice mode that works in the background (either GPT-Live or Grok Voice)
> - Background tasks
> - WebKit browser use
> - Create your own mini web apps
> - Native subagents
> - Memories and session recall
>
> And so much more. I'm genuinely making the agent app of my dreams for Apple platforms.
>
> Stay tuned here for lots more soon 🤖

From here on, every bot header carries an orange **Bypass** badge with an open padlock.

**Image 1: weather and music (two screens).**
- **Weather.** Cobot answers a weather question and adds "On the balcony, only the Outdoor Plug is currently on; I haven't changed anything." That is a home-accessory read, shown only as text. The weather card has:
  - a place name, the current temperature and condition, and feels-like, high and low values;
  - an Hours/Days switch and seven daily rows with rain chance and temperature bars;
  - "Weather · Legal" with the Apple logo, "Updated 1:22 AM", refresh and **Open in Weather**.
- **Mini-player and chrome.** A mini-player bar above the composer shows the track and album, with pause and close. The composer has a model chip, an effort chip ("High"), a fast toggle, and voice-mode and dictation buttons. The tab bar reads "Bots · Cobot · Others · Search".
- **Music.** A "Recalled 1" chip precedes "Playing … from Be Here Now (Deluxe Remastered Edition)." Two album tiles follow: one playing, with pause and speaker glyphs, and one with a play button. A context menu on a song offers **Play, Play Next, Add to Queue, Get Apple Music Link** and **View in Apple Music**.

**Image 2: voice, a skill approval and a Live Activity (three screens).**
- **Voice Mode settings.** The screen reads: "Voice mode talks through xAI's Grok Voice, so it needs an xAI API key: the Grok sign-in doesn't include it. Grok Voice costs about $0.08 a minute, billed to that key. Your bot keeps thinking with its own model and provider, like ChatGPT, Claude or Gemini." It has a Service picker and five voices, each with a short description; voice "samples are on this device and cost nothing".
- **Skill approval.** Cobot shows "Working · 23s" under a "Waiting for you · 23s" bar, then a card: "Install this skill? Cobot wants to install the skill notion-daily-notes." The card lists, each line marked with "+":
  - Skill, and When to Use It;
  - For: "Every bot";
  - Files: `SKILL.md` and a references file;
  - a preview of the skill's front matter.
- **Live Activity.** On the Home Screen, an expanded Dynamic Island Live Activity shows a Reminders "Today" list (two timed items, "1 MORE"), a 0:20 timer, and **Mute** and **End**.

**Image 3: Photos, Maps and settings (three screens).**
- **Photos.** A card reads "PHOTOS / October 2026 / October 15–17 · 59 photos and 1 video", with a hero image, a grid ending "+47", and share and expand. It sits under a voice bar reading "You / Cobot …", "Speaking 2:17", with microphone, keyboard and **End**.
- **Maps.** A card reads "MAPS / [place]", with a map pin, a Look Around thumbnail, an address line, **Open in Maps** and **Directions**. It sits under "Listening 2:24".
- **Settings.**
  - Providers & Models (8), Helpers, Speech & Dictation (ElevenLabs), Voice Mode (Ara), Images (GPT Image 2.5 Sunburst).
  - Under "What Bots Can Use": Tools & Access (36 tools), Skills (2), MCP Servers (3), Linked Folders (2), Secrets, Python and Shortcuts.

**Image 4: a mini app, helpers and the browser (three screens).**
- **Mini app.** A generated page titled "Your task garden" carries a "Version 6 of 6" switcher. It shows:
  - "TASK GARDEN · OCT 17, 12:18 PM / 1 wilting, 2 to bloom";
  - tabs Today 3, Tomorrow 4 and Past due 1;
  - an illustration that places reminders as flowers at their times;
  - a reminder card with a list chip, its due time, "Blooms in 6h 42m", **Ask Cobot** and refresh;
  - the footer "Reminders snapshot · October 17, 12:18 PM, [city]. Refresh asks Cobot to fetch the latest tasks. No reminders are changed here.";
  - a field reading "Ask Cobot to change it".
- **Helpers.** "Worked 1m 25s · 4 steps" leads to a card reading "HELPERS / The helper stopped". It shows the delegated task and "Stopped · 43s · GPT-6.1 Sol · High · Fast".
- **Browser.** "Meanwhile use your browser here to browse MacStories" leads to "Recalled 3", an inline browser page and "Thinking 8s". The next screen says "MacStories is open in my browser…" and shows a card: "DONE / MacStories / Homepage opened in the browser", with **View**, two thumbnails, "Done by Cobot · 2 steps · 20s" and **Watch Steps**.

**Replies seen through the relay.**
- Ben Tossell: "love the mini widgets - every agent should be doing this".
- Another reply asks how permissions work "when a subagent wants to touch something like contacts mid-task?". No answer from the author was found.

**Limits.**
- Stills only.
- That the Live Activity is the background voice session is [INFERENCE] from its Mute and End buttons; the screen does not say which app owns it. Whether the agent keeps reasoning while backgrounded is not shown.
- HomeKit appears only as bot text.
- "20+ Apple frameworks" can't be counted from the media; about nine are visible across all four 'Apple Bots' posts (§4).

### 3.5 Post 2: an early look on macOS (2026-10-20)

> A *very* early look at my 'Apple Bots' app based on Pi Durable, running on macOS.
>
> The app will take advantage of the unique features of each Apple device. That means a global quick entry on the Mac, agent split views on Mac/iPad, menu bar, and more.
>
> No native Apple framework will be ignored because I'm making the app I've always wanted.
>
> Apple Intelligence is seamlessly integrated as a background utility, and you can use any combination of models you want. Code mode works beautifully (thanks @badlogicgames) for tool-calling, and the latest MCP spec is also natively supported.
>
> Lots of work to do still, but getting to a usable state!

**Image 1: a three-pane window.**
- **Sidebar.**
  - A search field, "Bots and Messages".
  - "Waiting for You" (1), "Library", "Pages" and "Activity".
  - "Projects", with "+" and "Start a project: A board of tasks for your bot…".
  - "Pinned": Cobot ⌘1 and Builder ⌘2.
  - "Bots": Pixel, MusicBot, Researcher, ClubBot and WeatherBot, then "Archived".
- **Toolbar.** "…", a raised-hand glyph with a badge of 1, a bot picker and a sidebar toggle.
- **Chat with Pixel** ("Bypass · Claude Opus 5.5 · Fast"). The user pastes a link, which shows as a link chip. "Worked 11s · 2 steps" leads to an answer that ends "Want me to remove it?". The composer has "+", a model chip with effort and fast glyphs, and voice and dictation buttons.
- **Activity pane.** "Thought" rows with excerpts and durations; "Ran cobots curl -s -X POST https://api.firecrawl.dev/v2/scrape …" (Shell); and "Ran a script · Code Mode · 2 calls".

**Image 2: a link preview.** A popover shows the site, title and summary, with **Open**, **Copy** and **Share**. A right-hand panel reads "1 Link · Your message · 4:31 PM".

**Image 3: two bots side by side.**
- **Left: Cobot** ("Bypass · Claude Opus 5.5"). "What are my tasks due today?" leads to "Worked 18s · 2 steps" and a Reminders card:
  - "REMINDERS / Today / 9 reminders · 5 overdue · 1 done";
  - a change row: "Changed · Due ~~Tue, Oct 20, 11:00 AM~~ → Wed, Oct 21, 11:00 AM";
  - sections WORK and REMINDERS, with circle checkboxes, due lines, repeat markers and disclosure chevrons;
  - one completed row, struck through, reading "Done Today, 4:38 PM";
  - "Show 4 More", **Undo**, and share and expand buttons.
- **Right: Builder** ("Bypass · On Federico's Mac Studio · Claude Opus…"). Builder reports which Tailscale-published addresses it closed, naming "RemCTL, MailCTL, MusicCTL, NotesCTL and PhotoCTL" as sharing one address. It also says "Cobots Gallery on :8460 is still published", and lists a backup and an uncommitted config change it left for the user.

**Image 4: quick entry.** A floating panel shows a bot avatar and name with a picker ("Cobot ⌃⌄"), the text "What are my tasks due today?", a microphone and a send button.

**Limits.**
- The menu bar extra, iPad split views and Apple Intelligence are claimed but not shown.
- Whether the Mac app is native AppKit/SwiftUI, Mac Catalyst or the iPad app is unknown.

### 3.6 Post 4: Grok Bot's proactivity (2026-10-14)

> Here's a good example of @bot's proactive nature:
>
> It noticed that Gemini 4 Argon came out, knew that none of our @macstoriesnet internal apps use a Gemini model, and offered to start testing it.
>
> My bot is set up to test new features with @poteto's pstack + @cursor_ai cloud agents in VMs, so we can quickly evaluate changes before shipping to prod across all apps.
>
> All from a single proactive question I got this morning. This is very nice.

**Image: one iPhone screen.**
- The chat header reads "Assistant".
- A message summarizes the model's availability: it checked "Google's model page", lists context and pricing, and says "None of the MacStories apps use a Google model today, so this would be our first."
- A question card asks "Should Coder test Gemini 4 Argon on the test machine?". It offers lettered options: A "Yes, run a test-machine eval first", B "Add it to the apps like Haiku 5.5" and C "Keep Google out for now", plus a close button.
- The composer reads "Ask Assistant", with microphone and voice buttons.

**Corroboration.**
- xAI's docs identify `@bot` as Grok Bot ([tag on X](https://docs.x.ai/grok-bot/tag-on-x)).
- Grok Bot 0.66.0 (2026-10-02): "Your primary Bot, marked with a star, will now spot work it can take off your plate and offer to handle it." ([changelog](https://x.ai/changelog/bot#v0.66.0), read through its [RSS feed](https://x.ai/changelog/bot/rss.xml)).
- Our profile records question cards as core Grok Bot UX ([profile](agentic-workspace-landscape/projects/grok-bot.md#product-and-ux)).

**Limit.** The screenshot does not name the app. That it is Grok Bot's iPhone app is [INFERENCE] from the `@bot` mention and the card pattern.

### 3.7 Post 6: Agent Bump (2026-10-19)

> we built “let’s bump phones to exchange contacts” but for agents!
>
> now your @instinct / @bot / @muse (whatever you use!) can make plans, negotiate deals, and get what it needs from your friends/coworkers’ assistants
>
> it's “have your ppl (agents) talk to my ppl (agents)!” for everyone 🤝
>
> built w/ @uncanny_guzus @ @ycombinator  #MakeSomethingAgents hackathon (s/o @nemild)
>
> on top of @stripe (agentic p2p payments) + @manufact (mcp relay server) 🙌
>
> Who will you bump first?

The author's self-reply: "oops it’s #MakeSomethingAgentsWant 😅" ([2112276007789240683](https://x.com/oscrhong/status/2112276007789240683)).

**Video: a phone screen recording, 19.6 s.** It shows a web app at `bump.up.railway.app` in a mobile browser.
1. **Bump.** "Bump phones to connect", with a pill naming the assistant ("Muse"). Then "Looking for the other phone", over an animated face.
2. **Match.** "You bumped", with a card reading "AGENTBUMP · 18 OCT / @guzus / Muse ↔ guzus's Muse".
3. **Purpose.** "What's this about?" chips: Hiring, Fundraising, Build together, Flirt and Something else…. Below them: "Your agent opens with: 'Hi, I'm Muse, working on behalf of oscar…'".
4. **Confirm.** "Same code on their screen?" with **Not them** and **Connect**.
5. **Agent chat.** A thread headed "Your Muse and @guzus's Muse". Each message carries "✓ Jev · safe"; delivery shows "Received by Muse", with the note "Muse may only check when active. Messages stay saved until received." Below, "You & your assistant" offers "Ask your assistant…" and "Add image: Private to your assistant first."

**Photos.**
- Three phone screens captioned "Muse", "Muse2Muse via BMA" and "Muse". The middle one relays a test Stripe payment link between the two agents.
- A slide reading "2nd Place · Agent Bump", with three people.

**Corroboration.** Y Combinator's event page exists, titled "Make Something Agents Want" ([event](https://events.ycombinator.com/MakeSomethingAgentsWant); only its metadata rendered). No project page, Devpost entry or repository was found.

**Limits.**
- The slide says "2nd Place", but in-app messages say "we won the first prize". This is unresolved; it may be a different prize.
- Stripe and Manufact are named in the post but not visible in the media.
- The "Jev · safe" label suggests each relayed message passes a Jev check [INFERENCE].

### 3.8 Post 7: Personal Agent Proxy's Quick actions (2026-10-20)

> While personal agents like @instinct, @bot or @Muse are getting really good at long-horizon tasks, there is also an entire class of problems where I need something simple done right now.
>
> We keep building new widgets for these. Long term, they could be generated on the fly with generative UI, like json-render from @ctatedev.
>
> Jev-based and inspired by @anishfn.
>
> Was fun hacking on this with @hkonsti_!

The post quotes @anishfn's "i built a text box that turns into whatever(some ui) you type. powered by jev". The author's self-reply is the link `https://personalagentproxy.com/` ([2112373453286449359](https://x.com/arnestrickmann/status/2112373453286449359)).

**Video: a Mac screen recording, 16.5 s, no audio.**
- **Home.**
  - A greeting and a field, "Quick actions: What did [a colleague] recommend for dinner in Lisbon?".
  - "9 sources", with a Plaid tooltip, and "4 agents".
  - A contribution-style heatmap of requests, and "32 requests in the past week: marked 1 email as unread, sent 1 email, viewed 3 emails · 16 blocked".
- **Command bar.** A centred bar with **Esc** changes its card on each keystroke:
  - "what did … recommend for di…" shows **Meeting memory** from Granola: quoted passages with speaker, time, **Transcript** and a "Takeaway" line.
  - "set up a meeting next tuesday …" shows **New event**: a title, a suggested time ("10:00 – 10:30 · suggested"), "No location", a calendar picker, "Me · organizer" and a day timeline. Once the query adds "4pm with [the colleague]", the time moves to 16:00–16:30, beside a "Focus time" block, and the colleague appears as a guest. A **Create event** button follows.
  - "how much did i spend on tr…" shows **Transactions**: "Spent the last 30 days", a total, merchant rows with category, card and date, and a comparison with "the 30 days before". The total changes as the query narrows to travel.

**Corroboration from primary sources** (MIT; repository created 2026-10-06):
- The [README](https://github.com/personalagentproxy/proxy): "From Home, quick actions can find people, email and files, work with calendars, write email, calculate, convert units and show balances or spending. Each agent gets its own login and access."
- The [Quick actions doc](https://github.com/personalagentproxy/proxy/blob/main/packages/docs/content/quick-actions.mdx):
  - "Actions that change something stay on the card for you to review: no email or invitation is sent, and no record is created or changed, until you choose its button."
  - "These are actions you take as the owner of the workspace, so an agent's access settings do not limit them."
  - "The current text in Quick actions goes to TypeSafe AI as you type so Jev can choose the card, then to OpenRouter so the card's fields can be filled in. The records read from connected services are not part of those requests."
- The [classifier](https://github.com/personalagentproxy/proxy/blob/main/packages/api/src/intent/classify.ts):
  - It pins `jev-1.13.0` to pick the widget, with `incomplete` and `none` as possible answers, and fills fields with `openai/gpt-oss-120b` over OpenRouter.
  - "While typing goes on, a newer text is asked about every 300 ms, so a slower answer is never shown."
- [Shapeshift](https://github.com/anishfn/shapeshift) (MIT), the inspiration:
  - "Jev decides, code computes."
  - "A card only changes when a challenger wins twice in a row (or is very sure)."
  - It falls back to an offline keyword classifier.
- [json-render](https://github.com/vercel-labs/json-render) is Apache-2.0, "The Generative UI framework".
- What we know about Jev itself comes from Shapeshift's README and press summaries; TypeSafe AI's own pages were not read.

**Limits.**
- Frames were sampled, so what happens between them is inferred.
- The hosted instance was not used.
- That this video shows Personal Agent Proxy rests on the self-reply link and on the match between the frames and the README's Quick actions list; the window shows no product name.

### 3.9 Corroboration and context

- **MacStories.** No article about 'Apple Bots' was found on macstories.net. The nearest primary context is Viticci's review [Open Minis Is the iOS Agent I Wish Siri AI Could Be](https://www.macstories.net/reviews/open-minis-is-the-ios-agent-i-wish-siri-ai-could-be/) (July 2026). It describes an iOS agent whose "Apple framework integrations … are powered by command-line interfaces (CLIs) that bridge native Apple APIs (EventKit, MusicKit, HomeKit, etc.)". A "built-in Linux terminal … sandboxed to the app's workspace" drives them. Asked to add a model or MCP server, the app "will bring up a native settings screen and ask for permissions", and it stores credentials on a "Keychain-based page". The "Ran cobots …" rows suggest 'Apple Bots' follows the same native-API-as-command pattern [INFERENCE].
- **Viticci's RemCTL** ([repo](https://github.com/viticci/remctl), MIT) is his Reminders CLI and MCP server. Its README matters for feasibility:
  - It covers "features Apple doesn't expose to other apps, such as sections, tags, subtasks, smart lists, and templates".
  - It reaches them through a "RemCTL Capability Host" that needs "Reminders, Automation for the Reminders app, and Full Disk Access".
  - "You grant access to that one app, and the terminal, scripts, and AI apps use it."
  - Its Claude Code pane: "**Undo** brings back the last task you completed, and only that one. Repeating tasks have no Undo because completing them advances the series." Refresh shows when it last read ("Updated").
  - It also serves its tools over Tailscale. That matches the "RemCTL … share that address" text in post 2.
- **Other accounts.** No 'Apple Bots' post appears among Viticci's 40 latest Mastodon statuses (back to 2026-08-22, [profile](https://mastodon.macstories.net/@viticci)). None appears among his 100 latest Bluesky posts (back to 2026-05-21, [profile](https://bsky.app/profile/viticci.macstories.net)).
- **Market signal.** Grok Bot 0.70.2 (2026-10-11): "Connectors that come with an app, such as Figma, Notion, and Canva, can show it as an interactive card in the chat" ([changelog](https://x.ai/changelog/bot#v0.70.2)).

---

## 4. Demonstrated, claimed or inferred ('Apple Bots')

"Shown" means a screen exists; stills never show that a control works. "Claimed" means an author claim we could not verify.

| Capability | Evidence | Status |
|---|---|---|
| Reminders read and rendered as cards | List and Today cards (posts 5 and 2) | Shown as a screen state |
| Reminder changed by the bot | "Changed · Due … → …" row with Undo | The change itself is the card's own claim; not verified |
| Completing reminders from the card | Checkbox circles and chevrons | Inferred from the affordances; never shown in use |
| Alarms and timers | Timer and alarm cards in a window (post 5) | Shown. Corrected 2026-10-21: the window is most likely the iPad build, so no Mac AlarmKit question arises ([full record §9](2026-10-21-viticci-full-record-sep-oct.md#9-corrections-to-earlier-documents)) |
| "Events" | — | Claimed; no event card seen |
| Reading the Music app's now playing | Bot text on an iPhone | Shown as text; consistent with iOS APIs (§6) |
| In-app playback | "Played by Cobot" card; mini-player bar | Shown; that audio played is not observable |
| Queue actions | Context menu | Shown |
| Shazam | Card after "Worked 2m 11s · 1 step" | Shown as a result; capture method unknown |
| Apple Health charts | Sleep and steps cards (iPhone) | Shown |
| Weather with alerts | Cards with Apple Weather attribution | Shown |
| HomeKit | One sentence of bot text | Claimed by the bot; no card |
| Photos, Maps | Cards | Shown |
| Voice in the background | Live Activity with Mute and End on the Home Screen; voice bars | Shown as a screen state; whether reasoning continues in the background is not shown |
| Background tasks | A system activity when the app is left; a turn resuming after a force-quit (video reply, 2026-10-17) | Partly shown (corrected 2026-10-21, [full record §5.2](2026-10-21-viticci-apple-bots-record.md#52-the-force-quit-video-observed)) |
| WebKit browser use | Inline page; "Done … Watch Steps" card | Shown |
| Mini web apps | Task garden, "Version 6 of 6", snapshot footer | Shown |
| Native subagents | "Helpers" card; Helpers settings | Shown |
| Memory and session recall | "Recalled 1" and "Recalled 3" chips | Shown as chips |
| Code mode | "Ran a script · Code Mode · 2 calls" | Shown |
| MCP | "MCP Servers 3" in Settings | Settings row shown; "latest MCP spec" claimed |
| Any model | GPT-6.1 Sol and Claude Opus 5.5 chips; "Providers & Models 8" | Shown |
| Apple Intelligence as a utility | — | Claimed |
| Global quick entry | Floating panel | Shown |
| Agent split views | Two bots side by side on a Mac | Shown on Mac; iPad claimed |
| Menu bar | — | Claimed |
| 20+ Apple frameworks | Visible: Reminders, Music, Shazam, Health, Weather, Photos, Maps, alarms, WebKit; HomeKit as text | Count claimed; at least nine visible |
| Per-bot execution location | "On Federico's Mac Studio" in Builder's header | Shown |
| Permission posture | "Bypass" on every bot from 2026-10-17; skill install still asked | Shown; what Bypass skips is unknown |

---

## 5. Design grammar

Each pattern below gives the evidence, then what Memoshi could take from it.

1. **A card is a typed view of a real object, with its source on top.**
   - Evidence: headers name the kind and source ("REMINDERS", "PHOTOS", "MAPS", "TIMER · CHEF", "Apple Health · October 2–8", "Weather · Legal · Updated 1:22 AM").
   - Evidence: actions are the object's own verbs, not chat replies: Resume/Cancel, Play/Play Next/Add to Queue, Open in Maps/Directions, Open in Weather, Play Here/Apple Music.
   - Take: object cards are native SwiftUI views, which [D29](../plan/decisions.md#d29) already requires of chrome. Web views stay for content.
2. **Name the actor.**
   - Evidence: "Played by Cobot", "Now Playing · Researcher", "Done by Cobot · 2 steps · 20s", "ALARM · CHEF".
   - Take: every effect on a system object says which bot (or the user) caused it. This extends Memoshi's origin header ([02 §7.1](../plan/02-experience.md#71-anatomy-lifecycle-and-placement)).
3. **Show changes as before → after, with a narrow Undo.**
   - Evidence: the "Changed · Due ~~Tue~~ → Wed" row and Undo; RemCTL's single-step Undo, with no Undo for repeating tasks.
   - Take: the receipt records before and after values. Undo is a new, audited user action, not an edit to the receipt.
4. **Separate live from snapshot, and say which.**
   - Evidence: the mini app's footer ("Reminders snapshot · … No reminders are changed here"); the weather card's "Updated 1:22 AM" and refresh; RemCTL's "Updated" time and re-read after each write.
   - Take: a live object view shows its freshness. A snapshot says it is one, and routes changes through the bot.
5. **Show work on demand.**
   - Evidence: "Worked 13s · 3 steps ›" chips; an Activity pane with a kind (Web Search, Shell, Read, Write, Code Mode, Thought) and a duration for every step.
   - Take: this already matches Memoshi's `ToolGroup` and inspector ([02](../plan/02-experience.md)); no new concept.
6. **Ask at capability boundaries.**
   - Evidence: the skill-install card lists scope ("For: Every bot") and files with "+" markers, even under Bypass. Voice Mode explains its separate key and per-minute cost.
   - Take: Memoshi's `bot_proposal` (`skill_change`) and `grant_request` already cover this. Memoshi has no Bypass mode ([D27](../plan/decisions.md#d27)).
7. **Hand off to the system app.**
   - Evidence: Open in Weather, Open in Maps, View in Apple Music and Directions; a voice session that continues as a Live Activity while the app is in the background.
   - Take: object cards end with an "Open in <system app>" action. Phone sessions surface as Live Activities (§6).
8. **Assistant and workspace.**
   - Evidence: Cobot, pinned ⌘1, is the personal-objects assistant. Builder, "On Federico's Mac Studio", does infrastructure work. "Projects" are task boards. Grok Bot's "Assistant" proposes work through a question card.
   - Take: this matches Memoshi's Assistant-led home ([D2](../plan/decisions.md#d2)), with bots on their own computers.
   - Difference: 'Apple Bots' puts two composers side by side in one window, while Memoshi's rule 2 is "no second composer" ([02 §1](../plan/02-experience.md#1-scope-and-principles)). Memoshi's equivalent is multiple windows (Phase 2).
   - The pinned faces, roster, "Waiting for You" and Activity resemble the Grok Bot layout recorded in our [measured docs](prior/grok-bot-measured/behavior.md) [INFERENCE].
9. **Instant typed widgets for "right now" jobs.**
   - Evidence: Personal Agent Proxy's card changes on each keystroke, chosen by a classifier with deterministic fill-in. Writes wait for the card's button. Shapeshift's two-wins rule prevents flicker.
   - Take: QuickAsk can become typed cards (§7.6).
10. **Owner actions are not agent actions.**
    - Evidence: Personal Agent Proxy runs quick actions as the owner, outside agents' access settings, and logs agent requests "allowed or denied" ([site](https://personalagentproxy.com/)).
    - Take: an edit the user makes in a live view is the user's action (§7.1).
11. **Cross-user agent introductions need a human check.**
    - Evidence: Agent Bump confirms with "Same code on their screen?", picks a purpose first, and labels each relayed message with a safety check and a receipt.
    - Take: relevant only to v2 team bots; noted, not proposed.

---

## 6. Platform feasibility

### 6.1 Matrix

Memoshi's Mac configuration: a native SwiftUI/AppKit app on macOS 27, Developer ID–signed, without the App Sandbox ([09 P2, P6](../plan/09-platform-macos.md)). The iPhone app would ship through the App Store. Which capabilities a Developer ID profile can carry comes from Apple's [macOS capability table](https://developer.apple.com/help/account/reference/supported-capabilities-macos/).

| Capability | Mac | iPhone and iPad | API, permission and limits | What Memoshi can honestly promise |
|---|---|---|---|---|
| Reminders | Yes, macOS 14+ | Yes, iOS 17+ | [`requestFullAccessToReminders`](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoreminders(completion:)). "Your app can't request read-only access to either events or reminders" ([event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)). `NSRemindersFullAccessUsageDescription`. [`EKReminder`](https://developer.apple.com/documentation/eventkit/ekreminder) exposes due date components, completion and priority; recurrence "only supports a single recurrence rule" ([doc](https://developer.apple.com/documentation/eventkit/ekcalendaritem/recurrencerules)). Live updates through [`EKEventStoreChanged`](https://developer.apple.com/documentation/eventkit/ekeventstorechangednotification). | Lists, items, due dates, priority, completion and a single recurrence rule through public EventKit. Not sections, tags, subtasks, smart lists or templates: RemCTL needs Automation and Full Disk Access for those, which [09 §5.9](../plan/09-platform-macos.md) avoids |
| Calendar | Yes | Yes | Write-only access "lets your app create new events but doesn't let it read any events … including events your app created". [EventKit UI](https://developer.apple.com/documentation/eventkitui) is iOS, iPadOS, Mac Catalyst and visionOS only; on iOS 17+ its editor runs "outside of your app's process" and needs no calendar access. | Mac: our own event editor; create with write-only access, and read only with full access (T3 in 09 §5.9) |
| Music library and catalog | Yes ([`MusicLibraryRequest`](https://developer.apple.com/documentation/musickit/musiclibraryrequest), macOS 14+) | Yes, iOS 16+ | [MusicKit](https://developer.apple.com/documentation/musickit): without `NSAppleMusicUsageDescription` "the system terminates your app". The MusicKit App Service is "a runtime service that automatically associates with your app's bundle identifier" ([token generation](https://developer.apple.com/documentation/musickit/using-automatic-token-generation-for-apple-music-api)). Catalog playback needs [`canPlayCatalogContent`](https://developer.apple.com/documentation/musickit/musicsubscription/canplaycatalogcontent). | Library and catalog cards. Playing catalog tracks needs the user's Apple Music subscription. Developer ID plus the App Service: verify in a spike [INFERENCE] |
| Play music in the app | Yes ([`ApplicationMusicPlayer`](https://developer.apple.com/documentation/musickit/applicationmusicplayer), macOS 14+) | Yes | It "doesn't affect the Music app's state". On iOS it keeps playing in the background only with a background audio mode. | A "Played by <bot>" player in Memoshi |
| Read or control the Music app's player | **No** API | Yes: [`SystemMusicPlayer`](https://developer.apple.com/documentation/musickit/systemmusicplayer); [`systemMusicPlayer`](https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller/systemmusicplayer) shares the "Now-playing item" | Both are iOS, iPadOS, Mac Catalyst, tvOS and visionOS only. On a Mac the only route is Apple Events to Music.app ([`NSAppleEventsUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription); the [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events) under hardened runtime). | iPhone: yes, while the app runs. Mac: only after a decision to accept Automation |
| Identify a song | Yes, by microphone ([`SHManagedSession`](https://developer.apple.com/documentation/shazamkit/shmanagedsession), macOS 14+) | Yes, iOS 17+ | The session "performs all recording of audio", so it needs microphone permission [INFERENCE]. The app must have [ShazamKit enabled for its App ID](https://developer.apple.com/help/account/services/shazamkit/). [`SHLibrary`](https://developer.apple.com/documentation/shazamkit/shlibrary) is the user's synced Shazam library. Capturing what this Mac plays needs a Core Audio tap ([`AudioHardwareCreateProcessTap`](https://developer.apple.com/documentation/coreaudio/audiohardwarecreateprocesstap(_:_:)), macOS 14.2+) and [`NSAudioCaptureUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription). | "Listen and identify" by microphone. Identifying this Mac's own audio needs a plan decision: D41 names ScreenCaptureKit and Accessibility, not taps |
| Alarms and timers | **No** | Yes, iOS 26+ | [AlarmKit](https://developer.apple.com/documentation/alarmkit) is iOS, iPadOS and Mac Catalyst 26. Alarms override Focus and silent mode. "If the `NSAlarmKitUsageDescription` key is missing … apps can't schedule alarms". Countdowns appear as Live Activities. | iPhone only. The Mac uses notifications, including time-sensitive ones (available to Developer ID) |
| Weather | Framework only (macOS 13+); the WeatherKit **capability is not offered for Developer ID** profiles | Yes, iOS 16+ | [Attribution is required](https://developer.apple.com/documentation/weatherkit/weatherservice/attribution): "a legal attribution page and Apple Weather mark". WeatherKit provides "up to 500,000 API calls a month per Apple Developer Program membership" ([service help](https://developer.apple.com/help/account/services/weatherkit/)). The [REST API](https://developer.apple.com/documentation/weatherkitrestapi) serves other platforms. | Mac: through the REST API from the daemon, with attribution, after a spike [INFERENCE]. iPhone: native |
| Health | **No data**: "your app can't read or write HealthKit data. Calls to isHealthDataAvailable() return false" ([doc](https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable())) | Yes (iPhone; iPad on iPadOS 17+) | Per-type read and write consent | iPhone only |
| Home | **No**: [HomeKit](https://developer.apple.com/documentation/homekit) is iOS, iPadOS, Mac Catalyst, tvOS, visionOS and watchOS; the macOS capability table offers HomeKit to Apple Developer Program profiles, not to Developer ID | Yes | — | iPhone only |
| Photos, Maps, Contacts, location | Yes ([`PHPhotoLibrary`](https://developer.apple.com/documentation/photos/phphotolibrary), MapKit, `CNContactStore`, `CLLocationManager`) | Yes | Separate consent for each | Both |
| App Intents and Shortcuts | Yes, macOS 13+ | Yes, iOS 16+ | [App Intents](https://developer.apple.com/documentation/appintents) exposes *our* actions to Siri, Spotlight, Shortcuts and widgets. [`SnippetIntent`](https://developer.apple.com/documentation/appintents/snippetintent) (26) gives interactive snippets whose buttons run App Intents. Running a user's shortcut: `shortcuts run` on the Mac ([guide](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)); `shortcuts://run-shortcut?name=…` on iOS ([guide](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios)). No documented API calls another app's intents directly [INFERENCE]. | Memoshi's actions everywhere (AP-05); running a user's named shortcut as a visible handoff; never arbitrary control of other apps |
| Widgets | Yes | Yes | Buttons and toggles run App Intents. "On a locked device, buttons and toggles are inactive" ([interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)). "For a widget the user frequently views, a daily budget typically includes from 40 to 70 refreshes" ([budget](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)). | Glanceable state; approvals only open the app (D41, AP-07) |
| Live Activities | Shown in the menu bar of a paired Mac; a Mac app can't start one (`Activity` is iOS and iPadOS only) | Yes, iOS 16.1+ | A Live Activity "can be active for up to eight hours", then stays on the Lock Screen up to four more, "a maximum of 12 hours". Data "can't exceed a combined size of 4 KB". A Live Activity "can't access the network". Updates come from the app or through ActivityKit push ([guide](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [ActivityKit](https://developer.apple.com/documentation/activitykit)). | iPhone task progress. Push updates carry the displayed data, which conflicts with [R11-04](../plan/feature-catalog.md)'s content-free pushes unless they show only states and counts |
| Notifications | Yes; content extensions on macOS 11+ ([doc](https://developer.apple.com/documentation/usernotificationsui/unnotificationcontentextension)) | Yes | Actionable notifications; time-sensitive available to Developer ID (capability table) | Both (AP-02) |
| Background work | memoshid runs as a LaunchAgent ([D12](../plan/decisions.md#d12)) | Limited: [`BGContinuedProcessingTask`](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask) (26) runs "only in response to someone's action", shows progress in a Live Activity, can be cancelled and "can terminate … abruptly" ([guide](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)) | Background pushes: "don't try to send more than two or three per hour" ([guide](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)). Audio continues only with a background audio mode ([guide](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback)) | Bots run on the Mac or the runner. The phone is a client and an attended provider |
| Driving other apps' UI | Excluded in v1 and v1.1 (D41: no Accessibility or ScreenCaptureKit); Apple Events need per-app consent | No public API [INFERENCE: none documented; UIKit accessibility describes the app's own views] | — | Never on iOS. On the Mac only through a future decision |
| Generated mini apps | Web content in a sandboxed view (D29) | [App Review](https://developer.apple.com/app-store/review/guidelines/) 4.7 allows HTML5 and JavaScript mini apps. 4.7.2: "Your app may not extend or expose native platform APIs or technologies to the software without prior permission from Apple." 4.7.3: no sharing of "data or privacy permissions … without explicit user consent in each instance." 2.5.2 bars code that "introduces or changes features". | — | Snapshot data passed with consent; changes go through tool calls under policy |
| On-device model | macOS 26+ ([`SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)) | iOS 26+ | Requires an Apple Intelligence device and region. [`@Generable`](https://developer.apple.com/documentation/foundationmodels/generable) constrains output to a Swift type. | Local intent and card classification (D41's "small on-device jobs") |
| Handoff between devices | Yes ([`NSUserActivity`](https://developer.apple.com/documentation/foundation/nsuseractivity)) | Yes | — | Continue a conversation from Mac to iPhone (Phase 5) |

### 6.2 Custom native cards versus system-owned surfaces

These two families are different things and should never be promised as one.

| | Custom native cards (Memoshi's own SwiftUI) | System-owned surfaces (widgets, Live Activities, App Intent snippets, notifications) |
|---|---|---|
| Who renders | Memoshi's process, in Memoshi's windows | The system, in a separate process, from archived views or snapshots ([widget interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)) |
| Liveness | Bound to live state; re-read on change notifications | Timeline or push updates with budgets; Live Activities ≤ 4 KB and ≤ 8 h active |
| Interactivity | Anything: editors, scrubbers, menus, drag | Buttons and toggles that run App Intents; inactive while the device is locked |
| Who decides | The app or memoshid, under policy | Widgets never decide; notifications decide only attended T1–T2 approvals ([09 P10](../plan/09-platform-macos.md)); everything else opens the app (D41) |
| Platforms | Wherever Memoshi runs | Live Activities start only from iPhone or iPad; the Mac shows them mirrored |

### 6.3 What not to promise

- Control of, or reading from, arbitrary third-party apps on iOS.
- Reminders sections, tags, subtasks, smart lists or templates through public APIs.
- Native alarms, Health data, HomeKit or Music app control on the Mac.
- Native WeatherKit in a Developer ID Mac build.
- Unattended or background agent runs on the iPhone.
- Widgets, Live Activities or notifications as approval surfaces beyond what the plan allows.
- Identifying what the Mac itself is playing without a new permission decision.

---

## 7. Recommendation for Memoshi (input to the next-version spec)

### 7.1 Two objects, not one

- **Card, unchanged.** A bot's proposal to change a system object is a T4 `draft` Card, as [09 §5.9](../plan/09-platform-macos.md) already specifies for EventKit writes. It resolves once ([02 §7.1](../plan/02-experience.md#71-anatomy-lifecycle-and-placement)). Its receipt (the existing `CardReceipt` component) freezes:
  - the object reference;
  - the before and after values;
  - who decided, and when;
  - the result the framework returned.
- **Live object view, new.** A native SwiftUI view bound to an object reference, such as a reminder's identifier or a MusicKit item ID.
  - Memoshi.app renders it and re-reads on change notifications or player-state changes.
  - It shows the source ("Reminders · iCloud"), freshness ("Updated 9:41") and the actor of the latest change ("Completed by you · 9:43", "Moved by Scout, approved 9:40").
  - A receipt links to it ("Open live"); the view never edits a receipt.
  - When the object has changed since a receipt, the view shows the current state and a "Changed since" line.
  - Calling it something other than a Card keeps the one-shot contract intact [INFERENCE].
- **Edits in a live view are the user's own actions.** The app applies them, writes them to the audit log and posts a system line in the conversation, as Personal Agent Proxy treats owner actions. They are not bot tool calls, so they need no approval. The bot learns of them only through that line [INFERENCE].
- **Rendering is not reading.** The view can show the user live state without putting it in the model's context. The bot sees only what its granted tools return (T3 reads, 09 §5.9).
- **Undo** is a new user action with its own audit entry, limited to the last change. Repeating items follow RemCTL's rule that completing them advances the series (verify against EventKit) [INFERENCE].
- **Styling.** Live object views are a Memoshi-only surface. Under D43, Memoshi-only surfaces "use the same visual language" as the Kuvo parity spec. The 'Apple Bots' look is not a target, and nothing from it is copied.

### 7.2 Object types, in order of feasibility on the Mac

1. **Reminders and Calendar (EventKit).** These can ride [AP-08](../plan/feature-catalog.md), currently Phase 3, P2.
2. **Music.** Library and catalog search, in-app playback and a "Played by <bot>" mini-player. A new row.
3. **Song identification.** A microphone ShazamKit card. A new row.
4. **Photos and Maps** attachments.
5. **Weather** through the REST API, after a spike.

Phone-only types (Health, Home, alarms and timers, control of the Music app) come through the iPhone client (§7.5). Phase placement is the plan owner's call.

### 7.3 Memoshi.app as the capability host

- **The app holds the permissions.** Host capabilities run in Memoshi.app as daemon-to-app requests ([04 §8](../plan/04-architecture.md#8-host-capability-interfaces)), and 09 §5.9 already makes EventKit "native host capabilities in the app". Music and ShazamKit would join as new host services, so memoshid never needs these permissions [INFERENCE]. RemCTL uses the same shape: "You grant access to that one app, and the terminal, scripts, and AI apps use it."
- **Per-bot grants are the only per-bot boundary.** macOS grants a permission to the whole app, so Memoshi's own grants must do the per-bot work. Personal-object grants (Reminders, Calendar, Music) could start on the Assistant, with other bots asking through `grant_request` [INFERENCE].
- **Typed tools, not shell commands.** Open Minis and 'Apple Bots' expose native APIs as shell commands ("Ran cobots music library search"). For Memoshi, the primary surface should be typed tools that pass `beforeTool` per call. A command shim inside the sandbox could serve Code Mode, but only if every call reaches the same policy [INFERENCE].

### 7.4 Music and Shazam on the Mac

- **In-app playback only.** Reading or controlling Music.app requires Apple Events and Automation consent, which the plan avoids ([09 §5.9](../plan/09-platform-macos.md)). Adding it needs a decision.
- **Identify by microphone only.** Identifying what the Mac itself plays needs a Core Audio tap and a system-audio permission, which also needs a decision.

### 7.5 iPhone (Phase 5 unless re-planned)

- **Keep R11-01's remote client, and add an attended device provider.** While the iPhone app is open, or after the user starts a `BGContinuedProcessingTask`, the phone may run typed tool calls for phone-only frameworks on behalf of a Mac-hosted bot. The phone shows its own OS permission prompts, and results return over the relay. Never promise unattended execution on the phone.
- **Live Activities.** They can show a running task for up to 8 hours active and 12 hours on screen. Updates pushed through APNs carry the displayed data, so under R11-04 pushed updates could carry only states and counts. Updates from the running app are not affected.
- **Inline widgets fall under App Review 4.7.**
  - Don't bridge native APIs into generated web content (4.7.2).
  - Share data with each mini app only with consent (4.7.3).
  - 'Apple Bots'' snapshot-only task garden is the compliant shape [INFERENCE].

### 7.6 Quick entry

QuickAsk ([02 §11.4](../plan/02-experience.md)) could turn into typed cards as the user types:
- on-device Foundation Models with a `@Generable` enum picks the card type;
- [`NSDataDetector`](https://developer.apple.com/documentation/foundation/nsdatadetector) and deterministic parsers fill in dates and amounts;
- Shapeshift's two-wins rule keeps the card from flickering;
- writes wait for the card's button.

Unlike Personal Agent Proxy, which sends keystrokes to TypeSafe AI and OpenRouter, this keeps them on the Mac ([D28](../plan/decisions.md#d28)). How the classification quality compares with Jev is untested [INFERENCE].

### 7.7 Spikes before any commitment

1. MusicKit and ShazamKit App Services in a Developer ID, unsandboxed app on macOS 27.
2. The WeatherKit REST API from memoshid, with the attribution UI and the call quota.
3. EventKit change-notification latency, and identifier stability across iCloud sync.
4. `ApplicationMusicPlayer` behaviour while Music.app is also playing.
5. `SHManagedSession` matching through the Mac's microphone while the Mac plays the song.
6. Live Activities from the iPhone app showing in the Mac menu bar.
7. An App Review read of inline widgets on the iPhone against 4.7.2 and 4.7.3.

### 7.8 In-house starting points

Apollo (MIT, our own) already has most of these integrations in source. Its file paths are listed in the [in-house audit](agentic-workspace-landscape/landscape/in-house-assets.md#apple-integrations):
- iOS EventKit and Contacts context providers;
- Mac Calendar through an XPC helper;
- App Intents and entity donations;
- widgets, and Live Activities with ActivityKit and AlarmKit, plus a server-side Live Activity push sender;
- a capability registry that sets risk, approval and location per operation and is generated into Swift;
- approvals bound to an immutable action hash, which fits the receipt in §7.1.

Two cautions:
- That audit read code, and in its own words "Source support is not device acceptance". Treat every path as unproven until it runs on a device.
- Apollo reads Reminders on the Mac through `osascript` and Contacts through `sqlite3`, which [09 §5.9](../plan/09-platform-macos.md) rejects in favour of native calls. Do not port those two paths.

---

## 8. Licensing and reuse

| Source | Licence | Use for Memoshi |
|---|---|---|
| 'Apple Bots' (Viticci) | Unpublished; no licence | Ideas only. No screenshot, string or asset copied |
| Open Minis | Proprietary app; licence unknown | Ideas only |
| [RemCTL](https://github.com/viticci/remctl) | MIT | Reference for Undo and refresh semantics and the capability-host idea. Its advanced Reminders features depend on Automation and Full Disk Access, which 09 avoids |
| [PiDurableKit](https://github.com/finnvoor/PiDurableKit) | CC0-1.0 | Reference, if an on-device Pi runtime is ever needed; the plan keeps Pi in memoshid |
| [Personal Agent Proxy](https://github.com/personalagentproxy/proxy) | MIT | Reference for quick actions, owner versus agent actions, and the allowed/denied log |
| [Shapeshift](https://github.com/anishfn/shapeshift) | MIT | Reference for the calm-UI state machine |
| [json-render](https://github.com/vercel-labs/json-render) | Apache-2.0 | Reference |
| Agent Bump | No public repository found | Ideas only |
| Grok Bot | Proprietary | Ideas only ([D33](../plan/decisions.md#d33)) |
| [Apollo](agentic-workspace-landscape/landscape/in-house-assets.md#apple-integrations) | MIT (our own) | Reference and port selectively ([MASTER_PLAN §13](../plan/MASTER_PLAN.md#13-what-we-reuse)), except the `osascript` and `sqlite3` paths |
| Apple frameworks | Public APIs under the developer agreement | MusicKit, ShazamKit and WeatherKit need App ID services; WeatherKit needs attribution |

No visual asset from any post was copied into this repository. The Kuvo parity work ([D43](../plan/decisions.md#d43), P0-19) is untouched.

---

## 9. Open questions

1. Will 'Apple Bots' ship, or be open-sourced? **Updated 2026-10-21:** he plans an App Store release ("we plan to release on the App Store in the near future", Club MacStories, 9 Oct), and said of open source "I'll try as soon as my Opus limits reset" (8 Oct). Neither has a date ([full record §3](2026-10-21-viticci-apple-bots-record.md#3-timeline)).
2. Is its Mac build native, Mac Catalyst or the iPad app? This matters for how it schedules AlarmKit alarms "on a Mac". Unknown.
3. Did Agent Bump take first or second place? The slide and the in-app messages disagree.
4. Do MusicKit and ShazamKit App Services work for Developer ID Mac apps? Spike 1.
5. Should Memoshi accept Apple Events, for Music.app's now playing or RemCTL-style Reminders features? The plan currently avoids Automation.
6. Does D41's exclusion of ScreenCaptureKit extend in spirit to Core Audio taps?
7. Does R11-04's content-free push rule also apply to Live Activity pushes? That decides what an iPhone Live Activity can show.

---

## Sources

**The seven posts** (all retrieved 2026-10-20):
- https://x.com/viticci/status/2108192119152140318
- https://x.com/viticci/status/2112555465313853810
- https://x.com/viticci/status/2111418614343504107
- https://x.com/viticci/status/2110282174440017929
- https://x.com/viticci/status/2108623467965038946
- https://x.com/oscrhong/status/2112267545638207767
- https://x.com/arnestrickmann/status/2112341539154542928

**Self-replies:**
- https://x.com/viticci/status/2108635610160525412
- https://x.com/oscrhong/status/2112276007789240683
- https://x.com/arnestrickmann/status/2112373453286449359

**Retrieval endpoints:**
- `https://cdn.syndication.twimg.com/tweet-result?id=<id>`
- `https://publish.x.com/oembed?url=<post>`
- `https://api.fxtwitter.com/<user>/status/<id>` (third-party)

**Corroboration:**
- MacStories, [Open Minis review](https://www.macstories.net/reviews/open-minis-is-the-ios-agent-i-wish-siri-ai-could-be/)
- [RemCTL](https://github.com/viticci/remctl), and the [viticci GitHub account](https://github.com/viticci)
- [Mastodon](https://mastodon.macstories.net/@viticci); [Bluesky](https://bsky.app/profile/viticci.macstories.net)
- xAI, [tag @bot on X](https://docs.x.ai/grok-bot/tag-on-x); [Grok Bot changelog](https://x.ai/changelog/bot) through its [RSS feed](https://x.ai/changelog/bot/rss.xml) (0.66.0, 0.70.2)
- [Personal Agent Proxy](https://personalagentproxy.com/); its [repository](https://github.com/personalagentproxy/proxy), [Quick actions doc](https://github.com/personalagentproxy/proxy/blob/main/packages/docs/content/quick-actions.mdx) and [`classify.ts`](https://github.com/personalagentproxy/proxy/blob/main/packages/api/src/intent/classify.ts)
- [Shapeshift](https://github.com/anishfn/shapeshift); [json-render](https://github.com/vercel-labs/json-render); [PiDurableKit](https://github.com/finnvoor/PiDurableKit)
- Y Combinator, [Make Something Agents Want](https://events.ycombinator.com/MakeSomethingAgentsWant)

**Apple documentation** (availability read from Apple's documentation JSON on 2026-10-20):
- **EventKit:** [accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [`requestFullAccessToReminders`](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoreminders(completion:)), [`requestFullAccessToEvents`](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)), [`requestWriteOnlyAccessToEvents`](https://developer.apple.com/documentation/eventkit/ekeventstore/requestwriteonlyaccesstoevents(completion:)), [`EKEventStoreChanged`](https://developer.apple.com/documentation/eventkit/ekeventstorechangednotification), [EventKit UI](https://developer.apple.com/documentation/eventkitui)
- **Music:** [MusicKit](https://developer.apple.com/documentation/musickit), [`ApplicationMusicPlayer`](https://developer.apple.com/documentation/musickit/applicationmusicplayer), [`SystemMusicPlayer`](https://developer.apple.com/documentation/musickit/systemmusicplayer), [`MusicLibraryRequest`](https://developer.apple.com/documentation/musickit/musiclibraryrequest), [`canPlayCatalogContent`](https://developer.apple.com/documentation/musickit/musicsubscription/canplaycatalogcontent), [automatic token generation](https://developer.apple.com/documentation/musickit/using-automatic-token-generation-for-apple-music-api), [MusicKit service](https://developer.apple.com/help/account/services/musickit/), [`systemMusicPlayer`](https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller/systemmusicplayer), [`nowPlayingItem`](https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller/nowplayingitem)
- **ShazamKit and audio:** [ShazamKit](https://developer.apple.com/documentation/shazamkit), [`SHManagedSession`](https://developer.apple.com/documentation/shazamkit/shmanagedsession), [`SHLibrary`](https://developer.apple.com/documentation/shazamkit/shlibrary), [ShazamKit service](https://developer.apple.com/help/account/services/shazamkit/), [Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps), [`AudioHardwareCreateProcessTap`](https://developer.apple.com/documentation/coreaudio/audiohardwarecreateprocesstap(_:_:)), [`NSAudioCaptureUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription)
- **AlarmKit:** [AlarmKit](https://developer.apple.com/documentation/alarmkit), [scheduling an alarm](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)
- **Weather:** [WeatherKit](https://developer.apple.com/documentation/weatherkit), [attribution](https://developer.apple.com/documentation/weatherkit/weatherservice/attribution), [REST API](https://developer.apple.com/documentation/weatherkitrestapi), [WeatherKit service](https://developer.apple.com/help/account/services/weatherkit/), [macOS capability table](https://developer.apple.com/help/account/reference/supported-capabilities-macos/)
- **Health, Home, Photos:** [`isHealthDataAvailable()`](https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable()), [HomeKit](https://developer.apple.com/documentation/homekit), [`PHPhotoLibrary`](https://developer.apple.com/documentation/photos/phphotolibrary)
- **App Intents and Shortcuts:** [App Intents](https://developer.apple.com/documentation/appintents), [`SnippetIntent`](https://developer.apple.com/documentation/appintents/snippetintent), [snippets](https://developer.apple.com/documentation/appintents/displaying-static-and-interactive-snippets), [Shortcuts on the command line](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac), [Shortcuts URL scheme](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios)
- **Widgets, Live Activities, notifications:** [WidgetKit](https://developer.apple.com/documentation/widgetkit), [interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [reload budget](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), [ActivityKit](https://developer.apple.com/documentation/activitykit), [Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [`UNNotificationContentExtension`](https://developer.apple.com/documentation/usernotificationsui/unnotificationcontentextension), [background pushes](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)
- **Background work:** [`BGContinuedProcessingTask`](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask), [long-running tasks](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados), [`BGTaskScheduler`](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler), [media playback configuration](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback)
- **Apple Events:** [`NSAppleEventsUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription), [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)
- **Models and Foundation:** [`SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [`Generable`](https://developer.apple.com/documentation/foundationmodels/generable), [`NSDataDetector`](https://developer.apple.com/documentation/foundation/nsdatadetector), [`NSUserActivity`](https://developer.apple.com/documentation/foundation/nsuseractivity)
- **App Review Guidelines**, last updated 2026-10-16, §§2.5.2 and 4.7: https://developer.apple.com/app-store/review/guidelines/

**Memoshi plan and research:** [decisions](../plan/decisions.md), [02-experience](../plan/02-experience.md), [04-architecture](../plan/04-architecture.md), [09-platform-macos](../plan/09-platform-macos.md), [feature catalog](../plan/feature-catalog.md), [in-house assets](agentic-workspace-landscape/landscape/in-house-assets.md#apple-integrations), [Grok Bot profile](agentic-workspace-landscape/projects/grok-bot.md), [measured Grok Bot behaviour](prior/grok-bot-measured/behavior.md).
