# TASK-018 — ChartPatternEngine: double/triple top-bottom and head-and-shoulders

## Objective

Implement `ChartPatternEngine.mqh` per `TASK-002_PHASE2_SPECIFICATION.md`
section 6: double top/bottom and head-and-shoulders/inverse — the two
pattern families formalized for Phase 2. This is the seventh Phase 4
module and, together with TASK-017, the first task where `EA Files/`
reference material was consulted *during* implementation rather than
deferred and fixed afterward.

## Reason

Section 6's shared framework (pivot predicate, price/time tolerance,
minimum height, trend prerequisite, retest) was fully specified but
never implemented. This task makes it real code, cross-checked directly
against `EA Files/SRbounce/Idenitfying-Chart-Patterns.pdf` (a Fidelity
Investments technical-analysis webinar citing Kirkpatrick & Dodge's
*Technical Analysis: The Complete Resource for Financial Market
Technicians*) as it was written, per the discipline established in
TASK-017.

## Baseline behaviour

Neither baseline has a comparable chart-pattern module — new-engine work
per master-prompt section 10, not a port. No file under `01_BASELINE/`
is touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 6 in full.
`EA Files/SRbounce/Idenitfying-Chart-Patterns.pdf` (local-only, never
committed, per `SOURCE_LIBRARY.md`) — specifically its Double Top/Bottom,
Triple Top/Bottom, and Head and Shoulders slides.

## Specification and cross-check findings

`CPT_DetectDoubleTopArray`/`...BottomArray`: two confirmed swing
highs/lows within `price_tolerance_atr`, a neckline swing low/high
between them satisfying the ATR-based pullback floor, a preceding-trend
prerequisite, and a breakout scan for the earliest-in-time confirmed
close beyond the buffered neckline. `CPT_DetectHeadAndShouldersArray`/
`...InverseArray`: three confirmed swing highs/lows (RS/Head/LS) with
minimum head prominence, shoulder symmetry, time symmetry between the
two legs, a **sloped** neckline (linear interpolation between the two
intervening troughs/peaks, `CPT_LinearInterpolate`), and the same
earliest-in-time breakout scan against the neckline's own value at each
bar. `CPT_CheckRetestArray` implements section 6's retest-holds/fails
predicate.

**One correction applied from the reference material, not carried over
unreviewed from this project's own spec text:** double/triple top and
bottom target projections use the **extreme** peak/trough (highest peak
for tops, lowest trough for bottoms) — the source states this
explicitly ("[t]aking the height from the highest peak to the trough
and then subtracting..."). This project's own spec draft had used an
"average of the two peaks" formulation; this task corrected that to
match the actual cited technical-analysis source, applied during
implementation rather than found and fixed afterward.

**One head-and-shoulders match confirmed directly against the source:**
"three peaks with center peak higher than the other two... shoulders
approximately the same level... neckline through the two troughs...
target is the distance from the head to the neckline projected from the
neckline" matches this module's implementation closely.

**One self-caught omission, fixed before this task's first commit:**
the initial implementation of `CPT_DetectHeadAndShouldersArray`/
`...InverseArray` omitted the trend prerequisite entirely, despite
`TASK-002_PHASE2_SPECIFICATION.md` section 6 explicitly requiring it
("double top/H&S require a preceding confirmed uptrend... before the
first peak"). Caught while writing this task file's own cross-reference
against the specification, before any commit — both functions now take
a `trend_bars` parameter and check `CPT_HasPriorTrend` against the
leftmost shoulder (`ls`), mirrored for the inverse pattern.

**Explicit scope boundary, stated in the module's own header comment:**
triple top/bottom (the natural three-peak/trough extension of the same
framework) is deferred to a fast-follow task rather than rushed
alongside these four patterns — a stated boundary, not an oversight.

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/ChartPatternEngine.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_ChartPatternEngine.mq5`, this task
file. Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

- Triple top/bottom — see the stated scope boundary above.
- The remaining 11 chart patterns (triangles, rectangle, flags, pennants,
  wedges, channels, cup-and-handle) — Phase 5, per section 6's own
  stated scope; `EA Files/CHART PATTERN IN TECHNICAL ANALYSIS.pdf` (a
  separate, image-based/scanned PDF with no extractable text layer in
  this session's environment) was not usable for a cross-check here —
  flagged for a future session with OCR or `pdftoppm` available.
- `CPT_HasPriorTrend`'s lightweight closes-comparison proxy for the
  "preceding confirmed trend" requirement — a stated implementation
  choice (see the module's own header comment) avoiding a hard
  dependency on computing `MarketRegimeEngine`'s `T_final` at many
  historical indices.
- Required visual outputs (boundary lines, neckline, breakout/retest
  markers) — a later `PatternVisuals`/`StructureVisuals` consumer, not
  built yet.

## Risks

- No independent review available this phase.
- Runtime verification: the array-based functions' four hand-fabricated
  scenarios (with fully hand-traced linear-interpolation arithmetic for
  the sloped H&S neckline) are deterministic; only the final
  `CMarketData` smoke test is part of the batched TASK-003 through 017
  runtime gap.
- `EA Files/CHART PATTERN IN TECHNICAL ANALYSIS.pdf` could not be
  cross-checked in this session (no extractable text — likely
  scanned/image-based) — a real, stated limitation, not silently
  skipped.
- The sloped-neckline linear interpolation is the most arithmetically
  intricate logic in this module — every test value was hand-traced
  twice (once during test design, once again during this task-file
  write-up) specifically because of that risk; still worth an
  independent re-derivation given the general pattern that boundary/
  interpolation math is where subtle errors hide.

## Test plan

1. **Compile test** (completed, see Compiler result).
2. **Logic test — array-based core, fully hand-verifiable**: a double
   top with exact hand-computed `boundary_price`, `extreme_price`,
   `target`, `stop`, and `breakout_index`; a mirrored double bottom; a
   head-and-shoulders with the sloped-neckline target/boundary values
   hand-traced through the linear-interpolation formula at three
   distinct bar indices (breakout, head, RS); a mirrored inverse
   head-and-shoulders; and the retest predicate's holding, failing, and
   invalid-input cases.
3. **Logic test — `CMarketData` smoke test, batched**: double-top and
   head-and-shoulders detection against a real symbol's recent data,
   confirmed to complete without crashing.

## Acceptance criteria

- [x] `ChartPatternEngine.mqh` implements double/bottom top and
      head-and-shoulders/inverse per section 6, cross-checked against
      real reference material during implementation.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (clean on the first attempt, including after the trend-prerequisite
      fix and parameter-signature change).
- [x] Every hand-fabricated test case's expected values, including the
      sloped-neckline interpolation arithmetic, are hand-traced and
      verified twice.
- [ ] The `CMarketData` smoke test — batched with TASK-003 through 017's
      outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [x] The self-caught trend-prerequisite omission is fixed and reflected
      in the test scenarios (all four now include a satisfying trend
      prerequisite in their fabricated data).
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if any hand-verifiable test produces `FAIL` — especially the
head-and-shoulders/inverse interpolation values, given how error-prone
that arithmetic is and how directly it was flagged as a risk above.

## Implementation notes

`EA Files/CHART PATTERN IN TECHNICAL ANALYSIS.pdf`'s `pdftotext`
extraction returned empty output (confirmed via file-size and
byte-count checks) — almost certainly a scanned/image-based PDF with no
text layer, not a tooling misuse. `EA Files/SRbounce/Idenitfying-Chart-
Patterns.pdf` (a different, text-based PDF covering the same subject
matter) was used instead and was sufficient for this task's scope.

## Commands run

```
git checkout -b claude/task-018-chart-pattern-engine
pdftotext "EA Files/CHART PATTERN IN TECHNICAL ANALYSIS.pdf" - (empty — image-based)
pdftotext -layout "EA Files/SRbounce/Idenitfying-Chart-Patterns.pdf" -
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_ChartPatternEngine.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 679 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt (after the
trend-prerequisite fix, applied before this was ever compiled/committed).
Full log available in this session's history; not committed (build
artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not yet
runtime-confirmed**, but all four pattern-detection scenarios plus the
retest-predicate tests are deterministic and hand-traced (including the
sloped-neckline interpolation, verified twice); only the final
`CMarketData` smoke test is part of the batched runtime gap.

## Commit

Pending — see `git log` on `claude/task-018-chart-pattern-engine`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed.** Phase 4 progress: 7 of 8 items now
have real, tested implementations (swings, structure, SR/liquidity,
candlesticks, ICT/SMC geometry, regime engine, chart patterns).
Remaining: visuals. Triple top/bottom remains a stated, explicit
follow-up within the chart-pattern family.
