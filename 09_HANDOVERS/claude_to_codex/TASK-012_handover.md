# Claude → Codex handover — TASK-012 (MarketStructure)

**Note on review availability:** same as TASK-003 through 011 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`MarketStructure.mqh`: BOS/CHoCH break-event detection, structural bias,
range boundaries, and equilibrium — one function's output, built on
`SwingEngine.mqh`'s pivot predicate. Full detail in
`TASK-012_MARKET_STRUCTURE.md`.

## What to check, if/when reviewed

1. **The bias/break-event definitions themselves are this task's own
   formalization of standard SMC/ICT usage**, explicitly not yet
   cross-checked against the deeper reference material in `EA
   Files/SMC/` (kept local-only per copyright rules). This is the single
   most valuable thing an independent reviewer with access to that
   material — or general SMC/ICT domain knowledge — could check: does
   "higher-high AND higher-low → bullish bias" and "earliest-in-time
   close beyond the last swing → the break event" match conventional
   usage, or is there a nuance (e.g., internal vs. external structure,
   minor vs. major swing distinction) this first pass is missing?
2. **The "earliest-in-time break" scan direction** — confirm
   `MS_FindBreakIndexArray`'s loop (scanning from `reference_index - 1`
   down to `0`, returning the first match) actually returns the earliest
   qualifying bar in real chronological order, not the most recent one —
   this is the one piece of index-direction logic most worth an
   independent trace, similar to TASK-011's nearest-finder concern.
3. **The simultaneous-dual-break tie-break** (more recent wins) — confirm
   this is a reasonable choice for the rare case it's meant to handle.
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_MarketStructure.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
5. **Runtime verification:** the array-based core's five scenarios (full
   bias × break-direction matrix) are deterministic and hand-verifiable
   once confirmed to execute — only the live-symbol wrapper test is part
   of the batched TASK-003 through 012 gap.

## Files in this task

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Structure/MarketStructure.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_MarketStructure.mq5`,
`TASK-012_MARKET_STRUCTURE.md`, this file. Modified: `TASKS.md`. No
baseline or prior TASK-00N file touched.
