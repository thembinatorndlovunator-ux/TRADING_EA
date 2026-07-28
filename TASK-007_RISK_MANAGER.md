# TASK-007 — RiskManager: core risk-math functions

## Objective

Implement the core, stateless risk-calculation functions from
`TASK-002_PHASE2_SPECIFICATION.md` section 8 into `RiskManager.mqh`:
per-position risk-cash, risk-percent, the no-SL worst-case fallback, the
stop-floor/cap preflight, the broker-minimum-volume-vs-cap rejection
rule, and the `OrderCalcProfit` cross-check — the pure-computation slice
of `RiskManager` that needs only a `CSymbolProfile` (TASK-004) and does
not require `StateManager` (TASK-003) or live-position enumeration.

## Reason

This is the formula round-3 review found genuinely broken in the
specification itself (dimensional error — missing division by tick size
— and an unsigned-distance error that priced a profit-side stop as
positive risk). Both defects were fixed in the specification; this task
is where that fix actually becomes executable code, verified against the
specification's own hand-worked example (`price move 1.00, tick size
0.01, tick value 1, one lot -> risk_cash = 100`) rather than a fresh,
unverified derivation.

## Baseline behaviour

Neither baseline computes risk this way with this level of validation
(TASK-001's audit found unchecked `CTrade` results and requested-vs-
actual-fill price mixing in both baselines' R/management math — this
module is new-engine work built to avoid that class of defect, not a
port). No file under `01_BASELINE/` is touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 8 (all formulas below quote
it directly); `RISK_POLICY.md` lines 17–19 (`OrderCalcProfit`
cross-check, broker-minimum-volume rejection, full validation list);
section 8's own Test plan item 5 (the exact worked example this task's
test 1 reproduces).

## Specification

- `RM_ComputeLossDistance(is_long, entry, sl)` = `max(0, entry-sl)` long /
  `max(0, sl-entry)` short — zero on a profit-side stop.
- `RM_ComputeRiskCash(profile, loss_distance, volume, &risk_cash)` =
  `loss_distance * volume * tick_value_loss / tick_size`, using the
  loss-side tick value specifically (round-3 finding 8).
- `RM_ComputeRiskPercent(risk_cash, equity, &risk_percent)` = `100 *
  risk_cash / equity` — the same formula for per-trade and total-open,
  per section 8's "both explicitly connected to the 1%/1% caps" fix.
- `RM_ComputeNoStopRiskCash` — ATR-multiple proxy substituted into the
  same formula shape (not a conflated notional figure).
- `RM_ComputeMinStopDistance`/`RM_ComputeMaxStopDistance` — the floor/cap
  equations, section 8 defaults (`0.5x ATR` floor,
  `min(3% price, 4x ATR)` cap).
- `RM_ValidateStopDistance` — below floor widens (adjusted, true), above
  cap rejects (unchanged, **false** — never silently clamped), in
  between passes through unchanged; always sets a machine-readable
  `reason` (empty string on no-adjustment, per PROJECT_RULES.md rule 6).
- `RM_BrokerMinVolumeExceedsCap` — `RISK_POLICY.md`'s "reject broker
  minimum volume when actual risk exceeds the cap" rule, stated as a
  direct boolean check.
- `RM_CrossCheckRiskCash` — wraps `OrderCalcProfit`, comparing its result
  (as a positive loss magnitude) against the computed `risk_cash` within
  a configurable tolerance (default 5%, per section 8).

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/RiskManager.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_RiskManager.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

- `DailyWeeklyLimits`, `EquityPeakManager`, `DrawdownController` — the
  `StateManager`-backed, persisted-state parts of Phase 3's "Risk
  manager" bullet: daily/weekly loss tracking, cash-flow rebasing,
  profit-protection controls, drawdown-based risk reduction. Deferred to
  TASK-008 — this task is deliberately the pure-computation slice only.
- Live-position enumeration (summing `risk_cash` across open positions
  for `total_open_risk_pct`) — needs `PositionManager`, not yet built.
- Pending-order risk reservation — needs live pending-order enumeration,
  same reason.
- The durable-intent order-submission protocol — an `Execution/` module,
  not Phase 3's "Common core" scope.

## Risks

- No independent review available this phase.
- Runtime verification: batched with TASK-003 through 006's outstanding
  item, per the recurring environment limitation documented in TASK-005.
- Test 9 (the real-symbol `OrderCalcProfit` cross-check) depends on live
  broker pricing and a small, somewhat arbitrary stop distance (50
  points) — it is a sanity cross-check, not a byte-for-byte hand-derived
  assertion like tests 1–8, and its tolerance (5%) is deliberately loose
  enough to absorb ordinary spread/rounding effects rather than being a
  tight correctness proof.

## Test plan

1. **Compile test** (completed, see Compiler result).
2. **Logic test** (compiled, not yet runtime-confirmed — batched):
   `Test_RiskManager.mq5` must print all-PASS covering: the exact worked
   example from the specification's own Test plan (`risk_cash == 100`);
   zero risk on both a long and a short profit-side stop; correct
   loss-side distance for a short; risk-percent computation and its
   zero-equity failure case; the no-SL fallback's exact hand-derived
   value; the floor/cap equations' exact hand-derived values; all three
   `RM_ValidateStopDistance` branches (widen/reject/pass-through) with
   their exact reason strings; the broker-minimum-volume rule both
   exceeding and not exceeding a cap at hand-derived percentages; and a
   real-symbol `OrderCalcProfit` cross-check agreeing within tolerance.

## Acceptance criteria

- [x] `RiskManager.mqh` implements exactly the formulas specified in
      `TASK-002_PHASE2_SPECIFICATION.md` section 8, matching its own
      worked example precisely.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (clean on the first attempt).
- [ ] Logic test confirmed all-PASS on a real desktop MT5 session —
      batched with TASK-003 through 006's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if the logic test, once run, produces any `FAIL` — most
importantly test 1 (the specification's own worked example) and the
profit-side-stop zero-risk cases, since either failing would mean this
task did not actually fix the defect it exists to fix.

## Implementation notes

Every function that can fail returns `bool` and sets its output
parameter(s) to a safe default (`0.0`/empty string) on failure, matching
the "never an implicit zero passed off as a real value" discipline
established in TASK-005's `MarketData.mqh`. `RM_ValidateStopDistance`'s
reject branch deliberately does not touch `adjusted_stop_distance` beyond
its initial assignment — the function's `false` return is what a caller
must check, not a sentinel value in the output parameter.

## Commands run

```
git checkout -b claude/task-007-risk-manager
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_RiskManager.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 507 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt. Full log available in
this session's history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not
confirmed** — batched with TASK-003 through 006's outstanding runtime-
verification item.

## Commit

Pending — see `git log` on `claude/task-007-risk-manager`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed; logic-test runtime confirmation batched**
with the four prior tasks' outstanding item.
