# Strategy Specification — Trend Following

Fourth of six strategy families, per `STRATEGY_SPECIFICATION.md`'s
template. Two components per section 3's routing table ("V6.37
(trendline) + V8.11 (momentum)"), implemented as two setups.

## Strategy ID
STRAT-004

## Strategy Name
Trend Following

## Market Family
METAL, SYNTHETIC.

## Intraday Mode
Day-trade (both setups). Scalp: momentum-continuation setup only, per
section 3 ("Scalp for momentum half only").

## Eligible Regimes
**Trendline pullback:** `TRENDING_UP`/`TRENDING_DOWN` only.
**Momentum continuation:** `TRENDING_UP`/`_DOWN` **and**
`VOLATILITY_EXPANSION_UP`/`_DOWN` — per section 3, this is the
"momentum-continuation half" explicitly preferred under expansion too.

## Context / Entry Timeframes
H4 context / M15 entry (Day-trade); H1 context / M5 entry
(Scalp, momentum only) — per section 3's routing table.

## Required Market Structure
**Trendline pullback:** a validated three-anchor trendline, per
`TASK-002_PHASE2_SPECIFICATION.md` section 7's explicit porting decision
("three validated anchors, not two... the middle swing point must itself
lie within `InpTrendlineMiddleToleranceATR` of the line drawn through
the outer two points... re-projected fresh at every new confirmed
swing") — this is the concrete fix for V6.37's confirmed
`BuildThreePointTrendLine`/`EvaluateTrendBreaker` defect
(two-anchor-only construction, constant-projected level), not a port of
the baseline behavior. **Momentum continuation:** a recent Marubozu
displacement candle (`CandlestickPatternEngine.mqh`) in the trend's own
direction, within `InpMomentumLookbackBars` (default 10) bars.

## Required Location
Trendline pullback: current price within `InpTrendlineTouchToleranceATR`
(default 0.3) of the trendline's own projected value at the current bar.
Momentum continuation: current price no more than
`InpMaxPullbackATR` (default 1.0) ATR retraced from the displacement
candle's own extreme — a genuinely *shallow* pullback, not a deep
retracement (which would instead be a reversal-strategy candidate, not
trend-following continuation).

## Setup Conditions
**Trendline pullback:** regime matches the trendline's own direction (an
uptrend/support trendline requires `TRENDING_UP`; a downtrend/resistance
trendline requires `TRENDING_DOWN` — the trendline direction and regime
direction are not independently chosen, they are the same concept
checked twice by construction, since `TF_FindTrendlineArray` is called
with `want_support` derived directly from the regime). **Momentum
continuation:** a qualifying Marubozu displacement exists in the
required direction within the lookback window, and the current pullback
is shallow.

## Entry Trigger
Both setups require a directionally-consistent candlestick confirmation
(bullish/bearish pin bar or engulfing) at the current bar — same
confirmation set and same three-bar-reversal exclusion as every prior
strategy in this project.

## Candlestick Confirmation
Required — see Entry Trigger.

## Chart-Pattern / ICT-SMC Features
Not used by this strategy.

## News / Session / Spread Policy
Standard, same as every prior strategy.

## Stop-Loss Formula
Trendline pullback: beyond the trendline's own current value, ATR-
buffered. Momentum continuation: a fixed ATR distance
(`InpMomentumStopATR`, default 1.5) from entry — **stated simplification**:
a real implementation would prefer stopping beyond the most recent
confirmed swing in the trade's favor (matching the exit engine's own
"swing in favor" trailing concept, section 7), but that requires
composing `SwingEngine`'s nearest-finder with a specific recency window
this task did not build out; flagged explicitly as provisional, same
discipline as `SMCStrategy.mqh`'s target-formula flag.

## Target Formula
**Provisional 2R placeholder** (2× the stop distance, projected from
entry), same stated simplification as `SMCStrategy.mqh` — section 7's
real target selector does not exist as a built module yet.

## Exit Management / Maximum Holding Boundary
Standard, same as every prior strategy.

## Invalidation
Trendline pullback: a confirmed close through the trendline in the
adverse direction. Momentum continuation: a pullback exceeding the
shallow-pullback threshold before a confirmation candle appears.

## Duplicate-Signal Protection / Risk Multiplier / Journal Fields
Same stated Phase 6 deferrals as every prior strategy.

## Visual Objects
Deferred.

## Repainting Test
Inherited from the underlying modules' completed-bar convention;
`TF_FindTrendlineArray`'s own re-projection is itself the fix for a
repainting-adjacent baseline defect (a constant, non-reprojected line),
stated explicitly since this is the one place in this strategy where
"does not repaint" is a substantive claim rather than an inherited
property.

## Unit-Test Fixtures
One hand-fabricated scenario per setup, in
`Test_TrendFollowingStrategy.mq5`.

## Backtest Hypothesis
Not tested — Phase 8 concern.

## Acceptance Criteria
- [x] The trendline validation genuinely rejects a middle anchor that
      does not lie near the line through the outer two anchors (the
      specific defect this strategy exists to fix relative to V6.37).
- [x] Momentum continuation only fires on a genuinely shallow pullback,
      not an arbitrary retracement depth.

## Rejection Criteria
Rejected if the trendline validation accepts an invalid middle anchor,
or if momentum continuation fires after a deep retracement that should
instead invalidate the setup.
