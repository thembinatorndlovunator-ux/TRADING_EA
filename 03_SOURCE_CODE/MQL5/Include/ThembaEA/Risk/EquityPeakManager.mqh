//+------------------------------------------------------------------+
//| EquityPeakManager.mqh                                             |
//| Themba Adaptive Intraday Engine — Risk                             |
//|                                                                    |
//| Persisted equity-peak tracking, per                                 |
//| TASK-002_PHASE2_SPECIFICATION.md section 8: a DAILY peak (resets    |
//| each daily boundary, drives the daily equity-peak giveback           |
//| control) and an ALL-TIME account peak (reset only by an explicit,   |
//| documented operator action, never automatically — drives             |
//| current_drawdown_percent for DrawdownController). These are two      |
//| distinct concepts with two distinct reset rules, per section 8's     |
//| explicit correction of an earlier draft that conflated them.         |
//|                                                                    |
//| Persisted fields share StateManager's account-wide namespace with   |
//| DailyWeeklyLimits.mqh, prefixed "epm_" to avoid collision.            |
//|                                                                    |
//| Deliberately self-sufficient: this module tracks its OWN daily       |
//| reset timestamp rather than depending on DailyWeeklyLimits' reset    |
//| having already run first — avoids an inter-module ordering           |
//| dependency, per master-prompt section 22's "clear responsibility"    |
//| rule.                                                                |
//+------------------------------------------------------------------+
#property strict

#include "../Core/StateManager.mqh"
#include "../Market/SessionManager.mqh"

//+------------------------------------------------------------------+
//| Rebase the daily peak to current equity if the daily boundary has   |
//| been crossed since EquityPeakManager's own last recorded reset.      |
//| Idempotent within the same day.                                      |
//|                                                                    |
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 4):** the two fields (peak equity, reset time) are now written under        |
//| ONE SM_SetAccountDoublesBatch lock hold, with the reset time -- the           |
//| field DWL-style callers key their "is this fresh?" retry decision on --          |
//| written last, per that function's own corrected atomicity contract.               |
//| Returns the write's success so callers can propagate a persistence               |
//| failure as "peak state unknown", not "no reset needed" (see                          |
//| EPM_UpdateDailyPeak's own header for the fail-closed callers).                          |
//+------------------------------------------------------------------+
bool EPM_EnsureDailyPeakBaseline()
  {
   datetime last_reset = (datetime)SM_GetAccountDouble("epm_daily_peak_reset_time", 0.0);
   if(last_reset != 0 && !SN_DailyBoundaryCrossed(last_reset))
      return true; // already rebased for today — no-op, not a failure

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   string fields[2] = {"epm_daily_peak_equity", "epm_daily_peak_reset_time"};
   double values[2] = {equity, (double)SN_CurrentDailyBoundary()};
   return SM_SetAccountDoublesBatch(fields, values);
  }

//+------------------------------------------------------------------+
//| Updates the daily peak to max(peak, current equity). Calls           |
//| EPM_EnsureDailyPeakBaseline() first (cheap — a single stored-value   |
//| read) so this is always safe to call on every tick without a          |
//| separate reset step elsewhere.                                       |
//|                                                                    |
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 4):** now uses SM_SetAccountDoubleIfGreater, which holds the account          |
//| lock across the read-compare-write as ONE critical section -- the                |
//| previous separate SM_GetAccountDouble() read followed by a conditional               |
//| SM_SetAccountDouble() call let two concurrent instances interleave so a                 |
//| lower equity reading could overwrite an already-persisted higher peak.                     |
//| Also fixed: this and EPM_UpdateAccountPeak were previously only invoked                       |
//| from EvaluateAndJournal's own once-per-completed-bar path -- moved to run                         |
//| every tick from OnTick directly, per section 8's own peak-tracking                                    |
//| contract. Returns false if the peak state could not be verified/updated                                   |
//| this tick (lock timeout) — callers must treat this as "unknown", never as                                    |
//| "no update needed".                                                                                              |
//+------------------------------------------------------------------+
bool EPM_UpdateDailyPeak()
  {
   if(!EPM_EnsureDailyPeakBaseline())
      return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   return SM_SetAccountDoubleIfGreater("epm_daily_peak_equity", equity);
  }

//+------------------------------------------------------------------+
//| Daily giveback percent: 100 * (daily_peak - current_equity) /       |
//| daily_peak, per section 8's corrected "genuinely track a peak"       |
//| fix. Returns false (undefined) if no daily peak has been recorded   |
//| yet (call EPM_UpdateDailyPeak first).                                |
//+------------------------------------------------------------------+
bool EPM_GetDailyGivebackPercent(double &giveback_percent)
  {
   giveback_percent = 0.0;
   double peak = SM_GetAccountDouble("epm_daily_peak_equity", 0.0);
   if(peak <= 0.0)
      return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   giveback_percent = 100.0 * (peak - equity) / peak;
   if(giveback_percent < 0.0)
      giveback_percent = 0.0; // equity currently AT the peak — no giveback yet
   return true;
  }

//+------------------------------------------------------------------+
//| True iff the daily giveback control has armed: the daily peak has   |
//| risen at least arm_percent above 'daily_start_equity' (the caller    |
//| supplies this — owned by DailyWeeklyLimits, not duplicated here).   |
//+------------------------------------------------------------------+
bool EPM_IsDailyGivebackArmed(const double daily_start_equity, const double arm_percent)
  {
   if(daily_start_equity <= 0.0)
      return false;

   double peak = SM_GetAccountDouble("epm_daily_peak_equity", 0.0);
   double arm_measure = 100.0 * (peak - daily_start_equity) / daily_start_equity;
   return arm_measure >= arm_percent;
  }

//+------------------------------------------------------------------+
//| Updates the ALL-TIME account peak to max(peak, current equity).      |
//| Never auto-resets — only EPM_ExplicitResetAccountPeak() below         |
//| changes it downward, and that is an explicit, logged operator        |
//| action per section 8, never called by ordinary risk logic.           |
//|                                                                    |
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 4):** same atomic read-compare-write and every-tick cadence fix as           |
//| EPM_UpdateDailyPeak above — see that function's own header.                     |
//+------------------------------------------------------------------+
bool EPM_UpdateAccountPeak()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   return SM_SetAccountDoubleIfGreater("epm_account_peak_equity", equity);
  }

//+------------------------------------------------------------------+
//| current_drawdown_percent, per section 8: 100 * (account_peak -      |
//| current_equity) / account_peak, floored at 0 (equity above the      |
//| still-stale peak — which EPM_UpdateAccountPeak should have already   |
//| corrected — never reports a negative drawdown).                      |
//+------------------------------------------------------------------+
double EPM_GetCurrentDrawdownPercent()
  {
   double peak = SM_GetAccountDouble("epm_account_peak_equity", 0.0);
   if(peak <= 0.0)
      return 0.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = 100.0 * (peak - equity) / peak;
   return dd < 0.0 ? 0.0 : dd;
  }

//+------------------------------------------------------------------+
//| Explicit, operator-initiated reset of the all-time account peak to  |
//| current equity — per section 8, "reset only by an explicit,          |
//| documented operator action, never automatically." Ordinary risk      |
//| logic must never call this.                                          |
//+------------------------------------------------------------------+
void EPM_ExplicitResetAccountPeak()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   SM_SetAccountDouble("epm_account_peak_equity", equity);
  }
