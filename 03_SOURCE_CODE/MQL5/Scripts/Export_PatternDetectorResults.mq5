//+------------------------------------------------------------------+
//| Export_PatternDetectorResults.mq5                                 |
//| Themba Adaptive Intraday Engine — TASK-037 real-data export tool   |
//|                                                                    |
//| Runs the EXACT live MQL5 pattern predicates                          |
//| (CandlestickPatternEngine.mqh) against a real OHLC history segment      |
//| and writes one CSV row per bar (k, <pattern booleans>), in the           |
//| schema analysis/pattern_validation.py's compare_to_mql5_export             |
//| already expects.                                                             |
//|                                                                    |
//| **Scoped to exactly the 4 patterns pattern_validation.py's own          |
//| detect_all_patterns() currently computes (bullish_pin_bar,                    |
//| bearish_pin_bar, bullish_engulfing, bearish_engulfing) -- a stated,             |
//| documented scope decision, not an oversight. CandlestickPatternEngine.mqh          |
//| has 14 more predicates and ChartPatternEngine.mqh has its own 4 chart               |
//| patterns, but TASK-033 (pattern-validation completion) has not yet                    |
//| ported any of those into detect_all_patterns() -- exporting MORE columns               |
//| than Python currently validates would not be comparable against anything                 |
//| yet, and this export's whole point is to be immediately runnable through                  |
//| compare_to_mql5_export(). Extend this export once TASK-033 ships the                        |
//| corresponding Python-side predicates, matching column names exactly.**                       |
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
input string           InpOutputFile      = "ThembaEA\\Export\\pattern_detector_results.csv";

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

   int handle = FileOpen(InpOutputFile, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ, 0,
                          CP_UTF8);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("ABORT: could not open '%s' for writing (error=%d).", InpOutputFile,
                  GetLastError());
      return;
     }

   FileWriteString(handle, "k,bullish_pin_bar,bearish_pin_bar,bullish_engulfing,"
                           "bearish_engulfing\r\n");

   int rows_written = 0;
   for(int k = 0; k < n; k++)
     {
      bool bullish_pin_bar = CP_IsBullishPinBarArray(opens, highs, lows, closes, k,
                                                       InpTrendLookback);
      bool bearish_pin_bar = CP_IsBearishPinBarArray(opens, highs, lows, closes, k,
                                                       InpTrendLookback);
      bool bullish_engulfing = CP_IsBullishEngulfingArray(opens, highs, lows, closes, k,
                                                            InpSizeWindow);
      bool bearish_engulfing = CP_IsBearishEngulfingArray(opens, highs, lows, closes, k,
                                                            InpSizeWindow);

      string line = StringFormat("%d,%s,%s,%s,%s\r\n", k, bullish_pin_bar ? "True" : "False",
                                  bearish_pin_bar ? "True" : "False",
                                  bullish_engulfing ? "True" : "False",
                                  bearish_engulfing ? "True" : "False");
      FileWriteString(handle, line);
      rows_written++;
     }

   FileClose(handle);
   PrintFormat("=== TASK-037 Export_PatternDetectorResults complete: %d row(s) written to "
               "'%s' for '%s' on %s ===", rows_written, InpOutputFile, symbol,
               EnumToString(InpExportTimeframe));
  }
