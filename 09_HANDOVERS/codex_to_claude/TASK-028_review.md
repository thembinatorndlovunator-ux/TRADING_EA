# Codex Independent Code Review - TASK-028 Python/Jupyter Statistical Laboratory

**DISPOSITION: CHANGES REQUESTED**

The TASK-028 implementation at
`c4c80dabc82f6f538a5219eca57b9174989c1f2b` is not ready to close. The code is
substantial and all committed tests and notebooks execute, but the package
does not yet meet its own reproducibility contract or acceptance criteria.
Several analyses can silently accept malformed data or emit misleading risk
statistics, and three pieces that TASK-028 explicitly owns remain unfinished
without independently numbered follow-ups.

This is not a rejection of the useful foundation. The direct Python ports of
`EM_ComputeR`, both giveback predicates, the four implemented candlestick
predicates, and the stateless regime-selection formula agree with their MQL5
counterparts within their stated scopes. The current EA really does leave
`signal_id`, `market_family`, `intraday_mode`, and `news_state` at their empty
defaults, and the Python `Literal` fields really do reject empty
`market_family`/`intraday_mode`. No live-order call, credential, API key, or
`shell=True` use was found. Those positives do not cure the findings below.

## Review target and independent evidence

- Branch: `claude/task-028-python-statistical-lab`.
- Reviewed HEAD: `c4c80dabc82f6f538a5219eca57b9174989c1f2b`.
- TASK-028 implementation range: `130d982..c4c80da` (57 changed paths;
  TASK-028 itself begins at `e37bbec`). No path under `01_BASELINE/` or
  `03_SOURCE_CODE/MQL5/` changed in that range.
- `HEAD:01_BASELINE/EA_V637` and
  `baseline-v637:01_BASELINE/EA_V637` are the same Git tree,
  `fe46191174b150c4c1e0dceb1bffc6c42a076384`. The corresponding V8.11 trees
  are both `3bc9e68939873de57c70319ff75f3b39ffd58c75`.
- Independent test rerun: **196 passed** (`pytest -q`).
- Independent notebook rerun: all ten required notebooks, 01 through 10,
  exited 0 through the registered `themba-python-lab` kernel. The generated
  execution copies were review-only temporary files and were removed.
- Additional adversarial probes were run without changing repository source.
  Among other results, they reproduced strict-schema coercion, non-finite
  acceptance, invalid timezone conversion, two drawdown failures, a
  no-window walk-forward crash, non-standard `NaN` JSON, a disjoint-key
  pattern comparison falsely reporting no differences, a one-resample false
  release significance result, and a journal glob escaping its directory.
- The pre-existing untracked `.claude/` directory was left untouched. No
  commit was made.

Line references below are to `c4c80da`.

## Findings

### 1. [P0] TASK-028's owned deferred work is neither complete nor split into numbered follow-ups

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:114-123,176-183,412-425,456-465`;
`TASKS.md:38`; `analysis/regime_validation.py:1-28`;
`analysis/pattern_validation.py:1-27`.

The task specification requires all nine regime states plus gating, failure,
and hysteresis fixtures; the score-component correlation audit; and
candlestick/chart-pattern validation. Acceptance permits incomplete work only
if it is split into **independently numbered follow-ups**. Current code and
the task's own final notes instead show:

- `regime_validation.py` covers seven stateless classifier outcomes, accepts
  structure agreement as caller input, and explicitly omits both gating
  regimes, data failure, hysteresis, and any independently labelled confusion
  matrix;
- no score-correlation implementation exists; and
- `pattern_validation.py` ports four of 18 candlestick predicates and no chart
  pattern.

No separately numbered tasks own these gaps. `TASKS.md:38` merely embeds them
inside TASK-028's status. The statement there and at task lines 461-462 that
`regime_validation.py` “closes” TASK-016's confusion-matrix item is therefore
false; the module says the opposite at lines 19-28. Either complete this work
or create concrete numbered tasks and update every completion/status claim.
The acknowledged MQL5 population gap likewise means every current real EA
journal row is rejected before analysis; that end-to-end blocker also needs a
numbered owner rather than remaining only a prose observation.

### 2. [P0] Several required notebooks exist by filename but do not implement the named analysis

**Files:** `notebooks/03_strategy_regime_analysis.ipynb:8-59`;
`notebooks/04_session_and_news_analysis.ipynb:8-79`;
`notebooks/06_parameter_stability.ipynb:8-77`;
`notebooks/07_walk_forward_analysis.ipynb:8-53`;
`notebooks/09_pattern_detector_validation.ipynb:8-66`.
**Requirements:** `00_MASTER_PROMPT_FOR_CLAUDE.md:169-180,1125-1154` and
`TEST_PLAN.md:9-23`.

Execution success is genuine, but content is not complete:

- notebook 03 says it demonstrates all seven computed regimes but constructs
  only trending-up, expansion-up, and compression, and performs no strategy
  performance analysis;
- notebook 04 performs one news-window join and no session analysis;
- notebook 06 varies rolling calendar windows, not strategy parameters, and
  produces no parameter grid or neighbouring-parameter stability map;
- notebook 07 imports only `generate_windows` and checks four date boundaries;
  it never runs a walk-forward evaluation or reports train/test performance;
- notebook 09 checks only bullish engulfing in a three-bar array. With its
  default `trend_lookback=5`, neither pin-bar predicate can even be evaluated,
  despite the fixture comment claiming an embedded bullish pin bar. It does
  not invoke the MQL5 comparison helper.

The master prompt also asks for performance by strategy, setup, regime,
session, symbol, direction, hour, day, and news window. No current pipeline
provides that analysis. Thin notebooks are desirable, but a thin wrapper must
still exercise a pipeline that performs the named work.

### 3. [P1] Percentage drawdown and “equity” risk statistics are not reliable

**Files:** `analysis/metrics.py:61-67,216-252`;
`analysis/analyse_baseline.py:1-3,46-52,84-112,136`;
`analysis/monte_carlo.py:58-64,89-100,127,163`;
`tests/test_analyse_baseline.py:86-102`.

`compute_max_drawdown` selects the event with the largest **absolute** decline
and returns that event's percentage. It does not select the largest percentage
drawdown. An independent check on `[100, 10, 60, 200, 100]` returned 50% from
the later 200-to-100 fall even though the earlier 100-to-10 drawdown is 90%.

Both public pipelines also default `starting_equity` to zero. On
`[0, -100, -50]`, the helper reports a 100-unit drawdown but 0%, because line
241 special-cases a zero peak to zero percent. A zero starting balance makes
percentage drawdown and ruin analysis undefined or trivially wrong. The
baseline test actively canonizes the problem by calling 20/40 a 50% account
drawdown even though 40 is accumulated profit, not account equity.

Finally, cumulative closed-trade P/L is a **balance** curve, not an equity
curve: it contains no mark-to-market open-position values. The code and output
call it equity and therefore cannot satisfy `TEST_PLAN.md`'s separate max
balance and max equity drawdown requirements. Require a positive account
starting value, report balance drawdown honestly, compute maximum absolute and
maximum percentage events independently, and reserve equity drawdown for an
actual time series of account equity.

Monte Carlo adds a second modelling mismatch: lines 82-95 resample fixed
historical cash `profit` and add it unchanged after reordering. This project
sizes risk as a percentage of changing equity, so reordered trades should have
different cash risk/P&L as the path compounds. Use R/percentage returns with
the stated sizing model, or explicitly limit the tool and its claims to
fixed-volume/fixed-cash systems. With the current zero default,
`ruin_threshold=0` is also hit at the initial curve point even for an all-win
path.

### 4. [P1] Time conversion changes the instant while retaining a UTC label, and CSV paths silently assume naive time is UTC

**Files:** `analysis/time_utils.py:30-43,60-77`;
`tests/test_time_utils.py:38-48`;
`analysis/analyse_baseline.py:75-76`;
`analysis/calculate_mfe_mae.py:80,89-90`;
`analysis/analyse_giveback.py:86,95-96`;
`analysis/join_news_events.py:97`;
`analysis/walk_forward.py:120`.

`to_botswana_time` and `to_server_time` add an offset to a UTC-aware datetime
but leave `tzinfo=UTC`. Thus `2026-01-01 12:00+00:00` becomes
`14:00+00:00`, a different instant, rather than `14:00+02:00`, the same
instant expressed in local time. The current tests verify the wrong semantic
by requiring the converted aware datetime to subtract as two hours from the
original; a real timezone conversion should preserve the instant.

Separately, every CSV pipeline uses `pd.to_datetime(..., utc=True)`. Pandas
interprets a naive timestamp as UTC, so a string such as
`2026-01-01T01:00:00` is silently accepted as `+00:00`. That directly
contradicts reproducibility rule 5 and `ensure_utc`'s stated refusal to guess.
Blank CSV timestamps can become `NaT` even with `errors="raise"` and then
silently fail comparisons rather than being reported missing.
This can shift trade windows, MFE/MAE bars, news joins, and walk-forward
partitions. Parse first, reject naive/non-UTC timestamps explicitly, then
convert with `astimezone` when a real offset is required.

### 5. [P1] The “strict” journal schema silently coerces wrong JSON types and accepts non-finite analytical values

**Files:** `analysis/schema.py:63-91,93-132`;
`data_collection/journal_reader.py:71-98`.

`extra="forbid"` does reject extra keys, but the model is not type-strict.
Independent calls showed all of these malformed values being accepted and
coerced: `score="50"`, `risk_percent="0.3"`, `targets=["2.5"]`,
`regime_confidence="50"`, and integer `timestamp_utc=0` (converted to the Unix
epoch even though the schema requires ISO-8601). The model also accepted
`risk_percent=NaN` and `targets=[NaN]`; finiteness is checked only for `entry`
and `stop`. Python's `json.loads` accepts non-standard `NaN`/`Infinity` tokens
unless `parse_constant` rejects them.

The pattern-field validator at lines 113-121 is also a no-op: its comment says
an empty string must be rejected because only JSON `null` is valid, but it
returns the empty string unchanged and Pydantic accepts it.

These values can contaminate every downstream mean, R statistic, comparison,
and JSON report while appearing schema-valid. Enable strict field validation,
reject non-finite values in every numeric scalar/list/mapping, require the
timestamp's actual serialized type, and reject non-standard JSON constants.

### 6. [P1] The general CSV input layer does not enforce the reproducibility contract's integrity rules

**Files:** `analysis/csv_io.py:18-29` and every CSV-consuming pipeline;
`TASK-028_PYTHON_STATISTICAL_LAB.md:74-75`.

`read_csv_with_required_columns` checks only that column names exist. It does
not detect duplicate trade/event/bar IDs, duplicate rows, duplicate column
headers, missing cells, non-finite numbers, invalid OHLC geometry, mixed
symbols, or impossible entry/stop/exit geometry. No trade-analysis pipeline
checks duplicate `trade_id`, even though the contract explicitly says
duplicates must be visible failures. `compute_r_multiple` then converts a stop
on the wrong side of entry to 0R, appropriate as the live MQL5 fail-safe but
not appropriate for an audit: malformed research data becomes a plausible
zero-R trade.

Define and enforce a per-input schema before calculation, including unique
durable IDs, finite numerics, valid timestamp ordering/timezones, valid OHLC,
and valid initial risk. Do not silently turn invalid analytical records into
ordinary observations.

### 7. [P1] Walk-forward summary generation is broken on normal empty windows and is not a walk-forward selection procedure

**Files:** `analysis/walk_forward.py:36-61,73-96,114-182`;
`tests/test_walk_forward.py:55-60,111-155`;
`notebooks/06_parameter_stability.ipynb:43-77`;
`notebooks/07_walk_forward_analysis.ipynb:42-53`.

Empty test windows are an expected, explicitly tested state. Pandas converts
their `None` expectancy values to `NaN`, but line 168 filters with
`r is not None`, which does not remove `NaN`. The task's own five-trade
fixture therefore writes `mean_test_expectancy_r: NaN` instead of the mean of
its valid windows; `json.dumps` emits that non-standard JSON token. If the
data span is shorter than the training window, `generate_windows` correctly
returns `[]`, but asking `run` for a summary then raises
`KeyError: 'test_expectancy_r'` because the empty result has no columns.

More fundamentally, this code computes descriptive metrics for fixed rolling
partitions. It never selects parameters on the train window and applies the
frozen choice to the test window, so it is not walk-forward optimization or
evaluation. It also partitions only by exit time and ignores overlapping
trades whose entries precede a test boundary, leaving a temporal-leakage
route. Define the train/selection/frozen-test contract, purge or assign
boundary-spanning trades, and handle zero/empty windows with a stable output
schema and strict JSON.

### 8. [P1] Pattern cross-validation can report “no disagreements” when the datasets do not overlap

**File:** `analysis/pattern_validation.py:247-266`.

`compare_to_mql5_export` uses an inner merge and checks only rows that survive.
It does not require unique `k` values or equal key coverage. With Python
results at `k=1` and an MQL5 export at `k=0`, an independent probe returned an
empty disagreement DataFrame: the strongest possible apparent pass for two
datasets that were never compared. Duplicate keys can also create a Cartesian
join. Use a validated one-to-one outer merge and treat missing, extra, or
duplicate keys as explicit failures before comparing predicate columns.

The operational `run` contract at lines 269-278 also relies on callers to
reverse chronological data but has no timestamp/order column with which to
verify that convention. A normal ascending CSV is therefore silently analyzed
backwards. Require and validate a timestamp/order convention at the file
boundary.

### 9. [P1] Release comparison reports a random bootstrap mean as the observed effect and permits meaningless resample counts

**File:** `analysis/compare_releases.py:52-91,94-139`.

The point estimate named `diff_mean` is `mean(diffs)` across random bootstrap
replicates, not `mean(candidate)-mean(baseline)` on the observed data. It can
therefore move with the seed. No validation exists for `n_resamples` or
`confidence`. With identical observed samples `[0,1]` and `[0,1]`,
`n_resamples=1`, and seed 42, the function returned a +0.5 difference, CI
`[0.5,0.5]`, and `likely_significant=True`. The observed difference is
exactly zero.

Return the observed effect as the point estimate, validate confidence and a
defensible minimum/maximum resample count, and label percentile bounds as
simulation/bootstrap intervals. Also decide whether release runs are paired
on the same market periods/trades; if they are, independent resampling with
different streams discards the pairing and is the wrong test.

This is not limited to the one-resample probe. The committed test at
`tests/test_compare_releases.py:43-48` blesses two constant observations per
group (two losses versus two wins) as CI `[1,1]` and “likely significant.” An
empirical bootstrap cannot represent uncertainty outside two degenerate
samples; a suitable small-sample difference interval still includes zero.
The loader also never establishes that the releases share symbol, broker,
period, costs, modelling mode, or set file. Its `symbol` argument only labels
metadata and does not filter or validate either input. Arbitrary, incomparable
datasets can therefore be reported as a release effect.

### 10. [P1] Required report provenance is structurally impossible, and one join hashes only half its inputs

**Files:** `analysis/report_metadata.py:1-9,21-24,75-109,115-145`;
`analysis/join_news_events.py:119-138`;
`analysis/join_trade_journal.py:78-101`;
`analysis/pattern_validation.py:269-285`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:69-71,183`;
`00_MASTER_PROMPT_FOR_CLAUDE.md:58`.

`ReportMetadata` has no fields for EA version, timeframe, modelling mode,
costs/spread/slippage, set file, or explicit data source. Although it has
period fields, pipeline APIs do not accept or derive them, so reports normally
write `null`. Optional user-supplied symbol/broker values are not checked
against datasets. CSV outputs generally have no metadata sidecar, and
`pattern_validation` offers no JSON/provenance output at all.

`join_news_events` hashes only `news_events_csv`; it omits every journal file
whose decisions are in the result. Its reported dataset identity therefore
cannot identify or reproduce the joined dataset. Conversely, an empty journal
directory produces metadata with an empty Git commit/hash and `dirty=False`
instead of recording the still-known code provenance and an explicit empty
dataset state.

Git capture defaults to the process current working directory, and none of the
CLI wrappers supplies `repo_path`. Invoking a module from another repository
can record that unrelated commit; invoking it outside Git fails. This directly
violates the no-CWD-dependency rule. `join_news_events` also writes `currency`
into the metadata's `symbol` field, so `USD` can be labelled as though it were
the traded symbol `XAUUSD`.

The combined hash documentation says it uses relative paths, but line 86 uses
`str(p)`, so identical bytes addressed by relative versus absolute paths (or
moved to another machine) get different dataset hashes. Absolute paths are
also written into reports and may disclose usernames or private export-folder
names. Add the missing provenance fields, derive/validate them, hash all
inputs from a stable snapshot with portable identifiers, and attach metadata
to every reviewable output.

Output paths must also be validated as distinct from all inputs and from each
other. `join_news_events` writes `output_csv` before hashing its news input;
setting both paths equal overwrites the source and then hashes the replacement.
The journal pipeline likewise permits output/output collisions or an output
path that overwrites a journal file. Direct non-atomic writes can leave both
evidence and report truncated after interruption.

### 11. [P1] Statistical outputs still hide uncertainty or serialize invalid numbers

**Files:** `analysis/metrics.py:35-67,120-135,168-213`;
`analysis/analyse_baseline.py:96-114`;
`analysis/monte_carlo.py:41-55,103-118`;
`analysis/walk_forward.py:165-182`.

The contract requires sample size and uncertainty for statistical claims.
Baseline expectancy reports a sample standard deviation (dispersion), not
uncertainty of the estimated mean; profit factor and drawdown have no
uncertainty; `BootstrapCiResult` omits the original sample size; and Monte
Carlo ruin probability has no binomial interval even though it is an estimated
proportion. Several paths accept `NaN`/infinity and all report writers use
`json.dumps` with its default `allow_nan=True`, so invalid RFC JSON can be
written rather than failing visibly. The walk-forward bug above demonstrates
this on the repository's own fixture.

Define which outputs are descriptive versus inferential, attach `n` and an
appropriate uncertainty measure to every inferential claim, and serialize
with `allow_nan=False` after finite-value validation.

### 12. [P1] MFE/MAE and giveback bar-window semantics can include price action outside the trade

**Files:** `analysis/calculate_mfe_mae.py:1-19,76-103`;
`analysis/trade_math.py:46-90`;
`analysis/analyse_giveback.py:18-22,100-128`;
`analysis/exit_simulation.py:49-88`.

The script includes bars whose single `timestamp` lies in the inclusive
`[entry_time, exit_time]` range, but it never defines whether that timestamp is
bar open or bar close. For a trade entering or exiting inside a bar, the bar's
high/low necessarily includes some price action before entry or after exit
(or the bar is omitted, depending on timestamp convention). That can overstate
MFE/MAE and violates the no-future-data requirement for an exit study. The
input has no tick/intrabar boundary data with which to correct it.

Require bar-boundary-aligned trades for this approximation and reject others,
or use tick/sub-bar data and clip the first/last interval. Record the chosen
modelling mode in provenance. Also validate finite high/low values: current
`max(0.0, NaN)` paths can turn corrupt bars into plausible zero excursion.

The same ambiguity affects giveback more severely. With normal bar-open
timestamps, a trade exiting at 10:05 can include the 10:00 H1 bar's 11:00
close and trigger after the trade ceased to exist. Close-only sampling also
misses a guard that arms at an intrabar high and gives back before the close.
This is acceptable only as a clearly bounded proxy; it cannot by itself be
presented as evidence that reproduces the tick-evaluated live guard.

### 13. [P2] Journal/news error and snapshot handling can produce incomplete or irreproducible results

**Files:** `data_collection/journal_reader.py:61-100,103-145`;
`analysis/join_trade_journal.py:58-61,72-145`;
`analysis/join_news_events.py:92-138`;
`analysis/analyse_giveback.py:145-182`.

- `read_journal_directory` exposes a caller-supplied glob without constraining
  it to the directory. A probe using `../*.jsonl` read a parent file. The CLI
  uses a fixed pattern, so this is a library boundary issue, but it should be
  closed before the reader is reused with external input.
- Records are parsed first and files are hashed later, without locking or a
  before/after stability check. A concurrent EA append or a newly created
  daily file can make the report rows and reported dataset hash describe
  different snapshots.
- The reader accumulates all records, raw malformed lines, and validation
  payloads in memory with no file/line/record cap. A caller-controlled journal
  can exhaust memory; randomized pipelines similarly expose unbounded
  resample counts.
- Python decodes journals as strict UTF-8, while `DJ_AppendDecision` opens the
  MQL5 file with `FILE_ANSI`. Non-ASCII ANSI bytes can abort the whole reader,
  and a UTF-8 BOM is treated as a first-line parse error. The producer/consumer
  encoding must be one explicit, tested contract.
- `join_trade_journal` promises duplicate rows in its error report but writes
  only duplicate counts, not the affected records. `join_news_events` can
  silently exclude invalid journal lines when only CSV output is requested.
  `analyse_giveback` writes only a row-error count, losing the errors
  themselves. It also accepts an empty or all-invalid trade file as a
  successful `0 compared` run. Their CLIs still return success.
- News events are not deduplicated by durable event identity before joining.

Constrain resolved input paths, analyze an immutable snapshot (or verify file
identity before and after), stream/cap untrusted inputs, and make every dropped
or duplicated row identifiable in a mandatory error artifact/non-zero status.

### 14. [P2] The environment is not reproducible from the committed dependency declarations

**Files:** `requirements.txt:1-26`;
`03_SOURCE_CODE/Python/pyproject.toml:1-7`;
`analysis/time_utils.py:46-57`;
`analysis/resampling.py:20-27`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:161-174,437-454`.

Every dependency is unpinned and there is no lock/constraints file or
`requires-python`. The code relies on Python 3.11 behavior for the `Z` suffix,
Pydantic v2 APIs, and current pandas/NumPy behavior; a future “clean” install
need not reproduce this run. The test plan asks for formatter, linter,
type-checker, and exact versions, but no formatter/linter/type-check result is
recorded and Ruff is configured without being declared. The resampling
docstring's byte-identical-across-machines/NumPy-versions promise is stronger
than an unpinned numerical stack can guarantee.

Pin the supported Python range, commit a resolved lock/constraints file, run
the declared quality gates, and phrase deterministic guarantees as applying
to the pinned runtime.

### 15. [P2] Task/process documentation contains stale and unsupported completion claims

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:320-334,367-373,456-468`;
`TASKS.md:38`; `analysis/join_trade_journal.py:12-16`.

The task still has a `Commit: Pending` entry after eight TASK-028 commits.
It says the test suite directly demonstrates that a four-trade-per-group gap
is not significant, but the committed suite contains only a comment saying
that an earlier four-trade attempt was tried; no such regression test exists.
The final decision and TASKS row say regime confusion-matrix work is closed
while the implementation explicitly marks it pending. `join_trade_journal`'s
module text still says `join_news_events.py` is not built.

Update the canonical task record to distinguish “files exist and execute”
from acceptance completion, list actual commits, and remove claims not backed
by committed tests/artifacts.

## Confirmed checks that do not require changes

- All 196 committed tests pass independently.
- All ten required notebooks execute independently; their content findings
  above are not execution failures.
- `schema.py`'s `extra="forbid"` rejects unexpected object keys.
- The modern local NumPy generator is isolated from legacy global RNG state
  for a fixed installed runtime.
- `EM_ComputeR`, `EM_ShouldGivebackCloseV637`, and
  `EM_ShouldGivebackCloseV811` are algebraically faithful to
  `ExitManager.mqh:44-53,265-297`; `analyse_giveback`'s final `r_diff` sign is
  correctly `trigger_r - actual_final_r`.
- The four implemented candle predicates match
  `CandlestickPatternEngine.mqh:60-90,115-190,265-294`.
- The stateless selection math in `regime_validation.classify` matches
  `MarketRegimeEngine.mqh:103-232` given the caller-supplied structure inputs.
  This confirmation does not expand its scope to gating, hysteresis, structure
  computation, or independently labelled evidence.
- The current EA has no assignment to `decision.signal_id`,
  `decision.market_family`, `decision.intraday_mode`, or
  `decision.news_state`; the strict literals reject the two empty enum fields
  as the task states.
- Subprocess Git calls use argument arrays and no `shell=True`; no credentials
  or Python live-trading calls were found in the TASK-028 implementation.
- Both immutable baseline directory trees remain byte-identical to their tags.

## Required disposition

Keep TASK-028 **In progress**. Resolve the P0/P1 correctness and provenance
findings, complete or formally split the owned deferred deliverables into
numbered tasks, add adversarial regressions for every reproduced counterexample,
then rerun the full suite and all ten notebooks for another independent review.
