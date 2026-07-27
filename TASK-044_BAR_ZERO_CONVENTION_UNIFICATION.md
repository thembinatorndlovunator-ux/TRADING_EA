# TASK-044 - Unify the "bar 0" convention across the giveback/R-path family

## Objective

Pick ONE canonical meaning for R-path index 0 ("what does bar_index==0
represent?") and make every producer/consumer of an R-path agree on it,
closing the admitted, still-open inconsistency between
`parameter_stability.py`'s own schema, `analyse_giveback.py`'s R-path
construction, and notebook 02's synthetic fixtures.

Registered per Codex round-9 review (P1 finding 20), 2026-07-27: three
incompatible bar-0 conventions remain explicitly disclosed as unfinished
in `parameter_stability.py`'s own module docstring ("Picking one
canonical convention and updating the other two to match is a real,
not-yet-done follow-up") with no independently numbered owner. This task
is that registration.

## Reason

- `parameter_stability.py`'s own schema requires `bar_index` 0 to be
  EXACTLY `0.0` -- entry, before any bar has closed (a pure "R multiple
  is 0 at the moment of entry" starting point).
- `analyse_giveback.py` builds its R-paths from bar CLOSE prices -- its
  own index 0 already reflects the entry bar's own close, which is
  virtually never exactly `0.0` (the position has already moved by
  whatever the entry bar itself did before the path is even sampled).
- Notebook 02's synthetic fixtures begin a path at `+0.5R`, a third,
  different starting point.

All three currently disagree about what "the first point on an R-path"
means. R-paths from these three sources are NOT interchangeable today --
comparing or combining them (e.g. feeding an `analyse_giveback.py`-built
path into a `parameter_stability.py` sweep function, or validating a
notebook-02-style fixture against the schema) silently compares
different things under the same "R-path" name.

## Specification

1. **Canonical convention (recommended, not yet decided as final --
   confirm during implementation):** `parameter_stability.py`'s own
   existing choice -- index 0 is EXACTLY `0.0`, the moment of entry,
   before any bar has closed. This is the most natural "zero point" for
   an R-multiple curve (R is defined relative to entry) and is already
   the schema's own stated requirement; the other two producers are the
   ones that need to change, not this one.
2. **`analyse_giveback.py`:** prepend a synthetic `bar_index=0, r=0.0`
   point to every R-path before the entry bar's own first real close,
   shifting every subsequent bar's own index by one. Verify this does
   NOT change any already-published giveback/drawdown PERCENTAGE (the
   arm/trigger formula's own peak-tracking logic should be invariant to
   a single leading `0.0` point, since a peak can never be BELOW its own
   starting value) -- add a regression test proving the shifted and
   unshifted paths produce IDENTICAL `max_giveback_pct`/trigger-event
   results, only a different bar_index numbering.
3. **Notebook 02:** rebuild its synthetic fixtures to start at `0.0`
   instead of `+0.5R`, re-executed via `jupyter execute` with the new
   fixture, and any narrative text describing the fixture's own starting
   point corrected to match.
4. **Cross-consumer test:** a real R-path built via
   `analyse_giveback.py`'s own (now-unified) construction must validate
   successfully against `parameter_stability.py`'s own schema, and vice
   versa -- proving the two are now actually interchangeable, not merely
   independently self-consistent.

## Files affected

- `03_SOURCE_CODE/Python/analysis/parameter_stability.py` (docstring
  correction once unification lands; schema itself likely unchanged
  since it is the canonical target).
- `03_SOURCE_CODE/Python/analysis/analyse_giveback.py` (R-path
  construction).
- `03_SOURCE_CODE/Python/notebooks/02_*.ipynb` (synthetic fixture
  rebuild).
- Associated test files for both modules.
- `TASKS.md` and this task file.

## Out of scope

- Any change to the underlying giveback arm/trigger FORMULA itself
  (`compute_balance_peak_giveback`/`compute_daily_equity_peak_giveback`) --
  this task is about R-path INDEXING convention only, not the metric
  math, which is unaffected once the leading `0.0` point is confirmed
  invariant per Specification item 2's own test.

## Test plan (once started -- not run yet)

1. `analyse_giveback.py`'s own R-path construction, before vs. after the
   fix: identical `max_giveback_pct`/trigger-event counts, only the
   bar_index numbering shifts by one.
2. Notebook 02 re-executed via `jupyter execute`, zero errors, output
   diff reviewed for the fixture-shape change.
3. A real R-path from `analyse_giveback.py` validates against
   `parameter_stability.py`'s own schema without modification.
4. Full Python test suite passes; ruff/mypy clean.

## Rejection criteria

Reject if this ships as a documentation-only relabeling (renaming what
"bar 0" is called without actually changing any producer's own
construction to match), if the giveback formula's own percentage outputs
silently change as a side effect (must be proven invariant, not assumed),
or if any one of the three producers is left unconverted while claiming
this task complete.

## Status

Not started -- registered, no design or implementation work done yet.
`parameter_stability.py`'s own docstring is updated to cite this task by
number in place of its prior unnumbered "real, not-yet-done follow-up"
language.
