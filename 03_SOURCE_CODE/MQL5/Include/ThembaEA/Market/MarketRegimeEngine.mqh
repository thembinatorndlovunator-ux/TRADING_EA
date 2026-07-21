//+------------------------------------------------------------------+
//| MarketRegimeEngine.mqh                                            |
//| Themba Adaptive Intraday Engine — Market                          |
//|                                                                    |
//| The nine-state regime classifier, per                              |
//| TASK-002_PHASE2_SPECIFICATION.md section 2 — including the           |
//| classification-margin confidence formula that replaced round-2's     |
//| mathematically self-defeating one (min(T,1-2|0.5-E|), which was       |
//| exactly zero at both expansion extremes; the corrected formula        |
//| measures each selected state's own margin above its own threshold,    |
//| verified by hand at both extremes in TASK-002's own Test plan).       |
//|                                                                    |
//| Trend-direction agreement reuses MarketStructure.mqh's bias output    |
//| directly (TASK-012) rather than a third, independent swing-sequence   |
//| analyzer — a stated interpretation choice for section 2's              |
//| "swing_agreement" concept, since MarketStructure's higher-high/         |
//| higher-low bias comparison already answers exactly the question         |
//| swing_agreement asks.                                                   |
//|                                                                    |
//| Split into an array/scalar-based core (pure, hand-testable) and a     |
//| thin CMarketData-integrated wrapper, matching every other Structure/   |
//| Market module in this project. Hysteresis is a SEPARATE, explicitly   |
//| stateful concern (SRegimeHysteresisState) — the classifier itself is   |
//| stateless and returns only the raw, per-bar read.                      |
//|                                                                    |
//| Gating regimes: UNTRADEABLE_SPREAD_OR_LIQUIDITY is fully implemented   |
//| here; NEWS_BLACKOUT is accepted as a caller-supplied boolean           |
//| (section 10's news system is Phase 7 work, not yet built) — a          |
//| stated, explicit scope boundary, not an oversight.                     |
//+------------------------------------------------------------------+
#property strict

#include "../Structure/MarketStructure.mqh"

enum ENUM_MARKET_REGIME
  {
   REGIME_TRENDING_UP,
   REGIME_TRENDING_DOWN,
   REGIME_RANGING,
   REGIME_VOLATILITY_EXPANSION_UP,
   REGIME_VOLATILITY_EXPANSION_DOWN,
   REGIME_COMPRESSION,
   REGIME_TRANSITION_OR_UNCERTAIN,
   REGIME_NEWS_BLACKOUT,
   REGIME_UNTRADEABLE_SPREAD_OR_LIQUIDITY
  };

struct SRegimeRead
  {
   bool                valid;                   // false on data/indicator failure
   ENUM_MARKET_REGIME  regime;
   double              confidence;               // [0,1]
   bool                low_confidence_override;   // confidence < 0.5, per section 2
   double              T;
   double              T_final;
   double              E;
   double              ER;
  };

double MRE_Clamp01(const double v)
  {
   return MathMax(0.0, MathMin(1.0, v));
  }

//+------------------------------------------------------------------+
//| Threshold bound clampers, per section 2 / Data Conventions — apply    |
//| once at OnInit, not per tick.                                         |
//+------------------------------------------------------------------+
double MRE_ClampTrendThreshold(const double v)       { return MathMax(0.3, MathMin(0.9, v)); }
double MRE_ClampExpansionThreshold(const double v)   { return MathMax(0.55, MathMin(0.95, v)); }
double MRE_ClampCompressionThreshold(const double v) { return MathMax(0.05, MathMin(0.45, v)); }
double MRE_ClampMinEfficiency(const double v)        { return MathMax(0.05, MathMin(0.6, v)); }
double MRE_ClampTrendSlopeAtrDivisor(const double v) { return MathMax(0.05, MathMin(5.0, v)); }

//+------------------------------------------------------------------+
//| Gating regime: UNTRADEABLE_SPREAD_OR_LIQUIDITY, per section 2.        |
//+------------------------------------------------------------------+
bool MRE_IsUntradeableSpreadOrLiquidity(const double current_spread, const double atr,
                                         const double max_spread_atr_multiple,
                                         const double avg_ticks_per_bar,
                                         const double min_liquidity_ticks_per_bar)
  {
   if(atr > 0.0 && current_spread > atr * max_spread_atr_multiple)
      return true;
   if(min_liquidity_ticks_per_bar > 0.0 && avg_ticks_per_bar < min_liquidity_ticks_per_bar)
      return true;
   return false;
  }

//+------------------------------------------------------------------+
//| ARRAY/SCALAR-BASED CORE                                            |
//|                                                                    |
//| 'atr_percentile_values' is the trailing ATR window used for E        |
//| (index 0 = current ATR, indices 1..N-1 = comparison history — same    |
//| average-rank percentile convention as                                 |
//| CandlestickPatternEngine.mqh's CP_SizePercentileArray). 'current_atr' |
//| is atr_percentile_values[0], passed separately since it is also        |
//| used as T's slope divisor. 'ema_now'/'ema_prior' are the EMA value      |
//| at logical index 0 and at logical index 'ema_slope_bars'                |
//| respectively — only these two points are needed, not a full EMA         |
//| series. 'adx_now' is ADX at logical index 0.                             |
//+------------------------------------------------------------------+
SRegimeRead MRE_ClassifyArray(const double &closes[], const double &highs[], const double &lows[],
                               const double &atr_percentile_values[], const double current_atr,
                               const double ema_now, const double ema_prior, const double adx_now,
                               const int efficiency_window, const int swing_depth,
                               const int swing_lookback_max, const double trend_threshold,
                               const double expansion_threshold, const double compression_threshold,
                               const double min_efficiency, const double trend_slope_atr_divisor)
  {
   SRegimeRead r;
   r.valid = false;
   r.regime = REGIME_TRANSITION_OR_UNCERTAIN;
   r.confidence = 0.0;
   r.low_confidence_override = true;
   r.T = 0.0; r.T_final = 0.0; r.E = 0.0; r.ER = 0.0;

   int n = ArraySize(closes);
   if(efficiency_window <= 0 || efficiency_window >= n)
      return r;

   //--- Efficiency ratio ---------------------------------------------------
   double num = MathAbs(closes[0] - closes[efficiency_window]);
   double den = 0.0;
   for(int i = 1; i <= efficiency_window; i++)
      den += MathAbs(closes[i] - closes[i - 1]);

   double ER;
   bool er_fails_efficiency;
   if(den == 0.0)
     {
      ER = 0.0;
      er_fails_efficiency = true;
     }
   else
     {
      ER = num / den;
      er_fails_efficiency = (ER < min_efficiency);
     }
   r.ER = ER;

   //--- Expansion/compression evidence E (ATR percentile) ------------------
   int atr_n = ArraySize(atr_percentile_values);
   if(atr_n < 2 || current_atr <= 0.0)
      return r;

   int total = atr_n - 1;
   double less_count = 0.0;
   for(int i = 1; i < atr_n; i++)
     {
      if(atr_percentile_values[i] < current_atr) less_count += 1.0;
      else if(atr_percentile_values[i] == current_atr) less_count += 0.5;
     }
   double E = less_count / (double)total;
   r.E = E;

   //--- Trend strength T -----------------------------------------------------
   double ema_diff = ema_now - ema_prior;
   double ema_slope_norm = MRE_Clamp01(MathAbs(ema_diff) / (current_atr * trend_slope_atr_divisor));

   SMarketStructureState ms;
   bool ms_ok = MS_ComputeStructureArray(highs, lows, closes, swing_depth, swing_lookback_max, ms);

   double swing_agreement = 0.0;
   bool direction_agree = false;
   bool overall_up = ema_diff > 0.0;
   if(ms_ok && ms.valid)
     {
      if(ms.bias == STRUCTURE_BIAS_BULLISH)
        {
         swing_agreement = overall_up ? 1.0 : 0.0;
         direction_agree = overall_up;
        }
      else if(ms.bias == STRUCTURE_BIAS_BEARISH)
        {
         swing_agreement = (!overall_up) ? 1.0 : 0.0;
         direction_agree = !overall_up;
        }
     }

   double T = MRE_Clamp01(0.5 * swing_agreement + 0.5 * ema_slope_norm);
   r.T = T;

   //--- T_final via ADX --------------------------------------------------------
   double adx_multiplier = MRE_Clamp01(0.5 + adx_now / 100.0);
   double T_final = T * adx_multiplier;
   r.T_final = T_final;

   r.valid = true;

   //--- State selection, strict priority, no fallthrough ------------------------
   ENUM_MARKET_REGIME regime;
   double confidence;

   if(er_fails_efficiency)
     {
      regime = REGIME_RANGING;
      confidence = MRE_Clamp01(1.0 - T_final / trend_threshold);
     }
   else if(E > expansion_threshold)
     {
      if(direction_agree)
        {
         regime = overall_up ? REGIME_VOLATILITY_EXPANSION_UP : REGIME_VOLATILITY_EXPANSION_DOWN;
         confidence = MRE_Clamp01((E - expansion_threshold) / (1.0 - expansion_threshold));
        }
      else
        {
         regime = REGIME_TRANSITION_OR_UNCERTAIN;
         confidence = 0.0;
        }
     }
   else if(T_final >= trend_threshold && direction_agree)
     {
      regime = overall_up ? REGIME_TRENDING_UP : REGIME_TRENDING_DOWN;
      confidence = MRE_Clamp01((T_final - trend_threshold) / (1.0 - trend_threshold));
     }
   else if(E < compression_threshold)
     {
      regime = REGIME_COMPRESSION;
      confidence = MRE_Clamp01((compression_threshold - E) / compression_threshold);
     }
   else
     {
      regime = REGIME_RANGING;
      confidence = MRE_Clamp01(1.0 - T_final / trend_threshold);
     }

   r.regime = regime;
   r.confidence = confidence;
   r.low_confidence_override = (confidence < 0.5);
   return r;
  }

//+------------------------------------------------------------------+
//| HYSTERESIS (stateful — caller owns and persists 'state' across        |
//| calls; the classifier above is stateless).                            |
//+------------------------------------------------------------------+
struct SRegimeHysteresisState
  {
   bool                has_confirmed;
   ENUM_MARKET_REGIME  confirmed_regime;
   ENUM_MARKET_REGIME  pending_regime;
   int                 pending_count;
  };

void MRE_InitHysteresisState(SRegimeHysteresisState &state)
  {
   state.has_confirmed = false;
   state.confirmed_regime = REGIME_TRANSITION_OR_UNCERTAIN;
   state.pending_regime = REGIME_TRANSITION_OR_UNCERTAIN;
   state.pending_count = 0;
  }

//+------------------------------------------------------------------+
//| Returns the EFFECTIVE regime after applying 'required_bars'          |
//| (default 2) consecutive-read confirmation, or bypassing it              |
//| immediately when 'bypass_hysteresis' is true (gating regimes and        |
//| indicator/data failures, per section 2). Before a first confirmation     |
//| exists, an unconfirmed read reports TRANSITION_OR_UNCERTAIN rather        |
//| than a half-confirmed guess.                                              |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME MRE_ApplyHysteresis(SRegimeHysteresisState &state,
                                        const ENUM_MARKET_REGIME raw_regime,
                                        const bool bypass_hysteresis,
                                        const int required_bars = 2)
  {
   if(bypass_hysteresis)
     {
      state.confirmed_regime = raw_regime;
      state.has_confirmed = true;
      state.pending_regime = raw_regime;
      state.pending_count = required_bars;
      return raw_regime;
     }

   if(state.pending_regime != raw_regime)
     {
      state.pending_regime = raw_regime;
      state.pending_count = 1;
     }
   else
      state.pending_count++;

   if(state.pending_count >= required_bars)
     {
      state.confirmed_regime = raw_regime;
      state.has_confirmed = true;
     }

   return state.has_confirmed ? state.confirmed_regime : REGIME_TRANSITION_OR_UNCERTAIN;
  }

//+------------------------------------------------------------------+
//| CMARKETDATA-INTEGRATED WRAPPER                                     |
//+------------------------------------------------------------------+
string g_mre_ema_symbols[];
int    g_mre_ema_periods[];
int    g_mre_ema_handles[];

int MRE_GetOrCreateEmaHandle(const string symbol, const ENUM_TIMEFRAMES tf, const int period)
  {
   for(int i = 0; i < ArraySize(g_mre_ema_symbols); i++)
      if(g_mre_ema_symbols[i] == symbol && g_mre_ema_periods[i] == period)
         return g_mre_ema_handles[i];

   int handle = iMA(symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return INVALID_HANDLE;

   int n = ArraySize(g_mre_ema_symbols);
   ArrayResize(g_mre_ema_symbols, n + 1);
   ArrayResize(g_mre_ema_periods, n + 1);
   ArrayResize(g_mre_ema_handles, n + 1);
   g_mre_ema_symbols[n] = symbol;
   g_mre_ema_periods[n] = period;
   g_mre_ema_handles[n] = handle;
   return handle;
  }

string g_mre_adx_symbols[];
int    g_mre_adx_periods[];
int    g_mre_adx_handles[];

int MRE_GetOrCreateAdxHandle(const string symbol, const ENUM_TIMEFRAMES tf, const int period)
  {
   for(int i = 0; i < ArraySize(g_mre_adx_symbols); i++)
      if(g_mre_adx_symbols[i] == symbol && g_mre_adx_periods[i] == period)
         return g_mre_adx_handles[i];

   int handle = iADX(symbol, tf, period);
   if(handle == INVALID_HANDLE)
      return INVALID_HANDLE;

   int n = ArraySize(g_mre_adx_symbols);
   ArrayResize(g_mre_adx_symbols, n + 1);
   ArrayResize(g_mre_adx_periods, n + 1);
   ArrayResize(g_mre_adx_handles, n + 1);
   g_mre_adx_symbols[n] = symbol;
   g_mre_adx_periods[n] = period;
   g_mre_adx_handles[n] = handle;
   return handle;
  }

bool MRE_ClassifyLive(CMarketData &md, const int atr_percentile_window,
                       const int efficiency_window, const int ema_period,
                       const int ema_slope_bars, const int adx_period,
                       const int swing_depth, const int swing_lookback_max,
                       const double trend_threshold, const double expansion_threshold,
                       const double compression_threshold, const double min_efficiency,
                       const double trend_slope_atr_divisor, SRegimeRead &result)
  {
   result.valid = false;

   int window = MathMax(atr_percentile_window, efficiency_window + 1);
   window = MathMax(window, swing_depth * 2 + swing_lookback_max + 5);
   if(!md.HasBars(window))
      return false;

   double closes[], highs[], lows[];
   ArrayResize(closes, window);
   ArrayResize(highs, window);
   ArrayResize(lows, window);
   for(int i = 0; i < window; i++)
      if(!md.GetClose(i, closes[i]) || !md.GetHigh(i, highs[i]) || !md.GetLow(i, lows[i]))
         return false;

   double atr_values[];
   ArrayResize(atr_values, atr_percentile_window);
   for(int i = 0; i < atr_percentile_window; i++)
      if(!md.GetATR(i, atr_values[i], 14))
         return false;

   int ema_handle = MRE_GetOrCreateEmaHandle(md.Symbol(), md.Timeframe(), ema_period);
   if(ema_handle == INVALID_HANDLE)
      return false;
   double ema_buf[];
   if(CopyBuffer(ema_handle, 0, 1, ema_slope_bars + 1, ema_buf) != ema_slope_bars + 1)
      return false;
   // CopyBuffer's own series indexing here starts at MQL index 1 (the most
   // recently completed bar), matching this project's logical-index-0
   // convention directly; ema_buf[0] is logical index 0 and ema_buf is in
   // OLDEST-to-NEWEST order for CopyBuffer, so the slope-bars-ago value is
   // the LAST element, not ema_buf[ema_slope_bars].
   double ema_now = ema_buf[ArraySize(ema_buf) - 1];
   double ema_prior = ema_buf[0];

   int adx_handle = MRE_GetOrCreateAdxHandle(md.Symbol(), md.Timeframe(), adx_period);
   if(adx_handle == INVALID_HANDLE)
      return false;
   double adx_buf[];
   if(CopyBuffer(adx_handle, 0, 1, 1, adx_buf) != 1)
      return false;
   double adx_now = adx_buf[0];

   result = MRE_ClassifyArray(closes, highs, lows, atr_values, atr_values[0], ema_now, ema_prior,
                               adx_now, efficiency_window, swing_depth, swing_lookback_max,
                               trend_threshold, expansion_threshold, compression_threshold,
                               min_efficiency, trend_slope_atr_divisor);
   return result.valid;
  }
