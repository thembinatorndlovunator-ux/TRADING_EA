//+------------------------------------------------------------------+
//| Test_SMCStrategy.mq5                                              |
//| Themba Adaptive Intraday Engine — TASK-020 compile/logic test      |
//|                                                                    |
//| One hand-fabricated scenario per setup (order-block retest, sweep    |
//| reversal, FVG return), each hand-traced against the underlying        |
//| ICTSMCGeometry/CandlestickPatternEngine predicates, plus wrong-        |
//| regime negative cases proving each setup is regime-exclusive.          |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Strategies/SMCStrategy.mqh"

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

SSMCConfig MakeConfig()
  {
   SSMCConfig cfg;
   cfg.depth = 1;
   cfg.max_lookback = 8;
   cfg.displacement_atr_multiple = 1.5;
   cfg.retest_tolerance_atr = 0.3;
   cfg.max_retest_bars = 6;
   cfg.sweep_lookback = 3;
   cfg.shift_lookback = 3;
   cfg.fvg_scan_bars = 6;
   cfg.trend_lookback = 5;
   return cfg;
  }

void OnStart()
  {
   Print("=== TASK-020 SMCStrategy test start ===");
   SSMCConfig cfg = MakeConfig();

   //--- 1. Order-block retest (TRENDING_UP) --------------------------------
   {
      double opens[]  = {101.5,95,95,100,105,95,95,95,95,95,95,95,95,95,95};
      double highs[]  = {102.1,95,95,110,106,95,95,95,95,95,95,95,95,95,95};
      double lows[]   = {99.5, 95,95,100,99, 95,95,95,95,95,95,95,95,95,95};
      double closes[] = {102.0,95,95,110,100,105,95,95,95,95,95,95,95,95,95};
      double atr[]    = {5,5,5,5,5,5,5,5,5,5,5,5,5,5,5};

      SSMCSignal sig;
      bool ok = SMC_EvaluateOrderBlockRetestArray(opens, highs, lows, closes, atr,
                                                    REGIME_TRENDING_UP, cfg, sig);
      Check("OB retest: signal found", ok && sig.found);
      Check("OB retest: setup_type is SMC_SETUP_OB_RETEST", sig.setup_type == SMC_SETUP_OB_RETEST);
      Check("OB retest: direction is SMCD_LONG", sig.direction == SMCD_LONG);
      Check("OB retest: zone_high == 106", NearlyEqual(sig.zone_high, 106.0));
      Check("OB retest: zone_low == 99", NearlyEqual(sig.zone_low, 99.0));
      Check("OB retest: stop_price == 98.5 (99 - 5*0.1)", NearlyEqual(sig.stop_price, 98.5));
      Check("OB retest: target_price == 116 (102 + 2*7)", NearlyEqual(sig.target_price, 116.0));
      Check("OB retest: candlestick_pattern == bullish_pin_bar",
            sig.candlestick_pattern == "bullish_pin_bar");

      // Negative: wrong regime
      SSMCSignal sigNeg;
      bool okNeg = SMC_EvaluateOrderBlockRetestArray(opens, highs, lows, closes, atr,
                                                       REGIME_RANGING, cfg, sigNeg);
      Check("OB retest: wrong regime (RANGING) produces no signal",
            okNeg == false && sigNeg.found == false);
   }

   //--- 2. Sweep reversal (RANGING) ------------------------------------------
   {
      double opens[]  = {60,  50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50};
      double highs[]  = {63,  50,65,50,50,50,60,50,50,50,50,50,50,50,50,50,50,50,50,50};
      double lows[]   = {59,  50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50};
      double closes[] = {59.5,55,62,50,50,55,50,50,50,50,50,50,50,50,50,50,50,50,50,50};
      double atr[]    = {2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2};

      SSMCSignal sig;
      bool ok = SMC_EvaluateSweepReversalArray(opens, highs, lows, closes, atr, REGIME_RANGING,
                                                 cfg, sig);
      Check("sweep reversal: signal found", ok && sig.found);
      Check("sweep reversal: setup_type is SMC_SETUP_SWEEP_REVERSAL",
            sig.setup_type == SMC_SETUP_SWEEP_REVERSAL);
      Check("sweep reversal: direction is SMCD_SHORT (buy-side liquidity was swept)",
            sig.direction == SMCD_SHORT);
      Check("sweep reversal: zone_high == 65 (the sweep bar's own high)",
            NearlyEqual(sig.zone_high, 65.0));
      Check("sweep reversal: stop_price == 65.2 (65 + 2*0.1)", NearlyEqual(sig.stop_price, 65.2));
      Check("sweep reversal: target_price == 29.5 (59.5 - 2*15)",
            NearlyEqual(sig.target_price, 29.5));
      Check("sweep reversal: candlestick_pattern == bearish_pin_bar",
            sig.candlestick_pattern == "bearish_pin_bar");

      SSMCSignal sigNeg;
      bool okNeg = SMC_EvaluateSweepReversalArray(opens, highs, lows, closes, atr,
                                                    REGIME_TRENDING_UP, cfg, sigNeg);
      Check("sweep reversal: wrong regime (TRENDING_UP) produces no signal",
            okNeg == false && sigNeg.found == false);
   }

   //--- 3. FVG return (VOLATILITY_EXPANSION_UP) ------------------------------
   {
      double opens[]  = {101.5,95,95, 95,95, 95,95,95,95,95,95,95,95,95,95};
      double highs[]  = {102.1,95,100,95,95, 100,95,95,95,95,95,95,95,95,95};
      double lows[]   = {99.5, 95,95, 95,105,95, 95,95,95,95,95,95,95,95,95};
      double closes[] = {102.0,95,95, 95,95, 105,95,95,95,95,95,95,95,95,95};
      double atr[]    = {5,5,5,5,5,5,5,5,5,5,5,5,5,5,5};

      SSMCSignal sig;
      bool ok = SMC_EvaluateFVGReturnArray(opens, highs, lows, closes, atr,
                                            REGIME_VOLATILITY_EXPANSION_UP, cfg, sig);
      Check("FVG return: signal found", ok && sig.found);
      Check("FVG return: setup_type is SMC_SETUP_FVG_RETURN",
            sig.setup_type == SMC_SETUP_FVG_RETURN);
      Check("FVG return: direction is SMCD_LONG", sig.direction == SMCD_LONG);
      Check("FVG return: zone_high == 105", NearlyEqual(sig.zone_high, 105.0));
      Check("FVG return: zone_low == 95", NearlyEqual(sig.zone_low, 95.0));
      Check("FVG return: stop_price == 94.5 (95 - 5*0.1)", NearlyEqual(sig.stop_price, 94.5));
      Check("FVG return: target_price == 122 (102 + 2*10)", NearlyEqual(sig.target_price, 122.0));
      Check("FVG return: candlestick_pattern == bullish_pin_bar",
            sig.candlestick_pattern == "bullish_pin_bar");

      SSMCSignal sigNeg;
      bool okNeg = SMC_EvaluateFVGReturnArray(opens, highs, lows, closes, atr, REGIME_RANGING,
                                               cfg, sigNeg);
      Check("FVG return: wrong regime (RANGING) produces no signal",
            okNeg == false && sigNeg.found == false);
   }

   //--- 4. CMarketData-integrated wrapper against a real symbol -------------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok && md.HasBars(150))
     {
      SSMCSignal live;
      bool live_ok = SMC_EvaluateLive(md, 100, 20, 21, 5, 14, 0.6, 0.75, 0.25, 0.3, 0.5, cfg, live);
      Check("real-symbol SMC evaluation completes without crashing regardless of outcome", true);
      PrintFormat("INFO: real-symbol SMC evaluation found=%s",
                  (live_ok && live.found) ? "true" : "false");
     }
   else
     {
      PrintFormat("NOTE: '%s' does not have enough history — real-symbol "
                  "smoke test skipped.", InpTestSymbol);
     }

   PrintFormat("=== TASK-020 SMCStrategy test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
