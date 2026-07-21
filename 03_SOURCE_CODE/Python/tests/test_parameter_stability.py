from __future__ import annotations

import pytest

from analysis.parameter_stability import sweep_giveback_percent


# Hand-traced against ExitManager.mqh's EM_ShouldGivebackCloseV637 formula
# (effective_arm=max(0.25,arm_rr), trigger_r=peak_r*(1-pct/100), current<=trigger_r):
#
# Path B = [0.0, 2.0, 1.0, 0.5], actual_final_r = 0.5 (last value):
#   pct=40: trigger_r = 2.0*0.6 = 1.2 -> triggers at index2 (current=1.0<=1.2), r=1.0
#           r_diff = 1.0 - 0.5 = 0.5
#   pct=60: trigger_r = 2.0*0.4 = 0.8 -> triggers at index3 (current=0.5<=0.8), r=0.5
#           r_diff = 0.5 - 0.5 = 0.0
#   pct=80: trigger_r = 2.0*0.2 = 0.4 -> never triggers (0.5 > 0.4 at index3)
#           r_diff = 0.0 (no-trigger convention)
#
# Path C = [0.0, 1.25, 1.25], actual_final_r = 1.25:
#   peak reaches exactly 1.25 = effective_arm, but current==trigger_r never holds
#   for any percent > 0 (trigger_r always < 1.25 once armed) -> never triggers
#   at any of the three swept percents. r_diff = 0.0 always.
PATH_B = [0.0, 2.0, 1.0, 0.5]
PATH_C = [0.0, 1.25, 1.25]


def test_sweep_uses_full_path_set_not_just_triggered_subset():
    """Regression for a Codex review finding (2026-07-22): averaging only
    the TRIGGERED subset makes different giveback_percent settings
    incomparable (each triggers on a different subset). This test proves
    the mean is computed over the SAME full 2-path set at every percent."""

    rows = sweep_giveback_percent([PATH_B, PATH_C], [40.0, 60.0, 80.0])
    by_pct = {r.giveback_percent: r for r in rows}

    assert by_pct[40.0].n_triggered == 1
    assert by_pct[40.0].n_paths == 2
    assert by_pct[40.0].mean_r_diff_over_all_paths == pytest.approx(0.25)  # (0.5 + 0.0) / 2

    assert by_pct[60.0].n_triggered == 1
    assert by_pct[60.0].mean_r_diff_over_all_paths == pytest.approx(0.0)  # (0.0 + 0.0) / 2

    assert by_pct[80.0].n_triggered == 0
    assert by_pct[80.0].mean_r_diff_over_all_paths == pytest.approx(0.0)  # (0.0 + 0.0) / 2

    # Every row's mean is computed over n_paths == 2 -- the FULL set,
    # never a shrinking triggered-only subset.
    assert all(r.n_paths == 2 for r in rows)


def test_sweep_empty_r_paths_raises():
    with pytest.raises(ValueError):
        sweep_giveback_percent([], [40.0])


def test_sweep_empty_giveback_percents_raises():
    with pytest.raises(ValueError):
        sweep_giveback_percent([PATH_B], [])


def test_sweep_rejects_empty_path():
    with pytest.raises(ValueError):
        sweep_giveback_percent([[]], [40.0])


def test_sweep_ci_present_when_paths_vary():
    rows = sweep_giveback_percent([PATH_B, PATH_C], [40.0])
    assert rows[0].r_diff_ci_lower is not None
    assert rows[0].r_diff_ci_upper is not None
