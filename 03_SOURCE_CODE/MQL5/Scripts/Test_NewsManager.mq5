//+------------------------------------------------------------------+
//| Test_NewsManager.mq5                                              |
//| Themba Adaptive Intraday Engine — TASK-029 compile/logic test      |
//|                                                                    |
//| Tests 1-10 use hand-fabricated SNewsEvent arrays so every expected    |
//| result is hand-derivable (pure, deterministic, no live dependency).    |
//| Tests 11+ exercise NullNewsProvider (trivially deterministic) and         |
//| MT5CalendarProvider against a real symbol/currency — informational          |
//| only (whether any real event exists right now depends on the terminal's       |
//| actual calendar cache, not something this script controls), matching            |
//| Test_RiskManager.mq5's own real-symbol section precedent.                          |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/News/MT5CalendarProvider.mqh"
#include "../Include/ThembaEA/News/NullNewsProvider.mqh"

input string InpTestSymbol = "EURUSD";

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

SNewsEvent MakeEvent(const string id, const int importance, const datetime scheduled_server_time)
  {
   SNewsEvent e = NM_NewEvent();
   e.event_id = id;
   e.importance = importance;
   e.scheduled_server_time = scheduled_server_time;
   return e;
  }

void OnStart()
  {
   Print("=== TASK-029 NewsManager test start ===");

   datetime anchor = D'2026.07.21 12:00:00'; // arbitrary fixed reference server time

   SNewsEvent events[];
   ArrayResize(events, 2);
   events[0] = MakeEvent("EVT_HIGH", 2, anchor);          // high-importance event at anchor
   events[1] = MakeEvent("EVT_LOW", 0, anchor + 3600);    // low-importance event 1h later

   string trigger;

   //--- 1. Exactly at the event's scheduled time -> inside the window ----
   Check("current time == scheduled time is inside the blackout window",
         NM_IsInBlackoutWindowArray(events, anchor, 15, 15, 1, trigger));
   Check("triggering_event_id == EVT_HIGH for the exact-time case", trigger == "EVT_HIGH");

   //--- 2. 14 minutes before -> inside (before_minutes=15) ----------------
   Check("14 minutes before scheduled time is inside the window",
         NM_IsInBlackoutWindowArray(events, anchor - 14 * 60, 15, 15, 1, trigger));

   //--- 3. 16 minutes before -> outside -----------------------------------
   Check("16 minutes before scheduled time is OUTSIDE the window",
         NM_IsInBlackoutWindowArray(events, anchor - 16 * 60, 15, 15, 1, trigger) == false);

   //--- 4. 14 minutes after -> inside --------------------------------------
   Check("14 minutes after scheduled time is inside the window",
         NM_IsInBlackoutWindowArray(events, anchor + 14 * 60, 15, 15, 1, trigger));

   //--- 5. 16 minutes after -> outside -------------------------------------
   Check("16 minutes after scheduled time is OUTSIDE the window",
         NM_IsInBlackoutWindowArray(events, anchor + 16 * 60, 15, 15, 1, trigger) == false);

   //--- 6. min_importance filter excludes the low-importance event --------
   Check("a low-importance-only event does not trigger blackout at min_importance=1",
         NM_IsInBlackoutWindowArray(events, anchor + 3600, 15, 15, 1, trigger) == false);
   Check("the SAME low-importance event DOES trigger at min_importance=0",
         NM_IsInBlackoutWindowArray(events, anchor + 3600, 15, 15, 0, trigger));

   //--- 7. No events at all -> never a blackout ----------------------------
   SNewsEvent empty[];
   Check("an empty events array never triggers a blackout",
         NM_IsInBlackoutWindowArray(empty, anchor, 15, 15, 0, trigger) == false);
   Check("triggering_event_id is empty when no event triggers", trigger == "");

   //--- 8. Spread-extension: past nominal end, spread still wide ----------
   datetime past_nominal_end = anchor + 15 * 60 + 5 * 60; // 5 min past the 15-min-after window
   double wide_spread = 10.0;
   double atr = 1.0;
   double max_spread_atr_multiple = 0.15; // spread must be <= 0.15*ATR = 0.15 to "normalize"
   Check("past the nominal window end, a still-wide spread EXTENDS the blackout",
         NM_IsInBlackoutWindowExtended(events, past_nominal_end, 15, 15, 30, 1, wide_spread,
                                        atr, max_spread_atr_multiple, trigger));

   //--- 9. Spread-extension: past nominal end, spread normalized ----------
   double normal_spread = 0.10; // <= 0.15*1.0 -> normalized
   Check("past the nominal window end, a normalized spread does NOT extend the blackout",
         NM_IsInBlackoutWindowExtended(events, past_nominal_end, 15, 15, 30, 1, normal_spread,
                                        atr, max_spread_atr_multiple, trigger) == false);

   //--- 10. Spread-extension: past the extension deadline itself -----------
   datetime past_deadline = anchor + 15 * 60 + 31 * 60; // 31 min past nominal end, cap is 30
   Check("past the extension deadline, blackout ends regardless of spread",
         NM_IsInBlackoutWindowExtended(events, past_deadline, 15, 15, 30, 1, wide_spread,
                                        atr, max_spread_atr_multiple, trigger) == false);

   //--- 11. NullNewsProvider always reports zero events --------------------
   SNewsEvent null_events[];
   int null_count = NNP_FetchEvents(null_events);
   Check("NullNewsProvider reports exactly 0 events", null_count == 0);
   Check("NullNewsProvider leaves the events array empty", ArraySize(null_events) == 0);

   //--- 12. MT5CalendarProvider real-symbol smoke test (informational) ----
   string real_trigger;
   int fetch_result;
   bool blackout_now = MTC_IsInBlackoutNow(InpTestSymbol, "USD", 2, 15, 15, 30, 0.15, 1.0,
                                            real_trigger, fetch_result);
   PrintFormat("INFO: MTC_IsInBlackoutNow('%s', 'USD') = %s, fetch_result=%d, trigger='%s' — "
               "informational only, depends on the terminal's real, live calendar cache at "
               "the moment this script runs, not something this test controls.",
               InpTestSymbol, blackout_now ? "true" : "false", fetch_result, real_trigger);
   Check("MTC_IsInBlackoutNow runs without a runtime error (fetch_result >= -1, i.e. any "
         "defined outcome)", fetch_result >= -1);

   PrintFormat("=== TASK-029 NewsManager test complete: %d passed, %d failed ===", g_pass, g_fail);
  }
