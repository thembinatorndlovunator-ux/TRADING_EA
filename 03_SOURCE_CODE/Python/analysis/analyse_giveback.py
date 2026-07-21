"""analyse_giveback.py -- offline simulation of ExitManager.mqh's (TASK-030)
two giveback-guard models (V6.37-style percent-of-peak, V8.11-style
absolute-R-floor) against historical bar data, to gather the "Phase 8
evidence" ExitManager.mqh's own header says is required before either
model is ever enabled live. **This script never controls, and cannot be
wired to, any live trading action -- it only answers "if this guard had
been active, would it have closed each trade earlier, and would that have
helped or hurt".**

Required input format (same rationale as calculate_mfe_mae.py -- no real
MT5 export exists yet to derive this from):

``trades.csv`` columns: ``trade_id, symbol, is_long, entry_time, exit_time,
entry_price, stop_price`` and OPTIONALLY ``exit_price`` (if present and
non-null, used as the actual close R instead of the last bar's close --
the more accurate figure when available).

``bars.csv`` columns: ``symbol, timestamp, close`` -- note this is
CLOSE-price-based (a documented simplification: the live guard would check
current bid/ask every tick; a bar-close proxy is what offline analysis at
bar granularity can reasonably provide) -- distinct from
calculate_mfe_mae.py's high/low-based bars.csv.
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
from analysis.exit_simulation import simulate_giveback_path
from analysis.metrics import InsufficientSampleError, win_rate
from analysis.report_metadata import build_report_metadata
from analysis.time_utils import parse_iso8601_utc, parse_utc_series
from analysis.trade_math import compute_r_multiple

REQUIRED_TRADE_COLUMNS = {"trade_id", "symbol", "is_long", "entry_time", "exit_time", "entry_price", "stop_price"}
REQUIRED_BAR_COLUMNS = {"symbol", "timestamp", "close"}


@dataclass(frozen=True)
class TradeGivebackComparison:
    trade_id: str
    actual_final_r: float
    v637_trigger_bar: Optional[int]
    v637_trigger_r: Optional[float]
    v637_r_diff: float  # trigger_r - actual_final_r: positive means the
                         # guard would have closed at a BETTER R than the
                         # trade actually ended with (guard would have
                         # helped); negative means it would have closed
                         # early and hurt. 0.0 if the guard never triggered.
    v811_trigger_bar: Optional[int]
    v811_trigger_r: Optional[float]
    v811_r_diff: float


@dataclass(frozen=True)
class GivebackRunResult:
    comparisons: list[TradeGivebackComparison]
    row_errors: list[dict]


def run(
    trades_csv: Path,
    bars_csv: Path,
    output_csv: Optional[Path] = None,
    summary_json: Optional[Path] = None,
    *,
    v637_arm_rr: float = 1.25,
    v637_giveback_percent: float = 60.0,
    v637_floor_r: float = 0.05,
    v811_arm_r: float = 0.8,
    v811_floor_r: float = 0.1,
    symbol: Optional[str] = None,
    seed: Optional[int] = None,
    repo_path: Optional[Path] = None,
) -> GivebackRunResult:
    for out_path in (output_csv, summary_json):
        if out_path is not None and out_path.resolve() in (trades_csv.resolve(), bars_csv.resolve()):
            raise CsvSchemaError(f"output path {out_path} must not be the same as an input path")

    trades = read_csv_with_required_columns(trades_csv, REQUIRED_TRADE_COLUMNS)
    bars = read_csv_with_required_columns(bars_csv, REQUIRED_BAR_COLUMNS)
    assert_unique_ids(trades, "trade_id", trades_csv)
    assert_finite_columns(trades, ["entry_price", "stop_price"], trades_csv)
    assert_finite_columns(bars, ["close"], bars_csv)

    bars = bars.copy()
    bars["timestamp"] = parse_utc_series(bars["timestamp"])

    comparisons: list[TradeGivebackComparison] = []
    row_errors: list[dict] = []

    for _, row in trades.iterrows():
        trade_id = str(row["trade_id"])
        try:
            is_long = parse_is_long(row["is_long"])
            entry_time = parse_iso8601_utc(str(row["entry_time"]))
            exit_time = parse_iso8601_utc(str(row["exit_time"]))
            entry_price = float(row["entry_price"])
            stop_price = float(row["stop_price"])

            symbol_bars = bars[
                (bars["symbol"] == row["symbol"])
                & (bars["timestamp"] >= entry_time)
                & (bars["timestamp"] <= exit_time)
            ].sort_values("timestamp")

            if symbol_bars.empty:
                row_errors.append({"trade_id": trade_id, "error": "no bars found in trade window"})
                continue

            r_path = [
                compute_r_multiple(is_long, entry_price, stop_price, close)
                for close in symbol_bars["close"]
            ]

            has_exit_price = "exit_price" in trades.columns and pd.notna(row.get("exit_price"))
            if has_exit_price:
                actual_final_r = compute_r_multiple(is_long, entry_price, stop_price, float(row["exit_price"]))
            else:
                actual_final_r = r_path[-1]

            v637_result = simulate_giveback_path(
                r_path,
                "v637",
                arm_rr=v637_arm_rr,
                giveback_percent=v637_giveback_percent,
                close_trigger_floor_r=v637_floor_r,
            )
            v811_result = simulate_giveback_path(r_path, "v811", arm_r=v811_arm_r, floor_r=v811_floor_r)

            v637_bar, v637_r = v637_result if v637_result else (None, None)
            v811_bar, v811_r = v811_result if v811_result else (None, None)

            comparisons.append(
                TradeGivebackComparison(
                    trade_id=trade_id,
                    actual_final_r=actual_final_r,
                    v637_trigger_bar=v637_bar,
                    v637_trigger_r=v637_r,
                    v637_r_diff=(v637_r - actual_final_r) if v637_r is not None else 0.0,
                    v811_trigger_bar=v811_bar,
                    v811_trigger_r=v811_r,
                    v811_r_diff=(v811_r - actual_final_r) if v811_r is not None else 0.0,
                )
            )
        except (ValueError, KeyError) as exc:
            row_errors.append({"trade_id": trade_id, "error": str(exc)})

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        pd.DataFrame([c.__dict__ for c in comparisons]).to_csv(output_csv, index=False)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [trades_csv, bars_csv], symbol=symbol, random_seed=seed, repo_path=repo_path
        )
        summary = {
            "metadata": metadata.to_dict(),
            "n_trades_compared": len(comparisons),
            "n_row_errors": len(row_errors),
            "row_errors": row_errors,
        }
        for model in ("v637", "v811"):
            triggered = [c for c in comparisons if getattr(c, f"{model}_trigger_r") is not None]
            summary[model] = {
                "n_triggered": len(triggered),
                "n_not_triggered": len(comparisons) - len(triggered),
                "mean_r_diff_when_triggered": (
                    sum(getattr(c, f"{model}_r_diff") for c in triggered) / len(triggered)
                    if triggered
                    else None
                ),
            }
            if triggered:
                try:
                    wr = win_rate([getattr(c, f"{model}_r_diff") > 0.0 for c in triggered])
                    summary[model]["guard_helped_rate"] = wr.win_rate
                    summary[model]["guard_helped_rate_ci"] = [wr.ci_lower, wr.ci_upper]
                    summary[model]["guard_helped_rate_n"] = wr.n
                except InsufficientSampleError:
                    pass
        summary_json.write_text(json.dumps(summary, indent=2, default=str, allow_nan=False), encoding="utf-8")

    return GivebackRunResult(comparisons=comparisons, row_errors=row_errors)


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trades-csv", required=True, type=Path)
    parser.add_argument("--bars-csv", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--summary-json", type=Path, default=None)
    parser.add_argument("--v637-arm-rr", type=float, default=1.25)
    parser.add_argument("--v637-giveback-percent", type=float, default=60.0)
    parser.add_argument("--v637-floor-r", type=float, default=0.05)
    parser.add_argument("--v811-arm-r", type=float, default=0.8)
    parser.add_argument("--v811-floor-r", type=float, default=0.1)
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
            summary_json=args.summary_json,
            v637_arm_rr=args.v637_arm_rr,
            v637_giveback_percent=args.v637_giveback_percent,
            v637_floor_r=args.v637_floor_r,
            v811_arm_r=args.v811_arm_r,
            v811_floor_r=args.v811_floor_r,
            symbol=args.symbol,
            seed=args.seed,
        )
    except (FileNotFoundError, CsvSchemaError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"analyse_giveback: {len(result.comparisons)} compared, {len(result.row_errors)} row errors.")
    return 1 if result.row_errors else 0


if __name__ == "__main__":
    sys.exit(main())
