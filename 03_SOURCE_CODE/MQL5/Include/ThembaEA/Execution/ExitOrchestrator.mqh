//+------------------------------------------------------------------+
//| ExitOrchestrator.mqh                                              |
//| Themba Adaptive Intraday Engine — Execution                       |
//|                                                                    |
//| TASK-041 (exit-engine wiring, PARTIAL SCOPE, per the user's own        |
//| 2026-07-22 decision after this project's own scoping flagged the         |
//| full spec as considerably larger than the other tasks this sprint):        |
//| composes ExitManager.mqh's break-even, structure/ATR trailing (through       |
//| the never-widen invariant), time stop, and profit-lock formulas into           |
//| ONE per-tick decision for a single open position — the first caller              |
//| any of those formulas has ever had.                                                 |
//|                                                                    |
//| **EXPLICITLY OUT OF SCOPE this task, per the user's own approved         |
//| scope-down (not silently dropped):**                                        |
//| - Target selection (spec section 7's own multi-mechanism candidate           |
//|   sourcing from SwingEngine/MarketStructure) is NOT implemented here --         |
//|   the live target this orchestrator uses is simply whatever TP price             |
//|   the winning strategy proposed at entry (already set on the position               |
//|   via OM_OpenPosition), not a dynamically re-evaluated candidate. Porting             |
//|   V6.37's SetEquilibriumContinuationTarget/ApplyHistoricalM15Target/                   |
//|   FindQualifiedFractalTarget/SR-boundary mechanisms is real, separate,                   |
//|   not-yet-started work.                                                                     |
//| - The exit-priority list's items 1-4 (daily/session risk lock, news             |
//|   safety policy, opposite-confirmed-structure-shift, momentum-failure)              |
//|   are NOT composed here. Daily/weekly loss caps and news blackout ALREADY              |
//|   exist as separate systems (DailyWeeklyLimits.mqh, RegimeGateComposer.mqh)             |
//|   but gate NEW ENTRIES only, not yet an open position's own exit timing;                |
//|   opposite-confirmed-structure-shift has no dedicated detector function                   |
//|   yet; momentum-failure remains unspecified (ExitManager.mqh's own header                  |
//|   note, unchanged).                                                                             |
//| - The giveback guard (EM_ShouldGivebackCloseV637/V811) is intentionally           |
//|   NOT called here, matching ExitManager.mqh's own "default off until               |
//|   Phase 8 evidence" statement — this task does not change that.                       |
//|                                                                    |
//| Array-based/pure core (this file) + a live wrapper in                    |
//| ThembaAdaptiveIntradayEA.mq5 that loads/saves PositionStateTracker.mqh's       |
//| per-position state and calls OrderManager.mqh's OM_ModifyStop/               |
//| OM_ClosePosition — matching every other detection-engine module's own            |
//| "pure core + live wrapper" split in this project.                                   |
//+------------------------------------------------------------------+
#property strict

#include "ExitManager.mqh"
#include "PositionStateTracker.mqh"

struct SExitConfig
  {
   double break_even_min_r;
   double trail_buffer_atr_multiple;
   double atr_trail_multiple;
   int    trail_stale_bars;
   double scalp_max_minutes;
   double time_stop_min_r;
   double profit_lock_trigger_percent;
   double profit_lock_keep_percent;
   double stop_modify_tolerance; // price-unit tolerance below which a
                                  // recomputed stop is NOT resubmitted
                                  // (avoids churning modify requests for a
                                  // sub-point floating-point difference)
  };

struct SExitDecision
  {
   bool     should_close;
   string   close_reason;
   bool     should_modify_stop;
   double   new_stop_price;
  };

//+------------------------------------------------------------------+
//| PURE — evaluates one open position's exit state for the CURRENT tick,  |
//| mutating 'state' in place (caller persists it via PositionStateTracker.  |
//| mqh after this call). 'is_new_completed_bar' gates the                     |
//| bars-since-favorable-swing clock and the swing re-scan so both advance        |
//| exactly once per completed bar, never per tick — matching every other           |
//| once-per-completed-bar cadence in this EA.                                        |
//+------------------------------------------------------------------+
SExitDecision EO_EvaluatePosition(const bool is_long, const double entry_price,
                                   const double initial_stop_price, const double current_stop,
                                   const double current_price, const double target_price,
                                   const double atr, const double &highs[], const double &lows[],
                                   const int swing_depth, const int swing_max_lookback,
                                   const bool is_new_completed_bar, const bool is_scalp_mode,
                                   const double remaining_session_ratio, const double elapsed_minutes,
                                   const SExitConfig &cfg, SPositionExitState &state)
  {
   SExitDecision d;
   d.should_close = false;
   d.close_reason = "";
   d.should_modify_stop = false;
   d.new_stop_price = current_stop;

   double current_r = EM_ComputeR(is_long, entry_price, initial_stop_price, current_price);
   if(current_r > state.peak_r)
      state.peak_r = current_r;

   //--- Advance the "bars since last favorable swing" clock exactly once --
   //--- per newly completed bar, never per tick. ----------------------------
   if(is_new_completed_bar)
     {
      double swing_price;
      bool has_swing = EM_HasFavorableSwingBeyondEntry(is_long, entry_price, highs, lows,
                                                         swing_depth, swing_max_lookback, swing_price);
      bool is_genuinely_new_swing = has_swing &&
         (state.last_swing_price == 0.0 ||
          (is_long ? swing_price > state.last_swing_price : swing_price < state.last_swing_price));
      if(is_genuinely_new_swing)
        {
         state.last_swing_price = swing_price;
         state.bars_since_favorable_swing = 0;
        }
      else
         state.bars_since_favorable_swing++;
     }

   bool is_stale = EM_IsTrailStale(state.bars_since_favorable_swing, cfg.trail_stale_bars);

   //--- 1. Time stop -- closes outright; no further stop management -------
   if(EM_ShouldTimeStop(is_scalp_mode, elapsed_minutes, remaining_session_ratio,
                          cfg.scalp_max_minutes, current_r, cfg.time_stop_min_r, is_stale))
     {
      d.should_close = true;
      d.close_reason = "time_stop";
      return d;
     }

   //--- 2. Break-even arming (sticky once armed -- never un-arms) ---------
   bool has_favorable_swing_now = (state.last_swing_price != 0.0);
   if(!state.break_even_armed &&
      EM_ShouldArmBreakEven(has_favorable_swing_now, current_r, cfg.break_even_min_r))
      state.break_even_armed = true;

   //--- 3. Compose the effective stop: break-even floor, then trailing, ---
   //--- then profit-lock -- each pass through the never-widen invariant. --
   double effective_stop = current_stop;

   if(state.break_even_armed)
      effective_stop = EM_ApplyTrailNeverWiden(is_long, effective_stop, entry_price);

   if(is_stale)
     {
      double atr_fallback = EM_ComputeAtrFallbackTrailStop(is_long, current_price, atr,
                                                              cfg.atr_trail_multiple);
      effective_stop = EM_ApplyTrailNeverWiden(is_long, effective_stop, atr_fallback);
     }
   else if(state.last_swing_price != 0.0)
     {
      double structure_trail = EM_ComputeStructureTrailStop(is_long, state.last_swing_price, atr,
                                                               cfg.trail_buffer_atr_multiple);
      effective_stop = EM_ApplyTrailNeverWiden(is_long, effective_stop, structure_trail);
     }

   if(!state.profit_lock_armed &&
      EM_ShouldArmProfitLock(is_long, entry_price, target_price, current_price,
                               cfg.profit_lock_trigger_percent))
      state.profit_lock_armed = true;

   if(state.profit_lock_armed)
     {
      double profit_lock_stop = EM_ComputeProfitLockStop(is_long, entry_price, current_price,
                                                            cfg.profit_lock_keep_percent);
      effective_stop = EM_ApplyTrailNeverWiden(is_long, effective_stop, profit_lock_stop);
     }

   if(MathAbs(effective_stop - current_stop) > cfg.stop_modify_tolerance)
     {
      d.should_modify_stop = true;
      d.new_stop_price = effective_stop;
     }

   return d;
  }
