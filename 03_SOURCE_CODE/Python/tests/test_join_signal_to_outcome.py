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
    # Every trade row needs deal_id now (Codex review finding, 2026-07-22,
    # fourth round: deal_id was previously never read at all).
    for row in rows:
        row.setdefault("deal_id", f"d_{row['trade_id']}")
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
    assert row1["n_fills"] == 1


def test_partial_fill_one_order_aggregated_into_single_row():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    a single order (one journal decision) producing multiple trade
    outcome rows (partial fills) previously became multiple INDEPENDENT
    output rows, inflating a downstream statistical pipeline's n_trades
    with correlated observations. All fills for one order_id must now be
    aggregated into ONE output row: profit summed, n_fills counted, and
    every constituent trade_id/deal_id preserved for traceability."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = _trades_df(
        [
            {"trade_id": "t1", "order_id": "o1", "profit": 30.0},
            {"trade_id": "t2", "order_id": "o1", "profit": 20.0},
        ]
    )
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    assert len(joined) == 1
    row = joined.iloc[0]
    assert row["strategy"] == "SR_BOUNCE"
    assert row["profit"] == pytest.approx(50.0)
    assert row["n_fills"] == 2
    assert row["fill_trade_ids"] == "t1,t2"
    assert row["fill_deal_ids"] == "d_t1,d_t2"


def test_partial_fill_entry_exit_time_use_earliest_latest_across_fills():
    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = _trades_df(
        [
            {
                "trade_id": "t1",
                "order_id": "o1",
                "profit": 30.0,
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
            },
            {
                "trade_id": "t2",
                "order_id": "o1",
                "profit": 20.0,
                "entry_time": "2026-07-21T00:05:00Z",
                "exit_time": "2026-07-21T01:30:00Z",
            },
        ]
    )
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    row = joined.iloc[0]
    assert row["entry_time"] == "2026-07-21T00:00:00Z"
    assert row["exit_time"] == "2026-07-21T01:30:00Z"


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


def test_duplicate_submitted_journal_order_id_rejected():
    """A decision legitimately submits at most one order -- a duplicate
    SUBMITTED journal order_id is a schema error, not a valid
    multi-decision order."""

    journal = _journal_df(
        [
            {"order_id": "o1", "strategy": "SR_BOUNCE"},
            {"order_id": "o1", "strategy": "SMC"},
        ]
    )
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": 30.0}])
    with pytest.raises(CsvSchemaError):
        join_signal_to_outcome(journal, trades)


def test_null_journal_order_id_is_filtered_as_unsubmitted_not_rejected():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    the module's own docstring says a null/blank journal order_id is
    NORMAL (rejected before submission, or not yet filled) -- the round-3
    implementation instead aborted the ENTIRE journal the moment any row
    had a null order_id, directly contradicting that. A null-order_id
    decision must now be silently filtered out of matching, never raised
    as an error; an unrelated real order_id in trades still becomes an
    orphan since no SUBMITTED decision claims it."""

    journal = _journal_df(
        [
            {"order_id": None, "strategy": "SR_BOUNCE"},  # unsubmitted -- normal
            {"order_id": "o1", "strategy": "SMC"},
        ]
    )
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": 30.0}])
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    assert len(joined) == 1
    assert joined.iloc[0]["strategy"] == "SMC"


def test_blank_string_journal_order_id_also_filtered_as_unsubmitted():
    journal = _journal_df([{"order_id": "", "strategy": "SR_BOUNCE"}])
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": 30.0}])
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert len(joined) == 0
    assert len(row_errors) == 1  # t1's order_id "o1" is now an orphan


def test_null_trade_id_rejected():
    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = _trades_df([{"trade_id": None, "order_id": "o1", "profit": 30.0}])
    with pytest.raises(CsvSchemaError):
        join_signal_to_outcome(journal, trades)


def test_duplicate_trade_id_rejected():
    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = pd.DataFrame(
        [
            {"trade_id": "t1", "order_id": "o1", "profit": 30.0, "deal_id": "d1"},
            {"trade_id": "t1", "order_id": "o1", "profit": 20.0, "deal_id": "d2"},
        ]
    )
    with pytest.raises(CsvSchemaError):
        join_signal_to_outcome(journal, trades)


def test_null_deal_id_rejected():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    deal_id was previously never read at all."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = pd.DataFrame([{"trade_id": "t1", "order_id": "o1", "profit": 30.0, "deal_id": None}])
    with pytest.raises(CsvSchemaError):
        join_signal_to_outcome(journal, trades)


def test_duplicate_deal_id_rejected():
    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = pd.DataFrame(
        [
            {"trade_id": "t1", "order_id": "o1", "profit": 30.0, "deal_id": "dup"},
            {"trade_id": "t2", "order_id": "o1", "profit": 20.0, "deal_id": "dup"},
        ]
    )
    with pytest.raises(CsvSchemaError):
        join_signal_to_outcome(journal, trades)


def test_non_finite_profit_rejected():
    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": float("nan")}])
    with pytest.raises(CsvSchemaError):
        join_signal_to_outcome(journal, trades)


def test_shared_field_conflict_is_a_row_error_not_silent_trade_row_win():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    shared fields (e.g. symbol) were previously merged with silent
    trade-row precedence -- a genuine mismatch between the journal's
    recorded symbol and the trade export's own symbol for the SAME
    order_id is data corruption or a bad join, not something to silently
    resolve in the trade row's favor."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE", "symbol": "XAUUSD"}])
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": 30.0, "symbol": "EURUSD"}])
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert len(joined) == 0
    assert len(row_errors) == 1
    assert "symbol" in row_errors[0]["error"]


def test_shared_field_agreement_does_not_error():
    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE", "symbol": "XAUUSD"}])
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": 30.0, "symbol": "XAUUSD"}])
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    assert len(joined) == 1


def test_large_order_id_not_collapsed_by_float64_inference(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    generic pandas CSV inference loaded order_id as float64, collapsing
    9007199254740992 and 9007199254740993 to the SAME value. Both must
    now be read as distinct strings and joined correctly."""

    journal_csv = tmp_path / "journal.csv"
    pd.DataFrame(
        [
            {"order_id": "9007199254740992", "strategy": "SR_BOUNCE"},
            {"order_id": "9007199254740993", "strategy": "SMC"},
        ]
    ).to_csv(journal_csv, index=False)
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame(
        [
            {"trade_id": "t1", "order_id": "9007199254740992", "deal_id": "d1", "profit": 30.0},
            {"trade_id": "t2", "order_id": "9007199254740993", "deal_id": "d2", "profit": 20.0},
        ]
    ).to_csv(trades_csv, index=False)

    joined_df, row_errors = run(journal_csv, trades_csv, repo_path=REPO_ROOT)
    assert row_errors == []
    assert len(joined_df) == 2
    strategies = dict(zip(joined_df["order_id"], joined_df["strategy"]))
    assert strategies["9007199254740992"] == "SR_BOUNCE"
    assert strategies["9007199254740993"] == "SMC"


def test_leading_zero_order_id_preserved(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    generic numeric inference silently discarded leading zeroes
    ("001" -> 1)."""

    journal_csv = tmp_path / "journal.csv"
    pd.DataFrame([{"order_id": "001", "strategy": "SR_BOUNCE"}]).to_csv(journal_csv, index=False)
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame([{"trade_id": "t1", "order_id": "001", "deal_id": "d1", "profit": 30.0}]).to_csv(
        trades_csv, index=False
    )

    joined_df, row_errors = run(journal_csv, trades_csv, repo_path=REPO_ROOT)
    assert row_errors == []
    assert len(joined_df) == 1
    assert joined_df.iloc[0]["order_id"] == "001"


# --- run() (CSV wrapper) ------------------------------------------------------


def test_run_writes_output_csv_and_errors_json(tmp_path):
    journal_csv = tmp_path / "journal.csv"
    pd.DataFrame([{"order_id": "o1", "strategy": "SR_BOUNCE"}]).to_csv(journal_csv, index=False)
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame(
        [
            {"trade_id": "t1", "order_id": "o1", "deal_id": "d1", "profit": 30.0},
            {"trade_id": "t2", "order_id": "o_unknown", "deal_id": "d2", "profit": 10.0},
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


def test_run_provenance_auto_written_even_without_explicit_errors_json(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    provenance was previously written ONLY when errors_json was supplied
    explicitly -- a caller who requested only output_csv got a data file
    with zero provenance record anywhere."""

    journal_csv = tmp_path / "journal.csv"
    pd.DataFrame([{"order_id": "o1", "strategy": "SR_BOUNCE"}]).to_csv(journal_csv, index=False)
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame([{"trade_id": "t1", "order_id": "o1", "deal_id": "d1", "profit": 30.0}]).to_csv(
        trades_csv, index=False
    )

    output_csv = tmp_path / "out" / "unified.csv"
    run(journal_csv, trades_csv, output_csv=output_csv, repo_path=REPO_ROOT)

    errors_path = tmp_path / "out" / "unified.errors.json"
    assert errors_path.exists()
    payload = json.loads(errors_path.read_text(encoding="utf-8"))
    assert payload["metadata"]["dataset_hash"] != ""


def test_run_empty_trades_raises(tmp_path):
    from analysis.metrics import InsufficientSampleError

    journal_csv = tmp_path / "journal.csv"
    pd.DataFrame([{"order_id": "o1"}]).to_csv(journal_csv, index=False)
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame(columns=["trade_id", "order_id", "deal_id", "profit"]).to_csv(
        trades_csv, index=False
    )

    with pytest.raises(InsufficientSampleError):
        run(journal_csv, trades_csv)


def test_run_output_path_colliding_with_input_rejected(tmp_path):
    journal_csv = tmp_path / "journal.csv"
    pd.DataFrame([{"order_id": "o1"}]).to_csv(journal_csv, index=False)
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame([{"trade_id": "t1", "order_id": "o1", "deal_id": "d1", "profit": 30.0}]).to_csv(
        trades_csv, index=False
    )

    with pytest.raises(CsvSchemaError):
        run(journal_csv, trades_csv, output_csv=journal_csv)


def test_cli_main_returns_nonzero_when_row_errors_present(tmp_path):
    journal_csv = tmp_path / "journal.csv"
    pd.DataFrame([{"order_id": "o1"}]).to_csv(journal_csv, index=False)
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame(
        [{"trade_id": "t1", "order_id": "o_unknown", "deal_id": "d1", "profit": 30.0}]
    ).to_csv(trades_csv, index=False)

    exit_code = main(["--journal-csv", str(journal_csv), "--trades-csv", str(trades_csv)])
    assert exit_code == 1


def test_cli_main_missing_file(tmp_path, capsys):
    exit_code = main(
        ["--journal-csv", str(tmp_path / "nope.csv"), "--trades-csv", str(tmp_path / "nope2.csv")]
    )
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err
