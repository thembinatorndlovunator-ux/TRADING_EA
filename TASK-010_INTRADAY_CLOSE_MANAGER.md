# TASK-010 — IntradayCloseManager: the intraday boundary close

## Objective

Implement `IntradayCloseManager.mqh` per `00_MASTER_PROMPT_FOR_CLAUDE.md`
section 23 (Phase 3, "Intraday close"): close every one of this EA's own
open positions and cancel every one of its own pending orders at the
configured intraday boundary, per `TASK-002_PHASE2_SPECIFICATION.md`
section 8's fully-defined boundary rule. This is the last module in
Phase 3's "Common core" list.

## Reason

`RISK_POLICY.md` requires closing all exposure by the approved intraday
boundary. Section 8 corrected an earlier specification draft's "all
positions" wording (which conflicted with the own-magic-only closure
authority stated two paragraphs later) to explicitly "all of this EA's
own positions" — this task implements that corrected, precisely-scoped
rule, and is also the first module in this project to perform actual
trading operations (position close, order cancel), so it is the first
place both baselines' confirmed unchecked-`CTrade`-result defect is
directly addressed with real, checked replacement code.

## Baseline behaviour

TASK-001's audit found pervasive unchecked `CTrade` results in both
baselines, on every trading operation (`baseline_v637_audit.md`,
`baseline_v811_audit.md`). This module exists specifically to make that
defect structurally harder to reproduce: every `trade.PositionClose`/
`trade.OrderDelete` call here has its return value and `ResultRetcode()`
both checked, with a distinct machine-readable failure reason per ticket.
No file under `01_BASELINE/` is touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 8 ("Intraday boundary, fully
defined" and the account-wide close-scope rule). `RISK_POLICY.md` line
20. `PROJECT_RULES.md` rule 6 (machine-readable reason for every
operation).

## Specification

- `ICM_ShouldExecuteIntradayClose(hour=23, minute=45)` — true iff
  `SN_IsPastIntradayBoundary` (TASK-006) reports the boundary has passed
  **and** a fully successful close has not already run today in this
  session (an in-memory, not persisted, once-per-day guard — see Risks).
- `ICM_CloseAllOwnedPositions(magic, &reasons[])` — closes every open
  position carrying `magic`, across every symbol; never touches a
  position under a different magic. Returns true only if every close
  succeeded (checked via both the `CTrade` boolean result and
  `ResultRetcode()`); appends one machine-readable reason per failed
  ticket.
- `ICM_CancelAllOwnedPendingOrders(magic, &reasons[])` — the pending-order
  analogue; a pending order left open past the boundary would represent
  exposure opened after the boundary, so it is treated as part of the
  same close operation.
- `ICM_ExecuteIntradayClose(magic, &reasons[])` — runs both of the above,
  merges their reasons, and updates the once-per-day guard: **a full
  success suppresses further attempts for the rest of the day; anything
  less than full success keeps `ICM_ShouldExecuteIntradayClose` returning
  true so the caller retries on the next tick** — a deliberate
  fail-open-to-retry choice for a safety-critical operation.

## Files affected

New:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/IntradayCloseManager.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_IntradayCloseManager.mq5`, this task
file. Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

- Persisting the once-per-day guard across a restart (see Risks) — a
  future hardening task once `StateManager`'s per-instance namespace
  exists (TASK-003 only implemented the account-wide namespace).
- Retry backoff/rate-limiting on repeated failures — this first
  implementation retries every tick with no backoff; acceptable for now
  given the boundary window is a fixed once-daily event, not a
  high-frequency loop, but worth revisiting if a real failure mode
  produces tick-rate retry spam.
- Any orchestration of *when* `OnTick` calls this — no `EAController`
  exists yet.

## Risks

- No independent review available this phase.
- **This is the first module in the project whose test script performs
  real trading operations** (a minimum-volume market position and a
  pending order, under a dedicated, unmistakable test-only magic number,
  on a demo account) rather than only touching a safely-scoped state
  field or file. This is a deliberate choice — verifying close/cancel
  logic without ever actually opening/closing anything would not be real
  evidence — but it is a materially different risk category from every
  prior task's test script, flagged explicitly here and in the test
  script's own header warning. **Demo-account use only; the user should
  understand this before running it.**
- The once-per-day guard is in-memory only (module-level static
  variables), not persisted — a restart exactly at/after the boundary on
  a day the close already succeeded would allow one redundant close
  attempt (harmless — closing an already-closed position is a no-op scan
  that finds nothing to close — but stated as a known simplification, not
  a hidden gap).
- Test safety: the script refuses to run at all if the test magic already
  has any position/order open (rather than assuming a clean slate),
  specifically to avoid interfering with unrelated state under that
  magic from a prior interrupted run.

## Test plan

1. **Compile test** (completed, see Compiler result).
2. **Logic/live test** (compiled, not yet runtime-confirmed — batched,
   AND requires explicit user awareness given the real-trading-action
   caveat above): `Test_IntradayCloseManager.mq5` must print all-PASS
   covering: the boundary-due check; opening one real minimum-volume
   market position and confirming exactly one owned position exists;
   opening one real far-from-market pending order and confirming exactly
   one owned pending order exists; `ICM_ExecuteIntradayClose` reporting
   full success with zero failure reasons; zero owned positions and zero
   owned pending orders remaining afterward; and the once-per-day guard
   correctly suppressing an immediate redundant re-run.

## Acceptance criteria

- [x] `IntradayCloseManager.mqh` implements exactly the scope-corrected
      rule from `TASK-002_PHASE2_SPECIFICATION.md` section 8 (own-magic
      only, both positions and pending orders, every result checked).
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (clean on the first attempt).
- [ ] Logic test confirmed all-PASS on a real desktop MT5 session —
      batched with TASK-003 through 009's outstanding item, **with the
      additional caveat that this specific script performs real demo
      trading actions and should be run knowingly, not incidentally
      alongside the others.**
- [x] Every close/cancel failure produces its own machine-readable
      reason string; a full success produces zero reasons.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if the logic test, once run, produces any `FAIL` — most
importantly a leaked position/order remaining after
`ICM_ExecuteIntradayClose` reports success, which would mean the
success/failure reporting itself is untrustworthy.

## Implementation notes

Uses the standard MQL5 `<Trade\Trade.mqh>` `CTrade` class rather than
raw `OrderSend` — the class itself is standard, well-tested library code;
the defect this task avoids is TASK-001's finding that both baselines
called `CTrade` methods **without checking their results**, not the use
of `CTrade` itself. Every call here checks both the method's own boolean
return and `trade.ResultRetcode()` against the expected success codes.

## Commands run

```
git checkout -b claude/task-010-intraday-close-manager
mkdir -p 03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_IntradayCloseManager.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 841 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt. Full log available in
this session's history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic/live test: not
confirmed** — batched with TASK-003 through 009's outstanding item, with
the additional real-trading-action caveat noted above (this one should
not be run casually/unattended the way the other seven can be).

## Commit

Pending — see `git log` on `claude/task-010-intraday-close-manager`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed; logic-test runtime confirmation batched**
with the seven prior tasks' outstanding item, flagged for extra caution
given this script's real-trading-action nature. **This completes Phase
3's "Common core" list** (Market data, Symbol profile, Session manager,
Risk manager, Decision journal, Broker validator, Intraday close — all
eight items now have a corresponding, compiled module across TASK-003
through 010). Phase 4 ("Detection engines": swings, SR, structure,
candlesticks, chart patterns, ICT/SMC geometry, regimes, visuals) is the
next phase per the roadmap.
