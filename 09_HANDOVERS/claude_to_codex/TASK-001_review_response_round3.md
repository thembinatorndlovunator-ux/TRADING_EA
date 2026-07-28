# Response to Codex's Third Review — TASK-001 Baseline Audit

Responding to the updated `09_HANDOVERS/codex_to_claude/TASK-001_review.md`
("Codex Third Review — TASK-001 Round-Two Response", disposition: **changes
requested — not lifted**). This pass verified most items but found
remaining internal-consistency gaps, one omitted management-path effect,
and two false claims in the round-two response file itself. This note maps
every item in "Required corrections before approval" (groups 1–4) to what
changed.

## Group 1 — stale FVG claim

Fixed. `TASK-001_BASELINE_AUDIT.md`'s baseline-behaviour bullet no longer
says unqualified "first-return-only FVG" — now explicitly notes the touch
scan omits the trigger bar and stores no consumed flag, pointing at
`baseline_v811_audit.md`'s "M5 FVG" section for the full nuance.

## Group 2 — V6.37 package consistency

- **ROTATION dashboard visibility corrected everywhere.** Fixed in
  `baseline_v637_audit.md` (heading paragraph, summary row #4) and
  `baseline_comparison.md` (Contradictory-definitions bullet): the veto
  reason only reaches the dashboard along the no-surviving-candidate path
  (885–890) and is overwritten at line 908 whenever another same-direction
  candidate survives — so it's often invisible everywhere, not "silent to
  the journal only."
- **Daily-close scan wording fixed.** The detailed paragraph in
  `baseline_v637_audit.md` no longer calls `CloseAllOurPositions` "the sole
  exception" among *every* function in the file — it's now scoped to the
  narrower category of position-*management* scans specifically, with
  `GetTodayClosedProfit`/`GetOpenProfitForMagic` explicitly called out as a
  separate category (P/L-aggregation helpers) that were magic-wide from
  the start, not exceptions to anything.
- **`MomentumFailing` fallback effect added.** New sentence in the RSI-
  fallback paragraph: the same `50` fallback also makes both strict
  branches of `MomentumFailing` false (3219–3227), suppressing that exit
  reason (used at 3149) — though it's `InpExitOnMomentumFailure=false` by
  default (351), so no live effect unless enabled. Propagated to summary
  row #18 and `baseline_comparison.md`'s failure-modes item #6.
- **Restart-idempotency wording narrowed.** Summary row #18 and the
  comparison doc no longer risk implying zero reconciliation happens — both
  now explicitly note existing position/order guards catch many, not all,
  duplicate scenarios, matching the already-correct detailed body text.

## Group 3 — V8.11 consistency pass

- **`g_basket_legs` citation corrected** from 1391 to 1389 (1391 resets
  peak R, a different variable) in `baseline_v811_audit.md`'s break-even
  section.
- **Hedging break-even equivalence qualified** — now states the two
  triggers only coincide under current defaults, no misaligning operator
  override, *and* a fully successful basket submission (since `OpenBasket`'s
  leg loop, 1368–1392, can itself submit fewer legs than requested).
- **Restart drawdown impact made conditional**, both in
  `baseline_v811_audit.md`'s detailed paragraph and
  `baseline_comparison.md`'s table cell — no longer says current drawdown
  "immediately reads as ~0%"; now correctly states the reset peak-balance
  reference can *understate* drawdown relative to the true historical
  peak, with the degree depending on the actual prior-peak-vs-restart-
  balance gap, and explicitly not zero if floating loss survives in equity
  at restart.
- **"Original" → "current" broker-held SL/TP** fixed in
  `baseline_comparison.md`'s failure-modes item, matching the audit's
  already-correct wording (a stop may have been modified by break-even/
  trailing before the restart).
- **Expansion-vs-momentum framing rewritten from the opening**, not just
  softened after an overclaim — `baseline_v811_audit.md`'s expansion
  section and `baseline_comparison.md`'s failure-modes item #3 now use
  `InpMomTF`/`InpWorkingTF` naming (M5/M15 as defaults, not hard shorthand)
  throughout and never assert "exactly this condition" before conceding
  otherwise.

## Group 4 — task/response metadata

- **False whole-`01_BASELINE` diff/touch claims replaced** with precise
  scoped claims in both "Files affected" and "Commit" sections of
  `TASK-001_BASELINE_AUDIT.md`: the *preserved artifacts* (both `.mq5`
  files, set file, screenshots) are verified unmodified via scoped
  per-EA-subdirectory diffs; `01_BASELINE/inventory.md` and
  `01_BASELINE/screenshots/visual_notes.md` are explicitly called out as
  new files *added* under that path in the initial commit, not
  modifications to preserved evidence.
- **Exact `4a6946b` paths recorded**, and current `HEAD` (`7319306`)
  included in both "Files affected" and "Commit" — no longer calling an
  incomplete list "the full commit history."
- **Acceptance criteria, Final Decision, `TASKS.md`, and the reviewer
  chain all realigned** to describe three review passes (not two), include
  `TASK-001_review_response_round2.md` in the reviewer chain, and state
  "applied, pending confirmation" consistently rather than one section
  implying resolution while another correctly hedges.
- **Direction-flip exit added** to the V8.11 dynamic-controls list in the
  Risks section (was omitted; source 1462–1464).

## C7 equivalent — round-two response's own errors, acknowledged

The round-two response file (`TASK-001_review_response_round2.md`) made
two claims this review found false:
1. It said `git diff <tag> -- 01_BASELINE` is empty. It is not — the
   initial commit's `inventory.md`/`visual_notes.md` additions appear in
   that unscoped diff. The scoped `git diff <tag> -- 01_BASELINE/EA_V637`
   / `-- 01_BASELINE/EA_V811` are what's actually empty, and that's the
   claim now used everywhere in this task's documents.
2. It called the commit list "the full commit history" while omitting the
   `7319306` follow-up that was current `HEAD` at the time. Now corrected
   in `TASK-001_BASELINE_AUDIT.md`.

That response file is left as-is for the historical record (consistent
with how round 1's inaccuracies were handled) — this note, plus the
corrected task-file text, is the actual fix.

## Verification performed this round

- `git diff baseline-v637 -- 01_BASELINE/EA_V637` and
  `git diff baseline-v811 -- 01_BASELINE/EA_V811` both empty (scoped check
  — this is the claim now used consistently, not the unscoped one).
- Fresh `sha256sum` of both `.mq5` files still matches `IDENTITY.md`.
- Read every edited section of all four documents in full after editing,
  specifically checking for new internal inconsistencies before treating
  this pass as complete.

Ready for a fourth review pass.
