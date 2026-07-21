# Claude → Codex handover — TASK-018 (ChartPatternEngine)

**Note on review availability:** same as TASK-003 through 017 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`ChartPatternEngine.mqh`: double top/bottom and head-and-shoulders/
inverse, per section 6, cross-checked against
`EA Files/SRbounce/Idenitfying-Chart-Patterns.pdf` during
implementation. Full detail in `TASK-018_CHART_PATTERN_ENGINE.md`.

## What to check, if/when reviewed

1. **The sloped-neckline linear interpolation arithmetic is the single
   most error-prone part of this task** — `CPT_LinearInterpolate` and
   its three evaluation points (breakout bar, head bar, RS bar) were
   hand-traced twice during this session, but an independent third
   derivation of the head-and-shoulders test scenario's exact numbers
   (`target=62.25`, `boundary_price=86.5`) would be the highest-value
   review action here.
2. **The self-caught trend-prerequisite omission** — confirm
   `CPT_HasPriorTrend(closes, ls, trend_bars, true/false)` is genuinely
   applied to the correct reference point (`ls`, the leftmost/oldest
   shoulder, per section 6's "before the first peak" language) in both
   `CPT_DetectHeadAndShouldersArray` and its inverse.
3. **The extreme-vs-average target-projection correction** (double/
   triple top-bottom using the highest peak/lowest trough, not an
   average) — confirm this matches the cited source
   (`EA Files/SRbounce/Idenitfying-Chart-Patterns.pdf`, itself citing
   Kirkpatrick & Dodge) and is a genuine improvement over this
   project's own earlier, unreviewed spec text.
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_ChartPatternEngine.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
5. **Runtime verification:** the array-based functions' four scenarios
   are deterministic once confirmed to execute; only the final
   `CMarketData` smoke test is part of the batched TASK-003 through 018
   gap.

## Files in this task

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/ChartPatternEngine.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_ChartPatternEngine.mq5`,
`TASK-018_CHART_PATTERN_ENGINE.md`, this file. Modified: `TASKS.md`. No
baseline or prior TASK-00N file touched.
