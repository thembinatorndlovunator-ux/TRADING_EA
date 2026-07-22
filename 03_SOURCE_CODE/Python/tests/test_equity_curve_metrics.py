from __future__ import annotations

import json

import pandas as pd
import pytest

from analysis.csv_io import CsvSchemaError
from analysis.equity_curve_metrics import (
    compute_daily_equity_peak_giveback,
    compute_equity_curve_metrics,
    read_equity_ticks_csv,
    run,
)

# Two UTC calendar days, continuous (day 2's first tick == day 1's last
# tick): day 1 = [1000, 1010, 1005], day 2 = [1005, 1020, 995].
TIMESTAMPS = [
    "2026-07-21T10:00:00Z",
    "2026-07-21T11:00:00Z",
    "2026-07-21T12:00:00Z",
    "2026-07-22T09:00:00Z",
    "2026-07-22T10:00:00Z",
    "2026-07-22T11:00:00Z",
]
EQUITY = [1000.0, 1010.0, 1005.0, 1005.0, 1020.0, 995.0]


def _write_equity_ticks_csv(path, timestamps=None, equity=None, balance=None):
    timestamps = timestamps if timestamps is not None else TIMESTAMPS
    equity = equity if equity is not None else EQUITY
    balance = balance if balance is not None else equity
    df = pd.DataFrame(
        {
            "timestamp_utc": timestamps,
            "run_id": [1] * len(timestamps),
            "account_login": [12345] * len(timestamps),
            "broker_server": ["Deriv-Demo"] * len(timestamps),
            "equity": equity,
            "balance": balance,
        }
    )
    df.to_csv(path, index=False)


# --- read_equity_ticks_csv ---------------------------------------------------


def test_read_equity_ticks_csv_round_trip(tmp_path):
    path = tmp_path / "equity_ticks.csv"
    _write_equity_ticks_csv(path)
    df, file_hash = read_equity_ticks_csv(path)
    assert len(df) == 6
    assert file_hash  # a real, non-empty hex digest
    assert df["equity"].tolist() == EQUITY


def test_read_equity_ticks_csv_sorts_chronologically(tmp_path):
    path = tmp_path / "equity_ticks.csv"
    # Deliberately out of order.
    _write_equity_ticks_csv(
        path,
        timestamps=["2026-07-21T12:00:00Z", "2026-07-21T10:00:00Z", "2026-07-21T11:00:00Z"],
        equity=[1005.0, 1000.0, 1010.0],
    )
    df, _ = read_equity_ticks_csv(path)
    assert df["equity"].tolist() == [1000.0, 1010.0, 1005.0]


def test_read_equity_ticks_csv_rejects_empty(tmp_path):
    path = tmp_path / "equity_ticks.csv"
    _write_equity_ticks_csv(path, timestamps=[], equity=[])
    with pytest.raises(CsvSchemaError):
        read_equity_ticks_csv(path)


def test_read_equity_ticks_csv_rejects_non_finite_equity(tmp_path):
    path = tmp_path / "equity_ticks.csv"
    _write_equity_ticks_csv(path, equity=[1000.0, float("nan"), 1005.0, 1005.0, 1020.0, 995.0])
    with pytest.raises(CsvSchemaError):
        read_equity_ticks_csv(path)


def test_read_equity_ticks_csv_rejects_missing_column(tmp_path):
    path = tmp_path / "equity_ticks.csv"
    df = pd.DataFrame({"timestamp_utc": TIMESTAMPS, "equity": EQUITY})
    df.to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        read_equity_ticks_csv(path)


# --- compute_daily_equity_peak_giveback --------------------------------------
#
# Hand-traced against compute_balance_peak_giveback's own formula
# (arm_percent=1.0, floor_percent=0.5 -- i.e. 1%/0.5%):
#
# Day 1 = [1000, 1010, 1005]:
#   i0: value=1000, peak=1000 -- (peak-start)/start=0 -> not armed.
#   i1: value=1010, peak=1010 -- (1010-1000)/1000=1.0% >= 1.0% -> ARMED.
#       giveback=(1010-1010)/1010=0.0 -> not triggered.
#   i2: value=1005, peak stays 1010 -- giveback=(1010-1005)/1010=0.49505%
#       < 0.5% -> not triggered. max_giveback_pct = 0.0049505.
#   Day 1 result: armed=True, n_trigger_events=0, max_giveback_pct=0.0049505.
#
# Day 2 = [1005, 1020, 995] (continuous with day 1's last value):
#   i0: value=1005, peak=1005, start=1005 -- not armed yet (this day's OWN
#       peak resets to this day's own first value).
#   i1: value=1020, peak=1020 -- (1020-1005)/1005=1.4925% >= 1.0% -> ARMED.
#       giveback=0.0 -> not triggered.
#   i2: value=995, peak stays 1020 -- giveback=(1020-995)/1020=2.45098%
#       >= 0.5% -> TRIGGERED (n_trigger_events=1). max_giveback_pct=0.0245098.
#   Day 2 result: armed=True, n_trigger_events=1, max_giveback_pct=0.0245098.
#
# Aggregated: total_trigger_events=1, worst_day="2026-07-22" (0.0245098 >
# 0.0049505).


def test_compute_daily_equity_peak_giveback_hand_traced():
    timestamps = pd.to_datetime(TIMESTAMPS, utc=True)
    result = compute_daily_equity_peak_giveback(timestamps, EQUITY, arm_percent=1.0, floor_percent=0.5)

    assert len(result.days) == 2
    day1, day2 = result.days
    assert day1.date == "2026-07-21"
    assert day1.armed is True
    assert day1.n_trigger_events == 0
    assert day1.max_giveback_pct == pytest.approx(0.0049505, abs=1e-6)

    assert day2.date == "2026-07-22"
    assert day2.armed is True
    assert day2.n_trigger_events == 1
    assert day2.max_giveback_pct == pytest.approx(0.0245098, abs=1e-6)

    assert result.total_trigger_events == 1
    assert result.worst_day_date == "2026-07-22"
    assert result.worst_day_giveback_pct == pytest.approx(0.0245098, abs=1e-6)


def test_compute_daily_equity_peak_giveback_rejects_mismatched_lengths():
    with pytest.raises(ValueError):
        compute_daily_equity_peak_giveback(
            pd.to_datetime(TIMESTAMPS[:3], utc=True), EQUITY, arm_percent=1.0, floor_percent=0.5
        )


# --- compute_equity_curve_metrics / run --------------------------------------
#
# max_drawdown over the WHOLE combined 6-point curve: peak reaches 1020 at
# index 4, trough 995 at index 5 -> max_drawdown_abs=25,
# max_drawdown_pct=25/1020=0.0245098 (same trough as day 2's own worst
# giveback, since it is the single worst point in the whole series).


def test_compute_equity_curve_metrics_hand_traced():
    timestamps = pd.to_datetime(TIMESTAMPS, utc=True)
    result = compute_equity_curve_metrics(timestamps, EQUITY, arm_percent=1.0, floor_percent=0.5)

    assert result.n_ticks == 6
    assert result.max_drawdown.max_drawdown_abs == pytest.approx(25.0)
    assert result.max_drawdown.max_drawdown_pct == pytest.approx(0.0245098, abs=1e-6)
    assert result.account_peak_giveback.armed is True
    assert result.daily_peak_giveback.total_trigger_events == 1


def test_run_writes_summary_json_with_real_provenance(tmp_path):
    equity_ticks_csv = tmp_path / "equity_ticks.csv"
    _write_equity_ticks_csv(equity_ticks_csv)
    summary_json = tmp_path / "out" / "equity_summary.json"

    result = run(equity_ticks_csv, summary_json)
    assert result.n_ticks == 6
    assert summary_json.exists()

    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["metadata"]["dataset_hash"]
    assert payload["metadata"]["git_commit"]
    assert payload["summary"]["n_ticks"] == 6
    assert payload["summary"]["max_drawdown_pct"] == pytest.approx(0.0245098, abs=1e-6)
    assert payload["summary"]["daily_peak_giveback_n_days"] == 2
    assert payload["summary"]["daily_peak_giveback_worst_day_date"] == "2026-07-22"


def test_run_without_summary_json_still_returns_result(tmp_path):
    equity_ticks_csv = tmp_path / "equity_ticks.csv"
    _write_equity_ticks_csv(equity_ticks_csv)
    result = run(equity_ticks_csv)
    assert result.n_ticks == 6


def test_run_rejects_summary_json_same_as_input(tmp_path):
    equity_ticks_csv = tmp_path / "equity_ticks.csv"
    _write_equity_ticks_csv(equity_ticks_csv)
    with pytest.raises(ValueError):
        run(equity_ticks_csv, equity_ticks_csv)
