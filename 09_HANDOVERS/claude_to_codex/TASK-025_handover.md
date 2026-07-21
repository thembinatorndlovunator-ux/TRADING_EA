# Claude → Codex handover — TASK-025 (ThembaAdaptiveIntradayEA)

**Note on review availability:** same as TASK-003 through 024 — Codex's
independent-review budget is currently exhausted. Queued. **This is the
single highest-priority task to review whenever budget returns** — it's
the first real, attachable Expert Advisor in the project.

## What this task is

`ThembaAdaptiveIntradayEA.mq5`: the first real `OnInit`/`OnTick` Expert
Advisor, wiring every module from TASK-003 through TASK-024 into one
once-per-completed-bar decision pipeline. **Deliberately journal-only —
never submits, modifies, or closes a position it did not itself open,
because it never opens one at all.** Full detail in
`TASK-025_EA_CONTROLLER.md`.

## What to check, if/when reviewed

1. **The "never submits an order" claim is the single most important
   thing to verify independently** — search this file and everything it
   includes for any `CTrade` call that opens a position (`Buy`, `Sell`,
   `PositionOpen`, `OrderSend`, etc.) reachable from `OnTick`. The only
   trading-adjacent call in this file's own code is
   `ICM_ExecuteIntradayClose`, scoped to this EA's own magic number,
   which never has anything to close since nothing is ever opened under
   it — confirm this reasoning holds, not just that it sounds right.
2. **Once-per-completed-bar evaluation** — confirm `OnTick`'s
   `current_bar_time == g_last_evaluated_bar_time` guard genuinely
   prevents multiple evaluations within the same bar, matching the
   completed-bar-only convention held since TASK-005.
3. **The shared-computation efficiency claim** — confirm regime
   classification, the OHLC/ATR window, and `MarketStructure` are
   genuinely computed once per bar and passed into all five strategies'
   array-based functions, not redundantly recomputed per strategy.
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\ThembaAdaptiveIntradayEA.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently — note the
   `#property version` format quirk this task found (`"0.1"`/`"0.100"`
   both rejected, `"1.00"` accepted).
5. **Runtime verification is the single highest-priority item in the
   entire project's batched verification backlog** — this is the first
   chance to see the complete pipeline run live (attach to a real demo
   chart, confirm the journal file accumulates entries, confirm the
   account's trade history stays empty throughout).

## Files in this task

New: `03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5`,
`TASK-025_EA_CONTROLLER.md`, this file. Modified: `TASKS.md`. No baseline
or prior TASK-00N file touched.
