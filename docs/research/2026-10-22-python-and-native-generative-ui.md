# Python and native generative UI: Armin Ronacher's iOS Python IDE, Ronith's Swift interpreter and Interswift

**Status:** Research · 2026-10-22
**Owns:** A detailed record of two posts the user asked about (every post, photo, video and gathered reply) and of the open-source Interswift repository. Also: Apple's current App Review rules for running generated code, how our apps could run Python (numpy, matplotlib, quant research, notebooks), and how they could draw generated UI natively.
**Depends on:** [Viticci follow-ups §4.5, §5.5](2026-10-22-viticci-followups.md) (first pass) · [decisions](../plan/decisions.md): D29 (web views for content), D32 (Mac distribution), D38 (iPhone), D44 (engine) · [feature catalog](../plan/feature-catalog.md) CH-09 (card framework) and CH-17 (inline widgets)
**Mirrored in:** `~/Documents/memoshi/Pi_Swift/docs/research/`. Edit this copy first, then copy it across.

Research is evidence, not decisions ([index](README.md)). Labels: **Observed** (seen in a post, frame, file or document), **Claim** (an author's statement not verified), **[INFERENCE]** (our reasoning). Third-party media and raw captures are in `~/Documents/memoshi/evidence/2026-10-22-pi-mobile/`.

## 1. Summary

1. **Armin Ronacher's app is "Pyslopnista"**, a native-looking iOS Python IDE (Observed, §2):
   - Pyodide Python that installs numpy, matplotlib and pillow, and draws matplotlib figures in its console;
   - a debugger with a variable inspector and a REPL;
   - a formatter and a problems view;
   - a reactive Python `ui` module that brings up native-looking screens;
   - a Pi Durable coding agent;
   - an Accounts screen with Pi's whole sign-in set, subscriptions included.

   How Pyodide and the agent are hosted inside the app is not shown. No release is announced.
2. **Ronith's Swift interpreter is a closed prototype** (Observed, §3). In his words, it compiles "swift source to bytecode, rest is interpreted", with frameworks "bundled into the app at build time". He says it is "for simpler apps", and that an unsupported API makes "the app exit". It will not be open-sourced "for the time being". His company, Interface Club, was acquired on 21 Oct, and the product the interpreter was meant for shuts down on 15 Nov. Most of the reply thread is about App Review, not technique.
3. **Interswift, linked by Jason Kneen in that thread, is a one-commit MIT imitation** (Observed, §4). It interprets a very small SwiftUI subset: text, stacks, spacer, divider, and buttons that change integer state. Its rich Weather and Workout demos are precompiled native views that a document calls by name: "it does not demonstrate general interpretation". What it does show is the workable architecture: parse Swift with SwiftSyntax, compile to a view-building bytecode, build a view tree, and draw it with real SwiftUI using host-linked components.
4. **App Review (guidelines dated 16 Oct 2026) is the real constraint on iPhone** (Observed, §5):
   - **2.5.2** forbids executing code that "introduces or changes features or functionality of the app". The exception covers educational and developer-tool apps whose code is "completely viewable and editable by the user".
   - **4.7** allows "HTML5 and JavaScript mini apps" with extra rules. One of them: no exposing native platform APIs without Apple's permission.
   - **Enforcement:** Apple enforced 2.5.2 against AI app-builder apps in March 2026 (press).
   - **The Mac app** is distributed directly ([D32](../plan/decisions.md#d32)), so none of this applies there.
5. **Python on iPhone is practical** (Observed facts, §6).
   - **Pyodide 314** brings Python 3.14, NumPy 2.4, pandas 3, SciPy 1.18, Matplotlib 3.10 and statsmodels into a web view.
   - **Native CPython** has official iOS builds since 3.15. NumPy, pandas and Matplotlib publish no iOS wheels on PyPI yet.
   - **Carnets**, an open-source Jupyter app on the App Store, already ships notebooks with numpy, pandas and matplotlib.
   - **Heavy quant work belongs on the Mac:** long backtests, parameter sweeps and numba-based libraries such as vectorbt [INFERENCE].
6. **The state of the art in generative UI is a catalog of trusted native components plus a declarative spec that the model writes** (Observed, §7): Google's A2UI and Vercel's json-render, both with community SwiftUI renderers.
   - **Swift files** can be a way of writing that spec: Interswift's approach, extended.
   - **A full Swift interpreter** is closed, costly to build, and the riskiest route under 2.5.2 on iPhone [INFERENCE].

## 2. Armin Ronacher's iOS Python IDE ("Pyslopnista")

### 2.1 Posts (Observed)

| Date (UTC) | Post | Content |
|---|---|---|
| 15 Oct 10:32 | [2110680120843444589](https://x.com/mitsuhiko/status/2110680120843444589) | "In an afternoon (mostly passive) + one flight I built an IDE for Python for iOS that runs Pyodide, has a debugger, embeds linter and formatter, pi-durable powered coding agent and does iCloud Drive and all the other things too." Video: 78 s, 1180×2556, audio track digitally silent (−91 dB). 472 likes, 71 replies, 39.6 k views |
| 15 Oct 10:32 | [2110680275516854588](https://x.com/mitsuhiko/status/2110680275516854588) (self-reply) | "Also has a solid-js inspired version for Python that can bring up native UI. Because why not." 3 photos (§2.2) |
| 16 Oct 18:27 | [2111162089305678077](https://x.com/mitsuhiko/status/2111162089305678077) | To Lucas Meijer ("if I want to use opus55 I have to use their harnass and theirs is not durable"): "For some reason pi durable is not blocked by Anthropic. YMMV." |
| 21 Oct 22:43 | [2113038454942466410](https://x.com/mitsuhiko/status/2113038454942466410) | "'make it work with iPhone Duo and make it make sense' came out really nice." 3 photos of the same app on iPhone Duo |

### 2.2 What the video and photos show (Observed)

**Sign-in.** The app's name appears in the system dialog: "'Pyslopnista' Wants to Use 'radius.earendil.com' to Sign In". The Radius sheet offers "Sign in with browser (recommended)" and "Sign in with device code (when signing in from another device)". The device-code sheet shows "V6H8-SKEQ", Copy Code and "Open radius.earendil.com", and says the code "is already on the clipboard".

**Accounts screen:**
- Sign in with Radius ("Signed in"), and API Key ("Add Key").
- Under **Subscriptions:**
  - "Anthropic (Claude Pro/Max)";
  - "Sign in with ChatGPT" (openai);
  - "OpenAI (ChatGPT Plus/Pro)", labelled "OpenAI Codex (legacy)";
  - GitHub Copilot;
  - "Sign in with SuperGrok or X Premium";
  - Kimi Code;
  - Meta.

These are Pi's OAuth flows, working on iOS through the system sign-in sheet and device codes.

**Files.** An Examples folder holds:
- Catch the Turtle.py, Countdown.py, Counter App.py, Dependencies.py, Files.py;
- Flight.py, fractal.py, Guess the Number.py, Hello.py;
- notes.txt.

**Agent:**
- A sheet on "Claude Sonnet 4.5" ("Ask about the code in 'Examples', have it write a program, or explain an error").
- The request "Build me a little python script that renders a fractal as image" produces Write `fractal.py` and Run `fractal.py`. The console logs "Loading micropip, packaging … Installing numpy, matplotlib, pillow … Finished in 9313 ms", then "1 image shown to the model" and "Open fractal.py".

**Editor:**
- tabs (Catch the Turtle.py, fractal.py, Web Requests.py);
- a PEP 723 header (`# /// script` with `dependencies = ["numpy", "matplotlib", "pillow"]`);
- a Console panel that renders the matplotlib figure ("Mandelbrot Set Fractal") inline;
- a `>>>` Python prompt;
- "Finished in 8.3 s · Fractal rendered!".

Its menu lists Go to…, Jump to Definition, Show Info, Find, Find in Examples…, Format Code, Show Problems, Settings…, Rename…, Duplicate and Delete.

**Self-reply photos:**
- A debugger, "Paused · line 143", with step controls. The variable inspector shows `db` (`sqlite3.Connection`), `data` (`ReactiveDict`), `autosave` (`ui.Computation`) and `SORTS`, with "Tap a name in the editor to see its value. >>> runs here."
- A Reminders-style screen built in Python: Today 0, Overdue 1, All 4, Completed 4; My Lists: Inbox, Groceries, Learning; "Swipe a list to delete it."
- Its code: `ui.computed`, `ui.toast("The Inbox can't be deleted")`, `await ui.confirm(…, destructive=True, ok="Delete")`.

**iPhone Duo photos** show `Counter App.py`:
- Its comments: "Components run once. `count` is a signal: the lambdas that read it are what update on screen when it changes."
- The code: `ui.signal(0)`, `ui.Screen(…)`, `ui.Text(lambda: …, font="largeTitle")`, `ui.HStack(ui.Button("-1", on_click=…, kind="tinted", flex=1)…)`.
- The agent moves a misplaced `background=` keyword. The run shows "Finished in 900 ms".

### 2.3 Replies (38 of 71 gathered)

FxEmbed returns the first page of a thread and fails on later pages. Nested branches added the rest. Armin answered none of the technical questions in what was gathered (Observed):
- cold start ("hows the cold start", @simonlo);
- App Store ("does apple now allows apps executing code in App Store?", @RutkowskiHQ);
- interrupting a tight loop while keeping variables inspectable (@VaenshineX);
- whether the model runs on the device (@ethereaglehq);
- subscriptions ("What pi durable supports subs??? Even Claude?!", @tharshan_09).

The other replies are praise, and doubt about maintaining an app built in an afternoon.

### 2.4 Not known

- Whether Pyodide and Pi Durable run in a WKWebView or in JavaScriptCore.
- How the `ui` module reaches native views.
- Whether the app runs on an App Store build or a development build.
- Whether it will be released.

## 3. Ronith's Swift interpreter

### 3.1 Post and video (Observed)

[2102163666422702538](https://x.com/ronithhh/status/2102163666422702538), 21 Sep 22:30 UTC: "Prototyped a Swift interpreter that runs native, fully interactive iOS apps directly from a .swift file". It had 9,337 likes, 476 reposts, 295 replies and 1.76 M views. The 29.9 s video, 946×1682 and with no audio track, shows:
1. an "App World" document browser in the style of the Files app, with Create Document, `Weather.swift` and `WorkoutTracker.swift`;
2. the Swift source (`import SwiftUI`, `@main struct … : App`, `@State` properties);
3. a glitch transition into a weather app that looks like Apple's: San Francisco 64° Cloudy, hourly and 10-day forecasts, a city list, and Honolulu 84° Windy;
4. back to the browser, then `WorkoutTracker.swift` running as a workout app: Resume Current Workout; Full Body, Upper Body and Lower Body templates; set logging; and a menu with Start Rest Timer and Discard Workout.

### 3.2 What Ronith said in the thread (Observed)

| Question | His answer |
|---|---|
| Interpreting live, or compiling a bundle? | "Compile step from swift source to bytecode, rest is interpreted" |
| Link external xcframeworks? | "No unfortunately … Right now I'm bundling frameworks into the app at build time" |
| Why not Swift on WebAssembly? | "Couldnt just use wasm for this because it doesn't solve running swiftui code" |
| An API the interpreter does not support? | "The app exits and displays an error message (So no good handling yet lol)" |
| Persistence? | "Yup!" (the workout session survived a relaunch) |
| Is it LiveContainer? | "LiveContainer takes a compiled app binary as input, I'm trying to work directly from source text" |
| Like Playgrounds? | "I wish they just open sourced what playgrounds uses.." |
| One app that runs mini apps? | "Yeah this is exactly that, one app that can run mini apps" |
| Compiled dependencies such as CocoaPods? | "dont think that can work … Ultimately this will be for simpler apps" |
| Coverage? | "It's real, but doesn't have full feature coverage yet!" |
| Release and open source | "Not going open source route for now, will be using this for work on buoy"; "We want to generate native UIs on the fly within" buoy.chat; "Just a prototype not a released app" |
| The shake gesture | "I wanted to let the running app have as much control over gesture input as possible, hence shake to exit" |

Later, on 21 Oct: "Interface Club has been acquired by @variantui". iris.fun and buoy.chat sunset on 15 Nov ([2113012284419457271](https://x.com/ronithhh/status/2113012284419457271)).

### 3.3 Reply thread: 132 of 295 items gathered (Observed)

- **App Review dominates.**
  - The top reply: "holy shit apples not letting this ship" (1,083 likes). Ronith: "Yeah we will see haha".
  - Repliers quote 2.5.2 ("Apps may not download, install, or execute code that introduces or changes features…"), and note its educational exception.
  - One says Apple "purged a bunch of vibe coding and on-device code execution apps back in March". Ronith: "Yeah this is the thing that's really worrying".
  - Another says 2.5.2 "was written to stop" shipping apps that load `.swift` at runtime.
  - Several suggest sideloading through AltStore or an IPA.
- **Requests for the code.** Ronith offered one replier a DM ("Sure will dm you"); eight others in the gathered thread asked for the same.
- **Related projects named:**

| Project | What it is (Observed from its repository) | Use to us |
|---|---|---|
| [jasonkneen/interswift](https://github.com/jasonkneen/interswift) | §4 | Reference architecture, MIT |
| [emexlab/Nyxian](https://github.com/emexlab/Nyxian) | "A full native IDE and a userspace microkernel for building and running iOS apps entirely on-device", installed "just via a certificate". 1,272 stars, no license file | Sideload-only, unlicensed; not usable |
| [ForestP/SwiftlyInterpreter](https://github.com/ForestP/SwiftlyInterpreter) | "A Swift Inspired, Bytecode Based, Interpreted Language"; not SwiftUI | Low |
| LiveContainer | Runs compiled app binaries inside a container (Ronith's description) | Sideload-only |
| @Atlas_Slouched (unnamed) | "Swift > Wasm and a reimplementation of the SwiftUI api" | Unknown |

## 4. Interswift in detail (Observed, commit `03486798`, archived in evidence)

Jason Kneen posted it on 22 Sep, quoting Ronith: "as it's not being open-sourced (yet) I give you 'Interswift' … Just a start and not as good as shown above" ([2102501917674836012](https://x.com/jasonkneen/status/2102501917674836012), [2102504779746324821](https://x.com/jasonkneen/status/2102504779746324821)). It has two videos: an iPhone run (45.7 s) and a Mac run (30.4 s).

**Repository:**
- MIT licensed, one commit (2026-09-22 20:50 UTC), 5 stars;
- 28 files, about 100 KB of Swift, depending on SwiftSyntax 604.0.0;
- targets iOS 26+ and macOS 15+;
- the product is named "App World", with bundle ID `club.interface.AppWorld`. Those are Ronith's app name and company domain [INFERENCE: rebuilt from his video];
- its README cites a `spec-prd.md` that the repository does not contain.

**What it interprets** (README): one `@main App` with `WindowGroup { ContentView() }`; `Text`; `Button` with a string title and an integer `@State` assignment; `Spacer`, `Divider`, `VStack`, `HStack`, `ScrollView` and `NavigationStack`; the modifiers `.padding`, `.font`, `.foregroundStyle`/`.foregroundColor`, `.background` and `.frame(maxWidth: .infinity)`; integer `@State` with string interpolation; and two host-linked calls, `WeatherDashboard()` and `WorkoutTracker()`.

**How (source):**
- `GuestCompiler` walks the SwiftSyntax tree. It allows only `import SwiftUI` and `import Foundation`, and reports "Unbridged symbol", "Unbridged modifier" or "Unbridged view expression" as editor diagnostics.
- It emits a flat list of instructions: `text`, `spacer`, `divider`, `button(label, add/set)`, `group(kind, count)`, `padding`, `font`, `foreground`, `background`, `frame`, `weatherDashboard` and `workoutTracker`.
- `GuestVM` runs them on a stack to build a `GuestNode` tree.
- `GuestRenderer` draws the tree with SwiftUI.
- State is a `[String: Int]` dictionary; text interpolation is string replacement. "No native code is generated or loaded from the guest file."

**Its own caveats:**
- "WeatherKit, CoreLocation, arbitrary Swift control flow, general SwiftUI bridging … are not implemented."
- The Weather and Workout demos are native code "compiled into both host apps"; "editing their internals requires rebuilding the host".
- "This demo should not be used to execute untrusted files … it has not had a security audit."

**What it shows [INFERENCE]:**
- **The real design is a UI spec with precompiled components.** In practice a "Swift interpreter for generated UI" is a declarative view tree plus precompiled components, written in Swift syntax. That is the same design as a JSON or script UI API; only the authoring syntax differs.
- **The visual polish came from precompiled code.** In Interswift that is explicit. Whether Ronith's version interprets the full apps is not verifiable.

## 5. App Review rules for running generated code

**Text (Observed, [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), "Last Updated: October 16, 2026"):**
- **2.5.2:** "Apps should be self-contained in their bundles, and may not read or write data outside the designated container area, nor may they download, install, or execute code which introduces or changes features or functionality of the app, including other apps. Educational apps designed to teach, develop, or allow students to test executable code may, in limited circumstances, download code provided that such code is not used for other purposes. Such apps must make the source code provided by the app completely viewable and editable by the user."
- **4.7:** "Apps may offer certain software that is not embedded in the binary, specifically HTML5 and JavaScript mini apps and mini games, streaming games, chatbots, and plug-ins." It adds:
  - 4.7.1: privacy, content filtering and reporting;
  - 4.7.2: "may not extend or expose native platform APIs or technologies to the software without prior permission from Apple";
  - 4.7.3: no sharing data or permissions "without explicit user consent in each instance";
  - 4.7.4: an index of the software, with universal links;
  - 4.7.5: age restriction.

**Enforcement in 2026** (press; [MacRumors, 18 Mar](https://www.macrumors.com/2026/03/18/apple-blocks-updates-for-vibe-coding-apps/) and [30 Mar](https://www.macrumors.com/2026/03/30/apple-pulls-vibe-coding-app/)):
- Apple blocked updates of Replit and Vibecode on 18 Mar.
- It pulled "Anything" on 26 Mar, citing 2.5.2; the app returned on 3 Apr.
- Apple's statement: "there are no specific rules against vibe coding, but the apps have to adhere to longstanding guidelines."

**Precedents that ship:** Carnets and Pyto are Developer Tools apps that run user-editable Python with numpy, pandas and matplotlib (§6).

**What this means by approach [INFERENCE]:**

| Approach | iPhone, App Store | Mac, direct download (D32) |
|---|---|---|
| Generated declarative UI over our own components (data, not code) | Lowest risk: content drawn by the app's own reviewed components, like server-driven UI | Fine |
| Generated JavaScript logic for mini apps (QuickJS) | Named in 4.7, with obligations. Calls into Apple frameworks through our tools need care under 4.7.2 and 4.7.3 | Fine |
| User-visible Python notebooks and scripts | Developer-tool precedent (Carnets, Pyto) under 2.5.2's exception. Avoid downloading compiled code | Fine |
| Interpreting generated Swift as app features | Highest risk: the pattern Apple enforced against in 2026 | Fine |

## 6. Python in our apps: quant research and notebooks

### 6.1 Options (facts Observed in sources found 2026-10-22)

| Option | What you get | Limits |
|---|---|---|
| **Pyodide** in a hidden WKWebView on iPhone | Pyodide 314.0.7 (14 Sep 2026): Python 3.14, NumPy 2.4, pandas 3, SciPy 1.18, Matplotlib 3.10, statsmodels 0.14.6; scikit-learn 1.8 runs under JupyterLite. Pure-Python packages and Pyodide wheels from PyPI. WebAssembly is JIT-compiled in WebKit's own process [INFERENCE] | Cold start: one project measured the core at ~3 s and numpy, pandas, matplotlib and scipy (~43 MB) at ~8 s in headless Chromium; slower on a phone. Web content is memory-limited and can be killed ("jetsam … highwater"), with no published limit. Runs only while WebKit's process does, so suspended with the app [INFERENCE]. "Near native to … 3 to 5 times slower" (2021 figure) |
| **Native CPython** on iPhone | Official iOS XCframework since Python 3.15 (3.15.0 on 9 Oct 2026). PyPI accepts iOS wheels, and cibuildwheel builds them | NumPy, pandas and Matplotlib publish no iOS wheels on PyPI (NumPy PR #28759; the BeeWare index has some, Matplotlib only 3.6.0). We would build and ship every compiled package. Carnets ships such a stack: 1.5 GB, or 2.2 GB with scipy |
| **The Mac** (direct download) | Full CPython and Jupyter, numba, every library | Needs the Mac to be awake; reached over a remote environment |

### 6.2 Quant-specific notes [INFERENCE]

- **Run on iPhone through Pyodide:** numpy, pandas, scipy, statsmodels and matplotlib, plus pure-Python backtesting libraries.
- **Do not run on iPhone:** numba and libraries built on it, such as vectorbt. numba generates machine code at run time, which iOS forbids. A WebAssembly build exists in neither runtime.
- **Belong on the Mac (or a cloud runner):** long backtests, parameter sweeps, tick or minute data and machine-learning training. iPhone background time is bounded, and web content is memory-limited.
- **Market data should arrive through our own tools**, with API keys in the Keychain, and be handed to Python as files. Python's own network calls from a web view hit browser rules.

### 6.3 Notebooks

- **Format:** `.ipynb` is JSON: cells of markdown, code and outputs (text, images, tables). A native SwiftUI notebook view can render it, and the same notebook can run on the phone's kernel or on the Mac's [INFERENCE].
- **Alternative:** JupyterLite 0.8.6 runs full Jupyter on Pyodide 314.0.6 in a web view. It is quicker to adopt, but it is a web interface.
- **Precedent:** Carnets (BSD-3-Clause; 1.9.1 on 26 Nov 2025, Python 3.13) is a complete Jupyter app on iOS. Its stated limit applies to us too: only pure-Python packages can be installed at run time.

### 6.4 Recommendation [INFERENCE]

- **The Mac is the research machine:** Python and Jupyter, with heavy backtests run by Mac-homed bots.
- **On iPhone:**
  - Ship a pinned, offline Pyodide 314 bundle in a hidden web view for notebooks, quick analyses, small backtests and charts.
  - Measure cold start and memory on real devices.
  - Move to native CPython 3.15, with self-built wheels in the Carnets style, only if Pyodide fails those measurements or background runs prove necessary.
- **Keep user code viewable and editable,** and install only pure-Python packages at run time.

## 7. Native generative UI: premade and generated cards

### 7.1 What exists (Observed, sources found 2026-10-22)

- **Google A2UI:** "a declarative UI protocol for agent-driven interfaces". The client keeps "a 'catalog' of trusted, pre-approved UI components", and the agent "can only request to render components from that catalog". The UI is "a flat list of components with ID references".
  - Versions: v0.9.1 is current; v1.0, a release candidate, adds client-to-server actions.
  - Swift: the official SwiftUI renderer is "Planned"; a community renderer, [a2ui-swift](https://github.com/BBC6BAE9/a2ui-swift) (MIT), draws to SwiftUI, UIKit and AppKit.
- **Vercel json-render:** a catalog of components and actions defined by schema. The LLM emits JSON constrained to it, and "a generation that does not fit the catalog fails validation". Apache-2.0, v0.21.0 (18 Sep 2026), pre-1.0. [json-render-swift](https://github.com/ivanvanderbyl/json-render-swift) (Apache-2.0) ports its 26 standard components to SwiftUI.
- **MCP Apps** (SEP-1865, stable 26 Jan 2026): HTML in a sandboxed iframe. A native app needs a WKWebView for these.

### 7.2 Where Swift files fit [INFERENCE]

The user's idea: premade cards, plus new ones generated as Swift files. It maps onto the same structure in three layers:
1. **Components:** premade, compiled SwiftUI views. This is Memoshi's 17 card kinds (CH-09), plus Apple-data cards, Swift Charts, tables, forms and layout primitives. They are Interswift's "host-linked components" and A2UI's "catalog".
2. **A spec:** the declarative tree the app actually draws, validated against the catalog.
3. **Authoring** that produces the spec. The model can write it as:
   - JSON directly;
   - a **Swift subset** compiled with SwiftSyntax, as Interswift does. Models write SwiftUI well, and the files read as Swift;
   - Code Mode JavaScript calling a `ui` API with signals, for mini apps that need logic and state, as in Armin's Python layer.

**Graduation:** a generated card that proves itself can be promoted to a premade, compiled component in the next app release.

### 7.3 Why not a full Swift interpreter like Ronith's [INFERENCE]

- **Not available.** It is closed, its author's company has been acquired, and its product shuts down on 15 Nov.
- **Cost.** Full Swift (generics, protocols, result builders, property wrappers, closures, async) plus SwiftUI's API is a compiler-sized project. Its own author scopes it to "simpler apps", and it crashes on unsupported APIs.
- **App Review.** On iPhone, interpreting generated Swift as new app features is the 2.5.2 pattern Apple enforced against. 4.7 names only HTML5 and JavaScript for mini apps.
- **Not needed for the result.** A Swift subset that compiles to the spec gives Swift-file authoring, native rendering and premade components, without interpreting general Swift.

### 7.4 Recommendation [INFERENCE]

- **One catalog of native components and one declarative spec**, aligned with A2UI where practical so other agents' UIs can render too.
- **Authoring paths, in this order:** JSON; then the Swift subset; then JavaScript with signals for interactive mini apps.
- **Mini-app logic runs in QuickJS** (Pi_Swift's Code Mode engine) and reaches data only through our tools and policy.
- **MCP Apps** from third-party servers render in a sandboxed WKWebView.
- **The Mac build** may go further, for example with a broader Swift subset, because App Review does not apply to it.

### 7.5 What this changes in the plan

The plan makes generated widgets web content:
- CH-17 specifies inline widgets as "Charts, math and small HTML widgets in a sandboxed web view with no network".
- D29 keeps web views "for content only: … inline widgets".

Native generative UI would need a new decision under [change control](../plan/decisions.md#change-control). This note does not change either.

## 8. Open questions

**Answered 2026-10-22** by the user's decisions: question 1 by [D67](../plan/decisions.md#d67) (v1 is for the user's own devices, through TestFlight internal testing or Xcode, with no App Store), and question 2 by [D68](../plan/decisions.md#d68) (one Swift engine for live cards and mini apps; JSON cards stay; no JavaScript mini apps). Question 3 is taken up by [D60](../plan/decisions.md#d60) and Phase 0's S6 spike. The emulated Linux route in §5 became [D69](../plan/decisions.md#d69) (iSH, in its own GPL-3.0 module). So the App Review risks in §5 and §7 apply only to a later public release.

1. Will the iPhone app ship through the App Store, or stay on development and TestFlight builds for personal use for now? D38 does not say, and the risk in §5 depends on it.
2. Which authoring path first: JSON, the Swift subset, or JavaScript with signals?
3. Python on iPhone: what cold-start, memory and background results would Pyodide have to meet before native CPython is worth its build cost?
4. Which quant libraries and data providers matter, and should a Mac-homed research bot own the notebooks?

## 9. Sources

- **Posts:** as linked above. Raw threads, frames and photos are in `~/Documents/memoshi/evidence/2026-10-22-pi-mobile/` (see its README).
- **Interswift snapshot:** `interswift-03486798/` in the same folder.
- **Apple:** [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (retrieved 2026-10-22, "Last Updated: October 16, 2026").
- **Press on the 2026 enforcement:** MacRumors, [18 Mar](https://www.macrumors.com/2026/03/18/apple-blocks-updates-for-vibe-coding-apps/) and [30 Mar](https://www.macrumors.com/2026/03/30/apple-pulls-vibe-coding-app/).
- **Python:**
  - [Pyodide 314 release](https://blog.pyodide.org/posts/314-release/), [pyodide-py on PyPI](https://pypi.org/project/pyodide-py/) and the [changelog](https://pyodide.org/en/stable/project/changelog.html);
  - [Python on iOS](https://docs.python.org/3/using/ios.html), [python.org iOS releases](https://www.python.org/downloads/ios/) and [PEP 730](https://peps.python.org/pep-0730/);
  - [numpy#28759](https://github.com/numpy/numpy/pull/28759) and [BeeWare Mobile Wheels](https://beeware.org/mobile-wheels/);
  - [Carnets](https://github.com/holzschu/Carnets), [Pyto](https://apps.apple.com/us/app/pyto-ide/id1436650069) and [JupyterLite](https://jupyterlite.readthedocs.io/).
- **Generative UI:** [A2UI](https://a2ui.org/), [a2ui-swift](https://github.com/BBC6BAE9/a2ui-swift), [json-render](https://github.com/vercel-labs/json-render), [json-render-swift](https://github.com/ivanvanderbyl/json-render-swift) and [SEP-1865 MCP Apps](https://modelcontextprotocol.io/seps/1865-mcp-apps-interactive-user-interfaces-for-mcp).
