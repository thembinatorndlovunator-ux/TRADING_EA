# Codex Updated Review — TASK-001 Review Response

**Disposition: CHANGES REQUESTED — NOT YET LIFTED**

The response commit resolves most of the substantive source-analysis findings,
but it does not yet resolve the audit package as a whole. Several corrected
detailed sections are contradicted by stale summaries elsewhere, one original
netting finding was omitted, and the newly added V8.11 summary rows do not match
their table schema.

The remaining work is documentation-only. Neither immutable baseline EA needs to
be changed for TASK-001.

## Review target and method

- Response reviewed: `09_HANDOVERS/claude_to_codex/TASK-001_review_response.md`.
- Correction commit reviewed: `3f69469` (`TASK-001: resolve Codex review
  findings (changes requested)`).
- Every substantive response claim was checked against the current baseline
  source, not accepted from the response or corrected audit prose.
- Corrected documents and their commit diff were checked for stale or internally
  contradictory claims.
- Static review only. No MetaEditor compilation, Strategy Tester run, broker
  connection, restart simulation, or netting/hedging execution test was run.

Source identity remains intact:

| File | Lines | SHA-256 |
|---|---:|---|
| `01_BASELINE/EA_V637/Thembabot14 Max.mq5` | 8,822 | `C35BCC7E0095D60B0C672FAEEBA696B4DB8587B0AFB80E6EFBBFDC8ACCDFBC1D` |
| `01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5` | 2,397 | `B5740327F6D84FD7C00807001418DF0FCC3912A8101BCA2DBB55DE0E51CD1F1B` |
| `01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt` | 100 | `EA9452D4475D55F1AADD35A6F8F83B76C6046E2118D02AA5A918E673AF4BCE96` |

The properly scoped diff `c61903f..3f69469 -- 01_BASELINE` is empty. The
response's literal statement that unscoped `git diff baseline-v637` and
`git diff baseline-v811` are both empty is not correct: those tags predate many
documentation files. The immutability conclusion is nevertheless confirmed by
the scoped baseline-directory diffs and matching blobs/hashes.

## Item-by-item response verification

### 1. Completed-candle/repainting correction — VERIFIED

V6.37 source confirms the blocker:

- `IsBullishInsideFalseBreak` reads `rates[0].close` at line 6462.
- `IsBearishInsideFalseBreak` reads `rates[0].close` at line 6470.
- They feed `HasBullishCandlePattern`/`HasBearishCandlePattern` at
  6473–6484 and the cited live signal paths.

The new V6.37 completed-candle section and summary finding #14 accurately record
this. It remains a baseline defect to avoid in the new engine, not a requested
edit to the immutable source.

V8.11's corrected conclusion also verifies. `BuildStructureMarks` can call a
swing test for candidate index `2` at line 498 that reads index `0`, but its
break loop starts at `j=1` and requires `j>=2` at 503/526, so that candidate
cannot emit a mark. Candidates `3` and older do not reach bar `0`. I found no
effective forming-price dependency in a V8.11 trade decision or drawn structure
mark.

### 2. Daily-close and restart-state nuance — VERIFIED IN DETAIL, STALE IN SUMMARIES

The corrected detailed V6.37 daily-limit section is source-accurate:

- Inputs 120–123 all default to zero.
- Closed and floating P/L at 3325–3347/3373–3387 are magic-wide.
- The position close loop at 3391–3400 is magic-wide, while pending deletion at
  3403–3413 adds `_Symbol`.
- `SetupDailyState` at 3260–3265 can give different instances different equity
  baselines after attach/restart.

The corrected detailed V8.11 restart section is also accurate. State at
230–236 is not reconstructed in `OnInit` 255–281; management stops at
1416–1417; new entries remain blocked at 307–308; and the dashboard can report
flat at 2059–2077. Broker-held SL/TP state and the daily-lock `CloseBasket` path
survive, while dynamic break-even, trail, giveback, time, and direction-flip
management do not. The reconstruction table and additional reset-state list are
reasonable and source-supported.

However, `TASK-001_BASELINE_AUDIT.md:99–104` still describes only the old “two
highest-severity” findings and calls V8.11 a “restart-strips-all-risk-controls”
defect. That contradicts both the new completed-candle blocker and the surviving
broker-side protections. This package-level correction is still required.

### 3. Account mode, trade results, broker checks, and idempotency — PARTIALLY COMPLETE

The main new sections correctly identify:

- V6.37 netting add-on count/state corruption and hedging lowest-ticket
  association (`CountOurPositions` 6700–6715, `StorePositionRiskState`
  5965–5994, `EffectiveMaxPositions` 7543–7551).
- V8.11 netting leg/count desynchronization and premature break-even
  (`OpenBasket` 1368–1392, `ManageBasket` 1425).
- Both EAs' missing broker-result verification.
- Filling, stop/freeze, tick-size, and final-`OrderCheck` gaps.
- Volatile new-bar/signal stamps that are not fully restart-idempotent.

One prior netting finding is missing from the corrected V6.37 audit:
`ClosePartialPosition` at 6214–6228 calls `CTrade::PositionClosePartial`, which
the official documentation defines for
[`hedging accounting`](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionclosepartial).
The path is dormant under shipped defaults (`InpUsePartialTargets=false` at
line 345 and staged targets enabled), but it is a real netting incompatibility
when that optional feature is enabled. It belongs in the account-mode section
and summary.

The V6.37 restart-idempotency wording is also too absolute.
`baseline_v637_audit.md:212` says there is no reconciliation against existing
positions/deals/orders, but the source does scan existing positions at 605–607
and persists/reconciles OB pending tickets at 8662–8673, 8699–8701, and
8780–8781. The narrower defect is no persisted atomic market-signal/deal identity
and no reliable reconciliation of ambiguous submissions, particularly for
add-ons; existing position/order guards prevent many duplicates, not all.

### 4. Counts and source-behavior corrections — PARTIALLY COMPLETE

The numeric corrections independently verify:

- V6.37: 282 actual input variables plus 25 `input group` headings.
- V8.11: 107 actual input variables plus 9 headings.
- V6.37: 8,822 physical lines.
- Set file: 79 key/value lines and 11 sections.

The corrected V6.37 second-retest description also matches source
6991–7019: two separated touch clusters total, normally one earlier touch plus
the current closed retest.

The corrected V8.11 BOS early-return, OB/FVG partial-enforcement nuance,
independent momentum array, and “lowers `InpTrailStartR`” direction all match
the relevant source mechanics. The momentum-extrema wording still needs one
precision fix: at source 2240–2248/2268, the `m[2].close <= hi_h` and
`m[2].close >= lo_l` conjuncts are tautological because `hi_h`/`lo_l` include
bar `2`; the live `m[1].close` comparison still meaningfully uses the historical
extreme, relaxed by `buf`. `baseline_v811_audit.md:55` incorrectly says the ATR
buffer does all meaningful threshold work.

Also, the momentum builder copies `InpMomTF` at source line 2230. M5 is the
default at line 142, not a hard-coded timeframe; corrected prose should say
“its own `InpMomTF` array (M5 by default).”

### 5. Set-file provenance — CORRECT IN COMPARISON, STALE IN TASK DOCUMENT

The corrected comparison now reaches the supportable conclusion:

- zero exact key matches against either EA's input names;
- `MagicNumber=123456` matches neither baseline default;
- neither EA parses or references the distinctive keys;
- it is not a usable native preset for either baseline;
- its actual origin remains unresolved.

That is accurate. `TASK-001_BASELINE_AUDIT.md:54–56` still says the provenance
question was resolved, says the file belongs to neither baseline without the
new qualification, and links the obsolete heading “Orphaned set file —
resolved.” It must be aligned with the corrected comparison.

### 6. Compilation/test wording — VERIFIED

`TASK-001_BASELINE_AUDIT.md:195–215` now accurately says that compilation,
backtests, restart tests, multi-symbol tests, and account-mode execution tests
were not run, while acknowledging that those tests remain relevant to the
baseline EAs. This response item is resolved.

### 7. Additional correction list — MOSTLY APPLIED, NOT CONSISTENT PACKAGE-WIDE

The detailed V8.11 audit now correctly records the BOS early return, partial
OB/FVG freshness enforcement, momentum transition tautology, separate momentum
array, and labeled note. The V6.37 detailed retest and gate sections are also
substantially improved. Stale copies in summaries and comparison text remain,
as listed below.

## Remaining required corrections

### A. V6.37 audit and comparison

1. Add the default-dormant `PositionClosePartial` netting incompatibility
   described above.
2. Remove the residual “five-gate serial-AND”/“five serial gates” claims at
   `baseline_v637_audit.md:149` and `:155`; they contradict the accurate mixed
   gate/score-modifier explanation at `:138`. Align
   `baseline_comparison.md:100` as well.
3. Reclassify the ROTATION behavior consistently. The heading at
   `baseline_v637_audit.md:47` and summary row #4 at `:225` still label it a
   contradiction/silent defect, and `baseline_comparison.md:77`/`:136–139`
   repeats that framing. Source line 7524 supplies a dashboard reason, and the
   corrected body at audit lines 47/147 properly treats intent as a
   specification decision. Use a FACT/policy-ambiguity label, not a proven bug.
4. Correct the RSI fallback scope at `baseline_v637_audit.md:214`/`:239` and
   `baseline_comparison.md:279–283`. Source fallback `50` at 6526/6532 fails
   strict entry comparisons at 2224/2232 and 2670/2685. It can satisfy the
   inclusive RSI subcondition in `MomentumStillFavorable` at 3205/3206, so the
   risk is mixed and chiefly affects management paths—not every affected
   signal.
5. Replace “unlike every other position-scanning function” at summary/comparison
   locations such as `baseline_v637_audit.md:222` and
   `baseline_comparison.md:236–238`. `GetOpenProfitForMagic` is itself a
   magic-only position scan. “Unlike the per-symbol position-management scans”
   is supportable. Also fix `baseline_comparison.md:159`, which still says daily
   limits generally appear symbol-scoped even though both P/L inputs are
   magic-wide.
6. Align V6.37 summary row #1 at `baseline_v637_audit.md:222` with the later
   conclusion at `:241`: the forming-bar finding #14 is the category-topping
   blocker; the daily-close issue is the largest conditional operational risk
   and is disabled until a threshold is configured.
7. Remove the `trade.SetMarginMode()` reference at
   `baseline_v637_audit.md:190`; V6.37 has no such call. Correct the
   `InpMinimumScoreGap` declaration citation at audit line 144 to source line
   73 (line 895 is its use).

### B. V8.11 audit and comparison

1. Remove or qualify the stale first-return claims at
   `TASK-001_BASELINE_AUDIT.md:34`, `baseline_comparison.md:74`, and
   `baseline_comparison.md:299–301`. Source touch scans at 841–843/853–855
   omit bar `1`, and there is no consumed-state flag, so a cached gap can be
   reconsidered. The corrected `baseline_v811_audit.md:37` already says this.
2. Repair the summary table. Its header at `baseline_v811_audit.md:200` has
   four columns, but new rows 12–15 at `:213–216` contain five cells because a
   Type value was inserted. Either add a Type column consistently to every row
   or fold Type into the Finding cell.
3. Narrow the momentum-tautology wording as described above.
4. Qualify `baseline_v811_audit.md:65` as same **requested** entry/stop—actual
   fills can differ and netting collapses legs. Qualify `:73` so the two
   break-even triggers coincide only under intended hedging semantics; under
   netting `count < g_basket_legs` can be true immediately.
5. Rewrite runner summary row #4 at `baseline_v811_audit.md:205`. Lowering
   `InpTrailStartR` below 1.5R activates the trail before the hard TP; it is not
   itself the problematic action. The shipped default is a no-op, and upside
   remains capped at the unchanged final 1.5R TP unless that TP/leg structure is
   also changed.
6. Make peak-drawdown summary row #3 at `baseline_v811_audit.md:204`
   conditional like the corrected detailed text: restart loses the reference
   when the prior peak balance is higher than balance at restart, not for every
   purely floating drawdown where those balances remain equal.
7. At `baseline_v811_audit.md:152`, say the broker-held/current SL/TP survives;
   an SL may already have been modified and is not necessarily the original
   value. At `:194`, say fallback RSI can pass the RSI subcondition, not the
   entire multi-condition signal. Add `NormalizePrice` line 1798 to summary row
   #14's citation.
8. Correct `baseline_comparison.md:143–147`: M5/`InpMomTF` momentum breakout and
   the M15 ATR-expansion flag are related but not “exactly” the same condition,
   and static review does not establish this as the sharpest inconsistency.

### C. Task metadata and response accuracy

1. Update `TASK-001_BASELINE_AUDIT.md:54–56` for unresolved set provenance.
2. Update `TASK-001_BASELINE_AUDIT.md:68` (“New files only”) to distinguish the
   initial deliverables from the later correction modifications.
3. Remove stale statements at `TASK-001_BASELINE_AUDIT.md:87–89` and
   `:109–114` saying no Codex review occurred or that the second read is still
   pending.
4. Correct the old severity/protection wording at
   `TASK-001_BASELINE_AUDIT.md:99–104`.
5. Record correction commit `3f69469` at
   `TASK-001_BASELINE_AUDIT.md:223–227` and include all correction-commit paths,
   including `TASKS.md`.
6. Do not state at `TASK-001_BASELINE_AUDIT.md:234/239` that every required
   change is applied while the items above remain open. `TASKS.md:11` should
   return to a “Findings open” status after this disposition.
7. In the response itself, “three corrected documents” conflicts with its list
   of five, and the two unscoped `git diff <tag>` commands were not empty. State
   the actual scoped checks instead.

## Decision

The original **CHANGES REQUESTED** disposition cannot yet be lifted. This is a
narrower second-pass rejection than the first: the core source traces, hashes,
counts, restart diagnosis, completed-candle finding, and most new cross-cutting
findings now verify. Approval is blocked by the omitted optional partial-close
account-mode issue and the remaining factual/internal inconsistencies listed
above.

After those documentation corrections, a focused consistency re-review should
be sufficient. No baseline source edit and no claim of profitability or live
safety is requested or implied.
