from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.calculate_mfe_mae import TradesSchemaError, main, run

REPO_ROOT = Path(__file__).resolve().parents[3]


def _write_bars(path: Path) -> None:
    pd.DataFrame(
        {
            "symbol": ["XAUUSD"] * 4,
            "timestamp": [
                "2026-07-21T00:00:00Z",
                "2026-07-21T01:00:00Z",
                "2026-07-21T02:00:00Z",
                "2026-07-21T03:00:00Z",
            ],
            "high": [101.0, 105.0, 103.0, 104.0],
            "low": [99.0, 100.0, 97.0, 101.0],
        }
    ).to_csv(path, index=False)


def _write_trades(path: Path, rows: list[dict]) -> None:
    pd.DataFrame(rows).to_csv(path, index=False)


def test_missing_trade_column_raises(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    pd.DataFrame({"trade_id": ["t1"]}).to_csv(trades_path, index=False)

    with pytest.raises(TradesSchemaError):
        run(trades_path, bars_path)


def test_missing_bars_column_raises(tmp_path):
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )
    bars_path = tmp_path / "bars.csv"
    pd.DataFrame({"symbol": ["XAUUSD"]}).to_csv(bars_path, index=False)

    with pytest.raises(TradesSchemaError):
        run(trades_path, bars_path)


def test_valid_trade_hand_computed(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )

    result = run(trades_path, bars_path)
    assert len(result.results) == 1
    assert result.row_errors == []
    r = result.results[0]
    assert r.mfe_price == pytest.approx(5.0)
    assert r.mae_price == pytest.approx(3.0)


def test_header_only_trades_csv_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22): a header-only
    (zero-row) trades.csv previously produced a "successful" empty run
    (0 results, 0 row errors) instead of a visible insufficient-sample
    failure -- indistinguishable from "every trade was valid"."""

    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    pd.DataFrame(
        columns=[
            "trade_id",
            "symbol",
            "is_long",
            "entry_time",
            "exit_time",
            "entry_price",
            "stop_price",
        ]
    ).to_csv(trades_path, index=False)

    with pytest.raises(TradesSchemaError):
        run(trades_path, bars_path)


def test_malformed_stop_geometry_captured_as_row_error(tmp_path):
    """Regression for a Codex review finding: a long trade with entry
    100 and stop 101 is malformed and must be rejected, not silently
    computed as a plausible 0R trade."""

    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 101.0,  # stop on wrong side for a long
            }
        ],
    )

    result = run(trades_path, bars_path)
    assert result.results == []
    assert len(result.row_errors) == 1
    assert result.row_errors[0]["trade_id"] == "t1"


def test_misaligned_entry_time_captured_as_row_error(tmp_path):
    """Regression for a Codex review finding (2026-07-22): entry_time/
    exit_time must exactly match a bar timestamp -- a misaligned
    timestamp risks look-ahead/measurement contamination if silently
    tolerated."""

    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:30:00Z",  # not a bar timestamp
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )

    result = run(trades_path, bars_path)
    assert result.results == []
    assert len(result.row_errors) == 1


def test_malformed_is_long_captured_as_row_error_not_crash(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "bad-1",
                "symbol": "XAUUSD",
                "is_long": "sideways",  # malformed
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            },
            {
                "trade_id": "good-1",
                "symbol": "XAUUSD",
                "is_long": "False",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 102.0,
            },
        ],
    )

    result = run(trades_path, bars_path)
    assert len(result.results) == 1  # the good row still processed
    assert result.results[0].trade_id == "good-1"
    assert len(result.row_errors) == 1
    assert result.row_errors[0]["trade_id"] == "bad-1"


def test_no_bars_in_window_captured_as_row_error(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
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
    assert result.results == []
    assert len(result.row_errors) == 1
    assert "no-data" in result.row_errors[0]["trade_id"]


def test_writes_output_csv_and_errors_json(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )

    out_csv = tmp_path / "out" / "mfe_mae.csv"
    errors_json = tmp_path / "out" / "errors.json"
    run(
        trades_path,
        bars_path,
        output_csv=out_csv,
        errors_json=errors_json,
        seed=1,
        repo_path=REPO_ROOT,
    )

    assert out_csv.exists()
    df = pd.read_csv(out_csv)
    assert len(df) == 1
    assert df.iloc[0]["mfe_price"] == pytest.approx(5.0)

    assert errors_json.exists()
    payload = json.loads(errors_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_results"] == 1
    assert payload["summary"]["n_row_errors"] == 0


def test_cli_main_success(tmp_path, capsys):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )
    exit_code = main(["--trades-csv", str(trades_path), "--bars-csv", str(bars_path)])
    assert exit_code == 0
    assert "1 computed" in capsys.readouterr().out


def test_cli_main_missing_file_returns_error_exit_code(tmp_path, capsys):
    exit_code = main(
        ["--trades-csv", str(tmp_path / "nope.csv"), "--bars-csv", str(tmp_path / "nope2.csv")]
    )
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err


def test_duplicate_trade_id_rejected(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "dup",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            },
            {
                "trade_id": "dup",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            },
        ],
    )
    with pytest.raises(TradesSchemaError):
        run(trades_path, bars_path)


def test_non_finite_entry_price_rejected(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": float("nan"),
                "stop_price": 98.0,
            },
        ],
    )
    with pytest.raises(TradesSchemaError):
        run(trades_path, bars_path)


def test_duplicate_symbol_timestamp_bar_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    duplicate (symbol, timestamp) bars were not rejected, leaving it
    ambiguous which row's high/low applies at that instant."""

    bars_path = tmp_path / "bars.csv"
    pd.DataFrame(
        {
            "symbol": ["XAUUSD", "XAUUSD"],
            "timestamp": ["2026-07-21T00:00:00Z", "2026-07-21T00:00:00Z"],
            "high": [101.0, 102.0],
            "low": [99.0, 98.0],
        }
    ).to_csv(bars_path, index=False)
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
    with pytest.raises(TradesSchemaError):
        run(trades_path, bars_path)


def test_high_below_low_bar_rejected(tmp_path):
    bars_path = tmp_path / "bad_bars.csv"
    pd.DataFrame(
        {
            "symbol": ["XAUUSD"],
            "timestamp": ["2026-07-21T00:00:00Z"],
            "high": [90.0],
            "low": [100.0],
        }
    ).to_csv(bars_path, index=False)
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
            },
        ],
    )
    with pytest.raises(TradesSchemaError):
        run(trades_path, bars_path)


def test_naive_trade_timestamp_captured_as_row_error(tmp_path):
    """Regression for a Codex review finding: a naive timestamp string was
    previously silently accepted as UTC via pd.to_datetime(utc=True)."""

    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "naive-1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            },
        ],
    )
    result = run(trades_path, bars_path)
    assert result.results == []
    assert len(result.row_errors) == 1
    assert result.row_errors[0]["trade_id"] == "naive-1"


def test_output_path_colliding_with_input_rejected(tmp_path):
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )
    with pytest.raises(TradesSchemaError):
        run(trades_path, bars_path, output_csv=trades_path)


def test_cli_main_returns_nonzero_when_row_errors_present(tmp_path, capsys):
    """Regression for a Codex review finding: the CLI always returned 0
    even when every row failed."""

    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path)
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "bad-1",
                "symbol": "XAUUSD",
                "is_long": "sideways",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )
    exit_code = main(["--trades-csv", str(trades_path), "--bars-csv", str(bars_path)])
    assert exit_code == 1
