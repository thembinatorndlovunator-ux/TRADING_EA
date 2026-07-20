//+------------------------------------------------------------------+
//| MarketData.mqh                                                    |
//| Themba Adaptive Intraday Engine — Market                          |
//|                                                                    |
//| The single choke point for completed-bar price access, per        |
//| TASK-002_PHASE2_SPECIFICATION.md's "Data conventions" section:    |
//| "Logical index 0 denotes the most recently completed bar (MQL     |
//| series index 1); logical index k denotes k bars before that (MQL  |
//| series index k+1). No formula anywhere in this document reads MQL |
//| series index 0 (the currently forming bar)."                      |
//|                                                                    |
//| Every other module (regime, candlestick/chart patterns, swings,   |
//| mode router) reads price data ONLY through CMarketData — this is  |
//| deliberate: it is the one place the logical→MQL index translation |
//| (+1) happens, so it is structurally impossible for a downstream   |
//| formula to accidentally read the forming bar by using a raw MQL   |
//| series index instead of a logical one. This directly implements   |
//| ledger item 11 ("completed-candle enforcement, project-wide") and  |
//| PROJECT_RULES.md rule 4 ("No future-candle access or repainting") |
//| and rule 5 ("Confirmed pattern logic uses completed candles").     |
//+------------------------------------------------------------------+
#property strict

class CMarketData
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_atr_periods[];  // cached ATR handle periods
   int             m_atr_handles[];  // parallel array of handles

   int GetOrCreateATRHandle(const int period)
     {
      for(int i = 0; i < ArraySize(m_atr_periods); i++)
         if(m_atr_periods[i] == period)
            return m_atr_handles[i];

      int handle = iATR(m_symbol, m_timeframe, period);
      if(handle == INVALID_HANDLE)
         return INVALID_HANDLE;

      int n = ArraySize(m_atr_periods);
      ArrayResize(m_atr_periods, n + 1);
      ArrayResize(m_atr_handles, n + 1);
      m_atr_periods[n] = period;
      m_atr_handles[n] = handle;
      return handle;
     }

public:
                     CMarketData() { m_symbol = ""; m_timeframe = PERIOD_CURRENT; }

   bool Init(const string sym, const ENUM_TIMEFRAMES tf)
     {
      m_symbol = sym;
      m_timeframe = tf;
      ArrayFree(m_atr_periods);
      ArrayFree(m_atr_handles);
      return SymbolSelect(sym, true);
     }

   string          Symbol() const    { return m_symbol; }
   ENUM_TIMEFRAMES Timeframe() const { return m_timeframe; }

   //--- True iff logical indices 0..count-1 are all valid — i.e. at    --
   //--- least 'count' COMPLETED bars exist (the still-forming bar at   --
   //--- MQL index 0 is never counted towards this).                    --
   bool HasBars(const int count)
     {
      if(count <= 0)
         return true;
      int total = Bars(m_symbol, m_timeframe);
      return total >= (count + 1);
     }

   //--- Logical-index OHLCTV accessors. Each returns false (and leaves --
   //--- 'value' untouched) for a negative index or an index beyond      --
   //--- available history — callers must treat a false return as a      --
   //--- hard-failure read per section 2's "indicator/data failure"      --
   //--- rule, never as an implicit zero.                                 --
   bool GetOpen(const int logical_index, double &value)
     {
      if(logical_index < 0)
         return false;
      double buf[];
      if(CopyOpen(m_symbol, m_timeframe, logical_index + 1, 1, buf) != 1)
         return false;
      value = buf[0];
      return true;
     }

   bool GetHigh(const int logical_index, double &value)
     {
      if(logical_index < 0)
         return false;
      double buf[];
      if(CopyHigh(m_symbol, m_timeframe, logical_index + 1, 1, buf) != 1)
         return false;
      value = buf[0];
      return true;
     }

   bool GetLow(const int logical_index, double &value)
     {
      if(logical_index < 0)
         return false;
      double buf[];
      if(CopyLow(m_symbol, m_timeframe, logical_index + 1, 1, buf) != 1)
         return false;
      value = buf[0];
      return true;
     }

   bool GetClose(const int logical_index, double &value)
     {
      if(logical_index < 0)
         return false;
      double buf[];
      if(CopyClose(m_symbol, m_timeframe, logical_index + 1, 1, buf) != 1)
         return false;
      value = buf[0];
      return true;
     }

   bool GetTime(const int logical_index, datetime &value)
     {
      if(logical_index < 0)
         return false;
      datetime buf[];
      if(CopyTime(m_symbol, m_timeframe, logical_index + 1, 1, buf) != 1)
         return false;
      value = buf[0];
      return true;
     }

   bool GetTickVolume(const int logical_index, long &value)
     {
      if(logical_index < 0)
         return false;
      long buf[];
      if(CopyTickVolume(m_symbol, m_timeframe, logical_index + 1, 1, buf) != 1)
         return false;
      value = buf[0];
      return true;
     }

   //--- ATR value at a logical index, for 'period' (default 14 — the    --
   //--- canonical period most TASK-002 formulas mean by an unqualified  --
   //--- "ATR"; sections naming their own period, e.g. section 5's       --
   //--- InpCandleATRPeriod, pass it explicitly). Handles are created     --
   //--- once per distinct period and cached for the lifetime of this     --
   //--- CMarketData instance.                                            --
   bool GetATR(const int logical_index, double &value, const int period = 14)
     {
      if(logical_index < 0)
         return false;
      int handle = GetOrCreateATRHandle(period);
      if(handle == INVALID_HANDLE)
         return false;
      double buf[];
      if(CopyBuffer(handle, 0, logical_index + 1, 1, buf) != 1)
         return false;
      value = buf[0];
      return true;
     }
  };
