# Strategy Specification — Post-Expansion Retest

Fifth of six strategy families, per `STRATEGY_SPECIFICATION.md`'s
template. Section 3 describes this family only briefly ("new work,
V6.37-informed gating... prefer Post-Expansion Retest... block chasing
the initial spike") without a full formula, unlike the ported
sweep/shift or trendline mechanisms — this specification is this
project's own concrete formalization of that brief description, stated
explicitly, same discipline as `MarketStructure.mqh`'s bias/break
definitions and `ICTSMCGeometry.mqh`'s sweep algorithm.

## Strategy ID
STRAT-005

## Strategy Name
Post-Expansion Retest

## Market Family
METAL, SYNTHETIC.

## Intraday Mode
Scalp, Day-trade — per section 3's routing table.

## Eligible Regimes
`VOLATILITY_EXPANSION_UP`/`VOLATILITY_EXPANSION_DOWN` only.

## Prohibited Regimes
Every other regime, per section 3's general rule.

## Context / Entry Timeframes
H1 context / M5 entry (Day-trade); M15 context / M1 entry (Scalp) — per
section 3's routing table.

## Required Market Structure
The reference level is `MarketStructure.mqh`'s own most recent
same-direction swing extreme (`swing_high_1_price` for `_UP`,
`swing_low_1_price` for `_DOWN`) — the level whose break most plausibly
triggered the expansion, reusing `MarketStructure`'s already-computed
state rather than re-deriving a separate "what broke" concept. A
**genuine expansion move** must be confirmed: at least one bar since the
regime's own triggering break event traded beyond the reference level by
`InpMinExpansionATR` (default 1.5) ATR — this distinguishes an actual
displacement from price merely sitting near the level.

## Required Location
Current price within `InpPERRetestToleranceATR` (default 0.3) of the
reference level — a genuine return to the origin, not a shallow pullback
still far from it (that would instead be `TrendFollowingStrategy.mqh`'s
momentum-continuation setup).

## Setup Conditions
Regime is `VOLATILITY_EXPANSION_UP`/`_DOWN`, structure is valid, a
genuine expansion move is confirmed (see above), current price is
retesting the reference level, and — **a defensive, redundant no-chase
check**: `MarketStructure`'s own `last_event_index` (the break that
triggered the expansion) must be at least `InpNoChaseBarsAfterSpike`
(default 2) bars old. **Stated explicitly:** the canonical no-chase gate
belongs to the future `StrategyRouter` (section 3: "no entry within
`InpNoChaseBarsAfterSpike` bars of the regime's own transition"); this
strategy also checks it defensively since it can be evaluated standalone
before that router exists, not because this is the gate's permanent
home.

## Entry Trigger
A directionally-consistent candlestick confirmation (bullish/bearish pin
bar or engulfing) at the current bar — same confirmation set and
three-bar-reversal exclusion as every prior strategy.

## Candlestick Confirmation
Required — see Entry Trigger.

## Chart-Pattern / ICT-SMC Features
Not used directly — this strategy is deliberately distinct from
`SMCStrategy.mqh`'s FVG-return setup (which also fires under
`VOLATILITY_EXPANSION`): FVG-return targets a specific three-candle gap;
this strategy targets the broken swing-structure level itself. Both may
independently qualify on the same bar in principle; resolving that
overlap is a `StrategyRouter`/`ConflictResolver` (Phase 6) concern, not
addressed here.

## News / Session / Spread Policy
Standard, same as every prior strategy.

## Stop-Loss Formula
Beyond the reference level, ATR-buffered.

## Target Formula
**Provisional 2R placeholder**, same stated simplification as
`SMCStrategy.mqh`/`TrendFollowingStrategy.mqh`.

## Exit Management / Maximum Holding Boundary
Standard, same as every prior strategy.

## Invalidation
A confirmed close through the reference level in the adverse direction
(the retest has failed, not held).

## Duplicate-Signal Protection / Risk Multiplier / Journal Fields
Same stated Phase 6 deferrals as every prior strategy.

## Visual Objects
Deferred.

## Repainting Test
Inherited from the underlying modules' completed-bar convention.

## Unit-Test Fixtures
One hand-fabricated scenario, in `Test_PostExpansionRetestStrategy.mq5`.

## Backtest Hypothesis
Not tested — Phase 8 concern.

## Acceptance Criteria
- [x] Fires only under a `VOLATILITY_EXPANSION` regime with a confirmed
      genuine expansion move (not merely price sitting near a level).
- [x] The defensive no-chase check genuinely rejects a too-recent
      breakout.

## Rejection Criteria
Rejected if a signal fires without a confirmed genuine expansion move,
or if the no-chase check fails to reject a fresh breakout.
