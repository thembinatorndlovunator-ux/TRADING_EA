# Codex Fourth Review — TASK-001 Round-Three Response

**Disposition: CHANGES REQUESTED — NOT LIFTED**

The third correction pass fixes most of the preceding review, including the
stale task-level FVG description, V6.37 daily-scan scope, both newly requested
V6.37 management-path RSI effects, V8.11 basket-leg citation, conditional
restart drawdown calculation, current broker-held SL/TP wording, and the
direction-flip omission. Approval is still blocked by several source-factual
and package-consistency errors described below.

All remaining work is documentation-only. Neither immutable baseline EA should
be edited for TASK-001.

## Review target and method

- Response reviewed:
  `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round3.md`.
- Correction commits reviewed: `538bc39` and metadata follow-up `79f8e5a`
  (current `HEAD`).
- Every claimed correction was traced against the current V6.37/V8.11 source,
  not accepted from the response or revised prose. The current documents,
  commit path sets, status text, identity files, and diff claims were checked
  separately.
- Static review only. No MetaEditor compilation, Strategy Tester run, broker
  connection, restart simulation, or account-mode execution test was run.

Source identity remains intact:

| File | Lines | SHA-256 |
|---|---:|---|
| `01_BASELINE/EA_V637/Thembabot14 Max.mq5` | 8,822 | `C35BCC7E0095D60B0C672FAEEBA696B4DB8587B0AFB80E6EFBBFDC8ACCDFBC1D` |
| `01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5` | 2,397 | `B5740327F6D84FD7C00807001418DF0FCC3912A8101BCA2DBB55DE0E51CD1F1B` |
| `01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt` | 100 | `EA9452D4475D55F1AADD35A6F8F83B76C6046E2118D02AA5A918E673AF4BCE96` |

The per-EA tag diffs are empty, as are separate tag diffs for the set file and
the 13 PNGs. `git diff c61903f..79f8e5a -- 01_BASELINE` is also empty. The
preserved artifacts are unchanged. As previously established,
`git diff <baseline-tag> -- 01_BASELINE` is not empty because `c61903f` added
the inventory and visual-notes documents.

## Claim-by-claim verification

### Group 1 — stale FVG claim

**VERIFIED.** V8.11's `ScanFVG` touch loops stop at index 2
(841–843/853–855), omit trigger bar 1, and store no consumed state; FVG state
refreshes only on a new `InpRefineTF` bar at 387–395. The task description at
lines 34–38 now calls first-return enforcement partial and states both
limitations. It aligns with the detailed audit and comparison.

### Group 2 — V6.37 package consistency

| Item | Verdict | Independent result |
|---|---|---|
| ROTATION visibility/policy | **NOT RESOLVED** | The source sets a transient reason at 7524, but the revised condition is still wrong. The reason can reach the dashboard only when **both** `best_buy` and `best_sell` remain invalid at 885–890 and the transient value has not been cleared/replaced by a later candidate. A conflict at 893–900 or any selected candidate in either direction at 902–908 replaces the dashboard text; later candidates can also reset the reason at 1889. Audit lines 47/226 and comparison lines 139–152 incorrectly reduce this to Rotation being the sole candidate “in that direction” and use unsupported frequency claims such as “common”/“often.” Audit line 154 still says the interaction proves a maintenance miss, while comparison lines 284–296 still call it a verified conflict with Rotation's stated purpose. Source 8106–8115 does not say Rotation should trade Volatile Expansion; the router's no-mean-reversion policy may be intentional. The defensible classification remains verified reachability/policy ambiguity. |
| Daily-close scan scope | **VERIFIED, minor wording residue** | Source confirms magic-only P/L aggregation at 3325–3347/3373–3387, magic-only position closing at 3391–3400, symbol-scoped pending deletion at 3403–3413, and zero defaults at inputs 120–123. Audit lines 104–105, summary row 1, and the comparison now preserve those distinctions. “Never designed to” at audit line 104 still infers historical intent that static source cannot prove; “implemented magic-wide” is supportable. |
| `MomentumFailing` fallback | **V6.37 CORRECTION VERIFIED; COMPARISON INTRODUCES AN ERROR** | V6.37 fallback `50` at 6526/6532 fails strict entry tests at 2224/2232 and 2670/2685, can satisfy the inclusive `MomentumStillFavorable` conjunct at 3205–3206, and forces `MomentumFailing`'s strict RSI branches false at 3219–3227, suppressing its optional call at 3149 (default disabled at 351). Audit lines 215/240 record this correctly. Comparison lines 319–325 then incorrectly say fallback `50` fails strict entry-threshold RSI comparisons “in both files.” In V8.11, `50` lies inside both default entry momentum windows (inputs 147–150) and passes the RSI subcondition at 2205–2206; it is one of the four ANDed conditions at 2208–2209. The two EAs need separate path-specific wording. |
| Restart-idempotency narrowing | **VERIFIED** | V6.37 has volatile bar/signal stamps at 579–580/597–598 and 6718–6728, but scans current positions at 605–607 and persists/reconciles OB pending tickets at 8660–8673, 8699–8701, and 8779–8781. Audit lines 213/240 and comparison lines 312–318 now accurately narrow the risk to missing atomic market-signal/deal identity and ambiguous-submission reconciliation. |

### Group 3 — V8.11 consistency

| Item | Verdict | Independent result |
|---|---|---|
| Basket-leg citation and break-even qualification | **VERIFIED** | `g_basket_legs=opened` is at 1389; 1391 resets `g_basket_peak_r`. Audit line 73 now cites the right assignment and qualifies equivalence for aligned defaults, successful intended legs, hedging semantics, and the partial-opening path at 1368–1392. Netting can make `count < g_basket_legs` true immediately at 1425. “Successful” should continue to mean broker-confirmed positions, not merely a `true` `CTrade` Boolean, as audit line 179 already warns. |
| Restart drawdown calculation | **PARTIAL** | `OnInit` resets `g_peak_balance` to current balance at 272; current drawdown then uses that reset basis and current equity at 2291–2298. Audit line 91 and comparison line 178 correctly state that floating loss can remain nonzero and that the reset can understate drawdown. Audit lines 89/91 still call persisted `g_peak_dd` the “true historical worst drawdown” that survives “regardless.” Source 2299–2303 persists only the maximum of `g_current_dd`, whose peak basis itself resets on every restart. Across repeated restarts it is not guaranteed to equal drawdown from an unbroken all-time peak. Call it the persisted maximum session-relative drawdown observed by this calculation/display statistic. |
| Current broker-held SL/TP | **VERIFIED** | `MoveBasketStops` reads current SL/TP and can modify SL at 1477–1481. Audit line 152, comparison lines 269–278, and task lines 159–163 now correctly say current broker-held values survive, not necessarily the original basket-open values. |
| Momentum versus expansion | **PARTIAL** | Source uses configurable `InpMomTF` for momentum at 2173–2235 and configurable `InpWorkingTF` for `g_expansion` at 449/453–456; the blanket gate returns at 340–344. The revised long paragraph at audit line 127 and comparison failure item 3 distinguish the measurements. Stale text remains at audit line 61 and comparison lines 156–163, which still say the setup was explicitly designed to trade the blocked “volatility expansion” state. Source comment 2213–2218 promises only a premium/discount **location-gate** exemption because a breakout expands beyond value; it does not equate that concept with `g_expansion`. Calling the interaction a verified contradiction/policy conflict is therefore still stronger than the source supports. “Verified gate interaction; intent and impact unresolved” is supportable. Audit line 55, summary row 2 at line 203, and comparison lines 159–161 also retain hard-coded M5/M15 wording where `InpMomTF`/`InpWorkingTF` are configurable defaults. |

All Markdown tables in the core package have consistent column counts. The
prior table-schema issue remains resolved.

### Group 4 and C7 equivalent — metadata and response accuracy

| Item | Verdict | Independent result |
|---|---|---|
| Preserved-artifact diff wording | **PARTIAL** | Task lines 114–126 and 325–333 now distinguish preserved artifacts from the two audit documents added under `01_BASELINE`. However, `01_BASELINE/inventory.md:7–9` still says the unscoped tag diffs are empty “against `01_BASELINE/`,” contradicting its own correctly scoped commands at 83–86 and the response's claim that scoped wording is now used everywhere. Task lines 22–23 also retain the broad “nothing in `01_BASELINE/` was modified” wording. |
| Immutability evidence attribution | **PARTIAL** | The artifacts are genuinely unchanged, but per-EA-directory diffs prove only the EA directories, not the set file or PNGs. Cite the separate set-file/PNG path diffs or tag-blob equality for those artifacts. Task lines 46–48 also say the orphaned set hash matched `IDENTITY.md`; `01_BASELINE/setfiles/IDENTITY.md` contains no hash. The EA hashes match their identity files; the set hash is recorded in the inventory and matches the preservation-tag blob. |
| Exact paths and “full history” | **CURRENT CLAIM FALSE** | `538bc39` changed seven paths: both audits, comparison, task file, `TASKS.md`, the overwritten Codex review, and the new round-three response. `79f8e5a` then changed only the task file. Files affected stops at `538bc39`, while task lines 290–323 call the list the full history through current `HEAD`; current `HEAD` is `79f8e5a`. Another hash-recording commit would recreate the same self-reference problem. Remove the “through current HEAD” guarantee or describe the latest metadata-only commit symbolically instead of trying to embed a commit's own hash in itself. |
| Acceptance/status/reviewer chain | **FAILED** | The response says these were realigned, but task acceptance lines 209–221 say third-pass fixes are “now being addressed,” Reviewer lines 337–345 say they “are being applied” and omit `TASK-001_review_response_round3.md`, while Final Decision lines 349–353 says the fixes are already applied and pending confirmation. `TASKS.md:11` likewise says “resolving now.” The checked internal-consistency criterion at task lines 198–200 is therefore false, and `TASKS.md` does not contain the claimed matching file list. |
| Direction-flip risk item | **VERIFIED** | Task lines 159–163 now include direction-flip exit, matching source 1462–1464 and the detailed audit. |
| Historical-error acknowledgment | **PARTIAL** | The response accurately acknowledges the round-two response's two false claims. Its further assertion that correct scoped wording is now used everywhere is disproved by `01_BASELINE/inventory.md:7–9`. Historical response/handover files may remain unchanged if clearly treated as historical, but current core deliverables and package-wide claims must not repeat their errors. |
| Verification-document count | **MINOR ERROR** | Response lines 117–119 say all edited sections of “all four documents” were read, while `538bc39` changed five substantive package documents (both audits, comparison, task file, and `TASKS.md`), in addition to the review and new response. Name the intended subset or use the actual count. |

## Required corrections before approval

1. Correct ROTATION visibility to the actual global condition: no surviving
   buy **or** sell candidate, with the Rotation reason still the last transient
   reason. Remove unsupported “sole candidate in that direction,”
   “common/often,” proven-maintenance-miss, and stated-purpose-conflict claims
   at audit lines 47/154/226 and comparison lines 139–152/284–296.
2. Repair the cross-EA RSI synthesis at comparison lines 319–325: V6.37
   fallback `50` fails its strict entries but has the two documented management
   effects; V8.11 fallback `50` passes its default RSI-window subcondition but
   still needs the other three momentum conditions.
3. In the V8.11 audit, replace “true historical worst drawdown” with the
   source-supported persisted session-relative maximum, and finish aligning
   audit line 61/summary row 2 plus comparison lines 156–163 with the related-
   but-distinct `InpMomTF`/`InpWorkingTF` gate interaction.
4. Correct current package metadata:
   - align `inventory.md:7–9` and the task opening with the scoped immutability
     explanation;
   - distinguish EA `IDENTITY.md` hash matches from the set file's
     inventory/tag-blob verification, and cite set/PNG-specific diff evidence;
   - remove the recursively stale “full history through current HEAD” claim;
   - align Acceptance criteria, Reviewer, Final Decision, and `TASKS.md`, and
     include the round-three response in the reviewer chain;
   - correct the response's “all four documents” verification count or name
     the four-document subset intended.

## Decision

The prior **CHANGES REQUESTED** disposition cannot be lifted. The remaining
issues are narrower than the previous pass, but they include false source
characterizations (ROTATION visibility, cross-EA RSI behavior, persisted
drawdown meaning, and expansion intent) and demonstrably inconsistent package
metadata. These are material in an audit whose acceptance criterion requires
source-backed, internally consistent documentation.

A focused documentation-only correction pass should be sufficient. No baseline
source change, profitability claim, or live-safety claim is requested or
implied.
