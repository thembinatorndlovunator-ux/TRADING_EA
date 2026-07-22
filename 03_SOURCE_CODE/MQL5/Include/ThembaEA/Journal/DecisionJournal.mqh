//+------------------------------------------------------------------+
//| DecisionJournal.mqh                                               |
//| Themba Adaptive Intraday Engine — Journal                          |
//|                                                                    |
//| Serializes and durably appends a trade decision record to a daily  |
//| JSON-lines journal file, on-disk contract EXACTLY matching the      |
//| repo-root `TRADE_DECISION_SCHEMA.json` (reconciled with            |
//| TASK-002_PHASE2_SPECIFICATION.md section 9 during TASK-002's own     |
//| cleanup pass — this module is the first real consumer of that       |
//| reconciliation).                                                    |
//|                                                                    |
//| Per section 9: "the trade journal (raw TradeDecision records) is    |
//| the single source of truth; the learning-bucket statistics are a    |
//| derived, recomputable view over the journal — never a separately-   |
//| mutated store that could drift from the journal's own record."      |
//| This module is that single source of truth. Deriving learning       |
//| statistics from it (LearningStatistics.mqh) is a later, separate    |
//| task.                                                                |
//|                                                                    |
//| Nested schema fields whose internal shape the schema leaves open    |
//| (`score_breakdown`, `targets`, `reasons_passed`, `reasons_rejected`) |
//| are accepted here as PRE-SERIALIZED JSON snippets supplied by the    |
//| caller — building those nested structures is the responsibility of  |
//| whichever module produces the underlying values (scoring, routing), |
//| once those modules exist. This module's job is assembling and       |
//| durably writing the top-level envelope, not generating every nested |
//| value — a deliberate, stated scope boundary for this task.          |
//+------------------------------------------------------------------+
#property strict

struct STradeDecision
  {
   string   signal_id;
   datetime timestamp;            // stored as a datetime; serialized as
                                   // ISO-8601 UTC via DJ_FormatIso8601Utc
   string   symbol;
   string   market_family;        // "METAL" | "SYNTHETIC"
   string   intraday_mode;        // "SCALP" | "DAY_TRADE"
   string   regime;
   double   regime_confidence;    // 0-100 (schema scale)
   string   direction;            // "BUY" | "SELL" | "NONE"
   string   strategy;
   string   setup;
   string   candlestick_pattern;  // "" serializes as JSON null
   string   chart_pattern;        // "" serializes as JSON null
   double   score;                // 0-100 (schema scale)
   string   score_breakdown_json; // pre-serialized JSON object, e.g. "{}"
   double   entry;
   bool     has_entry;            // false -> entry serializes as null
   double   stop;
   bool     has_stop;             // false -> stop serializes as null
   string   targets_json;         // pre-serialized JSON array, e.g. "[]"
   double   risk_percent;
   string   news_state;
   string   session_state;
   string   reasons_passed_json;   // pre-serialized JSON array of strings
   string   reasons_rejected_json; // pre-serialized JSON array of strings
   string   ea_version;
   string   git_commit;
   string   order_id;              // TASK-036: MT5's POSITION_IDENTIFIER
                                    // (SOrderOpenResult.position_id) — NEVER
                                    // position_ticket (see OrderManager.mqh's
                                    // own SOrderOpenResult comment). "" (JSON
                                    // null) for a decision that never reached
                                    // order submission or was rejected.
   string   deal_id;               // TASK-036: MT5's DEAL_TICKET
                                    // (SOrderOpenResult.deal_ticket). "" (JSON
                                    // null) under the same conditions as
                                    // order_id.
  };

//+------------------------------------------------------------------+
//| Returns a STradeDecision with every field at a safe, explicit       |
//| default (empty strings, has_entry/has_stop false, empty JSON         |
//| containers "{}"/"[]") so a caller only needs to set the fields it    |
//| actually has values for.                                            |
//+------------------------------------------------------------------+
STradeDecision DJ_NewDecision()
  {
   STradeDecision d;
   d.signal_id = "";
   d.timestamp = 0;
   d.symbol = "";
   d.market_family = "";
   d.intraday_mode = "";
   d.regime = "";
   d.regime_confidence = 0.0;
   d.direction = "NONE";
   d.strategy = "";
   d.setup = "";
   d.candlestick_pattern = "";
   d.chart_pattern = "";
   d.score = 0.0;
   d.score_breakdown_json = "{}";
   d.entry = 0.0;
   d.has_entry = false;
   d.stop = 0.0;
   d.has_stop = false;
   d.targets_json = "[]";
   d.risk_percent = 0.0;
   d.news_state = "";
   d.session_state = "";
   d.reasons_passed_json = "[]";
   d.reasons_rejected_json = "[]";
   d.ea_version = "";
   d.git_commit = "";
   d.order_id = "";
   d.deal_id = "";
   return d;
  }

//+------------------------------------------------------------------+
//| Minimal JSON string escaping — backslash, double-quote, and the     |
//| control characters this project's own generated strings could        |
//| plausibly contain (newline, carriage return, tab). Not a general-    |
//| purpose JSON library; sufficient for this project's own field         |
//| values (symbol names, enum-like strings, reason text), which do      |
//| not contain exotic Unicode edge cases in practice.                    |
//+------------------------------------------------------------------+
string DJ_JsonEscapeString(const string value)
  {
   string result = value;
   StringReplace(result, "\\", "\\\\");
   StringReplace(result, "\"", "\\\"");
   StringReplace(result, "\n", "\\n");
   StringReplace(result, "\r", "\\r");
   StringReplace(result, "\t", "\\t");
   return result;
  }

//+------------------------------------------------------------------+
//| ISO-8601 UTC timestamp string, e.g. "2026-07-21T14:05:30Z", per     |
//| TRADE_DECISION_SCHEMA.json's "timestamp_utc": "ISO-8601" field.      |
//+------------------------------------------------------------------+
string DJ_FormatIso8601Utc(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                        dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
  }

//+------------------------------------------------------------------+
//| Serializes a STradeDecision to exactly one JSON-object line,         |
//| field-for-field matching TRADE_DECISION_SCHEMA.json's key set and    |
//| null-handling ("number|null" fields serialize as JSON null when      |
//| has_entry/has_stop is false; "string|null" pattern fields serialize  |
//| as JSON null when empty).                                            |
//+------------------------------------------------------------------+
string DJ_SerializeDecision(const STradeDecision &d)
  {
   string entry_json = d.has_entry ? DoubleToString(d.entry, 8) : "null";
   string stop_json  = d.has_stop  ? DoubleToString(d.stop, 8)  : "null";
   string candle_json = (StringLen(d.candlestick_pattern) > 0)
                         ? ("\"" + DJ_JsonEscapeString(d.candlestick_pattern) + "\"")
                         : "null";
   string chart_json = (StringLen(d.chart_pattern) > 0)
                        ? ("\"" + DJ_JsonEscapeString(d.chart_pattern) + "\"")
                        : "null";
   string order_id_json = (StringLen(d.order_id) > 0)
                           ? ("\"" + DJ_JsonEscapeString(d.order_id) + "\"")
                           : "null";
   string deal_id_json = (StringLen(d.deal_id) > 0)
                          ? ("\"" + DJ_JsonEscapeString(d.deal_id) + "\"")
                          : "null";

   string json = "{";
   json += "\"signal_id\":\"" + DJ_JsonEscapeString(d.signal_id) + "\",";
   json += "\"timestamp_utc\":\"" + DJ_FormatIso8601Utc(d.timestamp) + "\",";
   json += "\"symbol\":\"" + DJ_JsonEscapeString(d.symbol) + "\",";
   json += "\"market_family\":\"" + DJ_JsonEscapeString(d.market_family) + "\",";
   json += "\"intraday_mode\":\"" + DJ_JsonEscapeString(d.intraday_mode) + "\",";
   json += "\"regime\":\"" + DJ_JsonEscapeString(d.regime) + "\",";
   json += "\"regime_confidence\":" + DoubleToString(d.regime_confidence, 4) + ",";
   json += "\"direction\":\"" + DJ_JsonEscapeString(d.direction) + "\",";
   json += "\"strategy\":\"" + DJ_JsonEscapeString(d.strategy) + "\",";
   json += "\"setup\":\"" + DJ_JsonEscapeString(d.setup) + "\",";
   json += "\"candlestick_pattern\":" + candle_json + ",";
   json += "\"chart_pattern\":" + chart_json + ",";
   json += "\"score\":" + DoubleToString(d.score, 4) + ",";
   json += "\"score_breakdown\":" + d.score_breakdown_json + ",";
   json += "\"entry\":" + entry_json + ",";
   json += "\"stop\":" + stop_json + ",";
   json += "\"targets\":" + d.targets_json + ",";
   json += "\"risk_percent\":" + DoubleToString(d.risk_percent, 6) + ",";
   json += "\"news_state\":\"" + DJ_JsonEscapeString(d.news_state) + "\",";
   json += "\"session_state\":\"" + DJ_JsonEscapeString(d.session_state) + "\",";
   json += "\"reasons_passed\":" + d.reasons_passed_json + ",";
   json += "\"reasons_rejected\":" + d.reasons_rejected_json + ",";
   json += "\"ea_version\":\"" + DJ_JsonEscapeString(d.ea_version) + "\",";
   json += "\"git_commit\":\"" + DJ_JsonEscapeString(d.git_commit) + "\",";
   json += "\"order_id\":" + order_id_json + ",";
   json += "\"deal_id\":" + deal_id_json;
   json += "}";
   return json;
  }

//+------------------------------------------------------------------+
//| The journal file path for a given UTC date — one file per day,       |
//| keeping any single file's size bounded rather than one unbounded     |
//| lifetime file. Relative to the terminal's own (non-common) MQL5      |
//| Files sandbox, per standard MQL5 file-I/O restrictions.               |
//+------------------------------------------------------------------+
string DJ_JournalFilePath(const datetime utc_date)
  {
   MqlDateTime dt;
   TimeToStruct(utc_date, dt);
   return StringFormat("ThembaEA\\Journal\\decisions_%04d%02d%02d.jsonl",
                        dt.year, dt.mon, dt.day);
  }

//+------------------------------------------------------------------+
//| Appends one serialized decision as a new line to the day's journal  |
//| file (identified by the decision's own timestamp), creating the      |
//| file and its directory if needed. Returns false (with 'error_reason' |
//| set) if the file could not be opened for append — a caller must       |
//| treat this as a logged failure, never a silent no-op, per              |
//| PROJECT_RULES.md rule 6.                                               |
//+------------------------------------------------------------------+
bool DJ_AppendDecision(const STradeDecision &d, string &error_reason)
  {
   error_reason = "";
   string path = DJ_JournalFilePath(d.timestamp);

   // TASK-036: FILE_ANSI's single-byte-per-character mode used the
   // terminal's default codepage (CP_ACP) here, which is NOT UTF-8 on most
   // Windows locales -- a latent cross-language mismatch against the
   // Python reader's utf-8-sig decode. MQL5's FileOpen accepts an explicit
   // codepage as its 4th argument; passing CP_UTF8 makes FILE_ANSI mode
   // encode/decode as real UTF-8 instead of the system codepage, fixing
   // the mismatch without switching to FILE_UNICODE (which would write
   // UTF-16LE with a BOM, a different on-disk contract entirely).
   int handle = FileOpen(path, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ,
                          0, CP_UTF8);
   if(handle == INVALID_HANDLE)
     {
      error_reason = StringFormat("file_open_failed_error_%d", GetLastError());
      return false;
     }

   FileSeek(handle, 0, SEEK_END);
   string line = DJ_SerializeDecision(d);
   FileWriteString(handle, line + "\r\n");
   FileClose(handle);
   return true;
  }
