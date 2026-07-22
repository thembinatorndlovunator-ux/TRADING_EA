//+------------------------------------------------------------------+
//| ExitManager.mqh                                                   |
//| Themba Adaptive Intraday Engine — Execution                        |
//|                                                                    |
//| TASK-030 — begins Phase 8. Every individual exit-management FORMULA  |
//| from TASK-002_PHASE2_SPECIFICATION.md section 7, built and tested       |
//| standalone as pure functions: break-even arming, structure trailing      |
//| (long/short), ATR-fallback trailing, the "never widen a stop"              |
//| invariant, time stop, profit-lock (with the broker-min-stop partial-         |
//| lock recheck), and both giveback-guard models (V6.37-style percent-of-         |
//| peak, V8.11-style absolute-R-floor).                                             |
//|                                                                    |
//| Matches TASK-026 OrderManager.mqh's precedent exactly: build and test    |
//| every formula standalone first; wiring these into a live position's        |
//| actual SL/TP (requiring an orchestrating "exit priority" function           |
//| composing this module with daily/session risk lock, news safety,              |
//| opposite-confirmed-structure-shift, and live position enumeration) is           |
//| explicitly deferred to a follow-up task — see                                     |
//| TASK-030_EXIT_MANAGER.md's Scope Boundary section.                                  |
//|                                                                    |
//| **NOT BUILT — a genuine spec gap, not a scoping choice:** section 7's   |
//| exit-priority item 4, "momentum-failure exit," has no formula/            |
//| definition anywhere in TASK-002_PHASE2_SPECIFICATION.md — it appears        |
//| exactly once, in the priority list itself, with nothing else defining          |
//| what "momentum failure" means mathematically. This module does not             |
//| invent one; it is flagged here as needing its own specification work             |
//| before any implementation is attempted, per this project's "never                 |
//| invent an unspecified formula" discipline.                                          |
//+------------------------------------------------------------------+
#property strict

#include "../Structure/SwingEngine.mqh"

//+------------------------------------------------------------------+
//| R = the position's current open gain/loss expressed as a multiple of  |
//| its own initial risk distance (entry - initial_stop for a long, the     |
//| mirror for a short) — the common unit every exit formula below is         |
//| expressed in, per section 7's "InpBreakEvenMinR"/"InpTimeStopMinR"/          |
//| "InpGivebackArmRR" etc. all being R-denominated. Returns 0.0 (never          |
//| a divide-by-zero) if initial_risk_distance is non-positive (a stopless        |
//| or malformed position — a caller should never reach here in that case,           |
//| but this function fails safe rather than crashing).                                |
//+------------------------------------------------------------------+
double EM_ComputeR(const bool is_long, const double entry_price, const double initial_stop_price,
                    const double current_price)
  {
   double risk_distance = is_long ? (entry_price - initial_stop_price)
                                    : (initial_stop_price - entry_price);
   if(risk_distance <= 0.0)
      return 0.0;

   double favor_distance = is_long ? (current_price - entry_price) : (entry_price - current_price);
   return favor_distance / risk_distance;
  }

//+------------------------------------------------------------------+
//| True iff SwingEngine's canonical pivot predicate confirms a swing     |
//| pivot (low for a long, high for a short — "swing in favor" per          |
//| section 7's precise directional definition) strictly beyond entry in       |
//| the position's favor, within the given lookback. Reuses                      |
//| SwingEngine.mqh's array-based core directly — no pivot math is                 |
//| re-derived here, matching this project's "one pivot predicate, reused          |
//| everywhere" rule (ledger item 1).                                                 |
//+------------------------------------------------------------------+
bool EM_HasFavorableSwingBeyondEntry(const bool is_long, const double entry_price,
                                      const double &highs[], const double &lows[],
                                      const int depth, const int max_lookback,
                                      double &swing_price)
  {
   swing_price = 0.0;
   int found_index;
   if(is_long)
     {
      if(!SE_FindNearestConfirmedSwingLowArray(lows, 0, depth, max_lookback, found_index))
         return false;
      swing_price = lows[found_index];
      return swing_price > entry_price;
     }
   else
     {
      if(!SE_FindNearestConfirmedSwingHighArray(highs, 0, depth, max_lookback, found_index))
         return false;
      swing_price = highs[found_index];
      return swing_price < entry_price;
     }
  }

//+------------------------------------------------------------------+
//| Break-even arming, per section 7: "arms when SwingEngine confirms a   |
//| new swing pivot beyond the entry price in the trade's favor, AND the     |
//| position's actual fill price has moved at least InpBreakEvenMinR          |
//| (default 0.5R) in favor. Both conditions required."                          |
//+------------------------------------------------------------------+
bool EM_ShouldArmBreakEven(const bool has_favorable_swing_beyond_entry, const double current_r,
                           const double min_r)
  {
   return has_favorable_swing_beyond_entry && (current_r >= min_r);
  }

//+------------------------------------------------------------------+
//| Structure trailing stop, per section 7's directional formulas:        |
//| Long: most_recent_confirmed_swing_low_in_favor - ATR*InpTrailBuffer.     |
//| Short: most_recent_confirmed_swing_high_in_favor + ATR*InpTrailBuffer.     |
//| 'swing_price_in_favor' is the caller-supplied swing price from              |
//| EM_HasFavorableSwingBeyondEntry (or an equivalent fresh lookup) — this        |
//| function does not look it up itself, keeping this a pure scalar formula.        |
//+------------------------------------------------------------------+
double EM_ComputeStructureTrailStop(const bool is_long, const double swing_price_in_favor,
                                     const double atr, const double trail_buffer_atr_multiple)
  {
   return is_long ? (swing_price_in_favor - atr * trail_buffer_atr_multiple)
                   : (swing_price_in_favor + atr * trail_buffer_atr_multiple);
  }

//+------------------------------------------------------------------+
//| ATR-fallback trailing stop, per section 7: used when no new confirmed  |
//| favorable swing has formed within InpTrailStaleBars bars since the       |
//| last update (see EM_IsTrailStale). Long: current_price -                     |
//| ATR*InpATRTrailMultiple. Short: current_price + ATR*InpATRTrailMultiple.       |
//+------------------------------------------------------------------+
double EM_ComputeAtrFallbackTrailStop(const bool is_long, const double current_price,
                                       const double atr, const double atr_trail_multiple)
  {
   return is_long ? (current_price - atr * atr_trail_multiple)
                   : (current_price + atr * atr_trail_multiple);
  }

//+------------------------------------------------------------------+
//| True iff InpTrailStaleBars bars have elapsed since the last confirmed  |
//| favorable swing — the ONE staleness definition section 7 states is        |
//| shared by both the ATR-trailing fallback and the time stop's "no             |
//| progress" clock. 'bars_since_last_favorable_swing' is caller-tracked           |
//| per-position state (mirrors SRegimeHysteresisState's caller-owned                |
//| pattern in MarketRegimeEngine.mqh) — this module does not persist                 |
//| anything itself.                                                                     |
//+------------------------------------------------------------------+
bool EM_IsTrailStale(const int bars_since_last_favorable_swing, const int trail_stale_bars)
  {
   return bars_since_last_favorable_swing >= trail_stale_bars;
  }

//+------------------------------------------------------------------+
//| Enforces section 8's "a stop is never widened merely to avoid a       |
//| loss — SL modification is only ever loss-reducing/tightening... never    |
//| a distance increase" invariant. Returns the tighter of the position's         |
//| CURRENT stop and a CANDIDATE new stop, regardless of which trailing              |
//| formula produced the candidate — this is the single choke point every            |
//| trail-stop update (structure or ATR-fallback) must pass through before              |
//| ever being sent to OrderManager.mqh, so a caller can never accidentally              |
//| widen a stop by calling the wrong trailing formula at the wrong moment.                |
//+------------------------------------------------------------------+
double EM_ApplyTrailNeverWiden(const bool is_long, const double current_stop,
                                const double candidate_stop)
  {
   return is_long ? MathMax(current_stop, candidate_stop) : MathMin(current_stop, candidate_stop);
  }

//+------------------------------------------------------------------+
//| Time-stop duration ceiling, per section 7: Scalp mode uses               |
//| InpScalpMaxMinutes (default 60) elapsed; Day-trade mode uses the            |
//| mode's OWN remaining-session-time ratio (SessionManager.mqh's                 |
//| SN_GetSessionMinutesRemaining, section 1 item 4) reaching 0 — not                |
//| re-derived here, the ratio is a caller-supplied input.                              |
//|                                                                    |
//| **Added, 2026-07-22 (Codex review finding, seventh round, P0 finding    |
//| 8): 'session_ratio_known' -- when the caller could not determine the        |
//| session-remaining ratio at all (e.g. a calendar lookup failure), the           |
//| ratio must NOT be silently treated as 0.0/"duration exceeded". That               |
//| coercion previously let a data-read failure force an unintended                     |
//| day-trade close. An unknown session state means this duration check                    |
//| cannot fire at all -- the intraday boundary close (IntradayCloseManager.mqh,               |
//| a pure function of server time, no session-calendar dependency) remains                     |
//| the real safety net regardless.**                                                               |
//+------------------------------------------------------------------+
bool EM_IsTimeStopDurationExceeded(const bool is_scalp_mode, const double elapsed_minutes,
                                    const double remaining_session_ratio,
                                    const bool session_ratio_known,
                                    const double scalp_max_minutes)
  {
   if(is_scalp_mode)
      return elapsed_minutes >= scalp_max_minutes;
   if(!session_ratio_known)
      return false; // unknown session state must never force an unintended close
   return remaining_session_ratio <= 0.0;
  }

//+------------------------------------------------------------------+
//| Full time stop per section 7: closes if ALL of (a) the mode's           |
//| duration ceiling is exceeded, (b) current R < InpTimeStopMinR                |
//| (default 0.3R — a trade that has already made good progress is NOT             |
//| time-stopped merely for running long), (c) no fresh confirmed                     |
//| favorable swing within InpTrailStaleBars (the SAME staleness definition            |
//| as the ATR-trailing fallback — section 7's "one consistent 'no progress'             |
//| clock").                                                                                |
//+------------------------------------------------------------------+
bool EM_ShouldTimeStop(const bool is_scalp_mode, const double elapsed_minutes,
                        const double remaining_session_ratio, const bool session_ratio_known,
                        const double scalp_max_minutes, const double current_r,
                        const double time_stop_min_r, const bool is_stale)
  {
   if(!EM_IsTimeStopDurationExceeded(is_scalp_mode, elapsed_minutes, remaining_session_ratio,
                                      session_ratio_known, scalp_max_minutes))
      return false;
   if(current_r >= time_stop_min_r)
      return false;
   return is_stale;
  }

//+------------------------------------------------------------------+
//| Profit-lock arming, per section 7: "arms once price covers                |
//| InpProfitLockTriggerPercent (default 70%) of the distance from entry         |
//| (actual fill) to the current target." Returns false (never divides by         |
//| zero) if the entry-to-target distance is non-positive (a malformed               |
//| target on the wrong side of entry — a caller should never reach here in            |
//| that case).                                                                            |
//+------------------------------------------------------------------+
bool EM_ShouldArmProfitLock(const bool is_long, const double entry_price, const double target_price,
                            const double current_price, const double trigger_percent)
  {
   double total_distance = is_long ? (target_price - entry_price) : (entry_price - target_price);
   if(total_distance <= 0.0)
      return false;

   double covered = is_long ? (current_price - entry_price) : (entry_price - current_price);
   double covered_percent = 100.0 * covered / total_distance;
   return covered_percent >= trigger_percent;
  }

//+------------------------------------------------------------------+
//| Profit-lock stop price, per section 7: "raises the stop to lock          |
//| InpProfitLockKeepPercent (default 50%) of the current open gain."           |
//+------------------------------------------------------------------+
double EM_ComputeProfitLockStop(const bool is_long, const double entry_price,
                                 const double current_price, const double keep_percent)
  {
   double open_gain = is_long ? (current_price - entry_price) : (entry_price - current_price);
   double locked_gain = open_gain * keep_percent / 100.0;
   return is_long ? (entry_price + locked_gain) : (entry_price - locked_gain);
  }

//+------------------------------------------------------------------+
//| Partial-lock recheck, per section 7: "If the broker's minimum-stop-      |
//| distance enforcement moves the resulting stop further than intended,       |
//| the engine re-checks whether the actually-achieved lock still clears          |
//| InpProfitLockMinKeepPercent (default 30%); below that floor, the                 |
//| attempt is logged as a partial-lock warning, not silently accepted as              |
//| a full lock." 'actual_stop_price' is whatever the broker actually                    |
//| accepted (post RM_ValidateStopDistance-style floor widening in                          |
//| OrderManager.mqh/RiskManager.mqh, applied by whichever caller submits                     |
//| the stop-modification) — this function only judges the result, it does                     |
//| not perform the modification itself.                                                            |
//+------------------------------------------------------------------+
bool EM_ProfitLockClearsMinFloor(const bool is_long, const double entry_price,
                                  const double current_price, const double actual_stop_price,
                                  const double min_keep_percent)
  {
   double open_gain = is_long ? (current_price - entry_price) : (entry_price - current_price);
   if(open_gain <= 0.0)
      return false;

   double actual_locked_gain = is_long ? (actual_stop_price - entry_price)
                                         : (entry_price - actual_stop_price);
   double actual_keep_percent = 100.0 * actual_locked_gain / open_gain;
   return actual_keep_percent >= min_keep_percent;
  }

//+------------------------------------------------------------------+
//| Giveback guard — V6.37 model, per section 7's stated bounds: arm at   |
//| max(0.25, InpGivebackArmRR) R; giveback percentage clamped [10,90]%       |
//| (default 60%) of the position's own PEAK R; close-trigger floored at        |
//| 0.05R (never triggers a close below 0.05R of locked-in profit, even if          |
//| the percentage math would imply an earlier trigger). "peak_r" is                  |
//| caller-tracked running-maximum state (this module is stateless, matching             |
//| every other exit formula here). **Default OFF until Phase 8 evidence, per              |
//| section 7 — this function exists but no caller in this project invokes                   |
//| it yet; that is intentional, not a gap.**                                                    |
//+------------------------------------------------------------------+
bool EM_ShouldGivebackCloseV637(const double current_r, const double peak_r, const double arm_rr,
                                 const double giveback_percent, const double close_trigger_floor_r)
  {
   double effective_arm = MathMax(0.25, arm_rr);
   if(peak_r < effective_arm)
      return false;

   double clamped_percent = MathMax(10.0, MathMin(90.0, giveback_percent));
   double trigger_r = peak_r * (1.0 - clamped_percent / 100.0);
   if(trigger_r < close_trigger_floor_r)
      trigger_r = close_trigger_floor_r;

   return current_r <= trigger_r;
  }

//+------------------------------------------------------------------+
//| Giveback guard — V8.11 model, per section 7's stated bounds: arm at   |
//| max(0.3, InpGivebackArmR) R; close if current R drops back to floor        |
//| max(0.0, InpGivebackFloorR) R — an absolute R floor, not a percentage-        |
//| of-peak (the structural difference from the V6.37 model above, per               |
//| section 7's "both models built behind one ProfitGivebackGuard interface,             |
//| default off until Phase 8 evidence"). **Default OFF, same statement as                 |
//| the V6.37 variant above.**                                                                 |
//+------------------------------------------------------------------+
bool EM_ShouldGivebackCloseV811(const double current_r, const double peak_r, const double arm_r,
                                 const double floor_r)
  {
   double effective_arm = MathMax(0.3, arm_r);
   if(peak_r < effective_arm)
      return false;

   double effective_floor = MathMax(0.0, floor_r);
   return current_r <= effective_floor;
  }
