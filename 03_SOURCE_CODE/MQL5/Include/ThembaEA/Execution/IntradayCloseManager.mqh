//+------------------------------------------------------------------+
//| IntradayCloseManager.mqh                                          |
//| Themba Adaptive Intraday Engine — Execution                        |
//|                                                                    |
//| The intraday boundary close, per                                    |
//| TASK-002_PHASE2_SPECIFICATION.md section 8: "all of this EA's own   |
//| positions, across every symbol/mode it manages, are closed at        |
//| [InpIntradayBoundaryServerTime, default 23:45 server time] daily" — |
//| scoped strictly to THIS EA's own magic number, never a manual or     |
//| other-EA position, per section 8's account-wide close-scope rule     |
//| (this engine cannot know the intent behind a position it did not     |
//| open).                                                               |
//|                                                                    |
//| Every trading operation's result is explicitly checked — this is    |
//| the new-engine fix for both baselines' confirmed defect of            |
//| pervasive unchecked CTrade results (baseline_v637_audit.md,           |
//| baseline_v811_audit.md) — and every failure produces its own          |
//| machine-readable reason string, per PROJECT_RULES.md rule 6.          |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
#include "../Market/SessionManager.mqh"

//--- In-memory (not persisted) once-per-day guard: suppresses redundant
//--- close attempts on every tick after a FULLY successful close, but
//--- keeps retrying every tick after a partial/total failure until a
//--- full success is achieved — erring on the side of retrying a
//--- safety-critical close rather than silently giving up for the day.
datetime g_icm_close_done_date = 0;
bool     g_icm_close_done_today = false;

void ICM_AppendReason(string &reasons[], const string reason)
  {
   int n = ArraySize(reasons);
   ArrayResize(reasons, n + 1);
   reasons[n] = reason;
  }

//+------------------------------------------------------------------+
//| True iff the intraday boundary has been reached AND a fully          |
//| successful close has not already been executed today (in this       |
//| session — see the module-level guard comment above).                |
//+------------------------------------------------------------------+
bool ICM_ShouldExecuteIntradayClose(const int boundary_hour = 23,
                                     const int boundary_minute = 45)
  {
   if(!SN_IsPastIntradayBoundary(boundary_hour, boundary_minute))
      return false;

   datetime today = SN_CurrentDailyBoundary();
   if(g_icm_close_done_date != today)
     {
      g_icm_close_done_today = false; // a new day — allow (re)execution
      g_icm_close_done_date = today;
     }
   return !g_icm_close_done_today;
  }

//+------------------------------------------------------------------+
//| Closes every OPEN POSITION carrying 'magic' — this EA's own          |
//| positions only, across every symbol. Appends a machine-readable      |
//| reason for every close that did not succeed; returns true only if   |
//| every one of this EA's own positions closed successfully.            |
//+------------------------------------------------------------------+
bool ICM_CloseAllOwnedPositions(const long magic, string &reasons[])
  {
   bool all_ok = true;
   CTrade trade;
   trade.SetExpertMagicNumber(magic);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue; // not this EA's own position — never touched

      string symbol = PositionGetString(POSITION_SYMBOL);
      bool ok = trade.PositionClose(ticket);
      uint retcode = trade.ResultRetcode();

      if(!ok || (retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_PLACED))
        {
         ICM_AppendReason(reasons, StringFormat(
            "intraday_close_failed_ticket_%I64u_symbol_%s_retcode_%u",
            ticket, symbol, retcode));
         all_ok = false;
        }
     }

   return all_ok;
  }

//+------------------------------------------------------------------+
//| Cancels every PENDING ORDER carrying 'magic' — this EA's own          |
//| orders only. A pending order left open past the intraday boundary    |
//| would represent potential exposure opened after the boundary,        |
//| which conflicts with the boundary's own purpose (RISK_POLICY.md's    |
//| "close all exposure by the approved intraday boundary"), so this      |
//| is treated as part of the same intraday-close operation, not a       |
//| separate concern.                                                    |
//+------------------------------------------------------------------+
bool ICM_CancelAllOwnedPendingOrders(const long magic, string &reasons[])
  {
   bool all_ok = true;
   CTrade trade;
   trade.SetExpertMagicNumber(magic);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != magic)
         continue; // not this EA's own order — never touched

      string symbol = OrderGetString(ORDER_SYMBOL);
      bool ok = trade.OrderDelete(ticket);
      uint retcode = trade.ResultRetcode();

      if(!ok || retcode != TRADE_RETCODE_DONE)
        {
         ICM_AppendReason(reasons, StringFormat(
            "intraday_cancel_failed_ticket_%I64u_symbol_%s_retcode_%u",
            ticket, symbol, retcode));
         all_ok = false;
        }
     }

   return all_ok;
  }

//+------------------------------------------------------------------+
//| The full intraday-close operation: closes every owned position AND  |
//| cancels every owned pending order, for the given 'magic'. Updates    |
//| the once-per-day guard: a full success suppresses further attempts  |
//| for the rest of today; anything less than full success leaves        |
//| ICM_ShouldExecuteIntradayClose() returning true so the caller         |
//| retries on the next tick.                                            |
//+------------------------------------------------------------------+
bool ICM_ExecuteIntradayClose(const long magic, string &reasons[])
  {
   ArrayFree(reasons);

   string position_reasons[];
   string order_reasons[];
   bool positions_ok = ICM_CloseAllOwnedPositions(magic, position_reasons);
   bool orders_ok    = ICM_CancelAllOwnedPendingOrders(magic, order_reasons);

   for(int i = 0; i < ArraySize(position_reasons); i++)
      ICM_AppendReason(reasons, position_reasons[i]);
   for(int i = 0; i < ArraySize(order_reasons); i++)
      ICM_AppendReason(reasons, order_reasons[i]);

   bool all_ok = positions_ok && orders_ok;

   g_icm_close_done_date  = SN_CurrentDailyBoundary();
   g_icm_close_done_today = all_ok;

   return all_ok;
  }
