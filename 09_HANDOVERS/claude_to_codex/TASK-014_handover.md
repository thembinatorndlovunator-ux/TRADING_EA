# Claude → Codex handover — TASK-014 (CandlestickPatternEngine)

**Note on review availability:** same as TASK-003 through 013 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`CandlestickPatternEngine.mqh`: every candlestick pattern predicate from
`TASK-002_PHASE2_SPECIFICATION.md` section 5, translated directly into
code. The largest module in the project so far (18 pattern functions
plus shared measurement primitives). Full detail in
`TASK-014_CANDLESTICK_PATTERN_ENGINE.md`.

## What to check, if/when reviewed

1. **Transcription accuracy against section 5 is the single most
   valuable check for this task** — given the sheer number of formulas
   involved, the realistic failure mode is a mismatch between the
   specification's stated formula/threshold and this code's actual
   implementation, not a logic-design flaw. Every function's header
   comment cites its section-5 source; a systematic pass comparing each
   one directly against the specification text would be the highest-
   value review action here.
2. **Test coverage is intentionally not exhaustive** (one positive case
   per pattern, negative cases only for pin bar and marubozu) — flagged
   explicitly in `TASK-014_CANDLESTICK_PATTERN_ENGINE.md`'s Risks.
   Confirm whether any specific pattern's threshold logic looks
   fragile enough to warrant additional negative/boundary tests before
   this is trusted (tied thresholds, zero-range bars, patterns near the
   edges of their required array length).
3. **The harami detect/confirm split** (`CP_DetectHaramiArray` returning
   an implied-direction enum, `CP_IsHaramiConfirmedArray` checking the
   third bar separately) — confirm this two-step API shape correctly
   matches section 5's own "alert vs. confirmed" framing.
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_CandlestickPatternEngine.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
5. **Runtime verification:** the array-based functions' test cases are
   deterministic once confirmed to execute; only the final `CMarketData`
   wrapper smoke test is part of the batched TASK-003 through 014 gap.

## Files in this task

New:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/CandlestickPatternEngine.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_CandlestickPatternEngine.mq5`,
`TASK-014_CANDLESTICK_PATTERN_ENGINE.md`, this file. Modified:
`TASKS.md`. No baseline or prior TASK-00N file touched.
