//+------------------------------------------------------------------+
//| AsyncFillCorrelator.mqh                                           |
//| Themba Adaptive Intraday Engine — Execution                       |
//|                                                                    |
//| TASK-036 Specification item 4's "asynchronous fill correlation"       |
//| requirement: OM_OpenPosition treats TRADE_RETCODE_DONE and                |
//| TRADE_RETCODE_PLACED identically, scanning PositionsTotal() for the         |
//| resulting position immediately. For a genuinely synchronous DONE fill        |
//| this works; for PLACED (accepted but not necessarily filled yet on            |
//| every broker/execution model), the position may not exist at that scan          |
//| point, so both position_ticket and position_id can come back 0 with no           |
//| later mechanism to correlate a subsequent async fill back to the                   |
//| journal decision that triggered it.                                                    |
//|                                                                    |
//| **Design decision, stated explicitly (spec required picking one and       |
//| documenting why):** rather than rewriting an existing JSONL journal          |
//| line in place (would require reading/rewriting the whole day's file            |
//| on every async fill, defeating DecisionJournal.mqh's own append-only              |
//| durability design), this module tracks pending PLACED orders by their               |
//| MT5 order ticket (in-memory, session-scoped — this is a journal-                       |
//| ACCURACY concern, distinct from IntentManager.mqh's already-built,                      |
//| GlobalVariable-persisted, restart-durable crash-recovery mechanism for                    |
//| the underlying POSITION itself) and, when OnTradeTransaction later                          |
//| detects the resulting deal (filled) or the order's move to history                             |
//| without filling (cancelled/expired/rejected), APPENDS a correlated                                |
//| follow-up journal record referencing the original decision's signal_id                              |
//| — never silently leaving the original record's null order_id/deal_id                                  |
//| implying an open position that may or may not exist.                                                    |
//+------------------------------------------------------------------+
#property strict

ulong  g_afc_pending_order_tickets[];
string g_afc_pending_signal_ids[];

//+------------------------------------------------------------------+
//| Records a PLACED-but-not-yet-confirmed order for later correlation.   |
//+------------------------------------------------------------------+
void AFC_AddPending(const ulong order_ticket, const string signal_id)
  {
   int n = ArraySize(g_afc_pending_order_tickets);
   ArrayResize(g_afc_pending_order_tickets, n + 1);
   ArrayResize(g_afc_pending_signal_ids, n + 1);
   g_afc_pending_order_tickets[n] = order_ticket;
   g_afc_pending_signal_ids[n] = signal_id;
  }

//+------------------------------------------------------------------+
//| True iff 'order_ticket' has a pending correlation record, returning   |
//| its original signal_id and array index (for AFC_RemovePending).          |
//+------------------------------------------------------------------+
bool AFC_FindPending(const ulong order_ticket, string &signal_id_out, int &index_out)
  {
   signal_id_out = "";
   index_out = -1;
   for(int i = 0; i < ArraySize(g_afc_pending_order_tickets); i++)
     {
      if(g_afc_pending_order_tickets[i] == order_ticket)
        {
         signal_id_out = g_afc_pending_signal_ids[i];
         index_out = i;
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Removes the pending record at 'index' (swap-with-last, order does     |
//| not matter for this store).                                              |
//+------------------------------------------------------------------+
void AFC_RemovePending(const int index)
  {
   int last = ArraySize(g_afc_pending_order_tickets) - 1;
   if(index < 0 || index > last)
      return;
   g_afc_pending_order_tickets[index] = g_afc_pending_order_tickets[last];
   g_afc_pending_signal_ids[index] = g_afc_pending_signal_ids[last];
   ArrayResize(g_afc_pending_order_tickets, last);
   ArrayResize(g_afc_pending_signal_ids, last);
  }

//+------------------------------------------------------------------+
//| Number of currently-pending (unresolved) async correlations — test-   |
//| visible so a caller/test can assert the store is empty when expected.    |
//+------------------------------------------------------------------+
int AFC_PendingCount()
  {
   return ArraySize(g_afc_pending_order_tickets);
  }

//+------------------------------------------------------------------+
//| Test-only: wipes every pending record. Never called by normal EA      |
//| logic (a real pending record is only ever removed via AFC_RemovePending  |
//| once genuinely resolved).                                                   |
//+------------------------------------------------------------------+
void AFC_ClearAllPending()
  {
   ArrayFree(g_afc_pending_order_tickets);
   ArrayFree(g_afc_pending_signal_ids);
  }
