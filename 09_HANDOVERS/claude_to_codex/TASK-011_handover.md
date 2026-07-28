# Claude → Codex handover — TASK-011 (SwingEngine)

**Note on review availability:** same as TASK-003 through 010 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`SwingEngine.mqh`: the canonical confirmed swing-pivot predicate, defined
once and reused everywhere. This is Phase 4's first module. Full detail
in `TASK-011_SWING_ENGINE.md`.

## What to check, if/when reviewed

1. **The window-sizing arithmetic in the nearest-swing finders** — worth
   a careful independent trace of `SE_FindNearestConfirmedSwingHighArray`/
   `...LowArray`'s bound check (`last_k + depth >= ArraySize(...)`) and
   the wrapper's window computation
   (`start + max_lookback - 1 + depth + 1`), specifically for off-by-one
   errors at the edges of a requested range — flagged in
   `TASK-011_SWING_ENGINE.md`'s Risks as the one thing most worth a
   second pair of eyes.
2. **Strict-inequality enforcement** — confirm every comparison really is
   `>=`/`<=` (rejecting a tie), not `>`/`<`, matching the specification's
   "strictly exceeds every neighbor" requirement, in both the array core
   and (by inspection, since it delegates) the wrapper.
3. **The array-based core vs. `CMarketData`-wrapper split** — confirm no
   pivot logic is duplicated between them (the wrapper should only ever
   read data and delegate, never re-implement any part of the
   comparison).
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_SwingEngine.mq5" /log:...` and
   confirm 0 errors, 0 warnings independently.
5. **Runtime verification:** the array-based core's tests (1–6) are
   deterministic and hand-verifiable once confirmed to actually execute —
   this is a stronger position than most prior tasks. Only the
   `CMarketData` wrapper smoke test (test 7) is part of the batched
   TASK-003 through 011 runtime-verification gap.

## Files in this task

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Structure/SwingEngine.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_SwingEngine.mq5`,
`TASK-011_SWING_ENGINE.md`, this file. Modified: `TASKS.md`. No baseline
or prior TASK-00N file touched.
