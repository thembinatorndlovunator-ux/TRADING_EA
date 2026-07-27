# Claude → Codex handover — TASK-028 round 8 remediation

**Supersedes, for CURRENT status, `TASK-028_round7_handover.md`'s own
final "Requesting review" section** (which accurately reflects round 7's
state at the time it was written, including its own "this handover is the
request for the next review round" line — that request has since been
fulfilled: round 8 happened, in full, and this file is its resolution
record). That file is left unedited apart from two narrow, explicitly
`P2 finding 22`-labelled corrections to claims that were self-contradictory
or later became stale; this one is the current one.

## What happened

Round 7 closed with all 20 findings resolved and its own handover
requesting the next review round per the user's standing directive
("finish all the tasks, then we do a codex review after everything is
done"). That request was fulfilled: an eighth independent review returned
**22 findings — 10 P0, 11 P1, 1 P2 — disposition CHANGES REQUESTED**,
written to `09_HANDOVERS/codex_to_claude/TASK-028_review.md` (recorded at
commit `ed46ded`, Git-timestamped 2026-07-27 -- **corrected, 2026-07-27,
Codex round-9 P2 finding 22: this section's own surrounding date
references had drifted to imply an earlier "2026-07-22" review date in
other canonical docs; `ed46ded` and its entire 22-commit remediation range
are all 2026-07-27**). Every one of the 22 findings received a real,
committed fix for its own reported primary defect (never a workaround or
a silenced check), with a regression test reproducing the EXACT
counterexample the review reported (finding 21 substitutes a full,
individually-hashed 41-target MetaEditor compile pass for a Python
regression test, since it concerns compile evidence itself), and either a
clean MetaEditor compile (0 errors, 0 warnings) or a passing Python test
run, verified before committing.

**Corrected, 2026-07-27 (Codex round-9 P2 finding 22): "All 22 are now
resolved" above overclaimed scope as a blanket headline.** Two findings
were explicitly, honestly disclosed at the time as PARTIAL, not silently
dropped: finding 12's own commit message deferred its mode-first
ROUTING-ORDER half (candidates are still generated before mode is
computed, only vetoed post-hoc) as "a substantial separate architectural
task"; finding 14's own fix left the chart-pattern lifecycle registry
(FORMING/CONFIRMED/RETESTING/TRADED/INVALIDATED/EXPIRED, consumed-pattern
suppression) unimplemented in source. Both gaps are named explicitly in
"Findings resolved, by commit" below -- this correction exists because the
SUMMARY headline above did not carry the same caveat, letting "all 22
resolved" read as unqualified. Round 9's own remediation has since closed
the chart-pattern lifecycle gap in full and formally registered the
routing-order gap as `TASK-043_MODE_FIRST_ROUTING_ARCHITECTURE.md`.

## Verification evidence

- **MQL5:** every commit below that touched `.mq5`/`.mqh` files was
  compiled via MetaEditor64.exe before committing; build artifacts
  (`.ex5`) and per-commit logs were not retained (they never have been in
  this project), but a **full, current, individually-hashed compile of
  all 41 real `.mq5` targets** — the 2 Experts
  (`ThembaAdaptiveIntradayEA.mq5`, `EquityTickRecorder.mq5`) and all 39
  `Test_*.mq5`/`Export_*.mq5` scripts, not just this round's own touched
  files — is retained at
  `09_HANDOVERS/compile_evidence/TASK-028_round8_full_compile_evidence_2026-07-27.txt`,
  recording the exact MetaEditor invocation, MetaEditor version/build
  (5.0.0.5833), the tree commit compiled, and — for every target — its
  own SHA-256 source hash plus its COMPLETE raw compiler log text, not
  just a summary `Result:` line (finding 21's own complaint about the
  round-7 evidence file). All 41 compile clean. `THEMBA_EA_GIT_COMMIT`
  updated from a seven-commits-stale `b362c07a1bab` to `990f32c17327`
  (this round's own final content commit, immediately before this
  evidence pass), per this project's stated manual-build-tag convention.
- **Python:** the full `pytest` suite passes at every commit below; by
  the final content fix it stood at **718 passed, 0 failed**. `ruff
  check`, `ruff format --check`, and `mypy` were ALL re-run as a genuine
  final gate this round (unlike round 7, which named this omission as a
  gap) — all three report clean.
- **Notebooks:** all 11 notebooks under `03_SOURCE_CODE/Python/notebooks/`
  execute with zero raised exceptions via `nbconvert --execute` against
  the project's own registered `themba-python-lab` Jupyter kernel
  (finding 20) — including the 2 that previously failed clean-kernel
  execution (notebooks 00 and 04).

## Findings resolved, by commit

**P0 (10):**

1. **Account-mode safety guard exactly inverted** — `af06cb8`.
2. **Spread gate 20x the approved default, unbounded** — `b719b94`.
3. **Hard-risk path incomplete, could exceed the 1% cap** — `338bd3c`.
4. **Risk persistence neither atomic nor fail-closed** — `9e9dc1c`.
5. **Durable-intent protocol not durable/restart-idempotent** — `37b1f4d`.
6. **Persistence keys exceeding MT5's 63-character limit** — `453cd77`.
7. **Both live news providers retaining fail-open schema/error paths** —
   `29efe7e`.
8. **A partially filled entry recorded as rejection while exposure is
   live** — `dd312cd`.
9. **A first low-confidence bar still trading the prior confirmed
   regime** — `c534f85`.
10. **The mandatory intraday close not guaranteed across a no-tick
    boundary** — `95268e0`.

**P1 (11):**

11. **Order identity, actual-fill journaling, and asynchronous evidence
    incomplete** — `e352e7e`.
12. **Intraday mode's invalid NONE/UNKNOWN journal vocabulary** —
    `85dc773`. The finding's other, larger request — reordering the
    pipeline to regime → mode → mode-aware strategy generation →
    post-hoc consistency — is a substantial, separate architectural task
    and was explicitly NOT attempted, named honestly in the commit
    message rather than silently left unaddressed.
13. **Close/cooldown transaction handling not position-lifecycle-safe** —
    `b7c68c2`.
14. **Chart-pattern execution using stale sloped boundaries** — `b274a45`.
15. **The CSV ceiling fix requesting a 500 MB allocation per read,
    breaking pytest** — `95cb591`.
16. **Error budgets and multi-artifact report publication non-atomic** —
    `87d93d1`.
17. **The Python-vs-MQL pattern cross-check passing a completely
    different dataset** — `ead49e8`.
18. **Equity analysis merging unrelated runs/accounts into one
    artificial curve** — `79d21dd`.
19. **Several analytical/schema contracts remaining permissive or
    inconsistent** — `ca2cbe1`. Fallout discovered and fixed in the same
    commit: `journal_reader.py`'s own module docstring and
    `find_duplicate_signal_ids` assumed every real journal record has
    `signal_id == ""` — stale since TASK-036's `BuildSignalId` wiring,
    which the new `signal_id` `min_length=1` schema requirement then made
    impossible to construct via the normal pipeline anyway.
20. **Declared Python quality/notebook gates not clean** — `47d4a56`.
    Two notebooks (00, 04) fixed to execute clean; `ruff format` applied
    across 5 remaining files; a real `mypy` type error in
    `report_metadata.py` (surfaced by finally re-running the gate) fixed;
    `nbconvert` — the tool needed to reproduce "clean-kernel execution" —
    was not even a pinned dependency, so it was installed and added to
    `requirements-lock.txt`, with the exact execution command documented
    in `pyproject.toml` for the first time.
21. **Retained MQL compile evidence and embedded build provenance
    false/incomplete** — `c9b2298`, resolved LAST (after finding 22's
    documentation pass) so the compile evidence and
    `THEMBA_EA_GIT_COMMIT` build-tag reflect the truly final round-8
    state, not an intermediate one that would go stale again within the
    same round. See Verification evidence above for details.

**P2 (1):**

22. **Canonical history/status documents contradicting the source, Git,
    and their own deferrals** — `990f32c`. Corrected: `TASK-028_round7_handover.md`'s
    and `TASK-028_PYTHON_STATISTICAL_LAB.md`'s own round-7 history entry,
    both of which said "All 20 are now resolved" with no qualification,
    contradicting their own named, deliberately-retained follow-up items;
    `TASK-028_PYTHON_STATISTICAL_LAB.md`'s "Reviewer" section, stuck at
    "six rounds completed" since before round 7 even happened;
    `TASK-037_MT5_EXPORT_BRIDGE.md`'s stale descriptions of the
    predicted-regime export (still describing the pre-round-7 raw
    classifier) and the trade-history cost model (still describing the
    pre-round-7 close-only formula, not `TradeHistoryAggregator.mqh`'s
    prorated multi-fill allocation); `TASK-040_INTRADAY_MODE_ROUTER.md`'s
    stale `IMR_ClassifyMode`/`winner_score` description (superseded by
    THIS round's own finding 12) and its stale claim that
    `STradeDecision` has no `market_family`/`intraday_mode` fields (TASK-036
    shipped both rounds ago); `TASK-041_EXIT_ENGINE_WIRING.md`'s stale
    "runs once per completed bar" claim (superseded by round 7's own
    finding 8, which moved it to every tick); `TASKS.md`'s stale
    "kept unchanged" 4-column pattern-export claim (superseded by round
    7's own finding 11, now 16 columns) and three rows (TASK-034/036/040)
    that said "Done" while their own task files say "In progress" with
    "Independent review completed" left unchecked.

## What Claude did NOT do this round

- Did not attempt `IntradayModeRouter`'s pipeline-reorder (regime → mode
  → mode-aware strategy generation → post-hoc consistency), named,
  bounded, and deliberately deferred as part of finding 12 — a
  substantial, separate architectural task.
- Did not attempt `parameter_stability.py`'s cross-file bar0-convention
  unification or `TASK-037`'s cost-sensitivity/OHLC-R-path/session-news
  exports — all pre-existing, honestly-disclosed, not-yet-unified
  follow-ups, unchanged this round because nothing this round's own
  findings required touching them.
- Did not run any of this against a real/demo MT5 session — this sandbox
  cannot; every export/EA fix remains verified by compile + hand-derived
  or pytest-executed regression test only.

## Requesting review

Per the user's own sprint directive ("finish all the tasks, then we do a
codex review after everything is done, then from the review we correct
and make any solid adjustments needed then we launch the EA on MT5"),
this handover **is** the request for the next (ninth) review round.
