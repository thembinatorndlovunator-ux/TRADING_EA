# Claude → Codex handover — TASK-028 (Python statistical laboratory, part 1)

**Workflow note (explicit, per the user's own instruction for this task):**
this task is a deliberate test of the hybrid Claude-Code-builds /
Codex-audits workflow — Claude Code sketched the architecture, mapped the
dependencies, and built the primary scripts + tests; **Codex's job here is
to act as a strict code auditor: generate exhaustive unit tests beyond
what Claude wrote, and find fringe edge cases or security oversights
Claude skimmed past.** This is not a routine "review when budget allows"
note — it is the actual point of this task's second half.

## What this task is

The first real implementation increment of the Python/Jupyter analysis
layer Codex itself specified in `TASK-028_PYTHON_STATISTICAL_LAB.md`:
five shared modules (`schema.py`, `time_utils.py`, `metrics.py`,
`resampling.py`, `report_metadata.py`), one data-collection module
(`journal_reader.py`), the first of nine required scripts
(`join_trade_journal.py`, complete), one demo notebook (not one of the
ten required — proves the paired-pipeline pattern), and 70 tests, all
under `03_SOURCE_CODE/Python/`. Full detail in
`TASK-028_PYTHON_STATISTICAL_LAB.md`'s "Implementation notes (Claude, part
1 of N)" section.

## What to audit — be adversarial, not confirmatory

1. **Security / injection surface:**
   - `data_collection/journal_reader.py` reads arbitrary `.jsonl` files
     from a caller-supplied directory via `Path.glob` — check for path
     traversal risk if `directory` or the glob pattern were ever
     attacker-influenced (currently always caller-controlled, but confirm
     there's no way a malicious journal filename escapes the intended
     directory).
   - `analysis/report_metadata.py`'s `capture_git_commit` shells out via
     `subprocess.run(["git", ...])` — confirm `cwd` is never
     attacker-controlled in a way that could redirect to an unintended
     repository, and that argument lists (not shell strings) are used
     throughout (they are, but verify no `shell=True` was missed).
   - `analysis/schema.py`'s pydantic model uses `extra="forbid"` — confirm
     this actually blocks unexpected keys from a malformed/adversarial
     journal line rather than silently ignoring them (Claude believes it
     does, based on pydantic v2 semantics, but did not write a fuzzer to
     prove it against arbitrary malformed input beyond the explicit test
     cases in `test_schema.py`).
   - No credentials, API keys, or account numbers appear anywhere in this
     increment — confirm by grep, don't just trust this claim.

2. **Edge cases Claude's 70 tests may have missed:**
   - Extremely large journal files / many-GB directories (this
     implementation reads whole files into memory line-by-line, not
     streamed against a size cap — is that acceptable given expected
     journal sizes, or does it need a guard?).
   - Unicode/encoding edge cases in journal content (non-ASCII strategy
     names, emoji in a `setup` string, byte-order-mark at file start).
   - Concurrent writes: `DecisionJournal.mqh`'s `DJ_AppendDecision` could
     in principle be appending to a file this reader is mid-read of (both
     on a running demo terminal) — is a partial last line handled
     correctly (Claude's `_read_lines_from_file` reads line-by-line via a
     text-mode file handle; a mid-write torn last line would currently
     surface as a `ParseError`, which seems correct but wasn't explicitly
     tested).
   - `bootstrap_confidence_interval`'s `n_resamples` has no upper bound
     enforced — a caller passing an unreasonably large value has no
     safety net against a very long-running/memory-heavy call.
   - Timezone edge cases beyond what's tested: leap seconds, a
     `timestamp_utc` string with fractional seconds (`DJ_FormatIso8601Utc`
     never emits these today, but a future MQL5 change could).
   - `find_duplicate_signal_ids`/`find_duplicate_timestamp_symbol` — what
     happens with a dataset large enough that pandas' `duplicated()`
     memory behavior matters? Not tested at scale.

3. **The stated cross-layer finding** — independently confirm (don't just
   trust the task file's claim) that `ThembaAdaptiveIntradayEA.mq5` really
   never sets `decision.market_family`/`decision.intraday_mode` by
   re-reading that file yourself, then confirm the Python schema really
   does reject an empty string for both (it's a `Literal["METAL",
   "SYNTHETIC"]`/`Literal["SCALP", "DAY_TRADE"]` in `schema.py`).

4. **Reproducibility contract compliance** — check each of the 7 numbered
   rules in `TASK-028_PYTHON_STATISTICAL_LAB.md`'s "Reproducibility
   contract" section against the actual code, not just Claude's own
   claims about compliance.

5. **Test quality, not just test count** — 70 passing tests is not itself
   evidence of correctness if the tests are shallow or tautological;
   spot-check at least `test_metrics.py`'s Wilson-interval algebraic
   properties (`test_wilson_ci_all_wins_upper_bound_is_exactly_one`, etc.)
   by re-deriving the algebra yourself, and `test_resampling.py`'s
   isolation-from-global-state claim by trying to break it.

## Environment to reproduce this yourself

```
cd C:\TradingProjects\Themba_EA_Improvement_Lab
python -m venv .venv   # if not already present (.venv/ is gitignored)
.venv\Scripts\python.exe -m pip install -r 03_SOURCE_CODE\Python\requirements-lock.txt
cd 03_SOURCE_CODE\Python
..\..\.venv\Scripts\python.exe -m pytest -v
..\..\.venv\Scripts\python.exe -m ruff check .
..\..\.venv\Scripts\python.exe -m ruff format --check .
..\..\.venv\Scripts\python.exe -m mypy analysis data_collection --ignore-missing-imports
```

**Fixed, 2026-07-22 Codex review finding (third round):** this previously
installed from `requirements.txt` (the direct-dependency intent list),
never actually using `requirements-lock.txt` (the real `pip freeze` of
the exact tested transitive closure) for the one thing it exists to do
-- give a reproducible install. Also previously undeclared: `ruff format`
is now a real, run gate (see `pyproject.toml`'s `[tool.ruff]` comment).

## Files in this task

New: `03_SOURCE_CODE/Python/` (full tree: `analysis/`, `data_collection/`,
`news_connectors/` (empty placeholder), `notebooks/`, `tests/`,
`pyproject.toml`), this file. Modified: `TASK-028_PYTHON_STATISTICAL_LAB.md`
(Claude's implementation-notes addendum), `TASKS.md`, `requirements.txt`
(added `pytest`, `nbformat`, `nbclient`, `ipykernel`). No file under
`01_BASELINE/` touched. No MQL5 file touched.

---

## UPDATE — all 9 scripts + 10 notebooks now complete (parts 2-7)

Everything below this line was added in later commits on this same
branch, after the initial handover above (which only covered part 1:
the shared foundation + `join_trade_journal.py`). The audit points above
still apply to those first modules; this section adds what to check in
the newer ones.

**What's new:** `calculate_mfe_mae.py`, `analyse_giveback.py`,
`analyse_baseline.py`, `join_news_events.py`, `walk_forward.py`,
`monte_carlo.py`, `pattern_validation.py`, `compare_releases.py` (all 9
required scripts now exist), plus a bonus `regime_validation.py`
(**does NOT close TASK-016's deferred item** — only a partial,
formula-level port; see the "UPDATE" section far below for the
correction and the follow-up task this was split into), plus all 10
required notebooks (each executed for real via `jupyter execute`, not
hand-simulated). Test count at the time of this part-2 update was 196 —
see the bottom-of-file update for the current, actual count; do not
trust this number as current.

### Additional things to audit, be adversarial

1. **The `exit_simulation.py` ports (V637/V811 giveback models)** — these
   are safety-adjacent (they inform whether a not-yet-enabled MQL5
   feature should ever be enabled). Independently re-derive the algebra
   in `should_giveback_close_v637`/`v811` against `ExitManager.mqh`'s
   actual source, don't just trust that the hand-verified test cases
   were copied correctly.
2. **The sign convention in `analyse_giveback.py`'s `r_diff`** — Claude's
   own working caught and fixed a sign-flip bug here mid-session (the
   first draft computed `actual_final_r - trigger_r` instead of
   `trigger_r - actual_final_r`, inverting the meaning of "the guard
   would have helped"). Confirm the FINAL code and its tests are
   internally consistent — this is exactly the kind of subtle,
   easy-to-miss error a strict second reviewer should specifically hunt
   for elsewhere in this codebase too.
3. **`pattern_validation.py`'s array-index convention** — it deliberately
   uses the MQL5 "index 0 = newest" convention, opposite of a typical
   ascending-time DataFrame. Confirm no caller (now or in a future
   notebook) accidentally passes chronologically-ascending arrays
   without reversing them first — this would silently invert which bar
   is "current" vs "prior" in every pattern check.
4. **`regime_validation.py`'s scope-narrowing** — confirm the claim that
   accepting `swing_agreement`/`direction_agree` as inputs (rather than
   computing them from `MarketStructure.mqh`-equivalent logic) is
   clearly and honestly flagged everywhere it matters, not quietly
   presented as a full regime-engine validation.
5. **`compare_releases.py`'s two-sample bootstrap independence claim** —
   confirm that deriving the candidate stream's seed as `seed + 1` (not
   a second independently-chosen seed) is actually sufficient to avoid
   correlated draws between the two resampling streams; if you know a
   reason this specific derivation could still correlate them, that
   would be a valuable find.
6. **Every notebook's synthetic fixture matches its script's own test
   fixture "by eye" copy-paste** — confirm none of the 10 notebooks
   silently drifted from the numbers actually verified in the
   corresponding `tests/test_*.py` file (a copy-paste transcription slip
   between a notebook and its test file would be easy to miss without
   deliberately diffing them).
7. **Compile/run evidence:** re-run
   `cd 03_SOURCE_CODE/Python && pytest -v` yourself and independently
   re-execute at least a few notebooks via
   `jupyter execute --kernel_name=<your kernel> notebooks/<NN>_*.ipynb`
   to confirm the pass count and notebook exit codes are real, not just
   asserted in the task file. (This section's own "196 passed"/"all 10
   notebooks exit 0" claims are now stale — see the UPDATE below for the
   current state.)

---

## UPDATE — second independent review round resolved (2026-07-22)

Everything below this line covers the remediation of your own second
review pass (`09_HANDOVERS/codex_to_claude/TASK-028_review.md`, updated
in place, 16 findings: 2 P0/11 P1/3 P2). Full detail in
`TASK-028_PYTHON_STATISTICAL_LAB.md`'s "Implementation notes (Claude,
part 4 of N)" section — read that section for the complete list; it is
not duplicated here.

**Current, real state (verify independently, don't trust this line):**
`pytest -q` → 340 passed. `ruff check .` → all checks passed. `mypy
analysis data_collection --ignore-missing-imports` → success, no issues
in 23 source files (first type-check pass this project has ever run).
All 11 notebooks re-executed via `jupyter execute`, all exit 0.

### What to specifically re-audit this round

1. **The paired-pipeline fixes** — `analysis/performance_breakdown.py`
   and `analysis/parameter_stability.py` are new. Confirm they are
   actually real, general-purpose pipelines (not notebook logic merely
   relocated with the same narrow shape) and that `parameter_stability`'s
   full-path-set convention is correctly implemented, not just
   correctly described in a comment.
2. **The walk-forward window-anchor fix** — re-derive
   `test_windows_hand_computed_with_purged_boundaries`'s hand trace
   yourself; this is exactly the kind of off-by-one-in-spirit bug a
   second reviewer should independently re-verify, not accept on faith.
3. **The Newcombe-Wilson two-proportion interval**
   (`metrics.wilson_diff_confidence_interval`) — re-derive the formula
   independently and check it against a source you trust; this replaces
   a bootstrap method your own review found degenerate, so it is worth
   confirming the replacement is itself correct, not just different.
4. **The bar-alignment requirement in `calculate_mfe_mae.py`** — confirm
   `NoBarsInWindowError` really is now structurally unreachable (as
   claimed in `trade_math.py`'s own updated docstring) given the new
   alignment check, and that this was an intentional, disclosed
   consequence, not an accidental dead branch.
5. **Everywhere `sanitize_for_csv` was and was NOT applied** — confirm
   every CSV export carrying caller-controlled journal strings is
   covered (only `join_trade_journal.py` and `join_news_events.py` were
   identified this round); check whether any other export site was
   missed.
6. **The residual, disclosed gaps** — `ea_version`/`data_source` are only
   CLI-wired in `analyse_baseline.py`/`compare_releases.py`, not the
   other 7 scripts; TASK-036/037/038 are registered but not started.
   Confirm these are accurately disclosed as incomplete, not
   overclaimed.

---

## UPDATE — third independent review round resolved (2026-07-22)

**Added, 2026-07-22 Codex review finding (fourth round): this handover
previously ended at the second review round, with no update reflecting
round 3's remediation or round 4's review target at all -- both closed
here.**

Everything in this section covers the remediation of your third review
pass (`09_HANDOVERS/codex_to_claude/TASK-028_review.md`, updated in
place, 17 findings: 3 P0/10 P1/4 P2, reviewed against HEAD `fd07473`),
committed as `b88b63a`. Full detail in that commit's own message and in
`TASK-028_PYTHON_STATISTICAL_LAB.md`'s Reviewer section — not duplicated
here. Highlights: `join_signal_to_outcome.py` (new, the durable
journal-decision-to-trade-outcome join); seed-threading fixed
project-wide (`seed or 42` silently dropped `seed=0`); a real
look-ahead regression in `trade_math.compute_mfe_mae` from round 2's own
fix, corrected; `ruff format` declared and run as a real gate (46 files
reformatted); numerous task-ledger/canonical-history corrections.

**Current, real state at that commit:** 395 tests passing, ruff (incl.
`ruff format`) and mypy both clean, all 11 notebooks re-executed.

## UPDATE — fourth independent review round resolved (2026-07-22)

Everything in this section covers the remediation of your fourth review
pass (`09_HANDOVERS/codex_to_claude/TASK-028_review.md`, updated in
place, 18 findings: 3 P0/11 P1/4 P2, reviewed against HEAD `b88b63a`).
Full detail in `TASK-028_PYTHON_STATISTICAL_LAB.md`'s Reviewer section
and in the branch's commit history — not duplicated here.

**What changed this round (highlights, not exhaustive):**

1. **Required deliverables that were still absent, now built:**
   `metrics.compute_equity_peak_giveback` (the master-prompt-required
   "Equity-peak giveback" metric, ported from
   `TASK-002_PHASE2_SPECIFICATION.md`'s own arm/trigger formula) and the
   remaining `TEST_PLAN.md` baseline-comparison minimum surface
   (recovery factor, longest losing streak, average winner/loser,
   duration, trades/day), wired into `analyse_baseline.py`. A real
   session/mode/news OUTCOME breakdown (win rate/expectancy by
   `session_state`/`intraday_mode`/`news_state`/`in_news_blackout`) on
   clearly-labelled synthetic data in notebook 04 and
   `tests/test_performance_breakdown.py` — the dimensions already existed
   in `performance_breakdown.py`, only the demonstration/test was
   missing. Spread/slippage cost-scenario SENSITIVITY analysis remains a
   disclosed, separate, still-open deliverable -- not attempted this
   round.
2. **`join_signal_to_outcome.py` redesigned** to fix several integrity
   defects your review found: a null/blank journal `order_id` is now
   correctly filtered as a normal "unsubmitted decision" instead of
   aborting the entire journal; `deal_id` is now actually read and
   validated (null/duplicate checks, matching `trade_id`); durable
   identifiers (`order_id`/`deal_id`/`trade_id`) are read as `str` via a
   new `dtype` parameter on `read_csv_with_required_columns`, never
   pandas' inferred numeric type (closes the float64-collapse and
   leading-zero-loss counterexamples); shared fields (e.g. `symbol`)
   between journal and trade records now raise a row-level conflict error
   on disagreement instead of silently letting the trade row win;
   partial fills are aggregated into ONE output row per `order_id`
   (position), not one row per fill, so a downstream statistical
   pipeline no longer double-counts correlated fills as independent
   observations.
3. **Numerous smaller correctness/provenance fixes:** derived-sidecar
   path collisions in `join_news_events.py`/`join_trade_journal.py`
   fixed by deriving every implicit path before the collision check
   runs; the hash/re-hash race in `join_news_events.py` fixed (the
   "post-parse" hash previously ran before the news CSV was actually
   read); the atomic CSV writer's missing UTF-8 encoding fixed; the
   MFE/MAE same-bar case now correctly rejected as unmeasurable at bar
   resolution instead of using the exit bar's full contaminated range;
   duplicate-bar checks moved to run after UTC normalization;
   `parameter_stability.py`'s R-path CSV schema hardened (blank
   path_id, duplicate/fractional/negative bar_index, missing index 0,
   nonzero entry R all now rejected); giveback/news/pattern numeric
   controls validated instead of silently clamped;
   `compare_releases.py`'s comparability contract strengthened
   (mandatory shared `period_start`/`period_end` window instead of a
   weaker overlap check, role-specific broker/timeframe/modelling_mode/
   set_file manifest fields cross-checked for equality, role-preserving
   per-dataset hashes); provenance (`spread_note`/`slippage_note`) now
   threaded through every pipeline that persists metadata;
   resample/confidence config now exposed and persisted in
   `walk_forward.py`/`performance_breakdown.py`/`analyse_giveback.py`;
   post-compute finiteness checks added to `metrics.py`/
   `compare_releases.py` (sums of individually-finite values can still
   overflow); a caller-supplied `hour_of_day`/`day_of_week` is now always
   recomputed from `entry_time`, never trusted; journal-reader hardening
   (a single oversized physical line is now bounded while reading, not
   just when retained in an error record; `ValidationError.raw_record`
   size-capped; CLI `RuntimeError`/`JournalReaderLimitError` handling
   added to `join_trade_journal.py`/`join_news_events.py`); TASK-031/
   033/034/035/036/037 task-ledger corrections (transition-history
   buffer distinguished from hysteresis state, `session_state` bucket
   thresholds defined, chart-pattern export added to TASK-037's scope,
   score-correlation misattribution to TASK-024 corrected throughout).

**Current, real state (verify independently, don't trust this line):**
459 tests passing, `ruff check .` all checks passed, `ruff format
--check .` all files already formatted, `mypy analysis data_collection
--ignore-missing-imports` success (24 source files). All 11 notebooks
re-executed via `jupyter execute`, all exit 0.

### What to specifically re-audit this round

1. **The `join_signal_to_outcome.py` redesign** — this is the highest-risk
   change: re-derive the partial-fill aggregation logic by hand against
   `tests/test_join_signal_to_outcome.py`'s own fixtures, and confirm the
   `dtype=str` fix actually prevents the float64-collapse counterexample
   (a test for this exists — verify it actually exercises the bug, not
   just the fix).
2. **`compute_equity_peak_giveback`'s formula** — this is a genuinely new,
   somewhat interpretive metric (TASK-002's spec gives an exact formula
   for the DAILY-resetting variant; this module applies it at ACCOUNT
   scope since no daily-reset intraday equity data exists yet). Confirm
   the arm/trigger/re-arm state machine matches the spec's intent, and
   that the "BALANCE-based, not equity" caveat is applied consistently
   with the rest of `analyse_baseline.py`.
3. **`compare_releases.py`'s now-mandatory `period_start`/`period_end`** —
   confirm every trade in both datasets is actually checked against the
   window (not just the reported data-driven period), and that this
   closes the "touching ranges" counterexample your review reproduced.
4. **The journal-reader line-length cap** — confirm the
   `readline(MAX_LINE_BYTES + 1)` approach genuinely bounds memory for an
   oversized line with no trailing newline, and that subsequent lines in
   the same file are still read correctly afterward (not desynced).

## UPDATE — fifth independent review round, remediation IN PROGRESS (2026-07-22)

**Correction first (2026-07-22 Codex review finding, fifth round, finding
18): your fifth review read the fourth-round update above as claiming
"the remaining minimum comparison surface is now built" and that
"giveback resampling controls are exposed" — both disproven by findings 1
and 10 of that same review. Neither claim was intended that broadly (item
1 above only ever claimed `analyse_baseline.py`'s OWN single-dataset
surface, and item 3 of the "what changed" list only claimed
`walk_forward.py`/`performance_breakdown.py` exposure, not
`analyse_giveback.py`/`parameter_stability.py`), but the wording was not
careful enough to prevent that reading, and neither claim's real scope
was ever true for `compare_releases.py`'s side-by-side surface. This
section corrects the record rather than re-editing the prior claims in
place.**

Your fifth review (18 findings: 3 P0/11 P1/4 P2, reviewed against
`750443d`) is being remediated with regression tests per finding. As of
this update, resolved:

- **Findings 2/4/5 (all `join_signal_to_outcome.py`):** `deal_id` is no
  longer compared as a journal/trade shared-field invariant (it is
  fill-scoped, a journal decision legitimately has none yet) — this
  closes both the false-conflict-on-real-deal_id and the
  rejected-second-partial-fill counterexamples your review reproduced. A
  `direction`/`is_long` cross-schema invariant check was added (a
  probe with `direction=BUY`/`is_long=False` previously joined
  successfully). A whole position is now rejected as a unit if any
  constituent fill fails integrity, not just the literally-conflicting
  fill. The validated numeric `profit` series is now actually assigned
  back before summation (string profits `"30"`/`"20"` now correctly sum
  to `50.0`, not `3020.0`). Per-fill fields with no defined
  position-level aggregation (`entry_price`/`exit_price`/`stop_price`/
  `r_multiple`) are now explicitly `None` for a genuine multi-fill
  position instead of silently leaking the first fill's value. The
  sidecar-overwrite defect (errors_json derived after the collision
  check) is fixed via the same derive-before-check pattern already used
  elsewhere. Identity semantics (`order_id` = MT5 position ticket,
  `deal_id` = deal ticket, `trade_id` = this project's own per-fill CSV
  row identity) are now stated explicitly in the module docstring.
- **Finding 3 (session/mode/news):** the source-invalid
  `ratio >= 0.5` → `"OPEN"` / else → `"CLOSED"` mapping (which mislabelled
  pre-open time as open and turned a genuine `SN_GetSessionMinutesRemaining`
  data failure into a fabricated closed observation) is replaced by
  `SESSION_TIME_REMAINING_HIGH`/`LOW`/`UNKNOWN`, honestly describing what
  the ratio actually measures. Notebook 04 now runs the REAL composed
  chain (`join_news_events.py` → `join_signal_to_outcome.py` →
  `performance_breakdown.py`) against synthetic-but-realistic fixtures
  instead of a single hand-labelled "already unified" CSV. `news_state`
  still has no defined real vocabulary — the breakdown now groups by the
  independently-computed `in_news_blackout` instead of inventing one. The
  still-unowned `market_family`/`intraday_mode` mode-router/classifier gap
  is now named explicitly in `TASK-036_JOURNAL_PRODUCER_COMPLETION.md`
  rather than silently assumed to exist.
- **Finding 1 (equity-giveback/comparison mislabeling):**
  `compute_equity_peak_giveback` is renamed to `compute_balance_peak_giveback`
  and its docstring now states explicitly why it is NOT either
  master-prompt-required equity-peak-giveback metric.
  `compare_releases.py` now computes the full `TEST_PLAN.md` side-by-side
  surface (profit, profit factor, drawdowns, recovery, giveback, streaks,
  duration, frequency) for both datasets via a shared
  `analyse_baseline.compute_trade_summary`, returned as
  `baseline_summary`/`candidate_summary`/`surface_diff`, plus an explicit
  `surface_not_covered` field naming exactly which parts (MFE/MAE,
  dimensional breakdowns, cost sensitivity, real equity-based giveback)
  are still missing and which task owns closing each gap.
  `TASK-037_MT5_EXPORT_BRIDGE.md` gained five new Specification items
  (account equity-tick export, cost-scenario export, OHLC/R-path export,
  session/news evidence export, and the composed end-to-end run) so every
  one of those gaps now has a concrete numbered owner.
- **Finding 8 (overflow gaps):** `expectancy`'s variance calculation,
  `bootstrap_confidence_interval`, `compute_max_drawdown`, and
  `compute_balance_peak_giveback` (in `metrics.py`), `run_monte_carlo`
  (aggregate mean/CI overflow across resamples), and
  `parameter_stability.sweep_giveback_percent`'s mean-r-diff aggregation
  all now explicitly reject a finite-inputs-but-overflowing-result, each
  with a regression test reproducing the review's own counterexample.
- **Finding 13 (net-P/L contradiction):** `analyse_baseline.py`'s
  docstring no longer ASSERTS that an MT5 Deals export's profit column
  normally already nets commission/swap — it now states this as a
  REQUIREMENT on whatever produces `trades_csv`, and
  `TASK-037_MT5_EXPORT_BRIDGE.md`'s Specification item 1 now requires
  specifying and testing the actual net-P/L aggregation formula against
  real MT5 Deals fields before the bridge is accepted.

**Still pending (not yet remediated):** findings 6, 7, 9, 10, 11, 12, 14,
15, 16, 17, and the remainder of finding 18 (exact commit-count
verification). Do not treat this update as a request for a sixth review
yet — that request will follow once the remaining findings are resolved.

**Current, real state (verify independently, don't trust this line):**
477 tests passing, `ruff check .` all checks passed, `ruff format
--check .` all files already formatted, `mypy analysis data_collection
--ignore-missing-imports` success (24 source files). All 11 notebooks
re-executed via `jupyter execute`, all exit 0.
