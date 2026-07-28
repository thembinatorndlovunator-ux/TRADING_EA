# TASK-016 — MarketRegimeEngine: the nine-state regime classifier

## Objective

Implement `MarketRegimeEngine.mqh` per `TASK-002_PHASE2_SPECIFICATION.md`
section 2: the nine-state regime classifier, including the
classification-margin confidence formula that replaced round-2 review's
mathematically self-defeating one, the strict-priority state-selection
order, the gating regimes, and 2-bar hysteresis. This is the module every
other Phase 4 detection engine implicitly assumes a "current regime"
context from — the most consequential module implemented so far, since
round-2's broken formula (`min(T, 1−2|0.5−E|)`, exactly zero at both
expansion extremes) was the single most serious defect found across all
of TASK-002's review rounds.

## Reason

The corrected formula (`(E−threshold)/(1−threshold)` for expansion,
mirrored for the other states) was verified by hand in
`TASK-002_PHASE2_SPECIFICATION.md`'s own Test plan item 5, but had never
existed as executable code until this task. Getting this right matters
disproportionately: every strategy-routing decision in the eventual
system reads the regime this module produces.

## Baseline behaviour

Neither baseline has a comparable regime classifier — this is new-engine
work per master-prompt section 6, not a port. No file under
`01_BASELINE/` is touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 2 in full, including the Test
plan's hand-derived extreme values this task's tests 2 and 4 directly
reproduce.

## Specification

`MRE_ClassifyArray` computes efficiency ratio (`ER`, average-rank
percentile-consistent zero-denominator handling), expansion/compression
evidence (`E`, ATR percentile against a trailing window), trend strength
(`T`, reusing `MarketStructure.mqh`'s bias output for
`swing_agreement` — a stated interpretation choice, see below — combined
with EMA-slope-vs-ATR normalization), and `T_final` (ADX-multiplied `T`).
State selection follows section 2's exact strict-priority order (gating
→ data-failure → low-efficiency-RANGING → expansion-with-agreement →
trend-with-agreement → compression → fallback-RANGING), each with its own
margin-based confidence formula. `MRE_ApplyHysteresis` is a separate,
explicitly stateful function (2-bar consecutive-read confirmation, or
immediate bypass for gating/failure reads) — the classifier itself stays
stateless.

**Explicit scope boundaries, stated in the module's own header comment:**
`swing_agreement` reuses `MarketStructure.mqh`'s bias directly rather
than building a third, independent swing-sequence analyzer — a stated
interpretation choice, not a verbatim transcription of a separate
formula section 2 doesn't otherwise define precisely. `NEWS_BLACKOUT` is
accepted as a caller-supplied boolean since the news system (section 10)
is Phase 7 work, not yet built.

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/MarketRegimeEngine.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_MarketRegimeEngine.mq5`, this task
file. Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

- `NEWS_BLACKOUT` detection itself — a Phase 7 concern, accepted as a
  caller-supplied boolean here.
- Persisting hysteresis state across a restart — `SRegimeHysteresisState`
  is caller-owned in-memory state; wiring it into `StateManager`'s
  per-instance namespace (once that namespace exists, per TASK-003's
  scope note) is a later task if restart-persistence of mid-confirmation
  hysteresis turns out to matter in practice.
- The transition-history buffer and confusion-matrix Python fixtures
  section 2's "Required deliverables" list — separate follow-up work.

## Risks

- No independent review available this phase.
- Runtime verification: the array/scalar-based core's six classification
  scenarios plus the hysteresis/gating/clamper tests are deterministic;
  only the final `CMarketData` wrapper smoke test is part of the batched
  TASK-003 through 015 runtime gap.
- **`swing_agreement`'s reuse of `MarketStructure`'s bias is this task's
  own interpretation choice**, stated explicitly — worth a second opinion
  on whether section 2's own (looser) "last `InpRegimeSwingLookback`
  confirmed swings all agree" description was meant to be a genuinely
  separate, more general N-swing check rather than `MarketStructure`'s
  fixed two-swing-pair bias comparison.
- The `CopyBuffer` array-ordering subtlety (a non-`AS_SERIES` destination
  array fills oldest-to-newest, so `ema_buf[last]` is the newest value,
  not `ema_buf[0]`) is handled correctly in the wrapper but is exactly
  the kind of MQL5 platform detail most likely to be silently wrong in a
  first pass — flagged explicitly for a reviewer to re-verify
  independently, since `MarketData.mqh` (TASK-005) avoided this issue
  entirely by only ever copying one element at a time, so this is the
  first place in the project this ordering subtlety actually matters.

## Test plan

1. **Compile test** (completed, see Compiler result — clean on the first
   attempt for the most complex module in the project so far; one dead
   unused variable was found and removed during a follow-up cleanup
   pass, confirmed still clean after).
2. **Logic test — array/scalar-based core, fully hand-verifiable**: six
   classification scenarios (`TRENDING_UP` with an exact hand-computed
   confidence of `0.5`; `COMPRESSION` reproducing the specification's own
   `E=0 → confidence=1.0` extreme; `TRANSITION_OR_UNCERTAIN` from
   expansion evidence without direction agreement; `VOLATILITY_
   EXPANSION_UP` reproducing the specification's own `E=1 → confidence=
   1.0` extreme — the exact value round-2 review found broken;
   `RANGING` via a low efficiency ratio; `RANGING` via the priority-order
   fallback with an exact hand-computed confidence of `0.575`); the
   hysteresis state machine's five-step confirmation/switch/bypass
   sequence; the gating predicate's three cases (wide spread, low
   liquidity, neither); and the threshold clampers at their bounds.
3. **Logic test — `CMarketData` wrapper, batched**: a real-symbol
   classification, sanity-checked for `confidence`/`E` both within
   `[0,1]`.

## Acceptance criteria

- [x] `MarketRegimeEngine.mqh` implements section 2's full state-
      selection priority order and every confidence formula exactly,
      independently reproducing both of the specification's own
      hand-derived extreme-value checks.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation.
- [x] Every hand-fabricated scenario's regime, confidence, and
      intermediate values (`T_final`, `E`, `ER`) match their hand
      computation exactly.
- [ ] The `CMarketData` wrapper's real-symbol sanity check — batched with
      TASK-003 through 015's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if any hand-verifiable test produces `FAIL` — especially the
two extreme-confidence reproductions (scenarios 2 and 4), since a
regression there would mean this task failed at reproducing the exact
fix round-3 review's most serious finding required.

## Implementation notes

The `CopyBuffer` ordering subtlety (see Risks) is the one place in this
module where a subtle platform-API misunderstanding could silently
produce wrong `ema_now`/`ema_prior` values without any compile or
obvious-runtime error — documented explicitly in the wrapper's own
inline comment, not just this task file, so the reasoning travels with
the code.

## Commands run

```
git checkout -b claude/task-016-market-regime-engine
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_MarketRegimeEngine.mq5" /log:...
```

## Compiler result

**Real, verified.** First attempt: `Result: 0 errors, 0 warnings, 679 ms
elapsed`. After removing one dead unused variable found during review of
the module: `Result: 0 errors, 0 warnings, 676 ms elapsed, cpu='X64
Regular'`. Full logs available in this session's history; not committed
(build artifacts).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not yet
runtime-confirmed**, but all six classification scenarios plus
hysteresis/gating/clamper tests are deterministic and hand-computed;
only the final `CMarketData` wrapper smoke test is part of the batched
runtime gap.

## Commit

Pending — see `git log` on `claude/task-016-market-regime-engine`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed.** Phase 4 progress: swings, structure,
SR/liquidity, candlesticks, ICT/SMC geometry, and now the regime engine
all have real, tested implementations. Remaining: chart patterns
(section 6), visuals.
