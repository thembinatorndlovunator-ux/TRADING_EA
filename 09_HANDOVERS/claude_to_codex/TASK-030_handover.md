# Claude → Codex handover — TASK-030 (ExitManager, begins Phase 8)

**Note on review availability:** same as TASK-003 through 029 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`ExitManager.mqh`: 14 pure functions implementing every exit-management
formula from section 7 of `TASK-002_PHASE2_SPECIFICATION.md` that
actually has a concrete definition — break-even arming, structure/ATR
trailing, the never-widen-a-stop invariant, time stop, profit-lock (plus
its partial-lock recheck), and both giveback-guard models. Full detail,
including a genuine spec gap this task explicitly did NOT fill, in
`TASK-030_EXIT_MANAGER.md`.

## What to check, if/when reviewed

1. **The "momentum-failure exit" gap claim** — confirm by searching
   `TASK-002_PHASE2_SPECIFICATION.md` yourself that section 7's exit-
   priority item 4 genuinely has no formula defined anywhere else in
   the document (this task claims it appears exactly once, in the
   priority list itself) — if you find a definition this task missed,
   that's the single most valuable correction you could make here.
2. **`EM_ApplyTrailNeverWiden`'s direction logic** — confirm
   `MathMax` for longs / `MathMin` for shorts is actually the tighter
   direction in both cases, not swapped.
3. **The giveback-guard functions' interpretation of section 7's
   prose** — the spec gives bounds/defaults but not a fully worked
   example (unlike section 8's risk-cash formula); confirm the
   percent-of-peak (V6.37) vs. absolute-floor (V8.11) model split and
   the floor-overriding-a-lower-percentage-trigger behavior in
   `EM_ShouldGivebackCloseV637` match what section 7 actually intends.
4. **The swing-pivot hand-traced test cases** — re-trace
   `Test_ExitManager.mq5`'s fabricated `highs[]`/`lows[]` arrays (depth
   1, max_lookback 3) against `SwingEngine.mqh`'s actual comparison
   operators yourself; this is the same kind of array-indexing trace
   that caught a real transcription slip in TASK-020's FVG test.
5. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_ExitManager.mq5" /log:...` and
   confirm 0 errors, 0 warnings independently.
6. **The scope-boundary decision to defer the orchestrator/live-wiring**
   — confirm the reasoning (needs `DailyWeeklyLimits`/`NewsManager`/
   `MarketStructure` composed together, plus a stop-modification
   function that doesn't exist in `OrderManager.mqh` yet, plus new
   per-position state tracking) is a genuine blocker, not just deferred
   convenience.

## Files in this task

New:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/ExitManager.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_ExitManager.mq5`,
`TASK-030_EXIT_MANAGER.md`, this file. `TASKS.md` updated with this
task's own row. No file under `01_BASELINE/` touched.
`ThembaAdaptiveIntradayEA.mq5` is deliberately NOT modified — see the
task file's Scope Boundary section.
