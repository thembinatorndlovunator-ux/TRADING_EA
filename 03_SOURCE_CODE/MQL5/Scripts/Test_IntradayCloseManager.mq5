//+------------------------------------------------------------------+
//| Test_IntradayCloseManager.mq5                                     |
//| Themba Adaptive Intraday Engine — TASK-010 compile/logic test      |
//|                                                                    |
//| *** THIS SCRIPT PLACES REAL (MINIMAL-VOLUME) ORDERS ***             |
//| Unlike every other TASK-003..009 test script (which only touch a   |
//| test-scoped StateManager field or a throwaway journal file), this   |
//| one actually opens a minimum-volume market position and a far-away  |
//| pending order under a dedicated, unmistakably-test-only magic        |
//| number (InpTestMagic, default 990099001), then verifies             |
//| IntradayCloseManager genuinely closes/cancels them. This is the      |
//| only real way to verify closing logic actually works, not just       |
//| compiles. Run this ONLY on a demo account, and only when you intend  |
//| a brief real (though trivial) trading action to occur. It never       |
//| touches any position/order under a different magic number.           |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Execution/IntradayCloseManager.mqh"
#include "../Include/ThembaEA/Market/SymbolProfile.mqh"

input string InpTestSymbol = "EURUSD";
input long   InpTestMagic  = 990099001; // deliberately distinctive —
                                         // must never collide with a
                                         // real strategy's magic number

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

int CountOwnedPositions(const long magic)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetInteger(POSITION_MAGIC) == magic)
         count++;
     }
   return count;
  }

int CountOwnedPendingOrders(const long magic)
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket != 0 && OrderGetInteger(ORDER_MAGIC) == magic)
         count++;
     }
   return count;
  }

void OnStart()
  {
   Print("=== TASK-010 IntradayCloseManager test start ===");
   PrintFormat("WARNING: this test places a real minimum-volume market "
               "position and a pending order under magic %I64d on '%s', "
               "then closes/cancels them. Demo-account use only.",
               InpTestMagic, InpTestSymbol);

   // Safety: refuse to run if this magic already has something open —
   // never assume a clean slate, verify it.
   int pre_positions = CountOwnedPositions(InpTestMagic);
   int pre_orders = CountOwnedPendingOrders(InpTestMagic);
   if(pre_positions > 0 || pre_orders > 0)
     {
      PrintFormat("ABORT: magic %I64d already has %d position(s) and %d "
                  "pending order(s) open — refusing to run to avoid "
                  "interfering with existing state. Investigate before "
                  "re-running.", InpTestMagic, pre_positions, pre_orders);
      return;
     }

   CSymbolProfile profile;
   if(!profile.Load(InpTestSymbol))
     {
      PrintFormat("ABORT: '%s' failed to load — cannot determine a valid "
                  "minimum volume to trade.", InpTestSymbol);
      return;
     }

   //--- 1. ICM_ShouldExecuteIntradayClose behaves correctly -------------
   Check("boundary 00:00 is always due (independent of 'done today' state "
         "on the very first check)",
         ICM_ShouldExecuteIntradayClose(0, 0));

   //--- 1b. **Codex review finding, eighth round, P0 finding 10**: the -----
   //--- persisted due/pending-close record -- pure GlobalVariable state, ----
   //--- no live order needed. Cleaned up first so a prior aborted run --------
   //--- leaves no residue. -----------------------------------------------------
   ICM_ClearPendingCloseDate(InpTestSymbol, InpTestMagic);
   Check("no close is pending on a freshly cleared instance",
         ICM_IsCloseReconciliationPending(InpTestSymbol, InpTestMagic) == false);
   Check("ICM_GetPendingCloseDate returns 0 when nothing is pending",
         ICM_GetPendingCloseDate(InpTestSymbol, InpTestMagic) == 0);

   datetime fake_boundary_date = TimeTradeServer() - 86400; // "yesterday", to
                                                              // prove this
                                                              // survives a
                                                              // simulated
                                                              // day rollover
   bool armed = ICM_SetPendingCloseDate(InpTestSymbol, InpTestMagic, fake_boundary_date);
   Check("ICM_SetPendingCloseDate reports success", armed);
   Check("a close is now reported pending", ICM_IsCloseReconciliationPending(InpTestSymbol,
                                                                              InpTestMagic));
   Check("ICM_GetPendingCloseDate returns the exact date just armed",
         ICM_GetPendingCloseDate(InpTestSymbol, InpTestMagic) == fake_boundary_date);

   // **The core of this finding: a close armed for an EARLIER day (as if
   // the calendar already rolled over past it without the close ever
   // completing) stays reported as pending -- SN_IsPastIntradayBoundary()
   // for TODAY may well be false right now, but ICM_IsCloseReconciliationPending
   // must not depend on that; it is the persisted record, not today's clock.**
   Check("a close armed for an EARLIER day remains pending regardless of "
         "TODAY's own boundary state (the exact gap this finding closes)",
         ICM_IsCloseReconciliationPending(InpTestSymbol, InpTestMagic));

   ICM_ClearPendingCloseDate(InpTestSymbol, InpTestMagic);
   Check("ICM_ClearPendingCloseDate leaves nothing pending",
         ICM_IsCloseReconciliationPending(InpTestSymbol, InpTestMagic) == false);

   //--- 2. Open one real market position under the test magic -----------
   CTrade trade;
   trade.SetExpertMagicNumber(InpTestMagic);
   double vol = profile.volume_min;
   double ask = SymbolInfoDouble(InpTestSymbol, SYMBOL_ASK);
   bool opened = trade.Buy(vol, InpTestSymbol, ask, 0.0, 0.0, "TASK010_TEST");
   uint open_retcode = trade.ResultRetcode();
   Check(StringFormat("test position opens successfully (retcode=%u)", open_retcode),
         opened && (open_retcode == TRADE_RETCODE_DONE || open_retcode == TRADE_RETCODE_PLACED));

   if(!opened)
     {
      PrintFormat("ABORT: could not open the test position — skipping the "
                  "remaining close-verification checks. This may indicate "
                  "the market is closed or trading is currently disabled, "
                  "not necessarily a code defect.");
     }
   else
     {
      Check("exactly one owned position exists after opening",
            CountOwnedPositions(InpTestMagic) == 1);

      //--- 3. Open a far-away pending order under the same magic --------
      double point = profile.point;
      double pending_price = ask - 500 * point; // far from market, should
                                                  // not fill during the test
      bool pending_ok = trade.BuyLimit(vol, pending_price, InpTestSymbol,
                                        0.0, 0.0, ORDER_TIME_GTC, 0,
                                        "TASK010_TEST_PENDING");
      Check("test pending order places successfully", pending_ok);

      int pending_count_before_close = CountOwnedPendingOrders(InpTestMagic);
      Check("exactly one owned pending order exists after placing it",
            pending_count_before_close == 1);

      //--- 4. Execute the intraday close and verify everything clears ---
      string reasons[];
      bool close_ok = ICM_ExecuteIntradayClose(InpTestMagic, reasons);
      Check("ICM_ExecuteIntradayClose reports full success", close_ok);
      Check("ICM_ExecuteIntradayClose produces zero failure reasons on success",
            ArraySize(reasons) == 0);

      Check("zero owned positions remain after the intraday close",
            CountOwnedPositions(InpTestMagic) == 0);
      Check("zero owned pending orders remain after the intraday close",
            CountOwnedPendingOrders(InpTestMagic) == 0);

      //--- 5. The once-per-day guard suppresses a redundant re-run ------
      Check("ICM_ShouldExecuteIntradayClose returns false immediately "
            "after a fully successful close today",
            ICM_ShouldExecuteIntradayClose(0, 0) == false);

      //--- 6. **Codex review finding, eighth round, P0 finding 10**: ------
      //--- ICM_ReconcileIntradayClose end-to-end -- opens one more real -----
      //--- position, verifies the reconcile call (boundary 0:0, always -------
      //--- due) both closes it AND clears the persisted pending record ------
      //--- once fully successful. ---------------------------------------------
      ICM_ClearPendingCloseDate(InpTestSymbol, InpTestMagic); // clean slate
      bool opened3 = trade.Buy(vol, InpTestSymbol, SymbolInfoDouble(InpTestSymbol, SYMBOL_ASK),
                                0.0, 0.0, "TASK010_TEST_RECONCILE");
      if(opened3)
        {
         Check("one owned position exists before ICM_ReconcileIntradayClose",
               CountOwnedPositions(InpTestMagic) == 1);
         bool reconciled = ICM_ReconcileIntradayClose(InpTestSymbol, InpTestMagic, 0, 0);
         Check("ICM_ReconcileIntradayClose reports full success", reconciled);
         Check("zero owned positions remain after ICM_ReconcileIntradayClose",
               CountOwnedPositions(InpTestMagic) == 0);
         Check("ICM_ReconcileIntradayClose clears the pending record on full success",
               ICM_IsCloseReconciliationPending(InpTestSymbol, InpTestMagic) == false);
        }
      else
         Print("INFO: skipping step 6 (ICM_ReconcileIntradayClose end-to-end) -- could not "
               "open the additional test position.");
     }

   //--- Final safety check: this magic must be completely clear ----------
   Check("magic is fully clear at the end of the test (no leaked state)",
         CountOwnedPositions(InpTestMagic) == 0 &&
         CountOwnedPendingOrders(InpTestMagic) == 0);

   PrintFormat("=== TASK-010 IntradayCloseManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
