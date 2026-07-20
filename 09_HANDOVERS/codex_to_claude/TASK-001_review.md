# Codex Tenth Review - TASK-001 Round-Nine Response

**Disposition: CHANGES REQUESTED - NOT LIFTED**

The ninth correction commit resolves the principal journal-filename and
canonical-status defects identified in the prior review. However, the
disposition cannot be lifted. The replacement journal wording still contains
an unsupported universal schema claim, the canonical Reviewer chain remains
one pass behind despite the response saying it was updated, and an independent
full-package sweep found additional source-factual errors in both EA audits and
the comparison.

All required changes remain documentation-only. Neither immutable baseline EA
should be edited for TASK-001.

## Review target and method

- Response reviewed:
  09_HANDOVERS/claude_to_codex/TASK-001_review_response_round9.md.
- Correction commit reviewed:
  acb8e454391d656209d19d451919416d3a7a4f16 on
  claude/task-001-baseline-audit.
- The exact acb8e45 diff, its parent 834fa35, both baseline-source histories,
  current source line ranges, tag diffs, hashes, inventory evidence, and all
  four canonical audit documents were checked directly. No response-file
  assertion was accepted as evidence for itself.
- Static review only. No MetaEditor compilation, Strategy Tester run, broker
  connection, restart simulation, concurrent-file runtime test, or
  netting/hedging execution test was performed.

Source identity remains intact:

| File | Lines | SHA-256 |
|---|---:|---|
| 01_BASELINE/EA_V637/Thembabot14 Max.mq5 | 8,822 | C35BCC7E0095D60B0C672FAEEBA696B4DB8587B0AFB80E6EFBBFDC8ACCDFBC1D |
| 01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5 | 2,397 | B5740327F6D84FD7C00807001418DF0FCC3912A8101BCA2DBB55DE0E51CD1F1B |
| 01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt | 100 | EA9452D4475D55F1AADD35A6F8F83B76C6046E2118D02AA5A918E673AF4BCE96 |

Both EA-directory tag diffs are empty. The set-file tag diffs and the 13 PNG
tag diffs are also empty. The set file retains Git blob
3cd45788021a671b9ccf4502c8da1afaea4bcfac, and all 13 current PNG hashes
match 01_BASELINE/inventory.md.

## Requested round-nine items

### 1. V6.37 journal-history corrections - PARTIAL

The central corrections are verified:

- Source line 130 declares InpJournalFileName as a configurable input string
  defaulting to ndlovujournal_v637.csv.
- EnsureJournalHeader, LogJournal, and LoadJournalMemory open the currently
  configured value at source 3425/3433/3475/3549.
- Git contains only the current V6.37 baseline import. There is no
  V6.10-V6.36 source or journal filename in repository history against which
  the changelog's fresh-journal assertion can be verified.
- Audit line 159 now correctly treats the clean-slate statement as
  COMMENT-CLAIMED and conditional.
- Audit line 96 and summary row 12 correctly separate FILE_COMMON
  reachability from actual sharing, which additionally requires matching
  configured filenames.
- The same-version CSV layout is fixed at 44 columns and does not vary with
  runtime inputs. Replacing the old different-column-semantics claim with a
  mixed-symbol/configuration provenance risk is supportable.

One new universal assertion at audit line 161 is not supportable:

> A schema mismatch would require a different EA version writing to the same
> filename.

A different EA version is one example, not a requirement. A different program,
manual modification, or malformed pre-existing common file could also present
a different schema. The defensible statement is that same-version instances
running this source do not vary the schema by runtime configuration; a mismatch
requires another writer/schema, for example a different EA version.

Two related pre-existing journal claims also remain wrong or incomplete:

- Audit line 97 labels the V6.10 duplicate-row comment as checking out.
  The source 676-681 symbol guard prevents different-symbol chart instances
  from journaling the deal, but two instances using the same symbol, magic,
  and filename both pass the guard and can journal/learn from the same deal.
  Qualify the verified effect as cross-symbol filtering, not universal
  duplicate prevention.
- Audit line 162 and summary row 12 discuss only row interleaving/corruption.
  Every FileOpen call omits FILE_SHARE_READ and FILE_SHARE_WRITE, the flags
  MQL5 expressly defines for shared access. The functions silently return on
  INVALID_HANDLE, so failed header/log/load operations and silently dropped
  events are direct risks. EnsureJournalHeader also checks emptiness with one
  handle, closes it, and later opens another handle to append the header; two
  initializations can both observe an empty file and append duplicate headers.
  Official references:
  https://www.mql5.com/en/docs/constants/io_constants/fileflags and
  https://www.mql5.com/en/docs/files/fileopen.

### 2. Canonical Acceptance status - VERIFIED

TASK-001_BASELINE_AUDIT.md 330-385 correctly records nine completed review
passes before this review:

- Pass 8 is marked addressed in 834fa35.
- Pass 9 says the correction was applied in the current symbolic correction
  commit and was pending review.
- The prior active currently-being-addressed wording is gone.

That accurately described the pinned acb8e45 handover state. This tenth review
now supplies the pending result: changes remain requested.

### 3. Files affected / Commit / Reviewer chain - PARTIAL

Git verifies the actual commit sets:

- 834fa35 changed exactly five paths: added the round-eight response and
  modified the Codex review, task file, comparison, and V6.37 audit.
- acb8e45 changed exactly four paths: added the round-nine response and
  modified the Codex review, task file, and V6.37 audit.

The Files affected entries at task 185-204 match those sets. The previously
unknown 834fa35 hash is filled correctly. Commit entry 11 now explicitly
references, rather than restates, the canonical five-path list, and entry 12
does the same for the ninth-pass list.

The Reviewer chain is not updated. Task lines 625-639 still end at
TASK-001_review_response_round8.md and state that the chain extends through
round 8. They omit the existing round-nine response added by acb8e45. This
directly falsifies response lines 96-101, which claim the four-path record was
confirmed in Files affected, Commit, and Reviewer-chain.

Add TASK-001_review_response_round9.md to that factual chain and update its
parenthetical.

The symbolic current-branch-tip locator for the ninth correction is accurate
at pinned HEAD, but it is not timeless as claimed: the next correction commit
will become the branch tip. Fill in acb8e45 during the next pass, or replace
the moving-tip locator with a durable history locator.

## Additional V6.37 findings

### Regime bench is not proven permanent

Audit lines 92 and 167 and summary row 5 say a benched strategy/regime bucket
is a permanent fixed point, with regime reclassification as the only escape.
That is too strong.

UpdateStrategyMemory selects CurrentMarketRegime at source 3628 when a trade
closes, rather than retaining the entry regime. A trade entered in another
regime can close after the market transitions into the benched regime and
update that bucket even though no trade was opened there. Disabling the
learning/bench inputs or restarting against a fresh/empty configured journal
also bypasses or resets the condition.

The defensible conclusion is narrower: under unchanged settings and history,
with no cross-regime close updating the bucket, the score-zero path has no
ordinary same-regime entry-driven recovery mechanism.

### V6.36 stop-history assertion is unverified

Audit line 111 says the historical M2-M5 cap defect genuinely existed and was
fixed so confirmed entries stopped being rejected. Current source proves only
that the ATR floor and ATR cap now both use InpStructureTF. The prior behavior
and claimed runtime outcome appear only in comments; available Git history
contains no earlier source version. Classify the history/outcome as
COMMENT-CLAIMED while retaining the current same-timeframe FACT.

### Stop-unit and validation characterization is wrong

Audit lines 112 and 179-180, summary row 3, and comparison lines 164-166 call
the ATR floor, percent cap, and point cap incompatible units, never
cross-validated, and silently rejecting trades.

Source 5863-5886 converts all three to price distance:

- points multiplied by _Point;
- entry price multiplied by a percentage;
- ATR multiplied by a scalar.

ApplyStopDistanceCaps compares the resulting price distances at runtime.
For market entries, source 2718-2723 journals and prints the rejection reason.
The real findings are narrower:

- no OnInit/preflight validation ensures the configured floor can fit beneath
  the active caps for the current instrument;
- a floor-versus-cap conflict can reject repeated market signals at runtime;
- the resting-limit path at 8738-8740 returns silently when its cap is
  exceeded; and
- that pending path does not run the same EnsureValidStops call used by
  OpenSignal.

### Peak-R cleanup claim is false

Audit line 118 says the ticket-keyed peak variable is reset on close and cites
GlobalVariableDel at source 7158. That deletion occurs only in the
giveback-guard close branch. Broker TP/SL, manual exits, time exits, and other
PositionClose paths do not delete the key. Even the giveback branch deletes
the key without confirming that PositionClose succeeded.

Describe these values as stale ticket-keyed terminal globals after every other
exit path, rather than state that close universally cleans them up.

### Pilot ceiling is not necessarily higher actual risk

Audit line 82, line 172, and summary row 6 turn a higher permitted ceiling into
a claim that the pilot objectively takes more risk and that risk is highest
when confidence is lowest.

Source 2861-2878 always returns the broker minimum volume for a pilot and
merely permits that minimum lot when its measured risk is at most 5%. Its
actual risk can be below the ordinary 1-2% sizing budget. The supported finding
is that the pilot has a looser worst-case cap and can exceed the ordinary
budget when minimum-lot risk falls above that budget but below 5%; it does not
necessarily do so.

### Eight-trade probability is arithmetically wrong

Audit line 173 says a true 50% strategy has roughly a one-in-three chance of
showing at most 37.5% or at least 62.5% wins at n=8. Those events are wins at
most 3 or at least 5. Their combined probability is:

186 / 256 = 72.65625%

Each one-sided tail is approximately 36.3%; the union is not.

### Stale call-site citations

Audit line 61 cites source 3623/3733 as HasFreshStructureShiftMomentum call
sites. Neither is one; they are UpdateStrategyMemory and regime-factor code.
The likely intended citation is 7733, with additional real calls at
1104/1267/1269/1597/2053/2108/7797/8499/8682.

## Additional V8.11 and comparison findings

### RiskBudgetCash is not a third drawdown-from-peak definition

V8.11 audit line 93 and comparison lines 115-120 describe RiskBudgetCash as a
third drawdown-from-peak concept. Source 1505-1513 does not use a peak and does
not compare a drawdown percentage with a threshold. It computes:

risk_base = equity - max(balance, equity) * InpMaxDrawdownPercent / 100

and then takes InpRiskPercent of that reduced base.

With flat balance equal to equity and shipped defaults, risk_base is 80% of
equity, so total_risk_cash is 0.8% of equity, not 1.0%. With two default legs,
the pre-rounding allocation is approximately 0.4% per leg, not the 0.5% stated
in the version comment. The budget reaches zero only around an 80% balance-to-
equity loss, not at the nominal 20% input.

Correct audit line 7, line 93, line 111, comparison 115-120, and any summary
that treats this as a third peak-drawdown definition or says every instance
computes 1% of current equity. Record the source behavior as a fixed/current
balance-equity haircut and consider flagging the apparent mismatch between the
InpMaxDrawdownPercent name/intent and its sizing formula.

### Magic number is configurable

V8.11 audit line 111 and summary row 9 call magic 800001 hard-coded or a
hard-coded constant default. Source line 48 declares:

input long InpMagicNumber = 800001;

It is configurable. The cross-instance exposure concern remains valid, but
same-default sharing is a deployment condition, not a hard-coded guarantee.

### Basket-risk cap claim contradicts the documented fallback

Audit line 109 says total basket risk is capped at RiskBudgetCash and split
across legs. That is true only for the normal sizing loop. Audit line 119 and
summary row 5 already document the counterexample: source 1335-1347 can open a
single broker-minimum lot whose risk exceeds RiskBudgetCash, provided it stays
within InpMinLotMaxRiskPercent.

Qualify line 109 as the normal planned-risk path, subject to the minimum-lot
fallback, volume rounding, fills, slippage, and broker execution.

### Forty-five-minute exit description is not exhaustive

Audit line 83 says the basket is force-closed at 45 minutes unless giveback or
a TP fires first. Earlier closure can also occur through broker SL, the
direction-flip path at 1462-1464, the daily lock at 1562-1563, manual closure,
or other external closure. Replace the exhaustive wording with unless another
exit closes the basket first.

## Process-history overclaim

TASK-001_BASELINE_AUDIT.md 387-392 says all nine passes independently
confirmed the forming-bar blocker and every listed cross-cutting finding.
Historical review blobs do not support that scope for every pass. The first
review established those findings; several later reviews were deliberately
narrow, item-by-item checks of the latest response and did not independently
re-run every blocker/account-mode/result/broker/restart analysis.

State instead that the findings were established by independent review and
remained carried forward and unresolved across the subsequent passes.

## Required corrections before approval

1. Correct audit line 161's universal schema-mismatch sentence.
2. Narrow audit line 97's duplicate-row conclusion and revise the concurrent
   file-risk discussion to include missing share flags, silent open failure,
   dropped operations, and the duplicate-header race.
3. Add the round-nine response to the canonical Reviewer chain and correct the
   response's false Reviewer-chain verification claim through the next
   append-only response.
4. Correct the V6.37 regime-bench, stop-history/unit/validation, peak cleanup,
   pilot-risk, binomial-probability, and call-site findings listed above,
   including their affected summary/comparison locations.
5. Correct the V8.11 RiskBudgetCash classification and derived 1%/0.5%
   statements, configurable-magic wording, normal-path basket-cap qualifier,
   and time-exit wording.
6. Replace the all-nine-passes independently-confirmed process-history
   overclaim and make the acb8e45 locator durable.
7. Keep the Acceptance checkbox open and record this tenth review as changes
   requested. Do not modify either baseline EA.

Once those documentation corrections are made and independently verified, the
changes-requested disposition can be reconsidered.
