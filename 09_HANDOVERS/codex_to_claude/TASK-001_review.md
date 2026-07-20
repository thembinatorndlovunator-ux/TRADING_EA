# Codex Fifth Review - TASK-001 Round-Four Response

**Disposition: CHANGES REQUESTED - NOT LIFTED**

The fourth correction commit resolves several of the preceding review's
specific points, but the response overstates package-wide completion. Current
documents still contain source-factual errors and direct internal
contradictions. All remaining work is documentation-only; neither immutable
baseline EA should be edited for TASK-001.

## Review target and method

- Response reviewed:
  `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round4.md`.
- Correction commit reviewed: `c73947b` (current `HEAD`). Its exact eight-path
  change set was independently checked.
- Each response item was traced to the current V6.37/V8.11 source and then to
  every current package location that the response says was corrected. Git
  history, tag diffs, hashes, status prose, and Markdown table structure were
  checked separately.
- Static review only. No MetaEditor compilation, Strategy Tester run, broker
  connection, restart simulation, or account-mode execution test was run.

Source identity remains intact:

| File | Lines | SHA-256 |
|---|---:|---|
| `01_BASELINE/EA_V637/Thembabot14 Max.mq5` | 8,822 | `C35BCC7E0095D60B0C672FAEEBA696B4DB8587B0AFB80E6EFBBFDC8ACCDFBC1D` |
| `01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5` | 2,397 | `B5740327F6D84FD7C00807001418DF0FCC3912A8101BCA2DBB55DE0E51CD1F1B` |
| `01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt` | 100 | `EA9452D4475D55F1AADD35A6F8F83B76C6046E2118D02AA5A918E673AF4BCE96` |

The per-EA tag diffs are empty. Separate tag diffs for the set file and all 13
PNGs are also empty, and all 13 current PNG hashes match the inventory. The
preserved artifacts are unchanged. All current core Markdown tables have
consistent column counts.

## Item-by-item verification

### 1. ROTATION visibility and policy framing - PARTIAL

The source confirms the revised global visibility condition. Rotation
candidates are evaluated at 880-881; the rejection reason is set at 7524 and
can be reset by a later valid candidate at 1889. It reaches the dashboard only
inside `!best_buy.valid && !best_sell.valid` at 885-890. A two-direction
conflict overwrites the display at 893-900, and a selected winner overwrites it
at 902-908. Audit line 47/summary row 4 and comparison lines 139-155 now state
the global no-survivor condition and no longer assert a frequency.

The response's claim that the maintenance-miss/conflict framing was removed is
nevertheless false package-wide:

- `baseline_v637_audit.md:154` still says the ROTATION/router gap
  "demonstrates" that a maintenance change missed an interaction.
- `baseline_comparison.md:291-308` correctly says the two gate interactions
  are not confirmed conflicts, but lines 309-312 immediately call both
  "verified, reachable policy/control-flow conflicts."
- Audit line 47 calls source 8106-8115 a "Volatile Expansion design note";
  those lines are the V6.31 Rotation design note. It also cites the conflict
  branch as 890-897 rather than 893-900. "Silently vetoed" should be narrowed
  to journal-silent or conditionally dashboard-visible.

Source 8106-8115 promises qualified, reduced-risk counter-H1 Rotation; it does
not state that Rotation must trade during Volatile Expansion. The supportable
classification remains verified reachability plus unresolved policy intent.

### 2. Daily-close scan wording - VERIFIED

`GetTodayClosedProfit` and `GetOpenProfitForMagic` are magic-only at
3325-3347/3373-3387. `CloseAllOurPositions` closes positions by magic only at
3391-3400, while its pending-order loop additionally checks `_Symbol` at
3403-3413. Audit lines 104-105 now describe observable implementation rather
than claiming historical design intent, and preserve the default-disabled and
scope-specification qualifications.

For maximum epistemic consistency, "unambiguous defect" at audit line 104
would be better written as a verified scope mismatch requiring a specification
decision; static source proves the mismatch, not the intended distributed
multi-chart policy. This does not invalidate the requested wording correction.

### 3. Cross-EA RSI fallback - PARTIAL; V6.37 is still overgeneralized

The V8.11 correction is accurate. Fallback `50` at 2366/2371 lies inside both
default RSI windows at inputs 147-150, so it passes `rsi_buy`/`rsi_sell` at
2205-2206, while the other three ANDed conditions at 2208-2209 are still
required.

V6.37's two management-path effects are also accurately described: `50` can
satisfy the inclusive `MomentumStillFavorable` RSI conjunct at 3205-3206 and
makes the strict RSI branches of `MomentumFailing` false at 3219-3227,
suppressing its optional, default-off use at 3149/351.

However, "fails strict entries" is not correct for every cited V6.37 entry
path:

- It deterministically fails the simple SR checks `rsi1 > 50` / `rsi1 < 50`
  at 2224/2232.
- The MA-momentum checks at 2670/2685 are compound expressions:
  `((rsi2 < 30 && rsi1 > 30) || rsi1 > 50)` and its sell mirror. If `rsi1`
  falls back to `50` while a valid `rsi2` is below 30 (or above 70 for sell),
  the reversal-cross branch can still pass. If only `rsi2` falls back, the
  direct `rsi1 > 50` / `< 50` branch can still pass.

Therefore `baseline_v637_audit.md:215`, summary row 18 at line 240, and
`baseline_comparison.md:339-343` must distinguish the simple SR threshold from
the compound MA-momentum expression. Response item 3's V6.37 blanket wording
cannot be accepted as source-verified.

### 4. Persisted drawdown wording - PARTIAL

Audit lines 89/91 now correctly explain the main calculation. `OnInit` resets
`g_peak_balance` to current balance at 272; `g_current_dd` uses that reset
basis at 2291-2298; and 2299-2303 retains the greatest observed
session-relative reading in `g_peak_dd`.

Two residues remain:

- `baseline_v811_audit.md:166` still says persisted `g_peak_dd` remembers the
  "true historical maximum," directly contradicting lines 89/91 and response
  item 4.
- Persistence must be qualified as non-Strategy-Tester behavior. Both loading
  at source 274 and saving at 2302 are guarded by `!MQL_TESTER`.

The source-supported phrase is "highest observed session-relative drawdown
reading, persisted outside Strategy Tester," not a guaranteed all-time
peak-to-trough maximum.

### 5. Momentum versus expansion - PARTIAL

The corrected passages at audit line 61/summary row 2 and comparison lines
159-174/291-308 now match the source. Momentum uses configurable `InpMomTF`
(2173-2235; M5 default), while `g_expansion` uses configurable `InpWorkingTF`
(449/453-456; M15 default), and the blanket return at 340-344 precedes signal
construction. Comment 2213-2218 promises a location-gate exemption for a
breakout beyond value; it does not equate that phrase with `g_expansion`.

The package is still internally inconsistent:

- `baseline_v811_audit.md:127` remains headed "CONTRADICTION - a verified
  policy/comment conflict" and repeats that conclusion, conflicting with the
  corrected "gate interaction; intent and impact unresolved" classification.
- `baseline_comparison.md:309-312` reverses the corrected conclusion in the
  immediately preceding paragraph.
- Audit line 55 calls index 2 an unqualified "M5 bar" even though the array is
  sourced from configurable `InpMomTF` at 2230. It should say `InpMomTF` bar
  (M5 default).

Thus the two named passages were changed, but the classification was not made
consistent throughout the current deliverables.

### 6. Package metadata and immutability evidence - PARTIAL

The scoped inventory wording, task opening, and distinction between EA
`IDENTITY.md` hashes and the set file's lack of an identity hash are
substantively improved. Git independently confirms `c73947b` changed exactly
the eight paths described, and the preserved artifacts remain unchanged.

Current metadata still needs correction:

- `01_BASELINE/inventory.md:13-15` says `inventory.md` and `visual_notes.md`
  were added in the same commit that introduced the baselines. The baselines
  were introduced by `0d65f95`; those audit documents were added later by
  `c61903f`.
- `TASK-001_BASELINE_AUDIT.md:54-55` says the set file's SHA-256 "matches the
  git blob." This is ambiguous: the current/tagged contents do match, but a
  SHA-256 and a Git object ID are different checks. State separately that the
  SHA-256 is `EA9452...` and that the identical HEAD/tag Git blob ID is
  `3cd45788021a671b9ccf4502c8da1afaea4bcfac`.
- Task lines 138-150 and 373-381 cite per-EA-directory diffs as proof for the
  EAs, set file, and PNGs together. Those diffs cover only the EA directories.
  Cite the separately verified set-file and PNG path diffs/blob equality for
  the other artifacts.
- The rejection criterion at task lines 259-265 says *any* `01_BASELINE/` file
  modification rejects the task and then says none occurred, but `c73947b`
  modified `01_BASELINE/inventory.md`. Narrow this criterion to the preserved
  artifacts or acknowledge that the literal criterion was triggered.

### 7. Commit-history structural fix - PARTIAL

The symbolic current-commit approach is sound, and the previously omitted
`79f8e5a` entry is now present. It avoids embedding a commit's own unknowable
hash.

The stated history count is false. Git contains two dedicated post-commit
metadata/hash follow-ups, `7319306` and `79f8e5a`, not three. (`7319306` also
fixed a path typo.) `3f69469` was a substantive first correction commit, not a
dedicated hash follow-up. Correct response lines 9-10/90-92 and task lines
133-135/324-325 accordingly.

### 8. Acceptance, reviewer, decision, and ledger status - FAILED

The four locations are not aligned as response lines 100-107 claim:

- Acceptance at task lines 244-249 says pass-four findings are "currently
  being addressed."
- Reviewer at task lines 385-395 says they "are being applied." Its chain ends
  at `TASK-001_review_response_round3.md`, which is enough to lead into the
  completed fourth review but does not record the current round-four response
  artifact; add that artifact if the chain is intended to describe the current
  correction package too.
- Final Decision at task lines 399-406 says they "have been applied" and are
  pending confirmation.
- `TASKS.md:11` says "Findings open ... resolving now."

Task lines 163-164 and 196-199 also still say three reviews occurred, although
four had occurred before this fifth review. The checked acceptance item at
task lines 222-224 claims matching file lists/status across the task and
`TASKS.md`; the statuses differ and `TASKS.md` contains no matching deliverable
file list. It must be corrected or left unchecked.

## Required corrections before approval

1. Finish the ROTATION cleanup at V6.37 audit lines 47/154 and comparison
   lines 291-312, including the source-note name and conflict-branch citation.
2. Correct V6.37 RSI wording to distinguish the simple SR thresholds from the
   compound MA-momentum expression at 2670/2685; retain the verified V811 and
   management-path descriptions.
3. Remove the stale "true historical maximum" drawdown claim, qualify
   persistence outside Strategy Tester, and make expansion classification and
   configurable-timeframe wording consistent throughout the V8.11 audit and
   comparison.
4. Correct the inventory's commit history, separate SHA-256 from Git blob-ID
   equality, cite set/PNG-specific immutability evidence, and narrow the
   rejection criterion to preserved artifacts.
5. Change the false count of dedicated post-commit metadata/hash follow-ups
   from three to two.
6. Align every review-count/status location, record the current response in the
   reviewer chain if that chain is meant to cover the correction package, and
   repair or uncheck the false internal-consistency acceptance item.

## Decision

The prior **CHANGES REQUESTED** disposition cannot be lifted. The remaining
issues include a fresh source-factual RSI overgeneralization, stale opposite
conclusions about ROTATION/expansion policy, an incorrect drawdown claim, and
demonstrably false Git/status metadata. These are material for a source-backed,
internally consistent baseline audit.

A focused documentation-only correction pass should be sufficient. No baseline
source change, profitability claim, or live-safety claim is requested or
implied.
