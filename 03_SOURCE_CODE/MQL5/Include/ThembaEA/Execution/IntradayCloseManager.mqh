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
#include "../Core/KeyEncoding.mqh"
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

      // **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding
      // 8): TRADE_RETCODE_PLACED is "accepted for processing", not a
      // broker-confirmed close -- accepting it here let the once-per-day
      // guard mark today's boundary close as fully done while a position
      // could still genuinely be open. Only TRADE_RETCODE_DONE counts as
      // success; anything else (including PLACED) is a distinguishable
      // failure reason that keeps ICM_ShouldExecuteIntradayClose returning
      // true so the caller retries on the next tick, per this module's own
      // "keep retrying until a full success" guard design.**
      if(!ok || retcode != TRADE_RETCODE_DONE)
        {
         // **Extended, 2026-07-22 (Codex review finding, seventh round, P1
         // finding 14): TRADE_RETCODE_DONE_PARTIAL (a real partial
         // completion -- only part of the position's volume actually
         // closed) is now named explicitly rather than lumped under the
         // generic "failed" reason. It still correctly leaves all_ok=false
         // so this bar's close is retried on the position's own now-smaller
         // remaining volume next tick, per this module's own retry design.**
         string reason_tag;
         if(retcode == TRADE_RETCODE_PLACED)
            reason_tag = "intraday_close_pending_confirmation";
         else if(retcode == TRADE_RETCODE_DONE_PARTIAL)
            reason_tag = "intraday_close_partial_remainder_still_open";
         else
            reason_tag = "intraday_close_failed";
         ICM_AppendReason(reasons, StringFormat(
            "%s_ticket_%I64u_symbol_%s_retcode_%u",
            reason_tag, ticket, symbol, retcode));
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

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 10):** persisted (restart- and midnight-rollover-durable) "a close is        |
//| owed for this calendar day" record, per-instance (symbol+magic). The           |
//| module-level g_icm_close_done_date/g_icm_close_done_today guard above is         |
//| IN-MEMORY ONLY -- if the EA restarts, or if no tick arrives between the            |
//| boundary and the next server midnight (the review's own reported gap:                 |
//| "there is no timer... the next day's tick makes                                          |
//| SN_IsPastIntradayBoundary() false again, so overnight exposure can                          |
//| remain"), that in-memory guard is silently lost and nothing else recorded                      |
//| that yesterday's close was ever due, let alone whether it completed. This                          |
//| persisted field is the authoritative record ICM_ReconcileIntradayClose                                 |
//| below checks FIRST -- before even asking whether TODAY's own boundary has                                 |
//| been reached -- so a still-owed close from an EARLIER day is never                                            |
//| silently dropped by the calendar simply rolling over.                                                             |
//+------------------------------------------------------------------+
string ICM_PendingCloseKey(const string symbol, const long magic)
  {
   return KE_InstanceNamespace("ThembaEA_ICM", symbol, magic) + "__pending_close_date";
  }

//+------------------------------------------------------------------+
//| The calendar day (its own SN_CurrentDailyBoundary() value) whose close   |
//| is still owed, or 0 if none is currently owed.                             |
//+------------------------------------------------------------------+
datetime ICM_GetPendingCloseDate(const string symbol, const long magic)
  {
   string key = ICM_PendingCloseKey(symbol, magic);
   if(!GlobalVariableCheck(key))
      return 0;
   return (datetime)GlobalVariableGet(key);
  }

bool ICM_SetPendingCloseDate(const string symbol, const long magic, const datetime date)
  {
   bool ok = KE_SetDoubleChecked(ICM_PendingCloseKey(symbol, magic), (double)date);
   if(ok)
      // Safety-critical: must survive a crash occurring the instant after
      // this call returns, not wait for MT5's own periodic flush cadence --
      // this IS the record that makes the close survive a restart.
      GlobalVariablesFlush();
   return ok;
  }

void ICM_ClearPendingCloseDate(const string symbol, const long magic)
  {
   KE_SetDoubleChecked(ICM_PendingCloseKey(symbol, magic), 0.0);
  }

//+------------------------------------------------------------------+
//| True iff a close is currently owed (armed but not yet confirmed          |
//| fully done) for this instance -- callers use this to block new entries      |
//| even when SN_IsPastIntradayBoundary() itself reads false (e.g. just         |
//| after midnight, before today's own boundary, with YESTERDAY's close             |
//| still unresolved).                                                              |
//+------------------------------------------------------------------+
bool ICM_IsCloseReconciliationPending(const string symbol, const long magic)
  {
   return ICM_GetPendingCloseDate(symbol, magic) != 0;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 10):** the full persisted-due/pending intraday-close check+execute,          |
//| callable identically from OnInit (restart reconciliation -- "reconcile          |
//| the previous day's unfinished close before allowing any new entry"),                |
//| OnTick, AND OnTimer (the no-tick-boundary guarantee: a timer fires on its               |
//| own wall-clock schedule regardless of whether any tick arrives).                           |
//|                                                                    |
//| Arms the persisted pending-close record the INSTANT today's own boundary        |
//| is first observed reached (idempotent -- re-arming the same date is a               |
//| harmless no-op), then attempts the close whenever ANY date is recorded                 |
//| pending -- including one left over from an earlier day this instance                      |
//| never got to attempt again before now (a restart, or a tick-starved                          |
//| overnight gap). Only clears the record once ICM_ExecuteIntradayClose                             |
//| reports EVERY own-magic position closed and EVERY own-magic pending                                 |
//| order cancelled.                                                                                        |
//+------------------------------------------------------------------+
bool ICM_ReconcileIntradayClose(const string symbol, const long magic,
                                 const int boundary_hour = 23, const int boundary_minute = 45)
  {
   if(SN_IsPastIntradayBoundary(boundary_hour, boundary_minute))
     {
      datetime todays_boundary = SN_CurrentDailyBoundary();
      if(ICM_GetPendingCloseDate(symbol, magic) != todays_boundary)
         ICM_SetPendingCloseDate(symbol, magic, todays_boundary);
     }

   if(!ICM_IsCloseReconciliationPending(symbol, magic))
      return true; // nothing owed right now

   string reasons[];
   bool all_ok = ICM_ExecuteIntradayClose(magic, reasons);
   if(all_ok)
      ICM_ClearPendingCloseDate(symbol, magic);
   return all_ok;
  }
