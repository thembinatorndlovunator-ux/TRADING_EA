# Claude → Codex handover — TASK-028 round 7 remediation

**Supersedes, for CURRENT status, `TASK-028_handover.md`'s own final
"UPDATE" section** (which accurately reflects round 6's state at the time
it was written, including its own "do not treat this as a request for a
seventh review" line — that line is now stale by design: the seventh
review it was declining to request has since happened, in full, and this
file is its resolution record). That file is left unedited as an honest
historical snapshot; this one is the current one.

## What happened

Round 6 closed with 3 P0s intentionally left open pending the user's own
input (a live-EA identity correction, a genuinely-blocked equity-metrics
gap, and unowned new feature scope). The user reviewed all three and
directed: **"do everything now, finish all the tasks, then we do a codex
review after everything is done."** Under that directive, this session
built out TASK-034 (live safety wiring), TASK-036 (journal producer
completion), TASK-037 (MT5 export bridge), TASK-039 (triple top/bottom),
TASK-040 (IntradayModeRouter), TASK-041 (exit-engine wiring, partial
scope), then requested the seventh independent review the user's own
directive called for.

That review (round 7) returned **20 findings — 10 P0, 9 P1, 1 P2 —
disposition CHANGES REQUESTED**, written to
`09_HANDOVERS/codex_to_claude/TASK-028_review.md`. **Corrected, 2026-07-27
(Codex round-8 P2 finding 22): the line below previously read "All 20 are
now resolved" with no qualification, contradicting this same document's
own findings 12/13/17 (each of which names a retained, bounded,
deliberately-out-of-scope sub-item) and its own "What Claude did NOT do
this round" section further down. The accurate claim is narrower: every
finding's PRIMARY defect got a real fix, a regression test, and a verified
compile/test run; several also retain a named, bounded follow-up
explicitly NOT claimed closed here (see "What Claude did NOT do this
round" below for the exhaustive list).** Every finding got: a real fix
(never a workaround or a silenced check) for its primary defect, a
regression test reproducing the EXACT counterexample the review reported,
and either a clean MetaEditor compile (0 errors, 0 warnings) or a passing
Python test run, verified before committing — matching this project's own
established per-round discipline exactly.

## Verification evidence

- **MQL5:** every commit below that touched `.mq5`/`.mqh` files was
  compiled via MetaEditor64.exe before committing; build artifacts
  (`.ex5`) and per-commit logs were not retained (they never have been in
  this project), but a **full, current, consolidated compile of the EA
  and all 38 `Test_*.mq5`/`Export_*.mq5` scripts in
  `03_SOURCE_CODE/MQL5/Scripts/`** — not just this round's own touched
  files — is retained at
  `09_HANDOVERS/compile_evidence/TASK-028_round7_full_compile_evidence_2026-07-22.txt`,
  recording the exact repo commit it was generated against and the full
  `Result: N errors, N warnings` line for every one. All 39 compile
  clean. See `09_HANDOVERS/compile_evidence/README.md` for the retention
  convention this establishes going forward (this round's own P1 finding
  19).
- **Python:** the full `pytest` suite passes at every commit below;
  by the final P1 fix (finding 17) it stood at **694 passed, 0 failed**.
  `ruff`/`ruff format`/`mypy` were not re-run as a final gate this round
  (a genuine gap, not silently claimed clean) — worth doing before
  merge, but not repeated per-commit this round the way the MQL5 compile
  and pytest runs were.

## Findings resolved, by commit

**P0 (10):**

1. **IntentManager create-if-absent race** — `IM_EnsureInitialized`
   performs the bootstrap exactly once from `OnInit`; `IM_BeginIntent`
   no longer re-bootstraps on its own hot path. `IM_ReconcileOnRestart`
   gained a still-pending-order check via a new
   `IM_HasMatchingPendingOrder`.
2. **Journal-to-history schema/event mismatch** — the async-fill
   follow-up record was schema-invalid (wrong direction/empty
   market_family); rather than patch each defect, replaced the
   journal-write with log-only `LogAsyncFillResolution`, naming a real
   schema-correct follow-up as future work instead of inventing one
   under pressure.
3. **Live order path missing hard-risk-policy pieces** — added
   `ComputeOwnMagicOpenRiskCash` (own-magic total-open-risk cap, gate 5b)
   and an unconditional `risk_cap_percent` enforcement in
   `OM_CalculateVolume` (previously only checked in the
   widened-to-minimum branch).
4. **MT5-calendar decode/timing bugs** — `MTC_DecodeValue` now divides by
   the documented fixed `1,000,000` scale (not `digits`-dependent);
   `MTC_FetchEvents` fixed a UTC/server-time double-shift; `event_id` now
   uses the per-occurrence `values[i].id`, not the reusable
   `event_id`.
5. **News fail-safe gaps** — `FEP_LooksLikeJsonArray` rejects a
   non-array feed response before parsing (previously could silently
   read a malformed feed as "no events").
6. **IntradayModeRouter not implementing the canonical spec** —
   full rewrite: `IMR_ComputeModeScore` (weighted 4-component formula,
   fail-closed under 2 of 4 available), `IMR_ApplyModeHysteresis`
   (0.60/0.40 thresholds, neutral-band persistence, gating override),
   `IMR_IsCandidateConsistentWithMode` (the stage-4 post-hoc check that
   makes `intraday_mode` actually route behavior, not stay
   journal-only). One stated, bounded deviation: hysteresis confirms
   across 2 evaluations of this module, not 2 M1 bars, since this EA has
   no independent M1-tick hook.
7. **Regime fail-open / non-journaled failures** — `JournalDataFailureDecision`
   now journals a zero-confidence `TRANSITION_OR_UNCERTAIN` record with
   an immediate hysteresis bypass at all 3 early-return points in
   `EvaluateAndJournal`. `Test_RegimeGateComposer.mq5` scenario 5's own
   assertion was itself proven wrong against the real hysteresis state
   machine and corrected after a hand-trace.
8. **End-of-day closure / exit-management ordering** — `OnTick`
   reordered: boundary close first (every tick), a persistent
   (stateless, time-based) post-boundary entry lock, tick-sensitive exit
   management (`ManageOpenPositions`) now runs every tick instead of
   once per bar. `OM_ClosePosition`/`ICM_CloseAllOwnedPositions` now
   require broker-confirmed `TRADE_RETCODE_DONE`, not `PLACED`. A
   session-calendar failure no longer coerces to "duration exceeded" for
   the day-trade time stop.
9. **`Export_TradeHistory` multi-fill/reversal/cost/stop bugs** —
   extracted a new pure module, `TradeHistoryAggregator.mqh`
   (`TA_ProcessDeal`), tracking each `position_id` as a running leg:
   volume-weighted entry price across multiple `IN` fills, prorated
   entry-side cost allocation across partial closes, the FIRST fill's
   own `DEAL_SL` as the durable original-risk stop (not the closing
   deal's, which reflects trailing). `DEAL_ENTRY_INOUT` reversals close
   the well-defined existing leg; the new reversed leg is a stated,
   bounded, warned limitation.
10. **Broker/server timestamps mislabeled UTC** — already fixed earlier
    this round via `DJ_ServerTimeToUtc`/`ServerTimeToUtc` conversions
    threaded through the journal and every export script.

**P1 (9):**

11. **Pattern export schema + triple-top/bottom geometry** — added the
    missing three-way pairwise tolerance check and a genuinely sloped
    neckline (`CPT_LinearInterpolate`) to both
    `CPT_DetectTripleTopArray`/`CPT_DetectTripleBottomArray` and their
    Python ports; wired both into `ChartPatternStrategy.mqh`'s live
    trend-breakout-retest setup for the first time.
    `Export_PatternDetectorResults.mq5` rewritten to emit the full
    matching column set (all 16 always-included patterns +
    marubozu/tweezer/three_bar_reversal) plus symbol/timestamp/OHLC/atr
    provenance columns; `run()`'s own CLI path now forwards
    `swing_depth` always and an optional `atr` column.
12. **Predicted-regime exporter fidelity** — `Export_PredictedRegime.mq5`
    rewritten as a two-pass chronological replay of the FULL gated state
    machine (low-confidence override, historically-real news-blackout
    check via `MT5CalendarProvider.mqh`, hysteresis) instead of the raw
    stateless classifier; the spread/liquidity gate remains a stated,
    bounded limitation (no historical spread series exists).
13. **Equity-tick Python consumer** — new
    `analysis/equity_curve_metrics.py`: max account-equity drawdown and
    account-peak giveback (reusing the already-curve-agnostic
    `compute_max_drawdown`/`compute_balance_peak_giveback`), plus a new
    `compute_daily_equity_peak_giveback` (the one genuinely new formula,
    resetting the peak each UTC calendar day). Closes round 6's own P0-2
    for good.
14. **Daily/weekly baseline double-counting** — `DWL_ApplyCashFlowAdjustments`
    now runs BEFORE `DWL_EnsureDailyBaseline`/`DWL_EnsureWeeklyBaseline`
    (previously after), so a fresh baseline capture no longer gets
    double-counted against cash flows it already reflects. Added
    `DEAL_TYPE_CREDIT` to the cash-flow scan, a ticket round-trip
    precision guard, `SM_SetAccountDoublesBatch` (atomic multi-field
    writes), and a missing `SM_EnsureAccountSchema()` call in `OnInit`.
    `OnTradeTransaction`'s cooldown P/L now includes `DEAL_FEE`, handles
    `DEAL_ENTRY_INOUT`, and only clears position-tracking state once a
    position is confirmed fully closed (not on a broker-side partial
    fill).
15. **Python domain-validation gaps** — `classify()` now rejects
    non-finite inputs and a zero trend-slope divisor;
    `apply_hysteresis(required_bars<=0)` now raises;
    `RegimeTransitionHistory.record_confirmed` takes an explicit
    `has_confirmed` flag so it never records a phantom transition from
    the pre-confirmation sentinel; `_direction_matches_is_long` no
    longer accepts an arbitrary numeric via `bool()`; `path_id` is now
    read as `str`; `compute_r_multiple` checks intermediate
    finiteness, not just the final ratio.
16. **Provenance/atomicity, resource ceilings** — 8 pipelines reordered
    so git-metadata capture (which can raise) happens before the result
    CSV is written, not after; 5 `combine_labeled_hashes` call sites now
    use role-qualified labels, not bare basenames;
    `journal_reader.py`'s hash now covers bytes after a decode failure
    too, its per-file error retention is bounded incrementally (not only
    after a whole file is consumed), and its candidate-path
    enumeration aborts before fully materializing an oversized
    directory; `csv_io.py`'s file-size ceiling is now enforced on the
    actual bytes read, not just a pre-read `stat()` (a TOCTOU fix).
17. **Permissive/unauthenticated conventions** — `schema.py`'s
    `news_state` is now `Literal["CLEAR", "BLACKOUT"]`, matching the live
    producer exactly; `compare_releases.py` now computes and reports an
    explicit period-coverage ratio (observed span / claimed span) instead
    of only exposing the two periods for a caller to cross-check
    manually. `parameter_stability.py`'s bar0-convention gap remains an
    honestly-disclosed, not-yet-unified follow-up (unchanged this round
    — a materially larger, separate cross-cutting task).
18. **Journal vocabulary/collision/lock/provenance** — `market_family`
    schema fixed to match the live 4-value producer exactly (also finding
    18's own subject, alongside 17); `BuildSignalId` combines
    magic+microsecond-clock for genuine collision resistance;
    `THEMBA_EA_VERSION_STRING`/`THEMBA_EA_GIT_COMMIT` replace the stale
    hard-coded version string; `DJ_AppendDecision` now retries on
    contention instead of dropping a decision the instant another
    instance holds the file handle.
19. **MQL verification-evidence retention** — established
    `09_HANDOVERS/compile_evidence/` and its own README as the going-
    forward convention; produced this round's own full, current,
    reproducible compile-evidence file (see Verification evidence above).

**P2 (1):**

20. **Canonical docs contradicting reality** — `TASK-036`'s Files-affected
    list corrected against `git show --stat 712d4c6` directly (added
    `AsyncFillCorrelator.mqh`, the 3 Routing modules, 4 test scripts;
    removed `schema.py`, which that commit never touched); `TASK-037`'s
    stale "TASK-033 not started" claim corrected; `TASK-039`'s
    internally-inconsistent chart-pattern count corrected (17 = 4 + 2 +
    10 + 1, not "11 plus cup-and-handle" = 18) and its unnamed future
    owner registered as `TASK-042`; `TASKS.md`'s own rows for
    TASK-028/034/036/037/039/040/041 updated to current, Git-verified
    status; this handover itself replaces the prior one's stale
    "don't request review" closing note.

## What Claude did NOT do this round

- Did not re-run `ruff`/`ruff format`/`mypy` as a final gate (see
  Verification evidence).
- Did not attempt `parameter_stability.py`'s cross-file bar0-convention
  unification (finding 17) or the cost-sensitivity export (finding 13's
  own remaining scope) — both named, bounded, deliberately deferred, not
  silently dropped.
- Did not run any of this against a real/demo MT5 session — this
  sandbox cannot; every export/EA fix remains verified by compile +
  hand-derived or pytest-executed regression test only.

## Requesting review

Per the user's own sprint directive ("finish all the tasks, then we do a
codex review after everything is done, then from the review we correct
and make any solid adjustments needed then we launch the EA on MT5"),
this handover **is** the request for the next review round, unlike the
prior handover's own closing note.
