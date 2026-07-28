//+------------------------------------------------------------------+
//| Export_PredictedRegime.mq5                                       |
//| Themba Adaptive Intraday Engine — TASK-037 real-data export tool   |
//|                                                                    |
//| Runs the LIVE, FULLY GATED regime state machine (raw MRE_ClassifyArray  |
//| classification, then the SAME low-confidence-override / spread-           |
//| liquidity gate / news-blackout gate / hysteresis composition                 |
//| ThembaAdaptiveIntradayEA.mq5's EvaluateAndJournal() actually runs) over        |
//| a real historical OHLC segment, replayed in CHRONOLOGICAL order (oldest         |
//| bar first) — hysteresis and the gate composer are both STATEFUL across            |
//| bars, so a chronological replay is not optional, it is what makes this               |
//| a faithful reproduction of the live path at all. Writes one CSV row per                 |
//| bar: symbol, timestamp, predicted_regime (plus diagnostic columns —                       |
//| see the header written below).                                                              |
//|                                                                    |
//| **Rewritten, 2026-07-22 (Codex review finding, seventh round, P1 finding |
//| 12):** the previous version called the raw, stateless MRE_ClassifyArray      |
//| directly and emitted ITS output as "predicted_regime" — never the             |
//| low-confidence override, spread/liquidity gate, news gate, or hysteresis         |
//| the live EA actually composes on top of that raw read, so calling this              |
//| export's own output "predicted LIVE regime" was incorrect. It also                     |
//| iterated newest-to-oldest, which — now that hysteresis genuinely depends                  |
//| on bar-to-bar order — would silently replay the state machine backwards                     |
//| if left uncorrected. On an invalid/insufficient-data bar it previously                         |
//| skipped the row entirely rather than the specified zero-confidence                               |
//| transition/data-failure record.                                                                     |
//|                                                                    |
//| **Stated, bounded limitation, not silently omitted:** the spread/          |
//| liquidity gate is NOT replayed historically — MT5 exposes no historical       |
//| per-bar spread series without a much larger, separate tick-history-based         |
//| effort (SYMBOL_SPREAD only ever reflects the CURRENT live spread). This             |
//| export therefore always evaluates that ONE gate as "not triggered" for   |
//| every historical bar; every OTHER gate (low-confidence override, news      |
//| blackout, hysteresis) IS faithfully replayed. The news gate uses              |
//| MT5CalendarProvider.mqh's own historically-capable                              |
//| CalendarValueHistory-backed fetch (genuinely historical, unlike spread) --         |
//| NM_IsInBlackoutWindowArray already takes an explicit                                 |
//| 'current_server_time' parameter, so this replay calls it with each                      |
//| historical bar's own time rather than TimeCurrent().**                                    |
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

#include "../Include/ThembaEA/Market/RegimeGateComposer.mqh"
#include "../Include/ThembaEA/News/MT5CalendarProvider.mqh"

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

// Matches ThembaAdaptiveIntradayEA.mq5's own news-gate defaults
// (InpNewsCurrency/InpNewsMinImportance/InpNewsBlackoutBeforeMinutes/
// InpNewsBlackoutAfterMinutes/InpHysteresisRequiredBars).
input string InpNewsCurrency              = "USD";
input int    InpNewsMinImportance         = 3;
input int    InpNewsBlackoutBeforeMinutes = 15;
input int    InpNewsBlackoutAfterMinutes  = 15;
input int    InpHysteresisRequiredBars    = 2;

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

//+------------------------------------------------------------------+
//| One historical bar's own raw classification, collected during the    |
//| first (newest-to-oldest, history-bounded) scan pass -- the stateful      |
//| gating pipeline (low-confidence override, news gate, hysteresis) is        |
//| applied AFTERWARD, in a SECOND, chronological (oldest-to-newest) pass.       |
//+------------------------------------------------------------------+
struct SBarClassification
  {
   datetime    bar_time; // server time (matches iTime's own convention)
   bool        data_ok;  // false = a required read failed this bar
   SRegimeRead regime_read; // only meaningful when data_ok is true
  };

void OnStart()
  {
   Print("=== TASK-037 Export_PredictedRegime start ===");

   string symbol = (InpExportSymbol == "") ? _Symbol : InpExportSymbol;

   int window = MathMax(XPR_ATR_PERCENTILE_WINDOW, XPR_EFFICIENCY_WINDOW + 1);
   window = MathMax(window, InpSwingDepth * 2 + InpMaxLookback + 5);

   int ema_handle = iMA(symbol, InpExportTimeframe, XPR_EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   int adx_handle = iADX(symbol, InpExportTimeframe, XPR_ADX_PERIOD);
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

   //--- Pass 1: scan newest-to-oldest (bounded by available history), -----
   //--- collecting each bar's own raw classification. This is purely a  -----
   //--- data-fetch pass -- no gating/hysteresis state is touched here. -------
   SBarClassification bars[]; // bars[0] = newest, bars[last] = oldest

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

      SBarClassification bc;
      bc.bar_time = iTime(symbol, InpExportTimeframe, shift);

      double atr_values[];
      ArraySetAsSeries(atr_values, true);
      double ema_buf[];
      double adx_buf[];
      bool reads_ok = (CopyBuffer(atr_handle, 0, shift, XPR_ATR_PERCENTILE_WINDOW, atr_values) ==
                       XPR_ATR_PERCENTILE_WINDOW) &&
                      (CopyBuffer(ema_handle, 0, shift, XPR_EMA_SLOPE_BARS + 1, ema_buf) ==
                       XPR_EMA_SLOPE_BARS + 1) &&
                      (CopyBuffer(adx_handle, 0, shift, 1, adx_buf) == 1);

      if(!reads_ok)
         bc.data_ok = false;
      else
        {
         // CopyBuffer's own default order is OLDEST-to-NEWEST when
         // ArraySetAsSeries is NOT applied -- matching MRE_ClassifyLive's own
         // documented convention exactly (see that function's own comment).
         double ema_now = ema_buf[ArraySize(ema_buf) - 1];
         double ema_prior = ema_buf[0];
         double adx_now = adx_buf[0];

         bc.regime_read = MRE_ClassifyArray(closes, highs, lows, atr_values, atr_values[0], ema_now,
                                              ema_prior, adx_now, XPR_EFFICIENCY_WINDOW,
                                              InpSwingDepth, InpMaxLookback, XPR_TREND_THRESHOLD,
                                              XPR_EXPANSION_THRESHOLD, XPR_COMPRESSION_THRESHOLD,
                                              XPR_MIN_EFFICIENCY, XPR_TREND_SLOPE_DIVISOR);
         bc.data_ok = true; // reads succeeded -- bc.regime_read.valid may still be false, handled below
        }

      int n = ArraySize(bars);
      ArrayResize(bars, n + 1);
      bars[n] = bc;
     }

   int total_bars = ArraySize(bars);
   if(total_bars == 0)
     {
      Print("ABORT: no bar had sufficient history to classify -- nothing to export.");
      IndicatorRelease(ema_handle);
      IndicatorRelease(adx_handle);
      IndicatorRelease(atr_handle);
      return;
     }

   //--- Fetch news events ONCE for the exact time span this export covers, -
   //--- with a margin for the before/after blackout window -- bars[total-1] --
   //--- is the OLDEST collected bar, bars[0] the NEWEST (server time). --------
   datetime oldest_bar_time = bars[total_bars - 1].bar_time;
   datetime newest_bar_time = bars[0].bar_time;
   long server_gmt_offset_seconds = (long)TimeTradeServer() - (long)TimeGMT();
   datetime from_utc = (datetime)((long)oldest_bar_time - server_gmt_offset_seconds -
                                   InpNewsBlackoutBeforeMinutes * 60);
   datetime to_utc = (datetime)((long)newest_bar_time - server_gmt_offset_seconds +
                                 InpNewsBlackoutAfterMinutes * 60);
   SNewsEvent news_events[];
   int news_result = MTC_FetchEvents(InpNewsCurrency, InpNewsMinImportance, from_utc, to_utc,
                                       news_events);
   if(news_result < 0)
      Print("WARNING: MTC_FetchEvents failed for this export's date range -- the news gate will "
            "be evaluated against ZERO events for every bar (fail-OPEN for this historical "
            "replay only -- unlike the live EA, which fails closed, a replay cannot retry a "
            "failed historical calendar fetch). Treat exported news_gate_active as unreliable if "
            "this warning appears.");

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
   FileWriteString(handle, "symbol,timestamp,predicted_regime,raw_regime,confidence,"
                           "low_confidence_override,news_gate_active,spread_liquidity_gate_active\r\n");

   //--- Pass 2: replay CHRONOLOGICALLY (oldest first) -- hysteresis and ----
   //--- the gate composer are both stateful across bars, so this order is ---
   //--- not optional. -----------------------------------------------------------
   SRegimeHysteresisState hysteresis_state;
   MRE_InitHysteresisState(hysteresis_state);

   int rows_written = 0;
   for(int i = total_bars - 1; i >= 0; i--)
     {
      SBarClassification bc = bars[i];

      if(!bc.data_ok || !bc.regime_read.valid)
        {
         // Matches ThembaAdaptiveIntradayEA.mq5's own JournalDataFailureDecision:
         // a zero-confidence TRANSITION_OR_UNCERTAIN record, with an
         // immediate hysteresis bypass so a subsequent good read does not
         // have to fight through stale pending hysteresis state left over
         // from this failure bar.
         MRE_ApplyHysteresis(hysteresis_state, REGIME_TRANSITION_OR_UNCERTAIN, true,
                              InpHysteresisRequiredBars);
         string line = StringFormat("%s,%s,%s,%s,%.4f,%s,%s,%s\r\n", symbol,
                                     Iso8601Utc(bc.bar_time),
                                     RegimeToPythonVocabulary(REGIME_TRANSITION_OR_UNCERTAIN),
                                     "DATA_FAILURE", 0.0, "false", "false", "false");
         FileWriteString(handle, line);
         rows_written++;
         continue;
        }

      ENUM_MARKET_REGIME regime_for_gating = bc.regime_read.low_confidence_override
                                              ? REGIME_TRANSITION_OR_UNCERTAIN
                                              : bc.regime_read.regime;

      string triggering_event_id;
      bool news_blackout = NM_IsInBlackoutWindowArray(news_events, bc.bar_time,
                                                        InpNewsBlackoutBeforeMinutes,
                                                        InpNewsBlackoutAfterMinutes,
                                                        InpNewsMinImportance, triggering_event_id);

      // Stated, bounded limitation (see file header): the spread/liquidity
      // gate cannot be reconstructed historically -- always "not triggered."
      bool spread_liquidity_untradeable = false;

      SRegimeGateResult gate_result = RGC_ComposeGates(hysteresis_state, regime_for_gating,
                                                         spread_liquidity_untradeable, news_blackout,
                                                         triggering_event_id,
                                                         InpHysteresisRequiredBars);

      string line = StringFormat(
         "%s,%s,%s,%s,%.4f,%s,%s,%s\r\n", symbol, Iso8601Utc(bc.bar_time),
         RegimeToPythonVocabulary(gate_result.effective_regime),
         RegimeToPythonVocabulary(bc.regime_read.regime), bc.regime_read.confidence,
         bc.regime_read.low_confidence_override ? "true" : "false",
         gate_result.news_gate_active ? "true" : "false", "false");
      FileWriteString(handle, line);
      rows_written++;
     }

   FileClose(handle);
   IndicatorRelease(ema_handle);
   IndicatorRelease(adx_handle);
   IndicatorRelease(atr_handle);
   PrintFormat("=== TASK-037 Export_PredictedRegime complete: %d row(s) written to '%s' for "
               "'%s' on %s, in CHRONOLOGICAL order, predicted_regime = the FULLY GATED effective "
               "regime (low-confidence override + news gate + hysteresis all replayed; the "
               "spread/liquidity gate is NOT -- see file header) -- this is the PREDICTED side "
               "only; see REGIME_LABELLING_PROTOCOL.md for the independently-labelled ground "
               "truth this must be joined against ===", rows_written, InpOutputFile, symbol,
               EnumToString(InpExportTimeframe));
  }
