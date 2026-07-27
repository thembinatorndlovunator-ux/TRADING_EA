//+------------------------------------------------------------------+
//| DailyWeeklyBreachManager.mqh                                      |
//| Themba Adaptive Intraday Engine — Risk                             |
//|                                                                    |
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 3):** implements TASK-002_PHASE2_SPECIFICATION.md section 8's post-fill      |
//| daily/weekly loss-cap breach closure state machine verbatim:               |
//| "breach detection happens inside the OnTradeTransaction handler at the        |
//| moment the filling deal is reported... the closure order is submitted            |
//| synchronously from that same handler. A persisted closure_pending record             |
//| (per-instance namespace) is written before the close order is submitted;                |
//| if the close fails (requote/error), the EA retries on every subsequent                     |
//| tick until confirmed closed, blocking new entries on that symbol                              |
//| meanwhile; on restart, a pending closure_pending record is the first thing                       |
//| reconciled. A breach also cancels all of this EA's own pending orders...                            |
//| closes only positions carrying this EA's own magic number."                                            |
//|                                                                    |
//| Reuses IntradayCloseManager.mqh's own ICM_CloseAllOwnedPositions/            |
//| ICM_CancelAllOwnedPendingOrders primitives (own-magic, account-wide) —          |
//| this module owns only the persisted closure_pending flag and the                    |
//| retry-until-closed orchestration, not a second close/cancel                             |
//| implementation.                                                                             |
//|                                                                    |
//| Persisted per-instance (symbol+magic+account+server), NOT StateManager's      |
//| shared account-wide namespace — per section 8's own "per-instance             |
//| namespace" wording, since each magic-numbered instance manages its own            |
//| closure independently.                                                                |
//+------------------------------------------------------------------+
#property strict

#include "../Execution/IntradayCloseManager.mqh"

string DWB_Key(const string symbol, const long magic)
  {
   long   login  = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   return "ThembaEA_DWB_" + IntegerToString(login) + "_" + server + "_" +
          symbol + "_" + IntegerToString(magic) + "__pending";
  }

bool DWB_IsClosurePending(const string symbol, const long magic)
  {
   string key = DWB_Key(symbol, magic);
   if(!GlobalVariableCheck(key))
      return false;
   return GlobalVariableGet(key) != 0.0;
  }

void DWB_SetClosurePending(const string symbol, const long magic, const bool pending)
  {
   GlobalVariableSet(DWB_Key(symbol, magic), pending ? 1.0 : 0.0);
  }

//+------------------------------------------------------------------+
//| Arms the closure_pending record BEFORE submitting anything — per            |
//| section 8's own required write-before-submit ordering — then attempts        |
//| to close every own-magic position and cancel every own-magic pending          |
//| order. Idempotent/safe to call repeatedly: an already-closed position or        |
//| already-cancelled order is simply absent from PositionsTotal()/                    |
//| OrdersTotal() on the retry, so ICM_CloseAllOwnedPositions/                             |
//| ICM_CancelAllOwnedPendingOrders naturally no-op on it. Only clears the                    |
//| persisted record once BOTH report full success (retry-until-closed, per                      |
//| section 8). Call from OnTradeTransaction on a fresh breach detection and                         |
//| from OnTick on every tick while DWB_IsClosurePending() is true (including                            |
//| once at OnInit, for restart reconciliation).                                                             |
//+------------------------------------------------------------------+
bool DWB_AttemptClosure(const string symbol, const long magic, string &reasons[])
  {
   ArrayFree(reasons);
   DWB_SetClosurePending(symbol, magic, true); // persisted BEFORE the close order submits

   string position_reasons[];
   string order_reasons[];
   bool positions_ok = ICM_CloseAllOwnedPositions(magic, position_reasons);
   bool orders_ok    = ICM_CancelAllOwnedPendingOrders(magic, order_reasons);

   for(int i = 0; i < ArraySize(position_reasons); i++)
      ICM_AppendReason(reasons, position_reasons[i]);
   for(int i = 0; i < ArraySize(order_reasons); i++)
      ICM_AppendReason(reasons, order_reasons[i]);

   bool all_ok = positions_ok && orders_ok;
   if(all_ok)
      DWB_SetClosurePending(symbol, magic, false); // confirmed fully closed -- clear

   return all_ok;
  }
