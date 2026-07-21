# Claude → Codex handover — TASK-029 (NewsManager, begins Phase 7)

**Note on review availability:** same as TASK-003 through 027 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`NewsManager.mqh` (`SNewsEvent` interface shape, `NEWS_BLACKOUT`
predicate + spread-normalization extension), `MT5CalendarProvider.mqh`
(live metals provider wrapping MQL5's native Calendar functions),
`NullNewsProvider.mqh` (synthetics — always zero events). Begins Phase
7. Full detail, including several stated assumptions this task made
where the spec/project docs were silent, in `TASK-029_NEWS_MANAGER.md`.

## What to check, if/when reviewed

1. **The blackout-window boundary arithmetic** — trace tests 1-5 in
   `Test_NewsManager.mq5` (14/16-minutes before/after) by hand against
   `NM_IsInBlackoutWindowArray`'s actual comparison operators (`>=`/`<=`
   vs `>`/`<` matters at the exact boundary).
2. **The spread-extension cap (`max_extension_minutes`) is this task's
   own interpretation**, not something the spec states a number for —
   confirm whether capping the extension at all is the right call, or
   whether the spec intends an unbounded "wait until spread normalizes"
   with no time limit.
3. **The `MqlCalendarValue.time`-is-UTC assumption** — this is stated as
   unverified in the task file; if you have a way to confirm MQL5's
   actual documented behavior here (or test against a real known event),
   that would resolve the single most consequential unverified
   assumption in this task.
4. **The scope-boundary decision to NOT wire this into the live EA
   yet** — confirm the reasoning (bundling news + spread-gating +
   hysteresis into one coherent follow-up task, rather than partially
   wiring just news) is sound, not merely a convenient excuse to defer
   work.
5. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_NewsManager.mq5" /log:...` and
   confirm 0 errors, 0 warnings independently.
6. **`MTC_DecodeValue`'s fixed-point decoding** — confirm the
   `raw / 10^digits` approach and the `LONG_MIN`-as-"unavailable"
   sentinel check are actually correct against MQL5's documented
   `MqlCalendarValue` encoding, ideally against a real released event
   with a known actual value.

## Files in this task

New:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/News/NewsManager.mqh`,
`MT5CalendarProvider.mqh`, `NullNewsProvider.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_NewsManager.mq5`,
`TASK-029_NEWS_MANAGER.md`, this file. Modified: `TASKS.md`.
`ThembaAdaptiveIntradayEA.mq5` and `MarketRegimeEngine.mqh` are
deliberately NOT modified — see the task file's Scope Boundary section.
