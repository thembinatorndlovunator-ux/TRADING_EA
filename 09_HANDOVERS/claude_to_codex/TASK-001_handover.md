# Claude-to-Codex Handover: TASK-001 Baseline Audit

## Changed files

All new documentation, no code changes, all on branch
`claude/task-001-baseline-audit` (based off `main` at commit `947867c`):

- `TASKS.md`
- `TASK-001_BASELINE_AUDIT.md`
- `01_BASELINE/inventory.md`
- `01_BASELINE/screenshots/visual_notes.md`
- `baseline_v637_audit.md`
- `baseline_v811_audit.md`
- `baseline_comparison.md`
- `profit_giveback_diagnosis_plan.md`
- this file

Nothing under `01_BASELINE/EA_V637/`, `01_BASELINE/EA_V811/`, or
`01_BASELINE/setfiles/` was modified — verified via `git diff baseline-v637`
/ `git diff baseline-v811` (both empty) and fresh `sha256sum` matching
`IDENTITY.md`.

## Audit method

Two independent agent passes, one per baseline EA, each given the exact
audit checklist from `00_MASTER_PROMPT_FOR_CLAUDE.md` section 4 for their
assigned file and instructed to re-verify every line number by reading the
source directly (not trust a prior structural-survey map). Every finding in
both `baseline_v637_audit.md` and `baseline_v811_audit.md` is labeled FACT,
COMMENT-CLAIMED (with a checks-out/does-not-check-out verdict),
CONTRADICTION, or HYPOTHESIS. This is a **static reading only** — neither
file was compiled, backtested, or run.

## Assumptions made

- The set file `01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt` belongs to
  neither baseline (reasoning in `baseline_comparison.md` — no `Inp`-prefixed
  keys, uses INI sections no native `.set` file has, section names mirror
  the *planned new engine's* module names rather than either baseline's
  actual code organization). **Please independently check this reasoning**
  — if you can identify an actual source for this file, that would resolve
  a currently-open provenance question.
- Screenshot content was read directly (13 images viewed), not inferred
  from filenames; all interpretations are labeled hypotheses since no trade
  journal/CSV exists yet to confirm marker attribution to either EA.
- The severity labels ("Yes — matters for live trading" vs. "Depends on
  evidence") in both audits' summary tables are the auditing agent's
  judgment from reading control flow alone, not from any observed runtime
  behavior. Please check these judgments independently, especially the two
  flagged as highest-severity below.

## Known risks / gaps

1. **V6.37 — `CloseAllOurPositions` (lines 3389–3414) filters its
   position-closing loop by magic number only**, not by symbol, unlike
   every other position-scanning function in the file and unlike its own
   sibling pending-order-deletion loop three lines below it.
   `GetTodayClosedProfit`/`GetOpenProfitForMagic` (3325–3387), which feed
   the daily-limit computation that triggers this close-all, have the same
   symbol-filter omission. **Question for Codex:** please independently
   trace every call site of `CloseAllOurPositions` and confirm/refute that
   a multi-symbol deployment under the default shared magic number
   (`InpMagicNumber=312003`) would force-close unrelated, profitable
   positions on other symbols when one symbol trips the daily loss limit.

2. **V8.11 — a restart while a basket is open appears to permanently
   disable break-even, runner-trail, giveback-guard, time-exit, and
   direction-flip-exit management for that basket**, because
   `g_basket_dir`/`g_basket_risk`/etc. (lines 230–236) are plain in-memory
   globals never persisted or reconstructed from open positions in `OnInit`
   (255–281), `ManageBasket` short-circuits at lines 1416–1417 when they're
   zero, and the entry gate (`OnTick` 307–308) blocks any new basket from
   forming while the orphaned positions remain open — while the dashboard
   (2059–2077) reports `"Basket: flat"`. **Question for Codex:** please
   independently verify this restart-state trace, and check whether MQL5's
   `OnInit`/position-iteration APIs (`PositionsTotal`/`PositionSelectByTicket`/
   `PositionGetInteger(POSITION_MAGIC)`) could actually reconstruct
   `g_basket_*` state from currently-open positions matching the EA's magic
   number+symbol — i.e. is there a straightforward fix available, or does
   the basket model (shared entry price/risk assumption across legs) make
   reconstruction fundamentally lossy?

3. **Netting vs. hedging compatibility** — neither audit explicitly traced
   account-mode behavior (`ACCOUNT_MARGIN_MODE`) for either EA's
   multi-position logic (V6.37's pilot+add-ons stacking same-direction
   positions; V8.11's 1–4 leg baskets). Please check whether either EA's
   position-counting/management logic (`CountOurPositions`,
   `CountOurPositions` equivalents) behaves correctly on both netting and
   hedging accounts, since both models assume multiple simultaneous
   same-symbol positions can coexist and be individually tracked by ticket.

4. **Broker filling-mode / stop-level / freeze-level handling** — V6.37's
   `EnsureValidStops` (line 2988) and V8.11's stop-clamp logic were read as
   present but not independently stress-tested against a real broker's
   `SYMBOL_TRADE_STOPS_LEVEL`/`SYMBOL_FILLING_MODE` values. Please verify
   these are actually broker-safe, not just internally consistent.

5. **Duplicate-entry protection** — please check both EAs' new-bar/one-
   signal-per-bar gating (`IsNewBar` equivalents) for edge cases around
   terminal reconnects or requote retries that might double-submit an
   order.

6. **News time-zone handling** — V6.37's NFP logic depends on an unverified
   server-time-to-NY-time offset that the code's own comment flags as
   needing manual per-broker verification (`InpNewsHourServer`/
   `InpNewsMinuteServer`, lines 190–191). Please assess whether this is
   safe to rely on for any live/demo deployment as-is.

7. **Overfitting/complexity risk** — V6.37 defines 307 inputs across
   ~13 signal generators with a 5-gate serial funnel; whether this is
   healthy conservatism or unworkable signal starvation is explicitly
   flagged in both audits as requiring backtest evidence this repo doesn't
   have yet. No code-review answer is expected here, just concurrence or
   disagreement on the risk framing.

## Commands run

```
git checkout -b claude/task-001-baseline-audit
git diff baseline-v637 -- 01_BASELINE/EA_V637
git diff baseline-v811 -- 01_BASELINE/EA_V811
sha256sum "01_BASELINE/EA_V637/Thembabot14 Max.mq5"
sha256sum "01_BASELINE/EA_V811/NdlovuSMC_V8.11.mq5"
sha256sum "01_BASELINE/setfiles/SmartCore_v3_Tuned.set.txt"
sha256sum "01_BASELINE/screenshots/"*.png
grep -n -i "giveback" both baseline files
```

## Compiler status

N/A — no code changed in this task.

## Tests run

N/A — no code changed; this task is a static documentation audit.

## Tests not run

Everything: compilation, unit fixtures, backtests, visual tests,
restart tests, multi-symbol tests. None of these are applicable yet because
no code has changed and no test harness exists for either baseline in this
repo. `TEST_PLAN.md`'s full protocol applies once the *new* engine has code
to test, not to these immutable baselines.

## Questions for Codex

Per `AGENTS.md` review priorities, specifically requesting independent
verification of:

- Look-ahead bias / repainting: do either EA's structure/OB/FVG/SR scans
  ever reference the in-formation current bar (index 0) in a decision path,
  or are all confirmed-pattern decisions genuinely closed-bar only, as both
  audits concluded?
- Candle indexing / array orientation: confirm the series-array direction
  assumptions in both audits' cited line ranges are correct (both files use
  `ArraySetAsSeries`-style indexing per the audits, but this wasn't
  exhaustively re-derived by hand for every function).
- Indicator-handle lifecycle: neither audit traced whether indicator
  handles (ATR, MA, RSI, MACD wrappers) are created once in `OnInit` and
  released in `OnDeinit`, or recreated per-tick (a common MQL5 handle-leak
  pattern). Please check.
- The two findings-of-highest-concern above (items 1 and 2 in "Known risks
  / gaps") — please independently confirm or refute both before they
  inform any new-engine design decisions.
- Whether the audits' "self-confirmed bypass" and "gate contradiction"
  findings in V6.37 (ROTATION vs. regime router) and V8.11 (momentum
  breakout vs. expansion filter) are accurately characterized, or whether
  there's a code path either audit missed that actually reconciles them.

Please produce a written review (per `AGENTS.md`: "Codex must produce a
written review before changing Claude's code") before any fixes are
applied — none are proposed in this task; this is audit only.
