# TASK-037 - MT5 real-data export bridge

## Objective

Build the MQL5/MT5-side export scripts that produce the real datasets
every Python-lab pipeline currently documents but has never run against:
a normalized trade-history export, a real news-calendar export, and a
real MQL5 pattern-detector-results export. Without this task, "Real-data
run: PENDING" cannot ever become "done" anywhere in this project.

## Reason

Codex's TASK-028 review (finding #2) explicitly required this be a
numbered owner rather than an indefinite "genuinely still remaining"
bullet: "The prose-only MT5 trade-export bridge and current EA
journal-population gap also remain unnumbered. Those gaps make real-data
execution impossible and must have explicit owners." This also directly
unblocks the real-evidence portions of `TASK-031` (regime confusion
matrix) and `TASK-033` (pattern cross-check), and TASK-035's ML training
data.

## Baseline behaviour

Neither immutable baseline EA has any export capability. `01_BASELINE/`
must not be modified.

## Evidence

- `09_HANDOVERS/codex_to_claude/TASK-028_review.md` finding #2.
- Every `analysis/*.py` module's own docstring documents the exact
  normalized CSV schema it expects and states no real export exists yet
  -- this task's job is to produce data in those already-documented
  shapes, not invent new ones.
- `03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/CandlestickPatternEngine.mqh`
  -- has no CSV/export function for detector results (needed for
  TASK-033's real cross-check).
- `03_SOURCE_CODE/MQL5/.../ChartPatternEngine.mqh` -- likewise has no
  export function, and is likewise needed for TASK-033's real cross-check
  (added, 2026-07-22 Codex review finding, third round -- previously
  omitted from this Evidence list despite TASK-033 deferring its
  cross-check here too).
- `03_SOURCE_CODE/MQL5/Include/ThembaEA/News/NewsManager.mqh` -- no
  CSV/SQLite deterministic-backtest provider exists (TASK-029's own
  explicitly deferred item).

## Specification

1. **Trade-history export**: a script (`Test_*.mq5` or a small
   standalone tool) that reads MT5's own Deals/History and writes the
   normalized `trades.csv` schema `analyse_baseline.py` et al. already
   document (`trade_id, symbol, is_long, entry_time, exit_time,
   entry_price, exit_price, stop_price, profit`).
2. **News-calendar export**: a script producing the `news_events.csv`
   schema `join_news_events.py` documents (`event_id, event_name,
   currency, importance, scheduled_utc`), sourced from MT5's built-in
   economic calendar (`MT5CalendarProvider.mqh` already reads this live;
   this task adds an export path) or independently from the FairEconomy
   feed already chosen for live use in TASK-034.
3. **Pattern-detector export**: a new function on
   `CandlestickPatternEngine.mqh` that writes each pattern predicate's
   per-bar boolean result to CSV in the `k, <pattern_name>...` shape
   `pattern_validation.compare_to_mql5_export` already expects. **Added,
   2026-07-22 Codex review finding (third round): this item previously
   named only `CandlestickPatternEngine.mqh` -- `TASK-033_PATTERN_
   VALIDATION_COMPLETION.md` explicitly defers BOTH the candlestick AND
   the chart-pattern real MQL5-export cross-check to this task (its own
   Objective/Out-of-scope say so), so this export must ALSO cover
   `ChartPatternEngine.mqh` (double top/bottom, head-and-shoulders/
   inverse) in the same per-bar boolean CSV shape -- a candlestick-only
   export would leave TASK-033's chart-pattern cross-check with no data
   source to run against.**
4. **Regime-dataset labelling protocol (added, 2026-07-22 Codex review
   finding, third round -- previously unspecified entirely, leaving
   acceptance criterion "a real, independently-labelled regime dataset
   is produced" with no actual protocol to satisfy it):** the
   "independently-labelled" ground truth for `regime_validation.
   build_confusion_matrix` cannot be the live EA's own
   `MarketRegimeEngine.mqh` output (that would be comparing the
   classifier against itself, not an independent label). Define and
   document a real labelling protocol here -- e.g. a human analyst
   hand-labelling a real historical chart segment bar-by-bar against the
   spec's own nine-state definitions (section 2), BEFORE looking at what
   the engine outputs for those same bars, with the labelling
   methodology and labeller identity recorded in the resulting dataset's
   provenance. Do not accept a self-referential or synthetic-fixture
   substitute as satisfying this.
5. Every export must itself follow this project's reproducibility
   contract (explicit paths, no hidden state, visible failures on
   malformed source data) -- these are pipelines like any other, not a
   special exemption.

## Files affected

- New MQL5 export scripts/functions under `03_SOURCE_CODE/MQL5/Scripts/`
  or added to the relevant `Include/` modules.
- `TASKS.md` and this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- Any live trading behavior change -- these are read-only exports of
  data that already exists inside MT5/the EA's own state.
- Building the analysis that CONSUMES these exports -- that already
  exists (TASK-028's scripts); this task only produces the input data.

## Risks

- An MT5 Deals export's exact column semantics (net vs. gross profit,
  commission/swap netting) must match what `analyse_baseline.py`'s
  docstring already assumes -- verify against a real small export, don't
  assume.
- A pattern-detector export must run the EXACT same MQL5 code path the
  live EA uses, not a reimplementation, or the "cross-check" in TASK-033
  would compare Python against a second, independently-written MQL5
  path rather than the real one.

## Test plan

1. Compile clean in MetaEditor, 0 errors/0 warnings, real log evidence.
2. Run each export against real (or realistic demo-account) MT5 data and
   confirm the output matches its documented schema exactly.
3. Feed each export into its corresponding Python pipeline
   (`analyse_baseline.py`, `join_news_events.py`,
   `pattern_validation.compare_to_mql5_export`) and confirm it runs
   without a schema error -- the first genuine "Real-data run" for each.

## Acceptance criteria

- [ ] Trade-history export produces a real `trades.csv` consumable by
      `analyse_baseline.py` without modification.
- [ ] News-calendar export produces a real `news_events.csv` consumable
      by `join_news_events.py` without modification.
- [ ] Pattern-detector export produces a real per-bar CSV consumable by
      `pattern_validation.compare_to_mql5_export` without modification,
      covering BOTH candlestick (`CandlestickPatternEngine.mqh`) AND
      chart patterns (`ChartPatternEngine.mqh` -- added, 2026-07-22 Codex
      review finding, third round), AND `compare_to_mql5_export` is
      actually run against both with the result reported (this closes
      the real-evidence obligation `TASK-033` explicitly deferred here).
- [ ] A real, independently-labelled regime dataset is produced using
      the labelling protocol defined in Specification item 4 (added,
      2026-07-22 Codex review finding, third round) and
      `regime_validation.build_confusion_matrix` is actually run against
      it with the result reported (this closes the real-evidence
      obligation `TASK-031` explicitly deferred here).
- [ ] Independent review completed and findings resolved.

## Rejection criteria

Reject if an export's schema doesn't actually match what the
corresponding Python pipeline documents (requiring a Python-side
work-around defeats the point), or if the pattern-detector export
reimplements pattern logic instead of exporting the live engine's own
output.

## Status

Not started. Registered per Codex's TASK-028 review finding #2
(2026-07-22).
