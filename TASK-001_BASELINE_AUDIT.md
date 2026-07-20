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
  clustered SR bounce, two-stage order blocks, partially-enforced-first-return
  FVG (**corrected per third-pass review — was still unqualified here**: the
  touch scan omits the trigger bar and stores no consumed flag, so a cached
  gap can in principle be reconsidered — see `baseline_v811_audit.md`'s "M5
  FVG" section), M1
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
  EAs. **Corrected per independent review (C1):** the orphaned
  `SmartCore_v3_Tuned.set.txt` question is not resolved — the comparison
  document establishes only that the file is not a usable native preset
  for either baseline; its actual origin remains unresolved (see that
  file's "Orphaned set file — not usable for either baseline; provenance
  unresolved" section).

## Specification

No new specification documents are produced by this task (out of scope —
see below). This task's own "specification" is the master-prompt section-4
checklist itself, applied exhaustively to both files; nothing was added to
or altered in `STRATEGY_SPECIFICATION.md`, `RISK_POLICY.md`, or the other
governing specs.

## Files affected

**Distinguished per independent review (C2)** — initial deliverables vs.
later correction-pass modifications, all on branch
`claude/task-001-baseline-audit`:

**New in the initial commit (`c61903f`):**
- `TASKS.md`
- `TASK-001_BASELINE_AUDIT.md` (this file)
- `01_BASELINE/inventory.md`
- `01_BASELINE/screenshots/visual_notes.md`
- `baseline_v637_audit.md`
- `baseline_v811_audit.md`
- `baseline_comparison.md`
- `profit_giveback_diagnosis_plan.md`
- `09_HANDOVERS/claude_to_codex/TASK-001_handover.md`

**Modified in the first correction commit (`3f69469`)** in response to
Codex's first review — `baseline_v637_audit.md`, `baseline_v811_audit.md`,
`baseline_comparison.md`, `TASK-001_BASELINE_AUDIT.md`, `TASKS.md` — plus
new files `09_HANDOVERS/codex_to_claude/TASK-001_review.md` and
`09_HANDOVERS/claude_to_codex/TASK-001_review_response.md`.

**Modified in the second correction commit (`4a6946b`)**, responding to
Codex's second review, exact path set corrected in third-pass review —
`baseline_v637_audit.md`, `baseline_v811_audit.md`, `baseline_comparison.md`,
`TASK-001_BASELINE_AUDIT.md`, `TASKS.md`, plus overwriting
`09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place (Codex's own
edit to record its second review) and adding new file
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round2.md`.

**Modified in follow-up commit `7319306`** — `TASK-001_BASELINE_AUDIT.md`
only (filled in the `4a6946b` hash and fixed a path typo, both of which
could only be known after `4a6946b` existed).

**Modified in the third correction commit (`538bc39`)**, responding to
Codex's third review — the same four documents plus `TASKS.md`, plus new
file `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round3.md`
(also overwrote `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place
again, Codex's own third-pass edit).

**Precision correction, third-pass review (C3/R3-10):** the claim "no file
under `01_BASELINE/` was modified" is accurate for the *preserved baseline
artifacts* specifically (both `.mq5` files, the set file, and all 13
screenshots — none of these has ever been altered, verified by hash and by
`git diff <tag> -- 01_BASELINE/EA_V637` / `-- 01_BASELINE/EA_V811` staying
empty after every commit). It is **not** accurate as a claim that no commit
touched anything under the `01_BASELINE/` path at all: the initial commit
(`c61903f`) **added** two new files there — `01_BASELINE/inventory.md` and
`01_BASELINE/screenshots/visual_notes.md` — as new audit documentation
alongside the preserved evidence, not as edits to it. `git diff
<baseline-tag> -- 01_BASELINE` (unscoped to the EA subdirectories) is
therefore *not* empty; the scoped per-EA-subdirectory diffs are what
verify immutability, and that is the check this task actually relies on
(see Test plan).

## Out of scope

- No trading-code changes of any kind.
- No new architecture files under `03_SOURCE_CODE/`.
- No specification documents beyond the giveback *plan* (not a diagnosis —
  no trade data exists yet to diagnose from).
- No compilation or backtesting — nothing here is code.

**Note (C3, stale text removed per independent review):** an earlier draft
of this section stated "no actual Codex review execution" as an out-of-scope
item. That is no longer accurate — Codex has since completed three full
review passes (see Reviewer and Commit sections below); review execution
itself happened in a separate Codex session/branch per `AGENTS.md`, but it
did occur, and is not out of scope for this task's final state.

## Risks

- **Missing trade-linkage evidence**: none of the 13 screenshots, nor
  either EA, is backed by a trade-history CSV or journal export in this
  repo yet, so every visual interpretation and every "risk of X" checklist
  item that needed empirical confirmation is explicitly marked HYPOTHESIS,
  not FACT, per `profit_giveback_diagnosis_plan.md`.
- **Highest-severity code findings, unresolved by design of this task,
  updated per independent review (C4):** the category-topping finding is
  V6.37's completed-candle BLOCKER (`IsBullishInsideFalseBreak`/
  `IsBearishInsideFalseBreak` reading the forming bar — a confirmed rule
  violation, not a risk to weigh). Among evidence-dependent operational
  risks: V6.37's `CloseAllOurPositions` symbol-filter omission (gated
  behind all four daily thresholds defaulting to zero; when active, force-
  closes positions across symbols sharing a magic number) and V8.11's
  restart defect (loses *dynamic* risk management — break-even, trailing,
  giveback, time exit, and direction-flip exit (**added, missing from this
  list per third-pass review**) — for an open basket, though the current
  broker-held SL/TP and the daily-lock's `CloseBasket` path both survive;
  the dashboard still misreports "Basket: flat"). None of these are fixed
  here — fixing
  baseline code would violate "preserve both original EAs as immutable
  baselines" (`PROJECT_RULES.md` #1). These are inputs to the *new*
  engine's design, not patches to the old ones.
- **Audit depth vs. agent variance**: the two deep-audit passes were done
  by independent agent runs reading the full files end-to-end; line numbers
  were independently re-verified in each pass rather than trusted from the
  prior structural survey. **Updated per independent review — no
  longer a forward-looking risk:** the independent Codex read has since
  happened three times, each pass catching real precision issues the prior
  pass missed (including, in the third pass, two false claims made in the
  correction responses themselves). This remains listed as a risk category
  because a further pass cannot be ruled out as still finding something,
  not because no review has occurred yet.

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
- [ ] Independent Codex review completed and findings resolved — **in
      progress, three passes so far, updated per independent review**:
      pass 1 (`09_HANDOVERS/codex_to_claude/TASK-001_review.md`, first
      version) returned changes requested, addressed in commit `3f69469`;
      pass 2 (same file, updated in place) returned changes requested again
      — narrower, mostly internal-consistency issues between corrected
      detailed sections and stale summaries, plus a handful of precision
      fixes, addressed in commit `4a6946b`; pass 3 (same file, updated in
      place again) returned changes requested a third time — narrower
      still, including two false claims found in the round-two response
      file itself (`git diff <tag> -- 01_BASELINE` is not actually empty;
      "full commit history" omitted the current HEAD) — now being addressed
      in the third correction pass. All three passes independently
      confirmed the BLOCKER (V6.37's completed-candle violation in
      `IsBullishInsideFalseBreak`/`IsBearishInsideFalseBreak`) and the new
      cross-cutting findings (netting/hedging compatibility, trade-result
      handling, broker filling/stop/tick-size validation, restart
      idempotency). Not checked off until a review pass returns approval.

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

**Filled in per independent review (C5), updated for completeness in the
third-pass review — full commit history on this branch, through current
`HEAD`:**

1. `c61903f` — initial deliverables commit (9 files — see "Files
   affected"), including two new files added under `01_BASELINE/`
   (`inventory.md`, `screenshots/visual_notes.md` — new audit
   documentation, not edits to the preserved evidence). Reviewed by Codex;
   disposition **changes requested** (`09_HANDOVERS/codex_to_claude/TASK-001_review.md`,
   first version).
2. `3f69469` — first correction-pass commit, responding to that review.
   Touched `baseline_v637_audit.md`, `baseline_v811_audit.md`,
   `baseline_comparison.md`, `TASK-001_BASELINE_AUDIT.md`, `TASKS.md`; added
   `09_HANDOVERS/codex_to_claude/TASK-001_review.md` and
   `09_HANDOVERS/claude_to_codex/TASK-001_review_response.md`. Re-reviewed
   by Codex; disposition **changes requested again** (narrower — most
   source-level findings verified, but several summary/comparison sections
   were stale relative to the corrected detailed prose, plus a few
   precision fixes and one omitted netting finding).
3. `4a6946b` — second correction-pass commit, responding to that second
   review. Touched the same four documents plus `TASKS.md`; overwrote
   `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place (Codex's own
   second-pass edit); added
   `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round2.md`.
4. `7319306` (`HEAD` at the time of this third-pass correction) — follow-up
   commit, `TASK-001_BASELINE_AUDIT.md` only, filling in the `4a6946b` hash
   and fixing a path typo. Reviewed by Codex a third time; disposition
   **changes requested a third time** (narrower still — most items
   verified, a handful of remaining internal-consistency gaps, two false
   claims in the round-two response file, and several precision fixes).
5. `538bc39` — third correction-pass commit, responding to this third
   review. Touched the same four documents plus `TASKS.md`; overwrote
   `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place again; added
   `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round3.md`.

**Precision correction, third-pass review:** "no file under `01_BASELINE/` is
touched by any commit in this history" was inaccurate as stated — see the
identical correction and its full reasoning under "Files affected" above.
The accurate, verified claim is that the *preserved baseline artifacts*
(both `.mq5` files, the set file, all 13 screenshots) are unmodified by
every commit above (scoped `git diff <tag> -- 01_BASELINE/EA_V637` /
`-- 01_BASELINE/EA_V811` empty throughout), while `01_BASELINE/inventory.md`
and `01_BASELINE/screenshots/visual_notes.md` were intentionally added as
new audit documentation in commit 1.

## Reviewer

Codex — three independent review passes completed via
`09_HANDOVERS/claude_to_codex/TASK-001_handover.md` →
`09_HANDOVERS/codex_to_claude/TASK-001_review.md` (updated in place for each
subsequent pass) → `09_HANDOVERS/claude_to_codex/TASK-001_review_response.md`
→ `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round2.md`. All
three passes returned **changes requested**. All required changes from the
first two passes were applied in commits `3f69469` and `4a6946b`
respectively; the third pass's required changes are being applied in the
correction commit referenced below.

## Final decision

**Pending fourth review pass.** All changes requested by Codex's *third*
review have been applied in this correction pass — but consistent with
this task's own repeated finding across all three prior passes (a document
package that looks complete does not always survive its own consistency
check), this is stated as "applied, pending confirmation," not "resolved."
Per `00_MASTER_PROMPT_FOR_CLAUDE.md` section 21 (release gates), this
branch needs Codex to confirm the corrections resolve the disposition
before `main` merge is considered, and merge must not be performed by the
same agent that produced the audit.
