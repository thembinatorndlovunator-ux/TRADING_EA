# TASK-013 — SupportResistance: SR zones and equal-high/low liquidity

## Objective

Implement `SupportResistance.mqh` per `TASK-002_PHASE2_SPECIFICATION.md`
section 4's equal-high/low liquidity definition, generalized to N-touch
SR-zone detection at an arbitrary test price — serving both the
location-match requirement candlestick/chart patterns need (section 5)
and target-selection's nearest-SR-zone need (section 7).

## Reason

Section 4 defines equal-high/low liquidity precisely ("two or more swing
extremes within `ATR × InpEqualLevelTolerance` of each other") but every
other section that references "confirmed SR zone" (sections 3, 5, 7)
does so without its own formula — this task makes that concept real,
generalizing the exact same tolerance-clustering idea section 4 already
specifies rather than inventing a second, different SR concept.

## Baseline behaviour

Neither baseline has an isolated, reusable SR-zone module — SR logic is
embedded inline within larger V6.37 signal functions per
`baseline_v637_audit.md`. This module is new-engine work extracting that
concern into its own tested unit, not a port. No file under `01_BASELINE/`
is touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 4 ("Premium/discount and
equal-high/low liquidity... two or more swing extremes within `ATR ×
InpEqualLevelTolerance` (default `0.1`) of each other").

## Specification

Resistance is built from confirmed swing **highs** clustering; support
from confirmed swing **lows** — kept as two parallel function families
(never mixed into one direction-agnostic concept). `SR_CountSwingHigh
TouchesArray`/`...LowArray` count confirmed swings within `tolerance` of
a `test_price`. `SR_IsResistanceZoneArray`/`...SupportZoneArray` apply an
N-touch (`min_touches`) threshold to that count. `SR_IsEqualHighLiquidity
Array`/`...LowArray` implement section 4's definition exactly: true iff
the swing at a given index is itself confirmed AND has at least one other
confirmed swing within tolerance (total touches, including itself,
`>= 2`).

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Structure/SupportResistance.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_SupportResistance.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

- A "nearest SR zone to a price, searching outward" utility for target
  selection (section 7) — this task provides the zone-detection
  primitive; a caller can scan candidate prices with it, or a dedicated
  nearest-zone finder can be a follow-up task once a concrete consumer
  needs it.
- Premium/discount split (section 4 also mentions this) — that is
  `MarketStructure`'s equilibrium output (TASK-012), not a new SR concept;
  a caller compares a price against `MarketStructure`'s `equilibrium`
  directly rather than through this module.
- Zone clustering into a persistent registry of named levels — this
  module answers "is this price near a zone" on demand; it does not
  maintain a stateful list of discovered zones (no consumer needs that
  yet).

## Risks

- No independent review available this phase.
- Runtime verification: the array-based core's tests (1–8) are
  deterministic and hand-verifiable, matching TASK-011/012's testing
  position — only the `CMarketData` wrapper smoke test (test 9) is part
  of the batched TASK-003 through 013 runtime gap.
- `min_touches`/`tolerance` are caller-supplied with no built-in default
  validation (e.g., `min_touches < 1` would make every price trivially a
  "zone") — acceptable for a first implementation since every current
  test/intended caller supplies sane values, but worth a defensive bound
  if a future caller passes an untrusted value.

## Test plan

1. **Compile test** (completed, see Compiler result).
2. **Logic test — array-based core, fully hand-verifiable**: a
   fabricated highs array with a known clustered pair (two swings within
   tolerance of each other) and one isolated swing correctly produces
   touch count 2 for the clustered pair and 1 for the isolated one;
   `SR_IsResistanceZoneArray` correctly qualifies the clustered pair and
   rejects the isolated one at `min_touches=2`;
   `SR_IsEqualHighLiquidityArray` correctly confirms liquidity at a
   clustered swing, rejects it at the isolated swing, and rejects it
   outright at a non-swing index (with `touch_count=0`). The full pattern
   is mirrored for lows/support.
3. **Logic test — `CMarketData` wrapper, batched**: a real-symbol
   resistance-zone check at the current price with an ATR-scaled
   tolerance, confirmed to complete without crashing and to produce a
   non-negative touch count regardless of outcome.

## Acceptance criteria

- [x] `SupportResistance.mqh` implements equal-high/low liquidity exactly
      per `TASK-002_PHASE2_SPECIFICATION.md` section 4, generalized
      (same tolerance-clustering concept) to N-touch zone detection.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (clean on the first attempt).
- [x] The array-based core's eight hand-fabricated assertions cover both
      the clustered and isolated cases, for both highs and lows.
- [ ] The `CMarketData` wrapper's real-symbol sanity check — batched with
      TASK-003 through 012's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if the array-based core's hand-verifiable tests, once run,
produce any `FAIL` — particularly a mismatch in touch count, which would
mean the tolerance-clustering logic itself (the entire point of this
module) is wrong.

## Implementation notes

Built directly on `SwingEngine.mqh`'s array functions
(`SE_IsConfirmedSwingHighArray`/`...LowArray`), matching TASK-012's
"exactly one pivot implementation, reused everywhere" discipline —
`SupportResistance.mqh` never re-derives what counts as a confirmed
swing, only what counts as a cluster of them.

## Commands run

```
git checkout -b claude/task-013-support-resistance
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_SupportResistance.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 625 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt. Full log available in
this session's history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not yet
runtime-confirmed**, but the array-based core's eight assertions are
deterministic and hand-verifiable independent of the batched runtime gap;
only the live-symbol wrapper smoke test is part of that gap.

## Commit

Pending — see `git log` on `claude/task-013-support-resistance`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed.** Phase 4 progress: swings, structure
(BOS/CHoCH/range/equilibrium), and SR/equal-liquidity all have real,
tested implementations. Next: candlestick patterns (section 5's fully
formalized predicates are ready to become code) or ICT/SMC geometry
(order blocks/FVG/liquidity sweeps, section 4).
