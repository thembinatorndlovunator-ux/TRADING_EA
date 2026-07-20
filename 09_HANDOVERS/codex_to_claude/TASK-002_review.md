# Codex Independent Review - TASK-002 Phase 2 Specification, Round 3

**DISPOSITION: CHANGES REQUESTED**

`TASK-002_PHASE2_SPECIFICATION.md` at
`bf84f4d3093c86489362ccf85ceb37b634f1d9e9` is not yet a complete,
standalone, internally consistent, or fully executable Phase 2 specification.
Several round-2 corrections are genuine: the expansion and compression
confidence formulas now return `1.0` at their respective extremes; all seven
baseline corrections specifically named for source re-verification are now
accurate; the add-on/basket default-off rule is explicit; the
`StrategyRouter`/`ConflictResolver` ownership split is materially improved;
the two persistence namespaces are distinguished; item 14 is present; and
learning re-evaluation no longer opens a live-capital probe.

Those improvements do not cure the remaining blockers. The mode and regime
engines are still internally contradictory, most chart patterns are still
deferred rather than formalized, completed-candle indexing contradicts the
candlestick predicates, core risk equations are wrong, several contradiction
ledger entries point to mechanisms that are not actually defined, and this
commit deleted the substantive scoring, `TradeDecision`, offline-learning,
ICT/SMC, and news-policy text that existed in the preceding revision.

**Phase 3 may not begin on this specification.**

## Review target and evidence

- Branch: `claude/task-002-phase2-specification`.
- Reviewed commit: `bf84f4d3093c86489362ccf85ceb37b634f1d9e9`.
- Parent: `7842083f0cc7a117ea66947f27ae734d46de7c14`.
- Actual `7842083..bf84f4d` path set: modified
  `TASK-002_PHASE2_SPECIFICATION.md` and modified
  `09_HANDOVERS/codex_to_claude/TASK-002_review.md`.
- Governing requirements checked directly: `00_MASTER_PROMPT_FOR_CLAUDE.md`
  sections 5-15, 18, 22, and 23; `RISK_POLICY.md`; and
  `NEWS_INTEGRATION_SPEC.md`.
- Baseline behavior was re-derived from
  `01_BASELINE/EA_V637/Thembabot14 Max.mq5` and
  `01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5`. Audit documents were used as
  indexes, not accepted as authority.
- `HEAD:01_BASELINE/EA_V637` and `baseline-v637:01_BASELINE/EA_V637` have the
  same Git tree object, `fe46191174b150c4c1e0dceb1bffc6c42a076384`.
  `HEAD:01_BASELINE/EA_V811` and `baseline-v811:01_BASELINE/EA_V811` likewise
  share `3bc9e68939873de57c70319ff75f3b39ffd58c75`. These whole-directory checks
  include both `IDENTITY.md` files.
- This remains documentation-only review. Compilation and backtesting are not
  applicable.

Specification line references below are to `bf84f4d`.

## Direct answers to the nine requested checks

1. **Regime confidence: the two requested extreme calculations pass, but the
   complete regime model does not.** With defaults, expansion at `E=1` is
   `(1-0.75)/(1-0.75)=1`; compression at `E=0` is
   `(0.25-0)/0.25=1`. Other branches and state-selection logic remain broken
   as finding 2 details.
2. **Candlestick/chart predicates: no.** Section 5 has some real predicates,
   but not bounded or complete ones; section 6 explicitly defers most required
   pattern topologies to Phase 5.
3. **Chart state machine: partly.** Retest is now optional and terminal states
   are no longer shown after `TRADED`, but expiry transitions are still absent
   from `FORMING` and `RETESTING` despite prose claiming otherwise.
4. **Mode router: no.** Its spread mapping is still reversed, its candidate
   inputs create a routing cycle, and its missing-data and weight rules
   conflict or lack bounds.
5. **Strategy routing: no.** Ownership is improved, but timeframe selection,
   modifier composition/bounds, exact-score ties, risk multiplier, and
   compression/retest sequencing are not deterministic.
6. **Risk accounting: no.** The cash-risk equation is dimensionally wrong;
   “account-wide” conflicts with own-magic aggregation; loss/cash-flow
   equations are invalid; pending, breach, and persistence behavior remain
   incomplete.
7. **The seven named baseline corrections: yes.** Each now agrees with direct
   source; the evidence is recorded after the findings.
8. **Contradiction ledger: not substantively complete.** Item 14 is present,
   and items 7, 9, 13, and 14 make real decisions. Items 1/3/5/6/8/10/11/12
   remain unsupported by the referenced mechanisms.
9. **Learning shadow tracking: the live-capital contradiction is removed.** It
   is genuinely paper-only. The recovery rule is nevertheless not executable
   or statistically complete, and the surrounding learning contract was
   deleted.

## Numbered findings

### 1. The current specification is not standalone: substantive Phase 2 content was deleted

**Specification:** 494-505, 938-974. **Git:** `7842083..bf84f4d`.
**Master prompt:** 721-807, 895-980, 1068-1093, 1391-1400.

Current section 4 contains only “unchanged in substance” plus the new FVG-depth
choice. Current section 9 similarly says scoring, `TradeDecision`, journal,
and offline learning are unchanged, but then contains only shadow-recovery
prose. Current section 10 contains only a baseline news-time correction.

The parent revision actually contained the omitted material. The commit diff
shows that `bf84f4d` removed:

- the score-component list, score-correlation audit, and score semantics;
- the normalized `TradeDecision` field schema and its consumers;
- five-way learning buckets, confidence intervals, bounded influence,
  recency/version/reset rules, sample-plus-loss bench criteria, and journal/
  learning separation;
- the news provider architecture, normalized event schema, failure behavior,
  blackout/resumption rules, deterministic replay, and synthetic-news policy;
  and
- the prior ICT/SMC starting-point and defect decisions except FVG depth.

A canonical current specification cannot normatively incorporate deleted text
with “unchanged from round 2.” This also breaks live internal references:
section 1 lines 188 and 201-212 refer to a section-9 spread penalty, score
breakdown, and learning bucket that no longer exist; section 3 lines 461-465
logs to a `TradeDecision` structure no longer defined. News is an explicit
Phase 2 deliverable at master-prompt 1399, so a correction-only section does
not formalize it.

### 2. The regime extremes are fixed, but the complete classifier is still mathematically unsound

**Specification:** 259-373. **Master prompt:** 391-434.

The requested hand calculations are correct:

- expansion: at `E=1`, `(E-0.75)/(1-0.75)=0.25/0.25=1`; at `E=0.875`,
  confidence is `0.5`; at `E=0.80`, it is `0.2`;
- compression: at `E=0`, `(0.25-E)/0.25=1`; at `E=0.125`, confidence is
  `0.5`; at `E=0.20`, it is `0.2`; and
- trend: with threshold `0.6`, `T=1` gives `1`, `T=0.8` gives `0.5`, and
  `T=0.7` gives `0.25`.

The overall model still fails:

- Lines 274-284 define raw `T` and then `T_final = T * ADX_multiplier`, but
  state selection at 304-320 and confidence at 338-342 use `T`, never
  `T_final`. For example, raw `T=0.7`, `ADX=0` gives `T_final=0.35`; the text
  still selects trend because it compares raw `T` with `0.6`.
- Line 303 says low efficiency sets `RANGING` and then says “skip to step 4.”
  Literal step 4 can immediately overwrite it with `TRENDING`, contradicting
  lines 295-298's forced-range/transition description.
- If `E>0.75`, EMA and swing directions agree, but `T<0.6`, expansion step 2
  fails and the “no directional agreement” step 3 is false. The algorithm can
  fall through to `RANGING` even at `E=1`.
- Ranging confidence at 350-355 is not a complete equation: “clamped against
  ER” and “capped at ER's own gate value” do not specify an operator. Under the
  natural `min(raw,ER)` interpretation, every range selected by `ER<0.3` has
  confidence below `0.3` and is immediately converted to transition by the
  `<0.5` rule. Its raw curve is also perverse for “absence of trend”:
  `T=0 -> 0`, `T=0.3 -> 1`, `T=0.6 -> 0`.
- Expansion selection requires both `E` and trend/direction evidence, but
  expansion confidence ignores the trend margin. `E=1,T=0.6` therefore gets
  confidence `1` despite its trend evidence sitting exactly at the threshold.
- Configurable thresholds have no safe bounds. Trend/expansion threshold `1`
  or compression threshold `0` divides by zero.
- The engine declares completed candles at line 264 but uses `close[0]` in the
  efficiency formula at 292 without defining a completed-bar-local indexing
  convention. EMA period, slope horizon, regime timeframe, percentile tie
  convention, zero ER denominator, and the actual
  `UNTRADEABLE_SPREAD_OR_LIQUIDITY` predicate are also undefined.

The low-confidence rule creates additional effective thresholds—`T>=0.8`,
`E>=0.875`, or `E<=0.125` for confidence at least `0.5`—which must be an
explicit design decision rather than an unnoticed consequence.

### 3. The mode router remains circular and internally contradictory

**Specification:** 149-257. **Master prompt:** 331-387.

- The document defines `1` as Day-trade and `0` as Scalp, but the spread
  equation maps a tight/zero spread to `1` and a spread at least 5% of ATR to
  `0`. Wider spread still pushes mode selection toward Scalp. Lines 180-182
  compound the error by calling Day-trade the shorter expected move; master
  prompt 348-351 assigns the smaller horizon and strong spread checks to
  Scalp. A low weight does not reverse the equation, and the promised separate
  section-9 spread penalty was deleted.
- Components 4, 8, 9, and 10 require a current best candidate, direction,
  setup, score, expected R, and mode-specific history before a mode is
  selected. Section 3 uses the selected mode to decide candidate eligibility.
  No candidate-generation/mode/routing evaluation order breaks this cycle.
- Historical performance is itself bucketed by mode while a single mode is
  being selected; no rule says whether to evaluate the Scalp bucket, the
  Day-trade bucket, both, or a counterfactual pair.
- “Entry-timeframe ATR” is required before the entry timeframe is selected;
  both mode and family tables provide ranges, not a concrete timeframe.
- Lines 219-225 allow up to three unavailable components and continue scoring,
  while lines 245-247 say any indicator-read failure immediately bypasses
  hysteresis. The resulting state is not defined consistently.
- The news “proximity” input is always `1` whenever the formula runs because a
  blackout preempts the formula. It is a constant Day-trade bias, not a
  proximity measure.
- Session-time `remaining/total` is not clamped to `[0,1]`; configurable
  weights have no nonnegative bounds or all-zero-denominator behavior;
  `InpSpreadATRDivisor` has no positive lower bound. Item 5 is called fixed at
  `0.05`, then line 218 says all weights are configurable. The exact
  redistribution is `0.95/9 = 0.105555...`, not `0.1056`; the printed defaults
  sum to `1.0004`.
- Lines 228-230 say the neutral band means no mode/no trade, while 240-244 say
  a prior mode persists there. The later qualification may be intended to
  override the former, but a deterministic specification must state one rule
  in one precedence chain.

### 4. Candlestick definitions are still incomplete and contradict completed-candle enforcement

**Specification:** 507-586. **Master prompt:** 577-645.

Section 5 now has genuine measurement equations and several usable partial
predicates. It still does not meet “define each pattern mathematically” with
configurable, bounded thresholds:

- Most constants (`0.60`, `0.30`, `0.15`, `0.70`, `0.10`, `0.90`, `0.35`,
  `0.20`, `0.55`) have no input name or allowed minimum/maximum. Line 569's
  statement that a default is “its bound” is neither a range nor compatible
  with configurability.
- Lines 539-565 use `[0]` throughout, while lines 583-585 insist all predicates
  read `rates[1]` or older. In MQL series indexing `[0]` is the forming bar;
  no alternate local indexing contract is declared.
- The pin-bar trend formula uses undefined `N` at line 525. Morning/evening
  star uses nonnumeric “gapping or near-gapping.” Harami does not define the
  implied direction and uses whole-candle high/low containment rather than a
  stated body-containment choice. The three-bar reversal delegates to an
  undefined `SwingEngine` predicate and an undefined “reversal direction.”
- The master prompt requires wick-to-body, gap/overlap, and relative-size
  metrics. This section defines wick-to-range instead, no general gap/overlap
  equation, and no relative-size-versus-prior-candles equation.
- Direction/confirmation behavior for inside/outside/doji and the strength
  calculation (“body_ratio/atr_size-derived”) are undefined. “ER deep below”
  is not a context threshold, and “the pattern's own extreme” is not a
  direction-specific invalidation formula.

### 5. Most chart patterns remain unformalized, and the state graph is still incomplete

**Specification:** 588-687, 1110-1118. **Master prompt:** 649-718,
1391-1400.

Lines 590-597 and 1113-1118 explicitly defer triangles, rectangle, flags,
pennant, wedges, and channels to Phase 5. Master-prompt section 10 says “for
each pattern, define” the pivot topology, boundaries, trend prerequisite,
breakout, target, stop, invalidation, and other fields; section 23 assigns that
formalization to Phase 2. A generic framework cannot generate those omitted
topologies. This is also internally inconsistent with routing lines 409-412,
which already tries to route flag/pennant/channel candidates that section 6
cannot detect.

Even the representative definitions remain incomplete:

- `SwingEngine` has no mathematical pivot predicate; `pattern_height` and
  `H1_or_H2_avg` are undefined; no trend prerequisite is supplied; triple
  tops/bottoms do not define intervening pivots or neckline; H&S has no
  minimum head prominence or complete time topology; and “retest holds/fails”
  has no predicate.
- Under the natural `pattern_height = H-L`, the double-top pullback condition
  `L < H - 0.3*(H-L)` reduces to `L<H`, so it does not enforce a 30% pullback.
- Reused spread/session components have no pass/fail thresholds. The registry
  only says it prevents simultaneous duplicates, not repeated trades from an
  already-traded pattern. Required visual outputs—boundaries, neckline,
  start/end, breakout/retest markers, name, confidence, and status—are absent.

The state graph is improved but does not satisfy the claimed branching model.
It has `FORMING -> INVALIDATED` but no `FORMING -> EXPIRED`, and
`RETESTING -> TRADED/INVALIDATED` but no `RETESTING -> EXPIRED`. Maximum age is
defined only from confirmation. Lines 680-682 merely assert that both terminal
states are reachable from all three nonterminal states; the diagram and
transition predicates do not implement that assertion. Retest itself is now
genuinely optional, which is a valid correction.

### 6. Strategy routing is not fully deterministic

**Specification:** 382-492. **Master prompt:** 438-525.

The added columns and the ownership split at 444-459 are useful corrections.
Remaining gaps are:

- Context/entry cells are ranges with no rule selecting a specific timeframe.
  “Day-trade primary” and “Scalp for momentum half only” are not numeric
  mode-eligibility rules.
- Score multipliers and `InpConflictScoreGap` have defaults but no bounds,
  despite line 453 claiming a bound. Modifier ordering, composition, and score
  clamping are absent, especially important because section 9's score contract
  was deleted.
- Exact equal-score ties in one direction have no tiebreaker after the prior
  family-priority column was removed.
- Lines 461-465 call the eligibility *score* multiplier a logged “risk
  multiplier.” No risk multiplier is actually selected by the routing rules.
- “Unconfirmed chart-pattern reversals” are merely penalized in trending
  routing, while section 6 says a forming/unconfirmed pattern is never traded.
- The compression timing explanation is self-contradictory. It says completed
  bar N is classified before routing N, then says that close affects only the
  next bar and the breakout bar remains under the old compression regime.
  Default-required retest occurs after the breakout, by which time the regime
  has changed, so the sole compression-eligible family cannot meet its own
  breakout-plus-retest condition under the described timing. The interaction
  with two-bar regime hysteresis is not defined either.

### 7. Binding risk-policy rules disappeared from the current document

**Specification:** 767-915. **Risk policy:** 13-21. **Master prompt:**
827-854. **Git:** `7842083..bf84f4d`.

The numeric percentages/count, explicit add-on/basket default-off rule, and
directional no-risk-increase-after-loss correction are accurate. However, the
current standalone section removed and does not replace the normative rules
for:

- no martingale, grid, or averaging down;
- rejecting broker minimum volume when actual risk exceeds the cap;
- the `OrderCalcProfit` broker-aware cross-check;
- tick size/value, contract size, volume min/max/step, stop/freeze level,
  filling mode, and margin validation;
- never widening a stop merely to avoid a loss; and
- a fully defined approved intraday boundary.

Lines 254-255 merely mention a configured boundary without specifying its
input/time basis, and “all positions” there conflicts with the EA-owned-only
authority at lines 854-859. Presence in a parent commit is not presence in the
current specification.

### 8. Per-trade and aggregate risk equations are dimensionally wrong and contradict account-wide scope

**Specification:** 790-812, 925-935. **Risk policy:** 8-9, 17-19.

The line-793 formula
`abs(entry_fill-SL) * volume * tick_value` omits division by tick size. For a
price move of `1.00`, tick size `0.01`, tick value `1`, and one lot, it returns
`1` while the broker-cash loss is `100`. It also uses absolute distance, so a
long entered at `100` with a profit-locking SL at `101` is assigned positive
risk rather than zero downside. It does not select loss-side tick value,
handle deposit-currency conversion, include costs once, or perform the binding
`OrderCalcProfit` cross-check.

Neither `per_trade_risk_pct = 100*risk_cash/current_equity` nor
`total_open_risk_pct = 100*aggregate_cash/current_equity` is stated, so the
cash formula is not connected to the 1% caps. “Full notional value at 10 ATR”
for no-SL positions conflates notional with a 10-ATR loss proxy and defines no
closure/retry if a stop cannot be attached.

Scope is called account-wide at line 792, but total risk includes only this
EA's magic at 801-804. Two instances with different magic numbers can each
admit 1% while the aggregate account has 2%. This also contradicts the shared
account/server-only namespace at 930-933.

Pending reservation is present, but unsafe. The supported engine is hedging-
only, so opposite pending orders can both fill and remain open; all concurrently
live pending risks must be summed rather than assuming one of two outcomes.
No cash-risk equation is provided for a pending order, including stopless,
gap, spread, and slippage treatment.

### 9. Daily/weekly loss and cash-flow formulas do not measure period equity change

**Specification:** 813-840.

`TodayClosedPL + TodayFloatingPL + TodaySwapAndCommission` uses the entire
current floating P/L, not its change since the boundary. A position already at
`-1000` when `daily_start_equity` is recorded and still at `-1000` later is
therefore reported as a new `-1000` daily loss. Conversely, a `+1000` floating
gain present at the boundary that falls to zero can appear as no loss.
`TodayClosedPL` and `TodaySwapAndCommission` are undefined as gross/net terms,
so costs may be omitted or double-counted.

The cash-flow classifier at 820-825 infers deposits/withdrawals from
equity/balance/floating snapshots. Trade closes, commissions, swaps, credits,
and concurrent transactions also change those values; the deterministic source
is broker deal history/types with a persisted last-processed transaction.

The weekly boundary “first server-time session open following the configured
weekend” does not say which symbol's trading sessions control an account that
mixes metals and continuously traded synthetics. A correct account-wide model
needs an explicit calendar/boundary and either adjusted-equity delta or
closed-net P/L plus the persisted change in floating P/L.

### 10. Hard-cap breach and persistence mechanics remain incomplete

**Specification:** 841-859, 917-936, 981-986; ledger item 12 at 1072-1086.

The former soft slippage tolerance is gone, and post-fill excess now mandates
full closure. That is a genuine correction. “Immediately queued ... next
tick,” however, is not immediate; the actual fill is available in the trade-
transaction/reconciliation path, and no later tick is guaranteed. There is no
persisted breach lock, retry-until-confirmed rule, pending-order cancellation,
or fail-closed behavior when closure fails. “Actual fill plus confirmed
slippage” also double-describes the same price effect: actual fill already
embodies slippage.

The two key scopes at 925-933 are a real improvement. Their surrounding
protocol is unsafe:

- schema mismatch performs a full reset at 923-924/984-985, contradicting
  835-840's rule that period baselines reset only at real boundaries; a
  mid-period upgrade can erase loss history and reopen risk;
- multiple symbol instances share account-wide keys without a single-writer,
  locking, or compare-and-swap protocol, so atomic rename alone does not
  prevent lost updates or duplicate rebases; and
- daily/account peaks, cooldown streaks, failed-level counters, and learning
  buckets are not assigned unambiguously to one namespace.

The durable-intent protocol is also not crash-safe. The unique local intent ID
is not specified as broker-visible order metadata. A crash after broker
acceptance but before the ticket update leaves no unique correlation key;
symbol/direction/volume/SL/TP can match multiple orders. Restart checks only
live state, not order/deal history, so an order filled and closed before restart
can be misclassified as abandoned after 30 seconds. The protocol needs
broker-visible correlation, history lookup, and idempotent terminal handling.

### 11. Stop-floor/cap and profit-protection mechanisms remain underdefined

**Specification:** 861-908; ledger item 3 at 1032-1034.

Section 7 contains no initial ATR breathing-room-floor equation. Section 8
contains no percent-of-price/ATR cap equation, defaults, enable flags, or
floor-versus-cap inequality. A rolling ATR distribution is named, but no
percentile is selected and no computable accept/reject predicate is stated.
Attach/500-bar scheduling does not make an undefined comparison executable.

Profit controls also remain partial:

- “daily equity-peak giveback” is an absolute arm/floor rule and never records
  or calculates giveback from a peak;
- the three-loss cooldown has a duration but no streak scope, reset-on-win,
  expiry, or persistence rule;
- `current_drawdown_percent` has no defined peak, scope, or reset boundary;
- the daily profit target has no input/default/equation; and
- session-trade and failed-level counters have no session/level identity or
  reset semantics.

The corrected V6.37 history in lines 900-908 is source-accurate; the new-engine
mechanism remains incomplete.

### 12. Shadow learning is paper-only, but the recovery rule and surrounding learning contract are incomplete

**Specification:** 938-962. **Master prompt:** 1068-1093.

The narrow round-2 contradiction is resolved: lines 950-962 explicitly open
no live position and risk no live capital. Remaining defects are:

- a shadow trade cannot use the “same fill price” as an unplaced live trade;
  no deterministic entry, spread/slippage, commission, SL/TP, same-bar
  SL-versus-TP precedence, exit, expiry, or overlapping-shadow model exists;
- re-enablement uses raw win rate, not the required confidence interval and
  sample-plus-loss recovery rule;
- `InpRegimeLearningMinTrades` has no default here and “original bench
  threshold” is undefined because the bench contract was deleted;
- the prose does not explicitly preserve symbol+strategy+setup+regime+mode
  buckets; and
- no logic-version reset prevents old shadow outcomes being used after logic
  changes.

These are in addition to finding 1's deletion of the main score,
`TradeDecision`, journal, and learning specification.

### 13. The contradiction ledger contains item 14, but several entries still assert resolution

**Specification:** 976-1096.

The enumerated coverage is improved. Items 2 and 4 make clear routing
decisions; item 7 identifies two key namespaces; item 9 now unambiguously
chooses hedging-only; item 13 explicitly makes range/equilibrium a shared
output; and item 14 chooses one canonical swing depth for FVG gating.

The ledger is not substantively complete:

- **Items 1 and 8:** section 11's shared output explicitly lists pivots,
  range, and equilibrium, not canonical BOS/CHoCH break events and labels. It
  therefore does not establish that V8.11's visual and traded structural-break
  classifications have become one algorithm.
- **Item 3:** references the undefined stop-floor/cap mechanism in finding 11.
- **Item 5:** depends on unsafe schema-reset behavior and incomplete intent
  reconciliation from finding 10.
- **Item 6:** depends on the invalid period-loss/cash-flow equations in
  finding 9.
- **Item 10:** says account-wide scope, contradicted by own-magic aggregation
  in finding 8.
- **Item 11:** says completed-candle enforcement project-wide, but section 5
  uses `[0]`; it covers only three named engines, not regime, FVG, OB,
  liquidity, or all strategy signal paths. Its `EXPIRED` assertion also
  conflicts with the state graph.
- **Item 12:** the local intent record is not uniquely correlatable to broker
  history across the critical crash window.

Item 13 is now a real architecture decision, although its range-boundary
algorithm still needs definition before implementation. Item 14 resolves the
specific mixed-depth choice, but the canonical `SwingEngine` pivot/depth
formula itself is not yet specified.

### 14. The V8.11 sweep/shift/final-stop correction is still incomplete and the Test plan misstates its location

**Specification:** 126-132, 1146-1152. **V8.11 source:** 1008-1050,
1292-1310.

The Test plan now prints the pool and shift expressions, but the Evidence
section only lists source ranges, section 7 does not reference the sweep/shift
logic, and the final-stop transformation is merely called a “chain” rather
than stated. The source actually shows:

- pool indices `4..min(copied-2,4+max(10,InpSweepLookback))`, inclusive—11
  bars minimum and 31 at shipped `InpSweepLookback=30`;
- shift indices `2..min(copied-2,2+max(3,InpShiftLookback))`, inclusive—4
  bars minimum and 7 at shipped `InpShiftLookback=6`; and
- stop buffer = ATR component plus spread; rebuild to ATR floor if too close;
  reject above ATR cap; normalize; then recompute distance.

Thus the two scan expressions are partially reproduced in a self-test, but the
claimed normative source and complete formula are still absent.

### 15. Exit/trendline formulas remain directionally incomplete

**Specification:** 70-73, 392-398, 689-765. **V6.37 source:** 2582-2614,
6315-6369, 6388-6403.

The baseline summary now accurately states both trendline defects, but no
new-engine section decides whether the line uses two anchors or validates a
middle anchor, what middle-point tolerance applies, or how it is reprojected
at each confirmation bar. The Trend-Following routing row still cites the
baseline trendline without resolving that porting decision.

The new trailing equations are also written only for longs:
`swing - ATR*buffer` and `current_price - ATR*multiple`. A short requires the
appropriate swing high plus the buffer and a price-plus-ATR fallback. “Swing
in favor” does not identify which pivot type becomes the protective stop in
either direction. An engine coding these literal equations would place short
stops on the wrong side.

### 16. Self-verification and history fields overclaim the committed revision

**Specification:** 17-18, 1098-1108, 1122-1183, 1222-1249.

The Files-affected section is now correct: Git shows exactly two modified
paths. The Commit section is stale: at the reviewed commit it still calls the
revision pending instead of recording `bf84f4d`.

Test-plan items 1, 2, and 4 are false: section presence is not completed
formalization; ledger mechanisms remain defective; and the final-stop formula
is absent. The Acceptance checks for chart/candlestick mathematics, complete
risk accounting, executable mode/regime/routing, and every ledger decision are
also false. Lines 17-18's claim that every round-2 finding is fixed, and lines
1217-1220's claim that all five documentation checks passed, do not match the
current document.

## Direct baseline-source re-verification

All seven corrections specifically requested in round 3 now pass:

1. **V6.37 `IsSelfConfirmedSetup`: PASS.** The setup list is explicit at
   source 7534-7540. Premium/discount and horizontal-SR bypasses occur at 1895
   and 2001-2003. `SelectBestIndependentSignal` still calls
   `ApplyRegimeRouting` at 919-924, and that router can veto at 7464-7528.
   Specification 65-69 and 473-486 now describe this accurately.
2. **V6.37 news time: PASS.** Inputs 190-191 are broker-server HH:MM values;
   source 7260-7265 overwrites those fields on the current server date. There
   is no offset conversion. Specification 86-88 and 969-974 are accurate.
3. **V6.37 market stop-cap logging: PASS.** Market rejection is journaled and
   printed at 2718-2724; elite and skip/clamp paths are at 5834-5860; only the
   resting-limit inline check at 8738-8740 silently returns. Specification
   900-908 is accurate.
4. **V8.11 ladder: PASS.** R inputs are configurable at 75-78; shipped leg
   inputs request two at 72-74; sizing can reduce legs at 1328-1347; rungs are
   floored/monotonic at 1363-1366; submissions may partially fail at
   1368-1380. Specification 100-106 now includes the necessary conditions.
5. **V8.11 learning/clamp attribution: PASS.** The source contains no
   outcome-learning/journal feedback. Confluence additions cap at 929/943,
   while builder bonus paths at 1090-1120, 1164, 1205, and 2257-2278 are not
   uniformly capped. Specification 107-111 no longer attributes a learning
   clamp to V8.11.
6. **V8.11 daily/weekly baseline: PASS.** `ResetDailyState` and daily checks
   are at 1529-1564; there is no weekly state/reset/limit path. Specification
   93-97 correctly says the baseline has only daily state.
7. **V6.37 structural-classifier count: PASS.** `AnalyzeStructure` and
   `FindRecentStructureShiftLevel` have live call sites;
   `BuildBOSRetestSignal` at 7760-7788 calls both rather than defining a third
   classifier; `HasEntryCHOCH` at 5013-5025 has no call site. Specification
   74-78 now states two live classifiers plus one dead definition.

## Required correction outcome

Restore all deleted normative sections into the current document; make mode,
regime, pattern, routing, exit, risk, persistence, and recovery rules
mathematically executable; repair the ledger and self-verification claims; fill
the actual commit hash; and obtain another independent review. Until those
changes are complete, the unambiguous disposition remains **CHANGES
REQUESTED**, and **Phase 3 may not begin**.

No file under `01_BASELINE/` or any TASK-001 audit document was modified, and
Codex created no commit.
