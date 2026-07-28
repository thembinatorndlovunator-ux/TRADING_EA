//+------------------------------------------------------------------+
//| BrokerValidator.mqh                                               |
//| Themba Adaptive Intraday Engine — Risk                             |
//|                                                                    |
//| Judges a CSymbolProfile against TASK-002_PHASE2_SPECIFICATION.md   |
//| section 8's mandatory attach-time validation rule: "a mandatory    |
//| OnInit/symbol-attach validation routine checks tick value, tick    |
//| size, contract size, volume min/max/step, stop level, freeze       |
//| level, filling mode, and margin; any failure fails the symbol      |
//| closed (not traded)." Kept separate from SymbolProfile.mqh (which  |
//| only reads values) so this module has one job: deciding pass/fail  |
//| and producing PROJECT_RULES.md rule 6's required machine-readable  |
//| reason for every failure, not only the first one found.            |
//+------------------------------------------------------------------+
#property strict

#include "../Market/SymbolProfile.mqh"

//--- Appends one reason string to a dynamic reasons[] array.
void BV_AppendReason(string &reasons[], const string reason)
  {
   int n = ArraySize(reasons);
   ArrayResize(reasons, n + 1);
   reasons[n] = reason;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding      |
//| 7):** true iff 'filling_mode' (the SYMBOL_FILLING_MODE bitmask)          |
//| reports support for at least one NON-RETURN filling policy (FOK          |
//| and/or IOC). A symbol whose bitmask supports ONLY the implicit           |
//| RETURN behavior (or reports the bitmask as literally 0, which this      |
//| project's own CSymbolProfile comment notes some brokers legitimately    |
//| report instead of an explicit flag) can leave a market order's own      |
//| unfilled remainder still working after a partial fill (see              |
//| OrderManager.mqh's own P0 finding 4 fix,                                 |
//| SOrderOpenResult.has_live_remainder) -- this project's own order-        |
//| submission code (OM_OpenPosition/OM_ClosePosition) now explicitly        |
//| selects FOK/IOC via CTrade::SetTypeFillingBySymbol, but this             |
//| validator confirms the SYMBOL ITSELF actually supports one of them       |
//| before the EA is allowed to run on it at all.                           |
//+------------------------------------------------------------------+
bool BV_SupportsNonReturnFilling(const long filling_mode)
  {
   return (filling_mode & SYMBOL_FILLING_FOK) != 0 || (filling_mode & SYMBOL_FILLING_IOC) != 0;
  }

//+------------------------------------------------------------------+
//| Validates a CSymbolProfile. Returns true only if every check       |
//| passes. On any failure, 'reasons' (must be a dynamic array —       |
//| it is cleared and rebuilt here) holds one machine-readable string  |
//| per failed check, per PROJECT_RULES.md rule 6.                     |
//|                                                                    |
//| margin_initial == 0 is NOT treated as a failure here -- a           |
//| legitimate broker-reported value (leverage-based margin instead of  |
//| a fixed per-symbol initial margin). A genuinely failed READ of it   |
//| is instead caught by profile.loaded being false, which this        |
//| function checks first and treats as an immediate, total failure —  |
//| no other field is trustworthy once Load() itself failed.           |
//|                                                                    |
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding       |
//| 7):** this module's own header has always claimed it validates          |
//| "filling mode... and margin" per TASK-002_PHASE2_SPECIFICATION.md       |
//| section 8, but the function body previously stopped after freeze        |
//| level -- filling_mode==0 was explicitly documented as "not a failure"    |
//| with NO check of any kind for the non-zero case either, and margin      |
//| was never validated via any live broker call (OrderCalcMargin) at       |
//| all. Two real checks are added: (1) BV_SupportsNonReturnFilling         |
//| above -- a symbol whose bitmask supports ONLY RETURN is now refused;    |
//| (2) OrderCalcMargin itself is called for a representative minimum-      |
//| volume order -- if the BROKER'S OWN margin calculation for this         |
//| exact symbol fails outright, that is a genuine symbol/account-          |
//| configuration incompatibility this project's own risk math depends      |
//| on being able to trust downstream (RM_CrossCheckRiskCash's own          |
//| OrderCalcProfit cross-check makes the identical assumption for          |
//| profit calculation).**                                                   |
//+------------------------------------------------------------------+
bool BV_ValidateSymbolProfile(const CSymbolProfile &profile, string &reasons[])
  {
   ArrayFree(reasons);

   if(!profile.loaded)
     {
      BV_AppendReason(reasons, "symbol_profile_load_failed");
      return false;
     }

   bool pass = true;

   if(profile.tick_value <= 0.0)
     {
      BV_AppendReason(reasons, "invalid_tick_value");
      pass = false;
     }
   if(profile.tick_value_loss <= 0.0)
     {
      BV_AppendReason(reasons, "invalid_tick_value_loss");
      pass = false;
     }
   if(profile.tick_size <= 0.0)
     {
      BV_AppendReason(reasons, "invalid_tick_size");
      pass = false;
     }
   if(profile.contract_size <= 0.0)
     {
      BV_AppendReason(reasons, "invalid_contract_size");
      pass = false;
     }
   if(profile.volume_min <= 0.0)
     {
      BV_AppendReason(reasons, "invalid_volume_min");
      pass = false;
     }
   if(profile.volume_step <= 0.0)
     {
      BV_AppendReason(reasons, "invalid_volume_step");
      pass = false;
     }
   if(profile.volume_max < profile.volume_min)
     {
      BV_AppendReason(reasons, "invalid_volume_max");
      pass = false;
     }
   if(profile.point <= 0.0)
     {
      BV_AppendReason(reasons, "invalid_point");
      pass = false;
     }
   if(profile.stop_level_points < 0)
     {
      BV_AppendReason(reasons, "invalid_stop_level");
      pass = false;
     }
   if(profile.freeze_level_points < 0)
     {
      BV_AppendReason(reasons, "invalid_freeze_level");
      pass = false;
     }
   if(!BV_SupportsNonReturnFilling(profile.filling_mode))
     {
      BV_AppendReason(reasons, "filling_mode_return_only_or_unreported");
      pass = false;
     }

   double margin_check_price = SymbolInfoDouble(profile.symbol, SYMBOL_ASK);
   double margin_out;
   if(margin_check_price <= 0.0 ||
      !OrderCalcMargin(ORDER_TYPE_BUY, profile.symbol, profile.volume_min, margin_check_price,
                        margin_out))
     {
      BV_AppendReason(reasons, "margin_calculation_failed");
      pass = false;
     }

   return pass;
  }
