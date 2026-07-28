//+------------------------------------------------------------------+
//| Test_AsyncFillCorrelator.mq5                                      |
//| Themba Adaptive Intraday Engine — TASK-036 compile/logic test       |
//|                                                                    |
//| Pure, deterministic, no live trading action — exercises the pending    |
//| async-fill-correlation store directly. Cleared at the start and end     |
//| so a real run leaves no residue (the store is in-memory/session-           |
//| scoped, per AsyncFillCorrelator.mqh's own header, but a residual              |
//| entry could otherwise linger for the rest of THIS script run).                  |
//|                                                                    |
//| **Extended, 2026-07-28 (Codex review finding, tenth round, P0 finding    |
//| 2):** AFC_AddPending/AFC_FindPending now also carry                              |
//| RiskReservationManager.mqh's own unique reservation key alongside each             |
//| pending record (see that module's own header for why a bare symbol+magic              |
//| release is no longer safe) -- new coverage added for that field's own                    |
//| round-trip.                                                                                   |
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

   //--- 1. Add + find round trip, including the reservation key ------------
   AFC_AddPending(1001, "SIGNAL_A", "RESV_KEY_A");
   Check("one pending record after adding one", AFC_PendingCount() == 1);

   string found_signal_id;
   int found_index;
   string found_reservation_key;
   bool found = AFC_FindPending(1001, found_signal_id, found_index, found_reservation_key);
   Check("finds the pending record by order ticket", found);
   Check("found record carries the correct signal_id", found_signal_id == "SIGNAL_A");
   Check("found record carries the correct reservation_key", found_reservation_key == "RESV_KEY_A");
   Check("found record's index is 0", found_index == 0);

   //--- 1b. reservation_key defaults to empty when omitted ------------------
   AFC_AddPending(1004, "SIGNAL_D");
   string sig_d, resv_d;
   int idx_d;
   Check("omitted reservation_key defaults to an empty string",
         AFC_FindPending(1004, sig_d, idx_d, resv_d) && resv_d == "");
   AFC_RemovePending(idx_d);

   //--- 2. A different order ticket is NOT found ---------------------------
   string not_found_signal_id, not_found_reservation_key;
   int not_found_index;
   Check("an unrelated order ticket is not found",
         AFC_FindPending(9999, not_found_signal_id, not_found_index,
                          not_found_reservation_key) == false);

   //--- 3. Multiple pending records coexist independently ------------------
   AFC_AddPending(1002, "SIGNAL_B", "RESV_KEY_B");
   AFC_AddPending(1003, "SIGNAL_C", "RESV_KEY_C");
   Check("three pending records after adding three total", AFC_PendingCount() == 3);

   string sig_b, resv_b;
   int idx_b;
   Check("SIGNAL_B is found under its own order ticket with its own reservation key",
         AFC_FindPending(1002, sig_b, idx_b, resv_b) && sig_b == "SIGNAL_B" &&
         resv_b == "RESV_KEY_B");
   string sig_c, resv_c;
   int idx_c;
   Check("SIGNAL_C is found under its own order ticket with its own reservation key",
         AFC_FindPending(1003, sig_c, idx_c, resv_c) && sig_c == "SIGNAL_C" &&
         resv_c == "RESV_KEY_C");

   //--- 4. Removing one record does not disturb the others (including ------
   //---    their own reservation keys) --------------------------------------
   AFC_RemovePending(idx_b);
   Check("two pending records remain after removing one", AFC_PendingCount() == 2);
   string sig_a_after, resv_a_after;
   int idx_a_after;
   string sig_c_after, resv_c_after;
   int idx_c_after;
   Check("SIGNAL_A is still found after removing SIGNAL_B, with its own reservation key intact",
         AFC_FindPending(1001, sig_a_after, idx_a_after, resv_a_after) &&
         sig_a_after == "SIGNAL_A" && resv_a_after == "RESV_KEY_A");
   Check("SIGNAL_C is still found after removing SIGNAL_B, with its own reservation key intact",
         AFC_FindPending(1003, sig_c_after, idx_c_after, resv_c_after) &&
         sig_c_after == "SIGNAL_C" && resv_c_after == "RESV_KEY_C");
   Check("SIGNAL_B is no longer found after removal",
         AFC_FindPending(1002, sig_b, idx_b, resv_b) == false);

   //--- Cleanup -------------------------------------------------------------
   AFC_ClearAllPending();
   Check("no pending records remain after cleanup", AFC_PendingCount() == 0);

   PrintFormat("=== TASK-036 AsyncFillCorrelator test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
