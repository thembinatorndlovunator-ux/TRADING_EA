//+------------------------------------------------------------------+
//| ChartPatternEngine.mqh                                            |
//| Themba Adaptive Intraday Engine — Patterns                         |
//|                                                                    |
//| Double/triple top and bottom, and head-and-shoulders/inverse, per   |
//| TASK-002_PHASE2_SPECIFICATION.md section 6 — the two representative |
//| pattern families the specification formalizes in Phase 2; the        |
//| remaining 11 chart patterns (triangles, rectangle, flags, pennants,   |
//| wedges, channels) are explicitly deferred to Phase 5, per section     |
//| 6's own stated scope and this project's routing tables, which do     |
//| not reference them as eligible until formalized.                     |
//|                                                                    |
//| **Cross-checked against `EA Files/SRbounce/Idenitfying-Chart-        |
//| Patterns.pdf`** (a Fidelity Investments technical-analysis webinar,  |
//| citing Kirkpatrick & Dodge, "Technical Analysis: The Complete         |
//| Resource for Financial Market Technicians" — kept local-only per      |
//| SOURCE_LIBRARY.md's copyright rule) during this same task, not        |
//| deferred and fixed later the way TASK-014's candlestick engine was.   |
//| The head-and-shoulders definition matches that source closely (three  |
//| peaks, center highest, shoulders roughly equal, neckline through the  |
//| two troughs, target = head-to-neckline distance projected from the    |
//| neckline). **One concrete correction applied from that source:**      |
//| double/triple top and bottom target projections use the EXTREME       |
//| peak/trough (highest peak for tops, lowest trough for bottoms), not    |
//| an average of the peaks — the source states this explicitly            |
//| ("[t]aking the height from the highest peak to the trough..."),         |
//| correcting this task's own initial plan (carried over unreviewed        |
//| from TASK-002's spec text) to use an average.                           |
//|                                                                    |
//| **Explicit scope narrowing within this task:** triple top/bottom       |
//| (the three-peak/trough extension of the same framework) is deferred     |
//| to a fast-follow task rather than rushed here alongside double           |
//| top/bottom and head-and-shoulders/inverse — a stated boundary, not       |
//| an oversight.                                                            |
//|                                                                    |
//| Built directly on SwingEngine.mqh's pivot predicate — no swing logic    |
//| duplicated. Array-based core plus thin CMarketData wrapper, matching     |
//| every other Structure/Patterns module in this project.                   |
//+------------------------------------------------------------------+
#property strict

#include "../Structure/SwingEngine.mqh"

enum ENUM_CHART_PATTERN_TYPE
  {
   CPT_NONE,
   CPT_DOUBLE_TOP,
   CPT_DOUBLE_BOTTOM,
   CPT_HEAD_SHOULDERS,
   CPT_INV_HEAD_SHOULDERS,
   CPT_TRIPLE_TOP,     // TASK-039
   CPT_TRIPLE_BOTTOM   // TASK-039
  };

struct SChartPatternResult
  {
   bool                    found;
   ENUM_CHART_PATTERN_TYPE type;
   double                  boundary_price;  // neckline value at the reference point
   double                  extreme_price;   // the pattern-defining peak (tops) or trough (bottoms)
   double                  target;
   double                  stop;
   int                     breakout_index;  // -1 if no confirmed breakout found yet
  };

//+------------------------------------------------------------------+
//| Linear interpolation between two (index, price) points, used for    |
//| a head-and-shoulders neckline, which section 6 allows to be sloped   |
//| rather than flat.                                                    |
//+------------------------------------------------------------------+
double CPT_LinearInterpolate(const int x1, const double y1, const int x2, const double y2, const int k)
  {
   if(x1 == x2)
      return y1;
   return y1 + (y2 - y1) * ((double)(x1 - k)) / ((double)(x1 - x2));
  }

//+------------------------------------------------------------------+
//| Preceding-trend prerequisite: price moved meaningfully toward the    |
//| reference point over 'trend_bars' — a lightweight, directly-          |
//| computable proxy for section 6's "preceding confirmed uptrend/         |
//| downtrend" requirement (avoids a hard dependency on computing          |
//| MarketRegimeEngine's T_final at many historical indices, which that    |
//| module was not designed to do cheaply — a stated implementation        |
//| choice, same pattern as this project's other stated-choice notes).      |
//+------------------------------------------------------------------+
bool CPT_HasPriorTrend(const double &closes[], const int reference_index, const int trend_bars,
                        const bool require_up)
  {
   int n = ArraySize(closes);
   if(reference_index < 0 || reference_index + trend_bars >= n)
      return false;
   double earlier = closes[reference_index + trend_bars];
   double later = closes[reference_index];
   return require_up ? (earlier < later) : (earlier > later);
  }

//+------------------------------------------------------------------+
//| Double top: two confirmed swing highs within price tolerance,        |
//| separated by a confirmed swing low (the neckline) satisfying the      |
//| ATR-based pullback floor, per section 6.                              |
//+------------------------------------------------------------------+
bool CPT_DetectDoubleTopArray(const double &highs[], const double &lows[], const double &closes[],
                               const int depth, const int max_lookback, const double current_atr,
                               const double price_tolerance_atr, const double min_pullback_atr,
                               const int trend_bars, const double breakout_buffer_atr,
                               SChartPatternResult &result)
  {
   result.found = false;
   result.type = CPT_NONE;
   result.boundary_price = 0.0;
   result.extreme_price = 0.0;
   result.target = 0.0;
   result.stop = 0.0;
   result.breakout_index = -1;

   if(current_atr <= 0.0)
      return false;

   int h1;
   if(!SE_FindNearestConfirmedSwingHighArray(highs, 0, depth, max_lookback, h1))
      return false;
   int h2;
   if(!SE_FindNearestConfirmedSwingHighArray(highs, h1 + 1, depth, max_lookback, h2))
      return false;

   if(MathAbs(highs[h1] - highs[h2]) > current_atr * price_tolerance_atr)
      return false;

   int trough;
   if(!SE_FindNearestConfirmedSwingLowArray(lows, h1 + 1, depth, h2 - h1, trough))
      return false;
   if(trough >= h2)
      return false;

   double neckline = lows[trough];
   double extreme = MathMax(highs[h1], highs[h2]); // highest peak, per the reference source

   if(extreme - neckline < min_pullback_atr * current_atr)
      return false;
   if(!CPT_HasPriorTrend(closes, h2, trend_bars, true))
      return false;

   int breakout_level_index = -1;
   double breakout_level = neckline - current_atr * breakout_buffer_atr;
   for(int k = h1 - 1; k >= 0; k--)
     {
      if(closes[k] < breakout_level)
        {
         breakout_level_index = k;
         break;
        }
     }

   result.found = true;
   result.type = CPT_DOUBLE_TOP;
   result.boundary_price = neckline;
   result.extreme_price = extreme;
   result.target = neckline - (extreme - neckline);
   result.stop = highs[h1] + current_atr * breakout_buffer_atr; // above the more recent peak
   result.breakout_index = breakout_level_index;
   return true;
  }

//+------------------------------------------------------------------+
//| Mirror of CPT_DetectDoubleTopArray on swing lows.                    |
//+------------------------------------------------------------------+
bool CPT_DetectDoubleBottomArray(const double &highs[], const double &lows[], const double &closes[],
                                  const int depth, const int max_lookback, const double current_atr,
                                  const double price_tolerance_atr, const double min_pullback_atr,
                                  const int trend_bars, const double breakout_buffer_atr,
                                  SChartPatternResult &result)
  {
   result.found = false;
   result.type = CPT_NONE;
   result.boundary_price = 0.0;
   result.extreme_price = 0.0;
   result.target = 0.0;
   result.stop = 0.0;
   result.breakout_index = -1;

   if(current_atr <= 0.0)
      return false;

   int l1;
   if(!SE_FindNearestConfirmedSwingLowArray(lows, 0, depth, max_lookback, l1))
      return false;
   int l2;
   if(!SE_FindNearestConfirmedSwingLowArray(lows, l1 + 1, depth, max_lookback, l2))
      return false;

   if(MathAbs(lows[l1] - lows[l2]) > current_atr * price_tolerance_atr)
      return false;

   int peak;
   if(!SE_FindNearestConfirmedSwingHighArray(highs, l1 + 1, depth, l2 - l1, peak))
      return false;
   if(peak >= l2)
      return false;

   double neckline = highs[peak];
   double extreme = MathMin(lows[l1], lows[l2]); // lowest trough

   if(neckline - extreme < min_pullback_atr * current_atr)
      return false;
   if(!CPT_HasPriorTrend(closes, l2, trend_bars, false))
      return false;

   int breakout_level_index = -1;
   double breakout_level = neckline + current_atr * breakout_buffer_atr;
   for(int k = l1 - 1; k >= 0; k--)
     {
      if(closes[k] > breakout_level)
        {
         breakout_level_index = k;
         break;
        }
     }

   result.found = true;
   result.type = CPT_DOUBLE_BOTTOM;
   result.boundary_price = neckline;
   result.extreme_price = extreme;
   result.target = neckline + (neckline - extreme);
   result.stop = lows[l1] - current_atr * breakout_buffer_atr;
   result.breakout_index = breakout_level_index;
   return true;
  }

//+------------------------------------------------------------------+
//| Triple top: three confirmed swing highs (h1 newest, h2 middle, h3    |
//| oldest) PAIRWISE within price_tolerance_atr of EACH OTHER -- all         |
//| three pairs (h1-h2, h2-h3, AND h1-h3), per                                  |
//| TASK-002_PHASE2_SPECIFICATION.md section 6's own literal wording, not          |
//| just the two adjacent pairs (|H1-H2|<=tol and |H2-H3|<=tol does NOT             |
//| imply |H1-H3|<=tol -- by the triangle inequality it can be up to 2x tol,           |
//| a genuine spec deviation the seventh-round Codex review found, not a                 |
//| stated interpretation choice). Separated by two confirmed swing-low                    |
//| troughs forming a POSSIBLY SLOPED neckline through those two points                       |
//| (CPT_LinearInterpolate, the SAME sloped-neckline machinery                                  |
//| CPT_DetectHeadAndShouldersArray already uses) -- a previous flat                              |
//| MathMin(trough1,trough2) neckline is also fixed here, per the same                              |
//| review finding.                                                                                    |
//|                                                                    |
//| **Interpretation choice, stated explicitly (the spec's own triple-top       |
//| sentence does not fully pin this down beyond "same breakout/target/stop        |
//| logic using the neckline's value at the breakout bar"): boundary_price is           |
//| the neckline evaluated at h1 (the newest peak), mirroring                              |
//| CPT_DetectHeadAndShouldersArray's own "at rs (newest shoulder)"                            |
//| convention exactly. The pullback-depth floor is checked against BOTH                          |
//| troughs individually (extreme minus each trough's own raw low, not an   |
//| interpolated point) since a genuine pullback requirement is about how      |
//| far price actually retraced, independent of the neckline's own slope.**       |
//+------------------------------------------------------------------+
bool CPT_DetectTripleTopArray(const double &highs[], const double &lows[], const double &closes[],
                               const int depth, const int max_lookback, const double current_atr,
                               const double price_tolerance_atr, const double min_pullback_atr,
                               const int trend_bars, const double breakout_buffer_atr,
                               SChartPatternResult &result)
  {
   result.found = false;
   result.type = CPT_NONE;
   result.boundary_price = 0.0;
   result.extreme_price = 0.0;
   result.target = 0.0;
   result.stop = 0.0;
   result.breakout_index = -1;

   if(current_atr <= 0.0)
      return false;

   int h1;
   if(!SE_FindNearestConfirmedSwingHighArray(highs, 0, depth, max_lookback, h1))
      return false;
   int h2;
   if(!SE_FindNearestConfirmedSwingHighArray(highs, h1 + 1, depth, max_lookback, h2))
      return false;
   int h3;
   if(!SE_FindNearestConfirmedSwingHighArray(highs, h2 + 1, depth, max_lookback, h3))
      return false;

   if(MathAbs(highs[h1] - highs[h2]) > current_atr * price_tolerance_atr)
      return false;
   if(MathAbs(highs[h2] - highs[h3]) > current_atr * price_tolerance_atr)
      return false;
   if(MathAbs(highs[h1] - highs[h3]) > current_atr * price_tolerance_atr)
      return false;

   int trough1; // between h1 (newer) and h2
   if(!SE_FindNearestConfirmedSwingLowArray(lows, h1 + 1, depth, h2 - h1, trough1))
      return false;
   if(trough1 >= h2)
      return false;

   int trough2; // between h2 and h3 (older)
   if(!SE_FindNearestConfirmedSwingLowArray(lows, h2 + 1, depth, h3 - h2, trough2))
      return false;
   if(trough2 >= h3)
      return false;

   double extreme = MathMax(highs[h1], MathMax(highs[h2], highs[h3]));

   if(extreme - lows[trough1] < min_pullback_atr * current_atr)
      return false;
   if(extreme - lows[trough2] < min_pullback_atr * current_atr)
      return false;
   if(!CPT_HasPriorTrend(closes, h3, trend_bars, true))
      return false;

   int extreme_index = h1;
   if(highs[h2] > highs[extreme_index]) extreme_index = h2;
   if(highs[h3] > highs[extreme_index]) extreme_index = h3;

   int breakout_index = -1;
   for(int k = h1 - 1; k >= 0; k--)
     {
      double neck_k = CPT_LinearInterpolate(trough1, lows[trough1], trough2, lows[trough2], k);
      if(closes[k] < neck_k - current_atr * breakout_buffer_atr)
        {
         breakout_index = k;
         break;
        }
     }

   double neckline_at_extreme = CPT_LinearInterpolate(trough1, lows[trough1], trough2,
                                                         lows[trough2], extreme_index);
   int target_reference = (breakout_index >= 0) ? breakout_index : h1;
   double neckline_at_target = CPT_LinearInterpolate(trough1, lows[trough1], trough2, lows[trough2],
                                                        target_reference);

   result.found = true;
   result.type = CPT_TRIPLE_TOP;
   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P1 finding
   // 14): previously evaluated at 'h1' (the old pivot bar the neckline was
   // measured against, NOT the current bar) -- the live strategy's own
   // retest check (ChartPatternStrategy.mqh) compares this value directly
   // against closes[0] (the CURRENT bar's close). Whenever the neckline
   // has any slope, a value frozen at an old historical index is simply
   // wrong for that comparison -- it does not represent where the line
   // actually sits NOW. Projecting to index 0 (this array's own "current
   // bar" convention, matching every other index-0 read throughout this
   // module) makes boundary_price genuinely comparable to closes[0].**
   result.boundary_price = CPT_LinearInterpolate(trough1, lows[trough1], trough2, lows[trough2], 0);
   result.extreme_price = extreme;
   result.target = neckline_at_target - (extreme - neckline_at_extreme);
   result.stop = highs[h1] + current_atr * breakout_buffer_atr;
   result.breakout_index = breakout_index;
   return true;
  }

//+------------------------------------------------------------------+
//| Triple bottom: mirror of CPT_DetectTripleTopArray on swing lows --   |
//| see that function's own header for the seventh-round Codex review        |
//| fix (three-way pairwise tolerance + sloped neckline) this mirrors.          |
//+------------------------------------------------------------------+
bool CPT_DetectTripleBottomArray(const double &highs[], const double &lows[], const double &closes[],
                                  const int depth, const int max_lookback, const double current_atr,
                                  const double price_tolerance_atr, const double min_pullback_atr,
                                  const int trend_bars, const double breakout_buffer_atr,
                                  SChartPatternResult &result)
  {
   result.found = false;
   result.type = CPT_NONE;
   result.boundary_price = 0.0;
   result.extreme_price = 0.0;
   result.target = 0.0;
   result.stop = 0.0;
   result.breakout_index = -1;

   if(current_atr <= 0.0)
      return false;

   int l1;
   if(!SE_FindNearestConfirmedSwingLowArray(lows, 0, depth, max_lookback, l1))
      return false;
   int l2;
   if(!SE_FindNearestConfirmedSwingLowArray(lows, l1 + 1, depth, max_lookback, l2))
      return false;
   int l3;
   if(!SE_FindNearestConfirmedSwingLowArray(lows, l2 + 1, depth, max_lookback, l3))
      return false;

   if(MathAbs(lows[l1] - lows[l2]) > current_atr * price_tolerance_atr)
      return false;
   if(MathAbs(lows[l2] - lows[l3]) > current_atr * price_tolerance_atr)
      return false;
   if(MathAbs(lows[l1] - lows[l3]) > current_atr * price_tolerance_atr)
      return false;

   int peak1; // between l1 (newer) and l2
   if(!SE_FindNearestConfirmedSwingHighArray(highs, l1 + 1, depth, l2 - l1, peak1))
      return false;
   if(peak1 >= l2)
      return false;

   int peak2; // between l2 and l3 (older)
   if(!SE_FindNearestConfirmedSwingHighArray(highs, l2 + 1, depth, l3 - l2, peak2))
      return false;
   if(peak2 >= l3)
      return false;

   double extreme = MathMin(lows[l1], MathMin(lows[l2], lows[l3]));

   if(highs[peak1] - extreme < min_pullback_atr * current_atr)
      return false;
   if(highs[peak2] - extreme < min_pullback_atr * current_atr)
      return false;
   if(!CPT_HasPriorTrend(closes, l3, trend_bars, false))
      return false;

   int extreme_index = l1;
   if(lows[l2] < lows[extreme_index]) extreme_index = l2;
   if(lows[l3] < lows[extreme_index]) extreme_index = l3;

   int breakout_index = -1;
   for(int k = l1 - 1; k >= 0; k--)
     {
      double neck_k = CPT_LinearInterpolate(peak1, highs[peak1], peak2, highs[peak2], k);
      if(closes[k] > neck_k + current_atr * breakout_buffer_atr)
        {
         breakout_index = k;
         break;
        }
     }

   double neckline_at_extreme = CPT_LinearInterpolate(peak1, highs[peak1], peak2, highs[peak2],
                                                         extreme_index);
   int target_reference = (breakout_index >= 0) ? breakout_index : l1;
   double neckline_at_target = CPT_LinearInterpolate(peak1, highs[peak1], peak2, highs[peak2],
                                                        target_reference);

   result.found = true;
   result.type = CPT_TRIPLE_BOTTOM;
   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P1 finding
   // 14): see CPT_DetectTripleTopArray's own identical fix comment --
   // projects to index 0 (current bar) instead of the old 'l1' pivot.**
   result.boundary_price = CPT_LinearInterpolate(peak1, highs[peak1], peak2, highs[peak2], 0);
   result.extreme_price = extreme;
   result.target = neckline_at_target + (neckline_at_extreme - extreme);
   result.stop = lows[l1] - current_atr * breakout_buffer_atr;
   result.breakout_index = breakout_index;
   return true;
  }

//+------------------------------------------------------------------+
//| Head and shoulders: three confirmed swing highs (RS newest, Head,    |
//| LS oldest) with minimum head prominence and shoulder symmetry, a      |
//| sloped neckline through the two intervening swing lows, per           |
//| section 6 — matches the reference source's definition closely.        |
//+------------------------------------------------------------------+
bool CPT_DetectHeadAndShouldersArray(const double &highs[], const double &lows[], const double &closes[],
                                      const int depth, const int max_lookback, const double current_atr,
                                      const double price_tolerance_atr, const double time_tolerance,
                                      const double min_head_prominence_atr, const double breakout_buffer_atr,
                                      const int trend_bars, SChartPatternResult &result)
  {
   result.found = false;
   result.type = CPT_NONE;
   result.boundary_price = 0.0;
   result.extreme_price = 0.0;
   result.target = 0.0;
   result.stop = 0.0;
   result.breakout_index = -1;

   if(current_atr <= 0.0)
      return false;

   int rs;
   if(!SE_FindNearestConfirmedSwingHighArray(highs, 0, depth, max_lookback, rs))
      return false;
   int head;
   if(!SE_FindNearestConfirmedSwingHighArray(highs, rs + 1, depth, max_lookback, head))
      return false;
   int ls;
   if(!SE_FindNearestConfirmedSwingHighArray(highs, head + 1, depth, max_lookback, ls))
      return false;

   double H = highs[head], RS_p = highs[rs], LS_p = highs[ls];
   if(H <= MathMax(LS_p, RS_p))
      return false;
   if(H - MathMax(LS_p, RS_p) < min_head_prominence_atr * current_atr)
      return false;
   if(MathAbs(LS_p - RS_p) > current_atr * price_tolerance_atr)
      return false;

   double ls_to_head = (double)(ls - head);
   double head_to_rs = (double)(head - rs);
   if(ls_to_head <= 0.0 || head_to_rs <= 0.0)
      return false;
   double time_diff_ratio = MathAbs(ls_to_head - head_to_rs) / MathMax(ls_to_head, head_to_rs);
   if(time_diff_ratio > time_tolerance)
      return false;

   if(!CPT_HasPriorTrend(closes, ls, trend_bars, true)) // uptrend before the first (leftmost) shoulder
      return false;

   int trough1; // between ls (older) and head
   if(!SE_FindNearestConfirmedSwingLowArray(lows, head + 1, depth, ls - head, trough1))
      return false;
   if(trough1 >= ls)
      return false;

   int trough2; // between head and rs (newer)
   if(!SE_FindNearestConfirmedSwingLowArray(lows, rs + 1, depth, head - rs, trough2))
      return false;
   if(trough2 >= head)
      return false;

   int breakout_index = -1;
   for(int k = rs - 1; k >= 0; k--)
     {
      double neck_k = CPT_LinearInterpolate(trough1, lows[trough1], trough2, lows[trough2], k);
      if(closes[k] < neck_k - current_atr * breakout_buffer_atr)
        {
         breakout_index = k;
         break;
        }
     }

   double neckline_at_head = CPT_LinearInterpolate(trough1, lows[trough1], trough2, lows[trough2], head);
   int target_reference = (breakout_index >= 0) ? breakout_index : rs;
   double neckline_at_target = CPT_LinearInterpolate(trough1, lows[trough1], trough2, lows[trough2],
                                                       target_reference);

   result.found = true;
   result.type = CPT_HEAD_SHOULDERS;
   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P1 finding
   // 14): see CPT_DetectTripleTopArray's own identical fix comment --
   // projects to index 0 (current bar) instead of the old 'rs' pivot.**
   result.boundary_price = CPT_LinearInterpolate(trough1, lows[trough1], trough2, lows[trough2], 0);
   result.extreme_price = H;
   result.target = neckline_at_target - (H - neckline_at_head);
   result.stop = RS_p + current_atr * breakout_buffer_atr;
   result.breakout_index = breakout_index;
   return true;
  }

//+------------------------------------------------------------------+
//| Mirror of CPT_DetectHeadAndShouldersArray on swing lows.             |
//+------------------------------------------------------------------+
bool CPT_DetectInverseHeadAndShouldersArray(const double &highs[], const double &lows[],
                                             const double &closes[], const int depth,
                                             const int max_lookback, const double current_atr,
                                             const double price_tolerance_atr,
                                             const double time_tolerance,
                                             const double min_head_prominence_atr,
                                             const double breakout_buffer_atr,
                                             const int trend_bars, SChartPatternResult &result)
  {
   result.found = false;
   result.type = CPT_NONE;
   result.boundary_price = 0.0;
   result.extreme_price = 0.0;
   result.target = 0.0;
   result.stop = 0.0;
   result.breakout_index = -1;

   if(current_atr <= 0.0)
      return false;

   int rs;
   if(!SE_FindNearestConfirmedSwingLowArray(lows, 0, depth, max_lookback, rs))
      return false;
   int head;
   if(!SE_FindNearestConfirmedSwingLowArray(lows, rs + 1, depth, max_lookback, head))
      return false;
   int ls;
   if(!SE_FindNearestConfirmedSwingLowArray(lows, head + 1, depth, max_lookback, ls))
      return false;

   double H = lows[head], RS_p = lows[rs], LS_p = lows[ls];
   if(H >= MathMin(LS_p, RS_p))
      return false;
   if(MathMin(LS_p, RS_p) - H < min_head_prominence_atr * current_atr)
      return false;
   if(MathAbs(LS_p - RS_p) > current_atr * price_tolerance_atr)
      return false;

   double ls_to_head = (double)(ls - head);
   double head_to_rs = (double)(head - rs);
   if(ls_to_head <= 0.0 || head_to_rs <= 0.0)
      return false;
   double time_diff_ratio = MathAbs(ls_to_head - head_to_rs) / MathMax(ls_to_head, head_to_rs);
   if(time_diff_ratio > time_tolerance)
      return false;

   if(!CPT_HasPriorTrend(closes, ls, trend_bars, false)) // downtrend before the first (leftmost) shoulder
      return false;

   int peak1;
   if(!SE_FindNearestConfirmedSwingHighArray(highs, head + 1, depth, ls - head, peak1))
      return false;
   if(peak1 >= ls)
      return false;

   int peak2;
   if(!SE_FindNearestConfirmedSwingHighArray(highs, rs + 1, depth, head - rs, peak2))
      return false;
   if(peak2 >= head)
      return false;

   int breakout_index = -1;
   for(int k = rs - 1; k >= 0; k--)
     {
      double neck_k = CPT_LinearInterpolate(peak1, highs[peak1], peak2, highs[peak2], k);
      if(closes[k] > neck_k + current_atr * breakout_buffer_atr)
        {
         breakout_index = k;
         break;
        }
     }

   double neckline_at_head = CPT_LinearInterpolate(peak1, highs[peak1], peak2, highs[peak2], head);
   int target_reference = (breakout_index >= 0) ? breakout_index : rs;
   double neckline_at_target = CPT_LinearInterpolate(peak1, highs[peak1], peak2, highs[peak2],
                                                       target_reference);

   result.found = true;
   result.type = CPT_INV_HEAD_SHOULDERS;
   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P1 finding
   // 14): see CPT_DetectTripleTopArray's own identical fix comment --
   // projects to index 0 (current bar) instead of the old 'rs' pivot.**
   result.boundary_price = CPT_LinearInterpolate(peak1, highs[peak1], peak2, highs[peak2], 0);
   result.extreme_price = H;
   result.target = neckline_at_target + (neckline_at_head - H);
   result.stop = RS_p - current_atr * breakout_buffer_atr;
   result.breakout_index = breakout_index;
   return true;
  }

//+------------------------------------------------------------------+
//| Retest predicate, per section 6 (shared by every pattern above):     |
//| price returning within 'retest_tolerance_atr' of the boundary/        |
//| neckline enters the retest zone; holding means no confirmed close     |
//| beyond the boundary by more than 'failure_tolerance_atr' within        |
//| 'max_bars' of first touching that zone.                                |
//+------------------------------------------------------------------+
bool CPT_CheckRetestArray(const double &closes[], const int touch_index, const double boundary_price,
                           const bool is_bullish_breakout, const double current_atr,
                           const double failure_tolerance_atr, const int max_bars, bool &holds)
  {
   holds = false;
   int n = ArraySize(closes);
   if(touch_index < 0)
      return false;

   int end = MathMax(0, touch_index - max_bars);
   for(int k = touch_index; k >= end && k >= 0; k--)
     {
      if(is_bullish_breakout)
        {
         if(closes[k] < boundary_price - current_atr * failure_tolerance_atr)
           {
            holds = false;
            return true;
           }
        }
      else
        {
         if(closes[k] > boundary_price + current_atr * failure_tolerance_atr)
           {
            holds = false;
            return true;
           }
        }
     }
   holds = true;
   return true;
  }

//+------------------------------------------------------------------+
//| CMARKETDATA-INTEGRATED WRAPPER                                     |
//+------------------------------------------------------------------+
bool CPT_ReadPatternWindow(CMarketData &md, const int window, double &highs[], double &lows[],
                            double &closes[], double &current_atr, const int atr_period = 14)
  {
   if(!md.HasBars(window))
      return false;

   ArrayResize(highs, window);
   ArrayResize(lows, window);
   ArrayResize(closes, window);
   for(int i = 0; i < window; i++)
      if(!md.GetHigh(i, highs[i]) || !md.GetLow(i, lows[i]) || !md.GetClose(i, closes[i]))
         return false;

   return md.GetATR(0, current_atr, atr_period);
  }
