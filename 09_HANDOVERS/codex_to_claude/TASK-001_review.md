# Codex Eleventh Review — TASK-001 Round-Ten Response

**Disposition: CHANGES REQUESTED — NOT LIFTED**

Commit b1a8ea5 correctly applies many of the requested round-ten corrections,
but the package is not yet source-factual throughout. The remaining issues are
documentation issues only; neither preserved baseline EA should be changed for
TASK-001.

## Review target and independent verification

- Response reviewed:
  09_HANDOVERS/claude_to_codex/TASK-001_review_response_round10.md.
- Branch and commit reviewed:
  claude/task-001-baseline-audit at
  b1a8ea593e502b1c31772a183973334e3e50b01c, whose parent is
  acb8e454391d656209d19d451919416d3a7a4f16.
- I inspected the actual acb8e45..b1a8ea5 patch, not just the response's
  description of it. Git reports exactly these six paths:
  - added
    09_HANDOVERS/claude_to_codex/TASK-001_review_response_round10.md;
  - modified
    09_HANDOVERS/codex_to_claude/TASK-001_review.md,
    TASK-001_BASELINE_AUDIT.md, baseline_comparison.md,
    baseline_v637_audit.md, and baseline_v811_audit.md.
- V6.37 remains 8,822 lines, SHA-256
  C35BCC7E0095D60B0C672FAEEBA696B4DB8587B0AFB80E6EFBBFDC8ACCDFBC1D,
  Git blob 26018c013b60e371c112cea4f57552884d1e6902.
- V8.11 remains 2,397 lines, SHA-256
  B5740327F6D84FD7C00807001418DF0FCC3912A8101BCA2DBB55DE0E51CD1F1B,
  Git blob f0644ad8a3ce8f7471d3e3ed8393c375977ac551.
- Each EA's available Git history contains only the baseline-import commit
  0d65f95. Diffs against baseline-v637/baseline-v811 and the b1a8ea5
  source-only diff are empty. Therefore historical claims about versions not
  present in the repository can be verified only as comments, not as history.
- Static review only. I did not compile either EA, run Strategy Tester, connect
  to a broker, simulate a restart, or run the multi-instance journal race.

For the file-sharing semantics I also checked the official MQL5 references:
[File flags](https://www.mql5.com/en/docs/constants/io_constants/fileflags),
[FileOpen](https://www.mql5.com/en/docs/files/fileopen), and
[terminal global variables](https://www.mql5.com/en/docs/globals).

## Round-ten items that are now verified

The following corrections are supported by the current source and actual
b1a8ea5 diff:

1. V6.37 journal-history core:
   - InpJournalFileName is a configurable input string at source line 130.
   - baseline_v637_audit.md:159 now treats the fresh/clean journal claim as
     COMMENT-CLAIMED and conditional on the configured file actually being
     new or empty.
   - Lines 96 and 161 correctly distinguish FILE_COMMON reachability from
     actual cross-instance use of the same configured filename.
   - Line 161 no longer makes a universal “different column semantics” claim.
     It correctly says another EA version is only one possible source of a
     foreign schema. The remaining row-interleaving statement at line 163 is
     explicitly labeled HYPOTHESIS rather than FACT.
   - The same-symbol/same-magic/same-filename duplicate-row limitation at line
     97 follows from source lines 672–681.
   - All four journal FileOpen expressions omit FILE_SHARE_READ and
     FILE_SHARE_WRITE. The two-handle empty-check/append pattern at
     3425–3439 creates the stated duplicate-header time-of-check/time-of-use
     race.

2. Other requested V6.37 corrections:
   - baseline_v637_audit.md:111 now separates the current shared
     InpStructureTF fact from the unverified V6.36 history comment.
   - The stop floor and cap components are converted to price distances before
     comparison at source lines 5820–5886.
   - Source line 7158 is the EA's only explicit GlobalVariableDel for
     peak_key.
   - The pilot branch at 2865–2882 returns the broker minimum lot; 5% is a
     ceiling, not a target to which volume is scaled.
   - The literal fair-binomial event P(X <= 3 or X >= 5) is
     186/256 = 72.65625%, which rounds to 72.7%.
   - The actual HasFreshStructureShiftMomentum call sites are exactly
     1104, 1267, 1269, 1597, 2053, 2108, 7733, 7797, 8499, and 8682.

3. Requested V8.11 corrections:
   - RiskBudgetCash at 1505–1513 uses the current balance/equity pair and is
     not a third remembered-peak calculation.
   - Under the explicit flat-account condition balance = equity, shipped
     defaults produce exactly 0.8% total cash risk and 0.4% per default leg
     before volume rounding.
   - InpMagicNumber is configurable at source line 48.
   - baseline_v811_audit.md:109 now qualifies the RiskBudgetCash cap as the
     normal sizing path and points to the minimum-lot exception.
   - Direction flip and the daily lock are real additional paths that can
     attempt to close exposure before the time condition.

4. Canonical task/package status:
   - TASK-001_BASELINE_AUDIT.md:669–682 now lists the exchange chain through
     round 10.
   - “The first commit after acb8e45” resolves to b1a8ea5 in the current
     ancestry and remains a durable locator if later commits are added.
   - Pass 9 is marked addressed in acb8e45 at lines 381–390.
   - Pass 10 uses applied/pending-review wording at lines 391–408.
   - Lines 410–420 now accurately say the blocker/cross-cutting findings were
     established in the first independent review and carried forward, rather
     than claiming every later pass re-ran that analysis.
   - The acb8e45 hash is filled in, and Commit entry 13 references the
     canonical tenth-pass Files-affected list instead of duplicating it.

## Remaining changes required

### A. V6.37 journal wording is still not source-accurate

1. baseline_v637_audit.md:162 and summary row 12 at line 239 incorrectly say
   every journal FileOpen failure drops/abandons the operation.

   The read probe at source lines 3425–3431 has no INVALID_HANDLE return. If it
   fails, need_header remains true and execution proceeds to the second open
   at line 3433. Only the write handle at 3433–3435, LogJournal at 3475–3477,
   and LoadJournalMemory at 3549–3551 silently return/drop their respective
   operation. A failed read probe can instead misclassify the file as needing
   a header. The round-ten response repeats the same “all four abandon”
   overclaim at lines 33–37.

   Keep the missing-share-flags and duplicate-header findings, but describe
   the four failure paths separately.

2. The clean-slate correction is incomplete because it covers only the
   changelog comment. OnInit resets memory at source line 530, loads whatever
   configured journal exists at line 534, and then unconditionally prints
   “Clean learning slate: memory now judges only the current logic” at line
   545. That executable status message is misleading whenever an old or
   non-empty configured file was loaded. baseline_v637_audit.md:159–160 should
   record this runtime contradiction as well.

### B. V6.37 regime-bench scope is still overstated

3. baseline_v637_audit.md:92, line 168, and summary row 5 still generalize the
   bench to all entries of a strategy in that regime.

   - ApplyLearningToScore returns zero at source line 3727, but
     SelectBestIndependentSignal can still assign a zero-score candidate to
     an empty direction slot at 930–933. The normal OnTick threshold at
     647 then prevents that candidate from opening. “Cannot win a direction
     slot” is therefore not the actual blocker; the minimum-score check is.
   - More importantly, not every entry path calls ApplyLearningToScore.
     The news-displacement path at 632–638 sends a score-82 signal directly
     to OpenSignal; BuildNewsDisplacementSignal labels it TrendFollowing at
     7346. It can therefore open while the TrendFollowing regime bucket is
     benched.
   - ManageOrderBlockLimitOrders is called at line 588. Its
     SyncOrderBlockLimit path at 8658–8792 can place an FVGRetest pending
     order without ApplyLearningToScore. Although disabled by shipped
     default, it is configurable and can fill while that bucket is benched.

   The supported scope is: the hard zero blocks ordinary candidates routed
   through the combined-signal learning pipeline. It is not a universal
   per-strategy entry lock.

   Mirrored wording also remains stale at baseline_comparison.md:390–394 and
   433–435, which still says the strategy can “never” re-accumulate data and
   calls the mechanism self-perpetuating despite the documented close-time
   cross-regime update and the bypass paths above.

### C. V6.37 stop, probability, pilot, and cleanup corrections need finishing

4. Stop-path scope and visibility remain inconsistent:

   - baseline_v637_audit.md:180 says all three floor/cap/broker mechanisms
     interact on “every trade.” The resting-limit path at 8733–8740 applies
     the floor and its own inline cap but does not call EnsureValidStops or
     ApplyStopDistanceCaps.
   - Summary row 3 at line 230 says runtime rejection has “no explicit
     warning.” Market-entry rejection is explicitly journaled and printed at
     source lines 2718–2724. Only the resting-limit cap return at 8738–8740
     is silent.
   - Line 181 similarly mixes silent starvation with a per-rejection
     Print/journal record. It should distinguish absence of preflight warning
     from visibility of a rejection that has actually occurred.

5. The 72.7% arithmetic is correct only for the literal sample-extremity event,
   not for the probability that the cited source changes behavior. The low
   branches at 5761, 6256, 6267, and 6278 require win_rate > 0.0. At exactly
   eight fair trials, zero wins is counted in X <= 3 but changes none of those
   settings. The behavior-change probability is therefore:

   P(1–3 wins or 5–8 wins) = 185/256 = 72.265625%, approximately 72.3%.

   baseline_v637_audit.md:174 currently says 72.7% and immediately concludes
   that crossing those thresholds changes live stop/trailing behavior. It
   must either use 72.3% for that behavioral conclusion or explicitly separate
   the 72.7% extremity statistic from the 72.3% code-path statistic.

6. A fresh trend is not limited to one pilot:

   - a losing stage-1 close resets the pilot stage to zero at source 733–737;
   - the positionless timeout can also reset it at 6981–6985.

   baseline_v637_audit.md:173 should not call it the “single” pilot of a fresh
   trend. In the same stored trend, another minimum-lot pilot can follow a
   loss or timeout.

   The ceiling-vs-realized-risk correction also has stale mirrors:
   baseline_v637_audit.md:176 still calls it a pilot-risk “increase,”
   baseline_comparison.md:200 says “Weak-sample risk increase,” and
   baseline_comparison.md:436–438 says “risk escalation.” Those locations
   should say looser permitted ceiling, not necessarily higher realized risk.

7. baseline_v637_audit.md:118 correctly identifies the only explicit EA
   deletion, but “never cleaned up” is too absolute for an MT5 terminal global.
   The official terminal-global documentation says globals are automatically
   deleted four weeks after their last access. The accurate claim is that the
   EA does not explicitly delete peak-R keys on other exits, so they can
   remain stale until terminal expiry.

### D. Additional V6.37 source-claim cleanup from the open sweep

8. The corrected HasFreshStructureShiftMomentum call-site list is exact, but
   baseline_v637_audit.md:61 describes every call as a counter-H1-regime gate.
   Source 1104–1105 also permits fresh M15 direction while H1 is neutral,
   1265–1269 derives a responsive structure direction, and 1597–1598 adds FVG
   structure context. Keep the ten call sites but broaden the functional
   description.

9. baseline_v637_audit.md:17 says IsSwingHigh/IsSwingLow depth is only
   InpFractalDepth or InpStructureSwingDepth depending on caller. It omits the
   InpTrendSwingDepth-derived caller at 6331–6334 and other caller-supplied
   depths. This also conflicts with the audit's own three-input finding at
   line 21 and summary row 13.

10. baseline_v637_audit.md:31 misreads the source comment:
    source 7598–7600 says 33–40% win rate, not “losing 33–40%.” It also says
    the strategy is “only skipped” by the internal guard at 7576, while the
    caller independently gates both calls at 814–818.

### E. V8.11 risk arithmetic remains overgeneralized and internally inconsistent

11. baseline_v811_audit.md:93 correctly conditions 0.8%/0.4% on
    balance = equity, but shorthand repetitions at audit lines 7 and 111,
    summary row 9, and baseline_comparison.md:123 omit that condition.
    Shipped inputs alone do not determine the percentage.

    With defaults and E = equity, B = balance:

    - if E >= B, RiskBudgetCash = 0.008E;
    - if B > E, RiskBudgetCash/E = 0.01(1 - 0.2B/E), clamped at zero.

    Thus 0.8% is the flat-or-equity-at-least-balance result, not an
    unconditional shipped-default percentage. The displayed comparison
    formula should also retain source line 1511's MathMax(0.0, ...) clamp.

12. baseline_comparison.md:115–125 still calls g_current_dd and g_peak_dd two
    unrelated peak-based “definitions” and says none of the three items
    reference one another. Source 2299–2303 directly compares g_current_dd
    with g_peak_dd and assigns the latter from the former. The accurate
    taxonomy is one session-relative current-drawdown calculation, its
    persisted running maximum, and a separate non-peak sizing haircut.

13. The minimum-lot fallback still uses the nominal 1% input as its reachability
    boundary:

    - baseline_v811_audit.md:119 and summary row 5 say the fallback is
      reachable only when minimum-lot risk is above 1% and at most 2%;
    - baseline_comparison.md:201 and 439–442 retain only the “double intended
      risk” framing.

    At flat defaults the implemented normal budget is 0.8% of equity, so the
    fallback begins when minimum-lot risk exceeds roughly 0.8%, not 1%. It can
    accept just over 0.8% through 2%, up to 2.5 times the implemented flat
    budget. The documents may separately retain “up to double the nominal 1%
    input” if they clearly distinguish nominal intent from implemented budget.

14. baseline_v811_audit.md:111, summary row 9, and
    baseline_comparison.md:205 say RiskBudgetCash sizes from equity alone.
    Source 1507–1511 uses both current equity and current balance. The values
    are account-wide, so the cross-instance conclusion survives, but the input
    description must be corrected.

### F. V8.11 magic/exposure and time-exit corrections are incomplete

15. The cross-instance risk is incorrectly conditioned on reuse of the same
    magic number at baseline_v811_audit.md:111 and summary row 9. Different
    symbols/instances with different magics still independently calculate
    risk from the same account-wide balance/equity, while their
    CountOurPositions scopes do not see one another. Same magic is sufficient
    in some deployments, not necessary.

    The same paragraph says this EA family is “commonly run across an index
    suite.” The Boom/Crash name filter at 1616–1628 makes multi-symbol
    deployment plausible; neither source nor the available Git history proves
    that it is common. Label that as a deployment hypothesis or remove it.

16. The 45-minute description at baseline_v811_audit.md:83 and summary row 7
    is still inaccurate:

    - take profits are broker-side; no TP is checked inside ManageBasket;
    - under the shipped two-leg ladder, TP1 closes one leg, not the basket.
      The remaining leg can still reach the time exit. Only a TP that removes
      all remaining exposure ends the basket first;
    - the condition at 1455–1456 is strict “greater than 45 minutes” and is
      evaluated on the next tick, not exactly at minute 45;
    - CloseBasket at 1485–1500 ignores close result codes, so it attempts a
      close rather than guaranteeing “force-closed” exposure;
    - after a restart with positions open, lost basket state makes
      ManageBasket return at 1416–1417, so the time exit is not applied at all.

    Audit line 123 repeats the unqualified hard-cutoff/force-closed wording.
    The section needs an intact in-memory basket-state/uninterrupted-runtime
    qualifier and should distinguish a partial TP from a full basket exit.

### G. Additional V8.11 source-claim cleanup from the open sweep

17. baseline_v811_audit.md:101 and summary row 11 say stale or blank manual
    news times provide zero protection. Blank/invalid text returns false at
    2332–2336 and creates no window. A stale but syntactically valid HH:MM is
    still converted into today's timestamp at 2339–2346 and blocks that daily
    interval; it may protect the wrong time, but it is not zero protection.

18. Summary row 8 says the H1/M30 gate cannot enter a reversal until two swing
    pairs register a new trend. StructureTrend itself has that lag, but
    RefreshDirectionM30 can set g_dir30 from a current close beyond the most
    recent swing at 434–441. When H1 bias is neutral, TradeDirectionOK at
    580–583 allows M30 to lead. The classifier-lag fact is valid; the claimed
    universal entry timing is not.

### H. Canonical process history still contains two stale claims

19. TASK-001_BASELINE_AUDIT.md:339–340 says all ten review passes were “each
    narrower than the last.” That is contradicted by the round-ten response's
    own lines 5–11, which calls round ten the first broad full-package sweep
    and says it found more source-factual errors than any prior single round.
    Remove the monotonic-narrowing claim or scope it only to the passes for
    which it is true.

20. TASK-001_BASELINE_AUDIT.md:687–688 says the round-ten response filename is
    stated “before its commit exists.” At reviewed HEAD b1a8ea5 that commit
    exists and the file is present. If this history is worth retaining, put it
    in past tense: the filename was predeclared before the commit existed.

21. Minor response-file precision issue: round-ten response lines 168–173 say
    the exact six-path list was confirmed in Files affected, Commit, and
    Reviewer chain. Git confirms the six paths and the Files-affected section
    enumerates them. Commit entry 13 references that canonical list, while the
    Reviewer chain records only response filenames; those latter sections do
    not each restate an exact six-path list.

## Final decision

**Changes requested.** The b1a8ea5 corrections are substantial and the
requested Git/status mechanics are now sound, but the factual errors and stale
mirrors above prevent lifting the disposition. The next correction should
remain documentation-only and should not modify either file under
01_BASELINE/.
