# Codex Independent Review — TASK-001 Baseline Audit

**Disposition: CHANGES REQUESTED**

The baseline files were preserved correctly, and both headline concerns in the
handover are supported by the source. The audit package is not ready to approve,
however, because its closed-bar conclusion for V6.37 is false, several important
account-mode and trade-result risks are missing or understated, and a number of
factual/documentation claims need correction.

This disposition applies to the accuracy and completeness of the TASK-001 audit
documents. It does not authorize changes to either immutable baseline EA.

## Scope and method

- Reviewed commit: `c61903faf84412029579ba6687234129929e05d7` on
  `claude/task-001-baseline-audit`.
- Re-read the cited source ranges in both EAs and traced their callers and state
  transitions. I did not accept the handover's conclusions as evidence.
- Compared relevant MQL5 behavior with the official documentation linked below.
- Static review only: no MetaEditor compilation, Strategy Tester run, broker
  connection, restart simulation, or netting/hedging execution test was performed.
- No source or baseline file was modified.

Source identity independently verified:

| File | Lines | SHA-256 |
|---|---:|---|
| `01_BASELINE/EA_V637/Thembabot14 Max.mq5` | 8,822 | `C35BCC7E0095D60B0C672FAEEBA696B4DB8587B0AFB80E6EFBBFDC8ACCDFBC1D` |
| `01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5` | 2,397 | `B5740327F6D84FD7C00807001418DF0FCC3912A8101BCA2DBB55DE0E51CD1F1B` |
| `01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt` | 100 | `EA9452D4475D55F1AADD35A6F8F83B76C6046E2118D02AA5A918E673AF4BCE96` |

## Review findings

### 1. BLOCKER — V6.37 does use a forming candle in live decision paths

The audit's blanket conclusion that confirmed-pattern decisions are closed-bar
only is refuted.

- Every `CopyRates` array I traced is set as a series array, so logical index `0`
  is the current, incomplete bar. This agrees with the official
  [`CopyRates`](https://www.mql5.com/en/docs/series/copyrates) semantics.
- `IsBullishInsideFalseBreak` reads `rates[0].close` at line 6462.
- `IsBearishInsideFalseBreak` reads `rates[0].close` at line 6470.
- Those functions feed `HasBullishCandlePattern` and
  `HasBearishCandlePattern` at lines 6473–6484.
- The pattern helpers are live signal evidence at, among other places,
  1115/1119, 1655/1657, 2364/2370, 2473/2487, 7334/7336,
  7618/7634, 7722/7726, 7820/7824, 7977/7999, and 8513/8528.

`OnTick` admits one evaluation on a new entry bar at lines 579–580. On a normal
new bar, `rates[0]` is still incomplete; on reinitialization during a bar it is
both incomplete and already moving. This is not future-candle look-ahead, but it
is an intrabar, path-dependent input that violates the project's completed-candle
rule and can be the alternative that makes a pattern pass.

Most other V6.37 structure/fractal paths do correctly use closed bars and
confirmed pivots, but that does not cure this shared helper. The V6.37 audit must
replace its closed-bar-safe conclusion and add this as a release-blocking finding
for any future implementation derived from the baseline.

One related citation correction: `HasSecondRetestConfirmation` at lines
6991–7019 counts index `1` in its touch loop and returns
`current_bar_is_touch && touches >= 2`. It requires two separated touches total,
normally one prior touch plus the current closed retest—not two prior touches plus
the current retest.

### 2. HIGH — V6.37 cross-symbol daily close is confirmed, conditionally

The mechanical concern is correct:

- The default `InpMagicNumber` is `312003` at line 64.
- `OnTick` calls `CheckDailyLimits` at line 561, and its only call to
  `CloseAllOurPositions` is line 3321.
- `GetTodayClosedProfit` at lines 3325–3347 filters by magic at line 3337,
  but not by symbol.
- `GetOpenProfitForMagic` at lines 3373–3387 filters by magic at line 3382,
  but not by symbol.
- The position loop in `CloseAllOurPositions` at lines 3389–3400 also filters
  by magic only. It can therefore close every same-magic position on the account.
- In contrast, its pending-order loop at lines 3403–3413 filters by both magic
  and `_Symbol`.

Consequently, multiple chart instances sharing magic `312003` participate in one
magic-wide P/L calculation. An instance whose daily threshold is enabled and
whose `InpClosePositionsAtDailyLimit` is true (line 125, true by default) can,
when it locks, attempt to close positions on all symbols using that magic.

Two qualifications should be preserved in the audit:

1. All four daily money/percentage thresholds default to zero at lines 120–123,
   so this dangerous path is disabled by default.
2. The trigger is not actually one symbol's isolated P/L; it is already
   magic-wide. If an account-wide daily lock was intentional, closing positions
   across symbols may match that intent, while deleting pending orders only on
   `_Symbol` is then the inconsistent part. The intended scope must be specified.

There is also restart/instance divergence: `SetupDailyState` initializes
`g_day_start_equity` from current equity at lines 3260–3265. Instances attached
or restarted at different times can therefore use different percentage baselines.

### 3. HIGH — V8.11 open-basket restart management failure is confirmed

The handover's state trace is correct:

- Basket state is held in volatile globals at lines 230–236.
- `OnInit` at lines 255–281 restores only peak-drawdown data; it does not scan
  or reconcile open positions.
- `ManageBasket` returns at lines 1416–1417 when direction or risk is zero.
- `OnTick` blocks a replacement basket when matching positions exist at
  lines 307–308.
- The dashboard consequently reaches its `Basket: flat` branch at
  lines 2059–2077 even while orphaned EA positions remain open.

The restart disables the dynamic break-even logic at 1425–1432, runner trailing
at 1437–1445, giveback exit at 1448–1453, time exit at 1455–1460, and direction-
flip exit at 1462–1464. The original broker-side SL/TP submitted at line 1376
remains, and the separate daily-lock path can still call `CloseBasket`; the audit
should not imply that every form of protection disappears.

Open-position APIs make a conservative restart fix possible, but exact recovery
from positions alone is lossy:

| Recoverable or derivable | Not reliably reconstructable after state changes |
|---|---|
| Symbol, magic, direction, live tickets, current volume/count | Original basket risk after an SL has moved |
| Actual fill prices/current aggregate entry | Historical `g_basket_peak_r` |
| Earliest remaining open time | Original leg count after one or more legs close |
| Current SL/TP and setup/leg comments | Exact shared requested entry versus distinct fills |
| A conservative “open basket exists” state | Exact break-even/trail phase and already-banked-leg state |

The official [position properties](https://www.mql5.com/en/docs/constants/tradingconstants/positionproperties)
support the left-hand column. The robust design is to persist explicit basket
metadata keyed by account, symbol, magic, and basket ID, then reconcile it against
live positions in `OnInit`. Position-only recovery should be a conservative
fail-safe, not assumed to reproduce the original basket exactly.

The audit should also record that restart resets `g_day_baskets`, the daily
lock/day-start equity state, `g_last_basket_close`, `g_last_entry_bar`, and
`g_last_breakout_fire`. This can bypass the daily basket cap and cooldown/
one-signal markers. Persisting only historical peak drawdown does not cover those
controls. `OnInit` also resets `g_peak_balance` to current balance at line 272;
the live drawdown gate at 315–319/2289–2305 can therefore lose a higher
pre-restart peak reference even though the historical maximum drawdown statistic
is retained. This manifests when the former peak balance exceeds balance at
restart; it is not a change when both values are equal.

### 4. HIGH — neither EA is safe across both netting and hedging accounts

Neither file branches on `ACCOUNT_MARGIN_MODE`. Calling `trade.SetMarginMode()`
does not adapt the algorithms' per-leg assumptions. Under the official
[`PositionSelect`](https://www.mql5.com/en/docs/trading/positionselect) behavior,
netting permits one position per symbol, while hedging permits multiple positions;
on hedging accounts `PositionSelect(symbol)` selects the lowest-ticket position.

V6.37:

- The gate at lines 603–607 uses `CountOurPositions` (6700–6715), while
  `EffectiveMaxPositions` at 7543–7551 can permit three positions.
- On a netting account, successive same-symbol additions merge and the position
  count remains one. The intended two-add-on cap therefore does not bind.
- `AddOnConditionsMet` at 8058–8100 then measures spacing from the merged,
  volume-weighted `POSITION_PRICE_OPEN`, not the last add-on's entry.
- Every netting add-on reuses the one position ticket, so
  `StorePositionRiskState` at 5965–5994 overwrites aggregate risk, partial-exit,
  and staged-target state while volume sizing covers only the new deal. Together
  with the count remaining one, total aggregate exposure is not bounded by the
  intended leg cap.
- `ClosePartialPosition` at 6214–6228 uses `CTrade::PositionClosePartial`, whose
  official documentation describes the method for
  [hedging accounting](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionclosepartial).
- Even on hedging accounts, `StorePositionRiskState` calls
  `PositionSelect(_Symbol)` at line 5967 immediately after an entry. With more
  than one position this selects the oldest/lowest ticket, not necessarily the
  new add-on, so the old leg can be overwritten while the new leg receives no
  risk state. It can also select another magic number's lowest-ticket position;
  the magic check at line 5969 then returns without storing the newly opened
  EA position's state.
- A pending fill stores state using `DEAL_POSITION_ID` at lines 697–699, while
  later management keys it using `POSITION_TICKET` at 5997–6002. Those identifiers
  are not guaranteed to remain interchangeable.

V8.11:

- `OpenBasket` supports one to four same-symbol legs (default two) and submits
  them at lines 1368–1380. Whenever it opens multiple legs, netting collapses
  them into one position and cannot preserve separate TP legs.
- `g_basket_legs = opened` at line 1389 may become `2` while
  `CountOurPositions` at 1639–1653 returns `1`. The test
  `count < g_basket_legs` at line 1425 then treats the first leg as banked
  immediately and can attempt break-even before 1R.
- A pre-existing same-symbol net position owned by another magic number is an
  additional merge/ownership hazard because the EA's own-magic position gate may
  not see it before submitting.

Both baselines are materially hedging-oriented, and V6.37 still has a hedging-
ticket association defect. The future engine needs either an explicit supported
account mode with an initialization rejection, or separate netting-safe basket
semantics and tests.

### 5. HIGH — trade submission/result handling can create phantom state

Both EAs treat the Boolean returned by `CTrade` methods as proof of server
execution. Officially, a `true` result from
[`PositionOpen`](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionopen)
only confirms the basic request structure; `ResultRetcode` and the resulting
deal/position must be checked.

- V6.37 `OpenSignal` at lines 2765–2798 logs the open and updates internal state
  after a true Boolean without verifying a successful server retcode/deal.
  Its pending-limit path at 8769–8781 has the same problem.
- V8.11 increments `opened` at lines 1376–1380 and commits basket/day state at
  1385–1392 without verifying actual fills.
- V8.11 `MoveBasketStops` at 1467–1482 ignores modification results, yet
  `ManageBasket` sets `g_basket_be_done = true` at line 1431. It can therefore
  report a protected basket after the broker rejected the stop move.
- V8.11 `CloseBasket` at 1485–1500 also ignores close results while announcing
  closure.

The same rule applies to position modification: the official
[`PositionModify`](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionmodify)
documentation requires checking the trade-server return code.

### 6. HIGH — broker filling, stop, freeze, and price validation is incomplete

V6.37 has useful market-order safeguards, but it is not broker-portable as
written:

- `OnInit` at 525–546 sets magic/deviation but never derives filling policy from
  the symbol. `SetTypeFillingBySymbol` is not called.
- `EnsureValidStops` at 2988–3013 reads stops level, freeze level, and spread and
  conservatively clamps initial market stops.
- That clamp occurs after the configured maximum stop cap and can widen the stop
  past the configured distance without a second cap check. The later volume
  calculation does size cash risk using the widened stop, so the defect is the
  violated stop-distance policy, not an omitted post-clamp risk calculation.
- Modification logic checks whether a stop improves before broker clamping, not
  again afterward; the adjusted candidate can cease to be an improvement.
- Prices are normalized to `_Digits`, not `SYMBOL_TRADE_TICK_SIZE`.
- OB pending limits at 8715–8771 do not use `EnsureValidStops` and only require a
  two-point entry offset. They do not validate the broker's pending-entry stop
  distance or attached SL/TP distances.

V8.11 is also incomplete:

- Filling selection at 261–269 prefers IOC/FOK flags and otherwise chooses
  `ORDER_FILLING_RETURN`, but RETURN is forbidden for Market Execution symbols.
  Filling must be chosen using both the symbol flags and execution mode; see the
  official [order filling rules](https://www.mql5.com/en/docs/constants/tradingconstants/orderproperties)
  and [`SetTypeFillingBySymbol`](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradesettypefillingbysymbol).
- `StopsLegal` at 1630–1636 checks only absolute entry-to-SL distance. It does not
  validate direction, TP side/distance, or tick-size alignment.
- `NormalizePrice` uses `_Digits`, not the trade tick size.
- `MoveBasketStops` neither revalidates stops/freeze distance nor checks the
  result code.

Both EAs call `OrderCalcMargin`, which is a useful estimate, but the official
[`OrderCalcMargin`](https://www.mql5.com/en/docs/trading/ordercalcmargin)
documentation states that it ignores current open positions and pending orders.
Neither EA performs a final `OrderCheck`, so these checks should not be described
as complete broker validation.

### 7. MEDIUM — normal duplicate protection exists, restart idempotency does not

V6.37's new-bar gate is at 579–580/6718–6728; V8.11's is at
301–302/1778–1787, with an additional breakout stamp at 2223–2225. In continuous
runtime there is no automatic retry loop. A requote/rejection therefore normally
causes a missed trade, not a same-bar duplicate.

The protection is not restart-safe:

- Bar/signal stamps are volatile and reset on EA/terminal initialization.
- The first tick after restart is treated as a new bar even when the current bar
  is already underway.
- Neither EA persists an atomic signal/deal ID or reconciles a submitted request
  with positions, deals, and orders before allowing another submission.

Existing-position gates prevent many duplicates at default settings, but not all:
V6.37 add-ons/pending orders, a position that already closed, multiple instances,
and netting/magic ambiguity are counterexamples. V8.11 can likewise re-enter after
a quick close/restart sequence. The audit should characterize this as partial
continuous-runtime protection, not reconnect-safe idempotency.

### 8. V8.11 has no effective forming-bar dependency in the traced paths

The V8.11 arrays used for trade decisions are consistently set as series arrays.
The traced M30 bias, M15 expansion, order-block, FVG, M1 entry, momentum, and
confirmed-pivot paths use index `1` or older (or indicator shift `1`). I found no
forming price bar in a live trade-decision path.

`BuildStructureMarks` does invoke `IsSwingHigh`/`IsSwingLow` for candidate
index `2` at line 498 with depth two, so that isolated swing test reads index
`0`. Full control-flow tracing shows that read has no output effect: for candidate
`2`, the newer-break loop starts at `j=1` but requires `j>=2` at 503/526, so it
cannot create a BOS/CHoCH mark. For candidates `3` and older, the swing test no
longer reaches index `0`. Equal-high/low discovery starts at `depth + 1`.
Accordingly, I found no drawable structure output or trade decision that depends
on the forming price bar; the V8.11 closed-bar conclusion is supported.

### 9. MEDIUM — indicator handles are released, but lifecycle/readiness is weak

There is no obvious normal live handle leak in the reviewed wrappers:

- V6.37 creates and releases handles inside each call at 5929–5945 and
  6508–6568.
- V8.11 does the same at 1734–1756 and 2352–2371.

The design repeatedly creates handles, immediately calls `CopyBuffer`, and
releases them instead of caching initialized handles. There is no
`BarsCalculated` readiness guard. This is inefficient and can produce transient
fallback values; moreover, official
[`IndicatorRelease`](https://www.mql5.com/en/docs/series/indicatorrelease)
documentation states that release is not executed in the Strategy Tester.

Failure defaults are also semantically unsafe: V8.11 RSI returns `50` on invalid
handle or `CopyBuffer` failure at lines 2366/2371, and `50` lies inside its default
RSI acceptance windows. V6.37 also uses an RSI fallback of `50` at 6526/6532.
A data/indicator failure should be distinguishable from a valid neutral reading
and should fail the affected signal closed.

### 10. Gate findings need more precise characterization

V6.37 ROTATION versus regime routing:

- `IsSelfConfirmedSetup` includes `ROTATION_` at 7534–7541.
- This bypasses premium/discount and horizontal-SR gates at 1895 and
  2001–2003.
- The later expansion router at 7513–7526 admits only breakout/FVG setups, so
  the rotation names created at 8212/8281 are rejected during expansion.

The behavior is verified, but “contradiction/oversight” is not established.
“Self-confirmed” is documented for the value-area/SR bypasses, not for bypassing
regime policy; expansion is explicitly restricted to breakout/FVG behavior, and
rotation is a mean-reversion setup. The router also stores a dashboard reason at
line 7524, so the rejection is not entirely silent. Record this as a verified
policy/reachability choice requiring a specification decision and backtest, not a
proven bug.

V8.11 momentum breakout versus expansion:

- `g_expansion` is computed from closed M15 ATR at 453–456.
- `OnTick` returns unconditionally when it is true at 340–344.
- `BuildMomentumBreakout` at 2212–2284 therefore cannot run while the expansion
  flag is true, despite its internal comment/location exemption.

There is no missed path that reconciles those statements: the outer return wins.
However, an M5 momentum breakout is not definitionally the same as M15 ATR being
at least 1.8 times its average, so the setup remains reachable below that
threshold. The static finding is a policy/comment conflict; whether it suppresses
the best breakouts or harms performance requires testing.

### 11. HIGH — V6.37's NFP schedule is not safe as an authoritative live filter

- The server hour/minute are manual inputs at lines 190–191.
- `IsNFPDayNow` at 7243–7248 equates NFP day with the first Friday.
- `NewsStateNow` at 7251–7276 constructs that time directly in broker-server
  time.

There is no economic-calendar lookup, New York/UTC/server conversion, DST
handling, holiday/rescheduled-release handling, or automatic broker-offset
validation. The source comment itself requires manual verification. The filter
can only be treated as an operator-maintained approximation, not a dependable
live/demo protection. `IsSyntheticIndexSymbol` at 7233–7241 is also a substring
heuristic, so unrecognized synthetic symbols can receive inappropriate NFP
treatment.

### 12. Complexity/overfitting is a valid risk hypothesis, not a finding of failure

I concur with the risk framing: the number of strategies, interacting gates,
thresholds, and early learning decisions creates substantial opportunities for
signal starvation, fragile parameter interactions, and overfitting. Static code
review cannot establish that any of those outcomes occurs. They require ablation,
out-of-sample/walk-forward tests, neighboring-parameter stability checks, and
trade-count/gate-rejection telemetry.

The counts need correction:

- V6.37 contains 282 actual `input` variables plus 25 `input group` headings.
  Calling all 307 declarations “inputs” is misleading.
- V8.11 contains 107 actual `input` variables plus 9 group headings, not 116
  configurable variables.
- V6.37 has 8,822 physical lines, not 8,821.

The “five-gate serial-AND funnel” wording is also shorthand rather than literal
control flow: some stages modify score, some can zero it, and minimum-score/
score-gap tests occur separately.

## Package acceptance checks

The following parts of TASK-001 check out:

- All nine deliverables listed in the handover exist on the reviewed task branch.
- The two baseline source blobs and the set-file blob match their immutable
  baseline identities; no baseline code change is hidden in the documentation
  task.
- All 13 baseline PNGs are present and unchanged relative to the task branch's
  base commit; only `screenshots/visual_notes.md` was added under that directory.
- The audit headings cover the subject areas required by section 4 of
  `00_MASTER_PROMPT_FOR_CLAUDE.md`. This is a topic-coverage check, not a claim
  that I exhaustively revalidated every individual line citation outside the
  source paths discussed in this review.
- `profit_giveback_diagnosis_plan.md` remains a proposed diagnostic plan and does
  not pretend to establish a root cause without journal/CSV evidence.
- I found no claim that either baseline guarantees profitability.

Those packaging positives do not overcome the source-analysis and internal-
consistency corrections below.

## Additional audit corrections

The following claims should be corrected before approval:

1. V8.11's M1 BOS-retest loop does not simply inspect every candidate in its
   advertised range. It continues past candidates that fail the initial
   break/body tests, but after the first candidate that passes those tests it
   returns even if retest confirmation fails. A later valid candidate can
   therefore be skipped.
2. The V8.11 OB/FVG audit overstates “first return only.” OB mitigation checks
   omit recent bars `1` and `2`; FVG touch checks intentionally omit trigger bar
   `1`, and there is no persistent consumed flag. The code may reconsider the
   cached gap on later M1 bars. These are weaker controls than a true lifecycle
   state machine, but not the exact behavior claimed.
3. V8.11 momentum extrema at 2240–2245 include M5 bar `2`, so the prior-close
   comparisons at 2248/2268 are tautological. The transition test adds no filter;
   the ATR buffer is doing the meaningful threshold work.
4. The V8.11 hierarchy audit should not say every setup builder uses the shared
   M1 array: the momentum builder copies its own M5 array at 2227–2230.
5. Any runner-threshold text saying the setting “raises” a start from 1.5R to a
   smaller value should say “lowers.”
6. `baseline_comparison.md` calls static observations “present and working as
   designed.” Without compilation or execution, “present in source” is the
   supportable conclusion.
7. The handover says every finding is evidence-labeled, but the V8.11 document
   contains design/separate-note statements without one of the stated labels.
8. `TASK-001_BASELINE_AUDIT.md` still contains a post-commit placeholder; the
   reviewed commit is `c61903f`.

These corrections are separate from whether the immutable baseline code will
ever be fixed. The audit must be mechanically accurate because it is intended to
drive the new-engine design.

## Set-file provenance

The evidence supports only this conclusion: `SmartCore_v3_Tuned.set.txt` is not a
usable native preset for either reviewed baseline.

- It contains 79 key/value lines and 11 INI-style section headings, not 40 keys.
- None of its keys exactly matches an input-variable name in either EA.
- Its `MagicNumber=123456` matches neither V6.37 (`312003`) nor V8.11 (`800001`).
- Neither source contains a parser for the file or references its distinctive
  keys.

It does **not** follow that the file belongs to the planned new architecture.
`SmartCore_v3` may instead refer to an absent third EA or a manually drafted
configuration. Provenance remains unresolved unless source history or the
original producer is located.

The package is internally inconsistent here: `baseline_comparison.md` says the
provenance is resolved and also reports the wrong key count, while
`01_BASELINE/inventory.md` and `01_BASELINE/setfiles/IDENTITY.md` describe it as
unresolved. Those documents should converge on the narrower conclusion above.

## Required changes before approval

1. Correct the V6.37 audit's completed-candle/repainting conclusion and add the
   live `rates[0]` dependency with its call sites.
2. Preserve both confirmed headline risks, but add the scope/default-state nuance
   for V6.37 and the remaining broker-SL/TP/reconstruction nuance for V8.11.
3. Add the netting/hedging, post-entry ticket association, trade-result, filling,
   stop/tick-size, and restart-idempotency findings to the audit/comparison.
4. Correct the line/input/key counts and the source-behavior overstatements listed
   above.
5. Mark set-file provenance unresolved and remove the unsupported planned-engine
   attribution.
6. Replace “tests not applicable” with an accurate statement that compilation,
   backtests, restart tests, multi-symbol tests, and netting/hedging tests were not
   run. No source change is required for those tests to be relevant to a baseline
   audit.

As a follow-up after TASK-001—not as a prerequisite for approving this audit
package—the confirmed risks should be transferred into explicit future-engine
requirements and TEST_PLAN cases without editing the immutable baseline sources.

No profitability or live-safety conclusion is possible from this static review.
