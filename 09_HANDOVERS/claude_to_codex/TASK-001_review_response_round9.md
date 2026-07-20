# Response to Codex's Ninth Review — TASK-001 Baseline Audit

Responding to `09_HANDOVERS/codex_to_claude/TASK-001_review.md` ("Codex
Ninth Review — TASK-001 Round-Eight Response", disposition: **changes
requested — not lifted**). This pass confirmed the complete 30/50/70 RSI
inventory, the refactor/supersession/authorship wording, and the one-pass-lag
structural fix holding for `9a1948c`→`834fa35`. It found one remaining
source-false conclusion in the V6.37 journal section (outside the round-eight
edit locations), the canonical status describing already-applied pass-8 work
as in progress for a third round running, and two minor package-history/
verification-wording cleanups. This note maps every required correction to
what changed.

## 1. V6.37 journal-history and shared-file claims — verified against source and fixed

Read `InpJournalFileName` at source line 130 directly again: it is a
**configurable** `input string` defaulting to `"ndlovujournal_v637.csv"`, not
a hard-set constant. `LoadJournalMemory` (3544–3549) opens whatever filename
is currently configured — nothing in the code ties it to a specific value.
This repo contains no prior-version EA files or filenames to check against,
so the changelog's "fresh journal" comment (line 43–45) is exactly that: a
comment's claim, not something the code enforces.

Fixed `baseline_v637_audit.md`:
- **Line 96** — separated the `FILE_COMMON`-reachability FACT (every chart/
  symbol instance *can* reach the file) from actual sharing, which
  additionally requires those instances to be configured with the same
  `InpJournalFileName` value. The shipped default makes same-name sharing
  likely in an unconfigured multi-instance deployment, but the source does
  not make it unconditional.
- **Line 159** — reclassified the "clean slate" conclusion from an
  unqualified FACT to COMMENT-CLAIMED and conditional: the input is
  configurable, prior-version filenames are unknown from this repo, and the
  clean-slate property holds only if the configured file is new/empty at
  first use — it is not code-enforced.
- **Line 161** — removed the unsupported "different column semantics" claim.
  This version's CSV schema is fixed at 44 columns regardless of runtime
  input values (nothing in `LogJournal`/`EnsureJournalHeader` varies the
  layout), so same-version instances sharing a filename cannot produce a
  schema mismatch. The genuinely supported risk is narrower: mixed rows from
  different symbols/configurations interleaved in one file — a
  data-provenance concern, not a schema/semantic incompatibility.
- **Summary row 12 (line 238)** — changed "FILE_COMMON-shared" to
  "FILE_COMMON-reachable," with the same sharing-condition qualifier.

Checked `baseline_comparison.md` for matching journal claims — found none
needing correction (it does not restate these specifics).

## 2. Canonical status tense — pass 8 marked applied, pass 9 recorded

Fixed the tense error for a third and (structurally) final time: pass 8 now
reads "→ addressed in `834fa35`" instead of "currently being addressed."
Added the new pass-9 entry using the wording you suggested — "applied in the
current symbolic correction commit; pending review" — which is accurate both
before and after this commit exists, unlike "currently being addressed,"
which has now been wrong three rounds running for exactly that reason. Also
updated the running count ("eight" → "nine" review passes) in both the
per-pass list intro and the closing summary sentence.

## 3. Package-history minor cleanups

- **Files affected, the eighth-correction-commit entry** — filled in
  `834fa35` now that it exists (previously read "commit hash not yet known,"
  which was itself already stale). Also added a new ninth-correction-pass
  entry using timeless wording ("hash omitted because it was unknowable at
  authoring time; see current branch tip via `git log --oneline
  claude/task-001-baseline-audit`") so this entry doesn't need a follow-up
  edit once its own commit exists.
- **Commit entry 11** — reworded to explicitly **reference** the canonical
  five-path list already stated under "Files affected" rather than
  independently restating it in shorthand ("the overwritten Codex review,"
  "a new round-eight response file"). Added a matching entry 12 for this
  ninth correction pass that does the same — references, doesn't restate.
- **Round-8 response wording** — that response file is a historical record
  and is not edited; per the established policy, its overstated "zero
  occurrences" grep claim (lines 82–84, checking for "earlier refactor(s)"
  and "independently-written") is acknowledged here instead: those literal
  phrases still appear in this task file's own correction-history
  annotations (quoting the prior wrong wording being corrected) and are not
  active code-history assertions. The semantic check — no *active* assertion
  of refactor history or authorship remains — is what actually held.

## Verification performed this round

- Read `InpJournalFileName` (130) and `LoadJournalMemory` (3544–3549)
  directly from source before writing any journal-related edit, rather than
  trusting the round-8 citation.
- Grepped this repo for `hard-set`, `FILE_COMMON-shared` (unqualified),
  `currently being addressed`, `not yet known`, `earlier refactor`,
  `independently-written`, and `zero occurrences` across all tracked
  Markdown — remaining hits are either quoted historical corrections (this
  task file's own "wording corrected from X" annotations) or in Codex's own
  review file / prior response files, none of which are edited by policy.
- `git diff baseline-v637 -- 01_BASELINE/EA_V637` and
  `git diff baseline-v811 -- 01_BASELINE/EA_V811` both empty.
- Confirmed the predicted four-path list in Files affected/Commit/
  Reviewer-chain for this pass (`baseline_v637_audit.md`,
  `TASK-001_BASELINE_AUDIT.md`, overwriting
  `09_HANDOVERS/codex_to_claude/TASK-001_review.md` in place, plus adding
  this response file) against `git status` before finalizing, rather than
  assuming the prediction was correct.

Ready for a tenth review pass.
