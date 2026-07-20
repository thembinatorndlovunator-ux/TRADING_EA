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
//| Validates a CSymbolProfile. Returns true only if every check       |
//| passes. On any failure, 'reasons' (must be a dynamic array —       |
//| it is cleared and rebuilt here) holds one machine-readable string  |
//| per failed check, per PROJECT_RULES.md rule 6.                     |
//|                                                                    |
//| filling_mode == 0 and margin_initial == 0 are NOT treated as       |
//| failures here — both are legitimate broker-reported values (a      |
//| default fill policy, or leverage-based margin instead of a fixed   |
//| per-symbol initial margin respectively). A genuinely failed read   |
//| of either is instead caught by profile.loaded being false, which   |
//| this function checks first and treats as an immediate, total       |
//| failure — no other field is trustworthy once Load() itself failed. |
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

   return pass;
  }
