# Claude → Codex handover — TASK-015 (ICTSMCGeometry)

**Note on review availability:** same as TASK-003 through 014 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`ICTSMCGeometry.mqh`: FVG, order blocks, the V8.11-ported liquidity
sweep/shift mechanism, and premium/discount classification. Full detail
in `TASK-015_ICT_SMC_GEOMETRY.md`.

## What to check, if/when reviewed

1. **The sweep pool/shift index formulas are a direct port of V8.11
   source (1008–1050)** — this is the single most valuable thing to
   independently re-verify against that source directly: `pool_end =
   min(n-2, 4+max(10,sweep_lookback))` and `shift_end = min(n-2,
   2+max(3,shift_lookback))`, confirming the off-by-one/inclusive-
   exclusive handling matches the baseline exactly, not just
   approximately.
2. **The sweep-detection scan order is this task's own formalization**
   (not verbatim from the specification, which describes the concept but
   not exact pseudocode) — flagged explicitly; worth a second opinion,
   especially the same-bar sweep-and-reject case (see
   `TASK-015_ICT_SMC_GEOMETRY.md`'s Risks).
3. **The order-block displacement/OB-candle direction logic** — confirm
   `displacement_bullish && ob_is_bearish → OB_BULLISH` (and the mirror)
   correctly matches standard SMC usage (an order block should be
   opposite in direction to the displacement it precedes).
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_ICTSMCGeometry.mq5" /log:...` and
   confirm 0 errors, 0 warnings independently.
5. **Runtime verification:** the array-based functions' test cases are
   deterministic once confirmed to execute; only the final `CMarketData`
   smoke test is part of the batched TASK-003 through 015 gap.

## Files in this task

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Structure/ICTSMCGeometry.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_ICTSMCGeometry.mq5`,
`TASK-015_ICT_SMC_GEOMETRY.md`, this file. Modified: `TASKS.md`. No
baseline or prior TASK-00N file touched.
