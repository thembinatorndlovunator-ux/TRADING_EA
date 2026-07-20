//+------------------------------------------------------------------+
//| Test_SymbolProfile_BrokerValidator.mq5                            |
//| Themba Adaptive Intraday Engine — TASK-004 compile/logic test      |
//|                                                                    |
//| Exercises CSymbolProfile.Load() against a real broker symbol and   |
//| a deliberately-invalid symbol name, then exercises                 |
//| BV_ValidateSymbolProfile() against a valid profile, a load-failed  |
//| profile, and several hand-corrupted profiles to confirm every      |
//| individual check actually fires (and only that check).             |
//|                                                                    |
//| Run manually (drag onto a chart) and read the Experts log for      |
//| PASS/FAIL lines, per the same convention as Test_StateManager.mq5. |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Market/SymbolProfile.mqh"
#include "../Include/ThembaEA/Risk/BrokerValidator.mqh"

input string InpTestSymbol = "EURUSD"; // a symbol expected to be tradeable
                                        // on the connected account

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

bool ReasonsContain(const string &reasons[], const string needle)
  {
   for(int i = 0; i < ArraySize(reasons); i++)
      if(reasons[i] == needle)
         return true;
   return false;
  }

void OnStart()
  {
   Print("=== TASK-004 SymbolProfile / BrokerValidator test start ===");
   string reasons[];

   //--- 1. A real symbol loads successfully and validates clean -------
   CSymbolProfile good;
   bool loaded_ok = good.Load(InpTestSymbol);
   Check(StringFormat("real symbol '%s' loads successfully", InpTestSymbol),
         loaded_ok);
   if(loaded_ok)
     {
      Check("loaded profile has positive tick_value", good.tick_value > 0.0);
      Check("loaded profile has positive tick_value_loss", good.tick_value_loss > 0.0);
      Check("loaded profile has positive tick_size", good.tick_size > 0.0);
      Check("loaded profile has positive contract_size", good.contract_size > 0.0);
      Check("loaded profile has volume_max >= volume_min",
            good.volume_max >= good.volume_min);

      bool valid = BV_ValidateSymbolProfile(good, reasons);
      Check("valid real-symbol profile passes BrokerValidator", valid);
      Check("valid real-symbol profile produces zero reasons",
            ArraySize(reasons) == 0);
     }
   else
     {
      PrintFormat("NOTE: '%s' did not load — later checks that depend on "
                  "a valid base profile are skipped. This does not "
                  "necessarily indicate a code defect; it may mean this "
                  "symbol is unavailable on the connected account.",
                  InpTestSymbol);
     }

   //--- 2. A bogus symbol name fails to load and is rejected ----------
   CSymbolProfile bogus;
   bool bogus_loaded = bogus.Load("NOT_A_REAL_SYMBOL_XYZ_12345");
   Check("bogus symbol name fails to load", bogus_loaded == false);
   Check("bogus profile's loaded flag is false", bogus.loaded == false);

   bool bogus_valid = BV_ValidateSymbolProfile(bogus, reasons);
   Check("bogus profile fails BrokerValidator", bogus_valid == false);
   Check("bogus profile reason is symbol_profile_load_failed",
         ReasonsContain(reasons, "symbol_profile_load_failed"));
   Check("bogus profile produces exactly one reason (no cascade)",
         ArraySize(reasons) == 1);

   //--- 3. Hand-corrupted single-field profiles are each caught, and --
   //---    only the corrupted field's reason appears. ------------------
   if(loaded_ok)
     {
      CSymbolProfile corrupt_tick_value = good;
      corrupt_tick_value.tick_value = 0.0;
      bool v1 = BV_ValidateSymbolProfile(corrupt_tick_value, reasons);
      Check("zeroed tick_value fails validation", v1 == false);
      Check("zeroed tick_value reason present",
            ReasonsContain(reasons, "invalid_tick_value"));
      Check("zeroed tick_value produces exactly one reason",
            ArraySize(reasons) == 1);

      CSymbolProfile corrupt_volume = good;
      corrupt_volume.volume_max = corrupt_volume.volume_min - 0.01;
      bool v2 = BV_ValidateSymbolProfile(corrupt_volume, reasons);
      Check("volume_max below volume_min fails validation", v2 == false);
      Check("invalid_volume_max reason present",
            ReasonsContain(reasons, "invalid_volume_max"));

      //--- 4. Multiple simultaneous corruptions all get their own -----
      //---    reason, not just the first one found. --------------------
      CSymbolProfile corrupt_multi = good;
      corrupt_multi.tick_size = 0.0;
      corrupt_multi.contract_size = -1.0;
      corrupt_multi.freeze_level_points = -1;
      bool v3 = BV_ValidateSymbolProfile(corrupt_multi, reasons);
      Check("multi-field corruption fails validation", v3 == false);
      Check("multi-field corruption reports invalid_tick_size",
            ReasonsContain(reasons, "invalid_tick_size"));
      Check("multi-field corruption reports invalid_contract_size",
            ReasonsContain(reasons, "invalid_contract_size"));
      Check("multi-field corruption reports invalid_freeze_level",
            ReasonsContain(reasons, "invalid_freeze_level"));
      Check("multi-field corruption reports exactly three reasons",
            ArraySize(reasons) == 3);
     }

   //--- 5. filling_mode == 0 and margin_initial == 0 are NOT failures -
   //---    on an otherwise-loaded profile (legitimate broker values). -
   if(loaded_ok)
     {
      CSymbolProfile zero_optional = good;
      zero_optional.filling_mode = 0;
      zero_optional.margin_initial = 0.0;
      bool v4 = BV_ValidateSymbolProfile(zero_optional, reasons);
      Check("zero filling_mode/margin_initial alone does not fail validation",
            v4 == true);
      Check("zero filling_mode/margin_initial produces zero reasons",
            ArraySize(reasons) == 0);
     }

   PrintFormat("=== TASK-004 SymbolProfile / BrokerValidator test complete: "
               "%d passed, %d failed ===", g_pass, g_fail);
  }
