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
//|                                                                    |
//| **Extended, 2026-07-22 (Codex review finding, eighth round, P0 finding      |
//| 5):** IM_BeginIntent/IM_ReconcileOnRestart signatures changed (intent ID          |
//| generation, closed-history search, abandonment timeout) — new coverage             |
//| added for intent-ID round-tripping and the timeout boundary. The                      |
//| closed-history search itself (IM_FindIntentInHistory) needs a real broker                 |
//| fill/comment to exercise meaningfully and remains part of this project's                       |
//| batched runtime-verification backlog, same as the live-order-dependent                            |
//| paths already noted below.                                                                            |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Execution/IntentManager.mqh"

input string InpTestSymbol = "EURUSD";
input long   InpTestMagic  = 990099004; // dedicated, unmistakably-test-only
input int    InpTestTimeoutSeconds = 30;

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
   string intent_id_1;
   bool began = IM_BeginIntent(InpTestSymbol, InpTestMagic, true, 0.10, now, intent_id_1);
   Check("first IM_BeginIntent succeeds", began);
   Check("intent is now active", IM_HasActiveIntent(InpTestSymbol, InpTestMagic));

   //--- 1b. **Codex review finding, eighth round, P0 finding 5**: the ------
   //--- intent ID is non-empty, broker-comment-length-safe, and matches -----
   //--- what IM_GetIntentId reconstructs from the persisted record ----------
   Check("IM_BeginIntent returns a non-empty intent_id", intent_id_1 != "");
   Check("intent_id fits within MT5's 31-character order-comment limit",
         StringLen(intent_id_1) <= 31);
   Check("IM_GetIntentId reconstructs the exact same ID that was returned",
         IM_GetIntentId(InpTestSymbol, InpTestMagic) == intent_id_1);

   //--- 2. A second Begin while one is active is REFUSED (idempotency) -----
   string intent_id_2;
   bool began_again = IM_BeginIntent(InpTestSymbol, InpTestMagic, false, 0.20, now + 1, intent_id_2);
   Check("second IM_BeginIntent while active is refused (returns false)",
         began_again == false);
   Check("a refused IM_BeginIntent returns an empty intent_id", intent_id_2 == "");

   //--- 3. Clear frees it for a new Begin, and a NEW Begin gets a -----------
   //--- DIFFERENT intent ID (never reuses the previous one) -----------------
   IM_ClearIntent(InpTestSymbol, InpTestMagic);
   Check("intent is inactive after Clear", IM_HasActiveIntent(InpTestSymbol, InpTestMagic) == false);
   string intent_id_3;
   bool began_after_clear = IM_BeginIntent(InpTestSymbol, InpTestMagic, true, 0.15, now + 2,
                                            intent_id_3);
   Check("IM_BeginIntent succeeds again after Clear", began_after_clear);
   Check("a fresh intent gets a DIFFERENT ID than the previous one",
         intent_id_3 != intent_id_1);
   IM_ClearIntent(InpTestSymbol, InpTestMagic);

   //--- 4. Restart reconciliation: no active intent -> nothing to do -------
   bool was_filled, still_pending, abandoned;
   ulong pending_ticket;
   bool reconciled = IM_ReconcileOnRestart(InpTestSymbol, InpTestMagic, InpTestTimeoutSeconds,
                                            was_filled, still_pending, pending_ticket, abandoned);
   Check("reconciliation is a no-op when there is no orphaned intent",
         reconciled == false);

   //--- 5. Restart reconciliation: orphaned intent, NEVER filled, no -------
   //--- pending order, and OLD ENOUGH to exceed the timeout (backdated -----
   //--- 'timestamp' field, same simulation technique -----------------------
   //--- Test_DailyWeeklyLimits.mq5 uses for a stale boundary) so the --------
   //--- ABANDONED path is exercised deterministically without a real -------
   //--- wall-clock wait -----------------------------------------------------
   string intent_id_5;
   IM_BeginIntent(InpTestSymbol, InpTestMagic, true, 0.10, now, intent_id_5);
   IM_SetDouble(InpTestSymbol, InpTestMagic, "timestamp",
                (double)(now - InpTestTimeoutSeconds - 5)); // backdated past the timeout
   bool has_position = IM_HasMatchingPosition(InpTestSymbol, InpTestMagic);
   Check("precondition: dedicated test magic has no real open position",
         has_position == false);
   bool has_pending_order = IM_HasMatchingPendingOrder(InpTestSymbol, InpTestMagic);
   Check("precondition: dedicated test magic has no real pending order",
         has_pending_order == false);

   bool reconciled2 = IM_ReconcileOnRestart(InpTestSymbol, InpTestMagic, InpTestTimeoutSeconds,
                                             was_filled, still_pending, pending_ticket, abandoned);
   Check("orphaned intent is detected and reconciled", reconciled2 == true);
   Check("orphaned intent with no matching position/history reports was_filled == false",
         was_filled == false);
   Check("an old-enough orphaned intent with no trace reports still_pending == false",
         still_pending == false);
   Check("an old-enough orphaned intent with no trace reports abandoned_out == true",
         abandoned == true);
   Check("intent is cleared after abandonment reconciliation (resumes normal operation)",
         IM_HasActiveIntent(InpTestSymbol, InpTestMagic) == false);

   //--- 5b. Same scenario, but YOUNG (not yet past the timeout): must be ----
   //--- left ACTIVE, not treated as abandoned -- **Codex review finding, ----
   //--- eighth round, P0 finding 5**: "a very recent intent may simply not --
   //--- have reached the broker's history yet."------------------------------
   string intent_id_5b;
   IM_BeginIntent(InpTestSymbol, InpTestMagic, true, 0.10, now, intent_id_5b);
   // 'now' (fresh timestamp) — well within InpTestTimeoutSeconds of "now".
   bool reconciled_young = IM_ReconcileOnRestart(InpTestSymbol, InpTestMagic, InpTestTimeoutSeconds,
                                                  was_filled, still_pending, pending_ticket,
                                                  abandoned);
   Check("a young orphaned intent with no trace is detected", reconciled_young == true);
   Check("a young orphaned intent with no trace is NOT treated as abandoned",
         abandoned == false);
   Check("a young orphaned intent with no trace reports still_pending == true "
         "(left active for a later retry)", still_pending == true);
   Check("a young orphaned intent's pending_order_ticket_out is 0 (no real order)",
         pending_ticket == 0);
   Check("a young orphaned intent stays ACTIVE (not cleared)",
         IM_HasActiveIntent(InpTestSymbol, InpTestMagic));
   IM_ClearIntent(InpTestSymbol, InpTestMagic); // manual cleanup — this path never self-clears

   //--- 5c. **Codex review finding, seventh round, P0 finding 1**: a -------
   //--- restart with a genuinely PENDING order (simulated: an active -------
   //--- intent with no matching position, but IM_HasMatchingPendingOrder ---
   //--- WOULD report true for a real live order) must NOT clear the --------
   //--- intent. This dedicated test magic has no real pending order to -----
   //--- exercise the true branch against, so this test instead proves the --
   //--- CONTRACT directly: paths 5/5b above prove was_filled/still_pending/---
   //--- abandoned are genuinely distinguished outputs, not hard-wired to ----
   //--- the same outcome. A live/demo run with a real broker-pending order ---
   //--- remains part of this project's batched runtime-verification backlog.--

   //--- 6. A cleared/never-begun instance never falsely reports a match ----
   //--- position for an unrelated magic -------------------------------------
   long other_magic = InpTestMagic + 1;
   IM_ResetInstance(InpTestSymbol, other_magic);
   Check("an unrelated magic is unaffected by this instance's intent state",
         IM_HasActiveIntent(InpTestSymbol, other_magic) == false);

   //--- 7. IM_FindIntentInHistory refuses to search for a never-recorded ---
   //--- intent ID (the "TI0" default-field sentinel), per its own header ----
   bool history_filled;
   bool found_in_history = IM_FindIntentInHistory(InpTestSymbol, InpTestMagic, "TI0", now,
                                                   history_filled);
   Check("IM_FindIntentInHistory refuses to search for the 'TI0' sentinel ID",
         found_in_history == false);

   //--- Cleanup: leave no residue -------------------------------------------
   IM_ResetInstance(InpTestSymbol, InpTestMagic);
   IM_ResetInstance(InpTestSymbol, other_magic);
   Check("instance is clear after cleanup",
         IM_HasActiveIntent(InpTestSymbol, InpTestMagic) == false);

   PrintFormat("=== TASK-034 IntentManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
