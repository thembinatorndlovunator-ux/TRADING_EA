# TASK-005 — MarketData: completed-bar logical-index accessor

## Objective

Implement `MarketData.mqh` per `00_MASTER_PROMPT_FOR_CLAUDE.md` section
23 (Phase 3, "Market data"): the single choke point through which every
other module reads price/ATR data, enforcing
`TASK-002_PHASE2_SPECIFICATION.md`'s "Data conventions" logical-index
rule (logical index 0 = most recently completed bar, MQL series index 1;
no formula anywhere reads the still-forming bar).

## Reason

Ledger item 11 ("completed-candle enforcement, project-wide") requires
this to be one rule, enforced once, not re-implemented per module. Every
future detection engine (regime, candlestick, chart-pattern, swing) reads
through `CMarketData` specifically so the logical→MQL index translation
happens in exactly one place — a bug here would otherwise need to be
independently avoided by every downstream module instead of being
structurally impossible.

## Baseline behaviour

Both baselines read price arrays directly and inconsistently (V6.37's
confirmed intrabar reads in two candlestick helpers, per
`baseline_v637_audit.md`) — this module exists specifically to make that
class of defect unavailable in the new engine, not to port either
baseline's own array-indexing pattern.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md`, "Data conventions" section; ledger
item 11; `PROJECT_RULES.md` rules 4 and 5.

## Specification

`CMarketData::Init(symbol, timeframe)` binds the instance.
`HasBars(count)` returns true iff logical indices `0..count-1` are all
available (`Bars(symbol, tf) >= count + 1`). `GetOpen/High/Low/Close/
Time/TickVolume(logical_index, &value)` each translate to MQL series
index `logical_index + 1` via `CopyOpen`/`CopyHigh`/etc., returning false
(not an implicit zero) on a negative index or unavailable history.
`GetATR(logical_index, &value, period=14)` wraps `iATR`/`CopyBuffer` with
per-period handle caching (a distinct handle per requested period,
created once and reused for the instance's lifetime).

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/MarketData.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_MarketData.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

`SessionManager.mqh`, `RiskManager` and the rest of Phase 3. Indicator
wrappers beyond ATR (EMA/ADX, needed by the regime engine) — deferred to
the task that implements `MarketRegimeEngine.mqh` in Phase 4, which is
this module's first real consumer beyond its own test.

## Risks

- No independent review available this phase (same as TASK-003/004).
- **Runtime verification: now a confirmed, recurring environment
  limitation, not a per-task fluke.** Three consecutive attempts
  (TASK-003, TASK-004, TASK-005) to run a compiled test script against a
  live terminal in this session's environment have not produced runtime
  evidence. This attempt went further than before: the terminal's
  "Virtual Hosting" subsystem got stuck in a multi-minute retry loop
  (`failed to get logs [1003] (raw - read failed, 0 wsa error, 1 bytes
  needed)`, repeating every ~2 seconds) and never reached script
  execution — `bases\gvariables.dat`'s timestamp never changed. This
  looks like a genuine defect/limitation in how this sandboxed session
  reaches the terminal's network path, not something fixable by retrying
  with a longer timeout. **Decision:** I will stop re-attempting a live
  terminal run on every future task — it costs real time and has not
  once produced evidence across three tries. Compile evidence remains
  real and mandatory every task; runtime confirmation is deferred to a
  manual run by the user (or a session with genuine desktop access) at a
  convenient checkpoint, covering all pending scripts at once rather than
  one attempt per task.

## Test plan

1. **Compile test** (completed, see Compiler result).
2. **Logic test** (compiled, not yet runtime-confirmed — see Risks):
   `Test_MarketData.mq5` must print all-PASS covering: bar-availability
   bounds, negative-index rejection on every accessor, logical-index-0
   OHLC internal consistency (`low <= open,close <= high`), the core
   completed-candle guarantee (`time[0] + period_seconds <= now`),
   logical index 1 strictly preceding logical index 0, and ATR handle
   caching (two calls at the same period return the same value; a second
   distinct period also reads successfully).

## Acceptance criteria

- [x] `MarketData.mqh` implements the logical-index convention exactly
      as specified.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation.
- [ ] Logic test confirmed all-PASS on a real desktop MT5 session — not
      yet confirmed; now a known, accepted, batched-for-later item (see
      Risks) rather than a per-task open question.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if the logic test, once run, produces any `FAIL` — most
importantly the completed-candle guarantee, which is this module's entire
reason for existing.

## Implementation notes

ATR handle caching stores `(period, handle)` pairs in two parallel
dynamic arrays rather than a struct array, matching the simplest MQL5
idiom for this; a distinct-period second lookup and a same-period
repeated lookup are both exercised in the test to catch a caching bug
that either recreates handles needlessly or returns a stale value across
periods.

## Commands run

```
git checkout -b claude/task-005-market-data
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_MarketData.mq5" /log:...
```
Plus a terminal launch attempt identical in form to TASK-003/004's — see
Risks for why it did not produce runtime evidence this time either.

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 779 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt. Full log available in
this session's history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not
confirmed** — see Risks for the now-confirmed, recurring reason.

## Commit

Pending — see `git log` on `claude/task-005-market-data`.

## Reviewer

Not available this phase.

## Final decision

**Compiled and committed; logic-test runtime confirmation batched with
TASK-003/004's for a single future manual session**, per the Risks
section's decision to stop re-attempting live-terminal runs per task.
