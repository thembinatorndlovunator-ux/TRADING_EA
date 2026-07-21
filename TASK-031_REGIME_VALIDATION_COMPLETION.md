# TASK-031 - Regime validation completion

## Objective

Complete the regime-validation work TASK-016 originally deferred and
TASK-028 only partially closed: full nine-state synthetic-fixture
coverage (including the two gating overrides), the gating/hysteresis
logic itself, and a confusion matrix run against real,
independently-labelled regime evidence.

## Reason

Codex's independent review of TASK-028
(`09_HANDOVERS/codex_to_claude/TASK-028_review.md`, finding #1) found
that `TASK-028_PYTHON_STATISTICAL_LAB.md` and `TASKS.md` both claimed
`regime_validation.py` "closes TASK-016's deferred confusion-matrix
item." That claim is false: `regime_validation.py` only covers 7 of 9
regime states, accepts `swing_agreement`/`direction_agree` as
caller-supplied inputs instead of computing them, does not implement the
`NEWS_BLACKOUT`/`UNTRADEABLE_SPREAD_OR_LIQUIDITY` gating overrides or any
hysteresis logic, and has never run a confusion matrix against real
independently-labelled evidence (none exists in this project yet). This
task registers the real remaining scope as its own reviewable unit
instead of leaving it as an undifferentiated backlog bullet.

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
2. Port the hysteresis logic (state persistence/switching behavior)
   from `MarketRegimeEngine.mqh`, with hand-traceable synthetic fixtures
   proving it does not flap on borderline inputs.
3. Decide and document whether `MarketStructure.mqh`'s bias computation
   is ported to Python in this task or remains a caller-supplied input
   for another task — either is acceptable, but the choice must be
   explicit, not silently deferred again.
4. Only claim "confusion matrix against real evidence" once a real,
   independently-labelled regime dataset actually exists and
   `build_confusion_matrix` has been run against it; otherwise keep the
   existing "Real-data run: PENDING" convention.

## Files affected

- `03_SOURCE_CODE/Python/analysis/regime_validation.py` and its tests.
- Possibly a new notebook or an extension of
  `03_strategy_regime_analysis.ipynb`.
- `TASKS.md` and this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- Wiring any of this into the live EA's regime gating.
- Fabricating a "real evidence" confusion matrix from synthetic data.

## Risks

- Synthetic fixtures for gating/hysteresis could diverge from the live
  MQL5 behavior if hand-traced incorrectly — cross-check against
  `Test_MarketRegimeEngine.mq5` where one exists.
- Overclaiming completion again if the confusion-matrix requirement is
  satisfied with synthetic rather than real evidence.

## Test plan

1. Hand-trace synthetic fixtures for all nine states plus both gating
   overrides.
2. Hand-trace hysteresis behavior across at least one flapping-input
   scenario.
3. Run `pytest` and confirm all new/existing tests pass.
4. If real evidence exists by the time this task starts, run
   `build_confusion_matrix` against it and report the result; otherwise
   mark that step explicitly PENDING.

## Acceptance criteria

- [ ] All nine regime states plus both gating overrides are covered by
      synthetic fixtures.
- [ ] Hysteresis logic is ported and hand-verified.
- [ ] The bias/structure-input decision (ported vs. caller-supplied) is
      explicit and documented.
- [ ] No false "closes TASK-016" or "confusion matrix against real
      evidence" claim exists unless a real evidence run actually
      happened.
- [ ] Independent review completed and findings resolved.

## Rejection criteria

Reject if completion claims outrun what was actually built/tested, if
gating/hysteresis is skipped, or if a "confusion matrix" claim is backed
only by synthetic data presented as real evidence.

## Status

Not started. Registered as a formal follow-up per Codex's TASK-028
review finding #1.
