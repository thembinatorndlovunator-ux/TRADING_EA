//+------------------------------------------------------------------+
//| Test_MarketData.mq5                                               |
//| Themba Adaptive Intraday Engine — TASK-005 compile/logic test      |
//|                                                                    |
//| Exercises CMarketData against a real symbol/timeframe. The most    |
//| important assertion here is the completed-candle one: logical      |
//| index 0's bar must have actually closed relative to the current    |
//| server time — proving the +1 translation to MQL series index       |
//| really does skip the forming bar, not just that it compiles.       |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Market/MarketData.mqh"

input string          InpTestSymbol    = "EURUSD";
input ENUM_TIMEFRAMES InpTestTimeframe = PERIOD_M15;

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
   Print("=== TASK-005 MarketData test start ===");

   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("Init succeeds for '%s' %s", InpTestSymbol,
                       EnumToString(InpTestTimeframe)), init_ok);

   if(!init_ok)
     {
      PrintFormat("=== TASK-005 MarketData test complete: %d passed, %d failed "
                  "(remaining checks skipped — Init failed) ===", g_pass, g_fail);
      return;
     }

   //--- 1. Bar-availability checks -------------------------------------
   Check("HasBars(0) is trivially true", md.HasBars(0));
   Check("HasBars(5) is true (assuming any real history exists)",
         md.HasBars(5));
   Check("HasBars(100000000) is false (no symbol has that much history)",
         md.HasBars(100000000) == false);

   //--- 2. Negative logical index is rejected for every accessor ------
   double d;
   datetime t;
   long v;
   Check("GetOpen(-1) fails", md.GetOpen(-1, d) == false);
   Check("GetHigh(-1) fails", md.GetHigh(-1, d) == false);
   Check("GetLow(-1) fails", md.GetLow(-1, d) == false);
   Check("GetClose(-1) fails", md.GetClose(-1, d) == false);
   Check("GetTime(-1) fails", md.GetTime(-1, t) == false);
   Check("GetTickVolume(-1) fails", md.GetTickVolume(-1, v) == false);
   Check("GetATR(-1) fails", md.GetATR(-1, d) == false);

   //--- 3. Logical index 0 reads succeed and are internally consistent -
   double o0, h0, l0, c0;
   datetime time0;
   bool ohlc_ok = md.GetOpen(0, o0) && md.GetHigh(0, h0) &&
                  md.GetLow(0, l0) && md.GetClose(0, c0) &&
                  md.GetTime(0, time0);
   Check("logical index 0 OHLC+time all read successfully", ohlc_ok);

   if(ohlc_ok)
     {
      Check("high[0] >= low[0]", h0 >= l0);
      Check("open[0] is within [low[0], high[0]]", o0 >= l0 && o0 <= h0);
      Check("close[0] is within [low[0], high[0]]", c0 >= l0 && c0 <= h0);

      //--- The core completed-candle guarantee: index 0's bar must have
      //--- already closed relative to the current server time. If this
      //--- ever fails, the +1 translation is broken and the forming bar
      //--- is leaking through as logical index 0.
      int period_seconds = PeriodSeconds(InpTestTimeframe);
      datetime now = TimeCurrent();
      Check("logical index 0's bar has actually closed (time[0] + period <= now)",
            (time0 + period_seconds) <= now);
     }

   //--- 4. Logical index 1 is strictly older than logical index 0 -----
   datetime time1;
   bool time1_ok = md.GetTime(1, time1);
   Check("logical index 1 time read succeeds", time1_ok);
   if(ohlc_ok && time1_ok)
      Check("time[1] is strictly before time[0]", time1 < time0);

   //--- 5. ATR: sane positive value, consistent across repeated calls,  -
   //---    and handle caching does not corrupt a second distinct period -
   double atr14_a, atr14_b, atr20;
   bool atr_ok = md.GetATR(0, atr14_a, 14) && md.GetATR(0, atr14_b, 14) &&
                 md.GetATR(0, atr20, 20);
   Check("ATR(14) and ATR(20) both read successfully at logical index 0",
         atr_ok);
   if(atr_ok)
     {
      Check("ATR(14) is positive", atr14_a > 0.0);
      Check("ATR(14) is consistent across repeated calls (handle cache "
            "does not drift)", atr14_a == atr14_b);
      Check("ATR(20) is positive", atr20 > 0.0);
     }

   PrintFormat("=== TASK-005 MarketData test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
