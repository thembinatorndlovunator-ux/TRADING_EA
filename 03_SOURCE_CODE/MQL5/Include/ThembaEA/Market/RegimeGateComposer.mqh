//+------------------------------------------------------------------+
//| RegimeGateComposer.mqh                                            |
//| Themba Adaptive Intraday Engine — Market                          |
//|                                                                    |
//| TASK-034 — composes the three gates TASK-034_LIVE_SAFETY_WIRING.md's  |
//| Specification item 3 requires be applied in ONE place, not scattered:    |
//| spread/liquidity untradeability (MRE_IsUntradeableSpreadOrLiquidity,        |
//| TASK-016), hysteresis (MRE_ApplyHysteresis, TASK-016), and news             |
//| blackout (NewsManager.mqh, TASK-029). The caller supplies the news             |
//| blackout result (this module does not fetch news itself — matching             |
//| MarketRegimeEngine.mqh's own "NEWS_BLACKOUT is accepted as a caller-             |
//| supplied boolean" convention).                                                     |
//|                                                                    |
//| Priority when both spread/liquidity and news are simultaneously          |
//| active: spread/liquidity wins as the EFFECTIVE regime (an untradeable       |
//| market is untradeable regardless of the reason) but BOTH flags are            |
//| still reported in the result, so the journal shows every gate that            |
//| fired, per Specification item 5, not just the one that determined the           |
//| effective regime.                                                                  |
//|                                                                    |
//| The effective regime this returns is what StrategyRouter.mqh's own      |
//| STR_RouteCandidates must be called with (in place of the raw regime        |
//| read) — its own default case already blocks every strategy family for        |
//| NEWS_BLACKOUT/UNTRADEABLE_SPREAD_OR_LIQUIDITY/TRANSITION_OR_UNCERTAIN,         |
//| so substituting the effective regime is sufficient to enforce the              |
//| gates; no separate "entry_allowed" flag is needed here.                            |
//+------------------------------------------------------------------+
#property strict

#include "MarketRegimeEngine.mqh"

struct SRegimeGateResult
  {
   ENUM_MARKET_REGIME effective_regime;
   bool               spread_liquidity_gate_active;
   bool               news_gate_active;
   string             news_triggering_event_id;
  };

//+------------------------------------------------------------------+
//| Pure — composes the three gates given the raw classifier read, the    |
//| caller-computed spread/liquidity and news-blackout booleans, and the     |
//| caller-owned, persisted hysteresis state (mutated in place, matching        |
//| MRE_ApplyHysteresis's own calling convention).                                 |
//+------------------------------------------------------------------+
SRegimeGateResult RGC_ComposeGates(SRegimeHysteresisState &hysteresis_state,
                                    const ENUM_MARKET_REGIME raw_regime,
                                    const bool spread_liquidity_untradeable,
                                    const bool news_blackout_active,
                                    const string news_triggering_event_id,
                                    const int hysteresis_required_bars = 2)
  {
   SRegimeGateResult r;
   r.spread_liquidity_gate_active = spread_liquidity_untradeable;
   r.news_gate_active = news_blackout_active;
   r.news_triggering_event_id = news_triggering_event_id;

   ENUM_MARKET_REGIME regime_for_hysteresis = raw_regime;
   bool bypass = false;

   if(spread_liquidity_untradeable)
     {
      regime_for_hysteresis = REGIME_UNTRADEABLE_SPREAD_OR_LIQUIDITY;
      bypass = true;
     }
   else if(news_blackout_active)
     {
      regime_for_hysteresis = REGIME_NEWS_BLACKOUT;
      bypass = true;
     }
   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 9):
   // TASK-002_PHASE2_SPECIFICATION.md:401-411 states confidence below 0.5
   // "forces transition treatment for routing regardless of the nominal
   // state" -- this bypass was previously only applied for spread/liquidity
   // and news, so a raw_regime of REGIME_TRANSITION_OR_UNCERTAIN (which is
   // exactly what the EA maps a sub-0.5-confidence read to) went through
   // ORDINARY hysteresis instead, requiring 'hysteresis_required_bars'
   // consecutive low-confidence bars before effective_regime actually
   // changed. On just the FIRST low-confidence bar, effective_regime stayed
   // pinned to the prior CONFIRMED (possibly tradable) regime, letting
   // strategies keep trading against a regime read the classifier itself no
   // longer trusts. The low-confidence override must be immediate, exactly
   // like the spread/liquidity and news gates above.**
   else if(raw_regime == REGIME_TRANSITION_OR_UNCERTAIN)
     {
      bypass = true;
     }

   r.effective_regime = MRE_ApplyHysteresis(hysteresis_state, regime_for_hysteresis, bypass,
                                             hysteresis_required_bars);
   return r;
  }
