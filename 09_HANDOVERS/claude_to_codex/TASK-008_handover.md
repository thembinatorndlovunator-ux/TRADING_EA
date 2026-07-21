# Claude → Codex handover — TASK-008 (DailyWeeklyLimits, EquityPeakManager, DrawdownController)

**Note on review availability:** same as TASK-003 through 007 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

The `StateManager`-backed, persisted-state parts of Phase 3's "Risk
manager" bullet: period-change daily/weekly loss tracking with
deterministic cash-flow rebasing, daily and all-time equity peaks, and
the drawdown-based risk-reduction formula. Full detail in
`TASK-008_DAILY_WEEKLY_LIMITS.md`.

## What to check, if/when reviewed

1. **The period-change fix is the most important thing to verify:**
   confirm `DWL_GetDailyChangePercent`'s formula (`100*(equity-start)/
   start`) genuinely fixes round-3's finding (a position unchanged since
   the boundary must show ~0% change, not its full floating P/L). The
   test script doesn't hand-verify this with a synthetic position (no
   trades are placed) — it's a structural/formula check, not a live-
   position scenario. Worth a second look at whether a live-position
   scenario is needed to fully close this out.
2. **The 8-day cash-flow scan window** (`DailyWeeklyLimits.mqh`'s
   `DWL_ApplyCashFlowAdjustments`) is a stated, deliberate bound — confirm
   this trade-off (missing a cash event during an EA outage longer than
   8 days) is acceptable, or whether it should be widened/made
   configurable.
3. **`ulong` deal ticket stored as `double`** — confirm this is truly a
   non-issue for realistic account lifetimes, or flag if it should be
   handled differently (e.g., storing the low/high 32 bits separately).
4. **Daily peak vs. account peak separation** — confirm the two are
   genuinely independent (distinct field prefixes, distinct reset
   triggers) and that nothing accidentally shares state between them.
5. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_DailyWeeklyLimits.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
6. **Runtime verification is a known, batched item** across TASK-003
   through 008.

## Files in this task

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/DailyWeeklyLimits.mqh`,
`EquityPeakManager.mqh`, `DrawdownController.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_DailyWeeklyLimits.mq5`,
`TASK-008_DAILY_WEEKLY_LIMITS.md`, this file. Modified: `TASKS.md`. No
baseline or prior TASK-00N file touched.
