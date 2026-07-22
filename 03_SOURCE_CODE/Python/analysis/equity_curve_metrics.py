"""equity_curve_metrics.py -- Python consumer for EquityTickRecorder.mq5's
real intratrade, mark-to-market account-equity series (TASK-037's own
equity-tick export), computing the giveback metrics
``analysis.metrics.compute_balance_peak_giveback`` explicitly does NOT
provide (that function is a closed-trade BALANCE proxy only, per its own
docstring): a genuine "Account equity-peak giveback" (an all-time running
peak, never resetting) and a "Daily equity-peak giveback" (the SAME arm/
trigger formula, but the running peak resets at each UTC calendar-day
boundary). Also reports the maximum account-equity drawdown over the
whole series.

**Added, 2026-07-22 (Codex review finding, seventh round, P1 finding 13):**
EquityTickRecorder.mq5 (this same review round's own MQL-side fix, via
EventSetMillisecondTimer -- see that file's header) now produces a genuine
account-level, symbol-agnostic equity series. This module is the Python
consumer that was still missing -- without it, the export was "useful
scaffolding" only (the review's own words), closing neither round-6 P0-2
nor the master-prompt/test-plan deliverables it names.

**Reuses, does not duplicate, existing math:** ``compute_max_drawdown``
and ``compute_balance_peak_giveback`` (``analysis/metrics.py``) are both
already curve-agnostic (operate on any ``Sequence[float]``, regardless of
whether the values happen to be a closed-trade balance curve or a real
mark-to-market equity series) -- this module feeds the real equity column
into them directly rather than re-deriving the same formulas under a new
name. The only genuinely NEW logic here is
``compute_daily_equity_peak_giveback``'s per-UTC-calendar-day peak reset,
which ``compute_balance_peak_giveback``'s own whole-curve peak cannot
express.

**Cost-sensitivity comparisons remain a separate, unimplemented gap**
(named explicitly in the same review finding this module resolves the
equity-giveback half of) -- that needs a cost-SCENARIO export (the same
trade set re-priced under multiple explicit spread/slippage assumptions),
which is ``TASK-037_MT5_EXPORT_BRIDGE.md``'s own item 8, not built by this
module or this round. See ``compare_releases.py``'s own
``surface_not_covered.cost_sensitivity`` disclosure, which still applies.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence

import pandas as pd

from analysis.csv_io import (
    CsvSchemaError,
    assert_path_not_same_file,
    read_csv_with_required_columns_and_hash,
)
from analysis.metrics import (
    BalancePeakGivebackResult,
    MaxDrawdownResult,
    compute_balance_peak_giveback,
    compute_max_drawdown,
)
from analysis.report_metadata import atomic_write_text, build_report_metadata
from analysis.time_utils import parse_utc_series

REQUIRED_COLUMNS = {
    "timestamp_utc",
    "run_id",
    "account_login",
    "broker_server",
    "equity",
    "balance",
}


@dataclass(frozen=True)
class DailyGivebackDay:
    date: str  # ISO calendar date (UTC), e.g. "2026-07-21"
    n_ticks: int
    armed: bool
    n_trigger_events: int
    max_giveback_pct: float


@dataclass(frozen=True)
class DailyEquityGivebackResult:
    arm_percent: float
    floor_percent: float
    days: tuple  # tuple[DailyGivebackDay, ...]
    total_trigger_events: int
    worst_day_date: Optional[str]
    worst_day_giveback_pct: float


def read_equity_ticks_csv(path: Path) -> tuple[pd.DataFrame, str]:
    """Reads and validates an equity_ticks.csv (EquityTickRecorder.mq5's
    own schema), sorted into chronological order (the export is already
    chronological by construction -- one row appended per timer tick --
    but this does not trust that blindly; a caller-supplied file could be
    hand-edited or concatenated out of order). Raises CsvSchemaError for
    structural problems (missing columns, zero rows, a null/non-finite
    equity or balance value)."""

    df, file_hash = read_csv_with_required_columns_and_hash(path, REQUIRED_COLUMNS)
    if df.empty:
        raise CsvSchemaError(f"{path}: zero rows")

    df = df.copy()
    df["timestamp_utc"] = parse_utc_series(df["timestamp_utc"])
    for col in ("equity", "balance"):
        df[col] = pd.to_numeric(df[col], errors="coerce")
        if not df[col].apply(lambda v: pd.notna(v) and math.isfinite(v)).all():
            raise CsvSchemaError(f"{path}: '{col}' contains a null/non-finite value")

    df = df.sort_values("timestamp_utc").reset_index(drop=True)
    return df, file_hash


def compute_daily_equity_peak_giveback(
    timestamps: Sequence[pd.Timestamp],
    equity_curve: Sequence[float],
    arm_percent: float = 1.0,
    floor_percent: float = 0.5,
) -> DailyEquityGivebackResult:
    """The SAME arm/trigger giveback formula
    ``compute_balance_peak_giveback`` implements, but with the running
    peak reset at each UTC calendar-day boundary -- the "Daily equity-peak
    giveback" master-prompt metric, which (unlike
    ``compute_balance_peak_giveback``'s own whole-curve peak) genuinely
    needs a per-day reset. Groups 'timestamps'/'equity_curve' by UTC
    calendar date and re-runs ``compute_balance_peak_giveback``
    independently on each day's own slice (already curve-agnostic, so no
    duplicated math), then aggregates across days.

    Raises ValueError if 'timestamps' and 'equity_curve' are not the same
    length.
    """

    if len(timestamps) != len(equity_curve):
        raise ValueError(
            "compute_daily_equity_peak_giveback: 'timestamps' and 'equity_curve' must be the "
            "same length"
        )

    frame = pd.DataFrame({"timestamp": pd.DatetimeIndex(timestamps), "equity": list(equity_curve)})
    frame["date"] = frame["timestamp"].dt.strftime("%Y-%m-%d")

    days: list[DailyGivebackDay] = []
    total_trigger_events = 0
    worst_day_date: Optional[str] = None
    worst_day_giveback_pct = 0.0

    for date, group in frame.groupby("date", sort=True):
        day_equity = group["equity"].tolist()
        day_result = compute_balance_peak_giveback(day_equity, arm_percent, floor_percent)
        days.append(
            DailyGivebackDay(
                date=str(date),
                n_ticks=len(day_equity),
                armed=day_result.armed,
                n_trigger_events=day_result.n_trigger_events,
                max_giveback_pct=day_result.max_giveback_pct,
            )
        )
        total_trigger_events += day_result.n_trigger_events
        if day_result.max_giveback_pct > worst_day_giveback_pct:
            worst_day_giveback_pct = day_result.max_giveback_pct
            worst_day_date = str(date)

    return DailyEquityGivebackResult(
        arm_percent=arm_percent,
        floor_percent=floor_percent,
        days=tuple(days),
        total_trigger_events=total_trigger_events,
        worst_day_date=worst_day_date,
        worst_day_giveback_pct=worst_day_giveback_pct,
    )


@dataclass(frozen=True)
class EquityCurveMetricsResult:
    n_ticks: int
    max_drawdown: MaxDrawdownResult
    account_peak_giveback: BalancePeakGivebackResult
    daily_peak_giveback: DailyEquityGivebackResult


def compute_equity_curve_metrics(
    timestamps: Sequence[pd.Timestamp],
    equity_curve: Sequence[float],
    arm_percent: float = 1.0,
    floor_percent: float = 0.5,
) -> EquityCurveMetricsResult:
    """The three required metrics, computed together from the same
    equity series: max account-equity drawdown (whole series),
    account-peak giveback (whole series, never resetting), and
    daily-reset equity-peak giveback (per UTC calendar day)."""

    return EquityCurveMetricsResult(
        n_ticks=len(equity_curve),
        max_drawdown=compute_max_drawdown(equity_curve),
        account_peak_giveback=compute_balance_peak_giveback(equity_curve, arm_percent, floor_percent),
        daily_peak_giveback=compute_daily_equity_peak_giveback(
            timestamps, equity_curve, arm_percent, floor_percent
        ),
    )


def run(
    equity_ticks_csv: Path,
    summary_json: Optional[Path] = None,
    *,
    arm_percent: float = 1.0,
    floor_percent: float = 0.5,
    repo_path: Optional[Path] = None,
) -> EquityCurveMetricsResult:
    """Reads 'equity_ticks_csv' and computes the three required equity-
    based metrics. Writes a summary JSON (result + real dataset-hash/git
    provenance) if 'summary_json' is given. Raises CsvSchemaError for
    structural input problems."""

    if summary_json is not None:
        assert_path_not_same_file(summary_json, equity_ticks_csv, "summary_json")

    df, file_hash = read_equity_ticks_csv(equity_ticks_csv)
    equity_curve = df["equity"].tolist()
    result = compute_equity_curve_metrics(
        df["timestamp_utc"].tolist(), equity_curve, arm_percent, floor_percent
    )

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [equity_ticks_csv],
            repo_path=repo_path,
            dataset_hash_override=file_hash,
        )
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_ticks": result.n_ticks,
                "arm_percent": arm_percent,
                "floor_percent": floor_percent,
                "max_drawdown_abs": result.max_drawdown.max_drawdown_abs,
                "max_drawdown_pct": result.max_drawdown.max_drawdown_pct,
                "account_peak_giveback_armed": result.account_peak_giveback.armed,
                "account_peak_giveback_n_trigger_events": (
                    result.account_peak_giveback.n_trigger_events
                ),
                "account_peak_giveback_max_pct": result.account_peak_giveback.max_giveback_pct,
                "daily_peak_giveback_total_trigger_events": (
                    result.daily_peak_giveback.total_trigger_events
                ),
                "daily_peak_giveback_worst_day_date": result.daily_peak_giveback.worst_day_date,
                "daily_peak_giveback_worst_day_pct": (
                    result.daily_peak_giveback.worst_day_giveback_pct
                ),
                "daily_peak_giveback_n_days": len(result.daily_peak_giveback.days),
            },
        }
        atomic_write_text(summary_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return result


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--equity-ticks-csv", type=Path, required=True)
    parser.add_argument("--summary-json", type=Path, default=None)
    parser.add_argument("--arm-percent", type=float, default=1.0)
    parser.add_argument("--floor-percent", type=float, default=0.5)
    args = parser.parse_args(argv)

    try:
        result = run(
            args.equity_ticks_csv,
            args.summary_json,
            arm_percent=args.arm_percent,
            floor_percent=args.floor_percent,
        )
    except (CsvSchemaError, ValueError) as exc:
        print(f"equity_curve_metrics: {exc}", file=sys.stderr)
        return 1

    print(
        f"max_drawdown_pct={result.max_drawdown.max_drawdown_pct:.4f} "
        f"account_peak_giveback_max_pct={result.account_peak_giveback.max_giveback_pct:.4f} "
        f"daily_peak_giveback_worst_day_pct={result.daily_peak_giveback.worst_day_giveback_pct:.4f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
