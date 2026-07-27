//+------------------------------------------------------------------+
//| NoStopGraceManager.mqh                                            |
//| Themba Adaptive Intraday Engine — Risk                             |
//|                                                                    |
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 3):** enforces TASK-002_PHASE2_SPECIFICATION.md section 8's no-SL          |
//| fallback grace period verbatim: "The position is flagged for                  |
//| immediate remediation; if a valid stop is not attached within                     |
//| InpNoStopGraceSeconds (default 5) seconds, the position is closed                    |
//| immediately (fail-closed)." Tracks, per position_id (durable across a                   |
//| broker-side re-open — see OrderManager.mqh's own SOrderOpenResult                          |
//| comment for why POSITION_IDENTIFIER, not position_ticket, is the                              |
//| correct durable key), the first tick this EA observed the position                              |
//| missing its stop — same GlobalVariable-per-position persistence pattern                             |
//| as PositionStateTracker.mqh/CooldownManager.mqh.                                                        |
//+------------------------------------------------------------------+
#property strict

#include "../Core/KeyEncoding.mqh"

//+------------------------------------------------------------------+
//| Bounded, collision-resistant key -- see KeyEncoding.mqh's own header      |
//| (Codex review finding, eighth round, P0 finding 6: every persistence         |
//| module in this codebase must build a length-bounded key, not concatenate       |
//| the raw, unbounded server name).                                                  |
//+------------------------------------------------------------------+
string NSG_Key(const ulong position_id)
  {
   return KE_PositionNamespace("ThembaEA_NSG", position_id);
  }

//+------------------------------------------------------------------+
//| Returns the persisted "first observed missing SL" timestamp for        |
//| position_id, or 0 if this position is not currently tracked (either      |
//| never seen stopless, or already remediated/closed).                        |
//+------------------------------------------------------------------+
datetime NSG_GetFirstSeen(const ulong position_id)
  {
   string key = NSG_Key(position_id);
   if(!GlobalVariableCheck(key))
      return 0;
   return (datetime)GlobalVariableGet(key);
  }

bool NSG_SetFirstSeen(const ulong position_id, const datetime t)
  {
   return KE_SetDoubleChecked(NSG_Key(position_id), (double)t);
  }

//+------------------------------------------------------------------+
//| Stops tracking position_id — call once a valid stop is observed          |
//| attached, or once the position is confirmed closed (mirrors                 |
//| PST_Clear's own "clear once confirmed gone" contract).                          |
//+------------------------------------------------------------------+
void NSG_Clear(const ulong position_id)
  {
   string key = NSG_Key(position_id);
   if(GlobalVariableCheck(key))
      GlobalVariableDel(key);
  }
