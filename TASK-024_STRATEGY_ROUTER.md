# TASK-024 — StrategyRouter, SignalScorer, ConflictResolver: begins Phase 6

## Objective

Implement `SignalScorer.mqh`, `StrategyRouter.mqh`, and
`ConflictResolver.mqh` per `TASK-002_PHASE2_SPECIFICATION.md` section 3:
the unified candidate representation every one of the five strategy
modules (TASK-019–023) converts into, the regime × family eligibility
multiplier matrix, and the final cross-direction tie-break. This is the
first task where the entire system — every detection engine and every
strategy module — compiles and composes together as one unit.

## Reason

Section 3 explicitly separates two responsibilities that TASK-002's own
round-3 review found conflated in an earlier draft:
`StrategyRouter` owns eligibility/scoring only; `ConflictResolver` owns
only the final tie-break. This task implements that separation as two
distinct files with genuinely non-overlapping responsibilities, closing
the last major architectural piece before an actual `EAController` can
exist.

## Baseline behaviour

Not applicable — new-engine architecture, not a port. No file under
`01_BASELINE/` is touched.

## Evidence

`TASK-002_PHASE2_SPECIFICATION.md` section 3 in full (the eligibility
matrix, the `StrategyRouter`/`ConflictResolver` split, the conflict-gap
rule) and section 9 (the base-score formula this task partially
implements).

## Specification

`STradeCandidate` (`SignalScorer.mqh`) is the unified shape every
strategy signal converts into via a dedicated adapter function
(`SS_FromSRBounce`, `SS_FromSMC`, `SS_FromChartPattern`,
`SS_FromTrendFollowing`, `SS_FromPostExpansionRetest`) — pure structural
conversion, no scoring or eligibility logic in the adapters themselves.
`SS_ComputeBaseScore` implements section 9's expected-reward-to-risk and
regime-confidence components (equally weighted, scaled to `[0,100]`) —
**the other three section-9 components (location/pattern quality,
sample-gated historical performance) are explicitly deferred**, stated
in the module's own header comment, since neither exists as a
standalone reusable value yet. `SR_GetEligibilityMultiplier`
(`StrategyRouter.mqh`) implements section 3's regime × family matrix
exactly, cell-by-cell traceable to specific routing-table language via
inline comments. `STR_RouteCandidates` applies that multiplier and the
base score to every candidate, writing an eligible-or-not, fully-scored
list — never picking a winner. `CR_ResolveConflicts`
(`ConflictResolver.mqh`) is the **only** place a single winning direction
is chosen: highest score wins within a direction; between opposing
directions, `No trade` wins unless the score gap meets
`conflict_score_gap` (default 10).

**Stated simplification:** section 3's exact-score-tie rule (smaller
entry timeframe, then alphabetical family) is not implemented — no
candidate carries its own entry timeframe yet, and this is flagged
explicitly in the module header rather than silently omitted.

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Routing/SignalScorer.mqh`,
`StrategyRouter.mqh`, `ConflictResolver.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_StrategyRouter.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

The exact-tie rule (see Specification). The remaining three section-9
score components. Wiring this into an actual `OnTick`/`EAController`
entry point — this task produces the decision-making core, not the
running EA. Position sizing, order submission, journal writing — later
tasks consuming `CR_ResolveConflicts`'s output.

## Risks

- No independent review available this phase.
- Runtime verification: every hand-fabricated test case (base score,
  adapters, eligibility matrix, end-to-end routing, all four conflict-
  resolution branches) is deterministic; there is no live-symbol wrapper
  for this task specifically (routing composes already-evaluated
  candidates — the live-data dependency lives entirely in the five
  strategy modules' own wrappers, already batched).
- **The base score's honest two-of-five-component scope** is the most
  important thing to keep in mind going forward — a future task adding
  the remaining three components will change every candidate's score,
  and anything built on top of today's scores (if anything is, before
  that happens) should expect that.
- The eligibility matrix's `default: return 0.0` branch (gating regimes)
  was not given its own named `case` for each of the three gating
  regimes individually — relies on the `switch` statement's default
  branch catching `TRANSITION_OR_UNCERTAIN`/`NEWS_BLACKOUT`/
  `UNTRADEABLE_SPREAD_OR_LIQUIDITY` together, which is correct (they all
  block everything identically) but worth a second look to confirm no
  regime enum value accidentally falls through unintentionally.

## Test plan

1. **Compile test** (completed, see Compiler result — clean on the
   first attempt, the largest single-compilation-unit composition in the
   project so far, transitively including all five strategy modules and
   every detection engine).
2. **Logic test — fully hand-verifiable**: the base-score formula at an
   exact hand-computed value plus a zero-risk failure case; two adapter
   functions (SR Bounce, SMC) checked field-by-field, plus a not-found
   passthrough case; six eligibility-matrix cells spanning prefer/block
   across every regime category; an end-to-end `STR_RouteCandidates` run
   with one eligible and one blocked candidate, exact final score
   verified; and all four `CR_ResolveConflicts` branches (single-
   direction winner, opposing-directions gap met, opposing-directions
   gap not met, no eligible candidates).

## Acceptance criteria

- [x] `StrategyRouter` and `ConflictResolver` have genuinely
      non-overlapping responsibilities (verified by inspection — routing
      never compares across directions; conflict resolution never
      recomputes eligibility or score).
- [x] The eligibility matrix matches section 3's routing table
      cell-by-cell (verified by six representative test cases spanning
      every regime category).
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      — the largest composition test in the project, clean on the first
      attempt.
- [x] The base-score's deferred components are stated explicitly, not
      silently approximated.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if any hand-verifiable test produces `FAIL` — especially a
conflict-resolution branch producing the wrong outcome, since that is
the final decision point every trade this system ever makes will pass
through.

## Implementation notes

This is the first task in the project where a single compiled unit pulls
in every detection engine (TASK-011–018) and every strategy module
(TASK-019–023) simultaneously — its clean first-attempt compile is real,
if indirect, evidence that the "one implementation per concept, composed
by consumers" discipline held consistently since TASK-011 actually paid
off: no naming collision, no circular include, no signature mismatch
across eighteen prior tasks' worth of modules being pulled together at
once.

## Commands run

```
git checkout -b claude/task-024-strategy-router
mkdir -p 03_SOURCE_CODE/MQL5/Include/ThembaEA/Routing
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_StrategyRouter.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 683 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt, transitively including
every module from TASK-005 through TASK-023. Full log available in this
session's history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: fully
hand-verified** — every test in this task's script is a pure logic test
over caller-constructed data (no live-symbol dependency at this layer),
so there is no separate "batched runtime gap" item for this specific
task the way every strategy/detection module has had.

## Commit

Pending — see `git log` on `claude/task-024-strategy-router`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed.** Phase 6's core decision-making
pipeline (score → route → resolve) is complete and tested. What remains
before an actual running EA exists: wiring this into a real `OnTick`
loop (`EAController.mqh`, not yet built), position sizing off
`CR_ResolveConflicts`'s winning candidate (via `RiskManager.mqh`,
already built in TASK-007), and order submission (`OrderManager.mqh`,
not yet built) — Phase 6/7 remaining work.
