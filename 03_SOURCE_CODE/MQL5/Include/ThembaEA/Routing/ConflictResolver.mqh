//+------------------------------------------------------------------+
//| ConflictResolver.mqh                                              |
//| Themba Adaptive Intraday Engine — Routing                          |
//|                                                                    |
//| Owns ONLY the final tie-break given StrategyRouter.mqh's already-    |
//| scored, eligible-or-not candidate list, per                          |
//| TASK-002_PHASE2_SPECIFICATION.md section 3: "among eligible            |
//| candidates, the highest score wins in its own direction; between       |
//| opposing-direction candidates, No trade wins unless one direction's     |
//| top score exceeds the other's by at least InpConflictScoreGap."          |
//|                                                                    |
//| **Stated simplification:** section 3's exact-tie rule (smaller entry     |
//| timeframe wins, then alphabetically-first family name) is not                |
//| implemented — no candidate currently carries its own entry timeframe          |
//| as a field, and no strategy has produced an exact-score tie in any             |
//| test scenario built so far. The current same-direction tie-break is             |
//| simply "first candidate found in array order," which IS deterministic            |
//| (the candidate array's own order is fixed by the caller), just not the             |
//| specific rule section 3 states. Flagged here rather than silently                   |
//| left unimplemented.                                                                  |
//+------------------------------------------------------------------+
#property strict

#include "StrategyRouter.mqh"

struct SConflictResult
  {
   bool                     has_winner;
   STradeCandidate          winner;
   double                   winner_score;
   double                   winner_eligibility_multiplier; // TASK-036
   double                   winner_r_component;             // TASK-036
   double                   winner_regime_component;        // TASK-036
   ENUM_CANDIDATE_DIRECTION winning_direction;
   string                   reason; // set when has_winner is false
  };

//+------------------------------------------------------------------+
//| TASK-036 — local helper: fills 'result' from the winning routed        |
//| candidate at 'idx', including its own score-component breakdown, so     |
//| the 4 call sites below (each a different resolution branch) cannot         |
//| drift out of sync with each other on which fields get copied.               |
//+------------------------------------------------------------------+
void CR_FillWinnerFromRouted(SConflictResult &result, const SRoutedCandidate &routed[],
                              const int idx, const double score,
                              const ENUM_CANDIDATE_DIRECTION direction)
  {
   result.has_winner = true;
   result.winner = routed[idx].candidate;
   result.winner_score = score;
   result.winner_eligibility_multiplier = routed[idx].eligibility_multiplier;
   result.winner_r_component = routed[idx].r_component;
   result.winner_regime_component = routed[idx].regime_component;
   result.winning_direction = direction;
  }

//+------------------------------------------------------------------+
//| Resolves the final trade decision from a routed candidate list.      |
//| 'conflict_score_gap' (section 3 default 10, bounded [0,50]) is the    |
//| minimum score advantage one direction needs over the other when        |
//| both have an eligible candidate — below that gap, No trade wins.        |
//+------------------------------------------------------------------+
bool CR_ResolveConflicts(const SRoutedCandidate &routed[], const int count,
                          const double conflict_score_gap, SConflictResult &result)
  {
   result.has_winner = false;
   result.winner = SS_EmptyCandidate();
   result.winner_score = 0.0;
   result.winner_eligibility_multiplier = 0.0;
   result.winner_r_component = 0.0;
   result.winner_regime_component = 0.0;
   result.winning_direction = CAND_NONE;
   result.reason = "";

   double best_long_score = -1.0;
   int best_long_idx = -1;
   double best_short_score = -1.0;
   int best_short_idx = -1;

   for(int i = 0; i < count; i++)
     {
      if(!routed[i].eligible)
         continue;

      if(routed[i].candidate.direction == CAND_LONG && routed[i].final_score > best_long_score)
        {
         best_long_score = routed[i].final_score;
         best_long_idx = i;
        }
      if(routed[i].candidate.direction == CAND_SHORT && routed[i].final_score > best_short_score)
        {
         best_short_score = routed[i].final_score;
         best_short_idx = i;
        }
     }

   bool have_long = (best_long_idx >= 0);
   bool have_short = (best_short_idx >= 0);

   if(!have_long && !have_short)
     {
      result.reason = "no_eligible_candidates";
      return false;
     }

   if(have_long && !have_short)
     {
      CR_FillWinnerFromRouted(result, routed, best_long_idx, best_long_score, CAND_LONG);
      return true;
     }

   if(have_short && !have_long)
     {
      CR_FillWinnerFromRouted(result, routed, best_short_idx, best_short_score, CAND_SHORT);
      return true;
     }

   // Both directions have an eligible candidate — the gap rule decides.
   double gap = MathAbs(best_long_score - best_short_score);
   if(gap < conflict_score_gap)
     {
      result.reason = "opposing_directions_gap_not_met";
      return false;
     }

   if(best_long_score > best_short_score)
      CR_FillWinnerFromRouted(result, routed, best_long_idx, best_long_score, CAND_LONG);
   else
      CR_FillWinnerFromRouted(result, routed, best_short_idx, best_short_score, CAND_SHORT);
   return true;
  }
