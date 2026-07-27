//+------------------------------------------------------------------+
//| Test_KeyEncoding.mq5                                              |
//| Themba Adaptive Intraday Engine — compile/logic test                |
//|                                                                    |
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** exercises KeyEncoding.mqh's bounded-key builders directly            |
//| against the review's own worked examples (an ordinary Deriv synthetic         |
//| symbol name combined with a realistic server name, which the review               |
//| showed already exceeds MT5's 63-character global-variable name limit                  |
//| under the OLD raw-concatenation scheme) — proving every builder stays                    |
//| within the limit regardless of symbol/server length, and that distinct                       |
//| inputs produce distinct keys (collision resistance).                                             |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Core/KeyEncoding.mqh"

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
   Print("=== KeyEncoding test start ===");

   //--- 1. KE_HashHex is always exactly 16 characters ----------------------
   Check("KE_HashHex('') is 16 characters", StringLen(KE_HashHex("")) == 16);
   Check("KE_HashHex(short string) is 16 characters", StringLen(KE_HashHex("XAUUSD")) == 16);
   Check("KE_HashHex(long string) is 16 characters",
         StringLen(KE_HashHex("a_very_long_string_meant_to_simulate_an_unusually_long_"
                              "broker_server_name_combined_with_a_synthetic_symbol")) == 16);

   //--- 2. Deterministic: same input -> same output -------------------------
   Check("KE_HashHex is deterministic for the same input",
         KE_HashHex("XAUUSD_990001") == KE_HashHex("XAUUSD_990001"));

   //--- 3. Collision-resistant: different inputs -> different output --------
   //--- (not a formal guarantee, but any accidental collision on these -----
   //--- specific, deliberately similar test strings would indicate a --------
   //--- broken hash, not genuine bad luck) -----------------------------------
   Check("different symbols hash differently", KE_HashHex("XAUUSD") != KE_HashHex("EURUSD"));
   Check("different magics hash differently",
         KE_HashHex("XAUUSD_990001") != KE_HashHex("XAUUSD_990002"));
   Check("a single differing character hashes differently (avalanche)",
         KE_HashHex("Volatility 100 Index") != KE_HashHex("Volatility 100 Indey"));

   //--- 4. The review's own worked examples: keys that overflowed 63 --------
   //--- characters under the OLD raw-concatenation scheme must now stay -----
   //--- comfortably within it, using the SAME builders the fixed modules ----
   //--- actually call ---------------------------------------------------------
   string im_key = KE_InstanceNamespace("ThembaEA_IM", "Volatility 100 Index", 990001) +
                   "__active";
   PrintFormat("INFO: IntentManager-style key for a long synthetic symbol: '%s' (length=%d)",
               im_key, StringLen(im_key));
   Check("IntentManager-style key for a long synthetic symbol stays within MT5's 63-char limit",
         StringLen(im_key) <= 63);

   string cdm_key = KE_InstanceNamespace("ThembaEA_CDM", "Volatility 100 Index", 990001) +
                    "__cooldown_until";
   PrintFormat("INFO: CooldownManager-style key for a long synthetic symbol: '%s' (length=%d)",
               cdm_key, StringLen(cdm_key));
   Check("CooldownManager-style key for a long synthetic symbol stays within MT5's 63-char limit",
         StringLen(cdm_key) <= 63);

   //--- 5. Account-wide and per-position namespaces also stay bounded, ------
   //--- using this module's own longest known field name --------------------
   string aw_key = KE_AccountNamespace("ThembaEA_AW") + "__dwl_last_balance_deal_ticket";
   Check("StateManager-style account-wide key stays within MT5's 63-char limit",
         StringLen(aw_key) <= 63);

   string pst_key = KE_PositionNamespace("ThembaEA_PST", 123456789012) +
                     "__bars_since_favorable_swing";
   Check("PositionStateTracker-style key (its own longest field name) stays within "
         "MT5's 63-char limit", StringLen(pst_key) <= 63);

   //--- 6. KE_SetDoubleChecked round-trips a real write ----------------------
   string test_key = KE_InstanceNamespace("ThembaEA_TEST", "EURUSD", 1) + "__probe";
   if(GlobalVariableCheck(test_key))
      GlobalVariableDel(test_key);
   bool set_ok = KE_SetDoubleChecked(test_key, 42.5);
   Check("KE_SetDoubleChecked reports success for an ordinary, bounded key", set_ok);
   Check("KE_SetDoubleChecked actually persisted the value",
         GlobalVariableGet(test_key) == 42.5);
   GlobalVariableDel(test_key); // leave no residue

   PrintFormat("=== KeyEncoding test complete: %d passed, %d failed ===", g_pass, g_fail);
  }
