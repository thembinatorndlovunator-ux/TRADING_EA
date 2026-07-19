# Baseline Comparison: SmartCoreEngine V6.37 vs. NdlovuSMC V8.11

Synthesizes `baseline_v637_audit.md` and `baseline_v811_audit.md` per
`00_MASTER_PROMPT_FOR_CLAUDE.md` section 4 "Comparison." No winner is
selected by code size or comment density — this is a feature/risk matrix to
inform which modules get reused, retired, or isolated-tested in the new
`Themba Adaptive Intraday Engine`. Nothing here claims compilation,
correctness, or profitability; both source audits are static reads only.

## Orphaned set file — resolved

`01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt` does **not** belong to
either baseline. Evidence:

- Its keys have no `Inp` prefix (`RiskPercent=0.5`, `MagicNumber=123456`,
  `MaxDailyLoss=5.0`), but every actual input in both baselines is declared
  with an `Inp` prefix as part of the real MQL5 variable name
  (`InpRiskPercent`, `InpMagicNumber`, etc. in both files). A genuine `.set`
  export from either EA would show the `Inp`-prefixed name as the key —
  this file never does, for any of its 40 keys.
- `MagicNumber=123456` matches neither V637's default (`312003`, line 64)
  nor V811's default (`800001`, line 48).
- It uses bracketed INI sections (`[SMC]`, `[ChartPatterns]`, `[SRBounce]`,
  `[Learning]`, `[TrailTiers]`, `[PartialClose]`, `[Stagnation]`); native MT5
  `.set` files are always flat `Key=Value` with no sections at all.
- Its section names — `SMC`, `ChartPatterns`, `SRBounce`, `Learning` — map
  suggestively onto the *planned new EA's* module names in
  `00_MASTER_PROMPT_FOR_CLAUDE.md` section 22 (`SMCStrategy.mqh`,
  `ChartPatternEngine.mqh`, `SRBounceStrategy.mqh`, `LearningStatistics.mqh`),
  not onto either baseline's actual function/input organization. Neither
  baseline has a `ChartPatternEngine`-equivalent module at all (chart-pattern
  detection per `CHART_PATTERN_SPEC.md` doesn't exist in either V6.37 or
  V8.11 — see "unverified/absent functionality" below).

**Conclusion:** this file is best treated as an early draft/target parameter
sketch for the new architecture (or a generic template written before either
baseline's real input names were finalized), not a usable configuration for
either baseline EA. It should not be loaded into either baseline during
testing. It may still be useful later as a rough starting point for the new
EA's own default `.set` file, once the corresponding modules actually exist
— but that is a future decision, not one this audit makes.

## Verified functionality (present and working as designed, per static read)

| Capability | V6.37 | V8.11 |
|---|---|---|
| Fractal/swing detection | Yes — `IsSwingHigh/Low`, depth-configurable | Yes — `FindLastTwoSwings`, `InpSwingDepth` |
| Support/resistance with touch-decay scoring | Yes — `FindSRZone` | Yes (simpler) — `FindClusterBoundary`, touch-count only |
| BOS/CHoCH structural break detection | Yes — `AnalyzeStructure`, one consistent definition | Yes for `StructureTrend`/M30 direction, but **a second, disconnected definition** exists only for chart marks (`BuildStructureMarks`) — see Contradictory definitions |
| Order blocks | Yes — M30, with SR confluence requirement | Yes — two-stage M15→M5 refinement, single shared accessor `ActiveOB()` |
| FVG detection with "fresh/untouched, first-return-only" rule | Yes — enforced, verified | Yes — enforced, verified |
| Trendlines | Yes — three independent implementations (see Duplicated concepts) | Deliberately absent by design (header comment: SMC treats diagonal lines as "edgeless") |
| Premium/discount/equilibrium/OTE | Yes — hard gate with 4 documented escape hatches | Yes (as PD bands feeding `LocationOK`), simpler, no OTE-specific pocket |
| Range cycle / rotation | Yes — both, with a regime-routing contradiction (see below) | Not present as a named strategy (clustered SR bounce covers similar ground) |
| Basket/multi-leg entries | No — single-position pilot/add-on model instead | Yes — 1–4 legs, risk-budget-split sizing (core math correct, fallback path breaks it — see Contradictions) |
| Laddered take-profits | Partial — staged TP1→TP3→runner extension, not fixed R-ladder | Yes — fixed `ladder[0..3]` at 1.0/1.5/2.0/2.5R, defaults use only first 2 rungs |
| Giveback guard | Yes — `GuardOpenProfits`, arm/tolerance percent model | Yes — `ManageBasket` giveback block, arm/floor R model |
| Profit-lock floor (raise SL as % of distance-to-TP covered) | Yes — distinct from giveback guard | No equivalent found |
| Time exit | No fixed universal time exit (structural/momentum-based instead) | Yes — hard 45-minute wall-clock cutoff, uniform across all setup types |
| Drawdown lock | No dedicated equity-peak lock (giveback guard + daily limits instead) | Yes — but restart-vulnerable (see Contradictions) |
| Baskets/trades-per-day cap | Daily money/percent limits only, no trade-count cap found | Yes — `InpMaxDayBaskets` |
| Journal/learning system | Yes — CSV journal, per-strategy and per-strategy-per-regime win-rate adjustment | **None** — explicitly no journal files by design (header comment, verified by full-file grep for `FileOpen`) |
| Regime classification feeding strategy routing | Yes — 3-way (Trending/Ranging/Volatile Expansion), used to block/bench setups | No regime classifier — routing is H1/M30 direction + PD location only |
| News handling | Yes — NFP heuristic + synthetic-index bypass, both fragile (see Contradictions) | Manual `HH:MM` text windows only, off by default, no economic-calendar link at all |
| Candlestick confirmation | Yes, embedded per-strategy | Yes — shared pin-bar/engulfing helpers reused across 4 setup builders |
| Chart-pattern detection (double top, H&S, triangles, etc., per `CHART_PATTERN_SPEC.md`) | **Not present** | **Not present** |

## Unverified / absent functionality

- Neither baseline implements anything resembling the new project's planned
  `ChartPatternEngine` (double tops, triangles, flags, wedges, etc.) — this
  is greenfield work for the new EA, not something to port from either
  baseline.
- Neither baseline's actual live/demo trading behavior has been observed —
  both audits are static reads only; every "FACT" label describes code as
  written, not confirmed runtime behavior.
- Whether V637's five-gate signal funnel or V8.11's basket-sizing model
  produce a healthy trade cadence or starve/overexpose the account under
  real market conditions is unverified in either case — both audits flag
  this explicitly as requiring backtest evidence.

## Duplicated concepts

- **Trendlines, tripled within V6.37 alone**: `EvaluateSRChannel`,
  `EvaluateTrendBreaker`, and the dedicated `BuildTrendlineTouchSignal`/
  `BuildTrendlineBreakRetestSignal` pair are four separate "what counts as a
  trendline touch/break" implementations with different swing-depth inputs.
  V8.11 has none, by design.
- **"Drawdown from peak," three unrelated definitions within V8.11 alone**:
  a persisted display-only `g_peak_dd`, a restart-vulnerable `g_current_dd`/
  `g_peak_balance` pair that actually gates new baskets, and a same-tick
  `RiskBudgetCash` throttle using `MathMax(balance,equity)` — none reference
  each other.
- **Giveback guard, conceptually shared, differently parameterized**: V6.37
  arms at 1.25R and tolerates 60% giveback of peak; V8.11 arms at 0.8R and
  requires falling back to 0.1R floor. Different philosophies (percentage-
  of-peak vs. absolute-R-floor) solving the same problem — a natural
  candidate for an isolated A/B experiment in the new engine rather than
  picking one by inspection.
- **Fractal/swing depth, fragmented within V6.37**: three independent inputs
  (`InpFractalDepth`, `InpStructureSwingDepth`, `InpTrendSwingDepth`) all
  default to 2 but a comment implies one shared definition — never enforced
  equal.

## Contradictory definitions

- **V8.11's chart-mark structure vs. trading structure are different
  algorithms.** `BuildStructureMarks` (drawing-only BOS/CHoCH/EQL/EQH) uses
  its own swing-break scan, its own lookback window, and its own tolerance —
  entirely disconnected from `StructureTrend`/`FindClusterBoundary`, which
  is what actually drives trades. The chart a user watches does not show
  the structure the EA is actually trading from.
- **V6.37's ROTATION setups are self-confirmed but regime-vetoed anyway.**
  Flagged to bypass SR/value-area gates, then silently blocked by
  `ApplyRegimeRouting` during Volatile Expansion because the setup's string
  name matches none of that gate's allow-lists.
- **V6.37's ATR-based stop floor and percent-of-price stop cap are
  different units**, never cross-validated, and can conflict on certain
  symbols/sessions, silently rejecting trades.
- **V8.11's momentum-breakout setup is explicitly exempted from the
  location gate to trade volatility expansion, then blocked entirely by a
  separate blanket expansion gate** that fires on exactly the condition the
  setup exists to catch — the sharpest internal inconsistency found in
  either file.

## Risk-management differences

| Aspect | V6.37 | V8.11 |
|---|---|---|
| Base risk per trade | 1.0%–2.0% standing budget | 1.0% "total per basket" (nominal) |
| Weak-sample risk *increase* | Yes — pilot trade explicitly allowed 5.0% actual risk (the least-confirmed trade of a new trend) vs. 1–2% standing budget | No equivalent "increase on low confidence" path found |
| Minimum-lot fallback risk cap | Two different ceilings for what is the same situation depending on *why* min-lot was forced (pilot: 5.0%; ordinary min-lot-compatibility: 2.0%/0.30% gold) | One fallback path, but it can let a single leg risk up to 2.0% instead of the intended 1.0% "total" |
| Add-on / multi-leg de-risking | `InpAddOnRiskFactor` (0.75×), sample-independent, always-on | Legs split the same fixed total-risk budget — correct when the split succeeds |
| Global stop/trailing behavior driven by a small sample | Yes — `OverallWinRate()` (min 8 trades, pooled across all strategies) adjusts stop width and trailing EA-wide | No equivalent global behavior-changing feedback (no journal at all) |
| Drawdown lock persistence across restart | Not separately audited as a named "drawdown lock" (giveback guard + daily limits serve this role) | Broken — gating variable resets to current balance on restart, silently clearing the lock's basis |
| Cross-symbol / account-level exposure governance | Daily limits appear symbol-scoped in most functions **except** `CloseAllOurPositions`'s position-closing loop (magic-number-only — see below) | None — `RiskBudgetCash` sizes off total account equity per instance with no cross-instance awareness |

## Exit-management differences

- V6.37: staged TP ladder built once at entry from initial risk, extended
  forward only if fresh M15 structure agrees (never re-derived from scratch
  mid-trade); profit-lock floor (raises SL once X% of distance-to-TP is
  covered) plus a separate giveback guard; no universal time exit.
- V8.11: fixed R-multiple ladder (1.0/1.5/2.0/2.5R, only first 2 rungs live
  under current 2-leg default); break-even at 1.0R; runner trail arms at
  1.5R (identical to the last live leg's own TP under current defaults,
  making the trail dead code as shipped); giveback guard checked before the
  hard 45-minute time exit and before direction-flip exit.
- Both giveback guards are genuinely enforced, verified by reading the exit
  code, not merely comment-claimed.
- V8.11's hard wall-clock time exit is a design choice absent from V6.37;
  whether a volatility/structure-conditioned time exit (as the new engine's
  spec requires — "evidence-based, not universally fixed at 45 minutes")
  performs better is exactly the kind of isolated experiment the new engine
  should run rather than inheriting either baseline's approach uncritically.

## News limitations

- V6.37's NFP logic is pure calendar arithmetic (`day_of_week==5 && day<=7`)
  with no actual economic-calendar check and an explicitly-flagged-by-its-
  own-comment unverified server-time-to-NY-time assumption. Synthetic-index
  bypass relies on a narrow, hardcoded symbol-name substring match that
  silently mis-routes on unrecognized broker naming.
- V8.11's news filter is manual `HH:MM` text windows, current-day only, off
  by default, with no recurring schedule and no economic-calendar
  integration at all — blank window strings are silently treated as "no
  block," not "unknown," which is a false-sense-of-security trap if enabled
  without real values.
- **Neither baseline has anything resembling the new engine's planned
  `MT5CalendarProvider`/`FileCalendarProvider` structured news system.** This
  is greenfield work, not portable from either baseline.

## Visual strengths

- V6.37: dedicated clean-theme dashboard and TP-target drawing functions
  exist in source, but none of the 13 baseline screenshots reviewed in
  `01_BASELINE/screenshots/visual_notes.md` show a dashboard panel, pattern
  name, or chart-pattern boundary — only swing/structure markers. Whether
  the richer visual layer renders as coded is unconfirmed by the available
  screenshots.
- V8.11: `DrawZones`/`DrawWorkingChart` are verified to draw from the exact
  same globals the trade logic consumes for OB/FVG/PD/range — a genuine
  strength for order blocks, FVGs, and range boundaries. The BOS/CHoCH/EQL/
  EQH marks are the one exception (drawing-only, disconnected from trading
  logic — see Contradictory definitions).

## Journal strengths

- V6.37 has a real (if imperfect) learning journal: 44-column CSV, per-
  symbol scoped, minimum-sample gating before adjusting scores, a bench-
  losing-strategies safety valve. Its "BestStrategySetup" column is
  corrupted by a data-integrity bug (stores a summary-of-summaries instead
  of the real setup name) — this does not affect the win/loss counters that
  actually drive score adjustment, only downstream analytics.
- V8.11 has no journal at all, by design — nothing to corrupt, but also
  nothing to learn from; all scoring is static per-input.

## Failure modes (most operationally significant, both files)

1. **V6.37 — `CloseAllOurPositions`'s position-closing loop filters only by
   magic number, not symbol** (unlike every other position-scanning
   function in the file, and unlike its own sibling pending-order loop
   three lines below). With the default shared magic number, a daily-loss
   lock on one symbol force-closes positions on every symbol sharing that
   magic number in a multi-symbol deployment — including unrelated,
   profitable trades. **Highest-severity finding in the V637 audit.**
2. **V8.11 — a restart while a basket is open permanently disables every
   dynamic risk control** (break-even, runner trail, giveback guard, time
   exit, direction-flip exit) for that basket's remaining lifetime, while
   the dashboard reports "Basket: flat," hiding the fact that real,
   unmanaged exposure is still open. **Highest-severity finding in the V811
   audit**, and arguably the single most concerning finding across both
   baselines — it silently strips all protection with no visible signal to
   the operator.
3. Both files have at least one gate that blocks the exact condition a
   specific setup was built to trade (V6.37's ROTATION-vs-regime-router;
   V8.11's momentum-breakout-vs-expansion-filter) — a shared pattern of
   "gates not jointly reasoned through," not a coincidence, and worth a
   systematic gate-interaction test in the new engine's `ConflictResolver`.

## Reusable modules (concepts worth carrying forward, re-implemented cleanly)

- V6.37's SR touch-decay scoring, second-distinct-retest confirmation
  requirement, and dealing-range lock/persist-until-break behavior are
  well-reasoned and independently verified to work as documented.
- V6.37's minimum-sample-gated, bench-with-safety-valve journal-learning
  pattern is a reasonable starting point for the new engine's
  `LearningStatistics.mqh` — provided the self-perpetuating regime-bench
  lockout (a benched strategy can never re-accumulate the data needed to
  un-bench itself) is fixed before reuse.
- V8.11's two-stage M15→M5 order-block refinement with a single shared
  accessor (`ActiveOB()`) consumed identically by both drawing and trading
  code is a clean pattern worth reusing directly for the new engine's
  `OrderBlockEngine.mqh`.
- V8.11's "first-return-only, untouched" FVG rule and its shared
  pin-bar/engulfing helper functions (one definition, four call sites) are
  clean, verified, and directly portable patterns.
- Both giveback-guard designs (percent-of-peak vs. absolute-R-floor) are
  candidates for a head-to-head isolated experiment rather than either being
  assumed superior.

## Modules to retire (not carry forward as-is)

- V6.37's four vestigial, never-called functions (`HasEntryCHOCH`,
  `HasFibEMAConfluence`, `FindLatestFVG`, `FindLatestOrderBlock`) — dead
  code from earlier refactors.
- V6.37's three-times-duplicated trendline logic — consolidate to one
  definition if trendlines are carried into the new engine at all.
- V8.11's `BuildStructureMarks` chart-mark logic as currently written —
  either delete it or rewire it to read from the same structure functions
  that actually drive trades, so the chart stops showing a disconnected
  second opinion.
- The orphaned `SmartCore_v3_Tuned.set.txt` should not be loaded into
  either baseline for any testing (see resolution above).

## Modules needing isolated experiments before reuse

- Giveback-guard parameterization (percent-of-peak vs. absolute-R-floor).
- Fixed wall-clock time exit (V8.11's 45 minutes) vs. a
  volatility/structure-conditioned time exit, per the new engine's own
  spec requirement that time exits be "evidence-based, not universally
  fixed."
- Regime-based strategy benching with a hard zero-score lock — needs a
  guaranteed un-bench/re-evaluation path before reuse, given the
  self-perpetuating lockout identified in V6.37.
- Pilot-trade risk escalation on unconfirmed trends (V6.37) — the new
  engine's risk policy explicitly requires risk to never increase on weak
  evidence; this pattern should not be ported without redesign.
- Basket/multi-leg sizing — the new engine's `RISK_POLICY.md` disables
  multi-leg baskets by default until independently proven; V8.11's minimum-
  lot fallback path (which can silently double intended basket risk) is a
  concrete example of why that default caution is warranted.
