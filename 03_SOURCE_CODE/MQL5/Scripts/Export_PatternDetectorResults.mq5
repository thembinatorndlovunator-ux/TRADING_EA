//+------------------------------------------------------------------+
//| Export_PatternDetectorResults.mq5                                 |
//| Themba Adaptive Intraday Engine — TASK-037 real-data export tool   |
//|                                                                    |
//| Runs the EXACT live MQL5 pattern predicates                          |
//| (CandlestickPatternEngine.mqh) against a real OHLC history segment      |
//| and writes one CSV row per bar (k, <pattern booleans>, plus                |
//| provenance columns -- see below), in the schema                             |
//| analysis/pattern_validation.py's compare_to_mql5_export already                |
//| expects.                                                                       |
//|                                                                    |
//| **Rewritten, 2026-07-22 (Codex review finding, seventh round, P1 finding |
//| 11): the previous version scoped this export to exactly the ORIGINAL         |
//| 4 patterns (bullish/bearish pin bar, bullish/bearish engulfing) --              |
//| detect_all_patterns() has since grown to SIXTEEN always-included                  |
//| pattern columns (TASK-033), plus three more opt-in ones (marubozu,                  |
//| tweezer top/bottom, three_bar_reversal) that run()'s own CLI path now                 |
//| forwards (this same review round's own Python-side fix). Exporting                      |
//| only 4 columns made compare_to_mql5_export's own schema check (which                       |
//| derives its required MQL columns from ALL of python_results' own                             |
//| columns) fail outright for the other 16+ columns on any real                                    |
//| comparison run. This export now emits the FULL matching column set:                               |
//| every always-included pattern, plus the three ATR/swing-dependent      |
//| ones (this script always supplies both an ATR handle and                  |
//| InpSwingDepth, so all three are always included, matching a run() call        |
//| that also supplies an 'atr' column).**                                          |
//|                                                                    |
//| **Also added, this round: symbol/timestamp/OHLC provenance columns --   |
//| the previous export contained only the row index 'k', with nothing            |
//| proving an MQL export and a Python run() call actually analyzed the              |
//| SAME underlying chart segment. 'timestamp' is this bar's own UTC time,              |
//| and open/high/low/close/atr are the exact values this script itself                    |
//| fed into every predicate below -- a caller can independently verify a                    |
//| Python-side OHLC export lines up bar-for-bar before ever trusting a                         |
//| pattern-column comparison.**                                                                   |
//|                                                                    |
//| Uses the SAME trend_lookback=5/size_window=20 defaults                |
//| pattern_validation.py's own detect_all_patterns() uses, and the SAME       |
//| "index 0 = most recent bar" convention both sides already document.          |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Patterns/CandlestickPatternEngine.mqh"

input string          InpExportSymbol    = ""; // "" = current chart symbol
input ENUM_TIMEFRAMES  InpExportTimeframe = PERIOD_M15;
input int              InpBarCount        = 500;
input int              InpTrendLookback   = 5;
input int              InpSizeWindow      = 20;
input int              InpSwingDepth      = 3;
input string           InpOutputFile      = "ThembaEA\\Export\\pattern_detector_results.csv";

datetime ServerTimeToUtc(const datetime server_time)
  {
   long offset_seconds = (long)TimeTradeServer() - (long)TimeGMT();
   return (datetime)((long)server_time - offset_seconds);
  }

string Iso8601Utc(const datetime server_time)
  {
   datetime utc = ServerTimeToUtc(server_time);
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ", dt.year, dt.mon, dt.day, dt.hour, dt.min,
                        dt.sec);
  }

string BoolStr(const bool value) { return value ? "True" : "False"; }

void OnStart()
  {
   Print("=== TASK-037 Export_PatternDetectorResults start ===");

   string symbol = (InpExportSymbol == "") ? _Symbol : InpExportSymbol;

   double opens[], highs[], lows[], closes[];
   ArraySetAsSeries(opens, true);
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

   // Shift=1: skip the currently-forming bar, matching this project's own
   // "completed bars only" convention everywhere else.
   int copied_o = CopyOpen(symbol, InpExportTimeframe, 1, InpBarCount, opens);
   int copied_h = CopyHigh(symbol, InpExportTimeframe, 1, InpBarCount, highs);
   int copied_l = CopyLow(symbol, InpExportTimeframe, 1, InpBarCount, lows);
   int copied_c = CopyClose(symbol, InpExportTimeframe, 1, InpBarCount, closes);

   int n = MathMin(MathMin(copied_o, copied_h), MathMin(copied_l, copied_c));
   if(n <= 0)
     {
      PrintFormat("ABORT: could not copy OHLC history for '%s' on %s (copied o=%d h=%d l=%d "
                  "c=%d).", symbol, EnumToString(InpExportTimeframe), copied_o, copied_h, copied_l,
                  copied_c);
      return;
     }
   if(n < InpBarCount)
      PrintFormat("INFO: only %d of the requested %d bars were available for '%s' on %s.", n,
                  InpBarCount, symbol, EnumToString(InpExportTimeframe));

   int atr_handle = iATR(symbol, InpExportTimeframe, 14);
   if(atr_handle == INVALID_HANDLE)
     {
      Print("ABORT: could not create the ATR indicator handle.");
      return;
     }
   double atr_values[];
   ArraySetAsSeries(atr_values, true);
   if(CopyBuffer(atr_handle, 0, 1, n, atr_values) != n)
     {
      Print("ABORT: could not copy the ATR buffer for the requested bar range.");
      IndicatorRelease(atr_handle);
      return;
     }

   int handle = FileOpen(InpOutputFile, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ, 0,
                          CP_UTF8);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("ABORT: could not open '%s' for writing (error=%d).", InpOutputFile,
                  GetLastError());
      IndicatorRelease(atr_handle);
      return;
     }

   FileWriteString(handle, "k,symbol,timestamp,open,high,low,close,atr,"
                           "bullish_pin_bar,bearish_pin_bar,bullish_engulfing,bearish_engulfing,"
                           "dragonfly_rejection,gravestone_rejection,doji,spinning_top,"
                           "inside_bar,outside_bar,harami_detected,harami_confirmed,"
                           "morning_star,evening_star,three_white_soldiers,three_black_crows,"
                           "marubozu,tweezer_top,tweezer_bottom,three_bar_reversal\r\n");

   int rows_written = 0;
   for(int k = 0; k < n; k++)
     {
      ENUM_HARAMI_DIRECTION harami_direction = CP_DetectHaramiArray(opens, closes, k);

      bool bullish_pin_bar = CP_IsBullishPinBarArray(opens, highs, lows, closes, k,
                                                       InpTrendLookback);
      bool bearish_pin_bar = CP_IsBearishPinBarArray(opens, highs, lows, closes, k,
                                                       InpTrendLookback);
      bool bullish_engulfing = CP_IsBullishEngulfingArray(opens, highs, lows, closes, k,
                                                            InpSizeWindow);
      bool bearish_engulfing = CP_IsBearishEngulfingArray(opens, highs, lows, closes, k,
                                                            InpSizeWindow);
      bool dragonfly_rejection = CP_IsDragonflyRejectionArray(opens, highs, lows, closes, k);
      bool gravestone_rejection = CP_IsGravestoneRejectionArray(opens, highs, lows, closes, k);
      bool doji = CP_IsDojiArray(opens, highs, lows, closes, k);
      bool spinning_top = CP_IsSpinningTopArray(opens, highs, lows, closes, k);
      bool inside_bar = CP_IsInsideBarArray(highs, lows, k);
      bool outside_bar = CP_IsOutsideBarArray(highs, lows, k);
      bool harami_detected = (harami_direction != HARAMI_NONE);
      bool harami_confirmed = CP_IsHaramiConfirmedArray(closes, k, harami_direction);
      bool morning_star = CP_IsMorningStarArray(opens, highs, lows, closes, k);
      bool evening_star = CP_IsEveningStarArray(opens, highs, lows, closes, k);
      bool three_white_soldiers = CP_IsThreeWhiteSoldiersArray(opens, highs, lows, closes, k);
      bool three_black_crows = CP_IsThreeBlackCrowsArray(opens, highs, lows, closes, k);
      bool marubozu = CP_IsMarubozuArray(opens, highs, lows, closes, atr_values, k);
      bool tweezer_top = CP_IsTweezerTopArray(opens, highs, lows, closes, atr_values, k);
      bool tweezer_bottom = CP_IsTweezerBottomArray(opens, highs, lows, closes, atr_values, k);
      bool three_bar_reversal = CP_IsThreeBarReversalArray(highs, lows, opens, closes, k,
                                                             InpSwingDepth);

      datetime bar_time = iTime(symbol, InpExportTimeframe, k + 1);

      string line = StringFormat(
         "%d,%s,%s,%.8f,%.8f,%.8f,%.8f,%.8f,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"
         "%s,%s\r\n",
         k, symbol, Iso8601Utc(bar_time), opens[k], highs[k], lows[k], closes[k], atr_values[k],
         BoolStr(bullish_pin_bar), BoolStr(bearish_pin_bar), BoolStr(bullish_engulfing),
         BoolStr(bearish_engulfing), BoolStr(dragonfly_rejection), BoolStr(gravestone_rejection),
         BoolStr(doji), BoolStr(spinning_top), BoolStr(inside_bar), BoolStr(outside_bar),
         BoolStr(harami_detected), BoolStr(harami_confirmed), BoolStr(morning_star),
         BoolStr(evening_star), BoolStr(three_white_soldiers), BoolStr(three_black_crows),
         BoolStr(marubozu), BoolStr(tweezer_top), BoolStr(tweezer_bottom),
         BoolStr(three_bar_reversal));
      FileWriteString(handle, line);
      rows_written++;
     }

   FileClose(handle);
   IndicatorRelease(atr_handle);
   PrintFormat("=== TASK-037 Export_PatternDetectorResults complete: %d row(s) written to "
               "'%s' for '%s' on %s ===", rows_written, InpOutputFile, symbol,
               EnumToString(InpExportTimeframe));
  }
