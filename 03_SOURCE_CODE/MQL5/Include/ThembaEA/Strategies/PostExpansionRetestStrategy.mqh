//+------------------------------------------------------------------+
//| PostExpansionRetestStrategy.mqh                                   |
//| Themba Adaptive Intraday Engine — Strategies                       |
//|                                                                    |
//| The fifth of six strategy families, per                             |
//| STRATEGY_SPEC_POST_EXPANSION_RETEST.md. Section 3 describes this     |
//| family only briefly, without a full formula (unlike the ported       |
//| sweep/shift or trendline mechanisms) — this module is this project's  |
//| own concrete formalization, stated explicitly, same discipline as     |
//| MarketStructure.mqh's bias/break definitions and                       |
//| ICTSMCGeometry.mqh's sweep algorithm.                                  |
//|                                                                    |
//| Deliberately distinct from SMCStrategy.mqh's FVG-return setup (which   |
//| also fires under VOLATILITY_EXPANSION): this strategy targets the      |
//| broken swing-structure level itself (MarketStructure.mqh's own          |
//| swing_high_1_price/swing_low_1_price), not a specific three-candle      |
//| gap. Reusing MarketStructure's already-computed state rather than        |
//| re-deriving a separate "what broke" concept.                              |
//|                                                                    |
//| The no-chase check here is DEFENSIVE and REDUNDANT — the canonical      |
//| gate belongs to the future StrategyRouter (section 3); stated             |
//| explicitly in the module header and specification, not presented as       |
//| the gate's permanent home.                                                 |
//+------------------------------------------------------------------+
#property strict

#include "../Market/MarketRegimeEngine.mqh"
#include "../Patterns/CandlestickPatternEngine.mqh"

enum ENUM_PER_DIRECTION
  {
   PERD_NONE,
   PERD_LONG,
   PERD_SHORT
  };

struct SPostExpansionRetestSignal
  {
   bool               found;
   ENUM_PER_DIRECTION direction;
   double             entry_price;
   double             reference_level;
   double             stop_price;
   double             target_price;
   string             candlestick_pattern;
  };

struct SPERConfig
  {
   int    depth;
   int    max_lookback;
   double min_expansion_atr;
   double retest_tolerance_atr;
   int    no_chase_bars;
   double stop_buffer_atr;
   int    candlestick_trend_lookback;
  };

void PER_InitSignal(SPostExpansionRetestSignal &signal)
  {
   signal.found = false;
   signal.direction = PERD_NONE;
   signal.entry_price = 0.0;
   signal.reference_level = 0.0;
   signal.stop_price = 0.0;
   signal.target_price = 0.0;
   signal.candlestick_pattern = "";
  }

//+------------------------------------------------------------------+
//| Evaluates one bar for a post-expansion-retest candidate, per          |
//| STRATEGY_SPEC_POST_EXPANSION_RETEST.md. 'regime' and 'structure' are   |
//| caller-supplied (already computed) — no regime/structure computation   |
//| happens here, only composition.                                        |
//+------------------------------------------------------------------+
bool PER_EvaluateArray(const double &opens[], const double &highs[], const double &lows[],
                        const double &closes[], const double &atr_values[],
                        const ENUM_MARKET_REGIME regime, const SMarketStructureState &structure,
                        const SPERConfig &cfg, SPostExpansionRetestSignal &signal)
  {
   PER_InitSignal(signal);

   bool eligible = (regime == REGIME_VOLATILITY_EXPANSION_UP ||
                    regime == REGIME_VOLATILITY_EXPANSION_DOWN);
   if(!eligible)
      return false;
   if(!structure.valid)
      return false;

   int n = ArraySize(closes);
   if(n < 1 || ArraySize(atr_values) < 1)
      return false;
   double current_atr = atr_values[0];
   if(current_atr <= 0.0)
      return false;

   bool want_bullish = (regime == REGIME_VOLATILITY_EXPANSION_UP);

   // Defensive, redundant no-chase check — see file header.
   if(structure.last_event_index >= 0 && structure.last_event_index < cfg.no_chase_bars)
      return false;

   double reference_level = want_bullish ? structure.swing_high_1_price : structure.swing_low_1_price;

   // Confirm a genuine expansion move occurred: some bar since the
   // triggering event traded beyond the reference level by at least
   // min_expansion_atr — distinguishes real displacement from noise.
   int event_idx = (structure.last_event_index >= 0) ? structure.last_event_index : cfg.max_lookback;
   int highs_n = ArraySize(highs);
   bool expansion_confirmed = false;
   for(int k = 0; k < event_idx && k < highs_n; k++)
     {
      if(want_bullish && highs[k] > reference_level + current_atr * cfg.min_expansion_atr)
        { expansion_confirmed = true; break; }
      if(!want_bullish && lows[k] < reference_level - current_atr * cfg.min_expansion_atr)
        { expansion_confirmed = true; break; }
     }
   if(!expansion_confirmed)
      return false;

   double current_price = closes[0];
   double tol = current_atr * cfg.retest_tolerance_atr;
   if(MathAbs(current_price - reference_level) > tol)
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

   double stop_price = want_bullish ? (reference_level - current_atr * cfg.stop_buffer_atr)
                                     : (reference_level + current_atr * cfg.stop_buffer_atr);
   double risk = MathAbs(current_price - stop_price);

   signal.found = true;
   signal.direction = want_bullish ? PERD_LONG : PERD_SHORT;
   signal.entry_price = current_price;
   signal.reference_level = reference_level;
   signal.stop_price = stop_price;
   signal.target_price = want_bullish ? (current_price + 2.0 * risk) : (current_price - 2.0 * risk);
   signal.candlestick_pattern = pattern_name;
   return true;
  }

//+------------------------------------------------------------------+
//| CMARKETDATA-INTEGRATED WRAPPER                                     |
//+------------------------------------------------------------------+
bool PER_EvaluateLive(CMarketData &md, const int atr_percentile_window, const int efficiency_window,
                       const int ema_period, const int ema_slope_bars, const int adx_period,
                       const double trend_threshold, const double expansion_threshold,
                       const double compression_threshold, const double min_efficiency,
                       const double trend_slope_atr_divisor, const SPERConfig &cfg,
                       SPostExpansionRetestSignal &signal)
  {
   PER_InitSignal(signal);

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
   if(!MS_ComputeStructureArray(highs, lows, closes, cfg.depth, cfg.max_lookback, structure))
      return false;

   return PER_EvaluateArray(opens, highs, lows, closes, atr_values, regime_read.regime, structure,
                             cfg, signal);
  }
