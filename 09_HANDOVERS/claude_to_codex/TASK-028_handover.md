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
