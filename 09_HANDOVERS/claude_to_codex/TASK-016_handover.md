# Claude → Codex handover — TASK-016 (MarketRegimeEngine)

**Note on review availability:** same as TASK-003 through 015 — Codex's
independent-review budget is currently exhausted. Queued. **This is the
single highest-priority task to review whenever budget becomes
available** — it implements the exact formula round-2 review found
mathematically broken (the regime-confidence defect that was the most
serious finding across all of TASK-002's review rounds), and every
downstream strategy-routing decision in the eventual system depends on
this module's output.

## What this task is

`MarketRegimeEngine.mqh`: the nine-state regime classifier, including
the corrected classification-margin confidence formula. Full detail in
`TASK-016_MARKET_REGIME_ENGINE.md`.

## What to check, if/when reviewed

1. **Re-derive the two extreme-confidence test cases independently** —
   scenario 2 (`COMPRESSION` at `E=0`) and scenario 4
   (`VOLATILITY_EXPANSION_UP` at `E=1`) both claim `confidence=1.0`,
   reproducing `TASK-002_PHASE2_SPECIFICATION.md`'s own hand-derived
   values. This is the single most important thing to confirm
   independently, given what was previously broken here.
2. **The `CopyBuffer` array-ordering handling** in `MRE_ClassifyLive` —
   flagged explicitly in `TASK-016_MARKET_REGIME_ENGINE.md`'s Risks as
   the first place in this project a non-`AS_SERIES` destination array's
   default oldest-to-newest fill order actually matters (every prior
   module's `CopyBuffer`/`CopyClose`-family calls only ever copied one
   element at a time, sidestepping the issue). Worth an independent trace
   of `ema_now = ema_buf[ArraySize(ema_buf)-1]` / `ema_prior =
   ema_buf[0]` against MQL5's actual documented behavior.
3. **`swing_agreement`'s reuse of `MarketStructure`'s bias** — a stated
   interpretation choice (see Risks); worth a second opinion on whether
   section 2's own separate "last N confirmed swings agree" description
   was meant to be more general than `MarketStructure`'s fixed
   two-swing-pair comparison.
4. **The strict-priority state-selection order** — trace all six
   branches (gating/failure handled by the wrapper and caller
   respectively; low-efficiency-RANGING; expansion-with-agreement;
   trend-with-agreement; compression; fallback-RANGING) against section
   2's exact ordering to confirm no branch can be reached out of order.
5. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_MarketRegimeEngine.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
6. **Runtime verification:** all six classification scenarios plus
   hysteresis/gating/clamper tests are deterministic once confirmed to
   execute; only the final `CMarketData` wrapper smoke test is part of
   the batched TASK-003 through 016 gap.

## Files in this task

New:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/MarketRegimeEngine.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_MarketRegimeEngine.mq5`,
`TASK-016_MARKET_REGIME_ENGINE.md`, this file. Modified: `TASKS.md`. No
baseline or prior TASK-00N file touched.
