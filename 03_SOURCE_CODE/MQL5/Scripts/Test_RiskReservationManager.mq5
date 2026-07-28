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
//| **Extended, 2026-07-28 (Codex review finding, tenth round, P0        |
//| finding 2):** RRM_TryReserve/RRM_TryReserveLocked now return a         |
//| unique 'reservation_key_out' that RRM_ReleaseReservation requires        |
//| (a bare symbol+magic release is no longer accepted -- see that            |
//| module's own header for why). New coverage added for: same-symbol           |
//| concurrent reservations coexisting instead of colliding (the exact             |
//| ownerless-key defect the review reported), owner-checked release,               |
//| RRM_TryReserveLocked's externally-held-lock contract, and                          |
//| RRM_FindAgedReservations (the caller-driven reconciliation entry point                |
//| that replaces the retired automatic time-based exclusion from the sum).                 |
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

// Best-effort clean slate: releases any keys this script may have left
// behind from a prior aborted run, by prefix-scanning this test magic's own
// namespace directly (this script does not know the exact keys a prior,
// now-dead run may have minted).
void ClearAllTestReservations()
  {
   string aged_keys[64];
   int count = RRM_FindAgedReservations(TEST_MAGIC, 0, aged_keys);
   for(int i = 0; i < count; i++)
      RRM_ReleaseReservation(aged_keys[i]);
  }

void OnStart()
  {
   Print("=== RiskReservationManager test start ===");

   ClearAllTestReservations();

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

   //--- 1. A single reservation well under the cap succeeds, and returns a --
   //---    non-empty, structurally-unique key. ------------------------------
   double projected_1;
   string reason_1;
   string key_xau;
   bool ok_1 = RRM_TryReserve("XAUUSD_TEST", TEST_MAGIC, 0.0, small_risk_cash, cap_percent,
                               equity, projected_1, reason_1, key_xau);
   Check("first reservation (0.3% of equity, no existing exposure) succeeds", ok_1);
   Check("first reservation's own projected percent is ~0.3%",
         MathAbs(projected_1 - 0.3) < 0.01);
   Check("a successful reservation returns a non-empty key", key_xau != "");

   //--- 2. A SECOND symbol's reservation under the SAME magic must see ----
   //---    the FIRST symbol's own live reservation and be summed against --
   //---    it -- this is the exact cross-symbol race this module closes. --
   double projected_2;
   string reason_2;
   string key_eur;
   bool ok_2 = RRM_TryReserve("EURUSD_TEST", TEST_MAGIC, 0.0, another_risk_cash, cap_percent,
                               equity, projected_2, reason_2, key_eur);
   // 0.3% (already reserved by XAUUSD_TEST) + 0.4% (this reservation) = 0.7%,
   // still under the 1.0% cap -- must succeed, and its own projected total
   // must reflect BOTH reservations, not just this one's own 0.4%.
   Check("second symbol's reservation succeeds when the COMBINED total still fits the cap",
         ok_2);
   Check("second reservation's own projected percent reflects BOTH live reservations (~0.7%)",
         MathAbs(projected_2 - 0.7) < 0.01);
   Check("the second reservation's key differs from the first's",
         key_eur != key_xau && key_eur != "");

   //--- 2b. Ownerless-key regression (Codex round-10 P0 finding 2): a -------
   //---     SECOND concurrent reservation attempt for the SAME symbol+magic --
   //---     as an already-live reservation must get its OWN key and must -----
   //---     NOT collide with (overwrite/delete) the first one. ----------------
   double projected_2b;
   string reason_2b;
   string key_xau_2;
   bool ok_2b = RRM_TryReserve("XAUUSD_TEST", TEST_MAGIC, 0.0, small_risk_cash, cap_percent,
                                equity, projected_2b, reason_2b, key_xau_2);
   Check("a second concurrent reservation for the SAME symbol+magic succeeds independently",
         ok_2b);
   Check("the second same-symbol reservation gets a DIFFERENT key than the first",
         key_xau_2 != key_xau && key_xau_2 != "");
   // Both XAUUSD_TEST reservations (0.3% + 0.3%) plus EURUSD_TEST's 0.4% =
   // 1.0%, right at the cap -- projected_2b must reflect all THREE, proving
   // neither same-symbol reservation silently overwrote the other.
   Check("the combined projected percent after both same-symbol reservations reflects all three "
         "live entries (~1.0%)", MathAbs(projected_2b - 1.0) < 0.01);
   // Release only the SECOND XAUUSD_TEST reservation -- the first must
   // remain untouched (owner-checked release via structurally-unique keys).
   RRM_ReleaseReservation(key_xau_2);
   double projected_2c;
   string reason_2c;
   string key_probe;
   bool ok_2c = RRM_TryReserve("GBPUSD_TEST", TEST_MAGIC, 0.0, 0.0001, cap_percent, equity,
                                projected_2c, reason_2c, key_probe);
   Check("releasing the SECOND xau reservation leaves the FIRST xau + eur reservations still "
         "live (probe sees ~0.7%, not ~1.0% or 0%)",
         ok_2c && MathAbs(projected_2c - 0.7) < 0.01);
   RRM_ReleaseReservation(key_probe);

   //--- 3. A THIRD attempt that would push the COMBINED total over the ----
   //---    cap must be rejected, proving the cross-symbol sum is real, ----
   //---    not each call checking only its own proposed amount in --------
   //---    isolation. ------------------------------------------------------
   double projected_3;
   string reason_3;
   string key_gbp_rejected;
   double over_cap_risk_cash = equity * 0.005; // 0.3% + 0.4% + 0.5% = 1.2%, over the 1.0% cap
   bool ok_3 = RRM_TryReserve("GBPUSD_TEST", TEST_MAGIC, 0.0, over_cap_risk_cash, cap_percent,
                               equity, projected_3, reason_3, key_gbp_rejected);
   Check("a third reservation that would push the COMBINED total over the cap is rejected",
         ok_3 == false);
   Check("the rejection reason names the cap-exceeded condition",
         StringFind(reason_3, "cap_exceeded") >= 0);
   Check("a rejected reservation returns an empty key", key_gbp_rejected == "");

   //--- 4. Releasing the first symbol's reservation frees its own share ---
   //---    of the cap for a later caller. ------------------------------
   RRM_ReleaseReservation(key_xau);
   double projected_4;
   string reason_4;
   string key_gbp;
   bool ok_4 = RRM_TryReserve("GBPUSD_TEST", TEST_MAGIC, 0.0, over_cap_risk_cash, cap_percent,
                               equity, projected_4, reason_4, key_gbp);
   // Now only EURUSD_TEST's 0.4% is live; 0.4% + 0.5% = 0.9%, under the cap.
   Check("releasing the first reservation frees enough headroom for the "
         "previously-rejected amount to now succeed",
         ok_4);

   //--- 5. Existing actual open risk (passed in by the caller, as the ------
   //---    real EA does via ComputeOwnMagicOpenRiskCash) is correctly ------
   //---    added on top of live reservations. -------------------------------
   RRM_ReleaseReservation(key_eur);
   RRM_ReleaseReservation(key_gbp);
   double projected_5;
   string reason_5;
   string key_xau_5;
   double existing_actual_risk_cash = equity * 0.006; // simulates 0.6% already in real positions
   bool ok_5 = RRM_TryReserve("XAUUSD_TEST", TEST_MAGIC, existing_actual_risk_cash,
                               small_risk_cash, cap_percent, equity, projected_5, reason_5,
                               key_xau_5);
   // 0.6% (actual, passed in) + 0.3% (proposed) = 0.9%, under the cap.
   Check("existing actual open risk is correctly added to a new proposed reservation",
         ok_5 && MathAbs(projected_5 - 0.9) < 0.01);
   RRM_ReleaseReservation(key_xau_5);

   //--- 6. RRM_TryReserveLocked: caller-held-lock contract (Codex round-10 --
   //---    P0 finding 2) -- acquiring the account lock externally, holding ---
   //---    it across the "exposure snapshot" (simulated here by the caller's --
   //---    own existing_open_risk_cash argument, since this script has no ------
   //---    real broker positions of its own) and the reservation decision, -----
   //---    then releasing, must behave identically to the auto-locking --------
   //---    RRM_TryReserve wrapper. ---------------------------------------------
   double lock_token;
   bool lock_ok = SM_AcquireAccountLock(lock_token);
   Check("RRM_TryReserveLocked's caller can acquire the account lock itself", lock_ok);
   double projected_6;
   string reason_6;
   string key_locked;
   bool ok_6 = RRM_TryReserveLocked("XAUUSD_TEST", TEST_MAGIC, 0.0, small_risk_cash, cap_percent,
                                     equity, projected_6, reason_6, key_locked);
   SM_ReleaseAccountLock(lock_token);
   Check("RRM_TryReserveLocked succeeds under a caller-held lock", ok_6);
   Check("RRM_TryReserveLocked returns a non-empty key", key_locked != "");
   RRM_ReleaseReservation(key_locked);

   //--- 7. RRM_FindAgedReservations: caller-driven reconciliation entry -----
   //---    point (Codex round-10 P0 finding 2) -- replaces the retired --------
   //---    automatic time-based exclusion from the cap sum. A threshold of 0 ---
   //---    finds every currently-live reservation (since elapsed age is -------
   //---    always >= 0); a threshold larger than this test could possibly -----
   //---    run for finds none. --------------------------------------------------
   double projected_7;
   string reason_7;
   string key_aged_probe;
   RRM_TryReserve("XAUUSD_TEST", TEST_MAGIC, 0.0, small_risk_cash, cap_percent, equity,
                   projected_7, reason_7, key_aged_probe);
   string aged_all[64];
   int aged_all_count = RRM_FindAgedReservations(TEST_MAGIC, 0, aged_all);
   bool found_probe = false;
   for(int i = 0; i < aged_all_count; i++)
      if(aged_all[i] == key_aged_probe)
         found_probe = true;
   Check("RRM_FindAgedReservations with a 0-second threshold finds the just-created reservation",
         found_probe);

   string aged_none[64];
   int aged_none_count = RRM_FindAgedReservations(TEST_MAGIC, 999999, aged_none);
   bool found_probe_far = false;
   for(int i = 0; i < aged_none_count; i++)
      if(aged_none[i] == key_aged_probe)
         found_probe_far = true;
   Check("RRM_FindAgedReservations with a huge threshold does NOT find a freshly-created "
         "reservation", !found_probe_far);
   RRM_ReleaseReservation(key_aged_probe);

   //--- Cleanup: leave no residue -------------------------------------
   ClearAllTestReservations();
   string leftover[64];
   Check("no reservations remain under this test magic after cleanup",
         RRM_FindAgedReservations(TEST_MAGIC, 0, leftover) == 0);

   PrintFormat("=== RiskReservationManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
