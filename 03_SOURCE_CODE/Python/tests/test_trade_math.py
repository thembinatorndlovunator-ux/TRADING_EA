from __future__ import annotations

import pandas as pd
import pytest

from analysis.trade_math import (
    BarAlignmentError,
    IncompleteBarCoverageError,
    ZeroDurationTradeUnmeasurableError,
    compute_mfe_mae,
    compute_r_multiple,
)


# --- compute_r_multiple (mirrors ExitManager.mqh's own TASK-030 test cases) --


def test_compute_r_multiple_long():
    assert compute_r_multiple(True, 100.0, 98.0, 101.0) == pytest.approx(0.5)


def test_compute_r_multiple_short():
    assert compute_r_multiple(False, 100.0, 102.0, 99.0) == pytest.approx(0.5)


def test_compute_r_multiple_zero_risk_distance_is_zero():
    assert compute_r_multiple(True, 100.0, 100.0, 105.0) == 0.0


def test_compute_r_multiple_negative_favors_is_negative_r():
    assert compute_r_multiple(True, 100.0, 98.0, 97.0) == pytest.approx(-1.5)


def test_compute_r_multiple_rejects_overflow_to_non_finite():
    """Regression for a Codex review finding (2026-07-22, sixth round): a
    tiny-but-positive risk_distance combined with a large-but-finite
    favor_distance previously overflowed this division silently, with no
    check anywhere in this shared primitive -- reproduced counterexamples
    in calculate_mfe_mae.py (mfe_r == inf) and analyse_giveback.py
    (actual_final_r == inf, v637_r_diff == nan) both traced back to this
    exact gap."""

    with pytest.raises(ValueError):
        compute_r_multiple(True, 100.0, 100.0 - 1e-10, 1e300)


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
    # **Re-traced, 2026-07-22 Codex review finding (third round):** the
    # window is now HALF-OPEN [entry_time, exit_time) -- the exit bar
    # (03:00) is excluded since its price action occurs entirely after
    # the trade has already exited. Bars 0-2 (00:00, 01:00, 02:00) remain
    # in the window; high_max=105 (bar1), low_min=97 (bar2) -- the same
    # mfe/mae VALUES as before this fix (both extrema happen to fall
    # inside bars 0-2 already), but n_bars drops from 4 to 3.
    bars = _bars()
    result = compute_mfe_mae(
        trade_id="t1",
        is_long=True,
        entry_price=100.0,
        stop_price=98.0,
        entry_time=bars["timestamp"].iloc[0],
        exit_time=bars["timestamp"].iloc[-1],
        bars=bars,
        expected_cadence_minutes=60.0,
    )
    assert result.mfe_price == pytest.approx(5.0)  # 105 - 100
    assert result.mae_price == pytest.approx(3.0)  # 100 - 97
    assert result.mfe_r == pytest.approx(2.5)  # 5 / 2
    assert result.mae_r == pytest.approx(-1.5)  # -3 / 2
    assert result.n_bars == 3


def test_compute_mfe_mae_exit_bar_excluded_from_window():
    """Regression for a Codex review finding (2026-07-22, third round):
    the window previously INCLUDED the exit bar (timestamp <= exit_time),
    but a bar whose OPEN equals exit_time spans price action entirely
    AFTER the trade exited -- a direct two-bar probe (entry 00:00, exit
    01:00, an extreme 01:00 bar) previously returned mfe_r=449.5, almost
    entirely POST-EXIT look-ahead. With only bar 0 (00:00) in the window
    (bar 1 at 01:00 excluded as the exit bar), mfe/mae must come ONLY
    from bar 0's own [99, 101] range, not bar 1's extreme values."""

    bars = pd.DataFrame(
        {
            "timestamp": pd.to_datetime(["2026-07-21T00:00Z", "2026-07-21T01:00Z"]),
            "high": [101.0, 999.0],  # bar 1's extreme high must NOT leak in
            "low": [99.0, 1.0],  # bar 1's extreme low must NOT leak in
        }
    )
    result = compute_mfe_mae(
        trade_id="t_exit_excl",
        is_long=True,
        entry_price=100.0,
        stop_price=98.0,
        entry_time=bars["timestamp"].iloc[0],
        exit_time=bars["timestamp"].iloc[1],
        bars=bars,
        expected_cadence_minutes=60.0,
    )
    assert result.n_bars == 1
    assert result.mfe_price == pytest.approx(1.0)  # 101 - 100, bar 0 only
    assert result.mae_price == pytest.approx(1.0)  # 100 - 99, bar 0 only


def test_compute_mfe_mae_same_bar_trade_is_unmeasurable():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    entry_time == exit_time (a zero-duration trade at the bar-open
    instant) previously used that single aligned bar's FULL high/low
    range -- but that range spans the bar's entire
    [timestamp, next_bar_open) period, almost all of which occurs AFTER
    the trade already exited. A direct probe with one extreme bar
    (high=999, low=0) reproduced mfe_r=449.5, almost entirely post-exit
    contamination. This must now be rejected as unmeasurable at bar
    resolution, not approximated."""

    bars = pd.DataFrame(
        {
            "timestamp": pd.to_datetime(["2026-07-21T00:00:00Z"]),
            "high": [999.0],
            "low": [0.0],
        }
    )
    with pytest.raises(ZeroDurationTradeUnmeasurableError):
        compute_mfe_mae(
            trade_id="t_same_bar",
            is_long=True,
            entry_price=100.0,
            stop_price=98.0,
            entry_time=bars["timestamp"].iloc[0],
            exit_time=bars["timestamp"].iloc[0],
            bars=bars,
            expected_cadence_minutes=60.0,
        )


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
        expected_cadence_minutes=60.0,
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
            expected_cadence_minutes=60.0,
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
            expected_cadence_minutes=60.0,
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
            expected_cadence_minutes=60.0,
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
            expected_cadence_minutes=60.0,
        )


def test_compute_mfe_mae_rejects_incomplete_bar_coverage():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    a trade from 00:00 to 03:00 with bars only at 00:00 and 03:00 (the
    exit bar itself excluded by the half-open window) previously
    completed successfully and reported ONE measured bar, silently
    ignoring the missing 01:00 and 02:00 exposure -- endpoint alignment
    was enforced, but expected cadence/coverage was not. Must now raise
    IncompleteBarCoverageError instead of a spuriously "successful"
    partial result."""

    sparse_bars = pd.DataFrame(
        {
            "timestamp": pd.to_datetime(["2026-07-21T00:00Z", "2026-07-21T03:00Z"]),
            "high": [101.0, 999.0],  # extreme value at the (excluded) exit bar
            "low": [99.0, 0.0],
        }
    )
    with pytest.raises(IncompleteBarCoverageError):
        compute_mfe_mae(
            trade_id="t-sparse",
            is_long=True,
            entry_price=100.0,
            stop_price=98.0,
            entry_time=pd.Timestamp("2026-07-21T00:00Z"),
            exit_time=pd.Timestamp("2026-07-21T03:00Z"),
            bars=sparse_bars,
            expected_cadence_minutes=60.0,
        )


def test_compute_mfe_mae_complete_coverage_at_declared_cadence_succeeds():
    # Same window as the sparse-coverage test above, but with all 4 real
    # hourly bars present -- must succeed, proving the fix distinguishes
    # genuinely complete coverage from a gap.
    result = compute_mfe_mae(
        trade_id="t-complete",
        is_long=True,
        entry_price=100.0,
        stop_price=98.0,
        entry_time=pd.Timestamp("2026-07-21T00:00Z"),
        exit_time=pd.Timestamp("2026-07-21T03:00Z"),
        bars=_bars(),
        expected_cadence_minutes=60.0,
    )
    assert result.n_bars == 3  # 00:00, 01:00, 02:00 -- exit bar excluded


def test_compute_mfe_mae_rejects_non_finite_or_non_positive_cadence():
    bars = _bars()
    with pytest.raises(ValueError):
        compute_mfe_mae(
            trade_id="t-bad-cadence",
            is_long=True,
            entry_price=100.0,
            stop_price=98.0,
            entry_time=bars["timestamp"].iloc[0],
            exit_time=bars["timestamp"].iloc[1],
            bars=bars,
            expected_cadence_minutes=0.0,
        )
    with pytest.raises(ValueError):
        compute_mfe_mae(
            trade_id="t-bad-cadence-2",
            is_long=True,
            entry_price=100.0,
            stop_price=98.0,
            entry_time=bars["timestamp"].iloc[0],
            exit_time=bars["timestamp"].iloc[1],
            bars=bars,
            expected_cadence_minutes=float("nan"),
        )


def test_compute_mfe_mae_window_is_half_open_partial_bar_subset():
    # **Re-traced, 2026-07-22 Codex review finding (third round):** entry
    # at bar1 (01:00), exit at bar3 (03:00) -- the half-open window
    # [01:00, 03:00) includes bars 1-2 (01:00, 02:00) and excludes bar 3
    # (the exit bar). high max 105 (bar1), low min 97 (bar2).
    bars = _bars()
    result = compute_mfe_mae(
        trade_id="t5",
        is_long=True,
        entry_price=100.0,
        stop_price=98.0,
        entry_time=bars["timestamp"].iloc[1],
        exit_time=bars["timestamp"].iloc[3],
        bars=bars,
        expected_cadence_minutes=60.0,
    )
    assert result.n_bars == 2
    assert result.mfe_price == pytest.approx(5.0)
    assert result.mae_price == pytest.approx(3.0)
