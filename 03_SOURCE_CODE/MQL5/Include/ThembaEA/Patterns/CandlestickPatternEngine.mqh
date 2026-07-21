//+------------------------------------------------------------------+
//| CandlestickPatternEngine.mqh                                      |
//| Themba Adaptive Intraday Engine — Patterns                         |
//|                                                                    |
//| Every candlestick pattern predicate from                            |
//| TASK-002_PHASE2_SPECIFICATION.md section 5, translated directly      |
//| into code: the same base measurements, the same named/bounded        |
//| threshold defaults, the same logical-index convention (index 0 =     |
//| the most recently completed bar; every array here is expected to     |
//| already be in that convention, matching CMarketData/SwingEngine).    |
//|                                                                    |
//| Every pattern function is array-based (pure, hand-testable) with a   |
//| thin CMarketData-integrated wrapper layer at the bottom of the file, |
//| matching the Structure/ modules' established pattern.                |
//|                                                                    |
//| Per section 5: no pattern here is a standalone trading signal — a    |
//| regime read and a location match (SupportResistance.mqh etc.) are    |
//| required by whichever strategy consumes a pattern; this module only  |
//| detects the pattern itself.                                          |
//|                                                                    |
//| Not yet cross-checked against the deeper reference material in       |
//| `EA Files/Candlestick Bible.pdf` (kept local-only per                |
//| SOURCE_LIBRARY.md's copyright rule) — a stated scope boundary, not   |
//| an oversight, same as MarketStructure.mqh's SMC cross-check gap.     |
//+------------------------------------------------------------------+
#property strict

#include "../Structure/SwingEngine.mqh"

#define CP_BODY_EPSILON 0.00001

//+------------------------------------------------------------------+
//| Base measurements                                                  |
//+------------------------------------------------------------------+
struct SCandleRatios
  {
   double body;
   double range;
   double upper_wick;
   double lower_wick;
   double body_ratio;
   double upper_wick_ratio;
   double lower_wick_ratio;
   double upper_wick_to_body;
   double lower_wick_to_body;
   bool   valid;
  };

SCandleRatios CP_MeasureRatiosArray(const double &opens[], const double &highs[],
                                     const double &lows[], const double &closes[],
                                     const int k)
  {
   SCandleRatios m;
   m.body = 0; m.range = 0; m.upper_wick = 0; m.lower_wick = 0;
   m.body_ratio = 0; m.upper_wick_ratio = 0; m.lower_wick_ratio = 0;
   m.upper_wick_to_body = 0; m.lower_wick_to_body = 0;
   m.valid = false;

   int n = ArraySize(closes);
   if(k < 0 || k >= n)
      return m;

   double o = opens[k], h = highs[k], l = lows[k], c = closes[k];
   double range = h - l;
   if(range <= 0.0)
      return m; // a zero-range bar never qualifies for any pattern, per section 5

   m.body = MathAbs(c - o);
   m.range = range;
   m.upper_wick = h - MathMax(o, c);
   m.lower_wick = MathMin(o, c) - l;
   m.body_ratio = m.body / range;
   m.upper_wick_ratio = m.upper_wick / range;
   m.lower_wick_ratio = m.lower_wick / range;
   m.upper_wick_to_body = m.upper_wick / MathMax(m.body, CP_BODY_EPSILON);
   m.lower_wick_to_body = m.lower_wick / MathMax(m.body, CP_BODY_EPSILON);
   m.valid = true;
   return m;
  }

//+------------------------------------------------------------------+
//| atr_size[k] = range[k]/ATR — 'atr_values' is a parallel array of     |
//| already-computed ATR values at each logical index (from                |
//| CMarketData::GetATR, or a fabricated array in tests).                 |
//+------------------------------------------------------------------+
double CP_AtrSizeArray(const double &highs[], const double &lows[],
                        const double &atr_values[], const int k)
  {
   int n = ArraySize(highs);
   if(k < 0 || k >= n)
      return 0.0;
   double range = highs[k] - lows[k];
   double a = atr_values[k];
   if(a <= 0.0)
      return 0.0;
   return range / a;
  }

//+------------------------------------------------------------------+
//| Relative-size percentile of range[k] against the trailing 'window'   |
//| candles (k+1..k+window), average-rank tie convention per the         |
//| specification's Data Conventions section.                            |
//+------------------------------------------------------------------+
double CP_SizePercentileArray(const double &highs[], const double &lows[],
                               const int k, const int window)
  {
   int n = ArraySize(highs);
   if(k < 0 || k >= n)
      return 0.0;

   int end = MathMin(k + window, n - 1);
   int total = end - k;
   if(total <= 0)
      return 1.0; // no comparison history — cannot be disproven as large

   double range_k = highs[k] - lows[k];
   double less_count = 0.0;
   for(int i = k + 1; i <= end; i++)
     {
      double r = highs[i] - lows[i];
      if(r < range_k) less_count += 1.0;
      else if(r == range_k) less_count += 0.5;
     }
   return less_count / (double)total;
  }

//+------------------------------------------------------------------+
//| Single-candle patterns                                             |
//+------------------------------------------------------------------+
bool CP_IsBullishPinBarArray(const double &opens[], const double &highs[],
                              const double &lows[], const double &closes[],
                              const int k, const int trend_lookback,
                              const double min_lower_wick_ratio = 0.60,
                              const double max_body_ratio = 0.30,
                              const double max_opposite_wick_ratio = 0.15)
  {
   int n = ArraySize(closes);
   if(k < 0 || k + trend_lookback >= n)
      return false;

   SCandleRatios m = CP_MeasureRatiosArray(opens, highs, lows, closes, k);
   if(!m.valid)
      return false;
   if(m.lower_wick_ratio < min_lower_wick_ratio) return false;
   if(m.body_ratio > max_body_ratio) return false;
   if(m.upper_wick_ratio > max_opposite_wick_ratio) return false;

   double close_position = (closes[k] - lows[k]) / (highs[k] - lows[k]);
   if(close_position < 0.60) // upper 40% of range
      return false;

   return closes[k + trend_lookback] > closes[k]; // preceding down-move
  }

bool CP_IsBearishPinBarArray(const double &opens[], const double &highs[],
                              const double &lows[], const double &closes[],
                              const int k, const int trend_lookback,
                              const double min_upper_wick_ratio = 0.60,
                              const double max_body_ratio = 0.30,
                              const double max_opposite_wick_ratio = 0.15)
  {
   int n = ArraySize(closes);
   if(k < 0 || k + trend_lookback >= n)
      return false;

   SCandleRatios m = CP_MeasureRatiosArray(opens, highs, lows, closes, k);
   if(!m.valid)
      return false;
   if(m.upper_wick_ratio < min_upper_wick_ratio) return false;
   if(m.body_ratio > max_body_ratio) return false;
   if(m.lower_wick_ratio > max_opposite_wick_ratio) return false;

   double close_position = (closes[k] - lows[k]) / (highs[k] - lows[k]);
   if(close_position > 0.40) // lower 40% of range
      return false;

   return closes[k + trend_lookback] < closes[k]; // preceding up-move
  }

bool CP_IsDragonflyRejectionArray(const double &opens[], const double &highs[],
                                   const double &lows[], const double &closes[],
                                   const int k, const double max_body_ratio = 0.10,
                                   const double min_wick_ratio = 0.70)
  {
   SCandleRatios m = CP_MeasureRatiosArray(opens, highs, lows, closes, k);
   if(!m.valid) return false;
   return m.body_ratio <= max_body_ratio &&
          m.lower_wick_ratio >= min_wick_ratio &&
          m.upper_wick_ratio <= max_body_ratio;
  }

bool CP_IsGravestoneRejectionArray(const double &opens[], const double &highs[],
                                    const double &lows[], const double &closes[],
                                    const int k, const double max_body_ratio = 0.10,
                                    const double min_wick_ratio = 0.70)
  {
   SCandleRatios m = CP_MeasureRatiosArray(opens, highs, lows, closes, k);
   if(!m.valid) return false;
   return m.body_ratio <= max_body_ratio &&
          m.upper_wick_ratio >= min_wick_ratio &&
          m.lower_wick_ratio <= max_body_ratio;
  }

bool CP_IsMarubozuArray(const double &opens[], const double &highs[], const double &lows[],
                         const double &closes[], const double &atr_values[], const int k,
                         const double min_body_ratio = 0.90,
                         const double displacement_atr_multiple = 1.5)
  {
   SCandleRatios m = CP_MeasureRatiosArray(opens, highs, lows, closes, k);
   if(!m.valid || m.body_ratio < min_body_ratio)
      return false;
   return CP_AtrSizeArray(highs, lows, atr_values, k) >= displacement_atr_multiple;
  }

bool CP_IsDojiArray(const double &opens[], const double &highs[], const double &lows[],
                     const double &closes[], const int k, const double max_body_ratio = 0.10)
  {
   SCandleRatios m = CP_MeasureRatiosArray(opens, highs, lows, closes, k);
   return m.valid && m.body_ratio <= max_body_ratio;
  }

bool CP_IsSpinningTopArray(const double &opens[], const double &highs[], const double &lows[],
                            const double &closes[], const int k,
                            const double doji_max_body_ratio = 0.10,
                            const double max_body_ratio = 0.35,
                            const double min_wick_ratio = 0.20)
  {
   SCandleRatios m = CP_MeasureRatiosArray(opens, highs, lows, closes, k);
   if(!m.valid) return false;
   if(m.body_ratio <= doji_max_body_ratio || m.body_ratio > max_body_ratio)
      return false;
   return m.upper_wick_ratio >= min_wick_ratio && m.lower_wick_ratio >= min_wick_ratio;
  }

bool CP_IsInsideBarArray(const double &highs[], const double &lows[], const int k)
  {
   int n = ArraySize(highs);
   if(k < 0 || k + 1 >= n) return false;
   return highs[k] < highs[k + 1] && lows[k] > lows[k + 1];
  }

bool CP_IsOutsideBarArray(const double &highs[], const double &lows[], const int k)
  {
   int n = ArraySize(highs);
   if(k < 0 || k + 1 >= n) return false;
   return highs[k] > highs[k + 1] && lows[k] < lows[k + 1];
  }

//+------------------------------------------------------------------+
//| Two-candle patterns                                                |
//+------------------------------------------------------------------+
bool CP_IsBullishEngulfingArray(const double &opens[], const double &highs[],
                                 const double &lows[], const double &closes[], const int k,
                                 const int size_window = 20,
                                 const double min_size_percentile = 0.50)
  {
   int n = ArraySize(closes);
   if(k < 0 || k + 1 >= n) return false;

   bool cond = closes[k] > opens[k + 1] && opens[k] < closes[k + 1] &&
               MathAbs(closes[k] - opens[k]) > MathAbs(closes[k + 1] - opens[k + 1]) &&
               closes[k + 1] < opens[k + 1];
   if(!cond) return false;

   return CP_SizePercentileArray(highs, lows, k, size_window) >= min_size_percentile;
  }

bool CP_IsBearishEngulfingArray(const double &opens[], const double &highs[],
                                 const double &lows[], const double &closes[], const int k,
                                 const int size_window = 20,
                                 const double min_size_percentile = 0.50)
  {
   int n = ArraySize(closes);
   if(k < 0 || k + 1 >= n) return false;

   bool cond = closes[k] < opens[k + 1] && opens[k] > closes[k + 1] &&
               MathAbs(closes[k] - opens[k]) > MathAbs(closes[k + 1] - opens[k + 1]) &&
               closes[k + 1] > opens[k + 1];
   if(!cond) return false;

   return CP_SizePercentileArray(highs, lows, k, size_window) >= min_size_percentile;
  }

bool CP_IsTweezerTopArray(const double &opens[], const double &highs[], const double &lows[],
                           const double &closes[], const double &atr_values[], const int k,
                           const double tolerance_atr = 0.10)
  {
   int n = ArraySize(highs);
   if(k < 0 || k + 1 >= n) return false;
   double atr = atr_values[k];
   if(atr <= 0.0) return false;

   bool close_highs = MathAbs(highs[k] - highs[k + 1]) <= atr * tolerance_atr;
   bool prior_up = closes[k + 1] > opens[k + 1];
   bool current_down = closes[k] < opens[k];
   return close_highs && prior_up && current_down;
  }

bool CP_IsTweezerBottomArray(const double &opens[], const double &highs[], const double &lows[],
                              const double &closes[], const double &atr_values[], const int k,
                              const double tolerance_atr = 0.10)
  {
   int n = ArraySize(lows);
   if(k < 0 || k + 1 >= n) return false;
   double atr = atr_values[k];
   if(atr <= 0.0) return false;

   bool close_lows = MathAbs(lows[k] - lows[k + 1]) <= atr * tolerance_atr;
   bool prior_down = closes[k + 1] < opens[k + 1];
   bool current_up = closes[k] > opens[k];
   return close_lows && prior_down && current_up;
  }

enum ENUM_HARAMI_DIRECTION
  {
   HARAMI_NONE,
   HARAMI_BULLISH_IMPLIED,
   HARAMI_BEARISH_IMPLIED
  };

ENUM_HARAMI_DIRECTION CP_DetectHaramiArray(const double &opens[], const double &closes[],
                                            const int k, const double max_ratio = 0.50)
  {
   int n = ArraySize(closes);
   if(k < 0 || k + 1 >= n)
      return HARAMI_NONE;

   double bh_k  = MathMax(opens[k], closes[k]);
   double bl_k  = MathMin(opens[k], closes[k]);
   double bh_k1 = MathMax(opens[k + 1], closes[k + 1]);
   double bl_k1 = MathMin(opens[k + 1], closes[k + 1]);
   double body_k  = bh_k - bl_k;
   double body_k1 = bh_k1 - bl_k1;

   if(body_k1 <= 0.0 || body_k >= body_k1 * max_ratio)
      return HARAMI_NONE;
   if(!(bh_k <= bh_k1 && bl_k >= bl_k1))
      return HARAMI_NONE;

   return (closes[k + 1] > opens[k + 1]) ? HARAMI_BEARISH_IMPLIED : HARAMI_BULLISH_IMPLIED;
  }

//+------------------------------------------------------------------+
//| Confirmation: a third bar (logical index k-1, i.e. NEWER than the    |
//| harami's own inside candle at k) closing beyond close[k+1] in the     |
//| implied direction.                                                    |
//+------------------------------------------------------------------+
bool CP_IsHaramiConfirmedArray(const double &closes[], const int k,
                                const ENUM_HARAMI_DIRECTION implied_direction)
  {
   int n = ArraySize(closes);
   if(k < 1 || k + 1 >= n)
      return false;
   if(implied_direction == HARAMI_BULLISH_IMPLIED)
      return closes[k - 1] > closes[k + 1];
   if(implied_direction == HARAMI_BEARISH_IMPLIED)
      return closes[k - 1] < closes[k + 1];
   return false;
  }

//+------------------------------------------------------------------+
//| Three-candle patterns                                              |
//+------------------------------------------------------------------+
bool CP_IsMorningStarArray(const double &opens[], const double &highs[],
                            const double &lows[], const double &closes[], const int k,
                            const double max_middle_body_ratio = 0.30,
                            const double max_overlap = 0.50)
  {
   int n = ArraySize(closes);
   if(k < 0 || k + 2 >= n) return false;
   if(!(closes[k + 2] < opens[k + 2])) return false; // first candle bearish

   SCandleRatios mid = CP_MeasureRatiosArray(opens, highs, lows, closes, k + 1);
   if(!mid.valid || mid.body_ratio > max_middle_body_ratio) return false;

   double bh1 = MathMax(opens[k + 2], closes[k + 2]);
   double bl1 = MathMin(opens[k + 2], closes[k + 2]);
   double body1 = bh1 - bl1;
   if(body1 <= 0.0) return false;

   double overlap = MathMax(0.0, MathMin(highs[k + 1], bh1) - MathMax(lows[k + 1], bl1));
   if(overlap / body1 > max_overlap) return false;

   if(!(closes[k] > opens[k])) return false; // third candle bullish
   double midpoint1 = (opens[k + 2] + closes[k + 2]) / 2.0;
   return closes[k] > midpoint1;
  }

bool CP_IsEveningStarArray(const double &opens[], const double &highs[],
                            const double &lows[], const double &closes[], const int k,
                            const double max_middle_body_ratio = 0.30,
                            const double max_overlap = 0.50)
  {
   int n = ArraySize(closes);
   if(k < 0 || k + 2 >= n) return false;
   if(!(closes[k + 2] > opens[k + 2])) return false; // first candle bullish

   SCandleRatios mid = CP_MeasureRatiosArray(opens, highs, lows, closes, k + 1);
   if(!mid.valid || mid.body_ratio > max_middle_body_ratio) return false;

   double bh1 = MathMax(opens[k + 2], closes[k + 2]);
   double bl1 = MathMin(opens[k + 2], closes[k + 2]);
   double body1 = bh1 - bl1;
   if(body1 <= 0.0) return false;

   double overlap = MathMax(0.0, MathMin(highs[k + 1], bh1) - MathMax(lows[k + 1], bl1));
   if(overlap / body1 > max_overlap) return false;

   if(!(closes[k] < opens[k])) return false; // third candle bearish
   double midpoint1 = (opens[k + 2] + closes[k + 2]) / 2.0;
   return closes[k] < midpoint1;
  }

bool CP_IsThreeWhiteSoldiersArray(const double &opens[], const double &highs[],
                                   const double &lows[], const double &closes[], const int k,
                                   const double min_body_ratio = 0.55,
                                   const double max_upper_wick_ratio = 0.20)
  {
   int n = ArraySize(closes);
   if(k < 0 || k + 2 >= n) return false;

   for(int i = 0; i <= 2; i++)
     {
      int idx = k + i;
      if(!(closes[idx] > opens[idx])) return false;
      SCandleRatios m = CP_MeasureRatiosArray(opens, highs, lows, closes, idx);
      if(!m.valid || m.body_ratio < min_body_ratio || m.upper_wick_ratio > max_upper_wick_ratio)
         return false;
     }
   if(!(opens[k] > opens[k + 1] && opens[k + 1] > opens[k + 2])) return false;
   if(!(closes[k] > closes[k + 1] && closes[k + 1] > closes[k + 2])) return false;
   return true;
  }

bool CP_IsThreeBlackCrowsArray(const double &opens[], const double &highs[],
                                const double &lows[], const double &closes[], const int k,
                                const double min_body_ratio = 0.55,
                                const double max_lower_wick_ratio = 0.20)
  {
   int n = ArraySize(closes);
   if(k < 0 || k + 2 >= n) return false;

   for(int i = 0; i <= 2; i++)
     {
      int idx = k + i;
      if(!(closes[idx] < opens[idx])) return false;
      SCandleRatios m = CP_MeasureRatiosArray(opens, highs, lows, closes, idx);
      if(!m.valid || m.body_ratio < min_body_ratio || m.lower_wick_ratio > max_lower_wick_ratio)
         return false;
     }
   if(!(opens[k] < opens[k + 1] && opens[k + 1] < opens[k + 2])) return false;
   if(!(closes[k] < closes[k + 1] && closes[k + 1] < closes[k + 2])) return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Three-bar reversal — the one pattern that consumes SwingEngine's     |
//| pivot predicate directly, per section 5's own requirement.           |
//+------------------------------------------------------------------+
bool CP_IsThreeBarReversalArray(const double &highs[], const double &lows[],
                                 const double &opens[], const double &closes[],
                                 const int k, const int swing_depth)
  {
   int n = ArraySize(closes);
   if(k < 0 || k + 2 >= n) return false;

   if(SE_IsConfirmedSwingLowArray(lows, k + 1, swing_depth))
      return closes[k] > opens[k + 2];
   if(SE_IsConfirmedSwingHighArray(highs, k + 1, swing_depth))
      return closes[k] < opens[k + 2];
   return false;
  }

//+------------------------------------------------------------------+
//| Strength and invalidation — per section 5's storage requirements.    |
//+------------------------------------------------------------------+
double CP_ComputeStrength(const double primary_ratio, const double atr_size)
  {
   double clamped_ratio = MathMax(0.0, MathMin(1.0, primary_ratio));
   double clamped_atr = MathMax(0.0, MathMin(1.0, atr_size / 2.0));
   return 0.5 * clamped_ratio + 0.5 * clamped_atr;
  }

//+------------------------------------------------------------------+
//| CMARKETDATA-INTEGRATED HELPERS                                      |
//| These read a generous window of OHLC (+ATR where needed) from a      |
//| real symbol/timeframe and hand it to the array-based functions       |
//| above — no pattern logic is duplicated here.                         |
//+------------------------------------------------------------------+
bool CP_ReadWindow(CMarketData &md, const int window, double &opens[], double &highs[],
                    double &lows[], double &closes[])
  {
   if(!md.HasBars(window))
      return false;

   ArrayResize(opens, window);
   ArrayResize(highs, window);
   ArrayResize(lows, window);
   ArrayResize(closes, window);

   for(int i = 0; i < window; i++)
     {
      if(!md.GetOpen(i, opens[i]) || !md.GetHigh(i, highs[i]) ||
         !md.GetLow(i, lows[i]) || !md.GetClose(i, closes[i]))
         return false;
     }
   return true;
  }

bool CP_ReadAtrWindow(CMarketData &md, const int window, const int period, double &atr_values[])
  {
   ArrayResize(atr_values, window);
   for(int i = 0; i < window; i++)
      if(!md.GetATR(i, atr_values[i], period))
         return false;
   return true;
  }
