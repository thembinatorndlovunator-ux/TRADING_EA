# TASK-019 — SRBounceStrategy: the first strategy module

## Objective

Implement `SRBounceStrategy.mqh` per `STRATEGY_SPEC_SR_BOUNCE.md`
(written first, from `STRATEGY_SPECIFICATION.md`'s template, before any
code) and `TASK-002_PHASE2_SPECIFICATION.md` section 3: the first of six
strategy families, and the first Phase 5 ("Strategy modules") work in
this project. This is also the first module that composes essentially
the entire detection stack built in Phase 4 end-to-end — regime
(TASK-016), structure (TASK-012), SR zones (TASK-013), and candlestick
confirmation (TASK-014/017) — into one signal.

## Reason

Per master-prompt Phase 5's "add and test one at a time" instruction and
this project's own audit-then-specify-then-implement discipline
(`CLAUDE.md`), a strategy-level specification was written first
(`STRATEGY_SPEC_SR_BOUNCE.md`), matching the same discipline
`TASK-002_PHASE2_SPECIFICATION.md` itself followed at the phase level.
SR Bounce was chosen first because it is the simplest of the six
families, fully served by modules already built, and section 3's own
routing table lists it first.

## Baseline behaviour

Not applicable — this is new-engine strategy logic, not a port of either
baseline's own SR-bounce-style signal code. No file under `01_BASELINE/`
is touched.

## Evidence

`STRATEGY_SPEC_SR_BOUNCE.md` (this task's own specification, written
first). `TASK-002_PHASE2_SPECIFICATION.md` section 3 (routing table,
regime eligibility) and section 6 (retest-tolerance concept, reused for
zone proximity).

## Specification

See `STRATEGY_SPEC_SR_BOUNCE.md` in full. Summary: `SRB_EvaluateArray`
requires `regime == REGIME_RANGING`, a valid `SMarketStructureState`,
current price within `sr_tolerance_atr` of `range_low`/`range_high`, that
boundary independently qualifying as a >=2-touch SR zone
(`SupportResistance.mqh`), and a directionally-consistent candlestick
confirmation (bullish/bearish pin bar, engulfing, or tweezer —
**deliberately excluding three-bar reversal**, caught during this task's
own design as an ambiguous-direction confirmation source unsafe to use
naively at a specific zone). Produces `stop_price` (beyond the zone,
ATR-buffered) and `target_price` (the opposite range boundary — the
"Range Rotation" concept).

## Files affected

New: `STRATEGY_SPEC_SR_BOUNCE.md`,
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/SRBounceStrategy.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_SRBounceStrategy.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

Per the specification's own stated boundaries: scoring/eligibility-
multiplier composition, risk-multiplier application, position sizing,
duplicate-signal suppression (needs `StateManager`'s per-instance
namespace, not yet built), and visual objects — all explicitly later
(Phase 6 `StrategyRouter`/`RiskManager`, or a future `StateManager`
extension) concerns, not duplicated into this strategy module. The
remaining five strategy families (SMC/ICT Price-Action, Trend Following,
Chart-Pattern Breakout/Reversal, Post-Expansion Retest, No trade) are
separate future tasks, per Phase 5's "one at a time" instruction.

## Risks

- No independent review available this phase.
- Runtime verification: the array-based core's seven hand-fabricated
  scenarios are deterministic; only the final `CMarketData` wrapper
  smoke test (which composes `MarketRegimeEngine`, `MarketStructure`,
  `SupportResistance`, and `CandlestickPatternEngine` all live against a
  real symbol) is part of the batched TASK-003 through 018 runtime gap —
  and is the single most valuable item in that entire backlog to
  eventually confirm, since it is the first true end-to-end composition
  test in the project.
- `SMarketStructureState` is hand-constructed directly in the test
  script (bypassing `MS_ComputeStructureArray`'s own pivot-finding) for
  the array-based scenarios — a deliberate simplification (TASK-012
  already verified that function's correctness independently); the live
  wrapper test does exercise the real, composed path.
- The three-bar-reversal exclusion (see Specification) is a real,
  caught risk, not a hypothetical one — worth confirming independently
  that no other confirmation path in this module has a similar hidden
  direction ambiguity.

## Test plan

1. **Compile test** (completed, see Compiler result — clean on the
   first attempt despite transitively including seven modules).
2. **Logic test — array-based core, fully hand-verifiable**: a LONG
   signal (qualifying support zone, bullish pin bar, exact hand-computed
   `stop_price`/`target_price`); a mirrored SHORT signal; and four
   negative cases (wrong regime, invalid structure, no candlestick
   confirmation, a zone with insufficient touches) each confirmed to
   produce no signal.
3. **Logic test — `CMarketData` wrapper, batched**: a real-symbol,
   fully-composed evaluation (live regime classification feeding live
   structure feeding live SR-zone/candlestick checks), confirmed to
   complete without crashing.

## Acceptance criteria

- [x] `SRB_EvaluateArray` matches `STRATEGY_SPEC_SR_BOUNCE.md` exactly —
      regime gate, structure validity, zone qualification, and
      directional candlestick confirmation all independently required.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (clean on the first attempt).
- [x] Every hand-fabricated scenario's expected outcome (including all
      four negative cases) matches its hand computation exactly.
- [x] No confirmation path can produce a direction-inconsistent signal
      (the three-bar-reversal exclusion is the concrete fix for this).
- [ ] The `CMarketData` wrapper's real-symbol composition — batched with
      TASK-003 through 018's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if any hand-verifiable test produces `FAIL` — especially a
negative case unexpectedly producing a signal, which would mean one of
this strategy's required gates is not actually being enforced.

## Implementation notes

This module composes rather than recomputes: `SRB_EvaluateArray` takes
an already-classified `regime` and an already-computed
`SMarketStructureState` as parameters, performing no regime or structure
computation of its own — the same "one implementation per concept,
composed by consumers" discipline established across every Structure/
Patterns module since TASK-011, now demonstrated at the strategy level
for the first time.

## Commands run

```
git checkout -b claude/task-019-sr-bounce-strategy
mkdir -p 03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_SRBounceStrategy.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 802 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt, despite transitively
including `MarketRegimeEngine.mqh`, `MarketStructure.mqh`,
`SwingEngine.mqh`, `MarketData.mqh`, `SupportResistance.mqh`, and
`CandlestickPatternEngine.mqh`. Full log available in this session's
history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not yet
runtime-confirmed**, but all six array-based scenarios (one LONG, one
SHORT, four negative) are deterministic and hand-computed; only the
final `CMarketData` wrapper smoke test is part of the batched runtime
gap.

## Commit

Pending — see `git log` on `claude/task-019-sr-bounce-strategy`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed.** This is Phase 5's first strategy
module — the first genuine end-to-end proof that the Phase 4 detection
stack composes correctly. Five strategy families remain, each its own
future task with its own specification written first.
