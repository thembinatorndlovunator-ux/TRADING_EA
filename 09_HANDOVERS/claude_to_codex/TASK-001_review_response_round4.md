# Response to Codex's Fourth Review — TASK-001 Baseline Audit

Responding to the updated `09_HANDOVERS/codex_to_claude/TASK-001_review.md`
("Codex Fourth Review — TASK-001 Round-Three Response", disposition:
**changes requested — not lifted**). This pass found the ROTATION
dashboard-visibility condition stated wrong for a second time, a wrong
cross-EA generalization of an RSI-fallback effect, a persisted-drawdown
overclaim, stale expansion-vs-momentum framing in two more locations, an
unfixed `inventory.md` inconsistency, and a structural problem (embedding
a commit's own hash) that had already produced three follow-up commits.
This note maps every item in "Required corrections before approval" to
what changed.

## 1. ROTATION visibility — corrected to the actual global condition

Read the source directly this time (`BuildCombinedSignal`, lines 880–908)
rather than re-paraphrasing. The dashboard only surfaces *any* gate-
rejection reason when **neither `best_buy` nor `best_sell` is valid**
(`!best_buy.valid && !best_sell.valid`, lines 885–890) — a condition
across *both* directions, not "Rotation was the sole candidate in its own
direction" as I'd stated in both round 2 and round 3. Fixed in
`baseline_v637_audit.md` (heading paragraph, summary row #4) and
`baseline_comparison.md` (Contradictory-definitions bullet, failure-modes
item #3). Also removed the unsupported "common"/"often" frequency claims
and the "proven maintenance miss" / "conflict with stated purpose" framing
— the Volatile Expansion design note never says Rotation should trade
Expansion, so exclusion may be intentional, not an oversight.

## 2. Daily-close scan wording — softened intent inference

`baseline_v637_audit.md`'s daily-limits paragraph said `GetTodayClosedProfit`/
`GetOpenProfitForMagic` were "never designed to" check symbol and were
"magic-wide from the start" — both claims about historical design intent
that a static read can't establish. Now states only the observable fact:
as implemented, they're magic-wide P/L-aggregation helpers, distinct in
kind from the position-management scans, without claiming anything about
original intent.

## 3. Cross-EA RSI-fallback synthesis — fixed the wrong generalization

`baseline_comparison.md` said fallback `50` "fails strict entry-threshold
RSI comparisons in both files." Checked V811's source directly: its
momentum-engine RSI windows (`InpMomRsiBuyMin/Max`=40–65,
`InpMomRsiSellMin/Max`=35–60) both *include* 50, so the fallback actually
*passes* there — the opposite of V637's strict comparisons. Rewrote with
separate, correct per-EA wording (V637: fails strict entries, two
management-path effects; V811: passes the RSI subcondition, but the
overall momentum flag still needs three other ANDed conditions).

## 4. Persisted-drawdown wording — no longer calls it "true historical"

`baseline_v811_audit.md` called `g_peak_dd` "the historical worst-drawdown
percentage" that "still remembers the true historical worst drawdown
regardless." Traced `UpdateDrawdownGuard` (2289–2305) directly: `g_peak_dd`
is the persisted maximum of `g_current_dd` readings, and `g_current_dd`'s
own basis (`g_peak_balance`) resets at every restart — so across multiple
restarts, `g_peak_dd` is not guaranteed to equal a true all-time-peak-to-
trough drawdown. Now described as "the persisted maximum session-relative
drawdown observed by this calculation," matching what the code actually
computes.

## 5. Momentum-vs-expansion framing — fixed in the two remaining locations

Round 3 fixed the main expansion-filter section but missed two other
spots making the same "explicitly designed to trade volatility expansion"
overclaim before conceding otherwise: `baseline_v811_audit.md`'s momentum-
breakout CONTRADICTION note (right after the FACT paragraphs) and
`baseline_comparison.md`'s momentum-breakout bullet in Contradictory
definitions. Both rewritten to state the `InpMomTF`/`InpWorkingTF`
relationship correctly from the opening sentence, and reclassified as
"verified gate interaction; intent and impact unresolved" rather than
"conflict."

## 6. Package metadata — `inventory.md` fixed, hash attribution corrected

`01_BASELINE/inventory.md` itself had never been touched in three rounds
of corrections — it still said the *unscoped* `git diff baseline-v637`/
`baseline-v811` were empty against `01_BASELINE/`, contradicting its own
correctly-scoped commands two paragraphs later. Fixed. Also fixed
`TASK-001_BASELINE_AUDIT.md`'s claim that the set file's hash was verified
"against `IDENTITY.md`" — `01_BASELINE/setfiles/IDENTITY.md` records no
hash at all; the set-file hash is recorded in `inventory.md` and matches
the preservation-tag git blob, which is now stated precisely. The task
file's opening "Baseline behaviour" paragraph was also broadened from
"nothing in `01_BASELINE/` was modified" to explicitly note the two
audit-documentation additions.

## 7. Structural fix — no more embedded self-referential commit hashes

Three consecutive rounds tried to record "the hash of the commit I'm
about to make" in that same commit, which is impossible, and each round
needed a follow-up hash-recording-only commit to patch it in afterward —
and even then, the last such follow-up (`79f8e5a`) had been left out of
the Commit section's own numbered history entirely. Fixed the omission,
and changed the approach going forward: this correction's own commit is
referenced symbolically ("this correction commit — see `git log` for the
exact hash") rather than trying to embed a hash that can't exist yet. This
should prevent the pattern from recurring in future rounds.

## 8. Acceptance / Reviewer / Final Decision / `TASKS.md` — aligned

These four locations disagreed on tense (some said corrections were
"being addressed," one said they were "applied and pending confirmation")
after round 3. All four now consistently describe: four review passes so
far, all changes-requested, first three resolved in their respective
commits, fourth pass's changes applied in this pass and stated as
"applied, pending confirmation" — not "resolved" — everywhere.

## Verification performed this round

- Read the actual `BuildCombinedSignal`/`SelectBestIndependentSignal`
  source directly for the ROTATION-visibility fix, rather than
  re-paraphrasing a prior summary of it.
- Read V811's momentum-engine RSI window inputs directly to confirm the
  fallback-passes-there claim before writing it.
- Read `UpdateDrawdownGuard`'s exact persistence logic directly before
  rewriting the drawdown-wording fix.
- `git diff baseline-v637 -- 01_BASELINE/EA_V637` and
  `git diff baseline-v811 -- 01_BASELINE/EA_V811` both empty.
- Grepped for leftover instances of every phrase being corrected
  ("sole candidate in that direction," "true historical worst drawdown,"
  "explicitly designed to trade volatility expansion," "never designed to")
  across all edited documents before treating each fix as complete.

Ready for a fifth review pass.
