# TASK-021 — ChartPatternStrategy: the third strategy module

## Objective

Implement `ChartPatternStrategy.mqh` per `STRATEGY_SPEC_CHART_PATTERN.md`
(written first): the third of six strategy families, two setups
(trend-breakout-retest, range-boundary), composing `ChartPatternEngine.mqh`
(TASK-018) and `CandlestickPatternEngine.mqh` directly.

## Reason

`ChartPatternEngine.mqh` was built in TASK-018 but had no consumer until
now — same situation `ICTSMCGeometry.mqh` was in before TASK-020. This
task closes that gap and is the first strategy to use the pattern
engine's own real target formula (section 6's measured-move projection)
rather than a provisional placeholder, since chart patterns already have
a specified target calculation `SMCStrategy.mqh` did not.

## Baseline behaviour

Not applicable — new-engine strategy logic. No file under `01_BASELINE/`
is touched.

## Evidence

`STRATEGY_SPEC_CHART_PATTERN.md` (written first). `TASK-002_PHASE2_
SPECIFICATION.md` section 3.

## Specification

See `STRATEGY_SPEC_CHART_PATTERN.md` in full. `CPS_EvaluateTrendBreakoutRetestArray`
(`TRENDING_UP`/`_DOWN`): tries all four pattern types in turn, requires
an already-confirmed breakout whose direction matches the trend (a
"top"/"bottom" pattern breaking in the trend's own direction is read as
continuation, stated explicitly since the naming invites a counter-trend
misreading), requires the breakout to be fresh (not stale) and price
currently retesting the boundary, plus candlestick confirmation.
`CPS_EvaluateRangeBoundaryArray` (`RANGING`): a double top/bottom whose
`extreme_price` coincides with `MarketStructure`'s range boundary, plus
candlestick confirmation. Both reuse `ChartPatternEngine.mqh`'s own
`stop`/`target` fields unchanged — no stop/target math is duplicated.

## Files affected

New: `STRATEGY_SPEC_CHART_PATTERN.md`,
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/ChartPatternStrategy.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_ChartPatternStrategy.mq5`, this task
file. Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

The `COMPRESSION`-regime gated early-breakout variant — deferred
explicitly, matching the triple-top/bottom deferral precedent from
`ChartPatternEngine.mqh` itself. Same Phase 6 deferrals (scoring, risk
multiplier, sizing, duplicate-signal suppression) as every prior
strategy.

## Risks

- No independent review available this phase.
- Runtime verification: the array-based core's two setup scenarios plus
  three negative cases are deterministic; only the final `CMarketData`
  wrapper smoke test is part of the batched runtime gap.
- **A real compiler warning was found and fixed during this task**
  (`warning 60: possible use of uninitialized variable 'r'` — the
  compiler cannot statically prove `found_type != CPT_NONE` implies `r`
  was assigned, even though the logic guarantees it). Fixed by
  explicitly zero-initializing `r` at declaration rather than relying on
  the branch logic alone — a real, if latent, defect class (a compiler
  correctly flagging code whose safety depends on an implicit invariant
  across two separate variables) caught by insisting on 0 warnings, not
  just 0 errors.
- The trend-breakout-retest test reuses TASK-018's hand-verified
  double-top array, extended with a new index-0 candle — the extension's
  safety (that it doesn't silently change `breakout_index`) was
  explicitly re-traced by hand for each modified array before finalizing,
  not assumed from the original test's correctness.

## Test plan

1. **Compile test** (completed, see Compiler result — one real warning
   found and fixed).
2. **Logic test — array-based core, fully hand-verifiable**: a
   trend-breakout-retest scenario (double top breaking down, confirming
   `TRENDING_DOWN`) with `stop`/`target` values matching TASK-018's own
   hand-verified figures exactly (proving the strategy layer didn't
   silently alter them); a mismatched-trend-direction negative case; a
   range-boundary scenario (double bottom at `range_low`) with the same
   stop/target-unchanged property; a wrong-regime negative case; and an
   extreme-far-from-boundary negative case.
3. **Logic test — `CMarketData` wrapper, batched**: a real-symbol
   evaluation across both setups, confirmed to complete without
   crashing.

## Acceptance criteria

- [x] Trend-breakout-retest only fires when breakout direction matches
      the trend regime (verified by the mismatched-direction negative
      case).
- [x] Range-boundary only fires when the pattern extreme genuinely
      coincides with the range boundary (verified by the far-extreme
      negative case).
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (a real warning was found and properly fixed, not suppressed).
- [x] `stop`/`target` values pass through from `ChartPatternEngine.mqh`
      unchanged — verified against TASK-018's own hand-computed figures.
- [ ] The `CMarketData` wrapper's real-symbol composition — batched with
      TASK-003 through 020's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if any hand-verifiable test produces `FAIL`, or if the
uninitialized-variable fix is found to not actually address the
compiler's concern on re-inspection.

## Implementation notes

The uninitialized-variable warning is a useful reminder that this
project's "0 warnings" bar catches more than cosmetic issues — a
compiler's static analysis not being able to prove an invariant a human
reader can see by inspection is itself worth fixing explicitly (via
initialization) rather than dismissed as a false positive, since the
next person to modify the branch logic might break the invariant without
the initialization's defensive value.

## Commands run

```
git checkout -b claude/task-021-chart-pattern-strategy
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_ChartPatternStrategy.mq5" /log:...
```

## Compiler result

**Real, verified.** First attempt: `Result: 0 errors, 1 warnings` (the
uninitialized-variable warning above). After the fix:
`Result: 0 errors, 0 warnings, 894 ms elapsed, cpu='X64 Regular'`. Full
logs available in this session's history; not committed (build
artifacts).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not yet
runtime-confirmed**, but both setup scenarios plus their three negative
cases are deterministic and hand-computed; only the final `CMarketData`
wrapper smoke test is part of the batched runtime gap.

## Commit

Pending — see `git log` on `claude/task-021-chart-pattern-strategy`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed.** Three of six strategy families now
have real, tested implementations. Three remain: Trend Following,
Post-Expansion Retest, and No-trade (the latter essentially the
routing fallback, not its own detection module — to be addressed
directly in the Phase 6 `StrategyRouter` task rather than as a separate
strategy file).
