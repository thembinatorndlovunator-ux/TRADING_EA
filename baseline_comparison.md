# Baseline Comparison: SmartCoreEngine V6.37 vs. NdlovuSMC V8.11

**Independent Codex review completed** (`09_HANDOVERS/codex_to_claude/TASK-001_review.md`,
disposition: changes requested) — corrections are integrated throughout this
document and in both underlying audit files, and are marked inline where
they occur.

Synthesizes `baseline_v637_audit.md` and `baseline_v811_audit.md` per
`00_MASTER_PROMPT_FOR_CLAUDE.md` section 4 "Comparison." No winner is
selected by code size or comment density — this is a feature/risk matrix to
inform which modules get reused, retired, or isolated-tested in the new
`Themba Adaptive Intraday Engine`. Nothing here claims compilation,
correctness, or profitability; both source audits are static reads only.

## Orphaned set file — not usable for either baseline; provenance unresolved

**Corrected per independent Codex review** — the original version of this
section overreached by calling the provenance "resolved" and attributing it
to the planned new architecture. The evidence only supports the narrower
conclusion below; independent review found no support for the new-engine
attribution and flagged the "resolved" framing as an internal inconsistency
against `01_BASELINE/inventory.md` and `01_BASELINE/setfiles/IDENTITY.md`,
which correctly describe it as unresolved.

`01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt` is **not a usable native
preset for either reviewed baseline.** Evidence:

- It contains 79 key/value lines across 11 INI-style bracketed section
  headings (`[Common]`, `[Filters]`, `[Indicators]`, `[SMC]`, `[Protection]`,
  `[PartialClose]`, `[Stagnation]`, `[TrailTiers]`, `[Learning]`,
  `[ChartPatterns]`, `[SRBounce]`) — corrected from an earlier miscount of
  "40 keys." Native MT5 `.set` files are always flat `Key=Value` with no
  sections at all, so the bracketed-section structure alone rules out a
  genuine `.set` export from any MQL5 EA.
- None of its keys exactly matches an input-variable name in either baseline.
  Every actual input in both baselines is declared with an `Inp` prefix as
  part of the real MQL5 variable name (`InpRiskPercent`, `InpMagicNumber`,
  etc.); this file's keys never carry that prefix (`RiskPercent=0.5`,
  `MagicNumber=123456`, `MaxDailyLoss=5.0`, etc.).
- `MagicNumber=123456` matches neither V637's default (`312003`, line 64)
  nor V811's default (`800001`, line 48).
- Neither baseline source contains a parser for this file's format or
  references any of its distinctive keys.

**What the evidence does *not* support:** it does not follow that this file
belongs to the planned new engine architecture. Its section names (`SMC`,
`ChartPatterns`, `SRBounce`, `Learning`) are suggestive of module names in
`00_MASTER_PROMPT_FOR_CLAUDE.md` section 22, but suggestive naming overlap
is not evidence of origin — `SmartCore_v3` in the filename could equally
refer to an absent third EA version never delivered into this repo, or a
manually drafted configuration unconnected to any of these codebases.
**Provenance remains genuinely unresolved** unless source history or the
original author is located; this document does not claim to resolve it.

It should not be loaded into either baseline during testing regardless of
its origin. Whether it has any future value as a starting point for the new
engine's own default `.set` file is a separate, later decision this audit
does not make.

## Verified functionality (present in source, per static read)

**Wording corrected per independent review:** "present and working as
designed" overstated what a static read alone can establish. Nothing here
has been compiled or executed — this table reports what is genuinely
present and internally consistent in the source, not confirmed runtime
behavior.

| Capability | V6.37 | V8.11 |
|---|---|---|
| Fractal/swing detection | Yes — `IsSwingHigh/Low`, depth-configurable | Yes — `FindLastTwoSwings`, `InpSwingDepth` |
| Support/resistance with touch-decay scoring | Yes — `FindSRZone` | Yes (simpler) — `FindClusterBoundary`, touch-count only |
| BOS/CHoCH structural break detection | Yes — `AnalyzeStructure`, one consistent definition | Yes for `StructureTrend`/M30 direction, but **a second, disconnected definition** exists only for chart marks (`BuildStructureMarks`) — see "Contradictions and unresolved policy questions" |
| Order blocks | Yes — M30, with SR confluence requirement | Yes — two-stage M15→M5 refinement, single shared accessor `ActiveOB()` |
| FVG detection with "fresh/untouched, first-return-only" rule | Yes — enforced, verified | **Overstated, corrected in second-pass review** — partially enforced: touch scan omits the trigger bar and there is no persistent consumed-flag, so a cached gap can in principle be reconsidered on a later bar (see `baseline_v811_audit.md`'s "M5 FVG" section) |
| Trendlines | Yes — three independent implementations (see Duplicated concepts) | Deliberately absent by design (header comment: SMC treats diagonal lines as "edgeless") |
| Premium/discount/equilibrium/OTE | Yes — hard gate with 4 documented escape hatches | Yes (as PD bands feeding `LocationOK`), simpler, no OTE-specific pocket |
| Range cycle / rotation | Yes — both, with a regime-routing policy question for Rotation (see below; **wording corrected in second-pass review** — verified reachable behavior, not a confirmed contradiction) | Not present as a named strategy (clustered SR bounce covers similar ground) |
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
- Whether V637's multi-stage gate/score-modifier signal pipeline (**wording
  corrected in second-pass review** — not a literal five-gate serial-AND;
  see `baseline_v637_audit.md`'s "Large number of filters" section) or
  V8.11's basket-sizing model produce a healthy trade cadence or starve/
  overexpose the account under real market conditions is unverified in
  either case — both audits flag this explicitly as requiring backtest
  evidence.

## Duplicated concepts

- **Trendlines, tripled within V6.37 alone**: `EvaluateSRChannel`,
  `EvaluateTrendBreaker`, and the dedicated `BuildTrendlineTouchSignal`/
  `BuildTrendlineBreakRetestSignal` pair are four separate "what counts as a
  trendline touch/break" implementations with different swing-depth inputs.
  V8.11 has none, by design.
- **"Drawdown from peak," two peak-based definitions plus one non-peak sizing
  haircut within V8.11 (recharacterized in tenth-pass review — `RiskBudgetCash`
  is not a third peak-drawdown definition)**: a display-only `g_peak_dd`,
  persisted outside Strategy Tester only (**qualifier added in sixth-pass
  review**); a restart-vulnerable `g_current_dd`/`g_peak_balance` pair that
  actually gates new baskets; and, separately, `RiskBudgetCash`'s same-tick
  `equity - MathMax(balance,equity) * InpMaxDrawdownPercent/100` haircut,
  which references neither peak value and is not itself a drawdown-from-peak
  comparison — under shipped defaults it returns ~0.8% of equity per basket,
  not the nominal 1% the input name suggests. None of the three reference
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

## Contradictions and unresolved policy questions

**Heading broadened in sixth-pass review** — this section previously mixed
confirmed contradictions with items whose own text says they are *not*
confirmed contradictions (the ROTATION bullet below), a taxonomy mismatch.
The heading now reflects both categories; each bullet still states its own
correct classification individually.

- **V8.11's chart-mark structure vs. trading structure are different
  algorithms.** `BuildStructureMarks` (drawing-only BOS/CHoCH/EQL/EQH) uses
  its own swing-break scan, its own lookback window, and its own tolerance —
  entirely disconnected from `StructureTrend`/`FindClusterBoundary`, which
  is what actually drives trades. The chart a user watches does not show
  the structure the EA is actually trading from.
- **V6.37's ROTATION setups are self-confirmed but blocked during Volatile
  Expansion regime by `ApplyRegimeRouting` anyway** (setup's string name
  matches none of that gate's allow-lists). **Characterization corrected in
  second-pass review:** this is a verified, reachable policy question, not a
  confirmed contradiction — "self-confirmed" was documented to mean
  bypassing value-area/SR confirmation gates specifically, not regime
  policy. The **V6.31 Rotation design note** (name corrected in fifth-pass
  review, was mislabeled "Volatile Expansion design note") doesn't itself
  say Rotation should be allowed to trade during Expansion, so this may be
  intentional mean-reversion exclusion rather than an oversight — source
  alone can't settle which. **Dashboard-visibility condition corrected precisely,
  fourth-pass review (stated wrong in two prior drafts):** the router's
  rejection reason only reaches the dashboard when **no candidate survives
  in either direction that tick**, not "Rotation was the sole candidate in
  its own direction" — this is a global, not per-direction, condition. No
  claim is made about how often it occurs. It never reaches the journal
  regardless. Needs a specification decision (should Rotation trade during
  Expansion?) and backtest evidence, not a fix applied by assumption.
- **V6.37's ATR-based stop floor and percent-of-price stop cap are converted
  to the same price-distance unit and ARE cross-validated at runtime**
  (**recharacterized in tenth-pass review — was previously described as
  "different units, never cross-validated"**); the real gap is the absence
  of any preflight check that the floor fits under the caps for the
  attached instrument, so the two can still legitimately conflict on
  certain symbols/sessions and reject trades at runtime with no advance
  warning (the resting-limit path's own cap check also fails silently, with
  no journal row).
- **V8.11's momentum-breakout setup is exempted from the location gate to
  trade price expansion beyond value (its own `InpMomTF`, M5 default), then
  blocked by a separate blanket expansion gate keyed to `InpWorkingTF` ATR
  (M15 default) — opening framing rewritten in fourth-pass review to avoid
  first overclaiming "explicitly exempted... to trade volatility expansion"
  before conceding otherwise.** The `InpMomTF`-scale momentum-breakout
  condition and the `InpWorkingTF`-scale expansion flag that trips the
  blanket gate are related but not definitionally identical — the setup
  remains reachable for `InpMomTF`-scale breakouts below the
  `InpWorkingTF`-scale expansion threshold. This is a verified gate
  interaction confirmed by control flow (the outer gate unconditionally
  wins whenever it's true), with intent and impact otherwise unresolved —
  static review does not establish it as "the sharpest internal
  inconsistency" across either file — that's an empirical question about
  how often the two conditions actually coincide, requiring backtest
  evidence.

## Risk-management differences

| Aspect | V6.37 | V8.11 |
|---|---|---|
| Base risk per trade | 1.0%–2.0% standing budget | 1.0% "total per basket" (nominal) |
| Weak-sample risk *increase* | Yes — pilot trade explicitly allowed 5.0% actual risk (the least-confirmed trade of a new trend) vs. 1–2% standing budget | No equivalent "increase on low confidence" path found |
| Minimum-lot fallback risk cap | Two different ceilings for what is the same situation depending on *why* min-lot was forced (pilot: 5.0%; ordinary min-lot-compatibility: 2.0%/0.30% gold) | One fallback path, but it can let a single leg risk up to 2.0% instead of the intended 1.0% "total" |
| Add-on / multi-leg de-risking | `InpAddOnRiskFactor` (0.75×), sample-independent, always-on | Legs split the same fixed total-risk budget — correct when the split succeeds |
| Global stop/trailing behavior driven by a small sample | Yes — `OverallWinRate()` (min 8 trades, pooled across all strategies) adjusts stop width and trailing EA-wide | No equivalent global behavior-changing feedback (no journal at all) |
| Drawdown lock persistence across restart | Not separately audited as a named "drawdown lock" (giveback guard + daily limits serve this role) | **Corrected in third-pass review** — gating variable's peak-balance reference resets to current balance on restart, which can *understate* current drawdown relative to the true historical peak (conditional on how much higher that prior peak was — not an unconditional reset to zero, since floating loss at restart still shows up) |
| Cross-symbol / account-level exposure governance | **Corrected in second-pass review** — daily-limit P/L inputs (`GetTodayClosedProfit`/`GetOpenProfitForMagic`) are magic-wide, not symbol-scoped, to begin with; `CloseAllOurPositions`'s position-closing loop shares that same magic-only scope while its sibling pending-order loop is the one that's actually symbol-scoped — the two loops disagree with each other, not "everything except one loop" | None — `RiskBudgetCash` sizes off total account equity per instance with no cross-instance awareness |

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
  logic — see "Contradictions and unresolved policy questions").

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

**Ranking revised per independent Codex review** (`09_HANDOVERS/codex_to_claude/TASK-001_review.md`,
disposition: changes requested, now integrated into both audit documents).

0. **V6.37 — BLOCKER, category-topping finding: `IsBullishInsideFalseBreak`/
   `IsBearishInsideFalseBreak` read the forming, incomplete bar (`rates[0]`)
   and feed live signal evidence at roughly ten call sites** — a confirmed
   violation of the project's hard completed-candle/no-repainting rule
   (`PROJECT_RULES.md` #4–5). This is categorically more severe than the
   evidence-dependent operational risks below because it's a rule violation,
   not a risk to weigh — it blocks reuse of these two specific helpers
   outright. See `baseline_v637_audit.md`, "Completed-candle / repainting
   check." (V8.11 was independently confirmed clean of any equivalent
   forming-bar dependency in its trade-decision paths.)
1. **V6.37 — `CloseAllOurPositions`'s position-closing loop filters only by
   magic number, not symbol** (unlike the per-symbol *position-management*
   scans elsewhere in the file — **wording corrected in second-pass
   review**: `GetTodayClosedProfit`/`GetOpenProfitForMagic` are themselves
   magic-only, not exceptions to a universal rule — and unlike its own
   sibling pending-order loop three lines below). **Qualified per
   independent review:** all four daily
   thresholds default to zero (inactive out of the box), and the underlying
   P/L computation was already magic-wide rather than truly per-symbol —
   the sharper inconsistency is that the two loops in the same function
   disagree with each other regardless of which scope was intended. Still
   the most operationally dangerous *evidence-dependent* finding in the
   V637 audit.
2. **V8.11 — a restart while a basket is open disables the dynamic risk
   controls** (break-even, runner trail, giveback guard, time exit,
   direction-flip exit) for that basket's remaining lifetime, while the
   dashboard reports "Basket: flat." **Qualified per independent review,
   precision-corrected in third-pass review:** the broker-held SL/TP
   remains live regardless — but it is the *current* SL/TP (which may
   already have been modified by break-even/trailing before the restart,
   since `MoveBasketStops` can change the stop), not necessarily the
   *original* values placed at basket-open time. The daily-lock path can
   still force-close the basket —
   so this is not "every protection disappears," but the loss of all
   *dynamic* management (plus, additionally discovered, the daily basket
   cap, cooldown markers, and the live drawdown-lock's peak-balance
   reference all being restart-resettable too) remains the clearest
   capital-risk-relevant defect in either baseline.
3. Both files have at least one verified, reachable gate interaction whose
   intent and impact are unresolved from static reading alone (V6.37's
   ROTATION-vs-regime-router; V8.11's momentum-breakout-vs-expansion-
   filter). **Reframed per independent review, precision-corrected across
   third-, fourth-, and fifth-pass review (an editing leftover previously
   left a directly self-contradictory duplicate sentence here — removed):**
   neither case should be described as a setup "conflicting with its own
   stated purpose." V6.37's **V6.31 Rotation design note** (name corrected
   in fifth-pass review, was mislabeled "Volatile Expansion design note")
   never says Rotation should be allowed to trade during Expansion, so
   excluding it may be intentional, not an oversight. V8.11's momentum-
   breakout setup is not "blocked by exactly the condition it was built to
   trade" — its stated purpose (comment 2213–2218) is a premium/discount
   *location-gate* exemption for trading expansion beyond value, which the
   source does not equate with the specific, separately-defined
   `g_expansion` state; the setup's own `InpMomTF`-scale (M5 default)
   breakout condition and the blocking `InpWorkingTF`-scale (M15 default)
   expansion flag are related but not the same measurement (see
   `baseline_v811_audit.md`'s expansion section). Both are best described
   as verified, reachable gate interactions with unresolved intent and
   impact — each needs an explicit specification decision (was the
   restriction intended?) and backtest evidence (does it actually cost
   good trades?) before being treated as a defect to fix, not confirmed
   conflicts and not proven bugs.
4. **New, added by independent review — applies to both EAs:** neither file
   branches on `ACCOUNT_MARGIN_MODE`; both have netting-account defects
   (V637's add-on cap doesn't bind, risk state gets overwritten across
   merged positions; V811's leg count desyncs from actual position count,
   causing premature break-even) and V637 additionally has a hedging-mode
   ticket-association defect. See each audit's "Netting versus hedging
   account compatibility" section.
5. **New, added by independent review — applies to both EAs:** trade
   submission and modification results are not verified against the
   broker's actual result code in either file — a `true` Boolean from
   `CTrade` is treated as proof of execution. Broker filling-mode selection,
   stop/freeze-level/tick-size validation, and final `OrderCheck` are all
   incomplete in both files. See each audit's "Trade-submission result
   handling" and "Broker filling mode, stop/freeze level, and tick-size
   validation" sections.
6. **New, added by independent review — scope narrowed in third-pass
   review, applies to both EAs:** neither file persists an atomic market-
   signal/deal identity or reliably reconciles ambiguous submissions across
   a restart — this is narrower than "duplicate-signal protection is
   runtime-only": both files *do* scan existing positions/orders before
   entering (V637: 605–607; V811: `CountOurPositions` gate, see each
   audit), so many but not all duplicate scenarios are already caught. Both
   EAs' RSI wrappers fall back to `50` on a read failure, but **the effect
   is EA-specific, not a shared blanket behavior — corrected in fourth-pass
   review after an earlier draft wrongly generalized V637's behavior to
   "both files"**:
   - **V637: not uniform across its two entry paths — corrected in
     fifth-pass review, an earlier draft here also overgeneralized.** `50`
     deterministically *fails* the simple SR strict-threshold checks
     (2224/2232, single-sided comparisons). It does **not** reliably fail
     the compound MA-momentum entry expression (2670/2685 — **sell formula
     spelled out explicitly in eighth-pass review to avoid the "mirrored"
     shorthand hiding the actual threshold**: buy is `(rsi2<30 && rsi1>30)
     || rsi1>50`, sell is `(rsi2>70 && rsi1<70) || rsi1<50`) — a fallback on
     one of the two RSI reads can still let the other genuine reading
     satisfy the compound condition. Separately, the fallback can pass the more
     permissive `MomentumStillFavorable` management subcondition
     (3205/3206), and suppresses the optional, off-by-default
     `MomentumFailing` exit (3219–3227, exit itself disabled by default at
     351).
   - **V811:** `50` *passes* — it sits inside **both** default momentum-
     engine RSI windows (`InpMomRsiBuyMin/Max`=40–65, `InpMomRsiSellMin/Max`=35–60,
     inputs 147–150), so the fallback satisfies the RSI subcondition
     (2205–2206) in either direction. This still does not, by itself, make
     the overall momentum flag true — `g_mom_bull_ok`/`g_mom_bear_ok`
     require three other ANDed conditions (trend, position, momentum,
     lines 2208–2209) to also hold.

   See each audit's restart-idempotency
   section for the precise scope.

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
- V8.11's shared pin-bar/engulfing helper functions (one definition, four
  call sites) are a clean, verified, directly portable pattern. Its FVG
  "first-return-only, untouched" rule is a reasonable starting point but
  **not, as written, a clean lifecycle state machine to port directly**
  (**corrected in second-pass review** — see the FVG detection row above):
  a true single-fire consumed-flag would need to be added before reuse.
- Both giveback-guard designs (percent-of-peak vs. absolute-R-floor) are
  candidates for a head-to-head isolated experiment rather than either being
  assumed superior.

## Modules to retire (not carry forward as-is)

- V6.37's four vestigial, never-called functions (`HasEntryCHOCH`,
  `HasFibEMAConfluence`, `FindLatestFVG`, `FindLatestOrderBlock`) — dead
  code with no live call sites (**"from earlier refactors" removed in
  eighth-pass review — this repo's Git history has no commit history prior
  to the baseline import that would establish a refactor/supersession
  account; only the no-call-sites fact is source/Git-supported**).
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
