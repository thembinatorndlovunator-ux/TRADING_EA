# TASK-035 - ML signal model (Python trains, MQL5 executes)

## Objective

Build an offline-trained model that learns from real closed-trade
history (once it exists) plus the domain knowledge already encoded in
this project's reference materials (candlestick/SMC PDFs, baseline EA
source, the rule-based scoring logic already built), to improve signal
quality — exported as ONNX and consumed by the live MQL5 EA for signal
scoring/filtering. **Order execution remains entirely inside MQL5's
existing, already-built risk infrastructure** (OrderManager, cooldown,
daily/weekly limits, drawdown controller) — Python never talks to the
broker. This is the user's explicit architecture choice (2026-07-21),
matching TASK-028's own pre-existing "Offline-learning boundary" rule.

## Reason

The user wants the EA to keep improving from its own trading history
rather than staying purely static rule-based, without introducing a
second, unreviewed, ungated execution path. Per this project's own
already-written rules (`TASK-028_PYTHON_STATISTICAL_LAB.md`'s Offline-
learning boundary and Out-of-scope sections), ML work was always
supposed to wait until "the rule-based EA, dataset, and leakage controls
pass independent review and a separate experiment is approved" — this
task IS that separate, approved experiment, scoped explicitly to keep
Python out of the execution path.

## Baseline behaviour

Neither immutable baseline EA has any ML/ONNX component. This is wholly
new functionality, gated behind independent review before any live use.
`01_BASELINE/` must not be modified.

## Evidence

- `TASK-028_PYTHON_STATISTICAL_LAB.md` — "Offline-learning boundary" and
  "Out of scope" sections (pre-existing project rule this task must
  satisfy, not violate).
- `EA Files/Candlestick Bible.pdf`, SMC PDF, and other reference
  materials already cross-checked in `TASK-017_CANDLESTICK_REFERENCE_CROSSCHECK.md`
  — the "knowledge in the files provided" this model should incorporate
  (as features, priors, or hand-engineered inputs — not blindly
  re-derived by the model from scratch).
- `03_SOURCE_CODE/MQL5/.../SignalScorer.mqh`, `StrategyRouter.mqh` — the
  existing rule-based scoring this model augments, not replaces outright
  (a full replacement would need its own separate sign-off).
- `requirements.txt` — already lists `onnx`/`onnxruntime`/`skl2onnx` as
  declared-but-unexercised dependencies; this task is what finally
  exercises them.
- [[project-open-gaps]] — **no real trade/journal data exists anywhere
  in this project yet.** This is the hard blocker below.

## Critical dependency — this task cannot really start yet

There is currently **zero real trade history** anywhere in this
project. `03_SOURCE_CODE/Python/` has only ever run against synthetic
fixtures. A model "trained on past trades" needs actual past trades to
exist first. This task is genuinely blocked on:

1. TASK-025/027's EA actually running (real MT5 terminal attach —
   currently batched, never done).
2. Enough real closed trades accumulating in a real journal to train on
   (almost certainly needs weeks/months of live or demo running, not
   days — small-sample overfitting risk otherwise, per this project's
   own "tiny samples cannot drive automatic changes" rule).
3. The MT5-export-bridging task (already flagged as an open gap) to get
   that real data into the normalized CSV schema the Python lab expects.

**Do not fabricate or shortcut this with synthetic data presented as
real training data.** Until real data exists, this task's only honest
deliverable is the pipeline/architecture itself, proven on clearly-
labelled synthetic fixtures, with the real-data run marked PENDING —
exactly like every other Python-lab notebook.

## Specification

1. **Feature set**: combine (a) the same features `SignalScorer.mqh`
   already computes (regime, BOS/displacement, pin-bar/wick, EMA
   evidence, etc. — reuse, don't reinvent) with (b) any additional
   engineered features derivable from the reference-PDF knowledge base
   (e.g. specific candlestick/SMC criteria not already scored).
2. **Model**: start with an interpretable model (e.g. gradient-boosted
   trees) before considering anything less explainable — this project's
   own discipline favors traceable decisions over black-box ones.
3. **Training/validation split**: purged, embargoed walk-forward split
   (reuse `walk_forward.py`'s existing purging logic) — never a random
   shuffle split, which would leak future information.
4. **Export**: ONNX via `skl2onnx` (or equivalent), with a version tag
   and the exact training-data hash/commit recorded in the model's own
   metadata, matching this project's provenance-tracking discipline.
5. **MQL5 consumption**: the live EA loads the ONNX model (via
   `onnxruntime`'s MQL5 integration, or MT5's native ONNX support) to
   produce a score/filter signal that feeds into — not bypasses —
   `SignalScorer.mqh`'s existing composition. Exact integration point
   (adjust score vs. veto vs. separate confidence gate) is a design
   decision for this task, not to be improvised ad hoc during
   implementation.
6. **Live safety**: the model's output can only ever narrow/filter the
   rule-based system's decisions (e.g. suppress a low-confidence signal),
   never invent a trade the rule-based logic didn't already propose, and
   never bypass any of `CooldownManager`/`DailyWeeklyLimits`/
   `DrawdownController` (TASK-034 and earlier). This must remain true
   even if the model is later retrained/updated.

## Files affected

- New `03_SOURCE_CODE/Python/analysis/train_signal_model.py` (paired
  notebook per the reproducibility contract) + tests.
- New MQL5 ONNX-consumption module (name TBD at implementation time) +
  wiring into `SignalScorer.mqh`/`StrategyRouter.mqh`.
- `requirements.txt` (already has the ONNX deps declared).
- `TASKS.md` and this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- Python submitting or modifying live orders, directly or indirectly —
  this remains an MQL5-only capability per the user's own confirmed
  architecture choice.
- Training on synthetic data and calling the result "profitable" or
  "validated" — no real-data claims until real data exists.
- Any online/continuous learning that updates the live model without a
  human-reviewed retraining step — every model version is a reviewed
  artifact, not a moving target.
- Retiring or bypassing the existing rule-based `SignalScorer.mqh`
  logic — this augments it.

## Risks

- Overfitting to a small real-trade sample once one exists — must
  report sample size and out-of-sample performance with uncertainty,
  never a bare accuracy/win-rate number.
- Leakage via the feature set (e.g. a feature that indirectly encodes
  future information) — needs the same purged/embargoed discipline
  `walk_forward.py` already established.
- Silent architecture drift toward Python-side execution "just this
  once" — any change to the execution boundary is a separate,
  explicitly-flagged decision, not something to slide into this task.
- Premature "fast-tracking" pressure to skip the real-data dependency
  above and train on synthetic/small data anyway — explicitly rejected
  by this task's own spec.

## Test plan

1. Build and test the full pipeline (feature extraction -> purged
   split -> train -> ONNX export -> MQL5 load) against clearly-labelled
   synthetic fixtures first, exactly like every other Python-lab
   notebook — mark real-data run PENDING until real data exists.
2. Once real data exists (a future, separate milestone — do not force
   this task to wait indefinitely, but do not fabricate data to satisfy
   it either): retrain, report purged walk-forward out-of-sample
   performance with sample size and CI, and get independent review of
   that specific result before it ever influences a live signal.
3. MQL5-side: compile clean, hand-verified test confirming the model's
   output can only narrow/filter, never expand, the rule-based signal
   set, and never bypasses cooldown/limits/drawdown gates.

## Acceptance criteria

- [ ] Pipeline built and proven on synthetic fixtures; real-data run
      explicitly PENDING until real trade history exists.
- [ ] Purged/embargoed split used, no leakage.
- [ ] ONNX export with recorded provenance (data hash, commit, version).
- [ ] MQL5 integration only narrows/filters signals, never bypasses
      existing risk gates.
- [ ] Independent review completed before any live (even demo-account)
      use of the model's output.

## Rejection criteria

Reject if trained/evaluated on synthetic data presented as real, if
Python gains any direct or indirect order-execution capability, if the
model can bypass cooldown/limits/drawdown gates, or if a
profitability/accuracy claim is made without sample size and
out-of-sample evidence.

## Status

Not started — registered per the user's 2026-07-21 request, architecture
confirmed via AskUserQuestion (Python trains offline, MQL5 executes).
Blocked on real trade data existing (see "Critical dependency" above);
the pipeline-on-synthetic-fixtures portion can start independently.
