//+------------------------------------------------------------------+
//| PositionStateTracker.mqh                                          |
//| Themba Adaptive Intraday Engine — Execution                       |
//|                                                                    |
//| TASK-041 (exit-engine wiring, partial per the user's own 2026-07-22   |
//| scope decision) — persists the per-position running state           |
//| ExitOrchestrator.mqh's formulas need across ticks/bars but do not        |
//| themselves own (peak R, bars-since-last-favorable-swing, the last          |
//| favorable swing price used for structure trailing, and the sticky            |
//| break-even/profit-lock armed flags): none of this is a native MT5              |
//| position property, so it is persisted in native MQL5 global variables            |
//| (double-only), same mechanism as StateManager.mqh/CooldownManager.mqh/             |
//| IntentManager.mqh, keyed by the position's own durable position_id                  |
//| (MT5's POSITION_IDENTIFIER — see OrderManager.mqh's own SOrderOpenResult              |
//| comment for why this, not position_ticket, is the correct durable key                  |
//| for state that must survive a broker-side service re-open).                              |
//|                                                                    |
//| PST_Clear must be called once a position is confirmed closed (the EA's   |
//| own OnTradeTransaction handler) so this project never accumulates an       |
//| unbounded number of orphaned global variables for long-closed positions.     |
//+------------------------------------------------------------------+
#property strict

#include "../Core/KeyEncoding.mqh"

struct SPositionExitState
  {
   double   peak_r;
   int      bars_since_favorable_swing;
   bool     break_even_armed;
   bool     profit_lock_armed;
   double   last_swing_price;
   double   initial_stop_price; // captured ONCE, the first time this
                                  // position is ever evaluated (0.0 means
                                  // "not yet captured" — the live wrapper
                                  // seeds it from the position's CURRENT
                                  // SL at that first evaluation, before any
                                  // trailing has had a chance to move it).
                                  // R must stay pegged to this ORIGINAL
                                  // risk distance, never a shrinking
                                  // already-trailed one.
   // **Added, 2026-07-22 (Codex review finding, eighth round, P1 finding
   // 13):** this position's own intraday_mode AT ENTRY TIME (SCALP vs.
   // DAY_TRADE), captured ONCE the same way initial_stop_price is --
   // previously the exit wrapper applied one CURRENT, global
   // InpTimeStopUsesScalpMode input to every position's time-stop
   // regardless of which mode was actually confirmed when that specific
   // position was opened (or how long ago -- mode can and does change
   // between bars). entry_mode_captured distinguishes "never captured yet"
   // from "captured false" (a plain bool has no such sentinel of its own).
   bool     entry_mode_captured;
   bool     entry_was_scalp_mode;
  };

//+------------------------------------------------------------------+
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** previously concatenated the raw, unbounded server name directly           |
//| into the key -- "bars_since_favorable_swing" is this module's own longest             |
//| field name (27 characters); combined with a realistic server name this                    |
//| already risked exceeding MT5's 63-character global-variable limit,                            |
//| silently losing exit state. Now delegates to KeyEncoding.mqh's                                    |
//| KE_PositionNamespace (fixed-width hash).**                                                            |
//+------------------------------------------------------------------+
string PST_Namespace(const ulong position_id)
  {
   return KE_PositionNamespace("ThembaEA_PST", position_id);
  }

string PST_Key(const ulong position_id, const string field)
  {
   return PST_Namespace(position_id) + "__" + field;
  }

double PST_GetDouble(const ulong position_id, const string field, const double default_value)
  {
   string key = PST_Key(position_id, field);
   if(!GlobalVariableCheck(key))
      return default_value;
   return GlobalVariableGet(key);
  }

//+------------------------------------------------------------------+
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** the write's own success is now returned (previously ignored by           |
//| every caller). PST_Save below propagates a combined failure so a caller             |
//| can at least log a lost exit-state write instead of silently trusting                 |
//| one that did not happen.**                                                                |
//+------------------------------------------------------------------+
bool PST_SetDouble(const ulong position_id, const string field, const double value)
  {
   return KE_SetDoubleChecked(PST_Key(position_id, field), value);
  }

//+------------------------------------------------------------------+
//| Loads the persisted state for 'position_id', defaulting every field    |
//| to its safe "nothing has happened yet" value on first load (peak_r=0,     |
//| no swing seen yet, nothing armed).                                          |
//+------------------------------------------------------------------+
SPositionExitState PST_Load(const ulong position_id)
  {
   SPositionExitState s;
   s.peak_r = PST_GetDouble(position_id, "peak_r", 0.0);
   s.bars_since_favorable_swing = (int)PST_GetDouble(position_id, "bars_since_favorable_swing", 0.0);
   s.break_even_armed = PST_GetDouble(position_id, "break_even_armed", 0.0) != 0.0;
   s.profit_lock_armed = PST_GetDouble(position_id, "profit_lock_armed", 0.0) != 0.0;
   s.last_swing_price = PST_GetDouble(position_id, "last_swing_price", 0.0);
   s.initial_stop_price = PST_GetDouble(position_id, "initial_stop_price", 0.0);
   s.entry_mode_captured = PST_GetDouble(position_id, "entry_mode_captured", 0.0) != 0.0;
   s.entry_was_scalp_mode = PST_GetDouble(position_id, "entry_was_scalp_mode", 0.0) != 0.0;
   return s;
  }

//+------------------------------------------------------------------+
//| Persists 'state' for 'position_id'. Call once per completed-bar        |
//| evaluation after ExitOrchestrator.mqh has updated the in-memory state.     |
//|                                                                    |
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** now returns whether every field was actually persisted, so a           |
//| caller can at least log a lost write (the review's own "assert every                |
//| generated key/write" ask) rather than silently trust one that never                     |
//| happened.**                                                                                  |
//+------------------------------------------------------------------+
bool PST_Save(const ulong position_id, const SPositionExitState &state)
  {
   bool all_ok = true;
   all_ok = PST_SetDouble(position_id, "peak_r", state.peak_r) && all_ok;
   all_ok = PST_SetDouble(position_id, "bars_since_favorable_swing",
                           (double)state.bars_since_favorable_swing) && all_ok;
   all_ok = PST_SetDouble(position_id, "break_even_armed",
                           state.break_even_armed ? 1.0 : 0.0) && all_ok;
   all_ok = PST_SetDouble(position_id, "profit_lock_armed",
                           state.profit_lock_armed ? 1.0 : 0.0) && all_ok;
   all_ok = PST_SetDouble(position_id, "last_swing_price", state.last_swing_price) && all_ok;
   all_ok = PST_SetDouble(position_id, "initial_stop_price", state.initial_stop_price) && all_ok;
   all_ok = PST_SetDouble(position_id, "entry_mode_captured",
                           state.entry_mode_captured ? 1.0 : 0.0) && all_ok;
   all_ok = PST_SetDouble(position_id, "entry_was_scalp_mode",
                           state.entry_was_scalp_mode ? 1.0 : 0.0) && all_ok;
   return all_ok;
  }

//+------------------------------------------------------------------+
//| Wipes every field for 'position_id' — call once a position is          |
//| confirmed closed (OnTradeTransaction), so this project never                |
//| accumulates unbounded orphaned global variables for long-closed                |
//| positions. Also used by tests to leave no residue.                                |
//+------------------------------------------------------------------+
void PST_Clear(const ulong position_id)
  {
   PST_SetDouble(position_id, "peak_r", 0.0);
   PST_SetDouble(position_id, "bars_since_favorable_swing", 0.0);
   PST_SetDouble(position_id, "break_even_armed", 0.0);
   PST_SetDouble(position_id, "profit_lock_armed", 0.0);
   PST_SetDouble(position_id, "last_swing_price", 0.0);
   PST_SetDouble(position_id, "initial_stop_price", 0.0);
   PST_SetDouble(position_id, "entry_mode_captured", 0.0);
   PST_SetDouble(position_id, "entry_was_scalp_mode", 0.0);
  }
