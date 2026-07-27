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
//|                                                                    |
//| **Reused, 2026-07-27 (Codex review finding, ninth round, P0 finding    |
//| 1):** ThembaAdaptiveIntradayEA.mq5's OnTradeTransaction now also calls          |
//| DWB_AttemptClosure for a POST-FILL hard-risk-cap breach (the recomputed             |
//| actual per-trade or total-open-risk figure exceeding InpRiskCapPercent),                 |
//| not only a daily/weekly loss-cap breach -- both breach reasons require                       |
//| the exact same corrective action (close every own-magic position, cancel                        |
//| every own-magic pending order), so this module's persisted                                       |
//| closure_pending flag/retry-until-closed machinery is shared rather than                           |
//| duplicated under a second name. The flag itself does not distinguish                              |
//| WHICH breach reason armed it -- callers needing that distinction must                             |
//| log it themselves (see the EA's own PrintFormat calls at each call                                 |
//| site).**                                                                                           |
//+------------------------------------------------------------------+
#property strict

#include "../Core/KeyEncoding.mqh"
#include "../Execution/IntradayCloseManager.mqh"

//+------------------------------------------------------------------+
//| Bounded, collision-resistant key -- see KeyEncoding.mqh's own header      |
//| (Codex review finding, eighth round, P0 finding 6).                              |
//+------------------------------------------------------------------+
string DWB_Key(const string symbol, const long magic)
  {
   return KE_InstanceNamespace("ThembaEA_DWB", symbol, magic) + "__pending";
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding    |
//| 6):** in-memory fallback, belt-and-suspenders alongside the persisted        |
//| GlobalVariable below -- matching IntradayCloseManager.mqh's own                 |
//| g_icm_close_done_today precedent for the identical class of problem.               |
//| Closes the gap the review reported: if DWB_SetClosurePending(true)                     |
//| itself fails to persist (a real GlobalVariableSet failure, not merely a                    |
//| hypothetical), DWB_IsClosurePending() previously had NO other signal to                        |
//| fall back on and read false -- so OnTick's own every-tick retry loop         |
//| (see ThembaAdaptiveIntradayEA.mq5's own OnTick) would never call             |
//| DWB_AttemptClosure again until an ENTIRELY SEPARATE deal happened to         |
//| re-detect the breach. This flag is armed unconditionally the instant a       |
//| closure is first attempted (before the persisted write is even tried)       |
//| and cleared ONLY on a confirmed full success, so an in-session retry         |
//| loop keeps working regardless of the persisted write's own success.         |
//| Does not survive a restart (that residual gap needs the persisted flag      |
//| to have succeeded, or exposure would need to be reconstructed the same      |
//| way finding 6's other half does for IntradayCloseManager.mqh).              |
//+------------------------------------------------------------------+
bool g_dwb_closure_owed_inmemory = false;

bool DWB_IsClosurePending(const string symbol, const long magic)
  {
   if(g_dwb_closure_owed_inmemory)
      return true;
   string key = DWB_Key(symbol, magic);
   if(!GlobalVariableCheck(key))
      return false;
   return GlobalVariableGet(key) != 0.0;
  }

//+------------------------------------------------------------------+
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** the write's own success is now checked; arming the record          |
//| (pending=true) is flushed immediately -- this is the exact persisted            |
//| flag section 8 requires to be durable BEFORE the close order submits,               |
//| so it must survive a crash occurring the instant after this call                       |
//| returns, not wait for MT5's own periodic flush cadence.**                                  |
//+------------------------------------------------------------------+
bool DWB_SetClosurePending(const string symbol, const long magic, const bool pending)
  {
   bool ok = KE_SetDoubleChecked(DWB_Key(symbol, magic), pending ? 1.0 : 0.0);
   if(pending)
      GlobalVariablesFlush();
   return ok;
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
   // **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding 6):
   // arm the in-memory fallback FIRST, unconditionally -- see
   // g_dwb_closure_owed_inmemory's own header for the exact retry-loop gap
   // this closes regardless of whether the persisted write below succeeds.**
   g_dwb_closure_owed_inmemory = true;

   // Persisted BEFORE the close order submits, per section 8 -- proceeds to
   // close/cancel regardless of this write's own outcome (closing real
   // exposure now takes priority over the restart-recovery record of doing
   // so), but a failure is still logged since it means a crash during this
   // exact closure attempt would not be resumed correctly on restart.
   if(!DWB_SetClosurePending(symbol, magic, true))
      PrintFormat("ThembaEA: failed to persist closure_pending=true for '%s' magic %I64d before "
                  "closing -- proceeding with the close anyway (the in-memory fallback still "
                  "guarantees this session's own retry loop keeps working), but a crash during it "
                  "would not be resumed correctly on restart.", symbol, magic);

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
     {
      DWB_SetClosurePending(symbol, magic, false); // confirmed fully closed -- clear
      g_dwb_closure_owed_inmemory = false; // clear ONLY on confirmed full success
     }

   return all_ok;
  }
