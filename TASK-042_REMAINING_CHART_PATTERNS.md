# TASK-042 — Remaining chart-pattern families (trendline-slope-fitting)

**Registered 2026-07-22 (Codex review finding, seventh round, P2 finding
20):** TASK-039's own status previously named this remaining work as
"a future task must pick it up" without a concrete task number — an
unnamed-owner gap the review flagged as recreating the same ownership
problem earlier rounds already found and closed once for the chart-pattern
backlog generally (TASK-039 itself exists for exactly that reason). This
task file closes that gap by giving the remaining work a real number.

## Scope

The 11 master-prompt-listed chart-pattern families `ChartPatternEngine.mqh`
and `pattern_validation.py` do not yet implement, per
`TASK-039_CHART_PATTERN_COMPLETION.md`'s own corrected count (17 total
families; 4 built by TASK-033; 2 built by TASK-039 — triple top/bottom;
11 remain):

- Ascending triangle
- Descending triangle
- Symmetrical triangle
- Rectangle / consolidation box
- Bull flag
- Bear flag
- Pennant
- Rising wedge
- Falling wedge
- Parallel channel
- Cup-and-handle (behind its own disabled-by-default flag, per the master
  prompt's own requirement for this specific pattern)

Each of these needs genuine trendline-slope-fitting design work — none is
a direct extension of the existing swing-pivot-based double/triple
top/bottom or head-and-shoulders logic (which locate discrete confirmed
swing points and compare/interpolate between them). A trendline-based
pattern instead needs a best-fit (or tolerance-banded) line across several
points, a decision this project has not yet made or specified.

## Explicitly out of scope

- Wiring any of these patterns into live trading decisions
  (`ChartPatternStrategy.mqh`) — a separate, later task once the
  detectors themselves exist and are validated.
- A real MQL5-export cross-check — owned by `TASK-037`, once
  `Export_PatternDetectorResults.mq5` (or a successor) exports whatever
  columns this task's own Python port ends up needing.

## Status

Not started — registered as a concrete numbered follow-up, 2026-07-22, per
Codex review finding (seventh round, P2 finding 20). No design work,
implementation, or scope decision (e.g. the trendline-fitting tolerance
convention) has been made yet.
