from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.analyse_baseline import main, run
from analysis.csv_io import CsvSchemaError
from analysis.metrics import InsufficientSampleError

REPO_ROOT = Path(__file__).resolve().parents[3]


def _write_trades(path: Path) -> None:
    pd.DataFrame(
        [
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


def test_summary_hand_computed(tmp_path):
    path = tmp_path / "trades.csv"
    _write_trades(path)

    summary = run(path, starting_equity=0.0)

    assert summary["n_trades"] == 4
    assert summary["win_rate"]["value"] == pytest.approx(0.5)
    assert summary["win_rate"]["n"] == 4
    assert summary["expectancy_dollars"]["value"] == pytest.approx(12.5)
    assert summary["expectancy_r"]["value"] == pytest.approx(0.5)
    assert summary["profit_factor"] == pytest.approx(2.25)  # 90 / 40
    assert summary["gross_profit"] == pytest.approx(90.0)
    assert summary["gross_loss"] == pytest.approx(-40.0)
    assert summary["max_drawdown_abs"] == pytest.approx(20.0)
    assert summary["max_drawdown_pct"] == pytest.approx(0.5)  # 20 / 40
    assert summary["final_equity"] == pytest.approx(50.0)


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
