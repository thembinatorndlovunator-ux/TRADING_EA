//+------------------------------------------------------------------+
//| Test_CooldownManager.mq5                                          |
//| Themba Adaptive Intraday Engine — TASK-034 compile/logic test       |
//|                                                                    |
//| Pure, deterministic — no live trading action. Exercises              |
//| CooldownManager.mqh's pure trigger predicate directly, then its       |
//| GlobalVariable-backed live wrapper under a dedicated test symbol/       |
//| magic pair. All test fields are wiped at the end (CDM_ResetInstance)     |
//| so a real run leaves no residue.                                          |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Risk/CooldownManager.mqh"

input string InpTestSymbol = "EURUSD";
input long   InpTestMagic  = 990099003; // dedicated, unmistakably-test-only

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
   Print("=== TASK-034 CooldownManager test start ===");

   //--- 1. Pure predicate: fewer than 3 trades never triggers ------------
   double two[2] = {-10.0, -20.0};
   Check("fewer than 3 recorded trades never triggers", CDM_ShouldTriggerCooldown(two) == false);

   //--- 2. Pure predicate: all 3 losses, net negative -> triggers --------
   double all_losses[3] = {-10.0, -20.0, -5.0};
   Check("3 losses, net negative, triggers", CDM_ShouldTriggerCooldown(all_losses) == true);

   //--- 3. Pure predicate: a win among the 3 does NOT trigger -------------
   double one_win[3] = {-10.0, 50.0, -5.0};
   Check("a win within the last 3 does NOT trigger",
         CDM_ShouldTriggerCooldown(one_win) == false);

   //--- 4. Pure predicate: 3 losses but net non-negative (edge case; -----
   //--- cannot actually occur if every element is strictly < 0, but the ----
   //--- function checks both conjuncts independently per spec) -------------
   double zero_loss[3] = {-10.0, -20.0, 0.0};
   Check("a zero (not a loss) among the 3 does NOT trigger",
         CDM_ShouldTriggerCooldown(zero_loss) == false);

   //--- Live wrapper: clean slate before testing --------------------------
   CDM_ResetInstance(InpTestSymbol, InpTestMagic);

   datetime cooldown_until;
   Check("fresh instance: not in cooldown",
         CDM_IsInCooldown(InpTestSymbol, InpTestMagic, TimeCurrent(), cooldown_until) == false);

   //--- 5. Live wrapper: two wins then a loss -> ring buffer holds 3, but --
   //--- not all losses -> no cooldown --------------------------------------
   datetime now = TimeCurrent();
   CDM_RecordClosedTrade(InpTestSymbol, InpTestMagic, 50.0, now, 90);
   CDM_RecordClosedTrade(InpTestSymbol, InpTestMagic, 30.0, now, 90);
   CDM_RecordClosedTrade(InpTestSymbol, InpTestMagic, -10.0, now, 90);
   Check("2 wins + 1 loss: cooldown NOT triggered",
         CDM_IsInCooldown(InpTestSymbol, InpTestMagic, now, cooldown_until) == false);

   //--- 6. Live wrapper: three consecutive net-negative losses triggers ----
   //--- (the ring buffer now holds the last 3: all three of the below) -----
   CDM_ResetInstance(InpTestSymbol, InpTestMagic);
   CDM_RecordClosedTrade(InpTestSymbol, InpTestMagic, -15.0, now, 90);
   CDM_RecordClosedTrade(InpTestSymbol, InpTestMagic, -25.0, now, 90);
   CDM_RecordClosedTrade(InpTestSymbol, InpTestMagic, -5.0, now, 90);
   bool in_cooldown = CDM_IsInCooldown(InpTestSymbol, InpTestMagic, now, cooldown_until);
   Check("3 consecutive net-negative losses triggers cooldown", in_cooldown);
   Check("cooldown_until is now + 90 minutes",
         cooldown_until == now + 90 * 60);

   //--- 7. Cooldown expires after the configured duration, not before ------
   Check("cooldown is still active 1 second before expiry",
         CDM_IsInCooldown(InpTestSymbol, InpTestMagic, cooldown_until - 1, cooldown_until) == true);
   Check("cooldown has expired exactly at the expiry timestamp",
         CDM_IsInCooldown(InpTestSymbol, InpTestMagic, cooldown_until, cooldown_until) == false);
   Check("cooldown has expired well after the expiry timestamp",
         CDM_IsInCooldown(InpTestSymbol, InpTestMagic, cooldown_until + 3600, cooldown_until) == false);

   //--- 8. Cooldown on one symbol+magic does not affect a different magic --
   long other_magic = InpTestMagic + 1;
   CDM_ResetInstance(InpTestSymbol, other_magic);
   Check("a different magic on the same symbol is unaffected by the cooldown",
         CDM_IsInCooldown(InpTestSymbol, other_magic, now, cooldown_until) == false);

   //--- 9. A win overwriting the oldest loss (ring-buffer rotation) --------
   //--- clears a previously-triggered cooldown state on the NEXT re---------
   //--- evaluation (recording a new trade re-checks the current 3) ---------
   CDM_ResetInstance(InpTestSymbol, InpTestMagic);
   CDM_RecordClosedTrade(InpTestSymbol, InpTestMagic, -15.0, now, 90); // slot 0
   CDM_RecordClosedTrade(InpTestSymbol, InpTestMagic, -25.0, now, 90); // slot 1
   CDM_RecordClosedTrade(InpTestSymbol, InpTestMagic, -5.0, now, 90);  // slot 2 -> triggers
   Check("setup: cooldown triggered before the rotation win",
         CDM_IsInCooldown(InpTestSymbol, InpTestMagic, now, cooldown_until) == true);
   CDM_RecordClosedTrade(InpTestSymbol, InpTestMagic, 100.0, now, 90); // overwrites slot 0 (-15.0)
   // cooldown_until from the earlier trigger is still in the future, so
   // CDM_IsInCooldown still reports true here (recording a trade does not
   // retroactively clear an already-set cooldown_until — only elapsed time
   // does, per the spec's "reset is purely time-based" rule). This
   // confirms CDM_RecordClosedTrade never WIDENS the window on a
   // non-triggering re-evaluation either.
   datetime cooldown_until_after;
   CDM_IsInCooldown(InpTestSymbol, InpTestMagic, now, cooldown_until_after);
   Check("a subsequent win does not extend the already-set cooldown_until",
         cooldown_until_after == cooldown_until);

   //--- Cleanup: leave no residue ------------------------------------------
   CDM_ResetInstance(InpTestSymbol, InpTestMagic);
   CDM_ResetInstance(InpTestSymbol, other_magic);
   Check("instance is clear after cleanup",
         CDM_IsInCooldown(InpTestSymbol, InpTestMagic, now, cooldown_until) == false);

   PrintFormat("=== TASK-034 CooldownManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
