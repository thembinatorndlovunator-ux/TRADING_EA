# TASK-028 independent code review — round 5

**Disposition: CHANGES REQUESTED**

**Review target:** branch `claude/task-028-python-statistical-lab`, commit
`750443d8ac1a270e289663b330b0618d2f4b716f` (`750443d`), independently
reviewed against parent `b88b63abf1d8ca03a9cec29493c7bba471264ed6`
(`b88b63a`), the current MQL source, the project contracts, and the immutable
baseline tags.

The round-4 remediation fixes a meaningful number of concrete defects, and all
declared automated gates pass. TASK-028 is nevertheless not ready to merge. I
found **18 remaining findings: 3 P0, 11 P1, and 4 P2**. The primary blockers
are contract failures that green unit tests do not cover: the package still
does not calculate the required equity-based giveback/comparison surface, the
new signal/outcome join rejects and corrupts the intended real partial-fill
schema, and the proposed session/mode/news analysis is not derivable from the
live source or executable end to end.

## Findings

### 1. [P0] Required equity-giveback, comparison, and cost-sensitivity deliverables remain absent or mislabeled

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:5-17,121-131,168-195`;
`00_MASTER_PROMPT_FOR_CLAUDE.md:158-180,836-843,1193-1222`;
`TEST_PLAN.md:9-23`; `profit_giveback_diagnosis_plan.md:74-76,102-120`;
`03_SOURCE_CODE/Python/analysis/analyse_baseline.py:14-22,189-205,276-297`;
`03_SOURCE_CODE/Python/analysis/metrics.py:509-590`;
`03_SOURCE_CODE/Python/analysis/analyse_giveback.py:10-22,304-434`;
`03_SOURCE_CODE/Python/analysis/compare_releases.py:367-408`;
`TASK-037_MT5_EXPORT_BRIDGE.md:46-60`; `TASKS.md:38`.

`analyse_baseline` explicitly has only a closed-trade **balance** curve. It
passes that curve to `compute_equity_peak_giveback`, then emits a field named
`equity_peak_giveback` with a note admitting it is balance-based. The helper
ports the percentage formula but has neither intratrade equity observations nor
the daily reset/timestamp semantics of the daily guard. This is not an account
equity-peak-giveback measurement and it is not the separately required daily
equity-giveback measurement. `analyse_giveback` still simulates per-trade
R-path exit guards, which is a third and different quantity.

The release-comparison pipeline and notebook 10 still compare only win rate
and R expectancy. They do not provide the required side-by-side surface for
profit, profit factor, drawdowns, recovery, giveback, streaks, MFE/MAE,
duration, frequency, dimensional breakdowns, or cost sensitivity. Adding
`spread_note` and `slippage_note` is provenance, not a spread/slippage scenario
sweep. TASK-037 exports neither an equity series nor cost scenarios, and no
other numbered task owns those inputs and closure tests.

The round-5 handover's statement that the remaining minimum comparison surface
is now built is therefore false. Implement the synthetic, hand-verifiable
metrics now and give every unavailable real-data input a concrete numbered
owner; do not relabel balance or per-trade R-path measurements as equity.

### 2. [P0] The durable signal/outcome identity contract rejects valid real fills and has no coherent order/position/deal model

**Files:** `03_SOURCE_CODE/Python/analysis/join_signal_to_outcome.py:76-85,111-115,141-215,222-236`;
`03_SOURCE_CODE/Python/analysis/schema.py:101-110`;
`03_SOURCE_CODE/Python/tests/test_join_signal_to_outcome.py:15-24,49-73`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh:130-157,179-209`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:106-110,125-143`;
`TASK-037_MT5_EXPORT_BRIDGE.md:48-60`.

The intended journal CSV contains nullable `order_id` and `deal_id`. The join
compares every shared field except `order_id` as an invariant. Consequently:

- journal `deal_id=None` plus a normal filled trade `deal_id=d1` produces zero
  joined rows and a `deal_id` conflict;
- journal `deal_id=d1` plus partial fills `d1` and `d2` rejects the second fill
  and emits only the first fill instead of aggregating the position.

Both cases were reproduced directly. The committed fixtures avoid the defect
by omitting the journal `deal_id` column altogether.

The namespace itself is unresolved. The join calls `order_id` a position key,
while `SOrderOpenResult` exposes `deal_ticket` and `position_ticket`, not an
order ticket, and explicitly distinguishes them. `trade_id` is never defined
as a deal, order, or position identifier. If it is position-scoped, legitimate
fill rows violate the uniqueness check; if it is deal-scoped, it duplicates
`deal_id`. A generic same-name comparison also misses cross-schema invariants:
a journal `direction=BUY` and trade `is_long=False` joined successfully.

Define versioned `order_id`, `position_id`, `deal_id`, and `trade_id` semantics
from MQL transaction through export and Python, map differently named
invariants explicitly, and test real partial-fill cardinality. A position must
be rejected as a unit if any constituent fill fails integrity; silently
retaining a subset is invalid evidence.

### 3. [P0] The session/mode/news outcome path is source-invalid and still not executable end to end

**Files:** `03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/SessionManager.mqh:96-110,146-164`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/News/NewsManager.mqh:38-53,112-140,157-191`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:334-492`;
`TASK-006_SESSION_MANAGER.md:64-70`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:85-110,125-143,169-180`;
`TASK-037_MT5_EXPORT_BRIDGE.md:151-170`;
`03_SOURCE_CODE/Python/notebooks/04_session_and_news_analysis.ipynb`, cells
6-8; `03_SOURCE_CODE/Python/analysis/performance_breakdown.py:128-205,227-310`.

`SN_GetSessionMinutesRemaining` measures time until the day's last configured
session ends. It includes gaps, returns `1.0` before the first session opens,
and returns `false` for either no session or unreadable session data under an
explicit “exclude it, never default it” rule. TASK-036 and notebook 04 instead
map `ratio >= 0.5` to `OPEN` and every false result to `CLOSED`. That labels
pre-open time and some gaps as open and turns data failure into a real closed-
session observation.

The task also says the live router already knows `market_family` and
`intraday_mode`. Current source has no mode router or market-family classifier;
TASK-006 deferred that work and no numbered task owns it. `news_state` has no
defined vocabulary: `NewsManager` exposes event status, blackout, and trigger
ID, while notebook 04 invents `NONE`/`NFP_NEARBY` and an existing MQL test uses
`CLEAR`.

Notebook 04 manually labels an already unified synthetic CSV. It never runs
the composed producer/export -> news join -> signal/outcome join -> performance
breakdown path, and its final cell admits the real breakdown remains to be run.
Neither TASK-036 nor TASK-037 owns that acceptance run. Define source-faithful
states including unknown/error, assign the missing classifier, and test the
actual composed path.

### 4. [P1] Partial-fill aggregation can manufacture internally inconsistent dollar and R evidence

**Files:** `03_SOURCE_CODE/Python/analysis/join_signal_to_outcome.py:111-115,126-138,172-239`;
`03_SOURCE_CODE/Python/analysis/performance_breakdown.py:167-205`.

The join validates a temporary `profit_numeric` series but never assigns it
back. Calling the public function with string profits `"30"` and `"20"`
returned `3020.0`, not `50.0`; two finite `1e308` profits returned `inf`.
After summing profit, it copies every other outcome from `group.iloc[0]`.
A probe with fill profits `30/20` and fill R values `1/4` produced position
profit `50` but position `r_multiple=1`, which `performance_breakdown` then
uses as the entire trade's R outcome.

The same first-fill leakage affects trade/deal IDs, entry/exit/stop prices and
other numeric fields; there is no volume column with which to define weighted
prices. The function also claims full journal and normalized-trade schemas but
requires only one journal and four trade columns, so a minimal input can emit a
“unified” file without chronology, direction, stop geometry, or analysis
dimensions. Convert and post-validate every aggregate, define position-level
price/R semantics or drop those fields, and enforce the advertised schemas.

### 5. [P1] The signal/outcome join's implicit sidecar can overwrite its input evidence

**File:** `03_SOURCE_CODE/Python/analysis/join_signal_to_outcome.py:248-310`.

Path collisions are checked while `errors_json` is still `None`. The implicit
`<output-stem>.errors.json` path is derived only after the input has been read
and the output CSV written, then is written without revalidation. A direct run
with the journal input named `out.errors.json` and output `out.csv` completed
and replaced the journal CSV with JSON metadata. The same round-4 defect was
fixed in the trade/news joins but reintroduced here. Derive every implicit
path before any I/O and run the complete hard-link-aware input/output/output
collision check on that final set.

### 6. [P1] Provenance still does not bind persisted results to an immutable byte snapshot and remains optional

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:70-86,183-195`;
`03_SOURCE_CODE/Python/analysis/report_metadata.py:128-154,178-270`;
`03_SOURCE_CODE/Python/data_collection/journal_reader.py:287-365`;
`03_SOURCE_CODE/Python/analysis/join_trade_journal.py:123-190`;
`03_SOURCE_CODE/Python/analysis/join_news_events.py:206-286`;
`03_SOURCE_CODE/Python/analysis/join_signal_to_outcome.py:267-310`;
persisted-output paths in `analyse_baseline.py`, `analyse_giveback.py`,
`calculate_mfe_mae.py`, `walk_forward.py`, `performance_breakdown.py`,
`pattern_validation.py`, and `parameter_stability.py`.

The improved before/after hash checks are race detectors, not proof that the
parsed bytes equal the reported hash. Deterministic probes demonstrated both
directions:

- an ABA mutation let trade/news joins parse changed bytes, restore the old
  bytes before re-hash, and publish new analysis under the old hash;
- mutating an `analyse_baseline` input after parsing but before metadata
  produced an old-data result whose hash matched the new file;
- an outward `decisions_*.jsonl` symlink was included in the hash/source list
  but silently skipped by the reader, yielding nonempty provenance for zero
  analyzed rows.

Parse from one staged immutable byte snapshot or open handle and hash that
same accepted source set. Separately, most CSVs can still be written with no
JSON manifest, and most CLIs cannot express all applicable EA version, broker,
period, timeframe, modelling mode, cost model, set file, and source identity.
The empty-journal path writes `dataset_hash=""`, not a SHA-256 identity.
`PIPELINE_VERSION=0.3.0` and the new spread/slippage arguments are genuine
fixes, but the mandatory provenance acceptance criterion remains unmet.

### 7. [P1] Release comparison still cannot establish that two results came from comparable experiments

**Files:** `TEST_PLAN.md:3-8,25-29`;
`03_SOURCE_CODE/Python/analysis/compare_releases.py:220-344,367-426`;
`03_SOURCE_CODE/Python/notebooks/10_baseline_vs_candidate.ipynb`, cells 1-3.

The required period is a caller label used only as a containment bound. It
does not prove either run actually covered that window or used the same raw
market data. A baseline trading near 2 January and a candidate trading near 29
January both passed a 1-31 January label. Broker/timeframe/model/set-file pairs
are optional and are compared only when both are provided; a baseline broker
of `Deriv` and missing candidate broker passed. Costs remain a shared trusted
note, and role-specific output hashes prove only that the two trade files
differ, not that their source data matched. Notebook 10 demonstrates the flaw
by applying a full-year label to one-hour synthetic samples with no manifests.

Require complete role-specific run manifests and verify common period, raw
market-data identity, symbol universe, broker, timeframe, modelling and costs.
Different observed trade envelopes can be legitimate, so equality of first/
last trades is not the solution. Also retain the current disclosure that the
R bootstrap treats samples as independent, or implement a market-period-
aware paired/blocked comparison.

### 8. [P1] Finite inputs still yield non-finite results or uncaught overflow across the statistics layer

**Files:** `03_SOURCE_CODE/Python/analysis/metrics.py:223-285,354-413,416-485,509-590`;
`03_SOURCE_CODE/Python/analysis/monte_carlo.py:167-208`;
`03_SOURCE_CODE/Python/analysis/parameter_stability.py:193-233`.

Fresh probes against `750443d` produced:

- `bootstrap_confidence_interval([1e308,-1e308], 100, seed=1)` -> point
  `0.0`, CI `[NaN, NaN]`;
- `expectancy([1e308,-1e308], 100, seed=1)` -> uncaught `OverflowError`
  during variance calculation, before the new post-check;
- `compute_max_drawdown([1e308,-1e308])` -> infinite absolute and percentage
  drawdown;
- `compute_equity_peak_giveback([5e307,1e308,-1e308], ...)` -> infinite
  maximum giveback;
- `run_monte_carlo([5e306] * 20, 100, 1)` -> infinite mean final balance even
  though each individual final balance was finite;
- two finite stability paths ending at `-1e308` -> infinite mean and NaN CI.

Use stable accumulation or defensible magnitude bounds, catch arithmetic
overflow, and reject non-finite derived statistics before returning—not only
at late JSON serialization.

### 9. [P1] Parameter stability still sweeps the wrong surface and misstates effective configuration

**Files:** `profit_giveback_diagnosis_plan.md:102-120`;
`03_SOURCE_CODE/Python/analysis/parameter_stability.py:31-36,128-135,140-234,238-312`;
`03_SOURCE_CODE/Python/analysis/exit_simulation.py:18-49`;
`03_SOURCE_CODE/Python/analysis/analyse_giveback.py:235-247`;
`03_SOURCE_CODE/Python/notebooks/02_profit_giveback_analysis.ipynb`.

`arm_rr` and `close_trigger_floor_r` are checked only for finiteness. The
simulator clamps the arm to at least `0.25`, so a requested arm of `-5` and
`0.25` produce identical behavior while the artifact records `-5` as the
effective arm. Negative floors also pass despite the stated V6.37 `0.05R`
floor. Persist requested and effective values and reject settings outside the
defined model domain.

The diagnosis plan requires neighbouring sweeps of both V6.37 controls and
both V8.11 controls. The implementation is only a one-dimensional V6.37
giveback-percentage sweep. Its data contract also requires path index 0 to be
exactly `0R`, while `analyse_giveback` includes the entry-time bar close and
notebook 02 begins a path at `+0.5R`. Define one timestamp/bar convention and
implement the promised multidimensional/model-comparison surface.

### 10. [P1] Resampling controls are still hard-coded, conditionally validated, and unbounded

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:70-86`;
`03_SOURCE_CODE/Python/analysis/analyse_giveback.py:339-430`;
`03_SOURCE_CODE/Python/analysis/parameter_stability.py:193-312`;
`03_SOURCE_CODE/Python/analysis/walk_forward.py:157-184,213-243,330-396`;
`03_SOURCE_CODE/Python/analysis/performance_breakdown.py:128-205,227-310`;
`03_SOURCE_CODE/Python/analysis/metrics.py:354-413`.

Walk-forward and performance breakdown now expose and persist confidence and
resample count, but giveback and parameter stability still hard-code
`2000/0.95`. Validation happens only when a bootstrap is reached: performance
breakdown accepted `n_resamples=0` when all groups were singletons, and
walk-forward accepted it when no windows were generated. There is no upper
bound on bootstrap/Monte Carlo comparison counts, permitting accidental
unbounded memory/time use. Validate controls unconditionally at every public
boundary, expose them consistently, impose documented resource ceilings, and
make configuration inseparable from each persisted result.

### 11. [P1] Newly added baseline metrics are row-order dependent or normalized to the wrong period

**Files:** `03_SOURCE_CODE/Python/analysis/analyse_baseline.py:175-190,210-232,283-297`;
`03_SOURCE_CODE/Python/tests/test_analyse_baseline.py:352-364`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:83-84`.

Drawdown now correctly aggregates equal-time exits, recognizing that their CSV
order is not durable. Longest losing streak nevertheless iterates that same
arbitrary tied order. Reordering three simultaneous outcomes from
loss/win/loss to loss/loss/win changed the reported streak from `1` to `2`.
Define tied-time semantics or require a durable deal sequence.

`trades_per_day` divides by the active envelope from earliest entry to latest
exit, not the declared backtest/evaluation period. The test therefore blesses
four trades over seven active hours as about `13.7/day`, even if those trades
came from a month-long run. Average winner, average loser, and duration also
carry neither subgroup sample sizes nor uncertainty, despite the task's
sample-size/uncertainty contract. Accept an authenticated period and report
the denominators for every subgroup statistic.

### 12. [P1] MFE/MAE and giveback accept incomplete bar paths as complete evidence

**Files:** `03_SOURCE_CODE/Python/analysis/trade_math.py:73-133`;
`03_SOURCE_CODE/Python/analysis/calculate_mfe_mae.py:101-145`;
`03_SOURCE_CODE/Python/analysis/analyse_giveback.py:129-142,235-247`;
`TASK-037_MT5_EXPORT_BRIDGE.md:46-110`.

Endpoint alignment is enforced, but expected cadence/timeframe and gaps are
not. A trade from 00:00 to 03:00 with bars only at 00:00 and 03:00 completed
and reported one measured bar, silently ignoring the missing 01:00 and 02:00
exposure. Giveback likewise accepts sparse paths and follows a different
entry-bar-close convention from parameter stability. TASK-037 does not export
OHLC/close bars or per-trade R paths at all. Require a declared cadence,
complete interval coverage, and one canonical bar-boundary convention; add
the missing real-data exports.

### 13. [P1] The future real-export net-P/L contract is explicitly contradictory

**Files:** `03_SOURCE_CODE/Python/analysis/analyse_baseline.py:28-33`;
`TASK-037_MT5_EXPORT_BRIDGE.md:48-60,130-135`.

`analyse_baseline` asserts normalized `profit` is net and assumes an MT5 Deals
profit column normally already includes commission and swap. TASK-037 says
that exact net-versus-gross behavior is unverified and must not be assumed,
yet its export schema never defines aggregation of profit, commission, swap,
and fees. Every dollar metric can therefore be systematically wrong once the
first real export is used. Specify and test the normalized net-P/L equation
against actual MT5 history fields before accepting the bridge.

### 14. [P1] Registered follow-up tasks can pass without closing the source requirements assigned to them

**Files:** `00_MASTER_PROMPT_FOR_CLAUDE.md:424-432,649-662,1193-1222`;
`TASK-016_MARKET_REGIME_ENGINE.md:71-77`;
`TASK-018_CHART_PATTERN_ENGINE.md:77-90,207-213`;
`TASK-031_REGIME_VALIDATION_COMPLETION.md:95-126,145-160`;
`TASK-033_PATTERN_VALIDATION_COMPLETION.md:80-107,126-134`;
`TASK-034_LIVE_SAFETY_WIRING.md:83-111,134-160`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:106-110,125-143`;
`TASK-037_MT5_EXPORT_BRIDGE.md:3-9,46-110,115-170`.

Several deferrals are still not closure-safe:

- TASK-031 puts a transition-history ring buffer in Python-only Files
  affected, although the master and TASK-016 require/defer a live MQL engine
  transition history. Its acceptance can pass while the EA still lacks it.
- TASK-033 calls double top/bottom and H&S/inverse “all chart patterns,” but
  the master and TASK-018 also require and explicitly defer triple top/bottom.
  No numbered task owns their MQL implementation and Python validation.
- TASK-034 requires a `FairEconomyNewsProvider`, cache/refresh, URL setup and
  fail-closed fetch behavior in its specification, but omits the provider from
  Files affected, tests, and acceptance. It can pass with no live provider.
- TASK-036 does not handle asynchronous `TRADE_RETCODE_PLACED`: the EA journals
  once immediately after submission, has no `OnTradeTransaction` update path,
  and the task neither defines later fill correlation nor includes
  `OrderManager.mqh` in Files affected.
- TASK-037 claims to unblock every real Python run but omits OHLC/close bars,
  R paths, account equity, cost scenarios, session evidence, and the actual
  joined performance run.

Correct the scopes, dependencies, files, test plans, and acceptance criteria;
prose references to a future task are not executable ownership.

### 15. [P2] Performance dimensions can remain mutually contradictory

**File:** `03_SOURCE_CODE/Python/analysis/performance_breakdown.py:96-120,227-275`.

Hour and weekday are now authoritatively recomputed from `entry_time`, which is
a genuine fix. No equivalent validation exists for `news_state` versus
`in_news_blackout` or for categorical/boolean types. A row with
`news_state="CLEAR"` and `in_news_blackout=True` was accepted and grouped, as
were string-valued blackout flags. Define enums and cross-field invariants and
reject contradictory observations before grouping.

### 16. [P2] Journal/news resource, identifier, and path hardening remains incomplete

**Files:** `03_SOURCE_CODE/Python/data_collection/journal_reader.py:46-54,127-145,161-284,287-365`;
`03_SOURCE_CODE/Python/analysis/join_trade_journal.py:98-114`;
`03_SOURCE_CODE/Python/analysis/join_news_events.py:102-196,241-267`;
`03_SOURCE_CODE/Python/analysis/csv_io.py:82-122`.

- `MAX_LINE_BYTES` is a character limit on `TextIOWrapper`, not a byte limit.
  There is no file-count, total-byte, error-count, or aggregate retained-error
  budget; the design can retain roughly one million 2,000-character previews.
  A deeply nested but sub-megabyte JSON row raised `RecursionError` and aborted
  the directory instead of becoming one row error.
- Trade/news join output-output checks use resolved strings rather than the
  shared hard-link-aware helper. Their “outside journal directory” check tests
  only the immediate parent; a nested `journal/subdir/out.csv` was accepted.
- News `event_id` is read with generic pandas inference even though MQL defines
  it as a durable string. `001` is re-emitted as `1`, and `001`/`1` collapse
  into a false duplicate. Public news controls accept non-finite/wrong types:
  `min_importance=NaN`, `1.5`, and `True` passed the current boundary checks.

Make limits accurately byte-based with aggregate budgets, catch parser-depth
failures, use one file-identity/descendant policy, load every durable ID as a
string, and enforce finite non-boolean integer controls.

### 17. [P2] Required notebooks execute but do not verify the newly claimed behavior

**Files:** `03_SOURCE_CODE/Python/notebooks/01_baseline_trade_audit.ipynb`;
`03_SOURCE_CODE/Python/notebooks/04_session_and_news_analysis.ipynb`;
`03_SOURCE_CODE/Python/notebooks/10_baseline_vs_candidate.ipynb`.

Notebook 01 does not display or hand-check the new recovery/giveback/streak/
averages/duration/trades-per-day fields. Notebook 04 demonstrates the invalid
session mapping and manually prepared dimensions rather than the composed
pipeline. Notebook 10 still says both win-rate and R-expectancy differences
use two-sample bootstrap intervals, although win rate now correctly uses
Newcombe-Wilson. Successful execution proves the cells run, not that the
scientific claims are correct; update them to exercise and independently
hand-check the actual contracts.

### 18. [P2] Canonical task, handover, and backlog history still contradict Git and current test reality

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:328-336,359-360,489-492,517-536`;
`TASKS.md:38`; `09_HANDOVERS/claude_to_codex/TASK-028_handover.md:246-357`;
commit history `e37bbec..750443d`.

- Independent collection/execution produced **460 passed**, matching the
  commit message; TASK-028, TASKS, and the handover say 459.
- TASK-028 says “all three” remediation series after the fourth remediation
  commit landed. Actual TASK-028 history contains 21 commits including
  registration.
- The task/backlog inventory advertises two bonus pipelines but omits the real
  third pipeline, `join_signal_to_outcome.py`.
- It still refers generically to a future MT5 bridge although TASK-037 is now
  registered.
- TASK-028/TASKS say round 4 confirmed round 3's remediation genuinely
  resolved. The round-4 review confirmed only a specific subset and found new
  P0 defects in the redesigned join and outcome path. Scope that statement to
  the review's actual “Corrections independently confirmed” list.
- The handover overclaims that the minimum comparison surface is built and
  that giveback resampling controls are exposed; findings 1 and 10 disprove
  both claims.

Update all canonical documents to one durable, Git-factual pending-review
state. Do not rewrite a prior reviewer disposition as broader approval than it
gave.

## Corrections independently confirmed

The following round-4 remediation items are genuinely improved or resolved:

- Zero-duration MFE/MAE trades are rejected, canonical-time duplicate bars are
  checked after UTC normalization, and detailed R paths receive stronger
  structural validation.
- Atomic CSV output is explicitly UTF-8; the non-ASCII regression test passes.
- Durable IDs in `join_signal_to_outcome` are loaded as strings, preserving
  values above `2^53` and leading zeroes (subject to the larger identity
  defects in findings 2 and 4).
- The implicit sidecar paths in `join_trade_journal` and `join_news_events` are
  derived before their exact-path checks; the news re-hash occurs after news
  parsing, and a fixed enumerated journal-file list is passed to the reader.
- CLI handling for expected `RuntimeError` failures and several hard-link
  guards is improved.
- `PIPELINE_VERSION` is bumped to `0.3.0`, and spread/slippage provenance
  arguments are threaded through relevant reports.
- Profit factor now carries the true observation count. Newcombe-Wilson is
  correctly used for the win-rate difference, and release hashes are
  role-specific.
- Walk-forward and performance breakdown expose/persist confidence and
  resample counts. Performance hour/day dimensions are recomputed from UTC.
- Giveback parameters reject ordinary non-finite inputs and disclose more
  requested/effective configuration. Parameter-stability path schema checks
  are substantially stronger.
- Non-finite operand checks and several post-computation checks were added,
  although finding 8 demonstrates incomplete coverage.

## Independent verification run

- Full suite: **460 passed, 4 warnings in 31.85s**.
- Ruff lint: **All checks passed**.
- Ruff format check: **59 files already formatted**.
- mypy: **Success, no issues in 24 source files**.
- All **11 notebooks** executed successfully, each exit 0.
- `git diff --check b88b63a..750443d`: clean.
- The commit changes 44 paths and no path under `01_BASELINE/` or
  `03_SOURCE_CODE/MQL5/`; no secret-like credential material was added.
- `01_BASELINE/EA_V637` is byte-identical to tag `baseline-v637`: EA blob
  `26018c013b60e371c112cea4f57552884d1e6902`, `IDENTITY.md` blob
  `5bc1a9b4a3198f5575d9efc35ad723242ac4b2d6`.
- `01_BASELINE/EA_V811` is byte-identical to tag `baseline-v811`: EA blob
  `f0644ad8a3ce8f7471d3e3ed8393c375977ac551`, `IDENTITY.md` blob
  `e1ba7a7b741969d96b07db179edd9dfa82c0b44a`.

Green automation does not invalidate the counterexamples above. Several tests
avoid the real schema, some validation runs only when data reaches a particular
branch, and multiple required deliverables have no executable closure test.

## Required disposition

**CHANGES REQUESTED.** Do not merge or mark TASK-028 complete at `750443d`.
Resolve every P0/P1 item, add regression and end-to-end tests for the concrete
counterexamples, make every unavailable real-data input and live-source gap an
executable numbered dependency, correct the canonical history, and request a
sixth independent review.
