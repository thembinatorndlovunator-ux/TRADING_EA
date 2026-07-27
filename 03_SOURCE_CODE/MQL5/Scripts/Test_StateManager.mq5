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

   // **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 2):
   // SM_EnsureAccountLockInitialized is now a no-op -- bootstrap is folded
   // directly into SM_AcquireAccountLock itself (race-free via
   // ERR_GLOBALVARIABLE_NOT_FOUND detection). Calling it here is harmless
   // but no longer required; kept only to prove the no-op doesn't break
   // anything for existing call sites.**
   SM_EnsureAccountLockInitialized();

   // Clean slate: remove any residue from a prior run before testing.
   // Force the lock itself back to a clean unlocked state too (a prior
   // aborted run could otherwise leave it held).
   GlobalVariableSet(SM_AccountKey("lock"), 0.0);
   GlobalVariableSet(SM_AccountKey("lock") + "__since", 0.0);
   SM_DeleteAccountField("test_field_a");
   SM_DeleteAccountField("test_field_b");
   SM_DeleteAccountField("schema_version");
   SM_DeleteAccountField("test_peak");

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
   double token_1;
   bool first_acquire = SM_AcquireAccountLock(token_1, 200);
   Check("first lock acquire succeeds", first_acquire);
   Check("first acquire's own token is nonzero", token_1 != 0.0);
   SM_StampAccountLockHeld();

   double token_2_unused;
   bool second_acquire = SM_AcquireAccountLock(token_2_unused, 200); // short
                                                      // timeout, lock still
                                                      // held by "us" above —
                                                      // this simulates a
                                                      // second writer.
   Check("second acquire attempt while held times out (returns false)",
         second_acquire == false);

   SM_ReleaseAccountLock(token_1);
   double token_3;
   bool third_acquire = SM_AcquireAccountLock(token_3, 200);
   Check("acquire succeeds again after release", third_acquire);
   SM_ReleaseAccountLock(token_3);

   //--- 4b. Owner-token ABA regression (Codex review finding, ninth ---
   //---     round, P0 finding 2): a delayed release from a PRIOR holder ---
   //---     whose lock was force-broken as stale must NOT clear a -------
   //---     DIFFERENT, currently-legitimate holder's lock. --------------
   double token_a;
   Check("holder A acquires the lock", SM_AcquireAccountLock(token_a, 200));
   SM_StampAccountLockHeld();

   // Simulate holder A going silent long enough to look abandoned,
   // without actually waiting SM_LOCK_STALE_SECONDS in real time.
   GlobalVariableSet(SM_AccountKey("lock") + "__since",
                      (double)(TimeCurrent() - (SM_LOCK_STALE_SECONDS + 5)));

   double token_b;
   bool holder_b_acquired = SM_AcquireAccountLock(token_b, 200);
   Check("holder B force-breaks A's stale lock and acquires it", holder_b_acquired);
   Check("holder B's token differs from holder A's stale token", token_b != token_a);
   SM_StampAccountLockHeld();

   // Holder A's release finally arrives, using its OWN (now-stale) token --
   // this must be a no-op against holder B's live lock, not clear it.
   SM_ReleaseAccountLock(token_a);

   double token_c_unused;
   bool third_party_during_b = SM_AcquireAccountLock(token_c_unused, 200);
   Check("holder A's stale release does NOT clear holder B's live lock "
         "(a third acquire attempt still times out)",
         third_party_during_b == false);

   // Holder B's own, correctly-tokened release DOES clear it.
   SM_ReleaseAccountLock(token_b);
   double token_d;
   bool acquire_after_b_release = SM_AcquireAccountLock(token_d, 200);
   Check("holder B's own correctly-tokened release frees the lock for a new acquirer",
         acquire_after_b_release);
   SM_ReleaseAccountLock(token_d);

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

   //--- 6b. SM_SetAccountDoublesBatch stops at the first failed write ---
   //---     (Codex review finding, ninth round, P1 finding 2): a field --
   //---     name that exceeds MT5's 63-character global-variable limit --
   //---     makes KE_SetDoubleChecked fail for real (not simulated) -- ---
   //---     placed FIRST in the batch, the SECOND (otherwise-valid) -----
   //---     field must then NEVER be written. -------------------------
   string overlong_field = "";
   for(int i = 0; i < 80; i++)
      overlong_field += "x";
   SM_DeleteAccountField("test_field_a"); // start from a known state
   SM_SetAccountDouble("test_field_a", 1.0);
   string stop_early_fields[2] = {overlong_field, "test_field_a"};
   double stop_early_values[2] = {123.0, 456.0};
   bool stop_early_ok = SM_SetAccountDoublesBatch(stop_early_fields, stop_early_values);
   Check("a batch whose FIRST write fails reports overall failure",
         stop_early_ok == false);
   Check("a batch whose FIRST write fails never reaches the SECOND field",
         SM_GetAccountDouble("test_field_a", default_val) == 1.0);

   //--- 7. SM_SetAccountDoubleIfGreater: atomic raise-only write (Codex ----
   //---    review finding, eighth round, P0 finding 4) -----------------
   bool first_raise = SM_SetAccountDoubleIfGreater("test_peak", 50.0);
   Check("SM_SetAccountDoubleIfGreater returns true on first (never-set) write", first_raise);
   Check("SM_SetAccountDoubleIfGreater sets the field on first write",
         SM_GetAccountDouble("test_peak", default_val) == 50.0);

   SM_SetAccountDoubleIfGreater("test_peak", 30.0); // lower candidate — must NOT overwrite
   Check("SM_SetAccountDoubleIfGreater ignores a LOWER candidate",
         SM_GetAccountDouble("test_peak", default_val) == 50.0);

   SM_SetAccountDoubleIfGreater("test_peak", 75.0); // higher candidate — must overwrite
   Check("SM_SetAccountDoubleIfGreater applies a HIGHER candidate",
         SM_GetAccountDouble("test_peak", default_val) == 75.0);

   //--- Cleanup: leave no residue in the account-wide namespace -------
   SM_DeleteAccountField("test_field_a");
   SM_DeleteAccountField("test_field_b");
   SM_DeleteAccountField("schema_version");
   SM_DeleteAccountField("test_peak");
   Check("field A removed after cleanup",
         !SM_AccountFieldExists("test_field_a"));
   Check("schema_version removed after cleanup",
         !SM_AccountFieldExists("schema_version"));

   PrintFormat("=== TASK-003 StateManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
