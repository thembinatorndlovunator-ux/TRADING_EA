from __future__ import annotations

import pandas as pd
import pytest

from analysis.trade_math import BarAlignmentError, compute_mfe_mae, compute_r_multiple


# --- compute_r_multiple (mirrors ExitManager.mqh's own TASK-030 test cases) --


def test_compute_r_multiple_long():
    assert compute_r_multiple(True, 100.0, 98.0, 101.0) == pytest.approx(0.5)


def test_compute_r_multiple_short():
    assert compute_r_multiple(False, 100.0, 102.0, 99.0) == pytest.approx(0.5)


def test_compute_r_multiple_zero_risk_distance_is_zero():
    assert compute_r_multiple(True, 100.0, 100.0, 105.0) == 0.0


def test_compute_r_multiple_negative_favors_is_negative_r():
    assert compute_r_multiple(True, 100.0, 98.0, 97.0) == pytest.approx(-1.5)


# --- compute_mfe_mae --------------------------------------------------------


def _bars():
    return pd.DataFrame(
        {
            "timestamp": pd.to_datetime(
                ["2026-07-21T00:00Z", "2026-07-21T01:00Z", "2026-07-21T02:00Z", "2026-07-21T03:00Z"]
            ),
            "high": [101.0, 105.0, 103.0, 104.0],
            "low": [99.0, 100.0, 97.0, 101.0],
        }
    )


def test_compute_mfe_mae_long_hand_computed():
    bars = _bars()
    result = compute_mfe_mae(
        trade_id="t1",
        is_long=True,
        entry_price=100.0,
        stop_price=98.0,
        entry_time=bars["timestamp"].iloc[0],
        exit_time=bars["timestamp"].iloc[-1],
        bars=bars,
    )
    assert result.mfe_price == pytest.approx(5.0)  # 105 - 100
    assert result.mae_price == pytest.approx(3.0)  # 100 - 97
    assert result.mfe_r == pytest.approx(2.5)  # 5 / 2
    assert result.mae_r == pytest.approx(-1.5)  # -3 / 2
    assert result.n_bars == 4


def test_compute_mfe_mae_short_hand_computed():
    bars = _bars()
    result = compute_mfe_mae(
        trade_id="t2",
        is_long=False,
        entry_price=100.0,
        stop_price=102.0,
        entry_time=bars["timestamp"].iloc[0],
        exit_time=bars["timestamp"].iloc[-1],
        bars=bars,
    )
    assert result.mfe_price == pytest.approx(3.0)  # 100 - 97
    assert result.mae_price == pytest.approx(5.0)  # 105 - 100
    assert result.mfe_r == pytest.approx(1.5)  # 3 / 2
    assert result.mae_r == pytest.approx(-2.5)  # -5 / 2


def test_compute_mfe_mae_misaligned_entry_time_raises_bar_alignment_error():
    """Regression for a Codex review finding (2026-07-22): entry_time/
    exit_time must exactly match an actual bar timestamp -- bar
    timestamps are declared as bar-OPEN times, and an arbitrary
    (non-bar-aligned) timestamp risks look-ahead/measurement
    contamination if silently tolerated. A timestamp with no matching bar
    at all (e.g. a future date no bar covers) is the clearest case."""

    bars = _bars()
    far_future = pd.Timestamp("2027-01-01", tz="UTC")
    with pytest.raises(BarAlignmentError):
        compute_mfe_mae(
            trade_id="t3",
            is_long=True,
            entry_price=100.0,
            stop_price=98.0,
            entry_time=far_future,
            exit_time=far_future + pd.Timedelta(hours=1),
            bars=bars,
        )


def test_compute_mfe_mae_misaligned_exit_time_raises_bar_alignment_error():
    bars = _bars()
    with pytest.raises(BarAlignmentError):
        compute_mfe_mae(
            trade_id="t3b",
            is_long=True,
            entry_price=100.0,
            stop_price=98.0,
            entry_time=bars["timestamp"].iloc[0],
            exit_time=bars["timestamp"].iloc[0] + pd.Timedelta(minutes=30),  # not a bar timestamp
            bars=bars,
        )


def test_compute_mfe_mae_empty_bars_raises_bar_alignment_error_not_no_bars_error():
    """With alignment now required, an empty 'bars' input (e.g. the
    trade's symbol has no bar data at all) fails alignment before ever
    reaching the (now effectively unreachable, given aligned inputs
    always include at least their own two endpoint bars) empty-window
    check -- NoBarsInWindowError remains defined defensively but
    BarAlignmentError is what a caller will actually see here."""

    empty_bars = pd.DataFrame(columns=["timestamp", "high", "low"])
    with pytest.raises(BarAlignmentError):
        compute_mfe_mae(
            trade_id="t3c",
            is_long=True,
            entry_price=100.0,
            stop_price=98.0,
            entry_time=pd.Timestamp("2026-07-21T00:00Z"),
            exit_time=pd.Timestamp("2026-07-21T01:00Z"),
            bars=empty_bars,
        )


def test_compute_mfe_mae_entry_after_exit_raises():
    bars = _bars()
    with pytest.raises(ValueError):
        compute_mfe_mae(
            trade_id="t4",
            is_long=True,
            entry_price=100.0,
            stop_price=98.0,
            entry_time=bars["timestamp"].iloc[-1],
            exit_time=bars["timestamp"].iloc[0],
            bars=bars,
        )


def test_compute_mfe_mae_window_is_inclusive_of_partial_bar_subset():
    bars = _bars()
    # Only the middle two bars (index 1, 2): high max 105, low min 97
    result = compute_mfe_mae(
        trade_id="t5",
        is_long=True,
        entry_price=100.0,
        stop_price=98.0,
        entry_time=bars["timestamp"].iloc[1],
        exit_time=bars["timestamp"].iloc[2],
        bars=bars,
    )
    assert result.n_bars == 2
    assert result.mfe_price == pytest.approx(5.0)
    assert result.mae_price == pytest.approx(3.0)
