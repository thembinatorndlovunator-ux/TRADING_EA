//+------------------------------------------------------------------+
//| Test_PositionStateTracker.mq5                                     |
//| Themba Adaptive Intraday Engine — TASK-041 compile/logic test       |
//|                                                                    |
//| Pure, deterministic, no live trading action — a fabricated,           |
//| unmistakably-test-only position_id is used throughout (never a real     |
//| live position), so this never touches genuine trading state. All        |
//| fields are wiped at the end via PST_Clear.                                |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Execution/PositionStateTracker.mqh"

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
   Print("=== TASK-041 PositionStateTracker test start ===");

   ulong fake_position_id = 990099005001; // unmistakably-test-only, never a real MT5 identifier

   //--- 1. Clean slate --------------------------------------------------
   PST_Clear(fake_position_id);
   SPositionExitState fresh = PST_Load(fake_position_id);
   Check("fresh state: peak_r defaults to 0.0", fresh.peak_r == 0.0);
   Check("fresh state: bars_since_favorable_swing defaults to 0",
         fresh.bars_since_favorable_swing == 0);
   Check("fresh state: break_even_armed defaults to false", fresh.break_even_armed == false);
   Check("fresh state: profit_lock_armed defaults to false", fresh.profit_lock_armed == false);
   Check("fresh state: last_swing_price defaults to 0.0", fresh.last_swing_price == 0.0);
   Check("fresh state: initial_stop_price defaults to 0.0", fresh.initial_stop_price == 0.0);

   //--- 2. Round-trip save/load -------------------------------------------
   SPositionExitState s;
   s.peak_r = 1.75;
   s.bars_since_favorable_swing = 4;
   s.break_even_armed = true;
   s.profit_lock_armed = false;
   s.last_swing_price = 1.23456;
   s.initial_stop_price = 1.20000;
   PST_Save(fake_position_id, s);

   SPositionExitState loaded = PST_Load(fake_position_id);
   Check("round-trip: peak_r", loaded.peak_r == 1.75);
   Check("round-trip: bars_since_favorable_swing", loaded.bars_since_favorable_swing == 4);
   Check("round-trip: break_even_armed", loaded.break_even_armed == true);
   Check("round-trip: profit_lock_armed", loaded.profit_lock_armed == false);
   Check("round-trip: last_swing_price", MathAbs(loaded.last_swing_price - 1.23456) < 0.000001);
   Check("round-trip: initial_stop_price", MathAbs(loaded.initial_stop_price - 1.20000) < 0.000001);

   //--- 3. A different position_id is a completely separate namespace -----
   ulong other_position_id = fake_position_id + 1;
   PST_Clear(other_position_id);
   SPositionExitState other = PST_Load(other_position_id);
   Check("a different position_id is unaffected by the first one's state",
         other.peak_r == 0.0 && other.break_even_armed == false);

   //--- 4. PST_Clear wipes every field, including sticky armed flags ------
   PST_Clear(fake_position_id);
   SPositionExitState cleared = PST_Load(fake_position_id);
   Check("cleared state: peak_r reset to 0.0", cleared.peak_r == 0.0);
   Check("cleared state: break_even_armed reset to false", cleared.break_even_armed == false);
   Check("cleared state: profit_lock_armed reset to false", cleared.profit_lock_armed == false);
   Check("cleared state: last_swing_price reset to 0.0", cleared.last_swing_price == 0.0);
   Check("cleared state: initial_stop_price reset to 0.0", cleared.initial_stop_price == 0.0);

   //--- Cleanup -------------------------------------------------------------
   PST_Clear(fake_position_id);
   PST_Clear(other_position_id);

   PrintFormat("=== TASK-041 PositionStateTracker test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
