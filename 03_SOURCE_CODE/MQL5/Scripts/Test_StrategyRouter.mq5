//+------------------------------------------------------------------+
//| Test_StrategyRouter.mq5                                           |
//| Themba Adaptive Intraday Engine — TASK-024 compile/logic test      |
//|                                                                    |
//| Covers SignalScorer.mqh (base score, all five adapters),              |
//| StrategyRouter.mqh (eligibility multiplier matrix, end-to-end          |
//| routing), and ConflictResolver.mqh (single-winner, gap-met,             |
//| gap-not-met, and no-eligible-candidates cases) — all hand-computed.      |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Routing/ConflictResolver.mqh"

int g_pass = 0;
int g_fail = 0;

void Check(const string label, const bool condition)
  {
   if(condition) { PrintFormat("PASS: %s", label); g_pass++; }
   else          { PrintFormat("FAIL: %s", label); g_fail++; }
  }

bool NearlyEqual(const double a, const double b, const double tol = 0.001)
  {
   return MathAbs(a - b) <= tol;
  }

void OnStart()
  {
   Print("=== TASK-024 StrategyRouter/SignalScorer/ConflictResolver test start ===");

   //--- 1. SS_ComputeBaseScore ------------------------------------------
   {
      STradeCandidate c = SS_EmptyCandidate();
      c.found = true;
      c.entry_price = 100; c.stop_price = 99; c.target_price = 103; // risk1,reward3,R=3.0
      double base;
      bool ok = SS_ComputeBaseScore(c, 0.8, base);
      Check("base score computes successfully", ok);
      Check("base score == 90.0 (0.5*min(1,3/3) + 0.5*0.8 = 0.9 -> 90)",
            NearlyEqual(base, 90.0));

      STradeCandidate cZeroRisk = SS_EmptyCandidate();
      cZeroRisk.found = true;
      cZeroRisk.entry_price = 100; cZeroRisk.stop_price = 100; cZeroRisk.target_price = 105;
      double baseZero;
      Check("zero-risk candidate (entry==stop) fails to score",
            SS_ComputeBaseScore(cZeroRisk, 0.8, baseZero) == false);
   }

   //--- 2. Adapters -------------------------------------------------------
   {
      SSRBounceSignal srSig;
      srSig.found = true; srSig.direction = SRB_LONG; srSig.entry_price = 100;
      srSig.zone_price = 95; srSig.zone_touch_count = 2; srSig.stop_price = 94;
      srSig.target_price = 110; srSig.candlestick_pattern = "bullish_pin_bar";
      STradeCandidate srCand = SS_FromSRBounce(srSig);
      Check("SR-bounce adapter: found", srCand.found);
      Check("SR-bounce adapter: family is FAMILY_SR_BOUNCE", srCand.family == FAMILY_SR_BOUNCE);
      Check("SR-bounce adapter: direction is CAND_LONG", srCand.direction == CAND_LONG);
      Check("SR-bounce adapter: setup == support_bounce", srCand.setup == "support_bounce");
      Check("SR-bounce adapter: stop_price == 94", NearlyEqual(srCand.stop_price, 94.0));

      SSRBounceSignal srSigEmpty;
      srSigEmpty.found = false;
      STradeCandidate srCandEmpty = SS_FromSRBounce(srSigEmpty);
      Check("SR-bounce adapter: not-found signal produces not-found candidate",
            srCandEmpty.found == false);

      SSMCSignal smcSig;
      smcSig.found = true; smcSig.setup_type = SMC_SETUP_FVG_RETURN; smcSig.direction = SMCD_SHORT;
      smcSig.entry_price = 200; smcSig.zone_high = 205; smcSig.zone_low = 195;
      smcSig.stop_price = 206; smcSig.target_price = 190; smcSig.candlestick_pattern = "bearish_engulfing";
      STradeCandidate smcCand = SS_FromSMC(smcSig);
      Check("SMC adapter: found", smcCand.found);
      Check("SMC adapter: family is FAMILY_SMC_ICT", smcCand.family == FAMILY_SMC_ICT);
      Check("SMC adapter: setup == fvg_return", smcCand.setup == "fvg_return");
      Check("SMC adapter: direction is CAND_SHORT", smcCand.direction == CAND_SHORT);
   }

   //--- 3. Eligibility multiplier matrix -----------------------------------
   Check("SR Bounce is preferred in RANGING (1.10)",
         NearlyEqual(SR_GetEligibilityMultiplier(FAMILY_SR_BOUNCE, REGIME_RANGING), 1.10));
   Check("SR Bounce is blocked in TRENDING_UP (0.0)",
         NearlyEqual(SR_GetEligibilityMultiplier(FAMILY_SR_BOUNCE, REGIME_TRENDING_UP), 0.0));
   Check("Trend Following is preferred in TRENDING_DOWN (1.10)",
         NearlyEqual(SR_GetEligibilityMultiplier(FAMILY_TREND_FOLLOWING, REGIME_TRENDING_DOWN), 1.10));
   Check("Post-Expansion Retest is preferred in VOLATILITY_EXPANSION_UP (1.10)",
         NearlyEqual(SR_GetEligibilityMultiplier(FAMILY_POST_EXPANSION_RETEST,
                                                  REGIME_VOLATILITY_EXPANSION_UP), 1.10));
   Check("Every family is blocked in COMPRESSION (0.0)",
         NearlyEqual(SR_GetEligibilityMultiplier(FAMILY_TREND_FOLLOWING, REGIME_COMPRESSION), 0.0));
   Check("Every family is blocked in NEWS_BLACKOUT (0.0)",
         NearlyEqual(SR_GetEligibilityMultiplier(FAMILY_SMC_ICT, REGIME_NEWS_BLACKOUT), 0.0));

   //--- 4. STR_RouteCandidates end-to-end ----------------------------------
   {
      STradeCandidate candidates[2];
      candidates[0] = SS_EmptyCandidate();
      candidates[0].found = true; candidates[0].family = FAMILY_SR_BOUNCE;
      candidates[0].direction = CAND_LONG;
      candidates[0].entry_price = 100; candidates[0].stop_price = 99; candidates[0].target_price = 102;

      candidates[1] = SS_EmptyCandidate();
      candidates[1].found = true; candidates[1].family = FAMILY_TREND_FOLLOWING;
      candidates[1].direction = CAND_SHORT;
      candidates[1].entry_price = 100; candidates[1].stop_price = 101; candidates[1].target_price = 98;

      SRoutedCandidate routed[];
      int eligible_count = STR_RouteCandidates(candidates, 2, REGIME_RANGING, 0.8, routed);
      Check("exactly one candidate is eligible in RANGING (SR Bounce only)", eligible_count == 1);
      Check("SR-bounce candidate (index 0) is eligible", routed[0].eligible);
      Check("SR-bounce candidate final_score == 80.6667 (73.3333 * 1.10)",
            NearlyEqual(routed[0].final_score, 80.6667, 0.01));
      Check("trend-following candidate (index 1) is blocked", routed[1].eligible == false);
      Check("trend-following candidate reason == blocked_by_regime",
            routed[1].reason == "blocked_by_regime");
   }

   //--- 5. CR_ResolveConflicts ------------------------------------------------
   {
      // 5a. Single-direction winner
      SRoutedCandidate rSingle[1];
      rSingle[0].candidate = SS_EmptyCandidate();
      rSingle[0].candidate.found = true; rSingle[0].candidate.direction = CAND_LONG;
      rSingle[0].eligible = true; rSingle[0].final_score = 75.0;
      SConflictResult res1;
      bool ok1 = CR_ResolveConflicts(rSingle, 1, 10.0, res1);
      Check("single-direction winner: resolves successfully", ok1 && res1.has_winner);
      Check("single-direction winner: direction is CAND_LONG", res1.winning_direction == CAND_LONG);
      Check("single-direction winner: score == 75.0", NearlyEqual(res1.winner_score, 75.0));

      // 5b. Opposing directions, gap met (20 >= 10)
      SRoutedCandidate rGapMet[2];
      rGapMet[0].candidate = SS_EmptyCandidate(); rGapMet[0].candidate.direction = CAND_LONG;
      rGapMet[0].eligible = true; rGapMet[0].final_score = 80.0;
      rGapMet[1].candidate = SS_EmptyCandidate(); rGapMet[1].candidate.direction = CAND_SHORT;
      rGapMet[1].eligible = true; rGapMet[1].final_score = 60.0;
      SConflictResult res2;
      bool ok2 = CR_ResolveConflicts(rGapMet, 2, 10.0, res2);
      Check("opposing directions, gap met: resolves with LONG winning",
            ok2 && res2.has_winner && res2.winning_direction == CAND_LONG);

      // 5c. Opposing directions, gap NOT met (5 < 10) -> No trade
      SRoutedCandidate rGapNotMet[2];
      rGapNotMet[0].candidate = SS_EmptyCandidate(); rGapNotMet[0].candidate.direction = CAND_LONG;
      rGapNotMet[0].eligible = true; rGapNotMet[0].final_score = 55.0;
      rGapNotMet[1].candidate = SS_EmptyCandidate(); rGapNotMet[1].candidate.direction = CAND_SHORT;
      rGapNotMet[1].eligible = true; rGapNotMet[1].final_score = 50.0;
      SConflictResult res3;
      bool ok3 = CR_ResolveConflicts(rGapNotMet, 2, 10.0, res3);
      Check("opposing directions, gap not met: No trade (no winner)",
            ok3 == false && res3.has_winner == false);
      Check("opposing directions, gap not met: reason is set",
            res3.reason == "opposing_directions_gap_not_met");

      // 5d. No eligible candidates at all -> No trade
      SRoutedCandidate rNone[1];
      rNone[0].candidate = SS_EmptyCandidate();
      rNone[0].eligible = false;
      SConflictResult res4;
      bool ok4 = CR_ResolveConflicts(rNone, 1, 10.0, res4);
      Check("no eligible candidates: No trade (no winner)",
            ok4 == false && res4.has_winner == false);
      Check("no eligible candidates: reason is set", res4.reason == "no_eligible_candidates");
   }

   PrintFormat("=== TASK-024 test complete: %d passed, %d failed ===", g_pass, g_fail);
  }
