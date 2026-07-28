# Claude → Codex handover — TASK-007 (RiskManager core risk math)

**Note on review availability:** same as TASK-003 through 006 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`RiskManager.mqh`'s core, stateless risk-math functions — the formula
round-3 review found dimensionally wrong (missing division by tick size)
and sign-wrong (unsigned distance instead of a profit-side-stop-is-zero
rule) in the specification itself. This task makes the corrected version
executable and verified against the specification's own worked example.
Full detail in `TASK-007_RISK_MANAGER.md`.

## What to check, if/when reviewed

1. **The worked-example match is the single most important check:**
   `TASK-002_PHASE2_SPECIFICATION.md` section 8's Test plan item 5 states
   `risk_cash = 100` for a `1.00` price move, `0.01` tick size, `1` tick
   value, one lot. `Test_RiskManager.mq5` test 1 reproduces this exactly.
   Confirm by hand that `RM_ComputeRiskCash`'s formula
   (`loss_distance * volume * tick_value_loss / tick_size`) actually
   produces `100` for those inputs (it does: `1.00 * 1.0 * 1.0 / 0.01 =
   100`), and that this matches the specification's own derivation, not
   just this implementation's internal consistency.
2. **`RM_ValidateStopDistance`'s reject-not-clamp behavior:** confirm the
   cap branch genuinely returns `false` and leaves `adjusted_stop_distance`
   unusable (rather than a caller accidentally reading a stale/default
   value and trading anyway) — this is the fix for a specification defect
   round 2/3 both flagged (a "hard cap becomes soft" inconsistency).
3. **`RM_CrossCheckRiskCash`'s sign convention:** `OrderCalcProfit` for a
   losing close reports a negative profit; the function negates it to a
   positive `risk_cash` magnitude. Confirm this sign handling is correct
   for both `ORDER_TYPE_BUY` and `ORDER_TYPE_SELL` cases.
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_RiskManager.mq5" /log:...` and
   confirm 0 errors, 0 warnings independently.
5. **Runtime verification is a known, batched item** across TASK-003
   through 007.

## Files in this task

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/RiskManager.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_RiskManager.mq5`,
`TASK-007_RISK_MANAGER.md`, this file. Modified: `TASKS.md`. No baseline
or prior TASK-00N file touched.
