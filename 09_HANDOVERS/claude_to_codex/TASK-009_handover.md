# Claude → Codex handover — TASK-009 (DecisionJournal)

**Note on review availability:** same as TASK-003 through 008 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`DecisionJournal.mqh`: serializes a trade-decision record to exactly
`TRADE_DECISION_SCHEMA.json`'s on-disk contract and durably appends it to
a daily JSON-lines file. Full detail in `TASK-009_DECISION_JOURNAL.md`.

## What to check, if/when reviewed

1. **Schema fidelity is the single most important check:** compare
   `STradeDecision`'s field list and `DJ_SerializeDecision`'s output
   key-by-key against `TRADE_DECISION_SCHEMA.json` at repo root. Any
   drift here defeats the entire point of this task.
2. **Null-handling correctness:** confirm `has_entry=false`/
   `has_stop=false`/empty pattern strings genuinely produce JSON `null`,
   not a `0`/`""` sentinel that a downstream JSON consumer would
   misinterpret as a real value.
3. **The append-not-overwrite behavior** — `FileOpen` with
   `FILE_READ|FILE_WRITE` plus `FileSeek(handle, 0, SEEK_END)` before
   writing is the mechanism relied on for this; confirm it's actually
   correct MQL5 usage for append semantics (this is the one platform-API
   assumption in this task most worth double-checking).
4. **The "pre-serialized JSON snippet" scope boundary** for
   `score_breakdown`/`targets`/`reasons_*` — confirm this is a reasonable
   scoping decision for a first `DecisionJournal` implementation, or
   whether it should have built a minimal JSON-array/object builder
   itself instead of trusting caller-supplied strings verbatim.
5. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_DecisionJournal.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
6. **Runtime verification is a known, batched item** across TASK-003
   through 009.

## Files in this task

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_DecisionJournal.mq5`,
`TASK-009_DECISION_JOURNAL.md`, this file. Modified: `TASKS.md`. No
baseline or prior TASK-00N file touched.
