from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.csv_io import CsvSchemaError
from analysis.metrics import InsufficientSampleError
from analysis.walk_forward import generate_windows, main, run

REPO_ROOT = Path(__file__).resolve().parents[3]


# --- generate_windows --------------------------------------------------------


def test_generate_windows_hand_traced():
    first = pd.Timestamp("2026-01-01", tz="UTC")
    last = pd.Timestamp("2026-01-10", tz="UTC")
    windows = generate_windows(first, last, train_days=3, test_days=2, step_days=2)

    assert len(windows) == 4
    assert windows[0] == (
        pd.Timestamp("2026-01-01", tz="UTC"),
        pd.Timestamp("2026-01-04", tz="UTC"),
        pd.Timestamp("2026-01-04", tz="UTC"),
        pd.Timestamp("2026-01-06", tz="UTC"),
    )
    assert windows[3] == (
        pd.Timestamp("2026-01-07", tz="UTC"),
        pd.Timestamp("2026-01-10", tz="UTC"),
        pd.Timestamp("2026-01-10", tz="UTC"),
        pd.Timestamp("2026-01-12", tz="UTC"),
    )


def test_generate_windows_rejects_non_positive_days():
    first = pd.Timestamp("2026-01-01", tz="UTC")
    last = pd.Timestamp("2026-01-10", tz="UTC")
    with pytest.raises(ValueError):
        generate_windows(first, last, train_days=0, test_days=2, step_days=2)
    with pytest.raises(ValueError):
        generate_windows(first, last, train_days=3, test_days=-1, step_days=2)


def test_generate_windows_rejects_first_after_last():
    with pytest.raises(ValueError):
        generate_windows(
            pd.Timestamp("2026-01-10", tz="UTC"), pd.Timestamp("2026-01-01", tz="UTC"), 3, 2, 2
        )


def test_generate_windows_no_data_span_yields_at_least_zero_windows():
    # A single-instant span shorter than train+test yields zero windows --
    # not an error, just nothing to report.
    same = pd.Timestamp("2026-01-01", tz="UTC")
    windows = generate_windows(same, same, train_days=3, test_days=2, step_days=2)
    assert windows == []


# --- run() --------------------------------------------------------------------


def _write_trades(path: Path) -> None:
    def row(trade_id, day_offset, exit_price, profit):
        exit_time = pd.Timestamp("2026-01-01", tz="UTC") + pd.Timedelta(days=day_offset)
        return {
            "trade_id": trade_id,
            "symbol": "XAUUSD",
            "is_long": "True",
            "entry_time": (exit_time - pd.Timedelta(hours=1)).isoformat(),
            "exit_time": exit_time.isoformat(),
            "entry_price": 100.0,
            "exit_price": exit_price,
            "stop_price": 98.0,
            "profit": profit,
        }

    pd.DataFrame(
        [
            row("t0", 0, 104.0, 10.0),  # r=2.0, win
            row("t1", 1, 99.0, -5.0),  # r=-0.5, loss
            row("t2", 2, 103.0, 10.0),  # r=1.5, win
            row("t4", 4, 105.0, 20.0),  # r=2.5, win
            row("t8", 8, 99.0, -5.0),  # r=-0.5, loss
        ]
    ).to_csv(path, index=False)


def test_missing_column_raises(tmp_path):
    path = tmp_path / "trades.csv"
    pd.DataFrame({"trade_id": ["t1"]}).to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        run(path, train_days=3, test_days=2, step_days=2)


def test_empty_trades_raises(tmp_path):
    path = tmp_path / "trades.csv"
    pd.DataFrame(
        columns=[
            "trade_id", "symbol", "is_long", "entry_time", "exit_time",
            "entry_price", "exit_price", "stop_price", "profit",
        ]
    ).to_csv(path, index=False)
    with pytest.raises(InsufficientSampleError):
        run(path, train_days=3, test_days=2, step_days=2)


def test_windows_hand_computed(tmp_path):
    # Data spans day0..day8 -> windows: train[0,3)/test[3,5),
    # train[2,5)/test[5,7), train[4,7)/test[7,9); a 4th window's
    # test_start (day9) would exceed last_time (day8), so only 3 windows.
    path = tmp_path / "trades.csv"
    _write_trades(path)

    df = run(path, train_days=3, test_days=2, step_days=2)
    assert len(df) == 3

    w0 = df.iloc[0]
    assert w0["train_n"] == 3  # days 0, 1, 2
    assert w0["train_win_rate"] == pytest.approx(2.0 / 3.0)
    assert w0["train_expectancy_r"] == pytest.approx((2.0 - 0.5 + 1.5) / 3.0)
    assert w0["test_n"] == 1  # day 4
    assert w0["test_win_rate"] == pytest.approx(1.0)
    assert w0["test_expectancy_r"] == pytest.approx(2.5)

    w1 = df.iloc[1]
    assert w1["train_n"] == 2  # days 2, 4
    assert w1["test_n"] == 0  # nothing in [day5, day7)
    assert pd.isna(w1["test_win_rate"]) or w1["test_win_rate"] is None

    w2 = df.iloc[2]
    assert w2["train_n"] == 1  # day 4 only
    assert w2["test_n"] == 1  # day 8


def test_writes_output_csv_and_summary_json(tmp_path):
    path = tmp_path / "trades.csv"
    _write_trades(path)
    out_csv = tmp_path / "out" / "windows.csv"
    summary_json = tmp_path / "out" / "summary.json"

    run(
        path, train_days=3, test_days=2, step_days=2,
        output_csv=out_csv, summary_json=summary_json, symbol="XAUUSD", repo_path=REPO_ROOT,
    )

    assert out_csv.exists()
    assert len(pd.read_csv(out_csv)) == 3

    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_windows"] == 3
    assert payload["summary"]["train_days"] == 3


def test_cli_main_success(tmp_path, capsys):
    path = tmp_path / "trades.csv"
    _write_trades(path)
    exit_code = main(
        ["--trades-csv", str(path), "--train-days", "3", "--test-days", "2", "--step-days", "2"]
    )
    assert exit_code == 0
    assert "3 windows" in capsys.readouterr().out


def test_cli_main_missing_file(tmp_path, capsys):
    exit_code = main(
        ["--trades-csv", str(tmp_path / "nope.csv"), "--train-days", "3", "--test-days", "2",
         "--step-days", "2"]
    )
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err
