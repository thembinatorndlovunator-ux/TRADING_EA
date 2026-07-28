# MetaEditor compile evidence

**Added 2026-07-22 (Codex review finding, seventh round, P1 finding 19):**
several canonical task records claimed real MetaEditor 0-error/0-warning
evidence, but the reviewed tree retained neither compiler logs nor build
artifacts tied to any specific commit -- making the claim non-reproducible,
even though the compiles themselves genuinely happened.

## Convention going forward

- `.ex5` build artifacts are still never committed (`03_SOURCE_CODE/.gitignore`'s
  `*.ex5` rule stands).
- The **compiler log text itself** (converted from MetaEditor's UTF-16LE log
  output to UTF-8, per `00_MASTER_PROMPT_FOR_CLAUDE.md`'s "save the complete
  compiler output" requirement) is retained in this directory, one file per
  remediation round, named `TASK-<n>_round<r>_full_compile_evidence_<date>.txt`.
- Each file records the repo HEAD commit it was generated against, and the
  full `Result: N errors, N warnings` line (plus any error/warning detail) for
  every `.mq5` file compiled that round -- not just a pass/fail summary.

## Entries

`TASK-028_round7_full_compile_evidence_2026-07-22.txt` -- generated against
commit `970cb3974d28ee1cbe741cdb67de95550d4dc4dd` (immediately after Codex
round-7's finding 17 was resolved), covering the full EA
(`ThembaAdaptiveIntradayEA.mq5`) and all 38 `Test_*.mq5`/`Export_*.mq5`
scripts in `03_SOURCE_CODE/MQL5/Scripts/` at that commit -- not just the
files this round's own findings touched. Every one compiles with 0 errors,
0 warnings. **Known wrong, 2026-07-27 (Codex round-8 P1 finding 21): at
that commit, Git actually contained 39 `.mq5` programs (2 Experts + 37
Test/Export scripts) -- this entry's own "38 Test/Export scripts" both
undercounted the scripts AND omitted `EquityTickRecorder.mq5` (the second
Expert) from its per-file listing entirely, despite its own file recording
"all 39 programs compiled." Left as-is rather than retroactively rewritten
-- it is a historical record of what round 7 actually produced (wrong
counts included), not the current state; see the round-8 entry below for
accurate current counts and format.**

`TASK-028_round8_full_compile_evidence_2026-07-27.txt` -- generated against
the tree at commit `c9b2298` (the CHILD of the commit whose own
`THEMBA_EA_GIT_COMMIT` value is `990f32c17327...`, i.e. this same finding's
own commit, which changes only `THEMBA_EA_GIT_COMMIT`/`THEMBA_EA_VERSION_STRING`
and this compile-evidence/README pair -- no compiled behavior), covering
all 41 `.mq5` programs that exist in Git at that point: the 2 Experts
(`ThembaAdaptiveIntradayEA.mq5`, `EquityTickRecorder.mq5`) and all 39
`Test_*.mq5`/`Export_*.mq5` scripts, each listed individually with its own
SHA-256 source hash and its own COMPLETE raw MetaEditor log text (not just
the summary `Result:` line) -- addressing this same finding's complaint
that the retained evidence omitted invocation, compiler version/build, and
most raw log text. MetaEditor version: 5.0.0.5833. Every target compiles
with 0 errors, 0 warnings.

**Corrected, 2026-07-27 (Codex round-9 P1 finding 21):** this entry's own
phrasing above ("generated against the tree at commit `990f32c17327...`'s
own child") was ambiguous enough that the evidence file's OWN header text
independently described the provenance the OPPOSITE way (claimed the
PARENT's tree was compiled) -- the two disagreed. Spelled out explicitly
here now (`c9b2298`, not its parent `990f32c`) and corrected in the
evidence file's own header directly; see that file's own correction note
for the full `git show`-verified account of exactly which commit's
`THEMBA_EA_GIT_COMMIT` value is which.

`TASK-028_round9_full_compile_evidence_2026-07-28.txt` -- generated after
all 23 round-9 findings were resolved, against the tree at THIS EVIDENCE
FILE'S OWN COMMIT (never described as its parent's tree this time, per
round-9 P1 finding 21's own lesson, applied from the start rather than
corrected after the fact). `THEMBA_EA_GIT_COMMIT` in
`ThembaAdaptiveIntradayEA.mq5` is set to `2e71e38` (the last real content
commit before this evidence pass), matching this project's own stated
build-tag convention exactly. Covers all 46 `.mq5` programs that exist in
Git at that point: the 2 Experts (`ThembaAdaptiveIntradayEA.mq5`,
`EquityTickRecorder.mq5`) and all 44 `Test_*.mq5`/`Export_*.mq5` scripts.
**Corrected, 2026-07-28 (Codex round-10 P2 finding 20):** the rise from
round-8's 41 to round-9's 46 targets was previously attributed here to
just two new scripts ("`Test_ChartPatternLifecycle.mq5` and
`Test_ExecutionEventJournal.mq5`, plus scripts touched by other
findings") -- undercounted. The five ACTUAL new scripts round 9 added
were `Test_RiskReservationManager.mq5`, `Test_DailyWeeklyBreachManager.mq5`,
`Test_NoStopGraceManager.mq5`, `Test_ExecutionEventJournal.mq5`, and
`Test_ChartPatternLifecycle.mq5` (41 + 5 = 46). Each target is listed
individually with its own SHA-256 source hash and its own COMPLETE raw
MetaEditor log text. MetaEditor version: 5.0.0.5833. Every target
compiles with 0 errors, 0 warnings.

`TASK-028_round10_full_compile_evidence_2026-07-28.txt` -- generated
after all 21 round-10 findings were addressed (see the round-10
handover's own per-finding table for exactly what "addressed" means per
finding -- P0/P1 findings 1-14 and 18 with a real code fix and, where a
Python/MQL regression could be constructed, a passing test reproducing
the exact reported counterexample; P1 findings 15-17 confirmed as
already-honest, correctly-scoped registrations, not new code defects;
P2 findings 19-21 as canonical-documentation corrections), against the
tree at THIS EVIDENCE FILE'S OWN COMMIT. `THEMBA_EA_GIT_COMMIT` is set
to `e3da3f4` (the last real content commit before this evidence pass),
now explicitly documented in the EA's own source comment as a
LOGICAL-PARENT TAG, not a byte-exact "compiled from" identifier (round-10
P2 finding 21's own correction). Covers the SAME 46 `.mq5` programs as
round 9 -- round-10 remediation added no new `.mq5` target (its own new
module, `CloseFinalizationTracker.mqh`, is a reusable include with no
dedicated test script; see that file's own header). Format note: each
target's own SHA-256 hash plus MetaEditor's final `Result:` summary line
only (not the full percentage-by-percentage progress log round 8/9's
evidence files retained) -- disclosed explicitly in the evidence file's
own header as a deliberate format change, not an omission; the summary
line is the only line that ever carried pass/fail information. MetaEditor
version: 5.0.0.5833. Every target compiles with 0 errors, 0 warnings.
