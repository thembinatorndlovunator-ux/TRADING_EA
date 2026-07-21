# TASK-027 — Wire OrderManager into the live EA (order submission, gated)

## Objective

Make `ThembaAdaptiveIntradayEA.mq5` capable of submitting real orders —
the piece TASK-025's Final Decision and TASK-026's Scope Boundary both
explicitly deferred pending the user's own sign-off (obtained: "Wire
OrderManager into the live EA... turns this into a genuinely
trading-capable build"). Order submission is gated behind a new master
safety toggle, `InpEnableOrderSubmission` (default `false`) — with the
default, this build behaves identically to TASK-025's shipped EA.

## Reason

TASK-026 built `OrderManager.mqh` standalone, deliberately not wired in.
This task closes that gap, but does so by composing every risk control
already built (TASK-007/008/026), not by adding a bare "submit the
order" call — per `CLAUDE.md`'s "do not claim... backtest success... or
profitability without actual evidence" and section 8's binding blanket
rules, an order must never be submitted without every one of those
checks passing first.

## Baseline behaviour

Not applicable — new-engine architecture. No file under `01_BASELINE/`
is touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 8, specifically:
- The add-on/basket rule ("no sizing function may create a second
  concurrent position on the same symbol/direction as an existing one").
- The 1%/1% per-trade/total-open-risk caps (own-magic scope) and 2%/4%
  daily/weekly loss caps (account-wide measurement, own-magic closing
  authority) — "two caps, two deliberately different scopes."
- The drawdown-reduction rule ("risk may never increase as a function
  of a preceding loss").
- The stop floor/cap preflight and broker-minimum-volume-vs-cap
  rejection rule (already built in `RiskManager.mqh`/`OrderManager.mqh`).
- The `OrderCalcProfit` cross-check blanket rule.

## Specification

`AttemptOrderSubmission` (new function in the EA file itself — EA-
specific composition logic, not a reusable library module) runs this
gating sequence, in order, only when `InpEnableOrderSubmission` is
`true` and a strategy produced a winning candidate:

1. **No-add-on / no-concurrent-position rule.** Refuses if this EA's own
   magic already holds any position on this symbol. Simplification
   stated explicitly: the spec's rule is "same symbol/direction"; this
   implementation refuses on ANY existing owned position on the symbol
   regardless of direction, which is strictly more conservative (a
   hedging-account opposite-direction add-on is technically allowed by
   the letter of the spec but not attempted by this build).
2. **Daily/weekly loss caps** (`DailyWeeklyLimits.mqh`, TASK-008,
   unchanged) — `DWL_IsDailyLossBreached`/`DWL_IsWeeklyLossBreached`
   against `InpDailyLossCapPercent`/`InpWeeklyLossCapPercent` (defaults
   2.0/4.0, matching section 8's hard limits). Breach refuses the new
   entry; see Out of scope for what this does NOT also do.
3. **Drawdown-based risk reduction** (`EquityPeakManager.mqh`/
   `DrawdownController.mqh`, TASK-008, unchanged) —
   `effective_risk_percent = InpRiskPercentTarget *
   DC_ComputeRiskMultiplier(current_drawdown, ...)`. Never increases risk
   above `InpRiskPercentTarget`.
4. **Stop-distance floor/cap preflight** (`RiskManager.mqh`, TASK-007,
   unchanged) — `RM_ComputeMinStopDistance`/`RM_ComputeMaxStopDistance`/
   `RM_ValidateStopDistance` against the current bar's ATR
   (`atr_values[0]` from the already-computed shared window). A stop
   beyond the cap REJECTS the trade; a stop below the floor widens it
   (and the actually-submitted stop price is recomputed from the
   widened distance, not the strategy's original proposal).
5. **Position sizing** (`OrderManager.mqh`, TASK-026, unchanged) —
   `OM_CalculateVolume` against `effective_risk_percent` and
   `InpRiskCapPercent` (default 1.0%, section 8's hard per-trade/total-
   open-risk cap — enforced correctly as a total-open-risk cap too,
   since step 1 guarantees at most one position is ever open under this
   magic at a time, making per-trade and total-open-risk numerically
   identical here; stated explicitly as the simplification this
   guarantees, not a separate total-open-risk computation).
6. **`OrderCalcProfit` cross-check** (`RiskManager.mqh`'s
   `RM_CrossCheckRiskCash`, unchanged) against
   `InpRiskCrossCheckTolerancePercent` (default 5.0%, section 8's
   default) — a mismatch blocks the trade.
7. **Real order submission** (`OrderManager.mqh`'s `OM_OpenPosition`).

Every rejection at any step appends a machine-readable reason to the
journaled decision's existing `reasons_rejected_json` field (no schema
change — reused per `TRADE_DECISION_SCHEMA.json`'s already-generic
string-array field); every passed gate appends a corresponding entry to
`reasons_passed_json`. A successful submission additionally updates
`decision.stop` (to the actually-submitted, possibly floor-widened
value) and `decision.risk_percent` (to the actually-realized risk_cash /
equity) before journaling — the journal always reflects what actually
happened, never merely what the strategy proposed.

## **SCOPE BOUNDARY — WHAT THIS TASK DOES NOT DO**

- **Three-loss cooldown (per-symbol)**, named in section 8's hard-limits
  list, has no corresponding module anywhere in this project yet — no
  `CooldownManager.mqh` exists. This gate is NOT enforced by
  `AttemptOrderSubmission`. Stated explicitly as an open gap, not
  silently omitted.
- **Durable-intent / idempotency persistence** (section 12,
  `GlobalVariableSetOnCondition`-guarded intent record matching
  `StateManager.mqh`'s existing account-lock pattern) is NOT
  implemented for order submission. A terminal restart mid-submission
  has no reconciliation mechanism here.
- **No forced close-all on a daily/weekly loss-cap breach.** Breaching a
  cap blocks NEW entries only; it does not close this EA's existing
  open position(s). Forced closing on a risk-limit breach is exit-side
  logic (`ExitManager.mqh`, not yet built, Phase 8) — deliberately not
  folded into this entry-gating task.
- **No pending-order submission** — only `OM_OpenPosition`'s market
  orders are used; `IntradayCloseManager.mqh`'s pending-order
  cancellation path remains dormant since nothing here creates one.
- Per-market-family risk-percent tuning (spec: "XAUUSD 0.25%, other
  metals 0.25–0.50%, synthetics 0.25–0.50%") is simplified to one flat
  `InpRiskPercentTarget` input (default `0.3`, within that stated range)
  — `market_family` classification is not computed anywhere in this EA
  yet (a pre-existing gap from TASK-025, not introduced here).

## Files affected

Modified:
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5` (new
`InpEnableOrderSubmission` and 9 supporting risk-parameter inputs, new
includes for `DailyWeeklyLimits.mqh`/`EquityPeakManager.mqh`/
`DrawdownController.mqh`/`OrderManager.mqh`, new `AttemptOrderSubmission`
function, account-wide bookkeeping calls added to the top of
`EvaluateAndJournal`), `TASKS.md`. New: this task file. No file under
`01_BASELINE/` touched.

## Out of scope

See Scope Boundary above. Also out of scope: exposing per-market-family
risk defaults, `CooldownManager.mqh`, `ExitManager.mqh`'s forced-close-
on-breach behavior, durable-intent persistence.

## Risks

- No independent review available this phase.
- **This is the single highest-stakes change in the project so far** —
  with `InpEnableOrderSubmission=true` and a demo/live account attached,
  this build WILL place real orders. The default `false` value means no
  behavioral change occurs unless a user deliberately flips it.
- The three-loss cooldown gap (see Scope Boundary) means a symbol that
  has just lost three trades in a row is not specially blocked by this
  build — only the pre-existing daily/weekly loss caps and drawdown
  reduction apply.
- No forced close on a loss-cap breach (see Scope Boundary) means a
  position opened just before a daily-loss-cap breach stays open until
  its own stop/target/intraday-boundary close, not force-closed
  immediately on breach detection.
- `AttemptOrderSubmission`'s no-concurrent-position check
  (`PositionsTotal()` scan) and the subsequent `OM_OpenPosition` call
  are not wrapped in any cross-tick lock — since `OnTick` only evaluates
  once per completed bar (the existing `g_last_evaluated_bar_time`
  guard) and this EA is single-instance per chart, no race condition is
  currently possible in practice, but this has not been verified under
  concurrent multi-chart/multi-instance use of the same magic number (a
  configuration this project has never sanctioned — magic numbers are
  meant to be unique per EA instance).
- Runtime confirmation (this build actually attaching, journaling, and
  — if a user deliberately enables it on a demo account — submitting a
  correctly-gated order) remains unperformed in this session, joining
  the same batched manual-verification backlog TASK-025 flagged, now
  with materially higher stakes given real order submission is
  reachable.

## Test plan

1. **Compile test**: full EA file, now including
   `DailyWeeklyLimits.mqh`/`EquityPeakManager.mqh`/
   `DrawdownController.mqh`/`OrderManager.mqh` on top of TASK-025's
   dependency set.
2. **Runtime test — not yet performed, batched, now the single highest-
   priority item in the project's verification backlog**: attach with
   `InpEnableOrderSubmission=false` first and confirm behavior is
   byte-for-byte identical to TASK-025 (journal populates, zero orders,
   `reasons_rejected_json` shows
   `"order_submission_disabled_InpEnableOrderSubmission_false"`); only
   after that is confirmed, and only on a demo account, attach with
   `InpEnableOrderSubmission=true` and confirm (a) a rejected-gate case
   logs the correct reason in `reasons_rejected_json`, (b) a fully-
   passed case places a real minimum-risk order and journals
   `risk_percent`/`stop` matching what was actually submitted, (c) the
   no-add-on rule genuinely prevents a second position while one is
   open.

## Acceptance criteria

- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation.
- [x] Default (`InpEnableOrderSubmission=false`) behavior is unchanged
      from TASK-025 by code inspection (order-submission code path is
      never entered; `AttemptOrderSubmission` is not called).
- [x] Every one of the 6 pre-submission gates from the Specification
      section is present, in the stated order, verified by code
      inspection.
- [x] Every rejection path sets a machine-readable reason string,
      per `PROJECT_RULES.md` rule 6.
- [x] No file under `01_BASELINE/` touched.
- [ ] Runtime confirmation (both `false` and `true` toggle states on a
      real demo chart) — not yet performed, the single highest-priority
      item in the project's batched manual-verification backlog.
- [ ] Independent review — not available this phase, but this task is
      flagged as the single strongest candidate to prioritize once
      budget returns.

## Rejection criteria

Rejected if any future inspection finds `InpEnableOrderSubmission=false`
does not fully suppress order submission, if any of the 6 gates can be
bypassed, or if a stop widened at step 4 is submitted to the broker
using the strategy's original (not the widened) distance.

## Implementation notes

`atr_values[0]` (the shared window's own most-recent-completed-bar ATR,
already computed once per bar for the strategies) is reused directly
for the stop floor/cap preflight rather than fetching ATR a second time
— consistent with the project's "compute shared data once" discipline
established in TASK-025.

## Commands run

```
git checkout -b claude/task-027-wire-order-manager
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\ThembaAdaptiveIntradayEA.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 7201 ms elapsed,
cpu='X64 Regular'` on the first attempt.

## Test results

**Compile test: PASS (real evidence, above).** **Runtime test: not yet
performed** — flagged as the single highest-priority item in the
project's batched manual-verification backlog, now materially higher-
stakes than any prior item in that backlog since real order submission
is reachable when the toggle is flipped.

## Commit

Pending — see `git log` on `claude/task-027-wire-order-manager`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean.** This build is now genuinely trading-capable, but
only when a user explicitly sets `InpEnableOrderSubmission=true` — the
default keeps it identical to TASK-025's journal-only behavior. Gaps
still open before this is a complete, production-grade trading system:
three-loss cooldown (`CooldownManager.mqh` does not exist),
durable-intent/idempotency persistence (spec section 12),
`ExitManager.mqh` (forced close on loss-cap breach, trailing
stop/breakeven/target-hit/momentum-failure/profit-giveback exits — spec
section 7's full exit priority list), `NewsManager.mqh` (Phase 7), and
real-world runtime confirmation of everything built so far.
