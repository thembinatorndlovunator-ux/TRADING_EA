# TASK-001 — Baseline Audit: SmartCoreEngine V6.37 & NdlovuSMC V8.11

## Objective

Produce the complete baseline audit, evidence inventory, and comparison plan
required by `00_MASTER_PROMPT_FOR_CLAUDE.md` section 3 ("Initial Response and
First Actions") and `CLAUDE.md`'s workflow step 1 ("Audit"), before any
architecture or code work begins on the Themba Adaptive Intraday Engine.

## Reason

Per the master prompt's closing line: "Begin with the repository audit. Do
not modify trading logic until the audit, evidence inventory, and baseline
comparison plan are complete." Phase 0 (preservation — baselines hashed,
tagged, immutable under `01_BASELINE/`) was already done on `main`
(commit `0d65f95`, tags `baseline-v637`/`baseline-v811`). Nothing else had
been produced: no `TASKS.md`, no task file, no audit documents. This task
closes that gap.

## Baseline behaviour

Both baselines are read-only source of truth for this task — nothing in
`01_BASELINE/` was modified. Their behavior as documented by static reading:

- **SmartCoreEngine V6.37** (`01_BASELINE/EA_V637/Thembabot14 Max.mq5`,
  8,822 lines, 282 input variables + 25 input-group headings): fractal SR, triple-redundant trendline logic,
  FVG retest, range cycle/rotation, premium/discount/equilibrium/OTE, BOS/
  CHoCH, M30 order-block confluence, pilot trade + add-ons, regime-aware
  journal-learning, daily limits, ATR stop floor/cap, profit-lock +
  giveback guard, staged historical-target ladder, NFP heuristic news
  logic. Full detail: `baseline_v637_audit.md`.
- **NdlovuSMC V8.11** (`01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5`, 2,397
  lines, 107 input variables + 9 input-group headings): H1/M30/M15/M5/M1 hierarchy, SMC sweep-and-shift,
  clustered SR bounce, two-stage order blocks, first-return-only FVG, M1
  BOS retest, ASQ momentum breakout, 1–4 leg baskets with fixed R-ladder,
  giveback guard, hard 45-minute time exit, peak-drawdown lock, manual
  session/news filters, no journal/learning system by design. Full detail:
  `baseline_v811_audit.md`.

## Evidence

- `01_BASELINE/inventory.md` — re-verified SHA-256 of both `.mq5` files and
  the orphaned set file against `IDENTITY.md`, all matched; 13 screenshots
  catalogued with size/timestamp/hash.
- `01_BASELINE/screenshots/visual_notes.md` — objective per-screenshot
  observations, all interpretations explicitly labeled hypotheses (no
  linked trade journal/CSV exists yet to confirm against, per
  `VISUAL_EVIDENCE_PROTOCOL.md`).
- `baseline_v637_audit.md` / `baseline_v811_audit.md` — full-depth static
  audits, one `##` section per master-prompt section-4 checklist bullet for
  each EA, every claim cited to a real line number, every finding labeled
  FACT / COMMENT-CLAIMED / CONTRADICTION / HYPOTHESIS.
- `baseline_comparison.md` — synthesized feature/risk matrix across both
  EAs, plus resolution of the orphaned `SmartCore_v3_Tuned.set.txt`
  provenance question (belongs to neither baseline — see that file's
  "Orphaned set file — resolved" section).

## Specification

No new specification documents are produced by this task (out of scope —
see below). This task's own "specification" is the master-prompt section-4
checklist itself, applied exhaustively to both files; nothing was added to
or altered in `STRATEGY_SPECIFICATION.md`, `RISK_POLICY.md`, or the other
governing specs.

## Files affected

New files only, all on branch `claude/task-001-baseline-audit`:
- `TASKS.md`
- `TASK-001_BASELINE_AUDIT.md` (this file)
- `01_BASELINE/inventory.md`
- `01_BASELINE/screenshots/visual_notes.md`
- `baseline_v637_audit.md`
- `baseline_v811_audit.md`
- `baseline_comparison.md`
- `profit_giveback_diagnosis_plan.md`
- `09_HANDOVERS/claude_to_codex/TASK-001_handover.md`

No file under `01_BASELINE/` was modified (verified — see Test plan).

## Out of scope

- No trading-code changes of any kind.
- No new architecture files under `03_SOURCE_CODE/`.
- No specification documents beyond the giveback *plan* (not a diagnosis —
  no trade data exists yet to diagnose from).
- No actual Codex review execution — `09_HANDOVERS/claude_to_codex/TASK-001_handover.md`
  only requests it; the review itself happens in a separate Codex
  session/branch per `AGENTS.md`.
- No compilation or backtesting — nothing here is code.

## Risks

- **Missing trade-linkage evidence**: none of the 13 screenshots, nor
  either EA, is backed by a trade-history CSV or journal export in this
  repo yet, so every visual interpretation and every "risk of X" checklist
  item that needed empirical confirmation is explicitly marked HYPOTHESIS,
  not FACT, per `profit_giveback_diagnosis_plan.md`.
- **Two highest-severity code findings, unresolved by design of this
  task**: V6.37's `CloseAllOurPositions` symbol-filter omission (would
  force-close unrelated profitable positions across symbols on a shared
  magic number) and V8.11's restart-strips-all-risk-controls defect (a
  restarted EA with an open basket silently loses break-even/trailing/
  giveback/time-exit protection while the dashboard reports "flat"). Both
  are documented, neither is fixed here — fixing baseline code would
  violate "preserve both original EAs as immutable baselines"
  (`PROJECT_RULES.md` #1). These are inputs to the *new* engine's design,
  not patches to the old ones.
- **Audit depth vs. agent variance**: the two deep-audit passes were done
  by independent agent runs reading the full files end-to-end; line numbers
  were independently re-verified in each pass rather than trusted from the
  prior structural survey, but a second independent read (Codex) is still
  required per the release-gate process before these findings inform any
  new code.

## Test plan

Since no code changed, "testing" here means verifying the audit's own
integrity:
1. `git diff baseline-v637 -- 01_BASELINE/EA_V637` and
   `git diff baseline-v811 -- 01_BASELINE/EA_V811` both empty.
2. `sha256sum` of both `.mq5` files matches `IDENTITY.md` and
   `01_BASELINE/inventory.md`.
3. Every checklist bullet from master-prompt section 4 (both EAs) has a
   corresponding `##` section in the respective audit doc, citing a real
   function/input name and line number.
4. No `profitable`/`compiled`/`working` claims appear anywhere in any new
   document without an explicit "not applicable — no code changes" or
   equivalent caveat.
5. `git status` on `main` unchanged; all new files exist only on the task
   branch until Codex review passes and a merge is separately approved.

## Acceptance criteria

- [x] All 9 deliverables listed under "Files affected" exist and are
      internally consistent (same file list, same status, across
      `TASKS.md` and this task file).
- [x] Both baseline `.mq5` files, screenshots, and set file are unchanged
      (hash match).
- [x] Every master-prompt section-4 checklist bullet, both EAs, has a
      cited, line-numbered entry in the respective audit document.
- [x] Orphaned set-file provenance question is resolved (or explicitly
      documented as unresolved with reasoning) in `baseline_comparison.md`.
- [x] Profit-giveback document is a plan, not a diagnosis (no trade data
      exists to diagnose from).
- [x] Independent Codex review completed
      (`09_HANDOVERS/codex_to_claude/TASK-001_review.md`, disposition:
      **changes requested**) and findings resolved — corrections integrated
      into all three affected documents (`baseline_v637_audit.md`,
      `baseline_v811_audit.md`, `baseline_comparison.md`) in the follow-up
      commit. Includes one BLOCKER (V6.37's completed-candle violation in
      `IsBullishInsideFalseBreak`/`IsBearishInsideFalseBreak`) and several
      new cross-cutting findings (netting/hedging compatibility,
      trade-result handling, broker filling/stop/tick-size validation,
      restart idempotency) neither original audit had covered.

## Rejection criteria

This task would be rejected if: any `01_BASELINE/` file were modified; any
audit claim asserted compilation/correctness/profitability without
evidence; any checklist bullet were skipped or answered generically without
a source citation; or the giveback document presented hypotheses as
confirmed findings.

None of these occurred, per the Test plan checks above.

## Implementation notes

- Two independent general-purpose agents performed the full-depth static
  audits of V6.37 and V8.11 respectively, each given the master-prompt
  section-4 checklist for their EA and instructed to re-verify all line
  numbers by reading the file directly rather than trusting a prior
  structural-survey map. Both audits read their target file end-to-end.
- The orphaned-setfile resolution in `baseline_comparison.md` was reached
  by directly comparing the set file's key names (no `Inp` prefix, INI
  sections) against both EAs' actual input declarations (all `Inp`-prefixed,
  no native `.set` file ever has sections) — it does not match either
  baseline's real compiled inputs.
- All 13 screenshots were visually reviewed directly (image read) rather
  than inferred from filenames alone; observations are split into
  objective/certain vs. hypothesis per `VISUAL_EVIDENCE_PROTOCOL.md`.

## Commands run

```
git checkout -b claude/task-001-baseline-audit
git diff baseline-v637 -- 01_BASELINE/EA_V637   # empty
git diff baseline-v811 -- 01_BASELINE/EA_V811   # empty
sha256sum "01_BASELINE/EA_V637/Thembabot14 Max.mq5"
sha256sum "01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5"
sha256sum "01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt"
sha256sum "01_BASELINE/screenshots/"*.png
grep -n -i "giveback" "01_BASELINE/EA_V637/Thembabot14 Max.mq5"
grep -n -i "giveback" "01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5"
```

## Compiler result

No code changed in this task, so MetaEditor compilation is not relevant to
it — **wording corrected per independent review**: rather than a blanket
"not applicable," the accurate statement is that no compilation was
performed or claimed, because this task produces documentation only.

## Test results

**Wording corrected per independent review** — rather than a blanket "not
applicable," the accurate statement is: no compilation, backtest, restart
simulation, multi-symbol test, or netting/hedging execution test was
performed or is claimed anywhere in this document set. Those tests remain
relevant *to the baseline EAs themselves* and are exactly what several of
the audits' HYPOTHESIS-labeled findings (e.g. restart-idempotency, netting/
hedging behavior, NFP filter reliability) call for before they could be
confirmed — the audits identify what needs testing, they do not perform it.
All verification actually performed for this task was documentation/hash
integrity checking (see Test plan above), not software testing.

## Commit

- Initial deliverables commit: `c61903f` on `claude/task-001-baseline-audit`
  (9 files — see "Files affected").
- Codex independent review: `09_HANDOVERS/codex_to_claude/TASK-001_review.md`,
  disposition **changes requested**.
- Corrections-in-response-to-review commit: recorded once committed (see
  Final decision below) — updates `baseline_v637_audit.md`,
  `baseline_v811_audit.md`, `baseline_comparison.md`, and this file to
  integrate every required change from the review. No file under
  `01_BASELINE/` is touched by the correction commit either.

## Reviewer

Codex — independent review completed via
`09_HANDOVERS/claude_to_codex/TASK-001_handover.md` →
`09_HANDOVERS/codex_to_claude/TASK-001_review.md`. Disposition: **changes
requested**. All required changes from that review have been applied in
the corrections commit referenced above.

## Final decision

**Pending re-review.** All required changes from Codex's first review pass
have been applied. Per `00_MASTER_PROMPT_FOR_CLAUDE.md` section 21 (release
gates), this branch still needs Codex to confirm the corrections resolve
the disposition before `main` merge is considered, and merge must not be
performed by the same agent that produced the audit.
