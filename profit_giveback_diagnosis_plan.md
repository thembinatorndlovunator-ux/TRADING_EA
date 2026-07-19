# Profit Giveback Diagnosis — Plan (not a diagnosis)

Per `00_MASTER_PROMPT_FOR_CLAUDE.md` step 10 / `CLAUDE.md`, this document is
a **plan**, not a finding. `01_BASELINE/backtests/` is empty and no trade
history, journal CSV, or account statement exists anywhere in this repo yet.
Without executed-trade data there is nothing to diagnose — this document
records what each EA's code *currently claims* its giveback protection does
(verified by reading the source, not by observing behavior), what data is
missing, and the concrete analysis steps to run once that data exists.

## What each EA's code-level giveback/trailing/exit logic currently does

### SmartCoreEngine V6.37

- **Profit giveback guard** — `GuardOpenProfits` (`01_BASELINE/EA_V637/Thembabot14 Max.mq5:7083-7168`).
  Controlled by `InpUseProfitGivebackGuard` (default `true`), arms once open
  R reaches `InpGivebackArmRR` (default `1.25`), then closes if price
  retraces so that more than `InpMaxProfitGivebackPercent` (default `60.0`)
  of the peak open profit has been given back.
- **Version-history evidence of prior tuning** (lines 1–46, in-file
  comment): V6.32 explicitly states *"giveback guard loosened (1.25R arm,
  60% tolerance) so winners breathe through normal pullbacks"* — i.e. the
  current defaults are already a loosened version of an earlier, tighter
  guard. V6.35 separately notes break-even moved to 1R and "the time exit
  relaxed for slower runners." Both read as direct responses to some
  earlier version giving back too much profit or exiting winners too early
  — but the comment is a developer's account of a past decision, not
  evidence from this repo's trade data. **HYPOTHESIS**, not fact, until
  trade data confirms whether the loosening helped or hurt.
- **Daily limits / resets**: `SetupDailyState`, `ResetDailyStateIfNeeded`,
  `CheckDailyLimits` (lines 3260–3324) and profit accumulators
  (3325–3388) reset daily P&L tracking; these interact with the giveback
  guard by resetting its reference state each day, but the exact
  interaction (e.g. does a daily reset clear an armed-but-not-yet-triggered
  guard mid-position?) needs to be traced in code, not assumed.

### NdlovuSMC V8.11

- **Giveback guard** (`01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5:1448-1451`,
  inside `ManageBasket`): arms once basket peak R (`g_basket_peak_r`)
  reaches `InpGivebackArmR` (default `0.8`), then closes the whole basket
  once R drops back to `InpGivebackFloorR` (default `0.1`) — i.e. "bank the
  scalp" rather than let a winner fully round-trip to breakeven or a loss.
- **Version-history evidence of prior tuning** (lines 1–29, in-file
  comment): V8.11 states the stop window widened from *"0.35-0.90 to
  0.60-1.40 M15 ATRs"* with a larger buffer, "the floor AND cap move
  together, the V6.35 lesson" — an explicit cross-reference to the other
  baseline's earlier fix, and baskets now default to 2 legs (down from a
  higher default) "so each leg carries 0.5% and targets stay at 1.0R /
  1.5R." This reads as a deliberate risk-per-leg reduction, again a
  developer's account, not yet evidence from trade data.
- **45-minute time exit, peak-drawdown lock, break-even-on-first-bank**
  are all named in the header comment as existing exit/protection
  mechanisms (lines 17–20) alongside the giveback guard; their precise
  code locations and interactions are catalogued in `baseline_v811_audit.md`.
- **No journal files** is stated explicitly in the file's own header
  comment (line 17) — V811 has no equivalent of V637's CSV journal/learning
  system, so there is no historical statistics)-based adjustment to
  investigate for this baseline at all; giveback behavior here is purely
  the fixed-parameter guard described above.

## What data is missing to actually diagnose why profit gets given back

1. **Trade-history export** (open/close time, entry/exit price, direction,
   volume, P&L, symbol) for both EAs, ideally from a live or demo run, or at
   minimum a Strategy Tester run with realistic costs — none exists in
   `01_BASELINE/backtests/` or `08_RESULTS/trade_exports/` yet (both empty).
2. **MFE/MAE per trade** — needed to see how much open profit each trade
   reached before the giveback guard (or lack of one) let it retrace.
3. **V637's journal CSV** (`ndlovujournal_v637.csv`, per `InpJournalFileName`
   input) — would show the EA's own recorded per-trade/per-strategy
   outcomes and regime-learning adjustments, but only exists once the EA has
   actually run; nothing has been generated in this repo.
4. **Equity curve / peak-to-trough series** per session and per day, to
   compute equity-peak giveback and daily giveback separately from
   per-trade giveback.
5. **A record of which giveback-guard parameters were active** for any
   given historical run (both EAs' guards are input-driven, so the same
   code can behave very differently depending on `.set` file — this is
   exactly why the orphaned `SmartCore_v3_Tuned.set.txt` provenance problem
   noted in `01_BASELINE/setfiles/IDENTITY.md` and resolved in
   `baseline_comparison.md` matters here too: without knowing which set file
   (if any) was live during any historical trading, giveback numbers from
   that period can't be attributed to specific parameter values).

## Concrete Python analysis steps to run once that data exists

Per `00_MASTER_PROMPT_FOR_CLAUDE.md` section 19:

1. **`join_trade_journal.py`** — join trade-history export to the V637
   journal CSV (once one exists) and to screenshots via timestamp/symbol,
   producing one unified per-trade record. For V811 (no journal file),
   join trade-history directly to screenshot timestamps only.
2. **`calculate_mfe_mae.py`** → feeds `05_mfe_mae_exit_analysis.ipynb** —
   for every trade, compute MFE, MAE, and R-multiple at (a) the moment the
   giveback guard armed, (b) the moment it fired (or would have fired,
   for A/B comparison), and (c) actual close. This directly tests whether
   `InpGivebackArmRR`/`InpMaxProfitGivebackPercent` (V637) and
   `InpGivebackArmR`/`InpGivebackFloorR` (V811) are well-calibrated versus
   the empirical MFE distribution, rather than tuned by feel as the version
   history suggests.
3. **`analyse_giveback.py`** → feeds `02_profit_giveback_analysis.ipynb` —
   compute equity-peak giveback (account-level) and daily-peak giveback
   separately from per-trade giveback; segment by symbol, session, and
   (once regime detection exists) by regime, to see whether giveback
   concentrates in specific conditions (e.g. the choppy/ranging clusters
   flagged as a hypothesis in `01_BASELINE/screenshots/visual_notes.md`).
4. **Monte Carlo / bootstrap** (`monte_carlo.py`) — once enough trades
   exist, resample trade sequences to check whether observed giveback is
   within normal variance for the strategy's win/loss distribution, or is
   systematically worse than chance would predict (a real behavioral
   problem in the exit logic, not noise).
5. **Parameter stability check** (`06_parameter_stability.ipynb`) — vary
   `InpGivebackArmRR`/`InpMaxProfitGivebackPercent` (V637) and
   `InpGivebackArmR`/`InpGivebackFloorR` (V811) across neighbouring values
   once a backtest harness exists, to see if the currently-hardcoded
   defaults sit in a stable region or on a cliff edge — directly relevant
   given both files' version histories show these values were hand-tuned
   at least once already without (as far as this repo's evidence shows) a
   documented systematic sweep.

## Acceptance criteria for turning this into an actual diagnosis

- At minimum one trade-history export (demo, live, or Strategy Tester with
  documented settings — symbol, broker, date range, spread/slippage model,
  set file used) exists in `08_RESULTS/trade_exports/`.
- MFE/MAE has been computed per trade.
- Findings are reported per-symbol and per-session at minimum, ideally
  per-regime once `MarketRegimeEngine` exists.
- Any claim of "giveback is caused by X" is backed by a specific computed
  statistic (e.g. "62% of giveback-guard triggers occurred within 10
  minutes of a countertrend spike") — not a restated version-history
  comment.
