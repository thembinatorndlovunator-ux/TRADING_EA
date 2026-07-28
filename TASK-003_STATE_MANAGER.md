# TASK-003 — StateManager: account-wide scalar persistence

## Objective

Implement the first Phase 3 ("Common core") module per
`00_MASTER_PROMPT_FOR_CLAUDE.md` section 23: `StateManager`, scoped in
this task to the **account-wide namespace only** (account_login +
trade_server), per `TASK-002_PHASE2_SPECIFICATION.md` section 8's
two-namespace schema. This is the persistence substrate that
`RiskManager`, `DrawdownController`, `EquityPeakManager`, and
`DailyWeeklyLimits` will all build on in later Phase 3 tasks — it directly
targets V8.11's confirmed daily-limit anchor/reset restart defect
(`baseline_v811_audit.md`) and V8.11's truncated, unscoped peak-drawdown
persistence key.

## Reason

Per `CLAUDE.md`'s workflow, Phase 3 implementation begins now that
TASK-002's specification is complete (self-certified after round 3;
Codex's independent-review budget for this project phase is exhausted per
the user's explicit instruction). `CLAUDE.md`'s workflow requires one
bounded task per branch — this task is deliberately scoped to the
smallest genuinely independent, fully-specified, dependency-free unit:
the generic account-wide scalar store and its concurrency/schema-
versioning guarantees, without yet wiring in any risk-specific field
(daily/weekly baseline, peak equity). Those fields are a later task that
consumes this module's API.

## Baseline behaviour

V8.11's persisted peak-drawdown key truncates a `long` magic number and
carries no account/server identifier (`baseline_v811_audit.md`); its daily
reset (`ResetDailyState`, source 1529–1564) has a documented
numerator/denominator anchor mismatch across restarts and no weekly
counterpart at all. V6.37 has no comparable persisted risk-baseline
mechanism. Neither baseline is touched by this task — no file under
`01_BASELINE/` is modified.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 8 ("Persistence and restart —
namespaces assigned explicitly") and section 11 (`StateManager`'s stated
test boundary: "given a persisted state snapshot and a simulated restart,
every dependent module reads back the exact pre-restart values for its
own namespace, and a schema-version mismatch triggers a full reset with a
logged event" — corrected in that same document to a **targeted**
migration, never a blanket reset, which this implementation follows).

## Specification

Implemented exactly as specified in `TASK-002_PHASE2_SPECIFICATION.md`
section 8:

- **Namespace:** `account_login + trade_server` (via
  `AccountInfoInteger(ACCOUNT_LOGIN)` / `AccountInfoString(ACCOUNT_SERVER)`),
  deliberately unpartitioned by symbol/magic.
- **Storage:** native MQL5 global variables (`GlobalVariableSet`/
  `GlobalVariableGet`), which are double-only and persist across terminal
  restarts — the "small scalar" storage mechanism the specification
  calls for.
- **Concurrency:** a compare-and-set lock built on
  `GlobalVariableSetOnCondition`, with a stale-lock-breaking rule
  (`SM_LOCK_STALE_SECONDS = 30`) so a crashed holder can never
  permanently wedge the lock for other instances.
- **Schema versioning:** every account-wide record set carries a
  `schema_version` field; `SM_EnsureAccountSchema()` performs a
  **targeted, additive-only** migration on version mismatch — it may add
  new fields with neutral defaults but must never reset or delete an
  existing field, per the specification's explicit correction of the
  "full reset" language the master prompt's naive test-boundary phrasing
  could otherwise be read as.

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Core/StateManager.mqh`;
`03_SOURCE_CODE/MQL5/Scripts/Test_StateManager.mq5`; this task file;
`09_HANDOVERS/claude_to_codex/TASK-003_handover.md` (once written).
Modified: `TASKS.md` (task-ledger row added). No file under
`01_BASELINE/` or the TASK-001/TASK-002 documents is touched.

## Out of scope

- Per-instance (symbol+magic+account+server) structured/file-based
  storage — a separate, later task, per section 8's second namespace.
- Any risk-specific field (daily/weekly equity baseline, peak equity,
  cash-flow rebasing) — those belong to `RiskManager`/`DailyWeeklyLimits`/
  `EquityPeakManager`, which will call this module's generic API in a
  later task.
- `MarketData.mqh`, `SymbolProfile.mqh`, `SessionManager.mqh`,
  `BrokerValidator.mqh`, `DecisionJournal.mqh`, `IntradayCloseManager.mqh`
  — the rest of Phase 3's "Common core" list, each a separate bounded
  task.
- Any live trading logic. This module performs no order operations.

## Risks

- **No independent review is available for this task's code** (Codex's
  budget for this project phase is exhausted per the user's instruction).
  Verification here is limited to real MetaEditor compilation and the
  author's own hand-tracing of the lock/migration logic — a weaker
  guarantee than an independent reviewer's check, stated plainly rather
  than implied otherwise.
- **Runtime (logic) test execution could not be completed in this
  session's environment** — see Test results below. The script compiled
  and loaded on a live Deriv-Demo account (`41102878`) but its `OnStart`
  did not appear to execute (no growth in the terminal's journal log, no
  update to `bases\gvariables.dat`, in the ~30 seconds after "loaded
  successfully" was logged), consistent with this sandboxed session
  lacking the display/window context MT5 needs to instantiate a chart and
  run a script interactively. This is a session-environment limitation,
  not a claim that the code is untested by design — it needs manual
  confirmation on a real desktop session (see Test plan item 2).
- **`GlobalVariableSetOnCondition`'s exact atomicity guarantee** is
  documented MT5 platform behavior, not independently re-derived here;
  if it does not hold as documented, the lock's mutual-exclusion property
  would be weaker than stated. This is a reasonable platform-API trust
  boundary, not a gap in this module's own logic.

## Test plan

1. **Compile test** (completed, see Compiler result): `Test_StateManager.mq5`
   includes `StateManager.mqh` and must compile with 0 errors via
   MetaEditor.
2. **Logic test** (compiled, not yet runtime-confirmed — see Risks):
   `Test_StateManager.mq5`, run manually (drag onto any chart in a real
   desktop MT5 session, or run via Scripts in the Navigator), must print
   all `PASS` lines and 0 `FAIL` lines covering: round-trip set/get,
   default-value-on-unset, overwrite, two-field non-collision, lock
   mutual exclusion (a second acquire attempt while held must time out),
   lock release-then-reacquire, first-run schema stamping, and
   idempotent/non-destructive re-`Ensure` behavior. The script cleans up
   every test field it creates, leaving no residue in the account-wide
   namespace on a real account.
3. **Restart persistence** (not yet tested — requires an actual terminal
   restart, deferred to the task that adds a risk-specific field, where
   the consequence of failure is concrete and worth the manual test
   cycle).

## Acceptance criteria

- [x] `StateManager.mqh` implements the account-wide namespace, lock, and
      schema-versioning exactly as specified in
      `TASK-002_PHASE2_SPECIFICATION.md` section 8.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (see Compiler result).
- [ ] Logic test script confirmed to print all-PASS on a real desktop MT5
      session — **not yet confirmed; see Risks.**
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — **not available this phase; see Risks.**

## Rejection criteria

This task would be rejected if the logic test, once actually run on a
real desktop session, produces any `FAIL` line, or if manual code review
finds the lock does not actually exclude a concurrent second writer, or
if a schema migration is found to delete or reset an existing field
(violating the specification's explicit "never blanket-reset" rule).

## Implementation notes

`SM_AcquireAccountLock`'s `while(true)` loop required an explicit trailing
`return false;` after the loop body — MQL5's compiler does not perform the
flow analysis needed to prove that a `while(true)` loop whose only exits
are `return` statements always returns, and rejects the function with
error 117 ("not all control paths return a value") without it. This is
now the only unreachable line in the file and is commented as such.

Source and test files were made visible to a real MT5 terminal (Deriv MT5
Terminal, data folder hash `C734FF1CA4CACD5026FF92845253E847`) via
directory junctions (`MQL5\Include\ThembaEA` and `MQL5\Scripts\ThembaEA`
both point at this repo's `03_SOURCE_CODE/MQL5/...` folders) rather than
copying files — edits in the repo are what the terminal compiles and
loads, with no separate copy to keep in sync. These junctions are local
machine state, not part of the repository.

## Commands run

```
git checkout claude/task-002-phase2-specification
git pull origin claude/task-002-phase2-specification --ff-only
git checkout -b claude/task-003-state-manager
mkdir -p 03_SOURCE_CODE/MQL5/Include/ThembaEA/Core 03_SOURCE_CODE/MQL5/Scripts
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_StateManager.mq5" /log:"...\compile_log.txt"
```
Plus, via PowerShell: creation of the two directory junctions above, and a
terminal launch with a `[StartUp]` config (`Script=ThembaEA\Test_StateManager`,
`Symbol=EURUSD`, `Period=M1`) to attempt runtime verification (result: see
Risks/Test results — module loaded, `OnStart` execution unconfirmed).

## Compiler result

**Real, verified.** First attempt: `error 117: '}' - not all control paths
return a value` at `StateManager.mqh` line 99 (inside
`SM_AcquireAccountLock`). Fixed by adding an explicit trailing
`return false;`. Second attempt: `Result: 0 errors, 0 warnings, 1317 ms
elapsed, cpu='X64 Regular'` — full MetaEditor log available in this
session's history; not committed to the repo (a build artifact, not
source).

## Test results

**Compile test: PASS (real evidence, above).**

**Logic test: not confirmed.** `Test_StateManager.mq5` was launched
against a live Deriv-Demo account (`41102878`, server `Deriv-Demo`) via a
`terminal64.exe /config:...` startup script. The terminal's journal
logged `script Test_StateManager (EURUSD,M1) loaded successfully`, but no
further log lines appeared and `bases\gvariables.dat`'s modification
timestamp did not change in the ~30 seconds that followed — meaning
`OnStart` most likely never actually executed in this session (no visible
desktop/window context for MT5 to host a chart). **This is not a claim
that the logic test passed** — it is an honest record that the runtime
check could not be completed in this environment and needs to be run
manually on a real desktop MT5 session (drag `Test_StateManager` from the
Navigator onto any chart) before this module is trusted at runtime, not
only at compile time.

## Commit

Pending — see `git log` on `claude/task-003-state-manager` for the actual
hash (avoids the self-referential staleness problem noted in
`TASK-002_PHASE2_SPECIFICATION.md`'s own Commit section).

## Reviewer

Not available this phase — Codex's independent-review budget is
exhausted per the user's explicit instruction. This task's disposition is
therefore self-certified against real compilation evidence, with the
logic-test gap stated plainly above rather than implied resolved.

## Final decision

**Compiled and committed; logic-test runtime confirmation outstanding.**
Recommended before this module is relied upon by a later task: the user
(or a session with real desktop access) runs `Test_StateManager` manually
once and confirms all-PASS output, per Test plan item 2.
