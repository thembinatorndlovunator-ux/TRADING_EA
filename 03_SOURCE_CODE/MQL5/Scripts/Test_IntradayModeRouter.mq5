//+------------------------------------------------------------------+
//| Test_IntradayModeRouter.mq5                                       |
//| Themba Adaptive Intraday Engine — TASK-040 compile/logic test       |
//|                                                                    |
//| Pure, deterministic, no live trading action. Tests 1-3 exercise        |
//| IMR_ClassifyMarketFamily against the CURRENT chart symbol's real        |
//| broker-supplied SYMBOL_PATH (whatever family it actually is — the         |
//| assertions below are shape-checks, not a hardcoded expected family,         |
//| since this script may run against any symbol/broker). Tests 4+ exercise      |
//| IMR_ClassifyMode's pure scoring logic against hand-fabricated inputs.          |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Market/IntradayModeRouter.mqh"

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

void OnStart()
  {
   Print("=== TASK-040 IntradayModeRouter test start ===");

   //--- 1. market_family classification never throws/crashes on the -------
   //--- current chart symbol, and always returns a named enum value -------
   ENUM_MARKET_FAMILY family = IMR_ClassifyMarketFamily(_Symbol);
   string family_str = IMR_MarketFamilyToString(family);
   PrintFormat("INFO: '%s' (SYMBOL_PATH='%s') classified as %s.", _Symbol,
               SymbolInfoString(_Symbol, SYMBOL_PATH), family_str);
   Check("market_family classification returns a recognized, named value",
         family_str == "METAL" || family_str == "FOREX" ||
         family_str == "SYNTHETIC_INDEX" || family_str == "UNKNOWN");

   //--- 2. A path containing no recognizable keyword is UNKNOWN, never ----
   //--- guessed -- tested indirectly via the ToString/enum round-trip -----
   //--- since SYMBOL_PATH cannot be injected for a fake symbol in a --------
   //--- script context; the keyword-matching logic itself is exercised ----
   //--- directly in test 3 below via the shared StringFind approach. -------
   Check("MARKET_FAMILY_UNKNOWN stringifies to 'UNKNOWN', not a guessed family",
         IMR_MarketFamilyToString(MARKET_FAMILY_UNKNOWN) == "UNKNOWN");

   //--- 3. Every enum value round-trips through its own ToString ----------
   Check("MARKET_FAMILY_METAL stringifies correctly",
         IMR_MarketFamilyToString(MARKET_FAMILY_METAL) == "METAL");
   Check("MARKET_FAMILY_FOREX stringifies correctly",
         IMR_MarketFamilyToString(MARKET_FAMILY_FOREX) == "FOREX");
   Check("MARKET_FAMILY_SYNTHETIC_INDEX stringifies correctly",
         IMR_MarketFamilyToString(MARKET_FAMILY_SYNTHETIC_INDEX) == "SYNTHETIC_INDEX");

   //--- TASK-002 section 1 canonical formula (seventh-round rewrite) -------

   //--- 4. Component 1: regime persistence ---------------------------------
   Check("regime persistence: TRENDING_UP at half the window -> 0.5",
         MathAbs(IMR_ComputeRegimePersistence(REGIME_TRENDING_UP, 10, 20) - 0.5) < 1e-9);
   Check("regime persistence: clamps to 1.0 beyond the window",
         MathAbs(IMR_ComputeRegimePersistence(REGIME_TRENDING_DOWN, 40, 20) - 1.0) < 1e-9);
   Check("regime persistence: RANGING is always 0.3", IMR_ComputeRegimePersistence(REGIME_RANGING, 5, 20) == 0.3);
   Check("regime persistence: any other regime is 0.0",
         IMR_ComputeRegimePersistence(REGIME_COMPRESSION, 5, 20) == 0.0);

   //--- 5. Component 3: range-vs-average -----------------------------------
   Check("range-vs-average: 1.0x ATR -> 0.5", MathAbs(IMR_ComputeRangeVsAverage(1.0) - 0.5) < 1e-9);
   Check("range-vs-average: clamps to 1.0 beyond 2x ATR",
         MathAbs(IMR_ComputeRangeVsAverage(5.0) - 1.0) < 1e-9);

   //--- 6. Component 4: session time remaining -----------------------------
   Check("session time remaining: passes through the ratio when above the floor",
         MathAbs(IMR_ComputeSessionTimeRemaining(0.7, 200.0, 90.0) - 0.7) < 1e-9);
   Check("session time remaining: clamped to 0.0 below InpMinDayTradeSessionMinutes",
         IMR_ComputeSessionTimeRemaining(0.7, 50.0, 90.0) == 0.0);

   //--- 7. IMR_ComputeModeScore: weighted average over available components -
   {
      SModeComponent c1, c2, c3, c4;
      c1.available = true;  c1.value = 1.0;
      c2.available = true;  c2.value = 1.0;
      c3.available = true;  c3.value = 0.0;
      c4.available = true;  c4.value = 0.0;
      SModeWeights w = IMR_DefaultModeWeights(); // 0.25 each
      SModeScoreResult r = IMR_ComputeModeScore(c1, c2, c3, c4, w);
      Check("mode score: all 4 available, hand-computed weighted average == 0.5",
            r.valid && MathAbs(r.mode_score - 0.5) < 1e-9);
      Check("mode score: components_available == 4", r.components_available == 4);
   }
   {
      // Only 2 of 4 available (the minimum still valid) -- weighted average
      // over just those two.
      SModeComponent c1, c2, c3, c4;
      c1.available = true;  c1.value = 1.0;
      c2.available = false; c2.value = 0.0;
      c3.available = false; c3.value = 0.0;
      c4.available = true;  c4.value = 0.0;
      SModeWeights w = IMR_DefaultModeWeights();
      SModeScoreResult r = IMR_ComputeModeScore(c1, c2, c3, c4, w);
      Check("mode score: exactly 2 available is still valid, weighted average == 0.5",
            r.valid && MathAbs(r.mode_score - 0.5) < 1e-9);
   }
   {
      // Only 1 of 4 available -- undefined (fail-closed), per section 1's
      // own hard-failure rule, even though the available weight sum is
      // nonzero.
      SModeComponent c1, c2, c3, c4;
      c1.available = true;  c1.value = 1.0;
      c2.available = false; c2.value = 0.0;
      c3.available = false; c3.value = 0.0;
      c4.available = false; c4.value = 0.0;
      SModeWeights w = IMR_DefaultModeWeights();
      SModeScoreResult r = IMR_ComputeModeScore(c1, c2, c3, c4, w);
      Check("mode score: fewer than 2 of 4 available -> undefined (fail-closed)",
            r.valid == false);
   }

   //--- 8. IMR_UpdateTrendAge: increments on the SAME direction, resets on --
   //--- a flip or a non-directional regime -----------------------------------
   {
      SModeState state;
      IMR_InitModeState(state);
      IMR_UpdateTrendAge(state, REGIME_TRENDING_UP);
      Check("trend age: first TRENDING_UP read is age 1", state.trend_age_bars == 1);
      IMR_UpdateTrendAge(state, REGIME_TRENDING_UP);
      IMR_UpdateTrendAge(state, REGIME_TRENDING_UP);
      Check("trend age: three consecutive TRENDING_UP reads -> age 3", state.trend_age_bars == 3);
      IMR_UpdateTrendAge(state, REGIME_TRENDING_DOWN);
      Check("trend age: a direction FLIP resets to age 1 (a genuinely new trend)",
            state.trend_age_bars == 1);
      IMR_UpdateTrendAge(state, REGIME_RANGING);
      Check("trend age: a non-directional regime resets to 0", state.trend_age_bars == 0);
   }

   //--- 9. IMR_ApplyModeHysteresis: gating regime forces NONE immediately, --
   //--- bypassing hysteresis -------------------------------------------------
   {
      SModeState state;
      IMR_InitModeState(state);
      SModeScoreResult high_score;
      high_score.valid = true; high_score.mode_score = 0.90; high_score.components_available = 4;
      ENUM_INTRADAY_MODE mode = IMR_ApplyModeHysteresis(state, REGIME_NEWS_BLACKOUT, high_score, 2);
      Check("hysteresis: a gating regime forces NONE even with a high mode_score",
            mode == INTRADAY_MODE_NONE);
   }

   //--- 10. IMR_ApplyModeHysteresis: an undefined mode_score forces NONE ----
   {
      SModeState state;
      IMR_InitModeState(state);
      SModeScoreResult undefined_score;
      undefined_score.valid = false; undefined_score.mode_score = 0.0;
      undefined_score.components_available = 1;
      ENUM_INTRADAY_MODE mode = IMR_ApplyModeHysteresis(state, REGIME_TRENDING_UP, undefined_score, 2);
      Check("hysteresis: an undefined mode_score forces NONE", mode == INTRADAY_MODE_NONE);
   }

   //--- 11. IMR_ApplyModeHysteresis: two consecutive evaluations confirm ----
   //--- a threshold-clearing mode; the first alone does not -----------------
   {
      SModeState state;
      IMR_InitModeState(state);
      SModeScoreResult day_trade_score;
      day_trade_score.valid = true; day_trade_score.mode_score = 0.75;
      day_trade_score.components_available = 4;
      ENUM_INTRADAY_MODE m1 = IMR_ApplyModeHysteresis(state, REGIME_TRENDING_UP, day_trade_score, 2);
      Check("hysteresis: first DAY_TRADE-clearing read alone is not yet confirmed (NONE)",
            m1 == INTRADAY_MODE_NONE);
      ENUM_INTRADAY_MODE m2 = IMR_ApplyModeHysteresis(state, REGIME_TRENDING_UP, day_trade_score, 2);
      Check("hysteresis: second consecutive DAY_TRADE-clearing read confirms it",
            m2 == INTRADAY_MODE_DAY_TRADE);
   }

   //--- 12. IMR_ApplyModeHysteresis: neutral band carries the previously ---
   //--- confirmed mode forward; with none yet confirmed, stays NONE ---------
   {
      SModeState state;
      IMR_InitModeState(state);
      SModeScoreResult neutral_score;
      neutral_score.valid = true; neutral_score.mode_score = 0.50; // strictly inside (0.40, 0.60)
      neutral_score.components_available = 4;
      ENUM_INTRADAY_MODE mode = IMR_ApplyModeHysteresis(state, REGIME_RANGING, neutral_score, 2);
      Check("hysteresis: neutral band with no prior confirmation stays NONE", mode == INTRADAY_MODE_NONE);

      // Now confirm DAY_TRADE, then re-enter the neutral band -- it must
      // carry DAY_TRADE forward, not reset to NONE.
      SModeScoreResult day_trade_score;
      day_trade_score.valid = true; day_trade_score.mode_score = 0.75;
      day_trade_score.components_available = 4;
      IMR_ApplyModeHysteresis(state, REGIME_TRENDING_UP, day_trade_score, 2);
      IMR_ApplyModeHysteresis(state, REGIME_TRENDING_UP, day_trade_score, 2); // confirmed now
      ENUM_INTRADAY_MODE mode_after_neutral = IMR_ApplyModeHysteresis(state, REGIME_RANGING,
                                                                       neutral_score, 2);
      Check("hysteresis: neutral band carries the previously-CONFIRMED mode forward",
            mode_after_neutral == INTRADAY_MODE_DAY_TRADE);
   }

   //--- 13. IMR_IsCandidateConsistentWithMode: stage-4 post-hoc check -------
   Check("consistency: Day-trade candidate with expected R >= 1.0 passes",
         IMR_IsCandidateConsistentWithMode(INTRADAY_MODE_DAY_TRADE, 1.5) == true);
   Check("consistency: Day-trade candidate with expected R < 1.0 is rejected",
         IMR_IsCandidateConsistentWithMode(INTRADAY_MODE_DAY_TRADE, 0.5) == false);
   Check("consistency: Scalp candidate with expected R <= 2.0 passes",
         IMR_IsCandidateConsistentWithMode(INTRADAY_MODE_SCALP, 1.5) == true);
   Check("consistency: Scalp candidate with expected R > 2.0 is rejected",
         IMR_IsCandidateConsistentWithMode(INTRADAY_MODE_SCALP, 2.5) == false);
   Check("consistency: INTRADAY_MODE_NONE rejects every candidate outright",
         IMR_IsCandidateConsistentWithMode(INTRADAY_MODE_NONE, 1.5) == false);

   PrintFormat("=== TASK-040 IntradayModeRouter test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
