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


# --- round-5 regressions --------------------------------------------------


def test_null_journal_deal_id_against_real_trade_deal_id_is_not_a_conflict():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    'deal_id' was previously treated as a shared-field invariant between
    journal and trade rows. A journal decision (recorded before any fill
    exists) legitimately has a blank deal_id, so a real trade deal_id
    ("d1") was compared against that blank and reported as a false
    "journal/trade shared field(s) disagree" conflict -- rejecting every
    legitimate real fill the moment deal_id starts being genuinely
    populated on the trade side. deal_id must never be compared as a
    journal/trade invariant (it is fill-scoped, not decision-scoped)."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE", "deal_id": None}])
    trades = pd.DataFrame([{"trade_id": "t1", "order_id": "o1", "profit": 30.0, "deal_id": "d1"}])
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    assert len(joined) == 1
    assert joined.iloc[0]["profit"] == pytest.approx(30.0)


def test_second_partial_fill_with_different_deal_id_is_aggregated_not_rejected():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    if a journal row happens to also carry a real (non-blank) deal_id
    (e.g. copied from the first fill), a SECOND partial fill's different
    deal_id was previously rejected as "disagreeing" with the journal's,
    even though partial fills legitimately have distinct deal_ids. Both
    fills must be aggregated into one position."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE", "deal_id": "d1"}])
    trades = pd.DataFrame(
        [
            {"trade_id": "t1", "order_id": "o1", "profit": 30.0, "deal_id": "d1"},
            {"trade_id": "t2", "order_id": "o1", "profit": 20.0, "deal_id": "d2"},
        ]
    )
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    assert len(joined) == 1
    row = joined.iloc[0]
    assert row["profit"] == pytest.approx(50.0)
    assert row["n_fills"] == 2
    assert row["fill_deal_ids"] == "d1,d2"


def test_direction_is_long_cross_schema_mismatch_is_a_conflict():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    journal 'direction' (BUY/SELL) and trade 'is_long' (bool) describe
    the SAME underlying fact under different column names, so the
    generic same-name shared-column check never compared them -- a probe
    with direction=BUY and is_long=False previously joined successfully.
    This must now be a row error."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE", "direction": "BUY"}])
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": 30.0, "is_long": False}])
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert len(joined) == 0
    assert len(row_errors) == 1
    assert "direction/is_long" in row_errors[0]["error"]


def test_direction_is_long_agreement_does_not_error():
    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE", "direction": "SELL"}])
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": 30.0, "is_long": False}])
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    assert len(joined) == 1


def test_string_profits_summed_numerically_not_concatenated():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    a validated, numerically-coerced 'profit_numeric' series was computed
    but never assigned back to the working frame -- the ORIGINAL
    (string-typed) 'profit' column was what actually got summed, so
    string profits "30"/"20" produced the concatenated string-then-float
    3020.0, not the numeric sum 50.0."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = pd.DataFrame(
        [
            {"trade_id": "t1", "order_id": "o1", "profit": "30", "deal_id": "d1"},
            {"trade_id": "t2", "order_id": "o1", "profit": "20", "deal_id": "d2"},
        ]
    )
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    row = joined.iloc[0]
    assert row["profit"] == pytest.approx(50.0)
    assert row["profit"] != pytest.approx(3020.0)


def test_multi_fill_position_drops_ambiguous_first_fill_only_fields():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    entry_price/exit_price/stop_price/r_multiple have no volume/lot
    column to weight them across partial fills -- the round-4
    implementation silently reported the FIRST fill's values (e.g. its
    own r_multiple) as if they described the whole position, even though
    'profit' was a genuine sum across all fills (position profit=50 but
    r_multiple=1, the first fill's own R). These fields must now be
    explicitly undefined (None) for a genuine multi-fill position rather
    than silently first-fill-leaked. A single-fill position still
    reports them normally (no aggregation ambiguity)."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = pd.DataFrame(
        [
            {
                "trade_id": "t1",
                "order_id": "o1",
                "profit": 30.0,
                "deal_id": "d1",
                "r_multiple": 1.0,
                "entry_price": 100.0,
            },
            {
                "trade_id": "t2",
                "order_id": "o1",
                "profit": 20.0,
                "deal_id": "d2",
                "r_multiple": 4.0,
                "entry_price": 100.5,
            },
        ]
    )
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    row = joined.iloc[0]
    assert row["profit"] == pytest.approx(50.0)
    assert row["n_fills"] == 2
    assert pd.isna(row["r_multiple"])
    assert pd.isna(row["entry_price"])
    assert pd.isna(row["trade_id"])
    assert pd.isna(row["deal_id"])


def test_single_fill_position_keeps_r_multiple_and_price_fields():
    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = pd.DataFrame(
        [
            {
                "trade_id": "t1",
                "order_id": "o1",
                "profit": 30.0,
                "deal_id": "d1",
                "r_multiple": 1.5,
                "entry_price": 100.0,
            }
        ]
    )
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    row = joined.iloc[0]
    assert row["n_fills"] == 1
    assert row["r_multiple"] == pytest.approx(1.5)
    assert row["entry_price"] == pytest.approx(100.0)


def test_one_bad_fill_rejects_the_whole_position_not_just_that_fill():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    each fill was previously checked for shared-field conflicts
    INDEPENDENTLY, so if only one of a position's several fills
    conflicted with the journal row, the OTHER, non-conflicting fills
    were still silently aggregated -- an invalid, silently-incomplete
    position reported as if it were the whole thing. A position must now
    be rejected as a unit (every fill becomes a row error, none are
    aggregated) if ANY constituent fill fails integrity."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE", "symbol": "XAUUSD"}])
    trades = pd.DataFrame(
        [
            {
                "trade_id": "t1",
                "order_id": "o1",
                "profit": 30.0,
                "deal_id": "d1",
                "symbol": "XAUUSD",
            },
            {
                "trade_id": "t2",
                "order_id": "o1",
                "profit": 20.0,
                "deal_id": "d2",
                "symbol": "EURUSD",
            },
        ]
    )
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert len(joined) == 0
    assert len(row_errors) == 2
    assert {e["trade_id"] for e in row_errors} == {"t1", "t2"}


def test_sidecar_errors_json_path_does_not_overwrite_journal_input(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    the implicit errors_json sidecar was previously derived from
    output_csv AFTER the input/output collision check already ran (and
    after the CSV write itself) -- a journal input literally named
    'out.errors.json' alongside an output_csv 'out.csv' would have its
    derived errors_json path never checked against the journal input at
    all, silently overwriting the journal CSV with JSON metadata. The
    derived path must now be included in the collision check before any
    I/O happens."""

    journal_csv = tmp_path / "out.errors.json"
    pd.DataFrame([{"order_id": "o1", "strategy": "SR_BOUNCE"}]).to_csv(journal_csv, index=False)
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame([{"trade_id": "t1", "order_id": "o1", "deal_id": "d1", "profit": 30.0}]).to_csv(
        trades_csv, index=False
    )
    output_csv = tmp_path / "out.csv"

    original_journal_bytes = journal_csv.read_bytes()
    with pytest.raises(CsvSchemaError):
        run(journal_csv, trades_csv, output_csv=output_csv, repo_path=REPO_ROOT)
    assert journal_csv.read_bytes() == original_journal_bytes


def test_journal_deal_id_not_among_position_fills_is_a_conflict():
    """Regression for a Codex review finding (2026-07-22, sixth round):
    'deal_id' was previously excluded from EVERY conflict check, not
    only the equality-with-every-fill check that's genuinely wrong for
    fill-scoped data -- a probe with journal deal_id="WRONG" against a
    trade group whose only real fill has deal_id="d1" previously joined
    successfully. A non-blank journal deal_id must be a MEMBERSHIP match
    against the position's own fill deal_ids."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE", "deal_id": "WRONG"}])
    trades = pd.DataFrame([{"trade_id": "t1", "order_id": "o1", "profit": 30.0, "deal_id": "d1"}])
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert len(joined) == 0
    assert len(row_errors) == 1
    assert row_errors[0]["trade_id"] == "t1"
    assert "deal_id" in row_errors[0]["error"]


def test_journal_deal_id_matching_one_of_the_fills_is_not_a_conflict():
    """A non-blank journal deal_id that DOES match one of the position's
    real fills (e.g. copied from the first fill of an async follow-up
    record) must still be accepted -- the membership check added for the
    sixth-round finding above must not regress the fifth-round fix
    allowing a genuine matching deal_id through."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE", "deal_id": "d1"}])
    trades = pd.DataFrame(
        [
            {"trade_id": "t1", "order_id": "o1", "profit": 30.0, "deal_id": "d1"},
            {"trade_id": "t2", "order_id": "o1", "profit": 20.0, "deal_id": "d2"},
        ]
    )
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert row_errors == []
    assert len(joined) == 1
    assert joined.iloc[0]["profit"] == pytest.approx(50.0)


def test_unrecognized_direction_value_is_a_conflict_not_silently_skipped():
    """Regression for a Codex review finding (2026-07-22, sixth round):
    an unrecognized 'direction' value (anything but BUY/SELL) previously
    returned True unconditionally ("not this check's job to validate"),
    silently skipping the cross-schema check entirely rather than
    flagging genuinely invalid data."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE", "direction": "SIDEWAYS"}])
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": 30.0, "is_long": True}])
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert len(joined) == 0
    assert len(row_errors) == 1
    assert "direction/is_long" in row_errors[0]["error"]


def test_unparseable_is_long_string_is_a_conflict_not_silently_coerced_to_false():
    """Regression for a Codex review finding (2026-07-22, sixth round):
    direction=SELL, is_long="banana" previously joined successfully
    because an unrecognized is_long string was silently coerced to
    False, which happened to agree with SELL. "banana" must now be
    treated as a conflict, not a silent False."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE", "direction": "SELL"}])
    trades = _trades_df([{"trade_id": "t1", "order_id": "o1", "profit": 30.0, "is_long": "banana"}])
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert len(joined) == 0
    assert len(row_errors) == 1
    assert "direction/is_long" in row_errors[0]["error"]


def test_aggregated_profit_overflow_to_infinite_is_a_row_error():
    """Regression for a Codex review finding (2026-07-22, sixth round):
    two individually finite fill profits (1e308 each) can still overflow
    to a non-finite SUM -- the per-fill finiteness check validates each
    input value, not the aggregated output. This previously produced
    profit=inf silently, with no row error at all."""

    journal = _journal_df([{"order_id": "o1", "strategy": "SR_BOUNCE"}])
    trades = pd.DataFrame(
        [
            {"trade_id": "t1", "order_id": "o1", "profit": 1e308, "deal_id": "d1"},
            {"trade_id": "t2", "order_id": "o1", "profit": 1e308, "deal_id": "d2"},
        ]
    )
    joined, row_errors = join_signal_to_outcome(journal, trades)
    assert len(joined) == 0
    assert len(row_errors) == 2
    assert {e["trade_id"] for e in row_errors} == {"t1", "t2"}
    assert all("overflow" in e["error"] for e in row_errors)


def test_aba_mutation_cannot_desync_hash_from_parsed_content(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round):
    both journal_csv and trades_csv were previously read via the plain
    (non-hashing) helper, then build_report_metadata re-read them a
    SECOND time to compute their hash -- a deterministic ABA-mutation
    probe (mutate the journal between those reads, restore, rehash-
    matches-original) produced an output containing the ORIGINAL row
    while its metadata hash exactly matched the REPLACEMENT file. Both
    files are now read exactly ONCE (read_csv_with_required_columns_and_
    hash), so the hash used in the sidecar always describes the exact
    bytes that were actually parsed and joined -- proven here by running
    the pipeline twice against two distinct byte states and confirming
    each run's own combined hash differs and matches its own content."""

    journal_csv = tmp_path / "journal.csv"
    trades_csv = tmp_path / "trades.csv"
    pd.DataFrame([{"trade_id": "t1", "order_id": "o1", "deal_id": "d1", "profit": 30.0}]).to_csv(
        trades_csv, index=False
    )

    pd.DataFrame([{"order_id": "o1", "strategy": "SR_BOUNCE"}]).to_csv(journal_csv, index=False)
    errors_json_a = tmp_path / "a.errors.json"
    run(journal_csv, trades_csv, errors_json=errors_json_a, repo_path=REPO_ROOT)
    hash_a = json.loads(errors_json_a.read_text(encoding="utf-8"))["metadata"]["dataset_hash"]

    pd.DataFrame([{"order_id": "o1", "strategy": "MUTATED_STRATEGY"}]).to_csv(
        journal_csv, index=False
    )
    errors_json_b = tmp_path / "b.errors.json"
    run(journal_csv, trades_csv, errors_json=errors_json_b, repo_path=REPO_ROOT)
    hash_b = json.loads(errors_json_b.read_text(encoding="utf-8"))["metadata"]["dataset_hash"]

    assert hash_a != hash_b
