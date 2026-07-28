# TASK-043 - Mode-first routing architecture (regime -> mode -> mode-aware strategy generation)

## Objective

Implement the full pipeline ordering TASK-002_PHASE2_SPECIFICATION.md
section 1 actually specifies: **regime classifies first (fixed
`InpRegimeTF`) -> mode is computed second, independent of any trade
candidate -> strategy routing generates and scores candidates THIRD,
already mode-aware (mode-specific context/entry timeframe pairs, section
3's family x mode matrix) -> a lightweight post-hoc mode-consistency
check runs on the winning candidate only.**

Registered per Codex round-9 review (P1 finding 10), 2026-07-27: "All
five strategies are generated and conflict-resolved before the mode is
computed. Mode can only veto the already-selected winner afterward...
Implement the approved ordering or keep a numbered task open and stop
presenting TASK-028/the EA as launch ready." This task is that numbered
registration — mirroring TASK-042's own precedent (round-7 P2 finding 20:
"a future task must pick it up" is not a real owner; a numbered task is).

## Reason

`ThembaAdaptiveIntradayEA.mq5`'s `EvaluateAndJournal` today calls all five
strategy `*_Evaluate` functions against ONE shared `InpRegimeTimeframe`
bar (M15 by default), routes/resolves conflicts (`StrategyRouter.mqh`/
`ConflictResolver.mqh`), and only THEN computes `intraday_mode`
(`IntradayModeRouter.mqh`) and applies it as a post-hoc veto on the
already-selected winner. This is the exact ordering
TASK-002_PHASE2_SPECIFICATION.md section 1 was rewritten (round-3 finding
3) specifically to avoid: mode must be fixed BEFORE strategy generation,
not derived from (or merely vetoing) it, because the spec's own family x
mode timeframe matrix (section 3) requires each family to generate
candidates on a MODE-SPECIFIC context/entry timeframe pair — a strategy
cannot honestly claim to be "SCALP mode, M1 entry" if it was in fact
evaluated once, on M15, regardless of mode.

`IntradayModeRouter.mqh`'s own header (lines 10-33) and
`TASK-040_INTRADAY_MODE_ROUTER.md`'s own Specification item 4 ("Wiring
`intraday_mode` into actual strategy behavior... is a separate,
explicitly-named future task") already name this gap honestly — but
without a task number, which round-7's own P2 finding 20 established this
project must not repeat. This task supplies that number.

## Specification (TASK-002_PHASE2_SPECIFICATION.md section 1 and section 3
— summarized here; that file remains the authoritative source, not this
summary)

1. **Ordering.** Regime engine (section 2) runs first, on `InpRegimeTF`
   (fixed, mode-independent). Mode engine runs second, using ONLY the four
   regime/price/session-derived components already implemented in
   `IntradayModeRouter.mqh`'s `IMR_ComputeModeScore` (no candidate-quality
   input — this part is already correct, per round-8 P1 finding 12's own
   fix). Strategy routing runs THIRD, against the now-fixed mode and
   regime — this is the part not yet built. A post-hoc mode-consistency
   check (already built, section 1 stage 4) still runs on the winning
   candidate only, as today.
2. **Family x mode timeframe matrix (section 3).** Each of the five
   strategies must generate its candidate on the CONTEXT/ENTRY timeframe
   pair the matrix specifies for (family, active mode) — e.g., SMC/ICT
   Price-Action is H1 context / M5 entry in Day-trade but M15 context / M1
   entry in Scalp. This requires each strategy's own `*_Evaluate` function
   (or a new wrapper) to accept an explicit context/entry timeframe pair
   as an input, sourced from this matrix, rather than the single shared
   `InpRegimeTimeframe` every strategy reads today. Chart-Pattern
   Breakout/Reversal is explicitly "not eligible" in Scalp mode (matrix
   row) — mode-aware generation must skip generating that family's
   candidate at all in Scalp mode, not generate-then-block it after the
   fact.
3. **Regime-conditioned eligibility (section 3).** `TRENDING_UP/DOWN`,
   `RANGING`, `COMPRESSION`, `VOLATILITY_EXPANSION_UP/DOWN`,
   `TRANSITION_OR_UNCERTAIN`/`NEWS_BLACKOUT`/
   `UNTRADEABLE_SPREAD_OR_LIQUIDITY` each prefer/block/penalize/heavily-
   penalize specific families per the table in section 3 — bounded,
   configurable `eligibility_multiplier` values (`[0.10, 1.50]`),
   composed exactly once as `final_score = clamp(0, 100, base_score *
   eligibility_multiplier)`. `RegimeGateComposer.mqh` (TASK-034) already
   implements SOME regime gating (news/spread/liquidity blackout) but not
   this per-family preference/block/penalize table — confirm the overlap
   and scope precisely before implementing, not duplicate it.
4. **Exact-tie rule (section 3).** Among eligible same-direction
   candidates with exactly equal `final_score`: smaller (faster) entry
   timeframe wins; if still tied, alphabetically-first family name wins.
   `ConflictResolver.mqh`'s current tie-break must be checked against this
   exact rule, not assumed already correct.
5. **Scalp-attempt/unchanged-level counters (section 1).** Scalp mode caps
   attempts per session (`InpMaxScalpAttemptsPerSession`) and rejects a
   repeat entry at an unchanged level within the session — neither counter
   exists yet in any module.
6. **Bounded configurable weights.** `IMR_DefaultModeWeights()` is
   currently hard-coded equal weights (`0.25` each) — the spec requires
   these to be genuine, bounded, configurable inputs (matching the
   `eligibility_multiplier` bounding precedent in item 3).

## Files affected

None yet — registered, no design or implementation work done. Expected
scope when started: `StrategyRouter.mqh`, `ConflictResolver.mqh`,
`IntradayModeRouter.mqh`, all five strategy modules
(`SRBounceStrategy.mqh`, `SMCStrategy.mqh`, `TrendFollowingStrategy.mqh`,
`ChartPatternStrategy.mqh`, `PostExpansionRetestStrategy.mqh`),
`RegimeGateComposer.mqh`, and `ThembaAdaptiveIntradayEA.mq5`'s own
`EvaluateAndJournal` — likely this project's largest single architectural
change since TASK-024's original router composition, given every
strategy currently assumes one shared timeframe.

## Out of scope

- Historical-performance-conditioned mode scoring (TASK-002 section 1's
  own dropped component) — TASK-032's territory, unrelated to ordering.
- The compression-timing two-entry-opportunity rule (section 3) is
  already correctly specified and, per `IntradayModeRouter.mqh`'s own
  header, already implemented for the REGIME side — this task only closes
  the mode-first ORDERING gap, not regime-classifier correctness.

## Test plan (once started — not run yet)

1. A `SCALP`-classified bar and a `DAY_TRADE`-classified bar for the same
   underlying price data must route each of the five strategies against
   DIFFERENT context/entry timeframe pairs (per the matrix), verified by a
   hand-constructed fixture where the two timeframes disagree on a
   candidate's own signal.
2. Chart-Pattern Breakout/Reversal must never even be GENERATED as a
   candidate in Scalp mode (not generated-then-blocked) — assert
   `StrategyRouter`'s own candidate list omits it entirely.
3. The exact-tie rule (smaller entry timeframe, then alphabetical family
   name) reproduced against a hand-constructed exact-score tie.
4. Full MetaEditor compile, 0 errors/0 warnings, real log evidence.

## Rejection criteria

Reject if this ships as another post-hoc veto layered on top of the
existing generate-first ordering, if the family x mode timeframe matrix
is approximated by a single shared timeframe with per-family multipliers
instead of genuinely different candidate-generation timeframes, or if
this task's own status is claimed "Done" while any of Specification items
1-6 remain unimplemented.

## Status

Not started — registered, no design or implementation work done yet.
Explicitly named as the reason `TASK-028`/the EA must not be presented as
launch-ready while this remains open, per Codex round-9 P1 finding 10.
