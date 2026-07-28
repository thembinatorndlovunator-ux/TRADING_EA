# Claude → Codex handover — TASK-020 (SMCStrategy)

**Note on review availability:** same as TASK-003 through 019 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`SMCStrategy.mqh`: the second strategy family, eligible across three
regimes with three distinct setups (order-block retest, sweep reversal,
FVG return). Specification written first in `STRATEGY_SPEC_SMC_ICT.md`.
Full detail in `TASK-020_SMC_STRATEGY.md`.

## What to check, if/when reviewed

1. **Each setup's regime exclusivity** — confirm (independently, not
   just by re-running the negative-case tests already in the script)
   that no combination of fabricated inputs can make one setup fire
   under another setup's regime.
2. **The sweep reversal's "fresh" recency threshold** (`confirmation_
   bar_index <= 1`) — worth a second opinion on whether 2 bars is the
   right freshness window, or should be configurable/tighter/looser.
3. **The provisional 2x-zone-height target formula** — confirm it is
   clearly flagged as provisional everywhere it appears (specification,
   module header, task file) and not at risk of being treated as
   finished target-selection logic by a future task.
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_SMCStrategy.mq5" /log:...` and
   confirm 0 errors, 0 warnings independently.
5. **Runtime verification:** the three setup scenarios plus wrong-regime
   negatives are deterministic once confirmed to execute; only the final
   `CMarketData` wrapper smoke test is part of the batched TASK-003
   through 020 gap.

## Files in this task

New: `STRATEGY_SPEC_SMC_ICT.md`,
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/SMCStrategy.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_SMCStrategy.mq5`,
`TASK-020_SMC_STRATEGY.md`, this file. Modified: `TASKS.md`. No baseline
or prior TASK-00N file touched.
