//+------------------------------------------------------------------+
//| Test_ChartPatternLifecycle.mq5                                    |
//| Themba Adaptive Intraday Engine — Codex review, ninth round, P1     |
//| finding 11 compile/logic test                                      |
//|                                                                    |
//| Exercises ChartPatternLifecycle.mqh's own persistence primitives      |
//| directly: default (never-seen) state, state transitions, durable       |
//| identity (same pivots -> same instance; different pivots or different   |
//| pattern type -> a genuinely different instance), CPL_IsTerminal, and     |
//| CPL_CleanupStale's own age-based deletion. The test symbol+magic's       |
//| own records are removed at both start and end so a real run leaves       |
//| no residue and repeated runs never see stale state.                       |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Patterns/ChartPatternEngine.mqh"
#include "../Include/ThembaEA/Patterns/ChartPatternLifecycle.mqh"

const string TEST_SYMBOL = "TASK028_CPL_TEST_SYMBOL";
const long   TEST_MAGIC  = 990028;

int g_pass = 0;
int g_fail = 0;

void Check(const string label, const bool condition)
  {
   if(condition) { PrintFormat("PASS: %s", label); g_pass++; }
   else          { PrintFormat("FAIL: %s", label); g_fail++; }
  }

void CleanupTestState()
  {
   string prefix = CPL_InstancePrefix(TEST_SYMBOL, TEST_MAGIC) + "__";
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) == 0)
         GlobalVariableDel(name);
     }
  }

void OnStart()
  {
   Print("=== Codex round-9 P1 finding 11 ChartPatternLifecycle test start ===");
   CleanupTestState();

   datetime p1 = D'2026.01.01 00:00';
   datetime p2 = D'2026.01.01 00:15';

   //--- 1. A never-seen instance reports CPL_STATE_NONE ---------------------
   ENUM_CP_LIFECYCLE_STATE initial = CPL_GetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_DOUBLE_TOP, p1, p2);
   Check("never-seen instance reports CPL_STATE_NONE", initial == CPL_STATE_NONE);
   Check("CPL_STATE_NONE is not terminal", CPL_IsTerminal(initial) == false);

   //--- 2. State transitions persist and read back correctly ----------------
   bool set_confirmed = CPL_SetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_DOUBLE_TOP, p1, p2,
                                       CPL_STATE_CONFIRMED);
   Check("CPL_SetState(CONFIRMED) succeeds", set_confirmed);
   ENUM_CP_LIFECYCLE_STATE after_confirmed = CPL_GetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_DOUBLE_TOP,
                                                            p1, p2);
   Check("state reads back as CPL_STATE_CONFIRMED", after_confirmed == CPL_STATE_CONFIRMED);
   Check("CPL_STATE_CONFIRMED is not terminal", CPL_IsTerminal(after_confirmed) == false);

   bool set_retesting = CPL_SetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_DOUBLE_TOP, p1, p2,
                                       CPL_STATE_RETESTING);
   Check("CPL_SetState(RETESTING) succeeds", set_retesting);
   Check("state reads back as CPL_STATE_RETESTING",
         CPL_GetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_DOUBLE_TOP, p1, p2) == CPL_STATE_RETESTING);

   bool set_traded = CPL_SetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_DOUBLE_TOP, p1, p2,
                                    CPL_STATE_TRADED);
   Check("CPL_SetState(TRADED) succeeds", set_traded);
   ENUM_CP_LIFECYCLE_STATE after_traded = CPL_GetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_DOUBLE_TOP,
                                                         p1, p2);
   Check("state reads back as CPL_STATE_TRADED", after_traded == CPL_STATE_TRADED);
   Check("CPL_STATE_TRADED is terminal (consumed)", CPL_IsTerminal(after_traded));

   //--- 3. INVALIDATED and EXPIRED are also terminal -------------------------
   Check("CPL_STATE_INVALIDATED is terminal", CPL_IsTerminal(CPL_STATE_INVALIDATED));
   Check("CPL_STATE_EXPIRED is terminal", CPL_IsTerminal(CPL_STATE_EXPIRED));

   //--- 4. Durable identity: the SAME type+pivots is the SAME instance -------
   Check("re-querying the exact same type+pivots still reports TRADED (durable identity)",
         CPL_GetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_DOUBLE_TOP, p1, p2) == CPL_STATE_TRADED);

   //--- 5. A different pattern TYPE with the SAME pivots is a DIFFERENT ------
   //---    instance (identity includes type, not just pivots). -----------------
   ENUM_CP_LIFECYCLE_STATE different_type = CPL_GetState(TEST_SYMBOL, TEST_MAGIC,
                                                           (int)CPT_DOUBLE_BOTTOM, p1, p2);
   Check("a different pattern type with the same pivots is a genuinely different, "
         "never-seen instance", different_type == CPL_STATE_NONE);

   //--- 6. The SAME pattern type with DIFFERENT pivots is a DIFFERENT --------
   //---    instance. ----------------------------------------------------------
   datetime p3 = D'2026.02.01 00:00';
   ENUM_CP_LIFECYCLE_STATE different_pivots = CPL_GetState(TEST_SYMBOL, TEST_MAGIC,
                                                             (int)CPT_DOUBLE_TOP, p1, p3);
   Check("the same pattern type with a different second pivot is a genuinely different, "
         "never-seen instance", different_pivots == CPL_STATE_NONE);

   //--- 7. Confirmed-time and retest-touch-time round-trip -------------------
   datetime confirmed_time = D'2026.01.01 01:00';
   Check("CPL_SetConfirmedTime succeeds",
         CPL_SetConfirmedTime(TEST_SYMBOL, TEST_MAGIC, (int)CPT_HEAD_SHOULDERS, p1, p2,
                               confirmed_time));
   Check("CPL_GetConfirmedTime reads back the exact value",
         CPL_GetConfirmedTime(TEST_SYMBOL, TEST_MAGIC, (int)CPT_HEAD_SHOULDERS, p1, p2) ==
         confirmed_time);
   Check("an instance never given a confirmed_time reads back 0",
         CPL_GetConfirmedTime(TEST_SYMBOL, TEST_MAGIC, (int)CPT_INV_HEAD_SHOULDERS, p1, p2) == 0);

   datetime touch_time = D'2026.01.01 02:00';
   Check("CPL_SetRetestTouchTime succeeds",
         CPL_SetRetestTouchTime(TEST_SYMBOL, TEST_MAGIC, (int)CPT_HEAD_SHOULDERS, p1, p2,
                                 touch_time));
   Check("CPL_GetRetestTouchTime reads back the exact value",
         CPL_GetRetestTouchTime(TEST_SYMBOL, TEST_MAGIC, (int)CPT_HEAD_SHOULDERS, p1, p2) ==
         touch_time);

   //--- 8. CPL_CleanupStale deletes only records past the retention window ---
   // Force this instance's own last_update far into the past by writing the
   // state again and then directly back-dating the companion field.
   CPL_SetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_TRIPLE_TOP, p1, p2, CPL_STATE_INVALIDATED);
   string stale_prefix = CPL_InstancePrefix(TEST_SYMBOL, TEST_MAGIC);
   string stale_id = CPL_InstanceId((int)CPT_TRIPLE_TOP, p1, p2);
   string stale_last_update_key = CPL_Key(stale_prefix, stale_id, "last_update");
   GlobalVariableSet(stale_last_update_key, (double)(TimeTradeServer() - 100000)); // far in the past

   // A fresh, recently-touched instance must survive the same cleanup pass.
   CPL_SetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_TRIPLE_BOTTOM, p1, p2, CPL_STATE_CONFIRMED);

   CPL_CleanupStale(TEST_SYMBOL, TEST_MAGIC, 3600); // 1-hour retention window

   Check("a record older than the retention window is deleted by CPL_CleanupStale "
         "(reads back as never-seen)",
         CPL_GetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_TRIPLE_TOP, p1, p2) == CPL_STATE_NONE);
   Check("a record within the retention window survives CPL_CleanupStale",
         CPL_GetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_TRIPLE_BOTTOM, p1, p2) == CPL_STATE_CONFIRMED);
   Check("the original TRADED instance (recently touched) also survives",
         CPL_GetState(TEST_SYMBOL, TEST_MAGIC, (int)CPT_DOUBLE_TOP, p1, p2) == CPL_STATE_TRADED);

   //--- Cleanup: leave no residue --------------------------------------------
   CleanupTestState();
   int remaining = 0;
   string prefix = CPL_InstancePrefix(TEST_SYMBOL, TEST_MAGIC) + "__";
   int total = GlobalVariablesTotal();
   for(int i = 0; i < total; i++)
      if(StringFind(GlobalVariableName(i), prefix) == 0)
         remaining++;
   Check("test cleanup leaves no residual lifecycle records", remaining == 0);

   PrintFormat("=== Codex round-9 P1 finding 11 ChartPatternLifecycle test complete: "
               "%d passed, %d failed ===", g_pass, g_fail);
  }
