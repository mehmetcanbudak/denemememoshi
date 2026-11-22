# Memoshi name and trademark — preliminary search

**Date:** 2026-11-04  
**Status:** Preliminary public-source search filed; **not trademark clearance, a final name decision, or a risk re-score**.  
**Owns:** P0-16's naming/search evidence and the trademark-search input to the Phase 0 gate; the Memoh product-confusion assessment.  
**Depends on:** [D34](../plan/decisions.md#d34), [D59](../plan/decisions.md#d59), [D86](../plan/decisions.md#d86), [O8](../plan/decisions.md#open-decisions), [P0-16](../plan/phase-0.md#tickets), [Phase 0 exit criteria](../plan/phase-0.md#exit-criteria), [R22](../plan/risks.md#r22).

Research is evidence, not decisions. `[INFERENCE]` identifies an assessment rather than an observed registry finding. Registry statuses below are what the named public interface displayed on the research date, not an independent determination that rights exist, have expired, or can be disregarded.

## 1. Gate summary

- **The public product overlap with Memoh is substantiated.** At the inspected upstream revision, Memoh describes a multi-agent platform with a computer, browser and long-term memory per agent, API-key/model choice, coding agents, MCP and scheduled tasks. Its current first-party documentation also describes a desktop client, workspace files, terminal and desktop panes. This is not merely an unrelated repository with a similar spelling. [M1][memoh-readme] [M2][memoh-about]
- **An additional exact-name use exists:** Apple's Japanese App Store lists **“Memoshi｜推し活・チェキ管理”**, app ID **6780835257**, seller **SALT SPLASH K.K.**, as an iPhone lifestyle app for fan-activity/concert/photo records, with in-app purchases. This is evidence of an existing public software name, not a finding about that seller's registered trademarks or rights in the US/EU. [A1][apple-jp]
- The submitted USPTO combined-mark queries `CM:MEMOSHI` and `CM:MEMOH`, EUIPO basic query `MEMOSHI`, and WIPO embedded brand-name query `MEMOSHI` displayed no results. **Those outcomes do not establish availability.** Expanded searches returned other marks; the EUIPO software-related **MEMOHI** record and the broader WIPO results require attention. See §3, including the exact queries, identifiers and limitations. [U1][us-search] [E1][eu-memoshi] [W1][wipo-memoshi]
- **Carry-forward verdict:** the preliminary search is filed for [Phase 0 exit criterion 529](../plan/phase-0.md#exit-criteria); **O8 and R22 remain unresolved**. This record neither satisfies D34's clearance-before-brand-work requirement nor chooses a rename. No numeric/final risk score is assigned. [D34](../plan/decisions.md#d34), [O8](../plan/decisions.md#open-decisions), [R22](../plan/risks.md#r22).

## 2. Scope, prior evidence and method

### 2.1 Binding project boundary

[P0-16](../plan/phase-0.md#tickets) calls for starting the trademark search and Memoh assessment; the [exit criterion](../plan/phase-0.md#exit-criteria) calls for filing the search. [D34](../plan/decisions.md#d34) retains Memoshi as a working name and requires clearance and a Memoh assessment before brand work. [HANDOFF O8](../HANDOFF.md#7-open-decisions) likewise leaves the name open. The product baseline is a personal Assistant and persistent bots, each with memory/computer/browser, in native Mac/iPhone/iPad apps; v1 is the user's own-device product, with public release still O13. [MASTER_PLAN §§1,4](../plan/MASTER_PLAN.md#1-the-product), [D67](../plan/decisions.md#d67).

No future trademark-filing or public-sales territory is selected in the naming entries, P0-16, or the product/roadmap passages reviewed for this assignment. **This note uses the expressly requested US federal, EUIPO and WIPO interfaces as a limited preliminary screen, not as an adopted territorial strategy.** It does not silently add Turkish, Japanese, Chinese, UK or other national clearance work. A national record returned inside WIPO's participating collections is identified as such, not converted into a separate national-registry search.

### 2.2 Existing findings carried forward

The [2026-10-20 long-tail record, “Memoh”](agentic-workspace-landscape/landscape/oss-long-tail.md#memoh-cluster-b) already identified `felinics/Memoh`, its AGPL-3.0 licence, per-agent cloud computer/memory, channels, hosted/self-hosted distribution and naming concern. Its 2,710-star and repository-creation figures are **historical research observations**, not refreshed metrics in this note. [D34](../plan/decisions.md#d34) and [R22](../plan/risks.md#r22) carry that concern. The present pass checks the relevant primary product statements and official public search interfaces; it does not recreate the landscape audit.

### 2.3 Retrieval and authorization

All searches below were observed on **2026-11-04**. Static reads were used first. USPTO, EUIPO and WIPO are JavaScript-driven; their live public forms were then used in an isolated, assistant-owned browser session using the already-installed Chrome, without importing the user's browser state. No account, login, registry filing, purchase, registration, domain/account/configuration change or paid service was used. No reference product was installed, launched or instrumented; product capabilities below remain source/vendor claims, not reproduced behavior.

The WIPO static reader returned an ALTCHA challenge page. In the ordinary browser, the page initially displayed “Verifying...” and subsequently exposed the search form without an agent click on the challenge. No CAPTCHA solver, token fabrication, cookie import or access-control bypass was used. EUIPO's static page exposed only its shell; the browser supplied actual query and file-information results. Loading states were not treated as zero-match outcomes.

General web discovery queries, kept separate from official searches:

| Exact query | Source checks resulting from it | Evidential limit |
|---|---|---|
| `"Memoshi"` | Surfaced an app-directory lead; followed to the [primary Apple listing][apple-jp]. | Search ranking/absence is not a trademark search. Unrelated token/person/retail results were not treated as brand rights. |
| `"Memoshi" trademark` | Followed the exact-name app lead to Apple; consulted the [USPTO clearance guidance][us-clearance]. | No negative registry conclusion is taken from web-search absence. |
| `"Memoh" trademark` | Surfaced the withdrawn EU application **016477861**, verified directly at [EUIPO][eu-memoh], and a Chinese third-party lead **89753663**. | The [Aliyun page][china-lead] is a third-party lead only, not CNIPA evidence. No relationship between that applicant and `felinics/Memoh`, or current Chinese legal status, is established here. China is not added to the clearance scope. |
| `site.uspto.gov trademark search comprehensive clearance similar marks site:uspto.gov` | Located the [USPTO comprehensive-clearance][us-clearance], [federal-search][us-federal] and [likelihood-of-confusion][us-confusion] guidance. | Guidance explains the search boundary; it supplies no name-specific clearance. |

## 3. Official search record

### 3.1 United States — USPTO federal database

**Interface:** [Trademark Search][us-search], logged out; results path `https://tmsearch.uspto.gov/search/search-results`. Search terms are session-driven rather than encoded in that results URL, so the exact strings and mode are required to reproduce the record. Initial Wordmark queries retained both **Live** and **Dead** and their substatuses; no individual class was selected. The default “Coordinated” checkbox was displayed, but no class restriction was introduced. The expanded field-tag searches likewise returned live and dead records and contain no class/status clause.

| Exact submitted string | Mode | Observed result |
|---|---|---|
| `MEMOSHI` | Wordmark | “No results found”; displayed Live 0 / Dead 0. |
| `MEMOH` | Wordmark | “No results found”; displayed Live 0 / Dead 0. |
| `MEMOSHI*` | Wordmark | “No results found.” This exploratory basic-mode wildcard attempt is **not relied on as a proven substring search**. The documented combined-mark expressions below replace that ambiguity. |
| `MEMOH*` | Wordmark | Same limitation and displayed outcome as above. |
| `CM:MEMOSHI` | Field tag and Search builder | “No results found.” |
| `CM:MEMOH` | Field tag and Search builder | “No results found.” |
| `CM:/.*memosh.*/` | Field tag and Search builder | **3 results**, page 1 of 1; all three result cards read, listed below. |
| `CM:/.*memoh.*/` | Field tag and Search builder | **5 results**, page 1 of 1; all five result cards read, listed below. |

The `CM` and regular-expression approach follows the USPTO's own [federal searching guidance][us-federal]. These are lexical screens, not a complete pronunciation/translation/design search.

**Expanded-query result cards, as displayed by USPTO:** [U1][us-search]

| Query family | Mark | US serial | Displayed status | Class / displayed goods category | Displayed owner |
|---|---|---|---|---|---|
| `memosh` | MEMOSHE | 97191977 | Live / Registered | 014; jewelry, including bracelets/earrings | HONG KONG SHENGLANG INTERNATIONAL CO., LIMITED |
| `memosh` | MEMOSHIELD | 98464002 | Live / Registered | 005; dietary and nutritional supplements | Pinnacle Health Brands, LLC |
| `memosh` | MEMOSHE | 87490172 | Dead / Cancelled | 014; jewelry | Li Chunyan |
| `memoh` | MEMOHASP | 74064969 | Dead / Cancelled | 009; computer hardware for personal computers, with the result-card goods text truncated | ALADDIN KNOWLEDGE SYSTEM LTD |
| `memoh` | MEMOHI | 87078093 | Dead / Cancelled | 009; receivers, wireless equipment and other goods; full status check below | SHENZHEN MEMO TECHNOLOGY CO.,LTD |
| `memoh` | MEMOHONEY | 50069844 | Live / Pending | 005; dietary supplements for human consumption | GEX CORPORATION LLP |
| `memoh` | MEMOHEY | 97380463 | Live / Registered | 028; amusement/athletic products, with the result-card goods text truncated | Jiang, Jusu |
| `memoh` | HOMEMOH | 90417503 | Live / Registered | 010; medical/baby-care goods, including sphygmomanometers, baby bottles and breast pumps | Chen Zhonghui |

**MEMOHI follow-through:** the public [TSDR status query for serial 87078093][us-memohi] returned registration **5175169**, registration date **2017-04-04**, and **“DEAD/REGISTRATION/Cancelled/Invalidated”**. It states cancellation for failure to file an acceptable Section 8 declaration, status/cancellation date **2023-10-20**. Its expanded Class 9 goods include computer operating systems/programs, CAD/CAM workflow software and computer search-engine software, alongside communications/audio/video hardware. The current-owner panel identifies SHENZHEN MEMO TECHNOLOGY CO.,LTD. TSDR's own generation stamp was **2026-11-03 18:46:20 EST**. No assignment/proceedings investigation was performed, and cancellation is not evidence that commercial use ceased. [U2][us-memohi] [USPTO's dead-mark/common-law caveat][us-federal]

### 3.2 European Union — EUIPO eSearch plus

The [EUIPO searches page][eu-tools] links eSearch plus and separately describes TMview's participating-office coverage. **This section searches EUIPO/eSearch, not every EU member state's national register.** No class, owner, status or filing-date filter was applied to the basic searches.

| Exact query / action | Official result |
|---|---|
| Basic `MEMOSHI` | [Trade marks (0)][eu-memoshi]; “No results were found using the criteria introduced.” Designs/owners/representatives also displayed 0; those are not separate trademark clearances. |
| Basic `MEMOH` | [Trade marks (3), one page][eu-memoh-query]: MEMOHI **015564511**, MEMOH **016477861**, MEMOHIRA **018922329**. All three result summaries and file-information pages were read. |

| Official identifier | Observed status / dates | Relevant file-information finding |
|---|---|---|
| [015564511 — MEMOHI][eu-memohi] | Figurative; **Registered**; filed **2016-06-21**, registered **2016-10-20**; classes **9, 35, 41**; owner **SHENZHEN MEMO TECHNOLOGY CO.,LTD**. | Class 9 expressly includes “Computer programmes, recorded,” “Computer software, recorded” and “Computer programs (downloadable software),” plus communications/audio/video equipment. The page also displays expiry **2026-06-21**, while retaining **Registered** status, and a renewal record **029055061**, “Notification of expiry of trade mark,” status date **2025-11-23**. **Do not infer either successful renewal or lapsed rights from that mixed display.** Current renewal effect needs confirmation. |
| [016477861 — MEMOH][eu-memoh] | Word; **Application withdrawn**; filed **2017-03-17**; timeline withdrawal **2017-09-12**; class **20**; owner **INDUSTRIA FRIGORIFERI ITALIANA SpA**. | Goods include furniture, desks, seats, tables and racks. This is a furniture application, not evidence of an EU registration owned by the Memoh agent project. The timeline shows one opposition; its merits were not investigated. Withdrawal of this application is not a general release of the word. |
| [018922329 — MEMOHIRA][eu-memohira] | Word; **Registered**; filed **2023-09-06**, registered **2023-12-21**, expiry **2033-09-06**; class **9**; owner **Philipp Kühn**. | Class 9 goods are audio/video/amplifier racks and loudspeaker stands, **not software**. This demonstrates why a class number alone is insufficient to infer the product relationship. |

### 3.3 WIPO Global Brand Database — participating collections

**Interface:** [Global Brand Database][wipo-home], logged out. Brand-name searches had owner, application number, IP office, designation country, Nice class and goods/services fields blank. The exact submitted string and chosen strategy matter: the result breadcrumb for Embedded used “contains the word,” while Fuzzy used “contains word that resembles.”

| Exact string / strategy | Observed official outcome | Review boundary |
|---|---|---|
| `MEMOSHI` / **Embedded (results contain entered term)** | [“No results found!”][wipo-memoshi] | This is the observed participating-collections query, not global name clearance. |
| `MEMOH` / **Embedded (results contain entered term)** | [“Displaying 1-6 of 6 results”][wipo-memoh] | All six identifiers/status cards were read. Initial list extraction exposed five; switching to Grid exposed the sixth, PROJETO MEMOH. The completed six-record list is below. |
| `MEMOSHI` / **Fuzzy (results are spelled similarly to entered term)** | [**581 results**, page 1 of 20, “Displaying 1-30 of 581”][wipo-fuzzy] | The displayed count and visible first-page cards were inspected, **not all 581 records**. This is an open similarity-review workload, not a completed fuzzy clearance or a zero-match search. |

**All six Embedded `MEMOH` results:** [W2][wipo-memoh]

| Filing collection / number | Mark | Displayed owner | Nice classes | Displayed status |
|---|---|---|---|---|
| Brazil **913878340** | MEMOH | PEDRO DE FIGUEIREDO SCHNEIDER | 41 | Ended (**2019-02-21**) |
| Brazil **923692975** | MEMOH | HOMEM AO CONTRARIO SERVICOS LIMITADA ME | 41 | Registered (**2024-12-03**) |
| France **4503119** | MEMOH | BROLIN | 16, 35, 40 | Registered (**2019-03-22**) |
| European Union **016477861** | MEMOH | INDUSTRIA FRIGORIFERI ITALIANA SpA | 20 | Ended (**2017-09-12**); the direct EUIPO file says Application withdrawn. |
| Italy **2017000029857** | MEMOH | INDUSTRIA FRIGORIFERI ITALIANA S.P.A. | 20 | Registered (**2018-02-27**) |
| Brazil **923693238** | PROJETO MEMOH | HOMEM AO CONTRARIO SERVICOS LIMITADA ME | 41 | Registered (**2024-12-03**) |

No source here connects those owners to `felinics/Memoh`; no such connection is presumed. Goods beyond the classes were not adjudicated from these WIPO cards, and the underlying national files were not separately searched.

Visible Fuzzy first-page examples included UK **MEMOHI, UK00915564511**, classes 9/35/41, **Expired (2026-06-21)**, SHENZHEN MEMO TECHNOLOGY CO.,LTD; US **MIMOSHI, 78587925**, class 9, **Ended (2014-08-08)**, Jair Electronics Corporation; and US **MEMOSHE, 6956996**, class 14, **Registered (2023-01-17)**, displayed owner Li Chunyan. These are **WIPO-displayed leads**, not direct national status determinations, and the UK record does not resolve the EUIPO renewal question. [W3][wipo-fuzzy]

**Concrete coverage/latency limits:** WIPO's [coverage page][wipo-coverage], read in the browser, displayed US data through **2026-10-28**, EUIPO through **2026-11-03**, Madrid through **2026-10-30**, and Japan through **2026-10-27**. Other collections have different and sometimes much older endpoints. WIPO itself says its database covers Madrid and participating national/regional collections and that it can be prudent to search national/regional registers too. Thus an unreturned recent filing, nonparticipating office or unregistered use is not excluded. [W4][wipo-coverage] [W5][wipo-guidance]

### 3.4 What was inaccessible, incomplete, or outside this screen

- **No submitted literal/embedded shortlist query remains technically unreachable:** the US `MEMOSHI`/`MEMOH` and combined-mark queries, EUIPO `MEMOSHI`/`MEMOH`, and WIPO Embedded `MEMOSHI`/`MEMOH` each produced an actual result state. The initial static-reader failures/challenge shells were resolved by ordinary browser access; they are **not** recorded as failed or negative registry searches.
- **EUIPO MEMOHI's effective renewal position remains unresolved**, specifically because the accessible file simultaneously displays Registered, an elapsed expiry date and the renewal status described above. The file-information page was accessible; a current legal-status interpretation or further register/prosecution confirmation was not obtained. No account was created to use advanced functions.
- **WIPO Fuzzy review is incomplete, not technically blocked:** the 581-match outcome is reachable, but this note does not claim an exhaustive record-by-record assessment, phonetic search, transliteration search or legal comparison. The remaining matches must not be treated as nonconflicting.
- **Apple US listing check:** `https://apps.apple.com/us/app/id6780835257` returned **HTTP 404** in the static reader. The Japanese storefront listing was accessible. The US response establishes neither global delisting nor lack of US use/rights; the US storefront presence remains unconfirmed. [A1][apple-jp]
- Separate US state/business registries, TMOG issue-by-issue review, all EU national registers/TMview, direct Madrid Monitor, and additional national registries were **not performed in this limited screen**, not declared unreachable and not cleared by the WIPO result. Broader common-law/trade-name, pronunciation, translation/transliteration and logo/design searches remain outside the completed query set. The [USPTO comprehensive-clearance guidance][us-clearance] expressly distinguishes these resources from a federal database search alone.

## 4. Naming and product-confusion assessment

### 4.1 Memoh: actual primary facts, not an identity assumption

The GitHub main-revision API resolved `felinics/Memoh` to **`86ae1db1b6c09dcd0cebc44fccd79b2235c0505c`**, commit timestamp **2026-11-03T14:46:41Z**. The pinned [README][memoh-readme] uses the product name **Memoh**, calls it an open-source multi-agent platform, says each agent gets its own cloud computer/filesystem/desktop/browser/network/long-term memory, supports API keys or hosted Claude Code/Codex agents, and names chat channels, MCP tools, scheduled work and hosted/self-hosted routes. It links `memoh.ai`, `docs.memoh.ai` and `app.memoh.net`. Its footer identifies “MemohAI Team” / “Copyright (C) 2026 MemohAI”; this is an attribution, **not verified corporate identity or trademark ownership**. [M0][memoh-revision] [M1][memoh-readme]

The [pinned root LICENSE][memoh-license] is GNU AGPL v3. This is source-licence evidence, not clearance to adopt a competing product's name. No Memoh code, branding or artwork is imported by this investigation. The current [official about page][memoh-about] describes a desktop client for cloud/self-hosted servers and explicitly lists bot setup, sessions, providers, files, terminal/desktop panes, hooks, schedules and access control. The [quick start][memoh-start] advertises macOS/Windows/Linux downloads. Those pages are maker statements, not a launched or tested app. The site's [homepage metadata][memoh-site] identifies “Memoh — The multi-agent platform.”

### 4.2 Assessment

| Dimension | Evidence-based assessment |
|---|---|
| Name similarity | **MEMOSHI** and **MEMOH** share `MEMO`, but have different endings and lengths; they are not identical words. `[INFERENCE]` The shared beginning is a plausible discovery/association issue when presented beside a very similar product description. Neither intended pronunciation nor actual user confusion was established. [M1][memoh-readme] [D34](../plan/decisions.md#d34) |
| Product/purchaser overlap | `[INFERENCE]` Persistent bot teams, agent-specific workspaces/memory/browser, coding, scheduled tasks, MCP and model choice provide concrete reasons for overlapping searches and prospective users. This substantiates the concern beyond spelling alone. [M1][memoh-readme] [M2][memoh-about] [MASTER_PLAN §1](../plan/MASTER_PLAN.md#1-the-product) |
| Distinguishing facts | Memoshi's accepted baseline emphasizes native Apple apps, own-device operation, Assistant delegation and policy/recovery contracts; Memoh advertises hosted/self-hosted server operation and a desktop client. `[INFERENCE]` These differences matter to product positioning but do not by themselves dispose of trademark or affiliation confusion. No identical-UI claim is made. [M2][memoh-about] [MASTER_PLAN §§1,3](../plan/MASTER_PLAN.md#1-the-product) |
| Exact-name software use | The separate SALT SPLASH **Memoshi** iPhone listing is an exact Latin-name use in software, although its advertised fan-activity purpose differs from the bot platform. `[INFERENCE]` This adds an app-discovery/name-investment concern independent of the Memoh overlap. No US/EU registration or legal priority is inferred from the Japanese listing. [A1][apple-jp] |
| Registry significance | The searches did not establish an exact-name US federal/EUTM/WIPO result for Memoshi under the submitted queries, but did identify other marks and an unresolved EUIPO software-related MEMOHI renewal position. **A no-result string search does not settle similarity, related goods, territorial priority or common-law rights.** [U1][us-search] [E1][eu-memoshi] [E2][eu-memohi] [W1][wipo-memoshi] [USPTO guidance][us-confusion] |

**Scoped verdict:** `[INFERENCE]` Continuing to call the private development project Memoshi as the accepted **working name** is distinct from treating the name as cleared for brand investment or public distribution. The primary product overlap, exact-name app listing and unresolved registry/similarity work are sufficient reasons to keep O8/R22 open. This note neither recommends a replacement name nor determines infringement, registrability, coexistence terms, a final risk score or a legal safe harbor. The USPTO explains that marks need not be identical, that related goods need not share a class, and that earlier US commercial use may matter without federal registration. [D34](../plan/decisions.md#d34), [O8](../plan/decisions.md#open-decisions), [us-confusion], [us-clearance].

## 5. Open decisions and actionable ownership

The owner roles below follow the project's one-builder/user model; an external specialist is a proposed task-specific reviewer, not a booked service or a new prerequisite to private work. [D45](../plan/decisions.md#d45), [D67](../plan/decisions.md#d67), [D91](../plan/decisions.md#d91).

| Open item | Owner | Next action / decision boundary |
|---|---|---|
| Final product name, O8 | **User / builder, wearing PD** | Review the Memoh overlap and exact-name Apple app evidence together. Decide whether to retain Memoshi for clearance work or investigate alternatives; record the decision through change control **before brand work**. This note does not choose for the user. |
| Territorial and goods/services scope | **User / builder, wearing PD** | Declare actual intended use/public-distribution/filing territories and the offered goods/services. No territory is selected merely because a user, repository author or app seller is located there. Use that declaration to commission/perform the relevant national searches; do not assume US/EU/WIPO is worldwide coverage. |
| EUIPO MEMOHI **015564511** renewal and overlap | **Builder / PD**, with a qualified trademark reviewer for a legal conclusion | Retrieve current eRegister/prosecution/renewal confirmation for **029055061**, resolve the status/expiry display, and compare the actual software wording and mark with the intended Memoshi offering. Retain the dated official output; do not discard this record as expired on the present evidence. |
| Broader similarity/clearance record | **Builder / PD**; jurisdiction-qualified reviewer before public/commercial reliance | Review the remaining WIPO Fuzzy matches and then run territorial phonetic/transliteration/design/common-law searches appropriate to the selected name and goods. Refresh the USPTO/EUIPO/WIPO queries near the decision date, using the serial/application identifiers here rather than relying on result counts alone. US state/TMOG and EU national-register gaps in §3.4 remain explicit. |
| SALT SPLASH Memoshi software use | **Builder / PD** | Establish publisher/product use history and applicable storefront/territory presence from primary records, including the unresolved US storefront response. If relevant territories include Japan, add the appropriate official national search **after the territorial decision**. Do not treat a differing app category as clearance. |
| Memoh identity, use/priority and any coexistence question | **User / builder / PD**, with a trademark reviewer if legal reliance is needed | Establish the actual legal operator, use territories/dates and any relevant applications from primary records. The README copyright name and GitHub account are not proof of trademark ownership. No outreach, agreement or permission request is made or selected here. |
| Phase 0 gate integration | **Main integration owner / builder** | Link this record as **preliminary search filed, O8/R22 unresolved**; keep any risk re-score and final gate outcome in the existing gate process. Do not turn this evidence note into clearance or alter the execution/release holds. |

## 6. Permanent identifiers and unchanged contracts

A name decision does **not** reopen the accepted permanent identifier scheme. [D59](../plan/decisions.md#d59), as settled by [D86](../plan/decisions.md#d86), keeps:

| Purpose | Permanent value |
|---|---|
| Prefix / iPhone and iPad bundle ID | `com.mehmetcanbudak.memoshi` |
| Mac app bundle ID | `com.mehmetcanbudak.memoshi.mac` |
| Helper bundle ID / LaunchAgent label | `com.mehmetcanbudak.memoshi.memoshid` |
| iCloud container | `iCloud.com.mehmetcanbudak.memoshi` |
| Keychain access group | `<TeamID>.com.mehmetcanbudak.memoshi.secrets` |
| App Group | `<TeamID>.com.mehmetcanbudak.memoshi.shared` |

Only user-visible branding changes under the accepted rename policy. This research changes no identifier, account, provisioning/signing setting, domain decision, SDK pin, licence policy, frontend choice, numerical design value, feature stage, calendar, phase cut, qualification boundary or release hold. D91's qualifying personal/noncommercial Kuvo permission, D92–D94's design direction and the public/commercial rights-review boundary remain untouched. [D59](../plan/decisions.md#d59), [D91](../plan/decisions.md#d91), [D92](../plan/decisions.md#d92), [D93](../plan/decisions.md#d93), [D94](../plan/decisions.md#d94), [HANDOFF next moves](../HANDOFF.md#8-next-moves).

## Sources

Primary links were read on 2026-11-04 unless explicitly identified as carried historical evidence. Dynamic searches must be reproduced with the exact terms/mode/date/filters in §3; their links are not immutable registry snapshots. No third-party captures, app media, credentials or personal data are added to this repository.

- **M0:** [Memoh main-revision API][memoh-revision].
- **M1:** [Memoh README at `86ae1db1b6c09dcd0cebc44fccd79b2235c0505c`][memoh-readme].
- **M2:** [Memoh official About][memoh-about]; [Quick Start][memoh-start]; [homepage][memoh-site].
- **M3:** [Memoh pinned root LICENSE][memoh-license].
- **A1:** [Apple Japanese App Store, ID 6780835257][apple-jp].
- **U1:** [USPTO Trademark Search][us-search]; query ledger/results in §3.1.
- **U2:** [USPTO TSDR, serial 87078093][us-memohi].
- **E1:** [EUIPO basic MEMOSHI][eu-memoshi] and [basic MEMOH][eu-memoh-query].
- **E2–E4:** EUIPO files [015564511][eu-memohi], [016477861][eu-memoh], [018922329][eu-memohira].
- **W1–W3:** WIPO [Embedded MEMOSHI][wipo-memoshi], [Embedded MEMOH][wipo-memoh], [Fuzzy MEMOSHI][wipo-fuzzy].
- **W4–W5:** [WIPO collection coverage][wipo-coverage] and [official scope guidance][wipo-guidance].
- **Search scope guidance:** USPTO [comprehensive clearance][us-clearance], [federal searching][us-federal], [likelihood of confusion][us-confusion]; [EUIPO search tools][eu-tools].
- **Secondary discovery lead only:** [Aliyun, China number 89753663][china-lead]; not a primary-registry finding.

[memoh-revision]: https://api.github.com/repos/felinics/Memoh/commits/86ae1db1b6c09dcd0cebc44fccd79b2235c0505c
[memoh-readme]: https://github.com/felinics/Memoh/blob/86ae1db1b6c09dcd0cebc44fccd79b2235c0505c/README.md
[memoh-license]: https://github.com/felinics/Memoh/blob/86ae1db1b6c09dcd0cebc44fccd79b2235c0505c/LICENSE
[memoh-about]: https://docs.memoh.ai/about
[memoh-start]: https://docs.memoh.ai/guides/quick-start
[memoh-site]: https://memoh.ai/
[apple-jp]: https://apps.apple.com/jp/app/memoshi-%E6%8E%A8%E3%81%97%E6%B4%BB-%E3%83%81%E3%82%A7%E3%82%AD%E7%AE%A1%E7%90%86/id6780835257
[us-search]: https://tmsearch.uspto.gov/search/search-results
[us-memohi]: https://tsdr.uspto.gov/#caseNumber=87078093&caseSearchType=US_APPLICATION&caseType=DEFAULT&searchType=statusSearch
[us-clearance]: https://www.uspto.gov/trademarks/search/comprehensive-clearance-search-similar-trademarks
[us-federal]: https://www.uspto.gov/trademarks/search/federal-trademark-searching
[us-confusion]: https://www.uspto.gov/trademarks/search/likelihood-confusion
[eu-tools]: https://www.euipo.europa.eu/en/search-ip
[eu-memoshi]: https://euipo.europa.eu/eSearch/#basic/1+1+1+1/100+100+100+100/MEMOSHI
[eu-memoh-query]: https://euipo.europa.eu/eSearch/#basic/1+1+1+1/100+100+100+100/MEMOH
[eu-memohi]: https://euipo.europa.eu/eSearch/#details/trademarks/015564511
[eu-memoh]: https://euipo.europa.eu/eSearch/#details/trademarks/016477861
[eu-memohira]: https://euipo.europa.eu/eSearch/#details/trademarks/018922329
[wipo-home]: https://branddb.wipo.int/
[wipo-guidance]: https://www.wipo.int/en/web/global-brand-database
[wipo-coverage]: https://branddb.wipo.int/en/coverage
[wipo-memoshi]: https://branddb.wipo.int/en/similarname/results?sort=score%20desc&start=0&rows=30&asStructure=%7B%22_id%22:%228ff7%22,%22boolean%22:%22AND%22,%22bricks%22:%5B%7B%22_id%22:%228ff8%22,%22key%22:%22brandName%22,%22value%22:%22MEMOSHI%22,%22strategy%22:%22Simple%22%7D%5D%7D&_=1793749172655&fg=_void_
[wipo-memoh]: https://branddb.wipo.int/en/similarname/results?sort=score%20desc&rows=30&asStructure=%7B%22_id%22:%22902f%22,%22boolean%22:%22AND%22,%22bricks%22:%5B%7B%22_id%22:%229030%22,%22key%22:%22brandName%22,%22value%22:%22MEMOH%22,%22strategy%22:%22Simple%22%7D%5D%7D&fg=_void_&_=1793749317134
[wipo-fuzzy]: https://branddb.wipo.int/en/similarname/results?sort=score%20desc&start=0&rows=30&asStructure=%7B%22_id%22:%22907c%22,%22boolean%22:%22AND%22,%22bricks%22:%5B%7B%22_id%22:%22907d%22,%22key%22:%22brandName%22,%22value%22:%22MEMOSHI%22,%22strategy%22:%22Fuzzy%22%7D%5D%7D&fg=_void_&_=1793749473506
[china-lead]: https://tm.aliyun.com/detail/eb6e_89753663_9
