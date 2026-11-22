# S3: a Network Extension content filter for bot browsers (study)

**Status:** Study for the owner's decision, 2026-11-14. Not a decision and not a gate result. Nothing was built, signed, installed or approved for it. [D101](../plan/decisions.md#d101) and 08 §15 stay as they are until the owner decides.
**Labels:** **[OBS]** recorded by the owned independent-sink control. **[DOC]** Apple documentation or Apple staff on the developer forums. **[INFERENCE]** not observed or documented.
**Inputs:** the 2026-11-07 boundary design (`evidence/2026-11-07-memoshi-engineering/analysis/browser-no-bypass-design.md` §1, §4–§6), the GatewayAuth control (`evidence/2026-11-08-memoshi-engineering/GatewayAuth/`), and the 2026-11-14 owner-free controls (`evidence/2026-11-14-memoshi-s3-no-bypass-controls/`).

## 1. The question

D101's route (authenticated gateway proxy, a deny-local content-rule list plus the per-bot allowlist, and Lockdown Mode) passes every product scenario of the owned control except one: a `target=_blank` link activation opens a payload-free TCP connection before any navigation policy runs. 06 row 6 asks whether a Network Extension (NE) content filter is worth its permission cost to close it (`docs/plan/06-computers-and-browsers.md`, row 6 and open question 5). This study answers what it would close, what it would cost, and which options the owner has.

## 2. What is open today

| Gap | Today's control | Evidence |
|---|---|---|
| `target=_blank` preconnect: one empty TCP connection to a loopback port, and an empty authenticated gateway tunnel for names | None in public API: content rules, `javaScriptCanOpenWindowsAutomatically`, a cancelling navigation policy and `createWebViewWith` returning `nil` all run after it | [OBS] one empty connection per route (2 sink events: accept and read-end), with scripted and with trusted native clicks (§2.1) |
| WebRTC (STUN over UDP, TURN over TCP) | Lockdown removes `RTCPeerConnection` | [OBS] design §1.2, §1.6; WebKit creates these sockets with no proxy [DOC, design §1.2] |
| WebTransport (QUIC over UDP) | Lockdown removes `WebTransport`; with the proxy set it fails | [OBS] design §1.3 |
| HTTP/3 through `Alt-Svc`, DNS | Not measured on real sites | design §9; needs the owner's packet capture |

WebRTC and WebTransport are closed only by Lockdown. If the owner later drops Lockdown (its real-site cost is unmeasured and could fail S3.3), both reopen, and no public WebKit switch closes them again (design §5).

### 2.1 Trusted native clicks (2026-11-14 control)

The prototype and the GatewayAuth control clicked the link from script (`a.click()`). The 2026-11-14 control adds synthesized `NSEvent` clicks through the product's native input path (`BrowserInputSynthesizer`). The page saw every click as trusted, and the result is the same as for script clicks: one empty connection to the loopback sink on both routes, plus one empty gateway tunnel for the name on the gateway route [OBS: run `control-owned4b-9e95c15e09ac`, rows `product-fixture-native-blank` and `product-proxy-native-blank`]. A bot acting through real input does not avoid the residual.

## 3. What a content filter could close

A macOS content filter is a system extension with an `NEFilterDataProvider`. The system hands it each new network flow as an `NEFilterFlow` and applies its pass or drop verdict [DOC: NEFilterDataProvider]. A socket flow carries its remote and local endpoints [DOC: NEFilterSocketFlow], the audit token of the app it is attributed to (`sourceAppAuditToken`) and, since macOS 13, of the process that actually opened it (`sourceProcessAuditToken`); the two differ when a system process connects on an app's behalf [DOC: sourceProcessAuditToken].

A Memoshi filter would apply one rule: flows attributed to Memoshi's WebKit networking may go only to the bot gateway's loopback port; every other flow from them is dropped. That would cover:

| Gap | Covered? |
|---|---|
| `target=_blank` preconnect to loopback | Yes, if the filter sees loopback flows and decides before the connection completes. Neither is documented for loopback; it must be measured [INFERENCE] |
| WebRTC UDP and TURN-over-TCP | Yes: they are socket flows from the app's networking process [DOC: socket flows; INFERENCE: attribution of WebKit's networking process] |
| WebTransport and HTTP/3 (QUIC) | Yes, as UDP flows [INFERENCE] |
| Names WebKit resolves itself | Partly: lookups go through `mDNSResponder`, a system process; whether its flows are attributed to Memoshi is not documented [INFERENCE] |

It would also make Lockdown optional for the network boundary: WebRTC and WebTransport would be dropped at the flow level, so Lockdown would only be kept for its attack-surface reduction. That trade is the owner's [INFERENCE].

What it would not fix:

- **iPhone and iPad.** Content filters there run only on supervised devices, on a child's device through Screen Time, or per app on managed devices [DOC: TN3134]. The mobile bot browser keeps D101's route and its `_blank` residual.
- **Telling bots apart.** All bot web views in one app share WebKit's networking process [INFERENCE], so the filter can enforce "gateway only" for the app's WebKit traffic but cannot tell one bot from another. Per-bot policy stays in the gateway.
- **Other WebKit content in Memoshi.** Any non-bot web view that loads directly through the same networking process would be dropped too, unless the filter can tell it apart [INFERENCE]. Memoshi's other web content would have to be offline or gateway-routed.

The macOS 26 URL filter provider (`NEURLFilter`, an app extension) decides on full URLs [DOC: TN3134, WWDC25 234]. It sees URL loads, not raw sockets, so it would not close the preconnect, WebRTC or WebTransport [INFERENCE]. A transparent or per-app proxy was ruled out in the design (§4: loopback excluded; per-app VPN needs managed devices [DOC: TN3134]).

## 4. What it costs

| Cost | Detail |
|---|---|
| Packaging | On macOS a content filter must be a system extension (macOS 10.15+), in the app's `Contents/Library/SystemExtensions`; the app must be installed in `/Applications` for activation [DOC: TN3134; Installing System Extensions and Drivers] |
| Entitlements | `com.apple.developer.networking.networkextension` with the content-filter value; Developer ID builds use the `-systemextension` variant (`content-filter-provider-systemextension`), and the host app also needs `com.apple.developer.system-extension.install` [DOC: NE entitlement; Apple DTS, "Exporting a Developer ID Network Extension"]. A Developer ID provisioning profile with the Network Extension capability is required [DOC: NE entitlement] |
| User approval | Two steps: the user allows the system extension in System Settings, and saving the filter configuration with `NEFilterManager` asks the user to allow network filtering [DOC: Installing System Extensions; NEFilterManager] [INFERENCE: exact macOS 27 wording] |
| Privilege | A system extension runs in a global context, independent of the logged-in user [DOC: TN3134], as root [INFERENCE: design §4]. It sees every flow on the Mac, not only Memoshi's. |
| Conflict with rules | 08 §15 (Meta Muse row): "no privileged helper in v1". A root system extension is a privileged component Memoshi ships; adopting it changes that rule. It also adds an entitlement, a profile and a system-extension notarization path to 09's P2–P4 plan and S5 |
| Operational risk | A filter sits on every connection of the Mac. Developers report system-wide outages and verdicts not obeyed (developer forum threads 817264, 791769; macOS 27 beta report 837709) [DOC: forum reports, not Apple statements]. Updates replace the extension in place; deleting the app removes it [DOC: Installing System Extensions] |
| Privacy | The data provider runs in a restrictive sandbox that cannot export flow contents [DOC: Content filter providers], but the product would still hold a component that sees all of the user's traffic. The privacy section (08 §12) would need a new row |
| Interplay | Other filters (MDM, security products) run alongside; `NEFilterManager.grade` orders them [DOC: NEFilterManager] |
| Engineering | About 2–3 weeks for the extension, rule plumbing, approval UX, an owned signed control and failure handling [INFERENCE] |

## 5. Options for the owner

| Option | `_blank` residual | WebRTC/WebTransport | Rules that change | Cost |
|---|---|---|---|---|
| **A. Keep D101 and accept the residual.** File Apple Feedback and a WebKit bug; keep the `_blank` rows as retained failing controls; record a gate exception for S3 row 6's strict criterion | Stays open (empty connect, no payload) [OBS] | Closed by Lockdown | Gate exception in phase-0 | None now |
| **B. Opt-in filter on Mac.** A "strict browser isolation" setting installs the filter; without it the route is A | Closed on Macs that opt in [INFERENCE until measured] | Closed at flow level and by Lockdown | 08 §15 gets a scoped exception; 09 P2–P4 and S5 add the profile and notarization path | §4, plus two routes to test |
| **C. Required filter for bot browsers on Mac** | Closed on every Mac [INFERENCE until measured] | Closed at flow level; Lockdown becomes optional for the network boundary | 08 §15 reversed for Mac; onboarding gains two approvals | §4, and bot browsing cannot start before approval |
| **D. Bot browsing only on Bot computers (VMs, [D113](../plan/decisions.md#d113))** | Closed by the VM's own network policy [INFERENCE] | Same | 06's per-device browser model; Phase 2 timing | A VM per browsing bot |
| **E. Script click interceptor** | Not a boundary: page script can bypass it (design §5) | — | — | Rejected in the design |

What each option needs before it could be qualified:

- **A:** nothing new; the owner records the exception.
- **B and C:** a signed prototype run against the owned control: (1) a Developer ID-signed app with the extension and profile, (2) the control's `_blank`, WebRTC and WebTransport rows with Lockdown off and on, (3) proof that the filter sees loopback flows and drops the preconnect before connect, (4) proof that other apps' traffic is untouched, (5) the approval steps recorded. This needs the owner's signing identity and approval on this Mac.
- **D:** the Bot-computer VM work and a VM network-policy control.

## 6. Unknowns a prototype must settle

1. Whether a content filter sees loopback flows at all, and whether a drop at `handleNewFlow` prevents the TCP connect (the residual is a bare connect).
2. Which audit token WebKit's networking process flows carry: Memoshi's (`sourceAppAuditToken`) or only WebKit's own process.
3. Whether `mDNSResponder` lookups made for WebKit are attributed to Memoshi.
4. The exact approval prompts and behaviour on macOS 27, and on managed Macs with an existing filter.
5. The effect of a crash or an unresponsive filter on the user's whole network.

## 7. 2026-11-14 control results that bear on this study

Run `control-owned4b-9e95c15e09ac` (details in `evidence/2026-11-14-memoshi-s3-no-bypass-controls/README.md`) [OBS]:

- **Trusted clicks:** the `_blank` residual is unchanged under trusted native input (§2.1).
- **Persistent stores:** a service worker seeded into a `forIdentifier` store outside the boundary fired again when the store was reopened outside it, and did not fire when a product session reopened the store under Lockdown; 0 sink events. Lockdown is what stops it (`serviceWorker` undefined). Without Lockdown (option C) the filter or the deny-local list would have to stop it.
- **Two concurrent bots:** gateway route and owned-fixture route at once, both probes overlapping: 0 sink events.
- **Lockdown on owned fixtures:** 6 of 8 owned tasks passed in each of two runs. Only the cross-origin frame click failed both times (`unsupportedScale`); whether Lockdown causes it is not isolated. Lockdown removed `RTCPeerConnection`, `WebTransport`, service workers, IndexedDB, the Cache API, Web Audio, `FileReader`, WebAssembly and notifications, and WebGL returned `null`.
- **Not a formal pass:** the direct positive control missed its two local-only `.local` names (timeouts in WebKit), probably Local Network privacy for the fresh unsigned carrier [INFERENCE]. Every product scenario still had 0 sink events.

None of this changes §5. The residual stays open under every owner-free control, and only a flow-level control (B, C) or a VM (D) could close it.

## 8. Sources

- Apple, TN3134: Network Extension provider deployment — https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment
- Apple, Content filter providers — https://developer.apple.com/documentation/networkextension/content-filter-providers
- Apple, NEFilterDataProvider — https://developer.apple.com/documentation/networkextension/nefilterdataprovider
- Apple, NEFilterSocketFlow — https://developer.apple.com/documentation/networkextension/nefiltersocketflow
- Apple, NEFilterFlow.sourceAppAuditToken — https://developer.apple.com/documentation/networkextension/nefilterflow/sourceappaudittoken
- Apple, NEFilterFlow.sourceProcessAuditToken — https://developer.apple.com/documentation/networkextension/nefilterflow/sourceprocessaudittoken
- Apple, NEFilterManager — https://developer.apple.com/documentation/networkextension/nefiltermanager
- Apple, Network Extensions Entitlement — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension
- Apple, Installing System Extensions and Drivers — https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers
- Apple DTS (Quinn), "Exporting a Developer ID Network Extension" — https://developer.apple.com/forums/thread/737894
- Apple, WWDC25 session 234, "Filter and tunnel network traffic with NetworkExtension" — https://developer.apple.com/videos/play/wwdc2025/234
- Apple Developer Forums, NEFilterDataProvider reports — https://developer.apple.com/forums/thread/817264, https://developer.apple.com/forums/thread/791769, https://developer.apple.com/forums/thread/837709
- Memoshi: `docs/plan/08-security-and-privacy.md` §15; `docs/plan/09-platform-macos.md` P2–P4; `docs/plan/06-computers-and-browsers.md` row 6; [D101](../plan/decisions.md#d101); the 2026-11-07 design and its evidence named above.
