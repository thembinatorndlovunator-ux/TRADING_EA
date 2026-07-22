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

# Trades t1/t2/t4/t8 are offset +12h from the integer-day boundary grid
# (which is anchored to t0's own ENTRY time, i.e. exactly _BASE - 1h --
# see walk_forward.py's own fix, 2026-07-22: the overall analysis period
# starts at the earliest ENTRY, not the earliest exit) SPECIFICALLY so
# they never coincidentally land exactly on a window boundary. t0's own
# entry now legitimately anchors window 0 itself (rather than being
# purged, as it was under the old exit-time-anchored scheme) -- see
# test_windows_hand_computed_with_purged_boundaries's own comment for the
# full re-trace.
_BASE = pd.Timestamp("2026-01-01", tz="UTC")


def _row(trade_id, exit_time, exit_price, profit):
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


def _write_trades(path: Path) -> None:
    pd.DataFrame(
        [
            _row("t0", _BASE, 104.0, 10.0),  # r=2.0, win -- always purged (see above)
            _row("t1", _BASE + pd.Timedelta(days=1, hours=12), 99.0, -5.0),  # r=-0.5, loss
            _row("t2", _BASE + pd.Timedelta(days=2, hours=12), 103.0, 10.0),  # r=1.5, win
            _row("t4", _BASE + pd.Timedelta(days=4, hours=12), 105.0, 20.0),  # r=2.5, win
            _row("t8", _BASE + pd.Timedelta(days=8, hours=12), 99.0, -5.0),  # r=-0.5, loss
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
            "trade_id",
            "symbol",
            "is_long",
            "entry_time",
            "exit_time",
            "entry_price",
            "exit_price",
            "stop_price",
            "profit",
        ]
    ).to_csv(path, index=False)
    with pytest.raises(InsufficientSampleError):
        run(path, train_days=3, test_days=2, step_days=2)


def test_duplicate_trade_id_rejected(tmp_path):
    path = tmp_path / "trades.csv"
    pd.DataFrame(
        [_row("dup", _BASE, 104.0, 10.0), _row("dup", _BASE + pd.Timedelta(days=1), 99.0, -5.0)]
    ).to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        run(path, train_days=3, test_days=2, step_days=2)


def test_naive_timestamp_rejected(tmp_path):
    """Regression for a Codex review finding: pd.to_datetime(utc=True)
    silently accepted naive entry/exit timestamps as UTC."""

    path = tmp_path / "trades.csv"
    row = _row("t1", _BASE, 104.0, 10.0)
    row["exit_time"] = "2026-01-01T00:00:00"  # naive -- no "Z"
    pd.DataFrame([row]).to_csv(path, index=False)
    with pytest.raises(ValueError):
        run(path, train_days=3, test_days=2, step_days=2)


def test_impossible_chronology_rejected(tmp_path):
    path = tmp_path / "trades.csv"
    row = _row("t1", _BASE, 104.0, 10.0)
    row["entry_time"] = (_BASE + pd.Timedelta(days=1)).isoformat()  # after exit_time (_BASE)
    pd.DataFrame([row]).to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        run(path, train_days=3, test_days=2, step_days=2)


def test_malformed_stop_geometry_rejected(tmp_path):
    path = tmp_path / "trades.csv"
    row = _row("t1", _BASE, 104.0, 10.0)
    row["stop_price"] = 101.0  # wrong side for a long (entry_price=100.0)
    pd.DataFrame([row]).to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        run(path, train_days=3, test_days=2, step_days=2)


def test_missing_profit_not_silently_counted_as_loss(tmp_path):
    """Regression for a Codex review finding (2026-07-22): 'profit' was
    missing from NUMERIC_COLUMNS, so a missing/NaN profit reached
    `profit > 0` (False for NaN in pandas), silently counting an
    unknown-P/L row as a LOSS instead of raising a visible schema
    failure."""

    path = tmp_path / "trades.csv"
    row = _row("t1", _BASE, 104.0, 10.0)
    row["profit"] = ""  # becomes NaN once read back as numeric
    pd.DataFrame([row]).to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        run(path, train_days=3, test_days=2, step_days=2)


def test_seed_is_exposed_and_actually_used(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    this module's own docstring claimed "no seed is needed or accepted",
    which became false once per-window expectancy started bootstrapping
    internally -- the seed must be an explicit, exposed parameter, not a
    hidden default."""

    path = tmp_path / "trades.csv"
    _write_trades(path)
    summary_json_a = tmp_path / "out_a" / "summary.json"
    run(path, train_days=3, test_days=2, step_days=2, seed=7, summary_json=summary_json_a)
    payload_a = json.loads(summary_json_a.read_text(encoding="utf-8"))
    assert payload_a["summary"]["seed"] == 7


def test_n_resamples_and_confidence_exposed_and_actually_used(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    n_resamples/confidence were hard-wired to expectancy()'s own hidden
    defaults and never exposed at the run()/CLI boundary or persisted in
    the report."""

    path = tmp_path / "trades.csv"
    _write_trades(path)
    summary_json = tmp_path / "out" / "summary.json"
    run(
        path,
        train_days=3,
        test_days=2,
        step_days=2,
        seed=7,
        n_resamples=500,
        confidence=0.90,
        summary_json=summary_json,
    )
    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_resamples"] == 500
    assert payload["summary"]["confidence"] == 0.90


def test_train_and_expectancy_confidence_intervals_present(tmp_path):
    """Regression for a Codex review finding: walk-forward omitted train
    win-rate intervals and all expectancy intervals entirely."""

    path = tmp_path / "trades.csv"
    _write_trades(path)
    df = run(path, train_days=3, test_days=2, step_days=2)

    w0 = df.iloc[0]
    assert w0["train_win_rate_ci_lower"] is not None
    assert w0["train_win_rate_ci_upper"] is not None
    # train has 3 trades (n>=2) so an expectancy CI is estimable.
    assert pd.notna(w0["train_expectancy_r_ci_lower"])
    assert pd.notna(w0["train_expectancy_r_ci_upper"])


def test_output_path_colliding_with_input_rejected(tmp_path):
    path = tmp_path / "trades.csv"
    _write_trades(path)
    with pytest.raises(CsvSchemaError):
        run(path, train_days=3, test_days=2, step_days=2, output_csv=path)


def test_windows_hand_computed_with_purged_boundaries(tmp_path):
    # 3 windows result (test plan traced in this file's own history).
    # **Re-traced, 2026-07-22 Codex review finding:** the overall analysis
    # period is now anchored at the earliest ENTRY (not earliest exit --
    # see walk_forward.py's own fix), so t0's entry (exactly at the new
    # anchor) now legitimately falls inside window 0's train slice
    # instead of being structurally excluded. See the module-level
    # comment above for the rest of the hand trace this reproduces.
    path = tmp_path / "trades.csv"
    _write_trades(path)

    df = run(path, train_days=3, test_days=2, step_days=2)
    assert len(df) == 3

    w0 = df.iloc[0]
    assert w0["train_n"] == 3  # t0, t1, t2 (t0's entry now anchors window 0 itself)
    assert w0["train_win_rate"] == pytest.approx(2.0 / 3.0)  # t0 win, t1 loss, t2 win
    assert w0["train_expectancy_r"] == pytest.approx(1.0)  # mean(2.0, -0.5, 1.5)
    assert w0["test_n"] == 1  # t4
    assert w0["test_win_rate"] == pytest.approx(1.0)
    assert w0["test_expectancy_r"] == pytest.approx(2.5)

    w1 = df.iloc[1]
    assert w1["train_n"] == 2  # t2, t4 (rolling windows legitimately overlap)
    assert w1["train_win_rate"] == pytest.approx(1.0)
    assert w1["train_expectancy_r"] == pytest.approx(2.0)  # mean(1.5, 2.5)
    assert w1["test_n"] == 0  # nothing falls in [day5, day7)
    assert pd.isna(w1["test_win_rate"])
    assert pd.isna(w1["test_expectancy_r"])

    w2 = df.iloc[2]
    assert w2["train_n"] == 1  # t4
    assert w2["test_n"] == 1  # t8
    assert w2["test_win_rate"] == pytest.approx(0.0)
    assert w2["test_expectancy_r"] == pytest.approx(-0.5)


def test_trade_spanning_a_window_boundary_is_purged_from_both_sides(tmp_path):
    """Regression for a Codex review finding: partitioning by exit_time
    alone let a trade whose ENTRY preceded a test window's start (but
    whose exit fell inside it) count as a test-period observation -- a
    temporal-leakage route. Such a trade must now be excluded entirely."""

    path = tmp_path / "trades.csv"
    # **Re-traced, 2026-07-22 Codex review finding:** the overall analysis
    # period is now anchored at the earliest ENTRY (not earliest exit),
    # so a zero-duration early anchor (entry == exit == _BASE) is used to
    # fix first_time (and therefore window 0's train_start) at day0 --
    # this trade now legitimately falls inside window 0's own train slice
    # (it defines the anchor, so its entry trivially satisfies
    # "entry >= train_start"), rather than being purged as it would be
    # if it carried a separate, earlier entry_time (see the previous
    # test's own re-trace for why that's no longer purged either).
    early_anchor_exit = _BASE
    spanning_entry = _BASE + pd.Timedelta(
        days=2, hours=23
    )  # just before day3 (train/test boundary)
    spanning_exit = _BASE + pd.Timedelta(days=3, hours=1)  # just after day3
    # A far-future trade purely to extend the data span so
    # generate_windows actually produces window 0 -- it lands nowhere
    # near window 0's train/test ranges, so it does not affect this
    # test's assertions about the spanning trade.
    late_anchor_exit = _BASE + pd.Timedelta(days=20)
    pd.DataFrame(
        [
            {
                "trade_id": "early_anchor",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": early_anchor_exit.isoformat(),
                "exit_time": early_anchor_exit.isoformat(),
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 50.0,
            },
            {
                "trade_id": "spanner",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": spanning_entry.isoformat(),
                "exit_time": spanning_exit.isoformat(),
                "entry_price": 100.0,
                "exit_price": 110.0,
                "stop_price": 98.0,
                "profit": 100.0,
            },
            {
                "trade_id": "late_anchor",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": (late_anchor_exit - pd.Timedelta(hours=1)).isoformat(),
                "exit_time": late_anchor_exit.isoformat(),
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 50.0,
            },
        ]
    ).to_csv(path, index=False)

    df = run(path, train_days=3, test_days=2, step_days=2)
    # window0: train[day0,day3), test[day3,day5) -- "spanner" belongs to
    # NEITHER (entry is in train's range but exit is not; exit is in
    # test's range but entry is not) -> purged from both. train_n==1 is
    # "early_anchor" alone (it legitimately anchors the window, see the
    # comment above), proving "spanner" specifically was excluded from
    # train despite train_n being nonzero.
    assert df.iloc[0]["train_n"] == 1
    assert df.iloc[0]["test_n"] == 0


def test_zero_windows_does_not_crash(tmp_path):
    """Regression for a Codex review finding: when generate_windows
    legitimately returns zero windows (data span shorter than
    train+test), the summary_json block previously raised a bare
    KeyError trying to access a column on a columnless empty DataFrame."""

    path = tmp_path / "trades.csv"
    _row_single = _row("t1", _BASE, 104.0, 10.0)
    pd.DataFrame([_row_single]).to_csv(path, index=False)

    summary_json = tmp_path / "out" / "summary.json"
    df = run(path, train_days=365, test_days=365, step_days=365, summary_json=summary_json)

    assert len(df) == 0
    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_windows"] == 0
    assert payload["summary"]["mean_test_expectancy_r"] is None


def test_n_resamples_rejected_unconditionally_even_with_zero_windows(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    n_resamples/confidence were previously validated only INSIDE
    _slice_metrics's own bootstrap call -- when zero windows are
    generated, that call (and the validation inside it) is never reached
    at all, silently accepting n_resamples=0. Must now raise regardless
    of how many windows the data actually produces."""

    path = tmp_path / "trades.csv"
    pd.DataFrame([_row("t1", _BASE, 104.0, 10.0)]).to_csv(path, index=False)

    with pytest.raises(ValueError):
        run(path, train_days=365, test_days=365, step_days=365, n_resamples=0)
    with pytest.raises(ValueError):
        run(path, train_days=365, test_days=365, step_days=365, confidence=1.5)
    with pytest.raises(ValueError):
        run(path, train_days=365, test_days=365, step_days=365, n_resamples=10_000_000)


def test_mean_test_expectancy_ignores_nan_windows_not_just_none(tmp_path):
    """Regression for a Codex review finding: `r is not None` does not
    filter out pandas' NaN (the empty-window sentinel a DataFrame column
    actually holds), so this project's own 5-trade fixture previously
    wrote `mean_test_expectancy_r: NaN` -- a non-standard JSON token --
    instead of the mean over the genuinely-valid windows."""

    path = tmp_path / "trades.csv"
    _write_trades(path)
    summary_json = tmp_path / "out" / "summary.json"

    run(path, train_days=3, test_days=2, step_days=2, summary_json=summary_json)

    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    # window1's test_expectancy_r is NaN (no test trades); only windows 0
    # and 2 have real values: mean(2.5, -0.5) = 1.0
    assert payload["summary"]["mean_test_expectancy_r"] == pytest.approx(1.0)


def test_writes_output_csv_and_summary_json(tmp_path):
    path = tmp_path / "trades.csv"
    _write_trades(path)
    out_csv = tmp_path / "out" / "windows.csv"
    summary_json = tmp_path / "out" / "summary.json"

    run(
        path,
        train_days=3,
        test_days=2,
        step_days=2,
        output_csv=out_csv,
        summary_json=summary_json,
        symbol="XAUUSD",
        repo_path=REPO_ROOT,
    )

    assert out_csv.exists()
    assert len(pd.read_csv(out_csv)) == 3

    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_windows"] == 3
    assert payload["summary"]["train_days"] == 3


def test_summary_discloses_overlap_and_partial_window_status(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    'mean_test_expectancy_r' is an unlabelled, unweighted mean of
    per-window means -- final windows can be partial and test windows
    can overlap when step_days < test_days, so trades may receive
    unequal weight or appear more than once. Both facts must now be
    persisted explicitly."""

    path = tmp_path / "trades.csv"
    _write_trades(path)

    # step_days (1) < test_days (2) -- test windows must overlap.
    summary_json = tmp_path / "overlap.json"
    run(
        path, train_days=3, test_days=2, step_days=1, summary_json=summary_json, repo_path=REPO_ROOT
    )
    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["summary"]["test_windows_overlap"] is True
    assert "mean_test_expectancy_r_estimand" in payload["summary"]
    assert "final_window_test_period_is_partial" in payload["summary"]

    # step_days (2) == test_days (2) -- test windows must NOT overlap.
    summary_json2 = tmp_path / "no_overlap.json"
    run(
        path,
        train_days=3,
        test_days=2,
        step_days=2,
        summary_json=summary_json2,
        repo_path=REPO_ROOT,
    )
    payload2 = json.loads(summary_json2.read_text(encoding="utf-8"))
    assert payload2["summary"]["test_windows_overlap"] is False


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
        [
            "--trades-csv",
            str(tmp_path / "nope.csv"),
            "--train-days",
            "3",
            "--test-days",
            "2",
            "--step-days",
            "2",
        ]
    )
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err
