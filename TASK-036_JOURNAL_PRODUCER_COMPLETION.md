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
   not invent new classification logic).
3. Populate `news_state`/`session_state` from `NewsManager.mqh`'s actual
   blackout check and `SessionManager.mqh`'s actual session-remaining
   computation respectively, at decision time.
4. Add `order_id`/`deal_id` (nullable -- a decision that was rejected
   before order submission has neither) to `STradeDecision` and populate
   them once `OrderManager.mqh` confirms a fill. (The Python-side field
   -- `analysis/schema.py`'s `TradeDecision.order_id`/`deal_id` -- already
   exists; this is the matching MQL5-side population.)
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
- `03_SOURCE_CODE/MQL5/Experts/ThembaAdaptiveIntradayEA.mq5`
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

## Acceptance criteria

- [ ] All five fields (signal_id, market_family, intraday_mode,
      news_state, session_state) populated by the live EA.
- [ ] order_id/deal_id populated by the live EA on fill (schema-side
      already done).
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
