# Platform building blocks for an always-on agent workspace

> Off-the-shelf parts Memoshi could build on (connectors, memory, scheduling, sync and relay, channels, voice, desktop shell), and what the profiled products actually picked. Last verified: 2026-10-20.

Conventions: every non-trivial claim carries a source link. `(vendor claim)` = stated by the maker, not verified. `[INFERENCE]` = our reasoning. `unknown` = searched, not found. Prices and stars are as of 2026-10-20 unless stated otherwise. In the "used by" columns, a product is listed only when its repository or docs show the dependency.

Profiled products and how we checked them: Grok Bot is closed, so we used its [docs][gb-overview] only. For the others we read the default branch through the GitHub API on 2026-10-20: [OpenMausBot][omb] (Apache-2.0, 5.2K stars), [Rakazo][rkz] (Apache-2.0, 4.8K), [Noodle][ndl] (Apache-2.0, 179), [Lorca][lrc] (GPL-3.0, 316), [OpenBot][obt] (PolyForm Noncommercial 1.0.0, 671), [Aiden Agent][adn] (MIT, 85), [Kuvo Code][kuvo] (PolyForm Noncommercial 1.0.0, 64), [OpenClaw][oc] (MIT, 393K) and [Hermes Agent][hm] (MIT, 255K). On 2026-10-22 every Kuvo Code fact that came from its source was removed; Kuvo facts here now come from its public docs, README and CHANGELOG only ([D55](../../../plan/decisions.md#d55)).

## What changed in 2026 that affects these choices

| Date | Change | Why it matters |
| --- | --- | --- |
| 2025-11-19 announced, closed in FY2026 | Workday acquired Pipedream ([Workday 10-K exhibit][wday]) | Pipedream Connect is now owned by an enterprise HR vendor. Its roadmap risk is higher [INFERENCE]. |
| 2026-01-15 | WhatsApp Business Solution Terms bar "AI Providers" whose AI is the primary function ([terms][wa-terms]; press: [TechCrunch][wa-tc]) | A general-purpose assistant cannot use the official Cloud API. The only remaining route is unofficial Baileys, which carries ban risk. |
| 2026-08-05 | Arcade.dev acquired Smithery. Smithery's MCP proxy, Connect, API, CLI and SDKs shut down on 2026-10-31 ([smithery.ai/future][smithery-future], [Arcade blog][arcade-smithery]) | Do not build on Smithery. |
| 2026-08-19 | The InstantDB team joined OpenAI. Instant Cloud shuts down 2027-08-31 ([essay][instant-openai]) | Only the self-hosted path remains. |
| 2025-10-08 | Supabase acquired Triplit. Its repo was last pushed 2026-01-19 ([Supabase][triplit-supabase], [repo][triplit]) | Treat Triplit as dormant. |
| 2026 | Zep Community Edition deprecated. The open-source path is Graphiti ([graphiti][graphiti], [zep repo][zep-repo]) | No self-hosted Zep. |
| 2026 | The MCP Registry is still a preview. Its API has been frozen at v0.1 since 2025-10-24 ([registry][mcp-registry], [repo][mcp-registry-gh]) | Use it for discovery metadata only. It handles no OAuth and no per-user scoping. |
| 2026 | `imsg` moved from steipete to [openclaw/imsg][imsg]. OpenClaw removed BlueBubbles support ([OpenClaw announcement][oc-bb]) | The iMessage stack is consolidating on `imsg`. |
| 2026 | OpenAI shipped GPT-Live (`gpt-live-1`) with client-side delegation to a backend agent ([guide][oai-live]) | Voice can stay a thin layer while the agent remains the brain. OpenMausBot and OpenClaw already use it. |

## 1. Connectors

| Option | License | Hosting | Pricing (2026-10-20) | Strengths | Caveats | Used by |
| --- | --- | --- | --- | --- | --- | --- |
| [Composio][composio] (Sessions, formerly Tool Router) | SDK MIT; platform proprietary | cloud | Hobby $0: 100K tool calls and 50K trigger events per month. Pro $29/mo including $29 credit, then $0.0003/call and $0.003/trigger. Managed-OAuth calls cost $0.0005, and managed-app connections beyond the first 1K cost $0.10 one-time each ([pricing][composio-pricing]) | `sessions.create(user_id)` scopes toolkits per user, with a multi-account mode and an MCP endpoint per session ([docs][composio-sessions]). Includes triggers (app events). 30.6K stars | The default shared OAuth app shows the "Composio wants to access" consent screen. White-labelling needs your own OAuth apps. Cloud only | [OpenMausBot][omb-composio]: one project key, one reusable Session, labelled multi-accounts, triggers through its own Cloudflare broker ([broker][omb-broker]). [Rakazo][rkz-composio] (`@composio/core`). [OpenBot][obt-composio] (marketplace entry pointing at a user's Composio MCP URL) |
| [Pipedream Connect][pd-pricing] | Pipedream Source Available License v1.0 | cloud | Free in development only. Startup $99/mo (annual) or $150/mo, includes 100 external users, then $2/user/mo, and 10K credits, then $0.012/credit (1 credit = 30 s of compute) | 3,000+ apps (vendor claim). Billed per `external_user_id`. Managed OAuth or your own OAuth clients ([docs][pd-oauth]) | Workday-owned. Production use requires a paid plan. No self-host | [Rakazo][rkz-pd] (`pipedream-connector.ts`). [Noodle][ndl-mcp] (Pipedream as an MCP connection) |
| [Arcade.dev][arcade-pricing] | arcade-mcp MIT; platform proprietary | cloud; VPC/Helm on Enterprise | Free: 2,000 auth events and 2,000 tool calls. Team $25/mo plus $0.10/auth event and $0.01/tool call | Per-`user_id` token scoping and policy enforcement (vendor claim). Now owns Smithery | Arcade recommends your own OAuth apps in production ([docs][arcade-auth]). Per-call price is high at volume | none found |
| [Nango][nango-pricing] | Elastic License 2.0 | both (self-host has a reduced feature set) | Free: 10 connections. Pay-as-you-go $50/mo, then $0.29/connection/mo and $0.72/compute-hour | Auth for 1,000+ APIs (vendor claim). Managed or bring-your-own OAuth apps. One connection per end-user account ([repo][nango]) | ELv2 is not OSI open source. Per-connection pricing grows with users | none found |
| [Paragon ActionKit][paragon] | proprietary | cloud; self-host on Enterprise | Quote only, priced per connected user (unknown) | One API plus MCP server. Users identified by a signed JWT ([docs][paragon-docs]) | Opaque pricing. Built for B2B SaaS embedding | none found |
| [Zapier MCP][zapier-mcp] | proprietary | cloud | Included in Zapier plans. Each MCP call costs 2 tasks. Free plan: 100 tasks/mo | 9,000+ apps (vendor claim) | Credentials are scoped to one Zapier account, so not multi-tenant ([docs][zapier-conn]) | none found |
| [Official MCP Registry][mcp-registry] | MIT, moving to Apache-2.0 | public instance plus open-source server | free | Canonical server metadata with namespace verification. Can be mirrored | Preview with possible data resets. Metadata only | none found as a runtime dependency. OpenClaw's `mcp registry` command is its own local list ([docs][oc-mcp-reg]) |
| [Smithery][smithery-future] | CLI AGPL-3.0 | cloud, ending 2026-10-31 | Paid plans cancelled and refunded | Large directory | Shutting down | none found |
| Plain MCP client with its own OAuth (MCP auth: discovery, PKCE, loopback redirect) | n/a | local | free | No vendor in the path. Tokens stay on the device | You build the catalog, consent UI and token refresh. Each service needs its own OAuth client | All 9 OSS products, for example [OpenMausBot][omb-mcpoauth], [Rakazo][rkz-mcpoauth], [Noodle][ndl-mcpoauth], [Lorca][lrc-int] (`rmcp`), [OpenBot][obt-mcpoauth], [Aiden][adn-mcpoauth], [OpenClaw][oc-mcp-reg], [Hermes][hm-mcp]. [Grok Bot][gb-teambots] accepts remote HTTPS or command-based custom MCP servers |
| First-party plugin catalog with server-held tokens | proprietary | cloud | bundled with the plan | Bots call tools but never see OAuth tokens ([security][gb-security]) | Installed connectors are account-wide, not scoped per bot ([docs][gb-computer]) | [Grok Bot][gb-computer] ("Connect apps") |
| Direct REST "built-in" connectors | n/a | local | free | Full control, no third party | One connector at a time | [Lorca][lrc-int]: Gmail, Calendar and Drive through Google REST with Desktop OAuth plus PKCE. Slack through Slack's own MCP server |

**OAuth and per-bot scoping in practice**

- Labelled accounts with explicit selection. OpenMausBot asks for a label on every new account. It tells Composio to require explicit account choice when more than one could run a tool, so a new OAuth flow never silently replaces an existing one. The project key is encrypted with Electron `safeStorage` ([docs/composio.md][omb-composio]).
- Named accounts with per-account rules. Lorca keeps each account as a "named account" on a Runner. Each has its own Access rules and call limits, and tokens never reach the model's context or other devices ([integrations.md][lrc-int], [channels.md][lrc-channels]).
- Tokens held server-side. Grok Bot keeps OAuth tokens on its backend and Bots call tools without receiving them ([security][gb-security]). Its connectors are account-wide, not per bot ([computer-and-apps][gb-computer]).
- Hosted trigger relay. OpenMausBot's Cloudflare Worker broker (D1 plus rate limiters) receives signed Composio trigger events, queues them per installation for up to 7 days, and the local app long-polls the queue. This gives a desktop app "app event" automations without a public endpoint ([docs/composio.md][omb-composio], [wrangler.jsonc][omb-broker]).

## 2. Memory

| Option | License | Hosting | Pricing (2026-10-20) | Strengths | Caveats | Used by |
| --- | --- | --- | --- | --- | --- | --- |
| Plain Markdown files (`MEMORY.md`, `USER.md`, topic notes, daily logs) | n/a | local | free | Readable and editable by users. Diffable, portable, and works with Obsidian. No vendor | Recall quality depends on a load budget and search. Concurrent writers need care | [OpenClaw][oc-mem] (`USER.md`, `MEMORY.md`, `memory/YYYY-MM-DD.md`, `DREAMS.md`). [Hermes][hm-mem] (`MEMORY.md` 2,200 chars and `USER.md` 1,375 chars, frozen into the prompt at session start). [OpenMausBot][omb-mem] (first 200 lines or 24 KB of `MEMORY.md` load each turn, older entries move to `archive.md`, credentials redacted, 0600 files). [Lorca][lrc-mem] (`MEMORY.md`, topic notes, daily log on the Runner, synced E2E). [Aiden][adn-mem] (`MEMORY.md` plus `USER.md`, entries separated by `§`, the same format as Hermes) |
| Markdown plus SQLite FTS5/BM25 plus embeddings (sqlite-vec) | sqlite-vec MIT/Apache-2.0 | local | free | Hybrid keyword and vector recall with no server | You maintain the embedding pipeline | [OpenClaw memory-core][oc-mem-builtin] (FTS5 + vector + optional sqlite-vec in a separate read-only process). OpenClaw also has an optional [LanceDB plugin][oc-ext] and a `memory-wiki` plugin |
| Markdown documents in Postgres with revisions | n/a | server | free | Multi-tenant, transactional and versioned | Substring search only | [Rakazo][rkz-mem] (`MarkdownMemoryStore` with revisions, scoped per space, user and bot) |
| SQLite rows per owner, event-sourced | n/a | local | free | One schema for agent, channel and messaging-connection memories | Not readable as plain files | [OpenBot][obt-mem] (`node:sqlite`; owners are agent, channel and connection) |
| [Letta][letta] | Apache-2.0 | both | Free (BYOK). Pro $20/mo. API plan $20/mo plus $0.10 per active agent/mo ([pricing][letta-pricing]) | Self-editing memory blocks. 25.2K stars | It is a full agent runtime, so adopting it means adopting its agent model | none found |
| [mem0 / OpenMemory][mem0] | Apache-2.0 | both | Hobby free: 10K adds and 1K retrievals. Starter $19/mo. Pro $249/mo (graph memory) ([pricing][mem0-pricing]) | Simple `user_id`/`agent_id`/`run_id` scoping. 67.5K stars | Graph memory only on Pro | [Hermes][hm-memprov] (catalog plugin) |
| [Zep][zep-pricing] / [Graphiti][graphiti] | Apache-2.0 (Graphiti) | Zep cloud; Graphiti self-host | Free 10K credits. Flex $125/mo | Temporal knowledge graph with per-user graphs. Graphiti has 32.1K stars | Zep CE deprecated. High entry paid tier | none found |
| [Supermemory][supermemory] | MIT | both (self-host only on Scale/Enterprise) | Free with $5 credit/mo. Pro $19/mo ([pricing][supermemory-pricing]) | Memory graph plus RAG. Unlimited end users | Self-hosting is gated despite the MIT license | [Rakazo][rkz-supermemory] (provider adapter). [Hermes][hm-memprov] (catalog) |
| [Honcho][honcho] (Plastic Labs) | AGPL-3.0 | both | $5 starting credit. Ingestion $2/1M tokens. Queries $0.001 to $0.50 by reasoning level ([site][honcho-site]) | Peer-centric user and agent modelling. Supports multi-agent observers | AGPL. Per-query cost is hard to forecast | [Rakazo][rkz-honcho] (provider adapter). [OpenClaw][oc-honcho] (plugin). [Hermes][hm-memprov] (catalog) |
| [Cognee][cognee] | Apache-2.0 | both | Free 1M tokens. $1 per 1M processed ([pricing][cognee-pricing]) | Runs locally. Graph plus vector. 32.6K stars | Young hosted offering | [Hermes][hm-memprov] catalog entry ([cognee.yaml][hm-cognee]) |
| [LangMem][langmem] | MIT | library | free | Extraction and prompt-optimization primitives | Tied to LangGraph. 1.7K stars | none found |
| [Basic Memory][basicmem] | AGPL-3.0 | local plus cloud sync | Local free. Cloud $15/seat/mo ([pricing][basicmem-pricing]) | Markdown knowledge graph exposed over MCP | AGPL. Per-seat pricing | none found |
| First-party opaque memory | proprietary | cloud | bundled | "Stable preferences, role context, and summaries of prior work", kept separately per Bot ([FAQ][gb-overview]) | Mechanism unknown. Users cannot inspect it as files (unknown) | [Grok Bot][gb-overview] |

**What the profiled products converge on.** Seven of the nine OSS products keep memory as plain Markdown or plain records they own, with no memory vendor in the default path. Only Rakazo (Honcho, Supermemory), OpenClaw (Honcho, LanceDB) and Hermes (RetainDB and ByteRover bundled, others from a [catalog][hm-memprov]) add external providers, and always as an optional extra on top of the built-in store. Hermes allows exactly one external provider at a time. It mirrors built-in writes to that provider and passes everything through a secret scrub first ([memory-providers.md][hm-memprov]). The shared pattern [INFERENCE]: a small always-loaded file with a hard budget, topic files read on demand, a searchable log, credential redaction on write, and a visible, editable memory panel. Noodle documents only that a bot "keeps its workspace, memory and messages" ([usage.md][ndl-usage]); the mechanism is unknown.

## 3. Scheduling, durable execution, triggers

| Option | License | Hosting | Pricing (2026-10-20) | Strengths | Caveats | Used by |
| --- | --- | --- | --- | --- | --- | --- |
| In-process cron ([croner][croner], [croniter][croniter]) plus a persisted job table | croner MIT | local | free | No infrastructure. Timezone and seconds support. Works offline | Only fires while the daemon runs. You build retries, catch-up and history yourself | [OpenClaw][oc-cron] (`src/cron/schedule.ts`; jobs and run history in SQLite; Gateway must be running). [OpenMausBot][omb-routines] (Croner; overlapping runs blocked). [Rakazo][rkz-cron] (`croner` for parsing). [Aiden][adn-pkg] (`croner` plus `schedule-store.ts`). [Hermes][hm-cron] (`croniter`, single `cronjob_manage` tool, script-only no-agent mode) |
| Own scheduler code | n/a | local | free | Exact semantics: one-time runs, calendar-relative runs, DST handling | You maintain it | [Lorca][lrc-triggers] (Rust, `chrono-tz`; one-time, on-event and calendar-relative routines). [OpenBot][obt-sched] (`routine-scheduler.ts`). [Noodle][ndl-usage] (heartbeats and bot-scheduled wake-ups, only while the app is open and the Mac awake) |
| [Graphile Worker][graphile] | MIT | self-host on Postgres | free | `SKIP LOCKED` plus `LISTEN/NOTIFY`, crontab, no extra infrastructure | Node only, pre-1.0 | [Rakazo][rkz-worker] (`apps/worker` with graphile-worker plus an advisory-lock leader) |
| [Temporal][temporal] | MIT | both | Cloud: no base fee, $50 per 1M Actions (tiered down to $25/M). Business plan $500/mo ([pricing][temporal-pricing]) | Most mature. 7+ SDKs | Every timer, signal and retry is billed. Self-hosting is operationally heavy | none found |
| [Inngest][inngest] | SSPL-1.0 with delayed Apache-2.0 | both | Free 50K executions. Pro from $99/mo ([pricing][inngest-pricing]) | Event-driven step functions | SSPL. Low free-tier concurrency | none found |
| [Trigger.dev v4][triggerdev] | Apache-2.0 | both | Free $5 credit/mo. Hobby $10. Pro $50 plus compute ([pricing][triggerdev-pricing]) | No run timeouts. Checkpointed waits are not billed | TypeScript-first | none found |
| [Restate][restate] | BSL-1.1 | both | Free 100K actions. Starter $75/mo ([pricing][restate-pricing]) | Single Rust binary. Virtual objects | BSL, not OSI | none found |
| [DBOS Transact][dbos] | MIT | library on your Postgres; Conductor hosted | Library free. Conductor Pro $99/mo ([pricing][dbos-pricing]) | Durable workflows with just a library and Postgres | Hosted pricing partly undisclosed | none found |
| [Cloudflare Agents SDK][cf-agents] + [Durable Objects][cf-do] + [Workflows][cf-wf] | SDK MIT; runtime proprietary | cloud | DO free: 100K requests/day and 5 GB SQLite. Workers Paid from $5/mo. Workflows: 500K steps/mo, then $0.80 per 100K (billing started 2026-08-10) | One actor per agent, WebSocket hibernation, alarms | Lock-in. `agents` npm is pre-1.0 (v0.28.1) | OpenMausBot's [control plane and Composio broker][omb-broker] use Workers, D1 and Cron Triggers, but not Durable Objects or Workflows. [OpenBot][obt] account API uses Workers and D1 |
| [Convex][convex] scheduler, crons, Workflow component | backend FSL-1.1-Apache-2.0 | both | Free 1M calls, then $2.20/M. Pro $25 per developer ([pricing][convex-pricing]) | Scheduling is transactional with database writes. Reactive queries | FSL is source-available | none found in runtime code (OpenClaw uses Convex only in its [QA credential broker][oc-convex]) |
| Event-trigger relay (vendor or own) | n/a | cloud | varies | Desktop apps get webhooks without exposing a port | Needs an always-on relay | [OpenMausBot][omb-composio] (Composio triggers through its broker, long-poll). [Lorca][lrc-relaydoc] (relay "hosted receivers" seal each webhook to the subscribed Runner; this is the relay's only plaintext ingress). [OpenBot][obt-webhooks] (account service routes signed webhooks to the host over its Signal channel). [Grok Bot][gb-skills] (Cursor account integrations: Slack messages, GitHub notifications; schedules at least 5 minutes apart) |
| Email-in triggers | n/a | local or hosted | free to $ | Email-to-agent works everywhere | Parsing and authentication (DKIM, ARC) | [OpenClaw][oc-ext] `imap` plugin (imapflow, mailauth, mailparser) and [Gmail automations][oc-gmail]. [Hermes][hm-email] email platform. OpenMausBot handles Gmail through Composio triggers |

## 4. Sync, relay, remote access, end-to-end encryption

| Option | License | Hosting | Pricing (2026-10-20) | Strengths | Caveats | Used by |
| --- | --- | --- | --- | --- | --- | --- |
| [Tailscale][ts-pricing] Serve / Funnel / [tsnet][tsnet] | client BSD-3-Clause; control plane proprietary | vendor control plane | Personal $0 (6 users, non-commercial). Standard $8/user/mo | Encrypted, authenticated reachability with no public port. Serve adds identity headers | Users must install and sign in to Tailscale. [Funnel][ts-funnel] is beta, limited to ports 443/8443/10000 | [Aiden On The Go][adn-otg] (Serve only, never Funnel; own per-device credential still required). [OpenClaw][oc-ts] (Serve, or Funnel with a password). [OpenMausBot][omb-ts] (recommended remote route). [Hermes][hm-desktop] (documented remote option) |
| [Cloudflare Tunnel][cf-tunnel] | cloudflared Apache-2.0 | vendor | No tunnel fee found. Quick Tunnels need no account | Outbound-only. Stable hostnames | Needs a domain on Cloudflare. Quick Tunnels are for development | [OpenMausBot][omb-tunnel] (managed `cloudflared` tunnel through its control plane for `serve --tunnel`). [OpenClaw][oc-remote] (Cloudflare Tunnel plus Access, documented). [OpenBot][obt] (dev-only quick tunnels) |
| [ngrok][ngrok] | agent MIT; service proprietary | vendor | Free $5 one-time credit. Hobbyist $10/mo | Fastest setup | Free tier shows an interstitial page | none found as a runtime dependency |
| SSH tunnel | n/a | self | free | Universal fallback | Developer-grade UX | [OpenClaw][oc-remote] (client-managed tunnels, LaunchAgent recipe). [Hermes][hm-desktop] (SSH gateway connection) |
| Own relay with E2E-sealed blob sync | own (GPL-3.0) | own (Railway recipe) | your hosting | Stores only public keys and ciphertext. Multi-device sync, APNs/FCM pushes, S3 attachments. SQLite or Postgres with `NOTIFY` fan-out | You run the relay. The webhook receivers read plaintext briefly | [Lorca][lrc-relay] (`crates/relay`: axum, x25519-dalek, crypto_box, chacha20poly1305, ed25519 signed identity writes; [architecture][lrc-relaydoc]) |
| WebRTC peer-to-peer with own signalling and TURN | own | own Signal service plus coturn; accounts on Cloudflare Workers/D1 | your hosting | Chats and files go peer-to-peer. The cloud never carries content | NAT traversal and TURN operations | [OpenBot][obt] (Team API stays on loopback; a hidden Electron page bridges it over WebRTC; the same transport runs on mobile) |
| Router port-forward (UPnP / NAT-PMP) | own | user's Mac | free | No third party at all | Breaks on carrier-grade NAT. Exposes a UDP port | [Noodle Hub][ndl-hub] (UDP 38415, or a user-supplied address) |
| LAN with pinned TLS | own | local | free | Works offline. Bonjour discovery | Same network only | [Aiden][adn-otg] (per-install P-256 HTTPS identity; the QR code carries the CA anchor and key pin) |
| [Convex][convex] | FSL-1.1-Apache-2.0 | both | see section 3 | Reactive sync and scheduling in one system | Server-authoritative, not E2E | none found |
| [Electric][electric] | Apache-2.0 | both | Bills under $5/mo waived. $1/M writes ([pricing][electric-pricing]) | Postgres read-path sync over HTTP shapes | Writes go through your own API | none found |
| [Zero][zero] | Apache-2.0 | both | Self-host free. Cloud from $30/mo | Query-driven sync | No free cloud tier | none found |
| [InstantDB][instant] | Apache-2.0 | self-host (cloud winding down) | New cloud signups closed | Open-source sync plus auth | Cloud ends 2027-08-31 | none found |
| [Jazz][jazz] | MIT | both | Cloud pricing marked as draft | Local-first with permissions | Rewritten in Rust in 2026. The new repo is young | none found |
| [Automerge][automerge] / [Yjs][yjs] | MIT / MIT | library | free | Mature CRDTs | You supply relay and persistence | none found |
| [Triplit][triplit] | AGPL-3.0 | self-host | n/a | Syncing database | Dormant after the Supabase acquisition | none found |
| [libsignal][libsignal] | AGPL-3.0 | library | free | Signal Protocol with PQXDH | AGPL. Not supported for outside use | none found |
| [OpenMLS][openmls] ([RFC 9420][rfc9420]) | MIT | library | free | Standard group E2E (MLS) | Pre-1.0. You bring the delivery service | none found |
| [libsodium][libsodium] / [age][age] / Apple CryptoKit | ISC / BSD-3-Clause / OS | library | free | Audited primitives (box, secretbox, X25519) | Primitives only, no protocol | Lorca uses the RustCrypto equivalents (`crypto_box`, `chacha20poly1305`) ([Cargo.toml][lrc-cargo]) |
| Matrix ([Synapse][synapse], [matrix-rust-sdk][matrix-rust], [vodozemac][vodozemac]) | Synapse AGPL-3.0 or commercial; SDK and vodozemac Apache-2.0 | both | Element Server Suite Community free ([pricing][element-pricing]) | Federated E2E rooms. Native multi-party | Element calls Community Synapse "not for use in production environments". Heavy as a private substrate | Used as a channel, not as Memoshi's substrate: [OpenClaw][oc-ext] (`@matrix-org/matrix-sdk-crypto-*`). [Hermes][hm-pyproject] (`mautrix[encryption]`) |
| [LiveKit][livekit] | Apache-2.0 | both | Build $0: 1,000 agent minutes. Ship $50/mo | WebRTC SFU plus agents and SIP | Per-minute cloud charges | none found. Noodle links LiveKit's [WebRTC xcframework][ndl-pkg] |

**How Lorca's relay and Aiden On The Go work, in brief.**

- **Lorca.** Each identity has an ed25519 identity key and per-machine box keys. Clients write encrypted "blobs" of kinds such as `task`, `chat`, `credentials`, `file` and `job`; the nonce sits inside the ciphertext. Some envelopes are sealed to one machine and are deleted once consumed. The relay only signals sockets with "nudges"; clients pull pages and decrypt. With Postgres, writes for one identity are ordered by a transaction-scoped advisory lock, and `NOTIFY` fans events out across replicas. Housekeeping expires unconsumed envelopes after 7 days. A Prometheus `/metrics` endpoint is "the only view of a relay that cannot read what it stores" ([relay.md][lrc-relaydoc]).
- **Aiden On The Go.** Two modes. LAN mode advertises over Bonjour with a pinned self-CA HTTPS identity. Tailscale mode proxies only `/api/aiden/v1` through Serve and refuses to touch Funnel or unrelated Serve handlers. In both modes every phone gets its own random credential, stored as an scrypt digest. QR codes expire after 5 minutes and work once ([doc][adn-otg]).

## 5. Messaging channels

| Option | License | Hosting | Pricing (2026-10-20) | Strengths | Caveats | Used by |
| --- | --- | --- | --- | --- | --- | --- |
| [Telegram Bot API][tg-changelog] | proprietary, free service | Telegram cloud | Free. Paid broadcasts only above 30 msg/s | Bot API 10.x (May to Aug 2026) added `sendMessageDraft` streaming, guest mode and Rich Messages. Long-poll works without a public URL | No E2E for bots. About 1 msg/s per chat ([FAQ][tg-faq]) | [OpenClaw][oc-ext] (grammY). [Hermes][hm-pyproject] (python-telegram-bot). [Lorca][lrc-channels] (Runner polls). [OpenBot][obt-tree] (`apps/telegram-app`). [Rakazo][rkz-adapters] (Chat SDK adapter). [Aiden][adn] |
| [Slack apps][slack-ai] | proprietary | Slack | API free | Agent surfaces: split view, streaming, task cards. MCP server and Real-time Search API (2026-02) | Since 2025-05-29, non-Marketplace commercial apps are limited to 1 req/min on `conversations.history` ([changelog][slack-rl]) | [OpenClaw][oc-ext] (Bolt). [Hermes][hm-pyproject] (slack-bolt). [Lorca][lrc-int] (Slack MCP plus bot user). [OpenBot][obt-tree] (`apps/slack-app`). [Rakazo][rkz-adapters]. [OpenMausBot][omb-slack] (hosted Slack). [Grok Bot][gb-skills] (event triggers and drafts) |
| Discord bots | proprietary | Discord | free | Mature gateway. Voice channels | Verification required at 100+ guilds. MESSAGE_CONTENT is privileged ([rate limits][discord-rl]) | [OpenClaw][oc-ext]. [Hermes][hm-voice] (including voice channels). [OpenBot][obt-tree] |
| [WhatsApp Cloud API][wa-pricing] | proprietary | Meta | Per-message pricing since 2025-07-01. Service replies charged after 1,000 free per number per month from 2026-10-01 | Official and reliable | General-purpose AI assistants barred since 2026-01-15 ([terms][wa-terms]). 24-hour window and templates | [Hermes][hm-wa] (`whatsapp_cloud`, labelled as the no-ban-risk path for businesses). [Rakazo][rkz-adapters] (`@chat-adapter/whatsapp`, which we believe is the Cloud API [INFERENCE]) |
| [Baileys][baileys] (WhatsApp Web) | MIT | self | free | Personal number. No template rules | Violates WhatsApp terms. Ban risk. v7 still a release candidate | [OpenClaw][oc-wa] ("production-ready via WhatsApp Web (Baileys)"). [Hermes][hm-wa] (with an explicit ban-risk warning) |
| [imsg][imsg] | MIT | user's Mac | free | JSON-RPC over stdio. No server, no port | Needs Full Disk Access and Automation. The private API needs SIP changes | [OpenClaw][oc-imsg] (the only supported iMessage path) |
| [BlueBubbles][bluebubbles] | Apache-2.0 | user's Mac | free | Full iMessage including groups | Last server release 2025-05 | [Hermes][hm-bb]. Removed from [OpenClaw][oc-bb] |
| [Sendblue][sendblue] | proprietary | cloud | Free shared number for verified contacts only. AI Agent $100/line/mo | Hosted iMessage with SMS/RCS fallback | Outbound to new contacts only on Enterprise | [Rakazo][rkz-adapters] (`chat-adapter-sendblue`). [Hermes][hm-sendblue] (community plugin) |
| [Photon / Spectrum][photon] | spectrum-ts MIT; service proprietary | both | Free (shared line, up to 10 users). Pro $25/mo. Business $250/line/mo | One SDK across iMessage, WhatsApp, Telegram and more | Young | [Hermes][hm-photon] (recommended free iMessage path, through a Node sidecar over gRPC) |
| [Apple Messages for Business][amb] | proprietary | through a Messaging Service Provider | Set by the MSP (unknown) | Official, verified brand | Business brands only; the user starts the chat. Not usable for personal agents | none found |
| [AgentMail][agentmail] | proprietary | cloud | Free: 3 inboxes, 3K emails/mo. Developer $20/mo | Inboxes built for agents, with websockets and MCP | Free tier adds a footer | [Hermes][hm-agentmail] (optional skill). Noodle ships an AgentMail [tool icon][ndl-tree] (MCP tool, not a channel) |
| [Postmark][postmark] | proprietary | cloud | Free 100 emails/mo. Basic $15/mo for 10K. Inbound processing from Pro ($16.50/mo) | Deliverability | Inbound requires the Pro tier | none found |
| [Resend][resend] | proprietary | cloud | Free 3K/mo. Pro $20/mo for 50K. [Inbound][resend-inbound] counts toward the quota | Modern API | Inbound and outbound share one quota | [OpenBot][obt-tree] marketplace plugin entry only. OpenBot's own auth email uses [SMTP][obt-email] |
| SMTP / IMAP directly | n/a | any | free | No vendor | Deliverability is your problem | [Rakazo][rkz-adapters] (nodemailer). [OpenClaw][oc-ext] (IMAP in) |
| [Twilio][twilio-sms] SMS and voice | proprietary | cloud | US $0.0083/segment plus carrier fees. 10DLC brand $4.50 to $46 plus $15 vetting ([10DLC][twilio-10dlc]) | Ubiquitous. Supports phone calls | A2P 10DLC registration takes days | [OpenClaw][oc-ext] (`sms`; `voice-call` covers Twilio, Telnyx and Plivo). [Hermes][hm-pyproject] (`sms`) |
| [Vapi][vapi] | proprietary | cloud | $0.05/min hosting plus pass-through. About $0.08 to $0.13/min in total (vendor calculator) | Fast phone-agent orchestration | Costs stack up | none found |
| Vercel [Chat SDK][chatsdk] (`chat` + `@chat-adapter/*`) | MIT | library | free | One TypeScript bot abstraction over Slack, Teams, Google Chat, Discord, WhatsApp and more | Adapter maturity varies | [Rakazo][rkz-adapters] (Slack, Telegram, WhatsApp, Lark, Sendblue) |
| Own mobile app as the channel | own | own | n/a | Full UX control, push, E2E | App Store overhead | [Grok Bot][gb-overview] (iOS/Android). [Lorca][lrc] (Expo). [OpenBot][obt] (Expo). [Aiden][adn-otg] (iOS/Android). [Noodle][ndl] (TestFlight). [OpenMausBot][omb] |
| X mentions | proprietary | X | included | Public task intake | Region-limited | [Grok Bot][gb-overview] (`@bot`) |

## 6. Voice

| Option | License | Hosting | Pricing (2026-10-20) | Strengths | Caveats | Used by |
| --- | --- | --- | --- | --- | --- | --- |
| [ElevenLabs][el-pricing] (TTS, Scribe v2 Realtime STT, Agents) | proprietary | cloud | TTS $0.08/1K chars ($0.04 Flash/Turbo). Scribe v2 Realtime $0.39/hr. [Agents][el-agents] $0.08/min | Best-known voices. Realtime STT | Highest price per character. OpenMausBot rejected ElevenLabs Agents because of a 15 s custom-LLM timeout ([voice-mode.md][omb-voice-dec]) | [OpenMausBot][omb-voice] (TTS). [Rakazo][rkz] (BYOK). [OpenBot][obt-scribe] (Scribe v2 Realtime dictation). [OpenClaw][oc-ext]. [Hermes][hm-pyproject] (`tts-premium`) |
| [OpenAI Realtime / GPT-Live][oai-live] | proprietary | cloud | gpt-realtime audio $32 in / $64 out per 1M tokens. GPT-Live $0.05/min with the backend model billed separately ([pricing][oai-pricing]) | Full duplex. Delegates the work to your agent. WebRTC, WebSocket and SIP | Two bills. US vendor lock-in | [OpenMausBot][omb-voice] (Live call mode, user's own key). [OpenClaw][oc-talk] (iOS WebRTC, Gateway relay, Android GPT-Live). [Rakazo][rkz] (OpenAI voice key) |
| [Gemini Live API][gemini-live] | proprietary | cloud | `gemini-3.8-live`: audio in $3 / out $12 per 1M tokens (about $0.005 / $0.018 per min) ([pricing][gemini-pricing]) | Cheapest native audio-to-audio | Free tier trains on your data | [Aiden][adn-gemini] ("Aiden Live", Gemini TTS) |
| [Deepgram][deepgram] | proprietary | cloud | Nova-3 streaming $0.0048/min. Flux $0.0065/min | Flux has built-in turn detection | Enterprise needed for self-host | [OpenClaw][oc-ext] |
| [Cartesia][cartesia] / [Fish Audio][fish] | proprietary | cloud | Cartesia Pro $5/mo. Fish $15 per 1M bytes | Low latency (Cartesia). Low price (Fish) | Credit-based pricing (Cartesia) | Rakazo (both, [README][rkz]). OpenMausBot (Fish, [docs][omb-voice]). OpenClaw (Fish, [extensions][oc-ext]) |
| [Parakeet TDT 0.6B v3][parakeet] via [sherpa-onnx][sherpa] | CC-BY-4.0 / Apache-2.0 | local | free | Fast, accurate, offline. Cross-platform via ONNX | European languages only. Attribution required | [OpenBot][obt-voice] (int8 ONNX, pinned revision). [Aiden][adn] (`sherpa-onnx-node`). [Hermes][hm-pyproject] (sherpa-onnx for wake word) |
| [Whisper][whisper] / [whisper.cpp][whispercpp] / faster-whisper | MIT | local | free | 99 languages. Metal support | Not natively streaming | [OpenBot][obt-voice] (Whisper turbo int8). [Hermes][hm-pyproject] (`faster-whisper`) |
| [Kokoro-82M][kokoro] / Piper / Chatterbox | Apache-2.0 / MIT | local | free | Free local TTS | Model downloads. Quality below cloud voices | OpenMausBot considered Kokoro and rejected it for simplicity, then added local Chatterbox ([decision doc][omb-voice-dec], [docs][omb-voice]). [Hermes][hm-pyproject] (Piper, KittenTTS, NeuTTS, Edge TTS) |
| Apple [SpeechAnalyzer][speechanalyzer] and [Foundation Models][fm] | OS SDK | on-device | free | Private, offline, no download for the user | Apple platforms only, macOS/iOS 26+ | [Noodle][ndl-voice] (voice messages need macOS 26 on-device transcription). [OpenMausBot][omb-voice] (macOS dictation and call mode). [OpenClaw][oc-talk] (native Talk). [Aiden][adn] (Foundation Models) |
| Undisclosed | proprietary | cloud | bundled | Voice chat and voice memos | Provider unknown | [Grok Bot][gb-chat] |

## 7. Desktop shells

| Option | License | Version (2026-10-20) | Strengths | Caveats | Chosen by (cited) and stated reasons |
| --- | --- | --- | --- | --- | --- |
| [Electron][electron] | MIT | v44.9.1 stable. New major every 8 weeks ([schedule][electron-sched]) | Biggest ecosystem. Same code on all three desktop OSes. Embeds Node for the harness | Bundle size and RAM. Native features need helpers | Grok Bot: Electron 42.1.0 (press / third-party reconstruction: [PROVENANCE.md][gb-electron]). [OpenMausBot][omb-pkg] ^43.5 (Swift helpers for macOS speech; Cua driver). [Rakazo][rkz-desktop] 44.9 (client of the web API). [OpenBot][obt-pkg] 44.7 (sandboxed renderer, measured RAM per process). [Aiden][adn] ^43.1 ("native-feeling", with Swift and Rust helpers). [Hermes][hm-desktop] 40.10 ("Native desktop shell"). The usual stated reason is reach to macOS, Windows and Linux from one TypeScript codebase that also hosts the agent harness [INFERENCE from READMEs] |
| [Tauri 2][tauri] | Apache-2.0 / MIT | v2.12.4; v3.0.0-alpha.5 published 2026-10-14 | Small binaries using the system webview. Rust core. Mobile targets | WebView differences across OSes. v3 migration coming | [OpenClaw][oc-linux] (Linux companion and backup Windows app; macOS is native). [Hermes][hm-tauri] (bootstrap installer only) |
| Native Swift / SwiftUI / AppKit | Apple toolchain | macOS 26 SDK | Direct access to Speech, Foundation Models, menu bar, Shortcuts and Spotlight. Smallest footprint | Apple only. Needs a second shell for Windows/Linux | [Kuvo Code][kuvo] ("SwiftUI and AppKit with Liquid Glass. No Electron."). [Noodle][ndl] ("Native and fast, taking advantage of all OS features" vs "HTML-based, not native"). [OpenClaw][oc-macos] (macOS menu-bar companion; native iOS/Android). [Lorca][lrc] (AppKit app now deprecated) |
| Go with MyGo native UI | own toolkit | MyGo 0.4.x | One native-drawn UI on three OSes. No webview | A niche toolkit maintained by the Lorca author | [Lorca][lrc-desktop] ("built to feel native on each system"; replaced its AppKit app) |
| [Electrobun][electrobun] | MIT | v2.0.4 (2026-10-18) | Bun plus Zig. System webview or bundled CEF. Tiny bsdiff updates (vendor claim) | The 2.0 line is two months old. Small ecosystem | none found |

Pattern across products [INFERENCE]: every product that scaled (OpenClaw, Hermes, Lorca, Kuvo) puts the agent in a headless process (Gateway, `hermes serve`, `lorca serve`, `opencode serve`) and treats each desktop or mobile UI as a client. That decoupling is what lets OpenClaw ship native Swift on macOS and Tauri on Linux, and lets Lorca swap AppKit for MyGo without touching the agent.

## Recommended defaults for Memoshi

All recommendations below are [INFERENCE], derived from the tables above.

| Area | Default | Why | Alternatives |
| --- | --- | --- | --- |
| Architecture | A headless local daemon that owns agents, memory, schedules and channels. Desktop, mobile and web are clients over a local WebSocket | This is how OpenClaw, Hermes, Lorca and Kuvo are built. It makes "always-on" a deployment choice (laptop, Mac mini, VPS) rather than a rewrite | Cloud-first like Grok Bot, which needs per-user VMs; see execution-environments.md |
| Connectors | Build MCP-client OAuth first (PKCE plus loopback). Offer Composio Sessions as the optional managed catalog, with labelled multi-account selection and triggers following OpenMausBot's design. Scope per bot with an allowlist of toolkits and account labels. Tokens never enter model context | Every OSS product ships its own MCP OAuth. Composio is the managed catalog actually used (3 products) and has the most generous free tier ($0 for 100K calls) | Pipedream Connect (now Workday) for breadth. Nango if self-host matters (ELv2). Avoid Smithery (shuts down 2026-10-31) and Zapier MCP (not multi-tenant) |
| Memory | Per-bot `MEMORY.md` plus `USER.md` with a hard load budget, topic files, daily log, credential redaction on write, and a visible editor with undo. Recall through SQLite FTS5 plus optional sqlite-vec. Define a provider interface for one optional external store | This is the convergent design across OpenClaw, Hermes, OpenMausBot, Lorca and Aiden. Readable files are a trust feature | Honcho for user modelling (AGPL). Supermemory or mem0 for hosted recall. Graphiti for a temporal graph if relationship queries matter |
| Scheduling | croner in the daemon, with jobs and run history persisted in SQLite, catch-up after sleep, an overlap guard and one-shot jobs. Add a hosted "wake and deliver" relay only for webhooks and app events | Matches OpenClaw, OpenMausBot, Aiden and Hermes. Durable-execution platforms are unused by every profiled product | Postgres-backed graphile-worker or DBOS if Memoshi adds a server tier. Cloudflare DO alarms or Workflows for a hosted always-on tier. Temporal is overkill at this stage |
| Remote access and sync | Own blind relay with sealed-box blobs (Lorca-style), plus APNs/FCM pushes the relay cannot read. Tailscale Serve as an opt-in power-user route; Funnel off | Gives E2E by construction and zero setup for normal users | WebRTC with own TURN (OpenBot) for media and remote desktop. A managed Cloudflare Tunnel (OpenMausBot). Use OpenMLS only once shared multi-user rooms need group E2E |
| Channels | First tier: Telegram and Slack (official, free). iMessage through `imsg` on the user's Mac, with Photon or Sendblue as hosted options. Email through a per-bot AgentMail inbox | Lowest risk and widest use among the profiled products | WhatsApp only through Baileys, opt-in and labelled with ban risk: the Cloud API bars general-purpose assistants since 2026-01-15. Twilio for SMS and phone calls once 10DLC is done |
| Voice | STT on-device by default: Apple SpeechAnalyzer on Apple platforms, Parakeet through sherpa-onnx elsewhere. TTS: system voices, then bring-your-own-key ElevenLabs, Cartesia or Fish. Live calls through OpenAI GPT-Live delegation so the agent stays the brain | Privacy by default at zero cost. GPT-Live's delegation matches the "agent is the product" stance OpenMausBot documents | Gemini Live (about 3 to 10 times cheaper per minute). Deepgram Flux for turn-taking. Twilio voice for phone numbers |
| Desktop shell | If Memoshi is Apple-first: SwiftUI on the daemon (Noodle, Kuvo). If cross-platform at launch: Electron for the main window plus small native helpers (OpenMausBot, Aiden) | Electron is the majority choice (6 of 10 including Grok Bot) and the fastest path to three OSes. Native Swift gets Speech, Foundation Models, Shortcuts and the menu bar for free | Tauri 2 (OpenClaw Linux), but expect a v3 migration. Electrobun is too young. MyGo is single-maintainer |

## Sources

Primary sources first; press and third-party sources are marked.

[gb-overview]: https://docs.x.ai/grok-bot/overview
[gb-computer]: https://docs.x.ai/grok-bot/computer-and-apps
[gb-skills]: https://docs.x.ai/grok-bot/skills-routines-and-automations
[gb-chat]: https://docs.x.ai/grok-bot/chat-and-collaboration
[gb-security]: https://docs.x.ai/grok-bot/security
[gb-teambots]: https://docs.x.ai/grok-bot/team-bots
[gb-electron]: https://github.com/b-nnett/grok-bot-0.18-reconstructed/blob/main/PROVENANCE.md
[omb]: https://github.com/milind-soni/OpenMausBot
[omb-composio]: https://github.com/milind-soni/OpenMausBot/blob/HEAD/docs/composio.md
[omb-broker]: https://github.com/milind-soni/OpenMausBot/blob/HEAD/cloudflare/composio-broker/wrangler.jsonc
[omb-mcpoauth]: https://github.com/milind-soni/OpenMausBot/blob/HEAD/server/mcp-oauth.ts
[omb-mem]: https://github.com/milind-soni/OpenMausBot/blob/HEAD/docs/memory.md
[omb-routines]: https://github.com/milind-soni/OpenMausBot/blob/HEAD/docs/routine-schedules.md
[omb-ts]: https://github.com/milind-soni/OpenMausBot/blob/HEAD/apps/docs/content/docs/self-hosting/networking.mdx
[omb-tunnel]: https://github.com/milind-soni/OpenMausBot/blob/HEAD/server/tunnel.ts
[omb-slack]: https://github.com/milind-soni/OpenMausBot/blob/HEAD/server/hosted-slack.ts
[omb-voice]: https://github.com/milind-soni/OpenMausBot/blob/HEAD/apps/docs/content/docs/features/voice-and-memory.mdx
[omb-voice-dec]: https://github.com/milind-soni/OpenMausBot/blob/HEAD/docs/voice-mode.md
[omb-pkg]: https://github.com/milind-soni/OpenMausBot/blob/HEAD/package.json
[rkz]: https://github.com/elie222/rakazo
[rkz-composio]: https://github.com/elie222/rakazo/blob/HEAD/packages/adapters/src/composio-connector.ts
[rkz-pd]: https://github.com/elie222/rakazo/blob/HEAD/packages/adapters/src/pipedream-connector.ts
[rkz-mcpoauth]: https://github.com/elie222/rakazo/blob/HEAD/packages/adapters/src/mcp-oauth.ts
[rkz-mem]: https://github.com/elie222/rakazo/blob/HEAD/packages/memory/src/index.ts
[rkz-honcho]: https://github.com/elie222/rakazo/blob/HEAD/packages/adapters/src/honcho-memory-provider.ts
[rkz-supermemory]: https://github.com/elie222/rakazo/blob/HEAD/packages/adapters/src/supermemory-memory-provider.ts
[rkz-cron]: https://github.com/elie222/rakazo/blob/HEAD/packages/core/src/cron.ts
[rkz-worker]: https://github.com/elie222/rakazo/blob/HEAD/apps/worker/src/index.ts
[rkz-adapters]: https://github.com/elie222/rakazo/blob/HEAD/packages/adapters/package.json
[rkz-desktop]: https://github.com/elie222/rakazo/blob/HEAD/apps/desktop/package.json
[ndl]: https://github.com/pdparchitect/noodle
[ndl-mcp]: https://github.com/pdparchitect/noodle/blob/HEAD/docs/mcp-connections.md
[ndl-mcpoauth]: https://github.com/pdparchitect/noodle/blob/HEAD/Sources/NoodleMCP/MCPOAuth.swift
[ndl-usage]: https://github.com/pdparchitect/noodle/blob/HEAD/docs/usage.md
[ndl-hub]: https://github.com/pdparchitect/noodle/blob/HEAD/Hub/README.md
[ndl-voice]: https://github.com/pdparchitect/noodle/blob/HEAD/docs/voice-messages.md
[ndl-pkg]: https://github.com/pdparchitect/noodle/blob/HEAD/Package.swift
[ndl-tree]: https://github.com/pdparchitect/noodle/tree/HEAD/Support/ToolIcons
[lrc]: https://github.com/egoist/lorca
[lrc-int]: https://github.com/egoist/lorca/blob/HEAD/docs/architecture/integrations.md
[lrc-channels]: https://github.com/egoist/lorca/blob/HEAD/docs/architecture/channels.md
[lrc-mem]: https://github.com/egoist/lorca/blob/HEAD/web/content/docs/memory.mdx
[lrc-triggers]: https://github.com/egoist/lorca/blob/HEAD/docs/architecture/routine-triggers.md
[lrc-relay]: https://github.com/egoist/lorca/blob/HEAD/crates/relay/README.md
[lrc-relaydoc]: https://github.com/egoist/lorca/blob/HEAD/docs/architecture/relay.md
[lrc-cargo]: https://github.com/egoist/lorca/blob/HEAD/crates/cli/Cargo.toml
[lrc-desktop]: https://github.com/egoist/lorca/blob/HEAD/docs/architecture/desktop-app.md
[obt]: https://github.com/nightly-labs/openbot
[obt-composio]: https://github.com/nightly-labs/openbot/blob/HEAD/marketplace/plugin-catalog/plugins/composio/plugin.json
[obt-mcpoauth]: https://github.com/nightly-labs/openbot/blob/HEAD/src/backend/mcp-oauth-provider.ts
[obt-mem]: https://github.com/nightly-labs/openbot/blob/HEAD/src/backend/memory-store.ts
[obt-sched]: https://github.com/nightly-labs/openbot/blob/HEAD/src/backend/agent/routine-scheduler.ts
[obt-webhooks]: https://github.com/nightly-labs/openbot/blob/HEAD/docs/webhooks.md
[obt-tree]: https://github.com/nightly-labs/openbot/tree/HEAD/apps
[obt-email]: https://github.com/nightly-labs/openbot/blob/HEAD/apps/auth-api/src/server/email-delivery.ts
[obt-voice]: https://github.com/nightly-labs/openbot/blob/HEAD/src/main/voice-model-service.ts
[obt-scribe]: https://github.com/nightly-labs/openbot/blob/HEAD/src/main/voice-cloud-stream.ts
[obt-pkg]: https://github.com/nightly-labs/openbot/blob/HEAD/package.json
[adn]: https://github.com/sambitcreate/aiden-agent
[adn-otg]: https://github.com/sambitcreate/aiden-agent/blob/HEAD/docs/aiden-on-the-go-remote-access.md
[adn-mem]: https://github.com/sambitcreate/aiden-agent/blob/HEAD/main/services/bot-memory/files.ts
[adn-mcpoauth]: https://github.com/sambitcreate/aiden-agent/blob/HEAD/main/services/mcp-oauth.ts
[adn-pkg]: https://github.com/sambitcreate/aiden-agent/blob/HEAD/package.json
[adn-gemini]: https://github.com/sambitcreate/aiden-agent/tree/HEAD/main/services/gemini-live
[kuvo]: https://github.com/serhatandic/kuvo-code
[oc]: https://github.com/openclaw/openclaw
[oc-ext]: https://github.com/openclaw/openclaw/tree/HEAD/extensions
[oc-mem]: https://github.com/openclaw/openclaw/blob/HEAD/docs/concepts/memory.md
[oc-mem-builtin]: https://github.com/openclaw/openclaw/blob/HEAD/docs/concepts/memory-builtin.md
[oc-honcho]: https://github.com/openclaw/openclaw/blob/HEAD/docs/concepts/memory-honcho.md
[oc-cron]: https://github.com/openclaw/openclaw/blob/HEAD/docs/automation/cron-jobs/how-it-works.md
[oc-gmail]: https://github.com/openclaw/openclaw/blob/HEAD/docs/automation/cron-jobs/gmail.md
[oc-ts]: https://github.com/openclaw/openclaw/blob/HEAD/docs/gateway/tailscale.md
[oc-remote]: https://github.com/openclaw/openclaw/blob/HEAD/docs/gateway/remote.md
[oc-mcp-reg]: https://github.com/openclaw/openclaw/blob/HEAD/docs/cli/mcp/registry.md
[oc-wa]: https://github.com/openclaw/openclaw/blob/HEAD/docs/channels/whatsapp.md
[oc-imsg]: https://github.com/openclaw/openclaw/blob/HEAD/docs/channels/imessage.md
[oc-bb]: https://github.com/openclaw/openclaw/blob/HEAD/docs/announcements/bluebubbles-imessage.md
[oc-talk]: https://github.com/openclaw/openclaw/blob/HEAD/docs/nodes/talk.md
[oc-linux]: https://github.com/openclaw/openclaw/blob/HEAD/docs/platforms/linux.md
[oc-macos]: https://github.com/openclaw/openclaw/blob/HEAD/docs/platforms/macos.md
[oc-convex]: https://github.com/openclaw/openclaw/tree/HEAD/qa/convex-credential-broker
[hm]: https://github.com/NousResearch/hermes-agent
[hm-pyproject]: https://github.com/NousResearch/hermes-agent/blob/HEAD/pyproject.toml
[hm-mem]: https://github.com/NousResearch/hermes-agent/blob/HEAD/website/docs/user-guide/features/memory.md
[hm-memprov]: https://github.com/NousResearch/hermes-agent/blob/HEAD/website/docs/user-guide/features/memory-providers.md
[hm-cognee]: https://github.com/NousResearch/hermes-agent/blob/HEAD/plugin-catalog/cognee.yaml
[hm-cron]: https://github.com/NousResearch/hermes-agent/blob/HEAD/website/docs/user-guide/features/cron.md
[hm-mcp]: https://github.com/NousResearch/hermes-agent/blob/HEAD/website/docs/user-guide/features/mcp.md
[hm-email]: https://github.com/NousResearch/hermes-agent/tree/HEAD/plugins/platforms/email
[hm-wa]: https://github.com/NousResearch/hermes-agent/blob/HEAD/website/docs/user-guide/messaging/whatsapp.md
[hm-bb]: https://github.com/NousResearch/hermes-agent/blob/HEAD/website/docs/user-guide/messaging/bluebubbles.md
[hm-photon]: https://github.com/NousResearch/hermes-agent/blob/HEAD/plugins/platforms/photon/README.md
[hm-sendblue]: https://github.com/NousResearch/hermes-agent/blob/HEAD/plugin-catalog/sendblue.yaml
[hm-agentmail]: https://github.com/NousResearch/hermes-agent/tree/HEAD/optional-skills/email/agentmail
[hm-voice]: https://github.com/NousResearch/hermes-agent/blob/HEAD/website/docs/user-guide/features/voice-mode.md
[hm-desktop]: https://github.com/NousResearch/hermes-agent/blob/HEAD/website/docs/user-guide/desktop.md
[hm-tauri]: https://github.com/NousResearch/hermes-agent/blob/HEAD/apps/bootstrap-installer/src-tauri/tauri.conf.json
[composio]: https://github.com/ComposioHQ/composio
[composio-pricing]: https://composio.dev/pricing
[composio-sessions]: https://docs.composio.dev/docs/configuring-sessions
[pd-pricing]: https://pipedream.com/pricing
[pd-oauth]: https://pipedream.com/docs/connect/managed-auth/oauth-clients
[wday]: https://www.sec.gov/Archives/edgar/data/1327811/000132781126000010/wday-01312026x991.htm
[arcade-pricing]: https://www.arcade.dev/pricing
[arcade-auth]: https://docs.arcade.dev/en/references/auth-providers/google
[arcade-smithery]: https://www.arcade.dev/blog/smithery-joins-arcade/
[nango]: https://github.com/NangoHQ/nango
[nango-pricing]: https://www.nango.dev/pricing
[paragon]: https://www.useparagon.com/pricing
[paragon-docs]: https://docs.useparagon.com/learn/actionkit
[zapier-mcp]: https://zapier.com/mcp
[zapier-conn]: https://docs.zapier.com/mcp/overview/how-connections-work
[mcp-registry]: https://registry.modelcontextprotocol.io/
[mcp-registry-gh]: https://github.com/modelcontextprotocol/registry
[smithery-future]: https://smithery.ai/future
[letta]: https://github.com/letta-ai/letta
[letta-pricing]: https://docs.letta.com/pricing
[mem0]: https://github.com/mem0ai/mem0
[mem0-pricing]: https://mem0.ai/pricing
[zep-pricing]: https://www.getzep.com/pricing
[zep-repo]: https://github.com/getzep/zep
[graphiti]: https://github.com/getzep/graphiti
[supermemory]: https://github.com/supermemoryai/supermemory
[supermemory-pricing]: https://supermemory.ai/pricing
[honcho]: https://github.com/plastic-labs/honcho
[honcho-site]: https://honcho.dev
[cognee]: https://github.com/topoteretes/cognee
[cognee-pricing]: https://www.cognee.ai/pricing
[langmem]: https://github.com/langchain-ai/langmem
[basicmem]: https://github.com/basicmachines-co/basic-memory
[basicmem-pricing]: https://basicmemory.com/pricing
[croner]: https://github.com/Hexagon/croner
[croniter]: https://pypi.org/project/croniter/
[graphile]: https://github.com/graphile/worker
[temporal]: https://github.com/temporalio/temporal
[temporal-pricing]: https://temporal.io/pricing
[inngest]: https://github.com/inngest/inngest
[inngest-pricing]: https://www.inngest.com/pricing
[triggerdev]: https://github.com/triggerdotdev/trigger.dev
[triggerdev-pricing]: https://trigger.dev/pricing
[restate]: https://github.com/restatedev/restate
[restate-pricing]: https://restate.dev/pricing
[dbos]: https://github.com/dbos-inc/dbos-transact-py
[dbos-pricing]: https://www.dbos.dev/dbos-pricing
[cf-agents]: https://developers.cloudflare.com/agents/
[cf-do]: https://developers.cloudflare.com/durable-objects/platform/pricing/
[cf-wf]: https://developers.cloudflare.com/workflows/reference/pricing/
[convex]: https://docs.convex.dev/scheduling
[convex-pricing]: https://www.convex.dev/pricing
[ts-pricing]: https://tailscale.com/pricing
[ts-funnel]: https://tailscale.com/kb/1223/funnel
[tsnet]: https://tailscale.com/kb/1244/tsnet
[cf-tunnel]: https://developers.cloudflare.com/tunnel/
[ngrok]: https://ngrok.com/pricing
[electric]: https://github.com/electric-sql/electric
[electric-pricing]: https://electric-sql.com/pricing
[zero]: https://zero.rocicorp.dev
[instant]: https://www.instantdb.com/docs/self-hosting
[instant-openai]: https://www.instantdb.com/essays/instant_team_joins_openai
[jazz]: https://github.com/garden-co/jazz
[automerge]: https://github.com/automerge/automerge
[yjs]: https://github.com/yjs/yjs
[triplit]: https://github.com/aspen-cloud/triplit
[triplit-supabase]: https://supabase.com/blog/triplit-joins-supabase
[libsignal]: https://github.com/signalapp/libsignal
[openmls]: https://github.com/openmls/openmls
[rfc9420]: https://www.rfc-editor.org/rfc/rfc9420
[libsodium]: https://github.com/jedisct1/libsodium
[age]: https://github.com/FiloSottile/age
[synapse]: https://github.com/element-hq/synapse
[matrix-rust]: https://github.com/matrix-org/matrix-rust-sdk
[vodozemac]: https://github.com/matrix-org/vodozemac
[element-pricing]: https://element.io/pricing
[livekit]: https://livekit.io/pricing
[tg-changelog]: https://core.telegram.org/bots/api-changelog
[tg-faq]: https://core.telegram.org/bots/faq
[slack-ai]: https://docs.slack.dev/ai/
[slack-rl]: https://docs.slack.dev/changelog/2025/05/29/rate-limit-changes-for-non-marketplace-apps
[discord-rl]: https://github.com/discord/discord-api-docs/blob/main/developers/topics/rate-limits.mdx
[wa-pricing]: https://developers.facebook.com/docs/whatsapp/pricing
[wa-terms]: https://www.whatsapp.com/legal/business-solution-terms
[wa-tc]: https://techcrunch.com/2025/10/18/whatssapp-changes-its-terms-to-bar-general-purpose-chatbots-from-its-platform
[baileys]: https://github.com/WhiskeySockets/Baileys
[imsg]: https://github.com/openclaw/imsg
[bluebubbles]: https://github.com/BlueBubblesApp/bluebubbles-server
[sendblue]: https://www.sendblue.com/pricing
[photon]: https://photon.codes/pricing
[amb]: https://register.apple.com/resources/messages/messaging-documentation/
[agentmail]: https://www.agentmail.to/pricing
[postmark]: https://postmarkapp.com/pricing
[resend]: https://resend.com/pricing
[resend-inbound]: https://resend.com/features/inbound
[twilio-sms]: https://www.twilio.com/en-us/sms/pricing/us
[twilio-10dlc]: https://support.twilio.com/hc/en-us/articles/1260803965530
[vapi]: https://vapi.ai/pricing
[chatsdk]: https://chat-sdk.dev/docs
[el-pricing]: https://elevenlabs.io/pricing/api
[el-agents]: https://elevenlabs.io/pricing/agents
[oai-live]: https://developers.openai.com/api/docs/guides/live
[oai-pricing]: https://developers.openai.com/api/docs/pricing
[gemini-live]: https://ai.google.dev/gemini-api/docs/live
[gemini-pricing]: https://ai.google.dev/gemini-api/docs/pricing
[deepgram]: https://deepgram.com/pricing
[cartesia]: https://cartesia.ai/pricing
[fish]: https://fish.audio/developers/
[parakeet]: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
[sherpa]: https://github.com/k2-fsa/sherpa-onnx
[whisper]: https://github.com/openai/whisper
[whispercpp]: https://github.com/ggml-org/whisper.cpp
[kokoro]: https://huggingface.co/hexgrad/Kokoro-82M
[speechanalyzer]: https://developer.apple.com/documentation/speech/speechanalyzer
[fm]: https://developer.apple.com/documentation/foundationmodels
[electron]: https://github.com/electron/electron/releases
[electron-sched]: https://releases.electronjs.org/schedule
[tauri]: https://github.com/tauri-apps/tauri/releases
[electrobun]: https://github.com/blackboardsh/electrobun

1. Profiled product repositories and docs, read through the GitHub API on 2026-10-20: [OpenMausBot][omb], [Rakazo][rkz], [Noodle][ndl], [Lorca][lrc], [OpenBot][obt], [Aiden Agent][adn], [Kuvo Code][kuvo], [OpenClaw][oc], [Hermes Agent][hm]. Grok Bot docs: [overview][gb-overview], [computer and apps][gb-computer], [routines][gb-skills], [security][gb-security], [team bots][gb-teambots].
2. Vendor pricing and docs pages linked in each table row, fetched 2026-10-20.
3. Third-party: [Grok Bot 0.18 reconstruction PROVENANCE.md][gb-electron] (Electron version only). Press: [TechCrunch on the WhatsApp AI-provider ban][wa-tc].
