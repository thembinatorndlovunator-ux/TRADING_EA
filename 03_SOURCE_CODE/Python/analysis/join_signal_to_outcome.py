"""join_signal_to_outcome.py -- joins cleaned journal decisions
(``join_trade_journal.py``'s output) to their eventual trade outcomes
(``analyse_baseline.py``'s trades.csv schema, extended with an
``order_id`` column) by the durable ``order_id`` key, producing the
unified per-trade CSV ``performance_breakdown.py`` documents as its
required input.

**Provenance (Codex review finding, 2026-07-22, third round): this join
was previously unimplemented and unowned** -- ``join_trade_journal.py``
only cleans journal records, ``performance_breakdown.py`` requires an
already-unified CSV but never builds one, and TASK-036/037 each excluded
the consuming join from their own scope while their test plans implied
one existed. This script is that missing, explicit owner.

**Cardinality/duplicate rules, stated explicitly:**

- A ``order_id`` must be UNIQUE among journal decisions -- a decision
  legitimately submits at most one order, so a duplicate journal
  ``order_id`` is a schema error, not a valid multi-decision order.
- A ``order_id`` may appear MULTIPLE TIMES among trade outcomes -- this
  is the normal partial-fill case (one order, several deals/fills). Each
  fill becomes its own output row, all carrying the SAME journal
  dimensional fields (strategy, regime, session_state, etc.), since they
  all originated from the same decision.
- A trade outcome whose ``order_id`` matches NO journal decision is an
  orphaned outcome (a fill with no recorded decision) -- a row-level
  error, never silently dropped or silently joined to nothing.
- A journal decision with NO matching trade outcome (rejected before
  submission, or not yet filled) is normal and expected -- it simply
  does not appear in the joined output; this is not an error.

Required input formats:

``journal.csv`` -- ``join_trade_journal.py``'s own output shape (every
``TradeDecision`` field, including the ``order_id`` this task's schema
change added -- see ``analysis/schema.py``).

``trades.csv`` -- ``analyse_baseline.py``'s normalized schema
(``trade_id, symbol, is_long, entry_time, exit_time, entry_price,
exit_price, stop_price, profit``) PLUS an ``order_id`` column linking
each trade back to the journal decision that produced it. No MQL5
export or journal producer populates ``order_id`` in either file yet
(see ``TASK-036_JOURNAL_PRODUCER_COMPLETION.md``) -- this script is
ready to run the moment one does.
"""

from __future__ import annotations

import argparse
import json
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
REQUIRED_TRADE_COLUMNS = {"trade_id", "order_id", "profit"}


def join_signal_to_outcome(
    journal_df: pd.DataFrame, trades_df: pd.DataFrame
) -> tuple[pd.DataFrame, list[dict]]:
    """Returns (joined_df, row_errors). 'row_errors' entries have shape
    {"trade_id": ..., "order_id": ..., "error": ...} for any trade outcome
    whose order_id matches no journal decision. Raises CsvSchemaError if
    'journal_df' has a null or duplicate order_id -- see module docstring
    for the cardinality rules this enforces.
    """

    if journal_df["order_id"].isna().any():
        raise CsvSchemaError("join_signal_to_outcome: journal has a null order_id")
    dup = journal_df[journal_df.duplicated(subset=["order_id"], keep=False)]
    if not dup.empty:
        raise CsvSchemaError(
            f"join_signal_to_outcome: duplicate journal order_id values: "
            f"{sorted(dup['order_id'].unique())}"
        )

    journal_by_order = journal_df.set_index("order_id")
    journal_order_ids = set(journal_by_order.index)

    joined_rows = []
    row_errors: list[dict] = []
    for _, trade_row in trades_df.iterrows():
        order_id = trade_row["order_id"]
        if pd.isna(order_id) or order_id not in journal_order_ids:
            row_errors.append(
                {
                    "trade_id": str(trade_row.get("trade_id", "")),
                    "order_id": None if pd.isna(order_id) else str(order_id),
                    "error": "order_id matches no journal decision (orphaned trade outcome)",
                }
            )
            continue
        journal_row = journal_by_order.loc[order_id]
        combined = {**journal_row.to_dict(), **trade_row.to_dict()}
        joined_rows.append(combined)

    joined_df = pd.DataFrame(joined_rows)
    return joined_df, row_errors


def run(
    journal_csv: Path,
    trades_csv: Path,
    output_csv: Optional[Path] = None,
    errors_json: Optional[Path] = None,
    *,
    symbol: Optional[str] = None,
    seed: Optional[int] = None,
    repo_path: Optional[Path] = None,
) -> tuple[pd.DataFrame, list[dict]]:
    # Uses OS-level file-identity (not just Path.resolve()) so a hard
    # link to an input is also caught -- Codex review finding, third round.
    for out_path in (output_csv, errors_json):
        assert_path_not_same_file(out_path, journal_csv, "output path")
        assert_path_not_same_file(out_path, trades_csv, "output path")
    assert_output_paths_distinct([output_csv, errors_json])

    journal_df = read_csv_with_required_columns(journal_csv, REQUIRED_JOURNAL_COLUMNS)
    trades_df = read_csv_with_required_columns(trades_csv, REQUIRED_TRADE_COLUMNS)
    if trades_df.empty:
        raise InsufficientSampleError(f"{trades_csv}: zero trade rows")

    joined_df, row_errors = join_signal_to_outcome(journal_df, trades_df)

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_dataframe_csv(sanitize_dataframe_for_csv(joined_df), output_csv)

    if errors_json is not None:
        errors_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [journal_csv, trades_csv], symbol=symbol, random_seed=seed, repo_path=repo_path
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
        )
    except (FileNotFoundError, CsvSchemaError, InsufficientSampleError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"join_signal_to_outcome: {len(joined_df)} joined, {len(row_errors)} row errors.")
    return 1 if row_errors else 0


if __name__ == "__main__":
    sys.exit(main())
