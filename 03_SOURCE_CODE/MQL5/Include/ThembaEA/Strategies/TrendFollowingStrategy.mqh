//+------------------------------------------------------------------+
//| TrendFollowingStrategy.mqh                                        |
//| Themba Adaptive Intraday Engine — Strategies                       |
//|                                                                    |
//| The fourth of six strategy families, per                            |
//| STRATEGY_SPEC_TREND_FOLLOWING.md. Two setups: trendline pullback      |
//| (TRENDING regimes only) and momentum continuation (TRENDING AND       |
//| VOLATILITY_EXPANSION regimes, per section 3's "momentum-continuation  |
//| half").                                                                |
//|                                                                    |
//| TF_FindTrendlineArray is the concrete fix for V6.37's confirmed        |
//| BuildThreePointTrendLine/EvaluateTrendBreaker defect (two-anchor-only  |
//| construction, constant projected level) — per                          |
//| TASK-002_PHASE2_SPECIFICATION.md section 7's explicit porting          |
//| decision: three validated anchors, the middle one checked against       |
//| the line through the outer two, re-projected fresh every call. Reuses   |
//| ChartPatternEngine.mqh's CPT_LinearInterpolate directly — no             |
//| interpolation math is duplicated a third time.                           |
//|                                                                    |
//| Stop and target formulas are STATED SIMPLIFICATIONS (ATR-distance       |
//| stop, 2R target) — section 7's real target/stop selection logic does    |
//| not exist as a built module yet; see STRATEGY_SPEC_TREND_FOLLOWING.md's  |
//| own "Stop-Loss Formula"/"Target Formula" sections for why.               |
//+------------------------------------------------------------------+
#property strict

#include "../Market/MarketRegimeEngine.mqh"
#include "../Patterns/ChartPatternEngine.mqh"
#include "../Patterns/CandlestickPatternEngine.mqh"

enum ENUM_TFS_SETUP
  {
   TFS_NONE,
   TFS_TRENDLINE_PULLBACK,
   TFS_MOMENTUM_CONTINUATION
  };

enum ENUM_TFS_DIRECTION
  {
   TFSD_NONE,
   TFSD_LONG,
   TFSD_SHORT
  };

struct STrendlineResult
  {
   bool   found;
   int    anchor1_index; // newest
   double anchor1_price;
   int    anchor2_index; // middle
   double anchor2_price;
   int    anchor3_index; // oldest
   double anchor3_price;
   double current_value;  // trendline projected to logical index 0
   bool   is_support;
  };

struct STFStrategySignal
  {
   bool               found;
   ENUM_TFS_SETUP     setup_type;
   ENUM_TFS_DIRECTION direction;
   double             entry_price;
   double             stop_price;
   double             target_price;
   string             candlestick_pattern;
  };

struct STFConfig
  {
   int    depth;
   int    max_lookback;
   double middle_tolerance_atr;
   double touch_tolerance_atr;
   double stop_buffer_atr;
   int    momentum_lookback_bars;
   double displacement_atr_multiple;
   double max_pullback_atr;
   double momentum_stop_atr;
   int    candlestick_trend_lookback;
  };

void TFS_InitSignal(STFStrategySignal &signal)
  {
   signal.found = false;
   signal.setup_type = TFS_NONE;
   signal.direction = TFSD_NONE;
   signal.entry_price = 0.0;
   signal.stop_price = 0.0;
   signal.target_price = 0.0;
   signal.candlestick_pattern = "";
  }

//+------------------------------------------------------------------+
//| Finds and validates a three-anchor trendline. 'want_support' true    |
//| scans confirmed swing LOWS (an uptrend/support line); false scans     |
//| confirmed swing HIGHS (a downtrend/resistance line).                  |
//+------------------------------------------------------------------+
bool TF_FindTrendlineArray(const double &highs[], const double &lows[], const int depth,
                            const int max_lookback, const bool want_support,
                            const double middle_tolerance_atr, const double current_atr,
                            STrendlineResult &result)
  {
   result.found = false;
   result.current_value = 0.0;
   result.is_support = want_support;

   if(current_atr <= 0.0)
      return false;

   int p1, p2, p3;
   double v1, v2, v3;

   if(want_support)
     {
      if(!SE_FindNearestConfirmedSwingLowArray(lows, 0, depth, max_lookback, p1))
         return false;
      if(!SE_FindNearestConfirmedSwingLowArray(lows, p1 + 1, depth, max_lookback, p2))
         return false;
      if(!SE_FindNearestConfirmedSwingLowArray(lows, p2 + 1, depth, max_lookback, p3))
         return false;
      v1 = lows[p1]; v2 = lows[p2]; v3 = lows[p3];
     }
   else
     {
      if(!SE_FindNearestConfirmedSwingHighArray(highs, 0, depth, max_lookback, p1))
         return false;
      if(!SE_FindNearestConfirmedSwingHighArray(highs, p1 + 1, depth, max_lookback, p2))
         return false;
      if(!SE_FindNearestConfirmedSwingHighArray(highs, p2 + 1, depth, max_lookback, p3))
         return false;
      v1 = highs[p1]; v2 = highs[p2]; v3 = highs[p3];
     }

   // Validate: the middle anchor (p2, v2) must lie near the line through
   // the outer two anchors (p3 = oldest = x1, p1 = newest = x2).
   double expected_v2 = CPT_LinearInterpolate(p3, v3, p1, v1, p2);
   if(MathAbs(v2 - expected_v2) > current_atr * middle_tolerance_atr)
      return false;

   double projected = CPT_LinearInterpolate(p3, v3, p1, v1, 0);

   result.found = true;
   result.anchor1_index = p1; result.anchor1_price = v1;
   result.anchor2_index = p2; result.anchor2_price = v2;
   result.anchor3_index = p3; result.anchor3_price = v3;
   result.current_value = projected;
   return true;
  }

//+------------------------------------------------------------------+
//| Setup 1: trendline pullback.                                       |
//+------------------------------------------------------------------+
bool TFS_EvaluateTrendlinePullbackArray(const double &opens[], const double &highs[],
                                         const double &lows[], const double &closes[],
                                         const double &atr_values[], const ENUM_MARKET_REGIME regime,
                                         const STFConfig &cfg, STFStrategySignal &signal)
  {
   TFS_InitSignal(signal);
   if(regime != REGIME_TRENDING_UP && regime != REGIME_TRENDING_DOWN)
      return false;

   int n = ArraySize(closes);
   if(n < 1 || ArraySize(atr_values) < 1)
      return false;
   double current_atr = atr_values[0];
   if(current_atr <= 0.0)
      return false;

   bool want_bullish = (regime == REGIME_TRENDING_UP);

   STrendlineResult tl;
   if(!TF_FindTrendlineArray(highs, lows, cfg.depth, cfg.max_lookback, want_bullish,
                              cfg.middle_tolerance_atr, current_atr, tl))
      return false;

   double current_price = closes[0];
   double tol = current_atr * cfg.touch_tolerance_atr;
   if(MathAbs(current_price - tl.current_value) > tol)
      return false;

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

   double stop_price = want_bullish ? (tl.current_value - current_atr * cfg.stop_buffer_atr)
                                     : (tl.current_value + current_atr * cfg.stop_buffer_atr);
   double risk = MathAbs(current_price - stop_price);

   signal.found = true;
   signal.setup_type = TFS_TRENDLINE_PULLBACK;
   signal.direction = want_bullish ? TFSD_LONG : TFSD_SHORT;
   signal.entry_price = current_price;
   signal.stop_price = stop_price;
   signal.target_price = want_bullish ? (current_price + 2.0 * risk) : (current_price - 2.0 * risk);
   signal.candlestick_pattern = pattern_name;
   return true;
  }

//+------------------------------------------------------------------+
//| Setup 2: momentum continuation. Eligible in TRENDING and              |
//| VOLATILITY_EXPANSION regimes.                                         |
//+------------------------------------------------------------------+
bool TFS_EvaluateMomentumContinuationArray(const double &opens[], const double &highs[],
                                            const double &lows[], const double &closes[],
                                            const double &atr_values[],
                                            const ENUM_MARKET_REGIME regime, const STFConfig &cfg,
                                            STFStrategySignal &signal)
  {
   TFS_InitSignal(signal);
   bool eligible = (regime == REGIME_TRENDING_UP || regime == REGIME_TRENDING_DOWN ||
                    regime == REGIME_VOLATILITY_EXPANSION_UP ||
                    regime == REGIME_VOLATILITY_EXPANSION_DOWN);
   if(!eligible)
      return false;

   bool want_bullish = (regime == REGIME_TRENDING_UP || regime == REGIME_VOLATILITY_EXPANSION_UP);

   int n = ArraySize(closes);
   if(n < 1 || ArraySize(atr_values) < 1)
      return false;
   double current_atr = atr_values[0];
   if(current_atr <= 0.0)
      return false;

   bool displacement_found = false;
   int displacement_index = -1;
   for(int k = 1; k <= cfg.momentum_lookback_bars && k < n; k++)
     {
      if(CP_IsMarubozuArray(opens, highs, lows, closes, atr_values, k, 0.90,
                             cfg.displacement_atr_multiple))
        {
         bool disp_bullish = closes[k] > opens[k];
         if(disp_bullish == want_bullish)
           {
            displacement_found = true;
            displacement_index = k;
            break;
           }
        }
     }
   if(!displacement_found)
      return false;

   double extreme = want_bullish ? highs[displacement_index] : lows[displacement_index];
   double current_price = closes[0];
   double pullback = want_bullish ? (extreme - current_price) : (current_price - extreme);
   if(pullback > current_atr * cfg.max_pullback_atr)
      return false; // retraced too far — not a shallow pullback

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

   double stop_price = want_bullish ? (current_price - current_atr * cfg.momentum_stop_atr)
                                     : (current_price + current_atr * cfg.momentum_stop_atr);
   double risk = MathAbs(current_price - stop_price);

   signal.found = true;
   signal.setup_type = TFS_MOMENTUM_CONTINUATION;
   signal.direction = want_bullish ? TFSD_LONG : TFSD_SHORT;
   signal.entry_price = current_price;
   signal.stop_price = stop_price;
   signal.target_price = want_bullish ? (current_price + 2.0 * risk) : (current_price - 2.0 * risk);
   signal.candlestick_pattern = pattern_name;
   return true;
  }

//+------------------------------------------------------------------+
//| Dispatcher.                                                        |
//+------------------------------------------------------------------+
bool TFS_EvaluateArray(const double &opens[], const double &highs[], const double &lows[],
                        const double &closes[], const double &atr_values[],
                        const ENUM_MARKET_REGIME regime, const STFConfig &cfg,
                        STFStrategySignal &signal)
  {
   if(TFS_EvaluateTrendlinePullbackArray(opens, highs, lows, closes, atr_values, regime, cfg, signal))
      return true;
   if(TFS_EvaluateMomentumContinuationArray(opens, highs, lows, closes, atr_values, regime, cfg,
                                             signal))
      return true;

   TFS_InitSignal(signal);
   return false;
  }

//+------------------------------------------------------------------+
//| CMARKETDATA-INTEGRATED WRAPPER                                     |
//+------------------------------------------------------------------+
bool TFS_EvaluateLive(CMarketData &md, const int atr_percentile_window, const int efficiency_window,
                       const int ema_period, const int ema_slope_bars, const int adx_period,
                       const double trend_threshold, const double expansion_threshold,
                       const double compression_threshold, const double min_efficiency,
                       const double trend_slope_atr_divisor, const STFConfig &cfg,
                       STFStrategySignal &signal)
  {
   TFS_InitSignal(signal);

   SRegimeRead regime_read;
   if(!MRE_ClassifyLive(md, atr_percentile_window, efficiency_window, ema_period, ema_slope_bars,
                         adx_period, cfg.depth, cfg.max_lookback, trend_threshold, expansion_threshold,
                         compression_threshold, min_efficiency, trend_slope_atr_divisor, regime_read))
      return false;

   int window = cfg.depth + 2 * cfg.max_lookback + cfg.depth + 1;
   window = MathMax(window, cfg.momentum_lookback_bars + 2);
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

   return TFS_EvaluateArray(opens, highs, lows, closes, atr_values, regime_read.regime, cfg, signal);
  }
