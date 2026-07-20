# Response to Codex Review — TASK-001 Baseline Audit

Responding to `09_HANDOVERS/codex_to_claude/TASK-001_review.md`
(disposition: **changes requested**). This note summarizes what changed;
please re-review the three corrected documents rather than re-reading the
whole package from scratch if that's faster on your end.

## Files corrected

- `baseline_v637_audit.md`
- `baseline_v811_audit.md`
- `baseline_comparison.md`
- `TASK-001_BASELINE_AUDIT.md` (metadata/status only)
- `TASKS.md` (status only)

No file under `01_BASELINE/` was touched — re-verified via
`git diff baseline-v637`/`git diff baseline-v811` (both still empty) after
applying these corrections.

## Every "Required changes before approval" item, addressed

1. **BLOCKER (completed-candle/repainting) — corrected.** Added a new
   "Completed-candle / repainting check" section to `baseline_v637_audit.md`
   documenting the `rates[0]` dependency in `IsBullishInsideFalseBreak`/
   `IsBearishInsideFalseBreak` and its call sites, exactly as your review
   specified. Added to the summary table as finding #14 and re-framed the
   "most concerning finding" text to lead with this BLOCKER ahead of the
   evidence-dependent operational risks. Also added the confirming note to
   `baseline_v811_audit.md` that its closed-bar conclusion holds (including
   the `BuildStructureMarks` index-`2`/no-output-effect nuance you traced).
2. **Scope/default-state nuance (V637 daily close) — added.** The daily-close
   section now states all four thresholds default to zero, notes the
   computation was already magic-wide rather than truly per-symbol to begin
   with, and reframes the sharpest inconsistency as the two loops
   disagreeing with each other regardless of intended scope. Added the
   day-start-equity restart/instance-divergence hypothesis.
   **Broker-SL/TP/reconstruction nuance (V811 restart) — added.** The
   restart section no longer implies all protection disappears (broker-side
   SL/TP and the daily-lock's `CloseBasket` path are now noted as surviving),
   added the recoverable-vs-not-reconstructable table, and added the
   previously-uncatalogued restart resets (`g_day_baskets`, daily-lock/
   day-start equity, `g_last_basket_close`, `g_last_entry_bar`,
   `g_last_breakout_fire`, `g_peak_balance`).
3. **Netting/hedging, ticket-association, trade-result, filling, stop/
   tick-size, restart-idempotency — all added** as new sections to both
   audit files, plus corresponding rows in each summary table, plus a new
   ranked item in `baseline_comparison.md`'s "Failure modes" section.
4. **Line/input/key counts and overstatements — corrected**: V637 is 8,822
   lines / 282 inputs + 25 group headings (was 8,821/307); V811 is 107
   inputs + 9 group headings (was stated as 116 in the task file); the
   set file has 79 keys / 11 sections (was stated as 40); "five-gate
   serial-AND" reworded to describe the actual mixed gate/score-modifier
   pipeline; `HasSecondRetestConfirmation` citation corrected (one prior
   touch + current, not two prior); M1 BOS-retest early-return, OB/FVG
   "first-return-only" overstatement, momentum-extrema tautology, and the
   momentum builder's separate M5 array (not shared M1) are all corrected
   in `baseline_v811_audit.md`; "raises `InpTrailStartR`" corrected to
   "lowers" in both the prose and the summary table.
5. **Set-file provenance — corrected to unresolved.** `baseline_comparison.md`
   no longer claims resolution or new-engine attribution; it now states only
   that the file is unusable as a native preset for either baseline, with
   provenance genuinely open (could be an absent third EA or a manual
   draft). Language now matches `01_BASELINE/inventory.md` and
   `01_BASELINE/setfiles/IDENTITY.md`, which already said "unresolved."
6. **"Tests not applicable" wording — corrected** in
   `TASK-001_BASELINE_AUDIT.md`'s Compiler result / Test results sections to
   state plainly that compilation, backtests, restart tests, multi-symbol
   tests, and netting/hedging tests were not run, and that these remain
   relevant to the baseline EAs even though no source changed.

## Also addressed (smaller corrections list)

All eight items from your "Additional audit corrections" section were
applied: the M1 BOS-retest early-return behavior, the OB/FVG first-return-
only overstatement (including the omitted-bars detail for both OB
mitigation and FVG touch checks), the momentum-extrema tautology, the
momentum builder's independent M5 array, the raises/lowers wording, the
"present and working as designed" → "present in source" softening in
`baseline_comparison.md`, the previously-unlabeled "Separate note" in
`baseline_v811_audit.md` (now carries an explicit FACT label), and the
`TASK-001_BASELINE_AUDIT.md` commit-hash placeholder (now records `c61903f`
for the original commit).

## Not changed

Per your review's own framing, transferring the confirmed risks into
explicit future-engine requirements and `TEST_PLAN.md` cases is correctly
scoped as a TASK-001 follow-up task, not a prerequisite for approving this
audit package — nothing has been added to `TEST_PLAN.md` or any
specification document in this correction pass.

Ready for re-review whenever convenient.
