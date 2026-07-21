# Strategy Specification — Chart-Pattern Breakout/Reversal

Third of six strategy families, per `STRATEGY_SPECIFICATION.md`'s
template.

## Strategy ID
STRAT-003

## Strategy Name
Chart-Pattern Breakout/Reversal

## Market Family
METAL, SYNTHETIC.

## Intraday Mode
Day-trade only — per `TASK-002_PHASE2_SPECIFICATION.md` section 3,
Scalp is not eligible for this family (width-based rule).

## Eligible Regimes
Two, each its own setup, mirroring `SMCStrategy.mqh`'s multi-setup
precedent:
1. **`TRENDING_UP`/`TRENDING_DOWN`** — breakout-retest, direction
   confirming the trend (a reversal pattern breaking in the trend's own
   direction is a continuation confirmation, not a counter-trend call).
2. **`RANGING`** — a double top/bottom whose extreme coincides with the
   current range boundary (`MarketStructure.mqh`'s `range_high`/
   `range_low`).

## Prohibited Regimes
`COMPRESSION` (see Out of scope — the gated early-breakout variant is
deferred), `VOLATILITY_EXPANSION_UP/DOWN`, `TRANSITION_OR_UNCERTAIN`,
`NEWS_BLACKOUT`, `UNTRADEABLE_SPREAD_OR_LIQUIDITY`.

## Context / Entry Timeframes
H4 context / M15 entry, Day-trade only — per section 3's routing table.

## Required Market Structure
Trend-breakout-retest: any of the four patterns
`ChartPatternEngine.mqh` implements (double top/bottom, head-and-
shoulders/inverse), already broken out (`breakout_index >= 0`), within
`InpCPMaxBreakoutAgeBars` (default 10) of now. Range-boundary: a double
top/bottom (triple deferred, per `ChartPatternEngine.mqh`'s own stated
scope) whose `extreme_price` coincides with `MarketStructure`'s range
boundary.

## Required Location
Trend-breakout-retest: current price within `InpCPRetestToleranceATR`
(default 0.3) of the pattern's own `boundary_price` — a retest in
progress. Range-boundary: the pattern's extreme itself defines the
location.

## Setup Conditions
**Trend-breakout-retest:** the pattern's breakout direction must match
the regime's own direction (a double-top/H&S breaking **down** confirms
`TRENDING_DOWN`; a double-bottom/inverse-H&S breaking **up** confirms
`TRENDING_UP`) — this is a **continuation** read of a reversal pattern,
not a counter-trend call, stated explicitly since it is easy to misread
a "top"/"bottom" pattern name as inherently counter-trend. **Range-
boundary:** regime `RANGING`, structure valid, pattern extreme near the
boundary.

## Entry Trigger
Both setups require a directionally-consistent candlestick confirmation
(bullish/bearish pin bar or engulfing) at the current bar — same
confirmation set as `SRBounceStrategy.mqh`/`SMCStrategy.mqh`, same
three-bar-reversal exclusion and reasoning.

## Candlestick Confirmation
Required — see Entry Trigger.

## Chart-Pattern Confirmation
The strategy's entire basis.

## ICT/SMC Features
Not used by this strategy.

## News / Session / Spread Policy
Standard, same as every prior strategy in this project.

## Stop-Loss Formula
The pattern's own `stop` field, computed by `ChartPatternEngine.mqh`
directly — not recomputed here.

## Target Formula
The pattern's own `target` field (the measured-move/head-to-neckline
projection `ChartPatternEngine.mqh` already computes) — **this strategy
does not need the provisional 2×-zone-height placeholder
`SMCStrategy.mqh` uses**, since chart patterns already have a real,
specified target formula (section 6).

## Exit Management / Maximum Holding Boundary
Standard, same as every prior strategy.

## Invalidation
The pattern's own invalidation rule (a confirmed close back through the
boundary) — not independently re-implemented here; a future task wiring
pattern lifecycle tracking (`PatternRegistry`-equivalent) will consume
`ChartPatternEngine.mqh`'s own invalidation functions directly.

## Duplicate-Signal Protection / Risk Multiplier / Journal Fields
Same stated Phase 6 deferrals as every prior strategy.

## Visual Objects
Deferred.

## Repainting Test
Inherited from `ChartPatternEngine.mqh`'s own completed-bar convention.

## Unit-Test Fixtures
One hand-fabricated scenario per setup, in `Test_ChartPatternStrategy.mq5`.

## Backtest Hypothesis
Not tested — Phase 8 concern.

## Acceptance Criteria
- [x] Trend-breakout-retest only fires when the pattern's breakout
      direction matches the trend regime's own direction.
- [x] Range-boundary only fires when the pattern's extreme genuinely
      coincides with the current range boundary.

## Rejection Criteria
Rejected if a counter-trend breakout is accepted in the trend setup, or
if a pattern unrelated to the range boundary fires in the range setup.

## Out of scope, stated explicitly
The `COMPRESSION`-regime gated early-breakout variant (section 3:
"retest-optional confirmation... a genuine early, tighter-gated entry")
is deferred to a fast-follow task, matching the precedent set by
`ChartPatternEngine.mqh` deferring triple top/bottom — not rushed
alongside these two core setups.
