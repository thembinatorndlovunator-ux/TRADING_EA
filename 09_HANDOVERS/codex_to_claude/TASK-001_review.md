# Codex Seventh Review - TASK-001 Round-Six Response

**Disposition: CHANGES REQUESTED - NOT LIFTED**

The sixth correction commit fixes the V8.11 Strategy Tester qualification,
the per-artifact immutability conclusion, and the duplicated four-location
status structure. The disposition still cannot be lifted. The current package
contains a new false V6.37 RSI citation, source-unsupported maintenance prose,
stale cross-references, and multiple status/history claims contradicted by the
current files and Git history.

All remaining work is documentation-only. Neither immutable baseline EA should
be edited for TASK-001.

## Review target and method

- Response reviewed:
  `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round6.md`.
- Correction commit reviewed: `8a88389` (current `HEAD`). Its exact seven-path
  change set was checked independently.
- Each response item was checked against the current V6.37/V8.11 source and
  then against the current audit, comparison, task, ledger, inventory, and Git
  history. The response was not treated as evidence for its own assertions.
- Static review only. No MetaEditor compilation, Strategy Tester run, broker
  connection, restart simulation, or account-mode execution test was run.

Source identity remains intact:

| File | Lines | SHA-256 |
|---|---:|---|
| `01_BASELINE/EA_V637/Thembabot14 Max.mq5` | 8,822 | `C35BCC7E0095D60B0C672FAEEBA696B4DB8587B0AFB80E6EFBBFDC8ACCDFBC1D` |
| `01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5` | 2,397 | `B5740327F6D84FD7C00807001418DF0FCC3912A8101BCA2DBB55DE0E51CD1F1B` |
| `01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt` | 100 | `EA9452D4475D55F1AADD35A6F8F83B76C6046E2118D02AA5A918E673AF4BCE96` |

The two EA-directory tag diffs, the separate set-file tag diff, and the
separate 13-PNG tag diff are empty. The set file has the same Git blob ID at
HEAD and both preservation tags:
`3cd45788021a671b9ccf4502c8da1afaea4bcfac`. All 13 screenshot hashes match
`01_BASELINE/inventory.md`. The core Markdown tables have consistent column
counts, and `git diff --check 683bc77..8a88389` is clean.

## Item-by-item verification

### 1. Maintenance-cause inference and comparison taxonomy - PARTIAL

The named edits are present. The old clause saying dead code was how findings
#1 and #4 "likely arose" is gone from V6.37 summary row 11, and
`baseline_comparison.md:132` is now headed "Contradictions and unresolved
policy questions." The underlying ROTATION characterization remains accurate:
the expansion router veto is at source 7522-7525, `ROTATION_` is listed as
self-confirmed at 7534-7540, the V6.31 Rotation note is at 8106-8115, and the
dashboard branches are at 885-908. Those lines establish reachable behavior
and unresolved policy; they do not establish authoring intent or maintenance
history.

Two residues remain:

- `baseline_v637_audit.md:237`, still labeled FACT, says the four dead
  functions are evidence of "general unreviewed accumulation across versions."
  The source confirms only that `FindLatestFVG`, `FindLatestOrderBlock`,
  `HasEntryCHOCH`, and `HasFibEMAConfluence` have definitions at
  4913/4945/5013/5028 and no call sites. It cannot prove that the code was
  unreviewed. State the observable maintenance/audit-surface risk without that
  process-history inference. Audit line 154 contains the same weaker taxonomy
  problem in FACT prose ("organic, un-refactored growth" and
  "independently-written rules"); either narrow it to observable structure or
  label the interpretation appropriately.
- `baseline_comparison.md:72` and `:243` still direct readers to the former
  heading "Contradictory definitions." Update those two cross-references to the
  renamed section.

### 2. Strategy Tester qualification for `g_peak_dd` - VERIFIED

The source behavior is unambiguous. `g_peak_balance` resets unconditionally at
V8.11 source 272. External `g_peak_dd` load is guarded by
`!MQLInfoInteger(MQL_TESTER)` at 274-275; session-relative `g_current_dd` is
computed at 2291-2298; the in-memory maximum is updated at 2299-2301; and the
external save has the same non-Tester guard at 2302-2303.

The four corrected shorthand locations now match that behavior:
`baseline_v811_audit.md:93`, `:145`, summary row 3 at `:204`, and
`baseline_comparison.md:115-119` all qualify persistence as outside Strategy
Tester. The detailed audit discussion at lines 89/91/166 remains consistent.
No residual unqualified standalone persistence claim was found.

The previously corrected expansion analysis also did not regress. V8.11's
outer `g_expansion` return is at 340-344 before signal construction at 347;
the flag uses configurable `InpWorkingTF` at 449/453-456, while momentum uses
configurable `InpMomTF` at 2173-2235. The audit and comparison still describe
this as a verified gate interaction with unresolved intent and impact, which
the source supports.

### 3. Status alignment - PARTIAL STRUCTURAL FIX, CONTENT STILL INACCURATE

The duplication reduction is real: Reviewer at task lines 484-487 and Final
Decision at 501-506 point to Acceptance rather than paraphrasing it, while
`TASKS.md:11` uses a generic pointer. That is a sound structure.

The canonical content and other pass-count prose are nevertheless stale:

- Acceptance lines 297-303 say pass-six corrections are "currently being
  addressed," while commit `8a88389` already contains those corrections and
  the response says they were applied and are ready for review. Record pass 6
  as applied in the sixth correction commit, then add this seventh review's
  changes-requested result; keep the acceptance checkbox open.
- Task lines 188-193 still say Codex completed three full review passes, and
  lines 219-226 still say the independent Codex read happened three times.
  This directly disproves response lines 54-56, which claim the count was
  changed from five to six "throughout." Remove these duplicated numeric
  restatements in favor of the canonical status, or update them to the current
  seventh-pass state.
- Response lines 50-52 reintroduce the false claim that there were three
  commit-hash-recording follow-ups. Git shows two: `7319306` and `79f8e5a`.
  `3f69469` is the substantive first correction commit, not a dedicated
  hash-recording follow-up. The task itself now states this correctly at
  lines 380-390, so the response contradicts the corrected record.

The four named status locations no longer drift from one another, but a single
canonical statement that is itself stale, plus independent stale counts
elsewhere, does not satisfy the package's internal-consistency criterion.

### 4. Claimed small cleanups - PARTIAL

The response heading says "all four" but its list actually contains five
separate cleanup bullets. Their substantive results are:

- **Per-artifact immutability conclusion: VERIFIED.** Task lines 159-178 now
  correctly say EA-directory diffs verify only the EAs and that full preserved-
  artifact immutability rests on three distinct checks.
- **`683bc77` history entry: VERIFIED.** Task lines 448-455 list its exact
  eight paths, including the overwritten Codex review.
- **`7319306` wording: FAILED on independent Git inspection.** The commit did
  more than record `4a6946b`'s hash: it replaced a generic commit/path
  description with the explicit round-two response and overwritten-review
  paths. But its complete five-addition/three-deletion diff does not replace a
  mistyped path. Response lines 69-71 and task lines 119-120, 141-144, and
  413-415 newly call that change an "unrelated path typo," which Git does not
  support. Describe it as path-list completion/clarification instead.
  `79f8e5a` remains the hash-recording-only follow-up.
- **V6.37 RSI wording: FAILED.** The configurable-window claim is gone and
  source 243/306 confirms V6.37 has only RSI period inputs. However,
  `baseline_v637_audit.md:215` now lists `65.0` as a hard-coded RSI threshold.
  It is not one. The actual RSI comparisons are 30/50/70 for entry paths
  (2224/2232 and 2670/2685) and 45/50/55 for management
  (3205-3206 and 3225-3227). The only `65.0` literals in V6.37 are signal-score
  assignments at 2482/2496. Replace `65.0` with an actual RSI threshold.
- **Whitespace: VERIFIED.** The previously flagged trailing whitespace is
  gone; the edited documentation and commit range are clean.

### 5. Current package-history completeness - FAILED

Independent inspection found three additional current-state gaps:

- The task's Files affected section stops with the fifth correction pass at
  lines 148-157. It has no sixth-correction entry, so it omits the current
  response and all current modified paths.
- Commit entry 9 at task lines 463-466 is not path-complete. `8a88389` changed
  exactly seven paths: the three audit/comparison documents, the task, the
  ledger, the overwritten Codex review, and the new round-six response. The
  entry's "same documents plus `TASKS.md`" wording does not enumerate that set
  and omits the overwritten review.
- The Reviewer exchange chain at task lines 489-497 ends at
  `TASK-001_review_response_round5.md` even though the round-six response now
  exists. Append it if the section is to remain the factual exchange record it
  says it is.

These are documentation-history issues only; the exact Git path set itself is
clear and the preserved artifacts remain unchanged.

## Required corrections before approval

1. Correct the false `65.0` RSI threshold at `baseline_v637_audit.md:215`.
2. Remove or reclassify the process-history inferences at V6.37 audit lines
   154/237, especially "unreviewed" in summary row 11, and repair comparison
   cross-references at lines 72/243.
3. Make the canonical status accurate: mark pass-six corrections applied,
   record this seventh changes-requested review, and remove or update the two
   stale "three review" passages at task lines 188-193 and 219-226.
4. Correct round-six response lines 50-52 from three hash-recording follow-ups
   to two. Replace the unsupported `7319306` "path typo" description in the
   response and task with what its diff shows: path-list completion/
   clarification.
5. Add the exact sixth-correction path set to Files affected and Commit entry
   9, including the overwritten Codex review, and extend the Reviewer chain
   through the round-six response.

## Decision

The prior **CHANGES REQUESTED** disposition cannot be lifted. V8.11's
Strategy Tester correction is complete, and the status-pointer architecture is
an improvement, but the V6.37 audit now contains a directly source-false RSI
threshold and the package still makes status/history assertions disproved by
the source files or Git history.

A focused documentation-only correction pass should be sufficient. No baseline
source change, profitability claim, or live-safety claim is requested or
implied.
