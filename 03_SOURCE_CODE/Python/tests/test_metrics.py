from __future__ import annotations

import pytest

from analysis.metrics import (
    InsufficientSampleError,
    bootstrap_confidence_interval,
    compute_balance_peak_giveback,
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


def test_expectancy_rejects_non_finite_value_even_at_n_equals_1():
    """Regression for a Codex review finding (2026-07-22, third round):
    the n==1 branch previously ran BEFORE any finiteness check, so
    expectancy([NaN]) silently returned a NaN expectancy instead of a
    visible error."""

    with pytest.raises(ValueError):
        expectancy([float("nan")])
    with pytest.raises(ValueError):
        expectancy([1.0, float("inf"), 3.0])


def test_expectancy_rejects_overflow_to_non_finite_from_finite_inputs():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    every individual pnl value is finite, but summing them can still
    overflow -- the exact reproduced counterexample,
    expectancy([1e308, 1e308], n_resamples=100), previously returned
    mean/std_dev=inf and ci=[nan, nan] instead of raising."""

    with pytest.raises(ValueError):
        expectancy([1e308, 1e308], n_resamples=100)


def test_expectancy_rejects_overflow_error_during_variance_calculation():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    expectancy([1e308, -1e308], n_resamples=100, seed=1) previously raised
    an UNCAUGHT OverflowError during the variance calculation (Python's
    float ``**`` raises outright rather than returning inf) -- the
    post-compute finiteness check never even ran. The mean (0.0) is
    finite here; only the squared-deviation sum overflows."""

    with pytest.raises(ValueError):
        expectancy([1e308, -1e308], n_resamples=100, seed=1)


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


def test_profit_factor_rejects_non_finite_value():
    """Regression for a Codex review finding (2026-07-22, third round):
    profit_factor([NaN]) previously returned an "undefined" (None)
    factor with zero wins/losses since NaN > 0 and NaN < 0 are both
    False in Python -- silently classifying a NaN as neither, instead of
    raising."""

    with pytest.raises(ValueError):
        profit_factor([float("nan")])


def test_profit_factor_n_recovers_true_total_including_breakeven():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    n_wins + n_losses previously silently dropped break-even (exactly
    zero P/L) observations, making the true total sample size
    unrecoverable from the result. ProfitFactorResult.n must report the
    real total (3), not n_wins + n_losses (2)."""

    result = profit_factor([10.0, -5.0, 0.0])
    assert result.n_wins == 1
    assert result.n_losses == 1
    assert result.n == 3


def test_profit_factor_rejects_overflow_to_non_finite_from_finite_inputs():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    every individual pnl value is finite, but summing them can still
    overflow -- the exact reproduced counterexample,
    profit_factor([1e308, 1e308, -1]), previously returned an inf gross
    profit and an inf factor instead of raising."""

    with pytest.raises(ValueError):
        profit_factor([1e308, 1e308, -1])


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


def test_bootstrap_ci_rejects_above_max_resamples():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    no upper bound previously existed on n_resamples anywhere in this
    project, permitting an accidental unbounded memory/time request."""

    with pytest.raises(ValueError):
        bootstrap_confidence_interval([1.0, 2.0, 3.0], n_resamples=10_000_000, seed=1)


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


def test_bootstrap_ci_rejects_overflow_to_non_finite_from_finite_inputs():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    every individual data value is finite, but the resampled statistic can
    still overflow -- bootstrap_confidence_interval([1e308, -1e308], 100,
    seed=1) previously returned a silent point estimate of 0.0 with
    ci=[NaN, NaN] instead of raising."""

    with pytest.raises(ValueError):
        bootstrap_confidence_interval([1e308, -1e308], n_resamples=100, seed=1)


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


def test_max_drawdown_rejects_overflow_to_non_finite_from_finite_inputs():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    both curve values are individually finite, but 'peak - value' can
    still overflow when they are huge and opposite-signed --
    compute_max_drawdown([1e308, -1e308]) previously returned an infinite
    absolute and percentage drawdown with no guard at all."""

    with pytest.raises(ValueError):
        compute_max_drawdown([1e308, -1e308])


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


# --- compute_balance_peak_giveback -------------------------------------------
# Regression for a Codex review finding (2026-07-22, fourth round): no
# Python code computed the master-prompt-required "Equity-peak giveback"
# metric at all (distinct from compute_max_drawdown -- a single global
# worst-case figure -- this reports arm/trigger EVENTS, matching
# TASK-002_PHASE2_SPECIFICATION.md's own guard formula).


def test_balance_peak_giveback_empty_raises():
    with pytest.raises(InsufficientSampleError):
        compute_balance_peak_giveback([])


def test_balance_peak_giveback_rejects_non_positive_first_value():
    with pytest.raises(ValueError):
        compute_balance_peak_giveback([0.0, 10.0])


def test_balance_peak_giveback_rejects_non_finite_value():
    with pytest.raises(ValueError):
        compute_balance_peak_giveback([100.0, float("nan")])


def test_balance_peak_giveback_rejects_overflow_to_non_finite_giveback_pct():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    compute_balance_peak_giveback([5e307, 1e308, -1e308], ...) previously
    produced an infinite max_giveback_pct with no guard -- every curve
    value is individually finite, but 'peak - value' can still overflow."""

    with pytest.raises(ValueError):
        compute_balance_peak_giveback([5e307, 1e308, -1e308], arm_percent=1.0, floor_percent=0.5)


def test_balance_peak_giveback_rejects_non_positive_arm_or_floor_percent():
    with pytest.raises(ValueError):
        compute_balance_peak_giveback([100.0, 110.0], arm_percent=0.0)
    with pytest.raises(ValueError):
        compute_balance_peak_giveback([100.0, 110.0], floor_percent=-1.0)


def test_balance_peak_giveback_hand_computed():
    # start=1000, arm_percent=1.0%, floor_percent=0.5%.
    # i=0 value=1000 peak=1000 -- not armed ((1000-1000)/1000=0%).
    # i=1 value=1010 peak=1010 -- arms ((1010-1000)/1000=1.0% >= 1.0%);
    #     giveback=(1010-1010)/1010=0%.
    # i=2 value=1020 peak=1020 (new peak) -- giveback=0%.
    # i=3 value=1005 peak=1020 -- giveback=(1020-1005)/1020=1.47% >= 0.5%
    #     -> FIRST trigger event.
    # i=4 value=1000 peak=1020 -- giveback=(1020-1000)/1020=1.96% (new
    #     max, still triggered, not a NEW event).
    # i=5 value=1015 peak=1020 -- giveback=(1020-1015)/1020=0.49% < 0.5%
    #     -> recovers below floor, currently_triggered resets.
    # i=6 value=1025 peak=1025 (new peak) -- giveback=0%.
    curve = [1000.0, 1010.0, 1020.0, 1005.0, 1000.0, 1015.0, 1025.0]
    result = compute_balance_peak_giveback(curve, arm_percent=1.0, floor_percent=0.5)
    assert result.armed is True
    assert result.n_trigger_events == 1
    assert result.trigger_indices == [3]
    assert result.max_giveback_pct == pytest.approx((1020.0 - 1000.0) / 1020.0)
    assert result.max_giveback_pct_index == 4


def test_balance_peak_giveback_never_arms_if_peak_never_rises_enough():
    curve = [1000.0, 1002.0, 998.0, 1001.0]  # never reaches 1% above start
    result = compute_balance_peak_giveback(curve, arm_percent=1.0, floor_percent=0.5)
    assert result.armed is False
    assert result.n_trigger_events == 0
    assert result.max_giveback_pct == 0.0


def test_balance_peak_giveback_two_separate_declines_count_as_two_events():
    # Two independent arm->trigger->recover->re-trigger cycles must be
    # counted as two separate events, not merged into one.
    curve = [
        1000.0,
        1020.0,  # arms (2% >= 1%), giveback=0%
        1005.0,  # giveback=1.47% -> trigger #1
        1020.0,  # recovers to peak, giveback=0% -> currently_triggered resets
        1040.0,  # new peak
        1025.0,  # giveback=(1040-1025)/1040=1.44% -> trigger #2
    ]
    result = compute_balance_peak_giveback(curve, arm_percent=1.0, floor_percent=0.5)
    assert result.n_trigger_events == 2
    assert result.trigger_indices == [2, 5]


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
