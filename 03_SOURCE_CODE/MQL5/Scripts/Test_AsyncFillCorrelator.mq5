//+------------------------------------------------------------------+
//| Test_AsyncFillCorrelator.mq5                                      |
//| Themba Adaptive Intraday Engine — TASK-036 compile/logic test       |
//|                                                                    |
//| Pure, deterministic, no live trading action — exercises the pending    |
//| async-fill-correlation store directly. Cleared at the start and end     |
//| so a real run leaves no residue (the store is in-memory/session-           |
//| scoped, per AsyncFillCorrelator.mqh's own header, but a residual              |
//| entry could otherwise linger for the rest of THIS script run).                  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Execution/AsyncFillCorrelator.mqh"

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
   Print("=== TASK-036 AsyncFillCorrelator test start ===");

   AFC_ClearAllPending();
   Check("clean slate: no pending records", AFC_PendingCount() == 0);

   //--- 1. Add + find round trip -------------------------------------------
   AFC_AddPending(1001, "SIGNAL_A");
   Check("one pending record after adding one", AFC_PendingCount() == 1);

   string found_signal_id;
   int found_index;
   bool found = AFC_FindPending(1001, found_signal_id, found_index);
   Check("finds the pending record by order ticket", found);
   Check("found record carries the correct signal_id", found_signal_id == "SIGNAL_A");
   Check("found record's index is 0", found_index == 0);

   //--- 2. A different order ticket is NOT found ---------------------------
   string not_found_signal_id;
   int not_found_index;
   Check("an unrelated order ticket is not found",
         AFC_FindPending(9999, not_found_signal_id, not_found_index) == false);

   //--- 3. Multiple pending records coexist independently ------------------
   AFC_AddPending(1002, "SIGNAL_B");
   AFC_AddPending(1003, "SIGNAL_C");
   Check("three pending records after adding three total", AFC_PendingCount() == 3);

   string sig_b;
   int idx_b;
   Check("SIGNAL_B is found under its own order ticket",
         AFC_FindPending(1002, sig_b, idx_b) && sig_b == "SIGNAL_B");
   string sig_c;
   int idx_c;
   Check("SIGNAL_C is found under its own order ticket",
         AFC_FindPending(1003, sig_c, idx_c) && sig_c == "SIGNAL_C");

   //--- 4. Removing one record does not disturb the others -----------------
   AFC_RemovePending(idx_b);
   Check("two pending records remain after removing one", AFC_PendingCount() == 2);
   string sig_a_after, sig_c_after;
   int idx_a_after, idx_c_after;
   Check("SIGNAL_A is still found after removing SIGNAL_B",
         AFC_FindPending(1001, sig_a_after, idx_a_after) && sig_a_after == "SIGNAL_A");
   Check("SIGNAL_C is still found after removing SIGNAL_B",
         AFC_FindPending(1003, sig_c_after, idx_c_after) && sig_c_after == "SIGNAL_C");
   Check("SIGNAL_B is no longer found after removal",
         AFC_FindPending(1002, sig_b, idx_b) == false);

   //--- Cleanup -------------------------------------------------------------
   AFC_ClearAllPending();
   Check("no pending records remain after cleanup", AFC_PendingCount() == 0);

   PrintFormat("=== TASK-036 AsyncFillCorrelator test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
