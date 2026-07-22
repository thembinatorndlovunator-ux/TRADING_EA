//+------------------------------------------------------------------+
//| Export_PredictedRegime.mq5                                       |
//| Themba Adaptive Intraday Engine — TASK-037 real-data export tool   |
//|                                                                    |
//| Runs the LIVE regime classifier (MarketRegimeEngine.mqh's                |
//| MRE_ClassifyArray — the exact pure classification core                     |
//| MRE_ClassifyLive itself delegates to, per this task's own Risks              |
//| section: "never a reimplementation") against a real historical OHLC             |
//| segment, at EVERY historical bar, and writes one CSV row per bar:                 |
//| symbol, timestamp, predicted_regime.                                                  |
//|                                                                    |
//| **Why MRE_ClassifyArray directly, not MRE_ClassifyLive:**              |
//| MRE_ClassifyLive is hardcoded to classify "as of now" (via CMarketData's    |
//| own logical-index-0-is-the-latest-completed-bar convention); it has no        |
//| parameter for "classify as of N bars ago." Its OWN body is nothing more          |
//| than fetching the right OHLC/ATR/EMA/ADX windows and calling                       |
//| MRE_ClassifyArray. This script does exactly that same window-fetching                |
//| (parameterized by a variable historical shift instead of MRE_ClassifyLive's            |
//| hardcoded "now"), then calls the SAME MRE_ClassifyArray the live EA uses --               |
//| the actual classification math is never re-derived, only the array-fetching                |
//| plumbing is (mechanical, low-risk, and matches MRE_ClassifyLive's own                         |
//| already-established pattern almost verbatim).                                                    |
//|                                                                    |
//| Uses the EXACT same constants ThembaAdaptiveIntradayEA.mq5's                |
//| EvaluateAndJournal() hardcodes, so this really is "what the live EA          |
//| would have classified," not an independently-tuned historical replay.           |
//|                                                                    |
//| **This is only the PREDICTED side.** Per TASK-037 Specification item 4,      |
//| the independently-labelled ground truth needed for                                |
//| regime_validation.build_confusion_matrix must come from a human analyst              |
//| hand-labelling the SAME chart segment from the raw candles alone, BEFORE               |
//| ever looking at this export's own output -- see                                          |
//| REGIME_LABELLING_PROTOCOL.md for that protocol and the exact CSV schema                     |
//| the labelled side must produce. This script cannot do that part; it is                        |
//| the user's own step.                                                                             |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Market/MarketRegimeEngine.mqh"

input string          InpExportSymbol    = ""; // "" = current chart symbol
input ENUM_TIMEFRAMES  InpExportTimeframe = PERIOD_M15;
input int              InpBarCount        = 500;
input int              InpSwingDepth      = 3;
input int              InpMaxLookback     = 50;
input string           InpOutputFile      = "ThembaEA\\Export\\predicted_regime.csv";

// Matches ThembaAdaptiveIntradayEA.mq5's EvaluateAndJournal() constants exactly.
#define XPR_ATR_PERCENTILE_WINDOW 100
#define XPR_EFFICIENCY_WINDOW     20
#define XPR_EMA_PERIOD            21
#define XPR_EMA_SLOPE_BARS        5
#define XPR_ADX_PERIOD            14
#define XPR_TREND_THRESHOLD       0.6
#define XPR_EXPANSION_THRESHOLD   0.75
#define XPR_COMPRESSION_THRESHOLD 0.25
#define XPR_MIN_EFFICIENCY        0.3
#define XPR_TREND_SLOPE_DIVISOR   0.5

// **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding 10):**
// iTime(...) returns trade-SERVER time -- this export previously formatted
// it directly with a "Z" (UTC) suffix. See Export_TradeHistory.mq5's own
// identical fix/comment for the stated historical-DST approximation this
// necessarily makes.
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

//+------------------------------------------------------------------+
//| analysis/regime_validation.py's own Regime enum values have NO        |
//| "REGIME_" prefix ("TRENDING_UP", not "REGIME_TRENDING_UP"), while        |
//| MQL5's EnumToString(ENUM_MARKET_REGIME) always includes it -- strip it     |
//| here so predicted_regime matches that module's exact vocabulary.            |
//+------------------------------------------------------------------+
string RegimeToPythonVocabulary(const ENUM_MARKET_REGIME regime)
  {
   string s = EnumToString(regime);
   StringReplace(s, "REGIME_", "");
   return s;
  }

void OnStart()
  {
   Print("=== TASK-037 Export_PredictedRegime start ===");

   string symbol = (InpExportSymbol == "") ? _Symbol : InpExportSymbol;

   int window = MathMax(XPR_ATR_PERCENTILE_WINDOW, XPR_EFFICIENCY_WINDOW + 1);
   window = MathMax(window, InpSwingDepth * 2 + InpMaxLookback + 5);

   int ema_handle = iMA(symbol, InpExportTimeframe, XPR_EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   int adx_handle = iADX(symbol, InpExportTimeframe, XPR_ADX_PERIOD);
   // **Fixed, 2026-07-22 (Codex review finding, seventh round, P1 finding
   // 12): the ATR handle was previously created FRESH inside every
   // exported-bar iteration and never released -- a 500-bar export leaked
   // 500 indicator handles. Created ONCE here instead, matching ema/adx's
   // own already-correct pattern, and released alongside them below.**
   int atr_handle = iATR(symbol, InpExportTimeframe, 14);
   if(ema_handle == INVALID_HANDLE || adx_handle == INVALID_HANDLE ||
      atr_handle == INVALID_HANDLE)
     {
      Print("ABORT: could not create the EMA/ADX/ATR indicator handles.");
      if(ema_handle != INVALID_HANDLE) IndicatorRelease(ema_handle);
      if(adx_handle != INVALID_HANDLE) IndicatorRelease(adx_handle);
      if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
      return;
     }

   int handle = FileOpen(InpOutputFile, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ, 0,
                          CP_UTF8);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("ABORT: could not open '%s' for writing (error=%d).", InpOutputFile,
                  GetLastError());
      IndicatorRelease(ema_handle);
      IndicatorRelease(adx_handle);
      IndicatorRelease(atr_handle);
      return;
     }
   FileWriteString(handle, "symbol,timestamp,predicted_regime\r\n");

   int rows_written = 0;
   for(int i = 0; i < InpBarCount; i++)
     {
      int shift = i + 1; // logical index i -> MQL series index i+1, matching this
                          // project's own "Data conventions" everywhere else.

      double closes[], highs[], lows[];
      ArraySetAsSeries(closes, true);
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);
      int copied_c = CopyClose(symbol, InpExportTimeframe, shift, window, closes);
      int copied_h = CopyHigh(symbol, InpExportTimeframe, shift, window, highs);
      int copied_l = CopyLow(symbol, InpExportTimeframe, shift, window, lows);
      if(copied_c < window || copied_h < window || copied_l < window)
         break; // ran out of history further back than this

      double atr_values[];
      ArraySetAsSeries(atr_values, true);
      if(CopyBuffer(atr_handle, 0, shift, XPR_ATR_PERCENTILE_WINDOW, atr_values) !=
         XPR_ATR_PERCENTILE_WINDOW)
         break;

      double ema_buf[];
      if(CopyBuffer(ema_handle, 0, shift, XPR_EMA_SLOPE_BARS + 1, ema_buf) !=
         XPR_EMA_SLOPE_BARS + 1)
         break;
      // CopyBuffer's own default order is OLDEST-to-NEWEST when
      // ArraySetAsSeries is NOT applied -- matching MRE_ClassifyLive's own
      // documented convention exactly (see that function's own comment).
      double ema_now = ema_buf[ArraySize(ema_buf) - 1];
      double ema_prior = ema_buf[0];

      double adx_buf[];
      if(CopyBuffer(adx_handle, 0, shift, 1, adx_buf) != 1)
         break;
      double adx_now = adx_buf[0];

      SRegimeRead r = MRE_ClassifyArray(closes, highs, lows, atr_values, atr_values[0], ema_now,
                                          ema_prior, adx_now, XPR_EFFICIENCY_WINDOW, InpSwingDepth,
                                          InpMaxLookback, XPR_TREND_THRESHOLD,
                                          XPR_EXPANSION_THRESHOLD, XPR_COMPRESSION_THRESHOLD,
                                          XPR_MIN_EFFICIENCY, XPR_TREND_SLOPE_DIVISOR);
      if(!r.valid)
         continue; // matches the live EA's own "skip this bar" behavior

      datetime bar_time = iTime(symbol, InpExportTimeframe, shift);
      string line = StringFormat("%s,%s,%s\r\n", symbol, Iso8601Utc(bar_time),
                                  RegimeToPythonVocabulary(r.regime));
      FileWriteString(handle, line);
      rows_written++;
     }

   FileClose(handle);
   IndicatorRelease(ema_handle);
   IndicatorRelease(adx_handle);
   IndicatorRelease(atr_handle);
   PrintFormat("=== TASK-037 Export_PredictedRegime complete: %d row(s) written to '%s' for "
               "'%s' on %s -- this is the PREDICTED side only; see "
               "REGIME_LABELLING_PROTOCOL.md for the independently-labelled ground truth this "
               "must be joined against ===", rows_written, InpOutputFile, symbol,
               EnumToString(InpExportTimeframe));
  }
