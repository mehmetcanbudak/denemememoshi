# Agent harnesses: the engine layer Memoshi could embed or drive

Research date: 2026-10-20. All GitHub figures are from the authenticated `gh api` as of 2026-10-20. Contributor counts come from the `contributors?anon=1` pagination header; the API caps large repos, so read them as lower bounds. Vendor claims we could not check in code or docs are marked "(vendor claim)", our own reasoning is marked [INFERENCE], and things we searched for without finding are marked "unknown".

## 1. Summary table

| Harness | License | Lang | Embedding modes | Session resume | Permission hook | MCP | Subagents | Auth (subscription?) | Cadence (as of 2026-10-20) | Profiled users |
|---|---|---|---|---|---|---|---|---|---|---|
| [Pi](#pi) | MIT | TS | In-process SDK; RPC (JSONL stdio); JSON print mode; ACP via 3rd-party adapter | Yes (session files, fork) | `tool_call` extension event (no built-in policy) | Yes (built-in extension, own client) | Not built-in (extensions) | API keys (~30) + OAuth incl. Claude Pro/Max, ChatGPT, Copilot, SuperGrok, Meta | v1.3.0 on 2026-10-15; 20 releases since 2026-08-14 | OpenClaw, Aiden |
| [OpenCode](#opencode) | MIT | TS | HTTP server (OpenAPI 3.1 + SSE); V2 in-process `@opencode/sdk`; ACP | Yes (create/fork/revert/children) | HTTP permission reply; plugin `ctx.permission.assert` | Yes (dynamic add over HTTP) | Yes (child sessions) | API keys, ChatGPT Plus, Copilot, GitLab Duo; Claude OAuth removed | V2 v2.1.0 on 2026-10-20 (breaking); V1 v1.19.3 | Kuvo Code |
| [Codex](#codex) | Apache-2.0 | Rust | app-server JSON-RPC (stdio; ws/unix experimental); `codex exec --json`; TS SDK | Yes (threads: resume/fork/archive) | Server-to-client approval requests | Yes | Yes | ChatGPT sign-in, API key, Bedrock; SIWC tokens | Stable rust-v0.163.0 on 2026-10-15; several alphas/day | OpenMausBot, OpenBot, Noodle (drive CLI) |
| [Claude Code + Agent SDK](#claude-code-and-claude-agent-sdk) | Proprietary (SDK: Commercial Terms; Py wrapper MIT) | TS | SDK (TS/Py) that runs the CLI binary; `claude -p` stream-json; ACP via adapter | Yes (resume/fork) | `canUseTool` callback + hooks + modes | Yes (incl. in-process SDK servers) | Yes | API key, Bedrock/Vertex/Foundry; Claude plan OAuth only in the unmodified binary | v2.1.304 on 2026-10-19 (daily) | OpenMausBot, OpenBot, Noodle (drive CLI) |
| [Grok Build](#grok-build) | Source Apache-2.0; distributed binary listed as proprietary | Rust | Headless `-p` streaming-json; ACP `grok agent stdio` | Yes (`--resume`, `--session-id`) | `--always-approve`; hooks; permissions | Yes | Yes | SuperGrok / X Premium+ OAuth, device code, `XAI_API_KEY`, SSO | npm 1.0.64; source synced from monorepo, last 2026-09-29 | OpenMausBot, OpenBot, Noodle (drive CLI) |
| [Gemini CLI](#gemini-cli) | Apache-2.0 | TS | ACP `--acp`; headless stream-json; in-process `@google/gemini-cli-sdk`; A2A server pkg | Yes | Hooks; ACP permission | Yes | Yes | Code Assist Std/Ent, Gemini/Vertex API keys (consumer login ended 2026-06-18) | v0.64.0 on 2026-10-13; daily nightlies | none found |
| [Cursor CLI](#cursor-cli) | Proprietary | unknown | Headless `-p` stream-json; ACP `agent acp` | Yes (`session/load`) | ACP `session/request_permission`; auto-review | Yes (OAuth) | unknown | Cursor login, `CURSOR_API_KEY`, BYO Bedrock | Dated builds about weekly (v2026.10.08) | none found |
| [Cline](#cline) | Apache-2.0 | TS | CLI `--json` NDJSON; `--acp`; in-process `@cline/sdk` | Yes | SDK plugins/hooks; approvals; `--yolo` | Yes | unknown | Cline account, ChatGPT subscription OAuth, OCA, many API keys | cli-v3.0.73 / sdk v0.0.95 on 2026-10-17 | none found |
| [GitHub Copilot CLI + SDK](#github-copilot-cli-and-sdk) | CLI proprietary (redistributable unmodified); SDK MIT | CLI unknown; SDK 6 langs | SDK to CLI server over JSON-RPC; ACP `--acp` (stdio/TCP) | Yes | SDK permission handler; hooks | Yes | Custom agents | GitHub OAuth/tokens, BYOK | CLI v1.0.100 on 2026-10-19 | none found |
| [Meta Muse Code](#meta-muse-code) | Proprietary CLI; SDK repo MIT | unknown (native binary) | `muse exec --json` JSONL; `muse serve` versioned session protocol; TS SDK | Yes | Approvals, sandbox, hooks | Yes (OAuth 2.1) | Yes (+ observers) | Meta browser sign-in or `META_API_KEY`; subscription only via the Muse CLI | Beta since 2026-08-05 (press) | none found |
| [Vercel fx](#vercel-fx) | Apache-2.0 | Zig | `fx ask --json`; `fx acp`; in-process libfx (Node addon + WASM) | Yes (`-c`, `--resume`) | Modes: auto (model-checked), ask, full-access | Yes | Yes | Vercel AI Gateway, ChatGPT sub, Grok sub, OpenAI-compatible | v0.0.14 on 2026-10-16; 14 releases since 2026-08-17 | none found |
| [Google Antigravity](#google-antigravity) | Proprietary CLI/ACP server; Python SDK Apache-2.0 | Go (CLI), Python SDK | Headless `agy -p` stream-json; ACP server; Python SDK | Yes | SDK policies + human-in-the-loop | Yes | Yes | Google account (AI Pro/Ultra), Gemini API key, Vertex | CLI 1.4.3 on 2026-10-20 | none found |
| [Goose](#goose) | Apache-2.0 | Rust | `goose acp` stdio; `goose serve` (ACP over HTTP/WebSocket); Rust SDK | Yes (native); not for ACP providers | Tool permissions | MCP-native extensions | Yes | 15+ providers + Claude/ChatGPT/Pi/Amp via ACP providers | v1.55.0 on 2026-10-16; about weekly | none found (reference for BYO-agent) |

## 2. Harness profiles

### Pi

- Identity: the repo `badlogic/pi-mono` now redirects to [earendil-works/pi](https://github.com/earendil-works/pi). MIT, TypeScript. 116,531 stars, 14,869 forks, at least 300 contributors. v1.0.0 shipped [2026-10-01](https://github.com/earendil-works/pi/releases/tag/v1.0.0) and v1.3.0 on 2026-10-15; 20 releases between 2026-08-14 and 2026-10-15.
- Packages ([README](https://raw.githubusercontent.com/earendil-works/pi/main/README.md)): `pi-ai` (unified multi-provider LLM API), `pi-agent-core` (agent runtime with tool calling and state), `pi-coding-agent` (CLI + SDK), `pi-durable` ("durable conversation, task, and document runtime"), `pi-mcp`, `chord` (plugin host runtime), `pi-tui`. The README points to OpenClaw as "a real-world integration" and to [pi-chat](https://github.com/earendil-works/pi-chat) for Slack/chat automation.
- Related Earendil packages (npm, checked 2026-10-20): `pi-codemode` and `pi-env` (an SSH-deployed daemon for remote execution) ship at 1.3.0 with the rest. [Gondolin](https://github.com/earendil-works/gondolin) (Apache-2.0) is Earendil's Linux micro-VM sandbox and includes a Pi extension. `pi-server` ("experimental server package for pi"), `pi-client` and `pi-protocol` (a CBOR protocol for remote Pi sessions) stopped at 1.1.0 on 2026-10-07 and are not in the repo's [`packages/`](https://github.com/earendil-works/pi/tree/main/packages) directory. Treat them as inactive [INFERENCE].
- Embedding: the [SDK](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/sdk.md) runs in-process (`createAgentSession()`, `session.prompt()`, `session.subscribe()`, `SessionManager.inMemory()` or file-backed, fork/continue). [RPC mode](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc.md) runs `pi --mode rpc` as JSONL commands/responses/events over stdio. There is also a print/JSON mode.
- Streaming schema ([json.md](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/json.md)): `agent_start/agent_end/agent_settled`, `turn_start/turn_end`, `message_start/message_update/message_end`. `message_update` carries `text_delta`, `thinking_delta`, `toolcall_start/delta/end`, and there are `tool_execution_start/update/end` events. Wire updates carry deltas only.
- Permissions: "Pi does not include a built-in permission system" ([README](https://raw.githubusercontent.com/earendil-works/pi/main/README.md)). Pi has blocking hooks, not a policy:
  - the coding agent's [`tool_call` extension event](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md) can mutate or block a call, fails closed if the handler throws, and ships with a `permission-gate.ts` example;
  - `pi-agent-core` has a blocking `beforeToolCall` ([README](https://github.com/earendil-works/pi/tree/main/packages/agent));
  - Pi Durable has `beforeTool` (block or rewrite arguments) and `afterTool` (replace the result). Both run for nested calls made from Code Mode scripts or MCP bridges, which carry `call.parent`, so a host guard covers scripts too ([pi-durable README](https://github.com/earendil-works/pi/blob/main/packages/durable/README.md)).
- Extensions: TypeScript modules running in-process that register tools, commands, providers, MCP servers (`pi.registerMcpServer`), session hooks, and UI. Subagents and plan mode are intentionally left out ("Ask Pi to build what you want, or install a package").
- MCP: its own [pi-mcp](https://github.com/earendil-works/pi/blob/main/packages/mcp/README.md) client speaks protocol `2025-11-25` with OAuth. The current spec is `2026-07-28` (see section 3), so this is a version gap.
- Providers/auth ([providers.md](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/providers.md)): about 30 API-key providers, plus OAuth modules for [Anthropic "Claude Pro/Max"](https://github.com/earendil-works/pi/blob/main/packages/ai/src/auth/oauth/anthropic.ts), OpenAI ChatGPT/Codex, GitHub Copilot, [xAI "Sign in with SuperGrok or X Premium"](https://github.com/earendil-works/pi/blob/main/packages/ai/src/auth/oauth/xai.ts), and [Meta](https://github.com/earendil-works/pi/blob/main/packages/ai/src/auth/oauth/meta.ts) (source comment: "Muse Code CLI client id"), plus Kimi, OpenRouter, and Radius. The Anthropic flow requests the `user:sessions:claude_code` scope. These subscription paths conflict with the Anthropic and Meta policy text in section 4 [INFERENCE].
- ACP: only through the third-party [pi-acp](https://github.com/svkozak/pi-acp) adapter (MIT, listed in the ACP registry).
- Users: OpenClaw ([README](https://raw.githubusercontent.com/earendil-works/pi/main/README.md)), [Aiden Agent](https://github.com/sambitcreate/aiden-agent).

### OpenCode

- [anomalyco/opencode](https://github.com/anomalyco/opencode) (`sst/opencode` redirects here). MIT, TypeScript. 218,166 stars, 29,147 forks, at least 1,060 contributors. Two release lines run in parallel. V1 GitHub releases reached v1.19.3 on 2026-10-16. V2 started with tag v2.0.0 on 2026-09-11 and reached [v2.1.0 on 2026-10-20](https://github.com/anomalyco/opencode/blob/dev/CHANGELOG.md), which made "intentional changes to public SDK, HTTP message/event, and plugin contracts". V2 binaries are not yet on GitHub Releases ([#57058](https://github.com/anomalyco/opencode/issues)).
- HTTP server ([docs](https://opencode.ai/docs/server)): `opencode serve` (default 127.0.0.1:4096, optional basic auth) publishes an OpenAPI 3.1 spec at `/doc` and an SSE event bus at `/event` and `/global/event`. Session endpoints cover create/list/fork/abort/revert/summarize/diff/children, `prompt_async`, and `POST /session/:id/permissions/:permissionID`. MCP servers can be added at runtime with `POST /mcp`. Provider OAuth endpoints are exposed too. The TUI itself is a client of this server.
- In-process (V2): the [`@opencode/sdk` README](https://github.com/anomalyco/opencode/blob/dev/packages/sdk/README.md) says it "executes Server's assembled HTTP router in memory, opening no listener". It supports `database: { path }` and per-session plugin `instances` keyed on session metadata (the README's example is a Slack thread). This fits a multi-bot host well [INFERENCE].
- ACP: `opencode acp` ([docs](https://github.com/anomalyco/opencode/blob/dev/packages/web/src/content/docs/acp.mdx)); listed in the ACP registry.
- Permissions: the HTTP permission reply above; V2.0.29 added `ctx.permission.assert` for plugins, and V2.0.30 exposes MCP tool input to permission hooks ([CHANGELOG](https://github.com/anomalyco/opencode/blob/dev/CHANGELOG.md)).
- Subagents: child sessions (`/session/:id/children`); the changelog counts subagent cost.
- Auth: [providers doc](https://github.com/anomalyco/opencode/blob/dev/packages/web/src/content/docs/providers.mdx): "There are plugins that allow you to use your Claude Pro/Max models with OpenCode. Anthropic explicitly prohibits this. Previous versions of OpenCode came bundled with these plugins but that is no longer the case as of 1.3.0" (v1.3.0 shipped 2026-03-22). The same doc offers "zero setup" for ChatGPT Plus, GitHub Copilot, and GitLab Duo. Third-party plugins that restore Claude OAuth exist ([opencode-claude-auth](https://www.npmjs.com/package/opencode-claude-auth), third-party).
- User: [Kuvo Code](https://github.com/serhatandic/kuvo-code) runs unmodified opencode.

### Codex

- [openai/codex](https://github.com/openai/codex). Apache-2.0, Rust. 130,001 stars, at least 675 contributors. Latest stable is rust-v0.163.0 (2026-10-15); rust-v0.164.0-alpha.1 through alpha.6 shipped 2026-10-16 to 2026-10-19.
- [app-server](https://learn.chatgpt.com/docs/app-server.md) "is the interface Codex uses to power rich clients". It speaks bidirectional JSON-RPC 2.0 over stdio JSONL by default. WebSocket and Unix-socket transports are "experimental and unsupported", with capability-token or signed-bearer auth. `codex app-server generate-ts` and `generate-json-schema` emit typed schemas.
- Primitives: `thread/start|resume|fork|read|list|archive|delete|revert`, `turn/start|steer|interrupt`, and `review`. Notifications `item/started` and `item/completed` are authoritative, with item deltas in between. Item types include `agentMessage`, `commandExecution`, `fileChange`, `plan`, `mcpToolCall`, `dynamicToolCall`, and `contextCompaction`. Threads persist and can be listed without loading them.
- Approvals: server-to-client requests such as `item/commandExecution/requestApproval`, file-change approvals, and `item/permissions/requestApproval` for network/filesystem grants ([docs](https://learn.chatgpt.com/docs/app-server.md)). Custom tools: experimental `dynamicTools` on `thread/start` are executed by the client and persisted with the thread.
- Other modes: `codex exec` for CI/headless, and the TypeScript [`@openai/codex-sdk`](https://learn.chatgpt.com/docs/codex-sdk.md) (`startThread`, `run`, `resumeThread`). "The `codex mcp-server` command ... have been removed. Use the Codex app server."
- MCP client: yes, including MCP OAuth login and a `mcp_2026_07_28` feature flag ([app-server README](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)). Subagents: [documented](https://learn.chatgpt.com/docs/agent-configuration/subagents.md).
- Auth ([docs](https://learn.chatgpt.com/docs/auth.md)): ChatGPT sign-in, API key, Amazon Bedrock. Open-source apps can pass Sign-in-with-ChatGPT plan tokens into app-server ([SIWC: Codex app-server](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server.md)).
- ACP: only through the [codex-acp](https://github.com/agentclientprotocol/codex-acp) adapter (ACP org, 472 stars).

### Claude Code and Claude Agent SDK

- [anthropics/claude-code](https://github.com/anthropics/claude-code) (152,807 stars) is proprietary: "© Anthropic PBC. All rights reserved. Use is subject to Anthropic's Commercial Terms of Service" ([LICENSE.md](https://github.com/anthropics/claude-code/blob/main/LICENSE.md)). It ships about daily: v2.1.283 on 2026-09-25 through v2.1.304 on 2026-10-19.
- The Agent SDK is "A library that runs the Claude Code binary" ([overview](https://code.claude.com/docs/en/agent-sdk/overview)). So the in-process API spawns a subprocess underneath. TS [v0.3.304](https://github.com/anthropics/claude-agent-sdk-typescript) has no OSS license file. The Python wrapper [v0.2.168](https://github.com/anthropics/claude-agent-sdk-python) is MIT (8,303 stars). SDK use "is governed by Anthropic's Commercial Terms of Service".
- Capabilities ([overview](https://code.claude.com/docs/en/agent-sdk/overview)): built-in tools, hooks, subagents, MCP, permissions, sessions ("resume or fork later"), skills, commands, memory, and plugins.
- Permission flow ([docs](https://code.claude.com/docs/en/agent-sdk/permissions)): hooks run first, then `deny` rules, then permission mode (`plan`, `bypassPermissions`, ...), then `allow`/`ask` rules, then the `canUseTool` callback. Deny rules hold even in `bypassPermissions`.
- Subprocess protocol ([headless](https://code.claude.com/docs/en/headless)): `claude -p --output-format stream-json --verbose --include-partial-messages` for token-level NDJSON, `--input-format stream-json` for streaming input, `--continue`/`--resume`. JSON output reports `total_cost_usd`.
- Providers: Anthropic API, Amazon Bedrock, Google Cloud Agent Platform, Microsoft Foundry ([legal](https://code.claude.com/docs/en/legal-and-compliance)).
- ACP: through [claude-agent-acp](https://github.com/agentclientprotocol/claude-agent-acp) (formerly `zed-industries/claude-code-acp`), Apache-2.0, v0.94.0 on 2026-10-19; listed as "Claude Agent" in the registry.
- Branding rule: the product cannot call itself "Claude Code"; "{YourAgentName} Powered by Claude" is allowed ([overview](https://code.claude.com/docs/en/agent-sdk/overview)).

### Grok Build

- [xai-org/grok-build](https://github.com/xai-org/grok-build): Rust, 27,460 stars, created 2026-07-14. The README says "First-party code ... Apache License, Version 2.0". It is "synced periodically from the SpaceXAI monorepo"; "External contributions are not accepted". It includes "in-tree source ports (including openai/codex and sst/opencode tool implementations)". The ACP registry entry lists the distributed npm package `@xai-official/grok@1.0.64` as `"license": "proprietary"` ([registry](https://github.com/agentclientprotocol/registry/blob/main/grok-build/agent.json)). The last sync commit is dated 2026-09-29.
- Launch: [x.ai/news/grok-build-cli](https://x.ai/news/grok-build-cli), "early beta for all SuperGrok and X Premium Plus subscribers". The [overview](https://docs.x.ai/build/overview) says it is usable "via an interactive TUI, headlessly in scripts or bots, or through the Agent Client Protocol (ACP) in other apps."
- Headless ([docs](https://docs.x.ai/build/cli/headless-scripting)): `grok -p` with `--output-format plain|json|streaming-json`, `-s/--session-id`, `-r/--resume`, `-c/--continue`, `--always-approve`, `--no-auto-update`. Sessions live in `~/.grok/sessions`.
- ACP: `grok agent stdio`. Its `session/update` streams `agent_message_chunk`.
- Features (user guide [file list](https://github.com/xai-org/grok-build/tree/main/crates/codegen/xai-grok-pager/docs/user-guide)): MCP servers, skills, plugins, hooks, subagents, sessions, sandbox, plan mode, background tasks, permissions-and-safety, custom models (any `base_url` + `env_key` in `~/.grok/config.toml`).
- Auth ([guide](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/02-authentication.md)): browser OAuth at `auth.x.ai` (default), `--device-auth`, enterprise SSO, `XAI_API_KEY`. Tokens are kept in `~/.grok/auth.json` (0600).
- Users: OpenMausBot, OpenBot, and Noodle drive the CLI (per sibling profiles).

### Gemini CLI

- [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli): Apache-2.0, TypeScript. 107,457 stars, at least 700 contributors. v0.64.0 on 2026-10-13, plus daily nightlies.
- Major 2026 change: "On June 18, 2026, Gemini CLI and Gemini Code Assist IDE extensions will stop serving requests for Google AI Pro and Ultra, as well as those using it free of charge" ([Google Developers Blog, 2026-05-19](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli)). It stays available for Code Assist Standard/Enterprise and "via paid Gemini and Gemini Enterprise Agent Platform API keys".
- Embedding: `gemini --acp` ([acp-mode.md](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/acp-mode.md)); headless stream-json ([headless.md](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/headless.md)); the in-process [`@google/gemini-cli-sdk`](https://github.com/google-gemini/gemini-cli/blob/main/packages/sdk/README.md) (`GeminiCliAgent.sendStream`). The repo also ships an `a2a-server` package.
- Features: hooks, subagents, checkpointing, session management (docs tree). MCP: yes.
- Auth ([ToS page](https://geminicli.com/docs/resources/tos-privacy/)): Google account (Code Assist), Gemini API key, Vertex AI.
- Assessment: the Google-backed consumer path has moved to Antigravity. Gemini CLI is now an enterprise/API-key engine [INFERENCE].

### Cursor CLI

- Proprietary. The binary is `agent`, installed with `curl https://cursor.com/install`. Builds are versioned by date, about weekly: v2026.09.15, 09.22, 09.28, 10.08 ([changelog](https://cursor.com/docs/cli/changelog)).
- Headless: `agent -p` with `--output-format text|json|stream-json`; `--force`/`--yolo` to apply edits ([headless](https://cursor.com/docs/cli/headless)). The changelog adds per-turn token totals and `request_id` to stream-json, and says "headless transcripts write Claude Code-compatible JSONL" (via search snippet of the [changelog](https://cursor.com/docs/cli/changelog)).
- ACP ([docs](https://cursor.com/docs/cli/acp)): `agent acp` speaks JSON-RPC 2.0 over stdio. The flow is `initialize`, `authenticate` (`cursor_login`), `session/new` or `session/load` (resume), `session/prompt`, `session/update`, `session/request_permission`, `session/cancel`. Since v2026.10.08, ACP clients "get wakeups from watched background shells".
- Auth: `agent login`, `CURSOR_API_KEY`, `CURSOR_AUTH_TOKEN`. Models include Claude Opus/Sonnet 5.5 (also via BYO Bedrock), Grok 4.7, and Composer ([changelog](https://cursor.com/docs/cli/changelog)).
- Extras: MCP with OAuth, skills, self-hosted workers, Cloud Agents. Subagents: unknown. Ownership: "SpaceX Buys Cursor for $60B" (press, [tech-insider](https://tech-insider.org/ie/claude-code-agent-pricing-split-2026/) related-links, unverified).

### Cline

- [cline/cline](https://github.com/cline/cline): Apache-2.0, TypeScript. 70,586 stars, at least 347 contributors. One repo ships the VS Code/JetBrains extension, CLI, desktop app, and SDK ([README](https://github.com/cline/cline)). cli-v3.0.73, sdk v0.0.95, and desktop-v0.0.48 all shipped 2026-10-17, so cadence is near-daily.
- CLI ([apps/cli/README](https://github.com/cline/cline/blob/main/apps/cli/README.md)): `cline --json` streams NDJSON (`agent_event`); `--yolo` skips approvals. ACP via `--acp` ([apps/cli/src/acp](https://github.com/cline/cline/tree/main/apps/cli/src/acp), [docs/usage/acp.mdx](https://github.com/cline/cline/blob/main/docs/usage/acp.mdx)).
- SDK: `@cline/sdk` is an in-process Node agent (`Agent`, `createTool`) with a plugin system for "tools and lifecycle hooks ... policy enforcement" ([README](https://github.com/cline/cline)).
- Auth: "Sign in with Cline, Sign in with ChatGPT Subscription, Sign in with OCA, or use your own API key"; OAuth for `cline`, `openai-codex`, `oca` ([CLI README](https://github.com/cline/cline/blob/main/apps/cli/README.md)). MCP: yes (stdio, HTTP, SSE).

### GitHub Copilot CLI and SDK

- CLI: [github/copilot-cli](https://github.com/github/copilot-cli), proprietary [license](https://github.com/github/copilot-cli/blob/main/LICENSE.md). It grants a right to "reproduce and redistribute unmodified copies of the Software as part of an application or service" that "provides material functionality beyond the Software itself". v1.0.100 on 2026-10-19; about 20 tagged builds in 10 days.
- ACP: `copilot --acp` (stdio) or `--acp --port N` (TCP), public preview since [2026-01-28](https://github.blog/changelog/2026-01-28-acp-support-in-copilot-cli-is-now-in-public-preview/) ([docs](https://docs.github.com/en/copilot/reference/copilot-cli-reference/acp-server)).
- SDK: [github/copilot-sdk](https://github.com/github/copilot-sdk), MIT, 10,562 stars, in Node/Python/Go/.NET/Java/Rust. Per its README, "All SDKs communicate with the Copilot CLI server via JSON-RPC". The CLI is bundled for Node, Python, and .NET. The SDK is "generally available"; latest v1.0.24-preview.0 on 2026-10-19.
- Permissions/tools: tools default to the CLI's first-party set "similar to `--allow-all`", but "Tool execution is still governed by each SDK's permission handler". It supports custom agents, skills, tools, MCP, hooks, and form elicitation callbacks.
- Auth: signed-in GitHub user, OAuth GitHub App user tokens, `COPILOT_GITHUB_TOKEN`/`GH_TOKEN`, or BYOK (OpenAI, Foundry, Anthropic). Billing follows the user's Copilot plan.

### Meta Muse Code

- Meta's terminal/CI coding agent for Muse Spark ([docs](https://dev.meta.ai/docs/muse-code)). Beta launched 2026-08-05 ([TechCrunch](https://techcrunch.com/2026/08/05/meta-launches-muse-code-an-ai-agent-for-large-code-bases), press). The CLI is a native `muse` binary with no public source; license unknown (proprietary) [INFERENCE].
- Embedding: `muse exec --json` writes JSONL events ([extending](https://dev.meta.ai/docs/muse-code/extending)). The docs also say: "drive a Muse Code session from your own program over a stable, versioned session protocol. `muse serve` runs the protocol, and `muse schema` prints its JSON schema", wrapped by the TS `@muse-code/sdk`. The [meta-models/muse-code-sdk](https://github.com/meta-models/muse-code-sdk) repo is MIT, 67 stars, created 2026-08-28, with no tagged releases.
- Features: approvals and an OS sandbox on by default, hooks, skills (a `/migrate` skill imports Claude Code/Codex config), MCP with OAuth 2.1, subagents, four background "observer agents", workflows, session messaging, rewind. ACP: not documented (searched docs; unknown).
- Auth ([auth](https://dev.meta.ai/docs/muse-code/auth)): browser sign-in or `META_API_KEY`; pay-as-you-go tokens or flat [subscriptions](https://dev.meta.ai/docs/muse-code/subscriptions). Subscriptions default to "Contributor mode", which trades extra usage for training rights on your content.

### Vercel fx

- [vercel-labs/fx](https://github.com/vercel-labs/fx): Apache-2.0, Zig, created 2026-08-11. 3,501 stars, at least 29 contributors. "Status: Experimental." Releases run from v0.0.1 (2026-08-17) to v0.0.14 (2026-10-16).
- Embedding ([README](https://raw.githubusercontent.com/vercel-labs/fx/main/README.md)): `fx ask --json` (`final_output`, `--resume`); `fx acp` over stdio; and [libfx](https://github.com/vercel-labs/fx/blob/main/sdk/README.md), "the agent core as a JavaScript library, built as a native Node.js addon and as WebAssembly". `createFxAgent()` takes your own tools, MCP clients, and skills. Vercel documents running harnesses "durably on Vercel" ([docs](https://vercel.com/docs/agent-harnesses/fx)).
- Permissions: the default `auto` mode sends non-routine actions "to a model that checks the exact action for prompt injection or malicious behavior". The other modes are `ask` and `full-access`. Sessions live in `~/.fx/sessions`, and compaction keeps the full text on disk.
- Built-in tools include subagents. MCP is supported, and `src/mcp` has an "MCP v2 engine, behind FX_MCP_ENGINE=v2".
- Auth: `fx login` (Vercel AI Gateway), `fx login codex` (ChatGPT subscription), `fx login grok` (Grok subscription), or OpenAI-compatible endpoints. Vercel is listed as a Sign-in-with-ChatGPT plan-usage partner ([OpenAI](https://learn.chatgpt.com/docs/sign-in-with-chatgpt.md)).

### Google Antigravity

- Antigravity 2.0 (desktop) and the Antigravity CLI `agy` (Go) "use the same Antigravity agent harness" ([blog, 2026-05-19](https://antigravity.google/blog/introducing-google-antigravity-cli/)). The CLI repo [google-antigravity/antigravity-cli](https://github.com/google-antigravity/antigravity-cli) has no license and serves as a docs/forum repo; 1.4.3 shipped 2026-10-20.
- Headless ([docs](https://antigravity.google/docs/cli/headless)): `agy -p` with `--output-format text|json|stream-json`. It uses cached credentials, so you must "Authenticate once with an interactive `agy` session first".
- ACP: the registry entry `antigravity-acp` v1.4.1 ships a Google-hosted binary `agy_acp_server.par` marked `"license": "proprietary"` ([registry](https://github.com/agentclientprotocol/registry/blob/main/antigravity-acp/agent.json)).
- SDK: [`google-antigravity`](https://antigravity.google/docs/sdk/overview) Python ([repo](https://github.com/google-antigravity/antigravity-sdk-python), Apache-2.0, 3,795 stars, created 2026-04-29), "a secure, stateful runtime harness that handles tool execution, context management, safety policies, and subagent delegation". It covers custom tools, MCP, policies, human-in-the-loop, subagents, hooks, triggers, persistence, and local models. Auth is `GEMINI_API_KEY` or Vertex. "The `Agent` class manages binary discovery", so a local harness binary is likely involved [INFERENCE]. A managed cloud variant exists as the "Gemini API Antigravity Agent".
- Terms forbid third-party access (section 4).

### Goose

- [aaif-goose/goose](https://github.com/aaif-goose/goose) (formerly `block/goose`, now part of the Agentic AI Foundation at the Linux Foundation): Apache-2.0, Rust. 55,457 stars, at least 664 contributors. v1.55.0 on 2026-10-16, about weekly.
- Embedding: as an ACP agent via `goose acp` (stdio) or `goose serve` over HTTP/WebSocket ([docs](https://github.com/aaif-goose/goose/blob/main/documentation/docs/gdk/acp/index.md)). Crates include `goose-sdk`. "Custom Distributions" support white-label builds.
- ACP providers ([docs](https://github.com/aaif-goose/goose/blob/main/documentation/docs/guides/acp-providers.md)): goose drives Claude Code (claude-agent-acp), Codex (codex-acp), Amp, and Pi as model backends, and passes goose extensions to them as MCP servers. It states: "ACP providers let you use goose with your existing Claude Code or ChatGPT Plus/Pro subscriptions." Limitation: "No session fork or resume" for ACP providers.
- MCP-native extensions, subagents, tool permissions, 15+ direct providers.
- Relevance: this is the closest open reference implementation of a "bring-your-own-agent" host [INFERENCE].

## 3. Protocols

### Agent Client Protocol (ACP)

- Purpose: "standardizes communication between code editors/IDEs and coding agents". Local agents speak JSON-RPC over stdio; remote agents over HTTP/WebSocket ("Full support for remote agents is a work in progress") ([intro](https://agentclientprotocol.com/get-started/introduction)). It reuses MCP JSON types and adds diff and plan UX types.
- Versions ([repo](https://github.com/agentclientprotocol/agent-client-protocol), Apache-2.0, 4,472 stars): stable schema-v1.26.0 and v2.0.0-alpha.9, both on 2026-10-16. v2 "is still labeled draft" ([migration](https://agentclientprotocol.com/protocol/v2/migration)).
- v2 changes that matter for a host:
  - `session/prompt` now acknowledges acceptance rather than ending the turn; completion arrives in `state_update`.
  - Updates are upserts.
  - "The Client file system, terminal execution, and session modes APIs are gone"; agents should use client-provided MCP servers instead.
  - `session/load` is replaced by `session/resume` with `replayFrom`; `session/list` and `session/close` become required.
  - `auth/login` and `auth/logout`.
- RFDs in flight: session fork, proxy chains, MCP-over-ACP, configurable LLM providers ([llms.txt](https://agentclientprotocol.com/llms.txt)).
- Registry ([page](https://agentclientprotocol.com/get-started/registry)): 42 agents as of 2026-10-20, including Claude Agent, Codex, Copilot, Cursor, Cline, Gemini CLI, Google Antigravity, Grok Build, OpenCode, goose, pi ACP, Devin, Junie, Kimi CLI, Qwen Code, Mistral Vibe, Factory Droid, and Amp. Muse Code and fx are not listed; fx does ship `fx acp`.
- Implication: one ACP client implementation reaches nearly every engine in this document [INFERENCE].

### MCP (spec 2026-07-28)

The [changelog](https://modelcontextprotocol.io/specification/2026-07-28/changelog) lists these changes relative to 2025-11-25:

- MCP becomes stateless. The `initialize` handshake and `Mcp-Session-Id` are removed, and `server/discover` is added.
- `subscriptions/listen` replaces the GET stream and resource subscribe.
- Tasks move out of core into the extension `io.modelcontextprotocol/tasks`, with polling `tasks/get`, a new `tasks/update`, and no `tasks/list`.
- Multi Round-Trip Requests replace server-initiated `elicitation/create`, `sampling/createMessage`, and `roots/list`: servers return `resultType: "input_required"` and the client retries with `inputResponses`. `notifications/elicitation/complete` is removed.
- Authorization: issuer validation per RFC 9207, credentials keyed by issuer, and Dynamic Client Registration deprecated in favor of Client ID Metadata Documents.
- Deprecated: Roots, Sampling, Logging, HTTP+SSE.

Harness lag: pi-mcp speaks 2025-11-25 ([README](https://github.com/earendil-works/pi/blob/main/packages/mcp/README.md)); Codex gates on a `mcp_2026_07_28` flag ([README](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)); fx's v2 engine is opt-in. A host that brokers MCP for several engines must handle both generations for at least the 12-month deprecation window [INFERENCE].

### Codex app-server protocol

A JSON-RPC 2.0 dialect: `thread/*`, `turn/*`, `item/*` notifications, and server-to-client approval requests, with generated TS/JSON schemas ([docs](https://learn.chatgpt.com/docs/app-server.md)). It is richer than ACP v1 for durable threads: attachments, read-state, archive, metadata, revert, and dynamic tools. It is Codex-only. OpenAI's SIWC docs show third-party clients driving app-server with a user's ChatGPT plan token ([SIWC](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server.md)).

### Vendor-specific session protocols

- Copilot SDK: JSON-RPC to the CLI's server mode.
- Muse Code: `muse serve` plus `muse schema`.
- OpenCode: OpenAPI/SSE.
- Claude: stream-json over stdio.

### A2A

[a2aproject/A2A](https://github.com/a2aproject/A2A): v1.0.0 on 2026-03-12, v1.0.1 on 2026-05-28. Gemini CLI ships an `a2a-server` package. It is relevant only if Memoshi bots must delegate to remote, independently hosted agents. It is not needed to drive local harnesses [INFERENCE].

## 4. Subscription-auth policy (verbatim, dated)

### Anthropic (Claude Free/Pro/Max)

- [Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance) (retrieved 2026-10-20):
  - "OAuth authentication is intended exclusively for purchasers of Claude Free, Pro, Max, Team, and Enterprise subscription plans and is designed to support ordinary use of Claude Code and other native Anthropic applications."
  - "Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users. Moreover, developers may not collect, store, or intermediate Claude.ai credentials or session tokens — sign-in to a Claude account must complete through Anthropic's own flow."
  - "Nor does it prevent an end user from signing in to the unmodified Claude Code binary with their own Claude subscription, including where a platform hosts Claude Code."
  - Conditions for running Claude Code inside products: "The Claude Code binary must not be modified ... customers may not remove, disable, or restrict any authentication method built into it", and "Customers may not pay for, resell, or intermediate Claude usage on their end users' behalf."
  - "Anthropic reserves the right to take measures to enforce these restrictions and may do so without prior notice."
- [Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview): "Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK."
- [Consumer Terms](https://www.anthropic.com/legal/consumer-terms) (effective 2025-10-08) prohibit: "Except when you are accessing our Services via an Anthropic API Key or where we otherwise explicitly permit it, to access the Services through automated or non-human means, whether through a bot, script, or otherwise."
- [Help Center: Use the Claude Agent SDK with your Claude plan](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan?format=md):
  - Update of 2026-10-07: "Claude Max and Team plans now include monthly API credits, which cover the Claude Agent SDK, `claude -p`, the Claude API, and Claude Managed Agents. You can still use the Claude Agent SDK, `claude -p`, and third-party apps with your subscription limits."
  - Update of 2026-06-15: "We've paused the previously-announced changes to Claude Agent SDK usage."
- 2026 enforcement events:
  - 2026-01-09: users report OAuth tokens blocked for external use ([openclaw#559](https://github.com/openclaw/openclaw/issues/559)); press describes server-side checks against tools "spoofing" Claude Code (press, [tech-insider](https://tech-insider.org/ie/claude-code-agent-pricing-split-2026/)).
  - 2026-02-20: terms clarification (press, [The Register](https://www.theregister.com/software/2026/02/20/anthropic-clarifies-ban-on-third-party-tool-access-to-claude/5014546)).
  - 2026-03-22: OpenCode v1.3.0 stops bundling Claude OAuth plugins ([OpenCode docs](https://github.com/anomalyco/opencode/blob/dev/packages/web/src/content/docs/providers.mdx)).
  - 2026-04-04: subscription access cut off for OpenClaw, OpenCode, NanoClaw (press, [TheNextWeb](https://thenextweb.com/news/anthropic-openclaw-claude-subscription-ban-cost)).
  - 2026-05-13/14: metered "programmatic credit" plan announced (press, [InfoWorld](https://www.infoworld.com/article/4171274/anthropic-puts-claude-agents-on-a-meter-across-its-subscriptions.html)).
  - That plan was paused on 2026-06-15 per Anthropic's own Help Center. The press article claiming the split "took effect" conflicts with this primary source.

### OpenAI (ChatGPT Go/Plus/Pro)

- [Help Center: Using your ChatGPT plan in other apps and sites](https://help.openai.com/articles/20001542) (updated about 2026-10-08):
  - "If you have a Go, Plus, or Pro plan, you can also choose to use your ChatGPT plan for AI requests in participating commercial apps and sites that support this feature."
  - "You can set a weekly usage limit for each app."
  - "Supported open-source tools remain available to all ChatGPT users."
  - "If you're an open source developer, explore our developer docs. If you're a commercial partner interested in integrating Sign in with ChatGPT, with or without token sharing, please complete this interest form."
- [SIWC developer overview](https://developers.openai.com/siwc/token-sharing-open-source.md): "These docs explain ChatGPT plan usage for open-source and locally hosted apps. If you're interested in offering it in a paid or remotely hosted app, complete the interest form." Each install registers a client and must send a stable `ext_agent_host_id`.
- [Partner directory](https://learn.chatgpt.com/docs/sign-in-with-chatgpt.md) (2026-10-20):
  - Plan-usage apps: Amp Code, Conductor, Dactyl, Devin, Hermes Agent, Hyperagent, Kilo Code, Lovable (coming soon), Notion, Vercel, Vorflux, Warp.
  - Open-source integrations: OpenClaw, OpenCode, Pi, T3.
- Enforcement: none found in 2026. OpenAI moved Codex to credit-based usage on 2026-04-02 (press, [tech-insider](https://tech-insider.org/ie/claude-code-agent-pricing-split-2026/)).

### xAI / SpaceXAI (SuperGrok, X Premium+)

- [Acceptable Use Policy](https://x.ai/legal/acceptable-use-policy) (effective 2026-08-14) prohibits "Accessing the Services through unauthorized automated or non-human means, whether through a bot, script, or otherwise" and "using bots to access ... our Service".
- [xAI news, 2026-05-15, "Connect Grok to Hermes Agent"](https://x.ai/news/grok-hermes): "Starting today, you can use your Grok subscription directly inside Hermes Agent ... More open-source agents and integrations are coming soon."
- No general published third-party policy or developer program for subscription OAuth was found (unknown). Pi, fx, and Grok Build itself implement SuperGrok login. One third-party project recorded that "Public first-party sources do not provide the required permission" ([grok-search-cli#8](https://github.com/patrick-fu/grok-search-cli/issues/8), 2026-08-03, third-party).
- Enforcement: users report HTTP 403 for standard SuperGrok via Hermes OAuth ([hermes-agent#26847](https://github.com/NousResearch/hermes-agent/issues/26847), third-party). Cause unknown.

### Google (Google AI Pro/Ultra, Gemini Code Assist)

- [Gemini CLI terms page](https://geminicli.com/docs/resources/tos-privacy/) (last updated 2026-04-10): "Directly accessing the services powering Gemini CLI (for example, the Gemini Code Assist service) using third-party software, tools, or services (for example, using OpenClaw with Gemini CLI OAuth) is a violation of applicable terms and policies. Such actions may be grounds for suspension or termination of your account."
- [Antigravity Additional Terms](https://antigravity.google/terms) section 6 (retrieved 2026-10-20): "You must not abuse, harm, interfere with, or disrupt the Service. This includes, but is not limited to, using the Service in connection with products not provided by us. Using third party software, tools, or services to access the Service (e.g. using OpenClaw with Antigravity OAuth) is a breach of this Agreement. Such actions may be grounds for suspension or termination of your Antigravity and/or Gemini CLI accounts."
- 2026 enforcement events:
  - February 2026: users report mass 403 "ToS" bans for paid accounts using OpenClaw with Antigravity/Gemini CLI OAuth ([Google AI forum, 2026-02-20](https://discuss.ai.google.dev/t/urgent-mass-403-tos-bans-on-gemini-api-antigravity-for-open-source-cli-users-paid-tier/124508); [openclaw#14203](https://github.com/openclaw/openclaw/issues/14203); press, [GIGAZINE 2026-02-24](https://gigazine.net/gsc_news/en/20260224-google-gemini-openclaw-accounts-banned)).
  - 2026-06-18: consumer Gemini CLI service ended ([Google blog](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli)).

### Meta (Muse Code subscriptions)

- [Muse Code subscriptions](https://dev.meta.ai/docs/muse-code/subscriptions) (retrieved 2026-10-20):
  - "The subscription applies to the Muse Code API key that is automatically connected in the Muse Code CLI onboarding process. This credential is for use with Muse Code only."
  - "Subscription: a flat monthly rate ... It works only through the Muse Code CLI while signed in with your Meta Model API account."
- Enforcement: none found. Pi's Meta OAuth module uses the "Muse Code CLI client id" ([source](https://github.com/earendil-works/pi/blob/main/packages/ai/src/auth/oauth/meta.ts)), which conflicts with the text above [INFERENCE].

### Policy matrix for Memoshi [INFERENCE]

| Vendor | Memoshi calls the model with the user's subscription | Memoshi spawns the vendor's unmodified CLI, user signs in themselves |
|---|---|---|
| Anthropic | Prohibited without approval | Explicitly allowed; no intermediating or reselling |
| OpenAI | Allowed via SIWC; commercial/hosted apps must apply | Allowed (Codex app-server accepts SIWC tokens) |
| xAI | No published policy; AUP bans unauthorized bots; Hermes-only precedent | Not addressed; headless/ACP documented "in scripts or bots" |
| Google | Prohibited (both terms pages) | Risky: Antigravity terms ban use "in connection with products not provided by us" |
| Meta | Prohibited ("Muse Code only") | Plausibly allowed ("through the Muse Code CLI") |

## 5. Decision guide [INFERENCE throughout]

### (a) Own-loop personal assistant (Memoshi owns the loop, memory, and tools)

- Embed Pi's `pi-ai` + `pi-agent-core` in-process (MIT, provider-agnostic, `pi-durable` for long-lived tasks), or OpenCode V2 `@opencode/sdk` (in-process router, SQLite-style `database.path`, per-session plugin instances).
- Pi is smaller and assistant-shaped. OpenCode brings coding tools, permissions, and child sessions for free.
- Authenticate with API keys plus OpenAI SIWC; apply to OpenAI as a commercial partner.
- Do not ship Pi's Anthropic, Meta, or Google subscription OAuth paths.
- Risks:
  - Pi has no built-in permission policy, so Memoshi must implement one in Pi's blocking hooks: `tool_call` in the coding agent, `beforeTool` in Pi Durable, which also covers nested Code Mode calls.
  - Pi v1 is three weeks old; OpenCode 2.1 just broke SDK/event contracts.
  - pi-mcp lags MCP 2026-07-28.

### (b) Coding workspace

- Drive OpenCode via its HTTP/OpenAPI server or V2 SDK (proven by Kuvo Code), or Codex app-server for the richest durable-thread and approval model.
- Put an ACP client on top so users can switch engines.
- Risks:
  - Codex WebSocket transport is "experimental and unsupported".
  - Codex alphas ship daily.
  - OpenCode V2 binaries are not on GitHub Releases yet.
  - Claude via the SDK still means a proprietary binary under the Commercial Terms.

### (c) Bring-your-own-agent bot roster (OpenMausBot/OpenBot/Noodle pattern)

- Be an ACP client first. The registry covers Claude (adapter), Codex (adapter), Copilot, Cursor, Gemini CLI, Antigravity, Grok Build, OpenCode, Cline, goose, and Pi (adapter).
- Fall back to headless NDJSON (`claude -p`, `grok -p`, `muse exec --json`, `agy -p`) where ACP is missing or weak.
- Users sign in to the unmodified vendor CLI themselves. This is the one model Anthropic explicitly allows, and it matches Goose's ACP-provider design.
- Copilot's license explicitly allows bundling the unmodified CLI.
- Risks:
  - Google's Antigravity terms could be read to cover any third-party driver.
  - xAI has no published policy.
  - ACP v1/v2 coexistence; ACP adapters lose fork/resume (Goose's documented limitation).
  - Per-vendor quota opacity.
  - Never touch or copy `~/.claude`, `~/.grok/auth.json`, or similar credential files.

## Notes on sources

- `badlogic/pi-mono` resolves to `earendil-works/pi`, `sst/opencode` to `anomalyco/opencode`, `block/goose` to `aaif-goose/goose`, and `zed-industries/claude-code-acp` to `agentclientprotocol/claude-agent-acp`. `xai-org/grok-cli` does not exist; `superagent-ai/grok-cli` (MIT, last push 2026-07-06) is an unrelated community CLI. Vercel FX is `vercel-labs/fx`, not `vercel/fx`.
- Press figures (tech-insider, TheNextWeb, InfoWorld, The Register, GIGAZINE, TechCrunch) are discovery leads only. Where Anthropic's Help Center contradicts the press (programmatic credit split), the primary source is reported.
