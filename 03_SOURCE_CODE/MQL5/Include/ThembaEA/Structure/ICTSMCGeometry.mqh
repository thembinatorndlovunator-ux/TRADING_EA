//+------------------------------------------------------------------+
//| ICTSMCGeometry.mqh                                                 |
//| Themba Adaptive Intraday Engine — Structure                        |
//|                                                                    |
//| Fair value gaps, order blocks, liquidity sweeps, and premium/       |
//| discount classification, per                                       |
//| TASK-002_PHASE2_SPECIFICATION.md section 4. Combines what the        |
//| master-prompt architecture tree lists as three separate files        |
//| (LiquidityEngine.mqh, FVGEngine.mqh, OrderBlockEngine.mqh) into one   |
//| module for this task, since section 4 specifies all three as one      |
//| cohesive "ICT/SMC geometry" concern and they are small enough to      |
//| review together — matching the bundling precedent set by TASK-008.   |
//|                                                                    |
//| FVG uses the single canonical swing-depth definition from             |
//| SwingEngine.mqh exclusively (closes ledger item 14 — no independent   |
//| second depth input). Order blocks reuse                                |
//| CandlestickPatternEngine.mqh's Marubozu predicate directly for the     |
//| displacement-candle test, per section 4 ("the Marubozu predicate,      |
//| section 5") — no displacement logic is duplicated.                     |
//|                                                                    |
//| The liquidity-sweep detection algorithm below is this task's own      |
//| concrete formalization of section 4's ported-from-V8.11 description    |
//| ("a pool extreme is swept by a single bar's wick beyond it,             |
//| followed by a close back inside... this closing-back-inside bar is      |
//| the confirmation bar") — the specification describes the concept        |
//| precisely but not byte-level pseudocode, so the exact scan order and     |
//| loop structure here are a stated implementation choice, not a            |
//| verbatim transcription, same as MarketStructure.mqh's bias/break-event   |
//| definitions.                                                             |
//+------------------------------------------------------------------+
#property strict

#include "SwingEngine.mqh"
#include "../Patterns/CandlestickPatternEngine.mqh"

//+------------------------------------------------------------------+
//| Fair value gaps                                                    |
//+------------------------------------------------------------------+
enum ENUM_FVG_TYPE
  {
   FVG_NONE,
   FVG_BULLISH,
   FVG_BEARISH
  };

struct SFvgZone
  {
   ENUM_FVG_TYPE type;
   double        zone_high;
   double        zone_low;
   int           index; // logical index of the most recent (newest) of
                         // the three candles forming the gap
  };

//+------------------------------------------------------------------+
//| An FVG at logical index k spans candles k (newest), k+1 (middle),    |
//| k+2 (oldest): bullish iff low[k] > high[k+2]; bearish iff              |
//| high[k] < low[k+2] — per section 4 verbatim.                          |
//+------------------------------------------------------------------+
bool ICT_GetFvgZoneArray(const double &highs[], const double &lows[], const int k,
                          SFvgZone &zone)
  {
   zone.type = FVG_NONE;
   zone.zone_high = 0.0;
   zone.zone_low = 0.0;
   zone.index = k;

   int n = ArraySize(highs);
   if(k < 0 || k + 2 >= n)
      return false;

   if(lows[k] > highs[k + 2])
     {
      zone.type = FVG_BULLISH;
      zone.zone_low = highs[k + 2];
      zone.zone_high = lows[k];
      return true;
     }
   if(highs[k] < lows[k + 2])
     {
      zone.type = FVG_BEARISH;
      zone.zone_low = highs[k];
      zone.zone_high = lows[k + 2];
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Invalidation: a confirmed close fully through the gap.               |
//+------------------------------------------------------------------+
bool ICT_IsFvgInvalidated(const SFvgZone &zone, const double check_close)
  {
   if(zone.type == FVG_BULLISH)
      return check_close < zone.zone_low;
   if(zone.type == FVG_BEARISH)
      return check_close > zone.zone_high;
   return false;
  }

bool ICT_IsPriceInFvg(const SFvgZone &zone, const double price)
  {
   if(zone.type == FVG_NONE)
      return false;
   return price >= zone.zone_low && price <= zone.zone_high;
  }

double ICT_FvgFiftyPercentLevel(const SFvgZone &zone)
  {
   return (zone.zone_high + zone.zone_low) / 2.0;
  }

//+------------------------------------------------------------------+
//| Order blocks                                                       |
//+------------------------------------------------------------------+
enum ENUM_OB_TYPE
  {
   OB_NONE,
   OB_BULLISH,
   OB_BEARISH
  };

//+------------------------------------------------------------------+
//| An order block is the last opposite-direction candle (logical        |
//| index k+1) before a confirmed displacement move at logical index k    |
//| (the Marubozu predicate, CandlestickPatternEngine.mqh, reused          |
//| directly — not re-derived here). Its zone is that candle's full        |
//| range.                                                                  |
//+------------------------------------------------------------------+
bool ICT_DetectOrderBlockArray(const double &opens[], const double &highs[],
                                const double &lows[], const double &closes[],
                                const double &atr_values[], const int k,
                                const double displacement_atr_multiple,
                                ENUM_OB_TYPE &type, double &zone_high,
                                double &zone_low, int &ob_index)
  {
   type = OB_NONE;
   zone_high = 0.0;
   zone_low = 0.0;
   ob_index = -1;

   int n = ArraySize(closes);
   if(k < 0 || k + 1 >= n)
      return false;

   if(!CP_IsMarubozuArray(opens, highs, lows, closes, atr_values, k, 0.90,
                           displacement_atr_multiple))
      return false;

   bool displacement_bullish = closes[k] > opens[k];
   int ob = k + 1;
   bool ob_is_bearish = closes[ob] < opens[ob];
   bool ob_is_bullish = closes[ob] > opens[ob];

   if(displacement_bullish && ob_is_bearish)
     {
      type = OB_BULLISH;
      zone_high = highs[ob];
      zone_low = lows[ob];
      ob_index = ob;
      return true;
     }
   if(!displacement_bullish && ob_is_bullish)
     {
      type = OB_BEARISH;
      zone_high = highs[ob];
      zone_low = lows[ob];
      ob_index = ob;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Invalidation: a confirmed close through the zone.                    |
//+------------------------------------------------------------------+
bool ICT_IsOrderBlockInvalidated(const ENUM_OB_TYPE type, const double zone_high,
                                  const double zone_low, const double check_close)
  {
   if(type == OB_BULLISH) return check_close < zone_low;
   if(type == OB_BEARISH) return check_close > zone_high;
   return false;
  }

//+------------------------------------------------------------------+
//| Liquidity sweep and shift                                          |
//+------------------------------------------------------------------+
struct SSweepResult
  {
   bool   found;
   bool   is_bullish;              // true: swept sell-side liquidity
                                    // (a low), expecting a bullish
                                    // reaction; false: swept buy-side
                                    // liquidity (a high)
   double swept_level;
   int    sweep_bar_index;         // the bar whose wick first exceeded
                                    // the pool extreme
   int    confirmation_bar_index;  // the bar that closed back inside
                                    // the pool's prior range
  };

//+------------------------------------------------------------------+
//| Section 4's sweep pool / shift scan ranges, stated normatively:      |
//| pool: logical indices 4..min(n-2, 4+max(10,sweep_lookback));          |
//| shift: logical indices 2..min(n-2, 2+max(3,shift_lookback)).          |
//| Scans the shift window from its oldest bar toward the newest,          |
//| looking for a wick beyond either pool extreme, then searches            |
//| forward in time (toward index 0) from that bar for the first             |
//| confirmed close back inside — the earliest-in-time qualifying           |
//| confirmation, matching MarketStructure.mqh's own                        |
//| earliest-in-time-break convention for consistency across modules.       |
//+------------------------------------------------------------------+
bool ICT_DetectSweepArray(const double &highs[], const double &lows[], const double &closes[],
                           const int sweep_lookback, const int shift_lookback,
                           SSweepResult &result)
  {
   result.found = false;
   result.is_bullish = false;
   result.swept_level = 0.0;
   result.sweep_bar_index = -1;
   result.confirmation_bar_index = -1;

   int n = ArraySize(highs);

   int pool_start = 4;
   int pool_end = MathMin(n - 2, 4 + MathMax(10, sweep_lookback));
   if(pool_end < pool_start || pool_start >= n)
      return false;

   int shift_start = 2;
   int shift_end = MathMin(n - 2, 2 + MathMax(3, shift_lookback));
   if(shift_end < shift_start || shift_start >= n)
      return false;

   double pool_high = highs[pool_start];
   double pool_low  = lows[pool_start];
   for(int i = pool_start + 1; i <= pool_end; i++)
     {
      if(highs[i] > pool_high) pool_high = highs[i];
      if(lows[i]  < pool_low)  pool_low  = lows[i];
     }

   for(int k = shift_end; k >= shift_start; k--)
     {
      if(highs[k] > pool_high)
        {
         for(int c = k; c >= 0; c--)
           {
            if(closes[c] < pool_high)
              {
               result.found = true;
               result.is_bullish = false;
               result.swept_level = pool_high;
               result.sweep_bar_index = k;
               result.confirmation_bar_index = c;
               return true;
              }
           }
        }
      if(lows[k] < pool_low)
        {
         for(int c = k; c >= 0; c--)
           {
            if(closes[c] > pool_low)
              {
               result.found = true;
               result.is_bullish = true;
               result.swept_level = pool_low;
               result.sweep_bar_index = k;
               result.confirmation_bar_index = c;
               return true;
              }
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Final-stop transformation chain (buffer/floor/cap only — per          |
//| section 4, tick-size normalization and distance-recomputation-from-   |
//| the-normalized-price happen at order-submission time, an                |
//| Execution/-layer concern not yet built; this function computes the      |
//| pre-normalization stop DISTANCE only, a stated scope boundary).          |
//| floor/cap are supplied by the caller (RiskManager.mqh's                  |
//| RM_ComputeMinStopDistance/RM_ComputeMaxStopDistance) rather than           |
//| recomputed here, to avoid a Structure/-depends-on-Risk/ layering            |
//| inversion.                                                                  |
//+------------------------------------------------------------------+
bool ICT_ComputeSweepStopDistance(const double atr, const double spread,
                                   const double stop_atr_multiple,
                                   const double min_stop_distance,
                                   const double max_stop_distance,
                                   double &stop_distance, bool &rejected)
  {
   rejected = false;
   stop_distance = atr * stop_atr_multiple + spread;

   if(stop_distance < min_stop_distance)
      stop_distance = min_stop_distance;

   if(stop_distance > max_stop_distance)
     {
      rejected = true;
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Premium / discount classification                                  |
//| Trivial by design: reuses MarketStructure.mqh's already-computed     |
//| range_high/range_low/equilibrium (TASK-012) rather than re-deriving   |
//| a second notion of range/equilibrium, per ledger item 13.              |
//+------------------------------------------------------------------+
enum ENUM_PD_ZONE
  {
   PD_PREMIUM,
   PD_DISCOUNT,
   PD_EQUILIBRIUM
  };

ENUM_PD_ZONE ICT_ClassifyPremiumDiscount(const double price, const double equilibrium)
  {
   if(price > equilibrium) return PD_PREMIUM;
   if(price < equilibrium) return PD_DISCOUNT;
   return PD_EQUILIBRIUM;
  }
