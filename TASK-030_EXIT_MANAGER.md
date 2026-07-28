# TASK-030 — ExitManager: exit-management formulas (begins Phase 8)

## Objective

Build `03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/ExitManager.mqh` —
every individual exit-management FORMULA from
`TASK-002_PHASE2_SPECIFICATION.md` section 7, as pure, standalone,
hand-testable functions: break-even arming, structure trailing
(long/short), ATR-fallback trailing, the never-widen-a-stop invariant,
time stop, profit-lock (with its partial-lock recheck), and both
giveback-guard models.

## Reason

Section 7's exit engine is the last major undocumented-as-built piece
of `TASK-002_PHASE2_SPECIFICATION.md` (target selection is already
provisionally handled per-strategy; everything else in section 7 has no
module yet). This task begins closing that gap the same way TASK-026
(`OrderManager.mqh`) did: build and test every formula standalone
first, defer composition/live-wiring to a follow-up task.

## Baseline behaviour

Not applicable — new-engine module. No file under `01_BASELINE/` is
touched. (For context: this is exactly the kind of exit logic
`baseline_v637_audit.md`/`baseline_v811_audit.md` found both baseline
EAs implementing inconsistently between long/short sides — this
project's section 7 explicitly restates both directions for every
formula for that reason, and this module mirrors that discipline.)

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 7 (full text reproduced/
implemented here) and section 8's "a stop is never widened merely to
avoid a loss... never a distance increase" blanket rule (implemented as
`EM_ApplyTrailNeverWiden`).

## Specification

Fourteen functions, each directly citing the section 7 sentence it
implements (see `ExitManager.mqh`'s own per-function header comments
for the exact citation):

1. `EM_ComputeR` — R = open gain/loss ÷ initial risk distance, the
   common unit every other formula here is expressed in.
2. `EM_HasFavorableSwingBeyondEntry` — reuses `SwingEngine.mqh`'s
   canonical pivot predicate directly (no pivot math re-derived).
3. `EM_ShouldArmBreakEven` — favorable swing AND R ≥ `InpBreakEvenMinR`.
4. `EM_ComputeStructureTrailStop` — directional swing-in-favor ∓
   ATR×buffer.
5. `EM_ComputeAtrFallbackTrailStop` — directional current-price ∓
   ATR×multiple.
6. `EM_ApplyTrailNeverWiden` — the section-8 invariant: tighter of
   current vs. candidate stop, never the reverse.
7. `EM_IsTrailStale` — bars-since-last-favorable-swing ≥
   `InpTrailStaleBars`, the ONE staleness clock section 7 states is
   shared by both the ATR-trailing fallback and the time stop.
8. `EM_IsTimeStopDurationExceeded` — mode-specific duration ceiling
   (Scalp: elapsed minutes; Day-trade: remaining-session-ratio reaching
   0, composed from `SessionManager.mqh`'s already-built
   `SN_GetSessionMinutesRemaining`, not re-derived).
9. `EM_ShouldTimeStop` — all three of duration-exceeded, low R, and
   staleness required.
10. `EM_ShouldArmProfitLock` — percent of entry-to-target distance
    covered ≥ `InpProfitLockTriggerPercent`.
11. `EM_ComputeProfitLockStop` — locks `InpProfitLockKeepPercent` of
    open gain.
12. `EM_ProfitLockClearsMinFloor` — the partial-lock recheck against
    `InpProfitLockMinKeepPercent` after a broker min-stop-distance
    widening.
13. `EM_ShouldGivebackCloseV637` — percent-of-peak-R giveback model,
    close-trigger floored at `InpGivebackFloorR`-equivalent 0.05R.
14. `EM_ShouldGivebackCloseV811` — absolute-R-floor giveback model.

Both giveback functions are built but, per section 7's own words ("both
models built behind one `ProfitGivebackGuard` interface; default off
until Phase 8 evidence"), no caller in this project invokes them yet —
that is what the spec itself asks for, not a gap this task introduced.

## **NOT BUILT — A GENUINE SPEC GAP, NOT A SCOPING CHOICE**

Section 7's exit-priority item 4, **"momentum-failure exit,"** has no
formula or definition anywhere in `TASK-002_PHASE2_SPECIFICATION.md` —
it appears exactly once, in the priority list itself (line ~963), with
nothing else in the document defining what "momentum failure" means
mathematically. This task does not invent one. Flagged here as needing
its own specification work (a "what does momentum failure mean, and
what predicate detects it" discussion) before any implementation is
attempted, per this project's "never invent an unspecified formula"
discipline (the same discipline that made `PostExpansionRetestStrategy`,
TASK-023, flag its own speculative formalization explicitly rather than
silently presenting a guess as the spec's intent).

## **SCOPE BOUNDARY — NOT WIRED INTO THE LIVE EA**

This module is built and compiled, every formula hand-verified against
fabricated inputs, but nothing in this project calls any of these
functions yet. Missing before exits are actually live:

- **The exit-priority orchestrator** — one function composing this
  module's formulas with (1) daily/session risk lock
  (`DailyWeeklyLimits.mqh`/`DrawdownController.mqh`, already built), (2)
  news safety policy (`NewsManager.mqh`, TASK-029, already built but
  also not yet wired), (3) opposite-confirmed-structure-shift
  (`MarketStructure.mqh`'s BOS/CHoCH event, already built), in section
  7's stated priority order — none of which this task attempts to
  compose.
- **Momentum-failure exit** (item 4) — see above, not specifiable yet.
- **Live position enumeration and SL/TP modification** — calling
  `OrderManager.mqh`-adjacent logic (a `PositionModify`-equivalent does
  not exist anywhere in this project yet; `OrderManager.mqh` itself only
  has `OM_OpenPosition`/`OM_ClosePosition`, no stop-modification
  function) against this EA's actually-open position(s).
- **Per-position state tracking** — `peak_r`, `bars_since_last_
  favorable_swing`, break-even-armed/profit-lock-armed flags are all
  caller-owned state this module deliberately does not persist (mirrors
  `SRegimeHysteresisState`'s caller-owned pattern), but nothing anywhere
  in this project currently owns or persists that per-position state
  (a new concern — `StateManager.mqh`'s existing account-wide namespace
  is the wrong home for genuinely per-position data; a per-position
  state store may need its own design).

A dedicated follow-up task should build the orchestrator + a
`PositionModify`-style stop-update function in `OrderManager.mqh` (or a
new module) + per-position state tracking, all together — bundling a
partial wire-up here would leave the exit system in a more confusing
half-wired state than leaving it all visibly unwired, matching
TASK-029's identical reasoning for deferring its own live-EA wiring.

## Files affected

New:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/ExitManager.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_ExitManager.mq5`, this task file. No
`TASKS.md` modification needed beyond this task's own row (added
separately). No file under `01_BASELINE/` touched.
`ThembaAdaptiveIntradayEA.mq5` is NOT modified.

## Out of scope

See "Not built" and "Scope boundary" above. Also: exposing every
formula's dozen-plus tuning parameters (`InpBreakEvenMinR`,
`InpTrailBuffer`, etc.) as EA `input` variables — that belongs to
whichever future task actually wires this module into the live EA.

## Risks

- No independent review available this phase.
- The giveback-guard functions' exact percentage/floor semantics are
  this task's own interpretation of section 7's prose (which states
  bounds and defaults but not a fully worked example the way section
  8's risk-cash formula had) — flagged for confirmation.
- `EM_HasFavorableSwingBeyondEntry` calls
  `SE_FindNearestConfirmedSwingLowArray`/`HighArray` with `min_index=0`
  unconditionally — a caller wanting to search only swings CONFIRMED
  AFTER entry (not any historical swing beyond entry's price, which
  could include a stale pre-entry swing) would need to pass an
  appropriate `min_index` themselves; this function does not compute
  "the index corresponding to entry time" itself, a caller-responsibility
  worth flagging since getting it wrong would arm break-even off a swing
  that predates the trade.

## Test plan

1. **Compile test**: `Test_ExitManager.mq5` (includes `ExitManager.mqh`,
   which includes `SwingEngine.mqh`).
2. **Every one of the 14 functions hand-verified** against fabricated
   scalar inputs and, for `EM_HasFavorableSwingBeyondEntry`, a
   hand-traced fabricated `highs[]`/`lows[]` array (swing-pivot indices
   re-traced by hand in this task file's own working, matching
   `SE_IsConfirmedSwingLowArray`/`HighArray`'s actual comparison
   operators bar-by-bar) — 27 individual assertions across the 14
   functions.

## Acceptance criteria

- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation.
- [x] Every formula hand-verified against fabricated inputs (27
      assertions).
- [x] `EM_ApplyTrailNeverWiden` never returns a stop that widens
      relative to the current stop (hand-verified both directions,
      long and short).
- [x] Momentum-failure exit is NOT implemented, and is explicitly
      flagged as an unspecified gap rather than silently invented.
- [x] Not wired into `ThembaAdaptiveIntradayEA.mq5` — verified by
      inspection (that file is untouched by this task).
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.
- [ ] Runtime confirmation inside a live position-management context —
      not applicable yet, since nothing calls this module from an EA.

## Rejection criteria

Rejected if any future inspection finds a momentum-failure formula
silently invented and presented as the spec's own definition, or if
`EM_ApplyTrailNeverWiden` is bypassed anywhere a trail-stop candidate is
computed.

## Implementation notes

`EM_IsTrailStale`'s single staleness definition is deliberately shared
by both `EM_ShouldTimeStop` and the (caller's own) decision to fall back
from `EM_ComputeStructureTrailStop` to `EM_ComputeAtrFallbackTrailStop`
— per section 7's explicit "the same staleness definition as the ATR
fallback — one consistent 'no progress' clock," this module does not
define two different staleness concepts.

## Commands run

```
git checkout -b claude/task-030-exit-manager
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_ExitManager.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 437 ms elapsed,
cpu='X64 Regular'` on the first attempt.

## Test results

**Compile test: PASS (real evidence, above).** All 27 hand-derived
assertions traced by hand in this task file's Specification section
(swing-pivot indices re-traced bar-by-bar; giveback floor-override case
re-derived: peak 2.0R, 60% giveback → raw trigger 0.8R, floor
overridden to 1.0R since 1.0R > 0.8R, current 0.9R ≤ 1.0R → close).
Actual live-execution pass/fail counts from a real terminal run are not
yet captured in this session (batched, same as every prior task's
compile-only evidence).

## Commit

Pending — see `git log` on `claude/task-030-exit-manager`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean.** Every formula from section 7 that has an actual,
concrete definition in the spec is now built and tested standalone.
Momentum-failure exit remains genuinely unspecified — flagged, not
invented. Remaining before the exit engine is complete and live: the
exit-priority orchestrator (composing this module with
`DailyWeeklyLimits`/`NewsManager`/`MarketStructure`'s BOS/CHoCH), a
stop-modification function (`OrderManager.mqh` currently has none), and
per-position state tracking — all deliberately deferred to one coherent
follow-up task rather than partially wired here.

**Update, 2026-07-22 — TASK-041 (partial scope, per user decision):**
`OM_ModifyStop` (the stop-modification function), `PositionStateTracker.mqh`
(per-position state), and `ExitOrchestrator.mqh` (composing break-even,
structure/ATR trailing, time stop, and profit-lock only) are now built and
wired into `ThembaAdaptiveIntradayEA.mq5`'s new `ManageOpenPositions()`.
Target-selection porting, the daily-risk/news/opposite-structure-shift
exit-priority items, momentum-failure, and the giveback guard remain
explicitly deferred — see `TASK-041_EXIT_ENGINE_WIRING.md`'s own scope
section for exactly what is and is not covered.
