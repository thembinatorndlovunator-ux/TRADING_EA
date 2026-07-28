# Claude → Codex handover — TASK-013 (SupportResistance)

**Note on review availability:** same as TASK-003 through 012 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`SupportResistance.mqh`: SR-zone detection and equal-high/low liquidity
(section 4's exact definition, generalized to N touches), built on
`SwingEngine.mqh`. Full detail in `TASK-013_SUPPORT_RESISTANCE.md`.

## What to check, if/when reviewed

1. **The equal-high/low liquidity definition's fidelity to section 4** —
   confirm `SR_IsEqualHighLiquidityArray`/`...LowArray` (touches
   including the swing itself, `>= 2`) actually matches "two or more
   swing extremes within tolerance of each other," not an off-by-one
   (e.g., should the swing itself count toward the `>= 2`, or should it
   require two *other* swings near it — this implementation chose "itself
   plus at least one other," worth a second opinion on whether that's the
   intended reading).
2. **The highs/lows-only split** — confirm keeping resistance
   (highs-only) and support (lows-only) as separate concepts, rather than
   a combined "any swing extreme" zone concept, matches how the rest of
   the specification (sections 3, 5, 7) actually uses "SR zone."
3. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_SupportResistance.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
4. **Runtime verification:** the array-based core's eight assertions are
   deterministic once confirmed to execute; only the live-symbol wrapper
   test is part of the batched TASK-003 through 013 gap.

## Files in this task

New:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Structure/SupportResistance.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_SupportResistance.mq5`,
`TASK-013_SUPPORT_RESISTANCE.md`, this file. Modified: `TASKS.md`. No
baseline or prior TASK-00N file touched.
