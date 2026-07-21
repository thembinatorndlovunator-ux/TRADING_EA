from __future__ import annotations

import math

import pytest

from analysis.metrics import (
    InsufficientSampleError,
    bootstrap_confidence_interval,
    expectancy,
    profit_factor,
    wilson_confidence_interval,
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


def test_expectancy_single_observation_has_zero_std_dev():
    result = expectancy([5.0])
    assert result.expectancy == pytest.approx(5.0)
    assert result.std_dev == 0.0


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

    result = bootstrap_confidence_interval([10.0] * 5, n_resamples=50, seed=7)
    assert result.point_estimate == pytest.approx(10.0)
    assert result.ci_lower == pytest.approx(10.0)
    assert result.ci_upper == pytest.approx(10.0)
    assert result.n_resamples == 50
    assert result.seed == 7


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
