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
//|                                                                    |
//| **Extended, 2026-07-27 (Codex review finding, ninth round, P1 finding   |
//| 11):** every call site now threads a parallel bar-times[] array plus       |
//| a test-scoped symbol/magic (ChartPatternLifecycle.mqh's own persisted        |
//| registry needs both). Section 6's own hold/fail retest transition now         |
//| requires TWO calls against the same fixture -- the first call enters           |
//| RETESTING (returns false, no signal yet), the second resolves hold/fail          |
//| (returns true once, with the signal) -- documented explicitly at each             |
//| call site below, not silently assumed. New cases 4/5 exercise consumed-               |
//| suppression (a third call on an already-TRADED instance must never re-                  |
//| fire) and instance-identity independence (a genuinely different pattern                     |
//| instance is unaffected by another instance's own consumed state). A                            |
//| cleanup pass at both start and end removes this test's own lifecycle                              |
//| GlobalVariable records so repeated runs never see stale state from a                                 |
//| previous run.                                                                                            |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Strategies/ChartPatternStrategy.mqh"

input string          InpTestSymbol    = "EURUSD";
input ENUM_TIMEFRAMES InpTestTimeframe = PERIOD_M15;

const string TEST_LIFECYCLE_SYMBOL = "TASK021_TEST_SYMBOL";
const long   TEST_LIFECYCLE_MAGIC  = 990021;

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

//+------------------------------------------------------------------+
//| Test-only cleanup: deletes every lifecycle GlobalVariable this test  |
//| may have written, under its own dedicated test symbol+magic, so        |
//| repeated runs never see stale state from a previous run (and this       |
//| run never leaves residue behind either).                                 |
//+------------------------------------------------------------------+
void CleanupLifecycleTestState()
  {
   string prefix = CPL_InstancePrefix(TEST_LIFECYCLE_SYMBOL, TEST_LIFECYCLE_MAGIC) + "__";
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) == 0)
         GlobalVariableDel(name);
     }
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
   // TASK-002_PHASE2_SPECIFICATION.md section 6 defaults (Codex round-9 P1
   // finding 11 -- previously never wired to any live caller at all).
   cfg.retest_failure_atr = 0.2;
   cfg.retest_max_bars = 10;
   // Codex round-10 P1 finding 9: TASK-002_PHASE2_SPECIFICATION.md section
   // 6's own default (50) -- previously not a real operator input, now
   // wired and required by CPS_ApplyLifecycle's own signature.
   cfg.max_age_bars = 50;
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

//+------------------------------------------------------------------+
//| Builds a 13-element parallel bar-times[] array (index 0 = newest,     |
//| index 12 = oldest), starting from 'base', 15 minutes apart -- matches    |
//| every fixture's own 13-element opens/highs/lows/closes/atr arrays.          |
//+------------------------------------------------------------------+
void BuildTimes(const datetime base, datetime &times[])
  {
   ArrayResize(times, 13);
   for(int i = 0; i < 13; i++)
      times[i] = base + (12 - i) * 900;
  }

void OnStart()
  {
   Print("=== TASK-021 ChartPatternStrategy test start ===");
   CleanupLifecycleTestState();
   SCPStrategyConfig cfg = MakeConfig();

   //--- 1. Trend-breakout-retest (TRENDING_DOWN, double top, bearish -----
   //---    breakout confirms the downtrend). Two calls against the SAME ----
   //---    fixture: the first enters RETESTING (no signal yet, per section ---
   //---    6's own CONFIRMED -> RETESTING -> TRADED graph), the second --------
   //---    resolves hold/fail and fires the signal exactly once. -------------
   {
      double opens[]  = {90.0, 60,60,60,60,60,60,60,60,60,60,60,60};
      double highs[]  = {92.0, 95,95,100,95,95,95,101,95,95,95,95,95};
      double lows[]   = {89.4, 95,95,95, 95,90,95,95, 95,95,95,95,95};
      double closes[] = {89.5, 88,92,95, 95,85,95,100,95,95,93,95,95};
      double atr[]    = {2,2,2,2,2,2,2,2,2,2,2,2,2};
      datetime times[];
      BuildTimes(D'2026.01.01 00:00', times);

      SChartPatternStrategySignal sig1;
      bool ok1 = CPS_EvaluateTrendBreakoutRetestArray(opens, highs, lows, closes, atr, times,
                                                        TEST_LIFECYCLE_SYMBOL, TEST_LIFECYCLE_MAGIC,
                                                        REGIME_TRENDING_DOWN, cfg, sig1);
      Check("trend-breakout-retest: first call enters RETESTING, no signal yet",
            ok1 == false && sig1.found == false);

      SChartPatternStrategySignal sig;
      bool ok = CPS_EvaluateTrendBreakoutRetestArray(opens, highs, lows, closes, atr, times,
                                                       TEST_LIFECYCLE_SYMBOL, TEST_LIFECYCLE_MAGIC,
                                                       REGIME_TRENDING_DOWN, cfg, sig);
      Check("trend-breakout-retest: second call resolves hold -- signal found", ok && sig.found);
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

      // **Codex round-9 P1 finding 11:** a THIRD call against the identical
      // fixture must be suppressed -- this exact instance is now TRADED
      // (consumed) and must never re-enter eligibility, closing "rediscovered
      // geometry can trade repeatedly."
      SChartPatternStrategySignal sig3;
      bool ok3 = CPS_EvaluateTrendBreakoutRetestArray(opens, highs, lows, closes, atr, times,
                                                        TEST_LIFECYCLE_SYMBOL, TEST_LIFECYCLE_MAGIC,
                                                        REGIME_TRENDING_DOWN, cfg, sig3);
      Check("trend-breakout-retest: a TRADED instance is suppressed on a later call "
            "(consumed-pattern suppression)", ok3 == false && sig3.found == false);

      // Negative: wrong regime (TRENDING_UP instead of TRENDING_DOWN — the
      // pattern's bearish breakout does NOT confirm an uptrend). Uses a
      // DIFFERENT bar-times base so this negative case's own (never-reached)
      // lifecycle identity cannot collide with the positive case above.
      datetime timesNeg[];
      BuildTimes(D'2026.02.01 00:00', timesNeg);
      SChartPatternStrategySignal sigNeg;
      bool okNeg = CPS_EvaluateTrendBreakoutRetestArray(opens, highs, lows, closes, atr, timesNeg,
                                                          TEST_LIFECYCLE_SYMBOL, TEST_LIFECYCLE_MAGIC,
                                                          REGIME_TRENDING_UP, cfg, sigNeg);
      Check("trend-breakout-retest: mismatched trend direction produces no signal",
            okNeg == false && sigNeg.found == false);
   }

   //--- 2. Range-boundary (RANGING, double bottom at range_low). No -------
   //---    retest cycle of its own -- consumed-suppression fires as soon as ---
   //---    the first candlestick-confirmed emission happens. -------------------
   {
      double opens[]  = {95, 60,60,60,60,60,60,60,60,60,60,60,60};
      double highs[]  = {98, 70,70,55,55,60,55,55,55,55,55,55,55};
      double lows[]   = {90, 65,65,50,65,65,65,49,65,65,65,65,65};
      double closes[] = {97, 62,58,55,55,105,55,50,55,55,55,55,55};
      double atr[]    = {2,2,2,2,2,2,2,2,2,2,2,2,2};
      datetime times[];
      BuildTimes(D'2026.03.01 00:00', times);
      SMarketStructureState structure = MakeValidStructure(49.0, 200.0);

      SChartPatternStrategySignal sig;
      bool ok = CPS_EvaluateRangeBoundaryArray(opens, highs, lows, closes, atr, times,
                                                TEST_LIFECYCLE_SYMBOL, TEST_LIFECYCLE_MAGIC,
                                                REGIME_RANGING, structure, cfg, sig);
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

      // **Codex round-9 P1 finding 11:** a second call against the identical
      // fixture must be suppressed -- this exact instance is now TRADED.
      SChartPatternStrategySignal sig2;
      bool ok2 = CPS_EvaluateRangeBoundaryArray(opens, highs, lows, closes, atr, times,
                                                 TEST_LIFECYCLE_SYMBOL, TEST_LIFECYCLE_MAGIC,
                                                 REGIME_RANGING, structure, cfg, sig2);
      Check("range-boundary: a TRADED instance is suppressed on a later call "
            "(consumed-pattern suppression)", ok2 == false && sig2.found == false);

      // Negative: wrong regime
      datetime timesNegRegime[];
      BuildTimes(D'2026.04.01 00:00', timesNegRegime);
      SChartPatternStrategySignal sigNeg;
      bool okNeg = CPS_EvaluateRangeBoundaryArray(opens, highs, lows, closes, atr, timesNegRegime,
                                                    TEST_LIFECYCLE_SYMBOL, TEST_LIFECYCLE_MAGIC,
                                                    REGIME_TRENDING_UP, structure, cfg, sigNeg);
      Check("range-boundary: wrong regime (TRENDING_UP) produces no signal",
            okNeg == false && sigNeg.found == false);

      // Negative: extreme not near the range boundary
      datetime timesNegFar[];
      BuildTimes(D'2026.05.01 00:00', timesNegFar);
      SMarketStructureState farStructure = MakeValidStructure(10.0, 200.0);
      SChartPatternStrategySignal sigFar;
      bool okFar = CPS_EvaluateRangeBoundaryArray(opens, highs, lows, closes, atr, timesNegFar,
                                                    TEST_LIFECYCLE_SYMBOL, TEST_LIFECYCLE_MAGIC,
                                                    REGIME_RANGING, farStructure, cfg, sigFar);
      Check("range-boundary: extreme far from the range boundary produces no signal",
            okFar == false && sigFar.found == false);
   }

   //--- 3. Instance-identity independence: a DIFFERENT pattern instance ---
   //---    (different pivot bar times -- a shifted copy of case 1's own -----
   //---    fixture) is NOT affected by case 1's own already-TRADED state,  ---
   //---    per Codex round-9 P1 finding 11's own durable-identity ------------
   //---    requirement (keyed by pivots, not by pattern TYPE alone). ----------
   {
      double opens[]  = {90.0, 60,60,60,60,60,60,60,60,60,60,60,60};
      double highs[]  = {92.0, 95,95,100,95,95,95,101,95,95,95,95,95};
      double lows[]   = {89.4, 95,95,95, 95,90,95,95, 95,95,95,95,95};
      double closes[] = {89.5, 88,92,95, 95,85,95,100,95,95,93,95,95};
      double atr[]    = {2,2,2,2,2,2,2,2,2,2,2,2,2};
      datetime times[];
      BuildTimes(D'2026.06.01 00:00', times); // a distinct base -- distinct pivot times,
                                                // therefore a genuinely distinct identity
                                                // from case 1's own instance despite
                                                // identical prices/geometry.

      SChartPatternStrategySignal sig1;
      bool ok1 = CPS_EvaluateTrendBreakoutRetestArray(opens, highs, lows, closes, atr, times,
                                                        TEST_LIFECYCLE_SYMBOL, TEST_LIFECYCLE_MAGIC,
                                                        REGIME_TRENDING_DOWN, cfg, sig1);
      Check("instance independence: a genuinely different instance's own first call also "
            "enters RETESTING (unaffected by case 1's own already-TRADED state)",
            ok1 == false && sig1.found == false);

      SChartPatternStrategySignal sig2;
      bool ok2 = CPS_EvaluateTrendBreakoutRetestArray(opens, highs, lows, closes, atr, times,
                                                        TEST_LIFECYCLE_SYMBOL, TEST_LIFECYCLE_MAGIC,
                                                        REGIME_TRENDING_DOWN, cfg, sig2);
      Check("instance independence: this genuinely different instance still fires its own "
            "signal on its second call", ok2 && sig2.found);
   }

   //--- 4. CMarketData-integrated wrapper against a real symbol -----------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok && md.HasBars(150))
     {
      SChartPatternStrategySignal live;
      bool live_ok = CPS_EvaluateLive(md, InpTestSymbol, 990022, 100, 20, 21, 5, 14, 0.6, 0.75, 0.25,
                                       0.3, 0.5, cfg, live);
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

   //--- Cleanup: leave no residue --------------------------------------------
   CleanupLifecycleTestState();

   PrintFormat("=== TASK-021 ChartPatternStrategy test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
