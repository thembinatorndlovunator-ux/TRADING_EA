# Codex Thirteenth Review — TASK-001 Round-Twelve Response

**Disposition: CHANGES REQUESTED — NOT LIFTED**

Commit `ce9f712` fixes a substantial portion of the twelfth review, but the
four-document audit package is still not source-factual and internally
consistent throughout. In particular, the claimed trendline-count correction
was not actually applied everywhere, several risk/formula statements remain
under-qualified, and this fresh source sweep found material behaviors that the
audits still omit.

The detailed record below contains **45 labeled findings**: A1–A7 (7),
B1–B21 (21), C1–C10 (10), and D1–D7 (7).

## Review target and method

- Branch reviewed: `claude/task-001-baseline-audit`.
- Commit reviewed: `ce9f712643d9dff6ac9a24ae8087233561d5c47e`.
- Parent used for the correction diff:
  `a0f4ac3ce5a98435dfb8bd13aa7c0325e5260555`.
- Response reviewed:
  `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round12.md`.
- Sources independently checked:
  - `01_BASELINE/EA_V637/Thembabot14 Max.mq5` — 8,822 lines;
  - `01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5` — 2,397 lines.
- I inspected the actual `a0f4ac3..ce9f712` patch, every cited function/input
  and source range in both individual audits, the comparison mirrors, the task
  file's Git/process history, and the arithmetic/formulas. This remains static
  review only: no compilation, backtest, terminal, broker, restart, or
  concurrent-instance experiment was performed.

Git reports exactly six paths in `ce9f712`:

- added
  `09_HANDOVERS/claude_to_codex/TASK-001_review_response_round12.md`;
- modified
  `09_HANDOVERS/codex_to_claude/TASK-001_review.md`,
  `TASK-001_BASELINE_AUDIT.md`, `baseline_comparison.md`,
  `baseline_v637_audit.md`, and `baseline_v811_audit.md`.

It did not modify `TASKS.md` or any path under `01_BASELINE/`. The task file's
“first commit after `a0f4ac3`” locator resolves uniquely to `ce9f712`. At the
start of this review, its pass-12 “applied/pending review” status is the correct
pre-review state; the response to this review should naturally record pass 12
as addressed in `ce9f712` and add pass 13 as the new pending-review pass.

## Immutable-baseline verification

**PASS — both complete EA directories, including both `IDENTITY.md` files, are
byte-identical to their preservation tags.**

- `EA_V637` has tree
  `fe46191174b150c4c1e0dceb1bffc6c42a076384` at both HEAD and
  `baseline-v637`:
  - `IDENTITY.md` blob
    `5bc1a9b4a3198f5575d9efc35ad723242ac4b2d6`, SHA-256
    `60172420BDE832187466D27A364977B4F71C7390DF389B4795A6200B8394E382`;
  - source blob `26018c013b60e371c112cea4f57552884d1e6902`, SHA-256
    `C35BCC7E0095D60B0C672FAEEBA696B4DB8587B0AFB80E6EFBBFDC8ACCDFBC1D`.
- `EA_V811` has tree
  `3bc9e68939873de57c70319ff75f3b39ffd58c75` at both HEAD and
  `baseline-v811`:
  - `IDENTITY.md` blob
    `e1ba7a7b741969d96b07db179edd9dfa82c0b44a`, SHA-256
    `A1286C257D32A95D18A7B2719A649DDC6FCF4EBFCBD2D71FDED20678561D367E`;
  - source blob `f0644ad8a3ce8f7471d3e3ed8393c375977ac551`, SHA-256
    `B5740327F6D84FD7C00807001418DF0FCC3912A8101BCA2DBB55DE0E51CD1F1B`.

Both scoped tag diffs are empty. I also checked every commit reachable after
the baseline import `0d65f95` through `ce9f712`; none changes either preserved
EA directory. Each directory contains exactly the two tracked files named
above.

## Round-twelve response: item-by-item result

- **A1/A2: partial.** The unsupported broad-sweep/progressive-narrowing claims
  were removed from the Acceptance narrative, but the Commit entries still
  recreate the progressive “narrower still” story; see A3.
- **A3 and A5: verified.** The tense-defect location and `79f8e5a` diff are now
  described materially correctly.
- **A4: partial.** The round-11 tense was repaired, but the same self-expiring
  wording was immediately repeated for round 12; see A4.
- **A6: acknowledged correctly, then repeated.** See A2.
- **A7: partial.** Files affected and Acceptance now recognize both complete EA
  directories, but Rejection and Commit evidence still omit the two identity
  files; see A5.
- **B1: partial.** The flat/calm pilot ratios are numerically right, but their
  runtime conditions and XAU symbol-key condition are not propagated; see B10.
- **B2–B5, B7, B9, and B10: the targeted edits materially check out**, subject
  to the additional source and mirror findings below.
- **B6 and B8: partial.** A stale pilot mirror and stale classifier-summary
  wording remain; see B9/B16.
- **B11: not fully applied.** The response says both trendline locations now
  use “three mechanisms/four implementations”; the V6.37 audit and comparison
  feature table still say three implementations; see B1.
- **C1: partial.** The percentage floors and zero-budget branch were corrected,
  but the displayed underwater formula still omits the outer zero clamp; see
  C1.
- **C2: partial.** The stale runtime message is identified, but the per-leg
  number still lacks the condition that a two-leg split remains viable; see C6.
- **C3: verified.** The underwater fallback cases and zero-budget early return
  are correctly derived.
- **C4–C10: the new body findings are directionally correct**, but close-result
  wording, recurrence/scoring claims, summaries, and comparison mirrors remain
  inconsistent; see C4–C10 and D2–D6.

The arithmetic that does check out is: `186/256 = 72.65625%` (72.7%) for the
literal eight-trade two-tail event; `185/256 = 72.265625%` (72.3%) for the
implemented behavior-changing event after excluding zero wins;
`1.18 × 1.20 = 1.416`; 48 M30 bars = 24 hours; and a 3R-to-2.9R pullback is
3.33% of peak R. V6.37 also still has 282 real inputs, 25 group headings, and
a 44-field journal schema; V8.11 has 107 inputs and 9 group headings.

## A. Package and Git-history findings

### A1 — Round 12 had 28 findings, not 26

**Locations:** round-12 response lines 11–13;
`TASK-001_BASELINE_AUDIT.md` Acceptance line 485 and Commit lines 803–815.

The prior review contains A1–A7 (7), B1–B11 (11), and C1–C10 (10): 28
labeled findings. The response happens to contain 26 response actions because
A1/A2 share a bullet and A6 was acknowledged without an edit. “26 findings”
and “26-item open sweep” are therefore false; the durable description is “28
findings handled in 26 response bullets/actions.”

### A2 — The response repeats the path-list overclaim it acknowledges

**Location:** round-12 response lines 40–45 and 162–167.

The response correctly admits that Reviewer chain does not enumerate the six
changed paths, then says the six-path list was confirmed in
“Files affected/Commit/Reviewer-chain.” Files affected enumerates the paths;
Commit references that list; Reviewer records response filenames. Git confirms
the six paths, but not the response's claim about all three sections.

### A3 — The unsupported monotonic-narrowing story remains in Commit

**Locations:** `TASK-001_BASELINE_AUDIT.md` Acceptance lines 370–384 versus
Commit lines 647–650, 662–664, 675–679, 688–695, 704–710, 718–727,
735–743, and 752–759.

Acceptance now correctly says Git does not establish monotonic narrowing.
The successive Commit entries still say “narrower” and “narrower still” for
passes 2 through 9, recreating precisely the unsupported qualitative history
that the response says it removed. Retain concrete finding descriptions and
remove the comparative ordering.

### A4 — The Reviewer-chain annotation is already stale at `ce9f712`

**Location:** `TASK-001_BASELINE_AUDIT.md` lines 871–872.

It says round 12's filename is stated “before its own commit exists.” At the
reviewed HEAD, `ce9f712` exists and contains that file. Use past tense and the
known hash, or rely on the durable first-child locator without a self-expiring
temporal clause.

### A5 — Rejection and Commit evidence omit both immutable identity files

**Locations:** `TASK-001_BASELINE_AUDIT.md` lines 557–563 and 823–831, versus
the correct complete-directory wording at lines 238–263 and 347–350.

The former sections enumerate preserved evidence as two MQ5 files, the set
file, and screenshots. Git proves each EA directory also contains and preserves
an `IDENTITY.md`. All four sections should describe the same evidence set.

### A6 — Commit entry 7 does not record or reference the full `c73947b` path set

**Location:** `TASK-001_BASELINE_AUDIT.md` lines 680–687.

Git shows eight paths in `c73947b`, including the overwritten
`09_HANDOVERS/codex_to_claude/TASK-001_review.md`. The Files-affected entry at
lines 134–140 records this; Commit entry 7 neither names that review file nor
clearly points to the canonical path list. Make it an explicit reference.

### A7 — Two process-history explanations are not verifiable from Git

**Locations:** `TASK-001_BASELINE_AUDIT.md` lines 360–365 and 573–577.

Git establishes that status prose drifted; it does not establish the asserted
cause (“not because facts were unclear ... because ... paraphrases drift”). It
also cannot prove that two agents each read an entire source file end-to-end.
These may be retained as attributed process attestations, but not presented as
independently verified historical facts.

## B. V6.37 source and audit findings

### B1 — The trendline count and timeframe are still wrong

**Locations:** `baseline_v637_audit.md` lines 26–30;
`baseline_comparison.md` line 75; `TASK-001_BASELINE_AUDIT.md` line 31;
round-12 response lines 100–102.

The source has four entry implementations: `EvaluateSRChannel` (2452),
`EvaluateTrendBreaker` (2562), `BuildTrendlineTouchSignal` (7573), and
`BuildTrendlineBreakRetestSignal` (7663). They can be grouped as three
conceptual mechanisms because the dedicated pair shares a mechanism, but they
are not three implementations. Audit line 28's “H1/H4” is also false as a
shipped-default statement: `EvaluateTrendBreaker` reads configurable
`InpTrendHigherTF2`/`InpTrendHigherTF1` at 2572–2576, whose defaults are M15
and H1 at 149/148. The response's B11 “fixed at both locations” claim is false.

### B2 — The purported M5 FVG confirmation actually uses the entry timeframe

**Location:** `baseline_v637_audit.md` lines 37–39.

`HasFVGM5Confirmation` copies `InpEntryTF` at source 1628; that input defaults
to M3 at line 147 and is configurable. The source's function/input names and
comments are themselves stale “M5” labels. The audit should state the actual
entry-TF behavior rather than silently inheriting the misleading identifier.

### B3 — `FindClusterBoundary` does not fall back to an intact cluster

**Location:** `baseline_v637_audit.md` line 44.

Source 7895–7920 first chooses the highest-touch/nearest cluster without
checking invalidation. It then returns `false` at 7925–7927 if that winning
cluster is invalidated; it does not select the next-best intact cluster. Thus
“keeps the highest-touch-count cluster that is not invalidated” is false.

### B4 — The self-confirmed-bypass paragraph contradicts itself and the comments

**Location:** `baseline_v637_audit.md` line 55.

The paragraph first says the two bypass checks are identical, then correctly
describes their difference. Source 1895 applies only `IsSelfConfirmedSetup` in
the PD gate; source 2001–2003 additionally accepts `OB_SR_` in the SR gate.
The audit also calls that asymmetry undocumented, but source comments 1997–2000
explicitly explain that OB+SR bypasses horizontal SR while premium/discount
still applies.

### B5 — `AnalyzeStructure` is not one consistent BOS/CHoCH definition

**Locations:** `baseline_v637_audit.md` lines 59–60;
`baseline_comparison.md` line 72.

`AnalyzeStructure` (4791–4839) is one live classifier.
`FindRecentStructureShiftLevel` (1176–1205) is a different live older-swing
break test, and `BuildBOSRetestSignal` combines the mechanisms at 7777–7788.
`HasEntryCHOCH` (5013–5025) is a third, dead definition. “Canonical, clean,
single definition used consistently” is contradicted by both source and the
next audit bullet.

### B6 — The M30 order block is not guaranteed to be an untouched first return

**Location:** `baseline_v637_audit.md` line 66.

`ScanM30OrderBlock` starts at candidate `i=2` (8316). In that case `rates[1]`
is simultaneously the displacement candle at 8324 and the alleged current
return/rejection candle consumed at 8512–8516. For older candidates, the
mitigation loop at 8337–8338 excludes both `rates[1]` and `rates[2]`, so a
prior touch at index 2 is ignored. The comment claims first return; the code
does not enforce it.

### B7 — The two named OB integration paths are not identically H1-gated

**Location:** `baseline_v637_audit.md` line 68.

The standalone builder has the opposing-H1/fresh-shift check at 8497–8500,
and the separate pending-order path has it at 8680–8683. The named score
modifier `ApplyOrderBlockConfluence` (8554–8576) has no such check. The audit's
second citation points to a third path, not the second path named in its claim.

### B8 — Two pending-order guarantees conflict with source and with the audit

**Locations:** `baseline_v637_audit.md` lines 74 and 76, plus its own account-
mode finding around line 195.

- When the feature is disabled, source 8637–8641 ignores `OrderDelete`'s
  result and deletes the tracking keys regardless. It attempts cleanup; a
  failed cancellation can leave an untracked live order.
- On fill, source 697–699 stores risk under a key built from
  `DEAL_POSITION_ID`, while management reads a key based on `POSITION_TICKET`
  at 5997–6002. Those identifiers are not guaranteed interchangeable, as the
  audit itself already notes. Line 76 therefore cannot guarantee that
  trailing/giveback uses the stored actual-fill risk.

### B9 — “Pilot trade of a fresh trend” is not an identity-enforced invariant

**Locations:** `baseline_v637_audit.md` lines 80–81, 155, 174, and summary
row 6 at 234; `baseline_comparison.md` line 78.

`CalculateVolumeForRisk` checks only symbol/magic-scoped `PilotStage()==0`
at 2865; it stores no pilot ticket, direction, setup, or trend identity. Any
setup/direction can consume stage 0, including while the stored trend is zero.
`UpdatePilotTrendState` can let any same-symbol/magic position confirm stage 2
at 6953–6977, and any same-symbol/magic exit while stage 1 can confirm/reset it
at 720–737. Line 155 also still says one minimum-lot position until confirmed,
contradicting line 80's own configurable-position, pending-before-fill, and
journal-gated qualifications. Describe a symbol/magic stage-based minimum-lot
mode, not an identity-specific pilot guarantee or a universal single-position
throttle.

### B10 — The pilot-ceiling ratios still omit required runtime conditions

**Locations:** `baseline_v637_audit.md` lines 81, 174, and summary row 6 at
234; `baseline_comparison.md` lines 212–214 and 468–474.

Source 5889–5913 gives approximately 0.8% non-XAU and 0.2% XAU only when
equity is at least balance, volatility factor is 1, no news reduction applies,
and no existing position applies the add-on factor. If balance exceeds equity
or any factor is below 1, the implemented budget is lower and the
5%-ceiling-to-budget ratio is greater than 6.25×/25×. The XAU result also
requires the case-sensitive configurable key `InpXAUUSDSymbolKey` (default
`"XAU"`) to match `_Symbol` at 5766–5770. Comparison line 212's “1.0%–2.0%
standing budget” is independently false: 2% is a cap, while the XAU raw input
is 0.25% and the implemented budget is state-dependent.

### B11 — Favorable add-on spacing is fail-open

**Location:** `baseline_v637_audit.md` line 82.

`AddOnConditionsMet` returns `true` at 8089–8091 when ATR is unavailable,
bypassing the spacing test. Same-direction is enforced, but favorable spacing
is conditional on obtaining a valid ATR; the blanket “both pieces enforce”
claim is too strong.

### B12 — The profit-lock ordering “hypothesis” is settled by the source

**Location:** `baseline_v637_audit.md` line 120.

Source 7130–7136 attempts the stop modification before the giveback block at
7144–7158. The giveback predicate reads `rr` and `peak`, not `sl`, and local
`sl` is updated after a true modification result. There is explicit statement
order and no unresolved same-pass ordering question of the kind asserted.

### B13 — Two historical-target descriptions use the wrong mechanism/timing

**Locations:** `baseline_v637_audit.md` lines 125–126.

- The “M30/H4 major swings” at 1861–1872 call ordinary
  `FindQualifiedFractalTarget`, whose depth comes from `InpFractalDepth`.
  They do not use `IsConfirmedMajorSwing`/`InpMajorSwingDepth` at 4217 onward.
- The ladder is not universally created at trade-open time. Pending fills at
  697–699 store only risk, and `EnsureStagedTargetState` can first create the
  targets later from `ManageStagedHistoricalTargets` at 6120. Restored or
  otherwise missing-state positions can also be initialized during management.
  The supportable invariant is that existing stored ladder state is not
  continually re-derived, not that all state is born at open.

### B14 — Two pipeline claims ignore bypass/configuration branches

**Locations:** `baseline_v637_audit.md` lines 146 and 148.

- Although `IsSelfConfirmedSetup` contains `NFP_`, the live NFP entry path at
  632–638 calls `OpenSignal` directly. It bypasses
  `SelectBestIndependentSignal`, regime routing, OB score modification, and
  learning. NFP therefore does not “skip only gates 1 and 2” and traverse
  gates 3/5; the audit already recognizes this bypass at line 91.
- `BuildRangeCycleSignal` requires ranging at 7945 only when configurable
  `InpRangeCycleOnlyWhenRanging` is true. Its Trending-regime router can fire
  when that input is false. The overlap is shipped-default redundancy, not an
  unreachable branch in every configuration.

### B15 — The signal-family count has no consistent arithmetic basis

**Location:** `baseline_v637_audit.md` line 153.

`BuildCombinedSignal` contains 11 top-level families: SR, Trend, and nine
others. Replacing the SR umbrella with its six methods and Trend with its two
methods produces 17; counting direction-specific candidate objects produces
20. Neither “at least 13” nor “twelve to fourteen” follows from the stated
taxonomy.

### B16 — Summary row 9 reintroduces the classifier-vocabulary overclaim

**Location:** `baseline_v637_audit.md` summary row 9 at line 237.

`IsSyntheticIndexSymbol` has seven terms at 7233–7241;
`DirectionAllowedForSymbol` recognizes only boom/crash at 6678–6698. Naming
mismatches for jump/step/range-break/drift affect NFP classification only, not
both filters. The body at line 134 is correct; the summary is stale.

### B17 — The fractal-depth contradiction is stated against the wrong promise

**Locations:** `baseline_v637_audit.md` lines 21 and summary row 13 at 241;
`baseline_comparison.md` lines 145–148.

The line-201 comment does not promise one input for every fractal subsystem;
it specifically says `InpStructureSwingDepth` is used by SR, structure, and
FVG. The direct contradiction is within FVG context itself: `AnalyzeStructure`
uses `InpStructureSwingDepth` at 1593, while
`FindRecentStructureShiftLevel`/`FindFVGLinkedBreakOfStructure` reaches
`FindTwoConfirmedSwingsBefore`, which hardwires `InpFractalDepth` at 1156.
Trend/dealing-range having other inputs is fragmentation, but does not by
itself falsify that narrower comment.

### B18 — A material learning-sign defect is absent from the audit

**Location:** the learning discussion at `baseline_v637_audit.md` lines
98 and 166–176.

At source 3697–3700, a strategy with win rate above 50% but net loss enters the
`else` branch and subtracts `(0.50-win_rate)`, a negative number. It is boosted,
not penalized. With 60% wins and default 14% penalty, the factor gains 2.8%.
The regime branch repeats the sign error at 3730–3733, gaining 4% under the
default 20% penalty. A 50%-win/net-loss bucket receives no penalty. This is a
direct arithmetic/control-flow defect in the very learning system being
audited and belongs in the body and summary.

### B19 — Market-entry R management mixes requested and actual prices

**Location:** missing from the V6.37 sizing/management findings, especially
`baseline_v637_audit.md` lines 76, 115–120, and 186–195.

Market entries sample a requested quote at 2707 and store requested
`abs(entry-sl)` at 2796/5965–5976. Management and pilot confirmation then use
actual `POSITION_PRICE_OPEN` at 3034/6963 but divide by that requested risk at
3042–3050/6967–6974. Slippage therefore distorts R, break-even/trailing/
giveback, and pilot-confirmation thresholds. This is the V6.37 analogue of the
requested-fill defect newly documented for V8.11.

### B20 — Several close/delete outcomes are still stated as guarantees

**Locations:** `baseline_v637_audit.md` lines 74, 103, and 117;
`TASK-001_BASELINE_AUDIT.md` lines 294–296;
`baseline_comparison.md` lines 231–232 and 320.

V6.37 ignores the result of daily-lock `PositionClose` at 3399, giveback
`PositionClose` at 7157 (then deletes the peak key at 7158), and several
`OrderDelete` calls at 8639/8692/8704. These paths implement attempts, not
verified force-closes/closures/cleanup. The audit partly admits this at line
118, making the remaining “closed outright,” “force-close,” and “genuinely
enforced” wording internally inconsistent.

### B21 — Two material persistence/fail-open risks remain uncatalogued

**Locations:** `baseline_v637_audit.md` lines 18 and 52/159.

- `HasHTFLevelNear` returns `true` when no H4 levels or ATR are available at
  7392–7393. `FindSRZone` then passes the hard H4-confluence requirement and
  awards the positive confluence bonus at 5107–5111. Missing data is treated
  as affirmative confluence, not merely “not punished.”
- The locked-range keys at 7169–7177 contain only symbol and magic, while the
  stored range depends on configurable timeframe/depth/range settings. A
  settings change can reload a range produced under older semantics until a
  later break/reset. The persistence discussion does not disclose that
  configuration-staleness risk.

## C. V8.11 source and audit findings

### C1 — The underwater `RiskBudgetCash` equation still omits the zero clamp

**Location:** `baseline_v811_audit.md` line 102.

For shipped defaults and `E>0`, source 1509–1513 gives
`RiskBudgetCash/E = 0.01 × max(0, 1 − 0.2B/E)` in the `B>E` branch. The
document omits `max(0,...)`; its displayed expression becomes negative below
`E=0.2B`, while the source remains zero for every `E<=0.2B`. The boundary
prose is right, but the equation is not. Independent checks: `B=100`,
`E=80/50/25` yields 0.75%/0.60%/0.20% of equity and 2%-cap ratios
2.6667×/3.3333×/10×; `E<=20` yields zero.

### C2 — Sweep/shift lookback and final-stop formulas are incomplete

**Location:** `baseline_v811_audit.md` line 25.

Source 1008–1012 scans
`4..min(copied-2,4+max(10,InpSweepLookback))` inclusively (31 pool bars at
default 30). Source 1036–1049 scans
`2..min(copied-2,2+max(3,InpShiftLookback))` inclusively (7 micro bars at
default 6), not simply “the following 6 bars.” The eventual stop at 1292–1310
also adds spread, applies an ATR floor, rejects an over-cap distance,
normalizes, and recomputes distance; if the floor fires, it rebuilds the stop
from entry rather than retaining the raw sweep extreme plus buffer.

### C3 — Six threshold formulas omit their source-enforced floors

**Locations:** `baseline_v811_audit.md` lines 29, 37, 47, 75, 77, and 81.

- Cluster tolerance is `atr*MathMax(0.05,InpClusterTolATR)` at source 608.
- FVG minimum is
  `MathMax(3*_Point,atr*MathMax(0.03,InpFVGMinGapATR))` at 830.
- Pin wick uses `2*MathMax(Body,_Point)` at 1707/1714.
- Effective BE threshold is `MathMax(0.3,InpBasketBreakEvenAtR)` at 1426.
- Trail start/step are `MathMax(0.5,InpTrailStartR)` and
  `MathMax(0.2,InpTrailStepR)` at 1438/1440.
- Giveback arm/floor are `MathMax(0.3,InpGivebackArmR)` and
  `MathMax(0.0,InpGivebackFloorR)` at 1448–1449.

The stated defaults happen to exceed these floors, but the claims are written
as general configurable-input formulas.

### C4 — The manual news times recur daily, and midnight is mishandled

**Locations:** `baseline_v811_audit.md` line 110;
`baseline_comparison.md` lines 249–253.

Source 2339–2344 begins with the current date and replaces its hour/minute, so
every configured `HH:MM` recurs every calendar day. What is absent is
date-, weekday-, and event-specific scheduling, not recurrence. Because the
event is always built on the current date, before/after windows crossing
midnight are truncated. Audit line 110 also ends by saying blank/“invalid”
times provide no protection, reintroducing the overclaim corrected earlier in
the same paragraph: only empty, under-four-character, and colonless strings
are rejected; other malformed colon-containing strings are coerced and may
create a wrong window.

### C5 — Final scores are live-dynamic even though outcome learning is absent

**Locations:** `baseline_v811_audit.md` line 114;
`baseline_comparison.md` lines 280–281.

It is correct that there is no journal/outcome-feedback learning and base
scores are input constants. It is false that “all scoring” is static: live
sweep/touch/bias bonuses occur at 1088–1120, refined-OB/bias bonuses at 1164,
FVG bias at 1205, momentum strength/bias at 2257–2278, and OB/momentum
confluence at 922–945. Say fixed non-learning base scores with live evidence
bonuses.

### C6 — Risk wording still confuses nominal, modeled, and per-leg amounts

**Locations:** `baseline_v811_audit.md` lines 7 and 122, plus summary row 9 at
219.

Line 122 calls the comparison a “sized 1% budget”; source 1505–1514 produces
0.8% of equity for `E>=B`, less when `B>E>0.2B`, and zero at/below `0.2B`,
apart from the minimum-lot exception. “Nominal 1% input” is accurate. Its
claim that spike-prone synthetics are the exact class guarded by
`DirectionAllowed` is also too broad: source 1616–1628 recognizes boom/crash
substrings and broker long-/short-only modes, not all synthetic or spike-prone
instruments.

The approximately 0.4%-per-leg figure at lines 7/219 additionally requires a
viable two-leg normal split. Source 1328–1347 can reduce the requested default
to one leg; that one normal leg receives approximately 0.8%, and fallback can
differ further. This exposes a source-comment contradiction the audit omits:
header line 19 and group line 71 say 2–4 positions, while `LegsForScore`
1276–1280 and sizing 1328–1347 permit one.

### C7 — Status and execution wording still claims outcomes not established

**Locations:** `baseline_v811_audit.md` lines 71, 75, and 81.

- Line 71 calls `g_last_action` “printed/journaled.” V8.11 has no journal.
  Source 1394–1398 sets it, conditionally prints it, and source 2111 displays
  it on the dashboard.
- Line 75 says `ManageBasket` “moves all legs” to BE, and line 81 says the
  giveback path closes the basket. `MoveBasketStops` and `CloseBasket` ignore
  `CTrade` results at 1467–1500; source 1431 marks BE done even if every stop
  modification failed. These are modification/close attempts.

The same stale outcome language remains in comparison lines 231–232/320 and
task line 45 (“hard 45-minute time exit”), despite the detailed audit correctly
describing the time exit as an unchecked attempt.

### C8 — The round-12 additions were not carried into the audit summary

**Location:** `baseline_v811_audit.md` summary table, lines 209–225.

The table omits the requested-price R/BE/trail defect from line 66, the
truncated-magic/account-unspecified peak-DD key collision from line 98, and the
partial-submission wrong-TP status from line 71. Summary row 3 also omits the
four-week-without-access expiry qualification now present in body line 97.
The response says these findings were added; the document's own contradictions
summary should not silently drop them.

### C9 — The document's “no correctness claims” statement is literally false

**Locations:** `baseline_v811_audit.md` lines 126 and 227;
`baseline_comparison.md` lines 78 and 215;
`TASK-001_BASELINE_AUDIT.md` lines 557–569.

The audit explicitly says “the core math is correct,” while its closing line
says no correctness claim is made anywhere. The comparison repeats the claim,
and the task says no rejection criterion occurred. Narrow this to “no blanket
EA/runtime correctness claim”; a limited modeled-math conclusion must itself
carry the requested-fill, rounding, submission-success, and slippage conditions
in D4.

### C10 — Two further visual/state contradictions are absent

**Locations:** the range/visual discussion in `baseline_v811_audit.md` around
lines 29 and 146–150, and the startup discussion at line 7.

- Source comment 463 says `g_range_start` is the older boundary origin, but
  line 464 assigns a fixed lookback-bar time; `FindClusterBoundary` returns no
  origin. The strong/weak scan at 472–480 is also not restricted to bars after
  the selected boundary formed, so an older wick can mark a newly selected
  boundary “Strong.”
- `OnInit` line 279 hard-codes 0.60–1.40 stops and two legs as well as the
  already-noted 0.5% figure, despite configurable inputs at 72–74/90–92.
  Dashboard line 2020 hard-codes `H1`/`M30` labels despite configurable
  `InpBiasTF`/`InpDirectionTF` at 50–51. These messages can misstate a valid
  operator configuration.

## D. Remaining comparison-document drift

### D1 — V8.11 SR is not “touch-count only”

**Location:** `baseline_comparison.md` line 71.

`FindClusterBoundary` ranks primarily by touch count, but source 644–652 uses
distance to current price as a tie-breaker, 657–669 invalidates after two
consecutive closes, and the function derives cluster width. “Touch-count only”
is false.

### D2 — The V8.11 peak-DD expiry correction is missing from comparison

**Location:** `baseline_comparison.md` lines 119–138.

The comparison describes `g_peak_dd` persistence outside Strategy Tester but
omits the four-week-without-access terminal-global expiry now correctly stated
in `baseline_v811_audit.md` line 97.

### D3 — The cross-instance row denies awareness that exists

**Location:** `baseline_comparison.md` line 218.

Same-symbol/same-magic exposure is seen by `CountOurPositions` at V8.11 source
1639–1653 and normally blocks a later basket at `OnTick` 307–308. The confirmed
gap is different symbols regardless of magic, or the same symbol with different
magic values. “No cross-instance awareness ... independent of magic” is too
broad and contradicts the corrected individual audit.

### D4 — Requested-fill correction is missing from comparison math/management

**Locations:** `baseline_comparison.md` lines 78, 214–215, 226–230, and
478–484.

V8.11 sizes from requested entry-to-SL at source 1286–1330; submissions can
fail at 1368–1383; actual fills are never read; and R/BE/trail/giveback use the
requested basis at 1419–1445. The comparison should say modeled requested-basis
risk, conditional on intended submissions succeeding and before volume
rounding, fill differences, gaps, and slippage. Line 480 is specifically wrong
to call 2.5× a cap on “realized risk”; the code caps modeled requested-price
stop risk, while realized loss can exceed it.

### D5 — Journal strengths omit the magic-isolation defect

**Location:** `baseline_comparison.md` lines 274–279.

V6.37's physical file is configurable/common, not intrinsically per-symbol,
and restart replay filters only by symbol at source 3586–3589. The schema has
no magic field. Same-symbol/different-magic instances sharing a filename learn
from each other's historical rows. “Per-symbol scoped” needs “not per-magic
isolated,” matching the corrected individual audit.

### D6 — The restart section falsely says both EAs scan positions and orders

**Location:** `baseline_comparison.md` lines 365–371.

V6.37 source 605–607 calls `CountOurPositions`, which counts positions only.
It does not count resting pending orders; that omission is part of the
pending-pilot-before-fill behavior already documented elsewhere. V8.11 scans
positions through its gate, but the blanket positions/orders claim does not
hold for both EAs.

### D7 — “H1/M30 direction + PD location only” is not V8.11's whole routing

**Location:** `baseline_comparison.md` line 86.

It is correct that V8.11 has no named regime classifier. “Only” is false:
`OnTick` 325–344 also applies session, news, spread, and global expansion
gates; `BuildBestSignal` 916–945 applies momentum/confluence; and individual
builders have setup-specific gates. Retain the no-regime-classifier comparison
without reducing all routing to two controls.

## Required disposition

The `changes requested` disposition **cannot be lifted**. No preserved baseline
source should be edited. Correct the documentation and response-history record,
propagate each correction through the individual-audit summaries, comparison,
and canonical task file, then return the package for another independent
review.
