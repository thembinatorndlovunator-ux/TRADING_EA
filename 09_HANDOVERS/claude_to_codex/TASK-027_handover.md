# Claude → Codex handover — TASK-027 (wire OrderManager into the live EA)

**Note on review availability:** same as TASK-003 through 026 — Codex's
independent-review budget is currently exhausted. Queued. **This is the
single highest-priority task in the entire project to review whenever
budget returns** — it is the first build capable of submitting a real
order, and it was done at the user's explicit request/sign-off after
TASK-026 deliberately paused for that authorization.

## What this task is

Adds `InpEnableOrderSubmission` (master safety toggle, default `false`)
and `AttemptOrderSubmission` to `ThembaAdaptiveIntradayEA.mq5`, gating
real order submission behind 6 sequential risk checks composed from
already-built modules (`DailyWeeklyLimits.mqh`, `EquityPeakManager.mqh`,
`DrawdownController.mqh`, `RiskManager.mqh`, `OrderManager.mqh`). Full
detail, including explicit scope gaps, in
`TASK-027_WIRE_ORDER_MANAGER.md`.

## What to check, if/when reviewed

1. **`InpEnableOrderSubmission=false` truly changes nothing** — the
   single most important thing to verify. Confirm `AttemptOrderSubmission`
   is only ever called inside the `if(InpEnableOrderSubmission)` branch
   in `EvaluateAndJournal`, and that the account-wide bookkeeping calls
   added to the top of that function (`DWL_Ensure*`, `EPM_Update*`) are
   read-only with respect to trading (they only update StateManager's
   persisted equity/peak figures, never open/close anything) — confirm
   this by inspection, not by trusting this description.
2. **The 6-gate sequence's order and completeness** — trace each of the
   7 numbered steps in `AttemptOrderSubmission` against section 8 of
   `TASK-002_PHASE2_SPECIFICATION.md`, and confirm no gate can be
   skipped by an early return that bypasses a later one.
3. **The stated total-open-risk simplification** — confirm the claim
   that "step 1 (no-add-on) guarantees at most one position is ever
   open, making per-trade and total-open-risk numerically identical
   here" actually holds given the code, not just that it sounds
   plausible.
4. **The stop-widening-then-resubmission logic** — confirm that when
   `RM_ValidateStopDistance` widens a stop to the floor,
   `OM_OpenPosition` is actually called with `final_stop` (the widened
   value), not `resolution.winner.stop_price` (the strategy's original
   proposal) — a subtle place a copy-paste slip could silently submit
   the wrong stop.
5. **The explicitly stated open gaps** (three-loss cooldown, durable-
   intent persistence, no forced close on loss-cap breach) — confirm
   these are genuinely absent (not accidentally half-implemented
   somewhere) and that their absence is not misrepresented as anything
   other than an open gap.
6. **Compile evidence:** re-run
   `MetaEditor64.exe /compile:"...\ThembaAdaptiveIntradayEA.mq5" /log:...`
   and confirm 0 errors, 0 warnings independently.
7. **Runtime verification is now the single highest-priority item in
   the entire project's batched verification backlog, at materially
   higher stakes than any prior item** — this build can place real
   orders once a user flips `InpEnableOrderSubmission=true`. Confirm on
   a demo account, toggle off first (byte-for-byte TASK-025 behavior),
   then toggle on and confirm one fully-gated real order submission
   with correct journal fields.

## Files in this task

Modified: `03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5`,
`TASKS.md`. New: `TASK-027_WIRE_ORDER_MANAGER.md`, this file. No file
under `01_BASELINE/` touched.
