# TASK-006 — SessionManager: session-time-remaining and boundary clock

## Objective

Implement `SessionManager.mqh` per `00_MASTER_PROMPT_FOR_CLAUDE.md`
section 23 (Phase 3, "Session manager"): the session-time-remaining
input `TASK-002_PHASE2_SPECIFICATION.md` section 1's mode router
consumes, and the daily/weekly/intraday boundary-clock functions section
8's risk module depends on — all defined against the trade server's own
clock only, per section 8's explicit fix for mixed metals/synthetics
account calendars.

## Reason

Both the mode router (section 1) and the risk-cap reset logic (section 8)
need a correct, single-clock boundary definition; getting the Monday-
00:05 weekly-boundary arithmetic and the completed-session-minutes
fraction right now, with independent tests, is safer than re-deriving
this logic ad hoc inside a later, larger `RiskManager` task.

## Baseline behaviour

Neither baseline has a symbol-agnostic, server-clock-only boundary
concept — V8.11's daily reset (`ResetDailyState`) has the confirmed
anchor-mismatch defect this module's stateless design is built to avoid
(see TASK-003's rationale: persistence of the *last-processed* boundary
stays in `StateManager`, not duplicated here). No file under
`01_BASELINE/` is touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 1 item 4 (session time
remaining) and section 8 ("Reset boundary — single clock" / "Intraday
boundary, fully defined").

## Specification

- `SN_CurrentDailyBoundary()` — server-local midnight of the current day.
- `SN_DailyBoundaryCrossed(last_reset)` — true iff the current day's
  boundary is strictly after `last_reset` (the "first tick after the
  boundary passed" rule — no exact-timestamp tick required).
- `SN_CurrentWeeklyBoundary()` — the most recent Monday 00:05 server time
  at or before now.
- `SN_WeeklyBoundaryCrossed(last_reset)` — weekly analogue of the above.
- `SN_IsPastIntradayBoundary(hour=23, minute=45)` — true iff current
  server time-of-day is at or past the given boundary.
- `SN_GetSessionMinutesRemaining(symbol, &ratio)` — fraction of today's
  trading session(s) remaining, `[0,1]`; returns false (undefined,
  caller excludes the component per section 1's missing-data rule) if
  the symbol has no session today. **Interpretation choice, stated
  explicitly since section 1 does not fully pin down multi-session/
  gapped-day behavior:** "remaining" is measured against today's *last*
  session's end, not net trading time excluding any intraday gap — see
  the in-file comment for the reasoning (a Day-trade position can still
  be held across a gap into a later session before the intraday-close
  rule actually forces an exit).

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/SessionManager.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_SessionManager.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

Persistence of the last-processed boundary (that is `StateManager`'s job,
consumed by a later `RiskManager`/`DailyWeeklyLimits` task — see
Implementation notes for why this module stays stateless). The mode
router itself (section 1's full weighted-average formula) — a later
task. `RiskManager`, `DecisionJournal`, `IntradayCloseManager` — the rest
of Phase 3.

## Risks

- No independent review available this phase.
- Runtime verification: same confirmed, recurring environment limitation
  documented in TASK-005 — batched, not re-attempted per task.
- **The multi-session "remaining" interpretation is a stated judgment
  call**, not something section 1 fully specifies — flagged explicitly
  above and in the source comment rather than presented as the only
  possible reading, so a future reviewer or the strategy-calibration
  phase can revisit it if it turns out wrong for a specific broker's
  session structure (e.g., an unusual multi-session synthetic-index
  schedule).
- `SymbolInfoSessionTrade`'s `from`/`to` are treated as seconds-since-
  midnight offsets added onto today's server midnight — this is the
  standard, documented MQL5 interpretation, not independently re-derived
  here.

## Test plan

1. **Compile test** (completed, see Compiler result).
2. **Logic test** (compiled, not yet runtime-confirmed — batched per
   TASK-005's decision): `Test_SessionManager.mq5` must print all-PASS
   covering: daily boundary structural correctness (hour/min/sec all
   zero, not after now) and crossed/not-crossed behavior; weekly boundary
   structural correctness (falls on a Monday, `00:05:00`, not after now)
   and crossed/not-crossed behavior; intraday-boundary correctness
   verified by **independently recomputing** the expected true/false
   value from the current server time in the test script itself (not
   hardcoding an assumption about what time it is when run) for both the
   default `23:45` and an explicit `(23,45)` call, plus a same-minute
   boundary always being "past"; and session-minutes-remaining producing
   a value in `[0,1]` whenever the symbol reports a session today.

## Acceptance criteria

- [x] `SessionManager.mqh` implements every function specified above.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (three `datetime`/`long` conversion warnings were found and fixed
      during this pass — see Implementation notes).
- [ ] Logic test confirmed all-PASS on a real desktop MT5 session — batched
      with TASK-003/004/005's outstanding item.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if the logic test, once run, produces any `FAIL` — particularly
the weekly-boundary structural checks, since a wrong day-of-week/time
there would silently misalign every account-wide risk reset built on top
of it later.

## Implementation notes

The compiler flagged three `warning 43: possible loss of data due to
type conversion from 'long' to 'datetime'` on the first compile attempt
— `datetime` arithmetic in MQL5 (`datetime ± long`) can produce an
implicit `long` result at certain expression shapes, which the compiler
flags when assigned back to a `datetime`-typed variable. Fixed with
explicit `(datetime)(...)` casts around the full arithmetic expression at
each of the three sites, rather than suppressing or ignoring the
warning — this project's discipline is "0 errors, 0 warnings" as real,
checked evidence, not "0 errors" alone.

This module is deliberately stateless (see header comment) — it computes
"what is the current boundary" and "has a given prior boundary been
crossed," but does not itself remember the last-processed boundary across
restarts. That remembering is `StateManager`'s job; keeping the two
concerns separate means this module has zero dependency on TASK-003 and
can be fully tested in isolation, matching master-prompt section 22's
"clear responsibility and test boundary" rule.

## Commands run

```
git checkout -b claude/task-006-session-manager
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_SessionManager.mq5" /log:...
```

## Compiler result

**Real, verified.** First attempt: `Result: 0 errors, 3 warnings` (the
`datetime`/`long` conversion warnings above). Second attempt, after the
explicit-cast fix: `Result: 0 errors, 0 warnings, 464 ms elapsed,
cpu='X64 Regular'`. Full logs available in this session's history; not
committed (build artifacts).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not
confirmed** — batched with TASK-003/004/005's outstanding runtime-
verification item (see Risks).

## Commit

Pending — see `git log` on `claude/task-006-session-manager`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean (0 errors, 0 warnings) and committed; logic-test runtime
confirmation batched with TASK-003 through 005's outstanding item.**
