# TASK-041 - Exit-engine wiring (partial scope, per user decision 2026-07-22)

## Objective

Wire TASK-030's `ExitManager.mqh` formulas (break-even, structure/ATR
trailing with the never-widen invariant, time stop, profit-lock) into a
real, per-position orchestrator that manages every position this EA opens
under its own magic number — the gap TASK-030's own header explicitly
named ("wiring these into a live position's actual SL/TP... is explicitly
deferred to a follow-up task").

## Reason / scope decision

Auditing the full spec (`TASK-002_PHASE2_SPECIFICATION.md` section 7)
during this task's own "Audit" step found it considerably larger than
originally assumed: target selection needs 4-5 V6.37 baseline mechanisms
ported fresh (none exist in this project's own MQL5 source), the exit-
priority list's items 1-3 (daily/session risk lock, news safety,
opposite-confirmed-structure-shift) need wiring at EXIT time specifically
(not just entry, which is already gated), and item 4 (momentum-failure
exit) remains unspecified. Given real-money-safety-criticality and the
user's own time constraints, the user was asked and chose: **wire an
orchestrator for the formulas already built and tested now; explicitly
defer target-selection porting, the exit-priority items above, and
momentum-failure as named follow-up work, not silently skipped.**

## Specification (what THIS task actually builds)

1. **`OM_ModifyStop`** (`OrderManager.mqh`, new): a `CTrade`-based stop-
   modification function, mirroring `OM_ClosePosition`'s own-magic-only
   discipline and explicit-retcode-check pattern. Always resubmits the
   position's existing TP unchanged — this function only ever moves the
   stop.
2. **`PositionStateTracker.mqh`** (new): persists the per-position running
   state `ExitOrchestrator.mqh`'s formulas need but do not themselves own
   (peak R, bars-since-last-favorable-swing, the last favorable swing
   price, sticky break-even/profit-lock armed flags, and the position's
   own `initial_stop_price` captured once before any trailing occurs — R
   must stay pegged to the ORIGINAL risk distance, never a shrinking
   already-trailed one). Keyed by the position's own durable `position_id`
   (`POSITION_IDENTIFIER`), matching this project's own P0-1 identity
   fix. Cleared via `PST_Clear` once a position is confirmed closed
   (`OnTradeTransaction`).
3. **`ExitOrchestrator.mqh`** (new): the pure, array-based orchestrator —
   `EO_EvaluatePosition` composes break-even arming, structure/ATR
   trailing (through the never-widen invariant), time stop, and profit-
   lock into one per-tick decision (close, or modify-stop-to-X, or
   neither) for a single position. Live wrapper
   (`ThembaAdaptiveIntradayEA.mq5`'s new `ManageOpenPositions()`) runs
   independent of `EvaluateAndJournal`'s own regime-classification gates —
   an existing open position must still be protected even on a bar where a
   NEW entry decision could not be evaluated. **Corrected, 2026-07-27
   (Codex round-8 P2 finding 22): this bullet previously said
   `ManageOpenPositions()` "runs once per completed bar" -- stale since
   round 7's own P0 finding 8, which moved this call to run on EVERY tick
   (unconditionally, in `OnTick`), specifically because the once-per-bar
   cadence was losing intrabar responsiveness that `ExitOrchestrator.mqh`'s
   own header already advertised. Only `EO_EvaluatePosition`'s internal
   bar-count-based staleness clock still keys off the completed-bar
   boundary; the CALL itself is per-tick.**
4. **`InpTimeStopUsesScalpMode`** (new input, default `true`): which time-
   stop duration ceiling applies to every position this EA manages.
   Explicit, operator-set stand-in — same honest pattern as TASK-034's
   original `InpNewsProviderSource` note — until `intraday_mode`
   (TASK-040) is captured per-position at entry time and threaded through
   to exit management end-to-end (a further, explicitly named follow-up;
   TASK-040's own classifier output is currently journal-only for this
   exact reason).

## Explicitly NOT done, per the user's own approved scope-down

- **Target selection**: this orchestrator uses whatever TP price the
  winning strategy proposed at entry (already set on the position via
  `OM_OpenPosition`), not a dynamically re-evaluated candidate from
  `SetEquilibriumContinuationTarget`/`ApplyHistoricalM15Target`/
  `FindQualifiedFractalTarget`/SR-boundary selection — none of which exist
  in this project's own (non-baseline) MQL5 source yet.
- **Exit-priority items 1-3** (daily/session risk lock, news safety,
  opposite-confirmed-structure-shift) are not composed into the exit
  decision. Daily/weekly loss caps and news blackout already exist as
  separate systems but currently only gate NEW entries.
- **Momentum-failure exit** (item 4) remains unspecified — unchanged from
  `ExitManager.mqh`'s own existing header note.
- **The giveback guard** (`EM_ShouldGivebackCloseV637`/`V811`) is
  intentionally not called here, matching `ExitManager.mqh`'s own
  "default off until Phase 8 evidence" statement.

## Files affected

- `03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh` —
  `OM_ModifyStop` + `SOrderModifyResult`.
- New `PositionStateTracker.mqh`, `ExitOrchestrator.mqh`.
- `ThembaAdaptiveIntradayEA.mq5` — new `ManageOpenPositions()`, called
  from `OnTick` on every tick (see the correction above); `OnTradeTransaction`
  now also calls `PST_Clear` on confirmed closure; 9 new exit-config inputs.
- New `Test_PositionStateTracker.mq5`, `Test_ExitOrchestrator.mq5`;
  `Test_OrderManager.mq5` extended with `OM_ModifyStop` live-position
  checks (tests 9-10).

No file under `01_BASELINE/` may be modified.

## Test plan

1. Compile clean in MetaEditor, 0 errors/0 warnings, real log evidence —
   `ThembaAdaptiveIntradayEA.mq5` and all 4 touched/new test scripts
   independently.
2. `Test_OrderManager.mq5`: `OM_ModifyStop` succeeds on a real (minimum-
   volume) live position and the live SL reflects the accepted value;
   refuses to modify under the wrong magic.
3. `Test_PositionStateTracker.mq5`: round-trip save/load of every field;
   a different `position_id` is a fully separate namespace; `PST_Clear`
   resets every field including the sticky armed flags.
4. `Test_ExitOrchestrator.mq5`: 7 hand-derived scenarios — structure
   trailing beating break-even, the never-widen invariant holding across
   calls, staleness switching to the ATR fallback, the time stop firing
   only when duration+low-R+staleness all hold (and NOT firing when R
   already cleared the minimum), profit-lock arming and computing the
   correct locked stop, and a short-side mirror confirming every formula's
   direction is correct.
5. Runtime verification (attach to a real/demo chart, confirm a real
   position's stop actually trails/arms/closes as expected) — still
   batched project-wide.

## Acceptance criteria

- [x] `OM_ModifyStop` built, tested (real live position), own-magic-only
      enforced.
- [x] `PositionStateTracker.mqh` built and tested — durable, per-position,
      keyed by `position_id`.
- [x] `ExitOrchestrator.mqh` built, tested (7 scenarios incl. a short-side
      mirror), wired into `ManageOpenPositions()`, called on every tick
      (round 7's own P0 finding 8, see the correction in Specification
      item 3 above) independent of entry-evaluation's own gates.
- [x] Target selection, exit-priority items 1-3, momentum-failure, and the
      giveback guard are named as explicit out-of-scope gaps (per the
      user's own approved scope-down), not silently skipped.
- [ ] Independent review completed and findings resolved — deferred to
      this project's single, consolidated, end-of-sprint Codex review.

## Rejection criteria

Reject if this task claims the full spec (target selection, the complete
exit-priority list) is wired when it is not, if `R` is computed against a
shifting (already-trailed) stop instead of the position's own captured
`initial_stop_price`, or if a stop modification is ever allowed to widen
(loosen) a position's risk.

## Status

In progress — `OM_ModifyStop`, `PositionStateTracker.mqh`, and
`ExitOrchestrator.mqh` are built, wired into `ThembaAdaptiveIntradayEA.mq5`
via `ManageOpenPositions()`, and compile clean (real MetaEditor evidence,
2026-07-22). Independent review deferred to the consolidated end-of-sprint
Codex review.
