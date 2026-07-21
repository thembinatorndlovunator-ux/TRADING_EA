from __future__ import annotations

import pytest

from analysis.metrics import (
    InsufficientSampleError,
    bootstrap_confidence_interval,
    compute_max_drawdown,
    expectancy,
    profit_factor,
    wilson_confidence_interval,
    wilson_diff_confidence_interval,
    win_rate,
)


# --- wilson_confidence_interval -------------------------------------------


def test_wilson_ci_empty_sample_raises():
    with pytest.raises(InsufficientSampleError):
        wilson_confidence_interval(0, 0)


def test_wilson_ci_rejects_successes_out_of_range():
    with pytest.raises(ValueError):
        wilson_confidence_interval(11, 10)


def test_wilson_ci_all_wins_upper_bound_is_exactly_one():
    """Algebraic property, hand-derived: when successes == n, the Wilson
    interval's upper bound collapses to EXACTLY 1.0 (the (1 + z^2/n) terms
    cancel in the numerator and denominator) -- not an approximation."""

    lower, upper = wilson_confidence_interval(10, 10, confidence=0.95)
    assert upper == pytest.approx(1.0, abs=1e-9)
    assert 0.0 < lower < 1.0


def test_wilson_ci_all_losses_lower_bound_is_exactly_zero():
    lower, upper = wilson_confidence_interval(0, 10, confidence=0.95)
    assert lower == pytest.approx(0.0, abs=1e-9)
    assert 0.0 < upper < 1.0


def test_wilson_ci_symmetric_at_50_percent():
    """phat=0.5 is the one case where the Wilson interval is symmetric
    around the point estimate -- a structural property, not a fragile
    hand-computed digit-for-digit value."""

    lower, upper = wilson_confidence_interval(5, 10, confidence=0.95)
    midpoint = (lower + upper) / 2.0
    assert midpoint == pytest.approx(0.5, abs=1e-9)
    assert lower < 0.5 < upper


def test_wilson_ci_wider_at_lower_confidence():
    lower_95, upper_95 = wilson_confidence_interval(5, 10, confidence=0.95)
    lower_80, upper_80 = wilson_confidence_interval(5, 10, confidence=0.80)
    assert (upper_95 - lower_95) > (upper_80 - lower_80)


# --- win_rate --------------------------------------------------------------


def test_win_rate_empty_raises():
    with pytest.raises(InsufficientSampleError):
        win_rate([])


def test_win_rate_basic():
    result = win_rate([True, True, False, True, False])
    assert result.n == 5
    assert result.wins == 3
    assert result.win_rate == pytest.approx(0.6)
    assert result.ci_lower < result.win_rate < result.ci_upper


# --- expectancy --------------------------------------------------------------


def test_expectancy_empty_raises():
    with pytest.raises(InsufficientSampleError):
        expectancy([])


def test_expectancy_hand_computed():
    result = expectancy([1.0, 2.0, 3.0])
    assert result.expectancy == pytest.approx(2.0)
    assert result.std_dev == pytest.approx(1.0)  # sample variance ((1+0+1)/2)=1
    assert result.n == 3
    # A bootstrap CI on the mean is now included -- real uncertainty of
    # the mean, not just sample dispersion (Codex review finding).
    assert result.ci_lower is not None
    assert result.ci_upper is not None
    assert result.ci_lower <= result.expectancy <= result.ci_upper


def test_expectancy_single_observation_has_no_estimable_uncertainty():
    """Regression for a Codex review finding (2026-07-22): reporting
    std_dev=0.0 for a single observation is FALSE PRECISION -- spread is
    genuinely unestimable from one point, not zero. Both std_dev and the
    CI must be None, not a fabricated exact value."""

    result = expectancy([5.0])
    assert result.expectancy == pytest.approx(5.0)
    assert result.std_dev is None
    assert result.ci_lower is None
    assert result.ci_upper is None


# --- profit_factor -----------------------------------------------------------


def test_profit_factor_empty_raises():
    with pytest.raises(InsufficientSampleError):
        profit_factor([])


def test_profit_factor_hand_computed():
    result = profit_factor([10.0, 10.0, -5.0])
    assert result.gross_profit == pytest.approx(20.0)
    assert result.gross_loss == pytest.approx(-5.0)
    assert result.profit_factor == pytest.approx(4.0)
    assert result.n_wins == 2
    assert result.n_losses == 1


def test_profit_factor_no_losses_is_none_not_infinity():
    result = profit_factor([10.0, 10.0])
    assert result.profit_factor is None
    assert result.gross_loss == 0.0


def test_profit_factor_no_wins():
    result = profit_factor([-5.0, -3.0])
    assert result.gross_profit == 0.0
    assert result.profit_factor == pytest.approx(0.0)


# --- bootstrap_confidence_interval -------------------------------------------


def test_bootstrap_ci_insufficient_sample_raises():
    with pytest.raises(InsufficientSampleError):
        bootstrap_confidence_interval([1.0], n_resamples=100, seed=1)
    with pytest.raises(InsufficientSampleError):
        bootstrap_confidence_interval([], n_resamples=100, seed=1)


def test_bootstrap_ci_zero_variance_data_collapses_exactly():
    """Every bootstrap resample of constant data is that same constant --
    an exact, deterministic-by-construction property, not a randomized
    coincidence."""

    result = bootstrap_confidence_interval([10.0] * 5, n_resamples=100, seed=7)
    assert result.point_estimate == pytest.approx(10.0)
    assert result.ci_lower == pytest.approx(10.0)
    assert result.ci_upper == pytest.approx(10.0)
    assert result.n_resamples == 100
    assert result.seed == 7
    assert result.n == 5


def test_bootstrap_ci_rejects_below_min_resamples():
    with pytest.raises(ValueError):
        bootstrap_confidence_interval([1.0, 2.0, 3.0], n_resamples=50, seed=1)


def test_bootstrap_ci_rejects_confidence_out_of_range():
    """Regression for a Codex review finding: confidence 0 or 1 with a
    single resample previously returned a degenerate interval instead of
    a visible error -- confidence must be validated to be in (0, 1)."""

    with pytest.raises(ValueError):
        bootstrap_confidence_interval([1.0, 2.0, 3.0], confidence=0.0, n_resamples=100, seed=1)
    with pytest.raises(ValueError):
        bootstrap_confidence_interval([1.0, 2.0, 3.0], confidence=1.0, n_resamples=100, seed=1)


def test_bootstrap_ci_rejects_non_finite_data():
    with pytest.raises(ValueError):
        bootstrap_confidence_interval([1.0, float("nan"), 3.0], n_resamples=100, seed=1)


def test_bootstrap_ci_deterministic_given_same_seed():
    data = [1.0, 2.0, 3.0, 4.0, 5.0, 100.0]  # one outlier, non-trivial spread
    result_a = bootstrap_confidence_interval(data, n_resamples=500, seed=99)
    result_b = bootstrap_confidence_interval(data, n_resamples=500, seed=99)
    assert result_a == result_b


def test_bootstrap_ci_different_seed_can_differ():
    data = [1.0, 2.0, 3.0, 4.0, 5.0, 100.0]
    result_a = bootstrap_confidence_interval(data, n_resamples=500, seed=1)
    result_b = bootstrap_confidence_interval(data, n_resamples=500, seed=2)
    # Not a hard guarantee in general, but for this skewed dataset at
    # n_resamples=500 the two seeds are overwhelmingly unlikely to collide
    # exactly -- a coincidental failure here would itself be worth
    # investigating, not just re-run away.
    assert result_a != result_b


def test_bootstrap_ci_rejects_unknown_statistic():
    with pytest.raises(ValueError):
        bootstrap_confidence_interval([1.0, 2.0, 3.0], statistic="mode", n_resamples=10, seed=1)


# --- compute_max_drawdown ----------------------------------------------------


def test_max_drawdown_empty_raises():
    with pytest.raises(InsufficientSampleError):
        compute_max_drawdown([])


def test_max_drawdown_hand_computed():
    # peak 120 (idx1) -> trough 90 (idx2): dd=30, 25%
    # peak 130 (idx3) -> trough 80 (idx4): dd=50, 38.46% <- larger on BOTH axes here
    curve = [100.0, 120.0, 90.0, 130.0, 80.0]
    result = compute_max_drawdown(curve)
    assert result.max_drawdown_abs == pytest.approx(50.0)
    assert result.max_drawdown_abs_peak_index == 3
    assert result.max_drawdown_abs_trough_index == 4
    assert result.max_drawdown_pct == pytest.approx(50.0 / 130.0)
    assert result.max_drawdown_pct_peak_index == 3
    assert result.max_drawdown_pct_trough_index == 4


def test_max_drawdown_abs_and_pct_maxima_can_be_different_points():
    """Regression for a Codex review finding (2026-07-21): the largest
    ABSOLUTE decline and the largest PERCENTAGE decline are not always the
    same pair of points. On [100, 10, 60, 200, 100]: the 100->10 fall is
    only 90 in absolute terms but a 90% decline; the later 200->100 fall
    is a larger 100 in absolute terms but only a 50% decline. The old
    (buggy) implementation selected whichever point had the larger
    ABSOLUTE decline and reported THAT point's percentage (wrongly
    reporting 50% as "the" drawdown here, hiding the real 90% one)."""

    curve = [100.0, 10.0, 60.0, 200.0, 100.0]
    result = compute_max_drawdown(curve)

    assert result.max_drawdown_abs == pytest.approx(100.0)  # the 200 -> 100 fall
    assert result.max_drawdown_abs_peak_index == 3
    assert result.max_drawdown_abs_trough_index == 4

    assert result.max_drawdown_pct == pytest.approx(0.9)  # the 100 -> 10 fall
    assert result.max_drawdown_pct_peak_index == 0
    assert result.max_drawdown_pct_trough_index == 1


def test_max_drawdown_rejects_non_positive_first_value():
    """Regression for a Codex review finding: a non-positive starting
    value made percentage drawdown silently report 0% (a special case in
    the old code) instead of being flagged as undefined."""

    with pytest.raises(ValueError):
        compute_max_drawdown([0.0, -100.0, -50.0])
    with pytest.raises(ValueError):
        compute_max_drawdown([-10.0, 5.0])


def test_max_drawdown_rejects_non_finite_value_anywhere_in_curve():
    """Regression for a Codex review finding: a NaN later in the curve
    was silently ignored (every '>' comparison against NaN is False),
    which could hide a real drawdown entirely instead of surfacing the
    bad input."""

    with pytest.raises(ValueError):
        compute_max_drawdown([100.0, 120.0, float("nan"), 80.0])


def test_max_drawdown_monotonically_rising_is_zero():
    result = compute_max_drawdown([100.0, 110.0, 120.0, 130.0])
    assert result.max_drawdown_abs == 0.0
    assert result.max_drawdown_pct == 0.0


def test_max_drawdown_single_point():
    result = compute_max_drawdown([100.0])
    assert result.max_drawdown_abs == 0.0
    assert result.max_drawdown_abs_peak_index == 0


def test_max_drawdown_pct_can_exceed_one_when_balance_goes_negative():
    """Regression for a Codex review finding: max_drawdown_pct is NOT
    bounded to [0, 1] -- a balance falling below zero (e.g. a margin-call
    scenario) is a real drawdown greater than 100%, not an error."""

    result = compute_max_drawdown([100.0, -50.0])
    assert result.max_drawdown_pct == pytest.approx(1.5)
    assert result.max_drawdown_pct_trough_index == 1


# --- wilson_diff_confidence_interval ---------------------------------------


def test_wilson_diff_ci_boundary_case_is_not_degenerate():
    """Regression for a Codex review finding (2026-07-22): bootstrapping
    raw 0/1 outcomes for a win-rate DIFFERENCE collapses to a degenerate
    [1.0, 1.0] interval for an all-loss-vs-all-win boundary sample (ten
    trades each) -- not a defensible sampling-uncertainty statement. The
    Newcombe-Wilson method must produce a real (non-degenerate) interval
    even at this exact boundary."""

    result = wilson_diff_confidence_interval(successes_a=10, n_a=10, successes_b=0, n_b=10)
    assert result.diff == pytest.approx(1.0)
    assert result.ci_upper == pytest.approx(1.0)  # correctly bounded, proportions can't exceed 1
    assert result.ci_lower < result.ci_upper  # NOT degenerate, unlike the old bootstrap approach
    assert result.likely_significant is True


def test_wilson_diff_ci_two_all_loss_groups_is_not_degenerate_zero():
    """The mirror boundary case: two all-loss groups previously collapsed
    to a bootstrap [0.0, 0.0]. By symmetry (identical n and successes on
    both sides), the Newcombe-Wilson interval is [-u, u] where u is
    wilson_confidence_interval(0, 10)'s own upper bound -- a real,
    non-degenerate interval straddling zero, not a fabricated exact 0."""

    result = wilson_diff_confidence_interval(successes_a=0, n_a=10, successes_b=0, n_b=10)
    assert result.diff == pytest.approx(0.0)
    assert result.ci_upper > 0.0
    assert result.ci_lower == pytest.approx(-result.ci_upper)
    assert result.likely_significant is False


def test_wilson_diff_ci_identical_proportions_straddles_zero():
    result = wilson_diff_confidence_interval(successes_a=5, n_a=10, successes_b=5, n_b=10)
    assert result.diff == pytest.approx(0.0)
    assert result.ci_lower < 0.0 < result.ci_upper
    assert result.likely_significant is False


def test_wilson_diff_ci_insufficient_sample_raises():
    with pytest.raises(InsufficientSampleError):
        wilson_diff_confidence_interval(successes_a=0, n_a=0, successes_b=5, n_b=10)
