//+------------------------------------------------------------------+
//| SupportResistance.mqh                                             |
//| Themba Adaptive Intraday Engine — Structure                        |
//|                                                                    |
//| SR-zone detection and equal-high/low liquidity, both built on       |
//| SwingEngine.mqh's pivot predicate. Equal-high/low liquidity is      |
//| defined exactly per TASK-002_PHASE2_SPECIFICATION.md section 4:     |
//| "two or more swing extremes within ATR x InpEqualLevelTolerance     |
//| (default 0.1) of each other." An SR zone generalizes this to N      |
//| touches at an arbitrary test price, serving the location-match       |
//| requirement candlestick/chart patterns need (section 5's "no          |
//| pattern fires as a standalone signal... without a location match")   |
//| and the target-selection nearest-SR-zone need (section 7).            |
//|                                                                    |
//| Resistance is built from swing HIGHS clustering; support from       |
//| swing LOWS — the conventional split, kept as two parallel function   |
//| families rather than one direction-agnostic family, since mixing    |
//| highs and lows into one "level" concept would blur what a caller     |
//| is actually asking about.                                            |
//|                                                                    |
//| Same array-based-core-plus-thin-wrapper pattern as SwingEngine.mqh   |
//| and MarketStructure.mqh.                                             |
//+------------------------------------------------------------------+
#property strict

#include "SwingEngine.mqh"

//+------------------------------------------------------------------+
//| ARRAY-BASED CORE                                                   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Count of confirmed swing highs within 'tolerance' of 'test_price',   |
//| scanned over logical indices [depth, depth+max_lookback).            |
//+------------------------------------------------------------------+
int SR_CountSwingHighTouchesArray(const double &highs[], const int depth,
                                   const int max_lookback, const double test_price,
                                   const double tolerance)
  {
   int count = 0;
   int n = ArraySize(highs);
   int start = depth;
   int end = start + max_lookback; // exclusive
   for(int k = start; k < end && k + depth < n; k++)
     {
      if(SE_IsConfirmedSwingHighArray(highs, k, depth) &&
         MathAbs(highs[k] - test_price) <= tolerance)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Mirror of SR_CountSwingHighTouchesArray on confirmed swing lows.     |
//+------------------------------------------------------------------+
int SR_CountSwingLowTouchesArray(const double &lows[], const int depth,
                                  const int max_lookback, const double test_price,
                                  const double tolerance)
  {
   int count = 0;
   int n = ArraySize(lows);
   int start = depth;
   int end = start + max_lookback;
   for(int k = start; k < end && k + depth < n; k++)
     {
      if(SE_IsConfirmedSwingLowArray(lows, k, depth) &&
         MathAbs(lows[k] - test_price) <= tolerance)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| True iff 'test_price' has at least 'min_touches' confirmed swing     |
//| highs within 'tolerance' of it — a resistance zone. 'touch_count'    |
//| is always set so a caller can log the actual figure regardless of    |
//| the boolean outcome.                                                 |
//+------------------------------------------------------------------+
bool SR_IsResistanceZoneArray(const double &highs[], const int depth,
                               const int max_lookback, const double test_price,
                               const double tolerance, const int min_touches,
                               int &touch_count)
  {
   touch_count = SR_CountSwingHighTouchesArray(highs, depth, max_lookback,
                                                test_price, tolerance);
   return touch_count >= min_touches;
  }

//+------------------------------------------------------------------+
//| Mirror of SR_IsResistanceZoneArray on confirmed swing lows —          |
//| support.                                                              |
//+------------------------------------------------------------------+
bool SR_IsSupportZoneArray(const double &lows[], const int depth,
                            const int max_lookback, const double test_price,
                            const double tolerance, const int min_touches,
                            int &touch_count)
  {
   touch_count = SR_CountSwingLowTouchesArray(lows, depth, max_lookback,
                                               test_price, tolerance);
   return touch_count >= min_touches;
  }

//+------------------------------------------------------------------+
//| Equal-high liquidity, per section 4 verbatim: true iff the confirmed |
//| swing high AT 'swing_index' itself has at least one other confirmed  |
//| swing high within 'tolerance' of it (i.e. total touches, including    |
//| itself, >= 2). False if 'swing_index' is not itself a confirmed        |
//| swing high.                                                            |
//+------------------------------------------------------------------+
bool SR_IsEqualHighLiquidityArray(const double &highs[], const int depth,
                                   const int max_lookback, const int swing_index,
                                   const double tolerance, int &touch_count)
  {
   touch_count = 0;
   if(!SE_IsConfirmedSwingHighArray(highs, swing_index, depth))
      return false;

   double price = highs[swing_index];
   touch_count = SR_CountSwingHighTouchesArray(highs, depth, max_lookback, price, tolerance);
   return touch_count >= 2;
  }

//+------------------------------------------------------------------+
//| Mirror of SR_IsEqualHighLiquidityArray on confirmed swing lows.       |
//+------------------------------------------------------------------+
bool SR_IsEqualLowLiquidityArray(const double &lows[], const int depth,
                                  const int max_lookback, const int swing_index,
                                  const double tolerance, int &touch_count)
  {
   touch_count = 0;
   if(!SE_IsConfirmedSwingLowArray(lows, swing_index, depth))
      return false;

   double price = lows[swing_index];
   touch_count = SR_CountSwingLowTouchesArray(lows, depth, max_lookback, price, tolerance);
   return touch_count >= 2;
  }

//+------------------------------------------------------------------+
//| CMARKETDATA-INTEGRATED WRAPPERS                                     |
//+------------------------------------------------------------------+

bool SR_IsResistanceZone(CMarketData &md, const int depth, const int max_lookback,
                          const double test_price, const double tolerance,
                          const int min_touches, int &touch_count)
  {
   touch_count = 0;
   int window = depth + max_lookback + depth;
   if(!md.HasBars(window))
      return false;

   double highs[];
   ArrayResize(highs, window);
   for(int i = 0; i < window; i++)
      if(!md.GetHigh(i, highs[i]))
         return false;

   return SR_IsResistanceZoneArray(highs, depth, max_lookback, test_price,
                                    tolerance, min_touches, touch_count);
  }

bool SR_IsSupportZone(CMarketData &md, const int depth, const int max_lookback,
                       const double test_price, const double tolerance,
                       const int min_touches, int &touch_count)
  {
   touch_count = 0;
   int window = depth + max_lookback + depth;
   if(!md.HasBars(window))
      return false;

   double lows[];
   ArrayResize(lows, window);
   for(int i = 0; i < window; i++)
      if(!md.GetLow(i, lows[i]))
         return false;

   return SR_IsSupportZoneArray(lows, depth, max_lookback, test_price,
                                 tolerance, min_touches, touch_count);
  }
