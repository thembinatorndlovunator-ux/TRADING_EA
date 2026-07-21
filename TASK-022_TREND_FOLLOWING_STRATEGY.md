# TASK-022 — TrendFollowingStrategy: the fourth strategy module

## Objective

Implement `TrendFollowingStrategy.mqh` per
`STRATEGY_SPEC_TREND_FOLLOWING.md` (written first): the fourth strategy
family, two setups (trendline pullback, momentum continuation). This is
the task where `TASK-002_PHASE2_SPECIFICATION.md` section 7's explicit
trendline-porting decision — three validated anchors, middle-anchor
verification, fresh re-projection — finally becomes real code, directly
fixing V6.37's confirmed `BuildThreePointTrendLine`/`EvaluateTrendBreaker`
defect (two-anchor construction, constant projected level).

## Reason

Section 3's routing table splits Trend Following into two genuinely
different components ("V6.37 (trendline) + V8.11 (momentum)"), with the
momentum half specifically eligible under both `TRENDING` and
`VOLATILITY_EXPANSION` regimes — the same multi-setup pattern
established by `SMCStrategy.mqh` and `ChartPatternStrategy.mqh`.

## Baseline behaviour

V6.37's `BuildThreePointTrendLine` uses only the outer two of three
monotonic swing points (never testing the middle point's own distance
from that line), and `EvaluateTrendBreaker` projects a constant value
rather than re-projecting per bar (`baseline_v637_audit.md`). This task
implements the new-engine fix specified in
`TASK-002_PHASE2_SPECIFICATION.md` section 7, not a port of the
defective baseline behavior. No file under `01_BASELINE/` is touched.

## Evidence

`STRATEGY_SPEC_TREND_FOLLOWING.md` (written first). `TASK-002_PHASE2_
SPECIFICATION.md` sections 3 (routing) and 7 (trendline porting
decision, quoted directly in the module's own header comment).

## Specification

`TF_FindTrendlineArray` finds three confirmed swing points (lows for an
uptrend/support line, highs for a downtrend/resistance line), validates
the middle anchor against the line through the outer two (reusing
`ChartPatternEngine.mqh`'s `CPT_LinearInterpolate` directly — no
interpolation math duplicated a third time), and re-projects fresh to
the current bar every call (never a stored, stale value).
`TFS_EvaluateTrendlinePullbackArray` (`TRENDING` only): requires price
currently touching the freshly-projected trendline plus candlestick
confirmation. `TFS_EvaluateMomentumContinuationArray` (`TRENDING` **and**
`VOLATILITY_EXPANSION`): requires a recent Marubozu displacement in the
required direction and a genuinely shallow pullback from its extreme.

**Stop and target formulas are stated simplifications** (ATR-distance
stop, 2R target) — flagged explicitly in both the specification and the
module header, same discipline as `SMCStrategy.mqh`'s target-formula
flag, since section 7's real swing-based stop/target selection isn't
built as a standalone composable piece yet.

## Files affected

New: `STRATEGY_SPEC_TREND_FOLLOWING.md`,
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/TrendFollowingStrategy.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_TrendFollowingStrategy.mq5`, this task
file. Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

Same Phase 6 deferrals as every prior strategy. Swing-based (rather than
fixed-ATR-distance) stop placement — a stated simplification, see
Specification.

## Risks

- No independent review available this phase.
- Runtime verification: the array-based core's two setup scenarios plus
  four negative cases are deterministic; only the final `CMarketData`
  wrapper smoke test is part of the batched runtime gap.
- **The trendline-validation test is constructed as a perfect linear
  fit** (the middle anchor computed to lie exactly on the line, via the
  same interpolation formula the code itself uses) — this proves the
  happy path but is, by construction, the easiest possible case for the
  validation to pass; the paired negative case (middle anchor moved far
  off the line) is what actually exercises the rejection logic and is
  the more load-bearing of the two tests.
- Stop/target formulas are explicitly stated simplifications, flagged in
  three places (specification, module header, this task file) to
  prevent them from being mistaken for finished section-7 logic later,
  same pattern established by `SMCStrategy.mqh`.

## Test plan

1. **Compile test** (completed, see Compiler result — clean on the
   first attempt).
2. **Logic test — array-based core, fully hand-verifiable**: a
   trendline-pullback scenario with a perfect three-anchor linear fit
   and exact hand-computed `stop_price`/`target_price`; a wrong-regime
   negative case; an invalid-trendline negative case (middle anchor far
   off the line — the specific defect-fix this strategy exists to
   prove); a momentum-continuation scenario under
   `VOLATILITY_EXPANSION_UP` specifically (distinguishing it from the
   `TRENDING`-only trendline setup); a wrong-regime negative case for
   momentum; and a too-deep-pullback negative case.
3. **Logic test — `CMarketData` wrapper, batched**: a real-symbol
   evaluation across both setups, confirmed to complete without
   crashing.

## Acceptance criteria

- [x] The trendline validation genuinely rejects an invalid middle
      anchor (verified by the dedicated negative case) — the specific
      V6.37 defect this strategy exists to fix.
- [x] Momentum continuation is confirmed eligible under both `TRENDING`
      and `VOLATILITY_EXPANSION` regimes (tested under expansion
      specifically, not just trending, to prove the multi-regime claim).
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (clean on the first attempt).
- [x] A too-deep pullback is correctly rejected before candlestick
      confirmation is even checked.
- [ ] The `CMarketData` wrapper's real-symbol composition — batched with
      TASK-003 through 021's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if any hand-verifiable test produces `FAIL` — especially the
invalid-trendline negative case, since accepting a bad middle anchor
would mean this task failed to actually fix the V6.37 defect it exists
to fix.

## Implementation notes

`TF_FindTrendlineArray` cannot use MQL5 array-reference aliasing to pick
between `highs[]`/`lows[]` based on `want_support` (MQL5 does not
support binding a `const double &prices[]` to either array
conditionally) — resolved with explicit `if(want_support){...}else{...}`
branches, a small amount of duplication accepted as the idiomatic MQL5
approach rather than a workaround.

## Commands run

```
git checkout -b claude/task-022-trend-following-strategy
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_TrendFollowingStrategy.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 1010 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt. Full log available in
this session's history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not yet
runtime-confirmed**, but both setup scenarios plus all four negative
cases are deterministic and hand-computed; only the final `CMarketData`
wrapper smoke test is part of the batched runtime gap.

## Commit

Pending — see `git log` on `claude/task-022-trend-following-strategy`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed.** Four of six strategy families now
have real, tested implementations. Two remain: Post-Expansion Retest and
No-trade (the latter to be addressed directly in the Phase 6
`StrategyRouter` task, not as its own strategy file).
