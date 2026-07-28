# TASK-004 — SymbolProfile and BrokerValidator

## Objective

Implement the next Phase 3 ("Common core") module per
`00_MASTER_PROMPT_FOR_CLAUDE.md` section 23: `SymbolProfile.mqh` (read
and cache a symbol's broker-reported trading properties) and
`BrokerValidator.mqh` (judge those properties against
`TASK-002_PHASE2_SPECIFICATION.md` section 8's mandatory attach-time
validation rule), kept as two modules with one responsibility each, per
master-prompt section 22.

## Reason

Every later risk calculation (`RiskManager`, `DailyWeeklyLimits`, the
per-position risk formula) reads tick value, tick size, contract size,
and volume constraints from this module — getting it right now, with its
own dedicated test, is cheaper than debugging a wrong risk number two
tasks from now. This module has no dependency on `StateManager` (TASK-003)
and can proceed independently of that task's outstanding runtime-
verification gap.

## Baseline behaviour

Neither baseline EA has an equivalent dedicated, fail-closed symbol
validation module — `RISK_POLICY.md`'s validation requirement ("Validate
tick value, tick size, contract size, volume step, stop level, freeze
level, filling mode, and margin") is a new-engine requirement, not a
ported baseline behaviour. No file under `01_BASELINE/` is touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 8 ("A mandatory `OnInit`/
symbol-attach validation routine checks tick value, tick size, contract
size, volume min/max/step, stop level, freeze level, filling mode, and
margin; any failure fails the symbol closed"); round-3 review finding 8
("does not select loss-side tick value" — `tick_value_loss` is read and
validated explicitly here to close that gap for the future risk-formula
task); `RISK_POLICY.md` line 19; `PROJECT_RULES.md` rule 6 (every
rejection needs a machine-readable reason — `BV_ValidateSymbolProfile`
returns every failing check's reason, not just the first).

## Specification

- `CSymbolProfile::Load(symbol)` reads `SYMBOL_TRADE_TICK_VALUE`,
  `SYMBOL_TRADE_TICK_VALUE_PROFIT`, `SYMBOL_TRADE_TICK_VALUE_LOSS`,
  `SYMBOL_TRADE_TICK_SIZE`, `SYMBOL_TRADE_CONTRACT_SIZE`,
  `SYMBOL_VOLUME_MIN/MAX/STEP`, `SYMBOL_POINT`, `SYMBOL_MARGIN_INITIAL`,
  `SYMBOL_DIGITS`, `SYMBOL_TRADE_STOPS_LEVEL`,
  `SYMBOL_TRADE_FREEZE_LEVEL`, `SYMBOL_FILLING_MODE`, using the
  bool-returning reference overloads of `SymbolInfoDouble`/
  `SymbolInfoInteger` so a genuinely failed platform read is
  distinguishable from a legitimately zero-valued field. `loaded` is
  true only if every read succeeded.
- `BV_ValidateSymbolProfile(profile, reasons[])` returns false if
  `loaded` is false (immediate, total failure — no other field is
  trustworthy) or if any of `tick_value`, `tick_value_loss`, `tick_size`,
  `contract_size`, `volume_min`, `volume_step` is `<= 0`, `volume_max <
  volume_min`, `point <= 0`, or `stop_level_points`/`freeze_level_points
  < 0`. Every failing check appends its own reason string — the function
  does not stop at the first failure. `filling_mode == 0` and
  `margin_initial == 0` are explicitly **not** treated as failures (both
  are legitimate broker-reported values, per the module's own header
  comment) — a genuinely failed read of either is instead caught by
  `loaded == false`.

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/SymbolProfile.mqh`,
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/BrokerValidator.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_SymbolProfile_BrokerValidator.mq5`, this
task file. Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

- The "reject broker minimum volume when actual risk exceeds the cap"
  rule (`RISK_POLICY.md`) — that check needs a stop-loss distance and
  account equity, which are per-trade inputs `SymbolProfile` does not
  have; it belongs to the future `RiskManager` task.
- `OrderCalcMargin`/`OrderCalcProfit` cross-checks — per-trade, not
  attach-time; future `RiskManager` task.
- `MarketData.mqh`, `SessionManager.mqh`, and the rest of Phase 3.

## Risks

- No independent review available this phase (same as TASK-003).
- Runtime confirmation is the same open item as TASK-003: this session's
  environment could not host a live chart to run the test script's
  `OnStart`. See Test results below for what real evidence was and
  wasn't obtained this time.
- `InpTestSymbol` defaults to `"EURUSD"` — if the connected account does
  not carry that symbol, test 1 and everything gated behind
  `loaded_ok` will be skipped (the script prints a `NOTE:` line
  explaining this rather than reporting a false failure); tests 2–4 do
  not depend on it and always run.

## Test plan

1. **Compile test** (completed, see Compiler result).
2. **Logic test** (compiled, not yet runtime-confirmed — same gap as
   TASK-003): `Test_SymbolProfile_BrokerValidator.mq5` must print all-PASS
   covering: a real symbol loading cleanly and validating with zero
   reasons; a bogus symbol name failing to load and producing exactly the
   `symbol_profile_load_failed` reason; single-field corruptions each
   producing exactly their own reason and no others; a multi-field
   corruption producing exactly three reasons simultaneously; and
   `filling_mode`/`margin_initial` being zero not causing a failure on an
   otherwise-valid profile.

## Acceptance criteria

- [x] `SymbolProfile.mqh`/`BrokerValidator.mqh` implement exactly the
      fields and checks specified in `TASK-002_PHASE2_SPECIFICATION.md`
      section 8.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation.
- [ ] Logic test confirmed all-PASS on a real desktop MT5 session — not
      yet confirmed; same outstanding item as TASK-003.
- [x] Every validator failure produces its own distinct, machine-readable
      reason (verified by code inspection and by the test's multi-field
      corruption case design).
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if the logic test, once run, produces any `FAIL` line, or if
review finds a check that silently stops after the first failure instead
of reporting every failing field, or finds `filling_mode`/`margin_initial`
being incorrectly treated as hard failures when zero is a legitimate
broker value.

## Implementation notes

`BrokerValidator.mqh` lives under `Risk/`, not `Market/`, matching
master-prompt section 22's architecture tree exactly — `SymbolProfile`
is pure data access (`Market/`), `BrokerValidator` is a risk-relevant
judgment over that data (`Risk/`). `SymbolProfile.mqh` itself makes no
pass/fail judgment about the values it reads, keeping the
single-responsibility split clean between the two files.

## Commands run

```
git checkout -b claude/task-004-symbol-profile
mkdir -p 03_SOURCE_CODE/MQL5/Include/ThembaEA/Market 03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_SymbolProfile_BrokerValidator.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 852 ms elapsed,
cpu='X64 Regular'` — clean on the first compile attempt (unlike TASK-003,
which needed one control-flow fix). Full log available in this session's
history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not
confirmed** — same environment limitation as TASK-003 (no live-chart
context available in this session to run `OnStart`). The script is
visible in the Navigator via the same junction TASK-003 set up
(`MQL5\Scripts\ThembaEA`) and is ready for a manual run.

## Commit

Pending — see `git log` on `claude/task-004-symbol-profile`.

## Reviewer

Not available this phase — same as TASK-003.

## Final decision

**Compiled and committed; logic-test runtime confirmation outstanding**,
same open item as TASK-003 — both scripts can be confirmed in one manual
session once convenient.
