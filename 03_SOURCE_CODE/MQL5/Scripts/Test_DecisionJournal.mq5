//+------------------------------------------------------------------+
//| Test_DecisionJournal.mq5                                          |
//| Themba Adaptive Intraday Engine — TASK-009 compile/logic test      |
//|                                                                    |
//| Exercises escaping, ISO-8601 formatting, envelope serialization      |
//| (including null-handling for optional fields), and a real durable   |
//| append-then-read-back round trip. The test journal file is deleted   |
//| at the end so a real run leaves no residue.                          |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Journal/DecisionJournal.mqh"

int g_pass = 0;
int g_fail = 0;

void Check(const string label, const bool condition)
  {
   if(condition)
     {
      PrintFormat("PASS: %s", label);
      g_pass++;
     }
   else
     {
      PrintFormat("FAIL: %s", label);
      g_fail++;
     }
  }

bool Contains(const string haystack, const string needle)
  {
   return StringFind(haystack, needle) >= 0;
  }

void OnStart()
  {
   Print("=== TASK-009 DecisionJournal test start ===");

   //--- 1. Defaults -----------------------------------------------------
   STradeDecision d = DJ_NewDecision();
   Check("new decision defaults direction to NONE", d.direction == "NONE");
   Check("new decision defaults has_entry to false", d.has_entry == false);
   Check("new decision defaults has_stop to false", d.has_stop == false);
   Check("new decision defaults score_breakdown_json to {}",
         d.score_breakdown_json == "{}");
   Check("new decision defaults targets_json to []", d.targets_json == "[]");

   //--- 2. JSON string escaping ------------------------------------------
   string raw = "He said \"hi\"\\ and left\na newline";
   string escaped = DJ_JsonEscapeString(raw);
   Check("escaping handles embedded double-quotes",
         Contains(escaped, "\\\"hi\\\""));
   Check("escaping handles embedded backslash",
         Contains(escaped, "\\\\"));
   Check("escaping handles embedded newline",
         Contains(escaped, "\\n") && !Contains(escaped, "\nand"));

   //--- 3. ISO-8601 UTC formatting ---------------------------------------
   MqlDateTime known_dt;
   known_dt.year = 2026; known_dt.mon = 7; known_dt.day = 21;
   known_dt.hour = 14; known_dt.min = 5; known_dt.sec = 30;
   known_dt.day_of_week = 0; known_dt.day_of_year = 0;
   datetime known_time = StructToTime(known_dt);
   string iso = DJ_FormatIso8601Utc(known_time);
   Check("ISO-8601 formatting produces the exact expected string",
         iso == "2026-07-21T14:05:30Z");

   //--- 4. Full envelope serialization, including null-handling ----------
   STradeDecision full = DJ_NewDecision();
   full.signal_id = "test-signal-001";
   full.timestamp = known_time;
   full.symbol = "EURUSD";
   full.market_family = "METAL";
   full.intraday_mode = "SCALP";
   full.regime = "TRENDING_UP";
   full.regime_confidence = 87.5;
   full.direction = "BUY";
   full.strategy = "TrendFollowing";
   full.setup = "OB_retest";
   full.score = 72.25;
   full.entry = 1.23456;
   full.has_entry = true;
   // stop deliberately left unset (has_stop == false) to test null-handling
   full.targets_json = "[1.24000,1.25000]";
   full.risk_percent = 0.25;
   full.news_state = "CLEAR";
   full.session_state = "OPEN";
   full.reasons_passed_json = "[\"regime_aligned\"]";
   full.reasons_rejected_json = "[]";
   full.ea_version = "0.1.0-task009";
   full.git_commit = "unknown";

   string json = DJ_SerializeDecision(full);
   PrintFormat("INFO: serialized decision = %s", json);

   Check("serialized JSON contains signal_id", Contains(json, "\"signal_id\":\"test-signal-001\""));
   Check("serialized JSON contains correct timestamp_utc",
         Contains(json, "\"timestamp_utc\":\"2026-07-21T14:05:30Z\""));
   Check("serialized JSON contains symbol", Contains(json, "\"symbol\":\"EURUSD\""));
   Check("serialized JSON contains market_family", Contains(json, "\"market_family\":\"METAL\""));
   Check("serialized JSON contains direction BUY", Contains(json, "\"direction\":\"BUY\""));
   Check("serialized JSON has a numeric entry (has_entry=true)",
         Contains(json, "\"entry\":1.23456"));
   Check("serialized JSON has stop as null (has_stop=false)",
         Contains(json, "\"stop\":null"));
   Check("serialized JSON has candlestick_pattern as null (empty string)",
         Contains(json, "\"candlestick_pattern\":null"));
   Check("serialized JSON embeds the targets array verbatim",
         Contains(json, "\"targets\":[1.24000,1.25000]"));
   Check("serialized JSON is a single well-formed brace pair",
         StringGetCharacter(json, 0) == '{' &&
         StringGetCharacter(json, StringLen(json) - 1) == '}');

   //--- 5. Journal file path format ---------------------------------------
   string path = DJ_JournalFilePath(known_time);
   Check("journal file path matches the expected date-based pattern",
         path == "ThembaEA\\Journal\\decisions_20260721.jsonl");

   //--- 6. Real durable append-then-read-back round trip -------------------
   // Use a clearly test-scoped signal_id so this never collides with a
   // real trading decision, and delete the file afterward.
   string test_path = DJ_JournalFilePath(TimeCurrent());
   if(FileIsExist(test_path))
      FileDelete(test_path); // clean slate — do not append to a real file

   STradeDecision t1 = DJ_NewDecision();
   t1.signal_id = "TASK009_TEST_LINE_1";
   t1.timestamp = TimeCurrent();
   t1.symbol = "TESTSYMBOL";

   STradeDecision t2 = DJ_NewDecision();
   t2.signal_id = "TASK009_TEST_LINE_2";
   t2.timestamp = TimeCurrent();
   t2.symbol = "TESTSYMBOL";

   string err;
   bool append1_ok = DJ_AppendDecision(t1, err);
   Check("first append succeeds", append1_ok);
   bool append2_ok = DJ_AppendDecision(t2, err);
   Check("second append succeeds (does not overwrite the first)", append2_ok);

   int read_handle = FileOpen(test_path, FILE_READ | FILE_TXT | FILE_ANSI);
   Check("journal file can be reopened for reading", read_handle != INVALID_HANDLE);
   if(read_handle != INVALID_HANDLE)
     {
      string line1 = FileReadString(read_handle);
      string line2 = FileReadString(read_handle);
      FileClose(read_handle);

      Check("first written line contains TASK009_TEST_LINE_1",
            Contains(line1, "TASK009_TEST_LINE_1"));
      Check("second written line contains TASK009_TEST_LINE_2",
            Contains(line2, "TASK009_TEST_LINE_2"));
     }

   //--- Cleanup: leave no residue ------------------------------------------
   if(FileIsExist(test_path))
      FileDelete(test_path);
   Check("test journal file removed after cleanup", !FileIsExist(test_path));

   PrintFormat("=== TASK-009 DecisionJournal test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
