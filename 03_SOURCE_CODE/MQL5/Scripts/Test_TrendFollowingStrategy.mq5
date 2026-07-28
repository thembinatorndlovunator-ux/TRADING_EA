//+------------------------------------------------------------------+
//| Test_TrendFollowingStrategy.mq5                                   |
//| Themba Adaptive Intraday Engine — TASK-022 compile/logic test      |
//|                                                                    |
//| The trendline-pullback scenario is constructed so the middle anchor  |
//| lies EXACTLY on the line through the outer two (a perfect linear      |
//| fit, hand-computed via the same interpolation formula the code        |
//| uses), then a separate negative case moves that middle anchor far      |
//| off the line to prove the validation actually rejects an invalid       |
//| trendline — the specific defect this strategy exists to fix.           |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Strategies/TrendFollowingStrategy.mqh"

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

STFConfig MakeConfig()
  {
   STFConfig cfg;
   cfg.depth = 1;
   cfg.max_lookback = 8;
   cfg.middle_tolerance_atr = 0.5;
   cfg.touch_tolerance_atr = 0.3;
   cfg.stop_buffer_atr = 0.1;
   cfg.momentum_lookback_bars = 10;
   cfg.displacement_atr_multiple = 1.5;
   cfg.max_pullback_atr = 1.0;
   cfg.momentum_stop_atr = 1.5;
   cfg.candlestick_trend_lookback = 5;
   return cfg;
  }

void OnStart()
  {
   Print("=== TASK-022 TrendFollowingStrategy test start ===");
   STFConfig cfg = MakeConfig();

   //--- 1. Trendline pullback (TRENDING_UP, support trendline, perfect ---
   //---    linear fit: v3=100@idx11(oldest), v2=106@idx7(middle, exactly -
   //---    on the line), v1=112@idx3(newest)) -----------------------------
   double opens1[20], highs1[20], lows1[20], closes1[20], atr1[20];
   for(int i = 0; i < 20; i++)
     { opens1[i] = 200; highs1[i] = 200; lows1[i] = 200; closes1[i] = 200; atr1[i] = 2; }
   opens1[0] = 114.5; highs1[0] = 117.5; lows1[0] = 109.5; closes1[0] = 116.5;
   lows1[3] = 112; lows1[7] = 106; lows1[11] = 100;
   closes1[5] = 120;

   STFStrategySignal sig1;
   bool ok1 = TFS_EvaluateTrendlinePullbackArray(opens1, highs1, lows1, closes1, atr1,
                                                  REGIME_TRENDING_UP, cfg, sig1);
   Check("trendline pullback: signal found", ok1 && sig1.found);
   Check("trendline pullback: setup_type is TFS_TRENDLINE_PULLBACK",
         sig1.setup_type == TFS_TRENDLINE_PULLBACK);
   Check("trendline pullback: direction is TFSD_LONG", sig1.direction == TFSD_LONG);
   Check("trendline pullback: stop_price == 116.3 (116.5 - 2*0.1)",
         NearlyEqual(sig1.stop_price, 116.3));
   Check("trendline pullback: target_price == 116.9 (116.5 + 2*0.2)",
         NearlyEqual(sig1.target_price, 116.9));
   Check("trendline pullback: candlestick_pattern == bullish_pin_bar",
         sig1.candlestick_pattern == "bullish_pin_bar");

   // Negative: wrong regime
   STFStrategySignal sigNegRegime;
   bool okNegRegime = TFS_EvaluateTrendlinePullbackArray(opens1, highs1, lows1, closes1, atr1,
                                                          REGIME_RANGING, cfg, sigNegRegime);
   Check("trendline pullback: wrong regime (RANGING) produces no signal",
         okNegRegime == false && sigNegRegime.found == false);

   // Negative: invalid trendline — middle anchor moved far off the line
   double lows1Invalid[20];
   ArrayCopy(lows1Invalid, lows1);
   lows1Invalid[7] = 150.0; // far from the expected interpolated value of 106
   STFStrategySignal sigNegLine;
   bool okNegLine = TFS_EvaluateTrendlinePullbackArray(opens1, highs1, lows1Invalid, closes1, atr1,
                                                        REGIME_TRENDING_UP, cfg, sigNegLine);
   Check("trendline pullback: an invalid middle anchor (off the line) is correctly rejected",
         okNegLine == false && sigNegLine.found == false);

   //--- 2. Momentum continuation (VOLATILITY_EXPANSION_UP — testing the --
   //---    "also eligible under expansion" claim specifically, distinct  --
   //---    from the TRENDING-only trendline setup) -------------------------
   double opens2[20], highs2[20], lows2[20], closes2[20], atr2[20];
   for(int i = 0; i < 20; i++)
     { opens2[i] = 50; highs2[i] = 51; lows2[i] = 49; closes2[i] = 50; atr2[i] = 5; }
   opens2[0] = 107; highs2[0] = 110; lows2[0] = 102; closes2[0] = 109;
   opens2[5] = 100; highs2[5] = 110; lows2[5] = 100; closes2[5] = 110;

   STFStrategySignal sig2;
   bool ok2 = TFS_EvaluateMomentumContinuationArray(opens2, highs2, lows2, closes2, atr2,
                                                     REGIME_VOLATILITY_EXPANSION_UP, cfg, sig2);
   Check("momentum continuation: signal found under VOLATILITY_EXPANSION_UP", ok2 && sig2.found);
   Check("momentum continuation: setup_type is TFS_MOMENTUM_CONTINUATION",
         sig2.setup_type == TFS_MOMENTUM_CONTINUATION);
   Check("momentum continuation: direction is TFSD_LONG", sig2.direction == TFSD_LONG);
   Check("momentum continuation: stop_price == 101.5 (109 - 5*1.5)",
         NearlyEqual(sig2.stop_price, 101.5));
   Check("momentum continuation: target_price == 124 (109 + 2*7.5)",
         NearlyEqual(sig2.target_price, 124.0));
   Check("momentum continuation: candlestick_pattern == bullish_pin_bar",
         sig2.candlestick_pattern == "bullish_pin_bar");

   // Negative: wrong regime (RANGING is not eligible for momentum either)
   STFStrategySignal sigNegRegime2;
   bool okNegRegime2 = TFS_EvaluateMomentumContinuationArray(opens2, highs2, lows2, closes2, atr2,
                                                              REGIME_RANGING, cfg, sigNegRegime2);
   Check("momentum continuation: wrong regime (RANGING) produces no signal",
         okNegRegime2 == false && sigNegRegime2.found == false);

   // Negative: pullback too deep (closes[0] far from the displacement's
   // own extreme) — checked before candlestick confirmation, so this
   // must fail regardless of index-0 candle shape.
   double closes2Deep[20];
   ArrayCopy(closes2Deep, closes2);
   closes2Deep[0] = 90.0; // pullback = 110-90 = 20, far beyond 5*1.0=5
   STFStrategySignal sigDeep;
   bool okDeep = TFS_EvaluateMomentumContinuationArray(opens2, highs2, lows2, closes2Deep, atr2,
                                                        REGIME_VOLATILITY_EXPANSION_UP, cfg, sigDeep);
   Check("momentum continuation: a pullback deeper than the shallow threshold is rejected",
         okDeep == false && sigDeep.found == false);

   //--- 3. CMarketData-integrated wrapper against a real symbol -----------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok && md.HasBars(150))
     {
      STFStrategySignal live;
      bool live_ok = TFS_EvaluateLive(md, 100, 20, 21, 5, 14, 0.6, 0.75, 0.25, 0.3, 0.5, cfg, live);
      Check("real-symbol trend-following evaluation completes without crashing "
            "regardless of outcome", true);
      PrintFormat("INFO: real-symbol trend-following evaluation found=%s",
                  (live_ok && live.found) ? "true" : "false");
     }
   else
     {
      PrintFormat("NOTE: '%s' does not have enough history — real-symbol "
                  "smoke test skipped.", InpTestSymbol);
     }

   PrintFormat("=== TASK-022 TrendFollowingStrategy test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
