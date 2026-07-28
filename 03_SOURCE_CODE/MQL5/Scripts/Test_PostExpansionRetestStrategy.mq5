//+------------------------------------------------------------------+
//| Test_PostExpansionRetestStrategy.mq5                              |
//| Themba Adaptive Intraday Engine — TASK-023 compile/logic test      |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Strategies/PostExpansionRetestStrategy.mqh"

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

SPERConfig MakeConfig()
  {
   SPERConfig cfg;
   cfg.depth = 1;
   cfg.max_lookback = 8;
   cfg.min_expansion_atr = 1.5;
   cfg.retest_tolerance_atr = 0.3;
   cfg.no_chase_bars = 2;
   cfg.stop_buffer_atr = 0.1;
   cfg.candlestick_trend_lookback = 5;
   return cfg;
  }

SMarketStructureState MakeStructure(const double swing_high, const double swing_low,
                                     const int last_event_index)
  {
   SMarketStructureState s;
   s.valid = true;
   s.bias = STRUCTURE_BIAS_NEUTRAL;
   s.last_event = STRUCTURE_EVENT_NONE;
   s.last_event_index = last_event_index;
   s.has_swing_high_2 = false;
   s.has_swing_low_2 = false;
   s.swing_high_1_index = 0;
   s.swing_high_1_price = swing_high;
   s.swing_low_1_index = 0;
   s.swing_low_1_price = swing_low;
   s.range_high = swing_high;
   s.range_low = swing_low;
   s.equilibrium = (swing_high + swing_low) / 2.0;
   return s;
  }

void OnStart()
  {
   Print("=== TASK-023 PostExpansionRetestStrategy test start ===");
   SPERConfig cfg = MakeConfig();

   //--- Base scenario: VOLATILITY_EXPANSION_UP, reference level = 100, ---
   //--- genuine expansion (highs[3]=105 > 100+2*1.5=103), fresh enough ----
   //--- (last_event_index=5 >= no_chase_bars=2), retest at closes[0]=100.2 -
   double opens[]  = {98.2, 60,60,60,60,60,60,60,60,60};
   double highs[]  = {101.2,60,60,105,60,60,60,60,60,60};
   double lows[]   = {93.2, 60,60,60,60,60,60,60,60,60};
   double closes[] = {100.2,60,60,60,60,105,60,60,60,60};
   double atr[]    = {2,2,2,2,2,2,2,2,2,2};
   SMarketStructureState structure = MakeStructure(100.0, 50.0, 5);

   //--- 1. Positive scenario ------------------------------------------------
   SPostExpansionRetestSignal sig;
   bool ok = PER_EvaluateArray(opens, highs, lows, closes, atr, REGIME_VOLATILITY_EXPANSION_UP,
                                structure, cfg, sig);
   Check("signal found", ok && sig.found);
   Check("direction is PERD_LONG", sig.direction == PERD_LONG);
   Check("reference_level == 100", NearlyEqual(sig.reference_level, 100.0));
   Check("stop_price == 99.8 (100 - 2*0.1)", NearlyEqual(sig.stop_price, 99.8));
   Check("target_price == 101.0 (100.2 + 2*0.4)", NearlyEqual(sig.target_price, 101.0));
   Check("candlestick_pattern == bullish_pin_bar", sig.candlestick_pattern == "bullish_pin_bar");

   //--- 2. Negative: wrong regime -------------------------------------------
   SPostExpansionRetestSignal sigRegime;
   bool okRegime = PER_EvaluateArray(opens, highs, lows, closes, atr, REGIME_TRENDING_UP,
                                      structure, cfg, sigRegime);
   Check("wrong regime (TRENDING_UP) produces no signal",
         okRegime == false && sigRegime.found == false);

   //--- 3. Negative: too soon after the triggering break (no-chase) --------
   SMarketStructureState structureFresh = MakeStructure(100.0, 50.0, 1); // < no_chase_bars=2
   SPostExpansionRetestSignal sigChase;
   bool okChase = PER_EvaluateArray(opens, highs, lows, closes, atr, REGIME_VOLATILITY_EXPANSION_UP,
                                     structureFresh, cfg, sigChase);
   Check("a too-recent triggering break is rejected by the defensive no-chase check",
         okChase == false && sigChase.found == false);

   //--- 4. Negative: no genuine expansion (spike removed) -------------------
   double highsNoSpike[10];
   ArrayCopy(highsNoSpike, highs);
   highsNoSpike[3] = 60.0; // remove the 105 spike
   SPostExpansionRetestSignal sigNoExp;
   bool okNoExp = PER_EvaluateArray(opens, highsNoSpike, lows, closes, atr,
                                     REGIME_VOLATILITY_EXPANSION_UP, structure, cfg, sigNoExp);
   Check("no genuine expansion move (no bar exceeded the min-expansion threshold) "
         "produces no signal", okNoExp == false && sigNoExp.found == false);

   //--- 5. Negative: price not currently retesting the reference level -----
   double closesFar[10];
   ArrayCopy(closesFar, closes);
   closesFar[0] = 150.0; // far from reference_level=100
   SPostExpansionRetestSignal sigFar;
   bool okFar = PER_EvaluateArray(opens, highs, lows, closesFar, atr,
                                   REGIME_VOLATILITY_EXPANSION_UP, structure, cfg, sigFar);
   Check("price far from the reference level produces no signal",
         okFar == false && sigFar.found == false);

   //--- 6. CMarketData-integrated wrapper against a real symbol -----------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok && md.HasBars(150))
     {
      SPostExpansionRetestSignal live;
      bool live_ok = PER_EvaluateLive(md, 100, 20, 21, 5, 14, 0.6, 0.75, 0.25, 0.3, 0.5, cfg, live);
      Check("real-symbol post-expansion-retest evaluation completes without crashing "
            "regardless of outcome", true);
      PrintFormat("INFO: real-symbol post-expansion-retest evaluation found=%s",
                  (live_ok && live.found) ? "true" : "false");
     }
   else
     {
      PrintFormat("NOTE: '%s' does not have enough history — real-symbol "
                  "smoke test skipped.", InpTestSymbol);
     }

   PrintFormat("=== TASK-023 PostExpansionRetestStrategy test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
