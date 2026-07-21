//+------------------------------------------------------------------+
//| MT5CalendarProvider.mqh                                           |
//| Themba Adaptive Intraday Engine — News                            |
//|                                                                    |
//| Per NEWS_INTEGRATION_SPEC.md: "Metals: MT5 Economic Calendar is the  |
//| primary structured live source." Wraps MQL5's native                   |
//| CalendarValueHistory/CalendarEventById/CalendarCountryById into the       |
//| provider-agnostic SNewsEvent shape NewsManager.mqh defines.                 |
//|                                                                    |
//| **Stated, unverified assumption (flagged for the batched runtime-      |
//| verification backlog, same discipline as every live-symbol wrapper       |
//| in this project):** MqlCalendarValue.time is assumed to be expressed       |
//| in UTC per MQL5's own Calendar-function documentation (unlike bar/tick        |
//| timestamps elsewhere in this project, which are broker server time) —          |
//| this has not been independently confirmed against a live feed in this            |
//| sandboxed session.                                                                 |
//|                                                                    |
//| The historical CSV/SQLite deterministic-backtest provider           |
//| NEWS_INTEGRATION_SPEC.md also requires ("Backtesting: store historical  |
//| events in SQLite or CSV... repeated tests must produce identical event    |
//| decisions") is NOT built here — a separate, larger task (needs an actual     |
//| historical event store that does not exist yet), explicitly deferred, not      |
//| silently dropped. See TASK-029_NEWS_MANAGER.md's Scope Boundary section.          |
//+------------------------------------------------------------------+
#property strict

#include "NewsManager.mqh"

//+------------------------------------------------------------------+
//| Botswana offset — UTC+2 (Central Africa Time), no daylight saving.   |
//| Stated project-wide assumption; no project document specifies an       |
//| explicit offset value, so this is this task's own documented choice.     |
//+------------------------------------------------------------------+
#define MTC_BOTSWANA_UTC_OFFSET_SECONDS (2 * 3600)

//+------------------------------------------------------------------+
//| Decodes a Calendar fixed-point long value to a double using the      |
//| event's own 'digits' field, per MQL5's Calendar-value encoding —        |
//| returns 0.0 for the (common) case of an event with no numeric value      |
//| yet (e.g. a not-yet-released actual_value).                                |
//+------------------------------------------------------------------+
double MTC_DecodeValue(const long raw, const uint digits)
  {
   if(raw == LONG_MIN) // MQL5's documented "value not available" sentinel
      return 0.0;
   double scale = MathPow(10.0, (double)digits);
   if(scale <= 0.0)
      return 0.0;
   return (double)raw / scale;
  }

//+------------------------------------------------------------------+
//| Fetches events for 'currency_code' (empty = all currencies) between   |
//| 'from_utc'/'to_utc', filtered to importance >= 'min_importance',         |
//| mapped into the provider-agnostic SNewsEvent shape. Returns the           |
//| number of events found (0 on no matches, -1 on a provider failure —        |
//| a caller must treat -1 as "provider unavailable," per                        |
//| NEWS_INTEGRATION_SPEC.md's "provider failure uses the configured               |
//| fail-safe policy and is logged" — the fail-safe POLICY itself (e.g.             |
//| fail-closed and block all metal entries) is this function's caller's               |
//| responsibility, not this function's, matching this project's "one                  |
//| implementation per concept" discipline.                                              |
//+------------------------------------------------------------------+
int MTC_FetchEvents(const string currency_code, const int min_importance,
                     const datetime from_utc, const datetime to_utc, SNewsEvent &events[])
  {
   ArrayFree(events);

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from_utc, to_utc, NULL, currency_code);
   if(total < 0)
      return -1;
   if(total == 0)
      return 0;

   int server_gmt_offset_seconds = (int)(TimeTradeServer() - TimeGMT());
   datetime now_utc = TimeGMT();

   int count = 0;
   for(int i = 0; i < total; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev))
         continue; // event definition unavailable — skip rather than guess

      if((int)ev.importance < min_importance)
         continue;

      string currency = currency_code;
      if(currency == "")
        {
         MqlCalendarCountry country;
         if(CalendarCountryById(ev.country_id, country))
            currency = country.currency;
        }

      int n = ArraySize(events);
      ArrayResize(events, n + 1);
      events[n] = NM_NewEvent();
      events[n].event_id = IntegerToString((long)values[i].event_id);
      events[n].event_name = ev.name;
      events[n].currency = currency;
      events[n].importance = (int)ev.importance;
      events[n].scheduled_utc = values[i].time;
      events[n].scheduled_server_time = values[i].time + server_gmt_offset_seconds;
      events[n].scheduled_botswana_time = values[i].time + MTC_BOTSWANA_UTC_OFFSET_SECONDS;
      events[n].previous = MTC_DecodeValue(values[i].prev_value, ev.digits);
      events[n].forecast = MTC_DecodeValue(values[i].forecast_value, ev.digits);
      events[n].actual = MTC_DecodeValue(values[i].actual_value, ev.digits);
      events[n].revision = (double)values[i].revision;
      events[n].source = "MT5_CALENDAR";
      events[n].retrieved_at = now_utc;
      events[n].status = (values[i].time <= now_utc) ? NEWS_STATUS_RELEASED : NEWS_STATUS_SCHEDULED;
      count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| LIVE WRAPPER — mirrors every other detection engine's "array-based    |
//| core + live wrapper" split: fetches a bounded look-around window of     |
//| events for 'currency', then evaluates NewsManager.mqh's (possibly         |
//| spread-extended) blackout predicate against them for the CURRENT             |
//| server time and CURRENT spread/ATR.                                             |
//+------------------------------------------------------------------+
bool MTC_IsInBlackoutNow(const string symbol, const string currency, const int min_importance,
                          const int before_minutes, const int after_minutes,
                          const int max_extension_minutes, const double max_spread_atr_multiple,
                          const double current_atr, string &triggering_event_id, int &fetch_result)
  {
   triggering_event_id = "";

   datetime now_utc = TimeGMT();
   // Look back far enough to catch an event whose nominal+extended window
   // might still be open, and ahead far enough to catch one whose
   // before-window has already started.
   datetime from_utc = now_utc - (datetime)(after_minutes + max_extension_minutes + 60) * 60;
   datetime to_utc   = now_utc + (datetime)(before_minutes + 60) * 60;

   SNewsEvent events[];
   fetch_result = MTC_FetchEvents(currency, min_importance, from_utc, to_utc, events);
   if(fetch_result <= 0)
      return false; // no events (0) or provider failure (-1) — caller applies fail-safe policy

   double current_spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) *
                            SymbolInfoDouble(symbol, SYMBOL_POINT);
   datetime server_now = TimeTradeServer();

   return NM_IsInBlackoutWindowExtended(events, server_now, before_minutes, after_minutes,
                                         max_extension_minutes, min_importance, current_spread,
                                         current_atr, max_spread_atr_multiple, triggering_event_id);
  }
