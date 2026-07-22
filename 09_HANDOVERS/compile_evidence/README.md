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

## This directory's first entry

`TASK-028_round7_full_compile_evidence_2026-07-22.txt` -- generated against
commit `970cb3974d28ee1cbe741cdb67de95550d4dc4dd` (immediately after Codex
round-7's finding 17 was resolved), covering the full EA
(`ThembaAdaptiveIntradayEA.mq5`) and all 38 `Test_*.mq5`/`Export_*.mq5`
scripts in `03_SOURCE_CODE/MQL5/Scripts/` at that commit -- not just the
files this round's own findings touched. Every one compiles with 0 errors,
0 warnings.
