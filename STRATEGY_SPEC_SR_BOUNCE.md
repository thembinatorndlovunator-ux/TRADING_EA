# Strategy Specification — SR Bounce / Range Rotation

Filled out from `STRATEGY_SPECIFICATION.md`'s template, per master-prompt
Phase 5's "add and test one at a time" instruction and this project's own
audit-then-specify-then-implement discipline. This is the first of the
six strategy families (`TASK-002_PHASE2_SPECIFICATION.md` section 3) to
receive a concrete specification and implementation.

## Strategy ID
STRAT-001

## Strategy Name
SR Bounce / Range Rotation

## Market Family
METAL, SYNTHETIC — the strategy logic itself is family-agnostic; risk
percentages differ by family per `RISK_POLICY.md`, applied at the risk
layer, not here.

## Eligible Symbols
Any symbol passing `BrokerValidator.mqh`'s attach-time validation
(TASK-004).

## Intraday Mode
Scalp, Day-trade — per `TASK-002_PHASE2_SPECIFICATION.md` section 3's
routing table.

## Eligible Regimes
`RANGING` only.

## Prohibited Regimes
`TRENDING_UP`, `TRENDING_DOWN` (section 3: "Block SR Bounce counter-trend
fades"), `COMPRESSION`, `VOLATILITY_EXPANSION_UP`,
`VOLATILITY_EXPANSION_DOWN`, `TRANSITION_OR_UNCERTAIN`, `NEWS_BLACKOUT`,
`UNTRADEABLE_SPREAD_OR_LIQUIDITY` — section 3's general rule that these
last four block every family unconditionally.

## Context Timeframes
M30 (Day-trade) / M15 (Scalp) — per section 3's routing table.

## Entry Timeframe
M15 (Day-trade) / M5 (Scalp) — per section 3's routing table.

## Required Market Structure
A valid `RANGING`-regime read (`MarketRegimeEngine.mqh`, TASK-016) with a
computed `SMarketStructureState` (`MarketStructure.mqh`, TASK-012) —
`range_high`/`range_low` from that same structure read are the
strategy's own range boundaries; no second, independent range concept is
computed.

## Required Location
Current close within `InpSRBounceProximityATR` (default `0.3`, ATR
multiple — the same tolerance concept as `TASK-002_PHASE2_SPECIFICATION.md`
section 6's retest tolerance) of `range_low` (long candidate) or
`range_high` (short candidate).

## Setup Conditions
The proximate boundary (`range_low` for long, `range_high` for short)
must independently qualify as a genuine SR zone via
`SupportResistance.mqh`'s `SR_IsSupportZoneArray`/`SR_IsResistanceZoneArray`
(TASK-013), `min_touches >= 2` — the range boundary alone is not
sufficient; it must also show repeated respect as a level, closing
ledger-adjacent concern of not trading a boundary that has only ever
been touched once.

## Entry Trigger
A qualifying reversal candlestick pattern (`CandlestickPatternEngine.mqh`,
TASK-014/017) at the current bar, in the bounce direction:
- Long (at support): bullish pin bar, bullish engulfing, or tweezer
  bottom.
- Short (at resistance): bearish pin bar, bearish engulfing, or tweezer
  top.

**Deliberately excluded: three-bar reversal.** `CP_IsThreeBarReversalArray`
returns a single ambiguous boolean for either a bullish (swing-low-based)
or bearish (swing-high-based) reversal without telling the caller which
fired — using it here without resolving that ambiguity could confirm a
bearish reversal near a support level (or vice versa), a real
correctness risk caught during this task's own design, not used as a
confirmation source for this strategy as a result.

## Candlestick Confirmation
Required — see Entry Trigger above; the strategy produces no signal
without one of the four qualifying candlestick patterns.

## Chart-Pattern Confirmation
Optional, not required for this strategy in isolation — a double-top/
bottom or head-and-shoulders/inverse (`ChartPatternEngine.mqh`, TASK-018)
coinciding with the same zone is scoring-layer confluence
(`TASK-002_PHASE2_SPECIFICATION.md` section 9), not a hard gate here.

## ICT/SMC Features
Optional — equal-high/low liquidity at the zone
(`SR_IsEqualHighLiquidityArray`/`...LowArray`, TASK-013) is a bonus
confluence factor, not required.

## News Policy
Standard — `NEWS_BLACKOUT` is a gating regime (section 2); already
excluded via "Prohibited Regimes" above, no strategy-specific news logic
needed.

## Session Policy
Standard — Day-trade closes by the intraday boundary
(`IntradayCloseManager.mqh`, TASK-010); Scalp caps attempts per session
and rejects a repeat entry at an unchanged level within the session
(section 1) — the latter composes directly with this strategy's own
Duplicate-Signal Protection below.

## Spread Policy
Standard — `UNTRADEABLE_SPREAD_OR_LIQUIDITY` gating (section 2) already
excludes wide-spread conditions before this strategy is even evaluated;
no additional strategy-specific spread check.

## Stop-Loss Formula
Beyond the qualifying zone extreme, buffered by
`InpSRBounceStopBufferATR` (default `0.3`) × ATR: `range_low − buffer`
(long) / `range_high + buffer` (short). Final validation (floor/cap,
reject-not-clamp on cap breach) is `RiskManager.mqh`'s job
(`RM_ValidateStopDistance`, TASK-007), not duplicated here — this
strategy computes the raw candidate distance only.

## Target Formula
The opposite range boundary — `range_high` for a long, `range_low` for a
short — matching the "Range Rotation" naming directly (rotating from one
side of the confirmed range to the other).

## Exit Management
Standard exit engine (`TASK-002_PHASE2_SPECIFICATION.md` section 7) —
break-even/structure-trailing/ATR-fallback/time-stop/profit-lock/
giveback-guard. Not yet wired into a single `ExitManager.mqh` consumer;
this strategy produces `stop_price`/`target_price`, which such a consumer
will manage once built.

## Maximum Holding Boundary
Scalp: `InpScalpMaxMinutes` (default 60, section 7). Day-trade: the
intraday boundary (`IntradayCloseManager.mqh`).

## Invalidation
A confirmed close beyond the qualifying zone in the adverse direction
before entry invalidates the setup for this evaluation (the zone itself
remains eligible again once its consecutive-closes-beyond count returns
to zero, per section 3's level-invalidation lifecycle — not implemented
as persisted state in this task; see Out of scope).

## Duplicate-Signal Protection
Deferred to section 1's own stated mechanism (Scalp mode's repeat-entry
rejection at an unchanged level within a session) and section 3's
level-invalidation lifecycle — both require persisted per-instance state
(`StateManager`'s per-instance namespace, not yet built per TASK-003's
own scope note) to track across evaluations; this task's
`SRB_EvaluateArray` is stateless and evaluates each call independently,
so duplicate-signal suppression is explicitly a caller/future-task
responsibility, not built into this strategy module itself.

## Risk Multiplier
Not computed here — section 3 assigns `RANGING`-regime eligibility for
SR Bounce a `+10%` ("prefer") score multiplier, and `DrawdownController.mqh`
(TASK-008) separately computes the risk-reduction multiplier; both are
`StrategyRouter`/`RiskManager` composition concerns (Phase 6), not
duplicated in this strategy module, which produces a raw signal only.

## Journal Fields
Populates a subset of `DecisionJournal.mqh`'s (TASK-009) `STradeDecision`
fields directly: `strategy="SRBounce"`, `setup` (`"support_bounce"`/
`"resistance_bounce"`), `candlestick_pattern` (the specific confirming
pattern name), and the zone's own price/touch-count as
`score_breakdown_json` content once a scoring layer exists to populate
the rest.

## Visual Objects
Deferred — Phase 4's "visuals" item and Phase 5's strategy-specific
markers are both not yet built (no running EA context to draw into).

## Repainting Test
Every input this strategy reads (`SMarketStructureState`, SR-zone
touches, candlestick patterns) is itself built on the logical-index
(completed-bar-only) convention enforced throughout every underlying
module — no repainting is possible by construction, inherited rather
than independently re-verified here.

## Unit-Test Fixtures
Hand-fabricated arrays reproducing a clean `RANGING`-eligible range with
a qualifying (>=2-touch) SR zone at one boundary and a confirming
candlestick pattern at the current bar — see
`Test_SRBounceStrategy.mq5`.

## Backtest Hypothesis
Not tested — Phase 8 concern. No claim of backtest performance is made
by this task, per `CLAUDE.md`'s evidence rule.

## Acceptance Criteria
- [x] Produces a signal only when regime is `RANGING`, structure is
      valid, price is near a qualifying (`>=2`-touch) SR zone, and a
      directionally-consistent candlestick confirmation is present.
- [x] Never produces a signal from the excluded, ambiguous three-bar-
      reversal path.
- [x] Stop/target formulas match this specification exactly.

## Rejection Criteria
Rejected if the implementation produces a signal without regime/
structure/zone/candlestick conditions all independently satisfied, or if
a long signal can be produced by a bearish-context confirmation (or vice
versa).
