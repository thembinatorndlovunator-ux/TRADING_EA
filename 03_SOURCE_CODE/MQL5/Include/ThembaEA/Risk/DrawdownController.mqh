//+------------------------------------------------------------------+
//| DrawdownController.mqh                                            |
//| Themba Adaptive Intraday Engine — Risk                             |
//|                                                                    |
//| The "reduced risk after drawdown" formula from                     |
//| TASK-002_PHASE2_SPECIFICATION.md section 8: risk_multiplier =       |
//| clamp(1.0 - current_drawdown_percent / max_reduction_percent,        |
//| min_multiplier, 1.0). A single pure function — consumes             |
//| EquityPeakManager's current_drawdown_percent (not duplicated here)  |
//| and returns a multiplier for RiskManager's sizing, per section 8's  |
//| "risk may reduce or hold, never increase, as a function of a         |
//| preceding loss" rule.                                                |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| risk_multiplier in [min_multiplier, 1.0] — 1.0 at zero drawdown,     |
//| falling linearly to min_multiplier once drawdown reaches               |
//| max_reduction_percent, clamped at both ends (a drawdown beyond        |
//| max_reduction_percent does not reduce risk further than                |
//| min_multiplier; a negative/zero drawdown never exceeds 1.0).           |
//+------------------------------------------------------------------+
double DC_ComputeRiskMultiplier(const double current_drawdown_percent,
                                 const double max_reduction_percent = 10.0,
                                 const double min_multiplier = 0.25)
  {
   if(max_reduction_percent <= 0.0)
      return 1.0; // misconfigured bound — fail to the neutral, non-reducing case

   double multiplier = 1.0 - current_drawdown_percent / max_reduction_percent;
   if(multiplier < min_multiplier)
      multiplier = min_multiplier;
   if(multiplier > 1.0)
      multiplier = 1.0;
   return multiplier;
  }
