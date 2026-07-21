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
    std_dev: float


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


def expectancy(pnl: Sequence[float]) -> ExpectancyResult:
    """Mean P/L per trade, plus the sample standard deviation (population
    std with ddof=1, i.e. the usual sample estimator) so a caller can judge
    how noisy the mean is. Raises InsufficientSampleError if empty."""

    n = len(pnl)
    if n == 0:
        raise InsufficientSampleError("expectancy: empty pnl sequence")

    mean = sum(pnl) / n
    if n == 1:
        std_dev = 0.0  # a single observation has no estimable spread
    else:
        variance = sum((x - mean) ** 2 for x in pnl) / (n - 1)
        std_dev = math.sqrt(variance)
    return ExpectancyResult(expectancy=mean, n=n, std_dev=std_dev)


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
    (a bootstrap over 0 or 1 points cannot estimate any spread).
    """

    n = len(data)
    if n < 2:
        raise InsufficientSampleError(f"bootstrap_confidence_interval: need n>=2, got {n}")
    if statistic not in ("mean", "median"):
        raise ValueError(f"statistic must be 'mean' or 'median', got {statistic!r}")

    import numpy as np

    arr = np.asarray(data, dtype=float)
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
    )
