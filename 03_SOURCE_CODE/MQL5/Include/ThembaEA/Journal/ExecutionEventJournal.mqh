//+------------------------------------------------------------------+
//| ExecutionEventJournal.mqh                                         |
//| Themba Adaptive Intraday Engine — Journal                          |
//|                                                                    |
//| **Added, 2026-07-27 (Codex review finding, ninth round, P1 finding      |
//| 9):** a genuinely separate, append-only execution-event journal,         |
//| distinct from DecisionJournal.mqh's own STradeDecision record — the       |
//| "genuine, named follow-up" that round-7's own P0 finding 2 fix                |
//| explicitly deferred (see LogAsyncFillResolution's own prior header,          |
//| ThembaAdaptiveIntradayEA.mq5). An async fill/cancel outcome previously          |
//| only reached the Experts log via Print — never a journal row of any               |
//| kind — leaving the original PLACED decision's own order_id/deal_id                    |
//| permanently null with no other machine-readable evidence the fill (or                   |
//| cancellation) ever happened. Kept append-only, matching                                     |
//| DecisionJournal.mqh's own stated durability design (never rewriting an                        |
//| existing JSONL line in place), one JSON object per line, one file per                             |
//| UTC day.                                                                                             |
//|                                                                    |
//| This ALSO closes the review's second complaint ("a crash after broker    |
//| accepted and before the original journal append also still leaves        |
//| exposure with no journal row"): an execution event is independently       |
//| useful evidence keyed by signal_id/intent_id/order_id/deal_id even if     |
//| the original decision's own DJ_AppendDecision call never ran (or          |
//| hasn't run yet) — it does not depend on that earlier journal write        |
//| having succeeded.                                                        |
//+------------------------------------------------------------------+
#property strict

#include "DecisionJournal.mqh" // reuses DJ_JsonEscapeString/DJ_ServerTimeToUtc/DJ_FormatIso8601Utc

struct SExecutionEvent
  {
   string   event_id;      // unique per event, "EV<timestamp>_<micro>"
   string   event_type;    // "SYNC_FILL" | "SYNC_FILL_LIVE_REMAINDER" | "SYNC_FILL_UNRESOLVED" |
                            // "ASYNC_FILL_CONFIRMED" | "ASYNC_FILL_LIVE_REMAINDER" |
                            // "ASYNC_PARTIAL_FILL_THEN_CANCELLED" | "ASYNC_NEVER_FILLED" --
                            // see EXECUTION_EVENT_SCHEMA.json for the authoritative enum
   string   signal_id;     // "" -> null; the original decision's causal key, when known
   string   intent_id;     // "" -> null; IntentManager's own durable-intent ID
   string   order_id;      // "" -> null; MT5 POSITION_IDENTIFIER as string (never
                            // position_ticket — matches STradeDecision.order_id's own contract)
   ulong    order_ticket;  // MT5 order ticket this event resolves, 0 if not applicable
   string   deal_id;       // "" -> null; MT5 DEAL_TICKET as string, only when a specific
                            // fill deal is known at the call site (left "" otherwise —
                            // never fabricated)
   datetime timestamp;     // server-clock event time; serialized via DJ_ServerTimeToUtc +
                            // DJ_FormatIso8601Utc, same convention as DecisionJournal.mqh
   string   symbol;
   bool     filled;        // true iff real exposure resulted from this event
   double   volume;
   bool     has_volume;
   double   price;
   bool     has_price;
   string   outcome_note;  // free-text detail, e.g. "async_fill_confirmed"
  };

//+------------------------------------------------------------------+
//| Returns an SExecutionEvent with every field at a safe, explicit      |
//| default — mirrors DecisionJournal.mqh's own DJ_NewDecision().         |
//+------------------------------------------------------------------+
SExecutionEvent EEJ_NewEvent()
  {
   SExecutionEvent e;
   e.event_id = "";
   e.event_type = "";
   e.signal_id = "";
   e.intent_id = "";
   e.order_id = "";
   e.order_ticket = 0;
   e.deal_id = "";
   e.timestamp = 0;
   e.symbol = "";
   e.filled = false;
   e.volume = 0.0;
   e.has_volume = false;
   e.price = 0.0;
   e.has_price = false;
   e.outcome_note = "";
   return e;
  }

//+------------------------------------------------------------------+
//| Builds a unique event_id from the current server time plus MT5's     |
//| own microsecond counter — same collision-avoidance approach as        |
//| IntentManager.mqh's own IM_BuildIntentId (a bare microsecond count      |
//| alone resets across a terminal restart).                                 |
//+------------------------------------------------------------------+
string EEJ_BuildEventId(const datetime event_time, const long micro)
  {
   return StringFormat("EV%.0f_%d", (double)event_time, micro);
  }

//+------------------------------------------------------------------+
//| Serializes an SExecutionEvent to exactly one JSON-object line,        |
//| field-for-field matching EXECUTION_EVENT_SCHEMA.json's key set.        |
//+------------------------------------------------------------------+
string EEJ_SerializeEvent(const SExecutionEvent &e)
  {
   string signal_json = (StringLen(e.signal_id) > 0)
                         ? ("\"" + DJ_JsonEscapeString(e.signal_id) + "\"") : "null";
   string intent_json  = (StringLen(e.intent_id) > 0)
                         ? ("\"" + DJ_JsonEscapeString(e.intent_id) + "\"") : "null";
   string order_json   = (StringLen(e.order_id) > 0)
                         ? ("\"" + DJ_JsonEscapeString(e.order_id) + "\"") : "null";
   string deal_json    = (StringLen(e.deal_id) > 0)
                         ? ("\"" + DJ_JsonEscapeString(e.deal_id) + "\"") : "null";
   string volume_json  = e.has_volume ? DoubleToString(e.volume, 2) : "null";
   string price_json   = e.has_price  ? DoubleToString(e.price, 8)  : "null";

   string json = "{";
   json += "\"event_id\":\"" + DJ_JsonEscapeString(e.event_id) + "\",";
   json += "\"event_type\":\"" + DJ_JsonEscapeString(e.event_type) + "\",";
   json += "\"signal_id\":" + signal_json + ",";
   json += "\"intent_id\":" + intent_json + ",";
   json += "\"order_id\":" + order_json + ",";
   json += "\"order_ticket\":" + IntegerToString((long)e.order_ticket) + ",";
   json += "\"deal_id\":" + deal_json + ",";
   json += "\"timestamp_utc\":\"" + DJ_FormatIso8601Utc(e.timestamp) + "\",";
   json += "\"symbol\":\"" + DJ_JsonEscapeString(e.symbol) + "\",";
   json += "\"filled\":" + (e.filled ? "true" : "false") + ",";
   json += "\"volume\":" + volume_json + ",";
   json += "\"price\":" + price_json + ",";
   json += "\"outcome_note\":\"" + DJ_JsonEscapeString(e.outcome_note) + "\"";
   json += "}";
   return json;
  }

//+------------------------------------------------------------------+
//| The journal file path for a given UTC date — one file per day,        |
//| separate from DecisionJournal.mqh's own decisions_*.jsonl files.        |
//+------------------------------------------------------------------+
string EEJ_JournalFilePath(const datetime utc_date)
  {
   MqlDateTime dt;
   TimeToStruct(utc_date, dt);
   return StringFormat("ThembaEA\\Journal\\execution_events_%04d%02d%02d.jsonl",
                        dt.year, dt.mon, dt.day);
  }

//+------------------------------------------------------------------+
//| Appends one serialized event as a new line to the day's journal      |
//| file, creating the file/directory if needed. Same bounded-retry,      |
//| UTF-8, write-length-verified append as DecisionJournal.mqh's own       |
//| DJ_AppendDecision — see that function's own header for why each of      |
//| these choices (FILE_SHARE_READ-only, CP_UTF8, retry budget, checked      |
//| FileWriteString return) matters.                                          |
//+------------------------------------------------------------------+
bool EEJ_AppendEvent(const SExecutionEvent &e, string &error_reason)
  {
   error_reason = "";
   string path = EEJ_JournalFilePath(e.timestamp);

   const int max_attempts = 20;
   const int retry_delay_ms = 15;
   int handle = INVALID_HANDLE;
   for(int attempt = 0; attempt < max_attempts; attempt++)
     {
      handle = FileOpen(path, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ,
                         0, CP_UTF8);
      if(handle != INVALID_HANDLE)
         break;
      Sleep(retry_delay_ms);
     }
   if(handle == INVALID_HANDLE)
     {
      error_reason = StringFormat("file_open_failed_after_%d_attempts_error_%d", max_attempts,
                                   GetLastError());
      return false;
     }

   FileSeek(handle, 0, SEEK_END);
   string line = EEJ_SerializeEvent(e);
   string payload = line + "\r\n";
   uint written = FileWriteString(handle, payload);
   int write_error = (written != (uint)StringLen(payload)) ? GetLastError() : 0;
   FileClose(handle);
   if(written != (uint)StringLen(payload))
     {
      error_reason = StringFormat("file_write_incomplete_wrote_%u_of_%d_chars_error_%d",
                                   written, StringLen(payload), write_error);
      return false;
     }
   return true;
  }
