from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.csv_io import CsvSchemaError
from analysis.join_signal_to_outcome import join_signal_to_outcome, main, run

REPO_ROOT = Path(__file__).resolve().parents[3]


def _journal_df(rows: list[dict]) -> pd.DataFrame:
    return pd.DataFrame(rows)


def _trades_df(rows: list[dict]) -> pd.DataFrame:
    return pd.DataFrame(rows)


def test_basic_join_hand_computed():
    journal = _journal_df(
        [
            {"order_id": "o1", "strategy": "SR_BOUNCE", "regime": "REGIME_TRENDING_UP"},
            {"order_id": "o2", "strategy": "SMC", "regime": "REGIME_RANGING"},
        ]
    )
    trades = _trades_df(
        [
            {"trade_id": "t1", "order_id": "o1", "profit": 50.0},
            {"trade_id": "t2", "order_id": "o2", "profit": -20.0},
        ]
    )
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    assert len(joined) == 2
    row1 = joined[joined["trade_id"] == "t1"].iloc[0]
    assert row1["strategy"] == "SR_BOUNCE"
    assert row1["profit"] == pytest.approx(50.0)


def test_partial_fill_one_order_maps_to_multiple_trades():
    """A single order (one journal decision) can produce multiple trade
    outcome rows (partial fills) -- each fill gets its own row but ALL
    inherit the same journal dimensional fields."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = _trades_df(
        [
            {"trade_id": "t1", "order_id": "o1", "profit": 30.0},
            {"trade_id": "t2", "order_id": "o1", "profit": 20.0},
        ]
    )
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    assert len(joined) == 2
    assert (joined["strategy"] == "SR_BOUNCE").all()


def test_orphaned_trade_outcome_is_a_row_error_not_silently_dropped():
    """A trade outcome whose order_id matches no journal decision is a
    row-level error, never silently dropped or silently joined to
    nothing."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = _trades_df(
        [
            {"trade_id": "t1", "order_id": "o1", "profit": 30.0},
            {"trade_id": "t_orphan", "order_id": "o_unknown", "profit": 10.0},
        ]
    )
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert len(joined) == 1
    assert len(row_errors) == 1
    assert row_errors[0]["trade_id"] == "t_orphan"


def test_unmatched_journal_decision_is_not_an_error():
    """A journal decision with no matching trade (rejected before
    submission, or not yet filled) is normal -- not an error, simply
    absent from the joined output."""

    journal = _journal_df(
        [
            {"order_id": "o1", "strategy": "SR_BOUNCE"},
            {"order_id": "o2", "strategy": "SMC"},  # never filled
        ]
    )
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": 30.0}])
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert len(joined) == 1
    assert row_errors == []


def test_duplicate_journal_order_id_rejected():
    """A decision legitimately submits at most one order -- a duplicate
    journal order_id is a schema error, not a valid multi-decision
    order."""

    journal = _journal_df(
        [
            {"order_id": "o1", "strategy": "SR_BOUNCE"},
            {"order_id": "o1", "strategy": "SMC"},
        ]
    )
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": 30.0}])
    with pytest.raises(CsvSchemaError):
        join_signal_to_outcome(journal, trades)


def test_null_journal_order_id_rejected():
    journal = _journal_df([{"order_id": None, "strategy": "SR_BOUNCE"}])
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": 30.0}])
    with pytest.raises(CsvSchemaError):
        join_signal_to_outcome(journal, trades)


# --- run() (CSV wrapper) ------------------------------------------------------


def test_run_writes_output_csv_and_errors_json(tmp_path):
    journal_csv = tmp_path / "journal.csv"
    pd.DataFrame([{"order_id": "o1", "strategy": "SR_BOUNCE"}]).to_csv(journal_csv, index=False)
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame(
        [
            {"trade_id": "t1", "order_id": "o1", "profit": 30.0},
            {"trade_id": "t2", "order_id": "o_unknown", "profit": 10.0},
        ]
    ).to_csv(trades_csv, index=False)

    output_csv = tmp_path / "out" / "unified.csv"
    errors_json = tmp_path / "out" / "errors.json"
    joined_df, row_errors = run(
        journal_csv, trades_csv, output_csv=output_csv, errors_json=errors_json, repo_path=REPO_ROOT
    )

    assert len(joined_df) == 1
    assert len(row_errors) == 1
    assert output_csv.exists()
    payload = json.loads(errors_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_row_errors"] == 1


def test_run_empty_trades_raises(tmp_path):
    from analysis.metrics import InsufficientSampleError

    journal_csv = tmp_path / "journal.csv"
    pd.DataFrame([{"order_id": "o1"}]).to_csv(journal_csv, index=False)
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame(columns=["trade_id", "order_id", "profit"]).to_csv(trades_csv, index=False)

    with pytest.raises(InsufficientSampleError):
        run(journal_csv, trades_csv)


def test_run_output_path_colliding_with_input_rejected(tmp_path):
    journal_csv = tmp_path / "journal.csv"
    pd.DataFrame([{"order_id": "o1"}]).to_csv(journal_csv, index=False)
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame([{"trade_id": "t1", "order_id": "o1", "profit": 30.0}]).to_csv(
        trades_csv, index=False
    )

    with pytest.raises(CsvSchemaError):
        run(journal_csv, trades_csv, output_csv=journal_csv)


def test_cli_main_returns_nonzero_when_row_errors_present(tmp_path):
    journal_csv = tmp_path / "journal.csv"
    pd.DataFrame([{"order_id": "o1"}]).to_csv(journal_csv, index=False)
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame([{"trade_id": "t1", "order_id": "o_unknown", "profit": 30.0}]).to_csv(
        trades_csv, index=False
    )

    exit_code = main(["--journal-csv", str(journal_csv), "--trades-csv", str(trades_csv)])
    assert exit_code == 1


def test_cli_main_missing_file(tmp_path, capsys):
    exit_code = main(
        ["--journal-csv", str(tmp_path / "nope.csv"), "--trades-csv", str(tmp_path / "nope2.csv")]
    )
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err
