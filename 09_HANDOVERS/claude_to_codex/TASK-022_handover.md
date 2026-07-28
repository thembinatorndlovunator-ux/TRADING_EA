# Claude → Codex handover — TASK-022 (TrendFollowingStrategy)

**Note on review availability:** same as TASK-003 through 021 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`TrendFollowingStrategy.mqh`: the fourth strategy family, two setups
(trendline pullback, momentum continuation), including the concrete fix
for V6.37's confirmed two-anchor trendline defect. Specification written
first in `STRATEGY_SPEC_TREND_FOLLOWING.md`. Full detail in
`TASK-022_TREND_FOLLOWING_STRATEGY.md`.

## What to check, if/when reviewed

1. **`TF_FindTrendlineArray`'s middle-anchor validation is the single
   most important thing to verify** — this is the direct fix for
   V6.37's confirmed defect; confirm independently that
   `CPT_LinearInterpolate(p3, v3, p1, v1, p2)` genuinely computes "where
   the middle anchor should be if it were exactly on the line through
   the outer two," and that the rejection threshold
   (`current_atr * middle_tolerance_atr`) is a reasonable tolerance, not
   arbitrarily loose or tight.
2. **The momentum-continuation regime eligibility** — confirm the claim
   that it's genuinely eligible under both `TRENDING` and
   `VOLATILITY_EXPANSION` regimes matches section 3's routing table
   precisely (not just "probably similar").
3. **The stated stop/target simplifications** — confirm they're flagged
   clearly enough (specification, module header, task file) to avoid
   being mistaken for finished logic in a future task.
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_TrendFollowingStrategy.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
5. **Runtime verification:** the two setup scenarios plus four negative
   cases are deterministic once confirmed to execute; only the final
   `CMarketData` wrapper smoke test is part of the batched TASK-003
   through 022 gap.

## Files in this task

New: `STRATEGY_SPEC_TREND_FOLLOWING.md`,
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/TrendFollowingStrategy.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_TrendFollowingStrategy.mq5`,
`TASK-022_TREND_FOLLOWING_STRATEGY.md`, this file. Modified: `TASKS.md`.
No baseline or prior TASK-00N file touched.
