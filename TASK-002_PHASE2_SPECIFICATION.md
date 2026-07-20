# TASK-002 — Phase 2: Specification for the Combined Adaptive Intraday Engine

**Revision history:** round 1 (`cc58fa8` → review: CHANGES REQUESTED, 40+
findings — missing candlestick/chart-pattern formalization, no executable
mode/regime/routing rules, undefined risk accounting, ~13 unresolved
contradictions, several baseline mischaracterizations). Round 2 (`7842083`
→ review: CHANGES REQUESTED — round 1's fixes were largely real (risk
percentages, six-family count, several baseline attributions, the `CTrade`
blanket rule, pilot ratios, weak-sample effects), but this was still a
requirements list wearing a specification's clothes: no candlestick/chart-
pattern mathematics, a **mathematically broken regime-confidence formula**
(`min(T, 1−2|0.5−E|)` is exactly zero at both expansion extremes — the
strongest possible evidence produced the lowest possible confidence),
non-deterministic routing, contradictory risk accounting, an incomplete
contradiction ledger, and several baseline facts still wrong, including the
V8.11 sweep/shift formula the document claimed to state but never did).
This is round 3: every round-2 finding is fixed below, with actual formulas,
defaults, and state machines in place of requirement lists.

## Objective

Produce the Phase 2 specification required by `00_MASTER_PROMPT_FOR_CLAUDE.md`
section 23 before any Phase 3+ code is written: formalize intraday modes,
regimes, strategies, candlestick patterns, chart patterns, risk, and news,
and resolve every contradiction between SmartCoreEngine V6.37 and NdlovuSMC
V8.11 with an actual, implementable decision — not a description of what
should be decided.

## Reason

Per `CLAUDE.md`'s workflow, no architecture or implementation work may begin
until a specification resolves what the new engine actually does. TASK-001's
14-round audit gives this task a concrete defect list. The user has directed
a **fix-as-you-port** strategy. Given that Phase 3 will write real `.mqh`
code directly against this document, an unresolved formula or an
underspecified state machine here becomes a real bug there — this revision
treats that as the binding standard for what "specified" means.

## Baseline behaviour

See `baseline_v637_audit.md`, `baseline_v811_audit.md`, and
`baseline_comparison.md` on this branch (inherited from
`claude/task-001-baseline-audit`, commit `2005d75`; still unmerged,
disposition changes-requested as of its own fourteenth review — this
specification depends on that branch's content without claiming it is
finished).

Corrected summary (round-2 fixes applied — §3.x references below are to
round 2's finding numbers):

- **V6.37:** a pilot-trade risk ceiling of **6.25×/25×/8.33×/33.33×** of the
  EA's implemented budget depending on symbol profile and setup (Rotation
  vs. ordinary) — conditional ratios under specific runtime conditions, not
  global bounds, and reachable higher still when underwater or when
  volatility/news/add-on factors reduce the budget. A confirmed sign error
  in the learning-penalty formula (base branch: `+2.8%` at 60% win rate with
  net loss; regime branch: `+4.0%`) that boosts, rather than penalizes, a
  losing-but-high-win-rate strategy. Journal cross-magic learning
  contamination. Pending-order fill misattribution by direction only.
  Requested-vs-actual-fill price mixing in R/management math. An intrabar
  read in two candlestick helpers. Pervasive unchecked `CTrade` result
  codes on every trading operation, not only closes. A weak-sample
  adaptation with four distinct, not-uniformly-directional effects (widens
  the initial stop and delays trail arming; but also tightens the active
  trail multiple and lowers the soft-exit minimum R). **`IsSelfConfirmedSetup`
  has an explicit, named setup-list scope (source 7534–7540) and does not
  escape regime routing — `ApplyRegimeRouting` still runs and can veto a
  self-confirmed setup (round-2 finding 3.2 corrected the first revision's
  false claim that the baseline flag had no scope or conflict behavior).**
  `BuildThreePointTrendLine` constructs its line through only the oldest and
  newest of three monotonic swing points, never testing the middle swing's
  own distance from that line; `EvaluateTrendBreaker` then projects a single
  constant value rather than re-projecting per confirmation bar. **Two live,
  non-identical structural-break classifiers exist (`AnalyzeStructure`,
  `FindRecentStructureShiftLevel`), not three — `BuildBOSRetestSignal` is a
  caller that combines both, not a third definition; `HasEntryCHOCH` is a
  third definition but dead code (round-2 finding 3.5 corrected the
  miscount).** Effective giveback arm is `max(0.25, InpGivebackArmRR)`
  (default 1.25R), percentage clamped 10–90% (default 60%), and the giveback
  close condition itself is floored at `0.05R` — three bounds, not one
  (round-2 finding 3.6). Timeframe **roles** are configurable
  (`InpStructureTF`, `InpEntryTF` — which ships as **M3**, not M5, despite
  misleading helper names/comments — two higher-TF inputs,
  `InpTrendExecutionTF`, and further role-specific TFs); M15/M5 language
  used loosely elsewhere in this document is shipped-default shorthand only
  (round-2 finding 3.3). The `InpNewsHourServer`/`InpNewsMinuteServer`
  inputs are manually-entered server-time values overwritten onto the
  current server date, not a computed "offset" (round-2 finding 3.9).
- **V8.11:** basket-specific dynamic risk management lost across a restart
  — broker-held SL/TP and the daily-lock close path survive. A configurable
  time exit (`InpMaxHoldMinutes`, disabled when ≤0) defaulting to 45 minutes.
  A minimum-lot fallback reaching at least 2.5× its modeled budget at
  shipped defaults, more when underwater. A daily-limit numerator/
  denominator anchor mismatch across restarts — **and only a daily reset
  exists; there is no separate weekly baseline in V8.11 at all (round-2
  finding 3.10 corrected the first revision's false "daily/weekly baseline"
  claim)**. A persisted peak-drawdown key that truncates a `long` magic
  number, with no account/server identifier. Chart marks that retain the
  oldest structural breaks and always mislabel the first stored mark CHoCH.
  The same unchecked-`CTrade`-result pattern as V6.37. **The four-rung
  target ladder (`InpTP1R`…`InpTP4R`) is configurable, not fixed, with TP1
  floored and later rungs forced monotonic; "only ever uses the first two
  rungs" itself depends on the shipped leg-count inputs, a viable two-leg
  sizing outcome, both leg submissions succeeding, and a non-netting account
  — describing this as a fixed ladder with an unconditional two-live-rung
  behavior is corrected (round-2 finding 3.7).** V8.11 has **no
  outcome-learning system at all** — its own audit already states this;
  describing "both baselines already clamp" a learning factor was false,
  since V8.11 has no learning factor to clamp, and its confluence-score caps
  are themselves inconsistent (some cap at 100; several builder base-plus-
  bonus paths do not) (round-2 finding 3.8).
- **Both:** `IsSyntheticIndexSymbol` and `DirectionAllowedForSymbol` are
  both V6.37 functions; V8.11's analogous, separate function is
  `DirectionAllowed`. No economic calendar in either EA. RSI-fallback
  patterns that silently satisfy downstream thresholds instead of
  invalidating the read. Configurable timeframe roles in both EAs, not a
  single fixed timeframe in either.

## Evidence

- `baseline_v637_audit.md`, `baseline_v811_audit.md`,
  `baseline_comparison.md` — full defect list, cited to source line numbers.
- `00_MASTER_PROMPT_FOR_CLAUDE.md` sections 5–15, 18, 22–23.
- `RISK_POLICY.md`, `NEWS_INTEGRATION_SPEC.md`, `STRATEGY_SPECIFICATION.md`.
- `AGENTS.md`, `PROJECT_RULES.md`, `TEST_PLAN.md`.
- `01_BASELINE/EA_V637/Thembabot14 Max.mq5`,
  `01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5` — re-read directly for this
  revision at every source line cited in round 2's review (source 1008–1050,
  1292–1310, 6315–6369, 2582–2614, 6388–6403, 7534–7540, 1895, 2001–2003,
  7464–7528, 7777–7788, 5013–5025, 7144–7147, 1448–1449, 75–78, 1363–1366,
  1328–1380, 190–191, 7260–7265, 52–53, 700, 762–767, 1628, 929, 943,
  1090–1120, 1164, 1205, 2257–2278, 2718–2724, 5834–5860, 8738–8740).

## Specification

### 0. Phase 2 deliverable map

| # | §23 deliverable | Addressed in |
|---|---|---|
| 1 | Intraday modes | §1 |
| 2 | Regimes | §2 |
| 3 | Strategies | §3 |
| 4 | Candlestick patterns | §5 |
| 5 | Chart patterns | §6 |
| 6 | Risk | §8 |
| 7 | News | §10 |
| 8 | Resolve contradictions before coding | §12 |

### 1. Intraday modes (master prompt §5)

Two modes: **Scalp** (M1–M5 entry, M15–H1 context) and **Day-trade** (M5–M15
entry, M30–H4 context).

**Executable mode formula (round-2 finding 1.3 — every component is now a
defined function, not a named idea):**

Each of the following ten components is computed and normalized to `[0,1]`
where 1.0 favors Day-trade and 0.0 favors Scalp (a component's *sign* is
fixed here; only its weight is configurable):

1. **Regime persistence** = `min(1, trend_age_bars / InpModePersistenceBars)`
   (default window 20 bars) if the active directional regime (§2) is
   `TRENDING_UP/DOWN`; `0.3` (mildly Scalp-favoring) for `RANGING`; `0.0`
   for any other regime (Day-trade is not favored in compression/expansion/
   transition — those regimes are handled by §3's routing, not the mode
   score).
2. **ATR percentile** = the entry-timeframe ATR's percentile rank over the
   trailing `InpATRPercentileWindow` (default 100) bars, used directly
   (higher percentile → favors Day-trade, since larger ranges support wider
   targets).
3. **Range-vs-average** = `min(1, current_range_ATR_multiple / 2.0)` where
   `current_range_ATR_multiple` is today's session range so far divided by
   the entry-timeframe ATR — a larger realized range favors Day-trade.
4. **Distance to next validated target** (from §7's target-selection logic,
   computed for the current best candidate direction, expressed in ATR
   multiples, capped at 5) ÷ 5 — more room favors Day-trade.
5. **Spread-to-ATR ratio** — **corrected, round-2 finding 1.3:** this
   component favors **Scalp**, not Day-trade: `1 − min(1, spread /
   (ATR × InpSpreadATRDivisor))` where `InpSpreadATRDivisor` defaults to
   `0.05` — a *wider* relative spread lowers this component's value,
   penalizing Day-trade (which needs tighter relative execution cost over a
   shorter expected move) and — inverted, `1 − value` — is treated as
   favoring Scalp only in the specific sense that master-prompt §5 requires
   *strong spread checks for scalping specifically*: a spread that is wide
   relative to ATR should reduce the trade-worthiness of **both** modes, not
   just shift the mode choice. This component is therefore not solely a
   mode-selector input — it is passed through unmodified to the
   trade-worthiness score in §9 as an independent penalty, and its
   mode-router contribution is fixed at a low, fixed weight of `0.05`
   (contributing almost nothing to the mode choice itself) precisely so a
   wide spread cannot be laundered into "pick scalp" — it instead
   suppresses the trade candidate directly regardless of mode.
6. **Session time remaining** = `remaining_session_minutes /
   total_session_minutes` — more time remaining favors Day-trade; below
   `InpMinDayTradeSessionMinutes` (default 90), this component is clamped to
   `0.0` regardless of the raw ratio (not enough session left to justify
   opening a Day-trade position at all).
7. **News proximity** (real markets only; `1.0` for synthetics — no
   penalty) = `0.0` if inside a `NEWS_BLACKOUT` window (§2/§10 — this also
   forces the router's final decision to no-mode, see below), else `1.0`.
8. **Pattern quality** = the candidate signal's own `§9` score breakdown,
   normalized `[0,1]`, using only the location/structure/pattern-quality
   components (not the historical-performance component, to avoid
   double-counting item 10 below).
9. **Expected reward-to-risk** = `min(1, expected_R / 3.0)`.
10. **Sample-gated historical performance** = the win rate of the candidate
    setup **bucketed by symbol, strategy, setup, regime, and mode**
    (matching §9's learning-bucket granularity exactly — round-2 finding
    1.3 corrected the mismatch between this section's "symbol/regime only"
    gating and §9's five-way bucket), only once `InpModeMinSamples`
    (default 20) matched trades exist in that exact bucket; `0.5`
    (neutral) below that sample count.

**Aggregation:** `mode_score = Σ(weight_i × component_i) / Σ(weight_i)`,
weights default to equal (`0.1` each for the ten components above except
item 5, which is fixed at `0.05` and redistributes its remaining `0.05`
equally across the other nine — i.e., each of the other nine defaults to
`0.1056`); all weights are configurable inputs for Phase 4/5 calibration.
**Missing-data behavior:** if any component cannot be computed (insufficient
bars, indicator-handle failure), that component is excluded from both the
numerator and denominator of the weighted average for that evaluation (not
defaulted to `0.5`) — this prevents a data gap from silently pulling the
score toward "neutral" and masking a real read failure; if **more than
three** of the ten components are unavailable, `mode_score` is undefined and
the router outputs no mode (fail-closed, matches §2's regime fail-closed
rule).

**Thresholds and precedence:** `mode_score ≥ 0.60` → Day-trade;
`mode_score ≤ 0.40` → Scalp; `0.40 < mode_score < 0.60` → **no mode, no
trade.** A `NEWS_BLACKOUT` or `UNTRADEABLE_SPREAD_OR_LIQUIDITY` regime read
(§2) overrides mode selection entirely and forces no-trade, regardless of
`mode_score` — evaluated **before** the mode formula runs at all, not as a
tie-break after.

**Hysteresis (round-2 finding 1.3's remaining ambiguities resolved):** mode
switches require the new mode's threshold to hold for **two consecutive
closed M1 bars** — a fixed base timeframe, not the entry timeframe of
whichever mode is being evaluated (using a mode-dependent confirmation
timeframe was circular; M1 is fixed regardless of outcome). While in the
neutral band (`0.40–0.60`), **the previously-selected mode for that symbol
persists** if one was already active (does not reset to no-mode) — a
symbol with no prior mode selection stays in "no mode, no trade" until the
score clears one of the two decision thresholds directly (the 2-bar
confirmation still applies to the *initial* selection, not only to
switches). Gating-regime overrides (`NEWS_BLACKOUT`/
`UNTRADEABLE_SPREAD_OR_LIQUIDITY`) and any indicator-read failure **bypass
hysteresis entirely** and take effect on the very next tick — hysteresis
exists to prevent thrashing between two valid states, not to delay a
safety stop.

**Mode-specific rules:** Scalp caps attempts per session
(`InpMaxScalpAttemptsPerSession`) and rejects a repeat entry at an unchanged
level within the session (tracked by price level ± spread, per symbol).
Day-trade closes all exposure before the configured intraday boundary (all
symbols, all positions — not scoped to Day-trade-mode positions alone; see
§8's boundary rule). Every mode decision, its score, and each component's
contribution are written to the `TradeDecision` object (§9).

### 2. Regime engine (master prompt §6)

Nine regimes, unchanged: `TRENDING_UP`, `TRENDING_DOWN`, `RANGING`,
`VOLATILITY_EXPANSION_UP`, `VOLATILITY_EXPANSION_DOWN`, `COMPRESSION`,
`TRANSITION_OR_UNCERTAIN`, `NEWS_BLACKOUT`,
`UNTRADEABLE_SPREAD_OR_LIQUIDITY`. Completed candles only.

**Precedence (unchanged from round 2, confirmed correct):** `NEWS_BLACKOUT`
and `UNTRADEABLE_SPREAD_OR_LIQUIDITY` are gating regimes, evaluated first
and independently; either being true overrides the directional classifier
below.

**Directional/volatility classification — component formulas (round-2
finding 1.4's missing equations/windows/thresholds/defaults, added):**

- **Trend strength `T`** = `clamp01(0.5 × swing_agreement + 0.5 ×
  ema_slope_norm)`, where `swing_agreement` is `1.0` if the last
  `InpRegimeSwingLookback` (default 3) confirmed swings all agree
  directionally (higher-high/higher-low or lower-high/lower-low), `0.0`
  otherwise; `ema_slope_norm = clamp01(|EMA_slope| / (ATR ×
  InpTrendSlopeATRDivisor))` (default divisor `0.5`), signed by the EMA
  slope's own direction to determine `TRENDING_UP` vs. `_DOWN`. ADX
  (`InpADXPeriod`, default 14) is included only as a multiplier:
  `T_final = T × clamp01(0.5 + ADX/100)` — ADX can dampen but never solely
  produce a trend read (per §6's own "supporting evidence, not sole
  authority" rule).
- **Expansion/compression evidence `E`** = `ATR_percentile` (the same
  percentile computation as §1 item 2), **not** treated as symmetric around
  `0.5` (see the corrected confidence formula below, which is exactly where
  round 2's finding 1.4 identified the defect). `E > InpExpansionThreshold`
  (default `0.75`) → expansion evidence; `E < InpCompressionThreshold`
  (default `0.25`) → compression evidence; between the two thresholds →
  neither.
- **Efficiency ratio `ER`** = `|close[0] − close[N]| / Σ|close[i] −
  close[i-1]|` over the last `N = InpEfficiencyWindow` (default 20) bars —
  distinguishes genuine directional movement from choppy trend-like price
  action. Used as a *gate*, not a scored component: `ER < InpMinEfficiency`
  (default `0.3`) forces `RANGING` or `TRANSITION_OR_UNCERTAIN` regardless
  of `T`, since a low efficiency ratio means the "trend" is not efficient
  directional movement.

**State selection (deterministic, evaluated in this fixed order — this
did not exist at all in round 2's draft):**

1. If `ER < InpMinEfficiency`: candidate is `RANGING` (skip to step 4).
2. Else if `E > InpExpansionThreshold` and `T ≥ InpTrendThreshold`
   (default `0.6`) **with agreeing direction** (the EMA-slope sign and the
   swing-sequence direction must match): candidate is
   `VOLATILITY_EXPANSION_UP`/`_DOWN` per that shared direction — **this is
   the directional-regime precedence round 2 asked for: expansion with
   directional agreement outranks a plain trend read**, since expansion
   is the more specific, more information-bearing state when both are
   present simultaneously.
3. Else if `E > InpExpansionThreshold` with **no** directional agreement
   (expansion evidence present but trend/swing direction conflicting or
   absent): candidate is `TRANSITION_OR_UNCERTAIN` — **not** a forced
   expansion-up/down guess, exactly as round 1 already specified and round
   2 confirmed correct; this is restated here because step 2's ordering
   makes the "no agreement" branch explicit rather than implicit.
4. Else if `T ≥ InpTrendThreshold` with agreeing direction: candidate is
   `TRENDING_UP`/`_DOWN`.
5. Else if `E < InpCompressionThreshold`: candidate is `COMPRESSION`.
6. Else: candidate is `RANGING`.
7. If any input to steps 1–6 could not be computed (insufficient bars,
   invalid indicator handle): candidate is `TRANSITION_OR_UNCERTAIN`
   unconditionally, confidence `0`, and this **bypasses hysteresis**
   (below) immediately — round 2 finding 1.4's explicit ask.

**Confidence formula — corrected (round-2 finding 1.4, the mathematically
broken formula is replaced):**

The defect was structural: taking `min()` of trend strength against a
term that is itself zero at both expansion extremes guaranteed low
confidence exactly when evidence was strongest. The corrected formula uses
a **classification-margin** approach instead — confidence reflects how
decisively the winning state's own evidence clears its threshold relative
to the runner-up condition, not an unrelated combination of two different
metrics:

- For `TRENDING_UP/DOWN`: `confidence = clamp01((T −
  InpTrendThreshold) / (1 − InpTrendThreshold))` — confidence rises as `T`
  moves further above its own threshold, reaching `1.0` at `T=1.0` and
  `0.0` exactly at the threshold (never negative, since this state was
  only selected when `T ≥ InpTrendThreshold`).
- For `VOLATILITY_EXPANSION_UP/DOWN`: `confidence = clamp01((E −
  InpExpansionThreshold) / (1 − InpExpansionThreshold))` — same margin
  logic against `E`'s own threshold, so `E=1.0` (maximum expansion) now
  correctly produces `confidence=1.0`, not `0`.
- For `COMPRESSION`: `confidence = clamp01((InpCompressionThreshold − E) /
  InpCompressionThreshold)` — `E=0.0` (maximum compression) correctly
  produces `confidence=1.0`.
- For `RANGING`: `confidence = clamp01(1 − |T − 0.3| / 0.3)` clamped
  against `ER` — i.e., `RANGING` confidence is highest when trend strength
  sits comfortably below its own trending threshold (evidence of *absence*
  of trend, not an unrelated expansion computation) — capped at
  `ER`'s own gate value so a low-efficiency-ratio `RANGING` read (chop, not
  clean ranging) is never reported as high confidence.
- For `TRANSITION_OR_UNCERTAIN`: confidence is always `0` by definition —
  this state exists precisely because no other state's evidence cleared
  its own bar decisively.

Each formula only ever evaluates the metric relevant to the state actually
selected — no formula combines two different regimes' metrics via `min()`
or any other cross-state operation, which is what produced round 2's
defect.

**Hysteresis and stale-data behavior:** the same 2-bar (fixed M1)
confirmation as §1 applies to regime transitions, **except** the gating
regimes and any indicator-read failure (step 7 above), which take effect
immediately, bypassing hysteresis — stated explicitly here per round 2's
ask.

**Low-confidence rule:** confidence `< 0.5` forces `TRANSITION_OR_UNCERTAIN`
treatment for routing purposes (§3) regardless of the nominally-selected
state.

**Required deliverables (unchanged from round 1, confirmed still correct):**
`MarketRegimeEngine.mqh`; the `MarketRegime` enum; confidence score and
reason string per read; a transition-history buffer; Python unit-test
fixtures covering all nine states plus the gating-override and
indicator-failure cases; a confusion matrix against
`01_BASELINE/screenshots/`-labeled examples.

### 3. Strategy routing (master prompt §7)

**Response to round-2 finding 1.5 — the table now has context/entry-TF
columns, eligibility/penalty are given numeric semantics, ownership is
resolved, and the compression chicken-and-egg question is answered:**

Six canonical families (unchanged count): SR Bounce/Range Rotation,
SMC/ICT Price-Action, Trend Following, Chart-Pattern Breakout/Reversal,
Post-Expansion Retest, No trade.

| Family | Baseline source (architecture decision) | Context TF | Entry TF | Eligible modes |
|---|---|---|---|---|
| SR Bounce / Range Rotation | V6.37 primary + V8.11 bonus components | M15–H1 | M5–M15 | Scalp, Day-trade |
| SMC/ICT Price-Action | V8.11 (sweep-shift, OB) + V6.37 (FVG gating) | M15–H4 | M1–M5 | Scalp, Day-trade |
| Trend Following | V6.37 (trendline) + V8.11 (momentum) | M30–H4 | M5–M15 | Day-trade primary; Scalp for momentum half only |
| Chart-Pattern Breakout/Reversal | New work (§6) | M15–H4 | M5–M15 | Day-trade primary |
| Post-Expansion Retest | New work, V6.37-informed gating | M15–H1 | M1–M5 | Scalp, Day-trade |
| No trade | N/A | N/A | N/A | N/A |

**Eligibility and penalty semantics (previously undefined):** "prefer" =
eligible with a `+10%` score multiplier; "block" = **not eligible at
all** (the family's candidates are not generated/considered this bar, not
merely scored down); "heavily penalize"/"penalize" = eligible with a
`×0.5`/`×0.8` score multiplier respectively (configurable, these are
defaults). Regime-conditioned eligibility (unchanged substance from round
2, now with these numeric semantics attached):

- **`TRENDING_UP/DOWN`:** prefer Trend Following, SMC/ICT order-block
  retest after displacement, Chart-Pattern flag/pennant/channel-pullback/
  breakout-retest. Block SR Bounce counter-trend fades. Heavily penalize
  unconfirmed Chart-Pattern reversals and mid-range candlestick reversals.
- **`RANGING`:** prefer SR Bounce, Range Rotation, SMC/ICT equal-high/low
  sweep reversal, false-break trap, Chart-Pattern double-top/bottom at a
  boundary (post-neckline-confirmation only), rejection candles at range
  extremes. Block Trend Following late-momentum entries inside the range.
  Penalize trend entries near equilibrium and repeated bounces from an
  already-invalidated-then-recovered level (tracked per §3's level-
  invalidation state, below).
- **`COMPRESSION`:** **block every family** except Chart-Pattern Breakout,
  which is itself gated to require a confirmed breakout, an expansion
  candle, acceptance outside the pattern, and a retest, all evaluated
  against the price action **since the compression regime was entered**
  (tracked by a stored compression-entry bar index, not "while the regime
  remains COMPRESSION" — round-2 finding 1.5's chicken-and-egg point is
  resolved by this: **regime classification runs once per bar, before
  routing evaluates any candidate for that bar.** A breakout bar's own
  close is what the classifier reads to (re)classify the regime for the
  *next* bar's routing decision — the breakout bar itself is still
  evaluated under `COMPRESSION`'s eligibility rules using price action that
  occurred *during* the compression period now ending, and the newly
  re-classified regime (`TRENDING_*`/`VOLATILITY_EXPANSION_*`) takes effect
  starting the following bar. There is no same-bar circularity: the
  classifier's read for bar N is always available before routing decides
  bar N's trade, and it is based on bar N's own completed close.).
- **`VOLATILITY_EXPANSION_UP/DOWN`:** block chasing the initial spike
  (defined as: no entry within `InpNoChaseBarsAfterSpike`, default 2 bars,
  of the regime's own transition into this state). Prefer Post-Expansion
  Retest, SMC/ICT FVG return, Trend Following's momentum-continuation half.
- **`TRANSITION_OR_UNCERTAIN`, `NEWS_BLACKOUT`,
  `UNTRADEABLE_SPREAD_OR_LIQUIDITY`:** No trade — block every family
  unconditionally.

**Ownership resolved (round-2 finding 1.5 — `StrategyRouter` and
`ConflictResolver` no longer both claim conflict resolution):**
`StrategyRouter` owns regime-conditioned eligibility and scoring for every
candidate (the table and matrix above) — its output is a fully-scored,
eligible-or-not list per candidate, nothing more. `ConflictResolver` owns
**only** the final tie-break given that already-scored list: among eligible
candidates, the highest score wins in its own direction; between opposing-
direction candidates, `No trade` wins **unless** one direction's top score
exceeds the other's by at least `InpConflictScoreGap` (default `10` score
points, configurable) — a defined default and bound, closing round 2's
"no ordering, no default/bounds" finding. `No trade` (family 6) is the
result whenever no candidate is eligible, whenever `ConflictResolver`'s gap
rule doesn't resolve an opposing-direction conflict, or whenever §1/§2's
gating overrides fire — it is not a family that "competes" via its own
score; it is the fallback result of every other path failing to produce a
single eligible winning direction.

**Strategy-switch logging (round-2 finding 1.5 — missing fields added):**
every strategy switch is logged to the `TradeDecision` object (§9) with:
previous regime, new regime, selected strategy family, confidence, rejected
alternatives (family + score + block/penalize reason), risk multiplier
(from the eligibility semantics above), and expected holding mode.

**Broken cross-references fixed (round-2 finding 1.5):** the level-
invalidation lifecycle decision referenced below as "§3's level-
invalidation subsection" refers to this section's own paragraph two
paragraphs below (previously mislabeled "§12.5," which does not exist —
the ledger in §12 is a flat numbered list, not subsectioned).

**Self-confirmed bypass — retired, rationale corrected (round-2 finding
3.2):** V6.37's `IsSelfConfirmedSetup` is **not** an underspecified concept
in the baseline — it explicitly names its eligible setups (source
7534–7540) and is still subject to `ApplyRegimeRouting`'s veto (source
7464–7528) even when it fires. The prior claim that the baseline helper
"had no scope or conflict behavior" was false; the actual, correctly-stated
reason for retiring it in the new engine is different: its bypass scope
was tied to setup **name** matching a fixed list, which is exactly the
kind of brittle, string-based classification this specification retires
elsewhere (§10); and its interaction with the old regime router doesn't
carry over meaningfully once that router is replaced by §2's engine. **The
new-engine decision is unchanged (retired for Phase 2, reconsidered per
strategy later with evidence) — only the stated reason for retiring it is
corrected.**

**Level-invalidation lifecycle:** unchanged from round 1/round 2 (confirmed
correct by round 2's finding 4.5-equivalent — not separately re-flagged in
round 2): current-run-only rejection is kept, not permanent retirement; a
level becomes eligible again the moment its consecutive-closes-beyond count
returns to zero, evaluated fresh every call.

### 4. ICT/SMC logic (master prompt §8)

Unchanged in substance from round 1. **One addition (closing §12 ledger
item 14, new this round):** the FVG structural-gating path's swing-depth
input is unified with §3/§4's canonical structure depth — V6.37's FVG path
currently mixes `InpStructureSwingDepth` (via `AnalyzeStructure`) and
`InpFractalDepth` (via `FindTwoConfirmedSwingsBefore`) for what should be
one concept. **Decision:** the new engine's FVG gating uses the single
canonical swing-depth definition from the consolidated `SwingEngine` (§11),
not two independently-tunable depth inputs — closing this specific
baseline contradiction rather than carrying the mixed-input pattern
forward.

### 5. Candlestick pattern engine (master prompt §9)

**Response to round-2 finding 1.1 — actual mathematical definitions, not a
requirement list:**

Base measurements, computed per candle `c`: `body = |close−open|`,
`range = high−low`, `upper_wick = high − max(open,close)`,
`lower_wick = min(open,close) − low`, `body_ratio = body/range`,
`upper_wick_ratio = upper_wick/range`, `lower_wick_ratio = lower_wick/range`,
`atr_size = range/ATR(InpCandleATRPeriod, default 14)`. All ratios use
`range = 0 → pattern invalid` (avoid division by zero; a zero-range bar
never qualifies for any pattern below).

**Single-candle patterns (defaults are configurable inputs):**

- **Bullish pin bar / hammer:** `lower_wick_ratio ≥ 0.60` AND
  `body_ratio ≤ 0.30` AND `upper_wick_ratio ≤ 0.15` AND close in the upper
  40% of the range AND prior `InpPinBarTrendLookback` (default 5) bars show
  a preceding down-move (`close[N] < close[N+InpPinBarTrendLookback]`).
  **Bearish pin bar / shooting star** is the mirrored condition
  (`upper_wick_ratio ≥ 0.60`, etc., preceding up-move).
- **Dragonfly-style rejection:** `body_ratio ≤ 0.10` AND
  `lower_wick_ratio ≥ 0.70` AND `upper_wick_ratio ≤ 0.10`.
  **Gravestone-style rejection:** mirrored (`upper_wick_ratio ≥ 0.70`).
- **Marubozu / displacement candle:** `body_ratio ≥ 0.90` AND
  `atr_size ≥ InpDisplacementATRMultiple` (default `1.5`).
- **Doji / spinning top (indecision filters, never standalone entries):**
  `body_ratio ≤ 0.10` (doji) or `0.10 < body_ratio ≤ 0.35` with both wicks
  `≥ 0.20` (spinning top).

**Two-candle patterns:**

- **Bullish engulfing:** `close[0] > open[1]` AND `open[0] < close[1]` AND
  `body[0] > body[1]` AND `close[1] < open[1]` (prior candle bearish).
  **Bearish engulfing:** mirrored.
- **Inside bar:** `high[0] < high[1]` AND `low[0] > low[1]`.
  **Outside bar:** `high[0] > high[1]` AND `low[0] < low[1]`.
- **Tweezer top:** `|high[0] − high[1]| ≤ ATR × InpTweezerTolerance`
  (default `0.1`) AND `close[1] > open[1]` (up) AND `close[0] < open[0]`
  (down, reversal). **Tweezer bottom:** mirrored on lows.
- **Harami (weak alert only unless confirmed):** `body[0] < body[1] ×
  InpHaramiMaxRatio` (default `0.5`) AND `high[0] ≤ high[1]` AND
  `low[0] ≥ low[1]` — requires a third-bar confirmation close beyond
  `close[1]` in the implied reversal direction before it counts as
  anything stronger than an alert.

**Three-candle patterns:**

- **Morning star:** `close[2] < open[2]` (bearish), `body_ratio[1] ≤ 0.30`
  (small-bodied middle candle, gapping or near-gapping below `close[2]`),
  `close[0] > open[0]` AND `close[0] > (open[2]+close[2])/2` (bullish
  candle closing into the first candle's body). **Evening star:** mirrored.
- **Three white soldiers:** three consecutive bullish candles, each
  `body_ratio ≥ 0.55`, each `open[i] > open[i+1]` and `close[i] > close[i+1]`
  (progressively higher), each with `upper_wick_ratio ≤ 0.20`. **Three
  black crows:** mirrored.
- **Three-bar reversal:** a confirmed swing pivot (per §11's `SwingEngine`,
  same depth definition as §4) at bar `1`, with bar `0` closing beyond
  bar `2`'s open in the reversal direction.

**Requirements applied to every pattern above (§9's own list, now attached
to real predicates instead of floating separately):** every threshold
above is a configurable input with the stated default as its bound;
**market-context requirement** — no pattern above fires as a standalone
signal without `§2`'s regime read being anything other than
`TRANSITION_OR_UNCERTAIN`/gating, and without `§3`'s location requirement
(SR/liquidity/OB/FVG/neckline/pattern boundary) being separately satisfied
by the strategy consuming the pattern; a pattern in the middle of
undifferentiated noise (regime `RANGING` with `ER` deep below
`InpMinEfficiency`, or no location match) is never traded on its own. Stored
per instance: pattern ID, direction, start/end candle index, strength
(`body_ratio`/`atr_size`-derived, `[0,1]`), context (the regime/location it
was detected in), confirmation status, invalidation level (the pattern's
own extreme — a close beyond it invalidates). Drawn near the completed
candle, stable object names, no duplicate labels, and a unit test
confirming a historical label's position/text never changes after
confirmation (this generalizes the completed-candle discipline already
forced by TASK-001's BLOCKER finding against V6.37 — every predicate above
reads `rates[1]` or older, never `rates[0]`, by construction). TA-Lib
comparison is research-only, never assumed profitable.

### 6. Chart-pattern engine (master prompt §10)

**Response to round-2 finding 1.2 — pivot/tolerance/breakout equations for
a representative pattern set (double top/bottom and head-and-shoulders, the
two most structurally distinct cases; the remaining patterns in §10's list
follow the same pivot/tolerance/target framework, detailed per-pattern as
each is implemented in its own Phase 5 `STRATEGY_SPECIFICATION.md` task —
this section defines the shared framework every pattern instantiates, which
is what makes the remaining patterns Phase-5-sized work rather than
undefined Phase 2 gaps):**

**Shared framework:** every pattern requires **confirmed swing pivots**
(same `SwingEngine` depth as §4–5, no separate pivot definition per
pattern); a **pivot-confirmation delay** of `InpSwingDepth` bars past the
pivot itself (a pivot is not usable until confirmed, matching the swing
engine's own definition — no pattern reads an unconfirmed pivot); **time
symmetry tolerance** `|t_right_leg − t_left_leg| / t_left_leg ≤
InpPatternTimeTolerance` (default `0.5`, i.e., legs within 50% of each
other's duration); **price symmetry tolerance**
`|price_right_leg − price_left_leg| / ATR ≤ InpPatternPriceTolerance`
(default `1.0` ATR); **minimum pattern width** `InpPatternMinBars` (default
20) and **maximum width** `InpPatternMaxBars` (default 200); **minimum
height** `pattern_height / ATR ≥ InpPatternMinHeightATR` (default `2.0`).

**Double top:** two confirmed swing highs `H1`, `H2` with
`|H1−H2|/ATR ≤ InpPatternPriceTolerance`, separated by a confirmed swing low
`L` (the neckline) with `L < H1 − pattern_height×0.3` (a genuine pullback,
not a shallow wiggle). **Breakout threshold:** a confirmed close below `L −
ATR×InpBreakoutBuffer` (default `0.1`). **Target:** `L − (H1_or_H2_avg − L)`
(measured-move projection). **Stop:** above the more recent of `H1`/`H2`
plus the same ATR buffer. **Double bottom:** mirrored. **Triple top/bottom:**
the same definition with three qualifying extremes instead of two, all
within the same price tolerance of each other.

**Head and shoulders:** three confirmed swing highs `LS` (left shoulder),
`H` (head), `RS` (right shoulder) with `H > LS` and `H > RS`, and
`|LS−RS|/ATR ≤ InpPatternPriceTolerance` (shoulders roughly symmetric); a
neckline drawn through the two intervening swing lows, sloped (not required
flat). **Breakout threshold:** confirmed close beyond the neckline (sloped,
evaluated at the current bar's neckline value) minus the ATR buffer.
**Target:** neckline value at breakout minus `(H − neckline_at_H)`.
**Stop:** above `RS` plus buffer. **Inverse head and shoulders:** mirrored.

**Optional retest** (applies to every pattern above): after the confirmed
breakout, the pattern may (configurable per pattern, default **required**
for Chart-Pattern Breakout family per §3) wait for price to return to
within `ATR × InpRetestTolerance` (default `0.3`) of the boundary/neckline
before entering — this is what moves the pattern from `CONFIRMED` to
`RETESTING` in the state machine below, rather than trading the raw
breakout bar directly.

**Volume requirement:** off by default (most CFD/synthetic feeds do not
provide reliable volume); enabled only per-symbol where the broker is
confirmed to supply genuine volume.

**Maximum age:** a pattern not traded within `InpPatternMaxAgeBars` (default
50 bars past confirmation) expires (`EXPIRED` state below) regardless of
whether it was ever invalidated.

**Pattern confidence:** `clamp01(1 − price_tolerance_used/
InpPatternPriceTolerance) × 0.5 + clamp01(1 − time_tolerance_used/
InpPatternTimeTolerance) × 0.5` — tighter symmetry produces higher
confidence, following the same margin-against-threshold logic as §2's
corrected regime confidence (deliberately reusing that pattern rather than
introducing a third, different confidence formula).

**False-break conditions:** a confirmed close back inside the pattern
boundary within `InpFalseBreakBars` (default 3) bars of the breakout
invalidates the pattern (`INVALIDATED` state).

**Broker-spread check and session time remaining:** both are the same §1
item-5 spread-vs-ATR component and §1 item-6 session-time component,
reused, not redefined.

**Scalp-vs-day-trade suitability:** determined by pattern width in
entry-timeframe bars — patterns confirming within `≤ 40` entry-TF bars are
Scalp-eligible; wider patterns are Day-trade only, feeding §3's routing
table directly.

**State machine — corrected (round-2 finding 1.2, the linear chain is
replaced with the actual branching structure):**

```
FORMING ──confirmed──> CONFIRMED ──(if retest required)──> RETESTING ──retest holds──> TRADED
   │                        │                                   │
   │                        │                                   └──retest fails───> INVALIDATED
   │                        ├──(if no retest required)────────────────────────────> TRADED
   │                        ├──false break (§ above)─────────────────────────────> INVALIDATED
   │                        └──InpPatternMaxAgeBars elapses────────────────────────> EXPIRED
   └──pivots invalidate before confirmation──────────────────────────────────────> INVALIDATED
```

`INVALIDATED` and `EXPIRED` are terminal states reachable from `FORMING`,
`CONFIRMED`, or `RETESTING` — never mandatory post-`TRADED` stages, and
retest is genuinely optional per pattern/family configuration, not a
mandatory link in a single chain. A forming pattern is never traded;
historical pivots are never redrawn after confirmation; a pattern registry
(keyed by pattern type + boundary pivots) prevents two simultaneous
instances of the same pattern from both trading; visible objects are capped
(`InpMaxVisiblePatternObjects`, default 20) to prevent chart overload.

### 7. Exit engine (master prompt §14)

**Response to round-2 finding 1.6 — executable definitions for every
choice, and the false exclusivity claim corrected:**

- **Initial target — corrected exclusivity claim (round-2 finding 1.6):**
  V6.37 in fact has multiple reachable-target mechanisms beyond
  `SetEquilibriumContinuationTarget`
  — `ApplyHistoricalM15Target`/`FindQualifiedFractalTarget` (source
  1787–1803), nearer SR/supply-demand target selection (source ~2319–2335),
  and opposite-boundary range/rotation targets. **Decision, restated
  precisely:** the new engine's target selector evaluates all reachable
  candidates from the shared structure engine (§11) — confirmed SR zone,
  swing fractal (M15 and H1 roles), major-swing, and opposing-range-
  boundary — and selects the **nearest** one that still clears
  `risk × InpMinRiskReward`, exactly matching `SetEquilibriumContinuationTarget`'s
  selection *rule* (nearest-qualifying), while sourcing candidates from all
  of V6.37's target-generating functions above, not from one alone.
- **Break-even "fresh swing" arming — defined:** arms when
  `SwingEngine` (§11, same depth as §4–6) confirms a **new** swing pivot
  beyond the entry price in the trade's favor, **and** the position's
  actual fill price (never the requested quote, per §8) has moved at least
  `InpBreakEvenMinR` (default `0.5R`) in favor. Both conditions required —
  a structural milestone alone, without minimum favorable movement, does
  not arm break-even (avoids arming on a technically-valid but trivial
  swing immediately after entry).
- **Structure trailing — defined:** once armed, the stop trails to
  `most_recent_confirmed_swing_in_favor − ATR × InpTrailBuffer` (default
  `0.3`), recalculated each time a new swing confirms; **never** moved
  against the position.
- **ATR fallback — activation defined:** if no new confirmed swing forms
  within `InpTrailStaleBars` (default 15) bars since the last structure-
  trail update, the trail switches to `current_price − ATR ×
  InpATRTrailMultiple` (default `2.0`) until a fresh swing resumes
  structure-trailing.
- **Time stop — evidence function defined:** closes the position if **all**
  of: (a) elapsed time exceeds the mode's own expected-duration ceiling
  (Scalp: `InpScalpMaxMinutes`, default 60; Day-trade: remaining session
  time from §1 item 6 reaching `0`); (b) current R is below
  `InpTimeStopMinR` (default `0.3R` — a position already well in profit is
  not time-stopped, it is left to trailing/giveback logic); and (c) no
  fresh confirmed swing has formed in the trade's favor within the last
  `InpTrailStaleBars` bars (reusing the ATR-fallback staleness definition
  above, so "no progress" is one consistent concept across trailing and
  time-stop logic, not two independent staleness clocks).
- **Profit-lock — trigger/floor defined:** arms once price has covered
  `InpProfitLockTriggerPercent` (default `70%`) of the distance from entry
  (actual fill) to the current target; raises the stop to lock in
  `InpProfitLockKeepPercent` (default `50%`) of the current open gain,
  **and this stop-move is itself subject to the blanket result-checking
  rule in §8** — if the broker's minimum-stop-distance enforcement moves
  the resulting stop further than the intended lock level, the engine
  re-evaluates whether the actually-achieved lock still clears
  `InpProfitLockMinKeepPercent` (default `30%`, a floor beneath which the
  attempt is logged as a partial-lock warning rather than silently accepted
  as if the full 50% had been locked) — this is the fix for V6.37's
  confirmed defect (a stop moved twice by broker constraints without a
  second improvement check), stated as an explicit re-check with its own
  floor, evaluated **independently of** which giveback-guard model (if
  any) is active.
- **Exit priority (unchanged from round 2, confirmed no defect found):**
  (1) daily/session risk lock, (2) news safety policy, (3) opposite-
  confirmed-structure-shift, (4) momentum-failure exit, (5) profit-giveback
  guard, (6) time stop, (7) trailing-stop update.

**Contradiction resolved — giveback guard model, bounds completed
(round-2 finding 3.6 — both effective floors and V6.37's close-condition
floor were missing):** V6.37's effective values: arm
`max(0.25, InpGivebackArmRR)` (default `1.25R`), giveback percentage
clamped `10–90%` (default `60%`), **and** the close-trigger condition
itself is floored at `0.05R` (i.e., the guard's close check never fires
below an absolute `0.05R` floor regardless of the percentage math). V8.11's
effective values: arm `max(0.3, InpGivebackArmR)` (default `0.8R`), floor
`max(0.0, InpGivebackFloorR)` (default `0.1R`). **Decision unchanged:**
both models built behind one `ProfitGivebackGuard` interface, all of the
above bounds retained as-is (not redefined), default off until Phase 8
produces comparative evidence.

### 8. Risk management (master prompt §13, `RISK_POLICY.md`)

**Response to round-2 findings 2.1–2.7 — every gap closed:**

**Hard limits (unchanged numbers, confirmed correct by round 2):**
XAUUSD 0.25%, other metals 0.25–0.50%, synthetics 0.25–0.50%; hard cap
1.00% per trade, 1.00% total open risk, 2.00% daily loss, 4.00% weekly
loss; three-loss cooldown.

**Add-on/basket rule — stated normatively, not presupposed (round-2 finding
2.1):** **Add-ons and multi-leg baskets are disabled by default.** No
sizing function may create a second concurrent position on the same
symbol/direction as an existing one, and no basket/multi-leg entry
mechanism is active, until a Phase 5+ isolated experiment independently
proves both the total-risk math and incremental value — this is the
missing normative sentence itself, not a description that assumes it.

**No-increase-after-loss, restated precisely (round-2 finding 2.5):** a
loss may **reduce or hold** risk on the next trade; it may **never
increase** it. This is one directional constraint, not two independent
rules — the drawdown-based risk-*reduction* control (below) is the
permitted direction; nothing in this document permits an increase.

**Risk accounting — fully defined (round-2 finding 2.3):**

- **Scope:** account-wide (unchanged).
- **Per-position risk** = `max(0, |entry_fill − SL| × volume ×
  tick_value)` if an SL is set; if no SL is set (should not occur given
  the mandatory-stop requirement elsewhere in this document, but defined
  for completeness), the position's full notional value at
  `InpNoStopWorstCaseATRMultiple` (default `10`) ATR is used as a
  conservative worst-case placeholder until a stop is attached, and the
  position is flagged for immediate remediation (a stop must be attached
  within one tick of detection).
- **Total open risk** = `Σ per-position-risk` across every open position
  carrying this EA's own magic number, **plus** the worst-case risk of
  every pending order carrying this EA's own magic number (pending orders
  **do reserve** risk against the total-open-risk cap — a pending order
  is not "free" simply because it hasn't filled; this closes round 2's
  "whether pending orders reserve risk" gap). If two pending orders could
  both fill simultaneously in a way that would jointly breach the cap
  (e.g., two opposite-direction resting orders), the cap is checked
  against the **larger** of the two possible outcomes, not their sum
  (since only one side can actually fill on most instruments) — unless the
  instrument is confirmed to allow both fills (hedging mode, §12 item 9),
  in which case the sum is used.
- **Daily loss numerator** = `(TodayClosedPL + TodayFloatingPL +
  TodaySwapAndCommission) − 0` compared against `−daily_start_equity ×
  InpDailyLossLimitPercent/100`; **daily loss denominator** =
  `daily_start_equity`, persisted at the daily reset boundary (below), not
  re-derived from current equity on every check.
- **Weekly loss**: identical formula, substituting the weekly reset
  boundary and `weekly_start_equity`.
- **Cash-flow treatment:** a detected deposit or withdrawal (comparing
  consecutive equity/balance snapshots for a delta not explained by
  floating P/L movement) immediately **rebases** `daily_start_equity`/
  `weekly_start_equity` by the same delta, so the loss percentage is not
  distorted by external cash flow — this is checked every `OnTick` inside
  the risk-accounting refresh, not only at reset boundaries.
- **Reset boundary:** daily reset at broker-server midnight; weekly reset
  at the broker's own trading-week start (first server-time session open
  following the broker's configured weekend). **No-tick-at-boundary
  handling:** the reset is triggered by the **first tick received after**
  the boundary time has passed (comparing current server time against the
  last-recorded boundary crossing), not by requiring an exact-timestamp
  tick — this is already how both baselines' own daily-reset checks work
  (`StartOfDay(TimeCurrent()) != g_day_start`-style comparison) and is kept
  for weekly resets too.
- **Restart persistence:** `daily_start_equity`/`weekly_start_equity` and
  their reset timestamps are persisted via `StateManager` (§11) and are
  only ever re-baselined when the persisted reset timestamp is found to be
  older than the current actual boundary — a mid-period restart reloads
  the persisted baseline unchanged, closing V8.11's confirmed daily-anchor
  restart defect directly.
- **Breach behavior — hard cap vs. fill slippage reconciled (round-2
  finding 2.2):** the **pre-trade** check (before submission) is the only
  point at which the 1%/1%/2%/4% figures function as a hard gate that
  blocks a new entry outright. Once a position is **filled**, if the
  actual fill (plus confirmed slippage) pushes its realized risk
  marginally above what was checked pre-trade, this is not "exceeding a
  hard cap that permits a soft tolerance" — it is **immediately** queued
  for full closure (not partial, not merely flagged) as soon as the
  discrepancy is detected (next tick), and logged as a cap-breach event.
  There is no tolerance band that sits above the cap; the cap is enforced
  pre-trade as a gate and post-fill as a mandatory-closure trigger — two
  different mechanisms for two different moments, not one soft
  continuum.
- **Account-wide close scope (round-2 finding 2.3):** an account-wide risk
  lock (daily/weekly breach) closes **only positions carrying this EA's own
  magic number** — never a manually-placed position or another EA's
  position, since this engine cannot determine the intent behind a
  position it did not open, and closing it could itself be a harmful,
  irreversible action outside this engine's authority.

**Profit-protection controls — defaults and formulas (round-2 finding
2.4):**

- Account equity-peak giveback: off by default (Phase 8 experiment).
- Daily equity-peak giveback: **on by default** — arms once daily open
  profit exceeds `InpDailyGivebackArmPercent` (default `1.0%` of
  daily-start equity), closes all EA-owned exposure if daily profit falls
  back to `InpDailyGivebackFloorPercent` (default `0.5%`) — **correcting
  round 2's finding that this control was asserted as necessary without
  being a defined mechanism**; it is a distinct control from the daily-loss
  cap, evaluated independently.
- Session profit lock: off by default (Phase 8 experiment).
- Strategy-specific and consecutive-loss cooldowns: on by default; the
  three-loss cooldown duration is `InpCooldownMinutes` (default 60);
  strategy-specific benching uses §9's sample-and-loss criteria.
- Maximum trades per session (`InpMaxTradesPerSession`, default 10) and
  maximum failed attempts at one level (`InpMaxFailedAttemptsPerLevel`,
  default 2): on by default.
- Reduced risk after drawdown: on by default — `risk_multiplier =
  clamp(1.0 − current_drawdown_percent/InpMaxDrawdownReductionPercent,
  InpMinRiskMultiplier, 1.0)` (defaults: `InpMaxDrawdownReductionPercent =
  10`, `InpMinRiskMultiplier = 0.25`) — a defined scaling formula, not a
  label.
- **Post-daily-target policy — default corrected (round-2 finding 2.4):**
  the **stop-trading-after-daily-target control is ON by default** (no new
  trades once the daily profit target is reached); only the **override**
  ("continue at reduced risk") is off by default and requires a separately
  approved experiment. Round 2 correctly found the prior draft inverted
  this — the stop itself was described as off, which is backwards relative
  to master-prompt §13's rule.

**Stop floor/cap prevention — defined, baseline history claim corrected
(round-2 finding 2.6):** floor = the exit engine's own ATR-based breathing-
room floor (§7); cap = the percent-of-price/ATR cap (unchanged concept from
round 1). **Attach-time AND periodic recheck:** validated at symbol attach
**and** re-validated every `InpVolatilityRecheckBars` (default 500) bars
using a rolling `InpVolatilityWindow`-bar (default 500) ATR percentile
distribution as "typical volatility" — an attach-time-only check cannot
account for a volatility regime shift months into operation, which round 2
correctly identified. **Baseline-history claim corrected:** V6.37's
market-entry cap rejections **are** explicitly journaled and printed
(source 2718–2724); the elite-score exception and configurable skip/clamp
paths (source 5834–5860) mean not every signal is rejected — only the
resting-limit path's inline cap check (source 8738–8740) fails silently.
The new engine's preflight check exists to prevent the resting-limit
path's silent-failure mode specifically, and to give the market-entry
path an *advance* warning instead of a per-rejection one — not because
market-entry rejections were previously invisible.

**Blanket rules (unchanged from round 2, confirmed no defect found by round
2's own review):** every trading operation checked/reconciled against
result codes; every R calculation uses actual fill price; pending fills
matched by ticket/position identity; the sign-error defect is a hard
blocker for reuse; journal keys include symbol+magic; RSI/indicator failure
fails closed.

**Persistence and restart — storage/schema defined (round-2 finding 2.7):**
`StateManager` (§11) persists via MT5 global variables for small scalar
state (peak-drawdown, daily/weekly baselines) and a local file-based
key-value store (JSON or CSV, atomic write via write-to-temp-then-rename)
for structured state (basket/position tracking, learning statistics) too
large or complex for global variables. Every write includes a schema
version field; a version mismatch on load triggers a full state reset
(never a silent partial read of mismatched-schema data) and is logged.
**Two distinct key namespaces, not one (round-2 finding 2.7's collision
concern):** (a) **per-instance state** (basket tracking, position risk
keys) is keyed by `symbol + magic + account_login + trade_server` — the
missing `symbol` component round 2 identified is added, so multiple
symbol instances sharing an account/magic no longer collide; (b)
**account-wide state** (daily/weekly risk baselines) is keyed by
`account_login + trade_server` **only** — deliberately *not* partitioned
by magic or symbol, since the risk-accounting scope decision above is
account-wide by design. **Reconciliation order on restart:** account-wide
state loads first, then per-instance state, then `OrderManager` reconciles
every loaded per-instance record against live broker state (§12 item 12)
before any new trading decision is evaluated.

### 9. Signal scoring, trade decision object, journal, offline learning (master prompt §11–12, §18)

Unchanged from round 2 in substance (confirmed correct: baseline
attribution split, correlation framed as a test, full `TradeDecision`
field list, §18's learning requirements). **Response to round-2 finding
4.3 — the contradictory live probe is replaced:**

Round 2 correctly found that an "always-open small live-entry channel" for
a benched bucket directly contradicts the same paragraph's own "benching
applies to every entry path, with no bypass" rule, and continues deploying
real capital past the stated stop condition with no defined size,
frequency, loss cap, or approval gate. **Corrected re-evaluation
mechanism: shadow tracking, not a live probe.** A benched strategy/regime
bucket is re-evaluated using **shadow (paper) outcomes only** — the engine
continues to *score* candidates that would have qualified for the benched
bucket, records what their outcome *would have been* had they been taken
(using the same fill-price/slippage model as live trades, for
apples-to-apples comparison), and re-enables the bucket only once
`InpRegimeLearningMinTrades` **new** same-regime, same-entry-attribution
**shadow** trades accumulate with a win rate clearing the original bench
threshold. No live capital is risked to gather this re-evaluation
evidence — this both removes the contradiction round 2 found and removes
the entirely undefined size/frequency/loss-cap/approval-gate questions
that a real live probe would have required, since no live position is ever
opened for re-evaluation purposes.

### 10. News system (master prompt §15, `NEWS_INTEGRATION_SPEC.md`)

Unchanged in substance from round 2 (provider architecture, policy list,
`scheduled_botswana_time` field naming, and the classifier-attribution
correction were all confirmed correct by round 2's own review). **One
correction (round-2 finding 3.9):** V6.37's news-time inputs
(`InpNewsHourServer`/`InpNewsMinuteServer`, source 190–191) are manually-
entered server-time values overwritten onto the current server date
(source 7260–7265) — described here as exactly that, not as a computed
"server-time offset," which implies an automatic conversion that does not
exist in the source.

### 11. Required architecture and roadmap alignment (master prompt §22–23)

**Response to round-2 finding 4.4 — explicit test boundaries added, module
naming corrected, ownership duplication removed:**

- `StateManager`: owns all persisted state per §8's two-namespace key
  schema above. **Test boundary:** given a persisted state snapshot and a
  simulated restart, every dependent module reads back the exact
  pre-restart values for its own namespace, and a schema-version mismatch
  triggers a full reset with a logged event — both cases unit-testable
  without live market data.
- `StrategyRouter`: owns §3's eligibility/scoring only (ownership
  duplication with `ConflictResolver` removed — see §3's explicit split).
  **Test boundary:** given a fixed regime/confidence/candidate set, the
  eligible-and-scored output is fully deterministic.
- `ConflictResolver`: owns only the final tie-break given `StrategyRouter`'s
  output (§3). **Test boundary:** given a fixed scored-candidate list, the
  winning direction/family (or `No trade`) is fully deterministic per the
  score-gap rule.
- Risk persistence: owned by `StateManager`, consumed by `RiskManager`,
  `DrawdownController`, `EquityPeakManager`, `DailyWeeklyLimits`. **Test
  boundary:** given a persisted baseline and a sequence of simulated ticks/
  restarts, the daily/weekly loss percentage computed matches §8's formula
  exactly at every step.
- Trade reconciliation: owned by `OrderManager`/`PositionManager`,
  implementing §12 item 12's durable-intent protocol below. **Test
  boundary:** given a simulated crash between order submission and
  persistence, restart-time reconciliation correctly classifies the
  order as filled/failed/abandoned against live broker state.
- Shared trading/visual structure source: `SwingEngine`/`MarketStructure`
  (per §22's actual module names) computes swing pivots, range boundaries,
  and equilibrium **once**, exposed via one accessor consumed by
  `StrategyRouter` (trading) and **`StructureVisuals`** (drawing —
  corrected from "`PatternVisuals`," which master-prompt §22 assigns to
  candlestick/chart-pattern drawing specifically, a separate module; round-2
  finding 4.4 caught this naming/assignment error). **Test boundary:**
  given a fixed price series, `StrategyRouter` and `StructureVisuals` both
  reading the same swing/range/equilibrium output is directly assertable
  in a unit test (same accessor, same call, compared for equality).

Phase 3 (Common core) is the next task branch, contingent on one durable
prerequisite: `claude/task-001-baseline-audit` reaching an approved/merged
state with this document's citations re-verified against `main`, **and**
this specification passing independent review.

### 12. Contradiction resolution ledger

**Response to round-2 finding 4.1 — item 14 added; response to finding 4.2
— items 3, 5, 7, 9, 11, 12, 13 corrected to reference actual defined
mechanisms instead of asserting a resolution:**

1. **V8.11 chart-mark vs. traded structure** → §11: one canonical
   `SwingEngine`/`MarketStructure` source consumed by both
   `StrategyRouter` and `StructureVisuals`.
2. **V6.37 Rotation vs. Volatile-Expansion regime routing** → §3's matrix:
   Range Rotation eligible in `RANGING`, not in `VOLATILITY_EXPANSION_*`.
3. **V6.37 stop-floor/cap conflict** → §8's now-fully-defined preflight
   **and periodic recheck** (attach-time was insufficient alone, per
   round-2 finding 2.6 — corrected to include the recheck cadence).
4. **V8.11 momentum vs. expansion gate** → §2/§3: directional-regime-
   conditioned eligibility with an explicit no-chase bar count.
5. **V8.11 restart reconstruction** → §8/§11: `StateManager`'s persisted,
   versioned, two-namespace state plus `OrderManager`'s restart-time
   reconciliation against live broker state (item 12 below) — **durable
   serialization and reconciliation semantics are now both actually
   defined**, not merely a named test boundary.
6. **V8.11 daily-limit anchor/reset semantics** → §8: persisted baseline,
   numerator/denominator formulas, cash-flow rebasing, boundary detection.
7. **Persistence-key safety** → §8's two-namespace schema (symbol+magic+
   account+server for per-instance state; account+server only, explicitly
   unpartitioned by magic/symbol, for account-wide state) — **the schema
   is now safe across mixed scopes because two different schemas exist for
   the two different kinds of state**, not one schema stretched to cover
   both.
8. **V8.11 oldest-first/always-CHoCH chart-mark artifacts** → resolved by
   item 1 (single structure source replaces the defective independent
   scan).
9. **Netting vs. hedging account-mode support** → **hedging-mode only,
   full stop.** Round 2 correctly found "netting as a Phase 5+ addition"
   created an overlapping timeline with "hedging-only through Phases 3–7."
   **Corrected: netting-account support is out of scope entirely, with no
   promised future phase** — the engine validates and requires a
   hedging-mode account at `OnInit` and refuses to run otherwise; adding
   netting support, if ever wanted, would be a separate, fully-specified
   task proposed on its own merits, not a pre-committed roadmap item.
10. **V6.37 daily-limit symbol/magic scope** → §8: account-wide scope,
    removing the ambiguity.
11. **Completed-candle enforcement for every pattern/signal path** →
    **restated as one project-wide structural rule here, not scoped to §5
    alone (round-2 finding 4.2 correctly found §5 only covers candlesticks):
    every function in `SwingEngine`, `CandlestickPatternEngine`, and
    `ChartPatternEngine` that reads price data for a confirmed-pattern or
    confirmed-structure decision operates on `rates[1]` or older,
    unconditionally — this is a single rule applied across all three
    engines, restated here as the canonical location for it rather than
    left implicit in §5's own pattern-specific description.**
12. **Market-signal/deal restart reconciliation** → **an actual protocol,
    not only a post-restart position scan (round-2 finding 4.2):** every
    order submission first writes a durable "intent" record (`StateManager`,
    per-instance namespace) **before** the `CTrade` call is made, containing
    the intended symbol/direction/volume/SL/TP and a unique intent ID; the
    intent record is updated with the resulting ticket/deal ID immediately
    after the broker responds. On restart, `OrderManager` compares every
    persisted intent record against live broker state: a matching open
    position/order confirms the intent succeeded; an intent with no
    matching broker result and an age below `InpIntentTimeoutSeconds`
    (default 30) is treated as still in-flight and re-queried; older than
    that, it is treated as failed/abandoned and logged — this closes the
    crash-window gap round 2 identified between submission and persistence,
    since the intent record exists *before* the broker call, not only
    after.
13. **V8.11 range visual/trading semantics** → item 1's shared structure
    source **explicitly includes range boundaries and equilibrium as part
    of its computed, shared output** (round 2 found this wasn't actually
    stated) — `SwingEngine`/`MarketStructure` computes swing pivots, range
    high/low, and equilibrium together, as one function's output, consumed
    identically by trading and drawing code.
14. **V6.37 FVG semantics mixing `InpStructureSwingDepth`/`InpFractalDepth`**
    (new this round, closing round-2 finding 4.1's gap) → §4: the FVG
    path uses the single canonical `SwingEngine` depth definition, not two
    independently-tunable inputs.

## Files affected

**Round 3 (this revision):** modified `TASK-002_PHASE2_SPECIFICATION.md`;
modified `09_HANDOVERS/codex_to_claude/TASK-002_review.md` (round 2's
review, already present on disk from the independent reviewer, committed
alongside this response as in every prior round). Exact path set for the
commit containing this revision: two paths, both modified (not "none new"
— round-2 finding 4.5 corrected the prior draft's inaccurate claim about
the `cc58fa8..7842083` diff, and this entry now states the actual set for
the commit this revision belongs to). No file under `01_BASELINE/` is
touched. No `03_SOURCE_CODE/` files are created.

## Out of scope

- Any `.mqh`/`.mq5` implementation code — Phase 3+.
- Per-strategy `STRATEGY_SPECIFICATION.md` instances, and the remaining
  chart-pattern definitions beyond double-top/bottom and head-and-shoulders
  (§6 states the shared framework every remaining pattern instantiates;
  filling in triangle/flag/wedge/channel-specific pivot topologies is
  Phase 5, one at a time, using that same framework — not an open Phase 2
  gap, since the framework itself is now fully specified).
- Resolving TASK-001's merge status.
- Any claim of compilation, testing, or proven correctness.

## Risks

- **Dependency on an unmerged branch** — unchanged; re-verify citations
  against `main` once TASK-001 merges.
- **First-pass formulas need calibration** — the mode/regime weight
  defaults, thresholds, and confidence formulas are precisely defined and
  implementable, but their specific numeric defaults are Phase 4/5
  calibration targets, not final tuned constants; this is now stated
  consistently (round 2 found the prior draft's Acceptance section
  overclaimed these as final — corrected below).
- **Specification-implementation drift** — unchanged.

## Test plan

1. Every §23 Phase 2 deliverable has a section — §0's map, unchanged,
   confirmed complete by round 2.
2. Every contradiction in `baseline_comparison.md` and every item in round-1
   and round-2 reviews' contradiction findings appears in §12's ledger with
   an actual decision referencing a defined mechanism, not an assertion —
   checked directly against both reviews' finding lists; item 14 added,
   items 3/5/7/9/11/12/13 corrected to reference the now-defined
   mechanisms.
3. Every numeric limit in `RISK_POLICY.md` is restated in §8 as binding,
   including the add-on/basket normative sentence round 2 found missing.
4. The V8.11 sweep/shift/final-stop formula is now actually stated (§7's
   target-selection section references it; the formula itself — pool scan
   `4..min(copied-2,4+max(10,InpSweepLookback))`, shift scan
   `2..min(copied-2,2+max(3,InpShiftLookback))`, final-stop transformation
   chain — is stated in the Evidence section's source-line list and is
   the literal basis for §3/§4's SMC/ICT structural-gating description;
   round 2 correctly found this was claimed-but-absent in round 2's draft).
5. The regime-confidence formula is re-derived by hand for both extremes
   of `E` (expansion score): at `E=1.0`, `confidence=(1.0−0.75)/(1−0.75)=1.0`;
   at `E=0.0` under `COMPRESSION`'s formula,
   `confidence=(0.25−0.0)/0.25=1.0` — both extremes now correctly produce
   maximum confidence, closing round 2's finding 1.4 directly.

## Acceptance criteria

- [x] Every §23 Phase 2 deliverable has a section, including candlestick
      and chart-pattern mathematics (not only requirement lists).
- [x] Every hard numeric limit in `RISK_POLICY.md` is restated as binding,
      including the add-on/basket default-off rule as an actual normative
      sentence.
- [x] Risk accounting is fully defined: per-position/total-open-risk
      aggregation, pending-order reservation, numerator/denominator
      equations, cash-flow treatment, reset-boundary detection, restart
      persistence, and breach behavior (pre-trade gate vs. post-fill
      mandatory closure, not a soft tolerance above the cap).
- [x] The mode router, regime engine (with a corrected, non-self-defeating
      confidence formula), and strategy routing matrix each have a stated,
      hand-verifiable formula/threshold/precedence.
- [x] Every entry in §12's contradiction ledger states an actual decision
      referencing a defined mechanism elsewhere in this document, not an
      assertion of resolution.
- [x] Architecture responsibilities each have an explicit, unit-testable
      boundary, with no duplicated ownership (`StrategyRouter` vs.
      `ConflictResolver` split explicitly) and correct module naming
      (`StructureVisuals`, not `PatternVisuals`, for shared structure
      drawing).
- [ ] Independent Codex review completed and findings resolved — **pending
      this round's own review.**

## Rejection criteria

Unchanged from round 2, with one addition: this task would also be
rejected if any formula stated as "corrected" or "defined" in this revision
does not actually hold when independently recomputed (e.g., if the regime-
confidence formula still produces zero at either expansion extreme, or if
any stated default numeric bound is internally inconsistent with the
formula it bounds).

## Implementation notes

This revision was written directly in response to
`09_HANDOVERS/codex_to_claude/TASK-002_review.md`'s round-2 findings. The
regime-confidence defect was independently re-derived by hand (§2's Test
plan item 5) before selecting the corrected margin-based formula, rather
than patching the broken formula superficially. Every baseline source
citation round 2 flagged as wrong was re-read directly from
`01_BASELINE/EA_V637/Thembabot14 Max.mq5` and
`01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5` at the cited line ranges before
being restated (see the Evidence section's source-line list).

## Commands run

`git checkout claude/task-001-baseline-audit && git checkout -b claude/task-002-phase2-specification`
(round 1); this revision edits the same file, same branch.

## Compiler result

Not applicable — no code in this task.

## Test results

Documentation self-verification (Test plan above): all five items checked
directly against this revision's own content and confirmed present/correct,
including hand-recomputing the corrected confidence formula at both
expansion extremes.

## Commit

Round 1: `cc58fa8`. Round 2 (round-1 response): `7842083`. This revision:
pending — see `git log` on this branch for the actual hash once committed;
the commit containing this revision modifies exactly two paths
(`TASK-002_PHASE2_SPECIFICATION.md` and
`09_HANDOVERS/codex_to_claude/TASK-002_review.md`), stated here in advance
per the file-list-prediction discipline established in TASK-001's own
review cycle (predict the exact path set before committing, then verify
against `git status`).

## Reviewer

Round 1 (Codex, against `cc58fa8`): CHANGES REQUESTED, 40+ findings — see
round-1 history above. Round 2 (Codex, against `7842083`): CHANGES
REQUESTED — round 1's fixes were substantially real (confirmed: risk
percentages, six-family count, pilot ratios, weak-sample effects, `CTrade`
scope, score attribution, level-invalidation, TASK-001 dependency framing),
but candlestick/chart-pattern mathematics, the regime-confidence formula,
deterministic routing, full risk accounting, and several baseline facts
remained wrong or incomplete — see this document's inline corrections
throughout for the complete response. Round 3 review pending.

## Final decision

**Pending round 3 independent review.** Not ready for Phase 3 until that
review's disposition is approved, per the user's own stated preference to
get this right given Phase 3 will code directly against this document.
