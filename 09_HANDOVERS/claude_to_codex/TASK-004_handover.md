# Claude → Codex handover — TASK-004 (SymbolProfile + BrokerValidator)

**Note on review availability:** same as TASK-003 — Codex's independent-
review budget is currently exhausted. Queued for whenever it's available.

## What this task is

`SymbolProfile.mqh` (reads and caches a symbol's broker-reported trading
properties) and `BrokerValidator.mqh` (judges those properties against
`TASK-002_PHASE2_SPECIFICATION.md` section 8's mandatory attach-time
validation rule). Full detail in `TASK-004_SYMBOL_PROFILE.md`.

## What to check, if/when reviewed

1. **Read-failure vs. legitimate-zero distinction:** `CSymbolProfile::Load`
   uses the bool-returning reference overloads of `SymbolInfoDouble`/
   `SymbolInfoInteger` specifically so a failed platform read
   (`loaded=false`) is distinguishable from a field that legitimately
   reads as zero (`filling_mode`, `margin_initial`). Confirm this
   distinction is real and not just asserted — i.e., that `SymbolInfoDouble`
   really does return `false` on a genuine failure rather than silently
   writing `0.0` and returning `true`.
2. **Every-failure-reported, not just first:** `BV_ValidateSymbolProfile`
   is written to continue checking after the first failing field (except
   the `loaded == false` case, which is an immediate total failure).
   Confirm the multi-field-corruption test case in
   `Test_SymbolProfile_BrokerValidator.mq5` actually proves this rather
   than accidentally short-circuiting.
3. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_SymbolProfile_BrokerValidator.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
4. **The outstanding gap:** same as TASK-003 — the logic test has not
   been confirmed to actually run and print all-PASS in this session's
   environment. If reviewing, please run it on a real desktop session
   (drag `Test_SymbolProfile_BrokerValidator` onto any chart from the
   Navigator) and report the actual output.

## Files in this task

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/SymbolProfile.mqh`,
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/BrokerValidator.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_SymbolProfile_BrokerValidator.mq5`,
`TASK-004_SYMBOL_PROFILE.md`, this file. Modified: `TASKS.md`. No baseline
or TASK-001/002/003 file touched.
