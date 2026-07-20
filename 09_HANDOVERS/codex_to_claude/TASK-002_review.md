# Codex Independent Review - TASK-002 Phase 2 Specification, Round 2

**DISPOSITION: CHANGES REQUESTED**

`TASK-002_PHASE2_SPECIFICATION.md` at `7842083` is not complete,
internally consistent, or source-accurate enough to authorize Phase 3. The
revision fixes a useful subset of round 1, including the headline risk
percentages, several baseline attributions, the six-family count, and a number
of explicit architecture decisions. Material blockers remain, however:

- the candlestick and chart-pattern sections still list requirements rather
  than defining the required mathematics;
- the mode, regime, and routing rules are still non-executable, and the stated
  regime-confidence formula is mathematically self-defeating;
- the risk model omits a binding policy rule and leaves core accounting and
  breach behavior undefined or contradictory;
- the contradiction ledger is incomplete and several entries assert a
  resolution that the normative sections do not supply; and
- multiple claims about the two baseline sources remain false or incomplete,
  including the V8.11 sweep/shift formula that the document claims to have
  reproduced but never states.

**Phase 3 must not begin on this specification.** The complete remaining
finding set is below.

## Review target and evidence

- Branch: `claude/task-002-phase2-specification`.
- Reviewed commit: `7842083f0cc7a117ea66947f27ae734d46de7c14`.
- Parent: `cc58fa84090e285727634d31bcac75b2454fa488`.
- TASK-001 branch point: `2005d75c3027c2d426a5d530f0455477215c3fde`.
- Actual `cc58fa8..7842083` path set: added
  `09_HANDOVERS/codex_to_claude/TASK-002_review.md`; modified
  `TASK-002_PHASE2_SPECIFICATION.md`.
- Governing material checked: `00_MASTER_PROMPT_FOR_CLAUDE.md`, especially
  sections 5-15, 18, 22, and 23; `RISK_POLICY.md`;
  `NEWS_INTEGRATION_SPEC.md`; and the three TASK-001 audit documents.
- Both MQ5 files were checked directly rather than treating the audit documents
  as authority.
- The complete `01_BASELINE/EA_V637` tree at HEAD has Git tree object
  `fe46191174b150c4c1e0dceb1bffc6c42a076384`, exactly equal to
  `baseline-v637`; the complete `01_BASELINE/EA_V811` tree has object
  `3bc9e68939873de57c70319ff75f3b39ffd58c75`, exactly equal to
  `baseline-v811`. These comparisons include both `IDENTITY.md` files.
- This is a documentation review. Compilation and backtesting are not
  applicable.

Line references to the specification are for commit `7842083`. Source line
references are to the immutable MQ5 files at that commit.

## 1. Phase 2 formalization blockers

### 1.1 Candlestick-pattern mathematics is still absent

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:381-428`.

The response to round-1 finding 2.1 names candle measurements, copies the
master-prompt pattern list, and says thresholds will be configurable and
bounded. It does not define even one normalized measurement equation, one
pattern predicate, one default threshold or bound, or one per-pattern
confirmation, context, strength, and invalidation rule. For example, no
body/range/wick equations distinguish a pin bar from a doji, and no
multi-candle relation mathematically defines engulfing, morning star, or three
soldiers.

Master-prompt section 9 requires normalized mathematical definitions and a
mathematical rule for every pattern. A future module and unit-test list is not
that formalization. The section therefore remains a deliverable map, not the
Phase 2 specification it claims to be. Lines 965-968 make the conflict
explicit by putting per-pattern definition fields beyond the cross-cutting
list out of scope until Phase 5, even though master-prompt section 23 assigns
candlestick formalization to Phase 2.

### 1.2 Chart-pattern detection is still absent, and its state machine is wrong

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:430-460`.

The section again copies the master-prompt pattern and required-field lists,
but supplies no pivot-confirmation algorithm, pivot topology per pattern,
symmetry/touch tolerance, width/height defaults and bounds, trend prerequisite,
neckline/boundary equation, breakout/retest rule, target/stop equation,
invalidation rule, confidence equation, or mode-suitability rule for any
pattern. That fails master-prompt section 10's per-pattern formalization
requirement. Lines 965-968 likewise defer these definitions to Phase 5 in
direct conflict with the Phase 2 roadmap.

The purported status machine at lines 456-457 is also incorrectly linear:
`FORMING -> CONFIRMED -> RETESTING -> TRADED -> INVALIDATED -> EXPIRED`.
Retest is optional, and `INVALIDATED`/`EXPIRED` are alternative terminal
branches, not mandatory post-trade stages. Valid transitions and terminal
states must be defined explicitly.

### 1.3 The mode router still has no executable formula

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:149-186`.

The claimed “actual formula” never defines the component normalization
functions, direction/sign of every component, numeric defaults for the
weights, missing-data behavior, or aggregation equation. “Equal weighting”
does not make undefined normalized components computable.

Additional contradictions remain:

- Line 158 says wider spread relative to ATR favors scalp because day-trade
  targets can absorb it better. The reason supports day-trade, not scalp, and
  master-prompt section 5 specifically requires strong spread checks for
  scalping.
- Lines 162-163 gate history by symbol/regime only. Master-prompt section 5
  includes setup, and the same specification at lines 735-737 requires
  symbol/strategy/setup/regime/mode buckets.
- Lines 164-173 do not say whether an already-selected mode persists in the
  0.40-0.60 neutral band or during the first of the two bars required for a
  switch. They also make the confirmation timeframe depend on the mode whose
  selection is still being decided.

### 1.4 The regime classifier is incomplete and its confidence formula fails

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:195-235`.

Trend strength, expansion/compression, efficiency, and overlap are described
but not given formulas, windows, default thresholds, or missing-data rules.
There is no directional-regime precedence when trend and expansion/compression
conditions overlap.

More seriously, the line-223 formula is
`min(T, 1 - 2*abs(0.5-E))`. Its expansion term is zero at both `E=0` and
`E=1`; therefore the strongest possible compression and expansion evidence
has confidence zero and is forced to `TRANSITION_OR_UNCERTAIN` by lines
232-235. Taking the minimum with trend strength also makes a deliberately
non-trending `RANGING` or `COMPRESSION` state low-confidence by construction.
Confidence must be state-conditional, not the minimum of mutually opposed
evidence.

The two-bar transition rule also does not say whether immediate safety gates
and failed indicator reads bypass hysteresis, as they must to fail closed.

### 1.5 Strategy routing is not deterministic

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:277-328, 850-860`.

- Lines 277-279 claim the table assigns context and entry timeframes, but the
  table has no such columns.
- “Primarily,” “block or heavily penalize,” and “block or penalize” have no
  binary eligibility or numeric penalty semantics.
- No-trade is priority 1 and “always wins on conflict” at line 288, while the
  `ConflictResolver` can select a highest-score same-direction candidate or a
  direction whose score exceeds a configurable gap at lines 855-860. No
  ordering relates eligibility, family priority, score, and score gap, and no
  default/bounds are given for the gap.
- `StrategyRouter` owns conflict-priority resolution at lines 850-854 while
  `ConflictResolver` owns conflict resolution at lines 855-860. Ownership is
  duplicated.
- Master-prompt section 7 requires strategy-switch logging including previous
  and new regimes, risk multiplier, and expected holding mode. Those fields
  are absent from section 3 and from the `TradeDecision` list at lines 719-728.
- The compression route requires breakout, expansion, acceptance, and retest
  while the active regime remains `COMPRESSION`; the spec does not say how
  that can occur without the classifier first leaving compression.

The references to `section 12.5` at lines 285 and 304 are broken. There is no
subsection 12.5; numbered ledger item 5 concerns restart reconstruction.

### 1.6 Exit choices are not fully implementable

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:470-541`.

The exit list is improved, but selected behavior still lacks executable
thresholds and state transitions: what constitutes the “fresh swing” arming
event, how structure trailing is calculated, when ATR fallback activates,
the time-stop evidence function, and the profit-lock trigger/floor are not
specified. Calling these swappable choices does not define them for Phase 3.

The exclusivity claim at lines 486-490 is false. V6.37 also contains reachable
target logic in `ApplyHistoricalM15Target`/`FindQualifiedFractalTarget`
(source 1787-1803), nearer SR/supply-demand target selection (around
2319-2335), and opposite-boundary range/rotation targets.

## 2. Risk-policy and accounting blockers

### 2.1 The stated numeric caps pass; the add-on/basket rule does not

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:548-580, 1023-1024`.

The stated 0.25% XAUUSD reference risk, 0.25%-0.50% other-metal/synthetic
reference range, 1% per-trade and total-open hard caps, 2% daily loss, 4%
weekly loss, and three-loss cooldown count match `RISK_POLICY.md`.

However, `RISK_POLICY.md:16` and master-prompt section 13 require add-ons and
multi-leg baskets to be disabled by default until proved beneficial. Section
8 contains no normative enable/disable/default rule for either. Line 562's
phrase “not merely add-ons disabled by default” presupposes the missing rule;
it does not state it. The checked Acceptance item at lines 1023-1024 is false.

### 2.2 A hard cap is permitted to become soft after a fill

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:548-550, 599-606`.

The document calls every cap a hard ceiling that may never be exceeded, then
allows an actual fill to exceed it by a configurable slippage tolerance and
says a larger excess is merely “rejected/flagged.” An already-filled position
cannot be rejected. The specification must define deterministic immediate
mitigation/closure and reconciliation for any actual-fill risk above the cap;
any tolerance must sit inside, not above, the hard ceiling.

### 2.3 The risk-accounting model is not fully defined

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:582-622`.

The section chooses scope and denominators but omits the actual daily- and
weekly-loss numerator/equity equations. It also does not define:

- aggregation of position risk into total open risk, including positions with
  no SL, stops beyond entry, locked profit, commissions/spread, and correlated
  or multi-symbol exposure;
- whether and how pending orders reserve risk, how simultaneous triggers are
  handled, and whether pending orders are cancelled on a breach;
- cash-flow treatment for deposits, withdrawals, swaps, and corrections;
- the precise broker-week boundary and behavior when no tick occurs exactly
  at a boundary; or
- which owned versus manual/other-EA positions an account-wide close is
  authorized to close.

Lines 618-622 say exposure “tied to the breach” is closed but do not define
which exposure that is or how total-open-risk breaches are reduced. The
Acceptance claim at lines 1025-1027 is therefore false.

### 2.4 Profit-protection controls remain labels, and one default is inverted

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:624-649`.

No module has its arming threshold, floor, reset/persistence rule, cooldown
duration, maximum-count default/bounds, or drawdown-to-risk scaling formula.
The claim that daily peak giveback must be on to make the daily-loss cap
meaningful is unsupported; those are different controls.

Lines 647-649 make the “no new trades after daily profit target unless an
approved reduced-risk experiment exists” control off by default. That means
trading continues without the exception having been approved, the reverse of
master-prompt section 13's rule. The stop-trading control must be on by default;
only a separately approved reduced-risk continuation may override it.

### 2.5 The loss-conditioned sizing rule contradicts drawdown reduction

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:560-564, 643-646`.

The policy forbids increasing risk after a loss. Lines 562-564 instead forbid
*any* sizing as a function of a prior loss, which also forbids the required
loss/drawdown-driven risk reduction at lines 643-646. State the directional
constraint: a loss may reduce or hold risk, never increase it.

### 2.6 Stop floor/cap prevention is undefined and its source history is false

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:685-693`.

No floor equation, cap equation, defaults, bounds, “typical volatility”
statistic/window, or current-volatility recheck is supplied. An attach-time
sample cannot by itself prevent a conflict as ATR changes.

The explanation that V6.37 discovered the conflict only by “every signal being
silently rejected” is false. Market-entry cap rejection is explicitly
journaled/printed at V6.37 source 2718-2724; the elite-score exception and
configurable skip/clamp paths at 5834-5860 mean it is not every signal. Only
the resting-limit inline path at 8738-8740 silently returns.

### 2.7 Persistence and restart behavior remain underspecified

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:612-617, 841-849, 918-921`.

The storage medium, atomic-write/recovery protocol, schema versioning,
staleness rules, and authoritative reconciliation order are absent. Ledger
item 7 says keys contain full magic/account/server, but omits symbol and a
namespace/type discriminator; multiple symbol instances sharing an account and
magic can still collide. Conversely, account-wide risk baselines cannot be
partitioned by magic. The key schema must be defined per state scope.

## 3. Baseline-source accuracy defects

### 3.1 The promised V8.11 sweep/shift/stop formula is still wholly absent

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:12-14, 1008-1012`.

The specification never mentions `InpSweepLookback` or `InpShiftLookback` and
states no sweep range, shift range, or final-stop transformation, although the
test plan says those ranges were reproduced above.

The actual V8.11 source is:

- pool scan: `4..min(copied-2, 4+max(10,InpSweepLookback))` inclusive
  (source 1008-1012), giving a minimum 11 and shipped-default 31 bars;
- shift scan: `2..min(copied-2, 2+max(3,InpShiftLookback))` inclusive
  (source 1036-1050), giving a minimum 4 and shipped-default 7 bars; and
- final stop: add ATR/spread buffer, rebuild to the floor if too tight, reject
  if above the cap, normalize, and recompute distance (source 1292-1310).

Round-1 finding 3.4 is not resolved.

### 3.2 The self-confirmed-bypass baseline description is false

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:317-328`.

Retiring the feature is a valid new-engine decision. Its rationale is not.
V6.37 `IsSelfConfirmedSetup` explicitly lists setup names at source
7534-7540. It conditionally bypasses premium/discount and horizontal-SR gates
at 1895 and 2001-2003, while `ApplyRegimeRouting` at 7464-7528 still runs and
can explicitly veto conflicts. Round 1 found the *new draft's* generic flag
underspecified; it did not show that the baseline helper had no scope or
conflict behavior.

### 3.3 Timeframe descriptions regress after the corrected summary

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:93-98, 284, 367-376`.

The summary correctly calls timeframe roles configurable, but later uses
unqualified `M15->M5` for V8.11. Its actual path is configurable
`InpWorkingTF -> InpRefineTF` (V8.11 source 52-53, 700, 762-767); M15/M5 are
only shipped defaults.

The V6.37 structure paragraph likewise says M15/M5 while the relevant inputs
are configurable `InpStructureTF` and `InpEntryTF`; the latter ships as M3 and
is used at V6.37 source 1628 despite misleading helper comments/names.

### 3.4 The trendline correction is incomplete and cites nothing

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:285`.

Apart from the nonexistent `section 12.5`, “re-projected per bar” is not an
algorithm. V6.37 `BuildThreePointTrendLine` at 6315-6369 uses the middle swing
only for monotonic ordering and constructs the line through oldest and newest
anchors; it never checks the middle swing's distance from the projected line.
Separately, `EvaluateTrendBreaker` projects one value at `exec[1]` and
`ThreeCandleBreak` compares all confirmation closes to that same constant
(2582-2614, 6388-6403). The specification must decide how both defects are
fixed and whether the three-point function is redefined or renamed.

### 3.5 V6.37 structure implementations are miscounted

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:360-366`.

There are two live classifiers, `AnalyzeStructure` and
`FindRecentStructureShiftLevel`. `BuildBOSRetestSignal` at 7777-7788 is a
strategy/caller combining them, not a third definition. `HasEntryCHOCH` at
5013-5025 is a third definition but dead. “Multiple competing definitions” is
accurate; three live definitions is not.

### 3.6 Giveback formulas remain incomplete

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:527-539`.

V6.37's effective arm is `max(0.25, InpGivebackArmRR)`, its percentage is
clamped to 10%-90%, and its close line is floored at `0.05R` (source
7144-7147). V8.11's effective values are
`max(0.3, InpGivebackArmR)` and `max(0, InpGivebackFloorR)` (source
1448-1449). The section gives configurable shipped defaults and only some
bounds, then says vaguely to retain existing bounds. It omits both effective
arm floors and V6.37's 0.05R close floor, so an implementation cannot reproduce
either strategy as stated.

### 3.7 V8.11's ladder is not fixed and two live rungs are conditional

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:491-495`.

V8.11 has four configurable R inputs (source 75-78), with TP1 floored and later
levels made monotonic at 1363-1366. The shipped leg-count inputs request at
most two, but viable sizing can reduce this to one (1328-1347), submissions can
partially fail (1368-1380), and a netting account collapses positions. Calling
it a fixed ladder that “only ever uses” the first two rungs remains inaccurate.

### 3.8 Bounded learning is falsely attributed to both baselines

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:742-745`.

V8.11 has no outcome-learning system. Its audit says so, and its score paths
are not uniformly capped: some confluence additions cap at 100 (source 929,
943), while several builder base-plus-bonus paths do not (for example
1090-1120, 1164, 1205, 2257-2278). V6.37 clamps learning factors; “both
baselines already clamp this” is false.

### 3.9 The V6.37 news-time input is not an offset

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:821-824`.

V6.37 has no server-time offset or conversion. It has operator-entered
`InpNewsHourServer`/`InpNewsMinuteServer` (source 190-191) and overwrites the
current server date's hour/minute (7260-7265). This is a manually maintained
broker-server release time, not an “operator-maintained server-time offset.”

### 3.10 The architecture overstates each baseline's persistence pattern

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:841-846, 861-865`.

V8.11's core basket and daily state are not persisted; that absence creates
its restart defect. Only its peak-drawdown state uses terminal globals. It
also implements a daily limit/state reset, not a weekly baseline. The wording
about each baseline's independently persisted globals and V8.11 re-deriving a
daily/weekly baseline is overbroad.

## 4. Contradiction-ledger and cross-section defects

### 4.1 The ledger does not cover every named comparison contradiction

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:890-948`;
`baseline_comparison.md:149-156`.

The comparison explicitly flags V6.37 FVG semantics mixing
`InpStructureSwingDepth` with `InpFractalDepth`. No ledger entry decides which
depth/structure definition survives, and section 4 retains V6 FVG gating
without resolving it. Therefore the Test-plan claim at lines 999-1002 is
false.

### 4.2 Several ledger entries assert rather than specify a resolution

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:908-948`.

- Item 3 relies on the undefined and insufficient stop preflight described in
  finding 2.6.
- Item 5 names a restart test but does not define durable serialization and
  reconciliation semantics.
- Item 7's key scheme is unsafe/inapplicable across mixed state scopes, as
  described in finding 2.7.
- Item 9 says hedging-only through Phases 3-7 but permits netting as a Phase 5+
  addition, creating overlapping timelines.
- Item 11 says section 5 enforces completed candles project-wide. Section 5
  governs candlesticks; section 4 defers structure details, and section 6
  speaks only about confirmed pivots. The claim is not established.
- Item 12 only scans broker positions/orders after restart. That does not
  close the crash window between a successful submission/fill and persistence
  of its signal-to-order/deal identity; an atomic, idempotent reconciliation
  protocol is still absent.
- Item 13 asserts one shared range/equilibrium calculation, but section 11
  neither defines that output nor assigns its computation.

### 4.3 Learning benching contradicts itself and creates an unjustified live probe

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:754-775`.

Lines 767-768 say benching applies to every entry path with no bypass. Lines
770-775 then create an “always-open” small live-entry channel for the benched
bucket. That is a bypass and continues deploying capital after the stated
sample-and-loss stop condition. No probe size, frequency, maximum loss,
approval gate, or statistical recovery test is defined. Re-evaluation can use
shadow/paper outcomes; any live probe would require a separately bounded and
approved experiment.

### 4.4 Architecture responsibilities and test boundaries remain incomplete

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:838-880`.

Risk persistence, trade reconciliation, and shared structure at lines 861-880
have responsibility prose but no explicit test boundaries. Structural drawing
is assigned to `PatternVisuals`, while master-prompt section 22 provides the
separate `StructureVisuals` module. Strategy and conflict ownership is
duplicated as noted in finding 1.5. Thus the checked Acceptance claim at lines
1033-1035 is false.

### 4.5 Files-affected, Test, Acceptance, Commit, and Reviewer records overclaim the revision

**Location:** `TASK-002_PHASE2_SPECIFICATION.md:950-960, 983-987,
991-1037, 1076-1092`.

The Files-affected section says “New file (this revision): none,” although Git
shows `7842083` adds the round-1 review and modifies the specification.
Attribution/authorship does not remove an added path from the commit's affected
set. The exact `A`/`M` set must be stated. Lines 983-987 also call the mode and
regime formulas precise enough to implement, contradicted by findings 1.3 and
1.4.

Test-plan items 2 and 4 are false: ledger coverage is incomplete and the
sweep/shift formula is absent. Acceptance checks for add-ons, fully defined
risk accounting, executable formulas, complete contradiction decisions, and
architecture test boundaries are all contradicted by findings above.

The Commit section still calls this revision pending after it exists at
`7842083`; it must record that hash and the actual two-path commit diff. The
Reviewer section says every round-1 finding was addressed, which is false, and
round 2 is no longer pending once this review is incorporated.

## 5. Round-1 response-callout disposition

Every explicit response callout was checked, not merely located:

| Callout | Result | Basis |
|---|---|---|
| 1.1 numeric risk values | **Resolved** | The numeric percentages and three-loss count match policy. |
| 1.2 three-loss cooldown | **Resolved** | The binding trigger is now stated, although duration/reset semantics still need definition. |
| 1.3 other binding risk rules | **Partly resolved** | Most omitted rules were added; add-on/basket default-off is still absent and daily-target behavior is inverted. |
| 1.4 risk accounting | **Not resolved** | Scope/denominators are chosen, but numerators, aggregation, pending exposure, cash flows, boundaries, and breach reduction are not defined. |
| 1.5 profit protection | **Not resolved** | Controls are named but lack formulas/default bounds/state behavior. |
| 2.1 deliverables/candlestick/chart | **Not resolved** | Sections exist, but the required per-pattern mathematics does not. |
| 2.2 mode router | **Not resolved** | No computable normalizations/aggregation; contradictory spread and hysteresis rules. |
| 2.3 regime engine | **Not resolved** | Missing equations/thresholds and invalid confidence formula. |
| 4.1 learning-sign causality | **Resolved** | The document now treats the source arithmetic itself, and `+2.8%`/`+4.0%` recompute correctly for its stated 60%-win-rate/net-loss example. |
| 2.4 routing and family attribution | **Partly resolved** | Six-family count/source attribution fixed; routing remains nondeterministic. |
| 4.2 contradiction decisions | **Not resolved** | Ledger is incomplete and several entries have no implementable rule. |
| 4.4 self-confirm bypass | **Partly resolved** | Retirement is a decision; baseline rationale is false. |
| 4.5 level invalidation | **Resolved** | Current-run-only semantics are selected and justified. |
| 2.9 master-prompt mapping | **Resolved** | Post-expansion retest is now attributed to routing section 7, not pattern sections 9-10. |
| 2.7 exits | **Partly resolved** | Priorities/default choices added; key algorithms and baseline qualifications remain absent/false. |
| 3.8 giveback | **Partly resolved** | Shipped defaults are corrected; effective floors/clamps are incomplete. |
| 1.2-1.5 risk | **Partly resolved** | Numeric caps and several rules added; add-on rule, accounting, and profit-control semantics remain defective. |
| 4.3 `CTrade` scope | **Resolved** | The blanket rule now covers submissions, closes, modifies, and deletes with reconciliation. |
| 3.10 score attribution | **Resolved** | V6.37 and V8.11 bonus sources are separated and correlation is framed as a test. |
| 3.1 pilot ratios | **Resolved** | All four arithmetic ratios and their conditional nature are now represented. |
| 3.2 V8.11 time exit | **Resolved** | It is correctly described as configurable, conditional, and runtime-state dependent. |
| 3.3 timeframe roles | **Partly resolved** | Summary fixed; unqualified fixed-TF wording reappears in sections 3-4. |
| 3.4 sweep/shift/stop formula | **Not resolved** | Formula is absent despite the Test-plan claim. |
| 3.5 V8.11 ladder | **Not resolved** | “Fixed” and “only ever” remain false without configuration/fill/account-mode qualifications. |
| 3.7 weak-sample effects | **Resolved** | Lines 67-71 now distinguish all four effects and their directions. |
| 3.9 unsupported intent inference | **Resolved** | The unsupported development-intent claim was removed. |
| 2.6 offline learning | **Partly resolved** | Required topics added; false V8.11 attribution and contradictory live probe remain. |
| 2.5 / 3.6 news | **Partly resolved** | Provider/policy/classifier attribution fixed; server-time “offset” statement remains false. |
| 2.8 architecture | **Partly resolved** | Some ownership/test boundaries added; several are missing or inconsistent. |
| 4.6 Acceptance checks | **Not resolved** | Multiple checked conditions are demonstrably false. |
| 4.7 TASK-001 dependency status | **Resolved** | The dependency is consistently described as unmerged and changes-requested. |
| 4.8 Commit/reviewer history | **Not resolved** | Hash/path set and review status are stale or overclaimed. |

## 6. Independently confirmed corrections

These points do not need further correction unless surrounding prose changes:

- V6.37's four stated pilot reference-ceiling/budget ratios
  `6.25x/25x/8.33x/33.33x` are arithmetically correct for the stated default
  conditions; they are conditional ratios, not global bounds.
- The V6.37 learning-sign example is correct: a 60% win-rate bucket with net
  loss produces `+2.8%` in the base branch and `+4.0%` in the regime branch.
- V8.11's `InpMaxHoldMinutes` is configurable; the subsequent-tick close
  attempt occurs only while the EA remains running and managing the basket.
- The V8.11 minimum-lot example is at least `2.5x` the modeled budget at the
  stated shipped defaults and conditions.
- V6.37's managed target staging is TP1 -> TP3 -> runner.
- V8.11's missing-leg break-even proxy, V6.37's direction-only pending-fill
  matching, the journal/learning coupling, V8.11's oldest-four/first-CHoCH
  drawing artifacts, and both EAs' unchecked trade-operation classes are
  accurately retained as defects.
- The news-classifier attribution is now substantially correct: both named
  substring helpers are V6.37 functions, while V8.11 has a separate analogous
  `DirectionAllowed` filter.

## Required correction outcome

Replace requirement lists with complete executable formulas and bounded
defaults; repair the risk/accounting contradictions; add every omitted ledger
decision; correct the remaining baseline descriptions; reconcile routing,
architecture, tests, Acceptance, and Git-history fields; and then obtain a new
independent review. Until that happens, the only supportable disposition is
**CHANGES REQUESTED**.

No file under `01_BASELINE/` or any TASK-001 audit document was modified, and
no commit was created by Codex.
