//+------------------------------------------------------------------+
//| Test_ExecutionEventJournal.mq5                                    |
//| Themba Adaptive Intraday Engine — Codex review, ninth round, P1     |
//| finding 9 compile/logic test                                       |
//|                                                                    |
//| Exercises SExecutionEvent defaults, event_id uniqueness, JSON        |
//| serialization (including null-handling for optional fields), the      |
//| journal file path format, and a real durable append-then-read-back      |
//| round trip. The test journal file is deleted at the end so a real       |
//| run leaves no residue.                                                     |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Journal/ExecutionEventJournal.mqh"

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
   Print("=== Codex round-9 P1 finding 9 ExecutionEventJournal test start ===");

   //--- 1. Defaults --------------------------------------------------------
   SExecutionEvent e = EEJ_NewEvent();
   Check("new event defaults signal_id to empty", e.signal_id == "");
   Check("new event defaults intent_id to empty", e.intent_id == "");
   Check("new event defaults order_id to empty", e.order_id == "");
   Check("new event defaults deal_id to empty", e.deal_id == "");
   Check("new event defaults order_ticket to 0", e.order_ticket == 0);
   Check("new event defaults filled to false", e.filled == false);
   Check("new event defaults has_volume to false", e.has_volume == false);
   Check("new event defaults has_price to false", e.has_price == false);

   //--- 2. Event ID uniqueness/format ---------------------------------------
   datetime known_time = D'2026.07.27 10:00:00';
   string id1 = EEJ_BuildEventId(known_time, 12345);
   string id2 = EEJ_BuildEventId(known_time, 12346);
   Check("event IDs at the same timestamp but different micro counters differ",
         id1 != id2);
   Check("event ID starts with 'EV' prefix", StringFind(id1, "EV") == 0);

   //--- 3. Full serialization, including null-handling for unset fields ----
   SExecutionEvent full = EEJ_NewEvent();
   full.event_id = "EV_TEST_1";
   full.event_type = "ASYNC_FILL_CONFIRMED";
   full.signal_id = "SIG_TEST_1";
   full.intent_id = "TI123_456";
   full.order_id = "987654321";
   full.order_ticket = 111222333;
   full.deal_id = "555666777";
   full.timestamp = known_time;
   full.symbol = "EURUSD";
   full.filled = true;
   full.volume = 0.10;
   full.has_volume = true;
   full.price = 1.23456;
   full.has_price = true;
   full.outcome_note = "async_fill_confirmed";

   string json = EEJ_SerializeEvent(full);
   PrintFormat("INFO: serialized event = %s", json);

   Check("serialized JSON contains event_id", Contains(json, "\"event_id\":\"EV_TEST_1\""));
   Check("serialized JSON contains event_type",
         Contains(json, "\"event_type\":\"ASYNC_FILL_CONFIRMED\""));
   Check("serialized JSON contains signal_id", Contains(json, "\"signal_id\":\"SIG_TEST_1\""));
   Check("serialized JSON contains intent_id", Contains(json, "\"intent_id\":\"TI123_456\""));
   Check("serialized JSON contains order_id", Contains(json, "\"order_id\":\"987654321\""));
   Check("serialized JSON contains order_ticket as a bare integer",
         Contains(json, "\"order_ticket\":111222333"));
   Check("serialized JSON contains deal_id", Contains(json, "\"deal_id\":\"555666777\""));
   Check("serialized JSON contains correct timestamp_utc",
         Contains(json, "\"timestamp_utc\":\"2026-07-27T10:00:00Z\""));
   Check("serialized JSON contains filled=true", Contains(json, "\"filled\":true"));
   Check("serialized JSON contains the numeric volume", Contains(json, "\"volume\":0.10"));
   Check("serialized JSON contains the numeric price", Contains(json, "\"price\":1.23456000"));
   Check("serialized JSON is a single well-formed brace pair",
         StringGetCharacter(json, 0) == '{' &&
         StringGetCharacter(json, StringLen(json) - 1) == '}');

   //--- 4. Null-handling: unset signal_id/intent_id/order_id/deal_id/-------
   //---    volume/price all serialize as JSON null, never a fabricated -----
   //---    value. ------------------------------------------------------------
   SExecutionEvent sparse = EEJ_NewEvent();
   sparse.event_id = "EV_TEST_2";
   sparse.event_type = "ASYNC_NEVER_FILLED";
   sparse.order_ticket = 42;
   sparse.timestamp = known_time;
   sparse.symbol = "EURUSD";
   sparse.filled = false;
   sparse.outcome_note = "async_order_never_filled_state_ORDER_STATE_CANCELED";

   string sparse_json = EEJ_SerializeEvent(sparse);
   Check("unset signal_id serializes as null", Contains(sparse_json, "\"signal_id\":null"));
   Check("unset intent_id serializes as null", Contains(sparse_json, "\"intent_id\":null"));
   Check("unset order_id serializes as null", Contains(sparse_json, "\"order_id\":null"));
   Check("unset deal_id serializes as null", Contains(sparse_json, "\"deal_id\":null"));
   Check("unset volume serializes as null", Contains(sparse_json, "\"volume\":null"));
   Check("unset price serializes as null", Contains(sparse_json, "\"price\":null"));
   Check("filled=false serializes correctly", Contains(sparse_json, "\"filled\":false"));

   //--- 5. Journal file path format, distinct from DecisionJournal.mqh's ---
   //---    own decisions_*.jsonl files. ---------------------------------------
   string path = EEJ_JournalFilePath(known_time);
   Check("journal file path matches the expected date-based pattern",
         path == "ThembaEA\\Journal\\execution_events_20260727.jsonl");

   //--- 6. Real durable append-then-read-back round trip --------------------
   string test_path = EEJ_JournalFilePath(TimeCurrent());
   if(FileIsExist(test_path))
      FileDelete(test_path); // clean slate — do not append to a real file

   SExecutionEvent t1 = EEJ_NewEvent();
   t1.event_id = "EEJ_TEST_LINE_1";
   t1.event_type = "SYNC_FILL";
   t1.timestamp = TimeCurrent();
   t1.symbol = "TESTSYMBOL";
   t1.filled = true;
   t1.outcome_note = "sync_fill_confirmed";

   SExecutionEvent t2 = EEJ_NewEvent();
   t2.event_id = "EEJ_TEST_LINE_2";
   t2.event_type = "ASYNC_NEVER_FILLED";
   t2.timestamp = TimeCurrent();
   t2.symbol = "TESTSYMBOL";
   t2.filled = false;
   t2.outcome_note = "async_order_never_filled_state_ORDER_STATE_EXPIRED";

   string err;
   bool append1_ok = EEJ_AppendEvent(t1, err);
   Check("first append succeeds", append1_ok);
   bool append2_ok = EEJ_AppendEvent(t2, err);
   Check("second append succeeds (does not overwrite the first)", append2_ok);

   int read_handle = FileOpen(test_path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ, 0,
                               CP_UTF8);
   Check("journal file can be reopened for reading", read_handle != INVALID_HANDLE);
   if(read_handle != INVALID_HANDLE)
     {
      string line1 = FileReadString(read_handle);
      string line2 = FileReadString(read_handle);
      FileClose(read_handle);

      Check("first written line contains EEJ_TEST_LINE_1", Contains(line1, "EEJ_TEST_LINE_1"));
      Check("second written line contains EEJ_TEST_LINE_2", Contains(line2, "EEJ_TEST_LINE_2"));
     }

   //--- Cleanup: leave no residue --------------------------------------------
   if(FileIsExist(test_path))
      FileDelete(test_path);
   Check("test journal file removed after cleanup", !FileIsExist(test_path));

   PrintFormat("=== Codex round-9 P1 finding 9 ExecutionEventJournal test complete: "
               "%d passed, %d failed ===", g_pass, g_fail);
  }
