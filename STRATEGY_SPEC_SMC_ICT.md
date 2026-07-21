# Strategy Specification — SMC/ICT Price-Action

Filled out from `STRATEGY_SPECIFICATION.md`'s template, per master-prompt
Phase 5's "add and test one at a time" instruction. Second of the six
strategy families. Unlike SR Bounce (one regime, one setup shape), this
strategy is eligible across **three** regimes with three distinct setup
shapes, per `TASK-002_PHASE2_SPECIFICATION.md` section 3's routing
table — each is specified and implemented as its own detection function,
composed by one dispatcher, rather than forced into a single shape.

## Strategy ID
STRAT-002

## Strategy Name
SMC/ICT Price-Action

## Market Family
METAL, SYNTHETIC.

## Eligible Symbols
Any symbol passing `BrokerValidator.mqh`'s attach-time validation.

## Intraday Mode
Scalp, Day-trade — per section 3's routing table.

## Eligible Regimes
Three, each with its own setup (section 3's routing table lists this
strategy under all three rows):
1. **`TRENDING_UP`/`TRENDING_DOWN`** — order-block retest after
   displacement.
2. **`RANGING`** — liquidity sweep reversal (equal-high/low sweep,
   false-break trap).
3. **`VOLATILITY_EXPANSION_UP`/`_DOWN`** — fair-value-gap return.

## Prohibited Regimes
`COMPRESSION`, `TRANSITION_OR_UNCERTAIN`, `NEWS_BLACKOUT`,
`UNTRADEABLE_SPREAD_OR_LIQUIDITY` — section 3's general rule.

## Context Timeframes
H1 (Day-trade) / M15 (Scalp) — per section 3's routing table.

## Entry Timeframe
M5 (Day-trade) / M1 (Scalp) — per section 3's routing table.

## Required Market Structure
Setup-dependent: order-block retest needs a confirmed Marubozu
displacement (`CandlestickPatternEngine.mqh`) producing an order block
(`ICTSMCGeometry.mqh`, TASK-015) in the trend's own direction. Sweep
reversal needs a confirmed liquidity sweep
(`ICT_DetectSweepArray`). FVG return needs a confirmed fair value gap
(`ICT_GetFvgZoneArray`) formed in the expansion's own direction.

## Required Location
Setup-dependent, each already a "location" by construction: current
price at/near the order-block zone (retest), at the sweep's confirmation
bar, or inside the FVG zone.

## Setup Conditions

**1. Order-block retest (`TRENDING_UP`/`_DOWN`):** an order block matching
the trend's own direction (`OB_BULLISH` in `TRENDING_UP`, `OB_BEARISH` in
`TRENDING_DOWN`) is found within `InpSMCMaxRetestBars` (default 10) bars
of now, is not invalidated, and current price sits within
`InpSMCRetestToleranceATR` (default 0.3) ATR of the zone.

**2. Sweep reversal (`RANGING`):** a liquidity sweep is confirmed within
the most recent 2 bars (a "fresh" reversal, not a stale one) — the sweep
itself already embodies both "equal-high/low liquidity" (a pool extreme
existing to be swept at all implies resting liquidity there) and
"false-break trap" (a wick beyond the level followed by a close back
inside is precisely a false breakout).

**3. FVG return (`VOLATILITY_EXPANSION_UP`/`_DOWN`):** an FVG matching the
expansion's own direction is found within a scan window, is not
invalidated, and current price is inside the FVG zone.

## Entry Trigger
All three setups require a directionally-consistent candlestick
confirmation at the current bar (bullish/bearish pin bar or engulfing;
sweep reversal additionally allows tweezer top/bottom, matching
`SRBounceStrategy.mqh`'s own confirmation set at a reversal zone) —
**three-bar reversal excluded for the same reason as
`SRBounceStrategy.mqh`**: `CP_IsThreeBarReversalArray`'s ambiguous
direction return is unsafe to use without resolving which swing type
fired.

## Candlestick Confirmation
Required — see Entry Trigger.

## Chart-Pattern Confirmation
Not used by this strategy; SMC/ICT confluence is structural (order
block/sweep/FVG), not chart-pattern-based.

## ICT/SMC Features
The strategy's entire basis — see Setup Conditions.

## News Policy
Standard — `NEWS_BLACKOUT` gating excludes this strategy before
evaluation.

## Session Policy
Standard, same as `SRBounceStrategy.mqh`.

## Spread Policy
Standard — `UNTRADEABLE_SPREAD_OR_LIQUIDITY` gating.

## Stop-Loss Formula
Beyond the relevant zone (order block / sweep extreme / FVG boundary),
buffered by ATR — mirrors `ICTSMCGeometry.mqh`'s own
`ICT_ComputeSweepStopDistance` buffer concept, applied per setup type.

## Target Formula
**Stated simplification, not a full target-selection implementation:**
`TASK-002_PHASE2_SPECIFICATION.md` section 7's full target selector
(evaluating SR/swing/major-swing/opposing-range-boundary candidates
together) does not exist as a built module yet. This strategy uses a
straightforward `2× the zone height`, projected in the trade direction
from entry, as a placeholder target — explicitly flagged here as
provisional, to be replaced once a real target-selection module exists,
not presented as the specification's final answer on target selection.

## Exit Management
Standard exit engine (section 7), not yet wired into a single
`ExitManager.mqh` consumer — same status as `SRBounceStrategy.mqh`.

## Maximum Holding Boundary
Scalp: `InpScalpMaxMinutes`. Day-trade: intraday boundary.

## Invalidation
Order block: a confirmed close through the zone
(`ICT_IsOrderBlockInvalidated`). FVG: a confirmed close fully through the
gap (`ICT_IsFvgInvalidated`). Sweep: the reversal itself is the
confirmation event; no separate invalidation concept applies once
triggered (matching `ICTSMCGeometry.mqh`'s own scope).

## Duplicate-Signal Protection
Same stated deferral as `SRBounceStrategy.mqh` — needs persisted
per-instance state not yet built; this strategy's evaluation functions
are stateless.

## Risk Multiplier
Not computed here — same Phase 6 deferral as `SRBounceStrategy.mqh`.
Section 3 assigns each of the three regime/setup combinations its own
"prefer" eligibility multiplier.

## Journal Fields
`strategy="SMC_ICT"`, `setup` (`"ob_retest"`/`"sweep_reversal"`/
`"fvg_return"`), `candlestick_pattern`, zone bounds — same composition
approach as `SRBounceStrategy.mqh`.

## Visual Objects
Deferred, same as every strategy so far.

## Repainting Test
Inherited from the underlying modules' own completed-bar-only
convention — not independently re-verified here.

## Unit-Test Fixtures
Hand-fabricated arrays per setup, one each, in
`Test_SMCICTStrategy.mq5`.

## Backtest Hypothesis
Not tested — Phase 8 concern.

## Acceptance Criteria
- [x] Each of the three setups is independently gated by its own regime
      requirement and produces no signal outside it.
- [x] No confirmation path can produce a direction-inconsistent signal.
- [x] The provisional target formula is explicitly flagged as
      provisional, not presented as finished target-selection logic.

## Rejection Criteria
Rejected if any setup fires outside its required regime, or if the
target formula is later mistaken for a finished implementation of
section 7's full target selector.
