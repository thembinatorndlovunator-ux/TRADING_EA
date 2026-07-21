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

**Scope, stated explicitly (Codex review finding, 2026-07-21): this is a
descriptive rolling-window STABILITY report, not a walk-forward
OPTIMIZATION procedure.** It computes win-rate/expectancy for each
train/test window pair; it does NOT select any parameter on the train
window and freeze it for the test window (the standard definition of
"walk-forward" in a trading-strategy-development sense). A genuine
parameter-selection walk-forward harness (accepting a pluggable
train-window optimizer and a frozen-parameter test evaluator) is a
reasonable future enhancement, not attempted here.

**Purged boundaries, fixed 2026-07-21:** a trade is assigned to a window
only if BOTH its entry_time and exit_time fall inside that window's own
[start, end) range. A trade whose entry precedes a window's start (or
whose exit follows a window's end) is excluded from that window entirely
rather than assigned by exit_time alone -- the previous exit-time-only
partitioning could let a trade whose ENTRY (and thus whatever information
the trade's own decision used) preceded a test window's start still count
as a "test" observation, which is a temporal-leakage route for any
parameter genuinely selected on the train window.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
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
from analysis.metrics import InsufficientSampleError, expectancy, win_rate
from analysis.report_metadata import build_report_metadata
from analysis.time_utils import parse_utc_series
from analysis.trade_math import compute_r_multiple

REQUIRED_COLUMNS = {
    "trade_id", "symbol", "is_long", "entry_time", "exit_time",
    "entry_price", "exit_price", "stop_price", "profit",
}
NUMERIC_COLUMNS = ("entry_price", "exit_price", "stop_price")

SUMMARY_COLUMNS = [
    "window_index", "train_start", "train_end", "test_start", "test_end",
    "train_n", "train_win_rate", "train_expectancy_r",
    "test_n", "test_win_rate", "test_win_rate_ci_lower", "test_win_rate_ci_upper",
    "test_expectancy_r",
]


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


def _slice_window(trades: pd.DataFrame, start: pd.Timestamp, end: pd.Timestamp) -> pd.DataFrame:
    """A trade belongs to [start, end) only if BOTH its entry_time and
    exit_time fall inside that range -- see module docstring's "purged
    boundaries" note. A trade spanning the boundary is excluded from both
    the window it starts in and the window it ends in, rather than
    silently assigned to one by exit_time alone."""

    return trades[
        (trades["entry_time"] >= start) & (trades["entry_time"] < end)
        & (trades["exit_time"] >= start) & (trades["exit_time"] < end)
    ]


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
    both included, SUMMARY_COLUMNS in shape even when zero windows are
    generated). Raises CsvSchemaError/InsufficientSampleError the same
    way analyse_baseline.run does for structural input problems."""

    for out_path in (output_csv, summary_json):
        if out_path is not None and out_path.resolve() == trades_csv.resolve():
            raise CsvSchemaError(f"output path {out_path} must not be the same as the input trades_csv")

    trades = read_csv_with_required_columns(trades_csv, REQUIRED_COLUMNS)
    if trades.empty:
        raise InsufficientSampleError(f"{trades_csv}: zero trade rows")
    assert_unique_ids(trades, "trade_id", trades_csv)
    assert_finite_columns(trades, NUMERIC_COLUMNS, trades_csv)

    trades = trades.copy()
    trades["is_long"] = trades["is_long"].apply(parse_is_long)
    trades["entry_time"] = parse_utc_series(trades["entry_time"])
    trades["exit_time"] = parse_utc_series(trades["exit_time"])
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
        train_slice = _slice_window(trades, train_start, train_end)
        test_slice = _slice_window(trades, test_start, test_end)

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

    # Explicit column set even when 'rows' is empty (zero windows generated,
    # e.g. the data span is shorter than train_days+test_days) -- a Codex
    # review finding: pd.DataFrame([]) previously produced a DataFrame with
    # NO columns at all, and the summary_json block below then raised a
    # bare KeyError trying to access "test_expectancy_r" on it.
    result_df = pd.DataFrame(rows, columns=SUMMARY_COLUMNS)

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        result_df.to_csv(output_csv, index=False)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata([trades_csv], symbol=symbol, repo_path=repo_path)
        # pandas stores the "no test trades" case as NaN (float), not the
        # Python None _slice_metrics returned -- `r is not None` does NOT
        # filter NaN out (a Codex review finding, reproduced on this
        # module's own 5-trade test fixture: it silently wrote
        # `mean_test_expectancy_r: NaN`, a non-standard JSON token, instead
        # of the mean over the genuinely-valid windows). Use pd.notna().
        valid_test_expectancies = result_df["test_expectancy_r"][result_df["test_expectancy_r"].notna()]
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_windows": len(result_df),
                "train_days": train_days,
                "test_days": test_days,
                "step_days": step_days,
                "n_windows_with_test_data": int((result_df["test_n"] > 0).sum()),
                "mean_test_expectancy_r": (
                    float(valid_test_expectancies.mean()) if len(valid_test_expectancies) else None
                ),
            },
        }
        summary_json.write_text(json.dumps(payload, indent=2, default=str, allow_nan=False), encoding="utf-8")

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
