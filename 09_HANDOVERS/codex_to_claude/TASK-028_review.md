# TASK-028 independent code review - round 7

**Disposition: CHANGES REQUESTED**

**Review target:** branch `claude/task-028-python-statistical-lab`, commit
`7bccd2099607ffea198ff934d6a12028bc19f1e9` (`7bccd20`). I reviewed the
complete 24-commit range after the round-6 review commit, `8cb83b0..7bccd20`
(80 changed paths; 10,433 insertions and 688 deletions), rather than only the
latest commit. I independently inspected the Python and MQL source, canonical
specification and policy documents, task/history records, Git path history,
and immutable baselines. I also re-ran the full Python gates and every
notebook with the repository's declared kernel.

The Python gate result is strong: 655 tests pass, lint/format/type checking are
clean, and all 11 notebooks execute. The new MQL and exporter integration is
not yet safe or internally joinable, however. I found **20 remaining findings:
10 P0, 9 P1, and 1 P2**. Several current task records say the corresponding
round-6 blockers are resolved, but the current source provides direct
counterexamples. TASK-028 is not ready to merge or close, and its live-trading
or real-evidence outputs must not yet be relied on.

## Findings

### 1. [P0] An accepted asynchronous order is neither durably tracked nor restart-idempotent

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh:205-220`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:630-695`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/AsyncFillCorrelator.mqh:5-45`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/IntentManager.mqh:70-88,122-138`;
`TASK-034_LIVE_SAFETY_WIRING.md:73-78`;
`TASK-002_PHASE2_SPECIFICATION.md:1213-1225`.

`OM_OpenPosition` treats `TRADE_RETCODE_PLACED` as success. The EA then clears
the persisted intent at lines 650-652 and only afterwards registers an
in-memory correlation at lines 688-695. `AsyncFillCorrelator.mqh` explicitly
describes that store as session-scoped. A process or terminal failure after
the broker accepts the request but before the fill callback therefore loses
both protections. On restart, `IM_ReconcileOnRestart` checks only the current
position list and clears the intent either way; it never reconciles active
broker orders or order/deal history. A still-live accepted order can later
fill while the restarted EA is free to submit another.

There is also a creation race in `IM_BeginIntent`: two instances can both see
the Global Variable as absent; instance A creates it and CASes it to 1; then
instance B's delayed unconditional `GlobalVariableSet(..., 0.0)` resets A's
lock and B's CAS also succeeds. The metadata fields are written only after the
CAS and are not one atomic record.

This is not a theoretical distinction. MetaQuotes documents that a successful
asynchronous send/`PLACED` result means the request was accepted for
processing, not that execution completed, and that trade-transaction arrival
order is not guaranteed: [OrderSendAsync](https://www.mql5.com/en/docs/trading/ordersendasync),
[OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction).
Keep the durable intent active through a terminal broker outcome, persist the
request/order correlation before exposure can appear, reconcile orders,
positions, and history after restart, and make lock creation/acquisition
atomic across instances.

### 2. [P0] The journal-to-history identity/event contract rejects every ordinary synchronous closed trade and the asynchronous follow-up is schema-invalid

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh:218-247`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:200-238,661-695`;
`03_SOURCE_CODE/MQL5/Scripts/Export_TradeHistory.mq5:79-105,120-175`;
`03_SOURCE_CODE/Python/analysis/join_signal_to_outcome.py:237-270,291-302,371-400`;
`03_SOURCE_CODE/Python/analysis/join_trade_journal.py:161-164,286-299`;
`03_SOURCE_CODE/Python/analysis/schema.py:77-100,142-147`;
`TRADE_DECISION_SCHEMA.json:2-9`.

The stable-key correction itself is directionally right: the journal now
intends `order_id` to mean `POSITION_IDENTIFIER`, while keeping the session
ticket separately. But the synchronous resolution scans every current
position and takes the first matching `(symbol, magic)` position. In a hedging
account with an older matching position or concurrent fills, that need not be
the newly opened position. The opening deal already provides the definitive
`DEAL_POSITION_ID`; the scan discards that causal relation.

The normal synchronous journal stores `trade.ResultDeal()`--the **opening**
deal ticket--as `decision.deal_id`. `Export_TradeHistory` emits only
`DEAL_ENTRY_OUT`/`OUT_BY` rows and calls each **closing** deal ticket `deal_id`.
The Python join requires the journal `deal_id` to occur among the exported
deal IDs. Thus an ordinary closed position has a guaranteed `deal_id`
conflict, even before partial fills are considered.

The asynchronous workaround is also not a valid decision record. It creates a
fresh default decision, reuses the original `signal_id`, sets direction to
`NONE`, changes the strategy to `AsyncFillCorrelation`, and leaves
`market_family`, `intraday_mode`, and `regime` empty. The Python schema rejects
the empty/unknown enum values; the journal join reports the reused signal ID as
a duplicate; and the outcome join rejects `NONE` against a Boolean `is_long`.
Meanwhile the original `PLACED` row has a null `order_id` and is deliberately
filtered as unsubmitted. This requires an explicit submission/update/fill
event schema with unique event IDs and separate request/order, stable position,
opening-deal, and closing-deal roles--not a second malformed trade decision.

MetaQuotes confirms that `POSITION_IDENTIFIER` is lifecycle-stable while
`POSITION_TICKET` can change, and that deals link through
`DEAL_POSITION_ID`: [position properties](https://www.mql5.com/en/docs/constants/tradingconstants/positionproperties),
[deal properties](https://www.mql5.com/en/docs/constants/tradingconstants/dealproperties).

### 3. [P0] The live order path does not implement the canonical hard-risk policy

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh:66-123`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:121-132,510-539,630-695`;
`TASK-002_PHASE2_SPECIFICATION.md:1001-1035,1046-1076,1122-1135,1435-1438`;
`RISK_POLICY.md` (`Per-trade risk limits`, `Portfolio risk`, `Hard-stop
behaviour`, and default-off add-on/basket requirements).

`risk_cap_percent` is checked only when the calculated volume is below the
broker minimum. For every ordinary-sized order, `risk_percent` can exceed the
cap and still be accepted. The EA inputs are not validated to require target
risk to be positive and no greater than the cap, despite the input comment
claiming the value enforces both per-trade and total-open risk.

The live gate checks only whether this symbol/magic already has a position. It
does not sum this EA's risk across all symbols, reserve pending-order risk, or
enforce the portfolio cap. It has no post-fill calculation based on actual
fill/actual SL and no mandatory breach closure/cancel/retry state. Finally,
the specification's hedging-only `OnInit` refusal is absent. The source thus
implements a sizing helper, not the required pre-trade and post-fill hard-risk
system. Add input-domain validation, own-magic portfolio aggregation including
pending reservations, the hedging-mode guard, and the persisted mandatory
post-fill breach response before enabling order submission.

### 4. [P0] The default MT5-calendar provider shifts event times, decodes numeric values incorrectly, and exports a non-unique occurrence key

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/News/MT5CalendarProvider.mqh:37-49,53-113,126-151`;
`03_SOURCE_CODE/MQL5/Scripts/Export_NewsCalendar.mq5:35-64`;
`03_SOURCE_CODE/Python/analysis/join_news_events.py:259-268`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:83-87,469-474`.

The provider names its bounds UTC, supplies `TimeGMT()`-derived bounds to
`CalendarValueHistory`, treats `MqlCalendarValue.time` as UTC, and adds the
server offset to obtain server time. MetaQuotes states the opposite: calendar
query bounds and calendar-value times are in **trade-server time**. The
blackout is therefore shifted, and `scheduled_server_time` is shifted a
second time. See [CalendarValueHistory](https://www.mql5.com/en/docs/calendar/calendarvaluehistory)
and [MqlCalendarValue](https://www.mql5.com/en/docs/constants/structures/mqlcalendar).

`MTC_DecodeValue` divides raw calendar values by `10^event.digits`.
MetaQuotes specifies that these fields are scaled by 1,000,000 (or should be
read through the structure's value helpers), independent of display digits.
The provider also exports recurring `event_id` as the row identity, although
the value structure has a unique occurrence `id` and a reusable definition
`event_id`. Recurrences can therefore collide, while the Python join correctly
rejects duplicate event IDs. These errors affect the provider selected by
default, so live blackout behavior and exported real news evidence are not
trustworthy until corrected and regression-tested with a non-UTC server,
nontrivial digits, and repeated event definitions.

### 5. [P0] News fail-safe behavior can silently turn malformed provider data into a clear trading window, and `NONE` bypasses mandatory macro controls

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/News/FairEconomyNewsProvider.mqh:213-265,276-300,315-339`;
`03_SOURCE_CODE/MQL5/Scripts/Test_FairEconomyNewsProvider.mq5:114-125`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:61-77,424-480`;
`NEWS_INTEGRATION_SPEC.md` (`Failure behaviour` and required metal/forex
macro-filter sections); `PROJECT_RULES.md` (do not silently fail open).

A transport-level HTTP 200 containing an empty body, HTML error page, invalid
JSON, or a changed schema parses to zero events. `FEP_FetchLive` returns that
zero as success and `FEP_EnsureCache` marks the empty result valid for the
refresh interval. The live wrapper then reports no blackout instead of
provider unavailable. The test explicitly blesses invalid JSON as a valid
zero-event result, so it protects the fail-open bug.

The public provider selector also includes `NEWS_PROVIDER_NONE`, and the EA
returns no blackout for it even on metal/forex symbols whose macro filter is
mandatory. A deliberately disabled or syntactically unusable feed must not be
indistinguishable from a verified empty event window. Validate response shape
and required fields, propagate parse/schema failure as provider-unavailable,
and either remove `NONE` for mandatory families or make it fail closed.

### 6. [P0] `IntradayModeRouter` does not implement the approved executable mode specification and its result does not route trading behavior

**Files:**
`TASK-002_PHASE2_SPECIFICATION.md:191-216,218-289`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/IntradayModeRouter.mqh:45-53,118-177`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:395-411,906-985`;
`TASK-040_INTRADAY_MODE_ROUTER.md:44-56,78-91`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:873-880`; `TASKS.md` (`TASK-028` row).

The canonical specification defines regime first, then mode, then strategy;
four normalized components with configurable weights; explicit missing-data
semantics; no mode if too little evidence exists; thresholds of `<= 0.40` and
`>= 0.60`; neutral-state carry behavior; and two-M1-bar hysteresis. The current
router instead uses hard-coded, unnormalized signed point additions, includes
spread, news, and the already-selected winning candidate score, uses a zero
threshold, always returns one of two modes, and has neither missing-data nor
hysteresis state.

The EA evaluates and resolves all strategies before calling the mode router,
so the candidate influences mode instead of mode constraining strategy. It
coerces an unknown session ratio to zero and uses current-bar range divided by
recent bars rather than the specified session-range/ATR component. The module
and TASK-040 openly state its output is journal-only and no strategy consumes
it. Those disclosures are honest, but they directly contradict the canonical
TASK-028/TASKS claim that round-6 P0-3 is resolved. Implement the approved
formula/order and make mode an upstream routing input, or explicitly keep the
finding open and give the missing behavior a numbered owner.

### 7. [P0] Low-confidence/data-failure regime behavior is not fail-closed, the transition log remains absent, and the new MQL gate test fails by inspection

**Files:**
`TASK-002_PHASE2_SPECIFICATION.md:354-357,399-417`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/MarketRegimeEngine.mqh:229-231,239-291`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:836-888,890-959`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Routing/StrategyRouter.mqh:122-142`;
`03_SOURCE_CODE/MQL5/Scripts/Test_RegimeGateComposer.mq5:89-104`;
`TASK-031_REGIME_VALIDATION_COMPLETION.md:95-128,190-201`.

The classifier calculates `low_confidence_override = confidence < 0.5`, but
the EA never consumes it. It sends the nominal regime through the gate and
router, using confidence only as a scoring input, so a low-confidence trend,
range, expansion, or compression classification can still trade. The approved
spec requires `TRANSITION_OR_UNCERTAIN` treatment for routing below 0.5.

On classifier or OHLC/ATR failure, the EA returns before creating the promised
journal row. The approved behavior is a journaled transition state with zero
confidence and immediate hysteresis bypass. The separately required live MQL
transition-history buffer is also still absent; TASK-031 explicitly records it
as unimplemented even while TASK-028 declares the broader P0 closed.

The claimed gate-composer verification is not credible as written. Its test
first bypass-confirms `UNTRADEABLE`, then feeds one clean `RANGING` sample with
`required_bars=2` and asserts the result is not `UNTRADEABLE`. The actual
`MRE_ApplyHysteresis` leaves the prior confirmed regime in force after the
first pending sample and returns it, so line 101 deterministically fails; only
the second sample confirms `RANGING`. Fix the expectation or state-machine
semantics and retain real execution output.

### 8. [P0] End-of-day closure and exit management can leave or reopen exposure after the intraday boundary

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:319-339,699-785`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/IntradayCloseManager.mqh:41-57,61-93,138-162`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/ExitOrchestrator.mqh:5-25`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/ExitManager.mqh:158-180`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh:269-286`.

`OnTick` returns for every tick except the first tick of a new bar. On that
bar it evaluates/open-submits first, manages positions second, and checks the
intraday boundary last. The advertised retry "on the next tick" is therefore
actually once per bar. Worse, after a successful close the in-memory daily
guard suppresses all later closes that day, but no entry gate blocks later
bars after the boundary. With a shorter configurable timeframe or a session
that continues after 23:45, the EA can open new same-day exposure which the
guard will not close.

Both the close manager and `OM_ClosePosition` accept `PLACED` as a completed
close. The manager can set its done flag and the position state can be cleared
before a closing deal exists. The exit orchestrator's header says per-tick,
but its only live caller runs once per completed bar, losing intrabar peak,
trail, time-stop, and giveback responsiveness. Finally, a session-calendar
lookup failure is coerced to remaining ratio 0; in day mode that is interpreted
as duration exceeded and can force an unintended close.

Move mandatory boundary protection ahead of entry, make it a persistent
post-boundary entry lock, retry until broker-confirmed terminal outcomes, and
run genuinely tick-sensitive exit state on ticks (or revise and validate an
explicit bar-close design).

### 9. [P0] `Export_TradeHistory` does not produce valid position outcomes for multi-fill, partial-close, reversal, cost, or initial-risk analysis

**Files:**
`03_SOURCE_CODE/MQL5/Scripts/Export_TradeHistory.mq5:79-105,120-175`;
`03_SOURCE_CODE/Python/analysis/analyse_baseline.py:514-522`;
`03_SOURCE_CODE/Python/analysis/join_signal_to_outcome.py:273-289,371-400`.

The exporter indexes all opening deals but retains only the first entry ticket
for each position; it neither sums volumes nor computes a volume-weighted
entry. It emits a row for each `OUT`/`OUT_BY` deal, so partial closes become
separate complete trades, and it ignores `INOUT` reversal semantics. The
reported net P/L sums only the closing deal's profit, swap, commission, and
fee; entry-side fees/commission and other fills are omitted.

Most seriously, `stop_price` is read from the closing deal's `DEAL_SL`.
MetaQuotes defines that on an exit deal as the stop associated with the
position when that deal closed; it is not an immutable original-risk stop.
After break-even/trailing, the Python baseline analysis consumes that value as
initial risk and computes a false R multiple. A correct bridge must normalize
the complete `DEAL_POSITION_ID` lifecycle, pair all entry/exit/reversal
volumes, allocate all costs, retain the original submitted/fill-time stop from
durable evidence, and emit one well-defined outcome grain.

### 10. [P0] Broker/server timestamps are repeatedly labeled UTC, corrupting cross-system joins and day/session attribution

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:207-218,1002-1016`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh:131-140,198-209`;
`03_SOURCE_CODE/MQL5/Scripts/Export_TradeHistory.mq5:57-69`;
`03_SOURCE_CODE/MQL5/Scripts/Export_PredictedRegime.mq5:61-66,148-160`;
`03_SOURCE_CODE/MQL5/Experts/EquityTickRecorder.mq5:37-42,75-87`.

The EA assigns `TimeCurrent()` to decisions. `DJ_FormatIso8601Utc` merely
formats that value and appends `Z`; it performs no server-to-UTC conversion.
The trade, regime, and equity exporters repeat the same formatter pattern for
broker/server timestamps. MetaQuotes documents `TimeCurrent()` as trade-server
time: [TimeCurrent](https://www.mql5.com/en/docs/dateandtime/timecurrent).

On a non-UTC broker these rows claim a false instant. Journal-to-trade joins,
news joins, bar alignment, server-day reset attribution, and equity timelines
can all shift by hours; daylight-saving changes make a single fixed offset
insufficient across history. Establish one explicit time contract, export the
raw server timestamp plus an actually converted UTC instant (and offset/time
zone evidence), and regression-test a non-UTC/DST boundary.

### 11. [P1] The pattern comparison/export path is schema-incompatible, and triple-top/bottom geometry does not implement the approved specification

**Files:**
`03_SOURCE_CODE/Python/analysis/pattern_validation.py:1236-1310,1336-1341,1364-1458`;
`03_SOURCE_CODE/MQL5/Scripts/Export_PatternDetectorResults.mq5:79-98`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/ChartPatternEngine.mqh:255-372`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/ChartPatternStrategy.mqh:190-205`;
`TASK-002_PHASE2_SPECIFICATION.md:798-831`.

`detect_all_patterns` still describes a four-column default, but actually
emits `k` plus sixteen Boolean pattern columns. The comparator derives its
required MQL columns from all Python output columns. The MQL exporter writes
only the original four pattern columns, so a direct comparison fails schema
validation for the other twelve. The public `run`/CLI path exposes neither
ATR values nor swing depth, so marubozu/tweezers/three-bar-reversal cannot be
persisted through the advertised pipeline; notebook 09 does not close that
gap. The export also contains only row index `k`, with no symbol, timestamp,
timeframe, or OHLC fingerprint proving the MQL and Python rows came from the
same segment.

The Python triple port agrees algebraically with the new MQL code, but both
implement the same divergence from the specification. Triple tops/bottoms
compare only adjacent extrema, allowing extrema 1 and 3 to violate the stated
common tolerance. They flatten the neckline with one min/max instead of using
the specified potentially sloped neckline at breakout time, which changes the
breakout, stop, height, and target. `ChartPatternStrategy` does not call either
triple detector, so this work is module-only rather than live strategy
coverage. Align both implementations to the approved geometry and make the
cross-language export complete and data-bound.

### 12. [P1] The predicted-regime exporter is not an export of the live nine-state classifier and leaks indicator handles

**Files:**
`03_SOURCE_CODE/MQL5/Scripts/Export_PredictedRegime.mq5:1-21,99-160`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/MarketRegimeEngine.mqh:103-231,239-400`;
`REGIME_LABELLING_PROTOCOL.md` (nine-state predicted/actual contract);
`TASK-037_MT5_EXPORT_BRIDGE.md:281-297`.

The script calls the raw, stateless `MRE_ClassifyArray` directly. It omits the
live spread/liquidity override, news override, hysteresis state, and
low-confidence transition override, so it cannot emit either gated state and
does not reproduce the EA path. On invalid inputs it skips the row rather than
emitting the specified zero-confidence transition/data-failure record.
Calling this side of the confusion matrix "predicted live regime" is therefore
incorrect.

It also creates a new `iATR` handle inside every exported-bar iteration and
never calls `IndicatorRelease`; a 500-bar export can leak hundreds of handles.
The export has no exact requested start/end data contract, iterates newest to
oldest, and repeats the false-UTC formatter. Build one historical replay of the
same composed live state machine with explicit chronological order and bounded
resource lifetime.

### 13. [P1] The equity recorder is not complete account-equity evidence and no required equity/cost consumer exists

**Files:**
`03_SOURCE_CODE/MQL5/Experts/EquityTickRecorder.mq5:17-32,37-59,75-88`;
`00_MASTER_PROMPT_FOR_CLAUDE.md:836-843,1193-1222`;
`TEST_PLAN.md:9-29`; `TASK-037_MT5_EXPORT_BRIDGE.md:147-168,181-207`;
`03_SOURCE_CODE/Python/analysis/compare_releases.py:390-570`.

The recorder calls itself account-level and symbol-agnostic, but samples only
when the attached chart symbol ticks. Account equity can change because of
another symbol while that chart is idle, so the stream is not a complete
account-equity event series. Second-resolution timestamps can repeat; the
shared append file lacks account, broker/server, symbol source, run ID, and
timezone identity; it does not flush each sample; and nonpositive
`InpSampleEveryNTicks` is not rejected.

More importantly, there is still no Python consumer calculating maximum
account-equity drawdown, daily-reset giveback, account-peak giveback, or the
required cost-sensitivity comparisons from this evidence. `compare_releases`
continues to disclose those surfaces as absent. The export is useful scaffolding,
but it does not resolve round-6 P0-2 or the master/test-plan deliverables.

### 14. [P1] Daily/weekly baselines and cooldown/position lifecycle bookkeeping can misstate safety state

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/DailyWeeklyLimits.mqh:26-105`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:250-292,813-823`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Core/StateManager.mqh:195-230`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/CooldownManager.mqh`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/PositionStateTracker.mqh`.

On first use, the daily/weekly baselines are set to **current** equity. The
cash-flow cursor also starts at zero, so the immediately following eight-day
history scan adds all recent balance deals to those already-current baselines.
Recent deposits/withdrawals are double-counted. The comment claims credit
handling, but the code accepts only `DEAL_TYPE_BALANCE`. The cursor and
baseline writes are not one account-wide atomic update, and an unsigned
64-bit ticket is persisted in a `double`, which cannot represent all ticket
values exactly. Although the helper says safe to call every tick, the EA calls
it only once per new bar. The schema migration routine exists, but the EA never
calls `SM_EnsureAccountSchema`.

On closing deals, cooldown P/L omits `DEAL_FEE` and all entry-side costs. Every
`OUT` is treated as a whole losing/winning trade, and its position state is
cleared without checking whether a partial remainder still exists. Reversal
`INOUT` is ignored. MetaQuotes also defines `DONE_PARTIAL` as a real partial
completion, yet the open/close helpers accept only `DONE`/`PLACED` and do not
model the remaining volume. Rebase history from a cursor consistent with the
baseline instant and make position-lifecycle/cost accounting volume-aware.

### 15. [P1] Several Python public boundaries still accept invalid domain values or derive phantom state

**Files:**
`03_SOURCE_CODE/Python/analysis/regime_validation.py:103-190,237-266,293-324`;
`03_SOURCE_CODE/Python/analysis/join_signal_to_outcome.py:237-270`;
`03_SOURCE_CODE/Python/analysis/parameter_stability.py:178-220`;
`03_SOURCE_CODE/Python/analysis/trade_math.py:19-55`.

Independent adversarial probes found the following remaining boundary errors:

- `classify_regime` accepts non-finite inputs: `current_atr=NaN` can produce a
  valid `TRENDING_UP` result. A zero trend-slope divisor raises raw
  `ZeroDivisionError` instead of a domain error.
- `apply_hysteresis(required_bars=0)` is accepted even though confirmation-bar
  count must be positive.
- `RegimeTransitionHistory.record_confirmed` tells callers to record each
  hysteresis return. The initial unconfirmed `TRANSITION_OR_UNCERTAIN`
  sentinel is stored as a confirmed state, so the first actual confirmation
  creates a phantom transition from that sentinel.
- `_direction_matches_is_long` strictly parses strings but applies `bool()` to
  every other object; numeric `2` is silently accepted as long.
- `parameter_stability` does not preserve `path_id` as text on CSV read, so
  identifiers such as `001` and `1` collapse.
- `compute_r_multiple` checks only the final result. With finite inputs whose
  subtraction overflows (`entry=1e308`, `stop=-1e308`, `price=0`), risk
  distance becomes infinity and the function returns `-0.0` instead of the
  mathematically correct `-0.5` or rejecting the overflowed intermediate.

Validate finite/domain invariants at each public boundary and add the exact
counterexamples as regression tests.

### 16. [P1] Provenance and resource ceilings are still non-atomic or collision-prone

**Files:**
`03_SOURCE_CODE/Python/analysis/performance_breakdown.py:413-502` and analogous
`run` functions; `03_SOURCE_CODE/Python/data_collection/journal_reader.py:289-356,483-489,537-567`;
`03_SOURCE_CODE/Python/analysis/csv_io.py:86-97`;
`03_SOURCE_CODE/Python/analysis/analyse_giveback.py:396-400`;
`03_SOURCE_CODE/Python/analysis/calculate_mfe_mae.py:248-252`;
`03_SOURCE_CODE/Python/analysis/join_signal_to_outcome.py:535-539`.

Representative pipelines write the result CSV before capturing Git metadata
and writing its mandatory sidecar. A direct call with an invalid `repo_path`
raises `GitMetadataError` after leaving an apparently valid result without its
sidecar. Result plus provenance is not an atomic publication contract.

The journal hash is updated only for bytes in successfully decoded lines. Two
files whose first bad byte is identical but whose unread suffixes differ can
receive the same dataset hash. Error retention is capped only after a whole
file is consumed, so one file can retain up to the much larger record ceiling
before `max_retained_errors` takes effect. Candidate paths are fully
materialized and sorted before `max_files` limits them. `csv_io` checks file
size before `read_bytes()` but does not check the actual buffer length, so a
concurrently growing file can exceed the ceiling.

Finally, several combined-input hashes use basenames rather than role-qualified
paths/content ordering. Same-named inputs in different directories can swap
roles while producing the same combined hash and portable-name list. Hash all
raw bytes including invalid tails, stream within limits, recheck actual bytes,
qualify each input by semantic role, and publish result+sidecar transactionally.

### 17. [P1] Research comparison/state conventions remain permissive or unauthenticated despite canonical “resolved” language

**Files:**
`03_SOURCE_CODE/Python/analysis/schema.py:80-100`;
`03_SOURCE_CODE/Python/analysis/performance_breakdown.py:87-98,133-156,205-273`;
`03_SOURCE_CODE/Python/analysis/parameter_stability.py:64-74`;
`03_SOURCE_CODE/Python/analysis/compare_releases.py:390-396,471-539`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:987-1016`.

The live producer now defines `news_state` as exactly `CLEAR` or `BLACKOUT`,
but the schema accepts any string and `performance_breakdown` intentionally
normalizes/groups other values. A direct `BANANA` probe is accepted even
though the comment now identifies the two-value producer contract.

Parameter stability still documents three incompatible `bar0` conventions
(pre-bar 0R, entry-bar close, and notebook `+0.5R`) rather than normalizing one
definition. Release comparison also calls `set_file`, `data_period`, and cost
inputs caller-provided labels, verifies only that sample timestamps are
contained in the claimed interval, and then reports the full claimed duration
as authenticated. A one-hour sample can therefore be labeled a full year.
These fields must either be derived from evidence or clearly reported as
unauthenticated declarations; current acceptance/history language overstates
the contract.

### 18. [P1] The live decision journal remains operationally unsafe and inconsistent with its Python schema

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/IntradayModeRouter.mqh:59-75`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:207-238,836-866,987-1016`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh:198-245`;
`03_SOURCE_CODE/Python/analysis/schema.py:77-100`;
`TRADE_DECISION_SCHEMA.json:2-20`.

The Python/JSON schema accepts market families only `METAL|SYNTHETIC`; the live
router emits `METAL`, `FOREX`, `SYNTHETIC_INDEX`, or `UNKNOWN`. Three of four
live values are invalid, including the intended synthetic-index value. The
`signal_id` is symbol + broker second + process-local counter, so concurrent
instances or restarts within the same second can collide. `ea_version` is a
hard-coded stale task-027 string and `git_commit` is never populated.

All instances append to one daily file with `FILE_SHARE_READ` but no write
sharing or interprocess append lock. Concurrent EAs can fail to open or race at
end-of-file; the caller logs a terminal message but the evidence stream has a
hole. Classifier and data-read failures at lines 836-866 return before a
decision exists, despite the every-bar journal claim. Correct the vocabulary,
use an instance/run-aware unique event key, populate real build provenance,
serialize cross-instance appends, and emit explicit failure decisions.

### 19. [P1] MQL verification claims are not reproducible, and at least one claimed test is contradicted by its implementation

**Files:**
`03_SOURCE_CODE/MQL5/Scripts/Test_RegimeGateComposer.mq5:89-104`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/MarketRegimeEngine.mqh:263-291`;
the `Verification`, `Acceptance criteria`, and compile-evidence sections of
`TASK-034_LIVE_SAFETY_WIRING.md`, `TASK-036_JOURNAL_PRODUCER_COMPLETION.md`,
`TASK-037_MT5_EXPORT_BRIDGE.md`, `TASK-039_CHART_PATTERN_COMPLETION.md`,
`TASK-040_INTRADAY_MODE_ROUTER.md`, and `TASK-041_EXIT_ENGINE_WIRING.md`;
`00_MASTER_PROMPT_FOR_CLAUDE.md` (compiler-output retention requirement).

The gate-composer counterexample in finding 7 proves one script's advertised
hand verification cannot pass with the current state-machine code. Several
task records claim real MetaEditor 0-error/0-warning evidence, but the reviewed
tree retains neither compiler logs nor build artifacts tied to this commit.
MetaEditor was not available on this review environment's PATH, so I could not
independently compile the MQL sources. Absence of an artifact does not prove a
compile never occurred; it does make the claim non-reproducible and leaves the
new 10k-line integration dependent on inspection alone. Retain complete
compiler output per the master prompt and actual script runtime summaries;
compilation alone must not be described as executing logic tests.

### 20. [P2] Canonical task/history/ownership records contradict current source and Git reality

**Files/sections:** `TASK-028_PYTHON_STATISTICAL_LAB.md:843-894`;
`TASKS.md` (`TASK-028`, `TASK-031`, `TASK-033`, `TASK-036`, `TASK-037`,
`TASK-039`, `TASK-040`, and `TASK-041` rows);
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:186-200`;
`TASK-037_MT5_EXPORT_BRIDGE.md:281-297`;
`TASK-039_CHART_PATTERN_COMPLETION.md:141-164,189-192`;
`09_HANDOVERS/claude_to_codex/TASK-028_handover.md:505-528`;
stale producer-status comments in `03_SOURCE_CODE/Python/analysis/schema.py`,
Python test/notebook headers, `ChartPatternEngine.mqh`, and
`pattern_validation.py`.

The canonical files say round-6 P0-1/P0-3 are resolved and that every resolved
finding has a reproducing regression test, although findings 1, 2, 6, and 7
show the identity/mode/regime contracts remain open and P0-2 is still blocked.
TASK-036's Files-affected list does not match commit `712d4c6`: it omits
`AsyncFillCorrelator.mqh`, three routing modules, and four MQL tests, while
listing `schema.py`, which that commit did not change. TASK-037 still says the
Python pattern side is not started and that only four detectors exist.

TASK-039's count is internally inconsistent. The master set is 17 families;
six are built when the two triples are included, leaving eleven total. The
document describes eleven remaining **plus** cup-and-handle and leaves the
future owner unnamed, recreating the ownership gap. The current handover ends
at 602 tests and three unresolved P0s, omits the entire post-`349fddb` sprint,
and tells the reader not to request review even though this review is now in
progress. Update canonical status from actual Git paths and current source,
separate implemented/tested/reviewed states, correct the pattern inventory,
and register every deferred deliverable under a concrete numbered task.

## Corrections independently confirmed

The current range does contain substantial, correct remediation. In
particular, I confirmed:

- The MQL identity structure now separates stable `POSITION_IDENTIFIER` from
  session `POSITION_TICKET`, and exposes `ResultOrder()` and `ResultDeal()`.
- Decision-journal text is now explicitly written as UTF-8 rather than the
  Windows ANSI code page.
- Spread/liquidity and news overrides are composed before strategy evaluation,
  and recognized synthetic symbols bypass macro-news lookup.
- The round-6 Python fixes are present: strict string direction parsing,
  journal-deal membership checking, post-aggregation finiteness checks, inline
  input hashing where adopted, centralized text dtype for named trade-ID
  consumers, nonblank comparison labels, resampling-setting propagation, the
  two-dimensional V6.37 stability sweep, the renamed balance-step streak plus
  uncertainty output, cadence persistence, and the corrected notebook-10
  probability calculation.
- The new Python triple-top/triple-bottom functions match their MQL port. The
  remaining concern is that both share the same divergence from the approved
  geometry, not that the port mistranscribed the MQL implementation.

These are meaningful improvements; they do not remove the blockers above.

## Independent verification performed

- `pytest`: **655 passed**, 8 expected NumPy overflow/invalid warnings,
  29.44 seconds.
- `ruff check`: all checks passed.
- `ruff format --check`: all 59 Python files formatted.
- `mypy`: success across 24 source files.
- Notebooks `00` through `10`: all 11 executed successfully using the declared
  `themba-python-lab` kernel. A first attempt with the machine's unrelated
  default `python3` kernel lacked NumPy and is not counted as a product failure.
- `git diff --check 8cb83b0..7bccd20`: clean.
- Repository secret-pattern scan: no matches.
- MQL compile/runtime: not independently reproducible in this environment;
  MetaEditor was unavailable and no commit-bound compiler/runtime logs were
  retained. Static inspection found the deterministic gate-test failure above.

## Immutable baseline integrity

Both immutable evidence directories remain byte/tree-identical to their tags,
including `IDENTITY.md`:

- `01_BASELINE/EA_V637` matches `baseline-v637`; both resolve to tree
  `fe46191174b150c4c1e0dceb1bffc6c42a076384`.
- `01_BASELINE/EA_V811` matches `baseline-v811`; both resolve to tree
  `3bc9e68939873de57c70319ff75f3b39ffd58c75`.

No file under `01_BASELINE/` was modified during this review.

## Required disposition

**CHANGES REQUESTED.** Do not merge/close TASK-028, enable this EA for real
order submission, or use its MT5 exports as real statistical evidence yet.
The minimum safe path is to close P0 findings 1-10 first, add regression tests
that exercise their exact asynchronous/non-UTC/multi-fill/low-confidence/
post-boundary counterexamples, retain reproducible MQL compile and runtime
evidence, and then correct the remaining P1/P2 contracts before requesting the
next independent review.
