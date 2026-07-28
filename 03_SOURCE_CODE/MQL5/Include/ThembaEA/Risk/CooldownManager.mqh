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

#include "../Core/KeyEncoding.mqh"

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
//+------------------------------------------------------------------+
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** previously concatenated the raw, unbounded server+symbol name           |
//| directly into the key -- the review's own worked example                          |
//| ("ThembaEA_CDM_12345678_Deriv-Demo_Volatility 100 Index_990001__          |
//| cooldown_until", 76 characters) already exceeds MT5's 63-character              |
//| global-variable name limit on an ordinary Deriv synthetic, silently                 |
//| losing cooldown state. Now delegates to KeyEncoding.mqh's                                |
//| KE_InstanceNamespace (fixed-width hash).**                                                    |
//+------------------------------------------------------------------+
string CDM_InstanceNamespace(const string symbol, const long magic)
  {
   return KE_InstanceNamespace("ThembaEA_CDM", symbol, magic);
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

//+------------------------------------------------------------------+
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** the write's own success is now returned (previously ignored by           |
//| every caller).**                                                                          |
//+------------------------------------------------------------------+
bool CDM_SetDouble(const string symbol, const long magic, const string field, const double value)
  {
   return KE_SetDoubleChecked(CDM_Key(symbol, magic, field), value);
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P1 finding    |
//| 13):** per-POSITION (not symbol+magic) accumulator for a single             |
//| position's own P/L across however many separate CLOSING deals it takes         |
//| to fully close it -- a broker-side partial close of this EA's own "close          |
//| the full position" request leaves a smaller remainder open under the SAME             |
//| position_id, and the caller (OnTradeTransaction) must accumulate each                     |
//| partial closing deal's own P/L here rather than recording each one as a                      |
//| SEPARATE closed trade for the 3-loss cooldown -- three partial losing                            |
//| fills from ONE position must count as one closed trade, not three.                                  |
//+------------------------------------------------------------------+
string CDM_PositionPnlKey(const ulong position_id)
  {
   return KE_PositionNamespace("ThembaEA_CDM_POS", position_id) + "__cumulative_pnl";
  }

double CDM_GetAccumulatedPositionPnl(const ulong position_id)
  {
   string key = CDM_PositionPnlKey(position_id);
   if(!GlobalVariableCheck(key))
      return 0.0;
   return GlobalVariableGet(key);
  }

//+------------------------------------------------------------------+
//| Adds 'delta_pnl' (one closing deal's own P/L) to position_id's running    |
//| total. Call on EVERY closing deal for this position, whether or not it        |
//| is the one that finally leaves the position fully closed.                        |
//+------------------------------------------------------------------+
bool CDM_AccumulatePositionPnl(const ulong position_id, const double delta_pnl)
  {
   double total = CDM_GetAccumulatedPositionPnl(position_id) + delta_pnl;
   return KE_SetDoubleChecked(CDM_PositionPnlKey(position_id), total);
  }

//+------------------------------------------------------------------+
//| Clears the accumulator -- call once the position is CONFIRMED gone AND    |
//| its accumulated total has already been recorded via                            |
//| CDM_RecordClosedTrade, so a later, unrelated position that happens to             |
//| reuse this same position_id value (MT5 identifiers are not infinite)                  |
//| never inherits a stale running total.                                                    |
//+------------------------------------------------------------------+
void CDM_ClearAccumulatedPositionPnl(const ulong position_id)
  {
   KE_SetDoubleChecked(CDM_PositionPnlKey(position_id), 0.0);
  }

//+------------------------------------------------------------------+
//| Records one CLOSED trade's $ P/L (profit + swap + commission — the    |
//| caller's responsibility to sum those, this function just stores the      |
//| final net figure) into the 3-slot ring buffer for 'symbol'+'magic',        |
//| then re-evaluates the trigger against whatever 3 (or fewer) trades          |
//| are currently on record. If triggered, sets cooldown_until to 'now' +        |
//| 'cooldown_minutes'. Call this once per confirmed position-closing deal        |
//| (see ThembaAdaptiveIntradayEA.mq5's OnTradeTransaction).                        |
//|                                                                    |
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** now returns whether every write this call attempted actually           |
//| persisted, so a caller can at least log a lost cooldown-ledger write             |
//| (the review's own "assert every generated key/write" ask).**                        |
//+------------------------------------------------------------------+
bool CDM_RecordClosedTrade(const string symbol, const long magic, const double pnl,
                            const datetime now, const int cooldown_minutes)
  {
   int    next_slot = (int)CDM_GetDouble(symbol, magic, "next_slot", 0.0);
   double count      = CDM_GetDouble(symbol, magic, "count", 0.0);

   bool all_ok = true;
   all_ok = CDM_SetDouble(symbol, magic, "pnl_" + IntegerToString(next_slot), pnl) && all_ok;
   all_ok = CDM_SetDouble(symbol, magic, "next_slot", (double)((next_slot + 1) % 3)) && all_ok;
   all_ok = CDM_SetDouble(symbol, magic, "count", MathMin(count + 1.0, 3.0)) && all_ok;

   if(CDM_GetDouble(symbol, magic, "count", 0.0) >= 3.0)
     {
      double pnls[3];
      pnls[0] = CDM_GetDouble(symbol, magic, "pnl_0", 0.0);
      pnls[1] = CDM_GetDouble(symbol, magic, "pnl_1", 0.0);
      pnls[2] = CDM_GetDouble(symbol, magic, "pnl_2", 0.0);
      if(CDM_ShouldTriggerCooldown(pnls))
         all_ok = CDM_SetDouble(symbol, magic, "cooldown_until",
                                 (double)(now + cooldown_minutes * 60)) && all_ok;
     }
   return all_ok;
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
