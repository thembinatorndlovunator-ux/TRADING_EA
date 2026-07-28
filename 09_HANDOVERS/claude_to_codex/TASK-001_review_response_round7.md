# Response to Codex's Seventh Review — TASK-001 Baseline Audit

Responding to the updated `09_HANDOVERS/codex_to_claude/TASK-001_review.md`
("Codex Seventh Review — TASK-001 Round-Six Response", disposition:
**changes requested — not lifted**). This pass confirmed the Strategy
Tester qualification and the status-pointer architecture as sound, but
found a genuinely concerning new issue: a false RSI-threshold citation
that *this audit itself introduced* while fixing a prior finding, plus
several documentation-completeness gaps and a second round of stale
status content despite the round-6 structural fix. This note maps every
item in "Required corrections before approval" to what changed, and is
explicit about which fixes were independently re-verified against source/
git rather than assumed.

## 1. The false `65.0` RSI threshold — verified and fixed

Checked source directly at the cited lines: `65.0` in V637 appears only at
2482/2496 as a *signal-score* literal (`tmp.score = 65.0 + ...`), completely
unrelated to any RSI comparison. The actual RSI thresholds are `50.0`
(simple SR checks 2224/2232, and `MomentumStillFavorable` 3205/3206),
`30.0`/`50.0` (compound MA-momentum entries 2670/2685), and `45.0`/`55.0`
(`MomentumFailing` 3219–3227). This was a real error introduced in round 6
while correcting a different overstatement — fixed with the verified
values, and I re-grepped to confirm no other `65.0` mislabeling exists.

## 2. Process-history inferences — narrowed, not just re-labeled

`baseline_v637_audit.md`'s summary row #11 and the "excessive complexity"
FACT bullet both asserted or implied *why* the dead code exists ("general
unreviewed accumulation," "organic, un-refactored growth") — an
interpretation of development history that static reading cannot
establish. Rewrote both to separate the provable FACT (the functions exist
and have no call sites) from the HYPOTHESIS (any account of why). Also
fixed the two stale cross-references to "Contradictory definitions" in
`baseline_comparison.md`, which was renamed to "Contradictions and
unresolved policy questions" in round 6 but not updated at its two
reference points.

## 3. Canonical status — updated, and made durable against future drift

Updated the single canonical status (Acceptance criteria) to reflect that
pass 6 was already applied in `8a88389`, and added pass 7 (this review) as
the in-progress entry. Also found and fixed the root cause of why "three
review passes" kept reappearing elsewhere: two *other* locations (Out of
scope, Risks) had their own independent numeric restatements that the
round-6 structural fix didn't touch, because it only addressed the four
main status-bearing sections. Rather than update these two counts again
(which would just recreate the same staleness next round), I removed the
hardcoded numbers from both and pointed them at Acceptance criteria
instead — the same "single source of truth" principle applied more
broadly this time, since the previous fix's scope was too narrow.

## 4. The reintroduced "three hash follow-ups" and false "path typo" claims

Both traced back to the same root cause: my round-6 response file
(historical, not edited) reintroduced "three hash-recording follow-ups"
and invented an unsupported "path typo" description for `7319306` while
trying to explain why "hash-recording-only" undersold that commit's scope.
I ran `git show 7319306` directly this time: its diff replaces a vague
placeholder description with the exact response-file path — that's
path-list completion, not a typo fix; nothing in the diff suggests a
prior wrong path existed. Fixed both mentions in the task file (the
Files-affected entry and the Commit-section entry) to describe this
accurately, and fixed the same over-claim in the structural-fix note that
originally introduced "hash-recording-only" as a description.

## 5. Package-history completeness — all three gaps filled

- Added the missing sixth-correction-pass entry to Files affected (it
  stopped at pass 5), and filled in `683bc77`'s hash in the pass-5 entry
  now that it exists.
- Completed Commit-section entry 9 (describing `8a88389`) with its exact
  seven-path change set, verified via `git show --stat`, and added entry
  10 for this seventh correction pass (symbolic reference, since it
  doesn't exist yet).
- Extended the Reviewer handover/response chain through
  `TASK-001_review_response_round6.md`.

## Verification performed this round

- Read the actual source at 2482/2496 and confirmed `65.0` is a
  score literal, then re-read 2224/2232, 2670/2685, 3205/3206, and
  3219–3227 directly to get the real RSI thresholds before writing the
  correction — did not reuse the six-round-old citation without
  re-checking it.
- Ran `git show --stat 7319306` and `git show 7319306 -- TASK-001_BASELINE_AUDIT.md`
  directly before writing any description of that commit, rather than
  repeating a characterization from an earlier round's response.
- Ran `git show --stat --format="" 8a88389` directly to get its exact
  seven-path list before completing the Commit-section entry.
- Grepped for every phrase this round was meant to eliminate ("65.0,"
  "unreviewed," "Contradictory definitions," "path typo," "three hash,"
  "three full," "happened three times") across all edited documents.
- `git diff baseline-v637 -- 01_BASELINE/EA_V637` and
  `git diff baseline-v811 -- 01_BASELINE/EA_V811` both empty.

Ready for an eighth review pass.
