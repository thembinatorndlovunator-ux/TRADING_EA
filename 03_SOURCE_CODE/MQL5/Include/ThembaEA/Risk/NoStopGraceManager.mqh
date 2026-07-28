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
//| **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding      |
//| 6):** in-memory fallback, belt-and-suspenders alongside the persisted    |
//| GlobalVariable below -- same class of fix as                             |
//| DailyWeeklyBreachManager.mqh's g_dwb_closure_owed_inmemory (round 9,     |
//| finding 6) and IntradayCloseManager.mqh's g_icm_close_done_today         |
//| (round 8, finding 10). Closes the review's own reported gap: if          |
//| NSG_SetFirstSeen's persisted write repeatedly fails, NSG_GetFirstSeen    |
//| would keep reading 0 (never set) on every subsequent tick, so            |
//| EnforceNoStopGracePeriod's own "if(first_seen == 0) { set; continue; }"  |
//| branch re-triggers EVERY tick forever -- the grace period never          |
//| actually starts, and the mandatory five-second close never becomes      |
//| due. A small linear-scan array is used (this project's own magic        |
//| scope typically holds a small, single-digit number of concurrently      |
//| stopless positions at once, matching AsyncFillCorrelator.mqh's own      |
//| array-based pending-list precedent for a similarly-bounded count).      |
//+------------------------------------------------------------------+
ulong    g_nsg_inmemory_position_ids[];
datetime g_nsg_inmemory_first_seen[];

datetime NSG_GetFirstSeenInMemory(const ulong position_id, bool &found_out)
  {
   found_out = false;
   for(int i = 0; i < ArraySize(g_nsg_inmemory_position_ids); i++)
     {
      if(g_nsg_inmemory_position_ids[i] == position_id)
        {
         found_out = true;
         return g_nsg_inmemory_first_seen[i];
        }
     }
   return 0;
  }

void NSG_SetFirstSeenInMemory(const ulong position_id, const datetime t)
  {
   for(int i = 0; i < ArraySize(g_nsg_inmemory_position_ids); i++)
     {
      if(g_nsg_inmemory_position_ids[i] == position_id)
        {
         g_nsg_inmemory_first_seen[i] = t;
         return;
        }
     }
   int n = ArraySize(g_nsg_inmemory_position_ids);
   ArrayResize(g_nsg_inmemory_position_ids, n + 1);
   ArrayResize(g_nsg_inmemory_first_seen, n + 1);
   g_nsg_inmemory_position_ids[n] = position_id;
   g_nsg_inmemory_first_seen[n] = t;
  }

void NSG_ClearInMemory(const ulong position_id)
  {
   int idx = -1;
   for(int i = 0; i < ArraySize(g_nsg_inmemory_position_ids); i++)
     {
      if(g_nsg_inmemory_position_ids[i] == position_id)
        {
         idx = i;
         break;
        }
     }
   if(idx < 0)
      return;
   int last = ArraySize(g_nsg_inmemory_position_ids) - 1;
   g_nsg_inmemory_position_ids[idx] = g_nsg_inmemory_position_ids[last];
   g_nsg_inmemory_first_seen[idx] = g_nsg_inmemory_first_seen[last];
   ArrayResize(g_nsg_inmemory_position_ids, last);
   ArrayResize(g_nsg_inmemory_first_seen, last);
  }

//+------------------------------------------------------------------+
//| Returns the "first observed missing SL" timestamp for position_id,     |
//| or 0 if this position is not currently tracked (either never seen         |
//| stopless, or already remediated/closed). Prefers the in-memory value      |
//| (see its own header above) over the persisted GlobalVariable -- this      |
//| session's own tracking is authoritative once established; the             |
//| persisted value is only the fallback for a value never set this           |
//| session (e.g. immediately after a restart).                               |
//+------------------------------------------------------------------+
datetime NSG_GetFirstSeen(const ulong position_id)
  {
   bool found;
   datetime inmemory_value = NSG_GetFirstSeenInMemory(position_id, found);
   if(found)
      return inmemory_value;

   string key = NSG_Key(position_id);
   if(!GlobalVariableCheck(key))
      return 0;
   return (datetime)GlobalVariableGet(key);
  }

//+------------------------------------------------------------------+
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 6):    |
//| the in-memory value is now set UNCONDITIONALLY, before attempting the        |
//| persisted write -- see this file's own in-memory-fallback header for the         |
//| exact "every tick looks like the first observation" defect this closes.**        |
//+------------------------------------------------------------------+
bool NSG_SetFirstSeen(const ulong position_id, const datetime t)
  {
   NSG_SetFirstSeenInMemory(position_id, t);
   return KE_SetDoubleChecked(NSG_Key(position_id), (double)t);
  }

//+------------------------------------------------------------------+
//| Stops tracking position_id — call once a valid stop is observed          |
//| attached, or once the position is confirmed closed (mirrors                 |
//| PST_Clear's own "clear once confirmed gone" contract).                          |
//+------------------------------------------------------------------+
void NSG_Clear(const ulong position_id)
  {
   NSG_ClearInMemory(position_id);
   string key = NSG_Key(position_id);
   if(GlobalVariableCheck(key))
      GlobalVariableDel(key);
  }
