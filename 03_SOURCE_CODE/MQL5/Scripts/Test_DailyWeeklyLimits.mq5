//+------------------------------------------------------------------+
//| Test_DailyWeeklyLimits.mq5                                        |
//| Themba Adaptive Intraday Engine — TASK-008 compile/logic test      |
//|                                                                    |
//| Exercises DailyWeeklyLimits.mqh, EquityPeakManager.mqh, and         |
//| DrawdownController.mqh against the live connected account's real    |
//| equity. Every "dwl_"/"epm_"-prefixed account-wide field this        |
//| script touches is deleted at the end so a real run leaves no        |
//| residue, same discipline as Test_StateManager.mq5.                  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Risk/DailyWeeklyLimits.mqh"
#include "../Include/ThembaEA/Risk/EquityPeakManager.mqh"
#include "../Include/ThembaEA/Risk/DrawdownController.mqh"

int g_pass = 0;
int g_fail = 0;

void Check(const string label, const bool condition)
  {
   if(condition)
     {
      PrintFormat("PASS: %s", label);
      g_pass++;
     }
   else
     {
      PrintFormat("FAIL: %s", label);
      g_fail++;
     }
  }

bool NearlyEqual(const double a, const double b, const double tol = 0.01)
  {
   return MathAbs(a - b) <= tol;
  }

void CleanupTestFields()
  {
   SM_DeleteAccountField("dwl_daily_start_equity");
   SM_DeleteAccountField("dwl_daily_reset_time");
   SM_DeleteAccountField("dwl_weekly_start_equity");
   SM_DeleteAccountField("dwl_weekly_reset_time");
   SM_DeleteAccountField("dwl_last_balance_deal_ticket");
   SM_DeleteAccountField("epm_daily_peak_equity");
   SM_DeleteAccountField("epm_daily_peak_reset_time");
   SM_DeleteAccountField("epm_account_peak_equity");
   SM_ReleaseAccountLock();
  }

void OnStart()
  {
   Print("=== TASK-008 DailyWeeklyLimits / EquityPeakManager / DrawdownController test start ===");
   CleanupTestFields(); // clean slate before testing

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   PrintFormat("INFO: live account equity = %.2f", equity);

   //--- 1. Daily baseline: first call rebases -------------------------
   DWL_EnsureDailyBaseline();
   double daily_start = SM_GetAccountDouble("dwl_daily_start_equity", -1.0);
   Check("daily baseline set after first EnsureDailyBaseline call",
         daily_start > 0.0);
   datetime daily_reset_1 = (datetime)SM_GetAccountDouble("dwl_daily_reset_time", 0.0);
   Check("daily reset time set to today's boundary",
         daily_reset_1 == SN_CurrentDailyBoundary());

   //--- 2. Second call same day is a no-op -----------------------------
   DWL_EnsureDailyBaseline();
   datetime daily_reset_2 = (datetime)SM_GetAccountDouble("dwl_daily_reset_time", 0.0);
   Check("second same-day call does not change the reset timestamp",
         daily_reset_1 == daily_reset_2);

   //--- 3. Daily change percent -----------------------------------------
   double change_pct;
   bool change_ok = DWL_GetDailyChangePercent(change_pct);
   Check("DWL_GetDailyChangePercent succeeds once a baseline exists", change_ok);
   PrintFormat("INFO: daily change percent = %.4f%%", change_pct);

   //--- 4. Simulate a stale (yesterday) boundary -> forces a rebase ----
   SM_SetAccountDouble("dwl_daily_reset_time", (double)(SN_CurrentDailyBoundary() - 86400));
   DWL_EnsureDailyBaseline();
   datetime daily_reset_3 = (datetime)SM_GetAccountDouble("dwl_daily_reset_time", 0.0);
   Check("a stale (yesterday) reset timestamp forces a fresh rebase",
         daily_reset_3 == SN_CurrentDailyBoundary());

   //--- 5. Weekly baseline: same pattern --------------------------------
   DWL_EnsureWeeklyBaseline();
   double weekly_start = SM_GetAccountDouble("dwl_weekly_start_equity", -1.0);
   Check("weekly baseline set after first EnsureWeeklyBaseline call",
         weekly_start > 0.0);
   datetime weekly_reset_1 = (datetime)SM_GetAccountDouble("dwl_weekly_reset_time", 0.0);
   Check("weekly reset time set to the current weekly boundary",
         weekly_reset_1 == SN_CurrentWeeklyBoundary());

   DWL_EnsureWeeklyBaseline();
   datetime weekly_reset_2 = (datetime)SM_GetAccountDouble("dwl_weekly_reset_time", 0.0);
   Check("second same-week call does not change the reset timestamp",
         weekly_reset_1 == weekly_reset_2);

   //--- 6. Loss-breach detection using artificial baselines -------------
   // Force an obviously-breached baseline: start equity double the
   // current equity means change_percent is roughly -50%.
   SM_SetAccountDouble("dwl_daily_start_equity", equity * 2.0);
   double breach_change;
   bool breached = DWL_IsDailyLossBreached(1.0, breach_change);
   Check("an artificially inflated start-equity baseline reports a breach",
         breached);
   Check("reported change percent is clearly negative for the breach case",
         breach_change < -1.0);

   // Restore to a non-breaching baseline: start == current equity.
   SM_SetAccountDouble("dwl_daily_start_equity", equity);
   double no_breach_change;
   bool not_breached = DWL_IsDailyLossBreached(1.0, no_breach_change) == false;
   Check("start equity == current equity does not report a breach",
         not_breached);

   //--- 7. Cash-flow adjustment does not crash --------------------------
   DWL_ApplyCashFlowAdjustments();
   Check("DWL_ApplyCashFlowAdjustments completes without crashing", true);

   //--- 8. EquityPeakManager: daily peak ---------------------------------
   EPM_UpdateDailyPeak();
   double daily_peak_1 = SM_GetAccountDouble("epm_daily_peak_equity", -1.0);
   Check("daily peak set after first UpdateDailyPeak call", daily_peak_1 >= equity - 0.01);

   EPM_UpdateDailyPeak();
   double daily_peak_2 = SM_GetAccountDouble("epm_daily_peak_equity", -1.0);
   Check("daily peak never decreases across repeated calls",
         daily_peak_2 >= daily_peak_1 - 0.0001);

   double giveback_pct;
   bool giveback_ok = EPM_GetDailyGivebackPercent(giveback_pct);
   Check("EPM_GetDailyGivebackPercent succeeds once a peak exists", giveback_ok);
   Check("daily giveback percent is non-negative", giveback_pct >= 0.0);

   //--- 9. Daily giveback arming -----------------------------------------
   // Artificially low daily_start_equity makes the peak look like a huge
   // gain relative to it, which must arm at a modest threshold.
   bool armed_low_start = EPM_IsDailyGivebackArmed(1.0, 1.0);
   Check("giveback arms when daily_start_equity is artificially tiny",
         armed_low_start);

   double current_peak = SM_GetAccountDouble("epm_daily_peak_equity", equity);
   bool not_armed = EPM_IsDailyGivebackArmed(current_peak, 1.0) == false;
   Check("giveback does NOT arm when daily_start_equity equals the peak itself",
         not_armed);

   //--- 10. EquityPeakManager: all-time account peak ----------------------
   EPM_UpdateAccountPeak();
   double account_peak_1 = SM_GetAccountDouble("epm_account_peak_equity", -1.0);
   Check("account peak set after first UpdateAccountPeak call",
         account_peak_1 >= equity - 0.01);

   double dd_1 = EPM_GetCurrentDrawdownPercent();
   Check("drawdown percent is ~0 immediately after the peak is set to current equity",
         dd_1 < 0.01);

   //--- 11. Explicit reset ---------------------------------------------
   EPM_ExplicitResetAccountPeak();
   double account_peak_2 = SM_GetAccountDouble("epm_account_peak_equity", -1.0);
   Check("explicit reset sets the account peak to current equity",
         NearlyEqual(account_peak_2, AccountInfoDouble(ACCOUNT_EQUITY), 0.5));

   //--- 12. DrawdownController — pure function, hand-verified -----------
   Check("DC_ComputeRiskMultiplier(0,10,0.25) == 1.0",
         NearlyEqual(DC_ComputeRiskMultiplier(0.0, 10.0, 0.25), 1.0));
   Check("DC_ComputeRiskMultiplier(5,10,0.25) == 0.5",
         NearlyEqual(DC_ComputeRiskMultiplier(5.0, 10.0, 0.25), 0.5));
   Check("DC_ComputeRiskMultiplier(10,10,0.25) clamps to min 0.25",
         NearlyEqual(DC_ComputeRiskMultiplier(10.0, 10.0, 0.25), 0.25));
   Check("DC_ComputeRiskMultiplier(20,10,0.25) clamps to min 0.25 (beyond range)",
         NearlyEqual(DC_ComputeRiskMultiplier(20.0, 10.0, 0.25), 0.25));
   Check("DC_ComputeRiskMultiplier(-5,10,0.25) clamps to max 1.0",
         NearlyEqual(DC_ComputeRiskMultiplier(-5.0, 10.0, 0.25), 1.0));

   //--- Cleanup: leave no residue on the real account -------------------
   CleanupTestFields();
   Check("daily start equity field removed after cleanup",
         !SM_AccountFieldExists("dwl_daily_start_equity"));
   Check("account peak field removed after cleanup",
         !SM_AccountFieldExists("epm_account_peak_equity"));

   PrintFormat("=== TASK-008 test complete: %d passed, %d failed ===", g_pass, g_fail);
  }
