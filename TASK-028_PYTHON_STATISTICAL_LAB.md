# TASK-028 - Python/Jupyter statistical laboratory

## Objective

Implement the repository's reproducible Python/Jupyter analysis layer for
trade-export cleaning, journal/news joins, detector validation, risk and exit
research, walk-forward analysis, Monte Carlo analysis, and offline-learning
validation.

This is the primary Python implementation task from master-prompt sections 19
and 23 Phase 9. It also owns Python work explicitly deferred by earlier tasks,
especially TASK-016's regime fixtures/confusion matrix and TASK-024's score-
correlation validation.

## Reason

The repository currently has a Python dependency list but no committed `.py`
or `.ipynb` implementation. Without a dedicated task, required Python work has
no owner, reproducibility contract, or review gate.

## Baseline behaviour

Neither immutable baseline contains Python code. Baseline exports, logs,
screenshots, and reports are read-only evidence inputs. No file under
`01_BASELINE/` may be modified.

Python is for offline analysis and research, never unrestricted live execution
or automatic rewriting of EA source, parameters, set files, or model weights.

## Evidence

- `00_MASTER_PROMPT_FOR_CLAUDE.md:158-180` - permitted Python/Jupyter uses
  and paired-script reproducibility.
- `00_MASTER_PROMPT_FOR_CLAUDE.md:1125-1154` - ten required notebooks,
  paired scripts, and CSV/JSON outputs.
- `00_MASTER_PROMPT_FOR_CLAUDE.md:1457-1461` - Phase 9 offline learning and
  Python validation.
- `TEST_PLAN.md` - metrics, partitions, robustness tests, and rejection gates.
- `TASK-016_MARKET_REGIME_ENGINE.md` - deferred regime fixtures/confusion
  matrix.
- Master-prompt section 11 and TASK-024 - score-correlation audit.
- `TRADE_DECISION_SCHEMA.json` and TASK-009 - journal input contract.
- `requirements.txt` - currently declared Python dependencies.

## Specification

### Repository layout

Use the intended Python root already named by
`scripts/create_project_folders.ps1`:

- `03_SOURCE_CODE/Python/analysis/` - importable analysis modules and CLI
  scripts.
- `03_SOURCE_CODE/Python/data_collection/` - deterministic readers and
  normalizers for MT5 reports, trade exports, journals, and news data.
- `03_SOURCE_CODE/Python/news_connectors/` - approved offline/cache adapters;
  no broker credentials or trade execution.
- `03_SOURCE_CODE/Python/notebooks/` - required notebooks.
- `03_SOURCE_CODE/Python/tests/` - deterministic tests and synthetic fixtures.
- `08_RESULTS/python_reports/` - generated review outputs where repository
  size and privacy rules allow them.

### Reproducibility contract

1. Every notebook has a paired `.py` pipeline containing the actual logic.
   Notebook-only hidden/manual edits are prohibited.
2. Pipelines accept explicit input/output paths and do not depend on hidden
   kernel state, the current working directory, or GUI interaction.
3. Reports record Git commit, dataset identity/hash, symbol, broker, period,
   modelling mode, costs, set file, timezone, random seed, and pipeline
   version where applicable.
4. Randomized analysis uses explicit seeds and reports simulation/resample
   counts.
5. Schema errors, missing timestamps, duplicates, and timezone failures are
   visible failures, never silently coerced into plausible results.
6. Statistical claims report sample size and uncertainty. Tiny samples cannot
   drive automatic live parameter changes.
7. If real evidence data is unavailable, tests use clearly labelled synthetic
   fixtures and mark the real-data run pending rather than fabricate results.

### Required notebooks

Create the master-prompt section-19 set:

1. `01_baseline_trade_audit.ipynb`
2. `02_profit_giveback_analysis.ipynb`
3. `03_strategy_regime_analysis.ipynb`
4. `04_session_and_news_analysis.ipynb`
5. `05_mfe_mae_exit_analysis.ipynb`
6. `06_parameter_stability.ipynb`
7. `07_walk_forward_analysis.ipynb`
8. `08_monte_carlo_risk.ipynb`
9. `09_pattern_detector_validation.ipynb`
10. `10_baseline_vs_candidate.ipynb`

### Required scripts

At minimum, implement:

- `analyse_baseline.py`
- `analyse_giveback.py`
- `join_trade_journal.py`
- `join_news_events.py`
- `calculate_mfe_mae.py`
- `walk_forward.py`
- `monte_carlo.py`
- `pattern_validation.py`
- `compare_releases.py`

Shared modules should own schema validation, time normalization, performance
metrics, confidence intervals, deterministic resampling, report metadata, and
output serialization so notebook logic is not duplicated.

### Deferred validation included

- Synthetic fixtures for all nine regime states, gating overrides, data
  failure, and hysteresis; produce a confusion matrix against independently
  labelled evidence when available.
- Score-component correlation analysis, including correlated BOS/
  displacement, pin-bar/wick, and EMA evidence.
- Candlestick/chart-pattern validation against synthetic OHLC fixtures and
  exported MQL5 detector results.
- Journal validation and joins by durable signal/order/deal identity.
- Hand-verifiable MFE/MAE and equity-peak-giveback fixtures.

### Offline-learning boundary

Journal statistics and Python validation are required. Optional ML/ONNX work
may start only after the rule-based EA, dataset, and leakage controls pass
independent review and a separate experiment is approved.

## Files affected

Planned when implemented:

- New source, notebooks, tests, and fixtures under `03_SOURCE_CODE/Python/`.
- Reviewable outputs under `08_RESULTS/python_reports/` where permitted.
- `requirements.txt` only when a dependency is genuinely used and documented.
- `TASKS.md` and this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- Live order submission or account control from Python.
- Automatic EA/source/set-file/parameter/model-weight rewriting.
- Production ML/ONNX deployment without a separate approved experiment.
- In-sample profitability claims.
- Committing credentials, private exports, or sensitive account data.

## Risks

- Look-ahead leakage in outcome, regime, news, or detector joins.
- Survivorship/selection bias and repeated-testing bias.
- Broker/UTC/Botswana timezone and DST misalignment.
- Small-sample overinterpretation.
- Notebook/script divergence.
- Python/MQL5 metric-definition drift.
- Large generated files or sensitive data entering Git.

## Test plan

1. Install declared dependencies in a clean virtual environment.
2. Run deterministic unit tests on synthetic fixtures.
3. Execute every paired script with explicit paths.
4. Execute every notebook from a clean kernel and compare its core tables with
   the paired script.
5. Hand-check P/L aggregation, MFE/MAE, drawdown, giveback, confidence
   intervals, walk-forward splits, and Monte Carlo quantiles.
6. Test malformed schemas, duplicates, missing timestamps, timezone edges,
   empty samples, zero denominators, and deterministic seed repeatability.
7. Compare Python regime/pattern outputs with exported MQL5 fixtures; every
   difference must be explained or treated as a failed test.
8. Record exact formatter/linter/type-check/test versions and results.

## Acceptance criteria

- [ ] All ten notebooks execute from clean state.
- [ ] Every notebook has a paired reproducible `.py` pipeline.
- [ ] All nine named scripts exist and have automated tests.
- [ ] Deferred regime, score-correlation, and pattern-validation work is
      completed or split into independently numbered follow-ups.
- [ ] Reports contain required provenance, cost, timezone, and seed metadata.
- [ ] Synthetic calculations match independent hand calculations.
- [ ] No live execution, self-modification, future-data leakage, or credential
      handling is introduced.
- [ ] Outputs are reviewable as CSV/JSON as well as visual reports.
- [ ] Independent Codex review completed and findings resolved.

## Rejection criteria

Reject if notebooks depend on hidden state/manual edits; results are not
reproducible; leakage is present; uncertainty/sample size is hidden; Python can
place unrestricted live trades; code or parameters rewrite automatically;
sensitive data is committed; or claims cannot be traced to a named dataset,
commit, and pipeline version.

## Implementation notes (Claude, part 1 of N)

Codex's backlog registration above is reproduced unmodified. What follows
documents the first real implementation increment, built by Claude Code per
the project's established "build standalone + test, then hand to Codex as
strict auditor" workflow (the user's own stated preference for this task).

**Scope of this increment:** the shared foundation every later notebook/
script will import, plus the FIRST of the nine required scripts
(`join_trade_journal.py`) end to end, real and complete — not a stub. The
remaining eight scripts and all ten notebooks are explicitly NOT built yet
(see "Remaining backlog" below), split out per this task's own acceptance
criterion allowing deferred work to be "completed or split into
independently numbered follow-ups."

### What was built

- **Environment:** `.venv/` (already `.gitignore`d) with `pandas`, `numpy`,
  `scipy`, `pydantic`, `pytest` installed for real, plus `nbformat`/
  `nbclient`/`ipykernel` (added to `requirements.txt`) to actually execute
  the paired notebook from a clean kernel rather than hand-authoring it
  unverified.
- **`03_SOURCE_CODE/Python/analysis/schema.py`** — `TradeDecision` pydantic
  model, field-for-field matching `TRADE_DECISION_SCHEMA.json` and
  `DecisionJournal.mqh`'s actual serialization, `extra="forbid"`, strict
  UTC-only timestamps, a known-regime allowlist, NaN/inf rejection on
  `entry`/`stop`.
- **`03_SOURCE_CODE/Python/analysis/time_utils.py`** — UTC/server/Botswana
  (UTC+2, no DST, reusing `MT5CalendarProvider.mqh`'s TASK-029 stated
  assumption) conversions; `ensure_utc` never guesses a timezone for a
  naive datetime.
- **`03_SOURCE_CODE/Python/analysis/metrics.py`** — Wilson confidence
  interval, win rate, expectancy, profit factor (returns `None`, not
  `float('inf')`, when there are zero losing trades), and a seeded
  bootstrap confidence interval. Every function raises
  `InsufficientSampleError` on an empty sample rather than returning a
  silently-meaningless number.
- **`03_SOURCE_CODE/Python/analysis/resampling.py`** — `seeded_bootstrap_indices`,
  built on `numpy.random.default_rng` (not the legacy global RNG state),
  so results are reproducible given the same seed regardless of what else
  in the process touched `numpy.random` first.
- **`03_SOURCE_CODE/Python/analysis/report_metadata.py`** — git
  commit/dirty-state capture, per-file and combined-dataset SHA-256
  hashing (order-independent), and a `ReportMetadata` container covering
  every field the reproducibility contract requires.
- **`03_SOURCE_CODE/Python/data_collection/journal_reader.py`** — reads
  `decisions_*.jsonl` (matching `DJ_JournalFilePath`'s exact naming/layout),
  separates parse errors from schema-validation errors (neither silently
  dropped), and duplicate-detection on both `signal_id` and the practical
  interim `(timestamp_utc, symbol)` key.
- **`03_SOURCE_CODE/Python/analysis/join_trade_journal.py`** — the first of
  the nine required scripts, complete: CLI + a plain `run()` function for
  notebook/test use, writes CSV/JSON of valid records and a separate error
  report carrying full provenance metadata.
- **`03_SOURCE_CODE/Python/notebooks/00_journal_pipeline_demo.ipynb`** — NOT
  one of the ten required notebooks; a minimal, thin, actually-executed
  (via `jupyter execute` against a real registered kernel, real output
  captured, not hand-simulated) demonstration of the paired-notebook
  convention, using synthetic fixtures.
- **`03_SOURCE_CODE/Python/tests/`** — 70 tests, all synthetic-fixture-based,
  covering every module above including explicit edge cases (empty
  samples, zero-variance bootstrap, duplicate detection, malformed JSON
  lines, non-UTC timestamps, unknown regimes).

### A real, concrete cross-layer finding this increment surfaced

Running the real CLI against a journal line shaped EXACTLY like what
`ThembaAdaptiveIntradayEA.mq5` (TASK-025/027) actually emits today — via
an actual `python -m analysis.join_trade_journal` invocation, not a
hypothetical — confirms every real journal line the current EA build
produces will FAIL schema validation on `market_family`/`intraday_mode`
(both always empty strings; the live EA never sets either field). This
Python task cannot fix that — it is an MQL5-side gap — but it now has a
concrete, automated way to detect and quantify it once real journal data
exists. Flagged as a needed future MQL5 task, not silently worked around.

### Remaining backlog (explicitly NOT built this increment)

- 8 of 9 required scripts: `analyse_baseline.py`, `analyse_giveback.py`,
  `join_news_events.py`, `calculate_mfe_mae.py`, `walk_forward.py`,
  `monte_carlo.py`, `pattern_validation.py`, `compare_releases.py`.
- All 10 required notebooks.
- Deferred validation: regime confusion matrix (TASK-016), score-
  correlation analysis (TASK-024), candlestick/chart-pattern validation
  against MQL5 fixtures, MFE/MAE fixtures.
- `03_SOURCE_CODE/Python/news_connectors/` — empty, no adapter built yet
  (needs `join_news_events.py` first, which needs an agreed news-event
  export format from the MQL5 side — `NewsManager.mqh`, TASK-029, has no
  CSV/export path yet either).
- `08_RESULTS/python_reports/` — not created; nothing has been run against
  real data yet (no real journal exists, per the batched runtime-
  verification backlog every prior MQL5 task has also flagged).

## Commands run

```
git checkout -b claude/task-028-python-statistical-lab
python -m venv .venv
.venv/Scripts/python.exe -m pip install pandas numpy scipy pydantic pytest nbformat nbclient ipykernel
cd 03_SOURCE_CODE/Python
../../.venv/Scripts/python.exe -m pytest -v
../../.venv/Scripts/python.exe -m ipykernel install --user --name themba-python-lab
../../.venv/Scripts/python.exe -m jupyter execute --kernel_name=themba-python-lab notebooks/00_journal_pipeline_demo.ipynb
```

## Compiler result

Not applicable (Python, not MQL5) — see Test results for the equivalent
real-execution evidence this project requires in its place.

## Test results

**Real, verified.** `70 passed` via `pytest -v` against the actual
installed `.venv` (`pandas 3.0.3`, `numpy 2.5.1`, `pydantic 2.13.4`,
`scipy 1.18.0`, `pytest 9.1.1`). The paired notebook was executed for
real via `jupyter execute` against a registered kernel (not hand-
simulated) and produced the exact expected counts (1 valid record, 1
parse error, 1 validation error) with its own in-notebook assertions
passing. A real CLI smoke-test run (`python -m analysis.join_trade_journal`)
against a current-EA-shaped record independently confirmed the
market_family/intraday_mode finding above.

## Commit

19+ commits on `claude/task-028-python-statistical-lab` (part 1 through
both Codex-review remediation series) — see `git log` on that branch for
the full, current list rather than trusting a specific count/hash
recorded here, which has gone stale at least twice already (a lesson
this document itself is a live example of — see the round-2 doc-staleness
findings above).

## Reviewer

**Codex, via `/code-review ultra` — two independent review rounds
completed** (2026-07-21 and 2026-07-22; see
`09_HANDOVERS/codex_to_claude/TASK-028_review.md`, updated in place each
round). Round 1: 15 findings (2 P0/11 P1/2 P2), all resolved. Round 2: 16
findings (2 P0/11 P1/3 P2), all resolved — see the "part 4" remediation
notes below. A third review round should be requested once the user is
ready, per Codex's own stated disposition each time real correctness
issues are found.

## Implementation notes (Claude, part 2 of N — completes the 9 scripts + 10 notebooks)

Parts 2 through 7 of this implementation (commits on
`claude/task-028-python-statistical-lab` after the part-1 commit above)
completed all nine required scripts, added one bonus module closing a
different task's deferred item, and built all ten required notebooks.

### Scripts completed (all 9, each with its own test file)

2. **`calculate_mfe_mae.py`** — per-trade MFE/MAE from bar high/low data
   (`trade_math.py`'s `compute_mfe_mae`/`compute_r_multiple`, the latter a
   direct port of `ExitManager.mqh`'s `EM_ComputeR`).
3. **`analyse_giveback.py`** — offline simulation of both
   `ExitManager.mqh` giveback-guard models (`exit_simulation.py`, ported
   and cross-checked against the exact same hand-verified cases as
   `Test_ExitManager.mq5`) against historical bar-close R paths — never
   controls or wires to live trading.
4. **`analyse_baseline.py`** — aggregate win rate/expectancy/profit
   factor/max drawdown (`metrics.py`'s new `compute_max_drawdown`) over a
   normalized trade-export CSV.
5. **`join_news_events.py`** — independently recomputes `NEWS_BLACKOUT`
   status per journal decision against a news-events export; directly
   useful since every real journal record's `news_state` is currently
   always empty.
6. **`walk_forward.py`** — deterministic rolling train/test window
   generation (`generate_windows`, hand-traced) and per-window win-rate/
   expectancy stability metrics.
7. **`monte_carlo.py`** — seeded bootstrap resampling of a trade P/L
   sequence for final-equity/max-drawdown/ruin-probability distributions;
   explicitly documents the i.i.d.-resampling simplification (no
   trade-sequence autocorrelation).
8. **`pattern_validation.py`** — Python ports of 4 of
   `CandlestickPatternEngine.mqh`'s 18 pattern functions (bullish/bearish
   pin bar incl. TASK-017's fix, bullish/bearish engulfing); explicitly
   partial, and cross-checking against a real MQL5-exported
   detector-results CSV is not yet possible (no such export exists).
9. **`compare_releases.py`** — two-sample bootstrap CI on the win-rate/
   expectancy difference between two releases; never declares a release
   "better" automatically. Its own test suite incidentally demonstrates
   the reproducibility contract's "tiny samples cannot drive automatic
   changes" principle directly (a 4-trade-per-group stark gap correctly
   fails to reach significance; a 20-trade-per-group version of the same
   gap does).

**Bonus, beyond the 9-minimum list:** `regime_validation.py` — a Python
port of `MarketRegimeEngine.mqh`'s (TASK-016) classification formula.
Accepts `swing_agreement`/`direction_agree` as caller-supplied inputs
rather than re-implementing `MarketStructure.mqh`'s bias computation —
validates the regime-selection FORMULA, not the structure module. Only
7 of the 9 states are directly-computed and reproduced against synthetic
fixtures here (`NEWS_BLACKOUT`/`UNTRADEABLE_SPREAD_OR_LIQUIDITY` are
gating overrides applied before this function, not ported). **This does
NOT close TASK-016's deferred item** — full 9-state coverage, the
gating/hysteresis logic, and a confusion matrix against real
independently-labelled evidence are still open and are now tracked as
`TASK-031_REGIME_VALIDATION_COMPLETION.md` (see Codex's TASK-028 review
finding #1).

**Consolidation:** the `_parse_is_long` CSV-field parser, duplicated
across 4 scripts by part 1's end, was factored into
`analysis.csv_io.parse_is_long` and all call sites updated.

### All 10 required notebooks built and EXECUTED FOR REAL

Every notebook was run via `jupyter execute` against a registered kernel
(`themba-python-lab`) — not hand-simulated — with every in-notebook
`assert` passing (confirmed via each notebook's own real exit code, not
merely "no exception printed"). Each is a thin wrapper (per the
reproducibility contract's rule 1) around its paired script, using
clearly-labelled synthetic fixtures reused from that script's own
hand-verified test cases, with a closing "Real-data run: PENDING"
section per rule 7:

1. `01_baseline_trade_audit.ipynb` → `analyse_baseline.py`
2. `02_profit_giveback_analysis.ipynb` → `analyse_giveback.py`
3. `03_strategy_regime_analysis.ipynb` → `regime_validation.py`
4. `04_session_and_news_analysis.ipynb` → `join_news_events.py`
5. `05_mfe_mae_exit_analysis.ipynb` → `calculate_mfe_mae.py`
6. `06_parameter_stability.ipynb` → `parameter_stability.py` (real giveback-guard
   parameter sweep, as of the 2026-07-22 remediation -- previously misattributed
   to `walk_forward.py`, a stale mapping fixed per finding #16 of that round)
7. `07_walk_forward_analysis.ipynb` → `walk_forward.py` (split-mechanics framing)
8. `08_monte_carlo_risk.ipynb` → `monte_carlo.py`
9. `09_pattern_detector_validation.ipynb` → `pattern_validation.py`
10. `10_baseline_vs_candidate.ipynb` → `compare_releases.py`

(`00_journal_pipeline_demo.ipynb` from part 1 remains a non-required demo
of the paired-notebook pattern, not one of these ten.)

### What is still genuinely NOT done (explicit, not glossed over)

- **No real evidence data anywhere.** Every script and notebook operates
  on synthetic fixtures. Zero real MT5 trade exports, zero real news-event
  exports, zero real MQL5-exported pattern-detector results, and zero
  real journal files (the live EA's own runtime verification remains
  batched per TASK-025/027) exist in this project yet. Every "Real-data
  run: PENDING" note across all 11 notebooks is the honest, current state.
- **Deferred validation from the original spec, still open:** score-
  component correlation analysis (TASK-024's deferred item) has no
  dedicated module yet. Candlestick/chart-pattern validation is only
  4-of-18 patterns deep, and chart patterns (double top/bottom,
  head-and-shoulders) are not ported at all.
- **`03_SOURCE_CODE/Python/news_connectors/`** remains empty — no
  offline/cached adapter built (would need an agreed news-event export
  format from the MQL5 side first).
- **`08_RESULTS/python_reports/`** not created — nothing has been run
  against real data.
- **A future MT5-export-bridging task** is needed before any script here
  can run against real broker data — every script's own docstring states
  the normalized CSV schema it expects and why no real export exists yet
  to derive it from.
- **Offline-learning / ONNX work** (master-prompt Phase 9's optional
  ML track) is untouched, per the task's own explicit Out of scope
  statement — correctly not started.

## Commands run (parts 2-7, additive to part 1's)

```
# (same venv from part 1)
cd 03_SOURCE_CODE/Python
../../.venv/Scripts/python.exe -m pytest -v          # 196 passed
../../.venv/Scripts/python.exe -m jupyter execute --kernel_name=themba-python-lab notebooks/<NN>_*.ipynb --output=/tmp/exec_<NN>.ipynb   # x10, all exit 0
```

## Test results (parts 2-7)

**Real, verified.** `196 passed` via `pytest -v` (up from 70 at the end
of part 1). All 10 required notebooks executed successfully via `jupyter
execute` against a real registered kernel, confirmed via each notebook's
own process exit code (not merely absence of a printed traceback) — every
in-notebook `assert` (hand-verified numeric expectations, matching the
corresponding pytest cases) passed.

## Final decision

**9 of 9 required scripts complete and tested, plus two new real,
tested pipelines (`performance_breakdown.py`, `parameter_stability.py`)
added during round-2 remediation. All 10 required notebooks built,
paired to their scripts, and executed for real from a clean kernel. One
bonus module (`regime_validation.py`) partially addresses TASK-016's
deferred item (7 of 9 states, formula-only, no gating/hysteresis, no
confusion matrix against real evidence — full completion now tracked as
`TASK-031_REGIME_VALIDATION_COMPLETION.md`). Two full independent Codex
review rounds completed, 31 total findings across both, all resolved
with regression tests reproducing each reported counterexample. 340
tests passing, ruff and mypy both clean.**

## Implementation notes (Claude, part 3 of N — Codex review remediation)

Codex's independent review (`09_HANDOVERS/codex_to_claude/TASK-028_review.md`,
disposition CHANGES REQUESTED, 15 findings: 2 P0, 11 P1, 2 P2) was
resolved across 8 remediation commits (`4d3db0f` and earlier through
`fffa9ad`). Every P0/P1 finding got a real regression test reproducing
the exact counterexample Codex found; every P2 finding was either fixed
(environment pinning, ruff cleanup) or split into a numbered follow-up
task (this section). Real re-verification after remediation:

- `pytest -q` → **262 passed** (up from 196 pre-review).
- `ruff check .` → **All checks passed** (0 findings, down from 19).
- All 11 notebooks re-executed via
  `jupyter execute --kernel_name=themba-python-lab`, all exit 0.

Deferred deliverables Codex flagged as needing their own numbered tasks
rather than staying an undifferentiated backlog bullet are now:

- `TASK-031_REGIME_VALIDATION_COMPLETION.md` — full 9-state coverage,
  gating/hysteresis, confusion matrix against real independently-labelled
  evidence.
- `TASK-032_SCORE_CORRELATION_ANALYSIS.md` — TASK-024's deferred
  score-component correlation audit (BOS/displacement, pin-bar/wick, EMA
  evidence correlation).
- `TASK-033_PATTERN_VALIDATION_COMPLETION.md` — the remaining 14 of 18
  candlestick patterns and all chart patterns (double top/bottom,
  head-and-shoulders/inverse), cross-checked against real MQL5-exported
  detector results.

Genuinely still remaining beyond those three: an MT5-export-bridging
task (no real data exists anywhere in this project yet), `news_connectors/`,
and — as with every MQL5 task in this project — real-world runtime
confirmation, still batched. Per Codex's own required disposition, a
follow-up independent review round should be requested once the user is
ready.

## Implementation notes (Claude, part 4 of N — second Codex review round)

A second Codex review round (2026-07-22, same
`09_HANDOVERS/codex_to_claude/TASK-028_review.md`, updated in place) again
returned CHANGES REQUESTED — 16 findings (2 P0, 11 P1, 3 P2), several
substantive: the paired-pipeline contract still not fully satisfied
(notebooks 03/04/06 doing real analysis work inline instead of in a
script), walk-forward's window anchor structurally excluding the earliest
trade, a missing-profit column silently counted as a loss, timestamp
validation gaps in `analyse_baseline.py`/`compare_releases.py`, malformed
stop geometry producing plausible-looking 0R trades, Monte Carlo running
on arbitrarily tiny samples with mislabelled "95% CI" language,
`compare_releases` permitting cross-symbol comparisons and a degenerate
bootstrap win-rate interval, MFE/MAE bar-boundary contamination,
`join_news_events` silently dropping every invalid real-EA journal record,
output-aliasing and hash-before-parse ordering bugs, permissive CSV/JSON
validation (duplicate headers, blank IDs, duplicate JSON keys), a
memory-unsafe journal reader, an undeclared environment, and several stale
doc claims (including this document's own "closes TASK-016" and pattern-
count errors, fixed in the TASK-031/033 registration above).

**All 16 findings resolved this round:**

- Built real paired pipelines closing the paired-pipeline gap:
  `analysis/performance_breakdown.py` (strategy+regime+session/hour/day/
  symbol/direction breakdown, replacing notebook 03/04's inline groupbys)
  and `analysis/parameter_stability.py` (giveback-guard parameter sweep,
  replacing notebook 06's inline sweep and fixing its subset-mismatch
  statistical defect — every setting's mean is now computed over the same
  full path set, never a shrinking triggered-only subset). Genuine
  walk-forward parameter OPTIMIZATION (train-select-freeze-test, distinct
  from `walk_forward.py`'s honestly-scoped descriptive report) is
  registered as `TASK-038_WALK_FORWARD_OPTIMIZATION.md` rather than rushed.
- Fixed `walk_forward.py`'s window-zero anchor (now the earliest ENTRY,
  not earliest exit) and added `profit` to its finite-value validation
  (a missing/NaN profit previously read as a loss).
- Wired `parse_utc_series`/`assert_valid_stop_geometry` into
  `analyse_baseline.py` and `compare_releases.py`; fixed
  `analyse_baseline.py`'s same-timestamp drawdown nondeterminism by
  summing same-instant P/L into one balance step.
- Added `MIN_N_TRADES` floor, restored/strengthened the i.i.d.-resampling
  caveat, and relabelled `monte_carlo.py`'s interval fields as percentile
  scenario bounds, not "95% CI", everywhere they're presented.
- `compare_releases.py` now rejects cross-symbol comparisons even with no
  explicit `symbol` filter, and replaced the bootstrap win-rate-diff CI
  (degenerate at all-loss/all-win boundaries) with a proper Newcombe-Wilson
  two-proportion interval (`metrics.wilson_diff_confidence_interval`, new).
- Declared bar timestamps as bar-OPEN time and now REQUIRE entry/exit
  alignment to an actual bar in `calculate_mfe_mae.py`
  (`trade_math.BarAlignmentError`, new).
- `join_news_events.py` now surfaces every parse/validation error via an
  `errors_json` artifact and a non-zero exit code, instead of silently
  producing a successful empty analysis from a wholly-invalid real
  current-EA journal.
- Added `csv_io.assert_output_paths_distinct` (applied across every
  multi-output pipeline plus `pattern_validation.py`, which had none at
  all), fixed `join_trade_journal.py`/`join_news_events.py` to reject any
  output written inside their own input directory (not just matching it
  exactly), reordered journal hashing to happen BEFORE parsing, and wired
  the previously-unused `atomic_write_text` into every JSON write site.
- Added `csv_io.assert_high_low_geometry`'s open/close range check,
  `assert_unique_ids`'s blank/null rejection, `read_csv_with_required_columns`'s
  duplicate-header detection, `journal_reader`'s duplicate-JSON-key
  rejection (`object_pairs_hook`), and `join_news_events.py`'s
  importance-enum range check.
- `journal_reader.py` now streams and enforces `max_records` DURING the
  read (not after `readlines()` has already loaded everything), caps
  retained raw error-line length, and reports source files relative to
  the journal directory instead of an absolute path.
- Added `csv_io.sanitize_for_csv` (spreadsheet-formula-injection defense)
  and wired it into every CSV export carrying caller-controlled journal
  strings.
- `ReportMetadata` gained `ea_version`/`data_source` fields (wired into
  `analyse_baseline.py`/`compare_releases.py`'s CLI; available to every
  other script via `build_report_metadata`'s kwargs but not yet
  CLI-exposed there — a disclosed, not silently-complete, residual gap).
  `PIPELINE_VERSION` bumped `0.1.0` → `0.2.0`.
- Environment: `requirements-lock.txt` (real `pip freeze` of the full
  tested environment) added; ruff 0.15.22 and mypy 2.3.0 (new — this
  project's first type-checker pass, `mypy analysis data_collection
  --ignore-missing-imports` → "Success: no issues found in 23 source
  files") declared in `pyproject.toml`/`requirements.txt`.
- Fixed every stale doc claim this round found: this document's own
  false "closes TASK-016" claim and wrong pattern count (corrected in the
  TASK-031/033 registrations above), the Reviewer/notebook-06-mapping
  staleness fixed directly above, and notebook 03's matching stale claim
  in its own markdown.

Real re-verification after this round's remediation:

- `pytest -q` → **340 passed** (up from 262 after round 1).
- `ruff check .` → **All checks passed.**
- `mypy analysis data_collection --ignore-missing-imports` → **Success:
  no issues found in 23 source files** (first run, this round).
- All 11 notebooks re-executed via
  `jupyter execute --kernel_name=themba-python-lab`, all exit 0.

New numbered follow-ups registered this round (beyond TASK-031/032/033,
already registered after round 1): `TASK-036_JOURNAL_PRODUCER_COMPLETION.md`
(signal_id/market_family/intraday_mode/news_state/session_state
population, order_id/deal_id, FILE_ANSI-vs-UTF-8 fix),
`TASK-037_MT5_EXPORT_BRIDGE.md` (real trade/news/pattern-detector exports,
now also owning the real-evidence confusion matrix and MQL5-export
cross-check TASK-031/033 explicitly deferred to it), and
`TASK-038_WALK_FORWARD_OPTIMIZATION.md` (genuine train-select-freeze-test
parameter optimization).

Per Codex's own required disposition each round, a third independent
review round should be requested once the user is ready.
