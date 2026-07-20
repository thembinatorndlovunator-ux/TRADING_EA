# Codex Ninth Review - TASK-001 Round-Eight Response

**Disposition: CHANGES REQUESTED - NOT LIFTED**

The eighth correction commit correctly repairs the V6.37 RSI inventory,
removes the unsupported refactor/authorship assertions, and successfully
predeclares the current correction's five-path package record. The disposition
still cannot be lifted. Independent source review found a remaining V6.37
journal-history claim that the configurable filename and available Git history
do not support, and the single canonical status again says completed edits are
still being addressed.

All remaining work is documentation-only. Neither immutable baseline EA should
be edited for TASK-001.

## Review target and method

- Response reviewed:
  `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round8.md`.
- Correction commit reviewed: `834fa35` (current `HEAD`). Its exact five paths
  were checked directly against both the predeclared package list and Git.
- Every response item was checked against the current V6.37/V8.11 source and
  then against the audits, comparison, task, ledger, inventory, and Git
  history. The response was not accepted as evidence for itself.
- Static review only. No MetaEditor compilation, Strategy Tester run, broker
  connection, restart simulation, or account-mode execution test was run.

Source identity remains intact:

| File | Lines | SHA-256 |
|---|---:|---|
| `01_BASELINE/EA_V637/Thembabot14 Max.mq5` | 8,822 | `C35BCC7E0095D60B0C672FAEEBA696B4DB8587B0AFB80E6EFBBFDC8ACCDFBC1D` |
| `01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5` | 2,397 | `B5740327F6D84FD7C00807001418DF0FCC3912A8101BCA2DBB55DE0E51CD1F1B` |
| `01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt` | 100 | `EA9452D4475D55F1AADD35A6F8F83B76C6046E2118D02AA5A918E673AF4BCE96` |

The two EA-directory tag diffs, separate set-file tag diff, and separate
13-PNG tag diff are empty. The set file has Git blob ID
`3cd45788021a671b9ccf4502c8da1afaea4bcfac` at HEAD and both preservation
tags. All 13 screenshot hashes match `01_BASELINE/inventory.md`. Core Markdown
tables have consistent column counts, the edited package has no trailing
whitespace, and `git diff --check 9a1948c..834fa35` is clean.

## Item-by-item verification

### 1. Missing V6.37 `70.0` threshold - VERIFIED

Direct source inspection confirms the complete RSI behavior:

- Buy entry at 2670:
  `((rsi2 < 30.0 && rsi1 > 30.0) || rsi1 > 50.0)`.
- Sell entry at 2685:
  `((rsi2 > 70.0 && rsi1 < 70.0) || rsi1 < 50.0)`.
- Simple SR checks use strict `50.0` at 2224/2232.
- Management uses inclusive `50.0` at 3205-3206 and strict `45.0`/`55.0`
  at 3225/3227.
- The fallback is `50.0` at 6526/6532. The two `65.0` values at 2482/2496
  are signal scores, not RSI thresholds.

`baseline_v637_audit.md:215` now inventories 30/50/70 and spells out both
entry formulas. `baseline_comparison.md:353-356` does the same. The corrected
path-specific fallback conclusions remain accurate.

### 2. Refactor, supersession, and authorship wording - VERIFIED

Git history for each EA contains only baseline import `0d65f95`; the four dead
V6.37 function names occur only at their definitions (4913, 4945, 5013, 5028).
Current audit line 62 now treats any supersession account as HYPOTHESIS, audit
line 154 says "separately implemented rule layers," and comparison lines
400-405 retain only the no-call-site fact. These edits match the available
source and history.

### 3. Canonical status - PRIOR PASS FIXED, CURRENT TENSE STILL WRONG

The running count is now eight and pass 7 is correctly recorded as addressed
in `9a1948c`. The pointer architecture also remains sound: Out of scope, Risks,
Reviewer, Final Decision, and `TASKS.md` defer to Acceptance instead of
maintaining independent counts.

Acceptance line 362 nevertheless says pass 8 is "currently being addressed in
this eighth correction pass." Commit `834fa35` already contains those edits,
and response line 92 declares the package ready for ninth review. As in the
prior two rounds, the accurate handover state is "corrections applied, pending
review," not edits still in progress.

Record pass 8 as applied in `834fa35`, add this ninth changes-requested review,
and keep the acceptance checkbox open. For future current-pass entries, use
"applied in the current symbolic correction commit; pending review" rather
than "currently being addressed" so the canonical target is accurate both
before and after commit creation.

### 4. Package-history one-pass-lag fix - VERIFIED IN SUBSTANCE

The structural fix works. Git shows both `9a1948c` and `834fa35` changed exactly
five paths. Files affected lines 176-195 contain the exact prior and current
sets; the current set matches `834fa35`: V6.37 audit, comparison, task, the
overwritten Codex review, and the round-eight response. The Reviewer chain now
runs through that round-eight response.

Commit entry 11 points to the exact canonical path list in Files affected but
then uses shorthand ("the overwritten Codex review" and "a new round-eight
response file") rather than the exact paths/filename the response says appear
in all three locations. This does not recreate the missing-entry defect because
the entry explicitly delegates to the complete list above, but the response's
verification wording should say the Commit section *references* the canonical
exact list, not that it independently restates it.

Likewise, Files affected line 185 now says the commit hash is "not yet known,"
although `834fa35` exists. The hash may remain intentionally unembedded to
avoid self-reference, but use timeless wording such as "hash omitted because
it was unknowable at authoring time; see current branch tip."

### 5. V8.11 and prior substantive corrections - VERIFIED, NO REGRESSION

Commit `834fa35` does not touch the V8.11 source or audit. Independent source
checks reconfirm:

- `g_peak_balance` resets at 272; `g_peak_dd` load/save are non-Tester-only at
  274-275 and 2302-2303, while the live gate uses `g_current_dd` at 315-319.
- The expansion return is at 340-344 before signal construction at 346-347;
  it uses configurable `InpWorkingTF` at 449/453-456, while momentum uses
  configurable `InpMomTF` at 2173-2235.
- V8.11's RSI fallback is `50` at 2366/2371. It satisfies either default RSI
  window at 2205-2206, but the overall momentum flags still require three
  other ANDed conditions at 2208-2209.

Current V8.11 audit/comparison wording matches those facts. No V8.11 change is
requested.

### 6. Remaining V6.37 journal-history and shared-file claims - FAILED

Independent inspection of the journal section found a source-false conclusion
outside the round-eight edit locations:

- `baseline_v637_audit.md:159` calls `InpJournalFileName` "hard-set" to
  `ndlovujournal_v637.csv`, says that name is distinct from every prior
  version, and concludes V6.10-V6.36 history genuinely cannot be read unless
  someone renames an old file. Source line 130 declares a configurable
  `input string`, not a hard-set constant. The available repository contains no
  prior EA versions or filenames. Lines 43-45 are only a changelog comment
  claiming a fresh journal. `LoadJournalMemory` at 3544-3549 opens whatever
  filename the operator configures, so an operator can point it at an older
  file without renaming anything; the default-named file could also already
  exist. The clean-slate conclusion is therefore COMMENT-CLAIMED and
  conditional, not FACT.
- Audit lines 96/161 equate `FILE_COMMON` with the CSV being shared by every
  chart instance. `FILE_COMMON` establishes the common folder; actual sharing
  additionally requires those instances to use the same configured
  `InpJournalFileName`. The source's default and comment make same-name sharing
  likely by default, but not unconditional.
- Audit line 161 says differently configured V6.37 instances can write
  "different column semantics" to the file. Different runtime inputs do not
  change this version's fixed 44-column schema. The supported risk is mixed
  rows from multiple symbols/configurations sharing a filename; schema/semantic
  incompatibility would require a different writer/version and is not proven
  by the stated example.

Rewrite lines 96/159-161 to separate the configured-filename condition, the
comment's claimed clean slate, and the narrower shared-file risk.

### 7. Verification-claim wording - MINOR CLEANUP

Response lines 82-84 say grep confirmed no other occurrences of "earlier
refactor(s)" or "independently-written" remain. Those literal phrases still
appear in correction-history annotations and task line 315, although not as
active code-history assertions. The semantic check succeeded; describe it as
"no other active assertions remain" rather than claiming zero occurrences.

## Required corrections before approval

1. Correct the V6.37 journal claims at audit lines 96 and 159-161: the filename
   is configurable, prior-version filenames are unknown, clean-slate behavior
   is conditional on a new/empty configured file, and cross-instance sharing
   requires the same configured filename. Remove the unsupported
   different-column-semantics example for same-version configurations.
2. Mark pass-eight corrections applied in `834fa35`, record this ninth
   changes-requested review, and use applied/pending-review wording for the
   current pass instead of "currently being addressed."
3. Make the current symbolic-hash wording timeless and clarify that Commit
   entry 11 references the exact canonical Files affected list. Narrow the
   round-eight response's grep claim to active assertions rather than literal
   phrase absence.

## Decision

The prior **CHANGES REQUESTED** disposition cannot be lifted. The requested
round-eight RSI, history, and package-path corrections are real, and V8.11 plus
artifact preservation remain sound. However, the active V6.37 audit still
overstates what its configurable journal filename and `FILE_COMMON` flag prove,
and the canonical status again describes already-applied work as in progress.

A focused documentation-only correction pass should be sufficient. No baseline
source change, profitability claim, or live-safety claim is requested or
implied.
