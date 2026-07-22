# TASK-036 - Journal producer completion

## Objective

Close the remaining MQL5-side journal-population gaps that block real
Python-side analysis: populate `signal_id`, `market_family`,
`intraday_mode`, `news_state`, and `session_state` (all currently
written as empty strings by `DJ_NewDecision`), populate the durable
`order_id`/`deal_id` fields (schema side already done -- see below),
populate `score_breakdown_json` with `SignalScorer.mqh`'s real
per-component values (added, 2026-07-22 Codex review finding, third
round -- see item 6 below), and fix the `FILE_ANSI`-vs-UTF-8
cross-language encoding mismatch between `DecisionJournal.mqh` and the
Python journal reader.

**Scope narrowed, 2026-07-22 (Codex review finding #3, third round):**
the Python-side half of the `order_id`/`deal_id` work -- adding the
fields to `analysis/schema.py`'s `TradeDecision` AND building the actual
consuming join pipeline -- is now DONE (`analysis/join_signal_to_outcome.py`,
real and tested against synthetic order_id/deal_id values). This task's
remaining scope is MQL5-only: add `order_id`/`deal_id` to `STradeDecision`
and populate them from `OrderManager.mqh`'s fill confirmation. Codex's
finding #3 specifically flagged that this task's own Out-of-scope
section previously EXCLUDED building the join while its Test-plan
section simultaneously REQUIRED running it end-to-end -- both are fixed
below.

## Reason

Codex's TASK-028 review (finding #2, second round) found that every one
of these gaps was either undocumented as a follow-up owner or newly
discovered during that remediation round:

- `market_family`/`intraday_mode`/`news_state` were already known-empty
  (documented in `analysis/schema.py`'s own docstring), but `session_state`
  is ALSO always empty (`DecisionJournal.mqh:92`) -- not previously
  flagged as part of the same gap.
- No `order_id`/`deal_id` field existed anywhere in `STradeDecision` or
  the Python schema, so a journal decision could never be durably joined
  to its eventual trade outcome -- blocking `analysis/performance_breakdown.py`
  (TASK-028) from ever running against real data. **The Python-side half
  of this (schema field + join pipeline) is now closed -- see Objective.**
- `DecisionJournal.mqh:205` opens its file with `FILE_ANSI`; the Python
  reader decodes UTF-8 -- byte-identical for pure ASCII today, but a
  latent, untested cross-language contract mismatch.

A third review round (finding #3) additionally found this task's own
Out-of-scope/Test-plan contradiction described above.

**Added, 2026-07-22 (Codex review finding, third round):** `DecisionJournal.mqh`'s
`STradeDecision` already has a `score_breakdown_json` field (defaults to
`"{}"`), but nothing anywhere in the codebase ever populates it --
`Test_DecisionJournal.mq5` only asserts the empty default. This left an
unowned gap across three task files: `TASK-032_SCORE_CORRELATION_ANALYSIS.md`
step 1 correctly IDENTIFIES that the correlation analysis cannot run
against real data until per-component scores are journaled, but never
assigns an owner for actually populating them; `TASK-037_MT5_EXPORT_BRIDGE.md`
exports trade/news/pattern data but not per-decision score breakdowns.
This task is the natural owner (it already populates every other
currently-empty `STradeDecision` field from live EA state) and now
explicitly closes it -- see Specification item 6.

## Baseline behaviour

Neither immutable baseline EA has a decision journal at all -- this is
new-engine-only functionality. `01_BASELINE/` must not be modified.

## Evidence

- `03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh:33,37-38,55,71-75,92,150-169,205`
  -- the empty-default fields and the `FILE_ANSI` flag.
- `analysis/schema.py`'s own docstring -- the already-documented
  market_family/intraday_mode gap.
- `09_HANDOVERS/codex_to_claude/TASK-028_review.md` finding #2 -- the
  full list of gaps this task closes.
- `TRADE_DECISION_SCHEMA.json` -- the schema both sides must stay
  field-for-field consistent with once extended.

## Specification

1. Populate `signal_id` with a genuinely unique per-decision identifier
   at the point `ThembaAdaptiveIntradayEA.mq5` calls `DJ_NewDecision`
   (e.g. a composite of symbol + timestamp + an in-process counter --
   exact scheme is this task's own design decision, not prescribed here).
2. Populate `market_family`/`intraday_mode` from whatever the EA's own
   mode-routing logic already knows at decision time (these are
   presumably already computed somewhere in the strategy-routing chain;
   this task wires the existing value into the journal record, it does
   not invent new classification logic). **Corrected, 2026-07-22 Codex
   review finding (fifth round): no such mode-routing/`market_family`
   classifier logic actually exists in the current EA source --
   `TASK-006_SESSION_MANAGER.md` explicitly deferred it, and
   `analysis/schema.py`'s own docstring already documents that
   `ThembaAdaptiveIntradayEA.mq5` never sets either field today.** This
   item was BLOCKED on a still-unregistered future task to build that
   classifier first. **UNBLOCKED, 2026-07-22: TASK-040
   (`IntradayModeRouter.mqh`) built and wired both classifiers into
   `ThembaAdaptiveIntradayEA.mq5` the same day** — `g_market_family` is
   classified once at `OnInit`, and `intraday_mode` is computed every bar
   in `EvaluateAndJournal`, currently journaled via the free-form
   `reasons_passed_json`/`reasons_rejected_json` string arrays (no
   `STradeDecision` schema fields exist for them yet). This task's own
   remaining scope is exactly as originally stated: wire those
   ALREADY-COMPUTED values into proper `market_family`/`intraday_mode`
   schema fields on `STradeDecision`/the journal record, not invent the
   classification logic (that part is now done, by TASK-040).
3. Populate `news_state`/`session_state` from `NewsManager.mqh`'s actual
   blackout check and `SessionManager.mqh`'s actual session-remaining
   computation respectively, at decision time. **Session-state bucket
   mapping, corrected 2026-07-22 (Codex review finding, fifth round: the
   fourth-round `OPEN`/`CLOSING_SOON`/`CLOSED` mapping below was
   source-invalid -- `SN_GetSessionMinutesRemaining` returns `1.0`
   *before the first session even opens*, not only while genuinely
   mid-session, so labelling high-ratio time as `"OPEN"` mislabels
   pre-open time and inter-session gaps as open; mapping every `false`
   return to `"CLOSED"` turned a genuine "no session today / unreadable
   data" failure into a fabricated closed-session observation, violating
   that function's own documented "exclude it, never default it" rule):**
   `SessionManager.mqh`'s `SN_GetSessionMinutesRemaining` returns a
   continuous `remaining_ratio` in `[0, 1]`, not a discrete label, and
   returns `false` (never a ratio) for no session today or unreadable
   session data. Map it to one of three buckets, none of which claim an
   open/closed judgement the ratio cannot support: `remaining_ratio >= 0.5`
   -> `"SESSION_TIME_REMAINING_HIGH"`; `remaining_ratio < 0.5` ->
   `"SESSION_TIME_REMAINING_LOW"`; `SN_GetSessionMinutesRemaining` returns
   `false` -> `"SESSION_TIME_REMAINING_UNKNOWN"` (excluded from any
   HIGH/LOW judgement, never defaulted into either). These three exact
   string values are what `analysis/performance_breakdown.py`'s
   `session_state` dimension and notebook 04's synthetic session
   breakdown already assume -- use them verbatim, not a different or ad
   hoc set (and not the superseded `OPEN`/`CLOSING_SOON`/`CLOSED` set
   from the fourth round).
4. Add `order_id`/`deal_id` (nullable -- a decision that was rejected
   before order submission has neither) to `STradeDecision` and populate
   them once `OrderManager.mqh` confirms a fill. (The Python-side field
   -- `analysis/schema.py`'s `TradeDecision.order_id`/`deal_id` -- already
   exists; this is the matching MQL5-side population.) **`order_id` MUST
   be populated from `SOrderOpenResult.position_id` (MT5's
   `POSITION_IDENTIFIER`), NEVER `position_ticket` (Codex review finding,
   2026-07-22, sixth round, TASK-028's own P0 finding 1) -- MT5 documents
   `POSITION_TICKET` as changeable after a server-side service re-open or,
   in netting mode, a reversal, while `POSITION_IDENTIFIER` is documented
   as constant for the position's entire life and is what every related
   deal itself carries back as `DEAL_POSITION_ID`. `position_ticket`
   remains useful for THIS session's own immediate close/modify calls
   (which the live MT5 API itself requires), but must never be journaled
   as the durable `order_id`.**

   **Asynchronous fill correlation, added explicitly (Codex review
   finding, 2026-07-22, fifth round -- previously entirely unaddressed):**
   `OM_OpenPosition` (`OrderManager.mqh`) treats `TRADE_RETCODE_DONE` and
   `TRADE_RETCODE_PLACED` identically, immediately scanning
   `PositionsTotal()` for the resulting position right after the trade
   call. For a genuinely synchronous `DONE` fill this works; for
   `PLACED` (order accepted but not necessarily filled yet on every
   broker/execution model), the position may not exist at that scan
   point, so both `result.position_ticket` and `result.position_id` can
   come back `0` with no later mechanism to correlate a subsequent async
   fill back to the journal decision that triggered it. This task must
   (a) journal the decision once immediately after submission (as
   today), recording whichever identifiers ARE available at that point
   plus the raw `retcode`; (b) add an
   `OnTradeTransaction` handler that detects a LATER fill for a
   previously-`PLACED`-but-unconfirmed order and updates that journal
   decision's `order_id`/`deal_id` (or appends a correlated follow-up
   record -- pick one design and document why, do not leave the choice
   implicit); (c) define what happens if the async fill never arrives
   (order cancelled/expired) -- the journal record must not be left
   silently implying an open position that was never actually filled.
   `OrderManager.mqh` is therefore also a file this task modifies, not
   only `DecisionJournal.mqh`/the EA's synchronous journal call site.
5. Fix the encoding mismatch: change `DecisionJournal.mqh`'s `FileOpen`
   flags to write UTF-8 (MQL5's `FILE_ANSI` flag must be removed/replaced
   with whatever combination produces real UTF-8 output -- verify against
   an actual non-ASCII test case, not assumed).
6. **Added, 2026-07-22 Codex review finding (third round):** populate
   `score_breakdown_json` with `SignalScorer.mqh`'s actual per-component
   contributions (BOS/displacement, pin-bar/wick, EMA evidence, and
   whichever other components `SS_ComputeBaseScore`/its callers compute
   at decision time) serialized as a real JSON object, not the
   placeholder `"{}"`. Field names must match whatever
   `TASK-032_SCORE_CORRELATION_ANALYSIS.md`'s correlation module expects
   to consume -- coordinate the exact key names with that task rather
   than inventing them independently in each.

## Files affected

- `03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh`
- `03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5` (including a
  new `OnTradeTransaction` handler for async `PLACED`-then-later-fill
  correlation -- added, 2026-07-22 Codex review finding, fifth round)
- `03_SOURCE_CODE/MQL5/Include/ThembaEA/Execution/OrderManager.mqh`
  (added, 2026-07-22 Codex review finding, fifth round -- previously
  omitted despite Specification item 4's async-fill correlation work
  requiring changes here)
- `TRADE_DECISION_SCHEMA.json`
- `03_SOURCE_CODE/Python/analysis/schema.py`
- `03_SOURCE_CODE/Python/data_collection/journal_reader.py` (remove the
  now-fixed encoding caveat from its docstring once verified)
- `TASKS.md` and this task file

No file under `01_BASELINE/` may be modified.

## Out of scope

- Any change to order-submission behavior itself.
- Further changes to `analysis/join_signal_to_outcome.py` or
  `analysis/schema.py`'s `order_id`/`deal_id` fields -- both already
  exist and are tested; this task only populates the MQL5 side that
  feeds them.

## Risks

- A non-ASCII value (accented character in a comment/name) is the only
  realistic way to test the encoding fix for real -- needs a deliberate
  test case, not just an ASCII smoke test that would pass either way.
- Getting `order_id`/`deal_id` population wrong (e.g. recording the
  wrong deal on a partial fill) would corrupt every downstream join
  silently -- needs explicit test coverage for partial fills/rejections.
- **A `PLACED`-but-not-yet-`DONE` order whose fill only arrives later via
  `OnTradeTransaction` (added, 2026-07-22 Codex review finding, fifth
  round): if the async correlation step is wrong, a journal decision can
  silently keep a null/stale `order_id`/`deal_id` forever, or worse,
  correlate to the WRONG later transaction -- needs explicit test
  coverage for a delayed fill, a cancelled/expired `PLACED` order, and
  two overlapping `PLACED` orders resolving out of submission order.**

## Test plan

1. Compile clean in MetaEditor, 0 errors/0 warnings, real log evidence.
2. A hand-verified test script confirming every one of the five fields
   is populated (non-empty/non-null as appropriate) in a real
   `DJ_NewDecision` call for a representative decision.
3. A non-ASCII test case proving the encoding fix round-trips correctly
   through both the MQL5 writer and the Python reader.
4. Run `analysis/join_signal_to_outcome.py` (already built and tested
   against synthetic order_id values) against a small REAL journal +
   trade export once `order_id`/`deal_id` are populated by the live EA,
   confirming the join actually works end-to-end on real data -- the
   first "Real-data run" for this specific pipeline, not just another
   synthetic-fixture pass.
5. **Hand-verified test script for asynchronous fill correlation (added,
   2026-07-22 Codex review finding, fifth round): a `PLACED` order whose
   fill arrives on a LATER `OnTradeTransaction` call correctly updates
   (or correlates to) the original journal decision's `order_id`/
   `deal_id`; a `PLACED` order that is subsequently cancelled/expired
   without ever filling does not leave the journal record silently
   implying an open position.**

## Acceptance criteria

- [ ] All five fields (signal_id, market_family, intraday_mode,
      news_state, session_state) populated by the live EA.
- [ ] order_id/deal_id populated by the live EA on fill (schema-side
      already done).
- [ ] **Asynchronous `PLACED`-then-later-fill correlation implemented via
      `OnTradeTransaction` and hand-verified (added, 2026-07-22 Codex
      review finding, fifth round -- previously unaddressed; without
      this, a delayed real fill leaves `order_id`/`deal_id` null forever
      and the join in acceptance item below silently only ever exercises
      the synchronous `DONE` path).**
- [ ] score_breakdown_json populated with real per-component score
      values (added, 2026-07-22 Codex review finding, third round).
- [ ] FILE_ANSI/UTF-8 mismatch fixed and verified with a non-ASCII case.
- [ ] `join_signal_to_outcome.py` run against real data at least once,
      result reported (not left as another synthetic-only pass).
- [ ] Independent review completed and findings resolved.

## Rejection criteria

Reject if any field is populated with a placeholder/constant value
rather than the real computed one, or if the encoding fix is claimed
without a non-ASCII test actually exercising it.

## Status

Not started (MQL5 side). Registered per Codex's TASK-028 review finding
#2 (2026-07-22); scope narrowed and Out-of-scope/Test-plan contradiction
fixed per finding #3 of the third review round (2026-07-22) -- the
Python-side schema fields and the consuming join pipeline
(`analysis/join_signal_to_outcome.py`) are already built and tested.
