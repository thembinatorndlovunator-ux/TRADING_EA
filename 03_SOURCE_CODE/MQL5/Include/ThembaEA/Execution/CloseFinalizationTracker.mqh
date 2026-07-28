//+------------------------------------------------------------------+
//| CloseFinalizationTracker.mqh                                     |
//| Themba Adaptive Intraday Engine — Execution                      |
//|                                                                    |
//| **Added, 2026-07-28 (Codex review finding, tenth round, P1 finding    |
//| 8):** OnTradeTransaction's own DEAL_ENTRY_OUT/OUT_BY/INOUT handling         |
//| only finalizes a closed position (cooldown-ledger recording, PST/          |
//| NSG/CIFT cleanup) when PositionStillOpenById() ALREADY reads false at         |
//| that exact processing moment -- but MT5 does not guarantee that every         |
//| transaction type for a single close arrives in an order that makes the           |
//| position absent from PositionsTotal() right then (the closing DEAL_ADD              |
//| can be delivered before the position list itself has caught up). When              |
//| that race hits, finalization was previously skipped SILENTLY and                       |
//| PERMANENTLY -- no other code path ever revisited it, so the consecutive-               |
//| loss cooldown ledger failed to advance for that trade and PST/NSG/CIFT                     |
//| state for a position_id that will never be reused lingered forever.                          |
//|                                                                    |
//| This module gives the caller a durable (persisted, restart-survivable),      |
//| account-wide list of position_ids whose closing deal has been OBSERVED         |
//| but not yet FINALIZED -- a periodic reconciliation pass (see the EA's own          |
//| ReconcilePendingCloseFinalizations) re-checks each one and completes                   |
//| finalization once PositionStillOpenById finally reads false, independent               |
//| of the one DEAL_ADD callback's own timing.                                                 |
//|                                                                    |
//| Keyed account-wide (not per-instance): position_id is itself already            |
//| MT5's own globally-unique-per-account durable identity, and is a small,           |
//| already-bounded numeric string (unlike a symbol name), so no hashing is             |
//| needed for the per-marker suffix -- only the shared account-wide prefix               |
//| needs KeyEncoding.mqh's own length-bounding (see KE_AccountNamespace's                   |
//| header).                                                                                    |
//+------------------------------------------------------------------+
#property strict

#include "../Core/KeyEncoding.mqh"

string PCF_Prefix()
  {
   return KE_AccountNamespace("ThembaEA_PCF") + "__";
  }

string PCF_Key(const ulong position_id)
  {
   return PCF_Prefix() + IntegerToString((long)position_id);
  }

//+------------------------------------------------------------------+
//| Marks 'position_id' as awaiting finalization -- call the instant a    |
//| closing deal is observed but PositionStillOpenById() still reads       |
//| true. Idempotent (safe to call repeatedly for the same position_id).   |
//+------------------------------------------------------------------+
bool PCF_MarkPendingFinalization(const ulong position_id)
  {
   return KE_SetDoubleChecked(PCF_Key(position_id), 1.0);
  }

//+------------------------------------------------------------------+
//| Clears the pending-finalization mark -- call once finalization has    |
//| actually completed (never merely on a re-check that still finds the   |
//| position open).                                                        |
//+------------------------------------------------------------------+
void PCF_ClearPendingFinalization(const ulong position_id)
  {
   string key = PCF_Key(position_id);
   if(GlobalVariableCheck(key))
      GlobalVariableDel(key);
  }

//+------------------------------------------------------------------+
//| Enumerates every position_id currently marked as awaiting               |
//| finalization (bounded by ArraySize(position_ids_out) — this project's   |
//| own magic scope only ever has a small, single-digit number of              |
//| concurrently-open positions, matching every other bounded-array               |
//| enumeration precedent in this codebase, e.g. AsyncFillCorrelator.mqh).       |
//+------------------------------------------------------------------+
int PCF_FindPendingFinalizations(ulong &position_ids_out[])
  {
   string prefix = PCF_Prefix();
   int max_out = ArraySize(position_ids_out);
   int total = GlobalVariablesTotal();
   int found = 0;
   for(int i = total - 1; i >= 0 && found < max_out; i--)
     {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) != 0)
         continue;
      string suffix = StringSubstr(name, StringLen(prefix));
      position_ids_out[found] = (ulong)StringToInteger(suffix);
      found++;
     }
   return found;
  }
