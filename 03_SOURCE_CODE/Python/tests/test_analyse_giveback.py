from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.analyse_giveback import main, run
from analysis.csv_io import CsvSchemaError

REPO_ROOT = Path(__file__).resolve().parents[3]


def _write_bars(path: Path, closes: list[float]) -> None:
    n = len(closes)
    pd.DataFrame(
        {
            "symbol": ["XAUUSD"] * n,
            "timestamp": pd.date_range("2026-07-21T00:00:00Z", periods=n, freq="h"),
            "close": closes,
        }
    ).to_csv(path, index=False)


def _write_trades(path: Path, rows: list[dict]) -> None:
    pd.DataFrame(rows).to_csv(path, index=False)


def test_missing_columns_raises(tmp_path):
    trades_path = tmp_path / "trades.csv"
    pd.DataFrame({"trade_id": ["t1"]}).to_csv(trades_path, index=False)
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0])

    with pytest.raises(CsvSchemaError):
        run(trades_path, bars_path)


def test_guard_would_have_helped_hand_computed(tmp_path):
    # r_path (R = (close-100)/2 for a long, risk=2): 0.5, 1.0, 2.0, 0.7, 0.3
    # -> closes: 101, 102, 104, 101.4, 100.6
    # V637 triggers at index 3 (r=0.7); the trade's LAST bar (index 4,
    # r=0.3, no exit_price given) is worse -> guard would have helped:
    # r_diff = 0.7 - 0.3 = 0.4
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0, 102.0, 104.0, 101.4, 100.6])
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T04:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )

    result = run(trades_path, bars_path)
    assert len(result.comparisons) == 1
    c = result.comparisons[0]
    assert c.actual_final_r == pytest.approx(0.3)
    assert c.v637_trigger_bar == 3
    assert c.v637_trigger_r == pytest.approx(0.7)
    assert c.v637_r_diff == pytest.approx(0.4)


def test_guard_would_have_hurt_when_price_recovers(tmp_path):
    # Same trigger point (index 3, r=0.7), but price recovers afterward to
    # a HIGHER final R than the guard's trigger -> guard would have hurt:
    # r_diff = 0.7 - 1.2 = -0.5
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0, 102.0, 104.0, 101.4, 102.4])  # last close -> R=1.2
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T04:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )

    result = run(trades_path, bars_path)
    c = result.comparisons[0]
    assert c.actual_final_r == pytest.approx(1.2)
    assert c.v637_r_diff == pytest.approx(-0.5)


def test_exit_price_column_overrides_last_bar_close(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0, 102.0])
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
                "exit_price": 106.0,  # R = 3.0, not the last bar's R=1.0
            }
        ],
    )

    result = run(trades_path, bars_path)
    assert result.comparisons[0].actual_final_r == pytest.approx(3.0)


def test_never_triggered_gives_zero_diff(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [100.5])  # R = 0.25, never arms (< 1.25)
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T00:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )

    result = run(trades_path, bars_path)
    c = result.comparisons[0]
    assert c.v637_trigger_r is None
    assert c.v637_r_diff == 0.0
    assert c.v811_trigger_r is None
    assert c.v811_r_diff == 0.0


def test_no_bars_in_window_is_a_row_error(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0])
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "no-data",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2027-01-01T00:00:00Z",
                "exit_time": "2027-01-01T01:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )

    result = run(trades_path, bars_path)
    assert result.comparisons == []
    assert len(result.row_errors) == 1


def test_writes_output_csv_and_summary_json(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0, 102.0, 104.0, 101.4, 100.6])
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T04:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )

    out_csv = tmp_path / "out" / "giveback.csv"
    summary_json = tmp_path / "out" / "summary.json"
    run(trades_path, bars_path, output_csv=out_csv, summary_json=summary_json, seed=1, repo_path=REPO_ROOT)

    assert out_csv.exists()
    df = pd.read_csv(out_csv)
    assert len(df) == 1

    assert summary_json.exists()
    summary = json.loads(summary_json.read_text(encoding="utf-8"))
    assert summary["n_trades_compared"] == 1
    assert summary["v637"]["n_triggered"] == 1


def test_cli_main_success(tmp_path, capsys):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0])
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T00:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )
    exit_code = main(["--trades-csv", str(trades_path), "--bars-csv", str(bars_path)])
    assert exit_code == 0
    assert "1 compared" in capsys.readouterr().out


def test_duplicate_trade_id_rejected(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0])
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {"trade_id": "dup", "symbol": "XAUUSD", "is_long": "True",
             "entry_time": "2026-07-21T00:00:00Z", "exit_time": "2026-07-21T00:00:00Z",
             "entry_price": 100.0, "stop_price": 98.0},
            {"trade_id": "dup", "symbol": "XAUUSD", "is_long": "True",
             "entry_time": "2026-07-21T00:00:00Z", "exit_time": "2026-07-21T00:00:00Z",
             "entry_price": 100.0, "stop_price": 98.0},
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(trades_path, bars_path)


def test_non_finite_stop_price_rejected(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0])
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [{"trade_id": "t1", "symbol": "XAUUSD", "is_long": "True",
          "entry_time": "2026-07-21T00:00:00Z", "exit_time": "2026-07-21T00:00:00Z",
          "entry_price": 100.0, "stop_price": float("nan")}],
    )
    with pytest.raises(CsvSchemaError):
        run(trades_path, bars_path)


def test_naive_timestamp_captured_as_row_error(tmp_path):
    """Regression for a Codex review finding: pd.to_datetime(utc=True)
    silently accepted a naive timestamp as UTC."""

    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0])
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [{"trade_id": "naive-1", "symbol": "XAUUSD", "is_long": "True",
          "entry_time": "2026-07-21T00:00:00", "exit_time": "2026-07-21T00:00:00Z",
          "entry_price": 100.0, "stop_price": 98.0}],
    )
    result = run(trades_path, bars_path)
    assert result.comparisons == []
    assert len(result.row_errors) == 1
    assert result.row_errors[0]["trade_id"] == "naive-1"


def test_output_path_colliding_with_input_rejected(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0])
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [{"trade_id": "t1", "symbol": "XAUUSD", "is_long": "True",
          "entry_time": "2026-07-21T00:00:00Z", "exit_time": "2026-07-21T00:00:00Z",
          "entry_price": 100.0, "stop_price": 98.0}],
    )
    with pytest.raises(CsvSchemaError):
        run(trades_path, bars_path, output_csv=trades_path)


def test_summary_json_includes_actual_row_errors_not_just_count(tmp_path):
    """Regression for a Codex review finding: only a row-error COUNT was
    written, losing which trades actually failed."""

    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0])
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [{"trade_id": "bad-1", "symbol": "XAUUSD", "is_long": "True",
          "entry_time": "2027-01-01T00:00:00Z", "exit_time": "2027-01-01T01:00:00Z",
          "entry_price": 100.0, "stop_price": 98.0}],
    )
    summary_json = tmp_path / "out" / "summary.json"
    run(trades_path, bars_path, summary_json=summary_json)

    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["n_row_errors"] == 1
    assert payload["row_errors"][0]["trade_id"] == "bad-1"


def test_cli_main_returns_nonzero_when_row_errors_present(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0])
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [{"trade_id": "bad-1", "symbol": "XAUUSD", "is_long": "True",
          "entry_time": "2027-01-01T00:00:00Z", "exit_time": "2027-01-01T01:00:00Z",
          "entry_price": 100.0, "stop_price": 98.0}],
    )
    exit_code = main(["--trades-csv", str(trades_path), "--bars-csv", str(bars_path)])
    assert exit_code == 1
