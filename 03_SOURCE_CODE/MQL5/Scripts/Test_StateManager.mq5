//+------------------------------------------------------------------+
//| Test_StateManager.mq5                                             |
//| Themba Adaptive Intraday Engine — TASK-003 compile/logic test      |
//|                                                                    |
//| Not a unit-test framework — a MetaEditor-compilable, Strategy-      |
//| Tester/manual-run script that exercises StateManager.mqh's public  |
//| API and prints PASS/FAIL per assertion, per PROJECT_RULES.md rule  |
//| 13 (every experiment documents what it checked) and CLAUDE.md's    |
//| "no claim of test success without actual evidence" rule.           |
//|                                                                    |
//| Run manually (F7 compile, then drag onto a chart, or Scripts       |
//| Strategy-Tester run) and read the Experts log for PASS/FAIL lines. |
//| All test fields are deleted at the end so a real run leaves no      |
//| residue in the account-wide namespace.                             |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Core/StateManager.mqh"

int  g_pass  = 0;
int  g_fail  = 0;

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
   Print("=== TASK-003 StateManager test start ===");

   // Clean slate: remove any residue from a prior run before testing.
   SM_DeleteAccountField("test_field_a");
   SM_DeleteAccountField("test_field_b");
   SM_DeleteAccountField("schema_version");
   SM_ReleaseAccountLock();

   //--- 1. Round-trip set/get -----------------------------------------
   double default_val = -999.0;
   Check("unset field returns default",
         SM_GetAccountDouble("test_field_a", default_val) == default_val);

   bool set_ok = SM_SetAccountDouble("test_field_a", 12345.5);
   Check("set returns true (lock acquired)", set_ok);
   Check("field exists after set", SM_AccountFieldExists("test_field_a"));
   Check("get returns the value just set",
         SM_GetAccountDouble("test_field_a", default_val) == 12345.5);

   //--- 2. Overwrite -----------------------------------------------
   SM_SetAccountDouble("test_field_a", 1.0);
   Check("overwrite updates the value",
         SM_GetAccountDouble("test_field_a", default_val) == 1.0);

   //--- 3. Two independent fields do not collide --------------------
   SM_SetAccountDouble("test_field_b", 42.0);
   Check("field A unaffected by field B write",
         SM_GetAccountDouble("test_field_a", default_val) == 1.0);
   Check("field B holds its own value",
         SM_GetAccountDouble("test_field_b", default_val) == 42.0);

   //--- 4. Lock: acquire, verify a second acquire attempt within the --
   //---    hold window fails, then release and verify it succeeds. ---
   bool first_acquire = SM_AcquireAccountLock(200);
   Check("first lock acquire succeeds", first_acquire);
   SM_StampAccountLockHeld();

   bool second_acquire = SM_AcquireAccountLock(200); // short timeout,
                                                      // lock still held
                                                      // by "us" above —
                                                      // this simulates a
                                                      // second writer.
   Check("second acquire attempt while held times out (returns false)",
         second_acquire == false);

   SM_ReleaseAccountLock();
   bool third_acquire = SM_AcquireAccountLock(200);
   Check("acquire succeeds again after release", third_acquire);
   SM_ReleaseAccountLock();

   //--- 5. Schema versioning: first-run stamps the version, and a ----
   //---    second call is a true no-op (idempotent). ------------------
   Check("schema version unset before first ensure",
         SM_GetAccountSchemaVersion() == 0.0);

   SM_EnsureAccountSchema();
   Check("schema version stamped after first ensure",
         SM_GetAccountSchemaVersion() == SM_SCHEMA_VERSION);

   // Set an unrelated field, then call Ensure again — the migration
   // must be a no-op and must NOT touch the unrelated field (this is
   // the "never blanket-reset a valid field" property from section 8).
   SM_SetAccountDouble("test_field_a", 777.0);
   SM_EnsureAccountSchema();
   Check("second Ensure call leaves an existing field untouched",
         SM_GetAccountDouble("test_field_a", default_val) == 777.0);
   Check("second Ensure call is idempotent on schema version",
         SM_GetAccountSchemaVersion() == SM_SCHEMA_VERSION);

   //--- 6. SM_SetAccountDoublesBatch: multiple fields under ONE lock ----
   //---    hold (Codex review finding, seventh round, P1 finding 14) ----
   string batch_fields[2] = {"test_field_a", "test_field_b"};
   double batch_values[2] = {111.0, 222.0};
   bool batch_ok = SM_SetAccountDoublesBatch(batch_fields, batch_values);
   Check("SM_SetAccountDoublesBatch returns true (lock acquired)", batch_ok);
   Check("SM_SetAccountDoublesBatch sets the FIRST field",
         SM_GetAccountDouble("test_field_a", default_val) == 111.0);
   Check("SM_SetAccountDoublesBatch sets the SECOND field",
         SM_GetAccountDouble("test_field_b", default_val) == 222.0);

   string mismatched_fields[2] = {"test_field_a", "test_field_b"};
   double mismatched_values[1] = {999.0};
   bool mismatched_ok = SM_SetAccountDoublesBatch(mismatched_fields, mismatched_values);
   Check("SM_SetAccountDoublesBatch refuses mismatched field/value array sizes",
         mismatched_ok == false);
   Check("a refused mismatched batch call touches NEITHER field",
         SM_GetAccountDouble("test_field_a", default_val) == 111.0 &&
         SM_GetAccountDouble("test_field_b", default_val) == 222.0);

   //--- Cleanup: leave no residue in the account-wide namespace -------
   SM_DeleteAccountField("test_field_a");
   SM_DeleteAccountField("test_field_b");
   SM_DeleteAccountField("schema_version");
   SM_ReleaseAccountLock();
   Check("field A removed after cleanup",
         !SM_AccountFieldExists("test_field_a"));
   Check("schema_version removed after cleanup",
         !SM_AccountFieldExists("schema_version"));

   PrintFormat("=== TASK-003 StateManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
