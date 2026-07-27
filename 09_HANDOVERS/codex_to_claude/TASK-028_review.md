# TASK-028 independent code review - round 9

**Disposition: CHANGES REQUESTED**

**Review target:** branch `claude/task-028-python-statistical-lab`, commit
`79da9c9302bfeecef84303a4b65cb2930b46f87e` (`79da9c9`). I reviewed the
complete remediation range after the round-8 target,
`7252987c185e0654444948b1378c78e10d1ed3f3..79da9c9` (24 commits, 84 changed
paths, 7,941 insertions and 1,378 deletions), not only the handover or tip
commit. I independently inspected the current MQL5 and Python source, the
canonical Phase-2/risk contracts, Git history and diffs, retained compile
evidence, tests, notebooks, and both immutable baseline tags.

The remediation contains substantial real work, and all declared Python
quality gates are clean. It nevertheless does **not** support the handover's
claim that all 22 round-8 findings are resolved. Several safety-critical
findings remain only partly implemented; the source and handover explicitly
admit that portions of findings 11, 12, 14, and 19 were deferred while the
canonical history simultaneously calls all 22 resolved.

I found **23 remaining findings: 7 P0, 14 P1, and 2 P2**. The EA is **not ready
to merge, not ready for a demo-account trial with order submission enabled,
and not ready for live use** at this commit. Journal-only observation with
`InpEnableOrderSubmission=false` does not validate the unresolved execution
and capital-safety paths.

## Findings

### 1. [P0] The 1% hard-risk cap remains fail-open, raceable, and unenforced after an actual fill

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:610-648,1198-1273,1519-1531,1551-1576,1632-1648`;
`TASK-002_PHASE2_SPECIFICATION.md:1024-1035,1062-1076,1122-1136`;
`RISK_POLICY.md:5-11`.

`ComputeOwnMagicOpenRiskCash()` returns only a `double`, so its caller cannot
distinguish zero exposure from exposure whose risk could not be read. It
silently skips a position/order when a symbol profile cannot load (EA
1213-1215, 1264-1266), ATR is unavailable for a stopless position
(1221-1225), a pending order is stopless (1249-1251), the SL is on a
non-loss side, or `RM_Compute*RiskCash` fails. Those paths contribute zero to
the purported hard cap.

The aggregate check at 1519-1531 is a non-atomic snapshot. Intent acquisition
does not begin until 1551, and there is no account/magic-wide reservation or
lock around check plus submission. Two symbol instances sharing the magic can
both observe the same headroom and submit, exceeding 1% together.

`OnTradeTransaction()` checks only daily/weekly equity limits. It never
recomputes own-magic risk from the actual fill price and volume and never
forces closure for a post-fill per-trade/aggregate 1% breach. The journal
calculation at 1632-1648 merely scales the pre-fill estimate by the filled
volume ratio; it omits adverse entry slippage from
`abs(actual_fill - stop) * actual_volume * tick_value / tick_size`. A
`HistoryDealSelect` failure at 615-616 bypasses even the daily/weekly check.

**Required correction:** return an explicit validity result from every risk
scan; treat any unreadable component fail-closed; reserve proposed risk under
an account/magic-wide critical section before submission; and recompute actual
per-trade and total risk inside the fill handler, with persisted mandatory
closure/cancellation on breach.

**Round-8 finding 3 status:** only partially resolved. Pending-order summation,
the 10-ATR fallback, the grace manager, and the 0.25% shipped target are real
improvements; the original concurrency, unreadable-state, and actual-fill
defects remain.

### 2. [P0] Risk persistence is still neither transactional nor reliably fail-closed

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Core/StateManager.mqh:77-96,117-164,197-247`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/DailyWeeklyLimits.mqh:58-84,135-182`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/EquityPeakManager.mqh:42-79,127-147`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:918-929,1463-1470,1966-1969`;
`TASK-002_PHASE2_SPECIFICATION.md:1090-1120,1194-1211`.

`SM_EnsureAccountLockInitialized()` still performs check-then-set; its own
comment concedes this is not airtight. The lock has no owner token, and its
boolean and `__since` timestamp are separate writes. One owner can release the
boolean, a second owner can acquire/stamp, and the first owner can then clear
the second owner's timestamp. The stale-lock breaker likewise writes zero
without proving ownership, and `SM_StampAccountLockHeld()` cannot report a
failed timestamp write.

`SM_SetAccountDoublesBatch()` is not a transaction. It continues writing after
an early field fails. Consequently, a baseline write can fail while the final
freshness timestamp/cursor succeeds; the current caller sees `false`, but the
next call trusts the fresh marker and does not retry the missing field. The
comment's claimed idempotent recovery is also false for the actual data:

- retrying a daily/weekly baseline after a crash can capture later equity and
  hide intervening P/L;
- retrying cash-flow rebasing after the baseline changed but before the cursor
  changed can apply the same cash flow twice;
- retrying the daily-peak baseline can replace boundary equity with later
  equity.

Peak update return values are intentionally ignored at EA 918-929. When the
account peak is absent, `EPM_GetCurrentDrawdownPercent()` returns 0%, which
produces the least restrictive downstream multiplier instead of treating peak
state as unknown.

**Required correction:** use a versioned single-record prepare/commit protocol
or an atomic file replacement for related fields; use an owner-token lock with
owner-checked release/recovery; stop a batch at its first failed write; and
propagate peak/baseline validity so unknown state blocks entries and cannot
increase risk.

**Round-8 finding 4 status:** partially resolved. Per-tick peak calls,
raise-if-greater locking, checked setters, and the pre-entry daily/weekly
validity gate are improvements, but the persisted-record protocol remains
unsafe.

### 3. [P0] Durable intent can still race, correlate the wrong order, or clear after an inconclusive lookup

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/IntentManager.mqh:85-112,115-221,228-277,299-328,368-418`;
`TASK-002_PHASE2_SPECIFICATION.md:1213-1225`.

The first-creation path at 107-112 remains check-then-unconditional-set. Two
concurrent `OnInit` calls can reset an already active intent; the comments only
assume that two same-symbol/magic initializations will not race.

The identifier is derived solely from `GetMicrosecondCount()`, which restarts
with the terminal and can repeat across sessions. More importantly, live
position and pending-order reconciliation does not use the ID at all: it
matches only symbol plus magic at 228-241 and 262-277. An unrelated position or
order with the same magic can resolve the intent incorrectly.

History reconciliation searches orders, not the required closed order **and
deal** history. `HistorySelect` failure is indistinguishable from a successful
search with no match; once the timeout is reached, 394-411 clears the intent
anyway. That converts a temporary history failure into permission for a
duplicate submission. An order that partially filled and later cancelled is
also misclassified because `was_filled_out` is true only for final state
`ORDER_STATE_FILLED`. `IM_ClearIntent()` neither reports write success nor
flushes the safety-critical clear.

**Required correction:** create one globally unique ID, persist one coherent
intent record, match that exact ID in live orders/positions and order/deal
history, distinguish lookup failure from verified absence, model partial
terminal outcomes, and verify/flush every state transition.

**Round-8 finding 5 status:** partially resolved. A broker-visible comment ID,
bounded history query, timeout, and pending-correlator reconstruction were
added, but the protocol is not restart-idempotent yet.

### 4. [P0] Partial and asynchronous fills still have unsafe terminal-state handling

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh:239-332`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:768-800,1584-1614`.

`DONE_PARTIAL` is now accepted, but `OM_OpenPosition()` returns `false` after a
real fill if deal-history selection or live-position resolution fails
(OrderManager 298-332). The caller then clears the intent and journals a
rejection at EA 1586-1592 even though exposure exists.

For a resolved synchronous partial fill, the EA clears intent immediately at
1594-1597 without checking whether an order remainder remains live. For an
asynchronous order, the first `DEAL_ENTRY_IN` removes the correlator and clears
intent at 768-783, again without testing remaining order volume/state; later
remainder fills are uncorrelated. The history branch treats every final state
other than `FILLED` as “never filled,” including partially-filled-then-cancelled
orders. Entry-time mode is persisted only on the synchronous path, so an async
fill has no corresponding position mode state.

**Required correction:** drive opening exposure through a durable order-state
machine that retains intent/correlation until the order is terminal and all
filled volume is accounted for. Once the broker has filled any volume,
resolution uncertainty must never be returned as ordinary rejection.

**Round-8 finding 8 status:** partially resolved. The immediate
`DONE_PARTIAL == rejection` bug is fixed; partial/remainder lifecycle and
actual-fill risk are not.

### 5. [P0] FairEconomy still converts partial or missing schema into a verified safe calendar

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/News/FairEconomyNewsProvider.mqh:118-128,219-265,298-320,343-384`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/News/MT5CalendarProvider.mqh:95-169`;
`03_SOURCE_CODE/MQL5/Scripts/Test_FairEconomyNewsProvider.mq5:145-177`.

An object is counted as usable if `date` parses. `title`, `country`, and
`impact` may be missing, and missing/unrecognized impact maps to 0. The live
wrapper rejects only when **all** raw objects fail parsing. Therefore a payload
containing one benign parseable object plus one malformed high-impact object is
accepted and cached while silently omitting the event that should block
trading. Even `[{"date":"2026-07-27T12:00:00Z"}]` becomes
one “valid” zero-impact event with no identity/currency.

The new tests cover bracketed garbage and wholly unparseable arrays, not
partial failure or required-field absence. The MT5 provider's any-lookup-fails
behavior is now correctly fail-closed.

**Required correction:** validate the complete response and every object's
safety-required schema before caching any result. Reject the whole fetch if
any event is malformed, required identity/currency/impact is missing, or impact
is outside the known vocabulary.

**Round-8 finding 7 status:** MT5 is resolved; FairEconomy remains partial.

### 6. [P0] Mandatory-close and no-stop obligations can silently stop retrying

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/IntradayCloseManager.mqh:74-134,244-306`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/CloseInFlightTracker.mqh:29-66`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/DailyWeeklyBreachManager.mqh:59-107`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/NoStopGraceManager.mqh:37-48`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:419-437,716-745,821-874,1288-1328`;
`RISK_POLICY.md:20`.

- `ICM_ReconcileIntradayClose()` ignores a failed
  `ICM_SetPendingCloseDate()`. It then sees no pending record and returns
  success without attempting closure.
- The obligation is created only after the boundary is observed. If the
  terminal is offline before 23:45 and restarts after midnight, no prior-day
  record exists and today's `SN_IsPastIntradayBoundary()` is false; the missed
  close cannot be reconstructed.
- `EventSetTimer(30)` is unchecked. Timer-registration failure silently removes
  the advertised no-tick guarantee.
- `DWB_AttemptClosure()` proceeds after failing to persist
  `closure_pending=true`, but an incomplete attempt is then not retried on the
  next tick because the flag remains false.
- `EnforceNoStopGracePeriod()` ignores `NSG_SetFirstSeen()` failure. Repeated
  write failure makes every tick look like the first observation, so the
  five-second close never becomes due. This path is tick-only, not timer-driven.
- A `PLACED` close is recorded only in memory. The in-flight mark has no timeout
  or terminal-rejection/cancellation handler and is cleared only after a close
  deal when the position already appears gone. A rejected/cancelled close with
  no exit deal wedges resubmission until restart.

**Required correction:** treat every state/timer write as part of the safety
decision; retain/retry an obligation even when persistence fails; reconstruct
missed boundaries from owned exposure; and correlate close requests through
all terminal outcomes with timeout/reconciliation. The no-stop deadline must
be wall-clock-driven.

**Round-8 findings 10 and 13 status:** partially resolved. Timer, durable due
flags, partial-close accumulation, and in-flight throttling exist, but their
failure paths do not guarantee closure.

### 7. [P0] `OnInit` permits settings that defeat hard limits or make manual exposure EA-owned

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:109,176-191,240-281`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/BrokerValidator.mqh:5-13,33-104`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/RiskManager.mqh:142-152`;
`TASK-002_PHASE2_SPECIFICATION.md:983-1004,1138-1147`;
`RISK_POLICY.md:5-20`.

Validation checks positivity and `target <= cap`, but does not constrain
`InpRiskCapPercent <= 1`, `InpDailyLossCapPercent <= 2`, or
`InpWeeklyLossCapPercent <= 4`. An operator can therefore configure the fields
labelled “hard” above policy. `InpMagicNumber` is not required to be nonzero;
zero makes manual orders/positions match ownership scans and exposes them to
bulk closure.

The required `InpStopFloorAtrMultiple < InpStopCapAtrMultiple` relationship is
not checked. With the floor above the cap, the validator can widen a stop to
the floor after the original distance passed its cap test. `BrokerValidator`
claims filling-mode and margin validation, but stops after freeze level; there
is no `OrderCalcMargin` or `SetTypeFillingBySymbol` call anywhere in the MQL5
tree.

**Required correction:** enforce the policy maxima and all numeric domains at
initialization, require a positive reserved magic, enforce floor below cap,
and implement the promised filling-mode/margin validation before the EA can
enable submission.

### 8. [P1] Cash-flow deals can cause false daily/weekly breaches before rebasing

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:613-648,1966-1969`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/DailyWeeklyLimits.mqh:89-182`;
`TASK-002_PHASE2_SPECIFICATION.md:1090-1112`.

Every deal triggers the equity-cap check immediately, but balance/credit cash
flows are rebased only later on the completed-bar decision path. With a 10,000
baseline, a 300 withdrawal can transiently appear as a -3% trading loss and
force-close exposure; after the required rebase, the baseline is 9,700 and the
trading-period change is 0%.

Classify and apply a balance/credit deal's rebase before evaluating the caps
inside the same transaction handler, with the persisted cursor updated as one
recoverable operation.

### 9. [P1] Asynchronous fills remain absent from machine-readable journal evidence

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:455-478,768-800,1698-1717`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh:298-307`.

`LogAsyncFillResolution()` only calls `Print`. The original `PLACED` decision
keeps null causal IDs and a proposed entry, and no schema-correct fill/cancel
event or update is appended. The comments at EA 1704-1715 now accurately admit
this, so the handover cannot simultaneously call the whole round-8 journaling
finding resolved. A crash after broker acceptance and before the original
journal append also still leaves exposure with no journal row.

Introduce an append-only execution-event record keyed by signal/intent/order,
or a crash-safe update model. Synchronous fill identity/actual entry and
checked character counts are genuine improvements.

### 10. [P1] The approved mode-first routing architecture remains deliberately unimplemented

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:2070-2126,2134-2167,2213-2245`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/IntradayModeRouter.mqh:10-33`;
`TASK-002_PHASE2_SPECIFICATION.md:186-297,420-550`.

All five strategies are generated and conflict-resolved before the mode is
computed. Mode can only veto the already-selected winner afterward. The source
itself states that the required regime -> mode -> mode-aware strategy
generation pipeline, family/mode timeframe matrix, two closed-M1-bar
hysteresis, scalp-attempt/unchanged-level counters, and bounded configurable
weights were not attempted. All strategies still share the M15 decision
window, and `IMR_DefaultModeWeights()` is hard-coded.

The `NONE`/`UNKNOWN` vocabulary correction is real. It does not resolve the
substantive routing half of round-8 finding 12. Implement the approved ordering
or keep a numbered task open and stop presenting TASK-028/the EA as launch
ready.

### 11. [P1] Chart-pattern execution still has no required lifecycle registry

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/ChartPatternEngine.mqh:343,437,530,623`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/ChartPatternStrategy.mqh:182-206`;
`TASK-002_PHASE2_SPECIFICATION.md:829-906`.

Sloped boundaries are now projected to the current logical index, and
same-bar breakout/retest is rejected. However, the live strategy expressly
admits at 193-199 that it has no persisted
`FORMING/CONFIRMED/RETESTING/TRADED/INVALIDATED/EXPIRED` registry. Retest is
only current-price proximity; the live strategy does not call the engine's
hold/fail retest helper. There is no invalidation, expiry, or consumed-pattern
suppression, so rediscovered geometry can trade repeatedly.

The projection portion of round-8 finding 14 is resolved; its lifecycle
portion is not. Implement the state graph and durable pattern identity before
claiming the finding closed.

### 12. [P1] CSV-plus-JSON publication is not atomic and can destroy a previous valid report

**Files:**
`03_SOURCE_CODE/Python/analysis/report_metadata.py:211-274`;
`03_SOURCE_CODE/Python/analysis/join_trade_journal.py:224-264`;
`03_SOURCE_CODE/Python/analysis/join_news_events.py:402-437`.

`publish_dataframe_csv_and_json()` replaces the final CSV first and then the
JSON. If JSON publication fails, it unlinks the CSV. A process crash between
renames can still expose a new CSV with old/missing provenance, and a normal
second-write exception destroys a pre-existing valid CSV while leaving its old
JSON.

A focused probe starting with `old-csv`/`old-json` and injecting JSON-write
failure produced:

```text
csv_exists=False, json='old-json'
```

The same remove-on-failure pattern is duplicated in the three-output
journal/news publishers. Tests cover initially absent targets, not replacement
rollback or crash windows. Publish into a versioned directory and atomically
switch one manifest/pointer, or implement a recoverable transaction that
preserves the prior complete generation.

### 13. [P1] `max_retained_errors` is bypassed for excluded and non-file candidates

**File:**
`03_SOURCE_CODE/Python/data_collection/journal_reader.py:546-593,608-663`.

An outward-resolving path or matching non-file appends a `ParseError` and
immediately `continue`s before either budget check. Two matching directories
with `max_retained_errors=1` returned two retained errors instead of raising:

```text
retained_errors=2
```

The round-8 change correctly bounds parse errors inside regular files and
validation errors. Apply the same immediate check after **every** error append,
including exclusion paths, and test mixed error sources.

### 14. [P1] The Python/MQL pattern comparator still accepts different and non-finite datasets

**Files:**
`03_SOURCE_CODE/Python/analysis/pattern_validation.py:1386-1501`;
`03_SOURCE_CODE/MQL5/Scripts/Export_PatternDetectorResults.mq5:127-132`.

The MQL exporter always identifies each bar with
`symbol,timestamp,open,high,low,close,atr`. Python requires only OHLC because
the caller chooses `identity_columns`; symbol, time, and ATR can therefore be
omitted from validation. Matching OHLC/booleans with an MQL row containing the
wrong symbol, a 1999 timestamp, and `atr=999` returned zero disagreements.

Numeric identity is not required to be finite. For a Python `close=NaN`
against finite MQL close, `abs(NaN - value) > tolerance` is false, also
returning zero disagreements. `price_tolerance` itself accepts negative or
non-finite input.

Require the complete exporter identity on both sides, exact symbol/timestamp,
finite OHLC/ATR, and a finite nonnegative tolerance before comparing flags.

### 15. [P1] Pattern documentation/evidence is source-stale and still has no real MQL-export comparison

**Files/sections:**
`03_SOURCE_CODE/Python/analysis/pattern_validation.py:41-48`;
`03_SOURCE_CODE/MQL5/Scripts/Export_PatternDetectorResults.mq5:127-132`;
`03_SOURCE_CODE/Python/notebooks/09_pattern_detector_validation.ipynb` comparison cells;
`TASK-028_PYTHON_STATISTICAL_LAB.md:168-180`.

The module says the exporter is intentionally limited to the original four
candlestick patterns. Current source exports all 20 predicates. Notebook 09
then compares Python against a synthetic CSV built from Python's own results,
not an independently executed MQL export. That can test join plumbing but
cannot satisfy test-plan item 7's required Python-versus-exported-MQL fixture
comparison.

Correct the source description, retain a real exporter output with dataset and
build provenance, and run the comparator against it. If real MT5 evidence is
not yet available, mark this acceptance item pending rather than treating the
synthetic self-copy as cross-language validation.

### 16. [P1] Equity analysis accepts blank identity and resets “daily” giveback on the wrong clock

**Files:**
`03_SOURCE_CODE/Python/analysis/equity_curve_metrics.py:100-149,152-210,221-240`;
`03_SOURCE_CODE/MQL5/Experts/EquityTickRecorder.mq5:10,29-37,96-110,145-149`;
`TASK-002_PHASE2_SPECIFICATION.md:1101-1112`.

The reader only rejects more than one distinct
`(run_id,account_login,broker_server)` tuple. It accepts an entirely blank
file as one `(NaN,NaN,NaN)` identity and computes a curve. A focused two-row
probe with all three fields empty was accepted.

The “daily” metric groups UTC dates. The live risk contract resets at trade-
server midnight, explicitly not UTC. A broker-server offset can split one live
risk day into two Python days or merge pieces of adjacent server days, so the
offline metric does not reproduce the engine it is meant to validate.

Read identity fields as strings and require exactly one fully nonblank tuple.
Record server time/offset (or a server-day key) in the recorder and group on
the canonical server boundary.

### 17. [P1] Journal schema still admits blank and out-of-domain provenance/state

**Files:**
`03_SOURCE_CODE/Python/analysis/schema.py:75-142`;
`TRADE_DECISION_SCHEMA.json:1-27`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/MarketRegimeEngine.mqh:35-46`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:1905-1914,2181-2203`.

`Field(min_length=1)` is paired with `str_strip_whitespace=False`. Focused
validation accepted whitespace-only values for `signal_id`, `symbol`,
`strategy`, `setup`, `session_state`, `ea_version`, and `git_commit`, contrary
to the comments' “blank is rejected” claim. `regime` is an unrestricted string
with no minimum length, and `session_state` accepts arbitrary text even though
the producer has an exact three-value vocabulary. The root schema likewise
calls both merely strings/enum prose rather than enforceable values.

Strip then reject blank identity/provenance, restrict regime and session state
to the real producer enums, and add focused whitespace/arbitrary-token tests.

### 18. [P1] Performance breakdown validates normalized news states but groups the unnormalized originals

**File:**
`03_SOURCE_CODE/Python/analysis/performance_breakdown.py:204-295,354-369`.

Validation case/whitespace-normalizes `news_state`, but grouping uses the
original column. Null is also treated as “no claim,” despite the current
producer/schema having the explicit `UNKNOWN` token. A focused input produced
three separate groups for `CLEAR`, `" clear "`, and null rather than one
canonical state or a rejection.

Require exact `CLEAR|BLACKOUT|UNKNOWN` at this direct ingestion boundary, or
replace the grouped column with its canonicalized values and map null to a
declared policy. Do not validate one representation and report another.

### 19. [P1] The nominal 500 MB CSV ceiling still permits multi-gigabyte peak memory

**File:**
`03_SOURCE_CODE/Python/analysis/csv_io.py:52-66,90-160`.

One-MiB reads fix the tiny-file `MemoryError`, but a permitted near-500-MB CSV
is simultaneously retained as a list of chunks, the joined `raw_bytes`, a
decoded Unicode string, one or more `StringIO` readers, pandas parser storage,
and the resulting DataFrame. The chunks remain live after `b"".join`. Peak
memory can therefore be several times the advertised ceiling. The regression
test checks requested read size, not peak memory.

Hash while streaming into a bounded spool and let pandas consume the spool, or
set a substantially smaller, measured ceiling. Do not describe a 500-MB
source limit as a reliable memory bound while making multiple full copies.

### 20. [P1] Three incompatible bar-0 conventions remain explicitly unfinished

**File:**
`03_SOURCE_CODE/Python/analysis/parameter_stability.py:64-74`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:188-189`.

The module still says parameter stability requires pre-bar `0.0`,
`analyse_giveback.py` starts with the entry bar's close, and notebook 02 starts
at `+0.5R`; it explicitly calls unification “real, not-yet-done.” Round-8
finding 19 included this inconsistency, yet the response calls that finding
resolved and says this part was not attempted. No independently numbered
owner was found.

Choose and enforce one convention across producers/consumers, or split it into
a numbered follow-up and leave the relevant TASK-028 acceptance item open.

### 21. [P1] Compile evidence proves syntax, but its Git provenance is false and it does not run MQL tests

**Files/sections:**
`09_HANDOVERS/compile_evidence/TASK-028_round8_full_compile_evidence_2026-07-27.txt:1-12`;
`09_HANDOVERS/compile_evidence/README.md:39-50`;
`09_HANDOVERS/claude_to_codex/TASK-028_round8_handover.md:20-57,114-119,157-159`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:40-64`.

The artifact genuinely contains 41 headings and 41 clean results, and every
recorded source SHA-256 matches the current 41-target tree. Its provenance
statement is nevertheless factually wrong. It says parent commit `990f32c`
is the tree containing `THEMBA_EA_GIT_COMMIT="990f32c17327"`; direct
`git show` proves that commit still contains `b362c07a1bab`. The new macro was
introduced by child commit `c9b2298`. The retained EA hash matches the child/
current source bytes, not the claimed parent tree. The README partly describes
the child correctly, so the two evidence descriptions disagree.

Compilation also does not execute any `OnStart()` assertions. No retained MQL
runtime output proves the hard-risk, concurrency, restart, partial-fill,
provider-failure, timer, or close-retry counterexamples. The handover itself
confirms no Strategy Tester/demo session was run. In particular, hard-risk
commit `338bd3c` added no executable regression covering unreadable exposure,
cross-instance reservation, actual-fill slippage, or forced closure.

Record the exact committed source tree actually compiled, distinguish semantic
parent tag from byte-exact source commit, execute the MQL test scripts, and
retain their output. Compile-clean status is necessary but not behavior proof.

### 22. [P2] Canonical status/history contradicts current source, Git dates, and its own deferrals

**Files/sections:**
`TASK-028_PYTHON_STATISTICAL_LAB.md:345-365,969-1018`;
`TASKS.md:38`;
`09_HANDOVERS/claude_to_codex/TASK-028_round8_handover.md:12-27,59-159`.

All three surfaces say all 22 findings are resolved. The same history/handover
then says the routing-order half of finding 12 was not attempted, the chart
registry remains unimplemented in source, and the bar-0 unification was not
attempted. Findings 3-5, 7-8, 10-14, 16-19, and 21 also remain partial as
shown above. “All 22” and “each with a regression test reproducing the exact
counterexample” are therefore unsupported.

The Round-8 history labels the review `2026-07-22`, but Git records the review
commit `ed46ded` at `2026-07-27 09:46:56 +0200`; its 24-commit review/remediation/
handover range also occurs on July 27. The task's acceptance criteria remain
unchecked, which is consistent with an in-progress task but inconsistent with
the surrounding blanket closure language.

Correct these as current facts: round 8 was reviewed/remediated on July 27;
list resolved, partial, and deferred scopes separately; keep TASK-028 and the
dependent task rows in progress until this review is resolved and real MT5
evidence items are run.

### 23. [P2] Committed notebook output and diff hygiene are stale/machine-local

**Files:**
`03_SOURCE_CODE/Python/notebooks/00_journal_pipeline_demo.ipynb:94,186`;
`03_SOURCE_CODE/Python/notebooks/01_baseline_trade_audit.ipynb:65`;
`09_HANDOVERS/compile_evidence/TASK-028_round8_full_compile_evidence_2026-07-27.txt:1991`.

Committed notebook outputs expose `C:\Users\THEMBA~1\AppData\Local\Temp\...`.
Notebook 00 records Git commit `ca2cbe1`, not reviewed HEAD `79da9c9`. The
notebooks do execute successfully from clean kernels, but their committed
outputs are not current/portable evidence. Regenerate them at the reviewed
commit with portable labels or clear outputs. `git diff --check 7252987..HEAD`
also reports the compile-evidence file's extra blank line at EOF; remove it.

## Corrections independently confirmed

The following round-8 work is genuinely present and should be retained:

- The `OnInit` account guard now correctly requires hedging mode (EA 302-308).
- The spread default is 0.15 and `[0.02,1.0]` is validated at startup.
- The immediate low-confidence regime override is wired.
- Persistence keys use bounded encodings; the original 63-character overflow
  defect is resolved, and checked setters/flushes were added broadly.
- Pending-order risk is now included in the visible snapshot, no-stop exposure
  has a 10-ATR fallback, and `DONE_PARTIAL` is recognized as exposure.
- MT5 calendar definition-lookup failure now fails the whole fetch closed.
- Sloped chart boundaries are reprojected, and same-bar breakout/retest is
  rejected.
- Synchronous fill identity, actual entry, filled volume, and journal write-
  count checking are improved.
- Python regime-domain checks, vocabulary additions, bounded chunk reads,
  exact-byte hashing, notebook execution, and quality-gate cleanup are real.

These corrections do not neutralize the remaining failure cases above.

## Verification performed

- `pytest`: **718 passed**, 0 failed (8 expected overflow-test warnings).
- `ruff check .`: passed.
- `ruff format --check .`: **61 files already formatted**.
- `mypy analysis data_collection --ignore-missing-imports`: passed for 25
  source files.
- `pip check`: no broken requirements; active environment matches the lock.
- All 11 notebooks executed successfully through `nbconvert` using the
  `themba-python-lab` kernel.
- Current Git contains exactly 41 relevant `.mq5` targets (2 Experts plus 39
  Test/Export scripts); the evidence contains 41 headings, 41 `0 errors,
  0 warnings` results, and 41 matching current-source SHA-256 hashes.
- `git diff --check 7252987..79da9c9`: one trailing blank-line issue, reported
  in finding 23.
- `01_BASELINE/EA_V637` is byte-identical to `baseline-v637`, and
  `01_BASELINE/EA_V811` is byte-identical to `baseline-v811`, including both
  `IDENTITY.md` files. The remediation range does not touch `01_BASELINE/`.
- Worktree before writing this review was clean except the pre-existing
  untracked `.claude/` directory; it was left untouched.

## Final disposition

**CHANGES REQUESTED.** Do not merge TASK-028, do not enable the EA's order-
submission switch on a demo account yet, and do not treat its journals as
complete execution evidence. Resolve the P0 safety paths first, close or
honestly number every deferred architectural/validation item, run the MQL
behavior tests and retain their results, then request another independent
review.
