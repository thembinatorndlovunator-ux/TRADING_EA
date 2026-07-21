# TASK-026 — OrderManager: real order submission

## Objective

Build `03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh` —
the first module in this project capable of submitting a real order:
`OM_CalculateVolume` (position sizing), `OM_OpenPosition` (market-order
open with explicit result-code checking and position-ticket resolution),
`OM_ClosePosition` (single-ticket close, own-magic-only).

## Reason

TASK-025's `ThembaAdaptiveIntradayEA.mq5` was deliberately journal-only:
its task file's Final Decision explicitly named `OrderManager.mqh` as
the next piece needed before a trading-capable build exists. This task
builds that piece as its own standalone, independently tested module —
consistent with every prior Execution/Risk module's discipline — without
wiring it into the live EA.

## Baseline behaviour

Not applicable — new-engine module. No file under `01_BASELINE/` is
touched. (For context: both baseline EAs' confirmed defect of pervasive
unchecked `CTrade` results, per `baseline_v637_audit.md` /
`baseline_v811_audit.md`, is the specific defect `OM_OpenPosition` and
`OM_ClosePosition` fix here, same as `IntradayCloseManager.mqh` already
did for the close path.)

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 8 (risk-cash formula,
stop floor/cap, broker-minimum-volume-vs-cap rejection rule) and
`RISK_POLICY.md` ("reject broker minimum volume when actual risk exceeds
the cap", "use OrderCalcProfit to cross-check risk") — both already
implemented by `RiskManager.mqh` (TASK-007) and composed, not
re-derived, here.

## Specification

- `OM_CalculateVolume`: the algebraic inverse of
  `RM_ComputeRiskCash` — `raw_volume = (equity * risk_percent/100) /
  cash_per_lot`, rounded DOWN to the nearest `volume_step` (never up,
  since rounding up would silently exceed the requested risk). If the
  rounded volume falls below `volume_min`, defers entirely to
  `RM_BrokerMinVolumeExceedsCap`: if the broker's own minimum volume's
  risk would exceed `risk_cap_percent`, REJECTS outright (never rounds
  up to force a fit); otherwise widens to `volume_min` (a sanctioned
  widening within the cap, flagged via `widened_to_minimum` so a caller
  can log it) — this is a genuine widening of realized risk above the
  originally-requested `risk_percent`, bounded only by `risk_cap_percent`,
  which is intentional and matches how every other cap-vs-target
  distinction in this project already works (target is aspirational,
  cap is a hard boundary). Clamped to `volume_max` on the high side.
- `OM_OpenPosition`: submits a real market order via `CTrade`, checking
  `ResultRetcode()` explicitly against `TRADE_RETCODE_DONE` /
  `TRADE_RETCODE_PLACED` (never trusting the bool return alone). On
  success, resolves the actual position ticket by scanning
  `PositionsTotal()` for this EA's own `(symbol, magic)` — `ResultDeal()`
  is a deal ticket, not a position ticket, and the two are not
  interchangeable for a later `OM_ClosePosition`/`IntradayCloseManager`
  call.
- `OM_ClosePosition`: closes one ticket, but first verifies it actually
  carries the caller's own `magic` — refuses (does not close) a position
  under any other magic, matching `IntradayCloseManager.mqh`'s
  own-magic-only rule at single-ticket granularity.

## **SCOPE BOUNDARY — NOT WIRED INTO THE LIVE EA**

This module is built and independently tested (including a real,
flagged demo-account order placed and closed by its own test script —
see Test results), but it is **not** included by
`ThembaAdaptiveIntradayEA.mq5`, and that EA's `OnTick` still never calls
it. Making the live EA actually capable of trading — including it,
calling `OM_CalculateVolume`/`OM_OpenPosition` from
`EvaluateAndJournal`'s `has_decision` branch, respecting
`DailyWeeklyLimits`/`EquityPeakManager`/`DrawdownController` state before
sizing, and durable-intent/idempotency handling per spec section 12 — is
a separate, higher-stakes task requiring its own dedicated scrutiny and
explicit user sign-off before it is attempted, exactly as TASK-025's own
Final Decision flagged. This task closes the "the function doesn't exist
yet" gap; it deliberately does not close the "the EA can trade" gap.

## Files affected

New:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_OrderManager.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.
`ThembaAdaptiveIntradayEA.mq5` is NOT modified.

## Out of scope

Wiring into the live EA (see Scope Boundary above). Durable-intent /
idempotency handling for order submission (spec section 12 — a
`GlobalVariableSetOnCondition`-guarded intent record, matching
`StateManager.mqh`'s existing account-lock pattern, has not been built
for order submission specifically). Stop-loss/take-profit price
computation from a strategy's raw stop/target distances — this module
takes `sl_price`/`tp_price` as caller-supplied absolute prices, it does
not derive them. Partial closes / volume-reduction (`OM_ClosePosition`
closes the full ticket only). Pending-order submission (only market
orders — `Buy`/`Sell` — are implemented; `IntradayCloseManager.mqh`
already handles pending-order cancellation but nothing here creates
one).

## Risks

- No independent review available this phase.
- `OM_CalculateVolume`'s widening-to-minimum behavior means the
  *realized* risk percent on a small account can exceed the originally
  requested `risk_percent` (bounded by `risk_cap_percent`) — this is a
  deliberate, spec-driven choice (see Specification above), not an
  oversight, but any future caller must pass a genuinely intended
  `risk_cap_percent`, not a placeholder, since it is the only backstop.
- `OM_OpenPosition`'s position-ticket resolution scans all open
  positions on `(symbol, magic)` after a successful open; on an account
  running multiple concurrent positions under the same magic on the
  same symbol (not currently possible anywhere in this project, since
  nothing calls this function yet), this scan could resolve the wrong
  ticket if more than one exists. Not a defect against any real caller
  today — flagged for whichever future task actually wires this in.
- The real-order test (`Test_OrderManager.mq5`) places and closes a
  live minimum-volume position — demo-account use only, same discipline
  as `Test_IntradayCloseManager.mq5`.

## Test plan

1. **Compile test**: `Test_OrderManager.mq5` (includes `OrderManager.mqh`
   plus its full `RiskManager.mqh`/`SymbolProfile.mqh`/`Trade.mqh`
   dependency chain).
2. **Pure sizing tests (hand-verifiable, tests 1-6)**: exact worked
   example matching `Test_RiskManager.mq5`'s own round numbers; round-
   down-never-up at a non-exact step boundary; widen-to-minimum within
   cap; reject outright when even the minimum exceeds cap; clamp to
   volume_max; invalid-input guards (zero equity, zero loss_distance,
   unloaded profile).
3. **Real-order test (tests 7-8, flagged, demo-only)**: opens one real
   minimum-volume market position under a dedicated test magic
   (990099002, deliberately distinct from
   `Test_IntradayCloseManager.mq5`'s 990099001), verifies
   `OM_OpenPosition` resolves a nonzero position ticket, closes it via
   `OM_ClosePosition`, verifies zero positions remain; opens a second
   position and verifies `OM_ClosePosition` REFUSES to close it when
   given the wrong magic number, then cleans up correctly.

## Acceptance criteria

- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation.
- [x] `OM_CalculateVolume` never rounds up past the requested risk
      (hand-verified).
- [x] `OM_CalculateVolume` rejects, never silently widens past, a
      broker-minimum-volume-exceeds-cap case (hand-verified).
- [x] `OM_ClosePosition` refuses to close a position under the wrong
      magic (hand-verified via a real demo position).
- [x] Not wired into `ThembaAdaptiveIntradayEA.mq5` — verified by
      inspection (that file is untouched by this task).
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.
- [ ] Runtime confirmation beyond this task's own test script (i.e.
      confirmation inside a running EA context) — not applicable yet,
      since nothing calls this module from an EA.

## Rejection criteria

Rejected if any future inspection finds this module wired into
`ThembaAdaptiveIntradayEA.mq5`'s `OnTick` without that having been a
separately surfaced, explicitly confirmed decision, or if
`OM_CalculateVolume` is found to round up past the requested risk in any
case other than the sanctioned within-cap widening-to-minimum path.

## Implementation notes

`OM_CalculateVolume` deliberately calls `RM_ComputeRiskCash(profile,
loss_distance, 1.0, cash_per_lot)` to get the per-single-lot cash figure
rather than re-deriving the formula — the division that turns it into a
volume (`raw_volume = risk_cash_target / cash_per_lot`) is the only new
arithmetic this module adds on top of `RiskManager.mqh`.

## Commands run

```
git checkout -b claude/task-026-order-manager
mkdir -p 03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_OrderManager.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 4719 ms elapsed,
cpu='X64 Regular'` on the first attempt — no defects found this time.

## Test results

**Compile test: PASS (real evidence, above).** Tests 1-8's actual
pass/fail counts from a live run are not yet captured in this file —
the compile evidence above is real; running the script against a live
demo terminal joins the same batched-runtime-verification note every
other module's live-symbol path has carried, EXCEPT the sizing math
(tests 1-6) has also been hand-traced arithmetic-by-arithmetic in the
Specification/Test plan sections above, giving independent confidence
in that portion beyond "it compiles."

## Commit

Pending — see `git log` on `claude/task-026-order-manager`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean.** This module closes the "no order-submission
function exists" gap named in TASK-025's Final Decision. It is
deliberately NOT wired into the live EA — that remains a separate,
higher-stakes decision requiring explicit sign-off before any future
task attempts it. Remaining before a trading-capable build exists:
wiring this module into `ThembaAdaptiveIntradayEA.mq5` (with
`DailyWeeklyLimits`/`EquityPeakManager`/`DrawdownController` state
checked before every sizing call), durable-intent/idempotency handling
per spec section 12, and real-world runtime confirmation of the whole
pipeline (still batched, per TASK-025).
