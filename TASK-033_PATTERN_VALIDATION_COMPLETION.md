# TASK-033 - Pattern validation completion

## Objective

Complete `pattern_validation.py`'s candlestick coverage and add the
chart-pattern side (double top/bottom, head-and-shoulders/inverse) that
TASK-028 never ported.

**Exact counting convention (corrected, Codex review finding #2,
2026-07-22 -- the original "14 of 18" claim was source-factually
wrong):** `CandlestickPatternEngine.mqh` has **19** `CP_Is*Array` boolean
pattern predicates PLUS one non-boolean helper, `CP_DetectHaramiArray`
(returns `ENUM_HARAMI_DIRECTION`, used internally by
`CP_IsHaramiConfirmedArray`) -- **20 detector/predicate functions total**.
Four are currently ported: `CP_IsBullishPinBarArray`,
`CP_IsBearishPinBarArray`, `CP_IsBullishEngulfingArray`,
`CP_IsBearishEngulfingArray`. **Remaining: the other 15 `CP_Is*Array`
predicates** (`CP_IsDragonflyRejectionArray`, `CP_IsGravestoneRejectionArray`,
`CP_IsMarubozuArray`, `CP_IsDojiArray`, `CP_IsSpinningTopArray`,
`CP_IsInsideBarArray`, `CP_IsOutsideBarArray`, `CP_IsTweezerTopArray`,
`CP_IsTweezerBottomArray`, `CP_IsHaramiConfirmedArray`,
`CP_IsMorningStarArray`, `CP_IsEveningStarArray`,
`CP_IsThreeWhiteSoldiersArray`, `CP_IsThreeBlackCrowsArray`,
`CP_IsThreeBarReversalArray`) **plus the `CP_DetectHaramiArray` helper
`CP_IsHaramiConfirmedArray` depends on -- 16 functions in total** need
porting to close this task's candlestick side.

**This task's scope explicitly EXCLUDES the real-evidence MQL5-export
cross-check** (Codex review finding #2: TASK-033's first draft let its
own acceptance criteria pass with that step still PENDING, while its
Objective simultaneously promised it -- the same closure loophole found
in TASK-031). Producing a real MQL5-exported detector-results CSV is
`TASK-037_MT5_EXPORT_BRIDGE.md`'s deliverable; running
`compare_to_mql5_export` against it is tracked there.

## Reason

TASK-028's own "genuinely NOT done" section and Codex's review (finding
#1) both flag that candlestick coverage is incomplete and no chart
patterns are ported at all, and that no cross-check against a real
MQL5-exported detector-results CSV has ever run (none exists yet).
Codex's review required this be split into its own numbered task rather
than staying an undifferentiated backlog bullet under TASK-028. A second
review pass (finding #2, 2026-07-22) further found this task's own first
draft had the wrong pattern count and the same PENDING-closure loophole
as TASK-031 -- both fixed above.

## Baseline behaviour

Neither immutable baseline EA exposes a Python-importable pattern
detector; this is new validation tooling, not a baseline-behaviour
change. `01_BASELINE/` must not be modified.

## Evidence

- `TASK-028_PYTHON_STATISTICAL_LAB.md` — the "genuinely NOT done" note
  on 4/20 candlestick coverage (corrected, 2026-07-22 Codex review
  finding, fourth round -- this Evidence section still said "4/18" and
  "18" functions despite this task's own Objective already using the
  corrected count) and zero chart-pattern coverage.
- `09_HANDOVERS/codex_to_claude/TASK-028_review.md` finding #1.
- `03_SOURCE_CODE/Python/analysis/pattern_validation.py` — the existing
  4-pattern implementation and its `compare_to_mql5_export` merge logic
  (already fixed for outer-merge/duplicate-key coverage per a separate
  Codex finding; reuse that logic for the newly ported patterns).
- `03_SOURCE_CODE/MQL5/.../CandlestickPatternEngine.mqh` — 19
  `CP_Is*Array` boolean pattern predicates plus the non-boolean
  `CP_DetectHaramiArray` helper, 20 detector/predicate functions total
  (corrected count, 2026-07-22 Codex review finding, fourth round --
  this line previously said "the 18 candlestick pattern functions").
- `03_SOURCE_CODE/MQL5/.../ChartPatternEngine.mqh` — the chart-pattern
  functions (double top/bottom, head-and-shoulders/inverse).
- `TASK-017_CANDLESTICK_REFERENCE_CROSSCHECK.md` — the reference PDF
  cross-check already done for the candlestick engine; reuse its
  findings (e.g. the pin-bar wick-to-body fix) so the Python ports match
  the corrected MQL5 behavior, not a stale version.

## Specification

1. Port the remaining 15 `CP_Is*Array` candlestick predicates plus the
   `CP_DetectHaramiArray` helper (16 functions total -- see Objective's
   exact counting convention) from `CandlestickPatternEngine.mqh` to
   `pattern_validation.py`, each with its own hand-verified synthetic
   OHLC fixture (matching the reference cases from TASK-017 where
   applicable).
2. Port the chart-pattern functions (double top/bottom,
   head-and-shoulders/inverse) from `ChartPatternEngine.mqh`, including
   the sloped-neckline interpolation TASK-018 hand-verified.

   **Scope boundary, stated explicitly (Codex review finding, 2026-07-22,
   fifth round -- previously this task's "all chart patterns" language
   silently implied full coverage): this task's chart-pattern scope is
   double top/bottom and head-and-shoulders/inverse ONLY, matching
   `ChartPatternEngine.mqh`'s own current implementation.**

   **Corrected, 2026-07-22 Codex review finding (sixth round): the
   fifth-round note above named only triple top/bottom as the unowned
   gap -- `00_MASTER_PROMPT_FOR_CLAUDE.md` section 10 actually requires
   17 chart-pattern families, of which `ChartPatternEngine.mqh`
   implements 4; the other 13 (triple top/bottom AND 11 further families
   -- triangles, rectangle, flags, pennant, wedges, parallel channel,
   cup-and-handle) remained unowned by any numbered task, understating
   the real gap by more than a factor of 10.** `TASK-039_CHART_PATTERN_COMPLETION.md`
   now registers building all 13 in `ChartPatternEngine.mqh` and
   validating them here-adjacent in `pattern_validation.py`. This task's
   completion does not close that gap, and must not be described as
   covering "all chart patterns."**
3. Do NOT attempt the real MQL5-export cross-check here -- that is
   `TASK-037`'s deliverable once a real export exists. Keep the existing
   "Real-data run: PENDING" convention in whatever this task produces.

## Files affected

- `03_SOURCE_CODE/Python/analysis/pattern_validation.py` and its tests.
- `03_SOURCE_CODE/Python/notebooks/09_pattern_detector_validation.ipynb`.
- `TASKS.md` and this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- Modifying `CandlestickPatternEngine.mqh`/`ChartPatternEngine.mqh`
  themselves — this task validates, it does not change detector logic.
  Any bug found in the MQL5 side is a separate follow-up task.
- The real MQL5-export cross-check itself -- owned by `TASK-037`, not a
  deliverable of this task (see Objective).

## Risks

- Python/MQL5 metric-definition drift if a ported pattern's formula is
  transcribed incorrectly — every port needs a hand-traceable fixture,
  not just a visual code read-through.
- Miscounting the pattern surface again -- re-verify against the actual
  `CandlestickPatternEngine.mqh` source at implementation time rather
  than trusting this document's count if the source has since changed.

## Test plan

1. Unit-test each newly ported pattern against hand-verified synthetic
   OHLC fixtures.
2. Run `pytest` and confirm all tests pass.
3. Re-execute `09_pattern_detector_validation.ipynb` from a clean
   kernel.

## Acceptance criteria

- [x] All 16 remaining candlestick detector/predicate functions (15
      `CP_Is*Array` predicates + `CP_DetectHaramiArray`) ported and
      hand-verified: dragonfly/gravestone rejection, marubozu, doji,
      spinning top, inside/outside bar, tweezer top/bottom, harami-detect
      + harami-confirmed, morning/evening star, three white soldiers/
      three black crows, three-bar reversal (the last needing a minimal,
      explicitly-scoped port of `SwingEngine.mqh`'s own confirmed-pivot
      predicate). `detect_all_patterns()`'s DEFAULT output stays
      unchanged (still 4 columns) so `Export_PatternDetectorResults.mq5`
      (TASK-037) stays comparable; the new patterns are always computed
      when calling the individual functions directly, and added to
      `detect_all_patterns()`'s output as new always-present columns
      (dragonfly/gravestone/doji/spinning-top/inside-outside/harami/
      morning-evening-star/three-soldiers-crows) plus two OPT-IN groups
      gated on new optional `atr_values`/`swing_depth` parameters
      (marubozu/tweezer top/bottom, three-bar-reversal) that do not
      disturb a caller who omits them.
- [x] Double top/bottom and head-and-shoulders/inverse (this task's
      actual chart-pattern scope, NOT "all chart patterns" -- the other
      13 master-required families, including triple top/bottom, are
      owned by `TASK-039_CHART_PATTERN_COMPLETION.md`, see Specification
      item 2) ported and hand-verified, including the sloped-neckline
      `linear_interpolate` and the shared `check_retest` predicate.
- [x] No claim of a real MQL5-export cross-check is made here -- that
      remains explicitly owned by TASK-037. (Extending
      `Export_PatternDetectorResults.mq5` to cover these newly-ported
      patterns, and building an equivalent chart-pattern export, remain
      open follow-ups under TASK-037, not claimed here.)
- [ ] Independent review completed and findings resolved — deferred to
      this project's single, consolidated, end-of-sprint Codex review.

## Rejection criteria

Reject if a pattern port has no hand-traceable fixture, if the pattern
count is misstated again without re-verifying against the actual source,
or if MQL5 detector logic is modified under cover of this validation
task.

## Status

Done — all 16 remaining candlestick predicates + the harami-detect
helper, plus double top/bottom and head-and-shoulders/inverse chart
patterns (incl. the sloped-neckline interpolation and shared retest
predicate), ported to `pattern_validation.py` with hand-verified
fixtures. 67 tests in `test_pattern_validation.py` (up from 29), all
passing; ruff/ruff format/mypy clean; full 652-test suite passes with no
regressions. No real MQL5-export cross-check claimed — that stays
TASK-037's, with extending the existing 4-pattern export to cover this
task's new patterns noted as an open follow-up.
