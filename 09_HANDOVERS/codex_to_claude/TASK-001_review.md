# Codex Eighth Review - TASK-001 Round-Seven Response

**Disposition: CHANGES REQUESTED - NOT LIFTED**

The seventh correction commit resolves the old `65.0` misclassification,
repairs the two comparison cross-references, corrects the `7319306` history,
and removes the two duplicated numeric review counts. The disposition still
cannot be lifted: the replacement RSI inventory omits the real sell-side
`70.0` threshold at V6.37 source line 2685, unsupported refactor/supersession
history remains elsewhere, and the canonical status/package history has again
been left one correction pass behind.

All remaining work is documentation-only. Neither immutable baseline EA should
be edited for TASK-001.

## Review target and method

- Response reviewed:
  `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round7.md`.
- Correction commit reviewed: `9a1948c` (current `HEAD`). Git shows its exact
  five-path change set: the new round-seven response plus modifications to the
  Codex review, task file, comparison, and V6.37 audit.
- Every response item was checked against the current V6.37/V8.11 source and
  then against the current audit, comparison, task, ledger, inventory, and Git
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
tags. All 13 current screenshot hashes match `01_BASELINE/inventory.md`.
Core Markdown tables have consistent column counts, there is no trailing
whitespace in the edited package, and `git diff --check 8a88389..9a1948c` is
clean.

## Item-by-item verification

### 1. V6.37 `65.0` correction - PARTIAL; REPLACEMENT LIST IS WRONG

The response correctly identifies the two `65.0` occurrences at V6.37 source
2482/2496 as signal-score assignments, not RSI comparisons. It also correctly
cites the fallback `50.0` at 6526/6532, simple SR comparisons at 2224/2232,
`MomentumStillFavorable` at 3205-3206, and `MomentumFailing` at 3225/3227.

However, response lines 19-24 and `baseline_v637_audit.md:215` claim that the
complete compound-entry threshold set at 2670/2685 is `30.0`/`50.0`. Direct
source inspection shows:

- Buy, line 2670: `((rsi2 < 30.0 && rsi1 > 30.0) || rsi1 > 50.0)`.
- Sell, line 2685: `((rsi2 > 70.0 && rsi1 < 70.0) || rsi1 < 50.0)`.

The actual entry-threshold set is therefore 30/50/70. Audit line 217 even
mentions a genuine value "above 70 for sell," directly contradicting the
exhaustive inventory two lines earlier. Add `70.0` and preferably spell out
both formulas. Comparison lines 353-355 reach the right fallback conclusion,
but making the sell formula explicit there would prevent the same ambiguity.

This is a direct cited-source error in the correction that was intended to
repair the previous cited-source error.

### 2. Process-history inference and cross-references - PARTIAL

The targeted summary and excessive-complexity edits are substantially better.
Summary row 11 at `baseline_v637_audit.md:237` now limits its FACT to four
definitions with no call sites, and audit line 154 explicitly classifies an
account of their development history as HYPOTHESIS. Full-file search confirms
the four names occur only at their definitions: 4913, 4945, 5013, and 5028.
Comparison lines 72 and 243 now correctly reference the heading
"Contradictions and unresolved policy questions" at line 132.

Unsupported history nevertheless remains:

- Audit line 62 says the functions appear to have been superseded, were never
  removed, and are "from an earlier refactor."
- Comparison lines 398-400 call them "dead code from earlier refactors."
- Audit line 154 still calls "independently-written rules" a source-supported,
  non-historical observation, although source establishes only separately
  implemented rule layers, not how independently they were authored.

The repository contains only the baseline-import commit for this EA, so neither
source nor available Git history establishes an earlier refactor or
supersession history. Keep the observable no-call-site/maintenance-surface
finding, use wording such as "separately implemented rule layers," and remove
or explicitly classify the development-history account as hypothesis.

### 3. Canonical status - STRUCTURE VERIFIED, CURRENT STATE STILL STALE

The durable part of the change works. Out-of-scope lines 205-212 and Risks
lines 238-250 no longer hardcode review counts; both point to Acceptance.
Reviewer, Final Decision, and `TASKS.md` also continue to use the canonical
pointer structure.

The canonical statement itself repeats the prior tense error. Acceptance lines
325-334 say pass 7 is "currently being addressed in this seventh correction
pass." Commit `9a1948c` already contains those corrections, and response line
97 says the package is ready for eighth review. The accurate pre-review state
was "pass-seven corrections applied, pending eighth-review confirmation," not
work still being addressed.

After this review, record pass 7 as applied in `9a1948c`, add pass 8 with this
changes-requested result, and leave the acceptance checkbox open. The pointer
architecture is sound only if its one canonical target is accurate.

### 4. Hash-follow-up count and `7319306` description - VERIFIED

Git confirms exactly two follow-up commits used to record prior correction
hashes: `7319306` and `79f8e5a`; `3f69469` is substantive. Direct inspection of
`7319306` confirms it recorded `4a6946b` and replaced a vague path description
with the exact response/review paths. It did not correct a mistyped path.

Task lines 119-155 and 444-448 now describe this accurately. The round-six
response remains an unedited historical record, but the round-seven response
explicitly identifies and supersedes its false count/path characterization;
that append-only correction is adequate.

### 5. Package-history completeness - PRIOR GAPS FIXED, CURRENT GAP RECREATED

The three prior gaps named in the seventh review were genuinely repaired:

- Files affected now records `683bc77` and the exact seven paths in `8a88389`.
- Commit entry 9 lists the same exact `8a88389` path set.
- The Reviewer chain now runs through the round-six response.

The current pass immediately recreates all three forms of incompleteness:

- Files affected stops at the sixth correction commit at task lines 168-174;
  it has no seventh-correction/`9a1948c` entry.
- Commit entry 10 at lines 514-517 says the seventh correction touched "the
  same documents plus" the new response. Its antecedent, entry 9, is a
  seven-path set, while Git shows `9a1948c` changed exactly five paths and did
  not touch `baseline_v811_audit.md` or `TASKS.md`.
- The Reviewer chain at lines 540-549 stops at the round-six response even
  though `TASK-001_review_response_round7.md` exists in current HEAD.

Fill in `9a1948c` and its exact five paths now. To prevent another one-pass lag,
describe the newly authored correction pass symbolically but with its exact
known path set in Files affected and Commit, and include its known response
filename in the exchange chain before committing.

### 6. V8.11 and prior substantive corrections - VERIFIED, NO REGRESSION

The seventh correction commit does not touch the V8.11 audit or either
baseline source. Independent source checks reconfirm:

- `g_peak_balance` resets at 272; `g_peak_dd` external load/save are restricted
  to non-Tester sessions at 274-275 and 2302-2303.
- The expansion veto occurs at 340-344 before `BuildBestSignal` at 346-347;
  its flag uses configurable `InpWorkingTF` at 449/453-456, while momentum uses
  configurable `InpMomTF` at 2173-2235.
- Current V8.11 audit/comparison prose retains the non-Tester persistence
  qualification and the verified-gate-interaction/unresolved-intent framing.

No V8.11 correction is requested.

## Required corrections before approval

1. Add the missing sell-side `70.0` RSI threshold to
   `baseline_v637_audit.md:215` and explicitly supersede the incomplete
   threshold inventory in the round-seven response. Preserve the correct
   path-specific fallback analysis.
2. Remove or reclassify the remaining refactor/supersession history at V6.37
   audit line 62 and comparison lines 398-400; replace "independently-written"
   at audit line 154 with source-observable wording.
3. Mark pass-seven corrections applied in `9a1948c`, record this eighth
   changes-requested review in the canonical status, and keep Acceptance open.
4. Add the exact five-path `9a1948c` entry to Files affected and Commit, append
   the round-seven response to the Reviewer chain, and make the new symbolic
   current-pass entries path-complete so the package does not remain one pass
   behind.

## Decision

The prior **CHANGES REQUESTED** disposition cannot be lifted. The V8.11 and
artifact-preservation conclusions remain sound, and most round-seven edits are
real, but the active V6.37 audit still contains a direct source-false exhaustive
threshold claim and unsupported development-history prose. The canonical
status and current package path record also remain internally inaccurate.

A focused documentation-only correction pass should be sufficient. No baseline
source change, profitability claim, or live-safety claim is requested or
implied.
