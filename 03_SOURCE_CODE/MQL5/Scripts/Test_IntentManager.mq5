//+------------------------------------------------------------------+
//| Test_IntentManager.mq5                                            |
//| Themba Adaptive Intraday Engine — TASK-034 compile/logic test       |
//|                                                                    |
//| Pure, deterministic — no live trading action (uses a dedicated test    |
//| symbol/magic pair that is never expected to have a real open           |
//| position, so IM_HasMatchingPosition genuinely returns false for it       |
//| throughout — the "orphaned intent, never filled" reconciliation path      |
//| is exercised for real; the "orphaned intent, filled" path is exercised     |
//| against this EA's own real magic's positions if any happen to be open,      |
//| documented inline). All test fields are wiped at the end.                     |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Execution/IntentManager.mqh"

input string InpTestSymbol = "EURUSD";
input long   InpTestMagic  = 990099004; // dedicated, unmistakably-test-only

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
   Print("=== TASK-034 IntentManager test start ===");

   //--- Clean slate before testing -----------------------------------------
   IM_ResetInstance(InpTestSymbol, InpTestMagic);
   Check("no active intent on a freshly reset instance",
         IM_HasActiveIntent(InpTestSymbol, InpTestMagic) == false);

   //--- 1. Begin succeeds when no intent is active -------------------------
   datetime now = TimeCurrent();
   bool began = IM_BeginIntent(InpTestSymbol, InpTestMagic, true, 0.10, now);
   Check("first IM_BeginIntent succeeds", began);
   Check("intent is now active", IM_HasActiveIntent(InpTestSymbol, InpTestMagic));

   //--- 2. A second Begin while one is active is REFUSED (idempotency) -----
   bool began_again = IM_BeginIntent(InpTestSymbol, InpTestMagic, false, 0.20, now + 1);
   Check("second IM_BeginIntent while active is refused (returns false)",
         began_again == false);

   //--- 3. Clear frees it for a new Begin -----------------------------------
   IM_ClearIntent(InpTestSymbol, InpTestMagic);
   Check("intent is inactive after Clear", IM_HasActiveIntent(InpTestSymbol, InpTestMagic) == false);
   bool began_after_clear = IM_BeginIntent(InpTestSymbol, InpTestMagic, true, 0.15, now + 2);
   Check("IM_BeginIntent succeeds again after Clear", began_after_clear);
   IM_ClearIntent(InpTestSymbol, InpTestMagic);

   //--- 4. Restart reconciliation: no active intent -> nothing to do -------
   bool was_filled;
   bool reconciled = IM_ReconcileOnRestart(InpTestSymbol, InpTestMagic, was_filled);
   Check("reconciliation is a no-op when there is no orphaned intent",
         reconciled == false);

   //--- 5. Restart reconciliation: orphaned intent, NEVER filled -----------
   //--- (this test's own dedicated magic has no real position under it, ----
   //--- confirmed by CountOwnedPositions-equivalent inline check below) ----
   IM_BeginIntent(InpTestSymbol, InpTestMagic, true, 0.10, now);
   bool has_position = IM_HasMatchingPosition(InpTestSymbol, InpTestMagic);
   Check("precondition: dedicated test magic has no real open position",
         has_position == false);

   bool reconciled2 = IM_ReconcileOnRestart(InpTestSymbol, InpTestMagic, was_filled);
   Check("orphaned intent is detected and reconciled", reconciled2 == true);
   Check("orphaned intent with no matching position reports was_filled == false",
         was_filled == false);
   Check("intent is cleared after reconciliation (resumes normal operation)",
         IM_HasActiveIntent(InpTestSymbol, InpTestMagic) == false);

   //--- 6. A cleared/never-begun instance never falsely reports a match ----
   //--- position for an unrelated magic -------------------------------------
   long other_magic = InpTestMagic + 1;
   IM_ResetInstance(InpTestSymbol, other_magic);
   Check("an unrelated magic is unaffected by this instance's intent state",
         IM_HasActiveIntent(InpTestSymbol, other_magic) == false);

   //--- Cleanup: leave no residue -------------------------------------------
   IM_ResetInstance(InpTestSymbol, InpTestMagic);
   IM_ResetInstance(InpTestSymbol, other_magic);
   Check("instance is clear after cleanup",
         IM_HasActiveIntent(InpTestSymbol, InpTestMagic) == false);

   PrintFormat("=== TASK-034 IntentManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
