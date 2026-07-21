# Claude → Codex handover — TASK-010 (IntradayCloseManager)

**Note on review availability:** same as TASK-003 through 009 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`IntradayCloseManager.mqh`: closes every one of this EA's own open
positions and cancels every one of its own pending orders at the
configured intraday boundary. This completes Phase 3's "Common core"
list. Full detail in `TASK-010_INTRADAY_CLOSE_MANAGER.md`.

## What to check, if/when reviewed

1. **Own-magic scoping is the single most safety-critical check:**
   confirm `ICM_CloseAllOwnedPositions`/`ICM_CancelAllOwnedPendingOrders`
   truly never touch a position/order under a different magic number,
   under every iteration edge case (e.g., does `PositionGetTicket(i)`
   reliably select the position's context for the immediately-following
   `PositionGetInteger(POSITION_MAGIC)` call, or could there be a race if
   positions close between the `PositionsTotal()` count and the loop
   body — worth confirming this is safe under MQL5's actual execution
   model, which is single-threaded per `OnTick`/script run, so this
   should be safe, but worth an explicit second opinion).
2. **The once-per-day guard's fail-open-to-retry design** — confirm
   retrying every tick after a partial failure (rather than backing off)
   is the right choice, not a risk of hammering the broker with repeated
   close attempts in a real failure scenario (e.g., a persistently
   rejected order).
3. **This task's test script performs real trading actions** (a demo
   position and pending order, under a dedicated test magic) — this is
   flagged prominently in the script and task file; confirm the safety
   checks around it (refusing to run if the test magic already has open
   state, minimum volume only, far-from-market pending price) are
   sufficient.
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_IntradayCloseManager.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
5. **Runtime verification is a known, batched item** across TASK-003
   through 010 — but this one specifically requires deliberate,
   attentive execution (real demo trading actions), not incidental
   batching with the purely read-only/state-scoped scripts from earlier
   tasks.

## Files in this task

New:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/IntradayCloseManager.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_IntradayCloseManager.mq5`,
`TASK-010_INTRADAY_CLOSE_MANAGER.md`, this file. Modified: `TASKS.md`. No
baseline or prior TASK-00N file touched.
