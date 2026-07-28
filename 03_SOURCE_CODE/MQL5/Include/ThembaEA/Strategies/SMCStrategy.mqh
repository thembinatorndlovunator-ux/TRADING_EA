//+------------------------------------------------------------------+
//| SMCStrategy.mqh                                                   |
//| Themba Adaptive Intraday Engine — Strategies                       |
//|                                                                    |
//| The second of six strategy families, per STRATEGY_SPEC_SMC_ICT.md   |
//| and TASK-002_PHASE2_SPECIFICATION.md section 3. Unlike                |
//| SRBounceStrategy.mqh (one regime, one setup), this strategy is        |
//| eligible across three regimes with three distinct setup shapes,        |
//| each its own detection function composing ICTSMCGeometry.mqh           |
//| (TASK-015) and CandlestickPatternEngine.mqh (TASK-014/017), never      |
//| recomputing either.                                                    |
//|                                                                    |
//| **Target formula is a stated simplification** (2x zone height,         |
//| projected from entry) — section 7's full target selector does not      |
//| exist as a built module yet; see the specification's own "Target        |
//| Formula" section for why this is explicitly provisional.                |
//|                                                                    |
//| Deliberately excludes three-bar-reversal confirmation, for the same     |
//| reason as SRBounceStrategy.mqh.                                          |
//+------------------------------------------------------------------+
#property strict

#include "../Market/MarketRegimeEngine.mqh"
#include "../Structure/ICTSMCGeometry.mqh"
#include "../Patterns/CandlestickPatternEngine.mqh"

enum ENUM_SMC_SETUP_TYPE
  {
   SMC_SETUP_NONE,
   SMC_SETUP_OB_RETEST,
   SMC_SETUP_SWEEP_REVERSAL,
   SMC_SETUP_FVG_RETURN
  };

enum ENUM_SMC_DIRECTION
  {
   SMCD_NONE,
   SMCD_LONG,
   SMCD_SHORT
  };

struct SSMCSignal
  {
   bool                 found;
   ENUM_SMC_SETUP_TYPE  setup_type;
   ENUM_SMC_DIRECTION   direction;
   double               entry_price;
   double               zone_high;
   double               zone_low;
   double               stop_price;
   double               target_price;
   string               candlestick_pattern;
  };

struct SSMCConfig
  {
   int    depth;
   int    max_lookback;
   double displacement_atr_multiple;
   double retest_tolerance_atr;
   int    max_retest_bars;
   int    sweep_lookback;
   int    shift_lookback;
   int    fvg_scan_bars;
   int    trend_lookback;
  };

void SMC_InitSignal(SSMCSignal &signal)
  {
   signal.found = false;
   signal.setup_type = SMC_SETUP_NONE;
   signal.direction = SMCD_NONE;
   signal.entry_price = 0.0;
   signal.zone_high = 0.0;
   signal.zone_low = 0.0;
   signal.stop_price = 0.0;
   signal.target_price = 0.0;
   signal.candlestick_pattern = "";
  }

//+------------------------------------------------------------------+
//| Setup 1: order-block retest after displacement, in a trending        |
//| regime. Scans the most recent 'max_retest_bars' for a displacement    |
//| producing an order block matching the trend's own direction, not      |
//| invalidated, with current price at/near the zone.                     |
//+------------------------------------------------------------------+
bool SMC_EvaluateOrderBlockRetestArray(const double &opens[], const double &highs[],
                                        const double &lows[], const double &closes[],
                                        const double &atr_values[], const ENUM_MARKET_REGIME regime,
                                        const SSMCConfig &cfg, SSMCSignal &signal)
  {
   SMC_InitSignal(signal);
   if(regime != REGIME_TRENDING_UP && regime != REGIME_TRENDING_DOWN)
      return false;

   int n = ArraySize(closes);
   if(n < 1 || ArraySize(atr_values) < 1)
      return false;
   double current_atr = atr_values[0];
   if(current_atr <= 0.0)
      return false;

   bool want_bullish = (regime == REGIME_TRENDING_UP);
   double current_price = closes[0];

   for(int k = 0; k <= cfg.max_retest_bars && k + 1 < n; k++)
     {
      ENUM_OB_TYPE ob_type;
      double zh, zl;
      int ob_index;
      if(!ICT_DetectOrderBlockArray(opens, highs, lows, closes, atr_values, k,
                                     cfg.displacement_atr_multiple, ob_type, zh, zl, ob_index))
         continue;

      bool matches = want_bullish ? (ob_type == OB_BULLISH) : (ob_type == OB_BEARISH);
      if(!matches)
         continue;
      if(ICT_IsOrderBlockInvalidated(ob_type, zh, zl, current_price))
         continue;

      double tol = current_atr * cfg.retest_tolerance_atr;
      bool near_zone = (current_price >= zl - tol && current_price <= zh + tol);
      if(!near_zone)
         continue;

      string pattern_name = "";
      bool confirmed = false;
      if(want_bullish)
        {
         if(CP_IsBullishPinBarArray(opens, highs, lows, closes, 0, cfg.trend_lookback))
           { confirmed = true; pattern_name = "bullish_pin_bar"; }
         else if(CP_IsBullishEngulfingArray(opens, highs, lows, closes, 0))
           { confirmed = true; pattern_name = "bullish_engulfing"; }
        }
      else
        {
         if(CP_IsBearishPinBarArray(opens, highs, lows, closes, 0, cfg.trend_lookback))
           { confirmed = true; pattern_name = "bearish_pin_bar"; }
         else if(CP_IsBearishEngulfingArray(opens, highs, lows, closes, 0))
           { confirmed = true; pattern_name = "bearish_engulfing"; }
        }

      if(!confirmed)
         continue;

      double zone_height = zh - zl;
      signal.found = true;
      signal.setup_type = SMC_SETUP_OB_RETEST;
      signal.direction = want_bullish ? SMCD_LONG : SMCD_SHORT;
      signal.entry_price = current_price;
      signal.zone_high = zh;
      signal.zone_low = zl;
      signal.stop_price = want_bullish ? (zl - current_atr * 0.1) : (zh + current_atr * 0.1);
      signal.target_price = want_bullish ? (current_price + 2.0 * zone_height)
                                          : (current_price - 2.0 * zone_height);
      signal.candlestick_pattern = pattern_name;
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Setup 2: liquidity sweep reversal, in a ranging regime. Requires a   |
//| FRESH confirmed sweep (confirmation within the most recent 2 bars)    |
//| — an older sweep is stale and not tradeable as a fresh reversal.      |
//+------------------------------------------------------------------+
bool SMC_EvaluateSweepReversalArray(const double &opens[], const double &highs[], const double &lows[],
                                     const double &closes[], const double &atr_values[],
                                     const ENUM_MARKET_REGIME regime, const SSMCConfig &cfg,
                                     SSMCSignal &signal)
  {
   SMC_InitSignal(signal);
   if(regime != REGIME_RANGING)
      return false;

   int n = ArraySize(closes);
   if(n < 1 || ArraySize(atr_values) < 1)
      return false;
   double current_atr = atr_values[0];
   if(current_atr <= 0.0)
      return false;

   SSweepResult sweep;
   if(!ICT_DetectSweepArray(highs, lows, closes, cfg.sweep_lookback, cfg.shift_lookback, sweep))
      return false;
   if(sweep.confirmation_bar_index < 0 || sweep.confirmation_bar_index > 1)
      return false; // stale — not a fresh reversal

   bool want_bullish = sweep.is_bullish;
   string pattern_name = "";
   bool confirmed = false;
   if(want_bullish)
     {
      if(CP_IsBullishPinBarArray(opens, highs, lows, closes, 0, cfg.trend_lookback))
        { confirmed = true; pattern_name = "bullish_pin_bar"; }
      else if(CP_IsBullishEngulfingArray(opens, highs, lows, closes, 0))
        { confirmed = true; pattern_name = "bullish_engulfing"; }
      else if(CP_IsTweezerBottomArray(opens, highs, lows, closes, atr_values, 0))
        { confirmed = true; pattern_name = "tweezer_bottom"; }
     }
   else
     {
      if(CP_IsBearishPinBarArray(opens, highs, lows, closes, 0, cfg.trend_lookback))
        { confirmed = true; pattern_name = "bearish_pin_bar"; }
      else if(CP_IsBearishEngulfingArray(opens, highs, lows, closes, 0))
        { confirmed = true; pattern_name = "bearish_engulfing"; }
      else if(CP_IsTweezerTopArray(opens, highs, lows, closes, atr_values, 0))
        { confirmed = true; pattern_name = "tweezer_top"; }
     }

   if(!confirmed)
      return false;

   double sweep_bar_extreme_high = highs[sweep.sweep_bar_index];
   double sweep_bar_extreme_low = lows[sweep.sweep_bar_index];
   double zone_height = MathMax(current_atr * 0.5, MathAbs(sweep_bar_extreme_high - sweep_bar_extreme_low));

   signal.found = true;
   signal.setup_type = SMC_SETUP_SWEEP_REVERSAL;
   signal.direction = want_bullish ? SMCD_LONG : SMCD_SHORT;
   signal.entry_price = closes[0];
   signal.zone_high = sweep_bar_extreme_high;
   signal.zone_low = sweep_bar_extreme_low;
   signal.stop_price = want_bullish ? (sweep_bar_extreme_low - current_atr * 0.1)
                                     : (sweep_bar_extreme_high + current_atr * 0.1);
   signal.target_price = want_bullish ? (signal.entry_price + 2.0 * zone_height)
                                       : (signal.entry_price - 2.0 * zone_height);
   signal.candlestick_pattern = pattern_name;
   return true;
  }

//+------------------------------------------------------------------+
//| Setup 3: FVG return, in a volatility-expansion regime. Scans the     |
//| most recent 'fvg_scan_bars' for a not-yet-invalidated FVG matching    |
//| the expansion's own direction, with current price inside the zone.    |
//+------------------------------------------------------------------+
bool SMC_EvaluateFVGReturnArray(const double &opens[], const double &highs[], const double &lows[],
                                 const double &closes[], const double &atr_values[],
                                 const ENUM_MARKET_REGIME regime, const SSMCConfig &cfg,
                                 SSMCSignal &signal)
  {
   SMC_InitSignal(signal);
   if(regime != REGIME_VOLATILITY_EXPANSION_UP && regime != REGIME_VOLATILITY_EXPANSION_DOWN)
      return false;

   int n = ArraySize(closes);
   if(n < 1 || ArraySize(atr_values) < 1)
      return false;
   double current_atr = atr_values[0];
   if(current_atr <= 0.0)
      return false;

   bool want_bullish = (regime == REGIME_VOLATILITY_EXPANSION_UP);
   double current_price = closes[0];

   for(int k = 0; k <= cfg.fvg_scan_bars && k + 2 < n; k++)
     {
      SFvgZone zone;
      if(!ICT_GetFvgZoneArray(highs, lows, k, zone))
         continue;

      bool matches = want_bullish ? (zone.type == FVG_BULLISH) : (zone.type == FVG_BEARISH);
      if(!matches)
         continue;
      if(ICT_IsFvgInvalidated(zone, current_price))
         continue;
      if(!ICT_IsPriceInFvg(zone, current_price))
         continue;

      string pattern_name = "";
      bool confirmed = false;
      if(want_bullish)
        {
         if(CP_IsBullishPinBarArray(opens, highs, lows, closes, 0, cfg.trend_lookback))
           { confirmed = true; pattern_name = "bullish_pin_bar"; }
         else if(CP_IsBullishEngulfingArray(opens, highs, lows, closes, 0))
           { confirmed = true; pattern_name = "bullish_engulfing"; }
        }
      else
        {
         if(CP_IsBearishPinBarArray(opens, highs, lows, closes, 0, cfg.trend_lookback))
           { confirmed = true; pattern_name = "bearish_pin_bar"; }
         else if(CP_IsBearishEngulfingArray(opens, highs, lows, closes, 0))
           { confirmed = true; pattern_name = "bearish_engulfing"; }
        }

      if(!confirmed)
         continue;

      double zone_height = zone.zone_high - zone.zone_low;
      signal.found = true;
      signal.setup_type = SMC_SETUP_FVG_RETURN;
      signal.direction = want_bullish ? SMCD_LONG : SMCD_SHORT;
      signal.entry_price = current_price;
      signal.zone_high = zone.zone_high;
      signal.zone_low = zone.zone_low;
      signal.stop_price = want_bullish ? (zone.zone_low - current_atr * 0.1)
                                        : (zone.zone_high + current_atr * 0.1);
      signal.target_price = want_bullish ? (current_price + 2.0 * zone_height)
                                          : (current_price - 2.0 * zone_height);
      signal.candlestick_pattern = pattern_name;
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Dispatcher: tries each setup in turn, returning the first found.     |
//| At most one of the three can apply per evaluation, since each is      |
//| gated by a mutually-exclusive regime.                                  |
//+------------------------------------------------------------------+
bool SMC_EvaluateArray(const double &opens[], const double &highs[], const double &lows[],
                        const double &closes[], const double &atr_values[],
                        const ENUM_MARKET_REGIME regime, const SSMCConfig &cfg, SSMCSignal &signal)
  {
   if(SMC_EvaluateOrderBlockRetestArray(opens, highs, lows, closes, atr_values, regime, cfg, signal))
      return true;
   if(SMC_EvaluateSweepReversalArray(opens, highs, lows, closes, atr_values, regime, cfg, signal))
      return true;
   if(SMC_EvaluateFVGReturnArray(opens, highs, lows, closes, atr_values, regime, cfg, signal))
      return true;

   SMC_InitSignal(signal);
   return false;
  }

//+------------------------------------------------------------------+
//| CMARKETDATA-INTEGRATED WRAPPER                                     |
//+------------------------------------------------------------------+
bool SMC_EvaluateLive(CMarketData &md, const int atr_percentile_window, const int efficiency_window,
                       const int ema_period, const int ema_slope_bars, const int adx_period,
                       const double trend_threshold, const double expansion_threshold,
                       const double compression_threshold, const double min_efficiency,
                       const double trend_slope_atr_divisor, const SSMCConfig &cfg,
                       SSMCSignal &signal)
  {
   SMC_InitSignal(signal);

   SRegimeRead regime_read;
   if(!MRE_ClassifyLive(md, atr_percentile_window, efficiency_window, ema_period, ema_slope_bars,
                         adx_period, cfg.depth, cfg.max_lookback, trend_threshold, expansion_threshold,
                         compression_threshold, min_efficiency, trend_slope_atr_divisor, regime_read))
      return false;

   int window = cfg.depth + 2 * cfg.max_lookback + cfg.depth + 1;
   window = MathMax(window, cfg.max_retest_bars + cfg.depth + 2);
   window = MathMax(window, cfg.fvg_scan_bars + 3);
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

   return SMC_EvaluateArray(opens, highs, lows, closes, atr_values, regime_read.regime, cfg, signal);
  }
