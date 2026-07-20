# TASK-002 — Phase 2: Specification for the Combined Adaptive Intraday Engine

## Objective

Produce the Phase 2 specification required by `00_MASTER_PROMPT_FOR_CLAUDE.md`
section 23 ("Phase 2 — Specification") before any Phase 3+ code is written:
formalize intraday modes, regimes, strategy routing, risk, exits, and news —
and explicitly resolve every contradiction between SmartCoreEngine V6.37 and
NdlovuSMC V8.11 that TASK-001's 14-round audit surfaced, rather than carrying
either baseline's behavior forward by default.

## Reason

Per `CLAUDE.md`'s workflow ("1. Audit. 2. Specify. 3. Create a task branch
..."), no architecture or implementation work may begin until the audit is
complete and a specification resolves what a new, combined engine actually
does — not "port both EAs and pick whichever behavior compiles first."
TASK-001 (14 independent-review rounds, `baseline_v637_audit.md`,
`baseline_v811_audit.md`, `baseline_comparison.md`) is functionally complete
and gives this task a concrete defect list instead of vague "improve both"
intent. The user has directed a **fix-as-you-port** strategy: reuse what
works, correct every documented defect, and do not reproduce a bug just
because it existed in a baseline.

## Baseline behaviour

See `baseline_v637_audit.md`, `baseline_v811_audit.md`, and
`baseline_comparison.md` on this branch (inherited from
`claude/task-001-baseline-audit`, commit `2005d75`) for the full evidence
base. Summary of what this specification must NOT silently inherit:

- V6.37: pilot-trade risk ceiling far above its own implemented budget
  (6.25×–33.33× depending on setup), a sign-error in the learning-penalty
  formula that boosts losing-but-high-win-rate strategies, journal
  cross-magic learning contamination, pending-order fill misattribution by
  direction only, requested-vs-actual-fill price mixing in R/management
  math, an intrabar (forming-candle) read in two candlestick helpers, and
  pervasive unchecked `CTrade` result codes.
- V8.11: basket state lost entirely across a restart (no dynamic risk
  management survives), a fixed 45-minute time exit with no evidence
  conditioning, a minimum-lot fallback that can exceed its own risk budget,
  a daily-limit numerator/denominator anchor mismatch across restarts, a
  persisted peak-drawdown key that truncates a `long` magic number and can
  collide, chart marks that retain the oldest (not most recent) structural
  breaks, and the same unchecked-`CTrade`-result pattern as V6.37.
- Both: fragile substring-based symbol/news classification, no economic
  calendar (V6.37's NFP logic is calendar-arithmetic, not a real feed),
  RSI-indicator-failure fallbacks that silently satisfy downstream
  threshold checks instead of invalidating the read.

## Evidence

- `baseline_v637_audit.md`, `baseline_v811_audit.md`,
  `baseline_comparison.md` — full defect list, cited to source line numbers.
- `00_MASTER_PROMPT_FOR_CLAUDE.md` sections 5–15, 22–23 — product
  definition, regime engine, strategy routing, ICT/SMC logic, candlestick
  engine, chart-pattern engine, signal scoring, risk management, exit
  engine, news system, required architecture, roadmap.
- `RISK_POLICY.md` — binding risk defaults and hard caps.
- `STRATEGY_SPECIFICATION.md` — the per-strategy template every strategy
  module (Phase 5+) must be filled out against.

## Specification

### 1. Intraday modes (master prompt §5)

Two modes only: **Scalp** (M1–M5 entry, M15–H1 context, minutes to ~1 hour,
evidence-based time exit) and **Day-trade** (M5–M15 entry, M30–H4 context,
same-session only, session-aware risk). Mode selection is via a new
`IntradayModeRouter` — inputs per §5 (regime, ATR percentile, range vs.
average, trend persistence, distance to next validated target, spread/ATR,
session time remaining, news proximity, pattern quality, expected R:R,
sample-gated historical performance). **Neither baseline has this router —
it is new work, not a port.** Both baselines' fixed-timeframe assumptions
(V6.37's configurable-but-single entry TF, V8.11's five-fixed-role
hierarchy) are retired in favor of mode-conditioned timeframe selection.

**Contradiction resolved:** V8.11's fixed 45-minute time exit and V6.37's
absence of any universal time exit are both superseded — every mode's time
exit must be evidence-based per §5 ("Time exit must be conditional and
evidence-based, not universally fixed"), driven by mode, regime, target
progress, and session time remaining (§14), never a bare constant.

### 2. Regime engine (master prompt §6)

Nine regimes (`TRENDING_UP/DOWN`, `RANGING`, `VOLATILITY_EXPANSION_UP/DOWN`,
`COMPRESSION`, `TRANSITION_OR_UNCERTAIN`, `NEWS_BLACKOUT`,
`UNTRADEABLE_SPREAD_OR_LIQUIDITY`), built from swing sequence, BOS/CHoCH,
ATR-normalized EMA slope/separation, ADX as supporting evidence only (not
sole authority), ATR percentile, efficiency ratio, range overlap, directional
candle-body persistence, range compression, breakout acceptance, retest
success, and distance from equilibrium/key levels. Completed candles only.
Must emit a confidence score, a reason string, and a transition history.

**Contradiction resolved:** neither baseline's regime concept survives
as-is. V6.37's 3-way classifier (`Trending`/`Ranging`/`Volatile Expansion`,
ATR-expansion-over-average outranking a simple trend check) and V8.11's
ad-hoc pairing of a blanket `g_expansion` gate with independent H1/M30
direction gates are both replaced by the single 9-state engine above. A
low-confidence regime read must result in **waiting or reduced risk**, never
forced strategy selection — this directly closes V6.37's regime-bench
learning-penalty sign error and the V8.11 blanket-expansion-vs-momentum-
breakout gate conflict, since both were attempts to patch a regime concept
that is itself being replaced.

### 3. Strategy routing (master prompt §7) — what survives from each baseline, and how

| New-engine family | Primary source | Fix required before reuse |
|---|---|---|
| SR Bounce / Range Rotation | V6.37 primary (`EvaluateSRBounceSignal`, `FindSRZone`, `FindClusterBoundary`, plus `BuildRangeCycleSignal`/`BuildRotationSignal` for the "Range Rotation" half of this named family — master-prompt §7 groups SR Bounce and Range Rotation as one family) — V6.37's touch-decay scoring and second-distinct-retest confirmation are more developed than V8.11's simpler cluster ranking, but V8.11's `BuildSRBounce` sweep-first/extra-touch/H1-bias bonus scoring is worth folding in as additional score components (subject to the correlation-avoidance rule in §7 below, since "swept first" and "extra touches" may correlate) | Consolidate the file's fragmented fractal-depth inputs (`InpFractalDepth`/`InpStructureSwingDepth`/`InpTrendSwingDepth`/`InpMajorSwingDepth`/hard-coded literals) into one canonical swing-depth definition per structural concept; fix `LevelInvalidated`/`FindClusterBoundary`'s "retires" framing to an explicit, intentional current-run-only design (this is the decision — see below) rather than leaving it ambiguous; keep Rotation's countertrend risk-haircut *concept* (a lower risk budget for countertrend setups, `InpRotationRiskFactor`) as a general risk-engine feature, decoupled from the specific old regime router it was tied to (see the self-confirmed note below) |
| SMC/ICT price-action (sweep-shift, BOS/CHoCH, FVG, order blocks) | V8.11 for sweep-and-shift and the M15→M5 OB refinement (cleaner, single accessor `ActiveOB()` shared by drawing and trading); V6.37 for FVG retest structural gating (three independently-toggleable requirement flags) | Fix V8.11's sweep/shift lookback-range floors and the final-stop transformation chain (spread, floor, cap, normalize) so the spec states the real formula, not the unfloored one; fix V6.37's multiple coexisting BOS/CHoCH definitions (`AnalyzeStructure`, `FindRecentStructureShiftLevel`, `BuildBOSRetestSignal`) down to one; discard the dead `HasEntryCHOCH`/`HasFibEMAConfluence`/`FindLatestFVG`/`FindLatestOrderBlock` functions entirely rather than port them |
| Trend Following (incl. momentum continuation) | V6.37 (`EvaluateTrendBreaker`, `BuildThreePointTrendLine`) for the trendline half; V8.11's ASQ momentum breakout (`BuildMomentumBreakout`) for the momentum-continuation half — master-prompt §7 lists these under one "Trend Following" family and neither baseline's version is a full substitute for the other | **Decision, not an either/or:** implement genuine per-bar trendline re-projection (the line is re-evaluated at each new bar's time, and the middle anchor's own distance from the line is tested, not just its monotonic ordering) — this is what "three-point trendline" is supposed to mean, and the two-anchor-plus-constant-level shortcut is what created the audit's confirmed geometry defect; do not carry the shortcut forward as "documented as intentional." Consolidate the file's triple-implemented trendline logic (`EvaluateSRChannel`, `EvaluateTrendBreaker`, the dedicated touch/break-retest pair) into one definition. Momentum breakout is folded in as its own setup within this family, subject to the same regime-routing rules as everything else (V8.11's separate `g_expansion` blanket gate is retired along with the rest of its ad-hoc regime handling, per §2 above) |
| Chart-pattern breakout / Post-expansion retest | Neither baseline implements these as named strategies (V6.37 has ad-hoc range/rotation logic, now folded into the SR Bounce/Range Rotation row above; V8.11 has none) — **new work**, per master-prompt §9–10 | N/A — build fresh against `CandlestickPatternEngine.mqh`/`ChartPatternEngine.mqh` normalized definitions, not name-only pattern matching |
| Basket / multi-leg entries, add-ons | **Disabled by default** (V8.11 baskets, V6.37 pilot/add-on pyramiding) | Per `RISK_POLICY.md` ("Add-ons and multi-leg baskets are disabled until independently proven") and master-prompt §13 — this is not a partial port, it is an explicit off-switch until an isolated experiment proves total-risk math and incremental value. If ever re-enabled: fix V8.11's minimum-lot fallback exceeding its own risk budget, fix V6.37's pilot-ceiling-vs-implemented-budget gap (6.25×–33.33×, not a bounded 2.5–5×), and require actual `POSITION_PRICE_OPEN` (not requested-price) for every leg's ongoing R/BE/trail/giveback math |

**Self-confirmed bypass — narrowed, not blanket-retired.** V6.37's
`IsSelfConfirmedSetup` concept (some setups' own structural confirmation is
strong enough that a redundant horizontal SR/premium-discount re-check adds
no information) is a reasonable idea on its own and is **kept** as a
general "does this setup's evidence already imply location/SR
confirmation?" flag per setup. What is retired is only its specific
coupling to V6.37's old 3-way regime router (the interaction that produced
the Rotation-vs-Volatile-Expansion contradiction) — that coupling
disappears because the old regime router itself is replaced by the
9-state, confidence-gated engine in §2, which handles "block on
low-confidence/wrong-regime evidence" directly rather than through a
setup-name allow-list.

### 4. Risk management (master prompt §13, `RISK_POLICY.md`) — binding, not aspirational

- Per-trade risk: XAUUSD 0.25%, other metals 0.25–0.50%, synthetics
  0.25–0.50% until symbol-specific testing proves otherwise. **Hard cap
  1.00% per trade, 1.00% total open risk, 2.00% daily loss, 4.00% weekly
  loss.** These are hard ceilings, not soft targets a pilot/rotation/weak-
  sample mechanism is allowed to exceed — **this directly retires V6.37's
  pilot ceiling (up to 5.0% actual-risk permission) and its Rotation-setup
  budget interaction**, neither of which may be ported as-is.
- **No risk increase after a loss, ever** — this retires V6.37's
  weak-sample-driven stop-width/trailing widening (`OverallWinRate()` <45%
  widening ATR multiplier and trail thresholds) as a *risk-increasing*
  mechanism; a win-rate-based *reduction* in risk after losses is
  acceptable, an increase is not.
- **The confirmed sign-error defect is a hard blocker for reusing V6.37's
  learning-penalty pattern at all.** Any ported learning/scoring system must
  independently re-derive and unit-test the penalty branch's arithmetic
  (a losing bucket must always move the score down, never up, regardless of
  win-rate) before it is trusted.
- Journal/learning persistence, if reused: keys must include **both** symbol
  and magic number (fixing V6.37's cross-magic learning contamination via
  `LoadJournalMemory`'s symbol-only filter); file opens must use
  `FILE_SHARE_READ`/`FILE_SHARE_WRITE`; header-write must not have a
  duplicate-write race (single init-time write behind a lock, not a
  read-then-maybe-write pattern); the "best setup" field must carry the
  actual per-trade setup name through the position's lifetime (a real field
  on the position/deal record, not a derived summary-of-summaries computed
  at close time).
- **Every position-close, position-modify, and pending-order-delete call
  must check its `CTrade` result code before updating any internal state**
  (peak-R keys, break-even flags, basket-leg counts, tracking globals) —
  this is a blanket rule closing the pervasive "attempted vs. guaranteed"
  defect class found across both baselines (giveback closes, daily-lock
  closes, OB-limit-order cleanup, `MoveBasketStops`, `CloseBasket`).
- **Every R/break-even/trailing/giveback calculation must use the actual
  fill price (`POSITION_PRICE_OPEN`/`DEAL_PRICE` post-fill), never the
  pre-submission requested quote** — this is a blanket rule closing the
  requested-vs-actual-fill mixing defect confirmed in both baselines.
- **Pending-order fills must be matched to their originating order/position
  identity (ticket, `DEAL_POSITION_ID`, or equivalent), never by direction
  alone** — closing V6.37's pending-fill misattribution defect.
- RSI (or any indicator) read failure must **fail closed**: invalidate the
  candidate signal outright, never fall back to a fixed value (like 50)
  that can silently satisfy a downstream threshold comparison. Both
  baselines' `50`-fallback pattern is retired.
- Broker validation is mandatory before every order: tick size, tick value,
  volume min/max/step, stop level, freeze level, filling mode, margin —
  via `OrderCalcProfit`/`OrderCalcMargin` cross-checks, not assumption.

### 5. Exit engine (master prompt §14)

`ExitManager` supports: initial structural stop, initial target, a
multi-target plan that does not multiply total risk, break-even only after
evidence justifies it, structure-based trailing, ATR-based trailing,
swing-based trailing, an evidence-conditioned time stop, momentum-failure
exit, opposite-confirmed-structure-shift exit, session close, daily risk
lock, news safety policy, and profit-giveback guard. Every exit carries one
machine-readable reason.

**Contradiction resolved — giveback guard model:** V6.37 uses a
percent-of-peak model (arm at 1.25R, tolerate 60% giveback of peak); V8.11
uses an absolute-R-floor model (arm at 0.8R, floor at 0.1R). Per
`baseline_comparison.md`, this is "a natural candidate for an isolated
A/B experiment... rather than picking one by inspection." Resolution: build
both behind one `ProfitGivebackGuard` interface as swappable, independently
testable strategies; default to **off** until Phase 8 (per master-prompt
roadmap, "Exit and giveback" experiments) produces comparative evidence.
Whichever is tested first must fix its own baseline's confirmed defects:
V8.11's misleading `MathMax(rr,0.0)`-clamped status text ("banked +0.00R"
on an actual loss) and V6.37's profit-lock stop that can be moved a second
time by broker-minimum-distance enforcement without a second improvement
check.

**Contradiction resolved — target ladder:** V6.37's actual managed ladder is
TP1→TP3→runner (not TP1→TP2→TP3 as its own audit originally mis-stated);
V8.11's is a fixed `ladder[0..3]` at 1.0/1.5/2.0/2.5R with only the first
two rungs live at shipped leg-count defaults. The new engine's multi-target
plan should be built fresh against master-prompt §14's "next liquidity or SR
target" and "partial plus runner" comparison points, using whichever
baseline's *target-selection* logic (V6.37's `SetEquilibriumContinuationTarget`,
which biases toward the nearest qualifying target beyond `risk ×
InpMinRiskReward`) proves useful as a starting point — not either baseline's
specific stage-count scheme.

### 6. News system (master prompt §15)

Real provider architecture: `MT5CalendarProvider` (primary, live),
`FileCalendarProvider` (historical/backtest-deterministic),
optional `FairEconomyProvider` (secondary, Python-adapted, never the sole
live dependency), `NullNewsProvider` for synthetic indices. One normalized
event schema (event ID, name, currency, importance, scheduled UTC,
broker-server time, local time, previous/forecast/actual/revision, source,
retrieval timestamp, cache status).

**Contradiction resolved:** V6.37's `IsNFPDayNow` (pure first-Friday
calendar arithmetic, no real calendar, no DST handling, operator-maintained
server-time offset) is retired outright — it cannot be configured into
correctness, it must be replaced by `MT5CalendarProvider`. V6.37's and
V8.11's fragile substring-based synthetic/real-market classification
(`IsSyntheticIndexSymbol`'s 7-term list vs. `DirectionAllowedForSymbol`'s
2-term subset, overlapping only on "boom"/"crash") is retired in favor of
provider selection at the symbol-profile level — a synthetic symbol gets a
`NullNewsProvider` by configuration, not by runtime string matching that can
silently mis-classify an unrecognized broker symbol name.

### 7. Signal scoring, trade decision object, journal (master prompt §11–12, §18)

Score components per §11 (regime compatibility, HTF alignment, pattern
quality, location quality, liquidity event, displacement, retest quality,
candlestick confirmation, target room, spread/session/news quality,
sample-gated historical performance, and named penalties for stale zones,
repeated touches, conflicting direction, late entry, excessive stop
distance, poor data quality) — **each must be independently justified, not
inflated by re-counting correlated evidence.** Master-prompt §11 names the
exact failure mode both baselines exhibit: V6.37 stacks an OB-confluence
bonus onto *any* already-surviving signal (`ApplyOrderBlockConfluence`)
while separately scoring sweep/touch/bias bonuses that can describe the
same underlying displacement — before any bonus is added, it must be
checked against every other active bonus for whether they describe the
same market fact (the spec's own examples: BOS and displacement may be
related; a pin bar and wick rejection may be the same evidence; EMA trend
and price-above-EMA may be correlated). A score-correlation audit (Python)
is required before any strategy's scoring goes live, not added
retroactively.

One `TradeDecision` object per candidate, per §12's full field list (signal
ID, timestamp, symbol, broker, market family, intraday mode, regime,
regime confidence, direction, strategy family, setup — **the actual setup
name carried through the position's lifetime, not a derived summary,
closing V6.37's `BestStrategySetup` corruption bug** — candlestick pattern,
chart pattern, ICT/SMC features, entry trigger, entry/stop/target prices,
risk amount and percentage, estimated spread cost, expected R:R, score and
its full breakdown, news state, session state, reasons passed, reasons
rejected, data sufficiency, pattern object IDs, EA version, Git commit, and
set-file identifier). The same object feeds execution, dashboard, journal,
screenshots, Python analysis, and backtest reports — one source of truth,
not four independently-maintained descriptions of the same trade (closing
the exact class of drift this task's own canonical status/Files-affected/
Commit sections repeatedly suffered from during TASK-001's 14 review
rounds). The EA-version/Git-commit/set-file-identifier fields also give any
future orphaned-set-file question (per TASK-001's unresolved provenance
finding) a permanent, forward-looking answer: every trade this engine
places is traceable to the exact commit and configuration that produced it.

`DecisionJournal`/`TradeJournal`/`LearningStatistics.mqh` per the required
architecture (§22) — built fresh, informed by V6.37's minimum-sample-gated
bench-with-safety-valve pattern **only after** its sign-error is fixed and
its symbol+magic isolation gap is closed (see Risk section above).

### 8. Required architecture and roadmap alignment

This specification maps directly onto master-prompt §22's module tree and
§23's roadmap. Phase 3 (Common core: market data, symbol profile, session
manager, risk manager, decision journal, broker validator, intraday close)
is the next task branch after this specification is reviewed and approved.
Phase 4 (detection engines) and Phase 5 (strategy modules, added and tested
**one at a time**, per §23) follow — each strategy module gets its own
`STRATEGY_SPECIFICATION.md`-based document before it is coded, per that
template's fields (Strategy ID through Rejection Criteria), as its own
bounded task.

## Files affected

New file: `TASK-002_PHASE2_SPECIFICATION.md` (this file), on branch
`claude/task-002-phase2-specification` (branched from
`claude/task-001-baseline-audit` at `2005d75`, since this specification
must cite the audit documents that exist only on that branch). No file
under `01_BASELINE/` is touched. No `03_SOURCE_CODE/` files are created —
per master-prompt §23, Phase 2 is specification only; Phase 3 is the first
task branch permitted to write code.

## Out of scope

- Any `.mqh`/`.mq5` implementation code — that is Phase 3+.
- Per-strategy `STRATEGY_SPECIFICATION.md` instances for each of the six
  strategy families in §7's table — these are Phase 5's "one at a time"
  deliverables, each its own bounded task, not bundled into this
  cross-cutting specification.
- Resolving the merge status of `claude/task-001-baseline-audit` — that
  branch remains unmerged (still "changes requested" per its own Final
  Decision section) and this task does not change that; this specification
  simply depends on reading its content.
- Any claim that the specification above has been compiled, tested, or
  proven correct — it has not; it is a design document only.

## Risks

- **Dependency on an unmerged branch.** This task branch is based on
  `claude/task-001-baseline-audit`, which is not yet merged to `main`. If
  that branch is substantially revised before merge, this specification's
  citations may drift. Mitigate by re-checking citations against
  `main` once TASK-001 is actually merged, before Phase 3 begins.
- **Specification-implementation drift.** A specification is not
  self-enforcing; Phase 3+ tasks must be checked against this document
  during their own independent review, not assumed compliant.
- **Scope.** This document formalizes cross-cutting concerns (modes,
  regimes, risk, exits, news) at the level master-prompt §23 calls "Phase
  2." It does not yet formalize every individual strategy's entry/exit
  geometry to `STRATEGY_SPECIFICATION.md`'s full field list — that is
  explicitly deferred to Phase 5, one strategy at a time, per the master
  prompt's own roadmap.

## Test plan

Not applicable in the compilation/backtest sense — this is a specification
document, not code. Verification for this task is: (1) every contradiction
identified in `baseline_comparison.md` has an explicit resolution stated
above, not left implicit; (2) every resolution cites the specific audit
finding and source location it responds to; (3) every master-prompt section
this document claims to formalize (§5, §6, §7, §13, §14, §15) is actually
addressed, not merely referenced.

## Acceptance criteria

- [ ] Every "Contradiction resolved" callout above names the specific
      baseline behaviors in conflict and states which one (or neither)
      survives, with a reason.
- [ ] Every hard numeric limit in `RISK_POLICY.md` is restated here as
      binding, not superseded by any baseline-derived exception.
- [ ] Add-ons and multi-leg baskets are explicitly off by default,
      consistent with `RISK_POLICY.md`.
- [ ] Independent Codex review completed and findings resolved.

## Rejection criteria

This task would be rejected if: it silently ported a baseline behavior
already confirmed defective in TASK-001 without stating why; it claimed a
numeric risk limit different from `RISK_POLICY.md`; it introduced or implied
any actual trading-code change (this task must remain documentation-only);
or it left a contradiction identified in `baseline_comparison.md`
unaddressed.

## Implementation notes

Written directly, informed by the full TASK-001 audit history (14
independent-review rounds) already present in this session's context, plus
a direct re-read of `00_MASTER_PROMPT_FOR_CLAUDE.md` sections 5, 6, 7, 13,
14, 15, 22, and 23, `RISK_POLICY.md`, and `STRATEGY_SPECIFICATION.md` in
this session, rather than relying on memory of their contents from earlier
in the project.

## Commands run

`git checkout claude/task-001-baseline-audit && git checkout -b claude/task-002-phase2-specification`

## Compiler result

Not applicable — no code in this task.

## Test results

Not applicable — no code in this task.

## Commit

Pending — see `git log` on this branch for the actual hash once committed.

## Reviewer

Independent review pending (Codex or equivalent), per `PROJECT_RULES.md`
release-gate requirements — not yet requested for this task.

## Final decision

**Pending.** Awaiting user review of this specification before Phase 3
(Common core) begins.
