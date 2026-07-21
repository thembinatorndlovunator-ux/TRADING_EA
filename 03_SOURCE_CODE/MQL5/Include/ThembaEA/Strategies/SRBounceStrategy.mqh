//+------------------------------------------------------------------+
//| SRBounceStrategy.mqh                                              |
//| Themba Adaptive Intraday Engine — Strategies                       |
//|                                                                    |
//| The first of six strategy families, per                            |
//| STRATEGY_SPEC_SR_BOUNCE.md and                                      |
//| TASK-002_PHASE2_SPECIFICATION.md section 3. Composes, and does not   |
//| duplicate, four already-built modules: MarketRegimeEngine.mqh         |
//| (RANGING gate), MarketStructure.mqh (range_high/range_low),           |
//| SupportResistance.mqh (zone qualification), and                        |
//| CandlestickPatternEngine.mqh (directional confirmation). This module   |
//| produces a raw candidate SIGNAL only — scoring, risk-multiplier         |
//| composition, position sizing, and duplicate-signal suppression are      |
//| explicitly later (Phase 6 StrategyRouter / RiskManager) concerns,        |
//| per this strategy's own specification.                                   |
//|                                                                    |
//| Deliberately excludes three-bar-reversal confirmation — see the       |
//| specification's "Entry Trigger" section for why (an ambiguous          |
//| direction-agnostic return value from                                    |
//| CP_IsThreeBarReversalArray could confirm the wrong direction at a       |
//| zone if used naively).                                                  |
//+------------------------------------------------------------------+
#property strict

#include "../Market/MarketRegimeEngine.mqh"
#include "../Structure/SupportResistance.mqh"
#include "../Patterns/CandlestickPatternEngine.mqh"

enum ENUM_SR_BOUNCE_DIRECTION
  {
   SRB_NONE,
   SRB_LONG,
   SRB_SHORT
  };

struct SSRBounceSignal
  {
   bool                     found;
   ENUM_SR_BOUNCE_DIRECTION direction;
   double                   entry_price;   // current close, a reference — actual fill is a later concern
   double                   zone_price;
   int                      zone_touch_count;
   double                   stop_price;
   double                   target_price;
   string                   candlestick_pattern;
  };

//+------------------------------------------------------------------+
//| Evaluates one bar for a SR-bounce candidate, per                    |
//| STRATEGY_SPEC_SR_BOUNCE.md. 'regime' and 'structure' are supplied     |
//| by the caller (already computed via MarketRegimeEngine/               |
//| MarketStructure) — this function performs no regime/structure          |
//| computation of its own, only composition.                              |
//+------------------------------------------------------------------+
bool SRB_EvaluateArray(const double &opens[], const double &highs[], const double &lows[],
                        const double &closes[], const double &atr_values[], const int depth,
                        const int max_lookback, const ENUM_MARKET_REGIME regime,
                        const SMarketStructureState &structure, const double sr_tolerance_atr,
                        const int sr_min_touches, const double stop_buffer_atr,
                        const int trend_lookback, SSRBounceSignal &signal)
  {
   signal.found = false;
   signal.direction = SRB_NONE;
   signal.entry_price = 0.0;
   signal.zone_price = 0.0;
   signal.zone_touch_count = 0;
   signal.stop_price = 0.0;
   signal.target_price = 0.0;
   signal.candlestick_pattern = "";

   if(regime != REGIME_RANGING)
      return false;
   if(!structure.valid)
      return false;

   int n = ArraySize(closes);
   if(n < 1 || ArraySize(atr_values) < 1)
      return false;

   double atr = atr_values[0];
   if(atr <= 0.0)
      return false;

   double current_close = closes[0];
   double tolerance = atr * sr_tolerance_atr;

   bool near_support = MathAbs(current_close - structure.range_low) <= tolerance;
   bool near_resistance = MathAbs(current_close - structure.range_high) <= tolerance;

   if(near_support)
     {
      int touch_count;
      if(SR_IsSupportZoneArray(lows, depth, max_lookback, structure.range_low, tolerance,
                                sr_min_touches, touch_count))
        {
         string pattern_name = "";
         bool confirmed = false;

         if(CP_IsBullishPinBarArray(opens, highs, lows, closes, 0, trend_lookback))
           {
            confirmed = true;
            pattern_name = "bullish_pin_bar";
           }
         else if(CP_IsBullishEngulfingArray(opens, highs, lows, closes, 0))
           {
            confirmed = true;
            pattern_name = "bullish_engulfing";
           }
         else if(CP_IsTweezerBottomArray(opens, highs, lows, closes, atr_values, 0))
           {
            confirmed = true;
            pattern_name = "tweezer_bottom";
           }

         if(confirmed)
           {
            signal.found = true;
            signal.direction = SRB_LONG;
            signal.entry_price = current_close;
            signal.zone_price = structure.range_low;
            signal.zone_touch_count = touch_count;
            signal.stop_price = structure.range_low - atr * stop_buffer_atr;
            signal.target_price = structure.range_high;
            signal.candlestick_pattern = pattern_name;
            return true;
           }
        }
     }

   if(near_resistance)
     {
      int touch_count;
      if(SR_IsResistanceZoneArray(highs, depth, max_lookback, structure.range_high, tolerance,
                                   sr_min_touches, touch_count))
        {
         string pattern_name = "";
         bool confirmed = false;

         if(CP_IsBearishPinBarArray(opens, highs, lows, closes, 0, trend_lookback))
           {
            confirmed = true;
            pattern_name = "bearish_pin_bar";
           }
         else if(CP_IsBearishEngulfingArray(opens, highs, lows, closes, 0))
           {
            confirmed = true;
            pattern_name = "bearish_engulfing";
           }
         else if(CP_IsTweezerTopArray(opens, highs, lows, closes, atr_values, 0))
           {
            confirmed = true;
            pattern_name = "tweezer_top";
           }

         if(confirmed)
           {
            signal.found = true;
            signal.direction = SRB_SHORT;
            signal.entry_price = current_close;
            signal.zone_price = structure.range_high;
            signal.zone_touch_count = touch_count;
            signal.stop_price = structure.range_high + atr * stop_buffer_atr;
            signal.target_price = structure.range_low;
            signal.candlestick_pattern = pattern_name;
            return true;
           }
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//| CMARKETDATA-INTEGRATED WRAPPER                                     |
//+------------------------------------------------------------------+
bool SRB_EvaluateLive(CMarketData &md, const int depth, const int max_lookback,
                       const int atr_percentile_window, const int efficiency_window,
                       const int ema_period, const int ema_slope_bars, const int adx_period,
                       const double trend_threshold, const double expansion_threshold,
                       const double compression_threshold, const double min_efficiency,
                       const double trend_slope_atr_divisor, const double sr_tolerance_atr,
                       const int sr_min_touches, const double stop_buffer_atr,
                       const int trend_lookback, SSRBounceSignal &signal)
  {
   signal.found = false;

   SRegimeRead regime_read;
   if(!MRE_ClassifyLive(md, atr_percentile_window, efficiency_window, ema_period, ema_slope_bars,
                         adx_period, depth, max_lookback, trend_threshold, expansion_threshold,
                         compression_threshold, min_efficiency, trend_slope_atr_divisor, regime_read))
      return false;

   int window = depth + 2 * max_lookback + depth + 1;
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
   if(!MS_ComputeStructureArray(highs, lows, closes, depth, max_lookback, structure))
      return false;

   return SRB_EvaluateArray(opens, highs, lows, closes, atr_values, depth, max_lookback,
                             regime_read.regime, structure, sr_tolerance_atr, sr_min_touches,
                             stop_buffer_atr, trend_lookback, signal);
  }
