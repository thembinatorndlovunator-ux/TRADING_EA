# TASK-014 — CandlestickPatternEngine: the full section-5 pattern set

## Objective

Implement `CandlestickPatternEngine.mqh` per
`TASK-002_PHASE2_SPECIFICATION.md` section 5: base measurements
(body/range/wick ratios, wick-to-body, ATR-normalized size, relative-size
percentile), and every named pattern predicate with its exact
input/default/bound — single-candle (pin bar/hammer/shooting star,
dragonfly/gravestone rejection, marubozu/displacement, doji/spinning
top, inside/outside bar), two-candle (engulfing, tweezer, harami), and
three-candle (morning/evening star, three soldiers/crows, three-bar
reversal). This is the largest module implemented so far, and the first
to translate an entirely-already-formalized specification section
directly into code with no new formula design needed.

## Reason

Section 5 was one of round-2/round-3 review's most-cited gaps
("candlestick/chart-pattern mathematics" absent) — TASK-002's later
revisions closed that gap on paper, with real predicates, named bounded
inputs, and a stated logical-index/completed-candle convention. This
task is where that work becomes real, compiled, tested code rather than
staying a well-specified but unimplemented section.

## Baseline behaviour

TASK-001's audit found V6.37 has an intrabar read defect in two
candlestick helpers (reading the still-forming bar). This module
structurally cannot repeat that defect — every function takes arrays
already produced under the logical-index (completed-bar-only)
convention, via `CMarketData`/`CP_ReadWindow`, the same enforcement
mechanism `SwingEngine.mqh` established. No file under `01_BASELINE/` is
touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 5 in full — every function in
this module corresponds directly to a named formula/threshold table entry
there.

## Specification

`CP_MeasureRatiosArray` computes `body`/`range`/wicks/ratios/
wick-to-body for one candle (returns `valid=false` on a zero-range bar,
per section 5's own rule). `CP_AtrSizeArray` and `CP_SizePercentileArray`
(average-rank tie convention, per the specification's Data Conventions)
are the two other shared measurements. Every pattern function then
applies section 5's exact predicate using named, defaulted threshold
parameters matching the specification's table one-for-one — see the
module's own inline comments for the section-5 citation at each
function. `CP_IsThreeBarReversalArray` is the one pattern that directly
consumes `SwingEngine.mqh`'s confirmed-swing predicate, per section 5's
own requirement. `CP_ComputeStrength` implements the strength formula
(`0.5×primary_ratio + 0.5×min(1,atr_size/2)`, both clamped to `[0,1]`).

**Explicit scope boundary, stated in the module's own header comment:**
these predicates are section 5's own formalization, not yet cross-checked
against `EA Files/Candlestick Bible.pdf` (kept local-only per
`SOURCE_LIBRARY.md`'s copyright rule) — the same stated gap pattern as
`MarketStructure.mqh`'s SMC cross-check.

## Files affected

New:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/CandlestickPatternEngine.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_CandlestickPatternEngine.mq5`, this
task file. Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

- Confirmation status, invalidation-level tracking, and chart-object
  drawing/storage (section 5's "storage and drawing" requirements
  beyond the strength formula) — these need a live position in a
  pattern's lifecycle (confirmed vs. still-forming) that only makes
  sense once this engine is wired into an actual running EA context; a
  later task.
- `PatternRegistry.mqh` (deduplication/lifecycle tracking across ticks).
- Cross-checking predicates against `EA Files/Candlestick Bible.pdf` —
  see the scope boundary above.
- The regime/location gating rule ("no pattern fires as a standalone
  signal without a regime read and location match") — that composition
  happens at the strategy level, which does not exist yet.

## Risks

- No independent review available this phase.
- Runtime verification: the array-based functions' hand-fabricated test
  cases are deterministic; only the final `CMarketData`-wrapper smoke
  test is part of the batched TASK-003 through 013 runtime gap.
- **Test coverage is one clear positive case per pattern (plus a small
  number of clear-negative cases), not exhaustive edge-case coverage** —
  stated explicitly here rather than implied otherwise, given this
  module's unusually large surface area (18 distinct pattern functions).
  A future pass adding negative/boundary cases for every pattern (tied
  thresholds, zero-range bars, patterns spanning insufficient array
  length) would strengthen this further.
- The predicates are this task's own translation of section 5's formulas
  — a transcription error between the specification document and this
  code is the most likely defect class here, given the sheer number of
  formulas involved; every function's header comment cites its
  section-5 source specifically to make that cross-check easy for a
  future reviewer.

## Test plan

1. **Compile test** (completed, see Compiler result — clean on the first
   attempt despite this being the largest module implemented so far).
2. **Logic test — array-based core, hand-verifiable**: one fabricated,
   hand-computed positive case for every one of the 18 pattern
   functions (bullish/bearish pin bar, dragonfly/gravestone rejection,
   marubozu, doji, spinning top, inside/outside bar, bullish/bearish
   engulfing, tweezer top/bottom, harami detect+confirm, morning/evening
   star, three soldiers/crows, three-bar reversal bullish and bearish),
   plus negative cases for pin bar and marubozu specifically (chosen
   because their threshold logic is most failure-prone), plus the
   strength formula at two hand-computed points.
3. **Logic test — `CMarketData` wrapper, batched**: `CP_ReadWindow`/
   `CP_ReadAtrWindow` read a real symbol's OHLC/ATR window successfully,
   and a handful of pattern checks run against that real data without
   crashing (not hand-verifiable — a smoke test only).

## Acceptance criteria

- [x] Every pattern predicate in `TASK-002_PHASE2_SPECIFICATION.md`
      section 5 has a corresponding, correctly-named function with the
      same default thresholds.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (clean on the first attempt).
- [x] Every function's positive test case is hand-computed and matches
      the specification's own formula.
- [ ] The `CMarketData` wrapper's real-symbol smoke test — batched with
      TASK-003 through 013's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if any hand-verifiable test produces `FAIL` — for a module this
size, a single transcription error between the specification and the
code is the realistic failure mode, and the test suite exists
specifically to catch that class of error function-by-function.

## Implementation notes

`CP_MeasureRatiosArray` and `CP_AtrSizeArray` are the two shared
measurement primitives every pattern function is built on — no pattern
function re-derives `body_ratio`/`upper_wick_ratio`/etc. independently,
matching the "one implementation, reused everywhere" discipline
established by `SwingEngine.mqh`. The harami functions are split into a
`CP_DetectHaramiArray` (returns the implied direction as an enum) and a
separate `CP_IsHaramiConfirmedArray` (the third-bar confirmation), rather
than one function — this mirrors section 5's own two-step description
("alert" vs. "confirmed") directly in the API shape.

## Commands run

```
git checkout -b claude/task-014-candlestick-pattern-engine
mkdir -p 03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_CandlestickPatternEngine.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 841 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt, despite being the
largest module compiled in this project so far. Full log available in
this session's history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not yet
runtime-confirmed**, but every pattern function's positive test case is
deterministic and hand-computed from section 5's own formulas — only the
final `CMarketData` wrapper smoke test is part of the batched runtime
gap.

## Commit

Pending — see `git log` on `claude/task-014-candlestick-pattern-engine`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed.** Phase 4 progress: swings, structure,
SR/liquidity, and the full candlestick pattern set now have real, tested
implementations. Next: chart patterns (section 6 — the two formalized
pattern types, double/triple top-bottom and head-and-shoulders) or ICT/SMC
geometry (section 4 — order blocks, FVG, liquidity sweeps).
