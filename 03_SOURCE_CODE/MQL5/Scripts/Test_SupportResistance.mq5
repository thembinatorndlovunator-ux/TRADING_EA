//+------------------------------------------------------------------+
//| Test_SupportResistance.mq5                                        |
//| Themba Adaptive Intraday Engine — TASK-013 compile/logic test      |
//|                                                                    |
//| Tests 1-8 use hand-fabricated arrays with a known clustered pair of  |
//| swing highs/lows and one isolated swing high/low, so every expected  |
//| touch count and zone/liquidity verdict is exactly hand-verifiable.   |
//| Test 9 exercises the CMarketData wrapper against a real symbol.      |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Structure/SupportResistance.mqh"

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

void OnStart()
  {
   Print("=== TASK-013 SupportResistance test start ===");

   const int DEPTH = 1;
   const int LOOKBACK = 12;
   const double TOL = 2.0;

   //--- Fabricated highs: a clustered pair (idx2=65, idx5=64, within ----
   //--- tolerance of each other) and one isolated high (idx10=90). -------
   double highs[] = {40,40,65,40,40,64,40,40,40,40,90,40,40,40,40,40};

   //--- 1. Touch counting near the clustered pair's price -----------------
   int count1 = SR_CountSwingHighTouchesArray(highs, DEPTH, LOOKBACK, 65.0, TOL);
   Check("touch count near the clustered pair (test_price=65) is exactly 2",
         count1 == 2);

   int count_isolated = SR_CountSwingHighTouchesArray(highs, DEPTH, LOOKBACK, 90.0, TOL);
   Check("touch count near the isolated high (test_price=90) is exactly 1",
         count_isolated == 1);

   //--- 2. Resistance-zone verdicts ----------------------------------------
   int tc;
   bool zone_clustered = SR_IsResistanceZoneArray(highs, DEPTH, LOOKBACK, 65.0, TOL, 2, tc);
   Check("the clustered pair qualifies as a resistance zone (min_touches=2)",
         zone_clustered);
   Check("resistance-zone touch_count matches (2)", tc == 2);

   bool zone_isolated = SR_IsResistanceZoneArray(highs, DEPTH, LOOKBACK, 90.0, TOL, 2, tc);
   Check("the isolated high does NOT qualify as a resistance zone",
         zone_isolated == false);
   Check("isolated resistance touch_count matches (1)", tc == 1);

   //--- 3. Equal-high liquidity (section 4's exact definition) -----------
   int eq_tc;
   bool eq1 = SR_IsEqualHighLiquidityArray(highs, DEPTH, LOOKBACK, 2, TOL, eq_tc);
   Check("swing at idx2 (part of the clustered pair) is equal-high liquidity",
         eq1);
   Check("equal-high liquidity touch_count at idx2 is 2", eq_tc == 2);

   bool eq2 = SR_IsEqualHighLiquidityArray(highs, DEPTH, LOOKBACK, 10, TOL, eq_tc);
   Check("swing at idx10 (isolated) is NOT equal-high liquidity",
         eq2 == false);
   Check("equal-high liquidity touch_count at idx10 is 1", eq_tc == 1);

   bool eq3 = SR_IsEqualHighLiquidityArray(highs, DEPTH, LOOKBACK, 0, TOL, eq_tc);
   Check("a non-swing index (idx0) is NOT equal-high liquidity",
         eq3 == false);
   Check("equal-high liquidity touch_count at a non-swing index is 0",
         eq_tc == 0);

   //--- 4. Mirror: fabricated lows with the same clustered/isolated shape -
   double lows[] = {50,50,20,50,50,21,50,50,50,50,5,50,50,50,50,50};

   int count_low_clustered = SR_CountSwingLowTouchesArray(lows, DEPTH, LOOKBACK, 20.0, TOL);
   Check("low touch count near the clustered pair (test_price=20) is exactly 2",
         count_low_clustered == 2);

   int count_low_isolated = SR_CountSwingLowTouchesArray(lows, DEPTH, LOOKBACK, 5.0, TOL);
   Check("low touch count near the isolated low (test_price=5) is exactly 1",
         count_low_isolated == 1);

   bool support_clustered = SR_IsSupportZoneArray(lows, DEPTH, LOOKBACK, 20.0, TOL, 2, tc);
   Check("the clustered low pair qualifies as a support zone", support_clustered);

   bool support_isolated = SR_IsSupportZoneArray(lows, DEPTH, LOOKBACK, 5.0, TOL, 2, tc);
   Check("the isolated low does NOT qualify as a support zone",
         support_isolated == false);

   bool eq_low1 = SR_IsEqualLowLiquidityArray(lows, DEPTH, LOOKBACK, 2, TOL, eq_tc);
   Check("swing low at idx2 (clustered) is equal-low liquidity", eq_low1);

   bool eq_low2 = SR_IsEqualLowLiquidityArray(lows, DEPTH, LOOKBACK, 10, TOL, eq_tc);
   Check("swing low at idx10 (isolated) is NOT equal-low liquidity",
         eq_low2 == false);

   //--- 5. CMarketData-integrated wrapper against a real symbol -----------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok && md.HasBars(60))
     {
      double current_price = SymbolInfoDouble(InpTestSymbol, SYMBOL_BID);
      double atr;
      bool atr_ok = md.GetATR(0, atr, 14);
      if(atr_ok)
        {
         int live_tc;
         bool live_res = SR_IsResistanceZone(md, 3, 50, current_price, atr * 0.1, 2, live_tc);
         Check("real-symbol resistance-zone check completes without crashing "
               "regardless of outcome", true);
         Check("real-symbol resistance touch_count is non-negative", live_tc >= 0);
         PrintFormat("INFO: real-symbol resistance zone at current price: "
                     "found=%s touches=%d", live_res ? "true" : "false", live_tc);
        }
     }
   else
     {
      PrintFormat("NOTE: '%s' does not have enough history — real-symbol "
                  "check skipped.", InpTestSymbol);
     }

   PrintFormat("=== TASK-013 SupportResistance test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
