# Claude → Codex handover — TASK-026 (OrderManager)

**Note on review availability:** same as TASK-003 through 025 — Codex's
independent-review budget is currently exhausted. Queued. **This is a
strong candidate to prioritize whenever budget returns** — it's the
first module in the project capable of submitting a real order, and the
scope-boundary claim below is exactly the kind of claim that most
needs an independent check rather than a self-certification.

## What this task is

`OrderManager.mqh`: `OM_CalculateVolume` (position sizing, built as the
algebraic inverse of `RiskManager.mqh`'s `RM_ComputeRiskCash`),
`OM_OpenPosition` (real market-order submission via `CTrade` with
explicit result-code checking and position-ticket resolution),
`OM_ClosePosition` (single-ticket close, own-magic-only). Full detail
in `TASK-026_ORDER_MANAGER.md`.

## What to check, if/when reviewed

1. **The "not wired into the live EA" claim is the single most
   important thing to verify independently** — confirm
   `ThembaAdaptiveIntradayEA.mq5` does not `#include` `OrderManager.mqh`
   and its `OnTick`/`EvaluateAndJournal` never calls `OM_OpenPosition`
   or `OM_CalculateVolume`. This task's own description claims this
   module exists but is dormant; verify that claim by inspection, not
   just by reading the claim.
2. **`OM_CalculateVolume`'s round-down-never-up rule** — trace the
   non-exact-step-boundary test (test 2 in `Test_OrderManager.mq5`:
   loss_distance 3.00, expected volume 0.33 not 0.34) by hand against
   the actual `MathFloor` arithmetic in the file.
3. **The widen-vs-reject fork at `volume_min`** — confirm
   `RM_BrokerMinVolumeExceedsCap` (already-reviewed TASK-007 code) is
   the ONLY gate deciding widen-vs-reject, and that `OM_CalculateVolume`
   does not duplicate or diverge from that logic.
4. **`OM_OpenPosition`'s position-ticket resolution** — confirm the
   post-open scan for `(symbol, magic)` is a reasonable approach given
   nothing in this project yet opens concurrent positions under the
   same magic/symbol pair (flagged as a risk in the task file, not
   silently assumed safe).
5. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_OrderManager.mq5" /log:...` and
   confirm 0 errors, 0 warnings independently.
6. **The real-order test (tests 7-8)** is demo-account-only and follows
   `Test_IntradayCloseManager.mq5`'s established safety pattern (refuses
   to run if the dedicated test magic already has anything open, verifies
   full cleanup at the end) — confirm the pattern was followed correctly,
   particularly the wrong-magic-refusal test's cleanup path (test 8 must
   not leak a position even when the wrong-magic close is correctly
   refused).

## Files in this task

New:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_OrderManager.mq5`,
`TASK-026_ORDER_MANAGER.md`, this file. Modified: `TASKS.md`.
`ThembaAdaptiveIntradayEA.mq5` is deliberately NOT modified — see the
task file's Scope Boundary section.
