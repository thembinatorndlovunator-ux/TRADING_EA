//+------------------------------------------------------------------+
//| Test_ChartPatternStrategy.mq5                                     |
//| Themba Adaptive Intraday Engine — TASK-021 compile/logic test      |
//|                                                                    |
//| Reuses TASK-018's hand-verified double-top/double-bottom arrays      |
//| (boundary_price/extreme_price/target/stop already proven correct),   |
//| extended with a retest/confirmation candle at index 0 and re-traced   |
//| by hand to confirm the extension doesn't disturb the original          |
//| breakout_index (the scan loop's short-circuit behavior was verified    |
//| explicitly for each case before finalizing).                            |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Strategies/ChartPatternStrategy.mqh"

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

SCPStrategyConfig MakeConfig()
  {
   SCPStrategyConfig cfg;
   cfg.depth = 1;
   cfg.max_lookback = 8;
   cfg.price_tolerance_atr = 1.0;
   cfg.min_pullback_atr = 1.0;
   cfg.min_head_prominence_atr = 1.0;
   cfg.time_tolerance = 0.5;
   cfg.trend_bars = 3;
   cfg.breakout_buffer_atr = 0.1;
   cfg.max_breakout_age_bars = 10;
   cfg.retest_tolerance_atr = 0.3;
   cfg.candlestick_trend_lookback = 5;
   return cfg;
  }

SMarketStructureState MakeValidStructure(const double range_low, const double range_high)
  {
   SMarketStructureState s;
   s.valid = true;
   s.bias = STRUCTURE_BIAS_NEUTRAL;
   s.last_event = STRUCTURE_EVENT_NONE;
   s.last_event_index = -1;
   s.has_swing_high_2 = false;
   s.has_swing_low_2 = false;
   s.swing_high_1_index = 0;
   s.swing_high_1_price = range_high;
   s.swing_low_1_index = 0;
   s.swing_low_1_price = range_low;
   s.range_high = range_high;
   s.range_low = range_low;
   s.equilibrium = (range_high + range_low) / 2.0;
   return s;
  }

void OnStart()
  {
   Print("=== TASK-021 ChartPatternStrategy test start ===");
   SCPStrategyConfig cfg = MakeConfig();

   //--- 1. Trend-breakout-retest (TRENDING_DOWN, double top, bearish -----
   //---    breakout confirms the downtrend) --------------------------------
   {
      double opens[]  = {90.0, 60,60,60,60,60,60,60,60,60,60,60,60};
      double highs[]  = {92.0, 95,95,100,95,95,95,101,95,95,95,95,95};
      double lows[]   = {89.4, 95,95,95, 95,90,95,95, 95,95,95,95,95};
      double closes[] = {89.5, 88,92,95, 95,85,95,100,95,95,93,95,95};
      double atr[]    = {2,2,2,2,2,2,2,2,2,2,2,2,2};

      SChartPatternStrategySignal sig;
      bool ok = CPS_EvaluateTrendBreakoutRetestArray(opens, highs, lows, closes, atr,
                                                       REGIME_TRENDING_DOWN, cfg, sig);
      Check("trend-breakout-retest: signal found", ok && sig.found);
      Check("trend-breakout-retest: setup_type is CPS_TREND_BREAKOUT_RETEST",
            sig.setup_type == CPS_TREND_BREAKOUT_RETEST);
      Check("trend-breakout-retest: direction is CPSD_SHORT", sig.direction == CPSD_SHORT);
      Check("trend-breakout-retest: pattern_type is CPT_DOUBLE_TOP",
            sig.pattern_type == CPT_DOUBLE_TOP);
      Check("trend-breakout-retest: stop_price == 100.2 (from ChartPatternEngine, unchanged "
            "from TASK-018's hand-verified value)", NearlyEqual(sig.stop_price, 100.2));
      Check("trend-breakout-retest: target_price == 79 (from ChartPatternEngine, unchanged)",
            NearlyEqual(sig.target_price, 79.0));
      Check("trend-breakout-retest: candlestick_pattern == bearish_pin_bar",
            sig.candlestick_pattern == "bearish_pin_bar");

      // Negative: wrong regime (TRENDING_UP instead of TRENDING_DOWN — the
      // pattern's bearish breakout does NOT confirm an uptrend)
      SChartPatternStrategySignal sigNeg;
      bool okNeg = CPS_EvaluateTrendBreakoutRetestArray(opens, highs, lows, closes, atr,
                                                          REGIME_TRENDING_UP, cfg, sigNeg);
      Check("trend-breakout-retest: mismatched trend direction produces no signal",
            okNeg == false && sigNeg.found == false);
   }

   //--- 2. Range-boundary (RANGING, double bottom at range_low) -----------
   {
      double opens[]  = {95, 60,60,60,60,60,60,60,60,60,60,60,60};
      double highs[]  = {98, 70,70,55,55,60,55,55,55,55,55,55,55};
      double lows[]   = {90, 65,65,50,65,65,65,49,65,65,65,65,65};
      double closes[] = {97, 62,58,55,55,105,55,50,55,55,55,55,55};
      double atr[]    = {2,2,2,2,2,2,2,2,2,2,2,2,2};
      SMarketStructureState structure = MakeValidStructure(49.0, 200.0);

      SChartPatternStrategySignal sig;
      bool ok = CPS_EvaluateRangeBoundaryArray(opens, highs, lows, closes, atr, REGIME_RANGING,
                                                structure, cfg, sig);
      Check("range-boundary: signal found", ok && sig.found);
      Check("range-boundary: setup_type is CPS_RANGE_BOUNDARY",
            sig.setup_type == CPS_RANGE_BOUNDARY);
      Check("range-boundary: direction is CPSD_LONG", sig.direction == CPSD_LONG);
      Check("range-boundary: pattern_type is CPT_DOUBLE_BOTTOM",
            sig.pattern_type == CPT_DOUBLE_BOTTOM);
      Check("range-boundary: stop_price == 49.8 (unchanged from TASK-018)",
            NearlyEqual(sig.stop_price, 49.8));
      Check("range-boundary: target_price == 71 (unchanged from TASK-018)",
            NearlyEqual(sig.target_price, 71.0));
      Check("range-boundary: candlestick_pattern == bullish_pin_bar",
            sig.candlestick_pattern == "bullish_pin_bar");

      // Negative: wrong regime
      SChartPatternStrategySignal sigNeg;
      bool okNeg = CPS_EvaluateRangeBoundaryArray(opens, highs, lows, closes, atr,
                                                    REGIME_TRENDING_UP, structure, cfg, sigNeg);
      Check("range-boundary: wrong regime (TRENDING_UP) produces no signal",
            okNeg == false && sigNeg.found == false);

      // Negative: extreme not near the range boundary
      SMarketStructureState farStructure = MakeValidStructure(10.0, 200.0);
      SChartPatternStrategySignal sigFar;
      bool okFar = CPS_EvaluateRangeBoundaryArray(opens, highs, lows, closes, atr, REGIME_RANGING,
                                                   farStructure, cfg, sigFar);
      Check("range-boundary: extreme far from the range boundary produces no signal",
            okFar == false && sigFar.found == false);
   }

   //--- 3. CMarketData-integrated wrapper against a real symbol -----------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok && md.HasBars(150))
     {
      SChartPatternStrategySignal live;
      bool live_ok = CPS_EvaluateLive(md, 100, 20, 21, 5, 14, 0.6, 0.75, 0.25, 0.3, 0.5, cfg, live);
      Check("real-symbol chart-pattern strategy evaluation completes without crashing "
            "regardless of outcome", true);
      PrintFormat("INFO: real-symbol chart-pattern strategy evaluation found=%s",
                  (live_ok && live.found) ? "true" : "false");
     }
   else
     {
      PrintFormat("NOTE: '%s' does not have enough history — real-symbol "
                  "smoke test skipped.", InpTestSymbol);
     }

   PrintFormat("=== TASK-021 ChartPatternStrategy test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
