from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.analyse_baseline import main, run
from analysis.csv_io import CsvSchemaError
from analysis.metrics import InsufficientSampleError

REPO_ROOT = Path(__file__).resolve().parents[3]


def _write_trades(path: Path, rows: list[dict] | None = None) -> None:
    pd.DataFrame(
        rows
        or [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 102.0,
                "stop_price": 98.0,
                "profit": 40.0,
            },
            {
                "trade_id": "t2",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T02:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "exit_price": 99.0,
                "stop_price": 98.0,
                "profit": -20.0,
            },
            {
                "trade_id": "t3",
                "symbol": "XAUUSD",
                "is_long": "False",
                "entry_time": "2026-07-21T04:00:00Z",
                "exit_time": "2026-07-21T05:00:00Z",
                "entry_price": 100.0,
                "exit_price": 95.0,
                "stop_price": 102.0,
                "profit": 50.0,
            },
            {
                "trade_id": "t4",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T06:00:00Z",
                "exit_time": "2026-07-21T07:00:00Z",
                "entry_price": 100.0,
                "exit_price": 98.0,
                "stop_price": 98.0,
                "profit": -20.0,
            },
        ]
    ).to_csv(path, index=False)


def test_missing_column_raises(tmp_path):
    path = tmp_path / "trades.csv"
    pd.DataFrame({"trade_id": ["t1"]}).to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        run(path)


def test_empty_trades_raises(tmp_path):
    path = tmp_path / "trades.csv"
    pd.DataFrame(
        columns=[
            "trade_id", "symbol", "is_long", "entry_time", "exit_time",
            "entry_price", "exit_price", "stop_price", "profit",
        ]
    ).to_csv(path, index=False)
    with pytest.raises(InsufficientSampleError):
        run(path)


def test_non_positive_starting_balance_rejected(tmp_path):
    """Regression for a Codex review finding: a non-positive starting
    balance made percentage drawdown silently meaningless (0.0 default)."""

    path = tmp_path / "trades.csv"
    _write_trades(path)
    with pytest.raises(InsufficientSampleError):
        run(path, starting_balance=0.0)
    with pytest.raises(InsufficientSampleError):
        run(path, starting_balance=-500.0)


def test_non_finite_starting_balance_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22):
    `starting_balance <= 0` is False for NaN (every comparison against
    NaN is False in Python), so a NaN starting_balance previously slipped
    past that check and produced a NaN final balance with a plausible-
    looking 0.0 drawdown in memory instead of a visible error."""

    path = tmp_path / "trades.csv"
    _write_trades(path)
    with pytest.raises(InsufficientSampleError):
        run(path, starting_balance=float("nan"))


def test_naive_timestamp_rejected(tmp_path):
    """Regression for a Codex review finding: this script previously
    called pd.to_datetime(utc=True), which silently treats a naive string
    (no "Z"/offset) as if it were already UTC."""

    path = tmp_path / "trades.csv"
    rows = [
        {
            "trade_id": "t1", "symbol": "XAUUSD", "is_long": "True",
            "entry_time": "2026-07-21T00:00:00", "exit_time": "2026-07-21T01:00:00",  # naive
            "entry_price": 100.0, "exit_price": 102.0, "stop_price": 98.0, "profit": 40.0,
        }
    ]
    _write_trades(path, rows)
    with pytest.raises(ValueError):
        run(path)


def test_malformed_stop_geometry_rejected(tmp_path):
    """Regression for a Codex review finding: compute_r_multiple's live
    fail-safe silently returns 0R for malformed stop geometry -- a long
    trade with entry 100 and stop 101 must be rejected as malformed
    input, not reported as a plausible 0R trade."""

    path = tmp_path / "trades.csv"
    rows = [
        {
            "trade_id": "t1", "symbol": "XAUUSD", "is_long": "True",
            "entry_time": "2026-07-21T00:00:00Z", "exit_time": "2026-07-21T01:00:00Z",
            "entry_price": 100.0, "exit_price": 102.0, "stop_price": 101.0,  # stop on wrong side
            "profit": 40.0,
        }
    ]
    _write_trades(path, rows)
    with pytest.raises(CsvSchemaError):
        run(path)


def test_same_timestamp_trades_give_deterministic_drawdown(tmp_path):
    """Regression for a Codex review finding (2026-07-22): sorting only
    by exit_time leaves same-instant trades in an arbitrary tie-break
    order (CSV row order); reversing two same-time win/loss rows
    previously changed the observed max drawdown from 10.0% to ~9.09%
    with identical timestamps and net P/L. Same-instant P/L is now
    summed into one balance step before computing drawdown, so the
    result must be identical regardless of row order."""

    same_time = "2026-07-21T00:00:00Z"
    win_then_loss = [
        {"trade_id": "a", "symbol": "XAUUSD", "is_long": "True", "entry_time": same_time,
         "exit_time": same_time, "entry_price": 100.0, "exit_price": 110.0, "stop_price": 98.0,
         "profit": 100.0},
        {"trade_id": "b", "symbol": "XAUUSD", "is_long": "True", "entry_time": same_time,
         "exit_time": same_time, "entry_price": 100.0, "exit_price": 90.0, "stop_price": 98.0,
         "profit": -50.0},
    ]
    loss_then_win = list(reversed(win_then_loss))

    path_a = tmp_path / "a.csv"
    _write_trades(path_a, win_then_loss)
    path_b = tmp_path / "b.csv"
    _write_trades(path_b, loss_then_win)

    summary_a = run(path_a, starting_balance=1000.0)
    summary_b = run(path_b, starting_balance=1000.0)

    assert summary_a["max_balance_drawdown_abs"] == summary_b["max_balance_drawdown_abs"]
    assert summary_a["max_balance_drawdown_pct"] == summary_b["max_balance_drawdown_pct"]
    assert summary_a["final_balance"] == summary_b["final_balance"] == pytest.approx(1050.0)


def test_duplicate_trade_id_rejected(tmp_path):
    """Regression for a Codex review finding: duplicate trade_id values
    were never checked, silently double-counting a trade."""

    path = tmp_path / "trades.csv"
    _write_trades(
        path,
        [
            {"trade_id": "dup", "symbol": "XAUUSD", "is_long": "True",
             "entry_time": "2026-07-21T00:00:00Z", "exit_time": "2026-07-21T01:00:00Z",
             "entry_price": 100.0, "exit_price": 102.0, "stop_price": 98.0, "profit": 40.0},
            {"trade_id": "dup", "symbol": "XAUUSD", "is_long": "True",
             "entry_time": "2026-07-21T02:00:00Z", "exit_time": "2026-07-21T03:00:00Z",
             "entry_price": 100.0, "exit_price": 99.0, "stop_price": 98.0, "profit": -20.0},
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(path)


def test_non_finite_value_rejected(tmp_path):
    """Regression for a Codex review finding: NaN/non-numeric values in
    numeric columns were never checked before being fed into arithmetic."""

    path = tmp_path / "trades.csv"
    _write_trades(
        path,
        [
            {"trade_id": "t1", "symbol": "XAUUSD", "is_long": "True",
             "entry_time": "2026-07-21T00:00:00Z", "exit_time": "2026-07-21T01:00:00Z",
             "entry_price": 100.0, "exit_price": 102.0, "stop_price": 98.0, "profit": float("nan")},
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(path)


def test_output_path_colliding_with_input_rejected(tmp_path):
    """Regression for a Codex review finding: an output path equal to the
    input path would overwrite the source before/while reading it."""

    path = tmp_path / "trades.csv"
    _write_trades(path)
    with pytest.raises(CsvSchemaError):
        run(path, output_json=path)


def test_summary_hand_computed(tmp_path):
    path = tmp_path / "trades.csv"
    _write_trades(path)

    summary = run(path, starting_balance=1000.0)

    assert summary["n_trades"] == 4
    assert summary["win_rate"]["value"] == pytest.approx(0.5)
    assert summary["win_rate"]["n"] == 4
    assert summary["expectancy_dollars"]["value"] == pytest.approx(12.5)
    assert summary["expectancy_r"]["value"] == pytest.approx(0.5)
    assert summary["profit_factor"] == pytest.approx(2.25)  # 90 / 40
    assert summary["gross_profit"] == pytest.approx(90.0)
    assert summary["gross_loss"] == pytest.approx(-40.0)

    # balance_curve = [1000, 1040, 1020, 1070, 1050]
    # largest abs/pct decline both at peak=1040(idx1) -> trough=1020(idx2): 20, ~1.923%
    assert summary["max_balance_drawdown_abs"] == pytest.approx(20.0)
    assert summary["max_balance_drawdown_pct"] == pytest.approx(20.0 / 1040.0)
    assert summary["final_balance"] == pytest.approx(1050.0)
    assert summary["max_equity_drawdown"] is None


def test_r_multiples_hand_computed_per_trade(tmp_path):
    path = tmp_path / "trades.csv"
    _write_trades(path)
    per_trade_csv = tmp_path / "out" / "per_trade.csv"

    run(path, per_trade_csv=per_trade_csv)

    df = pd.read_csv(per_trade_csv).set_index("trade_id")
    assert df.loc["t1", "r_multiple"] == pytest.approx(1.0)
    assert df.loc["t2", "r_multiple"] == pytest.approx(-0.5)
    assert df.loc["t3", "r_multiple"] == pytest.approx(2.5)
    assert df.loc["t4", "r_multiple"] == pytest.approx(-1.0)


def test_writes_output_json_with_metadata(tmp_path):
    path = tmp_path / "trades.csv"
    _write_trades(path)
    output_json = tmp_path / "out" / "summary.json"

    run(path, output_json=output_json, symbol="XAUUSD", broker="Deriv", seed=1, repo_path=REPO_ROOT)

    payload = json.loads(output_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_trades"] == 4
    assert payload["metadata"]["symbol"] == "XAUUSD"
    assert payload["metadata"]["broker"] == "Deriv"


def test_cli_main_success(tmp_path, capsys):
    path = tmp_path / "trades.csv"
    _write_trades(path)
    exit_code = main(["--trades-csv", str(path)])
    assert exit_code == 0
    assert "n=4" in capsys.readouterr().out


def test_cli_main_missing_file(tmp_path, capsys):
    exit_code = main(["--trades-csv", str(tmp_path / "nope.csv")])
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err
