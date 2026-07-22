# TASK-028 independent code review - round 6

**Disposition: CHANGES REQUESTED**

**Review target:** branch `claude/task-028-python-statistical-lab`, commit
`971e543798ecacafae413810fc2cb8da2f65351a` (`971e543`), independently
reviewed across the complete 13-commit remediation range from
`750443d8ac1a270e289663b330b0618d2f4b716f` (`750443d`) through current
HEAD. The review re-ran the Python gates and notebooks, exercised adversarial
counterexamples, inspected the live MQL source and task ownership, checked Git
history, and compared both immutable baseline directories with their tags.

The remediation contains real improvements, and every declared automated gate
is green. It does **not** resolve all 18 round-5 findings. I found **17 remaining
findings: 3 P0, 12 P1, and 2 P2**. Several are the exact class of counterexample
the canonical documents now claim has a regression test and is fully resolved.
TASK-028 is not ready to merge or close.

## Findings

### 1. [P0] The durable MT5 identity and row-grain model is still invalid, and real multi-fill output breaks both downstream analysis paths

**Files:** `03_SOURCE_CODE/Python/analysis/join_signal_to_outcome.py:15-42,91-103,161-177,221-226,368-374`;
`03_SOURCE_CODE/Python/analysis/analyse_baseline.py:26-45,168-173,230-231`;
`03_SOURCE_CODE/Python/analysis/performance_breakdown.py:81,347-353`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh:130-157,189-205`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh:193-216`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:125-152,185-191`;
`TASK-037_MT5_EXPORT_BRIDGE.md:48-77,171-179,229-265`.

The join and TASK-037 define `order_id` as `SOrderOpenResult.position_ticket`
and assert that it stays stable for the lifetime of the position. Local MQL
source obtains that value through `PositionGetTicket`, which is
`POSITION_TICKET`. MT5's documented stable lifecycle key is instead
`POSITION_IDENTIFIER`; `POSITION_TICKET` can change after a server service
re-open and, in netting mode, after reversal. Every related deal carries the
stable identity as `DEAL_POSITION_ID`. See the official
[position properties](https://www.mql5.com/en/docs/constants/tradingconstants/positionproperties)
and [deal properties](https://www.mql5.com/en/docs/constants/tradingconstants/dealproperties).
The current key can therefore split or orphan one real position.

TASK-037 also calls each `trades.csv` row a fill while requiring that same row
to contain a complete entry, exit, and net-P/L outcome. Even an ordinary closed
position has separate entry and exit deals. A fill-level file makes
`analyse_baseline` count fills as trades, corrupting win rate, streak, frequency,
and sample size. A position-level file cannot truthfully carry a single unique
fill `deal_id`. The task never defines `DEAL_ENTRY_IN/OUT/INOUT/OUT_BY` pairing,
partial-volume allocation, or allocation of commission, swap, and fees.

The Python implementation is internally incompatible as well. For a genuine
multi-fill group it deliberately sets `trade_id`, `deal_id`, and `r_multiple`
to null. `performance_breakdown` rejects null `trade_id` and any present but
non-finite/null `r_multiple`. A direct two-fill probe produced a correctly
summed position and then failed immediately when passed to the advertised
breakdown consumer. Notebook 04 contains only single-fill outcomes, so its
green execution does not cover this case.

Finally, TASK-036 permits an appended asynchronous follow-up record, while the
join rejects duplicate submitted position IDs. The task excludes the schema and
join changes needed to model an update event, and `SOrderOpenResult` does not
capture `ResultOrder()`/the request identity needed to correlate overlapping
delayed `OnTradeTransaction` events. Define separate order, stable position,
deal, and normalized-outcome identities from MQL transaction through export and
Python before this evidence path can be considered durable.

### 2. [P0] The mandatory equity, drawdown, giveback, and cost-comparison deliverables are still absent and TASK-037 cannot close them as written

**Files:** `00_MASTER_PROMPT_FOR_CLAUDE.md:836-843,1193-1222`;
`TEST_PLAN.md:9-29`; `03_SOURCE_CODE/Python/analysis/compare_releases.py:35-42,539-570`;
`TASK-002_PHASE2_SPECIFICATION.md:1078-1108`;
`TASK-037_MT5_EXPORT_BRIDGE.md:3-9,147-155,181-197,249-258`.

`compare_releases` now exposes a substantially better balance/trade summary,
but it expressly reports MFE/MAE, dimensional analysis, cost sensitivity, and
real account/daily equity giveback as not implemented. Maximum equity drawdown
is absent without even appearing in `surface_not_covered`. The master prompt
requires these measurements, including distinct account and daily-reset equity
giveback.

TASK-037 only promises to export an equity series and cost scenarios. Its
Files-affected and Out-of-scope sections exclude the missing Python consumers
and incorrectly say those consumers already exist. Acceptance requires only
that the data be produced and that it "unblocks" measurement; it never requires
either equity metric or a spread/slippage sensitivity result to be calculated.
The proposed `timestamp,equity` schema also lacks balance cash-flow events and
server-day boundary evidence required for deterministic rebasing. Historical
account-equity ticks are not reconstructible from ordinary deal history; this
needs a tester/forward recorder and an executable analysis owner. Naming a task
that can pass without producing the required result does not resolve round-5
finding 1.

### 3. [P0] Live mode classification and regime-transition evidence remain unowned, so the promised journal and nine-state validation can pass without a real source path

**Files:** `00_MASTER_PROMPT_FOR_CLAUDE.md:369-387,424-432`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:357-365,451-456`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/MarketRegimeEngine.mqh:239-292,345-400`;
`TASK-031_REGIME_VALIDATION_COMPLETION.md:113-128,177-185`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:85-124,231-248`;
`TASK-037_MT5_EXPORT_BRIDGE.md:97-126`.

TASK-036 explicitly says `market_family` and `intraday_mode` depend on a
"still-unregistered future task," yet its acceptance requires both. The master
requires a live `IntradayModeRouter`; current MQL source has no such classifier
and the EA never sets either field. TASK-031 similarly discloses that the live
regime transition-history buffer remains unregistered. The current regime
engine retains hysteresis state but no required transition log.

TASK-037 has no dependency on completion of the live news/spread gating path.
`MRE_ClassifyLive` produces the seven formula regimes, and the EA does not
compose the two override states into a live nine-state result. Consequently a
claimed real nine-state confusion run can be generated before a nine-state live
producer exists. Disclosure is useful, but it is not executable numbered
ownership and does not satisfy round-5 finding 14.

### 4. [P1] Signal/outcome integrity still accepts corrupt cross-schema values and finite fills still aggregate to infinity

**File:** `03_SOURCE_CODE/Python/analysis/join_signal_to_outcome.py:194-218,260-287,307-375`.

Three direct counterexamples remain:

- a populated journal `deal_id="WRONG"` joined a trade group containing only
  `deal_id="d1"`, because `deal_id` is excluded from all conflict checks rather
  than treated as nullable-or-membership-constrained;
- `direction=SELL, is_long="banana"` joined successfully because arbitrary
  strings are coerced to false; unrecognized directions are accepted too;
- two individually finite profits of `1e308` summed to `inf` with no row error,
  because finiteness is checked before, but not after, group aggregation.

The whole-position conflict rejection, numeric-string conversion, and nulling
of ambiguous fill fields are genuine fixes. They do not make the remaining
identity and aggregate invariants safe.

### 5. [P1] The provenance fix is not system-wide, results can still be bound to bytes that were not analyzed, and sidecars remain optional

**Files:** `03_SOURCE_CODE/Python/analysis/csv_io.py:30-76`;
`analyse_giveback.py:209-210,352-362`; `calculate_mfe_mae.py:126-127,198-220`;
`compare_releases.py:107,612-640`; `join_signal_to_outcome.py:412-436`;
`monte_carlo.py:272-289`; `parameter_stability.py:159,519-525,597-603`;
`pattern_validation.py:348,419,439-445`; `performance_breakdown.py:347,360-370`;
`walk_forward.py:271,350-356`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:183-195,713-748`.

The new one-read CSV helper genuinely binds parsing and hashing where it is
used, but most persisted pipelines still parse through
`read_csv_with_required_columns` and later re-read the path inside
`build_report_metadata`. A deterministic `join_signal_to_outcome.run` probe
mutated the journal between those reads: the output contained the original
row, while its metadata hash exactly matched the replacement file. This is the
same old-analysis/new-hash race that round-5 finding 6 required the package to
eliminate.

Most CSV-producing entry points also continue to write the CSV when the JSON
sidecar is omitted. Mandatory, reproducible provenance therefore remains
separable from the result. Applying the fix to only `analyse_baseline`,
`join_trade_journal`, and `join_news_events` cannot support the canonical
"fully resolved" claim.

### 6. [P1] Journal provenance is not an exact-byte identity, and aggregate resource/path controls remain bypassable

**Files:** `03_SOURCE_CODE/Python/data_collection/journal_reader.py:47-73,191-204,225-239,247-305,344-360,398-439`;
`03_SOURCE_CODE/Python/analysis/csv_io.py:30-76,199-225`.

The journal reader opens with `utf-8-sig`, applies universal newline
translation, and hashes each decoded string after re-encoding it. Direct probes
showed that raw-byte-distinct LF, CRLF, and BOM+LF files all receive the same
digest. Distinct invalid byte streams can also collapse to the same digest when
decoding fails before decoded text reaches the hasher. The documentation's
claim that the hash represents the exact parsed bytes is therefore false; hash
the binary stream while decoding incrementally.

Only nonblank-record count and per-line size are bounded. There is no maximum
file count, total source bytes, parse-error count, or retained-error bytes. One
million retained 2,000-character errors can approach gigabytes. Whitespace-only
lines bypass the record and post-strip byte checks, and the new CSV helper reads
an entire caller-controlled file into bytes, decoded text, and a DataFrame with
no size ceiling. An outward symlink is silently skipped rather than reported as
an excluded requested source, and a directory matching `decisions_*.jsonl`
reaches the file reader and raises `PermissionError`. A nested output path under
the input journal directory is still permitted, so the earlier output-inside-
source-set class is only partially fixed.

### 7. [P1] Durable identifiers still undergo lossy numeric inference outside the specialized joins

**Files:** `03_SOURCE_CODE/Python/analysis/csv_io.py:79-119` and callers in
`analyse_giveback.py:209`, `calculate_mfe_mae.py:126`, `compare_releases.py:107`,
`monte_carlo.py:272`, `performance_breakdown.py:347`, `walk_forward.py:271`.

The generic CSV reader defaults to pandas type inference, and these callers do
not request string dtype for `trade_id`. A CSV containing IDs `001` and `1` is
loaded as integer values `1,1` and rejected as a false duplicate. Large ticket
values are exposed to the same identity-corruption class already fixed in the
specialized signal/news joins. Durable IDs need a central schema dtype rule,
not call-site-specific exceptions.

### 8. [P1] The release-comparison manifest is required syntactically but remains empty, unauthenticated caller assertion

**Files:** `03_SOURCE_CODE/Python/analysis/compare_releases.py:44-64,254-363,395-408,578-640`;
`03_SOURCE_CODE/Python/notebooks/10_baseline_vs_candidate.ipynb`.

Symbol-set equality and unequal nonempty role-manifest rejection are genuine
fixes. However, all seven required role pairs are checked only for equality,
not for nonblank values or type. A direct comparison with every pair blank
succeeded. Baseline/candidate EA version and data source remain optional and
were returned as null. Set-file names, `market_data_id`, and cost notes are
free-text assertions not bound to a manifest or source-file hash.

The claimed period remains containment only, as the module itself admits. It
does not establish that either experiment actually covered that period;
notebook 10 demonstrates the flaw by labelling one-hour samples with a full
year. Require nonblank role manifests and authenticate the set/raw-data/cost
inputs rather than treating equal empty strings or labels as evidence.

### 9. [P1] Resampling and confidence configuration is inconsistent inside one comparison artifact

**Files:** `03_SOURCE_CODE/Python/analysis/analyse_baseline.py:98-114,171-173,306-422`;
`03_SOURCE_CODE/Python/analysis/compare_releases.py:254-261,428-468,572-574`;
`03_SOURCE_CODE/Python/analysis/metrics.py:252-269`.

`compute_trade_summary` exposes `seed` but not `n_resamples` or `confidence`.
`compare_releases.run` accepts both settings for its top-level inference but
does not forward them into either nested summary. A probe with
`n_resamples=100, confidence=0.9` returned top-level 100/0.9 while nested win
rate and expectancy remained 2,000/0.95. One JSON artifact therefore reports
internally different inferential configurations. `analyse_baseline` has no CLI
controls for them, and the single-observation early return in `expectancy`
still precedes validation of supplied controls.

### 10. [P1] Finite inputs still yield non-finite derived evidence in multiple public pipelines

**Files:** `03_SOURCE_CODE/Python/analysis/compare_releases.py:471-528`;
`03_SOURCE_CODE/Python/analysis/join_signal_to_outcome.py:351-354`;
`03_SOURCE_CODE/Python/analysis/trade_math.py:18-49`;
`03_SOURCE_CODE/Python/analysis/calculate_mfe_mae.py:178-188`;
`03_SOURCE_CODE/Python/analysis/analyse_giveback.py:253-350`.

The core metric hardening is real, but public derived operations remain
unchecked. Independent probes produced:

- `surface_diff.net_profit == inf` from finite baseline/candidate summaries;
- `join_signal_to_outcome.profit == inf` from two finite fills;
- `mfe_r == inf` with no MFE/MAE row error from finite prices;
- `actual_final_r == inf` and `v637_r_diff == nan` with no giveback row error.

Some JSON writes eventually reject NaN/Infinity through `allow_nan=False`, but
CSV-only and in-memory runs return invalid evidence, and late serialization is
not a substitute for a public-boundary invariant. Post-validate every derived
aggregate or impose defensible magnitude bounds.

### 11. [P1] Parameter stability explicitly admits that the requested surface and R-path convention remain unfinished

**Files:** `profit_giveback_diagnosis_plan.md:102-120`;
`03_SOURCE_CODE/Python/analysis/parameter_stability.py:31-69,355-470`;
`03_SOURCE_CODE/Python/analysis/analyse_giveback.py:24-33,253-296`;
`03_SOURCE_CODE/Python/notebooks/02_profit_giveback_analysis.ipynb`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:713-748`; `TASKS.md:38`.

The new V8.11 `arm_r x floor_r` grid and model-domain checks are genuine.
Production source nevertheless says, in its own module documentation, that the
required V6.37 `arm_rr x giveback_percent` two-dimensional sweep is still not
implemented. It separately says the three consumers use different meanings of
bar/path index zero: pre-bar 0R, entry-bar close, and +0.5R synthetic start.
Those disclosures directly contradict the canonical claim that round-5 finding
9 is fully resolved with its counterexample regression-tested.

### 12. [P1] `longest_losing_streak` no longer means consecutive losing trades, and requested uncertainty is still absent

**Files:** `03_SOURCE_CODE/Python/analysis/analyse_baseline.py:182-228,288-302`;
`03_SOURCE_CODE/Python/tests/test_analyse_baseline.py:233-286`.

The row-order dependence was removed by replacing trades with net P/L buckets
per distinct exit timestamp. That creates a different metric. Simultaneous
profits `[-1,-1,+10]` report a longest losing streak of zero despite two losing
trades; three simultaneous losses count as one. Either define a durable trade
sequence/tie policy, report an interval/range, or rename the metric honestly.

Average winner, average loser, and duration gained subgroup counts but still
have no uncertainty, although the round-5 finding and test commentary named
both sample size and uncertainty. Standalone `trades_per_day` also retains an
active-envelope fallback; notebook 01 hand-checks that fallback rather than the
authenticated-period route.

### 13. [P1] Bar coverage improved, but the cadence contract and cross-consumer timestamp convention are not executable or reproducible

**Files:** `03_SOURCE_CODE/Python/analysis/trade_math.py:102-156,188-222`;
`calculate_mfe_mae.py:21-28,218-236`; `analyse_giveback.py:24-33,253-296,360-382`;
`TASK-037_MT5_EXPORT_BRIDGE.md:131-146,181-219,249-252`.

Ordinary missing intermediate bars are now correctly rejected. Two gaps remain:

- a finite positive cadence below pandas' timestamp resolution quantizes to
  zero and raises an uncaught `ZeroDivisionError`, because validation checks
  only finite and greater than zero;
- neither MFE/MAE nor giveback persists the declared cadence in its artifact.

More fundamentally, current MFE/MAE expects bar-open timestamps and a half-open
window, while giveback expects bar-close timestamps and an inclusive window.
Normal MT5 deals occur at tick times, not exact bar boundaries. TASK-037 says it
will choose one convention, but excludes the required Python changes and omits
`analyse_giveback` from its test/acceptance lists. It can therefore pass without
resolving the convention or real partial-bar semantics.

### 14. [P1] Thirteen required chart-pattern detectors and their validation remain outside executable numbered ownership

**Files:** `00_MASTER_PROMPT_FOR_CLAUDE.md:649-673`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/ChartPatternEngine.mqh:101,166,234,321`;
`TASK-018_CHART_PATTERN_ENGINE.md:88-103,212-217`;
`TASK-033_PATTERN_VALIDATION_COMPLETION.md:86-103,143-149`; `TASKS.md:41`.

Current source implements only double top/bottom and head-and-shoulders/inverse.
TASK-033 owns validation for those four and explicitly leaves triple top/bottom
unowned. TASK-018 additionally leaves eleven other master-required families
unowned. The master lists 17 patterns, so 13 remain. `TASKS.md` nevertheless
says TASK-033 covers "all chart patterns." That ledger statement is false and
the round-5 closure-safety gap remains.

### 15. [P1] Live news-provider selection and the news-state contract remain incomplete

**Files:** `PROJECT_RULES.md:7-8`; `NEWS_INTEGRATION_SPEC.md`;
`TASK-029_NEWS_MANAGER.md:127-132`; `TASK-034_LIVE_SAFETY_WIRING.md:79-104,164-177`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:99-124`;
`03_SOURCE_CODE/Python/analysis/performance_breakdown.py:131-185`.

Project rules require macro news for metals and `NullNewsProvider` for
synthetics. TASK-029 deferred provider selection to live-EA wiring, but
TASK-034 adds the FairEconomy provider without a metal/synthetic selection rule
or synthetic-bypass acceptance test. With `market_family` still unowned,
TASK-034 can pass while applying the macro blackout to synthetic markets.

No real `news_state` vocabulary is defined. The Python validator checks only
exact `CLEAR` and `BLACKOUT` values even though `join_news_events` produces only
the boolean flag. Direct probes accepted `BANANA`, `CLEAR `, and null alongside
`in_news_blackout=True`; tests explicitly bless arbitrary legacy values. Define
the enum and provider-routing invariant, or remove the unsupported text
dimension until its producer exists.

### 16. [P2] Notebook execution is green, but the claimed behavioral verification remains incomplete and one statistical explanation is false

**Files:** `03_SOURCE_CODE/Python/notebooks/01_baseline_trade_audit.ipynb`;
`02_profit_giveback_analysis.ipynb`; `04_session_and_news_analysis.ipynb`;
`06_parameter_stability.ipynb`; `10_baseline_vs_candidate.ipynb`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:713-748`; `TASKS.md:38`.

Notebook 01 genuinely checks several new summary fields, notebook 04 now invokes
the composed synthetic functions, and notebook 10 correctly checks the
Newcombe-Wilson method and R-difference arithmetic. However:

- notebook 10 never inspects `baseline_summary`, `candidate_summary`, or
  `surface_diff`, despite the canonical claim that the new comparison surface
  is hand-checked;
- its "total separation / no resample can straddle zero" explanation is false:
  both empirical groups support `-2.5` and `+2.5`; the exact probability
  `P(X_candidate <= X_baseline)` is approximately `0.0005724311`, not zero;
- notebook 06 exercises the old one-dimensional V6.37 sweep, not the new V8.11
  grid or missing V6.37 two-dimensional grid;
- notebook 04 manually assigns session states, never exercises `UNKNOWN`, and
  does not derive the state from the live ratio source;
- notebook 01 does not exercise the authenticated-period denominator path.

Executing successfully is not the same as regression-testing the counterexample
the canonical documentation claims each notebook now covers.

### 17. [P2] Canonical task/history documents contradict Git and each other

**Files:** `TASK-028_PYTHON_STATISTICAL_LAB.md:328-367,489-492,515-536,688-748`;
`TASKS.md:38`; `09_HANDOVERS/claude_to_codex/TASK-028_handover.md:368-462`.

The main task's earlier Commit/Reviewer sections still say three remediation
series and four review rounds, and an older implementation note still reports
four rounds and 459 tests. Its later appendix says round 5 is fully resolved
with a regression reproducing every counterexample. Finding 14's documentation-
only commit added no test, several counterexamples above remain, and the listed
round-5 commit sequence omits final documentation commit `971e543`.

`TASKS.md` reports 33 TASK-028-tagged commits. Git contains 34 from registration
commit `e37bbec` through current HEAD. The handover still ends with "remediation
IN PROGRESS," 477 tests, a pending list, and an instruction not to request round
6. These cannot all describe the same current state. Replace the stale duplicated
history with one canonical, Git-derived account and do not state that round 5 is
resolved before an independent review confirms it.

## Corrections independently confirmed

The following round-5 remediation is real, even though the package is not
complete:

- the balance-only giveback proxy is now honestly named and distinguished from
  account/daily equity metrics;
- `compare_releases` adds a broad balance/trade surface, verifies symbol-set
  equality, and rejects unequal supplied manifest pairs;
- signal/outcome aggregation converts numeric-string profit, derives the
  implicit sidecar before collision checks, excludes fill-scoped `deal_id` from
  the generic shared-field overwrite, rejects a conflicting position as one
  unit, and nulls fields with undefined multi-fill semantics;
- major overflow paths in core bootstrap/expectancy/drawdown/giveback,
  Monte Carlo, and stability helpers now fail visibly;
- V8.11 has a real two-dimensional arm/floor stability sweep and all four
  exposed model controls have domain checks;
- exposed randomized analyses generally have finite bounds and persist their
  controls, apart from the nested summary inconsistency in finding 9;
- ordinary sparse-bar gaps are rejected by both MFE/MAE and giveback;
- event IDs and join IDs are string-preserved in the specialized paths;
- the unsupported OPEN/CLOSED session interpretation was replaced with neutral
  HIGH/LOW/UNKNOWN wording, and notebook 04 now calls the actual synthetic
  news-join, outcome-join, and breakdown functions;
- TASK-034 now names the FairEconomy provider implementation and tests;
- notebook 01's new summary checks and notebook 10's Newcombe-Wilson correction
  are genuine.

## Verification performed

- Full Python suite: **532 passed**, 7 expected NumPy overflow/invalid warnings,
  in 26.60 seconds.
- Ruff lint: **all checks passed**.
- Ruff format check: **59 files already formatted**.
- mypy: **success**, 24 source files checked.
- All 11 notebooks (`00` through `10`) executed via `jupyter execute` with exit
  code 0; temporary executed copies were removed afterward.
- `git diff --check 750443d..971e543`: clean.
- Remediation range: 13 commits, 47 changed paths, no path under `01_BASELINE/`
  or `03_SOURCE_CODE/MQL5/`.
- Diff secret-assignment scan: no credential-like assignment found.
- V6.37 remains byte-identical to `baseline-v637`, including `IDENTITY.md`:
  source blob `26018c013b60e371c112cea4f57552884d1e6902`, identity blob
  `5bc1a9b4a3198f5575d9efc35ad723242ac4b2d6`.
- V8.11 remains byte-identical to `baseline-v811`, including `IDENTITY.md`:
  source blob `f0644ad8a3ce8f7471d3e3ed8393c375977ac551`, identity blob
  `e1ba7a7b741969d96b07db179edd9dfa82c0b44a`.
- The only pre-existing worktree item before this review was untracked
  `.claude/`; it was not touched.

## Required disposition

Keep TASK-028 open. Resolve every P0 and P1 above, add tests that exercise the
actual counterexamples rather than merely the normal path, and reconcile the
canonical history before requesting another independent review. In particular,
do not build the export/join contract around `POSITION_TICKET`; establish the
raw-deal and normalized-position schemas around stable MT5 lifecycle identity
first. The current package must not be described as fully resolved or ready to
merge.
