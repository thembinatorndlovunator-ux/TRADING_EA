# TASK-040 - IntradayModeRouter: market_family + first-pass intraday_mode classifier

## Objective

Build the live `market_family` (METAL/FOREX/SYNTHETIC_INDEX/UNKNOWN) and a
first-pass `intraday_mode` (SCALP/DAY_TRADE) classifier that Codex's sixth
review round (P0 finding 3) found unowned by any numbered task: TASK-036
required both fields but disclosed they depended on a "still-unregistered
future task"; the master prompt requires a live `IntradayModeRouter`
(section 5) and no MQL source implemented one.

## Reason

`market_family` was also the missing dependency TASK-034_LIVE_SAFETY_WIRING.md's
own Specification item 4 named as the reason it could not wire automatic
metal/synthetic news-provider routing and had to fall back to an explicit,
operator-set `InpNewsProviderSource` input instead. Building this classifier
was therefore the fastest way to unblock two open items at once.

## Specification

1. **`market_family`**: classify a symbol via the broker's own curated
   `SYMBOL_PATH` (Market Watch folder, e.g. `Metals\XAUUSD` or
   `Synthetic Indices\Continuous Indices\Volatility 75 Index`) — not the
   traded symbol's own ticker spelling, which varies per broker
   (`XAUUSD`/`GOLD`/`XAUUSD.a`/etc.) and is exactly the kind of ad hoc
   symbol-name heuristic TASK-034's own note warned against inventing.
   Returns `MARKET_FAMILY_UNKNOWN` (never a guess) when the path contains
   no recognizable keyword.
2. **`intraday_mode`**: a first-pass SCALP/DAY_TRADE classifier using the
   section-5 inputs that are already computable from this project's
   existing modules: regime persistence, ATR percentile (`E`),
   current-bar-vs-average range, and session time remaining
   (`SessionManager.mqh`'s `SN_GetSessionMinutesRemaining`, already built,
   previously unwired for this purpose). Section 5 does not specify exact
   weights anywhere in this project's documents, so `IMR_ComputeModeScore`'s
   scoring is a stated, documented interpretation choice, not a
   spec-verbatim formula — flagged in the module's own header exactly like
   `MarketRegimeEngine.mqh`'s "interpretation choice" notes. **Corrected,
   2026-07-27 (Codex round-8 P2 finding 22): this item previously said the
   mode score also used "only once a decision has been routed this bar --
   the winning candidate's own composite score," a genuine dependency on
   the resolved winner that Codex round-8's own P1 finding 12 flagged as
   making mode computation post-hoc rather than an independent,
   regime-driven classification. `IMR_ComputeModeScore`'s four components
   today are exactly the regime/ATR/range/session ones listed above, with
   no `winner_score` input at all; a SEPARATE, later, explicitly-named
   post-hoc consistency stage (TASK-002 section 1 stage 4, added round 7's
   P0 finding 6) still vetoes the routed winner by expected R once mode is
   known -- that veto stage is real and intentional, but the mode SCORE
   itself no longer depends on the winner. Reordering this veto stage into
   genuinely mode-AWARE strategy generation (this item's own remaining
   scope, see Specification item 4) is still not done -- named there
   honestly, not claimed complete here.**
3. **Explicitly NOT done, a genuine named gap, not silently skipped**:
   section 5's "historical performance of the setup in the same
   symbol/regime, only after enough samples" input needs a persistent
   per-symbol/regime performance-tracking store that does not exist yet —
   that is TASK-032's score-correlation/ML backlog territory.
4. **Journal-only, not yet behavior-wired**: none of the five existing
   strategies (`SRBounceStrategy.mqh` etc.) branch on `intraday_mode` to
   change entry timeframe, target sizing, or holding duration — they
   remain single-timeframe M15 evaluations. **Corrected, 2026-07-27 (Codex
   round-9 P1 finding 10): this item previously called the fix "a separate,
   larger, explicitly-named future task" without a task number — round-7's
   own P2 finding 20 already established that an unnumbered "future task"
   is not a real owner. Wiring `intraday_mode` into actual mode-first
   strategy generation (multi-timeframe entry selection per the family x
   mode matrix, mode-specific target/holding rules) is now registered as
   `TASK-043_MODE_FIRST_ROUTING_ARCHITECTURE.md`.**

## Files affected

- New `03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/IntradayModeRouter.mqh`
  + `Test_IntradayModeRouter.mq5`.
- `ThembaAdaptiveIntradayEA.mq5`: classifies `market_family` once at
  `OnInit` (one symbol per EA instance for its whole lifetime); computes
  and journals `intraday_mode` every bar via the same `gate_reasons`
  mechanism TASK-034 introduced; `ResolveNewsBlackout()` now auto-overrides
  to `NullNewsProvider` semantics whenever `market_family ==
  MARKET_FAMILY_SYNTHETIC_INDEX`, regardless of the operator's
  `InpNewsProviderSource` setting — this is a correctness rule
  (`PROJECT_RULES.md` rule 8), not a preference, so it is enforced
  automatically rather than left to the operator to remember.
- `TASK-034_LIVE_SAFETY_WIRING.md`: previously-blocked metal/synthetic
  provider-selection acceptance item and its synthetic-bypass test are
  now unblocked by this task (see that file's own updated status).
- `TASKS.md` and this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- The regime transition-history buffer P0 finding 3 also named
  (`TASK-031_REGIME_VALIDATION_COMPLETION.md`'s own disclosure) — that
  remains TASK-031's scope, not this task's.
- Wiring `intraday_mode` into actual strategy behavior (see
  Specification item 4) — `TASK-043_MODE_FIRST_ROUTING_ARCHITECTURE.md`
  (corrected 2026-07-27, Codex round-9 P1 finding 10 — previously an
  unnumbered "future task").
- Historical-performance-conditioned mode scoring (Specification item 3)
  — TASK-032's territory, needs infra that doesn't exist yet.
- Populating `DecisionJournal.mqh`'s own `market_family`/`intraday_mode`
  schema fields was originally out of scope for this task (`STradeDecision`
  had no such fields yet at the time this task was written; that was
  TASK-036's job, journalling both via the existing free-form
  `reasons_passed_json`/`reasons_rejected_json` string arrays as an interim
  measure). **Corrected, 2026-07-27 (Codex round-8 P2 finding 22): TASK-036
  has since shipped both real fields on `STradeDecision`
  (`decision.market_family`/`decision.intraday_mode`, populated directly in
  `EvaluateAndJournal`, matching `analysis/schema.py`'s own already-updated
  `Literal`s) -- this bullet is retained only as a historical record of the
  scope boundary at the time this task was written, not a statement of
  current behavior.**

## Test plan

1. Compile clean in MetaEditor, 0 errors/0 warnings, real log evidence —
   both `ThembaAdaptiveIntradayEA.mq5` (with this module wired in) and
   `Test_IntradayModeRouter.mq5` independently.
2. Hand-verified test script: `market_family` classification returns one
   of the four named values for the current chart's real symbol and never
   crashes; every enum value round-trips through `IMR_MarketFamilyToString`.
3. Hand-verified test script: **corrected, 2026-07-27 (Codex round-8 P2
   finding 22): this item previously named `IMR_ClassifyMode` and a
   `winner_score`-dependent scenario -- both stale since round 8's own P1
   finding 12 decoupled mode scoring from the routed winner (see
   Specification item 2's own correction above); the function under test
   today is `IMR_ComputeModeScore`/`IMR_ApplyModeHysteresis`, with no
   `winner_score` input at all.** A strong-trend/high-persistence/plenty-
   of-session-left case classifies DAY_TRADE; an expansion/wide-bar/
   imminent-news/little-session-left case classifies SCALP.
4. Runtime verification (attach to a real/demo chart, confirm
   `market_family`/`intraday_mode` values are sane for the actual traded
   symbol) — still batched project-wide.

## Acceptance criteria

- [x] `IMR_ClassifyMarketFamily` built, tested, wired at `OnInit`.
- [x] `IMR_ComputeModeScore`/`IMR_ApplyModeHysteresis` (renamed/restructured
      from this row's original `IMR_ClassifyMode`, corrected 2026-07-27,
      Codex round-8 P2 finding 22 -- see Specification item 2's own
      correction) built, tested, wired into `EvaluateAndJournal` (a
      later post-hoc consistency stage now also vetoes the routed winner
      by mode, per Specification item 2's correction; behavior-wiring
      into strategy generation itself remains Specification item 4's
      stated, deferred scope boundary).
- [x] `TASK-034_LIVE_SAFETY_WIRING.md`'s previously-blocked synthetic-bypass
      acceptance item is unblocked: `ResolveNewsBlackout()` now auto-selects
      `NullNewsProvider` semantics for `MARKET_FAMILY_SYNTHETIC_INDEX`,
      regardless of `InpNewsProviderSource`.
- [x] Historical-performance input and behavior-wiring are named as
      explicit out-of-scope gaps, not silently skipped.
- [ ] Independent review completed and findings resolved — deferred to
      this project's single, consolidated, end-of-sprint Codex review per
      the user's 2026-07-22 directive, not a per-task review this time.

## Rejection criteria

Reject if `market_family` is inferred from the ticker's own name/string
rather than `SYMBOL_PATH`, if the historical-performance gap is silently
faked instead of named, or if this task claims to have wired
`intraday_mode` into actual strategy behavior when it has not.

## Status

In progress — both classifiers built, wired, and compiling clean (real
MetaEditor evidence, 2026-07-22); `TASK-034`'s synthetic-bypass acceptance
item is now unblocked as a direct result. Independent review deferred to
the consolidated end-of-sprint review.
