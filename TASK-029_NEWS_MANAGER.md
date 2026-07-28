# TASK-029 — NewsManager: the news system core (begins Phase 7)

## Objective

Build the news system's provider-agnostic core and its two concrete
providers, per `NEWS_INTEGRATION_SPEC.md` and
`TASK-002_PHASE2_SPECIFICATION.md` section 10:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/News/NewsManager.mqh`
(`SNewsEvent` provider-interface shape, the `NEWS_BLACKOUT` predicate,
and its spread-normalization extension), `MT5CalendarProvider.mqh` (the
live metals provider, wrapping MQL5's native Calendar functions), and
`NullNewsProvider.mqh` (the synthetics provider — always zero events).

## Reason

Every module built through TASK-028 has explicitly named this as an
open gap: `MarketRegimeEngine.mqh`'s own header states "`NEWS_BLACKOUT`
is accepted as a caller-supplied boolean (section 10's news system is
Phase 7 work, not yet built)"; TASK-025's Out of scope section states
"this EA has no `NEWS_BLACKOUT` awareness... since that module also
accepts news state as a caller-supplied stub it was never wired to."
This task begins closing that gap, standalone and tested first —
matching TASK-026's `OrderManager.mqh` precedent (build and test the
module on its own, wire it into the live EA as a separate, later
decision).

## Baseline behaviour

Not applicable — new-engine module. No file under `01_BASELINE/` is
touched. (Neither baseline EA has any economic-calendar integration —
V6.37's `InpNewsHourServer`/`InpNewsMinuteServer` were manually-entered
HH:MM values overwritten onto the current server date, not a computed
provider read at all, per section 10's "Baseline correction.")

## Evidence

`NEWS_INTEGRATION_SPEC.md` (full file, reproduced/implemented here) and
`TASK-002_PHASE2_SPECIFICATION.md` section 10.

## Specification

- **`SNewsEvent`** (`NewsManager.mqh`): the provider-interface fields,
  verbatim from `NEWS_INTEGRATION_SPEC.md`'s "Provider interface"
  section — `event_id`, `event_name`, `currency`, `importance`,
  `scheduled_utc`, `scheduled_server_time`, `scheduled_botswana_time`,
  `previous`, `forecast`, `actual`, `revision`, `source`,
  `retrieved_at`, `status`.
- **`NM_IsInBlackoutWindowArray`** (`NewsManager.mqh`): the base
  predicate — true iff the current server time falls within
  `[scheduled_server_time - InpNewsBlackoutBeforeMinutes,
  scheduled_server_time + InpNewsBlackoutAfterMinutes]` for any event at
  or above `min_importance`, per section 10's concrete blackout-window
  parameters (defaults 15/15 minutes).
- **`NM_IsInBlackoutWindowExtended`** (`NewsManager.mqh`): as above, plus
  extends the blackout past the nominal window end while
  `current_spread > ATR × max_spread_atr_multiple` (spread not yet
  normalized), per section 10's "extended if spread has not
  normalized... by the nominal end of the window" — using the same
  `UNTRADEABLE_SPREAD_OR_LIQUIDITY` spread-vs-ATR formula already
  defined in `MarketRegimeEngine.mqh`'s `MRE_IsUntradeableSpreadOrLiquidity`
  (not re-derived, the same comparison reused inline).
- **`MTC_FetchEvents`/`MTC_IsInBlackoutNow`** (`MT5CalendarProvider.mqh`):
  wraps `CalendarValueHistory`/`CalendarEventById`/`CalendarCountryById`
  into `SNewsEvent`, filtered by currency and `min_importance`; the live
  wrapper composes a fetch + `NM_IsInBlackoutWindowExtended` call against
  the real current server time and real current spread/ATR — matching
  every other detection engine's "array-based core + live wrapper" split.
- **`NNP_FetchEvents`** (`NullNewsProvider.mqh`): always returns 0
  events, per "Deriv synthetic indices use `NullNewsProvider`. Do not
  apply macroeconomic event direction or blackout logic."

## **STATED ASSUMPTIONS AND INTERPRETATION CHOICES**

1. **`scheduled_botswana_time` assumes UTC+2** (Central Africa Time, no
   daylight saving) — no project document states an explicit offset;
   this is this task's own documented choice
   (`MTC_BOTSWANA_UTC_OFFSET_SECONDS` in `MT5CalendarProvider.mqh`).
2. **`MqlCalendarValue.time` is assumed to be UTC** per MQL5's own
   Calendar-function documentation (unlike bar/tick timestamps
   elsewhere in this project, which are broker server time) — NOT
   independently confirmed against a live feed in this sandboxed
   session; flagged for the batched runtime-verification backlog.
3. **The spread-extension is capped at `max_extension_minutes`**
   (test default 30) — the spec says "extended if spread has not
   normalized... by the nominal end," with no stated bound on how long
   an extension may run. An unbounded extension would mean a
   permanently wide spread blackouts trading forever, which does not
   seem to be the spec's intent; this task adds an explicit cap as its
   own interpretation, flagged here for confirmation.
4. **The no-add-on-style "same symbol/direction" nuance does not apply
   here** — news blackout is currency-scoped (all metals sharing a
   currency are blocked together), not symbol- or direction-scoped, per
   the spec's own provider-interface shape (events carry `currency`, not
   `symbol`).

## **SCOPE BOUNDARY — NOT WIRED INTO THE LIVE EA**

This module is built and compiled (including a real MT5-Calendar
field-mapping smoke test), but `ThembaAdaptiveIntradayEA.mq5` is **not**
modified by this task and does not include any News module. Wiring
`NEWS_BLACKOUT` into the live EA's regime read requires also fixing two
other pre-existing, already-documented gaps from TASK-025 at the same
time for the fix to be coherent:
`MRE_IsUntradeableSpreadOrLiquidity` (built in TASK-016, never called by
the live EA) and `MRE_ApplyHysteresis` (built in TASK-016, never called
by the live EA — `EvaluateAndJournal` currently uses the raw,
un-hysteresis'd `regime_read.regime` directly). Bundling a partial fix
(news only) into the live EA without also fixing the other two would
leave the regime-gating logic in a half-wired, arguably more confusing
state than leaving all three visibly un-wired together. A dedicated
follow-up "regime gating" task should wire all three at once. Also not
built: the CSV/SQLite deterministic-backtest provider
`NEWS_INTEGRATION_SPEC.md`'s "Backtesting" section requires, and the
optional/secondary cached Fair Economy adapter (explicitly marked
optional in the spec).

## Files affected

New:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/News/NewsManager.mqh`,
`MT5CalendarProvider.mqh`, `NullNewsProvider.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_NewsManager.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.
`ThembaAdaptiveIntradayEA.mq5` and `MarketRegimeEngine.mqh` are NOT
modified.

## Out of scope

See Scope Boundary and Stated Assumptions above. Also: per-market-family
provider SELECTION logic (which provider a caller uses for which
symbol) is the live EA's own responsibility once wired — this task
provides both providers but does not decide when each is used.

## Risks

- No independent review available this phase.
- The MT5-Calendar field-mapping (`MTC_FetchEvents`) compiled clean on
  its own, best-effort understanding of the `MqlCalendarValue`/
  `MqlCalendarEvent`/`MqlCalendarCountry` structures' field names —
  compiling clean confirms the field names/types are correct per this
  MetaEditor build, but does NOT confirm the semantic correctness of the
  timezone assumption (see Stated Assumptions #2) or the fixed-point
  value decoding (`MTC_DecodeValue`) against a real released event's
  actual value, since no real high-importance event may occur during
  this session's runtime-verification window.
- The extension-cap interpretation (Stated Assumptions #3) is this
  task's own addition — a future reviewer may determine the spec
  intended no cap at all, or a different bound.

## Test plan

1. **Compile test**: `Test_NewsManager.mq5` (includes
   `MT5CalendarProvider.mqh`, which includes `NewsManager.mqh`, plus
   `NullNewsProvider.mqh`).
2. **Pure blackout-predicate tests (hand-verifiable, tests 1-10)**:
   exact-time, 14/16-minutes-before, 14/16-minutes-after boundary cases;
   `min_importance` filtering; empty-events-array negative case;
   spread-extension active/inactive/expired-cap cases.
3. **`NullNewsProvider` test (test 11)**: always 0 events.
4. **`MT5CalendarProvider` real-symbol smoke test (test 12,
   informational)**: confirms `MTC_IsInBlackoutNow` runs without a
   runtime error against a real symbol/currency — the actual true/false
   result depends on whatever real economic events exist in the
   terminal's live calendar cache at the moment the script runs, which
   this test does not control (same precedent as
   `Test_RiskManager.mq5`'s real-symbol `OrderCalcProfit` section).

## Acceptance criteria

- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation.
- [x] Blackout-window before/after boundary arithmetic hand-verified.
- [x] `min_importance` filtering hand-verified.
- [x] Spread-extension active/inactive/expired-cap logic hand-verified.
- [x] `NullNewsProvider` never reports an event (hand-verified).
- [x] Not wired into `ThembaAdaptiveIntradayEA.mq5` or
      `MarketRegimeEngine.mqh` — verified by inspection (neither file is
      touched by this task).
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.
- [ ] Real-event runtime confirmation (an actual high-importance event
      correctly triggering `MTC_IsInBlackoutNow` against live data) —
      not yet performed, joins the batched manual-verification backlog;
      informational-only smoke test performed instead (see Test plan
      item 4).

## Rejection criteria

Rejected if any future inspection finds this module wired into
`ThembaAdaptiveIntradayEA.mq5` without that having been bundled with the
`UNTRADEABLE_SPREAD_OR_LIQUIDITY`/hysteresis fix as one coherent
follow-up task, or if the blackout-window boundary arithmetic is found
to disagree with section 10's stated before/after minute parameters.

## Implementation notes

`NM_IsInBlackoutWindowExtended`'s spread-normalization check reuses the
identical `current_spread > atr * max_spread_atr_multiple` comparison
`MarketRegimeEngine.mqh`'s already-reviewed
`MRE_IsUntradeableSpreadOrLiquidity` uses for
`UNTRADEABLE_SPREAD_OR_LIQUIDITY` — not re-derived, since section 10
and section 2 both reference the same `InpMaxSpreadATRMultiple` concept.

## Commands run

```
git checkout -b claude/task-029-news-manager
mkdir -p 03_SOURCE_CODE/MQL5/Include/ThembaEA/News
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_NewsManager.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 571 ms elapsed,
cpu='X64 Regular'` on the first attempt.

## Test results

**Compile test: PASS (real evidence, above).** Tests 1-11's arithmetic
is hand-traced in this file's Acceptance criteria and Test plan
sections. Test 12 (real MT5 Calendar smoke test) is informational only
per its own stated design — actual live-execution pass/fail counts from
a real terminal run are not yet captured in this session, joining the
batched runtime-verification backlog.

## Commit

Pending — see `git log` on `claude/task-029-news-manager`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean.** This closes the "no news-system module exists"
gap named by TASK-016/TASK-025's own out-of-scope statements. Not
wired into the live EA — that is deliberately bundled into a future
"regime gating" task alongside the pre-existing
`UNTRADEABLE_SPREAD_OR_LIQUIDITY`/hysteresis wiring gaps, so all three
land together coherently rather than partially. Remaining before the
news system is complete per its own spec: the CSV/SQLite
deterministic-backtest provider, the optional Fair Economy adapter, and
real-event runtime confirmation.
