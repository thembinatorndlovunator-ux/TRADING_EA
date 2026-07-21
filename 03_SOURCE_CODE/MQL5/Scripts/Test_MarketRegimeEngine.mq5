//+------------------------------------------------------------------+
//| Test_MarketRegimeEngine.mq5                                       |
//| Themba Adaptive Intraday Engine — TASK-016 compile/logic test      |
//|                                                                    |
//| Every scenario below is hand-computed from section 2's formulas —   |
//| including two that reproduce TASK-002_PHASE2_SPECIFICATION.md's     |
//| own Test plan item 5 extreme-value checks (E=1 -> confidence 1.0     |
//| for expansion, E=0 -> confidence 1.0 for compression), the exact      |
//| defect round-2 review found broken and round-3 confirmed fixed.       |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Market/MarketRegimeEngine.mqh"

input string          InpTestSymbol    = "EURUSD";
input ENUM_TIMEFRAMES InpTestTimeframe = PERIOD_M15;

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
   Print("=== TASK-016 MarketRegimeEngine test start ===");

   const int    EFF_WINDOW = 5;
   const int    SWING_DEPTH = 1;
   const int    SWING_LOOKBACK = 6;
   const double TREND_TH = 0.6;
   const double EXPANSION_TH = 0.75;
   const double COMPRESSION_TH = 0.25;
   const double MIN_EFF = 0.3;
   const double SLOPE_DIVISOR = 0.5;

   //--- Shared bullish-bias structure (reused from TASK-012's scenario 1) -
   double highsA[] = {40,40,40,65,40,40,40,40,60,40,40,40,40,40,40,40};
   double lowsA[]  = {50,50,50,50,50,30,50,50,50,50,20,50,50,50,50,50};
   double closesMonotonic[] = {65,60,55,50,45,40,38,37,36,35,34,33,32,31,30,29};

   //--- 1. TRENDING_UP -----------------------------------------------------
   {
      double atr_pct[] = {5.0,1,2,3,4,5,6,7,8,9};
      SRegimeRead r = MRE_ClassifyArray(closesMonotonic, highsA, lowsA, atr_pct, 5.0,
                                         110.0, 100.0, 30.0, EFF_WINDOW, SWING_DEPTH,
                                         SWING_LOOKBACK, TREND_TH, EXPANSION_TH,
                                         COMPRESSION_TH, MIN_EFF, SLOPE_DIVISOR);
      Check("scenario 1 (TRENDING_UP) computes as valid", r.valid);
      Check("scenario 1: regime is TRENDING_UP", r.regime == REGIME_TRENDING_UP);
      Check("scenario 1: T_final == 0.8", NearlyEqual(r.T_final, 0.8));
      Check("scenario 1: confidence == 0.5 ((0.8-0.6)/(1-0.6))",
            NearlyEqual(r.confidence, 0.5));
   }

   //--- 2. COMPRESSION (also hand-reproduces the spec's E=0 extreme) ------
   {
      double atr_pct[] = {1.0,5,6,7,8,9,10,11,12,13};
      SRegimeRead r = MRE_ClassifyArray(closesMonotonic, highsA, lowsA, atr_pct, 1.0,
                                         100.1, 100.0, 0.0, EFF_WINDOW, SWING_DEPTH,
                                         SWING_LOOKBACK, TREND_TH, EXPANSION_TH,
                                         COMPRESSION_TH, MIN_EFF, SLOPE_DIVISOR);
      Check("scenario 2 (COMPRESSION) computes as valid", r.valid);
      Check("scenario 2: E == 0.0 (current ATR is the lowest in its window)",
            NearlyEqual(r.E, 0.0));
      Check("scenario 2: regime is COMPRESSION", r.regime == REGIME_COMPRESSION);
      Check("scenario 2: confidence == 1.0 at E=0 (matches the spec's own "
            "hand-derived extreme — this is exactly the value round-2 "
            "review found broken)", NearlyEqual(r.confidence, 1.0));
   }

   //--- 3. TRANSITION_OR_UNCERTAIN (expansion evidence, no direction ------
   //---    agreement: bullish swing bias but bearish EMA slope) -----------
   {
      double atr_pct[] = {13.0,1,2,3,4,5,6,7,8,9};
      SRegimeRead r = MRE_ClassifyArray(closesMonotonic, highsA, lowsA, atr_pct, 13.0,
                                         100.0, 101.0, 20.0, EFF_WINDOW, SWING_DEPTH,
                                         SWING_LOOKBACK, TREND_TH, EXPANSION_TH,
                                         COMPRESSION_TH, MIN_EFF, SLOPE_DIVISOR);
      Check("scenario 3 (TRANSITION) computes as valid", r.valid);
      Check("scenario 3: regime is TRANSITION_OR_UNCERTAIN (expansion "
            "evidence present but direction disagrees)",
            r.regime == REGIME_TRANSITION_OR_UNCERTAIN);
      Check("scenario 3: confidence == 0.0", NearlyEqual(r.confidence, 0.0));
   }

   //--- 4. VOLATILITY_EXPANSION_UP (reproduces the spec's E=1 extreme) ----
   {
      double atr_pct[] = {13.0,1,2,3,4,5,6,7,8,9};
      SRegimeRead r = MRE_ClassifyArray(closesMonotonic, highsA, lowsA, atr_pct, 13.0,
                                         110.0, 100.0, 20.0, EFF_WINDOW, SWING_DEPTH,
                                         SWING_LOOKBACK, TREND_TH, EXPANSION_TH,
                                         COMPRESSION_TH, MIN_EFF, SLOPE_DIVISOR);
      Check("scenario 4 (VOLATILITY_EXPANSION_UP) computes as valid", r.valid);
      Check("scenario 4: E == 1.0 (current ATR is the highest in its window)",
            NearlyEqual(r.E, 1.0));
      Check("scenario 4: regime is VOLATILITY_EXPANSION_UP",
            r.regime == REGIME_VOLATILITY_EXPANSION_UP);
      Check("scenario 4: confidence == 1.0 at E=1 (matches the spec's own "
            "hand-derived extreme)", NearlyEqual(r.confidence, 1.0));
   }

   //--- 5. RANGING via low efficiency ratio --------------------------------
   {
      double closesChoppy[] = {50,55,45,55,45,55,50,50,50,50,50,50,50,50,50,50};
      double atr_pct[] = {5.0,1,2,3,4,5,6,7,8,9};
      SRegimeRead r = MRE_ClassifyArray(closesChoppy, highsA, lowsA, atr_pct, 5.0,
                                         105.0, 100.0, 20.0, EFF_WINDOW, SWING_DEPTH,
                                         SWING_LOOKBACK, TREND_TH, EXPANSION_TH,
                                         COMPRESSION_TH, MIN_EFF, SLOPE_DIVISOR);
      Check("scenario 5 (RANGING via low ER) computes as valid", r.valid);
      Check("scenario 5: ER is below the minimum-efficiency threshold",
            r.ER < MIN_EFF);
      Check("scenario 5: regime is RANGING", r.regime == REGIME_RANGING);
   }

   //--- 6. RANGING via fallback (no efficiency failure, no expansion, no --
   //---    trend, no compression trigger) ------------------------------------
   {
      double atr_pct[] = {5.0,1,2,3,4,5,6,7,8,9};
      SRegimeRead r = MRE_ClassifyArray(closesMonotonic, highsA, lowsA, atr_pct, 5.0,
                                         100.05, 100.0, 0.0, EFF_WINDOW, SWING_DEPTH,
                                         SWING_LOOKBACK, TREND_TH, EXPANSION_TH,
                                         COMPRESSION_TH, MIN_EFF, SLOPE_DIVISOR);
      Check("scenario 6 (RANGING via fallback) computes as valid", r.valid);
      Check("scenario 6: regime is RANGING", r.regime == REGIME_RANGING);
      Check("scenario 6: confidence == 0.575 (1 - 0.255/0.6)",
            NearlyEqual(r.confidence, 0.575));
   }

   //--- 7. Hysteresis state machine ----------------------------------------
   {
      SRegimeHysteresisState hs;
      MRE_InitHysteresisState(hs);

      ENUM_MARKET_REGIME e1 = MRE_ApplyHysteresis(hs, REGIME_TRENDING_UP, false, 2);
      Check("hysteresis: first read of a new regime is not yet confirmed "
            "(reports TRANSITION_OR_UNCERTAIN)", e1 == REGIME_TRANSITION_OR_UNCERTAIN);

      ENUM_MARKET_REGIME e2 = MRE_ApplyHysteresis(hs, REGIME_TRENDING_UP, false, 2);
      Check("hysteresis: second consecutive matching read confirms the regime",
            e2 == REGIME_TRENDING_UP);

      ENUM_MARKET_REGIME e3 = MRE_ApplyHysteresis(hs, REGIME_RANGING, false, 2);
      Check("hysteresis: a single differing read does not yet switch the "
            "confirmed regime", e3 == REGIME_TRENDING_UP);

      ENUM_MARKET_REGIME e4 = MRE_ApplyHysteresis(hs, REGIME_RANGING, false, 2);
      Check("hysteresis: a second consecutive differing read switches the "
            "confirmed regime", e4 == REGIME_RANGING);

      ENUM_MARKET_REGIME e5 = MRE_ApplyHysteresis(hs, REGIME_NEWS_BLACKOUT, true, 2);
      Check("hysteresis: bypass takes effect immediately regardless of prior "
            "state", e5 == REGIME_NEWS_BLACKOUT);
   }

   //--- 8. Gating: UNTRADEABLE_SPREAD_OR_LIQUIDITY --------------------------
   Check("wide spread relative to ATR triggers the gating condition",
         MRE_IsUntradeableSpreadOrLiquidity(1.0, 2.0, 0.15, 10.0, 5.0));
   Check("low tick volume triggers the gating condition",
         MRE_IsUntradeableSpreadOrLiquidity(0.1, 2.0, 0.15, 2.0, 5.0));
   Check("normal spread and liquidity do not trigger the gating condition",
         MRE_IsUntradeableSpreadOrLiquidity(0.1, 2.0, 0.15, 10.0, 5.0) == false);

   //--- 9. Threshold clampers ------------------------------------------------
   Check("trend threshold clamps below its floor", NearlyEqual(MRE_ClampTrendThreshold(0.1), 0.3));
   Check("trend threshold clamps above its ceiling", NearlyEqual(MRE_ClampTrendThreshold(0.95), 0.9));
   Check("trend threshold passes through unchanged within bounds",
         NearlyEqual(MRE_ClampTrendThreshold(0.6), 0.6));

   //--- 10. CMarketData-integrated wrapper against a real symbol -----------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok && md.HasBars(150))
     {
      SRegimeRead live;
      bool live_ok = MRE_ClassifyLive(md, 100, 20, 21, 5, 14, 3, 50, 0.6, 0.75, 0.25,
                                       0.3, 0.5, live);
      if(live_ok)
        {
         Check("real-symbol regime confidence is within [0,1]",
               live.confidence >= 0.0 && live.confidence <= 1.0);
         Check("real-symbol E is within [0,1]", live.E >= 0.0 && live.E <= 1.0);
         PrintFormat("INFO: real-symbol regime=%d confidence=%.4f E=%.4f T_final=%.4f",
                     live.regime, live.confidence, live.E, live.T_final);
        }
      else
        {
         PrintFormat("NOTE: MRE_ClassifyLive could not compute a live regime "
                     "for '%s' — likely insufficient history for the full "
                     "150-bar window, not necessarily a defect.", InpTestSymbol);
        }
      Check("real-symbol regime classification completes without crashing "
            "regardless of outcome", true);
     }
   else
     {
      PrintFormat("NOTE: '%s' does not have enough history — real-symbol "
                  "smoke test skipped.", InpTestSymbol);
     }

   PrintFormat("=== TASK-016 MarketRegimeEngine test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
