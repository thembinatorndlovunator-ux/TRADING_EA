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
.venv\Scripts\python.exe -m pip install -r requirements.txt
cd 03_SOURCE_CODE\Python
..\..\.venv\Scripts\python.exe -m pytest -v
```

## Files in this task

New: `03_SOURCE_CODE/Python/` (full tree: `analysis/`, `data_collection/`,
`news_connectors/` (empty placeholder), `notebooks/`, `tests/`,
`pyproject.toml`), this file. Modified: `TASK-028_PYTHON_STATISTICAL_LAB.md`
(Claude's implementation-notes addendum), `TASKS.md`, `requirements.txt`
(added `pytest`, `nbformat`, `nbclient`, `ipykernel`). No file under
`01_BASELINE/` touched. No MQL5 file touched.
