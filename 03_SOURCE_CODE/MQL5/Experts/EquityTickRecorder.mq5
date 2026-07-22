//+------------------------------------------------------------------+
//| EquityTickRecorder.mq5                                            |
//| Themba Adaptive Intraday Engine — TASK-037 real-data export tool   |
//|                                                                    |
//| A standalone, minimal EA (not a Test_*.mq5/Export_*.mq5 script,       |
//| deliberately -- a script's OnStart() runs once and exits, but             |
//| genuine intratrade equity-peak/giveback metrics need a sample on            |
//| every tick, which only a continuously-running EA/indicator can                |
//| provide) that appends one row of                                                 |
//| (timestamp_utc, equity, balance) to a CSV on every tick. This is the                |
//| input `analysis.metrics.compute_balance_peak_giveback`'s own docstring                |
//| explicitly says it does NOT provide (that function is a closed-trade                    |
//| BALANCE proxy only) -- TASK-037 Specification item 7 / the P0-2 finding                   |
//| this project's TASK-028 round-6 review named as "genuinely blocked                          |
//| without a real intratrade equity-tick export."                                                  |
//|                                                                    |
//| Attach this to any chart alongside (or instead of)                    |
//| ThembaAdaptiveIntradayEA.mq5 -- it does not read decisions or place        |
//| orders itself; it only observes and records this ACCOUNT's own equity/         |
//| balance, which is symbol-agnostic by nature (one account, not one per            |
//| symbol) - InpOutputFile therefore does not vary by chart symbol.                    |
//|                                                                    |
//| InpSampleEveryNTicks (default 1 -- every tick) exists purely to bound     |
//| file-write volume on a very fast tick stream; set to 1 for the most           |
//| faithful intratrade equity curve.                                                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "TASK-037 real-data export: records this account's own equity/balance on every tick."

input string InpOutputFile        = "ThembaEA\\Export\\equity_ticks.csv";
input int    InpSampleEveryNTicks = 1;

int    g_file_handle = INVALID_HANDLE;
long   g_tick_counter = 0;

string Iso8601Utc(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ", dt.year, dt.mon, dt.day, dt.hour, dt.min,
                        dt.sec);
  }

int OnInit()
  {
   bool file_exists = FileIsExist(InpOutputFile);
   g_file_handle = FileOpen(InpOutputFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI |
                             FILE_SHARE_READ, 0, CP_UTF8);
   if(g_file_handle == INVALID_HANDLE)
     {
      PrintFormat("EquityTickRecorder: could not open '%s' for writing (error=%d) -- refusing "
                  "to run.", InpOutputFile, GetLastError());
      return INIT_FAILED;
     }

   FileSeek(g_file_handle, 0, SEEK_END);
   if(!file_exists)
      FileWriteString(g_file_handle, "timestamp_utc,equity,balance\r\n");

   PrintFormat("EquityTickRecorder: initialized, appending to '%s' every %d tick(s).",
               InpOutputFile, InpSampleEveryNTicks);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_file_handle != INVALID_HANDLE)
     {
      FileClose(g_file_handle);
      g_file_handle = INVALID_HANDLE;
     }
  }

void OnTick()
  {
   g_tick_counter++;
   if(InpSampleEveryNTicks > 1 && (g_tick_counter % InpSampleEveryNTicks) != 0)
      return;

   if(g_file_handle == INVALID_HANDLE)
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   string line = StringFormat("%s,%.2f,%.2f\r\n", Iso8601Utc(TimeCurrent()), equity, balance);
   FileWriteString(g_file_handle, line);
  }
