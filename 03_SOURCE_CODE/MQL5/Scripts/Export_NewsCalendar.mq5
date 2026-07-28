//+------------------------------------------------------------------+
//| Export_NewsCalendar.mq5                                           |
//| Themba Adaptive Intraday Engine — TASK-037 real-data export tool   |
//|                                                                    |
//| Fetches real economic-calendar events via MT5CalendarProvider.mqh's   |
//| own MTC_FetchEvents (the EXACT same MQL5 code path                     |
//| FairEconomyNewsProvider.mqh's sibling live provider uses -- not a         |
//| reimplementation, per this task's own Risks section) and writes            |
//| news_events.csv in the schema analysis/join_news_events.py documents:         |
//| event_id, event_name, currency, importance, scheduled_utc.                       |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/News/MT5CalendarProvider.mqh"

input datetime InpFromDate      = D'2020.01.01 00:00:00';
input datetime InpToDate        = 0; // 0 = now
input string   InpCurrencyCode  = ""; // "" = every currency
input int      InpMinImportance = 0; // 0 = every importance level
input string   InpOutputFile    = "ThembaEA\\Export\\news_events.csv";

string Iso8601Utc(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ", dt.year, dt.mon, dt.day, dt.hour, dt.min,
                        dt.sec);
  }

void OnStart()
  {
   Print("=== TASK-037 Export_NewsCalendar start ===");

   datetime to_date = (InpToDate == 0) ? TimeCurrent() : InpToDate;

   SNewsEvent events[];
   int result = MTC_FetchEvents(InpCurrencyCode, InpMinImportance, InpFromDate, to_date, events);
   if(result < 0)
     {
      PrintFormat("ABORT: MTC_FetchEvents failed (result=%d) -- MT5's Calendar service may be "
                  "unavailable in this terminal/environment.", result);
      return;
     }

   int handle = FileOpen(InpOutputFile, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ, 0,
                          CP_UTF8);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("ABORT: could not open '%s' for writing (error=%d).", InpOutputFile,
                  GetLastError());
      return;
     }

   FileWriteString(handle, "event_id,event_name,currency,importance,scheduled_utc\r\n");

   for(int i = 0; i < ArraySize(events); i++)
     {
      // event_name may itself contain a comma -- wrap in double quotes,
      // escaping any embedded quote per standard CSV convention.
      string escaped_name = events[i].event_name;
      StringReplace(escaped_name, "\"", "\"\"");
      string line = StringFormat("%s,\"%s\",%s,%d,%s\r\n", events[i].event_id, escaped_name,
                                  events[i].currency, events[i].importance,
                                  Iso8601Utc(events[i].scheduled_utc));
      FileWriteString(handle, line);
     }

   FileClose(handle);
   PrintFormat("=== TASK-037 Export_NewsCalendar complete: %d event(s) written to '%s' ===",
               ArraySize(events), InpOutputFile);
  }
