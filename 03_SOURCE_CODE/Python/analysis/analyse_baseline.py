"""analyse_baseline.py -- aggregate performance summary over a normalized
trade-export CSV: win rate (with Wilson CI), expectancy ($  and R), profit
factor, and max drawdown on the resulting BALANCE curve.

**Balance, not equity, and stated explicitly (Codex review finding,
2026-07-21):** the curve this module builds is cumulative CLOSED-TRADE
P/L only -- it contains no mark-to-market value for any still-open
position, so it is a balance curve, not an equity curve. `TEST_PLAN.md`
requires both a max BALANCE drawdown and a max EQUITY drawdown as
separate figures; this module only ever produces the former. A true
equity curve needs an actual time series of account equity (including
floating P/L), which this project does not have yet (see
TASK-028_PYTHON_STATISTICAL_LAB.md's Risks section).

Required input format (documented here since neither baseline EA has a
committed real trade export yet -- 01_BASELINE/ contains only source code,
screenshots, and set files, no trade history):

``trades.csv`` columns: ``trade_id, symbol, is_long, entry_time, exit_time,
entry_price, exit_price, stop_price, profit`` -- ``profit`` is the NET
account-currency P/L (commission and swap already netted in, matching how
an MT5 "Deals" export's own profit column normally already nets these in
per deal); a future task bridging a real MT5 HTML/XLSX statement export
into this CSV shape is separate work, not attempted here.
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
    assert_finite_columns,
    assert_unique_ids,
    parse_is_long,
    read_csv_with_required_columns,
)
from analysis.metrics import InsufficientSampleError, compute_max_drawdown, expectancy, profit_factor, win_rate
from analysis.report_metadata import build_report_metadata
from analysis.trade_math import compute_r_multiple

REQUIRED_COLUMNS = {
    "trade_id",
    "symbol",
    "is_long",
    "entry_time",
    "exit_time",
    "entry_price",
    "exit_price",
    "stop_price",
    "profit",
}
NUMERIC_COLUMNS = ("entry_price", "exit_price", "stop_price", "profit")


def run(
    trades_csv: Path,
    output_json: Optional[Path] = None,
    per_trade_csv: Optional[Path] = None,
    *,
    starting_balance: float = 1000.0,
    symbol: Optional[str] = None,
    broker: Optional[str] = None,
    seed: Optional[int] = None,
    repo_path: Optional[Path] = None,
) -> dict:
    """Reads 'trades_csv', computes the aggregate summary, and (if given)
    writes it to 'output_json' plus a per-trade CSV (with the computed
    r_multiple column added) to 'per_trade_csv'. Returns the summary dict
    unconditionally so a caller (test or notebook) can inspect it without
    touching disk.

    Raises CsvSchemaError if a required column is missing, a duplicate
    trade_id exists, a numeric column has a non-finite/missing value, or
    an output path collides with the input path. Raises
    InsufficientSampleError if the file has zero trade rows, or if
    'starting_balance' is not strictly positive (percentage drawdown is
    undefined otherwise -- see metrics.compute_max_drawdown).
    """

    if starting_balance <= 0:
        raise InsufficientSampleError(
            f"analyse_baseline.run: starting_balance must be > 0, got {starting_balance}"
        )
    for out_path in (output_json, per_trade_csv):
        if out_path is not None and out_path.resolve() == trades_csv.resolve():
            raise CsvSchemaError(f"output path {out_path} must not be the same as the input trades_csv")

    trades = read_csv_with_required_columns(trades_csv, REQUIRED_COLUMNS)
    if trades.empty:
        raise InsufficientSampleError(f"{trades_csv}: zero trade rows")
    assert_unique_ids(trades, "trade_id", trades_csv)
    assert_finite_columns(trades, NUMERIC_COLUMNS, trades_csv)

    trades = trades.copy()
    trades["is_long"] = trades["is_long"].apply(parse_is_long)
    trades["entry_time"] = pd.to_datetime(trades["entry_time"], utc=True, errors="raise")
    trades["exit_time"] = pd.to_datetime(trades["exit_time"], utc=True, errors="raise")
    trades["r_multiple"] = trades.apply(
        lambda row: compute_r_multiple(
            row["is_long"], float(row["entry_price"]), float(row["stop_price"]), float(row["exit_price"])
        ),
        axis=1,
    )

    trades_sorted = trades.sort_values("exit_time")
    balance_curve = [starting_balance] + list(starting_balance + trades_sorted["profit"].cumsum())

    profits = trades_sorted["profit"].tolist()
    r_multiples = trades_sorted["r_multiple"].tolist()

    wr = win_rate([p > 0 for p in profits])
    exp_dollars = expectancy(profits)
    exp_r = expectancy(r_multiples)
    pf = profit_factor(profits)
    dd = compute_max_drawdown(balance_curve)

    summary = {
        "n_trades": len(trades_sorted),
        "win_rate": {
            "value": wr.win_rate,
            "ci_lower": wr.ci_lower,
            "ci_upper": wr.ci_upper,
            "confidence": wr.confidence,
            "n": wr.n,
        },
        "expectancy_dollars": {
            "value": exp_dollars.expectancy,
            "std_dev": exp_dollars.std_dev,
            "n": exp_dollars.n,
        },
        "expectancy_r": {"value": exp_r.expectancy, "std_dev": exp_r.std_dev, "n": exp_r.n},
        "profit_factor": pf.profit_factor,
        "gross_profit": pf.gross_profit,
        "gross_loss": pf.gross_loss,
        "max_balance_drawdown_abs": dd.max_drawdown_abs,
        "max_balance_drawdown_pct": dd.max_drawdown_pct,
        "max_balance_drawdown_abs_peak_index": dd.max_drawdown_abs_peak_index,
        "max_balance_drawdown_abs_trough_index": dd.max_drawdown_abs_trough_index,
        "max_balance_drawdown_pct_peak_index": dd.max_drawdown_pct_peak_index,
        "max_balance_drawdown_pct_trough_index": dd.max_drawdown_pct_trough_index,
        "max_equity_drawdown": None,  # not computable -- see module docstring
        "final_balance": balance_curve[-1],
        "starting_balance": starting_balance,
    }

    if output_json is not None:
        output_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [trades_csv], symbol=symbol, broker=broker, random_seed=seed, repo_path=repo_path
        )
        payload = {"metadata": metadata.to_dict(), "summary": summary}
        output_json.write_text(json.dumps(payload, indent=2, default=str, allow_nan=False), encoding="utf-8")

    if per_trade_csv is not None:
        per_trade_csv.parent.mkdir(parents=True, exist_ok=True)
        trades_sorted.to_csv(per_trade_csv, index=False)

    return summary


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--output-json", type=Path, default=None)
    parser.add_argument("--per-trade-csv", type=Path, default=None)
    parser.add_argument("--starting-balance", type=float, default=1000.0)
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--broker", default=None)
    parser.add_argument("--seed", type=int, default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        summary = run(
            trades_csv=args.trades_csv,
            output_json=args.output_json,
            per_trade_csv=args.per_trade_csv,
            starting_balance=args.starting_balance,
            symbol=args.symbol,
            broker=args.broker,
            seed=args.seed,
        )
    except (FileNotFoundError, CsvSchemaError, InsufficientSampleError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"analyse_baseline: n={summary['n_trades']} win_rate={summary['win_rate']['value']:.4f} "
        f"expectancy=${summary['expectancy_dollars']['value']:.2f} "
        f"profit_factor={summary['profit_factor']} "
        f"max_balance_dd_pct={summary['max_balance_drawdown_pct']:.4f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
