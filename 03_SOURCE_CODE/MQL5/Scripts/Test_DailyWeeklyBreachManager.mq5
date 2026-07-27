//+------------------------------------------------------------------+
//| Test_DailyWeeklyBreachManager.mq5                                 |
//| Themba Adaptive Intraday Engine — compile/logic test               |
//|                                                                    |
//| **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding    |
//| 6):** DailyWeeklyBreachManager.mqh (added round 8, finding 3) had never        |
//| had dedicated test coverage. Tests 1-2 are pure (no live trading action):       |
//| DWB_IsClosurePending/DWB_SetClosurePending round-trip and the new             |
//| in-memory-fallback fix. Test 3+ would need a real breach/real position          |
//| to exercise DWB_AttemptClosure's own close/cancel behavior for real -- that       |
//| remains part of this project's batched runtime-verification backlog,             |
//| matching every other broker-order-dependent path. A dedicated test-only            |
//| magic (InpTestMagic) is used throughout; every field this script touches           |
//| is cleared at the end.                                                              |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Risk/DailyWeeklyBreachManager.mqh"

input string InpTestSymbol = "EURUSD";
input long   InpTestMagic  = 990099015; // dedicated, unmistakably-test-only

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
   Print("=== DailyWeeklyBreachManager test start ===");

   DWB_SetClosurePending(InpTestSymbol, InpTestMagic, false);
   g_dwb_closure_owed_inmemory = false; // clean slate for the in-memory fallback too

   //--- 1. A fresh instance reports no closure pending ---------------------
   Check("a freshly-reset instance reports closure NOT pending",
         DWB_IsClosurePending(InpTestSymbol, InpTestMagic) == false);

   //--- 2. Set/get round-trip -----------------------------------------------
   bool set_ok = DWB_SetClosurePending(InpTestSymbol, InpTestMagic, true);
   Check("DWB_SetClosurePending(true) reports success", set_ok);
   Check("DWB_IsClosurePending reflects the persisted 'true' value",
         DWB_IsClosurePending(InpTestSymbol, InpTestMagic));
   DWB_SetClosurePending(InpTestSymbol, InpTestMagic, false);
   Check("DWB_IsClosurePending reflects the persisted 'false' value after clearing",
         DWB_IsClosurePending(InpTestSymbol, InpTestMagic) == false);

   //--- 3. **Codex review finding, ninth round, P0 finding 6**: the -------
   //--- in-memory fallback must independently report "pending" even when --
   //--- the persisted GlobalVariable itself says false -- simulating the ---
   //--- exact scenario the review reported: DWB_SetClosurePending(true) ----
   //--- silently failed to persist, but the in-session retry loop must -----
   //--- still keep working via g_dwb_closure_owed_inmemory. -----------------
   DWB_SetClosurePending(InpTestSymbol, InpTestMagic, false); // persisted: false
   g_dwb_closure_owed_inmemory = true;                        // in-memory: owed
   Check("DWB_IsClosurePending reports pending via the in-memory fallback even "
         "though the persisted flag itself says false",
         DWB_IsClosurePending(InpTestSymbol, InpTestMagic));

   //--- 4. Only clearing the in-memory fallback (matching what -------------
   //--- DWB_AttemptClosure does on a CONFIRMED full success) actually ------
   //--- clears the pending report. -----------------------------------------
   g_dwb_closure_owed_inmemory = false;
   Check("clearing the in-memory fallback (with the persisted flag already false) "
         "correctly reports closure NOT pending",
         DWB_IsClosurePending(InpTestSymbol, InpTestMagic) == false);

   //--- Cleanup ---------------------------------------------------------------
   DWB_SetClosurePending(InpTestSymbol, InpTestMagic, false);
   g_dwb_closure_owed_inmemory = false;

   PrintFormat("=== DailyWeeklyBreachManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
