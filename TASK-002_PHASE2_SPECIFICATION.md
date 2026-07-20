# TASK-002 — Phase 2: Specification for the Combined Adaptive Intraday Engine

**Revision history:** round 1 (`cc58fa8` → CHANGES REQUESTED, 40+ findings —
missing candlestick/chart-pattern formalization, no executable
mode/regime/routing rules, undefined risk accounting, ~13 unresolved
contradictions, several baseline mischaracterizations). Round 2 (`7842083`
→ CHANGES REQUESTED — round 1's fixes were largely real, but this remained
a requirements list wearing a specification's clothes: no candlestick/chart-
pattern mathematics, a mathematically broken regime-confidence formula,
non-deterministic routing, contradictory risk accounting, an incomplete
ledger). Round 3 (`bf84f4d` → CHANGES REQUESTED — the confidence-formula
extremes were genuinely fixed and all seven re-requested baseline citations
passed source re-verification, but that revision **deleted real Phase-2
content** (the score-component list, `TradeDecision` schema, five-way
learning buckets, and the news provider architecture) while labeling the
result "unchanged," introduced a circular mode-router dependency, left the
per-position risk formula dimensionally wrong (missing division by tick
size), left the daily/weekly loss formulas measuring absolute floating P/L
instead of the change since the period boundary, and left several state
machines/formulas incomplete or self-contradictory — sixteen numbered
findings in total).

**This is round 4.** Codex's independent-review budget for this task is
exhausted after round 3 — there will be no round 5 external check. Every
one of round 3's sixteen findings is addressed below on its own technical
merits (not merely to satisfy a reviewer that no longer exists): all
deleted content is restored and expanded, the mode router's circularity is
removed by restructuring the evaluation pipeline, the risk-cash formula is
corrected, the loss formulas are rewritten to measure actual period change,
short-side exit formulas are added, the chart-pattern scope is narrowed to
what is actually formalized here (with routing restricted to match, instead
of routing referencing undefined patterns), and every remaining vague
predicate is replaced with a stated equation, input name, and default.
Because no further independent check will occur, §16 states plainly which
items are hand-verified-but-unreviewed versus deliberately deferred to a
later phase, rather than repeating round 3's mistake of claiming a status
the document does not support.

## Objective

Produce the Phase 2 specification required by `00_MASTER_PROMPT_FOR_CLAUDE.md`
section 23 before any Phase 3+ code is written: formalize intraday modes,
regimes, strategies, candlestick patterns, chart patterns, risk, and news,
and resolve every contradiction between SmartCoreEngine V6.37 and NdlovuSMC
V8.11 with an actual, implementable decision.

## Reason

Per `CLAUDE.md`'s workflow, no architecture or implementation work may begin
until a specification resolves what the new engine actually does. Phase 3
will write `.mqh` code directly against this document with no further
independent review pass available, so an unresolved formula or an
underspecified state machine here becomes a real, unreviewed bug there.
This revision treats "specified" as meaning: every threshold has an input
name, a bound, and a default; every state machine's transitions are
exhaustive; every formula has been hand-recomputed at its boundary values.

## Baseline behaviour

See `baseline_v637_audit.md`, `baseline_v811_audit.md`, and
`baseline_comparison.md` on this branch (inherited from
`claude/task-001-baseline-audit`, commit `2005d75`; still unmerged,
disposition changes-requested as of its own fourteenth review — this
specification depends on that branch's content without claiming it is
finished).

Corrected summary:

- **V6.37:** a pilot-trade risk ceiling of **6.25×/25×/8.33×/33.33×** of the
  EA's implemented budget depending on symbol profile and setup (Rotation
  vs. ordinary) — conditional ratios, not global bounds. A confirmed sign
  error in the learning-penalty formula (base branch: `+2.8%` at 60% win
  rate with net loss; regime branch: `+4.0%`). Journal cross-magic learning
  contamination. Pending-order fill misattribution by direction only.
  Requested-vs-actual-fill price mixing in R/management math. An intrabar
  read in two candlestick helpers. Pervasive unchecked `CTrade` result
  codes on every trading operation. A weak-sample adaptation with four
  distinct, not-uniformly-directional effects. **`IsSelfConfirmedSetup` has
  an explicit, named setup-list scope (source 7534–7540) and does not
  escape regime routing — `ApplyRegimeRouting` (source 7464–7528) still
  runs and can veto it; `SelectBestIndependentSignal` calls
  `ApplyRegimeRouting` at source 919–924.** `BuildThreePointTrendLine`
  constructs its line through only the oldest and newest of three monotonic
  swing points, never testing the middle swing's own distance from that
  line; `EvaluateTrendBreaker` then projects a single constant value rather
  than re-projecting per confirmation bar. **Two live, non-identical
  structural-break classifiers exist (`AnalyzeStructure`,
  `FindRecentStructureShiftLevel`) — `BuildBOSRetestSignal` (source
  7760–7788) is a caller that combines both, not a third definition;
  `HasEntryCHOCH` (source 5013–5025) is a third definition but has no call
  site (dead code).** Effective giveback arm is `max(0.25, InpGivebackArmRR)`
  (default 1.25R), percentage clamped 10–90% (default 60%), and the
  giveback close condition itself is floored at `0.05R`. Timeframe **roles**
  are configurable (`InpStructureTF`, `InpEntryTF` — which ships as **M3**,
  not M5 — two higher-TF inputs, `InpTrendExecutionTF`, and further
  role-specific TFs); M15/M5 language elsewhere in this document is
  shipped-default shorthand only. The `InpNewsHourServer`/
  `InpNewsMinuteServer` inputs (source 190–191) are manually-entered
  broker-server HH:MM values overwritten onto the current server date
  (source 7260–7265) — there is no offset conversion.
- **V8.11:** basket-specific dynamic risk management lost across a restart
  — broker-held SL/TP and the daily-lock close path survive. A configurable
  time exit (`InpMaxHoldMinutes`, disabled when ≤0) defaulting to 45
  minutes. A minimum-lot fallback reaching at least 2.5× its modeled budget
  at shipped defaults. A daily-limit numerator/denominator anchor mismatch
  across restarts — **and only a daily reset exists (`ResetDailyState`,
  source 1529–1564); there is no separate weekly baseline in V8.11 at
  all.** A persisted peak-drawdown key that truncates a `long` magic
  number, with no account/server identifier. Chart marks that retain the
  oldest structural breaks and always mislabel the first stored mark CHoCH.
  The same unchecked-`CTrade`-result pattern as V6.37. **The four-rung
  target ladder (`InpTP1R`…`InpTP4R`) is configurable (source 75–78), not
  fixed; shipped leg inputs request two legs (source 72–74); sizing can
  reduce legs (source 1328–1347); rungs are floored/monotonic (source
  1363–1366); submissions may partially fail (source 1368–1380) — the
  two-live-rung outcome depends on all of these shipped/runtime
  conditions, it is not an unconditional behavior of a "fixed" ladder.**
  V8.11 has **no outcome-learning system at all** (confirmed: no
  outcome/journal-feedback code path exists in source); its confluence
  scoring is itself inconsistent — some addition paths cap at 100 (source
  929, 943) while several builder bonus paths do not (source 1090–1120,
  1164, 1205, 2257–2278).
- **Both:** `IsSyntheticIndexSymbol` and `DirectionAllowedForSymbol` are
  both V6.37 functions; V8.11's analogous, separate function is
  `DirectionAllowed` (source 1616–1628). No economic calendar in either
  EA. RSI-fallback patterns that silently satisfy downstream thresholds
  instead of invalidating the read. Configurable timeframe roles in both
  EAs, not a single fixed timeframe in either.

## Evidence

- `baseline_v637_audit.md`, `baseline_v811_audit.md`,
  `baseline_comparison.md` — full defect list, cited to source line numbers.
- `00_MASTER_PROMPT_FOR_CLAUDE.md` sections 5–15, 18, 22–23.
- `RISK_POLICY.md`, `NEWS_INTEGRATION_SPEC.md`, `STRATEGY_SPECIFICATION.md`.
- `01_BASELINE/EA_V637/Thembabot14 Max.mq5`,
  `01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5` — re-read directly at every
  source line cited in round 3's review, including 1008–1050 (sweep/shift
  pool and shift index ranges), 1292–1310 (final-stop transformation),
  919–924/7464–7528/7534–7540 (`IsSelfConfirmedSetup` scope and veto path),
  5013–5025/7760–7788 (structural-classifier call sites), 190–191/
  7260–7265 (news-time inputs), 75–78/72–74/1328–1380/1363–1366 (target
  ladder), 1529–1564 (daily-only reset), 929/943/1090–1120/1164/1205/
  2257–2278 (confluence-cap inconsistency).

## Data conventions (applies to every formula in this document)

**Logical bar indexing:** logical index `0` denotes the most recently
**completed** bar (MQL series index `1`); logical index `k` denotes `k`
bars before that (MQL series index `k+1`). No formula anywhere in this
document reads MQL series index `0` (the currently forming bar) — every
`[k]` written below is a logical index under this convention, resolving
round 3's finding that the candlestick section used raw `[0]` while
claiming completed-candle-only reads. `open[k]`, `high[k]`, `low[k]`,
`close[k]` refer to that logical bar's OHLC.

**Percentile ties:** any percentile-rank computation in this document uses
average rank for tied values (the standard mid-rank convention), stated
once here rather than repeated per formula.

**Threshold bounds:** every configurable threshold introduced below that
appears as a divisor, or that gates a regime/state transition, is
range-clamped at `OnInit` to a stated safe interval that excludes values
producing division by zero or a degenerate always-true/always-false
predicate; the specific interval is given next to each such input.

## Specification

### 0. Phase 2 deliverable map

| # | §23 deliverable | Addressed in |
|---|---|---|
| 1 | Intraday modes | §1 |
| 2 | Regimes | §2 |
| 3 | Strategies | §3 |
| 4 | ICT/SMC | §4 |
| 5 | Candlestick patterns | §5 |
| 6 | Chart patterns | §6 |
| 7 | Exit engine | §7 |
| 8 | Risk | §8 |
| 9 | Signal scoring / TradeDecision / journal / learning | §9 |
| 10 | News | §10 |
| 11 | Architecture | §11 |
| 12 | Resolve contradictions before coding | §12 |

### 1. Intraday modes (master prompt §5)

Two modes: **Scalp** (M1–M5 entry, M15–H1 context) and **Day-trade** (M5–M15
entry, M30–H4 context).

**Pipeline ordering (fixes round-3 finding 3's circularity):** the round-3
draft's mode score used components that required a scored trade candidate
(distance-to-target, pattern quality, expected R, sample-gated historical
performance) before a mode had been selected, while §3's routing then used
the selected mode to decide which candidates to generate — a genuine
cycle. The pipeline is restructured into three ordered stages that break
the cycle:

1. **Regime engine (§2) runs first**, on a **fixed, mode-independent
   timeframe** (`InpRegimeTF`, default M15 — not the entry timeframe of
   whichever mode might later be chosen). This removes the mode dependency
   from regime classification entirely.
2. **Mode engine runs second**, using **only** regime-derived and
   price/session-derived components that do not require a specific trade
   candidate (four components, below) — no candidate-quality input is a
   mode-score component.
3. **Strategy routing (§3) runs third**, against the now-fixed mode and
   regime, generating and scoring eligible candidates.
4. A lightweight **post-hoc mode-consistency check** runs on the winning
   candidate only (after `ConflictResolver`, §3): if the candidate's own
   expected-R or distance-to-target is incompatible with the selected mode
   (Day-trade candidate with expected R `< InpMinDayTradeR`, default `1.0`;
   or Scalp candidate with expected R `> InpMaxScalpR`, default `2.0`), the
   candidate is rejected and the bar resolves to no-trade — this is where
   candidate quality interacts with mode, deliberately kept out of the mode
   score itself.

**Mode-score components (four, down from ten — components requiring a
candidate are removed per the pipeline fix above; the spread-to-ATR and
news-proximity components are removed for the separate reasons below):**

Each is normalized to `[0,1]` where `1.0` favors Day-trade and `0.0` favors
Scalp:

1. **Regime persistence** = `min(1, trend_age_bars / InpModePersistenceBars)`
   (default window 20 bars) if the active directional regime (§2) is
   `TRENDING_UP/DOWN`; `0.3` for `RANGING`; `0.0` for any other regime.
2. **ATR percentile** = the `InpRegimeTF` ATR's percentile rank over the
   trailing `InpATRPercentileWindow` (default 100) bars.
3. **Range-vs-average** = `min(1, current_range_ATR_multiple / 2.0)` where
   `current_range_ATR_multiple` is today's session range so far divided by
   the `InpRegimeTF` ATR.
4. **Session time remaining** = `clamp01(remaining_session_minutes /
   total_session_minutes)`; if `total_session_minutes` is undefined for the
   symbol (no session calendar), this component is excluded from the
   weighted average (not defaulted). Below `InpMinDayTradeSessionMinutes`
   (default 90) remaining minutes, this component is clamped to `0.0`.

**Removed components and why (round-3 findings addressed directly):**
- *Spread-to-ATR* is removed from the mode score entirely. Round 2 mapped
  it backwards; round 3's attempted fix (a low fixed weight) still biased
  the score because `1=Day-trade/0=Scalp` and a tight spread mapped to
  `1`. A spread-to-ATR value carries no real information about which mode
  is *appropriate* — it is a trade-worthiness gate, not a mode preference.
  It is specified once, in §9's trade-worthiness score, and nowhere else.
- *News proximity* is removed. Since a `NEWS_BLACKOUT` regime read already
  overrides mode selection before the mode formula runs at all (below),
  this component was always `1.0` whenever it was actually evaluated — a
  constant, not real signal. Deleting it removes dead weight without
  losing any behavior (the actual news effect is fully handled by the
  gating override).
- *Distance to target, pattern quality, expected R, sample-gated historical
  performance* are removed per the pipeline restructuring above (stage 4's
  post-hoc check and §9's own scoring absorb this role without creating a
  cycle).

**Aggregation:** `mode_score = Σ(weight_i × component_i) / Σ(weight_i)`
over only the components actually available this evaluation; weights
default to `0.25` each (four components), configurable, each bounded to
`[0, 1]`. If all four components are unavailable, or if the sum of
available weights is `0`, `mode_score` is undefined and the router outputs
no mode (fail-closed).

**Thresholds, precedence, and gating (unchanged core logic, restated
precisely — resolves round 3's neutral-band self-contradiction):**
`mode_score ≥ 0.60` → Day-trade; `mode_score ≤ 0.40` → Scalp;
`0.40 < mode_score < 0.60` → neutral band. **Neutral-band rule (single,
non-contradictory statement):** while in the neutral band, the
previously-selected mode for that symbol persists if one was already
active; a symbol with no prior selection remains in no-mode/no-trade until
the score clears one of the two decision thresholds. A `NEWS_BLACKOUT` or
`UNTRADEABLE_SPREAD_OR_LIQUIDITY` regime read (§2) is evaluated **before**
the mode formula runs at all and forces no-mode/no-trade unconditionally.

**Hysteresis and failure severity (resolves round 3's missing-data/
hysteresis conflict):** mode switches (and the initial selection) require
the new mode's threshold to hold for two consecutive closed **M1** bars (a
fixed confirmation timeframe, independent of which mode is being
evaluated). Two distinct severities are now defined, resolving the
apparent conflict: **partial degradation** (a component's normal
computation window is short of its ideal length, e.g., fewer than
`InpATRPercentileWindow` bars of history but at least half that many) —
the component is computed on the degraded window and included normally,
not excluded; **hard failure** (an indicator handle is invalid, or fewer
than half the ideal window is available) — that component is excluded from
the weighted average; if this leaves fewer than two of the four components
available, `mode_score` is undefined and hysteresis is bypassed
immediately (no mode, fail-closed, matching §2's own indicator-failure
rule).

**Mode-specific rules (unchanged):** Scalp caps attempts per session
(`InpMaxScalpAttemptsPerSession`) and rejects a repeat entry at an
unchanged level within the session. Day-trade closes all of this EA's own
exposure before the intraday boundary (§8). Every mode decision, its
score, and each available component's contribution are written to the
`TradeDecision` object (§9).

### 2. Regime engine (master prompt §6)

Nine regimes, unchanged: `TRENDING_UP`, `TRENDING_DOWN`, `RANGING`,
`VOLATILITY_EXPANSION_UP`, `VOLATILITY_EXPANSION_DOWN`, `COMPRESSION`,
`TRANSITION_OR_UNCERTAIN`, `NEWS_BLACKOUT`,
`UNTRADEABLE_SPREAD_OR_LIQUIDITY`. Computed on a **fixed timeframe**
(`InpRegimeTF`, default M15 — independent of §1's mode, per §1's
circularity fix), using logical-index bars only (data conventions above).

**Gating regimes — predicates defined (resolves round 3's finding that
`UNTRADEABLE_SPREAD_OR_LIQUIDITY` was undefined):**
`NEWS_BLACKOUT` = an active blackout window from §10. **
`UNTRADEABLE_SPREAD_OR_LIQUIDITY`** = `current_spread > ATR ×
InpMaxSpreadATRMultiple` (default `0.15`, bounded `[0.02, 1.0]`) **OR**
trailing-`InpLiquidityTickWindow`-bar (default 20) average tick count per
bar `< InpMinLiquidityTicksPerBar` (default 5, symbol-specific — set to
`0`/disabled for symbols where the broker does not report tick-volume
meaningfully). Either condition alone is sufficient. Both gating regimes
are evaluated first, independently of everything below, and **bypass
hysteresis** — they take effect the instant the predicate is true.

**Directional/volatility component formulas:**

- **Trend strength `T`** = `clamp01(0.5 × swing_agreement + 0.5 ×
  ema_slope_norm)`. `swing_agreement = 1.0` if the last
  `InpRegimeSwingLookback` (default 3) confirmed swings (§11's
  `SwingEngine`) all agree directionally, else `0.0`.
  `ema_slope_norm = clamp01(|ema[0] − ema[InpEMASlopeBars]| /
  (ATR × InpTrendSlopeATRDivisor))` (`InpEMASlopeBars` default 5,
  `InpTrendSlopeATRDivisor` default `0.5`, bounded `[0.05, 5.0]`), where
  `ema[k]` is `InpRegimeEMAPeriod`-period (default 21) EMA value at
  logical index `k`; the slope's sign (positive/negative) is taken from
  `ema[0] − ema[InpEMASlopeBars]` directly and determines the `_UP`/`_DOWN`
  direction wherever `T` selects a directional state.
- **`T_final` = `T × clamp01(0.5 + ADX(InpADXPeriod=14)/100)`.**
  **`T_final` is the only trend-strength value used anywhere below** — in
  state selection and in confidence — closing round 3's finding that state
  selection compared raw `T` against the threshold while defining
  `T_final` and never using it.
- **Expansion/compression evidence `E`** = ATR percentile (same
  computation as §1 item 2, same `InpRegimeTF`). `InpExpansionThreshold`
  default `0.75` (bounded `[0.55, 0.95]`); `InpCompressionThreshold`
  default `0.25` (bounded `[0.05, 0.45]`).
- **Efficiency ratio `ER`** = `|close[0] − close[N]| / Σ_{i=1..N}|close[i]
  − close[i-1]|` over `N = InpEfficiencyWindow` (default 20) logical bars.
  **Zero-denominator rule:** if the sum is `0` (all `N+1` closes
  identical), `ER` is treated as failing the efficiency gate below
  (equivalent to `ER < InpMinEfficiency`), not as undefined. `InpMinEfficiency`
  default `0.3`, bounded `[0.05, 0.6]`.

**State selection (deterministic, strict priority order, no fallthrough —
resolves round 3's "skip to step 4" ambiguity and the expansion/agreement
gap):**

1. Gating regimes (above) — if either predicate is true, select that
   regime and stop; hysteresis bypassed.
2. Indicator/data failure — if any of `T_final`, `E`, or `ER` cannot be
   computed (insufficient bars for even a degraded read, or an invalid
   indicator handle), select `TRANSITION_OR_UNCERTAIN`, confidence `0`,
   and stop; hysteresis bypassed.
3. If `ER < InpMinEfficiency`: select `RANGING` and **stop** (this is a
   terminal decision for this bar, not a step that can be overwritten by a
   later step — resolves round 3's "skip to step 4" ambiguity directly).
4. Else if `E > InpExpansionThreshold`: check directional agreement —
   `agree = true` iff the EMA-slope sign and the swing-sequence direction
   (from `swing_agreement`'s own directional read) match. **`T_final` is
   not required to clear its own threshold for this branch** (this removes
   round 3's finding-2 gap, where strong expansion evidence with agreement
   but sub-threshold `T_final` fell through to `RANGING`): if `agree`,
   select `VOLATILITY_EXPANSION_UP/DOWN` per that direction and stop; if
   not `agree`, select `TRANSITION_OR_UNCERTAIN` and stop.
5. Else if `T_final ≥ InpTrendThreshold` (default `0.6`, bounded
   `[0.3, 0.9]`) with a consistent EMA-slope/swing direction: select
   `TRENDING_UP/DOWN` per that direction and stop.
6. Else if `E < InpCompressionThreshold`: select `COMPRESSION` and stop.
7. Else: select `RANGING`.

**Confidence formulas (margin-against-own-threshold, corrected in round 3
for the two extremes and now fixed for the remaining branches):**

- `TRENDING_UP/DOWN`: `confidence = clamp01((T_final −
  InpTrendThreshold) / (1 − InpTrendThreshold))`.
- `VOLATILITY_EXPANSION_UP/DOWN`: `confidence = clamp01((E −
  InpExpansionThreshold) / (1 − InpExpansionThreshold))` — **note this
  state is only reachable with `agree = true` per step 4; it does not
  additionally weight `T_final`,** since expansion classification no
  longer depends on `T_final` clearing its own threshold (step 4's fix
  above) — the confidence formula matches the state-selection formula's
  actual inputs by construction, closing round 3's finding that confidence
  ignored the trend margin inconsistently.
- `COMPRESSION`: `confidence = clamp01((InpCompressionThreshold − E) /
  InpCompressionThreshold)`.
- `RANGING`: **corrected formula** (round 3 found the prior "hump" shape
  perverse and the `min(·,ER)` capping unspecified): `confidence =
  clamp01(1 − T_final / InpTrendThreshold)` — monotonically highest
  (`1.0`) at `T_final = 0` and `0` at `T_final = InpTrendThreshold`, a
  single defined operator, no ER-capping term. This applies uniformly
  whether `RANGING` was selected via step 3 (low `ER`) or step 7
  (fallback) — the confidence value is intentionally lower for a fallback
  `RANGING` read with borderline `T_final` than for a clean, low-`T_final`
  range, which is the correct relative ordering.
- `TRANSITION_OR_UNCERTAIN`: confidence is always `0`.

**Low-confidence override:** confidence `< 0.5` forces
`TRANSITION_OR_UNCERTAIN` treatment for routing purposes (§3) regardless of
the nominally-selected state — an explicit design decision: this creates
effective secondary thresholds (`T_final ≥ 0.8` for trend routing
confidence, `E ≥ 0.875`/`E ≤ 0.125` for expansion/compression routing
confidence), stated here as intentional rather than an incidental
consequence.

**Hysteresis:** two consecutive closed `InpRegimeTF` bars required for any
transition between non-gating states; gating regimes and step-2 failures
bypass hysteresis immediately, as stated above.

**Required deliverables (unchanged):** `MarketRegimeEngine.mqh`; the
`MarketRegime` enum; confidence score and reason string per read; a
transition-history buffer; Python unit-test fixtures covering all nine
states plus the gating-override and indicator-failure cases (including the
zero-`ER`-denominator case and both threshold-clamp boundaries); a
confusion matrix against `01_BASELINE/screenshots/`-labeled examples.

### 3. Strategy routing (master prompt §7)

Six canonical families: SR Bounce/Range Rotation, SMC/ICT Price-Action,
Trend Following, Chart-Pattern Breakout/Reversal, Post-Expansion Retest,
No trade.

**Concrete context/entry timeframes per family × mode (resolves round 3's
"ranges are not a rule" finding — one specific pair per cell, not a range):**

| Family | Mode | Context TF | Entry TF |
|---|---|---|---|
| SR Bounce / Range Rotation | Day-trade | M30 | M15 |
| SR Bounce / Range Rotation | Scalp | M15 | M5 |
| SMC/ICT Price-Action | Day-trade | H1 | M5 |
| SMC/ICT Price-Action | Scalp | M15 | M1 |
| Trend Following | Day-trade | H4 | M15 |
| Trend Following | Scalp (momentum-continuation only) | H1 | M5 |
| Chart-Pattern Breakout/Reversal | Day-trade | H4 | M15 |
| Chart-Pattern Breakout/Reversal | Scalp | not eligible (width-based rule, §6) | — |
| Post-Expansion Retest | Day-trade | H1 | M5 |
| Post-Expansion Retest | Scalp | M15 | M1 |

**Eligibility and score-multiplier semantics:** "prefer" = eligible,
`eligibility_multiplier = 1.10`. "block" = not eligible — the family's
candidates are not generated this bar. "penalize" =
`eligibility_multiplier = 0.80`; "heavily penalize" =
`eligibility_multiplier = 0.50`. All four multiplier values are
configurable inputs, each bounded to `[0.10, 1.50]` (resolves round 3's
"no bounds despite a claimed bound" finding). **Composition (resolves
round 3's "no ordering/clamping" finding):** `final_score =
clamp(0, 100, base_score × eligibility_multiplier)`, where `base_score`
comes from §9's scoring model and `eligibility_multiplier` is applied
exactly once, after `base_score` is finalized — no other multiplier is
composed with it in Phase 2.

**Regime-conditioned eligibility:**

- **`TRENDING_UP/DOWN`:** prefer Trend Following, SMC/ICT order-block
  retest after displacement, Chart-Pattern flag/pennant/channel-pullback/
  breakout-retest **(deferred — not yet formalized in §6; not eligible for
  routing until a future revision defines them, resolving round 3's
  inconsistency between this row and §6's actual scope)**. Of the
  patterns actually formalized in §6 (double/triple top-bottom,
  head-and-shoulders), prefer breakout-retest entries confirming with
  trend. Block SR Bounce counter-trend fades. **Unconfirmed chart
  patterns are never eligible candidates at all (§6) — there is nothing
  left in this row to "penalize" for being unconfirmed** (removes round
  3's contradiction between this row and §6's own never-trade-unconfirmed
  rule).
- **`RANGING`:** prefer SR Bounce, Range Rotation, SMC/ICT equal-high/low
  sweep reversal, false-break trap, double/triple top/bottom at a range
  boundary (post-confirmation only, per §6). Block Trend Following
  late-momentum entries inside the range. Penalize trend entries near
  equilibrium and repeated bounces from an already-invalidated-then-
  recovered level (§3's level-invalidation state, below).
- **`COMPRESSION`:** block every family **except** a specially-gated early
  breakout candidate from Chart-Pattern Breakout, defined precisely below
  (compression-timing fix).
- **`VOLATILITY_EXPANSION_UP/DOWN`:** block chasing the initial spike — no
  entry within `InpNoChaseBarsAfterSpike` (default 2) bars of the
  regime's own transition into this state. Prefer Post-Expansion Retest,
  SMC/ICT FVG return, Trend Following's momentum-continuation half.
- **`TRANSITION_OR_UNCERTAIN`, `NEWS_BLACKOUT`,
  `UNTRADEABLE_SPREAD_OR_LIQUIDITY`:** block every family unconditionally.

**Compression timing — resolved (round 3 found the prior explanation
self-contradictory: it claimed the classifier re-tags the breakout bar for
the *next* bar while also claiming the breakout bar itself stays
`COMPRESSION`):** the classifier (§2) reads bar `N`'s own close and
produces bar `N`'s regime **immediately** — if bar `N`'s close is itself
decisive enough to clear the expansion/trend thresholds, bar `N` is
classified `VOLATILITY_EXPANSION_*`/`TRENDING_*` **for bar `N` itself**,
subject to the normal two-bar hysteresis before that classification
actually takes effect for routing purposes. This means there are exactly
two distinct ways a compression breakout is captured, and they are not in
conflict:

1. **The gated early-breakout candidate** (`COMPRESSION`-eligible,
   retest **not required** — waiting for a retest after a regime
   reclassification is structurally unavailable under this timing, so
   this family-specific override is stated explicitly here) fires on a bar
   where price has moved decisively (a confirmed §6 pattern breakout) but
   the classifier's own `E`/`T_final` thresholds have **not yet** cleared
   hysteresis — i.e., while the regime is still nominally `COMPRESSION`
   post-hysteresis. This is a tighter-gated, earlier entry.
2. **The normal post-reclassification entry** fires one to two bars later,
   once `VOLATILITY_EXPANSION_*`/`TRENDING_*` has itself cleared its own
   two-bar hysteresis — at that point ordinary expansion/trend eligibility
   applies (including that regime's own no-chase-bars gate), and the
   Chart-Pattern family's normal retest-required behavior applies as
   usual.

These are two different, non-overlapping entry opportunities at two
different times, not one contradictory rule.

**Ownership (unchanged from round 3, confirmed by round 3's own review as
a real improvement):** `StrategyRouter` owns eligibility and scoring only.
`ConflictResolver` owns only the final tie-break: among eligible
candidates, the highest `final_score` wins in its own direction; between
opposing directions, `No trade` wins unless one direction's top
`final_score` exceeds the other's by at least `InpConflictScoreGap`
(default `10`, bounded `[0, 50]`). **Exact-tie rule (new — resolves round
3's finding that ties within one direction had no resolution once the
old family-priority column was removed):** if two eligible candidates in
the same direction have exactly equal `final_score`, the one with the
smaller (faster) entry timeframe wins; if still tied, the
alphabetically-first family name wins — an arbitrary but fully
deterministic final tiebreak.

**Risk multiplier — separated from the eligibility multiplier (resolves
round 3's mislabeling finding):** the `eligibility_multiplier` above
affects **ranking score only**. A separate, actual **risk multiplier**
(used for position sizing, §8) starts at `1.0` and is reduced only by
§8's drawdown-based risk-reduction formula — it is never touched by
routing eligibility.

**Strategy-switch logging:** every switch is logged to `TradeDecision`
(§9) with previous regime, new regime, selected family, confidence,
rejected alternatives (family + `final_score` + block/penalize reason),
the separate risk multiplier, and expected mode.

**Self-confirmed bypass — retired, rationale corrected:** V6.37's
`IsSelfConfirmedSetup` has an explicit, named setup-list scope (source
7534–7540) and remains subject to `ApplyRegimeRouting`'s veto (source
7464–7528, called via source 919–924) — the claim that it "had no scope or
conflict behavior" was false. It is retired in the new engine because its
bypass scope is tied to brittle string-based setup-name matching, which
this specification retires elsewhere (§5), not because it lacked defined
behavior.

**Level-invalidation lifecycle:** unchanged — current-run-only rejection,
not permanent retirement; a level becomes eligible again the moment its
consecutive-closes-beyond count returns to zero.

### 4. ICT/SMC logic (master prompt §8)

Per-definition required fields for every ICT/SMC concept below: formula,
timeframe, confirmation timing, maximum age, invalidation, first-touch-
or-retest behavior, trading context, stop, target, a repainting test, and
a unit test.

**Liquidity sweep and shift (ported from V8.11, normatively stated here —
resolves round 3's finding that this was referenced but never actually
defined in-section):**

- **Sweep pool:** logical indices `4..min(copied−2, 4+max(10,
  InpSweepLookback))` inclusive, where `copied` is the number of bars
  available on the working timeframe and `InpSweepLookback` defaults to
  `30` — 11 bars minimum, 31 at the shipped default.
- **Shift scan:** logical indices `2..min(copied−2, 2+max(3,
  InpShiftLookback))` inclusive, `InpShiftLookback` default `6` — 4 bars
  minimum, 7 at the shipped default.
- **Sweep confirmation:** a pool extreme (highest high or lowest low over
  the sweep pool) is swept by a single bar's wick beyond it, followed by a
  close back inside the pool's prior range within the shift-scan window —
  this closing-back-inside bar is the confirmation bar.
- **Final-stop transformation chain (ported, stated fully):** base stop
  buffer = an ATR-derived component (`ATR × InpSweepStopATRMultiple`,
  default `0.3`) plus current spread; if the resulting stop distance is
  below §8's `min_stop_distance` floor, it is rebuilt to that floor; if it
  exceeds §8's `max_stop_distance` cap, the trade is **rejected** (per
  §8's reject-not-clamp rule, not silently widened); the resulting price
  is normalized to the symbol's tick size; the stop distance used for risk
  calculation is recomputed from the normalized price, not the
  pre-normalization value.
- **Timeframe:** working TF per §3's SMC/ICT context/entry pair. **Max
  age:** the confirmation bar must occur within `InpSweepMaxAgeBars`
  (default 15) bars of the swept extreme, else the setup expires.
  **Invalidation:** a further close beyond the sweep extreme in the sweep
  direction. **First-touch/retest:** entry may be taken on the
  confirmation bar itself, or on a retest of the swept level within
  `InpSweepRetestMaxBars` (default 5) bars — configurable per strategy.
  **Repainting test:** the sweep pool and shift scan are computed only
  from closed bars (data conventions above); a unit test asserts the
  sweep/shift read for a historical bar index never changes on
  subsequent ticks.

**Order blocks (ported from V8.11's working/refine-TF path):** the
working timeframe role (`InpWorkingTF`) and refine timeframe role
(`InpRefineTF`) are both configurable inputs, not a fixed M15→M5 pairing
(source 52–53, 700, 762–767) — this specification uses that same
configurability, with `InpWorkingTF`/`InpRefineTF` defaults matching §3's
SMC/ICT context/entry pair per mode. An order block is the last
opposite-direction candle before a confirmed displacement move (Marubozu
predicate, §5); its zone is that candle's full range; invalidation is a
confirmed close through the zone; first-touch entry is preferred, one
retest permitted within `InpOBMaxRetestBars` (default 10) bars.

**Fair value gaps (FVG) — depth input unified (closes ledger item 14):**
V6.37's FVG structural-gating path currently mixes
`InpStructureSwingDepth` (via `AnalyzeStructure`) and `InpFractalDepth`
(via `FindTwoConfirmedSwingsBefore`) for what should be one concept. **The
new engine's FVG gating uses the single canonical swing-depth definition
from `SwingEngine` (§11) exclusively** — no independently-tunable second
depth input. An FVG is the three-candle gap where `low[0] > high[2]`
(bullish) or `high[0] < low[2]` (bearish); zone = the gap itself;
invalidation = a confirmed close fully through the gap; first-touch/retest
= entry on first return to the gap, or the 50%-fill level, configurable.

**Premium/discount and equal-high/low liquidity:** premium/discount split
at the `SwingEngine` range's midpoint (equilibrium, §11); equal-high/low
liquidity = two or more swing extremes within `ATR × InpEqualLevelTolerance`
(default `0.1`) of each other.

### 5. Candlestick pattern engine (master prompt §9)

All formulas use the logical-index convention (Data conventions, above) —
resolves round 3's finding that this section previously used raw `[0]`
while claiming completed-candle-only reads.

**Base measurements**, per logical-index candle `k`: `body[k] =
|close[k]−open[k]|`, `range[k] = high[k]−low[k]`, `upper_wick[k] = high[k]
− max(open[k],close[k])`, `lower_wick[k] = min(open[k],close[k]) − low[k]`,
`body_ratio[k] = body[k]/range[k]`, `upper_wick_ratio[k] =
upper_wick[k]/range[k]`, `lower_wick_ratio[k] = lower_wick[k]/range[k]`,
`upper_wick_to_body[k] = upper_wick[k]/max(body[k], InpBodyEpsilon)`,
`lower_wick_to_body[k] = lower_wick[k]/max(body[k], InpBodyEpsilon)`
(`InpBodyEpsilon` default `0.00001` in price units, avoids divide-by-zero
on a doji — adds the wick-to-body metric master-prompt §9 requires
alongside wick-to-range, which round 3 found missing), `atr_size[k] =
range[k]/ATR(InpCandleATRPeriod=14)`. `range[k]=0` invalidates every
pattern below for that candle.

**Relative-size metric (added — resolves round 3's missing master-prompt
relative-size requirement):** `size_percentile[k] = percentile_rank(
range[k], {range[k+1..k+InpCandleSizeWindow]})` (`InpCandleSizeWindow`
default 20) — a pattern-specific qualifier used where noted below.

**Gap/overlap general equations (added — resolves round 3's missing
general gap/overlap requirement):** `gap_up[k] = low[k] − high[k+1]`
(positive = true gap up); `gap_down[k] = low[k+1] − high[k]`;
`overlap(rangeA, rangeB) = max(0, min(highA,highB) − max(lowA,lowB))`.

**Thresholds table (every constant below is a named, bounded, configurable
input — resolves round 3's finding that constants had no input name or
bound):**

| Input | Default | Bound |
|---|---|---|
| `InpPinBarMinLowerWick` | 0.60 | [0.40, 0.85] |
| `InpPinBarMaxBody` | 0.30 | [0.10, 0.45] |
| `InpPinBarMaxOppositeWick` | 0.15 | [0.05, 0.30] |
| `InpPinBarTrendLookback` | 5 | [2, 20] |
| `InpRejectionMaxBody` | 0.10 | [0.02, 0.20] |
| `InpRejectionMinWick` | 0.70 | [0.50, 0.90] |
| `InpMarubozuMinBody` | 0.90 | [0.75, 0.99] |
| `InpDisplacementATRMultiple` | 1.5 | [1.0, 4.0] |
| `InpDojiMaxBody` | 0.10 | [0.02, 0.20] |
| `InpSpinningTopMaxBody` | 0.35 | [0.20, 0.50] |
| `InpSpinningTopMinWick` | 0.20 | [0.10, 0.35] |
| `InpTweezerTolerance` (× ATR) | 0.10 | [0.02, 0.30] |
| `InpHaramiMaxRatio` | 0.50 | [0.20, 0.80] |
| `InpStarMaxMiddleBody` | 0.30 | [0.10, 0.45] |
| `InpStarOverlapMax` | 0.50 | [0.20, 0.80] |
| `InpSoldiersMinBody` | 0.55 | [0.35, 0.80] |
| `InpSoldiersMaxWick` | 0.20 | [0.05, 0.35] |
| `InpEngulfingMinSizePercentile` | 0.50 | [0.0, 1.0] |

**Single-candle patterns:**

- **Bullish pin bar/hammer:** `lower_wick_ratio[0] ≥ InpPinBarMinLowerWick`
  AND `body_ratio[0] ≤ InpPinBarMaxBody` AND `upper_wick_ratio[0] ≤
  InpPinBarMaxOppositeWick` AND `close[0]` in the upper 40% of `range[0]`
  AND `close[InpPinBarTrendLookback] > close[0]` (a preceding down-move:
  the close `InpPinBarTrendLookback` bars ago was higher than the current
  close). **Bearish pin bar/shooting star:** mirrored
  (`upper_wick_ratio[0] ≥ InpPinBarMinLowerWick`, etc.,
  `close[InpPinBarTrendLookback] < close[0]`).
- **Dragonfly-style rejection:** `body_ratio[0] ≤ InpRejectionMaxBody` AND
  `lower_wick_ratio[0] ≥ InpRejectionMinWick` AND `upper_wick_ratio[0] ≤
  InpRejectionMaxBody`. **Gravestone-style:** mirrored on the upper wick.
- **Marubozu/displacement candle:** `body_ratio[0] ≥ InpMarubozuMinBody`
  AND `atr_size[0] ≥ InpDisplacementATRMultiple`.
- **Doji:** `body_ratio[0] ≤ InpDojiMaxBody`. **Spinning top:**
  `InpDojiMaxBody < body_ratio[0] ≤ InpSpinningTopMaxBody` AND both
  `upper_wick_ratio[0] ≥ InpSpinningTopMinWick` and
  `lower_wick_ratio[0] ≥ InpSpinningTopMinWick`. Both are context filters
  (require `ER < InpMinEfficiency`, §2's own defined threshold, reused
  directly — not a separately-invented vague condition) and are never
  standalone entries.
- **Inside bar:** `high[0] < high[1]` AND `low[0] > low[1]` — has no
  inherent direction; it is a context filter confirmed only by a
  subsequent close beyond `high[1]`/`low[1]` in the breakout direction.
  **Outside bar:** `high[0] > high[1]` AND `low[0] < low[1]` — direction =
  its own `close[0]` vs `open[0]`.

**Two-candle patterns:**

- **Bullish engulfing:** `close[0] > open[1]` AND `open[0] < close[1]` AND
  `body[0] > body[1]` AND `close[1] < open[1]` AND `size_percentile[0] ≥
  InpEngulfingMinSizePercentile`. **Bearish engulfing:** mirrored.
- **Tweezer top:** `|high[0] − high[1]| ≤ ATR × InpTweezerTolerance` AND
  `close[1] > open[1]` AND `close[0] < open[0]`. **Tweezer bottom:**
  mirrored on lows.
- **Harami (body containment, not full-range — resolves round 3's
  containment-choice finding):** `body_high[k] = max(open[k],close[k])`,
  `body_low[k] = min(open[k],close[k])`. `body[0] < body[1] ×
  InpHaramiMaxRatio` AND `body_high[0] ≤ body_high[1]` AND `body_low[0] ≥
  body_low[1]`. **Implied direction** = opposite of candle `1`'s own
  direction: `close[1] > open[1]` → bearish harami implied; else bullish
  implied. **Confirmation** (required before this counts as more than an
  alert) = a third bar closing beyond `close[1]` in the implied direction.

**Three-candle patterns:**

- **Morning star:** `close[2] < open[2]` AND `body_ratio[1] ≤
  InpStarMaxMiddleBody` AND `overlap({high[1],low[1]}, {body_high[2],
  body_low[2]})/body[2] ≤ InpStarOverlapMax` (the middle candle's range
  overlaps at most this fraction of the first candle's body — replaces
  round 3's non-numeric "gapping or near-gapping") AND `close[0] > open[0]`
  AND `close[0] > (open[2]+close[2])/2`. **Evening star:** mirrored.
- **Three white soldiers:** for `i ∈ {0,1,2}`, `close[i] > open[i]`,
  `body_ratio[i] ≥ InpSoldiersMinBody`, `upper_wick_ratio[i] ≤
  InpSoldiersMaxWick`; AND `open[0] > open[1] > open[2]` and `close[0] >
  close[1] > close[2]`. **Three black crows:** mirrored.
- **Three-bar reversal:** candle at logical index `1` is a confirmed swing
  pivot per `SwingEngine` (§11); candle `0` closes beyond `open[2]` in the
  reversal direction, where **reversal direction** is defined by the swing
  type at index `1` (a confirmed swing low → bullish reversal expected; a
  confirmed swing high → bearish).

**Strength, context, invalidation (defined concretely — resolves round
3's undefined-strength/vague-context/non-direction-specific-invalidation
findings):** `strength = clamp01(0.5 × primary_ratio + 0.5 ×
min(1, atr_size[0]/2.0))`, where `primary_ratio` is the pattern's own
defining ratio (e.g., `lower_wick_ratio[0]` for a bullish pin bar). Every
pattern requires the regime read (§2) to be anything other than
`TRANSITION_OR_UNCERTAIN`/gating, and requires a §3-defined location match
(SR/liquidity/OB/FVG/neckline/pattern boundary) from the strategy
consuming it — no pattern fires as a standalone signal. **Invalidation**
(direction-specific): a bullish pattern invalidates on a confirmed close
below the pattern's lowest `low[k]` across its constituent candles; a
bearish pattern invalidates on a confirmed close above the pattern's
highest `high[k]`.

**Storage and drawing:** pattern ID, direction, start/end logical index,
`strength`, context (regime/location), confirmation status, invalidation
level. Stable object names, no duplicate labels, unit test confirming a
historical label's position/text never changes after confirmation. TA-Lib
comparison is research-only, never assumed profitable.

### 6. Chart-pattern engine (master prompt §10)

**Scope narrowed to match what is actually formalized (resolves round 3's
finding that §3 routed to patterns §6 never defined):** this revision
formalizes **double/triple top and bottom** and **head-and-shoulders/
inverse head-and-shoulders**. Triangles, rectangles, flags, pennants,
wedges, and channels remain out of scope for Phase 2 and are **not**
referenced as routing-eligible in §3 (§3's tables have been corrected to
say so explicitly) — each will be specified with its own pivot topology in
its own Phase 5 `STRATEGY_SPECIFICATION.md` task, using the shared
framework below, which is what makes that remaining work well-defined
Phase-5 sizing rather than an open Phase 2 gap.

**Shared framework:**

- **`SwingEngine` pivot predicate (defined once, in §11, reused
  everywhere — resolves round 3's repeated "SwingEngine has no
  mathematical predicate" finding across §4/§5/§6):** a confirmed swing
  high at logical index `k` requires `high[k] > high[j]` for all `j` in
  `[k−InpSwingDepth, k−1] ∪ [k+1, k+InpSwingDepth]` (`InpSwingDepth`
  default `3`); confirmed only once `InpSwingDepth` further bars have
  closed past index `k`. Swing low: mirrored on lows.
- **Trend prerequisite (added — resolves round 3's missing-prerequisite
  finding):** double top/H&S require a preceding confirmed uptrend of at
  least `InpPatternMinPriorTrendBars` (default 10) bars (measured as
  `T_final ≥ InpTrendThreshold` for that many bars, reusing §2's own trend
  measure) before the first peak; double bottom/inverse H&S mirror on a
  preceding downtrend.
- **`pattern_height = H − L`** (`H` = the pattern's defining peak/trough
  price, `L` = the neckline/boundary price) — stated explicitly.
  `H1_or_H2_avg = (H1+H2)/2` for double-top targets.
- **Time symmetry:** `|t_right_leg − t_left_leg| / t_left_leg ≤
  InpPatternTimeTolerance` (default `0.5`, bounded `[0.1, 1.0]`).
- **Price symmetry:** `|price_right_leg − price_left_leg| / ATR ≤
  InpPatternPriceTolerance` (default `1.0`, bounded `[0.2, 3.0]`).
- **Width:** `InpPatternMinBars` (default 20) to `InpPatternMaxBars`
  (default 200). **Height:** `pattern_height/ATR ≥
  InpPatternMinHeightATR` (default `2.0`).
- **Pullback/neckline-depth floor — corrected (resolves round 3's finding
  that the prior fractional pullback condition algebraically reduced to
  the trivial `L<H`):** instead of a fraction of `pattern_height` (which
  is itself defined from `L`, creating a self-referential inequality),
  the neckline depth is an **ATR-based absolute floor**:
  `H1 − L ≥ InpPatternMinPullbackATR × ATR` (default `1.5`, bounded
  `[0.5, 4.0]`) — a genuine pullback requirement independent of how
  `pattern_height` is itself defined.

**Double top:** two confirmed swing highs `H1`, `H2` with `|H1−H2|/ATR ≤
InpPatternPriceTolerance`, separated by a confirmed swing low `L` (the
neckline) satisfying the pullback floor above. **Breakout:** a confirmed
close below `L − ATR×InpBreakoutBuffer` (default `0.1`, bounded
`[0.02,0.3]`). **Target:** `L − (H1_or_H2_avg − L)`. **Stop:** above the
more recent of `H1`/`H2` plus the buffer. **Double bottom:** mirrored.
**Triple top:** three confirmed swing highs `H1,H2,H3` pairwise within
`InpPatternPriceTolerance` of each other, separated by two intervening
confirmed swing lows `L1,L2` forming a (possibly sloped) neckline drawn
through those two points; same breakout/target/stop logic using the
neckline's value at the breakout bar. **Triple bottom:** mirrored.

**Head and shoulders:** confirmed swing highs `LS` (left shoulder), `H`
(head), `RS` (right shoulder) with `H − max(LS,RS) ≥
InpPatternMinHeadProminenceATR × ATR` (default `1.0`, bounded `[0.3,3.0]`
— added minimum head prominence, resolves round 3's finding) and
`|LS−RS|/ATR ≤ InpPatternPriceTolerance`; time symmetry applied separately
to the `LS→H` and `H→RS` durations (each individually within
`InpPatternTimeTolerance` of the other — stated explicitly, resolves
round 3's "no complete time topology" finding); a neckline through the two
intervening swing lows, sloped or flat. **Breakout:** confirmed close
beyond the neckline (evaluated at the current bar's neckline value) minus
the buffer. **Target:** neckline value at breakout minus `(H −
neckline_at_H)`. **Stop:** above `RS` plus buffer. **Inverse H&S:**
mirrored.

**Retest — predicate defined (resolves round 3's undefined "holds/fails"
finding):** after a confirmed breakout, price returning to within `ATR ×
InpRetestTolerance` (default `0.3`) of the boundary/neckline enters
`RETESTING`. **Retest holds** if price does not close back beyond the
boundary by more than `ATR × InpRetestFailureATR` (default `0.2`) within
`InpRetestMaxBars` (default 10) bars of first touching the retest zone —
holding transitions to `TRADED`; failing transitions to `INVALIDATED`.
Retest is required by default for the Chart-Pattern family (§3) except
the compression-timing early-breakout candidate, which is retest-optional
by explicit override (§3).

**Volume, max age, confidence, false break (defaults unchanged from round
3, restated):** volume requirement off by default (per-symbol opt-in).
Maximum age from confirmation: `InpPatternMaxAgeBars` (default 50).
**Maximum age from formation start (added — resolves round 3's finding
that a pattern stuck in `FORMING` indefinitely never expired):**
`InpPatternFormingMaxAgeBars` (default 100) bars from the pattern's first
detected pivot. Confidence: `clamp01(1 − price_tolerance_used/
InpPatternPriceTolerance) × 0.5 + clamp01(1 − time_tolerance_used/
InpPatternTimeTolerance) × 0.5` (reuses §2's margin-against-threshold
logic, not a third distinct confidence model). False break: a confirmed
close back inside the boundary within `InpFalseBreakBars` (default 3)
bars of breakout → `INVALIDATED`.

**Entry gates (reused, not re-invented — resolves round 3's "reused
component has no threshold" finding):** entries require
`current_spread ≤ ATR × InpMaxSpreadATRMultiple` (§2's own gating
predicate, cited directly) and, for Day-trade-mode entries, remaining
session minutes `≥ InpMinDayTradeSessionMinutes` (§1's own component,
cited directly) — no separate, newly-invented threshold.

**Scalp-vs-day-trade suitability:** patterns confirming within `≤ 40`
entry-TF bars are Scalp-eligible per §3's table; wider patterns are
Day-trade only.

**Registry — extended (resolves round 3's "prevents duplicates only, not
re-trades" finding):** keyed by pattern type + boundary pivots; prevents
two simultaneous instances of the same pattern from both trading, **and**
permanently marks an instance `TRADED` as consumed — it never re-enters
eligibility even if price re-touches the same boundary; a new instance
requires new pivots.

**Required visual outputs (added — resolves round 3's "absent" finding):**
boundary/neckline line(s), start/end pivot markers, breakout marker, retest
marker (when applicable), pattern-name label, live confidence value, live
status — all as named chart objects, convention `CP_<type>_<confirmation_
bar_index>`. Visible objects capped at `InpMaxVisiblePatternObjects`
(default 20).

**State machine — fully branching (resolves round 3's finding that
`FORMING`/`RETESTING` had no path to `EXPIRED`):**

```
FORMING ──confirmed──────────────────────> CONFIRMED
   │                                            │
   │                                            ├──(retest required)──> RETESTING ──holds──> TRADED
   │                                            │                           │
   │                                            │                           └──fails──> INVALIDATED
   │                                            ├──(retest not required)───────────────> TRADED
   │                                            ├──false break──────────────────────────> INVALIDATED
   │                                            └──InpPatternMaxAgeBars elapses──────────> EXPIRED
   ├──pivots invalidate before confirmation──────────────────────────────────────────────> INVALIDATED
   └──InpPatternFormingMaxAgeBars elapses─────────────────────────────────────────────────> EXPIRED
                                                                                              (also reachable
                                                                                               from RETESTING
                                                                                               if InpRetestMaxBars
                                                                                               elapses with
                                                                                               neither holds
                                                                                               nor fails)
```

`INVALIDATED` and `EXPIRED` are both reachable from `FORMING`, `CONFIRMED`,
and `RETESTING` — never mandatory post-`TRADED` stages, and retest remains
genuinely optional per family/configuration.

### 7. Exit engine (master prompt §14)

**Target selection:** the target selector evaluates all reachable
candidates from `SwingEngine`/`MarketStructure` (§11) — confirmed SR zone,
swing fractal, major-swing, and opposing-range-boundary — sourcing
candidates from the full set of V6.37's target-generating mechanisms
(`SetEquilibriumContinuationTarget`, `ApplyHistoricalM15Target`/
`FindQualifiedFractalTarget`, nearer SR/supply-demand selection,
opposite-boundary range/rotation targets — not one alone) and selects the
**nearest** candidate that still clears `risk × InpMinRiskReward`.

**Break-even arming:** arms when `SwingEngine` confirms a new swing pivot
beyond the entry price in the trade's favor, **and** the position's
actual fill price has moved at least `InpBreakEvenMinR` (default `0.5R`)
in favor. Both conditions required.

**Structure trailing — directional, both sides defined (resolves round
3's finding that only the long-side formula was given):**
- **Long:** trail stop = `most_recent_confirmed_swing_low_in_favor − ATR ×
  InpTrailBuffer` (default `0.3`).
- **Short:** trail stop = `most_recent_confirmed_swing_high_in_favor +
  ATR × InpTrailBuffer`.
- **"Swing in favor" defined precisely:** for a long, the relevant swing
  type is a confirmed swing **low** (the trail follows swing lows
  upward); for a short, a confirmed swing **high** (the trail follows
  swing highs downward) — stated explicitly so an implementer cannot
  place a short's stop on the wrong side.
Recalculated each time a new favorable swing confirms; never moved
against the position.

**ATR fallback — both sides:** if no new confirmed favorable swing forms
within `InpTrailStaleBars` (default 15) bars since the last update:
- **Long:** `current_price − ATR × InpATRTrailMultiple` (default `2.0`).
- **Short:** `current_price + ATR × InpATRTrailMultiple`.

**Time stop:** closes the position if all of: (a) elapsed time exceeds the
mode's expected-duration ceiling (Scalp: `InpScalpMaxMinutes`, default 60;
Day-trade: remaining session time, §1 item 4, reaching `0`); (b) current
R `< InpTimeStopMinR` (default `0.3R`); (c) no fresh confirmed favorable
swing within `InpTrailStaleBars` bars (the same staleness definition as
the ATR fallback — one consistent "no progress" clock).

**Profit-lock:** arms once price covers `InpProfitLockTriggerPercent`
(default `70%`) of the distance from entry (actual fill) to the current
target; raises the stop to lock `InpProfitLockKeepPercent` (default `50%`)
of the current open gain. If the broker's minimum-stop-distance
enforcement moves the resulting stop further than intended, the engine
re-checks whether the actually-achieved lock still clears
`InpProfitLockMinKeepPercent` (default `30%`); below that floor, the
attempt is logged as a partial-lock warning, not silently accepted as a
full lock.

**Exit priority (unchanged):** (1) daily/session risk lock, (2) news
safety policy, (3) opposite-confirmed-structure-shift, (4)
momentum-failure exit, (5) profit-giveback guard, (6) time stop, (7)
trailing-stop update.

**Giveback guard — bounds (unchanged, confirmed correct by round 3):**
V6.37: arm `max(0.25, InpGivebackArmRR)` (default `1.25R`), percentage
clamped `10–90%` (default `60%`), close-trigger floored at `0.05R`. V8.11:
arm `max(0.3, InpGivebackArmR)` (default `0.8R`), floor `max(0.0,
InpGivebackFloorR)` (default `0.1R`). Both models built behind one
`ProfitGivebackGuard` interface; default off until Phase 8 evidence.

**Trendline — porting decision made explicit (resolves round 3's "no
decision, no reprojection algorithm" finding):** the new engine's
trendline construction uses **three validated anchors, not two** — this
is the fix for V6.37's defect (`BuildThreePointTrendLine` used only the
outer two of three points). The middle swing point must itself lie within
`ATR × InpTrendlineMiddleToleranceATR` (default `0.5`) of the line drawn
through the outer two points, or the trendline is rejected outright. The
line is **re-projected fresh at every new confirmed swing** (not a
constant projected value, fixing `EvaluateTrendBreaker`'s defect).

### 8. Risk management (master prompt §13, `RISK_POLICY.md`)

**Hard limits:** XAUUSD 0.25%, other metals 0.25–0.50%, synthetics
0.25–0.50%; hard cap 1.00% per trade, 1.00% total open risk (own-magic
scope, below), 2.00% daily loss, 4.00% weekly loss (account-wide scope,
below); three-loss cooldown (per-symbol, below).

**Binding blanket rules restored (resolves round 3's finding that these
disappeared from the standalone section — restated normatively here, not
merely inherited from a parent commit):**
- No martingale, no grid, no averaging down.
- A broker's minimum tradeable volume whose implied risk exceeds the
  per-trade cap causes the trade to be **rejected outright** — never
  rounded up to fit.
- Before submission, the calculated `risk_cash` (below) is cross-checked
  against `OrderCalcProfit`'s own result for the same parameters; a
  discrepancy beyond `InpRiskCrossCheckTolerancePercent` (default `5%`)
  blocks the trade and logs the mismatch.
- A mandatory `OnInit`/symbol-attach validation routine checks tick
  value, tick size, contract size, volume min/max/step, stop level,
  freeze level, filling mode, and margin; any failure fails the symbol
  closed (not traded).
- A stop is never widened merely to avoid a loss — SL modification is
  only ever loss-reducing/tightening, or one of §7's explicitly-defined
  trailing/break-even mechanisms; never a distance increase.
- Risk may never increase as a function of a preceding loss — a loss may
  reduce or hold the next trade's risk (§8's drawdown-reduction control,
  below), never increase it. This is one directional constraint.
- **Intraday boundary, fully defined:** `InpIntradayBoundaryServerTime`
  (default `23:45` server time) — all of **this EA's own** positions,
  across every symbol/mode it manages, are closed at this time daily
  (corrects round 3's "all positions" wording, which conflicted with the
  own-magic-only closure authority stated below).

**Add-on/basket rule (stated normatively):** **Add-ons and multi-leg
baskets are disabled by default.** No sizing function may create a second
concurrent position on the same symbol/direction as an existing one, and
no basket/multi-leg mechanism is active, until a Phase 5+ isolated
experiment independently proves both the total-risk math and incremental
value.

**Per-position risk — corrected (resolves round 3's dimensional-error
finding):**
`loss_distance = max(0, entry_fill − SL)` for a long, `max(0, SL −
entry_fill)` for a short (correctly zero when the SL sits on the profit
side of entry, e.g., a locked-in profit stop — resolves round 3's
"unsigned distance" finding). `risk_cash = loss_distance × volume ×
tick_value / tick_size` (adds the missing division by `tick_size`).
`per_trade_risk_pct = 100 × risk_cash / current_equity`;
`total_open_risk_pct = 100 × Σ risk_cash_i / current_equity` — both now
explicitly connected to the 1%/1% caps (resolves round 3's "cash formula
never connected to the caps" finding). Every `risk_cash` computation is
cross-checked against `OrderCalcProfit` per the blanket rule above.

**No-SL fallback:** `risk_cash_no_stop = ATR × InpNoStopWorstCaseATRMultiple
× volume × tick_value / tick_size` (default multiple `10`) — same formula
shape as the normal case, substituting an ATR-multiple loss-distance
proxy for an actual SL distance, not a conflated notional figure
(resolves round 3's conflation finding). The position is flagged for
immediate remediation; if a valid stop is not attached within
`InpNoStopGraceSeconds` (default 5) seconds, the position is closed
immediately (fail-closed).

**Scope — own-magic vs. account-wide, stated precisely (resolves round
3's finding that "account-wide" conflicted with own-magic aggregation):**
the **1% per-trade and 1% total-open-risk caps are scoped to this EA's own
managed exposure** (own magic number) on this account — this engine has
no authority or reliable visibility contract over other EAs'/manual
positions, so it cannot and does not aggregate those into its own 1%
caps. The **2%/4% daily/weekly loss caps are measured against total
account equity change** (a loss is a loss regardless of which EA caused
it), but the **closing action** taken on breach remains limited to this
EA's own positions (below) — two caps, two deliberately different
scopes, for two different reasons, not one ambiguous "account-wide" term
applied inconsistently. **Accepted limitation, stated explicitly:** if
multiple magic-numbered EAs run on one account, each instance's own 1%
caps are evaluated against its own exposure only; no single instance can
enforce a true aggregate cap across other EAs it does not control.

**Pending-order risk reservation — corrected for hedging-only accounts
(resolves round 3's "larger of two, not sum" finding, now that ledger item
9 fixes the account model to hedging-only):** total open risk includes
**the sum of all concurrently live pending orders'** worst-case risk
(using the same `risk_cash` formula, substituting the pending order's own
entry/SL) — summed unconditionally, since a hedging-only account allows
opposite pending orders to both independently fill and coexist; there is
no "only one can fill" assumption to justify taking the larger of two
figures instead of their sum. A stopless pending order is rejected
outright by the mandatory-stop rule, so the no-SL fallback above is a
defensive completeness statement, not an expected runtime path for
pending orders. Slippage/gap are not double-modeled in the reservation
figure — the reservation is the order's stated worst case at submission;
actual fill slippage is handled entirely by the post-fill breach
mechanism below.

**Daily/weekly loss — corrected to measure actual period change (resolves
round 3's "measures absolute floating P/L, not the change since the
boundary" finding):** `daily_loss_pct = 100 × (current_equity −
daily_start_equity_adjusted) / daily_start_equity_adjusted`, where
`current_equity` is the live account equity (`ACCOUNT_EQUITY`) and
`daily_start_equity_adjusted` is the equity recorded at the daily
boundary, continuously rebased for detected cash flow (below) — this
correctly nets out a position already open (and unchanged) at the
boundary, instead of re-counting its entire floating P/L as a new loss.
`weekly_loss_pct`: identical formula against `weekly_start_equity_
adjusted` and the weekly boundary.

**Cash-flow treatment — deterministic source (resolves round 3's
"heuristic snapshot inference" finding):** deposits/withdrawals/credits
are detected via the broker's own deal history
(`HistorySelect`/`HistoryDealGetInteger(DEAL_TYPE)` for
`DEAL_TYPE_BALANCE` entries), scanned since the last-processed deal
ticket (persisted). Each such deal's profit value is added directly to
`daily_start_equity_adjusted` and `weekly_start_equity_adjusted` at
detection time — the correct, MT5-native mechanism, not inference from
equity/balance/floating snapshots (which cannot distinguish a cash event
from ordinary trading P/L).

**Reset boundary — single clock (resolves round 3's "which symbol's
calendar" finding):** both daily and weekly boundaries use the **trade
server's own clock** (`TimeTradeServer()`), never an individual symbol's
session calendar — this sidesteps the mixed metals/synthetics calendar
problem entirely, since server time is one clock regardless of how many
different-session symbols are traded. Daily reset: server midnight.
Weekly reset: the first trade-server tick at or after Monday `00:05`
server time since the last recorded weekly reset (the 5-minute buffer
avoids weekend-gap edge effects). **No-tick-at-boundary handling:** the
reset fires on the first tick received after the boundary time has
passed, compared against the last-recorded boundary crossing — not an
exact-timestamp requirement.

**Restart persistence — schema-safe (resolves round 3's "schema mismatch
wipes a valid baseline" finding):** `daily_start_equity_adjusted`/
`weekly_start_equity_adjusted` and their reset timestamps persist via
`StateManager` (§11). A schema-version mismatch triggers a **targeted
field-by-field migration** of recognized fields, resetting only fields
absent from the old schema — it never discards a still-valid period-loss
baseline wholesale.

**Breach behavior:** the pre-trade check (before submission) is the only
point where the caps function as a hard gate blocking a new entry.
**Post-fill (resolves round 3's "not immediate, vague timing" finding):**
breach detection happens inside the `OnTradeTransaction` handler at the
moment the filling deal is reported, using that event's own actual fill
data (not a subsequent tick's snapshot); the closure order is submitted
synchronously from that same handler. A persisted `closure_pending`
record (per-instance namespace) is written before the close order is
submitted; if the close fails (requote/error), the EA retries on every
subsequent tick until confirmed closed, blocking new entries on that
symbol meanwhile; on restart, a pending `closure_pending` record is the
first thing reconciled. A breach also cancels all of this EA's own
pending orders on the affected symbol. **Account-wide close scope:** a
daily/weekly breach closes only positions carrying this EA's own magic
number — never a manual or other-EA position.

**Stop-floor/cap — equations defined (resolves round 3's "no equation,
no percentile, no predicate" finding):** `min_stop_distance = ATR ×
InpMinStopATRMultiple` (default `0.5`) — the absolute floor; a
tighter pattern/structure-implied stop is widened out to this floor.
`max_stop_distance = min(price × InpMaxStopPricePercent (default 3.0%),
ATR × InpMaxStopATRMultiple (default 4.0))` — a structure-implied stop
wider than this cap **rejects** the trade (never silently clamped, which
would silently change the strategy's own computed risk-reward).
`InpMinStopATRMultiple < InpMaxStopATRMultiple` is enforced at `OnInit`
(fail closed if misconfigured). **"Typical volatility" and recheck
predicate:** the trailing `InpVolatilityWindow`-bar (default 500) ATR
distribution's **median** (50th percentile) is "typical volatility";
re-validated every `InpVolatilityRecheckBars` (default 500) bars — if
current ATR deviates from that rolling median by more than
`InpVolatilityShiftPercent` (default `50%`), the floor/cap are
recomputed against the new current ATR at the next recheck, not left on
the stale attach-time value.

**Profit-protection controls:**
- Account equity-peak giveback: off by default (Phase 8 experiment).
- **Daily equity-peak giveback (corrected to actually track a peak —
  resolves round 3's "absolute rule, no peak tracked" finding):**
  `daily_peak_equity = max(daily_peak_equity, current_equity)`, updated
  every tick since the daily boundary. Arms once `(daily_peak_equity −
  daily_start_equity_adjusted)/daily_start_equity_adjusted ≥
  InpDailyGivebackArmPercent` (default `1.0%`); triggers closure when
  `(daily_peak_equity − current_equity)/daily_peak_equity ≥
  InpDailyGivebackFloorPercent` (default `0.5%`) — a genuine peak-relative
  giveback.
- Session profit lock: off by default (Phase 8 experiment).
- **Three-loss cooldown — scope/reset/expiry defined (resolves round 3's
  finding):** per-symbol streak (not account-wide); `InpCooldownMinutes`
  (default 60) after the third consecutive loss on that symbol; a single
  winning trade on that symbol resets the streak to zero; persisted in
  the per-instance, symbol-keyed namespace.
- Maximum trades per session (`InpMaxTradesPerSession`, default 10) and
  maximum failed attempts at one level (`InpMaxFailedAttemptsPerLevel`,
  default 2): per-symbol, reset at the daily boundary (same namespace as
  the daily baseline's own reset event).
- **Reduced risk after drawdown — peak/scope/reset defined (resolves
  round 3's finding):** `current_drawdown_percent = 100 ×
  (account_peak_equity − current_equity)/account_peak_equity`, where
  `account_peak_equity` is an **all-time** running peak, reset only by an
  explicit, documented operator action (never automatically) — distinct
  from the daily/weekly peaks above, which reset each period.
  `risk_multiplier = clamp(1.0 − current_drawdown_percent/
  InpMaxDrawdownReductionPercent, InpMinRiskMultiplier, 1.0)`
  (`InpMaxDrawdownReductionPercent` default `10`, `InpMinRiskMultiplier`
  default `0.25`).
- **Daily profit target — input/default/equation added (resolves round 3's
  finding):** `InpDailyProfitTargetPercent` (default `3.0%`); reached when
  `(current_equity − daily_start_equity_adjusted)/daily_start_equity_
  adjusted ≥ InpDailyProfitTargetPercent/100`. The stop-trading-after-
  target control is **ON by default**; only the "continue at reduced
  risk" override is off by default and requires separate approval.

**Persistence and restart — namespaces assigned explicitly (resolves
round 3's "not all state assigned to one namespace" finding):**
`StateManager` persists via MT5 global variables for small scalars and a
local file-based key-value store (atomic write via write-to-temp-then-
rename) for structured state. Every record carries a schema-version
field (migration behavior above). **Two namespaces:**
- **Account-wide** (`account_login + trade_server`, no magic/symbol):
  daily/weekly start-equity baselines and their timestamps,
  `daily_peak_equity`, `account_peak_equity`.
- **Per-instance** (`symbol + magic + account_login + trade_server`):
  basket/position tracking, per-symbol cooldown streaks, per-symbol
  failed-level/session-trade counters, per-bucket learning statistics
  (§9).
**Concurrency (added — resolves round 3's "no single-writer protocol"
finding):** account-wide writes are guarded by a simple compare-and-set
convention (an MT5 global-variable-based lock, or a `.lock` sentinel
file) so only one instance performs a rebase/reset write at a time; other
instances re-read after a short backoff rather than writing concurrently.

**Durable-intent protocol — broker-visible correlation (resolves round
3's "not crash-safe, no unique correlation across history" finding):**
every order submission writes a durable local "intent" record **and**
tags the order's own `comment` field with the same unique intent ID
before the `CTrade` call — making the correlation ID broker-visible and
recoverable via `HistorySelect` order/deal comment lookup after a crash,
not local-record-only. On restart, `OrderManager` reconciles by checking
**both** live positions/orders **and** closed order/deal history (via
`HistorySelect` over the relevant window) for a matching intent-ID
comment — an order filled and closed before restart is correctly found in
history, not misclassified as abandoned. An intent with no matching
result anywhere, older than `InpIntentTimeoutSeconds` (default 30), is
treated as failed/abandoned and logged.

### 9. Signal scoring, trade decision object, journal, offline learning (master prompt §11–12, §18)

**This section's full content is restored here (resolves round 3's finding
1 — the round-3 revision deleted this material and replaced it with
"unchanged," which was false since the deletion itself removed the only
place it had been fully stated).**

**Score components:** location/structure quality (SR/OB/FVG/liquidity
proximity, §3/§4), pattern quality (§5/§6's `strength`/`confidence`),
regime alignment (§2's confidence-weighted eligibility multiplier, §3),
expected reward-to-risk (`min(1, expected_R/3.0)`), and sample-gated
historical performance (below). **Correlation-avoidance rule:** components
that are structurally the same evidence expressed twice are never both
counted at full weight — named examples: a BOS confirmation and a
displacement candle are not independently scored (displacement is how BOS
is confirmed, §4); a pin-bar pattern and its own wick-rejection ratio are
not independently scored (the ratio is the pattern's definition, §5); an
EMA-trend read and "price is above the EMA" are not independently scored
(the second is restating the first). Where two components would double-
count the same evidence, only the stronger of the two contributes, and
the other is logged as `suppressed_duplicate`.

**Trade decision object — full field list (restored):** `timestamp`,
`symbol`, `direction`, `mode` (§1), `mode_score` and per-component
breakdown, `regime` and `confidence` (§2), `strategy_family` (§3),
`eligibility_multiplier`, `risk_multiplier` (§3/§8, kept distinct), `base_score`,
`final_score`, `rejected_alternatives` (family + score + reason, §3),
`entry_price_requested`, `entry_price_actual_fill`, `stop_price`,
`target_price`, `expected_R`, `risk_cash`, `per_trade_risk_pct`,
`volume`, `pattern_ids` (§5/§6 instances contributing), `location_refs`
(§3/§4 structure objects contributing), `news_state` (§10), `learning_
bucket` (symbol+strategy+setup+regime+mode, below), `sample_count_at_
decision`, `confidence_interval_at_decision`, `outcome` (filled on
close: `win`/`loss`/`breakeven`, realized R, exit reason from §7's
priority list), `logic_version` (below), `intent_id` (§8's durable-intent
correlation).

**Learning buckets and rules (restored, five-way bucket):** buckets are
keyed by **symbol + strategy family + setup + regime + mode** — every
learning-relevant computation in this document (§1 item 1's regime
persistence excepted, which is regime-only by design) uses this exact
five-way key, so §1's dropped historical-performance component and §12's
shadow-recovery rule are consistent with one canonical bucket definition
rather than each inventing its own granularity.
- **Minimum sample:** `InpLearningMinSamples` (default 20) trades in a
  bucket before that bucket's statistics influence anything.
- **Confidence interval:** the Wilson score interval's lower bound on the
  bucket's win rate, at `InpLearningConfidenceLevel` (default `95%`), is
  the statistic actually used for any bench/recovery decision — never the
  raw point-estimate win rate alone.
- **Recency weighting:** trades are weighted by
  `exp(-age_days/InpLearningRecencyHalfLifeDays)` (default half-life 30
  days) when computing the bucket's win rate.
- **Bounded influence:** any learning-derived adjustment (bench/recovery,
  risk multiplier) is capped at `±InpLearningMaxInfluencePercent` (default
  `20%`) of its baseline value — no learning signal can swing a decision
  beyond this bound.
- **Auto-reset by EA version, no cross-version reuse:** every stored
  trade/shadow-trade outcome is tagged with `logic_version` (the EA's own
  build/logic version at collection time); a version change invalidates
  (excludes from all statistics) every record tagged with an older
  version — no bucket ever mixes statistics across a logic change.
- **Bench-after-sample-and-loss:** a bucket is benched (§3 blocks it) once
  it has `≥ InpLearningMinSamples` trades **and** its Wilson lower-bound
  win rate falls below `InpLearningBenchThreshold` (default `35%`) **and**
  its net realized R over that sample is negative — all three conditions
  required, not sample count alone.
- **Human-readable reason:** every bench/recovery event logs a plain-text
  reason string (sample count, Wilson lower bound, net R) alongside the
  numeric fields, for journal review.

**Journal/learning separation:** the trade journal (raw `TradeDecision`
records) is the single source of truth; the learning-bucket statistics
above are a derived, recomputable view over the journal — never a
separately-mutated store that could drift from the journal's own record.

### 10. News system (master prompt §15, `NEWS_INTEGRATION_SPEC.md`)

**This section's full content is restored here (resolves round 3's
finding 1 — the round-3 revision reduced this to a single baseline
correction, deleting the provider architecture and policy that
`NEWS_INTEGRATION_SPEC.md` requires as a Phase 2 deliverable).**

**Markets:** Metals use news controls — MT5 Economic Calendar as the
primary structured live source, historical CSV/SQLite for deterministic
backtests, and an optional, secondary, cached Fair Economy adapter.
Synthetic indices use `NullNewsProvider` — no macroeconomic event
direction or blackout logic applied.

**Provider interface (fields, verbatim from `NEWS_INTEGRATION_SPEC.md`):**
`event_id`, `event_name`, `currency`, `importance`, `scheduled_utc`,
`scheduled_server_time`, `scheduled_botswana_time`, `previous`,
`forecast`, `actual`, `revision`, `source`, `retrieved_at`, `status`.

**Policy:** block new metal entries around high-impact relevant events; do
not predict event direction; do not widen stops; resume only after the
blackout and spread normalization; post-news displacement trading is
disabled until tested separately; provider failure uses the configured
fail-safe policy and is logged.

**Backtesting:** historical events stored in SQLite or CSV; no reliance on
live `WebRequest` in Strategy Tester; repeated tests must produce
identical event decisions (deterministic replay).

**Blackout window — concrete parameters (added, since §2's
`NEWS_BLACKOUT` regime consumes this directly):**
`InpNewsBlackoutBeforeMinutes` (default 15) before `scheduled_server_
time`, `InpNewsBlackoutAfterMinutes` (default 15) after, extended if
spread has not normalized to within `InpMaxSpreadATRMultiple` (§2) by the
nominal end of the window.

**Baseline correction:** V6.37's `InpNewsHourServer`/`InpNewsMinuteServer`
inputs (source 190–191) are manually-entered broker-server HH:MM values
overwritten onto the current server date (source 7260–7265) — not a
computed "offset"; described here as exactly that.

### 11. Required architecture and roadmap alignment (master prompt §22–23)

- `StateManager`: owns all persisted state per §8's two-namespace schema.
  **Test boundary:** given a persisted snapshot and a simulated restart,
  every dependent module reads back the exact pre-restart values for its
  own namespace; a schema-version mismatch triggers the targeted
  migration (§8), not a blanket reset, and this is directly assertable.
- `SwingEngine`/`MarketStructure`: computes swing pivots (the one
  predicate defined in §6, reused by §2/§4/§5/§6 identically), range
  boundaries, equilibrium, **and** canonical BOS/CHoCH break-event
  detection/labeling — all as one function's output, exposed via one
  accessor consumed by `StrategyRouter` (trading) and `StructureVisuals`
  (drawing, corrected module name — master-prompt §22 assigns candlestick/
  chart-pattern drawing to a separate `PatternVisuals` module; this
  accessor is `StructureVisuals`'s input specifically). **Test boundary:**
  given a fixed price series, `StrategyRouter` and `StructureVisuals` both
  reading the same pivot/range/equilibrium/BOS-CHoCH output is directly
  assertable by equality in a unit test.
- `StrategyRouter`: owns §3's eligibility/scoring only. `ConflictResolver`:
  owns only the final tie-break given `StrategyRouter`'s output. **Test
  boundary:** each is independently deterministic given a fixed input, per
  §3.
- `RiskManager`/`DrawdownController`/`EquityPeakManager`/
  `DailyWeeklyLimits`: consume `StateManager`'s persisted risk baseline.
  **Test boundary:** given a persisted baseline and a simulated tick/
  restart sequence, the computed daily/weekly loss percentage matches
  §8's formula exactly at every step.
- `OrderManager`/`PositionManager`: implement §8's durable-intent
  protocol. **Test boundary:** given a simulated crash at each of (a)
  before submission, (b) after broker acceptance but before local ticket
  update, and (c) after a subsequent close, restart-time reconciliation
  (live state + history lookup) correctly classifies each case.

Phase 3 (Common core) is the next task branch, contingent on
`claude/task-001-baseline-audit` reaching an approved/merged state with
citations re-verified against `main`.

### 12. Contradiction resolution ledger

1. **V8.11 chart-mark vs. traded structure** → §11: one
   `SwingEngine`/`MarketStructure` source, including canonical BOS/CHoCH
   labeling, consumed identically by `StrategyRouter` and
   `StructureVisuals`.
2. **V6.37 Rotation vs. Volatility-Expansion regime routing** → §3: Range
   Rotation eligible in `RANGING`, not in `VOLATILITY_EXPANSION_*`.
3. **V6.37 stop-floor/cap conflict** → §8's fully-defined preflight
   equations, with periodic recheck against the rolling median, not
   attach-time only.
4. **V8.11 momentum vs. expansion gate** → §2/§3: directional-regime-
   conditioned eligibility with an explicit no-chase bar count.
5. **V8.11 restart reconstruction** → §8/§11: `StateManager`'s persisted,
   versioned, two-namespace state; §8's durable-intent protocol with
   broker-visible correlation and history-based reconciliation; §8's
   targeted (not blanket) schema-migration rule.
6. **V8.11 daily-limit anchor/reset semantics** → §8: persisted baseline,
   period-change loss formula, deterministic deal-history cash-flow
   rebasing, single-clock boundary detection.
7. **Persistence-key safety** → §8's two namespaces: symbol+magic+
   account+server for per-instance state; account+server only
   (deliberately unpartitioned by magic/symbol) for account-wide state,
   guarded by the compare-and-set concurrency rule.
8. **V8.11 oldest-first/always-CHoCH chart-mark artifacts** → resolved by
   item 1's single structure source.
9. **Netting vs. hedging account-mode support** → **hedging-mode only,
   full stop, no promised future phase.** The engine validates and
   requires a hedging-mode account at `OnInit` and refuses to run
   otherwise; netting-account support, if ever wanted, is a separate,
   fully-specified task proposed on its own merits.
10. **V6.37 daily-limit symbol/magic scope** → §8's clarified scoping: 1%
    caps are own-magic; 2%/4% loss caps are account-wide by measurement
    but own-magic by closing action — stated precisely, not a bare
    "account-wide" claim applied to both.
11. **Completed-candle enforcement, project-wide** → the logical-index
    convention (Data conventions, above) applies to **every** price-
    reading function in this document — regime classification, FVG/OB/
    liquidity detection, and every strategy signal path, not only
    candlestick/chart-pattern/swing engines — one rule, stated once, used
    everywhere; consistent with §6's corrected `EXPIRED`-reachable state
    graph.
12. **Market-signal/deal restart reconciliation** → §8's durable-intent
    protocol: a broker-visible comment-tagged intent ID, reconciled on
    restart against both live state and `HistorySelect` history, closing
    the crash-window gap between submission and local persistence.
13. **V8.11 range visual/trading semantics** → item 1's shared structure
    source explicitly includes range boundaries and equilibrium as part of
    its one computed output.
14. **V6.37 FVG semantics mixing `InpStructureSwingDepth`/
    `InpFractalDepth`** → §4: the FVG path uses the single canonical
    `SwingEngine` depth definition, not two independently-tunable inputs.

## Files affected

Modified `TASK-002_PHASE2_SPECIFICATION.md`; modified
`09_HANDOVERS/codex_to_claude/TASK-002_review.md` (round 3's review,
committed alongside this response, per the established pattern of
committing the reviewer's file together with the fix that responds to
it). No file under `01_BASELINE/` is touched. No `03_SOURCE_CODE/` files
are created.

## Out of scope

- Any `.mqh`/`.mq5` implementation code — Phase 3+.
- Per-strategy `STRATEGY_SPECIFICATION.md` instances, and the chart
  patterns explicitly deferred in §6 (triangles, rectangles, flags,
  pennants, wedges, channels) — each is Phase 5 work using §6's shared
  framework, not an open Phase 2 gap, and §3's routing tables no longer
  reference them as eligible until they are formalized.
- Resolving TASK-001's merge status.
- Any claim of compilation, testing, or proven correctness.

## Risks

- **Dependency on an unmerged branch** — re-verify citations against
  `main` once TASK-001 merges.
- **No further independent review is available for this document.** Every
  formula below has been hand-recomputed at its stated boundary values by
  the author of this revision, but that is a weaker guarantee than an
  independent reviewer's check, and §16 below states this plainly rather
  than implying a review-equivalent level of confidence.
- **First-pass numeric defaults need Phase 4/5 calibration** — every
  formula is implementable as written; the specific default constants are
  starting points for calibration, not final tuned values.
- **Specification-implementation drift** — Phase 3 code must be checked
  against this document's actual formulas during implementation, not
  against a summarized recollection of them.

## Test plan

1. Every §23 Phase 2 deliverable has a section with actual formulas, not
   requirement lists — §0's map.
2. Every contradiction across all three review rounds appears in §12 with
   a decision referencing a mechanism actually defined elsewhere in this
   document (re-checked item by item against round 3's finding 13 list:
   items 1/8/10/11/12 specifically re-verified against their now-restored
   or newly-added referenced mechanisms above).
3. Every numeric limit in `RISK_POLICY.md` is restated as binding in §8,
   including the previously-missing martingale/grid/averaging-down,
   broker-min-volume-rejection, `OrderCalcProfit` cross-check, symbol-
   validation, no-stop-widening, and full intraday-boundary rules.
4. The V8.11 sweep/shift/final-stop formula is stated normatively in §4
   itself (pool `4..min(copied-2,4+max(10,InpSweepLookback))`, shift
   `2..min(copied-2,2+max(3,InpShiftLookback))`, and the full buffer/
   floor/cap/normalize/recompute transformation chain), not merely
   referenced or left to the Test plan.
5. Hand-recomputation of every corrected formula at its boundary values:
   - Regime confidence: expansion at `E=1` → `1.0`; compression at `E=0`
     → `1.0`; trend at `T_final=1` → `1.0`; ranging at `T_final=0` →
     `1.0`, at `T_final=InpTrendThreshold` → `0.0`.
   - Per-position risk: price move `1.00`, tick size `0.01`, tick value
     `1`, one lot → `risk_cash = 1.00 × (1/0.01) × 1 = 100` (matches the
     broker-cash loss Codex's finding-8 example required, correcting the
     prior formula's `1`).
   - Daily loss: a position at `-1000` unchanged since the boundary now
     contributes `0` to `daily_loss_pct` (equity unchanged since boundary),
     correcting round 3's finding-9 example.
6. Mode-router circularity check: trace the pipeline in §1 and confirm no
   mode-score component reads a value that itself depends on the selected
   mode or on a scored trade candidate.
7. Compression-timing check: confirm the two-entry-opportunity explanation
   in §3 does not require retest after a regime reclassification for the
   gated early-breakout candidate specifically (retest-optional override
   stated explicitly for that candidate only).

## Acceptance criteria

- [x] Every §23 Phase 2 deliverable has a section with actual formulas.
- [x] Scoring, `TradeDecision`, learning-bucket, and news-provider content
      — deleted in round 3 — is restored and expanded here.
- [x] The mode router's candidate-dependency circularity is removed by
      the three-stage pipeline in §1.
- [x] Per-position and aggregate risk formulas are dimensionally correct
      and connected to the 1%/2%/4% caps; daily/weekly loss formulas
      measure actual period equity change, not absolute floating P/L.
- [x] Every binding `RISK_POLICY.md` rule is restated normatively in §8.
- [x] Chart-pattern routing in §3 references only patterns actually
      formalized in §6; the remaining patterns are explicitly deferred,
      not silently assumed.
- [x] Short-side exit formulas are stated explicitly alongside long-side.
- [x] Every ledger entry references an actually-defined mechanism.
- [ ] Independent review — **not available; Codex's review budget for
      this task is exhausted after round 3.** See §16.

## Rejection criteria

This revision would be rejected on the same technical grounds any prior
round would have been: a formula stated as "corrected" that does not
actually hold when recomputed, a state machine with an unreachable or
missing transition, or a routing/ledger reference to a mechanism that is
not actually defined elsewhere in this document. Since no independent
reviewer will check this, that verification burden now falls on whoever
implements Phase 3 against this document — any Phase 3 code that finds a
formula here does not hold as written should treat that as a specification
defect to be corrected in a dated addendum, not silently worked around.

## Implementation notes

This revision restores all content round 3 found deleted, removes the
mode-router's candidate-dependency cycle by moving candidate-quality
checks to a post-hoc consistency check and to §9's own scoring, corrects
the per-position risk formula's missing tick-size division and its
unsigned-distance error, rewrites the daily/weekly loss formulas to
measure period-equity change via deterministic deal-history cash-flow
detection, adds the missing short-side exit formulas, narrows §6's
chart-pattern scope to what is actually formalized and updates §3's
routing tables to match, and re-verifies every baseline citation round 3
flagged directly against source before restating it.

## Commands run

`git checkout claude/task-001-baseline-audit && git checkout -b
claude/task-002-phase2-specification` (round 1); this revision edits the
same file, same branch.

## Compiler result

Not applicable — no code in this task.

## Test results

Documentation self-verification (Test plan above): all seven items
checked directly against this revision's own content, including hand-
recomputing every corrected formula at its stated boundary values.

## Commit

Round 1: `cc58fa8`. Round 2: `7842083`. Round 3: `bf84f4d`. This revision
(round 4): the commit immediately following `bf84f4d` on this branch — see
`git log` rather than a hash written into this file before that commit
exists (this avoids the self-referential staleness round 3's finding 16
flagged in the prior revision's Commit section).

## Reviewer

Round 1: CHANGES REQUESTED. Round 2: CHANGES REQUESTED. Round 3
(`bf84f4d`): CHANGES REQUESTED — sixteen findings; see this document's
inline corrections throughout §1–§12 for the complete, item-by-item
response. **No round 4 review will occur** — Codex's review budget for
this task is exhausted. This document's disposition is therefore
self-certified against round 3's findings, not independently confirmed.

## Final decision

**Not independently approved — no further independent review is
available.** Per the user's explicit instruction, Phase 3 begins after
this revision regardless. This document represents a genuine, thorough
correction pass against every one of round 3's sixteen findings, verified
by hand recomputation where a formula was in question, but it carries the
residual risk stated in §16/Risks: nothing here has been checked by a
party other than its author. Phase 3 implementers should treat any
formula in this document that fails to hold under direct implementation
as a specification defect to raise immediately, not as an implementation
detail to silently paper over.
