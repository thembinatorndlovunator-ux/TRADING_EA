"""join_signal_to_outcome.py -- joins cleaned journal decisions
(``join_trade_journal.py``'s output) to their eventual trade outcomes
(``analyse_baseline.py``'s trades.csv schema, extended with ``order_id``/
``deal_id`` columns) by the durable ``order_id`` key, producing the
unified per-position CSV ``performance_breakdown.py`` documents as its
required input.

**Provenance (Codex review finding, 2026-07-22, third round): this join
was previously unimplemented and unowned** -- ``join_trade_journal.py``
only cleans journal records, ``performance_breakdown.py`` requires an
already-unified CSV but never builds one, and TASK-036/037 each excluded
the consuming join from their own scope while their test plans implied
one existed. This script is that missing, explicit owner.

**Corrected, 2026-07-22 Codex review finding (fourth round): the round-3
implementation contradicted its own stated rules in several ways, all
fixed here:**

1. **A null/blank journal ``order_id`` is a NORMAL, EXPECTED state**
   (a decision rejected before submission, or not yet filled) -- the
   round-3 code instead aborted the ENTIRE journal with a schema error
   the moment any row had a null ``order_id``, directly contradicting
   this module's own documented cardinality rules. Such rows are now
   filtered out of consideration (never matched, never erroring) rather
   than raising.
2. **``deal_id`` is now actually read and used**, not silently ignored --
   each trade outcome's ``deal_id`` must be its own non-null, unique
   identifier (a real MT5 deal ticket is unique per fill), checked the
   same way ``trade_id`` is.
3. **Durable identifiers are read as ``str``, never pandas' inferred
   numeric type** -- an in-memory probe of ``9007199254740992``,
   ``9007199254740993``, and a blank ID previously loaded the column as
   ``float64`` and collapsed the first two (distinct) IDs to the SAME
   value; leading zeroes (``"001"``) were also silently discarded.
4. **``trade_id``/``deal_id`` are checked for null and duplicate values,
   and ``profit`` is checked for finiteness** -- none of these were
   checked before.
5. **Shared fields (e.g. ``symbol``) are no longer merged with silent
   trade-row precedence.** If a column exists on BOTH the journal and
   trade record for a matched pair, the two values must agree; a
   disagreement is now a row-level error (data corruption or a
   mismatched join), not a silent overwrite that could mask it.
6. **Partial fills are now aggregated into ONE output row per
   ``order_id``** (position), not one row per individual fill --
   downstream statistical pipelines (``performance_breakdown.py``) treat
   each output row as one independent trade observation; leaving
   multiple CORRELATED fill-rows per position previously inflated
   ``n_trades`` and understated confidence-interval width. ``profit`` is
   summed across a position's fills; ``entry_time``/``exit_time`` (when
   present) take the earliest/latest across fills; the full set of
   constituent ``trade_id``/``deal_id`` values is preserved in
   ``fill_trade_ids``/``fill_deal_ids`` for traceability, and ``n_fills``
   records how many fills were aggregated.

**Cardinality/duplicate rules, stated explicitly:**

- A submitted (non-null ``order_id``) journal decision's ``order_id``
  must be UNIQUE among journal decisions -- a decision legitimately
  submits at most one order, so a duplicate SUBMITTED journal
  ``order_id`` is a schema error, not a valid multi-decision order.
- A journal decision with a null/blank ``order_id`` is normal (rejected
  before submission, or not yet filled) -- filtered out, never an error.
- A ``order_id`` may appear MULTIPLE TIMES among trade outcomes -- this
  is the normal partial-fill case (one order, several deals/fills). All
  such fills are aggregated into ONE output row (see point 6 above).
- A trade outcome whose ``order_id`` matches no SUBMITTED journal
  decision is an orphaned outcome (a fill with no recorded decision) --
  a row-level error, never silently dropped or silently joined to
  nothing.
- A journal decision with NO matching trade outcome is normal and
  expected -- it simply does not appear in the joined output; this is
  not an error.

Required input formats:

``journal.csv`` -- ``join_trade_journal.py``'s own output shape (every
``TradeDecision`` field, including ``order_id``/``deal_id`` -- see
``analysis/schema.py``).

``trades.csv`` -- ``analyse_baseline.py``'s normalized schema
(``trade_id, symbol, is_long, entry_time, exit_time, entry_price,
exit_price, stop_price, profit``) PLUS ``order_id``/``deal_id`` columns
linking each fill back to the journal decision that produced it. No MQL5
export or journal producer populates ``order_id``/``deal_id`` in either
file yet (see ``TASK-036_JOURNAL_PRODUCER_COMPLETION.md``) -- this script
is ready to run the moment one does.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Optional

import pandas as pd

from analysis.csv_io import (
    CsvSchemaError,
    assert_output_paths_distinct,
    assert_path_not_same_file,
    atomic_write_dataframe_csv,
    read_csv_with_required_columns,
    sanitize_dataframe_for_csv,
)
from analysis.metrics import InsufficientSampleError
from analysis.report_metadata import atomic_write_text, build_report_metadata

REQUIRED_JOURNAL_COLUMNS = {"order_id"}
REQUIRED_TRADE_COLUMNS = {"trade_id", "order_id", "deal_id", "profit"}
# Durable identifiers must never be inferred as numeric -- see module
# docstring point 3.
IDENTITY_DTYPE = {"order_id": str, "deal_id": str, "trade_id": str}


def _is_blank(value: object) -> bool:
    return (
        value is None
        or (isinstance(value, float) and math.isnan(value))
        or str(value).strip() == ""
    )


def join_signal_to_outcome(
    journal_df: pd.DataFrame, trades_df: pd.DataFrame
) -> tuple[pd.DataFrame, list[dict]]:
    """Returns (joined_df, row_errors), one row of 'joined_df' per
    aggregated POSITION (order_id), not per individual fill (see module
    docstring point 6). 'row_errors' entries have shape
    {"trade_id": ..., "order_id": ..., "error": ...} for an orphaned trade
    outcome or a journal/trade shared-field conflict.

    Raises CsvSchemaError if any SUBMITTED (non-null order_id) journal
    decision has a duplicate order_id, if any trade_id/deal_id is null or
    duplicated, or if 'profit' contains a non-finite value -- see module
    docstring for the full cardinality rules this enforces.
    """

    order_id_blank = journal_df["order_id"].apply(_is_blank)
    submitted = journal_df[~order_id_blank]
    # Unsubmitted (null/blank order_id) decisions are normal -- rejected
    # before submission, or not yet filled -- and are simply excluded
    # from matching, never raised as an error (module docstring point 1).

    dup_submitted = submitted[submitted.duplicated(subset=["order_id"], keep=False)]
    if not dup_submitted.empty:
        raise CsvSchemaError(
            f"join_signal_to_outcome: duplicate SUBMITTED journal order_id values: "
            f"{sorted(dup_submitted['order_id'].unique())}"
        )

    if trades_df["trade_id"].apply(_is_blank).any():
        raise CsvSchemaError("join_signal_to_outcome: trades has a null/blank trade_id")
    dup_trade_id = trades_df[trades_df.duplicated(subset=["trade_id"], keep=False)]
    if not dup_trade_id.empty:
        raise CsvSchemaError(
            f"join_signal_to_outcome: duplicate trade_id values: "
            f"{sorted(dup_trade_id['trade_id'].unique())}"
        )

    if trades_df["deal_id"].apply(_is_blank).any():
        raise CsvSchemaError("join_signal_to_outcome: trades has a null/blank deal_id")
    dup_deal_id = trades_df[trades_df.duplicated(subset=["deal_id"], keep=False)]
    if not dup_deal_id.empty:
        raise CsvSchemaError(
            f"join_signal_to_outcome: duplicate deal_id values: "
            f"{sorted(dup_deal_id['deal_id'].unique())}"
        )

    profit_numeric = pd.to_numeric(trades_df["profit"], errors="coerce")
    if not profit_numeric.apply(lambda v: pd.notna(v) and math.isfinite(v)).all():
        raise CsvSchemaError("join_signal_to_outcome: trades has a non-finite/missing profit value")

    # Shared-field conflict detection (module docstring point 5): any
    # column present on BOTH sides (other than the join key itself) must
    # agree for a matched pair, or the row is a conflict error rather than
    # a silent trade-row-wins overwrite.
    shared_cols = (set(journal_df.columns) & set(trades_df.columns)) - {"order_id"}

    submitted_by_order = submitted.set_index("order_id")
    journal_order_ids = set(submitted_by_order.index)

    fill_rows: list[dict] = []
    row_errors: list[dict] = []
    for _, trade_row in trades_df.iterrows():
        order_id = trade_row["order_id"]
        if _is_blank(order_id) or order_id not in journal_order_ids:
            row_errors.append(
                {
                    "trade_id": str(trade_row.get("trade_id", "")),
                    "order_id": None if _is_blank(order_id) else str(order_id),
                    "error": "order_id matches no SUBMITTED journal decision (orphaned trade outcome)",
                }
            )
            continue
        journal_row = submitted_by_order.loc[order_id]
        conflicts = [
            col for col in shared_cols if not _values_equal(journal_row[col], trade_row[col])
        ]
        if conflicts:
            row_errors.append(
                {
                    "trade_id": str(trade_row.get("trade_id", "")),
                    "order_id": str(order_id),
                    "error": (
                        f"journal/trade shared field(s) disagree: {sorted(conflicts)} -- "
                        "refusing to silently let the trade row's value win"
                    ),
                }
            )
            continue
        combined = {**journal_row.to_dict(), **trade_row.to_dict()}
        fill_rows.append(combined)

    if not fill_rows:
        return pd.DataFrame(), row_errors

    fills_df = pd.DataFrame(fill_rows)

    # Aggregate every position's fills into ONE output row (module
    # docstring point 6) -- downstream statistical pipelines must see one
    # row per independent trade observation, not one per correlated fill.
    aggregated_rows = []
    for order_id, group in fills_df.groupby("order_id", sort=False):
        agg = group.iloc[0].to_dict()
        agg["profit"] = float(group["profit"].sum())
        agg["n_fills"] = len(group)
        agg["fill_trade_ids"] = ",".join(str(v) for v in group["trade_id"])
        agg["fill_deal_ids"] = ",".join(str(v) for v in group["deal_id"])
        if "entry_time" in group.columns:
            agg["entry_time"] = group["entry_time"].min()
        if "exit_time" in group.columns:
            agg["exit_time"] = group["exit_time"].max()
        aggregated_rows.append(agg)

    joined_df = pd.DataFrame(aggregated_rows)
    return joined_df, row_errors


def _values_equal(a: object, b: object) -> bool:
    if _is_blank(a) and _is_blank(b):
        return True
    return a == b


def run(
    journal_csv: Path,
    trades_csv: Path,
    output_csv: Optional[Path] = None,
    errors_json: Optional[Path] = None,
    *,
    symbol: Optional[str] = None,
    seed: Optional[int] = None,
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> tuple[pd.DataFrame, list[dict]]:
    # Uses OS-level file-identity (not just Path.resolve()) so a hard
    # link to an input is also caught -- Codex review finding, third round.
    for out_path in (output_csv, errors_json):
        assert_path_not_same_file(out_path, journal_csv, "output path")
        assert_path_not_same_file(out_path, trades_csv, "output path")
    assert_output_paths_distinct([output_csv, errors_json])

    journal_df = read_csv_with_required_columns(
        journal_csv, REQUIRED_JOURNAL_COLUMNS, dtype=IDENTITY_DTYPE
    )
    trades_df = read_csv_with_required_columns(
        trades_csv, REQUIRED_TRADE_COLUMNS, dtype=IDENTITY_DTYPE
    )
    if trades_df.empty:
        raise InsufficientSampleError(f"{trades_csv}: zero trade rows")

    joined_df, row_errors = join_signal_to_outcome(journal_df, trades_df)

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_dataframe_csv(sanitize_dataframe_for_csv(joined_df), output_csv)

    # **Fixed, 2026-07-22 Codex review finding (fourth round): provenance
    # was previously written ONLY when 'errors_json' was explicitly
    # supplied -- a caller who requested only output_csv got a data file
    # with zero provenance record anywhere, unlike every other pipeline in
    # this layer.**
    if errors_json is None and output_csv is not None:
        errors_json = output_csv.parent / f"{output_csv.stem}.errors.json"

    if errors_json is not None:
        errors_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [journal_csv, trades_csv],
            symbol=symbol,
            random_seed=seed,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=repo_path,
        )
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_journal_decisions": len(journal_df),
                "n_trade_outcomes": len(trades_df),
                "n_joined": len(joined_df),
                "n_row_errors": len(row_errors),
            },
            "row_errors": row_errors,
        }
        atomic_write_text(errors_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return joined_df, row_errors


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal-csv", required=True, type=Path)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--errors-json", type=Path, default=None)
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        joined_df, row_errors = run(
            journal_csv=args.journal_csv,
            trades_csv=args.trades_csv,
            output_csv=args.output_csv,
            errors_json=args.errors_json,
            symbol=args.symbol,
            seed=args.seed,
            spread_note=args.spread_note,
            slippage_note=args.slippage_note,
        )
    except (FileNotFoundError, CsvSchemaError, InsufficientSampleError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"join_signal_to_outcome: {len(joined_df)} joined, {len(row_errors)} row errors.")
    return 1 if row_errors else 0


if __name__ == "__main__":
    sys.exit(main())
