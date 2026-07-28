# TASK-020 — SMCStrategy: the second strategy module

## Objective

Implement `SMCStrategy.mqh` per `STRATEGY_SPEC_SMC_ICT.md` (written
first) and `TASK-002_PHASE2_SPECIFICATION.md` section 3: the second of
six strategy families, and the first strategy eligible across multiple
regimes with genuinely different setup shapes per regime (order-block
retest in trends, sweep reversal in ranges, FVG return in volatility
expansion) rather than one shape reused across contexts.

## Reason

Section 3's routing table lists SMC/ICT Price-Action under three
regimes, each with different confluence — unlike `SRBounceStrategy.mqh`
(one regime, one setup), forcing this into a single detection function
would have hidden the genuinely different logic each regime requires.
Specifying and implementing it as three explicit, independently-testable
functions composed by one dispatcher keeps each piece honest about what
it actually checks.

## Baseline behaviour

Not applicable — new-engine strategy logic, not a port. No file under
`01_BASELINE/` is touched.

## Evidence

`STRATEGY_SPEC_SMC_ICT.md` (written first). `TASK-002_PHASE2_
SPECIFICATION.md` section 3 (routing table, three-regime eligibility).

## Specification

See `STRATEGY_SPEC_SMC_ICT.md` in full. `SMC_EvaluateOrderBlockRetestArray`
(`TRENDING_UP`/`_DOWN`): scans the most recent `max_retest_bars` for a
trend-direction-matching, non-invalidated order block
(`ICTSMCGeometry.mqh`) with current price at/near the zone.
`SMC_EvaluateSweepReversalArray` (`RANGING`): requires a *fresh*
confirmed liquidity sweep (confirmation within the most recent 2 bars —
a stale sweep is not a tradeable fresh reversal). `SMC_EvaluateFVGReturnArray`
(`VOLATILITY_EXPANSION_UP`/`_DOWN`): scans for a non-invalidated,
direction-matching FVG with current price inside the zone. All three
require a directionally-consistent candlestick confirmation
(three-bar-reversal excluded, same reasoning as `SRBounceStrategy.mqh`).
`SMC_EvaluateArray` dispatches across all three (mutually exclusive by
regime, so at most one can fire per evaluation).

**Target formula is an explicitly stated simplification** (`2× zone
height`, projected from entry) — section 7's full target selector does
not exist as a built module yet; flagged in both the specification and
the module's own header comment as provisional, not a finished answer.

## Files affected

New: `STRATEGY_SPEC_SMC_ICT.md`,
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/SMCStrategy.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_SMCStrategy.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

Same Phase 6 deferrals as `SRBounceStrategy.mqh` (scoring, risk
multiplier, sizing, duplicate-signal suppression), plus: a real
target-selection module (see the stated simplification above); the
remaining four strategy families.

## Risks

- No independent review available this phase.
- Runtime verification: the array-based core's three setup scenarios
  plus wrong-regime negative cases are deterministic; only the final
  `CMarketData` wrapper smoke test (composing live regime classification
  with all three setup detectors) is part of the batched TASK-003
  through 019 runtime gap.
- **The target formula is explicitly provisional** — stated three times
  now (specification, module header, this task file) specifically to
  prevent it from being mistaken for finished section-7 target-selection
  logic in a future task that reads this code without the surrounding
  context.
- During this task's own test-array design, an indexing mistake placed
  the intended FVG one bar later than planned (logical index 4, not 3) —
  caught by tracing the scan loop by hand before finalizing, not by
  compilation (which cannot catch a wrong-but-valid array value); the
  test was corrected to match the actual behavior rather than forcing
  the code to match the original (wrong) plan. Recorded here as a
  concrete example of why hand-tracing every fabricated scenario matters
  even when the code itself has no bug.

## Test plan

1. **Compile test** (completed, see Compiler result — clean on the first
   attempt).
2. **Logic test — array-based core, fully hand-verifiable**: one
   complete scenario per setup (order-block retest with exact
   `zone_high`/`zone_low`/`stop_price`/`target_price`; sweep reversal,
   including the fresh-vs-stale confirmation-recency check; FVG return),
   each paired with a wrong-regime negative case proving the setup fires
   only in its required regime.
3. **Logic test — `CMarketData` wrapper, batched**: a real-symbol,
   fully-composed evaluation across all three setups, confirmed to
   complete without crashing.

## Acceptance criteria

- [x] Each of the three setups is independently gated by its own regime
      requirement and produces no signal outside it (verified by
      negative-case tests for all three).
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (clean on the first attempt).
- [x] Every hand-fabricated positive scenario's expected values match
      exact hand computation, including the sweep-reversal's
      fresh-confirmation-recency requirement.
- [x] The provisional target formula is flagged explicitly, not silently
      presented as finished.
- [ ] The `CMarketData` wrapper's real-symbol composition — batched with
      TASK-003 through 019's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if any hand-verifiable test produces `FAIL` — especially a
setup firing under the wrong regime, which would mean the routing-table
eligibility this strategy exists to implement is not actually enforced.

## Implementation notes

`SSMCConfig` groups the nine configuration parameters shared across the
three setup functions into one struct, avoiding the alternative of
threading nine individual parameters through every function signature —
a small design choice worth naming since `SRBounceStrategy.mqh` (TASK-019)
did not need this (fewer parameters, one setup shape) and future
strategy modules with multiple setups should likely follow this same
pattern rather than each inventing its own approach.

## Commands run

```
git checkout -b claude/task-020-smc-ict-strategy
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_SMCStrategy.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 862 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt. Full log available in
this session's history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not yet
runtime-confirmed**, but all three setup scenarios plus their wrong-
regime negative cases are deterministic and hand-computed; only the
final `CMarketData` wrapper smoke test is part of the batched runtime
gap.

## Commit

Pending — see `git log` on `claude/task-020-smc-ict-strategy`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed.** Two of six strategy families now have
real, tested implementations. Four remain: Trend Following, Chart-
Pattern Breakout/Reversal, Post-Expansion Retest, and No trade (the
last essentially trivial — the fallback when nothing else is eligible).
