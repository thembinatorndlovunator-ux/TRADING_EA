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

Pending — see `git log` on `claude/task-028-python-statistical-lab`.

## Reviewer

**Not available this phase for a full review, but this task is explicitly
built for Codex's strict-auditor role per the user's own stated hybrid
workflow** — see `09_HANDOVERS/claude_to_codex/TASK-028_handover.md` for
exactly what to stress-test (edge cases, security, leakage risks).

## Final decision

**IN PROGRESS — foundation + 1 of 9 scripts complete and tested with real
evidence; 0 of 10 notebooks (1 non-required demo notebook built and
executed for real); remaining 8 scripts and 10 notebooks explicitly
backlogged as follow-up work, not silently claimed done.**
