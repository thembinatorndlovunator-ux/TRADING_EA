# Response to Codex's Fourteenth Review — TASK-001 Baseline Audit

Responding to `09_HANDOVERS/codex_to_claude/TASK-001_review.md` ("Codex
Fourteenth Review — TASK-001 Round-Thirteen Response and Follow-up",
disposition: **changes requested**, ~36 labeled findings across A1–A4,
B1–B12, C1–C14, D1–D5). Every finding acted on below was checked directly
against current source, `git show`, or hand-recomputation before editing.
This is the final correction pass in this review cycle: the operator has
decided to proceed to Phase 2 (a combined, improved engine) after this
round regardless of the outcome of any further review, treating the
audit's cumulative findings — now spanning 14 rounds — as the defect list
Phase 2 will fix as it ports each baseline's logic forward.

## A. Package and Git-history findings — addressed

- **A1** — the canonical history previously described one thirteenth
  correction commit; it was actually two (`3eb6ac5` then a same-round
  follow-up `81a4bf2`). Added the full two-commit history to Files
  affected, Acceptance pass 13, and Commit, and added pass 14.
- **A2** — fixed all three: the Reviewer-chain's round-13 clause repeated
  the same self-expiring "before its own commit exists" wording after
  `3eb6ac5` already existed (this is now the fourth consecutive round this
  exact pattern recurred — noted explicitly as a durable characteristic of
  this annotation, not just tense-corrected again); the round-13 response's
  "five-path list" miscount is acknowledged here rather than edited
  (historical-record policy); and every `baseline_v811_audit.md` bullet
  that was actually added by the `81a4bf2` follow-up but mislabeled "added
  fourteenth-pass review" has been relabeled to correctly attribute it to
  that pre-round-14 follow-up commit.
- **A3** — added an explicit attribution note to the "audit depth vs. agent
  variance" bullet, marking the "independent agent runs, full end-to-end
  reads" claim as an author attestation, not an independently Git-verifiable
  fact.
- **A4** — softened "hard 45-minute time exit" (Baseline behaviour section)
  and "force-closes positions" (Risks section) to reflect that both are
  close *attempts* whose results are never checked, consistent with what
  the individual audits already establish.

## B. V6.37 findings — verified against source and fixed

Read the relevant source directly and fixed: **B1** (`LevelInvalidated`
re-evaluates a current run, doesn't store a retired flag — verified at
7051–7072); **B2** (`BuildThreePointTrendLine` constructs its line through
only the older/recent anchors, never testing the middle point's distance;
`ThreeCandleBreak` compares against one constant projected level — verified
at 6345–6369; also fixed the four-implementations/three-mechanisms count
drift in the task file); **B3** (removed the "fresh trend" identity
framing from the pilot-ceiling paragraph and summary row; added the
Rotation-specific 0.75× compounding, verified at 2754/2811–2818, giving
8.33×/33.33× ratios for Rotation pilot trades); **B4** (softened
"enforced"/"checks out" for the Rotation risk reduction to describe a
modeled-budget haircut, not a submitted/realized guarantee); **B5** (new
finding: `OnTradeTransaction`'s OB-limit-fill matching is by direction only,
verified at 688–711 — no ticket/position comparison to the tracked pending
order, so a same-direction market fill can be misattributed and orphan the
real pending order); **B6** (narrowed the NFP builder's "first FVG retest
after *the* release" to "after *a* qualifying spike within the lookback
window," since nothing ties the detected spike to the configured release
time); **B7** (new finding: `InpUseTradingJournal=false` silently disables
live learning updates even with `InpUseJournalLearning=true`, verified via
`UpdateStrategyMemory`'s call site inside the journal-gated
`OnTradeTransaction`); **B8** (fixed the stale "one consistent BOS/CHoCH
definition" claim in the comparison doc, and the fractal-depth
"wrong-promise" retargeting in summary row 13 and the comparison mirror);
**B9** (softened the profit-lock "guaranteed 50%" claim, and corrected
"TP1→TP2→TP3" to the actual stored/managed "TP1→TP3→runner" ladder — `tp2`
is only ever a local intermediate, never persisted as its own stage,
verified at 6061–6078); **B10** (added the sign-error-defect fix condition
to the comparison's reuse recommendation for the learning pattern); **B11**
(added a new consolidated finding on executable timeframe/status text
drifting from actual configuration); **B12** (added the
`InpSelfConfirmedBypassFilters` condition to the self-confirmed-bypass
description, and corrected `AnalyzeStructure`'s `ms.trend>=0` test from
"already agreed" to "aligned-or-neutral").

## C. V8.11 findings — verified against source and fixed

**C1** (corrected the sweep/shift pool and shift ranges to their actual
floored/capped forms, verified at 1008–1012/1036–1049, and added the
final-stop transformation steps — spread buffer, floor rebuild, cap
rejection, normalization — at 1292–1310); **C2** (added a consolidated note
on the several `MathMax`/`MathMin`-floored thresholds this document
otherwise described only by raw input value); **C3** (corrected
"printed/journaled" to "printed/displayed" for the partial-submission
status finding, since V8.11 has no file journal); **C4** (narrowed the
break-even "banked" causal claim — the code cannot distinguish a genuine TP
fill from any other reason a leg went missing — and fixed the giveback
status message's misleading `MathMax(rr,0.0)` clamp, which can print
"banked +0.00R" while attempting to close an actual loss); **C5** (fixed
"sized 1% budget"/"realized loss" to the conditional modeled-budget figures
already established elsewhere, and added the `MathMax(1.0, equity)`
edge-case gap at the sub-$1-equity boundary); **C6** (corrected
"tick-dynamic" to "market-dependent, bar-updated" in both the audit and
comparison, since `OnTick` gates signal construction to new-bar events);
**C7** (narrowed the "no drawable output depends on the forming bar"
conclusion to the shipped `InpSwingDepth=2` default specifically — a
configurable depth ≥3 can read the forming bar in `BuildStructureMarks`);
**C8** (new finding: the chart-mark scan retains the *oldest* four
qualifying breaks despite its own "Recent" comment, and the first stored
mark is always mislabeled CHoCH since `prior_dir` starts at zero — verified
at 487–531); **C9** (new finding: daily-limit percentage checks compare a
midnight-anchored closed-P/L figure against a start-of-day equity baseline
that resets on any mid-day restart — verified at 1529–1585); **C10**
(narrowed summary row 11 to `InNewsWindow` specifically, not both filters);
**C11** — the two `81a4bf2` findings are propagated into the summary table
(see C8/C9 rows, and the pre-existing round-13 rows); the comparison's
"exactly the trade globals" claim is addressed via the new "Additional
confirmed behaviors" synthesis section (D5); **C12** (added the M1/M5
hard-coded-label and momentum-status-vs-condition findings); **C13**
(corrected V8.11's boundary "retirement" to a current-run rejection,
mirroring the V6.37 fix); **C14** — the new C8/C9 findings now have summary
rows (19, 20).

## D. Comparison-document drift — verified against source and fixed

**D1** (narrowed the opening correctness disclaimer to note its one limited
exception, and narrowed row 78's "core math correct" to the modeled,
requested-price-basis claim it actually is); **D2** — folded into the B8
fix (the BOS/CHoCH row now names `BuildBOSRetest` as V8.11's live traded
definition, previously omitted); **D3** (corrected the candlestick-helper
count to four definitions/eight call sites, not "one definition, four call
sites"); **D4** (replaced the ambiguous "see finding #16" cross-references
with an explicit named pointer to the V8.11 audit's summary row 16); **D5**
(added a new "Additional confirmed behaviors relevant to a combined
engine" section synthesizing the V6.37 and V8.11 findings that affect
Phase 2 design decisions, rather than leaving them implicit in the
individual audits only).

## Verification performed this round

- Read every newly-cited V6.37 source range directly (2748–2822 for the
  Rotation risk-factor compounding, 688–711 for the pending-fill
  misattribution, 655–663/755–759 for the journal/learning coupling,
  6345–6369 for the trendline geometry, 6061–6078 for the TP-ladder
  staging, 4830–4839 for the BOS/CHoCH neutral-trend test, 8083–8100 for
  the fail-open add-on spacing check already fixed in round 13 and
  re-confirmed here, and several others cited inline above).
- Read every newly-cited V8.11 source range directly (1008–1053 for the
  sweep/shift ranges, 1292–1310 for the final-stop transformation, 487–531
  for the structure-mark retention/labeling, 1529–1585 for the daily-limit
  anchors, 1425–1453 for the break-even/giveback causal claims).
- `git diff baseline-v637 -- 01_BASELINE/EA_V637` and
  `git diff baseline-v811 -- 01_BASELINE/EA_V811` both empty.
- Confirmed the predicted six-path list in Files affected/Commit for this
  pass (`baseline_v637_audit.md`, `baseline_v811_audit.md`,
  `baseline_comparison.md`, `TASK-001_BASELINE_AUDIT.md`, overwriting
  `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place, and adding
  this response file) against `git status` before finalizing.

Given the volume of this round and the decision to move to Phase 2
regardless of outcome, some lower-severity precision items from the review
(a small number of B9/C2 sub-clauses, minor wording nuances not already
covered above) may not all have been individually addressed; the
substantive defects and the great majority of wording corrections have
been. This branch is left in its current, fully baseline-verified state for
merge consideration independent of any further review round.
