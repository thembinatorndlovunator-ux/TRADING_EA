//+------------------------------------------------------------------+
//| CloseInFlightTracker.mqh                                          |
//| Themba Adaptive Intraday Engine — Execution                       |
//|                                                                    |
//| **Added, 2026-07-22 (Codex review finding, eighth round, P1 finding    |
//| 13):** a close request that returns TRADE_RETCODE_PLACED (accepted for       |
//| processing, not yet broker-confirmed) was previously retried on EVERY          |
//| tick with no correlation to the FIRST outstanding request -- MetaQuotes           |
//| explicitly documents that OnTradeTransaction's own arrival order is not              |
//| guaranteed, so repeatedly resubmitting a close for the same position                    |
//| before its first request's terminal outcome arrives can produce                            |
//| close-order-exists, rate-limit, or volume errors at the broker.                                |
//|                                                                    |
//| Session-scoped (in-memory, like AsyncFillCorrelator.mqh's own pending      |
//| array) -- this is a submission-throttling concern, not a crash-recovery    |
//| one; IntentManager.mqh's durable intent record already owns the                |
//| crash-safety half for OPEN requests, and this project's own persisted            |
//| closure_pending (DailyWeeklyBreachManager.mqh) / pending_close_date                 |
//| (IntradayCloseManager.mqh) records already own it for the CLOSE                        |
//| obligation itself -- this tracker only prevents a SECOND close                            |
//| SUBMISSION while the first is still outstanding, keyed by position_id                        |
//| (durable across a broker-side re-open, matching this project's own                              |
//| POSITION_IDENTIFIER convention throughout).                                                          |
//+------------------------------------------------------------------+
#property strict

ulong g_cift_inflight_position_ids[];

bool CIFT_IsCloseInFlight(const ulong position_id)
  {
   for(int i = 0; i < ArraySize(g_cift_inflight_position_ids); i++)
      if(g_cift_inflight_position_ids[i] == position_id)
         return true;
   return false;
  }

void CIFT_MarkCloseInFlight(const ulong position_id)
  {
   if(CIFT_IsCloseInFlight(position_id))
      return;
   int n = ArraySize(g_cift_inflight_position_ids);
   ArrayResize(g_cift_inflight_position_ids, n + 1);
   g_cift_inflight_position_ids[n] = position_id;
  }

//+------------------------------------------------------------------+
//| Clears the in-flight mark — call once the position is CONFIRMED gone   |
//| (the same !PositionStillOpenById check this project already uses for      |
//| PST_Clear/NSG_Clear), never merely on a retry attempt.                        |
//+------------------------------------------------------------------+
void CIFT_ClearCloseInFlight(const ulong position_id)
  {
   int idx = -1;
   for(int i = 0; i < ArraySize(g_cift_inflight_position_ids); i++)
     {
      if(g_cift_inflight_position_ids[i] == position_id)
        {
         idx = i;
         break;
        }
     }
   if(idx < 0)
      return;
   int last = ArraySize(g_cift_inflight_position_ids) - 1;
   g_cift_inflight_position_ids[idx] = g_cift_inflight_position_ids[last];
   ArrayResize(g_cift_inflight_position_ids, last);
  }
