//+------------------------------------------------------------------+
//| Test_ExitManager.mq5                                              |
//| Themba Adaptive Intraday Engine — TASK-030 compile/logic test      |
//|                                                                    |
//| Every test uses hand-fabricated inputs so every expected result is   |
//| hand-derivable — pure, deterministic, no live-symbol dependency        |
//| anywhere in this file (matching ExitManager.mqh's own pure-function     |
//| nature).                                                                |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Execution/ExitManager.mqh"

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
   Print("=== TASK-030 ExitManager test start ===");

   //--- 1. EM_ComputeR ----------------------------------------------------
   Check("long R: entry 100, stop 98 (risk 2), price 101 -> R=0.5",
         NearlyEqual(EM_ComputeR(true, 100.0, 98.0, 101.0), 0.5));
   Check("short R: entry 100, stop 102 (risk 2), price 99 -> R=0.5",
         NearlyEqual(EM_ComputeR(false, 100.0, 102.0, 99.0), 0.5));
   Check("zero/negative risk distance -> R=0.0 (fail-safe, no divide-by-zero)",
         NearlyEqual(EM_ComputeR(true, 100.0, 100.0, 105.0), 0.0));

   //--- 2. EM_HasFavorableSwingBeyondEntry (depth=1, max_lookback=3) ------
   double lows[];  ArrayResize(lows, 6);
   lows[0]=10; lows[1]=9; lows[2]=5; lows[3]=9; lows[4]=10; lows[5]=11;
   double highs[]; ArrayResize(highs, 6);
   highs[0]=1; highs[1]=2; highs[2]=6; highs[3]=2; highs[4]=1; highs[5]=0;

   double swing_price;
   bool long_favorable_yes = EM_HasFavorableSwingBeyondEntry(true, 4.0, highs, lows, 1, 3, swing_price);
   Check("long: confirmed swing low (5.0) found and beyond entry (4.0) -> favorable",
         long_favorable_yes && NearlyEqual(swing_price, 5.0));

   bool long_favorable_no = EM_HasFavorableSwingBeyondEntry(true, 6.0, highs, lows, 1, 3, swing_price);
   Check("long: confirmed swing low (5.0) found but NOT beyond entry (6.0) -> not favorable",
         long_favorable_no == false);

   bool short_favorable_yes = EM_HasFavorableSwingBeyondEntry(false, 7.0, highs, lows, 1, 3, swing_price);
   Check("short: confirmed swing high (6.0) found and beyond entry (7.0) -> favorable",
         short_favorable_yes && NearlyEqual(swing_price, 6.0));

   bool short_favorable_no = EM_HasFavorableSwingBeyondEntry(false, 5.0, highs, lows, 1, 3, swing_price);
   Check("short: confirmed swing high (6.0) found but NOT beyond entry (5.0) -> not favorable",
         short_favorable_no == false);

   //--- 3. EM_ShouldArmBreakEven -------------------------------------------
   Check("break-even arms: favorable swing + R >= min_r",
         EM_ShouldArmBreakEven(true, 0.6, 0.5));
   Check("break-even does NOT arm: favorable swing but R < min_r",
         EM_ShouldArmBreakEven(true, 0.4, 0.5) == false);
   Check("break-even does NOT arm: R sufficient but no favorable swing",
         EM_ShouldArmBreakEven(false, 0.9, 0.5) == false);

   //--- 4. EM_ComputeStructureTrailStop -------------------------------------
   Check("long structure trail: swing 100, ATR 2, buffer 0.3 -> 99.4",
         NearlyEqual(EM_ComputeStructureTrailStop(true, 100.0, 2.0, 0.3), 99.4));
   Check("short structure trail: swing 100, ATR 2, buffer 0.3 -> 100.6",
         NearlyEqual(EM_ComputeStructureTrailStop(false, 100.0, 2.0, 0.3), 100.6));

   //--- 5. EM_ComputeAtrFallbackTrailStop ------------------------------------
   Check("long ATR fallback: price 100, ATR 2, multiple 2.0 -> 96",
         NearlyEqual(EM_ComputeAtrFallbackTrailStop(true, 100.0, 2.0, 2.0), 96.0));
   Check("short ATR fallback: price 100, ATR 2, multiple 2.0 -> 104",
         NearlyEqual(EM_ComputeAtrFallbackTrailStop(false, 100.0, 2.0, 2.0), 104.0));

   //--- 6. EM_ApplyTrailNeverWiden -------------------------------------------
   Check("long: a TIGHTER candidate (99.4 > 99) is accepted",
         NearlyEqual(EM_ApplyTrailNeverWiden(true, 99.0, 99.4), 99.4));
   Check("long: a WIDER candidate (98 < 99) is REJECTED, current stop kept",
         NearlyEqual(EM_ApplyTrailNeverWiden(true, 99.0, 98.0), 99.0));
   Check("short: a TIGHTER candidate (100.6 < 101) is accepted",
         NearlyEqual(EM_ApplyTrailNeverWiden(false, 101.0, 100.6), 100.6));
   Check("short: a WIDER candidate (102 > 101) is REJECTED, current stop kept",
         NearlyEqual(EM_ApplyTrailNeverWiden(false, 101.0, 102.0), 101.0));

   //--- 7. EM_IsTrailStale ---------------------------------------------------
   Check("5 bars since last favorable swing, threshold 5 -> stale",
         EM_IsTrailStale(5, 5));
   Check("4 bars since last favorable swing, threshold 5 -> NOT stale",
         EM_IsTrailStale(4, 5) == false);

   //--- 8. EM_IsTimeStopDurationExceeded -------------------------------------
   Check("scalp mode: elapsed 61min >= max 60min -> exceeded",
         EM_IsTimeStopDurationExceeded(true, 61.0, 0.0, 60.0));
   Check("scalp mode: elapsed 59min < max 60min -> NOT exceeded",
         EM_IsTimeStopDurationExceeded(true, 59.0, 0.0, 60.0) == false);
   Check("day-trade mode: remaining_ratio 0.0 -> exceeded",
         EM_IsTimeStopDurationExceeded(false, 0.0, 0.0, 60.0));
   Check("day-trade mode: remaining_ratio 0.01 -> NOT exceeded",
         EM_IsTimeStopDurationExceeded(false, 0.0, 0.01, 60.0) == false);

   //--- 9. EM_ShouldTimeStop (all three conditions required) -----------------
   Check("time stop fires: duration exceeded + low R + stale",
         EM_ShouldTimeStop(true, 61.0, 0.0, 60.0, 0.2, 0.3, true));
   Check("time stop does NOT fire: duration NOT exceeded",
         EM_ShouldTimeStop(true, 30.0, 0.0, 60.0, 0.2, 0.3, true) == false);
   Check("time stop does NOT fire: R already sufficient",
         EM_ShouldTimeStop(true, 61.0, 0.0, 60.0, 0.5, 0.3, true) == false);
   Check("time stop does NOT fire: not stale (fresh favorable swing)",
         EM_ShouldTimeStop(true, 61.0, 0.0, 60.0, 0.2, 0.3, false) == false);

   //--- 10. EM_ShouldArmProfitLock -------------------------------------------
   Check("profit lock arms: 70% of entry-to-target distance covered",
         EM_ShouldArmProfitLock(true, 100.0, 110.0, 107.0, 70.0));
   Check("profit lock does NOT arm: only 60% covered",
         EM_ShouldArmProfitLock(true, 100.0, 110.0, 106.0, 70.0) == false);

   //--- 11. EM_ComputeProfitLockStop -----------------------------------------
   Check("profit lock stop: entry 100, price 107 (gain 7), keep 50% -> 103.5",
         NearlyEqual(EM_ComputeProfitLockStop(true, 100.0, 107.0, 50.0), 103.5));

   //--- 12. EM_ProfitLockClearsMinFloor ---------------------------------------
   Check("actual lock of 50% clears a 30% floor",
         EM_ProfitLockClearsMinFloor(true, 100.0, 107.0, 103.5, 30.0));
   Check("actual lock of ~14% does NOT clear a 30% floor (partial-lock case)",
         EM_ProfitLockClearsMinFloor(true, 100.0, 107.0, 101.0, 30.0) == false);

   //--- 13. EM_ShouldGivebackCloseV637 ----------------------------------------
   Check("V637 giveback: armed (peak 2.0R >= 1.25R), current 0.7R <= trigger 0.8R -> close",
         EM_ShouldGivebackCloseV637(0.7, 2.0, 1.25, 60.0, 0.05));
   Check("V637 giveback: armed, current 0.9R > trigger 0.8R -> no close",
         EM_ShouldGivebackCloseV637(0.9, 2.0, 1.25, 60.0, 0.05) == false);
   Check("V637 giveback: not yet armed (peak 1.0R < 1.25R) -> no close regardless",
         EM_ShouldGivebackCloseV637(0.1, 1.0, 1.25, 60.0, 0.05) == false);
   Check("V637 giveback: close-trigger floor overrides a lower percentage-based trigger",
         EM_ShouldGivebackCloseV637(0.9, 2.0, 1.25, 60.0, 1.0)); // raw trigger 0.8 -> floored to 1.0

   //--- 14. EM_ShouldGivebackCloseV811 ----------------------------------------
   Check("V811 giveback: armed (peak 1.0R >= 0.3R), current 0.1R <= floor 0.1R -> close",
         EM_ShouldGivebackCloseV811(0.1, 1.0, 0.3, 0.1));
   Check("V811 giveback: armed, current 0.15R > floor 0.1R -> no close",
         EM_ShouldGivebackCloseV811(0.15, 1.0, 0.3, 0.1) == false);
   Check("V811 giveback: not yet armed (peak 0.2R < 0.3R) -> no close regardless",
         EM_ShouldGivebackCloseV811(0.05, 0.2, 0.3, 0.1) == false);

   PrintFormat("=== TASK-030 ExitManager test complete: %d passed, %d failed ===", g_pass, g_fail);
  }
