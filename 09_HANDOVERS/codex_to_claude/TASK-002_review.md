# Codex Independent Review - TASK-002 Phase 2 Specification

**DISPOSITION: CHANGES REQUESTED**

`TASK-002_PHASE2_SPECIFICATION.md` is not ready for approval. The stated risk
percentages mostly match policy, and many baseline defects are correctly
identified, but the document does not yet fulfill the Phase 2 deliverable it
claims to complete. It omits mandatory risk controls, does not formalize the
candlestick/chart-pattern work assigned to Phase 2, provides no executable
regime or strategy-routing rules, leaves several named baseline contradictions
undecided, and contains source-factual and internal-history errors.

Phase 3 should not begin until these findings are corrected and independently
re-reviewed.

## Review target and method

- Branch: `claude/task-002-phase2-specification`.
- Commit: `cc58fa84090e285727634d31bcac75b2454fa488`.
- Parent/base: `2005d75c3027c2d426a5d530f0455477215c3fde`.
- Git reality: `cc58fa8` adds exactly one path,
  `TASK-002_PHASE2_SPECIFICATION.md`.
- Governing documents read in full: `AGENTS.md`, `PROJECT_RULES.md`,
  `00_MASTER_PROMPT_FOR_CLAUDE.md`, `STRATEGY_SPECIFICATION.md`,
  `RISK_POLICY.md`, `NEWS_INTEGRATION_SPEC.md`, and `TEST_PLAN.md`.
- Both immutable MQ5 sources were checked directly. The audit documents were
  used as indexes, not accepted as authority.
- Both complete baseline EA directories remain byte-identical to their tags;
  the scoped diffs against `baseline-v637` and `baseline-v811` are empty.
- This is documentation review only. No compilation or backtest is applicable
  or claimed.

Line references below are to commit `cc58fa8` unless stated otherwise.

## 1. Risk-policy verification

### 1.1 PASS - the percentages that are present match policy

`TASK-002_PHASE2_SPECIFICATION.md:131-134` accurately restates these values
from `RISK_POLICY.md:5-11` and master prompt section 13 at lines 816-825:

- XAUUSD: 0.25% per trade;
- other metals: 0.25%-0.50%;
- synthetic indices: 0.25%-0.50%;
- hard per-trade cap: 1.00%;
- hard total open-risk cap: 1.00%;
- daily loss cap: 2.00%; and
- weekly loss cap: 4.00%.

The add-ons/multi-leg default-off rule also passes: specification row 114 says
both are disabled by default, matching `RISK_POLICY.md:16` and master prompt
830-831.

### 1.2 The binding three-loss cooldown is missing

**Specification:** Risk section 129-176 and Acceptance 346-347.

`RISK_POLICY.md:12` and master prompt line 825 require cooldown after exactly
three consecutive losses. The number and rule appear nowhere in the
specification. Acceptance's claim that every hard numeric policy limit is
restated is therefore already false.

### 1.3 Other binding risk-policy rules are omitted or weakened

**Specification:** Risk section 129-176.

The section never normatively states:

- no martingale, grid, or averaging down (`RISK_POLICY.md:13-15`);
- reject broker minimum volume when its actual risk exceeds the cap
  (`RISK_POLICY.md:17`, master prompt 832);
- validate contract size (`RISK_POLICY.md:19`; specification 174-176 lists
  other broker properties but omits this one);
- never widen a stop merely to avoid a loss (`RISK_POLICY.md:21`); or
- close **all** exposure by the approved intraday boundary
  (`RISK_POLICY.md:20`).

Lines 69 and 184 mention same-session/session close, but do not define the
binding all-symbol/all-position boundary rule. Row 114 merely says to fix the
old minimum-lot fallback if baskets are later enabled; it does not impose the
policy's general reject-above-cap behavior.

The specification correctly states no risk increase after a loss at 138-142.

### 1.4 The caps are numbers without enforceable accounting definitions

**Specification:** 131-176.

For the 1% total-open, 2% daily, and 4% weekly caps, the document does not
define:

- account-wide versus symbol/magic scope;
- treatment of pending orders and correlated/multi-symbol exposure;
- requested risk versus actual fill/commission/swap/gap-adjusted risk;
- daily and weekly reset timezone/boundary;
- start-equity/balance denominator;
- inclusion of closed and floating P/L and costs;
- restart persistence; or
- whether a breach blocks entries, attempts closure, or both.

This omission is material because the specification itself cites V8.11's
daily numerator/denominator anchor mismatch at lines 42-43. Restating `2%`
without choosing the new numerator, denominator, boundary, and restart state
does not resolve that defect or formalize risk.

### 1.5 Master-prompt section 13's profit-protection requirements are largely
unformalized

Master prompt lines 836-856 additionally call for separate treatment of
account/daily equity-peak giveback, session profit lock, strategy and
consecutive-loss cooldown, session trade/failed-level-attempt limits, reduced
risk after drawdown, post-daily-target policy, and intraday closure. The
specification names some exit concepts, but supplies no defaults, state model,
priority, reset rules, or enablement decision for most of them.

## 2. Phase 2 and master-prompt compliance

### 2.1 BLOCKER - the specification omits mandatory Phase 2 deliverables

**Specification:** Objective 5-10, sections 1-8 at 65-288, Out of scope
303-306, Risks 324-329.

Master prompt section 23, lines 1391-1400, assigns Phase 2 all of the following:

1. intraday modes;
2. regimes;
3. strategies;
4. candlestick patterns;
5. chart patterns;
6. risk;
7. news; and
8. contradiction resolution before coding.

The Objective substitutes exits for candlestick/chart-pattern formalization.
The document contains no mathematical candlestick definition and no chart-
pattern definition, then explicitly defers strategy specifications to Phase 5.
That deferral conflicts with the roadmap: Phase 5 adds and tests already-
specified strategies one at a time; it does not move Phase 2's specification
work into the coding phase.

Consequently, lines 280-288 cannot yet declare Phase 3 the next task. Phase 2
is incomplete under the exact section the document cites.

### 2.2 Intraday modes restate characteristics but do not define a router

**Specification:** 65-82. **Master prompt:** 331-387.

The timeframe ranges, typical durations, and input list are copied accurately.
Missing are an objective mode score/formula, thresholds, precedence/tie rules,
hysteresis or change timing, confidence/fail-closed behavior, and actual mode-
conditioned timeframe mappings. The section also omits explicit requirements
for limited scalp attempts, no repeat at an unchanged level, metals rollover
closure, the synthetic daily boundary, and logging the selected mode plus
reason (master prompt 352-367 and 387).

An implementer still has to invent the behavior, so the mode is not formalized
or acceptance-testable.

### 2.3 The regime list is accurate, but no regime engine is specified

**Specification:** 84-104. **Master prompt:** 391-434.

The nine names, candidate evidence, completed-candle rule, confidence/reason/
transition outputs, and low-confidence behavior accurately reflect section 6.
But there is no formula, threshold, state precedence, directional-expansion
rule, confidence calculation, transition/hysteresis rule, or stale/data-failure
behavior. The required enum/module artifact, Python unit fixtures, and
screenshot-labelled confusion matrix (master prompt 424-432) are also absent.

`NEWS_BLACKOUT` and `UNTRADEABLE_SPREAD_OR_LIQUIDITY` are named without saying
whether they override directional regimes or coexist as gates. A nine-item
enumeration is not an objective non-repainting classifier.

### 2.4 The strategy table is a provenance table, not strategy routing

**Specification:** 106-127. **Master prompt:** 438-525.

The table selects source concepts, but never assigns each strategy family:

- eligible/prohibited regimes;
- eligible intraday modes;
- context and entry timeframes;
- prefer/penalize/block behavior;
- conflict priority;
- minimum regime confidence;
- no-trade outcome; or
- required strategy-switch journal fields.

It therefore omits the core trending/ranging/compression/expansion/transition
routing matrix in master prompt section 7. It also omits `No trade` as an
explicit family/outcome.

The taxonomy is internally inconsistent: lines 303-305 say there are six
families in the table, but it has five rows, combines chart-pattern and post-
expansion, and substitutes a non-strategy basket/add-on row for `No trade`.
Master section 7 reaches six by counting `No trade`, while roadmap Phase 5's
six implementation modules split sweep-shift from FVG/BOS. Stable strategy
IDs and one canonical count are required.

Line 112 also says the master prompt places V6.37 trendlines and V8.11 ASQ
momentum under one family. Section 7 names `Trend Following`, but does not make
that baseline-module attribution; it is this specification's architecture
decision and should be labeled as such.

### 2.5 The news provider list is accurate, but the news policy is missing

**Specification:** 213-232. **Master prompt:** 895-980.
**NEWS_INTEGRATION_SPEC.md:** 1-47.

The providers and much of the schema are accurate. `local time` at line 220 is
not the master prompt's explicit Botswana time field. More importantly, the
section does not define:

- high-impact pre-event blocking;
- no stop widening and no directional prediction;
- resumption only after blackout plus spread/volatility normalization;
- medium-impact handling;
- post-news trading disabled by default;
- USD relevance for XAUUSD/XAGUSD;
- stale/missing/provider-failure fail-safe behavior and logging;
- cache validation/deduplication;
- deterministic historical replay; or
- explicit macro-news bypass for synthetic indices beyond provider selection.

Those are the actual section-15/news-spec policies. Provider class names alone
do not formalize news behavior.

### 2.6 Signal scoring and `TradeDecision` mostly track sections 11-12, but
learning reuse does not satisfy section 18

**Specification:** 234-276. **Master prompt:** 721-807 and 1068-1093.

The score component list, correlation warning, `TradeDecision` fields, and
common-consumer rule are substantially accurate. The learning paragraph,
however, mentions only the sign and symbol/magic defects. It omits section
18's confidence intervals, tested recency weighting, bounded influence,
logic-version reset, prohibition on old-version outcomes, sample-plus-loss
benching, and human-readable reason.

It also omits confirmed V6.37 defects that matter to reuse: disabling journal
writing freezes live memory updates even when learning remains enabled; regime
is attributed at close rather than entry; NFP/pending paths bypass ordinary
benching; and the ordinary same-regime path lacks a clear re-evaluation/
recovery mechanism. See source 662-663/759, 3544-3551, 3623-3628, and
3711-3739 plus `baseline_v637_audit.md`'s learning sections.

### 2.7 The exit section lists capabilities without selecting most behavior

**Specification:** 178-211. **Master prompt:** 860-891.

The supported-capability list and comparison points are cited accurately, but
the document does not choose fixed-R versus structure/liquidity target,
break-even trigger/evidence, structure versus ATR/swing trail precedence,
time-stop formula, or exit priority when triggers conflict. The target callout
rejects both baseline stage schemes, then delegates the actual selection to
whichever logic later "proves useful." That is a research plan, not the Phase
2 target policy an implementation can follow.

Defaulting both giveback models off pending Phase 8 is a valid current decision.
However, lines 196-200 attach V6.37's profit-lock stop-validation defect to the
giveback model. Profit lock is a separate exit; disabling giveback does not
resolve whether profit lock survives or how its post-clamp improvement check
works.

### 2.8 The architecture-alignment claim lacks responsibilities and test
boundaries

**Specification:** 278-288. **Master prompt:** 1302-1370.

The named modules and roadmap ordering are generally accurate, but saying the
specification maps directly to section 22 is premature. It supplies no module
responsibility/interface/test-boundary map, even though line 1370 requires a
clear responsibility and test boundary. The missing boundaries are precisely
where `StateManager`, `StrategyRouter`, `ConflictResolver`, risk persistence,
trade reconciliation, and a shared trading/visual structure source must own
the decisions left open above.

### 2.9 One master-prompt citation is mapped to the wrong subject

**Specification:** 113.

Master sections 9-10 cover candlestick and chart-pattern engines. They support
fresh candlestick/chart-pattern work, but post-expansion routing comes from
section 7, not sections 9-10. Split that combined row and cite each concept's
actual governing section.

## 3. Baseline source-factual findings

### 3.1 V6.37 pilot ratios are not a bounded `6.25x-33.33x` range

**Specification:** 32-33 and 114; also 135-137.

Source `EffectiveRiskPercent` 5773-5780, `CalculateAllowedRiskCash` 5889-5913,
Rotation haircut 2811-2818, and pilot branch 2865-2879 show four conditional
reference ratios when equity is at least balance and volatility/news/add-on
factors are all 1:

- non-XAU, non-Rotation: `5 / 0.8 = 6.25x`;
- XAU, non-Rotation: `5 / 0.2 = 25x`;
- non-XAU Rotation: `5 / 0.6 = 8.33x`; and
- XAU Rotation: `5 / 0.15 = 33.33x`.

Thus the ratio depends on symbol profile **and** setup, not only setup.
Underwater equity or volatility/news/add-on reductions shrink the ordinary
budget and can push the ratio above 33.33x. The pilot uses broker minimum lot,
so actual risk may also be below the ordinary budget. Finally, 5.0% is the
shipped value of configurable `InpPilotMaxActualRiskPercent` at source line
110, not an immutable constant. Correct all three distinctions.

### 3.2 V8.11's time exit is configurable and conditional on intact runtime
state

**Specification:** 39-40 and 78-82.

`InpMaxHoldMinutes` is a configurable input defaulting to 45 at V8.11 source
82 and is disabled when nonpositive. Source 1455-1458 uses strict `>` and acts
on a subsequent tick; `CloseBasket` 1485-1500 does not verify close results;
restart state causes the early return at 1416-1417. It is an evidence-
unconditioned configurable wall-clock close attempt, shipped default 45, not a
hard/fixed 45-minute guarantee.

The statement that no dynamic risk management survives restart is also too
broad. Basket-specific BE/trail/giveback/time/direction-flip state is lost, but
broker-held current SL/TP survives, and `CheckDailyLimits` 1544-1563 can still
attempt a close based on live positions.

### 3.3 The baseline timeframe descriptions are overcompressed

**Specification:** 74-76 and 111.

V8.11's five hierarchy roles are configurable inputs `InpBiasTF` through
`InpEntryTF` at source 50-54, and momentum has a sixth configurable
`InpMomTF` at 142. Its OB path is `InpWorkingTF -> InpRefineTF`; M15 -> M5 is
only shipped-default shorthand. V6.37 likewise has multiple configurable role
timeframes (`InpStructureTF`, `InpEntryTF`, two higher TFs,
`InpTrendExecutionTF`, dealing-range, OB, supply/demand, and trendline TFs),
plus hard-coded exceptions. Describe fixed **roles/defaults**, not two simple
fixed-timeframe assumptions.

### 3.4 The promised V8.11 sweep/shift/stop formula is absent

**Specification:** routing row 111.

The row says to fix the audit by stating the real formula, but never states or
selects one. Actual V8.11 source is:

- pool indices
  `4..min(copied-2,4+max(10,InpSweepLookback))` inclusive at 1007-1012:
  minimum 11 bars, 31 at shipped input 30 when history is sufficient;
- shift indices
  `2..min(copied-2,2+max(3,InpShiftLookback))` inclusive at 1034-1050:
  minimum 4 bars, 7 at shipped input 6; and
- final stop at 1292-1310: raw stop plus
  `ATR*max(0.05,InpStopBufferATR)+spread`, rebuild to
  `ATR*max(0.10,InpMinStopATR)` if too close, reject above
  `ATR*max(InpMinStopATR+0.05,InpMaxStopATR)`, then normalize and recompute.

An instruction to specify this later is neither a formula nor a contradiction
decision.

### 3.5 V8.11's ladder numbers and "two live rungs" need configuration and
account-mode qualifiers

**Specification:** 204-205.

The 1.0/1.5/2.0/2.5R numbers are shipped defaults of configurable inputs at
source 75-78; source 1363-1366 floors TP1 and makes later rungs monotonic. Two
rungs are requested only when two legs remain viable, both submissions
succeed, and separate positions are supported. Sizing may reduce the count at
1328-1334, submissions can fail at 1368-1380, and netting collapses the legs.
Call this the default requested hedging plan, not an unconditional live ladder.

### 3.6 The news/symbol-classification contradiction is misattributed

**Specification:** 223-232.

Both named functions are in V6.37:

- `IsSyntheticIndexSymbol`, source 7233-7241, is the seven-term news-family
  heuristic; and
- `DirectionAllowedForSymbol`, 6678-6698, is the two-term Boom/Crash direction
  filter plus broker long/short-mode check.

V8.11's corresponding function is `DirectionAllowed` at 1616-1628. It is also
a direction filter, not real/synthetic news-provider selection. V8.11's manual
news windows at 2321-2346 are global/configuration driven and do not use a
symbol-family classifier. Symbol-profile provider selection is a sound new
news design, but it does not by itself decide the separate Boom/Crash direction
policy, and the stated V6-versus-V8 mapping is false.

### 3.7 The V6.37 weak-sample adaptation is not uniformly "widening"

**Specification:** 138-142.

At aggregate win rate below 45%, source widens the initial ATR stop multiplier
by 0.10 at 5752-5763 and delays trail arming by 0.15R at 6250-6258. But it also
reduces the active trail ATR multiple by 0.15 at 6261-6269 (tighter) and lowers
the soft-exit minimum R by 0.10 at 6272-6280. Moreover, risk-based sizing can
reduce volume when the initial stop widens, so stop geometry is not
automatically an increase in cash risk after the immediately preceding loss.
The mechanism may be retired, but the decision must describe the four effects
and distinguish aggregate weak-sample adaptation from a per-loss lot increase.

### 3.8 Configurable giveback defaults are presented as invariant models

**Specification:** 188-190.

V6.37's 1.25R/60% and V8.11's 0.8R/0.1R are shipped input defaults, not hard
definitions. Effective source behavior is:

- V6.37: arm `max(0.25,InpGivebackArmRR)` and giveback percentage clamped
  10%-90% at 7144-7147; and
- V8.11: arm `max(0.3,InpGivebackArmR)` and floor
  `max(0,InpGivebackFloorR)` at 1448-1449.

Qualify the numbers as shipped defaults and state whether the new experiment
retains those clamps or defines new bounds.

### 3.9 The claimed development intent behind two regime defects is not
source-verifiable

**Specification:** 95-104.

The source verifies V6.37's classifier/router/sign arithmetic and V8.11's
expansion gate/momentum path. It does not establish that either defect "was an
attempt to patch a regime concept." That is a process-history inference. Label
it hypothesis or remove it.

### 3.10 The score-correlation paragraph mixes baseline attribution

**Specification:** 243-250.

V8.11 supplies the sweep-first/extra-touch/H1-bias bonus bundle at source
1088-1120. V6.37 supplies `ApplyOrderBlockConfluence` and its own touch-decay
and other bonuses. The current sentence makes these read like one V6.37 stack
and says both baselines exhibit the "exact" correlation failure without an
actual correlation analysis. Split the source attribution and treat double-
counting as a risk to be tested until the required Python audit establishes it.

## 4. Contradiction resolution and internal consistency

### 4.1 Replacing the regime classifier does not fix the learning sign error

**Specification:** 101-104 versus 143-147 and 273-276.

The bad subtraction at V6.37 source 3697-3700 and 3729-3733 is independent of
the number or definition of regimes. A nine-state classifier does not
"directly close" it. The later risk section correctly requires separate
arithmetic correction and unit tests. Remove the contradictory causal claim
from the regime section.

For reference, independent recomputation confirms the baseline defect: at
60% win rate and net loss, the default base branch subtracts
`0.14*(0.50-0.60)*2 = -0.028`, adding 2.8%; the regime branch similarly adds
4.0%.

### 4.2 The specification fails its own every-contradiction test

**Specification:** Test plan 333-339 and Acceptance 343-345.
**Comparison:** `baseline_comparison.md:158-214,302-426,488-495`.

Examples still lacking an explicit new-engine decision include:

- V8.11 chart-mark structure versus traded structure: require one canonical
  structure output consumed by both trading and visuals, or justify another
  choice;
- V6.37 Rotation versus expansion: the old coupling is deleted, but without a
  new regime routing matrix the spec never says if Rotation is allowed,
  penalized, or blocked in expansion;
- V6.37 stop-floor/cap conflict: no preflight policy, precedence, or visible
  rejection rule is chosen;
- V8.11 momentum versus expansion: deleting the blanket gate does not specify
  the new eligibility/confidence rule;
- V8.11 restart reconstruction, daily-limit anchor/reset semantics, safe
  full-long magic/account/server persistence keys, and oldest/first-CHoCH
  visual-mark behavior;
- netting versus hedging support or explicit account-mode rejection;
- V6.37 daily-limit symbol/magic scope;
- completed-candle enforcement for every pattern/signal path;
- market-signal/deal restart reconciliation; and
- V8.11 range visual/trading semantics.

Only counting paragraphs already titled "Contradiction resolved" makes the
Acceptance criterion tautological: an omitted contradiction escapes the set
being checked.

### 4.3 The `CTrade` rule is not blanket

**Specification:** 157-162.

It covers close, modify, and pending-delete calls, but omits market and pending
order submission even though the Baseline section cites unchecked submissions
across both EAs. Require broker retcode/result verification and resulting
deal/order/position reconciliation for **every** trading operation before
internal state is committed. A Boolean alone is insufficient.

### 4.4 The self-confirmed bypass decision is not implementable

**Specification:** 116-127.

The document keeps a general flag but supplies no list of eligible setups, no
definition of which location/SR checks it bypasses, no evidence-independence
test, and no behavior when the flag conflicts with regime or premium/discount
policy. Calling the concept "reasonable" is not the requested decision plus
testable justification. Define its exact scope per strategy or retire it until
the per-strategy evidence exists.

### 4.5 The current-run-only level invalidation choice lacks its stated reason

**Specification:** routing row 110.

The row chooses current-run-only invalidation over permanent retirement, but
does not explain why that lifecycle is preferable or define when a recovered
historical level becomes eligible again. It says "this is the decision - see
below," but no later rule supplies the rationale or state transition.

### 4.6 Acceptance criteria do not cover the claimed deliverable

**Specification:** Test plan 331-339, Acceptance 341-350, Test results 378-380.

The criteria omit checkable requirements for Phase 2 candlestick/chart-pattern
definitions, mode formulas, regime formulas, routing matrix, exit priorities,
news policy, persistence, and architecture boundaries. Test-plan item 2 says
each resolution cites a specific audit finding and source location, but most
callouts do not provide those locations. The Test results then says N/A even
though the document itself defines documentation verification. Record those
checks as run/not run with results; do not label all testing inapplicable.

### 4.7 TASK-001 dependency status is contradictory

**Specification:** 18-20, 283, 307-320.

Lines 18-20 call TASK-001 functionally complete, while 307-310 correctly say
the branch remains changes requested. Inherited
`TASK-001_BASELINE_AUDIT.md:615-630` records pass 14 as applied in the current
symbolic correction commit and pending independent review; its Final Decision
delegates status to Acceptance rather than itself saying "changes requested."

Line 283 says Phase 3 follows TASK-002 approval, while 316-320 also require
TASK-001 merge and citation recheck first. State one durable prerequisite:
TASK-001 approval/merge and rebase/citation verification, then TASK-002
approval, before Phase 3.

### 4.8 Commit and reviewer fields are stale

**Specification:** 382-389.

The commit is no longer pending; it is `cc58fa8`. The review has now been
requested and this file records its result. Update both fields using durable
wording rather than leaving self-expiring present tense.

## 5. Baseline claims independently confirmed

The following major claims were checked directly and are materially correct,
subject to the qualifications above:

- V6.37's base and regime learning branches have the same sign defect.
- V6.37 learning can cross magic numbers when instances share the configured
  common journal file; the loader filters symbol, not magic.
- V6.37 pending-fill handling keys by direction without order-ticket
  provenance.
- Both EAs mix or retain requested-price risk state instead of fully basing
  management on actual fills.
- The two named V6.37 inside-false-break helpers use `rates[0]` in live signal
  evidence.
- Both sources contain material unchecked trade-result paths.
- V8.11's minimum-lot fallback can reach 2.5x its modeled budget in the
  `E>=B` shipped-default case and more in the positive-budget underwater case.
- V8.11 has the daily anchor mismatch, magic truncation, old-first mark
  retention, and first-mark-always-CHoCH artifact described by the audit.
- V6.37's FVG route has three independently toggleable structure/confirmation
  requirements.
- V6.37's actual persisted/managed target stages are TP1 -> TP3 -> runner;
  TP2 is an intermediate target-search seed.
- V6.37's NFP date check is first-Friday arithmetic with manual server time;
  neither EA has a real economic-calendar feed.
- The `BestStrategySetup` field is populated from an aggregate memory summary,
  not the actual trade setup.

## Required correction outcome

Revise the document into an actual Phase 2 specification: complete every
section-23 deliverable, define the risk accounting and news policies, provide
objective mode/regime/routing behavior, enumerate and resolve all inherited
contradictions, correct the baseline statements, and replace the acceptance
criteria with checks that can fail when content is missing. Then submit the
revised specification for another independent review.

Until that happens, the disposition remains **CHANGES REQUESTED**, and Phase 3
should not begin.
