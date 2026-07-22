# TASK-028 independent code review — round 4

**Disposition: CHANGES REQUESTED**

**Review target:** branch `claude/task-028-python-statistical-lab`, commit
`b88b63abf1d8ca03a9cec29493c7bba471264ed6` (`b88b63a`), independently
reviewed against parent `fd07473` and against the current repository contracts.

The remediation is substantial and many round-3 defects are genuinely fixed,
but TASK-028 is not ready to merge. I found **18 findings: 3 P0, 11 P1, and
4 P2**. The most important blockers are not test-count issues: required
statistical deliverables remain absent, the new durable identity join cannot
consume the intended real journal/export contracts safely, and the required
session/mode/news outcome analysis still has no completed end-to-end path.

## Findings

### 1. [P0] Required baseline-comparison and equity-giveback deliverables remain absent and unowned

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:5-17,121-131,168-195`;
`00_MASTER_PROMPT_FOR_CLAUDE.md:158-180,1193-1222`;
`TEST_PLAN.md:9-23`; `analysis/analyse_baseline.py:1-24,180-225`;
`analysis/analyse_giveback.py:1-35,79-98,219-243`;
`analysis/compare_releases.py:264-312`; `TASK-037_MT5_EXPORT_BRIDGE.md:46-90`.

TASK-028 explicitly includes a hand-verifiable **equity-peak-giveback** fixture,
and the master prompt assigns equity-peak giveback to the Python laboratory.
No Python code computes account or daily equity-peak giveback. The current
giveback pipeline simulates per-trade R-path exit guards, which is a different
quantity. `analyse_baseline` explicitly operates on closed-trade balance only
and persists `max_equity_drawdown: None`.

The baseline-comparison minimum surface is also incomplete. The current
normalized trade schema already permits recovery factor, longest losing
sequence, average winner/loser, duration, and trades/day to be computed, but no
pipeline reports them. Maximum equity drawdown, equity-peak giveback, and
spread/slippage sensitivity need additional input data, yet no numbered task
owns the necessary equity-series/cost-scenario export and analysis. Merely
adding `spread_note`/`slippage_note` metadata is not sensitivity analysis.

This is not excused by the lack of real evidence: TASK-028's own contract says
to implement hand-verifiable synthetic fixtures while marking the real-data run
pending. Either implement these deliverables and fixtures now or create
specific, executable follow-ups whose inputs and closure tests are defined.

### 2. [P0] The new durable signal-to-outcome join is unusable with the intended real contracts and can corrupt statistical identity

**Files:** `analysis/join_signal_to_outcome.py:1-44,68-160`;
`analysis/schema.py:1-5,63-101`; `analysis/csv_io.py:28-68`;
`tests/test_join_signal_to_outcome.py:80-117`;
`TRADE_DECISION_SCHEMA.json:1-26`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:16-25,76-103,127-130,141-162`;
`TASK-037_MT5_EXPORT_BRIDGE.md:46-52,100-126`;
`analysis/performance_breakdown.py:29-47,150-183`.

The module says rejected/unfilled journal decisions are normal and should be
omitted from the matched output, while `TradeDecision.order_id` is explicitly
nullable. The implementation instead aborts the **entire journal** if any row
has a null `order_id`. A direct probe containing one filled decision and one
ordinary pre-submission rejection raised `CsvSchemaError`; the committed test
at lines 113-117 canonizes this contradiction.

Additional integrity defects remain:

- The implementation uses only `order_id`; `deal_id` is never read, despite
  the commit message and TASK-036 describing the Python half as order/deal-ID
  complete.
- Generic pandas CSV inference is used for durable IDs. An in-memory probe of
  `9007199254740992`, `9007199254740993`, and a blank ID loaded the column as
  `float64` and collapsed the first two IDs to the same value. Real MT5 ticket
  IDs are durable identifiers and must be read as strings, never floating
  point. Leading zeroes are also discarded (`"001"` becomes `1`).
- `trade_id` is not checked for nulls or duplicates, `profit` is not checked
  for finiteness, and the claimed full input schemas are reduced in code to
  one required journal column and three trade columns.
- Shared fields are merged with trade-row precedence. Conflicting journal and
  trade `symbol`, `direction`, or `strategy` values are silently masked rather
  than reconciled or rejected.
- The stated partial-fill rule emits one downstream “trade” per fill. The
  performance pipeline then treats those correlated rows as independent
  observations, inflating `n_trades` and confidence unless fills are first
  aggregated to one position/outcome or explicitly clustered.
- `TRADE_DECISION_SCHEMA.json` and `DecisionJournal.mqh` still have neither ID,
  contradicting `schema.py`'s current field-for-field-match claim.
- TASK-037's trade export still omits both `order_id` and `deal_id`, so the only
  task that is meant to produce real trades cannot produce this join's input.

Filter and count unsubmitted decisions instead of rejecting them; establish a
versioned, string-typed identity contract across MQL, JSON schema, journal CSV,
trade export, and Python; define aggregation/cardinality for positions and
partial fills; and add the real export-to-join-to-breakdown test to TASK-037.

### 3. [P0] Required performance by session, mode, and news window is still not delivered end to end

**Files:** `00_MASTER_PROMPT_FOR_CLAUDE.md:158-180,1125-1154,1215-1222`;
`TEST_PLAN.md:20-23`; `notebooks/04_session_and_news_analysis.ipynb` markdown
and code cells; `analysis/performance_breakdown.py:1-47,74-110,202-264`;
`tests/test_performance_breakdown.py:1-144`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:85-97`;
`TASK-037_MT5_EXPORT_BRIDGE.md:46-90,118-147`;
`TASK-002_PHASE2_SPECIFICATION.md:1268-1269`.

Notebook 04 now honestly says it does **not** perform session analysis: it
recomputes news-window membership and separately groups synthetic trades by UTC
hour. It never reports trade outcomes by `session_state`, `intraday_mode`,
`news_state`, or `in_news_blackout`. The performance module lists those generic
columns, but neither this notebook nor its tests exercise the required outcome
analyses.

The deferral chain is incomplete. TASK-037 specifies no broker session-table
export. TASK-036 says to derive `session_state` from the remaining-session API,
but does not define how the numeric value maps to the specified
`OPEN`/`CLOSING_SOON`/`CLOSED` buckets. The broken/missing export-to-outcome join
in finding 2 also prevents the news decisions from acquiring trade outcomes.

Implement and test synthetic session/mode/news outcome breakdowns now, then
define the exact producer/export mapping needed to repeat them on real data.

### 4. [P1] Late-derived sidecar names can overwrite another requested output or the input evidence

**Files:** `analysis/join_news_events.py:138-162,253-322`;
`analysis/join_trade_journal.py:81-97,166-203`.

Both scripts validate only the explicitly supplied paths, then derive a
provenance/error filename later without re-running collision checks.

Direct probes reproduced both failure modes:

- `join_news_events(output_csv=joined.csv,
  summary_json=joined.errors.json, errors_json=None)` wrote the requested
  summary and then replaced it with the derived error payload.
- With the news input itself named `joined.errors.json` and output
  `joined.csv`, the derived error report replaced the source news evidence.
- `join_trade_journal(output_csv=foo.csv,
  output_json=foo.provenance.json, errors_json=None)` similarly replaced the
  requested valid-record JSON with the derived provenance/error report.

Derive every implicit path before any read or write, then apply the complete
hard-link-aware input/output/output collision validation to the final path set.

### 5. [P1] Hash/re-hash checks still do not bind reports to the bytes and source set actually analyzed

**Files:** `analysis/join_trade_journal.py:99-159`;
`analysis/join_news_events.py:164-235`;
`data_collection/journal_reader.py:217-288`;
`analysis/analyse_baseline.py:124-239`;
`analysis/join_signal_to_outcome.py:132-158`;
`analysis/report_metadata.py:90-145,206-261`.

`join_trade_journal` captures and hashes one glob result, but the reader globs
the directory again. A probe added a second `decisions_*.jsonl` file after the
initial glob/hash: both files were analyzed, metadata listed only the first,
and the post-check passed because it re-hashed only the old list.

`join_news_events` performs its purported post-parse hash **before** reading
the news CSV. Mutating that CSV inside its reader produced a blackout result
from the new bytes with the old hash. The post-check is skipped entirely when
the journal directory initially has no journal file. Other pipelines still
parse first and hash later, which permits the inverse race.

This needs one immutable snapshot/staged-byte design shared by every pipeline,
plus re-enumeration of multi-file source sets before publication. Two hashes of
independent file reads are detection heuristics, not evidence that the parsed
bytes equal the reported hash.

### 6. [P1] The new atomic CSV writer violates the UTF-8 contract on Windows

**File:** `analysis/csv_io.py:330-352`.

The temporary CSV file is opened without an explicit encoding. In the tested
Windows environment it used `cp1252`: writing `Café` produced byte `0xE9`, and
reopening the result as UTF-8 raised `UnicodeDecodeError`. Characters outside
the active code page can fail the write outright.

Every pipeline now uses this helper, so this is system-wide. Open the temporary
file with `encoding="utf-8"` (and retain the current atomic replacement).

### 7. [P1] MFE/MAE and giveback bar identity still admit contaminated evidence

**Files:** `analysis/trade_math.py:73-133`;
`tests/test_trade_math.py:85-116`;
`analysis/calculate_mfe_mae.py:101-116`;
`analysis/analyse_giveback.py:129-142`.

The ordinary multi-bar MFE interval is now correctly half-open, but the new
`entry_time == exit_time` exception includes the entire bar. Under the module's
own exact bar-open convention, equal timestamps describe a zero-duration trade
at the bar open, not a trade exposed to the following bar. A probe with one bar
(`high=999`, `low=0`, entry `100`, stop `98`) returned `mfe_r=449.5` and
`mae_r=-50.0`, all from prices after the recorded exit. The test suite enshrines
this result as correct. Reject it as unmeasurable at bar resolution or require
tick/sub-bar evidence.

Both CSV pipelines also check duplicate `(symbol, timestamp)` keys **before**
UTC normalization. Raw spellings `...Z` and `...+00:00` pass as distinct, then
become the same instant. A direct MFE probe accepted two conflicting rows at
that instant and reported both in the measurement. Parse first, then enforce
canonical-time uniqueness.

### 8. [P1] The parameter-stability CSV does not enforce its stated path semantics or complete experiment configuration

**Files:** `analysis/parameter_stability.py:31-36,62-92,95-179,182-247`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:70-86`.

The new CSV-backed CLI and dataset hash are real improvements. The loader,
however, checks only `bar_index`/`r_value` finiteness. It does not reject blank
`path_id`, duplicate `(path_id, bar_index)`, fractional/negative/gapped indices,
missing index zero, or a nonzero entry R. Pandas silently drops a blank-ID group.
A malformed probe containing a blank ID, `-2.5`, duplicate index `7`, and no
index zero completed successfully.

`arm_rr` and `close_trigger_floor_r` are neither validated nor CLI-exposed.
NaN values produced a successful result. The summary omits both values plus
bootstrap confidence and resample count. Enforce the documented sequence
schema and persist/expose every effective parameter.

### 9. [P1] Giveback and other numeric analysis controls remain silently clamped or semantically invalid

**Files:** `analysis/analyse_giveback.py:101-120,219-227,248-338`;
`analysis/exit_simulation.py:18-49`;
`analysis/join_news_events.py:91-115,234-247`;
`analysis/pattern_validation.py:118-139,269-300,353-434`.

`analyse_giveback` validates none of its five model parameters and persists
none of them. Passing NaN for all five produced valid comparisons/triggers with
zero row errors because Python's `min`/`max` behavior silently selected effective
clamps. Out-of-range finite settings likewise execute a different effective
setting without the artifact disclosing requested or effective values. The
summary also lacks a like-for-like full-cohort mean effect magnitude for the
two models; it has only conditional mean magnitude and full-cohort helped rate.

The same validation discipline is absent from news `before_minutes`/
`after_minutes`/`min_importance` controls and pattern `trend_lookback`/
`size_window`; negative values can silently invert/empty windows or turn “no
comparison history” into an automatic percentile pass. Validate finite/range
semantics at each public entry point and report the effective configuration.

### 10. [P1] Release comparison still accepts experiments that violate the required comparability contract

**Files:** `TEST_PLAN.md:3-8,25-29`;
`analysis/compare_releases.py:15-22,191-262,285-326`;
`analysis/report_metadata.py:103-145`.

The fix rejects only wholly disjoint periods. A baseline spanning January
1-31 and candidate spanning January 31-February 28 passed because the ranges
touch at one instant. The contract requires identical periods, data, costs,
and broker settings, not any overlap. Multi-symbol inputs are checked only via
one global symbol set and min/max range; per-symbol periods and sample weights
may differ completely.

Broker, timeframe, modelling mode, spread, slippage, set file, and data identity
are still optional caller assertions, not two compared manifests. The one
combined, order-independent dataset hash is also not role-preserving: two
outside-repo inputs with the same filename receive indistinguishable labels,
so swapping baseline and candidate can retain the same combined hash while
reversing the comparison.

Require two complete role-specific experiment manifests, verify all mandated
equality fields, and either implement the same-market paired/blocked comparison
or explicitly model and disclose the within-period dependence.

### 11. [P1] Mandatory provenance remains optional or unexpressible for normal persisted outputs

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:70-86,183-195`;
`00_MASTER_PROMPT_FOR_CLAUDE.md:54-58`;
`analysis/report_metadata.py:23-32,168-261`; persisted-output sites across
`analyse_baseline.py`, `analyse_giveback.py`, `calculate_mfe_mae.py`,
`walk_forward.py`, `performance_breakdown.py`, `pattern_validation.py`,
`parameter_stability.py`, and `join_signal_to_outcome.py`.

Most CSV outputs can still be requested without any metadata sidecar. Most
CLIs cannot express EA version, broker, timeframe, period, modelling mode,
costs, set file, or data source. `spread_note` and `slippage_note` exist on the
dataclass but no analysis caller exposes or populates them. The signal/outcome
join writes provenance only when optional `errors_json` is supplied.

`PIPELINE_VERSION` also remains `0.2.0` even though `b88b63a` changes output
shapes, adds sidecars and metadata fields, renames persisted metrics, and adds
a new pipeline—contrary to its own “bump on output-shape change” comment.

Every persisted result needs an inseparable manifest with required applicable
fields and a truthful pipeline version; optional metadata is not the contract.

### 12. [P1] Several randomized reports still hide their resampling configuration

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:70-86`;
`analysis/walk_forward.py:145-184,202-339`;
`analysis/performance_breakdown.py:113-199,202-262`;
`analysis/parameter_stability.py:95-179,182-234`;
`analysis/analyse_giveback.py:267-337`.

Seed threading is improved, but the contract also requires explicit and
reported simulation/resample counts. Walk-forward, performance breakdown, and
parameter stability hard-wire `expectancy`/bootstrap defaults and omit
`confidence` and `n_resamples` from their artifacts. CSV-only output omits even
the seed. Giveback reports the mean-difference bootstrap configuration but not
the Wilson confidence used for its helped-rate intervals.

Expose these settings at `run()`/CLI boundaries, thread them into the metric,
and persist them beside every interval.

### 13. [P1] Finite operands can still produce non-finite statistics

**Files:** `analysis/metrics.py:211-365`;
`analysis/compare_releases.py:113-188`.

Input-level NaN/inf rejection is fixed, but sums, variance, means, resample
statistics, and differences are never checked after computation. Independent
probes produced:

- `expectancy([1e308, 1e308], n_resamples=100)` -> mean/std `inf`, CI
  `[nan, nan]`;
- `profit_factor([1e308, 1e308, -1])` -> gross profit and factor `inf`;
- two ten-value samples at opposite `1e308` magnitudes -> observed difference
  `-inf`, CI `[nan, nan]`.

Add defensible domain-magnitude bounds or stable arithmetic plus post-compute
finiteness checks. A pipeline must fail visibly before returning or persisting
non-finite statistical evidence.

### 14. [P1] Two numbered follow-ups still cannot deliver the closure they claim to own

**Files:** `00_MASTER_PROMPT_FOR_CLAUDE.md:424-432`;
`TASK-002_PHASE2_SPECIFICATION.md:409-418`;
`TASK-016_MARKET_REGIME_ENGINE.md:71-77`;
`TASK-031_REGIME_VALIDATION_COMPLETION.md:57-93,119-138`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:85-97`;
`TASK-037_MT5_EXPORT_BRIDGE.md:46-90,118-147`.

TASK-037 accepts responsibility for the real regime confusion matrix but
defines neither an OHLC/feature/predicted-regime export nor a concrete dataset
schema capable of feeding `regime_validation.classify` and
`build_confusion_matrix`. Its “e.g.” human-labelling prose is a requirement to
design a protocol later, not the executable protocol/export needed to meet its
acceptance criterion.

TASK-031 conflates the state carried by hysteresis (`confirmed`, `pending`,
`pending_count`) with the separately required transition-history buffer. The
master/spec and TASK-016 explicitly require/defer transition history as its own
deliverable. Persistent hysteresis state is necessary but is not a history of
transitions. Define representation, capacity/retention, timestamps/bar keys,
and tests. TASK-036's session-state bucket mapping also needs exact thresholds,
as noted in finding 3.

### 15. [P2] Caller-supplied “derived” dimensions can contradict the source timestamp

**File:** `analysis/performance_breakdown.py:96-110,202-240`.

If `hour_of_day` or `day_of_week` already exists, the pipeline trusts it rather
than recomputing or checking it. A row at `2026-01-01T02:00:00Z` carrying hour
`15` and day `Sunday` was accepted and grouped under those values; the actual
UTC values are hour 2 and Thursday. Recompute authoritative derived fields or
reject a mismatch. Apply the same cross-field consistency principle to
`news_state` versus `in_news_blackout`.

### 16. [P2] Journal resource limits, controlled CLI failures, and some advertised path guards remain incomplete

**Files:** `data_collection/journal_reader.py:129-214,217-288`;
`analysis/join_trade_journal.py:251-293`;
`analysis/join_news_events.py:334-374`;
`analysis/pattern_validation.py:384-393`;
`analysis/parameter_stability.py:200-205`.

The reader still materializes an arbitrarily large physical line before
truncation, retains complete validation-error dictionaries, has no file-count,
total-byte, per-line, error-count, or retained-error-payload budget, and does
not charge blank/decode-failed byte payloads against the record limit.

Hash-change and record-limit conditions raise `RuntimeError` subclasses that
the two CLIs do not catch, so expected input-integrity failures become
tracebacks. Pattern/parameter input guards and join output-output guards also
still use path strings rather than the shared file-identity check. Atomic
replacement mitigates some hard-link damage, but the documented policy is not
implemented consistently.

### 17. [P2] Several remaining statistical labels/documentation claims are inaccurate or underspecified

**Files:** `analysis/metrics.py:10-19,63-70,268-303`;
`analysis/walk_forward.py:113-142,310-339`;
`analysis/compare_releases.py:1-22`.

- `metrics.py` says `ProfitFactorResult` contains `n`; it contains only wins
  and losses, so break-even observations disappear and total sample size cannot
  be recovered from the result.
- `mean_test_expectancy_r` is an unlabelled, unweighted mean of per-window
  means. Final windows can be partial and test windows can overlap when
  `step_days < test_days`, so trades may receive unequal weight or appear more
  than once. Persist the overlap/partial-window status and define the estimand.
- `compare_releases`'s module header still says win-rate difference uses a
  bootstrap CI; it now correctly uses Newcombe-Wilson and bootstraps only
  R-expectancy.

### 18. [P2] Canonical task/history documents still contradict source and Git reality

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:328-358,506-523`;
`09_HANDOVERS/claude_to_codex/TASK-028_handover.md:192-238`;
`TASKS.md:38-46`; `TASK-033_PATTERN_VALIDATION_COMPLETION.md:54-65`;
`TASK-034_LIVE_SAFETY_WIRING.md:169-174`; commit message for `b88b63a`.

- Direct source enumeration confirms 19 `CP_Is*Array` predicates plus
  `CP_DetectHaramiArray`. TASK-033's objective is corrected, but its Evidence
  section still says `4/18` and 18 functions.
- TASKS row 40 still calls score correlation “TASK-024's deferred item,” while
  TASK-032 correctly explains it is a master-prompt requirement and TASK-024
  deferred different missing components.
- TASK-034 says it is not yet in TASKS although TASKS row 42 now registers it.
- TASK-028 says “both” remediation series despite three, and TASK-028/TASKS
  call round-3 remediation ongoing after `b88b63a` applied it. The durable
  wording is “remediation applied; pending independent review.”
- The handover ends at round 2 (`340` tests/`23` source files) and contains no
  current `b88b63a` review target; current independent results are 395 tests and
  24 mypy-checked source files.
- The commit message claims an order/deal-ID join, complete count propagation,
  and seed exposure in every persisted report; findings 2, 12, and this section
  show those claims are false.

Actual TASK-028 history contains 20 commits from registration `e37bbec` through
`b88b63a`. Update the task, ledger, follow-ups, and handover to describe one
consistent pending-review state and the actual source surface.

## Corrections independently confirmed

The following round-3 remediation items are genuinely improved or resolved:

- `parameter_stability` now has a real explicit CSV input and functioning CLI,
  hashes that input, validates finite R values and the effective giveback-
  percent range, and reports valid zero-variance bootstrap intervals.
- Seeds are now threaded correctly through baseline, giveback, performance,
  and walk-forward calculations; the prior `seed=0` substitution defect is
  fixed.
- The normal multi-bar MFE/MAE window excludes the exit-open bar.
- Baseline, comparison, and walk-forward reject reverse chronology.
- Duplicate raw bar keys are rejected (subject to canonical-time finding 7).
- `expectancy`, `profit_factor`, and the two-sample bootstrap reject ordinary
  NaN/inf operands.
- Performance breakdown has a dimension allowlist, uses `r_multiple`, and
  includes mode/news dimensions in its generic surface.
- Journal JSON numeric overflow (`1e400`) is rejected.
- News analysis rejects duplicate journal decisions and validates a
  provider-neutral nonnegative integer importance field.
- Formula sanitization now reaches the previously missed text-bearing CSV
  exporters.
- CSV writes use atomic replacement (subject to UTF-8 finding 6).
- Monte Carlo JSON now carries scenario-bound model/caveat semantics.
- Giveback helped-rate names now distinguish conditional and full-cohort rates.
- The core pattern module/notebook/TASK-028 count is corrected to 20 total,
  four ported, 16 remaining.
- The clean-install documentation now points to the lock file, and Ruff format
  is a declared gate.

## Independent verification run

- Full suite: **395 passed in 29.51s**.
- Ruff lint: **All checks passed**.
- Ruff format check: **59 files already formatted**.
- mypy: **Success, no issues in 24 source files**.
- All 11 notebooks executed from the registered `themba-python-lab` kernel,
  each exit 0.
- `git diff --check fd07473..b88b63a`: clean.
- No secret-like credential material was added by the commit.
- The commit changes no path under `01_BASELINE/`.
- `01_BASELINE/EA_V637` is byte-identical to `baseline-v637`: EA blob
  `26018c013b60e371c112cea4f57552884d1e6902`, `IDENTITY.md` blob
  `5bc1a9b4a3198f5575d9efc35ad723242ac4b2d6`.
- `01_BASELINE/EA_V811` is byte-identical to `baseline-v811`: EA blob
  `f0644ad8a3ce8f7471d3e3ed8393c375977ac551`, `IDENTITY.md` blob
  `e1ba7a7b741969d96b07db179edd9dfa82c0b44a`.

Green automation does not invalidate the counterexamples above; several tests
currently encode the defect (notably null journal order IDs and zero-duration
MFE), while other required deliverables have no test at all.

## Required disposition

**CHANGES REQUESTED.** Do not merge or mark TASK-028 complete at `b88b63a`.
Resolve every P0/P1 item, add regression/integration tests for the concrete
counterexamples, give missing real-data inputs executable numbered owners,
correct the canonical history, and request another independent review.
