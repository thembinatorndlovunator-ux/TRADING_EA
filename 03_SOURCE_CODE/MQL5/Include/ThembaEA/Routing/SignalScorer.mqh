//+------------------------------------------------------------------+
//| SignalScorer.mqh                                                  |
//| Themba Adaptive Intraday Engine — Routing                          |
//|                                                                    |
//| Begins Phase 6 ("Router"). Defines the unified STradeCandidate       |
//| shape every one of the five strategy modules (TASK-019 through        |
//| TASK-023) converts its own signal type into, plus the base-score       |
//| formula, per TASK-002_PHASE2_SPECIFICATION.md section 9.               |
//|                                                                    |
//| **Scope note, stated explicitly:** section 9 lists five score          |
//| components (location/structure quality, pattern quality, regime         |
//| alignment, expected reward-to-risk, sample-gated historical              |
//| performance). Only two are standalone-computable from what exists         |
//| today — expected reward-to-risk (every candidate already carries          |
//| entry/stop/target) and regime alignment (the regime confidence            |
//| already computed by MarketRegimeEngine.mqh). Location/pattern quality      |
//| and sample-gated historical performance need, respectively, a               |
//| reusable structure-quality score not yet built as one function, and a       |
//| real trade journal with enough history (TASK-009's DecisionJournal has       |
//| never been fed a real trade) — both are honestly deferred here rather        |
//| than approximated with a placeholder that could be mistaken for real.         |
//+------------------------------------------------------------------+
#property strict

#include "../Strategies/SRBounceStrategy.mqh"
#include "../Strategies/SMCStrategy.mqh"
#include "../Strategies/ChartPatternStrategy.mqh"
#include "../Strategies/TrendFollowingStrategy.mqh"
#include "../Strategies/PostExpansionRetestStrategy.mqh"

enum ENUM_STRATEGY_FAMILY
  {
   FAMILY_NONE,
   FAMILY_SR_BOUNCE,
   FAMILY_SMC_ICT,
   FAMILY_CHART_PATTERN,
   FAMILY_TREND_FOLLOWING,
   FAMILY_POST_EXPANSION_RETEST
  };

enum ENUM_CANDIDATE_DIRECTION
  {
   CAND_NONE,
   CAND_LONG,
   CAND_SHORT
  };

struct STradeCandidate
  {
   bool                      found;
   ENUM_STRATEGY_FAMILY      family;
   ENUM_CANDIDATE_DIRECTION  direction;
   string                    setup;
   double                    entry_price;
   double                    stop_price;
   double                    target_price;
   string                    candlestick_pattern;
  };

STradeCandidate SS_EmptyCandidate()
  {
   STradeCandidate c;
   c.found = false;
   c.family = FAMILY_NONE;
   c.direction = CAND_NONE;
   c.setup = "";
   c.entry_price = 0.0;
   c.stop_price = 0.0;
   c.target_price = 0.0;
   c.candlestick_pattern = "";
   return c;
  }

//+------------------------------------------------------------------+
//| Adapters: one per strategy module, converting its own signal type   |
//| into the unified STradeCandidate shape. No scoring or eligibility    |
//| logic happens here — pure structural conversion only.                |
//+------------------------------------------------------------------+
STradeCandidate SS_FromSRBounce(const SSRBounceSignal &sig)
  {
   STradeCandidate c = SS_EmptyCandidate();
   if(!sig.found) return c;
   c.found = true;
   c.family = FAMILY_SR_BOUNCE;
   c.direction = (sig.direction == SRB_LONG) ? CAND_LONG : CAND_SHORT;
   c.setup = (sig.direction == SRB_LONG) ? "support_bounce" : "resistance_bounce";
   c.entry_price = sig.entry_price;
   c.stop_price = sig.stop_price;
   c.target_price = sig.target_price;
   c.candlestick_pattern = sig.candlestick_pattern;
   return c;
  }

STradeCandidate SS_FromSMC(const SSMCSignal &sig)
  {
   STradeCandidate c = SS_EmptyCandidate();
   if(!sig.found) return c;
   c.found = true;
   c.family = FAMILY_SMC_ICT;
   c.direction = (sig.direction == SMCD_LONG) ? CAND_LONG : CAND_SHORT;
   c.setup = (sig.setup_type == SMC_SETUP_OB_RETEST) ? "ob_retest" :
             (sig.setup_type == SMC_SETUP_SWEEP_REVERSAL) ? "sweep_reversal" : "fvg_return";
   c.entry_price = sig.entry_price;
   c.stop_price = sig.stop_price;
   c.target_price = sig.target_price;
   c.candlestick_pattern = sig.candlestick_pattern;
   return c;
  }

STradeCandidate SS_FromChartPattern(const SChartPatternStrategySignal &sig)
  {
   STradeCandidate c = SS_EmptyCandidate();
   if(!sig.found) return c;
   c.found = true;
   c.family = FAMILY_CHART_PATTERN;
   c.direction = (sig.direction == CPSD_LONG) ? CAND_LONG : CAND_SHORT;
   c.setup = (sig.setup_type == CPS_TREND_BREAKOUT_RETEST) ? "trend_breakout_retest" : "range_boundary";
   c.entry_price = sig.entry_price;
   c.stop_price = sig.stop_price;
   c.target_price = sig.target_price;
   c.candlestick_pattern = sig.candlestick_pattern;
   return c;
  }

STradeCandidate SS_FromTrendFollowing(const STFStrategySignal &sig)
  {
   STradeCandidate c = SS_EmptyCandidate();
   if(!sig.found) return c;
   c.found = true;
   c.family = FAMILY_TREND_FOLLOWING;
   c.direction = (sig.direction == TFSD_LONG) ? CAND_LONG : CAND_SHORT;
   c.setup = (sig.setup_type == TFS_TRENDLINE_PULLBACK) ? "trendline_pullback" : "momentum_continuation";
   c.entry_price = sig.entry_price;
   c.stop_price = sig.stop_price;
   c.target_price = sig.target_price;
   c.candlestick_pattern = sig.candlestick_pattern;
   return c;
  }

STradeCandidate SS_FromPostExpansionRetest(const SPostExpansionRetestSignal &sig)
  {
   STradeCandidate c = SS_EmptyCandidate();
   if(!sig.found) return c;
   c.found = true;
   c.family = FAMILY_POST_EXPANSION_RETEST;
   c.direction = (sig.direction == PERD_LONG) ? CAND_LONG : CAND_SHORT;
   c.setup = "post_expansion_retest";
   c.entry_price = sig.entry_price;
   c.stop_price = sig.stop_price;
   c.target_price = sig.target_price;
   c.candlestick_pattern = sig.candlestick_pattern;
   return c;
  }

//+------------------------------------------------------------------+
//| Base score, per section 9: expected-reward-to-risk (min(1,          |
//| expected_R/3.0)) and regime-confidence alignment, equally weighted,  |
//| scaled to [0,100] — see the file header for why the other three       |
//| section-9 components are not included yet.                            |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 'r_component_out'/'regime_component_out' (added, 2026-07-22,          |
//| TASK-036 Specification item 6) expose the two real, currently-           |
//| implemented components separately, each already in [0,1] before the        |
//| 0.5/0.5 weighting -- so a caller (DecisionJournal.mqh's                       |
//| score_breakdown_json) can journal exactly what this function actually           |
//| computed, not a re-derived approximation. Both are 0.0 on a false                 |
//| return, matching base_score's own convention.                                        |
//+------------------------------------------------------------------+
bool SS_ComputeBaseScore(const STradeCandidate &candidate, const double regime_confidence,
                          double &base_score, double &r_component_out,
                          double &regime_component_out)
  {
   base_score = 0.0;
   r_component_out = 0.0;
   regime_component_out = 0.0;
   if(!candidate.found)
      return false;

   double risk = MathAbs(candidate.entry_price - candidate.stop_price);
   if(risk <= 0.0)
      return false;

   double reward = MathAbs(candidate.target_price - candidate.entry_price);
   double expected_r = reward / risk;
   double r_component = MathMax(0.0, MathMin(1.0, expected_r / 3.0));
   double regime_component = MathMax(0.0, MathMin(1.0, regime_confidence));

   double score01 = 0.5 * r_component + 0.5 * regime_component;
   base_score = score01 * 100.0;
   r_component_out = r_component;
   regime_component_out = regime_component;
   return true;
  }
