# Claude → Codex handover — TASK-024 (StrategyRouter / SignalScorer / ConflictResolver)

**Note on review availability:** same as TASK-003 through 023 — Codex's
independent-review budget is currently exhausted. Queued. **This task is
a strong candidate to prioritize whenever budget returns** — it's the
final decision point every trade in the eventual system passes through.

## What this task is

`SignalScorer.mqh`, `StrategyRouter.mqh`, `ConflictResolver.mqh`: the
unified candidate shape, the eligibility/scoring layer, and the final
cross-direction tie-break, respectively — begins Phase 6 and is the
first task where every detection engine and every strategy module
compiles together as one unit. Full detail in
`TASK-024_STRATEGY_ROUTER.md`.

## What to check, if/when reviewed

1. **The eligibility matrix (`SR_GetEligibilityMultiplier`) is the
   single most important thing to verify cell-by-cell** against section
   3's actual routing-table text — this task traced each cell to a
   specific quoted sentence in inline comments; confirm those citations
   are accurate, not just plausible-sounding.
2. **The `StrategyRouter`/`ConflictResolver` responsibility split** —
   confirm by inspection that `StrategyRouter` genuinely never compares
   across directions and `ConflictResolver` genuinely never recomputes
   eligibility or score, matching section 3's explicit separation
   (which round-3 review found conflated in an earlier draft).
3. **The base score's honest two-of-five-component scope** — confirm
   the deferral of location/pattern-quality and sample-gated historical
   performance is clearly flagged, not silently approximated by the
   two-component version.
4. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_StrategyRouter.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently — this is the largest
   compilation unit in the project (all five strategies, every
   detection engine), so it's also the best single stress-test of
   whether prior modules' interfaces actually compose cleanly.
5. **Every test in this task is a pure logic test** (no live-symbol
   dependency at this layer) — there is no separate runtime-verification
   gap for this specific task the way every strategy/detection module
   has had; the hand-verified tests are the whole story here.

## Files in this task

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Routing/SignalScorer.mqh`,
`StrategyRouter.mqh`, `ConflictResolver.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_StrategyRouter.mq5`,
`TASK-024_STRATEGY_ROUTER.md`, this file. Modified: `TASKS.md`. No
baseline or prior TASK-00N file touched.
