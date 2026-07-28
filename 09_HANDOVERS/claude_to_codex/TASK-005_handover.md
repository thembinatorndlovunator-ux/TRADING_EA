# Claude → Codex handover — TASK-005 (MarketData)

**Note on review availability:** same as TASK-003/004 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

`MarketData.mqh`: the logical-index (completed-bar-only) price/ATR
accessor every other detection module will read through. Full detail in
`TASK-005_MARKET_DATA.md`.

## What to check, if/when reviewed

1. **The core guarantee:** does `logical_index + 1` as the MQL series
   start position genuinely always skip the forming bar, under every
   condition (symbol just selected with no history cached yet, a
   just-closed bar right at the boundary)? The test's
   `time[0] + PeriodSeconds(tf) <= TimeCurrent()` assertion is the
   intended proof of this — confirm that assertion is actually a valid
   proof and not just plausible-looking.
2. **ATR handle lifecycle:** handles are created via `iATR` and cached
   per period for the instance's lifetime, but never explicitly released
   via `IndicatorRelease`. For a long-lived EA instance with a bounded,
   small set of periods this is fine; confirm that assumption holds for
   how this module will actually be used (if a future caller requests
   many distinct periods dynamically, this could leak handles — worth
   flagging if so).
3. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\Test_MarketData.mq5" /log:...` and
   confirm 0 errors, 0 warnings independently.
4. **Runtime verification is now a known, batched item** — see
   `TASK-005_MARKET_DATA.md`'s Risks section. Three consecutive attempts
   in this session's environment have not reached script execution
   (stuck in a "Virtual Hosting" retry loop). If reviewing with real
   desktop access, running `Test_StateManager`, `Test_
   SymbolProfile_BrokerValidator`, and `Test_MarketData` in one sitting
   and reporting all three outputs would close every outstanding runtime
   gap at once.

## Files in this task

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Market/MarketData.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_MarketData.mq5`,
`TASK-005_MARKET_DATA.md`, this file. Modified: `TASKS.md`. No baseline or
prior TASK-00N file touched.
