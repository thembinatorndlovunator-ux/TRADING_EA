//+------------------------------------------------------------------+
//| Test_ICTSMCGeometry.mq5                                           |
//| Themba Adaptive Intraday Engine — TASK-015 compile/logic test      |
//|                                                                    |
//| Hand-fabricated arrays throughout, each chosen so the expected       |
//| result is exactly hand-derivable from section 4's formulas — no      |
//| live data involved except the final smoke test.                      |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Structure/ICTSMCGeometry.mqh"

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
   Print("=== TASK-015 ICTSMCGeometry test start ===");

   //--- 1. Bullish FVG: low[0]=105 > high[2]=100 -------------------------
   {
      double highs[] = {110,103,100};
      double lows[]  = {105,98,95};
      SFvgZone z;
      bool ok = ICT_GetFvgZoneArray(highs, lows, 0, z);
      Check("bullish FVG detected", ok && z.type == FVG_BULLISH);
      Check("bullish FVG zone_low == 100 (high of the older candle)",
            NearlyEqual(z.zone_low, 100.0));
      Check("bullish FVG zone_high == 105 (low of the newer candle)",
            NearlyEqual(z.zone_high, 105.0));
      Check("50%% fill level == 102.5", NearlyEqual(ICT_FvgFiftyPercentLevel(z), 102.5));
      Check("price 102 (inside the zone) is reported as inside the FVG",
            ICT_IsPriceInFvg(z, 102.0));
      Check("close 99 (below zone_low) invalidates a bullish FVG",
            ICT_IsFvgInvalidated(z, 99.0));
      Check("close 102 (inside the zone) does NOT invalidate a bullish FVG",
            ICT_IsFvgInvalidated(z, 102.0) == false);
   }

   //--- 2. Bearish FVG: high[0]=95 < low[2]=100 ---------------------------
   {
      double highs[] = {95,102,105};
      double lows[]  = {90,97,100};
      SFvgZone z;
      bool ok = ICT_GetFvgZoneArray(highs, lows, 0, z);
      Check("bearish FVG detected", ok && z.type == FVG_BEARISH);
      Check("bearish FVG zone_low == 95", NearlyEqual(z.zone_low, 95.0));
      Check("bearish FVG zone_high == 100", NearlyEqual(z.zone_high, 100.0));
   }

   //--- 3. No FVG when ranges overlap -------------------------------------
   {
      double highs[] = {105,103,100};
      double lows[]  = {98,97,95};
      SFvgZone z;
      bool ok = ICT_GetFvgZoneArray(highs, lows, 0, z);
      Check("overlapping ranges produce no FVG", ok == false && z.type == FVG_NONE);
   }

   //--- 4. Bullish order block: bullish Marubozu displacement at k=0, ----
   //---    bearish OB candle at k+1 ----------------------------------------
   {
      double opens[]  = {100,105};
      double highs[]  = {110,106};
      double lows[]   = {100,99};
      double closes[] = {110,100};
      double atr[]    = {5,5};
      ENUM_OB_TYPE type; double zh, zl; int obi;
      bool ok = ICT_DetectOrderBlockArray(opens, highs, lows, closes, atr, 0, 1.5,
                                           type, zh, zl, obi);
      Check("bullish order block detected", ok && type == OB_BULLISH);
      Check("order block zone_high == 106", NearlyEqual(zh, 106.0));
      Check("order block zone_low == 99", NearlyEqual(zl, 99.0));
      Check("order block index == 1", obi == 1);
      Check("a close at 98 (below zone_low) invalidates the bullish order block",
            ICT_IsOrderBlockInvalidated(type, zh, zl, 98.0));
      Check("a close at 102 (inside the zone) does NOT invalidate it",
            ICT_IsOrderBlockInvalidated(type, zh, zl, 102.0) == false);
   }

   //--- 5. No order block when the displacement candle is not a Marubozu -
   {
      double opens[]  = {100,105};
      double highs[]  = {103,106};   // small body, not a Marubozu
      double lows[]   = {99,99};
      double closes[] = {101,100};
      double atr[]    = {5,5};
      ENUM_OB_TYPE type; double zh, zl; int obi;
      bool ok = ICT_DetectOrderBlockArray(opens, highs, lows, closes, atr, 0, 1.5,
                                           type, zh, zl, obi);
      Check("no order block when the reference candle is not a displacement Marubozu",
            ok == false && type == OB_NONE);
   }

   //--- 6. Liquidity sweep: buy-side (high) swept, single-bar reject ------
   //---    n=20, pool idx4..14 (peak 60 at idx6), shift idx2..5, wick at ---
   //---    idx3=65 sweeping above 60, closing back to 55 same bar. --------
   {
      double highs[20], lows[20], closes[20];
      for(int i = 0; i < 20; i++) { highs[i] = 50; lows[i] = 40; closes[i] = 50; }
      highs[6] = 60;   // pool peak
      highs[3] = 65;   // shift-window sweep wick
      closes[3] = 55;  // confirmation: closes back below the pool peak

      SSweepResult r;
      bool found = ICT_DetectSweepArray(highs, lows, closes, 3, 3, r);
      Check("buy-side liquidity sweep detected", found && r.found);
      Check("sweep direction is bearish (swept a high)", r.is_bullish == false);
      Check("swept_level == 60", NearlyEqual(r.swept_level, 60.0));
      Check("sweep_bar_index == 3", r.sweep_bar_index == 3);
      Check("confirmation_bar_index == 3 (same-bar reject)", r.confirmation_bar_index == 3);
   }

   //--- 7. Liquidity sweep: sell-side (low) swept --------------------------
   {
      double highs[20], lows[20], closes[20];
      for(int i = 0; i < 20; i++) { highs[i] = 60; lows[i] = 40; closes[i] = 50; }
      lows[6] = 30;    // pool trough
      lows[3] = 25;    // shift-window sweep wick
      closes[3] = 35;  // confirmation: closes back above the pool trough

      SSweepResult r;
      bool found = ICT_DetectSweepArray(highs, lows, closes, 3, 3, r);
      Check("sell-side liquidity sweep detected", found && r.found);
      Check("sweep direction is bullish (swept a low)", r.is_bullish);
      Check("swept_level == 30", NearlyEqual(r.swept_level, 30.0));
   }

   //--- 8. No sweep when nothing exceeds the pool extremes -----------------
   {
      double highs[20], lows[20], closes[20];
      for(int i = 0; i < 20; i++) { highs[i] = 50; lows[i] = 40; closes[i] = 45; }
      SSweepResult r;
      bool found = ICT_DetectSweepArray(highs, lows, closes, 3, 3, r);
      Check("flat data produces no sweep", found == false && r.found == false);
   }

   //--- 9. Final-stop transformation chain: pass-through, floor, cap ------
   {
      double dist; bool rejected;
      bool ok1 = ICT_ComputeSweepStopDistance(10.0, 1.0, 0.3, 2.0, 10.0, dist, rejected);
      Check("stop distance pass-through: 10*0.3+1=4, within [2,10]", ok1 && !rejected);
      Check("pass-through stop_distance == 4.0", NearlyEqual(dist, 4.0));

      bool ok2 = ICT_ComputeSweepStopDistance(1.0, 0.1, 0.3, 5.0, 10.0, dist, rejected);
      Check("stop distance below floor is widened to the floor", ok2 && !rejected);
      Check("widened stop_distance == 5.0 (the floor)", NearlyEqual(dist, 5.0));

      bool ok3 = ICT_ComputeSweepStopDistance(100.0, 1.0, 0.3, 2.0, 10.0, dist, rejected);
      Check("stop distance above the cap is REJECTED (not clamped)",
            ok3 == false && rejected);
   }

   //--- 10. Premium / discount classification ------------------------------
   Check("price above equilibrium classifies as PREMIUM",
         ICT_ClassifyPremiumDiscount(105.0, 100.0) == PD_PREMIUM);
   Check("price below equilibrium classifies as DISCOUNT",
         ICT_ClassifyPremiumDiscount(95.0, 100.0) == PD_DISCOUNT);
   Check("price at equilibrium classifies as EQUILIBRIUM",
         ICT_ClassifyPremiumDiscount(100.0, 100.0) == PD_EQUILIBRIUM);

   //--- 11. CMarketData smoke test against a real symbol -------------------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok && md.HasBars(60))
     {
      double ro[], rh[], rl[], rc[], ratr[];
      bool read_ok = CP_ReadWindow(md, 40, ro, rh, rl, rc) &&
                      CP_ReadAtrWindow(md, 40, 14, ratr);
      if(read_ok)
        {
         SFvgZone z; bool fvg_found = ICT_GetFvgZoneArray(rh, rl, 0, z);
         SSweepResult sr; bool sweep_found = ICT_DetectSweepArray(rh, rl, rc, 30, 6, sr);
         Check("real-symbol FVG/sweep checks complete without crashing", true);
         PrintFormat("INFO: real-symbol fvg_found=%s sweep_found=%s",
                     fvg_found ? "true" : "false", sweep_found ? "true" : "false");
        }
     }
   else
     {
      PrintFormat("NOTE: '%s' does not have enough history — real-symbol "
                  "smoke test skipped.", InpTestSymbol);
     }

   PrintFormat("=== TASK-015 ICTSMCGeometry test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
