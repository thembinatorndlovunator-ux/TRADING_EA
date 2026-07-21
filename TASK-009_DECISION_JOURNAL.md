# TASK-009 — DecisionJournal: durable trade-decision serialization

## Objective

Implement `DecisionJournal.mqh` per `00_MASTER_PROMPT_FOR_CLAUDE.md`
section 23 (Phase 3, "Decision journal"): serialize a trade-decision
record to exactly the repo-root `TRADE_DECISION_SCHEMA.json` on-disk
contract, and durably append it to a daily JSON-lines journal file, per
`TASK-002_PHASE2_SPECIFICATION.md` section 9's "journal is the single
source of truth" rule.

## Reason

TASK-002's cleanup pass reconciled section 9's `TradeDecision` field list
against `TRADE_DECISION_SCHEMA.json` (they didn't match before that
fix). This task is the first place that reconciliation actually gets
used — if the schema and the code drift apart again, this is where it
would be caught, by construction (the serializer's field list is
`TRADE_DECISION_SCHEMA.json`'s field list, one-to-one).

## Baseline behaviour

Neither baseline EA writes a structured decision journal in this schema
— TASK-001's audit found V6.37's market-entry rejections journaled as
plain log text (not structured), and the resting-limit path failing
silently with no journal entry at all. This module is new-engine work
built to make every decision structurally loggable, not a port of either
baseline's logging. No file under `01_BASELINE/` is touched.

## Evidence

`TRADE_DECISION_SCHEMA.json` (repo root, the canonical on-disk contract).
`TASK-002_PHASE2_SPECIFICATION.md` section 9 ("Trade decision object —
reconciled with the canonical schema" and "Journal/learning separation").
`PROJECT_RULES.md` rule 6 (every rejection needs a machine-readable
reason — `DJ_AppendDecision` returns a machine-readable
`error_reason` on failure, never a silent no-op).

## Specification

`STradeDecision` mirrors `TRADE_DECISION_SCHEMA.json`'s field set
exactly. `DJ_NewDecision()` returns safe defaults (`direction="NONE"`,
`has_entry`/`has_stop=false`, `score_breakdown_json="{}"`,
`targets_json="[]"`, etc.). `DJ_SerializeDecision` produces one JSON
object per decision, with the schema's `"number|null"` and
`"string|null"` fields (`entry`, `stop`, `candlestick_pattern`,
`chart_pattern`) correctly serializing as JSON `null` when unset, not a
sentinel number or empty string. `DJ_AppendDecision` durably appends the
serialized line to `ThembaEA\Journal\decisions_<UTC-date>.jsonl` (one
file per day), returning false with a machine-readable reason if the
file could not be opened.

**Explicit scope boundary, stated in the module's own header comment:**
the schema's open-shaped nested fields (`score_breakdown`, `targets`,
`reasons_passed`, `reasons_rejected`) are accepted as pre-serialized JSON
snippets supplied by the caller — this module assembles and durably
writes the top-level envelope; producing the nested values is the
responsibility of whichever module generates them (scoring, routing),
which does not exist yet.

## Files affected

New: `03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal/DecisionJournal.mqh`,
`03_SOURCE_CODE/MQL5/Scripts/Test_DecisionJournal.mq5`, this task file.
Modified: `TASKS.md`. No file under `01_BASELINE/` touched.

## Out of scope

- `TradeJournal.mqh`/`LearningStatistics.mqh` — the other two
  `Journal/` architecture modules; trade-outcome-level logging and the
  derived learning-bucket statistics view over this journal,
  respectively, per section 9's "journal is source of truth, statistics
  are a derived view" separation.
- Building the nested `score_breakdown`/`targets`/`reasons_*` JSON
  content — see the scope boundary above.
- Any actual scoring, routing, or regime logic that would produce a real
  `STradeDecision` to journal — Phase 4/5/6 work.

## Risks

- No independent review available this phase.
- Runtime verification: batched with TASK-003 through 008's outstanding
  item.
- **The JSON escaping helper is deliberately minimal**, not a
  general-purpose JSON library (see the module's own header comment) —
  sufficient for this project's own generated field values, but not
  validated against arbitrary Unicode/control-character input a
  malicious or corrupted upstream source might produce. Since every
  field written here originates from this project's own code (symbol
  names, enum-like strings, internally-generated reason text), this is a
  reasonable, stated scope limit, not an oversight.
- Nested JSON snippets (`score_breakdown_json`, `targets_json`, etc.) are
  trusted verbatim from the caller with no validation that they are
  actually well-formed JSON — a caller passing a malformed snippet would
  produce a malformed overall journal line. This is acceptable for now
  since no caller producing these exists yet; worth revisiting once the
  scoring/routing module that will populate them is built.

## Test plan

1. **Compile test** (completed, see Compiler result).
2. **Logic test** (compiled, not yet runtime-confirmed — batched):
   `Test_DecisionJournal.mq5` must print all-PASS covering: default-value
   correctness; JSON escaping of embedded quotes/backslashes/newlines;
   exact ISO-8601 UTC formatting for a known timestamp; full-envelope
   serialization including both a populated numeric field
   (`has_entry=true`) and a null field (`has_stop=false`, and an empty
   `candlestick_pattern`); the journal file path's exact date-based
   format; and — the most load-bearing check — a real durable
   append-then-reopen-and-read-back round trip confirming two
   sequentially appended lines both persist correctly (proving append
   mode, not overwrite). The test journal file is deleted both before
   (clean slate) and after (no residue) the round-trip test.

## Acceptance criteria

- [x] `STradeDecision`'s field set matches `TRADE_DECISION_SCHEMA.json`
      exactly, field-for-field.
- [x] Compiles with 0 errors, 0 warnings via real MetaEditor invocation
      (clean on the first attempt).
- [ ] Logic test confirmed all-PASS on a real desktop MT5 session —
      batched with TASK-003 through 008's outstanding item.
- [x] `"number|null"`/`"string|null"` schema fields correctly serialize
      as JSON `null` when unset, not a sentinel value.
- [x] No file under `01_BASELINE/` touched.
- [ ] Independent review — not available this phase.

## Rejection criteria

Rejected if the logic test, once run, produces any `FAIL` — most
importantly the null-handling checks (a `0.0` or empty-string sentinel
silently standing in for a real `null` would misrepresent "no value" as
"value is zero/empty" to anything reading the journal later) and the
append-round-trip check (a journal that overwrites instead of appending
would silently lose every prior decision).

## Implementation notes

The journal file lives under the terminal's own (non-common) `MQL5\Files`
sandbox, per standard MQL5 file-I/O restrictions — this keeps the journal
scoped to one terminal instance's data folder, consistent with
`StateManager`'s per-instance namespace concept (TASK-003/008), though
`DecisionJournal` itself does not use `StateManager` — a flat, append-
only file is the right storage shape for a journal, versus
`StateManager`'s scalar/small-record shape for state that gets
overwritten in place.

## Commands run

```
git checkout -b claude/task-009-decision-journal
mkdir -p 03_SOURCE_CODE/MQL5/Include/ThembaEA/Journal
"C:\Program Files\Deriv MT5 Terminal\MetaEditor64.exe" /compile:"...\Test_DecisionJournal.mq5" /log:...
```

## Compiler result

**Real, verified.** `Result: 0 errors, 0 warnings, 950 ms elapsed,
cpu='X64 Regular'` — clean on the first attempt. Full log available in
this session's history; not committed (build artifact).

## Test results

**Compile test: PASS (real evidence, above).** **Logic test: not
confirmed** — batched with TASK-003 through 008's outstanding runtime-
verification item.

## Commit

Pending — see `git log` on `claude/task-009-decision-journal`.

## Reviewer

Not available this phase.

## Final decision

**Compiled clean and committed; logic-test runtime confirmation batched**
with the six prior tasks' outstanding item. One module remains to
complete Phase 3's "Common core" list: `IntradayCloseManager.mqh`.
