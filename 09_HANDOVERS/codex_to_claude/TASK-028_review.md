# Codex Independent Code Review - TASK-028 Python/Jupyter Statistical Laboratory

**DISPOSITION: CHANGES REQUESTED**

TASK-028 at `c775a6ecc139b88ccf43bd51e32dbaec24848432` is not ready to
close or merge. The nine post-review remediation commits contain several real
fixes, and the committed suite, linter, and all notebooks run successfully.
However, green execution still masks acceptance-criteria gaps and substantive
data/statistical correctness defects. In several cases the new tests canonize
the defective behavior instead of detecting it.

The highest-level blockers are:

- required session, strategy/regime, parameter-stability, and genuine
  walk-forward work still lacks paired reproducible pipelines, or has been
  explicitly scoped down without a complete numbered owner;
- invalid timestamps, missing P/L, invalid initial-risk geometry, tiny samples,
  and non-finite values can still become plausible statistics;
- release-comparison and Monte Carlo intervals remain misleading in important
  boundary/tiny-sample cases; and
- journal outputs can silently omit all invalid EA records, overwrite evidence,
  or carry a hash of bytes different from those actually analyzed.

## Review target and independent evidence

- Branch: `claude/task-028-python-statistical-lab`.
- Reviewed HEAD: `c775a6ecc139b88ccf43bd51e32dbaec24848432`.
- Original review target: `c4c80dabc82f6f538a5219eca57b9174989c1f2b`.
- Remediation range: nine commits, `3c164f3..c775a6e`, after the review commit
  `8fed279` (43 changed paths relative to `c4c80da`).
- Full independent test rerun: **262 passed** (`pytest -q`).
- Independent lint rerun: **Ruff passed with zero findings**.
- Independent clean execution: all 11 committed notebooks (the ten required
  notebooks plus `00_journal_pipeline_demo.ipynb`) exited 0 through the
  registered `themba-python-lab` kernel. Temporary execution copies were
  removed.
- Direct adversarial probes independently reproduced, among other issues:
  naive timestamps accepted by `analyse_baseline`; the first walk-forward
  trade discarded and a missing `profit` counted as a loss; one historical
  trade producing a zero-width Monte Carlo interval; and an all-loss versus
  all-win sample producing a bootstrap win-rate difference interval of
  `[1.0, 1.0]`.
- `HEAD:01_BASELINE/EA_V637` and
  `baseline-v637:01_BASELINE/EA_V637` remain the same Git tree,
  `fe46191174b150c4c1e0dceb1bffc6c42a076384`. The corresponding V8.11 trees
  remain `3bc9e68939873de57c70319ff75f3b39ffd58c75`.
- No path under `01_BASELINE/` or `03_SOURCE_CODE/MQL5/` changed in the
  remediation range.
- The pre-existing untracked `.claude/` was left untouched. An unrelated
  untracked `TASK-034_LIVE_SAFETY_WIRING.md` appeared during review; it is not
  part of reviewed HEAD and is not counted as a TASK-028 follow-up. No commit
  was made.

Line references below are to `c775a6e`.

## Findings

### 1. [P0] Required analyses still do not satisfy the paired-pipeline contract

**Files:** `00_MASTER_PROMPT_FOR_CLAUDE.md:158-180,1125-1154`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:63-79,81-124,161-188,395-415,464-471`;
`notebooks/03_strategy_regime_analysis.ipynb:10-19,96-128`;
`notebooks/04_session_and_news_analysis.ipynb:10-21,93-145`;
`notebooks/06_parameter_stability.ipynb:10-20,48-96`;
`analysis/walk_forward.py:13-21`; `notebooks/07_walk_forward_analysis.ipynb:10-22`.

The remediation added content to the previously filename-only notebooks, but
the named analysis is still not implemented in a paired `.py` pipeline:

- Notebook 03 calls a DataFrame containing only `trade_id`, `regime`, and
  `profit` “strategy-performance analysis,” but groups only by regime and has
  no strategy/setup dimension.
- Notebook 04 explicitly says there is no session pipeline. It defines a
  made-up fixed UTC-hour `session_for_hour` function and aggregation inside the
  notebook rather than using or porting the broker-session logic. This is a
  demonstration, not the required reproducible session analysis.
- Notebook 06 implements its complete parameter grid and aggregation inline;
  `exit_simulation.py` only exposes guard predicates/path simulation. The
  resulting table is not emitted as CSV/JSON, has no corresponding pipeline
  test, and compares `mean_r_diff_when_triggered` over different selected
  subsets because non-triggered paths are omitted. Its sole assertion checks
  only a trigger-count ordering, not the hand-computable table values.
- `walk_forward.py` now accurately admits that it performs descriptive rolling
  windows and does not select on training data then freeze/evaluate on test
  data. Honest scoping is good, but it does not fulfill the still-present
  “walk-forward evaluation” deliverable and no numbered follow-up owns that
  missing harness.

The master prompt also calls for performance by strategy, setup, regime,
session, symbol, direction, hour, day, and news window. The current package
does not provide that complete analysis. Therefore the task-file statement
that every notebook is paired to a script containing its actual logic is
false. Either implement these pipelines and reviewable outputs or explicitly
move each remaining deliverable to a complete numbered task.

### 2. [P0] The numbered follow-ups do not fully own the deferred scope and contain closure loopholes

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:114-124,176-188,420-444,488-505`;
`TASK-031_REGIME_VALIDATION_COMPLETION.md:3-9,47-64,88-109`;
`TASK-033_PATTERN_VALIDATION_COMPLETION.md:3-18,44-57,84-102`;
`TASKS.md:38-41`; `analysis/pattern_validation.py:1-27`;
`data_collection/journal_reader.py:21-31`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/CandlestickPatternEngine.mqh:141-473`.

Creating TASK-031/032/033 is real progress, but it does not completely satisfy
the original acceptance criterion:

- TASK-028 requires regime data-failure coverage as well as nine states,
  gates, and hysteresis. TASK-031 omits data-failure behavior.
- TASK-031's objective promises a confusion matrix against real independently
  labelled evidence, but its test/acceptance text permits that run to remain
  `PENDING` and still close the task.
- TASK-033 similarly requires a real MQL5 detector export in its objective and
  specification but allows its acceptance criterion to pass with the export
  still `PENDING`. A completion task must either require the evidence or split
  the blocked evidence-production prerequisite into another numbered task.
- Durable signal/order/deal identity joins from TASK-028 remain unimplemented.
  There is no `order_id` or `deal_id` field anywhere in the Python sources,
  and no numbered follow-up owns the end-to-end journal identity/population
  gap.
- The journal reader says the producer's `FILE_ANSI` versus reader UTF-8
  mismatch is in a numbered future follow-up, but none of TASK-031/032/033
  owns it.
- The claimed pattern count is source-factually wrong. The MQL5 source has 19
  `CP_Is*Array` predicates plus `CP_DetectHaramiArray`. With four predicates
  ported, “remaining 14 of 18” is unsupported: 15 `CP_Is*` predicates remain,
  or 16 detector/predicate functions if the harami detector is counted. The
  follow-up must define its counting convention and cover the actual source
  surface.

The prose-only MT5 trade-export bridge and current EA journal-population gap
also remain unnumbered. Those gaps make real-data execution impossible and
must have explicit owners rather than living indefinitely under “genuinely
still remaining.”

### 3. [P1] Walk-forward partitioning permanently drops real trades and treats missing P/L as losses

**Files:** `analysis/walk_forward.py:61,108-144,167-186`;
`tests/test_walk_forward.py:65-72,148-180`.

Window zero is anchored at the earliest **exit** time, while `_slice_window`
requires both entry and exit to be at or after the window start. Every
positive-duration trade with the earliest exit necessarily entered before
that anchor, so it can never appear in any window. The test suite explicitly
calls this “correct purged behavior,” but it is not a train/test-boundary
crossing; the overall analysis period should start at the earliest eligible
entry (or another deliberately defined earlier boundary).

In addition, `NUMERIC_COLUMNS` omits `profit`. A missing/NaN profit reaches
`profit > 0`, where pandas returns `False`, silently converting unknown P/L
into a loss. A direct three-row probe returned `train_n=1` and
`train_win_rate=0.0`: the legitimate earliest trade was discarded and the
remaining NaN-profit row was counted as a loss. Both behaviors violate the
visible-failure rule.

### 4. [P1] Timestamp and event-order integrity is still inconsistent

**Files:** `analysis/time_utils.py:105-140`;
`analysis/analyse_baseline.py:95-113`;
`analysis/compare_releases.py:55-78`.

The new `parse_utc_series` correctly rejects naive/non-UTC timestamps, but
`analyse_baseline` still calls `pd.to_datetime(..., utc=True)`, which silently
assumes naive strings are UTC. A direct probe with no `Z` or offset was
accepted as one valid trade. `compare_releases` does not parse or validate its
entry/exit timestamps at all.

`analyse_baseline` also sorts only by `exit_time`. When multiple trades share
the same timestamp, the schema supplies no durable intra-timestamp deal
sequence. Reversing two same-time win/loss rows changed independently observed
max drawdown from 10.0% to approximately 9.09% with identical timestamps and
net P/L. Require a durable deal sequence/high-resolution time, or aggregate
same-instant balance changes before computing drawdown.

### 5. [P1] Invalid numeric/risk inputs still become plausible analytical results

**Files:** `analysis/trade_math.py:17-27`;
`analysis/analyse_baseline.py:87-122`;
`analysis/walk_forward.py:167-182`;
`analysis/compare_releases.py:55-78,93-146`;
`analysis/calculate_mfe_mae.py:88-123`;
`analysis/analyse_giveback.py:94-161`;
`analysis/metrics.py:136-151,184-220,233-285`;
`analysis/monte_carlo.py:68-117`.

`compute_r_multiple` faithfully mirrors the MQL live fail-safe by returning
0R for zero/wrong-side stop distance. That behavior is appropriate for a live
fail-safe, but not for evidence cleaning: a long trade with entry 100 and
initial stop 101 is malformed and must be rejected, not reported as plausible
0R. Baseline, walk-forward, release-comparison, MFE/MAE, and giveback pipelines
validate finiteness but not initial-stop side/distance before calling it.

Other counterexamples remain:

- `starting_balance=NaN` passes `starting_balance <= 0`, yielding NaN final
  balance with a plausible 0 drawdown in memory;
- `compute_max_drawdown` silently ignores later NaN values;
- direct `run_monte_carlo([NaN], ...)`, NaN/inf starting balance, or NaN ruin
  threshold can return meaningless results;
- `two_sample_bootstrap_diff` and the generic bootstrap accept non-finite
  arrays;
- optional giveback `exit_price` is not validated when populated, so infinity
  can reach `actual_final_r`; and
- header-only trade inputs in `calculate_mfe_mae` and `analyse_giveback` return
  successful zero-result/zero-error runs instead of a visible insufficient-
  sample failure.

`allow_nan=False` on some optional JSON outputs is not enough: callers may use
the in-memory result or CSV path, and a late serialization exception is not a
schema diagnosis.

### 6. [P1] Statistical uncertainty remains incomplete, and the generic bootstrap accepts indefensible settings

**Files:** `analysis/metrics.py:1-9,25-83,136-229`;
`analysis/analyse_baseline.py:118-150`;
`analysis/walk_forward.py:63-68,108-131`;
`analysis/analyse_giveback.py:172-197`.

The module-level statement that every function returns sample size and
uncertainty is false. Expectancy reports sample dispersion, not uncertainty
of the mean; with one observation it reports `std_dev=0.0`, even though spread
is unestimable. Profit factor and drawdown expose no inferential uncertainty,
walk-forward omits train win-rate intervals and all expectancy intervals, and
giveback's mean R difference has no interval.

`bootstrap_confidence_interval` validates neither `confidence` nor a defensible
minimum resample count and does not reject non-finite data. Independent probes
accepted confidence 0 and 1 with one resample and returned a degenerate
interval. Add finite-data checks, explicit confidence/resample validation, and
appropriate uncertainty for every reported statistical claim.

### 7. [P1] Monte Carlo output overstates what tiny i.i.d. resampling can establish

**Files:** `analysis/monte_carlo.py:1-27,45-145`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:357-363`;
`notebooks/08_monte_carlo_risk.ipynb:48-67`.

The fixed-cash/balance clarification is correct, but three material problems
remain:

1. Individual trades are sampled **with replacement**. This is an i.i.d.
   empirical bootstrap, not merely reordering the historical sequence. It
   destroys streak/autocorrelation, day-level caps, and cooldown structure,
   yet the module no longer carries the i.i.d./autocorrelation caveat the task
   file says is explicitly documented.
2. There is no minimum underlying trade sample. One historical trade can be
   resampled 2,000 times into an apparently precise interval. A direct probe
   with `[10.0]` returned final-balance bounds `[1010.0, 1010.0]` and drawdown
   bounds `[0.0, 0.0]`; more simulations cannot manufacture sample
   information.
3. `final_balance_ci_*` and `max_drawdown_pct_ci_*` are percentile scenario
   bounds conditional on the empirical i.i.d. model, not conventional
   confidence intervals for future balance/drawdown. The notebook presents
   them as “95% CI.” The ruin Wilson interval measures finite-simulation error,
   not uncertainty in the tiny historical distribution/model.

Use terminology matching the quantity, enforce sample adequacy, and either
preserve/block-resample dependence or state prominently that the tool cannot
support streak-sensitive ruin conclusions.

### 8. [P1] Release comparison neither enforces comparable experiments nor gives a valid boundary win-rate interval

**Files:** `TEST_PLAN.md:3-8,25-29`;
`analysis/compare_releases.py:50-78,93-205`;
`notebooks/10_baseline_vs_candidate.ipynb:45-66`.

The observed-difference fix and minimum group/resample checks are real.
However, default `symbol=None` permits different symbols, and the pipeline has
no inputs/checks for identical periods, broker, data, costs, modelling mode,
or set file. It accepted an EURUSD January-2026 baseline versus an XAUUSD
January-2025 candidate. Such a CI answers the wrong question regardless of its
arithmetic.

For binary win rate, resampling empirical 0/1 values collapses at boundary
samples. Ten all-loss baseline trades versus ten all-win candidate trades
always returns `[1.0, 1.0]`; two all-loss groups return `[0.0, 0.0]`. Those are
not defensible sampling-uncertainty intervals for proportions. Use an
appropriate difference-of-proportions interval/test (for example a
Wilson/Newcombe-family method) and reserve the continuous bootstrap for R
expectancy with adequacy/finite-data checks.

### 9. [P1] MFE/MAE and giveback still have unresolved bar-boundary contamination

**Files:** `analysis/calculate_mfe_mae.py:1-19,88-123`;
`analysis/trade_math.py:46-90`;
`analysis/analyse_giveback.py:10-22,94-143`.

The scripts never define whether a bar timestamp is its open or close time and
do not require entry/exit to align with bar boundaries. MFE/MAE includes the
entire high/low of any bar whose single timestamp lies in inclusive
`[entry_time, exit_time]`. The entry bar can therefore include pre-entry
extrema and the exit bar can include post-exit extrema (or valid boundary bars
can be omitted under the opposite timestamp convention). This is look-ahead/
measurement contamination, not merely a small approximation.

Giveback clearly labels close-only data as a tick-model simplification, but it
has the same undefined timestamp-boundary issue. Require tick/sub-bar data or a
declared convention plus alignment rejection/partial-bar policy. Header-only
success and unvalidated optional exit prices from finding 5 must be corrected
at the same boundary.

### 10. [P1] `join_news_events` can turn a wholly invalid real journal into a successful empty analysis

**Files:** `analysis/join_news_events.py:84-105,118-160,177-200`;
`data_collection/journal_reader.py:151-219`;
`analysis/schema.py:17-28`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:451-492`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh:68-97`.

`join_news_events` reads only `valid_records`, silently excluding parse/schema
failures from its joined output. Error counts exist only in the optional
summary, no row-level errors are emitted, and `main()` returns 0 regardless of
those errors.

This is immediately reachable: `DJ_NewDecision` initializes `signal_id`,
`market_family`, `intraday_mode`, and `news_state` empty; the live EA sets none
of those four fields before appending. The strict Python schema rejects the
empty market/mode values. A real current-EA journal can therefore produce a
successful empty CSV rather than visibly failing the analysis. Make invalid
input affect the returned/CLI disposition and provide a mandatory reviewable
error artifact. `join_trade_journal` now does this more honestly; its news
consumer must not discard that signal.

### 11. [P1] Output aliasing and non-snapshot hashing can overwrite evidence or misidentify the analyzed bytes

**Files:** `analysis/analyse_baseline.py:91-93,153-163`;
`analysis/analyse_giveback.py:90-92,163-197`;
`analysis/calculate_mfe_mae.py:84-86,124-155`;
`analysis/walk_forward.py:163-165,222-249`;
`analysis/join_news_events.py:93-104,122-153`;
`analysis/join_trade_journal.py:78-96,126-180`;
`analysis/pattern_validation.py:303-332`;
`analysis/report_metadata.py:142-159`;
`data_collection/journal_reader.py:90-148,182-218`.

Most two-output pipelines compare each output only with inputs, not with the
other output. Passing the same path for CSV and JSON is accepted, and the later
write replaces the earlier artifact. `pattern_validation` has no input/output
collision guard at all.

More seriously, `join_trade_journal` checks output paths only against the
input directory, not against its actual `decisions_*.jsonl` files. A direct
probe used a journal source file as `output_csv` and overwrote the source
evidence. `join_news_events` can write an output named
`decisions_generated.jsonl` inside the journal directory, then include that
derived output as an input in its own dataset hash.

Both journal pipelines parse first and hash later. A concurrent append or
completion of a torn final line can therefore make the result rows describe
one byte snapshot while metadata hashes another. Snapshot/hash before parse
and verify unchanged afterward, or copy to an immutable staging snapshot.
The provided `atomic_write_text` helper is unused; every output is still a
direct potentially partial write.

### 12. [P1] Required result provenance is still unavailable or optional in normal CLI use

**Files:** `00_MASTER_PROMPT_FOR_CLAUDE.md:45-58`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:63-79,176-187`;
`analysis/report_metadata.py:23-26,162-235`; all pipeline `run()` calls and
CLI parsers under `analysis/`.

The master requirement identifies EA version, Git commit, symbol, broker,
timeframe, date range, modelling mode, spread, slippage, set file, and data
source for every result. `ReportMetadata` has no EA-version or data-source
field and only a generic `costs_note`; normal pipeline calls pass at most
symbol/broker/seed. CLI parsers do not expose the remaining provenance, so the
new optional fields serialize as null even when those facts are essential.
CSV outputs have no mandatory metadata sidecar at all.

`PIPELINE_VERSION` also remains `0.1.0` despite remediation changing output
shapes and field semantics, directly contrary to its own “bump when output
shape changes” comment. Provenance fields must be available, required where
applicable, and emitted alongside every CSV/JSON result rather than only when
the caller happens to request an optional summary.

### 13. [P1] CSV/JSON validation remains permissive in ways that corrupt joins and pattern results

**Files:** `analysis/csv_io.py:25-94`;
`data_collection/journal_reader.py:120-146`;
`analysis/join_news_events.py:100-107`;
`analysis/pattern_validation.py:303-327`.

The shared checks still miss several structural failures:

- pandas mangles duplicate CSV header names before the required-column set
  check, so duplicate headers are silently accepted;
- `assert_unique_ids` deliberately removes null IDs, so a blank `event_id` or
  `trade_id` passes. A blank news event ID was later emitted as the string
  `"nan"`;
- JSON duplicate keys use `json.loads` last-value-wins semantics. A record
  containing two `score` keys produced one valid record and zero parse errors;
- news `importance` is only finite-checked, not required to match the MQL
  integer field; and
- OHLC validation checks only `high >= low`, not `low <= open,close <= high`.

These are evidence-schema failures and must fail visibly before any join,
pattern predicate, or statistic runs.

### 14. [P2] Journal resource, encoding, privacy, and spreadsheet-safety controls remain incomplete

**Files:** `data_collection/journal_reader.py:21-31,44-60,90-148,151-219`;
`analysis/join_trade_journal.py:126-180`;
`analysis/join_news_events.py:118-124`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh:205`.

The new `max_records` limit is checked only after `_read_lines_from_file`
calls `readlines()` and parses the whole file. A single huge file/line (or
large blank-line payload) can exhaust memory before the limit is consulted,
and error objects retain complete hostile raw lines. Stream and count with
explicit byte/line/error-payload bounds.

The reader still decodes UTF-8 while the producer writes `FILE_ANSI`. That
known cross-language contract mismatch has no tracked owner (finding 2).
Error artifacts also retain absolute source paths despite the portable
metadata work. Finally, caller-controlled journal strings are written directly
to CSV; formula-prefixed values can become spreadsheet formulas when a reviewer
opens the artifact. Apply a documented spreadsheet-safe export policy or make
the hazard explicit and provide a safe review format.

### 15. [P2] The declared environment is not the environment actually proven by the review evidence

**Files:** `requirements.txt:1-41`; `03_SOURCE_CODE/Python/pyproject.toml:1-23`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:161-174,473-486`.

Pinning the four core libraries, pytest, and notebook tools is an improvement,
but `requirements.txt` explicitly admits it is not a resolved transitive lock
and includes many untested lower-bound dependencies absent from the tested
environment. Ruff 0.15.22 is installed and used for the claimed gate but is
not declared. No type checker/version/result is declared despite the task test
plan requiring exact formatter/linter/type-check/test evidence. Python is only
lower-bounded (`>=3.11`) while the evidence is from 3.13.14.

A clean `pip install -r requirements.txt` therefore does not reconstruct the
proven environment. Commit a tested lock/constraints mechanism (or reduce the
requirements to what this task actually imports), declare all quality tools,
and record the exact clean-environment command/results.

### 16. [P2] Task, handover, notebook, and history claims are stale or contradictory

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:320-338,377-389,395-415,473-507`;
`TASKS.md:38-41`;
`09_HANDOVERS/claude_to_codex/TASK-028_handover.md:1-23,112-128,169-174`;
`notebooks/03_strategy_regime_analysis.ipynb:10-19`.

Examples:

- The task's Commit entry says nine commits ending `fffa9ad`; Git shows 18
  TASK-028 commits from registration through current HEAD.
- The task and `TASKS.md` say eight remediation commits; Git shows nine.
- The Reviewer field still says a full review was unavailable even though
  review commit `8fed279` exists.
- The task maps notebook 06 to `walk_forward.py`, while the notebook now calls
  itself paired to `exit_simulation.py`.
- Earlier task text still says the bonus regime module “closes” the deferred
  item, while the corrected later section says it does not.
- Notebook 03 still says the seven-state formula closes TASK-016's deferred
  confusion-matrix work.
- The handover still claims closure, 196 tests, and pre-remediation scope.

Update the canonical history once, with durable commit references and a clear
distinction between what was implemented, what was reviewed, and what remains
pending. Do not describe all findings as resolved until an independent rerun
actually confirms that disposition.

## Corrections independently confirmed

The following remediation work is real and should be preserved:

- absolute and percentage maximum drawdowns are now selected independently;
- baseline/Monte Carlo output is correctly labelled as closed-trade balance,
  not mark-to-market equity, with a positive starting balance;
- Botswana/server conversion now preserves the instant via `astimezone`, and
  the strict UTC-series helper works at the call sites that actually use it;
- schema validation now rejects non-string timestamps, extra fields, empty
  pattern strings, and several non-finite numeric cases;
- pattern comparison now rejects duplicate/disjoint keys rather than silently
  passing an inner merge;
- release comparison now reports the observed data difference and enforces a
  basic minimum group/resample count;
- the walk-forward no-window crash, NaN summary serialization, and true
  train/test-boundary spanning-trade leakage were fixed;
- giveback R-difference sign remains correct, and the four Python candlestick
  predicates, both giveback predicates, `EM_ComputeR`, and the scoped
  seven-state regime-selection formula match their current MQL5 counterparts;
- report Git-root discovery no longer defaults to an unrelated process CWD;
  no `shell=True`, Python live-order path, credential, or baseline mutation was
  found.

These fixes are substantial, but they do not resolve the findings above.

## Required disposition

**CHANGES REQUESTED.** Keep TASK-028 open. Correct the sixteen findings,
add regression tests for the counterexamples rather than tests that bless
them, execute all scripts/notebooks from a clean declared environment, and
request another independent review. TASK-028 should not be marked ready to
merge on `c775a6e`.
