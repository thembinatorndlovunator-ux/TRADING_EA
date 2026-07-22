//+------------------------------------------------------------------+
//| StrategyRouter.mqh                                                |
//| Themba Adaptive Intraday Engine — Routing                          |
//|                                                                    |
//| Owns eligibility and scoring ONLY, per                              |
//| TASK-002_PHASE2_SPECIFICATION.md section 3: "StrategyRouter owns     |
//| regime-conditioned eligibility and scoring for every candidate...    |
//| its output is a fully-scored, eligible-or-not list per candidate,     |
//| nothing more." The final tie-break between opposing directions is      |
//| ConflictResolver.mqh's job exclusively — this module never picks        |
//| a single winner across directions.                                     |
//|                                                                    |
//| SR_GetEligibilityMultiplier implements section 3's regime x family     |
//| matrix exactly: prefer=1.10, penalize=0.80, heavily_penalize=0.50,      |
//| block=0.0 (not eligible at all — the candidate is dropped, not just      |
//| scored down). Every cell below is traceable to a specific section-3      |
//| routing-table row; see the inline comments.                               |
//+------------------------------------------------------------------+
#property strict

#include "SignalScorer.mqh"

double SR_GetEligibilityMultiplier(const ENUM_STRATEGY_FAMILY family, const ENUM_MARKET_REGIME regime)
  {
   switch(regime)
     {
      case REGIME_TRENDING_UP:
      case REGIME_TRENDING_DOWN:
         // "prefer Trend Following, SMC/ICT order-block retest after
         // displacement, Chart-Pattern ... breakout-retest ... Block SR
         // Bounce counter-trend fades."
         if(family == FAMILY_TREND_FOLLOWING)         return 1.10;
         if(family == FAMILY_SMC_ICT)                 return 1.10;
         if(family == FAMILY_CHART_PATTERN)           return 1.10;
         if(family == FAMILY_SR_BOUNCE)               return 0.0;
         if(family == FAMILY_POST_EXPANSION_RETEST)   return 0.0; // not this regime's family
         return 1.0;

      case REGIME_RANGING:
         // "prefer SR Bounce, Range Rotation, SMC/ICT equal-high/low sweep
         // reversal, false-break trap, ... double/triple top/bottom at a
         // range boundary ... Block Trend Following late-momentum entries."
         if(family == FAMILY_SR_BOUNCE)               return 1.10;
         if(family == FAMILY_SMC_ICT)                 return 1.10;
         if(family == FAMILY_CHART_PATTERN)           return 1.10;
         if(family == FAMILY_TREND_FOLLOWING)         return 0.0;
         if(family == FAMILY_POST_EXPANSION_RETEST)   return 0.0;
         return 1.0;

      case REGIME_VOLATILITY_EXPANSION_UP:
      case REGIME_VOLATILITY_EXPANSION_DOWN:
         // "Prefer Post-Expansion Retest, SMC/ICT FVG return, Trend
         // Following's momentum-continuation half." Chart-pattern breakout
         // is not formalized for this regime in this project (section 6's
         // scope); SR Bounce requires RANGING, not eligible here.
         if(family == FAMILY_POST_EXPANSION_RETEST)   return 1.10;
         if(family == FAMILY_SMC_ICT)                 return 1.10;
         if(family == FAMILY_TREND_FOLLOWING)         return 1.10;
         if(family == FAMILY_SR_BOUNCE)               return 0.0;
         if(family == FAMILY_CHART_PATTERN)           return 0.0;
         return 1.0;

      case REGIME_COMPRESSION:
         // Block every family — the gated early-breakout chart-pattern
         // variant (section 3) is an explicit, stated deferral (see
         // ChartPatternStrategy.mqh's own "Out of scope"), not implemented,
         // so COMPRESSION blocks everything without exception here.
         return 0.0;

      default:
         // TRANSITION_OR_UNCERTAIN, NEWS_BLACKOUT,
         // UNTRADEABLE_SPREAD_OR_LIQUIDITY — block every family
         // unconditionally, per section 3's general rule.
         return 0.0;
     }
  }

struct SRoutedCandidate
  {
   STradeCandidate candidate;
   bool            eligible;
   double          eligibility_multiplier;
   double          base_score;
   double          r_component;      // TASK-036: SS_ComputeBaseScore's own r_component_out
   double          regime_component; // TASK-036: SS_ComputeBaseScore's own regime_component_out
   double          final_score;
   string          reason;
  };

//+------------------------------------------------------------------+
//| Applies eligibility and scoring to every supplied candidate. Does    |
//| NOT pick a winner across directions — that is ConflictResolver.mqh's  |
//| job. Returns the count of ELIGIBLE candidates (a candidate that was    |
//| not found, or was blocked by regime, is still written to 'routed' but  |
//| marked ineligible with a reason, never silently dropped from the        |
//| output array).                                                          |
//+------------------------------------------------------------------+
int STR_RouteCandidates(STradeCandidate &candidates[], const int count,
                         const ENUM_MARKET_REGIME regime, const double regime_confidence,
                         SRoutedCandidate &routed[])
  {
   ArrayResize(routed, count);
   int eligible_count = 0;

   for(int i = 0; i < count; i++)
     {
      routed[i].candidate = candidates[i];
      routed[i].eligible = false;
      routed[i].eligibility_multiplier = 0.0;
      routed[i].base_score = 0.0;
      routed[i].r_component = 0.0;
      routed[i].regime_component = 0.0;
      routed[i].final_score = 0.0;
      routed[i].reason = "";

      if(!candidates[i].found)
        {
         routed[i].reason = "no_signal";
         continue;
        }

      double mult = SR_GetEligibilityMultiplier(candidates[i].family, regime);
      if(mult <= 0.0)
        {
         routed[i].reason = "blocked_by_regime";
         continue;
        }

      double base, r_component, regime_component;
      if(!SS_ComputeBaseScore(candidates[i], regime_confidence, base, r_component,
                                regime_component))
        {
         routed[i].reason = "score_undefined";
         continue;
        }

      routed[i].eligible = true;
      routed[i].eligibility_multiplier = mult;
      routed[i].base_score = base;
      routed[i].r_component = r_component;
      routed[i].regime_component = regime_component;
      routed[i].final_score = MathMax(0.0, MathMin(100.0, base * mult));
      eligible_count++;
     }

   return eligible_count;
  }
