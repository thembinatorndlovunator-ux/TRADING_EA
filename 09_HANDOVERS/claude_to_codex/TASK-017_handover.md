# Claude → Codex handover — TASK-017 (candlestick reference cross-check)

**Note on review availability:** same as TASK-003 through 016 — Codex's
independent-review budget is currently exhausted. Queued.

## What this task is

Actually reading `EA Files/Candlestick Bible.pdf` and
`EA Files/SMC/SMART_MONEY_CONCEPT.pdf` (both local-only, never
committed) and cross-checking their pattern definitions against
`CandlestickPatternEngine.mqh` (TASK-014) and `ICTSMCGeometry.mqh`
(TASK-015) — closing a scope boundary those tasks had stated but not yet
acted on. Full detail in
`TASK-017_CANDLESTICK_REFERENCE_CROSSCHECK.md`.

## What to check, if/when reviewed

1. **The "currently non-binding" claim about the wick-to-body fix** —
   verify the algebra: given `lower_wick_ratio >= 0.60` and
   `body_ratio <= 0.30`, is `lower_wick_ratio/body_ratio >= 2.0`
   genuinely always true? (Yes: the ratio is minimized when the
   numerator is at its floor and the denominator at its ceiling
   simultaneously, giving exactly `0.60/0.30 = 2.0`.) Worth an
   independent re-derivation given how easy this kind of boundary-math
   claim is to get subtly wrong.
2. **The order-block definition fork** (finding 3) — this task
   deliberately did not resolve it, only documented it with a specific
   citation. Worth a second opinion on whether this project's simpler
   "last opposite candle before displacement" convention or the PDF's
   stricter "near-HTF-level, later-validated" convention is the better
   default once order blocks reach actual strategy-level consumption.
3. **Compile evidence:** re-run the three affected scripts'
   `MetaEditor64.exe /compile:...` commands and confirm 0 errors, 0
   warnings independently.

## Files in this task

Modified:
`03_SOURCE_CODE/MQL5/Include/ThembaEA/Patterns/CandlestickPatternEngine.mqh`.
New: `TASK-017_CANDLESTICK_REFERENCE_CROSSCHECK.md`, this file. Modified:
`TASKS.md`. No baseline or prior TASK-00N file touched.
