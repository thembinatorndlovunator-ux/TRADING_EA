//+------------------------------------------------------------------+
//| IntentManager.mqh                                                 |
//| Themba Adaptive Intraday Engine — Execution                       |
//|                                                                    |
//| TASK-034 — durable-intent / idempotency persistence, per             |
//| TASK-002_PHASE2_SPECIFICATION.md section 12: before submitting an       |
//| order, persist an intent record (symbol, direction, size, timestamp)      |
//| that survives a crash/restart between "about to submit" and "confirmed      |
//| filled or confirmed rejected." On restart, an orphaned intent record is       |
//| reconciled against actual open positions before resuming normal               |
//| operation — this is what prevents a crash-and-restart from causing a           |
//| second, duplicate order for the same signal.                                     |
//|                                                                    |
//| Storage: instance-scoped (account+server+symbol+magic) native MQL5      |
//| global variables, same double-only mechanism as StateManager.mqh/          |
//| CooldownManager.mqh. The 'active' flag is set via                            |
//| GlobalVariableSetOnCondition (compare-and-set) so IM_BeginIntent itself        |
//| is the same-tick idempotency guard: a second call while an intent is           |
//| already active fails closed (returns false, no second order should be           |
//| submitted) rather than silently overwriting the first intent.                     |
//|                                                                    |
//| Reconciliation policy (IM_ReconcileOnRestart): if an intent record is    |
//| found active at OnInit, check whether a position matching symbol+magic     |
//| now exists. Either way — found (the order filled before the crash) or       |
//| not found (it was rejected, or the crash happened before the order even       |
//| reached the broker) — the intent is cleared once reconciled, since the         |
//| live position list is now the ground truth and the whole point of              |
//| reconciliation is to resume normal operation with an accurate picture of         |
//| what is actually open, not to leave the symbol permanently blocked.                |
//+------------------------------------------------------------------+
#property strict

string IM_InstanceNamespace(const string symbol, const long magic)
  {
   long   login  = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   return "ThembaEA_IM_" + IntegerToString(login) + "_" + server + "_" + symbol + "_" +
          IntegerToString(magic);
  }

string IM_Key(const string symbol, const long magic, const string field)
  {
   return IM_InstanceNamespace(symbol, magic) + "__" + field;
  }

double IM_GetDouble(const string symbol, const long magic, const string field,
                     const double default_value)
  {
   string key = IM_Key(symbol, magic, field);
   if(!GlobalVariableCheck(key))
      return default_value;
   return GlobalVariableGet(key);
  }

void IM_SetDouble(const string symbol, const long magic, const string field, const double value)
  {
   GlobalVariableSet(IM_Key(symbol, magic, field), value);
  }

//+------------------------------------------------------------------+
//| True iff an intent is currently recorded active for 'symbol'+'magic'.  |
//+------------------------------------------------------------------+
bool IM_HasActiveIntent(const string symbol, const long magic)
  {
   return IM_GetDouble(symbol, magic, "active", 0.0) != 0.0;
  }

//+------------------------------------------------------------------+
//| Begins a new intent record just before order submission. Returns      |
//| false (and records nothing) if an intent is already active — this is    |
//| the idempotency guard: a caller must never submit a second order for      |
//| the same symbol+magic while one is already in flight. 'is_long' is         |
//| stored as 1.0/0.0, 'volume' and 'timestamp' verbatim.                        |
//+------------------------------------------------------------------+
bool IM_BeginIntent(const string symbol, const long magic, const bool is_long,
                     const double volume, const datetime now)
  {
   string active_key = IM_Key(symbol, magic, "active");
   if(!GlobalVariableCheck(active_key))
      GlobalVariableSet(active_key, 0.0); // unset sentinel, created once

   if(!GlobalVariableSetOnCondition(active_key, 1.0, 0.0))
      return false; // an intent is already active — refuse a second one

   IM_SetDouble(symbol, magic, "is_long", is_long ? 1.0 : 0.0);
   IM_SetDouble(symbol, magic, "volume", volume);
   IM_SetDouble(symbol, magic, "timestamp", (double)now);
   return true;
  }

//+------------------------------------------------------------------+
//| Clears the intent record — call on confirmed fill OR confirmed          |
//| rejection (both are a definitive outcome; only a crash mid-flight         |
//| leaves 'active' stuck at 1.0 for IM_ReconcileOnRestart to resolve).          |
//+------------------------------------------------------------------+
void IM_ClearIntent(const string symbol, const long magic)
  {
   IM_SetDouble(symbol, magic, "active", 0.0);
  }

//+------------------------------------------------------------------+
//| True iff a position matching 'symbol'+'magic' currently exists —       |
//| used by reconciliation to determine whether an orphaned intent            |
//| actually filled before the crash.                                            |
//+------------------------------------------------------------------+
bool IM_HasMatchingPosition(const string symbol, const long magic)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Call once at OnInit, before normal evaluation resumes. If an intent    |
//| record is active, reconciles it against the live position list and       |
//| clears it either way (see file header's reconciliation policy).             |
//| Returns true if an orphaned intent was found and reconciled (false if       |
//| there was nothing to reconcile — the common case). 'was_filled_out' is        |
//| only meaningful when this returns true.                                         |
//+------------------------------------------------------------------+
bool IM_ReconcileOnRestart(const string symbol, const long magic, bool &was_filled_out)
  {
   was_filled_out = false;
   if(!IM_HasActiveIntent(symbol, magic))
      return false;

   was_filled_out = IM_HasMatchingPosition(symbol, magic);
   IM_ClearIntent(symbol, magic);
   return true;
  }

//+------------------------------------------------------------------+
//| Test-only: wipes every field for 'symbol'+'magic' so a test run        |
//| leaves no residue. Never called by normal EA logic.                       |
//+------------------------------------------------------------------+
void IM_ResetInstance(const string symbol, const long magic)
  {
   IM_SetDouble(symbol, magic, "active", 0.0);
   IM_SetDouble(symbol, magic, "is_long", 0.0);
   IM_SetDouble(symbol, magic, "volume", 0.0);
   IM_SetDouble(symbol, magic, "timestamp", 0.0);
  }
