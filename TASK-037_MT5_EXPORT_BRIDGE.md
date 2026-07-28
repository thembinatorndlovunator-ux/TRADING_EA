# TASK-037 - MT5 real-data export bridge

## Objective

Build the MQL5/MT5-side export scripts that produce the real datasets
every Python-lab pipeline currently documents but has never run against:
a normalized trade-history export, a real news-calendar export, and a
real MQL5 pattern-detector-results export. Without this task, "Real-data
run: PENDING" cannot ever become "done" anywhere in this project.

## Reason

Codex's TASK-028 review (finding #2) explicitly required this be a
numbered owner rather than an indefinite "genuinely still remaining"
bullet: "The prose-only MT5 trade-export bridge and current EA
journal-population gap also remain unnumbered. Those gaps make real-data
execution impossible and must have explicit owners." This also directly
unblocks the real-evidence portions of `TASK-031` (regime confusion
matrix) and `TASK-033` (pattern cross-check), and TASK-035's ML training
data.

## Baseline behaviour

Neither immutable baseline EA has any export capability. `01_BASELINE/`
must not be modified.

## Evidence

- `09_HANDOVERS/codex_to_claude/TASK-028_review.md` finding #2.
- Every `analysis/*.py` module's own docstring documents the exact
  normalized CSV schema it expects and states no real export exists yet
  -- this task's job is to produce data in those already-documented
  shapes, not invent new ones.
- `03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/CandlestickPatternEngine.mqh`
  -- has no CSV/export function for detector results (needed for
  TASK-033's real cross-check).
- `03_SOURCE_CODE/MQL5/.../ChartPatternEngine.mqh` -- likewise has no
  export function, and is likewise needed for TASK-033's real cross-check
  (added, 2026-07-22 Codex review finding, third round -- previously
  omitted from this Evidence list despite TASK-033 deferring its
  cross-check here too).
- `03_SOURCE_CODE/MQL5/Include/ThembaEA/News/NewsManager.mqh` -- no
  CSV/SQLite deterministic-backtest provider exists (TASK-029's own
  explicitly deferred item).

## Specification

1. **Trade-history export**: a script (`Test_*.mq5` or a small
   standalone tool) that reads MT5's own Deals/History and writes the
   normalized `trades.csv` schema `analyse_baseline.py` et al. already
   document (`trade_id, symbol, is_long, entry_time, exit_time,
   entry_price, exit_price, stop_price, profit`) **PLUS `order_id`/
   `deal_id` columns (added, 2026-07-22 Codex review finding, fourth
   round -- this item previously omitted both, so the only task meant to
   produce real trades could not produce
   `analysis/join_signal_to_outcome.py`'s required input; `deal_id`
   specifically must be the real MT5 deal ticket for that fill, unique
   per row -- a partial fill produces multiple deals against the same
   order, and `join_signal_to_outcome.py` requires exactly that
   cardinality to aggregate them into one position)**. `order_id` must be
   populated from MT5's **position identifier** (`SOrderOpenResult
   .position_id` in `OrderManager.mqh`, MT5's own `POSITION_IDENTIFIER`),
   the identifier documented as stable across every fill AND the
   position's entire lifetime -- **corrected, 2026-07-22 Codex review
   finding (sixth round, TASK-028's own P0 finding 1): this previously
   said `position_ticket`/`POSITION_TICKET`, which MT5 documents as
   changeable after a server-side service re-open or, in netting mode, a
   reversal; `POSITION_IDENTIFIER` is the field MT5 documents as constant
   for the whole life of the position, matching every related deal's own
   `DEAL_POSITION_ID`.** NOT the literal order ticket, which is consumed
   once filled, and NOT `position_ticket` either (session-scoped, not
   durable) (added, 2026-07-22 Codex review finding, fifth round,
   matching `join_signal_to_outcome.py`'s own documented identity
   semantics).
   **Net P/L formula must be specified and verified, not assumed (added,
   2026-07-22 Codex review finding, fifth round):** `analyse_baseline.py`
   requires `profit` to already be NET of commission/swap/fees, but this
   task previously never defined how to derive that from MT5's own Deals
   fields (`profit`, `commission`, `swap`, `fee` are separate columns in
   MT5's history, and whether `profit` already includes any of the others
   is unverified). This export must document and TEST the exact
   aggregation formula (e.g. `net = profit + commission + swap + fee`)
   against a real small MT5 export before this bridge is accepted --
   `analyse_baseline.py`'s docstring now states this as a requirement on
   this task's export, not a fact about MT5's format.
2. **News-calendar export**: a script producing the `news_events.csv`
   schema `join_news_events.py` documents (`event_id, event_name,
   currency, importance, scheduled_utc`), sourced from MT5's built-in
   economic calendar (`MT5CalendarProvider.mqh` already reads this live;
   this task adds an export path) or independently from the FairEconomy
   feed already chosen for live use in TASK-034.
3. **Pattern-detector export**: a new function on
   `CandlestickPatternEngine.mqh` that writes each pattern predicate's
   per-bar boolean result to CSV in the `k, <pattern_name>...` shape
   `pattern_validation.compare_to_mql5_export` already expects. **Added,
   2026-07-22 Codex review finding (third round): this item previously
   named only `CandlestickPatternEngine.mqh` -- `TASK-033_PATTERN_
   VALIDATION_COMPLETION.md` explicitly defers BOTH the candlestick AND
   the chart-pattern real MQL5-export cross-check to this task (its own
   Objective/Out-of-scope say so), so this export must ALSO cover
   `ChartPatternEngine.mqh` (double top/bottom, head-and-shoulders/
   inverse) in the same per-bar boolean CSV shape -- a candlestick-only
   export would leave TASK-033's chart-pattern cross-check with no data
   source to run against.**
4. **Regime-dataset labelling protocol AND export schema, made concrete
   and executable (added, 2026-07-22 Codex review finding, third round;
   made concrete, fourth round -- Codex's fourth-round pass found the
   third-round text was still only a requirement to "design a protocol
   later," not the actual protocol/schema needed to satisfy the
   acceptance criterion below):**
   - **Predicted-regime export:** a new function/script that runs the
     LIVE `MarketRegimeEngine.mqh` (the exact code path the EA uses, per
     the Risks section below -- never a reimplementation) against a real
     historical OHLC segment and writes one CSV row per bar:
     `symbol, timestamp, predicted_regime` (the classifier's own
     `ENUM_MARKET_REGIME` output, `EnumToString`'d, matching
     `regime_validation.py`'s `Regime` string values exactly).
   - **Labelling protocol:** the "independently-labelled" ground truth
     for `regime_validation.build_confusion_matrix` cannot be the live
     EA's own `MarketRegimeEngine.mqh` output (that would be comparing
     the classifier against itself, not an independent label). A human
     analyst hand-labels the SAME real historical chart segment
     bar-by-bar against the spec's own nine-state definitions (section
     2), working from the raw chart alone, BEFORE ever looking at the
     `predicted_regime` export above, producing a second CSV:
     `symbol, timestamp, labelled_regime, labeller_id, labelling_date`.
   - **Joined dataset:** the two CSVs above are joined on
     `(symbol, timestamp)` into exactly the two parallel sequences
     `regime_validation.build_confusion_matrix(predicted, actual)`
     already accepts (`predicted_regime` -> `predicted`,
     `labelled_regime` -> `actual`) -- no further transformation needed;
     this task's own export/labelling CSVs ARE that function's required
     input shape. Do not accept a self-referential (classifier compared
     to itself) or synthetic-fixture substitute as satisfying this.
5. Every export must itself follow this project's reproducibility
   contract (explicit paths, no hidden state, visible failures on
   malformed source data) -- these are pipelines like any other, not a
   special exemption.
6. **OHLC/close-bar and per-trade R-path export (added, 2026-07-22 Codex
   review finding, fifth round -- previously entirely missing, so
   `calculate_mfe_mae.py`, `analyse_giveback.py`, and
   `parameter_stability.py` have no real-data input at all despite each
   documenting a required CSV shape):** a script exporting per-symbol OHLC
   bars at a DECLARED, fixed cadence (e.g. M1) covering every trade's
   `[entry_time, exit_time]` window with NO gaps (`calculate_mfe_mae.py`'s
   `bars.csv` schema), and a separate per-trade R-path export (one row per
   `path_id, bar_index, r_value`, `parameter_stability.py`'s schema,
   `r_value` computed from the SAME live `ExitManager.mqh`/
   `RiskManager.mqh` R-multiple formula the EA itself uses at each bar,
   not reimplemented in the export script). One canonical bar-boundary
   convention (entry-bar-close vs. bar-open) must be picked and used
   consistently by both the export and every Python consumer -- see the
   cross-file inconsistency `analysis/analyse_giveback.py` and
   `analysis/parameter_stability.py` currently have.

   **Scoped explicitly, 2026-07-22 Codex review finding (sixth round):
   picking a convention for the EXPORT alone does not resolve this.**
   `calculate_mfe_mae.py` currently uses bar-OPEN timestamps with a
   HALF-OPEN `[entry, exit)` window; `analyse_giveback.py` currently uses
   bar-CLOSE timestamps with an INCLUSIVE `[entry, exit]` window;
   `parameter_stability.py`'s own `r_paths.csv` schema requires
   `bar_index` 0 to be an exact pre-bar `0.0`. Whichever single
   convention this task picks, it MUST also include updating whichever of
   these three Python consumers does not already match it (their window/
   timestamp semantics, not merely their docstrings) as part of THIS
   task's own scope -- naming a convention without changing the
   non-conforming consumer code leaves the real cross-file mismatch
   exactly as unresolved as before, just with an export that follows one
   of the three existing conventions arbitrarily. Real MT5 deals occur at
   tick times, not exact bar boundaries, so this also requires deciding
   (and documenting) how a tick-time entry/exit is mapped onto whichever
   discrete bar-boundary convention is chosen -- silently rounding to the
   nearest bar boundary is a real semantic choice, not a formality, and
   must be stated and tested, not left implicit.
7. **Account equity-tick export (added, 2026-07-22 Codex review finding,
   fifth round):** a script exporting a genuine intratrade, mark-to-market
   EQUITY time series (`symbol-agnostic account-level timestamp, equity`
   rows) -- the input the real "Account equity-peak giveback" and "Daily
   equity-peak giveback" master-prompt metrics require and
   `analysis.metrics.compute_balance_peak_giveback` explicitly does NOT
   provide (that function is a closed-trade BALANCE proxy only, see its
   own docstring). Without this export, neither required equity-based
   giveback metric can ever be computed from real data.
8. **Cost-scenario export (added, 2026-07-22 Codex review finding, fifth
   round):** the SAME trade set run/re-priced under multiple explicit
   spread/slippage assumptions (not just `spread_note`/`slippage_note`
   provenance strings, which record a single caller-asserted assumption,
   never vary it) -- the input `compare_releases.py`'s `surface_diff`
   currently reports as an explicit, unimplemented gap
   (`surface_not_covered.cost_sensitivity`).
9. **Session/news evidence export (added, 2026-07-22 Codex review
   finding, fifth round):** a script exporting, per trade or per bar, the
   LIVE `SessionManager.mqh` (`SN_GetSessionMinutesRemaining`'s actual
   `remaining_ratio`/`false`-for-unreadable value, not a re-derived
   OPEN/CLOSED bucket) and `NewsManager.mqh` (real event status/blackout/
   trigger-ID fields, not an invented vocabulary) state at that instant --
   the source-faithful input `notebook 04`'s session/mode/news analysis
   needs to stop being a manually-labelled synthetic fixture.
10. **The actual joined, composed pipeline run (added, 2026-07-22 Codex
    review finding, fifth round):** once items 1-2 and 9 above produce
    real `trades.csv`/journal/`news_events.csv`/session-evidence exports,
    this task's acceptance includes actually running the composed chain
    `join_trade_journal.py` -> `join_signal_to_outcome.py` ->
    `join_news_events.py` -> `performance_breakdown.py` end to end against
    them and reporting the result -- neither TASK-036 nor this task
    previously owned that composed run; notebook 04's own closing cell
    admits it is still pending.

## Files affected

- New MQL5 export scripts/functions under `03_SOURCE_CODE/MQL5/Scripts/`
  or added to the relevant `Include/` modules, including OHLC/R-path
  export, account equity-tick export, cost-scenario export, and
  session/news evidence export (Specification items 6-9, added
  2026-07-22 Codex review finding, fifth round).
- `TASKS.md` and this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- Any live trading behavior change -- these are read-only exports of
  data that already exists inside MT5/the EA's own state.
- Building the analysis that CONSUMES these exports -- that already
  exists (TASK-028's scripts); this task only produces the input data.

## Risks

- An MT5 Deals export's exact column semantics (net vs. gross profit,
  commission/swap netting) must match what `analyse_baseline.py`'s
  docstring already assumes -- verify against a real small export, don't
  assume.
- A pattern-detector export must run the EXACT same MQL5 code path the
  live EA uses, not a reimplementation, or the "cross-check" in TASK-033
  would compare Python against a second, independently-written MQL5
  path rather than the real one.

## Test plan

1. Compile clean in MetaEditor, 0 errors/0 warnings, real log evidence.
2. Run each export against real (or realistic demo-account) MT5 data and
   confirm the output matches its documented schema exactly.
3. Feed each export into its corresponding Python pipeline
   (`analyse_baseline.py`, `join_news_events.py`,
   `pattern_validation.compare_to_mql5_export`, `calculate_mfe_mae.py`,
   `analyse_giveback.py`, `parameter_stability.py`) and confirm it runs
   without a schema error -- the first genuine "Real-data run" for each.
   **`analyse_giveback.py` explicitly included, 2026-07-22 Codex review
   finding (sixth round): this list previously omitted it, so this task
   could pass its own test plan without ever running the OHLC/R-path
   export against `analyse_giveback.py` at all -- despite that script
   being one of the two Python consumers whose bar-boundary convention
   Specification item 6 requires this task to reconcile.**
4. Verify the net-P/L aggregation formula (Specification item 1) against
   a real small MT5 Deals export field-by-field (added, 2026-07-22 Codex
   review finding, fifth round).
5. Run the full composed chain (Specification item 10) end to end and
   report the result.

## Acceptance criteria

**Status legend for this section (added 2026-07-22): every item below
needs an actual RUN against real MT5 data to be genuinely satisfied, per
this task's own Test plan. This sandbox cannot attach to a live/demo MT5
terminal (the established, repeatedly-confirmed constraint documented
throughout this project) or hand-label a chart. What follows honestly
distinguishes "the export tool is built and compiles clean" from "the
export has actually been run and produced real data" -- only the user's
own desktop MT5 session can do the latter.**

- [x] (built, not yet run) Trade-history export --
      `Export_TradeHistory.mq5` produces `trades.csv` (incl. `order_id`/
      `deal_id`, net-P/L formula documented and asserted in code) in
      exactly the schema `analyse_baseline.py`/`join_signal_to_outcome.py`
      already document. **Not yet run against real deals or verified
      field-by-field -- the user's own step.**
- [x] (built, not yet run) News-calendar export --
      `Export_NewsCalendar.mq5` reuses `MT5CalendarProvider.mqh`'s own
      live `MTC_FetchEvents` (not a reimplementation) to produce
      `news_events.csv`.
- [x] (built, not yet run) Pattern-detector export --
      `Export_PatternDetectorResults.mq5` runs the live
      `CandlestickPatternEngine.mqh` predicates. **Corrected, 2026-07-22
      (Codex review finding, seventh round, P2 finding 20): this previously
      said the export was scoped to only the original 4 patterns because
      "TASK-033, not started" -- TASK-033 shipped 2026-07-22, and this same
      review round's own P1 finding 11 fix extended the export to the FULL
      matching set `detect_all_patterns()` now computes (all sixteen
      always-included candlestick patterns plus marubozu/tweezer_top/
      tweezer_bottom/three_bar_reversal), plus symbol/timestamp/OHLC/atr
      provenance columns. `ChartPatternEngine.mqh`'s own chart patterns
      (double/triple top/bottom, head-and-shoulders/inverse) are NOT
      exported by this script -- that remains a genuine, separate,
      not-yet-built export (see TASK-039's row in `TASKS.md` for the
      chart-pattern side's own status).**
- [x] (built, not yet run/labelled) Predicted-regime export + labelling
      protocol -- **corrected, 2026-07-27 (Codex round-8 P2 finding 22):
      this bullet previously described `Export_PredictedRegime.mq5` as
      running only `MarketRegimeEngine.mqh`'s raw, stateless
      `MRE_ClassifyArray` -- stale since round 7's own P1 finding 12
      rewrote it as a two-pass chronological replay of the FULL gated
      state machine (low-confidence override, historically-real
      news-blackout check via `MT5CalendarProvider.mqh`, hysteresis), not
      the raw classifier alone (the spread/liquidity gate remains a
      stated, bounded limitation -- no historical spread series exists).**
      `REGIME_LABELLING_PROTOCOL.md` defines the exact human hand-labelling
      protocol and join for the independent `actual` side. **The
      hand-labelling itself is a human task this sandbox cannot perform.**
- [x] (documented, not verified against real data) Net-P/L aggregation
      formula -- **corrected, 2026-07-27 (Codex round-8 P2 finding 22):
      this bullet previously said `net = profit + commission + swap + fee`
      per closing deal -- stale since round 7's own P0 finding 9 extracted
      `TradeHistoryAggregator.mqh` (`TA_ProcessDeal`), which tracks each
      `position_id` as a running leg and prorates ENTRY-side cost
      (commission+swap+fee accumulated across potentially multiple `IN`
      fills) across each partial close, not just the closing deal's own
      cost: `row.profit = deal.raw_profit + deal_cost + entry_cost_alloc`
      where `entry_cost_alloc = entry_cost_total * (close_volume /
      entry_volume_total)`.** Implemented and commented in
      `Export_TradeHistory.mq5`/`TradeHistoryAggregator.mqh`. **Verifying
      it against a real MT5 Deals export remains the user's own step.**
- [ ] **Explicitly deferred this sprint, per a scope decision matching
      TASK-041's own precedent (not silently skipped):** OHLC/close-bar +
      per-trade R-path export (Specification item 6), cost-scenario
      export (item 8), and session/news evidence export (item 9). Given
      every acceptance item in this task fundamentally requires a real
      MT5 run this sandbox cannot perform, and time constraints this
      sprint, these three lower-priority exports were not built. Register
      as a follow-up once the 5 higher-value exports above have actually
      been run and validated.
- [ ] Account equity-tick export -- **[x] built** (`EquityTickRecorder.mq5`,
      a standalone continuously-running EA, not a one-shot script, since
      genuine intratrade sampling needs every tick) but **not yet run**.
      This closes the missing-INFRASTRUCTURE half of TASK-028's round-6
      P0-2 finding; the metrics themselves remain blocked until the user
      actually runs it against a real/demo account.
- [ ] The composed pipeline run (Specification item 10) -- remains
      entirely blocked; needs real output from the items above first.
- [ ] Independent review completed and findings resolved -- deferred to
      this project's single, consolidated, end-of-sprint Codex review.

## Rejection criteria

Reject if an export's schema doesn't actually match what the
corresponding Python pipeline documents (requiring a Python-side
work-around defeats the point), or if the pattern-detector export
reimplements pattern logic instead of exporting the live engine's own
output.

## Status

In progress — 5 export tools built and compiling clean (0 errors/0
warnings, real MetaEditor evidence, 2026-07-22): `Export_TradeHistory.mq5`,
`Export_NewsCalendar.mq5`, `Export_PatternDetectorResults.mq5`,
`Export_PredictedRegime.mq5` (+ `REGIME_LABELLING_PROTOCOL.md`), and
`EquityTickRecorder.mq5`. OHLC/R-path, cost-scenario, and session/news
evidence exports (Specification items 6/8/9) are explicitly deferred this
sprint, not silently skipped. Every acceptance item still needs an actual
run against real MT5 data (or, for regime labelling, a human analyst) --
this sandbox cannot perform either, per this project's established
runtime-verification-batched constraint; that remains entirely the user's
own step. Independent review deferred to the consolidated end-of-sprint
Codex review.
