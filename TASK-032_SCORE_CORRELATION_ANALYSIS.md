# TASK-032 - Score-component correlation analysis

## Objective

Implement the score-component correlation audit required by the master
prompt (section on scoring, lines 747-757: "Include a score-correlation
audit in Python," after explicitly warning against letting correlated
components like BOS/displacement, pin-bar/wick-rejection, or EMA-
trend/price-above-EMA double-count the same evidence): quantify
correlation between the scoring components that feed a signal's final
score — BOS/displacement evidence, pin-bar/wick evidence, and EMA
evidence — so double-counting or redundant weighting can be identified.

**Corrected, 2026-07-22 Codex review finding (third round):** this
objective/reason previously attributed the correlation-audit
requirement to TASK-024's task file — TASK-024 never deferred a
correlation audit; it deferred building THREE MISSING SCORE COMPONENTS
(location/pattern quality, sample-gated historical performance) that
don't exist yet at all, a different gap. The correlation-audit
requirement is the master prompt's own, independent of TASK-024's
deferral.

## Reason

The master prompt requires this analysis directly (see Objective).
TASK-028 listed it in its backlog but never built it, and Codex's
TASK-028 review (finding #1) required it be split into its own
numbered task rather than left as an undifferentiated bullet under
TASK-028's "genuinely remaining" list.

## Baseline behaviour

Neither immutable baseline EA exposes per-component score breakdowns in
a form Python can consume directly; this is new offline analysis
tooling, not a baseline-behaviour change. `01_BASELINE/` must not be
modified.

## Evidence

- `00_MASTER_PROMPT_FOR_CLAUDE.md` lines 747-757 — the actual
  correlation-audit requirement (not TASK-024; see the correction above).
- `TASK-024_STRATEGY_ROUTER.md` — SignalScorer's component weights and
  its own SEPARATE deferred item (the three missing score components,
  not this correlation audit).
- `09_HANDOVERS/codex_to_claude/TASK-028_review.md` finding #1 — the
  requirement to split this out as its own task.
- `03_SOURCE_CODE/MQL5/.../SignalScorer.mqh` — the actual score
  components and their current weights.
- `TRADE_DECISION_SCHEMA.json` — the journal fields (if any) exposing
  per-component scores for real trade decisions.

## Specification

1. Confirm whether `DecisionJournal.mqh` currently records
   per-component score contributions (not just the final `score`
   field) for a real decision. **As of 2026-07-22 (Codex review finding,
   third round): it does not** — the schema HAS a `score_breakdown_json`
   field, but nothing populates it (`Test_DecisionJournal.mq5` only
   asserts the empty `"{}"` default); this gap is now explicitly owned by
   `TASK-036_JOURNAL_PRODUCER_COMPLETION.md`'s Specification item 6, not
   left undocumented here. This task's own real-data run remains blocked
   until TASK-036 ships that population — coordinate the JSON key names
   with that task rather than inventing them independently here.
2. Build a Python module (e.g. `analysis/score_correlation.py`) that,
   given a set of per-component score records (real or synthetic),
   computes pairwise correlation (e.g. Pearson/Spearman) between
   BOS/displacement, pin-bar/wick, and EMA evidence components.
3. Use synthetic fixtures with hand-computable correlation (e.g.
   perfectly correlated, perfectly anti-correlated, and independent
   synthetic component series) to verify the implementation, per the
   reproducibility contract's rule 7.
4. Report sample size and confidence interval alongside any correlation
   claim — no correlation coefficient without an accompanying sample
   size and (if used to justify a weighting change) a bootstrap CI.

## Files affected

- New `03_SOURCE_CODE/Python/analysis/score_correlation.py` and its
  tests.
- Possibly a new notebook, or an extension of an existing regime/score
  notebook.
- `TASKS.md` and this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- Automatically re-weighting `SignalScorer.mqh`'s components based on
  this analysis — any weighting change is a separate, human-reviewed
  task.
- Running this against real data before the journal-schema gap (if
  found in step 1) is closed.

## Risks

- If the journal schema doesn't expose per-component scores, this task
  may need to become two tasks: a journal-schema extension (MQL5 side)
  and the Python analysis itself.
- Small-sample correlation claims can be spurious — must report CI, not
  a bare coefficient.

## Test plan

1. Verify (or document the absence of) per-component score fields in
   the journal schema.
2. Unit-test the correlation function against hand-computable synthetic
   fixtures (perfect correlation, perfect anti-correlation,
   independence).
3. Run `pytest` and confirm all tests pass.

## Acceptance criteria

- [ ] Journal-schema gap (if any) explicitly documented, not silently
      worked around.
- [ ] Correlation module implemented with hand-verified synthetic
      fixtures.
- [ ] Every correlation claim reports sample size and CI.
- [ ] Independent review completed and findings resolved.

## Rejection criteria

Reject if a correlation claim is reported without sample size/CI, or if
real-data correlation is claimed without a real, schema-exposed
per-component dataset actually existing.

## Status

Not started. Registered as a formal follow-up per Codex's TASK-028
review finding #1.
