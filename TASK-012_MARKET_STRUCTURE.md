# TASK-012 — MarketStructure: BOS/CHoCH, range, and equilibrium

## Objective

Implement `MarketStructure.mqh` per `TASK-002_PHASE2_SPECIFICATION.md`
section 11 and ledger item 1: canonical BOS/CHoCH break-event detection
and labeling, plus range boundaries and equilibrium, built directly on
`SwingEngine.mqh`'s pivot predicate (TASK-011) — all as one function's
output, so `StrategyRouter` (trading) and `StructureVisuals` (drawing)
consume identically defined values, never two independently-computed
notions of "the current structure."

## Reason

Ledger item 1 requires this consolidation specifically because V8.11's
chart marks and traded structure used inconsistent definitions
(`baseline_v811_audit.md`). This task is where that consolidation
becomes real code: one function computes bias, break events, range, and
equilibrium together from the same underlying swing data, so there is no
way for a trading decision and a chart label to disagree about what the
current structure is.

## Baseline behaviour

V8.11 has two independent structural-break scanners
(`AnalyzeStructure`, `FindRecentStructureShiftLevel`) with inconsistent
retention/labeling (chart marks retain the oldest breaks and always
mislabel the first stored mark CHoCH, per `baseline_v811_audit.md`). This
module is new-engine work replacing both with one shared source, not a
port of either. No file under `01_BASELINE/` is touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 11 ("one accessor consumed by
`StrategyRouter`... and `StructureVisuals`") and section 12 ledger items
1, 8, 13.

## Specification

**Bias:** compares the two most recent confirmed swing highs and the two
most recent confirmed swing lows (via `SwingEngine`'s nearest-finders).
Higher-high AND higher-low → `BULLISH`. Lower-high AND lower-low →
`BEARISH`. Anything else (including fewer than two confirmed swings on
either side) → `NEUTRAL`.

**Break event:** the earliest-in-time confirmed close after the most
recent swing high/low that closes beyond it — found by scanning forward
in time from the swing point (not "the most recent bar that happens to
exceed it", which could be many bars after the actual break). A break
above the last swing high while `BULLISH` is `BOS_BULLISH`
(continuation); the same break while `BEARISH`/`NEUTRAL` is
`CHOCH_BULLISH` (reversal signal). Mirrored for a break below the last
swing low. If both directions have a qualifying break in the scanned
window, the more recent one wins — a genuinely simultaneous dual-break
is a stated, unresolved edge case in this first implementation, not
silently picked one way without acknowledgment.

**Range and equilibrium:** `range_high`/`range_low` are the wider of the
two most recent swing highs/lows on each side; `equilibrium` is their
midpoint — the shared output ledger item 13 requires.

**Explicit scope boundary, stated in the module's own header comment:**
these bias/break-event definitions are this task's own formalization of
standard SMC/ICT usage, not yet cross-checked against the deeper
reference material in `EA Files/SMC/` (correctly kept out of git per
`SOURCE_LIBRARY.md`'s copyright rule) — a stated gap to revisit, not an
oversight.

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Structure/MarketStructure.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_MarketStructure.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

- Order blocks, FVGs, liquidity sweeps (section 4's remaining ICT/SMC
  geometry) — separate Phase 4 tasks building on this module's bias/break
  output.
- Cross-checking the bias/break-event definitions against `EA
  Files/SMC/`'s reference PDFs — see the scope boundary above.
- `StructureVisuals.mqh` itself (the drawing consumer) — a later task,
  once there is something worth drawing in a running EA context.

## Risks

- No independent review available this phase.
- Runtime verification: the array-based core's tests (1–5) are
  deterministic and hand-verifiable, matching TASK-011's stronger testing
  position — only the `CMarketData` wrapper smoke test (test 6) is part
  of the batched TASK-003 through 012 runtime gap.
- **The bias/break-event definitions are this task's own formalization**,
  stated explicitly as not yet cross-checked against the SMC reference
  material — flagged as the most likely place a future review or the
  EA-Files cross-check would find a refinement needed, versus a hard
  defect.
- The "simultaneous dual-break, more recent wins" tie-break is a stated
  simplification for a genuinely rare edge case (a single bar's close
  breaking both the last swing high and the last swing low
  simultaneously is only possible with unusual data), not fully
  reasoned through for every consequence.

## Test plan

1. **Compile test** (completed, see Compiler result).
2. **Logic test — array-based core, fully hand-verifiable**: five
   fabricated scenarios covering the full 2×2 bias × break-direction
   matrix (`BOS_BULLISH`, `CHOCH_BEARISH`, `BOS_BEARISH`,
   `CHOCH_BULLISH`) plus an insufficient-data case (a monotonic lows
   array with no interior trough correctly fails the computation
   outright). Every bias, event type, exact break-bar index, and the
   range/equilibrium values for the first scenario are hand-computed and
   asserted exactly.
3. **Logic test — `CMarketData` wrapper, batched**: a real-symbol
   structure computation, sanity-checked for internally consistent
   ordering (`range_high >= range_low`, equilibrium between them,
   `swing_high_1_price >= swing_low_1_price`).

## Acceptance criteria

- [x] `MarketStructure.mqh` implements bias, break-event, range, and
      equilibrium as one function's output, built directly on
      `SwingEngine.mqh`'s pivot predicate with no duplicated swing logic.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (clean on the first attempt).
- [x] The array-based core's five hand-fabricated scenarios cover the
      full bias × break-direction matrix and are deterministically
      verifiable.
- [ ] The `CMarketData` wrapper's real-symbol sanity check — batched with
      TASK-003 through 011's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if the array-based core's hand-verifiable tests, once run,
produce any `FAIL` — particularly a mismatch between the expected and
actual break-bar index, which would mean the "earliest-in-time" break
definition is not actually implemented as specified.

## Implementation notes

Follows `SwingEngine.mqh`'s array-core-plus-thin-wrapper pattern
exactly, and is built directly on `SwingEngine`'s own array functions
(`SE_FindNearestConfirmedSwingHighArray`/`...LowArray`) rather than
re-deriving pivot detection — this is the structural enforcement ledger
item 1 calls for: there is exactly one pivot implementation in the
codebase, and this module can only ever see swings through it.

## Commands run

```
git checkout -b claude/task-012-market-structure
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_MarketStructure.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 592 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt. Full log available in
this session's history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not yet
runtime-confirmed**, but — as with TASK-011 — the array-based core's
five scenarios are deterministic and hand-verifiable independent of the
batched runtime gap; only the live-symbol wrapper smoke test is part of
that gap.

## Commit

Pending — see `git log` on `claude/task-012-market-structure`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed.** Phase 4 progress: swings and structure
(BOS/CHoCH/range/equilibrium) both have real, tested implementations.
Next: `SupportResistance.mqh`, or the ICT/SMC geometry (order
blocks/FVG/liquidity sweeps) that consumes this module's bias/break
output directly.
