# TASK-038 - Genuine walk-forward parameter-optimization harness

## Objective

Build the actual walk-forward OPTIMIZATION procedure the trading
literature means by that term: select a parameter (or parameter set) on
each window's TRAIN slice (e.g. by a defined objective function over a
grid/search space), freeze it, and evaluate ONLY that frozen choice on
the corresponding TEST slice -- repeated across all rolling windows,
reporting the distribution of out-of-sample results the selection
procedure itself produces.

## Reason

`analysis/walk_forward.py` (TASK-028) is explicitly and honestly scoped
as a DESCRIPTIVE rolling-window stability report -- it computes win-rate/
expectancy for each train/test pair but never selects or freezes a
parameter. Codex's TASK-028 review (finding #1) confirmed this honest
scoping is good but flagged that the actual optimization deliverable
therefore has no owner at all: "it does not fulfill the still-present
'walk-forward evaluation' deliverable and no numbered follow-up owns
that missing harness." This task is that owner.

## Baseline behaviour

Neither immutable baseline EA has a walk-forward optimization framework.
This is new offline-research tooling. `01_BASELINE/` must not be
modified.

## Evidence

- `analysis/walk_forward.py`'s own module docstring -- states its scope
  limitation explicitly and points to this gap.
- `09_HANDOVERS/codex_to_claude/TASK-028_review.md` finding #1.
- `TEST_PLAN.md` -- whatever walk-forward-style validation it specifies
  should be cross-checked against this task's design.

## Specification

1. Reuse `walk_forward.generate_windows`/`_slice_window`'s existing
   purged-boundary window generation -- do not re-derive window
   mechanics that are already correct and tested.
2. Accept a pluggable "parameter space" and "objective function" (e.g.
   maximize TRAIN-window expectancy, or a risk-adjusted variant --
   **corrected, 2026-07-22 Codex review finding, third round: this
   previously said "test-window expectancy," which is exactly the
   leakage this task's own rejection criteria (below) and step 3 prohibit
   -- parameter selection must never use the test slice**) -- exact
   interface is this task's own design decision.
3. For each window: evaluate every candidate parameter value against
   the TRAIN slice only, select the winner by the objective function,
   then evaluate ONLY that frozen winner against the TEST slice.
4. Report the full distribution of test-slice results across windows
   (not just a mean) -- a walk-forward optimization's whole point is
   showing how selection-then-freeze performs out-of-sample repeatedly,
   and a single aggregate number hides whether that's stable or lucky.
5. Explicit, hand-computable synthetic fixtures proving the selection
   step actually uses ONLY the train slice (a leakage test: construct a
   fixture where the "obviously best" parameter on the full dataset
   differs from the best parameter on the train slice alone, and assert
   the harness selects the TRAIN-slice winner, not the global one).

## Files affected

- New `03_SOURCE_CODE/Python/analysis/walk_forward_optimization.py` (or
  an extension of `walk_forward.py` -- naming is this task's own call)
  + tests.
- Possibly a new notebook, or a rework of `06_parameter_stability.ipynb`/
  `07_walk_forward_analysis.ipynb`'s scope boundary (both currently
  paired to descriptive, non-optimizing pipelines).
- `TASKS.md` and this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- Any live parameter auto-tuning -- this is offline research tooling
  only, per this project's standing "no automatic live parameter
  changes from tiny samples" rule.
- Claiming a specific parameter is "optimal" for live use without
  independent review of the result and the usual real-data caveats
  every other pipeline in this lab carries.

## Risks

- The single biggest risk in any walk-forward optimizer is subtle
  leakage (the "best" parameter secretly influenced by test-window
  information) -- the leakage fixture in the spec above is not optional
  polish, it is the core correctness test for this entire task.
- Small per-window sample sizes could make parameter selection
  effectively random noise -- report sample size and, where feasible,
  a stability/consistency measure across windows, not just a single
  "the optimizer chose X" statement.

## Test plan

1. Leakage fixture (see Specification item 5) -- must pass before
   anything else about this task is trusted.
2. Hand-traced train-selection and test-evaluation numbers for at least
   2-3 windows, matching `walk_forward.py`'s own existing precedent for
   hand-verified fixtures.
3. Run `pytest` and confirm all tests pass.
4. Real notebook execution via `jupyter execute`.

## Acceptance criteria

- [ ] Parameter selection provably uses ONLY the train slice (leakage
      fixture passes).
- [ ] Full per-window test-result distribution reported, not just a
      mean.
- [ ] Independent review completed and findings resolved.

## Rejection criteria

Reject if parameter selection can be shown to use test-window
information in any way, or if results are presented as a single
aggregate without per-window detail.

## Status

Not started. Registered per Codex's TASK-028 review finding #1
(2026-07-22).
