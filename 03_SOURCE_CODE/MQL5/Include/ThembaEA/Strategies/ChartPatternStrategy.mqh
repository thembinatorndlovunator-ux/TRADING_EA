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
  };

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
                                           const double &atr_values[],
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

   if(found_type == CPT_NONE)
      return false;
   if(pattern_is_bullish_breakout != want_bullish)
      return false; // breakout direction must confirm the trend

   if(r.breakout_index > cfg.max_breakout_age_bars)
      return false; // stale breakout

   double current_price = closes[0];
   double tol = current_atr * cfg.retest_tolerance_atr;
   if(MathAbs(current_price - r.boundary_price) > tol)
      return false; // not currently retesting

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

         if(confirmed)
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

         if(confirmed)
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
                        const double &closes[], const double &atr_values[],
                        const ENUM_MARKET_REGIME regime, const SMarketStructureState &structure,
                        const SCPStrategyConfig &cfg, SChartPatternStrategySignal &signal)
  {
   if(CPS_EvaluateTrendBreakoutRetestArray(opens, highs, lows, closes, atr_values, regime, cfg, signal))
      return true;
   if(CPS_EvaluateRangeBoundaryArray(opens, highs, lows, closes, atr_values, regime, structure, cfg,
                                      signal))
      return true;

   CPS_InitSignal(signal);
   return false;
  }

//+------------------------------------------------------------------+
//| CMARKETDATA-INTEGRATED WRAPPER                                     |
//+------------------------------------------------------------------+
bool CPS_EvaluateLive(CMarketData &md, const int atr_percentile_window, const int efficiency_window,
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
   ArrayResize(opens, window);
   ArrayResize(highs, window);
   ArrayResize(lows, window);
   ArrayResize(closes, window);
   ArrayResize(atr_values, window);
   for(int i = 0; i < window; i++)
     {
      if(!md.GetOpen(i, opens[i]) || !md.GetHigh(i, highs[i]) || !md.GetLow(i, lows[i]) ||
         !md.GetClose(i, closes[i]) || !md.GetATR(i, atr_values[i], 14))
         return false;
     }

   SMarketStructureState structure;
   MS_ComputeStructureArray(highs, lows, closes, cfg.depth, cfg.max_lookback, structure);

   return CPS_EvaluateArray(opens, highs, lows, closes, atr_values, regime_read.regime, structure,
                             cfg, signal);
  }
