//+------------------------------------------------------------------+
//| KeyEncoding.mqh                                                   |
//| Themba Adaptive Intraday Engine — Core                            |
//|                                                                    |
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** every persistence module in this codebase (StateManager.mqh,           |
//| IntentManager.mqh, PositionStateTracker.mqh, CooldownManager.mqh, and             |
//| this round's own new NoStopGraceManager.mqh/DailyWeeklyBreachManager.mqh)             |
//| built its native-MQL5-GlobalVariable key by concatenating raw               |
//| account_login + trade_server + symbol (+ magic/position_id) text. MT5              |
//| limits a global-variable name to 63 characters and GlobalVariableSet                  |
//| silently fails beyond it — an ordinary Deriv synthetic symbol name              |
//| ("Volatility 100 Index") already pushes several of these keys past                    |
//| the limit on a normal broker server name, permanently breaking order                     |
//| submission (IntentManager) or silently losing cooldown/exit state                           |
//| (CooldownManager/PositionStateTracker) on exactly the symbols this                              |
//| project trades most.                                                                                |
//|                                                                    |
//| Fix: every namespace builder below produces a FIXED-WIDTH (16 hex           |
//| character) FNV-1a 64-bit hash of the unbounded identity components               |
//| (login+server+symbol+magic/position_id), so the resulting key length is              |
//| bounded regardless of how long a broker's server name or a synthetic                    |
//| symbol's name is. A 64-bit hash makes an accidental collision between                       |
//| two distinct instances astronomically unlikely for the small number of                          |
//| namespaces any single account ever actually creates (this is the same                              |
//| collision-tolerance standard this project already applies to its own                                  |
//| microsecond-resolution signal/intent IDs — see                                                            |
//| ThembaAdaptiveIntradayEA.mq5's BuildSignalId and IntentManager.mqh's                                          |
//| IM_BuildIntentId).                                                                                                |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| FNV-1a 64-bit hash — simple, dependency-free, and deterministic        |
//| across runs (no seeding from process/time state), which is required        |
//| here since the SAME input must always hash to the SAME key.                   |
//+------------------------------------------------------------------+
ulong KE_FNV1a64(const string s)
  {
   ulong hash = 0xcbf29ce484222325;
   int len = StringLen(s);
   for(int i = 0; i < len; i++)
     {
      hash ^= (ulong)StringGetCharacter(s, i);
      hash *= 0x100000001b3;
     }
   return hash;
  }

//+------------------------------------------------------------------+
//| Fixed-width (always exactly 16 characters) hex encoding of a 64-bit    |
//| hash — formatted as two 32-bit halves since MQL5's StringFormat has       |
//| well-established %08X support for 32-bit values (a single %I64X-style      |
//| 64-bit hex specifier is not relied on here).                                  |
//+------------------------------------------------------------------+
string KE_HashHex(const string s)
  {
   ulong h = KE_FNV1a64(s);
   return StringFormat("%08X%08X", (uint)(h >> 32), (uint)(h & 0xFFFFFFFF));
  }

//+------------------------------------------------------------------+
//| Bounded, collision-resistant ACCOUNT-WIDE namespace (login+server        |
//| only, no symbol/magic) — for StateManager.mqh's own account-wide           |
//| record set.                                                                    |
//+------------------------------------------------------------------+
string KE_AccountNamespace(const string prefix)
  {
   long   login  = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   string raw = IntegerToString(login) + "_" + server;
   return prefix + "_" + KE_HashHex(raw);
  }

//+------------------------------------------------------------------+
//| Bounded, collision-resistant PER-INSTANCE namespace (login+server+       |
//| symbol+magic) — for IntentManager.mqh/CooldownManager.mqh/                    |
//| DailyWeeklyBreachManager.mqh's own instance-scoped records.                       |
//+------------------------------------------------------------------+
string KE_InstanceNamespace(const string prefix, const string symbol, const long magic)
  {
   long   login  = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   string raw = IntegerToString(login) + "_" + server + "_" + symbol + "_" + IntegerToString(magic);
   return prefix + "_" + KE_HashHex(raw);
  }

//+------------------------------------------------------------------+
//| Bounded, collision-resistant PER-POSITION namespace (login+server+       |
//| position_id) — for PositionStateTracker.mqh/NoStopGraceManager.mqh's           |
//| own position-scoped records.                                                      |
//+------------------------------------------------------------------+
string KE_PositionNamespace(const string prefix, const ulong position_id)
  {
   long   login  = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   string raw = IntegerToString(login) + "_" + server + "_" + IntegerToString((long)position_id);
   return prefix + "_" + KE_HashHex(raw);
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding    |
//| 1):** bounded, collision-resistant MAGIC-WIDE namespace (login+server+     |
//| magic, deliberately NO symbol) -- for RiskReservationManager.mqh's own          |
//| cross-symbol risk-reservation ledger, which must be prefix-scannable            |
//| across every symbol this magic number manages (GlobalVariablesTotal()/           |
//| GlobalVariableName(i) enumeration, filtered by this exact prefix) to sum               |
//| every live reservation this magic currently holds, on any symbol,                          |
//| before allowing a NEW one -- KE_InstanceNamespace's own symbol+magic                           |
//| hash deliberately does NOT support this (symbol is folded into the SAME                            |
//| opaque digest as magic, so there is no shared prefix to scan for across                            |
//| a different symbol's own key). Callers append their own bounded                                       |
//| per-symbol suffix (e.g. KE_HashHex(symbol)) after this namespace's own                                       |
//| trailing "__".                                                                                                 |
//+------------------------------------------------------------------+
string KE_MagicNamespace(const string prefix, const long magic)
  {
   long   login  = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   string raw = IntegerToString(login) + "_" + server + "_" + IntegerToString(magic);
   return prefix + "_" + KE_HashHex(raw);
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** checked GlobalVariableSet — the review's own finding: "The code         |
//| ignores that return value." GlobalVariableSet returns 0 (a falsy               |
//| datetime) on failure, per MQL5's own documented contract. Logs the                 |
//| failing key/length for diagnosis (even though KE_*Namespace above is                  |
//| designed to keep every key this project builds well under the 63-                        |
//| character limit) and returns false so a caller can propagate the                             |
//| failure instead of silently proceeding as if the write succeeded.                                |
//+------------------------------------------------------------------+
bool KE_SetDoubleChecked(const string key, const double value)
  {
   if(GlobalVariableSet(key, value) == 0)
     {
      PrintFormat("ThembaEA: GlobalVariableSet FAILED for key '%s' (length=%d, error=%d) -- "
                  "value NOT persisted.", key, StringLen(key), GetLastError());
      return false;
     }
   return true;
  }
