# Codex Independent Code Review — TASK-028 Python/Jupyter Statistical Laboratory

**Disposition: CHANGES REQUESTED**

TASK-028 is **not ready to merge or close** at `fd07473fe53d42044518c5af514973a63a5e1eca`.
The remediation contains many real fixes, and all committed automated gates are
green, but required paired analyses, evidence identity, statistical
reproducibility, and future-data controls still have release-blocking defects.
Several new tests also encode the defective behavior rather than detecting it.

## Review target and independent evidence

- Branch: `claude/task-028-python-statistical-lab`
- Reviewed HEAD: `fd07473fe53d42044518c5af514973a63a5e1eca`
- Previous reviewed HEAD: `c775a6e`
- Remediation diff: 50 files, 3,999 insertions, 1,032 deletions.
- Full test suite: **340 passed** in 17.02 seconds.
- Ruff 0.15.22: **All checks passed**.
- mypy 2.3.0: **Success; no issues in 23 source files**.
- All 11 committed notebooks independently executed with fresh kernels and
  exited 0.
- The committed `requirements-lock.txt` exactly matches the active venv's
  ordinary `pip freeze` package set.
- Direct adversarial probes reproduced the MFE exit-bar look-ahead, invalid
  statistical inputs becoming results, a hash/parse snapshot mismatch,
  hard-link input overwrite, duplicate-journal acceptance, multiline duplicate
  CSV-header bypass, nested numeric overflow, and CSV formula injection.
- No file under `01_BASELINE/` was modified. The V6.37/V8.11 EA files and both
  `IDENTITY.md` files have the same Git blob IDs at HEAD as at their respective
  `baseline-v637`/`baseline-v811` tags.

## Findings

### 1. [P0] `parameter_stability.py` is not an explicit-input reproducible pipeline

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:63-79,161-188`;
`analysis/parameter_stability.py:50-168`;
`notebooks/06_parameter_stability.ipynb:7-23`.

`run()` accepts only caller-created in-memory R paths. The CLI accepts no input
path, always prints that no input source exists, and exits 1. Its hand-built
metadata consequently has no dataset identity/hash, timezone, or pipeline
version. Notebook 06 passes only because it creates the paths inside its kernel.
This does not satisfy the contract that pipelines accept explicit input/output
paths and identify the analyzed dataset.

The computational boundary is also unsafe: only non-empty collections are
validated. A NaN path and NaN `giveback_percent` produce a successful,
plausible-looking row, and values outside 10–90 are reported under the supplied
label even though `exit_simulation.py:23-30` silently clamps them. Distinct
reported settings can therefore execute the same setting. Constant multi-path
samples also suppress an otherwise valid degenerate bootstrap interval instead
of reporting it.

Provide a documented file schema and functioning CLI, hash that input, validate
all paths and parameters as finite and in range (or report both requested and
effective values), and persist the complete resampling configuration.

### 2. [P0] The required session/mode/news performance analysis is still incomplete

**Files:** `00_MASTER_PROMPT_FOR_CLAUDE.md:164-173`;
`TEST_PLAN.md:9-23`; `analysis/performance_breakdown.py:1-45,69-142`;
`notebooks/04_session_and_news_analysis.ipynb:15-19,77-97`.

The new pipeline claims the full strategy/setup/regime/session/symbol/direction/
hour/day/news-window breakdown, but its allowed dimensions omit both
`intraday_mode`/mode and `news_state`/`in_news_blackout`. Its documented
`r_multiple` input is unused, so it reports only dollar expectancy. Despite the
docstring saying dimensions must be a subset of `OPTIONAL_DIMENSIONS`, the code
checks only that a column exists, allowing arbitrary groupings such as
`trade_id` or `profit`.

Notebook 04 says it groups by trading session and reports session win rate, but
it actually groups only by derived `hour_of_day`. Its closing text then refers
to the removed implementation as “simplified fixed UTC-hour buckets.” Neither
the notebook nor its tests exercises `session_state`, and the named export
follow-up does not define the broker session-table export the notebook says is
needed. A generic ability to group a hypothetical supplied column is not the
required session/news analysis.

### 3. [P0] The required durable journal-decision-to-trade-outcome join is unimplemented and unowned

**Files:** `00_MASTER_PROMPT_FOR_CLAUDE.md:164-170`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:114-124`;
`analysis/join_trade_journal.py:1-16`;
`analysis/performance_breakdown.py:29-45`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:63-66,84-110`;
`TASK-037_MT5_EXPORT_BRIDGE.md:43-47,71-76`.

`join_trade_journal.py` cleans journal records; it does not join them to trade
outcomes. `performance_breakdown.py` requires an already-unified CSV and does
not build it. TASK-036 adds `order_id`/`deal_id` but explicitly excludes the
consuming join, while its own test plan nevertheless promises an end-to-end
join. TASK-037's trade schema omits those IDs and also declares consuming
analysis out of scope. Adding identifiers to producers is necessary but is not
an end-to-end join pipeline. Give the join an explicit implementation owner,
schema, duplicate/cardinality rules, partial-fill semantics, tests, and
reviewable outputs.

### 4. [P1] Bootstrap uncertainty uses hidden or falsely recorded seeds

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:69-77`;
`analysis/metrics.py:195-230`;
`analysis/analyse_baseline.py:146-191`;
`analysis/analyse_giveback.py:193-241`;
`analysis/performance_breakdown.py:95-191`;
`analysis/walk_forward.py:1-10,120-148,164-284`.

- `walk_forward.py` says it performs no randomization and needs no seed, yet
  every non-singleton expectancy invokes a bootstrap with hidden defaults. Its
  API and report expose no seed, resample count, or confidence.
- `performance_breakdown.run(seed=...)` records the supplied seed in metadata,
  but `compute_breakdown()` always uses `expectancy()`'s seed 42.
- `analyse_giveback` uses `seed or 42`; an explicit seed of 0 is recorded as 0
  while seed 42 generates the interval. It omits confidence and resample count.
- `analyse_baseline` never forwards its seed and discards the expectancy CI,
  confidence, resample count, and actual bootstrap seed from its summary.

Every randomized calculation must receive the reported seed/configuration, and
the result artifact—not merely an optional metadata object—must retain it.

### 5. [P1] Non-finite values and required uncertainty still bypass the shared statistical layer

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:74-77,190-196`;
`analysis/metrics.py:1-9,38-60,73-94,195-260`;
`analysis/compare_releases.py:104-167`;
`analysis/analyse_baseline.py:149-182`.

Direct calls produced the following instead of visible failures:

- `expectancy([NaN])` returned a one-observation result whose expectancy is
  NaN because the n=1 branch runs before finite validation.
- `profit_factor([NaN])` returned an undefined factor with zero wins and zero
  losses.
- `two_sample_bootstrap_diff()` accepted a non-finite sample and returned NaN
  point/interval fields.

The module header still says every function returns sample size and uncertainty,
which is false for `MaxDrawdownResult`, the raw Wilson tuple, and profit factor's
total sample. The baseline artifact still exposes no expectancy CI and no
uncertainty for profit factor or drawdown. Primary CSV wrappers catch some of
these cases, but these are public shared functions and the new in-memory
parameter pipeline bypasses those wrappers.

### 6. [P1] The MFE/MAE “bar-open alignment” fix still uses post-exit prices, and giveback timing remains undefined

**Files:** `analysis/trade_math.py:60-136`;
`analysis/calculate_mfe_mae.py:12-19,90-161`;
`analysis/analyse_giveback.py:18-22,108-169`;
`tests/test_trade_math.py:149-162`.

`trade_math.py` declares every timestamp to be the bar's **open** time and
requires the trade exit to equal such a timestamp, but then selects
`timestamp <= exit_time`. The entire exit bar therefore occurs after the trade
has exited. A direct two-bar probe with entry 00:00, exit 01:00, and an extreme
01:00 bar returned `mfe_r=449.5` and `mae_r=-50.0`, entirely from post-exit
movement. Under the declared convention the ordinary interval is
`[entry_time, exit_time)`; the current test explicitly enshrines the inclusive
bug.

Giveback analysis does not even declare whether its timestamps denote bar opens
or closes, requires no boundary alignment, and includes both endpoints. A
00:30–01:30 trade with only a 01:00 bar completed with zero row errors.
Neither analysis rejects duplicate `(symbol,timestamp)` bars or checks expected
interior coverage. This is precisely the future-data/measurement-contamination
rejection condition, not a documentation-only caveat.

### 7. [P1] Impossible trade chronology remains valid evidence

**Files:** `analysis/analyse_baseline.py:105-153`;
`analysis/compare_releases.py:57-89`;
`analysis/walk_forward.py:185-216`.

These pipelines strictly parse both timestamps but never require
`entry_time <= exit_time`. A baseline trade whose entry was one day after its
exit was accepted and reported as one valid trade. Add a shared chronology
check before any metric, sort, or window operation. Per-row pipelines may
report the row as an error; aggregate pipelines should fail the dataset.

### 8. [P1] `compare_releases` still accepts incomparable experiments

**Files:** `TEST_PLAN.md:3-8,25-29`;
`analysis/compare_releases.py:170-212,231-262`.

The test plan requires identical symbols, periods, data, costs, and broker
settings. The implementation checks only symbol sets. Broker and date values
are unverified caller assertions; modelling mode, timeframe, costs, spread,
slippage, set file, and data identity comparability are not represented or
checked. A same-symbol January-2026 baseline and January-2025 candidate were
accepted. One singular `ea_version`/`data_source` value is also insufficient to
identify two releases. Require two complete experiment manifests and reject
any non-approved mismatch before calculating a release comparison.

The replacement Newcombe-Wilson interval for the win-rate difference was
independently recomputed and is correct; that correction is resolved.

### 9. [P1] Required provenance is still unavailable or optional for normal outputs

**Files:** `00_MASTER_PROMPT_FOR_CLAUDE.md:54-58`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:63-75,176-187,595-599`;
`analysis/report_metadata.py:168-251`; all analysis CLI parsers/output sites.

`ea_version`, `data_source`, and pipeline version are real improvements, but
the acceptance criterion remains unmet:

- spread and slippage have no distinct fields; only optional `costs_note`
  exists;
- all caller-supplied provenance fields remain optional;
- only `analyse_baseline` and `compare_releases` expose the two new fields;
- most CLIs expose only symbol and/or seed, with no timeframe, period,
  modelling mode, costs, set file, broker, or data-source inputs;
- CSV outputs have no mandatory metadata sidecar;
- `pattern_validation.py` emits an entirely unprovenanced CSV;
- `parameter_stability.py` hand-builds incomplete metadata without a dataset
  hash, timezone, or pipeline version;
- `join_trade_journal` places provenance only in memory or its optional error
  report, not alongside its normal CSV/JSON data outputs.

The task itself discloses part of this gap while claiming all findings are
resolved. Make required fields expressible and validated where applicable, and
emit a mandatory manifest alongside every persisted result.

### 10. [P1] Hashing and output guards still cannot guarantee evidence identity

**Files:** `analysis/csv_io.py:62-76`;
`analysis/report_metadata.py:90-165`;
`analysis/join_trade_journal.py:80-140,146-168`;
`analysis/join_news_events.py:121-156,190-241`; all direct `to_csv()` sites.

Hash-before-parse is not a snapshot. A probe changed a journal after metadata
hashing but before parsing; the result analyzed the new record while retaining
the old hash. Other pipelines parse first and hash later, leaving the inverse
race. Hash and parse the same captured bytes/staged immutable files and verify
the source set did not change before publishing.

Path guards compare only `Path.resolve()`. An output path that is a hard link to
an existing input has a different resolved name and passes. A direct
`analyse_baseline` probe then overwrote the underlying input inode. Use
`samefile`/file identity checks for existing paths in addition to normalized
path checks.

JSON writes are now atomic, which is confirmed. Every CSV writer remains a
direct `to_csv(path)` operation, however, so interruption can leave a partial
artifact. Use the same temp-file-and-replace discipline for CSV output.

### 11. [P1] Journal/news/CSV validation still admits duplicate or corrupt evidence

**Files:** `analysis/csv_io.py:26-59`;
`analysis/schema.py:63-91,147-168`;
`data_collection/journal_reader.py:108-192,195-303`;
`analysis/join_news_events.py:55-98,142-250,268-293`;
`NewsManager.mqh:55-70`.

- `join_news_events` never runs the journal duplicate detectors. Two identical
  valid decisions were counted twice and the CLI returned 0, allowing biased
  blackout counts.
- Duplicate CSV-header detection reads only the first physical line. A quoted
  multiline duplicate header bypassed the check and pandas silently mangled
  the second name.
- `parse_constant` rejects literal `NaN`/`Infinity`, but JSON `1e400` parses as
  `inf` without using that hook. Because nested `score_breakdown` is
  unconstrained, the record validated, was written as `{'overflow': inf}` to
  CSV, and the CLI returned 0.
- News importance is hard-limited to `{0,1,2,3}` even though the provider-neutral
  MQL contract says it is mapped to whatever ordinal scale a provider uses.
  Python booleans are also admitted as 0/1. Either declare/normalize an MT5-only
  schema or validate a genuine provider-neutral integer contract.
- Row-level invalid-journal details are persisted only if the caller happens to
  request optional `errors_json`. Otherwise an all-invalid run may write an
  empty CSV, exit nonzero, and retain no reviewable error artifact.

The streaming reader is improved, but an arbitrarily large physical line must
still be materialized before truncation, validation errors retain the full raw
record, and there is no file-count/byte/error-payload budget. Add bounded
record/file sizes as defense in depth.

### 12. [P1] Spreadsheet-formula protection covers only two of the affected CSV exporters

**Files:** `analysis/csv_io.py:210-230`;
`analysis/analyse_baseline.py:193-195`;
`analysis/analyse_giveback.py:174-191`;
`analysis/calculate_mfe_mae.py:146-161`;
`analysis/performance_breakdown.py:114-142,176-178`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:592-594`.

`sanitize_for_csv` is used only by the two join scripts. The new performance
pipeline writes caller/journal-derived dimension values directly; a strategy of
`=1+1` was emitted unchanged. Baseline re-exports all original strings, while
giveback and MFE/MAE export caller-controlled `trade_id` directly. Apply one
safe, atomic CSV serializer to every text-bearing report, not only files whose
immediate producer is named “journal.”

### 13. [P1] The numbered follow-up ledger still has closure gaps and a leakage instruction

**Files:** `00_MASTER_PROMPT_FOR_CLAUDE.md:424-432,747-757`;
`TASK-016_MARKET_REGIME_ENGINE.md:71-77`;
`TASK-031_REGIME_VALIDATION_COMPLETION.md:5-17,57-81,115-125`;
`TASK-032_SCORE_CORRELATION_ANALYSIS.md:37-54,66-78`;
`TASK-033_PATTERN_VALIDATION_COMPLETION.md:72-101`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:49-88`;
`TASK-037_MT5_EXPORT_BRIDGE.md:41-57,99-113`;
`TASK-038_WALK_FORWARD_OPTIMIZATION.md:38-57`.

- TASK-031 omits the required regime transition-history buffer.
- TASK-037's acceptance criteria require a real independently labelled regime
  dataset/confusion run, but its specification defines no required feature/
  price export or labelling protocol. It also exports only candlestick detector
  results although TASK-033 defers both candlestick and chart-pattern real
  cross-checks to it.
- TASK-032 may finish after documenting absent score components, but neither
  TASK-036 nor TASK-037 owns populating/exporting those components. Real
  correlation remains blocked with no closure owner.
- TASK-038 gives “maximize **test-window** expectancy” as the parameter-selection
  objective immediately before requiring train-only selection. That example
  instructs the exact leakage its rejection criteria prohibit; it must say
  train-window expectancy.

Numbered files are not sufficient if their specifications cannot deliver their
own acceptance criteria.

### 14. [P2] The corrected candlestick count did not propagate through the package

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/CandlestickPatternEngine.mqh:141-473`;
`analysis/pattern_validation.py:1-13`;
`notebooks/09_pattern_detector_validation.ipynb:122-124`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:371-375,437-441,502-514`;
`TASK-033_PATTERN_VALIDATION_COMPLETION.md:9-26,54-64`.

Direct source enumeration finds 19 `CP_Is*Array` predicates plus the
`CP_DetectHaramiArray` helper. Four predicates are ported, so 15 predicates plus
the helper remain. TASK-033's Objective and TASKS now state that correctly, but
the files above still claim 18 total/14 remaining; `pattern_validation.py` even
lists 15 names after saying 14. This directly contradicts `fd07473`'s commit
message that the count was fixed.

### 15. [P2] Two persisted metric names still overstate or obscure their semantics

**Files:** `analysis/analyse_giveback.py:204-240`;
`analysis/monte_carlo.py:77-104,227-233`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:563-565`.

Giveback filters to triggered trades and then calls the conditional result
`guard_helped_rate`; one helpful trigger among 100 total trades is reported as
100%, not 1%. Name it `guard_helped_rate_when_triggered` and/or also report the
full-cohort policy rate.

Monte Carlo's prose/notebook correctly says the bootstrap quantiles are
fixed-cash i.i.d. **scenario bounds**, not future-performance confidence
intervals. The JSON dataclass still persists them as `*_ci_lower/upper` and
contains no bound type/model/caveat, so a reviewer of the required machine
artifact sees the old semantics. Rename the fields or serialize the model and
bound semantics with them. The ruin Wilson interval itself is correctly a
finite-simulation-error interval.

### 16. [P2] The documented install environment is still not the one the task tells a clean reviewer to install

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:161-175`;
`requirements.txt:1-51`;
`03_SOURCE_CODE/Python/requirements-lock.txt`;
`03_SOURCE_CODE/Python/pyproject.toml:1-38`.

The new lock matches the venv used here, and Ruff/mypy are now genuinely
declared. However, the advertised direct install file still contains twelve
expressly untested lower-bound dependencies absent from that lock, and no
documented clean-install command uses the lock. The task also requires exact
formatter/linter/type-check/test versions and results, but no formatter is
declared or run. Make one authoritative install path reproduce the proved
environment and either run/record a formatter or explicitly amend the test
requirement.

### 17. [P2] Canonical history and task registration remain stale or contradictory

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:320-338,402-424,473-485`;
`09_HANDOVERS/claude_to_codex/TASK-028_handover.md:182-228`;
`TASKS.md:38-44`;
`TASK-024_STRATEGY_ROUTER.md:35-76`;
`TASK-032_SCORE_CORRELATION_ANALYSIS.md:3-35`;
`TASK-034_LIVE_SAFETY_WIRING.md:3-18,164-169`;
`TASK-035_ML_SIGNAL_MODEL.md:3-14,178-183`.

- TASK-028, TASKS, and the handover pre-declare all 31 earlier findings
  “resolved” before this independent pass. Use “remediation applied; pending
  independent review” until approval.
- The notebook map still lists notebook 03 only with `regime_validation.py` and
  notebook 04 only with `join_news_events.py`, although both now also call
  `performance_breakdown.py`.
- Score-correlation is repeatedly attributed to TASK-024, but that task never
  deferred correlation; it deferred three missing score components. The actual
  correlation requirement is master-prompt lines 747-757.
- `fd07473` newly tracks TASK-034 and TASK-035, but TASKS skips both. TASK-035
  nevertheless says it is registered. TASK-034 says three tested standalone
  pieces exist and then says two of them have no module; TASK-035 calls cooldown
  already-built infrastructure while TASK-034 says no cooldown module exists.

The durable “19+ commits” wording is consistent with current Git history and
does not need correction.

## Corrections independently confirmed

The following prior findings are genuinely improved or resolved:

- walk-forward now starts at the earliest entry and validates finite profit;
- baseline/release comparison use strict UTC parsing and reject invalid stop
  geometry;
- same-timestamp baseline balance changes are aggregated deterministically;
- starting balance, drawdown curves, optional exit price, and primary numeric
  CSV columns receive stronger finite checks;
- header-only trade inputs fail in giveback/MFE analysis;
- generic bootstrap confidence/resample validation for n >= 2 is present;
- the Newcombe-Wilson win-rate-difference interval is correct and nondegenerate
  at all-win/all-loss boundaries;
- Monte Carlo now has a minimum trade count, finite-input checks, and accurate
  fixed-cash/i.i.d. caveats in prose and notebook presentation;
- ordinary same-path/output-output collisions are rejected;
- JSON writes are atomic;
- single-line duplicate headers, blank IDs, duplicate JSON keys, standard
  non-finite JSON constants, and full OHLC geometry receive visible checks;
- journal reading is incremental by line, parse-error text is capped, and
  source labels are portable;
- current-EA journal incompatibility is accurately documented and assigned to
  TASK-036;
- strategy/regime grouping and full-path-set parameter sweep arithmetic are
  real and match their synthetic hand calculations;
- all declared test, lint, type-check, and notebook-execution commands are
  reproducibly green in the existing environment;
- both baseline evidence trees remain immutable relative to their tags.

## Required disposition

**CHANGES REQUESTED.** Do not merge or mark TASK-028 complete at `fd07473`.
Resolve every P0/P1 finding, add regression tests for the counterexamples above,
make the follow-up scopes executable rather than circular, correct the canonical
history/count claims, and request another independent review. P2 items should
also be corrected before closure because several are explicit claims that this
commit says are already resolved.
