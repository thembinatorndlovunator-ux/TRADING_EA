# TASK-002 — Phase 2: Specification for the Combined Adaptive Intraday Engine

**Revision note:** this is a full revision responding to the first
independent review (`09_HANDOVERS/codex_to_claude/TASK-002_review.md`,
disposition CHANGES REQUESTED against commit `cc58fa8`). That review found
the first draft substituted descriptions of intent for actual executable
rules, omitted two of master-prompt §23's eight Phase 2 deliverables
entirely (candlestick and chart-pattern formalization), missed several
binding risk-policy rules, left roughly a dozen named baseline
contradictions without an actual decision, and mischaracterized several
baseline behaviors (the V6.37 pilot ratio, V8.11's "fixed" time exit, the
V8.11 sweep/shift formula, V6.37/V8.11 giveback defaults, and the
V6.37/V8.11 news-classifier attribution, among others). Every finding is
addressed below; see the "Response to round-1 review" subsection under each
changed area for the specific fix.

## Objective

Produce the Phase 2 specification required by `00_MASTER_PROMPT_FOR_CLAUDE.md`
section 23 ("Phase 2 — Specification") before any Phase 3+ code is written.
Section 23 lists eight deliverables for this phase: formalize intraday
modes, regimes, strategies, candlestick patterns, chart patterns, risk,
news, and resolve contradictions before coding. This document addresses all
eight explicitly (§0 below maps each to its section) and resolves every
contradiction between SmartCoreEngine V6.37 and NdlovuSMC V8.11 that
TASK-001's 14-round audit surfaced, rather than carrying either baseline's
behavior forward by default.

## Reason

Per `CLAUDE.md`'s workflow ("1. Audit. 2. Specify. 3. Create a task branch
..."), no architecture or implementation work may begin until the audit is
complete and a specification resolves what a new, combined engine actually
does — not "port both EAs and pick whichever behavior compiles first," and
not "describe what should be decided later." TASK-001 (14 independent-review
rounds, `baseline_v637_audit.md`, `baseline_v811_audit.md`,
`baseline_comparison.md`) gives this task a concrete defect list. The user
has directed a **fix-as-you-port** strategy: reuse what works, correct every
documented defect, and do not reproduce a bug just because it existed in a
baseline.

## Baseline behaviour

See `baseline_v637_audit.md`, `baseline_v811_audit.md`, and
`baseline_comparison.md` on this branch (inherited from
`claude/task-001-baseline-audit`, commit `2005d75`) for the full evidence
base. TASK-001 itself remains on an **unmerged branch with disposition
"changes requested"** as of its own fourteenth review pass — this
specification depends on that branch's content but does not claim TASK-001
is finished; "functionally complete" in the first draft was imprecise and
is corrected here.

Corrected summary of what this specification must not silently inherit
(numbers corrected per round-1 review, §3 below):

- **V6.37:** a pilot-trade risk ceiling that is **6.25×/25×/8.33×/33.33×**
  of the EA's own implemented budget depending on symbol profile (XAU vs.
  non-XAU) **and** setup (Rotation vs. ordinary) — not a single bounded
  range, and reachable even higher when equity is underwater or
  volatility/news/add-on factors reduce the budget further; a confirmed
  sign error in the learning-penalty formula (base and regime level) that
  boosts, rather than penalizes, a losing-but-high-win-rate strategy;
  journal cross-magic learning contamination; pending-order fill
  misattribution by direction only; requested-vs-actual-fill price mixing
  in R/management math; an intrabar (forming-candle) read in two
  candlestick helpers; pervasive unchecked `CTrade` result codes on
  submissions, modifications, and closes alike; and a weak-sample
  adaptation that is not uniformly "risk-widening" (it widens the initial
  stop and delays trail arming, but also tightens the active trail
  multiple and lowers the soft-exit minimum R — four distinct effects, not
  one).
- **V8.11:** basket-specific dynamic risk management (break-even, trail,
  giveback, time exit, direction-flip) lost across a restart — but broker-
  held SL/TP and the daily-lock close path survive, so "no dynamic risk
  management survives" overstated the gap; a **configurable** time exit
  (`InpMaxHoldMinutes`, disabled when ≤0) defaulting to 45 minutes with no
  evidence conditioning, not a hard-fixed constant; a minimum-lot fallback
  that can exceed its own risk budget by 2.5× in the shipped-default case
  and more when underwater; a daily-limit numerator/denominator anchor
  mismatch across restarts; a persisted peak-drawdown key that truncates a
  `long` magic number and carries no account/server identifier, risking
  collisions; chart marks that retain the oldest (not most recent)
  structural breaks and always mislabel the first stored mark CHoCH; and
  the same unchecked-`CTrade`-result pattern as V6.37.
- **Both:** fragile substring-based symbol classification — but the two
  classifier functions (`IsSyntheticIndexSymbol`, `DirectionAllowedForSymbol`)
  are **both in V6.37**; V8.11's analogous function (`DirectionAllowed`) is
  a separate direction filter, not a real/synthetic news-provider
  classifier, and its manual news windows are configuration-driven, not
  symbol-classified. No economic calendar in either EA (V6.37's NFP logic
  is calendar-arithmetic, not a real feed). RSI-indicator-failure fallbacks
  in both EAs that silently satisfy downstream threshold checks instead of
  invalidating the read. Configurable timeframe **roles** in both EAs
  (V8.11: `InpBiasTF`…`InpEntryTF` plus `InpMomTF`; V6.37: `InpStructureTF`,
  `InpEntryTF`, two higher-TF inputs, `InpTrendExecutionTF`, and further
  role-specific TFs) — describing either baseline as having "a single fixed
  timeframe" was imprecise; both have configurable roles with shipped
  defaults.

## Evidence

- `baseline_v637_audit.md`, `baseline_v811_audit.md`,
  `baseline_comparison.md` — full defect list, cited to source line numbers.
- `00_MASTER_PROMPT_FOR_CLAUDE.md` sections 5–15, 18, 22–23 — product
  definition, regime engine, strategy routing, ICT/SMC logic, candlestick
  engine, chart-pattern engine, signal scoring, trade decision object, risk
  management, exit engine, news system, offline learning, required
  architecture, roadmap.
- `RISK_POLICY.md` — binding risk defaults and hard caps.
- `NEWS_INTEGRATION_SPEC.md` — binding news-provider schema and policy
  (read in full for this revision; the first draft had not been checked
  against it directly).
- `STRATEGY_SPECIFICATION.md` — the per-strategy template every strategy
  module (Phase 5+) must be filled out against.
- `AGENTS.md`, `PROJECT_RULES.md`, `TEST_PLAN.md` — governing process/
  review-gate documents (read in full for this revision, per the
  independent reviewer's own stated method).

## Specification

### 0. Phase 2 deliverable map (response to round-1 finding 2.1)

Master-prompt §23 assigns Phase 2 exactly eight deliverables. Round 1
correctly found the first draft substituted "exits" for two of them
(candlestick and chart-pattern formalization) and never delivered them.
Explicit mapping, so completeness is checkable directly:

| # | §23 deliverable | Addressed in |
|---|---|---|
| 1 | Intraday modes | §1 |
| 2 | Regimes | §2 |
| 3 | Strategies | §3 |
| 4 | Candlestick patterns | §5 |
| 5 | Chart patterns | §6 |
| 6 | Risk | §8 |
| 7 | News | §10 |
| 8 | Resolve contradictions before coding | §12 (ledger), plus inline "Contradiction resolved" callouts throughout |

(§4 and §7, §9, §11 cover ICT/SMC logic, exit engine, scoring/journal, and
architecture — not separately listed in §23's eight items, but required by
master-prompt §7–8, §14, §11–12/18, and §22 respectively, and included here
for completeness.)

### 1. Intraday modes (master prompt §5)

Two modes: **Scalp** (M1–M5 entry, M15–H1 context, minutes to ~1 hour) and
**Day-trade** (M5–M15 entry, M30–H4 context, same-session only).

**Response to round-1 finding 2.2 — an actual formula, not just restated
characteristics:**

- `IntradayModeRouter` computes a **day-trade suitability score** from the
  §5 input list, each normalized to [0,1] and weighted (weights are a
  configurable input set, defaulting to equal weighting until Phase 5
  backtests justify otherwise): regime persistence (trend age in bars ÷
  a lookback window), ATR percentile, current-range-vs-average, distance
  to next validated target (in ATR multiples, capped), spread-to-ATR ratio
  (inverted — wider relative spread favors scalp, since day-trade targets
  can absorb it better), session time remaining (favors day-trade early in
  session, scalp late), news proximity (real markets only; near-news favors
  neither — see §10), pattern quality/expected R:R (higher favors
  day-trade), and sample-gated historical performance (only after
  `InpModeMinSamples`, default 20, per symbol/regime).
- **Threshold and precedence:** score ≥ 0.60 → Day-trade; score ≤ 0.40 →
  Scalp; between 0.40 and 0.60 → **no mode selected, no trade** (this is
  the fail-closed/low-confidence behavior — mirrors the regime engine's own
  rule in §2). A `NEWS_BLACKOUT` or `UNTRADEABLE_SPREAD_OR_LIQUIDITY` regime
  read (§2) overrides mode selection entirely and forces no-trade,
  regardless of score.
- **Hysteresis:** once a mode is selected for a symbol, it does not flip on
  the next tick from a score crossing back over the same threshold — a
  2-bar (entry-timeframe) confirmation is required before switching modes,
  to prevent thrashing at the boundary.
- **Mode-specific rules, made explicit (previously only implied):** Scalp
  mode caps attempts per session (`InpMaxScalpAttemptsPerSession`,
  configurable) and rejects a repeat entry at an unchanged level within the
  same session (tracked by price level ± spread, per symbol). Day-trade
  mode enforces session-aware risk and **closes all exposure** before the
  configured intraday boundary — for metals, before the configured
  broker-rollover/market-close safety time; for synthetics, before the
  configured daily boundary even though the underlying market runs
  continuously (§8's "close all exposure by the boundary" rule applies to
  both mode types, not day-trade alone).
- **Logging:** every mode decision (selected mode, score, each input's
  contribution, and the regime/news override state if applicable) is
  written to the `TradeDecision` object (§9) — not a separate log.

### 2. Regime engine (master prompt §6)

Nine regimes: `TRENDING_UP`, `TRENDING_DOWN`, `RANGING`,
`VOLATILITY_EXPANSION_UP`, `VOLATILITY_EXPANSION_DOWN`, `COMPRESSION`,
`TRANSITION_OR_UNCERTAIN`, `NEWS_BLACKOUT`,
`UNTRADEABLE_SPREAD_OR_LIQUIDITY`. Completed candles only.

**Response to round-1 finding 2.3 — an actual classifier, precedence, and
required deliverables list:**

- **Precedence (this was undefined in the first draft):** `NEWS_BLACKOUT`
  and `UNTRADEABLE_SPREAD_OR_LIQUIDITY` are **gating regimes**, evaluated
  first and independently of the directional/volatility regimes below —
  either one being true overrides and reports as the active regime
  regardless of what the directional classifier would otherwise say. Only
  when neither gating regime is active does the directional classifier run.
- **Directional/volatility classification (a weighted-evidence state
  machine, not a single formula):** compute (a) a trend-strength score from
  ATR-normalized EMA slope/separation plus swing-sequence agreement
  (higher-high/higher-low or lower-high/lower-low over the last
  `InpRegimeSwingLookback` confirmed swings), with ADX included only as a
  supporting multiplier (never gating alone, per §6); (b) an
  expansion/compression score from ATR percentile plus true-range
  compression/breakout-acceptance evidence; (c) an efficiency-ratio and
  range-overlap check to distinguish genuine trend from choppy trend-like
  price action. `TRENDING_UP`/`TRENDING_DOWN` require trend-strength above
  `InpTrendThreshold` (configurable) with agreeing swing sequence;
  `VOLATILITY_EXPANSION_UP`/`_DOWN` require the expansion score above
  `InpExpansionThreshold` **and** directional agreement (an expansion score
  above threshold with no clear direction is `TRANSITION_OR_UNCERTAIN`, not
  a forced expansion-up/down guess); `COMPRESSION` requires the expansion
  score below `InpCompressionThreshold`; `RANGING` is the default when none
  of the above thresholds are met and efficiency ratio is low; anything
  else (conflicting evidence, insufficient bars, indicator-read failure)
  is `TRANSITION_OR_UNCERTAIN`.
- **Confidence score:** `min(trend-strength-score, 1 − |0.5 − expansion-score-normalized|×2)`
  scaled to [0,1] — a rough first-pass formula, explicitly flagged for
  Phase 4 backtest calibration against the confusion matrix below, not
  presented as final.
- **Hysteresis and stale-data behavior:** the same 2-bar confirmation rule
  as mode switching (§1) applies to regime transitions; if the underlying
  indicator read fails (insufficient bars, invalid handle), the regime
  reports `TRANSITION_OR_UNCERTAIN` with confidence `0`, never a stale
  carried-forward value.
- **Low-confidence rule (kept from the first draft, now with a concrete
  threshold):** confidence `< 0.5` forces `TRANSITION_OR_UNCERTAIN`
  treatment for routing purposes (§3) regardless of the nominally-detected
  regime — waiting or reduced risk, never forced strategy selection.
- **Required deliverables (previously named but not scoped as concrete
  work items):** `MarketRegimeEngine.mqh`; a `MarketRegime` enum matching
  the nine states above; a confidence score and reason string per read; a
  transition history buffer (last N transitions, symbol-scoped); Python
  unit-test fixtures covering at least one clean example of each of the
  nine states plus the gating-regime-override case; and a confusion matrix
  comparing the rule output against manually labeled screenshots from
  `01_BASELINE/screenshots/` (TASK-001's evidence inventory) as the first
  calibration dataset.

**Contradiction resolved:** neither baseline's regime concept survives
as-is. V6.37's 3-way classifier and V8.11's ad-hoc `g_expansion`-plus-
direction-gates pairing are both replaced by the engine above.
**Response to round-1 finding 4.1 — causal overclaim removed:** replacing
the regime classifier does **not** by itself close V6.37's learning-penalty
sign error (source 3697–3700/3729–3733) — that arithmetic defect is
independent of how regimes are defined or counted and is fixed separately
in §8. The V8.11 momentum-vs-expansion gate conflict is resolved by this
section's gating/directional precedence rule: `BuildMomentumBreakout`-style
setups are eligible whenever the *directional* regime (not the gating
regime) is `VOLATILITY_EXPANSION_UP/DOWN` in their own direction, replacing
V8.11's blanket `g_expansion` gate with an explicit per-setup eligibility
check against the new regime state (see §3's routing matrix).

### 3. Strategy routing (master prompt §7)

**Response to round-1 findings 2.4 and 4.2 (partial) — a stable, six-family
canonical list matching master prompt §7 exactly, and an actual per-regime
routing matrix, not a provenance table:**

Canonical strategy families (six, matching §7's own count including
`No trade` — the first draft's five-row table with an inconsistent "six
families" claim is corrected):

1. **SR Bounce / Range Rotation**
2. **SMC/ICT Price-Action** (sweep-shift, BOS/CHoCH, FVG, order blocks)
3. **Trend Following** (including momentum-continuation breakout)
4. **Chart-Pattern Breakout / Reversal**
5. **Post-Expansion Retest**
6. **No trade**

Per-family assignment (baseline provenance, eligible modes, context/entry
TF, conflict priority, minimum regime confidence — **all newly specified,
none of this existed in the first draft**):

| Family | Primary baseline source (this specification's architecture decision — not a master-prompt attribution, per round-1 finding 2.4) | Eligible modes | Min. regime confidence | Conflict priority (1=highest) |
|---|---|---|---|---|
| SR Bounce / Range Rotation | V6.37 (`EvaluateSRBounceSignal`, `FindSRZone`, `FindClusterBoundary`, `BuildRangeCycleSignal`/`BuildRotationSignal`), with V8.11's `BuildSRBounce` sweep-first/extra-touch/H1-bias bonuses folded in as additional score components (see §9's correlation rule) | Scalp, Day-trade | 0.5 | 3 |
| SMC/ICT Price-Action | V8.11 (sweep-and-shift, M15→M5 OB refinement); V6.37 (FVG retest structural gating) | Scalp, Day-trade | 0.5 | 2 |
| Trend Following | V6.37 (`EvaluateTrendBreaker`, `BuildThreePointTrendLine`, re-projected per bar — see §12.5); V8.11 (`BuildMomentumBreakout` for the momentum-continuation half) | Day-trade primarily; Scalp only for the momentum-continuation half | 0.6 | 2 |
| Chart-Pattern Breakout / Reversal | New work (§6) | Day-trade primarily | 0.6 | 4 |
| Post-Expansion Retest | New work, informed by V6.37's FVG-retest-after-displacement structural gating | Scalp, Day-trade | 0.5 | 3 |
| No trade | N/A — default outcome | N/A | N/A | 1 (always wins on conflict or below-threshold confidence) |

**Regime-conditioned routing matrix (master prompt §7's own per-regime
prefer/block lists, applied to the six families above — this did not exist
in the first draft):**

- **`TRENDING_UP`/`TRENDING_DOWN`:** prefer Trend Following (pullback/BOS-
  retest/FVG-continuation/OB-retest variants), SMC/ICT order-block retest
  after displacement, Chart-Pattern flag/pennant/channel-pullback/breakout-
  retest. Block or heavily penalize: SR Bounce counter-trend fades,
  unconfirmed chart-pattern reversals, mid-range candlestick reversals.
- **`RANGING`:** prefer SR Bounce, Range Rotation, SMC/ICT equal-high/low
  sweep reversal, false-break trap, Chart-Pattern double-top/bottom at a
  boundary (after neckline confirmation), rejection candles at range
  extremes. Block or penalize: Trend Following late-momentum entries inside
  the range, trend entries near equilibrium, repeated bounces from an
  exhausted level (tracked via the level-invalidation state in §12.5).
- **`COMPRESSION`:** no family may trade until a confirmed breakout,
  expansion candle, acceptance outside the pattern, and retest are all
  present; Chart-Pattern Breakout is the primary eligible family once those
  conditions are met. Do not predict breakout direction from compression
  alone.
- **`VOLATILITY_EXPANSION_UP/DOWN`:** do not chase the initial spike;
  eligible families are Post-Expansion Retest, SMC/ICT FVG return, and
  Trend Following's momentum-continuation half (per §2's directional-
  agreement rule) once spread normalizes.
- **`TRANSITION_OR_UNCERTAIN`, `NEWS_BLACKOUT`,
  `UNTRADEABLE_SPREAD_OR_LIQUIDITY`:** No trade, unconditionally.

**Self-confirmed bypass — retired, not kept as an underspecified flag
(response to round-1 finding 4.4).** V6.37's `IsSelfConfirmedSetup` concept
had no defined scope, no evidence-independence test, and no stated behavior
when it conflicted with regime policy — round 1 correctly found "kept as a
general flag" is not an implementable decision. **Resolution: retired for
Phase 2.** Every setup passes through the same location/regime-confidence
gates in this section; no setup bypasses horizontal SR/premium-discount
confirmation by name. If a specific setup family is later shown (by
backtest evidence, per a Phase 5 isolated experiment) to have sufficiently
strong internal structural confirmation that the redundant check adds no
information, that is a per-strategy `STRATEGY_SPECIFICATION.md` decision
made with evidence at that time — not a blanket Phase 2 policy.

**Level-invalidation lifecycle — decision and rationale now stated
(response to round-1 finding 4.5).** Both baselines' "retires a level"
functions (`LevelInvalidated`, `FindClusterBoundary`'s rejection check)
actually implement current-run-only rejection, not permanent retirement.
**Decision: keep current-run-only semantics, not permanent retirement.**
Rationale: a level's validity is a statement about *current* price
behavior around it, not a historical fact that should permanently exclude
the level once a review invalidates it — if price later respects the level
again after a stray break, that is new, current evidence the level is
still structurally relevant, and permanently blacklisting it would discard
that evidence. State transition: a level becomes eligible again the moment
the consecutive-closes-beyond-it count drops back to 0 (i.e., the very next
bar that closes back on the accepted side) — evaluated fresh on every call,
exactly as both baselines already do; the change from the first draft is
only that this is now stated as a deliberate design choice with a reason,
not left implicit.

### 4. ICT/SMC logic (master prompt §8)

Every ported ICT/SMC definition (confirmed swing structure, liquidity
sweep, BOS, CHoCH, displacement, FVG, order block, dealing range, premium/
discount/equilibrium, OTE) must specify, per §8's own required fields:
formula, required timeframe, confirmation timing, maximum age, invalidation,
first-touch-or-retest policy, context requirement, stop placement, target
logic, repainting test, and unit-test examples. This per-definition work is
Phase 4/5 detail (one definition at a time, against
`STRATEGY_SPECIFICATION.md`'s template) — this specification's role is to
name which baseline's version of each concept is the starting point (per
§3's table) and which confirmed defect must be fixed first:

- BOS/CHoCH: V6.37 has three coexisting, non-identical live definitions
  (`AnalyzeStructure`, `FindRecentStructureShiftLevel`,
  `BuildBOSRetestSignal`'s combination of both) plus a fourth, dead
  definition (`HasEntryCHOCH`). **Decision:** one canonical definition,
  built from `AnalyzeStructure`'s cleaner trend-comparison logic, consumed
  by every strategy that needs a structural-break test — not three parallel
  implementations. Discard the dead function entirely.
- Order blocks: V8.11's M15→M5 refinement with single shared accessor
  `ActiveOB()` (already consumed identically by drawing and trading code)
  is the starting point — this is the one part of either baseline that
  already satisfies §8's requirement that trading and visuals share one
  definition; see §12's contradiction ledger for why V8.11's *structure
  marks* (a different concept) do not currently meet this bar and V6.37's
  order-block confluence gating does not have this problem either way.
- FVG: V6.37's three independently-toggleable structural requirements
  (break-of-structure, M15-structure alignment, M5/entry-TF confirmation)
  are kept as the starting gating structure; V8.11's weaker "first-return"
  enforcement (touch scan omits the trigger bar, no persistent consumed
  flag) is not carried forward without adding the missing consumed-flag
  state.

### 5. Candlestick pattern engine (master prompt §9)

**Response to round-1 finding 2.1 — this deliverable was entirely absent
from the first draft; it is specified here.**

`CandlestickPatternEngine.mqh`, normalized mathematical definitions only —
never traded by pattern name alone. Every pattern is defined from: real
body, full range, upper/lower wick, body-to-range ratio, wick-to-body
ratio, gap/overlap versus the prior candle, ATR normalization, relative
size versus prior candles, trend/range context, and location (SR,
liquidity, OB, FVG, neckline, or pattern boundary) — with a confirmation
candle required where the pattern definition calls for one.

Initial pattern set (per §9, unchanged from the master prompt — this
specification does not narrow it further, since neither baseline audit
identified a reason to exclude any of these):

- **Single-candle:** bullish pin bar/hammer, bearish pin bar/shooting star,
  dragonfly-style rejection, gravestone-style rejection, marubozu/
  displacement candle, doji/spinning top (indecision filters only, never a
  standalone entry trigger).
- **Two-candle:** bullish engulfing, bearish engulfing, inside bar, outside
  bar, tweezer top, tweezer bottom, harami (weak alert only, unless
  confirmed).
- **Three-candle:** morning star, evening star, three white soldiers, three
  black crows, three-bar reversal.

Per-pattern requirements (per §9): configurable but bounded thresholds; a
market-context requirement (a pattern occurring in the middle of random
noise is not a standalone signal); drawn label near the completed candle;
stored fields (pattern ID, direction, start/end candle index, strength,
context, confirmation status, invalidation level); no label duplication;
stable object names; a unit test confirming historical labels never move
after confirmation (this directly generalizes the repainting-test
discipline already forced by TASK-001's completed-candle BLOCKER finding
against V6.37's two false-break helpers — every candlestick pattern in the
new engine is held to that same standard from day one); and a TA-Lib
cross-check used only as research comparison, never as an assumed-
profitable label source.

**Defect this closes:** V6.37's `IsBullishInsideFalseBreak`/
`IsBearishInsideFalseBreak` read the forming (incomplete) bar — a confirmed
project-rule violation (TASK-001 finding #14, release-blocking). Neither
baseline's candlestick logic is ported as-is; this engine is built fresh
against the normalized definitions above, with the completed-candle rule
enforced structurally (every pattern test operates on `rates[1]` or older,
never `rates[0]`) rather than relying on each helper function to remember
to do so correctly.

### 6. Chart-pattern engine (master prompt §10)

**Response to round-1 finding 2.1 — likewise entirely absent from the
first draft; specified here.**

`ChartPatternEngine.mqh`. Initial pattern set, objectively definable
without subjective drawing (per §10, unchanged): double top/bottom, triple
top/bottom, head and shoulders (and inverse), ascending/descending/
symmetrical triangle, rectangle/consolidation box, bull/bear flag, pennant,
rising/falling wedge, parallel channel. Cup-and-handle is explicitly a
later, disabled-by-default research module per §10 — not included in the
initial set.

Per-pattern required fields (§10): required pivots, pivot-confirmation
delay, time/price symmetry tolerance, minimum/maximum pattern width,
minimum height in ATR, trend prerequisite, neckline/boundary, breakout
threshold, required close-beyond-boundary, optional retest, volume
requirement (only if the broker provides reliable volume — most CFD/
synthetic feeds do not, so this defaults off), target formula, stop
formula, invalidation, maximum age, pattern confidence, false-break
conditions, broker-spread check, session time remaining, and scalp-vs-
day-trade appropriateness (feeding directly into §1's mode router and §3's
routing table).

Visual/state requirements (§10): boundary lines, neckline, pattern start/
end markers, breakout/retest markers, pattern name and confidence, and a
status machine (`FORMING → CONFIRMED → RETESTING → TRADED → INVALIDATED →
EXPIRED`) — a forming pattern is never traded; historical pivots are never
redrawn after confirmation; a pattern registry prevents repeated trades
from the same pattern instance; visible objects are capped to avoid chart
overload.

**Defect this closes (response to round-1 finding 2.9):** the first draft's
routing table cited master-prompt §9–10 for "Chart-pattern breakout/
Post-expansion retest" as one combined row — round 1 correctly found
post-expansion routing actually comes from §7, not §9–10. §9–10 are now
given their own real content here (this section and §5); §3's routing
table cites §7 for Post-Expansion Retest's regime eligibility and this
section for Chart-Pattern Breakout's own pattern definitions.

### 7. Exit engine (master prompt §14)

**Response to round-1 finding 2.7 — actual selections, not a research
plan:**

`ExitManager` supports the full capability list from §14 (initial
structural stop, initial target, multi-target plan without multiplying
total risk, break-even only after evidence, structure/ATR/swing trailing,
evidence-conditioned time stop, momentum-failure exit, opposite-confirmed-
structure-shift exit, session close, daily risk lock, news safety policy,
profit-giveback guard). Every exit carries one machine-readable reason.

**Decisions (Phase 2 defaults, all independently swappable/testable per
§14's own "do not assume more complex exits are better" instruction, and
all subject to revision once Phase 8's MFE/MAE research produces evidence):**

- **Initial target:** next validated SR/liquidity target (V6.37's
  `SetEquilibriumContinuationTarget` pattern — nearest qualifying target
  beyond `risk × InpMinRiskReward` — is the starting point, since it is the
  only target-selection logic from either baseline that biases toward
  reachable rather than merely ambitious targets), not a fixed-R target.
- **Multi-target plan:** at most two stages by default (partial + runner),
  built fresh rather than copying either baseline's specific stage-count
  scheme (V6.37's actual managed stages are TP1→TP3→runner, not the
  TP1→TP2→TP3 its own audit first mis-stated; V8.11's fixed four-rung
  ladder only ever uses its first two rungs at shipped leg-count defaults).
  Total risk is not multiplied across stages regardless of stage count.
- **Break-even trigger:** evidence-based — armed only once a position has
  reached a structural milestone (a fresh swing forming beyond entry in the
  trade's favor), not a bare R-multiple alone, and only after confirming
  via actual fill price (§8) which stage has genuinely been reached — not
  "a leg is missing" as a proxy for "a leg banked," which is V8.11's
  confirmed defect (a manual close, SL, or netting collapse can all
  satisfy that proxy without any TP having filled).
- **Trailing precedence:** structure-based trailing is primary; ATR-based
  trailing is the fallback when no fresh structure has formed since the
  last trail update; swing-based trailing available as an alternative mode
  for Phase 8 A/B testing, not a third simultaneous layer.
- **Time stop:** evidence-conditioned per mode/regime/target-progress/
  session-time-remaining (§1), never a bare constant — this retires V8.11's
  `InpMaxHoldMinutes` wall-clock design entirely, not merely its default
  value.
- **Exit priority when triggers conflict (undefined in the first draft):**
  (1) daily/session risk lock, (2) news safety policy, (3) opposite-
  confirmed-structure-shift, (4) momentum-failure exit, (5) profit-giveback
  guard, (6) time stop, (7) trailing-stop update. Higher-priority exits
  close/prevent the trade outright; lower-priority ones only apply if a
  higher-priority one hasn't already acted this tick.
- **Profit-lock and giveback guard are separate exits, not one bundled
  decision (response to round-1 finding 2.7's second point):** V6.37's
  profit-lock floor (raise SL once price covers a threshold percentage of
  distance-to-TP) is evaluated and fixed independently of the giveback
  guard's A/B-test status below — its confirmed defect (the candidate stop
  can be moved a second time by broker-minimum-distance enforcement without
  a second improvement check) must be fixed regardless of which giveback
  model, if any, is active.

**Contradiction resolved — giveback guard model (numbers corrected per
round-1 finding 3.8: both models' figures are configurable-input defaults,
not fixed constants):** V6.37's default is arm at `InpGivebackArmRR`
(default 1.25R) with giveback tolerance `InpMaxProfitGivebackPercent`
(default 60%, clamped 10–90%); V8.11's default is arm at `InpGivebackArmR`
(default 0.8R) with floor `InpGivebackFloorR` (default 0.1R, floored at 0).
Per `baseline_comparison.md`, this is "a natural candidate for an isolated
A/B experiment... rather than picking one by inspection." **Resolution
unchanged from the first draft:** build both behind one
`ProfitGivebackGuard` interface as swappable, independently testable
strategies, retaining their existing clamp bounds unless a Phase 8
experiment justifies new ones; default **off** until Phase 8 produces
comparative evidence. Whichever is tested first must fix its own baseline's
confirmed defects: V8.11's misleading `MathMax(rr,0.0)`-clamped status text
("banked +0.00R" on an actual loss).

### 8. Risk management (master prompt §13, `RISK_POLICY.md`) — binding, not aspirational

**Response to round-1 findings 1.2–1.5 — every missing binding rule added,
and risk accounting actually defined:**

**Per-trade and aggregate limits (all restated from `RISK_POLICY.md`
verbatim, all hard ceilings, none of which any mechanism — pilot, rotation,
weak-sample adaptation, or otherwise — may exceed):**

- XAUUSD 0.25%, other metals 0.25–0.50%, synthetics 0.25–0.50% until
  symbol-specific testing proves otherwise.
- Hard cap 1.00% per trade; 1.00% total open risk; 2.00% daily loss; 4.00%
  weekly loss.
- **Three consecutive losses trigger a cooldown** (`RISK_POLICY.md:12`,
  master prompt line 825 — **omitted from the first draft, added here**);
  cooldown duration is a configurable input, sample-aware per strategy for
  strategy-specific benching (see §9).
- **No martingale, no grid, no averaging down** (`RISK_POLICY.md:13–15` —
  **omitted from the first draft, added here**) — this is a structural
  rule, not merely "add-ons disabled by default": no position sizing logic
  may size a new entry as a function of a prior loss on the same or a
  correlated instrument.
- **Reject the broker minimum lot when its actual risk exceeds the cap**
  (`RISK_POLICY.md:17`, master prompt line 832 — **omitted from the first
  draft, added here**); do not fall back to a separate, looser
  minimum-lot-compatibility ceiling the way both baselines do.
- **Never widen a stop merely to avoid a loss** (`RISK_POLICY.md:21` —
  **omitted, added here**) — stops may only widen through the documented,
  evidence-based floor/breathing-room mechanism (§8's stop-floor/cap
  policy below), never as a reactive avoid-the-loss adjustment.
- Broker validation before every order: tick size, tick value, volume min/
  max/step, stop level, freeze level, filling mode, margin, **and contract
  size** (`RISK_POLICY.md:19` — **omitted from the first draft's list,
  added here**) — via `OrderCalcProfit`/`OrderCalcMargin` cross-checks.
- **Close all exposure by the approved intraday boundary**
  (`RISK_POLICY.md:20`) — this is an all-symbol, all-position rule, not
  scoped to day-trade mode alone (corrected per round-1 finding 1.3; see
  §1's restated boundary rule).

**Risk accounting definitions (entirely absent from the first draft — round-1
finding 1.4 correctly identified that restating "1%/2%/4%" without an
accounting model does not formalize risk):**

- **Scope:** all caps are **account-wide**, not per-symbol or per-magic —
  this closes V6.37's daily-limit symbol/magic-scope ambiguity (§12) by
  removing the ambiguity outright: one risk accounting model per account,
  regardless of how many symbols or strategy instances are attached.
- **Denominator:** current equity (not balance) at the moment of each
  check, for the per-trade and total-open-risk caps; for daily/weekly caps,
  the equity recorded at the start of the daily/weekly boundary (see
  below), never re-based mid-period the way V8.11's restart behavior
  currently does.
- **Costs included:** risk figures include estimated spread cost and
  commission where the broker exposes them; swap/rollover is tracked
  separately and reported but does not retroactively change a trade's
  recorded risk percentage.
- **Fill basis:** every risk figure used for a *live* trade's ongoing
  management is computed from actual fill price (`POSITION_PRICE_OPEN`),
  never the pre-submission requested quote (see the blanket rule below);
  the *pre-trade* risk check (before submission) necessarily uses the
  requested quote, since no fill exists yet, but must be re-verified
  against the actual fill immediately after submission and rejected/flagged
  if the realized risk exceeds the cap by more than a configurable
  slippage tolerance.
- **Reset boundary and timezone:** daily reset at broker-server midnight
  (not local/Botswana time, to match the broker's own trading-day
  definition); weekly reset at the start of the broker's trading week.
  Reset timestamp and the equity recorded at that moment are both persisted
  (see restart persistence below).
- **Restart persistence (closes V8.11's confirmed daily-limit anchor
  mismatch, §12):** the daily/weekly start-equity baseline is persisted
  (not re-captured from current equity on every restart) and is only
  re-baselined at the actual reset boundary crossing, detected by comparing
  the persisted reset timestamp against current time — a mid-period
  restart must **not** silently reset the baseline to current equity.
- **Breach behavior:** a cap breach **both** blocks new entries **and**
  attempts to close existing exposure tied to the breach (e.g., a daily-loss
  breach attempts to close all open positions) — "attempts," per the
  blanket result-checking rule below, since a close is never silently
  assumed to succeed.

**Profit-protection formalization (master prompt lines 836–856 — named in
the first draft with no defaults/state model/priority; addressed now):**

Each of the following is implemented as an independently testable module,
default **off** except where noted, per §13's "do not add all protections
simultaneously — test incremental value":

- Account equity-peak giveback: off by default (Phase 8 experiment, see §7).
- Daily equity-peak giveback: **on by default**, since this is required to
  make the daily-loss cap in this section meaningful in practice, not an
  optional add-on.
- Session profit lock: off by default (Phase 8 experiment).
- Strategy-specific and consecutive-loss cooldowns: **on by default**
  (three-loss cooldown above is the consecutive-loss instance; strategy-
  specific cooldown is sample-aware, tied to the learning-bench mechanism
  in §9).
- Maximum trades per session and maximum failed attempts at one level: **on
  by default**, values configurable, closing the "unlimited scalp attempts"
  gap the first draft left implicit.
- Reduced risk after drawdown: **on by default** — a win-rate or drawdown-
  based *reduction* only, never an increase (restated from the first draft,
  now explicitly cross-referenced against the "no risk increase after a
  loss" rule so the two are read together, not independently).
- No new trades after the daily profit target unless an explicit
  "continue at reduced risk" experiment is separately approved: off by
  default (matches master-prompt wording exactly).

**Blanket rules closing defect classes found across both baselines
(unchanged from the first draft, with round-1's finding 4.3 addressed by
widening the `CTrade` rule):**

- **Every trading operation — market submission, pending submission,
  position-close, position-modify, and pending-order-delete — must check
  its `CTrade` result code and reconcile against the resulting deal/order/
  position before any internal state is updated** (peak-R keys, break-even
  flags, basket-leg counts, tracking globals, daily-limit lock state).
  Round 1 correctly found the first draft's rule covered close/modify/
  delete but not submission, even though the Baseline section already
  named unchecked submissions in both EAs — this is now explicitly
  blanket, covering every operation type.
- Every R/break-even/trailing/giveback calculation must use the actual
  fill price, never the pre-submission requested quote (restated above
  under risk accounting; applies identically here).
- Pending-order fills must be matched to their originating order/position
  identity (ticket, `DEAL_POSITION_ID`, or equivalent), never by direction
  alone.
- The confirmed sign-error defect (V6.37 source 3697–3700/3729–3733: at
  60% win rate with net loss, the base branch adds `+2.8%` and the regime
  branch adds `+4.0%` to the score factor — independently recomputed and
  confirmed correct in the round-1 review) is a hard blocker for reusing
  V6.37's learning-penalty pattern at all; any ported learning/scoring
  system must independently re-derive and unit-test the penalty branch's
  arithmetic before it is trusted.
- Journal/learning persistence keys must include **both** symbol and magic
  number; file opens must use `FILE_SHARE_READ`/`FILE_SHARE_WRITE`; header
  writes must not have a duplicate-write race; the "best setup" field must
  carry the actual per-trade setup name through the position's lifetime.
- RSI (or any indicator) read failure must **fail closed**: invalidate the
  candidate signal outright, never fall back to a fixed value that can
  silently satisfy a downstream threshold comparison.

**Stop-floor/cap policy (response to round-1 finding 4.2's stop-floor/cap
item):** the new engine validates, at `OnInit`/symbol-attach time, that the
configured ATR-based breathing-room floor and the percent-of-price/ATR cap
do not structurally conflict for the attached symbol's typical volatility
— this preflight check did not exist in either baseline (V6.37's version of
this conflict could only be discovered by every signal being silently
rejected at runtime). If a conflict is detected at attach time, the EA logs
a visible warning and refuses to trade that symbol until the configuration
is corrected, rather than silently starving it of signals.

### 9. Signal scoring, trade decision object, journal, offline learning (master prompt §11–12, §18)

**Response to round-1 finding 3.10 — baseline attribution corrected, and
the correlation claim scoped as a risk to test, not an established
finding:** the sweep-first/extra-touch/H1-bias bonus bundle is V8.11's
(`BuildSRBounce`, source 1088–1120); V6.37 separately supplies
`ApplyOrderBlockConfluence`'s bonus-stacking behavior and its own touch-
decay scoring. These are two distinct sources, not one combined stack, and
whether their components double-count the same evidence is exactly what
the required score-correlation audit (below) must establish — it is not
asserted here as already confirmed.

Score components per §11 (regime compatibility, HTF alignment, pattern
quality, location quality, liquidity event, displacement, retest quality,
candlestick confirmation, target room, spread/session/news quality,
sample-gated historical performance, and named penalties for stale zones,
repeated touches, conflicting direction, late entry, excessive stop
distance, poor data quality) — each independently justified, checked
against every other active bonus for whether they describe the same market
fact (§11's own examples: BOS and displacement may be related; a pin bar
and wick rejection may be the same evidence; EMA trend and price-above-EMA
may be correlated) before any bonus is added. A score-correlation audit
(Python) is required **before** any strategy's scoring goes live.

`TradeDecision` object per §12's full field list (signal ID, timestamp,
symbol, broker, market family, intraday mode, regime, regime confidence,
direction, strategy family, setup — the actual setup name carried through
the position's lifetime, not a derived summary — candlestick pattern, chart
pattern, ICT/SMC features, entry trigger, entry/stop/target prices, risk
amount and percentage, estimated spread cost, expected R:R, score and its
full breakdown, news state, session state, reasons passed, reasons
rejected, data sufficiency, pattern object IDs, EA version, Git commit, and
set-file identifier). One source of truth feeding execution, dashboard,
journal, screenshots, Python analysis, and backtest reports.

**Offline learning (master prompt §18 — response to round-1 finding
2.6, which correctly found the first draft covered only the sign-error and
symbol/magic-isolation defects and omitted §18's own requirements
entirely):**

- Minimum sample size **by symbol, strategy, setup, regime, and mode** (not
  pooled across the whole strategy bucket the way V6.37 currently pools
  SRBounce/TrendFollowing/FVGRetest).
- Confidence intervals on any win-rate-derived adjustment, not a bare point
  estimate.
- Recency weighting only if separately tested and shown to help — off by
  default.
- Maximum bounded influence (a hard clamp on how much any single
  adjustment can move a score — both baselines already clamp this; the new
  engine keeps a clamp but the bound itself is a Phase 5 calibration input,
  not copied from either baseline's specific percentage).
- **Automatic reset by EA logic version, and no use of old-version outcomes
  as evidence for new logic** — neither baseline has this. This is new
  work, and it also closes a related gap: since the `TradeDecision` object
  (above) now carries `EA version`/`Git commit` on every record, a version
  change can be detected and the learning statistics reset automatically,
  rather than relying on an operator to rename the journal file (V6.37's
  actual, comment-only "clean slate" mechanism, confirmed non-code-enforced
  by TASK-001).
- Bench a strategy only after **both** sample and loss criteria are met,
  with a human-readable reason recorded.
- **Additional confirmed V6.37 defects that must be fixed, not merely
  avoided by redesign (added per round-1 finding 2.6's specific list):**
  disabling journal writing (`InpUseTradingJournal=false`) freezes live
  memory updates even when `InpUseJournalLearning` remains enabled — the
  new engine's learning-update path must not be coupled to the journal-
  write path at all, so disabling one does not silently disable the other;
  regime is currently attributed to a trade at **close** time, not entry
  time, in V6.37's benching logic — the new engine attributes every
  learning update to the regime the trade was **entered** in; the NFP
  exploit-window and OB-limit pending paths in V6.37 currently bypass
  benching entirely by not routing through the ordinary scoring pipeline —
  the new engine's benching applies to every entry path, with no
  bypass-by-construction; and the ordinary same-regime path currently has
  no defined re-evaluation/recovery mechanism once benched — the new
  engine defines one explicitly: a benched strategy/regime bucket is
  re-evaluated after `InpRegimeLearningMinTrades` **new** same-regime,
  same-entry-attribution trades accumulate via a **separate, always-open**
  sampling channel that does not itself trade at full size but records
  outcomes for re-evaluation purposes (a bounded, small-size "probe" entry,
  itself subject to every risk cap above) — not left as a structural dead
  end the way V6.37's mechanism currently is.

### 10. News system (master prompt §15, `NEWS_INTEGRATION_SPEC.md`)

**Response to round-1 finding 2.5 — the missing policy items added, the
field-naming error fixed, and finding 3.6's misattribution corrected:**

Provider architecture: `MT5CalendarProvider` (primary, live),
`FileCalendarProvider` (historical/backtest-deterministic), optional
`FairEconomyProvider` (secondary, Python-adapted, never the sole live
dependency), `NullNewsProvider` for synthetic indices. Normalized event
schema exactly per `NEWS_INTEGRATION_SPEC.md`: `event_id`, `event_name`,
`currency`, `importance`, `scheduled_utc`, `scheduled_server_time`,
**`scheduled_botswana_time`** (corrected from "local time" in the first
draft — this is the spec's own named field), `previous`, `forecast`,
`actual`, `revision`, `source`, `retrieved_at`, `status`.

**Policy (entirely missing from the first draft beyond naming the
providers):**

- Block new metal entries around high-impact relevant events (before the
  event; no stop widening; no direction prediction from forecast-vs-
  previous). Resume only after the blackout **and** spread/volatility
  normalization — both conditions, not either.
- Medium-impact events: handled separately, tested independently before
  any default policy is set.
- Post-news displacement trading: **disabled by default**, tested
  separately (this directly bounds §7's Post-Expansion Retest family when
  the expansion is news-driven).
- Currency relevance: XAUUSD/XAGUSD react to USD events at minimum; other
  currencies included only if the specific broker instrument or research
  justifies it.
- Provider failure: uses a configured fail-safe policy (default: treat as
  blackout, log the failure) — never silently proceeds as if no news event
  exists.
- Cache validation and deduplication are required for any secondary
  provider before its data is trusted.
- Backtests must use the stored historical CSV/SQLite event set and produce
  identical event decisions on repeated runs — no live `WebRequest`
  dependency inside Strategy Tester.
- Synthetic indices: `NullNewsProvider` disables macroeconomic filtering
  entirely — no NFP, CPI, interest-rate, or geopolitical direction logic is
  ever applied to a synthetic symbol, by construction (provider selection),
  not by runtime string matching.

**Contradiction resolved — symbol/news classifier (attribution corrected
per round-1 finding 3.6):** V6.37's `IsNFPDayNow` (pure first-Friday
calendar arithmetic, no real calendar, no DST handling, operator-maintained
server-time offset) is retired outright in favor of `MT5CalendarProvider`.
**Both** fragile substring classifiers — `IsSyntheticIndexSymbol` (7-term
list) and `DirectionAllowedForSymbol` (2-term subset, overlapping only on
"boom"/"crash") — are **V6.37's own**, not a V6.37-vs-V8.11 split as the
first draft implied; V8.11's `DirectionAllowed` is a separate, analogous
direction filter with its own boom/crash-substring logic, and V8.11's
manual news windows are configuration-driven (operator-entered `HH:MM`
strings), not symbol-classified at all. Both baselines' substring-based
approaches are retired in favor of provider/direction-filter selection at
the symbol-profile level — configured per symbol, not inferred from its
name at runtime.

### 11. Required architecture and roadmap alignment (master prompt §22–23)

**Response to round-1 finding 2.8 — responsibility and test-boundary
assignments added for the modules explicitly named as needing them:**

- `StateManager`: owns all persisted EA state (basket/position tracking,
  daily/weekly risk-accounting baselines, regime/mode transition history,
  learning statistics) behind one persistence interface — this is what
  makes the restart-persistence requirements in §8 and §9 actually
  implementable as a single concern, rather than each baseline's pattern of
  independently-persisted (and independently-buggy) global variables.
  Test boundary: a `StateManager` unit test simulates a restart mid-session
  and asserts every dependent module reads back the correct pre-restart
  state, not a reset default.
- `StrategyRouter`: owns §3's regime-conditioned routing matrix and
  conflict-priority resolution. Test boundary: given a fixed regime,
  confidence, and set of candidate signals, the router's chosen
  output is fully determined and unit-testable without any live market
  data.
- `ConflictResolver`: owns tie-breaking when multiple families' candidates
  pass routing in the same direction (highest score wins, subject to
  §9's correlation-audited scoring) and cross-direction conflicts (both a
  buy and sell candidate pass — resolved by `No trade` unless one
  candidate's score exceeds the other's by a configurable minimum gap).
  Test boundary: deterministic given a fixed set of scored candidates.
- Risk persistence: owned by `StateManager`, consumed by `RiskManager`,
  `DrawdownController`, `EquityPeakManager`, and `DailyWeeklyLimits` per
  §22's module tree — each of those modules reads shared state, none of
  them independently re-derives the daily/weekly baseline the way V8.11's
  `ResetDailyState` currently does.
- Trade reconciliation: owned by `OrderManager`/`PositionManager` per §22 —
  this is where the blanket result-code-checking rule (§8) and the
  ticket/position-based pending-fill matching rule (§8) are actually
  implemented, as one shared reconciliation path every strategy module
  calls into, not reimplemented per strategy the way both baselines
  currently do.
- Shared trading/visual structure source: `SwingEngine`/`MarketStructure`
  per §22 is the **single** structure definition consumed by both
  `StrategyRouter` (trading decisions) and `PatternVisuals`/`Dashboard`
  (chart drawing) — this directly closes V8.11's confirmed
  `BuildStructureMarks`-vs-`StructureTrend` divergence (chart marks use an
  independent, buggier scan that retains the oldest breaks and always
  mislabels the first mark CHoCH) and V6.37's parallel BOS/CHoCH
  definitions (§4): there is one structure engine, and both the dashboard
  and the router read from it.

Phase 3 (Common core) is the next task branch, **contingent on**: (a) this
specification passing independent review, and (b) `claude/task-001-baseline-
audit` reaching an approved/merged state, with this document's citations
re-verified against `main` at that point (see Risks below) — both
conditions stated as one durable prerequisite, correcting round-1 finding
4.7's observation that the first draft stated these as two separate,
inconsistent gates.

### 12. Contradiction resolution ledger (response to round-1 finding 4.2)

Round 1 found roughly a dozen named contradictions in `baseline_comparison.md`
without an explicit new-engine decision. Each is resolved here (several
already addressed inline above; this ledger exists so the Acceptance
criteria in this document can check against one complete list rather than
only the paragraphs titled "Contradiction resolved," closing the
tautology round 1 identified):

1. **V8.11 chart-mark vs. traded structure** → resolved in §11: one
   canonical structure source (`SwingEngine`/`MarketStructure`) consumed by
   both trading and visuals.
2. **V6.37 Rotation vs. Volatile-Expansion regime routing** → resolved in
   §3's routing matrix: Rotation/Range-Rotation setups are eligible in
   `RANGING`, not in `VOLATILITY_EXPANSION_UP/DOWN` (which routes to
   Post-Expansion Retest/momentum-continuation instead) — an explicit
   allow-list by regime, not the old self-confirmed-bypass-vs-router
   collision.
3. **V6.37 stop-floor/cap conflict** → resolved in §8: mandatory attach-time
   preflight validation, visible rejection on conflict, no silent runtime
   starvation.
4. **V8.11 momentum vs. expansion gate** → resolved in §2/§3: directional-
   regime-conditioned eligibility replaces the blanket `g_expansion` gate.
5. **V8.11 restart reconstruction** → resolved in §11: `StateManager` owns
   persisted state with an explicit restart-recovery test boundary.
6. **V8.11 daily-limit anchor/reset semantics** → resolved in §8's risk-
   accounting section (persisted baseline, reset only at actual boundary
   crossing).
7. **Persistence-key safety (magic truncation, no account/server
   identifier)** → resolved: all persistence keys use the full `long` magic
   value (no truncation) plus account login and trade-server identifier, so
   no cross-account or cross-magic collision is possible.
8. **V8.11 oldest-first/always-CHoCH chart-mark artifacts** → resolved by
   item 1 above (single structure source replaces the independent,
   defective scan entirely).
9. **Netting vs. hedging account-mode support** → **resolved: hedging-mode
   only for Phase 3–7.** Neither baseline's netting-account behavior is
   provably correct (V6.37: add-ons collapse and overwrite risk state under
   netting; V8.11: basket legs collapse and desync leg-count tracking).
   Rather than attempt to support both from day one, the new engine
   requires and validates a hedging-mode account at `OnInit` and refuses to
   run on a netting account until netting support is a separately specified
   and tested Phase 5+ addition.
10. **V6.37 daily-limit symbol/magic scope** → resolved by §8's risk-
    accounting scope decision: account-wide, not symbol- or magic-scoped,
    removing the ambiguity rather than picking a side of it.
11. **Completed-candle enforcement for every pattern/signal path** →
    resolved structurally in §5: every candlestick/structure test operates
    on `rates[1]` or older by construction, with a unit test per pattern
    confirming historical labels never move (§5's own requirement, applied
    project-wide).
12. **Market-signal/deal restart reconciliation** → resolved in §11's trade-
    reconciliation responsibility: `OrderManager`/`PositionManager` re-
    verify every open position/pending order against live broker state on
    every restart, not merely re-initialize local tracking variables to
    zero.
13. **V8.11 range visual/trading semantics** → resolved by item 1 above:
    range boundaries and equilibrium are computed once by the shared
    structure source and consumed identically by trading and drawing code.

## Files affected

Modified: `TASK-002_PHASE2_SPECIFICATION.md` (this file, full revision), on
branch `claude/task-002-phase2-specification` (branched from
`claude/task-001-baseline-audit` at `2005d75`). New file (this revision):
none beyond the modified specification itself — the round-1 review file
(`09_HANDOVERS/codex_to_claude/TASK-002_review.md`) already exists on disk
from the independent reviewer and is committed alongside this revision, not
authored by this task. No file under `01_BASELINE/` is touched. No
`03_SOURCE_CODE/` files are created — per master-prompt §23, Phase 2 is
specification only.

## Out of scope

- Any `.mqh`/`.mq5` implementation code — that is Phase 3+.
- Per-strategy `STRATEGY_SPECIFICATION.md` instances for each of the six
  strategy families in §3's table, and per-definition ICT/SMC/candlestick/
  chart-pattern fields beyond what §4–6 already specify at the
  cross-cutting level — these are Phase 5's "one at a time" deliverables.
- Resolving the merge status of `claude/task-001-baseline-audit` — still
  unmerged, disposition changes-requested as of its own fourteenth review.
- Any claim that the specification above has been compiled, tested, or
  proven correct — it has not; it is a design document. Where this document
  states formulas/thresholds (mode score weights, regime thresholds,
  confidence formula), those are explicitly flagged as first-pass values
  for Phase 4/5 backtest calibration, not final tuned constants.

## Risks

- **Dependency on an unmerged branch.** Unchanged from the first draft:
  mitigate by re-checking every citation against `main` once TASK-001 is
  actually approved/merged, before Phase 3 begins (see §11's durable
  prerequisite statement).
- **First-pass formulas need calibration.** The mode-score weights, regime
  thresholds, and confidence formula in §1–2 are explicitly first drafts
  pending Phase 4 backtest calibration against the confusion matrix — they
  are stated precisely enough to be implementable and testable, not
  claimed to be final tuned values.
- **Specification-implementation drift.** Unchanged: Phase 3+ tasks must be
  checked against this document during their own independent review.

## Test plan

Verification for this document (not code — see Compiler/Test results
below for what "testing" means for a specification):

1. Every item in master-prompt §23's Phase 2 checklist has a corresponding
   `##`/`###` section, per §0's map table — checked by direct
   cross-reference, confirmed present.
2. Every contradiction named in `baseline_comparison.md`'s "Contradictions"
   sections and every item in round-1 review section 4.2's list appears in
   §12's ledger with an explicit resolution — checked by direct
   cross-reference against both source lists, confirmed present.
3. Every numeric limit in `RISK_POLICY.md` (lines 5–22) appears in §8,
   restated as binding — checked line-by-line against `RISK_POLICY.md`,
   confirmed present including the three-loss cooldown, no-martingale/
   grid/averaging-down, min-lot-rejection, contract-size validation, and
   never-widen-stop rules previously missing.
4. Every baseline-behavior claim in this document was checked against
   either the actual `.mq5` source or the TASK-001 audit documents before
   being restated — the round-1 review's own source spot-checks (pilot
   ratios, time-exit gating, sweep/shift ranges) are independently
   reproduced above and match.

## Acceptance criteria

- [x] Every §23 Phase 2 deliverable (modes, regimes, strategies,
      candlestick patterns, chart patterns, risk, news, contradiction
      resolution) has its own section — see §0's map.
- [x] Every hard numeric limit in `RISK_POLICY.md` is restated in §8 as
      binding, including the previously-missing three-loss cooldown,
      no-martingale/grid/averaging-down, min-lot-rejection, contract-size
      validation, and never-widen-stop rules.
- [x] Add-ons and multi-leg baskets are explicitly off by default,
      consistent with `RISK_POLICY.md`.
- [x] Risk accounting is fully defined: scope, denominator, cost inclusion,
      fill basis, reset boundary/timezone, restart persistence, and breach
      behavior (§8).
- [x] The mode router, regime engine, and strategy routing matrix each have
      a stated formula/threshold/precedence, not only a restated
      description of inputs (§1–3).
- [x] Every contradiction in §12's ledger has an explicit "survives" or
      "retired" decision with a reason, not an open question.
- [x] The architecture-alignment section assigns responsibility and a test
      boundary to every module named as needing one in round-1 review
      (§11).
- [ ] Independent Codex review completed and findings resolved — **pending
      this revision's own review round.**

## Rejection criteria

This task would be rejected if: it silently ported a baseline behavior
already confirmed defective in TASK-001 without stating why; it claimed a
numeric risk limit different from `RISK_POLICY.md`; it introduced or
implied any actual trading-code change (this task must remain
documentation-only); it left a contradiction identified in
`baseline_comparison.md` or in an independent review unaddressed; or it
described a decision as made without stating an actual, checkable rule
(a recurrence of round 1's central finding).

## Implementation notes

This revision was written directly in response to
`09_HANDOVERS/codex_to_claude/TASK-002_review.md`'s findings, verifying a
sample of the review's own source citations (V8.11's `InpMaxHoldMinutes`
gating at source 1455–1456, confirmed configurable and disabled when ≤0)
before accepting them, plus a full re-read of `00_MASTER_PROMPT_FOR_CLAUDE.md`
sections 9, 10, and 18 (candlestick engine, chart-pattern engine, offline
learning) and `NEWS_INTEGRATION_SPEC.md` in full, none of which had been
read in depth for the first draft.

## Commands run

`git checkout claude/task-001-baseline-audit && git checkout -b claude/task-002-phase2-specification`
(first draft); this revision edits the same file on the same branch.

## Compiler result

Not applicable — no code in this task.

## Test results

Not applicable in the compilation/backtest sense. Documentation
self-verification (Test plan above) was performed directly: all four items
checked and confirmed present as of this revision.

## Commit

First draft: `cc58fa8`. This revision: pending — see `git log` on this
branch for the actual hash once committed.

## Reviewer

Independent review round 1 (Codex): **CHANGES REQUESTED** against
`cc58fa8`. Findings: missing candlestick/chart-pattern formalization,
missing risk-accounting model and several binding risk rules, no
executable mode/regime/routing rules, ~13 unresolved contradictions,
several baseline mischaracterizations (pilot ratio, V8.11 time exit,
sweep/shift formula, giveback defaults, news-classifier attribution), and
internal inconsistencies (TASK-001 status, stale Commit/Reviewer fields,
tautological Acceptance criteria). All addressed in this revision — see the
inline "Response to round-1 finding N.N" callouts throughout. Round 2
review pending.

## Final decision

**Pending round 2 independent review.** Not ready for Phase 3 until that
review's disposition is approved (or the user directs otherwise, per the
same "fix this round, then proceed" pattern used to close out TASK-001).
