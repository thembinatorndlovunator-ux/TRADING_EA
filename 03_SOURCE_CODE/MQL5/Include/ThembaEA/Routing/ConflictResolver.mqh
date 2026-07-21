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
   ENUM_CANDIDATE_DIRECTION winning_direction;
   string                   reason; // set when has_winner is false
  };

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
      result.has_winner = true;
      result.winner = routed[best_long_idx].candidate;
      result.winner_score = best_long_score;
      result.winning_direction = CAND_LONG;
      return true;
     }

   if(have_short && !have_long)
     {
      result.has_winner = true;
      result.winner = routed[best_short_idx].candidate;
      result.winner_score = best_short_score;
      result.winning_direction = CAND_SHORT;
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
     {
      result.has_winner = true;
      result.winner = routed[best_long_idx].candidate;
      result.winner_score = best_long_score;
      result.winning_direction = CAND_LONG;
     }
   else
     {
      result.has_winner = true;
      result.winner = routed[best_short_idx].candidate;
      result.winner_score = best_short_score;
      result.winning_direction = CAND_SHORT;
     }
   return true;
  }
