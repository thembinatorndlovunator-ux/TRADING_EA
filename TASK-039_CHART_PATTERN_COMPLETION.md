# TASK-039 - Remaining chart-pattern detectors (build + validate)

## Objective

Build the 13 master-required chart-pattern families
`ChartPatternEngine.mqh` does not yet implement, and validate every one
of them in `pattern_validation.py` -- closing the gap Codex's sixth
review (finding 14, 2026-07-22) found: `00_MASTER_PROMPT_FOR_CLAUDE.md`
section 10 requires 17 chart-pattern families; `ChartPatternEngine.mqh`
currently implements only 4 (double top, double bottom, head-and-
shoulders, inverse head-and-shoulders); `TASK-033_PATTERN_VALIDATION_COMPLETION.md`
owns Python-side validation for those same 4 and explicitly excludes
triple top/bottom; nothing owns the other 11. **13 of 17 required
pattern families remain outside any numbered task's executable
ownership** until this task exists.

## Reason

`TASKS.md`'s TASK-033 row previously said its scope was "remaining 16
candlestick detector/predicate functions... + all chart patterns" --
false: TASK-033's own body already correctly scoped itself to the 4
implemented chart patterns and explicitly flagged triple top/bottom as
unowned, but neither `TASKS.md` nor TASK-033's own disclosure named the
other 11 unowned families (triangles, rectangle/consolidation box,
flags, pennant, wedges, parallel channel, cup-and-handle) at all --
understating the real gap by a factor of more than 10. Codex's sixth
review required this be split into its own numbered task, matching the
established pattern (TASK-031/032/033/034/035/036/037/038) rather than
staying an under-counted disclosure inside TASK-033/TASK-018.

## Baseline behaviour

Neither immutable baseline EA (V6.37/V8.11) has a chart-pattern engine
at all; this is new detection logic for the Themba Adaptive Intraday
Engine only. `01_BASELINE/` must not be modified.

## Evidence

- `00_MASTER_PROMPT_FOR_CLAUDE.md` section 10 -- the full 17-pattern
  list (items 1-17; item 17, cup-and-handle, is explicitly "a later
  research module, disabled by default").
- `03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/ChartPatternEngine.mqh`
  -- implements only patterns 1/2/5/6 (double top, double bottom, head-
  and-shoulders, inverse head-and-shoulders).
- `TASK-018_CHART_PATTERN_ENGINE.md`'s own "Out of scope" section --
  already correctly names all 13 remaining patterns (triple top/bottom
  plus "the remaining 11 chart patterns: triangles, rectangle, flags,
  pennants, wedges, channels, cup-and-handle") as Phase 5, deferred --
  but "a fast-follow task" was prose, not executable ownership, which is
  exactly what this task registers.
- `TASK-033_PATTERN_VALIDATION_COMPLETION.md`'s own scope-boundary note
  -- already correctly excludes triple top/bottom from its validation
  scope, but (until this task's own registration) named only that one
  pair, not the full 13-pattern gap.
- `09_HANDOVERS/codex_to_claude/TASK-028_review.md` finding 14 (sixth
  round).

## Specification

1. Implement the remaining 13 chart-pattern families in
   `ChartPatternEngine.mqh`, matching the array-based, no-subjective-
   drawing convention `CP_IsDoubleTopArray`/`CP_IsHeadAndShouldersArray`
   (etc.) already establish, including sloped-neckline/trendline
   interpolation where the pattern geometry requires it (as TASK-018
   already did for head-and-shoulders):
   - Triple top, triple bottom.
   - Ascending triangle, descending triangle, symmetrical triangle.
   - Rectangle / consolidation box.
   - Bull flag, bear flag, pennant.
   - Rising wedge, falling wedge.
   - Parallel ascending/descending channel.
   - Cup and handle (master prompt item 17 requires this be a separate,
     later research module, DISABLED BY DEFAULT -- implement behind its
     own explicit flag, never enabled unconditionally alongside the
     other 12).
2. Port every one of those 13 detectors into `pattern_validation.py`,
   each with its own hand-verified synthetic OHLC fixture (matching this
   project's existing `CP_IsDoubleTopArray`/etc. port style already in
   that module) -- extending, not duplicating, TASK-033's existing
   chart-pattern validation surface.
3. Do NOT attempt the real MQL5-export cross-check here -- that remains
   `TASK-037`'s deliverable once a real export exists, same scope
   boundary TASK-033 already established for its own 4 patterns.
4. Update `TASKS.md`'s TASK-033 row and `TASK-033_PATTERN_VALIDATION_COMPLETION.md`
   to reference this task as the owner of the remaining 13 families,
   removing any remaining "all chart patterns" ambiguity.

## Files affected

- `03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/ChartPatternEngine.mqh`.
- `03_SOURCE_CODE/Python/analysis/pattern_validation.py` and its tests.
- `03_SOURCE_CODE/Python/notebooks/09_pattern_detector_validation.ipynb`.
- `TASKS.md`, `TASK-033_PATTERN_VALIDATION_COMPLETION.md`, this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- The real MQL5-export cross-check itself -- owned by `TASK-037`.
- Any required visual outputs (boundary lines, breakout/retest markers)
  -- a later `PatternVisuals`/`StructureVisuals` consumer, matching
  TASK-018's own existing scope boundary for its 4 patterns.
- Wiring any of these 13 patterns into `StrategyRouter`/`SignalScorer`
  or any live trading decision -- detection and validation only.

## Risks

- Pattern geometry for triangles/wedges/channels/flags/pennants
  typically needs a trendline-slope-fitting helper (not just fixed
  horizontal levels like double top/bottom) -- reuse
  `ChartPatternEngine.mqh`'s existing sloped-neckline interpolation
  approach rather than inventing a second, inconsistent slope-fitting
  method.
- Cup-and-handle is explicitly the least well-defined pattern in the
  master prompt's own list ("disabled by default... later research
  module") -- do not let ambiguity in its definition block the other 12,
  genuinely-specified patterns from shipping.
- Miscounting the pattern surface again -- re-verify against
  `00_MASTER_PROMPT_FOR_CLAUDE.md` section 10's own numbered list at
  implementation time rather than trusting this document's count if the
  master prompt has since changed.

## Test plan

1. Compile clean in MetaEditor, 0 errors/0 warnings, real log evidence.
2. Unit-test each of the 12 non-cup-and-handle detectors against hand-
   verified synthetic OHLC fixtures on both the MQL5 and Python sides.
3. Confirm cup-and-handle is behind its own explicit disabled-by-default
   flag and does not fire when that flag is off.
4. Run `pytest` and confirm all `pattern_validation.py` tests pass.
5. Re-execute `09_pattern_detector_validation.ipynb` from a clean
   kernel.

## Acceptance criteria

- [ ] All 12 non-cup-and-handle chart patterns implemented in
      `ChartPatternEngine.mqh` and ported to `pattern_validation.py`
      with hand-verified fixtures.
- [ ] Cup-and-handle implemented behind an explicit disabled-by-default
      flag, or explicitly deferred again with a NEW numbered follow-up
      naming it (never silently dropped).
- [ ] No claim of a real MQL5-export cross-check is made here -- that
      remains explicitly owned by `TASK-037`.
- [ ] `TASKS.md`/`TASK-033_PATTERN_VALIDATION_COMPLETION.md` updated to
      remove any remaining "all chart patterns" ambiguity.
- [ ] Independent review completed and findings resolved.

## Rejection criteria

- Any claim that "all chart patterns" are covered without every one of
  the 17 master-prompt-listed families being genuinely implemented (or,
  for cup-and-handle, explicitly deferred behind a disabled-by-default
  flag) and validated.
- Wiring any of these patterns into live trading decisions -- out of
  scope for this task.
