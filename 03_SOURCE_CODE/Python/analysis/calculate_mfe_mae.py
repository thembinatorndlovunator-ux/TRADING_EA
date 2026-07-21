"""calculate_mfe_mae.py -- per-trade maximum favorable/adverse excursion.

Required input format (documented here since no real MT5 export exists yet
to derive it from -- a future task bridging a real MT5 "Deals" export into
this shape is separate work, not attempted here):

``trades.csv`` columns: ``trade_id, symbol, is_long, entry_time, exit_time,
entry_price, stop_price`` (``is_long`` accepts "True"/"False"/"1"/"0",
case-insensitive; ``entry_time``/``exit_time`` must be ISO-8601 UTC, same
convention as ``DJ_FormatIso8601Utc``).

``bars.csv`` columns: ``symbol, timestamp, high, low`` (``timestamp``
ISO-8601 UTC) -- one row per completed bar, any timeframe, covering at
least every trade's [entry_time, exit_time] window.

A trade whose window has no matching bars, or whose input row is malformed,
is recorded in the error report -- never silently dropped or defaulted to
a zero excursion (see ``trade_math.NoBarsInWindowError``'s own docstring
for why those two situations must not be conflated).
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import pandas as pd

from analysis.csv_io import CsvSchemaError, parse_is_long, read_csv_with_required_columns
from analysis.report_metadata import build_report_metadata
from analysis.trade_math import MfeMaeResult, NoBarsInWindowError, compute_mfe_mae

TradesSchemaError = CsvSchemaError  # kept as a local alias for readability
                                     # at this script's own call sites

REQUIRED_TRADE_COLUMNS = {
    "trade_id",
    "symbol",
    "is_long",
    "entry_time",
    "exit_time",
    "entry_price",
    "stop_price",
}
REQUIRED_BAR_COLUMNS = {"symbol", "timestamp", "high", "low"}


@dataclass(frozen=True)
class MfeMaeRunResult:
    results: list[MfeMaeResult]
    row_errors: list[dict]


def run(
    trades_csv: Path,
    bars_csv: Path,
    output_csv: Optional[Path] = None,
    errors_json: Optional[Path] = None,
    *,
    symbol: Optional[str] = None,
    seed: Optional[int] = None,
    repo_path: Optional[Path] = None,
) -> MfeMaeRunResult:
    """Reads 'trades_csv' and 'bars_csv', computes MFE/MAE per trade.
    Raises TradesSchemaError/FileNotFoundError for structural problems
    (missing file, missing required column) -- those are script-level
    failures, distinct from a per-ROW problem (malformed timestamp, no
    bars in window), which is instead collected into 'row_errors' so one
    bad trade never hides every other trade's valid result.
    """

    trades = read_csv_with_required_columns(trades_csv, REQUIRED_TRADE_COLUMNS)
    bars = read_csv_with_required_columns(bars_csv, REQUIRED_BAR_COLUMNS)

    bars = bars.copy()
    bars["timestamp"] = pd.to_datetime(bars["timestamp"], utc=True, errors="raise")

    results: list[MfeMaeResult] = []
    row_errors: list[dict] = []

    for _, row in trades.iterrows():
        trade_id = str(row["trade_id"])
        try:
            is_long = parse_is_long(row["is_long"])
            entry_time = pd.to_datetime(row["entry_time"], utc=True, errors="raise")
            exit_time = pd.to_datetime(row["exit_time"], utc=True, errors="raise")
            entry_price = float(row["entry_price"])
            stop_price = float(row["stop_price"])
            symbol_bars = bars[bars["symbol"] == row["symbol"]]

            result = compute_mfe_mae(
                trade_id=trade_id,
                is_long=is_long,
                entry_price=entry_price,
                stop_price=stop_price,
                entry_time=entry_time,
                exit_time=exit_time,
                bars=symbol_bars,
            )
            results.append(result)
        except (ValueError, NoBarsInWindowError, KeyError) as exc:
            row_errors.append({"trade_id": trade_id, "error": str(exc)})

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        out_df = pd.DataFrame(
            [
                {
                    "trade_id": r.trade_id,
                    "mfe_price": r.mfe_price,
                    "mae_price": r.mae_price,
                    "mfe_r": r.mfe_r,
                    "mae_r": r.mae_r,
                    "n_bars": r.n_bars,
                }
                for r in results
            ]
        )
        out_df.to_csv(output_csv, index=False)

    if errors_json is not None:
        errors_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [trades_csv, bars_csv], symbol=symbol, random_seed=seed, repo_path=repo_path
        )
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_trades_input": len(trades),
                "n_results": len(results),
                "n_row_errors": len(row_errors),
            },
            "row_errors": row_errors,
        }
        errors_json.write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")

    return MfeMaeRunResult(results=results, row_errors=row_errors)


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--bars-csv", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--errors-json", type=Path, default=None)
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--seed", type=int, default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        result = run(
            trades_csv=args.trades_csv,
            bars_csv=args.bars_csv,
            output_csv=args.output_csv,
            errors_json=args.errors_json,
            symbol=args.symbol,
            seed=args.seed,
        )
    except (FileNotFoundError, TradesSchemaError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"calculate_mfe_mae: {len(result.results)} computed, {len(result.row_errors)} row errors.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
