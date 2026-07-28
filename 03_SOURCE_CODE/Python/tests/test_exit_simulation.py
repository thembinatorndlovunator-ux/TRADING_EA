from __future__ import annotations

import pytest

from analysis.exit_simulation import (
    should_giveback_close_v637,
    should_giveback_close_v811,
    simulate_giveback_path,
)

# --- direct ports: same hand-verified cases as ExitManager.mqh's own
# --- Test_ExitManager.mq5 (TASK-030, tests 13-14) -- kept in lockstep so a
# --- future divergence between the Python port and the MQL5 source shows
# --- up as a failing test here, not silently.


def test_v637_matches_mql5_close_case():
    assert should_giveback_close_v637(0.7, 2.0, 1.25, 60.0, 0.05) is True


def test_v637_matches_mql5_no_close_case():
    assert should_giveback_close_v637(0.9, 2.0, 1.25, 60.0, 0.05) is False


def test_v637_matches_mql5_not_armed_case():
    assert should_giveback_close_v637(0.1, 1.0, 1.25, 60.0, 0.05) is False


def test_v637_matches_mql5_floor_override_case():
    assert should_giveback_close_v637(0.9, 2.0, 1.25, 60.0, 1.0) is True


def test_v811_matches_mql5_close_case():
    assert should_giveback_close_v811(0.1, 1.0, 0.3, 0.1) is True


def test_v811_matches_mql5_no_close_case():
    assert should_giveback_close_v811(0.15, 1.0, 0.3, 0.1) is False


def test_v811_matches_mql5_not_armed_case():
    assert should_giveback_close_v811(0.05, 0.2, 0.3, 0.1) is False


# --- simulate_giveback_path -------------------------------------------------


def test_simulate_empty_path_raises():
    with pytest.raises(ValueError):
        simulate_giveback_path([], "v637")


def test_simulate_unknown_model_raises():
    with pytest.raises(ValueError):
        simulate_giveback_path([0.5, 1.0], "made_up_model")


def test_simulate_v637_never_triggers_returns_none():
    # Monotonically rising R: arms only at the last bar (peak 1.5 >= 1.25),
    # and that same bar sets a new peak, so current_r == peak_r there --
    # always above trigger_r (peak_r * fraction < peak_r) -- never closes.
    assert simulate_giveback_path([0.1, 0.5, 1.0, 1.5], "v637") is None


def test_simulate_v637_triggers_at_expected_bar():
    # peak reaches 2.0 at index 2 (armed, trigger=0.8); index 3 drops to
    # 0.7 <= 0.8 -> triggers there.
    result = simulate_giveback_path([0.5, 1.0, 2.0, 0.7], "v637")
    assert result == (3, pytest.approx(0.7))


def test_simulate_v811_triggers_at_expected_bar():
    # peak reaches 1.0 at index 1 (armed, effective floor 0.1); index 3
    # drops to 0.1 <= 0.1 -> triggers there.
    result = simulate_giveback_path([0.5, 1.0, 0.6, 0.1], "v811")
    assert result == (3, pytest.approx(0.1))


def test_simulate_v811_never_armed_returns_none():
    assert simulate_giveback_path([0.1, 0.2, 0.1, 0.05], "v811") is None


def test_simulate_custom_params_override_defaults():
    # With a much tighter arm threshold, a lower peak triggers where the
    # default parameters would not have armed yet.
    result = simulate_giveback_path([0.5, 0.1], "v637", arm_rr=0.4, giveback_percent=50.0)
    assert result is not None
    assert result[0] == 1
