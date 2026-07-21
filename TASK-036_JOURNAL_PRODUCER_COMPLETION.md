# TASK-036 - Journal producer completion

## Objective

Close the MQL5-side journal-population gaps that block real Python-side
analysis: populate `signal_id`, `market_family`, `intraday_mode`,
`news_state`, and `session_state` (all currently written as empty
strings by `DJ_NewDecision`), add durable `order_id`/`deal_id` fields for
signal-to-outcome joins, and fix the `FILE_ANSI`-vs-UTF-8 cross-language
encoding mismatch between `DecisionJournal.mqh` and the Python journal
reader.

## Reason

Codex's TASK-028 review (finding #2) found that every one of these gaps
was either undocumented as a follow-up owner or newly discovered during
this remediation round:

- `market_family`/`intraday_mode`/`news_state` were already known-empty
  (documented in `analysis/schema.py`'s own docstring), but `session_state`
  is ALSO always empty (`DecisionJournal.mqh:92`) -- not previously
  flagged as part of the same gap.
- No `order_id`/`deal_id` field exists anywhere in `STradeDecision` or
  the Python schema, so a journal decision can never be durably joined to
  its eventual trade outcome -- blocking `analysis/performance_breakdown.py`
  (TASK-028) from ever running against real data, and blocking any
  strategy/regime/session performance breakdown from being anything more
  than a synthetic-fixture proof of concept.
- `DecisionJournal.mqh:205` opens its file with `FILE_ANSI`; the Python
  reader decodes UTF-8 -- byte-identical for pure ASCII today, but a
  latent, untested cross-language contract mismatch.

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
   before order submission has neither) to both `STradeDecision` and
   `analysis/schema.py`'s `TradeDecision`, populated once `OrderManager.mqh`
   confirms a fill.
5. Fix the encoding mismatch: change `DecisionJournal.mqh`'s `FileOpen`
   flags to write UTF-8 (MQL5's `FILE_ANSI` flag must be removed/replaced
   with whatever combination produces real UTF-8 output -- verify against
   an actual non-ASCII test case, not assumed).

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

- Building the actual signal-to-outcome JOIN pipeline that consumes
  `order_id`/`deal_id` -- that is `analysis/performance_breakdown.py`
  (already built, TASK-028) gaining real data, not new code here.
- Any change to order-submission behavior itself.

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
4. Run `analysis/performance_breakdown.py` against a small real (or
   realistically-shaped) joined dataset once `order_id`/`deal_id`
   exist, confirming the join actually works end-to-end.

## Acceptance criteria

- [ ] All five fields (signal_id, market_family, intraday_mode,
      news_state, session_state) populated by the live EA.
- [ ] order_id/deal_id added to both schemas and populated on fill.
- [ ] FILE_ANSI/UTF-8 mismatch fixed and verified with a non-ASCII case.
- [ ] Independent review completed and findings resolved.

## Rejection criteria

Reject if any field is populated with a placeholder/constant value
rather than the real computed one, or if the encoding fix is claimed
without a non-ASCII test actually exercising it.

## Status

Not started. Registered per Codex's TASK-028 review finding #2
(2026-07-22).
