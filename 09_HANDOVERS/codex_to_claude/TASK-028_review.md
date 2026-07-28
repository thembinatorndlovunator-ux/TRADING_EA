# TASK-028 independent code review - round 10

**Disposition: CHANGES REQUESTED**

**Review target:** branch `claude/task-028-python-statistical-lab`, commit
`6213a48f038e77716145ad54cf5a6a7ebe63e725` (`6213a48`). I reviewed the
complete remediation range after the round-9 target,
`79da9c9302bfeecef84303a4b65cb2930b46f87e..6213a48` (27 commits, 67 changed
paths, 8,338 insertions, 1,201 deletions), the round-9 handover, current MQL5
and Python source, canonical specifications and risk policy, Git history,
retained compile evidence, tests, notebooks, and both immutable baseline tags.

The remediation contains substantial genuine work. The retained 46-target
MetaEditor compile is internally authentic, every recorded source hash matches
the compiled tree, and the Python gates are clean. Those facts do **not**
support the handover's assertion that 21 findings received complete fixes.
Several fixes repeat the race they claim to remove, and multiple hard-risk and
mandatory-closure paths still fail open.

I found **21 remaining findings: 7 P0, 11 P1, and 3 P2**. The EA is **not ready
to merge as a completed TASK-028 package, not ready for a demo-account trial
with `InpEnableOrderSubmission=true`, and not ready for live use**. The two
registered architecture tasks, TASK-043 and TASK-044, also remain explicitly
not started. A journal-only attachment with order submission disabled may be
used for observation, but it does not exercise or validate the unsafe paths
below.

## Findings

### 1. [P0] The account lock's new bootstrap and timestamp protocol are still raceable, and multi-field risk state is still non-transactional

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Core/StateManager.mqh:124-182,204-228,280-354`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/DailyWeeklyLimits.mqh:135-182`;
`TASK-002_PHASE2_SPECIFICATION.md:1194-1211,1394-1403`.

`SM_AcquireAccountLock()` does not make first-use creation race-free. Two
callers can both fail `GlobalVariableSetOnCondition()` because the key is
absent. Caller A can execute `GlobalVariableSet(lock_key, 0.0)` and then
acquire a nonzero token; delayed caller B can subsequently execute the same
unconditional set at line 167 and overwrite A's live token with zero. The
comment at lines 124-136 calling this “provably race-free” is false. The CAS
also is not preceded by `ResetLastError()`, so its interpretation of
`GetLastError()` at lines 163-167 is not isolated from a stale prior error.

The lock token and `__since` timestamp are separate, unowned writes. Acquire
returns at lines 157-160 and callers stamp later at 225-228. A contender can
therefore observe a new token with an old stale timestamp and break it at
173-182. Release CAS-clears the token at 207, then unconditionally clears
`__since` at 216. A new holder can acquire and stamp between those operations,
after which the old holder erases the new holder's timestamp. The source's
claim at 208-215 that nobody can observe that interval is not established.

Finally, the batch writer itself explicitly concedes at 297-321 that it has no
WAL/versioned-record transaction. Stopping after the first failed write fixes
one ordinary write-failure ordering, but a crash after a successful baseline
write and before its cursor/marker still lets recovery capture later equity or
double-apply a cash flow. `DWL_ApplyCashFlowAdjustments()` writes daily
baseline, weekly baseline, and deal cursor as three separate globals at
175-182, so the admitted crash window is in a binding risk path.

**Required correction:** replace first-use plain-set bootstrapping with a
creation/acquisition protocol that cannot overwrite a live owner; bind the
staleness timestamp to the same owner token and condition its update/clear on
that token; and persist logically coupled risk fields as one recoverable
versioned record or WAL transaction. Add real concurrent-first-use,
stale-break, delayed-release, write-failure, and crash/restart tests.

### 2. [P0] Hard-risk reservations are ownerless and do not make the exposure check atomic

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/RiskReservationManager.mqh:37,44-55,66-86,91-175`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:1959-1983,2000-2023,2053-2075,2084-2091,2142-2148`;
`TASK-002_PHASE2_SPECIFICATION.md:986-987,1024-1035,1062-1076`;
`RISK_POLICY.md:5-11`.

There is only one reservation key per `symbol+magic` at RRM 52-55; it has no
reservation ID or owner/intent token. A second same-symbol caller can include
the first reservation in its sum, then overwrite that exact key at 143-145.
If its later `IM_BeginIntent()` fails, EA 2022 blindly deletes the other
caller's live reservation. The same stale-release defect can occur when an old
fill path clears intent and a newer flow reserves before the old
`RRM_ReleaseReservation()` runs. Release is unlocked and unconditionally
deletes the shared key at RRM 168-175, contrary to the comment that no other
holder can be affected.

The actual-position/pending-order risk snapshot is computed before the RRM
lock at EA 1968-1983. Consequently, “actual exposure + reservations + new
reservation” is not one critical section as RRM 18-22 and 97-100 claim. A
position can appear after a caller's stale snapshot but before its locked
reservation decision. Reservations also disappear from the sum after the
fixed 120-second age at RRM 37 and 79-86 even when an accepted broker request
has not been reconciled. The `exposure_unresolved` path releases at EA
2073-2075 while the surrounding source admits the real fill's details are not
yet resolvable; the assertion that `PositionsTotal()` will already account for
it is not proven.

**Required correction:** use a unique reservation/intent owner key, owner-
checked release, and an account/magic-wide lock that encloses a fresh actual
exposure scan, reservation sum, and new reservation write. Do not age out or
release accepted/unresolved exposure until broker history/position state
proves its terminal disposition.

### 3. [P0] Actual-fill 1% cap enforcement still has multiple silent bypasses

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:795-853,972-1045,1586-1688`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh:160-178`;
`TASK-002_PHASE2_SPECIFICATION.md:1024-1035,1073-1076,1122-1136`;
`RISK_POLICY.md:5-11,45-46`.

The post-fill hard-cap block is below `HistoryDealSelect(trans.deal)`. A select
failure returns at EA 852-853, so the actual-fill cap is skipped entirely even
though the preceding comments claim only deal-specific work remains below the
gate.

When selection succeeds, the code reads `DEAL_POSITION_ID` and passes it to
`PositionSelectByTicket()` at 995-996. `DEAL_POSITION_ID` is the durable
`POSITION_IDENTIFIER`; it is not guaranteed to equal the current
`POSITION_TICKET`, a distinction OrderManager itself documents at 160-178.
Selection failure has no fail-closed `else`, so neither per-trade nor aggregate
cap enforcement runs.

The per-trade formula at EA 1012-1018 uses `abs(fill - SL)`. The specification
requires directional `max(0, loss-side distance)`: for a buy filled below an SL
that is now on the profit side, `abs` invents risk and can force a false close.
Neither this calculation nor `ComputeOwnMagicOpenRiskCash()`'s calculations at
1631-1683 perform the policy-required `OrderCalcProfit` cross-check. Finally,
the aggregate scanner silently continues when `PositionGetTicket()` or
`OrderGetTicket()` returns zero at 1593-1595 and 1644-1646, treating an
unreadable component as absent rather than invalidating the cap calculation.

**Required correction:** enforce the actual-fill check even when history
selection is temporarily unavailable; select/enumerate by the correct ticket
or compare `POSITION_IDENTIFIER` explicitly; fail closed on every unreadable
component; use the directional loss formula; and apply the broker-native
cross-check to every binding risk-cash computation.

### 4. [P0] The durable-intent “race-free” bootstrap repeats the same destructive first-use race

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/IntentManager.mqh:169-235,256-287`;
`TASK-002_PHASE2_SPECIFICATION.md:1213-1225`.

`IM_BeginIntent()` has the same interleaving as finding 1. Two callers can both
observe the missing key. Caller A can create zero and CAS it to active; delayed
caller B then executes the unconditional `GlobalVariableSet(active_key, 0.0)`
at line 201, erasing A's live intent and allowing a duplicate submission. The
“provably race-free” claim at 169-181 is therefore false. It also reads
`GetLastError()` without resetting it before the CAS.

After active is acquired, `is_long`, `volume`, `timestamp`, and
`intent_micro` are four independent writes at 216-235. Ordinary failures are
rolled back, but a process crash can leave `active=1` with an incoherent
record; there is no prepare/commit marker. Exact-ID matching and improved
history enumeration are real improvements, but they do not repair acquisition
or record atomicity.

**Required correction:** make absent-key acquisition genuinely atomic and
persist one versioned intent record with a recoverable prepare/commit state.
Test two simultaneous first-ever callers and crash at each persisted field.

### 5. [P0] A mixed valid/malformed FairEconomy response can still hide a high-impact event and be cached as safe

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/News/FairEconomyNewsProvider.mqh:233-305,383-445`;
`03_SOURCE_CODE/MQL5/Scripts/Test_FairEconomyNewsProvider.mq5:189-244`;
`NEWS_INTEGRATION_SPEC.md` (provider-unavailable fail-closed policy).

`FEP_ParseFeedJson()` skips an object with a missing date at 275-276 and an
unparseable date at 278-281 **before** setting
`any_required_field_missing_out` at 283-284. A payload containing one valid
benign event and one high-impact object whose date is absent or malformed has
`raw_object_count=2`, `parsed_count=1`, and the malformed flag remains false.
`FEP_FetchLive()` rejects only “all objects unparseable” at 416-423 or a flag
set by a date-parseable malformed object at 435-443. It therefore accepts and
caches that partial calendar.

The new tests cover malformed fields on objects with parseable dates; they do
not cover the mixed valid plus invalid/missing-date counterexample.

**Required correction:** validate every raw object's required schema,
including date presence and parseability, before any `continue`; reject the
entire fetch if any object is malformed; add both mixed-payload regressions.

### 6. [P0] Mandatory boundary/no-stop protection is still tick-dependent or non-durable

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:515-550,1180-1194,1220-1242,1691-1740`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/DailyWeeklyBreachManager.mqh:57-75,95-153`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/NoStopGraceManager.mqh:33-50,103-135`;
`TASK-002_PHASE2_SPECIFICATION.md:1011-1015,1037-1044,1122-1136`;
`RISK_POLICY.md:20`.

If `EventSetTimer(30)` fails, OnInit logs that the no-tick guarantee is absent
at EA 536-540 but still returns `INIT_SUCCEEDED` and can enable real order
submission at 542-550. The only retry is on a future tick at 1193-1194; with no
tick, the condition that motivated the timer remains unprotected.

`OnTimer()` calls only the intraday-close manager at 1180-1184. The five-second
no-stop grace clock is first armed and enforced only from OnTick at 1237-1242
and 1703-1740. A stopless position can therefore remain untracked and open
indefinitely during a tick-starved interval, despite the specification's
wall-clock five-second maximum.

For loss-cap closure, `DailyWeeklyBreachManager` explicitly admits at lines
71-73 that its fallback does not survive restart. It proceeds with closure
after a failed `closure_pending=true` write at 125-134; a crash during that
attempt loses the mandatory retry obligation. The analogous no-stop in-memory
timestamp also resets after restart when its persisted write failed.

**Required correction:** do not permit order-enabled initialization without a
working independent timer; run all wall-clock mandatory protections from that
timer; and make closure/no-stop obligations durably reconstructible when a
persistence write fails. Retain actual timer-failure, no-tick, write-failure,
and restart evidence.

### 7. [P0] Daily/weekly state failure disables breach detection instead of creating a fail-closed obligation

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:229,795-845,1231-1235,2546-2549`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Risk/DailyWeeklyLimits.mqh:135-182`;
`TASK-002_PHASE2_SPECIFICATION.md:1078-1136`.

Moving cash-flow rebasing before the fill-time breach check is correct in the
normal success path. On failure, however, EA 825-826 sets
`g_daily_weekly_risk_state_valid=false`, and lines 831-834 consequently force
both breach booleans false. No pending closure or independent re-evaluation
obligation is armed. OnTick retries only a closure that is already pending at
1231-1235; a later completed-bar refresh gates future entries but does not
necessarily close existing exposure that should already have been tested.

The validity flag also starts false at line 229 and is initialized through the
completed-bar evaluation path at 2546-2549. A deal arriving before that first
evaluation—for example while reconciling pre-existing own-magic exposure—can
skip the account-wide 2%/4% check. The baseline/cursor crash non-idempotence in
finding 1 compounds this path.

**Required correction:** unknown daily/weekly state must block entries and
create a durable, repeatedly evaluated fail-closed obligation for existing
exposure; initialization/restart must load and validate the state before any
deal can be treated as cap-clear.

### 8. [P1] Async/partial-fill lifecycle handling still loses position-mode and close-finalization state

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:869-969,1059-1153,2179-2194,2378-2393`.

Keeping the correlator and intent alive for a live partial remainder is a real
fix. The asynchronous `DEAL_ENTRY_IN` path, however, never persists the
position's entry-time intraday mode. Only the synchronous branch does so at
2179-2194. Exit management later falls back to the one global input at
2378-2393, so asynchronously opened positions do not receive the per-position
time-stop behavior the comments promise.

For exits, cooldown finalization and PST/NSG/CIFT cleanup occur only if
`PositionStillOpenById()` is already false while processing the closing
`DEAL_ADD` at 920-948. MT5 does not promise that all transaction types arrive
in an order that makes the position absent at that exact callback, and there
is no later position-transaction/reconciliation path that finalizes a close
missed there. A fully closed position can therefore retain state and fail to
advance the consecutive-loss ledger.

**Required correction:** initialize entry state from every confirmed sync or
async fill, and persist a close-finalization obligation that is reconciled
after the position disappears rather than depending on one callback ordering.

### 9. [P1] Chart-pattern lifecycle marks candidates TRADED before confirmation or execution and omits required lifecycle branches

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/ChartPatternLifecycle.mqh:5-46,93-192`;
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Strategies/ChartPatternStrategy.mqh:80-209,335-382,415-480`;
`TASK-002_PHASE2_SPECIFICATION.md:845-907`.

`CPS_ApplyLifecycle()` sets `TRADED` at 168-171. The caller does this at
359-362 **before** checking candlestick confirmation at 364-382. A retest bar
without a confirming candle emits no signal but permanently consumes the
pattern. Even a confirmed candidate is consumed during strategy generation,
before mode routing, conflict resolution, news/risk gates, journal-only veto,
or broker submission, so “TRADED” does not mean traded. The range path also
sets `TRADED` at 208-209 before downstream routing/submission.

Every `CPL_SetState()`/timestamp result in the strategy is ignored. It can
return `true` and emit a candidate after the `TRADED` write failed, enabling a
duplicate after restart. There is also no CAS/lock, so concurrent instances
can both observe nonterminal state and emit the same instance.

The lifecycle file admits it has no `FORMING` stage at 35-46, and the strategy
admits no false-break invalidation at 90-96. `CPL_GetConfirmedTime()` and
`CPL_CleanupStale()` have no production callers; only tests call them. There is
no wired `InpPatternMaxAgeBars`, so the header's statement that confirmation
expiry is implemented is false and stored globals grow without production
cleanup.

**Required correction:** transition to a separate eligible state during
detection and mark `TRADED` only after a confirmed order outcome; check every
state write, serialize consumption, wire both age limits and cleanup, and
implement the specification's FORMING/false-break/alternate-terminal paths.
Tests must cover no-candle, router/risk veto, journal-only, failed persistence,
concurrency, max-age, and false-break cases.

### 10. [P1] Execution-event journaling still cannot guarantee the machine-readable fill record it claims

**Files:**
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/ExecutionEventJournal.mqh:5-25,88-91,140-183`;
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:600-644,730-762,2086-2112,2150-2177`.

The new independent journal is useful, but the source overclaims closure of
the broker-accept/crash window. For a synchronous fill, the broker can accept
before execution reaches EA 2150-2177; a crash in that interval still leaves
no event. Restart intent reconciliation at 730-762 only prints the recovered
outcome and clears/reconciles state—it does not backfill an execution event.

On async resolution, `LogAsyncFillResolution()` never sets `volume` or `price`
even though a selected fill deal provides them, so a row can say `filled=true`
with null fill economics. If `EEJ_AppendEvent()` fails, lines 638-643 merely
print after lifecycle state has already advanced; there is no durable retry
queue. The shared daily file is opened with `FILE_SHARE_READ` but not
`FILE_SHARE_WRITE` at EEJ 158-163; contention beyond the fixed 300 ms retry
budget permanently loses the event.

**Required correction:** persist an append obligation before clearing the
intent/correlator, backfill from broker history on restart, populate available
deal economics, and retry failed appends durably. Do not claim the crash gap is
closed until a crash between broker acceptance and every append point is
reconciled.

### 11. [P1] Multi-file Python report publication is still not atomic, including on an ordinary exception

**Files:**
`03_SOURCE_CODE/Python/analysis/report_metadata.py:233-316`;
`03_SOURCE_CODE/Python/analysis/join_trade_journal.py:255-287`;
`03_SOURCE_CODE/Python/analysis/join_news_events.py:420-451`.

`publish_dataframe_csv_and_json()` calls the pair “ONE atomic unit,” writes
both temporary files, then renames JSON at 311-313 and CSV at 314-316 with no
rollback. Fault injection that raises `OSError` on the second `os.replace`
left the old CSV and new JSON together, with no temp residue. This is a normal
commit-stage exception, not only the process-crash residual risk admitted at
280-290. The trade-journal and news joins repeat the same multi-rename pattern.

Every caller using the helper inherits the mixed-generation risk, including
pattern, baseline, giveback, MFE/MAE, performance, parameter-stability,
walk-forward, and signal/outcome reports.

**Required correction:** publish into a versioned generation and atomically
switch one manifest/pointer, or implement and fault-test restoration of the
entire prior generation on every rename-stage failure.

### 12. [P1] Blank server timestamps silently erase every day from daily equity analysis

**Files:**
`03_SOURCE_CODE/Python/analysis/equity_curve_metrics.py:176-180,230-249,323-331`.

`pd.to_datetime(..., errors="raise")` converts blank cells to `NaT`; it does
not raise. The later `strftime`/groupby silently drops `NaT` dates. A two-row
probe with blank `timestamp_server` values returned a valid 10% account
drawdown but `daily_days=0`, so the daily giveback report omitted the entire
curve.

**Required correction:** explicitly reject null/`NaT` values after parsing and
add a regression proving blank server timestamps cannot yield a zero-day
report.

### 13. [P1] Equity run/account identities are numerically inferred before being converted to strings

**Files:**
`03_SOURCE_CODE/Python/analysis/equity_curve_metrics.py:125-173`;
`03_SOURCE_CODE/Python/analysis/csv_io.py:215-230`.

The equity reader's documentation says identity columns are read explicitly
as strings, but line 146 does not pass `dtype`. Conversion at 157 occurs after
pandas has already discarded leading zeros or collapsed numeric forms. A CSV
containing identities `001`/`0123` and `1`/`123` was accepted as one identity,
with both rows represented as `1`/`123`.

**Required correction:** pass string dtypes for `run_id`, `account_login`, and
`broker_server` at ingestion, before any inference, and test leading-zero and
large-integer identities.

### 14. [P1] EquityTickRecorder appends the new seven-column schema to existing incompatible files

**Files:**
`03_SOURCE_CODE/MQL5/Experts/EquityTickRecorder.mq5:116-140,166-181`;
Git parent of the `b84446c` schema change.

Before `b84446c`, the same default output had a six-column header without
`timestamp_server`. Current OnInit only checks `FileIsExist()` and writes the
new header when the path is absent at 127-140. An existing old-schema,
zero-byte, or wrong-schema file is opened and receives seven-column rows at
177-180 without validation or migration, producing a malformed dataset.

**Required correction:** validate the exact existing header and fail closed,
rotate/migrate it, or use a versioned output filename. Check the write result
as well as flushing it.

### 15. [P1] Mode-first routing remains explicitly unimplemented

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:2660-2719,2798-2841`;
`TASK-043_MODE_FIRST_ROUTING_ARCHITECTURE.md:138-142`.

The EA still generates/routes all five strategies on one shared M15 window
and applies a post-hoc mode veto afterward. Its own comment at 2806-2826
admits that this differs from the executable mode-first specification.
TASK-043 remains `Not started` and expressly says the EA must not be described
as launch-ready while it is open. Registering the task is an honest process
decision, but it does not resolve the runtime behavior.

### 16. [P1] Bar-zero unification and real cross-language pattern validation remain open

**Files:**
`TASK-044_BAR_ZERO_CONVENTION_UNIFICATION.md:105-110`;
`03_SOURCE_CODE/Python/notebooks/09_pattern_detector_validation.ipynb`;
the TASK-028 acceptance criteria.

TASK-044 remains `Not started`; therefore the MQL/Python current-bar convention
is still inconsistent. Notebook 09's committed comparison remains synthetic;
no retained real MQL exporter output is compared with Python on the same
dataset and canonical bar identity. The handover correctly calls these
follow-ups, but other canonical files incorrectly call all findings resolved.
Until both are implemented and measured, pattern parity is not established.

### 17. [P1] The required MQL behavioral evidence does not exist

**Files:**
`09_HANDOVERS/compile_evidence/TASK-028_round9_full_compile_evidence_2026-07-28.txt`;
`09_HANDOVERS/claude_to_codex/TASK-028_round9_handover.md:39-43,256-262`;
`PROJECT_RULES.md:13-14`; `TEST_PLAN.md:31-44`.

The retained artifact proves syntax for 46 sources; it does not execute a
single `Test_*.mq5` `OnStart()` assertion. There is no retained Strategy
Tester report, demo attachment log, restart/concurrency run, provider-failure
run, timer-failure run, partial-fill trace, close-retry trace, or real pattern
export. The handover discloses this honestly, but the safety-critical claims in
findings 1-10 therefore remain both source-defective and behaviorally untested.
This is an explicit demo/release blocker under the project rules and test plan.

### 18. [P1] Notebook 09 was not re-executed in place after its comparison code changed

**Files:**
`09_HANDOVERS/claude_to_codex/TASK-028_round9_handover.md:75-85`;
`03_SOURCE_CODE/Python/notebooks/09_pattern_detector_validation.ipynb:187-199`;
Git commits `e573276` and `6bf68dc`.

The handover says notebooks 00, 01, and 09 were re-executed with
`nbconvert --execute --inplace`. The edited complete-identity comparison cell
in notebook 09 has `execution_count: null` and no output. Its retained
execution timestamps predate commit `e573276`, which changed that cell, and no
later commit re-executed it. A disposable fresh run succeeds, but that does not
make the committed execution/provenance claim true.

**Required correction:** execute the committed notebook in place after the
final code change and retain the resulting execution metadata/output, while
still labelling the comparison synthetic until real MQL export data exists.

### 19. [P2] Canonical closure/history text contradicts the open tasks and its own round count

**Files:**
`TASK-028_PYTHON_STATISTICAL_LAB.md:139-148,328-369,402-407,1044-1090`;
`TASKS.md:38`; `09_HANDOVERS/compile_evidence/README.md:63-75`;
compile evidence line 2; TASK-043 and TASK-044 Status sections.

The handover carefully says 21 fixes plus two registered follow-ups, yet the
compile artifact says all 23 findings were resolved, the README repeats that
claim, TASK-028's Reviewer section calls round 9 “fully resolved,” and
`TASKS.md` says all 23 were addressed/resolved. Both follow-up tasks say `Not
started`, and TASK-043 expressly forbids launch-ready framing.

TASK-028 is also internally stale: Files affected remains a planned
Python-only list even though round 9 changed 67 paths; Commit says six
remediation series; Reviewer first describes nine rounds and later calls the
review file a concatenation of “all six”; lines 402-407 still use present tense
to say round-6 P0s are unresolved and a seventh review should be requested.

**Required correction:** state one durable Git range and one truthful status:
21 implementation fixes, two open numbered follow-ups, and round-10 changes
requested. Separate historical-at-the-time text from current status and make
Files/Commit/Reviewer/Acceptance criteria agree.

### 20. [P2] Compile and notebook evidence metadata contains several Git-verifiable inaccuracies

**Files:**
`09_HANDOVERS/claude_to_codex/TASK-028_round9_handover.md:48-85`;
`09_HANDOVERS/compile_evidence/README.md:63-75`;
`09_HANDOVERS/compile_evidence/TASK-028_round9_full_compile_evidence_2026-07-28.txt:8-24`;
`TASK-044_BAR_ZERO_CONVENTION_UNIFICATION.md:11`; `TASKS.md:54`.

- The rise from 41 to 46 compile targets came from five new scripts:
  `Test_RiskReservationManager`, `Test_DailyWeeklyBreachManager`,
  `Test_NoStopGraceManager`, `Test_ExecutionEventJournal`, and
  `Test_ChartPatternLifecycle`. The handover/README/history name only two and
  incorrectly attribute the rest to touched scripts.
- The compile artifact does not literally record `a4cc8f5`, despite the
  handover saying it records the compiled tree commit. It also says that
  evidence commit changes only the EA and evidence file, while Git shows it
  also changes the compile-evidence README.
- The handover says the “other 7 required notebooks” were untouched. TASK-028
  defines ten required notebooks; after required notebooks 01 and 09, eight
  remain. Notebook 00 is additional.
- TASK-044 says it was registered 2026-07-27, but its creation commit
  `8510cc2` is 2026-07-28 01:42:28 +0200.
- Per-commit compile/test claims have no retained per-commit artifacts. They
  must be identified as author-reported actions, not independently auditable
  evidence.

The final-state compile result itself is valid; these are provenance/history
errors, not evidence that the compiler logs were fabricated.

### 21. [P2] Runtime/build provenance and TASK-028's “current state” narrative remain stale

**Files:**
`03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5:40-49,71-72`;
`03_SOURCE_CODE/Python/notebooks/00_environment_and_data_contract.ipynb` output near line 198;
`TASK-028_PYTHON_STATISTICAL_LAB.md:431-448,507-532,1069-1072`.

The EA comment says `THEMBA_EA_GIT_COMMIT` identifies the actual commit the
file was compiled from, but the current/compiled source embeds `2e71e38` while
the compiled tree is `a4cc8f5` and the reviewed tip is `6213a48`. At
`2e71e38`, the EA blob/version/macro are different. A runtime journal row
containing only `2e71e38` cannot identify the compiled bytes. Notebook 00
similarly retains `git_commit=4683afb...` despite later source/output changes.
If these are intended as logical-parent tags, the fields and comments must say
that; otherwise generate an exact build/source identifier.

TASK-028 also still describes `news_state` as always empty, only 4/20
candlesticks as ported, chart patterns as unported, and no pattern exporter as
existing at 431-448 and 507-532. Current source has populated news state, the
full candlestick set, chart-pattern implementations, and
`Export_PatternDetectorResults.mq5`. These are headed/presented as current
state and contradict the later history at 1069-1072.

## Verification results that passed

- Git range `79da9c9..6213a48`: 27 commits, 67 paths, 8,338 insertions, 1,201
  deletions; `git diff --check` is clean.
- The retained round-9 artifact contains exactly 46 target headings, 46 source
  hashes, and 46 `0 errors, 0 warnings` results. All hashes match the files at
  `a4cc8f5`; no MQL5 source changed between `a4cc8f5` and `6213a48`.
- Python: 749 tests passed; focused regressions passed; Ruff check and format,
  whole-project mypy (50 source files), and `pip check` are clean.
- All 11 notebooks execute successfully in a fresh disposable run. Fresh
  notebook 03/04/06 output objects match the committed outputs; this does not
  cure notebook 09's false in-place-execution claim.
- Both immutable baseline directories, including each `IDENTITY.md`, are
  byte-identical to `baseline-v637` and `baseline-v811`. No commit in the
  reviewed range touches `01_BASELINE/`.
- The baseline trees are:
  - V6.37: `fe46191174b150c4c1e0dceb1bffc6c42a076384`
  - V8.11: `3bc9e68939873de57c70319ff75f3b39ffd58c75`

## Final disposition

**CHANGES REQUESTED.** Do not merge TASK-028 as complete and do not begin a
demo trial with order submission enabled. Repair P0 findings 1-7 first, add
retained MQL runtime/restart/concurrency/failure evidence, then resolve the P1
correctness and validation findings and reconcile canonical history before
requesting another independent review.
