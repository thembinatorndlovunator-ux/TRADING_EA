//+------------------------------------------------------------------+
//| Test_SessionManager.mq5                                           |
//| Themba Adaptive Intraday Engine — TASK-006 compile/logic test      |
//|                                                                    |
//| Boundary-function checks are deliberately not hardcoded against    |
//| "the current time" (that would be flaky depending on when this is  |
//| run) — instead each expected value is independently recomputed in  |
//| this script using the same MqlDateTime approach the module itself  |
//| uses, and compared against the module's actual output. A mismatch  |
//| means the two derivations disagree, not that "now" was unlucky.    |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Market/SessionManager.mqh"

input string InpTestSymbol = "EURUSD";

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

void OnStart()
  {
   Print("=== TASK-006 SessionManager test start ===");

   //--- 1. Daily boundary ------------------------------------------
   datetime daily = SN_CurrentDailyBoundary();
   MqlDateTime daily_dt;
   TimeToStruct(daily, daily_dt);
   Check("daily boundary has hour=0", daily_dt.hour == 0);
   Check("daily boundary has min=0", daily_dt.min == 0);
   Check("daily boundary has sec=0", daily_dt.sec == 0);
   Check("daily boundary is not after now", daily <= TimeTradeServer());

   Check("daily boundary crossed when last reset was yesterday",
         SN_DailyBoundaryCrossed(daily - 86400));
   Check("daily boundary NOT crossed when last reset is today's boundary itself",
         SN_DailyBoundaryCrossed(daily) == false);
   Check("daily boundary NOT crossed when last reset is later today",
         SN_DailyBoundaryCrossed(TimeTradeServer()) == false);

   //--- 2. Weekly boundary -------------------------------------------
   datetime weekly = SN_CurrentWeeklyBoundary();
   MqlDateTime weekly_dt;
   TimeToStruct(weekly, weekly_dt);
   Check("weekly boundary falls on a Monday", weekly_dt.day_of_week == 1);
   Check("weekly boundary has hour=0", weekly_dt.hour == 0);
   Check("weekly boundary has min=5", weekly_dt.min == 5);
   Check("weekly boundary has sec=0", weekly_dt.sec == 0);
   Check("weekly boundary is not after now", weekly <= TimeTradeServer());

   Check("weekly boundary crossed when last reset was 8 days ago",
         SN_WeeklyBoundaryCrossed(weekly - 8 * 86400));
   Check("weekly boundary NOT crossed when last reset is this boundary itself",
         SN_WeeklyBoundaryCrossed(weekly) == false);

   //--- 3. Intraday boundary — recompute expectation independently ---
   MqlDateTime now_dt;
   TimeToStruct(TimeTradeServer(), now_dt);
   int now_minutes = now_dt.hour * 60 + now_dt.min;

   // boundary_hour/minute = 0:00 must always be "past" (any time of day
   // is at or after midnight).
   Check("intraday boundary 00:00 is always past",
         SN_IsPastIntradayBoundary(0, 0));

   // Recompute the same predicate independently for the module's own
   // default (23:45) and compare, rather than assuming the outcome.
   int default_boundary_minutes = 23 * 60 + 45;
   bool expected_default = (now_minutes >= default_boundary_minutes);
   Check("intraday boundary default (23:45) matches independent recomputation",
         SN_IsPastIntradayBoundary() == expected_default);
   Check("intraday boundary explicit (23,45) matches independent recomputation",
         SN_IsPastIntradayBoundary(23, 45) == expected_default);

   // A boundary exactly at "now" (to the minute) must be considered past
   // (the function uses >=, not >).
   Check("intraday boundary set to the current minute is past",
         SN_IsPastIntradayBoundary(now_dt.hour, now_dt.min));

   //--- 4. Session-time-remaining for a real symbol -------------------
   double ratio;
   bool session_ok = SN_GetSessionMinutesRemaining(InpTestSymbol, ratio);
   if(session_ok)
     {
      Check(StringFormat("session ratio for '%s' is within [0,1]", InpTestSymbol),
            ratio >= 0.0 && ratio <= 1.0);
     }
   else
     {
      PrintFormat("NOTE: '%s' reports no trading session for today (dow=%d) — "
                  "this is a valid outcome on a weekend/holiday, not "
                  "necessarily a defect.", InpTestSymbol, now_dt.day_of_week);
     }
   Check("SN_GetSessionMinutesRemaining does not crash regardless of outcome",
         true); // reaching this line at all is the assertion

   PrintFormat("=== TASK-006 SessionManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
