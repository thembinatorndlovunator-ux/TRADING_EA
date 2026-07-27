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
//|                                                                    |
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 6):   |
//| this previously had no timestamp and no timeout at all -- only cleared   |
//| once a close DEAL confirms the position gone (CIFT_ClearCloseInFlight,   |
//| called from OnTradeTransaction's DEAL_ENTRY_OUT handling once             |
//| !PositionStillOpenById). A close request that is instead REJECTED or     |
//| CANCELLED at the broker (a genuinely terminal outcome, but one that      |
//| produces NO close deal and leaves the position still open) left the      |
//| in-flight mark set FOREVER -- CIFT_IsCloseInFlight kept returning true,   |
//| so ICM_CloseAllOwnedPositions's own retry loop perpetually skipped        |
//| resubmitting a close for that position, "wedging" it until an EA         |
//| restart cleared the in-memory array. A CIFT_STALE_SECONDS timeout        |
//| (generous relative to a normal close round-trip, matching                |
//| StateManager.mqh's own SM_LOCK_STALE_SECONDS staleness pattern) now      |
//| treats an in-flight mark older than that as abandoned and clears it      |
//| automatically, so the caller's own retry loop can resubmit instead of    |
//| staying wedged.**                                                        |
//+------------------------------------------------------------------+
#property strict

#define CIFT_STALE_SECONDS 30

ulong    g_cift_inflight_position_ids[];
datetime g_cift_inflight_since[];

bool CIFT_IsCloseInFlight(const ulong position_id)
  {
   for(int i = 0; i < ArraySize(g_cift_inflight_position_ids); i++)
     {
      if(g_cift_inflight_position_ids[i] != position_id)
         continue;

      if((TimeCurrent() - g_cift_inflight_since[i]) > CIFT_STALE_SECONDS)
        {
         // Stale -- no terminal close-confirmation deal arrived within a
         // reasonable window (a rejected/cancelled close with no exit deal,
         // per this file's own fix above). Clear it so the caller's own
         // retry loop can resubmit instead of being wedged until restart.
         PrintFormat("ThembaEA: CloseInFlightTracker: in-flight close mark for position_id=%I64u "
                     "is older than %d seconds with no confirming close deal -- treating as "
                     "abandoned (likely rejected/cancelled at the broker) and allowing a retry.",
                     position_id, CIFT_STALE_SECONDS);
         CIFT_ClearCloseInFlight(position_id);
         return false;
        }
      return true;
     }
   return false;
  }

void CIFT_MarkCloseInFlight(const ulong position_id)
  {
   for(int i = 0; i < ArraySize(g_cift_inflight_position_ids); i++)
     {
      if(g_cift_inflight_position_ids[i] == position_id)
        {
         g_cift_inflight_since[i] = TimeCurrent(); // refresh on a repeated mark
         return;
        }
     }
   int n = ArraySize(g_cift_inflight_position_ids);
   ArrayResize(g_cift_inflight_position_ids, n + 1);
   ArrayResize(g_cift_inflight_since, n + 1);
   g_cift_inflight_position_ids[n] = position_id;
   g_cift_inflight_since[n] = TimeCurrent();
  }

//+------------------------------------------------------------------+
//| Clears the in-flight mark — call once the position is CONFIRMED gone   |
//| (the same !PositionStillOpenById check this project already uses for      |
//| PST_Clear/NSG_Clear), never merely on a retry attempt. Also called          |
//| internally by CIFT_IsCloseInFlight once a mark is judged stale (see           |
//| that function's own header).                                              |
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
   g_cift_inflight_since[idx] = g_cift_inflight_since[last];
   ArrayResize(g_cift_inflight_position_ids, last);
   ArrayResize(g_cift_inflight_since, last);
  }
