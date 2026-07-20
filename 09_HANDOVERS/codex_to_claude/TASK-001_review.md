# Codex Fourteenth Review - TASK-001 Round-Thirteen Response and Follow-up

**DISPOSITION: CHANGES REQUESTED**

The disposition cannot be lifted. At `81a4bf2`, the package is neither fully
source-factual nor internally consistent, so TASK-001 is **not ready to merge**
and Phase 2 should **not** begin yet. The remaining issues include executable
risk/exit semantics, formula qualifications, newly found source defects, and an
actual two-commit gap in the package's account of its own history.

Line references below are to the files as they exist at `81a4bf2`.

## Review target and method

- Branch: `claude/task-001-baseline-audit`.
- HEAD: `81a4bf2560f62bc38de42cd07c53d4cd555d9ab1`.
- HEAD parent: `3eb6ac5e2290ae504189988c2becbd6918b965ad`.
- Round-13 response reviewed:
  `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round13.md`.
- Sources independently read and traced:
  - `01_BASELINE/EA_V637/Thembabot14 Max.mq5` - 8,822 lines;
  - `01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5` - 2,397 lines.
- I checked the actual Git patches, source declarations and call sites, every
  cited function/input range, arithmetic, the comparison mirrors, and the task
  file's self-referential history. This was a static review: no compile,
  backtest, terminal, broker, restart, or concurrent-instance test was run.

The correction history after the prior reviewed commit `ce9f712` is split:

1. `3eb6ac5` added the round-13 response and modified the prior Codex review,
   `TASK-001_BASELINE_AUDIT.md`, `baseline_comparison.md`,
   `baseline_v637_audit.md`, and `baseline_v811_audit.md`: exactly six paths.
2. `81a4bf2` then modified exactly two paths:
   `TASK-001_BASELINE_AUDIT.md` and `baseline_v811_audit.md`.

Neither commit touched `TASKS.md` or a path below `01_BASELINE/`.

## Immutable-baseline verification

**PASS. Both complete EA directories, including each `IDENTITY.md`, are
byte-identical to their preservation tags.**

- `EA_V637` has tree
  `fe46191174b150c4c1e0dceb1bffc6c42a076384` at HEAD and `baseline-v637`.
  - MQ5 blob `26018c013b60e371c112cea4f57552884d1e6902`, SHA-256
    `C35BCC7E0095D60B0C672FAEEBA696B4DB8587B0AFB80E6EFBBFDC8ACCDFBC1D`.
  - `IDENTITY.md` blob `5bc1a9b4a3198f5575d9efc35ad723242ac4b2d6`,
    SHA-256
    `60172420BDE832187466D27A364977B4F71C7390DF389B4795A6200B8394E382`.
- `EA_V811` has tree
  `3bc9e68939873de57c70319ff75f3b39ffd58c75` at HEAD and `baseline-v811`.
  - MQ5 blob `f0644ad8a3ce8f7471d3e3ed8393c375977ac551`, SHA-256
    `B5740327F6D84FD7C00807001418DF0FCC3912A8101BCA2DBB55DE0E51CD1F1B`.
  - `IDENTITY.md` blob `e1ba7a7b741969d96b07db179edd9dfa82c0b44a`,
    SHA-256
    `A1286C257D32A95D18A7B2719A649DDC6FCF4EBFCBD2D71FDED20678561D367E`.

Both scoped tag diffs are empty. `git log --all --` for each complete EA
directory shows only the baseline import `0d65f95`; no later commit altered
either source or identity file.

## Independent arithmetic checks

- V6.37 contains 282 `input` declarations plus 25 `input group` headings.
- `1.18 * 1.20 = 1.416`, correctly rounded to about 1.42 where stated.
- For eight fair binary outcomes, the literal-extreme count is
  `186/256 = 72.65625%`, or 72.7%; excluding the all-loss outcome that does not
  change behavior leaves `185/256 = 72.265625%`, or 72.3%.
- Forty-eight M30 bars are 24 hours.
- V8.11's shipped sizing budget is `0.8%` of equity only in the `E >= B`
  branch. A viable normal two-leg split is about `0.4%` per leg before
  rounding. The 2% fallback is therefore 2.5 times that modeled budget in
  that branch, not a realized-loss ceiling.
- V6.37's familiar pilot ratios, `5/0.8 = 6.25` and `5/0.2 = 25`, are valid
  only under the conditions in B3 below. A default Rotation pilot instead
  compares against `0.6%`/`0.15%`, producing `8.333...`/`33.333...`.

## Round-13 response and `81a4bf2` result

The follow-up genuinely did two things the response left incomplete:

- it added accurate V8.11 body findings for the false `g_range_start` comment,
  the unrestricted 60-bar sweep scan, the hard-coded startup literals, and the
  hard-coded H1/M30 dashboard labels; and
- it removed the unsupported `narrower`/`narrower still` comparisons from
  Commit entries 2 through 9.

Those edits are verified. The sign-error finding and many other round-13
corrections also match the source. They do not resolve the findings below.
Notably, the response's C-item mapping did not track the prior review: its C2
answer addresses the prior per-leg item rather than sweep/shift formulas, and
its C3 says the threshold-floor item was already correct when the omissions
remain in the current audit.

## A. Package and Git-history findings

### A1. The canonical history omits the `81a4bf2` follow-up

**Document:** `TASK-001_BASELINE_AUDIT.md`, Files affected 237-244,
Acceptance pass 13 at 550-584, Commit entry 16 at 893-898.

These locations describe one thirteenth correction commit, durably located as
the first commit after `ce9f712`. That is `3eb6ac5`, whose stated six-path set is
correct. They never record its child `81a4bf2`, which supplied two additional
round-13 fixes. Pass 13's singular "current symbolic correction commit" is
therefore incomplete. Add the exact two-commit history, mark pass 13 addressed
by `3eb6ac5` plus `81a4bf2`, and add pass 14 using durable applied/pending-review
wording until this review is answered.

### A2. Three current process-history statements are false

- `TASK-001_BASELINE_AUDIT.md:957-959` says the round-13 response filename is
  stated before its own commit exists. `3eb6ac5` exists and added that file.
- `TASK-001_review_response_round13.md:151-155` calls the `3eb6ac5` set a
  "five-path list" while enumerating six paths; Git confirms six.
- `baseline_v811_audit.md:7,30-31` labels material added by `81a4bf2` as
  "added fourteenth-pass review." Git and the commit subject establish it as
  an unlabeled follow-up completing round 13 before this fourteenth review.

### A3. Unverifiable process attestations are presented as established history

**Document:** `TASK-001_BASELINE_AUDIT.md:314-317,624-628,634-636`.

The assertions that two agents read both entire files, independently rechecked
every line, and visually read all screenshots are not derivable from the
repository or Git history. They may be true author attestations, but should be
explicitly attributed as such rather than presented as independently verified
facts. This is especially important in a file whose Acceptance/Reviewer/Commit
sections purport to be canonical evidence.

### A4. The task summary still states attempted actions as guarantees

**Document:** `TASK-001_BASELINE_AUDIT.md:45,302-304`.

- The V8.11 mechanism is not a "hard 45-minute time exit." Source 1455-1460
  checks strict elapsed time on a later tick, `CloseBasket` 1485-1500 ignores
  trade results, and the restart state gap at 1416-1417 can suppress it. It is
  a 45-minute close-attempt trigger.
- V6.37's `CloseAllOurPositions` does not prove positions were force-closed;
  source 3399 ignores `PositionClose`'s result. It attempts same-magic closes.

## B. V6.37 findings

### B1. `LevelInvalidated` does not retire a level

**Document:** `baseline_v637_audit.md:19`.

Source `LevelInvalidated` 7051-7072 returns true only while the newest
consecutive closes remain beyond the level. A newer close back on the accepted
side returns false; no retired state is stored. Replace "retires" with a
current-run invalidation description. The same lifecycle distinction should be
used wherever this behavior is summarized.

### B2. The "three-point trendline" and break geometry are overstated

**Documents:** `baseline_v637_audit.md:28,31`; `baseline_comparison.md:75`;
`TASK-001_BASELINE_AUDIT.md:31`.

`BuildThreePointTrendLine` 6315-6369 finds three monotonic swing prices, but
constructs its line only through the older and recent points at 6353-6356 or
6362-6365; it never tests the middle swing's distance from that line. In
addition, `EvaluateTrendBreaker` 2582-2614 projects each line once at
`exec[1].time`, then `ThreeCandleBreak` 6388-6403 compares all confirmation
closes to that single constant level rather than projecting the line at each
bar's time. Document the actual two-anchor construction and constant-level
confirmation behavior.

The package taxonomy also drifts: source has four entry implementations
(`EvaluateSRChannel` 2452, `EvaluateTrendBreaker` 2562,
`BuildTrendlineTouchSignal` 7573, and `BuildTrendlineBreakRetestSignal` 7663)
grouped into three conceptual mechanisms. "Three implementations" and
"triple-redundant" are not the precise canonical description.

### B3. Pilot identity and pilot-ratio summaries remain wrong

**Documents:** `baseline_v637_audit.md:177`, summary row 6 at 237;
`baseline_comparison.md:214-215,486-492`.

`PilotStage()==0` at source 2865 is only symbol/magic state. It does not require
a new/fresh trend, a particular setup, direction, ticket, or even nonzero
stored trend. Therefore "least-confirmed trade of a fresh/new trend" is false.

The 6.25x/25x ratios require all of: `E >= B`, volatility factor 1, no news
reduction, no already-open add-on reduction, a non-Rotation setup, and (for the
XAU number) a case-sensitive match to `InpXAUUSDSymbolKey` at 5766-5770.
Rotation sets `g_rotation_sizing` at 2754 and applies the default 0.75 factor at
2812-2817 before the pilot branch, so otherwise-flat Rotation budgets are
0.6%/0.15% and the ratios are 8.333x/33.333x. Lower runtime factors make the
ratio larger still. Thus "up to 6.25x/25x at shipped defaults" is not valid.

### B4. Rotation/add-on "reduced risk" is only a budget haircut

**Documents:** `baseline_v637_audit.md:47,180`;
`baseline_comparison.md:217`.

The 0.75 factor reduces `risk_cash` at 2812-2818 and 5910-5911, but the stage-0
pilot branch 2865-2879 ignores that cash target and the min-lot compatibility
path 2884-2927 can exceed it. The source enforces a lower modeled budget, not a
guarantee of lower submitted or realized exposure. "Checks out," "enforced,"
and "always-on de-risking" need this distinction.

### B5. New: pending fills are associated by direction, not order provenance

**Document:** add to the V6.37 pending-order/journal findings and summary, and
synthesize in `baseline_comparison.md`.

`OnTradeTransaction` 688-710 treats any same-symbol/magic `DEAL_ENTRY_IN` as an
OB pending fill when the corresponding direction key exists. It never compares
the deal/order provenance to the stored pending ticket before logging and
deleting that tracking state. Pending orders are not included by
`CountOurPositions` in the OnTick gate at 605-607, so another same-direction
market fill while an OB limit rests is reachable. That fill can be mislabeled,
erase the real pending order's tracking, and leave the actual pending live and
untracked.

### B6. The NFP builder does not prove a post-release first retest

**Documents:** `baseline_v637_audit.md:136` and the NFP comparison at
`baseline_comparison.md:246-250`.

`BuildNewsDisplacementSignal` 7299-7306 accepts any qualifying spike in the
last 18 M5 bars; it never ties that candle's time to the configured release.
If `spike==2`, `m5[1]` both completes the FVG boundary at 7314-7321 and is used
as the alleged retest at 7330-7338. The intervening-bar loop is empty. This is
not a guaranteed "first FVG retest after a displacement spike," much less a
release-linked spike.

### B7. New: disabling the journal also disables live learning updates

**Document:** add to the V6.37 Journal/learning section and summary.

`OnTradeTransaction` returns at source 662-663 when
`InpUseTradingJournal=false`, before `UpdateStrategyMemory` at 759.
`LoadJournalMemory` 3544-3551 is independently gated by
`InpUseJournalLearning`. With journal off and learning on, the EA can load old
memory during initialization but never update outcomes during that run. The
two inputs are not operationally independent.

### B8. Structure and fractal summaries contradict the corrected body

- `baseline_comparison.md:72` calls `AnalyzeStructure` one consistent V6.37
  definition. Live source also uses `FindRecentStructureShiftLevel` 1176 onward,
  and `BuildBOSRetestSignal` 7777-7788 combines mechanisms.
- `baseline_v637_audit.md` summary row 13 at 244 and
  `baseline_comparison.md:147-150` still say the line-201 comment implies one
  shared fractal definition. It only promises that `InpStructureSwingDepth`
  covers SR/structure/FVG. The actual contradiction is narrower and concrete:
  the FVG path uses `InpStructureSwingDepth` through `AnalyzeStructure` at 1593
  but `InpFractalDepth` through `FindTwoConfirmedSwingsBefore` at 1156. The
  broader source also has `InpMajorSwingDepth` and hard-coded depth 2.

### B9. Exit, target, and trade-result wording remains too strong

**Document:** `baseline_v637_audit.md:105,120,123,127,204` and summary row 16
at 247; mirrors at `baseline_comparison.md:224-234,368-375`.

- Position closes and modifications are attempts, not verified state changes:
  `PositionModify` at 7135 and `PositionClose` at 7157/3399 are not followed by
  a broker `ResultRetcode` check. The giveback path deletes peak state at 7158
  regardless of close outcome.
- The profit-lock candidate is checked for improvement at 7130, then
  `EnsureValidStops` can move it at 7134 without a second improvement check. It
  is not guaranteed to lock exactly 50% of peak gain.
- `FindNextQualifiedM15Target` computes TP2 only as an intermediate. Stored/live
  stages are TP1 -> TP3 -> runner at 6069-6077 and 6140-6166, not
  TP1 -> TP2 -> TP3. A pending fill stores risk at 697-699 but can initialize
  the ladder later through `EnsureStagedTargetState` 6094-6120; it is not always
  built at entry. The timeframe is configurable `InpStructureTF`, M15 only by
  default.
- A true `CTrade` call in the pending path is treated as successful placement,
  not proof that a trade executed or filled. Keep the missing result-code/order-
  existence defect, but distinguish market-open assumptions from pending-order
  placement assumptions.

### B10. The learning conclusion mixes fact with hypothesis, and comparison
recommends reuse without the known sign fix

**Documents:** `baseline_v637_audit.md:171`;
`baseline_comparison.md:429-439`.

The multiplier ordering and `1.18*1.20=1.416` are facts. Claims that this will
increase selection frequency and create future confirming data require
candidate distributions and trading evidence, so that causal portion is a
hypothesis. More importantly, the comparison recommends reusing the learning
pattern conditioned only on fixing the regime-bench gap. Source 3697-3700 and
3729-3733 has the now-confirmed sign error that boosts a net-losing bucket when
its win rate exceeds 50%; any reuse recommendation must require fixing that too.

### B11. Executable timeframe/status text is inconsistent with configuration

**Document:** add a broader runtime-reporting finding to `baseline_v637_audit.md`
and its summary.

Examples: source 2625/2639 reports "3 M15" and "H1/H4" although the count and
timeframes come from `InpTrendBreakConfirmCandles`, `InpTrendExecutionTF`, and
`InpTrendHigherTF1/2` (whose shipped higher-TF pair is M15/H1, not H1/H4).
FVG runtime reasons/tokens at 1697-1713 say M15/M5/H1 although the builders use
configurable `InpStructureTF`/entry inputs. Similar literal timeframe/status
drift occurs at 1374-1375, 1455-1456, 3171, and 8787. These are executable
operator messages, not harmless variable names.

### B12. Two gate/structure descriptions omit source conditions

**Document:** `baseline_v637_audit.md:56,60,149`.

- Both self-confirmed bypasses at source 1895 and 2001 require
  `InpSelfConfirmedBypassFilters`; the audit says the self-confirmed test acts
  alone and that such setups skip gates 1-2. Qualify this with the input being
  enabled (true only at shipped default).
- `AnalyzeStructure` 4830-4838 treats `ms.trend==0` with the aligned/BOS branch
  because the test is `>=0`; neutral is not a trend that "already agreed."
  Say aligned-or-neutral versus opposing.

## C. V8.11 findings

### C1. Sweep/shift and final-stop formulas are still incomplete

**Document:** `baseline_v811_audit.md:25`.

The actual pool range is
`4..min(copied-2, 4+max(10,InpSweepLookback))` at source 1008-1012. The shift
range is `2..min(copied-2, 2+max(3,InpShiftLookback))` at 1036-1049, which is
seven candidate bars at the shipped lookback 6, not simply six. The final stop
path at 1292-1310 adds spread, may rebuild from entry for the minimum floor,
may reject for the maximum cap, normalizes the stop, and recomputes distance.
The current prose omits those material clamps and transformations.

### C2. Multiple configurable thresholds omit source-enforced floors

**Document:** `baseline_v811_audit.md:29,39,43,49,72,77,79,83`.

The source actually uses:

- cluster tolerance `atr*max(0.05,InpClusterTolATR)` and touch count
  `max(2,InpClusterMinTouches)` at 608/623/654/1075;
- FVG minimum `max(3*_Point, atr*max(0.03,InpFVGMinGapATR))` at 830;
- BOS lookback `max(4,InpBOSLookback)` at 1218;
- pin wick `2*max(body,_Point)` at 1707/1714;
- TP1 `max(0.3,InpTP1R)` at 1363;
- break-even arm `max(0.3,InpBasketBreakEvenAtR)` at 1426;
- trail start/step `max(0.5,InpTrailStartR)` and
  `max(0.2,InpTrailStepR)` at 1438/1440; and
- giveback arm/floor `max(0.3,InpGivebackArmR)` and
  `max(0,InpGivebackFloorR)` at 1448-1449.

The audit presents the inputs without these effective minima.

### C3. `g_last_action` is not file-journaled

**Document:** `baseline_v811_audit.md:73`.

Source 1394-1398 assigns `g_last_action` and conditionally calls terminal
`Print`; dashboard line 2111 displays it. There are no file-journal calls in
V8.11. "Printed/journaled" conflates terminal output with a journal that the
same audit correctly says does not exist.

### C4. Break-even and giveback prose infers causes and successful execution

**Documents:** `baseline_v811_audit.md:77,83`;
`baseline_comparison.md:228-234,331`; `TASK-001_BASELINE_AUDIT.md:45`.

At source 1425-1431, break-even triggers on
`rr >= threshold OR count < g_basket_legs`; the code never establishes that a
missing leg "banked." A manual close, SL, rejection/state mismatch, and netting
collapse can all satisfy it. `MoveBasketStops` 1467-1482 is unchecked, yet
`g_basket_be_done` is set true.

The giveback path 1448-1453 only attempts unchecked `CloseBasket`; 1485-1500
announces closure without validating results. Its status at 1451 clamps a
negative R to zero and can say "banked +0.00R" while attempting to close a
loss. Replace "closes/enforced/raises" with exact trigger-and-attempt behavior.

### C5. Risk prose confuses nominal input, modeled risk, and realized risk

**Document:** `baseline_v811_audit.md:124,128,130`, summary rows 5 and 9 at
217/221; mirrors at `baseline_comparison.md:216-217,498-503`.

- "Sized 1% budget" is false. `RiskBudgetCash` 1505-1514 yields 0.8% only for
  `E>=B`, less for `B>E>0.2B`, and zero for `E<=0.2B` at shipped inputs.
- `OpenBasket` models risk from requested entry and stop; it never reads actual
  fills. Therefore "realized loss," "actual risk," and a realized 2.5x cap are
  unsupported. Slippage/gaps can exceed the modeled amount.
- About 0.4% per leg requires a viable normal two-leg split. A reduced one-leg
  split receives about 0.8% in the `E>=B` case; the minimum-lot fallback differs.
- At the edge `0<E<1`, source 1337 divides by `max(1,E)`, not by true equity.
  The reported `min_risk_pct` understates the true percentage and the nominal
  2% fallback ceiling can be exceeded in true-equity terms.

### C6. Signal scores are not tick-dynamic

**Documents:** `baseline_v811_audit.md:116`;
`baseline_comparison.md:289-292`.

The score inputs are fixed and the bonuses use runtime market evidence, but
`OnTick` returns before signal construction unless a new entry-timeframe bar
has appeared at source 301-302. Hierarchy and momentum also use slower caches.
Call the scores market-dependent/bar-updated, not tick-dynamic.

### C7. `BuildStructureMarks` is not universally forming-bar independent

**Document:** `baseline_v811_audit.md:152`.

The audit's control-flow conclusion holds only at shipped
`InpSwingDepth=2`. In `BuildStructureMarks` 487-573, a configurable depth
`D>=3` lets candidate `i=D` read `r[0]` through `IsSwingHigh/Low`, while its
newer-break loop can reach a valid `j>=2` and emit a mark. The traded decision
paths remain closed-bar clean, but the universal statement that no drawable
output can depend on the forming bar is false for supported configurations.

### C8. New: structure-mark retention and first-label semantics are wrong

**Document:** add to the `BuildStructureMarks` contradiction and V8.11 summary.

`BuildStructureMarks` starts at an index up to 90, decrements toward newer
bars, and stops after four marks. It therefore preferentially keeps the oldest
four qualifying breaks in the scan, contrary to the "Recent" comment at source
487. `prior_dir` starts at zero, so the first stored bullish or bearish break
is always labeled CHoCH at 507/530 despite there being no prior stored leg whose
direction changed.

### C9. New: daily-limit numerator and denominator have different anchors

**Document:** add to V8.11 daily-loss findings and summary/comparison.

`ResetDailyState` 1529-1536 stores midnight as the history boundary but current
(or restart-time) equity as `g_day_start_equity`. `TodayClosedProfit` 1566-1585
replays closing deals since midnight; `CheckDailyLimits` 1544-1558 then adds
current floating position profit. Across a mid-day restart or midnight with
open exposure, this is not account change from the stored equity baseline.
Entry-side commissions are excluded by the exit-deal filter, and floating swap
is not separately included. The shipped 3% daily-loss limit is active, so this
is operational rather than display-only.

### C10. News/session summary and comparison misstate recurrence

**Documents:** `baseline_v811_audit.md` summary row 11 at 223;
`baseline_comparison.md:251-255`.

The three rejected input forms (empty, too short, or colonless) apply to
`InNewsWindow`, not `SessionOK`; the summary should not combine both filters.
Source 2339-2346 rebuilds the configured news times on the current date each
call, so a valid window recurs daily. The actual limitations are no
date/weekday/event schedule and truncation rather than wraparound for windows
crossing midnight.

### C11. The new range findings are correct but not propagated

**Documents:** `baseline_v811_audit.md:30-31` versus summary 209-230;
`baseline_comparison.md:268-272`.

The new body findings correctly show that `g_range_start` is a fixed-lookback
drawing timestamp and the 60-bar strong/weak scan is not scoped to boundary
formation. But neither appears in the summary. The comparison still says range
visuals use exactly the trade globals and calls BOS/CHoCH the sole visual/trade
disconnect. Only boundary prices/equilibrium are shared. `g_range_start` and
`g_low_swept/g_high_swept` are drawing/dashboard semantics, not trade inputs.

### C12. Additional executable status strings remain inconsistent with inputs

**Document:** add to the V8.11 runtime-reporting finding and summary.

Beyond the four messages added at `81a4bf2`, source still hard-codes M1 at
1060/1242/1266 although `InpEntryTF` is configurable, and M5 at
1147/1159/1190/1201/2050/2052 although `InpRefineTF` is configurable. Momentum
conditions at 2247-2248/2267-2268 allow a close short of the extreme by an ATR
buffer, but status text at 2261-2262/2280-2281 claims an actual breakout
above/below the extreme.

### C13. V8.11 boundary "retirement" is also non-persistent

**Document:** `baseline_v811_audit.md:29`.

`FindClusterBoundary` 657-669 rejects the boundary only during the current
newest consecutive-close run. A recovery close makes it eligible again; no
retired flag is stored. As in V6.37, "retires" is too strong.

### C14. The V8.11 summary is incomplete

**Document:** `baseline_v811_audit.md`, summary table 209-230.

In addition to C8-C12, the four verified body findings added by `81a4bf2`
(range origin, unrestricted sweep scan, startup literals, dashboard timeframe
labels) are absent from the canonical contradiction/risk table. This omission
has already allowed an affirmative comparison claim to remain false. Propagate
all confirmed body contradictions, including the new findings in this review.

## D. Remaining comparison-only drift

### D1. The correctness disclaimer conflicts with an affirmative claim

**Document:** `baseline_comparison.md:12-13,78`.

The opening disclaims correctness claims, while row 78 says V8.11's "core math
correct." The defensible statement is limited: requested-price arithmetic
splits one modeled budget when the intended multi-leg loop succeeds, subject to
rounding, submission success, fills, slippage, and the edge cases in C5. It is
not blanket core correctness.

### D2. The V8.11 structure row omits a traded definition

**Document:** `baseline_comparison.md:72`.

The row mentions `StructureTrend`/M30 and drawing-only `BuildStructureMarks`,
but live `BuildBOSRetest` 1209-1271 is another traded structural-break
definition. The row is incomplete for both EAs; B8 states the V6.37 half.

### D3. Candlestick-helper count is wrong

**Document:** `baseline_comparison.md:444-445`.

V8.11 has four shared pin/engulfing helper definitions and eight calls across
four setup builders, not "one definition, four call sites." State the helper
set and builder-level reuse accurately.

### D4. A cross-reference has no local target

**Document:** `baseline_comparison.md:216-217`.

"See finding #16" is ambiguous because the comparison has no numbered finding
16. Name and link the V8.11 audit's summary row 16 explicitly.

### D5. The comparison omits material source findings

**Document:** `baseline_comparison.md`, especially risk/exit/reuse conclusions
at 224-234, 429-445, and 486-503.

The comparison must synthesize, rather than silently omit, at least the newly
confirmed behaviors that affect a future combined engine: V6.37 pending-fill
misassociation, trendline projection geometry, journal/learning toggle
coupling, NFP spike/retest weakness, and the learning sign error; V8.11 daily-
limit anchor mismatch, configurable-depth forming-bar mark path, old-first
mark retention/first-CHoCH label, and range/status-message divergence. Several
current affirmative comparison statements are false precisely because body
findings were not propagated.

## Required disposition after correction

The next response should address every item above against source and Git, update
the canonical history for both `3eb6ac5` and `81a4bf2`, and propagate confirmed
findings through each individual summary and `baseline_comparison.md`. Until
that is independently reviewed, the disposition remains **CHANGES REQUESTED**;
TASK-001 is not ready to merge and Phase 2 should not begin.
