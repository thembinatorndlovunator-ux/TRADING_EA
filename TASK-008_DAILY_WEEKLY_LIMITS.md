# TASK-008 — DailyWeeklyLimits, EquityPeakManager, DrawdownController

## Objective

Implement the `StateManager`-backed, persisted-state parts of Phase 3's
"Risk manager" bullet: `DailyWeeklyLimits.mqh` (period-change loss
tracking with deterministic cash-flow rebasing), `EquityPeakManager.mqh`
(daily and all-time equity peaks, feeding the daily giveback control and
drawdown), and `DrawdownController.mqh` (the risk-reduction formula that
consumes the drawdown figure) — per
`TASK-002_PHASE2_SPECIFICATION.md` section 8.

## Reason

This is `StateManager`'s (TASK-003) first real consumer — the account-
wide namespace TASK-003 built and only synthetically tested now gets
exercised with the actual fields section 8 specifies. It also closes the
specific defect round-3 review found in the specification itself: the
prior daily/weekly loss formula measured absolute floating P/L rather
than the change since the boundary (a position already at `-1000` at the
boundary and unchanged since would have wrongly re-counted as a new
`-1000` loss) — this task makes the corrected, period-change formula
executable.

## Baseline behaviour

V8.11's daily-limit anchor/reset has a confirmed numerator/denominator
mismatch across restarts and no weekly counterpart at all
(`baseline_v811_audit.md`); its persisted peak-drawdown key truncates a
`long` magic number with no account/server identifier. This task is the
new-engine replacement for both defects, not a port of either. No file
under `01_BASELINE/` is touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 8: "Daily/weekly loss —
corrected to measure actual period change", "Cash-flow treatment —
deterministic source", "Reset boundary — single clock", "Profit-
protection controls" (daily equity-peak giveback, corrected to actually
track a peak), and "Reduced risk after drawdown — peak/scope/reset
defined".

## Specification

- `DWL_EnsureDailyBaseline()` / `DWL_EnsureWeeklyBaseline()` — rebase the
  respective start-equity baseline to current equity when
  `SN_DailyBoundaryCrossed`/`SN_WeeklyBoundaryCrossed` (TASK-006) reports
  the boundary has passed since the last recorded reset; idempotent
  within the same period.
- `DWL_ApplyCashFlowAdjustments()` — scans `DEAL_TYPE_BALANCE` deals
  (MT5's own deposit/withdrawal/credit deal type) since the last-
  processed ticket, over a bounded 8-day trailing window, and adds each
  such deal's profit to both baselines immediately.
- `DWL_GetDailyChangePercent`/`DWL_GetWeeklyChangePercent` — `100 *
  (current_equity - start_equity) / start_equity`, signed (negative =
  loss). `DWL_IsDailyLossBreached`/`DWL_IsWeeklyLossBreached` — `change
  <= -cap_percent`.
- `EPM_EnsureDailyPeakBaseline`/`EPM_UpdateDailyPeak` — the daily peak,
  self-resetting at the daily boundary independently of
  `DailyWeeklyLimits`. `EPM_GetDailyGivebackPercent` — `100 *
  (daily_peak - current_equity) / daily_peak`, floored at 0.
  `EPM_IsDailyGivebackArmed(daily_start_equity, arm_percent)` — arms once
  the peak has risen `arm_percent` above the caller-supplied
  `daily_start_equity` (owned by `DailyWeeklyLimits`, passed in rather
  than duplicated).
- `EPM_UpdateAccountPeak`/`EPM_GetCurrentDrawdownPercent` — the all-time
  peak, never auto-reset. `EPM_ExplicitResetAccountPeak` — the one
  explicit, operator-only reset path, never called by ordinary risk
  logic.
- `DC_ComputeRiskMultiplier(drawdown_percent, max_reduction=10,
  min_multiplier=0.25)` — `clamp(1 - drawdown/max_reduction,
  min_multiplier, 1.0)`.

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/DailyWeeklyLimits.mqh`,
`EquityPeakManager.mqh`, `DrawdownController.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_DailyWeeklyLimits.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

- Wiring these into an actual `OnTick`/`OnTradeTransaction` handler, or
  into `RiskManager`'s (TASK-007) pre-trade gate — that requires an
  `EAController`/`OnInit` entry point that does not exist yet.
- The breach-response actions themselves (closing positions, cancelling
  pending orders, the `closure_pending` persisted record) — section 8's
  `OrderManager`/`PositionManager` responsibility, an `Execution/` module
  not in Phase 3's "Common core" scope.
- Session-trade/failed-level counters and the three-loss cooldown
  (per-symbol, per-instance namespace — a different namespace and a
  different owning module than this task's account-wide fields).
- Daily profit target (same formula shape as the loss cap, trivially
  addable later; left out here to keep this task's scope matched to its
  title).

## Risks

- No independent review available this phase.
- Runtime verification: batched with TASK-003 through 007's outstanding
  item.
- **Cash-flow ticket tracking stores a `ulong` deal ticket as a `double`**
  (`StateManager`'s only storage type). MT5 deal tickets are unlikely to
  exceed double-precision's 2^53 exact-integer range in this project's
  realistic lifetime, but this is a known, stated approximation, not an
  unlimited guarantee — flagged here rather than silently assumed safe
  forever.
- **The 8-day cash-flow scan window** is a deliberate bound (see
  `DailyWeeklyLimits.mqh`'s header comment) to keep `HistorySelect` cheap
  on every call; an EA outage longer than 8 days would miss rebasing for
  a cash event that occurred in the unscanned gap. This is an accepted,
  stated trade-off for a first implementation, not an oversight — a
  longer window is a one-line change if a real outage of that length
  becomes a concern.
- `EPM_IsDailyGivebackArmed`'s `daily_start_equity` parameter is supplied
  by the caller rather than read internally, so it is possible to call it
  with a stale value if `DailyWeeklyLimits` hasn't been kept in sync —
  this coupling is deliberate (keeps the two modules independently
  testable) but does mean a future orchestrator must pass the same
  `daily_start_equity` both modules would otherwise agree on.

## Test plan

1. **Compile test** (completed, see Compiler result).
2. **Logic test** (compiled, not yet runtime-confirmed — batched):
   `Test_DailyWeeklyLimits.mq5` must print all-PASS covering: daily/
   weekly baseline first-set and same-period no-op behavior; a forced
   stale-reset-timestamp scenario correctly triggering a fresh rebase;
   signed change-percent computation; loss-breach detection both firing
   (artificially inflated start-equity) and not firing (start equals
   current equity); the cash-flow scan completing without error; daily
   peak set/non-decreasing behavior; daily giveback percent and arming
   (both armed and not-armed cases); all-time account peak set/drawdown-
   near-zero-at-set behavior; the explicit reset path; and
   `DC_ComputeRiskMultiplier` hand-verified at five boundary points
   (zero drawdown, half the reduction range, exactly at the reduction
   cap, beyond the reduction cap, and a defensive negative-drawdown
   case). Every account-wide test field is deleted at both the start and
   end of the run, leaving no residue on the real connected account.

## Acceptance criteria

- [x] All three modules implement exactly the formulas specified in
      `TASK-002_PHASE2_SPECIFICATION.md` section 8.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (all three new modules plus the test script, clean on the first
      attempt).
- [ ] Logic test confirmed all-PASS on a real desktop MT5 session —
      batched with TASK-003 through 007's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [x] The daily-peak-vs-account-peak conflation round-3 review implicitly
      guarded against (two distinct reset rules) is structurally
      impossible to blur here — they are two distinctly-prefixed,
      independently-reset fields, not one shared value.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if the logic test, once run, produces any `FAIL` — most
importantly the stale-boundary-forces-rebase case (the exact defect this
task exists to fix relative to V8.11's baseline) and the loss-breach
detection cases.

## Implementation notes

`EquityPeakManager` deliberately does not depend on `DailyWeeklyLimits`
having run first — each module tracks its own reset timestamp
independently, even though both reset at the same daily boundary. This
trades a small amount of redundant boundary-checking for the absence of
an inter-module ordering dependency, which is worth it at this stage:
a future orchestrator (`EAController`, not yet built) is free to call
these functions in any order without a hidden "must call X before Y"
requirement.

## Commands run

```
git checkout -b claude/task-008-daily-weekly-limits
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_DailyWeeklyLimits.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 628 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt, across all three new
`.mqh` files plus the test script. Full log available in this session's
history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not
confirmed** — batched with TASK-003 through 007's outstanding runtime-
verification item.

## Commit

Pending — see `git log` on `claude/task-008-daily-weekly-limits`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed; logic-test runtime confirmation batched**
with the five prior tasks' outstanding item. This closes the
`StateManager`-consuming half of Phase 3's "Risk manager" bullet;
`DecisionJournal.mqh` and `IntradayCloseManager.mqh` remain to complete
Phase 3.
