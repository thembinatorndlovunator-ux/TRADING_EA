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
   existing modules: regime, ATR percentile (`E`), trend persistence
   (`T_final`), current-bar-vs-average range, spread/ATR, session time
   remaining (`SessionManager.mqh`'s `SN_GetSessionMinutesRemaining`,
   already built, previously unwired for this purpose), news proximity,
   and — only once a decision has been routed this bar — the winning
   candidate's own composite score as a coarse proxy for "pattern
   quality"/"expected reward-to-risk" (neither is independently available
   before order sizing). Section 5 does not specify exact weights anywhere
   in this project's documents, so `IMR_ClassifyMode`'s scoring is a
   stated, documented interpretation choice, not a spec-verbatim formula —
   flagged in the module's own header exactly like
   `MarketRegimeEngine.mqh`'s "interpretation choice" notes.
3. **Explicitly NOT done, a genuine named gap, not silently skipped**:
   section 5's "historical performance of the setup in the same
   symbol/regime, only after enough samples" input needs a persistent
   per-symbol/regime performance-tracking store that does not exist yet —
   that is TASK-032's score-correlation/ML backlog territory.
4. **Journal-only, not yet behavior-wired**: none of the five existing
   strategies (`SRBounceStrategy.mqh` etc.) branch on `intraday_mode` to
   change entry timeframe, target sizing, or holding duration — they
   remain single-timeframe M15 evaluations. Wiring `intraday_mode` into
   actual strategy behavior (multi-timeframe entry selection, mode-specific
   target/holding rules) is a separate, larger, explicitly-named future
   task, mirroring how this EA itself started journal-only (TASK-025)
   before order submission was wired in later (TASK-027).

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
  Specification item 4) — a separate future task.
- Historical-performance-conditioned mode scoring (Specification item 3)
  — TASK-032's territory, needs infra that doesn't exist yet.
- Populating `DecisionJournal.mqh`'s own `market_family`/`intraday_mode`
  schema fields — `STradeDecision` has no such fields yet; that remains
  TASK-036's job. This task journals both via the existing free-form
  `reasons_passed_json`/`reasons_rejected_json` string arrays in the
  meantime (same interim pattern TASK-034 used for its own gate reasons).

## Test plan

1. Compile clean in MetaEditor, 0 errors/0 warnings, real log evidence —
   both `ThembaAdaptiveIntradayEA.mq5` (with this module wired in) and
   `Test_IntradayModeRouter.mq5` independently.
2. Hand-verified test script: `market_family` classification returns one
   of the four named values for the current chart's real symbol and never
   crashes; every enum value round-trips through `IMR_MarketFamilyToString`.
3. Hand-verified test script: `IMR_ClassifyMode` — a strong-trend/high-
   persistence/plenty-of-session-left case classifies DAY_TRADE; an
   expansion/wide-bar/imminent-news/little-session-left case classifies
   SCALP; a high-quality routed decision (`winner_score>=70`) raises the
   day-trade score relative to an otherwise-identical no-decision case; a
   low-quality decision (`winner_score<70`) gets no such nudge.
4. Runtime verification (attach to a real/demo chart, confirm
   `market_family`/`intraday_mode` values are sane for the actual traded
   symbol) — still batched project-wide.

## Acceptance criteria

- [x] `IMR_ClassifyMarketFamily` built, tested, wired at `OnInit`.
- [x] `IMR_ClassifyMode` built, tested, wired into `EvaluateAndJournal`
      (journal-only, per Specification item 4's stated scope boundary).
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
