//+------------------------------------------------------------------+
//| ChartPatternLifecycle.mqh                                         |
//| Themba Adaptive Intraday Engine — Patterns                         |
//|                                                                    |
//| **Added, 2026-07-27 (Codex review finding, ninth round, P1 finding      |
//| 11):** TASK-002_PHASE2_SPECIFICATION.md section 6's required               |
//| `FORMING/CONFIRMED/RETESTING/TRADED/INVALIDATED/EXPIRED` state             |
//| machine and durable pattern identity ("keyed by pattern type +               |
//| boundary pivots... permanently marks an instance TRADED as consumed --        |
//| it never re-enters eligibility even if price re-touches the same              |
//| boundary"). `ChartPatternEngine.mqh`'s own detection functions are            |
//| stateless by design (they rediscover geometry fresh from the current           |
//| price window every call) -- this module is the PERSISTED layer on top             |
//| of that, giving each detected instance a durable identity that                        |
//| survives across bars so it can be marked consumed once traded/                          |
//| invalidated/expired.                                                                        |
//|                                                                    |
//| **Durable identity:** pattern type + the two identity-defining pivot          |
//| bars' own TIMES (not bar INDEX -- a pivot's index into the shared               |
//| evaluation window shifts by one every new bar, but its own timestamp               |
//| never changes). `ChartPatternStrategy.mqh` converts the detection                     |
//| engine's own `pivot_index_1`/`pivot_index_2` output fields to times via                  |
//| its caller-supplied `times[]` array before calling into this module.                        |
//|                                                                    |
//| **Storage:** one GlobalVariable key per (instance, field), scoped            |
//| under `KE_InstanceNamespace` (symbol+magic) — the same bounded,                |
//| collision-resistant per-instance namespace `IntentManager.mqh`/                    |
//| `CooldownManager.mqh` already use, KeyEncoding.mqh's own established              |
//| pattern. `CPL_CleanupStale` prefix-scans and deletes old records past             |
//| a retention window, mirroring `RiskReservationManager.mqh`'s own                     |
//| established prefix-scan-and-cleanup idiom -- this keeps GlobalVariable                  |
//| count bounded over the EA's lifetime instead of growing forever as new                     |
//| pattern instances are discovered and consumed.                                                 |
//|                                                                    |
//| **What this module does NOT do (a real, stated scope boundary, not a        |
//| silently skipped part of the spec):** `ChartPatternEngine.mqh`'s own            |
//| detection functions only ever report an ALREADY-CONFIRMED pattern (a               |
//| non-negative `breakout_index`) -- there is no separate, turn-by-turn                  |
//| tracking of a pattern instance while it is still in `FORMING`, so this                   |
//| module's own state graph begins at `CONFIRMED`, not `FORMING`. Section                     |
//| 6's `InpPatternFormingMaxAgeBars` (expiry from FIRST detected pivot,                          |
//| before confirmation) therefore cannot be enforced by this module --                              |
//| only expiry FROM CONFIRMATION (`InpPatternMaxAgeBars`) is implemented                                here.
//| Building genuine turn-by-turn FORMING-stage tracking (persisting a                                       |
//| pattern's own pivots before its breakout is even confirmed) is a                                            |
//| further, separate architectural item, not attempted here.                                                      |
//+------------------------------------------------------------------+
#property strict

#include "../Core/KeyEncoding.mqh"

enum ENUM_CP_LIFECYCLE_STATE
  {
   CPL_STATE_NONE,        // no persisted record -- this exact instance has never been seen
   CPL_STATE_CONFIRMED,
   CPL_STATE_RETESTING,
   CPL_STATE_TRADED,
   CPL_STATE_INVALIDATED,
   CPL_STATE_EXPIRED
  };

//+------------------------------------------------------------------+
//| Bounded, collision-resistant per-symbol+magic namespace every        |
//| pattern instance under this EA's own scope shares -- KeyEncoding.mqh's   |
//| established KE_InstanceNamespace, same as IntentManager.mqh.            |
//+------------------------------------------------------------------+
string CPL_InstancePrefix(const string symbol, const long magic)
  {
   return KE_InstanceNamespace("ThembaEA_CPL", symbol, magic);
  }

//+------------------------------------------------------------------+
//| Durable pattern identity: type + the two identity-defining pivot     |
//| bars' own TIMES, hashed to a bounded, fixed-width key component.        |
//+------------------------------------------------------------------+
string CPL_InstanceId(const int pattern_type, const datetime pivot1_time, const datetime pivot2_time)
  {
   string raw = IntegerToString(pattern_type) + "_" + IntegerToString((long)pivot1_time) + "_" +
                IntegerToString((long)pivot2_time);
   return KE_HashHex(raw);
  }

string CPL_Key(const string instance_prefix, const string instance_id, const string field)
  {
   return instance_prefix + "__" + instance_id + "__" + field;
  }

//+------------------------------------------------------------------+
//| Reads this exact instance's own persisted state. CPL_STATE_NONE       |
//| means no record exists yet -- this instance has never been observed     |
//| before (the caller should treat it as newly CONFIRMED).                    |
//+------------------------------------------------------------------+
ENUM_CP_LIFECYCLE_STATE CPL_GetState(const string symbol, const long magic, const int pattern_type,
                                       const datetime pivot1_time, const datetime pivot2_time)
  {
   string prefix = CPL_InstancePrefix(symbol, magic);
   string id = CPL_InstanceId(pattern_type, pivot1_time, pivot2_time);
   string key = CPL_Key(prefix, id, "state");
   if(!GlobalVariableCheck(key))
      return CPL_STATE_NONE;
   return (ENUM_CP_LIFECYCLE_STATE)(int)GlobalVariableGet(key);
  }

//+------------------------------------------------------------------+
//| Persists this exact instance's own state, touching its own            |
//| "last_update" companion field for CPL_CleanupStale's own staleness       |
//| bookkeeping. Returns false (logged) if either write fails -- a caller     |
//| must not assume the transition took effect.                              |
//+------------------------------------------------------------------+
bool CPL_SetState(const string symbol, const long magic, const int pattern_type,
                   const datetime pivot1_time, const datetime pivot2_time,
                   const ENUM_CP_LIFECYCLE_STATE new_state)
  {
   string prefix = CPL_InstancePrefix(symbol, magic);
   string id = CPL_InstanceId(pattern_type, pivot1_time, pivot2_time);
   bool ok = KE_SetDoubleChecked(CPL_Key(prefix, id, "state"), (double)new_state);
   ok = KE_SetDoubleChecked(CPL_Key(prefix, id, "last_update"), (double)TimeTradeServer()) && ok;
   return ok;
  }

//+------------------------------------------------------------------+
//| The server time this instance was first confirmed -- used to enforce  |
//| InpPatternMaxAgeBars expiry. Returns 0 if never recorded.                |
//+------------------------------------------------------------------+
datetime CPL_GetConfirmedTime(const string symbol, const long magic, const int pattern_type,
                                const datetime pivot1_time, const datetime pivot2_time)
  {
   string prefix = CPL_InstancePrefix(symbol, magic);
   string id = CPL_InstanceId(pattern_type, pivot1_time, pivot2_time);
   string key = CPL_Key(prefix, id, "confirmed_time");
   if(!GlobalVariableCheck(key))
      return 0;
   return (datetime)GlobalVariableGet(key);
  }

bool CPL_SetConfirmedTime(const string symbol, const long magic, const int pattern_type,
                            const datetime pivot1_time, const datetime pivot2_time,
                            const datetime confirmed_time)
  {
   string prefix = CPL_InstancePrefix(symbol, magic);
   string id = CPL_InstanceId(pattern_type, pivot1_time, pivot2_time);
   return KE_SetDoubleChecked(CPL_Key(prefix, id, "confirmed_time"), (double)confirmed_time);
  }

//+------------------------------------------------------------------+
//| The server time this instance first entered its own retest zone --   |
//| used as CPT_CheckRetestArray's own 'touch_index' anchor, converted to    |
//| a bar index by the caller. Returns 0 if never recorded (not yet          |
//| touched).                                                                 |
//+------------------------------------------------------------------+
datetime CPL_GetRetestTouchTime(const string symbol, const long magic, const int pattern_type,
                                  const datetime pivot1_time, const datetime pivot2_time)
  {
   string prefix = CPL_InstancePrefix(symbol, magic);
   string id = CPL_InstanceId(pattern_type, pivot1_time, pivot2_time);
   string key = CPL_Key(prefix, id, "retest_touch");
   if(!GlobalVariableCheck(key))
      return 0;
   return (datetime)GlobalVariableGet(key);
  }

bool CPL_SetRetestTouchTime(const string symbol, const long magic, const int pattern_type,
                              const datetime pivot1_time, const datetime pivot2_time,
                              const datetime touch_time)
  {
   string prefix = CPL_InstancePrefix(symbol, magic);
   string id = CPL_InstanceId(pattern_type, pivot1_time, pivot2_time);
   return KE_SetDoubleChecked(CPL_Key(prefix, id, "retest_touch"), (double)touch_time);
  }

//+------------------------------------------------------------------+
//| True for a TERMINAL, consumed state -- section 6's own "permanently    |
//| marks an instance TRADED as consumed... never re-enters eligibility"     |
//| requirement, extended (correctly) to INVALIDATED/EXPIRED as well: none    |
//| of the three should ever become eligible again without new pivots         |
//| (a genuinely new instance identity).                                       |
//+------------------------------------------------------------------+
bool CPL_IsTerminal(const ENUM_CP_LIFECYCLE_STATE state)
  {
   return state == CPL_STATE_TRADED || state == CPL_STATE_INVALIDATED ||
          state == CPL_STATE_EXPIRED;
  }

//+------------------------------------------------------------------+
//| Deletes every field of every instance under this symbol+magic whose   |
//| own "last_update" is older than 'max_age_seconds' -- keeps GlobalVariable |
//| count bounded over the EA's lifetime instead of growing forever, per        |
//| RiskReservationManager.mqh's own established prefix-scan-and-cleanup       |
//| idiom (GlobalVariablesTotal()/GlobalVariableName(i), the only MQL5           |
//| primitive that can discover "every key matching a prefix").                    |
//+------------------------------------------------------------------+
void CPL_CleanupStale(const string symbol, const long magic, const int max_age_seconds)
  {
   string full_prefix = CPL_InstancePrefix(symbol, magic) + "__";
   const string suffix = "__last_update";
   const int suffix_len = 13; // StringLen("__last_update"), a compile-time constant here
   datetime now = TimeTradeServer();
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      string name = GlobalVariableName(i);
      if(StringFind(name, full_prefix) != 0)
         continue;
      if(StringLen(name) < suffix_len || StringSubstr(name, StringLen(name) - suffix_len) != suffix)
         continue; // only the "__last_update" companion key drives cleanup decisions

      double last_update = GlobalVariableGet(name);
      if(last_update <= 0.0 || (now - (datetime)last_update) <= max_age_seconds)
         continue; // not stale yet

      string instance_key_prefix = StringSubstr(name, 0, StringLen(name) - suffix_len);
      GlobalVariableDel(instance_key_prefix + "__state");
      GlobalVariableDel(instance_key_prefix + "__last_update");
      GlobalVariableDel(instance_key_prefix + "__confirmed_time");
      GlobalVariableDel(instance_key_prefix + "__retest_touch");
     }
  }
