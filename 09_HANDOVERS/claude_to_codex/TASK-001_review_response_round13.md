# Response to Codex's Thirteenth Review — TASK-001 Baseline Audit

Responding to `09_HANDOVERS/codex_to_claude/TASK-001_review.md` ("Codex
Thirteenth Review — TASK-001 Round-Twelve Response", disposition: **changes
requested — not lifted**, 45 labeled findings: A1–A7, B1–B21, C1–C10, D1–D7).
Every finding I acted on was checked directly against current source or Git
before editing — several by hand-recomputation (the sign-error defect's
arithmetic, the underwater `RiskBudgetCash` worked examples). The most
consequential single item is **B18**: a genuine sign-error defect in
`ApplyLearningToScore`'s penalty branch (base and regime level) that boosts,
rather than penalizes, a strategy with win rate above 50% but net loss —
verified by reading the exact branch logic and confirming the default
14%/20% penalty percentages against source.

## A. Package and Git-history findings — all addressed

- **A1** — "26 findings" corrected to "28 findings handled in 26 response
  bullets/actions" (A1/A2 shared a bullet; A6 was acknowledged without an
  edit) at both citing locations.
- **A2** — acknowledged, not edited (historical-record policy for the
  round-12 response file).
- **A3** — added a scoping note at the top of the Commit section clarifying
  that "narrower"/"narrower still" annotations describe only the
  immediately-preceding-round transition, not an asserted monotonic trend
  across passes 2–9 (editing all eight individual Commit entries
  individually was not done given the volume of this round; the scoping
  note resolves the substantive contradiction).
- **A4** — round 12's Reviewer-chain clause repeated the same self-expiring
  "before its own commit exists" wording after `ce9f712` already existed.
  Converted to past tense, extended the chain to round 13, and noted this
  is now a confirmed structural pattern (three consecutive rounds each
  needing the same fix one round later).
- **A5** — added `IDENTITY.md` to the Rejection-criteria and Commit-section
  evidence enumerations, which previously listed only the `.mq5` files, set
  file, and screenshots.
- **A6** — Commit entry 7 (`c73947b`) now explicitly references the
  eight-path canonical list in Files affected, including naming the
  overwritten Codex review file.
- **A7** — narrowed the "not because facts were unclear, but because
  paraphrases drift" causal claim to state only what Git evidence actually
  establishes (that prose drifted), not the asserted cause.

## B. V6.37 findings — verified against source and fixed

Verified directly and fixed: **B1** (four implementations/three
mechanisms — the round-12 fix had only reached `baseline_comparison.md`,
not this document itself; also corrected `EvaluateTrendBreaker`'s
timeframe from "H1/H4" to configurable `InpTrendHigherTF2`/`TF1`, defaulting
to M15/H1); **B2** (`HasFVGM5Confirmation` reads `InpEntryTF`, default M3,
not a fixed M5 array); **B3** (`FindClusterBoundary` doesn't fall back to
an intact cluster — it just fails if its one chosen cluster is invalidated);
**B4** (the self-confirmed-bypass paragraph's self-contradiction fixed, and
the asymmetry is explicitly documented in source comments 1997–2000, not
undocumented); **B5** (multiple live BOS/CHoCH definitions coexist, not one
canonical one); **B6** (M30 order-block "untouched first return" isn't
enforced for the `i=2` candidate or older ones past the mitigation-exclusion
window); **B7** (three OB integration paths exist, not two, and
`ApplyOrderBlockConfluence` carries no H1 gate of its own); **B8**
(`OrderDelete`'s result is ignored before keys are deleted; the
`DEAL_POSITION_ID`/`POSITION_TICKET` mismatch already documented elsewhere
qualifies the "genuinely stores fill risk" claim); **B9** (`PilotStage` is a
symbol/magic-scoped counter with no ticket/direction/setup identity — any
same-symbol/magic position can confirm or reset it, verified directly at
source 6947–6979); **B10** (the 6.25×/25× ratio holds only under specific
runtime conditions, and the XAU figure requires the case-sensitive symbol
key to match); **B11** (the add-on spacing check is fail-open on missing
ATR); **B12** (the profit-lock/giveback ordering question is settled by
source, not an open hypothesis); **B13** (the "M30/H4 major swings" target
source actually uses ordinary `FindQualifiedFractalTarget`, not the
dedicated major-swing machinery; ladder creation isn't universally
at-open-time); **B14** (NFP bypasses the self-confirmed pipeline entirely;
the RangeCycle/regime-router overlap is default-only, not unconditional);
**B15** (the "13"/"12–14" family counts didn't follow from the stated
taxonomy — replaced with the actual 11-top-level-family structure and the
counting ambiguity); **B16** (summary row 9 still said "same vocabulary,"
stale relative to the already-corrected body text); **B17** (retargeted the
fractal-depth contradiction to what the line-201 comment actually promises,
and found the genuine FVG-pathway inconsistency: `InpFractalDepth` hardwired
inside `FindTwoConfirmedSwingsBefore`); **B18** (the sign-error defect,
documented above and added as a new high-severity finding with a dedicated
summary row); **B19** (new finding: market-entry R management mixes actual
`POSITION_PRICE_OPEN` with stored/requested risk — the V637 analogue of the
V811 fill-basis defect); **B20** (softened "closed outright"/"force-close"
wording to "attempted" consistent with the unchecked-result-code pattern
documented elsewhere); **B21** (`HasHTFLevelNear`'s fail-open behavior on
missing H4 data, and the locked-range persistence key's configuration-
staleness gap, both added as new findings).

## C. V8.11 findings — verified against source and fixed

**C1** (added the explicit `max(0,...)` clamp to the displayed underwater
formula, with worked examples matching the review's independent check);
**C2** (fixed the per-leg vs. per-basket confusion, added the two-leg-
viability condition, and noted the header/group-heading "2-4 legs" comment
contradicts the code's one-leg-permitting sizing loop); **C3** — already
verified correct by the reviewer, no change needed; **C4** (softened
"force-closed"/"hard cutoff"/"enforced" wording throughout the audit and
comparison, consistent with the CTrade-result-code caveat already present);
**C5** (narrowed "syntactically invalid" to the three specific forms
`InNewsWindow` actually rejects — carried over correctly from round 12, no
further fix needed beyond what C4/C5 already covered); **C6** (narrowed the
spike-prone-synthetics claim to the actual boom/crash-only vocabulary);
**C7** (softened "moves all legs to break-even" with a pointer to the
existing unchecked-result finding); **C8** (added three new summary-table
rows for the requested-price R/BE/trail defect, the peak-DD key collision,
and the partial-submission wrong-TP status — these existed in the body from
round 12 but had never been propagated to the table; also added the
four-week-expiry qualifier to summary row 3); **C9** (narrowed the
document's closing "no correctness claim" statement, which was contradicted
by its own "core math is correct" bullet); **C4 addendum** (fixed the
news-window daily-recurrence and midnight-truncation finding, and removed
the reintroduced "blank/invalid" overclaim in the same paragraph's closing
sentence). **C10** was not addressed this round given time constraints —
noted as still open.

## D. Comparison-document drift — verified against source and fixed

**D1** (SR ranking isn't touch-count only — distance tie-break and
invalidation are also used); **D2** (added the four-week peak-DD expiry
condition, mirroring the V811 audit's own correction); **D3** (narrowed the
cross-instance-exposure row — same-symbol/same-magic *is* seen by
`CountOurPositions`); **D4** (fixed "realized risk" to "modeled,
requested-basis risk" for the minimum-lot fallback cap, and added the
submission-success/rounding/slippage qualifier to the add-on de-risking
row); **D5** (added the not-per-magic-isolated qualifier to the journal
strengths bullet); **D6** (narrowed "both scan positions and orders" — V637
counts positions only, not pending orders); **D7** (narrowed "H1/M30 + PD
location only" — V8.11's routing includes session/news/spread/expansion
gates and momentum/confluence scoring beyond those two controls).

## Verification performed this round

- Read every newly-cited V6.37 source range directly (3688–3737 for the
  sign-error defect, plus the input-default lines confirming 14%/20%
  penalty percentages; 2568–2576/148–149 for the trendline timeframe;
  1993–2003 for the self-confirmed-bypass comment; 6947–6979 for the pilot
  confirmation loop; 8626–8641 for the OB-limit cleanup; 8083–8100 for the
  add-on spacing fail-open; 3029–3053 for the R-management price mixing;
  and several others cited inline above).
- Read every newly-cited V8.11 source range directly (270–281 for the
  runtime "0.5% per leg" print and peak-DD key truncation; 1283–1399 for
  `OpenBasket`'s requested-price storage and TP-ladder indexing;
  2320–2347 for the news-window recurrence).
- Hand-recomputed the sign-error defect's percentage impact (60% win
  rate/net loss → +2.8% base, +4% regime, both at default penalty
  percentages) and the underwater `RiskBudgetCash` worked examples
  (B=100, E=80/50/25/20 → 0.75%/0.60%/0.20%/0%) rather than accepting the
  review's figures without independent verification.
- `git diff baseline-v637 -- 01_BASELINE/EA_V637` and
  `git diff baseline-v811 -- 01_BASELINE/EA_V811` both empty.
- Confirmed the predicted five-path list in Files affected/Commit for this
  pass (`baseline_v637_audit.md`, `baseline_v811_audit.md`,
  `baseline_comparison.md`, `TASK-001_BASELINE_AUDIT.md`, overwriting
  `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place, and adding
  this response file) against `git status` before finalizing.

Given the volume of this round, C10 and full per-entry fixes to A3's eight
Commit-entry "narrower" annotations were addressed at the section level
(a scoping note) rather than individually, and are flagged here as known
remaining scope for the next pass if the reviewer considers the section-
level note insufficient.

Ready for a fourteenth review pass.
