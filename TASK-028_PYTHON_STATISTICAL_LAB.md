# TASK-028 - Python/Jupyter statistical laboratory

## Objective

Implement the repository's reproducible Python/Jupyter analysis layer for
trade-export cleaning, journal/news joins, detector validation, risk and exit
research, walk-forward analysis, Monte Carlo analysis, and offline-learning
validation.

This is the primary Python implementation task from master-prompt sections 19
and 23 Phase 9. It also owns Python work explicitly deferred by earlier tasks
(especially TASK-016's regime fixtures/confusion matrix) plus the master
prompt's own directly-required score-correlation audit (lines 747-757 —
corrected, 2026-07-22 Codex review finding, third round: this previously
misattributed the correlation requirement to TASK-024, which deferred a
different gap, three missing score components, not a correlation audit;
see `TASK-032_SCORE_CORRELATION_ANALYSIS.md`'s own correction).

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
- `00_MASTER_PROMPT_FOR_CLAUDE.md:747-757` - score-correlation audit
  requirement (corrected, 2026-07-22 Codex review finding, third round:
  not TASK-024, which deferred a different gap — see
  `TASK-032_SCORE_CORRELATION_ANALYSIS.md`'s own correction).
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
  correlation analysis (master prompt lines 747-757, not TASK-024 —
  corrected, 2026-07-22 Codex review finding, third round), candlestick/
  chart-pattern validation against MQL5 fixtures, MFE/MAE fixtures.
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

19+ commits on `claude/task-028-python-statistical-lab` (part 1 onward
— corrected, 2026-07-22 Codex review finding, fourth round: this
previously said "both," stale since the third round landed; round 4's
own independent count was 20 commits, `e37bbec` through `b88b63a` — the
durable "19+" wording itself is still accurate and deliberately not
being replaced with a moving target). **The "all three... remediation
series" ordinal claim itself went stale by round 6 (there have now been
six remediation series) and is deliberately not being replaced with
another moving target here either (Codex review finding, 2026-07-22,
sixth round, finding 17) — see `git log --grep=TASK-028` on that branch
for the full, current list and count rather than trusting a specific
count/ordinal recorded here, which has now gone stale at least three
times** (a lesson this document itself is a live example of — see the
round-2 doc-staleness findings above).

## Reviewer

**Codex, via `/code-review ultra` — nine independent review rounds
completed.** **Corrected, 2026-07-28 (Codex round-9 P2 finding 22, updated
in place a fourth time upon round 9's own full resolution): a ninth
review round returned 23 findings (7 P0, 14 P1, 2 P2) against round 8's
own resolution, all Git-timestamped 2026-07-27/28. Every finding received
either a real fix or, for two (finding 10's mode-first routing reorder,
finding 20's bar-0 convention unification) whose own full request is
genuinely large, separate architecture, a concrete numbered task
registration (`TASK-043`/`TASK-044`, both explicitly "Not started") --
see this file's own Round 9 history entry below for the full,
per-finding commit-by-commit account. A tenth review round should be
requested now that round 9 is fully resolved, not before.** Round 8
itself: an eighth review round returned 22 findings (10 P0/11 P1/1 P2)
against round 7's own resolution -- every one received a real fix, with
two (finding 12's mode-first routing-order half, finding 14's
chart-pattern lifecycle registry) explicitly, honestly disclosed as
PARTIAL at the time (see this file's own Round 8 history entry below for
the full account) and since closed or formally registered by round 9's
own remediation. (2026-07-21, 2026-07-22 x5; see
`09_HANDOVERS/codex_to_claude/TASK-028_review.md`, updated in place each
round -- it always holds the LATEST round's text only, never a
concatenation of all six; use the "Round 5"/"Round 6" entries in this
file's own history section below, or `git log --grep=TASK-028`, for
what earlier rounds actually said). Round 1: 15 findings (2 P0/11 P1/2
P2), remediation applied with regression tests. Round 2: 16 findings (2
P0/11 P1/3 P2), remediation applied with regression tests — see the
"part 4" remediation notes below. **Round 3 independently confirmed most
of rounds 1-2's fixes** (see that review's own "Corrections
independently confirmed" section -- walk-forward, baseline/release
comparison, giveback/MFE finite checks, bootstrap CI validation, the
Wilson interval, Monte Carlo's minimum-trade-count and caveats, path-
collision/atomic-write handling, CSV/JSON hardening, journal reading,
and all declared quality-gate commands were all independently verified
genuinely improved or resolved), while also surfacing 17 NEW findings (3
P0/10 P1/4 P2) against the round-2 HEAD, remediated in commit `b88b63a`
with regression tests per finding. **Round 4 independently confirmed
round 3's remediation was genuinely applied** (see that review's own
"Corrections independently confirmed" section), while surfacing 18
further findings (3 P0/11 P1/4 P2) against `b88b63a` -- required
deliverables that remained absent (equity-peak giveback, the missing
baseline-comparison metrics, a real session/mode/news outcome
breakdown), integrity defects in the new signal-to-outcome join, and
numerous smaller correctness/provenance gaps. Round 4's 18 findings were
remediated with regression tests per finding, committed as `750443d`.
**Round 5 independently confirmed several round-4 fixes were genuine**
(see that review's own "Corrections independently confirmed" section),
surfacing its own 18 findings (3 P0/11 P1/4 P2) against `750443d`, each
resolved with regression tests per finding (commits `aa39ac4` through
`52e8dec`, canonical-doc update `971e543`). **A sixth review then found
round 5's "fully resolved" canonical-doc characterization overbroad**,
surfacing 17 further findings (3 P0/12 P1/2 P2) against `971e543` --
several reproducing the exact class of counterexample the canonical docs
had just described as closed. All 12 P1s and both P2s from that sixth
round are now resolved with regression tests per finding (commits
`5ebea9a` through `8117111`, listed individually in this file's own
Round 6 history entry below); the 3 P0s are intentionally not yet
resolved, pending the user's own input on scope/risk (see the Round 6
history entry for why each one specifically needs a checkpoint rather
than an autonomous judgment call). A seventh review round should be
requested once the 3 P0s have a resolution or an agreed disposition, not
before.

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
   `CandlestickPatternEngine.mqh`'s 20 detector/predicate functions (19
   `CP_Is*Array` boolean predicates plus the non-boolean
   `CP_DetectHaramiArray` helper — corrected count, 2026-07-22 Codex
   review finding, third round; this previously said "18") — the 4
   ported are bullish/bearish pin bar incl. TASK-017's fix, bullish/
   bearish engulfing; explicitly partial, and cross-checking against a
   real MQL5-exported detector-results CSV is not yet possible (no such
   export exists).
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
3. `03_strategy_regime_analysis.ipynb` → `regime_validation.py` +
   `performance_breakdown.py` (added, 2026-07-22 remediation, third round
   -- this mapping previously omitted `performance_breakdown.py`, which
   this notebook also calls; a stale mapping fixed per Codex review
   finding #17)
4. `04_session_and_news_analysis.ipynb` → `join_news_events.py` +
   `performance_breakdown.py` (same fix as row 3 above)
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
  component correlation analysis (master prompt lines 747-757's own
  requirement, not TASK-024's deferred item — corrected, 2026-07-22
  Codex review finding, third round) has no dedicated module yet.
  Candlestick/chart-pattern validation is only
  4-of-20 patterns deep (corrected count, 2026-07-22 Codex review
  finding, third round; this previously said "4-of-18"), and chart
  patterns (double top/bottom, head-and-shoulders) are not ported at
  all.
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
`TASK-031_REGIME_VALIDATION_COMPLETION.md`). Four independent Codex
review rounds completed so far (see the Reviewer section above for the
full breakdown of each): rounds 1-2 (31 findings) and round 3 (17
findings) each had remediation applied with regression tests reproducing
every reported counterexample, and round 3's remediation was
independently confirmed genuinely resolved by round 4, which itself
surfaced 18 further findings now also remediated — 459 tests passing,
ruff (incl. `ruff format`) and mypy both clean as of this line. **This
line previously said "31 total findings... all resolved" (corrected,
third round) and then stopped at round 3 without reflecting round 4
(corrected, 2026-07-22 Codex review finding, fourth round) -- "remediation
applied, pending independent review" remains the honest phrasing for
round 4's own 18 findings until a fifth review actually runs.**

**Superseded, 2026-07-22 Codex review finding (sixth round, finding 17):
this section is a HISTORICAL CHECKPOINT frozen at round 4's own
remediation point (test count, round count, and "pending independent
review" phrasing all describe that moment, not the current state) --
kept as-is rather than endlessly re-edited in place each round, which is
exactly the "stale duplicated history" pattern round 6 flagged. For the
CURRENT, Git-verified state, see this file's own "Round 5"/"Round 6"
history entries further below (or run `git log --grep=TASK-028` /
`pytest -q` directly) -- do not trust the test count or round count on
this specific line for anything after round 4.**

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
- `TASK-032_SCORE_CORRELATION_ANALYSIS.md` — the master prompt's own
  score-component correlation audit requirement (lines 747-757, not
  TASK-024's deferred item — corrected, 2026-07-22 Codex review finding,
  third round; see that task file's own correction) (BOS/displacement,
  pin-bar/wick, EMA evidence correlation).
- `TASK-033_PATTERN_VALIDATION_COMPLETION.md` — the remaining 16 of 20
  candlestick detector/predicate functions (corrected count, 2026-07-22
  Codex review finding, third round; this previously said "14 of 18")
  and all chart patterns (double top/bottom,
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

## Implementation notes (Claude, parts 5-7 of N — third, fourth, and fifth Codex review rounds)

**Corrected, 2026-07-22 Codex review finding (fifth round, finding 18):**
this section was previously never appended after round 2 above, even
though rounds 3, 4, and (partially) 5 had all already landed in git —
the round-by-round remediation detail for those rounds lives in each
round's own commit message and (for rounds 4-5) in
`09_HANDOVERS/claude_to_codex/TASK-028_handover.md`'s `## UPDATE`
sections, not duplicated here. This section is a brief, honest pointer
so this canonical file does not read as if history stopped at round 2.

- **Round 3** (17 findings: 3 P0/10 P1/4 P2, reviewed against `fd07473`):
  fully resolved, committed as `b88b63a`. Highlights: `join_signal_to_outcome.py`
  built (the durable journal-decision-to-trade-outcome join), project-wide
  seed-threading fix (`seed or 42` silently dropping `seed=0`), a real
  look-ahead regression in `trade_math.compute_mfe_mae` corrected, `ruff
  format` declared and run as a real gate.
- **Round 4** (18 findings: 3 P0/11 P1/4 P2, reviewed against `b88b63a`):
  fully resolved, committed as `750443d`. Highlights: the (since renamed,
  see round 5) equity-peak-giveback metric and remaining baseline-comparison
  surface built into `analyse_baseline.py`; `join_signal_to_outcome.py`
  redesigned for partial-fill aggregation and durable-ID string typing
  (both since found incomplete by round 5 — see below); a real session/
  mode/news outcome breakdown added to notebook 04 (since found
  source-invalid by round 5).
- **Round 5** (18 findings: 3 P0/11 P1/4 P2, reviewed against `750443d`):
  each finding had a regression test reproducing the review's own
  counterexample, committed across `aa39ac4`, `9f4784e`, `8b0930f`,
  `4ce4a43`, `b51bc41`, `8fc05de`, `457970f`, `4e03b2b`, `17077a9`,
  `3a1bafc`, `ce0ee25`, `52e8dec`. This round caught SELF-INTRODUCED
  regressions in round 4's own remediation (the `join_signal_to_outcome.py`
  redesign in particular), not only pre-existing gaps — confirming this
  project's "every fix needs its own adversarial counterexample test"
  discipline is warranted. Resolved, in finding order: 1/2/3 (all P0 —
  balance-vs-equity giveback mislabeling + `compare_releases.py`
  side-by-side surface; the durable signal/outcome identity model; the
  source-invalid session-state mapping + notebook 04's move to the real
  composed pipeline), 4/5 (partial-fill $/R corruption, sidecar
  overwrite), 6 (provenance not bound to an immutable byte snapshot — the
  ABA-mutation race across `join_trade_journal.py`/`join_news_events.py`/
  `analyse_baseline.py` — **later found by round 6 to be non-exhaustive:
  see below**), 7 (`compare_releases.py`'s comparability manifest made
  required and role-specific — **later found by round 6 to still be
  incomplete: see below**), 8 (remaining overflow/non-finite gaps across
  the statistics layer — **later found by round 6 to be non-exhaustive:
  see below**), 9 (`parameter_stability.py`'s wrong-surface sweep — added
  the missing V8.11 2-D `arm_r`/`floor_r` grid; **this round's own module
  docstring simultaneously disclosed that the ANALOGOUS V6.37 2-D
  `arm_rr`/`giveback_percent` grid was still missing — finding 9 was
  therefore only PARTIALLY resolved here, not "fully resolved" as this
  section previously and wrongly summarized round 5 as a whole; round 6
  finding 11 caught this discrepancy and round 6's own remediation closed
  the remaining V6.37 2-D grid — see below**), 10 (hard-coded/unbounded
  resampling controls), 11 (row-order-dependent streak + wrong
  `trades_per_day` denominator), 12 (MFE/MAE and giveback accepting
  incomplete bar paths — `trade_math.assert_complete_bar_coverage`), 13
  (the net-P/L assumption-vs-requirement contradiction), 14 (task
  closure-safety gaps across TASK-018/031/033/034/036/037), 15/16 (P2 —
  `news_state`/`in_news_blackout` consistency, journal/news resource and
  identifier hardening), 17 (P2 — notebooks 01/10 now hand-check the
  newer summary/comparison fields against hand-traced fixture values, not
  just execute cleanly), 18 (P2 — this section's own history, kept
  current). 532 tests passing, ruff/ruff format/mypy clean, every
  notebook that imports an affected function re-executed with zero errors
  as of that update.

  **Corrected, 2026-07-22 (this section previously claimed round 5 was
  "fully resolved" and requested a sixth review on that basis — a sixth
  review then ran and found 17 remaining findings, several reproducing
  the exact class of counterexample this section claimed was closed;
  round 5 alone was not, in fact, sufficient for merge-readiness).** See
  the Round 6 entry below for the corrected, Git-verified state.

- **Round 6** (17 findings: 3 P0/12 P1/2 P2, reviewed against `971e543`,
  recorded verbatim as `8cb83b0`): confirmed round 5's remediation was
  real (see that review's own "Corrections independently confirmed"
  section) but found several items only PARTIALLY closed across the
  codebase (6: ABA-race provenance fixed in only 3 of 12 entry points; 7:
  comparability manifest checked for equality but not nonblank content,
  and ea_version/data_source still optional; 8: `compute_r_multiple`'s
  own division and `_point_diff`'s subtraction both still unchecked for
  overflow; 9: the V8.11 2-D grid left the analogous V6.37 grid
  undone while the canonical docs cited finding 9 as fully resolved
  anyway). **All 12 P1s and both P2s are now resolved**, each with a
  regression test reproducing the review's own reported counterexample,
  committed in finding order: 4 (`5ebea9a` — `join_signal_to_outcome.py`
  deal_id membership check, unrecognized direction/is_long rejection,
  aggregated-profit overflow), 5 (`afbca1c` — the ABA-race fix extended
  to all 9 remaining entry points, implicit-sidecar derivation extended
  to 8 of them), 6 (`4f4464a` — journal_reader.py rewritten to hash raw
  bytes in binary mode before any decoding, closing the "hash isn't
  exact-byte" gap; max_files/max_total_source_bytes/max_retained_errors
  ceilings added; csv_io.py gained a file-size ceiling), 7 (`905797e` —
  a shared `csv_io.TRADE_ID_DTYPE` applied to the 7 remaining trades.csv
  consumers), 8 (`4c7939a` — nonblank validation added to all 7 role-
  manifest pairs; ea_version/data_source made required, deliberately NOT
  equality-checked since a comparison's premise is that releases differ;
  notebook 10's claimed period corrected to match its own fixture), 9
  (`1612758` — `compute_trade_summary` gained n_resamples/confidence,
  threaded from `compare_releases.run`'s own top-level settings into both
  nested summaries; `expectancy`'s n==1 branch now validates its controls
  unconditionally), 10 (`512c77e` — `compute_r_multiple` hardened at its
  one shared root, closing three independently-reported overflow
  counterexamples at once; `compare_releases._point_diff` hardened
  separately), 11 (`c9e8623` — `sweep_v637_arm_rr_and_giveback_percent`/
  `run_v637_2d_sweep` added, closing the V6.37 2-D gap; canonical docs'
  finding-9 overclaim corrected), 12 (`d2c0175` — `longest_losing_streak`
  renamed to `longest_losing_balance_step_streak`; bootstrap CIs added to
  avg winner/loser/duration; notebook 01 exercises the authenticated-
  period route), 13 (`3cd8236` — cadence-quantizes-to-zero ValueError;
  cadence persisted in both artifacts; TASK-037 required to update the
  non-conforming consumer, not just name a convention), 14 (`37c4bdc` —
  `TASK-039_CHART_PATTERN_COMPLETION.md` registered for the 13 unowned
  chart-pattern families), 15 (`0f1feb7` — TASK-034's metal/synthetic
  provider-selection rule and synthetic-bypass test added; news_state
  whitespace/case near-miss normalization), 16 (`8117111` — notebook 10
  hand-checks `baseline_summary`/`candidate_summary`/`surface_diff` and
  its false "total separation" claim corrected; `derive_session_state`
  made real and unit-tested, notebook 04 exercises `UNKNOWN`), 17 (this
  history entry, `TASKS.md`'s row, and
  `09_HANDOVERS/claude_to_codex/TASK-028_handover.md`'s own UPDATE
  section, all corrected in the same pass). 602 tests passing (up from
  532 at round 5's close), ruff/ruff format/mypy clean, all 11 notebooks
  re-executed with zero errors as of this update.

  **The 3 P0s (1: durable identity model uses MT5's unstable
  `POSITION_TICKET` where the documented stable key is
  `POSITION_IDENTIFIER`/`DEAL_POSITION_ID`; 2: mandatory equity/drawdown/
  giveback/cost-comparison deliverables remain genuinely blocked without
  a real intratrade equity-tick export; 3: live mode classification and
  regime-transition evidence are unowned new EA feature scope) are
  intentionally NOT resolved as of this update** -- each involves either
  a live-trading-EA identity/behavior change needing a MetaEditor compile
  this sandbox cannot perform, an input this project does not have yet,
  or new feature scope rather than a bug fix; per this project's own
  workflow discipline, these get a user checkpoint before any code is
  written, not an autonomous judgment call. A seventh independent review
  should be requested once the 3 P0s have a resolution or an agreed
  disposition, not before.

  **Update, 2026-07-22, same day:** the user reviewed all three P0s and
  directed "do everything now... then we do a codex review after
  everything is done" -- explicitly authorizing the code changes this
  entry's own P0-1/P0-3 note above said needed a checkpoint first,
  and deliberately replacing this project's usual per-task review cadence
  with one consolidated review at the end of the sprint. Under that
  directive: **P0-1 resolved** (`64779d6` — `SOrderOpenResult` gained a
  `position_id` field alongside the existing `position_ticket`, populated
  via `PositionGetInteger(POSITION_IDENTIFIER)`; `position_ticket` itself
  is kept, unchanged, since `PositionSelectByTicket`/`CTrade::PositionClose`
  still require the live session ticket for immediate operations --
  neither field replaces the other). **P0-3 resolved** (`TASK-040`,
  `IntradayModeRouter.mqh`: live `market_family` via broker-curated
  `SYMBOL_PATH`, plus a first-pass `intraday_mode` classifier; `TASK-034`'s
  `RegimeGateComposer.mqh`, built the same day, also closes this finding's
  "the EA does not compose the two override states into a live nine-state
  result" sub-point). TASK-031's own regime-transition-history buffer gap,
  which this same P0-3 finding also named, remains that task's separate,
  not-yet-started scope. **P0-2 remains genuinely blocked** -- no amount of
  working faster substitutes for the real intratrade equity-tick export
  this project does not have; it stays explicitly named as blocked, not
  worked around. Both `ThembaAdaptiveIntradayEA.mq5` and every new test
  script compile clean (0 errors/0 warnings, real MetaEditor evidence) as
  of this update.

  **Further update, same day (TASK-037):** P0-2's missing-INFRASTRUCTURE
  half is now closed -- `EquityTickRecorder.mq5` (a standalone,
  continuously-running EA; a one-shot script cannot sample every tick)
  now exists and compiles clean. The metrics themselves remain blocked --
  no REAL equity-tick data exists yet, since that requires the user to
  actually run it against a real/demo account, which this sandbox cannot
  do. P0-2 moves from "no export exists" to "export exists, real data
  does not yet" -- still not resolved, not silently claimed done.

- **Round 7 (2026-07-22), a seventh independent Codex review** (requested
  once round 6's 3 P0s reached the disposition this file's own round-6
  entry above named, per that entry's own "a seventh independent review
  should be requested once the 3 P0s have a resolution or an agreed
  disposition" condition): **20 findings (10 P0, 9 P1, 1 P2), disposition
  CHANGES REQUESTED**, written to
  `09_HANDOVERS/codex_to_claude/TASK-028_review.md`. **Corrected, 2026-07-27
  (Codex round-8 P2 finding 22): "All 20 are now resolved" below previously
  had no qualification, contradicting several findings' own retained,
  named, bounded follow-up items (the pipeline-reorder half of finding 6,
  the spread/liquidity-gate limitation in finding 12, the bar0-convention
  unification and cost-sensitivity export explicitly NOT done per finding
  17 -- see `09_HANDOVERS/claude_to_codex/TASK-028_round7_handover.md`'s
  own "What Claude did NOT do this round" section for the exhaustive
  list).** Every finding's PRIMARY defect is resolved, each with a real fix,
  a regression test reproducing the exact reported counterexample, and
  either a clean MetaEditor compile (0
  errors/0 warnings; full evidence retained in
  `09_HANDOVERS/compile_evidence/TASK-028_round7_full_compile_evidence_2026-07-22.txt`,
  covering the EA and all 38 `Test_*.mq5`/`Export_*.mq5` scripts, not just
  this round's own touched files) or a passing Python test suite (694
  passed as of the last P1 fix; commits below run sequentially, so a
  later commit's own test count supersedes an earlier one). All 10 P0s:
  IntentManager's create-if-absent race (finding 1), the journal-to-
  history identity/event schema mismatch (finding 2), the live order
  path's hard-risk-policy gaps (finding 3), MT5-calendar decode/timing
  bugs (finding 4), news fail-safe gaps (finding 5), IntradayModeRouter's
  non-canonical formula now replaced with the real TASK-002 section 1
  spec (finding 6), regime fail-open/non-journaled-failure behavior
  (finding 7), end-of-day closure and exit-management ordering (finding
  8), `Export_TradeHistory`'s multi-fill/reversal/cost/stop bugs (finding
  9, now backed by a new pure `TradeHistoryAggregator.mqh` module), and
  broker-timestamp UTC mislabeling (finding 10). All 9 P1s: pattern export
  schema incompatibility + triple-top/bottom geometry (finding 11,
  including wiring the triple detectors into `ChartPatternStrategy.mqh`'s
  live path for the first time), the predicted-regime exporter rewritten
  to replay the full gated state machine chronologically instead of the
  raw stateless classifier (finding 12), a new `analysis/
  equity_curve_metrics.py` Python consumer for the equity-tick export
  (finding 13, closing round 6's own P0-2 for good), daily/weekly
  baseline double-counting from a cash-flow-adjustment ordering bug
  (finding 14), six Python domain-validation gaps across
  `regime_validation.py`/`join_signal_to_outcome.py`/
  `parameter_stability.py`/`trade_math.py` (finding 15), journal
  vocabulary/signal_id-collision/file-locking/build-provenance issues
  (finding 18, publisher-side; schema.py's own vocabulary fix is finding
  17's own subject too), eight pipelines' result-CSV-before-provenance-
  sidecar ordering plus several other provenance/resource-ceiling gaps
  (finding 16), and permissive/unauthenticated research conventions --
  `news_state` now a real `Literal["CLEAR", "BLACKOUT"]` and
  `compare_releases.py`'s new period-coverage-ratio fields (finding 17).
  The 1 P2 (finding 20) is this canonical-documentation-accuracy finding
  itself -- resolved by this same history entry, `TASKS.md`'s own
  corrected rows, `TASK-036`/`TASK-037`/`TASK-039`'s own corrected
  sections, and a new `TASK-042_REMAINING_CHART_PATTERNS.md` registering
  TASK-039's previously-unnamed remaining-chart-pattern owner under a
  concrete task number. See
  `09_HANDOVERS/claude_to_codex/TASK-028_round7_handover.md` for the full,
  per-finding commit-by-commit account.

- **Round 8, an eighth independent Codex review** (requested per round
  7's own handover, which stated it "is the request for the next review
  round"): **22 findings (10 P0, 11 P1, 1 P2), disposition CHANGES
  REQUESTED**, written to `09_HANDOVERS/codex_to_claude/TASK-028_review.md`
  (commit `ed46ded`). **Corrected, 2026-07-27 (Codex round-9 P2 finding
  22): this entry previously said "Round 8 (2026-07-22)" -- the review
  commit `ed46ded` and its entire 22-commit remediation/handover range
  are all Git-timestamped 2026-07-27, not 2026-07-22. Every date claim in
  this project's canonical docs must be the Git-recorded date, not an
  assumed/copy-pasted one.**
  Every one of the 22 findings received a real, committed fix for its own
  reported PRIMARY defect, with a regression test reproducing the exact
  counterexample (or, for finding 21, a full 41-target MetaEditor compile
  pass in place of a Python regression test) -- but **"all 22 resolved"
  is not, by itself, an accurate summary of scope, and this entry no
  longer states it that way (Codex round-9 P2 finding 22's own
  complaint): finding 12's own commit message explicitly, honestly
  deferred its ROUTING-ORDER half (mode computed before candidate
  generation, not after) as "a substantial separate architectural task,"
  and finding 14's own fix explicitly left the chart-pattern lifecycle
  registry (FORMING/CONFIRMED/RETESTING/TRADED/INVALIDATED/EXPIRED,
  consumed-pattern suppression) unimplemented in source -- both were
  real, disclosed, PARTIAL fixes, not silently-dropped ones, but "all 22
  resolved" as a blanket headline obscured that distinction. Round 9's
  own remediation (this same document's next history entry) has SINCE
  closed the chart-pattern lifecycle gap in full and formally registered
  the mode-first routing-order gap as `TASK-043_MODE_FIRST_ROUTING_ARCHITECTURE.md`
  (not yet implemented) rather than leaving it another unnumbered
  "future task."** Full evidence retained at
  `09_HANDOVERS/compile_evidence/TASK-028_round8_full_compile_evidence_2026-07-27.txt`,
  covering the EA, `EquityTickRecorder.mq5`, and all 39 `Test_*.mq5`/
  `Export_*.mq5` scripts -- 41 targets, not just this round's own touched
  files) or a passing Python test suite (718 passed as of the final
  finding). All 10 P0s: account-mode guard exactly inverted (finding 1,
  `af06cb8`), spread gate 20x too wide/unbounded (finding 2, `b719b94`),
  incomplete hard-risk path (finding 3, `338bd3c`), risk-persistence
  atomicity/fail-open (finding 4, `9e9dc1c`), durable-intent protocol gaps
  (finding 5, `37b1f4d`), GlobalVariable key length overflow (finding 6,
  `453cd77`), fail-open news-provider paths (finding 7, `29efe7e`), a
  partial fill recorded as rejection instead of live exposure (finding 8,
  `dd312cd`), a low-confidence bar not bypassing hysteresis immediately
  (finding 9, `c534f85`), and the mandatory intraday close not guaranteed
  across a no-tick boundary (finding 10, `95268e0`). All 11 P1s: order
  identity/actual-fill journaling gaps (finding 11, `e352e7e`),
  mode-routing's invalid NONE/UNKNOWN vocabulary (finding 12, `85dc773` --
  the routing-ORDER half of this finding was explicitly, honestly deferred
  as a substantial separate architectural task, not silently dropped, per
  that commit's own message), position-lifecycle-unsafe close/cooldown
  handling (finding 13, `b7c68c2`), stale sloped chart-pattern boundary
  evaluation (finding 14, `b274a45`), csv_io.py's 500MB allocation causing
  a pytest MemoryError (finding 15, `95cb591`), non-atomic error budgets
  and multi-artifact report publication (finding 16, `87d93d1`), the
  Python-vs-MQL5 pattern cross-check accepting a completely different
  dataset (finding 17, `ead49e8`), equity analysis merging unrelated
  runs/accounts into one artificial curve (finding 18, `79d21dd`),
  several permissive/inconsistent schema and domain contracts including
  a stale journal_reader.py assumption fixed as direct fallout (finding
  19, `ca2cbe1`), two notebooks failing clean-kernel execution plus eight
  files failing `ruff format --check` (finding 20, `47d4a56`), and
  incomplete/misattributed MQL compile evidence including a
  seven-commits-stale `THEMBA_EA_GIT_COMMIT` (finding 21, `c9b2298`,
  resolved last so the compile evidence and build-commit macro reflect
  the truly final round-8 state). The 1 P2 (finding 22, `990f32c`) is
  this canonical-documentation-accuracy finding itself -- corrected
  TASK-028_round7_handover.md's and this file's own "all resolved"
  overclaims, `TASK-037`/`TASK-040`/`TASK-041`'s stale behavior
  descriptions, and `TASKS.md`'s own stale counts/status mismatches. See
  `09_HANDOVERS/claude_to_codex/TASK-028_round8_handover.md` for the full,
  per-finding commit-by-commit account.

- **Round 9 (2026-07-27/28), a ninth independent Codex review** (requested
  per round 8's own handover): **23 findings (7 P0, 14 P1, 2 P2),
  disposition CHANGES REQUESTED**, written to
  `09_HANDOVERS/codex_to_claude/TASK-028_review.md` (commit `c70ee72`).
  Every finding received either a real, committed fix for its own
  reported primary defect (a regression test reproducing the exact
  counterexample where one could be constructed) or -- for two findings
  whose own full request is genuinely large, separate architecture
  (finding 10's mode-first routing reorder, finding 20's bar-0
  convention unification) -- a concrete, numbered task registration
  (`TASK-043`/`TASK-044`, both "Not started" in their own Status
  sections) rather than an unnumbered "future task." All 7 P0s: hard-risk
  cap still fail-open/raceable/unenforced post-fill (`3a5549a`), risk
  persistence still non-transactional/unsafe (`fad8901`), durable intent
  race/wrong-order-correlation/premature-clear (`a38e98c`), partial/async
  fill terminal-state handling still unsafe (`4d69783`), FairEconomy
  accepting partial/malformed calendar payload as safe (`2dd855b`),
  mandatory-close/no-stop obligations silently stopping retry on write
  failure (`892425d`), `OnInit` permitting settings that defeat hard
  limits (`996039b`). All 14 P1s: cash-flow deals causing false daily/
  weekly breach before rebasing (`03d1f17`), async fills absent from
  machine-readable journal evidence (`c3815ad`), mode-first routing
  architecture registered as `TASK-043` (`1974b98`), chart-pattern
  lifecycle registry built in full (`d04fed9`), CSV+JSON publish
  rollback destroying a prior valid report (`19f16ff`),
  `max_retained_errors` bypassed for excluded/non-file candidates
  (`7100ff0`), Python/MQL pattern comparator accepting different/non-
  finite datasets (`e573276`), stale pattern-export docs + notebook 09
  self-comparison honestly re-labelled (`6bf68dc`), equity analysis
  accepting blank identity + wrong daily-reset clock (`b84446c`), journal
  schema still admitting blank/out-of-domain provenance via whitespace
  (`8bbd881`), performance_breakdown validating normalized news_state but
  grouping the unnormalized original (`e4e2ab5`), the nominal 500 MB CSV
  ceiling still permitting multi-gigabyte peak memory (`7a797d3`), the
  three incompatible bar-0 conventions registered as `TASK-044`
  (`8510cc2`), compile-evidence false Git provenance corrected/MQL
  runtime execution honestly disclosed as sandbox-blocked (`a2699f2`).
  The 2 P2s: canonical docs contradicting reality yet again, including
  this same history entry's own date/blanket-claim corrections
  (`4683afb`), and committed notebook output/diff hygiene (`33cd86d`).
  A whole-project `mypy .` gate run (the first of this remediation pass)
  surfaced and fixed one real, pre-existing, unrelated type error
  (`2e71e38`). Full evidence retained at
  `09_HANDOVERS/compile_evidence/TASK-028_round9_full_compile_evidence_2026-07-28.txt`
  (`a4cc8f5`), covering all 46 `.mq5` targets (up from round-8's 41 --
  this round added `Test_ChartPatternLifecycle.mq5` and
  `Test_ExecutionEventJournal.mq5`), 0 errors/0 warnings, and a passing
  Python test suite (749 passed). See
  `09_HANDOVERS/claude_to_codex/TASK-028_round9_handover.md` for the
  full, per-finding commit-by-commit account.
