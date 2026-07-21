# TASK-033 - Pattern validation completion

## Objective

Complete `pattern_validation.py`'s candlestick coverage (currently 4 of
18 patterns: bullish/bearish pin bar, bullish/bearish engulfing) and add
the chart-pattern side (double top/bottom, head-and-shoulders/inverse)
that TASK-028 never ported, then cross-check every pattern against real
MQL5-exported detector results.

## Reason

TASK-028's own "genuinely NOT done" section and Codex's review (finding
#1) both flag that only 4 of 18 candlestick patterns are ported and no
chart patterns are ported at all, and that no cross-check against a real
MQL5-exported detector-results CSV has ever run (none exists yet).
Codex's review required this be split into its own numbered task rather
than staying an undifferentiated backlog bullet under TASK-028.

## Baseline behaviour

Neither immutable baseline EA exposes a Python-importable pattern
detector; this is new validation tooling, not a baseline-behaviour
change. `01_BASELINE/` must not be modified.

## Evidence

- `TASK-028_PYTHON_STATISTICAL_LAB.md` — the "genuinely NOT done" note
  on 4/18 candlestick coverage and zero chart-pattern coverage.
- `09_HANDOVERS/codex_to_claude/TASK-028_review.md` finding #1.
- `03_SOURCE_CODE/Python/analysis/pattern_validation.py` — the existing
  4-pattern implementation and its `compare_to_mql5_export` merge logic
  (already fixed for outer-merge/duplicate-key coverage per a separate
  Codex finding; reuse that logic for the newly ported patterns).
- `03_SOURCE_CODE/MQL5/.../CandlestickPatternEngine.mqh` — the 18
  candlestick pattern functions.
- `03_SOURCE_CODE/MQL5/.../ChartPatternEngine.mqh` — the chart-pattern
  functions (double top/bottom, head-and-shoulders/inverse).
- `TASK-017_CANDLESTICK_REFERENCE_CROSSCHECK.md` — the reference PDF
  cross-check already done for the candlestick engine; reuse its
  findings (e.g. the pin-bar wick-to-body fix) so the Python ports match
  the corrected MQL5 behavior, not a stale version.

## Specification

1. Port the remaining 14 candlestick pattern functions from
   `CandlestickPatternEngine.mqh` to `pattern_validation.py`, each with
   its own hand-verified synthetic OHLC fixture (matching the reference
   cases from TASK-017 where applicable).
2. Port the chart-pattern functions (double top/bottom,
   head-and-shoulders/inverse) from `ChartPatternEngine.mqh`, including
   the sloped-neckline interpolation TASK-018 hand-verified.
3. Produce a real MQL5-exported detector-results CSV (via a small
   `Test_*.mq5` script or an export hook) for at least one non-trivial
   fixture set, and run `compare_to_mql5_export` against it for real —
   closing the "Real-data run: PENDING" gap this specific area has had
   since TASK-028 part 1.

## Files affected

- `03_SOURCE_CODE/Python/analysis/pattern_validation.py` and its tests.
- `03_SOURCE_CODE/Python/notebooks/09_pattern_detector_validation.ipynb`.
- A new small MQL5 export script/test under the relevant task's test
  directory, if needed to produce the real export.
- `TASKS.md` and this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- Modifying `CandlestickPatternEngine.mqh`/`ChartPatternEngine.mqh`
  themselves — this task validates, it does not change detector logic.
  Any bug found in the MQL5 side is a separate follow-up task.

## Risks

- Python/MQL5 metric-definition drift if a ported pattern's formula is
  transcribed incorrectly — every port needs a hand-traceable fixture,
  not just a visual code read-through.
- The real MQL5 export step depends on being able to actually run
  MetaEditor/MT5 to generate it; if that's unavailable, this task must
  say so explicitly rather than fabricate a CSV.

## Test plan

1. Unit-test each newly ported pattern against hand-verified synthetic
   OHLC fixtures.
2. Run `pytest` and confirm all tests pass.
3. Re-execute `09_pattern_detector_validation.ipynb` from a clean
   kernel.
4. If a real MQL5 export was produced, run `compare_to_mql5_export`
   against it and report the result; otherwise mark that step
   explicitly PENDING, not fabricated.

## Acceptance criteria

- [ ] All 18 candlestick patterns ported and hand-verified.
- [ ] All chart patterns (double top/bottom, head-and-shoulders/inverse)
      ported and hand-verified.
- [ ] `compare_to_mql5_export` run against at least one real MQL5
      export, or the absence of one explicitly stated as PENDING.
- [ ] Independent review completed and findings resolved.

## Rejection criteria

Reject if a pattern port has no hand-traceable fixture, if a "real
MQL5 export" comparison is actually run against synthetic data
presented as real, or if MQL5 detector logic is modified under cover of
this validation task.

## Status

Not started. Registered as a formal follow-up per Codex's TASK-028
review finding #1.
