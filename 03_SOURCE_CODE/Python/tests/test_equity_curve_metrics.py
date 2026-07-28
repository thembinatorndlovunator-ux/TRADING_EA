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


def _write_equity_ticks_csv(
    path,
    timestamps=None,
    equity=None,
    balance=None,
    timestamps_server=None,
    run_id=None,
    account_login=None,
    broker_server=None,
):
    timestamps = timestamps if timestamps is not None else TIMESTAMPS
    equity = equity if equity is not None else EQUITY
    balance = balance if balance is not None else equity
    # Server-local timestamps default to the SAME naive wall-clock reading
    # as the UTC ones (offset 0) when a test doesn't care about the
    # UTC-vs-server distinction -- strip the trailing "Z" only.
    timestamps_server = (
        timestamps_server if timestamps_server is not None else [t.rstrip("Z") for t in timestamps]
    )
    df = pd.DataFrame(
        {
            "timestamp_utc": timestamps,
            "timestamp_server": timestamps_server,
            "run_id": run_id if run_id is not None else [1] * len(timestamps),
            "account_login": account_login
            if account_login is not None
            else [12345] * len(timestamps),
            "broker_server": broker_server
            if broker_server is not None
            else ["Deriv-Demo"] * len(timestamps),
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


def test_read_equity_ticks_csv_rejects_blank_timestamp_server(tmp_path):
    """Regression for a Codex review finding (2026-07-28, tenth round, P1
    finding 12): pd.to_datetime(..., errors="raise") does NOT raise for a
    blank cell -- it silently converts it to NaT, which
    compute_daily_equity_peak_giveback's own groupby("date") then silently
    DROPS. A blank timestamp_server value must be rejected explicitly at
    ingestion, not silently accepted as a valid (but nonexistent) date."""
    path = tmp_path / "equity_ticks.csv"
    server_ts = [t.rstrip("Z") for t in TIMESTAMPS]
    server_ts[2] = ""  # blank -- pd.to_datetime silently parses this as NaT
    _write_equity_ticks_csv(path, timestamps_server=server_ts)
    with pytest.raises(CsvSchemaError, match="timestamp_server"):
        read_equity_ticks_csv(path)


def test_run_blank_timestamp_server_cannot_yield_a_zero_day_report(tmp_path):
    """Regression for a Codex review finding (2026-07-28, tenth round, P1
    finding 12): the review's own reproduced counterexample -- a probe
    with blank timestamp_server values returned a valid account drawdown
    but daily_days=0, silently omitting the entire curve from the daily
    giveback report. run() must now raise CsvSchemaError instead of
    silently producing a zero-day report."""
    equity_ticks_csv = tmp_path / "equity_ticks.csv"
    server_ts = [t.rstrip("Z") for t in TIMESTAMPS]
    server_ts[0] = ""
    server_ts[1] = ""
    _write_equity_ticks_csv(equity_ticks_csv, timestamps_server=server_ts)

    with pytest.raises(CsvSchemaError, match="timestamp_server"):
        run(equity_ticks_csv)


def test_read_equity_ticks_csv_rejects_missing_column(tmp_path):
    path = tmp_path / "equity_ticks.csv"
    df = pd.DataFrame({"timestamp_utc": TIMESTAMPS, "equity": EQUITY})
    df.to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        read_equity_ticks_csv(path)


def test_read_equity_ticks_csv_rejects_mixed_run_ids(tmp_path):
    """Regression for a Codex review finding (2026-07-22, eighth round, P1
    finding 18): EquityTickRecorder.mq5 deliberately appends run_id/
    account_login/broker_server so repeated runs are distinguishable, but
    this reader previously only checked those columns EXIST, never that
    they identify a SINGLE run -- sorting the whole file by timestamp and
    computing one curve silently stitched together unrelated equity
    series. The review's own reproduced counterexample: a two-run probe
    (here, run A ending near its own peak, run B starting from a much
    lower balance) previously produced an artificial ~90% "drawdown" at
    the seam between the two independent curves. Must now raise
    CsvSchemaError instead."""

    path = tmp_path / "equity_ticks.csv"
    df = pd.DataFrame(
        {
            "timestamp_utc": [
                "2026-07-21T10:00:00Z",
                "2026-07-21T11:00:00Z",
                "2026-07-22T09:00:00Z",
                "2026-07-22T10:00:00Z",
            ],
            "timestamp_server": [
                "2026-07-21T10:00:00",
                "2026-07-21T11:00:00",
                "2026-07-22T09:00:00",
                "2026-07-22T10:00:00",
            ],
            "run_id": [1, 1, 2, 2],  # run 2 is a DIFFERENT run appended to the same file
            "account_login": [12345, 12345, 12345, 12345],
            "broker_server": ["Deriv-Demo", "Deriv-Demo", "Deriv-Demo", "Deriv-Demo"],
            "equity": [
                10000.0,
                10500.0,
                1000.0,
                1050.0,
            ],  # run 2 starts near-zero relative to run 1's peak
            "balance": [10000.0, 10500.0, 1000.0, 1050.0],
        }
    )
    df.to_csv(path, index=False)
    with pytest.raises(CsvSchemaError, match="distinct.*run_id.*account_login.*broker_server"):
        read_equity_ticks_csv(path)


def test_read_equity_ticks_csv_rejects_mixed_accounts(tmp_path):
    """Same finding as test_read_equity_ticks_csv_rejects_mixed_run_ids --
    a different account_login (or broker_server) sharing the same file
    must also be rejected, not just a different run_id."""

    path = tmp_path / "equity_ticks.csv"
    df = pd.DataFrame(
        {
            "timestamp_utc": ["2026-07-21T10:00:00Z", "2026-07-21T11:00:00Z"],
            "timestamp_server": ["2026-07-21T10:00:00", "2026-07-21T11:00:00"],
            "run_id": [1, 1],
            "account_login": [12345, 67890],  # different account
            "broker_server": ["Deriv-Demo", "Deriv-Demo"],
            "equity": [10000.0, 1000.0],
            "balance": [10000.0, 1000.0],
        }
    )
    df.to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        read_equity_ticks_csv(path)


def test_read_equity_ticks_csv_rejects_wholly_blank_identity(tmp_path):
    """Regression for a Codex review finding (2026-07-27, ninth round, P1
    finding 16): the previous 'exactly one distinct identity' check alone
    accepted an entirely BLANK file (every row's run_id/account_login/
    broker_server empty) as one uniform, but meaningless, (NaN, NaN, NaN)
    tuple, and computed a curve from it (the review's own reproduced
    counterexample: a two-row probe with all three fields empty)."""

    path = tmp_path / "equity_ticks.csv"
    df = pd.DataFrame(
        {
            "timestamp_utc": ["2026-07-21T10:00:00Z", "2026-07-21T11:00:00Z"],
            "timestamp_server": ["2026-07-21T10:00:00", "2026-07-21T11:00:00"],
            "run_id": ["", ""],
            "account_login": ["", ""],
            "broker_server": ["", ""],
            "equity": [10000.0, 10500.0],
            "balance": [10000.0, 10500.0],
        }
    )
    df.to_csv(path, index=False)
    with pytest.raises(CsvSchemaError, match="blank/missing"):
        read_equity_ticks_csv(path)


def test_read_equity_ticks_csv_rejects_whitespace_only_identity(tmp_path):
    path = tmp_path / "equity_ticks.csv"
    _write_equity_ticks_csv(path, timestamps=TIMESTAMPS[:2], equity=EQUITY[:2], run_id=["  ", "  "])
    with pytest.raises(CsvSchemaError, match="blank/missing"):
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
    result = compute_daily_equity_peak_giveback(
        timestamps, EQUITY, arm_percent=1.0, floor_percent=0.5
    )

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


def test_run_groups_daily_giveback_by_server_clock_not_utc(tmp_path):
    """Regression for a Codex review finding (2026-07-27, ninth round, P1
    finding 16): the "daily" giveback metric previously grouped by UTC
    calendar date, but the live risk contract's own daily boundary resets
    at trade-server midnight -- a broker-server GMT offset can split one
    live risk day into two UTC dates (or merge pieces of two adjacent
    server days). This constructs exactly that split: three ticks whose
    UTC timestamps span two different UTC calendar dates (21st, 21st,
    22nd) but whose SERVER-local timestamps (a +3 offset) all fall on the
    SAME server calendar date (22nd). Grouping by UTC would report 2 days;
    grouping by the correct server clock must report exactly 1."""

    equity_ticks_csv = tmp_path / "equity_ticks.csv"
    _write_equity_ticks_csv(
        equity_ticks_csv,
        timestamps=[
            "2026-07-21T22:00:00Z",
            "2026-07-21T23:30:00Z",
            "2026-07-22T00:30:00Z",
        ],
        timestamps_server=[
            "2026-07-22T01:00:00",
            "2026-07-22T02:30:00",
            "2026-07-22T03:30:00",
        ],
        equity=[1000.0, 1010.0, 1005.0],
    )

    result = run(equity_ticks_csv)
    assert len(result.daily_peak_giveback.days) == 1, (
        "all three ticks share the SAME server-calendar day (2026-07-22) despite spanning "
        "two different UTC calendar dates -- grouping by UTC would incorrectly report 2 days"
    )
    assert result.daily_peak_giveback.days[0].date == "2026-07-22"


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
