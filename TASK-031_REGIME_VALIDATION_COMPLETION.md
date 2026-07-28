# TASK-031 - Regime validation completion

## Objective

Complete the FORMULA-LEVEL regime-validation work TASK-016 originally
deferred and TASK-028 only partially closed: full nine-state
synthetic-fixture coverage (including the two gating overrides AND
data-failure behavior), and the gating/hysteresis logic itself.

**This task's scope explicitly EXCLUDES the confusion matrix against
real, independently-labelled evidence** (Codex review finding #2,
2026-07-22: TASK-031's first draft let its own acceptance criteria pass
with that evidence-production step still PENDING, while its Objective
simultaneously promised it -- a closure loophole). Producing that real
evidence depends on `TASK-037_MT5_EXPORT_BRIDGE.md`'s real-data exports
existing first; running `build_confusion_matrix` against real evidence
is tracked there, NOT as a silently-optional item here.

## Reason

Codex's independent review of TASK-028
(`09_HANDOVERS/codex_to_claude/TASK-028_review.md`, finding #1) found
that `TASK-028_PYTHON_STATISTICAL_LAB.md` and `TASKS.md` both claimed
`regime_validation.py` "closes TASK-016's deferred confusion-matrix
item." That claim is false: `regime_validation.py` only covers 7 of 9
regime states, accepts `swing_agreement`/`direction_agree` as
caller-supplied inputs instead of computing them, does not implement the
`NEWS_BLACKOUT`/`UNTRADEABLE_SPREAD_OR_LIQUIDITY` gating overrides,
data-failure behavior, or any hysteresis logic, and has never run a
confusion matrix against real independently-labelled evidence (none
exists in this project yet). A second Codex review pass (finding #2,
2026-07-22) further found this task's own first draft omitted
data-failure coverage entirely and let the confusion-matrix requirement
close as PENDING despite the Objective promising it -- both fixed above.

## Baseline behaviour

Neither immutable baseline EA exposes a Python-importable regime
classifier; this is new validation tooling, not a baseline-behaviour
change. `01_BASELINE/` must not be modified.

## Evidence

- `09_HANDOVERS/codex_to_claude/TASK-028_review.md` finding #1 — the
  false completion claim this task corrects.
- `TASK-016_MARKET_REGIME_ENGINE.md` — the original deferred "regime
  fixtures/confusion matrix" item.
- `03_SOURCE_CODE/Python/analysis/regime_validation.py` — existing
  partial coverage (module docstring already states its own limits
  accurately; only the two task-tracking docs overclaimed).
- `03_SOURCE_CODE/MQL5/.../MarketRegimeEngine.mqh` — the nine-state
  classifier and its gating/hysteresis logic to be fully ported.
- `03_SOURCE_CODE/MQL5/.../MarketStructure.mqh` — the bias/structure
  computation `regime_validation.py` currently takes as a caller-supplied
  input rather than computing.

## Specification

1. Extend `regime_validation.py` (or a new module) to synthetically
   fixture all nine regime states, including `NEWS_BLACKOUT` and
   `UNTRADEABLE_SPREAD_OR_LIQUIDITY` as gating overrides applied before
   the T/T_final/E/ER decision tree, matching
   `MRE_IsUntradeableSpreadOrLiquidity`'s exact predicate.
2. Add data-failure behavior coverage: synthetic fixtures for whatever
   `MarketRegimeEngine.mqh` does when its own inputs are unavailable/
   invalid (e.g. missing bar data, a `MarketStructure.mqh` read
   failure) -- re-read the MQL5 source for its actual documented
   data-failure path rather than inventing one; this was the specific
   category TASK-028 named ("nine states, gating overrides, DATA
   FAILURE, and hysteresis") that this task's first draft omitted.
3. Port the hysteresis logic (state persistence/switching behavior)
   from `MarketRegimeEngine.mqh`, with hand-traceable synthetic fixtures
   proving it does not flap on borderline inputs. **Added, 2026-07-22
   Codex review finding (third round): `MRE_ApplyHysteresis` is
   inherently STATEFUL across calls (`SRegimeHysteresisState` carries
   `pending_regime`/`pending_count`/`confirmed_regime` forward bar to
   bar) -- this task's Python port must maintain and thread the
   equivalent persistent state across a MULTI-BAR sequence of raw-regime
   reads, not just single-shot, stateless fixtures.** **Corrected,
   2026-07-22 Codex review finding (fourth round): the previous wording
   here called that multi-bar sequence "a regime transition-history
   buffer" -- that conflates two DISTINCT things. `SRegimeHysteresisState`
   is hysteresis's own small confirm/pending state, needed only for the
   classifier's OWN operation; it is NOT the separately required
   "transition history" deliverable (master prompt: "Create... A
   transition history"; TASK-016's own "Required deliverables" list
   names it alongside, not as part of, hysteresis -- see item 3a below,
   which this task also owns.** Test the hysteresis port at minimum: a
   borderline input that flips raw regime every bar (must never confirm
   a switch, `pending_count` resets each time); a genuine sustained
   switch across >= `required_bars` consecutive identical reads (must
   confirm); and the pre-first-confirmation state (`has_confirmed=false`)
   correctly reporting `TRANSITION_OR_UNCERTAIN` rather than a
   half-confirmed guess.
3a. **The transition-history buffer itself (added, 2026-07-22 Codex
    review finding, fourth round -- previously entirely unaddressed by
    this task despite being TASK-016's own explicitly-deferred item):**
    a genuine LOG of past CONFIRMED regime transitions over time --
    distinct from hysteresis's own tiny confirm/pending counter above.
    Define and port: (a) representation -- a bounded ring buffer of
    `(bar_timestamp, from_regime, to_regime)` tuples, one entry per
    CONFIRMED transition (not per bar, and not per pending/unconfirmed
    flap); (b) capacity/retention -- a fixed maximum entry count (this
    task's own design decision; state and justify the chosen number, do
    not leave it unbounded); (c) timestamps/bar keys -- each entry keyed
    to the real bar timestamp the transition was confirmed on, not a
    bar-index alone, so the buffer remains meaningful across gaps/
    resumptions; (d) hand-traceable tests proving entries are appended
    only on a genuine CONFIRMED transition (never on a pending/
    unconfirmed flap that never resolves) and that the buffer evicts its
    oldest entry once capacity is exceeded.

    **Scope boundary, stated explicitly (Codex review finding,
    2026-07-22, fifth round): this item is a PYTHON-SIDE offline
    analysis port only.** `00_MASTER_PROMPT_FOR_CLAUDE.md`'s section 6
    ("Create: `MarketRegimeEngine.mqh`... A transition history...")
    requires the transition-history buffer as part of the LIVE MQL5
    engine itself, alongside the regime enum/confidence score/reason
    string -- a genuinely separate deliverable from this task's Python
    port, which only replays/analyzes already-recorded regime sequences
    offline. This task's completion (however thorough the Python port)
    does NOT close that master-prompt line item. **The live
    `MarketRegimeEngine.mqh` transition-history buffer remains
    unregistered and unowned by any numbered task as of this writing --
    a future task must be created for it before section 6's requirement
    can be considered closed**; this task's own acceptance criteria
    below are scoped to the Python port only and must not be read as
    satisfying the live-engine requirement.
4. Decide and document whether `MarketStructure.mqh`'s bias computation
   is ported to Python in this task or remains a caller-supplied input
   for another task — either is acceptable, but the choice must be
   explicit, not silently deferred again.
5. Do NOT attempt the real-evidence confusion matrix here -- that is
   `TASK-037`'s deliverable once a real, independently-labelled regime
   dataset exists. Keep the existing "Real-data run: PENDING" convention
   in whatever this task produces.

## Files affected

- `03_SOURCE_CODE/Python/analysis/regime_validation.py` and its tests.
- Possibly a new notebook or an extension of
  `03_strategy_regime_analysis.ipynb`.
- `TASKS.md` and this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- Wiring any of this into the live EA's regime gating.
- Fabricating a "real evidence" confusion matrix from synthetic data.
- The real-evidence confusion matrix itself -- owned by `TASK-037`, not
  a deliverable of this task (see Objective).

## Risks

- Synthetic fixtures for gating/hysteresis could diverge from the live
  MQL5 behavior if hand-traced incorrectly — cross-check against
  `Test_MarketRegimeEngine.mq5` where one exists.
- Overclaiming completion again if the confusion-matrix requirement is
  satisfied with synthetic rather than real evidence.

## Test plan

1. Hand-trace synthetic fixtures for all nine states plus both gating
   overrides plus data-failure behavior.
2. Hand-trace hysteresis behavior across at least one flapping-input
   scenario, using a persisted, multi-bar regime transition-history
   buffer/state threaded call-to-call (see Specification item 3) --
   not a single-shot fixture.
3. Run `pytest` and confirm all new/existing tests pass.

## Acceptance criteria

- [x] All nine regime states, both gating overrides, AND data-failure
      behavior are covered by synthetic fixtures. The 7 directly-computed
      states plus 3 data-failure paths were already covered; this task
      added `is_untradeable_spread_or_liquidity` (the
      `UNTRADEABLE_SPREAD_OR_LIQUIDITY` gate, cross-checked directly
      against `Test_MarketRegimeEngine.mq5`'s own hand-traced values) and
      the `NEWS_BLACKOUT`/`UNTRADEABLE_SPREAD_OR_LIQUIDITY` enum values
      (the `NEWS_BLACKOUT` trigger itself lives in `NewsManager.mqh`,
      outside this task's scope, per the module's own docstring).
- [x] Hysteresis logic is ported (`RegimeHysteresisState`/
      `init_hysteresis_state`/`apply_hysteresis`) and hand-verified: the
      exact 5-step scenario `Test_MarketRegimeEngine.mq5` already
      hand-traces, PLUS a borderline flapping-input case (never
      confirms), a genuine sustained switch across `required_bars` (does
      confirm), and the pre-first-confirmation state (reports
      `TRANSITION_OR_UNCERTAIN`, never a half-confirmed guess).
- [x] The transition-history buffer (a distinct deliverable from
      hysteresis state) is ported and hand-verified in Python
      (`RegimeTransitionHistory`): representation
      (`(timestamp, from_regime, to_regime)`), capacity/retention (500
      entries, justified in the class's own docstring), and
      timestamp-keying are all defined and tested (records only genuine
      confirmed transitions, never repeated same-regime confirmations;
      evicts the oldest entry at capacity; rejects a non-positive
      capacity). **This is the Python-side offline port only -- it does
      not close `00_MASTER_PROMPT_FOR_CLAUDE.md` section 6's live MQL5
      `MarketRegimeEngine.mqh` transition-history requirement, which
      remains unregistered and unowned.**
- [x] The bias/structure-input decision (ported vs. caller-supplied) is
      explicit and documented — confirmed as caller-supplied (unchanged),
      with an explicit test
      (`test_structure_read_failure_modeled_as_neutral_caller_supplied_bias`)
      documenting why a "MarketStructure read failure" is not a distinct
      path this module can represent.
- [x] No "closes TASK-016" claim is made anywhere -- this task closes
      the FORMULA-level item only; the real-evidence confusion matrix
      remains explicitly owned by TASK-037.
- [ ] Independent review completed and findings resolved — deferred to
      this project's single, consolidated, end-of-sprint Codex review.

## Rejection criteria

Reject if completion claims outrun what was actually built/tested, if
gating/hysteresis/data-failure is skipped, or if this task's own
documentation implies the real-evidence confusion matrix is in scope
here (it is not -- see Objective).

## Status

Done — `regime_validation.py` extended with gating overrides
(`is_untradeable_spread_or_liquidity`), hysteresis
(`RegimeHysteresisState`/`init_hysteresis_state`/`apply_hysteresis`), and
a transition-history buffer (`RegimeTransitionHistory`), each
cross-checked against `Test_MarketRegimeEngine.mq5`'s own hand-traced
values where one exists. 26 tests in `test_regime_validation.py` (up from
15), all passing; ruff/ruff format/mypy clean; full suite (614 tests)
passes with no regressions. Independent review deferred to the
consolidated end-of-sprint Codex review.
