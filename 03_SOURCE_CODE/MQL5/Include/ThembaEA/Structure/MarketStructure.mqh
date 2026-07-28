//+------------------------------------------------------------------+
//| MarketStructure.mqh                                               |
//| Themba Adaptive Intraday Engine — Structure                        |
//|                                                                    |
//| Canonical BOS/CHoCH break-event detection and labeling, plus range  |
//| boundaries and equilibrium, built directly on SwingEngine.mqh's     |
//| pivot predicate — per TASK-002_PHASE2_SPECIFICATION.md section 11:  |
//| "SwingEngine/MarketStructure computes swing pivots, range          |
//| boundaries, and equilibrium together, as one function's output,     |
//| consumed identically by trading and drawing code" and ledger item   |
//| 1: "the shared structure module additionally computes and labels    |
//| BOS/CHoCH events using the canonical swing-pivot definition,         |
//| exposed as a labeled event stream consumed identically by trading    |
//| logic and StructureVisuals."                                        |
//|                                                                    |
//| Structural bias and break-event definitions (standard SMC/ICT        |
//| usage — see EA Files/SMC/* for the deeper reference material this    |
//| formalizes; not yet cross-checked against those PDFs in this task,  |
//| which is an explicit, stated scope boundary, not an oversight):      |
//|   - BIAS: comparing the two most recent confirmed swing highs and    |
//|     the two most recent confirmed swing lows. Both higher-high AND   |
//|     higher-low -> BULLISH. Both lower-high AND lower-low ->           |
//|     BEARISH. Anything else (including too few confirmed swings) ->   |
//|     NEUTRAL.                                                         |
//|   - BREAK EVENT: the EARLIEST-IN-TIME confirmed close after the       |
//|     most recent swing high/low that closes beyond it. A break above  |
//|     the last swing high while BULLISH bias is a BOS_BULLISH           |
//|     (continuation); the same break while BEARISH or NEUTRAL bias is  |
//|     a CHOCH_BULLISH (change of character / reversal signal). Mirror  |
//|     for a break below the last swing low.                            |
//|   - If both a bullish and bearish break are found in the scanned      |
//|     window, the more recent one (smaller logical index) is reported  |
//|     as the current event — a genuinely simultaneous dual-break is a  |
//|     rare, unresolved edge case in this first implementation, stated  |
//|     here rather than silently picked one way.                        |
//|                                                                    |
//| Split into an array-based core (pure, hand-testable) and a thin       |
//| CMarketData-integrated wrapper, matching SwingEngine.mqh's own         |
//| pattern.                                                              |
//+------------------------------------------------------------------+
#property strict

#include "SwingEngine.mqh"

enum ENUM_STRUCTURE_BIAS
  {
   STRUCTURE_BIAS_NEUTRAL,
   STRUCTURE_BIAS_BULLISH,
   STRUCTURE_BIAS_BEARISH
  };

enum ENUM_STRUCTURE_EVENT
  {
   STRUCTURE_EVENT_NONE,
   STRUCTURE_EVENT_BOS_BULLISH,
   STRUCTURE_EVENT_BOS_BEARISH,
   STRUCTURE_EVENT_CHOCH_BULLISH,
   STRUCTURE_EVENT_CHOCH_BEARISH
  };

struct SMarketStructureState
  {
   bool                valid;              // false if not enough confirmed
                                            // swings exist yet to compute anything
   int                 swing_high_1_index;
   double              swing_high_1_price;
   bool                has_swing_high_2;
   int                 swing_high_2_index;
   double              swing_high_2_price;
   int                 swing_low_1_index;
   double              swing_low_1_price;
   bool                has_swing_low_2;
   int                 swing_low_2_index;
   double              swing_low_2_price;
   ENUM_STRUCTURE_BIAS  bias;
   ENUM_STRUCTURE_EVENT last_event;
   int                 last_event_index;   // logical index of the break bar,
                                            // -1 if no break found
   double              range_high;
   double              range_low;
   double              equilibrium;
  };

//+------------------------------------------------------------------+
//| ARRAY-BASED CORE                                                   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Earliest-in-time logical index strictly newer than 'reference_index' |
//| whose close breaks 'reference_price' (above it if bullish, below it  |
//| if not). Scans from just after the reference point FORWARD in time   |
//| (i.e. decreasing logical index) so the first match found is the       |
//| actual break event, not merely "some later bar that also qualifies". |
//| Returns -1 if no such bar exists in range.                            |
//+------------------------------------------------------------------+
int MS_FindBreakIndexArray(const double &closes[], const int reference_index,
                            const double reference_price, const bool bullish)
  {
   int n = ArraySize(closes);
   int start = MathMin(reference_index - 1, n - 1);
   for(int k = start; k >= 0; k--)
     {
      double c = closes[k];
      bool condition = bullish ? (c > reference_price) : (c < reference_price);
      if(condition)
         return k;
     }
   return -1;
  }

//+------------------------------------------------------------------+
//| Full structure computation from fabricated/extracted arrays — see    |
//| the file header for the bias and break-event definitions.            |
//+------------------------------------------------------------------+
bool MS_ComputeStructureArray(const double &highs[], const double &lows[],
                               const double &closes[], const int depth,
                               const int max_lookback, SMarketStructureState &state)
  {
   state.valid = false;
   state.bias = STRUCTURE_BIAS_NEUTRAL;
   state.last_event = STRUCTURE_EVENT_NONE;
   state.last_event_index = -1;
   state.has_swing_high_2 = false;
   state.has_swing_low_2 = false;

   int sh1;
   if(!SE_FindNearestConfirmedSwingHighArray(highs, 0, depth, max_lookback, sh1))
      return false;
   state.swing_high_1_index = sh1;
   state.swing_high_1_price = highs[sh1];

   int sl1;
   if(!SE_FindNearestConfirmedSwingLowArray(lows, 0, depth, max_lookback, sl1))
      return false;
   state.swing_low_1_index = sl1;
   state.swing_low_1_price = lows[sl1];

   int sh2;
   if(SE_FindNearestConfirmedSwingHighArray(highs, sh1 + 1, depth, max_lookback, sh2))
     {
      state.swing_high_2_index = sh2;
      state.swing_high_2_price = highs[sh2];
      state.has_swing_high_2 = true;
     }

   int sl2;
   if(SE_FindNearestConfirmedSwingLowArray(lows, sl1 + 1, depth, max_lookback, sl2))
     {
      state.swing_low_2_index = sl2;
      state.swing_low_2_price = lows[sl2];
      state.has_swing_low_2 = true;
     }

   //--- Bias -------------------------------------------------------------
   if(state.has_swing_high_2 && state.has_swing_low_2)
     {
      bool higher_high = state.swing_high_1_price > state.swing_high_2_price;
      bool higher_low  = state.swing_low_1_price  > state.swing_low_2_price;
      bool lower_high  = state.swing_high_1_price < state.swing_high_2_price;
      bool lower_low   = state.swing_low_1_price  < state.swing_low_2_price;

      if(higher_high && higher_low)
         state.bias = STRUCTURE_BIAS_BULLISH;
      else if(lower_high && lower_low)
         state.bias = STRUCTURE_BIAS_BEARISH;
      else
         state.bias = STRUCTURE_BIAS_NEUTRAL;
     }

   //--- Break-event detection ---------------------------------------------
   int bull_break = MS_FindBreakIndexArray(closes, sh1, state.swing_high_1_price, true);
   int bear_break = MS_FindBreakIndexArray(closes, sl1, state.swing_low_1_price, false);

   int chosen_index = -1;
   bool chosen_is_bullish = false;
   if(bull_break >= 0 && bear_break >= 0)
     {
      // Both found — the more recent one (smaller logical index) wins;
      // see file header for why a true simultaneous tie is unresolved.
      if(bull_break <= bear_break)
        { chosen_index = bull_break; chosen_is_bullish = true; }
      else
        { chosen_index = bear_break; chosen_is_bullish = false; }
     }
   else if(bull_break >= 0)
     { chosen_index = bull_break; chosen_is_bullish = true; }
   else if(bear_break >= 0)
     { chosen_index = bear_break; chosen_is_bullish = false; }

   if(chosen_index >= 0)
     {
      state.last_event_index = chosen_index;
      if(chosen_is_bullish)
         state.last_event = (state.bias == STRUCTURE_BIAS_BULLISH)
                             ? STRUCTURE_EVENT_BOS_BULLISH
                             : STRUCTURE_EVENT_CHOCH_BULLISH;
      else
         state.last_event = (state.bias == STRUCTURE_BIAS_BEARISH)
                             ? STRUCTURE_EVENT_BOS_BEARISH
                             : STRUCTURE_EVENT_CHOCH_BEARISH;
     }

   //--- Range boundaries and equilibrium — shared with StructureVisuals, --
   //--- per ledger item 13, computed from the two most recent swing        --
   //--- points on each side (widest available pair, not just the nearest). -
   state.range_high = state.swing_high_1_price;
   state.range_low  = state.swing_low_1_price;
   if(state.has_swing_high_2 && state.swing_high_2_price > state.range_high)
      state.range_high = state.swing_high_2_price;
   if(state.has_swing_low_2 && state.swing_low_2_price < state.range_low)
      state.range_low = state.swing_low_2_price;
   state.equilibrium = (state.range_high + state.range_low) / 2.0;

   state.valid = true;
   return true;
  }

//+------------------------------------------------------------------+
//| CMARKETDATA-INTEGRATED WRAPPER                                     |
//+------------------------------------------------------------------+
bool MS_ComputeStructure(CMarketData &md, const int depth, const int max_lookback,
                          SMarketStructureState &state)
  {
   state.valid = false;

   // Generous window: enough to find two consecutive swings on each side
   // plus scan all the way back to the most recent completed bar for a
   // break event.
   int window = depth + 2 * max_lookback + depth + 1;
   if(!md.HasBars(window))
      return false;

   double highs[], lows[], closes[];
   ArrayResize(highs, window);
   ArrayResize(lows, window);
   ArrayResize(closes, window);
   for(int i = 0; i < window; i++)
     {
      if(!md.GetHigh(i, highs[i]) || !md.GetLow(i, lows[i]) || !md.GetClose(i, closes[i]))
         return false;
     }

   return MS_ComputeStructureArray(highs, lows, closes, depth, max_lookback, state);
  }
