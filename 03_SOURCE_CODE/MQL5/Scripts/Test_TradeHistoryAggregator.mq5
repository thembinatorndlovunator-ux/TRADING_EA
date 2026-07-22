//+------------------------------------------------------------------+
//| Test_TradeHistoryAggregator.mq5                                  |
//| Themba Adaptive Intraday Engine — TASK-037 compile/logic test      |
//|                                                                    |
//| Pure, deterministic, no live trading action, no HistorySelect --      |
//| exercises TA_ProcessDeal directly against hand-fabricated SDealRecord    |
//| values (never read from a real live deal). Each scenario below is        |
//| hand-derivable; see the inline comments for the arithmetic. Added,          |
//| 2026-07-22, Codex review finding, seventh round, P0 finding 9.               |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Journal/TradeHistoryAggregator.mqh"

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

bool NearlyEqual(const double a, const double b, const double tol = 0.00001)
  {
   return MathAbs(a - b) <= tol;
  }

SDealRecord MakeDeal(const ulong ticket, const ulong position_id, const ENUM_DEAL_ENTRY entry,
                      const ENUM_DEAL_TYPE deal_type, const double volume, const double price,
                      const datetime time, const double stop_loss, const double commission,
                      const double swap, const double fee, const double raw_profit)
  {
   SDealRecord d;
   d.ticket = ticket;
   d.position_id = position_id;
   d.symbol = "EURUSD";
   d.entry = entry;
   d.deal_type = deal_type;
   d.volume = volume;
   d.price = price;
   d.time = time;
   d.stop_loss = stop_loss;
   d.commission = commission;
   d.swap = swap;
   d.fee = fee;
   d.raw_profit = raw_profit;
   return d;
  }

void OnStart()
  {
   Print("=== TASK-037 TradeHistoryAggregator test start ===");

   //--- 1. Single entry, single full close -----------------------------------
   {
      SPositionLeg legs[];
      STradeRow row;
      string warning;
      SDealRecord in1 = MakeDeal(1, 100, DEAL_ENTRY_IN, DEAL_TYPE_BUY, 1.0, 1.1000,
                                  D'2026.01.01 10:00:00', 1.0950, -2.0, 0.0, 0.0, 0.0);
      bool produced_in = TA_ProcessDeal(legs, in1, row, warning);
      Check("scenario 1: an IN deal never produces a row", produced_in == false);
      Check("scenario 1: an IN deal never sets a warning", warning == "");

      SDealRecord out1 = MakeDeal(2, 100, DEAL_ENTRY_OUT, DEAL_TYPE_SELL, 1.0, 1.1050,
                                   D'2026.01.01 11:00:00', 0.0, -2.0, -0.5, 0.0, 50.0);
      bool produced_out = TA_ProcessDeal(legs, out1, row, warning);
      Check("scenario 1: a full close produces a row", produced_out);
      Check("scenario 1: warning is empty on a clean full close", warning == "");
      Check("scenario 1: entry_price is the single fill's own price",
            NearlyEqual(row.entry_price, 1.1000));
      Check("scenario 1: stop_price is the entry deal's own SL",
            NearlyEqual(row.stop_price, 1.0950));
      Check("scenario 1: is_long is true (closing SELL deal closes a long)", row.is_long);
      // profit = raw_profit(50.0) + exit_cost(-2.0-0.5) + entry_cost_alloc(-2.0 * 1.0/1.0)
      //        = 50.0 - 2.5 - 2.0 = 45.5
      Check("scenario 1: profit includes both entry- and exit-side costs",
            NearlyEqual(row.profit, 45.5));
      Check("scenario 1: the leg is fully closed and removed", ArraySize(legs) == 0);
   }

   //--- 2. Two entry fills (broker-split single order) aggregate into a -----
   //--- volume-weighted entry price; only the FIRST fill's stop is kept -------
   {
      SPositionLeg legs[];
      STradeRow row;
      string warning;
      SDealRecord in1 = MakeDeal(3, 200, DEAL_ENTRY_IN, DEAL_TYPE_BUY, 0.6, 1.2000,
                                  D'2026.01.02 09:00:00', 1.1900, -1.2, 0.0, 0.0, 0.0);
      SDealRecord in2 = MakeDeal(4, 200, DEAL_ENTRY_IN, DEAL_TYPE_BUY, 0.4, 1.2010,
                                  D'2026.01.02 09:00:01', 1.1910, -0.8, 0.0, 0.0, 0.0);
      TA_ProcessDeal(legs, in1, row, warning);
      TA_ProcessDeal(legs, in2, row, warning);

      SDealRecord out1 = MakeDeal(5, 200, DEAL_ENTRY_OUT, DEAL_TYPE_SELL, 1.0, 1.2100,
                                   D'2026.01.02 10:00:00', 0.0, -2.0, 0.0, 0.0, 90.0);
      bool produced = TA_ProcessDeal(legs, out1, row, warning);
      Check("scenario 2: full close after two entry fills produces a row", produced);
      // weighted entry = (1.2000*0.6 + 1.2010*0.4) / 1.0 = (0.72 + 0.4804) / 1.0 = 1.2004
      Check("scenario 2: entry_price is the VOLUME-WEIGHTED average across both fills",
            NearlyEqual(row.entry_price, 1.2004));
      Check("scenario 2: stop_price is the FIRST fill's own SL (1.1900), not the second's "
            "(1.1910)", NearlyEqual(row.stop_price, 1.1900));
      Check("scenario 2: entry_time is the FIRST fill's own time",
            row.entry_time == D'2026.01.02 09:00:00');
      // entry_cost_total = -1.2 + -0.8 = -2.0; fully allocated since fully closed.
      // profit = 90.0 + (-2.0 exit cost) + (-2.0 entry cost) = 86.0
      Check("scenario 2: profit sums BOTH entry fills' own costs, not just one",
            NearlyEqual(row.profit, 86.0));
   }

   //--- 3. A single entry, closed across TWO partial closes -- prorated -----
   //--- entry cost across both rows sums to the whole entry cost --------------
   {
      SPositionLeg legs[];
      STradeRow row_a, row_b;
      string warning;
      SDealRecord in1 = MakeDeal(6, 300, DEAL_ENTRY_IN, DEAL_TYPE_BUY, 2.0, 1.3000,
                                  D'2026.01.03 08:00:00', 1.2900, -4.0, 0.0, 0.0, 0.0);
      TA_ProcessDeal(legs, in1, row_a, warning);

      SDealRecord out_a = MakeDeal(7, 300, DEAL_ENTRY_OUT, DEAL_TYPE_SELL, 1.0, 1.3050,
                                    D'2026.01.03 09:00:00', 0.0, -2.0, 0.0, 0.0, 50.0);
      bool produced_a = TA_ProcessDeal(legs, out_a, row_a, warning);
      Check("scenario 3: first partial close produces a row", produced_a);
      Check("scenario 3: leg stays open after a partial close", ArraySize(legs) == 1);
      // entry_price = 2.6/2.0 = 1.3000; alloc = -4.0*(1.0/2.0) = -2.0
      // profit_a = 50.0 + -2.0(exit cost) + -2.0(entry alloc) = 46.0
      Check("scenario 3: row A entry_price uses the WHOLE leg's own weighted average",
            NearlyEqual(row_a.entry_price, 1.3000));
      Check("scenario 3: row A profit", NearlyEqual(row_a.profit, 46.0));

      SDealRecord out_b = MakeDeal(8, 300, DEAL_ENTRY_OUT, DEAL_TYPE_SELL, 1.0, 1.3100,
                                    D'2026.01.03 10:00:00', 0.0, -2.0, 0.0, 0.0, 100.0);
      bool produced_b = TA_ProcessDeal(legs, out_b, row_b, warning);
      Check("scenario 3: second (final) partial close produces a row", produced_b);
      Check("scenario 3: row B entry_price is IDENTICAL to row A's (same leg basis)",
            NearlyEqual(row_b.entry_price, row_a.entry_price));
      // profit_b = 100.0 + -2.0(exit cost) + -2.0(entry alloc) = 96.0
      Check("scenario 3: row B profit", NearlyEqual(row_b.profit, 96.0));
      Check("scenario 3: the two rows' prorated entry-cost allocations sum to the whole "
            "entry cost (-4.0) -- summing row A+B profit recovers the true total net P/L",
            NearlyEqual(row_a.profit + row_b.profit, 150.0 - 2.0 - 2.0 - 4.0));
      Check("scenario 3: the leg is fully closed and removed after the second close",
            ArraySize(legs) == 0);
   }

   //--- 4. An orphaned closing deal (no matching open leg) is refused, ------
   //--- not fabricated --------------------------------------------------------
   {
      SPositionLeg legs[];
      STradeRow row;
      string warning;
      SDealRecord out_orphan = MakeDeal(9, 400, DEAL_ENTRY_OUT, DEAL_TYPE_SELL, 1.0, 1.4050,
                                         D'2026.01.04 10:00:00', 0.0, -2.0, 0.0, 0.0, 50.0);
      bool produced = TA_ProcessDeal(legs, out_orphan, row, warning);
      Check("scenario 4: an orphaned closing deal does NOT produce a row", produced == false);
      Check("scenario 4: an orphaned closing deal DOES set a warning", warning != "");
   }

   //--- 5. A reversal (INOUT) that closes EXACTLY the open volume -- clean, -
   //--- no warning --------------------------------------------------------------
   {
      SPositionLeg legs[];
      STradeRow row;
      string warning;
      SDealRecord in1 = MakeDeal(10, 500, DEAL_ENTRY_IN, DEAL_TYPE_BUY, 1.0, 1.4000,
                                  D'2026.01.05 08:00:00', 1.3900, -2.0, 0.0, 0.0, 0.0);
      TA_ProcessDeal(legs, in1, row, warning);

      SDealRecord reversal_exact = MakeDeal(11, 500, DEAL_ENTRY_INOUT, DEAL_TYPE_SELL, 1.0,
                                             1.4050, D'2026.01.05 09:00:00', 0.0, -2.0, 0.0, 0.0,
                                             50.0);
      bool produced = TA_ProcessDeal(legs, reversal_exact, row, warning);
      Check("scenario 5: an exact-volume reversal produces a row", produced);
      Check("scenario 5: an exact-volume reversal sets NO warning (nothing untracked)",
            warning == "");
      Check("scenario 5: profit", NearlyEqual(row.profit, 46.0)); // 50 - 2 - 2
      Check("scenario 5: the closed leg is removed", ArraySize(legs) == 0);
   }

   //--- 6. A reversal (INOUT) whose own volume EXCEEDS the open leg -- the ---
   //--- closing half is still well-defined, but a warning flags the ------------
   //--- untracked new reversed leg (stated, bounded limitation) -----------------
   {
      SPositionLeg legs[];
      STradeRow row;
      string warning;
      SDealRecord in1 = MakeDeal(12, 600, DEAL_ENTRY_IN, DEAL_TYPE_BUY, 1.0, 1.5000,
                                  D'2026.01.06 08:00:00', 1.4900, -2.0, 0.0, 0.0, 0.0);
      TA_ProcessDeal(legs, in1, row, warning);

      SDealRecord reversal_excess = MakeDeal(13, 600, DEAL_ENTRY_INOUT, DEAL_TYPE_SELL, 2.5,
                                              1.5050, D'2026.01.06 09:00:00', 0.0, -2.0, 0.0, 0.0,
                                              50.0);
      bool produced = TA_ProcessDeal(legs, reversal_excess, row, warning);
      Check("scenario 6: a reversal still closes the well-defined existing leg", produced);
      Check("scenario 6: a reversal exceeding the open leg DOES set a warning",
            warning != "");
      // The closing half is still computed against the leg's own open_volume
      // (1.0), NOT the deal's full 2.5 volume.
      Check("scenario 6: profit is computed against the CLOSED volume only (1.0), not the "
            "deal's full reversal volume (2.5)", NearlyEqual(row.profit, 46.0)); // 50 - 2 - 2
      Check("scenario 6: the old leg is removed (fully closed) regardless of the untracked "
            "new reversed leg", ArraySize(legs) == 0);
   }

   //--- 7. A non-position deal (position_id == 0, e.g. a balance operation) --
   //--- is silently ignored -- never fabricated into a phantom leg -------------
   {
      SPositionLeg legs[];
      STradeRow row;
      string warning;
      SDealRecord balance_deal = MakeDeal(14, 0, DEAL_ENTRY_IN, DEAL_TYPE_BALANCE, 0.0, 0.0,
                                           D'2026.01.07 00:00:00', 0.0, 0.0, 0.0, 0.0, 500.0);
      bool produced = TA_ProcessDeal(legs, balance_deal, row, warning);
      Check("scenario 7: a position_id==0 deal never produces a row", produced == false);
      Check("scenario 7: a position_id==0 deal never sets a warning", warning == "");
      Check("scenario 7: a position_id==0 deal never creates a leg", ArraySize(legs) == 0);
   }

   //--- 8. A deal entry type this aggregator does not understand (e.g. -----
   //--- DEAL_ENTRY_STATE) is ignored, not misclassified as an entry or close --
   {
      SPositionLeg legs[];
      STradeRow row;
      string warning;
      SDealRecord state_deal = MakeDeal(15, 800, DEAL_ENTRY_STATE, DEAL_TYPE_BUY, 1.0, 1.6000,
                                         D'2026.01.08 00:00:00', 0.0, 0.0, 0.0, 0.0, 0.0);
      bool produced = TA_ProcessDeal(legs, state_deal, row, warning);
      Check("scenario 8: an unrecognized deal entry type never produces a row",
            produced == false);
      Check("scenario 8: an unrecognized deal entry type never sets a warning", warning == "");
      Check("scenario 8: an unrecognized deal entry type never creates a leg",
            ArraySize(legs) == 0);
   }

   //--- 9. A normal (non-reversal) closing deal whose own volume exceeds the -
   //--- tracked open volume is clamped, with a warning --------------------------
   {
      SPositionLeg legs[];
      STradeRow row;
      string warning;
      SDealRecord in1 = MakeDeal(16, 900, DEAL_ENTRY_IN, DEAL_TYPE_BUY, 1.0, 1.6000,
                                  D'2026.01.09 08:00:00', 1.5900, -2.0, 0.0, 0.0, 0.0);
      TA_ProcessDeal(legs, in1, row, warning);

      SDealRecord out_oversized = MakeDeal(17, 900, DEAL_ENTRY_OUT, DEAL_TYPE_SELL, 1.5, 1.6050,
                                            D'2026.01.09 09:00:00', 0.0, -2.0, 0.0, 0.0, 50.0);
      bool produced = TA_ProcessDeal(legs, out_oversized, row, warning);
      Check("scenario 9: an oversized ordinary close still produces a row (clamped)", produced);
      Check("scenario 9: an oversized ordinary close DOES set a warning", warning != "");
      Check("scenario 9: profit is computed against the CLAMPED volume (1.0), not the deal's "
            "own oversized volume (1.5)", NearlyEqual(row.profit, 46.0)); // 50 - 2 - 2
      Check("scenario 9: the leg is fully closed and removed", ArraySize(legs) == 0);
   }

   PrintFormat("=== TASK-037 TradeHistoryAggregator test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
