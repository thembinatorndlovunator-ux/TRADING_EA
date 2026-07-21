//+------------------------------------------------------------------+
//| SwingEngine.mqh                                                   |
//| Themba Adaptive Intraday Engine — Structure                        |
//|                                                                    |
//| The canonical confirmed swing-pivot predicate, defined ONCE here    |
//| and reused everywhere, per TASK-002_PHASE2_SPECIFICATION.md         |
//| section 6: "a confirmed swing high at logical index k requires      |
//| high[k] > high[j] for all j in [k-InpSwingDepth, k-1] u [k+1,        |
//| k+InpSwingDepth] (default depth 3); confirmed only once             |
//| InpSwingDepth further bars have closed past index k. Swing low:      |
//| mirrored on lows." This closes round-3 review's repeated finding      |
//| that "SwingEngine has no mathematical pivot predicate," raised        |
//| independently against sections 4, 5, and 6.                          |
//|                                                                    |
//| Split into an ARRAY-BASED CORE (pure, deterministic, fully hand-     |
//| testable with fabricated data — no live symbol required) and a       |
//| thin CMarketData-INTEGRATED WRAPPER that reads the needed window      |
//| from a real symbol/timeframe and delegates to the core. Every other  |
//| module in this project (regime engine, candlestick three-bar         |
//| reversal, chart-pattern pivots, exit-engine "swing in favor"          |
//| trailing) is specified to consume the wrapper functions — this is    |
//| what makes the shared-pivot-definition requirement (ledger item 1,   |
//| and sections 2/5/6/7's repeated "reuses this, not a new definition") |
//| structurally enforced rather than a documentation convention.        |
//+------------------------------------------------------------------+
#property strict

#include "../Market/MarketData.mqh"

//+------------------------------------------------------------------+
//| ARRAY-BASED CORE                                                   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| True iff logical index k in 'highs' (index 0 = most recently         |
//| completed bar, per the project's logical-index convention) is a      |
//| confirmed swing high at the given depth: high[k] strictly exceeds    |
//| every one of the 'depth' bars immediately newer AND every one of      |
//| the 'depth' bars immediately older. Requires k >= depth (enough       |
//| newer bars have closed to confirm it) and k+depth < ArraySize(highs)  |
//| (enough older history exists to test the far side) — a false          |
//| return for either bound violation means "not yet confirmable /        |
//| insufficient data", not "not a swing".                                |
//+------------------------------------------------------------------+
bool SE_IsConfirmedSwingHighArray(const double &highs[], const int k, const int depth)
  {
   int n = ArraySize(highs);
   if(depth <= 0 || k < depth || k + depth >= n)
      return false;

   double high_k = highs[k];
   for(int offset = 1; offset <= depth; offset++)
     {
      if(highs[k - offset] >= high_k) // a newer bar at or above -> not a pivot
         return false;
      if(highs[k + offset] >= high_k) // an older bar at or above -> not a pivot
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Mirror of SE_IsConfirmedSwingHighArray on lows (strictly below       |
//| every neighbor within 'depth' on both sides).                        |
//+------------------------------------------------------------------+
bool SE_IsConfirmedSwingLowArray(const double &lows[], const int k, const int depth)
  {
   int n = ArraySize(lows);
   if(depth <= 0 || k < depth || k + depth >= n)
      return false;

   double low_k = lows[k];
   for(int offset = 1; offset <= depth; offset++)
     {
      if(lows[k - offset] <= low_k)
         return false;
      if(lows[k + offset] <= low_k)
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Scans logical indices [max(min_index,depth) .. +max_lookback) for   |
//| the nearest (smallest k, i.e. most recent) confirmed swing high,      |
//| returning it via 'found_index'. False if none found in range or if   |
//| 'highs' is too short to test the full requested range — this          |
//| function never silently tests a reduced/partial range; a caller       |
//| must supply an array long enough for the full request.                |
//+------------------------------------------------------------------+
bool SE_FindNearestConfirmedSwingHighArray(const double &highs[], const int min_index,
                                            const int depth, const int max_lookback,
                                            int &found_index)
  {
   found_index = -1;
   if(depth <= 0 || max_lookback <= 0)
      return false;

   int start = MathMax(min_index, depth);
   int last_k = start + max_lookback - 1;
   if(last_k + depth >= ArraySize(highs))
      return false; // not enough data to test the full requested range

   for(int k = start; k <= last_k; k++)
     {
      if(SE_IsConfirmedSwingHighArray(highs, k, depth))
        {
         found_index = k;
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Mirror of SE_FindNearestConfirmedSwingHighArray on lows.             |
//+------------------------------------------------------------------+
bool SE_FindNearestConfirmedSwingLowArray(const double &lows[], const int min_index,
                                           const int depth, const int max_lookback,
                                           int &found_index)
  {
   found_index = -1;
   if(depth <= 0 || max_lookback <= 0)
      return false;

   int start = MathMax(min_index, depth);
   int last_k = start + max_lookback - 1;
   if(last_k + depth >= ArraySize(lows))
      return false;

   for(int k = start; k <= last_k; k++)
     {
      if(SE_IsConfirmedSwingLowArray(lows, k, depth))
        {
         found_index = k;
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| CMARKETDATA-INTEGRATED WRAPPERS                                     |
//| Each reads exactly the window the core needs from a real symbol/     |
//| timeframe (via CMarketData, TASK-005 — enforcing the same logical-   |
//| index, completed-bar-only convention everywhere) and delegates to    |
//| the array-based core above. No swing/pivot math is duplicated here.  |
//+------------------------------------------------------------------+

bool SE_IsConfirmedSwingHigh(CMarketData &md, const int k, const int depth = 3)
  {
   if(depth <= 0 || k < depth)
      return false;

   int window = k + depth + 1;
   if(!md.HasBars(window))
      return false;

   double highs[];
   ArrayResize(highs, window);
   for(int i = 0; i < window; i++)
      if(!md.GetHigh(i, highs[i]))
         return false;

   return SE_IsConfirmedSwingHighArray(highs, k, depth);
  }

bool SE_IsConfirmedSwingLow(CMarketData &md, const int k, const int depth = 3)
  {
   if(depth <= 0 || k < depth)
      return false;

   int window = k + depth + 1;
   if(!md.HasBars(window))
      return false;

   double lows[];
   ArrayResize(lows, window);
   for(int i = 0; i < window; i++)
      if(!md.GetLow(i, lows[i]))
         return false;

   return SE_IsConfirmedSwingLowArray(lows, k, depth);
  }

bool SE_FindNearestConfirmedSwingHigh(CMarketData &md, const int min_index,
                                       const int depth, const int max_lookback,
                                       int &found_index)
  {
   found_index = -1;
   if(depth <= 0 || max_lookback <= 0)
      return false;

   int start = MathMax(min_index, depth);
   int window = start + max_lookback - 1 + depth + 1; // last tested k's far neighbor + 1
   if(!md.HasBars(window))
      return false;

   double highs[];
   ArrayResize(highs, window);
   for(int i = 0; i < window; i++)
      if(!md.GetHigh(i, highs[i]))
         return false;

   return SE_FindNearestConfirmedSwingHighArray(highs, min_index, depth, max_lookback,
                                                 found_index);
  }

bool SE_FindNearestConfirmedSwingLow(CMarketData &md, const int min_index,
                                      const int depth, const int max_lookback,
                                      int &found_index)
  {
   found_index = -1;
   if(depth <= 0 || max_lookback <= 0)
      return false;

   int start = MathMax(min_index, depth);
   int window = start + max_lookback - 1 + depth + 1;
   if(!md.HasBars(window))
      return false;

   double lows[];
   ArrayResize(lows, window);
   for(int i = 0; i < window; i++)
      if(!md.GetLow(i, lows[i]))
         return false;

   return SE_FindNearestConfirmedSwingLowArray(lows, min_index, depth, max_lookback,
                                                found_index);
  }
