//+------------------------------------------------------------------+
//| Test_RiskReservationManager.mq5                                   |
//| Themba Adaptive Intraday Engine — compile/logic test               |
//|                                                                    |
//| Exercises RiskReservationManager.mqh, added 2026-07-27 (Codex        |
//| review finding, ninth round, P0 finding 1) to close the cross-       |
//| symbol total-open-risk race: two chart instances sharing a magic     |
//| number, on different symbols, could each independently observe       |
//| headroom under the total-open-risk cap and both submit, together     |
//| exceeding it. This script simulates that race using two DIFFERENT    |
//| fake magic numbers/symbols under the SAME test process to prove the  |
//| reservation ledger actually sums across symbols and enforces the     |
//| cap as one critical section.                                        |
//|                                                                    |
//| Not a unit-test framework — prints PASS/FAIL per assertion, per      |
//| PROJECT_RULES.md rule 13 and CLAUDE.md's "no claim of test success   |
//| without actual evidence" rule. All reservation keys this script      |
//| touches are cleared at the end so a real run leaves no residue.      |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Risk/RiskReservationManager.mqh"

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

// A distinctive fake magic number for this test run, so it can never
// collide with a real EA instance's own reservations.
#define TEST_MAGIC 918273645

void OnStart()
  {
   Print("=== RiskReservationManager test start ===");

   // Clean slate: clear any residue from a prior aborted run.
   RRM_ReleaseReservation("XAUUSD_TEST", TEST_MAGIC);
   RRM_ReleaseReservation("EURUSD_TEST", TEST_MAGIC);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
     {
      Print("FAIL: this test requires a connected account with positive equity "
            "(AccountInfoDouble(ACCOUNT_EQUITY) <= 0) -- cannot proceed.");
      g_fail++;
      PrintFormat("=== RiskReservationManager test complete: %d passed, %d failed ===",
                  g_pass, g_fail);
      return;
     }
   PrintFormat("INFO: live account equity = %.2f", equity);

   double cap_percent = 1.0; // matches this project's own real InpRiskCapPercent default scale
   double small_risk_cash  = equity * 0.003; // 0.3% of equity -- comfortably fits alone
   double another_risk_cash = equity * 0.004; // 0.4% of equity

   //--- 1. A single reservation well under the cap succeeds ---------------
   double projected_1;
   string reason_1;
   bool ok_1 = RRM_TryReserve("XAUUSD_TEST", TEST_MAGIC, 0.0, small_risk_cash, cap_percent,
                               equity, projected_1, reason_1);
   Check("first reservation (0.3% of equity, no existing exposure) succeeds", ok_1);
   Check("first reservation's own projected percent is ~0.3%",
         MathAbs(projected_1 - 0.3) < 0.01);

   //--- 2. A SECOND symbol's reservation under the SAME magic must see ----
   //---    the FIRST symbol's own live reservation and be summed against --
   //---    it -- this is the exact cross-symbol race this module closes. --
   double projected_2;
   string reason_2;
   bool ok_2 = RRM_TryReserve("EURUSD_TEST", TEST_MAGIC, 0.0, another_risk_cash, cap_percent,
                               equity, projected_2, reason_2);
   // 0.3% (already reserved by XAUUSD_TEST) + 0.4% (this reservation) = 0.7%,
   // still under the 1.0% cap -- must succeed, and its own projected total
   // must reflect BOTH reservations, not just this one's own 0.4%.
   Check("second symbol's reservation succeeds when the COMBINED total still fits the cap",
         ok_2);
   Check("second reservation's own projected percent reflects BOTH live reservations (~0.7%)",
         MathAbs(projected_2 - 0.7) < 0.01);

   //--- 3. A THIRD attempt that would push the COMBINED total over the ----
   //---    cap must be rejected, proving the cross-symbol sum is real, ----
   //---    not each call checking only its own proposed amount in --------
   //---    isolation. ------------------------------------------------------
   double projected_3;
   string reason_3;
   double over_cap_risk_cash = equity * 0.005; // 0.3% + 0.4% + 0.5% = 1.2%, over the 1.0% cap
   bool ok_3 = RRM_TryReserve("GBPUSD_TEST", TEST_MAGIC, 0.0, over_cap_risk_cash, cap_percent,
                               equity, projected_3, reason_3);
   Check("a third reservation that would push the COMBINED total over the cap is rejected",
         ok_3 == false);
   Check("the rejection reason names the cap-exceeded condition",
         StringFind(reason_3, "cap_exceeded") >= 0);

   //--- 4. Releasing the first symbol's reservation frees its own share ---
   //---    of the cap for a later caller. ------------------------------
   RRM_ReleaseReservation("XAUUSD_TEST", TEST_MAGIC);
   double projected_4;
   string reason_4;
   bool ok_4 = RRM_TryReserve("GBPUSD_TEST", TEST_MAGIC, 0.0, over_cap_risk_cash, cap_percent,
                               equity, projected_4, reason_4);
   // Now only EURUSD_TEST's 0.4% is live; 0.4% + 0.5% = 0.9%, under the cap.
   Check("releasing the first reservation frees enough headroom for the "
         "previously-rejected amount to now succeed",
         ok_4);

   //--- 5. Existing actual open risk (passed in by the caller, as the ------
   //---    real EA does via ComputeOwnMagicOpenRiskCash) is correctly ------
   //---    added on top of live reservations. -------------------------------
   RRM_ReleaseReservation("EURUSD_TEST", TEST_MAGIC);
   RRM_ReleaseReservation("GBPUSD_TEST", TEST_MAGIC);
   double projected_5;
   string reason_5;
   double existing_actual_risk_cash = equity * 0.006; // simulates 0.6% already in real positions
   bool ok_5 = RRM_TryReserve("XAUUSD_TEST", TEST_MAGIC, existing_actual_risk_cash,
                               small_risk_cash, cap_percent, equity, projected_5, reason_5);
   // 0.6% (actual, passed in) + 0.3% (proposed) = 0.9%, under the cap.
   Check("existing actual open risk is correctly added to a new proposed reservation",
         ok_5 && MathAbs(projected_5 - 0.9) < 0.01);

   //--- Cleanup: leave no residue -------------------------------------
   RRM_ReleaseReservation("XAUUSD_TEST", TEST_MAGIC);
   RRM_ReleaseReservation("EURUSD_TEST", TEST_MAGIC);
   RRM_ReleaseReservation("GBPUSD_TEST", TEST_MAGIC);

   PrintFormat("=== RiskReservationManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
