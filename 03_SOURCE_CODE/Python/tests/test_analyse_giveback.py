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


def test_header_only_trades_csv_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22): a header-only
    (zero-row) trades.csv previously produced a "successful" empty run
    instead of a visible insufficient-sample failure."""

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
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0])

    with pytest.raises(CsvSchemaError):
        run(trades_path, bars_path)


def test_malformed_stop_geometry_captured_as_row_error(tmp_path):
    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T02:00:00Z",
                "entry_price": 100.0,
                "stop_price": 101.0,  # wrong side for a long
            }
        ],
    )
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0, 102.0, 103.0])

    result = run(trades_path, bars_path)
    assert result.comparisons == []
    assert len(result.row_errors) == 1


def test_non_finite_exit_price_rejected_as_row_error(tmp_path):
    """Regression for a Codex review finding (2026-07-22): the optional
    exit_price column was never checked for finiteness when populated --
    `pd.notna(inf)` is True, so an infinite exit_price could reach
    compute_r_multiple and produce an infinite actual_final_r."""

    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T02:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
                "exit_price": float("inf"),
            }
        ],
    )
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0, 102.0, 103.0])

    result = run(trades_path, bars_path)
    assert result.comparisons == []
    assert len(result.row_errors) == 1


def test_duplicate_symbol_timestamp_bar_rejected(tmp_path):
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
    bars_path = tmp_path / "bars.csv"
    pd.DataFrame(
        {
            "symbol": ["XAUUSD", "XAUUSD"],
            "timestamp": ["2026-07-21T00:00:00Z", "2026-07-21T00:00:00Z"],
            "close": [101.0, 102.0],
        }
    ).to_csv(bars_path, index=False)
    with pytest.raises(CsvSchemaError):
        run(trades_path, bars_path)


def test_nan_model_parameters_rejected_not_silently_clamped(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    none of the five giveback-model parameters were validated -- passing
    NaN for all five previously produced valid comparisons/triggers with
    zero row errors, because should_giveback_close_v637/v811's own
    max()/min() clamps silently select an effective value from a NaN
    input (Python's max(a, nan) returns 'a'). Must now be rejected
    outright."""

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
    nan = float("nan")
    with pytest.raises(ValueError):
        run(
            trades_path,
            bars_path,
            v637_arm_rr=nan,
            v637_giveback_percent=nan,
            v637_floor_r=nan,
            v811_arm_r=nan,
            v811_floor_r=nan,
        )


def test_summary_persists_requested_and_effective_model_params(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    an out-of-range-but-finite setting is silently clamped by
    should_giveback_close_v637/v811's own max()/min() logic without the
    artifact disclosing the requested vs. effective value -- both are now
    persisted in every summary."""

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
    summary_json = tmp_path / "out" / "summary.json"
    run(
        trades_path,
        bars_path,
        summary_json=summary_json,
        v637_arm_rr=-5.0,  # out-of-range, clamped to 0.25 downstream
        v637_giveback_percent=150.0,  # out-of-range, clamped to 90.0
    )
    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["requested_model_params"]["v637_arm_rr"] == -5.0
    assert payload["effective_model_params"]["v637_arm_rr"] == pytest.approx(0.25)
    assert payload["requested_model_params"]["v637_giveback_percent"] == 150.0
    assert payload["effective_model_params"]["v637_giveback_percent"] == pytest.approx(90.0)


def test_duplicate_bar_with_differently_spelled_same_instant_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    the duplicate-(symbol, timestamp) check previously ran on the RAW
    string timestamp column BEFORE UTC normalization -- "...Z" and
    "...+00:00" are different strings describing the SAME instant, so
    they passed the (string-based) uniqueness check, then collapsed to
    one conflicting instant once parsed. Both spellings here must be
    rejected as duplicates."""

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
    bars_path = tmp_path / "bars.csv"
    pd.DataFrame(
        {
            "symbol": ["XAUUSD", "XAUUSD"],
            "timestamp": ["2026-07-21T00:00:00Z", "2026-07-21T00:00:00+00:00"],
            "close": [101.0, 102.0],
        }
    ).to_csv(bars_path, index=False)
    with pytest.raises(CsvSchemaError):
        run(trades_path, bars_path)


def test_misaligned_entry_exit_time_captured_as_row_error(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round): a
    00:30-01:30 trade with only a 01:00 bar previously completed with
    ZERO row errors despite neither endpoint aligning to any real bar --
    entry_time/exit_time must now each match an actual bar timestamp."""

    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:30:00Z",
                "exit_time": "2026-07-21T01:30:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )
    bars_path = tmp_path / "bars.csv"
    _write_bars(bars_path, [101.0])  # single bar at 00:00 only

    result = run(trades_path, bars_path)
    assert result.comparisons == []
    assert len(result.row_errors) == 1


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


def test_guard_helped_rate_is_scoped_to_triggered_subset_not_full_cohort(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    the old key ``guard_helped_rate`` was silently CONDITIONAL on this
    model's own triggered subset -- one helpful trigger among many total
    trades would be reported as 100%, not the much smaller full-cohort
    rate. Here 1 of 4 trades triggers v637 (and that one trigger helps),
    so ``guard_helped_rate_when_triggered`` must read 100% while
    ``guard_helped_rate_full_cohort`` must read 25% -- proving the two
    are no longer conflated under one ambiguous name."""

    bars_path = tmp_path / "bars.csv"
    bars = pd.DataFrame(
        {
            "symbol": ["XAUUSD"] * 8,
            "timestamp": pd.to_datetime(
                [
                    "2026-07-21T00:00:00Z",
                    "2026-07-21T01:00:00Z",
                    "2026-07-21T02:00:00Z",
                    "2026-07-21T03:00:00Z",
                    "2026-07-21T04:00:00Z",
                    "2026-07-21T05:00:00Z",
                    "2026-07-21T06:00:00Z",
                    "2026-07-21T07:00:00Z",
                ]
            ),
            "close": [101.0, 102.0, 104.0, 101.4, 100.6, 100.5, 100.5, 100.5],
        }
    )
    bars.to_csv(bars_path, index=False)

    trades_path = tmp_path / "trades.csv"
    _write_trades(
        trades_path,
        [
            # Same fixture as test_guard_would_have_helped_hand_computed:
            # v637 triggers at r=0.7, actual final r=0.3 -> helped.
            {
                "trade_id": "helped-1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T04:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            },
            # Same fixture as test_never_triggered_gives_zero_diff, x3:
            # R=0.25 never arms the guard at all.
            {
                "trade_id": "never-triggered-1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T05:00:00Z",
                "exit_time": "2026-07-21T05:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            },
            {
                "trade_id": "never-triggered-2",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T06:00:00Z",
                "exit_time": "2026-07-21T06:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            },
            {
                "trade_id": "never-triggered-3",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T07:00:00Z",
                "exit_time": "2026-07-21T07:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            },
        ],
    )

    summary_json = tmp_path / "out" / "summary.json"
    result = run(trades_path, bars_path, summary_json=summary_json, seed=1, repo_path=REPO_ROOT)
    assert len(result.comparisons) == 4

    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    v637 = payload["v637"]
    assert v637["n_triggered"] == 1
    assert v637["guard_helped_rate_when_triggered"] == pytest.approx(1.0)
    assert v637["guard_helped_rate_full_cohort"] == pytest.approx(0.25)
    assert "guard_helped_rate" not in v637
    # Regression for a Codex review finding (2026-07-22, fourth round):
    # the Wilson confidence level used for these intervals was never
    # persisted.
    assert v637["guard_helped_rate_when_triggered_confidence"] == pytest.approx(0.95)
    assert v637["guard_helped_rate_full_cohort_confidence"] == pytest.approx(0.95)


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
    run(
        trades_path,
        bars_path,
        output_csv=out_csv,
        summary_json=summary_json,
        seed=1,
        repo_path=REPO_ROOT,
    )

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
            {
                "trade_id": "dup",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T00:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            },
            {
                "trade_id": "dup",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T00:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            },
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
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T00:00:00Z",
                "entry_price": 100.0,
                "stop_price": float("nan"),
            }
        ],
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
        [
            {
                "trade_id": "naive-1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00",
                "exit_time": "2026-07-21T00:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
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
        [
            {
                "trade_id": "bad-1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2027-01-01T00:00:00Z",
                "exit_time": "2027-01-01T01:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
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
        [
            {
                "trade_id": "bad-1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2027-01-01T00:00:00Z",
                "exit_time": "2027-01-01T01:00:00Z",
                "entry_price": 100.0,
                "stop_price": 98.0,
            }
        ],
    )
    exit_code = main(["--trades-csv", str(trades_path), "--bars-csv", str(bars_path)])
    assert exit_code == 1
