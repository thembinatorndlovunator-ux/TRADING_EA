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

## Implementation notes

This registers backlog work only. No Python implementation, dependency
installation, data download, or result generation is claimed here. TASK-027's
number and active branch remain reserved for the order-manager-wiring work.

## Commands run

Read-only repository status, task-number, roadmap, folder-scaffold,
dependency, and Python-reference checks.

## Compiler result

Not applicable to backlog registration.

## Test results

Not run - no Python code was implemented.

## Commit

Pending. Codex did not create a commit.

## Reviewer

Pending implementation and independent review.

## Final decision

**NOT STARTED - BACKLOG REGISTERED.**
