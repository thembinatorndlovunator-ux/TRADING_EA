# Claude → Codex handover — TASK-019 (SRBounceStrategy)

**Note on review availability:** same as TASK-003 through 018 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`SRBounceStrategy.mqh`: the first of six strategy families, and the
first module composing the full Phase 4 detection stack end-to-end.
Specification written first in `STRATEGY_SPEC_SR_BOUNCE.md`. Full detail
in `TASK-019_SR_BOUNCE_STRATEGY.md`.

## What to check, if/when reviewed

1. **The three-bar-reversal exclusion is the single most important
   design decision to double-check** — confirm `CP_IsThreeBarReversalArray`
   genuinely does return an ambiguous (direction-unspecified) result the
   way this task's specification claims, and that excluding it (rather
   than resolving the ambiguity and using it) was the right call versus
   the alternative of exposing the swing type from that function.
2. **Whether any of the three confirmation patterns actually used
   (pin bar, engulfing, tweezer) has a similar hidden ambiguity** — this
   task caught one such issue by inspection; worth a systematic check
   that the other three don't have an analogous problem.
3. **The composition boundary** — confirm `SRB_EvaluateArray` truly
   performs no regime/structure computation of its own (only consumes
   caller-supplied `regime`/`structure`), matching the stated
   architecture discipline.
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_SRBounceStrategy.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
5. **Runtime verification — this task's live wrapper smoke test is the
   single highest-value item in the entire batched TASK-003 through 019
   runtime-verification backlog**, since it's the first genuine
   end-to-end composition (live regime → live structure → live SR-zone/
   candlestick checks) in the project. If only one thing gets manually
   run from the whole backlog, this is the one worth prioritizing.

## Files in this task

New: `STRATEGY_SPEC_SR_BOUNCE.md`,
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/SRBounceStrategy.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_SRBounceStrategy.mq5`,
`TASK-019_SR_BOUNCE_STRATEGY.md`, this file. Modified: `TASKS.md`. No
baseline or prior TASK-00N file touched.
