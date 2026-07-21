"""Performance-metric primitives shared by every analysis pipeline.

Per the reproducibility contract: "Statistical claims report sample size
and uncertainty. Tiny samples cannot drive automatic live parameter
changes." Every function here returns its own sample size alongside the
point estimate (via the ``*Result`` dataclasses below), and every function
raises ``InsufficientSampleError`` on an empty input rather than returning
a silently-meaningless 0.0/NaN -- a caller must handle the empty case
explicitly, never plot or report a number that was never actually computed.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Sequence

from analysis.resampling import seeded_bootstrap_indices


class InsufficientSampleError(ValueError):
    """Raised when a metric is asked to summarize zero observations."""


MIN_N_RESAMPLES = 100  # below this a percentile bootstrap CI is not a defensible estimate


@dataclass(frozen=True)
class WinRateResult:
    win_rate: float
    wins: int
    n: int
    ci_lower: float
    ci_upper: float
    confidence: float


@dataclass(frozen=True)
class ExpectancyResult:
    expectancy: float
    n: int
    std_dev: float | None  # None when n < 2 -- spread is genuinely
                           # unestimable from a single observation, never
                           # reported as a false-precision 0.0 (Codex
                           # review finding, 2026-07-22)
    ci_lower: float | None  # bootstrap CI on the MEAN -- None when n < 2
    ci_upper: float | None
    confidence: float | None
    n_resamples: int | None
    seed: int | None


@dataclass(frozen=True)
class ProfitFactorResult:
    profit_factor: float | None  # None means "undefined" (see docstring)
    gross_profit: float
    gross_loss: float
    n_wins: int
    n_losses: int


@dataclass(frozen=True)
class BootstrapCiResult:
    point_estimate: float
    ci_lower: float
    ci_upper: float
    confidence: float
    n_resamples: int
    seed: int
    n: int  # original sample size the bootstrap was drawn from


@dataclass(frozen=True)
class MaxDrawdownResult:
    """The largest ABSOLUTE decline and the largest PERCENTAGE decline are
    tracked and reported INDEPENDENTLY, each with its own peak/trough index
    -- they are not always the same pair of points (e.g. a later, larger
    -in-dollars decline from a higher peak can have a SMALLER percentage
    than an earlier, smaller-in-dollars decline from a lower peak). A
    caller that needs "the" single drawdown figure must pick which of the
    two it means; this module does not privilege one over the other.

    ``max_drawdown_pct`` is NOT bounded to [0, 1] -- a balance that falls
    below zero (e.g. a margin-call scenario) produces a percentage greater
    than 1.0, which is correct, not an error.
    """

    max_drawdown_abs: float  # peak-to-trough decline, always >= 0
    max_drawdown_abs_peak_index: int
    max_drawdown_abs_trough_index: int
    max_drawdown_pct: float  # >= 0, NOT capped at 1.0 -- see class docstring
    max_drawdown_pct_peak_index: int
    max_drawdown_pct_trough_index: int


def wilson_confidence_interval(successes: int, n: int, confidence: float = 0.95) -> tuple[float, float]:
    """The Wilson score interval for a binomial proportion -- preferred over
    the naive normal-approximation interval because it stays within [0, 1]
    and remains reasonable at small n, both of which matter for this
    project's typically-small trade samples.

    Raises InsufficientSampleError if n == 0 (an undefined proportion, not
    a 0%-with-full-confidence one).
    """

    if n == 0:
        raise InsufficientSampleError("wilson_confidence_interval: n == 0")
    if not (0 <= successes <= n):
        raise ValueError(f"successes ({successes}) must be within [0, n={n}]")

    z = _z_score(confidence)
    phat = successes / n
    denom = 1.0 + z**2 / n
    centre = phat + z**2 / (2 * n)
    margin = z * math.sqrt((phat * (1 - phat) + z**2 / (4 * n)) / n)
    lower = (centre - margin) / denom
    upper = (centre + margin) / denom
    return max(0.0, lower), min(1.0, upper)


@dataclass(frozen=True)
class ProportionDiffResult:
    diff: float  # p_a - p_b, on the actual observed proportions
    ci_lower: float
    ci_upper: float
    likely_significant: bool  # True iff the CI excludes 0.0
    n_a: int
    n_b: int
    confidence: float


def wilson_diff_confidence_interval(
    successes_a: int, n_a: int, successes_b: int, n_b: int, confidence: float = 0.95
) -> ProportionDiffResult:
    """Newcombe-Wilson hybrid score interval for the difference of two
    INDEPENDENT binomial proportions (p_a - p_b) -- the standard
    defensible interval for comparing two win rates, unlike resampling
    the raw 0/1 outcomes with an empirical bootstrap.

    **Added, 2026-07-22 Codex review finding:** bootstrapping a binary
    0/1 outcome collapses at boundary samples -- ten all-loss vs. ten
    all-win groups always returned a degenerate ``[1.0, 1.0]`` interval,
    and two all-loss groups always returned ``[0.0, 0.0]``, neither of
    which is a defensible sampling-uncertainty statement. This method
    combines each group's own Wilson interval (already used elsewhere in
    this module) via Newcombe's method:
    ``lower = diff - sqrt((p_a-l_a)^2 + (u_b-p_b)^2)``,
    ``upper = diff + sqrt((u_a-p_a)^2 + (p_b-l_b)^2)``.

    Raises InsufficientSampleError if either n is 0.
    """

    l_a, u_a = wilson_confidence_interval(successes_a, n_a, confidence)
    l_b, u_b = wilson_confidence_interval(successes_b, n_b, confidence)
    p_a = successes_a / n_a
    p_b = successes_b / n_b
    diff = p_a - p_b

    lower = diff - math.sqrt((p_a - l_a) ** 2 + (u_b - p_b) ** 2)
    upper = diff + math.sqrt((u_a - p_a) ** 2 + (p_b - l_b) ** 2)

    return ProportionDiffResult(
        diff=diff, ci_lower=lower, ci_upper=upper,
        likely_significant=(lower > 0.0 or upper < 0.0),
        n_a=n_a, n_b=n_b, confidence=confidence,
    )


def _z_score(confidence: float) -> float:
    # Closed-form inverse-normal is not in the stdlib without scipy; this
    # project's requirements.txt already declares scipy, so use it directly
    # rather than hand-rolling an approximation.
    from scipy.stats import norm

    if not (0.0 < confidence < 1.0):
        raise ValueError(f"confidence must be in (0, 1), got {confidence}")
    return float(norm.ppf(1.0 - (1.0 - confidence) / 2.0))


def win_rate(outcomes: Sequence[bool], confidence: float = 0.95) -> WinRateResult:
    """Win rate + Wilson confidence interval over a sequence of win/loss
    booleans (True = win). Raises InsufficientSampleError if empty."""

    n = len(outcomes)
    if n == 0:
        raise InsufficientSampleError("win_rate: empty outcomes sequence")

    wins = sum(1 for o in outcomes if o)
    lower, upper = wilson_confidence_interval(wins, n, confidence)
    return WinRateResult(
        win_rate=wins / n, wins=wins, n=n, ci_lower=lower, ci_upper=upper, confidence=confidence
    )


def expectancy(
    pnl: Sequence[float], n_resamples: int = 2000, seed: int = 42, confidence: float = 0.95
) -> ExpectancyResult:
    """Mean P/L per trade, the sample standard deviation (ddof=1), and a
    bootstrap confidence interval on the MEAN itself -- the actual
    uncertainty-of-the-mean the reproducibility contract calls for, not
    just sample dispersion (Codex review finding, 2026-07-22: reporting
    dispersion alone, and reporting it as ``std_dev=0.0`` for a single
    observation, both overstate what is actually known).

    With n == 1, BOTH ``std_dev`` and the CI are ``None`` -- spread and
    the mean's uncertainty are equally unestimable from one observation,
    never reported as a false-precision zero. Raises
    InsufficientSampleError only if empty (n == 1 is a valid, if
    uncertainty-free, expectancy)."""

    n = len(pnl)
    if n == 0:
        raise InsufficientSampleError("expectancy: empty pnl sequence")

    mean = sum(pnl) / n
    if n == 1:
        return ExpectancyResult(
            expectancy=mean, n=n, std_dev=None, ci_lower=None, ci_upper=None,
            confidence=None, n_resamples=None, seed=None,
        )

    variance = sum((x - mean) ** 2 for x in pnl) / (n - 1)
    std_dev = math.sqrt(variance)
    boot = bootstrap_confidence_interval(
        pnl, statistic="mean", n_resamples=n_resamples, confidence=confidence, seed=seed
    )
    return ExpectancyResult(
        expectancy=mean, n=n, std_dev=std_dev, ci_lower=boot.ci_lower, ci_upper=boot.ci_upper,
        confidence=confidence, n_resamples=n_resamples, seed=seed,
    )


def profit_factor(pnl: Sequence[float]) -> ProfitFactorResult:
    """gross_profit / abs(gross_loss). Raises InsufficientSampleError if
    empty. If there are zero losing trades, ``profit_factor`` is returned
    as None (not float('inf')) -- an explicitly undefined value a caller
    must handle, rather than a special float that silently poisons any
    downstream arithmetic or gets misread as a real (huge) number."""

    n = len(pnl)
    if n == 0:
        raise InsufficientSampleError("profit_factor: empty pnl sequence")

    gross_profit = sum(x for x in pnl if x > 0)
    gross_loss = sum(x for x in pnl if x < 0)  # negative or zero
    n_wins = sum(1 for x in pnl if x > 0)
    n_losses = sum(1 for x in pnl if x < 0)

    if gross_loss == 0.0:
        pf = None
    else:
        pf = gross_profit / abs(gross_loss)

    return ProfitFactorResult(
        profit_factor=pf,
        gross_profit=gross_profit,
        gross_loss=gross_loss,
        n_wins=n_wins,
        n_losses=n_losses,
    )


def bootstrap_confidence_interval(
    data: Sequence[float],
    statistic: str = "mean",
    n_resamples: int = 2000,
    confidence: float = 0.95,
    seed: int = 42,
) -> BootstrapCiResult:
    """Deterministic (seeded) percentile bootstrap CI for the mean or
    median of 'data'. Per the reproducibility contract: "Randomized
    analysis uses explicit seeds and reports simulation/resample counts" --
    both the seed and n_resamples are always returned alongside the
    interval, and repeated calls with the same seed produce byte-identical
    results (see resampling.seeded_bootstrap_indices).

    Raises InsufficientSampleError if data has fewer than 2 observations
    (a bootstrap over 0 or 1 points cannot estimate any spread). Raises
    ValueError if 'confidence' is not in (0, 1), 'n_resamples' is below
    ``MIN_N_RESAMPLES``, or 'data' contains a non-finite (NaN/inf) value
    -- none of these were previously validated (Codex review finding,
    2026-07-22): confidence 0 or 1 with a single resample previously
    returned a degenerate interval instead of a visible error.
    """

    n = len(data)
    if n < 2:
        raise InsufficientSampleError(f"bootstrap_confidence_interval: need n>=2, got {n}")
    if statistic not in ("mean", "median"):
        raise ValueError(f"statistic must be 'mean' or 'median', got {statistic!r}")
    if not (0.0 < confidence < 1.0):
        raise ValueError(f"confidence must be in (0, 1), got {confidence}")
    if n_resamples < MIN_N_RESAMPLES:
        raise ValueError(f"n_resamples must be >= {MIN_N_RESAMPLES} for a defensible CI, got {n_resamples}")

    import numpy as np

    arr = np.asarray(data, dtype=float)
    if not np.all(np.isfinite(arr)):
        raise ValueError("bootstrap_confidence_interval: data contains non-finite (NaN/inf) values")
    stat_fn = np.mean if statistic == "mean" else np.median

    resample_stats = np.empty(n_resamples, dtype=float)
    for i, idx in enumerate(seeded_bootstrap_indices(n, n_resamples, seed)):
        resample_stats[i] = stat_fn(arr[idx])

    alpha = 1.0 - confidence
    lower = float(np.quantile(resample_stats, alpha / 2))
    upper = float(np.quantile(resample_stats, 1.0 - alpha / 2))
    point = float(stat_fn(arr))

    return BootstrapCiResult(
        point_estimate=point,
        ci_lower=lower,
        ci_upper=upper,
        confidence=confidence,
        n_resamples=n_resamples,
        seed=seed,
        n=n,
    )


def compute_max_drawdown(balance_curve: Sequence[float]) -> MaxDrawdownResult:
    """Maximum peak-to-trough decline over a chronologically-ordered
    balance curve (the caller's responsibility to order correctly -- this
    function does not know about timestamps; also the caller's
    responsibility to supply an actual BALANCE or EQUITY series -- this
    function has no way to tell the two apart). Tracks the running peak
    and, at every point, both the absolute and percentage decline from
    that peak; the two MAXIMA are tracked independently (see
    ``MaxDrawdownResult``'s own docstring for why they are not always the
    same point).

    Raises InsufficientSampleError if empty. Raises ValueError if the
    first value is not strictly positive -- percentage drawdown is
    undefined relative to a non-positive starting balance, so this must
    be rejected rather than silently reported as 0%. Raises ValueError if
    ANY value (not just the first) is non-finite -- a NaN later in the
    curve was previously silently skipped by every ``>`` comparison
    (NaN comparisons are always False in Python), which could hide a real
    drawdown entirely rather than surface the bad input (Codex review
    finding, 2026-07-22).
    """

    if not balance_curve:
        raise InsufficientSampleError("compute_max_drawdown: empty balance curve")
    if not all(math.isfinite(v) for v in balance_curve):
        raise ValueError("compute_max_drawdown: balance_curve contains a non-finite (NaN/inf) value")
    if balance_curve[0] <= 0:
        raise ValueError(
            f"compute_max_drawdown: the first value ({balance_curve[0]!r}) must be > 0 -- "
            "percentage drawdown is undefined relative to a non-positive starting balance"
        )

    peak = balance_curve[0]
    peak_index = 0

    max_dd_abs = 0.0
    max_dd_abs_peak_index = 0
    max_dd_abs_trough_index = 0

    max_dd_pct = 0.0
    max_dd_pct_peak_index = 0
    max_dd_pct_trough_index = 0

    for i, value in enumerate(balance_curve):
        if value > peak:
            peak = value
            peak_index = i

        dd_abs = peak - value
        dd_pct = dd_abs / peak  # peak is always > 0: starts > 0, only ever increases

        if dd_abs > max_dd_abs:
            max_dd_abs = dd_abs
            max_dd_abs_peak_index = peak_index
            max_dd_abs_trough_index = i

        if dd_pct > max_dd_pct:
            max_dd_pct = dd_pct
            max_dd_pct_peak_index = peak_index
            max_dd_pct_trough_index = i

    return MaxDrawdownResult(
        max_drawdown_abs=max_dd_abs,
        max_drawdown_abs_peak_index=max_dd_abs_peak_index,
        max_drawdown_abs_trough_index=max_dd_abs_trough_index,
        max_drawdown_pct=max_dd_pct,
        max_drawdown_pct_peak_index=max_dd_pct_peak_index,
        max_drawdown_pct_trough_index=max_dd_pct_trough_index,
    )
