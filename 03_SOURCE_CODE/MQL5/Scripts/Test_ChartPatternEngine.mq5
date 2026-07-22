//+------------------------------------------------------------------+
//| Test_ChartPatternEngine.mq5                                       |
//| Themba Adaptive Intraday Engine — TASK-018 compile/logic test      |
//|                                                                    |
//| Every scenario is a hand-fabricated array with values chosen so the |
//| expected result — including the sloped-neckline linear             |
//| interpolation for head-and-shoulders — is derivable by hand.        |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Patterns/ChartPatternEngine.mqh"

input string          InpTestSymbol    = "EURUSD";
input ENUM_TIMEFRAMES InpTestTimeframe = PERIOD_M15;

int g_pass = 0;
int g_fail = 0;

void Check(const string label, const bool condition)
  {
   if(condition) { PrintFormat("PASS: %s", label); g_pass++; }
   else          { PrintFormat("FAIL: %s", label); g_fail++; }
  }

bool NearlyEqual(const double a, const double b, const double tol = 0.001)
  {
   return MathAbs(a - b) <= tol;
  }

void OnStart()
  {
   Print("=== TASK-018 ChartPatternEngine test start ===");

   const int    DEPTH = 1;
   const int    LOOKBACK = 8;
   const double ATR = 2.0;
   const double PRICE_TOL = 1.0;
   const double PULLBACK_ATR = 1.0;
   const int    TREND_BARS = 3;
   const double BREAKOUT_BUF = 0.1;

   //--- 1. Double top -------------------------------------------------------
   {
      double highs[]  = {95,95,95,100,95,95,95,101,95,95,95,95,95};
      double lows[]   = {95,95,95,95,95,90,95,95,95,95,95,95,95};
      double closes[] = {88,88,92,95,95,95,95,100,95,95,93,95,95};
      SChartPatternResult r;
      bool ok = CPT_DetectDoubleTopArray(highs, lows, closes, DEPTH, LOOKBACK, ATR,
                                          PRICE_TOL, PULLBACK_ATR, TREND_BARS,
                                          BREAKOUT_BUF, r);
      Check("double top detected", ok && r.found && r.type == CPT_DOUBLE_TOP);
      Check("double top boundary_price == 90 (neckline)", NearlyEqual(r.boundary_price, 90.0));
      Check("double top extreme_price == 101 (higher peak)", NearlyEqual(r.extreme_price, 101.0));
      Check("double top target == 79 (90 - (101-90))", NearlyEqual(r.target, 79.0));
      Check("double top stop == 100.2 (100 + 2*0.1)", NearlyEqual(r.stop, 100.2));
      Check("double top breakout_index == 1", r.breakout_index == 1);
   }

   //--- 2. Double bottom (mirror) --------------------------------------------
   {
      double highs[]  = {70,70,70,55,55,60,55,55,55,55,55,55,55};
      double lows[]   = {65,65,65,50,65,65,65,49,65,65,65,65,65};
      double closes[] = {62,62,58,55,55,55,55,50,55,55,55,55,55};
      SChartPatternResult r;
      bool ok = CPT_DetectDoubleBottomArray(highs, lows, closes, DEPTH, LOOKBACK, ATR,
                                             PRICE_TOL, PULLBACK_ATR, TREND_BARS,
                                             BREAKOUT_BUF, r);
      Check("double bottom detected", ok && r.found && r.type == CPT_DOUBLE_BOTTOM);
      Check("double bottom boundary_price == 60 (neckline)", NearlyEqual(r.boundary_price, 60.0));
      Check("double bottom extreme_price == 49 (lower trough)", NearlyEqual(r.extreme_price, 49.0));
      Check("double bottom target == 71 (60 + (60-49))", NearlyEqual(r.target, 71.0));
      Check("double bottom stop == 49.8 (50 - 2*0.1)", NearlyEqual(r.stop, 49.8));
      Check("double bottom breakout_index == 1", r.breakout_index == 1);
   }

   //--- 2a. TASK-039: Triple top (natural 3-peak extension of double top) --
   //--- Cross-checked against pattern_validation.py's own hand-verified ----
   //--- test_detect_triple_top_found (identical fixture/expected values). --
   {
      double highs[]  = {100,110,100,90,100,110,100,90,100,110,100,95,90,85};
      double lows[]   = {95,100,95,80,95,100,95,80,95,100,95,85,80,75};
      double closes[] = {98,105,97,85,97,105,97,85,97,105,97,90,85,80};
      SChartPatternResult r;
      bool ok = CPT_DetectTripleTopArray(highs, lows, closes, 1, 5, 2.0, 0.5, 1.0, 2, 0.1, r);
      Check("triple top detected", ok && r.found && r.type == CPT_TRIPLE_TOP);
      Check("triple top boundary_price == 80 (lower of the two troughs)",
            NearlyEqual(r.boundary_price, 80.0));
      Check("triple top extreme_price == 110 (highest peak)", NearlyEqual(r.extreme_price, 110.0));
      Check("triple top target == 50 (80 - (110-80))", NearlyEqual(r.target, 50.0));
      Check("triple top stop == 110.2 (110 + 2*0.1)", NearlyEqual(r.stop, 110.2));
   }

   //--- 2b. TASK-039: Triple bottom (mirror) ---------------------------------
   //--- Cross-checked against pattern_validation.py's own
   //--- test_detect_triple_bottom_found (identical fixture/expected values).
   {
      double highs[]  = {105,100,105,120,105,100,105,120,105,100,105,115,120,125};
      double lows[]   = {100,90,100,110,100,90,100,110,100,90,100,105,110,115};
      double closes[] = {102,95,103,115,103,95,103,115,103,95,103,110,115,120};
      SChartPatternResult r;
      bool ok = CPT_DetectTripleBottomArray(highs, lows, closes, 1, 5, 2.0, 0.5, 1.0, 2, 0.1, r);
      Check("triple bottom detected", ok && r.found && r.type == CPT_TRIPLE_BOTTOM);
      Check("triple bottom boundary_price == 120 (higher of the two peaks)",
            NearlyEqual(r.boundary_price, 120.0));
      Check("triple bottom extreme_price == 90 (lowest trough)",
            NearlyEqual(r.extreme_price, 90.0));
      Check("triple bottom target == 150 (120 + (120-90))", NearlyEqual(r.target, 150.0));
      Check("triple bottom stop == 89.8 (90 - 2*0.1)", NearlyEqual(r.stop, 89.8));
   }

   //--- 3. Head and shoulders (sloped neckline, hand-traced interpolation) -
   {
      double highs[]  = {95,95,95,100,95,95,95,110,95,95,95,101,95,95,95,95,95,95,95,95};
      double lows[]   = {95,95,95,95,95,86,95,95,95,85,95,95,95,95,95,95,95,95,95,95};
      double closes[] = {80,80,80,95,95,95,95,95,95,95,95,95,95,95,85,95,95,95,95,95};
      SChartPatternResult r;
      bool ok = CPT_DetectHeadAndShouldersArray(highs, lows, closes, DEPTH, LOOKBACK, ATR,
                                                 PRICE_TOL, 0.5, PULLBACK_ATR, BREAKOUT_BUF,
                                                 TREND_BARS, r);
      Check("head and shoulders detected", ok && r.found && r.type == CPT_HEAD_SHOULDERS);
      Check("H&S extreme_price == 110 (the head)", NearlyEqual(r.extreme_price, 110.0));
      Check("H&S boundary_price == 86.5 (sloped neckline at RS, hand-interpolated)",
            NearlyEqual(r.boundary_price, 86.5));
      Check("H&S breakout_index == 2", r.breakout_index == 2);
      Check("H&S target == 62.25 (86.75 - (110 - 85.5), hand-interpolated)",
            NearlyEqual(r.target, 62.25));
      Check("H&S stop == 100.2 (100 + 2*0.1)", NearlyEqual(r.stop, 100.2));
   }

   //--- 4. Inverse head and shoulders (mirror) --------------------------------
   {
      double highs[]  = {95,95,115,95,95,109,95,95,95,110,95,95,95,95,95,95,95,95,95,95};
      double lows[]   = {95,95,95,50,95,95,95,40,95,95,95,49,95,95,95,95,95,95,95,95};
      double closes[] = {115,115,115,95,95,95,95,95,95,95,95,95,95,95,105,95,95,95,95,95};
      SChartPatternResult r;
      bool ok = CPT_DetectInverseHeadAndShouldersArray(highs, lows, closes, DEPTH, LOOKBACK,
                                                         ATR, PRICE_TOL, 0.5, PULLBACK_ATR,
                                                         BREAKOUT_BUF, TREND_BARS, r);
      Check("inverse head and shoulders detected",
            ok && r.found && r.type == CPT_INV_HEAD_SHOULDERS);
      Check("inverse H&S extreme_price == 40 (the head)", NearlyEqual(r.extreme_price, 40.0));
      Check("inverse H&S boundary_price == 108.5 (sloped neckline at RS)",
            NearlyEqual(r.boundary_price, 108.5));
      Check("inverse H&S breakout_index == 2", r.breakout_index == 2);
      Check("inverse H&S target == 177.75 (108.25 + (109.5 - 40))",
            NearlyEqual(r.target, 177.75));
      Check("inverse H&S stop == 49.8 (50 - 2*0.1)", NearlyEqual(r.stop, 49.8));
   }

   //--- 5. Retest predicate ---------------------------------------------------
   {
      double closesHold[] = {102,101,100};
      bool holds1;
      bool ran1 = CPT_CheckRetestArray(closesHold, 2, 100.0, true, 1.0, 0.5, 3, holds1);
      Check("retest check runs successfully (holding case)", ran1);
      Check("retest holds when price stays above the failure tolerance", holds1);

      double closesFail[] = {95,101,100};
      bool holds2;
      bool ran2 = CPT_CheckRetestArray(closesFail, 2, 100.0, true, 1.0, 0.5, 3, holds2);
      Check("retest check runs successfully (failing case)", ran2);
      Check("retest fails when a close breaches the failure tolerance", holds2 == false);

      double dummy[] = {100};
      bool holds3;
      Check("retest check rejects a negative touch_index",
            CPT_CheckRetestArray(dummy, -1, 100.0, true, 1.0, 0.5, 3, holds3) == false);
   }

   //--- 6. CMarketData-integrated wrapper against a real symbol --------------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok && md.HasBars(60))
     {
      double rh[], rl[], rc[], ratr;
      bool read_ok = CPT_ReadPatternWindow(md, 40, rh, rl, rc, ratr);
      if(read_ok)
        {
         SChartPatternResult dt, hs;
         bool dt_found = CPT_DetectDoubleTopArray(rh, rl, rc, 3, 30, ratr, 1.0, 1.5, 10, 0.1, dt);
         bool hs_found = CPT_DetectHeadAndShouldersArray(rh, rl, rc, 3, 30, ratr, 1.0, 0.5, 1.0,
                                                           0.1, 10, hs);
         Check("real-symbol chart-pattern checks complete without crashing", true);
         PrintFormat("INFO: real-symbol double_top_found=%s head_shoulders_found=%s",
                     dt_found ? "true" : "false", hs_found ? "true" : "false");
        }
     }
   else
     {
      PrintFormat("NOTE: '%s' does not have enough history — real-symbol "
                  "smoke test skipped.", InpTestSymbol);
     }

   PrintFormat("=== TASK-018 ChartPatternEngine test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
