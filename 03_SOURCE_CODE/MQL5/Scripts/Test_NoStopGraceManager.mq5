//+------------------------------------------------------------------+
//| Test_NoStopGraceManager.mq5                                       |
//| Themba Adaptive Intraday Engine — compile/logic test               |
//|                                                                    |
//| **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding    |
//| 6):** NoStopGraceManager.mqh (added round 8, finding 3) had never had          |
//| dedicated test coverage. Pure, deterministic, no live trading action --        |
//| exercises the persisted first-seen tracker AND its new in-memory              |
//| fallback directly against fabricated position_id values. All test             |
//| fields are cleared at the end so a real run leaves no residue.                |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Risk/NoStopGraceManager.mqh"

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
   Print("=== NoStopGraceManager test start ===");

   ulong pos_a = 990099014001;
   ulong pos_b = 990099014002;

   NSG_Clear(pos_a);
   NSG_Clear(pos_b);

   //--- 1. A never-tracked position reports 0 (not currently tracked) -----
   Check("a never-tracked position's first-seen is 0", NSG_GetFirstSeen(pos_a) == 0);

   //--- 2. Set/get round-trip --------------------------------------------
   datetime t1 = TimeCurrent();
   bool set_ok = NSG_SetFirstSeen(pos_a, t1);
   Check("NSG_SetFirstSeen reports success", set_ok);
   Check("NSG_GetFirstSeen returns the exact value just set", NSG_GetFirstSeen(pos_a) == t1);

   //--- 3. An unrelated position is unaffected ----------------------------
   Check("an unrelated position is unaffected", NSG_GetFirstSeen(pos_b) == 0);

   //--- 4. Clear un-tracks it ----------------------------------------------
   NSG_Clear(pos_a);
   Check("NSG_Clear un-tracks the position", NSG_GetFirstSeen(pos_a) == 0);

   //--- 5. **Codex review finding, ninth round, P0 finding 6**: the -------
   //--- in-memory fallback must be authoritative even if the PERSISTED ----
   //--- GlobalVariable itself is deleted out from under it directly -------
   //--- (simulating "the persisted write silently failed / was lost") -----
   //--- -- NSG_GetFirstSeen must still return the in-memory value, not 0, -
   //--- which is exactly what closes the review's "every tick looks like -
   //--- the first observation" defect. ------------------------------------
   datetime t2 = TimeCurrent() - 100;
   NSG_SetFirstSeen(pos_a, t2);
   // Directly delete the persisted GlobalVariable, simulating a scenario
   // where the persisted write never actually landed (or was lost) while
   // the in-memory fallback still correctly remembers it.
   string persisted_key = NSG_Key(pos_a);
   if(GlobalVariableCheck(persisted_key))
      GlobalVariableDel(persisted_key);
   Check("NSG_GetFirstSeen still returns the correct value from the in-memory fallback "
         "even after the persisted GlobalVariable is gone",
         NSG_GetFirstSeen(pos_a) == t2);

   //--- 6. Clearing removes BOTH the in-memory and persisted state --------
   NSG_SetFirstSeen(pos_a, TimeCurrent());
   NSG_Clear(pos_a);
   Check("NSG_Clear removes the in-memory fallback too (not just the persisted key)",
         NSG_GetFirstSeen(pos_a) == 0);

   //--- Cleanup -------------------------------------------------------------
   NSG_Clear(pos_a);
   NSG_Clear(pos_b);

   PrintFormat("=== NoStopGraceManager test complete: %d passed, %d failed ===", g_pass, g_fail);
  }
