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

Both baselines are read-only source of truth for this task — the preserved
EA/set/screenshot artifacts under `01_BASELINE/` were never modified
(**scoped precisely in fourth-pass review**: this task's own audit
documentation, `inventory.md` and `screenshots/visual_notes.md`, was added
under that same path, which is intentional and distinct from modifying the
preserved evidence — see "Files affected" and "Commit" below for the full
distinction). Their behavior as documented by static reading:

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

- `01_BASELINE/inventory.md` — **hash-attribution corrected in fourth-pass
  review, SHA-256-vs-blob-ID distinction added in fifth-pass review (the
  two are different checks and were previously conflated)**: re-verified
  SHA-256 of both `.mq5` files against their respective `IDENTITY.md` files
  (both matched). The orphaned set file's hash is recorded in
  `inventory.md` itself — its SHA-256 is `ea9452d4475d55f1aadd35a6f8f83b76c6046e2118d02aa5a918e673af4bce96`
  (**not** verified against an `IDENTITY.md` hash, because
  `01_BASELINE/setfiles/IDENTITY.md` records no hash at all — it documents
  the file's orphaned/unresolved status only) — and, as a separate check,
  its current/tagged content is confirmed identical to the preservation
  commit by matching Git blob object ID
  `3cd45788021a671b9ccf4502c8da1afaea4bcfac` at the `baseline-v637`/
  `baseline-v811` tags. 13 screenshots catalogued with size/timestamp/hash.
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
only (filled in the `4a6946b` hash and completed/clarified its
correction-pass entry with the exact response-file path — **corrected in
seventh-pass review**: an earlier draft of this description, going back to
this commit's own original message, called the second change a "path
typo" fix; the actual diff shows no such typo being corrected, only the
vague placeholder path description being replaced with the exact one —
both details could only be known after `4a6946b` existed).

**Modified in the third correction commit (`538bc39`)**, responding to
Codex's third review — the same four documents plus `TASKS.md`, plus new
file `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round3.md`
(also overwrote `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place
again, Codex's own third-pass edit).

**Modified in the fourth correction commit**, responding to Codex's fourth
review — the same four documents plus `TASKS.md` plus `01_BASELINE/inventory.md`
(a preserved-directory-path exception noted and justified in the
Baseline-behaviour section above — this is new audit-documentation content,
not a change to the preserved evidence itself), plus new file
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round4.md` (also
overwrote `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place again).
**Structural fix, fourth-pass review:** this entry deliberately does not
embed its own commit hash — see `git log --oneline claude/task-001-baseline-audit`
for the exact hash. **Two** prior rounds (**count corrected in fifth-pass
review, was previously miscounted as three**) each tried to record their
own commit hash and had to follow up with a second, dedicated
metadata/hash-recording commit (`7319306` for `4a6946b`'s hash — **wording
corrected in sixth-pass review, then corrected again in seventh-pass
review after the sixth-pass correction itself introduced a false "path
typo" description**: `7319306`'s actual diff shows it also completed/
clarified that entry's response-file path, not a typo fix, so
"hash-recording-only" still overstates its sole purpose, just not for the
reason previously claimed; `79f8e5a` for `538bc39`'s hash, which genuinely
was hash-recording-only) because the hash cannot be known before the
commit exists; this entry breaks that loop by referencing the commit
symbolically instead.

**Modified in the fifth correction commit `683bc77`** (**hash filled in
now that it exists, seventh-pass review**), responding to Codex's fifth
review — the same five documents as the fourth pass
(`baseline_v637_audit.md`, `baseline_v811_audit.md`,
`baseline_comparison.md`, `TASK-001_BASELINE_AUDIT.md`, `TASKS.md`) plus
`01_BASELINE/inventory.md` again (a second, different correction to that
same preserved-directory-path exception), plus new file
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round5.md` (also
overwrote `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place
again).

**Modified in the sixth correction commit `8a88389`** — exactly seven
paths (**added in seventh-pass review, this entry was previously
missing**): `baseline_v637_audit.md`, `baseline_v811_audit.md`,
`baseline_comparison.md`, `TASK-001_BASELINE_AUDIT.md`, `TASKS.md`,
overwrote `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place, and
added new file `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round6.md`.
No `01_BASELINE/` path was touched by this commit.

**Modified in the seventh correction commit `9a1948c`** — exactly five
paths (**added in eighth-pass review, this entry was previously
missing**): `baseline_v637_audit.md`, `baseline_comparison.md`,
`TASK-001_BASELINE_AUDIT.md`, overwrote
`09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place, and added new
file `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round7.md`.
Did **not** touch `baseline_v811_audit.md`, `TASKS.md`, or any
`01_BASELINE/` path.

**Modified in the eighth correction commit `834fa35`** (**hash filled in
now that it exists, ninth-pass review**; its path set was already stated
correctly here before it existed — the eighth-pass structural fix held):
`baseline_v637_audit.md`, `baseline_comparison.md`,
`TASK-001_BASELINE_AUDIT.md`, overwrote
`09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place, and added
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round8.md`. Did
**not** touch `baseline_v811_audit.md`, `TASKS.md`, or any `01_BASELINE/`
path.

**Modified in the ninth correction commit `acb8e45`** (**hash filled in now
that it exists, tenth-pass review**; its path set was already stated
correctly here before it existed): `baseline_v637_audit.md`,
`TASK-001_BASELINE_AUDIT.md`, overwrote
`09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place, and added
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round9.md`. Did
**not** touch `baseline_v811_audit.md`, `baseline_comparison.md`,
`TASKS.md`, or any `01_BASELINE/` path.

**Modified in the tenth correction pass** (hash not embedded here —
unknowable at authoring time; **locator corrected in tenth-pass review to
be durable rather than a moving target** — see the first commit after
`acb8e45` in `git log --oneline claude/task-001-baseline-audit`, since
"current branch tip" wording goes stale the moment a further commit is
made): `baseline_v637_audit.md`, `baseline_v811_audit.md`,
`baseline_comparison.md`, `TASK-001_BASELINE_AUDIT.md`, overwriting
`09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place, and adding new
file `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round10.md`.
Not touching `TASKS.md` or any `01_BASELINE/` path.

**Precision correction, third-pass review, evidence-per-artifact separated in fifth-pass review (the EA-directory diffs below verify only the two `.mq5` files, not the set file or screenshots — an earlier draft cited them for all three together):** the claim "no file
under `01_BASELINE/` was modified" is accurate for the *preserved baseline
artifacts* specifically, verified by three separate checks: both `.mq5`
files via `git diff <tag> -- 01_BASELINE/EA_V637` / `-- 01_BASELINE/EA_V811`
staying empty after every commit; the set file via its SHA-256 (recorded in
`inventory.md`) and Git blob-ID equality at the preservation tags (see
Evidence section above); and all 13 screenshots via their individually
recorded SHA-256 hashes in `inventory.md`, unchanged across every commit.
It is **not** accurate as a claim that no commit
touched anything under the `01_BASELINE/` path at all: the initial commit
(`c61903f`) **added** two new files there — `01_BASELINE/inventory.md` and
`01_BASELINE/screenshots/visual_notes.md` — as new audit documentation
alongside the preserved evidence, not as edits to it. `git diff
<baseline-tag> -- 01_BASELINE` (unscoped to the EA subdirectories) is
therefore *not* empty. **Closing statement corrected in sixth-pass
review** — the scoped per-EA-subdirectory diffs verify only the two
`.mq5` files' immutability specifically; they are not, by themselves, the
complete evidence this task relies on. Full artifact immutability is the
combination of all three checks named above (EA-source diffs, set-file
hash/blob-ID equality, screenshot hashes) — see Test plan.

## Out of scope

- No trading-code changes of any kind.
- No new architecture files under `03_SOURCE_CODE/`.
- No specification documents beyond the giveback *plan* (not a diagnosis —
  no trade data exists yet to diagnose from).
- No compilation or backtesting — nothing here is code.

**Note (C3, stale text removed per independent review):** an earlier draft
of this section stated "no actual Codex review execution" as an out-of-scope
item. That is no longer accurate — Codex has since reviewed this package
multiple times (**pass count no longer restated here as of seventh-pass
review, to stop this exact note going stale every round — see Acceptance
criteria above for the current count**); review execution itself happened
in a separate Codex session/branch per `AGENTS.md`, but it did occur, and
is not out of scope for this task's final state.

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
  happened repeatedly (**pass count no longer restated here as of
  seventh-pass review, for the same reason as the Out-of-scope note above —
  see Acceptance criteria for the current count**), each pass catching real
  precision issues the prior pass missed, including false claims introduced
  by the correction responses themselves on more than one occasion. This
  remains listed as a risk category because a further pass cannot be ruled
  out as still finding something,
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

- [x] All deliverables listed under "Files affected" exist. **Corrected in
      fifth-pass review** — the original wording of this criterion claimed
      "same file list, same status, across `TASKS.md` and this task file,"
      which is not actually true and was a false claim to have checked:
      `TASKS.md` is a one-row-per-task summary ledger and does not contain,
      and was never meant to contain, a matching per-file deliverable list —
      that level of detail lives only in this task file's "Files affected"
      section.
- [x] Both baseline `.mq5` files, screenshots, and set file are unchanged
      (hash match).
- [x] Every master-prompt section-4 checklist bullet, both EAs, has a
      cited, line-numbered entry in the respective audit document.
- [x] Orphaned set-file provenance question is resolved (or explicitly
      documented as unresolved with reasoning) in `baseline_comparison.md`.
- [x] Profit-giveback document is a plan, not a diagnosis (no trade data
      exists to diagnose from).
- [ ] Independent Codex review completed and findings resolved.
      **STRUCTURAL FIX, sixth-pass review: this bullet is now the single
      canonical statement of review status for the whole document.**
      Three consecutive rounds (four, five, six) tried to independently
      restate this same status in the Acceptance/Reviewer/Final-Decision/
      `TASKS.md` sections and each time produced prose that disagreed in
      tense or detail — not because the underlying facts were unclear, but
      because four independently-written paraphrases of the same fact drift
      from each other. As of this round, Reviewer and Final Decision below
      no longer restate this status — they point here. `TASKS.md`'s one-line
      ledger entry is intentionally terse and generic rather than
      attempting to mirror this level of detail, for the same reason.

      **Status:** ten review passes so far, all returning changes
      requested, each narrower than the last:
      - Pass 1 → addressed in commit `3f69469`.
      - Pass 2 (internal-consistency gaps between corrected detail and
        stale summaries, plus precision fixes) → addressed in `4a6946b`.
      - Pass 3 (further precision gaps, two false claims in the round-two
        response file) → addressed in `538bc39`.
      - Pass 4 (further precision gaps: the ROTATION dashboard-visibility
        condition stated wrong twice, a wrong cross-EA RSI generalization,
        a persisted-drawdown overclaim, stale momentum-vs-expansion
        framing, an unfixed `inventory.md` inconsistency) → addressed in
        `c73947b`.
      - Pass 5 (further precision gaps: a mislabeled design-note source, an
        RSI-fallback claim that didn't hold for one of two entry paths, a
        remaining "true historical maximum" drawdown overclaim, two more
        stale momentum-vs-expansion locations, a wrong commit-attribution
        in `inventory.md`, an ambiguous SHA-256-vs-Git-blob-ID claim, a
        miscounted "three hash follow-ups," and a false status-alignment
        claim) → addressed in `683bc77`.
      - Pass 6 (an unsupported maintenance-cause inference, a missing
        Strategy Tester qualifier on four `g_peak_dd` persistence mentions,
        a taxonomy mismatch in a comparison-doc heading, minor prose/
        citation cleanup, and — again — a false status-alignment claim,
        which prompted the structural fix applied that round) → addressed
        in `8a88389`.
      - Pass 7 (a false RSI-threshold citation this audit itself introduced
        while fixing a prior finding, unproven process-history/"unreviewed"
        inferences, two stale cross-references to a renamed section, the
        canonical status text itself being stale — pass 6 already applied
        but still described as "in progress" — a reintroduced false
        "three hash follow-ups" claim, an unsupported "path typo"
        description of `7319306` introduced in the round-six response, and
        incomplete Files-affected/Commit/Reviewer-chain entries for the
        sixth correction pass) → addressed in `9a1948c`.
      - Pass 8 (an incomplete RSI-threshold inventory still missing the
        sell-side `70.0` value despite the same paragraph citing it
        correctly two sentences later, unsupported refactor/supersession
        history at two more locations, "independently-written" implying an
        authorship claim the source doesn't support, the canonical status
        again describing an already-applied pass as "in progress," and
        Files-affected/Commit/Reviewer-chain entries one pass behind again)
        → addressed in `834fa35`.
      - Pass 9 (a V6.37 journal-history claim outside the round-eight edit
        locations — `InpJournalFileName` described as "hard-set" when it is
        a configurable input, an unconditional "clean slate" claim treated
        as FACT when it is COMMENT-CLAIMED and conditional, an unsupported
        "different column semantics" risk for same-version instances, an
        unqualified `FILE_COMMON`-sharing claim not conditioned on matching
        configured filenames, an overstated "zero occurrences" grep claim
        in the round-eight response, and — for the third round running —
        the canonical status describing an already-applied pass as "in
        progress") → addressed in `acb8e45`.
      - Pass 10 (a remaining unsupported universal schema-mismatch
        sentence, a narrowed duplicate-row conclusion and expanded
        concurrent-file-access risk (missing `FILE_SHARE_READ`/
        `FILE_SHARE_WRITE`, silent open failures, a duplicate-header race),
        a Reviewer chain one pass behind despite the round-nine response
        claiming it was current, a moving-tip locator claimed as timeless,
        a regime-bench "permanent fixed point" overclaim, a V6.36
        stop-history claim treated as FACT when only comment-claimed, a
        stop-floor/cap "incompatible units, never cross-validated"
        mischaracterization, a peak-R "cleaned up on every close" overclaim,
        a pilot-risk "objectively higher" overclaim, a binomial-probability
        arithmetic error, stale `HasFreshStructureShiftMomentum` call-site
        citations, a V8.11 `RiskBudgetCash` mischaracterized as a third
        peak-drawdown definition, a V8.11 magic-number "hard-coded"
        overclaim, an unqualified basket-risk-cap claim, a non-exhaustive
        45-minute exit description, and an all-nine-passes
        independently-reconfirmed process-history overclaim) → **applied in
        the current symbolic correction commit; pending review**.

      **Overclaim corrected in tenth-pass review:** the BLOCKER (V6.37's
      completed-candle violation in `IsBullishInsideFalseBreak`/
      `IsBearishInsideFalseBreak`) and the cross-cutting findings (netting/
      hedging compatibility, trade-result handling, broker filling/stop/
      tick-size validation, restart idempotency) were established by
      independent review and have remained carried forward and unresolved
      across the subsequent passes — it is not accurate that all nine passes
      *independently re-confirmed* them: the first review pass established
      these findings; several later passes were deliberately narrow,
      item-by-item checks of the latest response and did not re-run the full
      blocker/account-mode/result/broker/restart analysis each time. Not
      checked off until a review pass returns approval rather than
      changes-requested.

## Rejection criteria

This task would be rejected if: any **preserved** `01_BASELINE/` artifact
(either `.mq5` file, the set file, or any of the 13 screenshots) were
modified — **narrowed in fifth-pass review**: the literal, unqualified
criterion "any `01_BASELINE/` file were modified" is not what this task
actually rejects on, and taken literally would be triggered by this task's
own intentional addition of `01_BASELINE/inventory.md` and
`01_BASELINE/screenshots/visual_notes.md` as new audit documentation; any
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

**Filled in per independent review (C5), updated for completeness across
subsequent passes — commit history on this branch below. Structural note,
fourth-pass review: this list is deliberately not framed as "the complete
history through current HEAD," since that framing is itself recursive —
each new correction commit changes what "current HEAD" means, which is
exactly the self-reference problem that produced **two** dedicated
follow-up hash-recording commits in earlier rounds (`7319306` and
`79f8e5a` — **count corrected in fifth-pass review, was previously
miscounted as three**; `3f69469` was a substantive first correction commit
addressing Codex's actual review content, not a dedicated hash-recording
follow-up, even though it's also listed below). For the actual current
tip, run `git log --oneline claude/task-001-baseline-audit`.**

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
   and completing/clarifying that entry's response-file path (**"path
   typo" description corrected to this in seventh-pass review — the
   original diff shows no typo fix**). Reviewed by Codex a third time;
   disposition
   **changes requested a third time** (narrower still — most items
   verified, a handful of remaining internal-consistency gaps, two false
   claims in the round-two response file, and several precision fixes).
5. `538bc39` — third correction-pass commit, responding to Codex's third
   review. Touched the same four documents plus `TASKS.md`; overwrote
   `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place again; added
   `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round3.md`.
6. `79f8e5a` — follow-up commit, `TASK-001_BASELINE_AUDIT.md` only, filling
   in the `538bc39` hash (**omitted from this list until now — exactly the
   kind of gap this section's structural fix, above, is meant to prevent
   going forward**). Reviewed by Codex a fourth time; disposition
   **changes requested a fourth time** (narrower still — most items
   verified, remaining precision issues in the ROTATION-visibility
   condition, cross-EA RSI synthesis, persisted-drawdown wording, momentum-
   vs-expansion framing, and package metadata, including this section's
   own recursive-hash problem).
7. `c73947b` — fourth correction-pass commit (**hash filled in now that it
   exists in history — the symbolic-reference approach applies only to
   describing the commit currently being made, not to past commits, which
   can and should just be cited directly**), responding to Codex's fourth
   review. Touched the same documents plus `01_BASELINE/inventory.md` (see
   Baseline-behaviour section above for why this one preserved-directory
   file needed a correction) and added
   `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round4.md`.
   Reviewed by Codex a fifth time; disposition **changes requested a fifth
   time** (narrower still — most items verified, remaining precision
   issues in the ROTATION source-note name and citations, the V6.37 RSI-
   fallback claim for its compound entry expression, persisted-drawdown
   wording, momentum-vs-expansion classification consistency, an
   `inventory.md` commit-attribution error, an ambiguous SHA-256-vs-blob-ID
   claim, a miscounted hash-follow-up total, and a false claim of
   cross-section status alignment).
8. `683bc77` — fifth correction-pass commit (**hash filled in now that it
   exists — path-completed in sixth-pass review**, an earlier draft of this
   entry omitted the overwritten Codex review file from its path list).
   Touched all eight paths: `baseline_v637_audit.md`,
   `baseline_v811_audit.md`, `baseline_comparison.md`,
   `TASK-001_BASELINE_AUDIT.md`, `TASKS.md`, `01_BASELINE/inventory.md`,
   overwrote `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place,
   and added `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round5.md`.
   Reviewed by Codex a sixth time; disposition **changes requested a sixth
   time** (narrower still — most items verified, remaining issues an
   unsupported maintenance-cause inference, a missing Strategy Tester
   qualifier on four `g_peak_dd` mentions, a comparison-heading taxonomy
   mismatch, minor prose/citation cleanup, and — again — a false
   status-alignment claim, which prompted the structural fix in this
   section rather than another prose attempt).
9. `8a88389` — sixth correction-pass commit (**hash filled in and path
   list completed, seventh-pass review**). Touched exactly seven paths:
   `baseline_v637_audit.md`, `baseline_v811_audit.md`,
   `baseline_comparison.md`, `TASK-001_BASELINE_AUDIT.md`, `TASKS.md` (now
   a stable, pass-count-independent entry), overwrote
   `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place, and added
   `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round6.md`.
   Reviewed by Codex a seventh time; disposition **changes requested a
   seventh time** (narrower still — most items verified or resolved
   (Strategy Tester qualification, status-pointer architecture), remaining
   issues a false `65.0` RSI-threshold citation this audit introduced
   while fixing a prior finding, unproven process-history/"unreviewed"
   inferences, two stale cross-references to a renamed section, the
   canonical status text itself being stale, a reintroduced false
   "three hash follow-ups" claim, an unsupported "path typo" description of
   `7319306`, and incomplete Files-affected/Commit/Reviewer-chain entries
   for this very commit).
10. `9a1948c` — seventh correction-pass commit (**hash filled in and path
    list completed, eighth-pass review**). Touched exactly five paths:
    `baseline_v637_audit.md`, `baseline_comparison.md`,
    `TASK-001_BASELINE_AUDIT.md`, overwrote
    `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place, and added
    `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round7.md`. Did
    **not** touch `baseline_v811_audit.md` or `TASKS.md`. Reviewed by Codex
    an eighth time; disposition **changes requested an eighth time**
    (narrower still — most items verified or resolved (the `65.0`
    misclassification, the two comparison cross-references, the `7319306`
    history, the duplicated numeric review counts), remaining issues an
    incomplete RSI-threshold inventory missing the sell-side `70.0` value,
    unsupported refactor/supersession history, "independently-written"
    implying an unsupported authorship claim, the canonical status one
    pass behind again, and the package-history entries recreating the
    same one-pass lag they were just fixed for).
11. Eighth correction-pass commit, `834fa35` (**hash filled in now that it
    exists, ninth-pass review**) — responding to the eighth review. Its
    exact path set is not restated here; this entry **references** the
    canonical five-path list already stated above in "Files affected"
    (predicted before the commit existed, since the file list was knowable
    even though the hash was not) — Codex's ninth review noted the prior
    wording here read as an independent restatement rather than a pointer,
    which is the same cross-section-drift risk the sixth-pass structural
    fix exists to avoid. Reviewed by Codex a ninth time; disposition
    **changes requested a ninth time** (narrower still — most items
    verified or resolved (the complete 30/50/70 RSI inventory, the
    refactor/supersession/authorship wording, the one-pass-lag structural
    fix itself), remaining issues a V6.37 journal-history conclusion the
    configurable filename doesn't support, the canonical status again
    describing already-applied pass-8 work as in progress, and two minor
    package-history/verification-wording cleanups).
12. Ninth correction-pass commit, `acb8e45` (**hash filled in now that it
    exists, tenth-pass review**) — responding to the ninth review. This
    entry likewise references, rather than restates, the ninth-pass path
    list already stated above in "Files affected." Reviewed by Codex a
    tenth time; disposition **changes requested a tenth time** (narrower on
    the requested journal/status items — most resolved (the configurable-
    filename and clean-slate corrections, the pass-8/9 status tense) —
    but Codex's independent full-package sweep found several further
    source-factual errors elsewhere in both audits and the comparison that
    the ninth-pass response had not been asked to check: see Acceptance
    criteria pass 10 below for the complete list).
13. Tenth correction-pass commit (hash not embedded here — unknowable at
    authoring time; **locator corrected in tenth-pass review to be durable
    rather than a moving target** — Codex noted "current branch tip"
    wording goes stale the moment a further commit is made, exactly like
    the tense problem this same fix pattern solved for canonical status
    prose; see the first commit in `git log --oneline
    claude/task-001-baseline-audit` *after* `acb8e45`) — responding to this
    tenth review. This entry likewise references, rather than restates, the
    tenth-pass path list already stated above in "Files affected."

**Precision correction, third-pass review, per-artifact evidence separated in fifth-pass review:** "no file under `01_BASELINE/` is
touched by any commit in this history" was inaccurate as stated — see the
identical correction and its full reasoning under "Files affected" above.
The accurate, verified claim is that the *preserved baseline artifacts* are
unmodified by every commit above, evidenced separately per artifact type:
both `.mq5` files via scoped `git diff <tag> -- 01_BASELINE/EA_V637` /
`-- 01_BASELINE/EA_V811` (empty throughout); the set file via SHA-256 and
Git blob-ID equality (see Evidence section); all 13 screenshots via
individually recorded SHA-256 hashes in `inventory.md`. Separately,
`01_BASELINE/inventory.md` and `01_BASELINE/screenshots/visual_notes.md`
were intentionally added as new audit documentation in commit 1
(`c61903f`) — a different, later commit than the one that introduced the
baselines (`0d65f95`).

## Reviewer

Codex. **Current pass-by-pass status: see the Acceptance criteria section
above (the single canonical status statement as of the sixth-pass
structural fix) — not restated here to avoid the cross-section drift that
failed three rounds running.**

Handover/response file chain (factual record of what was exchanged, not a
status claim): `09_HANDOVERS/claude_to_codex/TASK-001_handover.md` →
`09_HANDOVERS/codex_to_claude/TASK-001_review.md` (updated in place for
each subsequent pass) →
`09_HANDOVERS/claude_to_codex/TASK-001_review_response.md` →
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round2.md` →
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round3.md` →
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round4.md` →
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round5.md` →
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round6.md` →
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round7.md` →
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round8.md` →
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round9.md` →
`09_HANDOVERS/claude_to_codex/TASK-001_review_response_round10.md`
(**chain corrected in tenth-pass review to actually include round 9 —
Codex's tenth review found this chain still ending at round 8 despite
`acb8e45` already having added the round-9 response file, which directly
falsified the round-9 response's own claim that this chain was current;
round 10's filename is stated now, before its commit exists, per the
eighth-pass structural fix above**).

## Final decision

**Status: see the Acceptance criteria section above.** This section
states only the decision, not a restatement of pass-by-pass status (same
reasoning as Reviewer above). Per `00_MASTER_PROMPT_FOR_CLAUDE.md` section
21 (release gates), this branch needs Codex to confirm the corrections
resolve the disposition before `main` merge is considered, and merge must
not be performed by the same agent that produced the audit.
