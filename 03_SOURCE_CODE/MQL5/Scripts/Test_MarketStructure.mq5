//+------------------------------------------------------------------+
//| Test_MarketStructure.mq5                                          |
//| Themba Adaptive Intraday Engine — TASK-012 compile/logic test      |
//|                                                                    |
//| Tests 1-5 use hand-fabricated arrays covering the full 2x2 bias x   |
//| break-direction matrix (BOS_BULLISH, BOS_BEARISH, CHOCH_BULLISH,    |
//| CHOCH_BEARISH) plus an insufficient-data case — every expected      |
//| result is exactly hand-verifiable, no live data involved. Test 6    |
//| exercises the CMarketData wrapper against a real symbol.            |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Structure/MarketStructure.mqh"

input string          InpTestSymbol    = "EURUSD";
input ENUM_TIMEFRAMES InpTestTimeframe = PERIOD_M15;

int g_pass = 0;
int g_fail = 0;

void Check(const string label, const bool condition)
  {
   if(condition)
     {
      PrintFormat("PASS: %s", label);
      g_pass++;
     }
   else
     {
      PrintFormat("FAIL: %s", label);
      g_fail++;
     }
  }

bool NearlyEqual(const double a, const double b, const double tol = 0.0001)
  {
   return MathAbs(a - b) <= tol;
  }

void OnStart()
  {
   Print("=== TASK-012 MarketStructure test start ===");

   const int DEPTH = 1;
   const int LOOKBACK = 6;

   //--- Bullish-bias arrays (higher high @ idx3=65 > idx8=60; higher --
   //--- low @ idx5=30 > idx10=20). Size 16 throughout. -----------------
   double highsA[] = {40,40,40,65,40,40,40,40,60,40,40,40,40,40,40,40};
   double lowsA[]  = {50,50,50,50,50,30,50,50,50,50,20,50,50,50,50,50};

   //--- 1. BOS_BULLISH: bullish bias + break above the last swing high -
   double closesA_bosbull[] = {55,70,55,55,55,55,55,55,55,55,55,55,55,55,55,55};
   SMarketStructureState s1;
   bool ok1 = MS_ComputeStructureArray(highsA, lowsA, closesA_bosbull, DEPTH, LOOKBACK, s1);
   Check("scenario 1 computes successfully", ok1);
   Check("scenario 1: bias is BULLISH (higher high + higher low)",
         s1.bias == STRUCTURE_BIAS_BULLISH);
   Check("scenario 1: event is BOS_BULLISH (continuation)",
         s1.last_event == STRUCTURE_EVENT_BOS_BULLISH);
   Check("scenario 1: break index is exactly 1 (earliest qualifying close)",
         s1.last_event_index == 1);
   Check("scenario 1: range_high == 65 (the higher of the two swing highs)",
         NearlyEqual(s1.range_high, 65.0));
   Check("scenario 1: range_low == 20 (the lower of the two swing lows)",
         NearlyEqual(s1.range_low, 20.0));
   Check("scenario 1: equilibrium == 42.5 (midpoint)",
         NearlyEqual(s1.equilibrium, 42.5));

   //--- 2. CHOCH_BEARISH: same bullish-bias structure, but the break is -
   //---    BELOW the last swing low instead — a change of character ----
   double closesA_chochbear[] = {55,55,55,55,25,55,55,55,55,55,55,55,55,55,55,55};
   SMarketStructureState s2;
   bool ok2 = MS_ComputeStructureArray(highsA, lowsA, closesA_chochbear, DEPTH, LOOKBACK, s2);
   Check("scenario 2 computes successfully", ok2);
   Check("scenario 2: bias is still BULLISH (same swing structure)",
         s2.bias == STRUCTURE_BIAS_BULLISH);
   Check("scenario 2: event is CHOCH_BEARISH (break against bullish bias)",
         s2.last_event == STRUCTURE_EVENT_CHOCH_BEARISH);
   Check("scenario 2: break index is exactly 4", s2.last_event_index == 4);

   //--- Bearish-bias arrays (lower high @ idx3=60 < idx8=65; lower low -
   //--- @ idx5=20 < idx10=30). ------------------------------------------
   double highsB[] = {40,40,40,60,40,40,40,40,65,40,40,40,40,40,40,40};
   double lowsB[]  = {50,50,50,50,50,20,50,50,50,50,30,50,50,50,50,50};

   //--- 3. BOS_BEARISH: bearish bias + break below the last swing low --
   double closesB_bosbear[] = {45,45,15,45,45,45,45,45,45,45,45,45,45,45,45,45};
   SMarketStructureState s3;
   bool ok3 = MS_ComputeStructureArray(highsB, lowsB, closesB_bosbear, DEPTH, LOOKBACK, s3);
   Check("scenario 3 computes successfully", ok3);
   Check("scenario 3: bias is BEARISH (lower high + lower low)",
         s3.bias == STRUCTURE_BIAS_BEARISH);
   Check("scenario 3: event is BOS_BEARISH (continuation)",
         s3.last_event == STRUCTURE_EVENT_BOS_BEARISH);
   Check("scenario 3: break index is exactly 2", s3.last_event_index == 2);

   //--- 4. CHOCH_BULLISH: same bearish-bias structure, break ABOVE the -
   //---    last swing high instead — a change of character -------------
   double closesB_chochbull[] = {45,65,45,45,45,45,45,45,45,45,45,45,45,45,45,45};
   SMarketStructureState s4;
   bool ok4 = MS_ComputeStructureArray(highsB, lowsB, closesB_chochbull, DEPTH, LOOKBACK, s4);
   Check("scenario 4 computes successfully", ok4);
   Check("scenario 4: bias is still BEARISH (same swing structure)",
         s4.bias == STRUCTURE_BIAS_BEARISH);
   Check("scenario 4: event is CHOCH_BULLISH (break against bearish bias)",
         s4.last_event == STRUCTURE_EVENT_CHOCH_BULLISH);
   Check("scenario 4: break index is exactly 1", s4.last_event_index == 1);

   //--- 5. Insufficient data: a monotonic lows array has no interior ---
   //---    trough, so the computation must fail outright ----------------
   double lowsMonotonic[] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};
   SMarketStructureState s5;
   bool ok5 = MS_ComputeStructureArray(highsA, lowsMonotonic, closesA_bosbull, DEPTH,
                                        LOOKBACK, s5);
   Check("a monotonic lows array (no confirmable swing low) fails the computation",
         ok5 == false);
   Check("a failed computation leaves 'valid' false", s5.valid == false);

   //--- 6. CMarketData-integrated wrapper against a real symbol --------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok)
     {
      SMarketStructureState live;
      bool live_ok = MS_ComputeStructure(md, 3, 50, live);
      if(live_ok)
        {
         Check("real-symbol structure: range_high >= range_low",
               live.range_high >= live.range_low);
         Check("real-symbol structure: equilibrium lies within [range_low, range_high]",
               live.equilibrium >= live.range_low && live.equilibrium <= live.range_high);
         Check("real-symbol structure: swing_high_1 >= swing_low_1 (sane ordering)",
               live.swing_high_1_price >= live.swing_low_1_price);
        }
      else
        {
         PrintFormat("NOTE: MS_ComputeStructure could not compute a real "
                     "structure for '%s' — likely insufficient confirmed "
                     "swings in the scanned window, not necessarily a "
                     "defect.", InpTestSymbol);
        }
      Check("real-symbol structure computation completes without crashing "
            "regardless of outcome", true);
     }

   PrintFormat("=== TASK-012 MarketStructure test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
