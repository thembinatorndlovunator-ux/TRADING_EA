//+------------------------------------------------------------------+
//| Test_CloseInFlightTracker.mq5                                     |
//| Themba Adaptive Intraday Engine — compile/logic test                |
//|                                                                    |
//| **Added, 2026-07-22 (Codex review finding, eighth round, P1 finding    |
//| 13):** pure, deterministic, no live trading action -- exercises the           |
//| in-memory session-scoped close-in-flight tracker directly against            |
//| fabricated position_id values.                                                    |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Execution/CloseInFlightTracker.mqh"

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

void OnStart()
  {
   Print("=== CloseInFlightTracker test start ===");

   ulong pos_a = 990099013001;
   ulong pos_b = 990099013002;

   // Clean slate (in case a prior aborted run left residue in-memory --
   // impossible across script runs since this is session-scoped, but
   // idempotent regardless).
   CIFT_ClearCloseInFlight(pos_a);
   CIFT_ClearCloseInFlight(pos_b);

   Check("a fresh position is not reported in-flight", CIFT_IsCloseInFlight(pos_a) == false);

   CIFT_MarkCloseInFlight(pos_a);
   Check("marking a position in-flight is reflected immediately", CIFT_IsCloseInFlight(pos_a));
   Check("an UNRELATED position is unaffected by another one's in-flight mark",
         CIFT_IsCloseInFlight(pos_b) == false);

   // Marking the same position twice must not create a duplicate entry
   // (idempotent) -- verified indirectly via a single clear fully
   // un-marking it.
   CIFT_MarkCloseInFlight(pos_a);
   CIFT_ClearCloseInFlight(pos_a);
   Check("a single clear fully un-marks a position marked twice (idempotent mark)",
         CIFT_IsCloseInFlight(pos_a) == false);

   CIFT_MarkCloseInFlight(pos_a);
   CIFT_MarkCloseInFlight(pos_b);
   Check("two independently in-flight positions are both reported true",
         CIFT_IsCloseInFlight(pos_a) && CIFT_IsCloseInFlight(pos_b));
   CIFT_ClearCloseInFlight(pos_a);
   Check("clearing one in-flight position leaves the OTHER one still marked",
         CIFT_IsCloseInFlight(pos_a) == false && CIFT_IsCloseInFlight(pos_b));

   CIFT_ClearCloseInFlight(pos_b);
   Check("both positions are clear after cleanup",
         CIFT_IsCloseInFlight(pos_a) == false && CIFT_IsCloseInFlight(pos_b) == false);

   //--- Staleness timeout (Codex review finding, ninth round, P0 finding 6):
   //--- a close request that is REJECTED/CANCELLED at the broker (producing
   //--- NO close deal) previously left the in-flight mark set FOREVER,
   //--- wedging resubmission until restart. Simulated here the same way
   //--- Test_StateManager.mq5/Test_DailyWeeklyLimits.mq5 simulate a stale
   //--- lock/boundary -- backdating the in-memory timestamp directly rather
   //--- than waiting CIFT_STALE_SECONDS in real time.
   ulong pos_c = 990099013003;
   CIFT_MarkCloseInFlight(pos_c);
   Check("a freshly-marked position is in-flight", CIFT_IsCloseInFlight(pos_c));
   for(int i = 0; i < ArraySize(g_cift_inflight_position_ids); i++)
      if(g_cift_inflight_position_ids[i] == pos_c)
         g_cift_inflight_since[i] = TimeCurrent() - (CIFT_STALE_SECONDS + 5);
   Check("a mark older than CIFT_STALE_SECONDS with no confirming close deal is treated as "
         "abandoned, not wedged forever", CIFT_IsCloseInFlight(pos_c) == false);
   // Proves the stale entry was actually REMOVED, not just reported false
   // once while still occupying a slot -- a fresh mark must round-trip
   // cleanly afterward.
   CIFT_MarkCloseInFlight(pos_c);
   Check("a fresh mark on the same position_id after its stale entry was cleared "
         "round-trips normally", CIFT_IsCloseInFlight(pos_c));
   CIFT_ClearCloseInFlight(pos_c);

   PrintFormat("=== CloseInFlightTracker test complete: %d passed, %d failed ===", g_pass, g_fail);
  }
