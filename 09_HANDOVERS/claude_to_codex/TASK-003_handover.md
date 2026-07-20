# Claude → Codex handover — TASK-003 (StateManager, account-wide persistence)

**Note on review availability:** the user has stated Codex's independent-
review budget for this project is currently exhausted. This handover is
written in the standard format regardless, so that a review can be run
against it whenever budget is available again — treat it as queued, not
urgent.

## What this task is

The first Phase 3 ("Common core") module: `StateManager.mqh`, scoped to
the account-wide scalar namespace only (account_login + trade_server), per
`TASK-002_PHASE2_SPECIFICATION.md` section 8. Full detail in
`TASK-003_STATE_MANAGER.md`.

## What to check, if/when reviewed

1. **Lock correctness:** does `SM_AcquireAccountLock`'s use of
   `GlobalVariableSetOnCondition(lock_key, 1.0, 0.0)` actually provide
   mutual exclusion as MT5 documents it, and does the stale-lock-breaking
   branch (`SM_LOCK_STALE_SECONDS = 30`) introduce a window where two
   callers could both believe they hold the lock (e.g., if a legitimate
   long-held lock is mistaken for abandoned)?
2. **Schema migration:** does `SM_EnsureAccountSchema()` genuinely never
   delete/reset an existing field, matching
   `TASK-002_PHASE2_SPECIFICATION.md` section 8's "targeted migration,
   never blanket reset" requirement? At schema version 1.0 there is
   nothing to migrate from, so this is mostly a structural check that the
   *pattern* used for future migrations (additive-only branches) is sound.
3. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_StateManager.mq5" /log:...` and
   confirm 0 errors, 0 warnings independently.
4. **The outstanding gap:** `Test_StateManager.mq5`'s logic assertions
   (round-trip, lock exclusion, schema idempotency) have not been
   confirmed to actually run and print all-PASS — see
   `TASK-003_STATE_MANAGER.md`'s Test results section for why (this
   session's environment could not host a live MT5 chart to execute
   `OnStart`). If reviewing this task, please run the script on a real
   desktop session and report the actual PASS/FAIL output — that is more
   valuable than a code-reading-only review for a module whose entire
   purpose is runtime persistence behavior.

## Files in this task

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Core/StateManager.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_StateManager.mq5`,
`03_SOURCE_CODE/.gitignore`, `TASK-003_STATE_MANAGER.md`, this file.
Modified: `TASKS.md`. No baseline or TASK-001/002 file touched.
