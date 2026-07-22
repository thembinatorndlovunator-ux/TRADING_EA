//+------------------------------------------------------------------+
//| CooldownManager.mqh                                               |
//| Themba Adaptive Intraday Engine — Risk                            |
//|                                                                    |
//| TASK-034 — the three-loss-per-symbol cooldown, per                  |
//| TASK-002_PHASE2_SPECIFICATION.md section 8 and the user's own         |
//| 2026-07-21 trigger specification: if all of the last 3 CLOSED           |
//| trades on a symbol+magic are losses AND their combined $ P/L is           |
//| negative, block new entries on that symbol+magic for a configurable        |
//| duration. Reset is purely time-based — no early-reset-on-win rule was      |
//| specified, so none is invented here (see TASK-034_LIVE_SAFETY_WIRING.md's    |
//| Specification item 1).                                                        |
//|                                                                    |
//| Split into a pure, hand-testable array-based core                     |
//| (CDM_ShouldTriggerCooldown) and a live wrapper that persists a 3-slot      |
//| ring buffer per symbol+magic instance via native MQL5 global variables       |
//| (double-only storage) — same GlobalVariable persistence mechanism as         |
//| StateManager.mqh, but INSTANCE-scoped (account+server+symbol+magic),          |
//| not account-wide, since a cooldown is meaningful per traded symbol,            |
//| not per account.                                                                 |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| PURE CORE — given exactly the last 3 closed-trade $ P/L values        |
//| (order does not matter; this only asks "are all 3 losses AND is the     |
//| sum negative"), decides whether the cooldown trigger fires. Fewer         |
//| than 3 recorded trades (ArraySize != 3) never triggers — there is not      |
//| yet enough history to evaluate the rule.                                    |
//+------------------------------------------------------------------+
bool CDM_ShouldTriggerCooldown(const double &last_three_pnls[])
  {
   if(ArraySize(last_three_pnls) != 3)
      return false;

   bool all_losses = true;
   double sum = 0.0;
   for(int i = 0; i < 3; i++)
     {
      if(last_three_pnls[i] >= 0.0)
         all_losses = false;
      sum += last_three_pnls[i];
     }
   return all_losses && (sum < 0.0);
  }

//+------------------------------------------------------------------+
//| LIVE WRAPPER — instance-scoped GlobalVariable persistence.            |
//+------------------------------------------------------------------+
string CDM_InstanceNamespace(const string symbol, const long magic)
  {
   long   login  = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   return "ThembaEA_CDM_" + IntegerToString(login) + "_" + server + "_" + symbol + "_" +
          IntegerToString(magic);
  }

string CDM_Key(const string symbol, const long magic, const string field)
  {
   return CDM_InstanceNamespace(symbol, magic) + "__" + field;
  }

double CDM_GetDouble(const string symbol, const long magic, const string field,
                      const double default_value)
  {
   string key = CDM_Key(symbol, magic, field);
   if(!GlobalVariableCheck(key))
      return default_value;
   return GlobalVariableGet(key);
  }

void CDM_SetDouble(const string symbol, const long magic, const string field, const double value)
  {
   GlobalVariableSet(CDM_Key(symbol, magic, field), value);
  }

//+------------------------------------------------------------------+
//| Records one CLOSED trade's $ P/L (profit + swap + commission — the    |
//| caller's responsibility to sum those, this function just stores the      |
//| final net figure) into the 3-slot ring buffer for 'symbol'+'magic',        |
//| then re-evaluates the trigger against whatever 3 (or fewer) trades          |
//| are currently on record. If triggered, sets cooldown_until to 'now' +        |
//| 'cooldown_minutes'. Call this once per confirmed position-closing deal        |
//| (see ThembaAdaptiveIntradayEA.mq5's OnTradeTransaction).                        |
//+------------------------------------------------------------------+
void CDM_RecordClosedTrade(const string symbol, const long magic, const double pnl,
                            const datetime now, const int cooldown_minutes)
  {
   int    next_slot = (int)CDM_GetDouble(symbol, magic, "next_slot", 0.0);
   double count      = CDM_GetDouble(symbol, magic, "count", 0.0);

   CDM_SetDouble(symbol, magic, "pnl_" + IntegerToString(next_slot), pnl);
   CDM_SetDouble(symbol, magic, "next_slot", (double)((next_slot + 1) % 3));
   CDM_SetDouble(symbol, magic, "count", MathMin(count + 1.0, 3.0));

   if(CDM_GetDouble(symbol, magic, "count", 0.0) >= 3.0)
     {
      double pnls[3];
      pnls[0] = CDM_GetDouble(symbol, magic, "pnl_0", 0.0);
      pnls[1] = CDM_GetDouble(symbol, magic, "pnl_1", 0.0);
      pnls[2] = CDM_GetDouble(symbol, magic, "pnl_2", 0.0);
      if(CDM_ShouldTriggerCooldown(pnls))
         CDM_SetDouble(symbol, magic, "cooldown_until", (double)(now + cooldown_minutes * 60));
     }
  }

//+------------------------------------------------------------------+
//| True iff 'symbol'+'magic' is currently in cooldown at 'now'.          |
//| 'cooldown_until_out' is always set (0 if never triggered / already      |
//| expired) so a caller can journal the exact expiry timestamp.              |
//+------------------------------------------------------------------+
bool CDM_IsInCooldown(const string symbol, const long magic, const datetime now,
                       datetime &cooldown_until_out)
  {
   cooldown_until_out = (datetime)CDM_GetDouble(symbol, magic, "cooldown_until", 0.0);
   return cooldown_until_out > now;
  }

//+------------------------------------------------------------------+
//| Test-only: wipes every field for 'symbol'+'magic' so a test run        |
//| leaves no residue and starts from a clean slate. Never called by         |
//| normal EA logic.                                                            |
//+------------------------------------------------------------------+
void CDM_ResetInstance(const string symbol, const long magic)
  {
   CDM_SetDouble(symbol, magic, "pnl_0", 0.0);
   CDM_SetDouble(symbol, magic, "pnl_1", 0.0);
   CDM_SetDouble(symbol, magic, "pnl_2", 0.0);
   CDM_SetDouble(symbol, magic, "next_slot", 0.0);
   CDM_SetDouble(symbol, magic, "count", 0.0);
   CDM_SetDouble(symbol, magic, "cooldown_until", 0.0);
  }
