//+------------------------------------------------------------------+
//| EquityTickRecorder.mq5                                            |
//| Themba Adaptive Intraday Engine — TASK-037 real-data export tool   |
//|                                                                    |
//| A standalone, minimal EA (not a Test_*.mq5/Export_*.mq5 script,       |
//| deliberately -- a script's OnStart() runs once and exits, but             |
//| genuine intratrade equity-peak/giveback metrics need a sample on            |
//| every tick, which only a continuously-running EA/indicator can                |
//| provide) that appends one row of                                                 |
//| (timestamp_utc, run_id, account_login, broker_server, equity, balance)              |
//| to a CSV. This is the input                                                            |
//| `analysis.metrics.compute_balance_peak_giveback`'s own docstring                          |
//| explicitly says it does NOT provide (that function is a closed-trade                        |
//| BALANCE proxy only) -- TASK-037 Specification item 7 / the P0-2 finding                       |
//| this project's TASK-028 round-6 review named as "genuinely blocked                              |
//| without a real intratrade equity-tick export."                                                      |
//|                                                                    |
//| **Fixed, 2026-07-22 (Codex review finding, seventh round, P1 finding    |
//| 13):**                                                                       |
//| - Samples on a MILLISECOND TIMER (EventSetMillisecondTimer), not OnTick --      |
//|   the previous OnTick-based design only sampled when THIS chart's own            |
//|   attached symbol ticked, so account equity changes driven by another               |
//|   symbol's own position while this chart was quiet were missed entirely --            |
//|   not a genuine account-level, symbol-agnostic series as claimed. A timer               |
//|   samples on wall-clock time regardless of which symbol last ticked.                       |
//| - InpSampleIntervalMs replaces InpSampleEveryNTicks (a tick count has no             |
//|   meaning for a timer); a non-positive value is rejected at OnInit rather               |
//|   than silently accepted.                                                                  |
//| - Every row now also carries run_id (this EA instance's own OnInit-time                     |
//|   TimeLocal() timestamp, disambiguating separate runs appended to the same                   |
//|   file), account_login, and broker_server -- the file previously lacked any                    |
//|   account/broker/run identity at all.                                                              |
//| - Every write is followed by FileFlush so a crash cannot lose buffered                              |
//|   samples.                                                                                             |
//| - Timestamps use DJ_ServerTimeToUtc's own conversion (duplicated here,                                    |
//|   this file has no dependency on DecisionJournal.mqh) instead of labelling                                  |
//|   server time "Z" directly (P0 finding 10).                                                                    |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"
#property description "TASK-037 real-data export: records this account's own equity/balance on a wall-clock timer."

input string InpOutputFile        = "ThembaEA\\Export\\equity_ticks.csv";
input int    InpSampleIntervalMs  = 1000; // milliseconds between samples; must be positive

int      g_file_handle = INVALID_HANDLE;
datetime g_run_id       = 0;

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

int OnInit()
  {
   if(InpSampleIntervalMs <= 0)
     {
      PrintFormat("EquityTickRecorder: InpSampleIntervalMs must be positive, got %d -- refusing "
                  "to run.", InpSampleIntervalMs);
      return INIT_FAILED;
     }

   g_run_id = TimeLocal();

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
      FileWriteString(g_file_handle, "timestamp_utc,run_id,account_login,broker_server,equity,"
                                     "balance\r\n");

   if(!EventSetMillisecondTimer(InpSampleIntervalMs))
     {
      PrintFormat("EquityTickRecorder: EventSetMillisecondTimer failed (error=%d) -- refusing "
                  "to run.", GetLastError());
      FileClose(g_file_handle);
      g_file_handle = INVALID_HANDLE;
      return INIT_FAILED;
     }

   PrintFormat("EquityTickRecorder: initialized, appending to '%s' every %d ms (run_id=%I64d).",
               InpOutputFile, InpSampleIntervalMs, (long)g_run_id);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_file_handle != INVALID_HANDLE)
     {
      FileClose(g_file_handle);
      g_file_handle = INVALID_HANDLE;
     }
  }

void OnTimer()
  {
   if(g_file_handle == INVALID_HANDLE)
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);

   string line = StringFormat("%s,%I64d,%I64d,%s,%.2f,%.2f\r\n", Iso8601Utc(TimeTradeServer()),
                               (long)g_run_id, login, server, equity, balance);
   FileWriteString(g_file_handle, line);
   FileFlush(g_file_handle);
  }
