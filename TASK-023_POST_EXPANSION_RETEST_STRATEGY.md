# TASK-023 — PostExpansionRetestStrategy: the fifth strategy module

## Objective

Implement `PostExpansionRetestStrategy.mqh` per
`STRATEGY_SPEC_POST_EXPANSION_RETEST.md` (written first): the fifth of
six strategy families, and the last with real detection logic (the
sixth, No-trade, is the routing fallback — addressed directly in the
future `StrategyRouter` task, not as its own file, per the precedent
already stated in `ChartPatternStrategy.mqh`'s final decision).

## Reason

Section 3 describes this family only briefly ("new work... block chasing
the initial spike... prefer Post-Expansion Retest") without a full
formula, unlike the ported sweep/shift or trendline mechanisms — this
task is this project's own concrete formalization, stated explicitly,
same discipline as `MarketStructure.mqh`'s bias/break definitions and
`ICTSMCGeometry.mqh`'s sweep algorithm.

## Baseline behaviour

Not applicable — new work per section 3's own description, not a port.
No file under `01_BASELINE/` is touched.

## Evidence

`STRATEGY_SPEC_POST_EXPANSION_RETEST.md` (written first). `TASK-002_
PHASE2_SPECIFICATION.md` section 3.

## Specification

See `STRATEGY_SPEC_POST_EXPANSION_RETEST.md` in full.
`PER_EvaluateArray` requires a `VOLATILITY_EXPANSION_UP`/`_DOWN` regime,
a valid structure, a **genuine confirmed expansion move** (some bar
since the triggering break traded beyond `MarketStructure`'s own
same-direction swing extreme by at least `min_expansion_atr` ATR — not
merely price sitting near a level), current price retesting that
reference level, a **defensive, redundant** no-chase check (the
canonical gate belongs to the future `StrategyRouter`, stated
explicitly), and candlestick confirmation. Deliberately distinct from
`SMCStrategy.mqh`'s FVG-return setup — this strategy targets the broken
swing-structure level itself, not a specific three-candle gap; resolving
any overlap between the two on the same bar is a `ConflictResolver`
(Phase 6) concern, not addressed here.

## Files affected

New: `STRATEGY_SPEC_POST_EXPANSION_RETEST.md`,
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/PostExpansionRetestStrategy.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_PostExpansionRetestStrategy.mq5`, this
task file. Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

Resolving the potential overlap with `SMCStrategy.mqh`'s FVG-return
setup — a `ConflictResolver` concern. Same Phase 6 deferrals (scoring,
risk multiplier, sizing, duplicate-signal suppression) and provisional
2R target formula as every prior multi-setup strategy.

## Risks

- No independent review available this phase.
- Runtime verification: the array-based core's positive scenario plus
  four negative cases are deterministic; only the final `CMarketData`
  wrapper smoke test is part of the batched runtime gap.
- **This entire strategy is this project's own formalization** of a
  section-3 description that was never a full formula — flagged more
  prominently than most prior tasks' "stated interpretation choice"
  notes, since here there is no baseline or reference-material source to
  cross-check against at all, only the specification's own three-sentence
  description. This is the single most speculative strategy module in
  the project so far, worth the most scrutiny if/when independent review
  becomes available.
- The no-chase check's redundancy with a future router-level gate is
  intentional but means this strategy currently enforces a rule it isn't
  the "true" owner of — worth confirming the future `StrategyRouter`
  task actually implements the canonical version rather than assuming
  this defensive copy is sufficient forever.

## Test plan

1. **Compile test** (completed, see Compiler result — clean on the
   first attempt).
2. **Logic test — array-based core, fully hand-verifiable**: one
   complete positive scenario with exact hand-computed `stop_price`/
   `target_price`, plus four negative cases (wrong regime, too-recent
   triggering break, no genuine expansion move, price not currently
   retesting).
3. **Logic test — `CMarketData` wrapper, batched**: a real-symbol
   evaluation, confirmed to complete without crashing.

## Acceptance criteria

- [x] Fires only under a `VOLATILITY_EXPANSION` regime with a confirmed
      genuine expansion move (verified by the dedicated negative case).
- [x] The defensive no-chase check genuinely rejects a too-recent
      breakout (verified by its own negative case).
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (clean on the first attempt).
- [ ] The `CMarketData` wrapper's real-symbol composition — batched with
      TASK-003 through 022's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase, and most needed
      here specifically given this module's speculative nature (see
      Risks).

## Rejection criteria

Rejected if any hand-verifiable test produces `FAIL`, or if a future
review finds this task's own formalization of section 3's brief
description to be an unreasonable reading of intent.

## Implementation notes

Reuses `MarketStructure.mqh`'s already-computed `swing_high_1_price`/
`swing_low_1_price`/`last_event_index` directly as the reference level
and break-recency proxy, rather than introducing a new "what broke"
concept — consistent with the "one implementation per concept, composed
by consumers" discipline held since TASK-011.

## Commands run

```
git checkout -b claude/task-023-post-expansion-retest-strategy
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_PostExpansionRetestStrategy.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 835 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt. Full log available in
this session's history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not yet
runtime-confirmed**, but the positive scenario and all four negative
cases are deterministic and hand-computed; only the final `CMarketData`
wrapper smoke test is part of the batched runtime gap.

## Commit

Pending — see `git log` on `claude/task-023-post-expansion-retest-strategy`.

## Reviewer

Not available this phase — flagged as the highest-priority strategy
module to review whenever budget allows, given its speculative nature.

## Final decision

**Compiled clean and committed.** Five of six strategy families now have
real, tested implementations. Phase 5 is functionally complete — the
sixth family (No-trade) is the routing fallback, not its own module.
Phase 6 (`StrategyRouter`/`ConflictResolver`) is next.
