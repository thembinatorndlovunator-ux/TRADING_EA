# Codex Third Review — TASK-001 Round-Two Response

**Disposition: CHANGES REQUESTED — NOT LIFTED**

The second correction pass resolves most of the prior review, but the package
still contains source-factual and internal-consistency errors. The remaining
work is documentation-only. Neither immutable baseline EA should be edited for
TASK-001.

## Review target and method

- Response reviewed:
  `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round2.md`.
- Correction commits reviewed: `4a6946b` and its metadata follow-up
  `7319306` (current `HEAD`).
- Every A, B, and C response item was checked against the actual V6.37/V8.11
  source, the current audit documents, and the relevant Git history. Claims in
  the response were not treated as evidence.
- Static review only. No MetaEditor compilation, Strategy Tester run, broker
  connection, restart simulation, or netting/hedging execution test was run.

Source identity remains intact:

| File | Lines | SHA-256 |
|---|---:|---|
| `01_BASELINE/EA_V637/Thembabot14 Max.mq5` | 8,822 | `C35BCC7E0095D60B0C672FAEEBA696B4DB8587B0AFB80E6EFBBFDC8ACCDFBC1D` |
| `01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5` | 2,397 | `B5740327F6D84FD7C00807001418DF0FCC3912A8101BCA2DBB55DE0E51CD1F1B` |
| `01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt` | 100 | `EA9452D4475D55F1AADD35A6F8F83B76C6046E2118D02AA5A918E673AF4BCE96` |

`git diff c61903f..7319306 -- 01_BASELINE` is empty, as are the
artifact-scoped tag diffs for `01_BASELINE/EA_V637` and
`01_BASELINE/EA_V811`. The original EAs and set file are therefore unchanged.
This does **not** make `git diff <baseline-tag> -- 01_BASELINE` empty: the
initial audit commit added `01_BASELINE/inventory.md` and
`01_BASELINE/screenshots/visual_notes.md` after those tags.

## Section A — V6.37 audit and comparison

| Item | Verdict | Independent verification |
|---|---|---|
| A1 — dormant partial-close/netting issue | **VERIFIED** | `InpUsePartialTargets=false` is declared at source 345; the live path is additionally gated by `!staged_targets` at 3059–3061; `ClosePartialPosition` calls `trade.PositionClosePartial` at 6214–6228. Audit lines 194 and 237 now record the default-dormant incompatibility accurately. |
| A2 — mixed gate/score pipeline | **VERIFIED** | `SelectBestIndependentSignal` has hard filters at 919–924, a score-only OB modifier at 927, and learned score transformation at 928; the later direction-gap test is at 895. Audit lines 138–155 and comparison lines 100–106 no longer present all stages as five serial AND gates. |
| A3 — ROTATION classification | **PARTIAL** | The mechanics are correct: `ROTATION_*` is self-confirmed at 7534–7540, bypasses the value-area/SR gates at 1895 and 2001–2003, and is rejected by expansion routing at 7513–7525. The package still calls the veto “silent” at audit line 47 and later says it is not silent; lines 226 and comparison 145–146 overstate dashboard visibility. Source 7524 only sets `g_last_value_filter_reason`; it reaches the dashboard only on the no-surviving-candidate path at 885–890 and is replaced at 908 when a candidate survives. Audit line 154 and comparison lines 276–282 also still imply this was a missed defect/setup condition rather than an unresolved policy choice. |
| A4 — RSI fallback scope | **PARTIAL** | Fallback `50` at 6526/6532 fails the strict entry tests at 2224/2232 and 2670/2685, while it can satisfy the inclusive RSI conjunct in `MomentumStillFavorable` at 3205–3206. The revised audit captures that effect, but omits another management effect: the same fallback makes both strict branches of `MomentumFailing` false at 3219–3227, suppressing that optional exit reason at 3149 (`InpExitOnMomentumFailure=false` by default at 351). Comparison lines 298–302 still make the blanket claim that both EAs accept the fallback as neutral rather than failing closed. |
| A5 — daily-close scan wording | **PARTIAL** | Summary row 1 and the comparison were corrected. Detailed audit line 104 still says every other position scan filters by symbol and calls `CloseAllOurPositions` the sole exception, despite identifying the magic-only `GetOpenProfitForMagic` scan at source 3373–3387 in the same paragraph. Its per-symbol-intent conclusion is also stronger than audit line 105's acknowledged per-magic/account-wide alternative. |
| A6 — severity alignment | **VERIFIED** | Summary row 1 at audit line 223 now makes the forming-bar finding #14 the category-topping blocker and correctly treats the daily-close risk as threshold-gated; inputs 120–123 default to zero. |
| A7 — `SetMarginMode` and score-gap citation | **VERIFIED** | V6.37 contains neither `trade.SetMarginMode()` nor an `ACCOUNT_MARGIN_MODE` branch. The false reference is gone. `InpMinimumScoreGap` is declared at source 73 and used at 895, as the corrected audit now states. |

One related summary inconsistency also remains: audit line 240 says there is
“no reconciliation against existing positions/deals on restart,” although the
source scans current positions at 605–607 and persists/reconciles OB pending
tickets at 8662–8673, 8699–8701, and 8780–8781. Audit line 213 already has the
supportable narrower finding: no persisted atomic **market-signal/deal**
identity and no reliable reconciliation of ambiguous submissions. Comparison
lines 298–302 should use that same scope instead of saying all duplicate-signal
protection is runtime-only.

## Section B — V8.11 audit and comparison

| Item | Verdict | Independent verification |
|---|---|---|
| B1 — FVG lifecycle wording | **PARTIAL / PACKAGE CLAIM FALSE** | `ScanFVG` checks prior touches only through index 2 at 841–843/853–855, omits trigger bar 1, stores no consumed flag, and refreshes only on a new `InpRefineTF` bar at 387–395. Audit line 37 and comparison lines 74/319–323 now capture that nuance. `TASK-001_BASELINE_AUDIT.md:34` nevertheless still says unqualified “first-return-only FVG,” directly contradicting response B1's claim that it was removed there. |
| B2 — summary table schema | **VERIFIED** | Audit lines 200–216 use the declared four-column schema consistently. A mechanical pipe-count check found no remaining malformed Markdown table in the audit package. |
| B3 — momentum tautology/timeframe | **MOSTLY VERIFIED** | Because the extreme at 2240–2245 includes `m[2]`, the `m[2].close` conjuncts at 2248/2268 are tautological; the separate `m[1].close` comparisons remain meaningful and are relaxed by `buf`. The corrected analysis says this. Source 2230 copies configurable `InpMomTF`, default M5 at 142. Audit line 57 is precise, but line 55 and comparison lines 155–157 still use unqualified M5 shorthand despite the response claiming both audit sections were corrected. |
| B4 — requested fills and break-even semantics | **PARTIAL** | Audit line 65 correctly says requested entry/stop: source 1286–1287 samples the request once and 1376 submits it for every leg, while actual fills can differ and netting can collapse legs. Audit line 73 correctly exposes netting's immediate `count < g_basket_legs` risk at 1425, but cites source 1391 for the basket-leg assignment; the assignment is at **1389**, while 1391 resets peak R. Its claim that the two break-even triggers do not diverge under hedging also requires current defaults, independently aligned inputs, and a fully successful basket; partial submission is possible at 1368–1392. |
| B5 — runner-trail summary | **VERIFIED** | With two default legs (72–74), TP2=1.5R (76), and trail start=1.5R (86), the shipped trail is a no-op at 1362–1366/1437–1445. Row 4 correctly says lowering the start activates the trail before TP but does not raise the unchanged final TP ceiling. |
| B6 — peak-drawdown condition | **VERIFIED IN ROW 3; STALE ELSEWHERE** | Summary row 3 correctly limits the restart defect to a prior true peak above restart balance. `OnInit` rebases `g_peak_balance` at 272; `UpdateDrawdownGuard` uses balance/equity at 2291–2296. Detailed audit line 91 still says current drawdown immediately becomes approximately zero, which is not necessarily true when floating loss survives in equity. Comparison line 174 still states the reset effect unconditionally. The accurate statement is that the prior peak component is forgotten and current drawdown can be understated. |
| B7 — current SL/TP, RSI, and normalization | **PARTIAL** | V8.11 audit lines 152, 194, 215, and 216 now correctly identify current broker-held SL/TP, scope fallback RSI to one of four ANDed conditions at 2205–2209, and cite `NormalizePrice` at 1798. Comparison line 269 still says the **original** basket-open SL/TP survives, although `MoveBasketStops` can modify SL at 1477–1481. |
| B8 — momentum versus expansion | **PARTIAL** | Comparison lines 152–163 correctly say the two states are related, not identical, and that opportunity quality is empirical. Source uses configurable `InpMomTF` in the momentum engine (2173–2235; M5 default at 142) and `InpWorkingTF` in the expansion flag (449/453–456; M15 default at 52); the blanket return is at 340–344. Audit line 127 still first calls them “exactly this condition” and “the same M15-ATR-expansion condition,” then concedes they are not definitionally identical. Comparison lines 276–282 retain the broader unsupported claim that the setup was built to trade the blocked condition. The source comment at 2213–2218 says price expansion beyond value, not the separately defined `g_expansion` state. |

## Section C — task metadata and response accuracy

| Item | Verdict | Independent verification |
|---|---|---|
| C1 — set provenance | **VERIFIED** | The set file has 79 key/value lines and 11 sections. Exact-name comparison finds zero keys matching either EA's input identifiers; `MagicNumber=123456` differs from V6.37's 312003 and V8.11's 800001. “Not a usable native preset for either baseline; provenance unresolved” is the supportable conclusion and is now reflected in the task evidence section. |
| C2 — file breakdown | **PARTIAL** | Initial and first-pass files are distinguished. The second-pass block at task lines 92–96 still contains a placeholder instead of commit `4a6946b` and omits the modified Codex review path. The actual `4a6946b` path set is the four audit/task documents, `TASKS.md`, the overwritten Codex review, and the new round-two response. Follow-up `7319306` then modifies the task file again. |
| C3 — stale “no review” statements | **VERIFIED AS REQUESTED** | The old claims that no review occurred or that a second read was pending are gone. Separate current status/history inconsistencies are covered under C5/C6. |
| C4 — severity/protection wording | **MOSTLY VERIFIED** | The task now leads with the V6.37 completed-candle blocker and qualifies the threshold-gated daily-close risk and surviving V8.11 broker/daily-lock protections. Its V8.11 dynamic-control list at lines 131–133 still omits direction-flip exit, present at source 1462–1464 and listed in the detailed audit. |
| C5 — commit/path history | **PARTIAL / CURRENT CLAIM FALSE** | `3f69469` and `4a6946b` are recorded, but the section calls itself the “full commit history” while omitting current `HEAD` follow-up `7319306`. More importantly, task lines 276–277 say no file under `01_BASELINE` was touched by any commit in the history; `c61903f` added `01_BASELINE/inventory.md` and `01_BASELINE/screenshots/visual_notes.md`. Only the preserved EA/set/screenshot artifacts remained untouched. |
| C6 — status consistency | **PARTIAL** | The acceptance checkbox remains open and the Final Decision correctly awaits review. But acceptance lines 178–185 and `TASKS.md:11` say the second-pass corrections are still being resolved, while Final Decision lines 290–296 say they were applied and await confirmation. The reviewer chain at task lines 281–284 also omits `TASK-001_review_response_round2.md`. After this review, the status must record a third changes-requested pass. |
| C7 — response/diff accuracy | **FAILED** | The response correctly acknowledges that the predecessor's unscoped tag diffs were not empty, and its actual verification commands at response lines 127–129 use the correct EA subdirectories. But response lines 120–121 then make the new false claim that `git diff <tag> -- 01_BASELINE` is empty. It is not: the initial audit's inventory and visual-notes additions appear. Use the exact EA directories and separately identify the preserved set/PNG blobs when making an immutability claim. |

## Required corrections before approval

1. Remove the remaining unqualified FVG claim at
   `TASK-001_BASELINE_AUDIT.md:34`.
2. Make the V6.37 package internally consistent:
   - describe the ROTATION reason as a transient value that is only
     conditionally surfaced, and retain policy-ambiguity framing at audit
     lines 47/154/226 and comparison lines 139–148/276–282;
   - replace the still-universal scan claim at audit line 104;
   - add the `MomentumFailing` fallback effect and make RSI wording
     path-specific at audit line 215/summary row 18 and comparison 298–302;
   - narrow summary row 18/comparison restart wording to volatile market-signal
     identity rather than denying existing-position and pending-order
     reconciliation.
3. Finish the V8.11 consistency pass:
   - correct `g_basket_legs` citation 1391 → 1389 and qualify the hedging
     break-even equivalence at audit line 73;
   - correct audit line 91 and comparison line 174 so restart drawdown impact
     is conditional and need not become zero;
   - change comparison line 269 from original to current broker-held SL/TP;
   - remove the remaining exact/same-condition expansion claims at audit line
     127 and comparison lines 276–282;
   - use `InpMomTF`/`InpWorkingTF`, with M5/M15 identified as defaults, where
     the configured timeframes matter.
4. Repair task/response metadata:
   - replace the false whole-`01_BASELINE` diff/touch claims with exact
     artifact-scoped checks;
   - record the exact `4a6946b` paths and follow-up `7319306` in Files affected
     and Commit history;
   - align Acceptance criteria, Final Decision, `TASKS.md`, and the reviewer
     chain with this third review and the round-two response;
   - include direction-flip exit in the task's list of V8.11 dynamic controls
     lost after restart.

## Decision

The prior **CHANGES REQUESTED** disposition cannot be lifted. Core source
analysis, source identity, table repair, set provenance, partial-close coverage,
and most requested precision corrections now verify, but the response's B1 and
C7 claims are demonstrably false and the remaining A/B/C inconsistencies are
material to an evidence-based audit.

A focused documentation-only correction and consistency pass should be enough
for the next review. No baseline source change, profitability claim, or live-
safety claim is requested or implied.
