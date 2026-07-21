# TASK-025 — ThembaAdaptiveIntradayEA: the first real Expert Advisor

## Objective

Wire every module built across TASK-003 through TASK-024 into an actual
compilable Expert Advisor: `03_SOURCE_CODE/MQL5/Experts/
ThembaAdaptiveIntradayEA.mq5`. This is the first file in the project
that is a real `OnInit`/`OnTick` EA, not a library module or a
standalone test script — the first artifact a user could literally
attach to a live MT5 chart.

## Reason

Every prior task built and tested one piece in isolation (or, from
TASK-019 onward, composed a few pieces together). This task is the
integration point that proves the whole pipeline — regime
classification, all five strategies, routing, conflict resolution,
journaling — actually runs together inside a real `OnTick` loop, not
just inside a test script's `OnStart`.

## Baseline behaviour

Not applicable — new-engine architecture. No file under `01_BASELINE/`
is touched, and this EA is entirely separate from both preserved
baseline EAs.

## Evidence

Every prior task's module (TASK-005 through TASK-024) is included and
exercised here. `CLAUDE.md`'s workflow and risk-management instructions
governed the scope decision below.

## Specification

`OnInit` loads and validates the symbol profile
(`BrokerValidator.mqh`, fail-closed on any validation error) and
initializes `CMarketData`. `OnTick` evaluates once per newly completed
bar only (never per tick), matching this project's completed-bar-only
convention throughout: classifies the regime once
(`MRE_ClassifyLive`), reads one shared OHLC/ATR window, computes
`MarketStructure` once, evaluates all five strategies against that same
shared data (no redundant regime/array/structure recomputation per
strategy), converts each result via `SignalScorer.mqh`'s adapters,
routes and resolves via `StrategyRouter.mqh`/`ConflictResolver.mqh`, and
journals the outcome via `DecisionJournal.mqh` — win or no-trade, every
bar's decision is recorded.

## **THE SINGLE MOST IMPORTANT SCOPE DECISION IN THIS TASK**

**This EA never submits, modifies, or closes a position it did not
itself open, because it never opens one at all.** No `OrderManager.mqh`
exists yet; no position sizing via `RiskManager.mqh` happens; no
`CTrade` call to open a position is made anywhere in this file. The one
place this EA touches live trading state at all is
`IntradayCloseManager.mqh`'s boundary-close check, which is scoped
strictly to this EA's own magic number (`InpMagicNumber`) — since this
build never opens anything under that magic, that call is a safe no-op
in practice. This is a deliberate, hard scope boundary, not an oversight
or a "TODO" left implicit: actual order submission is a separate,
higher-stakes task requiring its own dedicated scrutiny (real risk-cap
enforcement before submission, real position sizing, real broker
result-code checking on every operation) that this task does not
attempt.

## Files affected

New:
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5`, this task
file. Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

Order submission (`OrderManager.mqh`, position sizing, real `CTrade`
calls to open a position) — explicitly, deliberately deferred, see
above. Exposing every strategy's dozen-plus tuning parameters as `input`
variables (currently hard-coded local constants inside
`EvaluateAndJournal`, matching the defaults used throughout this
project's test scripts) — a future calibration-focused task. News
integration (`NewsManager.mqh` does not exist yet — this EA has no
`NEWS_BLACKOUT` awareness beyond what `MarketRegimeEngine.mqh` itself
already handles internally, which is none, since that module also
accepts news state as a caller-supplied stub it was never wired to).

## Risks

- No independent review available this phase.
- **This is the first module in the project that cannot be verified with
  a companion `Test_*.mq5` script** — an EA's `OnInit`/`OnTick` lifecycle
  isn't exercised by a script's `OnStart` the way every prior module's
  logic was. Verification here is: (a) real compilation (achieved,
  0 errors/0 warnings after fixing a real `#property version` format
  issue), and (b) attaching it to a real chart and watching the journal
  file populate — which joins the same batched manual-verification
  backlog every strategy/detection module's live wrapper has been
  waiting in, except this is the first item in that backlog that would
  actually demonstrate the FULL pipeline running live, not one module's
  wrapper in isolation.
- The five strategies' configuration values are hard-coded to this
  project's own test-script defaults, not yet independently tuned or
  exposed for calibration — stated explicitly as provisional, matching
  every strategy module's own "provisional target formula" disclosures.
- `EvaluateAndJournal` calls `MS_ComputeStructureArray` without checking
  its own return value (the structure's `valid` field is checked
  downstream by whichever strategy needs it, per each strategy's own
  established `!structure.valid -> return false` pattern) — this is
  consistent with how every strategy module already handles an invalid
  structure internally, not a new gap introduced here.

## Test plan

1. **Compile test** (completed, see Compiler result): a real
   `#property version` format defect was found and fixed (MQL5 requires
   `xxx.yyy`-shaped version strings; `"0.1"` and `"0.100"` were both
   rejected before `"1.00"` was accepted).
2. **Runtime test — not yet performed, batched with the project's
   existing runtime-verification backlog, but flagged as the single most
   valuable item in that backlog**: attaching this EA to a real chart
   (demo account) and confirming (a) `OnInit` succeeds and logs
   initialization, (b) `OnTick` fires once per completed bar and logs a
   decision (or a `NoTrade` reason) every time, (c) the journal file
   (`MQL5\Files\ThembaEA\Journal\decisions_<date>.jsonl`) actually
   accumulates entries, and (d) no order is ever placed (confirmed via
   the account's own trade history staying empty while this EA runs).

## Acceptance criteria

- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation.
- [x] Never submits, modifies, or closes any position under any
      circumstance in this build (verified by code inspection — no
      `CTrade` open-position call exists anywhere in this file or in any
      module it composes, apart from `IntradayCloseManager.mqh`'s
      own-magic-scoped, currently-no-op close path).
- [x] Evaluates once per completed bar, not per tick.
- [x] Every one of the five strategy modules and the router/conflict-
      resolver pipeline is exercised in one real `OnTick` call.
- [ ] Runtime confirmation (attach to a real chart, observe journal
      entries accumulate) — not yet performed, the single highest-
      priority item in the project's batched manual-verification
      backlog.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if any future inspection finds an order-submission path this
task's own description claims does not exist, or if `OnTick` is found to
evaluate more than once per completed bar (defeating the completed-bar-
only convention this entire project has maintained since TASK-005).

## Implementation notes

Regime classification and the shared OHLC/ATR/structure computation
happen exactly once per bar and are passed into all five strategies'
`*Array` functions directly (not their `*Live` wrapper variants, which
would each redundantly reclassify the regime and re-fetch data) — a
direct efficiency and consistency improvement over calling each
strategy's own `_Live` wrapper independently, made possible because every
strategy module's array-based core was already designed for exactly this
kind of external composition from TASK-019 onward.

## Commands run

```
git checkout -b claude/task-025-ea-controller
mkdir -p 03_SOURCE_CODE/MQL5/Experts
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\ThembaAdaptiveIntradayEA.mq5" /log:...
```

## Compiler result

**Real, verified.** First attempt: `warning 68: version '0.1' is
incompatible with MQL5 Market, must be xxx.yyy`. Second attempt
(`"0.100"`): same warning persisted. Third attempt (`"1.00"`):
`Result: 0 errors, 0 warnings, 1865 ms elapsed, cpu='X64 Regular'` —
clean. Full logs available in this session's history; not committed
(build artifacts).

## Test results

**Compile test: PASS (real evidence, above).** **Runtime test: not yet
performed** — flagged as the single highest-priority item in the
project's batched manual-verification backlog, since it is the first
opportunity to see the entire pipeline run live rather than one module
in isolation.

## Commit

Pending — see `git log` on `claude/task-025-ea-controller`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed.** This is the first real Expert Advisor
in the project — journal-only, no order submission, by deliberate and
stated design. Remaining before a trading-capable build exists:
`OrderManager.mqh`/`PositionManager.mqh` (real order submission, wired to
`RiskManager.mqh`'s already-built sizing/validation functions), and
real-world runtime confirmation of everything built so far.
