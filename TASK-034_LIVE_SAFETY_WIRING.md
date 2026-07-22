# TASK-034 - Live safety wiring: cooldown, durable intent, regime-gating

## Objective

Wire together three safety-critical pieces into the live EA. **Only one
of the three already exists as a tested standalone module** (Codex
review finding, 2026-07-22, third round: this section previously implied
all three pre-existed, which contradicts item 1/2 below, each of which
says plainly "no module exists" — corrected here):

1. Three-loss-per-symbol cooldown (spec section 8) — no module exists
   yet; must be built from scratch as part of this task.
2. Durable-intent / idempotency persistence (spec section 12) — no
   module exists yet; must be built from scratch as part of this task.
3. Regime-gating (`MRE_IsUntradeableSpreadOrLiquidity`,
   `MRE_ApplyHysteresis`, both built in TASK-016) + `NewsManager.mqh`'s
   `NEWS_BLACKOUT` (TASK-029) — this is the one piece that already
   exists as tested standalone modules, built but never called from
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
   - **Metal/synthetic provider-selection rule, added 2026-07-22 (Codex
     review finding, sixth round -- this item previously built the
     provider but never stated WHEN to actually route to it):**
     `PROJECT_RULES.md` rules 7-8 require "macroeconomic news filters
     apply to metals, not Deriv synthetic indices" and separate
     per-instrument-class profiles. This wiring must therefore select
     `FairEconomyNewsProvider` (or `MT5CalendarProvider`) for a metal
     symbol and `NullNewsProvider` for a synthetic-index symbol -- never
     apply the macro blackout to a synthetic index. **This selection
     needs a live `market_family` classification, which no numbered task
     currently builds** (see `00_MASTER_PROMPT_FOR_CLAUDE.md`'s
     `IntradayModeRouter` requirement and
     `TASK-036_JOURNAL_PRODUCER_COMPLETION.md`'s own disclosure that
     `market_family`/`intraday_mode` depend on a "still-unregistered
     future task") -- this task must NOT invent an ad hoc symbol-name
     heuristic to route around that missing dependency; if the real
     classifier is not ready when this task starts, this specific
     sub-item is blocked on it and must be named as blocked, not
     silently worked around.
5. Journal every gate decision (which gate fired, if any) so Python-side
   analysis (`join_news_events.py` et al.) has real data to validate
   against once this ships.

## Files affected

- New `03_SOURCE_CODE/MQL5/.../CooldownManager.mqh` + test script.
- `StateManager.mqh` or a new durable-intent module + test script.
- `ThembaAdaptiveIntradayEA.mq5` (`EvaluateAndJournal` wiring).
- **New `03_SOURCE_CODE/MQL5/Include/ThembaEA/News/FairEconomyNewsProvider.mqh`
  + test script (added, 2026-07-22 Codex review finding, fifth round --
  Specification item 4 fully specifies this provider, caching/refresh
  strategy, and fail-closed fallback, but this file previously omitted
  it entirely, so the task could be marked complete without it ever
  being built).**
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
5. **Hand-verified test script for `FairEconomyNewsProvider` (added,
   2026-07-22 Codex review finding, fifth round): parses a real captured
   feed sample into the correct blackout-window structure; the
   caching/refresh strategy does not re-fetch mid-trading-loop; and an
   unreachable/malformed feed fails CLOSED (treated as blackout), not
   open.**
6. **Synthetic-bypass acceptance test (added, 2026-07-22 Codex review
   finding, sixth round): a decision on a Deriv synthetic-index symbol
   must NOT have the macro news blackout applied, even during a real,
   currently-active FairEconomy blackout window that WOULD block a metal
   symbol at the same instant -- confirms `PROJECT_RULES.md` rule 8 is
   actually enforced, not just a provider that exists. This test is
   itself blocked on a live `market_family` classification (see
   Specification item 4's own note) -- if that dependency is not ready,
   this test must be reported as blocked, not skipped silently.**
7. Runtime verification (attach to a real/demo chart) — still batched
   project-wide, but flag explicitly if this task is the one that
   finally unblocks it.

## Acceptance criteria

- [x] CooldownManager built, tested, wired into `EvaluateAndJournal` —
      `CooldownManager.mqh` (new), `Test_CooldownManager.mq5`, wired as
      `AttemptOrderSubmission`'s new step 0 and fed by
      `ThembaAdaptiveIntradayEA.mq5`'s new `OnTradeTransaction` handler.
- [x] Durable intent record built, tested (incl. restart-reconciliation),
      wired into the order-submission path — `IntentManager.mqh` (new),
      `Test_IntentManager.mq5`, wired around step 7's `OM_OpenPosition`
      call; `IM_ReconcileOnRestart` called from `OnInit`.
- [x] Regime-gating (spread/liquidity + hysteresis + news blackout)
      composed and wired into `EvaluateAndJournal` —
      `RegimeGateComposer.mqh` (new), `Test_RegimeGateComposer.mq5`; the
      composed effective regime now feeds every strategy evaluation and
      `STR_RouteCandidates`, replacing the raw, un-gated classifier read.
- [x] `FairEconomyNewsProvider` built, tested (parsing, caching/refresh,
      fail-closed fallback), and wired in as `NewsManager.mqh`'s live
      provider (added, 2026-07-22 Codex review finding, fifth round --
      previously omitted from acceptance despite being fully specified
      in Specification item 4, so the task could pass without it) —
      `FairEconomyNewsProvider.mqh` (new), `Test_FairEconomyNewsProvider.mq5`;
      wired in via the new `InpNewsProviderSource` input (see next item).
- [ ] **BLOCKED, not silently skipped, per this item's own instruction:**
      Metal/synthetic provider-selection rule enforced and proven by the
      synthetic-bypass test (Test plan item 6) -- this still needs a live
      `market_family` classification that no numbered task yet builds
      (TASK-028 P0-3 / `IntradayModeRouter`). What IS wired: a new,
      EXPLICIT, operator-set `InpNewsProviderSource` input
      (`ENUM_NEWS_PROVIDER_SOURCE`: `NEWS_PROVIDER_MT5_CALENDAR` default /
      `NEWS_PROVIDER_FAIR_ECONOMY` / `NEWS_PROVIDER_NONE`) that the
      deploying operator sets per symbol/chart -- documented in the input's
      own header comment as a stand-in, not an automatic per-symbol
      heuristic, and NOT a substitute for this acceptance item. Automatic
      routing must replace this manual input once TASK-028 P0-3 ships (next
      in this session's own priority order).
- [x] Every gate decision is journaled — `EvaluateAndJournal` builds a
      `gate_reasons` array (raw regime, effective regime, which gate(s)
      fired) every bar regardless of decision outcome, merged into
      `decision.reasons_passed_json`/`reasons_rejected_json`.
- [ ] Independent review completed and findings resolved — pending the
      user's own consolidated, end-of-sprint Codex review (see
      `TASKS.md`'s TASK-028 row / this project's 2026-07-22 sprint
      directive), not a per-task review this time.

## Implementation notes (added 2026-07-22, real evidence)

- `ThembaAdaptiveIntradayEA.mq5` compiles clean (0 errors, 0 warnings,
  MetaEditor64.exe) with every module above included and wired.
- `Test_CooldownManager.mq5`, `Test_IntentManager.mq5`,
  `Test_RegimeGateComposer.mq5`, and `Test_FairEconomyNewsProvider.mq5`
  each compile clean (0 errors, 0 warnings). Per this project's
  established discipline (see `Test_StateManager.mq5`/`Test_OrderManager.mq5`),
  these are MetaEditor-compilable PASS/FAIL scripts, not an automated
  test framework — actually running them and reading the Experts log for
  PASS/FAIL lines remains the user's own manual desktop-MT5 step, same as
  every other test script in this project (this sandbox cannot attach to
  a live/demo terminal — see `feedback_runtime_verification_batched.md`).
- The cooldown reset rule and intent-reconciliation policy were traced
  directly to this file's own Specification items 1/2, not invented; see
  each module's own header comment for the exact reasoning.

## Rejection criteria

Reject if any gate is wired in isolation without the other two (per
TASK-029's own stated reason for deferring), if the cooldown reset rule
or intent-reconciliation logic is invented rather than traced to spec,
or if `InpEnableOrderSubmission` is flipped as part of this task.

## Status

In progress — CooldownManager, durable intent, and the composed
spread/liquidity+hysteresis+news-blackout gate are built, wired, and
compile clean (real MetaEditor evidence, 2026-07-22). The metal/synthetic
AUTOMATIC provider-selection sub-item (Specification item 4's last
paragraph, Test plan item 6) remains explicitly BLOCKED on TASK-028 P0-3's
still-unbuilt `market_family` classifier, per that item's own instruction
not to invent a workaround — not silently skipped, and not claimed done.
Independent review deferred to this project's single, consolidated,
end-of-sprint Codex review per the user's own 2026-07-22 directive, not a
per-task review this time.
