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
     }

   //--- Final safety check: this magic must be completely clear ----------
   Check("magic is fully clear at the end of the test (no leaked state)",
         CountOwnedPositions(InpTestMagic) == 0 &&
         CountOwnedPendingOrders(InpTestMagic) == 0);

   PrintFormat("=== TASK-010 IntradayCloseManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
