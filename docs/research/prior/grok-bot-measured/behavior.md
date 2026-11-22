# Grok Bot as measured: MemoBot's behavior contract (secondary source)

**Status:** Draft 4 · 2026-10-20 · imported prior research; everything below the `BEGIN VERBATIM COPY` marker is a frozen, byte-identical copy of the source
**Owns:** Memoshi's archived copy of MemoBot's `spec/behavior.md`, a measured description of Grok Bot 0.71.2 desktop behavior, kept as a behavior reference only
**Depends on:** [Research index](../../README.md) · [Grok Bot profile](../../agentic-workspace-landscape/projects/grok-bot.md) · [CONTEXT.md](CONTEXT.md) · [http.md](http.md) · [D29](../../../plan/decisions.md#d29) · [D33](../../../plan/decisions.md#d33)

> **Behavior reference only. Never copy assets.** MemoBot rebuilds Grok Bot's desktop UI with its own code, but it reuses Grok Bot's original static assets: fonts, glyph icons, artwork, audio, localization, vector geometry, animation data, and the native `Assets.car` and `icon.icns`. The rights to do so are unverified. The body says so itself: "User asset approval does not establish redistribution rights or legal clean-room certification." Memoshi never copies a Grok Bot or MemoBot asset, string, geometry or line of code ([D33](../../../plan/decisions.md#d33)) and draws its own avatars ([D29](../../../plan/decisions.md#d29)). Memoshi contributors do not open MemoBot's `.analyst-reference/` tree, its staged assets, or the captures in `.verification/`. Use this file for what Grok Bot does, not for how it is drawn.

## Provenance

| Field | Value |
|---|---|
| Source file | `~/Projects/MemoBot/spec/behavior.md`, 21,714 bytes, SHA-256 `83ea37ea04f1fa3f1f084672eb3003a1226fa5c707720698d7e0d90f0cb75296`, last modified 2026-10-20 15:56 local time |
| What it is | MemoBot's "independent implementation contract". MemoBot (`~/Projects/MemoBot`) is a local re-implementation of the Grok Bot desktop app: TypeScript and React on public Electron 42.1.0, with its own backend and a Swift OS helper. This file records the behavior and geometry its authors measured from the installed app, plus MemoBot's own design rules |
| Evidence class | **Secondary source.** Measured by MemoBot's authors; not published by xAI or Cursor, and not re-measured by Memoshi |
| Measured against | Grok Bot desktop **0.71.2** (2026-10-14, the last version in the public changelog). The app installed on this Mac is now **0.72.0** (`/Applications/Grok Bot.app`, bundle ID `com.anysphere.sand`, read from its `Info.plist` on 2026-10-20). What changed in 0.72.0 is unknown |
| Repo state | `~/Projects/MemoBot` is not a git repository and has no LICENSE file, so there is no commit to pin. The SHA-256 above pins the copied bytes. The source was still being edited on the day of the copy |
| Imported | 2026-10-20: copied with `cp`, then this header was prepended. Nothing below the marker was edited |

Check the body against the source (prints `identical` while the source is unchanged):

```sh
sed '1,/^<!-- BEGIN VERBATIM COPY -->$/d' docs/research/prior/grok-bot-measured/behavior.md \
  | diff - ~/Projects/MemoBot/spec/behavior.md && echo identical
```

## How to read it for Memoshi

**Precedence.** For product facts such as features, policies and release dates, the [Grok Bot profile](../../agentic-workspace-landscape/projects/grok-bot.md) wins, because it cites xAI's docs and changelog. This file wins only for measured desktop behavior as of 0.71.2. Even there it states MemoBot's targets, which aim to match Grok Bot's UI but not its private server internals or model wording.

| What to take | Body section | Where it informs Memoshi |
|---|---|---|
| Roster: a pinned grid with its own order; sections as owned records, where deleting one ungroups its bots; the seven bot actions; inline rename, unread, hide and restore | "Observable desktop surface" | Sidebar Bots section ([02-experience.md](../../../plan/02-experience.md)) |
| A details drawer with Details, Library and Computer tabs that edit real state: "All visible actions must work or show a precise missing-credential/OS-capability error" | same | Bot inspector ([02-experience.md](../../../plan/02-experience.md)) |
| Runs: overlapping turns queue per bot while different bots run independently; failed runs keep partial text; retry rechecks authority without duplicating the human turn | "Chat and runs" | Chats and Tasks ([05-bots-and-assistant.md](../../../plan/05-bots-and-assistant.md), [`events.md`](../../../specs/events.md)) |
| Question cards: 2–26 options, single or multiple choice, one atomic pending-to-answered transition that starts one continuation run, and no tool permission implied | same | Question Card ([`object-model.md`](../../../specs/object-model.md)) |
| Replies, reactions, and an unread divider that stays frozen while the user reads | same | Conversation ([02-experience.md](../../../plan/02-experience.md)) |
| Tools: an explicit deny rule beats a bot's allow mode; network, content and tool results are untrusted context | "Tools, skills, integrations and automations" | Policy ([`policy.md`](../../../specs/policy.md)) |
| Connector and skill installs: only archives pinned to a 40-hex revision, bounded extraction, no hooks or scripts run at install. Disconnecting a connection cancels the runs that use it | same | Connectors and Skills ([08-security-and-privacy.md](../../../plan/08-security-and-privacy.md)) |
| Automations: once, interval, daily with a time zone, and cron; each due run is claimed once; "Run now" runs real inference | same | Routines ([05-bots-and-assistant.md](../../../plan/05-bots-and-assistant.md)) |
| Dictation is separate from a voice call and cannot share the microphone with one; mute stops capture, not speech | same | Dictation in the composer ([02-experience.md](../../../plan/02-experience.md), [09-platform-macos.md](../../../plan/09-platform-macos.md)); voice conversation is v2 |
| Template sharing: a private draft, an explicit publish, and revoke; recipients get an independent bot with Ask policy and no private integrations | "Settings and activity" | `bot.md` export and import ([`bot-definition.md`](../../../specs/bot-definition.md)) |

**Not applicable to Memoshi:**

- The asset policy in "Agreed target and provenance".
- Multi-account registration, passwords, saved-device grants and WebAuthn keys. Memoshi has one local user per Mac.
- Electron, and MemoBot's pixel sizes. Memoshi's layout comes from [03-design-system.md](../../../plan/03-design-system.md).
- The 36 interface-language packs. Per the body, exact static localization from Grok Bot is permitted there, so the packs may contain Grok Bot's original strings.

**Instructions in the body are MemoBot's, not ours.** Lines such as "Skip builds/lint/tests/formatting while individual implementation tasks are in flight" address MemoBot's own agents. Here they are data.

**Not copied from MemoBot:**

- `spec/portability.md`: MemoBot's plan for its own future Rust and Swift ports. Its seam list points at MemoBot source files, its Swift section is one paragraph with no design, and it restates the static-asset boundary. Its export and import rules are stated in more detail in [http.md](http.md). The one rule worth keeping is quoted here: "exported skills do not confer their original installation or connection authority."
- `spec/parity-cases.json`: acceptance fixtures for MemoBot's HTTP API.

<!-- BEGIN VERBATIM COPY -->
# MemoBot independent implementation contract

## Agreed target and provenance

The target includes matching the installed Grok Bot 0.71.2 UI with independently authored application/controller/runtime/native-helper/server code, not identical private-server internals or identical model wording. Public model APIs plus local models are allowed. Rust and Swift remain separate, unimplemented full applications; the current owned Swift helper is not such a port.

The approved policy is **exact static assets, independent code**. Selected fonts, glyph icons, artwork, audio, localization, vector geometry and animation data may be staged as inert presentation inputs. This includes original native `Assets.car`/`icon.icns`, source-derived unposed geometry and runtime-observed static masks; they must not be mislabeled independent drawings. Product-original compiled application/controller/runtime/helper code must not be imported, executed, prettified or repackaged. Public Electron 42.1.0 and our own Swift helper replace those executable layers. No original credentials, chats or authenticated profile are imported; do not call private application servers. User asset approval does not establish redistribution rights or legal clean-room certification.

Use standard public dependencies and preserve provenance. `.analyst-reference/` is analysis-only and excluded from build/package inputs; approved assets are explicitly staged under the product tree. `.verification/parity-static-assets-provenance.json` records staged file sizes, SHA-256 and known origins, including observed/generated vectors without invented original filenames. Publicly fetched catalog marks have separate public-origin receipts, not assumed blanket licenses. Fresh SQLite persistence and credentials use the `independent` profile, never upstream state.

## Observable desktop surface

The measured desktop baseline is 1040×760 CSS pixels, with a 280px sidebar and 60px main header. Circular Search/New Bot controls, a three-column pinned-avatar grid, scrollable grouped roster, account menu and Connect apps footer frame the transcript and rounded composer. The empty composer is 728×44px; typed state is 728×76px. A settled reply draft is 728×114px, with a full-width 28px outlined quote preview, overlaid 20px cancel control and “Reply…” placeholder; the quote is not an icon-led, curly-quoted 22px row. Empty conversations never fabricate activity. Layout adapts to smaller windows and RTL. Approved static fonts/icons/geometry provide presentation inputs; independently authored UI/controllers provide behavior.

New Bot is 440×579px, with thirteen shape choices and eleven theme-aware colors, Cancel/Create, and independently implemented animated rendering. Approved normalized static paths, source-derived unposed numeric solids and runtime-observed SVG outline masks are inert vector data, not independently drawn geometry or recovered controllers. Rest/controlled-pose/transition measurements are finite observations, not exhaustive equivalence. Bots retain editable name, description, instructions, labels, provider/model, skills/connections, approval mode and knowledge.

Measured surfaces: Settings 900×666px with 198px navigation; catalog 800×666px; search 560×454.5px; details drawer 320px; bot menu 230×214px; share menu 230×63px; delete confirmation 320×151px. The seven bot actions are Pin/Unpin, Move to new section, Mark as Unread, Rename Bot, Copy conversation ID, Hide from sidebar/Restore bot, and Delete. Rename is inline; unread, hide/restore and pin order persist. Pinned bots are ordered separately from the grouped roster; moving to a section unpins the bot. Sections are owned records: create/rename/delete, drag bots between groups or ungroup, collapse locally; deleting a section ungroups its bots without deleting them. Delete requires explicit confirmation.

Details is a drawer with Details, Library, Computer tabs; editing updates real owned state. Library manages notes/files and shows selected skills/connections. Computer shows real capability/permission state, allowed workspace, connection configuration, and per-bot automation schedules. All visible actions must work or show a precise missing-credential/OS-capability error; no empty handlers or pretend success.

## Accounts and ownership

The backend is ours, local-first. Initial Sign in opens real owned registration/login, not upstream login. Registration collects display name, email and password and creates an isolated workspace/main bot. Passwords use a salted KDF; persisted revocable sessions and same-origin CSRF protect mutations. Account menu contains Usage & Billing with actual token count, active/archived roster switch, Support submenu (Activity and Import / export), Settings, Add account/account switching and Log out. The native reference account-menu receipt (`.verification/parity-account-reference-menu.json`) measures 228×212.5px, distinct from the bot-action menu. Submenus support keyboard navigation. No hard-coded identity or pretend authentication.

Saved-device account selection is real authority, not a database-wide account chooser. Sign-in/bootstrap remembers only authorized accounts for the private device cookie; list returns metadata only. Activate requires a valid encrypted server-side grant and creates a fresh session while revoking the previous active session. Forget removes that account's device authority/tracked sessions without deleting its workspace; forgetting the active account clears its session. Logout forgets the current account but preserves other saved accounts. Password/key-policy changes revoke affected grants; unknown/expired grants require actual authentication.

## Chat and runs

A bot supports persisted conversations, new conversation, history selection, clear with confirmation, user/assistant messages, streamed model text, stop/cancel, retry a failed run, copied message/code blocks, markdown tables/lists/links/code/math/diagrams, attachments, and tools/approval cards. Existing transcript survives restart. Consequential tool requests are shown before execution; denial and cancellation are durable, consumer-visible states. Run errors retain partial text and a useful explanation, never a fake assistant response. Model output comes only from configured providers. Preserve chronological message order and queue overlapping turns for one bot; different bots may run independently.

Replies persist optional `Message.replyToId`, not a client-authored quote. Require a completed canonical target in the same authorized conversation: missing/cross-conversation targets fail with 404 and incomplete targets with `409 REPLY_TARGET_INCOMPLETE`. Individual-message lookup resolves previews outside the loaded page without marking read. Provider history treats quotations as untrusted conversation data. Retry retains the original human turn's document/reply and rechecks current authority without duplicating the human message.

Reactions persist normalized emoji buckets and actor ID/display-name lists. Private owners/current room members set only their own desired `{emoji,active}` state idempotently; the server supplies session identity. Streaming messages reject reactions with `409 MESSAGE_STREAMING`; failed/cancelled messages remain reactable. Remove empty buckets and emit scoped canonical updates only on change. Imported reaction actors receive fresh historical IDs: they are not current accounts, membership or the importing person's own reaction authority.

Unread state uses optional persisted `Bot.lastReadMessageId`, with private per-member room preferences. Fetching any page records the conversation's latest message and clears that viewer's unread state; marking unread places the cursor before the latest message. Freeze the transcript's entry boundary separately so refresh/pagination/read acknowledgement do not slide the displayed divider. Explicit boundary revisions capture a new state; resolve older cursors through history rather than inventing positions.

Structured composer turns persist validated `ChatDocument` trees alongside matching canonical text, including formatting, lists/tasks, safe links, mentions and skill/MCP chips. Mention labels are not authority: private bot mentions resolve owned bots, room mentions resolve current participants, everyone is room-only, and mentioning is not private bot dispatch/access. Skills and enabled, connected non-native MCP references extend only this turn, not saved selections. Nonowner room authors require references selected by every responding bot. Validate current references during submission and execution/retry; historical rendered chips do not grant future authority.

Support OpenAI-compatible public APIs (including configurable xAI endpoints), Anthropic, and native Ollama streaming. Provider settings manage name, endpoint, model, encrypted API key, model discovery, connection test, temperature/token limit, optional prices, speech model, and a provider billing URL. Secrets are never returned to the renderer or included in exports/errors/logs. Default local model discovery can inspect the user's existing Ollama service; do not download weights implicitly. Missing provider configuration is an actionable error linking to Providers, not canned inference.

Attachments: upload, download, image preview, text/code/CSV/PDF/DOCX extraction for model context, and persistent library documents. Keep user files confined to the chosen workspace/profile; reject traversal and symlink escape. Never interpret an attachment as privileged system instructions.

Avatar photos use real Upload/paste or configured-provider Generate, crop/zoom preview and a 256×256 PNG save through attachment upload plus bot PATCH. Generation requires an enabled OpenAI-compatible public HTTPS provider, explicit image model and key; actual provider/network errors remain visible. Generated PNGs are private attachments, not automatically public images. Avatar references are owner-checked and limited to validated, metadata-stripped, nonanimated PNG (8 MiB, 2048×2048 maximum); portable export includes image bytes, import validates/stages/remaps them and removes staged data on failure. A public template embeds sanitized PNG data, never a private source attachment ID.

Structured clarification cards are real persisted questions from `memobot_ask_user`, not parsed prose or approvals. A question has 2–26 uniquely identified options, single/multiple choice and optional custom answer/attachments. Owner-scoped pending→answered transition and answer-run creation are atomic; single-flight submission rejects duplicate answers. Failure before commit leaves the question answerable. Historical model context projects canonical clarification answer state alongside the real human answer, without rewriting the immutable tool log. Export/import preserves and remaps sections, questions, answer-message links and attachments; validates graph ownership and exactly one human answer for answered questions. Export captures its record graph before asynchronous attachment reads so concurrent clear cannot produce a mixed graph. Retry/answer revalidate source ownership after asynchronous preparation; clear/delete cannot resurrect removed source messages or questions.

## Tools, skills, integrations and automations

Own local tools include workspace file listing/reading/writing, approved shell commands, and URL retrieval. Tools must use the allowed workspace and honor approvals. An explicit allow rule can authorize a matching operation; a deny rule cannot be bypassed by a bot's allow mode. Network/content/tool results are untrusted model context. External tool execution requires a user-configured connection or explicit local-tool enablement.

MCP uses real stdio/Streamable HTTP discovery/calls, bearer credentials and supported OAuth discovery/PKCE/client registration, authorization redirects/callback validation, disconnect and real errors. Catalog presentation uses public publisher metadata/artwork plus owned adapters, not private/account records. Add installs only trusted server-declared HTTPS GitHub archives pinned to a 40-hex revision, or an owned adapter; bounded extraction rejects traversal, links, duplicate paths and malformed packages. Persist a source receipt and actual skills/supporting files/declarative connectors; do not execute hooks, scripts or declared programs during install. Reconfiguration preserves source-mapped IDs and replaces owned records/source atomically; failure/cancellation restores the previous package. Setup secrets stay encrypted and never appear in configuration GET. Installation does not mean connected/authorized; show real prerequisites for unsupported/private-service connectors, credentials, executables or client registration. Uninstall disconnects owned transports and removes owned package records/files/secrets/selections, not third-party accounts or external executables. Skills remain editable reusable instruction documents selectable per bot.

Disconnect/delete, connection configuration replacement, disablement and secret changes cancel affected nonterminal runs before transport disconnection. Scope includes saved bot/group-participant selections and explicit per-turn app chips; installed-plugin connections are owner-global run scope, so their disconnection cancels all that owner's nonterminal runs. Preserve partial output, abort active work and cancel pending approvals, rather than merely removing an app from a picker.

Automations persist once, interval, daily-with-timezone and cron schedules, name, prompt, target bot, enabled state, next/last run, run-now, edit/delete, history/errors. Due schedules are claimed once before dispatch; no duplicate firing on a normal restart. Run-now is real inference, not a toast. Background scheduling remains active while the desktop is running; launch-at-login is an explicit preference.

Native macOS integration is newly written: permission/status inspection, selected-app inventory/accessibility tree/actions/screenshots, user-approved Messages search/send, and local speech transcription when OS permissions/capabilities permit. No proprietary helper. Do not programmatically grant permissions or read private apps without an approval. Sensitive native operations always require explicit user consent. Missing OS grants are visible prerequisites.

Desktop text Copy permits sanitized clipboard writes only from the owned main frame at the exact private application origin. Both Electron permission checks and requests enforce this boundary; renderer clipboard-read and camera permissions remain denied. Normal microphone requests stay audio-only, and notifications remain gated by the saved setting.

Dictation is a distinct single recording/transcription into the composer (or explicit auto-send); it cannot share microphone ownership with a voice call. A voice call stays with its original bot/conversation across navigation. Return to call uses a direct navigation callback. Lifecycle connecting/live/ending/failed is separate from idle/listening/thinking/speaking activity; settings/transcript trays do not end the call. Microphone mute stops capture/transcription but does **not** cancel spoken output. Reconcile delayed clarification metadata before speaking a completed reply, and route a spoken answer to its pending question. Explicit termination/failure/unmount releases tracks, audio contexts, capture nodes, timers and transcription requests; do not silently leak a pending permission acquisition.

Call capture uses an AudioWorklet with mono PCM sampled on the audio clock, bounded 500ms pre-roll, 240ms minimum voiced audio, 850ms trailing silence and 25.5s buffer cap. Quiet initial consonants are retained. Input bars/RMS are measured microphone signal; system-TTS output bars indicate speech activity/boundaries, **not** measured output PCM amplitude. Real transcription and system speech are required, never simulated text/audio. Per-bot voice preferences persist and normalize to 28 language choices plus automatic, six rates (0.5, 0.75, 1, 1.25, 1.5, 2), and selected voice URI. Missing platform/provider/grants produce actionable errors.

## Settings and activity

General: profile, Theme (System/Light/Dark), accent, language, spelling, microphone, hardware acceleration, timezone, auto-review/rules, security-key preference, notifications/sounds, launch at login. Settings persist and have actual effects. Hardware acceleration applies at next desktop restart. Security-key preference must be implemented with owned WebAuthn verification or explicitly identified as requiring an enrolled key; a boolean is not itself enrollment.

Settings geometry uses 32px content side padding, 28px group spacing, 14px-radius cards with 8px vertical inset, 48px rows (40px toggles), 28px selects and 32×20px switches. Customizable native selects size automatically to the selected value; the browser picker handles keyboard selection and Escape dismisses the picker before the enclosing settings modal. Preserve independent overlay dismissal rather than closing multiple layers at once.

Provider onboarding, catalog contents and configuration-sharing privacy review use independently configured public services and owned records. They do not reproduce private upstream subscriptions, private catalog access or private-service workflows.

Create a copy dispatches a chat prompt; `memobot_create_template` produces only a private owner-scoped persisted draft. Its tool card supports preview/edit/publish/copy/revoke/delete, using revision checks against concurrent edits. Editing changes the draft snapshot, never the live bot. Only explicit publish creates an immutable allowlisted configuration link; same-revision publish is idempotent, and explicit republish atomically revokes the predecessor. Revoke keeps the private draft; delete removes it and its publication. Published text redacts known secrets/workspace paths; recipients import an independent bot with ask policy and new image attachment. No conversations, private files/integrations/provider settings or approval grants cross the seam. The direct snapshot endpoint is a separate implemented API, not the tool-card lifecycle.

Native Email is unavailable without an owned service/domain: no address is created, no original product mailbox is claimed, and incoming mail, mail-trigger routines and approved sending are not implemented by displaying that catalog detail. Feedback submission stores an owned local SQLite report/optional conversation ID and returns a durable receipt; response preference stores profile email only when requested. It is not vendor delivery, sent email or a promised support response.

Provide 36 interface-language packs, not merely localized date formatting. The recorded structural check covers 1,052 keys in each pack; it is not professional translation review. Exact static localization is permitted by the asset policy, so provenance must not imply all text was independently authored. System resolves the device locale; Arabic, Hebrew and Urdu use RTL layout. Language selection is account-scoped, survives reload, and preserves interpolation values.

Computer: allowed workspace, local-tool opt-in, native permissions/status, MCP connections, automations. Usage & Billing: real run/token counts, configured price-based costs (unknown cost remains unknown), spending cap, per-provider breakdown and the provider's actual billing portal; MemoBot does not fabricate upstream credits or charge for a nonexistent service. Updates: independent app version, import/export, supported update source only when configured; never fetch/install the reference product's updates.

Search opens a keyboard-accessible global overlay for bots/messages/skills/documents, supports empty/loading/no-result states and opens the selected result. Cmd/Ctrl+K opens search, Escape closes overlays, Cmd/Ctrl+N opens New Bot. Activity shows real run/automation/tool records and errors. Notifications are real, permission-aware, and suppressible.

## Acceptance and portability

Shared records are in `src/shared/types.ts`; HTTP/event contract is in `spec/http.md`; runtime seam is in `src/shared/runtime.ts`. Keep UI state separate from owned backend state. Rust and Swift clients must be able to exercise the same JSON HTTP/SSE scenarios without JavaScript implementation details. Do not invent placeholder Rust/Swift projects now.

Required scenarios: independent startup without analyst directories; register/login/logout/restart; bot CRUD/avatar/pin/archive/delete; live local model stream and cancel; queued runs; approved/denied local tool; uploaded file/library; persistent settings; global search; skills; real MCP discovery/call; automation run and due trigger; export/import; native capability inspection; voice flow where configured; no secret leakage. Use permanent tests for meaningful invariants and language-neutral scenario fixtures. Skip builds/lint/tests/formatting while individual implementation tasks are in flight; integration owner runs them afterward.

Historical captures, non-hero pixel metrics and older package/test receipts are labeled by revision/scope in README. The finite avatar comparison recorded 128/142 strict-RGBA exact cases at 8×, including all 26 neutral cases but residual controlled-pose and shape-transition differences; it does not prove whole-app or exhaustive animation equivalence. The existing package is stale pending integrated rebuild/smoke/integrity work. Paid-provider credentials, physical keys/microphone, personal-app grants, mailbox service, private servers, professional translation review and notarization are not counted as done.
