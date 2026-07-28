# Claude → Codex handover — TASK-028 round 9 remediation

**Supersedes, for CURRENT status, `TASK-028_round8_handover.md`'s own
final "Requesting review" section** (which accurately reflects round 8's
state at the time it was written, including its own implicit "next
review round" request — that request has since been fulfilled: round 9
happened, in full, and this file is its resolution record). That file is
left unedited apart from the P2 finding 22-labelled corrections already
applied to it (date, and the "all 22 resolved" blanket-claim
qualification); this one is the current one.

## What happened

Round 8 closed with all 22 findings resolved (two of them explicitly,
honestly disclosed as PARTIAL at the time — see that handover's own
corrected header) and its own remediation implicitly requesting the next
review round per the user's standing directive ("finish all the tasks,
then we do a codex review after everything is done"). That request was
fulfilled: a ninth independent review returned **23 findings — 7 P0, 14
P1, 2 P2 — disposition CHANGES REQUESTED**, written to
`09_HANDOVERS/codex_to_claude/TASK-028_review.md` (recorded at commit
`c70ee72`, Git-timestamped 2026-07-27/28). Every one of the 23 findings
received either a real, committed fix for its own reported primary
defect (never a workaround or a silenced check), with a regression test
reproducing the EXACT counterexample the review reported where one could
be constructed, or — for two findings whose own full request is a
genuinely large, separate architectural undertaking (mode-first routing
ordering, finding 10; the bar-0 convention unification, finding 20) — a
concrete, numbered task registration (`TASK-043`/`TASK-044`) rather than
an unnumbered "future task," matching this project's own established
"name it, don't fake it" discipline (the exact precedent round-7's own
P2 finding 20 established for `TASK-042`).

**No blanket "all resolved" headline this time without the same
qualification stated up front:** findings 10 and 20 are registered, not
implemented — their own numbered task files (`TASK-043_MODE_FIRST_ROUTING_ARCHITECTURE.md`,
`TASK-044_BAR_ZERO_CONVENTION_UNIFICATION.md`) are both "Not started,"
stated as such in their own Status sections. Every other finding (21 of
23) received a genuine, complete fix. MQL runtime execution (Strategy
Tester/live or demo terminal attachment) remains categorically blocked by
this sandbox — confirmed across three independent attempts earlier in
this project (TASK-003/004/005) and not re-attempted this round per that
standing decision; no runtime output is claimed or fabricated anywhere in
this remediation.

## Verification evidence

- **MQL5:** every commit below that touched `.mq5`/`.mqh` files was
  compiled via MetaEditor64.exe before committing; build artifacts
  (`.ex5`) and per-commit logs were not retained (they never have been in
  this project), but a **full, current, individually-hashed compile of
  all 46 real `.mq5` targets** — the 2 Experts
  (`ThembaAdaptiveIntradayEA.mq5`, `EquityTickRecorder.mq5`) and all 44
  `Test_*.mq5`/`Export_*.mq5` scripts (up from round-8's 41 — this round
  added `Test_ChartPatternLifecycle.mq5` and `Test_ExecutionEventJournal.mq5`;
  **corrected, 2026-07-28, Codex round-10 P2 finding 20: undercounts --
  the actual five new scripts were `Test_RiskReservationManager.mq5`,
  `Test_DailyWeeklyBreachManager.mq5`, `Test_NoStopGraceManager.mq5`,
  `Test_ExecutionEventJournal.mq5`, and `Test_ChartPatternLifecycle.mq5`
  (41 + 5 = 46). Left as-is above rather than retroactively rewritten --
  see `09_HANDOVERS/compile_evidence/README.md`'s own corrected entry
  for the accurate count.**),
  not just this round's own touched files — is retained at
  `09_HANDOVERS/compile_evidence/TASK-028_round9_full_compile_evidence_2026-07-28.txt`,
  recording the exact MetaEditor invocation, MetaEditor version/build
  (5.0.0.5833), the tree commit compiled, and — for every target — its
  own SHA-256 source hash plus its COMPLETE raw compiler log text. All 46
  compile clean. `THEMBA_EA_GIT_COMMIT` updated to `2e71e38` (this
  round's own final content commit, immediately before this evidence
  pass), per this project's stated manual-build-tag convention — this
  time the evidence file's own header states precisely, from the start,
  that the tree compiled is the evidence commit's own, never described as
  its parent's (round-9 P1 finding 21's own lesson, applied proactively
  rather than corrected after the fact).
- **Python:** the full `pytest` suite passes at every commit below; by
  the final content fix it stood at **749 passed, 0 failed**. `ruff
  check`, `ruff format --check`, and `mypy` were all re-run as a genuine
  whole-project final gate (the first true `mypy .` run of this
  remediation pass surfaced one real, pre-existing, unrelated type error
  in `tests/conftest.py` — fixed in commit `2e71e38`) — all three report
  clean.
- **Notebooks:** notebooks 00, 01, and 09 (the three touched by this
  round's own findings 14/15/23) re-executed via `nbconvert --execute
  --inplace` against the project's own registered `themba-python-lab`
  Jupyter kernel, zero raised exceptions, zero machine-local paths or
  stale `git_commit` values remaining in committed output. (`jupyter
  execute`'s own CLI silently skipped re-running an edited cell in this
  environment during this round — confirmed by `execution_count`/outputs
  staying empty after a run that otherwise completed without error;
  `nbconvert` executed correctly and is the more reliable tool going
  forward.) The other 7 required notebooks were not touched this round
  and were not re-executed, since nothing in round 9's own findings
  required changing them. **Corrected, 2026-07-28 (Codex round-10 P2
  finding 20): "7" undercounts -- TASK-028 defines TEN required
  notebooks (01-10 per the task's own numbered list; notebook 00 is an
  additional, non-required demo). After the three touched here (00, 01,
  09 -- note 00 is the non-required demo, not one of the ten), EIGHT of
  the ten required notebooks remained untouched, not seven. Left as-is
  above rather than retroactively rewritten -- this is a historical
  record of what round 9's own handover said at the time, not the
  current count.**

## Findings resolved, by commit

**P0 (7):**

1. **Hard-risk cap still fail-open/raceable/unenforced post-fill** —
   `3a5549a`. New `RiskReservationManager.mqh` (cross-symbol reservation
   ledger, magic-wide prefix-scannable via `KeyEncoding.mqh`'s new
   `KE_MagicNamespace`) closes the race two chart instances sharing a
   magic on different symbols could hit; a new post-fill actual-risk
   recomputation in `OnTradeTransaction` catches slippage pushing a fill
   over the cap.
2. **Risk persistence still non-transactional/unsafe** — `fad8901`.
   `StateManager.mqh`'s account lock rewritten around an owner-token
   compare-and-set (closes an ABA release race) with an atomic
   create-if-absent bootstrap; `SM_SetAccountDoublesBatch` now stops at
   the first failed write instead of continuing regardless;
   `EquityPeakManager.mqh` returns an explicit validity flag distinct
   from "genuinely zero drawdown."
3. **Durable intent race/wrong-order-correlation/premature-clear** —
   `a38e98c`. Intent IDs now fold in a wall-clock timestamp (not
   microseconds-since-terminal-start alone, which resets on restart);
   position/order matching now requires the intent ID to match via
   `POSITION_COMMENT`/`ORDER_COMMENT`, not symbol+magic alone; a failed
   history lookup now leaves the intent active instead of falling through
   to abandonment.
4. **Partial/async fill terminal-state handling still unsafe** —
   `4d69783`. `OM_OpenPosition` now distinguishes a confirmed-but-
   unresolved fill from an outright rejection (`exposure_unresolved`);
   `has_live_remainder` detects a `DONE_PARTIAL` fill whose own order
   ticket is still working, keeping the durable intent alive for its
   later resolution instead of clearing it prematurely.
5. **FairEconomy accepting partial/malformed calendar payload as safe** —
   `2dd855b`. `FEP_ParseFeedJson` now rejects the whole fetch if any
   date-parseable object is missing a required field or has an unknown
   impact value, instead of silently treating a partially-malformed feed
   as verified-safe.
6. **Mandatory-close/no-stop obligations silently stopping retry on
   write failure** — `892425d`. The same in-memory-fallback pattern
   already used once (`IntradayCloseManager.mqh`'s own
   `g_icm_close_done_today`) is now applied consistently to
   `DailyWeeklyBreachManager.mqh`, `NoStopGraceManager.mqh`, and
   `CloseInFlightTracker.mqh` (staleness timeout added), plus `OnInit`'s
   own `EventSetTimer` return value is now checked and retried every tick
   until armed.
7. **`OnInit` permitting settings that defeat hard limits** — `996039b`.
   New startup refusals for `InpRiskCapPercent > 1.0`,
   `InpDailyLossCapPercent`/`InpWeeklyLossCapPercent` outside their own
   documented maxima, `InpMagicNumber == 0`, and an inverted stop
   floor/cap; `BrokerValidator.mqh` now also rejects a RETURN-only
   filling mode and calls `OrderCalcMargin` as a real broker-side check.

**P1 (14):**

8. **Cash-flow deals causing false daily/weekly breach before rebase** —
   `03d1f17`. `OnTradeTransaction`'s `DEAL_ADD` handler now calls the
   existing, idempotent `DWL_ApplyCashFlowAdjustments()` before
   evaluating the breach check, so a deposit/withdrawal deal is rebased
   into the baseline before the same handler invocation checks it against
   the cap.
9. **Async fills absent from machine-readable journal evidence** —
   `c3815ad`. New `ExecutionEventJournal.mqh` — a genuinely separate,
   append-only execution-event journal (the "genuine, named follow-up"
   round-7's own P0 finding 2 fix deferred) — records every sync/async
   fill/cancel resolution, including at the exact moment of synchronous
   fill confirmation (before `EvaluateAndJournal`'s own later
   `DJ_AppendDecision` call), closing the crash-window gap the review
   also named.
10. **Mode-first routing architecture remains deliberately
    unimplemented** — `1974b98`. Registered as
    `TASK-043_MODE_FIRST_ROUTING_ARCHITECTURE.md`, a real specification
    stub (not implementation) — this is genuinely substantial,
    unimplemented architecture (regime → mode → mode-aware strategy
    generation, replacing today's generate-then-veto ordering), not
    something to approximate under review-remediation time pressure.
11. **Chart-pattern execution still has no required lifecycle registry**
    — `d04fed9`. New `ChartPatternLifecycle.mqh` — a persisted
    FORMING/CONFIRMED/RETESTING/TRADED/INVALIDATED/EXPIRED state
    registry keyed by a durable identity (pattern type + the two
    identity-defining pivot bars' own TIMES) — closes this in full;
    `ChartPatternStrategy.mqh` now genuinely calls the engine's own
    `CPT_CheckRetestArray` hold/fail predicate and permanently suppresses
    a consumed instance from ever re-entering eligibility.
12. **CSV-plus-JSON publication not atomic, can destroy a previous valid
    report** — `19f16ff`. `publish_dataframe_csv_and_json` and the two
    three-output journal/news publishers now write every requested file
    fully to a temp location first; a pre-existing valid file group
    survives completely untouched if any temp write fails, closing a
    reproduced probe where the prior "unlink on failure" policy destroyed
    a pre-existing valid CSV.
13. **`max_retained_errors` bypassed for excluded/non-file candidates** —
    `7100ff0`. Both exclusion branches in `read_journal_directory` now
    run the same budget check immediately after their own error append,
    closing a path that previously skipped it entirely via an early
    `continue`.
14. **Python/MQL pattern comparator accepting different/non-finite
    datasets** — `e573276`. `python_identity` must now include the
    COMPLETE exporter identity (symbol/timestamp/OHLC/atr, not a
    caller-chosen subset), every numeric identity column is asserted
    finite on both sides, and `price_tolerance` itself must be finite and
    non-negative.
15. **Pattern documentation/evidence source-stale, no real MQL-export
    comparison** — `6bf68dc`. Corrected `pattern_validation.py`'s own
    stale "exporter scoped to 4 patterns" claim (it exports all 20);
    notebook 09's own markdown now states explicitly that test-plan item
    7 remains PENDING, not satisfied by its synthetic self-comparison.
16. **Equity analysis accepts blank identity, resets "daily" giveback on
    the wrong clock** — `b84446c`. Identity columns are now read as
    strings and asserted non-blank (closing a wholly-blank-file
    false-pass); `EquityTickRecorder.mq5` now records a new
    `timestamp_server` column and the daily-giveback path groups by it
    instead of UTC, matching the live risk contract's own trade-server-
    midnight reset boundary.
17. **Journal schema still admits blank/out-of-domain provenance via
    whitespace** — `8bbd881`. A shared strip-and-reject-blank validator
    now closes the `str_strip_whitespace=False` gap that let a
    whitespace-only value satisfy `min_length=1`; `session_state` is now
    a Literal of its real three-value producer vocabulary.
18. **Performance breakdown validates normalized news_state but groups
    the unnormalized originals** — `e4e2ab5`. `compute_breakdown` now
    replaces the grouped column with its own canonicalized value
    (matching what validation already checked); null now canonicalizes
    to the real `"UNKNOWN"` producer token instead of an exempt "no
    claim" carve-out.
19. **The nominal 500 MB CSV ceiling still permits multi-gigabyte peak
    memory** — `7a797d3`. Every chunk is now written directly into a
    `tempfile.SpooledTemporaryFile` (bounded in-memory, spilling to disk
    beyond 1 MiB) with an incrementally-updated SHA-256 hash — neither
    the raw bytes nor a decoded string is ever materialized as one
    contiguous in-memory object.
20. **Three incompatible bar-0 conventions remain explicitly unfinished**
    — `8510cc2`. Registered as `TASK-044_BAR_ZERO_CONVENTION_UNIFICATION.md`
    — R-path indexing touches financially-meaningful giveback/drawdown
    percentage math across three modules, requiring an invariance proof
    this remediation pass did not rush.
21. **Compile evidence proves syntax, false Git provenance; no MQL
    runtime execution** — `a2699f2`. Corrected the round-8 evidence
    file's own header, which claimed the PARENT commit's tree was
    compiled (confirmed wrong via `git show`: the parent's own
    `THEMBA_EA_GIT_COMMIT` value is a different, earlier reference than
    claimed). MQL runtime execution remains honestly disclosed as
    sandbox-blocked, not fabricated.

**P2 (2):**

22. **Canonical status/history contradicts current source, Git dates,
    and its own deferrals** — `4683afb`. Corrected the "2026-07-22"
    round-8 review date (Git-confirmed 2026-07-27) across three canonical
    surfaces, and replaced the unqualified "all 22 resolved" headlines
    with language naming the two genuinely partial scopes and their
    since-closed/registered status.
23. **Committed notebook output and diff hygiene stale/machine-local** —
    `33cd86d`. Notebooks 00/01's own committed print output no longer
    embeds a machine-specific temp directory path (filename only);
    notebook 00's own `session_state="london"` fixture fixed (would have
    failed schema validation after finding 17); the compile-evidence
    file's own extra trailing blank line at EOF removed.

## What Claude did NOT do this round

- Did not implement `TASK-043`'s mode-first routing reorder or
  `TASK-044`'s bar-0 convention unification — both registered as real,
  scoped, numbered follow-ups (specification stubs, no implementation),
  not approximated under time pressure. See each task file's own Status
  section.
- Did not attempt `TASK-037`'s cost-sensitivity/OHLC-R-path/session-news
  exports — pre-existing, honestly-disclosed, not-yet-built follow-ups,
  unchanged this round because nothing this round's own findings required
  touching them.
- Did not run any of this against a real/demo MT5 session — this sandbox
  cannot (three independent confirmed attempts earlier in this project);
  every export/EA fix remains verified by compile + hand-derived or
  pytest-executed regression test only. This is the single largest
  remaining gap before the EA can be considered launch-ready, and it
  remains the user's own responsibility to perform in a real desktop MT5
  session.

## Requesting review

Per the user's own sprint directive ("finish all the tasks, then we do a
codex review after everything is done, then from the review we correct
and make any solid adjustments needed then we launch the EA on MT5"),
this handover **is** the request for the next (tenth) review round.
