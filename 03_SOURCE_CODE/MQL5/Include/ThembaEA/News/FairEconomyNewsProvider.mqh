//+------------------------------------------------------------------+
//| FairEconomyNewsProvider.mqh                                       |
//| Themba Adaptive Intraday Engine — News                            |
//|                                                                    |
//| TASK-034 — per the user's own 2026-07-21 specification             |
//| (TASK-034_LIVE_SAFETY_WIRING.md Specification item 4): high-impact     |
//| calendar events for NEWS_BLACKOUT are sourced from the FairEconomy       |
//| free JSON calendar widely used by MT5 news-filter EAs                     |
//| (nfs.faireconomy.net/ff_calendar_thisweek.json), parsed into                |
//| NewsManager.mqh's provider-agnostic SNewsEvent shape — same role as         |
//| MT5CalendarProvider.mqh, an alternate metals-oriented provider.               |
//|                                                                    |
//| **Terminal-settings prerequisite the user must set locally (cannot be  |
//| scripted from here): Tools -> Options -> Expert Advisors -> "Allow        |
//| WebRequest for listed URL" must include https://nfs.faireconomy.net —       |
//| WebRequest fails with no data otherwise. FEP_FetchLive treats that as         |
//| an ordinary fetch failure (return -1), which FEP_EnsureCache/                   |
//| FEP_IsInBlackoutNow then surface as feed_unavailable_out=true for the             |
//| caller to apply the fail-closed policy on.**                                        |
//|                                                                    |
//| **Stated, unverified assumption (flagged for the batched runtime-      |
//| verification backlog, same discipline as MT5CalendarProvider.mqh):         |
//| this file's JSON parser targets the specific flat-array-of-objects           |
//| shape ({"title","country","date","impact","forecast","previous",...})          |
//| this feed has historically used. These free community endpoints DO             |
//| drift; the exact field names/format must be re-verified against a live            |
//| response before this is ever relied on for a real trading decision.**              |
//|                                                                    |
//| Caching: FEP_EnsureCache fetches at most once per FEP_MIN_REFETCH_     |
//| SECONDS (session-scoped — "re-fetch once per session start, not          |
//| per-tick," per Specification item 4), with a multi-hour safety-net           |
//| refresh so a long-running unattended session does not trade all week           |
//| against a single stale snapshot. A failed fetch is retried on the very          |
//| next call (does not wait out the refresh interval), and fails CLOSED —           |
//| the caller must treat feed_unavailable_out=true as an active blackout,             |
//| never as "no blackout."                                                               |
//+------------------------------------------------------------------+
#property strict

#include "NewsManager.mqh"

#define FEP_FEED_URL "https://nfs.faireconomy.net/ff_calendar_thisweek.json"
#define FEP_MIN_REFETCH_SECONDS (4 * 3600)
#define FEP_BOTSWANA_UTC_OFFSET_SECONDS (2 * 3600)

//+------------------------------------------------------------------+
//| PARSING — pure, hand-testable against a captured feed sample.         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Splits a top-level JSON array of flat objects into per-object          |
//| substrings by brace-depth tracking. Assumes no '{'/'}' characters       |
//| occur inside a string field's own value — true of this feed's known      |
//| fields (plain-text titles/currencies/dates), a documented limitation        |
//| of this hand-rolled parser, not a general-purpose JSON library.               |
//+------------------------------------------------------------------+
int FEP_SplitObjects(const string json_text, string &objects_out[])
  {
   ArrayFree(objects_out);
   int depth = 0;
   int obj_start = -1;
   int len = StringLen(json_text);
   for(int i = 0; i < len; i++)
     {
      ushort ch = StringGetCharacter(json_text, i);
      if(ch == '{')
        {
         if(depth == 0)
            obj_start = i;
         depth++;
        }
      else if(ch == '}')
        {
         depth--;
         if(depth == 0 && obj_start >= 0)
           {
            int n = ArraySize(objects_out);
            ArrayResize(objects_out, n + 1);
            objects_out[n] = StringSubstr(json_text, obj_start, i - obj_start + 1);
            obj_start = -1;
           }
        }
     }
   return ArraySize(objects_out);
  }

//+------------------------------------------------------------------+
//| Extracts a "key":"value" JSON string field from a single flat object   |
//| substring. Returns "" if the key is absent. Does not unescape or          |
//| handle escaped quotes inside the value — not needed for this feed's         |
//| known plain-text fields.                                                       |
//+------------------------------------------------------------------+
string FEP_ExtractStringField(const string obj, const string key)
  {
   string needle = "\"" + key + "\"";
   int key_pos = StringFind(obj, needle);
   if(key_pos < 0)
      return "";
   int colon_pos = StringFind(obj, ":", key_pos + StringLen(needle));
   if(colon_pos < 0)
      return "";
   int quote_start = StringFind(obj, "\"", colon_pos + 1);
   if(quote_start < 0)
      return "";
   int quote_end = StringFind(obj, "\"", quote_start + 1);
   if(quote_end < 0)
      return "";
   return StringSubstr(obj, quote_start + 1, quote_end - quote_start - 1);
  }

//+------------------------------------------------------------------+
//| Maps FairEconomy's "impact" string to the same 0-3 ordinal scale       |
//| MT5CalendarProvider.mqh uses (ENUM_CALENDAR_EVENT_IMPORTANCE cast:         |
//| none=0, low=1, moderate=2, high=3) so NewsManager.mqh's                       |
//| min_importance filter behaves identically regardless of which provider          |
//| supplied the event.                                                                 |
//+------------------------------------------------------------------+
int FEP_MapImpact(const string impact)
  {
   string s = impact;
   StringToLower(s);
   if(s == "high")
      return 3;
   if(s == "medium")
      return 2;
   if(s == "low")
      return 1;
   return 0; // "holiday", "non-economic", empty, or unrecognized
  }

//+------------------------------------------------------------------+
//| Best-effort, lenient numeric parse for forecast/previous strings        |
//| (e.g. "1.2%", "-0.3", ""). Not safety-critical — these fields are          |
//| informational only; NewsManager.mqh's blackout predicate never reads         |
//| them. Returns 0.0 on anything it cannot confidently parse, rather than         |
//| guessing at unit suffixes ("%", "K", "M", "B").                                   |
//+------------------------------------------------------------------+
double FEP_ParseLenientDouble(const string raw)
  {
   string s = raw;
   StringTrimLeft(s);
   StringTrimRight(s);
   if(s == "")
      return 0.0;

   string cleaned = "";
   bool seen_dot = false;
   int len = StringLen(s);
   for(int i = 0; i < len; i++)
     {
      ushort ch = StringGetCharacter(s, i);
      if(i == 0 && (ch == '-' || ch == '+'))
        {
         cleaned += StringSubstr(s, i, 1);
         continue;
        }
      if(ch >= '0' && ch <= '9')
        {
         cleaned += StringSubstr(s, i, 1);
         continue;
        }
      if(ch == '.' && !seen_dot)
        {
         seen_dot = true;
         cleaned += ".";
         continue;
        }
      break; // stop at the first non-numeric character (e.g. '%', 'K')
     }
   if(cleaned == "" || cleaned == "-" || cleaned == "+")
      return 0.0;
   return StringToDouble(cleaned);
  }

//+------------------------------------------------------------------+
//| Parses "YYYY-MM-DDTHH:MM:SS±HH:MM" (or a "Z"/absent suffix, meaning     |
//| UTC) into a UTC datetime. 'ok_out' is false if 'iso' is too short to       |
//| contain at least the date+time portion — the caller must skip that          |
//| event rather than guess its scheduled time.                                     |
//+------------------------------------------------------------------+
datetime FEP_ParseIso8601ToUtc(const string iso, bool &ok_out)
  {
   ok_out = false;
   if(StringLen(iso) < 19)
      return 0;

   string date_part = StringSubstr(iso, 0, 10); // YYYY-MM-DD
   string time_part = StringSubstr(iso, 11, 8); // HH:MM:SS
   string date_dotted = date_part;
   StringReplace(date_dotted, "-", ".");

   datetime as_if_utc = StringToTime(date_dotted + " " + time_part);
   if(as_if_utc == 0)
      return 0;

   int offset_seconds = 0;
   if(StringLen(iso) > 19)
     {
      string tz = StringSubstr(iso, 19);
      if(tz != "" && tz != "Z")
        {
         int sign = (StringGetCharacter(tz, 0) == '-') ? -1 : 1;
         string hh = StringSubstr(tz, 1, 2);
         string mm = (StringLen(tz) >= 6) ? StringSubstr(tz, 4, 2) : "00";
         offset_seconds = sign * ((int)StringToInteger(hh) * 3600 + (int)StringToInteger(mm) * 60);
        }
     }

   ok_out = true;
   return as_if_utc - offset_seconds;
  }

//+------------------------------------------------------------------+
//| Parses a full feed response body into the provider-agnostic            |
//| SNewsEvent[] shape. Pure — no network access — hand-testable against      |
//| a captured feed sample. Skips (rather than guesses) any object            |
//| missing a parseable "date" field.                                             |
//+------------------------------------------------------------------+
int FEP_ParseFeedJson(const string json_text, SNewsEvent &events_out[])
  {
   ArrayFree(events_out);
   string objects[];
   int total = FEP_SplitObjects(json_text, objects);

   datetime now_utc = TimeGMT();
   int server_gmt_offset_seconds = (int)(TimeTradeServer() - TimeGMT());
   int count = 0;

   for(int i = 0; i < total; i++)
     {
      string title = FEP_ExtractStringField(objects[i], "title");
      string country = FEP_ExtractStringField(objects[i], "country");
      string date_str = FEP_ExtractStringField(objects[i], "date");
      string impact = FEP_ExtractStringField(objects[i], "impact");
      string forecast_str = FEP_ExtractStringField(objects[i], "forecast");
      string previous_str = FEP_ExtractStringField(objects[i], "previous");

      if(date_str == "")
         continue;

      bool parsed_ok;
      datetime scheduled_utc = FEP_ParseIso8601ToUtc(date_str, parsed_ok);
      if(!parsed_ok)
         continue;

      int n = ArraySize(events_out);
      ArrayResize(events_out, n + 1);
      events_out[n] = NM_NewEvent();
      events_out[n].event_id = title + "_" + country + "_" + IntegerToString((long)scheduled_utc);
      events_out[n].event_name = title;
      events_out[n].currency = country;
      events_out[n].importance = FEP_MapImpact(impact);
      events_out[n].scheduled_utc = scheduled_utc;
      events_out[n].scheduled_server_time = scheduled_utc + server_gmt_offset_seconds;
      events_out[n].scheduled_botswana_time = scheduled_utc + FEP_BOTSWANA_UTC_OFFSET_SECONDS;
      events_out[n].previous = FEP_ParseLenientDouble(previous_str);
      events_out[n].forecast = FEP_ParseLenientDouble(forecast_str);
      events_out[n].actual = 0.0; // this feed does not reliably expose actuals pre-release
      events_out[n].revision = 0.0;
      events_out[n].source = "FAIRECONOMY";
      events_out[n].retrieved_at = now_utc;
      events_out[n].status = (scheduled_utc <= now_utc) ? NEWS_STATUS_RELEASED : NEWS_STATUS_SCHEDULED;
      count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| LIVE FETCH + SESSION CACHE                                          |
//+------------------------------------------------------------------+
SNewsEvent g_fep_cached_events[];
bool       g_fep_cache_valid = false;
datetime   g_fep_last_fetch_time = 0;

//+------------------------------------------------------------------+
//| Fetches the live feed via WebRequest and parses it. Returns the       |
//| event count (>= 0) on success, -1 on any transport/HTTP failure —         |
//| caller must treat -1 as "provider unavailable," matching                     |
//| MTC_FetchEvents's own -1 convention.                                            |
//+------------------------------------------------------------------+
int FEP_FetchLive(SNewsEvent &events_out[])
  {
   ArrayFree(events_out);

   char post[];
   char result[];
   string result_headers;

   ResetLastError();
   int http_code = WebRequest("GET", FEP_FEED_URL, "", "", 5000, post, 0, result, result_headers);
   if(http_code != 200)
     {
      PrintFormat("FairEconomyNewsProvider: WebRequest to '%s' failed (http_code=%d, "
                  "GetLastError=%d) -- treating as a provider failure; the caller applies the "
                  "fail-closed policy.", FEP_FEED_URL, http_code, GetLastError());
      return -1;
     }

   string json_text = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   return FEP_ParseFeedJson(json_text, events_out);
  }

//+------------------------------------------------------------------+
//| Clears the session cache — call at OnInit so each new session          |
//| refetches rather than reusing a previous run's (or test's) data.          |
//+------------------------------------------------------------------+
void FEP_InvalidateCache()
  {
   g_fep_cache_valid = false;
   g_fep_last_fetch_time = 0;
   ArrayFree(g_fep_cached_events);
  }

//+------------------------------------------------------------------+
//| Ensures the session cache is populated and not older than              |
//| FEP_MIN_REFETCH_SECONDS. Returns false if the cache could not be           |
//| populated (fetch failed and there is no usable prior cache) — a               |
//| failed fetch does NOT update the cache timestamp, so the very next            |
//| call retries immediately rather than waiting out the refresh interval.          |
//+------------------------------------------------------------------+
bool FEP_EnsureCache(const datetime now)
  {
   if(g_fep_cache_valid && (now - g_fep_last_fetch_time) < FEP_MIN_REFETCH_SECONDS)
      return true;

   SNewsEvent fetched[];
   int result = FEP_FetchLive(fetched);
   if(result < 0)
      return false; // fail closed -- caller treats this as an active blackout

   ArrayFree(g_fep_cached_events);
   int n = ArraySize(fetched);
   ArrayResize(g_fep_cached_events, n);
   for(int i = 0; i < n; i++)
      g_fep_cached_events[i] = fetched[i];

   g_fep_cache_valid = true;
   g_fep_last_fetch_time = now;
   return true;
  }

//+------------------------------------------------------------------+
//| LIVE WRAPPER — mirrors MT5CalendarProvider.mqh's MTC_IsInBlackoutNow.  |
//| 'feed_unavailable_out' is true whenever the cache could not be            |
//| populated; the return value is only meaningful (false = genuinely no        |
//| blackout) when feed_unavailable_out is false. The caller must apply           |
//| the fail-closed policy — treat feed_unavailable_out=true as an active           |
//| blackout — never treat this function's false return as "safe to               |
//| trade" without checking feed_unavailable_out first.                                |
//+------------------------------------------------------------------+
bool FEP_IsInBlackoutNow(const string symbol, const string currency, const int min_importance,
                          const int before_minutes, const int after_minutes,
                          const int max_extension_minutes, const double max_spread_atr_multiple,
                          const double current_atr, string &triggering_event_id,
                          bool &feed_unavailable_out)
  {
   triggering_event_id = "";
   datetime now_utc = TimeGMT();

   if(!FEP_EnsureCache(now_utc))
     {
      feed_unavailable_out = true;
      return false;
     }
   feed_unavailable_out = false;

   SNewsEvent filtered[];
   for(int i = 0; i < ArraySize(g_fep_cached_events); i++)
     {
      if(currency != "" && g_fep_cached_events[i].currency != currency)
         continue;
      int m = ArraySize(filtered);
      ArrayResize(filtered, m + 1);
      filtered[m] = g_fep_cached_events[i];
     }

   double current_spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) *
                            SymbolInfoDouble(symbol, SYMBOL_POINT);
   datetime server_now = TimeTradeServer();

   return NM_IsInBlackoutWindowExtended(filtered, server_now, before_minutes, after_minutes,
                                         max_extension_minutes, min_importance, current_spread,
                                         current_atr, max_spread_atr_multiple, triggering_event_id);
  }
