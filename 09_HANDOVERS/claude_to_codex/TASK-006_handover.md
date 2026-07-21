# Claude → Codex handover — TASK-006 (SessionManager)

**Note on review availability:** same as TASK-003/004/005 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`SessionManager.mqh`: session-time-remaining and the daily/weekly/
intraday boundary clock, all against the trade server's own clock. Full
detail in `TASK-006_SESSION_MANAGER.md`.

## What to check, if/when reviewed

1. **Weekly boundary arithmetic:** `SN_CurrentWeeklyBoundary()`'s
   `days_since_monday = (dt.day_of_week + 6) % 7` mapping and the
   week-rollback branch (`if(now < this_week_monday_0005) return
   this_week_monday_0005 - 7*86400`) are the two places most likely to
   have an off-by-one for a specific day of week — worth tracing by hand
   for all seven `day_of_week` values (0=Sunday..6=Saturday), not just
   the one the reviewer happens to run it on.
2. **The multi-session "remaining" interpretation** in
   `SN_GetSessionMinutesRemaining` is a stated judgment call (see
   `TASK-006_SESSION_MANAGER.md`'s Risks section) — worth a second
   opinion on whether "time until today's last session ends" is the
   right reading of `TASK-002_PHASE2_SPECIFICATION.md` section 1 item 4,
   versus a stricter "net trading time only" interpretation.
3. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_SessionManager.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently (three `datetime`/
   `long` conversion warnings were found and fixed during this task —
   confirm the fix is real, not just silencing).
4. **Runtime verification is a known, batched item** across TASK-003
   through 006 — see `TASK-006_SESSION_MANAGER.md`'s Risks section.

## Files in this task

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/SessionManager.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_SessionManager.mq5`,
`TASK-006_SESSION_MANAGER.md`, this file. Modified: `TASKS.md`. No
baseline or prior TASK-00N file touched.
