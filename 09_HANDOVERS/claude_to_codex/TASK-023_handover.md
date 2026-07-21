# Claude → Codex handover — TASK-023 (PostExpansionRetestStrategy)

**Note on review availability:** same as TASK-003 through 022 — Codex's
independent-review budget is currently exhausted. Queued. **This is the
highest-priority strategy module to review whenever budget becomes
available** — see below for why.

## What this task is

`PostExpansionRetestStrategy.mqh`: the fifth strategy family, and the
most speculative module in the project — section 3 describes this
family in three sentences with no full formula, unlike every other
strategy which ports or directly formalizes an existing baseline/
reference-material mechanism. Specification written first in
`STRATEGY_SPEC_POST_EXPANSION_RETEST.md`. Full detail in
`TASK-023_POST_EXPANSION_RETEST_STRATEGY.md`.

## What to check, if/when reviewed

1. **This entire strategy's formalization is this task's own invention**,
   not cross-checked against any baseline or reference material (there
   is none for this specific family) — this is the single most
   important thing to independently sanity-check: does "retest the
   swing-structure level that was broken to trigger the expansion, after
   confirming a genuine displacement occurred" match what "Post-
   Expansion Retest" is reasonably meant to be, or is there a different,
   more standard reading this task missed?
2. **The overlap with `SMCStrategy.mqh`'s FVG-return setup** — both fire
   under `VOLATILITY_EXPANSION` regimes; confirm the stated
   distinction (swing-structure level vs. FVG zone) is real and not
   accidentally the same thing in most cases.
3. **The defensive no-chase check's redundancy** — confirm this is
   genuinely intended as a temporary defensive copy, not something that
   should instead live only in this strategy.
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_PostExpansionRetestStrategy.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
5. **Runtime verification:** the positive scenario and four negative
   cases are deterministic once confirmed to execute; only the final
   `CMarketData` wrapper smoke test is part of the batched TASK-003
   through 023 gap.

## Files in this task

New: `STRATEGY_SPEC_POST_EXPANSION_RETEST.md`,
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/PostExpansionRetestStrategy.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_PostExpansionRetestStrategy.mq5`,
`TASK-023_POST_EXPANSION_RETEST_STRATEGY.md`, this file. Modified:
`TASKS.md`. No baseline or prior TASK-00N file touched.
