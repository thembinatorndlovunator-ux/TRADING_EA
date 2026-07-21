//+------------------------------------------------------------------+
//| Test_SRBounceStrategy.mq5                                         |
//| Themba Adaptive Intraday Engine — TASK-019 compile/logic test      |
//|                                                                    |
//| Hand-fabricated arrays with a directly-constructed                  |
//| SMarketStructureState (bypassing MarketStructure's own pivot-        |
//| finding, since its correctness was already verified in TASK-012 —    |
//| this test only needs a valid structure INPUT, not to re-derive it).  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Strategies/SRBounceStrategy.mqh"

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
   Print("=== TASK-019 SRBounceStrategy test start ===");

   const int    DEPTH = 1;
   const int    LOOKBACK = 8;
   const double SR_TOL = 0.3;
   const int    SR_MIN_TOUCHES = 2;
   const double STOP_BUF = 0.3;
   const int    TREND_LOOKBACK = 5;

   //--- 1. LONG signal: qualifying support zone + bullish pin bar --------
   double opens1[]  = {90,   95,95,95,95,95,95,95,95,95,95,95,95};
   double highs1[]  = {90.6, 95,95,95,95,95,95,95,95,95,95,95,95};
   double lows1[]   = {88,   95,95,90.2,95,95,95,89.8,95,95,95,95,95};
   double closes1[] = {90.5, 95,95,95,95,95,95,95,95,95,95,95,95};
   double atr1[]    = {2,2,2,2,2,2,2,2,2,2,2,2,2};
   SMarketStructureState struct1 = MakeValidStructure(90.0, 110.0);

   SSRBounceSignal sig1;
   bool ok1 = SRB_EvaluateArray(opens1, highs1, lows1, closes1, atr1, DEPTH, LOOKBACK,
                                 REGIME_RANGING, struct1, SR_TOL, SR_MIN_TOUCHES, STOP_BUF,
                                 TREND_LOOKBACK, sig1);
   Check("LONG scenario: signal found", ok1 && sig1.found);
   Check("LONG scenario: direction is SRB_LONG", sig1.direction == SRB_LONG);
   Check("LONG scenario: zone_price == 90 (range_low)", NearlyEqual(sig1.zone_price, 90.0));
   Check("LONG scenario: zone_touch_count == 2", sig1.zone_touch_count == 2);
   Check("LONG scenario: stop_price == 89.4 (90 - 2*0.3)", NearlyEqual(sig1.stop_price, 89.4));
   Check("LONG scenario: target_price == 110 (range_high)", NearlyEqual(sig1.target_price, 110.0));
   Check("LONG scenario: candlestick_pattern == bullish_pin_bar",
         sig1.candlestick_pattern == "bullish_pin_bar");

   //--- 2. Negative: wrong regime (TRENDING_UP instead of RANGING) --------
   SSRBounceSignal sig2;
   bool ok2 = SRB_EvaluateArray(opens1, highs1, lows1, closes1, atr1, DEPTH, LOOKBACK,
                                 REGIME_TRENDING_UP, struct1, SR_TOL, SR_MIN_TOUCHES, STOP_BUF,
                                 TREND_LOOKBACK, sig2);
   Check("wrong regime (TRENDING_UP) produces no signal", ok2 == false && sig2.found == false);

   //--- 3. Negative: invalid structure -------------------------------------
   SMarketStructureState invalidStruct = MakeValidStructure(90.0, 110.0);
   invalidStruct.valid = false;
   SSRBounceSignal sig3;
   bool ok3 = SRB_EvaluateArray(opens1, highs1, lows1, closes1, atr1, DEPTH, LOOKBACK,
                                 REGIME_RANGING, invalidStruct, SR_TOL, SR_MIN_TOUCHES, STOP_BUF,
                                 TREND_LOOKBACK, sig3);
   Check("invalid structure produces no signal", ok3 == false && sig3.found == false);

   //--- 4. Negative: no candlestick confirmation (plain small candle) -----
   double opens4[]  = {90,   95,95,95,95,95,95,95,95,95,95,95,95};
   double highs4[]  = {90.3, 95,95,95,95,95,95,95,95,95,95,95,95};
   double lows4[]   = {89.8, 95,95,90.2,95,95,95,89.8,95,95,95,95,95};
   double closes4[] = {90.1, 95,95,95,95,95,95,95,95,95,95,95,95};
   SSRBounceSignal sig4;
   bool ok4 = SRB_EvaluateArray(opens4, highs4, lows4, closes4, atr1, DEPTH, LOOKBACK,
                                 REGIME_RANGING, struct1, SR_TOL, SR_MIN_TOUCHES, STOP_BUF,
                                 TREND_LOOKBACK, sig4);
   Check("a plain non-reversal candle at a valid zone produces no signal",
         ok4 == false && sig4.found == false);

   //--- 5. Negative: zone with insufficient touches (min_touches not met) -
   SMarketStructureState struct5 = MakeValidStructure(70.0, 110.0); // no swing lows near 70
   double closes5[] = {70.1, 95,95,95,95,95,95,95,95,95,95,95,95};
   double opens5[]  = {70,   95,95,95,95,95,95,95,95,95,95,95,95};
   double highs5[]  = {70.6, 95,95,95,95,95,95,95,95,95,95,95,95};
   double lows5[]   = {68,   95,95,90.2,95,95,95,89.8,95,95,95,95,95};
   SSRBounceSignal sig5;
   bool ok5 = SRB_EvaluateArray(opens5, highs5, lows5, closes5, atr1, DEPTH, LOOKBACK,
                                 REGIME_RANGING, struct5, SR_TOL, SR_MIN_TOUCHES, STOP_BUF,
                                 TREND_LOOKBACK, sig5);
   Check("a zone with zero qualifying touches produces no signal",
         ok5 == false && sig5.found == false);

   //--- 6. SHORT signal (mirror): qualifying resistance zone + bearish ----
   //---    pin bar -----------------------------------------------------------
   double opens6[]  = {110,  95,95,95,95,95,95,95,95,95,95,95,95};
   double highs6[]  = {112,  95,95,109.8,95,95,95,110.2,95,95,95,95,95};
   double lows6[]   = {109.4,95,95,95,95,95,95,95,95,95,95,95,95};
   double closes6[] = {109.5,95,95,95,95,95,95,95,95,95,95,95,95};
   SMarketStructureState struct6 = MakeValidStructure(90.0, 110.0);

   SSRBounceSignal sig6;
   bool ok6 = SRB_EvaluateArray(opens6, highs6, lows6, closes6, atr1, DEPTH, LOOKBACK,
                                 REGIME_RANGING, struct6, SR_TOL, SR_MIN_TOUCHES, STOP_BUF,
                                 TREND_LOOKBACK, sig6);
   Check("SHORT scenario: signal found", ok6 && sig6.found);
   Check("SHORT scenario: direction is SRB_SHORT", sig6.direction == SRB_SHORT);
   Check("SHORT scenario: zone_price == 110 (range_high)", NearlyEqual(sig6.zone_price, 110.0));
   Check("SHORT scenario: stop_price == 110.6 (110 + 2*0.3)", NearlyEqual(sig6.stop_price, 110.6));
   Check("SHORT scenario: target_price == 90 (range_low)", NearlyEqual(sig6.target_price, 90.0));
   Check("SHORT scenario: candlestick_pattern == bearish_pin_bar",
         sig6.candlestick_pattern == "bearish_pin_bar");

   //--- 7. CMarketData-integrated wrapper against a real symbol -----------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok && md.HasBars(150))
     {
      SSRBounceSignal live;
      bool live_ok = SRB_EvaluateLive(md, 3, 50, 100, 20, 21, 5, 14, 0.6, 0.75, 0.25, 0.3, 0.5,
                                       0.3, 2, 0.3, 5, live);
      Check("real-symbol SR-bounce evaluation completes without crashing regardless of outcome",
            true);
      PrintFormat("INFO: real-symbol SR-bounce evaluation found=%s",
                  (live_ok && live.found) ? "true" : "false");
     }
   else
     {
      PrintFormat("NOTE: '%s' does not have enough history — real-symbol "
                  "smoke test skipped.", InpTestSymbol);
     }

   PrintFormat("=== TASK-019 SRBounceStrategy test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
