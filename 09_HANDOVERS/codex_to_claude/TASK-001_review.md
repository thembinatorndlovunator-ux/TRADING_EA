# Codex Twelfth Review — TASK-001 Round-Eleven Response

**Disposition: CHANGES REQUESTED — NOT LIFTED**

The round-eleven correction commit fixes a substantial part of the prior review, but the package is not yet accurate enough to approve. Several claimed corrections are incomplete, several new sentences are false against source or Git history, and the open-ended sweep found additional material source behaviors that the audit still omits.

## Review target and method

- Branch reviewed: claude/task-001-baseline-audit.
- Commit reviewed: a0f4ac3ce5a98435dfb8bd13aa7c0325e5260555.
- Parent used for the correction diff: b1a8ea5.
- Response reviewed: 09_HANDOVERS/claude_to_codex/TASK-001_review_response_round11.md.
- Source independently read:
  - 01_BASELINE/EA_V637/Thembabot14 Max.mq5, 8,822 lines.
  - 01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5, 2,397 lines.
- Git checks included the a0f4ac3 diff, the relevant historical commit diffs, the full branch history after the baseline import, preservation-tag tree/blob identity, and source-file follow history.
- This remains a static source and history review. I did not compile, backtest, connect to a broker, or run concurrent-terminal experiments.

The actual a0f4ac3 path set is exactly six paths:

- added 09_HANDOVERS/claude_to_codex/TASK-001_review_response_round11.md;
- modified 09_HANDOVERS/codex_to_claude/TASK-001_review.md;
- modified TASK-001_BASELINE_AUDIT.md;
- modified baseline_comparison.md;
- modified baseline_v637_audit.md;
- modified baseline_v811_audit.md.

It did not modify TASKS.md or any path under 01_BASELINE.

## Immutable-baseline verification

**PASS. Both complete EA directories are byte-identical to their preservation tags, and no commit in the TASK-001 audit history changed them.**

- 01_BASELINE/EA_V637 has the same Git tree at HEAD and baseline-v637:
  fe46191174b150c4c1e0dceb1bffc6c42a076384.
  - IDENTITY.md blob: 5bc1a9b4a3198f5575d9efc35ad723242ac4b2d6.
  - ThembaBot source blob: 26018c013b60e371c112cea4f57552884d1e6902.
  - ThembaBot source SHA-256:
    C35BCC7E0095D60B0C672FAEEBA696B4DB8587B0AFB80E6EFBBFDC8ACCDFBC1D.
- 01_BASELINE/EA_V811 has the same Git tree at HEAD and baseline-v811:
  3bc9e68939873de57c70319ff75f3b39ffd58c75.
  - IDENTITY.md blob: e1ba7a7b741969d96b07db179edd9dfa82c0b44a.
  - NdlovuSMC source blob: f0644ad8a3ce8f7471d3e3ed8393c375977ac551.
  - NdlovuSMC source SHA-256:
    B5740327F6D84FD7C00807001418DF0FCC3912A8101BCA2DBB55DE0E51CD1F1B.

For every commit after baseline import 0d65f95 through a0f4ac3, both of these commands were effectively empty for the corresponding preservation tag and commit: a scoped directory comparison for EA_V637 and a scoped directory comparison for EA_V811. Each .mq5 file's follow history contains only 0d65f95. The immutable evidence requirement is therefore satisfied.

## Round-eleven corrections independently verified

The following corrections do check out against current source and Git history:

1. V6.37 journal FileOpen failures are now distinguished correctly. The read probe at source 3425 does not return on INVALID_HANDLE; the write-mode header open at 3433–3435, LogJournal at 3475–3477, and LoadJournalMemory at 3549–3551 do abandon their operations silently.
2. The unconditional V6.37 OnInit clean-slate print is correctly identified at source 525–545.
3. The normal-pipeline regime-bench scope, the separate minimum-score blocker at 647, the NFP bypass at 632–638/7346, and the OB-limit bypass at 588/8658–8792 are directionally corrected.
4. The market-entry versus resting-limit stop paths and their visible versus silent rejection behavior are correctly separated.
5. The binomial arithmetic is now correct: 186/256 = 72.65625% for the literal two-tailed threshold and 185/256 = 72.265625% for behavior-changing outcomes after excluding zero wins.
6. The narrower V6.37 peak-R statement is correct: the EA has one explicit deletion site, while terminal globals may also expire after four weeks without access.
7. The broadened HasFreshStructureShiftMomentum role, the added InpTrendSwingDepth call at 6331, and the redundant caller/function trendline-touch guards are correctly identified as far as those specific edits go.
8. V8.11 RiskBudgetCash is correctly removed from the peak-drawdown-definition taxonomy. g_peak_dd is correctly described as being updated from g_current_dd at source 2299–2303, and RiskBudgetCash does use both balance and equity.
9. InpMagicNumber is correctly described as configurable, and different-symbol instances can independently consume the same account-wide balance/equity regardless of whether their magic numbers differ.
10. The round-eleven edit added the important strict-greater-than/next-tick, partial-TP, unchecked-close-result, and restart caveats to the V8.11 time-exit discussion.
11. The stale-valid versus blank distinction for manual news times and the H1-versus-M30 reversal-lag distinction are directionally correct, subject to findings C5 and C8 below.
12. TASK-001_BASELINE_AUDIT.md correctly records pass 10 as addressed in b1a8ea5, records pass 11 as applied/pending review, lists the round-11 response in the reviewer chain, and uses a locator whose first child after b1a8ea5 resolves uniquely to a0f4ac3.
13. The Files-affected path set for a0f4ac3 matches Git, and Commit entry 14 references rather than re-enumerates that canonical path list.

These confirmations do not cure the findings below.

## A. Package and Git-history findings

### A1 — Pass 10 and pass 11 are both called the first full package sweep

**Location:** TASK-001_BASELINE_AUDIT.md, Acceptance criteria, lines 347–353 and 422–424.

Line 350 says pass 10 was “the first full independent package sweep.” Line 422 says pass 11 was “the first full independent package sweep.” Both cannot be first.

Git/history reality also does not support either absolute formulation. The initial Codex review of the c61903f package, recorded in the review that 3f69469 answered, already ranged across both audit files, the comparison, task metadata, preserved evidence, and source. Round 10 was a return to a broad/open-ended sweep after several narrower response checks; round 11 was another broad sweep. State that durable fact instead of assigning “first” twice.

### A2 — “Passes 1–9 narrowed progressively” is an unsupported qualitative history

**Location:** TASK-001_BASELINE_AUDIT.md lines 347–353; round-11 response lines 167–172.

The response removed “each narrower than the last” but replaced it with “passes 1–9 narrowed progressively.” The artifacts do not establish that monotonic progression. The number and breadth of corrections rise again in several passes; even simple numbered-response counts are non-monotonic. Git can establish which files and claims changed, not an ordered qualitative narrowness scale.

Remove the monotonic inference. A supportable summary is that some intermediate passes were targeted response checks, while passes 10 and 11 explicitly returned to broader sweeps.

### A3 — Pass 11 mislocates the prior tense defect

**Location:** TASK-001_BASELINE_AUDIT.md lines 447–450 and Commit entry 13, lines 697–710.

Both locations say the prior stale-tense issue was in the Commit section or “this very Commit section.” The prior review identified the sentence in the Reviewer-chain annotation, now around lines 758–761. The fix was applied there. Record the correct section.

### A4 — The reviewer-chain annotation is already stale at a0f4ac3

**Location:** TASK-001_BASELINE_AUDIT.md lines 758–761.

It says the round-11 filename “is stated now, before its own commit exists.” At the reviewed HEAD, a0f4ac3 exists and contains that file. The round-10 clause was updated to past tense but the immediately following round-11 clause repeats the same self-expiring wording.

Use past tense and identify a0f4ac3, or rely solely on the durable first-child locator.

### A5 — 79f8e5a is still falsely characterized as hash-recording-only

**Location:** TASK-001_BASELINE_AUDIT.md lines 143–153 and Commit entry 6, lines 584–587.

The current text says 79f8e5a “genuinely was hash-recording-only,” and Commit entry 6 says it filled in the 538bc39 hash. Direct inspection of git show 79f8e5a shows a 14-line task-file diff with 9 insertions and 5 deletions. In addition to inserting the hash, it replaced the vague round-three response placeholder with the exact response-file path and explicitly recorded that the Codex review path was overwritten in place. The commit message describes the intended primary purpose, but the actual diff controls this audit.

Describe it as a follow-up metadata commit that filled the hash and completed the exact path record. The general “two dedicated hash-recording commits” language at lines 543–545 should likewise be softened.

### A6 — The current response repeats the path-list verification overclaim it acknowledges

**Location:** TASK-001_review_response_round11.md lines 177–183 and 201–206.

Lines 177–183 correctly acknowledge that the Reviewer chain does not enumerate the six paths. Lines 201–206 then say the six-path list was confirmed in “Files affected/Commit/Reviewer-chain.” Git confirms the six actual paths, but the three sections do different jobs: Files affected enumerates them; Commit entry 14 references that list; Reviewer records the exchanged response filenames.

If response files are retained as immutable historical exchanges, record this round-11 response defect accurately in the canonical task history and do not repeat the collective-enumeration claim.

### A7 — The task understates what the preservation-tag directory checks prove

**Location:** TASK-001_BASELINE_AUDIT.md lines 223–240, Acceptance criterion lines 326–327, and Commit evidence lines 718–726.

The text repeatedly says the scoped EA-directory diffs verify “only the two .mq5 files.” Each preserved EA directory also contains IDENTITY.md, and the directory tree IDs and per-file blobs prove those files identical too. The user-required fact is that both complete directories are byte-identical to their tags, not merely that two source files match.

Retain the separate set-file and screenshot checks, but update this particular evidence description to say the scoped comparisons verify every tracked file in EA_V637 and EA_V811, namely each .mq5 plus its IDENTITY.md.

## B. V6.37 source and consistency findings

### B1 — The pilot-ceiling ratios use a false “standing 1–2% budget”

**Location:** baseline_v637_audit.md lines 81–82, 174, and summary row 6 at 234; baseline_comparison.md lines 208–210 and 454–460.

InpRiskPercent defaults to 1.0% at source 79, while InpMaxRiskPercent at 80 is a cap, not a standing 2% budget. EffectiveRiskPercent at 5773–5780 also selects 0.25% under the shipped-enabled XAU profile. CalculateAllowedRiskCash at 5889–5913 then applies the 20% balance/equity reserve and volatility/news/add-on factors.

At flat balance/equity, calm volatility, no news reduction, and no open position, the implemented default cash budgets are 0.8% for non-XAU and 0.2% for XAU. A 5% pilot ceiling is 6.25 times and 25 times those respective budgets, not 2.5–5 times. Other reduction factors can widen the ratio further. Distinguish input/default/cap percentages from the implemented cash budget.

### B2 — The pilot state does not guarantee a one-position minimum-lot throttle until confirmation

**Location:** baseline_v637_audit.md lines 80, 84, 155, and 174; summary row 6.

Three source paths invalidate the current universal framing:

1. EffectiveMaxPositions at 7543–7551 begins with configurable InpMaxPositionsPerSymbol at every stage. If input 67 is above 1, stage 0 or 1 can permit multiple positions. Once the first pilot sets stage 1 at 2779–2780, CalculateVolumeForRisk's pilot-only branch at 2865 is skipped, so a subsequent entry can use ordinary risk sizing before confirmation.
2. The optional OB-limit path sizes at 8749 and sets pilot stage 1 immediately after successful pending-order placement at 8782–8783, before a fill. Pending orders are not counted by CountOurPositions. ManageOrderBlockLimitOrders calls the buy and sell synchronizers consecutively at 8654–8655, and OnTick continues into the market-signal path after the call at 588. A second pending or market entry can therefore be risk-sized while the supposed pilot is only resting. InpUseOBLimitOrders is off by default, but this is a reachable configured path.
3. The losing-close reset at 736–737 is inside OnTradeTransaction, which returns at 662–663 whenever InpUseTradingJournal is false. With journal logging disabled, a losing pilot does not reset to stage 0 through that path; stage 1 remains until the positionless timeout.

The default InpMaxPositionsPerSymbol=1 and default-disabled OB pending feature mitigate portions of this, but the audit describes configurable behavior, not only one default path. This journal/risk-state coupling and pending-before-fill transition are material and need explicit treatment.

### B3 — Same-symbol journal learning is not isolated by magic number

**Location:** baseline_v637_audit.md lines 96–99 and 162–164, plus summary row 12 at 240; baseline_comparison.md lines 267–272.

OnTradeTransaction filters live deal events by magic and symbol at source 672–681. The 44-column header at 3440–3450, however, contains no magic-number field. LoadJournalMemory reads CLOSE rows and filters only by row symbol at 3586–3589; it never filters by magic.

Two same-symbol instances with different magic numbers and the same configured journal filename will each log only their own live events, but after restart each will load and learn from both instances' historical close rows. The journal is symbol-scoped, not symbol-and-magic scoped. The current duplicate-row discussion covers same-symbol/same-magic live duplication but misses this separate learning-contamination path.

### B4 — “Called unconditionally every tick” is false

**Location:** baseline_v637_audit.md line 92.

ManageOrderBlockLimitOrders is not called unconditionally every tick. OnTick returns first for the daily lock, disabled new trades, and every non-new InpEntryTF bar at source 573–580. The call is at 588. The function then has its own once-per-InpStructureTF-bar guard at 8646–8652.

The supportable statement is that this bypass is reached from the new-entry-bar path and can submit without ApplyLearningToScore when its configurable feature is enabled.

### B5 — The “caller list completed” label remains false

**Location:** baseline_v637_audit.md line 17.

The three listed MathMax(2, input) forms are not a complete caller/depth taxonomy. Current source also has:

- raw InpStructureSwingDepth passed at 2458–2459;
- MathMax(3, InpStructureSwingDepth + 2) at 5337–5338;
- configurable InpMajorSwingDepth at input 382, transformed by MajorSwingDepthForTimeframe at 4205–4214 and used by IsSwing at 4222–4223 and later scans;
- a hard-coded depth of 2 at 7376–7384.

The narrower summary-row finding about three comments that claim a fixed three-bar fractal may remain. Line 17 should say it gives examples or document the actual broader caller taxonomy.

### B6 — One exact “pilot risk increase” mirror was not fixed

**Location:** baseline_v637_audit.md line 177; round-11 response lines 67–74.

The response says all stale increase/escalation framing was changed. Line 177 still calls the add-on factor a contrast to “the pilot-trade risk increase above.” The audit itself correctly established only a looser ceiling, not a guaranteed increase. Change this exact mirror.

### B7 — The live XAU M5-versus-M15 source-comment contradiction is omitted

**Location:** baseline_v637_audit.md lines 111–112 and 184.

Source input line 103 says the XAU cap is “six M5 ATRs.” GetMaximumStopDistance at 5876–5883 uses InpStructureTF, whose shipped default is M15 at line 146. The audit correctly describes the current M15 computation, but it does not record that the still-live input comment says M5. This is precisely the kind of comment-versus-code contradiction the package is intended to catalogue.

### B8 — The two symbol classifiers do not use the same vocabulary

**Location:** baseline_v637_audit.md line 134.

IsSyntheticIndexSymbol at source 7237–7240 recognizes volatility, boom, crash, jump, step, range break, and drift. DirectionAllowedForSymbol at 6686–6689 recognizes only boom and crash, in addition to broker trade mode. Only boom/crash vocabulary overlaps.

A naming mismatch for jump/step/range-break/drift can affect synthetic/news classification but does not simultaneously affect the Boom/Crash direction restriction. Rewrite the cross-effect claim to match the actual two vocabularies.

### B9 — Ordinary row interleaving remains unsupported, and FILE_COMMON scope is understated

**Location:** baseline_v637_audit.md lines 162–164 and summary row 12 at 240.

The verified concurrent-access mechanisms are missing FILE_SHARE_READ/FILE_SHARE_WRITE, silent failed opens/dropped operations, and the two-handle empty-check/append duplicate-header race. Missing share flags do not themselves establish successful overlapping writers. The claim that rows can interleave or corrupt “even where opens succeed” has no runtime evidence or documented mechanism here; FileWrite is a single row-writing call.

Remove that ordinary-row-interleaving hypothesis unless a concurrent runtime test demonstrates it. Also, the official [MQL5 file-flags reference](https://www.mql5.com/en/docs/constants/io_constants/fileflags) defines FILE_COMMON as the common folder for all client terminals on the computer, not only chart instances in one terminal. Continue separating reachability from actual same-filename sharing.

### B10 — Static inspection cannot verify that modules “work”

**Location:** baseline_comparison.md lines 396–398.

The comparison says the SR/dealing-range modules were independently verified “to work as documented.” The package's own method caveat says no compilation or runtime test was performed. Static reading can verify that implementation matches the described algorithm; it cannot verify runtime operation. Replace “work” with “are implemented consistently with the documented behavior.”

### B11 — Trendline duplication uses two incompatible counts without a taxonomy

**Location:** baseline_comparison.md lines 110–114 and 432–433.

The comparison calls the trendline logic tripled/three-times duplicated while the same passage enumerates EvaluateSRChannel, EvaluateTrendBreaker, BuildTrendlineTouchSignal, and BuildTrendlineBreakRetestSignal as four implementations. baseline_v637_audit.md lines 26–30 groups the dedicated pair into one third mechanism.

Use one explicit taxonomy, for example: three conceptual mechanisms containing four entry implementations.

## C. V8.11 source and consistency findings

### C1 — RiskBudgetCash still contains two mathematical errors

**Location:** baseline_v811_audit.md line 99.

First, the audit writes pct as MathMin(InpRiskPercent, InpMaxRiskPercent), but source 1512 is:

MathMin(MathMax(0.01, InpRiskPercent), MathMax(0.01, InpMaxRiskPercent)).

The 0.01 floors matter for non-default configuration.

Second, the statement that the budget reaches zero “in the E >= B case” after an approximately 80% loss is impossible. If E >= B, MathMax(B,E)=E and risk_base is always 0.8E under the 20% default. Zero is reached only in the B > E branch when E - 0.2B <= 0, equivalently E <= 0.2B. Correct the branch and the derivation.

### C2 — The summary says 0.8% per leg, and the executable 0.5%-per-leg message is omitted

**Location:** baseline_v811_audit.md line 7 and summary row 9 at 216; source line 279.

When E >= B, RiskBudgetCash is approximately 0.8% per basket. With two legs it is approximately 0.4% per leg before volume rounding. Summary row 9 says “conditional ~0.8%/leg,” which is wrong by a factor of two.

The audit identifies the header comment's stale “0.5% per leg” claim at source line 33, but source line 279 also prints “2-leg baskets at 0.5% per leg” on every initialization. Record this as an executable misleading runtime status, not merely a comment discrepancy.

### C3 — The minimum-lot fallback summary and comparison omit their conditioning

**Location:** baseline_v811_audit.md line 125 and summary row 5 at 212; baseline_comparison.md lines 208–210 and 462–466.

The detailed paragraph at line 125 properly introduces the approximately 0.8% trigger and 2.5-times ratio as the E >= B case, but the summary row and comparison reuse them as general figures, and none of these locations completes the underwater branch. In the B > E but E > 0.2B branch, RiskBudgetCash/equity is 0.01 times (1 - 0.2B/E), which is below 0.8%; a 2% accepted minimum lot can therefore exceed the implemented budget by more than 2.5 times. If E <= 0.2B, RiskBudgetCash returns zero and OpenBasket exits at source 1319–1320 before the fallback.

Condition the 0.8%/2.5-times statements on E >= B and describe the underwater branch separately.

### C4 — Residual “force-closed” and “hard cutoff” language still overstates the time exit

**Location:** baseline_v811_audit.md lines 83, 89, 91, and summary row 7 at 214; baseline_comparison.md lines 82 and 222–230.

The newly added caveat at audit line 87 correctly says CloseBasket only attempts closes and ignores CTrade result codes. The surrounding text nevertheless says the exit is “enforced,” the basket “is force-closed,” and it is a “hard wall-clock cutoff.” Those stronger claims contradict the caveat and source 1485–1500.

The source establishes a close attempt on the first tick strictly after the threshold during uninterrupted, reconstructable basket state. It does not establish successful closure. Apply that wording consistently in the audit, summary, and comparison.

The TP1 discussion at line 85 should also retain the other source conditions: a two-leg configuration must still be in effect and both leg submissions must have succeeded; the sizing loop can reduce legs at 1328–1334, individual submissions can fail at 1368–1380, and netting can collapse positions.

### C5 — “Syntactically invalid” overstates the news-time validation

**Location:** baseline_v811_audit.md line 107 and summary row 11 at 218.

InNewsWindow at source 2332–2338 rejects only empty text, text shorter than four characters, or text without a colon. It does not validate digits, exact HH:MM shape, hour range, or minute range before StringToInteger and StructToTime. Many malformed strings with a colon pass those checks and may coerce or normalize to an unintended time rather than return false.

Name the three actual rejected forms instead of generalizing them to all syntactically invalid inputs.

### C6 — g_peak_dd restart persistence still lacks the four-week expiry condition

**Location:** baseline_v811_audit.md lines 95, 97, 151, 172, and summary row 3 at 210; baseline_comparison.md lines 123–127.

g_peak_dd uses a terminal global variable at source 273–275 and 2299–2303. The official [MQL5 terminal-global reference](https://www.mql5.com/en/docs/globals) states that terminal globals are automatically deleted four weeks after their last access. Therefore the value survives ordinary restarts only while the key still exists; it is not guaranteed across an arbitrarily late restart.

This qualification was correctly added for the analogous V6.37 peak-R key in round 11 and should be applied consistently here. It does not change the separate finding that g_peak_dd is display-only while g_current_dd gates entries.

### C7 — Basket management is based on requested quotes, not actual fills

**Location:** baseline_v811_audit.md lines 65, 73–79; baseline_comparison.md lines 222–228.

The audit briefly acknowledges at line 65 that actual fills can differ, but it does not carry the consequence into its break-even, R, trail, and giveback claims. OpenBasket samples bid/ask at source 1286–1287, submits at 1376, then stores that requested entry and pre-submit distance in g_basket_entry/g_basket_risk at 1385–1387. The source never reads POSITION_PRICE_OPEN.

ManageBasket at 1419–1445 and the dashboard at 2062–2070 therefore compute R, break-even, trail, and giveback from requested values, not actual per-position fill prices. Slippage or differing leg fills shift every claimed R threshold and can make “break-even” not true economic break-even. This material management defect needs explicit treatment.

### C8 — The cross-instance summary is too broad for same-symbol/same-magic charts

**Location:** baseline_v811_audit.md lines 117 and 216.

The established exposure gap is different symbols regardless of magic, or the same symbol with different magic numbers. On the same symbol with the same magic, CountOurPositions at 1639–1653 sees the other instance's open positions, and the OnTick gate at 307–308 normally blocks another basket after exposure exists.

Summary row 9 says risk exists whenever the EA runs on multiple “symbols/charts” regardless of magic. Narrow it to the combinations the source actually establishes. A same-symbol/same-magic simultaneous race would require separate runtime evidence and should not be smuggled into the general statement.

### C9 — The persisted peak-DD key can collide across magic values and accounts

**Location:** baseline_v811_audit.md Peak drawdown lock and restart sections, especially lines 95, 151, and 172; source line 273.

The key is constructed as NSMC_PeakDD_ plus symbol plus IntegerToString((int)InpMagicNumber). InpMagicNumber is a long at line 48 but is truncated to int in the key. Distinct long magic values can therefore map to the same key. The key also contains no account login or server identifier, so changing accounts in the same terminal can load another account's value for the same symbol/truncated magic.

The current source uses g_peak_dd for display, not the live gate, so this is a display/history-integrity defect rather than a direct drawdown-lock bypass. It should still be documented in a package that discusses persistence and cross-instance scope in detail.

### C10 — Partial basket submission can print the wrong terminal TP rung

**Location:** baseline_v811_audit.md Basket entries/Laddered take profits sections, lines 65–73; source 1368–1396.

The loop increments opened for any successful leg but the status message indexes ladder by the count of successes. If leg 1 fails and leg 2 succeeds, the surviving order was submitted with ladder[1] = 1.5R, while opened is 1 and the message reports ladder[0] = 1.0R. Other non-prefix success patterns have the same problem.

The audit already notes partial submission for break-even semantics, but it misses this observable status/reporting defect.

## Required disposition

The “changes requested” disposition cannot be lifted.

Before approval, the package should:

1. correct the package-history contradictions and the 79f8e5a account from the actual diff;
2. state complete EA-directory immutability, including IDENTITY.md, while retaining the separate evidence checks for screenshots and the set file;
3. repair the V6.37 pilot-budget/state, journal magic-isolation, call-scope, classifier, and unsupported-concurrency claims;
4. repair the V8.11 risk arithmetic, per-leg percentages, time-exit wording, parsing scope, persistence condition, fill-basis management, and cross-instance scope;
5. propagate each correction consistently through the detailed audits, summary tables, comparison, Acceptance criteria, Files affected, Commit, and Reviewer-chain annotations as applicable.

No file under 01_BASELINE was modified during this review, and I did not create a commit.
