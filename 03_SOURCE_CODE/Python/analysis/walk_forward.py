"""walk_forward.py -- rolling train/test window stability analysis over a
time-ordered trade series, using the SAME normalized trade-export schema as
``analyse_baseline.py`` (``trade_id, symbol, is_long, entry_time, exit_time,
entry_price, exit_price, stop_price, profit``).

Window boundaries are entirely deterministic given
(``train_days``, ``test_days``, ``step_days``) and the dataset's own first/
last ``exit_time`` -- no randomization is used here (Monte Carlo resampling
is a separate concern, see ``monte_carlo.py``), so no seed is needed or
accepted, per the reproducibility contract's "where applicable" qualifier
on the seed requirement.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import pandas as pd

from analysis.csv_io import CsvSchemaError, read_csv_with_required_columns
from analysis.metrics import InsufficientSampleError, expectancy, win_rate
from analysis.report_metadata import build_report_metadata
from analysis.trade_math import compute_r_multiple

REQUIRED_COLUMNS = {
    "trade_id", "symbol", "is_long", "entry_time", "exit_time",
    "entry_price", "exit_price", "stop_price", "profit",
}


def _parse_is_long(value: object) -> bool:
    text = str(value).strip().lower()
    if text in ("true", "1", "yes", "long"):
        return True
    if text in ("false", "0", "no", "short"):
        return False
    raise ValueError(f"cannot parse is_long value: {value!r}")


def generate_windows(
    first_time: pd.Timestamp, last_time: pd.Timestamp, train_days: int, test_days: int, step_days: int
) -> list[tuple[pd.Timestamp, pd.Timestamp, pd.Timestamp, pd.Timestamp]]:
    """Generates (train_start, train_end, test_start, test_end) tuples,
    rolling forward by 'step_days' each time, stopping once a window's
    test_start would fall after 'last_time' (no window is generated that
    starts entirely beyond the available data). Raises ValueError if any
    of the three day counts is non-positive."""

    if train_days <= 0 or test_days <= 0 or step_days <= 0:
        raise ValueError("train_days, test_days, and step_days must all be > 0")
    if first_time > last_time:
        raise ValueError(f"first_time ({first_time}) must not be after last_time ({last_time})")

    windows = []
    train_start = first_time
    while True:
        train_end = train_start + pd.Timedelta(days=train_days)
        test_start = train_end
        test_end = test_start + pd.Timedelta(days=test_days)
        if test_start > last_time:
            break
        windows.append((train_start, train_end, test_start, test_end))
        train_start = train_start + pd.Timedelta(days=step_days)

    return windows


@dataclass(frozen=True)
class WindowMetrics:
    n: int
    win_rate: Optional[float]
    win_rate_ci_lower: Optional[float]
    win_rate_ci_upper: Optional[float]
    expectancy_r: Optional[float]


def _slice_metrics(slice_df: pd.DataFrame) -> WindowMetrics:
    n = len(slice_df)
    if n == 0:
        return WindowMetrics(0, None, None, None, None)

    wr = None
    try:
        wr = win_rate((slice_df["profit"] > 0).tolist())
    except InsufficientSampleError:
        pass

    exp = None
    try:
        exp = expectancy(slice_df["r_multiple"].tolist())
    except InsufficientSampleError:
        pass

    return WindowMetrics(
        n=n,
        win_rate=wr.win_rate if wr else None,
        win_rate_ci_lower=wr.ci_lower if wr else None,
        win_rate_ci_upper=wr.ci_upper if wr else None,
        expectancy_r=exp.expectancy if exp else None,
    )


def run(
    trades_csv: Path,
    train_days: int,
    test_days: int,
    step_days: int,
    output_csv: Optional[Path] = None,
    summary_json: Optional[Path] = None,
    *,
    symbol: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> pd.DataFrame:
    """Returns a DataFrame with one row per window (train/test metrics
    both included). Raises CsvSchemaError/InsufficientSampleError the same
    way analyse_baseline.run does for structural input problems."""

    trades = read_csv_with_required_columns(trades_csv, REQUIRED_COLUMNS)
    if trades.empty:
        raise InsufficientSampleError(f"{trades_csv}: zero trade rows")

    trades = trades.copy()
    trades["is_long"] = trades["is_long"].apply(_parse_is_long)
    trades["exit_time"] = pd.to_datetime(trades["exit_time"], utc=True, errors="raise")
    trades["r_multiple"] = trades.apply(
        lambda row: compute_r_multiple(
            row["is_long"], float(row["entry_price"]), float(row["stop_price"]), float(row["exit_price"])
        ),
        axis=1,
    )
    trades = trades.sort_values("exit_time")

    windows = generate_windows(
        trades["exit_time"].iloc[0], trades["exit_time"].iloc[-1], train_days, test_days, step_days
    )

    rows = []
    for i, (train_start, train_end, test_start, test_end) in enumerate(windows):
        train_slice = trades[(trades["exit_time"] >= train_start) & (trades["exit_time"] < train_end)]
        test_slice = trades[(trades["exit_time"] >= test_start) & (trades["exit_time"] < test_end)]

        train_m = _slice_metrics(train_slice)
        test_m = _slice_metrics(test_slice)

        rows.append(
            {
                "window_index": i,
                "train_start": train_start,
                "train_end": train_end,
                "test_start": test_start,
                "test_end": test_end,
                "train_n": train_m.n,
                "train_win_rate": train_m.win_rate,
                "train_expectancy_r": train_m.expectancy_r,
                "test_n": test_m.n,
                "test_win_rate": test_m.win_rate,
                "test_win_rate_ci_lower": test_m.win_rate_ci_lower,
                "test_win_rate_ci_upper": test_m.win_rate_ci_upper,
                "test_expectancy_r": test_m.expectancy_r,
            }
        )

    result_df = pd.DataFrame(rows)

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        result_df.to_csv(output_csv, index=False)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata([trades_csv], symbol=symbol, repo_path=repo_path)
        test_expectancies = [r for r in result_df["test_expectancy_r"] if r is not None]
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_windows": len(result_df),
                "train_days": train_days,
                "test_days": test_days,
                "step_days": step_days,
                "n_windows_with_test_data": int((result_df["test_n"] > 0).sum()),
                "mean_test_expectancy_r": (
                    sum(test_expectancies) / len(test_expectancies) if test_expectancies else None
                ),
            },
        }
        summary_json.write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")

    return result_df


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--train-days", type=int, required=True)
    parser.add_argument("--test-days", type=int, required=True)
    parser.add_argument("--step-days", type=int, required=True)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--summary-json", type=Path, default=None)
    parser.add_argument("--symbol", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        result_df = run(
            trades_csv=args.trades_csv,
            train_days=args.train_days,
            test_days=args.test_days,
            step_days=args.step_days,
            output_csv=args.output_csv,
            summary_json=args.summary_json,
            symbol=args.symbol,
        )
    except (FileNotFoundError, CsvSchemaError, InsufficientSampleError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"walk_forward: {len(result_df)} windows generated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
