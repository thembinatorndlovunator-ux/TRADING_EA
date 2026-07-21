# TASK-011 — SwingEngine: the canonical confirmed-swing pivot predicate

## Objective

Implement `SwingEngine.mqh` per `TASK-002_PHASE2_SPECIFICATION.md`
sections 6 and 11: the one mathematical pivot predicate — "a confirmed
swing high at logical index k requires `high[k] > high[j]` for all `j`
in `[k-depth, k-1] ∪ [k+1, k+depth]`, confirmed only once `depth` further
bars have closed past index k" — defined once, reused by every consumer
(regime engine, candlestick three-bar reversal, chart-pattern pivots,
exit-engine trailing). This is the first Phase 4 ("Detection engines")
module, and the first task in the roadmap's own dependency order (per
master-prompt section 23, "Swings" is listed first under Phase 4).

## Reason

Round-3 review raised "`SwingEngine` has no mathematical pivot predicate"
as a finding against three separate sections (4, 5, 6) independently —
the specification fixed this by stating the formula once, but nothing
enforced every consumer actually reusing it rather than each
reimplementing its own version. This task makes that structural: every
future module that needs a swing pivot imports this file and calls its
functions, so there is exactly one implementation to get right, not one
per consumer.

## Baseline behaviour

Neither baseline has a single shared swing-pivot definition — this is
part of what TASK-001's audit and TASK-002's ledger items 1/8/13
identified as needing consolidation (V8.11's chart marks vs. traded
structure using inconsistent definitions). This module is the new-
engine's single source of truth; it does not port either baseline's own
swing-detection code. No file under `01_BASELINE/` is touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 6 (the pivot predicate,
stated in the "Shared framework" subsection) and section 11 ("one
`SwingEngine` reused everywhere"); ledger items 1, 8, 11, 13.

## Specification

Split into an array-based **core** (pure, deterministic,
`SE_IsConfirmedSwingHighArray`/`SE_IsConfirmedSwingLowArray`,
`SE_FindNearestConfirmedSwingHighArray`/`...LowArray`) and a thin
`CMarketData`-integrated **wrapper** with the same four function names
minus `Array`, which reads the exact window the core needs from a real
symbol/timeframe and delegates — no pivot math is duplicated between the
two. A pivot at logical index `k` requires `k >= depth` (enough newer,
i.e. more-recent, bars have closed to confirm it did not get broken) and
`k+depth` within available history (enough older bars exist to test the
far side) — either bound violation returns false ("not yet confirmable /
insufficient data"), never a guess.

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Structure/SwingEngine.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_SwingEngine.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

- Swing-sequence direction agreement (higher-high/higher-low pattern
  matching over N swings) — that is the regime engine's own consumption
  logic (section 2's `swing_agreement`), a later Phase 4 task, not part
  of the shared pivot predicate itself.
- BOS/CHoCH break-event detection and labeling — ledger item 1 assigns
  this to the same shared `SwingEngine`/`MarketStructure` module
  eventually, but it is additional logic beyond the pivot predicate;
  deferred to a `MarketStructure.mqh` task once this predicate exists to
  build on.
- Range/equilibrium computation (ledger item 13) — same deferral.

## Risks

- No independent review available this phase.
- Runtime verification: batched with TASK-003 through 010's outstanding
  item, but **this task's fabricated-array tests (1–6) are fully
  hand-verifiable and do not depend on live data at all** — only test 7
  (the `CMarketData` wrapper smoke test) is part of the batched runtime
  gap. This is a meaningfully stronger testing position than most prior
  tasks, worth noting explicitly rather than lumping all seven tests
  together as equally unverified.
- The nearest-swing finder's window-sizing arithmetic
  (`start + max_lookback - 1 + depth + 1`) is the one place in this file
  most worth a second pair of eyes for an off-by-one — it was hand-traced
  against the fabricated-array test case (`min_index=0, depth=3,
  max_lookback=6` correctly locating index 4) but a boundary error at the
  very edge of a requested range is exactly the kind of bug a single
  hand-traced example might not catch.

## Test plan

1. **Compile test** (completed, see Compiler result).
2. **Logic test — array-based core, fully hand-verifiable without live
   data** (completed via compilation; the assertions themselves are
   deterministic and do not require a runtime session to trust, only to
   confirm the code path executes — see Risks for why this is a stronger
   position than "batched, unconfirmed"): a fabricated 12-element array
   with a known peak at index 4 correctly confirms that swing and
   correctly rejects a non-peak, a too-recent (unconfirmable), and a
   too-old (insufficient-history) index; a 5-element array correctly
   reports insufficient data; a hand-constructed tie (plateau) correctly
   fails the strict-inequality requirement; the nearest-finder locates
   the known peak; the mirrored swing-low case behaves identically; and
   a monotonic (strictly increasing) array correctly reports no interior
   pivot found.
3. **Logic test — CMarketData wrapper, batched with TASK-003 through
   010's outstanding item**: a real-symbol swing search, cross-checked by
   independently re-reading the found pivot's six neighbors and hand-
   verifying the strict-inequality property directly (not trusting the
   function's own answer), per TASK-006's "recompute independently"
   discipline.

## Acceptance criteria

- [x] `SwingEngine.mqh` implements exactly the pivot predicate specified
      in `TASK-002_PHASE2_SPECIFICATION.md` sections 6 and 11.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (clean on the first attempt).
- [x] The array-based core's hand-fabricated test cases are fully
      deterministic and verifiable by hand, not dependent on live data.
- [ ] The `CMarketData` wrapper's real-symbol cross-check — batched with
      TASK-003 through 010's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if the array-based core's hand-verifiable tests, once run,
produce any `FAIL` — these are deterministic and have no legitimate
"depends on live conditions" excuse the way the `CMarketData` wrapper
tests do.

## Implementation notes

The array-based/wrapper split exists specifically so this task's
correctness does not depend on the still-unresolved live-terminal
runtime-verification gap (TASK-005's finding) — the core logic that
actually matters (the pivot predicate's boundary conditions) is testable
with fabricated data that this session's own compile-and-reason-about
process can already trust, once it's confirmed to actually execute and
print PASS on a real run. Every future Structure/Pattern module in this
project should follow the same split where feasible: pure core +
thin platform-integration wrapper.

## Commands run

```
git checkout -b claude/task-011-swing-engine
mkdir -p 03_SOURCE_CODE/MQL5/Include/ThembaEA/Structure
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_SwingEngine.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 973 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt. Full log available in
this session's history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not yet
runtime-confirmed** (batched with TASK-003 through 010's outstanding
item) **but the array-based core's assertions are deterministic and
hand-verifiable independent of that gap** — see Risks/Test plan for why
this task's testing position is stronger than most prior ones.

## Commit

Pending — see `git log` on `claude/task-011-swing-engine`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed.** This is Phase 4's first module,
matching the roadmap's own dependency order (swings listed first). Next:
either `MarketStructure.mqh` (BOS/CHoCH built on this pivot) or
`SupportResistance.mqh`, both of which now have a real pivot predicate to
build on.
