# TASK-034 - Live safety wiring: cooldown, durable intent, regime-gating

## Objective

Wire together the three safety-critical pieces that exist as tested
standalone modules but are **not yet called by the live EA**:

1. Three-loss-per-symbol cooldown (spec section 8) — no module exists.
2. Durable-intent / idempotency persistence (spec section 12) — no
   module exists.
3. Regime-gating (`MRE_IsUntradeableSpreadOrLiquidity`,
   `MRE_ApplyHysteresis`, both built in TASK-016) + `NewsManager.mqh`'s
   `NEWS_BLACKOUT` (TASK-029) — built but never called from
   `ThembaAdaptiveIntradayEA.mq5`'s `EvaluateAndJournal`.

TASK-029's own task file deliberately deferred wiring these three
together as one coherent task rather than partially wiring just news in
isolation — this is that task.

## Reason

This is the largest concrete gap between "compiles and passes synthetic
tests" and "safe to run against a live/demo account." Per
[[project-open-gaps]]: `EvaluateAndJournal` currently reads the raw,
un-hysteresis'd, un-gated regime directly, with no cooldown and no
crash-recovery intent record. Order submission is already gated OFF by
default (`InpEnableOrderSubmission=false`, TASK-026/027), so this task
does not itself increase live-trading risk, but it is a hard
prerequisite before that flag could ever responsibly be considered for
`true`.

## Baseline behaviour

Neither immutable baseline EA implements per-symbol cooldown,
crash-recoverable intent persistence, or hysteresis-gated regime
switching in a form this project can reuse directly — this is new
orchestration wiring existing modules, not a port. `01_BASELINE/` must
not be modified.

## Evidence

- `TASK-002_PHASE2_SPECIFICATION.md` sections 8 (cooldown) and 12
  (durable intent).
- `03_SOURCE_CODE/MQL5/.../MarketRegimeEngine.mqh` —
  `MRE_IsUntradeableSpreadOrLiquidity`, `MRE_ApplyHysteresis` (TASK-016,
  built, unwired).
- `03_SOURCE_CODE/MQL5/.../NewsManager.mqh` — `NEWS_BLACKOUT` (TASK-029,
  built, unwired).
- `03_SOURCE_CODE/MQL5/.../StateManager.mqh` — the existing
  `GlobalVariableSetOnCondition`-guarded account-lock pattern the durable
  -intent record should reuse for consistency.
- `ThembaAdaptiveIntradayEA.mq5` (TASK-025) — `EvaluateAndJournal`, the
  actual call site all three pieces need to gate.
- `TASK-029_NEWS_MANAGER.md` — states the explicit reason wiring was
  deferred as one combined task.

## Specification

1. **CooldownManager.mqh** (new): tracks the last 3 closed trades per
   symbol. **Trigger (user-specified, 2026-07-21):** if all 3 of the
   last 3 trades on a symbol are losses AND their combined $ P/L is
   negative, block new entries on that symbol for a configurable
   duration (input parameter, default within the user's stated 1-2 hour
   range — e.g. `InpCooldownMinutes = 90`). Reset: cooldown expires
   purely on elapsed time (no early-reset-on-win rule was specified —
   do not invent one; if a future session wants an early-reset
   condition, that's a spec amendment, not an assumption here).
2. **Durable intent record** (new, likely in `StateManager.mqh` or a
   sibling module): before submitting an order, persist a
   `GlobalVariableSetOnCondition`-guarded intent record (symbol,
   direction, size, timestamp); clear it on confirmed fill or confirmed
   rejection. On EA restart, reconcile any orphaned intent record
   against actual open positions before resuming normal operation.
3. **Regime-gating wiring**: `EvaluateAndJournal` must call
   `MRE_IsUntradeableSpreadOrLiquidity` and `MRE_ApplyHysteresis` before
   using the regime result, and check `NEWS_BLACKOUT` before allowing
   entry — all three gates composed in one place, not scattered.
4. **News data source (user-specified, 2026-07-21):** high-impact
   calendar events for `NEWS_BLACKOUT` are to be sourced from the
   FairEconomy calendar feed (the free JSON calendar widely used by MT5
   news-filter EAs, e.g. `nfs.faireconomy.net/ff_calendar_thisweek.json`
   — exact current URL/format must be verified against what's live when
   this task starts, these endpoints drift). This needs:
   - A new `FairEconomyNewsProvider` implementing `NewsManager.mqh`'s
     existing provider interface (alongside `MT5CalendarProvider`/
     `NullNewsProvider`), parsing that feed's JSON into the same
     blackout-window structure the other providers produce.
   - `WebRequest` for that exact host added to the MT5 terminal's
     allowed-URLs list (Tools -> Options -> Expert Advisors) — this is a
     terminal-settings change only the user can make locally; it cannot
     be scripted from here.
   - A caching/refresh strategy (e.g. re-fetch once per session start,
     not per-tick) so the EA doesn't depend on network latency inside
     the trading loop.
   - Explicit fallback behavior if the feed is unreachable (fail closed
     — treat as blackout/untradeable — not fail open).
5. Journal every gate decision (which gate fired, if any) so Python-side
   analysis (`join_news_events.py` et al.) has real data to validate
   against once this ships.

## Files affected

- New `03_SOURCE_CODE/MQL5/.../CooldownManager.mqh` + test script.
- `StateManager.mqh` or a new durable-intent module + test script.
- `ThembaAdaptiveIntradayEA.mq5` (`EvaluateAndJournal` wiring).
- `TASKS.md` and this task file.

No file under `01_BASELINE/` may be modified.

## Out of scope

- Flipping `InpEnableOrderSubmission` to `true` — that remains a
  separate, explicit, human-approved decision per
  [[feedback-workflow]]'s established pause point.
- The "momentum-failure exit" and exit-engine wiring (TASK-030's gap) —
  separate task, no formula exists yet for the former.

## Risks

- Getting the cooldown reset condition or intent-reconciliation-on-
  restart logic wrong is a real-money-adjacent risk once order submission
  is ever enabled — needs hand-verified test cases for every edge case
  (EA restart mid-flight order, exactly-three-losses boundary, etc.),
  not just the happy path.
- Composing three gates in one call site risks short-circuit bugs (e.g.
  news gate silently skipped if spread gate returns early) — needs
  explicit test coverage for every gate-combination.

## Test plan

1. Compile clean in MetaEditor, 0 errors/0 warnings, real log evidence.
2. Hand-verified test script covering: 3 consecutive losses with net
   negative $ P/L triggers cooldown; a win within the last 3 trades
   does NOT trigger it; cooldown blocks entry on that symbol only
   (other symbols unaffected); cooldown expires after the configured
   duration elapses, not before.
3. Hand-verified test script for durable intent: normal fill clears it;
   simulated restart with an orphaned intent record reconciles
   correctly against both a filled and a never-filled scenario.
4. Hand-verified test script for gate composition: each of
   spread/liquidity, hysteresis, and news blackout independently blocks
   entry, and all three compose correctly (no short-circuit skipping).
5. Runtime verification (attach to a real/demo chart) — still batched
   project-wide, but flag explicitly if this task is the one that
   finally unblocks it.

## Acceptance criteria

- [ ] CooldownManager built, tested, wired into `EvaluateAndJournal`.
- [ ] Durable intent record built, tested (incl. restart-reconciliation),
      wired into the order-submission path.
- [ ] Regime-gating (spread/liquidity + hysteresis + news blackout)
      composed and wired into `EvaluateAndJournal`.
- [ ] Every gate decision is journaled.
- [ ] Independent review completed and findings resolved.

## Rejection criteria

Reject if any gate is wired in isolation without the other two (per
TASK-029's own stated reason for deferring), if the cooldown reset rule
or intent-reconciliation logic is invented rather than traced to spec,
or if `InpEnableOrderSubmission` is flipped as part of this task.

## Status

Not started — drafted while TASK-028's Codex review was in progress, as
the "Specify" step for the next branch once review findings (if any)
are resolved and TASK-028 is ready to hand off. Not yet added to
`TASKS.md` — pending user confirmation this is the right next priority.
