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
//|                                                                    |
//| **Added, 2026-07-27 (Codex review finding, ninth round, P1 finding 16):  |
//| a new 'timestamp_server' column (the SAME tick's own TimeTradeServer(),         |
//| formatted plainly, no "Z" -- this is genuinely NOT UTC). The live risk           |
//| contract's daily boundary (PROJECT_RULES.md / SessionManager.mqh's own              |
//| SN_CurrentDailyBoundary) resets at TRADE-SERVER midnight, explicitly not             |
//| UTC -- analysis.equity_curve_metrics.py's own "daily" giveback metric                  |
//| previously grouped by UTC calendar date, which a broker-server GMT                        |
//| offset can split into two Python days (or merge two adjacent server                          |
//| days) relative to what the live EA actually experienced. Recording the                           |
//| server time directly here lets the Python side group by the SAME                                    |
//| server-calendar-day boundary the live engine actually resets on,                                        |
//| instead of silently substituting a different (UTC) clock.**                                                |
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

//+------------------------------------------------------------------+
//| **Added, 2026-07-27 (Codex review finding, ninth round, P1 finding    |
//| 16):** plain (non-UTC) server-local timestamp formatting -- no "Z"        |
//| suffix, since this is deliberately NOT UTC. Lets the Python side group      |
//| by the live risk contract's own trade-server-midnight daily boundary,        |
//| not a UTC calendar date that a broker-server GMT offset can split or          |
//| merge relative to it.                                                          |
//+------------------------------------------------------------------+
string Iso8601ServerLocal(const datetime server_time)
  {
   MqlDateTime dt;
   TimeToStruct(server_time, dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min,
                        dt.sec);
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P1 finding    |
//| 18):** broker_server (ACCOUNT_SERVER, a broker-controlled string this          |
//| EA does not control) was previously written into the CSV row via plain            |
//| StringFormat concatenation, with no quoting -- a server name containing               |
//| a literal comma, double-quote, or newline (not something this project                    |
//| can rule out from a third-party broker) would silently shift every                          |
//| later field on that row, corrupting the CSV structure rather than just                          |
//| the one field. Standard RFC 4180 CSV quoting: a field containing a                                  |
//| comma/quote/newline is wrapped in double quotes, with any embedded                                     |
//| quote doubled; a field needing none of that is returned unchanged                                        |
//| (matching every other row's own unquoted plain-numeric fields).**                                            |
//+------------------------------------------------------------------+
string CsvQuoteField(const string value)
  {
   if(StringFind(value, ",") < 0 && StringFind(value, "\"") < 0 &&
      StringFind(value, "\n") < 0 && StringFind(value, "\r") < 0)
      return value;
   string escaped = value;
   StringReplace(escaped, "\"", "\"\"");
   return "\"" + escaped + "\"";
  }

// **Added, 2026-07-28 (Codex review finding, tenth round, P1 finding 14):**
// the exact, current CSV header -- the single source of truth both the
// fresh-file write path and the existing-file validation path below
// compare against, so the two can never silently drift apart.
#define EQUITY_TICK_CSV_HEADER \
   "timestamp_utc,timestamp_server,run_id,account_login,broker_server,equity,balance\r\n"

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

   // **Fixed, 2026-07-28 (Codex review finding, tenth round, P1 finding
   // 14):** OnInit previously only checked FileIsExist() before deciding
   // whether to write a fresh header -- an OLD-schema file (six columns,
   // predating b84446c's 'timestamp_server' addition), a zero-byte file
   // with no header at all, or any other wrong-schema file was opened and
   // then silently received new seven-column rows appended underneath
   // whatever (or no) header it already had, corrupting the file's own
   // schema consistency. A pre-existing NON-EMPTY file's actual first line
   // is now read back and compared against the exact current header
   // BEFORE any row is ever appended -- a mismatch fails closed (refuses
   // to run) rather than silently corrupting the dataset. A zero-byte
   // existing file (never had any schema imposed) is treated the same as
   // "does not exist" -- safe to initialize fresh, nothing to corrupt.
   bool file_has_content = false;
   if(file_exists)
     {
      int probe_handle = FileOpen(InpOutputFile, FILE_READ | FILE_TXT | FILE_ANSI |
                                   FILE_SHARE_READ, 0, CP_UTF8);
      if(probe_handle == INVALID_HANDLE)
        {
         PrintFormat("EquityTickRecorder: could not open existing '%s' to validate its own "
                     "header (error=%d) -- refusing to run rather than risk appending "
                     "incompatible rows to an unverified file.", InpOutputFile, GetLastError());
         return INIT_FAILED;
        }
      if(!FileIsEnding(probe_handle))
        {
         file_has_content = true;
         string existing_header = FileReadString(probe_handle);
         // FileReadString does not include the line terminator -- compare
         // against the expected header with its own trailing "\r\n" stripped.
         string expected_header = EQUITY_TICK_CSV_HEADER;
         StringReplace(expected_header, "\r\n", "");
         if(existing_header != expected_header)
           {
            FileClose(probe_handle);
            PrintFormat("EquityTickRecorder: existing '%s' has an incompatible header "
                        "(expected '%s', found '%s') -- refusing to append seven-column rows "
                        "to a file whose own schema does not match. Move/rename the old file, "
                        "or point InpOutputFile at a new path, before running again.",
                        InpOutputFile, expected_header, existing_header);
            return INIT_FAILED;
           }
        }
      FileClose(probe_handle);
     }

   g_file_handle = FileOpen(InpOutputFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI |
                             FILE_SHARE_READ, 0, CP_UTF8);
   if(g_file_handle == INVALID_HANDLE)
     {
      PrintFormat("EquityTickRecorder: could not open '%s' for writing (error=%d) -- refusing "
                  "to run.", InpOutputFile, GetLastError());
      return INIT_FAILED;
     }

   FileSeek(g_file_handle, 0, SEEK_END);
   if(!file_has_content)
     {
      uint header_written = FileWriteString(g_file_handle, EQUITY_TICK_CSV_HEADER);
      if(header_written != (uint)StringLen(EQUITY_TICK_CSV_HEADER))
        {
         PrintFormat("EquityTickRecorder: failed to write the CSV header to '%s' (wrote %u of "
                     "%d chars, error=%d) -- refusing to run with an unverified/incomplete "
                     "header.", InpOutputFile, header_written, StringLen(EQUITY_TICK_CSV_HEADER),
                     GetLastError());
         FileClose(g_file_handle);
         g_file_handle = INVALID_HANDLE;
         return INIT_FAILED;
        }
      FileFlush(g_file_handle);
     }

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
   datetime tick_server_time = TimeTradeServer();

   string line = StringFormat("%s,%s,%I64d,%I64d,%s,%.2f,%.2f\r\n", Iso8601Utc(tick_server_time),
                               Iso8601ServerLocal(tick_server_time), (long)g_run_id, login,
                               CsvQuoteField(server), equity, balance);
   // **Fixed, 2026-07-28 (Codex review finding, tenth round, P1 finding
   // 14):** the write's own result was previously discarded -- a partial/
   // failed write (disk full, permission change mid-run) silently produced
   // a truncated or missing row with no record of it having happened.
   uint written = FileWriteString(g_file_handle, line);
   if(written != (uint)StringLen(line))
      PrintFormat("EquityTickRecorder: CRITICAL -- write to '%s' incomplete (wrote %u of %d "
                  "chars, error=%d) -- this tick's own equity sample may be missing or "
                  "truncated.", InpOutputFile, written, StringLen(line), GetLastError());
   FileFlush(g_file_handle);
  }
