# TASK-028 independent code review - round 8

**Disposition: CHANGES REQUESTED**

**Review target:** branch `claude/task-028-python-statistical-lab`, commit
`7252987c185e0654444948b1378c78e10d1ed3f3` (`7252987`). I reviewed the
complete 18-commit remediation range after the round-7 target,
`7bccd20..7252987` (77 changed paths; 5,973 insertions and 1,297 deletions),
not only the tip commit. I independently inspected the current MQL5 and
Python source, the round-7 response, the canonical Phase-2/risk/news/test
contracts, Git history and path sets, retained compile evidence, and both
immutable baseline tags. I also ran the pinned Python gates and all 11
notebooks from clean kernels.

The response does contain real improvements, but its statement that all 20
round-7 findings are resolved is not supported by the current source. I found
**22 remaining findings: 10 P0, 11 P1, and 1 P2**. Several are direct
capital-safety defects in the live order path, not documentation polish. The
EA is **not ready to merge, not ready for a demo-account trial, and not ready
to produce trustworthy real-evidence output** at this commit.

## Findings

### 1. [P0] The account-mode safety guard is exactly inverted

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:195-207`;
`TASK-002_PHASE2_SPECIFICATION.md:1435-1439`.

The canonical decision is hedging-only: require
`ACCOUNT_MARGIN_MODE_RETAIL_HEDGING` and refuse every other accounting mode.
The EA does the opposite. It rejects hedging and admits netting/exchange
accounts while claiming the risk model assumes netting.

This is not a harmless wording inversion. On netting accounts, one symbol
position may aggregate deals from different strategies/manual activity, while
the current code attributes and manages exposure using symbol/magic scans. On
the required hedging account, several other current assumptions (notably
`OrderManager.mqh:242-268` taking the first symbol+magic position) also need to
be made position-specific. Fix the guard and the dependent position-resolution
logic together. MetaQuotes' account-mode definitions confirm that hedging
permits independent positions while netting permits only one position per
symbol: [Account properties](https://www.mql5.com/en/docs/constants/environment_state/accountinformation).

### 2. [P0] The shipped spread gate is 20 times the approved default and is not bounded

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:102-112,688-703,1314-1319`;
`TASK-002_PHASE2_SPECIFICATION.md:307-317`.

The Phase-2 predicate is
`current_spread > ATR * InpMaxSpreadATRMultiple`, default `0.15`, with the input
bounded to `[0.02, 1.0]`. The live EA ships `InpMaxSpreadAtrMultiple = 3.0` and
has no corresponding `OnInit` bounds check. That permits a spread/ATR ratio
twenty times the approved default before entering
`UNTRADEABLE_SPREAD_OR_LIQUIDITY`.

The same value is also used for post-news spread normalization, so the mismatch
can both admit poor-liquidity entries and end a spread-extended blackout much
earlier than specified. Set the correct default and reject out-of-range values
at initialization.

### 3. [P0] The hard-risk path remains incomplete and can exceed the 1% cap

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:146-157,712-765,853-940,942-1035,365-460`;
`TASK-002_PHASE2_SPECIFICATION.md:983-1004,1025-1076,1122-1136`;
`RISK_POLICY.md:5-20`.

The added ordinary per-order cap check and open-position sum are genuine
improvements, but they do not implement the approved hard-risk system:

- `ComputeOwnMagicOpenRiskCash` scans positions only. It omits every pending
  order despite the required unconditional sum of pending reservations.
- It skips stopless positions (`SL == 0`), symbol-profile failures, and
  risk-computation failures. Those paths therefore contribute zero to the cap.
  The specification instead requires a 10-ATR fallback plus stop attachment or
  mandatory close within the grace interval.
- The check is a non-atomic snapshot. Two symbol instances sharing one magic
  can both observe headroom, both submit, and together exceed 1% before either
  fill appears in `PositionsTotal()`.
- `OnTradeTransaction` has no actual-fill risk recomputation and none of the
  required persisted `closure_pending`, same-handler close submission,
  pending-order cancellation, retry-until-closed, or restart reconciliation.
- A daily/weekly breach only rejects a future entry. It does not close this EA's
  existing exposure as section 8 requires.
- The default target is 0.30% for every symbol. The approved XAUUSD default is
  specifically 0.25%; 0.30% is only within the allowed range for other
  metals/synthetics.

This needs one account/magic-wide reservation and post-fill state machine, with
all unreadable risk treated fail-closed. Merely documenting skipped risk does
not make the cap hard.

### 4. [P0] Risk persistence is neither atomic nor fail-closed

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Core/StateManager.mqh:50-120,128-169,175-183,227-247`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/DailyWeeklyLimits.mqh:33-72,116-164,170-220`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/EquityPeakManager.mqh:33-57,101-119`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:1230-1246`.

`SM_SetAccountDoublesBatch` holds a writer lock but then performs several
independent `GlobalVariableSet` calls. A process failure between iterations
leaves a partial record; the comment claiming a crash sees either none or all
is false. The lock's own first creation is check-then-unconditional-set, so two
initializing instances can reset an already-acquired lock just like the intent
race the response tried to fix.

Callers ignore failed writes. If a lock/write fails and a daily/weekly baseline
is absent, `DWL_Get*ChangePercent` returns false, `DWL_Is*LossBreached` returns
false, and the EA records `daily_weekly_loss_caps_clear`. That converts a risk-
state failure into permission to trade. Peak updates are likewise separate
read/compare/write operations, so concurrent instances can overwrite a higher
peak with a lower one. They are invoked only on the completed-bar decision
path, not every tick as the peak-equity contract requires.

Use a recoverable commit/version protocol (or one encoded record), verify every
write, retry/reconcile under a genuinely atomic lock, and block entries when
the risk state cannot be proven valid.

### 5. [P0] The durable-intent protocol is still not durable or restart-idempotent

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/IntentManager.mqh:69-123,131-220`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/AsyncFillCorrelator.mqh:5-31,35-77`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:262-290,423-456,958-1044`;
`TASK-002_PHASE2_SPECIFICATION.md:1213-1225`.

Moving `if absent -> GlobalVariableSet(0)` from the hot path to `OnInit` does
not make it atomic: two charts with the same symbol/magic can still initialize
concurrently, and the delayed unconditional zero from one can reset the
other's acquired lock. After CAS, direction/volume/time are written separately
and every result is ignored.

More importantly, the implementation has no unique intent ID, does not place
that ID in the broker comment, never searches closed order/deal history, and
has no 30-second abandoned-intent timeout. The comment submitted at EA lines
970-972 is only `Themba_<strategy>`. A fill that also closes before restart has
no live position/order trace and is cleared as if never submitted.

If restart finds a still-pending order, it leaves the intent active but does
not reconstruct the session-only `AsyncFillCorrelator` arrays. The later fill
or cancellation therefore cannot pass `AFC_FindPending`, so the intent remains
stuck until another restart. Implement the broker-visible ID and live+history
reconciliation specified in section 11, rather than a symbol/magic existence
heuristic.

### 6. [P0] Persistence keys exceed MT5's 63-character limit on ordinary target symbols

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/IntentManager.mqh:33-57`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/PositionStateTracker.mqh:42-65`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/CooldownManager.mqh:50-74`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Core/StateManager.mqh:50-62`.

All namespaces concatenate unbounded login, server, symbol, ticket, magic, and
field text. MetaQuotes limits a terminal-global-variable name to 63 characters
and returns failure from `GlobalVariableSet` otherwise:
[GlobalVariableSet](https://www.mql5.com/en/docs/globals/globalvariableset).
The code ignores that return value.

With representative ordinary values, these are already invalid:

```text
ThembaEA_IM_12345678_Deriv-Demo_Volatility 100 Index_990001__active
length = 67

ThembaEA_CDM_12345678_Deriv-Demo_Volatility 100 Index_990001__cooldown_until
length = 76
```

Position-state fields can exceed the limit even without a long symbol. On a
common Deriv synthetic, the intent key cannot be created, so order submission
fails permanently; cooldown and exit state can silently disappear. Use a
bounded collision-resistant encoding and assert every generated key/write.

No code calls `GlobalVariablesFlush`, either. MetaQuotes states that sudden
failure can lose unflushed terminal globals, directly contradicting the crash-
durability claim: [GlobalVariablesFlush](https://www.mql5.com/en/docs/globals/globalvariablesflush).

### 7. [P0] Both live news providers retain fail-open schema/error paths

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/News/FairEconomyNewsProvider.mqh:219-265,276-340,361-379`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/News/MT5CalendarProvider.mqh:72-100,143-172`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:236-260,664-709`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/IntradayModeRouter.mqh:80-105`.

`FEP_LooksLikeJsonArray` validates only the first `[` and final `]`. Inputs such
as `[garbage]`, `[{}]`, or an array of schema-drift objects without a parseable
`date` pass the shape check, parse to zero events, and are cached as a verified
empty calendar. The new tests cover non-array garbage but not bracketed
malformed/incompatible data.

The MT5 provider similarly skips `CalendarEventById` failures. If every value's
definition lookup fails, the provider returns zero rather than `-1`, and the
caller treats it as no events. A partial set of failed definitions can also
silently omit the very release that should block trading.

Finally, `NEWS_PROVIDER_NONE` is rejected only when the path-based family
classifier happens to return METAL/FOREX. A real metal under an unrecognized
broker path becomes `UNKNOWN` and can select `NONE`, bypassing the mandatory
macro filter. Parse/lookup/schema failure and safety-relevant UNKNOWN
classification must propagate as provider unavailable/fail-closed.

### 8. [P0] A partially filled entry is recorded as rejection while exposure is live

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh:228-240`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:974-997`.

`OM_OpenPosition` accepts only `TRADE_RETCODE_DONE` and
`TRADE_RETCODE_PLACED`. `TRADE_RETCODE_DONE_PARTIAL` falls into the failure
branch. The EA then clears the intent and journals an order rejection even
though part of the requested position actually exists. That exposure is not
correlated to the decision and receives none of the required post-fill risk
handling.

MetaQuotes defines code 10010 as "Only part of the request was completed":
[trade-server return codes](https://www.mql5.com/en/docs/constants/errorswarnings/enum_trade_return_codes).
Treat it as live exposure, resolve the actual position/deal/volume, keep the
intent until terminal resolution, and run the post-fill hard-risk check.

### 9. [P0] A first low-confidence bar can still trade the prior confirmed regime

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:1295-1327`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/RegimeGateComposer.mqh:46-74`;
`TASK-002_PHASE2_SPECIFICATION.md:401-411`.

The EA maps confidence below 0.5 to `TRANSITION_OR_UNCERTAIN`, but the composer
bypasses hysteresis only for news/spread. If the previous confirmed regime was
tradable, the first low-confidence evaluation becomes merely a pending
transition; `effective_regime` remains the stale tradable regime and strategies
can still submit. That contradicts the specification's statement that
confidence below 0.5 **forces** transition treatment for routing regardless of
the nominal state. The low-confidence safety override must be immediate.

### 10. [P0] The mandatory intraday close is not guaranteed across a no-tick boundary

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:467-524`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/SessionManager.mqh:78-93`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/IntradayCloseManager.mqh:25-57,159-185`;
`RISK_POLICY.md:20`.

Moving the close to the start of every `OnTick` is an improvement, but there is
no timer. If no tick arrives at or after 23:45 before midnight, the close never
runs; the next day's tick makes `SN_IsPastIntradayBoundary()` false again, so
overnight exposure can remain. The boundary is also a hard-coded default in
function arguments, not the specified operator input.

Use a timer plus persisted due/pending state spanning midnight, and reconcile
the previous day's unfinished close before allowing any new entry. The current
in-memory once-per-day guard is insufficient for the mandatory "close all
exposure by the approved intraday boundary" rule.

### 11. [P1] Order identity, actual-fill journaling, and asynchronous evidence remain incomplete

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh:242-268`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:303-364,423-456,970-1044,1467-1550`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh:240-291`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:269-290`.

For a synchronous fill, `OrderManager` scans and takes the first matching
symbol+magic position. On the required hedging account that can be an older
position; the opening deal's `DEAL_POSITION_ID` is the causal key and should be
used. The journal leaves `entry` at the strategy's requested price even though
`open_result.fill_price` is known, so entry, stop distance, and recorded risk
do not describe the actual fill.

For `PLACED`, the original decision keeps null IDs. Resolution now emits only a
terminal `Print`; there is no schema-valid submission/fill/cancel event or
update that Python can join. Comments at EA lines 355-364 and TASK-036 still
claim a follow-up row is appended, contradicting the code. A crash after broker
acceptance but before the later journal append can leave exposure with no
decision record at all.

`DJ_AppendDecision` also ignores the return value of `FileWriteString` and
returns true after a short/failed write. Define a separate append-only order
lifecycle event schema, causal IDs, actual fill fields, and checked durable
writes.

### 12. [P1] Intraday mode is still post-hoc, not the approved routing stage, and its journal vocabulary is invalid

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:1175-1205,1344-1501`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/IntradayModeRouter.mqh:20-33,63-77,127-135,310-364`;
`TASK-002_PHASE2_SPECIFICATION.md:191-216,291-294,426-440`;
`TRADE_DECISION_SCHEMA.json:5-7`;
`03_SOURCE_CODE/Python/analysis/schema.py:79-86`.

The specification orders regime -> mode -> mode-aware strategy generation ->
post-hoc consistency. The EA evaluates all five strategies, performs regime
routing, and resolves the winner **before** computing mode. Mode then only
vetoes the winner by expected R. Every strategy uses one shared M15 data
window, not the family-by-mode context/entry timeframe table; there is no scalp
attempt/unchanged-level counter. Hysteresis explicitly uses two module
evaluations rather than two closed M1 bars, and weights are hard-coded rather
than bounded inputs.

`IntradayModeRouter` legitimately returns `NONE` for a gating regime, invalid
score, or initial neutral state, and the EA journals that string. Both schema
files permit only `SCALP|DAY_TRADE`, so normal fail-closed decisions are
rejected by the Python ingestion path. Conversely, a data-read failure is
fabricated as `SCALP` and `CLEAR` even though mode and news were not evaluated,
contaminating both analyses. Add an explicit `NONE/UNKNOWN` vocabulary and
implement the approved pre-strategy mode routing.

### 13. [P1] Close/cooldown transaction handling is not position-lifecycle-safe

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:365-420,1062-1169`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh:280-334,364-405`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/IntradayCloseManager.mqh:66-116`.

Every OUT/OUT_BY/INOUT deal is immediately recorded as one closed trade for
the three-loss cooldown, even if the position remains open after a partial
close. Three partial losing fills from one position can therefore become three
consecutive losses. The amount includes close-side costs only, not allocated
entry-side costs. `INOUT` is treated only as closure, although the same deal
also creates a new opposite leg whose state is never initialized.

A close returning `PLACED` is considered not closed and retried on every tick,
but there is no close-in-flight correlation. Repeated requests can be submitted
before the first terminal transaction arrives, producing close-order-exists,
rate-limit, or volume errors. MetaQuotes explicitly says transaction arrival
order is not guaranteed: [OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction).

The exit wrapper also applies one global `InpTimeStopUsesScalpMode` Boolean to
every position instead of persisting each position's entry-time mode. Aggregate
cooldown P/L by stable position lifecycle and persist one in-flight close state.

### 14. [P1] Chart-pattern execution lacks the specified state machine and uses stale sloped boundaries

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/ChartPatternEngine.mqh:300-338,342-430`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/ChartPatternStrategy.mqh:170-208`;
`TASK-002_PHASE2_SPECIFICATION.md:764-840`.

No persistent `FORMING/CONFIRMED/RETESTING/TRADED/INVALIDATED/EXPIRED`
registry exists. A geometry is rediscovered statelessly on every bar, so the
same pattern can be traded repeatedly. "Retest" is merely current proximity to
the boundary; no state proves that breakout occurred first and then price
returned, allowing same-bar breakout/retest behavior.

For triple top/bottom and other sloped boundaries, the detector stores
`boundary_price` evaluated at an old pivot (for example triple top at `h1`,
line 333). The live strategy compares the current close directly with that old
value at lines 185-188 instead of projecting the line to the current/retest
index. That changes entry eligibility whenever the neckline slopes. Preserve
the line anchors/state and evaluate the boundary at the queried bar.

### 15. [P1] The CSV ceiling fix requests a 500 MB allocation for every read and breaks pytest

**Files:**
`03_SOURCE_CODE/Python/analysis/csv_io.py:46-52,79-106`;
`03_SOURCE_CODE/Python/tests/test_csv_io.py:66-90`.

Every tiny CSV is opened with `fh.read(MAX_CSV_FILE_BYTES + 1)`, where the
default is 500,000,000 bytes. CPython attempts a buffer sized to the requested
count; a one-byte probe peaked at about 500,008,794 bytes. The regression test
monkeypatches the limit to ten bytes and therefore never exercises the shipped
allocation.

Two independent full runs in the pinned environment produced respectively
`691 passed / 3 failed` and `690 passed / 4 failed`, with every failure a
`MemoryError` at `csv_io.py:101`. This directly falsifies the response's
`694 passed, 0 failed` final-gate claim and is nondeterministic under available
memory. Read in bounded chunks or through a capped streaming wrapper; do not
request the entire ceiling in one call.

### 16. [P1] Error budgets and multi-artifact report publication are still non-atomic

**Files:**
`03_SOURCE_CODE/Python/data_collection/journal_reader.py:596-636`;
`03_SOURCE_CODE/Python/analysis/pattern_validation.py:1523-1558` (representative;
the same output/sidecar pattern occurs in other pipelines).

The remaining parse-error budget is passed into the line reader, but schema
validation subsequently appends every validation error and checks the combined
budget only after the whole file. Five syntactically valid, schema-invalid
records with `max_retained_errors=1` were all validated and retained before
`JournalReaderLimitError`. The claimed memory bound therefore still does not
hold for validation errors within one file.

Metadata is now computed before results, which fixes one specific invalid-repo
failure. It does not make a result CSV and mandatory provenance JSON one atomic
publication. Fault-injecting a sidecar write failure leaves the result CSV
present without its provenance. Stage both files, then publish a manifest/
directory transaction or remove the staged result on failure.

### 17. [P1] The Python-vs-MQL pattern cross-check can pass a completely different dataset

**Files:**
`03_SOURCE_CODE/Python/analysis/pattern_validation.py:1367-1414`;
`03_SOURCE_CODE/MQL5/Scripts/Export_PatternDetectorResults.mq5:119-151`;
`03_SOURCE_CODE/Python/notebooks/09_pattern_detector_validation.ipynb:110-120`.

The exporter now includes symbol, timestamp, OHLC, and ATR provenance, but the
comparator derives its columns only from `detect_all_patterns()` (`k` plus
Booleans) and ignores every provenance field. A probe with the wrong symbol, a
1999 timestamp, and entirely different OHLC/ATR but matching Boolean flags
returned zero disagreements. Exact `k` coverage proves only that two tables
have the same row numbers, not that they classified the same bars.

Bind each comparison row to a checked symbol/timestamp/OHLC/ATR identity (and
logical-index convention). Notebook 09's text is also stale: it still says no
MQL exporter exists and only four predicates are ported.

### 18. [P1] Equity analysis merges unrelated runs/accounts into one artificial curve

**Files:**
`03_SOURCE_CODE/MQL5/Experts/EquityTickRecorder.mq5:20-38,61-119`;
`03_SOURCE_CODE/Python/analysis/equity_curve_metrics.py:65-116,188-229`.

The recorder intentionally appends `run_id`, `account_login`, and
`broker_server` so repeated runs are distinguishable. The consumer merely
checks that the columns exist, sorts the entire file, and computes one curve.
It neither filters nor rejects mixed identity tuples. A two-run/two-account
probe produced an artificial 90% maximum drawdown at the boundary between
otherwise independent curves.

Require exactly one `(run_id, account_login, broker_server)` per result or
return separately grouped metrics. Also escape/validate the CSV identity
fields rather than assuming broker names cannot contain delimiters.

### 19. [P1] Several analytical public-domain and schema contracts remain permissive or inconsistent

**Files:**
`03_SOURCE_CODE/Python/analysis/regime_validation.py:125-205`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/MarketRegimeEngine.mqh:60-75`;
`03_SOURCE_CODE/Python/analysis/performance_breakdown.py:133-158`;
`03_SOURCE_CODE/Python/analysis/parameter_stability.py:64-74`;
`03_SOURCE_CODE/Python/analysis/schema.py:1-15,74-120`;
`TRADE_DECISION_SCHEMA.json:1-27`.

- `classify(..., trend_threshold=0)` reaches a raw division by zero; a negative
  `trend_slope_atr_divisor` returns a valid read even though the MQL/source
  domain is positive and bounded. Other thresholds/agreement/ADX domains are
  likewise not enforced at the public boundary.
- `performance_breakdown` deliberately accepts and groups arbitrary
  `news_state` text; `BANANA` becomes a valid report group even though the
  canonical producer vocabulary is `CLEAR|BLACKOUT`.
- `parameter_stability.py` still documents three incompatible bar-0
  conventions and says unification is unfinished, while history says finding
  17 is resolved.
- Pydantic still accepts blank `signal_id`, strategy/setup/session,
  `ea_version`, and `git_commit`. The root JSON schema still calls
  `news_state` merely `string`. `schema.py`'s module docstring also still says
  order/deal IDs are absent from MQL/JSON although both now contain them.

Validate the source domains and nonblank identity/provenance vocabulary at
every public ingestion boundary; do not rely on an assumed prior pipeline.

### 20. [P1] The declared Python quality/notebook gates are not clean

**Files:**
`03_SOURCE_CODE/Python/notebooks/00_journal_pipeline_demo.ipynb:56-105`;
`03_SOURCE_CODE/Python/notebooks/04_session_and_news_analysis.ipynb:44-70`;
`03_SOURCE_CODE/Python/pyproject.toml:17-49`.

Clean-kernel execution results:

- Required notebook 04 fails because its decision fixture uses
  `news_state=""`; schema validation yields zero decisions and the blackout
  assertion fails.
- Bonus notebook 00 fails because its supposedly valid fixture uses lowercase
  `news_state="clear"`; it reports zero valid records and two validation
  errors.
- The other nine required notebooks pass.

`ruff check .` and mypy pass, but `ruff format --check .` says eight files
would be reformatted:

```text
analysis/compare_releases.py
analysis/equity_curve_metrics.py
analysis/pattern_validation.py
analysis/regime_validation.py
tests/test_analyse_giveback.py
tests/test_equity_curve_metrics.py
tests/test_join_signal_to_outcome.py
tests/test_regime_validation.py
```

Together with finding 15, the response's final verification state is not
reproducible.

### 21. [P1] Retained MQL compile evidence and embedded build provenance are false/incomplete

**Files:**
`09_HANDOVERS/compile_evidence/TASK-028_round7_full_compile_evidence_2026-07-22.txt`;
`09_HANDOVERS/compile_evidence/README.md:3-29`;
`09_HANDOVERS/claude_to_codex/TASK-028_round7_handover.md:34-50`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:40-54`.

At evidence commit `970cb39`, Git contains 39 `.mq5` programs: two Experts and
37 Test/Export scripts. The artifact has 38 headings/results: the main EA plus
the 37 scripts. `EquityTickRecorder.mq5` is omitted. The handover instead says
there are 38 Test/Export scripts and that all 39 programs compiled. Both counts
are wrong.

The 121-line artifact is also mostly one `Result:` line per target; only one
target retains normal compiler-information lines. It omits invocation,
compiler version/build, source hashes, and most raw compiler log text, so it is
not the "complete compiler output" promised by the README/master prompt.

Finally, the EA says its manual macro must identify the exact compiled commit,
but `THEMBA_EA_GIT_COMMIT` is `b362c07a1bab`. The retained build is attributed
to `970cb39`, seven later commits after changes to 13 MQL paths including the
EA. Every journal from that binary would claim the wrong source. Generate the
tag at build time and retain complete evidence for every `.mq5` target.

### 22. [P2] Canonical history/status documents contradict the source, Git, and their own deferrals

**Files:**
`09_HANDOVERS/claude_to_codex/TASK-028_round7_handover.md:24-50,55-217`;
`TASK-028_PYTHON_STATISTICAL_LAB.md:345-390,896-943`;
`TASK-036_JOURNAL_PRODUCER_COMPLETION.md:269-312`;
`TASK-037_MT5_EXPORT_BRIDGE.md:154-190,296-326,343-347`;
`TASK-040_INTRADAY_MODE_ROUTER.md:30-56,101-122`;
`TASK-041_EXIT_ENGINE_WIRING.md:44-88,123-129`;
`TASKS.md:38-52`.

The handover says all 20 findings received complete fixes and exact regression
tests, then explicitly defers parts of the reviewed findings: a schema-correct
async event, cost sensitivity, unified bar-0 convention, historical
spread/liquidity replay, and the `INOUT` new leg. Current task records add more
contradictions:

- TASK-028's Reviewer section still says six rounds while its later history and
  `TASKS.md` say seven.
- TASK-036 still claims the old signal-ID shape and an async follow-up journal
  row; current source logs only.
- TASK-037 still describes the old raw regime export and close-only cost model,
  while its implementation was changed; it also keeps real-run acceptance open.
- TASK-040 still describes a superseded candidate-dependent/journal-only router;
  TASK-041 still says once-per-completed-bar position management.
- `TASKS.md` says TASK-033 kept four default pattern columns, while the current
  source has 16; several rows say Done while their task files say In progress
  and leave independent-review acceptance unchecked.
- Live transition history, cost scenarios, OHLC/R paths, session/news evidence,
  schema-correct async events, historical gate replay, and the unified bar-0
  convention remain unimplemented or unowned despite the closure wording.

Record remediation as applied/pending review, preserve unresolved sub-items as
open numbered work, and make the task statuses derive from one canonical
source rather than repeating stale claims.

## Verification performed

### Git and scope

- Reviewed `7bccd20..7252987`: 18 commits, 77 changed paths, 5,973 insertions,
  1,297 deletions.
- `git diff --check 7bccd20..7252987`: clean.
- The current worktree reports the EA as modified only because of index/stat
  state: its working-file blob hash and HEAD blob are both
  `647abfb73261e8fea3420e735fbedbee53e56d13`, and `git diff` is empty. I did
  not touch or normalize it. The pre-existing untracked `.claude/` directory
  was also left untouched.

### Python gates (pinned environment)

- Python `3.13.14`; pytest `9.1.1`; ruff `0.15.22`; mypy `2.3.0`.
- Full pytest: not reproducibly clean. Two runs produced 3 and 4 failures,
  respectively, all `MemoryError` at `analysis/csv_io.py:101`.
- `ruff check .`: pass.
- `ruff format --check .`: fail; 8 files need formatting.
- `mypy analysis data_collection --ignore-missing-imports`: pass, 25 source
  files.
- Clean-kernel notebooks: 9/10 required pass; required notebook 04 fails.
  Bonus notebook 00 also fails.

### MQL evidence

- Retained evidence contains 38 zero-error/zero-warning result summaries, not
  the claimed 39; `EquityTickRecorder.mq5` is absent.
- The MQL tree at evidence commit `970cb39` is byte/tree-identical to HEAD, so
  the artifact's 38 covered targets do apply to their current source. This is
  syntax evidence only; none of the transaction, restart, concurrency,
  provider-failure, no-tick-boundary, or broker-mode paths above was run.
- The handover explicitly confirms no real/demo MT5 session was executed.

### Immutable baselines

Both baseline directories, including `IDENTITY.md`, are byte/tree-identical to
their tags:

```text
EA_V637 HEAD/tag tree: fe46191174b150c4c1e0dceb1bffc6c42a076384
EA_V811 HEAD/tag tree: 3bc9e68939873de57c70319ff75f3b39ffd58c75
```

No file under `01_BASELINE/` was modified.

## Corrections independently confirmed

The remediation did genuinely improve several areas: current-time MT5
calendar bounds/scaling/per-occurrence identity; ordinary per-order sizing-cap
enforcement; boundary-first and per-tick exit invocation; data-failure
journaling; multi-IN/partial-close aggregation in the history exporter;
pairwise triple-pattern tolerance and sloped target math; several Python
non-finite/overflow/ID-domain checks; role-qualified report hashes; invalid-tail
hashing; and observed-period coverage ratios. Those improvements do not resolve
the blockers above.

## Final disposition

**CHANGES REQUESTED.** Do not merge this branch and do not attach the EA to a
demo or live account at `7252987`. Resolve all P0 findings, make the Python and
MQL evidence gates reproducibly clean, correct the P1 analytical/evidence
contracts, reconcile the canonical history, then request another independent
review. A demo trial should begin only after that review approves the exact
compiled commit and the mandatory release-gate tests are run.
