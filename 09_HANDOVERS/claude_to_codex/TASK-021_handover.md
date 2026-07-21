# Claude → Codex handover — TASK-021 (ChartPatternStrategy)

**Note on review availability:** same as TASK-003 through 020 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`ChartPatternStrategy.mqh`: the third strategy family, two setups
(trend-breakout-retest, range-boundary), composing `ChartPatternEngine.mqh`
and `CandlestickPatternEngine.mqh`. Specification written first in
`STRATEGY_SPEC_CHART_PATTERN.md`. Full detail in
`TASK-021_CHART_PATTERN_STRATEGY.md`.

## What to check, if/when reviewed

1. **The "continuation, not counter-trend" reading of a reversal pattern
   breaking in the trend's own direction** — confirm this interpretation
   of section 3's routing table is correct, since it's easy to misread a
   "double top" as inherently bearish/counter-trend regardless of
   context.
2. **The uninitialized-variable fix** — confirm the explicit
   zero-initialization of `r` in `CPS_EvaluateTrendBreakoutRetestArray`
   genuinely resolves the compiler's concern and that the four
   conditional-assignment branches really do guarantee `r` is valid
   whenever `found_type != CPT_NONE` is reached downstream.
3. **The array-extension safety claim** — the test reuses TASK-018's
   double-top/bottom arrays with an added index-0 candle; confirm
   independently that this doesn't silently change `breakout_index` (the
   task file claims the scan loop's short-circuit behavior makes this
   safe — worth re-tracing).
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_ChartPatternStrategy.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
5. **Runtime verification:** the two setup scenarios plus three negative
   cases are deterministic once confirmed to execute; only the final
   `CMarketData` wrapper smoke test is part of the batched TASK-003
   through 021 gap.

## Files in this task

New: `STRATEGY_SPEC_CHART_PATTERN.md`,
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/ChartPatternStrategy.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_ChartPatternStrategy.mq5`,
`TASK-021_CHART_PATTERN_STRATEGY.md`, this file. Modified: `TASKS.md`.
No baseline or prior TASK-00N file touched.
