//+------------------------------------------------------------------+
//| Test_CandlestickPatternEngine.mq5                                 |
//| Themba Adaptive Intraday Engine — TASK-014 compile/logic test      |
//|                                                                    |
//| Every case below uses hand-fabricated OHLC(+ATR) arrays with values |
//| chosen so the expected result is derivable by hand from section 5's |
//| own formulas — no live data involved except the final smoke test.   |
//| Coverage is one clear positive (and, for several patterns, one       |
//| clear negative) per pattern, not exhaustive edge-case coverage —     |
//| stated explicitly in TASK-014_CANDLESTICK_PATTERN_ENGINE.md's Risks. |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Patterns/CandlestickPatternEngine.mqh"

input string          InpTestSymbol    = "EURUSD";
input ENUM_TIMEFRAMES InpTestTimeframe = PERIOD_M15;

int g_pass = 0;
int g_fail = 0;

void Check(const string label, const bool condition)
  {
   if(condition) { PrintFormat("PASS: %s", label); g_pass++; }
   else          { PrintFormat("FAIL: %s", label); g_fail++; }
  }

bool NearlyEqual(const double a, const double b, const double tol = 0.0001)
  {
   return MathAbs(a - b) <= tol;
  }

void OnStart()
  {
   Print("=== TASK-014 CandlestickPatternEngine test start ===");

   //--- Bullish pin bar: low=90 high=98 open=95 close=97; closes[5]=105 -
   {
      double o[] = {95,96,96,96,96,96};
      double h[] = {98,99,99,99,99,99};
      double l[] = {90,94,94,94,94,94};
      double c[] = {97,96,96,96,96,105};
      Check("bullish pin bar detected on the fabricated positive case",
            CP_IsBullishPinBarArray(o,h,l,c,0,5));
      double c_neg[] = {97,96,96,96,96,90}; // no preceding down-move
      Check("bullish pin bar rejected when there is no preceding down-move",
            CP_IsBullishPinBarArray(o,h,l,c_neg,0,5) == false);
   }

   //--- Dragonfly / gravestone rejection ----------------------------------
   {
      double o[] = {99}, h[] = {100}, l[] = {90}, c[] = {99};
      Check("dragonfly rejection detected", CP_IsDragonflyRejectionArray(o,h,l,c,0));
   }
   {
      double o[] = {91}, h[] = {100}, l[] = {90}, c[] = {91};
      Check("gravestone rejection detected", CP_IsGravestoneRejectionArray(o,h,l,c,0));
   }

   //--- Marubozu / displacement -------------------------------------------
   {
      double o[] = {100}, h[] = {110}, l[] = {100}, c[] = {110};
      double atr_ok[] = {5};
      double atr_bad[] = {10};
      Check("marubozu detected with sufficient ATR displacement (atr=5)",
            CP_IsMarubozuArray(o,h,l,c,atr_ok,0));
      Check("marubozu rejected when ATR displacement is insufficient (atr=10)",
            CP_IsMarubozuArray(o,h,l,c,atr_bad,0) == false);
   }

   //--- Doji / spinning top -------------------------------------------------
   {
      double o[] = {100}, h[] = {105}, l[] = {95}, c[] = {100.5};
      Check("doji detected (body_ratio 0.05)", CP_IsDojiArray(o,h,l,c,0));
   }
   {
      double o[] = {94}, h[] = {100}, l[] = {90}, c[] = {96};
      Check("spinning top detected (body_ratio 0.20, both wicks 0.40)",
            CP_IsSpinningTopArray(o,h,l,c,0));
   }

   //--- Inside / outside bar -------------------------------------------------
   {
      double h[] = {95,100}, l[] = {91,90};
      Check("inside bar detected", CP_IsInsideBarArray(h,l,0));
      Check("inside bar is not also an outside bar", CP_IsOutsideBarArray(h,l,0) == false);
   }
   {
      double h[] = {105,100}, l[] = {85,90};
      Check("outside bar detected", CP_IsOutsideBarArray(h,l,0));
   }

   //--- Bullish / bearish engulfing (with size-percentile check) ---------
   {
      double o[] = {94,100,50,50,50};
      double h[] = {102,101,52,52,52};
      double l[] = {93,95,49,49,49};
      double c[] = {101,95,51,51,51};
      Check("bullish engulfing detected (size percentile 1.0)",
            CP_IsBullishEngulfingArray(o,h,l,c,0));
   }
   {
      double o[] = {101,95,50,50,50};
      double h[] = {102,100,52,52,52};
      double l[] = {94,94,49,49,49};
      double c[] = {94,100,51,51,51};
      Check("bearish engulfing detected (size percentile 1.0)",
            CP_IsBearishEngulfingArray(o,h,l,c,0));
   }

   //--- Tweezer top / bottom -------------------------------------------------
   {
      double o[] = {99,95}, h[] = {100.1,100.0}, l[] = {95,94}, c[] = {96,99};
      double atr[] = {2,2};
      Check("tweezer top detected", CP_IsTweezerTopArray(o,h,l,c,atr,0));
   }
   {
      double o[] = {96,99}, h[] = {101,102}, l[] = {89.9,90.0}, c[] = {99,96};
      double atr[] = {2,2};
      Check("tweezer bottom detected", CP_IsTweezerBottomArray(o,h,l,c,atr,0));
   }

   //--- Harami: detect + third-bar confirmation ------------------------------
   {
      double o[] = {93,97,100};
      double h[] = {96,99,101};
      double l[] = {92,96,89};
      double c[] = {95,98,90};
      ENUM_HARAMI_DIRECTION dir = CP_DetectHaramiArray(o,c,1);
      Check("harami detected with bullish-implied direction (prior candle bearish)",
            dir == HARAMI_BULLISH_IMPLIED);
      Check("harami confirmed by the third (newest) bar closing beyond the "
            "prior candle's close in the implied direction",
            CP_IsHaramiConfirmedArray(c,1,dir));
   }

   //--- Morning star -----------------------------------------------------------
   {
      double o[] = {99,99,110};
      double h[] = {109,101,111};
      double l[] = {98,97,99};
      double c[] = {108,98,100};
      Check("morning star detected", CP_IsMorningStarArray(o,h,l,c,0));
   }

   //--- Evening star -------------------------------------------------------------
   {
      double o[] = {102,101,100};
      double h[] = {103,103,111};
      double l[] = {96,99,99};
      double c[] = {97,102,110};
      Check("evening star detected", CP_IsEveningStarArray(o,h,l,c,0));
   }

   //--- Three white soldiers --------------------------------------------------
   {
      double o[] = {108,104,100};
      double h[] = {115,111,107};
      double l[] = {108,104,100};
      double c[] = {114,110,106};
      Check("three white soldiers detected", CP_IsThreeWhiteSoldiersArray(o,h,l,c,0));
   }

   //--- Three black crows ------------------------------------------------------
   {
      double o[] = {106,110,114};
      double h[] = {106,110,114};
      double l[] = {99,103,107};
      double c[] = {100,104,108};
      Check("three black crows detected", CP_IsThreeBlackCrowsArray(o,h,l,c,0));
   }

   //--- Three-bar reversal (bullish: confirmed swing low at k+1) ------------
   {
      double h[] = {15,20,15};
      double l[] = {10,5,10};
      double o[] = {9,7,8};
      double c[] = {9,6,7};
      Check("bullish three-bar reversal detected at a confirmed swing low",
            CP_IsThreeBarReversalArray(h,l,o,c,0,1));
   }
   //--- Three-bar reversal (bearish: confirmed swing high at k+1) -----------
   {
      double h[] = {10,15,10};
      double l[] = {5,6,5};
      double o[] = {11,13,12};
      double c[] = {11,14,13};
      Check("bearish three-bar reversal detected at a confirmed swing high",
            CP_IsThreeBarReversalArray(h,l,o,c,0,1));
   }

   //--- Strength formula, hand-verified ------------------------------------
   Check("CP_ComputeStrength(0.8, 1.0) == 0.65",
         NearlyEqual(CP_ComputeStrength(0.8, 1.0), 0.65));
   Check("CP_ComputeStrength clamps out-of-range inputs to 1.0",
         NearlyEqual(CP_ComputeStrength(1.5, 3.0), 1.0));

   //--- CMarketData-integrated read helpers against a real symbol ------------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok && md.HasBars(30))
     {
      double ro[], rh[], rl[], rc[], ratr[];
      bool read_ok = CP_ReadWindow(md, 20, ro, rh, rl, rc);
      Check("CP_ReadWindow reads a real-symbol OHLC window successfully", read_ok);
      if(read_ok)
        {
         bool atr_ok = CP_ReadAtrWindow(md, 20, 14, ratr);
         Check("CP_ReadAtrWindow reads a real-symbol ATR window successfully", atr_ok);
         if(atr_ok)
           {
            // Exercise a handful of pattern checks against real data purely
            // for a no-crash / sane-output smoke test — not hand-verifiable.
            bool dummy1 = CP_IsDojiArray(ro, rh, rl, rc, 0);
            bool dummy2 = CP_IsMarubozuArray(ro, rh, rl, rc, ratr, 0);
            Check("real-symbol pattern checks complete without crashing",
                  true);
           }
        }
     }
   else
     {
      PrintFormat("NOTE: '%s' does not have enough history — real-symbol "
                  "smoke test skipped.", InpTestSymbol);
     }

   PrintFormat("=== TASK-014 CandlestickPatternEngine test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
