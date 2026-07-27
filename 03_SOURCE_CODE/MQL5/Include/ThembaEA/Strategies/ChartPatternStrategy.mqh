//+------------------------------------------------------------------+
//| ChartPatternStrategy.mqh                                          |
//| Themba Adaptive Intraday Engine — Strategies                       |
//|                                                                    |
//| The third of six strategy families, per                             |
//| STRATEGY_SPEC_CHART_PATTERN.md. Two setups, mirroring                |
//| SMCStrategy.mqh's multi-setup precedent: trend-breakout-retest        |
//| (TRENDING regimes, breakout direction must confirm the trend — a      |
//| reversal-pattern breakout in the trend's own direction is read as     |
//| continuation, not counter-trend) and range-boundary (RANGING regime,  |
//| a double top/bottom whose extreme coincides with the current range    |
//| boundary). Composes ChartPatternEngine.mqh (TASK-018) and              |
//| CandlestickPatternEngine.mqh directly — no pattern-detection or        |
//| stop/target math is duplicated; unlike SMCStrategy.mqh, this strategy  |
//| uses the pattern engine's own real target formula (section 6),         |
//| not a provisional placeholder.                                          |
//|                                                                    |
//| The COMPRESSION-regime gated early-breakout variant is explicitly       |
//| deferred — see the specification's "Out of scope" section.              |
//+------------------------------------------------------------------+
#property strict

#include "../Market/MarketRegimeEngine.mqh"
#include "../Patterns/ChartPatternEngine.mqh"
#include "../Patterns/CandlestickPatternEngine.mqh"
#include "../Patterns/ChartPatternLifecycle.mqh"

enum ENUM_CPS_SETUP
  {
   CPS_NONE,
   CPS_TREND_BREAKOUT_RETEST,
   CPS_RANGE_BOUNDARY
  };

enum ENUM_CPS_DIRECTION
  {
   CPSD_NONE,
   CPSD_LONG,
   CPSD_SHORT
  };

struct SChartPatternStrategySignal
  {
   bool                     found;
   ENUM_CPS_SETUP           setup_type;
   ENUM_CPS_DIRECTION       direction;
   ENUM_CHART_PATTERN_TYPE  pattern_type;
   double                   entry_price;
   double                   stop_price;
   double                   target_price;
   string                   candlestick_pattern;
  };

struct SCPStrategyConfig
  {
   int    depth;
   int    max_lookback;
   double price_tolerance_atr;
   double min_pullback_atr;         // double top/bottom
   double min_head_prominence_atr;  // head-and-shoulders
   double time_tolerance;           // head-and-shoulders
   int    trend_bars;               // preceding-trend prerequisite
   double breakout_buffer_atr;
   int    max_breakout_age_bars;
   double retest_tolerance_atr;
   int    candlestick_trend_lookback;
   // **Added, 2026-07-27 (Codex review finding, ninth round, P1 finding 11):
   // CPT_CheckRetestArray's own hold/fail parameters, per TASK-002_PHASE2_
   // SPECIFICATION.md section 6 (InpRetestFailureATR default 0.2,
   // InpRetestMaxBars default 10) -- previously never wired to any live
   // caller at all (the strategy used current-price proximity only, never
   // calling the engine's own hold/fail predicate).
   double retest_failure_atr;
   int    retest_max_bars;
  };

//+------------------------------------------------------------------+
//| **Added, 2026-07-27 (Codex review finding, ninth round, P1 finding 11):  |
//| applies ChartPatternLifecycle.mqh's persisted state machine to an          |
//| already-breakout-confirmed pattern instance (CPT_Detect*Array's own          |
//| 'found' + 'breakout_index >= 0' contract). Returns true ONLY on the exact       |
//| bar this instance's retest resolves to TRADED for the first and only time         |
//| -- every other case (already consumed, not yet touching the retest zone,             |
//| retest still pending, or a transition to INVALIDATED/EXPIRED this very                  |
//| call) returns false. A CONSUMED instance (TRADED/INVALIDATED/EXPIRED)                       |
//| never re-enters eligibility, per section 6's own "permanently marks an                         |
//| instance TRADED as consumed" requirement, extended to all three terminal                            |
//| states.                                                                                                    |
//|                                                                    |
//| **Stated scope boundary:** the false-break invalidation path (section 6:      |
//| "a confirmed close back inside the boundary within InpFalseBreakBars bars       |
//| of breakout") is NOT implemented here -- a separate predicate this fix           |
//| does not attempt, named honestly rather than silently folded into the               |
//| retest-fail path (which is a DIFFERENT trigger: failing AFTER entering the              |
//| retest zone, not before it). See ChartPatternLifecycle.mqh's own header             |
//| for the FORMING-stage tracking this module also does not attempt.**                     |
//+------------------------------------------------------------------+
bool CPS_ApplyLifecycle(const string symbol, const long magic,
                          const ENUM_CHART_PATTERN_TYPE pattern_type, const int pivot_index_1,
                          const int pivot_index_2, const datetime &times[], const double &closes[],
                          const double current_price, const double boundary_price,
                          const bool is_bullish_breakout, const double current_atr,
                          const double retest_tolerance_atr, const double retest_failure_atr,
                          const int retest_max_bars)
  {
   int n = ArraySize(times);
   if(pivot_index_1 < 0 || pivot_index_2 < 0 || pivot_index_1 >= n || pivot_index_2 >= n)
      return false; // cannot form a durable identity without both pivot times

   datetime pivot1_time = times[pivot_index_1];
   datetime pivot2_time = times[pivot_index_2];

   ENUM_CP_LIFECYCLE_STATE state = CPL_GetState(symbol, magic, (int)pattern_type, pivot1_time,
                                                  pivot2_time);
   if(CPL_IsTerminal(state))
      return false; // consumed (TRADED/INVALIDATED/EXPIRED) -- never re-enters eligibility

   if(state == CPL_STATE_NONE)
     {
      // Newly confirmed instance -- first time this exact identity has ever
      // been observed.
      CPL_SetState(symbol, magic, (int)pattern_type, pivot1_time, pivot2_time, CPL_STATE_CONFIRMED);
      CPL_SetConfirmedTime(symbol, magic, (int)pattern_type, pivot1_time, pivot2_time, times[0]);
      state = CPL_STATE_CONFIRMED;
     }

   double tol = current_atr * retest_tolerance_atr;
   bool currently_in_retest_zone = MathAbs(current_price - boundary_price) <= tol;

   if(state == CPL_STATE_CONFIRMED)
     {
      if(!currently_in_retest_zone)
         return false; // still waiting to touch the retest zone
      CPL_SetState(symbol, magic, (int)pattern_type, pivot1_time, pivot2_time, CPL_STATE_RETESTING);
      CPL_SetRetestTouchTime(symbol, magic, (int)pattern_type, pivot1_time, pivot2_time, times[0]);
      return false; // just entered RETESTING this bar -- hold/fail is evaluated on a later bar
     }

   // state == CPL_STATE_RETESTING: recompute the touch bar's CURRENT "bars
   // ago" index from its own persisted TIME (bar indices shift by one every
   // new bar -- the raw index recorded at touch time is stale by now).
   datetime touch_time = CPL_GetRetestTouchTime(symbol, magic, (int)pattern_type, pivot1_time,
                                                  pivot2_time);
   int touch_index_now = -1;
   for(int k = 0; k < n; k++)
     {
      if(times[k] == touch_time)
        {
         touch_index_now = k;
         break;
        }
     }
   if(touch_index_now < 0 || touch_index_now > retest_max_bars)
     {
      // The touch bar has either rolled out of the shared evaluation
      // window (cannot verify -- fail closed) or InpRetestMaxBars has
      // elapsed with neither a hold nor a fail resolved -- section 6's own
      // third RETESTING transition path.
      CPL_SetState(symbol, magic, (int)pattern_type, pivot1_time, pivot2_time, CPL_STATE_EXPIRED);
      return false;
     }

   bool holds;
   if(!CPT_CheckRetestArray(closes, touch_index_now, boundary_price, is_bullish_breakout, current_atr,
                             retest_failure_atr, retest_max_bars, holds))
      return false; // touch_index invalid -- should not happen given the check above

   if(holds)
     {
      CPL_SetState(symbol, magic, (int)pattern_type, pivot1_time, pivot2_time, CPL_STATE_TRADED);
      return true; // eligible to trade -- this exact instance is now consumed forever after
     }

   CPL_SetState(symbol, magic, (int)pattern_type, pivot1_time, pivot2_time, CPL_STATE_INVALIDATED);
   return false;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-27 (Codex review finding, ninth round, P1 finding 11):  |
//| the range-boundary setup has no breakout/retest cycle of its own (it        |
//| fires as soon as a double top/bottom's own extreme coincides with the         |
//| current range boundary AND a confirming candlestick appears) -- its own            |
//| consumed-suppression is therefore simpler: the FIRST time this exact               |
//| identity is about to emit a real signal, mark it TRADED (consumed)                    |
//| immediately and allow the emission; any LATER call for the SAME identity                 |
//| (the same pivots rediscovered, e.g. a second confirming candlestick days                    |
//| later at the same boundary) is suppressed. Call only at the exact point                        |
//| an entry signal is otherwise about to be emitted (after candlestick                                confirmation
//| has already passed), never earlier.**                                                                 |
//+------------------------------------------------------------------+
bool CPS_ConsumeRangeBoundaryInstance(const string symbol, const long magic,
                                        const ENUM_CHART_PATTERN_TYPE pattern_type,
                                        const int pivot_index_1, const int pivot_index_2,
                                        const datetime &times[])
  {
   int n = ArraySize(times);
   if(pivot_index_1 < 0 || pivot_index_2 < 0 || pivot_index_1 >= n || pivot_index_2 >= n)
      return false;

   datetime pivot1_time = times[pivot_index_1];
   datetime pivot2_time = times[pivot_index_2];

   ENUM_CP_LIFECYCLE_STATE state = CPL_GetState(symbol, magic, (int)pattern_type, pivot1_time,
                                                  pivot2_time);
   if(CPL_IsTerminal(state))
      return false; // already consumed by an earlier bar's own emission

   CPL_SetState(symbol, magic, (int)pattern_type, pivot1_time, pivot2_time, CPL_STATE_TRADED);
   return true;
  }

void CPS_InitSignal(SChartPatternStrategySignal &signal)
  {
   signal.found = false;
   signal.setup_type = CPS_NONE;
   signal.direction = CPSD_NONE;
   signal.pattern_type = CPT_NONE;
   signal.entry_price = 0.0;
   signal.stop_price = 0.0;
   signal.target_price = 0.0;
   signal.candlestick_pattern = "";
  }

//+------------------------------------------------------------------+
//| Setup 1: trend-breakout-retest. Tries all four pattern types; the    |
//| first one found with a confirmed breakout direction matching the      |
//| trend regime is used.                                                 |
//+------------------------------------------------------------------+
bool CPS_EvaluateTrendBreakoutRetestArray(const double &opens[], const double &highs[],
                                           const double &lows[], const double &closes[],
                                           const double &atr_values[], const datetime &times[],
                                           const string symbol, const long magic,
                                           const ENUM_MARKET_REGIME regime,
                                           const SCPStrategyConfig &cfg,
                                           SChartPatternStrategySignal &signal)
  {
   CPS_InitSignal(signal);
   if(regime != REGIME_TRENDING_UP && regime != REGIME_TRENDING_DOWN)
      return false;

   int n = ArraySize(closes);
   if(n < 1 || ArraySize(atr_values) < 1)
      return false;
   double current_atr = atr_values[0];
   if(current_atr <= 0.0)
      return false;

   bool want_bullish = (regime == REGIME_TRENDING_UP);

   SChartPatternResult r;
   r.found = false;
   r.type = CPT_NONE;
   r.boundary_price = 0.0;
   r.extreme_price = 0.0;
   r.target = 0.0;
   r.stop = 0.0;
   r.breakout_index = -1;
   ENUM_CHART_PATTERN_TYPE found_type = CPT_NONE;
   bool pattern_is_bullish_breakout = false;

   SChartPatternResult rTop;
   if(CPT_DetectDoubleTopArray(highs, lows, closes, cfg.depth, cfg.max_lookback, current_atr,
                                cfg.price_tolerance_atr, cfg.min_pullback_atr, cfg.trend_bars,
                                cfg.breakout_buffer_atr, rTop) && rTop.breakout_index >= 0)
     { r = rTop; found_type = CPT_DOUBLE_TOP; pattern_is_bullish_breakout = false; }

   if(found_type == CPT_NONE)
     {
      SChartPatternResult rBot;
      if(CPT_DetectDoubleBottomArray(highs, lows, closes, cfg.depth, cfg.max_lookback, current_atr,
                                      cfg.price_tolerance_atr, cfg.min_pullback_atr, cfg.trend_bars,
                                      cfg.breakout_buffer_atr, rBot) && rBot.breakout_index >= 0)
        { r = rBot; found_type = CPT_DOUBLE_BOTTOM; pattern_is_bullish_breakout = true; }
     }

   if(found_type == CPT_NONE)
     {
      SChartPatternResult rHs;
      if(CPT_DetectHeadAndShouldersArray(highs, lows, closes, cfg.depth, cfg.max_lookback, current_atr,
                                          cfg.price_tolerance_atr, cfg.time_tolerance,
                                          cfg.min_head_prominence_atr, cfg.breakout_buffer_atr,
                                          cfg.trend_bars, rHs) && rHs.breakout_index >= 0)
        { r = rHs; found_type = CPT_HEAD_SHOULDERS; pattern_is_bullish_breakout = false; }
     }

   if(found_type == CPT_NONE)
     {
      SChartPatternResult rIhs;
      if(CPT_DetectInverseHeadAndShouldersArray(highs, lows, closes, cfg.depth, cfg.max_lookback,
                                                 current_atr, cfg.price_tolerance_atr,
                                                 cfg.time_tolerance, cfg.min_head_prominence_atr,
                                                 cfg.breakout_buffer_atr, cfg.trend_bars, rIhs) &&
         rIhs.breakout_index >= 0)
        { r = rIhs; found_type = CPT_INV_HEAD_SHOULDERS; pattern_is_bullish_breakout = true; }
     }

   // **Added, 2026-07-22 (Codex review finding, seventh round, P1 finding
   // 11): CPT_DetectTripleTopArray/CPT_DetectTripleBottomArray (TASK-039)
   // were never called from any live strategy path -- module-only coverage,
   // per the review's own wording. Wired in here (the same trend-breakout-
   // retest setup double top/H&S already use); range-boundary deliberately
   // stays double-top/bottom only, per that setup's own existing, separate
   // scope note.**
   if(found_type == CPT_NONE)
     {
      SChartPatternResult rTt;
      if(CPT_DetectTripleTopArray(highs, lows, closes, cfg.depth, cfg.max_lookback, current_atr,
                                   cfg.price_tolerance_atr, cfg.min_pullback_atr, cfg.trend_bars,
                                   cfg.breakout_buffer_atr, rTt) && rTt.breakout_index >= 0)
        { r = rTt; found_type = CPT_TRIPLE_TOP; pattern_is_bullish_breakout = false; }
     }

   if(found_type == CPT_NONE)
     {
      SChartPatternResult rTb;
      if(CPT_DetectTripleBottomArray(highs, lows, closes, cfg.depth, cfg.max_lookback, current_atr,
                                      cfg.price_tolerance_atr, cfg.min_pullback_atr, cfg.trend_bars,
                                      cfg.breakout_buffer_atr, rTb) && rTb.breakout_index >= 0)
        { r = rTb; found_type = CPT_TRIPLE_BOTTOM; pattern_is_bullish_breakout = true; }
     }

   if(found_type == CPT_NONE)
      return false;
   if(pattern_is_bullish_breakout != want_bullish)
      return false; // breakout direction must confirm the trend

   if(r.breakout_index > cfg.max_breakout_age_bars)
      return false; // stale breakout
   // **Added, 2026-07-22 (Codex review finding, eighth round, P1 finding
   // 14): "Retest" requires the breakout to have already happened, and
   // THEN price returning to the boundary afterward -- a breakout found at
   // breakout_index==0 (the CURRENT bar) has price breaking out and being
   // checked for "retest" confirmation on the exact same single bar, which
   // is not a retest at all (there is no later bar in which price could
   // have come back). Requiring breakout_index >= 1 (a strictly earlier
   // bar) is a real, bounded fix for "no state proves that breakout
   // occurred first and then price returned, allowing same-bar breakout/
   // retest behavior" -- the review's own more general ask (a persisted
   // FORMING/CONFIRMED/RETESTING/TRADED/INVALIDATED/EXPIRED registry
   // preventing the SAME pattern instance from being traded repeatedly
   // across multiple bars) remains a substantial, separate architectural
   // task, not attempted here -- this detector is still stateless and
   // rediscovers geometry fresh every bar, matching finding 12's own
   // explicitly-stated, still-deferred pipeline-reorder scope.**
   if(r.breakout_index < 1)
      return false; // breakout and retest cannot be the same single bar

   double current_price = closes[0];
   // **Fixed, 2026-07-27 (Codex review finding, ninth round, P1 finding 11):
   // the naive current-price-proximity check (kept no persisted state across
   // bars at all) is replaced by the real, persisted lifecycle registry --
   // ChartPatternLifecycle.mqh -- which gives this exact pattern instance a
   // durable identity (type + the two identity pivots' own bar TIMES),
   // tracks it through CONFIRMED -> RETESTING -> TRADED/INVALIDATED/EXPIRED,
   // calls the engine's own CPT_CheckRetestArray hold/fail predicate (never
   // wired to any live caller before this fix), and permanently suppresses a
   // TRADED/INVALIDATED/EXPIRED instance from ever re-entering eligibility --
   // closing "rediscovered geometry can trade repeatedly."**
   if(!CPS_ApplyLifecycle(symbol, magic, found_type, r.pivot_index_1, r.pivot_index_2, times, closes,
                           current_price, r.boundary_price, pattern_is_bullish_breakout, current_atr,
                           cfg.retest_tolerance_atr, cfg.retest_failure_atr, cfg.retest_max_bars))
      return false; // not yet eligible this bar (still forming/retesting), or consumed/expired

   string pattern_name = "";
   bool confirmed = false;
   if(want_bullish)
     {
      if(CP_IsBullishPinBarArray(opens, highs, lows, closes, 0, cfg.candlestick_trend_lookback))
        { confirmed = true; pattern_name = "bullish_pin_bar"; }
      else if(CP_IsBullishEngulfingArray(opens, highs, lows, closes, 0))
        { confirmed = true; pattern_name = "bullish_engulfing"; }
     }
   else
     {
      if(CP_IsBearishPinBarArray(opens, highs, lows, closes, 0, cfg.candlestick_trend_lookback))
        { confirmed = true; pattern_name = "bearish_pin_bar"; }
      else if(CP_IsBearishEngulfingArray(opens, highs, lows, closes, 0))
        { confirmed = true; pattern_name = "bearish_engulfing"; }
     }

   if(!confirmed)
      return false;

   signal.found = true;
   signal.setup_type = CPS_TREND_BREAKOUT_RETEST;
   signal.direction = want_bullish ? CPSD_LONG : CPSD_SHORT;
   signal.pattern_type = found_type;
   signal.entry_price = current_price;
   signal.stop_price = r.stop;
   signal.target_price = r.target;
   signal.candlestick_pattern = pattern_name;
   return true;
  }

//+------------------------------------------------------------------+
//| Setup 2: range-boundary. Only double top/bottom, per section 3's     |
//| own wording (triple deferred, per ChartPatternEngine.mqh's stated     |
//| scope).                                                                |
//+------------------------------------------------------------------+
bool CPS_EvaluateRangeBoundaryArray(const double &opens[], const double &highs[], const double &lows[],
                                     const double &closes[], const double &atr_values[],
                                     const datetime &times[], const string symbol, const long magic,
                                     const ENUM_MARKET_REGIME regime,
                                     const SMarketStructureState &structure,
                                     const SCPStrategyConfig &cfg,
                                     SChartPatternStrategySignal &signal)
  {
   CPS_InitSignal(signal);
   if(regime != REGIME_RANGING)
      return false;
   if(!structure.valid)
      return false;

   int n = ArraySize(closes);
   if(n < 1 || ArraySize(atr_values) < 1)
      return false;
   double current_atr = atr_values[0];
   if(current_atr <= 0.0)
      return false;

   double tol = current_atr * cfg.retest_tolerance_atr;

   SChartPatternResult rTop;
   if(CPT_DetectDoubleTopArray(highs, lows, closes, cfg.depth, cfg.max_lookback, current_atr,
                                cfg.price_tolerance_atr, cfg.min_pullback_atr, cfg.trend_bars,
                                cfg.breakout_buffer_atr, rTop))
     {
      if(MathAbs(rTop.extreme_price - structure.range_high) <= tol)
        {
         string pattern_name = "";
         bool confirmed = false;
         if(CP_IsBearishPinBarArray(opens, highs, lows, closes, 0, cfg.candlestick_trend_lookback))
           { confirmed = true; pattern_name = "bearish_pin_bar"; }
         else if(CP_IsBearishEngulfingArray(opens, highs, lows, closes, 0))
           { confirmed = true; pattern_name = "bearish_engulfing"; }

         if(confirmed && CPS_ConsumeRangeBoundaryInstance(symbol, magic, CPT_DOUBLE_TOP,
                                                            rTop.pivot_index_1, rTop.pivot_index_2,
                                                            times))
           {
            signal.found = true;
            signal.setup_type = CPS_RANGE_BOUNDARY;
            signal.direction = CPSD_SHORT;
            signal.pattern_type = CPT_DOUBLE_TOP;
            signal.entry_price = closes[0];
            signal.stop_price = rTop.stop;
            signal.target_price = rTop.target;
            signal.candlestick_pattern = pattern_name;
            return true;
           }
        }
     }

   SChartPatternResult rBot;
   if(CPT_DetectDoubleBottomArray(highs, lows, closes, cfg.depth, cfg.max_lookback, current_atr,
                                   cfg.price_tolerance_atr, cfg.min_pullback_atr, cfg.trend_bars,
                                   cfg.breakout_buffer_atr, rBot))
     {
      if(MathAbs(rBot.extreme_price - structure.range_low) <= tol)
        {
         string pattern_name = "";
         bool confirmed = false;
         if(CP_IsBullishPinBarArray(opens, highs, lows, closes, 0, cfg.candlestick_trend_lookback))
           { confirmed = true; pattern_name = "bullish_pin_bar"; }
         else if(CP_IsBullishEngulfingArray(opens, highs, lows, closes, 0))
           { confirmed = true; pattern_name = "bullish_engulfing"; }

         if(confirmed && CPS_ConsumeRangeBoundaryInstance(symbol, magic, CPT_DOUBLE_BOTTOM,
                                                            rBot.pivot_index_1, rBot.pivot_index_2,
                                                            times))
           {
            signal.found = true;
            signal.setup_type = CPS_RANGE_BOUNDARY;
            signal.direction = CPSD_LONG;
            signal.pattern_type = CPT_DOUBLE_BOTTOM;
            signal.entry_price = closes[0];
            signal.stop_price = rBot.stop;
            signal.target_price = rBot.target;
            signal.candlestick_pattern = pattern_name;
            return true;
           }
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Dispatcher.                                                        |
//+------------------------------------------------------------------+
bool CPS_EvaluateArray(const double &opens[], const double &highs[], const double &lows[],
                        const double &closes[], const double &atr_values[], const datetime &times[],
                        const string symbol, const long magic,
                        const ENUM_MARKET_REGIME regime, const SMarketStructureState &structure,
                        const SCPStrategyConfig &cfg, SChartPatternStrategySignal &signal)
  {
   if(CPS_EvaluateTrendBreakoutRetestArray(opens, highs, lows, closes, atr_values, times, symbol, magic,
                                            regime, cfg, signal))
      return true;
   if(CPS_EvaluateRangeBoundaryArray(opens, highs, lows, closes, atr_values, times, symbol, magic,
                                      regime, structure, cfg, signal))
      return true;

   CPS_InitSignal(signal);
   return false;
  }

//+------------------------------------------------------------------+
//| CMARKETDATA-INTEGRATED WRAPPER                                     |
//+------------------------------------------------------------------+
bool CPS_EvaluateLive(CMarketData &md, const string symbol, const long magic,
                       const int atr_percentile_window, const int efficiency_window,
                       const int ema_period, const int ema_slope_bars, const int adx_period,
                       const double trend_threshold, const double expansion_threshold,
                       const double compression_threshold, const double min_efficiency,
                       const double trend_slope_atr_divisor, const SCPStrategyConfig &cfg,
                       SChartPatternStrategySignal &signal)
  {
   CPS_InitSignal(signal);

   SRegimeRead regime_read;
   if(!MRE_ClassifyLive(md, atr_percentile_window, efficiency_window, ema_period, ema_slope_bars,
                         adx_period, cfg.depth, cfg.max_lookback, trend_threshold, expansion_threshold,
                         compression_threshold, min_efficiency, trend_slope_atr_divisor, regime_read))
      return false;

   int window = cfg.depth + 2 * cfg.max_lookback + cfg.depth + 1;
   if(!md.HasBars(window))
      return false;

   double opens[], highs[], lows[], closes[], atr_values[];
   datetime times[];
   ArrayResize(opens, window);
   ArrayResize(highs, window);
   ArrayResize(lows, window);
   ArrayResize(closes, window);
   ArrayResize(atr_values, window);
   ArrayResize(times, window);
   for(int i = 0; i < window; i++)
     {
      if(!md.GetOpen(i, opens[i]) || !md.GetHigh(i, highs[i]) || !md.GetLow(i, lows[i]) ||
         !md.GetClose(i, closes[i]) || !md.GetATR(i, atr_values[i], 14) || !md.GetTime(i, times[i]))
         return false;
     }

   SMarketStructureState structure;
   MS_ComputeStructureArray(highs, lows, closes, cfg.depth, cfg.max_lookback, structure);

   return CPS_EvaluateArray(opens, highs, lows, closes, atr_values, times, symbol, magic,
                             regime_read.regime, structure, cfg, signal);
  }
